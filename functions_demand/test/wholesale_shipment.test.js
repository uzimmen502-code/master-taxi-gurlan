/**
 * Ulgurji buyurtma zanjiri, 3-bosqich — demand codebase (FakeFirestore):
 * buyurtma berilishi bilan relay jo'natmasi AVTOMATIK (sotuvchi qabul/rad qilmaydi).
 *
 *   node functions_demand/test/wholesale_shipment.test.js
 *
 * Qulflanadi:
 *   - createShipmentInternal / ensureWholesaleShipment idempotent (takror, parallel → 1 jo'natma)
 *   - narx MUHRDAN (tarif keyin o'zgarsa ham), ichki ulush muhrlangan versiyadan; versiya yo'q → xato kodi
 *   - o'lchamsiz posilka faqat ichki yaratishda; createLogisticsOrder hali o'lcham talab qiladi
 *   - getWholesaleDeliveryCode: faqat xaridor, relay hosilasi bilan bir xil kod; sotuvchi/begona — rad
 *   - relay getShipmentSecrets / cancelLogisticsOrder O'ZGARMAGAN (jonli): sotuvchi topshirish kodini oladi;
 *     guard'larsiz xavflar qulflangan (tuzatish — feat/ulg-relay-guards, deploy qilinmaguncha darvoza YOPIQ)
 *   - onCreate trigger order.shipment yozadi, holat o'zgarmaydi; xato yo'li + reconcile (2 daqiqa, 5 urinish → final)
 *   - xaridor bekor qilsa — to'lanmagan jo'natma va LEG ham bekor
 *   - logistika jo'natuvchi darvozasi to'smaydi; LEG ochilishi logistics_all ga bo'ysunadi
 *   - to'liq relay oqimi: eskrou (simulyatsiya) → LEG → acceptLeg (olish = sotuvchi) → scan → xaridor kodi bilan delivery
 */
const assert = require('assert');
const api = require('../api/logistics');
const L = require('../core/logistics');
const W = require('../api/wholesale_orders');
const tariffCore = require('../core/tariff');
const config = require('../core/config');
const {
  K1, NOW, ctx, makeDb, seed, orderPayload, deps, PHOTO,
} = require('./helpers/logistics_harness');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const BUYER = '998905556677';
const SELLER = '998901234567';
const STRANGER = '998907770007';
const ORDER_ID = 'wo1';

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

/** Kvota yozgan muhr (relay tarifining O'ZI bilan hisoblangan, o'lchamsiz). */
function sealedDelivery(tariff, weightG = 800, goodsTotal = 140000) {
  const snap = tariffCore.quoteParcel(tariff, { actualWeightG: weightG, declaredValue: goodsTotal }, ORIGIN, DEST, { dimsOptional: true });
  return {
    tariffVersion: snap.tariffVersion,
    zone: snap.zone,
    actualWeightG: weightG,
    chargeableWeightG: snap.chargeableWeightG,
    dims: null,
    priceSnapshot: snap,
  };
}

/** Default codebase `placeWholesaleOrder` yozadigan buyurtma shakli. */
function orderDoc(db, extra = {}) {
  const t = db.docs.get('module_tariffs/logistics_v7');
  const delivery = sealedDelivery(t);
  const fee = delivery.priceSnapshot.customerPrice;
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
    delivery,
    origin: ORIGIN,
    destination: DEST,
    quoteId: 'q1',
    status: 'placed',
    historySeq: 1,
    payment: { status: 'held', amount: 140000 + fee },
    shipment: null,
    refundStatus: null,
    createdAt: NOW,
    updatedAt: NOW,
    statusUpdatedAt: NOW,
    ...extra,
  };
}

async function placeOrder(db, extra = {}, id = ORDER_ID) {
  await db.collection('wholesale_orders').doc(id).set(orderDoc(db, extra));
  return id;
}
const orderOf = (db, id = ORDER_ID) => db.docs.get(`wholesale_orders/${id}`);
const at = (ms) => () => new Date(NOW.getTime() + ms);

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

