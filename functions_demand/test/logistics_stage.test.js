/**
 * AVA Logistics — ishga tushirish bosqichi INTERNAL → PUBLIC (CLAUDE.md 42).
 *
 *   node functions_demand/test/logistics_stage.test.js
 *
 * Qulflanadi:
 *   - standart (stage yozilmagan) = INTERNAL, ro'yxat bo'sh → hech kim (yopiq)
 *   - INTERNAL: faqat testerIds narx oladi / buyurtma beradi; boshqalar
 *     `module_internal_only` (unavailable), hujjat YOZILMAYDI
 *   - INTERNAL: LEG faqat ro'yxatdagi ijrochiga mos keladi; tashqi ijrochi
 *     acceptLeg qila olmaydi (match yo'q)
 *   - testerIds har xil yozuvda (+998…, 9 xonali) — kanonik solishtiriladi
 *   - getLogisticsAccess: ro'yxatni qaytarmaydi; modul o'chiq — allowed=false
 *   - PUBLIC: hamma
 */
const assert = require('assert');
const api = require('../api/logistics');
const L = require('../core/logistics');
const tariffCore = require('../core/tariff');
const config = require('../core/config');
const {
  OWNER, K1, F1, ctx, makeDb, seed, orderPayload, deps, fund, legOf,
} = require('./helpers/logistics_harness');

const STRANGER = '998907770007';

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

function cfg(logistics) {
  return { 'module_config/logistics_all': { enabled: true, matchingEnabled: true, pushEnabled: false, logistics } };
}
function fresh(extra) {
  config.clearCache(); tariffCore.clearCache();
  return makeDb(seed(extra));
}

// ── sof funksiya ─────────────────────────────────────────────────────
ok('stageOf: yo\'q / noma\'lum → internal (yopiq); lug\'at: off | internal | pilot | public (42-band, D8)', () => {
  assert.strictEqual(L.stageOf({}), 'internal');
  assert.strictEqual(L.stageOf({ logistics: {} }), 'internal');
  assert.strictEqual(L.stageOf({ logistics: { stage: 'beta' } }), 'internal', 'noma\'lum qiymat — yopiq tomonga');
  assert.strictEqual(L.stageOf({ logistics: { stage: 'PUBLIC' } }), 'internal', 'katta harf — noma\'lum');
  assert.strictEqual(L.stageOf({ logistics: { stage: 'public' } }), 'public');
  assert.strictEqual(L.stageOf({ logistics: { stage: 'pilot' } }), 'pilot');
  assert.strictEqual(L.stageOf({ logistics: { stage: 'off' } }), 'off');
  assert.deepStrictEqual(Object.values(L.STAGE), ['off', 'internal', 'pilot', 'public']);
  assert.strictEqual(config.DEFAULTS.logistics.stage, 'internal');
  assert.deepStrictEqual(config.DEFAULTS.logistics.testerIds, []);
});

ok('isStageAllowed: OFF — hech kim (sinovchi ham); PILOT — INTERNAL kabi faqat ro\'yxat (PILOT qoidasi UNKNOWN); PUBLIC — hamma', () => {
  const list = ['+998 90 111 00 01'];
  const at = (stage) => ({ logistics: { stage, testerIds: list } });
  assert.strictEqual(L.isStageAllowed(at('off'), OWNER), false, 'off: sinovchi ham yo\'q');
  assert.strictEqual(L.isStageAllowed({ logistics: { stage: 'off', testerIds: list } }, STRANGER), false);
  assert.strictEqual(L.isStageAllowed(at('pilot'), OWNER), true);
  assert.strictEqual(L.isStageAllowed(at('pilot'), STRANGER), false);
  assert.strictEqual(L.isStageAllowed(at('internal'), OWNER), true);
  assert.strictEqual(L.isStageAllowed(at('internal'), STRANGER), false);
  assert.strictEqual(L.isStageAllowed(at('public'), STRANGER), true);
  assert.strictEqual(L.isStageAllowed({ logistics: { stage: 'off' } }, ''), false);
});

ok('isStageAllowed: kanonik solishtirish (+998…, 9 xonali); bo\'sh ID / ro\'yxat emas — rad', () => {
  const c = { logistics: { stage: 'internal', testerIds: ['+998 90 111 00 01', '902220002'] } };
  assert.strictEqual(L.isStageAllowed(c, OWNER), true);
  assert.strictEqual(L.isStageAllowed(c, K1), true);
  assert.strictEqual(L.isStageAllowed(c, STRANGER), false);
  assert.strictEqual(L.isStageAllowed(c, ''), false);
  assert.strictEqual(L.isStageAllowed({ logistics: { testerIds: 'not-a-list' } }, OWNER), false);
  assert.strictEqual(L.isStageAllowed({ logistics: { stage: 'public' } }, ''), true);
});

// ── jo'natuvchi ──────────────────────────────────────────────────────
ok('standart (stage yozilmagan): hech kim narx olmaydi — module_internal_only', async () => {
  const db = fresh({ 'module_config/logistics_all': { enabled: true, matchingEnabled: true, pushEnabled: false } });
  await assert.rejects(() => api.makeQuoteLogisticsOrder({ db })(orderPayload(), ctx(OWNER)),
    (e) => e.code === 'unavailable' && e.details.reason === 'module_internal_only');
});

