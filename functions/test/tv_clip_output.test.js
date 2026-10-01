/**
 * TV клип чиқиши — `functions/tv_clip_output.js`.
 *
 * Иккита асосий кафолат:
 *   1. ФЛАГ ЎЧИҚ → ҳеч нарса ўзгармайди. `FirebaseStorageOutput` айнан
 *      олдинги йўл (`tv_clip_variants/…`, `tv_clip_hls/…`) ва token'ли
 *      `firebasestorage.googleapis.com` URL'ини беради.
 *   2. ФЛАГ ЁҚИҚ → объект R2'га `processed/{clipId}/{runId}/…` йўлида,
 *      тўғри Content-Type ва `immutable` Cache-Control билан ёзилади,
 *      URL эса `https://video.ava-uz.com/processed/…` бўлади.
 *
 * Шунингдек: R2 ёзуви йиқилса хато ЮҚОРИГА ОТИЛАДИ (чақирувчи клипни
 * `error` қилади) ва Firebase'га fallback БЎЛМАЙДИ.
 *
 * Soф: на Storage, на R2, на `@aws-sdk/client-s3` керак (сохта мижоз).
 *
 * Ишлатиш (functions/ ичидан):
 *   npm run test:tv-clip-output
 */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  contentTypeFor,
  r2OwnerAllowed,
  resolveClipBackend,
  purgeCdnUrls,
  FirebaseStorageOutput,
  R2Output,
  TV_CLIP_CACHE_CONTROL,
} = require('../tv_clip_output');

const results = [];
function check(name, pass) {
  results.push({name, pass});
  console.log(`${pass ? '  ok  ' : ' FAIL '} ${name}`);
}

const CLIP = 'clipA';
const RUN = 'r1';

// Ҳақиқий локал файл — `upload` уни ўқийди (ҳажм/стрим учун).
const TMP = path.join(os.tmpdir(), 'ava_r2_test_asset.bin');
fs.writeFileSync(TMP, Buffer.alloc(1234, 7));

// ── Сохта Firebase bucket ───────────────────────────────────────────
function fakeBucket() {
  const uploads = [];
  const deleted = [];
  let listing = [];
  return {
    uploads, deleted,
    setListing(names) {
      listing = names;
    },
    async upload(localPath, opts) {
      uploads.push({localPath, opts});
    },
    async getFiles({prefix}) {
      return [listing.filter((n) => n.startsWith(prefix)).map((name) => ({
        name,
        delete: async () => {
          deleted.push(name);
        },
      }))];
    },
  };
}

// ── Сохта R2 (S3) мижози + команда синфлари ─────────────────────────
function fakeSdk() {
  const mk = (type) => class {
    constructor(input) {
      this.type = type;
      this.input = input;
    }
  };
  return {
    PutObjectCommand: mk('put'),
    ListObjectsV2Command: mk('list'),
    DeleteObjectsCommand: mk('delete'),
  };
}

function fakeR2Client({listing = [], failPut = false} = {}) {
  const sent = [];
  return {
    sent,
    async send(cmd) {
      sent.push(cmd);
      if (cmd.type === 'put') {
        if (failPut) throw new Error('R2 PutObject 503');
        return {};
      }
      if (cmd.type === 'list') {
        const p = cmd.input.Prefix;
        return {
          Contents: listing.filter((k) => k.startsWith(p)).map((Key) => ({Key})),
          IsTruncated: false,
        };
      }
      return {};
    },
  };
}

// ── 1. ФЛАГ ЎЧИҚ: регрессия йўқ ─────────────────────────────────────
async function testFirebaseUnchanged() {
  const bucket = fakeBucket();
  const out = new FirebaseStorageOutput(bucket, 'master-taxi-gurlan.firebasestorage.app');

  const varUrl = await out.upload(
      TMP, {clipId: CLIP, runId: RUN, kind: 'variant', name: '720p.mp4'},
      'video/mp4');
  const hlsUrl = await out.upload(
      TMP, {clipId: CLIP, runId: RUN, kind: 'hls', name: 'master.m3u8'},
      'application/vnd.apple.mpegurl');

  check('[firebase] variant yo\'li o\'zgarmadi',
      bucket.uploads[0].opts.destination ===
      `tv_clip_variants/${CLIP}/${RUN}/720p.mp4`);
  check('[firebase] hls yo\'li o\'zgarmadi',
      bucket.uploads[1].opts.destination ===
      `tv_clip_hls/${CLIP}/${RUN}/master.m3u8`);
  check('[firebase] URL shakli o\'zgarmadi (token bilan)',
      varUrl.startsWith('https://firebasestorage.googleapis.com/v0/b/' +
          'master-taxi-gurlan.firebasestorage.app/o/') &&
      varUrl.includes('?alt=media&token='));
  check('[firebase] hls URL ham token bilan',
      hlsUrl.includes('?alt=media&token='));
  check('[firebase] Cache-Control immutable',
      bucket.uploads[0].opts.metadata.cacheControl === TV_CLIP_CACHE_CONTROL);
  check('[firebase] Content-Type mp4',
      bucket.uploads[0].opts.metadata.contentType === 'video/mp4');
  check('[firebase] Content-Type m3u8',
      bucket.uploads[1].opts.metadata.contentType ===
      'application/vnd.apple.mpegurl');
  check('[firebase] har obyektga alohida token',
      bucket.uploads[0].opts.metadata.metadata
          .firebaseStorageDownloadTokens !==
      bucket.uploads[1].opts.metadata.metadata
          .firebaseStorageDownloadTokens);
}

