/**
 * Кафе-ресторан қидируви — МАВЖУД ресторанларни `search_index`га тушириш (2026-10-25, Agent C;
 * `functions/shop_search_index.js` → `onSearchIndexRestaurantWrite`). Намуна: `backfill_shop_search_index.js`.
 *
 * Мантиқ ТРИГГЕРДА (бир манба): скрипт ресторан ҳужжатига фақат битта майдон ёзади — `searchIndexedAt` (бошқа
 * майдонга тегилмайди; rules бу майдонни а'зога ёздирмайди, мавжуд `restaurantProfilePatchOk` diff-асосли бўлгани
 * учун а'зо таҳририга халақит бермайди). Deploy қилинган триггер шу ўзгаришни кўриб индекслайди.
 * Режага фақат индекс ёзуви ЙЎҚ ёки ЭСКИРГАН (`title`/`active` мос эмас) ресторанлар киради — қайта ишга
 * туширилса, триггер ишлагандан кейин режа бўш бўлади (идемпотент).
 *
 * Хавфсизлик (27, 28-банд):
 *   - DRY RUN — стандарт: рўйхат ва нима ёзилиши, ҳеч нарса ёзилмайди.
 *   - `--apply`: ёзишдан ОЛДИН заҳира (`tools/backup/restaurant_search_backfill_<vaqt>.json`: ҳар ресторандаги
 *     аввалги `searchIndexedAt` қиймати), 400 тадан батч, якунда саноқ.
 *   - Қайтариш: `--rollback <backup.json> --apply` — аввалги `searchIndexedAt` тикланади (йўқ бўлгани ўчирилади).
 *     Индекс ёзуви — ҳосила маълумот: у ресторанинг ЖОРИЙ ҳолатини акс эттиради ва ўчирилмайди.
 *   - Фақат emulator'да синалган; прод'га ишга тушириш — эганинг алоҳида рухсати билан.
 *
 *   node functions/tools/backfill_restaurant_search_index.js            # dry run
 *   node functions/tools/backfill_restaurant_search_index.js --apply
 *   node functions/tools/backfill_restaurant_search_index.js --rollback functions/tools/backup/<file>.json --apply
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { restaurantToSearchEntry } = require('../shop_search_index');

const BATCH = 400;
const READ_CHUNK = 300;

/** Режа (тест ишлатади): қайси ресторанга `searchIndexedAt` ёзилади. */
async function plan(db) {
  const snap = await db.collection('restaurants').get();
  const out = [];
  for (let i = 0; i < snap.docs.length; i += READ_CHUNK) {
    const docs = snap.docs.slice(i, i + READ_CHUNK);
    const refs = docs.map((d) => db.collection('search_index').doc(`restaurant_${d.id}`));
    const idx = refs.length ? await db.getAll(...refs) : [];
    docs.forEach((d, j) => {
      const x = d.data() || {};
      const want = restaurantToSearchEntry(d.id, x);
      const have = idx[j] && idx[j].exists ? (idx[j].data() || {}) : null;
      if (have && have.title === want.title && have.active === want.active) return;
      out.push({
        col: 'restaurants', id: d.id, field: 'searchIndexedAt',
        before: x.searchIndexedAt === undefined ? null : x.searchIndexedAt,
        value: '__server_time__', reason: have ? 'stale' : 'missing',
      });
    });
  }
  return out;
}

async function applyPlan(db, admin, steps) {
  const { FieldValue } = admin.firestore;
  let written = 0;
  for (let i = 0; i < steps.length; i += BATCH) {
    const batch = db.batch();
    steps.slice(i, i + BATCH).forEach((s) => {
      batch.update(db.collection(s.col).doc(s.id), { [s.field]: FieldValue.serverTimestamp() });
    });
    await batch.commit();
    written += Math.min(BATCH, steps.length - i);
  }
  return written;
}

/** Заҳирадаги Timestamp JSON'да `{_seconds,_nanoseconds}` бўлиб қолади — қайта Timestamp қилинади. */
function restoreValue(admin, v) {
  if (v && typeof v === 'object' && Number.isFinite(v._seconds)) {
    return new admin.firestore.Timestamp(v._seconds, v._nanoseconds || 0);
  }
  return v;
}

async function rollback(db, admin, steps) {
  const { FieldValue } = admin.firestore;
  let written = 0;
  for (let i = 0; i < steps.length; i += BATCH) {
    const batch = db.batch();
    steps.slice(i, i + BATCH).forEach((s) => {
      batch.update(db.collection(s.col).doc(s.id), {
        [s.field]: s.before === null ? FieldValue.delete() : restoreValue(admin, s.before),
      });
    });
    await batch.commit();
    written += Math.min(BATCH, steps.length - i);
  }
  return written;
}

async function main() {
  const admin = require('firebase-admin');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-backfill' });
    } else {
      admin.initializeApp({ credential: admin.credential.cert(require(path.join(__dirname, '..', 'service-account.json'))) });
    }
  }
  const db = admin.firestore();
  const apply = process.argv.includes('--apply');
  const rbIdx = process.argv.indexOf('--rollback');
  if (rbIdx > 0) {
    const steps = JSON.parse(fs.readFileSync(process.argv[rbIdx + 1], 'utf8'));
    console.log(`${apply ? 'APPLY' : 'DRY RUN'} rollback: ${steps.length} ta restoran`);
    if (apply) console.log(`tiklandi: ${await rollback(db, admin, steps)}`);
    return;
  }
  const steps = await plan(db);
  const by = steps.reduce((m, s) => ({ ...m, [s.reason]: (m[s.reason] || 0) + 1 }), {});
  console.log(`${apply ? 'APPLY' : 'DRY RUN'} backfill: ${steps.length} ta restoran ${JSON.stringify(by)}`);
  steps.slice(0, 20).forEach((s) => console.log(`  ${s.col}/${s.id} ${s.field} (${s.reason})`));
  if (!apply || steps.length === 0) return;
  const dir = path.join(__dirname, 'backup');
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `restaurant_search_backfill_${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(file, JSON.stringify(steps, null, 1), 'utf8');
  console.log(`zaxira: ${file}`);
  console.log(`yozildi: ${await applyPlan(db, admin, steps)}`);
}

module.exports = { plan, applyPlan, rollback };

if (require.main === module) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
