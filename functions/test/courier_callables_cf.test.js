/**
 * Kuryer callable'lari — HAQIQIY `functions/index.js` (Emulator, `.run`).
 *
 *   firebase emulators:exec --only firestore --project demo-courier-cf \
 *     "node functions/test/courier_callables_cf.test.js"
 *
 * Qulflanadi (2026-10-07):
 *   - XAVFSIZLIK: oddiy foydalanuvchi o'z buyurtmasini markPicked/
 *     submitPayment qila OLMAYDI (avval «naqd 10 mln» → qaytim hamyonga);
 *   - begona kuryer boshqa marshrutdagi buyurtmaga tegolmaydi;
 *   - EGA QARORI: `suspended` kuryer qo'lidagi buyurtmani TUGATADI, lekin
 *     yangi marshrut yaratolmaydi;
 *   - hamyon qoldig'i faqat o'z marshrutidagi mijozniki.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-courier-cf';

// `COURIER_CF_INDEX` — eski versiyaga qarshi qayta tekshirish uchun
// (bug avval mavjud bo'lganini isbotlash: hujum testlari YIQILISHI kerak).
const fns = require(process.env.COURIER_CF_INDEX || '../index');
const admin = require('firebase-admin');
const db = admin.firestore();

const ATTACKER = '998901230001';
const SUSPENDED = '998901230002';
const APPROVED = '998901230003';
const CUSTOMER = '998907650001';
const STRANGER = '998907650002';

const ctx = (phone) => ({ auth: { uid: phone, token: { phone_number: `+${phone}` } } });
const call = (name, data, phone) => fns[name].run(data, ctx(phone));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
const deniedWith = (msg) => (e) => e.code === 'permission-denied' && (!msg || e.message === msg);

async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => db.recursiveDelete(d.ref)));
}
async function reset() {
  await Promise.all(['users', 'provider_capabilities', 'delivery_routes', 'orders',
    'settlement_journal', 'settlement_accounts'].map(wipe));
  const docs = {
    [`users/${ATTACKER}`]: { bonusBalance: 0 },
    [`users/${CUSTOMER}`]: { bonusBalance: 5000 },
    [`users/${STRANGER}`]: { bonusBalance: 777000 },
    [`users/${SUSPENDED}`]: { accountId: 'accS' },
    'provider_capabilities/accS': { status: { courier: 'suspended' } },
    [`users/${APPROVED}`]: { accountId: 'accA' },
    'provider_capabilities/accA': { status: { courier: 'approved' } },
    // Hujumchining O'Z buyurtmasi — hech qaysi marshrutda emas.
    'orders/oAtt': { userPhone: ATTACKER, status: 'new', total: 10000 },
    // To'xtatilgan kuryerning faol marshrutidagi buyurtma.
    'orders/oS': {
      userPhone: CUSTOMER, status: 'in_delivery', fulfillmentStatus: 'courier_picked',
      total: 20000, courierId: SUSPENDED, deliveryRouteId: 'rS',
    },
    'orders/oReady': { userPhone: STRANGER, status: 'ready', total: 15000 },
    'delivery_routes/rS': { courierId: SUSPENDED, status: 'active', orders: ['oS'], currentIndex: 0 },
  };
  await Promise.all(Object.entries(docs).map(([p, d]) => db.doc(p).set(d)));
}
const balance = async (phone) => (await db.collection('users').doc(phone).get()).data().bonusBalance;

(async () => {
  await reset();

  await check('HUJUM: oddiy foydalanuvchi o\'z buyurtmasini markPicked qila olmaydi', async () => {
    await assert.rejects(() => call('courierMarkPicked', { orderId: 'oAtt', courierPhone: ATTACKER }, ATTACKER),
      deniedWith('Courier not authorized'));
    const od = (await db.doc('orders/oAtt').get()).data();
    assert.strictEqual(od.status, 'new', 'buyurtma o\'zgarmagan');
    assert.strictEqual(od.courierId, undefined);
  });

  await check('HUJUM: «naqd 10 mln» bilan submitPayment — rad, hamyon O\'ZGARMAYDI', async () => {
    await db.doc('orders/oAtt').update({ fulfillmentStatus: 'arrived', status: 'in_delivery' });
    await assert.rejects(() => call('courierSubmitPayment', {
      orderId: 'oAtt', courierPhone: ATTACKER, lines: [{ kind: 'cash', amount: 10000000 }],
    }, ATTACKER), deniedWith('Courier not authorized'));
    assert.strictEqual(await balance(ATTACKER), 0);
    assert.notStrictEqual((await db.doc('orders/oAtt').get()).data().paymentStatus, 'paid');
  });

  await check('begona (approved) kuryer boshqa marshrutdagi buyurtmaga tegolmaydi', async () => {
    await assert.rejects(() => call('courierMarkArrived', { orderId: 'oS', courierPhone: APPROVED }, APPROVED),
      deniedWith('Not your order'));
    await assert.rejects(() => call('courierSubmitPayment', {
      orderId: 'oS', courierPhone: APPROVED, lines: [{ kind: 'cash', amount: 20000 }],
    }, APPROVED), deniedWith('Not your order'));
  });

  await check('telefon mos kelmasa — rad (boshqa kuryer nomidan)', async () => {
    await assert.rejects(() => call('courierMarkArrived', { orderId: 'oS', courierPhone: SUSPENDED }, APPROVED),
      deniedWith('Phone mismatch'));
  });

  await check('EGA QARORI: suspended kuryer qo\'lidagi buyurtmani TUGATADI (arrived → to\'lov)', async () => {
    const a = await call('courierMarkArrived', { orderId: 'oS', courierPhone: SUSPENDED }, SUSPENDED);
    assert.deepStrictEqual(a, { ok: true });
    const p = await call('courierSubmitPayment', {
      orderId: 'oS', courierPhone: SUSPENDED, lines: [{ kind: 'cash', amount: 20000 }],
    }, SUSPENDED);
    assert.strictEqual(p.ok, true);
    const od = (await db.doc('orders/oS').get()).data();
    assert.strictEqual(od.status, 'delivered');
    assert.strictEqual(od.paymentStatus, 'paid');
  });

  await check('suspended kuryer YANGI marshrut yarata olmaydi', async () => {
    await assert.rejects(() => call('courierCreateRoute', {
      courierPhone: SUSPENDED, orderedOrderIds: ['oReady'],
    }, SUSPENDED), deniedWith('Courier not authorized'));
    assert.strictEqual((await db.doc('orders/oReady').get()).data().status, 'ready');
  });

  await check('hamyon qoldig\'i: o\'z marshrutidagi mijoz — bor; begona raqam — rad', async () => {
    const r = await call('courierGetCustomerWalletBalance',
      { courierPhone: SUSPENDED, customerPhone: CUSTOMER }, SUSPENDED);
    assert.strictEqual(r.bonusBalance, 5000);
    await assert.rejects(() => call('courierGetCustomerWalletBalance',
      { courierPhone: SUSPENDED, customerPhone: STRANGER }, SUSPENDED), deniedWith('Not your customer'));
  });

  await check('approved kuryer: yangi marshrut → markPicked ishlaydi (oddiy oqim buzilmagan)', async () => {
    const r = await call('courierCreateRoute', { courierPhone: APPROVED, orderedOrderIds: ['oReady'] }, APPROVED);
    assert.strictEqual(r.count, 1);
    const p = await call('courierMarkPicked', { orderId: 'oReady', courierPhone: APPROVED }, APPROVED);
    assert.deepStrictEqual(p, { ok: true });
  });

  const failed = results.filter((x) => !x.pass).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi.`);
  process.exit(failed ? 1 : 0);
})();
