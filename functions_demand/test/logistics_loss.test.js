/**
 * "Yo'qolgan posilka" (D1, ega qarori 2026-10-16) — sof testlar (FakeFirestore).
 *
 *   node functions_demand/test/logistics_loss.test.js
 *
 * Haqiqiy tranzaksiya / parallel chaqiruv: `logistics_loss_emulator.test.js`.
 * Pul harakati (ledger) default codebase'da: `functions/test/relay_escrow_cf.test.js`.
 *
 * Qulflanadi:
 *   1) e'lon qilingan qiymat (declaredValue) MAJBURIY: yo'q yoki <= 0 bo'lsa
 *      quote ham, create ham rad (chunki yo'qolsa qaytariladigan summa G shu);
 *   2) adminMarkShipmentLost: faqat admin/superadmin, faqat in_transit/disputed +
 *      eskrou to'langan, posilka IJROCHIDA bo'lsa; idempotent.
 */
const assert = require('assert');
const api = require('../api/logistics');
const tariffCore = require('../core/tariff');
const config = require('../core/config');
const {
  fixture, OWNER, ADMIN, ctx, makeDb, seed, orderPayload, deps,
} = require('./helpers/logistics_harness');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const fresh = (extra) => { config.clearCache(); tariffCore.clearCache(); return makeDb(seed(extra)); };

const PARCEL = { actualWeightG: 800, lengthCm: 20, widthCm: 15, heightCm: 10, description: 'Kitoblar' };
const reasonOf = (reason) => (e) => e.code === 'invalid-argument' && e.details.reason === reason;

// ═══════════════════════════════════════════════════════════════════════
// 1) declaredValue MAJBURIY
for (const [label, dv, reason] of [
  ['yo\'q', undefined, 'declared_value_required'],
  ['null', null, 'declared_value_required'],
  ['0', 0, 'declared_value_required'],
  ['manfiy', -5000, 'declared_value_required'],
  ['kasr (1.5)', 1.5, 'parcel_invalid'],
  ['satr ("5000")', '5000', 'parcel_invalid'],
]) {
  ok(`quote: declaredValue ${label} — rad (${reason})`, async () => {
    const db = fresh();
    const parcel = dv === undefined ? PARCEL : { ...PARCEL, declaredValue: dv };
    await assert.rejects(
      () => api.makeQuoteLogisticsOrder({ db })(orderPayload({ parcels: [parcel] }), ctx(OWNER)),
      reasonOf(reason));
  });
}

ok('create: declaredValue yo\'q — rad va HECH NARSA yozilmaydi', async () => {
  const db = fresh();
  await assert.rejects(
    () => api.makeCreateLogisticsOrder(deps(db))(orderPayload({ parcels: [PARCEL] }), ctx(OWNER)),
    reasonOf('declared_value_required'));
  assert.deepStrictEqual(Object.keys(db.dump('shipments')), []);
  assert.deepStrictEqual(Object.keys(db.dump('logistics_orders')), []);
});

ok('create: ikkinchi posilkada declaredValue 0 — butun buyurtma rad (birinchisi to\'g\'ri bo\'lsa ham)', async () => {
  const db = fresh();
  const good = { ...PARCEL, declaredValue: 100000 };
  const bad = { ...PARCEL, declaredValue: 0 };
  await assert.rejects(
    () => api.makeCreateLogisticsOrder(deps(db))(orderPayload({ parcels: [good, bad] }), ctx(OWNER)),
    reasonOf('declared_value_required'));
  assert.deepStrictEqual(Object.keys(db.dump('shipments')), []);
});

ok('create: musbat declaredValue — shipment.priceSnapshot.declaredValue va parcel.declaredValue muhrlanadi', async () => {
  const db = fresh();
  const r = await api.makeCreateLogisticsOrder(deps(db))(
    orderPayload({ parcels: [{ ...PARCEL, declaredValue: 150000 }] }), ctx(OWNER));
  const s = db.dump('shipments')[r.shipmentIds[0]];
  assert.strictEqual(s.priceSnapshot.declaredValue, 150000);
  assert.strictEqual(s.parcel.declaredValue, 150000);
});