// Kutilgan xato loglarini jim qilish (natija qatorlari ko'rinsin).
const realError = console.error;
const realLog = console.log;
function quiet() { console.error = () => {}; console.log = () => {}; }
function loud() { console.error = realError; console.log = realLog; }

// ═══════════════════════════════════════════════════════════════════════
ok('trigger: jo\'natma + ORDER + sirlar + LEG(draft); order.shipment yoziladi, holat placed qoladi', async () => {
  const db = makeDb(seedW());
  await placeOrder(db);
  quiet();
  let r;
  try { r = await W.onWholesaleOrderCreated(deps(db), orderOf(db), ORDER_ID); } finally { loud(); }
  assert.strictEqual(r.linked, true);
  const o = orderOf(db);
  assert.strictEqual(o.status, 'placed', 'holat o\'zgarmaydi (in_delivery — eskrou tushganda)');
  assert.strictEqual(o.shipment.shipmentId, r.shipmentId);
  assert.ok(/^AVA-\d{2}-\d{4}-\d{6}$/.test(o.shipment.trackingNumber));
  assert.strictEqual(o.shipmentError, null);
  assert.strictEqual(o.historySeq, 2);
  const h = db.docs.get(`wholesale_orders/${ORDER_ID}/history/2`);
  assert.deepStrictEqual([h.event, h.actor, h.from, h.to], ['shipment_created', 'system', 'placed', 'placed']);

  const ship = db.dump('shipments')[r.shipmentId];
  assert.strictEqual(ship.ownerId, SELLER, 'egasi/jo\'natuvchi = sotuvchi');
  assert.strictEqual(ship.recipientId, BUYER);
  assert.strictEqual(ship.source, 'wholesale');
  assert.strictEqual(ship.wholesaleOrderId, ORDER_ID);
  assert.strictEqual(ship.recipientName, 'Bobur');
  assert.strictEqual(ship.status, 'awaiting_payment');
  assert.strictEqual(ship.paymentStatus, 'pending', 'pul YO\'Q — eskrouni default codebase yozadi');
  assert.deepStrictEqual(ship.currentCustodian, { kind: 'sender', id: SELLER, since: NOW });
  assert.strictEqual(ship.parcel.declaredValue, 140000, 'e\'lon qilingan qiymat = tovar summasi');
  const lo = db.dump('logistics_orders')[ship.orderId];
  assert.deepStrictEqual(lo.recipient, { name: 'Bobur', phone: BUYER });
  assert.strictEqual(lo.ownerId, SELLER);
  assert.strictEqual(lo.source, 'wholesale');
  assert.strictEqual(lo.wholesaleOrderId, ORDER_ID);
  assert.strictEqual(lo.termsAcceptedAt, null);
  assert.ok(db.docs.get(`shipments/${r.shipmentId}/private/secrets`).qrSecret);
  const leg = db.dump('demands')[ship.legIds[0]];
  assert.strictEqual(leg.status, 'draft');
  assert.strictEqual(leg.ownerId, SELLER, 'LEG-1 olish kontakti = sotuvchi');
  assert.strictEqual(leg.attributes.wholesaleOrderId, ORDER_ID);
  assert.strictEqual(leg.location.districtId, 'gurlan');
});

ok('idempotent: takror trigger / reconcile / parallel — BITTA jo\'natma va bitta bog\'lanish', async () => {
  const db = makeDb(seedW());
  await placeOrder(db);
  quiet();
  try {
    const rs = await Promise.all([
      W.ensureWholesaleShipment(deps(db), ORDER_ID),
      W.ensureWholesaleShipment(deps(db), ORDER_ID),
    ]);
    const again = await W.ensureWholesaleShipment(deps(db), ORDER_ID);
    assert.strictEqual(again.skipped, 'already_linked');
    assert.strictEqual(new Set(rs.map((r) => r.shipmentId)).size, 1, JSON.stringify(rs));
  } finally { loud(); }
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 1);
  assert.strictEqual(Object.keys(db.dump('logistics_orders')).length, 1);
  assert.strictEqual(Object.keys(db.dump('demands')).length, 1);
  // Ichki yordamchining o'zi ham: takror chaqiruv — o'sha natija.
  const o = orderOf(db);
  const name = 'Bobur';
  const r2 = await api.createShipmentInternal(deps(db), W.shipmentInputFromOrder(ORDER_ID, o, name));
  assert.strictEqual(r2.duplicate, true);
  assert.strictEqual(r2.shipmentId, o.shipment.shipmentId);
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 1);
});

