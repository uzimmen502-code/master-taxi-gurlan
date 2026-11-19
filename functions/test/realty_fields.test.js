/**
 * «Уй-жой бозори» қўшимча майдонлари — `functions/realty_fields.js` (соф).
 * Ишга тушириш: `node test/realty_fields.test.js`.
 */
'use strict';

const assert = require('assert');
const {
  parseRealtyExtras, extrasForCreate, extrasForUpdate, MAX_IMAGES, EXTRA_KEYS,
} = require('../realty_fields');

let passed = 0;
function check(name, fn) {
  fn();
  passed += 1;
  console.log(`✓ ${name}`);
}
const Y = 2026;
const p = (d, o = {}) => parseRealtyExtras(d, { nowYear: Y, ...o });

check('P1 бўш сўров — ҳеч нарса (сотувда ижара шартлари тозаланади)', () => {
  const r = p({});
  assert.deepStrictEqual(r.values, { rentPeriod: null, deposit: null });
  assert.deepStrictEqual(r.clearBase, []);
  assert.deepStrictEqual(extrasForCreate(r.values), {});
});

check('P2 тўлиқ квартира (ижара) — ҳаммаси тозаланган ҳолда', () => {
  const r = p({
    propertyType: 'apartment', renovation: 'euro', buildingType: 'brick',
    yearBuilt: 2010, utilities: ['internet', 'gas', 'gas', 'water'],
    documents: 'ready', furnished: true, bathroom: 'separate', balcony: false,
    parking: true, priceCurrency: 'usd', rentPeriod: 'month', deposit: '500',
    negotiable: true, mortgage: false, barter: true, landSotix: 6,
  }, { deal: 'rent' });
  assert.strictEqual(r.error, undefined);
  assert.deepStrictEqual(r.values.utilities, ['gas', 'water', 'internet']);
  assert.strictEqual(r.values.priceCurrency, 'USD');
  assert.strictEqual(r.values.deposit, 500);
  assert.strictEqual(r.values.balcony, false);
  assert.strictEqual(r.values.landSotix, null, 'квартирада сотих йўқ');
  assert.deepStrictEqual(r.clearBase, []);
});

check('P3 ер участкаси — хона/қават/таъмир тозаланади, сотих қолади', () => {
  const r = p({ propertyType: 'land', landSotix: '6.255', renovation: 'euro', balcony: true });
  assert.strictEqual(r.values.landSotix, 6.26);
  assert.strictEqual(r.values.renovation, null);
  assert.strictEqual(r.values.balcony, null);
  assert.deepStrictEqual(r.clearBase, ['rooms', 'floor', 'totalFloors']);
});

check('P4 таҳрир: калит келмаса жорий тур ҳисобга олинади', () => {
  const r = p({ landSotix: 10 }, { currentPropertyType: 'apartment' });
  assert.strictEqual(r.values.landSotix, null);
  const r2 = p({ landSotix: 10 }, { currentPropertyType: 'house' });
  assert.strictEqual(r2.values.landSotix, 10);
  const r3 = p({ landSotix: 10 });
  assert.strictEqual(r3.values.landSotix, 10, 'тур номаълум — сотих сақланади');
});

check('P5 null/бўш — тозалаш; extrasForUpdate → del', () => {
  const r = p({ propertyType: null, utilities: [], priceCurrency: '', furnished: null }, { deal: 'rent' });
  assert.deepStrictEqual(r.values, {
    propertyType: null, furnished: null, priceCurrency: null, utilities: null,
  });
  const DEL = Symbol('del');
  const u = extrasForUpdate(r.values, DEL);
  assert.strictEqual(u.propertyType, DEL);
  assert.ok(!('renovation' in u), 'калити йўқ — тегилмайди');
});

check('B1 чегаралар: сотих 0.1 / 10000, йил 1900 / жорий+2, депозит 1', () => {
  assert.strictEqual(p({ landSotix: 0.1 }).values.landSotix, 0.1);
  assert.strictEqual(p({ landSotix: 10000 }).values.landSotix, 10000);
  assert.strictEqual(p({ landSotix: 0.09 }).error, 'land_sotix_invalid');
  assert.strictEqual(p({ landSotix: 10000.01 }).error, 'land_sotix_invalid');
  assert.strictEqual(p({ yearBuilt: 1900 }).values.yearBuilt, 1900);
  assert.strictEqual(p({ yearBuilt: Y + 2 }).values.yearBuilt, Y + 2);
  assert.strictEqual(p({ yearBuilt: 1899 }).error, 'year_built_invalid');
  assert.strictEqual(p({ yearBuilt: Y + 3 }).error, 'year_built_invalid');
  assert.strictEqual(p({ deposit: 1 }, { deal: 'rent' }).values.deposit, 1);
  assert.strictEqual(p({ deposit: 0 }, { deal: 'rent' }).error, 'deposit_invalid');
  assert.strictEqual(MAX_IMAGES, 10);
});

check('N1 нотўғри қийматлар — диагностик код', () => {
  assert.strictEqual(p({ propertyType: 'castle' }).error, 'property_type_invalid');
  assert.strictEqual(p({ propertyType: 1 }).error, 'property_type_invalid');
  assert.strictEqual(p({ renovation: 'lux' }).error, 'renovation_invalid');
  assert.strictEqual(p({ buildingType: 'glass' }).error, 'building_type_invalid');
  assert.strictEqual(p({ documents: 'yes' }).error, 'documents_invalid');
  assert.strictEqual(p({ bathroom: 'two' }).error, 'bathroom_invalid');
  assert.strictEqual(p({ rentPeriod: 'week' }, { deal: 'rent' }).error, 'rent_period_invalid');
  assert.strictEqual(p({ furnished: 'yes' }).error, 'furnished_invalid');
  assert.strictEqual(p({ barter: 1 }).error, 'barter_invalid');
  assert.strictEqual(p({ priceCurrency: 'EUR' }).error, 'currency_invalid');
  assert.strictEqual(p({ utilities: 'gas' }).error, 'utilities_invalid');
  assert.strictEqual(p({ utilities: ['gas', 'wifi'] }).error, 'utilities_invalid');
  assert.strictEqual(p({ yearBuilt: 2000.5 }).error, 'year_built_invalid');
  assert.strictEqual(p({ yearBuilt: true }).error, 'year_built_invalid');
  assert.strictEqual(p({ deposit: 99.5 }, { deal: 'rent' }).error, 'deposit_invalid');
  assert.strictEqual(p({ landSotix: 'abc' }).error, 'land_sotix_invalid');
});

check('N2 сотувда ижара шартлари сақланмайди', () => {
  const r = p({ rentPeriod: 'day', deposit: 100 }, { deal: 'sale' });
  assert.strictEqual(r.values.rentPeriod, null);
  assert.strictEqual(r.values.deposit, null);
});

check('K1 калитлар рўйхати тўлиқ (17)', () => {
  assert.strictEqual(EXTRA_KEYS.length, 17);
});

console.log(`\n${passed} passed: realty_fields.test.js`);
