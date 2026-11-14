/**
 * AVA Logistics — ICHKI jo'natma (Ulgurji) zanjiri + NAQD yetkazish haqi, FakeFirestore.
 *
 *   node functions_demand/test/logistics_internal_chain.test.js
 *
 * S7 (ega «улаш керак бўлса ула», 2026-11-13) va S5 (ega CONFIRMED 2026-11-14, rad: 2026-11-14).
 * Qulflanadi:
 *   - Ulgurji lineage shartnomasi: quoteParcelForPoints / createShipmentInternal /
 *     prepareCancelUnpaidShipmentInTx / buildRoute / buildLegDemand / validateParcel eksportlari;
 *   - createShipmentInternal `sequential` → bugungidek 1 LEG; `assemble_all` → createLogisticsOrder
 *     bilan AYNI zanjir (transfer nuqtalari), narx QAYTA HISOBLANMAYDI, idempotentlik + poyga;
 *   - Ulgurji zanjiri muddati: `wholesale_refund_pending` (sotuvchi hamyoniga refund YO'Q),
 *     o'zgarmas hodisa, sotuvchiga «hamyonga qaytadi» xabari YO'Q;
 *   - qaytish jo'natmasi (wholesale_return naqshi) relay zanjir kodi bilan ishlaydi;
 *   - NAQD: ochish, LEG/taklifda `cashToCollect`, custody, tasdiqsiz yetkazish yo'q,
 *     yig'uvchi EARNED'i 0 (naqdda qoladi), ko'p LEG, muddat, bekor qilish, qayta rejalash;
 *   - NAQD RAD: summa serverda (yetkazish + qaytish), o'zgarmas qayd, idempotent / ziddiyat;
 *   - Ulgurji LEG'ini sotuvchi `cancelDemand` bilan bekor qila olmaydi.
 */
const assert = require('assert');
const api = require('../api/logistics');
const offersApi = require('../api/offers');
const adapter = require('../adapters/logistics');
const tariffCore = require('../core/tariff');
const config = require('../core/config');
const L = require('../core/logistics');
const sm = require('../core/state_machine');
const {
  OWNER, K1, F1, ADMIN, NOW, ctx, makeDb, seed, deps, photoFor,
} = require('./helpers/logistics_harness');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const SELLER = OWNER;
const BUYER = '998905556677';
const H48 = 48 * 3600 * 1000;
const at = (ms) => new Date(NOW.getTime() + ms);

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
const chainSeed = (extra = {}) => seed({
  'module_config/logistics_all': CHAIN_CFG,
  'geo_districts/yunusobod': { regionId: 'toshkent_shahri' },
  ...extra,
});
function fresh(seedDocs) {
  const db = makeDb(seedDocs || chainSeed());
  config.clearCache(); tariffCore.clearCache();
  return db;
}

const ORIGIN = { regionId: 'xorazm', districtId: 'gurlan', lat: 41.84, lng: 60.39, addressText: 'Gurlan, Sotuvchi ombori' };
const DEST_FAR = { regionId: 'toshkent_shahri', districtId: 'chilonzor', lat: 41.28, lng: 69.2, addressText: 'Chilonzor 9' };
const DEST_NEAR = { regionId: 'xorazm', districtId: 'gurlan', lat: 41.85, lng: 60.40, addressText: 'Gurlan, Xaridor' };
const PARCEL = { actualWeightG: 5000, declaredValue: 150000 };

/** Ulgurji `shipmentInputFromOrder` bilan AYNI shakl (muhr kvotadan). */
async function wholesaleInput(db, over = {}) {
  const dest = over.destination || DEST_FAR;
  const rq = await api.quoteParcelForPoints(db, ORIGIN, dest, PARCEL, { dimsOptional: true });
  return {
    idempotencyKey: 'wholesale_ship_WO1',
    ownerId: SELLER,
    recipientId: BUYER,
    recipient: { name: 'Xaridor' },
    origin: rq.origin,
    destination: rq.destination,
    parcel: {
      actualWeightG: PARCEL.actualWeightG, lengthCm: null, widthCm: null, heightCm: null,
      declaredValue: PARCEL.declaredValue, description: 'Un (50 kg) × 1', fragile: false,
    },
    priceSnapshot: rq.quote,
    pricedAt: NOW,
    source: 'wholesale',
    extra: { wholesaleOrderId: 'WO1' },
    ...over,
  };
}
const shipOf = (db, id) => db.dump('shipments')[id];
const legDoc = (db, id) => db.dump('demands')[id];
const reason = (code) => (e) => (e.details || {}).reason === code;
const accept = (db, legId, p, now) => api.makeAcceptLeg(deps(db, now))({ legId }, ctx(p));
async function fundEscrow(db, shipmentId) {
  const ref = db.collection('shipments').doc(shipmentId);
  const before = (await ref.get()).data();
  await ref.update({ paymentStatus: 'escrow_funded', status: 'ready', fundedAt: NOW });
  return api.makeOnShipmentFunded(deps(db))(before, (await ref.get()).data(), shipmentId);
}
const secretOf = (db, shipmentId) => db.docs.get(`shipments/${shipmentId}/private/secrets`).qrSecret;
const hcode = (db, s) => L.handoverCodeFor(s, secretOf(db, s));
const dcode = (db, s) => L.deliveryCodeFor(s, secretOf(db, s));

