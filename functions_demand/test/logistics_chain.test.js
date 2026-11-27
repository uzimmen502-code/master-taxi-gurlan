/**
 * AVA Logistics — «avval butun zanjirni yig', keyin yur» (assemble_all), FakeFirestore.
 *
 *   node functions_demand/test/logistics_chain.test.js
 *
 * Ega qarorlari 2026-11-07 (CONFIRMED). Qulflanadi:
 *   - buyurtma: transfer nuqtalari bo'yicha avtomatik LEG'lar, payout splitInternal bo'yicha, `chain`;
 *   - markaz yo'q → bitta LEG (TRANSFER_POINT_MISSING), bir tuman → bitta LEG;
 *   - to'lov → BARCHA LEG ochiladi + har LEG push, muddat = fundedAt + 48 soat (takror cho'zmaydi);
 *   - qisman olish qulflamaydi, kontakt YO'Q; oxirgi olish qulflaydi, kontaktlar shu yerda;
 *   - LEG-2+ ijrochisi jo'natuvchi telefonini HECH QACHON olmaydi; legAssignments yozilmaydi;
 *   - qulfgacha bo'shatish mumkin (qayta matching), qulfdan keyin CHAIN_LOCKED;
 *   - qulfgacha posilka olinmaydi (CHAIN_NOT_LOCKED);
 *   - o'zi-o'ziga topshirish (selfTransfer) — kod/rasmsiz, hodisa o'zgarmas, payout LEG bo'yicha;
 *   - 48 soat: bekor + refund_pending + match'lar yopiladi + xabarlar; expireDemandsSweeper tegmaydi;
 *   - adminReopenChainLeg (qulf saqlanadi, custody to'xtaydi, qayta olinganda kontakt yangilanadi);
 *   - payoutOverrides (yig'indi = pool, faqat yig'ishda, audit);
 *   - sequential: LEG-2 olish telefoni jo'natuvchi EMAS (privacy tuzatish).
 */
const assert = require('assert');
const api = require('../api/logistics');
const offersApi = require('../api/offers');
const maint = require('../api/maintenance');
const tariffCore = require('../core/tariff');
const config = require('../core/config');
const {
  OWNER, K1, F1, ADMIN, NOW, ctx, makeDb, seed, orderPayload, deps, fund, PHOTO, photoFor, legOf,
} = require('./helpers/logistics_harness');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

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
function chainSeed(extra = {}, cfg = CHAIN_CFG) {
  return seed({
    'module_config/logistics_all': cfg,
    'geo_districts/yunusobod': { regionId: 'toshkent_shahri' },
    ...extra,
  });
}
const DEST = { regionId: 'toshkent_shahri', districtId: 'chilonzor', lat: 41.28, lng: 69.2, addressText: 'Chilonzor 9' };
const PARCELS = [{ actualWeightG: 5000, lengthCm: 50, widthCm: 40, heightCm: 40, declaredValue: 150000 }];
const H48 = 48 * 3600 * 1000;
const at = (ms) => new Date(NOW.getTime() + ms);

function fresh(seedDocs) {
  const db = makeDb(seedDocs || chainSeed());
  config.clearCache(); tariffCore.clearCache();
  return db;
}
async function newChain(db, over = {}) {
  const r = await api.makeCreateLogisticsOrder(deps(db))(orderPayload({ destination: DEST, parcels: PARCELS, ...over }), ctx(OWNER));
  const shipmentId = r.shipmentIds[0];
  return { r, shipmentId, legIds: legOf(db, shipmentId) };
}
const shipOf = (db, id) => db.dump('shipments')[id];
const legDoc = (db, id) => db.dump('demands')[id];
const matchOf = (db, legId, p) => db.dump('demand_matches')[`${legId}_${p}`];
const accept = (db, legId, p, now) => api.makeAcceptLeg(deps(db, now))({ legId }, ctx(p));
const release = (db, legId, p) => offersApi.makeCancelAssignment({
  db, now: () => NOW, onReopened: api.makeOnLegReopened(deps(db)),
})({ demandId: legId }, ctx(p));
const reason = (code) => (e) => (e.details || {}).reason === code;

/** To'langan, BARCHA LEG olingan (qulflangan) zanjir: K1 → LEG-1, F1 → LEG-2 va LEG-3. */
async function lockedChain(db) {
  const c = await newChain(db);
  await fund(db, c.shipmentId);
  await accept(db, c.legIds[1], F1);
  await accept(db, c.legIds[2], F1);
  await accept(db, c.legIds[0], K1);
  return c;
}
function noSenderPhone(m, label) {
  const cu = (m && m.contactUnlocked) || {};
  for (const [k, v] of Object.entries(cu)) assert.notStrictEqual(v, OWNER, `${label}: ${k} = jo'natuvchi telefoni`);
}