// ── 2. ФЛАГ ЁҚИҚ: R2 ────────────────────────────────────────────────
async function testR2Upload() {
  const client = fakeR2Client();
  const out = new R2Output({client, bucket: 'ava-video', sdk: fakeSdk()});

  const urls = {};
  for (const [name, kind] of [
    ['720p.mp4', 'variant'], ['360p_fast.mp4', 'variant'],
    ['master.m3u8', 'hls'], ['720p.ts', 'hls'],
  ]) {
    urls[name] = await out.upload(TMP, {clipId: CLIP, runId: RUN, kind, name});
  }

  const puts = client.sent.filter((c) => c.type === 'put');
  check('[r2] barcha obyektlar `processed/{clipId}/{runId}/` da',
      puts.every((c) => c.input.Key.startsWith(`processed/${CLIP}/${RUN}/`)));
  check('[r2] variant ham, hls ham bitta prefiksda (ildiz bo\'linmaydi)',
      puts[0].input.Key === `processed/${CLIP}/${RUN}/720p.mp4` &&
      puts[2].input.Key === `processed/${CLIP}/${RUN}/master.m3u8`);
  check('[r2] bucket to\'g\'ri', puts.every((c) => c.input.Bucket === 'ava-video'));
  check('[r2] URL CDN domenida',
      urls['720p.mp4'] ===
      `https://video.ava-uz.com/processed/${CLIP}/${RUN}/720p.mp4`);
  check('[r2] URL da token YO\'Q (kesh buzilmasin)',
      !urls['720p.mp4'].includes('token'));
  check('[r2] Cache-Control immutable',
      puts.every((c) => c.input.CacheControl ===
          'public, max-age=31536000, immutable'));
  check('[r2] Content-Type .mp4 -> video/mp4',
      puts[0].input.ContentType === 'video/mp4');
  check('[r2] Content-Type .m3u8 -> application/vnd.apple.mpegurl',
      puts[2].input.ContentType === 'application/vnd.apple.mpegurl');
  check('[r2] Content-Type .ts -> video/mp2t',
      puts[3].input.ContentType === 'video/mp2t');
  check('[r2] ContentLength fayl hajmiga teng',
      puts[0].input.ContentLength === 1234);
}

// ── 3. Content-Type харитаси (талаб қилинган мослик) ────────────────
function testContentTypes() {
  check('.m3u8 -> application/vnd.apple.mpegurl',
      contentTypeFor('master.m3u8') === 'application/vnd.apple.mpegurl');
  check('.m4s -> video/mp4', contentTypeFor('seg1.m4s') === 'video/mp4');
  check('.mp4 -> video/mp4', contentTypeFor('720p.mp4') === 'video/mp4');
  check('.webp -> image/webp', contentTypeFor('poster.webp') === 'image/webp');
  check('kengaytma ustuvor (noto\'g\'ri taklif bekor qilinadi)',
      contentTypeFor('a.m3u8', 'video/mp4') ===
      'application/vnd.apple.mpegurl');
  check('noma\'lum kengaytma -> taklif qilingani',
      contentTypeFor('x.bin', 'video/mp4') === 'video/mp4');
}

// ── 4. R2 ХАТОСИ: fallback ЙЎҚ ──────────────────────────────────────
async function testR2FailureNoFallback() {
  const client = fakeR2Client({failPut: true});
  const out = new R2Output({client, bucket: 'ava-video', sdk: fakeSdk()});
  let threw = false;
  try {
    await out.upload(TMP, {clipId: CLIP, runId: RUN, kind: 'variant',
      name: '720p.mp4'});
  } catch (e) {
    threw = /503/.test(e.message);
  }
  check('[r2] yozuv yiqilsa xato YUQORIGA otiladi (klip -> error)', threw);
  check('[r2] yiqilganda Firebase\'ga fallback urinishi YO\'Q',
      client.sent.filter((c) => c.type === 'put').length === 1);
}

