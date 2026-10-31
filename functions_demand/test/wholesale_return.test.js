/**
 * Ulgurji 3b — rad etish va QAYTISH jo'natmasi (demand codebase, FakeFirestore + HAQIQIY relay
 * callable'lari: acceptLeg / scanHandover / confirmDelivery / getShipmentSecrets — O'ZGARMAGAN):
 *
 *   node functions_demand/test/wholesale_return.test.js
 *
 * Qulflanadi:
 *   - getWholesaleDeliveryCode: karta buyurtmasida kod faqat «Pul tushdi» dan keyin
 *   - markWholesaleBuyerRefused: faqat OXIRGI LEG kuryeri va posilka qo'lida; chek yuborilgan /
 *     tasdiqlangan — RAD; xaridor hisoblagichi; idempotent
 *   - qaytish jo'natmasi: xaridor manzili → sotuvchi, egasi = qabul qiluvchi = sotuvchi, HOZIRGI tarif
 *     versiyasi muhrlanadi, LEG-1 posilka qo'lidagi kuryerga biriktirilgan (match bilan), shakl
 *     `createShipmentInternal` bilan bir xil (paritet), idempotent; to'langach relay matching ishlamaydi;
 *     kuryer relay scanHandover (bizning kod) → sotuvchi kodi bilan relay confirmDelivery
 *   - custodian kuryer bo'lmasa — LEG draft (odatdagi matching)
 *   - reconcile: qaytish jo'natmasi qayta urinish, final — tegmaydi; trigger xato belgisida aylanmaydi
 */
const assert = require('assert');
const api = require('../api/logistics');
const L = require('../core/logistics');
const W = require('../api/wholesale_orders');
const C = require('../api/wholesale_card');
const R = require('../api/wholesale_return');
const E = require('../api/wholesale_events');
const tariffCore = require('../core/tariff');
const config = require('../core/config');
const {
  K1, NOW, ctx, makeDb, seed, deps, PHOTO,
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
    [`users/${BUYER}`]: { name: 'Bobur', fcmToken: 'tokB' },
    [`users/${SELLER}`]: { name: 'Sotuvchi', fcmToken: 'tokS' },
    [`users/${K1}`]: { accountId: `acc${K1}`, fcmToken: 'tokK1' },
    ...extra,
  });
}

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
    historySeq: 1,
    paymentMethod: 'card_on_delivery',
    payment: { status: 'held_seller', amount: fee + 3500, payer: 'seller', payerWalletUid: SELLER },
    cardPayment: { status: 'awaiting', confirmedAt: null },
    stock: { packId: 'p1', qty: 10, decremented: true, restored: false },
    shipment: null,
    refundStatus: null,
    createdAt: NOW,
    updatedAt: NOW,
    statusUpdatedAt: NOW,
    ...extra,
  };
}
const orderOf = (db, id = ORDER_ID) => db.docs.get(`wholesale_orders/${id}`);
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
async function q(fn) {
  console.error = () => {}; console.log = () => {};
  try { return await fn(); } finally { console.error = realError; console.log = realLog; }
}
const fakeMessaging = () => {
  const sent = [];
  return { sent, sendEach: async (msgs) => { sent.push(...msgs); return { responses: msgs.map(() => ({ success: true })) }; } };
};

/**
 * Oqim: buyurtma (karta) → jo'natma → default SHIP_FUND simulyatsiyasi → LEG active → K1 oladi →
 * (scan=true bo'lsa) sotuvchi kodi bilan K1 posilkani oladi. Qaytaradi {db, d, shipmentId, legId}.
 */
async function flow({ scan = true, extraSeed = {}, extraOrder = {} } = {}) {
  const db = makeDb(seedW(extraSeed));
  await db.collection('wholesale_orders').doc(ORDER_ID).set(orderDoc(db, extraOrder));
  const d = deps(db);
  const r = await q(() => W.ensureWholesaleShipment(d, ORDER_ID));
  const shipmentId = r.shipmentId;
  const ref = db.collection('shipments').doc(shipmentId);
  const before = (await ref.get()).data();
  const legId = before.legIds[0];
  // Default codebase `wholesaleShipFund` yozuvlari (eskrou relay'ga, buyurtma in_delivery).
  await ref.update({ paymentStatus: 'escrow_funded', status: 'ready', fundedAt: NOW });
  await db.collection('wholesale_orders').doc(ORDER_ID).update({ status: 'in_delivery', 'payment.deliveryFunded': true, historySeq: 3 });
  await q(async () => api.makeOnShipmentFunded(d)(before, (await ref.get()).data(), shipmentId));
  await api.makeAcceptLeg(d)({ legId }, ctx(K1));
  if (scan) {
    const sec = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(SELLER));
    await api.makeScanHandover(d)({ legId, code: sec.handoverCode, photoUrls: PHOTO }, ctx(K1));
  }
  return { db, d, shipmentId, legId };
}

