/**
 * «Splash реклама» — НАМУНА (уй) реклама: бутун республика учун битта ҳужжат (эга 2026-11-28:
 * «экранда намуна учун чорловчи Реклама банери ярат»).
 *
 * Нима қилади (`--apply` билан):
 *   1. `splash_house_ad/out/house_{uz_Cyrl,uz_Latn,ru}.{webp|png}` ни Storage'га юклайди:
 *      `platform_images/splash_ads/house_{lang}_{sha8}.{ext}` (мазмун хеши йўлда — креатив ўзгарса янги ҳавола,
 *      мижоз кеши янгиланади; бир хил файл қайта юкланмайди; токен детерминистик — қайта ишга тушириш бир хил ҳавола).
 *   2. `splash_ads/ava_house_republic` (ДОИМИЙ ID — идемпотент) ҳужжатини `adminUpsertSplashAd` билан БИР ХИЛ шаклда
 *      ёзади (`validateAd` + `adminAdFields`): house:true, imageUrls (3 тил), imageUrl = кирилл (эски мижоз), матн 3 тил,
 *      areaKeys ['all'], weight 1, муддат 365 кун. Ҳужжат + `admin_audit` бир транзакцияда; ўзгармаган бўлса — ёзмайди.
 *   3. Ёзишдан олдин мавжуд ҳужжат нусхаси: `functions/tools/backup/splash_house_ad_<вақт>.json`.
 *
 * Мижоз намунани ФАҚАТ ҳудудда бошқа реклама бўлмаганда кўрсатади (feat/splash-house-ad). Эски мижоз (house
 * майдонини билмайди) — оғирлик 1 (пуллик оғирлиги = кунлик тўлов сўмда), яъни улуши амалда сезилмайди.
 *
 * Хавфсизлик (27, 28, 41-банд): DRY RUN — сукут; лойиҳа ФАҚАТ `--project <id>`; `--apply` — ёзиш.
 *
 *   node functions/tools/create_splash_house_ad.js --project <id>                         # DRY RUN
 *   node functions/tools/create_splash_house_ad.js --project <id> --apply
 *   node functions/tools/create_splash_house_ad.js --project <id> --ext png               # PNG (сукут webp)
 *   node functions/tools/create_splash_house_ad.js --project <id> --off --apply           # вақтинча ўчириш (active:false)
 *   node functions/tools/create_splash_house_ad.js --project <id> --rollback <backup.json> --apply
 *       # ROLLBACK: backup'даги ҳолатга қайтаради (ҳужжат аввал йўқ бўлган бўлса — ўчиради); Storage файллари қолади.
 */
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { validateAd, adminAdFields, ADS } = require('../splash_ads');

const DOC_ID = 'ava_house_republic';
const LANGS = ['uz_Cyrl', 'uz_Latn', 'ru'];
const DAY_MS = 86400000;
const TZ_OFFSET_MS = 5 * 3600000;
const DURATION_DAYS = 365; // validateAd: ≤ 366 кун
const MAX_BYTES = 1500 * 1024; // SplashAdPrefetcher.maxImageBytes
const STORAGE_URL_PREFIX = 'https://firebasestorage.googleapis.com/';
const ACTOR = 'tool:create_splash_house_ad';
const CONTENT_TYPES = { webp: 'image/webp', png: 'image/png' };

/** Матн (расм юкланмаса — мижоз шуни кўрсатади). `SplashAdTexts.placeholder` билан бир хил. */
const TEXT = Object.freeze({
  uz_Cyrl: 'Бу ерда сизнинг рекламангиз бўлиши мумкин',
  uz_Latn: 'Bu yerda sizning reklamangiz bölişi mumkin',
  ru: 'Здесь может быть ваша реклама',
});

