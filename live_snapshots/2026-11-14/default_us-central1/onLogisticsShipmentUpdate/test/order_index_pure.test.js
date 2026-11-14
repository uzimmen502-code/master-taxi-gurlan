/**
 * `order_index.js` — тоза мантиқ (эмуляторсиз): календарь, ҳолат жадвали,
 * «тиқилиб қолган» вақти.   node functions/test/order_index_pure.test.js
 */
'use strict';
const assert = require('assert');
const oi = require('../order_index');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
const CAL = oi.DEFAULT_CALENDAR;
const MIN = 60000;
/** Тошкент маҳаллий вақти → UTC ms. */
const T = (y, mo, d, h = 0, mi = 0) => Date.UTC(y, mo - 1, d, h, mi) - 5 * 60 * MIN;
const iso = (msv) => new Date(msv + 5 * 60 * MIN).toISOString().slice(0, 16); // маҳаллий
// 2026-10-12 — Душанба, 2026-10-17 — Шанба, 2026-10-18 — Якшанба.

check('C1 иш вақти ичида — дақиқалар оддий қўшилади', () => {
  assert.strictEqual(iso(oi.addWorkMinutes(T(2026, 10, 12, 10, 0), 120, CAL)), '2026-10-12T12:00');
});
check('C2 кечқурун 22:00 даги буюртма — эртага 08:00 дан саналади', () => {
  assert.strictEqual(iso(oi.addWorkMinutes(T(2026, 10, 12, 22, 0), 120, CAL)), '2026-10-13T10:00');
});
check('C3 19:00 + 2 соат → эртага 09:00 (20:00 да тўхтайди)', () => {
  assert.strictEqual(iso(oi.addWorkMinutes(T(2026, 10, 12, 19, 0), 120, CAL)), '2026-10-13T09:00');
});
check('C4 Шанба 19:00 + 2 соат → Душанба 09:00 (Якшанба дам)', () => {
  assert.strictEqual(iso(oi.addWorkMinutes(T(2026, 10, 17, 19, 0), 120, CAL)), '2026-10-19T09:00');
});
check('C5 3 иш куни: Жума 15:00 → Сешанба 15:00 (Якшанба саналмайди)', () => {
  assert.strictEqual(iso(oi.addWorkDays(T(2026, 10, 16, 15, 0), 3, CAL)), '2026-10-20T15:00');
});
check('C6 байрам куни ҳам саналмайди', () => {
  const cal = { ...CAL, holidays: ['2026-10-13'] };
  assert.strictEqual(iso(oi.addWorkDays(T(2026, 10, 12, 10, 0), 1, cal)), '2026-10-14T10:00');
});
check('C7 чегара: айнан 20:00 — ёпиқ, 08:00 — очиқ', () => {
  assert.strictEqual(iso(oi.alignToWork(T(2026, 10, 12, 20, 0), CAL)), '2026-10-13T08:00');
  assert.strictEqual(iso(oi.alignToWork(T(2026, 10, 12, 8, 0), CAL)), '2026-10-12T08:00');
});

const meta = (extra = {}) => ({ sourceCollection: 'x', sourceId: 'id1', eventMs: T(2026, 10, 12, 10, 0), ...extra });
const build = (col, data, prev = null, extra = {}, legExtra = {}) =>
  oi.buildIndexDoc(prev, oi.normalize(col, data, legExtra), meta(extra));