// ═══════════════════════════════════════════════════════════════════════
ok('getWholesaleDeliveryCode (karta): tasdiqdan oldin card_payment_unconfirmed; sotuvchi tasdiqlagach — kod (relay hosilasi)', async () => {
  const { db, shipmentId } = await flow();
  const getCode = W.makeGetWholesaleDeliveryCode({ db });
  await q(() => rejects(getCode({ orderId: ORDER_ID }, ctx(BUYER)), 'failed-precondition', 'card_payment_unconfirmed'));
  await q(() => C.makeConfirmWholesaleCardPayment({ db, now: () => NOW })({ orderId: ORDER_ID }, ctx(SELLER)));
  const r = await q(() => getCode({ orderId: ORDER_ID }, ctx(BUYER)));
  const qr = db.docs.get(`shipments/${shipmentId}/private/secrets`).qrSecret;
  assert.strictEqual(r.deliveryCode, L.deliveryCodeFor(shipmentId, qr));
  // Hamyon buyurtmasi — o'zgarmagan (gate yo'q).
  const db2 = makeDb(seedW());
  await db2.collection('wholesale_orders').doc('ww').set(orderDoc(db2, { paymentMethod: 'wallet', cardPayment: null, payment: { status: 'held' } }));
  await q(() => rejects(W.makeGetWholesaleDeliveryCode({ db: db2 })({ orderId: 'ww' }, ctx(BUYER)), 'failed-precondition', 'shipment_not_ready'));
});

ok('markWholesaleBuyerRefused: begona / sotuvchi / xaridor — not_last_leg_courier; posilka olinmagan — parcel_not_in_hand', async () => {
  const mark = (db) => C.makeMarkWholesaleBuyerRefused({ db, now: () => NOW });
  const a = await flow({ scan: false });
  await q(async () => {
    await rejects(mark(a.db)({ orderId: ORDER_ID }, ctx(STRANGER)), 'permission-denied', 'not_last_leg_courier');
    await rejects(mark(a.db)({ orderId: ORDER_ID }, ctx(SELLER)), 'permission-denied', 'not_last_leg_courier');
    await rejects(mark(a.db)({ orderId: ORDER_ID }, ctx(BUYER)), 'permission-denied', 'not_last_leg_courier');
    await rejects(mark(a.db)({ orderId: ORDER_ID }, {}), 'unauthenticated');
    await rejects(mark(a.db)({ orderId: ORDER_ID }, ctx(K1)), 'failed-precondition', 'parcel_not_in_hand');
  });
  assert.strictEqual(orderOf(a.db).status, 'in_delivery');
  assert.strictEqual(a.db.docs.get(`wholesale_buyer_stats/${BUYER}`), undefined);
});

ok('markWholesaleBuyerRefused: chek yuborilgan — receipt_submitted; tasdiqlangan — card_payment_confirmed; hamyon — not_card_order', async () => {
  const mark = (db) => C.makeMarkWholesaleBuyerRefused({ db, now: () => NOW });
  let f = await flow({ extraOrder: { cardPayment: { status: 'receipt_submitted', receiptPath: 'p', submittedAt: NOW } } });
  await q(() => rejects(mark(f.db)({ orderId: ORDER_ID }, ctx(K1)), 'failed-precondition', 'receipt_submitted'));
  f = await flow({ extraOrder: { cardPayment: { status: 'confirmed' } } });
  await q(() => rejects(mark(f.db)({ orderId: ORDER_ID }, ctx(K1)), 'failed-precondition', 'card_payment_confirmed'));
  f = await flow({ extraOrder: { paymentMethod: 'wallet', cardPayment: null, payment: { status: 'held' } } });
  await q(() => rejects(mark(f.db)({ orderId: ORDER_ID }, ctx(K1)), 'failed-precondition', 'not_card_order'));
  // Nizoda kuryer RAD (faqat admin).
  f = await flow({ extraOrder: { cardPayment: { status: 'disputed' } } });
  await f.db.collection('wholesale_orders').doc(ORDER_ID).update({ status: 'payment_dispute' });
  await q(() => rejects(mark(f.db)({ orderId: ORDER_ID }, ctx(K1)), 'failed-precondition', 'invalid_transition'));
});

