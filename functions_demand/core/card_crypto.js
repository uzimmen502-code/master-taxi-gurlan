'use strict';

/**
 * ULGURJI SOTUVCHI KARTASI — Cloud KMS shifrlash (ega qarori, 2026-10-31).
 *
 * Karta raqami va egasi ismi `wholesale_sellers/{tel}/private/payout` da OCHIQ MATN
 * sifatida saqlanmaydi: Cloud KMS simmetrik kaliti (ENCRYPT_DECRYPT) bilan shifrlanadi.
 *
 *   Kalit:    env `WHOLESALE_CARD_KMS_KEY`, default
 *             projects/master-taxi-gurlan/locations/europe-west1/keyRings/ava-secrets/cryptoKeys/wholesale-seller-card
 *             (kalitni EGA yaratadi; funksiyalar `master-taxi-gurlan@appspot.gserviceaccount.com`
 *             nomidan ishlaydi — faqat SHU kalitga `roles/cloudkms.cryptoKeyEncrypterDecrypter`).
 *   REST:     POST https://cloudkms.googleapis.com/v1/{kalit}:encrypt | :decrypt
 *             (plaintext/ciphertext/additionalAuthenticatedData — base64). Yangi paket YO'Q:
 *             token — `google-auth-library` (firebase-admin orqali o'rnatilgan, lock: 8.9.0),
 *             HTTP — Node global `fetch`.
 *   Saqlash:  `kms:v1:<base64 ciphertext>`. Kalit aylanishi (rotation) — KMS o'zi: decrypt
 *             KALIT nomi bilan chaqiriladi, versiya ciphertext ichida.
 *   AAD:      `wholesale_seller_card|v1|{kanon tel}|{maydon}` (base64). Ciphertext boshqa
 *             sotuvchiga (yoki o'sha hujjatning boshqa maydoniga) ko'chirilsa — KMS RAD etadi.
 *             Tel KANON shaklda (998XXXXXXXXX): 9/12 xonali hujjat ID'si bir xil AAD beradi.
 *
 * Xatolar — `CardCryptoError` (`code`, `transient`, `httpStatus`, `kmsStatus`). Bu modul
 * HECH NARSANI LOG QILMAYDI; xato matnida ochiq matn ham, ciphertext ham, KMS javob matni
 * ham yo'q (faqat HTTP holati + KMS status kodi). Chaqiruvchi faqat last4 ni log qiladi.
 *
 * Testda HTTP va token qatlami almashtiriladi: `createCardCrypto({ fetchImpl, getAccessToken })`.
 */

const DEFAULT_KEY_NAME = 'projects/master-taxi-gurlan/locations/europe-west1/keyRings/ava-secrets/cryptoKeys/wholesale-seller-card';
const KEY_ENV = 'WHOLESALE_CARD_KMS_KEY';
const KMS_ENDPOINT = 'https://cloudkms.googleapis.com/v1';
const SCOPE = 'https://www.googleapis.com/auth/cloud-platform';
const PREFIX = 'kms:v1:';
const ENC_VERSION = 1;
const DEFAULT_TIMEOUT_MS = 5000;
const PLAINTEXT_MAX = 256;
const STORED_MAX = 4096;
const FIELDS = Object.freeze(['cardNumber', 'holderName']);
const KEY_NAME_RE = /^projects\/[a-z][a-z0-9-]{4,61}[a-z0-9]\/locations\/[a-z0-9-]+\/keyRings\/[A-Za-z0-9_-]{1,63}\/cryptoKeys\/[A-Za-z0-9_-]{1,63}$/;
const B64_RE = /^[A-Za-z0-9+/]+={0,2}$/;

class CardCryptoError extends Error {
  constructor(code, message, { transient = false, httpStatus = null, kmsStatus = null } = {}) {
    super(message);
    this.name = 'CardCryptoError';
    this.code = code;
    this.transient = transient;
    this.httpStatus = httpStatus;
    this.kmsStatus = kmsStatus;
  }
}

const isCardCryptoError = (e) => !!e && e.name === 'CardCryptoError' && typeof e.code === 'string';

/** Kanon tel (998XXXXXXXXX) — `core/ids.toCanonicalId` bilan bir xil (aylanma require yo'q). */
function canonicalPhone(v) {
  const d = String(v == null ? '' : v).replace(/\D/g, '');
  if (d.length === 9) return `998${d}`;
  if (d.length === 12 && d.startsWith('998')) return d;
  return '';
}

