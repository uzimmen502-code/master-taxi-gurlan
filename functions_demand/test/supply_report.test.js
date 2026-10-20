/**
 * A7 — hudud bo'yicha taklifchilar hisoboti (sof funksiya).
 *
 *   node functions_demand/test/supply_report.test.js
 *
 * Maqsad: har viloyatda NECHTA ishlay oladigan taklifchi borligini sanash va
 * hududni yoqish (variant A: «taklifchi yetarli bo'lganda») uchun tayyorlik
 * ko'rsatish. Firestore'ga tegmaydi.
 */
const assert = require('assert');
const { summarizeSupply } = require('../tools/provider_supply_report');

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

const REGIONS = ['xorazm', 'toshkent_shahri', 'andijon'];

/** `service` ishlaydigan holatda (status enabled) va xohishi bor hujjat. */
function svcDoc(regionIds, over = {}) {
  return {
    status: { service: 'enabled' },
    service: { active: true, regionIds, categoryIds: ['elektrik'] },
    ...over,
  };
}

console.log('summarizeSupply');
ok('har hudud uchun ishlay oladigan taklifchi soni', () => {
  const r = summarizeSupply({
    capDocs: [svcDoc(['xorazm']), svcDoc(['xorazm']), svcDoc(['toshkent_shahri'])],
    regionIds: REGIONS,
    min: 2,
    service: 'service',
  });
  const by = Object.fromEntries(r.rows.map((x) => [x.regionId, x]));
  assert.strictEqual(by.xorazm.providers, 2);
  assert.strictEqual(by.toshkent_shahri.providers, 1);
  assert.strictEqual(by.andijon.providers, 0);
});
ok('tayyorlik: soni >= min bo`lsa ready', () => {
  const r = summarizeSupply({
    capDocs: [svcDoc(['xorazm']), svcDoc(['xorazm'])],
    regionIds: REGIONS, min: 2, service: 'service',
  });
  const by = Object.fromEntries(r.rows.map((x) => [x.regionId, x]));
  assert.strictEqual(by.xorazm.ready, true);
  assert.strictEqual(by.andijon.ready, false);
  assert.deepStrictEqual(r.readyRegions, ['xorazm']);
});
ok('chegara aniq: min-1 tayyor emas, min tayyor', () => {
  const docs = [svcDoc(['andijon']), svcDoc(['andijon']), svcDoc(['andijon']), svcDoc(['andijon'])];
  const below = summarizeSupply({ capDocs: docs, regionIds: REGIONS, min: 5, service: 'service' });
  assert.strictEqual(below.readyRegions.length, 0);
  const at = summarizeSupply({ capDocs: [...docs, svcDoc(['andijon'])], regionIds: REGIONS, min: 5, service: 'service' });
  assert.deepStrictEqual(at.readyRegions, ['andijon']);
});
ok('xohish yo`q (active:false) yoki huquq yo`q (status) sanalmaydi', () => {
  const r = summarizeSupply({
    capDocs: [
      svcDoc(['xorazm'], { service: { active: false, regionIds: ['xorazm'] } }),
      svcDoc(['xorazm'], { status: { service: 'suspended' } }),
      svcDoc(['xorazm'], { status: {} }),
    ],
    regionIds: REGIONS, min: 1, service: 'service',
  });
  assert.strictEqual(r.rows.find((x) => x.regionId === 'xorazm').providers, 0);
});
ok('bir taklifchi bir nechta hududda — har birida sanaladi, jami bir marta', () => {
  const r = summarizeSupply({
    capDocs: [svcDoc(['xorazm', 'andijon'])],
    regionIds: REGIONS, min: 1, service: 'service',
  });
  assert.strictEqual(r.rows.find((x) => x.regionId === 'xorazm').providers, 1);
  assert.strictEqual(r.rows.find((x) => x.regionId === 'andijon').providers, 1);
  assert.strictEqual(r.totalProviders, 1);
});
ok('noma`lum hudud (geo_regions da yo`q) alohida ko`rsatiladi, yo`qolmaydi', () => {
  const r = summarizeSupply({
    capDocs: [svcDoc(['atlantida'])],
    regionIds: REGIONS, min: 1, service: 'service',
  });
  assert.deepStrictEqual(r.unknownRegions, ['atlantida']);
});
ok('hududsiz taklifchi (regionIds bo`sh) hisobda ko`rinadi', () => {
  const r = summarizeSupply({
    capDocs: [svcDoc([])], regionIds: REGIONS, min: 1, service: 'service',
  });
  assert.strictEqual(r.withoutRegion, 1);
});
ok('hisobotda telefon/ID yo`q (40-band) — faqat sonlar', () => {
  const r = summarizeSupply({
    capDocs: [svcDoc(['xorazm'], { identity: { primaryUid: '998901234567' } })],
    regionIds: REGIONS, min: 1, service: 'service',
  });
  assert.ok(!JSON.stringify(r).includes('998901234567'));
});
ok('min noto`g`ri bo`lsa xato (0, manfiy, kasr, NaN)', () => {
  for (const bad of [0, -1, 1.5, NaN, undefined]) {
    assert.throws(
      () => summarizeSupply({ capDocs: [], regionIds: REGIONS, min: bad, service: 'service' }),
      /min/,
      `min=${bad} rad etilishi kerak`,
    );
  }
});
ok('noma`lum xizmat nomi rad etiladi', () => {
  assert.throws(
    () => summarizeSupply({ capDocs: [], regionIds: REGIONS, min: 1, service: 'nonsense' }),
    /service/,
  );
});

console.log(`\n${passed} test o'tdi.`);
