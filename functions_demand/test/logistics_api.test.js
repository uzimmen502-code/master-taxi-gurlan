/**
 * AVA Logistics API — to'liq oqim (FakeFirestore).
 *
 *   node functions_demand/test/logistics_api.test.js
 *
 * Qulflanadi:
 *   - buyurtma: ORDER + SHIPMENT + sirlar + marshrut v1 + LEG(draft); idempotent
 *   - to'lovsiz LEG ochilmaydi; eskrou tushgach LEG-1 active + matching
 *   - acceptLeg: faqat mos ijrochi, birinchi g'olib, kontakt 1-pog'ona
 *   - scanHandover: kod/QR + rasm; ATOMAR; idempotent; 2-pog'ona kontakt
 *   - confirmDelivery: faqat oxirgi LEG, alohida kod; EARNED ma'lumoti hodisada
 *   - cancel: custody'gacha; eskrou → refund_pending
 *   - replan: 2 LEG, zanjir (keyingi LEG oldingisi OLGANDA ochiladi), payout bo'linishi
 *   - tarif admini: narxsiz faol qilinmaydi; faol/eski versiya o'zgarmas
 */
const assert = require('assert');
const api = require('../api/logistics');
const L = require('../core/logistics');
const tariffCore = require('../core/tariff');
const config = require('../core/config');
// Seed, payload va oqim yordamchilari — paritet testi bilan BITTA manba.
const {
  fixture, OWNER, K1, K2, F1, ADMIN, NOW, ctx, makeDb, seed, orderPayload, deps, fund, PHOTO, photoFor, BUCKET, legOf,
} = require('./helpers/logistics_harness');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

// ═══════════════════════════════════════════════════════════════════════
ok('kotirovka: faol tarif bo\'yicha, 1 parcel = 10 000', async () => {
  const db = makeDb(seed()); config.clearCache(); tariffCore.clearCache();
  const q = await api.makeQuoteLogisticsOrder({ db })(orderPayload(), ctx(OWNER));
  assert.strictEqual(q.total, 10000);
  assert.strictEqual(q.parcels[0].zone, 'ZONE_0');
  assert.strictEqual(q.tariffVersion, 7);
  assert.strictEqual(q.parcels[0].payout, undefined, 'ichki qatlam mijozga KO\'RSATILMAYDI');
});

ok('tarif faol bo\'lmasa — tariff_not_active; modul o\'chiq — unavailable', async () => {
  const db = makeDb(seed({ 'module_tariffs/logistics': { activeVersion: 0 } }));
  config.clearCache(); tariffCore.clearCache();
  await assert.rejects(() => api.makeQuoteLogisticsOrder({ db })(orderPayload(), ctx(OWNER)),
    (e) => e.code === 'failed-precondition' && e.details.reason === 'tariff_not_active');
  const db2 = makeDb(seed({ 'module_config/logistics_all': { enabled: false } }));
  config.clearCache(); tariffCore.clearCache();
  await assert.rejects(() => api.makeQuoteLogisticsOrder({ db: db2 })(orderPayload(), ctx(OWNER)),
    (e) => e.code === 'unavailable');
});

ok('noma\'lum tuman / viloyatga mos bo\'lmagan tuman — rad', async () => {
  const db = makeDb(seed()); config.clearCache(); tariffCore.clearCache();
  await assert.rejects(() => api.makeQuoteLogisticsOrder({ db })(orderPayload({
    origin: { regionId: 'xorazm', districtId: 'chilonzor' },
  }), ctx(OWNER)), (e) => e.details.reason === 'geo_district_unknown');
  await assert.rejects(() => api.makeQuoteLogisticsOrder({ db })(orderPayload({
    origin: { regionId: 'andijon' },
  }), ctx(OWNER)), (e) => e.details.reason === 'geo_region_unknown');
});

