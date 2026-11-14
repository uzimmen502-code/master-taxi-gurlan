/**
 * Kafe-restoran tarifi — SOF funksiyalar (emulator kerak emas).
 *   node functions/test/restaurant_delivery_tariff_pure.test.js
 *
 * D-REST-2: 2 % faqat taom summasidan, ceil, butun so'm.
 * D-REST-4: 1 km gacha base + har km, 500 ga yaxlit, tunda ×1.5; o'z kuryeri
 *           narxi restoran sozlamasidan; tarif yo'q → null.
 */
'use strict';
const assert = require('assert');
const t = require('../restaurant_delivery_tariff');
const ro = require('../restaurant_orders');

let pass = 0;
let failCount = 0;
function check(name, fn) {
  try { fn(); pass += 1; console.log(`PASS - ${name}`); } catch (e) {
    failCount += 1; console.log(`FAIL - ${name} :: ${e.message}`);
  }
}

// ── AVA ulushi ─────────────────────────────────────────────────────────
check('2 %: 60 000 → 1 200', () => {
  const f = t.computeAvaFee(60000);
  assert.deepStrictEqual({ rateBps: f.rateBps, basis: f.basis, amount: f.amount, version: f.version },
    { rateBps: 200, basis: 60000, amount: 1200, version: 1 });
});
check('2 %: ceil — 33 333 → 667 (666.66 emas)', () => {
  assert.strictEqual(t.computeAvaFee(33333).amount, 667);
});
check('2 %: 1 so\'m → 1 (nol emas)', () => assert.strictEqual(t.computeAvaFee(1).amount, 1));
check('2 %: satr / manfiy / 0 / float rad etiladi', () => {
  for (const bad of ['60000', -1, 0, 60000.5, null, undefined]) {
    assert.throws(() => t.computeAvaFee(bad), /butun/);
  }
});

// ── Tarif hujjati ──────────────────────────────────────────────────────
const doc = { base: 5000, perKm: 1500, nightCoef: 1.5, nightStart: 23, nightEnd: 6, roadFactor: 1.3, maxKm: 12, version: 3,
  regions: { xorazm: { base: 4000 } } };
check('resolveDeliveryPrices: global', () => {
  const p = t.resolveDeliveryPrices(doc, 'tashkent');
  assert.strictEqual(p.base, 5000); assert.strictEqual(p.perKm, 1500);
  assert.strictEqual(p.nightPermille, 1500); assert.strictEqual(p.roadFactorPermille, 1300);
  assert.strictEqual(p.maxKm, 12); assert.strictEqual(p.version, 3); assert.strictEqual(p.source, 'global');
});
check('resolveDeliveryPrices: mintaqa ustun (xorazm base 4000, perKm global)', () => {
  const p = t.resolveDeliveryPrices(doc, 'xorazm');
  assert.strictEqual(p.base, 4000); assert.strictEqual(p.perKm, 1500); assert.strictEqual(p.source, 'region:xorazm');
});
check('resolveDeliveryPrices: hujjat yo\'q / base yo\'q → null (hardcode yo\'q)', () => {
  assert.strictEqual(t.resolveDeliveryPrices(null, 'default'), null);
  assert.strictEqual(t.resolveDeliveryPrices({ perKm: 1500 }, 'default'), null);
  assert.strictEqual(t.resolveDeliveryPrices({ base: 5000.5, perKm: 1500 }, 'default'), null, 'float base rad');
  assert.strictEqual(t.resolveDeliveryPrices({ base: 0, perKm: 1500 }, 'default'), null, 'base 0 rad');
});

// ── Narx ───────────────────────────────────────────────────────────────
const prices = t.resolveDeliveryPrices(doc, 'default');
check('fee: 0.8 km → base 5 000 (1 km gacha)', () => {
  assert.strictEqual(t.computeDeliveryFee({ distanceMeters: 800, prices, night: false }).fee, 5000);
});
check('fee: 3 km → 5000 + 2×1500 = 8 000', () => {
  assert.strictEqual(t.computeDeliveryFee({ distanceMeters: 3000, prices, night: false }).fee, 8000);
});
check('fee: 5 km → 11 000', () => {
  assert.strictEqual(t.computeDeliveryFee({ distanceMeters: 5000, prices, night: false }).fee, 11000);
});
check('fee: 2.3 km → 5000 + round(1.3×1500=1950) = 6950 → 7 000 (500 ga)', () => {
  assert.strictEqual(t.computeDeliveryFee({ distanceMeters: 2300, prices, night: false }).fee, 7000);
});
check('fee: tun ×1.5 — 3 km → 12 000', () => {
  assert.strictEqual(t.computeDeliveryFee({ distanceMeters: 3000, prices, night: true }).fee, 12000);
});
check('fee: natija doim 500 ga karrali va butun', () => {
  for (let m = 0; m <= 15000; m += 137) {
    const f = t.computeDeliveryFee({ distanceMeters: m, prices, night: m % 2 === 0 }).fee;
    assert.ok(Number.isInteger(f) && f % 500 === 0, `m=${m} fee=${f}`);
  }
});
check('isNightAt: 23:30 Toshkent — tun; 12:00 — kunduz', () => {
  // UTC 18:30 = Toshkent 23:30
  assert.strictEqual(t.isNightAt(new Date('2026-10-08T18:30:00Z'), 23, 6), true);
  assert.strictEqual(t.isNightAt(new Date('2026-10-08T07:00:00Z'), 23, 6), false);
});