ok('narx MUHRDAN: faol tarif o\'zgarsa ham customerPrice/tariffVersion o\'zgarmaydi, ulush v7 ichki qatlamidan', async () => {
  const base = seedW();
  const v7 = base['module_tariffs/logistics_v7'];
  const db = makeDb({
    ...base,
    'module_tariffs/logistics': { activeVersion: 8 },
    'module_tariffs/logistics_v8': {
      ...v7, version: 8, internal: { ...v7.internal, platformMarginBps: 5000 },
    },
  });
  await placeOrder(db);
  const o = orderOf(db);
  quiet();
  let r;
  try { r = await W.ensureWholesaleShipment(deps(db), ORDER_ID); } finally { loud(); }
  const ship = db.dump('shipments')[r.shipmentId];
  assert.strictEqual(ship.priceSnapshot.customerPrice, o.deliveryFee);
  assert.strictEqual(ship.priceSnapshot.tariffVersion, 7);
  assert.strictEqual(ship.priceSnapshot.zone, o.delivery.zone);
  const internal = db.docs.get(`shipments/${r.shipmentId}/private/internal`);
  const exp = tariffCore.splitInternal(v7, o.deliveryFee, ['direct']);
  assert.strictEqual(internal.tariffVersion, 7);
  assert.strictEqual(internal.platformShare, exp.platformShare, 'v7 marjasi (v8 emas)');
  assert.strictEqual(internal.platformShare + internal.providerPool, o.deliveryFee);
  assert.deepStrictEqual(internal.legPayouts.map((l) => l.amount), [exp.providerPool]);
  assert.strictEqual(db.dump('demands')[ship.legIds[0]].attributes.payout, exp.providerPool);
});

ok('muhrlangan tarif versiyasi yo\'q → shipmentError (tariff_version_missing), jo\'natma yo\'q', async () => {
  const db = makeDb(seedW());
  // Buyurtma muhri v7 bo'yicha; versiya hujjati keyin yo'qolgan.
  await placeOrder(db);
  db.docs.delete('module_tariffs/logistics_v7');
  quiet();
  let r;
  try { r = await W.onWholesaleOrderCreated(deps(db), orderOf(db), ORDER_ID); } finally { loud(); }
  assert.strictEqual(r.failed, true);
  assert.strictEqual(r.code, 'tariff_version_missing');
  const o = orderOf(db);
  assert.strictEqual(o.shipment, null);
  assert.strictEqual(o.status, 'placed');
  assert.strictEqual(o.shipmentError.code, 'tariff_version_missing');
  assert.strictEqual(o.shipmentError.attempts, 1);
  assert.strictEqual(o.shipmentError.final, false);
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 0);
  assert.ok(!JSON.stringify(o.shipmentError).includes(BUYER), 'xatoda PII yo\'q');
});

ok('muhr buzilgan (deliveryFee ≠ priceSnapshot.customerPrice) → delivery_price_mismatch, jo\'natma yo\'q', async () => {
  const db = makeDb(seedW());
  await placeOrder(db);
  await db.collection('wholesale_orders').doc(ORDER_ID).update({ deliveryFee: 1 });
  quiet();
  let r;
  try { r = await W.ensureWholesaleShipment(deps(db), ORDER_ID); } finally { loud(); }
  assert.strictEqual(r.code, 'delivery_price_mismatch');
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 0);
});

