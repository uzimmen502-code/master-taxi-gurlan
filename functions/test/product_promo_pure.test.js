/**
 * Маҳсулот белгиси (эга 2026-11-19/20) — тоза қоидалар: node test/product_promo_pure.test.js
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const P = require('../product_promo');

const DAY = 24 * 60 * 60 * 1000;
const H = 60 * 60 * 1000;
const NOW = Date.UTC(2026, 10, 20, 12, 0, 0);
const fv = { ts: () => 'TS', del: () => 'DEL', at: (ms) => ({ ms, toMillis: () => ms }) };

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
const opts = { nowMs: NOW, eventMs: NOW, fv };
// Нарх 10 000, 10 кун турибди.
const shop = (extra = {}) => ({ status: 'active', price: 10000, priceTracked: 10000, priceSince: fv.at(NOW - 10 * DAY), moderatedAt: 'x', ...extra });
const req = (extra = {}) => ({ kind: 'discount', percent: 10, until: NOW + 10 * DAY, requestedAt: NOW, ...extra });

// ── нарх математикаси ──
check('discounted: 10000 −10% = 9000', () => assert.strictEqual(P.discountedPrice(10000, 10), 9000));
check('discounted floor: 999 −10% = 899 (899.1)', () => assert.strictEqual(P.discountedPrice(999, 10), 899));
check('discounted: never below 1', () => assert.strictEqual(P.discountedPrice(1, 90), 1));
check('percent from base floor: 10000→8500 = 15; 30000→20000 = 33', () => {
  assert.strictEqual(P.discountPercent(10000, 8500), 15);
  assert.strictEqual(P.discountPercent(30000, 20000), 33);
  assert.strictEqual(P.discountPercent(100, 100), 0);
});

// ── 7 кун / 30 кун ойнаси ──
check('reference: ongoing 7d exactly → held', () => assert.strictEqual(P.referenceHeld(shop({ priceSince: fv.at(NOW - 7 * DAY) }), 10000, NOW), true));
check('reference: ongoing 6d23h → NOT held', () => assert.strictEqual(P.referenceHeld(shop({ priceSince: fv.at(NOW - (6 * DAY + 23 * H)) }), 10000, NOW), false));
check('reference: ongoing 100 days → held (overlap with last 30d)', () => assert.strictEqual(P.referenceHeld(shop({ priceSince: fv.at(NOW - 100 * DAY) }), 10000, NOW), true));
check('reference: history period overlapping window only 6d → NOT held', () => {
  const d = shop({ price: 9000, priceTracked: 9000, priceSince: fv.at(NOW - DAY), priceHistory: [{ price: 10000, from: fv.at(NOW - 60 * DAY), to: fv.at(NOW - 24 * DAY) }] });
  assert.strictEqual(P.referenceHeld(d, 10000, NOW), false);
});
check('reference: history period overlapping window 7d → held', () => {
  const d = shop({ price: 9000, priceTracked: 9000, priceSince: fv.at(NOW - DAY), priceHistory: [{ price: 10000, from: fv.at(NOW - 60 * DAY), to: fv.at(NOW - 23 * DAY) }] });
  assert.strictEqual(P.referenceHeld(d, 10000, NOW), true);
});
check('reference: promo periods do not count', () => {
  const d = shop({ price: 9000, priceTracked: 9000, priceSince: fv.at(NOW - DAY), priceHistory: [{ price: 9000, from: fv.at(NOW - 20 * DAY), to: fv.at(NOW - 2 * DAY), promo: true }] });
  assert.strictEqual(P.referenceHeld(d, 9000, NOW), false);
});

// ── сўров текшируви ──
check('request ok: percent 10 → valid', () => assert.deepStrictEqual(P.validatePromoRequest('tv_shop_items', shop(), req(), NOW), { ok: true, kind: 'discount', percent: 10, untilMs: NOW + 10 * DAY }));
check('request: until > 30d → UNTIL_TOO_FAR; exactly 30d ok', () => {
  assert.strictEqual(P.validatePromoRequest('tv_shop_items', shop(), req({ until: NOW + 30 * DAY + 1 }), NOW).reason, 'UNTIL_TOO_FAR');
  assert.strictEqual(P.validatePromoRequest('tv_shop_items', shop(), req({ until: NOW + 30 * DAY }), NOW).ok, true);
});
check('request: until past → UNTIL_INVALID', () => assert.strictEqual(P.validatePromoRequest('tv_shop_items', shop(), req({ until: NOW - 1 }), NOW).reason, 'UNTIL_INVALID'));
check('request: percent 0 / 91 / float → PERCENT_INVALID', () => {
  [0, 91, 10.5].forEach((p) => assert.strictEqual(P.validatePromoRequest('tv_shop_items', shop(), req({ percent: p }), NOW).reason, 'PERCENT_INVALID'));
});
check('request: price 6 days → PRICE_NOT_7_DAYS', () => assert.strictEqual(P.validatePromoRequest('tv_shop_items', shop({ priceSince: fv.at(NOW - 6 * DAY) }), req(), NOW).reason, 'PRICE_NOT_7_DAYS'));
check('request: price 0 / negotiable → PRICE_REQUIRED', () => {
  assert.strictEqual(P.validatePromoRequest('tv_shop_items', shop({ price: 0, priceTracked: 0 }), req(), NOW).reason, 'PRICE_REQUIRED');
  assert.strictEqual(P.validatePromoRequest('tv_shop_items', shop({ priceUnit: 'negotiable' }), req(), NOW).reason, 'PRICE_REQUIRED');
});
check('request: price 1 → DISCOUNT_TOO_SMALL (floor keeps 1)', () => assert.strictEqual(P.validatePromoRequest('tv_shop_items', shop({ price: 1, priceTracked: 1 }), req(), NOW).reason, 'DISCOUNT_TOO_SMALL'));
check('request: discount on top of active discount → PROMO_ACTIVE', () => {
  const d = shop({ price: 9000, priceTracked: 9000, promo: { kind: 'discount', basePrice: 10000, price: 9000 } });
  assert.strictEqual(P.validatePromoRequest('tv_shop_items', d, req(), NOW).reason, 'PROMO_ACTIVE');
});

// ── қўллаш ──
check('apply tv: price 9000, promo.base 10000, history closes base period', () => {
  const p = P.buildApplyPatch('tv_shop_items', shop(), { percent: 10, untilMs: NOW + DAY, actor: 'a', nowMs: NOW, fv });
  assert.strictEqual(p.price, 9000);
  assert.strictEqual(p.promo.basePrice, 10000);
  assert.strictEqual(p.promo.price, 9000);
  assert.deepStrictEqual(p.promo.base, { price: 10000 });
  assert.strictEqual(p.priceTracked, 9000);
  assert.strictEqual(p.priceHistory[0].price, 10000);
  assert.ok(!p.priceHistory[0].promo);
});
const ws = (extra = {}) => ({
  status: 'active', priceTracked: 10000, priceSince: fv.at(NOW - 10 * DAY),
  priceTiers: [{ minQty: 1, price: 10000 }, { minQty: 10, price: 9999 }],
  packs: [{ id: 'p1', label: '1 kg', priceTiers: [{ minQty: 1, price: 10000 }, { minQty: 10, price: 9999 }], unitWeightG: 1000 },
    { id: 'p2', label: '5 kg', priceTiers: [{ minQty: 1, price: 45001 }] }],
  ...extra,
});
check('apply wholesale: every tier and every pack tier, int floor', () => {
  const p = P.buildApplyPatch('wholesale_products', ws(), { percent: 10, untilMs: NOW + DAY, actor: 'a', nowMs: NOW, fv });
  assert.deepStrictEqual(p.priceTiers, [{ minQty: 1, price: 9000 }, { minQty: 10, price: 8999 }]);
  assert.deepStrictEqual(p.packs[0].priceTiers, [{ minQty: 1, price: 9000 }, { minQty: 10, price: 8999 }]);
  assert.deepStrictEqual(p.packs[1].priceTiers, [{ minQty: 1, price: 40500 }]);
  assert.strictEqual(p.packs[0].label, '1 kg');
  assert.strictEqual(p.packs[0].unitWeightG, 1000);
  assert.strictEqual(p.promo.basePrice, 10000);
  assert.strictEqual(p.promo.base.packs[1].priceTiers[0].price, 45001);
});
check('apply platform: price + priceTiers', () => {
  const p = P.buildApplyPatch('platform_products', { price: 2000, priceTiers: [{ minQty: 1, price: 2100 }], priceTracked: 2000, priceSince: fv.at(NOW - 9 * DAY) },
    { percent: 50, untilMs: NOW + DAY, actor: 'a', nowMs: NOW, fv });
  assert.strictEqual(p.price, 1000);
  assert.deepStrictEqual(p.priceTiers, [{ minQty: 1, price: 1050 }]);
});

// ── сотувчи акция пайтида нархни ўзгартиради ──
const R0 = req();
const promoOn = (extra = {}) => shop({
  price: 9000, priceTracked: 9000, priceSince: fv.at(NOW - DAY),
  promo: { kind: 'discount', percent: 10, basePrice: 10000, price: 9000, base: { price: 10000 }, applied: { price: 9000 }, until: fv.at(NOW + 5 * DAY) },
  promoState: { status: 'active', requestKey: P.requestKeyOf(R0) }, promoRequest: R0, ...extra,
});
check('seller sets price == base → promo cancelled (price stays base)', () => {
  const p = P.planPromoWrite('tv_shop_items', promoOn(), promoOn({ price: 10000 }), opts);
  assert.strictEqual(p.patch.promo, 'DEL');
  assert.strictEqual(p.patch.promoState.reason, 'PRICE_RESTORED');
  assert.ok(!('price' in p.patch));
  assert.strictEqual(p.patch.priceHistory.slice(-1)[0].promo, true);
});
check('seller sets price ≠ base (lower) → continues, % recomputed from base (floor)', () => {
  const p = P.planPromoWrite('tv_shop_items', promoOn(), promoOn({ price: 8550 }), opts);
  assert.strictEqual(p.decision, 'continued');
  assert.strictEqual(p.patch.promo.percent, 14);
  assert.strictEqual(p.patch.promo.sellerChanged, true);
  assert.strictEqual(p.patch.promo.basePrice, 10000);
});
check('seller sets price > base → cancelled PRICE_ABOVE_BASE', () => {
  const p = P.planPromoWrite('tv_shop_items', promoOn(), promoOn({ price: 12000 }), opts);
  assert.strictEqual(p.patch.promoState.reason, 'PRICE_ABOVE_BASE');
});
check('server-applied price (priceTracked == price) is NOT a seller change', () => {
  assert.strictEqual(P.planPromoWrite('tv_shop_items', promoOn(), promoOn(), opts), null);
});

// ── якунлаш (муддат / бекор) ──
check('end: price still server-set → base restored', () => {
  const { patch, restored } = P.buildEndPatch('tv_shop_items', promoOn(), { status: 'expired', reason: 'EXPIRED', nowMs: NOW, fv });
  assert.strictEqual(restored, true);
  assert.strictEqual(patch.price, 10000);
  assert.strictEqual(patch.priceTracked, 10000);
  assert.strictEqual(patch.promo, 'DEL');
  assert.strictEqual(patch.promoState.requestKey, P.requestKeyOf(R0));
});
check('end: seller changed price → keep seller price, drop badge', () => {
  const d = promoOn({ price: 8550, priceTracked: 8550, promo: { ...promoOn().promo, sellerChanged: true, percent: 14 } });
  const { patch, restored } = P.buildEndPatch('tv_shop_items', d, { status: 'expired', reason: 'EXPIRED', nowMs: NOW, fv });
  assert.strictEqual(restored, false);
  assert.ok(!('price' in patch));
  assert.strictEqual(patch.promo, 'DEL');
});
check('end: wholesale restores tiers + packs only if untouched', () => {
  const ap = P.buildApplyPatch('wholesale_products', ws(), { percent: 10, untilMs: NOW + DAY, actor: 'a', nowMs: NOW, fv });
  const d = { ...ws(), priceTiers: ap.priceTiers, packs: ap.packs, priceTracked: 9000, promo: ap.promo };
  const r1 = P.buildEndPatch('wholesale_products', d, { status: 'expired', reason: 'EXPIRED', nowMs: NOW, fv });
  assert.strictEqual(r1.restored, true);
  assert.deepStrictEqual(r1.patch.packs, ws().packs);
  const d2 = { ...d, packs: [{ ...d.packs[0], label: 'x' }, d.packs[1]] };
  assert.strictEqual(P.buildEndPatch('wholesale_products', d2, { status: 'expired', reason: 'EXPIRED', nowMs: NOW, fv }).restored, false);
});
check('end: Aksiya → just removed', () => {
  const d = shop({ promo: { kind: 'promo', until: fv.at(NOW) } });
  const r = P.buildEndPatch('tv_shop_items', d, { status: 'expired', reason: 'EXPIRED', nowMs: NOW, fv });
  assert.strictEqual(r.restored, false);
  assert.strictEqual(r.patch.promo, 'DEL');
});

// ── режа: сўровлар ──
check('plan: discount request → pending with newPrice (badge unchanged until moderation)', () => {
  const p = P.planPromoWrite('tv_shop_items', shop(), shop({ promoRequest: req() }), opts);
  assert.strictEqual(p.patch.promoState.status, 'pending');
  assert.strictEqual(p.patch.promoState.newPrice, 9000);
  assert.ok(!('price' in p.patch));
});
check('plan: same request again → no-op', () => {
  const r = req();
  const d = shop({ promoRequest: r, promoState: { status: 'pending', requestKey: P.requestKeyOf(r) } });
  assert.strictEqual(P.planPromoWrite('tv_shop_items', d, d, opts), null);
});
check('plan: price change clears pending request', () => {
  const r = req();
  const d = shop({ price: 9500, promoRequest: r, promoState: { status: 'pending', requestKey: P.requestKeyOf(r) } });
  assert.strictEqual(P.planPromoWrite('tv_shop_items', d, d, opts).patch.promoState.reason, 'PRICE_CHANGED');
});
check('plan: Aksiya → active immediately', () => {
  const p = P.planPromoWrite('tv_shop_items', shop(), shop({ promoRequest: { kind: 'promo', until: NOW + DAY, requestedAt: NOW } }), opts);
  assert.strictEqual(p.patch.promo.kind, 'promo');
});
check('plan: request deleted (state active with key) → restore', () => {
  const d = promoOn();
  delete d.promoRequest;
  const p = P.planPromoWrite('tv_shop_items', null, d, opts);
  assert.ok(p, 'plan');
  assert.strictEqual(p.patch.price, 10000);
  assert.strictEqual(p.patch.promoState.reason, 'CANCELLED');
});
check('plan: platform_products ignores promoRequest', () => {
  const d = { price: 100, priceTracked: 100, priceSince: fv.at(NOW - DAY), promoRequest: req() };
  assert.strictEqual(P.planPromoWrite('platform_products', d, d, opts), null);
});

// ── Ulgurji: нарх-фақат таҳрир модерациясиз ──
check('packs: price-only change → not content; label change → content', () => {
  const a = ws();
  const b = ws({ packs: a.packs.map((p) => ({ ...p, priceTiers: p.priceTiers.map((t) => ({ ...t, price: t.price + 1 })) })) });
  assert.strictEqual(P.packsNonPriceChanged(a, b), false);
  assert.strictEqual(P.packsNonPriceChanged(a, ws({ packs: [{ ...a.packs[0], label: 'New' }, a.packs[1]] })), true);
  assert.strictEqual(P.packsNonPriceChanged(a, ws({ packs: [a.packs[0]] })), true, 'qadoq olib tashlandi');
  assert.strictEqual(P.packsNonPriceChanged(a, ws({ packs: [{ ...a.packs[0], priceTiers: [{ minQty: 2, price: 1 }] }, a.packs[1]] })), false, 'pog\'ona tuzilmasi ham narx');
});
check('plan: active wholesale, pack label edited while staying active → server sets pending', () => {
  const a = ws();
  const b = ws({ packs: [{ ...a.packs[0], label: 'New' }, a.packs[1]] });
  assert.strictEqual(P.planPromoWrite('wholesale_products', a, b, opts).patch.status, 'pending');
});
check('plan: active wholesale, price-only edit → stays active', () => {
  const a = ws();
  const b = ws({ priceTiers: [{ minQty: 1, price: 11000 }] });
  const p = P.planPromoWrite('wholesale_products', a, b, opts);
  assert.ok(!('status' in p.patch));
  assert.strictEqual(p.patch.priceTracked, 11000);
});

// ── бошқа ──
check('firstActiveAt rules', () => {
  assert.strictEqual(P.shouldStampFirstActive('wholesale_products', null, { status: 'active' }), true);
  assert.strictEqual(P.shouldStampFirstActive('tv_shop_items', { status: 'expired', moderatedAt: 1 }, { status: 'active' }), false);
  assert.strictEqual(P.shouldStampFirstActive('platform_products', null, { status: 'active' }), false);
});
check('stockLeft', () => {
  const prod = { packs: [{ id: 'p1', label: 'a', priceTiers: [{}] }, { id: 'p2', label: 'b', priceTiers: [{}] }] };
  assert.strictEqual(P.stockLeftOf(prod, { packs: { p1: 2, p2: 1 } }), 3);
  assert.strictEqual(P.stockLeftOf(prod, { packs: { p1: 2 } }), null);
});
check('packIdsOf parity with functions_demand source (if present)', () => {
  const src = path.join(__dirname, '..', '..', 'functions_demand', 'api', 'wholesale_stock.js');
  if (!fs.existsSync(src)) { console.log('  (functions_demand/api/wholesale_stock.js yo\'q — o\'tkazildi)'); return; }
  const demand = require(src);
  if (typeof demand.packIdsOf === 'function') assert.deepStrictEqual(P.packIdsOf({}), demand.packIdsOf({}));
});
check('messages: 3 languages', () => ['uz_Cyrl', 'uz_Latn', 'ru'].forEach((l) => assert.ok(P.renderMessage('promo_approved', l, { title: 't', percent: 5 }).body.includes('5'))));

const failed = results.filter((x) => !x).length;
console.log(`\n${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
