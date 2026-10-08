/**
 * KAFE-RESTORAN — to'liq zanjir (D-REST-14): buyurtma → restoran qabuli
 * (2 % hamyondan) → kuryer olish → olib ketish (kod) → yetib keldim → yakun
 * (yetkazish puli hamyon→hamyon yoki naqd) — HAQIQIY `functions/index.js`
 * callable'lari `.run()` orqali, Firestore Emulator, haqiqiy ledger.
 *
 *   firebase emulators:exec --only firestore --project demo-restaurant-orders \
 *     "node functions/test/restaurant_orders_cf.test.js"
 *
 * Qulflanadi (docs/kafe_restoran_taklifi_uz.md §11.8):
 *   - narx FAQAT menyudan; mavjud bo'lmagan taom; minimal buyurtma; modul darvozasi
 *   - 2 % BIR marta (takror qabul idempotent); hamyon yetmasa `placed` qoladi
 *   - parallel qabul ↔ taymaut: bitta g'olib; rad → qaytarish idempotent
 *   - ikki kuryer olish → bittasi; `ready` bo'lmasdan olib ketish yo'q; kod noto'g'ri
 *   - hamyon yetkazish puli mijoz → kuryer; yetmasa naqdga tushadi
 *   - yetkaza olmadi → 2 % qaytadi, mijozga strike, 2-strike → faqat oldindan
 *   - eski yo'llar (courierSubmitPayment, courierCreateRoute, customerCancelOrder,
 *     adminSetOrderStatus) restoran buyurtmasini rad etadi
 *   - o'z kuryeri / olib ketish → restoran o'zi yetkazdi
 *   - sverka: Σdr == Σcr, ledger == bonusBalance
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-restaurant-orders';
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.DIRECTIONS_API_KEY = ''; // Directions chaqirilmaydi → to'g'ri chiziq × yo'l koeffitsienti
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require('../index');
const admin = require('firebase-admin');
const ledger = require('../settlement_ledger');
const tariffMod = require('../restaurant_delivery_tariff');
const ro = require('../restaurant_orders');

const db = admin.firestore();

const OWNER = '998911000001';
const STAFF = '998911000002';
const CUSTOMER = '998912000001';
const CUSTOMER2 = '998912000002';
const COURIER_A = '998913000001';
const COURIER_B = '998913000002';
const STRANGER = '998914000001';
const ADMIN = '998915000001';
const ACC = { [COURIER_A]: 'accREST0000000000A', [COURIER_B]: 'accREST0000000000B' };

const R_LOC = { lat: 41.8406, lng: 60.3917 }; // Gurlan
const C_LOC = { lat: 41.8586, lng: 60.3917 }; // ~2 km shimolda
const TARIFF = { base: 5000, perKm: 1500, nightCoef: 1.5, nightStart: 23, nightEnd: 6, roadFactor: 1.3, maxKm: 15, version: 1 };

const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, ctxOf(who));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function expectCode(promise, code, httpsCode) {
  await assert.rejects(promise, (e) => {
    const got = (e.details && e.details.code) || e.message;
    assert.strictEqual(got, code, `kod ${got} (${e.code}): ${e.message}`);
    if (httpsCode) assert.strictEqual(e.code, httpsCode);
    return true;
  });
}

async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
async function topUp(uid, amount, key) {
  await ledger.postEntry(db, {
    idempotencyKey: `topup:${uid}:${key}`, kind: 'test_topup',
    legs: [{ account: 'admin_clearing', dr: amount }, { account: ledger.passengerCreditAccount(uid), cr: amount }],
  });
}
const pcBal = async (uid) => {
  const s = await db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(uid)).get();
  return s.exists ? Number(s.data().balance || 0) : 0;
};
const bonus = async (uid) => Number(((await db.collection('users').doc(uid).get()).data() || {}).bonusBalance || 0);
const order = async (id) => (await db.collection('orders').doc(id).get()).data() || {};
const events = async (id) => (await db.collection('orders').doc(id).collection('order_events').get()).size;
const secret = async (id) => (await db.collection('orders').doc(id).collection('private').doc('secrets').get()).data() || {};
async function journalBalanced() {
  const s = await db.collection(ledger.COL_JOURNAL).get();
  for (const d of s.docs) {
    const legs = d.data().legs || [];
    const dr = legs.reduce((a, l) => a + (l.dr || 0), 0);
    const cr = legs.reduce((a, l) => a + (l.cr || 0), 0);
    assert.strictEqual(dr, cr, `journal ${d.id} Σdr ${dr} != Σcr ${cr}`);
  }
  return s.size;
}
async function seedCourier(phone, status) {
  await db.collection('users').doc(phone).set({ role: 'user', accountId: ACC[phone], bonusBalance: 0 });
  await db.collection('provider_capabilities').doc(ACC[phone]).set({
    identity: { accountId: ACC[phone], primaryUid: phone },
    courier: { active: true }, status: { courier: status },
  });
}
function expectedAvaFee(from, to) {
  const straight = tariffMod.haversineMeters(from.lat, from.lng, to.lat, to.lng);
  const m = Math.round((straight * 1300) / 1000);
  const prices = tariffMod.resolveDeliveryPrices(TARIFF, tariffMod.resolveRegionKey(from.lat, from.lng));
  const night = tariffMod.isNightAt(new Date(), prices.nightStartH, prices.nightEndH);
  return tariffMod.computeDeliveryFee({ distanceMeters: m, prices, night }).fee;
}
let keySeq = 0;
const key = () => `rest_test_${Date.now()}_${keySeq += 1}`;

async function reset() {
  await clearEmulator();
  await db.collection('module_config').doc('restaurants_all').set({ restaurants: { stage: 'public', testerIds: [] } });
  await db.collection('settings').doc('restaurant_delivery').set(TARIFF);
  await db.collection('settings').doc('app').set({ restaurantAutoApprove: true });
  for (const u of [OWNER, STAFF, CUSTOMER, CUSTOMER2, STRANGER]) {
    await db.collection('users').doc(u).set({ role: 'user', name: `U${u.slice(-4)}`, bonusBalance: 0 });
  }
  await db.collection('users').doc(ADMIN).set({ role: 'admin', bonusBalance: 0 });
  await seedCourier(COURIER_A, 'approved');
  await seedCourier(COURIER_B, 'approved');
  await topUp(OWNER, 10000, 'o');
  await topUp(CUSTOMER, 50000, 'c');
  await topUp(CUSTOMER2, 1000, 'c2');
  await db.collection('restaurant_courier_prefs').doc(COURIER_A).set({ buyoutEnabled: true, buyoutLimit: 100000 });
}

async function registerRestaurant(who, over = {}) {
  const r = await call('restaurantRegister', {
    name: 'Gurlan osh', legalType: 'yatt', address: 'Gurlan, markaz', ...R_LOC,
    delivery: { mode: 'ava_courier', pickup: true }, payment: { prepay: true, cash: true, cardNumber: '8600123412341234', cardHolder: 'OSHPAZ' },
    prepTimeMin: 25, minOrderAmount: 30000, ...over,
  }, who);
  const rid = r.restaurantId;
  const menu = db.collection('restaurants').doc(rid).collection('menu_items');
  await menu.doc('osh').set({ name: 'Osh', price: 40000, available: true, packagingFee: 0, categoryId: 'c1', sort: 1 });
  await menu.doc('somsa').set({ name: 'Somsa', price: 10000, available: true, packagingFee: 500, categoryId: 'c1', sort: 2 });
  await menu.doc('tugadi').set({ name: 'Tugadi', price: 15000, available: false, categoryId: 'c1', sort: 3 });
  await menu.doc('narxsiz').set({ name: 'Narxsiz', price: '5000', available: true, categoryId: 'c1', sort: 4 });
  return rid;
}
const place = (rid, who, over = {}) => call('placeRestaurantOrder', {
  idempotencyKey: key(), restaurantId: rid, items: [{ itemId: 'osh', qty: 1 }, { itemId: 'somsa', qty: 2 }],
  fulfillmentMode: 'delivery', foodPaymentMethod: 'prepay', deliveryPaymentMethod: 'wallet',
  address: 'Mijoz uyi', ...C_LOC, note: 'achchiq bo\'lmasin', utensils: 2, ...over,
}, who);

async function main() {
  await reset();
  let rid;
  let feeAva;

  // ── 1. Ro'yxatdan o'tish ────────────────────────────────────────────
  await check('R1 restoran ro\'yxatdan o\'tdi (autoApprove → approved), owner a\'zo, rekvizit private da', async () => {
    rid = await registerRestaurant(OWNER);
    const r = (await db.collection('restaurants').doc(rid).get()).data();
    assert.strictEqual(r.status, 'approved');
    assert.strictEqual(r.ownerUid, OWNER);
    assert.strictEqual(r.walletUserDocId, OWNER);
    assert.strictEqual(r.minOrderAmount, 30000);
    assert.ok(r.geohash && r.geohash.length === 7, 'geohash');
    const m = await db.collection('restaurants').doc(rid).collection('members').doc(OWNER).get();
    assert.strictEqual(m.data().role, 'owner');
    const p = await db.collection('restaurants').doc(rid).collection('private').doc('payment').get();
    assert.strictEqual(p.data().cardNumber, '8600123412341234');
    await db.collection('restaurants').doc(rid).collection('members').doc(STAFF).set({ role: 'staff' });
  });
  await check('R2 modul darvozasi: internal + testersiz → MODULE_INTERNAL_ONLY; public → ok', async () => {
    await db.collection('module_config').doc('restaurants_all').set({ restaurants: { stage: 'internal', testerIds: [] } });
    await expectCode(place(rid, CUSTOMER), 'MODULE_INTERNAL_ONLY');
    const a = await call('getRestaurantsAccess', {}, CUSTOMER);
    assert.deepStrictEqual(a, { allowed: false, stage: 'internal' });
    await db.collection('module_config').doc('restaurants_all').set({ restaurants: { stage: 'internal', testerIds: [CUSTOMER] } });
    assert.strictEqual((await call('getRestaurantsAccess', {}, CUSTOMER)).allowed, true);
    await db.collection('module_config').doc('restaurants_all').set({ restaurants: { stage: 'public', testerIds: [] } });
  });

  // ── 2. Buyurtma ─────────────────────────────────────────────────────
  let o1;
  await check('P1 buyurtma: narx menyudan (60 000 + qadoq 1 000 + yetkazish tarifdan), placed, kod, hodisa, idempotent', async () => {
    feeAva = expectedAvaFee(R_LOC, C_LOC);
    const k = key();
    const r = await call('placeRestaurantOrder', {
      idempotencyKey: k, restaurantId: rid,
      items: [{ itemId: 'osh', qty: 1, price: 1 }, { itemId: 'somsa', qty: 2, price: 1 }],
      fulfillmentMode: 'delivery', foodPaymentMethod: 'prepay', deliveryPaymentMethod: 'wallet',
      address: 'Mijoz uyi', ...C_LOC, utensils: 2,
    }, CUSTOMER);
    o1 = r.orderId;
    assert.strictEqual(r.itemsTotal, 60000, 'klient narxi e\'tiborsiz');
    assert.strictEqual(r.packagingTotal, 1000);
    assert.strictEqual(r.deliveryFee, feeAva, 'tarif');
    assert.strictEqual(r.total, 61000 + feeAva);
    const od = await order(o1);
    assert.strictEqual(od.type, 'restaurant');
    assert.strictEqual(od.restaurantStatus, 'placed');
    assert.strictEqual(od.status, 'new');
    assert.strictEqual(od.fulfillmentStatus, 'pending');
    assert.strictEqual(od.paymentStatus, 'unpaid');
    assert.strictEqual(od.courierId, null);
    assert.strictEqual(od.deliveryTariffVersion, 1);
    assert.strictEqual(od.distanceSource, 'estimate');
    assert.deepStrictEqual(od.avaFee, { rateBps: 200, basis: 60000, amount: 1200, version: 1, charged: false });
    assert.strictEqual(od.restaurantPayment.cardNumber, '8600123412341234', 'oldindan to\'lov rekviziti snapshot');
    assert.strictEqual(od.restaurantLat, R_LOC.lat);
    assert.ok(od.acceptDeadlineAt.toMillis() > Date.now() + 4 * 60 * 1000, 'deadline ~5 daq');
    const s = await secret(o1);
    assert.ok(/^\d{4}$/.test(s.pickupCode), 'pickupCode 4 raqam');
    assert.strictEqual(await events(o1), 1);
    const again = await call('placeRestaurantOrder', { idempotencyKey: k, restaurantId: rid, items: [{ itemId: 'osh', qty: 9 }], ...C_LOC }, CUSTOMER);
    assert.strictEqual(again.orderId, o1);
    assert.strictEqual(again.duplicate, true);
  });
  await check('P2 mavjud bo\'lmagan / tugagan / narxi satr taom, minimal buyurtma, egasi o\'zidan buyurtma', async () => {
    await expectCode(place(rid, CUSTOMER, { items: [{ itemId: 'yoq', qty: 1 }] }), 'MENU_ITEM_NOT_FOUND');
    await expectCode(place(rid, CUSTOMER, { items: [{ itemId: 'tugadi', qty: 1 }, { itemId: 'osh', qty: 1 }] }), 'MENU_ITEM_UNAVAILABLE');
    await expectCode(place(rid, CUSTOMER, { items: [{ itemId: 'narxsiz', qty: 3 }] }), 'MENU_PRICE_INVALID');
    await expectCode(place(rid, CUSTOMER, { items: [{ itemId: 'somsa', qty: 1 }] }), 'MIN_ORDER_NOT_MET');
    await expectCode(place(rid, OWNER), 'OWN_RESTAURANT');
    await expectCode(place(rid, CUSTOMER, { items: [{ itemId: 'osh', qty: 0 }] }), 'ITEM_INVALID');
    await expectCode(place(rid, CUSTOMER, { lat: null, lng: null }), 'DELIVERY_ADDRESS_REQUIRED');
    await expectCode(place(rid, CUSTOMER, { foodPaymentMethod: 'cash_to_restaurant' }), 'FOOD_PAYMENT_INVALID');
  });
  await check('P3 quoteRestaurantDelivery = buyurtmadagi narx', async () => {
    const q = await call('quoteRestaurantDelivery', { restaurantId: rid, ...C_LOC }, CUSTOMER);
    assert.strictEqual(q.deliveryFee, feeAva);
    assert.strictEqual(q.deliveryMode, 'ava_courier');
  });

  // ── 3. Qabul — 2 % ──────────────────────────────────────────────────
  await check('A1 begona qabul qila olmaydi; staff a\'zo qabul qiladi → 2 % egasi hamyonidan, journal, idempotent', async () => {
    await expectCode(call('restaurantAcceptOrder', { orderId: o1 }, STRANGER), 'NOT_RESTAURANT_MEMBER', 'permission-denied');
    const before = await pcBal(OWNER);
    const r = await call('restaurantAcceptOrder', { orderId: o1, prepTimeMin: 30 }, STAFF);
    assert.strictEqual(r.feeAmount, 1200);
    assert.strictEqual(await pcBal(OWNER), before - 1200);
    assert.strictEqual(await bonus(OWNER), before - 1200, 'bonusBalance ko\'zgusi');
    const od = await order(o1);
    assert.strictEqual(od.restaurantStatus, 'accepted');
    assert.strictEqual(od.status, 'accepted');
    assert.strictEqual(od.fulfillmentStatus, 'confirmed');
    assert.strictEqual(od.prepTimeMin, 30);
    assert.strictEqual(od.avaFee.charged, true);
    assert.strictEqual(od.acceptDeadlineAt, null);
    const j = await db.collection(ledger.COL_JOURNAL).doc(`bonus:restFee_${o1}_v1`).get();
    assert.ok(j.exists, 'jurnal yozuvi');
    assert.strictEqual(j.data().legs.find((l) => l.cr).account, ro.EARNINGS_ACCOUNT);
    const r2 = await call('restaurantAcceptOrder', { orderId: o1 }, OWNER);
    assert.strictEqual(r2.idempotent, true);
    assert.strictEqual(await pcBal(OWNER), before - 1200, 'ikkinchi marta yechilmadi');
    const wl = await db.collection('users').doc(OWNER).collection('wallet_ledger').where('refId', '==', o1).get();
    assert.strictEqual(wl.size, 1);
  });
  await check('A2 hamyon yetmasa → RESTAURANT_WALLET_INSUFFICIENT, buyurtma placed qoladi, jurnal yo\'q', async () => {
    const r = await place(rid, CUSTOMER, { items: [{ itemId: 'osh', qty: 12 }] }); // 480 000 → 9 600 > 8 800
    await expectCode(call('restaurantAcceptOrder', { orderId: r.orderId }, OWNER), 'RESTAURANT_WALLET_INSUFFICIENT', 'failed-precondition');
    assert.strictEqual((await order(r.orderId)).restaurantStatus, 'placed');
    assert.strictEqual((await db.collection(ledger.COL_JOURNAL).doc(`bonus:restFee_${r.orderId}_v1`).get()).exists, false);
    await call('customerCancelRestaurantOrder', { orderId: r.orderId }, CUSTOMER);
  });
  await check('A3 parallel qabul ↔ taymaut: BITTA g\'olib; yechim faqat qabulda', async () => {
    const r = await place(rid, CUSTOMER);
    await db.collection('orders').doc(r.orderId).update({ acceptDeadlineAt: admin.firestore.Timestamp.fromMillis(Date.now() - 60000) });
    const before = await pcBal(OWNER);
    const [acc, exp] = await Promise.allSettled([
      call('restaurantAcceptOrder', { orderId: r.orderId }, OWNER),
      fns.expireUnacceptedRestaurantOrders.run({}),
    ]);
    const od = await order(r.orderId);
    if (od.restaurantStatus === 'accepted') {
      assert.strictEqual(acc.status, 'fulfilled');
      assert.strictEqual(await pcBal(OWNER), before - 1200);
    } else {
      assert.strictEqual(od.restaurantStatus, 'rejected');
      assert.strictEqual(od.rejectReason, 'timeout');
      assert.strictEqual(acc.status, 'rejected');
      assert.strictEqual(acc.reason.details.code, 'ORDER_INVALID_TRANSITION');
      assert.strictEqual(await pcBal(OWNER), before, 'taymautda yechilmaydi');
    }
    assert.strictEqual(exp.status, 'fulfilled');
    if (od.restaurantStatus === 'accepted') await call('restaurantRejectOrder', { orderId: r.orderId, reason: 'test' }, OWNER);
  });
  await check('A4 rad (accepted) → 2 % qaytadi, idempotent; mijoz bekor accepted da yo\'q', async () => {
    const r = await place(rid, CUSTOMER);
    await call('restaurantAcceptOrder', { orderId: r.orderId }, OWNER);
    const mid = await pcBal(OWNER);
    await expectCode(call('customerCancelRestaurantOrder', { orderId: r.orderId }, CUSTOMER), 'CANCEL_NOT_ALLOWED');
    await call('restaurantRejectOrder', { orderId: r.orderId, reason: 'osh tugadi' }, OWNER);
    assert.strictEqual(await pcBal(OWNER), mid + 1200);
    assert.strictEqual(await bonus(OWNER), mid + 1200);
    const od = await order(r.orderId);
    assert.strictEqual(od.restaurantStatus, 'rejected');
    assert.strictEqual(od.status, 'rejected');
    assert.strictEqual(od.avaFee.refunded, true);
    const r2 = await call('restaurantRejectOrder', { orderId: r.orderId }, OWNER);
    assert.strictEqual(r2.idempotent, true);
    assert.strictEqual(await pcBal(OWNER), mid + 1200, 'ikki marta qaytarilmaydi');
  });
  await check('A5 mijoz bekor: placed → cancelled (2 % yechilmagan), takror idempotent', async () => {
    const r = await place(rid, CUSTOMER);
    await call('customerCancelRestaurantOrder', { orderId: r.orderId, reason: 'fikrim o\'zgardi' }, CUSTOMER);
    const od = await order(r.orderId);
    assert.strictEqual(od.restaurantStatus, 'cancelled');
    assert.strictEqual(od.status, 'cancelled');
    await expectCode(call('customerCancelRestaurantOrder', { orderId: r.orderId }, STRANGER), 'NOT_ORDER_OWNER');
    const r2 = await call('customerCancelRestaurantOrder', { orderId: r.orderId }, CUSTOMER);
    assert.strictEqual(r2.ok, true);
  });
  await check('A6 mijoz «to\'ladim» → paid_declared; restoran tasdiqlaydi → paid', async () => {
    await call('customerMarkRestaurantOrderPaid', { orderId: o1 }, CUSTOMER);
    assert.strictEqual((await order(o1)).paymentStatus, 'paid_declared');
    await call('restaurantConfirmPayment', { orderId: o1 }, OWNER);
    assert.strictEqual((await order(o1)).paymentStatus, 'paid');
  });

  // ── 4. Kuryer ───────────────────────────────────────────────────────
  await check('K1 yaqindagilar: faqat ishlaydigan kuryer; proeksiyada telefon/manzil yo\'q; accepted ham ko\'rinadi', async () => {
    await expectCode(call('listNearbyRestaurantOrders', { ...R_LOC }, STRANGER), 'Courier not authorized', 'permission-denied');
    const l = await call('listNearbyRestaurantOrders', { ...R_LOC }, COURIER_A);
    const row = l.orders.find((x) => x.id === o1);
    assert.ok(row, 'o1 ro\'yxatda');
    assert.strictEqual(row.restaurantStatus, 'accepted');
    assert.strictEqual(row.deliveryFee, feeAva);
    assert.strictEqual(row.deliveryPaymentMethod, 'wallet');
    assert.ok(!('phone' in row) && !('address' in row) && !('userPhone' in row), 'PII yo\'q');
    const far = await call('listNearbyRestaurantOrders', { lat: 41.3, lng: 69.2 }, COURIER_A); // Toshkent
    assert.ok(!far.orders.find((x) => x.id === o1), 'radiusdan tashqarida ko\'rinmaydi');
  });
  await check('K2 ikki kuryer bir vaqtda oladi → bittasi; marshrut hujjati; takror idempotent; boshqasi CONFLICT', async () => {
    const [a, b] = await Promise.allSettled([
      call('courierClaimRestaurantOrder', { orderId: o1 }, COURIER_A),
      call('courierClaimRestaurantOrder', { orderId: o1 }, COURIER_B),
    ]);
    const ok = [a, b].filter((x) => x.status === 'fulfilled');
    const bad = [a, b].filter((x) => x.status === 'rejected');
    assert.strictEqual(ok.length, 1, `g'oliblar: ${ok.length}`);
    assert.strictEqual(bad[0].reason.details.code, 'COURIER_ASSIGNMENT_CONFLICT');
    const od = await order(o1);
    assert.ok([COURIER_A, COURIER_B].includes(od.courierId));
    const route = await db.collection('delivery_routes').doc(od.deliveryRouteId).get();
    assert.strictEqual(route.data().courierId, od.courierId);
    assert.deepStrictEqual(route.data().orders, [o1]);
    const again = await call('courierClaimRestaurantOrder', { orderId: o1 }, od.courierId);
    assert.strictEqual(again.idempotent, true);
    const other = od.courierId === COURIER_A ? COURIER_B : COURIER_A;
    await expectCode(call('courierClaimRestaurantOrder', { orderId: o1 }, other), 'COURIER_ASSIGNMENT_CONFLICT');
    // qolgan testlar uchun g'olib A bo'lsin
    if (od.courierId !== COURIER_A) {
      await db.collection('orders').doc(o1).update({ courierId: COURIER_A });
      await route.ref.update({ courierId: COURIER_A });
    }
    assert.ok(!(await call('listNearbyRestaurantOrders', { ...R_LOC }, COURIER_B)).orders.find((x) => x.id === o1), 'olingan buyurtma ro\'yxatda yo\'q');
  });
  await check('K3 eski yo\'llar restoran buyurtmasini rad etadi (submitPayment / createRoute / listReady / customerCancel / adminSetOrderStatus)', async () => {
    await expectCode(call('courierSubmitPayment', { orderId: o1, courierPhone: COURIER_A, lines: [{ kind: 'cash', amount: 1000 }] }, COURIER_A), 'USE_RESTAURANT_COMPLETION');
    await expectCode(call('customerCancelOrder', { orderId: o1 }, CUSTOMER), 'USE_RESTAURANT_CANCEL');
    await expectCode(call('adminSetOrderStatus', { adminPhone: ADMIN, orderId: o1, status: 'ready' }, ADMIN), 'RESTAURANT_ORDER_READONLY');
    const r = await place(rid, CUSTOMER2, { deliveryPaymentMethod: 'cash' });
    await call('restaurantAcceptOrder', { orderId: r.orderId }, OWNER);
    await call('restaurantMarkReady', { orderId: r.orderId }, OWNER);
    const ready = await call('courierListReadyOrders', {}, COURIER_B);
    assert.ok(!ready.orders.find((x) => x.id === r.orderId), 'courierListReadyOrders da yo\'q');
    await expectCode(call('courierCreateRoute', { courierPhone: COURIER_B, orderedOrderIds: [r.orderId] }, COURIER_B), 'no_ready_orders');
    assert.strictEqual((await order(r.orderId)).restaurantStatus, 'ready', 'holat buzilmadi');
    await call('restaurantRejectOrder', { orderId: r.orderId, reason: 'test' }, OWNER);
  });
  await check('K4 olib ketish: ready bo\'lmasdan yo\'q; kod noto\'g\'ri → MISMATCH (urinish sanaladi); to\'g\'ri → picked', async () => {
    await expectCode(call('courierPickupRestaurantOrder', { orderId: o1, pickupCode: '0000' }, COURIER_A), 'RESTAURANT_NOT_READY');
    await call('restaurantMarkReady', { orderId: o1 }, OWNER);
    const s = await secret(o1);
    const wrong = s.pickupCode === '1111' ? '2222' : '1111';
    await expectCode(call('courierPickupRestaurantOrder', { orderId: o1, pickupCode: wrong }, COURIER_A), 'PICKUP_CODE_MISMATCH');
    assert.strictEqual((await secret(o1)).pickupAttempts, 1);
    await expectCode(call('courierPickupRestaurantOrder', { orderId: o1, pickupCode: s.pickupCode }, COURIER_B), 'Not your order', 'permission-denied');
    await call('courierPickupRestaurantOrder', { orderId: o1, pickupCode: s.pickupCode }, COURIER_A);
    const od = await order(o1);
    assert.strictEqual(od.restaurantStatus, 'picked');
    assert.strictEqual(od.status, 'in_delivery');
    assert.strictEqual(od.fulfillmentStatus, 'courier_picked');
    await expectCode(call('courierCompleteRestaurantDelivery', { orderId: o1 }, COURIER_A), 'ORDER_INVALID_TRANSITION');
  });
  await check('K5 yetib keldim → arrived; yakun: hamyon yetkazish puli mijoz → kuryer, idempotent, stats', async () => {
    await call('courierArriveRestaurantOrder', { orderId: o1 }, COURIER_A);
    assert.strictEqual((await order(o1)).restaurantStatus, 'arrived');
    const c0 = await pcBal(CUSTOMER);
    const k0 = await pcBal(COURIER_A);
    const r = await call('courierCompleteRestaurantDelivery', { orderId: o1, outcome: 'delivered' }, COURIER_A);
    assert.strictEqual(r.walletPaid, feeAva);
    assert.strictEqual(r.cashCollected, 0, 'oldindan to\'langan + hamyon → naqd yo\'q');
    assert.strictEqual(await pcBal(CUSTOMER), c0 - feeAva);
    assert.strictEqual(await pcBal(COURIER_A), k0 + feeAva);
    assert.strictEqual(await bonus(CUSTOMER), c0 - feeAva);
    assert.strictEqual(await bonus(COURIER_A), k0 + feeAva);
    const od = await order(o1);
    assert.strictEqual(od.restaurantStatus, 'delivered');
    assert.strictEqual(od.status, 'delivered');
    assert.strictEqual(od.fulfillmentStatus, 'completed');
    assert.strictEqual(od.paymentStatus, 'paid');
    const r2 = await call('courierCompleteRestaurantDelivery', { orderId: o1, outcome: 'delivered' }, COURIER_A);
    assert.strictEqual(r2.idempotent, true);
    assert.strictEqual(await pcBal(CUSTOMER), c0 - feeAva, 'ikki marta yechilmadi');
    const st = (await db.collection('restaurant_customer_stats').doc(CUSTOMER).get()).data();
    assert.strictEqual(st.completedCount, 1);
    assert.ok((await events(o1)) >= 7, `hodisalar: ${await events(o1)}`);
  });
  await check('K6 vykup (naqd): B limitsiz ko\'rmaydi/ololmaydi; A oladi; olib ketishda paid (buyout); yakunda naqd = taom + yetkazish', async () => {
    const r = await place(rid, CUSTOMER2, { foodPaymentMethod: 'cash_buyout', deliveryPaymentMethod: 'cash' });
    await call('restaurantAcceptOrder', { orderId: r.orderId }, OWNER);
    const lB = await call('listNearbyRestaurantOrders', { ...R_LOC }, COURIER_B);
    assert.ok(!lB.orders.find((x) => x.id === r.orderId), 'B vykupni yoqmagan');
    await expectCode(call('courierClaimRestaurantOrder', { orderId: r.orderId }, COURIER_B), 'BUYOUT_LIMIT_EXCEEDED');
    const lA = await call('listNearbyRestaurantOrders', { ...R_LOC }, COURIER_A);
    assert.strictEqual(lA.orders.find((x) => x.id === r.orderId).buyoutAmount, 61000);
    await call('courierClaimRestaurantOrder', { orderId: r.orderId }, COURIER_A);
    await call('restaurantMarkReady', { orderId: r.orderId }, OWNER);
    await call('courierPickupRestaurantOrder', { orderId: r.orderId, pickupCode: (await secret(r.orderId)).pickupCode }, COURIER_A);
    let od = await order(r.orderId);
    assert.strictEqual(od.paymentStatus, 'paid');
    assert.strictEqual(od.paidBy, 'courier_buyout');
    assert.strictEqual(od.buyoutAmount, 61000);
    await call('courierArriveRestaurantOrder', { orderId: r.orderId }, COURIER_A);
    const j0 = await journalBalanced();
    const res = await call('courierCompleteRestaurantDelivery', { orderId: r.orderId, outcome: 'delivered' }, COURIER_A);
    assert.strictEqual(res.cashCollected, 61000 + feeAva);
    assert.strictEqual(res.walletPaid, 0);
    assert.strictEqual(await journalBalanced(), j0, 'naqdda ledger yozuvi yo\'q (AVA puli emas)');
    od = await order(r.orderId);
    assert.strictEqual(od.restaurantStatus, 'delivered');
  });
  await check('K7 hamyon yetmasa → yetkazish puli naqdga tushadi (fallback)', async () => {
    const r = await place(rid, CUSTOMER2, { deliveryPaymentMethod: 'wallet' }); // CUSTOMER2 hamyoni 1 000
    await call('restaurantAcceptOrder', { orderId: r.orderId }, OWNER);
    await call('courierClaimRestaurantOrder', { orderId: r.orderId }, COURIER_A);
    await call('restaurantMarkReady', { orderId: r.orderId }, OWNER);
    await call('courierPickupRestaurantOrder', { orderId: r.orderId, pickupCode: (await secret(r.orderId)).pickupCode }, COURIER_A);
    await call('courierArriveRestaurantOrder', { orderId: r.orderId }, COURIER_A);
    const c0 = await pcBal(CUSTOMER2);
    const res = await call('courierCompleteRestaurantDelivery', { orderId: r.orderId, outcome: 'delivered' }, COURIER_A);
    assert.strictEqual(res.deliveryPaymentMethod, 'cash');
    assert.strictEqual(res.walletPaid, 0);
    assert.strictEqual(res.cashCollected, feeAva);
    assert.strictEqual(await pcBal(CUSTOMER2), c0, 'hamyon tegilmadi');
    assert.strictEqual((await order(r.orderId)).deliveryFeeFallback, 'insufficient_wallet');
  });
  await check('K8 yetkaza olmadi → delivery_failed, 2 % restoranga qaytdi, strike; 2-strike → faqat oldindan to\'lov', async () => {
    for (let i = 0; i < 2; i += 1) {
      const r = await place(rid, CUSTOMER2, { foodPaymentMethod: 'cash_buyout', deliveryPaymentMethod: 'cash' });
      await call('restaurantAcceptOrder', { orderId: r.orderId }, OWNER);
      const o0 = await pcBal(OWNER);
      await call('courierClaimRestaurantOrder', { orderId: r.orderId }, COURIER_A);
      await call('restaurantMarkReady', { orderId: r.orderId }, OWNER);
      await call('courierPickupRestaurantOrder', { orderId: r.orderId, pickupCode: (await secret(r.orderId)).pickupCode }, COURIER_A);
      await call('courierArriveRestaurantOrder', { orderId: r.orderId }, COURIER_A);
      const res = await call('courierCompleteRestaurantDelivery', { orderId: r.orderId, outcome: 'failed', failReason: 'customer_absent' }, COURIER_A);
      assert.strictEqual(res.refundAmount, 1200);
      assert.strictEqual(await pcBal(OWNER), o0 + 1200);
      const od = await order(r.orderId);
      assert.strictEqual(od.restaurantStatus, 'delivery_failed');
      assert.strictEqual(od.status, 'cancelled');
      assert.strictEqual(od.avaFee.refunded, true);
      const st = (await db.collection('restaurant_customer_stats').doc(CUSTOMER2).get()).data();
      assert.strictEqual(st.strikes, i + 1);
      if (i === 0) assert.ok(!st.prepayOnlyUntil, '1-strike: hali cheklov yo\'q');
      else assert.ok(st.prepayOnlyUntil.toMillis() > Date.now(), '2-strike: prepayOnlyUntil');
    }
    await expectCode(place(rid, CUSTOMER2, { foodPaymentMethod: 'cash_buyout', deliveryPaymentMethod: 'cash' }), 'PREPAY_ONLY');
    const ok = await place(rid, CUSTOMER2, { foodPaymentMethod: 'prepay', deliveryPaymentMethod: 'cash' });
    assert.ok(ok.orderId, 'oldindan to\'lov bilan mumkin');
    await call('customerCancelRestaurantOrder', { orderId: ok.orderId }, CUSTOMER2);
  });
  await check('K9 rad (ready, kuryer biriktirilgan) → marshrutdan olinadi, 2 % qaytadi; oxirgisi ketsa marshrut yopiladi', async () => {
    const r = await place(rid, CUSTOMER);
    const r2 = await place(rid, CUSTOMER);
    await call('restaurantAcceptOrder', { orderId: r.orderId }, OWNER);
    await call('restaurantAcceptOrder', { orderId: r2.orderId }, OWNER);
    await call('courierClaimRestaurantOrder', { orderId: r.orderId }, COURIER_B);
    await call('courierClaimRestaurantOrder', { orderId: r2.orderId }, COURIER_B);
    await call('restaurantMarkReady', { orderId: r.orderId }, OWNER);
    const o0 = await pcBal(OWNER);
    await call('restaurantRejectOrder', { orderId: r.orderId, reason: 'kuryer kelmadi' }, OWNER);
    assert.strictEqual(await pcBal(OWNER), o0 + 1200);
    const od = await order(r.orderId);
    const routeRef = db.collection('delivery_routes').doc(od.deliveryRouteId);
    let route = (await routeRef.get()).data();
    assert.deepStrictEqual(route.orders, [r2.orderId], 'marshrutdan olindi, ikkinchisi qoldi');
    assert.strictEqual(route.status, 'active', 'buyurtma qolgan — marshrut ochiq');
    await call('restaurantRejectOrder', { orderId: r2.orderId, reason: 'tugadi' }, OWNER);
    route = (await routeRef.get()).data();
    assert.deepStrictEqual(route.orders, []);
    assert.strictEqual(route.status, 'completed', 'bo\'sh marshrut yopildi — kuryer yangisini ola oladi');
    assert.strictEqual(route.completedReason, 'restaurant_rejected');
    assert.strictEqual(await pcBal(OWNER), o0 + 2400, 'ikkala 2 % qaytdi');
  });

  // ── 5. O'z kuryeri / olib ketish / admin ───────────────────────────
  let rid2;
  await check('O1 o\'z kuryerli restoran: narx restorandan (7 000), restoran o\'zi yetkazdi → delivered + paid; 2 % qoladi', async () => {
    rid2 = await registerRestaurant(OWNER, { name: 'Somsa uyi', delivery: { mode: 'own_courier', pickup: true, ownFee: { type: 'fixed', fixed: 7000, freeAbove: 100000 } }, minOrderAmount: 0 });
    const r = await place(rid2, CUSTOMER, { foodPaymentMethod: 'cash_to_restaurant' });
    assert.strictEqual(r.deliveryFee, 7000);
    assert.strictEqual((await order(r.orderId)).deliveryFeeSource, 'restaurant');
    assert.strictEqual((await order(r.orderId)).deliveryPaymentMethod, 'none');
    await expectCode(call('courierClaimRestaurantOrder', { orderId: r.orderId }, COURIER_A), 'NOT_AVA_COURIER_ORDER');
    await call('restaurantAcceptOrder', { orderId: r.orderId }, OWNER);
    const o0 = await pcBal(OWNER);
    await expectCode(call('restaurantMarkDelivered', { orderId: r.orderId }, OWNER), 'ORDER_INVALID_TRANSITION');
    await call('restaurantMarkReady', { orderId: r.orderId }, OWNER);
    await call('restaurantMarkDelivered', { orderId: r.orderId }, OWNER);
    const od = await order(r.orderId);
    assert.strictEqual(od.restaurantStatus, 'delivered');
    assert.strictEqual(od.paymentStatus, 'paid');
    assert.strictEqual(await pcBal(OWNER), o0, '2 % qoldi');
    const big = await place(rid2, CUSTOMER, { foodPaymentMethod: 'cash_to_restaurant', items: [{ itemId: 'osh', qty: 3 }] }); // 120 000 ≥ freeAbove
    assert.strictEqual(big.deliveryFee, 0, 'freeAbove');
    await call('customerCancelRestaurantOrder', { orderId: big.orderId }, CUSTOMER);
  });
  await check('O2 olib ketish: yetkazish 0, manzilsiz ham bo\'ladi, delivered', async () => {
    const r = await place(rid2, CUSTOMER, { fulfillmentMode: 'pickup', foodPaymentMethod: 'cash_to_restaurant', lat: null, lng: null });
    assert.strictEqual(r.deliveryFee, 0);
    assert.strictEqual((await order(r.orderId)).deliveryMode, 'pickup');
    await call('restaurantAcceptOrder', { orderId: r.orderId }, OWNER);
    await call('restaurantMarkReady', { orderId: r.orderId }, OWNER);
    await call('restaurantMarkDelivered', { orderId: r.orderId }, OWNER);
    assert.strictEqual((await order(r.orderId)).restaurantStatus, 'delivered');
  });
  await check('O3 admin: suspended → buyurtma yo\'q; audit; qayta approved; noto\'g\'ri o\'tish rad', async () => {
    await expectCode(call('adminSetRestaurantStatus', { restaurantId: rid2, status: 'suspended' }, STRANGER), 'Admin role required', 'permission-denied');
    await call('adminSetRestaurantStatus', { restaurantId: rid2, status: 'suspended', reason: 'shikoyat' }, ADMIN);
    await expectCode(place(rid2, CUSTOMER, { foodPaymentMethod: 'cash_to_restaurant' }), 'RESTAURANT_NOT_APPROVED');
    const audit = await db.collection('admin_audit').where('target', '==', rid2).get();
    assert.strictEqual(audit.size, 1);
    assert.strictEqual(audit.docs[0].data().kind, 'restaurant_status');
    await expectCode(call('adminSetRestaurantStatus', { restaurantId: rid2, status: 'applied' }, ADMIN), 'RESTAURANT_INVALID_TRANSITION');
    await call('adminSetRestaurantStatus', { restaurantId: rid2, status: 'approved' }, ADMIN);
    assert.strictEqual((await db.collection('restaurants').doc(rid2).get()).data().status, 'approved');
  });
  await check('O4 3 ta taymaut ketma-ket → restoran 30 daqiqaga pauza → RESTAURANT_PAUSED', async () => {
    for (let i = 0; i < 3; i += 1) {
      const r = await place(rid2, CUSTOMER, { foodPaymentMethod: 'cash_to_restaurant' });
      await db.collection('orders').doc(r.orderId).update({ acceptDeadlineAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000) });
      const res = await fns.expireUnacceptedRestaurantOrders.run({});
      assert.strictEqual(res.expired, 1, `expired=${res.expired}`);
      assert.strictEqual((await order(r.orderId)).restaurantStatus, 'rejected');
    }
    const rr = (await db.collection('restaurants').doc(rid2).get()).data();
    assert.ok(rr.pausedUntil && rr.pausedUntil.toMillis() > Date.now(), 'pausedUntil');
    assert.strictEqual(rr.timeoutStreak, 0);
    await expectCode(place(rid2, CUSTOMER, { foodPaymentMethod: 'cash_to_restaurant' }), 'RESTAURANT_PAUSED');
    await db.collection('restaurants').doc(rid2).update({ pausedUntil: null });
  });

  // ── 6. Sverka ───────────────────────────────────────────────────────
  await check('S1 ledger: Σdr == Σcr; passenger_credit == bonusBalance (owner, mijozlar, kuryerlar)', async () => {
    await journalBalanced();
    for (const u of [OWNER, CUSTOMER, CUSTOMER2, COURIER_A, COURIER_B]) {
      assert.strictEqual(await bonus(u), await pcBal(u), `ko'zgu ${u}`);
    }
    const e = await db.collection(ledger.COL_ACCOUNTS).doc(ro.EARNINGS_ACCOUNT).get();
    assert.ok(e.exists && e.data().balance > 0, 'AVA daromadi > 0');
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
