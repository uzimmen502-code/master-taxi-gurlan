/**
 * «AVA Супермаркет» — тоза функциялар (эмуляторсиз): node test/supermarket_pure.test.js
 */
'use strict';
const assert = require('assert');
const sm = require('../supermarket');
const TAX = require('../tools/data/supermarket_taxonomy_v1.json');
const SETTINGS = require('../tools/data/supermarket_settings_v1.json');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.message}`); }
};
const clone = (o) => JSON.parse(JSON.stringify(o));

const BEEF = { smGroupId: 'beef', smStatus: 'active', price: 80000, qtyStep: 0.5, stock: 10, unit: 'kg', weighed: true, name: 'Мол гўшти', smVariety: { id: 'lean' } };
const MILK = { smGroupId: 'milk', smStatus: 'active', price: 12000, qtyStep: 1, stock: 5, unit: 'l', weighed: false, name: 'Сут' };
const price = (items, products = { beef: BEEF, milk: MILK }) => sm.priceSupermarketOrder({
  items: items.map(([productId, qty]) => ({ productId, qMilli: sm.toMilli(qty) })), products, feeBp: 1100, weighHoldPercent: 10,
});

check('P1 toMilli: каср 3 хонагача, бошқаси null', () => {
  assert.strictEqual(sm.toMilli(1.5), 1500);
  assert.strictEqual(sm.toMilli(0.1 + 0.2), 300);
  assert.strictEqual(sm.toMilli(2), 2000);
  assert.strictEqual(sm.toMilli(1.2345), null);
  assert.strictEqual(sm.toMilli('1'), null);
  assert.strictEqual(sm.toMilli(NaN), null);
  assert.strictEqual(sm.toMilli(Infinity), null);
});

check('P2 қатор суммаси бутун, round half up', () => {
  assert.strictEqual(sm.lineTotalOf(35000, 1500), 52500);
  assert.strictEqual(sm.lineTotalOf(333, 500), 167); // 166.5 → 167
  assert.strictEqual(sm.lineTotalOf(333, 499), 166); // 166.167
  assert.ok(Number.isInteger(sm.lineTotalOf(12345, 1333)));
});

check('P3 тортиш ушлаб туриши = ceil(10%), бутун; 0% → 0', () => {
  assert.strictEqual(sm.holdExtraOf(52500, 10), 5250);
  assert.strictEqual(sm.holdExtraOf(52501, 10), 5251); // 5250.1 → 5251
  assert.strictEqual(sm.holdExtraOf(9, 10), 1);
  assert.strictEqual(sm.holdExtraOf(52500, 0), 0);
});

check('P4 етказиш ҳақи: жонли platformDeliveryFeeFromSettings билан бир хил (fail closed, bps, версия)', () => {
  assert.strictEqual(sm.feeBpOf(11), 1100);
  assert.strictEqual(sm.feeBpOf(undefined), 0);
  assert.strictEqual(sm.feeBpOf(150), 10000);
  assert.strictEqual(sm.feeOf(100000, 1100), 11000);
  assert.strictEqual(sm.feeOf(12345, 1100), 1358); // 1357.95
  for (const g of [1, 99, 12345, 144000, 999999, 7777777]) {
    for (const pct of [0, 5, 11, 12.5]) assert.strictEqual(sm.feeOf(g, sm.feeBpOf(pct)), Math.round(g * pct / 100), `${g} ${pct}`);
  }
  assert.strictEqual(sm.feeConfigFromApp({}), null);
  assert.strictEqual(sm.feeConfigFromApp({ platformDeliveryFeePercent: -1 }), null);
  assert.strictEqual(sm.feeConfigFromApp({ platformDeliveryFeePercent: '' }), null);
  assert.strictEqual(sm.feeConfigFromApp({ platformDeliveryFeePercent: null }), null);
  assert.deepStrictEqual(sm.feeConfigFromApp({ platformDeliveryFeePercent: 11, platformDeliveryFeeVersion: 3 }), { percent: 11, bps: 1100, version: 3 });
  assert.deepStrictEqual(sm.feeConfigFromApp({ platformDeliveryFeePercent: '11' }), { percent: 11, bps: 1100, version: 0 });
  assert.deepStrictEqual(sm.feeConfigFromApp({ platformDeliveryFeePercent: 200 }), { percent: 100, bps: 10000, version: 0 });
  assert.deepStrictEqual(sm.feeConfigFromApp({ platformDeliveryFeePercent: 0 }), { percent: 0, bps: 0, version: 0 });
});

check('P5 қайта нархлаш: goods + ceil10%(тортиладиган) + fee(goods) = hold', () => {
  const r = price([['beef', 1.5], ['milk', 2]]);
  assert.ok(r.ok, JSON.stringify(r));
  assert.deepStrictEqual([r.goods, r.extras, r.fee, r.hold], [144000, 12000, 15840, 171840]);
  const beef = r.lines[0];
  assert.deepStrictEqual([beef.total, beef.holdExtra, beef.qty, beef.unit, beef.smUnit, beef.weighed], [120000, 12000, 1.5, 'кг', 'kg', true]);
  assert.strictEqual(r.lines[1].holdExtra, 0);
  assert.deepStrictEqual(r.stockOps, [{ productId: 'beef', newStockMilli: 8500 }, { productId: 'milk', newStockMilli: 3000 }]);
  assert.ok([r.goods, r.extras, r.fee, r.hold].every(Number.isInteger));
});

check('P6 қадам / stock / ҳолат текшируви (+ чегара: qty == stock)', () => {
  assert.strictEqual(price([['beef', 1.3]]).code, 'QTY_STEP_INVALID');
  assert.strictEqual(price([['milk', 1.5]]).code, 'QTY_STEP_INVALID');
  assert.ok(price([['milk', 5]]).ok);
  const oos = price([['milk', 6]]);
  assert.deepStrictEqual([oos.code, oos.details.available], ['OUT_OF_STOCK', 5]);
  assert.strictEqual(price([['x', 1]]).code, 'PRODUCT_NOT_FOUND');
  assert.strictEqual(price([['milk', 1]], { milk: { ...MILK, smStatus: 'hidden' } }).code, 'PRODUCT_UNAVAILABLE');
  assert.strictEqual(price([['milk', 1]], { milk: { ...MILK, smGroupId: undefined } }).code, 'PRODUCT_UNAVAILABLE');
  assert.strictEqual(price([['milk', 1]], { milk: { ...MILK, smStatus: 'out_of_stock' } }).code, 'OUT_OF_STOCK');
  assert.strictEqual(price([['milk', 1]], { milk: { ...MILK, price: 0 } }).code, 'PRICE_MISSING');
  assert.strictEqual(price([['milk', 1]], { milk: { ...MILK, price: 1200.5 } }).code, 'PRICE_MISSING');
  assert.strictEqual(price([['milk', 1]], { milk: { ...MILK, stock: undefined } }).code, 'OUT_OF_STOCK');
});

check('P7 тортиш: ≤ qty×1.10; такрор — ўзгармайди; бошқа қиймат — LINE_ALREADY_SETTLED', () => {
  const lines = price([['beef', 1.5], ['milk', 2]]).lines;
  const ok = sm.applyWeights(lines, [{ productId: 'beef', actualQty: 1.65 }], 10);
  assert.ok(ok.ok && ok.changed);
  assert.deepStrictEqual([ok.lines[0].finalTotal, ok.stockDeltas.beef], [132000, -150]);
  assert.strictEqual(sm.applyWeights(lines, [{ productId: 'beef', actualQty: 1.651 }], 10).code, 'ACTUAL_QTY_OVER_LIMIT');
  assert.strictEqual(sm.applyWeights(lines, [{ productId: 'beef', actualQty: 0 }], 10).code, 'ACTUAL_QTY_INVALID');
  assert.strictEqual(sm.applyWeights(lines, [{ productId: 'milk', actualQty: 2 }], 10).code, 'LINE_NOT_WEIGHED');
  assert.strictEqual(sm.applyWeights(lines, [{ productId: 'zz', actualQty: 1 }], 10).code, 'LINE_NOT_FOUND');
  const again = sm.applyWeights(ok.lines, [{ productId: 'beef', actualQty: 1.65 }], 10);
  assert.ok(again.ok && !again.changed);
  assert.strictEqual(sm.applyWeights(ok.lines, [{ productId: 'beef', actualQty: 1.4 }], 10).code, 'LINE_ALREADY_SETTLED');
});

check('P8 ҳисоб-китоб: кам тортилди → фарқ қайтади; кўп → ушлангандан ОШМАЙДИ', () => {
  const r = price([['beef', 1.5], ['milk', 2]]);
  const less = sm.applyWeights(r.lines, [{ productId: 'beef', actualQty: 1.4 }], 10);
  const c1 = sm.computeCharge(less.lines, 1100);
  assert.deepStrictEqual([c1.goods, c1.extras, c1.fee, c1.target], [136000, 0, 14960, 150960]);
  assert.deepStrictEqual(sm.adjustment(r.hold, c1.target), { next: 150960, refund: 20880, capDiscount: 0 });
  const more = sm.applyWeights(r.lines, [{ productId: 'beef', actualQty: 1.65 }], 10);
  const c2 = sm.computeCharge(more.lines, 1100);
  assert.strictEqual(c2.target, 173160);
  assert.deepStrictEqual(sm.adjustment(r.hold, c2.target), { next: 171840, refund: 0, capDiscount: 1320 });
});

check('P9 қаторни олиш: қатор + унинг ушлаши + fee улуши қайтади', () => {
  const r = price([['beef', 1.5], ['milk', 2]]);
  const removedMilk = r.lines.map((l) => (l.productId === 'milk' ? { ...l, removed: { reason: 'x' } } : l));
  const c = sm.computeCharge(removedMilk, 1100);
  assert.deepStrictEqual([c.goods, c.extras, c.fee, c.target], [120000, 12000, 13200, 145200]);
  assert.strictEqual(sm.adjustment(r.hold, c.target).refund, 26640);
  const removedBeef = r.lines.map((l) => (l.productId === 'beef' ? { ...l, removed: { reason: 'x' } } : l));
  assert.strictEqual(sm.adjustment(r.hold, sm.computeCharge(removedBeef, 1100).target).refund, 171840 - (24000 + 2640));
});

// Эга 2026-11-28: дарвоза ФАҚАТ модул созламаси (module_gate ҳолати); settings stage/testers/districts йўқ.
check('P10 дарвоза: enabled — очиқ; hidden/coming_soon/soon — MODULE_CLOSED; бўш туман — DISTRICT_REQUIRED; fail-open unknown', () => {
  assert.deepStrictEqual(sm.gateFromModuleStatus('enabled', { districtId: 'gurlan', requireDistrict: true }).allowed, true);
  for (const st of ['hidden', 'coming_soon', 'soon']) {
    assert.strictEqual(sm.gateFromModuleStatus(st, { districtId: 'gurlan', requireDistrict: true }).reason, 'MODULE_CLOSED', st);
  }
  assert.strictEqual(sm.gateFromModuleStatus('enabled', { districtId: '', requireDistrict: true }).reason, 'DISTRICT_REQUIRED');
  assert.strictEqual(sm.gateFromModuleStatus('enabled', { districtId: '', requireDistrict: false }).allowed, true);
  assert.strictEqual(sm.gateFromModuleStatus('unknown', { districtId: 'gurlan', requireDistrict: true }).allowed, true);
  assert.ok(sm.messagesOf ? sm.messagesOf('MODULE_CLOSED').uz_Latn : true);
  assert.strictEqual(typeof sm.gateDecision, 'undefined', 'эски stage/testers дарвозаси олиб ташланди');
});

check('P10b созлама (эга 2026-11-28): stage/testerIds/districtIds/slots/cutoffMin ихтиёрий; юборилса — аввалгидек текширилади', () => {
  assert.ok(sm.validateSupermarketSettings({ weighHoldPercent: 10 }).ok);
  assert.ok(sm.validateSupermarketSettings({ weighHoldPercent: 10, courierPayout: { mode: 'percent', percent: 50 } }).ok);
  assert.ok(!sm.validateSupermarketSettings({ weighHoldPercent: 10, stage: 'on' }).ok);
  assert.ok(!sm.validateSupermarketSettings({ weighHoldPercent: 10, cutoffMin: 9999 }).ok);
  assert.ok(!sm.validateSupermarketSettings({}).ok, 'weighHoldPercent шарт');
});

check('P11 вақт оралиқлари: Тошкент вақти, cutoff, эртага — ҳаммаси', () => {
  const at = (h, m) => Date.UTC(2026, 10, 20, h - 5, m); // Тошкент соати → UTC
  const a = sm.availableSlots(SETTINGS, at(8, 0));
  assert.deepStrictEqual(a.today.map((s) => s.id), ['morning', 'afternoon', 'evening']);
  assert.strictEqual(a.today[0].date, '2026-11-20');
  assert.strictEqual(a.tomorrow[0].date, '2026-11-21');
  assert.deepStrictEqual(sm.availableSlots(SETTINGS, at(9, 0)).today.map((s) => s.id), ['morning', 'afternoon', 'evening']); // 540 ≤ 600−60
  assert.deepStrictEqual(sm.availableSlots(SETTINGS, at(9, 1)).today.map((s) => s.id), ['afternoon', 'evening']);
  assert.deepStrictEqual(sm.availableSlots(SETTINGS, at(23, 30)).today, []);
  assert.strictEqual(sm.availableSlots(SETTINGS, at(23, 30)).tomorrow.length, 3);
  assert.strictEqual(sm.availableSlots(SETTINGS, Date.UTC(2026, 10, 20, 19, 30)).tomorrow[0].date, '2026-11-22'); // Тошкент 00:30 21-нояб.
});

check('P12 seed таксономия: 9 бўлим / 90 гуруҳ, валид, uz_Latn янги алифбода', () => {
  assert.deepStrictEqual(sm.validateSupermarketTaxonomy(TAX), { ok: true, errors: [] });
  assert.strictEqual(TAX.categories.length, 9);
  assert.strictEqual(TAX.categories.reduce((n, c) => n + c.groups.length, 0), 90);
  const latn = [];
  for (const c of TAX.categories) { latn.push(c.names.uz_Latn); for (const g of c.groups) latn.push(g.names.uz_Latn); }
  for (const s of latn) assert.ok(!/o'|g'|sh|ch|ʻ/i.test(s), `эски лотин: ${s}`);
  const ids = TAX.categories.map((c) => c.id);
  assert.ok(ids.includes('household'));
  const beef = sm.findGroup(TAX, 'beef');
  assert.deepStrictEqual([beef.category.id, beef.group.unit, beef.group.step, beef.group.weighed], ['meat_fish', 'kg', 0.5, true]);
});

check('P13 таксономия валидатори — салбий ҳолатлар', () => {
  const t = clone(TAX);
  t.categories[1].groups[0].id = 'beef'; // такрор (бошқа бўлимда)
  t.categories[0].groups[1].unit = 'ton';
  t.categories[0].groups[2].step = 0;
  delete t.categories[2].names.ru;
  t.categories[3].groups[0].extra = 1;
  t.categories[4].groups[0].step = 0.0001;
  const v = sm.validateSupermarketTaxonomy(t);
  for (const e of ['GROUP_ID_DUPLICATE categories[1].groups[0].id', 'UNIT_INVALID categories[0].groups[1].unit',
    'STEP_INVALID categories[0].groups[2].step', 'NAME_MISSING categories[2].names.ru',
    'UNKNOWN_KEY categories[3].groups[0].extra', 'STEP_INVALID categories[4].groups[0].step']) {
    assert.ok(v.errors.includes(e), `${e} :: ${JSON.stringify(v.errors)}`);
  }
  assert.strictEqual(sm.validateSupermarketTaxonomy({ categories: [] }).ok, false);
  assert.strictEqual(sm.validateSupermarketTaxonomy(null).ok, false);
});

check('P14 созламалар валидатори', () => {
  assert.ok(sm.validateSupermarketSettings(SETTINGS).ok);
  const bad = { ...clone(SETTINGS), stage: 'beta', testerIds: ['12345'], weighHoldPercent: 10.5, cutoffMin: -1, x: 1 };
  bad.slots[0].endMin = 500;
  const v = sm.validateSupermarketSettings(bad);
  for (const e of ['STAGE_INVALID stage', 'TESTER_INVALID testerIds[0]', 'WEIGH_HOLD_PERCENT_INVALID weighHoldPercent',
    'CUTOFF_INVALID cutoffMin', 'UNKNOWN_KEY x', 'SLOT_END_INVALID slots[0].endMin']) {
    assert.ok(v.errors.includes(e), `${e} :: ${JSON.stringify(v.errors)}`);
  }
  assert.ok(!sm.validateSupermarketSettings({ ...clone(SETTINGS), weighHoldPercent: 51 }).ok);
  assert.ok(sm.validateSupermarketSettings({ ...clone(SETTINGS), weighHoldPercent: 50 }).ok);
});

check('P15 таклиф/харид нархи валидатори', () => {
  const o = { smGroupId: 'beef', smVariety: { id: 'lean', names: { uz_Cyrl: 'Лаҳм', uz_Latn: 'Lahm', ru: 'Постная' } }, stock: 12.5, smStatus: 'active', price: 85000 };
  assert.ok(sm.validateOffer(o).ok, JSON.stringify(sm.validateOffer(o)));
  const v = sm.validateOffer({ ...o, price: 85000.5, stock: -1, smStatus: 'on', unit: 'ton', packLabel: 'x'.repeat(41), role: 'admin' });
  for (const e of ['PRICE_INVALID offer.price', 'STOCK_INVALID offer.stock', 'SM_STATUS_INVALID offer.smStatus',
    'UNIT_INVALID offer.unit', 'PACK_LABEL_INVALID offer.packLabel', 'UNKNOWN_KEY offer.role']) assert.ok(v.errors.includes(e), e);
  assert.ok(sm.validateOffer({ ...o, packQty: 1.5, packUnit: 'l' }).ok);
  const pv = sm.validateOffer({ ...o, packQty: 0, packUnit: 'm' });
  assert.ok(pv.errors.includes('PACK_QTY_INVALID offer.packQty') && pv.errors.includes('PACK_UNIT_INVALID offer.packUnit'), JSON.stringify(pv.errors));
  assert.ok(sm.validateOffer({ ...o, packQty: 2 }).errors.includes('PACK_UNIT_INVALID offer.packUnit'));
  assert.ok(sm.validateOffer({ ...o, packUnit: 'kg' }).errors.includes('PACK_QTY_INVALID offer.packQty'));
  assert.ok(sm.validateCost({ purchasePrice: 70000, supplier: 'Бозор' }).ok);
  assert.ok(!sm.validateCost({ purchasePrice: 70000.5, supplier: 'Бозор' }).ok);
});

check('P16 қидирув токенлари: синоним + кирилл/лотин folding', () => {
  const g = sm.findGroup(TAX, 'beef');
  const tokens = sm.offerSearchTokens({ name: 'Мол гўшти', variety: { names: { uz_Cyrl: 'Лаҳм', uz_Latn: 'Lahm', ru: 'Постная' } }, group: g.group, category: g.category });
  for (const t of ['мол', 'mol', 'гўшти', "go'shti", 'лаҳм']) assert.ok(tokens.includes(t), `${t} :: ${tokens.join(',')}`);
  assert.ok(tokens.length <= 60);
  const p = sm.findGroup(TAX, 'potato');
  const t2 = sm.offerSearchTokens({ name: 'Картошка', variety: { names: { uz_Cyrl: 'Маҳаллий', uz_Latn: 'Mahalliy', ru: 'Местный' } }, group: p.group, category: p.category });
  assert.ok(t2.includes('картофель') && t2.includes('kartoshka'));
});

check('P17 хато хабарлари ва ҳамён изоҳлари — ҳар код учун 3 тил', () => {
  for (const k of Object.keys(sm.REFUND_NOTES)) for (const l of sm.LANGS) assert.ok(sm.REFUND_NOTES[k].messages[l], `${k}.${l}`);
  assert.deepStrictEqual([...sm.OPERATOR_ROLES], ['admin', 'superadmin', 'dispatcher']);
  for (const code of Object.keys(sm.MSG)) {
    const m = sm.messagesOf(code);
    for (const l of sm.LANGS) assert.ok(m[l] && m[l].length > 3, `${code}.${l}`);
    assert.ok(!/o'|g'/.test(m.uz_Latn), `${code} uz_Latn эски алифбо`);
  }
  assert.deepStrictEqual(sm.messagesOf('NOPE'), sm.messagesOf('INTERNAL'));
});

const passed = results.filter(Boolean).length;
console.log(`\n${passed}/${results.length} passed`);
process.exit(passed === results.length ? 0 : 1);
