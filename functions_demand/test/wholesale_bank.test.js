/**
 * Ulgurji: BANK O'TKAZMASI (`bank_transfer`, ega qarorlari 2026-11-13/14) + AVA ulushi 10 kunlik
 * hisoboti — demand codebase (FakeFirestore, qat'iy tranzaksiya: yozuvdan keyin o'qish — xato).
 *
 *   node functions_demand/test/wholesale_bank.test.js
 *
 * Qulflanadi:
 *   - core: usul ro'yxati, methodOf, deliveryPaidByBuyer, 5 ish kuni muddati (chegara), shipmentAllowed
 *   - kvota: deliveryPaymentMethod (yo'q → wallet; boshqasi — aniq kod), mavjudlik (tasdiqlangan sotuvchi),
 *     muhr (bankHold = deliveryFee), yopiq bo'lsa kvota yozilmaydi
 *   - qabul → awaiting + bankPayDeadlineAt; jo'natma YO'Q; «Пул тушди» (faqat sotuvchi, idempotent,
 *     muddat chegarasi) → jo'natma ochiladi (onUpdate)
 *   - sweeper: muddat o'tdi → cancelled (bank_payment_timeout, refundStatus pending), takror — yo'q, poyga
 *   - xaridor bekor qilishi: tasdiqqacha — ha (sotuvchiga xabar), keyin — bank_payment_confirmed
 *   - reconcile: 150 ta kutilayotgan bank buyurtmasi hamyon buyurtmasini siqib chiqarmaydi
 *   - xabarlar: yangi kalitlar × 3 til; rad/yo'qolishda tovar puli qaytarish matni YO'Q (ega, 2026-11-14)
 *   - hisobot: davr chegaralari (01/11/21, oy oxiri, kabisa), faqat yetkazilgan bank buyurtmalari,
 *     anomaliya, qat'iy admin, «yig'ildi» (yopilgan davr, idempotent, server summasi), oylik hisobot
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const tariffCore = require('../core/tariff');
const config = require('../core/config');
const WO = require('../core/wholesale_orders');
const W = require('../api/wholesale_orders');
const B = require('../api/wholesale_bank');
const F = require('../api/wholesale_fee_statement');
const E = require('../api/wholesale_events');
const N = require('../notify/wholesale_notify');
const DF = require('../api/wholesale_failed');
const {
  NOW, ctx, makeDb, seed, deps,
} = require('./helpers/logistics_harness');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const BUYER = '998905556677';
const SELLER = '998901234567';
const SELLER2 = '998903330003';
const STRANGER = '998907770007';
const ADMIN = '998909990000';
const DISP = '998908880000';
const ORDER_ID = 'wb1';
const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
const T = (localIso) => Date.parse(`${localIso}+05:00`);
const localIso = (ms) => new Date(ms + 5 * HOUR).toISOString().slice(0, 16);

const ORIGIN = {
  regionId: 'xorazm', districtId: 'gurlan', lat: 41.84, lng: 60.39, geohash: 'tp5my0b', addressText: 'Gurlan, Markaz 1',
};
const DEST = {
  regionId: 'xorazm', districtId: 'gurlan', lat: 41.85, lng: 60.40, geohash: 'tp5my2c', addressText: 'Gurlan, Bog\'cha 5',
};

function seedW(extra = {}) {
  config.clearCache();
  tariffCore.clearCache();
  return seed({
    [`users/${BUYER}`]: { name: 'Bobur' },
    [`users/${SELLER}`]: { name: 'Sotuvchi' },
    ...extra,
  });
}

/** Default codebase `placeWholesaleOrder` (bank) yozadigan shakl: ushlanma = FAQAT yetkazish haqi. */
function orderDoc(db, extra = {}) {
  const t = db.docs.get('module_tariffs/logistics_v7');
  const snap = tariffCore.quoteParcel(t, { actualWeightG: 800, declaredValue: 140000 }, ORIGIN, DEST, { dimsOptional: true });
  const fee = snap.customerPrice;
  return {
    buyerId: BUYER,
    buyerWalletUid: BUYER,
    sellerId: SELLER,
    productId: 'rice',
    productTitle: 'Guruch',
    packId: 'p1',
    packLabel: '1 kg',
    qty: 10,
    unitPrice: 14000,
    goodsTotal: 140000,
    deliveryFee: fee,
    total: 140000 + fee,
    currency: 'UZS',
    delivery: {
      tariffVersion: snap.tariffVersion, zone: snap.zone, actualWeightG: 800, chargeableWeightG: snap.chargeableWeightG, dims: null, priceSnapshot: snap,
    },
    origin: ORIGIN,
    destination: DEST,
    quoteId: 'q1',
    status: 'placed',
    historySeq: 2,
    paymentMethod: 'bank_transfer',
    deliveryPaymentMethod: 'wallet',
    payment: { status: 'held', amount: fee, payer: 'buyer', covers: 'delivery_fee' },
    shipment: null,
    refundStatus: null,
    sellerDecision: 'pending',
    acceptDeadlineAt: new Date(WO.acceptDeadlineFor(NOW.getTime())),
    createdAt: NOW,
    updatedAt: NOW,
    statusUpdatedAt: NOW,
    ...extra,
  };
}
const BANK_DEADLINE = new Date(WO.bankPayDeadlineFor(NOW.getTime()));
/** Qabul qilingan, tovar puli kutilayotgan bank buyurtmasi. */
const awaitingExtra = (extra = {}) => ({
  sellerDecision: 'accepted',
  acceptedAt: NOW,
  sellerDecisionAt: NOW,
  bankPayment: {
    status: 'awaiting', awaitingSince: NOW, confirmedAt: null, confirmedBy: null,
  },
  bankPayDeadlineAt: BANK_DEADLINE,
  historySeq: 3,
  ...extra,
});
async function put(db, extra = {}, id = ORDER_ID) {
  await db.collection('wholesale_orders').doc(id).set(orderDoc(db, extra));
  return id;
}
const orderOf = (db, id = ORDER_ID) => db.docs.get(`wholesale_orders/${id}`);
const historyOf = (db, id = ORDER_ID) => db.dump(`wholesale_orders/${id}/history`);
const at = (ms) => () => new Date(NOW.getTime() + ms);
const confirm = (db, now = () => NOW) => B.makeConfirmWholesaleBankPayment({ db, now });
const newsKeys = (db) => Object.values(db.dump('admin_news')).map((n) => `${n.targetUserId}:${n.dataType}`).sort();
const keys = (b, a) => E.transitionNotifications(b, a).map((x) => `${x.to}:${x.key}`).sort();

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

