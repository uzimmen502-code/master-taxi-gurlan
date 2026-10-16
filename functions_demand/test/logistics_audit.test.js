/**
 * Kuryer/Relay auditi (2026-10-16) — sof testlar (FakeFirestore).
 *
 *   node functions_demand/test/logistics_audit.test.js
 *
 * Poyga tuzatishlari HAQIQIY tranzaksiya bilan `logistics_audit_emulator.test.js`da;
 * bu yerda mantiq va chegaralar:
 *   L1  cancelLogisticsOrder: custodyCount > 0 — status `ready` bo'lsa ham bekor yo'q
 *   L3a scanHandover takrori: keyingi LEG ochilmay qolgan bo'lsa QAYTA ochiladi
 *   L3c legChainSweeper: to'langan jo'natmaning qotib qolgan `draft` LEG'ini ochadi
 *   L5  createLogisticsOrder: parallel chaqiruvlar — BITTA ORDER
 *   L6  acceptLeg: capability/qarz/bosqich/kill switch qayta tekshiriladi
 *   L12 adminUpsertLogisticsTariff: faol/eski versiya ustiga yozilmaydi
 */
const assert = require('assert');
const api = require('../api/logistics');
const tariffCore = require('../core/tariff');
const config = require('../core/config');
const {
  fixture, OWNER, K1, F1, ADMIN, NOW, ctx, makeDb, seed, orderPayload, deps, fund, PHOTO, photoFor, legOf,
} = require('./helpers/logistics_harness');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const fresh = (extra) => { config.clearCache(); tariffCore.clearCache(); return makeDb(seed(extra)); };

const ROUTE = [
  { to: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
  { from: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
];

/** To'langan, 2 LEG'li jo'natma (Gurlan -> Urganch -> Chilonzor); LEG-1 active. */
async function twoLegFunded(db, d) {
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload({
    destination: { regionId: 'toshkent_shahri', districtId: 'chilonzor', lat: 41.28, lng: 69.2, addressText: 'Chilonzor 9' },
    parcels: [{ actualWeightG: 5000, lengthCm: 50, widthCm: 40, heightCm: 40 }],
  }), ctx(OWNER));
  const shipmentId = r.shipmentIds[0];
  await fund(db, shipmentId);
  const p = await api.makeAdminPlanShipmentRoute(d)({ shipmentId, reason: 'test', legs: ROUTE }, ctx(ADMIN));
  return { shipmentId, orderId: r.orderId, leg0: p.legIds[0], leg1: p.legIds[1] };
}

/** `db.runTransaction`ning n-chaqiruvini yiqitadi (n = 1, 2, ...). */
function failTxCall(db, n) {
  const real = db.runTransaction;
  let calls = 0;
  db.runTransaction = async (fn) => {
    calls += 1;
    if (calls === n) throw new Error('sinov: tranzaksiya yiqildi');
    return real(fn);
  };
  return () => { db.runTransaction = real; };
}

// ═══════════════════════════════════════════════════════════════════════
// L1
ok('L1: custodyCount > 0 bo\'lsa status `ready` bo\'lsa ham bekor qilib bo\'lmaydi', async () => {
  const db = fresh();
  const d = deps(db);
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload(), ctx(OWNER));
  const shipmentId = r.shipmentIds[0];
  await fund(db, shipmentId);
  await db.collection('shipments').doc(shipmentId).update({ custodyCount: 1 });
  await assert.rejects(() => api.makeCancelLogisticsOrder(d)({ orderId: r.orderId }, ctx(OWNER)),
    (e) => e.code === 'failed-precondition' && e.details.reason === 'in_transit');
  const s = db.dump('shipments')[shipmentId];
  assert.strictEqual(s.status, 'ready');
  assert.strictEqual(s.paymentStatus, 'escrow_funded');
  assert.strictEqual(db.dump('logistics_orders')[r.orderId].status !== 'cancelled', true);
});

