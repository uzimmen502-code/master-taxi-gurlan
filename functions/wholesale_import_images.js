/**
 * Улгуржи Excel юклаш — расмни URL'дан олиш (SSRF ҳимояси) ва қайта кодлаш (sharp, Apache-2.0).
 *
 * SSRF: фақат http/https, 80/443, логин-паролсиз; хост номи DNS орқали ечилади ва ХАР БИР манзил
 * текширилади (ички/махсус тармоқлар, localhost, metadata 169.254.169.254 — рад). Уланиш айнан
 * текширилган IP'га (`lookup` алмаштирилади) — DNS rebinding йўқ. Йўналтириш (redirect) ≤ 3,
 * ҳар бирида қайта текширув. Вақт ≤ 10 с, ҳажм ≤ 10 МБ (оқим узилади).
 * Қайта кодлаш: EXIF бўйича буриш, ≤ 1600 px, JPEG 80, метамаълумот ўчирилади.
 */
'use strict';

const dns = require('dns');
const net = require('net');
const http = require('http');
const https = require('https');

const IMG = Object.freeze({
  timeoutMs: 10000,
  maxBytes: 10 * 1024 * 1024,
  maxRedirects: 3,
  maxSidePx: 1600,
  maxInputPixels: 40 * 1000 * 1000,
  jpegQuality: 80,
});

const BLOCKED_HOSTS = new Set(['localhost', 'metadata', 'metadata.google.internal', 'metadata.goog']);

function ipv4ToInt(ip) {
  return ip.split('.').reduce((a, o) => (a * 256) + Number(o), 0);
}
const V4_BLOCKS = [
  ['0.0.0.0', 8], ['10.0.0.0', 8], ['100.64.0.0', 10], ['127.0.0.0', 8], ['169.254.0.0', 16],
  ['172.16.0.0', 12], ['192.0.0.0', 24], ['192.0.2.0', 24], ['192.88.99.0', 24], ['192.168.0.0', 16],
  ['198.18.0.0', 15], ['198.51.100.0', 24], ['203.0.113.0', 24], ['224.0.0.0', 4], ['240.0.0.0', 4],
].map(([base, bits]) => [ipv4ToInt(base), bits]);

/** Ички/махсус манзилми (IPv4 ва IPv6). Тушунарсиз шакл — рад (true). */
function isPrivateIp(ip) {
  const fam = net.isIP(ip);
  if (fam === 4) {
    const n = ipv4ToInt(ip);
    return V4_BLOCKS.some(([base, bits]) => {
      const size = 2 ** (32 - bits);
      return n >= base && n < base + size;
    });
  }
  if (fam === 6) {
    const s = ip.toLowerCase();
    if (s === '::' || s === '::1') return true;
    const mapped = s.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
    if (mapped) return isPrivateIp(mapped[1]);
    if (/^::ffff:/.test(s)) return true;
    const first = parseInt(s.split(':')[0] || '0', 16);
    if ((first & 0xfe00) === 0xfc00) return true; // fc00::/7 ULA
    if ((first & 0xffc0) === 0xfe80) return true; // fe80::/10 link-local
    if ((first & 0xff00) === 0xff00) return true; // multicast
    if (s.startsWith('64:ff9b:') || s.startsWith('2001:db8') || s.startsWith('2002:')) return true;
    return false;
  }
  return true;
}

class ImageError extends Error {
  constructor(code) { super(code); this.code = code; }
}

/** Хост → текширилган манзиллар (ёки ImageError). `resolve` — тест учун алмаштирилади. */
async function vetHost(hostname, resolve) {
  const host = String(hostname || '').toLowerCase().replace(/^\[|\]$/g, '').replace(/\.$/, '');
  if (!host || BLOCKED_HOSTS.has(host) || host.endsWith('.localhost') || host.endsWith('.internal')) {
    throw new ImageError('IMAGE_BLOCKED_HOST');
  }
  let addrs;
  if (net.isIP(host)) {
    addrs = [{ address: host, family: net.isIP(host) }];
  } else {
    try {
      addrs = await resolve(host);
    } catch (_) {
      throw new ImageError('IMAGE_FETCH_FAILED');
    }
  }
  if (!Array.isArray(addrs) || addrs.length === 0) throw new ImageError('IMAGE_FETCH_FAILED');
  if (addrs.some((a) => isPrivateIp(a.address))) throw new ImageError('IMAGE_BLOCKED_HOST');
  return addrs;
}

const defaultResolve = (host) => dns.promises.lookup(host, { all: true, verbatim: true });

function checkUrl(raw) {
  let u;
  try { u = new URL(String(raw)); } catch (_) { throw new ImageError('IMAGE_URL_INVALID'); }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') throw new ImageError('IMAGE_URL_INVALID');
  if (u.username || u.password) throw new ImageError('IMAGE_URL_INVALID');
  if (u.port && u.port !== '80' && u.port !== '443') throw new ImageError('IMAGE_URL_INVALID');
  return u;
}