// ── 5. Эски авлодларни тозалаш ──────────────────────────────────────
async function testCleanup() {
  // Firebase: эски клип (variantRun йўқ) — ҳеч нарса ўчмайди.
  const b = fakeBucket();
  b.setListing([
    `tv_clip_variants/${CLIP}/720p.mp4`,
    `tv_clip_hls/${CLIP}/master.m3u8`,
  ]);
  const fbOut = new FirebaseStorageOutput(b, 'bkt');
  await fbOut.cleanupOldRuns(CLIP, '');
  check('[firebase] variantRun yo\'q — eski fayllar saqlanadi',
      b.deleted.length === 0);

  // Firebase: жонли run бор — эскилари кетади, жонлиси қолади.
  const b2 = fakeBucket();
  b2.setListing([
    `tv_clip_variants/${CLIP}/720p.mp4`,
    `tv_clip_variants/${CLIP}/r0/720p.mp4`,
    `tv_clip_variants/${CLIP}/r1/720p.mp4`,
  ]);
  const fbOut2 = new FirebaseStorageOutput(b2, 'bkt');
  await fbOut2.cleanupOldRuns(CLIP, 'r1');
  check('[firebase] jonli run saqlandi, eskilari o\'chdi',
      b2.deleted.length === 2 &&
      !b2.deleted.includes(`tv_clip_variants/${CLIP}/r1/720p.mp4`));

  // R2: жонли run қолади.
  const client = fakeR2Client({listing: [
    `processed/${CLIP}/r0/720p.mp4`,
    `processed/${CLIP}/r0/master.m3u8`,
    `processed/${CLIP}/r1/720p.mp4`,
    `processed/clipB/r0/720p.mp4`,
  ]});
  const r2 = new R2Output({client, bucket: 'ava-video', sdk: fakeSdk()});
  await r2.cleanupOldRuns(CLIP, 'r1');
  const del = client.sent.find((c) => c.type === 'delete');
  const keys = del ? del.input.Delete.Objects.map((o) => o.Key) : [];
  check('[r2] eski run o\'chirildi', keys.length === 2 &&
      keys.every((k) => k.startsWith(`processed/${CLIP}/r0/`)));
  check('[r2] jonli run tegilmadi',
      !keys.includes(`processed/${CLIP}/r1/720p.mp4`));
  check('[r2] boshqa klipga tegilmadi',
      !keys.some((k) => k.includes('clipB')));

  // R2: variantRun йўқ — ҳеч нарса ўчмайди (ва ҳатто list ҳам қилинмайди).
  const c2 = fakeR2Client({listing: [`processed/${CLIP}/720p.mp4`]});
  const r2b = new R2Output({client: c2, bucket: 'ava-video', sdk: fakeSdk()});
  await r2b.cleanupOldRuns(CLIP, '');
  check('[r2] variantRun yo\'q — hech nima o\'chmaydi', c2.sent.length === 0);
}

// ── 6. Эга рўйхати (tvR2OutputOwners) ───────────────────────────────
function testOwnerAllowlist() {
  const list = ['998941133355'];
  check('aynan mos', r2OwnerAllowed('998941133355', list));
  check('formatlangan raqam mos (+998 94 113-33-55)',
      r2OwnerAllowed('+998 94 113-33-55', list));
  check('ro\'yxatdagi format erkin',
      r2OwnerAllowed('998941133355', ['+998 (94) 113-33-55']));
  check('milliy format mos (941133355)',
      r2OwnerAllowed('941133355', list));
  check('boshqa raqam mos EMAS',
      !r2OwnerAllowed('998901234567', list));
  check('bo\'sh ro\'yxat — false', !r2OwnerAllowed('998941133355', []));
  check('ro\'yxat massiv emas — false',
      !r2OwnerAllowed('998941133355', undefined));
  check('egasi yo\'q — false', !r2OwnerAllowed('', list));
  check('null egasi yiqilmaydi', !r2OwnerAllowed(null, list));
  // Qisqa, ma'nosiz qiymat butun ro'yxatni ochib yubormasligi kerak.
  check('qisqa qiymat mos EMAS (9 raqamdan kam)',
      !r2OwnerAllowed('3355', list) && !r2OwnerAllowed('998941133355', ['55']));
}