// ═══════════════════════════════════════════════════════════════════════
ok('buyurtma: Gurlan → Chilonzor = 3 LEG (Urganch, Yunusobod orqali), payout splitInternal, chain=assembling', async () => {
  const db = fresh();
  const { r, shipmentId, legIds } = await newChain(db);
  assert.strictEqual(r.total, 240000);
  assert.strictEqual(legIds.length, 3);
  const ship = shipOf(db, shipmentId);
  assert.deepStrictEqual(ship.chain, {
    mode: 'assemble_all', state: 'assembling', deadlineAt: null, lockedAt: null, claimed: 0, legCount: 3,
    selfTransferLegIds: [],
  });
  assert.strictEqual(ship.legCount, 3);
  const legs = legIds.map((id) => legDoc(db, id));
  assert.deepStrictEqual(legs.map((l) => l.attributes.legKind), ['first_mile', 'line_haul', 'last_mile']);
  assert.deepStrictEqual(legs.map((l) => l.location.districtId), ['gurlan', 'urganch_shahri', 'yunusobod']);
  assert.deepStrictEqual(legs.map((l) => l.destination.districtId), ['urganch_shahri', 'yunusobod', 'chilonzor']);
  assert.strictEqual(legs[1].location.addressText, '', 'Urganch markazi manzili konfigda yo\'q');
  assert.strictEqual(legs[2].location.addressText, 'Yunusobod bekat');
  assert.deepStrictEqual(legs.map((l) => l.attributes.payout), [48000, 96000, 48000], 'pool 192 000: 25/50/25%');
  assert.ok(legs.every((l) => l.attributes.chainMode === 'assemble_all' && l.status === 'draft'));
  assert.deepStrictEqual(legs.map((l) => l.attributes.legIndex), [0, 1, 2]);
  assert.strictEqual(legs[1].attributes.dependsOnLegId, legIds[0]);
  const internal = db.docs.get(`shipments/${shipmentId}/private/internal`);
  assert.deepStrictEqual(internal.legPayouts.map((p) => p.amount), [48000, 96000, 48000]);
  assert.strictEqual(db.docs.get(`route_plans/${shipmentId}/versions/1`).legs.length, 3);
});

ok('markaz yo\'q (toshkent_shahri standartda YO\'Q) → 1 LEG; bir tuman → 1 LEG; sequential → `chain` yo\'q', async () => {
  const noTp = { ...CHAIN_CFG, logistics: { ...CHAIN_CFG.logistics, transferPoints: undefined } };
  const db = fresh(chainSeed({}, noTp));
  const a = await newChain(db);
  assert.strictEqual(a.legIds.length, 1, 'TRANSFER_POINT_MISSING → to\'g\'ridan-to\'g\'ri');
  assert.strictEqual(shipOf(db, a.shipmentId).chain.legCount, 1);
  assert.strictEqual(legDoc(db, a.legIds[0]).attributes.legKind, 'direct');
  const b = await newChain(db, { clientRequestId: 'req-chain-same-1', destination: orderPayload().destination });
  assert.strictEqual(b.legIds.length, 1, 'Gurlan → Gurlan');
  const db2 = fresh(seed());
  const s = await newChain(db2);
  assert.strictEqual(shipOf(db2, s.shipmentId).chain, undefined, 'sequential hujjat shakli o\'zgarmagan');
  assert.strictEqual(legDoc(db2, s.legIds[0]).attributes.chainMode, undefined);
});

