/**
 * Ulgurji S57 — yetkazish haqi NAQD kuryerga (S5) + avtomatik ko'p LEG zanjir (S7), demand codebase
 * (FakeFirestore, qat'iy tranzaksiya: yozuvdan keyin o'qish — xato).
 *
 *   node functions_demand/test/wholesale_cash.test.js
 *
 * Qulflanadi (ega CONFIRMED 2026-11-13/14; PROPOSED qismlar alohida belgilangan):
 *   - kvota: `deliveryPaymentMethods {wallet, cash}` + `cashUnavailableReason` (darvoza O'CHIQ — `cash_disabled`,
 *     o'z yetkazishi — `self_delivery`, ochiq qarz — `buyer_debt` [PROPOSED]); naqd muhri, hamyondan ushlanma 0
 *   - Ulgurji jo'natmasi relay zanjiridan: `sequential` → 1 LEG, `assemble_all` → transfer nuqtalari bo'yicha LEG'lar
 *   - naqd bitta LEG: jo'natma `cash_on_delivery`, buyurtma in_delivery + `cashDelivery`, idempotent, to'liq oqim
 *     (tasdiqsiz yetkazish yo'q, yig'uvchi EARNED 0)
 *   - naqd ko'p LEG: hamma LEG ochiladi, yig'uvchi — oxirgi LEG, oxirgi kuryer naqd oladi
 *   - naqd rad: to'ladi / to'lamadi → relay o'zgarmas qaydi, `cashRefusal`, `returnDebt {payer: buyer}` (faqat
 *     to'lamaganda), qaytish jo'natmasi AYNAN `refusal.returnFee` bilan; tarif o'zgarsa — `cash_return_fee_mismatch`
 *   - sabablar: courier_problem — rad [PROPOSED]; yo'q xaridor + «to'ladi» — rad; `cashPaid` majburiy
 *   - bekor: jo'natma ochilmasdan xaridor bekor qildi — ochilgan naqd jo'natma ham bekor; custody boshlangach — yo'q
 *   - zanjir muddati (naqd): jo'natma cancelled + chain expired, pul holati o'zgarmaydi (default buyurtmani bekor qiladi)
 *   - yo'qolgan naqd posilka (ega 2026-11-14): `adminMarkShipmentLost` → lost/loss_pending (naqd to'lanmagan bo'lsa);
 *     naqd qayd etilgan — `cash_already_recorded`; pul — default `relay_escrow.settleCashLoss`
 *   - reconcile: bog'langan, lekin ochilmagan naqd jo'natma ochiladi
 *   - xabarlar: yangi kalitlar × 3 til, o'tish xabarlari
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const api = require('../api/logistics');
const L = require('../core/logistics');
const tariffCore = require('../core/tariff');
const config = require('../core/config');
const WO = require('../core/wholesale_orders');
const W = require('../api/wholesale_orders');
const DF = require('../api/wholesale_failed');
const R = require('../api/wholesale_return');
const E = require('../api/wholesale_events');
const N = require('../notify/wholesale_notify');
const {
  K1, F1, ADMIN, NOW, ctx, makeDb, seed, deps, photoFor,
} = require('./helpers/logistics_harness');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const BUYER = '998905556677';
const SELLER = '998901234567';
const ORDER_ID = 'wc1';
const G = 140000;
const H48 = 48 * 3600 * 1000;
const at = (ms) => new Date(NOW.getTime() + ms);

const ORIGIN = { regionId: 'xorazm', districtId: 'gurlan', lat: 41.84, lng: 60.39, addressText: 'Gurlan, Sotuvchi ombori' };
const DEST_NEAR = { regionId: 'xorazm', districtId: 'gurlan', lat: 41.85, lng: 60.40, addressText: 'Gurlan, Xaridor' };
const DEST_FAR = { regionId: 'toshkent_shahri', districtId: 'chilonzor', lat: 41.28, lng: 69.2, addressText: 'Chilonzor 9' };

const CHAIN_CFG = {
  enabled: true,
  matchingEnabled: true,
  pushEnabled: false,
  logistics: {
    stage: 'public',
    chainMode: 'assemble_all',
    chainAssemblyHours: 48,
    transferPoints: { regions: { toshkent_shahri: { districtId: 'yunusobod', addressText: 'Yunusobod bekat' } } },
  },
};

function fresh({ chain = false, extra = {} } = {}) {
  config.clearCache();
  tariffCore.clearCache();
  return makeDb(seed({
    ...(chain ? { 'module_config/logistics_all': CHAIN_CFG } : {}),
    'geo_districts/yunusobod': { regionId: 'toshkent_shahri' },
    [`users/${BUYER}`]: { name: 'Bobur' },
    [`users/${SELLER}`]: { name: 'Sotuvchi' },
    ...extra,
  }));
}

/** Default `placeWholesaleOrder` yozadigan NAQD buyurtma (hamyon usuli: eskrouda FAQAT tovar summasi). */
async function placeCash(db, { dest = DEST_NEAR, extra = {}, id = ORDER_ID } = {}) {
  const rq = await api.quoteParcelForPoints(db, ORIGIN, dest, { actualWeightG: 5000, declaredValue: G }, { dimsOptional: true });
  const fee = rq.quote.customerPrice;
  await db.collection('wholesale_orders').doc(id).set({
    buyerId: BUYER,
    buyerWalletUid: BUYER,
    sellerId: SELLER,
    productId: 'rice',
    productTitle: 'Guruch',
    packId: 'p1',
    packLabel: '50 kg',
    qty: 1,
    unitPrice: G,
    goodsTotal: G,
    deliveryFee: fee,
    total: G + fee,
    currency: 'UZS',
    delivery: {
      tariffVersion: rq.quote.tariffVersion, zone: rq.quote.zone, actualWeightG: 5000,
      chargeableWeightG: rq.quote.chargeableWeightG, dims: null, priceSnapshot: rq.quote,
    },
    origin: rq.origin,
    destination: rq.destination,
    quoteId: 'q1',
    status: 'placed',
    historySeq: 1,
    paymentMethod: 'wallet',
    deliveryMethod: 'ava_courier',
    deliveryPaymentMethod: 'cash',
    payment: {
      status: 'held', amount: G, payer: 'buyer', covers: 'goods',
    },
    shipment: null,
    refundStatus: null,
    createdAt: NOW,
    updatedAt: NOW,
    statusUpdatedAt: NOW,
    ...extra,
  });
  return { fee, id };
}
const orderOf = (db, id = ORDER_ID) => db.docs.get(`wholesale_orders/${id}`);
const shipOf = (db, id) => db.dump('shipments')[id];
const legDoc = (db, id) => db.dump('demands')[id];
const secretOf = (db, s) => db.docs.get(`shipments/${s}/private/secrets`).qrSecret;
const hcode = (db, s) => L.handoverCodeFor(s, secretOf(db, s));
const dcode = (db, s) => L.deliveryCodeFor(s, secretOf(db, s));
const accept = (db, legId, p, now) => api.makeAcceptLeg(deps(db, now))({ legId }, ctx(p));