ok('declaredValueFee mantig\'i o\'zgarmagan: 1 234 567 so\'m -> haq 12 346 (feeBps 100, ceil)', async () => {
  // Harness tarifi haqni 0 qiladi (narx testlari barqaror turishi uchun) — bu yerda
  // ASL fixture tarifi (feeBps 100).
  const db = fresh({ 'module_tariffs/logistics_v7': fixture.tariff });
  const q = await api.makeQuoteLogisticsOrder({ db })(
    orderPayload({ parcels: [{ ...PARCEL, declaredValue: 1234567 }] }), ctx(OWNER));
  assert.strictEqual(q.parcels[0].declaredValueFee, 12346);
  assert.strictEqual(q.parcels[0].customerPrice, q.parcels[0].basePrice + 12346);
});

ok('tarif chegarasi o\'zgarmagan: maxValue dan katta qiymat — over_declared_value', async () => {
  const db = fresh();
  await assert.rejects(
    () => api.makeQuoteLogisticsOrder({ db })(
      orderPayload({ parcels: [{ ...PARCEL, declaredValue: 60000000 }] }), ctx(OWNER)),
    (e) => e.code === 'failed-precondition' && e.details.reason === 'over_declared_value');
});

// ═══════════════════════════════════════════════════════════════════════
// 2) adminMarkShipmentLost
const L = require('../core/logistics');
const {
  K1, F1, DECLARED_VALUE, legOf, photoFor,
} = require('./helpers/logistics_harness');

const DISPATCHER = '998908880000';
const SUPER = '998907770000';
const OPID = 'lost-op-0001';
const LOST = { reason: 'Kuryer yo\'qotdi', note: 'Telefon orqali tasdiqlandi', opId: OPID };
const lostSeed = () => ({
  [`users/${DISPATCHER}`]: { role: 'dispatcher' },
  [`users/${SUPER}`]: { role: 'superadmin' },
});
const markLost = (d) => api.makeAdminMarkShipmentLost(d);
const ROUTE2 = [
  { to: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
  { from: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
];

/** Bir LEG: yaratildi, to'landi, K1 oldi va posilkani QABUL QILDI (in_transit, custodian K1). */
async function inTransitOneLeg(db, d) {
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload(), ctx(OWNER));
  const shipmentId = r.shipmentIds[0];
  await require('./helpers/logistics_harness').fund(db, shipmentId);
  const [legId] = legOf(db, shipmentId);
  await api.makeAcceptLeg(d)({ legId }, ctx(K1));
  const sec = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(OWNER));
  await api.makeScanHandover(d)({ legId, code: sec.handoverCode, photoUrls: photoFor(K1) }, ctx(K1));
  return { shipmentId, orderId: r.orderId, legId, sec };
}

/** Ikki LEG (Gurlan -> Urganch -> Chilonzor): K1 LEG-1 ni oldi, F1 LEG-2 ni oldi va posilkani QABUL QILDI. */
async function inTransitTwoLegs(db, d) {
  const H = require('./helpers/logistics_harness');
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload({
    destination: { regionId: 'toshkent_shahri', districtId: 'chilonzor', lat: 41.28, lng: 69.2, addressText: 'Chilonzor 9' },
    parcels: [{ actualWeightG: 5000, lengthCm: 50, widthCm: 40, heightCm: 40, declaredValue: DECLARED_VALUE }],
  }), ctx(OWNER));
  const shipmentId = r.shipmentIds[0];
  await H.fund(db, shipmentId);
  const p = await api.makeAdminPlanShipmentRoute(d)({ shipmentId, reason: 'test', legs: ROUTE2 }, ctx(ADMIN));
  const [leg0, leg1] = p.legIds;
  await api.makeAcceptLeg(d)({ legId: leg0 }, ctx(K1));
  const sec = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(OWNER));
  await api.makeScanHandover(d)({ legId: leg0, code: sec.handoverCode, photoUrls: photoFor(K1) }, ctx(K1));
  await api.makeAcceptLeg(d)({ legId: leg1 }, ctx(F1));
  await api.makeScanHandover(d)({ legId: leg1, code: sec.handoverCode, photoUrls: photoFor(F1) }, ctx(F1));
  return { shipmentId, orderId: r.orderId, leg0, leg1, sec };
}