/** Qulflangan 3 LEG zanjir: K1 → LEG-1, F1 → LEG-2, LEG-3. */
async function lockAll(db, legIds) {
  await accept(db, legIds[1], F1);
  await accept(db, legIds[2], F1);
  await accept(db, legIds[0], K1);
}
/** Posilka oxirgi LEG kuryeri (F1) qo'lida: LEG-1, LEG-2, LEG-3 pickup'lar. */
async function carryToLastLeg(db, shipmentId, legIds) {
  const scan = api.makeScanHandover(deps(db));
  await scan({ legId: legIds[0], code: hcode(db, shipmentId), photoUrls: photoFor(K1) }, ctx(K1));
  await scan({ legId: legIds[1], code: hcode(db, shipmentId), photoUrls: photoFor(F1) }, ctx(F1));
  await scan({ legId: legIds[2], code: hcode(db, shipmentId), photoUrls: photoFor(F1) }, ctx(F1));
}

// ═══════════════════════════════════════════════════════════════════════
// SHARTNOMA
// ═══════════════════════════════════════════════════════════════════════
ok('shartnoma: Ulgurji import qiladigan eksportlar bor (wholesale_orders.js + wholesale_return.js)', () => {
  for (const k of ['quoteParcelForPoints', 'createShipmentInternal', 'prepareCancelUnpaidShipmentInTx',
    'buildRoute', 'buildLegDemand', 'validateParcel', 'openCashShipment', 'quoteCashRefusalDue',
    'recordCashRefusal', 'closeShipmentMatches']) {
    assert.strictEqual(typeof api[k], 'function', k);
  }
  assert.strictEqual(api.CONFIG_REGION, 'all');
});

ok('quoteParcelForPoints: o\'lchamsiz (dimsOptional) — hajmiy vazn 0; qisman o\'lcham — rad; bayroqsiz — rad', async () => {
  const db = fresh();
  const r = await api.quoteParcelForPoints(db, ORIGIN, DEST_FAR, PARCEL, { dimsOptional: true });
  assert.deepStrictEqual(Object.keys(r).sort(), ['destination', 'origin', 'quote', 'tariff']);
  assert.strictEqual(r.quote.volumetricWeightG, 0);
  assert.strictEqual(r.quote.chargeableWeightG, 5000);
  assert.strictEqual(r.quote.customerPrice, 100000, 'Xorazm → Toshkent, 5 kg (fixture tarif)');
  await assert.rejects(() => api.quoteParcelForPoints(db, ORIGIN, DEST_FAR, PARCEL), reason('bad_dimensions'));
  await assert.rejects(() => api.quoteParcelForPoints(db, ORIGIN, DEST_FAR, { ...PARCEL, lengthCm: 10 }, { dimsOptional: true }),
    reason('bad_dimensions'));
  assert.throws(() => api.validateParcel({ ...PARCEL, lengthCm: 10 }, 0, { dimsOptional: true }), reason('parcel_invalid'));
  assert.strictEqual(api.validateParcel(PARCEL, 0, { dimsOptional: true }).lengthCm, null);
});

// ═══════════════════════════════════════════════════════════════════════
// S7: ZANJIR
// ═══════════════════════════════════════════════════════════════════════
ok('sequential (standart konfig): 1 to\'g\'ridan-to\'g\'ri LEG, `chain` yo\'q, shakl Ulgurji lineage bilan bir xil', async () => {
  const db = fresh(seed());
  const r = await api.createShipmentInternal(deps(db), await wholesaleInput(db));
  assert.deepStrictEqual(Object.keys(r).sort(),
    ['chainMode', 'deliveryPaymentMethod', 'duplicate', 'legCount', 'orderId', 'shipmentId', 'trackingNumber']);
  assert.strictEqual(r.duplicate, false);
  assert.strictEqual(r.legCount, 1);
  assert.strictEqual(r.chainMode, 'sequential');
  const ship = shipOf(db, r.shipmentId);
  assert.strictEqual(ship.chain, undefined);
  assert.strictEqual(ship.deliveryPayment, undefined, 'eskrou jo\'natmada maydon yo\'q');
  assert.strictEqual(ship.ownerId, SELLER);
  assert.strictEqual(ship.recipientId, BUYER);
  assert.strictEqual(ship.source, 'wholesale');
  assert.strictEqual(ship.wholesaleOrderId, 'WO1');
  assert.strictEqual(ship.status, 'awaiting_payment');
  assert.strictEqual(ship.paymentStatus, 'pending');
  const leg = legDoc(db, ship.legIds[0]);
  assert.strictEqual(leg.attributes.legKind, 'direct');
  assert.strictEqual(leg.attributes.wholesaleOrderId, 'WO1');
  assert.strictEqual(leg.attributes.chainMode, undefined);
  assert.strictEqual(leg.payment.kind, 'escrow');
  assert.strictEqual(leg.location.districtId, 'gurlan', 'LEG-1 olish — sotuvchida');
  assert.strictEqual(leg.destination.districtId, 'chilonzor', 'oxirgi LEG — xaridorga');
  const order = db.dump('logistics_orders')[r.orderId];
  assert.deepStrictEqual(order.recipient, { name: 'Xaridor', phone: BUYER });
  assert.strictEqual(order.wholesaleOrderId, 'WO1');
});

