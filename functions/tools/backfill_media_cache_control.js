/**
 * Storage'dagi TV media fayllariga `Cache-Control` sarlavhasini qo'yadi.
 *
 * Muammo: Firebase Storage standarti — `private, max-age=0`. Ya'ni hech bir
 * CDN yoki oraliq kesh saqlay olmaydi va klient ham har safar qaytadan
 * so'raydi: har bir HLS segmenti har ko'rishda us-central1'dan tortiladi.
 *
 * Bu skript FAQAT metadata'ni yangilaydi — fayl qayta yozilmaydi, qayta
 * kodlanmaydi, download token va URL o'zgarmaydi. Shuning uchun arzon va
 * ilovaga hech qanday ta'sir qilmaydi (eski URL'lar ishlayveradi).
 *
 * Yangi yuklamalar buni allaqachon o'zi qo'yadi (`TV_CLIP_CACHE_CONTROL`
 * functions/index.js, `_tvMediaCacheControl` tv_storage_service.dart) —
 * bu skript faqat ESKI fayllar uchun.
 *
 * Ishlatish:
 *   node functions/tools/backfill_media_cache_control.js                # dry run
 *   node functions/tools/backfill_media_cache_control.js --apply
 *   node functions/tools/backfill_media_cache_control.js --apply --prefix tv_clip_hls/
 */
const admin = require('firebase-admin');
const path = require('path');

if (!admin.apps.length) {
  const sa = path.join(__dirname, '..', 'service-account.json');
  admin.initializeApp({credential: admin.credential.cert(require(sa))});
}

const BUCKET = 'master-taxi-gurlan.firebasestorage.app';
const bucket = admin.storage().bucket(BUCKET);

const CACHE_CONTROL = 'public, max-age=31536000, immutable';

// Video/HLS/poster — hammasi o'zgarmas: qayta yaratilganda yangi nom yoki
// yangi token beriladi, shuning uchun `immutable` xavfsiz.
const DEFAULT_PREFIXES = [
  'tv_clip_variants/',
  'tv_clip_hls/',
  'tv_clips/',
];

const APPLY = process.argv.includes('--apply');
const PARALLEL = 8;

function argValue(name) {
  const i = process.argv.indexOf(name);
  return (i >= 0 && i + 1 < process.argv.length) ? process.argv[i + 1] : null;
}

const prefixes = argValue('--prefix')
  ? [argValue('--prefix')]
  : DEFAULT_PREFIXES;

async function processPrefix(prefix) {
  const [files] = await bucket.getFiles({prefix});
  let already = 0;
  const todo = [];
  for (const f of files) {
    if ((f.metadata || {}).cacheControl === CACHE_CONTROL) already++;
    else todo.push(f);
  }
  console.log(`${prefix.padEnd(22)} jami ${String(files.length).padStart(5)}  ` +
      `allaqachon ${String(already).padStart(5)}  kerak ${String(todo.length).padStart(5)}`);

  if (!APPLY || todo.length === 0) return {total: files.length, done: 0, failed: 0};

  let done = 0;
  let failed = 0;
  for (let i = 0; i < todo.length; i += PARALLEL) {
    const batch = todo.slice(i, i + PARALLEL);
    await Promise.all(batch.map(async (f) => {
      try {
        // PATCH semantikasi: faqat `cacheControl` o'zgaradi, `metadata`
        // ichidagi `firebaseStorageDownloadTokens` tegilmaydi.
        await f.setMetadata({cacheControl: CACHE_CONTROL});
        done++;
      } catch (e) {
        failed++;
        console.error(`  XATO ${f.name}: ${e.message}`);
      }
    }));
    if (done % 200 < PARALLEL && done > 0) {
      console.log(`    ...${done}/${todo.length}`);
    }
  }
  console.log(`    ${prefix}: ${done} yangilandi, ${failed} xato`);
  return {total: files.length, done, failed};
}

(async () => {
  console.log(`=== Cache-Control backfill (${BUCKET}) ===`);
  console.log(APPLY ? `APPLY — "${CACHE_CONTROL}"` : 'DRY RUN (--apply bilan bajariladi)');
  console.log('');

  let done = 0;
  let failed = 0;
  for (const p of prefixes) {
    const r = await processPrefix(p);
    done += r.done;
    failed += r.failed;
  }
  console.log('');
  console.log(APPLY
    ? `Jami: ${done} fayl yangilandi, ${failed} xato.`
    : 'Bajarish uchun --apply qo\'shing.');
  process.exit(failed > 0 ? 1 : 0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