// ── O'z kuryeri ────────────────────────────────────────────────────────
check('ownFee fixed 7 000', () => {
  assert.strictEqual(t.computeOwnDeliveryFee({ type: 'fixed', fixed: 7000 }, { distanceMeters: 4000, itemsTotal: 20000 }), 7000);
});
check('ownFee distance: base 4000 + 2 km × 1000 = 6 000', () => {
  assert.strictEqual(t.computeOwnDeliveryFee({ type: 'distance', base: 4000, perKm: 1000 }, { distanceMeters: 3000, itemsTotal: 20000 }), 6000);
});
check('ownFee freeAbove: 100 000 dan bepul', () => {
  assert.strictEqual(t.computeOwnDeliveryFee({ type: 'fixed', fixed: 7000, freeAbove: 100000 }, { distanceMeters: 1000, itemsTotal: 100000 }), 0);
  assert.strictEqual(t.computeOwnDeliveryFee({ type: 'fixed', fixed: 7000, freeAbove: 100000 }, { distanceMeters: 1000, itemsTotal: 99999 }), 7000);
});
check('ownFee maxKm: 5 km chegara → 6 km null', () => {
  assert.strictEqual(t.computeOwnDeliveryFee({ type: 'fixed', fixed: 7000, maxKm: 5 }, { distanceMeters: 6000, itemsTotal: 1 }), null);
});
check('ownFee sozlama yo\'q → 0', () => {
  assert.strictEqual(t.computeOwnDeliveryFee(null, { distanceMeters: 6000, itemsTotal: 1 }), 0);
});

// ── Holat jadvali ──────────────────────────────────────────────────────
check('transitions: placed→accepted ha, placed→delivered yo\'q, delivered→* yo\'q', () => {
  assert.strictEqual(ro.canTransition('placed', 'accepted'), true);
  assert.strictEqual(ro.canTransition('placed', 'delivered'), false);
  assert.strictEqual(ro.canTransition('delivered', 'rejected'), false);
  assert.strictEqual(ro.canTransition('ready', 'picked'), true);
  assert.strictEqual(ro.canTransition('accepted', 'picked'), false, 'tayyor bo\'lmasdan olib ketish yo\'q');
  assert.strictEqual(ro.canTransition('nope', 'accepted'), false);
});
check('LEGACY: har holat uchun status/fulfillmentStatus jufti bor', () => {
  for (const s of Object.values(ro.RS)) {
    assert.ok(Array.isArray(ro.LEGACY[s]) && ro.LEGACY[s].length === 2, s);
    assert.ok(Array.isArray(ro.TRANSITIONS[s]), s);
  }
});
check('isOpenAt: 09:00–22:00; yarim tundan o\'tadigan 20:00–02:00; yo\'q → ochiq', () => {
  const at = (h) => new Date(Date.UTC(2026, 9, 8, (h - 5 + 24) % 24, 0)); // Toshkent soati
  assert.strictEqual(ro.isOpenAt({ open: '09:00', close: '22:00' }, at(12)), true);
  assert.strictEqual(ro.isOpenAt({ open: '09:00', close: '22:00' }, at(23)), false);
  assert.strictEqual(ro.isOpenAt({ open: '20:00', close: '02:00' }, at(1)), true);
  assert.strictEqual(ro.isOpenAt({ open: '20:00', close: '02:00' }, at(15)), false);
  assert.strictEqual(ro.isOpenAt(null, at(3)), true);
  assert.strictEqual(ro.isOpenAt({ open: 'x', close: '22:00' }, at(3)), true, 'noto\'g\'ri format → ochiq');
});

console.log(`\n${pass} passed, ${failCount} failed`);
process.exit(failCount ? 1 : 0);
