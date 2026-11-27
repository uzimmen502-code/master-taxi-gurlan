/**
 * T-1 (ega 2026-11-28): `platform_delivery_fee.js` — yagona manba. Eski ikki nusxa bilan
 * EKVIVALENTLIK (ko'p qiymat ustida):
 *   A) index.js `platformDeliveryFeeFromSettings` — 4edbfb10 dagi matn (jonli placeOrderPostPaid);
 *   B) supermarket.js `feeConfigFromApp` + `feeBpOf` + `feeOf` — 4edbfb10 dagi matn.
 *
 *   node functions/test/platform_delivery_fee.test.js
 */
'use strict';
const assert = require('assert');
const pdf = require('../platform_delivery_fee');

// ── A: eski index.js nusxasi (HttpsError o'rniga marker) ──
function legacyIndex(settings, itemsTotal) {
  const raw = (settings || {}).platformDeliveryFeePercent;
  const pctIn = (typeof raw === 'number' || (typeof raw === 'string' && raw.trim() !== ''))
    ? Number(raw)
    : NaN;
  if (!Number.isFinite(pctIn) || pctIn < 0) return 'TARIFF_NOT_CONFIGURED';
  const percent = Math.min(pctIn, 100);
  const bps = Math.round(percent * 100);
  const total = Number(itemsTotal) || 0;
  const fee = Math.floor((total * bps + 5000) / 10000);
  const verRaw = Number((settings || {}).platformDeliveryFeeVersion);
  const version = Number.isInteger(verRaw) && verRaw > 0 ? verRaw : 0;
  return { percent, bps, fee, version };
}
// ── B: eski supermarket.js nusxasi ──
function smFeeConfigFromApp(appData) {
  const raw = (appData || {}).platformDeliveryFeePercent;
  const pctIn = (typeof raw === 'number' || (typeof raw === 'string' && raw.trim() !== '')) ? Number(raw) : NaN;
  if (!Number.isFinite(pctIn) || pctIn < 0) return null;
  const percent = Math.min(pctIn, 100);
  const verRaw = Number((appData || {}).platformDeliveryFeeVersion);
  return { percent, bps: Math.round(percent * 100), version: Number.isInteger(verRaw) && verRaw > 0 ? verRaw : 0 };
}
function smFeeBpOf(pct) {
  const n = Number(pct);
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.round(Math.min(n, 100) * 100);
}
function smFeeOf(goods, bp) {
  if (!(goods > 0) || !(bp > 0)) return 0;
  return Math.floor((goods * bp + 5000) / 10000);
}

// ── Yangi modul orqali index.js o'rami (index.js dagi bilan bir xil) ──
function viaModule(settings, itemsTotal) {
  const cfg = pdf.feeConfigFromApp(settings);
  if (!cfg) return pdf.TARIFF_NOT_CONFIGURED;
  return { percent: cfg.percent, bps: cfg.bps, fee: pdf.feeOf(Number(itemsTotal) || 0, cfg.bps), version: cfg.version };
}

let passed = 0;
let failed = 0;
function ok(name, fn) {
  try { fn(); passed += 1; console.log(`  OK  ${name}`); } catch (e) { failed += 1; console.error(`  XATO ${name}\n       ${e.message}`); }
}

const PCTS = [
  undefined, null, '', ' ', 'abc', NaN, Infinity, -Infinity, -1, -0.01, 0, '0', 0.004, 0.005, 0.006,
  0.5, 1, '1', 1.5, 2, '2', 2.345, 2.355, 5, 7.25, 10, 11, '11', 12.5, 33.335, 50, 99.99, 100, '100',
  100.5, 150, 1e6, true, false, [], {}, '2.5', ' 3 ',
];
const VERS = [undefined, null, 0, 1, 2, '3', 2.5, -1, 'x', 17];
// Deterministik psevdo-tasodifiy jamlar (LCG) + chegaralar.
const TOTALS = [undefined, null, 0, '0', 1, 2, 49, 50, 99, 100, 101, 199, 249, 250, 251, 999, 1000, 1050,
  2100, 9999, 10000, 12345, 35000, 99999, 100000, 123456, 999999, 1000000, 25000000, 999999999];
