/**
 * XARAKTERIZATSIYA TESTI — pul yaxlitlash va kuryer haqi chaqiruvchilari (takrorlanishlar auditi
 * T-2 / T-4, ega 2026-11-28). Refaktordan OLDIN yozilgan va eski kodda yashil bo'lgan; refaktordan
 * keyin ham har chaqiruvchining natijasi AYNAN shu bo'lishi shart.
 *
 *   node functions/test/money_rounding_characterization.test.js
 *
 * Mustaqil orakul: BigInt bilan aniq hisob (float yo'q). Har chaqiruvchi uchun: musbat, salbiy
 * (noto'g'ri kirish), chegara (0, 1, 10000, .5 holatlari) va tasodifiy (urug'li) to'plam.
 * Xavfsiz butun son chegarasidan tashqari natijalar — alohida `LEGACY_UNSAFE` jadvalida
 * (eski kodda o'lchangan qiymatlar; farqi hisobotda ochiq yozilgan).
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

// ═════ 1. Kuryer VAZIFA haqi — courier_task_payout.computePayout (floor, bps; noto'g'ri → null) ═════
check('vazifa haqi: floor(base × bps / 10000) — jadval', () => {
  for (const a of AMOUNTS) for (const b of BPS) assert.strictEqual(ctp.computePayout(a, b), oracle(a, b, 10000, 'floor'), `${a} ${b}`);
});
check('vazifa haqi: tasodifiy 3000', () => {
  for (const [a, b] of RANDOM) assert.strictEqual(ctp.computePayout(a, b), oracle(a, b, 10000, 'floor'), `${a} ${b}`);
});
check('vazifa haqi: .5 holatlari pastga (1×5000 → 0, 3×5000 → 1, 10001×5000 → 5000)', () => {
  assert.strictEqual(ctp.computePayout(1, 5000), 0);
  assert.strictEqual(ctp.computePayout(3, 5000), 1);
  assert.strictEqual(ctp.computePayout(10001, 5000), 5000);
  assert.strictEqual(ctp.computePayout(15000, 3333), 4999); // 4999.5 → 4999
});
check('vazifa haqi: noto\'g\'ri kirish → null', () => {
  for (const [a, b] of [[0, 100], [-1, 100], [1.5, 100], ['100', 100], [NaN, 100], [null, 100], [100, -1], [100, 10001], [100, 1.5], [100, '100'], [100, null]]) {
    assert.strictEqual(ctp.computePayout(a, b), null, `${a} ${b}`);
  }
});
check('vazifa haqi: buildPayout — sabab va qiymat', () => {
  const s = { version: 4, modules: { carpet: { bps: 1250 } } };
  assert.deepStrictEqual(ctp.buildPayout('carpet', 't1', 123457, s, 'c1'),
    { module: 'carpet', taskId: 't1', courierId: 'c1', payout: 15432, bps: 1250, version: 4, base: 123457, reason: null });
  assert.strictEqual(ctp.buildPayout('carpet', 't1', 0, s, 'c1').reason, 'price_unknown');
  assert.strictEqual(ctp.buildPayout('carpet', 't1', 0, s, 'c1').payout, null);
  assert.strictEqual(ctp.buildPayout('agro', 't1', 1000, s, 'c1').reason, 'not_configured');
  assert.strictEqual(ctp.buildPayout('agro', 't1', 1000, null, 'c1').payout, null);
});

// ═════ 2. Kuryer XIZMAT haqi — courier_payout.computeFee (ceil, bps 0..5000; noto'g'ri → xato) ═════
check('xizmat haqi: ceil(gross × bps / 10000) — jadval', () => {
  for (const a of AMOUNTS) for (const b of BPS.filter((x) => x <= 5000)) assert.strictEqual(cp.computeFee(a, b), oracle(a, b, 10000, 'ceil'), `${a} ${b}`);
});
check('xizmat haqi: tasodifiy', () => {
  for (const [a, b] of RANDOM) if (b <= 5000) assert.strictEqual(cp.computeFee(a, b), oracle(a, b, 10000, 'ceil'), `${a} ${b}`);
});
check('xizmat haqi: .5 → yuqoriga; net = gross − fee (floor bilan teng)', () => {
  assert.strictEqual(cp.computeFee(1, 5000), 1);
  assert.strictEqual(cp.computeFee(3, 5000), 2);
  assert.strictEqual(cp.computeFee(10001, 1), 2);
  assert.strictEqual(cp.computeFee(10000, 1), 1);
  for (const [a, b] of RANDOM.slice(0, 500)) if (b <= 5000) assert.strictEqual(a - cp.computeFee(a, b), oracle(a, 10000 - b, 10000, 'floor'));
});
check('xizmat haqi: noto\'g\'ri kirish → xato (xabarlar o\'zgarmaydi)', () => {
  const msg = (m) => (e) => e.message === m;
  for (const a of [0, -1, 1.5, '100', NaN, null]) throwsCode(() => cp.computeFee(a, 100), msg('courierPayout: amount must be a positive integer'));
  for (const b of [-1, 5001, 1.5, '100', null]) throwsCode(() => cp.computeFee(100, b), msg('courierPayout: feeBps out of range'));
  throwsCode(() => cp.computeFee(Number.MAX_SAFE_INTEGER, 4999), msg('courierPayout: amount too large'));
  throwsCode(() => cp.computeFee(2 ** 51 + 1, 4999), msg('courierPayout: amount too large'));
});

// ═════ 3. Supermarket KURYER to'lovi — courierPayoutSnapshot (floor, butun foiz; fee yaroqsiz → 0) ═════
check('supermarket kuryer: percent → floor(fee × pct / 100) — jadval', () => {
  for (const a of AMOUNTS) for (const p of PCTS) {
    assert.deepStrictEqual(sm.courierPayoutSnapshot({ mode: 'percent', percent: p }, a, 3),
      { mode: 'percent', percent: p, amount: oracle(a, p, 100, 'floor'), settingsVersion: 3 }, `${a} ${p}`);
  }
});
check('supermarket kuryer: .5 → pastga (1×50% → 0, 3×50% → 1, 15001×33% → 4950)', () => {
  const amt = (fee, p) => sm.courierPayoutSnapshot({ mode: 'percent', percent: p }, fee, 1).amount;
  assert.strictEqual(amt(1, 50), 0);
  assert.strictEqual(amt(3, 50), 1);
  assert.strictEqual(amt(15001, 33), 4950);
});
check('supermarket kuryer: fee 0 / manfiy / kasr / satr → amount 0 (null EMAS)', () => {
  for (const fee of [0, -5, 1000.5, '15000', null, undefined, NaN]) {
    assert.strictEqual(sm.courierPayoutSnapshot({ mode: 'percent', percent: 13 }, fee, 2).amount, 0, String(fee));
  }
});
check('supermarket kuryer: fixed, sozlanmagan, buzuq', () => {
  assert.deepStrictEqual(sm.courierPayoutSnapshot({ mode: 'fixed', fixedAmount: 7000 }, 15000, 2),
    { mode: 'fixed', fixedAmount: 7000, amount: 7000, settingsVersion: 2 });
  assert.deepStrictEqual(sm.courierPayoutSnapshot({ mode: 'fixed', fixedAmount: 0 }, 15000, 2),
    { mode: 'fixed', fixedAmount: 0, amount: 0, settingsVersion: 2 });
  assert.deepStrictEqual(sm.courierPayoutSnapshot(null, 15000, 2), { mode: null, amount: null, settingsVersion: 2 });
  assert.deepStrictEqual(sm.courierPayoutSnapshot(undefined, 15000, 'x'), { mode: null, amount: null, settingsVersion: 0 });
  for (const bad of [{ mode: 'percent', percent: 12.5 }, { mode: 'percent', percent: 101 }, { mode: 'percent', percent: -1 },
    { mode: 'fixed', fixedAmount: -1 }, { mode: 'fixed', fixedAmount: 1.5 }, { mode: 'x' }, 'str']) {
    assert.deepStrictEqual(sm.courierPayoutSnapshot(bad, 15000, 2), { mode: null, amount: null, settingsVersion: 2 }, JSON.stringify(bad));
  }
});

// ═════ 4. Supermarket tortish ushlab turishi — holdExtraOf (ceil, foiz; ≤0 → 0) ═════
check('ushlab turish: ceil(line × pct / 100) — jadval', () => {
  for (const a of AMOUNTS) for (const p of PCTS) assert.strictEqual(sm.holdExtraOf(a, p), p > 0 ? oracle(a, p, 100, 'ceil') : 0, `${a} ${p}`);
});
check('ushlab turish: .5 → yuqoriga; 0/manfiy → 0', () => {
  assert.strictEqual(sm.holdExtraOf(1, 50), 1);
  assert.strictEqual(sm.holdExtraOf(3, 50), 2);
  assert.strictEqual(sm.holdExtraOf(100, 10), 10);
  assert.strictEqual(sm.holdExtraOf(101, 10), 11);
  for (const [l, p] of [[0, 10], [-1, 10], [100, 0], [100, -5], [100, NaN], [NaN, 10], [null, 10], [100, undefined]]) {
    assert.strictEqual(sm.holdExtraOf(l, p), 0, `${l} ${p}`);
  }
});
check('ushlab turish: kasr kirish — eski formula natijasi', () => {
  assert.strictEqual(sm.holdExtraOf(1000.5, 7), 71);
  assert.strictEqual(sm.holdExtraOf(1000, 7.5), 75);
});

// ═════ 5. Yetkazish haqi — platform_delivery_fee.feeOf (half_up, bps; ≤0 → 0) ═════
check('yetkazish haqi: floor((goods × bps + 5000) / 10000) — jadval', () => {
  for (const a of AMOUNTS) for (const b of BPS) assert.strictEqual(pdf.feeOf(a, b), b > 0 ? oracle(a, b, 10000, 'half_up') : 0, `${a} ${b}`);
});
check('yetkazish haqi: tasodifiy', () => {
  for (const [a, b] of RANDOM) assert.strictEqual(pdf.feeOf(a, b), b > 0 ? oracle(a, b, 10000, 'half_up') : 0, `${a} ${b}`);
});
check('yetkazish haqi: .5 → yuqoriga, .4999 → pastga', () => {
  assert.strictEqual(pdf.feeOf(1, 5000), 1);
  assert.strictEqual(pdf.feeOf(3, 5000), 2);
  assert.strictEqual(pdf.feeOf(10010, 500), 501); // 500.5
  assert.strictEqual(pdf.feeOf(10001, 500), 500); // 500.05
  assert.strictEqual(pdf.feeOf(9999, 5000), 5000); // 4999.5
});
check('yetkazish haqi: kasr goods — eski formula, ≤0/son emas → 0', () => {
  assert.strictEqual(pdf.feeOf(1000.5, 1250), 125);
  assert.strictEqual(pdf.feeOf(1000.4, 1250), 125);
  assert.strictEqual(pdf.feeOf(4.4, 1250), 1); // 0.55 → 1
  for (const [g, b] of [[0, 100], [-1, 100], [100, 0], [100, -1], [NaN, 100], [null, 100], [100, undefined], ['x', 100]]) {
    assert.strictEqual(pdf.feeOf(g, b), 0, `${g} ${b}`);
  }
  assert.strictEqual(sm.feeOf, pdf.feeOf);
});

// ═════ 6. Restoran AVA ulushi — restaurant_delivery_tariff.computeAvaFee (ceil, bps; standart 200) ═════
check('restoran AVA ulushi: ceil — jadval (sozlama bilan)', () => {
  for (const a of AMOUNTS) for (const b of BPS) {
    const r = rt.computeAvaFee(a, { rateBps: b, source: 'setting', settingsVersion: 5 });
    assert.deepStrictEqual(r, { rateBps: b, basis: a, amount: oracle(a, b, 10000, 'ceil'), version: rt.AVA_FEE_VERSION, rateSource: 'setting', settingsVersion: 5 }, `${a} ${b}`);
  }
});
check('restoran AVA ulushi: standart 200 bps, sozlamasiz shakl o\'zgarmaydi', () => {
  assert.deepStrictEqual(rt.computeAvaFee(123457), { rateBps: 200, basis: 123457, amount: 2470, version: rt.AVA_FEE_VERSION });
  assert.deepStrictEqual(rt.computeAvaFee(50000, { rateBps: 10001 }), { rateBps: 200, basis: 50000, amount: 1000, version: rt.AVA_FEE_VERSION });
  assert.strictEqual(rt.computeAvaFee(1).amount, 1); // 0.02 → 1
  assert.strictEqual(rt.computeAvaFee(1, { rateBps: 0 }).amount, 0);
});
check('restoran AVA ulushi: noto\'g\'ri itemsTotal → invalid-argument', () => {
  for (const a of [0, -1, 1.5, '100', NaN, null, undefined]) throwsCode(() => rt.computeAvaFee(a), (e) => e.code === 'invalid-argument');
});

// ═════ 7. Taksi komissiyasi — taxi_billing.calculateTaxiFee (ceil, fare × 4 × bps / 10000) ═════
check('taksi: ceil(fare × 4 × bps / 10000) — jadval', () => {
  for (const a of AMOUNTS) for (const b of BPS) {
    const f = tb.calculateTaxiFee(a, b);
    assert.strictEqual(f.feeAmount, oracle(a * 4, b, 10000, 'ceil'), `${a} ${b}`);
    assert.deepStrictEqual(f, { farePerSeat: a, seatBasis: 4, rateBps: b, rate: b / 10000, grossBasis: a * 4, feeAmount: f.feeAmount });
  }
});
check('taksi: tasodifiy', () => {
  for (const [a, b] of RANDOM) assert.strictEqual(tb.calculateTaxiFee(a, b).feeAmount, oracle(a * 4, b, 10000, 'ceil'), `${a} ${b}`);
});
check('taksi: chegara va xato kodlari', () => {
  assert.strictEqual(tb.calculateTaxiFee(1, 1).feeAmount, 1);
  assert.strictEqual(tb.calculateTaxiFee(2500, 1).feeAmount, 1);
  assert.strictEqual(tb.calculateTaxiFee(1250, 10).feeAmount, 5); // 5.0 aniq
  assert.strictEqual(tb.calculateTaxiFee(1251, 10).feeAmount, 6);
  for (const a of [0, -1, 1.5, '350000', NaN, null]) throwsCode(() => tb.calculateTaxiFee(a), (e) => e.code === 'invalid-argument');
  for (const b of [-1, 10001, 1.5, '200', null]) throwsCode(() => tb.calculateTaxiFee(350000, b), (e) => e.code === 'internal');
});

// ═════ 8. Ulgurji (demand) AVA ulushi — avaFeeOf (ceil, bps; !bps → 0; katta → xato) ═════
check('Ulgurji AVA ulushi: ceil — jadval', () => {
  for (const a of AMOUNTS) for (const b of BPS) assert.strictEqual(dw.avaFeeOf(a, b), b ? oracle(a, b, 10000, 'ceil') : 0, `${a} ${b}`);
});
check('Ulgurji AVA ulushi: !bps → 0, xavfsiz chegaradan oshsa → amount_too_large', () => {
  for (const b of [0, null, undefined, NaN, '']) assert.strictEqual(dw.avaFeeOf(100000, b), 0, String(b));
  throwsCode(() => dw.avaFeeOf(Number.MAX_SAFE_INTEGER, 333), (e) => e.code === 'failed-precondition' && e.details && e.details.reason === 'amount_too_large');
});

// ═════ 9. Xavfsiz butun son chegarasidan TASHQARI — eski kodda o'lchangan (2026-11-28) ═════
// Bu hududda eski chaqiruvchilar bir xil emas: xizmat haqi va Ulgurji XATO beradi, qolganlari
// float aniqligida son qaytaradi. Refaktor ularni o'zgartirmaydi (`unsafe: 'unchecked'`).
const LEGACY_UNSAFE = [
  // [amount, task(9999), sm13%, hold7%, fee1250, rest333, taxi333]
  [2251799813685249, 2251574633703880, 292733975779082, 157625986957968, 281474976710656, 74984933795719, 299939735182876],
  [4503599627370499, 4503149267407762, 585467951558164, 315251973915935, 562949953421312, 149969867591438, 599879470365751],
  [9007199254740991, 9006298534815516, 1170935903116328, 630503947831870, 1125899906842624, 299939735182876, 1199758940731500],
  [9000000000000000, 8999100000000000, 1170000000000000, 630000000000001, 1125000000000000, 299700000000000, 1198800000000000],
  [123456789012345, 123444443333443, 16049382571604, 8641975230865, 15432098626543, 4111111074112, 16444444296445],
];
// Refaktordan keyin ATAYLAB o'zgargan (eski float natija noto'g'ri edi, yangisi BigInt orakul bilan
// AYNAN teng). Real summalarda (mahsulot < 9 007 199 254 740 991) farq yo'q — yuqoridagi jadvallar.
const UNSAFE_CHANGED = {
  'hold 9000000000000000': 630000000000000, // eski 630000000000001 (+99 float yo'qotdi)
  'taxi 9007199254740991': 1199758940731501, // eski 1199758940731500 (Math.ceil float)
};
check('xavfsiz chegaradan tashqari: eski natijalar (vazifa, supermarket, ushlab turish, yetkazish, restoran, taksi)', () => {
  const diffs = {};
  const cmp = (key, actual, legacy) => { if (actual !== legacy) diffs[key] = actual; };
  for (const [a, task, smv, hold, fee, rest, taxi] of LEGACY_UNSAFE) {
    cmp(`task ${a}`, ctp.computePayout(a, 9999), task);
    cmp(`sm ${a}`, sm.courierPayoutSnapshot({ mode: 'percent', percent: 13 }, a, 1).amount, smv);
    cmp(`hold ${a}`, sm.holdExtraOf(a, 7), hold);
    cmp(`fee ${a}`, pdf.feeOf(a, 1250), fee);
    cmp(`rest ${a}`, rt.computeAvaFee(a, { rateBps: 333 }).amount, rest);
    cmp(`taxi ${a}`, tb.calculateTaxiFee(a, 333).feeAmount, taxi);
  }
  assert.deepStrictEqual(diffs, UNSAFE_CHANGED);
  assert.strictEqual(UNSAFE_CHANGED['hold 9000000000000000'], oracle(9e15, 7, 100, 'ceil'));
  assert.strictEqual(UNSAFE_CHANGED['taxi 9007199254740991'], oracle(9007199254740991 * 4, 333, 10000, 'ceil'));
});

console.log(`\n${passed} passed, ${failed} failed`);
if (failed) process.exitCode = 1;
