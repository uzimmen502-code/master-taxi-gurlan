/**
 * Ижара хабарномаси — СОФ мантиқ (`realty_alerts.js`), emulator керак эмас.
 *
 *   node functions/test/realty_alerts.test.js
 *
 * Қулфланади: мослик (битим, масофа, хона, нарх, муддат, ўз эълони),
 * чегара ҳолатлари, кирувчи маълумот текшируви, geohash қўшнилари
 * (10 км радиус ҳеч қачон қўшни катакдан ташқарига чиқмайди), тинч соат.
 */
'use strict';
const assert = require('assert');
const {
  mismatchReason, parseAlertInput, neighborCells, haversineKm,
  isQuietHour, tashkentDay, RADIUS_OPTIONS_KM,
} = require('../realty_alerts');
const { encode } = require('../geo_hash');

let passed = 0;
function ok(name, fn) {
  try { fn(); passed += 1; console.log(`  OK  ${name}`); } catch (e) {
    console.error(`  XATO ${name}\n       ${e.message}`);
    process.exitCode = 1;
  }
}

const NOW = Date.parse('2026-10-08T10:00:00Z');
// Гурлан маркази атрофида.
const C = { lat: 41.844, lng: 60.392 };
const alert = (over = {}) => ({
  ownerId: '998900000001', deal: 'rent', status: 'active',
  centerLat: C.lat, centerLng: C.lng, radiusKm: 3,
  roomsMin: null, roomsMax: null, priceMax: null,
  expiresAt: NOW + 10 * 86400000, ...over,
});
// ~1 км шимолда.
const listing = (over = {}) => ({
  deal: 'rent', ownerId: '998900000002', lat: C.lat + 0.009, lng: C.lng, ...over,
});

ok('позитив: радиус ичида, бир хил битим → мос', () => {
  assert.strictEqual(mismatchReason(alert(), listing(), NOW), '');
});
ok('негатив: битим тури бошқа', () => {
  assert.strictEqual(mismatchReason(alert(), listing({ deal: 'sale' }), NOW), 'deal');
});
ok('негатив: радиусдан ташқарида (≈5.5 км, радиус 3)', () => {
  assert.strictEqual(mismatchReason(alert(), listing({ lat: C.lat + 0.05 }), NOW), 'distance');
});
ok('чегара: масофа радиусга тенг атрофида — ичкари мос, ташқари йўқ', () => {
  const kmPerDegLat = haversineKm(0, 0, 1, 0);
  const inside = listing({ lat: C.lat + (2.99 / kmPerDegLat) });
  const outside = listing({ lat: C.lat + (3.01 / kmPerDegLat) });
  assert.strictEqual(mismatchReason(alert(), inside, NOW), '');
  assert.strictEqual(mismatchReason(alert(), outside, NOW), 'distance');
});
ok('негатив: ўз эълони ўзига хабар бўлмайди', () => {
  assert.strictEqual(
    mismatchReason(alert(), listing({ ownerId: '998900000001' }), NOW), 'own_listing');
});
ok('негатив: тўхтатилган / муддати ўтган хабарнома', () => {
  assert.strictEqual(mismatchReason(alert({ status: 'paused' }), listing(), NOW), 'alert_inactive');
  assert.strictEqual(mismatchReason(alert({ expiresAt: NOW }), listing(), NOW), 'alert_expired');
});
ok('хона: оралиқда мос, ташқарида йўқ, чегаралар киради', () => {
  const a = alert({ roomsMin: 2, roomsMax: 3 });
  assert.strictEqual(mismatchReason(a, listing({ rooms: 2 }), NOW), '');
  assert.strictEqual(mismatchReason(a, listing({ rooms: 3 }), NOW), '');
  assert.strictEqual(mismatchReason(a, listing({ rooms: 1 }), NOW), 'rooms');
  assert.strictEqual(mismatchReason(a, listing({ rooms: 4 }), NOW), 'rooms');
});
ok('хона кўрсатилмаган эълон — фильтр қўлланмайди («маълумот йўқ» ≠ «мос эмас»)', () => {
  assert.strictEqual(mismatchReason(alert({ roomsMin: 2 }), listing(), NOW), '');
});
ok('нарх: чегарага тенг мос, ошса йўқ; рақамсиз эълонга фильтр йўқ', () => {
  const a = alert({ priceMax: 3000000 });
  assert.strictEqual(mismatchReason(a, listing({ priceAmount: 3000000 }), NOW), '');
  assert.strictEqual(mismatchReason(a, listing({ priceAmount: 3000001 }), NOW), 'price');
  assert.strictEqual(mismatchReason(a, listing(), NOW), '');
});
ok('аниқ нуқтасиз эълон — мос эмас', () => {
  assert.strictEqual(mismatchReason(alert(), listing({ lat: undefined }), NOW), 'no_point');
});

