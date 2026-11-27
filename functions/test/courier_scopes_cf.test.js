/**
 * Kuryer toifalari — HAQIQIY `functions/index.js` (Emulator, `.run`), `courier_scopes.js`.
 *
 *   firebase emulators:exec --only firestore --project demo-courier-scopes \
 *     "node functions/test/courier_scopes_cf.test.js"
 *
 * Qulflanadi (ega qarorlari 2026-10-31):
 *   - «Туман» darhol; viloyat/respublika — mashina + hujjat shart (SCOPE_REQUIREMENTS_MISSING);
 *   - Мануал (standart) → pending; Авто → darhol approved; tasdiqlanganini qayta so'rash o'zgartirmaydi;
 *   - admin approve/reject (reject — sabab shart), audit yozuvlari; oddiy foydalanuvchi admin callable'ni chaqirolmaydi;
 *   - ishlamayotgan (suspended) kuryer toifa so'rolmaydi; noto'g'ri toifa — invalid-argument.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-courier-scopes';

const fns = require('../index');
const admin = require('firebase-admin');
const db = admin.firestore();
const pure = require('../courier_scopes');

const COURIER = '998901240001';
const NO_CAR = '998901240002';
const SUSPENDED = '998901240003';
const ADMIN = '998901240009';
const USER = '998901240010';

const ctx = (phone) => ({ auth: { uid: phone, token: { phone_number: `+${phone}` } } });
const call = (name, data, phone) => fns[name].run(data, ctx(phone));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
const err = (code, msg) => (e) => e.code === code && (!msg || e.message === msg);

async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => d.ref.delete()));
}
const CAR = { vehicleType: 'car', carPlate: '90A123BC', carModel: 'Cobalt', driverLicenseNo: 'AF1234567' };
async function reset() {
  await Promise.all(['users', 'provider_capabilities', 'courier_documents', 'settings',
    'capability_audit', 'admin_audit'].map(wipe));
  const docs = {
    [`users/${COURIER}`]: { accountId: 'accC' },
    'provider_capabilities/accC': { status: { courier: 'approved' }, identity: { primaryUid: COURIER } },
    [`courier_documents/${COURIER}`]: CAR,
    [`users/${NO_CAR}`]: { accountId: 'accN' },
    'provider_capabilities/accN': { status: { courier: 'trial' }, identity: { primaryUid: NO_CAR } },
    [`courier_documents/${NO_CAR}`]: { vehicleType: 'bike' },
    [`users/${SUSPENDED}`]: { accountId: 'accS' },
    'provider_capabilities/accS': { status: { courier: 'suspended' } },
    [`courier_documents/${SUSPENDED}`]: CAR,
    [`users/${ADMIN}`]: { role: 'admin' },
    [`users/${USER}`]: { role: 'user' },
  };
  await Promise.all(Object.entries(docs).map(([p, d]) => db.doc(p).set(d)));
}
const cap = async (id) => (await db.doc(`provider_capabilities/${id}`).get()).data();
const count = async (col) => (await db.collection(col).get()).size;

(async () => {
  await check('sof: requestedScopes / isScopeActive / missingRequirements / parseScopes', async () => {
    assert.deepStrictEqual(pure.requestedScopes({}), ['district']);
    assert.deepStrictEqual(pure.requestedScopes({ courier: { scopes: ['republic', 'x', 'district'] } }),
      ['district', 'republic']);
    assert.strictEqual(pure.isScopeActive({ courier: { scopes: ['region'] } }, 'region'), false);
    assert.strictEqual(pure.isScopeActive({ courier: { scopes: ['region'] },
      review: { courierScopes: { region: { status: 'approved' } } } }, 'region'), true);
    assert.strictEqual(pure.isScopeActive({ review: { courierScopes: { region: { status: 'approved' } } } },
      'region'), false, 'tanlanmagan bo\'lsa tasdiq yetmaydi');
    assert.deepStrictEqual(pure.missingRequirements(CAR), []);
    assert.deepStrictEqual(pure.missingRequirements({ vehicleType: 'car', carPlate: ' ' }),
      ['carPlate', 'carModel', 'driverLicenseNo']);
    assert.strictEqual(pure.parseScopes([]).error, 'SCOPES_INVALID');
    assert.strictEqual(pure.parseScopes(['city']).error, 'SCOPES_INVALID');
    assert.deepStrictEqual(pure.parseScopes(['region', 'district', 'region']).scopes, ['district', 'region']);
    assert.strictEqual(pure.approvalModeOf({ scopeApprovalMode: 'AUTO' }), 'manual');
  });

  await reset();
  await check('«Туман» — darhol, audit yozuvi yo\'q', async () => {
    const r = await call('courierRequestScopes', { scopes: ['district'] }, COURIER);
    assert.deepStrictEqual(r.scopes, ['district']);
    assert.deepStrictEqual(r.review, {});
    assert.deepStrictEqual((await cap('accC')).courier.scopes, ['district']);
    assert.strictEqual(await count('capability_audit'), 0);
  });

  await check('Мануал (standart): viloyat → pending; qayta so\'rov — idempotent (audit 1 ta)', async () => {
    const r = await call('courierRequestScopes', { scopes: ['district', 'region'] }, COURIER);
    assert.strictEqual(r.mode, 'manual');
    assert.strictEqual(r.review.region, 'pending');
    await call('courierRequestScopes', { scopes: ['district', 'region'] }, COURIER);
    assert.strictEqual((await cap('accC')).review.courierScopes.region.status, 'pending');
    assert.strictEqual(await count('capability_audit'), 1);
  });

  await check('mashinasiz kuryer: viloyat/respublika — SCOPE_REQUIREMENTS_MISSING, hech narsa yozilmaydi', async () => {
    await assert.rejects(() => call('courierRequestScopes', { scopes: ['republic'] }, NO_CAR),
      (e) => err('failed-precondition', 'SCOPE_REQUIREMENTS_MISSING')(e)
        && e.details.missing.includes('vehicleType'));
    assert.strictEqual((await cap('accN')).courier, undefined);
  });

  await check('suspended — so\'rolmaydi; noto\'g\'ri toifa — invalid-argument; tokensiz — unauthenticated', async () => {
    await assert.rejects(() => call('courierRequestScopes', { scopes: ['district'] }, SUSPENDED),
      err('permission-denied', 'COURIER_NOT_WORKING'));
    await assert.rejects(() => call('courierRequestScopes', { scopes: ['city'] }, COURIER),
      err('invalid-argument', 'SCOPES_INVALID'));
    await assert.rejects(() => fns.courierRequestScopes.run({ scopes: ['district'] }, {}),
      err('unauthenticated'));
    await assert.rejects(() => call('courierRequestScopes', { scopes: ['district'] }, USER),
      err('failed-precondition', 'NOT_A_COURIER'));
  });

  await check('admin ro\'yxati: pending so\'rov + mashina ma\'lumoti; oddiy user — rad', async () => {
    const r = await call('adminListCourierScopeRequests', {}, ADMIN);
    assert.strictEqual(r.items.length, 1);
    assert.strictEqual(r.items[0].accountId, 'accC');
    assert.strictEqual(r.items[0].requests.region.status, 'pending');
    assert.strictEqual(r.items[0].vehicle.carModel, 'Cobalt');
    await assert.rejects(() => call('adminListCourierScopeRequests', {}, USER), err('permission-denied'));
  });

  await check('admin reject — sabab shart; approve → faol; audit + admin_audit', async () => {
    await assert.rejects(() => call('adminDecideCourierScope',
      { accountId: 'accC', scope: 'region', decision: 'reject' }, ADMIN), err('invalid-argument', 'REASON_REQUIRED'));
    await assert.rejects(() => call('adminDecideCourierScope',
      { accountId: 'accC', scope: 'region', decision: 'approve' }, USER), err('permission-denied'));
    await assert.rejects(() => call('adminDecideCourierScope',
      { accountId: 'accC', scope: 'republic', decision: 'approve' }, ADMIN),
    err('failed-precondition', 'NO_SCOPE_REQUEST'));
    const r = await call('adminDecideCourierScope', { accountId: 'accC', scope: 'region', decision: 'approve' }, ADMIN);
    assert.strictEqual(r.status, 'approved');
    const c = await cap('accC');
    assert.strictEqual(pure.isScopeActive(c, 'region'), true);
    assert.strictEqual(c.review.courierScopes.region.decidedBy, ADMIN);
    assert.strictEqual(await count('admin_audit'), 1);
    const again = await call('adminDecideCourierScope', { accountId: 'accC', scope: 'region', decision: 'approve' }, ADMIN);
    assert.strictEqual(again.unchanged, true);
    assert.strictEqual(await count('admin_audit'), 1);
  });

  await check('tasdiqlangan viloyat — kuryer qayta so\'rasa ham approved qoladi', async () => {
    const r = await call('courierRequestScopes', { scopes: ['region'] }, COURIER);
    assert.strictEqual(r.review.region, 'approved');
    assert.deepStrictEqual((await cap('accC')).courier.scopes, ['region']);
  });

  await check('Авто/Мануал: faqat admin; auto → respublika darhol approved', async () => {
    await assert.rejects(() => call('adminSetCourierScopeApprovalMode', { mode: 'auto' }, USER),
      err('permission-denied'));
    await assert.rejects(() => call('adminSetCourierScopeApprovalMode', { mode: 'fast' }, ADMIN),
      err('invalid-argument', 'MODE_INVALID'));
    const m = await call('adminSetCourierScopeApprovalMode', { mode: 'auto' }, ADMIN);
    assert.strictEqual(m.mode, 'auto');
    assert.strictEqual((await db.doc('settings/courier').get()).data().scopeApprovalMode, 'auto');
    const r = await call('courierRequestScopes', { scopes: ['district', 'republic'] }, COURIER);
    assert.strictEqual(r.review.republic, 'approved');
    assert.strictEqual((await cap('accC')).review.courierScopes.republic.decidedBy, 'auto');
  });

  await check('Мануал\'га qaytish — avvalgi rad etilgan so\'rov qayta pending bo\'ladi', async () => {
    await call('adminSetCourierScopeApprovalMode', { mode: 'manual' }, ADMIN);
    await call('adminDecideCourierScope',
      { accountId: 'accC', scope: 'republic', decision: 'reject', reason: 'hujjat noaniq' }, ADMIN);
    assert.strictEqual(pure.isScopeActive(await cap('accC'), 'republic'), false);
    const r = await call('courierRequestScopes', { scopes: ['district', 'republic'] }, COURIER);
    assert.strictEqual(r.review.republic, 'pending');
  });

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi.`);
  process.exit(failed ? 1 : 0);
})();
