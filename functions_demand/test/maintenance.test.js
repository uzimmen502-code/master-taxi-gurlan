/**
 * Sweeper'lar — AVA Logistics LEG'lari bilan (FakeFirestore).
 *
 *   node functions_demand/test/maintenance.test.js
 *
 * Qulflanadi (ega qarori 2026-10-07):
 *   - `reopenStaleAssignments` logistika LEG'iga TEGMAYDI (LEG-2 kuryeri
 *     LEG-1 kelguncha soatlab kutadi — chiqarib tashlash + NO_SHOW xato);
 *     oddiy `service` talabi esa avvalgidek 120 daqiqadan keyin qayta ochiladi.
 *   - `expireDemandsSweeper` logistika LEG'ini `expired` qilganda jo'natmaga
 *     `legProblem` yozadi (admin ko'radi, `adminReactivateLeg` bilan ochadi);
 *     boshqa modul talabida jo'natma yo'q — hech narsa yozilmaydi.
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const maint = require('../api/maintenance');
const config = require('../core/config');

const NOW = new Date('2026-10-07T10:00:00Z');
const hoursAgo = (h) => new Date(NOW.getTime() - h * 3600 * 1000);
const OWNER = '998901110001';
const K1 = '998902220002';

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

function seed() {
  return {
    'module_config/global': { enabled: true, matchingEnabled: true, pushEnabled: false },
    // service: 3 soat oldin qabul qilingan, ish boshlanmagan → qayta ochiladi.
    'demands/svc1': {
      module: 'service', mode: 'quote', status: 'accepted', ownerId: OWNER,
      location: { regionId: 'xorazm', districtId: 'gurlan' },
      assignment: { providerId: K1, offerId: 'o1', acceptedAt: hoursAgo(3) },
      timeWindow: { expiresAt: new Date(NOW.getTime() + 3600 * 1000) },
      createdAt: hoursAgo(5), updatedAt: hoursAgo(3),
    },
    [`demand_matches/svc1_${K1}`]: { demandId: 'svc1', providerId: K1, status: 'accepted' },
    // logistics LEG: 3 soat oldin qabul qilingan, LEG-1 hali kelmagan → TEGILMAYDI.
    'demands/leg2': {
      module: 'logistics', mode: 'quote', status: 'accepted', ownerId: OWNER,
      location: { regionId: 'xorazm', districtId: 'urganch_shahri' },
      attributes: { shipmentId: 's1', legIndex: 1, legCount: 2, dependsOnLegId: 'leg1' },
      assignment: { providerId: K1, offerId: null, acceptedAt: hoursAgo(3) },
      timeWindow: { expiresAt: new Date(NOW.getTime() + 2 * 24 * 3600 * 1000) },
      createdAt: hoursAgo(5), updatedAt: hoursAgo(3),
    },
    [`demand_matches/leg2_${K1}`]: { demandId: 'leg2', providerId: K1, status: 'accepted' },
    // logistics LEG: active, muddati o'tgan → expired + shipment.legProblem.
    'demands/leg3': {
      module: 'logistics', mode: 'quote', status: 'active', ownerId: OWNER,
      location: { regionId: 'xorazm', districtId: 'gurlan' },
      attributes: { shipmentId: 's2', legIndex: 0, legCount: 1 },
      assignment: { providerId: null, offerId: null, acceptedAt: null },
      timeWindow: { expiresAt: hoursAgo(1) },
      createdAt: hoursAgo(80), updatedAt: hoursAgo(80),
    },
    'demand_matches/leg3_998903330003': { demandId: 'leg3', providerId: '998903330003', status: 'new' },
    // service: active, muddati o'tgan → expired, jo'natma yo'q.
    'demands/svc2': {
      module: 'service', mode: 'quote', status: 'active', ownerId: OWNER,
      location: { regionId: 'xorazm', districtId: 'gurlan' },
      timeWindow: { expiresAt: hoursAgo(2) },
      createdAt: hoursAgo(10), updatedAt: hoursAgo(10),
    },
    'shipments/s1': { ownerId: OWNER, status: 'in_transit', paymentStatus: 'escrow_funded', legIds: ['leg1', 'leg2'] },
    'shipments/s2': { ownerId: OWNER, status: 'ready', paymentStatus: 'escrow_funded', legIds: ['leg3'] },
  };
}

ok('reopenStaleAssignments: service qayta ochiladi, logistika LEG\'i TEGILMAYDI', async () => {
  const db = new FakeFirestore(seed()); config.clearCache();
  const r = await maint.makeReopenStaleAssignments({ db, now: () => NOW })();
  assert.strictEqual(r.reopened, 1, 'faqat service');
  const svc = db.dump('demands').svc1;
  assert.strictEqual(svc.status, 'active');
  assert.strictEqual(svc.assignment.providerId, null);
  assert.strictEqual(db.dump('demand_matches')[`svc1_${K1}`].status, 'deadline_missed');
  const leg = db.dump('demands').leg2;
  assert.strictEqual(leg.status, 'accepted', 'LEG qabul qilingan holatda qoladi');
  assert.strictEqual(leg.assignment.providerId, K1, 'kuryer chiqarib tashlanmaydi');
  assert.strictEqual(db.dump('demand_matches')[`leg2_${K1}`].status, 'accepted');
  const trust = Object.values(db.dump('trust_events') || {});
  assert.ok(trust.every((e) => e.demandId !== 'leg2'), 'LEG kuryeriga NO_SHOW yozilmaydi');
});

ok('expireDemandsSweeper: logistika LEG\'i expired + shipment.legProblem; service — faqat expired', async () => {
  const db = new FakeFirestore(seed()); config.clearCache();
  const r = await maint.makeExpireSweeper({ db, now: () => NOW })();
  assert.strictEqual(r.expired, 2);
  assert.strictEqual(r.legProblems, 1);
  assert.strictEqual(db.dump('demands').leg3.status, 'expired');
  assert.strictEqual(db.dump('demands').svc2.status, 'expired');
  assert.strictEqual(db.dump('demands').leg2.status, 'accepted', 'muddati o\'tmagan LEG tegilmaydi');
  const s2 = db.dump('shipments').s2;
  assert.deepStrictEqual(s2.legProblem, { legId: 'leg3', kind: 'leg_expired', at: NOW });
  assert.strictEqual(s2.status, 'ready', 'jo\'natma holati o\'zgarmaydi (pul eskrouda)');
  assert.strictEqual(db.dump('shipments').s1.legProblem, undefined);
  assert.strictEqual(db.dump('demand_matches')['leg3_998903330003'].status, 'expired', 'inbox tozalanadi');
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