async function rejects(promise, code, reason) {
  try {
    await promise;
  } catch (e) {
    assert.strictEqual(e.code, code, `kutilgan «${code}», keldi «${e.code}»: ${e.message}`);
    if (reason) assert.strictEqual((e.details || {}).reason, reason, `reason: ${JSON.stringify(e.details)}`);
    return e;
  }
  throw new Error(`«${code}/${reason || ''}» xatosi kutilgan edi`);
}
const realError = console.error;
const realLog = console.log;
function quiet() { console.error = () => {}; console.log = () => {}; }
function loud() { console.error = realError; console.log = realLog; }
async function q(fn) { quiet(); try { return await fn(); } finally { loud(); } }

/** Naqd buyurtma: jo'natma + ochish (bitta LEG, K1 oladi, posilka K1 qo'lida). */
async function cashInHand(db) {
  const { fee } = await placeCash(db);
  const r = await q(() => W.ensureWholesaleShipment(deps(db), ORDER_ID));
  const s = r.shipmentId;
  const legId = shipOf(db, s).legIds[0];
  await q(() => accept(db, legId, K1));
  await q(() => api.makeScanHandover(deps(db))({ legId, code: hcode(db, s), photoUrls: photoFor(K1) }, ctx(K1)));
  return { fee, shipmentId: s, legId };
}

// ═══════════════════════════════════════════════════════════════════════
// KVOTA
// ═══════════════════════════════════════════════════════════════════════
const QTARIFF = {
  module: 'logistics',
  version: 3,
  status: 'active',
  currency: 'UZS',
  volumetricDivisor: 6000,
  zones: tariffCore.ZONES,
  matrix: { regions: { xorazm: { xorazm: 'ZONE_1', toshkent_shahri: 'ZONE_4' } } },
  weightBrackets: [1000, 5000, 20000],
  prices: {
    ZONE_1: { brackets: [10000, 15000, 25000], extraPerKg: null },
    ZONE_4: { brackets: [30000, 40000, 60000], extraPerKg: 2000 },
  },
  declaredValue: { feeBps: 0, maxValue: 50000000 },
  limits: {},
  internal: { platformMarginBps: 2000, legShareBps: { first_mile: 3000, line_haul: 4000, last_mile: 3000 } },
};
function quoteDb({ gate = {}, extra = {} } = {}) {
  tariffCore.clearCache();
  config.clearCache();
  return new FakeFirestore({
    'geo_regions/xorazm': { name: 'Xorazm' },
    'geo_regions/toshkent_shahri': { name: 'Toshkent' },
    'geo_districts/gurlan': { regionId: 'xorazm' },
    'geo_districts/chilonzor': { regionId: 'toshkent_shahri' },
    'module_tariffs/logistics': { activeVersion: 3 },
    'module_tariffs/logistics_v3': QTARIFF,
    'module_config/wholesale_orders_all': { enabled: true, stage: 'public', ...gate },
    'settings/wholesale_orders': { avaFeeBps: 200, feeVersion: 4 },
    [`wholesale_sellers/${SELLER}`]: {
      phone: SELLER,
      approvalStatus: 'approved',
      regionId: 'xorazm',
      districtId: 'gurlan',
      address: 'Markaz 1',
      selfDelivery: { enabled: true, coverage: 'nation', dropoff: 'buyer_address' },
    },
    'wholesale_products/rice': {
      sellerId: SELLER,
      title: 'Guruch',
      status: 'active',
      market: 'wholesale',
      packs: [{ id: 'p1', label: '1 kg', priceTiers: [{ minQty: 1, price: 15000 }, { minQty: 10, price: 14000 }], unitWeightG: 1000 }],
    },
    'wholesale_stock/rice': { packs: { p1: 100 }, version: 1 },
    ...extra,
  });
}
const quote = (db) => W.makeQuoteWholesaleOrder({ db, now: () => NOW });
const qreq = (x = {}) => ({
  productId: 'rice', packId: 'p1', qty: 10, destination: { regionId: 'toshkent_shahri', districtId: 'chilonzor', addressText: 'Chilonzor 5' }, ...x,
});
const BC = ctx(BUYER);

ok('kvota: naqd darvozasi O\'CHIQ (standart) — cash false + cash_disabled; naqd so\'rovi rad, kvota YOZILMAYDI', async () => {
  const db = quoteDb();
  const r = await q(() => quote(db)(qreq(), BC));
  assert.deepStrictEqual(r.deliveryPaymentMethods, { wallet: true, cash: false });
  assert.strictEqual(r.cashUnavailableReason, 'cash_disabled');
  assert.strictEqual(r.deliveryPaymentMethod, 'wallet');
  assert.deepStrictEqual(r.payPlan, { walletNow: 200000, atDoorToSellerCard: 0, bankTransfer: 0 }, 'hamyon: tovar + yetkazish (o\'zgarmagan)');
  const n = Object.keys(db.dump('wholesale_quotes')).length;
  const e = await q(() => rejects(quote(db)(qreq({ deliveryPaymentMethod: 'cash' }), BC), 'failed-precondition', 'cash_delivery_unavailable'));
  assert.strictEqual(e.details.cashUnavailableReason, 'cash_disabled');
  assert.strictEqual(Object.keys(db.dump('wholesale_quotes')).length, n);
});