let seed = 20261128;
for (let i = 0; i < 400; i += 1) {
  seed = (seed * 1103515245 + 12345) % 2147483648;
  TOTALS.push(seed % 5000000);
}

ok(`index.js eski formulasi bilan AYNAN teng (${PCTS.length} foiz × ${VERS.length} versiya × ${TOTALS.length} jam)`, () => {
  let n = 0;
  for (const p of PCTS) {
    for (const v of VERS) {
      const s = { platformDeliveryFeePercent: p, platformDeliveryFeeVersion: v };
      for (const t of TOTALS) {
        assert.deepStrictEqual(viaModule(s, t), legacyIndex(s, t), `pct=${String(p)} ver=${String(v)} total=${String(t)}`);
        n += 1;
      }
    }
  }
  assert.ok(n > 100000, `vektorlar soni ${n}`);
});

ok('supermarket.js eski nusxasi bilan AYNAN teng (feeConfigFromApp / feeBpOf / feeOf)', () => {
  for (const p of PCTS) {
    for (const v of VERS) {
      const s = { platformDeliveryFeePercent: p, platformDeliveryFeeVersion: v };
      assert.deepStrictEqual(pdf.feeConfigFromApp(s), smFeeConfigFromApp(s), `cfg pct=${String(p)} ver=${String(v)}`);
    }
    assert.strictEqual(pdf.feeBpOf(p), smFeeBpOf(p), `bp pct=${String(p)}`);
  }
  const BPS = [undefined, null, NaN, -100, 0, 1, 49, 50, 99, 100, 150, 200, 250, 1100, 1250, 9999, 10000];
  for (const b of BPS) for (const t of TOTALS) {
    assert.strictEqual(pdf.feeOf(t, b), smFeeOf(t, b), `feeOf total=${String(t)} bps=${String(b)}`);
  }
  assert.strictEqual(pdf.feeOf(-100, 200), smFeeOf(-100, 200));
});

ok('pozitiv: 11 % → 2100 dan 231; 2 % → 35000 dan 700; 2.5 % → 250 bps', () => {
  assert.deepStrictEqual(viaModule({ platformDeliveryFeePercent: 11, platformDeliveryFeeVersion: 2 }, 2100), { percent: 11, bps: 1100, fee: 231, version: 2 });
  assert.strictEqual(viaModule({ platformDeliveryFeePercent: 2 }, 35000).fee, 700);
  assert.strictEqual(pdf.feeConfigFromApp({ platformDeliveryFeePercent: 2.5 }).bps, 250);
});

ok('chegara: yarim so\'m yuqoriga (5 % × 10 = 0.5 → 1; 5 % × 9 = 0.45 → 0); 100 % dan katta → 100 %', () => {
  assert.strictEqual(pdf.feeOf(10, 500), 1);
  assert.strictEqual(pdf.feeOf(9, 500), 0);
  assert.deepStrictEqual(pdf.feeConfigFromApp({ platformDeliveryFeePercent: 250 }), { percent: 100, bps: 10000, version: 0 });
  assert.strictEqual(pdf.feeOf(12345, 10000), 12345);
});

ok('negativ: yo\'q / bo\'sh / manfiy / son emas → null (TARIFF_NOT_CONFIGURED), hardcode fallback yo\'q', () => {
  for (const p of [undefined, null, '', '  ', 'x', -1, NaN, Infinity, true, {}, []]) {
    assert.strictEqual(pdf.feeConfigFromApp({ platformDeliveryFeePercent: p }), null, String(p));
  }
  assert.strictEqual(pdf.feeConfigFromApp(null), null);
  assert.strictEqual(pdf.feeConfigFromApp(undefined), null);
});

ok('natija har doim butun son (8-qoida)', () => {
  for (const p of [0.004, 1.5, 2.345, 7.25, 33.335]) {
    const cfg = pdf.feeConfigFromApp({ platformDeliveryFeePercent: p });
    assert.ok(Number.isInteger(cfg.bps), `bps ${p}`);
    for (const t of TOTALS.slice(0, 60)) {
      const f = pdf.feeOf(Number(t) || 0, cfg.bps);
      assert.ok(Number.isInteger(f), `fee ${p} ${t}`);
    }
  }
});

console.log(`\n${passed} test o'tdi${failed ? `, ${failed} xato` : ''}.`);
if (failed) process.exitCode = 1;
