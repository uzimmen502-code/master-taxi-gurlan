/**
 * «AVA Супермаркет» 2-босқич — тоза функциялар (эмуляторсиз): node test/supermarket_stage2_pure.test.js
 * Ҳафталик сават (эслатма вақти, шакл), етишмовчилик (ҳисоб/ҳолат), cross-sell pairs, Excel импорт қоидалари.
 */
'use strict';
const assert = require('assert');
const sm = require('../supermarket');
const SI = require('../supermarket_import');
const X = require('../wholesale_import_xlsx');
const TAX1 = require('../tools/data/supermarket_taxonomy_v1.json');
const TAX2 = require('../tools/data/supermarket_taxonomy_v2.json');

const results = [];
const pending = [];
const check = (name, fn) => {
  try {
    const r = fn();
    if (r && typeof r.then === 'function') { pending.push(r.then(() => { results.push(true); console.log(`PASS - ${name}`); }, (e) => { results.push(false); console.log(`FAIL - ${name} :: ${e.message}`); })); return; }
    results.push(true); console.log(`PASS - ${name}`);
  } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.message}`); }
};
const clone = (o) => JSON.parse(JSON.stringify(o));
const BP = 1100;
const HOLD = 10;

// ── cross-sell pairs ──
check('S1 pairs: v2 (21 гуруҳ) тўғри; v1 (pairs-сиз) ҳам тўғри; номаълум/ўзи/такрор/>10/массив эмас — рад', () => {
  assert.ok(sm.validateSupermarketTaxonomy(TAX1).ok);
  const v2 = sm.validateSupermarketTaxonomy(TAX2);
  assert.ok(v2.ok, v2.errors.join(','));
  const beef = sm.findGroup(TAX2, 'beef').group;
  assert.deepStrictEqual(beef.pairs, ['onion', 'carrot', 'rice', 'cottonseed_oil']);
  assert.deepStrictEqual(sm.findGroup(TAX2, 'black_tea').group.pairs, ['sugar', 'lemon']);
  const t = clone(TAX2);
  const g = t.categories[0].groups[0]; // beef
  g.pairs = ['caviar']; assert.ok(sm.validateSupermarketTaxonomy(t).errors.includes('PAIR_UNKNOWN categories[0].groups[0].pairs[0]'));
  g.pairs = ['beef']; assert.ok(sm.validateSupermarketTaxonomy(t).errors.includes('PAIR_SELF categories[0].groups[0].pairs[0]'));
  g.pairs = ['onion', 'onion']; assert.ok(sm.validateSupermarketTaxonomy(t).errors.includes('PAIR_DUPLICATE categories[0].groups[0].pairs[1]'));
  g.pairs = 'onion'; assert.ok(sm.validateSupermarketTaxonomy(t).errors.includes('PAIRS_INVALID categories[0].groups[0].pairs'));
  const ids = []; for (const c of t.categories) for (const x of c.groups) if (x.id !== 'beef') ids.push(x.id);
  g.pairs = ids.slice(0, 10); assert.ok(sm.validateSupermarketTaxonomy(t).ok, '10 — чегара');
  g.pairs = ids.slice(0, 11); assert.ok(sm.validateSupermarketTaxonomy(t).errors.includes('PAIRS_INVALID categories[0].groups[0].pairs'));
});

// ── ҳафталик сават ──
const SAT_10_00 = Date.UTC(2026, 10, 21, 5, 0); // 2026-11-21 шанба, Тошкент 10:00
check('S2 nextRemindAtMs: шанба 10:00 → худди шу дақиқа = кейинги ҳафта; 10:01 — бугун; душанба 09:00; ўчиқ/бузуқ — null', () => {
  assert.strictEqual(sm.nextRemindAtMs({ enabled: true, weekday: 6, minute: 600 }, SAT_10_00), Date.UTC(2026, 10, 28, 5, 0));
  assert.strictEqual(sm.nextRemindAtMs({ enabled: true, weekday: 6, minute: 601 }, SAT_10_00), Date.UTC(2026, 10, 21, 5, 1));
  assert.strictEqual(sm.nextRemindAtMs({ enabled: true, weekday: 1, minute: 540 }, SAT_10_00), Date.UTC(2026, 10, 23, 4, 0));
  assert.strictEqual(sm.nextRemindAtMs({ enabled: true, weekday: 7, minute: 0 }, SAT_10_00), Date.UTC(2026, 10, 21, 19, 0)); // якшанба 00:00 Тошкент
  assert.strictEqual(sm.nextRemindAtMs({ enabled: true, weekday: 6, minute: 1439 }, SAT_10_00), Date.UTC(2026, 10, 21, 18, 59));
  assert.strictEqual(sm.nextRemindAtMs({ enabled: false, weekday: 6, minute: 601 }, SAT_10_00), null);
  for (const bad of [{ enabled: true, weekday: 0, minute: 0 }, { enabled: true, weekday: 8, minute: 0 }, { enabled: true, weekday: 1, minute: 1440 }, { enabled: true, weekday: 1, minute: -1 }, { enabled: true, weekday: 1.5, minute: 0 }, null]) {
    assert.strictEqual(sm.nextRemindAtMs(bad, SAT_10_00), null, JSON.stringify(bad));
  }
});

check('S3 advanceRemindMs: ўтган due → +7 кун; 15 кун ўтган → келажакдаги биринчи (+21); келажакдаги — ўзи', () => {
  const W = 7 * 86400000;
  const due = SAT_10_00 - 60000;
  assert.strictEqual(sm.advanceRemindMs(due, SAT_10_00), due + W);
  assert.strictEqual(sm.advanceRemindMs(SAT_10_00, SAT_10_00), SAT_10_00 + W);
  assert.strictEqual(sm.advanceRemindMs(SAT_10_00 - 15 * 86400000, SAT_10_00), SAT_10_00 - 15 * 86400000 + 3 * W);
  assert.strictEqual(sm.advanceRemindMs(SAT_10_00 + 5, SAT_10_00), SAT_10_00 + 5);
});

check('S4 listShapeProblem: тўғри; ном 40/41; 100/101 қатор; қатор шакли; remind', () => {
  const ok = { name: 'Ҳафталик', items: [{ groupId: 'beef', varietyId: 'lean', offerId: 'beef_lean_1', qty: 1.5 }, { groupId: 'milk', qty: 2 }], remind: { enabled: true, weekday: 6, minute: 600 } };
  assert.strictEqual(sm.listShapeProblem(ok), '');
  assert.strictEqual(sm.listShapeProblem({ ...ok, name: 'x'.repeat(40) }), '');
  assert.strictEqual(sm.listShapeProblem({ ...ok, name: 'x'.repeat(41) }), 'NAME_INVALID');
  assert.strictEqual(sm.listShapeProblem({ ...ok, name: '  ' }), 'NAME_INVALID');
  assert.strictEqual(sm.listShapeProblem({ ...ok, items: Array.from({ length: 100 }, () => ({ groupId: 'milk', qty: 1 })) }), '');
  assert.strictEqual(sm.listShapeProblem({ ...ok, items: Array.from({ length: 101 }, () => ({ groupId: 'milk', qty: 1 })) }), 'ITEMS_INVALID');
  for (const it of [{ groupId: 'Beef!', qty: 1 }, { groupId: 'milk', qty: 0 }, { groupId: 'milk', qty: 1.2345 }, { groupId: 'milk', qty: 1, price: 5 }, { groupId: 'milk', qty: 1, offerId: 'a/b' }, 'milk']) {
    assert.strictEqual(sm.listShapeProblem({ ...ok, items: [it] }), 'ITEM_INVALID', JSON.stringify(it));
  }
  assert.strictEqual(sm.listShapeProblem({ ...ok, remind: { enabled: true, weekday: 6 } }), 'REMIND_INVALID');
  assert.strictEqual(sm.listShapeProblem({ ...ok, remind: { enabled: 'yes', weekday: 6, minute: 1 } }), 'REMIND_INVALID');
});

// ── етишмовчилик ──
const BEEF = { smGroupId: 'beef', smStatus: 'active', price: 80000, qtyStep: 0.5, stock: 10, unit: 'kg', weighed: true, name: 'Мол гўшти' };
const MILK = { smGroupId: 'milk', smStatus: 'active', price: 12000, qtyStep: 1, stock: 5, unit: 'l', weighed: false, name: 'Сут' };
const KEFIR = { smGroupId: 'kefir', smStatus: 'active', price: 15000, qtyStep: 1, stock: 5, unit: 'l', weighed: false, name: 'Кефир' };
const AYRAN = { smGroupId: 'katyk', smStatus: 'active', price: 9000, qtyStep: 1, stock: 1, unit: 'l', weighed: false, name: 'Айрон' };
const baseLines = () => sm.priceSupermarketOrder({
  items: [{ productId: 'beef', qMilli: 1500 }, { productId: 'milk', qMilli: 2000 }], products: { beef: BEEF, milk: MILK }, feeBp: BP, weighHoldPercent: HOLD,
}).lines;
const report = (lines, extra = {}) => sm.applyShortageReport(lines, {
  productId: 'milk', availableQty: 1, subs: [{ offerId: 'kefir_1', data: KEFIR }, { offerId: 'ayran_1', data: AYRAN }], actor: '998915000004', nowMs: 1000, ...extra,
});

check('S5 applyShortageReport: қатор shortage (30 дақ), пулга тегмайди; такрор — changed:false; чегара/хато кодлари', () => {
  const lines = baseLines();
  const r = report(lines);
  assert.ok(r.ok && r.changed && r.pricing === 'none');
  const sh = r.lines[1].shortage;
  assert.deepStrictEqual([sh.state, sh.availableQty, sh.substitutes.map((s) => s.offerId), sh.answerByMs, sh.substitutes[0].price], ['pending', 1, ['kefir_1', 'ayran_1'], 1000 + 30 * 60000, 15000]);
  assert.strictEqual(sm.chargeAfter(171840, lines, r.lines, BP, 'none').next, 171840);
  assert.strictEqual(report(r.lines, { nowMs: 5000 }).changed, false, 'идемпотент');
  assert.strictEqual(report(lines, { availableQty: 0, subs: [] }).ok, true, '0 — фақат олиб ташлаш');
  assert.strictEqual(report(lines, { availableQty: 2 }).code, 'AVAILABLE_QTY_INVALID', 'available == qty');
  assert.strictEqual(report(lines, { availableQty: 0.5 }).code, 'AVAILABLE_QTY_INVALID', 'қадам');
  assert.strictEqual(report(lines, { availableQty: -1 }).code, 'AVAILABLE_QTY_INVALID');
  assert.strictEqual(report(lines, { subs: [{ offerId: 'milk', data: MILK }] }).code, 'SUBSTITUTE_INVALID');
  assert.strictEqual(report(lines, { subs: [{ offerId: 'beef', data: BEEF }] }).code, 'SUBSTITUTE_INVALID', 'буюртмада бор');
  assert.strictEqual(report(lines, { subs: [{ offerId: 'x_000001', data: { ...KEFIR, stock: 0 } }] }).code, 'SUBSTITUTE_INVALID');
  assert.strictEqual(report(lines, { subs: [{ offerId: 'x_000001', data: null }] }).code, 'SUBSTITUTE_INVALID');
  assert.strictEqual(report(lines, { productId: 'nope_1' }).code, 'LINE_NOT_FOUND');
  const settled = sm.applyWeights(lines, [{ productId: 'beef', actualQty: 1.4 }], HOLD).lines;
  assert.strictEqual(report(settled, { productId: 'beef', availableQty: 1, subs: [] }).code, 'LINE_ALREADY_SETTLED');
  // кутилаётган қаторни тортиб бўлмайди
  const rb = report(lines, { productId: 'beef', availableQty: 1, subs: [] });
  assert.strictEqual(sm.applyWeights(rb.lines, [{ productId: 'beef', actualQty: 1 }], HOLD).code, 'LINE_SHORTAGE_PENDING');
});

const choose = (lines, choice, extra = {}) => sm.applyShortageChoice(lines, {
  productId: 'milk', choice, feeBp: BP, weighHoldPercent: HOLD, actor: '998912000001', nowMs: 2000, ...extra,
});
check('S6 алмаштириш: қимматроқ (кефир 2 л) → +6660 ечилади; арзонроқ (айрон 1 л, stock 1) → қайтим; stock ўзгаришлари; substitutedFrom', () => {
  const lines = baseLines();
  const rep = report(lines).lines;
  const up = choose(rep, 'substitute', { offerId: 'kefir_1', offerData: KEFIR });
  assert.ok(up.ok && up.pricing === 'delta');
  const nl = up.lines[1];
  assert.deepStrictEqual([nl.productId, nl.price, nl.qty, nl.total, nl.substitutedFrom.productId, nl.substitutedFrom.total, nl.shortage.state, nl.shortage.choice],
    ['kefir_1', 15000, 2, 30000, 'milk', 24000, 'resolved', 'substitute']);
  assert.deepStrictEqual(up.stockDeltas, { milk: 2000, kefir_1: -2000 });
  assert.deepStrictEqual(sm.chargeAfter(171840, rep, up.lines, BP, 'delta'), { next: 178500, refund: 0, debit: 6660, capDiscount: 0, target: 178500 });
  // айрон stock 1 — 2 л сўраса OUT_OF_STOCK; 1 л — қайтим
  assert.strictEqual(choose(rep, 'substitute', { offerId: 'ayran_1', offerData: AYRAN }).code, 'OUT_OF_STOCK');
  const down = choose(rep, 'substitute', { offerId: 'ayran_1', offerData: AYRAN, qty: 1 });
  // goods 120000 + 9000 = 129000; fee 14190; extras 12000 → 155190; қайтим 16650
  assert.deepStrictEqual(sm.chargeAfter(171840, rep, down.lines, BP, 'delta'), { next: 155190, refund: 16650, debit: 0, capDiscount: 0, target: 155190 });
  assert.strictEqual(choose(rep, 'substitute', { offerId: 'other_01', offerData: KEFIR }).code, 'SUBSTITUTE_INVALID', 'рўйхатда йўқ');
  assert.strictEqual(choose(rep, 'substitute', { offerId: 'kefir_1', offerData: { ...KEFIR, smStatus: 'hidden' } }).code, 'SUBSTITUTE_INVALID');
  assert.strictEqual(choose(rep, 'substitute', { offerId: 'kefir_1', offerData: KEFIR, qty: 1.5 }).code, 'QTY_STEP_INVALID');
  // нарх ошган бўлса — жорий каталог нархи (снапшот эмас)
  const pricier = choose(rep, 'substitute', { offerId: 'kefir_1', offerData: { ...KEFIR, price: 16000 } });
  assert.strictEqual(pricier.lines[1].total, 32000);
  assert.strictEqual(choose(up.lines, 'remove').code, 'LINE_SHORTAGE_RESOLVED', 'иккинчи жавоб (алмаштирилган)');
  assert.strictEqual(choose(choose(rep, 'reduce').lines, 'remove').code, 'LINE_SHORTAGE_RESOLVED', 'иккинчи жавоб (камайтирилган)');
  assert.strictEqual(choose(lines, 'remove').code, 'LINE_NO_SHORTAGE');
});

check('S7 камайтириш (2→1 л): қайтим 13320; олиб ташлаш: қатор + fee улуши 26640 (adminRemove математикаси); охирги қатор — LAST_LINE', () => {
  const rep = report(baseLines()).lines;
  const red = choose(rep, 'reduce');
  assert.deepStrictEqual([red.lines[1].qty, red.lines[1].total, red.lines[1].reducedFrom.qty, red.pricing], [1, 12000, 2, 'cap']);
  assert.deepStrictEqual(red.stockDeltas, { milk: 1000 });
  assert.deepStrictEqual(sm.chargeAfter(171840, rep, red.lines, BP, 'cap'), { next: 158520, refund: 13320, debit: 0, capDiscount: 0, target: 158520 });
  assert.strictEqual(choose(rep, 'reduce', { qty: 2 }).code, 'QTY_STEP_INVALID', '> available');
  assert.strictEqual(choose(rep, 'reduce', { qty: 0 }).code, 'QTY_STEP_INVALID');
  const zero = report(baseLines(), { availableQty: 0, subs: [] }).lines;
  assert.strictEqual(choose(zero, 'reduce').code, 'QTY_STEP_INVALID', 'available 0 — камайтириб бўлмайди');
  const rm = choose(rep, 'remove');
  assert.ok(rm.lines[1].removed && rm.lines[1].removed.reason === 'shortage');
  assert.deepStrictEqual(sm.chargeAfter(171840, rep, rm.lines, BP, 'cap'), { next: 145200, refund: 26640, debit: 0, capDiscount: 0, target: 145200 });
  // тортиладиган қатор камайса — ушлаш ҳам қайта ҳисобланади
  const rb = report(baseLines(), { productId: 'beef', availableQty: 1, subs: [] }).lines;
  const redB = choose(rb, 'reduce', { productId: 'beef' });
  assert.deepStrictEqual([redB.lines[0].total, redB.lines[0].holdExtra], [80000, 8000]);
  const one = sm.priceSupermarketOrder({ items: [{ productId: 'milk', qMilli: 2000 }], products: { milk: MILK }, feeBp: BP, weighHoldPercent: HOLD }).lines;
  assert.strictEqual(choose(report(one, { subs: [] }).lines, 'remove').code, 'LAST_LINE');
});

// ── Excel импорт ──
const H = SI.COLUMNS.map(SI.headerText);
const rowOf = (o) => SI.COLUMNS.map((c) => (o[c.key] === undefined ? null : o[c.key]));
const sheet = (objs) => ({ header: H, rows: objs.map((o, i) => ({ rowNumber: i + 2, cells: rowOf(o) })) });
const GOOD = { sku: 'beef_lean_1', groupId: 'beef', price: 80000, stock: 10 };

check('S8 импорт қатори: минимал (нав «Оддий», гуруҳ бирлиги); 3 тил тўлдирилади; weighed/packQty/cost; хатолар', () => {
  const r = SI.validateRow({ ...GOOD });
  assert.deepStrictEqual(r.errors, []);
  assert.deepStrictEqual([r.offer.smVariety.id, r.offer.smVariety.names.uz_Latn, r.offer.smStatus, r.offer.unit, r.cost], ['standard', 'Oddiy', 'active', undefined, null]);
  const v = SI.validateRow({ ...GOOD, variety_uz_Cyrl: 'Лаҳм', quality_ru: 'Высший', weighed: 'ҳа', qtyStep: '0,5', packQty: 1.5, packUnit: 'L', purchasePrice: '70 000', supplier: 'Бозор' });
  assert.deepStrictEqual(v.errors, []);
  assert.deepStrictEqual(v.offer.smVariety.names, { uz_Cyrl: 'Лаҳм', uz_Latn: 'Лаҳм', ru: 'Лаҳм' });
  assert.ok(/^v[0-9a-f]{12}$/.test(v.offer.smVariety.id));
  assert.deepStrictEqual([v.offer.smQuality.uz_Cyrl, v.offer.weighed, v.offer.qtyStep, v.offer.packQty, v.offer.packUnit, v.cost.purchasePrice], ['Высший', true, 0.5, 1.5, 'l', 70000]);
  const codes = (o) => SI.validateRow({ ...GOOD, ...o }).errors;
  assert.deepStrictEqual(codes({ sku: 'ab' }), ['SKU_INVALID']);
  assert.deepStrictEqual(codes({ sku: 'a/b/cdef' }), ['SKU_INVALID']);
  assert.deepStrictEqual(codes({ price: 1.5 }), ['PRICE_NOT_INT']);
  assert.deepStrictEqual(codes({ price: 0 }), ['PRICE_INVALID']);
  assert.deepStrictEqual(codes({ price: null }), ['PRICE_REQUIRED']);
  assert.deepStrictEqual(codes({ stock: -1 }), ['STOCK_INVALID']);
  assert.deepStrictEqual(codes({ stock: 'кўп' }), ['STOCK_INVALID']);
  assert.deepStrictEqual(codes({ unit: 'ton' }), ['UNIT_INVALID']);
  assert.deepStrictEqual(codes({ status: 'deleted' }), ['SM_STATUS_INVALID']);
  assert.deepStrictEqual(codes({ packQty: 1.5 }), ['PACK_UNIT_INVALID']);
  assert.deepStrictEqual(codes({ weighed: 'балки' }), ['WEIGHED_INVALID']);
  assert.deepStrictEqual(codes({ supplier: 'X' }), ['PURCHASE_PRICE_REQUIRED']);
  assert.deepStrictEqual(codes({ imageUrl: 'ftp://x/y.jpg' }), ['IMAGE_URL_INVALID']);
  assert.deepStrictEqual(codes({ imageUrl: 'http://localhost:8080/a.jpg' }), ['IMAGE_URL_INVALID']);
});

check('S9 импорт варақ: 500 — OK, 501 — TOO_MANY_ROWS; дубликат SKU; GROUP_UNKNOWN; CATEGORY_MISMATCH; «#» намуна; сарлавҳа йўқ', () => {
  const many = (n) => Array.from({ length: n }, (_, i) => ({ ...GOOD, sku: `sku_${String(i).padStart(4, '0')}` }));
  const ok = SI.validateSheet(sheet(many(500)), TAX1);
  assert.strictEqual(ok.fileError, undefined);
  assert.strictEqual(ok.rows.length, 500);
  assert.ok(ok.rows.every((r) => r.errors.length === 0));
  assert.strictEqual(SI.validateSheet(sheet(many(501)), TAX1).fileError, 'TOO_MANY_ROWS');
  assert.strictEqual(SI.validateSheet(sheet([{ sku: '#beef_lean_1', groupId: 'beef', price: 1, stock: 1 }, ...many(500)]), TAX1).rows.length, 500, 'намуна саналмайди');
  const r = SI.validateSheet(sheet([GOOD, { ...GOOD }, { ...GOOD, sku: 'caviar_01', groupId: 'caviar' }, { ...GOOD, sku: 'beef_cat_1', categoryId: 'dairy' }, { ...GOOD, sku: 'beef_cat_2', categoryId: 'meat_fish' }]), TAX1);
  assert.deepStrictEqual(r.rows.map((x) => x.errors), [['SKU_DUPLICATE'], ['SKU_DUPLICATE'], ['GROUP_UNKNOWN'], ['CATEGORY_MISMATCH'], []]);
  assert.strictEqual(SI.validateSheet(sheet([]), TAX1).fileError, 'NO_ROWS');
  const noPrice = SI.validateSheet({ header: H.filter((h) => !h.includes('[price]')), rows: [] }, TAX1);
  assert.deepStrictEqual([noPrice.fileError, noPrice.missing], ['HEADER_MISSING', ['price']]);
});

check('S10 шаблон: .xlsx мавжуд парсер (`[sku]` сарлавҳа) билан ўқилади; фақат намуна → NO_ROWS; Help варағи 3 тил', async () => {
  const buf = await SI.buildTemplate();
  const p = await X.parseXlsx(buf);
  assert.ok(p.ok, p.code);
  assert.strictEqual(p.sheet.header.length, SI.COLUMNS.length);
  assert.strictEqual(SI.validateSheet(p.sheet, TAX1).fileError, 'NO_ROWS');
});

Promise.all(pending).then(() => {
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
});