ok('assemble_all: Gurlan → Chilonzor = 3 LEG (createLogisticsOrder bilan AYNI), narx muhrdan (qayta hisoblanmaydi)', async () => {
  const db = fresh();
  const input = await wholesaleInput(db);
  // Muhr bugungi tarifdan farq qiladi — server uni QAYTA HISOBLAMAYDI (D-8).
  input.priceSnapshot = { ...input.priceSnapshot, customerPrice: 200000 };
  const r = await api.createShipmentInternal(deps(db), input);
  assert.strictEqual(r.legCount, 3);
  assert.strictEqual(r.chainMode, 'assemble_all');
  const ship = shipOf(db, r.shipmentId);
  assert.strictEqual(ship.priceSnapshot.customerPrice, 200000);
  assert.deepStrictEqual(ship.chain, {
    mode: 'assemble_all', state: 'assembling', deadlineAt: null, lockedAt: null, claimed: 0, legCount: 3,
    selfTransferLegIds: [],
  });
  const legs = ship.legIds.map((id) => legDoc(db, id));
  assert.deepStrictEqual(legs.map((l) => l.location.districtId), ['gurlan', 'urganch_shahri', 'yunusobod']);
  assert.deepStrictEqual(legs.map((l) => l.destination.districtId), ['urganch_shahri', 'yunusobod', 'chilonzor']);
  assert.ok(legs.every((l) => l.attributes.chainMode === 'assemble_all' && l.attributes.wholesaleOrderId === 'WO1'));
  const internal = db.docs.get(`shipments/${r.shipmentId}/private/internal`);
  assert.strictEqual(internal.platformShare + internal.providerPool, 200000, 'ulush muhrlangan narxdan');
  assert.strictEqual(internal.legPayouts.reduce((s, p) => s + p.amount, 0), internal.providerPool);
  assert.ok(legs.every((l, i) => Number.isInteger(l.attributes.payout) && l.attributes.payout === internal.legPayouts[i].amount));
});

ok('idempotentlik: takror → duplicate (AYNI id), parallel 3 chaqiruv → BITTA jo\'natma', async () => {
  const db = fresh();
  const input = await wholesaleInput(db);
  const [a, b, c] = await Promise.all([1, 2, 3].map(() => api.createShipmentInternal(deps(db), input)));
  const ids = new Set([a.shipmentId, b.shipmentId, c.shipmentId]);
  assert.strictEqual(ids.size, 1);
  assert.strictEqual([a, b, c].filter((x) => !x.duplicate).length, 1, 'faqat bitta g\'olib');
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 1);
  assert.strictEqual(Object.keys(db.dump('logistics_orders')).length, 1);
  const d = await api.createShipmentInternal(deps(db), input);
  assert.strictEqual(d.duplicate, true);
  assert.strictEqual(d.shipmentId, a.shipmentId);
  assert.strictEqual(d.legCount, 3);
  assert.strictEqual(d.chainMode, 'assemble_all');
  assert.strictEqual(Object.keys(db.dump('demands')).length, 3, 'LEG\'lar ikkilanmadi');
});

ok('salbiy: kalit / egasi=qabul qiluvchi / muhr mos emas / tarif versiyasi yo\'q / to\'lov usuli', async () => {
  const db = fresh();
  const base = await wholesaleInput(db);
  const c = (over) => api.createShipmentInternal(deps(db), { ...base, ...over });
  await assert.rejects(() => c({ idempotencyKey: 'short' }), reason('idempotency_key'));
  await assert.rejects(() => c({ recipientId: SELLER }), reason('recipient_is_owner'));
  await assert.rejects(() => c({ parcel: { ...base.parcel, actualWeightG: 4999 } }), reason('price_snapshot_mismatch'));
  await assert.rejects(() => c({ priceSnapshot: { ...base.priceSnapshot, tariffVersion: 99 } }), reason('tariff_version_missing'));
  await assert.rejects(() => c({ priceSnapshot: { ...base.priceSnapshot, customerPrice: 0 } }), reason('price_snapshot_invalid'));
  await assert.rejects(() => c({ deliveryPaymentMethod: 'card' }), reason('delivery_payment_method'));
  await assert.rejects(() => c({ source: 'X' }), reason('source_required'));
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 0, 'hech narsa yozilmadi');
});