ok('kvota: naqd ochiq — hamyon: muhr deliveryPaymentMethod cash, walletNow = FAQAT tovar, cashToCourier = haq; bank: walletHold 0', async () => {
  const db = quoteDb({ gate: { cashDeliveryEnabled: true } });
  const r = await q(() => quote(db)(qreq({ deliveryPaymentMethod: 'cash' }), BC));
  assert.deepStrictEqual(r.deliveryPaymentMethods, { wallet: true, cash: true });
  assert.strictEqual(r.cashUnavailableReason, null);
  assert.deepStrictEqual([r.deliveryPaymentMethod, r.cashToCourier, r.deliveryFee, r.total], ['cash', 60000, 60000, 200000]);
  assert.deepStrictEqual(r.payPlan, {
    walletNow: 140000, atDoorToSellerCard: 0, bankTransfer: 0, cashToCourier: 60000,
  });
  const qd = db.dump('wholesale_quotes')[r.quoteId];
  assert.deepStrictEqual([qd.deliveryPaymentMethod, qd.deliveryFee, qd.total, qd.bankHold], ['cash', 60000, 200000, undefined]);
  // Bank + naqd: hamyondan HECH NARSA (bankHold 0), tovar puli bank orqali.
  const b = await q(() => quote(db)(qreq({ paymentMethod: 'bank_transfer', deliveryPaymentMethod: 'cash' }), BC));
  assert.deepStrictEqual([b.walletHold, b.payPlan.walletNow, b.payPlan.bankTransfer, b.payPlan.cashToCourier], [0, 0, 140000, 60000]);
  const bd = db.dump('wholesale_quotes')[b.quoteId];
  assert.deepStrictEqual([bd.deliveryPaymentMethod, bd.bankHold], ['cash', 0]);
  // Hamyon usuli (default) — muhrda deliveryPaymentMethod YO'Q (bugungi shakl, orqaga moslik).
  const w = await q(() => quote(db)(qreq(), BC));
  assert.strictEqual(db.dump('wholesale_quotes')[w.quoteId].deliveryPaymentMethod, undefined);
});

ok('kvota: o\'z yetkazishi — cash false + self_delivery; maydon berilsa not_applicable', async () => {
  const db = quoteDb({ gate: { cashDeliveryEnabled: true } });
  const r = await q(() => quote(db)(qreq({ deliveryMethod: 'self' }), BC));
  assert.deepStrictEqual(r.deliveryPaymentMethods, { wallet: false, cash: false });
  assert.strictEqual(r.cashUnavailableReason, 'self_delivery');
  assert.strictEqual(r.deliveryPaymentMethod, undefined);
  await q(() => rejects(quote(db)(qreq({ deliveryMethod: 'self', deliveryPaymentMethod: 'cash' }), BC), 'invalid-argument', 'delivery_payment_method_not_applicable'));
});

ok('kvota [PROPOSED]: ochiq Ulgurji qarzi (returnDebt.payer = buyer) — naqd YOPIQ (buyer_debt); boshqa xaridor qarzi ta\'sir qilmaydi', async () => {
  const db = quoteDb({
    gate: { cashDeliveryEnabled: true },
    extra: {
      'wholesale_orders/old1': { buyerId: BUYER, status: 'refused', returnDebt: { payer: 'buyer', kind: 'cash_refusal', amount: 90000, status: 'open' } },
      'wholesale_orders/other': { buyerId: '998907770007', status: 'refused', returnDebt: { payer: 'buyer', amount: 1 } },
      'wholesale_orders/courierDebt': { buyerId: BUYER, status: 'refused', returnDebt: { payer: 'courier', amount: 5 } },
    },
  });
  const r = await q(() => quote(db)(qreq(), BC));
  assert.deepStrictEqual([r.deliveryPaymentMethods.cash, r.cashUnavailableReason], [false, 'buyer_debt']);
  const e = await q(() => rejects(quote(db)(qreq({ deliveryPaymentMethod: 'cash' }), BC), 'failed-precondition', 'cash_delivery_unavailable'));
  assert.strictEqual(e.details.cashUnavailableReason, 'buyer_debt');
  // Kuryer qarzi (payer courier) xaridorni to'smaydi; qarz yopilsa (returnDebt null) — naqd ochiladi.
  await db.collection('wholesale_orders').doc('old1').update({ returnDebt: null });
  const r2 = await q(() => quote(db)(qreq(), BC));
  assert.deepStrictEqual([r2.deliveryPaymentMethods.cash, r2.cashUnavailableReason], [true, null]);
});

ok('cashAvailability (sof): self > disabled > debt tartibi', () => {
  assert.deepStrictEqual(W.cashAvailability({ self: true, enabled: true, hasDebt: true }), { available: false, reason: 'self_delivery' });
  assert.deepStrictEqual(W.cashAvailability({ self: false, enabled: false, hasDebt: true }), { available: false, reason: 'cash_disabled' });
  assert.deepStrictEqual(W.cashAvailability({ self: false, enabled: true, hasDebt: true }), { available: false, reason: 'buyer_debt' });
  assert.deepStrictEqual(W.cashAvailability({ self: false, enabled: true, hasDebt: false }), { available: true, reason: null });
  assert.strictEqual(WO.isCashDelivery({ deliveryPaymentMethod: 'cash' }), true);
  assert.strictEqual(WO.isCashDelivery({ deliveryPaymentMethod: 'cash', deliveryMethod: 'self' }), false);
  assert.strictEqual(WO.isCashDelivery({}), false, 'eski buyurtma — hamyon');
});

