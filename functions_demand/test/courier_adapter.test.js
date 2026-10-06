/**
 * `courier` adapteri — 13.6.3, shahar ichi kuryer.
 *
 *   node functions_demand/test/courier_adapter.test.js
 *
 * Bu `provider_presence` manbasini ISHLATADIGAN birinchi modul. Test
 * ikkita narsani qulflaydi:
 *   1. `dispatch` rejimi reestr orqali to'g'ri e'lon qilinadi — yadroning
 *      push limiti, `assignmentDeadline` va to'lqinlari shunga bog'liq;
 *   2. joylashuvsiz nomzod `dispatch`da MUMKIN EMAS — aks holda mijozga
 *      «qancha vaqtda yetib keladi» deb aytib bo'lmaydi.
 */
const assert = require('assert');
const courier = require('../adapters/courier');
const presenceGeo = require('../sources/presence_geo');
const registry = require('../core/registry');
const baseConfig = require('../core/config');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const cfg = { ...baseConfig, searchRadiusKm: 15, maxLocationAgeSec: 120 };

/** Urganch markazi. */
const LAT = 41.5500;
const LNG = 60.6300;

function demand(over = {}) {
  return {
    id: 'd1',
    module: 'courier',
    location: { lat: LAT, lng: LNG, districtId: 'urganch_sh', regionId: 'xorazm' },
    attributes: {},
    ...over,
  };
}

function candidate(over = {}) {
  return {
    providerId: '998901110001',
    presence: { lat: LAT, lng: LNG, vehicle: 'car', updatedAt: new Date() },
    ...over,
  };
}

// ─── reestr va rejim ──────────────────────────────────────────────────
ok('reestrga ulangan va rejimi `dispatch`', () => {
  assert.strictEqual(registry.getAdapter('courier'), courier);
  assert.strictEqual(registry.modeFor('courier'), 'dispatch');
  assert.ok(registry.enabledModules().includes('courier'));
});

ok('`service` moduli buzilmagan', () => {
  assert.strictEqual(registry.modeFor('service'), 'quote');
});

ok('manbalar: `presence` BIRINCHI', () => {
  assert.strictEqual(courier.sources[0], presenceGeo.fetchCandidates,
      'dedupe `presence`ni birinchi kelgan nusxaga biriktiradi');
  assert.strictEqual(courier.sources.length, 2);
});

// ─── isEligible ───────────────────────────────────────────────────────
ok('joylashuvsiz nomzod rad etiladi', () => {
  assert.strictEqual(
      courier.isEligible(demand(), candidate({ presence: null }), cfg), 'no_presence');
  assert.strictEqual(
      courier.isEligible(demand(), candidate({ presence: {} }), cfg), 'no_presence');
});

ok('koordinatasi null bo`lgan presence ham rad etiladi', () => {
  const c = candidate({ presence: { lat: null, lng: null, updatedAt: new Date() } });
  assert.strictEqual(courier.isEligible(demand(), c, cfg), 'no_presence');
});

ok('koordinatasiz TALAB rad etiladi', () => {
  assert.strictEqual(
      courier.isEligible(demand({ location: {} }), candidate(), cfg),
      'no_demand_location');
});

ok('radius ichidagi kuryer o`tadi', () => {
  assert.strictEqual(courier.isEligible(demand(), candidate(), cfg), true);
});

ok('radiusdan uzoqdagi kuryer rad etiladi', () => {
  // Toshkent — ~450 km.
  const c = candidate({
    presence: { lat: 41.3111, lng: 69.2797, vehicle: 'car', updatedAt: new Date() },
  });
  assert.strictEqual(courier.isEligible(demand(), c, cfg), 'too_far');
});

ok('katak chetidagi, lekin radius ichidagi kuryer o`tadi', () => {
  // ~8 km shimolda: geohash katagi boshqa bo`lishi mumkin, radius ichida.
  const c = candidate({
    presence: { lat: LAT + 0.072, lng: LNG, vehicle: 'car', updatedAt: new Date() },
  });
  assert.strictEqual(courier.isEligible(demand(), c, cfg), true);
});

// ─── score: GPS yangiligi ─────────────────────────────────────────────
ok('yangi GPS eskisidan yuqori baholanadi', () => {
  const fresh = courier.score(demand(), candidate({
    presence: { lat: LAT, lng: LNG, updatedAt: new Date() },
  }), cfg);
  const old = courier.score(demand(), candidate({
    presence: { lat: LAT, lng: LNG, updatedAt: new Date(Date.now() - 100 * 1000) },
  }), cfg);
  assert.ok(fresh > old, `yangi ${fresh} eski ${old} dan katta bo'lishi kerak`);
});

ok('chegaradan eski GPS bonus bermaydi', () => {
  const s = courier.score(demand(), candidate({
    presence: { lat: LAT, lng: LNG, updatedAt: new Date(Date.now() - 200 * 1000) },
  }), cfg);
  assert.strictEqual(s, 0);
});

ok('updatedAt yo`q bo`lsa bonus 0', () => {
  assert.strictEqual(courier.score(demand(), candidate({
    presence: { lat: LAT, lng: LNG },
  }), cfg), 0);
});

ok('bonus adapter shartnomasi chegarasida (-0.1 .. +0.1)', () => {
  for (const ageSec of [0, 1, 30, 60, 119, 120, 500]) {
    const s = courier.score(demand(), candidate({
      presence: { lat: LAT, lng: LNG, updatedAt: new Date(Date.now() - ageSec * 1000) },
    }), cfg);
    assert.ok(s >= 0 && s <= 0.1, `ageSec=${ageSec} -> ${s}`);
  }
});

// ─── proyeksiya va push ───────────────────────────────────────────────
ok('proyeksiyada faqat sxemada BOR attributlar bo`ladi', () => {
  const p = courier.buildProjection(demand({
    attributes: { preferredTimeOfDay: 'kunduzi', accessNotes: 'ikkinchi qavat' },
  }), cfg);
  assert.deepStrictEqual(
      Object.keys(p.attributes).sort(), ['accessNotes', 'preferredTimeOfDay']);
  assert.strictEqual(p.attributes.preferredTimeOfDay, 'kunduzi');
});

ok('MAXFIYLIK: proyeksiyada telefon va aniq manzil YO`Q', () => {
  const p = courier.buildProjection(demand(), cfg);
  const flat = JSON.stringify(p);
  assert.ok(!flat.includes('contact'), 'kontakt sizib chiqdi');
  assert.ok(!('phone' in p), 'telefon sizib chiqdi');
});

ok('accessNotes 200 belgidan uzun bo`lmaydi', () => {
  const p = courier.buildProjection(demand({
    attributes: { accessNotes: 'x'.repeat(500) },
  }), cfg);
  assert.strictEqual(p.attributes.accessNotes.length, 200);
});

ok('push sarlavhasi `dispatch` shaklida', () => {
  const t = courier.buildPushTemplate(demand(), {
    categoryName: 'Yetkazib berish', districtName: 'Urganch', distanceKm: 2.4,
  });
  assert.ok(t.title.includes('qabul qilasizmi'), `kutilmagan sarlavha: ${t.title}`);
  assert.ok(t.body.includes('Urganch'));
  assert.ok(t.body.includes('2.4 km'));
});

// ──────────────────────────────────────────────────────────────────────
(async () => {
  for (const t of tests) {
    try {
      await t.fn();
      passed += 1;
      console.log(`  OK  ${t.name}`);
    } catch (e) {
      console.error(`  XATO ${t.name}\n       ${e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