ok('Ulgurji eskrou zanjiri to\'liq: to\'lov → hammasi ochiq → qulf → sotuvchidan olish → xaridorga kod bilan', async () => {
  const db = fresh();
  const r = await api.createShipmentInternal(deps(db), await wholesaleInput(db));
  const { legIds } = shipOf(db, r.shipmentId);
  const f = await fundEscrow(db, r.shipmentId);
  assert.strictEqual(f.activated, 3);
  await lockAll(db, legIds);
  assert.strictEqual(shipOf(db, r.shipmentId).chain.state, 'locked');
  const m1 = db.dump('demand_matches')[`${legIds[0]}_${K1}`];
  assert.strictEqual(m1.contactUnlocked.ownerPhone, SELLER, 'LEG-1 olish kontakti — sotuvchi');
  const sec = await api.makeGetShipmentSecrets(deps(db))({ shipmentId: r.shipmentId }, ctx(SELLER));
  assert.strictEqual(sec.deliveryCode, undefined, 'sotuvchi yetkazish kodini OLMAYDI');
  await carryToLastLeg(db, r.shipmentId, legIds);
  const m3 = db.dump('demand_matches')[`${legIds[2]}_${F1}`];
  assert.strictEqual(m3.contactUnlocked.recipientPhone, BUYER, 'oxirgi LEG — xaridor telefoni');
  const c = await api.makeConfirmDelivery(deps(db))({ legId: legIds[2], deliveryCode: dcode(db, r.shipmentId), photoUrls: photoFor(F1) }, ctx(F1));
  assert.strictEqual(c.shipmentStatus, 'delivered');
  assert.strictEqual(c.cashCollected, undefined);
  const ev = db.dump('custody_events')[c.eventId];
  assert.strictEqual(ev.completedLegPayout, legDoc(db, legIds[2]).attributes.payout, 'eskrou: EARNED odatdagidek');
  assert.strictEqual(ev.cashCollected, undefined);
});

ok('Ulgurji zanjiri 48 soatda yig\'ilmadi: wholesale_refund_pending (refund_pending EMAS), hodisa, sotuvchiga xabar YO\'Q', async () => {
  const db = fresh();
  const r = await api.createShipmentInternal(deps(db), await wholesaleInput(db));
  const { legIds } = shipOf(db, r.shipmentId);
  await fundEscrow(db, r.shipmentId);
  await accept(db, legIds[0], K1);
  const sw = await api.makeLegChainSweeper(deps(db, at(H48 + 60000)))();
  assert.strictEqual(sw.chainExpired, 1);
  const ship = shipOf(db, r.shipmentId);
  assert.strictEqual(ship.status, 'cancelled');
  assert.strictEqual(ship.chain.state, 'expired');
  assert.ok(ship.chain.expiredAt instanceof Date);
  assert.strictEqual(ship.paymentStatus, 'wholesale_refund_pending', 'sotuvchi hamyoniga refund YO\'Q');
  assert.ok(L.canTransitionPayment('wholesale_refund_pending', 'refunded'), 'Ulgurji tomoni yopadi');
  assert.ok(!L.canTransitionPayment('wholesale_refund_pending', 'refund_pending'));
  const ev = db.dump('logistics_audit')[`chain_expired_${r.shipmentId}`];
  assert.strictEqual(ev.wholesaleOrderId, 'WO1');
  assert.strictEqual(ev.refundTarget, 'wholesale');
  assert.strictEqual(ev.refundPending, false);
  assert.strictEqual(ev.paymentStatusAfter, 'wholesale_refund_pending');
  assert.strictEqual(ev.deliveryPaymentMethod, 'escrow');
  const news = db.dump('admin_news');
  assert.ok(!news[`chainExpired_${r.shipmentId}_${SELLER}`], 'sotuvchiga «hamyonga qaytadi» xabari yo\'q');
  assert.ok(news[`chainExpired_${r.shipmentId}_${K1}`], 'LEG olgan kuryerga xabar');
  assert.ok(legIds.every((id) => legDoc(db, id).status === 'cancelled'));
});