ok('PAYMENT_STATUS: loss_pending/loss_settled va o\'tishlar (faqat escrow_funded/escrow_frozen -> loss_pending -> loss_settled)', () => {
  assert.strictEqual(L.PAYMENT_STATUS.LOSS_PENDING, 'loss_pending');
  assert.strictEqual(L.PAYMENT_STATUS.LOSS_SETTLED, 'loss_settled');
  assert.ok(L.canTransitionPayment('escrow_funded', 'loss_pending'));
  assert.ok(L.canTransitionPayment('escrow_frozen', 'loss_pending'));
  assert.ok(L.canTransitionPayment('loss_pending', 'loss_settled'));
  for (const from of ['pending', 'settled', 'refund_pending', 'refunded', 'release_approved', 'loss_settled']) {
    assert.ok(!L.canTransitionPayment(from, 'loss_pending'), `${from} -> loss_pending MUMKIN EMAS`);
  }
  assert.ok(!L.canTransitionPayment('loss_pending', 'refund_pending'));
  assert.ok(!L.canTransitionPayment('loss_pending', 'settled'));
  assert.ok(!L.canTransitionPayment('loss_settled', 'refunded'));
});

ok('goodsValueOf: priceSnapshot.declaredValue (butun, > 0); yo\'q/0/kasr/satr -> 0', () => {
  assert.strictEqual(L.goodsValueOf({ priceSnapshot: { declaredValue: 150000 } }), 150000);
  for (const bad of [undefined, null, 0, -1, 1.5, '150000', NaN]) {
    assert.strictEqual(L.goodsValueOf({ priceSnapshot: { declaredValue: bad } }), 0, String(bad));
  }
  assert.strictEqual(L.goodsValueOf({}), 0);
});

ok('adminMarkShipmentLost: faqat admin/superadmin (oddiy foydalanuvchi, dispatcher, mijoz, kuryer, kirmagan — rad)', async () => {
  const db = fresh(lostSeed());
  const d = deps(db);
  const { shipmentId } = await inTransitOneLeg(db, d);
  const call = (who) => markLost(d)({ shipmentId, ...LOST }, who ? ctx(who) : { auth: null });
  for (const who of [OWNER, K1, DISPATCHER]) {
    await assert.rejects(() => call(who), (e) => e.code === 'permission-denied', who);
  }
  await assert.rejects(() => call(null), (e) => e.code === 'unauthenticated');
  assert.strictEqual(db.dump('shipments')[shipmentId].status, 'in_transit', 'rad etilganda hech narsa o\'zgarmaydi');
  assert.deepStrictEqual(Object.keys(db.dump('logistics_incidents')), []);
  const r = await call(SUPER);
  assert.strictEqual(r.ok, true);
});

ok('adminMarkShipmentLost: argumentlar (shipmentId, sabab, opId)', async () => {
  const db = fresh(lostSeed());
  const d = deps(db);
  const { shipmentId } = await inTransitOneLeg(db, d);
  const bad = async (data, reason) => assert.rejects(
    () => markLost(d)(data, ctx(ADMIN)), (e) => e.code === 'invalid-argument' && (!reason || e.details.reason === reason));
  await bad({ ...LOST });
  await bad({ shipmentId, ...LOST, reason: 'ab' }, 'loss_reason_required');
  await bad({ shipmentId, ...LOST, reason: '' }, 'loss_reason_required');
  await bad({ shipmentId, ...LOST, opId: 'qisqa' }, 'loss_op_id');
  await bad({ shipmentId, ...LOST, opId: 'bo\'sh joy bor!!' }, 'loss_op_id');
  assert.deepStrictEqual(Object.keys(db.dump('logistics_incidents')), []);
});

