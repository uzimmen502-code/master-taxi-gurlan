/**
 * AVA Logistics — avtomatik LEG bo'linishi (`core/relay_split.js`), sof.
 *
 *   node functions_demand/test/relay_split.test.js
 *
 * Qulflanadi (ega qarori 2026-11-07):
 *   - bir tuman → 1 LEG; bir viloyat → 2 LEG (O yoki D markaz bo'lsa 1);
 *     turli viloyat → 3 LEG; viaCapital → poytaxt markazi qo'shiladi;
 *   - markaz yo'q → bitta to'g'ridan-to'g'ri LEG + TRANSFER_POINT_MISSING;
 *   - standart jadval: har viloyat repo geo ma'lumotidagi tuman ID'siga ishora qiladi;
 *     konfig standartni viloyat bo'yicha ustiga yozadi (core/config.js DEFAULTS).
 */
const assert = require('assert');
const path = require('path');
const S = require('../core/relay_split');
const config = require('../core/config');
const DEFAULT_TABLE = require('../core/seed/transfer_points_default.json');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const TP = {
  regions: {
    xorazm: { districtId: 'urganch_shahri', addressText: 'Urganch bekat', lat: 41.55, lng: 60.63 },
    toshkent_shahri: { districtId: 'yunusobod' },
    buxoro: { districtId: 'buxoro_shahri' },
  },
  viaCapital: false,
  capitalRegionId: 'toshkent_shahri',
};
const P = (regionId, districtId, extra = {}) => ({ regionId, districtId, addressText: `${districtId} manzil`, ...extra });
const ids = (plan) => plan.points.map((p) => p.districtId || p.regionId);

ok('bir tuman → 1 LEG (markaz orqali EMAS)', () => {
  const r = S.planRelayPoints(P('xorazm', 'gurlan'), P('xorazm', 'gurlan'), TP);
  assert.strictEqual(r.legCount, 1);
  assert.strictEqual(r.reason, 'same_district');
  assert.strictEqual(r.fallback, null);
});

ok('bir viloyat, boshqa tuman → 2 LEG: O → markaz → D', () => {
  const r = S.planRelayPoints(P('xorazm', 'gurlan'), P('xorazm', 'xiva'), TP);
  assert.strictEqual(r.legCount, 2);
  assert.deepStrictEqual(ids(r), ['gurlan', 'urganch_shahri', 'xiva']);
  assert.strictEqual(r.points[1].addressText, 'Urganch bekat', 'markaz manzili konfigdan');
  assert.ok(r.points[1].geohash, 'markaz koordinatasi bo\'lsa geohash');
});

ok('bir viloyat, O yoki D markazning o\'zi → 1 LEG; D manzili mijozniki qoladi', () => {
  const a = S.planRelayPoints(P('xorazm', 'urganch_shahri'), P('xorazm', 'gurlan'), TP);
  assert.strictEqual(a.legCount, 1);
  const b = S.planRelayPoints(P('xorazm', 'gurlan'), P('xorazm', 'urganch_shahri', { addressText: 'Mijoz uyi' }), TP);
  assert.strictEqual(b.legCount, 1);
  assert.strictEqual(b.segments[0].to.addressText, 'Mijoz uyi', 'markaz bilan ustma-ust tushgan D — D o\'zi');
});

ok('turli viloyat → 3 LEG: O → C(O) → C(D) → D', () => {
  const r = S.planRelayPoints(P('xorazm', 'gurlan'), P('toshkent_shahri', 'chilonzor'), TP);
  assert.strictEqual(r.legCount, 3);
  assert.deepStrictEqual(ids(r), ['gurlan', 'urganch_shahri', 'yunusobod', 'chilonzor']);
  for (let i = 1; i < r.segments.length; i += 1) {
    assert.strictEqual(r.segments[i].from, r.segments[i - 1].to, 'zanjir uzluksiz');
  }
});

ok('turli viloyat, D markazda → 2 LEG; O markazda → 2 LEG', () => {
  const a = S.planRelayPoints(P('xorazm', 'gurlan'), P('toshkent_shahri', 'yunusobod'), TP);
  assert.deepStrictEqual(ids(a), ['gurlan', 'urganch_shahri', 'yunusobod']);
  const b = S.planRelayPoints(P('xorazm', 'urganch_shahri'), P('toshkent_shahri', 'chilonzor'), TP);
  assert.deepStrictEqual(ids(b), ['urganch_shahri', 'yunusobod', 'chilonzor']);
});