// ═══════════════════════════════════════════════════════════════════════
// ZANJIR (S7)
// ═══════════════════════════════════════════════════════════════════════
ok('zanjir: `sequential` (standart) — Ulgurji jo\'natmasi bugungidek 1 LEG; `assemble_all` — transfer nuqtalari bo\'yicha 3 LEG', async () => {
  const db1 = fresh();
  await placeCash(db1, { extra: { deliveryPaymentMethod: undefined, payment: { status: 'held', amount: 0 } } });
  const r1 = await q(() => W.ensureWholesaleShipment(deps(db1), ORDER_ID));
  const s1 = shipOf(db1, r1.shipmentId);
  assert.strictEqual(s1.legIds.length, 1);
  assert.strictEqual(s1.chain, undefined);
  assert.strictEqual(s1.deliveryPayment, undefined, 'hamyon usuli — eskrou (deliveryPayment yo\'q)');
  assert.strictEqual(orderOf(db1).status, 'placed', 'hamyon usuli: in_delivery — default SHIP_FUND');

  const db2 = fresh({ chain: true });
  await placeCash(db2, { dest: DEST_FAR, extra: { deliveryPaymentMethod: undefined, payment: { status: 'held', amount: 0 } } });
  const r2 = await q(() => W.ensureWholesaleShipment(deps(db2), ORDER_ID));
  const s2 = shipOf(db2, r2.shipmentId);
  assert.strictEqual(s2.legIds.length, 3, 'Gurlan → (viloyat markazi) → Toshkent transfer → Chilonzor');
  assert.strictEqual(s2.chain.mode, 'assemble_all');
  assert.strictEqual(s2.chain.state, 'assembling');
  assert.strictEqual(s2.priceSnapshot.customerPrice, orderOf(db2).deliveryFee, 'narx muhrdan — qayta hisoblanmaydi');
  for (const id of s2.legIds) assert.strictEqual(legDoc(db2, id).status, 'draft', 'eskrou tushmaguncha LEG ochilmaydi');
  const idem = db2.dump('demand_idempotency')[`wholesale_ship_${ORDER_ID}`];
  assert.deepStrictEqual([idem.legCount, idem.chainMode, idem.deliveryPaymentMethod], [3, 'assemble_all', 'escrow']);
});

// ═══════════════════════════════════════════════════════════════════════
// NAQD — BITTA LEG
// ═══════════════════════════════════════════════════════════════════════
ok('naqd 1 LEG: jo\'natma cash_on_delivery + LEG active; buyurtma in_delivery + cashDelivery + tarix; takror — bitta', async () => {
  const db = fresh();
  const { fee } = await placeCash(db);
  const r = await q(() => W.ensureWholesaleShipment(deps(db), ORDER_ID));
  assert.strictEqual(r.linked, true);
  assert.strictEqual(r.cashOpen.opened, true);
  const s = shipOf(db, r.shipmentId);
  assert.deepStrictEqual([s.status, s.paymentStatus], ['ready', 'cash_on_delivery']);
  assert.deepStrictEqual([s.deliveryPayment.method, s.deliveryPayment.amount, s.deliveryPayment.status], ['cash', fee, 'pending']);
  assert.strictEqual(s.deliveryPayment.collectorLegId, s.legIds[0]);
  assert.strictEqual(legDoc(db, s.legIds[0]).status, 'active');
  assert.strictEqual(legDoc(db, s.legIds[0]).attributes.cashToCollect, fee, 'kuryer taklifida naqd summa');
  const o = orderOf(db);
  assert.strictEqual(o.status, 'in_delivery');
  assert.deepStrictEqual([o.cashDelivery.status, o.cashDelivery.shipmentId, o.cashDelivery.amount], ['opened', r.shipmentId, fee]);
  const h = db.dump(`wholesale_orders/${ORDER_ID}/history`);
  const ev = Object.values(h).find((x) => x.event === 'cash_shipment_opened');
  assert.deepStrictEqual([ev.from, ev.to, ev.actor, ev.meta.amount], ['placed', 'in_delivery', 'system', fee]);
  assert.strictEqual(o.payment.amount, G, 'eskrouga yetkazish haqi TUSHMAGAN (default ushlamagan)');
  // Takror (trigger / reconcile): bitta jo'natma, ikkinchi ochish yo'q.
  const again = await q(() => W.ensureWholesaleShipment(deps(db), ORDER_ID));
  assert.strictEqual(again.skipped, 'already_linked');
  const o2 = await q(() => W.openWholesaleCashShipment(deps(db), ORDER_ID));
  assert.strictEqual(o2.skipped, 'already_opened');
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 1);
});

ok('naqd 1 LEG TO\'LIQ OQIM: olish → yetkazish tasdiqsiz rad (cash_confirmation_required) → tasdiq bilan delivered, collected, EARNED 0', async () => {
  const db = fresh();
  const { fee, shipmentId, legId } = await cashInHand(db);
  assert.strictEqual(shipOf(db, shipmentId).status, 'in_transit');
  const code = dcode(db, shipmentId);
  const e = await q(() => rejects(api.makeConfirmDelivery(deps(db))({ legId, deliveryCode: code, photoUrls: photoFor(K1) }, ctx(K1)),
    'failed-precondition', 'cash_confirmation_required'));
  assert.strictEqual(e.details.cashToCollect, fee);
  const c = await q(() => api.makeConfirmDelivery(deps(db))({
    legId, deliveryCode: code, photoUrls: photoFor(K1), cashCollected: true,
  }, ctx(K1)));
  assert.strictEqual(c.cashCollected, fee);
  const s = shipOf(db, shipmentId);
  assert.deepStrictEqual([s.status, s.deliveryPayment.status, s.deliveryPayment.collectedBy], ['delivered', 'collected', K1]);
  const ev = db.dump('custody_events')[c.eventId];
  assert.deepStrictEqual([ev.deliversShipment, ev.completedLegPayout, ev.cashCollected.amount], [true, 0, fee],
    'default RELEASE shu hodisaga qaraydi; yig\'uvchi haqi naqdda (EARNED yo\'q)');
});

// ═══════════════════════════════════════════════════════════════════════
// NAQD — KO'P LEG (assemble_all)
// ═══════════════════════════════════════════════════════════════════════
async function cashChainInHand(db) {
  const { fee } = await placeCash(db, { dest: DEST_FAR });
  const r = await q(() => W.ensureWholesaleShipment(deps(db), ORDER_ID));
  const s = r.shipmentId;
  const legIds = shipOf(db, s).legIds;
  await q(async () => {
    await accept(db, legIds[1], F1);
    await accept(db, legIds[2], F1);
    await accept(db, legIds[0], K1);
    const scan = api.makeScanHandover(deps(db));
    await scan({ legId: legIds[0], code: hcode(db, s), photoUrls: photoFor(K1) }, ctx(K1));
    await scan({ legId: legIds[1], code: hcode(db, s), photoUrls: photoFor(F1) }, ctx(F1));
    await scan({ legId: legIds[2], code: hcode(db, s), photoUrls: photoFor(F1) }, ctx(F1));
  });
  return { fee, shipmentId: s, legIds };
}

