/**
 * Русча ҳудуд номлари (`data/geo_names_ru.js`) ва backfill режаси.
 *
 *   node test/geo_names_ru.test.js
 */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { REGIONS_RU, DISTRICTS_RU } = require('../tools/data/geo_names_ru');
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

t('режа: йўқ nameRu → ёзилади, before = null', () => {
  const p = planNameRu([{ collection: 'geo_districts', id: 'sirgali' }]);
  assert.deepStrictEqual(p.writes, [
    { path: 'geo_districts/sirgali', before: null, nameRu: 'Сергелийский район' },
  ]);
});

t('режа: бир хил nameRu → қайта ёзилмайди (idempotent)', () => {
  const p = planNameRu([{ collection: 'geo_districts', id: 'sirgali', nameRu: 'Сергелийский район' }]);
  assert.deepStrictEqual(p.writes, []);
  assert.deepStrictEqual(p.conflicts, []);
});

t('режа: қўлда ёзилган бошқа nameRu → тегилмайди; --overwrite билан ёзилади', () => {
  const docs = [{ collection: 'geo_regions', id: 'xorazm', nameRu: 'Хорезм' }];
  const p = planNameRu(docs);
  assert.deepStrictEqual(p.writes, []);
  assert.strictEqual(p.conflicts.length, 1);
  const o = planNameRu(docs, { overwrite: true });
  assert.deepStrictEqual(o.writes, [
    { path: 'geo_regions/xorazm', before: 'Хорезм', nameRu: 'Хорезмская область' },
  ]);
});

t('режа: бўш/пробел nameRu — йўқ деб ҳисобланади', () => {
  const p = planNameRu([{ collection: 'geo_regions', id: 'andijon', nameRu: '  ' }]);
  assert.strictEqual(p.writes.length, 1);
  assert.strictEqual(p.writes[0].before, null);
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
