/**
 * Naqd yetkazish haqi hisobi — sof funksiyalar (Firestore yo'q).
 *
 *   node functions/test/relay_cash_pure.test.js
 *
 * Pul jadvallari (S5, ega 2026-11-14): bitta LEG, ko'p LEG, hamyon yetmaydi (qarz + AVA),
 * chegara (hamyon AYNAN teng / 0 / manfiy), noto'g'ri kirishlar, xaridor to'lamagan rad.
 */
'use strict';
const assert = require('assert');
const C = require('../relay_cash');

let passed = 0;
const tests = [];
const ok = (name, fn) => tests.push({ name, fn });
const W = 'passenger_credit:998904440004';
const sum = (legs, k) => legs.reduce((s, l) => s + (l[k] || 0), 0);

ok('bitta LEG: due = AVA ulushi + xizmat haqi; kuryer sofi = payout − haq', () => {
  // narx 100 000 = platforma 20 000 + pool 80 000 (bitta LEG = 80 000), xizmat haqi 5% = 4 000
  const p = C.planCashOutbound({
    amount: 100000, platformShare: 20000, providerPool: 80000, keep: 80000, serviceFee: 4000, balance: 500000, walletAccount: W,
  });
  assert.strictEqual(p.earlier, 0);
  assert.strictEqual(p.due, 24000);
  assert.strictEqual(p.take, 24000);
  assert.strictEqual(p.gap, 0);
  assert.strictEqual(sum(p.legs, 'dr'), sum(p.legs, 'cr'));
  assert.deepStrictEqual(p.legs, [
    { account: W, dr: 24000 },
    { account: 'earnings:ava_logistics_fee', cr: 20000 },
    { account: 'earnings:ava_courier_service_fee', cr: 4000 },
  ]);
  // Kuryer: naqd +100 000, hamyon −24 000 → sof 76 000 = 80 000 − 4 000 (eskrou bilan bir xil).
  assert.strictEqual(100000 - p.due, 80000 - 4000);
});

ok('ko\'p LEG: oldingi LEG ulushlari platform_accrual ga (EARNED yopiladi), yig\'uvchi o\'z ulushini saqlaydi', () => {
  // 240 000 = 48 000 + pool 192 000 (48 000 / 96 000 / 48 000), yig'uvchi = LEG-3 (48 000), haq 0
  const p = C.planCashOutbound({
    amount: 240000, platformShare: 48000, providerPool: 192000, keep: 48000, serviceFee: 0, balance: 1000000, walletAccount: W,
  });
  assert.strictEqual(p.earlier, 144000);
  assert.strictEqual(p.due, 192000);
  assert.deepStrictEqual(p.legs, [
    { account: W, dr: 192000 },
    { account: 'platform_accrual', cr: 144000 },
    { account: 'earnings:ava_logistics_fee', cr: 48000 },
  ]);
});

ok('hamyon yetmaydi: take = hamyon, gap = AVA qoplaydi (admin_clearing) → kuryer qarzi; hamyon manfiy EMAS', () => {
  const p = C.planCashOutbound({
    amount: 240000, platformShare: 48000, providerPool: 192000, keep: 48000, serviceFee: 0, balance: 50000, walletAccount: W,
  });
  assert.strictEqual(p.take, 50000);
  assert.strictEqual(p.gap, 142000);
  assert.deepStrictEqual(p.legs.slice(0, 2), [{ account: W, dr: 50000 }, { account: 'admin_clearing', dr: 142000 }]);
  assert.strictEqual(sum(p.legs, 'dr'), sum(p.legs, 'cr'));
});

ok('chegara: hamyon AYNAN due → gap 0; hamyon 0 yoki manfiy → hammasi qarz', () => {
  const base = { amount: 100000, platformShare: 20000, providerPool: 80000, keep: 80000, serviceFee: 0, walletAccount: W };
  assert.strictEqual(C.planCashOutbound({ ...base, balance: 20000 }).gap, 0);
  const z = C.planCashOutbound({ ...base, balance: 0 });
  assert.strictEqual(z.take, 0);
  assert.strictEqual(z.gap, 20000);
  assert.ok(!z.legs.some((l) => l.account === W), 'hamyon qatori yo\'q');
  assert.strictEqual(C.planCashOutbound({ ...base, balance: -5000 }).gap, 20000);
});

ok('salbiy: ulush yig\'indisi ≠ narx, keep > pool, haq > keep, float — anomaliya (pul yo\'q)', () => {
  const base = { amount: 100000, platformShare: 20000, providerPool: 80000, keep: 80000, serviceFee: 0, balance: 1, walletAccount: W };
  const code = (c) => (e) => e.code === c;
  assert.throws(() => C.planCashOutbound({ ...base, platformShare: 20001 }), code('cash_split_mismatch'));
  assert.throws(() => C.planCashOutbound({ ...base, keep: 80001 }), code('cash_keep_exceeds_pool'));
  assert.throws(() => C.planCashOutbound({ ...base, keep: 100, serviceFee: 101 }), code('cash_service_fee_invalid'));
  assert.throws(() => C.planCashOutbound({ ...base, amount: 100000.5 }), code('cash_amounts_invalid'));
  assert.throws(() => C.planCashOutbound({ ...base, amount: 0, platformShare: 0, providerPool: 0, keep: 0 }), code('cash_amounts_invalid'));
});

ok('qaytish haqi: hamyondan (yetmasa AVA), AVA-only rejim; escrow aynan R', () => {
  const E = 'escrow:RET1';
  const a = C.planReturnFund({ returnFee: 100000, balance: 300000, walletAccount: W, escrowAccount: E });
  assert.deepStrictEqual(a.legs, [{ account: W, dr: 100000 }, { account: E, cr: 100000 }]);
  const b = C.planReturnFund({ returnFee: 100000, balance: 30000, walletAccount: W, escrowAccount: E });
  assert.deepStrictEqual([b.take, b.gap], [30000, 70000]);
  const c = C.planReturnFund({ returnFee: 100000, balance: 999999, walletAccount: W, escrowAccount: E, avaOnly: true });
  assert.deepStrictEqual(c.legs, [{ account: 'admin_clearing', dr: 100000 }, { account: E, cr: 100000 }]);
  assert.throws(() => C.planReturnFund({ returnFee: 0, escrowAccount: E }), (e) => e.code === 'return_fee_invalid');
});

ok('xaridor to\'lamadi: qarz = yetkazish + qaytish; AVA = oldingi LEG\'lar + qaytish; yig\'uvchi ulushi qarzdan', () => {
  const u = C.planUnpaidRefusal({ deliveryFee: 240000, returnFee: 100000, providerPool: 192000, keep: 48000 });
  assert.deepStrictEqual(u, {
    coverOutbound: 144000, coverReturn: 100000, avaCovered: 244000, buyerDebt: 340000, owedToCollector: 48000,
  });
  const single = C.planUnpaidRefusal({ deliveryFee: 100000, returnFee: 100000, providerPool: 80000, keep: 80000 });
  assert.strictEqual(single.coverOutbound, 0, 'bitta LEG: oldingi kuryer yo\'q');
});

(async () => {
  for (const t of tests) {
    try { await t.fn(); passed += 1; console.log(`PASS - ${t.name}`); } catch (e) { console.log(`FAIL - ${t.name} :: ${e.stack || e.message}`); }
  }
  console.log(`\n${passed}/${tests.length} passed`);
  process.exit(passed === tests.length ? 0 : 1);
})();