/** AAD satri: sotuvchi + maydon. Noto'g'ri kontekst — xato (fail closed). */
function aadFor(ctx) {
  const c = ctx || {};
  const phone = canonicalPhone(c.sellerId);
  if (!phone) throw new CardCryptoError('CARD_CRYPTO_CONTEXT', 'Sotuvchi ID yaroqsiz');
  if (!FIELDS.includes(c.field)) throw new CardCryptoError('CARD_CRYPTO_CONTEXT', 'Maydon yaroqsiz');
  return `wholesale_seller_card|v${ENC_VERSION}|${phone}|${c.field}`;
}

const isEncryptedValue = (v) => typeof v === 'string' && v.startsWith(PREFIX) && v.length > PREFIX.length && v.length <= STORED_MAX
  && B64_RE.test(v.slice(PREFIX.length));

function resolveKeyName(explicit) {
  const k = String(explicit || process.env[KEY_ENV] || DEFAULT_KEY_NAME).trim();
  if (!KEY_NAME_RE.test(k)) throw new CardCryptoError('KMS_KEY_NAME_INVALID', 'KMS kalit nomi yaroqsiz');
  return k;
}

/** Default token: GoogleAuth (ADC; Cloud Functions'da — metadata server, appspot SA). Kechiktirilgan. */
function defaultTokenProvider({ keyFile } = {}) {
  let auth = null;
  return async () => {
    if (!auth) {
      // eslint-disable-next-line global-require
      const { GoogleAuth } = require('google-auth-library');
      auth = new GoogleAuth({ scopes: [SCOPE], ...(keyFile ? { keyFile } : {}) });
    }
    return auth.getAccessToken(); // kutubxona tokenni muddati tugaguncha keshlaydi
  };
}

/** `promise` ni `ms` ichida tugatadi, aks holda `onTimeout()` xatosi. Taymer har doim tozalanadi. */
function withTimeout(promise, ms, onTimeout) {
  let t = null;
  const timer = new Promise((_, reject) => { t = setTimeout(() => reject(onTimeout()), ms); });
  return Promise.race([promise, timer]).finally(() => clearTimeout(t));
}

function httpError(status, kmsStatus) {
  const o = { httpStatus: status, kmsStatus };
  if (status === 401 || status === 403) return new CardCryptoError('KMS_PERMISSION_DENIED', `KMS ruxsat bermadi (${status})`, o);
  if (status === 404) return new CardCryptoError('KMS_KEY_NOT_FOUND', 'KMS kaliti topilmadi (404)', o);
  if (status === 400 && kmsStatus === 'FAILED_PRECONDITION') {
    return new CardCryptoError('KMS_FAILED_PRECONDITION', 'KMS kalit versiyasi yaroqsiz (400)', o);
  }
  if (status === 400) return new CardCryptoError('KMS_INVALID_ARGUMENT', 'KMS so\'rovni rad etdi (400)', o);
  if (status === 429 || status >= 500) {
    return new CardCryptoError('KMS_UNAVAILABLE', `KMS vaqtincha ishlamayapti (${status})`, { ...o, transient: true });
  }
  return new CardCryptoError('KMS_HTTP_ERROR', `KMS javobi kutilmagan (${status})`, o);
}

/**
 * @param {object} [opts]
 * @param {string} [opts.keyName]        default: env WHOLESALE_CARD_KMS_KEY → DEFAULT_KEY_NAME
 * @param {Function} [opts.fetchImpl]    (url, init) → Response-ga o'xshash {ok,status,json()}; default global fetch
 * @param {Function} [opts.getAccessToken] () → Promise<string>; default GoogleAuth (cloud-platform)
 * @param {number} [opts.timeoutMs]      har bir token/HTTP chaqiruvi uchun; default 5000
 * @param {string} [opts.keyFile]        ixtiyoriy service-account JSON (faqat migratsiya vositasi uchun)
 */
