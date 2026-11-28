/**
 * «AVA Супермаркет» ўлчов бирликлари (эга 2026-11-28: «ҳақиқий маҳсулотлар учун дона, кг, литр ва бошқа ўлчов бирликлар
 * керак»). Тоза тест (эмуляторсиз):  node test/supermarket_units_pure.test.js
 * Қулфланади: ягона манба supermarket_units.json → UNITS/UNIT_LABELS; рўйхат (PROPOSED: + g, ml, box, m); 3 тил;
 * aliases тўқнашмайди; unitFromInput; validateOffer/priceSupermarketOrder/импорт қатори янги бирликларни қабул қилади;
 * эски ҳужжат (unit 'дона' матни) — аввалгидек 'piece'; PACK_UNITS ўзгармаган.
 */
'use strict';
const assert = require('assert');
const sm = require('../supermarket');
const imp = require('../supermarket_import');
const SRC = require('../supermarket_units.json');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.message}`); }
};
const LATN_OLD = /o'|g'|o‘|g‘|sh|ch/i;

check('U1 ягона манба: UNITS = supermarket_units.json тартиби; эски 5 та аввалгидек бошида', () => {
  assert.deepStrictEqual([...sm.UNITS], SRC.units.map((u) => u.id));
  assert.deepStrictEqual(sm.UNITS.slice(0, 5), ['kg', 'l', 'piece', 'pack', 'bunch']);
  for (const id of ['piece', 'kg', 'g', 'l', 'ml', 'pack', 'box', 'm']) assert.ok(sm.UNITS.includes(id), id);
  assert.strictEqual(new Set(sm.UNITS).size, sm.UNITS.length);
});

check('U2 ҳар бирлик 3 тилда ёрлиқ (uz_Latn янги алифбода); UNIT_LABELS — манбадан', () => {
  for (const u of SRC.units) {
    for (const l of sm.LANGS) assert.ok(typeof u.labels[l] === 'string' && u.labels[l].trim(), `${u.id} ${l}`);
    assert.ok(!LATN_OLD.test(u.labels.uz_Latn), `${u.id} uz_Latn`);
    assert.deepStrictEqual(sm.UNIT_LABELS[u.id], u.labels);
  }
  assert.strictEqual(sm.UNIT_LABELS.kg.uz_Cyrl, 'кг');
  assert.strictEqual(sm.UNIT_LABELS.piece.ru, 'шт');
  assert.strictEqual(sm.UNIT_LABELS.pack.uz_Cyrl, 'қадоқ'); // мижоз sm_unit_pack билан бир хил
});

check('U3 aliases: бир матн фақат битта бирликка (тўқнашув йўқ)', () => {
  const seen = new Map();
  for (const u of SRC.units) {
    for (const a of [u.id, ...(u.aliases || [])]) {
      const k = a.trim().toLowerCase();
      assert.ok(!seen.has(k) || seen.get(k) === u.id, `«${a}» ${seen.get(k)} ва ${u.id}`);
      seen.set(k, u.id);
    }
  }
});

check('U4 unitFromInput: id/матн → id; бўш → \'\'; номаълум → null', () => {
  const t = sm.unitFromInput;
  assert.strictEqual(t('kg'), 'kg');
  assert.strictEqual(t(' КГ '), 'kg');
  assert.strictEqual(t('Литр'), 'l');
  assert.strictEqual(t('шт'), 'piece');
  assert.strictEqual(t('дона'), 'piece');
  assert.strictEqual(t('пачка'), 'pack');
  assert.strictEqual(t('гр'), 'g');
  assert.strictEqual(t('мл'), 'ml');
  assert.strictEqual(t('коробка'), 'box');
  assert.strictEqual(t('кор.'), 'box');
  assert.strictEqual(t('метр'), 'm');
  assert.strictEqual(t(''), '');
  assert.strictEqual(t(null), '');
  assert.strictEqual(t('тонна'), null);
  assert.strictEqual(t('gram s'), null);
});

const OFFER = { smGroupId: 'flour', smVariety: { id: 'std', names: { uz_Cyrl: 'Оддий', uz_Latn: 'Oddiy', ru: 'Обычный' } }, stock: 10, smStatus: 'active', price: 5000 };

check('U5 validateOffer: янги бирликлар қабул; номаълум — UNIT_INVALID; PACK_UNITS ўзгармаган', () => {
  for (const unit of ['g', 'ml', 'box', 'm', 'piece', 'kg']) assert.ok(sm.validateOffer({ ...OFFER, unit }).ok, unit);
  assert.ok(sm.validateOffer({ ...OFFER, unit: 'gram' }).errors.includes('UNIT_INVALID offer.unit'));
  assert.ok(sm.validateOffer({ ...OFFER, unit: 'кг' }).errors.includes('UNIT_INVALID offer.unit')); // сервер фақат id
  assert.deepStrictEqual([...sm.PACK_UNITS], ['kg', 'l', 'piece']);
});

check('U6 priceSupermarketOrder: янги бирлик қаторга smUnit + uz_Cyrl ёрлиқ; эски «дона» матни → piece (аввалгидек)', () => {
  const p = (d) => sm.priceSupermarketOrder({ items: [{ productId: 'x1', qMilli: 2000 }], products: { x1: { ...OFFER, ...d } }, feeBp: 0, weighHoldPercent: 10 });
  const g = p({ unit: 'box' });
  assert.ok(g.ok, JSON.stringify(g));
  assert.deepStrictEqual([g.lines[0].smUnit, g.lines[0].unit, g.lines[0].total], ['box', 'қути', 10000]);
  const legacy = p({ unit: 'дона' });
  assert.deepStrictEqual([legacy.lines[0].smUnit, legacy.lines[0].unit], ['piece', 'дона']);
});

check('U7 Excel импорт қатори: «кг» → kg, «метр» → m, бўш — гуруҳники (unit йўқ), «тонна» → UNIT_INVALID', () => {
  const row = (unit, extra = {}) => imp.validateRow({ sku: 'sku_000001', groupId: 'flour', unit, price: 5000, stock: 3, ...extra });
  assert.strictEqual(row('кг').offer.unit, 'kg');
  assert.strictEqual(row('метр').offer.unit, 'm');
  assert.strictEqual(row('ml').offer.unit, 'ml');
  assert.ok(!('unit' in row('').offer));
  assert.ok(row('тонна').errors.includes('UNIT_INVALID'));
  assert.strictEqual(row('', { packQty: 1.5, packUnit: 'литр' }).offer.packUnit, 'l');
});

check('U8 импорт шаблони ёрдами — бирликлар рўйхати манбадан (3 тил)', () => {
  const col = imp.COLUMNS.find((c) => c.key === 'unit');
  for (const [i, l] of sm.LANGS.entries()) for (const u of SRC.units) assert.ok(col.help[i].includes(`${u.id} (${u.labels[l]})`), `${l} ${u.id}`);
});

const passed = results.filter(Boolean).length;
console.log(`\n${passed}/${results.length} passed`);
process.exit(passed === results.length ? 0 : 1);