ok('TO\'LIQ QAYTISH: K1 refused → qaytish jo\'natmasi (hozirgi tarif v8, sotuvchi→sotuvchi, LEG-1 K1 ga) → to\'landi → relay matching YO\'Q → K1 scan (bizning kod) → sotuvchi kodi bilan relay confirmDelivery', async () => {
  const v7 = seedW()['module_tariffs/logistics_v7'];
  const f = await flow({
    extraSeed: {
      'module_tariffs/logistics': { activeVersion: 8 },
      'module_tariffs/logistics_v8': { ...v7, version: 8 },
      [`wholesale_buyer_stats/${BUYER}`]: { cardRefusals: 1 },
    },
  });
  const { db } = f;
  const messaging = fakeMessaging();
  const d = { ...deps(db), messaging };
  const before = orderOf(db);
  const r = await q(() => C.makeMarkWholesaleBuyerRefused({ db, now: () => NOW })({ orderId: ORDER_ID, reason: 'pul yo\'q dedi' }, ctx(K1)));
  assert.deepStrictEqual([r.status, r.idempotent], ['refused', false]);
  let o = orderOf(db);
  assert.deepStrictEqual([o.status, o.refundStatus, o.returnStatus, o.refusal.by, o.refusal.via, o.refusal.legId, o.refusal.reason],
    ['refused', 'pending', 'pending_shipment', K1, 'courier', f.legId, 'pul yo\'q dedi']);
  assert.deepStrictEqual(o.stock, { packId: 'p1', qty: 10, decremented: true, restored: false }, 'qoldiq rad paytida TIKLANMAYDI');
  assert.strictEqual(db.docs.get(`wholesale_buyer_stats/${BUYER}`).cardRefusals, 2);
  const h = db.docs.get(`wholesale_orders/${ORDER_ID}/history/4`);
  assert.deepStrictEqual([h.from, h.to, h.actor, h.actorId], ['in_delivery', 'refused', 'courier', K1]);
  assert.strictEqual((await q(() => C.makeMarkWholesaleBuyerRefused({ db, now: () => NOW })({ orderId: ORDER_ID }, ctx(K1)))).idempotent, true);
  assert.strictEqual(db.docs.get(`wholesale_buyer_stats/${BUYER}`).cardRefusals, 2, 'takror — hisoblagich +1 emas');
  // Asl jo'natmaga tegilmagan (relay o'zgarmaydi).
  assert.strictEqual(db.docs.get(`shipments/${f.shipmentId}`).status, 'in_transit');

  // demand triggeri → qaytish jo'natmasi + xabarlar.
  const out = await q(() => E.onWholesaleOrderUpdated(d, before, orderOf(db), ORDER_ID));
  assert.strictEqual(out.return.linked, true, JSON.stringify(out));
  o = orderOf(db);
  const rs = o.returnShipment;
  assert.strictEqual(o.returnStatus, 'awaiting_payment');
  assert.strictEqual(rs.courierId, K1);
  assert.strictEqual(rs.tariffVersion, 8, 'HOZIRGI tarif (asl 7 emas)');
  const ship = db.docs.get(`shipments/${rs.shipmentId}`);
  assert.deepStrictEqual([ship.ownerId, ship.recipientId, ship.source, ship.wholesaleOrderId, ship.wholesaleReturn, ship.outboundShipmentId],
    [SELLER, SELLER, 'wholesale_return', ORDER_ID, true, f.shipmentId]);
  assert.deepStrictEqual([ship.origin.addressText, ship.destination.addressText], [DEST.addressText, ORIGIN.addressText], 'xaridordan → sotuvchiga');
  assert.deepStrictEqual([ship.status, ship.paymentStatus], ['awaiting_payment', 'pending'], 'pul YO\'Q — default codebase to\'laydi');
  assert.strictEqual(ship.priceSnapshot.customerPrice, rs.fee);
  assert.strictEqual(ship.priceSnapshot.tariffVersion, 8);
  assert.deepStrictEqual([ship.parcel.actualWeightG, ship.parcel.declaredValue], [800, 140000]);
  assert.deepStrictEqual(ship.legAssignments, { [rs.legId]: K1 });
  const leg = db.docs.get(`demands/${rs.legId}`);
  assert.deepStrictEqual([leg.status, leg.assignment.providerId, leg.ownerId, leg.attributes.wholesaleOrderId, leg.attributes.wholesaleReturn],
    ['accepted', K1, SELLER, ORDER_ID, true]);
  const m = db.docs.get(`demand_matches/${rs.legId}_${K1}`);
  assert.deepStrictEqual([m.status, m.providerId, m.demandId, m.contactUnlocked.stage], ['accepted', K1, rs.legId, 1]);
  assert.ok(m.projection && m.projection.attributes, 'ijrochi ko\'radigan proyeksiya');
  const lo = db.docs.get(`logistics_orders/${ship.orderId}`);
  assert.deepStrictEqual([lo.ownerId, lo.recipientId, lo.source, lo.wholesaleReturn], [SELLER, SELLER, 'wholesale_return', true]);
  const keys = out.notifications.map((n) => `${n.to}:${n.key}`).sort();
  assert.deepStrictEqual(keys, ['buyer:ws_refused_buyer', 'seller:ws_refused_seller'].sort());
  // Bog'lanish yozuvi triggerni yana chaqiradi → kuryerga xabar (bitta).
  const out2 = await q(() => E.onWholesaleOrderUpdated(d, { ...o, returnShipment: null }, o, ORDER_ID));
  assert.deepStrictEqual(out2.notifications.map((n) => n.key), ['ws_return_courier']);
  assert.ok(messaging.sent.some((x) => x.token === 'tokK1'));
  // Idempotent: qayta chaqiruv — yangi jo'natma yo'q.
  assert.strictEqual((await q(() => R.ensureWholesaleReturnShipment(d, ORDER_ID))).skipped, 'already_linked');
  const dup = await q(() => R.createReturnShipment(d, ORDER_ID, o, K1));
  assert.deepStrictEqual([dup.duplicate, dup.shipmentId, dup.fee, dup.courierId], [true, rs.shipmentId, rs.fee, K1]);
  assert.strictEqual(Object.values(db.dump('shipments')).filter((s) => s.source === 'wholesale_return').length, 1);

  // Qaytish kodi: faqat qaytish kuryeri.
  const getRet = C.makeGetWholesaleReturnHandoverCode({ db });
  await q(async () => {
    await rejects(getRet({ orderId: ORDER_ID }, ctx(STRANGER)), 'permission-denied', 'not_return_courier');
    await rejects(getRet({ orderId: ORDER_ID }, ctx(SELLER)), 'permission-denied', 'not_return_courier');
  });

  // Default `wholesaleReturnFund` yozuvlari → relay onShipmentFunded: biriktirilgan LEG — matching YO'Q.
  const rref = db.collection('shipments').doc(rs.shipmentId);
  const rb = (await rref.get()).data();
  await rref.update({ paymentStatus: 'escrow_funded', status: 'ready', fundedAt: NOW, escrowEntryId: `wholesaleReturnFund:${ORDER_ID}` });
  await db.collection('wholesale_orders').doc(ORDER_ID).update({ status: 'returning', returnStatus: 'in_transit' });
  const act = await q(async () => api.makeOnShipmentFunded(d)(rb, (await rref.get()).data(), rs.shipmentId));
  assert.strictEqual(act.skipped, 'status_accepted');
  assert.deepStrictEqual(Object.keys(db.dump('demand_matches')).filter((k) => k.startsWith(rs.legId)), [`${rs.legId}_${K1}`]);

  // K1: qaytish kodi (bizning callable) → relay scanHandover.
  const code = await q(() => getRet({ orderId: ORDER_ID }, ctx(K1)));
  const qr = db.docs.get(`shipments/${rs.shipmentId}/private/secrets`).qrSecret;
  assert.strictEqual(code.handoverCode, L.handoverCodeFor(rs.shipmentId, qr));
  assert.ok(!('deliveryCode' in code), 'yetkazish kodi kuryerga berilmaydi');
  await api.makeScanHandover(d)({ legId: rs.legId, code: code.handoverCode, photoUrls: PHOTO }, ctx(K1));
  const s2 = db.docs.get(`shipments/${rs.shipmentId}`);
  assert.deepStrictEqual([s2.status, s2.currentCustodian.kind, s2.currentCustodian.id], ['in_transit', 'provider', K1]);
  // Sotuvchi (egasi) yetkazish kodini relay getShipmentSecrets dan oladi → K1 relay confirmDelivery.
  const sec = await api.makeGetShipmentSecrets(d)({ shipmentId: rs.shipmentId }, ctx(SELLER));
  const c = await api.makeConfirmDelivery(d)({ legId: rs.legId, deliveryCode: sec.deliveryCode, photoUrls: PHOTO }, ctx(K1));
  assert.strictEqual(c.shipmentStatus, 'delivered');
  const ev = db.dump('custody_events')[c.eventId];
  assert.deepStrictEqual([ev.deliversShipment, ev.shipmentId], [true, rs.shipmentId]);
  const s3 = db.docs.get(`shipments/${rs.shipmentId}`);
  assert.deepStrictEqual([s3.source, s3.wholesaleOrderId, s3.status], ['wholesale_return', ORDER_ID, 'delivered'], 'default `completeReturn` shu maydonlarga qaraydi');
});

