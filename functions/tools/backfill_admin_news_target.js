#!/usr/bin/env node
/**
 * `admin_news` — умумий хабарларга `targetUserId: ''` (админ аудити O-4,
 * 2026-10-08).
 *
 * Нега: `admin_news` ўқиш қоидаси ҳозир `if true` — шахсий чеклар (манзил,
 * сумма, буюртма) ҳаммага очиқ. Ёпиш режаси: илова умумий хабарларни
 * `where('targetUserId', '==', '')` билан сўрайди (шахсийлари аллақачон
 * `whereIn` aliases билан), кейин rules `list`ни шу шарт билан чеклайди.
 * Firestore тенглик сўрови майдони ЙЎҚ ҳужжатни қайтармайди — шунинг учун
 * эски умумий хабарларга майдон қўшиш керак. Янгиларини `onAdminNewsCreate`
 * нормаллаштиради.
 *
 *   node functions/tools/backfill_admin_news_target.js            # DRY-RUN
 *   node functions/tools/backfill_admin_news_target.js --apply    # ёзади
 *   node functions/tools/backfill_admin_news_target.js --rollback <batchId>
 *
 * Хавфсизлик: фақат `targetUserId` майдони ЙЎҚ ёки `null` ҳужжатлар
 * ўзгаради (шахсий хабарга тегилмайди); ўзгарган ID'лар
 * `admin_news_backfill/{batchId}/chunks/*` да (rollback шу ердан, фақат
 * қиймат ҳали '' бўлса майдон ўчирилади). Ўқиш саҳифалаб (500), ёзиш
 * 400 талик batch'ларда; охирида текширув.
 */
'use strict';

const PAGE = 500;
const WRITE_BATCH = 400;
const CHUNK = 2000;
const BACKUP_COL = 'admin_news_backfill';

function needsTarget(data) {
  return data.targetUserId === undefined || data.targetUserId === null;
}

/** Барча `admin_news` ни саҳифалаб ўқиб, майдони йўқларини қайтаради. */
async function planBackfill(db) {
  const ids = [];
  let scanned = 0;
  let last = null;
  for (;;) {
    let q = db.collection('admin_news').orderBy('__name__').limit(PAGE);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const d of snap.docs) {
      scanned += 1;
      if (needsTarget(d.data() || {})) ids.push(d.id);
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE) break;
  }
  return { scanned, ids };
}

async function applyBackfill(db, admin, { log = console.log } = {}) {
  const { scanned, ids } = await planBackfill(db);
  const batchRef = db.collection(BACKUP_COL).doc();
  // Аввал захира (ID рўйхати), кейин ёзув — ярим йўлда тўхтаса ҳам rollback бор.
  for (let i = 0; i < ids.length; i += CHUNK) {
    await batchRef.collection('chunks').doc(String(i / CHUNK)).set({ ids: ids.slice(i, i + CHUNK) });
  }
  await batchRef.set({
    total: ids.length, scanned, status: 'writing',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    by: 'tool:backfill_admin_news_target',
  });
  let written = 0;
  for (let i = 0; i < ids.length; i += WRITE_BATCH) {
    const part = ids.slice(i, i + WRITE_BATCH);
    const snaps = await db.getAll(...part.map((id) => db.collection('admin_news').doc(id)));
    const batch = db.batch();
    let n = 0;
    for (const s of snaps) {
      // Ўқиш ва ёзиш орасида кимдир майдон қўйган бўлса — тегмаймиз.
      if (!s.exists || !needsTarget(s.data() || {})) continue;
      batch.update(s.ref, { targetUserId: '' });
      n += 1;
    }
    if (n > 0) await batch.commit();
    written += n;
    log(`… ${Math.min(i + WRITE_BATCH, ids.length)}/${ids.length}`);
  }
  // Текширув: майдони йўқ ҳужжат қолмади.
  const after = await planBackfill(db);
  await batchRef.set({ status: 'done', written, remaining: after.ids.length }, { merge: true });
  return { batchId: batchRef.id, scanned, planned: ids.length, written, remaining: after.ids.length };
}

async function rollbackBackfill(db, admin, batchId) {
  const ref = db.collection(BACKUP_COL).doc(batchId);
  const head = await ref.get();
  if (!head.exists) throw new Error(`batch topilmadi: ${batchId}`);
  const chunks = await ref.collection('chunks').get();
  let reverted = 0;
  for (const c of chunks.docs) {
    const ids = (c.data() || {}).ids || [];
    for (let i = 0; i < ids.length; i += WRITE_BATCH) {
      const part = ids.slice(i, i + WRITE_BATCH);
      const snaps = await db.getAll(...part.map((id) => db.collection('admin_news').doc(id)));
      const batch = db.batch();
      let n = 0;
      for (const s of snaps) {
        if (!s.exists || (s.data() || {}).targetUserId !== '') continue;
        batch.update(s.ref, { targetUserId: admin.firestore.FieldValue.delete() });
        n += 1;
      }
      if (n > 0) await batch.commit();
      reverted += n;
    }
  }
  await ref.set({ rolledBackAt: admin.firestore.FieldValue.serverTimestamp(), reverted }, { merge: true });
  return { reverted };
}

module.exports = { planBackfill, applyBackfill, rollbackBackfill, needsTarget };

if (require.main === module) {
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
  (async () => {
    if (ROLLBACK) {
      const r = await rollbackBackfill(db, admin, ROLLBACK);
      console.log(`Rollback: ${r.reverted} ta hujjatdan targetUserId olib tashlandi.`);
      return;
    }
    if (!APPLY) {
      const { scanned, ids } = await planBackfill(db);
      console.log(`DRY-RUN: ${scanned} ta hujjat, ${ids.length} tasiga targetUserId: '' qo'shiladi.`);
      console.log('Namuna:', ids.slice(0, 10).join(', '));
      console.log('Yozish uchun --apply.');
      return;
    }
    const r = await applyBackfill(db, admin);
    console.log(`Yozildi: ${r.written}/${r.planned}. Qoldi: ${r.remaining}. Batch: ${r.batchId} (rollback: --rollback ${r.batchId}).`);
  })().catch((e) => { console.error(e); process.exit(1); });
}