ok('to\'lov → BARCHA LEG active + har LEG push; muddat = fundedAt + 48 soat; trigger takrori muddatni cho\'zmaydi', async () => {
  const db = fresh();
  const { shipmentId, legIds } = await newChain(db);
  const pushed = [];
  const d = { ...deps(db), notify: async (_db, demand) => { pushed.push(demand.id); } };
  const ref = db.collection('shipments').doc(shipmentId);
  const before = (await ref.get()).data();
  await ref.update({ paymentStatus: 'escrow_funded', status: 'ready', fundedAt: NOW });
  const after = (await ref.get()).data();
  const res = await api.makeOnShipmentFunded(d)(before, after, shipmentId);
  assert.strictEqual(res.activated, 3);
  const ship = shipOf(db, shipmentId);
  assert.strictEqual(ship.chain.deadlineAt.getTime(), NOW.getTime() + H48);
  for (const id of legIds) {
    const l = legDoc(db, id);
    assert.strictEqual(l.status, 'active');
    assert.strictEqual(l.timeWindow.expiresAt.getTime(), NOW.getTime() + H48, 'LEG muddati = zanjir muddati');
  }
  assert.deepStrictEqual(pushed.sort(), [...legIds].sort(), 'har LEG mos ijrochilariga push');
  assert.ok(matchOf(db, legIds[0], K1) && matchOf(db, legIds[0], F1));
  assert.ok(matchOf(db, legIds[1], F1) && !matchOf(db, legIds[1], K1), 'LEG-2 respublika: kuryer K1 emas');
  assert.ok(matchOf(db, legIds[2], F1));
  // Takror (keyinroq) — muddat o'zgarmaydi, LEG'lar qayta ochilmaydi.
  const again = await api.activateChain(deps(db, at(3600 * 1000)), shipmentId);
  assert.strictEqual(again.activated, 0);
  assert.strictEqual(shipOf(db, shipmentId).chain.deadlineAt.getTime(), NOW.getTime() + H48);
});

ok('qisman olish: qulf YO\'Q, kontakt YO\'Q, claimed=1, legAssignments yozilmaydi', async () => {
  const db = fresh();
  const { shipmentId, legIds } = await newChain(db);
  await fund(db, shipmentId);
  const r = await accept(db, legIds[0], K1);
  assert.deepStrictEqual(r.chain, { state: 'assembling', claimed: 1, legCount: 3 });
  const ship = shipOf(db, shipmentId);
  assert.strictEqual(ship.chain.state, 'assembling');
  assert.strictEqual(ship.chain.claimed, 1);
  assert.strictEqual(ship.chain.lockedAt, null);
  assert.deepStrictEqual(ship.assignedProviderIds, [K1]);
  assert.strictEqual(ship.legAssignments, undefined, 'boshqa kuryer telefonlari jo\'natmada YO\'Q');
  const m = matchOf(db, legIds[0], K1);
  assert.strictEqual(m.status, 'accepted');
  assert.strictEqual(m.contactUnlocked, null, 'qulfgacha jo\'natuvchi telefoni ochilmaydi');
  assert.strictEqual(matchOf(db, legIds[0], F1).status, 'taken');
});

ok('qulfgacha posilka olinmaydi: CHAIN_NOT_LOCKED (to\'g\'ri kod bilan ham)', async () => {
  const db = fresh();
  const { shipmentId, legIds } = await newChain(db);
  await fund(db, shipmentId);
  await accept(db, legIds[0], K1);
  const sec = await api.makeGetShipmentSecrets(deps(db))({ shipmentId }, ctx(OWNER));
  await assert.rejects(() => api.makeScanHandover(deps(db))({ legId: legIds[0], code: sec.handoverCode, photoUrls: PHOTO }, ctx(K1)),
    reason('CHAIN_NOT_LOCKED'));
  assert.strictEqual(Object.keys(db.dump('custody_events')).length, 0);
  assert.strictEqual(shipOf(db, shipmentId).custodyCount, 0);
});

ok('qulfgacha bo\'shatish: LEG active, claimed-1, qayta matching (match `new`); qulfdan keyin — CHAIN_LOCKED', async () => {
  const db = fresh();
  const { shipmentId, legIds } = await newChain(db);
  await fund(db, shipmentId);
  await accept(db, legIds[0], K1);
  assert.strictEqual(matchOf(db, legIds[0], F1).status, 'taken');
  const rr = await release(db, legIds[0], K1);
  assert.strictEqual(rr.reopened, true);
  const l = legDoc(db, legIds[0]);
  assert.strictEqual(l.status, 'active');
  assert.strictEqual(l.assignment.providerId, null);
  assert.strictEqual(l.timeWindow.expiresAt.getTime(), NOW.getTime() + H48, 'muddat zanjirniki qoladi');
  const ship = shipOf(db, shipmentId);
  assert.strictEqual(ship.chain.claimed, 0);
  assert.deepStrictEqual(ship.assignedProviderIds, []);
  assert.strictEqual(matchOf(db, legIds[0], F1).status, 'new', 'qayta matching: boshqalar yana ko\'radi');
  // F1 endi oladi.
  await accept(db, legIds[0], F1);
  // To'liq yig'ib, qulfdan keyin bo'shatish rad.
  await accept(db, legIds[1], F1);
  await accept(db, legIds[2], F1);
  assert.strictEqual(shipOf(db, shipmentId).chain.state, 'locked');
  await assert.rejects(() => release(db, legIds[1], F1), reason('CHAIN_LOCKED'));
  assert.strictEqual(legDoc(db, legIds[1]).status, 'accepted', 'rad etilganda LEG o\'zgarmaydi');
});