// ═══════════════════════════════════════════════════════════════════════
// CORE (sof)
// ═══════════════════════════════════════════════════════════════════════

ok('core: bank_transfer — uchinchi usul; methodOf; deliveryPaidByBuyer (hamyon+bank ha, karta yo\'q)', () => {
  assert.deepStrictEqual([...WO.PAYMENT_METHODS], ['wallet', 'card_on_delivery', 'bank_transfer']);
  assert.strictEqual(WO.methodOf({ paymentMethod: 'bank_transfer' }), 'bank_transfer');
  assert.strictEqual(WO.methodOf({ paymentMethod: 'card_on_delivery' }), 'card_on_delivery');
  assert.strictEqual(WO.methodOf({}), 'wallet', 'eski buyurtma — hamyon');
  assert.strictEqual(WO.methodOf({ paymentMethod: 'weird' }), 'wallet');
  assert.strictEqual(WO.deliveryPaidByBuyer({ paymentMethod: 'bank_transfer' }), true);
  assert.strictEqual(WO.deliveryPaidByBuyer({}), true);
  assert.strictEqual(WO.deliveryPaidByBuyer({ paymentMethod: 'card_on_delivery' }), false);
  assert.deepStrictEqual([...WO.DELIVERY_PAYMENT_METHODS], ['wallet']);
  assert.strictEqual(WO.BANK_PAY_BUSINESS_DAYS, 5);
});

ok('muddat: qabul + 5 ish kuni (Du–Ju, Toshkent) — ish kunida o\'sha soat; dam olish kunida — Du 00:00 dan', () => {
  const cases = [
    ['2026-11-16T10:00', '2026-11-23T10:00'], // Du → keyingi Du
    ['2026-11-20T15:00', '2026-11-27T15:00'], // Ju → keyingi Ju
    ['2026-11-18T23:59', '2026-11-25T23:59'], // Ch 23:59
    ['2026-11-21T12:00', '2026-11-30T00:00'], // Sh → Du 00:00 + 5 = keyingi Du 00:00
    ['2026-11-22T23:59', '2026-11-30T00:00'], // Ya
  ];
  for (const [from, to] of cases) assert.strictEqual(localIso(WO.bankPayDeadlineFor(T(from))), to, `${from} → ${to}`);
  // UTC chegarasi: Ju 19:30Z = Sh 00:30 mahalliy → keyingi hafta Du 00:00 + 5 ish kuni.
  assert.strictEqual(WO.bankPayDeadlineFor(Date.parse('2026-11-20T19:30:00Z')), T('2026-11-30T00:00'));
  assert.throws(() => WO.bankPayDeadlineFor(1.5));
});

ok('shipmentAllowed (bank): qabul yetmaydi — FAQAT confirmed + confirmedAt; hamyon/eski — o\'zgarmagan', () => {
  const acc = { paymentMethod: 'bank_transfer', sellerDecision: 'accepted', acceptedAt: NOW };
  assert.strictEqual(WO.shipmentAllowed(acc), false, 'bankPayment yo\'q');
  assert.strictEqual(WO.shipmentAllowed({ ...acc, bankPayment: { status: 'awaiting' } }), false);
  assert.strictEqual(WO.shipmentAllowed({ ...acc, bankPayment: { status: 'confirmed' } }), false, 'confirmedAt yo\'q');
  for (const s of ['timeout', 'cancelled', '']) assert.strictEqual(WO.shipmentAllowed({ ...acc, bankPayment: { status: s, confirmedAt: NOW } }), false, s);
  assert.strictEqual(WO.shipmentAllowed({ ...acc, bankPayment: { status: 'confirmed', confirmedAt: NOW } }), true);
  assert.strictEqual(WO.shipmentAllowed({ ...acc, sellerDecision: 'pending', bankPayment: { status: 'confirmed', confirmedAt: NOW } }), false);
  assert.strictEqual(WO.shipmentAllowed({ paymentMethod: 'wallet', sellerDecision: 'accepted', acceptedAt: NOW }), true);
  assert.strictEqual(WO.shipmentAllowed({}), true);
});

ok('parseQuoteRequest: bank — deliveryPaymentMethod yo\'q/bo\'sh → wallet; cash → unsupported; boshqa usulda berilsa — not_applicable', () => {
  const base = { productId: 'rice', packId: 'p1', qty: 10, destination: { addressText: 'Gurlan 5' } };
  assert.strictEqual(W.parseQuoteRequest({ ...base, paymentMethod: 'bank_transfer' }).deliveryPaymentMethod, 'wallet');
  assert.strictEqual(W.parseQuoteRequest({ ...base, paymentMethod: 'bank_transfer', deliveryPaymentMethod: '' }).deliveryPaymentMethod, 'wallet');
  assert.strictEqual(W.parseQuoteRequest({ ...base, paymentMethod: 'bank_transfer', deliveryPaymentMethod: 'wallet' }).deliveryPaymentMethod, 'wallet');
  for (const bad of ['cash', 'card', 'WALLET', 1]) {
    assert.throws(() => W.parseQuoteRequest({ ...base, paymentMethod: 'bank_transfer', deliveryPaymentMethod: bad }),
      (e) => e.details.reason === 'delivery_payment_method_unsupported' && e.details.allowed.join() === 'wallet', String(bad));
  }
  assert.strictEqual(W.parseQuoteRequest({ ...base }).deliveryPaymentMethod, null);
  for (const pm of ['wallet', 'card_on_delivery']) {
    assert.throws(() => W.parseQuoteRequest({ ...base, paymentMethod: pm, deliveryPaymentMethod: 'wallet' }),
      (e) => e.details.reason === 'delivery_payment_method_not_applicable', pm);
  }
  assert.throws(() => W.parseQuoteRequest({ ...base, paymentMethod: 'bank' }),
    (e) => e.details.reason === 'payment_method_invalid' && e.details.allowed.includes('bank_transfer'));
});

