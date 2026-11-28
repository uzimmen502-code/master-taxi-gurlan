/**
 * XARAKTERIZATSIYA TESTI — pul yaxlitlash va kuryer haqi chaqiruvchilari (takrorlanishlar auditi
 * T-2 / T-4, ega 2026-11-28).
 *
 *   node functions/test/money_rounding_characterization.test.js
 *
 * Tarix: b6aa2230 da refaktordan OLDIN yozilgan (eski natijalar, 29/29). Ega 2026-11-28 qarorlari
 * («ҳа бир хил бўлсин» — HAMMA joyda yarmidan yuqoriga; «ҳа» — supermarket kuryer to'lovi yaroqsiz
 * bazada null) bo'yicha kutilgan qiymatlar ATAYLAB yangilandi. Har chaqiruvchining ESKI → YANGI
 * farqi «O'ZGARGAN NATIJALAR» bo'limida aniq misol bilan qulflangan.
 *
 * Mustaqil orakul: BigInt bilan aniq hisob (float yo'q). Har chaqiruvchi uchun: musbat, salbiy
 * (noto'g'ri kirish), chegara (0, 1, .5 holatlari) va tasodifiy (urug'li) to'plam.
 */
'use strict';

const assert = require('assert');
const ctp = require('../courier_task_payout');
const cp = require('../courier_payout');
const sm = require('../supermarket');
const pdf = require('../platform_delivery_fee');
const rt = require('../restaurant_delivery_tariff');
const tb = require('../taxi_billing');
const dw = require('../../functions_demand/api/wholesale_orders');

let passed = 0;
let failed = 0;
function check(name, fn) {
  try {
    fn();
    passed += 1;
  } catch (e) {
    failed += 1;
    console.error(`  XATO ${name}\n       ${e && e.message}`);
  }
}

// ── Orakul (BigInt, aniq) ────────────────────────────────────────────────
function oracle(amount, rate, denom, mode) {
  const p = BigInt(amount) * BigInt(rate);
  const d = BigInt(denom);
  const q = p / d;
  const r = p % d;
  if (mode === 'floor') return Number(q);
  if (mode === 'ceil') return Number(r > 0n ? q + 1n : q);
  if (mode === 'half_up') return Number(r * 2n >= d ? q + 1n : q);
  throw new Error(mode);
}
const HU = 'half_up';

const AMOUNTS = [1, 2, 3, 5, 7, 99, 100, 101, 199, 200, 201, 999, 1000, 1001, 4999, 5000, 5001, 9999, 10000, 10001,
  12345, 15000, 20000, 25000, 33333, 99999, 100000, 123457, 250000, 333333, 350000, 999999, 1000000, 1000001,
  12345678, 99999999, 123456789];
const BPS = [0, 1, 2, 3, 49, 50, 51, 99, 100, 101, 125, 150, 175, 199, 200, 201, 250, 299, 300, 333, 499, 500, 999,
  1000, 1250, 1300, 2500, 3333, 4999, 5000, 5001, 7500, 9999, 10000];
const PCTS = [0, 1, 2, 3, 5, 7, 10, 12, 13, 15, 25, 33, 49, 50, 51, 66, 75, 99, 100];

// Urug'li tasodifiy (mulberry32) — takrorlanadigan to'plam.
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(20261128);
const randInt = (max) => 1 + Math.floor(rand() * max);
const RANDOM = Array.from({ length: 3000 }, () => [randInt(50000000), Math.floor(rand() * 10001)]);

const throwsCode = (fn, pred) => {
  let threw = false;
  try { fn(); } catch (e) { threw = true; if (pred && !pred(e)) throw new Error(`kutilmagan xato: ${e && (e.code || e.message)}`); }
  if (!threw) throw new Error('xato kutilgan edi');
};

// ═════ 1. Kuryer VAZIFA haqi — computePayout (half_up, bps; noto'g'ri → null) ═════
check('vazifa haqi: half_up(base × bps / 10000) — jadval + tasodifiy', () => {
  for (const a of AMOUNTS) for (const b of BPS) assert.strictEqual(ctp.computePayout(a, b), oracle(a, b, 10000, HU), `${a} ${b}`);
  for (const [a, b] of RANDOM) assert.strictEqual(ctp.computePayout(a, b), oracle(a, b, 10000, HU), `${a} ${b}`);
});
check('vazifa haqi: noto\'g\'ri kirish → null; buildPayout rounding muhri', () => {
  for (const [a, b] of [[0, 100], [-1, 100], [1.5, 100], ['100', 100], [NaN, 100], [null, 100], [100, -1], [100, 10001], [100, 1.5], [100, '100'], [100, null]]) {
    assert.strictEqual(ctp.computePayout(a, b), null, `${a} ${b}`);
  }
  const s = { version: 4, modules: { carpet: { bps: 1250 } } };
  assert.deepStrictEqual(ctp.buildPayout('carpet', 't1', 123457, s, 'c1'),
    { module: 'carpet', taskId: 't1', courierId: 'c1', payout: 15432, bps: 1250, version: 4, base: 123457, reason: null, rounding: 'half_up' });
  assert.strictEqual(ctp.buildPayout('carpet', 't1', 0, s, 'c1').reason, 'price_unknown');
  assert.strictEqual(ctp.buildPayout('agro', 't1', 1000, s, 'c1').reason, 'not_configured');
});

