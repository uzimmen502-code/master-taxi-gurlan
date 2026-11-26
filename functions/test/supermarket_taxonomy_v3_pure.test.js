/* eslint-disable no-console */
// «AVA Супермаркет» таксономияси v3 (эга 2026-11-28): v2 + 10-категория «Байрам ва ширинликлар».
// Тоза тест (эмулятор шарт эмас). Ишга тушириш: node test/supermarket_taxonomy_v3_pure.test.js
// Ega prod'да: node functions/tools/seed_supermarket.js --upgrade --taxonomy-file functions/tools/data/supermarket_taxonomy_v3.json \
//   --expected-version <жорий> --project <id> [--apply]
const assert = require('assert');
const sm = require('../supermarket');
const TAX2 = require('../tools/data/supermarket_taxonomy_v2.json');
const TAX3 = require('../tools/data/supermarket_taxonomy_v3.json');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.message}`); }
};
const clone = (o) => JSON.parse(JSON.stringify(o));
const NEW = TAX3.categories.find((c) => c.id === 'holiday_sweets');
const LATN_OLD = /o'|g'|o‘|g‘|sh|ch/i;

check('T1 v3 валидатордан ўтади; 10 категория; ҳажм чегарада', () => {
  const r = sm.validateSupermarketTaxonomy(TAX3);
  assert.ok(r.ok, r.errors.join(','));
  assert.strictEqual(TAX3.categories.length, 10);
  assert.ok(Buffer.byteLength(JSON.stringify(TAX3), 'utf8') < 200 * 1024);
});

check('T2 v2 нинг 9 категорияси ЎЗГАРМАГАН (тартиб, гуруҳлар, pairs) — фақат қўшилди', () => {
  assert.deepStrictEqual(TAX3.categories.slice(0, 9), TAX2.categories);
  assert.strictEqual(sm.stableStringify(TAX3.categories) === sm.stableStringify(TAX2.categories), false, 'upgrade ёзилиши керак');
});

check('T3 янги категория: id, охирги тартиб, иконка, 3 тилда ном (uz_Latn янги алифбода)', () => {
  assert.ok(NEW);
  assert.strictEqual(NEW.icon, 'holiday');
  assert.ok(NEW.order > Math.max(...TAX2.categories.map((c) => c.order)));
  assert.deepStrictEqual(NEW.names, { uz_Cyrl: 'Байрам ва ширинликлар', uz_Latn: 'Bayram va şirinliklar', ru: 'Праздник и сладости' });
});

check('T4 6 гуруҳ: торт, конфет, печенье, шоколад, бир марталик идиш, шар/безак; бирлик/қадам/тортилади', () => {
  const m = Object.fromEntries(NEW.groups.map((g) => [g.id, `${g.unit}/${g.step}/${g.weighed}`]));
  assert.deepStrictEqual(m, {
    cake: 'piece/1/false',
    candies: 'kg/0.5/true',
    cookies: 'pack/1/false',
    chocolate: 'piece/1/false',
    disposable_tableware: 'pack/1/false',
    balloons_decor: 'pack/1/false',
  });
  for (const g of NEW.groups) {
    for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) assert.ok(g.names[l] && g.names[l].trim(), `${g.id} ${l}`);
    assert.ok(!LATN_OLD.test(g.names.uz_Latn), `${g.id} uz_Latn эски алифбода`);
    assert.ok(g.synonyms.length >= 2, `${g.id} синонимлар`);
  }
  // Салфетка Уй-рўзғорда қолади (эга) — кўчирилмади.
  const hh = TAX3.categories.find((c) => c.id === 'household');
  assert.ok(hh.groups.some((g) => g.id === 'napkins'));
  assert.ok(!NEW.groups.some((g) => g.id === 'napkins'));
});

check('T5 жуфтлар: торт → шарлар/идишлар/шарбат/салфетка; ҳаммаси мавжуд гуруҳ', () => {
  const cake = sm.findGroup(TAX3, 'cake').group;
  for (const p of ['balloons_decor', 'disposable_tableware', 'fruit_juice', 'napkins']) assert.ok(cake.pairs.includes(p), p);
  for (const g of NEW.groups) for (const p of g.pairs || []) assert.ok(sm.findGroup(TAX3, p) && sm.findGroup(TAX3, p).group, `${g.id} → ${p}`);
});

check('T6 гуруҳ id бутун таксономияда ягона; такрор/номаълум жуфт/нотўғри бирлик — рад (validator ишлайди)', () => {
  const ids = TAX3.categories.flatMap((c) => c.groups.map((g) => g.id));
  assert.strictEqual(new Set(ids).size, ids.length);
  const dup = clone(TAX3);
  dup.categories[9].groups.push({ ...dup.categories[9].groups[0] });
  assert.ok(sm.validateSupermarketTaxonomy(dup).errors.some((e) => e.startsWith('GROUP_ID_DUPLICATE')));
  const badPair = clone(TAX3);
  badPair.categories[9].groups[0].pairs = ['no_such_group'];
  assert.ok(sm.validateSupermarketTaxonomy(badPair).errors.some((e) => e.startsWith('PAIR_UNKNOWN')));
  const badUnit = clone(TAX3);
  badUnit.categories[9].groups[1].unit = 'gram';
  assert.ok(sm.validateSupermarketTaxonomy(badUnit).errors.some((e) => e.startsWith('UNIT_INVALID')));
  const noLatn = clone(TAX3);
  delete noLatn.categories[9].names.uz_Latn;
  assert.ok(sm.validateSupermarketTaxonomy(noLatn).errors.some((e) => e.startsWith('NAME_MISSING')));
});

check('T7 version ҳужжатлари: v(N+1) — категориялар нусхаси (seed --upgrade шакли)', () => {
  const v = sm.buildTaxonomyVersionDocs({ categories: TAX3.categories, version: 3, previousVersion: 2, actor: 'seed', ts: null });
  assert.strictEqual(v.doc.version, 3);
  assert.strictEqual(v.doc.categories.length, 10);
});

const passed = results.filter(Boolean).length;
console.log(`\n${passed}/${results.length} passed`);
process.exit(passed === results.length ? 0 : 1);