// ═══════════════════════════════════════════════════════════════════════
// L3a
ok('L3a: scanHandover takrori — birinchi chaqiruvda ochilmagan keyingi LEG QAYTA ochiladi', async () => {
  const db = fresh();
  const d = deps(db);
  const { shipmentId, leg0, leg1 } = await twoLegFunded(db, d);
  await api.makeAcceptLeg(d)({ legId: leg0 }, ctx(K1));
  const sec = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(OWNER));
  const scanArgs = { legId: leg0, code: sec.handoverCode, photoUrls: PHOTO };

  // 1-chaqiruv: scan tranzaksiyasi (1) o'tadi, keyingi LEG ochish (2) yiqiladi -> faqat log.
  const restore = failTxCall(db, 2);
  const s1 = await api.makeScanHandover(d)(scanArgs, ctx(K1));
  restore();
  assert.strictEqual(s1.idempotent, false);
  assert.strictEqual(db.dump('demands')[leg0].status, 'in_progress');
  assert.strictEqual(db.dump('demands')[leg1].status, 'draft', 'LEG-2 ochilmay qoldi (xato yutildi)');

  // Boshqa ijrochi takrorlasa LEG ochilmaydi (hodisani u yozmagan).
  const other = await api.makeScanHandover(d)({ ...scanArgs, photoUrls: photoFor(F1) }, ctx(F1));
  assert.strictEqual(other.idempotent, true);
  assert.strictEqual(db.dump('demands')[leg1].status, 'draft');

  // 2-chaqiruv (K1 qayta urinadi): idempotent, LEG-2 ENDI ochiladi + matching.
  const s2 = await api.makeScanHandover(d)(scanArgs, ctx(K1));
  assert.strictEqual(s2.idempotent, true);
  assert.strictEqual(db.dump('demands')[leg1].status, 'active');
  assert.ok(db.dump('demand_matches')[`${leg1}_${F1}`], 'LEG-2 uchun matching ishladi');
  assert.strictEqual(Object.keys(db.dump('custody_events')).length, 1, 'ikkinchi custody hodisasi YO\'Q');

  // 3-chaqiruv: yana idempotent, hech narsa o'zgarmaydi (LEG allaqachon active).
  const writesBefore = db.writes;
  const s3 = await api.makeScanHandover(d)(scanArgs, ctx(K1));
  assert.strictEqual(s3.idempotent, true);
  assert.strictEqual(db.writes, writesBefore, 'LEG allaqachon ochiq — yozuv yo\'q');
});

// ═══════════════════════════════════════════════════════════════════════
// L3c
ok('L3c sweeper: to\'langan, LEG-1 draft qolgan jo\'natma ochiladi; to\'lanmagan — tegilmaydi; takror — 0', async () => {
  const db = fresh();
  const d = deps(db);
  const paid = await api.makeCreateLogisticsOrder(d)(orderPayload(), ctx(OWNER));
  const unpaid = await api.makeCreateLogisticsOrder(d)(orderPayload({ clientRequestId: 'req-logistics-0002' }), ctx(OWNER));
  const paidShip = paid.shipmentIds[0];
  const [paidLeg] = legOf(db, paidShip);
  const [unpaidLeg] = legOf(db, unpaid.shipmentIds[0]);
  // Eskrou tushdi, lekin trigger LEG'ni ochmadi (yo'qolgan): to'g'ridan-to'g'ri yozuv.
  await db.collection('shipments').doc(paidShip).update({ paymentStatus: 'escrow_funded', status: 'ready' });
  assert.strictEqual(db.dump('demands')[paidLeg].status, 'draft');

  const run = api.makeLegChainSweeper(d);
  const r1 = await run();
  assert.strictEqual(r1.opened, 1);
  assert.strictEqual(db.dump('demands')[paidLeg].status, 'active');
  assert.ok(db.dump('demand_matches')[`${paidLeg}_${K1}`], 'matching ishladi');
  assert.strictEqual(db.dump('demands')[unpaidLeg].status, 'draft', 'to\'lanmagan jo\'natma LEG\'i ochilmaydi');
  const r2 = await run();
  assert.strictEqual(r2.opened, 0, 'idempotent: ikkinchi aylanish hech narsa ochmaydi');
});