ok('buyurtma: ORDER + SHIPMENT + sirlar + ichki ulush + marshrut v1 + LEG(draft); idempotent', async () => {
  const db = makeDb(seed()); config.clearCache(); tariffCore.clearCache();
  const create = api.makeCreateLogisticsOrder(deps(db));
  const r = await create(orderPayload(), ctx(OWNER));
  assert.strictEqual(r.duplicate, false);
  assert.strictEqual(r.total, 10000);
  assert.deepStrictEqual(r.trackingNumbers, ['AVA-26-1007-000001']);
  const ship = db.dump('shipments')[r.shipmentIds[0]];
  assert.strictEqual(ship.status, 'awaiting_payment');
  assert.strictEqual(ship.paymentStatus, 'pending');
  assert.strictEqual(ship.priceSnapshot.customerPrice, 10000);
  assert.strictEqual(ship.priceSnapshot.tariffVersion, 7, 'D-8: tarif versiyasi muhrlangan');
  assert.deepStrictEqual(ship.currentCustodian, { kind: 'sender', id: OWNER, since: NOW });
  assert.strictEqual(ship.recipientName, 'Olim aka');
  assert.strictEqual(ship.recipientPhone, undefined, 'telefon shipment\'da YO\'Q (40-band)');
  const order = db.dump('logistics_orders')[r.orderId];
  assert.strictEqual(order.status, 'awaiting_payment');
  assert.strictEqual(order.recipient.phone, '998905556677');
  assert.strictEqual(order.customerPriceTotal, 10000);
  // Sirlar va ichki qatlam — private/
  const secrets = db.docs.get(`shipments/${r.shipmentIds[0]}/private/secrets`);
  assert.ok(secrets && secrets.qrSecret.length === 32);
  const internal = db.docs.get(`shipments/${r.shipmentIds[0]}/private/internal`);
  assert.strictEqual(internal.platformShare, 2000);
  assert.deepStrictEqual(internal.legPayouts.map((l) => l.amount), [8000]);
  // LEG — draft, to'lovsiz ochilmaydi.
  const legId = ship.legIds[0];
  const leg = db.dump('demands')[legId];
  assert.strictEqual(leg.status, 'draft');
  assert.strictEqual(leg.module, 'logistics');
  assert.strictEqual(leg.attributes.payout, 8000);
  assert.strictEqual(leg.attributes.legKind, 'direct');
  assert.strictEqual(leg.tariffVersion, 7);
  assert.strictEqual(leg.location.districtId, 'gurlan');
  assert.ok(leg.location.geohash, 'geohash koordinatadan');
  // Marshrut v1
  const plan = db.docs.get(`route_plans/${r.shipmentIds[0]}/versions/1`);
  assert.strictEqual(plan.legs.length, 1);
  assert.strictEqual(plan.legs[0].legId, legId);
  // Idempotent
  const again = await create(orderPayload(), ctx(OWNER));
  assert.strictEqual(again.duplicate, true);
  assert.strictEqual(again.orderId, r.orderId);
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 1);
  // Tracking hisoblagichi: keyingi buyurtma 000002
  const r2 = await create(orderPayload({ clientRequestId: 'req-logistics-0002' }), ctx(OWNER));
  assert.deepStrictEqual(r2.trackingNumbers, ['AVA-26-1007-000002']);
});

