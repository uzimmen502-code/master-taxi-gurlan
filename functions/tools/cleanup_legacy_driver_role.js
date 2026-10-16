#!/usr/bin/env node
/**
 * Эски `users.role == 'driver'` белгисини тозалаш (эга қарори 2026-10-17,
 * «ҳайдовчи роли» 3-босқич).
 *
 * Нега: ҳайдовчилик ҲУҚУҚИ `provider_capabilities`да; `role: driver` — эски
 * "ариза → админ тасдиғи" оқимининг қолдиғи. Янги оқим уни ёзмайди (2-босқич),
 * аудитория ҳуқуқдан аниқланади (1-босқич). Бу асбоб қолган эски белгини `user`
 * га тушаради.
 *
 *   node functions/tools/cleanup_legacy_driver_role.js                 # DRY-RUN (ҳеч нарса ёзмайди)
 *   node functions/tools/cleanup_legacy_driver_role.js --apply         # ёзади (backup билан)
 *   node functions/tools/cleanup_legacy_driver_role.js --apply --include-no-capability
 *   node functions/tools/cleanup_legacy_driver_role.js --rollback <batchId>
 *
 * Хавфсизлик:
 *  - фақат `role == 'driver'` бўлган ҳужжат; `admin`/`dispatcher`/`superadmin` ВА БОШҚА
 *    рол ҲЕЧ ҚАЧОН тегилмайди (сўров ўзи фақат driver ни олади + ёзишдан олдин қайта текширилади);
 *  - стандарт режимда фақат ҲУҚУҚЛИ ҳайдовчилар (capability'си ишлайдиган ва тури бор) тозаланади;
 *    ҳуқуқсиз эски ҳайдовчилар `--include-no-capability` билан ҳам тозаланади (аввал dry-run
 *    ҳисоботида алоҳида санаб кўрсатилади);
 *  - backup: `users_role_cleanup/{batchId}` (+ `chunks/*` да uid рўйхати) ВА маҳаллий JSON
 *    (`functions/tools/backup/…`) — ёзишдан ОЛДИН;
 *  - ёзиш 400 талик batch'лар, прогресс, охирида текширув (қолган сони);
 *  - rollback: backup рўйхатидан, фақат ҳозир `user` бўлганларни `driver` га қайтаради.
 */
'use strict';

const PAGE = 500;
const WRITE_BATCH = 400;
const CHUNK = 2000;
const BACKUP_COL = 'users_role_cleanup';
const TAXI_WORKING = ['starter', 'verification_required', 'verified'];

/** Ҳуқуқли ҳайдовчи: capability ишлайдиган ҳолатда ва камида битта тур эълон қилинган. */
function isCapabilityDriver(cap) {
  if (!cap) return false;
  const st = ((cap.status || {}).taxi) || '';
  const types = Array.isArray((cap.taxi || {}).taxiTypes) ? cap.taxi.taxiTypes : [];
  return TAXI_WORKING.includes(st) && types.length > 0;
}

/** `users` ичидан `role == driver` ни саҳифалаб ўқиб, ҳуқуқ бўйича таснифлайди. */
async function planCleanup(db, { includeNoCapability = false } = {}) {
  const withCap = [];
  const noCap = [];
  let scanned = 0;
  let last = null;
  for (;;) {
    let q = db.collection('users').where('role', '==', 'driver')
      .orderBy('__name__').limit(PAGE);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    const caps = await Promise.all(snap.docs.map(async (d) => {
      const acc = String((d.data() || {}).accountId || '');
      if (!acc) return null;
      const c = await db.collection('provider_capabilities').doc(acc).get();
      return c.exists ? c.data() : null;
    }));
    snap.docs.forEach((d, i) => {
      scanned += 1;
      (isCapabilityDriver(caps[i]) ? withCap : noCap).push(d.id);
    });
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE) break;
  }
  return {
    scanned,
    withCapability: withCap,
    withoutCapability: noCap,
    ids: includeNoCapability ? [...withCap, ...noCap] : withCap,
  };
}

