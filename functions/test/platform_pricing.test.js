/**
 * AVA do'koni narx pog'onalari — sof funksiyalar va Dart bilan paritet.
 *
 *   node functions/test/platform_pricing.test.js
 */
'use strict';
const assert = require('assert');
const path = require('path');
const fs = require('fs');
const pricing = require('../platform_pricing');

const { vectors } = JSON.parse(fs.readFileSync(
  path.join(__dirname, 'fixtures', 'platform_price_vectors.json'), 'utf8'));

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

ok('paritet vektorlari: v2 (pog\'onali) va v1 (eski yagona narx)', () => {
  for (const v of vectors) {
    const p = { price: v.price, priceTiers: v.tiers, createdAt: v.createdAt };
    assert.strictEqual(pricing.unitPriceForQty(p, v.qty, 2), v.v2, `v2 ${JSON.stringify(v)}`);
    assert.strictEqual(pricing.unitPriceForQty(p, v.qty, 1), v.v1, `v1 ${JSON.stringify(v)}`);
  }
});

ok('ega misoli: 10 000 → 1–9: 10 500, 10–50: 10 000, 50+: 9 500', () => {
  assert.deepStrictEqual(pricing.derivedTiers(10000), [
    { minQty: 1, price: 10500 }, { minQty: 10, price: 10000 }, { minQty: 50, price: 9500 },
  ]);
});

ok('har doim BUTUN so\'m (float yo\'q)', () => {
  for (let p = 1; p <= 3000; p += 7) {
    for (const t of pricing.derivedTiers(p)) assert.ok(Number.isInteger(t.price), `${p}`);
  }
});

ok('admin pog\'onasi bo\'lsa — hisoblanmaydi, o\'shalar ishlatiladi', () => {
  const tiers = pricing.effectiveTiers({ price: 10000, priceTiers: [{ minQty: 5, price: 8000 }] });
  assert.deepStrictEqual(tiers, [{ minQty: 5, price: 8000 }]);
});

ok('noto\'g\'ri pog\'ona yozuvlari tashlab yuboriladi, narx yo\'q → bo\'sh', () => {
  assert.deepStrictEqual(pricing.cleanTiers([{ minQty: 0, price: 5 }, { minQty: 2, price: -1 }, null]), []);
  assert.deepStrictEqual(pricing.derivedTiers(0), []);
  assert.deepStrictEqual(pricing.derivedTiers('abc'), []);
});

ok('YANGI tovar (2026-10-07 dan): pog\'ona hisoblanmaydi — qo\'shuvchi o\'zi qo\'yadi', () => {
  const fresh = { price: 10000, createdAt: { toMillis: () => Date.parse('2026-10-07T09:00:00Z') } };
  assert.deepStrictEqual(pricing.effectiveTiers(fresh), []);
  assert.strictEqual(pricing.unitPriceForQty(fresh, 1, 2), 10000);
  assert.strictEqual(pricing.isLegacyProduct(fresh), false);
  // Firestore Timestamp shakli bilan eski tovar — hisoblanadi.
  const old = { price: 10000, createdAt: { toMillis: () => Date.parse('2026-08-01T00:00:00Z') } };
  assert.strictEqual(pricing.unitPriceForQty(old, 1, 2), 10500);
});

ok('pricingVersion berilmasa (eski ilova) — eski yagona narx', () => {
  assert.strictEqual(pricing.unitPriceForQty({ price: 10000 }, 1, undefined), 10000);
  assert.strictEqual(pricing.unitPriceForQty({ price: 10000 }, 60, 0), 10000);
});

(async () => {
  for (const t of tests) {
    try { await t.fn(); passed += 1; console.log(`  OK  ${t.name}`); } catch (e) {
      console.error(`  XATO ${t.name}\n       ${e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