ok('TO\'LIQ OQIM (1 LEG): eskrou → LEG active+matching → acceptLeg → scanHandover → confirmDelivery', async () => {
  const db = makeDb(seed()); config.clearCache(); tariffCore.clearCache();
  const d = deps(db);
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload(), ctx(OWNER));
  const shipmentId = r.shipmentIds[0];
  const legId = legOf(db, shipmentId)[0];

  // To'lovsiz accept yo'q (LEG draft).
  await assert.rejects(() => api.makeAcceptLeg(d)({ legId }, ctx(K1)), (e) => e.code === 'permission-denied', 'match yo\'q');

  // Eskrou tushdi → LEG-1 ochiladi + matching.
  const act = await fund(db, shipmentId);
  assert.strictEqual(act.activated, true);
  const leg = db.dump('demands')[legId];
  assert.strictEqual(leg.status, 'active');
  const matches = db.dump('demand_matches');
  assert.ok(matches[`${legId}_${K1}`], 'K1 (posilka oladi) mos');
  assert.ok(!matches[`${legId}_${K2}`], 'K2 (acceptsParcels=false) mos EMAS');
  assert.ok(matches[`${legId}_${F1}`], 'F1 (freight, xorazm) mos');
  assert.strictEqual(matches[`${legId}_${K1}`].projection.attributes.payout, 8000, 'ijrochi haqni ko\'radi');
  assert.strictEqual(matches[`${legId}_${K1}`].projection.customerPrice, undefined, 'mijoz narxi ijrochiga yo\'q (14-band)');

  // acceptLeg: K2 mos emas → permission-denied; K1 oladi; F1 kechikdi.
  await assert.rejects(() => api.makeAcceptLeg(d)({ legId }, ctx(K2)), (e) => e.code === 'permission-denied');
  const acc = await api.makeAcceptLeg(d)({ legId }, ctx(K1));
  assert.strictEqual(acc.ok, true);
  await assert.rejects(() => api.makeAcceptLeg(d)({ legId }, ctx(F1)), (e) => e.code === 'failed-precondition', 'birinchi g\'olib');
  const legA = db.dump('demands')[legId];
  assert.strictEqual(legA.status, 'accepted');
  assert.strictEqual(legA.assignment.providerId, K1);
  const mK1 = db.dump('demand_matches')[`${legId}_${K1}`];
  assert.strictEqual(mK1.status, 'accepted');
  assert.strictEqual(mK1.contactUnlocked.stage, 1);
  assert.strictEqual(mK1.contactUnlocked.ownerPhone, OWNER, '1-pog\'ona: jo\'natuvchi telefoni');
  assert.strictEqual(mK1.contactUnlocked.recipientPhone, undefined, 'qabul qiluvchi hali YOPIQ (Т-9)');
  assert.strictEqual(db.dump('demand_matches')[`${legId}_${F1}`].status, 'taken');
  assert.deepStrictEqual(db.dump('shipments')[shipmentId].assignedProviderIds, [K1]);

  // Sirlar: egasi hammasini, custodian bo'lmagan ijrochi — hech narsa.
  const sec = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(OWNER));
  assert.ok(/^\d{6}$/.test(sec.handoverCode) && /^\d{6}$/.test(sec.deliveryCode));
  assert.ok(sec.qrPayload.startsWith(`AVA1|${shipmentId}|`));
  await assert.rejects(() => api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(K1)), (e) => e.code === 'permission-denied');

  // scanHandover: rasmsiz → rad; noto'g'ri kod → rad; to'g'ri → ATOMAR o'zgarish.
  const scan = api.makeScanHandover(d);
  await assert.rejects(() => scan({ legId, code: sec.handoverCode }, ctx(K1)), (e) => e.details.reason === 'photo_required');
  await assert.rejects(() => scan({ legId, code: '000000', photoUrls: PHOTO }, ctx(K1)),
    (e) => e.code === 'permission-denied' && e.details.reason === 'bad_proof');
  await assert.rejects(() => scan({ legId, code: sec.handoverCode, photoUrls: photoFor(F1) }, ctx(F1)), (e) => e.details.reason === 'not_assigned');
  assert.strictEqual(Object.keys(db.dump('custody_events')).length, 0, 'rad etilganda hodisa YO\'Q');

  const s1 = await scan({ legId, qrPayload: sec.qrPayload, photoUrls: PHOTO, conditionFlags: ['intact'], location: { lat: 41.84, lng: 60.39, accuracy: 12 } }, ctx(K1));
  assert.strictEqual(s1.idempotent, false);
  const ev = db.dump('custody_events')[s1.eventId];
  assert.deepStrictEqual(ev.from, { kind: 'sender', id: OWNER });
  assert.deepStrictEqual(ev.to, { kind: 'provider', id: K1 });
  assert.strictEqual(ev.proof.qrVerified, true);
  assert.strictEqual(ev.completesLegId, null, 'birinchi LEG — oldingi yo\'q');
  const ship1 = db.dump('shipments')[shipmentId];
  assert.strictEqual(ship1.status, 'in_transit');
  assert.deepStrictEqual(ship1.currentCustodian, { kind: 'provider', id: K1, since: NOW });
  assert.strictEqual(ship1.currentLegId, legId);
  assert.strictEqual(db.dump('demands')[legId].status, 'in_progress');
  const mK1b = db.dump('demand_matches')[`${legId}_${K1}`];
  assert.strictEqual(mK1b.contactUnlocked.stage, 2);
  assert.strictEqual(mK1b.contactUnlocked.recipientPhone, '998905556677', '2-pog\'ona: oxirgi LEG — qabul qiluvchi');
  assert.strictEqual(mK1b.contactUnlocked.deliveryCodeRequired, true);
  assert.strictEqual(db.dump('logistics_orders')[r.orderId].status, 'in_transit');

  // Idempotent: ikkinchi scan — ikkinchi hodisa YO'Q.
  const s2 = await scan({ legId, code: sec.handoverCode, photoUrls: PHOTO }, ctx(K1));
  assert.strictEqual(s2.idempotent, true);
  assert.strictEqual(Object.keys(db.dump('custody_events')).length, 1);

  // Endi custodian sirlarni oladi — lekin yetkazish kodisiz.
  const secK1 = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(K1));
  assert.strictEqual(secK1.handoverCode, sec.handoverCode);
  assert.strictEqual(secK1.deliveryCode, undefined, 'yetkazish kodi faqat egasiga');

  // confirmDelivery: handover kodi O'TMAYDI; to'g'ri kod → delivered.
  const confirm = api.makeConfirmDelivery(d);
  if (sec.handoverCode !== sec.deliveryCode) {
    await assert.rejects(() => confirm({ legId, deliveryCode: sec.handoverCode, photoUrls: PHOTO }, ctx(K1)),
      (e) => e.details.reason === 'bad_delivery_code');
  }
  const c1 = await confirm({ legId, deliveryCode: sec.deliveryCode, photoUrls: PHOTO }, ctx(K1));
  assert.strictEqual(c1.shipmentStatus, 'delivered');
  const ship2 = db.dump('shipments')[shipmentId];
  assert.strictEqual(ship2.status, 'delivered');
  assert.strictEqual(ship2.currentCustodian.kind, 'recipient');
  assert.strictEqual(db.dump('demands')[legId].status, 'completed');
  const evD = db.dump('custody_events')[c1.eventId];
  assert.strictEqual(evD.deliversShipment, true);
  assert.strictEqual(evD.completesLegId, legId);
  assert.strictEqual(evD.completedLegPayout, 8000, 'EARNED ma\'lumoti hodisada — default codebase o\'qiydi');
  assert.strictEqual(db.dump('logistics_orders')[r.orderId].status, 'delivered');
  // Yakunlangan jo'natma sirlari yopiq; bekor qilib bo'lmaydi.
  await assert.rejects(() => api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(OWNER)), (e) => e.details.reason === 'shipment_closed');
  await assert.rejects(() => api.makeCancelLogisticsOrder(d)({ orderId: r.orderId }, ctx(OWNER)), (e) => e.details.reason === 'in_transit');
});