/** Битта GET (йўналтиришсиз): { status, location, contentType, body }. */
function getOnce(u, addr, opts) {
  return new Promise((resolve, reject) => {
    const mod = u.protocol === 'https:' ? https : http;
    const req = mod.request({
      protocol: u.protocol,
      hostname: u.hostname.replace(/^\[|\]$/g, ''),
      port: u.port || (u.protocol === 'https:' ? 443 : 80),
      path: `${u.pathname}${u.search}`,
      method: 'GET',
      headers: { 'User-Agent': 'AVA-ImageImport/1.0', Accept: 'image/*' },
      // Уланиш фақат текширилган IP'га (DNS rebinding йўқ); TLS SNI/сертификат — асл хост номи.
      lookup: (_h, o, cb) => (o && o.all ? cb(null, [addr]) : cb(null, addr.address, addr.family)),
      timeout: opts.timeoutMs,
    }, (res) => {
      const status = res.statusCode || 0;
      if (status >= 300 && status < 400) {
        res.resume();
        resolve({ status, location: res.headers.location || '' });
        return;
      }
      if (status !== 200) { res.resume(); reject(new ImageError('IMAGE_FETCH_FAILED')); return; }
      const len = Number(res.headers['content-length'] || 0);
      if (len > opts.maxBytes) { res.destroy(); reject(new ImageError('IMAGE_TOO_LARGE')); return; }
      const chunks = [];
      let size = 0;
      res.on('data', (c) => {
        size += c.length;
        if (size > opts.maxBytes) { res.destroy(); reject(new ImageError('IMAGE_TOO_LARGE')); return; }
        chunks.push(c);
      });
      res.on('end', () => resolve({ status, contentType: String(res.headers['content-type'] || ''), body: Buffer.concat(chunks) }));
      res.on('error', () => reject(new ImageError('IMAGE_FETCH_FAILED')));
    });
    req.on('timeout', () => { req.destroy(); reject(new ImageError('IMAGE_TIMEOUT')); });
    req.on('error', (e) => reject(e instanceof ImageError ? e : new ImageError('IMAGE_FETCH_FAILED')));
    req.end();
  });
}

/** URL → хом байтлар (SSRF ҳимояли). `deps.resolve` — тест учун. */
async function fetchImageBytes(rawUrl, deps = {}) {
  const resolve = deps.resolve || defaultResolve;
  const opts = { timeoutMs: deps.timeoutMs || IMG.timeoutMs, maxBytes: deps.maxBytes || IMG.maxBytes };
  let u = checkUrl(rawUrl);
  const deadline = Date.now() + opts.timeoutMs;
  for (let hop = 0; hop <= IMG.maxRedirects; hop += 1) {
    const addrs = await vetHost(u.hostname, resolve);
    const remaining = deadline - Date.now();
    if (remaining <= 0) throw new ImageError('IMAGE_TIMEOUT');
    const r = await getOnce(u, addrs[0], { ...opts, timeoutMs: remaining });
    if (r.status === 200) {
      const ct = r.contentType.toLowerCase();
      if (ct && !ct.startsWith('image/') && !ct.startsWith('application/octet-stream')) {
        throw new ImageError('IMAGE_NOT_IMAGE');
      }
      return r.body;
    }
    if (!r.location) throw new ImageError('IMAGE_FETCH_FAILED');
    try { u = checkUrl(new URL(r.location, u).toString()); } catch (e) { throw e instanceof ImageError ? e : new ImageError('IMAGE_FETCH_FAILED'); }
  }
  throw new ImageError('IMAGE_FETCH_FAILED');
}

/** Хом байтлар → JPEG (буриш, ≤1600 px, метамаълумотсиз). Расм бўлмаса — IMAGE_NOT_IMAGE. */
async function reencodeImage(buf) {
  const sharp = require('sharp');
  try {
    const img = sharp(buf, { limitInputPixels: IMG.maxInputPixels, failOn: 'error' });
    const meta = await img.metadata();
    if (!meta || !meta.width || !meta.height) throw new ImageError('IMAGE_NOT_IMAGE');
    return await img
      .rotate()
      .resize({ width: IMG.maxSidePx, height: IMG.maxSidePx, fit: 'inside', withoutEnlargement: true })
      .flatten({ background: '#ffffff' })
      .jpeg({ quality: IMG.jpegQuality, mozjpeg: true })
      .toBuffer();
  } catch (e) {
    if (e instanceof ImageError) throw e;
    throw new ImageError('IMAGE_NOT_IMAGE');
  }
}

/** URL → тайёр JPEG байтлар. */
async function fetchAndProcess(url, deps = {}) {
  const raw = await fetchImageBytes(url, deps);
  return reencodeImage(raw);
}

module.exports = { IMG, ImageError, isPrivateIp, vetHost, checkUrl, fetchImageBytes, reencodeImage, fetchAndProcess };
