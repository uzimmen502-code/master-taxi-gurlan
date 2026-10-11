/**
 * Русча ҳудуд номлари (`data/geo_names_ru.js`) ва backfill режаси.
 *
 *   node test/geo_names_ru.test.js
 */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  REGIONS_RU,
  DISTRICTS_RU,
  REGIONS_RU_SHORT,
  DISTRICTS_RU_SHORT,
} = require('../tools/data/geo_names_ru');
const { REGIONS, DISTRICTS_BY_REGION } = require('../tools/data/uzbekistan_geo_data');
const { planNameRu } = require('../tools/backfill-geo-name-ru');

let passed = 0;
function t(name, fn) {
  fn();
  passed++;
  console.log('  ✓', name);
}

// Хоразм seed скрипти импорт қилинса ишга тушиб кетади — ID'ларни матндан оламиз.
const seedSrc = fs.readFileSync(path.join(__dirname, '..', 'tools', 'seed-service-config.js'), 'utf8');
const khorezmBlock = seedSrc.slice(seedSrc.indexOf('const KHOREZM_DISTRICTS'), seedSrc.indexOf('];', seedSrc.indexOf('const KHOREZM_DISTRICTS')));
const KHOREZM_IDS = [...khorezmBlock.matchAll(/id: '([a-z_]+)'/g)].map((m) => m[1]);

t('Хоразм ID\'лари матндан топилди', () => {
  assert.ok(KHOREZM_IDS.includes('gurlan'));
  assert.strictEqual(KHOREZM_IDS.length, 13);
});

t('ҳар бир seed вилоятининг русча номи бор', () => {
  const ids = ['xorazm', ...REGIONS.map((r) => r.id)];
  const missing = ids.filter((id) => !REGIONS_RU[id]);
  assert.deepStrictEqual(missing, []);
  assert.deepStrictEqual(Object.keys(REGIONS_RU).sort(), ids.sort(), 'ортиқча калит йўқ');
});

t('ҳар бир seed туманининг русча номи бор (ортиқчаси йўқ)', () => {
  const ids = [...KHOREZM_IDS, ...Object.values(DISTRICTS_BY_REGION).flat().map((d) => d.id)];
  assert.strictEqual(new Set(ids).size, ids.length, 'seed ID\'лари такрорланмайди');
  const missing = ids.filter((id) => !DISTRICTS_RU[id]);
  assert.deepStrictEqual(missing, []);
  assert.deepStrictEqual(Object.keys(DISTRICTS_RU).sort(), [...ids].sort());
});

t('номлар — кирилл рус ҳарфлари, ўзбекча ҳарф (ўқғҳ) ёки «тумани» йўқ', () => {
  for (const [id, n] of Object.entries({ ...REGIONS_RU, ...DISTRICTS_RU })) {
    assert.ok(/^[А-Яа-яЁё -]+$/.test(n), `${id}: «${n}»`);
    assert.ok(!/[ўқғҳЎҚҒҲ]|тумани|шаҳри|вилояти/.test(n), `${id}: «${n}»`);
  }
});

t('қисқа номлар: фақат тўлиқ номи борларга, «район»/«город»сиз, тўлиқ номнинг ўзакидан', () => {
  for (const [map, full] of [[REGIONS_RU_SHORT, REGIONS_RU], [DISTRICTS_RU_SHORT, DISTRICTS_RU]]) {
    for (const [id, s] of Object.entries(map)) {
      assert.ok(full[id], `${id}: тўлиқ номи йўқ`);
      assert.ok(/^[А-Яа-яЁё-]+$/.test(s), `${id}: «${s}»`);
      assert.ok(!/район|город|область/.test(s), `${id}: «${s}»`);
      // «Гурлен» ↔ «Гурленский район»: биринчи 3 ҳарф бир хил (тасодифий хатони ушлайди).
      assert.strictEqual(s.slice(0, 3).toLowerCase(), full[id].slice(0, 3).toLowerCase(), `${id}: «${s}» ↔ «${full[id]}»`);
    }
  }
  // «город X» — илова ўзи қисқартиради; шаҳар номли туман тўлиқ қолади.
  assert.strictEqual(DISTRICTS_RU_SHORT.urganch_shahri, undefined);
  assert.strictEqual(DISTRICTS_RU_SHORT.andijon_tumani, undefined);
  assert.strictEqual(DISTRICTS_RU_SHORT.gurlan, 'Гурлен');
});

t('режа: йўқ майдонлар → иккаласи ёзилади, before = null', () => {
  const p = planNameRu([{ collection: 'geo_districts', id: 'sirgali' }]);
  assert.deepStrictEqual(p.writes, [{
    path: 'geo_districts/sirgali',
    before: { nameRu: null, nameRuShort: null },
    data: { nameRu: 'Сергелийский район', nameRuShort: 'Сергели' },
  }]);
});

t('режа: қисқа шакли йўқ ҳужжат → фақат nameRu', () => {
  const p = planNameRu([{ collection: 'geo_districts', id: 'urganch_shahri' }]);
  assert.deepStrictEqual(p.writes[0].data, { nameRu: 'город Ургенч' });
});

t('режа: бир хил қийматлар → қайта ёзилмайди (idempotent)', () => {
  const p = planNameRu([{
    collection: 'geo_districts', id: 'sirgali', nameRu: 'Сергелийский район', nameRuShort: 'Сергели',
  }]);
  assert.deepStrictEqual(p.writes, []);
  assert.deepStrictEqual(p.conflicts, []);
});

t('режа: қўлда ёзилган бошқа қиймат → тегилмайди, қолган майдон ёзилади; --overwrite билан ҳаммаси', () => {
  const docs = [{ collection: 'geo_regions', id: 'xorazm', nameRu: 'Хорезм вилоят' }];
  const p = planNameRu(docs);
  assert.strictEqual(p.conflicts.length, 1);
  assert.strictEqual(p.conflicts[0].field, 'nameRu');
  assert.deepStrictEqual(p.writes, [{
    path: 'geo_regions/xorazm', before: { nameRuShort: null }, data: { nameRuShort: 'Хорезм' },
  }]);
  const o = planNameRu(docs, { overwrite: true });
  assert.deepStrictEqual(o.writes[0].data, { nameRu: 'Хорезмская область', nameRuShort: 'Хорезм' });
  assert.deepStrictEqual(o.writes[0].before, { nameRu: 'Хорезм вилоят', nameRuShort: null });
});

t('режа: бўш/пробел қиймат — йўқ деб ҳисобланади', () => {
  const p = planNameRu([{ collection: 'geo_regions', id: 'andijon', nameRu: '  ' }]);
  assert.strictEqual(p.writes.length, 1);
  assert.deepStrictEqual(p.writes[0].before, { nameRu: null });
});

t('режа: номи йўқ ҳужжат ва ҳужжати йўқ ном алоҳида кўрсатилади', () => {
  const p = planNameRu([
    { collection: 'geo_districts', id: 'admin_qoshgan_tuman' },
    { collection: 'service_areas', id: 'svc_gurlan_markaz' },
  ]);
  assert.deepStrictEqual(p.writes, []);
  assert.deepStrictEqual(p.missingName, ['geo_districts/admin_qoshgan_tuman']);
  assert.ok(p.missingDoc.includes('geo_districts/gurlan'));
  assert.ok(!p.missingDoc.some((x) => x.startsWith('service_areas')));
});

console.log(`\n${passed} passed`);