ok('INTERNAL: sinovchi narx oladi va buyurtma beradi; begona — rad, hujjat YOZILMAYDI', async () => {
  const db = fresh(cfg({ stage: 'internal', testerIds: [OWNER] }));
  const q = await api.makeQuoteLogisticsOrder({ db })(orderPayload(), ctx(OWNER));
  assert.strictEqual(q.total, 10000);
  const r = await api.makeCreateLogisticsOrder(deps(db))(orderPayload(), ctx(OWNER));
  assert.strictEqual(r.duplicate, false);

  const before = Object.keys(db.dump('shipments')).length;
  await assert.rejects(() => api.makeQuoteLogisticsOrder({ db })(orderPayload(), ctx(STRANGER)),
    (e) => e.code === 'unavailable' && e.details.reason === 'module_internal_only');
  await assert.rejects(() => api.makeCreateLogisticsOrder(deps(db))(orderPayload({ clientRequestId: 'req-stranger-01' }), ctx(STRANGER)),
    (e) => e.details.reason === 'module_internal_only');
  assert.strictEqual(Object.keys(db.dump('shipments')).length, before, 'begona buyurtmasi yozilmadi');
  assert.strictEqual(Object.keys(db.dump('demand_idempotency')).filter((k) => k.startsWith(STRANGER)).length, 0);
});

// ── ijrochi ──────────────────────────────────────────────────────────
ok('INTERNAL: LEG faqat ro\'yxatdagi ijrochiga mos; tashqi ijrochi acceptLeg qila olmaydi', async () => {
  // OWNER + K1 sinovchi; F1 (mos keladigan freight) — ro'yxatda YO'Q.
  const db = fresh(cfg({ stage: 'internal', testerIds: [OWNER, K1] }));
  const d = deps(db);
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload(), ctx(OWNER));
  const shipmentId = r.shipmentIds[0];
  const legId = legOf(db, shipmentId)[0];
  const act = await fund(db, shipmentId);
  assert.strictEqual(act.activated, true);
  const matches = db.dump('demand_matches');
  assert.ok(matches[`${legId}_${K1}`], 'K1 sinovchi — mos');
  assert.ok(!matches[`${legId}_${F1}`], 'F1 sinov ro\'yxatida yo\'q — mos EMAS');
  await assert.rejects(() => api.makeAcceptLeg(d)({ legId }, ctx(F1)), (e) => e.code === 'permission-denied');
  const acc = await api.makeAcceptLeg(d)({ legId }, ctx(K1));
  assert.strictEqual(acc.ok, true);
});

ok('PUBLIC: hamma narx oladi; LEG ro\'yxatsiz ijrochilarga ham mos', async () => {
  const db = fresh(cfg({ stage: 'public', testerIds: [] }));
  const d = deps(db);
  const q = await api.makeQuoteLogisticsOrder({ db })(orderPayload(), ctx(STRANGER));
  assert.strictEqual(q.total, 10000);
  const r = await api.makeCreateLogisticsOrder(d)(orderPayload(), ctx(OWNER));
  const legId = legOf(db, r.shipmentIds[0])[0];
  await fund(db, r.shipmentIds[0]);
  const matches = db.dump('demand_matches');
  assert.ok(matches[`${legId}_${K1}`] && matches[`${legId}_${F1}`]);
});

ok('OFF: sinovchi ham narx ololmaydi (module_internal_only), getLogisticsAccess false; PILOT: sinovchi oladi', async () => {
  const off = fresh(cfg({ stage: 'off', testerIds: [OWNER] }));
  await assert.rejects(() => api.makeQuoteLogisticsOrder({ db: off })(orderPayload(), ctx(OWNER)),
    (e) => e.code === 'unavailable' && e.details.reason === 'module_internal_only');
  assert.deepStrictEqual(await api.makeGetLogisticsAccess({ db: off })({}, ctx(OWNER)), { allowed: false, stage: 'off' });
  const pilot = fresh(cfg({ stage: 'pilot', testerIds: [OWNER] }));
  assert.strictEqual((await api.makeQuoteLogisticsOrder({ db: pilot })(orderPayload(), ctx(OWNER))).total, 10000);
  await assert.rejects(() => api.makeQuoteLogisticsOrder({ db: pilot })(orderPayload(), ctx(STRANGER)),
    (e) => e.details.reason === 'module_internal_only');
  assert.deepStrictEqual(await api.makeGetLogisticsAccess({ db: pilot })({}, ctx(OWNER)), { allowed: true, stage: 'pilot' });
});

// ── ilova kirishi ────────────────────────────────────────────────────
ok('getLogisticsAccess: sinovchi true, begona false; ro\'yxat QAYTARILMAYDI; o\'chiq modul — false', async () => {
  const db = fresh(cfg({ stage: 'internal', testerIds: [OWNER] }));
  const fn = api.makeGetLogisticsAccess({ db });
  assert.deepStrictEqual(await fn({}, ctx(OWNER)), { allowed: true, stage: 'internal' });
  assert.deepStrictEqual(await fn({}, ctx(STRANGER)), { allowed: false, stage: 'internal' });
  await assert.rejects(() => fn({}, {}), (e) => e.code === 'unauthenticated');
  const off = fresh({ 'module_config/logistics_all': { enabled: false, logistics: { stage: 'public' } } });
  assert.strictEqual((await api.makeGetLogisticsAccess({ db: off })({}, ctx(OWNER))).allowed, false);
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