ok('confirmDelivery: posilka olinmagan LEG\'da yetkazib bo\'lmaydi', async () => {
  const db = makeDb(seed()); config.clearCache(); tariffCore.clearCache();
  const d = deps(db);
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload(), ctx(OWNER));
  const shipmentId = r.shipmentIds[0]; const legId = legOf(db, shipmentId)[0];
  await fund(db, shipmentId);
  await api.makeAcceptLeg(d)({ legId }, ctx(K1));
  const sec = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(OWNER));
  await assert.rejects(() => api.makeConfirmDelivery(d)({ legId, deliveryCode: sec.deliveryCode, photoUrls: PHOTO }, ctx(K1)),
    (e) => e.details.reason === 'leg_not_in_progress');
});

// Audit S5/L13 (2026-10-16): dalil rasmi — faqat chaqiruvchining o'z Storage yo'li.
ok('S5: scanHandover/confirmDelivery rasmi — begona host, boshqa foydalanuvchi yo\'li, begona bucket RAD; o\'ziniki qabul', async () => {
  const db = makeDb(seed()); config.clearCache(); tariffCore.clearCache();
  const d = deps(db);
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload(), ctx(OWNER));
  const shipmentId = r.shipmentIds[0]; const legId = legOf(db, shipmentId)[0];
  await fund(db, shipmentId);
  await api.makeAcceptLeg(d)({ legId }, ctx(K1));
  const sec = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(OWNER));
  const scan = api.makeScanHandover(d);
  const badUrls = [
    ['https://r2.example/handover1.jpg'], // begona host
    photoFor(F1), // boshqa foydalanuvchining papkasi
    photoFor(K1, 'x.jpg', 'boshqa-bucket.firebasestorage.app'), // begona bucket
    ['http://firebasestorage.googleapis.com/v0/b/' + BUCKET + '/o/logistics%2F' + K1 + '%2Fx.jpg'], // http
    [...PHOTO, 'https://evil.example/a.jpg'], // bittasi begona bo'lsa ham rad
  ];
  for (const photoUrls of badUrls) {
    await assert.rejects(() => scan({ legId, code: sec.handoverCode, photoUrls }, ctx(K1)),
      (e) => e.code === 'invalid-argument' && e.details.reason === 'photo_url_invalid', JSON.stringify(photoUrls));
  }
  assert.strictEqual(Object.keys(db.dump('custody_events')).length, 0, 'rad etilganda custody YO\'Q');
  // To'g'ri (o'ziniki) — qabul.
  const s = await scan({ legId, code: sec.handoverCode, photoUrls: PHOTO }, ctx(K1));
  assert.strictEqual(s.idempotent, false);
  assert.deepStrictEqual(db.dump('custody_events')[s.eventId].proof.photoUrls, PHOTO);
  // confirmDelivery ham xuddi shunday.
  const confirm = api.makeConfirmDelivery(d);
  for (const photoUrls of badUrls) {
    await assert.rejects(() => confirm({ legId, deliveryCode: sec.deliveryCode, photoUrls }, ctx(K1)),
      (e) => e.code === 'invalid-argument' && e.details.reason === 'photo_url_invalid', JSON.stringify(photoUrls));
  }
  const c = await confirm({ legId, deliveryCode: sec.deliveryCode, photoUrls: PHOTO }, ctx(K1));
  assert.strictEqual(c.shipmentStatus, 'delivered');
});

ok('S5: rasm ixtiyoriy bo\'lsa (requireHandoverPhoto=false) rasmsiz o\'tadi; rasm berilsa baribir tekshiriladi', async () => {
  const db = makeDb(seed({ 'module_config/logistics_all': {
    enabled: true, matchingEnabled: true, pushEnabled: false, logistics: { stage: 'public', requireHandoverPhoto: false },
  } })); config.clearCache(); tariffCore.clearCache();
  const d = deps(db);
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload(), ctx(OWNER));
  const shipmentId = r.shipmentIds[0]; const legId = legOf(db, shipmentId)[0];
  await fund(db, shipmentId);
  await api.makeAcceptLeg(d)({ legId }, ctx(K1));
  const sec = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(OWNER));
  const scan = api.makeScanHandover(d);
  await assert.rejects(() => scan({ legId, code: sec.handoverCode, photoUrls: ['https://evil.example/a.jpg'] }, ctx(K1)),
    (e) => e.details.reason === 'photo_url_invalid');
  const s = await scan({ legId, code: sec.handoverCode }, ctx(K1));
  assert.strictEqual(s.idempotent, false);
});

ok('bekor qilish: eskrou tushgan bo\'lsa refund_pending; LEG va match yopiladi; keyin yana bekor — idempotent', async () => {
  const db = makeDb(seed()); config.clearCache(); tariffCore.clearCache();
  const d = deps(db);
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload(), ctx(OWNER));
  const shipmentId = r.shipmentIds[0]; const legId = legOf(db, shipmentId)[0];
  await fund(db, shipmentId);
  await assert.rejects(() => api.makeCancelLogisticsOrder(d)({ orderId: r.orderId }, ctx(K1)), (e) => e.code === 'permission-denied');
  const c = await api.makeCancelLogisticsOrder(d)({ orderId: r.orderId }, ctx(OWNER));
  assert.strictEqual(c.refundPending, 1);
  const ship = db.dump('shipments')[shipmentId];
  assert.strictEqual(ship.status, 'cancelled');
  assert.strictEqual(ship.paymentStatus, 'refund_pending', 'pulni default codebase qaytaradi');
  assert.strictEqual(db.dump('demands')[legId].status, 'cancelled');
  assert.strictEqual(db.dump('demand_matches')[`${legId}_${K1}`].status, 'cancelled');
  assert.strictEqual(db.dump('logistics_orders')[r.orderId].status, 'cancelled');
  const c2 = await api.makeCancelLogisticsOrder(d)({ orderId: r.orderId }, ctx(OWNER));
  assert.strictEqual(c2.refundPending, 0);
});