ok('naqd ko\'p LEG: 3 LEG hammasi ochiladi (muddat 48 soat), yig\'uvchi = oxirgi LEG; oxirgi kuryer naqd oladi → delivered', async () => {
  const db = fresh({ chain: true });
  const { fee } = await placeCash(db, { dest: DEST_FAR });
  const r = await q(() => W.ensureWholesaleShipment(deps(db), ORDER_ID));
  const s = shipOf(db, r.shipmentId);
  assert.strictEqual(s.legIds.length, 3);
  assert.strictEqual(s.paymentStatus, 'cash_on_delivery');
  assert.strictEqual(s.deliveryPayment.collectorLegId, s.legIds[2]);
  assert.ok(s.chain.deadlineAt, 'zanjir muddati naqd ochilishda boshlanadi');
  for (const id of s.legIds) assert.strictEqual(legDoc(db, id).status, 'active');
  assert.deepStrictEqual(s.legIds.map((id) => legDoc(db, id).attributes.cashToCollect), [0, 0, fee], 'naqdni faqat oxirgi kuryer oladi');
  assert.strictEqual(orderOf(db).status, 'in_delivery');

  const db2 = fresh({ chain: true });
  const c2 = await cashChainInHand(db2);
  const last = c2.legIds[2];
  const done = await q(() => api.makeConfirmDelivery(deps(db2))({
    legId: last, deliveryCode: dcode(db2, c2.shipmentId), photoUrls: photoFor(F1), cashCollected: true,
  }, ctx(F1)));
  assert.strictEqual(done.cashCollected, c2.fee);
  const s2 = shipOf(db2, c2.shipmentId);
  assert.deepStrictEqual([s2.status, s2.deliveryPayment.status, s2.deliveryPayment.collectedBy], ['delivered', 'collected', F1]);
});

// ═══════════════════════════════════════════════════════════════════════
// NAQD RAD
// ═══════════════════════════════════════════════════════════════════════
const report = (db, data, who = K1) => DF.makeReportWholesaleDeliveryFailed({ db, now: () => NOW })({ orderId: ORDER_ID, ...data }, ctx(who));
const respond = (db, decision) => DF.makeRespondWholesaleDeliveryFailed({ db, now: () => NOW })({ orderId: ORDER_ID, decision }, BC);

ok('naqd rad — kirish: cashPaid majburiy (summa serverdan), courier_problem rad [PROPOSED], yo\'q xaridor + «to\'ladi» rad', async () => {
  const db = fresh();
  const { fee } = await cashInHand(db);
  const e = await q(() => rejects(report(db, { reasonCode: 'customer_refused' }), 'invalid-argument', 'cash_paid_required'));
  assert.strictEqual(e.details.cashDue.deliveryFee, fee);
  assert.strictEqual(e.details.cashDue.total, fee + e.details.cashDue.returnFee);
  await q(() => rejects(report(db, { reasonCode: 'courier_problem', cashPaid: false }), 'invalid-argument', 'reason_not_allowed_cash'));
  await q(() => rejects(report(db, { reasonCode: 'customer_absent', cashPaid: true }), 'invalid-argument', 'cash_paid_absent'));
  await q(() => rejects(report(db, { cashPaid: false }), 'invalid-argument', 'reason_required'));
  assert.strictEqual(orderOf(db).deliveryFailed, undefined, 'hech narsa yozilmadi');
  const st = await q(() => DF.makeGetWholesaleDeliveryFailedState({ db })({ orderId: ORDER_ID }, ctx(K1)));
  assert.deepStrictEqual(st.allowedReasons, ['customer_absent', 'customer_refused']);
  assert.deepStrictEqual([st.deliveryPaymentMethod, st.cashToCollect, st.cashDue.deliveryFee], ['cash', fee, fee]);
});

ok('naqd rad — TO\'LADI: relay qaydi refusal_collected, buyurtma refused + cashRefusal (qarz YO\'Q), qaytish jo\'natmasi AYNAN returnFee', async () => {
  const db = fresh();
  const { fee, shipmentId } = await cashInHand(db);
  const r = await q(() => report(db, { reasonCode: 'customer_refused', cashPaid: true }));
  assert.strictEqual(r.awaitingBuyer, true);
  const due = r.cashDue;
  assert.strictEqual(due.total, fee + due.returnFee);
  assert.strictEqual(shipOf(db, shipmentId).deliveryPayment.status, 'pending', 'xaridor tasdig\'igacha pul qaydi YO\'Q');
  const news = Object.values(db.dump('admin_news')).find((n) => n.targetUid === BUYER || n.uid === BUYER || String(n.body || '').includes(String(due.total)));
  assert.ok(news, 'xaridorga summa bilan xabar');
  await q(() => respond(db, 'confirm'));
  const s = shipOf(db, shipmentId);
  assert.strictEqual(s.deliveryPayment.status, 'refusal_collected');
  assert.deepStrictEqual([s.deliveryPayment.refusal.paid, s.deliveryPayment.refusal.total], [true, due.total]);
  const o = orderOf(db);
  assert.strictEqual(o.status, 'refused');
  assert.strictEqual(o.refundStatus, 'pending');
  assert.deepStrictEqual([o.cashRefusal.paid, o.cashRefusal.deliveryFee, o.cashRefusal.returnFee, o.cashRefusal.total],
    [true, fee, due.returnFee, due.total]);
  assert.strictEqual(o.returnDebt, undefined, 'to\'lagan — qarz yo\'q');
  assert.strictEqual(o.refusal.cashPaid, true);
  assert.ok(db.dump('logistics_audit')[`cash_refusal_${shipmentId}`], 'o\'zgarmas hodisa');
  // Qaytish jo'natmasi — eshik oldidagi muhr bilan, posilka qo'lidagi kuryerga biriktirilgan.
  const rr = await q(() => R.ensureWholesaleReturnShipment(deps(db), ORDER_ID));
  assert.strictEqual(rr.linked, true);
  assert.strictEqual(rr.fee, due.returnFee);
  const rs = shipOf(db, rr.shipmentId);
  assert.deepStrictEqual([rs.source, rs.outboundShipmentId, rs.priceSnapshot.customerPrice, rs.paymentStatus], ['wholesale_return', shipmentId, due.returnFee, 'pending']);
  assert.strictEqual(rr.courierId, K1);
  // Takror tasdiq — idempotent (relay qaydi o'zgarmaydi).
  const again = await q(() => respond(db, 'confirm'));
  assert.strictEqual(again.idempotent, true);
});