ok('bankAvailability: tasdiqlangan + yetkazish haqi > 0 — ochiq; aks holda sabab kodi', () => {
  assert.deepStrictEqual(W.bankAvailability({ approvalStatus: 'approved' }, 60000), { available: true, reason: null });
  assert.deepStrictEqual(W.bankAvailability({ approvalStatus: 'pending' }, 60000), { available: false, reason: 'seller_not_approved' });
  assert.deepStrictEqual(W.bankAvailability(null, 60000), { available: false, reason: 'seller_not_approved' });
  assert.deepStrictEqual(W.bankAvailability({ approvalStatus: 'approved' }, 0), { available: false, reason: 'delivery_fee_invalid' });
  assert.deepStrictEqual(W.bankAvailability({ approvalStatus: 'approved' }, 1), { available: true, reason: null });
});

// ═══════════════════════════════════════════════════════════════════════
// KVOTA (wholesale_card.test.js muhiti: 10 × 14 000, yetkazish 60 000, AVA 250 bps)
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
function quoteDb(sellerExtra = {}) {
  tariffCore.clearCache();
  config.clearCache();
  const db = new FakeFirestore({
    'geo_regions/xorazm': { name: 'Xorazm' },
    'geo_regions/toshkent_shahri': { name: 'Toshkent' },
    'geo_districts/gurlan': { regionId: 'xorazm' },
    'geo_districts/chilonzor': { regionId: 'toshkent_shahri' },
    'module_tariffs/logistics': { activeVersion: 3 },
    'module_tariffs/logistics_v3': QTARIFF,
    'module_config/wholesale_orders_all': { enabled: true, stage: 'public' },
    'settings/wholesale_orders': { avaFeeBps: 200, feeVersion: 4 },
    [`wholesale_sellers/${SELLER}`]: {
      phone: SELLER, approvalStatus: 'approved', regionId: 'xorazm', districtId: 'gurlan', address: 'Markaz 1', ...sellerExtra,
    },
    'wholesale_products/rice': {
      sellerId: SELLER,
      title: 'Гуруч',
      status: 'active',
      market: 'wholesale',
      packs: [{ id: 'p1', label: '1 кг', priceTiers: [{ minQty: 1, price: 15000 }, { minQty: 10, price: 14000 }], unitWeightG: 1000 }],
    },
    'wholesale_stock/rice': { packs: { p1: 100 }, version: 1 },
  });
  return db;
}
const quote = (db) => W.makeQuoteWholesaleOrder({ db, now: () => NOW });
const qreq = (extra = {}) => ({
  productId: 'rice', packId: 'p1', qty: 10, destination: { regionId: 'toshkent_shahri', districtId: 'chilonzor', addressText: 'Chilonzor 5' }, ...extra,
});

ok('kvota bank_transfer: muhr paymentMethod + deliveryPaymentMethod + bankHold = deliveryFee; avaFee muhrda, javobda YO\'Q', async () => {
  const db = quoteDb();
  const r = await q(() => quote(db)(qreq({ paymentMethod: 'bank_transfer' }), { auth: { token: { phone_number: `+${BUYER}` } } }));
  assert.strictEqual(r.paymentMethod, 'bank_transfer');
  assert.deepStrictEqual(r.paymentMethods, { wallet: true, card_on_delivery: false, bank_transfer: true });
  assert.deepStrictEqual([r.deliveryPaymentMethod, r.walletHold, r.deliveryFee, r.goodsTotal], ['wallet', 60000, 60000, 140000]);
  assert.strictEqual(r.bankUnavailableReason, null);
  for (const k of ['avaFee', 'sellerPayout', 'bankHold', 'cardHold']) assert.ok(!(k in r), `${k} xaridorga ko'rinmaydi`);
  const qd = db.dump('wholesale_quotes')[r.quoteId];
  assert.deepStrictEqual([qd.paymentMethod, qd.deliveryPaymentMethod, qd.bankHold, qd.cardHold], ['bank_transfer', 'wallet', 60000, undefined]);
  assert.deepStrictEqual([qd.avaFeeBps, qd.avaFee, qd.sellerPayout, qd.feeVersion], [200, 2800, 137200, 4], 'AVA ulushi hisobot uchun muhrlanadi');
});

ok('kvota: sotuvchi tasdiqlanmagan — bank yopiq (hamyon kvotasida false + sabab); bank so\'rovi — bank_transfer_unavailable, kvota YOZILMAYDI', async () => {
  const db = quoteDb({ approvalStatus: 'pending' });
  const c = { auth: { token: { phone_number: `+${BUYER}` } } };
  const r = await q(() => quote(db)(qreq(), c));
  assert.deepStrictEqual([r.paymentMethods.bank_transfer, r.bankUnavailableReason], [false, 'seller_not_approved']);
  const before = Object.keys(db.dump('wholesale_quotes')).length;
  const e = await q(() => rejects(quote(db)(qreq({ paymentMethod: 'bank_transfer' }), c), 'failed-precondition', 'bank_transfer_unavailable'));
  assert.strictEqual(e.details.bankUnavailableReason, 'seller_not_approved');
  assert.strictEqual(Object.keys(db.dump('wholesale_quotes')).length, before);
  await q(() => rejects(quote(db)(qreq({ paymentMethod: 'bank_transfer', deliveryPaymentMethod: 'cash' }), c),
    'invalid-argument', 'delivery_payment_method_unsupported'));
});

// ═══════════════════════════════════════════════════════════════════════
// QABUL → KUTISH → «ПУЛ ТУШДИ» → JO'NATMA
// ═══════════════════════════════════════════════════════════════════════

