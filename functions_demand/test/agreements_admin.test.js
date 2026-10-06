/**
 * Kelishuvlar (D-SERVICE-2, D-TAXI-24) va admin capability amallari
 * (D-TAXI-4, T-6 migratsiya, 41-qoida audit).
 *
 *   node functions_demand/test/agreements_admin.test.js
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const caps = require('../core/capabilities');
const { makeAcceptServiceAgreement } = require('../api/agreements');
const admin = require('../api/admin_capabilities');
const { makeRequestCapability } = require('../api/capabilities');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const A = '998901110001';
const ADMIN = '998909990000';
const NOW = new Date('2026-10-06T10:00:00.000Z');
const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });

function makeDb(seed = {}) {
  const db = new FakeFirestore({ [`users/${ADMIN}`]: { role: 'admin' }, ...seed });
  db.runTransaction = async (fn) => {
    const tx = {
      get: (ref) => ref.get(),
      set: (ref, data, opts) => { tx._ops.push(() => ref.set(data, opts)); },
      update: (ref, data) => { tx._ops.push(() => ref.update(data)); },
      delete: (ref) => { tx._ops.push(() => ref.delete()); },
      _ops: [],
    };
    const out = await fn(tx);
    for (const op of tx._ops) await op();
    return out;
  };
  return db;
}
const capOf = (db, id) => db.dump('provider_capabilities')[id];

// ─── kelishuv ─────────────────────────────────────────────────────────
ok('kelishuv qabul: accountId yaratiladi, versiya yoziladi, idempotent', async () => {
  const db = makeDb({ [`users/${A}`]: {} });
  const accept = makeAcceptServiceAgreement({ db, now: () => NOW });
  const r1 = await accept({ service: 'taxi', version: caps.AGREEMENT_VERSIONS.taxi }, ctx(A));
  assert.strictEqual(r1.changed, true);
  assert.ok(r1.accountId.startsWith('acc'));
  const doc = db.dump('service_agreements')[r1.accountId];
  assert.strictEqual(doc.taxi.version, caps.AGREEMENT_VERSIONS.taxi);
  assert.strictEqual(doc.taxi.acceptedByUid, A);
  assert.strictEqual(caps.hasCurrentAgreement(doc, 'taxi'), true);
  assert.strictEqual(caps.hasCurrentAgreement(doc, 'courier'), false, 'har xizmatning o\'z kelishuvi');
  const r2 = await accept({ service: 'taxi', version: caps.AGREEMENT_VERSIONS.taxi }, ctx(A));
  assert.strictEqual(r2.changed, false);
  assert.strictEqual(r2.accountId, r1.accountId);
});
ok('eski versiyani qabul qilib bo\'lmaydi', async () => {
  const db = makeDb({ [`users/${A}`]: {} });
  await assert.rejects(
    () => makeAcceptServiceAgreement({ db })({ service: 'taxi', version: 0 }, ctx(A)),
    (e) => e.code === 'failed-precondition');
});
ok('kelishuv va capability bir xil accountId ga tushadi', async () => {
  const db = makeDb({ [`users/${A}`]: {} });
  const a = await makeAcceptServiceAgreement({ db, now: () => NOW })({ service: 'taxi', version: 1 }, ctx(A));
  const c = await makeRequestCapability({ db, now: () => NOW })({ service: 'taxi' }, ctx(A));
  assert.strictEqual(a.accountId, c.accountId);
});

// ─── kelishuv (D-TAXI-24.1): starter kelishuvsiz, 4 oydan keyin taqdim ──
ok('TAXI: kelishuvsiz ham `starter` BERILADI (D-TAXI-24.1, ega qarori)', async () => {
  const db = makeDb({ [`users/${A}`]: {} });
  const r = await makeRequestCapability({ db, now: () => NOW })({ service: 'taxi' }, ctx(A));
  assert.strictEqual(r.status, caps.TAXI.starter);
  assert.strictEqual(r.agreementRequired, undefined, 'starter da kelishuv taqdim qilinmaydi');
  assert.deepStrictEqual(db.dump('service_agreements'), {}, 'kelishuv hujjati yo\'q');
  assert.strictEqual(caps.AGREEMENT_GATED.taxi, false);
});
ok('TAXI: kelishuvdan KEYIN ham `starter` o\'sha-o\'sha', async () => {
  const db = makeDb({ [`users/${A}`]: {} });
  await makeAcceptServiceAgreement({ db, now: () => NOW })({ service: 'taxi', version: caps.AGREEMENT_VERSIONS.taxi }, ctx(A));
  const r = await makeRequestCapability({ db, now: () => NOW })({ service: 'taxi' }, ctx(A));
  assert.strictEqual(r.status, caps.TAXI.starter);
});
ok('D-TAXI-24.1: `verification_required` da requestCapability kelishuvni TAQDIM qiladi; qabul qilgach — yo\'q', async () => {
  const db = makeDb({ [`users/${A}`]: {} });
  const req = makeRequestCapability({ db, now: () => NOW });
  const first = await req({ service: 'taxi' }, ctx(A));
  await db.collection('provider_capabilities').doc(first.accountId)
    .set({ status: { taxi: caps.TAXI.verificationRequired } }, { merge: true });
  const due = await req({ service: 'taxi' }, ctx(A));
  assert.strictEqual(due.changed, false, 'ishlash huquqi o\'zgarmaydi (D-TAXI-5)');
  assert.strictEqual(due.status, caps.TAXI.verificationRequired);
  assert.strictEqual(due.agreementRequired, true);
  assert.strictEqual(due.agreementVersion, caps.AGREEMENT_VERSIONS.taxi);
  await makeAcceptServiceAgreement({ db, now: () => NOW })({ service: 'taxi', version: caps.AGREEMENT_VERSIONS.taxi }, ctx(A));
  const after = await req({ service: 'taxi' }, ctx(A));
  assert.strictEqual(after.agreementRequired, undefined);
});
ok('agreementDue: taksi — verification_required/verified HA, starter YO\'Q; boshqa xizmatlar YO\'Q', () => {
  assert.strictEqual(caps.agreementDue('taxi', 'starter'), false);
  assert.strictEqual(caps.agreementDue('taxi', 'verification_required'), true);
  assert.strictEqual(caps.agreementDue('taxi', 'verified'), true);
  assert.strictEqual(caps.agreementDue('taxi', 'suspended'), false);
  assert.strictEqual(caps.agreementDue('courier', 'approved'), false);
  assert.strictEqual(caps.agreementDue('seller', 'enabled'), false);
});
ok('kelishuv darvozasi hozir hech bir xizmatda yo\'q (matnlar kutilmoqda, 2-bis)', async () => {
  for (const s of caps.SERVICES) assert.strictEqual(caps.AGREEMENT_GATED[s], false, s);
  const db = makeDb({ [`users/${A}`]: {} });
  const r = await makeRequestCapability({ db, now: () => NOW })({ service: 'courier' }, ctx(A));
  assert.strictEqual(r.status, caps.COURIER.trial);
});

// ─── admin status ─────────────────────────────────────────────────────
async function withTaxi(db) {
  await makeAcceptServiceAgreement({ db, now: () => NOW })({ service: 'taxi', version: caps.AGREEMENT_VERSIONS.taxi }, ctx(A));
  const r = await makeRequestCapability({ db, now: () => NOW })({ service: 'taxi' }, ctx(A));
  return r.accountId;
}
ok('admin taksini `verified` qiladi + audit yoziladi (D-TAXI-4, 41-qoida)', async () => {
  const db = makeDb({ [`users/${A}`]: {} });
  const id = await withTaxi(db);
  const set = admin.makeAdminSetCapabilityStatus({ db, now: () => NOW });
  const r = await set({ accountId: id, service: 'taxi', status: 'verified', reason: 'hujjatlar to\'liq' }, ctx(ADMIN));
  assert.deepStrictEqual(r, { accountId: id, service: 'taxi', from: 'starter', to: 'verified' });
  assert.strictEqual(capOf(db, id).status.taxi, 'verified');
  assert.strictEqual(capOf(db, id).review.taxi.reviewedBy, ADMIN);
  const audit = Object.values(db.dump('capability_audit'));
  assert.strictEqual(audit.length, 1);
  assert.strictEqual(audit[0].by, ADMIN);
  assert.strictEqual(audit[0].from, 'starter');
});
ok('D-TAXI-24.1: admin `verified` — haydovchi kelishuvni qabul qilmagan bo\'lsa RAD (agreement_required)', async () => {
  const db = makeDb({ [`users/${A}`]: {} });
  const r0 = await makeRequestCapability({ db, now: () => NOW })({ service: 'taxi' }, ctx(A)); // kelishuvsiz starter
  const set = admin.makeAdminSetCapabilityStatus({ db, now: () => NOW });
  await assert.rejects(
    () => set({ accountId: r0.accountId, service: 'taxi', status: 'verified', reason: 'ok' }, ctx(ADMIN)),
    (e) => e.code === 'failed-precondition' && e.details && e.details.reason === 'agreement_required'
      && e.details.agreementVersion === caps.AGREEMENT_VERSIONS.taxi);
  assert.strictEqual(capOf(db, r0.accountId).status.taxi, 'starter', 'o\'zgarmagan');
  assert.deepStrictEqual(db.dump('capability_audit'), {}, 'rad etilgan amal auditga tushmaydi');
  // Kelishuvsiz `suspended` / `verification_required` — mumkin (pullik huquq emas).
  const s = await set({ accountId: r0.accountId, service: 'taxi', status: 'suspended', reason: 'shikoyat' }, ctx(ADMIN));
  assert.strictEqual(s.to, 'suspended');
  // Haydovchi qabul qildi → endi verified mumkin.
  await makeAcceptServiceAgreement({ db, now: () => NOW })({ service: 'taxi', version: caps.AGREEMENT_VERSIONS.taxi }, ctx(A));
  const v = await set({ accountId: r0.accountId, service: 'taxi', status: 'verified', reason: 'hujjatlar' }, ctx(ADMIN));
  assert.strictEqual(v.to, 'verified');
});
ok('telefon bo\'yicha ham topadi', async () => {
  const db = makeDb({ [`users/${A}`]: {} });
  await withTaxi(db);
  const r = await admin.makeAdminSetCapabilityStatus({ db, now: () => NOW })(
    { phone: A, service: 'taxi', status: 'suspended', reason: 'shikoyat' }, ctx(ADMIN));
  assert.strictEqual(r.to, 'suspended');
  assert.strictEqual(capOf(db, r.accountId).suspend.taxi.reason, 'shikoyat');
});
ok('NOTO\'G\'RI o\'tish rad: taksida `approved` yo\'q, `not_registered`dan suspend yo\'q', async () => {
  const db = makeDb({ [`users/${A}`]: {} });
  const id = await withTaxi(db);
  const set = admin.makeAdminSetCapabilityStatus({ db, now: () => NOW });
  await assert.rejects(() => set({ accountId: id, service: 'taxi', status: 'approved' }, ctx(ADMIN)), (e) => e.code === 'failed-precondition');
  await assert.rejects(() => set({ accountId: id, service: 'courier', status: 'suspended' }, ctx(ADMIN)), (e) => e.code === 'failed-precondition');
  assert.strictEqual(capOf(db, id).status.taxi, 'starter', 'o\'zgarmagan');
});
ok('oddiy foydalanuvchi admin amalini chaqira olmaydi', async () => {
  const db = makeDb({ [`users/${A}`]: { role: 'user' } });
  const id = await withTaxi(db);
  await assert.rejects(
    () => admin.makeAdminSetCapabilityStatus({ db })({ accountId: id, service: 'taxi', status: 'verified' }, ctx(A)),
    (e) => e.code === 'permission-denied');
});

// ─── T-6 migratsiya ───────────────────────────────────────────────────
const D1 = '998912778777';
const D2 = '903334455';
function driversSeed() {
  return {
    [`users/${D1}`]: { role: 'superadmin' },
    [`users/${D2}`]: { role: 'user' },
    [`drivers/${D1}`]: { approved: true, taxiTypes: ['intercity'] },
    [`drivers/${D2}`]: { approved: true, taxiType: 'marshrut' },
    'drivers/998905556677': { approved: false },
  };
}
ok('migratsiya dryRun STANDART: hech narsa yozilmaydi, ro\'yxat qaytadi', async () => {
  const db = makeDb(driversSeed());
  const r = await admin.makeAdminMigrateTaxiDrivers({ db, now: () => NOW })({}, ctx(ADMIN));
  assert.strictEqual(r.dryRun, true);
  assert.strictEqual(r.total, 2, 'faqat approved');
  assert.strictEqual(r.migrated.length, 2);
  assert.deepStrictEqual(db.dump('provider_capabilities'), {});
});
ok('migratsiya: verified + 4 oylik billing grace, starter EMAS (T-6)', async () => {
  const db = makeDb(driversSeed());
  const r = await admin.makeAdminMigrateTaxiDrivers({ db, now: () => NOW })({ dryRun: false }, ctx(ADMIN));
  assert.strictEqual(r.migratedCount, 2);
  const all = db.dump('provider_capabilities');
  for (const d of Object.values(all)) {
    assert.strictEqual(d.status.taxi, 'verified');
    assert.strictEqual(d.window.taxi.billingGraceUntil.toISOString(), '2027-02-06T10:00:00.000Z');
    assert.strictEqual(caps.isTaxiBillable(d, NOW), false, 'grace ichida bepul');
    assert.strictEqual(caps.isTaxiBillable(d, new Date('2027-03-01T00:00:00Z')), true);
    assert.strictEqual(caps.canPublishPaid(d, 'taxi'), true);
  }
  // 9 xonali drivers kaliti kanon primaryUid oladi.
  const d2 = Object.values(all).find((d) => d.identity.primaryUid === `998${D2}`);
  assert.ok(d2, '9 xonali haydovchi migratsiya qilinmagan');
  assert.strictEqual(db.dump('users')[D2].accountId, d2.identity.accountId);
  assert.strictEqual(Object.values(db.dump('capability_audit')).length, 2);
});
ok('migratsiya IDEMPOTENT: ikkinchi marta skip, grace qayta yozilmaydi', async () => {
  const db = makeDb(driversSeed());
  const run = admin.makeAdminMigrateTaxiDrivers({ db, now: () => NOW });
  await run({ dryRun: false }, ctx(ADMIN));
  const later = admin.makeAdminMigrateTaxiDrivers({ db, now: () => new Date('2026-12-01T00:00:00Z') });
  const r = await later({ dryRun: false }, ctx(ADMIN));
  assert.strictEqual(r.migratedCount, 0);
  assert.strictEqual(r.skipped.length, 2);
  for (const d of Object.values(db.dump('provider_capabilities'))) {
    assert.strictEqual(d.window.taxi.billingGraceUntil.toISOString(), '2027-02-06T10:00:00.000Z');
  }
});

(async () => {
  for (const t of tests) {
    try { await t.fn(); passed += 1; console.log(`  OK  ${t.name}`); } catch (e) {
      console.error(`  XATO ${t.name}\n       ${e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
