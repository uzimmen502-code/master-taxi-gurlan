/**
 * Онлайн дўкон қидируви — МАВЖУД ҳужжатларни индексга тушириш (2026-10-25, 4-босқич; `functions/shop_search_index.js`).
 *
 * Мантиқ ТРИГГЕРДА (бир манба): скрипт ҳужжатга фақат шундай ёзув қиладики, deploy қилинган триггер уни индекслайди:
 *   • `tv_shop_items` — `searchTokens` (айнан триггер ҳисоблайдиган қиймат, `shopItemTokens`); фарқ қилмаса — тегмайди;
 *   • `tv_shops`, `businesses` — `searchIndexedAt` (бир майдон; бошқа майдонга тегилмайди).
 *
 * Хавфсизлик (27, 28-банд):
 *   - DRY RUN — стандарт: ҳужжатлар рўйхати ва нима ёзилиши, ҳеч нарса ёзилмайди.
 *   - `--apply`: ёзишдан ОЛДИН заҳира (`tools/backup/shop_search_backfill_<vaqt>.json`: ҳар ҳужжатнинг аввалги
 *     `searchTokens` / `searchIndexedAt` қиймати), 400 тадан батч, якунда саноқ.
 *   - Қайтариш: `--rollback <backup.json> --apply` — аввалги қийматлар тикланади (йўқ бўлгани ўчирилади); индекс
 *     ёзувлари триггер орқали шунга мос янгиланади.
 *
 *   node functions/tools/backfill_shop_search_index.js            # dry run
 *   node functions/tools/backfill_shop_search_index.js --apply
 *   node functions/tools/backfill_shop_search_index.js --rollback functions/tools/backup/<file>.json --apply
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { shopItemTokens } = require('../shop_search_index');

const BATCH = 400;

function sameTokens(a, b) {
  return Array.isArray(a) && a.length === b.length && a.every((x, i) => x === b[i]);
}

/** Режа (тест ишлатади): қайси ҳужжатга нима ёзилади. */
async function plan(db) {
  const out = [];
  const items = await db.collection('tv_shop_items').get();
  items.docs.forEach((d) => {
    const x = d.data() || {};
    const tokens = shopItemTokens(x);
    if (!sameTokens(x.searchTokens, tokens)) {
      out.push({ col: 'tv_shop_items', id: d.id, field: 'searchTokens', before: x.searchTokens === undefined ? null : x.searchTokens, value: tokens });
    }
  });
  for (const col of ['tv_shops', 'businesses']) {
    const snap = await db.collection(col).get();
    snap.docs.forEach((d) => {
      const x = d.data() || {};
      out.push({ col, id: d.id, field: 'searchIndexedAt', before: x.searchIndexedAt === undefined ? null : x.searchIndexedAt, value: '__server_time__' });
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
      const v = s.value === '__server_time__' ? FieldValue.serverTimestamp() : s.value;
      batch.update(db.collection(s.col).doc(s.id), { [s.field]: v });
    });
    await batch.commit();
    written += Math.min(BATCH, steps.length - i);
  }
  return written;
}

async function rollback(db, admin, steps) {
  const { FieldValue } = admin.firestore;
  let written = 0;
  for (let i = 0; i < steps.length; i += BATCH) {
    const batch = db.batch();
    steps.slice(i, i + BATCH).forEach((s) => {
      batch.update(db.collection(s.col).doc(s.id), { [s.field]: s.before === null ? FieldValue.delete() : s.before });
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
    console.log(`${apply ? 'APPLY' : 'DRY RUN'} rollback: ${steps.length} ta hujjat`);
    if (apply) console.log(`tiklandi: ${await rollback(db, admin, steps)}`);
    return;
  }
  const steps = await plan(db);
  const by = steps.reduce((m, s) => ({ ...m, [s.col]: (m[s.col] || 0) + 1 }), {});
  console.log(`${apply ? 'APPLY' : 'DRY RUN'} backfill: ${steps.length} ta hujjat ${JSON.stringify(by)}`);
  steps.slice(0, 20).forEach((s) => console.log(`  ${s.col}/${s.id.replace(/\d{5}(\d{4})/, '*****$1')} ${s.field}`));
  if (!apply || steps.length === 0) return;
  const dir = path.join(__dirname, 'backup');
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `shop_search_backfill_${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(file, JSON.stringify(steps, null, 1), 'utf8');
  console.log(`zaxira: ${file}`);
  console.log(`yozildi: ${await applyPlan(db, admin, steps)}`);
}

module.exports = { plan, applyPlan, rollback };

if (require.main === module) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