ok('bekor qilish (to\'lanmagan): refund yo\'q, paymentStatus pending qoladi', async () => {
  const db = makeDb(seed()); config.clearCache(); tariffCore.clearCache();
  const d = deps(db);
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload(), ctx(OWNER));
  const c = await api.makeCancelLogisticsOrder(d)({ orderId: r.orderId }, ctx(OWNER));
  assert.strictEqual(c.refundPending, 0);
  assert.strictEqual(db.dump('shipments')[r.shipmentIds[0]].paymentStatus, 'pending');
});

ok('2 LEG (Gurlan → Urganch → Chilonzor): replan, zanjir, payout bo\'linishi, custody provider→provider', async () => {
  const db = makeDb(seed()); config.clearCache(); tariffCore.clearCache();
  const d = deps(db);
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload({
    destination: { regionId: 'toshkent_shahri', districtId: 'chilonzor', lat: 41.28, lng: 69.2, addressText: 'Chilonzor 9' },
    parcels: [{ actualWeightG: 5000, lengthCm: 50, widthCm: 40, heightCm: 40 }],
  }), ctx(OWNER));
  assert.strictEqual(r.total, 240000);
  const shipmentId = r.shipmentIds[0];
  const oldLegId = legOf(db, shipmentId)[0];
  await fund(db, shipmentId);
  assert.strictEqual(db.dump('demands')[oldLegId].status, 'active');

  const plan = api.makeAdminPlanShipmentRoute(d);
  await assert.rejects(() => plan({ shipmentId, legs: [{}, {}] }, ctx(OWNER)), (e) => e.code === 'permission-denied');
  // Uzilgan zanjir rad.
  await assert.rejects(() => plan({ shipmentId, legs: [
    { to: { regionId: 'xorazm', districtId: 'urganch_shahri' } },
    { from: { regionId: 'xorazm', districtId: 'gurlan' } },
  ] }, ctx(ADMIN)), (e) => e.details.reason === 'legs_discontinuous');

  const p = await plan({ shipmentId, reason: 'Urganch orqali', legs: [
    { to: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
    { from: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
  ] }, ctx(ADMIN));
  assert.strictEqual(p.version, 2);
  assert.strictEqual(p.legCount, 2);
  assert.strictEqual(p.firstLeg.activated, true, 'to\'langan — LEG-1 darhol ochiladi');
  assert.strictEqual(db.dump('demands')[oldLegId].status, 'cancelled', 'eski LEG bekor');
  const [leg0, leg1] = p.legIds;
  const d0 = db.dump('demands')[leg0]; const d1 = db.dump('demands')[leg1];
  assert.strictEqual(d0.attributes.legKind, 'first_mile');
  assert.strictEqual(d1.attributes.legKind, 'last_mile');
  assert.strictEqual(d0.attributes.payout + d1.attributes.payout, 192000, 'pool = 240 000 − 20%');
  assert.strictEqual(d0.attributes.payout, 96000);
  assert.strictEqual(d0.status, 'active'); assert.strictEqual(d1.status, 'draft');
  assert.strictEqual(d1.attributes.dependsOnLegId, leg0);
  assert.strictEqual(d0.attributes.nextLegId, leg1);
  const v2 = db.docs.get(`route_plans/${shipmentId}/versions/2`);
  assert.strictEqual(v2.createdBy, ADMIN); assert.strictEqual(v2.legs.length, 2);
  assert.ok(db.docs.get(`route_plans/${shipmentId}/versions/1`).supersededAt, 'eski reja o\'chirilmaydi, superseded (D-9)');

  // LEG-1: K1 (Gurlan) oladi; F1 ham mos (xorazm), lekin K1 birinchi.
  await api.makeAcceptLeg(d)({ legId: leg0 }, ctx(K1));
  // Tayinlangan LEG bor — qayta rejalash RAD.
  await assert.rejects(() => plan({ shipmentId, legs: [{}] }, ctx(ADMIN)), (e) => e.details.reason === 'leg_assigned');

  const sec = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(OWNER));
  const scan = api.makeScanHandover(d);
  const s0 = await scan({ legId: leg0, code: sec.handoverCode, photoUrls: PHOTO }, ctx(K1));
  assert.strictEqual(s0.idempotent, false);
  // ZANJIR: K1 posilkani OLDI → LEG-2 ochildi (draft → active) + matching.
  const d1b = db.dump('demands')[leg1];
  assert.strictEqual(d1b.status, 'active', 'keyingi LEG oldingisi olganda ochiladi (deadlock yo\'q)');
  const m1 = db.dump('demand_matches');
  assert.ok(m1[`${leg1}_${F1}`], 'LEG-2 (Urganch → Toshkent): freight mos');
  assert.ok(!m1[`${leg1}_${K1}`], 'kuryer viloyatdan tashqariga olib bormaydi (destination_out_of_area)');
  // K1 kontakti 2-pog'ona: oraliq LEG — qabul qiluvchi YO'Q.
  const mK1 = m1[`${leg0}_${K1}`];
  assert.strictEqual(mK1.contactUnlocked.stage, 2);
  assert.strictEqual(mK1.contactUnlocked.recipientPhone, null);
  assert.strictEqual(mK1.contactUnlocked.handoverToKind, 'provider');

  // LEG-2: F1 oladi → olish kontakti = K1 (joriy custodian); K1 ga F1 telefoni ochiladi.
  await api.makeAcceptLeg(d)({ legId: leg1 }, ctx(F1));
  const mF1 = db.dump('demand_matches')[`${leg1}_${F1}`];
  assert.strictEqual(mF1.contactUnlocked.ownerPhone, K1, 'oraliq LEG: oldingi ijrochi telefoni');
  assert.strictEqual(db.dump('demand_matches')[`${leg0}_${K1}`].contactUnlocked.nextProviderPhone, F1);

  // F1 K1'dan oladi: custody provider → provider, LEG-1 completed + payout hodisada.
  const secF = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(K1)); // custodian QR ko'rsatadi
  const s1 = await scan({ legId: leg1, qrPayload: secF.qrPayload, photoUrls: photoFor(F1), conditionFlags: ['package_damaged'] }, ctx(F1));
  const ev1 = db.dump('custody_events')[s1.eventId];
  assert.deepStrictEqual(ev1.from, { kind: 'provider', id: K1 });
  assert.deepStrictEqual(ev1.to, { kind: 'provider', id: F1 });
  assert.strictEqual(ev1.completesLegId, leg0);
  assert.strictEqual(ev1.completedLegProviderId, K1);
  assert.strictEqual(ev1.completedLegPayout, 96000);
  assert.deepStrictEqual(ev1.proof.conditionFlags, ['package_damaged']);
  assert.strictEqual(db.dump('demands')[leg0].status, 'completed');
  assert.strictEqual(db.dump('demands')[leg1].status, 'in_progress');
  assert.strictEqual(db.dump('shipments')[shipmentId].currentCustodian.id, F1);
  assert.strictEqual(db.dump('demand_matches')[`${leg0}_${K1}`].status, 'completed');
  assert.strictEqual(db.dump('demand_matches')[`${leg1}_${F1}`].contactUnlocked.recipientPhone, '998905556677', 'oxirgi LEG: qabul qiluvchi');
  assert.strictEqual(Object.keys(db.dump('custody_events')).length, 2, 'custody tarixi — ikkita o\'zgarmas yozuv');

  // K1 (oxirgi LEG emas) yetkaza olmaydi; F1 yetkazadi.
  await assert.rejects(() => api.makeConfirmDelivery(d)({ legId: leg0, deliveryCode: sec.deliveryCode, photoUrls: PHOTO }, ctx(K1)),
    (e) => e.details.reason === 'not_last_leg');
  const c = await api.makeConfirmDelivery(d)({ legId: leg1, deliveryCode: sec.deliveryCode, photoUrls: photoFor(F1) }, ctx(F1));
  assert.strictEqual(c.shipmentStatus, 'delivered');
  assert.strictEqual(db.dump('custody_events')[c.eventId].completedLegPayout, 96000);
  assert.strictEqual(db.dump('logistics_orders')[r.orderId].status, 'delivered');
});

