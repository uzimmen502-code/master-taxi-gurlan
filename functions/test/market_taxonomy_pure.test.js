/**
 * «Бозорлар» taxonomy/markets — ТОЗА валидатор (эмулятор керак эмас).
 *   node functions/test/market_taxonomy_pure.test.js
 *
 * Positive: v1 JSON ўтади. Negative: ru номи йўқ, такрор бўлим id, options'сиз select, int'да options, min>max,
 * майдон бўлими номаълум, 'ton' бирлиги, такрор moduleId, нотўғри marketId. Boundary: ном 60/61, min==max.
 * PRICE_UNITS — firestore.rules `priceUnit` рўйхати билан бир хил.
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const t = require('../market_taxonomy');

const V1 = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'tools', 'data', 'market_taxonomy_v1.json'), 'utf8'));
const clone = () => JSON.parse(JSON.stringify(V1));

let pass = 0;
let failCount = 0;
function check(name, fn) {
  try { fn(); pass += 1; console.log(`PASS - ${name}`); } catch (e) {
    failCount += 1; console.log(`FAIL - ${name} :: ${e.message}`);
  }
}
function expectError(obj, expected) {
  const r = t.validateMarketTaxonomy(obj);
  assert.strictEqual(r.ok, false, 'ok:false kutilgan');
  assert.ok(r.errors.includes(expected), `kutilgan «${expected}», bor: ${JSON.stringify(r.errors)}`);
}
function expectOk(obj) {
  const r = t.validateMarketTaxonomy(obj);
  assert.deepStrictEqual(r, { ok: true, errors: [] });
}

// ── Positive ──
check('P1 v1 JSON ўтади (4 бозор, moduleId лар)', () => {
  expectOk(V1);
  assert.deepStrictEqual(Object.keys(V1.markets), ['livestock', 'auto', 'meat', 'farm']);
  assert.deepStrictEqual(Object.values(V1.markets).map((m) => m.moduleId),
    ['livestock_market', 'auto_market', 'meat_market', 'farm_market']);
});
check('P2 v1: гўштда «Барчаси»/«Импорт» бўлим ЭМАС; деҳқонда тонна йўқ', () => {
  const ids = V1.markets.meat.categories.map((c) => c.id);
  assert.deepStrictEqual(ids, ['beef', 'mutton', 'poultry', 'fish', 'other']);
  assert.deepStrictEqual(V1.markets.farm.priceUnits, ['kg', 'ton', 'piece']);
  assert.deepStrictEqual(V1.markets.meat.priceUnits, ['kg']);
});
check('P3 PRICE_UNITS = firestore.rules priceUnit рўйхати', () => {
  const rules = fs.readFileSync(path.join(__dirname, '..', '..', 'firestore.rules'), 'utf8');
  const m = rules.match(/d\.get\('priceUnit', ''\) in \[([^\]]*)\]/);
  assert.ok(m, 'rules ichida priceUnit ro\'yxati topilmadi');
  const list = m[1].split(',').map((s) => s.trim().replace(/^'|'$/g, ''));
  assert.deepStrictEqual(list, [...t.PRICE_UNITS]);
});
const V2 = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'tools', 'data', 'market_taxonomy_v2.json'), 'utf8'));
check('P6 v2 JSON ўтади; 4 эски бозор v1 билан АЙНАН бир хил; +electronics/appliances (эга 2026-11-16)', () => {
  expectOk(t.normalizeTaxonomy(V2));
  assert.deepStrictEqual(Object.keys(V2.markets), ['livestock', 'auto', 'meat', 'farm', 'electronics', 'appliances']);
  for (const id of Object.keys(V1.markets)) assert.deepStrictEqual(V2.markets[id], V1.markets[id], id);
  const e = V2.markets.electronics;
  const a = V2.markets.appliances;
  assert.deepStrictEqual([e.moduleId, e.order, a.moduleId, a.order], ['electronics_market', 50, 'appliances_market', 60]);
  assert.deepStrictEqual(e.categories.map((c) => c.id), ['phones', 'computers', 'tv', 'gadgets', 'accessories']);
  assert.deepStrictEqual(a.categories.map((c) => c.id), ['large', 'small', 'climate']);
  assert.ok([...e.categories, ...a.categories].every((c) => c.orderable === true));
  assert.deepStrictEqual(e.fields.map((f) => f.key), ['brand', 'model', 'condition', 'warranty_months', 'storage_gb']);
  assert.deepStrictEqual(a.fields.map((f) => f.key), ['brand', 'model', 'condition', 'warranty_months']);
  assert.deepStrictEqual(e.fields[4].categories, ['phones', 'computers', 'gadgets']);
  assert.deepStrictEqual([e.priceUnits, a.priceUnits], [['', 'piece'], ['', 'piece']]);
});
check('P7 v2 бозор id лари = firestore.rules tvShopItemShapeOk market рўйхати', () => {
  const rules = fs.readFileSync(path.join(__dirname, '..', '..', 'firestore.rules'), 'utf8');
  const m = rules.match(/d\.get\('market', 'livestock'\) in \[([^\]]*)\]/);
  assert.ok(m, 'rules ichida market ro\'yxati topilmadi');
  const list = m[1].split(',').map((s) => s.trim().replace(/^'|'$/g, ''));
  assert.deepStrictEqual(list, Object.keys(V2.markets));
});
check('P8 upgrade diffMarkets: added/changed/removed/unchanged', () => {
  const { diffMarkets } = require('../tools/upgrade_market_taxonomy');
  const d = diffMarkets(V1.markets, V2.markets);
  assert.deepStrictEqual(d, { added: ['electronics', 'appliances'], changed: [], removed: [], unchanged: ['livestock', 'auto', 'meat', 'farm'] });
  const m2 = JSON.parse(JSON.stringify(V1.markets)); m2.meat.order = 31; delete m2.farm;
  assert.deepStrictEqual(diffMarkets(V1.markets, m2), { added: [], changed: ['meat'], removed: ['farm'], unchanged: ['livestock', 'auto'] });
});
check('P9 upgrade decide: WRITE v2 / CONFLICT / NOOP (қайта) / REMOVE_REFUSED / MISSING; fromValue(toValue) айнан', () => {
  const { decide, fromValue } = require('../tools/upgrade_market_taxonomy');
  const { toValue } = require('../tools/seed_market_taxonomy');
  const v1doc = { exists: true, version: 1, markets: V1.markets };
  assert.deepStrictEqual([decide(v1doc, 1, V2.markets).action, decide(v1doc, 1, V2.markets).version], ['WRITE', 2]);
  assert.strictEqual(decide(v1doc, 2, V2.markets).action, 'TAXONOMY_VERSION_CONFLICT');
  assert.strictEqual(decide({ exists: true, version: 2, markets: V2.markets }, 1, V2.markets).action, 'NOOP');
  assert.strictEqual(decide({ exists: true, version: 3, markets: V2.markets }, 1, V2.markets).action, 'TAXONOMY_VERSION_CONFLICT');
  assert.strictEqual(decide({ exists: true, version: 2, markets: V2.markets }, 2, V1.markets).action, 'REMOVE_REFUSED');
  assert.strictEqual(decide({ exists: false }, 1, V2.markets).action, 'MISSING');
  assert.deepStrictEqual(fromValue(toValue(V2.markets)), V2.markets);
});
check('P4 normalizeTaxonomy сатрларни trim қилади, бошқа қийматга тегмайди', () => {
  const n = t.normalizeTaxonomy({ a: '  x ', b: [' y', 3, true, null], c: { d: ' z' } });
  assert.deepStrictEqual(n, { a: 'x', b: ['y', 3, true, null], c: { d: 'z' } });
});
check('P5 stableStringify калит тартибига боғлиқ эмас', () => {
  assert.strictEqual(t.stableStringify({ a: 1, b: { c: 2, d: [1, { e: 1, f: 2 }] } }),
    t.stableStringify({ b: { d: [1, { f: 2, e: 1 }], c: 2 }, a: 1 }));
});

// ── Negative ──
check('N1 ru номи йўқ → NAME_MISSING markets.meat.names.ru', () => {
  const o = clone(); delete o.markets.meat.names.ru;
  expectError(o, 'NAME_MISSING markets.meat.names.ru');
});
check('N1b бўш (фақат бўшлиқ) ном → NAME_MISSING', () => {
  const o = clone(); o.markets.meat.names.uz_Latn = '   ';
  expectError(o, 'NAME_MISSING markets.meat.names.uz_Latn');
});
check('N2 такрор бўлим id → CATEGORY_ID_DUPLICATE', () => {
  const o = clone(); o.markets.auto.categories[1].id = 'cars';
  expectError(o, 'CATEGORY_ID_DUPLICATE markets.auto.categories[1].id');
});
check('N3 options\'сиз select → OPTIONS_MISSING', () => {
  const o = clone(); delete o.markets.livestock.fields[2].options;
  expectError(o, 'OPTIONS_MISSING markets.livestock.fields[2].options');
  const o2 = clone(); o2.markets.livestock.fields[2].options = [];
  expectError(o2, 'OPTIONS_MISSING markets.livestock.fields[2].options');
});
check('N4 int майдонда options → OPTIONS_NOT_ALLOWED', () => {
  const o = clone(); o.markets.livestock.fields[1].options = [{ id: 'aa', names: { uz_Cyrl: 'a', uz_Latn: 'a', ru: 'a' } }];
  expectError(o, 'OPTIONS_NOT_ALLOWED markets.livestock.fields[1].options');
});
check('N5 min > max → MIN_GT_MAX', () => {
  const o = clone(); o.markets.livestock.fields[1].min = 601;
  expectError(o, 'MIN_GT_MAX markets.livestock.fields[1]');
});
check('N5b min/max text майдонда → MIN_MAX_NOT_ALLOWED; maxLen int майдонда → MAXLEN_NOT_ALLOWED', () => {
  const o = clone(); o.markets.livestock.fields[0].min = 1;
  expectError(o, 'MIN_MAX_NOT_ALLOWED markets.livestock.fields[0]');
  const o2 = clone(); o2.markets.livestock.fields[1].maxLen = 10;
  expectError(o2, 'MAXLEN_NOT_ALLOWED markets.livestock.fields[1].maxLen');
});
check('N5c maxLen 0 / 501 / каср → MAXLEN_INVALID; 1 ва 500 → ўтади', () => {
  for (const bad of [0, 501, 2.5]) {
    const o = clone(); o.markets.livestock.fields[0].maxLen = bad;
    expectError(o, 'MAXLEN_INVALID markets.livestock.fields[0].maxLen');
  }
  for (const good of [1, 500]) {
    const o = clone(); o.markets.livestock.fields[0].maxLen = good;
    expectOk(o);
  }
});
check('N6 майдон бўлими номаълум id → FIELD_CATEGORY_UNKNOWN', () => {
  const o = clone(); o.markets.auto.fields[0].categories = ['cars', 'boats'];
  expectError(o, 'FIELD_CATEGORY_UNKNOWN markets.auto.fields[0].categories[1]');
});
check('N6b бошқа бозорнинг бўлими ҳам номаълум (meat.beef → auto)', () => {
  const o = clone(); o.markets.auto.fields[0].categories = ['beef'];
  expectError(o, 'FIELD_CATEGORY_UNKNOWN markets.auto.fields[0].categories[0]');
});
check('N7 нотўғри нарх бирлиги \'tonne\' → PRICE_UNIT_INVALID; бўш рўйхат → PRICE_UNITS_EMPTY', () => {
  const o = clone(); o.markets.farm.priceUnits = ['kg', 'tonne'];
  expectError(o, 'PRICE_UNIT_INVALID markets.farm.priceUnits[1]');
  const o2 = clone(); o2.markets.farm.priceUnits = [];
  expectError(o2, 'PRICE_UNITS_EMPTY markets.farm.priceUnits');
  const o3 = clone(); o3.markets.farm.priceUnits = ['kg', 'kg'];
  expectError(o3, 'PRICE_UNIT_DUPLICATE markets.farm.priceUnits[1]');
});
check('N8 такрор moduleId → MODULE_ID_DUPLICATE', () => {
  const o = clone(); o.markets.farm.moduleId = 'meat_market';
  expectError(o, 'MODULE_ID_DUPLICATE markets.farm.moduleId');
});
check('N9 нотўғри marketId (катта ҳарф / рақам / 1 ҳарф) → MARKET_ID_INVALID', () => {
  for (const bad of ['Meat', 'meat2', 'm', '_meat']) {
    const o = clone(); o.markets[bad] = { ...o.markets.meat, moduleId: `x_${bad.toLowerCase().replace(/[^a-z_]/g, '')}_market` };
    expectError(o, `MARKET_ID_INVALID markets.${bad}`);
  }
});
check('N10 бўлимлар бўш → CATEGORIES_EMPTY; orderable bool эмас → ORDERABLE_INVALID', () => {
  const o = clone(); o.markets.meat.categories = [];
  expectError(o, 'CATEGORIES_EMPTY markets.meat.categories');
  const o2 = clone(); o2.markets.meat.categories[0].orderable = 'yes';
  expectError(o2, 'ORDERABLE_INVALID markets.meat.categories[0].orderable');
});
check('N11 майдон тури номаълум, required йўқ, такрор key', () => {
  const o = clone(); o.markets.meat.fields[0].type = 'float';
  expectError(o, 'FIELD_TYPE_INVALID markets.meat.fields[0].type');
  const o2 = clone(); delete o2.markets.meat.fields[0].required;
  expectError(o2, 'REQUIRED_INVALID markets.meat.fields[0].required');
  const o3 = clone(); o3.markets.auto.fields[1].key = 'brand';
  expectError(o3, 'FIELD_KEY_DUPLICATE markets.auto.fields[1].key');
});
check('N12 номаълум калит → UNKNOWN_KEY; markets йўқ → MARKETS_MISSING; объект эмас', () => {
  const o = clone(); o.markets.meat.colour = 'red';
  expectError(o, 'UNKNOWN_KEY markets.meat.colour');
  expectError({}, 'MARKETS_MISSING markets');
  expectError({ markets: {} }, 'MARKETS_EMPTY markets');
  expectError(null, 'TAXONOMY_NOT_OBJECT');
  expectError([], 'TAXONOMY_NOT_OBJECT');
});
check('N13 imageUrl > 500 / сатр эмас → IMAGE_URL_INVALID; order каср → ORDER_INVALID', () => {
  const o = clone(); o.markets.meat.imageUrl = 'x'.repeat(501);
  expectError(o, 'IMAGE_URL_INVALID markets.meat.imageUrl');
  const o2 = clone(); delete o2.markets.meat.imageUrl;
  expectError(o2, 'IMAGE_URL_INVALID markets.meat.imageUrl');
  const o3 = clone(); o3.markets.meat.order = 1.5;
  expectError(o3, 'ORDER_INVALID markets.meat.order');
});
check('N14 200 KB дан катта → TAXONOMY_TOO_LARGE', () => {
  const o = clone();
  for (let i = 0; i < 2000; i += 1) {
    o.markets.auto.fields[4].options.push({ id: `o_${'a'.repeat(3)}${String.fromCharCode(97 + (i % 26))}`, names: { uz_Cyrl: 'Ж'.repeat(40), uz_Latn: 'x'.repeat(40), ru: 'Ж'.repeat(40) } });
  }
  const r = t.validateMarketTaxonomy(o);
  assert.strictEqual(r.ok, false);
  assert.ok(r.errors[0].startsWith('TAXONOMY_TOO_LARGE'), JSON.stringify(r.errors.slice(0, 2)));
});
check('N15 slogan ru йўқ → SLOGAN_MISSING; sloganNoOrder ихтиёрий', () => {
  const o = clone(); delete o.markets.auto.slogan.ru;
  expectError(o, 'SLOGAN_MISSING markets.auto.slogan.ru');
  const o2 = clone(); delete o2.markets.meat.sloganNoOrder;
  expectOk(o2);
});

// ── Boundary ──
check('B1 бозор номи 60 белги — ўтади; 61 — NAME_TOO_LONG', () => {
  const o = clone(); o.markets.meat.names.ru = 'я'.repeat(60);
  expectOk(o);
  const o2 = clone(); o2.markets.meat.names.ru = 'я'.repeat(61);
  expectError(o2, 'NAME_TOO_LONG markets.meat.names.ru');
});
check('B2 бўлим номи 40 — ўтади; 41 — NAME_TOO_LONG', () => {
  const o = clone(); o.markets.meat.categories[0].names.uz_Cyrl = 'М'.repeat(40);
  expectOk(o);
  const o2 = clone(); o2.markets.meat.categories[0].names.uz_Cyrl = 'М'.repeat(41);
  expectError(o2, 'NAME_TOO_LONG markets.meat.categories[0].names.uz_Cyrl');
});
check('B3 count: min==max ўтади; min=max+1 MIN_GT_MAX; фақат min ёки фақат max ўтади', () => {
  const o = clone(); o.markets.livestock.fields[3].min = 5; o.markets.livestock.fields[3].max = 5;
  expectOk(o);
  const o2 = clone(); o2.markets.livestock.fields[3].min = 6; o2.markets.livestock.fields[3].max = 5;
  expectError(o2, 'MIN_GT_MAX markets.livestock.fields[3]');
  const o3 = clone(); delete o3.markets.livestock.fields[3].max;
  expectOk(o3);
  const o4 = clone(); delete o4.markets.livestock.fields[3].min;
  expectOk(o4);
  const o5 = clone(); o5.markets.livestock.fields[3].min = 1.5;
  expectError(o5, 'MIN_INVALID markets.livestock.fields[3].min');
});
check('B4 шиор 300 — ўтади; 301 — SLOGAN_TOO_LONG', () => {
  const o = clone(); o.markets.farm.slogan.ru = 'с'.repeat(300);
  expectOk(o);
  const o2 = clone(); o2.markets.farm.slogan.ru = 'с'.repeat(301);
  expectError(o2, 'SLOGAN_TOO_LONG markets.farm.slogan.ru');
});
check('B5 хатолар сони 50 билан чекланади', () => {
  const o = clone();
  for (const m of Object.values(o.markets)) { m.names = {}; m.slogan = {}; m.categories.forEach((c) => { c.names = {}; }); }
  const r = t.validateMarketTaxonomy(o);
  assert.strictEqual(r.ok, false);
  assert.ok(r.errors.length <= t.LIMITS.maxErrors, `${r.errors.length}`);
});
check('B6 buildVersionDocs: ҳужжат/тарих/аудит шакли', () => {
  const d = t.buildVersionDocs({ markets: { a: 1 }, version: 3, previousVersion: 2, actor: '998901112233', ts: 'TS' });
  assert.deepStrictEqual(d.doc, { markets: { a: 1 }, version: 3, updatedAt: 'TS', updatedBy: '998901112233' });
  assert.deepStrictEqual(d.history, { ...d.doc, previousVersion: 2 });
  assert.deepStrictEqual(d.audit, { kind: 'market_taxonomy_set', actor: '998901112233', target: 'v3', version: 3, at: 'TS' });
});

console.log(`\n${pass} passed, ${failCount} failed`);
process.exit(failCount ? 1 : 0);