ok('qaytish jo\'natmasi (wholesale_return naqshi): biriktirilgan LEG-1 + eksportlar → olish → sotuvchiga topshirish', async () => {
  const db = fresh(seed());
  const COURIER = K1;
  // `wholesale_return.createReturnShipment` AYNI qadamlari (eksport qilingan relay yordamchilari ustida).
  const rq = await api.quoteParcelForPoints(db, DEST_NEAR, ORIGIN, PARCEL, { dimsOptional: true });
  const parcel = api.validateParcel({ ...PARCEL, description: 'Qaytarish' }, 0, { dimsOptional: true });
  const t = rq.tariff;
  const shipmentRef = db.collection('shipments').doc('RET1');
  const legRef = db.collection('demands').doc('RLEG1');
  const order = { id: 'RORD1', ownerId: SELLER, termsAcceptedAt: null };
  const shipment = {
    orderId: order.id, ownerId: SELLER, trackingNumber: 'AVA-T-RET', status: 'awaiting_payment', paymentStatus: 'pending',
    origin: rq.origin, destination: rq.destination, recipientName: '', parcel, priceSnapshot: { ...rq.quote, calculatedAt: NOW },
    currentCustodian: { kind: 'sender', id: SELLER, since: NOW }, currentLegId: null, routePlanVersion: 1,
    legIds: ['RLEG1'], legCount: 1, assignedProviderIds: [COURIER], custodyCount: 0, createdAt: NOW, updatedAt: NOW,
    recipientId: SELLER, source: 'wholesale_return', wholesaleOrderId: 'WO1', wholesaleReturn: true,
    legAssignments: { RLEG1: COURIER },
  };
  const route = api.buildRoute({ tariff: t, shipment, version: 1, points: [{ from: rq.origin, to: rq.destination }] });
  const leg = api.buildLegDemand({
    ownerId: SELLER, order, shipment, shipmentId: 'RET1', leg: route.legs[0], legIndex: 0, legCount: 1,
    legIds: ['RLEG1'], adapter, now: NOW, ttlMinutes: 60,
  });
  leg.status = sm.STATUS.ACCEPTED;
  leg.assignment = { providerId: COURIER, offerId: null, acceptedAt: NOW };
  await shipmentRef.set(shipment);
  await shipmentRef.collection('private').doc('secrets').set({ qrSecret: 'ret-secret', createdAt: NOW });
  await legRef.set(leg);
  await db.collection('demand_matches').doc(`RLEG1_${COURIER}`).set({ demandId: 'RLEG1', providerId: COURIER, status: 'accepted' });
  await db.collection('logistics_orders').doc('RORD1').set({ ownerId: SELLER, recipient: { name: '', phone: SELLER } });
  assert.strictEqual(leg.attributes.wholesaleOrderId, 'WO1');
  const f = await fundEscrow(db, 'RET1');
  assert.strictEqual(f.skipped, 'status_accepted', 'biriktirilgan LEG\'ga matching ishlamaydi');
  // Kuryer o'zi custodian emas (sotuvchi kodi — getWholesaleReturnHandoverCode; testda hosila).
  const scan = await api.makeScanHandover(deps(db))({ legId: 'RLEG1', code: L.handoverCodeFor('RET1', 'ret-secret'), photoUrls: photoFor(COURIER) }, ctx(COURIER));
  assert.strictEqual(scan.legStatus, 'in_progress');
  const sec = await api.makeGetShipmentSecrets(deps(db))({ shipmentId: 'RET1' }, ctx(SELLER));
  assert.ok(sec.deliveryCode, 'qaytishda egasi = qabul qiluvchi — kod sotuvchida');
  const c = await api.makeConfirmDelivery(deps(db))({ legId: 'RLEG1', deliveryCode: sec.deliveryCode, photoUrls: photoFor(COURIER) }, ctx(COURIER));
  assert.strictEqual(c.shipmentStatus, 'delivered');
  assert.strictEqual(db.dump('custody_events')[c.eventId].completedLegPayout, route.legs[0].payout);
});

ok('Ulgurji LEG\'ini sotuvchi `cancelDemand` bilan bekor qila olmaydi (jonli himoya ko\'chirildi); oddiy talab — o\'zgarmagan', async () => {
  const db = fresh(seed());
  const r = await api.createShipmentInternal(deps(db), await wholesaleInput(db));
  const legId = shipOf(db, r.shipmentId).legIds[0];
  const cancel = offersApi.makeCancelDemand({ db, now: () => NOW });
  await assert.rejects(() => cancel({ demandId: legId }, ctx(SELLER)), reason('wholesale_managed'));
  assert.strictEqual(legDoc(db, legId).status, 'draft');
  await db.collection('demands').doc('PLAIN1').set({ ownerId: SELLER, module: 'repair', status: 'active' });
  const ok2 = await cancel({ demandId: 'PLAIN1' }, ctx(SELLER));
  assert.ok(ok2);
  assert.strictEqual(legDoc(db, 'PLAIN1').status, 'cancelled');
});

// ═══════════════════════════════════════════════════════════════════════
// S5: NAQD
// ═══════════════════════════════════════════════════════════════════════
ok('naqd, 1 LEG: deliveryPayment, LEG/taklifda cashToCollect, ochish → active; tasdiqsiz yetkazish YO\'Q; yig\'uvchi EARNED 0', async () => {
  const db = fresh(seed());
  const r = await api.createShipmentInternal(deps(db), await wholesaleInput(db, { destination: DEST_NEAR, deliveryPaymentMethod: 'cash' }));
  assert.strictEqual(r.deliveryPaymentMethod, 'cash');
  let ship = shipOf(db, r.shipmentId);
  const legId = ship.legIds[0];
  const price = ship.priceSnapshot.customerPrice;
  assert.deepStrictEqual(ship.deliveryPayment, {
    method: 'cash', amount: price, currency: 'UZS', status: 'pending', collectedBy: null, collectedAt: null,
    collectorLegId: legId, collectorLegPayout: legDoc(db, legId).attributes.payout,
  });
  const leg = legDoc(db, legId);
  assert.strictEqual(leg.attributes.cashToCollect, price);
  assert.strictEqual(leg.attributes.deliveryPaymentMethod, 'cash');
  assert.strictEqual(leg.payment.kind, 'cash');
  const proj = adapter.buildProjection({ id: legId, ...leg }, {});
  assert.strictEqual(proj.attributes.cashToCollect, price, 'kuryer olishdan oldin summani ko\'radi');
  // Ochilmagan naqd jo'natmada custody yo'q.
  const o = await api.openCashShipment(deps(db), r.shipmentId);
  assert.strictEqual(o.opened, true);
  assert.strictEqual(o.activation.activated, true);
  ship = shipOf(db, r.shipmentId);
  assert.strictEqual(ship.status, 'ready');
  assert.strictEqual(ship.paymentStatus, 'cash_on_delivery');
  assert.strictEqual(legDoc(db, legId).status, 'active');
  const again = await api.openCashShipment(deps(db), r.shipmentId);
  assert.strictEqual(again.opened, false, 'takror ochish — idempotent');
  await accept(db, legId, K1);
  await api.makeScanHandover(deps(db))({ legId, code: hcode(db, r.shipmentId), photoUrls: photoFor(K1) }, ctx(K1));
  const confirm = api.makeConfirmDelivery(deps(db));
  await assert.rejects(() => confirm({ legId, deliveryCode: dcode(db, r.shipmentId), photoUrls: photoFor(K1) }, ctx(K1)),
    (e) => reason('cash_confirmation_required')(e) && e.details.cashToCollect === price);
  assert.strictEqual(shipOf(db, r.shipmentId).status, 'in_transit', 'tasdiqsiz — yetkazilmadi');
  const c = await confirm({ legId, deliveryCode: dcode(db, r.shipmentId), photoUrls: photoFor(K1), cashCollected: true }, ctx(K1));
  assert.strictEqual(c.cashCollected, price);
  ship = shipOf(db, r.shipmentId);
  assert.strictEqual(ship.status, 'delivered');
  assert.strictEqual(ship.paymentStatus, 'cash_on_delivery', 'pulni relay_cash yopadi (settled)');
  assert.strictEqual(ship.deliveryPayment.status, 'collected');
  assert.strictEqual(ship.deliveryPayment.collectedBy, K1);
  const ev = db.dump('custody_events')[c.eventId];
  assert.strictEqual(ev.completedLegPayout, 0, 'yig\'uvchi haqi naqdda — EARNED yo\'q (ikki marta to\'lanmaydi)');
  assert.deepStrictEqual(ev.cashCollected, { amount: price, collectorId: K1, collectorLegPayout: leg.attributes.payout });
  // Takror — idempotent, ikkinchi hodisa yo'q.
  const c2 = await confirm({ legId, deliveryCode: dcode(db, r.shipmentId), photoUrls: photoFor(K1), cashCollected: true }, ctx(K1));
  assert.strictEqual(c2.idempotent, true);
});