ok('L3c sweeper: keyingi LEG faqat oldingisi OLINGANDA ochiladi (accepted — hali emas)', async () => {
  const db = fresh();
  const d = deps(db);
  const { shipmentId, leg0, leg1 } = await twoLegFunded(db, d);
  const run = api.makeLegChainSweeper(d);
  assert.strictEqual((await run()).opened, 0, 'LEG-1 active, LEG-2 draft: ochadigan narsa yo\'q');
  await api.makeAcceptLeg(d)({ legId: leg0 }, ctx(K1));
  assert.strictEqual((await run()).opened, 0, 'LEG-1 accepted (posilka olinmagan): LEG-2 ochilmaydi');
  assert.strictEqual(db.dump('demands')[leg1].status, 'draft');
  // scan keyingi LEG ochishda yiqildi -> sweeper ochadi.
  const sec = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(OWNER));
  const restore = failTxCall(db, 2);
  await api.makeScanHandover(d)({ legId: leg0, code: sec.handoverCode, photoUrls: PHOTO }, ctx(K1));
  restore();
  assert.strictEqual(db.dump('demands')[leg1].status, 'draft');
  const r = await run();
  assert.strictEqual(r.opened, 1);
  assert.strictEqual(db.dump('demands')[leg1].status, 'active');
});

ok('L3c sweeper: bekor qilingan/refund jo\'natma, modul o\'chiq, chegara (batchSize) hurmat qilinadi', async () => {
  const db = fresh();
  const d = deps(db);
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload(), ctx(OWNER));
  const shipmentId = r.shipmentIds[0];
  const [legId] = legOf(db, shipmentId);
  await fund(db, shipmentId);
  await api.makeCancelLogisticsOrder(d)({ orderId: r.orderId }, ctx(OWNER));
  assert.strictEqual(db.dump('demands')[legId].status, 'cancelled');
  assert.strictEqual((await api.makeLegChainSweeper(d)()).opened, 0, 'bekor qilingan jo\'natma tegilmaydi');

  // Modul o'chiq — hech narsa o'qilmaydi.
  const db2 = fresh();
  const d2 = deps(db2);
  const r2 = await api.makeCreateLogisticsOrder(d2)(orderPayload(), ctx(OWNER));
  await db2.collection('shipments').doc(r2.shipmentIds[0]).update({ paymentStatus: 'escrow_funded', status: 'ready' });
  await db2.collection('module_config').doc('logistics_all').set({ enabled: false });
  config.clearCache();
  const off = await api.makeLegChainSweeper(d2)();
  assert.strictEqual(off.skipped, 'disabled');
  assert.strictEqual(off.opened, 0);

  // Sahifalash: 3 ta qotgan jo'natma, sahifa 2 -> bir aylanishda HAMMASI (2 sahifa).
  const db3 = fresh();
  const d3 = deps(db3);
  const legs = [];
  for (let i = 1; i <= 3; i += 1) {
    const o = await api.makeCreateLogisticsOrder(d3)(orderPayload({ clientRequestId: `req-logistics-100${i}` }), ctx(OWNER));
    await db3.collection('shipments').doc(o.shipmentIds[0]).update({ paymentStatus: 'escrow_funded', status: 'ready' });
    legs.push(legOf(db3, o.shipmentIds[0])[0]);
  }
  const run = api.makeLegChainSweeper({ ...d3, batchSize: 2 });
  const full = await run();
  assert.strictEqual(full.opened, 3);
  assert.strictEqual(full.truncated, false);
  assert.ok(legs.every((id) => db3.dump('demands')[id].status === 'active'));

  // maxPages chegarasi: ochiq aytiladi (truncated), jim yo'qolmaydi.
  const db4 = fresh();
  const d4 = deps(db4);
  for (let i = 1; i <= 3; i += 1) {
    const o = await api.makeCreateLogisticsOrder(d4)(orderPayload({ clientRequestId: `req-logistics-200${i}` }), ctx(OWNER));
    await db4.collection('shipments').doc(o.shipmentIds[0]).update({ paymentStatus: 'escrow_funded', status: 'ready' });
  }
  const cut = await api.makeLegChainSweeper({ ...d4, batchSize: 2, maxPages: 1 })();
  assert.strictEqual(cut.opened, 2);
  assert.strictEqual(cut.truncated, true);
});