check('N1 нон: new → NEW, 15 дақиқа 24/7 (тунда ҳам)', () => {
  const d = build('orders', { type: 'bread', status: 'new', statusUpdatedAt: T(2026, 10, 12, 23, 50), userPhone: '998901234567', total: 8000 });
  assert.strictEqual(d.module, 'bread');
  assert.strictEqual(d.normStatus, 'NEW');
  assert.strictEqual(iso(d.stuckAtMs), '2026-10-13T00:05');
  assert.strictEqual(d.customerTail, '4567');
  assert.strictEqual(d.amount, 8000);
});
check('N2 «Овқат» буюртмаси индексга тушмайди', () => {
  assert.strictEqual(oi.normalize('orders', { type: 'food', status: 'new' }), null);
});
check('N3 якунланган буюртмада stuckAt йўқ', () => {
  const d = build('orders', { type: 'bread', status: 'delivered', statusUpdatedAt: T(2026, 10, 1) });
  assert.strictEqual(d.final, true);
  assert.strictEqual(d.stuckAtMs, null);
});
check('N4 ўзи олиб кетади + ready → курьер кутмайди, чегара йўқ', () => {
  const d = build('orders', { type: 'bread', status: 'ready', fulfillmentMode: 'pickup', statusUpdatedAt: T(2026, 10, 12, 10) });
  assert.strictEqual(d.normStatus, 'ACCEPTED');
  assert.strictEqual(d.stage, 'waiting_pickup');
  assert.strictEqual(d.stuckAtMs, null);
});
check('N5 улгуржи: қабулдан 3 иш куни (cycle), иш вақтида', () => {
  const p1 = build('orders', { type: 'platform', status: 'accepted', statusUpdatedAt: T(2026, 10, 16, 15) });
  assert.strictEqual(p1.module, 'wholesale');
  assert.strictEqual(p1.stuckRule, 'cycle');
  assert.strictEqual(iso(p1.stuckAtMs), '2026-10-20T15:00');
  // Курьерга ўтди — cycle боши сақланади.
  const p2 = build('orders', { type: 'platform', status: 'in_delivery', statusUpdatedAt: T(2026, 10, 19, 9) }, p1);
  assert.strictEqual(p2.cycleSinceMs, p1.cycleSinceMs);
  assert.strictEqual(iso(p2.stuckAtMs), '2026-10-20T15:00');
});
check('N6 ресторан тайёрланмоқда: prepTimeMin + 15', () => {
  const d = build('orders', { type: 'restaurant', restaurantStatus: 'accepted', prepTimeMin: 30, statusUpdatedAt: T(2026, 10, 12, 12), restaurantName: 'Osh markazi' });
  assert.strictEqual(d.module, 'restaurant');
  assert.strictEqual(d.stage, 'preparing');
  assert.strictEqual(iso(d.stuckAtMs), '2026-10-12T12:45');
  assert.strictEqual(d.title, 'Osh markazi');
});
check('N7 ресторан placed — сервер ўзи 5 дақда рад этади, чегара йўқ', () => {
  const d = build('orders', { type: 'restaurant', restaurantStatus: 'placed', statusUpdatedAt: T(2026, 10, 12, 12) });
  assert.strictEqual(d.normStatus, 'NEW');
  assert.strictEqual(d.stuckAtMs, null);
});
check('N8 босқич ўзгармаса stageSince сақланади (picked → arrived)', () => {
  const a = build('orders', { type: 'restaurant', restaurantStatus: 'picked', statusUpdatedAt: T(2026, 10, 12, 12) });
  const b = build('orders', { type: 'restaurant', restaurantStatus: 'arrived', statusUpdatedAt: T(2026, 10, 12, 12, 40) }, a);
  assert.strictEqual(b.stageSinceMs, a.stageSinceMs);
  assert.strictEqual(iso(b.stuckAtMs), '2026-10-12T12:45');
});
check('N9 гилам: олиб кетилгандан 7 иш куни; тайёр турса 3 иш куни (қайси эрта)', () => {
  const picked = build('carpet_wash_orders', { status: 'picked_up', updatedAt: T(2026, 10, 12, 10) });
  assert.strictEqual(picked.module, 'carpet');
  assert.strictEqual(picked.stuckRule, 'cycle');
  assert.strictEqual(iso(picked.stuckAtMs), '2026-10-20T10:00'); // 7 иш куни (Якшанбасиз)
  const ready = build('carpet_wash_orders', { status: 'ready', updatedAt: T(2026, 10, 14, 10) }, picked);
  assert.strictEqual(ready.stuckRule, 'stage:ready_return');
  assert.strictEqual(iso(ready.stuckAtMs), '2026-10-17T10:00');
  const late = build('carpet_wash_orders', { status: 'ready', updatedAt: T(2026, 10, 19, 10) }, picked);
  assert.strictEqual(late.stuckRule, 'cycle'); // 7 кун эртароқ тугайди
});
check('N10 гилам қайтаришда курьер — returnCourierId', () => {
  const d = build('carpet_wash_orders', { status: 'return_in_delivery', pickupCourierId: 'A', returnCourierId: 'B', updatedAt: T(2026, 10, 12, 10) });
  assert.strictEqual(d.courierId, 'B');
});
check('N11 сут: олинди, якунланмаган — 1 иш куни', () => {
  const d = build('agro_pickup_orders', { status: 'picked_up', updatedAt: T(2026, 10, 17, 18) });
  assert.strictEqual(d.module, 'milk');
  assert.strictEqual(iso(d.stuckAtMs), '2026-10-19T18:00');
});
check('N12 Logistics: тўлов кутилмоқда — тиқилиб қолган эмас', () => {
  const d = build('shipments', { status: 'awaiting_payment', updatedAt: T(2026, 10, 1) });
  assert.strictEqual(d.stage, 'awaiting_payment');
  assert.strictEqual(d.stuckAtMs, null);
});
check('N13 Logistics: LEG муддати ўтди — дарҳол', () => {
  const at = T(2026, 10, 12, 11);
  const d = build('shipments', { status: 'ready', legProblem: { kind: 'leg_expired', at }, fundedAt: T(2026, 10, 9, 9), updatedAt: at });
  assert.strictEqual(d.stage, 'leg_expired');
  assert.strictEqual(d.stuckAtMs, at);
});
check('N14 Logistics: line_haul LEG — 3 иш куни; маҳаллий — 1', () => {
  const base = { status: 'in_transit', currentLegId: 'L2', updatedAt: T(2026, 10, 12, 10), fundedAt: T(2026, 10, 12, 9) };
  const lh = build('shipments', base, null, {}, { legKind: 'line_haul' });
  assert.strictEqual(lh.stage, 'leg_linehaul_transit');
  assert.strictEqual(iso(lh.stuckAtMs), '2026-10-15T10:00');
  const lm = build('shipments', base, null, {}, { legKind: 'last_mile' });
  assert.strictEqual(lm.stage, 'leg_local_transit');
  assert.strictEqual(iso(lm.stuckAtMs), '2026-10-13T10:00');
  const directSame = build('shipments', base, null, {}, { legKind: 'direct', legCrossRegion: false });
  assert.strictEqual(directSame.stage, 'leg_local_transit');
});
check('N15 Logistics: эшикдан эшиккача 6 иш куни (fundedAt дан) босқичдан эрта бўлса', () => {
  const d = build('shipments', { status: 'in_transit', currentLegId: 'L3', updatedAt: T(2026, 10, 20, 10), fundedAt: T(2026, 10, 12, 9) }, null, {}, { legKind: 'line_haul' });
  assert.strictEqual(d.stuckRule, 'cycle');
  assert.strictEqual(iso(d.stuckAtMs), '2026-10-19T09:00');
});
check('N16 курьер талаби: фақат module=courier; LEG — йўқ', () => {
  assert.strictEqual(oi.normalize('demands', { module: 'logistics', status: 'active' }), null);
  const d = build('demands', { module: 'courier', status: 'active', updatedAt: T(2026, 10, 12, 23, 0), ownerId: '998901112233', budget: { max: 15000.4 } });
  assert.strictEqual(d.normStatus, 'WAITING_COURIER');
  assert.strictEqual(iso(d.stuckAtMs), '2026-10-12T23:15'); // 24/7
  assert.strictEqual(d.amount, 15000);
});
check('N17 номаълум статус → UNKNOWN, stuckAt йўқ (тахмин қилинмайди)', () => {
  const d = build('carpet_wash_orders', { status: 'teleported', updatedAt: T(2026, 10, 12) });
  assert.strictEqual(d.normStatus, 'UNKNOWN');
  assert.strictEqual(d.stuckAtMs, null);
});
check('N18 созламадан чегара ўзгаради (merge), бошқалари сақланади', () => {
  const rules = oi.mergeRules({ rules: { bread: { stages: { new: { min: 30 } } } } });
  assert.strictEqual(rules.bread.stages.new.min, 30);
  assert.strictEqual(rules.bread.stages.accepted.min, 60);
  const d = oi.buildIndexDoc(null, oi.normalize('orders', { type: 'bread', status: 'new', statusUpdatedAt: T(2026, 10, 12, 10) }), meta({ rules }));
  assert.strictEqual(iso(d.stuckAtMs), '2026-10-12T10:30');
});
check('N19 вақт майдони йўқ (эски ҳужжат) — sinceApprox белгиланади', () => {
  const d = build('carpet_wash_orders', { status: 'new' });
  assert.strictEqual(d.sinceApprox, true);
});

const failed = results.filter((x) => !x).length;
console.log(`\n${results.length - failed}/${results.length} order_index pure checks passed.`);
process.exit(failed ? 1 : 0);