ok('qabul (bank): awaiting + bankPayDeadlineAt = qabul + 5 ish kuni + history; jo\'natma YO\'Q; xabarlar — bank matnlari', async () => {
  const db = makeDb(seedW());
  await put(db);
  const before = orderOf(db);
  const r = await q(() => W.makeAcceptWholesaleOrder({ db, now: at(HOUR) })({ orderId: ORDER_ID }, ctx(SELLER)));
  const t1 = NOW.getTime() + HOUR;
  assert.strictEqual(r.bankPayDeadlineMs, WO.bankPayDeadlineFor(t1));
  const o = orderOf(db);
  assert.deepStrictEqual([o.status, o.sellerDecision, o.bankPayment.status], ['placed', 'accepted', 'awaiting']);
  assert.strictEqual(o.bankPayDeadlineAt.getTime(), WO.bankPayDeadlineFor(t1));
  assert.strictEqual(o.bankPayment.awaitingSince.getTime(), t1);
  assert.deepStrictEqual(o.payment, before.payment, 'pul maydonlari tegilmaydi');
  const h = historyOf(db)['3'];
  assert.deepStrictEqual([h.event, h.meta.bankPayBusinessDays], ['seller_accepted', 5]);
  const u = await q(() => E.onWholesaleOrderUpdated(deps(db, new Date(t1)), before, o, ORDER_ID));
  assert.strictEqual(u.shipment, undefined, 'tovar puli tasdiqlanmaguncha jo\'natma ochilmaydi');
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 0);
  assert.strictEqual((await q(() => W.ensureWholesaleShipment(deps(db), ORDER_ID))).skipped, 'seller_decision_accepted');
  assert.deepStrictEqual(newsKeys(db), [`${BUYER}:ws_bank_await_buyer`, `${SELLER}:ws_bank_await_seller`].sort());
  const body = Object.values(db.dump('admin_news')).find((n) => n.dataType === 'ws_bank_await_buyer').body;
  assert.ok(body.includes('140000') && body.includes(E.deadlineText(o.bankPayDeadlineAt)), body);
});

ok('qabul (hamyon): bankPayment YOZILMAYDI (regressiya yo\'q)', async () => {
  const db = makeDb(seedW());
  await put(db, { paymentMethod: 'wallet', deliveryPaymentMethod: undefined });
  await q(() => W.makeAcceptWholesaleOrder({ db, now: () => NOW })({ orderId: ORDER_ID }, ctx(SELLER)));
  const o = orderOf(db);
  assert.deepStrictEqual([o.bankPayment, o.bankPayDeadlineAt, o.sellerDecision], [undefined, undefined, 'accepted']);
});

ok('«Пул тушди»: faqat sotuvchi; auth; noto\'g\'ri ID; bank emas; qabulgacha — rad, yozuv yo\'q', async () => {
  const db = makeDb(seedW());
  await put(db, awaitingExtra());
  await put(db, { paymentMethod: 'wallet', ...awaitingExtra({ bankPayment: undefined, bankPayDeadlineAt: undefined }) }, 'wal');
  await put(db, {}, 'pend');
  await q(async () => {
    await rejects(confirm(db)({ orderId: ORDER_ID }, ctx(BUYER)), 'permission-denied', 'not_order_party');
    await rejects(confirm(db)({ orderId: ORDER_ID }, ctx(STRANGER)), 'permission-denied', 'not_order_party');
    await rejects(confirm(db)({ orderId: ORDER_ID }, {}), 'unauthenticated');
    await rejects(confirm(db)({ orderId: 'a/b' }, ctx(SELLER)), 'invalid-argument', 'order_required');
    await rejects(confirm(db)({ orderId: 'nope' }, ctx(SELLER)), 'not-found', 'order_not_found');
    await rejects(confirm(db)({ orderId: 'wal' }, ctx(SELLER)), 'failed-precondition', 'not_bank_order');
    await rejects(confirm(db)({ orderId: 'pend' }, ctx(SELLER)), 'failed-precondition', 'seller_not_accepted');
  });
  assert.strictEqual(orderOf(db).bankPayment.status, 'awaiting');
  assert.deepStrictEqual(historyOf(db), {});
});

ok('«Пул тушди»: confirmed + history; takror — idempotent (yozuv yo\'q); onUpdate → jo\'natma + xaridorga xabar', async () => {
  const db = makeDb(seedW());
  await put(db, awaitingExtra({ sellerId: SELLER.slice(3) }));
  const before = orderOf(db);
  const r = await q(() => confirm(db, at(DAY))({ orderId: ORDER_ID }, ctx(SELLER)));
  assert.deepStrictEqual([r.ok, r.bankPaymentStatus, r.idempotent], [true, 'confirmed', false]);
  const o = orderOf(db);
  assert.deepStrictEqual([o.bankPayment.status, o.bankPayment.confirmedBy, o.status, o.historySeq], ['confirmed', SELLER, 'placed', 4]);
  assert.strictEqual(o.bankPayment.confirmedAt.getTime(), NOW.getTime() + DAY);
  assert.strictEqual(historyOf(db)['4'].event, 'bank_payment_confirmed');
  const writes = db.writes;
  const r2 = await q(() => confirm(db, at(2 * DAY))({ orderId: ORDER_ID }, ctx(SELLER)));
  assert.strictEqual(r2.idempotent, true);
  assert.strictEqual(db.writes, writes);
  const u = await q(() => E.onWholesaleOrderUpdated(deps(db, new Date(NOW.getTime() + DAY)), before, o, ORDER_ID));
  assert.strictEqual(u.shipment.linked, true);
  const linked = orderOf(db);
  assert.strictEqual(db.dump('shipments')[linked.shipment.shipmentId].wholesaleOrderId, ORDER_ID);
  assert.strictEqual(linked.status, 'placed', 'in_delivery — default codebase eskrou o\'tkazganda');
  assert.deepStrictEqual(newsKeys(db), [`${BUYER}:ws_bank_confirmed_buyer`]);
  // Takror trigger — ikkinchi jo'natma yo'q.
  const u2 = await q(() => E.onWholesaleOrderUpdated(deps(db), before, o, ORDER_ID));
  assert.strictEqual(u2.shipment.skipped, 'already_linked');
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 1);
});

