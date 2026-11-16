/**
 * «БОЗОРЛАР» STAGE 11 (эга 2026-11-16) — ўз дўкони (businessId'сиз) ва бозор эълонлари бизнес буюртма
 * занжирида: ҲАҚИҚИЙ `functions/index.js` callable'лари `.run()` орқали, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-biz-shop \
 *     "node test/business_orders_shop_cf.test.js"
 *
 * Қулфланади: босқич OFF → ёпиқ; ўз дўкони маҳсулоти буюртма бўлади (сотувчи = ownerPhone, нарх серверда);
 * бозор бўлими orderable → OK + snapshot (market/category/taxonomyVersion); livestock / auto cars →
 * ITEM_NOT_ORDERABLE; таксономия йўқ → ITEM_NOT_ORDERABLE; pending/blocked/status'сиз бозор эълони → рад;
 * аралаш сотувчи / объектга боғланган маҳсулот → ITEM_NOT_IN_SHOP; ўз маҳсулоти, блок дўкон, олиб кетиш
 * нуқтаси йўқ → рад; сотувчи рухсати (бегона рад, эга қабул/тайёр/рад), курьер оқими delivered'гача;
 * объект режими + бозор (регрессия); pilot `itemId` орқали; «етказилмади» рўйхати ўз дўкони сотувчисига.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18497';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-biz-shop';
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.DIRECTIONS_API_KEY = '';
process.env.CUSTOMER_CONFIRM_CACHE_MS = '0';
process.env.BUSINESS_ORDERS_TAXONOMY_CACHE_MS = '0';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* лойиҳа керак, берилган: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require('../index');
const admin = require('firebase-admin');
const bo = require('../business_orders');
const dfLib = require('../delivery_failed');

const db = admin.firestore();

const SHOP = '998931100001'; // ўз дўкони сотувчиси (объекти йўқ)
const SHOP2 = '998931100002';
const BIZ_SELLER = '998931000001';
const BUYER = '998932000001';
const STRANGER = '998934000001';
const COURIER_A = '998933000001';
const ACC = { [COURIER_A]: 'accSHOP0000000000A' };

const S_LOC = { lat: 41.8406, lng: 60.3917 };
const C_LOC = { lat: 41.8586, lng: 60.3917 };
const TARIFF = { base: 6000, perKm: 1500, nightCoef: 1.5, nightStart: 23, nightEnd: 6, roadFactor: 1.3, maxKm: 15, version: 3 };

const n3 = (s) => ({ uz_Cyrl: s, uz_Latn: s, ru: s });
const TAXONOMY = {
  version: 3,
  markets: {
    livestock: { moduleId: 'livestock_market', categories: [{ id: 'all', names: n3('all'), orderable: false }] },
    auto: {
      moduleId: 'auto_market',
      categories: [
        { id: 'cars', names: n3('cars'), orderable: false },
        { id: 'moto', names: n3('moto'), orderable: false },
        { id: 'parts', names: n3('parts'), orderable: true },
      ],
    },
    meat: { moduleId: 'meat_market', categories: [{ id: 'beef', names: n3('beef'), orderable: true }] },
    farm: { moduleId: 'farm_market', categories: [{ id: 'vegetables', names: n3('veg'), orderable: true }] },
  },
};

const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, ctxOf(who));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
async function expectCode(promise, code, httpsCode) {
  await assert.rejects(promise, (e) => {
    const got = (e.details && (e.details.code || e.details.reason)) || e.message;
    assert.strictEqual(got, code, `код ${got} (${e.code}): ${e.message}`);
    if (httpsCode) assert.strictEqual(e.code, httpsCode);
    return true;
  });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const order = async (id) => (await db.collection('orders').doc(id).get()).data() || {};
const secret = async (id) => (await db.collection('orders').doc(id).collection('private').doc('secrets').get()).data() || {};
let keySeq = 0;
const key = () => `shop_test_${Date.now()}_${keySeq += 1}`;

const base = { ownerPhone: SHOP, kind: 'product', status: 'active', districtId: 'gurlan' };
const ITEMS = {
  s1: { ...base, price: 10000, title: 'Aralash buyum' },
  sMeat: { ...base, price: 80000, priceUnit: 'kg', market: 'meat', category: 'beef', regionId: 'xorazm', taxonomyVersion: 3, title: 'Mol go\'shti' },
  sParts: { ...base, price: 150000, priceUnit: '', market: 'auto', category: 'parts', title: 'Fara' },
  sCar: { ...base, price: 90000000, priceUnit: '', market: 'auto', category: 'cars', title: 'Nexia' },
  sLive: { ...base, price: 5000000, priceUnit: 'piece', market: 'livestock', category: 'all', title: 'Sigir' },
  sCatUnknown: { ...base, price: 1000, priceUnit: 'kg', market: 'meat', category: 'xyz', title: 'nomalum' },
  sNoCat: { ...base, price: 1000, priceUnit: 'kg', market: 'meat', title: 'bo\'limsiz' },
  sPending: { ...base, price: 3000, priceUnit: 'kg', market: 'farm', category: 'vegetables', status: 'pending', title: 'kutilmoqda' },
  sNoStatusMarket: { ownerPhone: SHOP, kind: 'product', price: 3000, priceUnit: 'kg', market: 'farm', category: 'vegetables', title: 'status yo\'q' },
  sBlocked: { ...base, price: 3000, status: 'blocked', title: 'bloklangan' },
  sOther: { ...base, ownerPhone: SHOP2, price: 4000, title: 'boshqa sotuvchi' },
  sLinked: { ...base, businessId: 'biz1', ownerPhone: BIZ_SELLER, price: 4000, title: 'obyektga bog\'langan' },
  sBuyerOwn: { ...base, ownerPhone: BUYER, price: 4000, title: 'xaridorniki' },
  bMeat: { businessId: 'biz1', ownerPhone: BIZ_SELLER, kind: 'product', price: 70000, priceUnit: 'kg', status: 'active', market: 'meat', category: 'beef', title: 'obyekt go\'shti' },
  bLive: { businessId: 'biz1', ownerPhone: BIZ_SELLER, kind: 'product', price: 70000, priceUnit: 'piece', status: 'active', market: 'livestock', category: 'all', title: 'obyekt qo\'yi' },
  bPlain: { businessId: 'biz1', ownerPhone: BIZ_SELLER, kind: 'product', price: 20000, status: 'active', title: 'Kitob' },
};

async function reset() {
  await clearEmulator();
  await db.collection('server_config').doc('business_orders').set({ stage: 'public' });
  await db.collection('settings').doc('restaurant_delivery').set(TARIFF);
  await db.collection('taxonomy').doc('markets').set(TAXONOMY);
  for (const u of [SHOP, SHOP2, BIZ_SELLER, BUYER, STRANGER]) {
    await db.collection('users').doc(u).set({ role: 'user', name: `U${u.slice(-4)}`, bonusBalance: 0 });
  }
  await db.collection('users').doc(COURIER_A).set({ role: 'user', accountId: ACC[COURIER_A], bonusBalance: 0 });
  await db.collection('provider_capabilities').doc(ACC[COURIER_A]).set({
    identity: { accountId: ACC[COURIER_A], primaryUid: COURIER_A },
    courier: { active: true }, status: { courier: 'approved' },
  });
  await db.collection('restaurant_courier_prefs').doc(COURIER_A).set({ buyoutEnabled: true, buyoutLimit: 500000 });
  await db.collection('tv_shops').doc(SHOP).set({
    ownerPhone: SHOP, name: 'Sidabilla', pickupLat: S_LOC.lat, pickupLng: S_LOC.lng, pickupAddress: 'Gurlan bozor 5',
  });
  await db.collection('tv_shops').doc(SHOP2).set({ ownerPhone: SHOP2, name: 'Ikkinchi', ...{ pickupLat: S_LOC.lat, pickupLng: S_LOC.lng } });
  await db.collection('businesses').doc('biz1').set({
    ownerId: BIZ_SELLER, name: 'Gurlan kitob', address: 'Gurlan markaz', ...S_LOC,
    regionId: 'xorazm', districtId: 'gurlan', status: 'active',
  });
  for (const [id, d] of Object.entries(ITEMS)) await db.collection('tv_shop_items').doc(id).set(d);
}

const shopPlace = (items, over = {}, who = BUYER) => call('placeBusinessOrder', {
  idempotencyKey: key(), items, address: 'Mijoz uyi', ...C_LOC, deliveryPaymentMethod: 'cash', ...over,
}, who);
const shopQuote = (items, over = {}, who = BUYER) => call('quoteBusinessOrder', { items, ...C_LOC, ...over }, who);

async function main() {
  await reset();

  await check('P1 taxonomyOrderable (соф): market йўқ → ok; orderable → ok; false/номаълум/таксономиясиз → рад', async () => {
    assert.deepStrictEqual(bo.taxonomyOrderable({}, null), { ok: true, market: null, category: null });
    assert.deepStrictEqual(bo.taxonomyOrderable({ market: 'meat', category: 'beef' }, TAXONOMY), { ok: true, market: 'meat', category: 'beef' });
    assert.strictEqual(bo.taxonomyOrderable({ market: 'auto', category: 'cars' }, TAXONOMY).reason, 'CATEGORY_NOT_ORDERABLE');
    assert.strictEqual(bo.taxonomyOrderable({ market: 'livestock', category: 'all' }, TAXONOMY).reason, 'CATEGORY_NOT_ORDERABLE');
    assert.strictEqual(bo.taxonomyOrderable({ market: 'meat', category: 'xyz' }, TAXONOMY).reason, 'CATEGORY_UNKNOWN');
    assert.strictEqual(bo.taxonomyOrderable({ market: 'china', category: 'x' }, TAXONOMY).reason, 'MARKET_UNKNOWN');
    assert.strictEqual(bo.taxonomyOrderable({ market: 'meat', category: 'beef' }, null).reason, 'TAXONOMY_UNAVAILABLE');
    assert.strictEqual(bo.taxonomyOrderable({ market: 'toString', category: 'x' }, TAXONOMY).reason, 'MARKET_UNKNOWN', 'prototype калити');
    assert.strictEqual(bo.taxonomyOrderable({ market: 5, category: 'beef' }, TAXONOMY).ok, false, 'сатр эмас → рад');
  });

  await check('G1 босқич OFF (ҳужжат йўқ) → ўз дўкони quote/place ҳам MODULE_OFF', async () => {
    const cfg = db.collection('server_config').doc('business_orders');
    await cfg.delete();
    await expectCode(shopPlace([{ itemId: 's1', qty: 1 }]), 'MODULE_OFF', 'failed-precondition');
    await expectCode(shopQuote([{ itemId: 'sMeat', qty: 1 }]), 'MODULE_OFF');
    assert.deepStrictEqual(await call('getBusinessOrdersAccess', { itemId: 's1' }, BUYER), { allowed: false, stage: 'off', reason: 'MODULE_OFF' });
    await cfg.set({ stage: 'public' });
  });

  await check('G2 pilot: ўз дўкони — маҳсулот тумани (itemId) бўйича рухсат', async () => {
    const cfg = db.collection('server_config').doc('business_orders');
    await cfg.set({ stage: 'pilot', pilotDistrictIds: ['urganch'] });
    await expectCode(shopQuote([{ itemId: 's1', qty: 1 }]), 'MODULE_NOT_IN_PILOT');
    assert.strictEqual((await call('getBusinessOrdersAccess', { itemId: 's1' }, BUYER)).allowed, false);
    await cfg.set({ stage: 'pilot', pilotDistrictIds: ['gurlan'] });
    assert.strictEqual((await call('getBusinessOrdersAccess', { itemId: 's1' }, BUYER)).allowed, true);
    assert.strictEqual((await shopQuote([{ itemId: 's1', qty: 1 }])).ok, true);
    await cfg.set({ stage: 'public' });
  });

  let shopOrderId = '';
  await check('S1 Аралаш ўз дўкони (market йўқ): place → sellerKind shop, sellerUid = ownerPhone, нарх серверда', async () => {
    const r = await shopPlace([{ itemId: 's1', qty: 2, price: 1, unitPrice: 1 }], { itemsTotal: 5, total: 5, sellerUid: STRANGER });
    shopOrderId = r.orderId;
    const o = await order(r.orderId);
    assert.strictEqual(o.type, 'business');
    assert.strictEqual(o.sellerKind, 'shop');
    assert.strictEqual(o.businessId, null);
    assert.strictEqual(o.sellerUid, SHOP);
    assert.strictEqual(o.itemsTotal, 20000, 'клиент нархи эътиборсиз');
    assert.strictEqual(o.items[0].unitPrice, 10000);
    assert.strictEqual(o.items[0].market, undefined);
    assert.strictEqual(o.taxonomyVersion, null);
    assert.strictEqual(o.businessLat, S_LOC.lat);
    assert.strictEqual(o.businessName, 'Sidabilla');
    assert.strictEqual(o.businessAddress, 'Gurlan bozor 5');
    assert.strictEqual(o.businessStatus, 'placed');
    assert.ok(Number.isInteger(o.deliveryFee) && o.deliveryFee > 0);
  });

  await check('S2 бозор orderable (meat/beef, auto/parts): OK + market/category snapshot + taxonomyVersion', async () => {
    const r = await shopPlace([{ itemId: 'sMeat', qty: 3 }, { itemId: 'sParts', qty: 1 }]);
    const o = await order(r.orderId);
    assert.strictEqual(o.taxonomyVersion, 3);
    assert.deepStrictEqual(o.items.map((x) => [x.itemId, x.market, x.category, x.lineTotal]), [
      ['sMeat', 'meat', 'beef', 240000], ['sParts', 'auto', 'parts', 150000],
    ]);
    assert.strictEqual(o.itemsTotal, 390000);
  });

  await check('S3 livestock / auto cars / номаълум бўлим / бўлимсиз → ITEM_NOT_ORDERABLE', async () => {
    await expectCode(shopQuote([{ itemId: 'sLive', qty: 1 }]), 'ITEM_NOT_ORDERABLE', 'failed-precondition');
    await expectCode(shopPlace([{ itemId: 'sCar', qty: 1 }]), 'ITEM_NOT_ORDERABLE');
    await expectCode(shopQuote([{ itemId: 'sCatUnknown', qty: 1 }]), 'ITEM_NOT_ORDERABLE');
    await expectCode(shopQuote([{ itemId: 'sNoCat', qty: 1 }]), 'ITEM_NOT_ORDERABLE');
    await expectCode(shopQuote([{ itemId: 's1', qty: 1 }, { itemId: 'sCar', qty: 1 }]), 'ITEM_NOT_ORDERABLE'); // битта рад қатор → бутун буюртма
  });

  await check('S4 pending / blocked / status\'сиз бозор эълони → ITEM_UNAVAILABLE', async () => {
    await expectCode(shopQuote([{ itemId: 'sPending', qty: 1 }]), 'ITEM_UNAVAILABLE');
    await expectCode(shopQuote([{ itemId: 'sBlocked', qty: 1 }]), 'ITEM_UNAVAILABLE');
    await expectCode(shopQuote([{ itemId: 'sNoStatusMarket', qty: 1 }]), 'ITEM_UNAVAILABLE');
  });

  await check('S5 таксономия ҳужжати йўқ → бозор эълони ITEM_NOT_ORDERABLE, бозорсиз маҳсулот ишлайди', async () => {
    await db.collection('taxonomy').doc('markets').delete();
    try {
      await expectCode(shopQuote([{ itemId: 'sMeat', qty: 1 }]), 'ITEM_NOT_ORDERABLE');
      assert.strictEqual((await shopQuote([{ itemId: 's1', qty: 1 }])).ok, true);
    } finally {
      await db.collection('taxonomy').doc('markets').set(TAXONOMY);
    }
  });

  await check('S6 аралаш сотувчи / объектга боғланган маҳсулот → ITEM_NOT_IN_SHOP; ўз маҳсулоти → OWN_BUSINESS', async () => {
    await expectCode(shopQuote([{ itemId: 's1', qty: 1 }, { itemId: 'sOther', qty: 1 }]), 'ITEM_NOT_IN_SHOP');
    await expectCode(shopQuote([{ itemId: 'sLinked', qty: 1 }]), 'ITEM_NOT_IN_SHOP');
    await expectCode(shopQuote([{ itemId: 'sBuyerOwn', qty: 1 }]), 'OWN_BUSINESS');
    await expectCode(shopQuote([{ itemId: 'nope', qty: 1 }]), 'ITEM_NOT_FOUND');
  });

  await check('S7 дўкон блокланган → SHOP_BLOCKED; олиб кетиш нуқтаси йўқ → SELLER_PICKUP_LOCATION_MISSING', async () => {
    await db.collection('tv_shops').doc(SHOP).update({ status: 'blocked' });
    await expectCode(shopQuote([{ itemId: 's1', qty: 1 }]), 'SHOP_BLOCKED');
    await db.collection('tv_shops').doc(SHOP).update({ status: 'active', pickupLat: admin.firestore.FieldValue.delete() });
    await expectCode(shopQuote([{ itemId: 's1', qty: 1 }]), 'SELLER_PICKUP_LOCATION_MISSING');
    await db.collection('tv_shops').doc(SHOP).update({ pickupLat: '41.84' });
    await expectCode(shopQuote([{ itemId: 's1', qty: 1 }]), 'SELLER_PICKUP_LOCATION_MISSING'); // сатр координата рад
    await db.collection('tv_shops').doc(SHOP).update({ pickupLat: S_LOC.lat });
  });

  await check('S8 private/pickup (эга 2026-11-16): асосий манба; нотўғри private → эски оммавий fallback; оммавийсиз ҳам ишлайди', async () => {
    const priv = db.collection('tv_shops').doc(SHOP).collection('private').doc('pickup');
    const P = { lat: 41.8450, lng: 60.3950, address: 'Maxfiy nuqta 9' };
    try {
      await priv.set(P);
      const r = await shopPlace([{ itemId: 's1', qty: 1 }]);
      const o = await order(r.orderId);
      assert.strictEqual(o.businessLat, P.lat);
      assert.strictEqual(o.businessLng, P.lng);
      assert.strictEqual(o.businessAddress, 'Maxfiy nuqta 9');
      await priv.set({ lat: '41.8', lng: 60.39, address: 'x' });
      const o2 = await order((await shopPlace([{ itemId: 's1', qty: 1 }])).orderId);
      assert.strictEqual(o2.businessLat, S_LOC.lat, 'нотўғри private → legacy');
      assert.strictEqual(o2.businessAddress, 'Gurlan bozor 5');
      await priv.set(P);
      const del = admin.firestore.FieldValue.delete();
      await db.collection('tv_shops').doc(SHOP).update({ pickupLat: del, pickupLng: del, pickupAddress: del });
      assert.strictEqual((await shopQuote([{ itemId: 's1', qty: 1 }])).ok, true, 'фақат private');
      await priv.delete();
      await expectCode(shopQuote([{ itemId: 's1', qty: 1 }]), 'SELLER_PICKUP_LOCATION_MISSING');
    } finally {
      await priv.delete();
      await db.collection('tv_shops').doc(SHOP).update({ pickupLat: S_LOC.lat, pickupLng: S_LOC.lng, pickupAddress: 'Gurlan bozor 5' });
    }
  });

  await check('A1 сотувчи рухсати: бегона/объект эгаси рад (NOT_ORDER_SELLER), ownerPhone қабул + тайёр', async () => {
    await expectCode(call('businessAcceptOrder', { orderId: shopOrderId }, STRANGER), 'NOT_ORDER_SELLER', 'permission-denied');
    await expectCode(call('businessAcceptOrder', { orderId: shopOrderId }, BIZ_SELLER), 'NOT_ORDER_SELLER');
    await expectCode(call('businessRejectOrder', { orderId: shopOrderId }, STRANGER), 'NOT_ORDER_SELLER');
    const a = await call('businessAcceptOrder', { orderId: shopOrderId }, SHOP);
    assert.strictEqual(a.ok, true);
    assert.strictEqual((await call('businessAcceptOrder', { orderId: shopOrderId }, SHOP)).idempotent, true);
    await expectCode(call('businessMarkReady', { orderId: shopOrderId }, STRANGER), 'NOT_ORDER_SELLER');
    await call('businessMarkReady', { orderId: shopOrderId }, SHOP);
    assert.strictEqual((await order(shopOrderId)).businessStatus, 'ready');
  });

  await check('A2 курьер оқими (мавжуд): nearby → claim → pickup code → arrive → complete = delivered; custody seller→courier', async () => {
    const list = await call('listNearbyBusinessOrders', { ...S_LOC }, COURIER_A);
    const row = list.orders.find((x) => x.id === shopOrderId);
    assert.ok(row, 'яқин рўйхатда');
    assert.strictEqual(row.businessId, '');
    assert.strictEqual(row.businessName, 'Sidabilla');
    await call('courierClaimBusinessOrder', { orderId: shopOrderId }, COURIER_A);
    const code = (await secret(shopOrderId)).pickupCode;
    await call('courierPickupBusinessOrder', { orderId: shopOrderId, pickupCode: code }, COURIER_A);
    await call('courierArriveBusinessOrder', { orderId: shopOrderId }, COURIER_A);
    await call('courierCompleteBusinessOrder', { orderId: shopOrderId }, COURIER_A);
    assert.strictEqual((await order(shopOrderId)).businessStatus, 'delivered');
    const cust = await db.collection('custody_events').where('orderId', '==', shopOrderId).get();
    assert.ok(cust.size >= 1);
    const pick = cust.docs.map((d) => d.data()).find((x) => x.from && x.from.kind === 'seller');
    assert.ok(pick, 'seller → courier');
    assert.strictEqual(pick.from.id, SHOP);
    assert.strictEqual(pick.businessId, '');
  });

  await check('A3 дўкон буюртмадан кейин блокланди → accept SHOP_BLOCKED, reject мумкин', async () => {
    const r = await shopPlace([{ itemId: 's1', qty: 1 }]);
    await db.collection('tv_shops').doc(SHOP).update({ status: 'blocked' });
    try {
      await expectCode(call('businessAcceptOrder', { orderId: r.orderId }, SHOP), 'SHOP_BLOCKED');
      assert.strictEqual((await call('businessRejectOrder', { orderId: r.orderId, reason: 'yopiq' }, SHOP)).ok, true);
      assert.strictEqual((await order(r.orderId)).businessStatus, 'rejected');
    } finally {
      await db.collection('tv_shops').doc(SHOP).update({ status: 'active' });
    }
  });

  await check('R1 объект режими (регрессия): бозорсиз ва orderable бозор OK (sellerKind business), livestock → ITEM_NOT_ORDERABLE', async () => {
    const r = await call('placeBusinessOrder', {
      idempotencyKey: key(), businessId: 'biz1', items: [{ itemId: 'bPlain', qty: 1 }, { itemId: 'bMeat', qty: 2 }],
      address: 'x', ...C_LOC, deliveryPaymentMethod: 'cash',
    }, BUYER);
    const o = await order(r.orderId);
    assert.strictEqual(o.sellerKind, 'business');
    assert.strictEqual(o.businessId, 'biz1');
    assert.strictEqual(o.sellerUid, BIZ_SELLER);
    assert.strictEqual(o.taxonomyVersion, 3);
    assert.deepStrictEqual(o.items.map((x) => x.market || null), [null, 'meat']);
    await expectCode(call('quoteBusinessOrder', { businessId: 'biz1', items: [{ itemId: 'bLive', qty: 1 }], ...C_LOC }, BUYER), 'ITEM_NOT_ORDERABLE');
    await expectCode(call('quoteBusinessOrder', { businessId: 'biz1', items: [{ itemId: 's1', qty: 1 }], ...C_LOC }, BUYER), 'ITEM_NOT_IN_BUSINESS');
    assert.strictEqual((await call('businessAcceptOrder', { orderId: r.orderId }, BIZ_SELLER)).ok, true);
  });

  await check('D1 «етказилмади» рўйхати: объектсиз сотувчи — очиқ буюртмаси йўқ → DF_NOT_ALLOWED, бор → рухсат', async () => {
    await expectCode(call('listDeliveryFailedPending', {}, SHOP2), 'DF_NOT_ALLOWED');
    await db.collection('orders').doc('dfShop1').set({ type: 'business', sellerKind: 'shop', sellerUid: SHOP2, businessStatus: 'arrived', [dfLib.OPEN]: true });
    const r = await call('listDeliveryFailedPending', {}, SHOP2);
    assert.ok(r && typeof r === 'object');
    await expectCode(call('listDeliveryFailedPending', {}, STRANGER), 'DF_NOT_ALLOWED');
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