ok('PARITET: qaytish jo\'natmasi / LEG / ichki / sirlar / ORDER shakli `createShipmentInternal` bilan bir xil (+ qaytish maydonlari)', async () => {
  const f = await flow();
  const { db } = f;
  // Toza ichki jo'natma (o'sha helper) — taqqoslash uchun.
  await db.collection('wholesale_orders').doc('wo2').set(orderDoc(db));
  const fresh = await q(() => W.ensureWholesaleShipment(deps(db), 'wo2'));
  await q(() => C.makeMarkWholesaleBuyerRefused({ db, now: () => NOW })({ orderId: ORDER_ID }, ctx(K1)));
  const rr = await q(() => R.ensureWholesaleReturnShipment(deps(db), ORDER_ID));
  const keys = (o) => Object.keys(o).sort();
  const a = db.docs.get(`shipments/${fresh.shipmentId}`);
  const b = db.docs.get(`shipments/${rr.shipmentId}`);
  assert.deepStrictEqual(keys(b), [...keys(a), 'wholesaleReturn', 'outboundShipmentId', 'legAssignments'].sort());
  assert.deepStrictEqual(keys(b.parcel), keys(a.parcel));
  assert.deepStrictEqual(keys(b.priceSnapshot), keys(a.priceSnapshot));
  const la = db.docs.get(`demands/${a.legIds[0]}`);
  const lb = db.docs.get(`demands/${b.legIds[0]}`);
  assert.deepStrictEqual(keys(lb), [...keys(la), 'preassigned'].sort());
  assert.deepStrictEqual(keys(lb.attributes), [...keys(la.attributes), 'wholesaleReturn'].sort());
  for (const sub of ['private/internal', 'private/secrets']) {
    assert.deepStrictEqual(keys(db.docs.get(`shipments/${rr.shipmentId}/${sub}`)), keys(db.docs.get(`shipments/${fresh.shipmentId}/${sub}`)), sub);
  }
  assert.deepStrictEqual(keys(db.docs.get(`route_plans/${rr.shipmentId}/versions/1`)), keys(db.docs.get(`route_plans/${fresh.shipmentId}/versions/1`)));
  const oa = db.docs.get(`logistics_orders/${a.orderId}`);
  const ob = db.docs.get(`logistics_orders/${b.orderId}`);
  assert.deepStrictEqual(keys(ob), [...keys(oa).filter((k) => k !== 'wholesaleOrderId'), 'wholesaleOrderId', 'wholesaleReturn'].sort());
  const ia = db.docs.get(`shipments/${fresh.shipmentId}/private/internal`);
  const ib = db.docs.get(`shipments/${rr.shipmentId}/private/internal`);
  assert.strictEqual(ib.platformShare + ib.providerPool, b.priceSnapshot.customerPrice);
  assert.strictEqual(ia.platformShare + ia.providerPool, a.priceSnapshot.customerPrice);
});