ok('«Пул тушди»: muddat chegarasi — aynan muddatda o\'tadi, +1 ms — bank_pay_deadline_passed; muddat yo\'q — missing; bekor/timeout — rad', async () => {
  const db = makeDb(seedW());
  await put(db, awaitingExtra(), 'a');
  await put(db, awaitingExtra(), 'b');
  await put(db, awaitingExtra({ bankPayDeadlineAt: null }), 'c');
  await put(db, awaitingExtra({ status: 'cancelled', bankPayment: { status: 'timeout' } }), 'd');
  await put(db, awaitingExtra({ bankPayment: { status: 'cancelled' } }), 'e');
  const atDl = () => new Date(BANK_DEADLINE.getTime());
  const after = () => new Date(BANK_DEADLINE.getTime() + 1);
  assert.strictEqual((await q(() => confirm(db, atDl)({ orderId: 'a' }, ctx(SELLER)))).idempotent, false);
  await q(async () => {
    await rejects(confirm(db, after)({ orderId: 'b' }, ctx(SELLER)), 'failed-precondition', 'bank_pay_deadline_passed');
    await rejects(confirm(db)({ orderId: 'c' }, ctx(SELLER)), 'failed-precondition', 'bank_pay_deadline_missing');
    await rejects(confirm(db)({ orderId: 'd' }, ctx(SELLER)), 'failed-precondition', 'order_not_placed');
    await rejects(confirm(db)({ orderId: 'e' }, ctx(SELLER)), 'failed-precondition', 'bank_payment_state');
  });
  assert.strictEqual(orderOf(db, 'b').bankPayment.status, 'awaiting');
});

// ═══════════════════════════════════════════════════════════════════════
// SWEEPER
// ═══════════════════════════════════════════════════════════════════════

ok('sweeper: muddat o\'tgan awaiting → cancelled (system, bank_payment_timeout, refundStatus pending); chegara <=; takror — yo\'q; xabarlar', async () => {
  const db = makeDb(seedW());
  const past = new Date(NOW.getTime() - 1);
  await put(db, awaitingExtra({ bankPayDeadlineAt: past }), 'exp');
  await put(db, awaitingExtra({ bankPayDeadlineAt: new Date(NOW.getTime()) }), 'edge');
  await put(db, awaitingExtra({ bankPayDeadlineAt: new Date(NOW.getTime() + 1) }), 'fresh');
  await put(db, awaitingExtra({ bankPayDeadlineAt: past, bankPayment: { status: 'confirmed', confirmedAt: NOW } }), 'conf');
  const before = orderOf(db, 'exp');
  const r = await q(() => B.runWholesaleBankPaymentSweep({ db, now: () => NOW }));
  assert.deepStrictEqual([r.checked, r.cancelled, r.failed], [2, 2, 0]);
  const o = orderOf(db, 'exp');
  assert.deepStrictEqual([o.status, o.cancelledBy, o.cancelReason, o.refundStatus, o.bankPayment.status],
    ['cancelled', 'system', 'bank_payment_timeout', 'pending', 'timeout']);
  assert.deepStrictEqual(o.payment, before.payment, 'pul — default refundOrder (bu yerda yozilmaydi)');
  const h = historyOf(db, 'exp')['4'];
  assert.deepStrictEqual([h.from, h.to, h.actor, h.event], ['placed', 'cancelled', 'system', 'bank_payment_timeout']);
  assert.strictEqual(orderOf(db, 'edge').status, 'cancelled');
  for (const id of ['fresh', 'conf']) assert.strictEqual(orderOf(db, id).status, 'placed', id);
  const writes = db.writes;
  const r2 = await q(() => B.runWholesaleBankPaymentSweep({ db, now: () => NOW }));
  assert.deepStrictEqual([r2.checked, r2.cancelled], [0, 0]);
  assert.strictEqual(db.writes, writes);
  await q(() => E.onWholesaleOrderUpdated(deps(db), before, o, 'exp'));
  assert.deepStrictEqual(newsKeys(db), [`${BUYER}:ws_bank_timeout_buyer`, `${SELLER}:ws_bank_timeout_seller`].sort());
  await q(() => rejects(confirm(db)({ orderId: 'exp' }, ctx(SELLER)), 'failed-precondition', 'order_not_placed'));
});

ok('sweeper: so\'rov va tranzaksiya orasida «Пул тушди» bosilsa — bekor QILINMAYDI', async () => {
  const db = makeDb(seedW());
  await put(db, awaitingExtra({ bankPayDeadlineAt: new Date(NOW.getTime() - 1) }), 'race');
  const realTx = db.runTransaction;
  let first = true;
  db.runTransaction = async (fn) => {
    if (first) {
      first = false;
      await db.collection('wholesale_orders').doc('race').update({ 'bankPayment.status': 'confirmed', 'bankPayment.confirmedAt': NOW });
    }
    return realTx(fn);
  };
  const r = await q(() => B.runWholesaleBankPaymentSweep({ db, now: () => NOW }));
  assert.deepStrictEqual([r.checked, r.cancelled, r.skipped], [1, 0, 1]);
  assert.deepStrictEqual([orderOf(db, 'race').status, orderOf(db, 'race').refundStatus], ['placed', null]);
});

ok('sweeper: limit — bir chaqiruvda ko\'pi bilan N ta', async () => {
  const db = makeDb(seedW());
  for (let i = 0; i < 4; i += 1) await put(db, awaitingExtra({ bankPayDeadlineAt: new Date(NOW.getTime() - 1) }), `o${i}`);
  const r1 = await q(() => B.runWholesaleBankPaymentSweep({ db, now: () => NOW }, { limit: 3 }));
  const r2 = await q(() => B.runWholesaleBankPaymentSweep({ db, now: () => NOW }, { limit: 3 }));
  assert.deepStrictEqual([r1.cancelled, r2.cancelled], [3, 1]);
  assert.strictEqual(B.BANK_SWEEP_LIMIT, 200);
});

// ═══════════════════════════════════════════════════════════════════════
// XARIDOR BEKOR QILISHI (PROPOSED: tasdiqqacha)
// ═══════════════════════════════════════════════════════════════════════

