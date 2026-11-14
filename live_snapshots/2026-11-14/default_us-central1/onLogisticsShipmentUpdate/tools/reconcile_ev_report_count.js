#!/usr/bin/env node
/**
 * EV `reportCount` sverkasi (admin audit, 2026-10-08).
 *
 * `reportCount` endi «OCHIQ (hal qilinmagan) shikoyatlar soni»:
 * `adminResolveEvReport` uni kamaytiradi (1ee9355). Lekin undan oldin hal
 * qilingan shikoyatlar sanagda qolib ketgan — bunday stansiyalar admin
 * navbatida (`reportCount > 0`) abadiy turadi va EV trip planner ularni
 * jarimalaydi. Bu tool har stansiya uchun `reports` subkolleksiyasidagi
 * `resolved != true` sonini sanab, `reportCount`ni shunga tenglaydi.
 *
 *   node functions/tools/reconcile_ev_report_count.js            # DRY-RUN
 *   node functions/tools/reconcile_ev_report_count.js --apply    # yozadi
 *   node functions/tools/reconcile_ev_report_count.js --rollback <batchId>
 *
 * Xavfsizlik: faqat `reportCount > 0` stansiyalar o'qiladi; o'zgaradigan
 * har stansiyaning ESKI qiymati `ev_report_count_reconcile/{batchId}`
 * hujjatiga yoziladi (rollback shu yerdan). Tranzaksiya: hisob va yozuv
 * bitta tranzaksiyada (parallel yangi shikoyat sanalmay qolmaydi).
 */
'use strict';
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const args = process.argv.slice(2);
const APPLY = args.includes('--apply');
const rbIdx = args.indexOf('--rollback');
const ROLLBACK = rbIdx >= 0 ? String(args[rbIdx + 1] || '') : '';

const keyPath = path.join(__dirname, '..', 'service-account.json');
if (!fs.existsSync(keyPath)) {
  console.error('service-account.json topilmadi:', keyPath);
  process.exit(1);
}
admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
const db = admin.firestore();
db.settings({ preferRest: true });

const BATCH_COL = 'ev_report_count_reconcile';

async function rollback(batchId) {
  const snap = await db.collection(BATCH_COL).doc(batchId).get();
  if (!snap.exists) {
    console.error('Batch topilmadi:', batchId);
    process.exit(1);
  }
  const changes = snap.data().changes || [];
  for (const c of changes) {
    await db.collection('ev_charging_stations').doc(c.stationId).update({ reportCount: c.before });
  }
  await snap.ref.update({ rolledBackAt: admin.firestore.FieldValue.serverTimestamp() });
  console.log(`Rollback: ${changes.length} ta stansiya eski qiymatiga qaytdi.`);
}

async function main() {
  if (ROLLBACK) return rollback(ROLLBACK);

  const stations = await db.collection('ev_charging_stations').where('reportCount', '>', 0).get();
  const plan = [];
  for (const s of stations.docs) {
    const reports = await s.ref.collection('reports').get();
    const open = reports.docs.filter((r) => (r.data() || {}).resolved !== true).length;
    const before = Number((s.data() || {}).reportCount) || 0;
    if (open !== before) plan.push({ stationId: s.id, before, after: open });
  }
  console.table(plan);
  console.log(`${stations.size} ta stansiya tekshirildi, ${plan.length} tasi o'zgaradi.`);
  if (!APPLY) {
    console.log('DRY-RUN: hech narsa yozilmadi. Yozish uchun --apply.');
    return;
  }

  const batchRef = db.collection(BATCH_COL).doc();
  const applied = [];
  for (const p of plan) {
    const ref = db.collection('ev_charging_stations').doc(p.stationId);
    // Qayta sanash tranzaksiyada — dry-run va apply orasida yangi shikoyat
    // kelgan bo'lsa, u ham hisobga olinadi.
    const res = await db.runTransaction(async (t) => {
      const [st, reports] = await Promise.all([t.get(ref), t.get(ref.collection('reports'))]);
      if (!st.exists) return null;
      const before = Number((st.data() || {}).reportCount) || 0;
      const after = reports.docs.filter((r) => (r.data() || {}).resolved !== true).length;
      if (before === after) return null;
      t.update(ref, { reportCount: after });
      return { stationId: p.stationId, before, after };
    });
    if (res) applied.push(res);
  }
  await batchRef.set({
    changes: applied,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    by: 'tool:reconcile_ev_report_count',
  });
  // Tekshiruv: yozilgan qiymatlar hozirgi ochiq shikoyatlarga teng.
  let mismatch = 0;
  for (const a of applied) {
    const st = await db.collection('ev_charging_stations').doc(a.stationId).get();
    if ((Number(st.data().reportCount) || 0) !== a.after) mismatch += 1;
  }
  console.log(`Yozildi: ${applied.length} ta. Batch: ${batchRef.id} (rollback: --rollback ${batchRef.id}).`);
  if (mismatch) console.warn(`DIQQAT: ${mismatch} ta stansiya qiymati tekshiruvda farq qildi (parallel yangilanish).`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