ok('naqd rad — TO\'LAMADI: refusal_unpaid, buyurtmada returnDebt {payer: buyer, kind: cash_refusal, amount = yetkazish + qaytish}', async () => {
  const db = fresh();
  const { fee, shipmentId } = await cashInHand(db);
  const r = await q(() => report(db, { reasonCode: 'customer_absent', cashPaid: false }));
  await q(() => respond(db, 'confirm'));
  const s = shipOf(db, shipmentId);
  assert.strictEqual(s.deliveryPayment.status, 'refusal_unpaid');
  const o = orderOf(db);
  assert.strictEqual(o.status, 'refused');
  assert.deepStrictEqual([o.returnDebt.payer, o.returnDebt.kind, o.returnDebt.amount, o.returnDebt.deliveryFee, o.returnDebt.returnFee, o.returnDebt.status],
    ['buyer', 'cash_refusal', r.cashDue.total, fee, r.cashDue.returnFee, 'open']);
  assert.strictEqual(o.cashRefusal.paid, false);
  // Xabarlar: xaridorga qarz + adminlarga.
  const items = E.transitionNotifications({ ...o, status: 'in_delivery', returnDebt: null }, o).map((x) => x.key);
  assert.ok(items.includes('ws_cash_debt_buyer') && items.includes('ws_cash_debt_admin'), JSON.stringify(items));
  // Qarz bor — keyingi kvotada naqd yopiq (shu buyurtma qarzi o'qiladi).
  assert.strictEqual(await W.buyerHasOpenDebt(db, BUYER), true);
});

ok('naqd rad: «Олмоқчиман» (davom) — relay qaydi YOZILMAYDI, buyurtma in_delivery, keyin naqd yetkazish ishlaydi', async () => {
  const db = fresh();
  const { shipmentId, legId } = await cashInHand(db);
  await q(() => report(db, { reasonCode: 'customer_refused', cashPaid: true }));
  await q(() => respond(db, 'reject'));
  assert.strictEqual(shipOf(db, shipmentId).deliveryPayment.status, 'pending');
  assert.strictEqual(shipOf(db, shipmentId).deliveryPayment.refusal, undefined);
  assert.strictEqual(orderOf(db).status, 'in_delivery');
  const c = await q(() => api.makeConfirmDelivery(deps(db))({
    legId, deliveryCode: dcode(db, shipmentId), photoUrls: photoFor(K1), cashCollected: true,
  }, ctx(K1)));
  assert.strictEqual(c.shipmentStatus, 'delivered');
});

ok('naqd rad: tarif orada o\'zgardi — qaytish jo\'natmasi OCHILMAYDI (cash_return_fee_mismatch), xato belgisi', async () => {
  const db = fresh();
  await cashInHand(db);
  await q(() => report(db, { reasonCode: 'customer_refused', cashPaid: true }));
  await q(() => respond(db, 'confirm'));
  const t = db.docs.get('module_tariffs/logistics_v7');
  const bumped = JSON.parse(JSON.stringify(t));
  bumped.version = 8;
  for (const z of Object.keys(bumped.prices || {})) {
    const p = bumped.prices[z];
    if (Array.isArray(p.brackets)) p.brackets = p.brackets.map((x) => x + 1000);
  }
  await db.collection('module_tariffs').doc('logistics_v8').set(bumped);
  await db.collection('module_tariffs').doc('logistics').set({ activeVersion: 8 });
  tariffCore.clearCache();
  const rr = await q(() => R.ensureWholesaleReturnShipment(deps(db), ORDER_ID));
  assert.strictEqual(rr.failed, true);
  assert.strictEqual(rr.code, 'cash_return_fee_mismatch');
  assert.strictEqual(orderOf(db).returnShipment, undefined);
  assert.strictEqual(orderOf(db).returnShipmentError.code, 'cash_return_fee_mismatch');
});

// ═══════════════════════════════════════════════════════════════════════
// BEKOR / MUDDAT / YO'QOLISH / RECONCILE
// ═══════════════════════════════════════════════════════════════════════
ok('naqd bekor: jo\'natma bog\'langan, ochilmagan payt xaridor bekor qildi — ochish ham, jo\'natma ham bekor (pul yo\'q)', async () => {
  const db = fresh();
  const { fee } = await placeCash(db);
  // Jo'natma yaratilib bog'langan, ochish yiqilgan holat (createShipmentInternal + bog'lash, open chaqirilmagan).
  const o0 = orderOf(db);
  const created = await q(() => api.createShipmentInternal(deps(db), W.shipmentInputFromOrder(ORDER_ID, o0, 'Bobur')));
  await db.collection('wholesale_orders').doc(ORDER_ID).update({
    shipment: { shipmentId: created.shipmentId, orderId: created.orderId, trackingNumber: created.trackingNumber, createdAt: NOW },
  });
  assert.strictEqual(shipOf(db, created.shipmentId).deliveryPayment.amount, fee);
  await q(() => W.makeCancelWholesaleOrder({ db, now: () => NOW })({ orderId: ORDER_ID }, BC));
  assert.strictEqual(orderOf(db).status, 'cancelled');
  assert.strictEqual(shipOf(db, created.shipmentId).status, 'cancelled', 'to\'lanmagan naqd jo\'natma ham bekor');
  const r = await q(() => W.openWholesaleCashShipment(deps(db), ORDER_ID));
  assert.strictEqual(r.skipped, 'status_cancelled');
  assert.strictEqual(shipOf(db, created.shipmentId).paymentStatus, 'pending', 'ochilmadi');
});

