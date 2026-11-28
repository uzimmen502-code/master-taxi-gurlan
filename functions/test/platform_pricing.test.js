/**
 * Narx qoidalari — sof funksiyalar.
 *   AVA do'koni: YAGONA narx (ega 2026-11-28 — pog'onalar olib tashlangan, hisoblangan pog'ona yo'q).
 *   Ulgurji: sotuvchi qo'ygan ANIQ pog'onalar (wholesale_orders.js) — o'zgarmagan.
 *
 *   node functions/test/platform_pricing.test.js
 *
 * Eslatma: functions/test/fixtures/platform_price_vectors.json (hisoblangan pog'ona vektorlari)
 * endi serverda ishlatilmaydi — Dart testi (`test/models/platform_price_tiers_test.dart`) klient
 * tomonda yangilanguncha fayl tegilmadi.
 */
'use strict';
const assert = require('assert');
const pricing = require('../platform_pricing');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const OLD = { price: 10000 }; // createdAt yo'q — avval «eski tovar» (hisoblangan pog'ona) edi
const OLD_TS = { price: 10000, createdAt: { toMillis: () => Date.parse('2026-08-01T00:00:00Z') } };
const NEW = { price: 10000, createdAt: { toMillis: () => Date.parse('2026-11-01T00:00:00Z') } };

ok('server versiyasi: SERVER_PRICING_VERSION = 3 (yagona narx); 1/2 eski buyurtmalar uchun saqlangan', () => {
  assert.strictEqual(pricing.SERVER_PRICING_VERSION, 3);
  assert.strictEqual(pricing.SERVER_PRICING_VERSION, pricing.PRICING_VERSION_SINGLE);
  assert.deepStrictEqual([pricing.PRICING_VERSION_LEGACY, pricing.PRICING_VERSION_TIERED], [1, 2]);
});

ok('AVA do\'koni: istalgan miqdorda bir xil narx (1, 9, 10, 49, 50, 500) — eski va yangi tovar', () => {
  for (const p of [OLD, OLD_TS, NEW]) {
    for (const q of [1, 9, 10, 49, 50, 500]) assert.strictEqual(pricing.platformUnitPrice(p, q), 10000, `${q}`);
  }
});

ok('AVA do\'koni: priceTiers bo\'lsa ham E\'TIBORSIZ (prod: 0 tovarda bor) — yagona `price`', () => {
  const p = { price: 2000, priceTiers: [{ minQty: 1, price: 2200 }, { minQty: 5, price: 1800 }] };
  assert.strictEqual(pricing.platformUnitPrice(p), 2000);
});

ok('AVA do\'koni: butun so\'m; narx yo\'q / noto\'g\'ri → 0 (chaqiruvchi rad etadi)', () => {
  assert.strictEqual(pricing.platformUnitPrice({ price: 1234.9 }), 1234);
  assert.strictEqual(pricing.platformUnitPrice({}), 0);
  assert.strictEqual(pricing.platformUnitPrice({ price: 'abc' }), 0);
  assert.strictEqual(pricing.platformUnitPrice(null), 0);
});

ok('hisoblangan pog\'ona YO\'Q: eksportda derivedTiers / isLegacyProduct / DERIVED_TIERS_CUTOFF_MS yo\'q', () => {
  for (const k of ['derivedTiers', 'isLegacyProduct', 'effectiveTiers', 'DERIVED_TIERS_CUTOFF_MS', 'LOW_MARKUP_PCT']) {
    assert.strictEqual(pricing[k], undefined, k);
  }
  // Ulgurji moslik funksiyasi ham pog'onasiz eski tovarga +5 % qo'shmaydi.
  assert.strictEqual(pricing.unitPriceForQty(OLD, 1, 2), 10000);
  assert.strictEqual(pricing.unitPriceForQty(OLD_TS, 60, 2), 10000);
});

ok('ulgurji: aniq pog\'onalar — eng yuqori minQty ≤ qty; qty birinchisidan kichik → birinchisi; chegara', () => {
  const tiers = [{ minQty: 5, price: 8000 }, { minQty: 20, price: 7000 }];
  assert.strictEqual(pricing.tierUnitPrice(tiers, 1), 8000);
  assert.strictEqual(pricing.tierUnitPrice(tiers, 19), 8000);
  assert.strictEqual(pricing.tierUnitPrice(tiers, 20), 7000);
  assert.strictEqual(pricing.unitPriceForQty({ priceTiers: tiers }, 20, pricing.PRICING_VERSION_TIERED), 7000);
  assert.strictEqual(pricing.tierUnitPrice([], 3), null);
});

ok('cleanTiers: noto\'g\'ri yozuvlar tashlanadi, tartiblanadi', () => {
  assert.deepStrictEqual(pricing.cleanTiers([{ minQty: 0, price: 5 }, { minQty: 2, price: -1 }, null]), []);
  assert.deepStrictEqual(pricing.cleanTiers([{ minQty: 10, price: 9 }, { minQty: 1, price: 11 }]),
    [{ minQty: 1, price: 11 }, { minQty: 10, price: 9 }]);
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