ok('tarif admini: qoralama narxsiz FAOL qilinmaydi; to\'liq → faol, eski retired, pointer; faol versiya o\'zgarmas', async () => {
  const db = makeDb(seed()); config.clearCache(); tariffCore.clearCache();
  const d = deps(db);
  const upsert = api.makeAdminUpsertLogisticsTariff(d);
  const activate = api.makeAdminActivateLogisticsTariff(d);
  await assert.rejects(() => upsert({ tariff: { ...fixture.tariff, version: 8 } }, ctx(OWNER)), (e) => e.code === 'permission-denied');

  const partial = { ...fixture.tariff, version: 8, prices: {} };
  const u1 = await upsert({ tariff: partial }, ctx(ADMIN));
  assert.strictEqual(u1.status, 'draft');
  assert.ok(u1.activationErrors.length > 0, 'narxsiz — faol qilib bo\'lmasligi oldindan aytiladi');
  await assert.rejects(() => activate({ version: 8 }, ctx(ADMIN)), (e) => e.details.reason === 'tariff_incomplete');
  assert.strictEqual(db.dump('module_tariffs').logistics.activeVersion, 7, 'faol versiya o\'zgarmadi');

  await upsert({ tariff: { ...fixture.tariff, version: 8 } }, ctx(ADMIN));
  const a = await activate({ version: 8 }, ctx(ADMIN));
  assert.deepStrictEqual(a, { version: 8, previousVersion: 7 });
  const docs = db.dump('module_tariffs');
  assert.strictEqual(docs.logistics.activeVersion, 8);
  assert.strictEqual(docs.logistics_v8.status, 'active');
  assert.strictEqual(docs.logistics_v7.status, 'retired');
  await assert.rejects(() => upsert({ tariff: { ...fixture.tariff, version: 8 } }, ctx(ADMIN)), (e) => e.details.reason === 'tariff_immutable');
  assert.strictEqual(Object.values(db.dump('logistics_audit')).filter((x) => x.kind === 'tariff_activate').length, 1, 'audit (41-band)');
  // Yangi buyurtma endi v8 bilan.
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload(), ctx(OWNER));
  assert.strictEqual(db.dump('shipments')[r.shipmentIds[0]].priceSnapshot.tariffVersion, 8);
});