for (const [label, patch, reason] of [
  ['awaiting_payment', { status: 'awaiting_payment', paymentStatus: 'pending' }, 'shipment_not_lossable'],
  ['ready', { status: 'ready' }, 'shipment_not_lossable'],
  ['delivered', { status: 'delivered' }, 'shipment_not_lossable'],
  ['cancelled', { status: 'cancelled' }, 'shipment_not_lossable'],
  ['closed', { status: 'closed' }, 'shipment_not_lossable'],
  ['to\'lov settled', { paymentStatus: 'settled' }, 'payment_not_lossable'],
  ['to\'lov refund_pending', { paymentStatus: 'refund_pending' }, 'payment_not_lossable'],
  ['to\'lov pending', { paymentStatus: 'pending' }, 'payment_not_lossable'],
]) {
  ok(`adminMarkShipmentLost: ${label} — rad (${reason}), hech narsa yozilmaydi`, async () => {
    const db = fresh(lostSeed());
    const d = deps(db);
    const { shipmentId } = await inTransitOneLeg(db, d);
    await db.collection('shipments').doc(shipmentId).update(patch);
    const before = JSON.stringify(db.dump('shipments')[shipmentId]);
    const writes = db.writes;
    await assert.rejects(() => markLost(d)({ shipmentId, ...LOST }, ctx(ADMIN)),
      (e) => e.code === 'failed-precondition' && e.details.reason === reason);
    assert.strictEqual(db.writes, writes, 'yozuv yo\'q');
    assert.strictEqual(JSON.stringify(db.dump('shipments')[shipmentId]), before);
    assert.deepStrictEqual(Object.keys(db.dump('logistics_incidents')), []);
  });
}

ok('adminMarkShipmentLost: posilka ijrochida emas (jo\'natuvchi/qabul qiluvchi qo\'lida) — custodian_not_provider', async () => {
  for (const kind of ['sender', 'recipient']) {
    const db = fresh(lostSeed());
    const d = deps(db);
    const { shipmentId } = await inTransitOneLeg(db, d);
    await db.collection('shipments').doc(shipmentId).update({ currentCustodian: { kind, id: kind === 'sender' ? OWNER : null } });
    await assert.rejects(() => markLost(d)({ shipmentId, ...LOST }, ctx(ADMIN)),
      (e) => e.code === 'failed-precondition' && e.details.reason === 'custodian_not_provider', kind);
    assert.deepStrictEqual(Object.keys(db.dump('logistics_incidents')), []);
  }
});

ok('adminMarkShipmentLost: jo\'natma topilmadi — not-found; qiymat yozilmagan (eski hujjat) — declared_value_missing', async () => {
  const db = fresh(lostSeed());
  const d = deps(db);
  await assert.rejects(() => markLost(d)({ shipmentId: 'yoq', ...LOST }, ctx(ADMIN)), (e) => e.code === 'not-found');
  const { shipmentId } = await inTransitOneLeg(db, d);
  await db.collection('shipments').doc(shipmentId).update({ 'priceSnapshot.declaredValue': 0 });
  await assert.rejects(() => markLost(d)({ shipmentId, ...LOST }, ctx(ADMIN)),
    (e) => e.code === 'failed-precondition' && e.details.reason === 'declared_value_missing');
  assert.deepStrictEqual(Object.keys(db.dump('logistics_incidents')), []);
});

ok('adminMarkShipmentLost: kuryerning accountId\'si yo\'q — courier_account_missing (qarz yozib bo\'lmaydi, e\'lon qilinmaydi)', async () => {
  const db = fresh(lostSeed());
  const d = deps(db);
  const { shipmentId } = await inTransitOneLeg(db, d);
  await db.collection('users').doc(K1).update({ accountId: '' });
  await assert.rejects(() => markLost(d)({ shipmentId, ...LOST }, ctx(ADMIN)),
    (e) => e.code === 'failed-precondition' && e.details.reason === 'courier_account_missing');
  assert.strictEqual(db.dump('shipments')[shipmentId].status, 'in_transit');
});

