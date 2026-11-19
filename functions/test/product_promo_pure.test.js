/**
 * Маҳсулот белгиси (эга 2026-11-19) — тоза қоидалар: node test/product_promo_pure.test.js
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const P = require('../product_promo');

const DAY = 24 * 60 * 60 * 1000;
const H = 60 * 60 * 1000;
const NOW = Date.UTC(2026, 10, 19, 12, 0, 0);
// Тест fv: оддий қийматлар.
const fv = { ts: () => 'TS', del: () => 'DEL', at: (ms) => ({ ms, toMillis: () => ms }) };

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
const hist = (price, fromMs, toMs) => [{ price, from: fromMs, to: toMs }];
const req = (extra = {}) => ({ kind: 'discount', oldPrice: 100000, until: NOW + 10 * DAY, requestedAt: NOW, ...extra });

// ── фоиз ──
check('percent floor: 100000→80000 = 20', () => assert.strictEqual(P.discountPercent(100000, 80000), 20));
check('percent floor: 30000→20000 = 33 (33.33 floor)', () => assert.strictEqual(P.discountPercent(30000, 20000), 33));
check('percent floor: 999→1 = 99 (99.89 floor)', () => assert.strictEqual(P.discountPercent(999, 1), 99));
check('percent: price >= old → 0', () => {
  assert.strictEqual(P.discountPercent(100, 100), 0);
  assert.strictEqual(P.discountPercent(100, 120), 0);
  assert.strictEqual(P.discountPercent(0, 0), 0);
});
check('percent: float input rejected → 0', () => assert.strictEqual(P.discountPercent(100.5, 50), 0));

// ── 7 кун чегараси ──
check('7-day: 6d23h → NOT held', () => {
  const v = P.validatePromoRequest({ req: req(), price: 80000, history: hist(100000, NOW - (6 * DAY + 23 * H) - H, NOW - H), nowMs: NOW });
  assert.deepStrictEqual(v, { ok: false, reason: 'OLD_PRICE_NOT_7_DAYS' });
});
check('7-day: exactly 7d → held', () => {
  const v = P.validatePromoRequest({ req: req(), price: 80000, history: hist(100000, NOW - 7 * DAY, NOW), nowMs: NOW });
  assert.strictEqual(v.ok, true);
  assert.strictEqual(v.percent, 20);
});
check('7-day: 7d minus 1 ms → NOT held', () => {
  const v = P.validatePromoRequest({ req: req(), price: 80000, history: hist(100000, NOW - 7 * DAY + 1, NOW), nowMs: NOW });
  assert.strictEqual(v.ok, false);
});
check('7-day: other price in history does not count', () => {
  const v = P.validatePromoRequest({ req: req({ oldPrice: 120000 }), price: 80000, history: hist(100000, NOW - 20 * DAY, NOW), nowMs: NOW });
  assert.strictEqual(v.reason, 'OLD_PRICE_NOT_7_DAYS');
});
check('7-day: period ended > 30 days ago (PROPOSED lookback) → NOT held', () => {
  const v = P.validatePromoRequest({ req: req(), price: 80000, history: hist(100000, NOW - 60 * DAY, NOW - 31 * DAY), nowMs: NOW });
  assert.strictEqual(v.reason, 'OLD_PRICE_NOT_7_DAYS');
});
check('7-day: entry with unknown start → NOT held', () => {
  const v = P.validatePromoRequest({ req: req(), price: 80000, history: [{ price: 100000, from: null, to: NOW }], nowMs: NOW });
  assert.strictEqual(v.reason, 'OLD_PRICE_NOT_7_DAYS');
});

// ── муддат ──
check('until > 30 days → UNTIL_TOO_FAR', () => {
  const v = P.validatePromoRequest({ req: req({ kind: 'promo', until: NOW + 30 * DAY + 1 }), price: 1, history: [], nowMs: NOW });
  assert.strictEqual(v.reason, 'UNTIL_TOO_FAR');
});
check('until exactly 30 days → ok', () => {
  const v = P.validatePromoRequest({ req: req({ kind: 'promo', until: NOW + 30 * DAY }), price: 1, history: [], nowMs: NOW });
  assert.strictEqual(v.ok, true);
});
check('until in the past → UNTIL_INVALID', () => {
  const v = P.validatePromoRequest({ req: req({ kind: 'promo', until: NOW - 1 }), price: 1, history: [], nowMs: NOW });
  assert.strictEqual(v.reason, 'UNTIL_INVALID');
});
check('until measured from requestedAt (not later trigger time)', () => {
  const v = P.validatePromoRequest({ req: req({ kind: 'promo', requestedAt: NOW - DAY, until: NOW + 30 * DAY - H }), price: 1, history: [], nowMs: NOW });
  assert.strictEqual(v.reason, 'UNTIL_TOO_FAR');
});

// ── бошқа текширувлар ──
check('kind invalid', () => assert.strictEqual(P.validatePromoRequest({ req: req({ kind: 'free' }), price: 1, history: [], nowMs: NOW }).reason, 'KIND_INVALID'));
check('old price not higher', () => assert.strictEqual(P.validatePromoRequest({ req: req({ oldPrice: 80000 }), price: 80000, history: hist(80000, 0, NOW), nowMs: NOW }).reason, 'OLD_PRICE_NOT_HIGHER'));
check('discount < 1% → DISCOUNT_TOO_SMALL', () => assert.strictEqual(P.validatePromoRequest({ req: req({ oldPrice: 1000 }), price: 999, history: hist(1000, NOW - 8 * DAY, NOW), nowMs: NOW }).reason, 'DISCOUNT_TOO_SMALL'));
check('price 0 / negotiable → PRICE_REQUIRED', () => {
  assert.strictEqual(P.validatePromoRequest({ req: req(), price: 0, history: [], nowMs: NOW }).reason, 'PRICE_REQUIRED');
  assert.strictEqual(P.validatePromoRequest({ req: req(), price: 5, history: [], nowMs: NOW, priceUnit: 'negotiable' }).reason, 'PRICE_REQUIRED');
});
check('old price float → OLD_PRICE_INVALID', () => assert.strictEqual(P.validatePromoRequest({ req: req({ oldPrice: 100.5 }), price: 50, history: [], nowMs: NOW }).reason, 'OLD_PRICE_INVALID'));

// ── wholesale нархи ──
check('priceOf wholesale = smallest minQty tier', () => {
  assert.strictEqual(P.priceOf('wholesale_products', { priceTiers: [{ minQty: 10, price: 9000 }, { minQty: 1, price: 10000 }] }), 10000);
  assert.strictEqual(P.priceOf('wholesale_products', { priceTiers: [] }), null);
  assert.strictEqual(P.priceOf('tv_shop_items', { price: 5 }), 5);
  assert.strictEqual(P.priceOf('tv_shop_items', { price: 5.5 }), null);
});

// ── режа ──
const shop = (extra = {}) => ({ status: 'active', price: 100000, priceTracked: 100000, priceSince: fv.at(NOW - 10 * DAY), moderatedAt: 'x', ...extra });
check('plan: legacy doc (no priceTracked) → start tracking, no history', () => {
  const p = P.planPromoWrite('tv_shop_items', shop(), { status: 'active', price: 5, moderatedAt: 'x' }, { nowMs: NOW, eventMs: NOW, fv });
  assert.strictEqual(p.patch.priceTracked, 5);
  assert.strictEqual(p.patch.priceSince.ms, NOW);
  assert.ok(!('priceHistory' in p.patch));
});
check('plan: no change → null (idempotent)', () => {
  assert.strictEqual(P.planPromoWrite('tv_shop_items', shop(), shop(), { nowMs: NOW, eventMs: NOW, fv }), null);
});
check('plan: price change resets priceSince + closes old period', () => {
  const p = P.planPromoWrite('tv_shop_items', shop(), shop({ price: 80000 }), { nowMs: NOW, eventMs: NOW - 1000, fv });
  assert.strictEqual(p.patch.priceTracked, 80000);
  assert.strictEqual(p.patch.priceSince.ms, NOW - 1000);
  assert.strictEqual(p.patch.priceHistory.length, 1);
  assert.strictEqual(p.patch.priceHistory[0].price, 100000);
  assert.strictEqual(p.patch.priceHistory[0].from.ms, NOW - 10 * DAY);
  assert.strictEqual(p.patch.priceHistory[0].to.ms, NOW - 1000);
});
check('plan: price drop + discount request in ONE write → pending with percent', () => {
  const p = P.planPromoWrite('tv_shop_items', shop(), shop({ price: 80000, promoRequest: req() }), { nowMs: NOW, eventMs: NOW, fv });
  assert.strictEqual(p.decision, 'discount_pending');
  assert.strictEqual(p.patch.promoState.status, 'pending');
  assert.strictEqual(p.patch.promoState.percent, 20);
  assert.strictEqual(p.patch.promoState.price, 80000);
  assert.ok(!('promo' in p.patch), 'moderatsiyagacha badge yo\'q');
});
check('plan: price changed 6 days after previous change → rejected 7-day', () => {
  const p = P.planPromoWrite('tv_shop_items', shop(), shop({ priceSince: fv.at(NOW - 6 * DAY), price: 80000, promoRequest: req() }), { nowMs: NOW, eventMs: NOW, fv });
  assert.strictEqual(p.patch.promoState.status, 'rejected');
  assert.strictEqual(p.patch.promoState.reason, 'OLD_PRICE_NOT_7_DAYS');
});
check('plan: same request again → no re-evaluation', () => {
  const r = req();
  const cur = shop({ price: 80000, priceTracked: 80000, promoRequest: r, promoState: { status: 'pending', requestKey: P.requestKeyOf(r) } });
  assert.strictEqual(P.planPromoWrite('tv_shop_items', cur, cur, { nowMs: NOW, eventMs: NOW, fv }), null);
});
check('plan: promo (Aksiya) → active immediately, no moderation', () => {
  const p = P.planPromoWrite('tv_shop_items', shop(), shop({ promoRequest: req({ kind: 'promo', oldPrice: undefined }) }), { nowMs: NOW, eventMs: NOW, fv });
  assert.strictEqual(p.patch.promo.kind, 'promo');
  assert.strictEqual(p.patch.promoState.status, 'active');
});
check('plan: price change clears approved discount', () => {
  const r = req();
  const cur = shop({ price: 70000, priceTracked: 80000, promoRequest: r, promo: { kind: 'discount', percent: 20 }, promoState: { status: 'active', requestKey: P.requestKeyOf(r) } });
  const p = P.planPromoWrite('tv_shop_items', cur, cur, { nowMs: NOW, eventMs: NOW, fv });
  assert.strictEqual(p.patch.promo, 'DEL');
  assert.strictEqual(p.patch.promoState.reason, 'PRICE_CHANGED');
});
check('plan: price change keeps Aksiya (no percent)', () => {
  const r = req({ kind: 'promo' });
  const cur = shop({ price: 70000, priceTracked: 80000, promoRequest: r, promo: { kind: 'promo' }, promoState: { status: 'active', requestKey: P.requestKeyOf(r) } });
  const p = P.planPromoWrite('tv_shop_items', cur, cur, { nowMs: NOW, eventMs: NOW, fv });
  assert.ok(!('promo' in p.patch));
  assert.ok(!('promoState' in p.patch));
});
check('plan: request deleted → cancelled, badge removed', () => {
  const cur = shop({ promo: { kind: 'promo' }, promoState: { status: 'active', requestKey: 'k' } });
  const p = P.planPromoWrite('tv_shop_items', cur, cur, { nowMs: NOW, eventMs: NOW, fv });
  assert.strictEqual(p.patch.promo, 'DEL');
  assert.strictEqual(p.patch.promoState.reason, 'CANCELLED');
});
check('plan: history capped at 10', () => {
  const h = Array.from({ length: 10 }, (_, i) => ({ price: i + 1, from: fv.at(i), to: fv.at(i + 1) }));
  const p = P.planPromoWrite('tv_shop_items', shop(), shop({ price: 1, priceHistory: h }), { nowMs: NOW, eventMs: NOW, fv });
  assert.strictEqual(p.patch.priceHistory.length, 10);
  assert.strictEqual(p.patch.priceHistory[9].price, 100000);
  assert.strictEqual(p.patch.priceHistory[0].price, 2);
});
check('firstActiveAt: create active / first approval yes; re-approval no', () => {
  assert.strictEqual(P.shouldStampFirstActive('wholesale_products', null, { status: 'active' }), true);
  assert.strictEqual(P.shouldStampFirstActive('tv_shop_items', { status: 'pending' }, { status: 'active' }), true);
  assert.strictEqual(P.shouldStampFirstActive('tv_shop_items', { status: 'expired', moderatedAt: 1 }, { status: 'active' }), false);
  assert.strictEqual(P.shouldStampFirstActive('tv_shop_items', { status: 'active' }, { status: 'active' }), false);
  assert.strictEqual(P.shouldStampFirstActive('tv_shop_items', { status: 'pending' }, { status: 'active', firstActiveAt: 1 }), false);
  assert.strictEqual(P.shouldStampFirstActive('wholesale_products', { status: 'pending', publishedAt: 1 }, { status: 'active' }), false);
});

// ── қолдиқ ──
check('stockLeft: sum over all packs; missing pack → unknown', () => {
  const prod = { packs: [{ id: 'p1', label: 'a', priceTiers: [{}] }, { id: 'p2', label: 'b', priceTiers: [{}] }] };
  assert.strictEqual(P.stockLeftOf(prod, { packs: { p1: 2, p2: 1 } }), 3);
  assert.strictEqual(P.stockLeftOf(prod, { packs: { p1: 2 } }), null);
  assert.strictEqual(P.stockLeftOf({}, { packs: { default: 4 } }), 4);
  assert.strictEqual(P.stockLeftOf({}, null), null);
});
check('packIdsOf parity with functions_demand source (if present)', () => {
  const src = path.join(__dirname, '..', '..', 'functions_demand', 'api', 'wholesale_stock.js');
  if (!fs.existsSync(src)) { console.log('  (functions_demand/api/wholesale_stock.js bu daraxtda yo\'q — o\'tkazildi)'); return; }
  const demand = require(src);
  if (typeof demand.packIdsOf !== 'function') return;
  const cases = [{}, { packs: [{ id: 'p1', label: 'a', priceTiers: [{}] }, { id: 'p1', label: 'b', priceTiers: [{}] }, { id: 'x', label: 'c', priceTiers: [{}] }] }];
  cases.forEach((c) => assert.deepStrictEqual(P.packIdsOf(c), demand.packIdsOf(c)));
});
check('messages: 3 languages', () => {
  ['uz_Cyrl', 'uz_Latn', 'ru'].forEach((l) => assert.ok(P.renderMessage('promo_approved', l, { title: 't', percent: 5 }).body.includes('5')));
});

const failed = results.filter((x) => !x).length;
console.log(`\n${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
