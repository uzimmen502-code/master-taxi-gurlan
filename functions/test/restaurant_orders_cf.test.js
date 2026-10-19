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
const OWNER2 = '998911000003'; // boshqa restoranning egasi (D-REST-15 — raqib)
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
  for (const u of [OWNER, STAFF, CUSTOMER, CUSTOMER2, STRANGER, OWNER2]) {
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
  // packagingFee: 500 — ESKI maydon (qadoqlash haqi olib tashlangan, D-REST-28): server e'tiborsiz qoldirishi kerak.
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
  await check('V1 muassasa turi (D-REST-41): uy ovqatchisi — doim `home` (tanlab bo\'lmaydi); kafe-restoran — cafe/restaurant/chaikhana; noto\'g\'ri — rad; berilmasa (eski ilova) — maydon yozilmaydi', async () => {
    const base = { name: 'Tur sinovi', address: 'Gurlan', ...R_LOC, delivery: { mode: 'ava_courier', pickup: true }, payment: { prepay: true, cash: true } };
    const reg = async (extra) => (await db.collection('restaurants').doc((await call('restaurantRegister', { ...base, ...extra }, OWNER2)).restaurantId).get()).data();
    assert.strictEqual((await reg({ legalType: 'individual' })).venueType, 'home');
    assert.strictEqual((await reg({ legalType: 'individual', venueType: 'restaurant' })).venueType, 'home', 'uy ovqatchisi boshqa tur tanlay olmaydi');
    assert.strictEqual((await reg({})).venueType, 'home', 'legalType berilmasa individual');
    for (const v of ['cafe', 'restaurant', 'chaikhana']) assert.strictEqual((await reg({ legalType: 'yatt', venueType: v })).venueType, v);
    assert.strictEqual((await reg({ legalType: 'llc', venueType: 'chaikhana' })).venueType, 'chaikhana');
    assert.strictEqual('venueType' in (await reg({ legalType: 'yatt' })), false, 'eski ilova turni yubormaydi — maydon yo\'q');
    for (const v of ['home', 'bar', 'CAFE', 5]) {
      await expectCode(call('restaurantRegister', { ...base, legalType: 'yatt', venueType: v }, OWNER2), 'VENUE_TYPE_INVALID', 'invalid-argument');
    }
  });
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
  await check('R1b bir ega bir nechta restoran ochadi (menejerlik, D-REST-15): son chegarasi yo\'q — 12 ta ham ok, har birida owner a\'zo', async () => {
    const ids = [];
    for (let i = 0; i < 12; i += 1) {
      const r = await call('restaurantRegister', { name: `Filial ${i}`, address: 'x', ...R_LOC, delivery: { mode: 'none', pickup: true } }, OWNER);
      assert.ok(r.restaurantId && r.restaurantId !== rid);
      ids.push(r.restaurantId);
    }
    const mine = await db.collection('restaurants').where('ownerUid', '==', OWNER).get();
    assert.strictEqual(mine.size, 13);
    const m = await db.collection('restaurants').doc(ids[11]).collection('members').doc(OWNER).get();
    assert.strictEqual(m.data().role, 'owner');
    // Tozalash — keyingi testlar bitta restoran (rid) bilan ishlaydi.
    for (const id of ids) await db.collection('restaurants').doc(id).delete();
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
  await check('P1 buyurtma: narx menyudan (60 000 + yetkazish tarifdan; eski packagingFee hisobga olinmaydi — D-REST-28), placed, kod, hodisa, idempotent', async () => {
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
    assert.strictEqual(r.packagingTotal, undefined, 'qadoqlash haqi yo\'q (D-REST-28)');
    assert.strictEqual(r.deliveryFee, feeAva, 'tarif');
    assert.strictEqual(r.total, 60000 + feeAva, 'eski packagingFee jamiga KIRMAYDI');
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
  await check('P2b miqdor limiti (D-REST-26): default 50 (yig\'indi, qatorlarni bo\'lib aylanib o\'tib bo\'lmaydi); maxQtyPerItem oshirsa o\'tadi; shipi 500', async () => {
    const mk = (q, extra = []) => place(rid, CUSTOMER, { items: [{ itemId: 'osh', qty: q }, ...extra] });
    const unavailable = [{ itemId: 'tugadi', qty: 1 }]; // limitdan KEYINGI tekshiruvda yiqiladi — buyurtma yaratilmaydi
    await expectCode(mk(51, unavailable), 'QTY_LIMIT_EXCEEDED', 'failed-precondition');
    await expectCode(place(rid, CUSTOMER, { items: [{ itemId: 'osh', qty: 30 }, { itemId: 'osh', qty: 30 }, ...unavailable] }), 'QTY_LIMIT_EXCEEDED');
    await expectCode(mk(501, unavailable), 'ITEM_INVALID');
    await db.collection('restaurants').doc(rid).update({ maxQtyPerItem: 100 });
    try {
      await expectCode(mk(60, unavailable), 'MENU_ITEM_UNAVAILABLE'); // 60 ≤ 100: limitdan o'tdi
      await expectCode(mk(101, unavailable), 'QTY_LIMIT_EXCEEDED');
      await db.collection('restaurants').doc(rid).update({ maxQtyPerItem: 9999 }); // buzilgan qiymat → default 50
      await expectCode(mk(51, unavailable), 'QTY_LIMIT_EXCEEDED');
      await expectCode(mk(50, unavailable), 'MENU_ITEM_UNAVAILABLE');
    } finally {
      await db.collection('restaurants').doc(rid).update({ maxQtyPerItem: 50 });
    }
  });
  // ── 2c. Miqdorga chegirma (D-REST-25) ────────────────────────────────
  const tierMenu = () => db.collection('restaurants').doc(rid).collection('menu_items');
  const placeAndCancel = async (items) => {
    const r = await place(rid, CUSTOMER, { items });
    const od = await order(r.orderId);
    await call('customerCancelRestaurantOrder', { orderId: r.orderId }, CUSTOMER); // keyingi testlar uchun tozalash
    return { r, od };
  };
  await check('Q1 pog\'ona chegaralari: 9 dona — asosiy narx; 10 — 32 000; 12 — 384 000 (420 000 dan); 30 — 30 000; chegirma restoran hisobidan, AVA 2 % chegirmali summadan', async () => {
    await tierMenu().doc('tier').set({ name: 'Plov', price: 35000, available: true, categoryId: 'c1', sort: 9, qtyTiers: [{ minQty: 10, price: 32000 }, { minQty: 30, price: 30000 }] });
    const cases = [[9, 35000, 0, 315000, 0], [10, 32000, 10, 320000, 30000], [12, 32000, 10, 384000, 36000], [29, 32000, 10, 928000, 87000], [30, 30000, 30, 900000, 150000]];
    for (const [qty, unit, minQty, total, discount] of cases) {
      const { r, od } = await placeAndCancel([{ itemId: 'tier', qty }]);
      assert.strictEqual(r.itemsTotal, total, `qty ${qty}`);
      assert.strictEqual(od.itemsTotal, total);
      assert.strictEqual(od.qtyDiscountTotal, discount);
      assert.strictEqual(od.total, total + od.deliveryFee);
      assert.deepStrictEqual(od.items.map((i) => [i.price, i.unitPrice, i.tierMinQty, i.count, i.lineTotal, i.discount]), [[35000, unit, minQty, qty, total, discount]]);
      assert.strictEqual(od.avaFee.amount, tariffMod.computeAvaFee(total).amount, 'AVA ulushi CHEGIRMALI summadan');
    }
    assert.notStrictEqual(tariffMod.computeAvaFee(384000).amount, tariffMod.computeAvaFee(420000).amount, 'chegirma AVA ulushini kamaytiradi');
  });
  await check('Q2 bir taom bir nechta qatorda — son YIG\'INDI bo\'yicha (6+6 = 12 → pog\'ona); boshqa taom bilan aralash — har biri o\'zicha', async () => {
    const { od } = await placeAndCancel([{ itemId: 'tier', qty: 6 }, { itemId: 'tier', qty: 6 }, { itemId: 'somsa', qty: 2 }]);
    const byId = Object.fromEntries(od.items.map((i) => [i.itemId, i]));
    assert.deepStrictEqual([byId.tier.unitPrice, byId.tier.lineTotal, byId.tier.count], [32000, 384000, 12]);
    assert.deepStrictEqual([byId.somsa.unitPrice, byId.somsa.tierMinQty, byId.somsa.discount, byId.somsa.lineTotal], [10000, 0, 0, 20000], 'pog\'onasiz taom o\'zgarmaydi');
    assert.strictEqual(od.itemsTotal, 384000 + 20000);
    assert.strictEqual(od.qtyDiscountTotal, 36000);
  });
  await check('Q3 klient narx/chegirma yubora olmaydi: items ichidagi price/unitPrice/discount/tierMinQty e\'tiborsiz', async () => {
    const { od } = await placeAndCancel([{ itemId: 'tier', qty: 10, price: 1, unitPrice: 1, discount: 999999, tierMinQty: 99, lineTotal: 1 }]);
    assert.deepStrictEqual([od.itemsTotal, od.items[0].unitPrice, od.items[0].tierMinQty], [320000, 32000, 10]);
  });
  await check('Q4 buzilgan hujjat (pog\'ona asosiy narxdan YUQORI, tartibsiz, noto\'g\'ri tip) narxni OSHIRMAYDI: server tozalaydi', async () => {
    await tierMenu().doc('tierbad').set({ name: 'Bad', price: 35000, available: true, categoryId: 'c1', sort: 10, qtyTiers: [{ minQty: 5, price: 40000 }] });
    let { od } = await placeAndCancel([{ itemId: 'tierbad', qty: 6 }]);
    assert.deepStrictEqual([od.itemsTotal, od.qtyDiscountTotal], [210000, 0], 'yuqori narxli pog\'ona qo\'llanmadi');
    await tierMenu().doc('tierbad').update({ qtyTiers: [{ minQty: 5, price: 30000 }, { minQty: 3, price: 20000 }, { minQty: 8, price: 10000 }] });
    ({ od } = await placeAndCancel([{ itemId: 'tierbad', qty: 9 }]));
    assert.deepStrictEqual([od.items[0].unitPrice, od.itemsTotal], [30000, 270000], 'birinchi noto\'g\'ri pog\'onadan keyingisi tashlandi');
    await tierMenu().doc('tierbad').update({ qtyTiers: [{ minQty: '5', price: 100 }, 'x', null] });
    ({ od } = await placeAndCancel([{ itemId: 'tierbad', qty: 9 }]));
    assert.deepStrictEqual([od.items[0].unitPrice, od.qtyDiscountTotal], [35000, 0]);
    await tierMenu().doc('tierbad').update({ qtyTiers: 'x' });
    ({ od } = await placeAndCancel([{ itemId: 'tierbad', qty: 9 }]));
    assert.strictEqual(od.itemsTotal, 315000);
  });
  await check('Q5 minimal buyurtma CHEGIRMALI summaga tekshiriladi (40 000 → 20 000 < 30 000 → MIN_ORDER_NOT_MET); menyu o\'zgarsa eski buyurtma narxi o\'zgarmaydi (snapshot)', async () => {
    await tierMenu().doc('tiermin').set({ name: 'Min', price: 10000, available: true, categoryId: 'c1', sort: 11, qtyTiers: [{ minQty: 4, price: 5000 }] });
    await expectCode(place(rid, CUSTOMER, { items: [{ itemId: 'tiermin', qty: 4 }] }), 'MIN_ORDER_NOT_MET', 'failed-precondition');
    const ok = await place(rid, CUSTOMER, { items: [{ itemId: 'tiermin', qty: 3 }, { itemId: 'osh', qty: 1 }] }); // 30 000 + 40 000, pog'ona qo'llanmaydi
    assert.strictEqual(ok.itemsTotal, 70000);
    await tierMenu().doc('tier').update({ price: 99000, qtyTiers: [] });
    const { od } = await placeAndCancel([{ itemId: 'tier', qty: 10 }]);
    assert.strictEqual(od.itemsTotal, 990000, 'yangi narx — yangi buyurtmada');
    const old = await order(ok.orderId);
    assert.strictEqual(old.itemsTotal, 70000, 'eski buyurtma o\'zgarmadi');
    await call('customerCancelRestaurantOrder', { orderId: ok.orderId }, CUSTOMER);
    await tierMenu().doc('tier').delete(); await tierMenu().doc('tierbad').delete(); await tierMenu().doc('tiermin').delete();
  });
  // ── 2d. Oldindan buyurtma (S4b) ──────────────────────────────────────
  const MINMS = 60 * 1000;
  const restRef = () => db.collection('restaurants').doc(rid);
  /** Toshkent (UTC+5) bo'yicha `daysAhead` kundan keyingi hh:mm — epoch ms. */
  const tashkentAt = (daysAhead, hh, mm = 0) => {
    const t = new Date(Date.now() + 5 * 3600 * 1000);
    return Date.UTC(t.getUTCFullYear(), t.getUTCMonth(), t.getUTCDate() + daysAhead, hh - 5, mm);
  };
  const tashkentHourNow = () => new Date(Date.now() + 5 * 3600 * 1000).getUTCHours();
  const pre = (ms, over = {}) => place(rid, CUSTOMER, { items: [{ itemId: 'osh', qty: 1 }, { itemId: 'somsa', qty: 2 }], scheduledForMs: ms, ...over });
  const cancelPre = (orderId) => call('customerCancelRestaurantOrder', { orderId }, CUSTOMER);

  await check('PO1 restoran belgisi yo\'q — PREORDER_NOT_ACCEPTED; belgi bilan — buyurtma: scheduledFor, isPreorder, qabul muddati min(2 soat, bajarilishdan 30 daq), natijada scheduledForMs; oddiy buyurtmada maydon YO\'Q', async () => {
    const at = Date.now() + 120 * MINMS;
    await expectCode(pre(at), 'PREORDER_NOT_ACCEPTED', 'failed-precondition');
    await restRef().update({ acceptsPreorder: true });
    const r = await pre(at);
    assert.strictEqual(r.scheduledForMs, at);
    const od = await order(r.orderId);
    assert.strictEqual(od.isPreorder, true);
    assert.strictEqual(od.scheduledFor.toMillis(), at);
    assert.strictEqual(od.restaurantStatus, 'placed');
    const expectedDeadline = Math.min(Date.now() + 120 * MINMS, at - 30 * MINMS);
    assert.ok(Math.abs(od.acceptDeadlineAt.toMillis() - expectedDeadline) < 10000, 'qabul muddati 90 daqiqa atrofida (120 daq oldindan: min(2 soat, 90 daq))');
    assert.strictEqual(r.acceptDeadlineAtMs, od.acceptDeadlineAt.toMillis());
    await cancelPre(r.orderId);
    const normal = await place(rid, CUSTOMER);
    const odn = await order(normal.orderId);
    assert.strictEqual('scheduledFor' in odn, false);
    assert.strictEqual('isPreorder' in odn, false);
    assert.ok(Math.abs(odn.acceptDeadlineAt.toMillis() - (Date.now() + 5 * MINMS)) < 10000, 'oddiy buyurtma — 5 daqiqa');
    await cancelPre(normal.orderId);
  });
  await check('PO2 oyna: 59 daqiqa — PREORDER_TOO_SOON; 61 daqiqa ok; 7 kundan uzoq — PREORDER_TOO_FAR; noto\'g\'ri tur — PREORDER_TIME_INVALID (buyurtma yaratilmaydi)', async () => {
    await expectCode(pre(Date.now() + 59 * MINMS), 'PREORDER_TOO_SOON');
    await expectCode(pre(Date.now() - 5 * MINMS), 'PREORDER_TOO_SOON');
    await expectCode(pre(Date.now() + 7 * 24 * 60 * MINMS + 5 * MINMS), 'PREORDER_TOO_FAR');
    for (const bad of ['1800000000000', 1.5, 0, -1, Number.NaN, true]) await expectCode(pre(bad), 'PREORDER_TIME_INVALID', 'invalid-argument');
    const ok = await pre(Date.now() + 61 * MINMS);
    await cancelPre(ok.orderId);
    const ok7 = await pre(Date.now() + 7 * 24 * 60 * MINMS - 5 * MINMS);
    await cancelPre(ok7.orderId);
  });
  await check('PO3 ish vaqti BAJARILISH vaqtida: hozir yopiq restoranga ertangi buyurtma mumkin; oddiy buyurtma — RESTAURANT_CLOSED; ish vaqtidan tashqari vaqt — PREORDER_CLOSED_AT_TIME', async () => {
    const h = tashkentHourNow();
    const hh = (n) => String((h + n) % 24).padStart(2, '0');
    await restRef().update({ openingHours: { open: `${hh(2)}:00`, close: `${hh(5)}:00` } }); // hozir YOPIQ
    try {
      await expectCode(place(rid, CUSTOMER), 'RESTAURANT_CLOSED');
      const inside = await pre(tashkentAt(2, (h + 3) % 24, 30));
      await cancelPre(inside.orderId);
      await expectCode(pre(tashkentAt(2, (h + 8) % 24, 0)), 'PREORDER_CLOSED_AT_TIME', 'failed-precondition');
      await expectCode(pre(tashkentAt(2, (h + 5) % 24, 0)), 'PREORDER_CLOSED_AT_TIME');
      const atOpen = await pre(tashkentAt(2, (h + 2) % 24, 0));
      await cancelPre(atOpen.orderId);
    } finally {
      await restRef().update({ openingHours: admin.firestore.FieldValue.delete() });
    }
  });
  await check('PO4 pauza bajarilishdan KEYIN tugasa — mumkin; bajarilish vaqtida ham davom etsa — RESTAURANT_PAUSED', async () => {
    const at = Date.now() + 3 * 60 * MINMS;
    await restRef().update({ pausedUntil: admin.firestore.Timestamp.fromMillis(at + 30 * MINMS) });
    try {
      await expectCode(pre(at), 'RESTAURANT_PAUSED');
      await expectCode(place(rid, CUSTOMER), 'RESTAURANT_PAUSED');
      await restRef().update({ pausedUntil: admin.firestore.Timestamp.fromMillis(Date.now() + 30 * MINMS) });
      const ok = await pre(at);
      await cancelPre(ok.orderId);
    } finally {
      await restRef().update({ pausedUntil: admin.firestore.FieldValue.delete() });
    }
  });
  await check('PO5 yetkazish narxining tungi koeffitsienti BAJARILISH vaqtiga qarab (02:00 — tungi, 14:00 — kunduzgi); quoteRestaurantDelivery ham', async () => {
    const day = await pre(tashkentAt(2, 14, 0));
    const night = await pre(tashkentAt(2, 2, 0));
    const od1 = await order(day.orderId);
    const od2 = await order(night.orderId);
    assert.strictEqual(od1.deliveryTariffSnapshot.night, false);
    assert.strictEqual(od2.deliveryTariffSnapshot.night, true);
    assert.ok(od2.deliveryFee > od1.deliveryFee, `tungi ${od2.deliveryFee} > kunduzgi ${od1.deliveryFee}`);
    const qDay = await call('quoteRestaurantDelivery', { restaurantId: rid, ...C_LOC, scheduledForMs: tashkentAt(2, 14, 0) }, CUSTOMER);
    const qNight = await call('quoteRestaurantDelivery', { restaurantId: rid, ...C_LOC, scheduledForMs: tashkentAt(2, 2, 0) }, CUSTOMER);
    assert.strictEqual(qDay.deliveryFee, od1.deliveryFee);
    assert.strictEqual(qNight.deliveryFee, od2.deliveryFee);
    const qBad = await call('quoteRestaurantDelivery', { restaurantId: rid, ...C_LOC, scheduledForMs: 'x' }, CUSTOMER);
    assert.ok(qBad.deliveryFee > 0, 'noto\'g\'ri vaqt — oddiy hisob, xato emas');
    await cancelPre(day.orderId); await cancelPre(night.orderId);
  });
  await check('PO6 idempotent: bir xil kalit — bitta buyurtma, scheduledForMs saqlanadi', async () => {
    const k = key();
    const at = Date.now() + 5 * 60 * MINMS;
    const a = await pre(at, { idempotencyKey: k });
    const b = await pre(at, { idempotencyKey: k });
    assert.strictEqual(b.duplicate, true);
    assert.deepStrictEqual([b.orderId, b.scheduledForMs], [a.orderId, at]);
    await cancelPre(a.orderId);
  });
  await check('PO7 qabul qilingan oldindan buyurtma: kuryer ro\'yxatida YO\'Q, kuryer ololmaydi, «tayyor» bosilmaydi (PREORDER_TOO_EARLY) — oyna (90 daq) ochilgach hammasi ishlaydi', async () => {
    const at = Date.now() + 5 * 60 * MINMS;
    const r = await pre(at, { items: [{ itemId: 'osh', qty: 1 }, { itemId: 'somsa', qty: 2 }] });
    const acc = await call('restaurantAcceptOrder', { orderId: r.orderId, prepTimeMin: 30 }, STAFF);
    assert.strictEqual(acc.couriersNotified, 0);
    const listed = async () => (await call('listNearbyRestaurantOrders', { ...R_LOC }, COURIER_A)).orders.some((x) => x.id === r.orderId);
    assert.strictEqual(await listed(), false, 'kunlar oldin kuryer ro\'yxatiga chiqmaydi');
    await expectCode(call('courierClaimRestaurantOrder', { orderId: r.orderId }, COURIER_A), 'PREORDER_TOO_EARLY', 'failed-precondition');
    await expectCode(call('restaurantMarkReady', { orderId: r.orderId }, STAFF), 'PREORDER_TOO_EARLY', 'failed-precondition');
    assert.strictEqual((await order(r.orderId)).restaurantStatus, 'accepted');
    // 89 daqiqa qoldi — oyna ochiq
    await db.collection('orders').doc(r.orderId).update({ scheduledFor: admin.firestore.Timestamp.fromMillis(Date.now() + 89 * MINMS) });
    assert.strictEqual(await listed(), true, 'oyna ochildi — kuryer ro\'yxatida');
    await call('restaurantMarkReady', { orderId: r.orderId }, STAFF);
    assert.strictEqual((await order(r.orderId)).restaurantStatus, 'ready');
    // tozalash: kuryer olmagan, restoran rad qiladi (2 % qaytadi)
    await call('restaurantRejectOrder', { orderId: r.orderId, reason: 'test' }, STAFF);
  });
  await check('PO8 oldindan buyurtmaning qabul muddati o\'tsa — taymaut (rad) oddiy yo\'l bilan; mijoz placed holatda bekor qila oladi', async () => {
    const r = await pre(Date.now() + 4 * 60 * MINMS);
    await db.collection('orders').doc(r.orderId).update({ acceptDeadlineAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000) });
    const res = await fns.expireUnacceptedRestaurantOrders.run({});
    assert.ok(res === null || res === undefined || typeof res === 'object');
    const od = await order(r.orderId);
    assert.strictEqual(od.restaurantStatus, 'rejected');
    assert.strictEqual(od.rejectReason, 'timeout');
    const c = await pre(Date.now() + 4 * 60 * MINMS);
    await cancelPre(c.orderId);
    assert.strictEqual((await order(c.orderId)).restaurantStatus, 'cancelled');
    await db.collection('restaurants').doc(rid).update({ timeoutStreak: 0, acceptsPreorder: false });
  });
  await check('S6 jonli nuqta tozalash: restoran rad qilsa o\'chadi; soatlik supurgi 2 soatdan eskisini o\'chiradi, yangisiga tegmaydi', async () => {
    const live = (id) => db.collection('order_courier_live').doc(id);
    const r = await place(rid, CUSTOMER);
    await live(r.orderId).set({ orderId: r.orderId, lat: 41.8, lng: 60.3, updatedAt: admin.firestore.Timestamp.now() });
    await call('restaurantRejectOrder', { orderId: r.orderId, reason: 'test' }, OWNER);
    assert.strictEqual((await live(r.orderId).get()).exists, false, 'rad — nuqta o\'chdi');
    const old = admin.firestore.Timestamp.fromMillis(Date.now() - 3 * 3600 * 1000);
    await live('sw_old').set({ orderId: 'sw_old', lat: 1, lng: 1, updatedAt: old });
    await live('sw_new').set({ orderId: 'sw_new', lat: 1, lng: 1, updatedAt: admin.firestore.Timestamp.now() });
    await fns.sweepRestaurantCourierLive.run({});
    assert.strictEqual((await live('sw_old').get()).exists, false);
    assert.strictEqual((await live('sw_new').get()).exists, true);
    await live('sw_new').delete();
  });
  await check('P3quoteRestaurantDelivery = buyurtmadagi narx', async () => {
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
  await check('A1b D-REST-15: BOSHQA restoran egasi (o\'z restorani bor, a\'zo) begona buyurtmaga tegolmaydi — accept/reject/ready/confirmPayment/delivered → NOT_RESTAURANT_MEMBER, hech narsa o\'zgarmaydi, 2 % yechilmaydi', async () => {
    const rid2x = await registerRestaurant(OWNER2, { name: 'Raqib kafe' });
    assert.ok((await db.collection('restaurants').doc(rid2x).collection('members').doc(OWNER2).get()).exists, 'o\'z restoranida a\'zo');
    // placed buyurtma — qabul urinishi
    const p = await place(rid, CUSTOMER);
    await expectCode(call('restaurantAcceptOrder', { orderId: p.orderId, prepTimeMin: 10 }, OWNER2), 'NOT_RESTAURANT_MEMBER', 'permission-denied');
    assert.strictEqual((await order(p.orderId)).restaurantStatus, 'placed');
    assert.strictEqual(await bonus(OWNER2), 0, 'raqib hamyonidan yechilmagan');
    await call('customerCancelRestaurantOrder', { orderId: p.orderId }, CUSTOMER);
    // accepted buyurtma (o1) — qolgan o'tishlar
    const before = await order(o1);
    const evBefore = await events(o1);
    const balBefore = await pcBal(OWNER);
    for (const fn of ['restaurantRejectOrder', 'restaurantMarkReady', 'restaurantConfirmPayment', 'restaurantMarkDelivered']) {
      await expectCode(call(fn, { orderId: o1, reason: 'raqib' }, OWNER2), 'NOT_RESTAURANT_MEMBER', 'permission-denied');
    }
    const after = await order(o1);
    assert.strictEqual(after.restaurantStatus, before.restaurantStatus);
    assert.strictEqual(after.paymentStatus, before.paymentStatus);
    assert.strictEqual(after.status, before.status);
    assert.strictEqual(await events(o1), evBefore, 'hodisa qo\'shilmagan');
    assert.strictEqual(await pcBal(OWNER), balBefore, 'egasi hamyoni o\'zgarmagan (rad → 2 % qaytmagan)');
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
  await check('KP yaqin kuryerlarga push (B5): qabulda — yaqin + limiti yetgan A ha, uzoqdagi B va limitsiz yaqin yo\'q; a\'zo/mijoz yo\'q; tayyor bo\'lganda 30 s ichida takror yo\'q; oldindan to\'lov — limitsiz ham', async () => {
    const presence = (id, loc) => db.collection('provider_presence').doc(id).set({
      providerId: id, module: 'courier', isOnline: true, lat: loc.lat, lng: loc.lng,
      updatedAt: admin.firestore.Timestamp.now(),
    });
    const NEAR_NO_LIMIT = '998913000003';
    await db.collection('users').doc(NEAR_NO_LIMIT).set({ role: 'user', bonusBalance: 0 });
    await presence(COURIER_A, { lat: R_LOC.lat + 0.001, lng: R_LOC.lng }); // ~110 m
    await presence(COURIER_B, { lat: 41.3, lng: 69.2 }); // Toshkent — radiusdan tashqarida
    await presence(NEAR_NO_LIMIT, { lat: R_LOC.lat, lng: R_LOC.lng + 0.002 }); // yaqin, vykup limiti yo'q
    await presence(OWNER, { lat: R_LOC.lat, lng: R_LOC.lng }); // restoran egasi — a'zo
    await presence(CUSTOMER, { lat: R_LOC.lat, lng: R_LOC.lng }); // mijozning o'zi
    const prefOf = async (id) => (await db.collection('restaurant_courier_prefs').doc(id).get()).data() || {};

    const r1 = await place(rid, CUSTOMER, { foodPaymentMethod: 'cash_buyout', deliveryPaymentMethod: 'cash' });
    const acc = await call('restaurantAcceptOrder', { orderId: r1.orderId }, OWNER);
    assert.strictEqual(acc.couriersNotified, 1, `faqat A: ${JSON.stringify(acc)}`);
    assert.strictEqual((await prefOf(COURIER_A)).lastPushOrderId, r1.orderId);
    assert.strictEqual((await prefOf(COURIER_A)).lastPushStage, 'accepted');
    assert.strictEqual((await prefOf(COURIER_B)).lastPushOrderId, undefined, 'uzoqdagi B push olmaydi');
    assert.strictEqual((await prefOf(NEAR_NO_LIMIT)).lastPushOrderId, undefined, 'vykup limitsiz push olmaydi');
    assert.strictEqual((await prefOf(OWNER)).lastPushOrderId, undefined, 'a\'zo push olmaydi');
    assert.strictEqual((await prefOf(CUSTOMER)).lastPushOrderId, undefined, 'mijoz push olmaydi');
    const ready = await call('restaurantMarkReady', { orderId: r1.orderId }, OWNER);
    assert.strictEqual(ready.couriersNotified, 0, 'A 30 s ichida takror push olmaydi');

    const r2 = await place(rid, CUSTOMER); // prepay/wallet — vykup kerak emas
    const acc2 = await call('restaurantAcceptOrder', { orderId: r2.orderId }, OWNER);
    assert.strictEqual(acc2.couriersNotified, 1, 'A throttle, NEAR_NO_LIMIT oldindan to\'lovda mos');
    assert.strictEqual((await prefOf(NEAR_NO_LIMIT)).lastPushOrderId, r2.orderId);

    // Kuryer olgan buyurtma tayyor bo'lsa — yaqinlarga push yo'q (faqat o'sha kuryerga xabar).
    await db.collection('restaurant_courier_prefs').doc(NEAR_NO_LIMIT).delete();
    await call('courierClaimRestaurantOrder', { orderId: r2.orderId }, COURIER_A);
    const ready2 = await call('restaurantMarkReady', { orderId: r2.orderId }, OWNER);
    assert.strictEqual(ready2.couriersNotified, 0);
    for (const id of [r1.orderId, r2.orderId]) await call('restaurantRejectOrder', { orderId: id, reason: 'test' }, OWNER);
    await Promise.all([COURIER_A, COURIER_B, NEAR_NO_LIMIT, OWNER, CUSTOMER].map((id) => db.collection('provider_presence').doc(id).delete()));
    await db.collection('restaurant_courier_prefs').doc(COURIER_A).set({ buyoutEnabled: true, buyoutLimit: 100000 });
  });
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
  await check('K2 ikki kuryer bir vaqtda oladi → bittasi; marshrut hujjati; takror idempotent; boshqasi CONFLICT; olgan kuryerning ismi buyurtmaga yoziladi (S6)', async () => {
    await db.collection('users').doc(COURIER_A).update({ name: 'Ali Valiyev' });
    await db.collection('users').doc(COURIER_B).update({ name: 'Bobur' });
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
    assert.strictEqual(od.courierName, od.courierId === COURIER_A ? 'Ali Valiyev' : 'Bobur', 'kuryer ismi (faqat ishtirokchilar o\'qiydi)');
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
    await db.collection('order_courier_live').doc(o1).set({ orderId: o1, lat: 41.84, lng: 60.39, updatedAt: admin.firestore.Timestamp.now() });
    const r = await call('courierCompleteRestaurantDelivery', { orderId: o1, outcome: 'delivered' }, COURIER_A);
    assert.strictEqual((await db.collection('order_courier_live').doc(o1).get()).exists, false, 'yetkazish tugadi — jonli nuqta o\'chdi (S6)');
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
    assert.strictEqual(lA.orders.find((x) => x.id === r.orderId).buyoutAmount, 60000);
    await call('courierClaimRestaurantOrder', { orderId: r.orderId }, COURIER_A);
    await call('restaurantMarkReady', { orderId: r.orderId }, OWNER);
    await call('courierPickupRestaurantOrder', { orderId: r.orderId, pickupCode: (await secret(r.orderId)).pickupCode }, COURIER_A);
    let od = await order(r.orderId);
    assert.strictEqual(od.paymentStatus, 'paid');
    assert.strictEqual(od.paidBy, 'courier_buyout');
    assert.strictEqual(od.buyoutAmount, 60000);
    await call('courierArriveRestaurantOrder', { orderId: r.orderId }, COURIER_A);
    const j0 = await journalBalanced();
    const res = await call('courierCompleteRestaurantDelivery', { orderId: r.orderId, outcome: 'delivered' }, COURIER_A);
    assert.strictEqual(res.cashCollected, 60000 + feeAva);
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

  // ── 6. Admin paneli (B4) ────────────────────────────────────────────
  await check('AD1 tarif: begona/noto\'g\'ri rad; saqlash → v2, tarix v2 (previous v1), audit; yangi buyurtma v2 bilan', async () => {
    const valid = { base: 6000, perKm: 2000, nightCoef: 1.5, nightStart: 23, nightEnd: 6, roadFactor: 1.3, maxKm: 20, regions: { xorazm: { base: 5500, perKm: 1800 } }, reason: 'yoqilg\'i' };
    await expectCode(call('adminSetRestaurantDeliveryPrices', valid, STRANGER), 'Admin role required', 'permission-denied');
    await expectCode(call('adminSetRestaurantDeliveryPrices', { ...valid, base: 0 }, ADMIN), 'PRICE_INVALID');
    await expectCode(call('adminSetRestaurantDeliveryPrices', { ...valid, perKm: 1500.5 }, ADMIN), 'PRICE_INVALID');
    await expectCode(call('adminSetRestaurantDeliveryPrices', { ...valid, nightCoef: 5 }, ADMIN), 'NIGHT_COEF_INVALID');
    await expectCode(call('adminSetRestaurantDeliveryPrices', { ...valid, nightStart: 24 }, ADMIN), 'NIGHT_HOURS_INVALID');
    await expectCode(call('adminSetRestaurantDeliveryPrices', { ...valid, roadFactor: 3 }, ADMIN), 'ROAD_FACTOR_INVALID');
    await expectCode(call('adminSetRestaurantDeliveryPrices', { ...valid, regions: { mars: { base: 1, perKm: 1 } } }, ADMIN), 'REGION_UNKNOWN');
    await expectCode(call('adminSetRestaurantDeliveryPrices', { ...valid, regions: { xorazm: { base: 5500, perKm: 1800, maxKm: 0 } } }, ADMIN), 'MAX_KM_INVALID');
    const r = await call('adminSetRestaurantDeliveryPrices', valid, ADMIN);
    assert.strictEqual(r.version, 2, 'seed v1 → v2');
    const doc = (await db.collection('settings').doc('restaurant_delivery').get()).data();
    assert.strictEqual(doc.base, 6000);
    assert.strictEqual(doc.perKm, 2000);
    assert.strictEqual(doc.version, 2);
    assert.strictEqual(doc.updatedBy, ADMIN);
    assert.deepStrictEqual(doc.regions, { xorazm: { base: 5500, perKm: 1800 } });
    const h = (await db.collection('restaurant_delivery_tariffs').doc('v2').get()).data();
    assert.strictEqual(h.version, 2);
    assert.strictEqual(h.previous.version, 1);
    assert.strictEqual(h.previous.base, 5000);
    assert.strictEqual(h.changedBy, ADMIN);
    assert.strictEqual(h.reason, 'yoqilg\'i');
    const audit = await db.collection('admin_audit').where('kind', '==', 'restaurant_delivery_tariff').get();
    assert.strictEqual(audit.size, 1);
    assert.strictEqual(audit.docs[0].data().to, '2');
    // Yangi buyurtma yangi versiya bilan; narx Xorazm mintaqasidan (Gurlan).
    const o = await place(rid, CUSTOMER);
    const od = await order(o.orderId);
    assert.strictEqual(od.deliveryTariffVersion, 2);
    assert.strictEqual(od.deliveryTariffSnapshot.base, 5500, 'mintaqa narxi');
    await call('customerCancelRestaurantOrder', { orderId: o.orderId }, CUSTOMER);
    // Keyingi testlar uchun — seed tarifi (v3).
    const back = await call('adminSetRestaurantDeliveryPrices', { ...TARIFF, regions: {}, reason: 'qaytarish' }, ADMIN);
    assert.strictEqual(back.version, 3);
    assert.strictEqual(((await db.collection('restaurant_delivery_tariffs').doc('v3').get()).data()).previous.base, 6000);
  });
  await check('AD2 avto-tasdiq: o\'chirilsa yangi restoran `applied`; audit; qayta yoqiladi', async () => {
    await expectCode(call('adminSetRestaurantAutoApprove', { enabled: false }, STRANGER), 'Admin role required', 'permission-denied');
    await call('adminSetRestaurantAutoApprove', { enabled: false }, ADMIN);
    assert.strictEqual((await db.collection('settings').doc('app').get()).data().restaurantAutoApprove, false);
    const r = await call('restaurantRegister', { name: 'Yangi kafe', address: 'x', ...R_LOC, delivery: { mode: 'none', pickup: true } }, CUSTOMER2);
    assert.strictEqual((await db.collection('restaurants').doc(r.restaurantId).get()).data().status, 'applied');
    const audit = await db.collection('admin_audit').where('kind', '==', 'restaurant_auto_approve').get();
    assert.strictEqual(audit.size, 1);
    await call('adminSetRestaurantAutoApprove', { enabled: true }, ADMIN);
    assert.strictEqual((await db.collection('settings').doc('app').get()).data().restaurantAutoApprove, true);
  });
  await check('AD3 bosqich: internal + testerlar (har xil yozuv) → faqat tester; STAGE_INVALID; `enabled` saqlanadi; public qaytadi', async () => {
    await db.collection('module_config').doc('restaurants_all').set({ enabled: true }, { merge: true });
    await expectCode(call('adminSetRestaurantsStage', { stage: 'beta' }, ADMIN), 'STAGE_INVALID');
    await expectCode(call('adminSetRestaurantsStage', { stage: 'public' }, STRANGER), 'Admin role required', 'permission-denied');
    const r = await call('adminSetRestaurantsStage', { stage: 'internal', testerIds: [`+${CUSTOMER2}`, CUSTOMER2.slice(3), 'abc'] }, ADMIN);
    assert.deepStrictEqual(r.testerIds, [CUSTOMER2], 'kanonik, takrorsiz, noto\'g\'ri tashlanadi');
    const cfg = (await db.collection('module_config').doc('restaurants_all').get()).data();
    assert.strictEqual(cfg.enabled, true, 'boshqa kalit tegilmadi');
    assert.strictEqual(cfg.restaurants.stage, 'internal');
    assert.strictEqual((await call('getRestaurantsAccess', {}, CUSTOMER)).allowed, false);
    assert.strictEqual((await call('getRestaurantsAccess', {}, CUSTOMER2)).allowed, true);
    const audit = await db.collection('admin_audit').where('kind', '==', 'restaurants_stage').get();
    assert.strictEqual(audit.size, 1);
    assert.strictEqual(audit.docs[0].data().from, 'public');
    await call('adminSetRestaurantsStage', { stage: 'public', testerIds: [] }, ADMIN);
    assert.strictEqual((await call('getRestaurantsAccess', {}, CUSTOMER)).allowed, true);
  });
  await check('AD4 admin bekor: accepted+kuryerda → cancelled, 2 % qaytadi, marshrutdan olinadi (bo\'sh → yopiladi), audit, idempotent; yakunlangan → ORDER_ALREADY_FINAL', async () => {
    const r = await place(rid, CUSTOMER);
    await call('restaurantAcceptOrder', { orderId: r.orderId }, OWNER);
    await call('courierClaimRestaurantOrder', { orderId: r.orderId }, COURIER_B);
    const o0 = await pcBal(OWNER);
    await expectCode(call('adminCancelRestaurantOrder', { orderId: r.orderId, reason: 'x' }, STRANGER), 'Admin role required', 'permission-denied');
    const res = await call('adminCancelRestaurantOrder', { orderId: r.orderId, reason: 'mijoz qo\'ng\'iroq qildi' }, ADMIN);
    assert.strictEqual(res.from, 'accepted');
    assert.strictEqual(res.refundAmount, 1200);
    assert.strictEqual(await pcBal(OWNER), o0 + 1200, '2 % qaytdi');
    const od = await order(r.orderId);
    assert.strictEqual(od.restaurantStatus, 'cancelled');
    assert.strictEqual(od.status, 'cancelled');
    assert.strictEqual(od.cancelledBy, `admin:${ADMIN}`);
    assert.strictEqual(od.avaFee.refunded, true);
    const route = (await db.collection('delivery_routes').doc(od.deliveryRouteId).get()).data();
    assert.deepStrictEqual(route.orders, []);
    assert.strictEqual(route.status, 'completed');
    assert.strictEqual(route.completedReason, 'admin_cancelled');
    const again = await call('adminCancelRestaurantOrder', { orderId: r.orderId }, ADMIN);
    assert.strictEqual(again.idempotent, true);
    assert.strictEqual(await pcBal(OWNER), o0 + 1200, 'ikkinchi marta qaytmadi');
    const audit = await db.collection('admin_audit').where('kind', '==', 'restaurant_order_cancel').get();
    assert.strictEqual(audit.size, 1);
    const ev = await db.collection('orders').doc(r.orderId).collection('order_events').where('actor', '==', 'admin').get();
    assert.strictEqual(ev.size, 1);
    // Yakunlangan (mijoz bekor qilgan) buyurtma — admin ham o'zgartira olmaydi.
    const r2 = await place(rid, CUSTOMER);
    await call('customerCancelRestaurantOrder', { orderId: r2.orderId }, CUSTOMER);
    await expectCode(call('adminCancelRestaurantOrder', { orderId: r2.orderId }, ADMIN), 'ORDER_ALREADY_FINAL');
  });

  // ── 6b. Taom kuxnalari (D-REST-24) ──────────────────────────────────
  const cz = require('../restaurant_cuisines');
  const cuisines = () => db.collection('restaurant_cuisines');
  const addCuisine = (who, name, group = 'national', restaurantId = rid) =>
    call('restaurantAddCuisine', { restaurantId, name, group }, who);

  await check('CU1 nom kaliti: kirill/lotin/apostrof variantlari bitta; harfsiz nom kalitida harf yo\'q; id ≤ 80 va oxirida "-" yo\'q', () => {
    const k = cz.cuisineKey;
    assert.strictEqual(k('Ўзбек'), 'ozbek');
    for (const v of ["O'zbek", 'O‘zbek', 'Oʻzbek', 'o`zbek', '  O\'ZBEK  ']) assert.strictEqual(k(v), 'ozbek', v);
    assert.strictEqual(k('Қашқадарё миллий таомлари'), k('Qashqadaryo  milliy   taomlari'));
    assert.strictEqual(k('Самарқанд миллий таомлари'), 'samarqand milliy taomlari');
    assert.ok(!/[a-z]/.test(k('123 !!')), 'harfsiz');
    assert.strictEqual(k(null), '');
    const long = cz.cleanName('Щ'.repeat(60));
    assert.strictEqual(long.length, 40, 'nom 40 belgiga qisqartiriladi');
    const id = cz.cuisineDocId('national', cz.cuisineKey(long));
    assert.ok(id.length <= 80 && !id.endsWith('-'), id);
    assert.strictEqual(cz.cuisineDocId('world', 'a b'), 'world_a-b');
  });
  await check('CU2 a\'zo o\'z nomini qo\'shadi → hujjat (group, nameKey, createdBy); boshqa yozuvda qayta — o\'sha id, takror yaratilmaydi', async () => {
    const r = await addCuisine(OWNER, 'Қашқадарё миллий таомлари');
    assert.strictEqual(r.existed, false);
    assert.strictEqual(r.group, 'national');
    assert.strictEqual(r.id, 'national_qashqadaryo-milliy-taomlari');
    const doc = (await cuisines().doc(r.id).get()).data();
    assert.strictEqual(doc.name, 'Қашқадарё миллий таомлари');
    assert.strictEqual(doc.nameKey, 'qashqadaryo milliy taomlari');
    assert.strictEqual(doc.createdBy, OWNER);
    assert.strictEqual(doc.hidden, false);
    const again = await addCuisine(STAFF, "Qashqadaryo milliy taomlari");
    assert.strictEqual(again.existed, true);
    assert.strictEqual(again.id, r.id);
    assert.strictEqual(again.name, 'Қашқадарё миллий таомлари', 'birinchi yozilgan ko\'rinish saqlanadi');
    assert.strictEqual((await cuisines().get()).size, 1);
    // bir xil nom boshqa GURUHDA — alohida kuxna
    const w = await addCuisine(OWNER, 'Qashqadaryo milliy taomlari', 'world');
    assert.strictEqual(w.existed, false);
    assert.strictEqual(w.id, 'world_qashqadaryo-milliy-taomlari');
    await cuisines().doc(w.id).delete();
  });
  await check('CU3 rad: a\'zo emas, noto\'g\'ri guruh, bo\'sh/harfsiz/qisqa nom, restoran id yo\'q, kirish yo\'q', async () => {
    await expectCode(addCuisine(STRANGER, 'Xorazm'), 'NOT_RESTAURANT_MEMBER', 'permission-denied');
    await expectCode(addCuisine(OWNER2, 'Xorazm'), 'NOT_RESTAURANT_MEMBER', 'permission-denied');
    await expectCode(addCuisine(OWNER, 'Xorazm', 'asia'), 'CUISINE_GROUP_INVALID');
    for (const bad of ['', '   ', 'a', '123', '!!!', '——']) {
      await expectCode(addCuisine(OWNER, bad), 'CUISINE_NAME_INVALID');
    }
    await expectCode(call('restaurantAddCuisine', { name: 'Xorazm', group: 'national' }, OWNER), 'RESTAURANT_ID_REQUIRED');
    await expectCode(fns.restaurantAddCuisine.run({ restaurantId: rid, name: 'Xorazm', group: 'national' }, {}), 'AUTH_REQUIRED', 'unauthenticated');
    assert.strictEqual((await cuisines().get()).size, 1, 'rad etilganlar hujjat yaratmaydi');
  });
  await check('CU4 parallel 6 ta bir xil nom → bitta hujjat, bitta "created"; kunlik hisob faqat yaratilganlarni sanaydi (22-qoida)', async () => {
    const out = await Promise.all(Array.from({ length: 6 }, (_, i) => addCuisine(i % 2 ? OWNER : STAFF, i % 2 ? 'Xorazm taomlari' : 'Хоразм таомлари')));
    assert.strictEqual(out.filter((x) => !x.existed).length, 1, 'bitta g\'olib');
    assert.strictEqual(new Set(out.map((x) => x.id)).size, 1);
    assert.strictEqual((await cuisines().where('nameKey', '==', 'xorazm taomlari').get()).size, 1);
    // Kunlik hisob faqat YARATILGAN nomlarni sanaydi: CU2 da 2 ta (milliy + dunyo, dunyosi
    // keyin o'chirilgan — hisob qoladi) + bu yerda 1 ta = 3; 5 ta takror sanalmaydi.
    const total = (await db.collection('restaurant_cuisine_quota').get()).docs.reduce((a, s) => a + s.data().count, 0);
    assert.strictEqual(total, 3);
  });
  await check('CU5 kunlik chegara: 5 yangi nom ok, 6-si CUISINE_RATE_LIMIT; BOR nom chegaradan keyin ham qaytadi; boshqa foydalanuvchi o\'z hisobida', async () => {
    await db.collection('restaurant_cuisine_quota').get().then((s) => Promise.all(s.docs.map((d) => d.ref.delete())));
    for (let i = 0; i < cz.DAILY_NEW_LIMIT; i += 1) {
      const r = await addCuisine(OWNER, `Test kuxna ${String.fromCharCode(97 + i)}${String.fromCharCode(97 + i)}`);
      assert.strictEqual(r.existed, false);
    }
    await expectCode(addCuisine(OWNER, 'Test kuxna zz'), 'CUISINE_RATE_LIMIT', 'resource-exhausted');
    const old = await addCuisine(OWNER, 'Test kuxna aa');
    assert.strictEqual(old.existed, true, 'bor nom — hisobga kirmaydi');
    const other = await addCuisine(STAFF, 'Test kuxna zz');
    assert.strictEqual(other.existed, false, 'STAFF o\'z hisobida');
  });
  await check('CU6 admin yashiradi: begona rad; audit; idempotent; yashirin nom qayta qo\'shilmaydi (CUISINE_BLOCKED); qaytarsa ishlaydi', async () => {
    const id = 'national_qashqadaryo-milliy-taomlari';
    await expectCode(call('adminSetRestaurantCuisineHidden', { cuisineId: id, hidden: true }, OWNER), 'Admin role required');
    const r = await call('adminSetRestaurantCuisineHidden', { cuisineId: id, hidden: true, reason: 'test' }, ADMIN);
    assert.deepStrictEqual({ hidden: r.hidden, changed: r.changed }, { hidden: true, changed: true });
    assert.strictEqual((await cuisines().doc(id).get()).data().hidden, true);
    const again = await call('adminSetRestaurantCuisineHidden', { cuisineId: id, hidden: true }, ADMIN);
    assert.strictEqual(again.changed, false);
    const audits = await db.collection('admin_audit').where('kind', '==', 'restaurant_cuisine_hidden').get();
    assert.strictEqual(audits.size, 1, 'audit faqat o\'zgarganda');
    await expectCode(addCuisine(OWNER, 'Qashqadaryo milliy taomlari'), 'CUISINE_BLOCKED', 'failed-precondition');
    await expectCode(call('adminSetRestaurantCuisineHidden', { cuisineId: 'yoq_id', hidden: true }, ADMIN), 'CUISINE_NOT_FOUND');
    await expectCode(call('adminSetRestaurantCuisineHidden', { cuisineId: id }, ADMIN), 'HIDDEN_REQUIRED');
    await call('adminSetRestaurantCuisineHidden', { cuisineId: id, hidden: false }, ADMIN);
    assert.strictEqual((await addCuisine(OWNER, 'Qashqadaryo milliy taomlari')).existed, true);
  });

  await check('CU7 tayyor kuxnalar (seed): 16 ta, id ≤ 80, 3 tilda; sotuvchi kirill/lotin yozsa tayyor hujjatga tushadi, takror yaratilmaydi', async () => {
    const { buildDocs } = require('../tools/seed_restaurant_cuisines');
    const docs = buildDocs();
    assert.strictEqual(docs.length, 16);
    assert.strictEqual(new Set(docs.map((d) => d.id)).size, 16);
    for (const { id, data } of docs) {
      assert.ok(id.length <= 80, id);
      assert.ok(['national', 'world'].includes(data.group));
      assert.ok(data.names.uz_Cyrl && data.names.uz_Latn && data.names.ru, id);
      await cuisines().doc(id).create(data); // seed `--apply` bilan bir xil
    }
    const before = (await cuisines().get()).size;
    const a = await addCuisine(OWNER, 'Ўзбек');
    const b = await addCuisine(OWNER, "O‘zbek");
    const c = await addCuisine(OWNER, 'Хитой', 'world');
    const d = await addCuisine(OWNER, 'Farg`ona');
    assert.deepStrictEqual([a.id, a.existed], ['national_ozbek', true]);
    assert.deepStrictEqual([b.id, b.existed], ['national_ozbek', true]);
    assert.deepStrictEqual([c.id, c.existed], ['world_xitoy', true]);
    assert.deepStrictEqual([d.id, d.existed], ['national_fargona', true]);
    assert.strictEqual((await cuisines().get()).size, before, 'takror hujjat yaratilmadi');
  });

  // ── 6c. Taom o'chirilsa video ham o'chadi (D-REST-30) ────────────────
  await check('DV1 taom o\'chirilsa FAQAT shu taomning klip(lar)i o\'chadi (xodim yuklagani ham); boshqa taom/restoran videosi/boshqa restoran saqlanadi; takror — xato yo\'q', async () => {
    const clips = db.collection('tv_clips');
    const mk = (id, extra) => clips.doc(id).set({ ownerPhone: STAFF, status: 'active', category: 'product', ...extra });
    await mk('dv_a1', { linkKind: 'restaurant_item', linkId: rid, linkItemId: 'osh' });
    await mk('dv_a2', { linkKind: 'restaurant_item', linkId: rid, linkItemId: 'osh', status: 'pending', ownerPhone: OWNER });
    await mk('dv_b1', { linkKind: 'restaurant_item', linkId: rid, linkItemId: 'somsa' });
    await mk('dv_rest', { linkKind: 'restaurant', linkId: rid });
    await mk('dv_other', { linkKind: 'restaurant_item', linkId: 'r9', linkItemId: 'osh' });
    await mk('dv_plain', {});
    const gone = await db.collection('restaurants').doc(rid).collection('menu_items').doc('osh').get();
    await db.collection('restaurants').doc(rid).collection('menu_items').doc('osh').delete();
    await fns.onRestaurantMenuItemDeleted.run(gone, { params: { rid, iid: 'osh' } });
    const left = async () => (await clips.get()).docs.map((d) => d.id).filter((id) => id.startsWith('dv_')).sort();
    assert.deepStrictEqual(await left(), ['dv_b1', 'dv_other', 'dv_plain', 'dv_rest']);
    await fns.onRestaurantMenuItemDeleted.run(gone, { params: { rid, iid: 'osh' } }); // idempotent
    assert.deepStrictEqual(await left(), ['dv_b1', 'dv_other', 'dv_plain', 'dv_rest']);
  });
  await check('DV2 videosi yo\'q taom — xato yo\'q; 130 ta bog\'langan klip (takror yuklash) ham to\'liq o\'chadi', async () => {
    const snap = await db.collection('restaurants').doc(rid).collection('menu_items').doc('somsa').get();
    await fns.onRestaurantMenuItemDeleted.run(snap, { params: { rid, iid: 'yo_q_taom' } });
    const batchSize = 130;
    for (let i = 0; i < batchSize; i += 100) {
      const b = db.batch();
      for (let j = i; j < Math.min(i + 100, batchSize); j += 1) {
        b.set(db.collection('tv_clips').doc(`dv_many_${j}`), { ownerPhone: OWNER, status: 'active', linkKind: 'restaurant_item', linkId: rid, linkItemId: 'many' });
      }
      await b.commit();
    }
    await fns.onRestaurantMenuItemDeleted.run(snap, { params: { rid, iid: 'many' } });
    const rest = (await db.collection('tv_clips').where('linkItemId', '==', 'many').get()).size;
    assert.strictEqual(rest, 0);
  });

  // ── 7. Sverka ───────────────────────────────────────────────────────
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