ok('xaridor bekor: qaror kutilayotganda / tovar puli kutilayotganda — ha (bankPayment cancelled, sotuvchiga xabar); tasdiqdan keyin — bank_payment_confirmed', async () => {
  const db = makeDb(seedW());
  await put(db, {}, 'pend');
  await put(db, awaitingExtra(), 'aw');
  await put(db, awaitingExtra({ bankPayment: { status: 'confirmed', confirmedAt: NOW } }), 'cf');
  const cancel = W.makeCancelWholesaleOrder({ db, now: at(HOUR) });
  await q(() => cancel({ orderId: 'pend' }, ctx(BUYER)));
  assert.deepStrictEqual([orderOf(db, 'pend').status, orderOf(db, 'pend').bankPayment], ['cancelled', undefined]);
  const before = orderOf(db, 'aw');
  await q(() => cancel({ orderId: 'aw' }, ctx(BUYER)));
  const aw = orderOf(db, 'aw');
  assert.deepStrictEqual([aw.status, aw.cancelledBy, aw.refundStatus, aw.bankPayment.status], ['cancelled', 'buyer', 'pending', 'cancelled']);
  await q(() => rejects(cancel({ orderId: 'cf' }, ctx(BUYER)), 'failed-precondition', 'bank_payment_confirmed'));
  assert.strictEqual(orderOf(db, 'cf').status, 'placed');
  await q(() => E.onWholesaleOrderUpdated(deps(db), before, aw, 'aw'));
  assert.deepStrictEqual(newsKeys(db), [`${SELLER}:ws_bank_buyer_cancelled_seller`]);
  // Bekor qilingan — sweeper endi ko'rmaydi.
  const r = await q(() => B.runWholesaleBankPaymentSweep({ db, now: () => new Date(BANK_DEADLINE.getTime() + 1) }));
  assert.strictEqual(r.checked, 0);
});

// ═══════════════════════════════════════════════════════════════════════
// RECONCILE — kutilayotgan bank buyurtmalari so'rovni to'ldirmaydi
// ═══════════════════════════════════════════════════════════════════════

ok('reconcile: 150 ta awaiting bank (limit 100 dan ko\'p) — hamyon va bank-TASDIQLANGAN buyurtmalar baribir bog\'lanadi', async () => {
  const db = makeDb(seedW());
  for (let i = 0; i < 150; i += 1) await put(db, awaitingExtra(), `a${String(i).padStart(3, '0')}`);
  await put(db, { paymentMethod: 'wallet', ...awaitingExtra({ bankPayment: undefined, bankPayDeadlineAt: undefined }) }, 'zwallet');
  await put(db, awaitingExtra({ bankPayment: { status: 'confirmed', confirmedAt: NOW } }), 'zconf');
  const rc = await q(() => W.reconcileWholesaleShipments({ ...deps(db), now: at(10 * 60 * 1000) }));
  assert.deepStrictEqual([rc.linked, rc.checked], [2, 2], JSON.stringify(rc));
  assert.ok(orderOf(db, 'zwallet').shipment.shipmentId);
  assert.ok(orderOf(db, 'zconf').shipment.shipmentId);
  assert.strictEqual(orderOf(db, 'a000').shipment, null);
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 2);
});

// ═══════════════════════════════════════════════════════════════════════
// RAD / YO'QOLISH — xabarlar (ega, 2026-11-14: tovar puli qaytarish matni YO'Q)
// ═══════════════════════════════════════════════════════════════════════

ok('«етказилмади» (bank): hamyon sabablari (other yo\'q), to\'lov holati held — mavjud hamyon oqimi', () => {
  const o = { paymentMethod: 'bank_transfer', status: 'in_delivery', payment: { status: 'held' } };
  assert.deepStrictEqual(DF.allowedReasonsOf(o), [...DF.WALLET_REASONS]);
  assert.deepStrictEqual(DF.allowedReasonsOf({ paymentMethod: 'card_on_delivery' }), [...DF.REASONS]);
});

ok('xabarlar (bank): rad → faqat xaridorga umumiy (sababga qarab), sotuvchiga «pul» matni yo\'q; yo\'qolish → yetkazish haqi matni', () => {
  const inDel = { status: 'in_delivery', paymentMethod: 'bank_transfer' };
  assert.deepStrictEqual(keys(inDel, { ...inDel, status: 'refused', refusal: { reasonCode: 'customer_absent' } }), ['buyer:ws_refused_buyer_absent']);
  assert.deepStrictEqual(keys(inDel, { ...inDel, status: 'refused', refusal: { reasonCode: 'courier_problem' } }), ['buyer:ws_refused_buyer_courier']);
  // Pul hisoblangach (refundStatus done) hamyon «товар суммаси қайтарилди» xabari bankda YO'Q.
  const ref = { ...inDel, status: 'refused', refundStatus: 'pending', walletRefusal: null };
  assert.deepStrictEqual(keys(ref, { ...ref, refundStatus: 'done', walletRefusal: { fault: 'buyer', goodsRefunded: 0 } }), []);
  assert.deepStrictEqual(keys(inDel, { ...inDel, status: 'lost', lost: { deliveryFeeRefunded: 30000, deliveryFeeOutstanding: 0 } }),
    ['buyer:ws_bank_lost_buyer', 'seller:ws_lost_seller']);
  assert.deepStrictEqual(keys(inDel, { ...inDel, status: 'lost', lost: { deliveryFeeRefunded: 10000, deliveryFeeOutstanding: 20000 } }),
    ['admins:ws_lost_fee_admin', 'buyer:ws_bank_lost_buyer_partial', 'seller:ws_lost_seller']);
  // Kuryer qaytish haqi / qarzi xabarlari — hamyon bilan bir xil.
  const rfd = { ...inDel, status: 'refused', refusal: { by: '998900000001' } };
  assert.deepStrictEqual(keys(rfd, { ...rfd, courierReturnDebt: { amount: 5000 } }),
    ['admins:ws_return_courier_debt_admin', 'refusal_courier:ws_return_courier_debt']);
  // Boshqa usullar o'zgarmagan.
  const wal = { status: 'in_delivery', paymentMethod: 'wallet' };
  assert.deepStrictEqual(keys(wal, { ...wal, status: 'refused', refusal: { reasonCode: 'customer_absent' } }), ['seller:ws_refused_seller_wallet']);
});