ok('naqd bekor: ochilgan jo\'natma, custody YO\'Q — bekor qilinadi (LEG ham); kuryer olgach — bekor qilinmaydi', async () => {
  const db = fresh();
  await placeCash(db);
  const r = await q(() => W.ensureWholesaleShipment(deps(db), ORDER_ID));
  const ref = db.collection('wholesale_orders').doc(ORDER_ID);
  await db.runTransaction(async (tx) => {
    const o = (await tx.get(ref)).data();
    const write = await W.prepareCancelInTx(tx, db, ref, o, { actor: 'admin', actorId: ADMIN, reason: 'test' });
    write(NOW);
  });
  const s = shipOf(db, r.shipmentId);
  assert.deepStrictEqual([s.status, s.paymentStatus], ['cancelled', 'cash_on_delivery'], 'pul holati o\'zgarmaydi (pul yo\'q)');
  assert.strictEqual(legDoc(db, s.legIds[0]).status, 'cancelled');
  assert.strictEqual(orderOf(db).refundStatus, 'pending', 'default refundOrder tovar ushlanmasini qaytaradi');

  const db2 = fresh();
  const c = await cashInHand(db2);
  const ref2 = db2.collection('wholesale_orders').doc(ORDER_ID);
  await db2.runTransaction(async (tx) => {
    const o = (await tx.get(ref2)).data();
    const write = await W.prepareCancelInTx(tx, db2, ref2, o, { actor: 'admin', actorId: ADMIN, reason: 'test' });
    write(NOW);
  });
  assert.strictEqual(shipOf(db2, c.shipmentId).status, 'in_transit', 'custody boshlangan — jo\'natmaga tegilmaydi');
});

ok('naqd zanjir muddati: 48 soatda yig\'ilmadi — jo\'natma cancelled + chain expired, paymentStatus cash_on_delivery, audit deliveryPaymentMethod cash', async () => {
  const db = fresh({ chain: true });
  await placeCash(db, { dest: DEST_FAR });
  const r = await q(() => W.ensureWholesaleShipment(deps(db), ORDER_ID));
  await q(() => accept(db, shipOf(db, r.shipmentId).legIds[0], K1));
  const out = await q(() => api.expireChain(deps(db), r.shipmentId, at(H48 + 60000)));
  assert.strictEqual(out.expired, true);
  const s = shipOf(db, r.shipmentId);
  assert.deepStrictEqual([s.status, s.chain.state, s.paymentStatus], ['cancelled', 'expired', 'cash_on_delivery']);
  const a = db.dump('logistics_audit')[`chain_expired_${r.shipmentId}`];
  assert.deepStrictEqual([a.wholesaleOrderId, a.deliveryPaymentMethod, a.refundPending], [ORDER_ID, 'cash', false]);
  assert.strictEqual(orderOf(db).status, 'in_delivery', 'buyurtmani default `onChainExpired` bekor qiladi (functions/test/wholesale_cash_cf)');
  // Xabarlar (default bekor qilgach): xaridor va sotuvchi.
  const keys = E.transitionNotifications({ ...orderOf(db) }, { ...orderOf(db), status: 'cancelled', cancelReason: 'courier_chain_expired' }).map((x) => x.key);
  assert.deepStrictEqual(keys.filter((k) => k.startsWith('ws_chain')), ['ws_chain_expired_buyer', 'ws_chain_expired_seller']);
});

ok('yo\'qolgan NAQD posilka (ega 2026-11-14): adminMarkShipmentLost — lost + loss_pending, incident (G, mas\'ul K1, naqd, xaridor 0); takror idempotent', async () => {
  const db = fresh();
  const { shipmentId, legId, fee } = await cashInHand(db);
  const mark = api.makeAdminMarkShipmentLost({ db, now: () => NOW });
  const r = await q(() => mark({ shipmentId, reason: 'yo\'qoldi', opId: 'op-lost-0001' }, ctx(ADMIN)));
  assert.deepStrictEqual([r.ok, r.idempotent, r.status, r.paymentStatus, r.goodsValue], [true, false, 'lost', 'loss_pending', G]);
  const s = shipOf(db, shipmentId);
  assert.deepStrictEqual([s.status, s.paymentStatus, s.lostLegId], ['lost', 'loss_pending', legId]);
  assert.strictEqual(s.deliveryPayment.status, 'pending', 'naqd holati o\'zgarmaydi (relay_cash triggeri ishlamaydi)');
  assert.strictEqual(legDoc(db, legId).status, 'disputed');
  const inc = db.dump('logistics_incidents')[shipmentId];
  assert.deepStrictEqual(
    [inc.status, inc.goodsValue, inc.courier.uid, inc.courier.accountId, inc.customer.uid, inc.customerPrice, inc.deliveryPaymentMethod, inc.buyerCashPaid],
    ['declared', G, K1, `acc${K1}`, SELLER, fee, 'cash', 0],
  );
  const again = await q(() => mark({ shipmentId, reason: 'yo\'qoldi', opId: 'op-lost-0002' }, ctx(ADMIN)));
  assert.strictEqual(again.idempotent, true);
});

ok('yo\'qolgan NAQD posilka: naqd allaqachon qayd etilgan (collected / refusal_*) — RAD cash_already_recorded, hech narsa yozilmaydi', async () => {
  for (const st of ['collected', 'refusal_collected', 'refusal_unpaid', 'settled']) {
    const db = fresh();
    const { shipmentId } = await cashInHand(db);
    await db.collection('shipments').doc(shipmentId).update({ 'deliveryPayment.status': st });
    const e = await q(() => rejects(api.makeAdminMarkShipmentLost({ db, now: () => NOW })({
      shipmentId, reason: 'yo\'qoldi', opId: 'op-lost-0003',
    }, ctx(ADMIN)), 'failed-precondition', 'cash_already_recorded'));
    assert.strictEqual(e.details.cashStatus, st);
    const s = shipOf(db, shipmentId);
    assert.deepStrictEqual([s.status, s.paymentStatus], ['in_transit', 'cash_on_delivery'], st);
    assert.strictEqual(db.dump('logistics_incidents')[shipmentId], undefined, st);
  }
});