ok('LEG-2 muddati tugadi (kuryer topilmadi) → shipment.legProblem; admin qayta ochadi → matching qaytadan, zanjir davom etadi', async () => {
  const db = makeDb(seed()); config.clearCache(); tariffCore.clearCache();
  const d = deps(db);
  const maint = require('../api/maintenance');
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload({
    destination: { regionId: 'toshkent_shahri', districtId: 'chilonzor', lat: 41.28, lng: 69.2, addressText: 'Chilonzor 9' },
    parcels: [{ actualWeightG: 5000, lengthCm: 50, widthCm: 40, heightCm: 40 }],
  }), ctx(OWNER));
  const shipmentId = r.shipmentIds[0];
  await fund(db, shipmentId);
  const p = await api.makeAdminPlanShipmentRoute(d)({ shipmentId, reason: 'Urganch orqali', legs: [
    { to: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
    { from: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
  ] }, ctx(ADMIN));
  const [leg0, leg1] = p.legIds;
  await api.makeAcceptLeg(d)({ legId: leg0 }, ctx(K1));
  const sec = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(OWNER));
  await api.makeScanHandover(d)({ legId: leg0, code: sec.handoverCode, photoUrls: PHOTO }, ctx(K1));
  assert.strictEqual(db.dump('demands')[leg1].status, 'active', 'LEG-2 matching ochiq');
  const payoutBefore = db.dump('demands')[leg1].attributes.payout;

  // 3 kun + 1 soat o'tdi, hech kim olmadi → sweeper.
  const later = new Date(NOW.getTime() + (3 * 24 + 1) * 3600 * 1000);
  const sw = await maint.makeExpireSweeper({ db, now: () => later })();
  assert.strictEqual(sw.expired, 1); assert.strictEqual(sw.legProblems, 1);
  assert.strictEqual(db.dump('demands')[leg1].status, 'expired');
  assert.strictEqual(db.dump('shipments')[shipmentId].legProblem.legId, leg1);
  assert.strictEqual(db.dump('shipments')[shipmentId].status, 'in_transit', 'jo\'natma K1 qo\'lida, qotib qolmaydi');
  assert.strictEqual(db.dump('demand_matches')[`${leg1}_${F1}`].status, 'expired');
  // in_transit'da to'liq qayta rejalash hali ham RAD (LEG-1 ijrochi qo'lida) — qayta ochish yo'li alohida.
  await assert.rejects(() => api.makeAdminPlanShipmentRoute(d)({ shipmentId, legs: [{}] }, ctx(ADMIN)), (e) => e.details.reason === 'shipment_not_replannable');

  const react = api.makeAdminReactivateLeg({ ...d, now: () => later });
  await assert.rejects(() => react({ legId: leg1 }, ctx(OWNER)), (e) => e.code === 'permission-denied');
  await assert.rejects(() => react({ legId: leg0 }, ctx(ADMIN)), (e) => e.details.reason === 'leg_not_expired', 'in_progress LEG qayta ochilmaydi');
  const rr = await react({ legId: leg1, reason: 'kuryer topilmadi, qayta' }, ctx(ADMIN));
  assert.strictEqual(rr.ok, true);
  const leg1b = db.dump('demands')[leg1];
  assert.strictEqual(leg1b.status, 'active');
  assert.strictEqual(leg1b.reopenCount, 1);
  assert.ok(leg1b.timeWindow.expiresAt.getTime() > later.getTime(), 'muddat qaytadan');
  assert.strictEqual(leg1b.attributes.payout, payoutBefore, 'payout o\'zgarmaydi');
  assert.strictEqual(db.dump('shipments')[shipmentId].legProblem, null);
  assert.strictEqual(db.dump('demand_matches')[`${leg1}_${F1}`].status, 'new', 'F1 ga yana taklif');
  assert.ok(Object.values(db.dump('logistics_audit')).some((x) => x.kind === 'leg_reactivate' && x.legId === leg1), 'audit (41-band)');
  // Zanjir davom etadi: F1 oladi, K1 dan posilkani oladi.
  await api.makeAcceptLeg({ ...d, now: () => later })({ legId: leg1 }, ctx(F1));
  const secK = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(K1));
  const s1 = await api.makeScanHandover({ ...d, now: () => later })({ legId: leg1, code: secK.handoverCode, photoUrls: photoFor(F1) }, ctx(F1));
  assert.strictEqual(s1.idempotent, false);
  assert.strictEqual(db.dump('demands')[leg0].status, 'completed');
  assert.strictEqual(db.dump('demands')[leg1].status, 'in_progress');
});