ok('xabar matnlari: 8 yangi bank kaliti × 3 til, o\'rinbosarlar to\'ldiriladi', () => {
  const p = {
    product: 'Guruch', qty: 10, goods: 140000, bankDeadline: '14.10 02:30', refund: 30000, left: 20000,
  };
  const BANK_KEYS = ['ws_bank_await_buyer', 'ws_bank_await_seller', 'ws_bank_confirmed_buyer', 'ws_bank_timeout_buyer',
    'ws_bank_timeout_seller', 'ws_bank_buyer_cancelled_seller', 'ws_bank_lost_buyer', 'ws_bank_lost_buyer_partial'];
  assert.deepStrictEqual(Object.keys(N.MESSAGES).filter((k) => k.startsWith('ws_bank_')).sort(), [...BANK_KEYS].sort());
  for (const key of BANK_KEYS) {
    for (const lang of N.LANGS) {
      const t = N.render(key, lang, p);
      assert.ok(t.title && t.body, `${key}/${lang}`);
      assert.ok(!/\{\w+\}/.test(t.title + t.body), `${key}/${lang}: ${t.body}`);
    }
  }
  assert.ok(N.render('ws_bank_await_seller', 'ru', p).body.includes('14.10 02:30'));
});

// ═══════════════════════════════════════════════════════════════════════
// AVA ULUSHI HISOBOTI (10 kunlik + oylik)
// ═══════════════════════════════════════════════════════════════════════

ok('davr: 01→11, 11→21, 21→keyingi oy 1; oy oxiri 30/31, fevral 28/29, dekabr → yanvar; Toshkent 00:00', () => {
  const p = (s) => F.parsePeriod(s);
  assert.deepStrictEqual([p('2026-11-01').periodEnd, p('2026-11-01').lastDay], ['2026-11-11', '2026-11-10']);
  assert.deepStrictEqual([p('2026-11-11').periodEnd, p('2026-11-11').lastDay], ['2026-11-21', '2026-11-20']);
  assert.deepStrictEqual([p('2026-11-21').periodEnd, p('2026-11-21').lastDay], ['2026-12-01', '2026-11-30']);
  assert.deepStrictEqual([p('2026-10-21').lastDay, p('2026-02-21').lastDay, p('2028-02-21').lastDay], ['2026-10-31', '2026-02-28', '2028-02-29']);
  assert.deepStrictEqual([p('2026-12-21').periodEnd, p('2026-12-21').lastDay], ['2027-01-01', '2026-12-31']);
  assert.strictEqual(p('2026-11-01').startMs, Date.parse('2026-10-31T19:00:00Z'));
  assert.strictEqual(p('2026-11-21').endMs, Date.parse('2026-11-30T19:00:00Z'));
  for (const bad of ['2026-11-05', '2026-11-10', '2026-13-01', '2026-00-11', '26-11-01', '', null, '2026-11-1', '2019-01-01']) {
    assert.throws(() => F.parsePeriod(bad), (e) => e.details.reason === 'period_invalid', String(bad));
  }
  assert.deepStrictEqual(F.parseMonth('2026-12').endMs, Date.parse('2026-12-31T19:00:00Z'));
  assert.throws(() => F.parseMonth('2026-13'), (e) => e.details.reason === 'month_invalid');
});

function statementDb() {
  const db = makeDb(seedW({
    [`users/${ADMIN}`]: { role: 'admin' },
    [`users/${DISP}`]: { role: 'dispatcher' },
  }));
  return db;
}
const P = F.parsePeriod('2026-11-11');
async function delivered(db, id, {
  method = 'bank_transfer', seller = SELLER, deliveredAt, goods = 100000, fee = 2000, status = 'delivered', settlement,
} = {}) {
  await db.collection('wholesale_orders').doc(id).set({
    sellerId: seller, buyerId: BUYER, paymentMethod: method, status, goodsTotal: goods, deliveryFee: 30000, deliveredAt,
  });
  if (settlement !== null) {
    await db.collection('wholesale_orders').doc(id).collection('private').doc('settlement')
      .set(settlement || { goodsTotal: goods, avaFee: fee, avaFeeBps: 200, sellerPayout: goods - fee });
  }
}

ok('hisobot: faqat davrda YETKAZILGAN bank buyurtmalari (boshi kiradi, oxiri kirmaydi); hamyon/yetkazilmagan — yo\'q; anomaliya alohida', async () => {
  const db = statementDb();
  await delivered(db, 'b1', { deliveredAt: new Date(P.startMs), goods: 100000, fee: 2000 });
  await delivered(db, 'b2', { deliveredAt: new Date(P.endMs - 1), goods: 50001, fee: 1001 });
  await delivered(db, 'b3', { seller: SELLER2, deliveredAt: new Date(P.startMs + DAY), goods: 30000, fee: 600 });
  await delivered(db, 'xEnd', { deliveredAt: new Date(P.endMs) });
  await delivered(db, 'xBefore', { deliveredAt: new Date(P.startMs - 1) });
  await delivered(db, 'xWallet', { method: 'wallet', deliveredAt: new Date(P.startMs + HOUR) });
  await delivered(db, 'xCard', { method: 'card_on_delivery', deliveredAt: new Date(P.startMs + HOUR) });
  await delivered(db, 'xInDel', { status: 'in_delivery', deliveredAt: new Date(P.startMs + HOUR) });
  await delivered(db, 'bad', { deliveredAt: new Date(P.startMs + HOUR), settlement: null });
  const r = await q(() => F.makeAdminGetWholesaleFeeStatement({ db, now: () => new Date(P.endMs + DAY) })({ periodStart: '2026-11-11' }, ctx(ADMIN)));
  assert.deepStrictEqual([r.periodStart, r.periodEnd, r.lastDay, r.closed, r.methods], ['2026-11-11', '2026-11-21', '2026-11-20', true, ['bank_transfer', 'card_on_delivery']]);
  // S4: so'rov karta usulini ham oladi, lekin kuryerli karta (`xCard`) hisobotga KIRMAYDI (faqat o'z yetkazishi).
  assert.deepStrictEqual(r.totals, {
    sellers: 2, count: 3, goodsTotal: 180001, avaFeeDue: 3601,
  });
  const s1 = r.sellers.find((s) => s.sellerId === SELLER);
  assert.deepStrictEqual([s1.count, s1.goodsTotal, s1.avaFeeDue, s1.orderIds.sort(), s1.methods, s1.collected],
    [2, 150001, 3001, ['b1', 'b2'], { bank_transfer: 2 }, null]);
  assert.deepStrictEqual(r.anomalies, [{ orderId: 'bad', sellerId: SELLER, code: 'settlement_invalid' }]);
  assert.ok(r.sellers.every((s) => Number.isInteger(s.avaFeeDue)));
});