ok('reconcile: 2 daqiqadan yosh — kutadi; urinishlar 5 ta → final, keyin tegmaydi; tuzalsa — bog\'lanadi', async () => {
  const db = makeDb(seedW());
  const t7 = db.docs.get('module_tariffs/logistics_v7');
  await placeOrder(db);
  await placeOrder(db, {}, 'wo2');
  db.docs.delete('module_tariffs/logistics_v7');
  quiet();
  try {
    await W.onWholesaleOrderCreated(deps(db), orderOf(db), ORDER_ID); // attempts 1
    const r0 = await W.reconcileWholesaleShipments({ db, now: at(60 * 1000) });
    assert.deepStrictEqual([r0.checked, r0.young], [0, 2], 'trigger hali ishlayotgan bo\'lishi mumkin');
    for (let i = 0; i < 4; i += 1) await W.reconcileWholesaleShipments({ db, now: at(3 * 60 * 1000 + i) });
    const o = orderOf(db);
    assert.strictEqual(o.shipmentError.attempts, 5);
    assert.strictEqual(o.shipmentError.final, true, '5-urinishdan keyin admin (5-bosqich)');
    assert.strictEqual(orderOf(db, 'wo2').shipmentError.attempts, 4, 'wo2: triggersiz, faqat reconcile');
    const r5 = await W.reconcileWholesaleShipments({ db, now: at(20 * 60 * 1000) });
    assert.deepStrictEqual([r5.final, r5.checked, r5.failed], [1, 1, 1], 'final (wo1) qayta urinilmaydi');
    assert.strictEqual(orderOf(db).shipmentError.attempts, 5);
    assert.strictEqual(orderOf(db, 'wo2').shipmentError.final, true);
    const r5b = await W.reconcileWholesaleShipments({ db, now: at(25 * 60 * 1000) });
    assert.deepStrictEqual([r5b.final, r5b.checked], [2, 0]);
    // Tuzalgan + final bo'lmagan buyurtma — reconcile bog'laydi.
    db.docs.set('module_tariffs/logistics_v7', t7);
    await db.collection('wholesale_orders').doc('wo2').update({ shipmentError: { code: 'x', attempts: 2, final: false } });
    const r6 = await W.reconcileWholesaleShipments({ db, now: at(30 * 60 * 1000) });
    assert.deepStrictEqual([r6.checked, r6.linked, r6.final], [1, 1, 1]);
  } finally { loud(); }
  assert.ok(orderOf(db, 'wo2').shipment.shipmentId);
  assert.strictEqual(orderOf(db, 'wo2').shipmentError, null);
  assert.strictEqual(orderOf(db).shipment, null, 'final buyurtma — admin hal qiladi');
});

ok('trigger: placed bo\'lmagan buyurtma — jo\'natma yo\'q', async () => {
  const db = makeDb(seedW());
  await placeOrder(db, { status: 'cancelled' });
  const r = await W.onWholesaleOrderCreated(deps(db), orderOf(db), ORDER_ID);
  assert.strictEqual(r.skipped, 'not_placed');
  const r2 = await W.ensureWholesaleShipment(deps(db), ORDER_ID);
  assert.strictEqual(r2.skipped, 'status_cancelled');
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 0);
});

ok('o\'lchamsiz posilka FAQAT ichki yaratishda: createLogisticsOrder hali parcel_invalid; qisman o\'lcham — rad', async () => {
  const db = makeDb(seedW());
  await rejects(api.makeCreateLogisticsOrder(deps(db))(orderPayload({
    parcels: [{ actualWeightG: 800, declaredValue: 1000 }],
  }), ctx(SELLER)), 'invalid-argument', 'parcel_invalid');
  assert.throws(() => api.validateParcel({ actualWeightG: 800, lengthCm: 10, declaredValue: 5 }, 0, { dimsOptional: true }),
    (e) => e.details.reason === 'parcel_invalid');
  const p = api.validateParcel({ actualWeightG: 800, declaredValue: 5 }, 0, { dimsOptional: true });
  assert.deepStrictEqual([p.lengthCm, p.widthCm, p.heightCm], [null, null, null]);
  await placeOrder(db);
  quiet();
  let r;
  try { r = await W.ensureWholesaleShipment(deps(db), ORDER_ID); } finally { loud(); }
  const ship = db.dump('shipments')[r.shipmentId];
  assert.deepStrictEqual([ship.parcel.lengthCm, ship.parcel.widthCm, ship.parcel.heightCm], [null, null, null]);
  assert.strictEqual(ship.priceSnapshot.volumetricWeightG, 0);
  assert.strictEqual(db.dump('demands')[ship.legIds[0]].attributes.parcel.lengthCm, null);
});