// ── 7. Backend аниқлаш ──────────────────────────────────────────────
function testResolveBackend() {
  check('variantBackend=r2 -> r2',
      resolveClipBackend({variantBackend: 'r2'}) === 'r2');
  check('variantBackend=firebase -> firebase',
      resolveClipBackend({variantBackend: 'firebase'}) === 'firebase');
  check('maydon yo\'q, URL CDN\'da -> r2',
      resolveClipBackend({
        hlsUrl: 'https://video.ava-uz.com/processed/a/r1/master.m3u8',
      }) === 'r2');
  check('maydon yo\'q, URL firebasestorage -> firebase',
      resolveClipBackend({
        hlsUrl: 'https://firebasestorage.googleapis.com/v0/b/x/o/y?alt=media',
      }) === 'firebase');
  check('variant URL bo\'yicha ham aniqlanadi',
      resolveClipBackend({
        videoVariants: {'720p': 'https://video.ava-uz.com/processed/a/r1/720p.mp4'},
      }) === 'r2');
  check('eski klip (hech narsa yo\'q) -> firebase',
      resolveClipBackend({}) === 'firebase');
  check('bo\'sh/null yiqilmaydi', resolveClipBackend(null) === 'firebase');
}

// ── 8. Клип ўчирилганда ─────────────────────────────────────────────
async function testDeleteAllForClip() {
  // Firebase: ikkala ildiz ham o'chadi.
  const b = fakeBucket();
  const removed = [];
  b.deleteFiles = async ({prefix}) => {
    removed.push(prefix);
  };
  const fb = new FirebaseStorageOutput(b, 'bkt');
  const fbUrls = await fb.deleteAllForClip(CLIP);
  check('[firebase] ikkala prefiks ham o\'chirildi',
      removed.includes(`tv_clip_variants/${CLIP}/`) &&
      removed.includes(`tv_clip_hls/${CLIP}/`));
  check('[firebase] purge uchun URL yo\'q (CDN\'da emas)',
      fbUrls.length === 0);

  // R2: barcha avlodlar o'chadi va purge uchun URL qaytadi.
  const client = fakeR2Client({listing: [
    `processed/${CLIP}/r0/720p.mp4`,
    `processed/${CLIP}/r1/720p.mp4`,
    `processed/${CLIP}/r1/720p.ts`,
    `processed/${CLIP}/r1/master.m3u8`,
    `processed/clipB/r1/720p.mp4`,
  ]});
  const r2 = new R2Output({client, bucket: 'ava-video', sdk: fakeSdk()});
  const urls = await r2.deleteAllForClip(CLIP);
  const del = client.sent.find((c) => c.type === 'delete');
  const keys = del ? del.input.Delete.Objects.map((o) => o.Key) : [];
  check('[r2] BARCHA avlodlar o\'chdi (r0 ham, r1 ham)', keys.length === 4);
  check('[r2] boshqa klipga tegilmadi',
      !keys.some((k) => k.includes('clipB')));
  check('[r2] purge uchun to\'liq CDN URL\'lari qaytdi',
      urls.length === 4 &&
      urls.every((u) => u.startsWith('https://video.ava-uz.com/processed/')));
  check('[r2] .ts segment ham ro\'yxatda (eng katta fayl)',
      urls.some((u) => u.endsWith('/720p.ts')));
}

// ── 9. CDN purge ────────────────────────────────────────────────────
async function testPurge() {
  const token = process.env.CLOUDFLARE_API_TOKEN;
  const zone = process.env.CLOUDFLARE_ZONE_ID;
  delete process.env.CLOUDFLARE_API_TOKEN;
  delete process.env.CLOUDFLARE_ZONE_ID;
  const n = await purgeCdnUrls(['https://video.ava-uz.com/processed/a/r1/x.mp4']);
  check('kalit yo\'q — purge o\'tkazib yuboriladi, yiqilmaydi', n === 0);
  check('bo\'sh ro\'yxat — 0', (await purgeCdnUrls([])) === 0);
  if (token !== undefined) process.env.CLOUDFLARE_API_TOKEN = token;
  if (zone !== undefined) process.env.CLOUDFLARE_ZONE_ID = zone;
}

async function main() {
  await testFirebaseUnchanged();
  await testR2Upload();
  testContentTypes();
  await testR2FailureNoFallback();
  await testCleanup();
  testOwnerAllowlist();
  testResolveBackend();
  await testDeleteAllForClip();
  await testPurge();

  try {
    fs.unlinkSync(TMP);
  } catch (_) {}

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} passed`);
  process.exit(failed.length ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