// ═════ 2. Kuryer XIZMAT haqi — computeFee (half_up, bps 0..5000; noto'g'ri → xato) ═════
check('xizmat haqi: half_up — jadval + tasodifiy', () => {
  for (const a of AMOUNTS) for (const b of BPS.filter((x) => x <= 5000)) assert.strictEqual(cp.computeFee(a, b), oracle(a, b, 10000, HU), `${a} ${b}`);
  for (const [a, b] of RANDOM) if (b <= 5000) assert.strictEqual(cp.computeFee(a, b), oracle(a, b, 10000, HU), `${a} ${b}`);
});
check('xizmat haqi: noto\'g\'ri kirish → xato (xabarlar o\'zgarmaydi)', () => {
  const msg = (m) => (e) => e.message === m;
  for (const a of [0, -1, 1.5, '100', NaN, null]) throwsCode(() => cp.computeFee(a, 100), msg('courierPayout: amount must be a positive integer'));
  for (const b of [-1, 5001, 1.5, '100', null]) throwsCode(() => cp.computeFee(100, b), msg('courierPayout: feeBps out of range'));
  throwsCode(() => cp.computeFee(Number.MAX_SAFE_INTEGER, 4999), msg('courierPayout: amount too large'));
});

// ═════ 3. Supermarket KURYER to'lovi — courierPayoutSnapshot (half_up, bps; fee yaroqsiz → null) ═════
check('supermarket kuryer: eski {percent} = percent×100 bps — jadval', () => {
  for (const a of AMOUNTS) for (const p of PCTS) {
    assert.deepStrictEqual(sm.courierPayoutSnapshot({ mode: 'percent', percent: p }, a, 3),
      { mode: 'percent', percentBps: p * 100, percent: p, rounding: 'half_up', amount: oracle(a, p * 100, 10000, HU), settingsVersion: 3 }, `${a} ${p}`);
  }
});
check('supermarket kuryer: yangi {percentBps} 0.01 % aniqlikda — jadval', () => {
  for (const a of AMOUNTS) for (const b of BPS) {
    const s = sm.courierPayoutSnapshot({ mode: 'percent', percentBps: b }, a, 1);
    assert.strictEqual(s.amount, oracle(a, b, 10000, HU), `${a} ${b}`);
    assert.strictEqual(s.percent, b / 100);
  }
  assert.strictEqual(sm.courierPayoutSnapshot({ mode: 'percent', percentBps: 1250 }, 15000, 1).amount, 1875); // 12.5 %
});
check('supermarket kuryer: fee 0 / manfiy / kasr / satr → amount null, reason fee_unknown', () => {
  for (const fee of [0, -5, 1000.5, '15000', null, undefined, NaN]) {
    const s = sm.courierPayoutSnapshot({ mode: 'percent', percent: 13 }, fee, 2);
    assert.deepStrictEqual([s.amount, s.reason], [null, 'fee_unknown'], String(fee));
  }
});
check('supermarket kuryer: fixed, sozlanmagan, buzuq', () => {
  assert.deepStrictEqual(sm.courierPayoutSnapshot({ mode: 'fixed', fixedAmount: 7000 }, 15000, 2),
    { mode: 'fixed', fixedAmount: 7000, amount: 7000, settingsVersion: 2 });
  assert.deepStrictEqual(sm.courierPayoutSnapshot({ mode: 'fixed', fixedAmount: 7000 }, 0, 2).amount, 7000);
  assert.deepStrictEqual(sm.courierPayoutSnapshot(null, 15000, 2), { mode: null, amount: null, reason: 'not_configured', settingsVersion: 2 });
  for (const bad of [{ mode: 'percent', percent: 12.5 }, { mode: 'percent', percent: 101 }, { mode: 'percent', percentBps: 10001 },
    { mode: 'percent', percentBps: 1.5 }, { mode: 'percent', percent: 12, percentBps: 1200 }, { mode: 'percent' },
    { mode: 'fixed', fixedAmount: -1 }, { mode: 'fixed', fixedAmount: 1000, percentBps: 5 }, { mode: 'x' }, 'str']) {
    assert.deepStrictEqual(sm.courierPayoutSnapshot(bad, 15000, 2), { mode: null, amount: null, reason: 'not_configured', settingsVersion: 2 }, JSON.stringify(bad));
  }
});

