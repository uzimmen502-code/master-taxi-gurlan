/**
 * AVA Logistics — NAQD yetkazish haqi jo'natmasi YO'QOLDI: sof hisob `relay_escrow.planCashLoss`
 * (ega CONFIRMED 2026-11-14 qoidasi; tafsilot PROPOSED). Firestore yo'q.
 *
 *   node functions/test/relay_cash_loss_pure.test.js
 *
 * Qulflanadi: G birinchi navbatda egaga; oldingi LEG'lar haqi (E) hamyon qoldig'idan, yetmagani AVA
 * (admin_clearing) + qarz; Σdr == Σcr; butun so'm; noto'g'ri kirish — xato; chegaralar (0, aniq teng, 1 kam).
 */
'use strict';
const assert = require('assert');
const R = require('../relay_escrow');

const CA = 'passenger_credit:998902220002';
const OA = 'passenger_credit:998901234567';
const plan = (goods, earlier, balance) => R.planCashLoss({
  goods, earlier, balance, courierAccount: CA, ownerAccount: OA,
});
const sum = (legs, k) => legs.reduce((s, l) => s + (l[k] || 0), 0);

let passed = 0;
const tests = [];
const ok = (name, fn) => tests.push({ name, fn });

ok('eksport: kalit, hisob nomlari relay_cash bilan bir xil', () => {
  assert.strictEqual(R.cashLostKey('S1'), 'relayCashLost:S1');
  assert.strictEqual(R.AVA_COVER_ACCOUNT, require('../relay_cash').AVA_COVER_ACCOUNT);
  assert.strictEqual(R.isCashShipment({ deliveryPayment: { method: 'cash' } }), true);
  assert.strictEqual(R.isCashShipment({ deliveryPayment: { method: 'escrow' } }), false);
  assert.strictEqual(R.isCashShipment({}), false);
  assert.strictEqual(R.isCashShipment(null), false);
});

ok('1 LEG, kuryer boy: G to\'liq egaga, E=0, qarz 0, 2 oyoq', () => {
  const p = plan(140000, 0, 500000);
  assert.deepStrictEqual([p.takeGoods, p.takeEarlier, p.gap, p.goodsOutstanding, p.debt], [140000, 0, 0, 0, 0]);
  assert.deepStrictEqual(p.legs, [{ account: CA, dr: 140000 }, { account: OA, cr: 140000 }]);
});

ok('ko\'p LEG, kuryer boy: G egaga + E accrual\'ga, bitta kuryer debeti', () => {
  const p = plan(140000, 30000, 500000);
  assert.deepStrictEqual([p.takeGoods, p.takeEarlier, p.gap, p.debt], [140000, 30000, 0, 0]);
  assert.deepStrictEqual(p.legs, [
    { account: CA, dr: 170000 }, { account: OA, cr: 140000 }, { account: 'platform_accrual', cr: 30000 },
  ]);
});

ok('chegara: hamyon AYNAN G+E — qarz 0; G+E−1 — 1 so\'m AVA + qarz', () => {
  const a = plan(140000, 30000, 170000);
  assert.deepStrictEqual([a.takeGoods, a.takeEarlier, a.gap, a.debt], [140000, 30000, 0, 0]);
  const b = plan(140000, 30000, 169999);
  assert.deepStrictEqual([b.takeGoods, b.takeEarlier, b.gap, b.goodsOutstanding, b.debt], [140000, 29999, 1, 0, 1]);
  assert.deepStrictEqual(b.legs, [
    { account: CA, dr: 169999 }, { account: 'admin_clearing', dr: 1 },
    { account: OA, cr: 140000 }, { account: 'platform_accrual', cr: 30000 },
  ]);
});

ok('hamyon G dan kam: G qisman (qoldiq qarz), E to\'liq AVA (qarz) — G birinchi navbatda', () => {
  const p = plan(140000, 30000, 100000);
  assert.deepStrictEqual([p.takeGoods, p.takeEarlier, p.gap, p.goodsOutstanding, p.debt], [100000, 0, 30000, 40000, 70000]);
  assert.deepStrictEqual(p.legs, [
    { account: CA, dr: 100000 }, { account: 'admin_clearing', dr: 30000 },
    { account: OA, cr: 100000 }, { account: 'platform_accrual', cr: 30000 },
  ]);
});

ok('hamyon 0 / manfiy / butun emas: G to\'liq qarz; E bo\'lsa — faqat AVA yozuvi; E=0 — yozuv YO\'Q', () => {
  for (const b of [0, -5000, 12.5, NaN, null, undefined]) {
    const p = plan(140000, 30000, b);
    assert.deepStrictEqual([p.takeGoods, p.takeEarlier, p.gap, p.debt], [0, 0, 30000, 170000], String(b));
    assert.deepStrictEqual(p.legs, [{ account: 'admin_clearing', dr: 30000 }, { account: 'platform_accrual', cr: 30000 }]);
  }
  const z = plan(140000, 0, 0);
  assert.deepStrictEqual([z.legs.length, z.debt, z.goodsOutstanding], [0, 140000, 140000]);
});

ok('har reja: Σdr == Σcr, hamma summa butun ≥ 0, kuryer debeti ≤ hamyon', () => {
  for (const goods of [1, 999, 140000, 5000000]) {
    for (const earlier of [0, 1, 48000, 96000]) {
      for (const balance of [0, 1, 500, 139999, 140000, 170000, 10000000]) {
        const p = plan(goods, earlier, balance);
        if (p.legs.length) assert.strictEqual(sum(p.legs, 'dr'), sum(p.legs, 'cr'));
        for (const l of p.legs) assert.ok(Number.isSafeInteger(l.dr || l.cr) && (l.dr || l.cr) > 0);
        assert.ok(p.takeGoods + p.takeEarlier <= balance);
        assert.strictEqual(p.takeGoods + p.goodsOutstanding, goods);
        assert.strictEqual(p.takeEarlier + p.gap, earlier);
        assert.strictEqual(p.debt, p.goodsOutstanding + p.gap);
      }
    }
  }
});

ok('noto\'g\'ri kirish: G 0/manfiy/kasr/satr, E manfiy/kasr, hisob bir xil/yo\'q — xato', () => {
  const bad = [
    [0, 0], [-1, 0], [1.5, 0], ['140000', 0], [140000, -1], [140000, 0.5], [140000, '0'],
  ];
  for (const [g, e] of bad) assert.throws(() => plan(g, e, 100), /cash_loss_amounts_invalid/, `${g}/${e}`);
  assert.throws(() => R.planCashLoss({ goods: 1, earlier: 0, balance: 1, courierAccount: CA, ownerAccount: CA }), /cash_loss_accounts_invalid/);
  assert.throws(() => R.planCashLoss({ goods: 1, earlier: 0, balance: 1, courierAccount: '', ownerAccount: OA }), /cash_loss_accounts_invalid/);
});

(async () => {
  for (const t of tests) {
    try { await t.fn(); passed += 1; console.log(`  ok  ${t.name}`); } catch (e) { console.log(`  FAIL ${t.name}\n${e.stack}`); }
  }
  console.log(`\n${passed}/${tests.length} relay cash loss pure checks passed.`);
  process.exit(passed === tests.length ? 0 : 1);
})();