// ═══════════════════════════════════════════════════════════════════════
// L5
ok('L5: ikki parallel createLogisticsOrder (bir xil clientRequestId) — BITTA ORDER', async () => {
  const db = fresh();
  const create = api.makeCreateLogisticsOrder(deps(db));
  const [a, b] = await Promise.all([create(orderPayload(), ctx(OWNER)), create(orderPayload(), ctx(OWNER))]);
  assert.strictEqual(a.orderId, b.orderId);
  assert.strictEqual([a, b].filter((x) => x.duplicate).length, 1, 'bittasi g\'olib, ikkinchisi duplicate');
  assert.strictEqual(Object.keys(db.dump('logistics_orders')).length, 1);
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 1);
  assert.strictEqual(Object.keys(db.dump('demands')).length, 1, 'bitta LEG');
  assert.strictEqual(Object.keys(db.dump('demand_idempotency')).length, 1);
  // Boshqa clientRequestId — alohida ORDER.
  const c = await create(orderPayload({ clientRequestId: 'req-logistics-0002' }), ctx(OWNER));
  assert.notStrictEqual(c.orderId, a.orderId);
});

// ═══════════════════════════════════════════════════════════════════════
// L6
async function fundedForAccept(extra) {
  const db = fresh(extra);
  const d = deps(db);
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload(), ctx(OWNER));
  const shipmentId = r.shipmentIds[0];
  const [legId] = legOf(db, shipmentId);
  await fund(db, shipmentId);
  assert.ok(db.dump('demand_matches')[`${legId}_${K1}`], 'K1 matching paytida mos edi');
  return { db, d, shipmentId, legId };
}
async function assertNotAccepted(db, d, legId, reason, code = 'permission-denied') {
  await assert.rejects(() => api.makeAcceptLeg(d)({ legId }, ctx(K1)),
    (e) => e.code === code && e.details.reason === reason, `kutilgan sabab: ${reason}`);
  const leg = db.dump('demands')[legId];
  assert.strictEqual(leg.status, 'active', 'LEG hali ochiq');
  assert.strictEqual(leg.assignment.providerId, null);
  assert.deepStrictEqual(db.dump('shipments')[leg.attributes.shipmentId].assignedProviderIds, []);
}

ok('L6: match tuzilgach capability bekor qilindi (active=false) — acceptLeg RAD', async () => {
  const { db, d, legId } = await fundedForAccept();
  await db.collection('provider_capabilities').doc(`acc${K1}`).update({ 'courier.active': false });
  await assertNotAccepted(db, d, legId, 'not_matched');
});

ok('L6: capability statusi to\'xtatildi (suspended) — acceptLeg RAD', async () => {
  const { db, d, legId } = await fundedForAccept();
  await db.collection('provider_capabilities').doc(`acc${K1}`).update({ 'status.courier': 'suspended' });
  await assertNotAccepted(db, d, legId, 'not_matched');
});

ok('L6: qarz bloki (provider_stats.debtBlocked) — acceptLeg RAD', async () => {
  const { db, d, legId } = await fundedForAccept();
  await db.collection('provider_stats').doc(K1).set({ debtBlocked: true });
  await assert.rejects(() => api.makeAcceptLeg(d)({ legId }, ctx(K1)),
    (e) => e.code === 'permission-denied' && e.details.reason === 'not_matched' && e.details.why === 'debt');
  assert.strictEqual(db.dump('demands')[legId].status, 'active');
});

ok('L6: moderator bloki (matchingBlocked) — acceptLeg RAD', async () => {
  const { db, d, legId } = await fundedForAccept();
  await db.collection('provider_stats').doc(K1).set({ matchingBlocked: true });
  await assertNotAccepted(db, d, legId, 'not_matched');
});