ok('oxirgi olish qulflaydi; kontaktlar: LEG-1 ← jo\'natuvchi, LEG-2 ← K1, LEG-3 ← F1; LEG-2+ jo\'natuvchi telefonini OLMAYDI', async () => {
  const db = fresh();
  const { shipmentId, legIds } = await newChain(db);
  await fund(db, shipmentId);
  await accept(db, legIds[1], F1);
  assert.strictEqual(matchOf(db, legIds[1], F1).contactUnlocked, null);
  await accept(db, legIds[2], F1);
  const last = await accept(db, legIds[0], K1);
  assert.deepStrictEqual(last.chain, { state: 'locked', claimed: 3, legCount: 3 });
  const ship = shipOf(db, shipmentId);
  assert.strictEqual(ship.chain.state, 'locked');
  assert.strictEqual(ship.chain.lockedAt.getTime(), NOW.getTime());
  assert.strictEqual(ship.chain.claimed, 3);
  assert.deepStrictEqual([...ship.assignedProviderIds].sort(), [K1, F1].sort());
  assert.strictEqual(ship.legAssignments, undefined);
  assert.deepStrictEqual(ship.chain.selfTransferLegIds, [legIds[2]], 'LEG-3: oldingi LEG ham F1 — telefon yo\'q');
  // Proyeksiya: kuryer olishdan oldin zanjir belgisini ko'radi.
  assert.strictEqual(matchOf(db, legIds[1], F1).projection.attributes.chainMode, 'assemble_all');
  const m0 = matchOf(db, legIds[0], K1).contactUnlocked;
  assert.strictEqual(m0.stage, 1);
  assert.strictEqual(m0.ownerPhone, OWNER, 'LEG-1: jo\'natuvchidan oladi');
  assert.strictEqual(m0.nextProviderPhone, F1);
  assert.strictEqual(m0.pickupAddress, 'Gurlan, Markaz 1');
  assert.strictEqual(matchOf(db, legIds[0], K1).status, 'accepted');
  const m1 = matchOf(db, legIds[1], F1).contactUnlocked;
  assert.strictEqual(m1.ownerPhone, K1, 'LEG-2: oldingi LEG kuryeridan');
  assert.strictEqual(m1.nextProviderPhone, F1);
  const m2 = matchOf(db, legIds[2], F1).contactUnlocked;
  assert.strictEqual(m2.ownerPhone, F1, 'LEG-3: o\'zi (ketma-ket LEG)');
  assert.strictEqual(m2.nextProviderPhone, null);
  assert.strictEqual(m2.pickupAddress, 'Yunusobod bekat');
  noSenderPhone(matchOf(db, legIds[1], F1), 'LEG-2');
  noSenderPhone(matchOf(db, legIds[2], F1), 'LEG-3');
  // Qulflangan LEG'ni boshqa kuryer ololmaydi.
  await assert.rejects(() => accept(db, legIds[0], F1), (e) => e.code === 'failed-precondition');
});

ok('qulfdan keyin to\'liq oqim: custody K1 → F1 → F1 (selfTransfer, kodsiz) → yetkazildi; payout LEG bo\'yicha', async () => {
  const db = fresh();
  const { shipmentId, legIds } = await lockedChain(db);
  const d = deps(db);
  const scan = api.makeScanHandover(d);
  const sec = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(OWNER));
  await scan({ legId: legIds[0], code: sec.handoverCode, photoUrls: PHOTO }, ctx(K1));
  assert.strictEqual(legDoc(db, legIds[1]).status, 'accepted', 'zanjirda ketma-ket ochish YO\'Q (allaqachon tayinlangan)');
  // F1 LEG-2 ni kodsiz ololmaydi (oldingi LEG uniki emas).
  await assert.rejects(() => scan({ legId: legIds[1], selfTransfer: true }, ctx(F1)), reason('self_transfer_invalid'));
  const secK1 = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(K1));
  await scan({ legId: legIds[1], code: secK1.handoverCode, photoUrls: photoFor(F1) }, ctx(F1));
  // F1 o'zidan o'ziga: kod/rasm kerak emas (klient chaqiruv shakli aynan shu).
  const st = await scan({
    legId: legIds[2], selfTransfer: true, photoUrls: [], conditionFlags: ['intact'], clientRequestId: 'self-req-0001',
  }, ctx(F1));
  assert.strictEqual(st.idempotent, false);
  const ev = db.dump('custody_events')[st.eventId];
  assert.deepStrictEqual(ev.from, { kind: 'provider', id: F1 });
  assert.deepStrictEqual(ev.to, { kind: 'provider', id: F1 });
  assert.strictEqual(ev.proof.selfTransfer, true);
  assert.strictEqual(ev.proof.codeVerified, false);
  assert.strictEqual(ev.proof.qrVerified, false);
  assert.strictEqual(ev.completesLegId, legIds[1]);
  assert.strictEqual(ev.completedLegProviderId, F1);
  assert.strictEqual(ev.completedLegPayout, 96000, 'LEG-2 haqi o\'zgarmagan');
  assert.strictEqual(legDoc(db, legIds[1]).status, 'completed');
  assert.strictEqual(legDoc(db, legIds[2]).status, 'in_progress');
  assert.strictEqual(Object.keys(db.dump('custody_events')).length, 3, 'har topshirish alohida o\'zgarmas hodisa');
  // Takror — idempotent (ikkinchi hodisa yo'q).
  const again = await scan({ legId: legIds[2], selfTransfer: true }, ctx(F1));
  assert.strictEqual(again.idempotent, true);
  const c = await api.makeConfirmDelivery(d)({ legId: legIds[2], deliveryCode: sec.deliveryCode, photoUrls: photoFor(F1) }, ctx(F1));
  assert.strictEqual(c.shipmentStatus, 'delivered');
  assert.strictEqual(db.dump('custody_events')[c.eventId].completedLegPayout, 48000);
});

