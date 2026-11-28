/**
 * Taksi komissiyasi admin sozlamasi (ega 2026-11-28) — SOF qism.
 *
 *   node functions/test/taxi_commission_pure.test.js
 */
'use strict';
const assert = require('assert');
const tb = require('../taxi_billing');

let passed = 0;
let failed = 0;
function ok(name, fn) {
  try { fn(); passed += 1; console.log(`  OK  ${name}`); } catch (e) { failed += 1; console.error(`  XATO ${name}\n       ${e.message}`); }
}

ok('standart: stavka berilmasa 200 bps — eski formula bilan bir xil (350000 → 28000)', () => {
  assert.strictEqual(tb.DEFAULT_RATE_BPS, 200);
  assert.strictEqual(tb.RATE_BPS, 200);
  assert.deepStrictEqual(tb.calculateTaxiFee(350000), tb.calculateTaxiFee(350000, 200));
  assert.strictEqual(tb.calculateTaxiFee(350000).feeAmount, 28000);
  assert.strictEqual(tb.calculateTaxiFee.length, 1, 'passengers parametri yo\'q (D-TAXI-6)');
});

ok('stavka parametri: 300 bps → 42000; 150 → 21000; 0 → 0; 10000 → 100 %', () => {
  assert.strictEqual(tb.calculateTaxiFee(350000, 300).feeAmount, 42000);
  assert.strictEqual(tb.calculateTaxiFee(350000, 150).feeAmount, 21000);
  assert.strictEqual(tb.calculateTaxiFee(350000, 0).feeAmount, 0);
  assert.strictEqual(tb.calculateTaxiFee(350000, 10000).feeAmount, 1400000);
  const f = tb.calculateTaxiFee(350000, 300);
  assert.deepStrictEqual([f.rateBps, f.rate, f.grossBasis], [300, 0.03, 1400000]);
});

ok('half_up chegara (ega 2026-11-28): 333333 × 4 × 175 / 10000 = 23333.31 → 23333; eski reys (ceil) → 23334', () => {
  const f = tb.calculateTaxiFee(333333, 175);
  assert.strictEqual(f.feeAmount, 23333);
  assert.strictEqual(tb.calculateTaxiFee(333333, 175, 'ceil').feeAmount, 23334);
  assert.ok(Number.isInteger(f.feeAmount));
});

ok('noto\'g\'ri stavka (server xatosi) → internal: -1, 10001, 2.5, \'200\', NaN, null', () => {
  for (const bad of [-1, 10001, 2.5, '200', NaN, null]) {
    assert.throws(() => tb.calculateTaxiFee(350000, bad), (e) => e.code === 'internal', String(bad));
  }
});

ok('resolveCommission: yo\'q → 200/v0 configured:false; to\'g\'ri → o\'zi; buzuq → 200 + invalid', () => {
  assert.deepStrictEqual(tb.resolveCommission(null), { bps: 200, version: 0, configured: false, invalid: false });
  assert.deepStrictEqual(tb.resolveCommission({ bps: 300, version: 4 }), { bps: 300, version: 4, configured: true });
  assert.deepStrictEqual(tb.resolveCommission({ bps: 0, version: 1 }), { bps: 0, version: 1, configured: true });
  assert.strictEqual(tb.resolveCommission({ bps: '300', version: 2 }).bps, 200);
  assert.strictEqual(tb.resolveCommission({ bps: '300', version: 2 }).invalid, true);
  assert.strictEqual(tb.resolveCommission({ bps: 300, version: -3 }).version, 0);
});

ok('tripRateBps: snapshot bo\'lsa o\'sha (300), eski reys (yo\'q / buzuq) → 200', () => {
  assert.strictEqual(tb.tripRateBps({ rateBps: 300 }), 300);
  assert.strictEqual(tb.tripRateBps({ rateBps: 0 }), 0);
  assert.strictEqual(tb.tripRateBps({}), 200);
  assert.strictEqual(tb.tripRateBps({ rateBps: 'x' }), 200);
  assert.strictEqual(tb.tripRateBps(null), 200);
});

ok('validateCommissionInput: faqat butun son 0..10000; satr/kasr/manfiy — BPS_INVALID; expectedVersion butun ≥ 0', () => {
  assert.deepStrictEqual(tb.validateCommissionInput({ bps: 250, reason: '  test  ' }), { bps: 250, expectedVersion: null, reason: 'test' });
  assert.strictEqual(tb.validateCommissionInput({ bps: 0 }).bps, 0);
  assert.strictEqual(tb.validateCommissionInput({ bps: 10000, expectedVersion: 3 }).expectedVersion, 3);
  for (const bad of ['250', 2.5, -1, 10001, null, undefined, NaN]) {
    assert.throws(() => tb.validateCommissionInput({ bps: bad }), (e) => e.message === 'BPS_INVALID', String(bad));
  }
  assert.throws(() => tb.validateCommissionInput({ bps: 200, expectedVersion: -1 }), (e) => e.message === 'EXPECTED_VERSION_INVALID');
  assert.strictEqual(tb.validateCommissionInput({ bps: 200, reason: 'x'.repeat(500) }).reason.length, 300);
});

console.log(`\n${passed} test o'tdi${failed ? `, ${failed} xato` : ''}.`);
if (failed) process.exitCode = 1;
