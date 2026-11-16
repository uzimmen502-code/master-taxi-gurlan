/**
 * Сервер қидируви токенлари (2026-11-16) — тоза тестлар: `node test/market_search_tokens_pure.test.js`.
 * Клиент паритети: `lib/features/ads/utils/ad_search_text.dart` (AdSearchText) билан бир хил нормализация.
 */
'use strict';
const assert = require('assert');
const m = require('../market_search_tokens');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};

check('P1 toLatin/toCyrillic — AdSearchText жадвали (ў/ғ/ҳ/қ, диграфлар, foldMarks)', () => {
  assert.strictEqual(m.toLatin('Қўй ғишт ҳовли'), "qo'y g'isht hovli");
  assert.strictEqual(m.toCyrillic("qo'y g'isht hovli"), 'қўй ғишт ҳовли');
  assert.strictEqual(m.toCyrillic('qoʻy'), 'қўй'); // ʻ → ' → ў
  assert.strictEqual(m.toCyrillic('qo‘y'), 'қўй'); // U+2018
  assert.strictEqual(m.toLatin('Щётка'), 'shyotka');
  assert.strictEqual(m.toCyrillic('choynak'), 'чойнак');
});
check('P2 words — клиент _wordSplit: кичик ҳарф, <2 ҳарф ташланади, ʻ сўз ичида қолади', () => {
  assert.deepStrictEqual(m.words('Sigir, 3 yosh! a qoʻy'), ['sigir', 'yosh', 'qoʻy']);
  assert.deepStrictEqual(m.words(''), []);
  assert.deepStrictEqual(m.words(null), []);
});
check('P3 бутун сўз ҳар уч ёзувда + бошлар (≥3); клиент queryTokens бутун сўзлари ичида', () => {
  const t = m.buildSearchTokens(['Sigir', '']);
  for (const x of ['sigir', 'сигир', 'sig', 'sigi', 'сиг', 'сиги']) assert.ok(t.includes(x), x);
  assert.ok(!t.includes('si'), '2 ҳарфли бош йўқ');
  const c = m.buildSearchTokens(['Телефон Samsung', '']);
  for (const x of ['телефон', 'telefon', 'tel', 'теле', 'samsung', 'самсуң', 'sam']) assert.ok(c.includes(x), x);
});
check('P4 бош апостроф билан тугамайди', () => {
  const t = m.buildSearchTokens(["qo'chqor", '']);
  assert.ok(!t.some((x) => x.endsWith("'")), t.join(','));
  assert.ok(t.includes("qo'c"));
});
check('P5 лимит 60, title биринчи (узун тавсиф title сўзларини сиқиб чиқармайди)', () => {
  const long = Array.from({ length: 80 }, (_, i) => `soz${i}abc`).join(' ');
  const t = m.buildSearchTokens(['Mol', long]);
  assert.strictEqual(t.length, m.MAX_TOKENS);
  assert.ok(t.includes('mol') && t.includes('мол'));
});
check('P6 детерминистик ва дубликатсиз', () => {
  const a = m.shopItemTokens({ title: 'Qoʻy qoʻy', description: 'Qo\'y' });
  const b = m.shopItemTokens({ title: 'Qoʻy qoʻy', description: 'Qo\'y' });
  assert.deepStrictEqual(a, b);
  assert.strictEqual(new Set(a).size, a.length);
});
check('P7 realtyTokens: title+text; ownerName/addressText/телефон КИРМАЙДИ', () => {
  const t = m.realtyTokens({ title: 'Uy', text: 'Hovli katta', ownerName: 'Akmal', addressText: 'Navoiy 12', phone: '998901112233' });
  assert.ok(t.includes('hovli') && t.includes('ҳовли'));
  for (const x of ['akmal', 'navoiy', '998901112233', 'nav']) assert.ok(!t.includes(x), x);
});
check('P8 planTokens: ўчирилган → null; токен тенг → null; бузилган токен → тузатилади', () => {
  assert.strictEqual(m.planTokens('tv_shop_items', { title: 'a' }, null), null);
  const d = { title: 'Sigir', description: 'sog\'lom' };
  const tok = m.shopItemTokens(d);
  assert.strictEqual(m.planTokens('tv_shop_items', null, { ...d, searchTokens: tok }), null);
  assert.strictEqual(m.planTokens('tv_shop_items', d, { ...d, price: 5, searchTokens: tok }), null);
  assert.deepStrictEqual(m.planTokens('tv_shop_items', d, { ...d, price: 5, searchTokens: ['eski'] }), tok);
  assert.deepStrictEqual(m.planTokens('tv_shop_items', d, { ...d, title: 'Buqa', searchTokens: tok }), m.shopItemTokens({ ...d, title: 'Buqa' }));
  assert.deepStrictEqual(m.planTokens('tv_shop_items', d, { ...d }), tok, 'токен йўқ → ёзилади');
  assert.deepStrictEqual(m.planTokens('realty_listings', null, { title: 'Uy', text: '' }), m.realtyTokens({ title: 'Uy' }));
});
check('P9 бўш матн → бўш массив (ёзилади, токенсиз ҳужжат қидирувга тушмайди)', () => {
  assert.deepStrictEqual(m.shopItemTokens({}), []);
  assert.deepStrictEqual(m.planTokens('tv_shop_items', null, {}), []);
  assert.strictEqual(m.planTokens('tv_shop_items', null, { searchTokens: [] }), null);
});
check('P10 onShopItemModeration CONTENT_FIELDS ичида searchTokens ЙЎҚ (ўзаро loop/pending йўқ)', () => {
  const mod = require('../market_moderation');
  assert.ok(!mod.CONTENT_FIELDS.includes('searchTokens'));
  assert.strictEqual(mod.contentChanged({ title: 'a' }, { title: 'a', searchTokens: ['x'] }), false);
});

const failed = results.filter((x) => !x).length;
console.log(`\n${results.length - failed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