ok('viaCapital: Xorazm → Buxoro poytaxt markazi orqali (4 LEG); poytaxtning o\'zi — qo\'shimcha nuqta yo\'q', () => {
  const tp = { ...TP, viaCapital: true };
  const r = S.planRelayPoints(P('xorazm', 'gurlan'), P('buxoro', 'kogon_shahri'), tp);
  assert.deepStrictEqual(ids(r), ['gurlan', 'urganch_shahri', 'yunusobod', 'buxoro_shahri', 'kogon_shahri']);
  assert.strictEqual(r.legCount, 4);
  const t = S.planRelayPoints(P('xorazm', 'gurlan'), P('toshkent_shahri', 'chilonzor'), tp);
  assert.deepStrictEqual(ids(t), ['gurlan', 'urganch_shahri', 'yunusobod', 'chilonzor'], 'poytaxt markazi takrorlanmaydi');
});

ok('markaz yo\'q → 1 to\'g\'ridan-to\'g\'ri LEG + TRANSFER_POINT_MISSING (taxmin YO\'Q)', () => {
  const r = S.planRelayPoints(P('xorazm', 'gurlan'), P('andijon', 'andijon_shahri'), TP);
  assert.strictEqual(r.legCount, 1);
  assert.strictEqual(r.reason, 'fallback');
  assert.deepStrictEqual(r.fallback, { errorCode: 'TRANSFER_POINT_MISSING', missingRegionIds: ['andijon'] });
  const v = S.planRelayPoints(P('xorazm', 'gurlan'), P('buxoro', 'kogon_shahri'),
    { ...TP, viaCapital: true, regions: { ...TP.regions, toshkent_shahri: undefined } });
  assert.deepStrictEqual(v.fallback.missingRegionIds, ['toshkent_shahri'], 'poytaxt markazi yo\'q');
  const bad = S.planRelayPoints(P('xorazm', 'gurlan'), P('xorazm', 'xiva'),
    { regions: { xorazm: { districtId: 'Urganch Shahri!' } } });
  assert.strictEqual(bad.reason, 'fallback', 'yaroqsiz tuman ID — markaz yo\'q deb hisoblanadi');
});

ok('chegaraviy: tumanisiz O (faqat viloyat) — markazgacha alohida LEG', () => {
  const r = S.planRelayPoints({ regionId: 'xorazm', districtId: '' }, P('toshkent_shahri', 'chilonzor'), TP);
  assert.strictEqual(r.legCount, 3);
  const same = S.planRelayPoints({ regionId: 'xorazm', districtId: '' }, { regionId: 'xorazm', districtId: '' }, TP);
  assert.ok(same.legCount >= 1);
});

ok('standart jadval: har tuman ID repo geo ma\'lumotida, aynan shu viloyatda (toshkent_shahri YO\'Q — UNKNOWN)', () => {
  const geo = require(path.join(__dirname, '..', '..', 'functions', 'tools', 'data', 'uzbekistan_geo_data.js'));
  const districtsOf = {};
  const groups = geo.DISTRICTS || geo.districts || geo.DISTRICTS_BY_REGION || {};
  for (const [rid, list] of Object.entries(groups)) districtsOf[rid] = new Set((list || []).map((d) => d.id));
  // Xorazm — alohida seed (functions/tools/seed-service-config.js): urganch_shahri u yerda.
  districtsOf.xorazm = new Set(['urganch_shahri']);
  assert.ok(Object.keys(districtsOf).length >= 13, `geo guruhlari topilmadi: ${Object.keys(geo)}`);
  for (const [rid, tp] of Object.entries(DEFAULT_TABLE.regions)) {
    assert.ok(districtsOf[rid], `viloyat geo ma'lumotida yo'q: ${rid}`);
    assert.ok(districtsOf[rid].has(tp.districtId), `${rid} → ${tp.districtId} repo'da yo'q`);
  }
  assert.strictEqual(DEFAULT_TABLE.regions.toshkent_shahri, undefined);
  assert.strictEqual(Object.keys(DEFAULT_TABLE.regions).length, 13);
});

ok('konfig: standart — sequential, 48 soat, jadval; Firestore viloyat bo\'yicha ustiga yozadi', () => {
  const d = config.DEFAULTS.logistics;
  assert.strictEqual(d.chainMode, 'sequential');
  assert.strictEqual(d.chainAssemblyHours, 48);
  assert.strictEqual(d.transferPoints.regions.xorazm.districtId, 'urganch_shahri');
  const merged = config.deepMerge(config.DEFAULTS, {
    logistics: { transferPoints: { regions: { toshkent_shahri: { districtId: 'yunusobod' }, xorazm: { addressText: 'Bekat' } } } },
  });
  assert.strictEqual(merged.logistics.transferPoints.regions.toshkent_shahri.districtId, 'yunusobod');
  assert.strictEqual(merged.logistics.transferPoints.regions.xorazm.districtId, 'urganch_shahri', 'boshqa maydon saqlanadi');
  assert.strictEqual(merged.logistics.transferPoints.regions.xorazm.addressText, 'Bekat');
  assert.strictEqual(merged.logistics.transferPoints.regions.andijon.districtId, 'andijon_shahri');
  assert.strictEqual(config.DEFAULTS.logistics.transferPoints.regions.toshkent_shahri, undefined, 'standart buzilmaydi');
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