// ═════ 4. Supermarket tortish ushlab turishi — holdExtraOf (yangi: half_up; eski buyurtma: ceil) ═════
check('ushlab turish: yangi — half_up(line × bps / 10000); eski buyurtma muhrsiz — ceil', () => {
  for (const a of AMOUNTS) for (const p of PCTS) {
    assert.strictEqual(sm.holdExtraOf(a, p), p > 0 ? oracle(a, p * 100, 10000, HU) : 0, `num ${a} ${p}`);
    const neu = sm.holdSpecOfOrder({ weighHoldBps: p * 100, holdRounding: 'half_up' });
    const old = sm.holdSpecOfOrder({ weighHoldPercent: p });
    assert.strictEqual(sm.holdExtraOf(a, neu), p > 0 ? oracle(a, p * 100, 10000, HU) : 0, `new ${a} ${p}`);
    assert.strictEqual(sm.holdExtraOf(a, old), p > 0 ? oracle(a, p, 100, 'ceil') : 0, `old ${a} ${p}`);
  }
  assert.strictEqual(sm.holdExtraOf(10001, { bps: 1250, rounding: 'half_up' }), 1250); // 12.5 % → 1250.125
  for (const [l, p] of [[0, 10], [-1, 10], [100, 0], [100, -5], [100, NaN], [NaN, 10], [null, 10], [100, undefined]]) {
    assert.strictEqual(sm.holdExtraOf(l, p), 0, `${l} ${p}`);
  }
});
check('ushlab turish: manba — weighHoldBps → weighHoldPercent×100 → 1000', () => {
  assert.strictEqual(sm.holdBpsOf({ weighHoldBps: 1250, weighHoldPercent: 99 }), 1250);
  assert.strictEqual(sm.holdBpsOf({ weighHoldPercent: 12 }), 1200);
  assert.strictEqual(sm.holdBpsOf({}), 1000);
  assert.deepStrictEqual(sm.holdSpecOfSettings({ weighHoldPercent: 10 }), { bps: 1000, rounding: 'half_up' });
  assert.deepStrictEqual(sm.holdSpecOfOrder({ weighHoldPercent: 10 }), { bps: 1000, rounding: 'ceil' });
});

// ═════ 5. Yetkazish haqi — feeOf (half_up, O'ZGARMADI) ═════
check('yetkazish haqi: half_up — jadval + tasodifiy (o\'zgarmagan)', () => {
  for (const a of AMOUNTS) for (const b of BPS) assert.strictEqual(pdf.feeOf(a, b), b > 0 ? oracle(a, b, 10000, HU) : 0, `${a} ${b}`);
  for (const [a, b] of RANDOM) assert.strictEqual(pdf.feeOf(a, b), b > 0 ? oracle(a, b, 10000, HU) : 0, `${a} ${b}`);
  assert.strictEqual(pdf.feeOf(1000.5, 1250), 125);
  for (const [g, b] of [[0, 100], [-1, 100], [100, 0], [NaN, 100], [null, 100], ['x', 100]]) assert.strictEqual(pdf.feeOf(g, b), 0);
  assert.strictEqual(sm.feeOf, pdf.feeOf);
});

// ═════ 6. Restoran AVA ulushi — computeAvaFee (half_up) ═════
check('restoran AVA ulushi: half_up — jadval; standart 200 bps shakli', () => {
  for (const a of AMOUNTS) for (const b of BPS) {
    const r = rt.computeAvaFee(a, { rateBps: b, source: 'setting', settingsVersion: 5 });
    assert.deepStrictEqual(r, { rateBps: b, basis: a, amount: oracle(a, b, 10000, HU), version: rt.AVA_FEE_VERSION, rateSource: 'setting', settingsVersion: 5 }, `${a} ${b}`);
  }
  assert.deepStrictEqual(rt.computeAvaFee(123457), { rateBps: 200, basis: 123457, amount: 2469, version: rt.AVA_FEE_VERSION });
  for (const a of [0, -1, 1.5, '100', NaN, null, undefined]) throwsCode(() => rt.computeAvaFee(a), (e) => e.code === 'invalid-argument');
});

