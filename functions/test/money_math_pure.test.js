/**
 * money_math.js + courier_payout_calc.js — sof testlar (T-2 / T-4, ega 2026-11-28).
 *
 *   node functions/test/money_math_pure.test.js
 */
'use strict';

const assert = require('assert');
const mm = require('../money_math');
const calc = require('../courier_payout_calc');
const lt = require('../logistics_tariff');

let passed = 0;
let failed = 0;
function check(name, fn) {
  try { fn(); passed += 1; } catch (e) { failed += 1; console.error(`  XATO ${name}\n       ${e && e.message}`); }
}
const throwsCode = (fn, code) => assert.throws(fn, (e) => e && e.code === code, code);

check('money_math: .5 holatlari — floor / ceil / half_up', () => {
  // 1 × 5000 bps = 0.5; 3 × 5000 = 1.5; 9999 × 5000 = 4999.5; 10001 × 5000 = 5000.5
  assert.deepStrictEqual(['floor', 'ceil', 'half_up'].map((m) => mm.bpsOf(1, 5000, m)), [0, 1, 1]);
  assert.deepStrictEqual(['floor', 'ceil', 'half_up'].map((m) => mm.bpsOf(3, 5000, m)), [1, 2, 2]);
  assert.deepStrictEqual(['floor', 'ceil', 'half_up'].map((m) => mm.bpsOf(9999, 5000, m)), [4999, 5000, 5000]);
  assert.deepStrictEqual(['floor', 'ceil', 'half_up'].map((m) => mm.pctOf(1, 50, m)), [0, 1, 1]);
  assert.deepStrictEqual(['floor', 'ceil', 'half_up'].map((m) => mm.pctOf(15001, 33, m)), [4950, 4951, 4950]); // 4950.33
});
check('money_math: aniq bo\'linish — barcha yo\'nalishda bir xil; 0 → 0', () => {
  for (const m of mm.MODES) {
    assert.strictEqual(mm.bpsOf(10000, 250, m), 250);
    assert.strictEqual(mm.bpsOf(0, 250, m), 0);
    assert.strictEqual(mm.bpsOf(12345, 0, m), 0);
    assert.strictEqual(mm.pctOf(200, 100, m), 200);
  }
});
check('money_math: noto\'g\'ri kirish — kodli xato', () => {
  throwsCode(() => mm.bpsOf(100, 100, 'round'), 'MONEY_MODE_INVALID');
  throwsCode(() => mm.mulDivRound(100, 100, 0, 'floor'), 'MONEY_DENOM_INVALID');
  throwsCode(() => mm.mulDivRound(100, 100, 3, 'floor'), 'MONEY_DENOM_INVALID');
  for (const a of [-1, NaN, Infinity, '100', null, undefined]) throwsCode(() => mm.bpsOf(a, 100, 'floor'), 'MONEY_AMOUNT_INVALID');
  throwsCode(() => mm.bpsOf(1.5, 100, 'floor'), 'MONEY_NOT_INTEGER');
  for (const r of [-1, 1.5, '100', null]) throwsCode(() => mm.bpsOf(100, r, 'floor'), 'MONEY_RATE_INVALID');
});
check('money_math: xavfsiz chegara — throw (standart) / unchecked', () => {
  throwsCode(() => mm.bpsOf(Number.MAX_SAFE_INTEGER, 2, 'ceil'), 'MONEY_UNSAFE_INTEGER');
  assert.strictEqual(mm.bpsOf(Number.MAX_SAFE_INTEGER, 1, 'floor'), 900719925474);
  assert.strictEqual(typeof mm.bpsOf(Number.MAX_SAFE_INTEGER, 2, 'ceil', { unsafe: 'unchecked' }), 'number');
});

check('calc.taskPayout: floor, noto\'g\'ri → null; chegara 0/10000', () => {
  assert.strictEqual(calc.taskPayout(123457, 1250), 15432);
  assert.strictEqual(calc.taskPayout(1, 10000), 1);
  assert.strictEqual(calc.taskPayout(1, 9999), 0);
  assert.strictEqual(calc.taskPayout(100, 0), 0);
  for (const [b, r] of [[0, 100], [-1, 100], [1.5, 100], [100, 10001], [100, -1], [100, 1.5]]) assert.strictEqual(calc.taskPayout(b, r), null);
});
check('calc.supermarketPayoutAmount: percent floor / fixed; fee yaroqsiz → 0', () => {
  assert.strictEqual(calc.supermarketPayoutAmount({ mode: 'percent', percent: 13 }, 15000), 1950);
  assert.strictEqual(calc.supermarketPayoutAmount({ mode: 'percent', percent: 33 }, 15001), 4950);
  assert.strictEqual(calc.supermarketPayoutAmount({ mode: 'percent', percent: 100 }, 15001), 15001);
  assert.strictEqual(calc.supermarketPayoutAmount({ mode: 'percent', percent: 13 }, 0), 0);
  assert.strictEqual(calc.supermarketPayoutAmount({ mode: 'percent', percent: 13 }, 100.5), 0);
  assert.strictEqual(calc.supermarketPayoutAmount({ mode: 'fixed', fixedAmount: 7000 }, 0), 7000);
});
check('calc.serviceFee / net: ceil + net = floor(gross × (10000 − bps))', () => {
  const o = { feeBpsMax: 5000 };
  assert.strictEqual(calc.serviceFee(10001, 1, o), 2);
  assert.strictEqual(calc.netAfterServiceFee(10001, 1, o), 9999);
  assert.strictEqual(calc.serviceFee(100000, 0, o), 0);
  assert.strictEqual(calc.serviceFee(3, 5000, o), 2);
  assert.throws(() => calc.serviceFee(100, 5001, o), /feeBps out of range/);
  assert.throws(() => calc.serviceFee(0, 100, o), /amount must be a positive integer/);
  assert.throws(() => calc.serviceFee(Number.MAX_SAFE_INTEGER, 2, o), /amount too large/);
});
check('calc.legSplit = logistics_tariff.splitInternal (bir xil funksiya)', () => {
  assert.strictEqual(calc.legSplit, lt.splitInternal);
});

console.log(`\n${passed} passed, ${failed} failed`);
if (failed) process.exitCode = 1;