ok('selfTransfer: LEG-1 (jo\'natuvchidan) va sequential jo\'natmada RAD', async () => {
  const db = fresh();
  const { legIds } = await lockedChain(db);
  await assert.rejects(() => api.makeScanHandover(deps(db))({ legId: legIds[0], selfTransfer: true }, ctx(K1)),
    reason('self_transfer_invalid'));
  const db2 = fresh(seed());
  const s = await newChain(db2);
  await fund(db2, s.shipmentId);
  await accept(db2, s.legIds[0], F1); // Gurlan → Chilonzor to'g'ridan-to'g'ri: faqat freight mos
  await assert.rejects(() => api.makeScanHandover(deps(db2))({ legId: s.legIds[0], selfTransfer: true }, ctx(F1)),
    reason('self_transfer_invalid'));
});

ok('48 soat: CHAIN_EXPIRED; expireDemandsSweeper tegmaydi; legChainSweeper → bekor + refund_pending + match\'lar yopiq + xabar', async () => {
  const db = fresh();
  const { r, shipmentId, legIds } = await newChain(db);
  await fund(db, shipmentId);
  await accept(db, legIds[0], K1);
  const late = at(H48 + 60 * 1000);
  await assert.rejects(() => accept(db, legIds[1], F1, late), reason('CHAIN_EXPIRED'));
  // Umumiy sweeper zanjir LEG'larini yakka `expired` qilmaydi.
  const ex = await maint.makeExpireSweeper({ db, now: () => late })();
  assert.strictEqual(ex.expired, 0);
  assert.strictEqual(ex.chainSkipped, 2);
  assert.strictEqual(legDoc(db, legIds[1]).status, 'active');
  // Muddatdan OLDIN — tegilmaydi.
  const early = await api.makeLegChainSweeper(deps(db, at(H48 - 60 * 1000)))();
  assert.strictEqual(early.chainExpired, 0);
  const sw = await api.makeLegChainSweeper(deps(db, late))();
  assert.strictEqual(sw.chainExpired, 1);
  const ship = shipOf(db, shipmentId);
  assert.strictEqual(ship.status, 'cancelled');
  assert.strictEqual(ship.cancelledBy, 'assembly_expired');
  assert.strictEqual(ship.chain.state, 'expired');
  assert.strictEqual(ship.paymentStatus, 'refund_pending', 'mavjud refund yo\'li (relay_escrow) pulni qaytaradi');
  assert.ok(legIds.every((id) => legDoc(db, id).status === 'cancelled'));
  assert.strictEqual(matchOf(db, legIds[0], K1).status, 'cancelled');
  assert.strictEqual(matchOf(db, legIds[0], K1).contactUnlocked, null);
  assert.strictEqual(matchOf(db, legIds[1], F1).status, 'cancelled');
  assert.strictEqual(db.dump('logistics_orders')[r.orderId].status, 'cancelled');
  const news = db.dump('admin_news');
  assert.ok(news[`chainExpired_${shipmentId}_${OWNER}`], 'jo\'natuvchiga xabar');
  assert.ok(news[`chainExpired_${shipmentId}_${K1}`], 'LEG olgan kuryerga xabar');
  assert.ok(!news[`chainExpired_${shipmentId}_${F1}`], 'olmagan kuryerga xabar yo\'q');
  const n = news[`chainExpired_${shipmentId}_${OWNER}`];
  assert.ok(n.i18n.uz_Cyrl.title && n.i18n.uz_Latn.title && n.i18n.ru.title, '3 til');
  assert.strictEqual(n.targetUserId, OWNER);
  assert.ok(db.dump('logistics_audit')[`chain_expired_${shipmentId}`]);
  // Takror — hech narsa.
  const sw2 = await api.makeLegChainSweeper(deps(db, at(H48 + 3600 * 1000)))();
  assert.strictEqual(sw2.chainExpired, 0);
});