ok('adminMarkShipmentLost: bitta LEG — jo\'natma lost/loss_pending, LEG disputed, hodisa, audit, ORDER problem', async () => {
  const db = fresh(lostSeed());
  const d = deps(db);
  const { shipmentId, orderId, legId } = await inTransitOneLeg(db, d);
  const custodyBefore = Object.keys(db.dump('custody_events')).length;
  const r = await markLost(d)({ shipmentId, ...LOST }, ctx(ADMIN));
  assert.deepStrictEqual(
    { ok: r.ok, idempotent: r.idempotent, status: r.status, paymentStatus: r.paymentStatus, goodsValue: r.goodsValue, legId: r.legId },
    { ok: true, idempotent: false, status: 'lost', paymentStatus: 'loss_pending', goodsValue: DECLARED_VALUE, legId });

  const s = db.dump('shipments')[shipmentId];
  assert.strictEqual(s.status, 'lost');
  assert.strictEqual(s.paymentStatus, 'loss_pending');
  assert.strictEqual(s.lostLegId, legId);
  assert.strictEqual(s.lossIncidentId, shipmentId);
  assert.ok(!('lostBy' in s), 'admin telefoni jo\'natmada (egasi/ijrochi o\'qiydi) turmaydi');
  assert.deepStrictEqual(s.currentCustodian.id, K1, 'custody yozuvi O\'ZGARMAYDI (15-band)');

  assert.strictEqual(db.dump('demands')[legId].status, 'disputed');
  assert.strictEqual(Object.keys(db.dump('custody_events')).length, custodyBefore, 'custody tarixiga tegilmaydi');

  const inc = db.dump('logistics_incidents')[shipmentId];
  assert.strictEqual(inc.type, 'lost');
  assert.strictEqual(inc.status, 'declared');
  assert.strictEqual(inc.goodsValue, DECLARED_VALUE);
  assert.strictEqual(inc.legId, legId);
  assert.strictEqual(inc.orderId, orderId);
  assert.deepStrictEqual(inc.courier, { uid: K1, accountId: `acc${K1}` });
  assert.deepStrictEqual(inc.customer, { uid: OWNER });
  assert.strictEqual(inc.declaredBy, ADMIN);
  assert.strictEqual(inc.reason, LOST.reason);
  assert.strictEqual(inc.note, LOST.note);
  assert.strictEqual(inc.refundedNow, null, 'pul hali hisoblanmagan');
  assert.strictEqual(inc.outstanding, null);
  assert.strictEqual(inc.paidTotal, 0);
  const ev = db.dump(`logistics_incidents/${shipmentId}/events`);
  assert.deepStrictEqual(Object.keys(ev), ['declared']);
  assert.strictEqual(ev.declared.amount, DECLARED_VALUE);

  const audit = db.dump('logistics_audit')[`lost_${shipmentId}`];
  assert.strictEqual(audit.kind, 'shipment_lost');
  assert.strictEqual(audit.by, ADMIN);
  assert.strictEqual(db.dump('logistics_orders')[orderId].status, 'problem');
  // Kuryerda qabul qiluvchi PII qolmaydi.
  const m = db.dump('demand_matches')[`${legId}_${K1}`];
  assert.ok(!m.contactUnlocked, 'contactUnlocked tozalangan');
});

ok('adminMarkShipmentLost: ikki LEG, yo\'qolgan 2-LEG — 1-LEG completed O\'ZGARMAYDI, custody hodisalari o\'zgarmaydi', async () => {
  const db = fresh(lostSeed());
  const d = deps(db);
  const { shipmentId, leg0, leg1 } = await inTransitTwoLegs(db, d);
  assert.strictEqual(db.dump('demands')[leg0].status, 'completed');
  const events = JSON.stringify(db.dump('custody_events'));
  const r = await markLost(d)({ shipmentId, ...LOST }, ctx(ADMIN));
  assert.strictEqual(r.legId, leg1);
  assert.strictEqual(db.dump('demands')[leg0].status, 'completed', 'oldingi ijrochi haqi saqlanadi');
  assert.strictEqual(db.dump('demands')[leg1].status, 'disputed');
  assert.strictEqual(JSON.stringify(db.dump('custody_events')), events);
  const inc = db.dump('logistics_incidents')[shipmentId];
  assert.deepStrictEqual(inc.courier, { uid: F1, accountId: `acc${F1}` }, 'jarima custodian (F1) ga, K1 ga emas');
  assert.strictEqual(inc.legIndex, 1);
});

