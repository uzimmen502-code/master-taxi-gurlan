/**
 * 13.1.2 — geohash pariteti + Т-4 geo hisoblari.
 *
 *   npm --prefix functions_demand run test:geo
 *
 * Emulator kerak emas — sof funksiyalar.
 */
const assert = require('assert');
const path = require('path');
const fs = require('fs');

const gh = require('../geo/geo_hash');
const geo = require('../geo/geo');

let passed = 0;
function ok(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`  OK  ${name}`);
  } catch (e) {
    console.error(`  XATO ${name}\n       ${e.message}`);
    process.exitCode = 1;
  }
}

const fixture = JSON.parse(
  fs.readFileSync(path.join(__dirname, 'fixtures', 'geohash_vectors.json'), 'utf8'),
);

console.log('geohash pariteti (fixture)');
for (const v of fixture.vectors) {
  ok(`${v.name} -> ${v.geohash}`, () => {
    assert.strictEqual(gh.encode(v.lat, v.lng, v.precision), v.geohash);
  });
}

ok('eski codebase bilan bit-babit bir xil', () => {
  // Ikkita nusxa ajralib ketmasin (Т-1): tasodifiy 200 nuqtada solishtiramiz.
  const old = require('../../functions/geo_hash');
  for (let i = 0; i < 200; i += 1) {
    const lat = (Math.random() * 180) - 90;
    const lng = (Math.random() * 360) - 180;
    const p = 1 + Math.floor(Math.random() * 8);
    assert.strictEqual(gh.encode(lat, lng, p), old.encode(lat, lng, p));
  }
});

ok('decodeBounds -> encode aylanishi barqaror', () => {
  const h = gh.encode(41.55, 60.63, 6);
  const b = gh.decodeBounds(h);
  const mid = { lat: (b.minLat + b.maxLat) / 2, lng: (b.minLng + b.maxLng) / 2 };
  assert.strictEqual(gh.encode(mid.lat, mid.lng, 6), h);
});

console.log('haversineKm');
ok('bir nuqta -> 0', () => {
  assert.strictEqual(geo.haversineKm(41.55, 60.63, 41.55, 60.63), 0);
});
ok('Urganch -> Xiva ~ 22-30 km', () => {
  const km = geo.haversineKm(41.55, 60.63, 41.3783, 60.3639);
  assert.ok(km > 22 && km < 30, `kutilmagan: ${km}`);
});
ok('Urganch -> Toshkent ~ 700-740 km', () => {
  const km = geo.haversineKm(41.55, 60.63, 41.2995, 69.2401);
  assert.ok(km > 700 && km < 740, `kutilmagan: ${km}`);
});

console.log('etaMinutes');
ok('piyoda mashinadan sekin', () => {
  const foot = geo.etaMinutes(41.55, 60.63, 41.56, 60.64, 'foot');
  const car = geo.etaMinutes(41.55, 60.63, 41.56, 60.64, 'car');
  assert.ok(foot > car, `foot=${foot} car=${car}`);
});
ok('nomalum transport -> car', () => {
  assert.strictEqual(
    geo.etaMinutes(41.55, 60.63, 41.6, 60.7, 'kosmik_kema'),
    geo.etaMinutes(41.55, 60.63, 41.6, 60.7, 'car'),
  );
});
ok('hech qachon 0 daqiqa emas', () => {
  assert.strictEqual(geo.etaMinutes(41.55, 60.63, 41.550001, 60.630001, 'car'), 1);
});
ok('~1 km shahar ichida mashinada 2-4 daqiqa', () => {
  // 0.009 kenglik ~ 1 km; yo'l koeffitsienti 1.35 -> 1.35 km / 24 km/soat ~ 3.4 daq
  const m = geo.etaMinutes(41.55, 60.63, 41.559, 60.63, 'car');
  assert.ok(m >= 2 && m <= 5, `kutilmagan: ${m}`);
});

console.log('precisionForRadiusKm');
ok('1 km -> 6 (katak 1.2 km)', () => {
  assert.strictEqual(geo.precisionForRadiusKm(1), 6);
});
ok('5 km -> 5 (katak 4.9 km emas, 4 ga tushadi)', () => {
  // 5 km > 4.9 km, shuning uchun precision 4 (39 km) tanlanadi.
  assert.strictEqual(geo.precisionForRadiusKm(5), 4);
});
ok('juda katta radius -> 2', () => {
  assert.strictEqual(geo.precisionForRadiusKm(99999), 2);
});