ok('naqd, ko\'p LEG zanjir: faqat oxirgi LEG naqd oladi; oldingi LEG EARNED odatdagidek; oraliq kuryer yetkaza olmaydi', async () => {
  const db = fresh();
  const r = await api.createShipmentInternal(deps(db), await wholesaleInput(db, { deliveryPaymentMethod: 'cash' }));
  const ship0 = shipOf(db, r.shipmentId);
  const { legIds } = ship0;
  const PRICE = ship0.priceSnapshot.customerPrice;
  const pays = db.docs.get(`shipments/${r.shipmentId}/private/internal`).legPayouts.map((p) => p.amount);
  assert.deepStrictEqual(legIds.map((id) => legDoc(db, id).attributes.cashToCollect), [0, 0, PRICE]);
  assert.strictEqual(ship0.deliveryPayment.collectorLegId, legIds[2]);
  assert.strictEqual(ship0.deliveryPayment.collectorLegPayout, pays[2]);
  const o = await api.openCashShipment(deps(db), r.shipmentId);
  assert.strictEqual(o.activation.activated, 3);
  assert.strictEqual(shipOf(db, r.shipmentId).chain.deadlineAt.getTime(), NOW.getTime() + H48, 'muddat ochilgan paytdan');
  await lockAll(db, legIds);
  await carryToLastLeg(db, r.shipmentId, legIds);
  const evs = Object.values(db.dump('custody_events'));
  const leg1Done = evs.find((e) => e.completesLegId === legIds[0]);
  assert.strictEqual(leg1Done.completedLegPayout, pays[0], 'LEG-1 EARNED (relay_escrow) — o\'zgarmagan');
  const c = await api.makeConfirmDelivery(deps(db))({
    legId: legIds[2], deliveryCode: dcode(db, r.shipmentId), photoUrls: photoFor(F1), cashCollected: true,
  }, ctx(F1));
  assert.strictEqual(c.cashCollected, PRICE);
  assert.strictEqual(db.dump('custody_events')[c.eventId].completedLegPayout, 0);
  assert.strictEqual(shipOf(db, r.shipmentId).deliveryPayment.collectedBy, F1);
});

ok('naqd zanjir muddati: bekor, pul holati O\'ZGARMAYDI (eskrou yo\'q), hodisada method=cash', async () => {
  const db = fresh();
  const r = await api.createShipmentInternal(deps(db), await wholesaleInput(db, { deliveryPaymentMethod: 'cash' }));
  await api.openCashShipment(deps(db), r.shipmentId);
  await accept(db, shipOf(db, r.shipmentId).legIds[0], K1);
  const sw = await api.makeLegChainSweeper(deps(db, at(H48 + 1000)))();
  assert.strictEqual(sw.chainExpired, 1);
  const ship = shipOf(db, r.shipmentId);
  assert.strictEqual(ship.status, 'cancelled');
  assert.strictEqual(ship.chain.state, 'expired');
  assert.strictEqual(ship.paymentStatus, 'cash_on_delivery');
  const ev = db.dump('logistics_audit')[`chain_expired_${r.shipmentId}`];
  assert.strictEqual(ev.deliveryPaymentMethod, 'cash');
  assert.strictEqual(ev.refundTarget, null);
});