// Admin audit (2026-10-08): qayta rejalashdan keyin eski `expired` LEG
// `cancelled`ga o'ta olmaydi va qoladi — uni «LEG'ni qayta ochish» bilan
// jonlantirish ikkinchi, «etim» LEG yaratardi (13/15-band).
ok('qayta rejalash: legProblem tozalanadi; eski (superseded) LEG qayta ochilmaydi', async () => {
  const db = makeDb(seed()); config.clearCache(); tariffCore.clearCache();
  const d = deps(db);
  const maint = require('../api/maintenance');
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload(), ctx(OWNER));
  const shipmentId = r.shipmentIds[0];
  await fund(db, shipmentId);
  const [oldLeg] = legOf(db, shipmentId);
  assert.strictEqual(db.dump('demands')[oldLeg].status, 'active');

  const later = new Date(NOW.getTime() + (3 * 24 + 1) * 3600 * 1000);
  await maint.makeExpireSweeper({ db, now: () => later })();
  assert.strictEqual(db.dump('demands')[oldLeg].status, 'expired');
  assert.strictEqual(db.dump('shipments')[shipmentId].legProblem.legId, oldLeg);
  assert.strictEqual(db.dump('shipments')[shipmentId].status, 'ready');

  const p = await api.makeAdminPlanShipmentRoute({ ...d, now: () => later })({ shipmentId, reason: 'yangi yo\'l', legs: [
    { to: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
    { from: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
  ] }, ctx(ADMIN));
  assert.ok(!p.legIds.includes(oldLeg));
  assert.strictEqual(db.dump('shipments')[shipmentId].legProblem, null, 'eski reja muammosi tozalandi');
  assert.strictEqual(db.dump('demands')[oldLeg].status, 'expired', 'expired → cancelled o\'tishi yo\'q, qoladi');

  const react = api.makeAdminReactivateLeg({ ...d, now: () => later });
  await assert.rejects(() => react({ legId: oldLeg }, ctx(ADMIN)),
    (e) => e.details.reason === 'leg_superseded', 'eski reja LEG\'i ochilmaydi');
  assert.strictEqual(db.dump('demands')[oldLeg].status, 'expired');
});

ok('qayta ochish: modul o\'chiq — aniq sabab bilan rad, eski match tarixi O\'CHIRILMAYDI', async () => {
  const db = makeDb(seed()); config.clearCache(); tariffCore.clearCache();
  const d = deps(db);
  const maint = require('../api/maintenance');
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload(), ctx(OWNER));
  const shipmentId = r.shipmentIds[0];
  await fund(db, shipmentId);
  const [leg] = legOf(db, shipmentId);
  const later = new Date(NOW.getTime() + (3 * 24 + 1) * 3600 * 1000);
  await maint.makeExpireSweeper({ db, now: () => later })();
  const matchesBefore = Object.keys(db.dump('demand_matches')).filter((k) => k.startsWith(`${leg}_`));
  assert.ok(matchesBefore.length > 0);

  await db.collection('module_config').doc('logistics_all').set({ enabled: false });
  config.clearCache();
  const react = api.makeAdminReactivateLeg({ ...d, now: () => later });
  await assert.rejects(() => react({ legId: leg }, ctx(ADMIN)), (e) => e.details.reason === 'module_disabled');
  const matchesAfter = Object.keys(db.dump('demand_matches')).filter((k) => k.startsWith(`${leg}_`));
  assert.deepStrictEqual(matchesAfter.sort(), matchesBefore.sort(), 'match tarixi saqlandi');
  assert.strictEqual(db.dump('demands')[leg].status, 'expired');
});

ok('onShipmentFunded: faqat pending→escrow_funded o\'tishida; takror chaqiruv LEG\'ni qayta ochmaydi', async () => {
  const db = makeDb(seed()); config.clearCache(); tariffCore.clearCache();
  const d = deps(db);
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload(), ctx(OWNER));
  const shipmentId = r.shipmentIds[0];
  const run = api.makeOnShipmentFunded(d);
  const same = await run({ paymentStatus: 'escrow_funded' }, { paymentStatus: 'escrow_funded', legIds: legOf(db, shipmentId) }, shipmentId);
  assert.strictEqual(same.skipped, 'no_change');
  await fund(db, shipmentId);
  const again = await run({ paymentStatus: 'pending' }, { paymentStatus: 'escrow_funded', legIds: legOf(db, shipmentId) }, shipmentId);
  assert.strictEqual(again.skipped, 'status_active', 'idempotent');
});

// Harness fake'i qulflanadi: yana «yumshoq» bo'lib qolsa, yuqoridagi oqimlar
// haqiqiy SDK'da yiqiladigan tranzaksiyani yashil ko'rsatadi.
ok('harness fake tranzaksiyasi haqiqiy SDK kabi: yozuvdan KEYIN o\'qish XATO', async () => {
  const db = makeDb(seed());
  const ref = db.collection('shipments').doc('s1');
  await assert.rejects(
    () => db.runTransaction(async (tx) => {
      tx.set(ref, { x: 1 });
      await tx.get(ref);
    }),
    /all reads to be executed before all writes/,
  );
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