const sha = (buf) => crypto.createHash('sha256').update(buf).digest('hex');
/** Детерминистик download token (UUID шакли) — қайта ишга тушириш бир хил ҳавола беради. */
function tokenOf(objectPath, buf) {
  const h = sha(Buffer.concat([Buffer.from(`${objectPath}:`), buf]));
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-a${h.slice(17, 20)}-${h.slice(20, 32)}`;
}
const objectPathOf = (lang, buf, ext) => `platform_images/splash_ads/house_${lang}_${sha(buf).slice(0, 8)}.${ext}`;
const downloadUrlOf = (bucket, objectPath, token) =>
  `${STORAGE_URL_PREFIX}v0/b/${bucket}/o/${encodeURIComponent(objectPath)}?alt=media&token=${token}`;

/** Тошкент кунининг боши (бугун 00:00). */
const tashkentDayStart = (ms) => Math.floor((ms + TZ_OFFSET_MS) / DAY_MS) * DAY_MS - TZ_OFFSET_MS;

/** Соф: ҳужжат учун `validateAd` кириши. */
function buildAd({ imageUrls, nowMs, active = true }) {
  const startAtMs = tashkentDayStart(nowMs);
  return {
    title: 'AVA · намуна реклама (Реклама бериш)',
    text: { ...TEXT },
    imageUrl: imageUrls.uz_Cyrl,
    imageUrls,
    linkUrl: '',
    startAtMs,
    endAtMs: startAtMs + DURATION_DAYS * DAY_MS,
    districts: [],
    regionIds: [],
    priority: 0,
    weight: 1,
    active,
    house: true,
  };
}

/** Солиштириш учун (вақт белгиларисиз). */
function comparable(d) {
  if (!d) return null;
  const ms = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : v);
  return JSON.stringify({
    title: d.title, text: d.text, imageUrl: d.imageUrl, imageUrls: d.imageUrls || {}, linkUrl: d.linkUrl,
    startAt: ms(d.startAt), endAt: ms(d.endAt), districts: d.districts, regionIds: d.regionIds, areaKeys: d.areaKeys,
    priority: d.priority, weight: d.weight, source: d.source, house: d.house === true, active: d.active, visible: d.visible,
  });
}

/** Backup JSON (Timestamp → {_ms}). */
function toBackup(data) {
  return JSON.parse(JSON.stringify(data || null, (k, v) => (v && typeof v.toMillis === 'function' ? { _ms: v.toMillis() } : v)));
}
function fromBackup(obj, TS) {
  const walk = (v) => {
    if (Array.isArray(v)) return v.map(walk);
    if (v && typeof v === 'object') {
      if (Object.keys(v).length === 1 && Number.isSafeInteger(v._ms)) return TS.fromMillis(v._ms);
      return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, walk(x)]));
    }
    return v;
  };
  return walk(obj);
}

function readCreatives(dir, ext) {
  return LANGS.map((lang) => {
    const file = path.join(dir, `house_${lang}.${ext}`);
    if (!fs.existsSync(file)) throw new Error(`Креатив йўқ: ${file} (аввал: node functions/tools/splash_house_ad/render.js)`);
    const buf = fs.readFileSync(file);
    if (!buf.length || buf.length > MAX_BYTES) throw new Error(`${file}: ${buf.length} B (1..${MAX_BYTES})`);
    return { lang, file, buf };
  });
}

async function main() {
  const argv = process.argv.slice(2);
  const arg = (name) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : null; };
  const project = arg('--project');
  const apply = argv.includes('--apply');
  const off = argv.includes('--off');
  const rollbackFile = arg('--rollback');
  const ext = arg('--ext') || 'webp';
  if (!project) { console.log('--project <id> шарт (DRY RUN сукут, --apply — ёзиш).'); process.exit(2); }
  if (!CONTENT_TYPES[ext]) { console.log('--ext webp | png'); process.exit(2); }
  const bucketName = arg('--bucket') || `${project}.firebasestorage.app`;

  const admin = require('firebase-admin');
  admin.initializeApp({ projectId: project, storageBucket: bucketName });
  const db = admin.firestore();
  const TS = admin.firestore.Timestamp;
  const FV = admin.firestore.FieldValue;
  const ref = db.collection(ADS).doc(DOC_ID);
  const mode = apply ? 'APPLY' : 'DRY RUN';
  console.log(`${mode} · project=${project} · bucket=${bucketName} · doc=${ADS}/${DOC_ID}`);

  // ── ROLLBACK ──
  if (rollbackFile) {
    const backup = JSON.parse(fs.readFileSync(rollbackFile, 'utf8'));
    if (backup.docPath !== `${ADS}/${DOC_ID}`) throw new Error(`backup бошқа ҳужжатники: ${backup.docPath}`);
    const restore = backup.data ? fromBackup(backup.data, TS) : null;
    console.log(restore ? `RESTORE → version ${restore.version}` : 'DELETE (аввал ҳужжат йўқ эди)');
    if (!apply) return console.log('DRY RUN: ҳеч нарса ёзилмади.');
    await db.runTransaction(async (t) => {
      const cur = await t.get(ref);
      if (restore) t.set(ref, { ...restore, updatedAt: FV.serverTimestamp() });
      else if (cur.exists) t.delete(ref);
      t.create(db.collection('admin_audit').doc(), {
        kind: restore ? 'splash_ad_set' : 'splash_ad_delete', actor: ACTOR, target: `${ADS}/${DOC_ID}`,
        before: cur.exists ? toBackup(cur.data()) : null, after: restore ? backup.data : null,
        reason: `rollback ${path.basename(rollbackFile)}`, at: FV.serverTimestamp(),
      });
    });
    return console.log('ROLLBACK APPLIED.');
  }

  // ── Креативлар ──
  const creatives = readCreatives(path.join(__dirname, 'splash_house_ad', 'out'), ext);
  const bucket = admin.storage().bucket(bucketName);
  const imageUrls = {};
  const uploads = [];
  for (const c of creatives) {
    const objectPath = objectPathOf(c.lang, c.buf, ext);
    const token = tokenOf(objectPath, c.buf);
    imageUrls[c.lang] = downloadUrlOf(bucketName, objectPath, token);
    const [exists] = await bucket.file(objectPath).exists();
    uploads.push({ ...c, objectPath, token, exists });
    console.log(`${exists ? 'EXISTS ' : apply ? 'UPLOAD ' : 'WOULD UPLOAD '}${objectPath} (${Math.round(c.buf.length / 1024)} KB)`);
  }

  // ── Ҳужжат ──
  const v = validateAd(buildAd({ imageUrls, nowMs: Date.now(), active: !off }));
  if (!v.ok) throw new Error(`validateAd: ${v.errors.join(', ')}`);
  const fields = adminAdFields(v.clean, TS);
  const snap = await ref.get();
  const prev = snap.exists ? snap.data() : null;
  // Муддат ҳар ишга туширишда сурилмасин: ҳужжат бор ва фаол бўлса — аввалги ойна сақланади.
  if (prev && prev.startAt && prev.endAt && prev.endAt.toMillis() > Date.now() && !off) {
    fields.startAt = prev.startAt;
    fields.endAt = prev.endAt;
  }
  const changed = comparable(prev) !== comparable(fields);
  console.log(prev ? `EXISTS version ${prev.version || 1} · ${changed ? 'CHANGED' : 'UNCHANGED (ёзилмайди)'}` : 'NEW document');
  console.log(JSON.stringify({ ...toBackup(fields) }, null, 2));
  if (!apply) return console.log('DRY RUN: ҳеч нарса ёзилмади. Ёзиш учун --apply.');

  for (const u of uploads) {
    if (u.exists) continue;
    await bucket.file(u.objectPath).save(u.buf, {
      resumable: false,
      contentType: CONTENT_TYPES[ext],
      metadata: { cacheControl: 'public, max-age=31536000, immutable', metadata: { firebaseStorageDownloadTokens: u.token } },
    });
  }
  if (!changed) return console.log('APPLIED: ҳужжат ўзгармаган (идемпотент).');

  const backupDir = path.join(__dirname, 'backup');
  fs.mkdirSync(backupDir, { recursive: true });
  const backupFile = path.join(backupDir, `splash_house_ad_${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(backupFile, JSON.stringify({ docPath: `${ADS}/${DOC_ID}`, project, data: toBackup(prev) }, null, 2));
  console.log(`BACKUP ${backupFile}`);

  const version = await db.runTransaction(async (t) => {
    const cur = await t.get(ref);
    const curData = cur.exists ? cur.data() : null;
    if (curData && curData.source === 'paid') throw new Error('Пуллик ҳужжат устидан ёзилмайди');
    const next = (curData && Number.isInteger(curData.version) ? curData.version : 0) + 1;
    t.set(ref, {
      ...fields, version: next, updatedAt: FV.serverTimestamp(), ...(cur.exists ? {} : { createdAt: FV.serverTimestamp() }),
    });
    t.create(db.collection('admin_audit').doc(), {
      kind: 'splash_ad_set', actor: ACTOR, target: `${ADS}/${DOC_ID} v${next}`,
      before: curData ? toBackup(curData) : null, after: toBackup(fields),
      reason: off ? 'намуна реклама ўчирилди (--off)' : 'намуна реклама (эга 2026-11-28)', at: FV.serverTimestamp(),
    });
    return next;
  });
  console.log(`APPLIED: ${ADS}/${DOC_ID} v${version}. Rollback: --rollback ${backupFile} --apply`);
}

if (require.main === module) main().catch((e) => { console.error(e.message || e); process.exit(1); });

module.exports = { buildAd, objectPathOf, tokenOf, downloadUrlOf, tashkentDayStart, comparable, toBackup, fromBackup, DOC_ID, TEXT };