ok('custodian kuryer bo\'lmasa (posilka jo\'natuvchida) — qaytish LEG\'i draft, biriktirish/match yo\'q', async () => {
  const f = await flow({ scan: false });
  await f.db.collection('wholesale_orders').doc(ORDER_ID).update({ status: 'refused', refundStatus: 'pending' });
  const r = await q(() => R.ensureWholesaleReturnShipment(deps(f.db), ORDER_ID));
  assert.strictEqual(r.linked, true);
  assert.strictEqual(r.courierId, null);
  const ship = f.db.docs.get(`shipments/${r.shipmentId}`);
  assert.deepStrictEqual(ship.assignedProviderIds, []);
  assert.strictEqual(ship.legAssignments, undefined);
  const leg = f.db.docs.get(`demands/${ship.legIds[0]}`);
  assert.strictEqual(leg.status, 'draft');
  assert.strictEqual(Object.keys(f.db.dump('demand_matches')).filter((k) => k.startsWith(ship.legIds[0])).length, 0);
});

ok('reconcile: rad etilgan, jo\'natmasiz, 2 daqiqadan eski — bog\'lanadi; xato belgisi bilan trigger aylanmaydi; final — tegilmaydi', async () => {
  const f = await flow();
  const { db } = f;
  await q(() => C.makeMarkWholesaleBuyerRefused({ db, now: () => NOW })({ orderId: ORDER_ID }, ctx(K1)));
  // Trigger «yiqilgan»: xato belgisi bor → trigger qayta urinmaydi.
  await db.collection('wholesale_orders').doc(ORDER_ID).update({ returnShipmentError: { code: 'x', attempts: 1, final: false } });
  const t = await q(() => E.onWholesaleOrderUpdated(deps(db), orderOf(db), orderOf(db), ORDER_ID));
  assert.strictEqual(t.return, undefined);
  const at = (ms) => () => new Date(NOW.getTime() + ms);
  let r = await q(() => W.reconcileWholesaleShipments({ db, now: at(60 * 1000) }));
  assert.deepStrictEqual([r.returnChecked, r.returnLinked], [0, 0], 'yosh — kutadi');
  r = await q(() => W.reconcileWholesaleShipments({ db, now: at(3 * 60 * 1000) }));
  assert.deepStrictEqual([r.returnChecked, r.returnLinked], [1, 1]);
  assert.ok(orderOf(db).returnShipment.shipmentId);
  assert.strictEqual(orderOf(db).returnShipmentError, null);
  r = await q(() => W.reconcileWholesaleShipments({ db, now: at(30 * 60 * 1000) }));
  assert.strictEqual(r.returnChecked, 0);
  // Final xato — tegilmaydi.
  await db.collection('wholesale_orders').doc('wo3').set(orderDoc(db, {
    status: 'refused', refundStatus: 'done', returnShipmentError: { code: 'x', attempts: 5, final: true },
  }));
  r = await q(() => W.reconcileWholesaleShipments({ db, now: at(60 * 60 * 1000) }));
  assert.deepStrictEqual([r.returnFinal, r.returnChecked], [1, 0]);
});