ok('getWholesaleDeliveryCode: faqat xaridor; kod relay hosilasi bilan bir xil (confirmDelivery qabul qiladi); sotuvchi/begona rad', async () => {
  const db = makeDb(seedW());
  await placeOrder(db);
  const getCode = W.makeGetWholesaleDeliveryCode({ db });
  quiet();
  try {
    await rejects(getCode({ orderId: ORDER_ID }, ctx(BUYER)), 'failed-precondition', 'shipment_not_ready');
  } finally { loud(); }
  quiet();
  let r;
  try { r = await W.ensureWholesaleShipment(deps(db), ORDER_ID); } finally { loud(); }
  quiet();
  let b;
  try {
    b = await getCode({ orderId: ORDER_ID }, ctx(BUYER));
    await rejects(getCode({ orderId: ORDER_ID }, ctx(SELLER)), 'permission-denied', 'not_order_party');
    await rejects(getCode({ orderId: ORDER_ID }, ctx(STRANGER)), 'permission-denied', 'not_order_party');
    await rejects(getCode({ orderId: ORDER_ID }, {}), 'unauthenticated');
    await rejects(getCode({ orderId: '' }, ctx(BUYER)), 'invalid-argument', 'order_required');
    await rejects(getCode({ orderId: 'nope' }, ctx(BUYER)), 'not-found', 'order_not_found');
  } finally { loud(); }
  const qr = db.docs.get(`shipments/${r.shipmentId}/private/secrets`).qrSecret;
  assert.strictEqual(b.deliveryCode, L.deliveryCodeFor(r.shipmentId, qr));
  assert.ok(L.verifyDeliveryCode(r.shipmentId, qr, b.deliveryCode), 'confirmDelivery tekshiruvi bilan bir xil');
  assert.deepStrictEqual(Object.keys(b).sort(), ['deliveryCode', 'orderId', 'shipmentId', 'trackingNumber'], 'QR/topshirish kodi YO\'Q');
  // Jo'natma boshqa buyurtmaniki bo'lib qolsa — rad.
  await db.collection('shipments').doc(r.shipmentId).update({ wholesaleOrderId: 'other' });
  quiet();
  try {
    await rejects(getCode({ orderId: ORDER_ID }, ctx(BUYER)), 'permission-denied', 'not_recipient');
    await db.collection('shipments').doc(r.shipmentId).update({ wholesaleOrderId: ORDER_ID, status: 'delivered' });
    await rejects(getCode({ orderId: ORDER_ID }, ctx(BUYER)), 'failed-precondition', 'shipment_closed');
  } finally { loud(); }
});

ok('relay getShipmentSecrets (O\'ZGARMAGAN): sotuvchi = egasi — topshirish kodi + QR oladi; xaridor — rad', async () => {
  const db = makeDb(seedW());
  await placeOrder(db);
  quiet();
  let r;
  try { r = await W.ensureWholesaleShipment(deps(db), ORDER_ID); } finally { loud(); }
  const secrets = api.makeGetShipmentSecrets(deps(db));
  const s = await secrets({ shipmentId: r.shipmentId }, ctx(SELLER));
  const qr = db.docs.get(`shipments/${r.shipmentId}/private/secrets`).qrSecret;
  assert.strictEqual(s.handoverCode, L.handoverCodeFor(r.shipmentId, qr), 'LEG-1 topshirish kodi sotuvchida');
  assert.ok(s.qrPayload.startsWith(`AVA1|${r.shipmentId}|`));
  // XAVF QULFI: lineage getShipmentSecrets egaga (sotuvchiga) YETKAZISH kodini ham beradi —
  // sotuvchi + kuryer kelishib xaridorsiz «yetkazildi» qila oladi. Tuzatish: feat/ulg-relay-guards.
  assert.strictEqual(s.deliveryCode, L.deliveryCodeFor(r.shipmentId, qr));
  await rejects(secrets({ shipmentId: r.shipmentId }, ctx(BUYER)), 'permission-denied');
  await rejects(secrets({ shipmentId: r.shipmentId }, ctx(STRANGER)), 'permission-denied');
});