ok('yo\'qolgan NAQD posilka: cash_on_delivery, lekin deliveryPayment yo\'q (naqd emas) — RAD payment_not_lossable; admin emas — rad', async () => {
  const db = fresh();
  const { shipmentId } = await cashInHand(db);
  await db.collection('shipments').doc(shipmentId).update({ deliveryPayment: null });
  await q(() => rejects(api.makeAdminMarkShipmentLost({ db, now: () => NOW })({
    shipmentId, reason: 'yo\'qoldi', opId: 'op-lost-0004',
  }, ctx(ADMIN)), 'failed-precondition', 'payment_not_lossable'));
  const db2 = fresh();
  const c2 = await cashInHand(db2);
  await q(() => rejects(api.makeAdminMarkShipmentLost({ db: db2, now: () => NOW })({
    shipmentId: c2.shipmentId, reason: 'yo\'qoldi', opId: 'op-lost-0005',
  }, ctx(K1)), 'permission-denied'));
  assert.strictEqual(db2.dump('logistics_incidents')[c2.shipmentId], undefined);
});

ok('to\'lov holatlari mashinasi: cash_on_delivery → loss_pending ruxsat (faqat shu yangi o\'tish); refund_pending/escrow_funded — yo\'q', () => {
  assert.ok(L.canTransitionPayment('cash_on_delivery', 'loss_pending'));
  assert.ok(L.canTransitionPayment('cash_on_delivery', 'settled'));
  assert.ok(!L.canTransitionPayment('cash_on_delivery', 'refund_pending'));
  assert.ok(!L.canTransitionPayment('cash_on_delivery', 'escrow_funded'));
  assert.ok(!L.canTransitionPayment('cash_on_delivery', 'loss_settled'), 'to\'g\'ridan-to\'g\'ri loss_settled yo\'q');
  assert.ok(L.canTransitionPayment('loss_pending', 'loss_settled'));
});

ok('reconcile: bog\'langan, ochilmagan naqd jo\'natma (2 daqiqadan eski) ochiladi; yosh — kutadi', async () => {
  const db = fresh();
  await placeCash(db);
  const o0 = orderOf(db);
  const created = await q(() => api.createShipmentInternal(deps(db), W.shipmentInputFromOrder(ORDER_ID, o0, 'Bobur')));
  await db.collection('wholesale_orders').doc(ORDER_ID).update({
    shipment: { shipmentId: created.shipmentId, orderId: created.orderId, trackingNumber: created.trackingNumber, createdAt: NOW },
  });
  const young = await q(() => W.reconcileWholesaleShipments({ ...deps(db), now: () => at(30 * 1000) }));
  assert.strictEqual(young.cashOpenChecked, 0);
  const r = await q(() => W.reconcileWholesaleShipments({ ...deps(db), now: () => at(3 * 60 * 1000) }));
  assert.deepStrictEqual([r.cashOpenChecked, r.cashOpened], [1, 1]);
  assert.strictEqual(orderOf(db).status, 'in_delivery');
  assert.strictEqual(shipOf(db, created.shipmentId).paymentStatus, 'cash_on_delivery');
});

ok('xabarlar: yangi kalitlar × 3 til (bo\'sh emas, o\'rinbosarlar mos); naqd ochilishi va to\'langan rad o\'tishlari', () => {
  const keys = ['ws_df_buyer_confirm_cash_paid', 'ws_df_buyer_confirm_cash_unpaid', 'ws_cash_open_buyer', 'ws_cash_refusal_paid_buyer',
    'ws_cash_refused_goods_refund_buyer', 'ws_cash_debt_buyer', 'ws_cash_debt_admin', 'ws_chain_expired_buyer', 'ws_chain_expired_seller'];
  for (const k of keys) {
    for (const lang of N.LANGS) {
      const m = (N.MESSAGES[k] || {})[lang];
      assert.ok(m && m.title && m.body, `${k}.${lang}`);
      const ph = (s) => (s.match(/\{[a-zA-Z]+\}/g) || []).sort().join();
      assert.strictEqual(ph(m.body), ph(N.MESSAGES[k].uz_Cyrl.body), `${k}.${lang} o'rinbosarlari`);
    }
  }
  const base = {
    paymentMethod: 'wallet', deliveryPaymentMethod: 'cash', deliveryMethod: 'ava_courier', productTitle: 'Guruch', qty: 1,
  };
  const open = E.transitionNotifications({ ...base, status: 'placed' }, { ...base, status: 'in_delivery' }).map((x) => x.key);
  assert.ok(open.includes('ws_cash_open_buyer'));
  const wal = E.transitionNotifications({ paymentMethod: 'wallet', status: 'placed' }, { paymentMethod: 'wallet', status: 'in_delivery' }).map((x) => x.key);
  assert.ok(!wal.includes('ws_cash_open_buyer'), 'hamyon usulida yo\'q');
  const refused = E.transitionNotifications({ ...base, status: 'in_delivery' }, { ...base, status: 'refused', cashRefusal: { paid: true, total: 9 } }).map((x) => x.key);
  assert.ok(refused.includes('ws_cash_refusal_paid_buyer'));
  const refund = E.transitionNotifications(
    { ...base, status: 'refused', refundStatus: 'pending' },
    { ...base, status: 'refused', refundStatus: 'done', cashRefusalSettlement: { goodsRefunded: G } },
  ).map((x) => x.key);
  assert.ok(refund.includes('ws_cash_refused_goods_refund_buyer'));
  const p = N.render('ws_cash_open_buyer', 'uz_Latn', { product: 'Guruch', qty: 1, deliveryFee: 60000 });
  assert.ok(p.body.includes('60000') && !/\{/.test(p.body), p.body);
});

(async () => {
  for (const t of tests) {
    try {
      await t.fn();
      passed += 1;
      console.log(`  ok  ${t.name}`);
    } catch (e) {
      loud();
      console.log(`  XATO ${t.name}\n       ${e.stack || e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