ok('L6: INTERNAL bosqich — ijrochi sinov ro\'yxatidan chiqarildi — acceptLeg RAD', async () => {
  const { db, d, legId } = await fundedForAccept();
  await db.collection('module_config').doc('logistics_all').set({
    enabled: true, matchingEnabled: true, pushEnabled: false, logistics: { stage: 'internal', testerIds: [OWNER] },
  });
  config.clearCache();
  await assertNotAccepted(db, d, legId, 'not_matched');
  await assert.rejects(() => api.makeAcceptLeg(d)({ legId }, ctx(K1)), (e) => e.details.why === 'stage_internal');
});

ok('L6: kill switch (modul o\'chirildi) — acceptLeg RAD', async () => {
  const { db, d, legId } = await fundedForAccept();
  await db.collection('module_config').doc('logistics_all').set({ enabled: false });
  config.clearCache();
  await assertNotAccepted(db, d, legId, 'module_disabled', 'unavailable');
});

ok('L6: hudud o\'zgardi (ijrochi boshqa viloyatga ko\'chdi) — acceptLeg RAD', async () => {
  const { db, d, legId } = await fundedForAccept();
  await db.collection('provider_capabilities').doc(`acc${K1}`).update({
    'courier.regionIds': ['toshkent_shahri'], 'courier.districtIds': [],
  });
  await assertNotAccepted(db, d, legId, 'not_matched');
});

ok('L6: hamma narsa joyida — acceptLeg oldingidek ishlaydi (ijrochi o\'zgarishsiz)', async () => {
  const { db, d, legId } = await fundedForAccept();
  const r = await api.makeAcceptLeg(d)({ legId }, ctx(K1));
  assert.strictEqual(r.ok, true);
  assert.strictEqual(db.dump('demands')[legId].assignment.providerId, K1);
});

// ═══════════════════════════════════════════════════════════════════════
// L12
ok('L12: faol/eski tarif ustiga upsert yozmaydi; qoralama yangilanadi (createdAt saqlanadi); audit tranzaksiyada', async () => {
  const db = fresh();
  const d = deps(db);
  const upsert = api.makeAdminUpsertLogisticsTariff(d);
  // Faol (v7) va retired versiya o'zgarmas.
  const before7 = JSON.stringify(db.dump('module_tariffs').logistics_v7);
  await assert.rejects(() => upsert({ tariff: { ...fixture.tariff, version: 7 } }, ctx(ADMIN)), (e) => e.details.reason === 'tariff_immutable');
  assert.strictEqual(JSON.stringify(db.dump('module_tariffs').logistics_v7), before7, 'faol hujjat o\'zgarmadi');
  await db.collection('module_tariffs').doc('logistics_v6').set({ ...fixture.tariff, version: 6, status: 'retired' });
  await assert.rejects(() => upsert({ tariff: { ...fixture.tariff, version: 6 } }, ctx(ADMIN)), (e) => e.details.reason === 'tariff_immutable');
  assert.strictEqual(db.dump('module_tariffs').logistics_v6.status, 'retired');
  assert.strictEqual(Object.values(db.dump('logistics_audit')).filter((x) => x.kind === 'tariff_upsert').length, 0, 'rad etilganda audit YO\'Q');

  // Qoralama: ikki marta yozish mumkin, createdAt birinchisidan.
  const t0 = new Date('2026-10-01T00:00:00Z');
  const u1 = api.makeAdminUpsertLogisticsTariff({ ...d, now: () => t0 });
  await u1({ tariff: { ...fixture.tariff, version: 8 } }, ctx(ADMIN));
  await upsert({ tariff: { ...fixture.tariff, version: 8 } }, ctx(ADMIN));
  const v8 = db.dump('module_tariffs').logistics_v8;
  assert.strictEqual(v8.status, 'draft');
  assert.strictEqual(v8.createdAt.getTime(), t0.getTime());
  assert.strictEqual(v8.updatedAt.getTime(), NOW.getTime());
  assert.strictEqual(Object.values(db.dump('logistics_audit')).filter((x) => x.kind === 'tariff_upsert').length, 2);
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
