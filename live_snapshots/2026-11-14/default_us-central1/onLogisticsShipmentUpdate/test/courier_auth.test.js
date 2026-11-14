/**
 * Kuryer avtorizatsiyasi — `courier_auth.js` (Firestore Emulator, Admin SDK).
 *
 *   firebase emulators:exec --only firestore --project demo-courier-auth \
 *     "node functions/test/courier_auth.test.js"
 *
 * Qulflanadi (ega qarori 2026-10-07):
 *   - `suspended` kuryer YANGI ish ololmaydi, lekin QO'LIDAGI ishni tugatadi
 *   - `not_registered` (accountId yo'q / capability yo'q) — ikkala rejimda yopiq
 *   - buyurtma faqat O'Z faol marshrutida bo'lsa (begona / tugagan marshrut — rad)
 *   - hamyon qoldig'i faqat o'z marshrutidagi mijozniki
 *   - 9 va 12 xonali ID'lar (users kaliti, route.courierId, order.phone)
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-courier-auth';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const caps = require('../capabilities_model');
const { MODES, makeCourierAuth } = require('../courier_auth');

// `functions/index.js` → `canonicalUid` bilan bir xil.
const digits = (v) => String(v || '').replace(/\D/g, '');
const canonicalUid = (v) => { const d = digits(v); return d.length === 9 ? `998${d}` : d; };

const auth = makeCourierAuth({ db, caps, canonicalUid, HttpsError: functions.https.HttpsError });

const APPROVED = '998901110001';
const SUSPENDED = '998901110002';
const TRIAL = '998901110003';
const NO_ACCOUNT = '998901110004';
const OLD9 = '998901110005'; // users kaliti 9 xonali
const ROUTE9 = '998901110006'; // route.courierId 9 xonali
const OTHER = '998901110009';
const CUST1 = '998907770001';
const CUST2 = '998907770002';
const CUST9 = '998907770003'; // buyurtmada 9 xonali

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
const denied = (code) => (e) => e.code === code || e.httpErrorCode?.status === code;
async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => d.ref.delete()));
}
async function seed() {
  await Promise.all(['users', 'provider_capabilities', 'delivery_routes', 'orders'].map(wipe));
  const docs = {
    [`users/${APPROVED}`]: { accountId: 'accA' },
    'provider_capabilities/accA': { status: { courier: 'approved' } },
    [`users/${SUSPENDED}`]: { accountId: 'accS' },
    'provider_capabilities/accS': { status: { courier: 'suspended', taxi: 'starter' } },
    [`users/${TRIAL}`]: { accountId: 'accT' },
    'provider_capabilities/accT': { status: { courier: 'trial' } },
    [`users/${NO_ACCOUNT}`]: { role: 'user' },
    [`users/${OLD9.slice(3)}`]: { accountId: 'acc9' },
    'provider_capabilities/acc9': { status: { courier: 'approved' } },
    [`users/${ROUTE9}`]: { accountId: 'accR' },
    'provider_capabilities/accR': { status: { courier: 'approved' } },
    [`users/${OTHER}`]: { accountId: 'accO' },
    'provider_capabilities/accO': { status: { courier: 'approved' } },
    'delivery_routes/r1': { courierId: SUSPENDED, status: 'active', orders: ['o1', 'o2'] },
    'delivery_routes/r2': { courierId: OTHER, status: 'active', orders: ['o3'] },
    'delivery_routes/r3': { courierId: SUSPENDED, status: 'completed', orders: ['o4'] },
    'delivery_routes/r4': { courierId: ROUTE9.slice(3), status: 'ready', orders: ['o5'] },
    'orders/o1': { userPhone: CUST1 },
    'orders/o2': { phone: CUST9.slice(3) },
    'orders/o3': { userPhone: CUST2 },
    'orders/o4': { userPhone: CUST2 },
    'orders/o5': { userPhone: CUST1 },
  };
  await Promise.all(Object.entries(docs).map(([p, d]) => db.doc(p).set(d)));
}

(async () => {
  await seed();

  await check('approved/trial: YANGI ish — ruxsat, kanon ID qaytadi', async () => {
    assert.strictEqual(await auth.resolve(APPROVED, MODES.new), APPROVED);
    assert.strictEqual(await auth.resolve(TRIAL.slice(3), MODES.new), TRIAL, '9 xonali kirish ham kanon');
  });

  await check('EGA QARORI: suspended — yangi ish YO\'Q, qo\'lidagini TUGATADI', async () => {
    await assert.rejects(() => auth.resolve(SUSPENDED, MODES.new), denied('permission-denied'));
    assert.strictEqual(await auth.resolve(SUSPENDED, MODES.finish), SUSPENDED);
  });

  await check('not_registered (accountId yo\'q / users yo\'q) — ikkala rejimda yopiq', async () => {
    for (const phone of [NO_ACCOUNT, '998909999999']) {
      await assert.rejects(() => auth.resolve(phone, MODES.new), denied('permission-denied'));
      await assert.rejects(() => auth.resolve(phone, MODES.finish), denied('permission-denied'));
    }
  });

  await check('rejim berilmasa — eng qattiq (new)', async () => {
    await assert.rejects(() => auth.resolve(SUSPENDED), denied('permission-denied'));
  });

  await check('eski 9 xonali users kaliti topiladi', async () => {
    assert.strictEqual(await auth.resolve(OLD9, MODES.new), OLD9);
  });

  await check('noto\'g\'ri raqam — invalid-argument', async () => {
    await assert.rejects(() => auth.resolve('12', MODES.new), denied('invalid-argument'));
  });

  await check('buyurtma O\'Z faol marshrutida — ruxsat', async () => {
    const r = await auth.assertOrderOnActiveRoute(SUSPENDED, 'o1');
    assert.strictEqual(r.id, 'r1');
  });

  await check('begona marshrutdagi buyurtma — RAD (eski teshik)', async () => {
    await assert.rejects(() => auth.assertOrderOnActiveRoute(SUSPENDED, 'o3'), denied('permission-denied'));
    await assert.rejects(() => auth.assertOrderOnActiveRoute(APPROVED, 'o1'), denied('permission-denied'));
  });

  await check('tugagan marshrutdagi buyurtma — RAD', async () => {
    await assert.rejects(() => auth.assertOrderOnActiveRoute(SUSPENDED, 'o4'), denied('permission-denied'));
  });

  await check('route.courierId 9 xonali — 12 xonali telefon bilan topiladi (ready ham)', async () => {
    const r = await auth.assertOrderOnActiveRoute(ROUTE9, 'o5');
    assert.strictEqual(r.id, 'r4');
  });

  await check('hamyon: o\'z marshrutidagi mijoz — ruxsat (buyurtmada 9 xonali ham)', async () => {
    await auth.assertCustomerOnActiveRoute(SUSPENDED, CUST1);
    await auth.assertCustomerOnActiveRoute(SUSPENDED, CUST9);
  });

  await check('hamyon: begona mijoz / marshrutsiz kuryer — RAD', async () => {
    await assert.rejects(() => auth.assertCustomerOnActiveRoute(SUSPENDED, CUST2), denied('permission-denied'),
      'CUST2 faqat begona va tugagan marshrutda');
    await assert.rejects(() => auth.assertCustomerOnActiveRoute(APPROVED, CUST1), denied('permission-denied'));
    await assert.rejects(() => auth.assertCustomerOnActiveRoute(APPROVED, ''), denied('invalid-argument'));
  });

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi.`);
  process.exit(failed ? 1 : 0);
})();