ok('48 soat: modul o\'chiq bo\'lsa ham zanjir muddati ishlaydi (refund yo\'li)', async () => {
  const db = fresh();
  const { shipmentId } = await newChain(db);
  await fund(db, shipmentId);
  await db.collection('module_config').doc('logistics_all').update({ enabled: false });
  config.clearCache();
  const sw = await api.makeLegChainSweeper(deps(db, at(H48 + 1000)))();
  assert.strictEqual(sw.skipped, 'disabled');
  assert.strictEqual(sw.chainExpired, 1);
  assert.strictEqual(shipOf(db, shipmentId).paymentStatus, 'refund_pending');
});

ok('qulflangan zanjir qulf paytida muddat o\'tsa ham bekor QILINMAYDI', async () => {
  const db = fresh();
  const { shipmentId } = await lockedChain(db);
  const sw = await api.makeLegChainSweeper(deps(db, at(H48 + 1000)))();
  assert.strictEqual(sw.chainExpired, 0);
  assert.strictEqual(shipOf(db, shipmentId).chain.state, 'locked');
  assert.strictEqual(shipOf(db, shipmentId).paymentStatus, 'escrow_funded');
});

ok('egasi bekor qildi → chain.state=cancelled, refund_pending', async () => {
  const db = fresh();
  const { r, shipmentId, legIds } = await newChain(db);
  await fund(db, shipmentId);
  await accept(db, legIds[0], K1);
  await api.makeCancelLogisticsOrder(deps(db))({ orderId: r.orderId }, ctx(OWNER));
  const ship = shipOf(db, shipmentId);
  assert.strictEqual(ship.chain.state, 'cancelled');
  assert.strictEqual(ship.paymentStatus, 'refund_pending');
});

