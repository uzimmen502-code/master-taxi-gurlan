/**
 * «Ҳайдовчи роли» 2–3-босқич (эга, 2026-10-17). HAQIQIY Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-legacy-role \
 *     "node functions/test/legacy_driver_role_cf.test.js"
 *
 *   A  эски тасдиқ йўли (`autoApproveDriverApplication`) энди `users.role = driver` ЁЗМАЙДИ
 *   B  тозалаш асбоби: dry-run ҳеч нарса ёзмайди; ҳуқуқли/ҳуқуқсиз таснифи
 *   C  apply: фақат ҳуқуқли `driver` → `user`; admin/dispatcher/courier/user тегилмайди
 *   D  --include-no-capability: ҳуқуқсизлар ҳам; backup ёзилади; идемпотент
 *   E  rollback: фақат шу batch туширганни қайтаради (бошқа сабабдан `user` бўлганни эмас)
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-legacy-role';
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.FIREBASE_STORAGE_EMULATOR_HOST = process.env.FIREBASE_STORAGE_EMULATOR_HOST || '127.0.0.1:1';

const fns = require('../index.js');
const admin = require('firebase-admin');
const db = admin.firestore();
const tool = require('../tools/cleanup_legacy_driver_role');

const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};

async function wipe() {
  for (const col of ['users', 'provider_capabilities', 'users_role_cleanup', 'driver_requests', 'drivers', 'settings']) {
    const s = await db.collection(col).get();
    await Promise.all(s.docs.map(async (d) => {
      const subs = await d.ref.listCollections();
      for (const sc of subs) {
        const ss = await sc.get();
        await Promise.all(ss.docs.map((x) => x.ref.delete()));
      }
      await d.ref.delete();
    }));
  }
}
async function user(phone, role, { cap } = {}) {
  const acc = `acc_${phone}`;
  await db.collection('users').doc(phone).set({ phone, role, ...(cap ? { accountId: acc } : {}) });
  if (cap) {
    await db.collection('provider_capabilities').doc(acc).set({
      identity: { primaryUid: phone }, status: { taxi: cap.status }, taxi: { taxiTypes: cap.types },
    });
  }
}
const roleOf = async (p) => (await db.collection('users').doc(p).get()).data().role;

(async () => {
  await check('A autoApproveDriverApplication role ni driver QILMAYDI (user qoladi)', async () => {
    await wipe();
    const P = '998905550001';
    await db.collection('users').doc(P).set({ phone: P, role: 'user' });
    await db.collection('settings').doc('app').set({ driverApprovalMode: 'auto' });
    const r = await fns.autoApproveDriverApplication.run({
      uid: P, phone: P, name: 'Test', car: 'Cobalt', plate: '01A123BC', taxiType: 'local',
    }, ctxOf(P));
    assert.ok(r && r.ok !== false);
    assert.strictEqual(await roleOf(P), 'user');
    const drv = (await db.collection('drivers').doc(P).get()).data();
    assert.strictEqual(drv.approved, true, 'drivers profili oldingidek yoziladi');
  });

  const SET = async () => {
    await wipe();
    await user('998905550011', 'driver', { cap: { status: 'starter', types: ['local'] } });
    await user('998905550012', 'driver', { cap: { status: 'verified', types: ['intercity'] } });
    await user('998905550013', 'driver'); // huquqsiz (capability yo'q)
    await user('998905550014', 'driver', { cap: { status: 'suspended', types: ['local'] } }); // ishlamaydi
    await user('998905550015', 'admin', { cap: { status: 'starter', types: ['local'] } });
    await user('998905550016', 'dispatcher');
    await user('998905550017', 'courier');
    await user('998905550018', 'user');
  };

  await check('B dry-run: hech narsa yozmaydi, tasnif togri', async () => {
    await SET();
    const p = await tool.planCleanup(db);
    assert.deepStrictEqual(p.withCapability.sort(), ['998905550011', '998905550012']);
    assert.deepStrictEqual(p.withoutCapability.sort(), ['998905550013', '998905550014']);
    assert.deepStrictEqual(p.ids.sort(), ['998905550011', '998905550012']);
    assert.strictEqual(p.scanned, 4);
    assert.strictEqual(await roleOf('998905550011'), 'driver');
    assert.strictEqual((await db.collection('users_role_cleanup').get()).size, 0);
  });

  await check('C apply (standart): faqat huquqli driver -> user; boshqa rollar teginilmaydi', async () => {
    await SET();
    const r = await tool.applyCleanup(db, admin, { log: () => {} });
    assert.strictEqual(r.written, 2);
    assert.strictEqual(r.remaining, 0);
    assert.strictEqual(await roleOf('998905550011'), 'user');
    assert.strictEqual(await roleOf('998905550012'), 'user');
    assert.strictEqual(await roleOf('998905550013'), 'driver', 'huquqsiz tegilmaydi');
    assert.strictEqual(await roleOf('998905550014'), 'driver', 'suspended tegilmaydi');
    assert.strictEqual(await roleOf('998905550015'), 'admin');
    assert.strictEqual(await roleOf('998905550016'), 'dispatcher');
    assert.strictEqual(await roleOf('998905550017'), 'courier');
    assert.strictEqual(await roleOf('998905550018'), 'user');
  });

  await check('C2 idempotent: ikkinchi apply 0 yozadi', async () => {
    const r = await tool.applyCleanup(db, admin, { log: () => {} });
    assert.strictEqual(r.planned, 0);
    assert.strictEqual(r.written, 0);
  });

  await check('D --include-no-capability: huquqsizlar ham; backup (Firestore + fayl)', async () => {
    await SET();
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'rolebak-'));
    const r = await tool.applyCleanup(db, admin, { includeNoCapability: true, log: () => {}, backupDir: dir });
    assert.strictEqual(r.written, 4);
    assert.strictEqual(await roleOf('998905550013'), 'user');
    assert.strictEqual(await roleOf('998905550015'), 'admin');
    const head = (await db.collection('users_role_cleanup').doc(r.batchId).get()).data();
    assert.strictEqual(head.status, 'done');
    assert.strictEqual(head.total, 4);
    const chunk = (await db.collection('users_role_cleanup').doc(r.batchId).collection('chunks').get()).docs[0].data();
    assert.strictEqual(chunk.ids.length, 4);
    const file = JSON.parse(fs.readFileSync(r.localFile, 'utf8'));
    assert.strictEqual(file.ids.length, 4);
    assert.strictEqual(file.previousRole, 'driver');
  });

  await check('E rollback: faqat shu batch tushirganni qaytaradi', async () => {
    await SET();
    const r = await tool.applyCleanup(db, admin, { includeNoCapability: true, log: () => {} });
    // Batchdan KEYIN kimdir ozi (boshqa sabab) user qilgan: roleCleanupBatch yoq.
    await db.collection('users').doc('998905550018').set({ role: 'user' }, { merge: true });
    // Va bitta driver ni qo'lda boshqa rolga o'zgartirgan.
    await db.collection('users').doc('998905550011').update({ role: 'dispatcher' });
    const rb = await tool.rollbackCleanup(db, admin, r.batchId);
    assert.strictEqual(rb.reverted, 3); // 4 tadan 1 tasi dispatcher bo'lib ketgan
    assert.strictEqual(await roleOf('998905550012'), 'driver');
    assert.strictEqual(await roleOf('998905550013'), 'driver');
    assert.strictEqual(await roleOf('998905550014'), 'driver');
    assert.strictEqual(await roleOf('998905550011'), 'dispatcher', 'boshqa rolga teginilmaydi');
    assert.strictEqual(await roleOf('998905550018'), 'user');
    const u = (await db.collection('users').doc('998905550012').get()).data();
    assert.strictEqual(u.roleCleanupBatch, undefined, 'belgi olib tashlanadi');
  });

  await check('E2 rollback: noma\'lum batch — xato', async () => {
    let err = null;
    try { await tool.rollbackCleanup(db, admin, 'yoq'); } catch (e) { err = e; }
    assert.ok(err);
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
