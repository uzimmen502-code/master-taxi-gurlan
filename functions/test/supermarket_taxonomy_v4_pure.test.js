/* eslint-disable no-console */
// «AVA Супермаркет» таксономияси — supermarket_taxonomy_v4.json (эга 2026-11-28 «қўш»: гуруҳи йўқ намуналар учун янги
// гуруҳлар; гуруҳ танлови PROPOSED). prod taxonomy/supermarket v1 = v3 файли мазмуни → бу файл ҳужжат v2 бўлади.
// Тоза тест (эмулятор шарт эмас):  node test/supermarket_taxonomy_v4_pure.test.js
// Эга prod'да: node functions/tools/seed_supermarket.js --upgrade --taxonomy-file functions/tools/data/supermarket_taxonomy_v4.json \
//   --expected-version 1 --project <id> [--apply]
const assert = require('assert');
const sm = require('../supermarket');
const { diffTaxonomy } = require('../tools/seed_supermarket');
const TAX3 = require('../tools/data/supermarket_taxonomy_v3.json');
const TAX4 = require('../tools/data/supermarket_taxonomy_v4.json');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.message}`); }
};
const clone = (o) => JSON.parse(JSON.stringify(o));
const LATN_OLD = /o'|g'|o‘|g‘|sh|ch/i;
const NEW = {
  pearl_barley: { cat: 'grain_flour', unit: 'kg/0.5/false', names: { uz_Cyrl: 'Перловка', uz_Latn: 'Perlovka', ru: 'Перловка' } },
  funchoza: { cat: 'grain_flour', unit: 'pack/1/false', names: { uz_Cyrl: 'Фунчоза ва лапша', uz_Latn: 'Funçoza va lapşa', ru: 'Фунчоза и лапша' } },
  baking_soda: { cat: 'oil_spices', unit: 'pack/1/false', names: { uz_Cyrl: 'Сода ва қабартгич', uz_Latn: 'Soda va qabartgiç', ru: 'Сода и разрыхлитель' } },
  small_household: { cat: 'household', unit: 'piece/1/false', names: { uz_Cyrl: 'Майда рўзғор буюмлари', uz_Latn: 'Mayda rözğor buyumlari', ru: 'Мелкие хозтовары' } },
  // Эга 2026-11-28 «ҳа» (номи эганики; бўлим/бирлик PROPOSED): Қуриқ қаймоқ, тузланган бодиринг/қалампир.
  preserves_pickles: { cat: 'oil_spices', unit: 'piece/1/false', names: { uz_Cyrl: 'Консерва ва тузламалар', uz_Latn: 'Konserva va tuzlamalar', ru: 'Консервы и соления' } },
};

check('T1 v4 валидатордан ўтади; 10 бўлим / 101 гуруҳ; ҳажм чегарада', () => {
  const r = sm.validateSupermarketTaxonomy(sm.trimDeep(clone(TAX4)));
  assert.ok(r.ok, r.errors.join(','));
  assert.strictEqual(TAX4.categories.length, 10);
  assert.strictEqual(TAX4.categories.reduce((n, c) => n + c.groups.length, 0), 101);
  assert.ok(Buffer.byteLength(JSON.stringify(TAX4), 'utf8') < 200 * 1024);
});

check('T2 v3 (prod v1) ЎЗГАРМАГАН — фақат 5 гуруҳ мавжуд бўлимлар охирига қўшилди', () => {
  assert.deepStrictEqual(TAX4.categories.map((c) => c.id), TAX3.categories.map((c) => c.id));
  TAX3.categories.forEach((c3, i) => {
    const c4 = TAX4.categories[i];
    const { groups: g3, ...h3 } = c3;
    const { groups: g4, ...h4 } = c4;
    assert.deepStrictEqual(h4, h3, `${c3.id} сарлавҳа`);
    assert.deepStrictEqual(g4.slice(0, g3.length), g3, `${c3.id} эски гуруҳлар`);
  });
  const d = diffTaxonomy(TAX3.categories, TAX4.categories);
  assert.deepStrictEqual(d.addedGroups.sort(), ['grain_flour/funchoza', 'grain_flour/pearl_barley', 'household/small_household', 'oil_spices/baking_soda', 'oil_spices/preserves_pickles']);
  for (const k of ['addedCategories', 'removedCategories', 'changedCategories', 'removedGroups', 'changedGroups']) assert.deepStrictEqual(d[k], [], k);
});

check('T3 янги гуруҳлар: бўлим, бирлик/қадам/тортилади, 3 тилда ном (uz_Latn янги алифбода), синонимлар', () => {
  for (const [id, want] of Object.entries(NEW)) {
    const f = sm.findGroup(TAX4, id);
    assert.ok(f && f.group, id);
    assert.strictEqual(f.category.id, want.cat, id);
    assert.strictEqual(`${f.group.unit}/${f.group.step}/${f.group.weighed}`, want.unit, id);
    assert.deepStrictEqual(f.group.names, want.names, id);
    assert.ok(!LATN_OLD.test(f.group.names.uz_Latn), `${id} uz_Latn эски алифбода`);
    assert.ok(f.group.synonyms.length >= 4 && f.group.synonyms.length <= 20, `${id} синонимлар`);
    assert.ok(f.group.order > Math.max(...TAX3.categories.find((c) => c.id === want.cat).groups.map((g) => g.order)), `${id} охирида`);
  }
});

check('T4 гуруҳ id ягона (drinks/soda ≠ baking_soda); янги синонимлар эски гуруҳлар синоним/номи билан тўқнашмайди', () => {
  const ids = TAX4.categories.flatMap((c) => c.groups.map((g) => g.id));
  assert.strictEqual(new Set(ids).size, ids.length);
  const oldWords = new Set();
  for (const c of TAX3.categories) for (const g of c.groups) for (const w of [...Object.values(g.names), ...(g.synonyms || [])]) oldWords.add(w.toLowerCase());
  for (const id of Object.keys(NEW)) for (const s of sm.findGroup(TAX4, id).group.synonyms) assert.ok(!oldWords.has(s.toLowerCase()), `${id}: «${s}» эски гуруҳда бор`);
});

check('T5 rollback аниқланади: v4 → v3 фарқи — 5 гуруҳ removed (seed --upgrade --allow-remove талаб қилади)', () => {
  const d = diffTaxonomy(TAX4.categories, TAX3.categories);
  assert.strictEqual(d.removedGroups.length, 5);
  assert.deepStrictEqual(d.addedGroups, []);
});

check('T6 нотўғри шакл рад: такрор id, номаълум бирлик, uz_Latn йўқ', () => {
  const dup = clone(TAX4);
  dup.categories[1].groups.push({ ...dup.categories[1].groups[0] });
  assert.ok(sm.validateSupermarketTaxonomy(dup).errors.some((e) => e.startsWith('GROUP_ID_DUPLICATE')));
  const bad = clone(TAX4);
  bad.categories[1].groups.find((g) => g.id === 'pearl_barley').unit = 'gram';
  assert.ok(sm.validateSupermarketTaxonomy(bad).errors.some((e) => e.startsWith('UNIT_INVALID')));
  const noLatn = clone(TAX4);
  delete noLatn.categories[8].groups.find((g) => g.id === 'small_household').names.uz_Latn;
  assert.ok(sm.validateSupermarketTaxonomy(noLatn).errors.some((e) => e.startsWith('NAME_MISSING')));
});

check('T7 version ҳужжатлари: v1 → v2 (seed --upgrade шакли), тарих — тўлиқ нусха', () => {
  const v = sm.buildTaxonomyVersionDocs({ categories: TAX4.categories, version: 2, previousVersion: 1, actor: 'seed', ts: null });
  assert.strictEqual(v.doc.version, 2);
  assert.strictEqual(v.doc.categories.reduce((n, c) => n + c.groups.length, 0), 101);
  assert.strictEqual(sm.stableStringify(v.history.categories), sm.stableStringify(TAX4.categories));
});

const passed = results.filter(Boolean).length;
console.log(`\n${passed}/${results.length} passed`);
process.exit(passed === results.length ? 0 : 1);