ok('XAVF QULFI (guard\'larsiz relay): sotuvchi cancelLogisticsOrder bilan to\'lanmagan Ulgurji jo\'natmasini bekor qila oladi', async () => {
  const db = makeDb(seedW());
  await placeOrder(db);
  quiet();
  let r;
  try { r = await W.ensureWholesaleShipment(deps(db), ORDER_ID); } finally { loud(); }
  const ship = db.dump('shipments')[r.shipmentId];
  const c = await api.makeCancelLogisticsOrder(deps(db))({ orderId: ship.orderId }, ctx(SELLER));
  assert.strictEqual(c.ok, true, 'feat/ulg-relay-guards deploy qilinmaguncha — darvoza YOPIQ');
  assert.strictEqual(db.dump('shipments')[r.shipmentId].status, 'cancelled');
  assert.strictEqual(orderOf(db).status, 'placed', 'buyurtma qotadi — default SHIP_FUND anomaliya beradi (shipment_not_payable)');
});

ok('xaridor bekor qilsa (to\'lanmagan) — jo\'natma, LEG va logistika ORDER ham bekor', async () => {
  const db = makeDb(seedW());
  await placeOrder(db);
  quiet();
  let r;
  try { r = await W.ensureWholesaleShipment(deps(db), ORDER_ID); } finally { loud(); }
  quiet();
  try {
    await W.makeCancelWholesaleOrder({ db, now: () => NOW })({ orderId: ORDER_ID }, ctx(BUYER));
  } finally { loud(); }
  const ship = db.dump('shipments')[r.shipmentId];
  assert.strictEqual(ship.status, 'cancelled');
  assert.strictEqual(ship.paymentStatus, 'pending');
  assert.strictEqual(ship.cancelledBy, 'wholesale_buyer');
  assert.strictEqual(db.dump('demands')[ship.legIds[0]].status, 'cancelled');
  assert.strictEqual(db.dump('logistics_orders')[ship.orderId].status, 'cancelled');
  const o = orderOf(db);
  assert.strictEqual(o.status, 'cancelled');
  assert.strictEqual(o.refundStatus, 'pending');
  const h = db.docs.get(`wholesale_orders/${ORDER_ID}/history/3`);
  assert.strictEqual(h.meta.shipmentCancelled, r.shipmentId);
});

ok('to\'langan jo\'natma (in_delivery) — xaridor bekor qila olmaydi, jo\'natmaga tegilmaydi', async () => {
  const db = makeDb(seedW());
  await placeOrder(db);
  quiet();
  let r;
  try { r = await W.ensureWholesaleShipment(deps(db), ORDER_ID); } finally { loud(); }
  await db.collection('shipments').doc(r.shipmentId).update({ paymentStatus: 'escrow_funded', status: 'ready' });
  await db.collection('wholesale_orders').doc(ORDER_ID).update({ status: 'in_delivery' });
  quiet();
  try {
    await rejects(W.makeCancelWholesaleOrder({ db, now: () => NOW })({ orderId: ORDER_ID }, ctx(BUYER)),
      'failed-precondition', 'invalid_transition');
  } finally { loud(); }
  assert.strictEqual(db.dump('shipments')[r.shipmentId].status, 'ready');
});