ok('кирувчи: тўғри шакл', () => {
  const r = parseAlertInput({ deal: 'rent', lat: 41.8, lng: 60.4, radiusKm: 5, roomsMin: 2, roomsMax: 3, priceMax: 3000000 });
  assert.ok(r.value);
  assert.strictEqual(r.value.radiusKm, 5);
  assert.strictEqual(r.value.priceMax, 3000000);
});
ok('кирувчи: нотўғри қийматлар рад', () => {
  assert.strictEqual(parseAlertInput({ deal: 'x', lat: 1, lng: 1, radiusKm: 3 }).reason, 'deal_required');
  assert.strictEqual(parseAlertInput({ deal: 'rent', lat: 0, lng: 0, radiusKm: 3 }).reason, 'location_required');
  assert.strictEqual(parseAlertInput({ deal: 'rent', lat: 41, lng: 60, radiusKm: 2 }).reason, 'radius_invalid');
  assert.strictEqual(parseAlertInput({ deal: 'rent', lat: 41, lng: 60, radiusKm: 3, roomsMin: 4, roomsMax: 2 }).reason, 'rooms_invalid');
  assert.strictEqual(parseAlertInput({ deal: 'rent', lat: 41, lng: 60, radiusKm: 3, priceMax: 100.5 }).reason, 'price_invalid', 'пул — бутун сўм');
  assert.strictEqual(parseAlertInput({ deal: 'rent', lat: 41, lng: 60, radiusKm: 3, priceMax: -5 }).reason, 'price_invalid');
});

ok('geohash: энг катта радиусдаги (10 км) ҳар нуқта 9 катакнинг ичида', () => {
  const maxR = Math.max(...RADIUS_OPTIONS_KM);
  // Катак бурчакларига яқин марказлар ҳам текширилади.
  const centers = [C, { lat: 41.836, lng: 60.469 }, { lat: 41.661, lng: 60.117 }];
  for (const c of centers) {
    const cells = new Set(neighborCells(c.lat, c.lng));
    for (let deg = 0; deg < 360; deg += 15) {
      const rad = (deg * Math.PI) / 180;
      const dLat = (maxR / 111.32) * Math.cos(rad);
      const dLng = (maxR / (111.32 * Math.cos((c.lat * Math.PI) / 180))) * Math.sin(rad);
      const h = encode(c.lat + dLat, c.lng + dLng, 4);
      assert.ok(cells.has(h), `${deg}° → ${h} қўшнилар ичида эмас`);
    }
  }
});

ok('тинч соат: 23:00–07:00 Тошкент', () => {
  // 18:00 UTC = 23:00 Тошкент; 02:00 UTC = 07:00 Тошкент.
  assert.strictEqual(isQuietHour(Date.parse('2026-10-08T18:00:00Z')), true);
  assert.strictEqual(isQuietHour(Date.parse('2026-10-08T01:59:00Z')), true);
  assert.strictEqual(isQuietHour(Date.parse('2026-10-08T02:00:00Z')), false);
  assert.strictEqual(isQuietHour(Date.parse('2026-10-08T17:59:00Z')), false);
  assert.strictEqual(tashkentDay(Date.parse('2026-10-08T19:30:00Z')), '2026-10-09', 'Тошкентда янги кун');
});

console.log(`\n${passed} test o'tdi.`);