ok('adminReopenChainLeg: LEG-2 qayta ochiladi, qulf saqlanadi, custody to\'xtaydi; qayta olinganda kontaktlar yangilanadi', async () => {
  const db = fresh();
  const { shipmentId, legIds } = await lockedChain(db);
  const d = deps(db);
  const reopen = api.makeAdminReopenChainLeg(d);
  await assert.rejects(() => reopen({ shipmentId, legId: legIds[1], reason: 'kuryer kasal' }, ctx(K1)), (e) => e.code === 'permission-denied');
  await assert.rejects(() => reopen({ shipmentId, legId: legIds[1], reason: '' }, ctx(ADMIN)), reason('reason_required'));
  const r1 = await reopen({ shipmentId, legId: legIds[1], reason: 'kuryer kasal' }, ctx(ADMIN));
  assert.strictEqual(r1.idempotent, false);
  assert.strictEqual(r1.claimed, 2);
  const l = legDoc(db, legIds[1]);
  assert.strictEqual(l.status, 'active');
  assert.strictEqual(l.assignment.providerId, null);
  assert.ok(l.chainReopenedAt);
  const ship = shipOf(db, shipmentId);
  assert.strictEqual(ship.chain.state, 'locked', 'qulf saqlanadi');
  assert.strictEqual(ship.chain.claimed, 2);
  assert.ok(ship.assignedProviderIds.includes(F1), 'F1 LEG-3 ni saqlaydi');
  assert.deepStrictEqual(ship.chain.selfTransferLegIds, [], 'LEG-2 ochiq — o\'ziga topshirish yo\'q');
  assert.strictEqual(legDoc(db, legIds[0]).assignment.providerId, K1, 'boshqa LEG\'lar kuryerini saqlaydi');
  assert.strictEqual(legDoc(db, legIds[2]).assignment.providerId, F1);
  assert.strictEqual(matchOf(db, legIds[0], K1).contactUnlocked.nextProviderPhone, null, 'tushgan kuryer telefoni qo\'shnida qolmaydi');
  assert.strictEqual(matchOf(db, legIds[2], F1).contactUnlocked.ownerPhone, null);
  assert.ok(db.dump('logistics_audit')[`chain_reopen_${legIds[1]}_1`], 'audit');
  // Idempotent.
  const r2 = await reopen({ shipmentId, legId: legIds[1], reason: 'kuryer kasal' }, ctx(ADMIN));
  assert.strictEqual(r2.idempotent, true);
  assert.strictEqual(Object.keys(db.dump('logistics_audit')).filter((k) => k.startsWith('chain_reopen_')).length, 1);
  // Custody to'xtaydi: K1 oladi, lekin LEG-3 (F1) LEG-2 ochiq ekan ololmaydi.
  const sec = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(OWNER));
  await api.makeScanHandover(d)({ legId: legIds[0], code: sec.handoverCode, photoUrls: PHOTO }, ctx(K1));
  await assert.rejects(() => api.makeScanHandover(d)({ legId: legIds[2], code: sec.handoverCode, photoUrls: photoFor(F1) }, ctx(F1)),
    reason('prev_leg_not_in_progress'));
  // posilka olingan LEG qayta ochilmaydi.
  await assert.rejects(() => reopen({ shipmentId, legId: legIds[0], reason: 'test sabab' }, ctx(ADMIN)), reason('leg_not_reopenable'));
  // F1 qayta oladi (qulf holatida faqat qayta ochilgan LEG) → kontaktlar yangilanadi.
  assert.strictEqual(matchOf(db, legIds[1], F1).status, 'new', 'qayta matching');
  const acc = await accept(db, legIds[1], F1);
  assert.deepStrictEqual(acc.chain, { state: 'locked', claimed: 3, legCount: 3 });
  assert.deepStrictEqual(shipOf(db, shipmentId).chain.selfTransferLegIds, [legIds[2]]);
  assert.strictEqual(matchOf(db, legIds[1], F1).contactUnlocked.ownerPhone, K1);
  assert.strictEqual(matchOf(db, legIds[0], K1).contactUnlocked.nextProviderPhone, F1);
  assert.strictEqual(matchOf(db, legIds[0], K1).contactUnlocked.stage, 2, 'posilkani olgan K1 ning 2-pog\'ona kontakti buzilmaydi');
  assert.strictEqual(matchOf(db, legIds[2], F1).contactUnlocked.ownerPhone, F1);
  noSenderPhone(matchOf(db, legIds[1], F1), 'LEG-2 (qayta)');
});

ok('adminReopenChainLeg: yig\'ish paytida RAD (CHAIN_NOT_LOCKED); sequential jo\'natmada not_chain', async () => {
  const db = fresh();
  const { shipmentId, legIds } = await newChain(db);
  await fund(db, shipmentId);
  await accept(db, legIds[0], K1);
  await assert.rejects(() => api.makeAdminReopenChainLeg(deps(db))({ shipmentId, legId: legIds[0], reason: 'test sabab' }, ctx(ADMIN)),
    reason('CHAIN_NOT_LOCKED'));
  const db2 = fresh(seed());
  const s = await newChain(db2);
  await assert.rejects(() => api.makeAdminReopenChainLeg(deps(db2))({ shipmentId: s.shipmentId, legId: s.legIds[0], reason: 'test sabab' }, ctx(ADMIN)),
    reason('not_chain'));
});