// ═════ 7. Taksi komissiyasi — calculateTaxiFee (yangi reys: half_up; eski reys muhrsiz: ceil) ═════
check('taksi: half_up(fare × 4 × bps / 10000) — jadval + tasodifiy; eski reys — ceil', () => {
  for (const a of AMOUNTS) for (const b of BPS) {
    const f = tb.calculateTaxiFee(a, b);
    assert.deepStrictEqual(f, { farePerSeat: a, seatBasis: 4, rateBps: b, rate: b / 10000, grossBasis: a * 4, feeAmount: oracle(a * 4, b, 10000, HU), feeRounding: 'half_up' });
    assert.strictEqual(tb.calculateTaxiFee(a, b, tb.tripFeeRounding({})).feeAmount, oracle(a * 4, b, 10000, 'ceil'), `old ${a} ${b}`);
  }
  for (const [a, b] of RANDOM) assert.strictEqual(tb.calculateTaxiFee(a, b).feeAmount, oracle(a * 4, b, 10000, HU), `${a} ${b}`);
  assert.strictEqual(tb.tripFeeRounding({ feeRounding: 'half_up' }), 'half_up');
  assert.strictEqual(tb.tripFeeRounding({ rateBps: 200 }), 'ceil');
  for (const a of [0, -1, 1.5, '350000', NaN, null]) throwsCode(() => tb.calculateTaxiFee(a), (e) => e.code === 'invalid-argument');
  for (const b of [-1, 10001, 1.5, '200', null]) throwsCode(() => tb.calculateTaxiFee(350000, b), (e) => e.code === 'internal');
});

// ═════ 8. Ulgurji (demand) AVA ulushi — avaFeeOf (half_up; !bps → 0; katta → xato) ═════
check('Ulgurji AVA ulushi: half_up — jadval; !bps → 0; amount_too_large', () => {
  for (const a of AMOUNTS) for (const b of BPS) assert.strictEqual(dw.avaFeeOf(a, b), b ? oracle(a, b, 10000, HU) : 0, `${a} ${b}`);
  for (const b of [0, null, undefined, NaN, '']) assert.strictEqual(dw.avaFeeOf(100000, b), 0, String(b));
  throwsCode(() => dw.avaFeeOf(Number.MAX_SAFE_INTEGER, 333), (e) => e.code === 'failed-precondition' && e.details && e.details.reason === 'amount_too_large');
});

// ═════ 9. O'ZGARGAN NATIJALAR — ega 2026-11-28 qarori (ESKI → YANGI, aniq misollar) ═════
const CHANGED = [
  // [chaqiruvchi, kirish, eski, yangi]
  ['vazifa haqi (floor→half_up)', () => ctp.computePayout(33333, 1500), 4999, 5000], // 4999.95
  ['vazifa haqi (floor→half_up)', () => ctp.computePayout(3, 5000), 1, 2], // 1.5
  ['xizmat haqi (ceil→half_up)', () => cp.computeFee(10001, 1), 2, 1], // 1.0001
  ['xizmat haqi (ceil→half_up)', () => cp.computeFee(96000, 1), 10, 10], // 9.6 — o'zgarmagan holat
  ['supermarket kuryer (floor→half_up)', () => sm.courierPayoutSnapshot({ mode: 'percent', percent: 13 }, 15500, 1).amount, 2015, 2015], // 2015.0
  ['supermarket kuryer (floor→half_up)', () => sm.courierPayoutSnapshot({ mode: 'percent', percent: 15 }, 1237, 1).amount, 185, 186], // 185.55
  ['supermarket kuryer (fee 0: 0→null)', () => sm.courierPayoutSnapshot({ mode: 'percent', percent: 13 }, 0, 1).amount, 0, null],
  ['ushlab turish (ceil→half_up)', () => sm.holdExtraOf(52501, 10), 5251, 5250], // 5250.1
  ['restoran AVA ulushi (ceil→half_up)', () => rt.computeAvaFee(1).amount, 1, 0], // 0.02
  ['restoran AVA ulushi (ceil→half_up)', () => rt.computeAvaFee(123457).amount, 2470, 2469], // 2469.14
  ['taksi (ceil→half_up)', () => tb.calculateTaxiFee(333333, 175).feeAmount, 23334, 23333], // 23333.31
  ['Ulgurji AVA ulushi (ceil→half_up)', () => dw.avaFeeOf(10001, 250), 251, 250], // 250.025
  ['yetkazish haqi (o\'zgarmadi)', () => pdf.feeOf(10001, 500), 500, 500],
];
check('o\'zgargan natijalar: har chaqiruvchi uchun eski → yangi misol', () => {
  for (const [name, fn, , want] of CHANGED) assert.strictEqual(fn(), want, name);
});
check('o\'zgarish chegarasi: farq ≤ 1 so\'m (tasodifiy 3000, eski ceil/floor vs yangi half_up)', () => {
  for (const [a, b] of RANDOM) {
    const hu = oracle(a, b, 10000, HU);
    assert.ok(Math.abs(hu - oracle(a, b, 10000, 'ceil')) <= 1 && Math.abs(hu - oracle(a, b, 10000, 'floor')) <= 1, `${a} ${b}`);
  }
});

console.log(`\n${passed} passed, ${failed} failed`);
if (failed) process.exitCode = 1;
