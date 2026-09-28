/**
 * `ev_static_map.js` — so'rov yig'uvchining chegaralari.
 *
 *   npm --prefix functions run test:ev-static-map
 *
 * Emulator kerak emas — sof funksiya.
 */
const assert = require('assert');
const {
  MAX_STATIC_MAP_MARKERS,
  clampNum,
  parseStaticMapMarkers,
  buildStaticMapQuery,
} = require('../ev_static_map');

let passed = 0;
function ok(name, fn) {
  try {
    fn();
    passed++;
    console.log(`  OK  ${name}`);
  } catch (e) {
    console.error(`  XATO ${name}\n       ${e.message}`);
    process.exitCode = 1;
  }
}

console.log('clampNum');
ok('chegaradan oshsa qisiladi', () => {
  assert.strictEqual(clampNum(999, 5, 16, 12, 0), 16);
  assert.strictEqual(clampNum(-999, 5, 16, 12, 0), 5);
});
ok('son bo`lmasa fallback', () => {
  assert.strictEqual(clampNum('salom', 5, 16, 12, 0), 12);
  assert.strictEqual(clampNum(undefined, 5, 16, 12, 0), 12);
});
ok('kasr yaxlitlanadi — kesh uchun', () => {
  assert.strictEqual(clampNum(41.8412345, 37, 46, 41.55), 41.841);
});

console.log('parseStaticMapMarkers');
ok('bo`sh — bo`sh ro`yxat', () => {
  assert.deepStrictEqual(parseStaticMapMarkers(''), []);
  assert.deepStrictEqual(parseStaticMapMarkers(undefined), []);
});
ok('noto`g`ri juftlik tashlanadi', () => {
  assert.deepStrictEqual(
    parseStaticMapMarkers('41.84,60.39|buzuq|42.0,60.5'),
    ['41.84,60.39', '42,60.5'],
  );
});
ok('eng ko`pi MAX_STATIC_MAP_MARKERS ta', () => {
  const many = Array.from(
    { length: MAX_STATIC_MAP_MARKERS + 15 },
    () => '41.84,60.39',
  ).join('|');
  assert.strictEqual(
    parseStaticMapMarkers(many).length,
    MAX_STATIC_MAP_MARKERS,
  );
});
ok('chegaradagi marker soni URL uzunligini buzmaydi', () => {
  // Google Static Maps URL chegarasi — 8192 belgi. To'liq to'ldirilgan
  // so'rov ham undan ancha kichik bo'lishi kerak.
  const many = Array.from(
    { length: MAX_STATIC_MAP_MARKERS },
    () => '41.840,60.390',
  ).join('|');
  const q = buildStaticMapQuery({ markers: many });
  assert.ok(q.length < 4000, `uzunlik: ${q.length}`);
});
ok('marker rangi berilishi mumkin', () => {
  const q = buildStaticMapQuery({
    markers: '41.84,60.39',
    color: '0x3FAE5A',
  });
  assert.ok(q.includes('color%3A0x3FAE5A'), q);
});
ok('noto`g`ri rang e`tiborsiz qoldiriladi', () => {
  const q = buildStaticMapQuery({
    markers: '41.84,60.39',
    color: 'javascript:alert(1)',
  });
  assert.ok(q.includes('color%3A0x1E4FD8'), q);
});
ok('O`zbekiston chegarasidan tashqarisi qisiladi', () => {
  // London (51.5, -0.12) — chegaraga qisiladi, begona hududga so'rov ketmaydi.
  const [m] = parseStaticMapMarkers('51.5,-0.12');
  assert.strictEqual(m, '46,55');
});

console.log('buildStaticMapQuery');
ok('standart qiymatlar', () => {
  const q = buildStaticMapQuery({});
  assert.ok(q.includes('center=41.55,60.39'), q);
  assert.ok(q.includes('zoom=12'), q);
  assert.ok(q.includes('size=400x200'), q);
  assert.ok(q.includes('scale=2'), q);
});
ok('kalit QO`SHILMAYDI', () => {
  const q = buildStaticMapQuery({ lat: 41.84, lng: 60.39 });
  assert.ok(!q.includes('key='), 'kalit query ichida chiqib ketdi');
});
ok('o`lcham va zoom chegarada', () => {
  const q = buildStaticMapQuery({ w: 5000, h: -3, zoom: 99 });
  assert.ok(q.includes('size=640x80'), q);
  assert.ok(q.includes('zoom=16'), q);
});
ok('markerlar kodlanadi', () => {
  const q = buildStaticMapQuery({ markers: '41.84,60.39' });
  assert.ok(q.includes('markers=size%3Asmall'), q);
  assert.ok(q.includes('41.84%2C60.39'), q);
});
ok('marker yo`q — markers parametri ham yo`q', () => {
  assert.ok(!buildStaticMapQuery({}).includes('markers='));
});

console.log(`\n${passed} ta tekshiruv o'tdi`);