ok('openCashShipment salbiy: eskrou jo\'natma — not_cash_shipment; bekor qilingan — not_payable', async () => {
  const db = fresh(seed());
  const e = await api.createShipmentInternal(deps(db), await wholesaleInput(db));
  await assert.rejects(() => api.openCashShipment(deps(db), e.shipmentId), reason('not_cash_shipment'));
  const c = await api.createShipmentInternal(deps(db), await wholesaleInput(db, { idempotencyKey: 'wholesale_ship_WO2', deliveryPaymentMethod: 'cash' }));
  await db.runTransaction(async (tx) => {
    const cm = await api.prepareCancelUnpaidShipmentInTx(tx, db, c.shipmentId);
    cm(NOW, 'wholesale_order_cancelled');
  });
  await assert.rejects(() => api.openCashShipment(deps(db), c.shipmentId), reason('not_payable'));
});

ok('prepareCancelUnpaidShipmentInTx: naqd ochilgan, custody yo\'q → bekor (zanjir cancelled, LEG\'lar); olingandan keyin → null', async () => {
  const db = fresh();
  const r = await api.createShipmentInternal(deps(db), await wholesaleInput(db, { deliveryPaymentMethod: 'cash' }));
  await api.openCashShipment(deps(db), r.shipmentId);
  const { legIds } = shipOf(db, r.shipmentId);
  await accept(db, legIds[0], K1);
  await db.runTransaction(async (tx) => {
    const cm = await api.prepareCancelUnpaidShipmentInTx(tx, db, r.shipmentId);
    assert.ok(cm);
    cm(NOW, 'wholesale_order_cancelled');
  });
  const ship = shipOf(db, r.shipmentId);
  assert.strictEqual(ship.status, 'cancelled');
  assert.strictEqual(ship.chain.state, 'cancelled');
  assert.ok(legIds.every((id) => legDoc(db, id).status === 'cancelled'));
  await api.closeShipmentMatches(db, r.shipmentId, NOW);
  assert.strictEqual(db.dump('demand_matches')[`${legIds[0]}_${K1}`].status, 'cancelled');
  // Custody boshlangan naqd jo'natma — bekor qilib bo'lmaydi.
  const db2 = fresh(seed());
  const s = await api.createShipmentInternal(deps(db2), await wholesaleInput(db2, { destination: DEST_NEAR, deliveryPaymentMethod: 'cash' }));
  await api.openCashShipment(deps(db2), s.shipmentId);
  const l2 = shipOf(db2, s.shipmentId).legIds[0];
  await accept(db2, l2, K1);
  await api.makeScanHandover(deps(db2))({ legId: l2, code: hcode(db2, s.shipmentId), photoUrls: photoFor(K1) }, ctx(K1));
  const none = await db2.runTransaction((tx) => api.prepareCancelUnpaidShipmentInTx(tx, db2, s.shipmentId));
  assert.strictEqual(none, null);
});

ok('naqd + admin qayta rejalash: yig\'uvchi yangi oxirgi LEG, cashToCollect faqat unda', async () => {
  const db = fresh(seed());
  const r = await api.createShipmentInternal(deps(db), await wholesaleInput(db, { deliveryPaymentMethod: 'cash' }));
  await api.openCashShipment(deps(db), r.shipmentId);
  const out = await api.makeAdminPlanShipmentRoute(deps(db))({
    shipmentId: r.shipmentId,
    reason: 'test',
    legs: [{ from: ORIGIN, to: { regionId: 'xorazm', districtId: 'urganch_shahri' } }, { from: { regionId: 'xorazm', districtId: 'urganch_shahri' }, to: DEST_FAR }],
  }, ctx(ADMIN));
  assert.strictEqual(out.legCount, 2);
  const ship = shipOf(db, r.shipmentId);
  assert.strictEqual(ship.deliveryPayment.collectorLegId, out.legIds[1]);
  assert.strictEqual(ship.deliveryPayment.collectorLegPayout, legDoc(db, out.legIds[1]).attributes.payout);
  assert.deepStrictEqual(out.legIds.map((id) => legDoc(db, id).attributes.cashToCollect), [0, ship.priceSnapshot.customerPrice]);
  assert.strictEqual(legDoc(db, out.legIds[0]).status, 'active', 'naqd ochilgan — yangi LEG-1 darhol ochiladi');
});

// ── NAQD RAD (ega 2026-11-14: xaridor yetkazish + qaytish haqini to'laydi) ──
async function cashAtDoor(db) {
  const r = await api.createShipmentInternal(deps(db), await wholesaleInput(db, { deliveryPaymentMethod: 'cash' }));
  await api.openCashShipment(deps(db), r.shipmentId);
  const { legIds } = shipOf(db, r.shipmentId);
  await lockAll(db, legIds);
  await carryToLastLeg(db, r.shipmentId, legIds);
  return { shipmentId: r.shipmentId, legIds };
}

ok('rad summasi serverda: yetkazish (muhr) + qaytish (teskari yo\'nalish, faol tarif)', async () => {
  const db = fresh();
  const { shipmentId } = await cashAtDoor(db);
  const due = await api.quoteCashRefusalDue(deps(db), shipmentId);
  const back = await api.quoteParcelForPoints(db, DEST_FAR, ORIGIN, PARCEL, { dimsOptional: true });
  assert.deepStrictEqual(due, {
    deliveryFee: 100000, returnFee: back.quote.customerPrice, total: 100000 + back.quote.customerPrice,
    returnTariffVersion: 7, currency: 'UZS',
  });
});