ok('payoutOverrides: yig\'indi = pool, butun so\'m, yig\'ishda; audit; sequential va qulfdan keyin RAD', async () => {
  const db = fresh();
  const { shipmentId, legIds } = await newChain(db);
  await fund(db, shipmentId);
  const plan = api.makeAdminPlanShipmentRoute(deps(db));
  const LEGS = [
    { to: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
    { from: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' },
      to: { regionId: 'toshkent_shahri', districtId: 'yunusobod', addressText: 'Yunusobod bekat' } },
    { from: { regionId: 'toshkent_shahri', districtId: 'yunusobod', addressText: 'Yunusobod bekat' } },
  ];
  const ov = (a, b, c) => [{ legIndex: 0, amount: a }, { legIndex: 1, amount: b }, { legIndex: 2, amount: c }];
  await assert.rejects(() => plan({ shipmentId, legs: LEGS, payoutOverrides: ov(50000, 96000, 48000) }, ctx(ADMIN)), reason('payout_override_sum'));
  await assert.rejects(() => plan({ shipmentId, legs: LEGS, payoutOverrides: ov(50000.5, 93999.5, 48000) }, ctx(ADMIN)), reason('payout_override_invalid'));
  await assert.rejects(() => plan({ shipmentId, legs: LEGS, payoutOverrides: [{ legIndex: 0, amount: 192000 }] }, ctx(ADMIN)), reason('payout_override_invalid'));
  const p = await plan({ shipmentId, legs: LEGS, reason: 'Toshkent qismi qimmat', payoutOverrides: ov(40000, 100000, 52000) }, ctx(ADMIN));
  assert.deepStrictEqual(p.payouts, [40000, 100000, 52000]);
  assert.deepStrictEqual(p.legIds.map((id) => legDoc(db, id).attributes.payout), [40000, 100000, 52000]);
  assert.ok(p.legIds.every((id) => legDoc(db, id).status === 'active' && legDoc(db, id).attributes.chainMode === 'assemble_all'));
  assert.ok(legIds.every((id) => legDoc(db, id).status === 'cancelled'), 'eski LEG\'lar bekor');
  const ship = shipOf(db, shipmentId);
  assert.strictEqual(ship.chain.deadlineAt.getTime(), NOW.getTime() + H48, 'muddat o\'zgarmaydi');
  assert.strictEqual(ship.chain.claimed, 0);
  assert.strictEqual(ship.chain.legCount, 3);
  const internal = db.docs.get(`shipments/${shipmentId}/private/internal`);
  assert.deepStrictEqual(internal.legPayouts.map((x) => x.amount), [40000, 100000, 52000]);
  assert.strictEqual(internal.platformShare, 48000, 'platforma ulushi o\'zgarmaydi');
  const audit = db.dump('logistics_audit')[`payout_override_${shipmentId}_v2`];
  assert.deepStrictEqual(audit.before, [48000, 96000, 48000]);
  assert.deepStrictEqual(audit.after, [40000, 100000, 52000]);
  assert.strictEqual(audit.by, ADMIN);
  // Qulfdan keyin — rad.
  await accept(db, p.legIds[0], K1); await accept(db, p.legIds[1], F1); await accept(db, p.legIds[2], F1);
  await assert.rejects(() => plan({ shipmentId, legs: LEGS, payoutOverrides: ov(40000, 100000, 52000) }, ctx(ADMIN)), reason('CHAIN_LOCKED'));
  // Sequential — rad.
  const db2 = fresh(seed());
  const s = await newChain(db2);
  await assert.rejects(() => api.makeAdminPlanShipmentRoute(deps(db2))({ shipmentId: s.shipmentId, legs: [{}], payoutOverrides: [{ legIndex: 0, amount: 192000 }] }, ctx(ADMIN)),
    reason('payout_override_chain_only'));
});

ok('legChainSweeper: zanjirning draft qolgan LEG\'larini ochadi (trigger yiqilgan)', async () => {
  const db = fresh();
  const { shipmentId, legIds } = await newChain(db);
  // Trigger'siz to'lov — muddat yo'q, LEG'lar draft.
  await db.collection('shipments').doc(shipmentId).update({ paymentStatus: 'escrow_funded', status: 'ready', fundedAt: NOW });
  const sw = await api.makeLegChainSweeper(deps(db, at(600 * 1000)))();
  assert.strictEqual(sw.failed, 0);
  assert.ok(legIds.every((id) => legDoc(db, id).status === 'active'));
  assert.strictEqual(shipOf(db, shipmentId).chain.deadlineAt.getTime(), NOW.getTime() + H48, 'muddat fundedAt dan');
});

ok('sequential privacy: LEG-2 LEG-1 dan oldin olinsa olish telefoni jo\'natuvchi EMAS; K1 olgach — K1', async () => {
  const db = fresh(seed());
  const d = deps(db);
  const s = await newChain(db);
  await fund(db, s.shipmentId);
  const p = await api.makeAdminPlanShipmentRoute(d)({ shipmentId: s.shipmentId, reason: 'Urganch orqali', legs: [
    { to: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
    { from: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
  ] }, ctx(ADMIN));
  const [leg0, leg1] = p.legIds;
  // LEG-2 ni majburan ochamiz (masalan admin/sweeper) — LEG-1 hali hech kimda.
  await api.activateLeg(d, leg1);
  await accept(db, leg1, F1);
  const m = matchOf(db, leg1, F1);
  assert.strictEqual(m.contactUnlocked.ownerPhone, null, 'avval jo\'natuvchi telefoni (currentCustodian) ochilardi');
  noSenderPhone(m, 'LEG-2');
  await accept(db, leg0, K1);
  assert.strictEqual(matchOf(db, leg1, F1).contactUnlocked.ownerPhone, K1);
  assert.strictEqual(matchOf(db, leg0, K1).contactUnlocked.nextProviderPhone, F1);
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