ok('qaytish narxi hisoblanmasa (faol tarif yo\'q) — returnShipmentError, jo\'natma yo\'q, PII yo\'q', async () => {
  const f = await flow();
  await q(() => C.makeMarkWholesaleBuyerRefused({ db: f.db, now: () => NOW })({ orderId: ORDER_ID }, ctx(K1)));
  f.db.docs.delete('module_tariffs/logistics_v7');
  f.db.docs.set('module_tariffs/logistics', { activeVersion: 0 });
  tariffCore.clearCache();
  const r = await q(() => R.ensureWholesaleReturnShipment(deps(f.db), ORDER_ID));
  assert.strictEqual(r.failed, true);
  const o = orderOf(f.db);
  assert.strictEqual(o.returnShipment, undefined);
  assert.strictEqual(o.returnShipmentError.attempts, 1);
  assert.ok(!JSON.stringify(o.returnShipmentError).includes(BUYER));
  assert.strictEqual(Object.values(f.db.dump('shipments')).filter((s) => s.source === 'wholesale_return').length, 0);
});

(async () => {
  for (const t of tests) {
    try {
      await t.fn();
      passed += 1;
      console.log(`  ok  ${t.name}`);
    } catch (e) {
      console.error = realError; console.log = realLog;
      console.log(`  XATO ${t.name}\n       ${e.stack || e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
