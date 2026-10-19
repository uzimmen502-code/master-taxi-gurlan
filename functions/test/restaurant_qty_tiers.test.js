/**
 * Miqdorga chegirma pog'onalari — sof mantiq (D-REST-25). Emulator kerak emas:
 *   node functions/test/restaurant_qty_tiers.test.js
 * Buyurtma zanjiridagi ishlatilishi — restaurant_orders_cf.test.js (Q1…Q5), qoida — restaurant_rules.test.js.
 */
'use strict';
const assert = require('assert');
const { sanitizeTiers, unitPriceFor, MAX_TIERS } = require('../restaurant_qty_tiers');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.message}`); }
};
const t = (minQty, price) => ({ minQty, price });

check('misol (ega): osh 35 000; 10 tadan 32 000; 30 tadan 30 000 — chegaralar: 9 → 35 000; 10 → 32 000; 29 → 32 000; 30 → 30 000; 500 → 30 000', () => {
  const tiers = [t(10, 32000), t(30, 30000)];
  const at = (n) => unitPriceFor(35000, tiers, n);
  assert.deepStrictEqual(at(1), { unitPrice: 35000, tierMinQty: 0 });
  assert.deepStrictEqual(at(9), { unitPrice: 35000, tierMinQty: 0 });
  assert.deepStrictEqual(at(10), { unitPrice: 32000, tierMinQty: 10 });
  assert.deepStrictEqual(at(12), { unitPrice: 32000, tierMinQty: 10 });
  assert.deepStrictEqual(at(29), { unitPrice: 32000, tierMinQty: 10 });
  assert.deepStrictEqual(at(30), { unitPrice: 30000, tierMinQty: 30 });
  assert.deepStrictEqual(at(500), { unitPrice: 30000, tierMinQty: 30 });
  // hujjatdagi hisob: 12 porsiya 420 000 → 384 000
  assert.strictEqual(12 * at(12).unitPrice, 384000);
  assert.strictEqual(12 * 35000 - 12 * at(12).unitPrice, 36000);
});

check('pog\'ona yo\'q/bo\'sh/ro\'yxat emas — asosiy narx', () => {
  for (const raw of [undefined, null, [], 'x', {}, 5, [null], [undefined], ['x']]) {
    assert.deepStrictEqual(unitPriceFor(35000, raw, 100), { unitPrice: 35000, tierMinQty: 0 }, JSON.stringify(raw));
  }
});

check('sanitizeTiers: to\'g\'ri prefiks saqlanadi; birinchi noto\'g\'ridan keyin hammasi tashlanadi', () => {
  assert.deepStrictEqual(sanitizeTiers(40000, [t(10, 38000), t(30, 35000)]), [t(10, 38000), t(30, 35000)]);
  assert.deepStrictEqual(sanitizeTiers(40000, [t(10, 38000), t(5, 35000), t(30, 30000)]), [t(10, 38000)], 'orqaga minQty');
  assert.deepStrictEqual(sanitizeTiers(40000, [t(10, 38000), t(30, 38000)]), [t(10, 38000)], 'narx pasaymadi');
  assert.deepStrictEqual(sanitizeTiers(40000, [t(10, 38000), t(30, 39000)]), [t(10, 38000)], 'narx oshdi');
  assert.deepStrictEqual(sanitizeTiers(40000, [t(10, 40000)]), [], 'asosiy narxga teng');
  assert.deepStrictEqual(sanitizeTiers(40000, [t(10, 45000)]), [], 'asosiydan yuqori — narx OSHMAYDI');
  assert.deepStrictEqual(sanitizeTiers(40000, [t(1, 30000)]), [], 'minQty 1 — pog\'ona emas');
  assert.deepStrictEqual(sanitizeTiers(40000, [t(501, 30000)]), []);
  assert.deepStrictEqual(sanitizeTiers(40000, [t(2, 1)]), [t(2, 1)], 'quyi chegara');
  assert.deepStrictEqual(sanitizeTiers(40000, [t(500, 30000)]), [t(500, 30000)], 'yuqori chegara');
});

check('turlar: satr/kasr/NaN/manfiy/begona element — pog\'ona sifatida qabul qilinmaydi', () => {
  for (const bad of [{ minQty: '10', price: 100 }, { minQty: 10, price: '100' }, { minQty: 10.5, price: 100 }, { minQty: 10, price: 99.5 },
    { minQty: Number.NaN, price: 100 }, { minQty: 10, price: Number.NaN }, { minQty: -3, price: 100 }, { minQty: 10, price: -1 }, { minQty: 10 }, { price: 100 }, 5, 'x', null]) {
    assert.deepStrictEqual(sanitizeTiers(40000, [bad]), [], JSON.stringify(bad));
  }
  assert.deepStrictEqual(sanitizeTiers(Number.NaN, [t(10, 100)]), []);
  assert.deepStrictEqual(sanitizeTiers(0, [t(10, 100)]), []);
  assert.deepStrictEqual(sanitizeTiers('40000', [t(10, 100)]), []);
});

check(`eng ko'pi ${MAX_TIERS} ta pog'ona (ortiqchasi e'tiborsiz)`, () => {
  const many = [t(2, 39000), t(3, 38000), t(4, 37000), t(5, 36000)];
  assert.strictEqual(sanitizeTiers(40000, many).length, MAX_TIERS);
  assert.deepStrictEqual(unitPriceFor(40000, many, 100), { unitPrice: 37000, tierMinQty: 4 }, '4-pog\'ona e\'tiborsiz');
});

check('chegirma hech qachon asosiy narxdan OSHMAYDI va musbat: tasodifiy hujjatlar bo\'yicha xususiyat tekshiruvi', () => {
  let seed = 7;
  const rnd = (n) => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed % n; };
  for (let i = 0; i < 2000; i += 1) {
    const base = 1 + rnd(100000);
    const raw = Array.from({ length: rnd(5) }, () => ({ minQty: rnd(600) - 5, price: rnd(120000) - 100 }));
    const count = 1 + rnd(600);
    const { unitPrice, tierMinQty } = unitPriceFor(base, raw, count);
    assert.ok(Number.isInteger(unitPrice) && unitPrice >= 1 && unitPrice <= base, `${base} ${JSON.stringify(raw)} ${count} → ${unitPrice}`);
    assert.ok(tierMinQty === 0 || tierMinQty <= count);
    // monotonlik: ko'proq son — narx oshmaydi
    assert.ok(unitPriceFor(base, raw, count + 1).unitPrice <= unitPrice);
  }
});

const passed = results.filter(Boolean).length;
console.log(`\n${passed}/${results.length} passed`);
process.exit(passed === results.length ? 0 : 1);