ok('adminMarkShipmentLost: 1-LEG da yo\'qolsa keyingi LEG (draft/active/accepted) bekor qilinadi, matchlar yopiladi', async () => {
  const db = fresh(lostSeed());
  const d = deps(db);
  const r0 = await api.makeCreateLogisticsOrder(d)(orderPayload({
    destination: { regionId: 'toshkent_shahri', districtId: 'chilonzor', lat: 41.28, lng: 69.2, addressText: 'Chilonzor 9' },
    parcels: [{ actualWeightG: 5000, lengthCm: 50, widthCm: 40, heightCm: 40, declaredValue: DECLARED_VALUE }],
  }), ctx(OWNER));
  const shipmentId = r0.shipmentIds[0];
  await require('./helpers/logistics_harness').fund(db, shipmentId);
  const p = await api.makeAdminPlanShipmentRoute(d)({ shipmentId, reason: 'test', legs: ROUTE2 }, ctx(ADMIN));
  const [leg0, leg1] = p.legIds;
  await api.makeAcceptLeg(d)({ legId: leg0 }, ctx(K1));
  const sec = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(OWNER));
  await api.makeScanHandover(d)({ legId: leg0, code: sec.handoverCode, photoUrls: photoFor(K1) }, ctx(K1));
  assert.strictEqual(db.dump('demands')[leg1].status, 'active', 'keyingi LEG ochilgan');
  assert.ok(db.dump('demand_matches')[`${leg1}_${F1}`]);

  await markLost(d)({ shipmentId, ...LOST }, ctx(ADMIN));
  assert.strictEqual(db.dump('demands')[leg0].status, 'disputed');
  assert.strictEqual(db.dump('demands')[leg1].status, 'cancelled');
  assert.strictEqual(db.dump('demands')[leg1].cancelledBy, 'lost');
  assert.strictEqual(db.dump('demand_matches')[`${leg1}_${F1}`].status, 'cancelled');
});

ok('adminMarkShipmentLost: disputed jo\'natma + escrow_frozen (nizo) — ruxsat', async () => {
  const db = fresh(lostSeed());
  const d = deps(db);
  const { shipmentId } = await inTransitOneLeg(db, d);
  await db.collection('shipments').doc(shipmentId).update({ status: 'disputed', paymentStatus: 'escrow_frozen' });
  const r = await markLost(d)({ shipmentId, ...LOST }, ctx(ADMIN));
  assert.strictEqual(r.status, 'lost');
  assert.strictEqual(db.dump('shipments')[shipmentId].paymentStatus, 'loss_pending');
});

ok('adminMarkShipmentLost: IDEMPOTENT — qayta chaqiruv (shu opId ham, boshqa opId ham) yozmaydi, bitta incident', async () => {
  const db = fresh(lostSeed());
  const d = deps(db);
  const { shipmentId } = await inTransitOneLeg(db, d);
  const first = await markLost(d)({ shipmentId, ...LOST }, ctx(ADMIN));
  assert.strictEqual(first.idempotent, false);
  const writes = db.writes;
  const again = await markLost(d)({ shipmentId, ...LOST }, ctx(ADMIN));
  const other = await markLost(d)({ shipmentId, ...LOST, opId: 'lost-op-0002', reason: 'boshqa sabab' }, ctx(SUPER));
  for (const r of [again, other]) {
    assert.strictEqual(r.idempotent, true);
    assert.strictEqual(r.goodsValue, DECLARED_VALUE);
    assert.strictEqual(r.paymentStatus, 'loss_pending');
  }
  assert.strictEqual(db.writes, writes, 'qayta chaqiruv hech narsa yozmaydi');
  assert.strictEqual(Object.keys(db.dump('logistics_incidents')).length, 1);
  assert.strictEqual(db.dump('logistics_incidents')[shipmentId].reason, LOST.reason, 'birinchi sabab saqlanadi (o\'zgarmas)');
});

ok('yo\'qolgandan keyin: kuryer yetkazib bera olmaydi, keyingi LEG olinmaydi, sweeper tegmaydi', async () => {
  const db = fresh(lostSeed());
  const d = deps(db);
  const { shipmentId, legId, sec } = await inTransitOneLeg(db, d);
  await markLost(d)({ shipmentId, ...LOST }, ctx(ADMIN));
  await assert.rejects(
    () => api.makeConfirmDelivery(d)({ legId, deliveryCode: L.deliveryCodeFor(shipmentId, 'x'), photoUrls: photoFor(K1) }, ctx(K1)),
    (e) => e.code === 'failed-precondition' && e.details.reason === 'leg_not_in_progress');
  const writes = db.writes;
  const sweep = await api.makeLegChainSweeper(d)();
  assert.strictEqual(sweep.opened, 0);
  assert.strictEqual(db.writes, writes);
  void sec;
});

// ═══════════════════════════════════════════════════════════════════════
(async () => {
  for (const t of tests) {
    try { await t.fn(); passed += 1; console.log(`  OK  ${t.name}`); } catch (e) {
      console.error(`  XATO ${t.name}\n       ${e.stack || e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
void ADMIN;