ok('rad, xaridor to\'ladi: refusal_collected, o\'zgarmas qayd; takror idempotent; boshqa natija — ziddiyat; keyin yetkazish YO\'Q', async () => {
  const db = fresh();
  const { shipmentId, legIds } = await cashAtDoor(db);
  const rec = (over) => api.recordCashRefusal(deps(db), {
    shipmentId, legId: legIds[2], courierId: F1, paid: true, ...over,
  });
  await assert.rejects(() => rec({ courierId: K1 }), reason('not_assigned'));
  await assert.rejects(() => rec({ legId: legIds[1] }), reason('cash_collector_mismatch'));
  await assert.rejects(() => rec({ paid: 'yes' }), reason('cash_refusal_input'));
  const a = await rec();
  assert.strictEqual(a.recorded, true);
  assert.strictEqual(a.paid, true);
  const ship = shipOf(db, shipmentId);
  assert.strictEqual(ship.deliveryPayment.status, 'refusal_collected');
  assert.strictEqual(ship.deliveryPayment.collectedBy, F1);
  assert.strictEqual(ship.deliveryPayment.refusal.total, a.deliveryFee + a.returnFee);
  assert.strictEqual(ship.status, 'in_transit', 'holat Ulgurji oqimida o\'zgaradi');
  const audit = db.dump('logistics_audit')[`cash_refusal_${shipmentId}`];
  assert.strictEqual(audit.kind, 'cash_refusal');
  assert.strictEqual(audit.wholesaleOrderId, 'WO1');
  assert.strictEqual(audit.total, a.total);
  const b = await rec();
  assert.strictEqual(b.idempotent, true);
  assert.strictEqual(b.total, a.total);
  await assert.rejects(() => rec({ paid: false }), reason('cash_refusal_conflict'));
  await assert.rejects(() => api.makeConfirmDelivery(deps(db))({
    legId: legIds[2], deliveryCode: dcode(db, shipmentId), photoUrls: photoFor(F1), cashCollected: true,
  }, ctx(F1)), reason('cash_state_invalid'));
});

ok('rad, xaridor to\'lamadi: refusal_unpaid (collectedBy yo\'q), summa qaydda — qarz/AVA qoplash relay_cash da', async () => {
  const db = fresh();
  const { shipmentId, legIds } = await cashAtDoor(db);
  const a = await api.recordCashRefusal(deps(db), { shipmentId, legId: legIds[2], courierId: F1, paid: false });
  const ship = shipOf(db, shipmentId);
  assert.strictEqual(ship.deliveryPayment.status, 'refusal_unpaid');
  assert.strictEqual(ship.deliveryPayment.collectedBy, null);
  assert.strictEqual(ship.deliveryPayment.refusal.paid, false);
  assert.strictEqual(a.total, a.deliveryFee + a.returnFee);
});

ok('rad: eskrou jo\'natmada — not_cash_shipment; posilka hali olinmagan — leg_not_in_progress', async () => {
  const db = fresh(seed());
  const e = await api.createShipmentInternal(deps(db), await wholesaleInput(db));
  await assert.rejects(() => api.quoteCashRefusalDue(deps(db), e.shipmentId), reason('not_cash_shipment'));
  const c = await api.createShipmentInternal(deps(db), await wholesaleInput(db, {
    idempotencyKey: 'wholesale_ship_WO3', destination: DEST_NEAR, deliveryPaymentMethod: 'cash',
  }));
  await api.openCashShipment(deps(db), c.shipmentId);
  const legId = shipOf(db, c.shipmentId).legIds[0];
  await accept(db, legId, K1);
  await assert.rejects(() => api.recordCashRefusal(deps(db), { shipmentId: c.shipmentId, legId, courierId: K1, paid: true }),
    reason('leg_not_in_progress'));
});

ok('to\'lov holatlari mashinasi: naqd faqat pending → cash_on_delivery → settled; noto\'g\'ri o\'tishlar rad', () => {
  assert.ok(L.canTransitionPayment('pending', 'cash_on_delivery'));
  assert.ok(L.canTransitionPayment('cash_on_delivery', 'settled'));
  assert.ok(!L.canTransitionPayment('cash_on_delivery', 'refund_pending'));
  assert.ok(!L.canTransitionPayment('cash_on_delivery', 'escrow_funded'));
  assert.ok(!L.canTransitionPayment('escrow_funded', 'cash_on_delivery'));
  assert.ok(L.isCustodyFunded({ paymentStatus: 'cash_on_delivery', deliveryPayment: { method: 'cash' } }));
  assert.ok(!L.isCustodyFunded({ paymentStatus: 'cash_on_delivery' }), 'deliveryPayment\'siz — ochiq emas');
  assert.ok(!L.isCustodyFunded({ paymentStatus: 'pending', deliveryPayment: { method: 'cash' } }));
});

(async () => {
  for (const t of tests) {
    try { await t.fn(); passed += 1; console.log(`  OK  ${t.name}`); } catch (e) {
      console.error(`  XATO ${t.name}\n       ${e.stack || e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
