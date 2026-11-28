/**
 * «AVA Супермаркет» намуналари — гуруҳ бириктириш тоза функциялари (эмуляторсиз):
 *   node test/assign_supermarket_sample_groups_pure.test.js
 * Қулфланади: ном → гуруҳ (ибора > ягона сўз > умумий сўз), ўзбекча қўшимча, EXCLUDE, AMBIGUOUS/NO_MATCH тегилмайди,
 * --map устун/номаълум гуруҳ рад, smGroupId/smPartnerKey бор — SKIP (идемпотент), rollback шартлари.
 */
'use strict';
const assert = require('assert');
const T = require('../tools/assign_supermarket_sample_groups');
// prod taxonomy/supermarket v1 = v3 файли мазмуни (2026-11-28 текширилди); v4 — +4 гуруҳ (эга «қўш», ҳужжат v2 бўлади).
const TAX = require('../tools/data/supermarket_taxonomy_v3.json');
const TAX4 = require('../tools/data/supermarket_taxonomy_v4.json');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.message}`); }
};
const IDX = T.buildIndex(TAX);
const g = (name) => T.matchProduct(name, IDX).groupId;
const r = (name) => T.matchProduct(name, IDX).reason;

check('positive: чой, ун, ёғ, қоғоз, макарон, совун', () => {
  assert.strictEqual(g('Хитой кўк чойи'), 'green_tea');
  assert.strictEqual(g('Кўк чой ГРАНД ЧОЙ'), 'green_tea');
  assert.strictEqual(g('Цитрусли Қора чой  TESS'), 'black_tea');
  assert.strictEqual(g('МАКФА уни'), 'flour');
  assert.strictEqual(g('ун Эъзоз'), 'flour');
  assert.strictEqual(g('GAP YO"Q пахта ёғи, 2 литр'), 'cottonseed_oil');
  assert.strictEqual(g('ОРИЕН кунгабоқар ёғи'), 'sunflower_oil');
  assert.strictEqual(g('Ҳожатхона қоғози 8 та рулон'), 'toilet_paper');
  assert.strictEqual(g('Спагетти макарони'), 'pasta');
  assert.strictEqual(g('Хўжалик совуни'), 'soap');
  assert.strictEqual(g('Aprel кир ювиш кукуни'), 'laundry');
});

check('ибора бир сўзли номдан устун: «… Лимон … қора чойи» → black_tea (lemon эмас)', () => {
  assert.strictEqual(g('Имбир, Лимон, Мята таъмли TESS қора чойи'), 'black_tea');
});

check('CONFIRMED (эга 2026-11-28): семичка → sunflower_oil, мойка → dish_wash, горох → chickpea, «Океан … гели» → laundry', () => {
  assert.strictEqual(g('Семичка мойи КРИСТАЛЛИНА'), 'sunflower_oil');
  assert.strictEqual(g('АЛИФ семичка мойи'), 'sunflower_oil');
  assert.strictEqual(g('посуда мойка'), 'dish_wash');
  assert.strictEqual(g('горох Натурелла'), 'chickpea');
  assert.strictEqual(g('Океан, универсал ювиш гели, барча турга ишлатса бўлади 5 литр'), 'laundry');
  assert.deepStrictEqual({ ...T.ALIASES }, { семичка: 'sunflower_oil', мойка: 'dish_wash' });
});

// ── Таксономия v4 (янги гуруҳлар; гуруҳ танлови PROPOSED) ──
const IDX4 = T.buildIndex(TAX4);
const g4 = (name) => T.matchProduct(name, IDX4).groupId;
const r4 = (name) => T.matchProduct(name, IDX4).reason;
// prod'даги 59 намунадан қолган 10 таси (2026-11-28 DRY RUN, номлар prod'дан айнан).
const LEFT10 = {
  'Банкалар учун металл қопқоқ 50 дона': 'small_household',
  Гугурт: 'small_household',
  'резина қўлқоп': 'small_household',
  Перловка: 'pearl_barley',
  'Пишевая сода': 'baking_soda',
  Фунчоза: 'funchoza',
  'Қуриқ қаймоқ': null,
  'Тузланган бодиринг': null,
  'тузланган қалампир': null,
  'MILTER писта ёғи 5 литр': null,
};

check('v4 positive: 6 та гуруҳсиз намуна янги гуруҳга тушади', () => {
  for (const [name, want] of Object.entries(LEFT10)) if (want) assert.strictEqual(g4(name), want, name);
});

check('v4: 4 таси ҳали ҳам тегилмайди (EXCLUDED тузланган/қуриқ; MILTER писта ёғи — NO_MATCH, эга ҳал қилади)', () => {
  assert.strictEqual(r4('Қуриқ қаймоқ'), 'EXCLUDED:қуриқ');
  assert.strictEqual(r4('Тузланган бодиринг'), 'EXCLUDED:тузланган');
  assert.strictEqual(r4('тузланган қалампир'), 'EXCLUDED:тузланган');
  assert.strictEqual(r4('MILTER писта ёғи 5 литр'), 'NO_MATCH');
});

check('v4 boundary/negative: ягона синоним (1 балл) етарли; умумий сўз ўғирламайди; эски 49 таси ўзгармайди', () => {
  assert.strictEqual(T.matchProduct('қопқоқ', IDX4).score, 1); // чегара: ≥ 1
  assert.strictEqual(g4('пищевая плёнка'), null); // «пищевая» ёлғиз синоним эмас — сода эмас
  assert.strictEqual(g4('Кока кола газли'), 'soda'); // ичимлик «soda» гуруҳи baking_soda билан аралашмайди
  const old49 = ['Хитой кўк чойи', 'МАКФА уни', 'GAP YO"Q пахта ёғи, 2 литр', 'Спагетти макарони', 'Хўжалик совуни', 'Aprel кир ювиш кукуни',
    'Ҳожатхона қоғози 8 та рулон', 'Суюк порошок', 'Имбир, Лимон, Мята таъмли TESS қора чойи', 'Семичка мойи КРИСТАЛЛИНА', 'посуда мойка', 'горох Натурелла'];
  for (const n of old49) assert.strictEqual(g4(n), g(n), n);
});

check('v3 (prod ҳозир): янги гуруҳлар йўқ — 6 таси NO_MATCH (таксономия кўтарилмагунча)', () => {
  for (const [name, want] of Object.entries(LEFT10)) if (want) assert.strictEqual(r(name), 'NO_MATCH', name);
});

check('negative: қисқа калит сўз бошида — қўшимча эмас («универсал» ≠ «ун», «тузланган» ≠ «туз»)', () => {
  assert.strictEqual(T.tokenMatches('универсал', 'ун'), false);
  assert.strictEqual(T.tokenMatches('уни', 'ун'), true);
  assert.strictEqual(T.tokenMatches('тузланган', 'туз'), false);
  assert.notStrictEqual(g('Океан, универсал ювиш гели 5 литр'), 'flour');
});

check('negative: EXCLUDE (тузланган/қуриқ) — автомат мослаштирилмайди', () => {
  assert.strictEqual(g('тузланган қалампир'), null);
  assert.strictEqual(r('тузланган қалампир'), 'EXCLUDED:тузланган');
  assert.strictEqual(g('Қуриқ қаймоқ'), null);
});

check('negative: NO_MATCH ва AMBIGUOUS (фақат умумий сўз «ёғ») — тегилмайди', () => {
  assert.strictEqual(r('Гугурт'), 'NO_MATCH');
  assert.strictEqual(r('Банкалар учун металл қопқоқ 50 дона'), 'NO_MATCH');
  const m = T.matchProduct('MILTER писта ёғи 5 литр', IDX);
  assert.strictEqual(m.groupId, null);
  assert.strictEqual(m.reason, 'NO_MATCH'); // 0.5 + 0.5 — ҳар бири < 1
  const tie = T.buildIndex({ categories: [{ id: 'c', groups: [{ id: 'a1', names: { uz_Cyrl: 'Олма' } }, { id: 'a2', names: { uz_Cyrl: 'Нок' } }] }] });
  assert.strictEqual(T.matchProduct('олма нок', tie).reason, 'AMBIGUOUS');
});

check('planAssign: categoryId гуруҳдан; SKIP_HAS_GROUP / SKIP_PARTNER; UNMATCHED', () => {
  const rows = T.planAssign([
    { id: 'p1', name: 'Қора чой' },
    { id: 'p2', name: 'Қора чой', smGroupId: 'black_tea' },
    { id: 'p3', name: 'Қора чой', smPartnerKey: 'k'.repeat(16) },
    { id: 'p4', name: 'Гугурт' },
  ], TAX);
  assert.deepStrictEqual(rows.map((x) => x.action), ['ASSIGN', 'SKIP_HAS_GROUP', 'SKIP_PARTNER', 'UNMATCHED']);
  assert.strictEqual(rows[0].groupId, 'black_tea');
  assert.strictEqual(rows[0].categoryId, TAX.categories.find((c) => c.groups.some((x) => x.id === 'black_tea')).id);
});

check('idempotent: бириктирилган ҳужжатлар қайта режада 0 ASSIGN', () => {
  const docs = [{ id: 'a', name: 'Хитой кўк чойи' }, { id: 'b', name: 'МАКФА уни' }];
  const first = T.planAssign(docs, TAX);
  const after = docs.map((d, i) => ({ ...d, smGroupId: first[i].groupId }));
  assert.strictEqual(T.planAssign(after, TAX).filter((x) => x.action === 'ASSIGN').length, 0);
});

check('--map: устун, null — тегилмайди, номаълум гуруҳ — рад', () => {
  const rows = T.planAssign([{ id: 'x', name: 'Гугурт' }, { id: 'y', name: 'Қора чой' }], TAX, { x: 'salt', y: null });
  assert.deepStrictEqual(rows.map((z) => [z.action, z.groupId || null, z.source]), [['ASSIGN', 'salt', 'map'], ['SKIP_MAP_NULL', null, 'map']]);
  assert.throws(() => T.planAssign([{ id: 'x', name: 'Гугурт' }], TAX, { x: 'caviar' }), /GROUP_UNKNOWN/);
});

check('planRollback: фақат скрипт ёзган қиймат ва намуна эмас', () => {
  const bk = [
    { id: 'a', after: { smGroupId: 'flour', smCategoryId: 'grain_flour' } },
    { id: 'b', after: { smGroupId: 'flour', smCategoryId: 'grain_flour' } },
    { id: 'c', after: { smGroupId: 'flour', smCategoryId: 'grain_flour' } },
    { id: 'd', after: { smGroupId: 'flour', smCategoryId: 'grain_flour' } },
  ];
  const cur = [
    { id: 'a', exists: true, smGroupId: 'flour', smCategoryId: 'grain_flour', updateTime: 't1' },
    { id: 'b', exists: true, smGroupId: 'flour', smCategoryId: 'grain_flour', smSample: true },
    { id: 'c', exists: true, smGroupId: 'pasta', smCategoryId: 'grain_flour' },
    { id: 'd', exists: false },
  ];
  const p = T.planRollback(bk, cur);
  assert.deepStrictEqual(p.writes, [{ id: 'a', updateTime: 't1' }]);
  assert.deepStrictEqual(p.skipped.map((s) => s.id), ['b', 'c', 'd']);
});

(async () => {
  // --taxonomy-file фақат DRY RUN: --apply / --rollback билан Firestore'га уланмасдан рад этилади.
  try {
    assert.strictEqual(T.parseArgs(['--project', 'p', '--taxonomy-file', 'v4.json']).taxonomyFile, 'v4.json');
    for (const extra of [['--apply'], ['--rollback', 'b.json']]) {
      await assert.rejects(T.main(['--project', 'demo-x', '--taxonomy-file', 'v4.json', ...extra]), /faqat DRY RUN/);
    }
    await assert.rejects(T.main(['--project', 'demo-x', '--taxonomy-file']), /fayli berilmadi/);
    results.push(true); console.log('PASS - --taxonomy-file: фақат DRY RUN (apply/rollback рад)');
  } catch (e) { results.push(false); console.log(`FAIL - --taxonomy-file guard :: ${e.message}`); }
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
})();