ok('hisobot: qat\'iy admin — dispatcher / oddiy / kirmagan RAD; noto\'g\'ri davr — period_invalid', async () => {
  const db = statementDb();
  const fn = F.makeAdminGetWholesaleFeeStatement({ db });
  await q(async () => {
    await rejects(fn({ periodStart: '2026-11-11' }, ctx(DISP)), 'permission-denied');
    await rejects(fn({ periodStart: '2026-11-11' }, ctx(SELLER)), 'permission-denied');
    await rejects(fn({ periodStart: '2026-11-11' }, {}), 'unauthenticated');
    await rejects(fn({ periodStart: '2026-11-12' }, ctx(ADMIN)), 'invalid-argument', 'period_invalid');
    await rejects(F.makeAdminGetWholesaleOrdersReport({ db })({ month: '2026-11' }, ctx(DISP)), 'permission-denied');
    await rejects(F.makeAdminMarkWholesaleFeeCollected({ db })({ sellerId: SELLER, periodStart: '2026-11-11' }, ctx(DISP)), 'permission-denied');
  });
});

ok('«yig\'ildi»: davr tugamagan — period_not_closed; qarz yo\'q — nothing_due; yozuv (server summasi) + idempotent; hisobotda ko\'rinadi', async () => {
  const db = statementDb();
  await delivered(db, 'b1', { deliveredAt: new Date(P.startMs + HOUR), goods: 100000, fee: 2000 });
  await delivered(db, 'b2', { deliveredAt: new Date(P.startMs + 2 * HOUR), goods: 40000, fee: 800 });
  const open = () => new Date(P.endMs - 1);
  const closed = () => new Date(P.endMs);
  const mark = (now) => F.makeAdminMarkWholesaleFeeCollected({ db, now });
  await q(async () => {
    await rejects(mark(open)({ sellerId: SELLER, periodStart: '2026-11-11' }, ctx(ADMIN)), 'failed-precondition', 'period_not_closed');
    await rejects(mark(closed)({ sellerId: SELLER2, periodStart: '2026-11-11' }, ctx(ADMIN)), 'failed-precondition', 'nothing_due');
    await rejects(mark(closed)({ sellerId: 'abc', periodStart: '2026-11-11' }, ctx(ADMIN)), 'invalid-argument', 'seller_required');
  });
  const r = await q(() => mark(closed)({ sellerId: SELLER.slice(3), periodStart: '2026-11-11', note: 'naqd olindi' }, ctx(ADMIN)));
  assert.deepStrictEqual([r.idempotent, r.avaFeeDue], [false, 2800]);
  const a = db.docs.get(`admin_audit/${F.collectedDocId(SELLER, '2026-11-11')}`);
  assert.deepStrictEqual([a.kind, a.actor, a.detail.avaFeeDue, a.detail.count, a.detail.orderIds.sort(), a.reason],
    ['wholesale_fee_collected', ADMIN, 2800, 2, ['b1', 'b2'], 'naqd olindi']);
  const writes = db.writes;
  const r2 = await q(() => mark(closed)({ sellerId: SELLER, periodStart: '2026-11-11' }, ctx(ADMIN)));
  assert.deepStrictEqual([r2.idempotent, r2.avaFeeDue], [true, 2800]);
  assert.strictEqual(db.writes, writes, 'takrorda yozuv yo\'q');
  const st = await q(() => F.makeAdminGetWholesaleFeeStatement({ db, now: closed })({ periodStart: '2026-11-11' }, ctx(ADMIN)));
  assert.deepStrictEqual(st.sellers[0].collected, { at: P.endMs, by: ADMIN, amount: 2800 });
});

ok('oylik hisobot: HAMMA usul, sotuvchi × usul (soni, tovar, yetkazish, AVA ulushi, qanday olinadi)', async () => {
  const db = statementDb();
  const M = F.parseMonth('2026-11');
  await delivered(db, 'w1', { method: 'wallet', deliveredAt: new Date(M.startMs), goods: 100000, fee: 2000 });
  await delivered(db, 'w2', { method: 'wallet', deliveredAt: new Date(M.startMs + DAY), goods: 50000, fee: 1000 });
  await delivered(db, 'b1', { deliveredAt: new Date(M.endMs - 1), goods: 70000, fee: 1400 });
  await delivered(db, 'c1', { method: 'card_on_delivery', seller: SELLER2, deliveredAt: new Date(M.startMs + DAY), goods: 10000, fee: 200 });
  await delivered(db, 'xDec', { method: 'wallet', deliveredAt: new Date(M.endMs) });
  const r = await q(() => F.makeAdminGetWholesaleOrdersReport({ db })({ month: '2026-11' }, ctx(ADMIN)));
  const row = (s, m) => r.rows.find((x) => x.sellerId === s && x.paymentMethod === m);
  assert.deepStrictEqual([row(SELLER, 'wallet').count, row(SELLER, 'wallet').goodsTotal, row(SELLER, 'wallet').avaFee, row(SELLER, 'wallet').avaFeeVia],
    [2, 150000, 3000, 'release']);
  assert.deepStrictEqual([row(SELLER, 'bank_transfer').avaFee, row(SELLER, 'bank_transfer').avaFeeVia], [1400, 'statement']);
  assert.strictEqual(row(SELLER2, 'card_on_delivery').deliveryFee, 30000);
  assert.deepStrictEqual(r.totals, {
    count: 4, goodsTotal: 230000, deliveryFee: 120000, avaFee: 4600,
  });
  assert.strictEqual(r.byMethod.wallet.count, 2);
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