async function applyCleanup(db, admin, { includeNoCapability = false, log = console.log, backupDir } = {}) {
  const plan = await planCleanup(db, { includeNoCapability });
  const { ids } = plan;
  const batchRef = db.collection(BACKUP_COL).doc();
  // 1) АВВАЛ backup: Firestore (uid рўйхати) ва маҳаллий файл.
  for (let i = 0; i < ids.length; i += CHUNK) {
    await batchRef.collection('chunks').doc(String(i / CHUNK)).set({ ids: ids.slice(i, i + CHUNK) });
  }
  await batchRef.set({
    total: ids.length,
    withCapability: plan.withCapability.length,
    withoutCapability: plan.withoutCapability.length,
    includeNoCapability,
    status: 'writing',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    by: 'tool:cleanup_legacy_driver_role',
  });
  let localFile = '';
  if (backupDir) {
    const fs = require('fs');
    const path = require('path');
    fs.mkdirSync(backupDir, { recursive: true });
    localFile = path.join(backupDir, `users_role_cleanup_${batchRef.id}.json`);
    fs.writeFileSync(localFile, JSON.stringify({
      batchId: batchRef.id, previousRole: 'driver', ids,
      withoutCapability: plan.withoutCapability,
    }, null, 2));
  }
  // 2) Ёзиш: ҳар ҳужжат ёзишдан олдин қайта текширилади (ораликда ким ўзгартирган бўлса тегмаймиз).
  let written = 0;
  for (let i = 0; i < ids.length; i += WRITE_BATCH) {
    const part = ids.slice(i, i + WRITE_BATCH);
    const snaps = await db.getAll(...part.map((id) => db.collection('users').doc(id)));
    const batch = db.batch();
    let n = 0;
    for (const s of snaps) {
      if (!s.exists || (s.data() || {}).role !== 'driver') continue;
      batch.update(s.ref, {
        role: 'user',
        roleCleanupAt: admin.firestore.FieldValue.serverTimestamp(),
        roleCleanupBatch: batchRef.id,
      });
      n += 1;
    }
    if (n > 0) await batch.commit();
    written += n;
    log(`… ${Math.min(i + WRITE_BATCH, ids.length)}/${ids.length}`);
  }
  // 3) Текширув.
  const after = await planCleanup(db, { includeNoCapability });
  await batchRef.set({ status: 'done', written, remaining: after.ids.length }, { merge: true });
  return {
    batchId: batchRef.id, planned: ids.length, written,
    remaining: after.ids.length, localFile,
  };
}

async function rollbackCleanup(db, admin, batchId) {
  const ref = db.collection(BACKUP_COL).doc(batchId);
  const head = await ref.get();
  if (!head.exists) throw new Error(`batch topilmadi: ${batchId}`);
  const chunks = await ref.collection('chunks').get();
  let reverted = 0;
  for (const c of chunks.docs) {
    const ids = (c.data() || {}).ids || [];
    for (let i = 0; i < ids.length; i += WRITE_BATCH) {
      const part = ids.slice(i, i + WRITE_BATCH);
      const snaps = await db.getAll(...part.map((id) => db.collection('users').doc(id)));
      const batch = db.batch();
      let n = 0;
      for (const s of snaps) {
        const d = s.exists ? (s.data() || {}) : {};
        // Фақат бизнинг batch тушурган ва ҳозир ҳам `user` бўлганни қайтарамиз.
        if (!s.exists || d.role !== 'user' || d.roleCleanupBatch !== batchId) continue;
        batch.update(s.ref, {
          role: 'driver',
          roleCleanupAt: admin.firestore.FieldValue.delete(),
          roleCleanupBatch: admin.firestore.FieldValue.delete(),
        });
        n += 1;
      }
      if (n > 0) await batch.commit();
      reverted += n;
    }
  }
  await ref.set({
    rolledBackAt: admin.firestore.FieldValue.serverTimestamp(), reverted,
  }, { merge: true });
  return { reverted };
}

module.exports = { isCapabilityDriver, planCleanup, applyCleanup, rollbackCleanup, TAXI_WORKING };

if (require.main === module) {
  const fs = require('fs');
  const path = require('path');
  const admin = require('firebase-admin');
  const args = process.argv.slice(2);
  const APPLY = args.includes('--apply');
  const INCLUDE = args.includes('--include-no-capability');
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
      const r = await rollbackCleanup(db, admin, ROLLBACK);
      console.log(`Rollback: ${r.reverted} ta hujjatda role 'driver' qaytarildi.`);
      return;
    }
    if (!APPLY) {
      const p = await planCleanup(db, { includeNoCapability: INCLUDE });
      console.log('DRY-RUN (hech narsa yozilmadi)');
      console.log(`  role == driver:               ${p.scanned}`);
      console.log(`  huquqli (capability bor):     ${p.withCapability.length}`);
      console.log(`  huquqsiz (capability yoq):    ${p.withoutCapability.length}`);
      console.log(`  tozalanadi (shu rejimda):     ${p.ids.length}`);
      if (p.withoutCapability.length > 0 && !INCLUDE) {
        console.log('  ESLATMA: huquqsizlar tegilmaydi (--include-no-capability bilan tozalanadi).');
      }
      return;
    }
    const r = await applyCleanup(db, admin, {
      includeNoCapability: INCLUDE,
      backupDir: path.join(__dirname, 'backup'),
    });
    console.log(`Tayyor: batch=${r.batchId} rejalangan=${r.planned} yozildi=${r.written} qoldi=${r.remaining}`);
    console.log(`Backup fayli: ${r.localFile}`);
    console.log(`Rollback: node functions/tools/cleanup_legacy_driver_role.js --rollback ${r.batchId}`);
  })().catch((e) => { console.error(e); process.exit(1); });
}
