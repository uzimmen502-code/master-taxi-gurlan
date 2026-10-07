/**
 * Capability API — HAQIQIY Firestore tranzaksiyasi bilan (Emulator, Admin SDK).
 *
 *   firebase emulators:exec --only firestore --project demo-caps-tx \
 *     "node functions_demand/test/capabilities_tx_emulator.test.js"
 *
 * Nega alohida (run_all.js da emas): sof testlardagi fake tranzaksiya
 * yozuvlarni oxiriga suradi va «yozuvdan KEYIN o'qish»ni ushlamaydi.
 * Haqiqiy SDK esa `Firestore transactions require all reads to be executed
 * before all writes` deb tashlaydi. `ensureAccountId` yangi foydalanuvchida
 * (`users.accountId` hali yo'q) aynan shu holatga tushardi: hisob ID yozilar,
 * keyin `provider_capabilities` o'qilardi — birinchi ariza hech qachon
 * o'tmasdi.
 *
 * Qulflanadi:
 *   - accountId'siz foydalanuvchi: requestCapability (courier, taxi),
 *     acceptServiceAgreement, T-6 migratsiya — muvaffaqiyatli
 *   - bir vaqtdagi ikki ariza → BITTA accountId (22-qoida)
 *   - adminGrantCapability (kuryer → approved) haqiqiy tranzaksiyada;
 *     ikki admin bir vaqtda bossa — bitta g'olib, audit ikki marta emas
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-caps-tx';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const caps = require('../core/capabilities');
const { makeRequestCapability } = require('../api/capabilities');
const { makeAcceptServiceAgreement } = require('../api/agreements');
const adminCaps = require('../api/admin_capabilities');

const A = '998901110001';
const B = '998901110002';
const ADMIN = '998909990000';
const NOW = new Date('2026-10-07T10:00:00.000Z');
const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => d.ref.delete()));
}
async function reset(seed = {}) {
  await Promise.all(['users', 'provider_capabilities', 'service_agreements',
    'capability_audit', 'drivers', 'settings'].map(wipe));
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await Promise.all(Object.entries(seed).map(([path, data]) => db.doc(path).set(data)));
}
const userDoc = async (id) => (await db.collection('users').doc(id).get()).data() || {};
const capDoc = async (id) => (await db.collection('provider_capabilities').doc(id).get()).data() || {};

(async () => {
  await check('requestCapability(courier): accountId\'siz foydalanuvchi → trial', async () => {
    await reset({ [`users/${A}`]: { phone: A } });
    const r = await makeRequestCapability({ db, now: () => NOW })({ service: 'courier' }, ctx(A));
    assert.strictEqual(r.status, caps.COURIER.trial);
    assert.ok(r.accountId.startsWith('acc'));
    assert.strictEqual((await userDoc(A)).accountId, r.accountId, 'users.accountId yozilgan');
    const cap = await capDoc(r.accountId);
    assert.strictEqual(cap.status.courier, caps.COURIER.trial);
    assert.strictEqual(cap.identity.primaryUid, A);
  });

  await check('requestCapability(taxi): accountId\'siz foydalanuvchi → starter', async () => {
    await reset({ [`users/${A}`]: { phone: A } });
    const r = await makeRequestCapability({ db, now: () => NOW })({ service: 'taxi' }, ctx(A));
    assert.strictEqual(r.status, caps.TAXI.starter);
    assert.strictEqual((await capDoc(r.accountId)).status.taxi, caps.TAXI.starter);
  });

  await check('requestCapability: users hujjati umuman yo\'q → yaratiladi + trial', async () => {
    await reset();
    const r = await makeRequestCapability({ db, now: () => NOW })({ service: 'courier' }, ctx(B));
    assert.strictEqual((await userDoc(B)).accountId, r.accountId);
  });

  await check('requestCapability: ikkinchi chaqiruv IDEMPOTENT, accountId o\'sha', async () => {
    await reset({ [`users/${A}`]: { phone: A } });
    const req = makeRequestCapability({ db, now: () => NOW });
    const r1 = await req({ service: 'courier' }, ctx(A));
    const r2 = await req({ service: 'courier' }, ctx(A));
    assert.strictEqual(r2.changed, false);
    assert.strictEqual(r2.accountId, r1.accountId);
  });

  await check('acceptServiceAgreement: accountId\'siz foydalanuvchi', async () => {
    await reset({ [`users/${A}`]: { phone: A } });
    const r = await makeAcceptServiceAgreement({ db, now: () => NOW })(
      { service: 'taxi', version: caps.AGREEMENT_VERSIONS.taxi }, ctx(A));
    assert.strictEqual(r.changed, true);
    assert.strictEqual((await userDoc(A)).accountId, r.accountId);
  });

  await check('T-6 migratsiya: accountId\'siz haydovchi xatosiz o\'tadi', async () => {
    await reset({ [`users/${A}`]: { phone: A }, [`drivers/${A}`]: { approved: true } });
    const r = await adminCaps.makeAdminMigrateTaxiDrivers({ db, now: () => NOW })({ dryRun: false }, ctx(ADMIN));
    assert.deepStrictEqual(r.errors, []);
    assert.strictEqual(r.migratedCount, 1);
  });

  await check('22-qoida: bir vaqtdagi ikki ariza → BITTA accountId', async () => {
    await reset({ [`users/${A}`]: { phone: A } });
    const req = makeRequestCapability({ db, now: () => NOW });
    const [r1, r2] = await Promise.all([
      req({ service: 'courier' }, ctx(A)),
      req({ service: 'taxi' }, ctx(A)),
    ]);
    assert.strictEqual(r1.accountId, r2.accountId);
    assert.strictEqual((await userDoc(A)).accountId, r1.accountId);
    const all = await db.collection('provider_capabilities').get();
    assert.strictEqual(all.size, 1, 'ikkinchi capability hujjati yaratilmagan');
  });

  await check('adminGrantCapability: accountId\'siz kuryer → approved, audit 2 qadam', async () => {
    await reset({ [`users/${A}`]: { phone: A } });
    const r = await adminCaps.makeAdminGrantCapability({ db, now: () => NOW })(
      { phone: A, service: 'courier', reason: 'test' }, ctx(ADMIN));
    assert.strictEqual(r.status, caps.COURIER.approved);
    assert.strictEqual((await userDoc(A)).accountId, r.accountId);
    assert.strictEqual((await capDoc(r.accountId)).status.courier, caps.COURIER.approved);
    const audit = await db.collection('capability_audit').get();
    assert.strictEqual(audit.size, 2);
  });

  await check('adminGrantCapability: ikki admin bir vaqtda bossa — bitta natija, audit 2 (4 emas)', async () => {
    await reset({ [`users/${A}`]: { phone: A } });
    const g = adminCaps.makeAdminGrantCapability({ db, now: () => NOW });
    const out = await Promise.allSettled([
      g({ phone: A, service: 'courier' }, ctx(ADMIN)),
      g({ phone: A, service: 'courier' }, ctx(ADMIN)),
    ]);
    const vals = out.filter((o) => o.status === 'fulfilled').map((o) => o.value);
    assert.strictEqual(vals.length, 2, out.map((o) => o.reason && o.reason.message).join(' | '));
    assert.deepStrictEqual(vals.map((v) => v.changed).sort(), [false, true]);
    assert.strictEqual(vals[0].accountId, vals[1].accountId);
    const audit = await db.collection('capability_audit').get();
    assert.strictEqual(audit.size, 2);
  });

  await check('D-15.3 AUTO: accountId\'siz kuryer → darhol approved + audit (haqiqiy tx)', async () => {
    await reset({ [`users/${A}`]: { phone: A } });
    await adminCaps.makeAdminSetCourierApprovalMode({ db, now: () => NOW })({ mode: 'auto' }, ctx(ADMIN));
    const r = await makeRequestCapability({ db, now: () => NOW })({ service: 'courier' }, ctx(A));
    assert.strictEqual(r.status, caps.COURIER.approved);
    assert.strictEqual((await capDoc(r.accountId)).status.courier, caps.COURIER.approved);
    const audit = await db.collection('capability_audit').where('kind', '==', 'auto_approve').get();
    assert.strictEqual(audit.size, 1);
  });

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi.`);
  process.exit(failed ? 1 : 0);
})();