function createCardCrypto(opts = {}) {
  // Kalit nomi xatosi modul yuklanishida EMAS, chaqiruvda tashlanadi: noto'g'ri env butun
  // demand codebase'ni (deploy discovery / cold start) yiqitmasin — faqat karta amallari yopiladi.
  let keyName = null;
  let keyError = null;
  try { keyName = resolveKeyName(opts.keyName); } catch (e) { keyError = e; }
  const timeoutMs = Number.isInteger(opts.timeoutMs) && opts.timeoutMs > 0 ? opts.timeoutMs : DEFAULT_TIMEOUT_MS;
  const fetchImpl = opts.fetchImpl || ((...a) => globalThis.fetch(...a));
  const getAccessToken = opts.getAccessToken || defaultTokenProvider({ keyFile: opts.keyFile });

  async function token() {
    let tok;
    try {
      tok = await withTimeout(Promise.resolve().then(() => getAccessToken()), timeoutMs,
        () => new CardCryptoError('KMS_TIMEOUT', 'KMS token vaqti tugadi', { transient: true }));
    } catch (e) {
      if (isCardCryptoError(e)) throw e;
      throw new CardCryptoError('KMS_AUTH_FAILED', 'KMS uchun token olinmadi', { transient: true });
    }
    if (typeof tok !== 'string' || !tok) throw new CardCryptoError('KMS_AUTH_FAILED', 'KMS uchun token olinmadi', { transient: true });
    return tok;
  }

  async function call(op, body) {
    if (keyError) throw keyError;
    const tok = await token();
    const ac = typeof AbortController === 'function' ? new AbortController() : null;
    let res;
    try {
      res = await withTimeout(
        Promise.resolve().then(() => fetchImpl(`${KMS_ENDPOINT}/${keyName}:${op}`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${tok}`, 'Content-Type': 'application/json; charset=utf-8' },
          body: JSON.stringify(body),
          ...(ac ? { signal: ac.signal } : {}),
        })),
        timeoutMs,
        () => {
          if (ac) ac.abort();
          return new CardCryptoError('KMS_TIMEOUT', `KMS ${op} vaqti tugadi`, { transient: true });
        },
      );
    } catch (e) {
      if (isCardCryptoError(e)) throw e;
      throw new CardCryptoError('KMS_NETWORK', `KMS ${op}: tarmoq xatosi`, { transient: true });
    }
    let json = null;
    try { json = await res.json(); } catch (_) { json = null; }
    if (!res.ok) {
      const kmsStatus = json && json.error && typeof json.error.status === 'string' ? json.error.status : null;
      throw httpError(Number(res.status) || 0, kmsStatus);
    }
    return json || {};
  }

  /**
   * Ochiq matn → `kms:v1:<base64>`.
   * @param {string} plain
   * @param {{sellerId: string, field: 'cardNumber'|'holderName'}} ctx
   */
  async function encryptCard(plain, ctx) {
    if (typeof plain !== 'string' || !plain || plain.length > PLAINTEXT_MAX) {
      throw new CardCryptoError('CARD_CRYPTO_INPUT', 'Shifrlanadigan qiymat yaroqsiz');
    }
    const aad = aadFor(ctx);
    const out = await call('encrypt', {
      plaintext: Buffer.from(plain, 'utf8').toString('base64'),
      additionalAuthenticatedData: Buffer.from(aad, 'utf8').toString('base64'),
    });
    const ct = out.ciphertext;
    if (typeof ct !== 'string' || !ct || !B64_RE.test(ct)) throw new CardCryptoError('KMS_BAD_RESPONSE', 'KMS javobida ciphertext yo\'q');
    const stored = `${PREFIX}${ct}`;
    if (stored.length > STORED_MAX) throw new CardCryptoError('KMS_BAD_RESPONSE', 'KMS ciphertext juda uzun');
    return stored;
  }

  /**
   * `kms:v1:<base64>` → ochiq matn. AAD mos kelmasa / ciphertext buzilgan — KMS_INVALID_ARGUMENT.
   * @param {string} stored
   * @param {{sellerId: string, field: 'cardNumber'|'holderName'}} ctx
   */
  async function decryptCard(stored, ctx) {
    if (!isEncryptedValue(stored)) throw new CardCryptoError('CARD_CIPHERTEXT_FORMAT', 'Shifrlangan qiymat shakli noto\'g\'ri');
    const aad = aadFor(ctx);
    const out = await call('decrypt', {
      ciphertext: stored.slice(PREFIX.length),
      additionalAuthenticatedData: Buffer.from(aad, 'utf8').toString('base64'),
    });
    if (typeof out.plaintext !== 'string' || !B64_RE.test(out.plaintext)) {
      throw new CardCryptoError('KMS_BAD_RESPONSE', 'KMS javobida plaintext yo\'q');
    }
    const plain = Buffer.from(out.plaintext, 'base64').toString('utf8');
    if (!plain || plain.length > PLAINTEXT_MAX) throw new CardCryptoError('KMS_BAD_RESPONSE', 'KMS plaintext yaroqsiz');
    return plain;
  }

  return { keyName, encryptCard, decryptCard };
}

module.exports = {
  DEFAULT_KEY_NAME,
  KEY_ENV,
  KMS_ENDPOINT,
  PREFIX,
  ENC_VERSION,
  DEFAULT_TIMEOUT_MS,
  FIELDS,
  CardCryptoError,
  isCardCryptoError,
  isEncryptedValue,
  aadFor,
  resolveKeyName,
  createCardCrypto,
};