ok('logistika jo\'natuvchi darvozasi to\'smaydi; LEG ochilishi logistics_all ga bo\'ysunadi (o\'chiq → draft)', async () => {
  const db = makeDb(seedW({
    'module_config/logistics_all': { enabled: false, matchingEnabled: true, pushEnabled: false, logistics: { stage: 'internal' } },
  }));
  await placeOrder(db);
  quiet();
  let r;
  try { r = await W.ensureWholesaleShipment(deps(db), ORDER_ID); } finally { loud(); }
  assert.strictEqual(r.linked, true, 'kvotada Ulgurji darvozasi o\'tgan — jo\'natma ochiladi');
  const ref = db.collection('shipments').doc(r.shipmentId);
  const before = (await ref.get()).data();
  await ref.update({ paymentStatus: 'escrow_funded', status: 'ready' });
  quiet();
  let act;
  try { act = await api.makeOnShipmentFunded(deps(db))(before, (await ref.get()).data(), r.shipmentId); } finally { loud(); }
  assert.strictEqual(act.skipped, 'disabled');
  assert.strictEqual(db.dump('demands')[before.legIds[0]].status, 'draft');
});

ok('TO\'LIQ RELAY OQIMI: eskrou → LEG active → acceptLeg (olish = sotuvchi) → scan → xaridor kodi bilan delivery', async () => {
  const db = makeDb(seedW());
  await placeOrder(db);
  const d = deps(db);
  quiet();
  let r;
  try { r = await W.ensureWholesaleShipment(d, ORDER_ID); } finally { loud(); }
  const shipmentId = r.shipmentId;
  const ref = db.collection('shipments').doc(shipmentId);
  const before = (await ref.get()).data();
  const legId = before.legIds[0];
  // Default codebase (wholesaleShipFund) yozadigan maydonlar — relay FUND bilan bir xil.
  await ref.update({ paymentStatus: 'escrow_funded', status: 'ready', fundedAt: NOW });
  quiet();
  let act;
  try { act = await api.makeOnShipmentFunded(d)(before, (await ref.get()).data(), shipmentId); } finally { loud(); }
  assert.strictEqual(act.activated, true);
  assert.strictEqual(db.dump('demands')[legId].status, 'active');
  await api.makeAcceptLeg(d)({ legId }, ctx(K1));
  const m = db.dump('demand_matches')[`${legId}_${K1}`];
  assert.strictEqual(m.contactUnlocked.ownerPhone, SELLER, 'LEG-1 olish kontakti = sotuvchi');
  const sellerSec = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(SELLER));
  await api.makeScanHandover(d)({ legId, code: sellerSec.handoverCode, photoUrls: PHOTO }, ctx(K1));
  const m2 = db.dump('demand_matches')[`${legId}_${K1}`];
  assert.strictEqual(m2.contactUnlocked.recipientPhone, BUYER, '2-pog\'ona: qabul qiluvchi = xaridor');
  quiet();
  let buyerSec;
  try { buyerSec = await W.makeGetWholesaleDeliveryCode({ db })({ orderId: ORDER_ID }, ctx(BUYER)); } finally { loud(); }
  if (sellerSec.handoverCode !== buyerSec.deliveryCode) {
    await rejects(api.makeConfirmDelivery(d)({ legId, deliveryCode: sellerSec.handoverCode, photoUrls: PHOTO }, ctx(K1)),
      'permission-denied', 'bad_delivery_code');
  }
  const c = await api.makeConfirmDelivery(d)({ legId, deliveryCode: buyerSec.deliveryCode, photoUrls: PHOTO }, ctx(K1));
  assert.strictEqual(c.shipmentStatus, 'delivered');
  const ev = db.dump('custody_events')[c.eventId];
  assert.strictEqual(ev.deliversShipment, true, 'default codebase RELEASE triggeri shu hodisaga qaraydi');
  assert.strictEqual(ev.shipmentId, shipmentId);
  assert.strictEqual(ev.ownerId, SELLER);
  assert.strictEqual(ev.completedLegPayout, db.docs.get(`shipments/${shipmentId}/private/internal`).providerPool);
  const lo = db.dump('logistics_orders')[before.orderId];
  assert.strictEqual(lo.status, 'delivered');
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