console.log('neighborPrefixes');
ok('9 ta katak (markaz + 8 qoshni)', () => {
  const n = geo.neighborPrefixes(41.55, 60.63, 6);
  assert.strictEqual(n.length, 9);
});
ok('markaz katak royxatda bor', () => {
  const n = geo.neighborPrefixes(41.55, 60.63, 6);
  assert.ok(n.includes(gh.encode(41.55, 60.63, 6)));
});
ok('Firestore `in` chegarasiga (30) sigadi', () => {
  for (const p of [3, 4, 5, 6, 7]) {
    assert.ok(geo.neighborPrefixes(41.55, 60.63, p).length <= 30);
  }
});
ok('katak chegarasidagi nuqta ham qamrab olinadi', () => {
  // Katak chetidagi kuryer tushib qolmasligi SHART — to'lqinning asosiy xatosi
  // ayni shu yerda bo'lardi.
  const b = gh.decodeBounds(gh.encode(41.55, 60.63, 6));
  const edgeLat = b.maxLat + 0.000001;
  const prefixes = geo.neighborPrefixes(41.55, 60.63, 6);
  assert.ok(prefixes.includes(gh.encode(edgeLat, 60.63, 6)));
});

console.log('prefixRange');
ok('oraliq prefiks bilan boshlanadi', () => {
  const r = geo.prefixRange('tr7h');
  assert.strictEqual(r.start, 'tr7h');
  assert.ok(r.end > r.start);
  assert.ok('tr7hzzz' < r.end, 'base32 ichidagi hamma narsa oraliqda bolishi kerak');
});

console.log('approxPoint (Т-20)');
ok('determinstik — bir demandId doim bir nuqta', () => {
  const a = geo.approxPoint(41.55, 60.63, 'demand_abc123');
  const b = geo.approxPoint(41.55, 60.63, 'demand_abc123');
  assert.deepStrictEqual(a, b);
});
ok('aniq nuqtadan 300-600 m oraligida', () => {
  for (let i = 0; i < 50; i += 1) {
    const p = geo.approxPoint(41.55, 60.63, `demand_${i}`);
    const m = geo.haversineKm(41.55, 60.63, p.lat, p.lng) * 1000;
    assert.ok(m >= 280 && m <= 640, `kutilmagan masofa: ${Math.round(m)} m`);
  }
});
ok('turli demandId -> turli yonalish (tor emas)', () => {
  // Agar og'ish doim bir yo'nalishda bo'lsa, bir nechta talabdan aniq joyni
  // tiklash mumkin bo'lardi. Shuning uchun yo'nalish tarqoq bo'lishi kerak.
  const angles = new Set();
  for (let i = 0; i < 40; i += 1) {
    const p = geo.approxPoint(41.55, 60.63, `demand_${i}`);
    const q = Math.atan2(p.lat - 41.55, p.lng - 60.63);
    angles.add(Math.round((q * 4) / Math.PI)); // 8 ta sektor
  }
  assert.ok(angles.size >= 5, `juda tor tarqalish: ${angles.size} sektor`);
});
ok('truncate EMAS — tor panjaraga tushmaydi', () => {
  const p = geo.approxPoint(41.55, 60.63, 'demand_x');
  assert.notStrictEqual(p.lat, 41.55);
  assert.notStrictEqual(p.lng, 60.63);
});

console.log('detourKm');
ok('yol ustidagi posilka ~ 0 ga yaqin', () => {
  // Urganch -> Toshkent yo'lida, Urganchdan 1 km chetda olib, 2 km chetda topshirish.
  const d = geo.detourKm(
    { lat: 41.55, lng: 60.63 },
    { lat: 41.555, lng: 60.635 },
    { lat: 41.30, lng: 69.24 },
    { lat: 41.2995, lng: 69.2401 },
  );
  assert.ok(d < 3, `kutilmagan chetlashish: ${d} km`);
});
ok('yoldan tashqaridagi posilka katta chetlashish', () => {
  const d = geo.detourKm(
    { lat: 41.55, lng: 60.63 },
    { lat: 42.45, lng: 59.61 },
    { lat: 42.46, lng: 59.62 },
    { lat: 41.2995, lng: 69.2401 },
  );
  assert.ok(d > 100, `kutilmagan chetlashish: ${d} km`);
});
ok('hech qachon manfiy emas', () => {
  const d = geo.detourKm(
    { lat: 41.55, lng: 60.63 },
    { lat: 41.55, lng: 60.63 },
    { lat: 41.2995, lng: 69.2401 },
    { lat: 41.2995, lng: 69.2401 },
  );
  assert.ok(d >= 0, `manfiy: ${d}`);
});

console.log(`\n${passed} test o'tdi.`);
