/**
 * KURYERNI KUZATISH — boshdan-oxirigacha (S6, D-REST-37): HAQIQIY Cloud Function'lar (`.run()`) + HAQIQIY `firestore.rules`
 * (RULES_FILE) bitta emulyatorda. Zanjir: buyurtma → qabul → kuryer oladi → kuryer jonli nuqtani KLIENT sifatida yozadi
 * (rules) → mijoz va restoran o'qiydi, begona o'qimaydi → tayyor/olindi/yetdi → yetkazildi: nuqta o'chadi, yozish va o'qish yopiq;
 * rad etilgan buyurtmada ham nuqta o'chadi; eskirgan nuqtani soatlik supurish o'chiradi.
 *
 *   RULES_FILE=<abs>\firestore.rules firebase emulators:exec --only firestore --project demo-courier-live-e2e \
 *     "node functions/test/courier_live_e2e.test.js"
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-courier-live-e2e';
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.DIRECTIONS_API_KEY = '';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { serverTimestamp } = require('firebase/firestore');
const fns = require('../index');
const admin = require('firebase-admin');
const ledger = require('../settlement_ledger');

const db = admin.firestore();
const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = process.env.FIRESTORE_EMULATOR_HOST.split(':');

const OWNER = '998911000001';
const CUSTOMER = '998912000001';
const STRANGER = '998914000001';
const COURIER_A = '998913000001';
const COURIER_B = '998913000002';
const ACC = { [COURIER_A]: 'accLIVE0000000000A', [COURIER_B]: 'accLIVE0000000000B' };
const R_LOC = { lat: 41.8406, lng: 60.3917 };
const C_LOC = { lat: 41.8586, lng: 60.3917 };
const TARIFF = { base: 5000, perKm: 1500, nightCoef: 1.5, nightStart: 23, nightEnd: 6, roadFactor: 1.3, maxKm: 15, version: 1 };

const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, ctxOf(who));
let keySeq = 0;
const key = () => `live_e2e_${Date.now()}_${keySeq += 1}`;

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};

async function topUp(uid, amount, k) {
  await ledger.postEntry(db, {
    idempotencyKey: `topup:${uid}:${k}`, kind: 'test_topup',
    legs: [{ account: 'admin_clearing', dr: amount }, { account: ledger.passengerCreditAccount(uid), cr: amount }],
  });
}
async function seedCourier(phone) {
  await db.collection('users').doc(phone).set({ role: 'user', name: phone === COURIER_A ? 'Ali Valiyev' : '', accountId: ACC[phone], bonusBalance: 0 });
  await db.collection('provider_capabilities').doc(ACC[phone]).set({
    identity: { accountId: ACC[phone], primaryUid: phone }, courier: { active: true }, status: { courier: 'approved' },
  });
}

async function main() {
  const env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT,
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  console.log(`rules: ${RULES_PATH}`);
  const as = (phone) => env.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const live = (who, oid) => as(who).doc(`order_courier_live/${oid}`);
  const pos = (oid, extra = {}) => ({ orderId: oid, lat: 41.85, lng: 60.39, heading: 90, speed: 6, updatedAt: serverTimestamp(), ...extra });

  await env.clearFirestore();
  await db.collection('module_config').doc('restaurants_all').set({ restaurants: { stage: 'public', testerIds: [] } });
  await db.collection('settings').doc('restaurant_delivery').set(TARIFF);
  await db.collection('settings').doc('app').set({ restaurantAutoApprove: true });
  for (const u of [OWNER, CUSTOMER, STRANGER]) await db.collection('users').doc(u).set({ role: 'user', name: `U${u.slice(-4)}`, bonusBalance: 0 });
  await seedCourier(COURIER_A);
  await seedCourier(COURIER_B);
  await topUp(OWNER, 20000, 'o');
  await topUp(CUSTOMER, 50000, 'c');

  const reg = await call('restaurantRegister', {
    name: 'Gurlan osh', legalType: 'yatt', address: 'Gurlan, markaz', ...R_LOC,
    delivery: { mode: 'ava_courier', pickup: true }, payment: { prepay: true, cash: true, cardNumber: '8600123412341234', cardHolder: 'OSHPAZ' },
    prepTimeMin: 25, minOrderAmount: 10000,
  }, OWNER);
  const rid = reg.restaurantId;
  await db.collection('restaurants').doc(rid).collection('menu_items').doc('osh').set({ name: 'Osh', price: 40000, available: true, categoryId: 'c1', sort: 1 });
  const place = async () => (await call('placeRestaurantOrder', {
    idempotencyKey: key(), restaurantId: rid, items: [{ itemId: 'osh', qty: 1 }], fulfillmentMode: 'delivery',
    foodPaymentMethod: 'prepay', deliveryPaymentMethod: 'wallet', address: 'Mijoz uyi', ...C_LOC, note: '', utensils: 1,
  }, CUSTOMER)).orderId;
  const secret = async (id) => (await db.collection('orders').doc(id).collection('private').doc('secrets').get()).data();
  const exists = async (id) => (await db.collection('order_courier_live').doc(id).get()).exists;

  let o1;
  await check('E1 buyurtma → restoran qabul → kuryer A oladi: courierId va courierName buyurtmada', async () => {
    o1 = await place();
    await call('restaurantAcceptOrder', { orderId: o1 }, OWNER);
    await call('courierClaimRestaurantOrder', { orderId: o1 }, COURIER_A);
    const od = (await db.collection('orders').doc(o1).get()).data();
    assert.strictEqual(od.courierId, COURIER_A);
    assert.strictEqual(od.restaurantStatus, 'accepted');
    assert.strictEqual(od.courierName, 'Ali Valiyev', 'kuryer ismi buyurtmaga yozildi (mijoz va restoran ko\'radi)');
  });

  await check('E2 kuryer A jonli nuqtani KLIENT sifatida yozadi (rules); boshqa kuryer, mijoz, restoran, begona — yozolmaydi', async () => {
    await assertSucceeds(live(COURIER_A, o1).set(pos(o1)));
    await assertSucceeds(live(COURIER_A, o1).set(pos(o1, { lat: 41.851 })), 'ikkinchi nuqta (yangilash)');
    for (const who of [COURIER_B, CUSTOMER, OWNER, STRANGER]) await assertFails(live(who, o1).set(pos(o1)), `yozish ${who}`);
    await assertFails(live(COURIER_A, o1).set(pos(o1, { updatedAt: new Date() })), 'server vaqti bo\'lmasa');
  });

  await check('E3 mijoz va restoran egasi nuqtani o\'qiydi; begona va boshqa kuryer o\'qiy olmaydi; ro\'yxat yo\'q', async () => {
    const d = await assertSucceeds(live(CUSTOMER, o1).get());
    assert.strictEqual(d.data().lat, 41.851);
    await assertSucceeds(live(OWNER, o1).get());
    await assertFails(live(STRANGER, o1).get());
    await assertFails(live(COURIER_B, o1).get());
    await assertFails(as(CUSTOMER).collection('order_courier_live').get());
  });

  await check('E4 tayyor → olindi (kod) → yetib keldi: har holatda nuqta yoziladi va mijoz o\'qiydi', async () => {
    await call('restaurantMarkReady', { orderId: o1 }, OWNER);
    await assertSucceeds(live(COURIER_A, o1).set(pos(o1, { lat: 41.845 })));
    await call('courierPickupRestaurantOrder', { orderId: o1, pickupCode: (await secret(o1)).pickupCode }, COURIER_A);
    await assertSucceeds(live(COURIER_A, o1).set(pos(o1, { lat: 41.852 })));
    await call('courierArriveRestaurantOrder', { orderId: o1 }, COURIER_A);
    await assertSucceeds(live(COURIER_A, o1).set(pos(o1, { lat: 41.8585 })));
    assert.strictEqual((await assertSucceeds(live(CUSTOMER, o1).get())).data().lat, 41.8585);
    assert.strictEqual((await db.collection('orders').doc(o1).get()).data().restaurantStatus, 'arrived');
  });

  await check('E5 yetkazildi → nuqta SERVERda o\'chadi; kuryer yoza olmaydi, mijoz va restoran o\'qiy olmaydi', async () => {
    assert.strictEqual(await exists(o1), true);
    await call('courierCompleteRestaurantDelivery', { orderId: o1, outcome: 'delivered' }, COURIER_A);
    assert.strictEqual(await exists(o1), false, 'nuqta o\'chdi');
    await assertFails(live(COURIER_A, o1).set(pos(o1)), 'yetkazilgach yozib bo\'lmaydi');
    await assertFails(live(CUSTOMER, o1).get());
    await assertFails(live(OWNER, o1).get());
  });

  let o2;
  await check('E6 restoran RAD etsa (kuryer oldin olgan): nuqta o\'chadi, yozish va o\'qish yopiladi', async () => {
    o2 = await place();
    await call('restaurantAcceptOrder', { orderId: o2 }, OWNER);
    await call('courierClaimRestaurantOrder', { orderId: o2 }, COURIER_A);
    await assertSucceeds(live(COURIER_A, o2).set(pos(o2)));
    assert.strictEqual(await exists(o2), true);
    await call('restaurantRejectOrder', { orderId: o2, reason: 'Mahsulot tugadi' }, OWNER);
    assert.strictEqual(await exists(o2), false);
    await assertFails(live(COURIER_A, o2).set(pos(o2)));
    await assertFails(live(CUSTOMER, o2).get());
  });

  await check('E7 eskirgan nuqta (2 soatdan eski) soatlik supurishda o\'chadi; yangisi qoladi', async () => {
    const o3 = await place();
    await call('restaurantAcceptOrder', { orderId: o3 }, OWNER);
    await call('courierClaimRestaurantOrder', { orderId: o3 }, COURIER_B);
    await assertSucceeds(live(COURIER_B, o3).set(pos(o3)));
    await db.collection('order_courier_live').doc('stale_x').set({ orderId: 'stale_x', lat: 1, lng: 1, updatedAt: admin.firestore.Timestamp.fromMillis(Date.now() - 3 * 3600 * 1000) });
    await fns.sweepRestaurantCourierLive.run({});
    assert.strictEqual(await exists('stale_x'), false, 'eskirgani o\'chdi');
    assert.strictEqual(await exists(o3), true, 'yangisi qoldi');
  });

  await check('E8 nuqta faqat TAYINLANGAN kuryerniki: kuryer B, A ning faol buyurtmasiga yoza olmaydi (olishdan oldin ham)', async () => {
    const o4 = await place();
    await call('restaurantAcceptOrder', { orderId: o4 }, OWNER);
    await assertFails(live(COURIER_A, o4).set(pos(o4)), 'hali hech kim olmagan');
    await call('courierClaimRestaurantOrder', { orderId: o4 }, COURIER_A);
    await assertFails(live(COURIER_B, o4).set(pos(o4)));
    await assertSucceeds(live(COURIER_A, o4).set(pos(o4)));
  });

  await env.cleanup();
  const ok = results.filter(Boolean).length;
  console.log(`\n${ok} passed, ${results.length - ok} failed`);
  process.exit(results.every(Boolean) ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
