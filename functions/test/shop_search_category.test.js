/**
 * S6 (2026-11-03): бизнес объектининг қидирув ёзуви тур бўйича (сартарош/клиника «дўкон» эмас). Соф функция — эмулятор
 * керак эмас:   node test/shop_search_category.test.js
 *
 * Паритет: `business_category_labels.json` калитлари = `business_directory.js` CATEGORIES; номлар = мижоз
 * `assets/lang/*.json` (`business_cat_<wire>`, `business_cat_short_<wire>`). Сервер линиясидаги worktree'да lang
 * эски (14 тур) бўлса — 30 тур киритилган коммит 3be2e413 (git) билан солиштирилади.
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const { businessToSearchEntry, shopItemToSearchEntry } = require('../shop_search_index');
const { CATEGORIES } = require('../business_directory');
const { SEARCH_INDEX_MAX_TOKENS, buildSearchIndexTokens } = require('../search_tokens');
const LABELS = require('../business_category_labels.json');

const OWNER = '998914100001';
const SHOP_WORDS = ['дўкон', 'dokon', "do'kon", 'магазин', 'бозор', 'bozor'];
const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
const biz = (extra) => businessToSearchEntry('b1', { ownerId: OWNER, name: 'Ali', status: 'active', ...extra });
const noShopWords = (e) => {
  for (const w of SHOP_WORDS) {
    assert.ok(!e.keywords.includes(w), `keyword ${w}`);
    assert.ok(!e.searchTokens.includes(w), `token ${w}`);
  }
};

function clientLang(lang) {
  const file = path.join(__dirname, '..', '..', 'assets', 'lang', `${lang}.json`);
  if (fs.existsSync(file)) {
    const j = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (j.business_cat_marketing) return { src: file, j };
  }
  try {
    const raw = execFileSync('git', ['show', `3be2e413:assets/lang/${lang}.json`], {
      cwd: path.join(__dirname, '..'), encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'],
    });
    return { src: `git 3be2e413:assets/lang/${lang}.json`, j: JSON.parse(raw) };
  } catch (_) {
    return null;
  }
}

check('C1 labels JSON keys == CATEGORIES (30), har birida full/short x 3 til', () => {
  assert.deepStrictEqual(Object.keys(LABELS).sort(), [...CATEGORIES].sort());
  assert.strictEqual(CATEGORIES.length, 30);
  for (const c of CATEGORIES) {
    for (const kind of ['full', 'short']) {
      for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) assert.ok(String(LABELS[c][kind][l] || '').trim(), `${c}.${kind}.${l}`);
    }
  }
});

check('C2 paritet: server nomlari = mijoz assets/lang business_cat_* (3 til)', () => {
  for (const lang of ['uz_Cyrl', 'uz_Latn', 'ru']) {
    const got = clientLang(lang);
    if (!got) { console.log(`  SKIP ${lang}: mijoz lang topilmadi (git yo'q)`); continue; }
    for (const c of CATEGORIES) {
      assert.strictEqual(LABELS[c].full[lang], got.j[`business_cat_${c}`], `${got.src} business_cat_${c}`);
      assert.strictEqual(LABELS[c].short[lang], got.j[`business_cat_short_${c}`], `${got.src} business_cat_short_${c}`);
    }
  }
});

check('R1 retail: do\'kon so\'zlari qoladi + tur nomi; subtitle = tur nomi (oflayn, subtype yo\'q)', () => {
  const e = biz({ category: 'retail', address: 'Gurlan, Mustaqillik 5' });
  for (const w of SHOP_WORDS) assert.ok(e.keywords.includes(w), w);
  assert.ok(e.keywords.includes('савдо ва дўконлар') && e.keywords.includes('торговля'));
  assert.strictEqual(e.subtitle, 'Савдо ва дўконлар');
  assert.ok(e.searchTokens.includes('дўкон') && e.searchTokens.includes('savdo'));
  assert.ok(e.searchTokens.includes('mustaqillik'), 'manzil hali ham qidiriladi');
  assert.deepStrictEqual([e.type, e.moduleId, e.iconKey, e.active], ['shop', 'cheap_products_home', 'shop', true]);
});

check('R2 online retail: subtitle «Онлайн дўкон»; subtype bo\'lsa — subtype', () => {
  assert.strictEqual(biz({ category: 'retail', online: true }).subtitle, 'Онлайн дўкон');
  assert.strictEqual(biz({ category: 'retail', online: true, subtype: 'Кийим-кечак' }).subtitle, 'Кийим-кечак');
  assert.strictEqual(biz({ category: 'wholesale', online: true }).subtitle, 'Онлайн дўкон', 'eski wire -> retail');
});

check('R3 fashion: do\'kon so\'zlari bor (kiyim do\'koni)', () => {
  const e = biz({ category: 'fashion' });
  for (const w of SHOP_WORDS) assert.ok(e.keywords.includes(w), w);
  assert.strictEqual(e.subtitle, 'Мода ва тўй');
});

check('S1 health: «Тиббиёт» bilan topiladi (kirill/lotin/rus), «дўкон» yo\'q', () => {
  const e = biz({ category: 'health', subtype: 'Стоматология', address: 'Urganch' });
  noShopWords(e);
  for (const t of ['тиббиёт', 'tibbiyot', 'медицина', 'стоматология', 'stomatologiya', 'саломатлик', 'здоровье']) {
    assert.ok(e.searchTokens.includes(t), t);
  }
  assert.strictEqual(e.subtitle, 'Стоматология');
  assert.strictEqual(biz({ category: 'health' }).subtitle, 'Тиббиёт');
});

check('S2 personal (sartarosh): tur nomi, «дўкон»/«Онлайн дўкон» yo\'q; online ham do\'kon emas', () => {
  const e = biz({ category: 'personal', subtype: 'Сартарошхона' });
  noShopWords(e);
  assert.ok(e.searchTokens.includes('маиший') && e.searchTokens.includes('maishiy') && e.searchTokens.includes('бытовые'));
  assert.ok(e.searchTokens.includes('сартарошхона') && e.searchTokens.includes('sartaroshxona'));
  const o = biz({ category: 'personal', online: true });
  noShopWords(o);
  assert.strictEqual(o.subtitle, 'Маиший хизматлар');
});

check('S3 eski wire home_services -> personal; professional (yurist) do\'kon emas', () => {
  const e = biz({ category: 'home_services' });
  noShopWords(e);
  assert.strictEqual(e.subtitle, 'Маиший хизматлар');
  const y = biz({ category: 'professional' });
  noShopWords(y);
  assert.ok(y.searchTokens.includes('yuridik') && y.searchTokens.includes('юридик'));
});

check('S4 «other»: subtitle manzil (Бошқа emas), manzil yo\'q bo\'lsa — «Бошқа»; do\'kon emas', () => {
  assert.strictEqual(biz({ category: 'other', address: 'Gurlan' }).subtitle, 'Gurlan');
  assert.strictEqual(biz({ category: 'other' }).subtitle, 'Бошқа');
  noShopWords(biz({ category: 'other' }));
});

check('L1 turi yo\'q/notanish (eski hujjat): avvalgi xulq — do\'kon so\'zlari, subtitle manzil/«Онлайн дўкон»', () => {
  const e = biz({ address: 'Urganch' });
  for (const w of SHOP_WORDS) assert.ok(e.keywords.includes(w), w);
  assert.strictEqual(e.subtitle, 'Urganch');
  assert.strictEqual(biz({ category: 'nonsense' }).subtitle, 'Онлайн дўкон');
});

check('T1 barcha 30 tur: tokenlar <= 64, nomi va qisqa tur nomi tokenlarda, deterministik', () => {
  for (const c of CATEGORIES) {
    const d = { category: c, subtype: 'Аниқроқ тур номи узунроқ', address: 'Хоразм вилояти, Гурлан тумани, Мустақиллик кўчаси 12' };
    const a = biz(d);
    const b = biz(d);
    assert.deepStrictEqual(a, b, `${c} deterministik`);
    assert.ok(a.searchTokens.length <= SEARCH_INDEX_MAX_TOKENS, `${c} ${a.searchTokens.length}`);
    assert.ok(a.searchTokens.includes('ali'), `${c} nomi`);
    const shortTok = buildSearchIndexTokens(LABELS[c].short.uz_Cyrl);
    for (const t of shortTok) assert.ok(a.searchTokens.includes(t), `${c} ${t}`);
    assert.ok(a.keywords.length <= 48, `${c} keywords`);
    assert.strictEqual(new Set(a.keywords).size, a.keywords.length, `${c} takrorsiz`);
  }
});

check('T2 eng uzun nom (80) + subtype (60): chegara 64 buzilmaydi; nom birinchi', () => {
  const name = 'Ааааа Бббббб Вввввв Гггггг Дддддд Ееееее Жжжжжж Зззззз Ииииии Кккккк Лллллл'.slice(0, 80);
  const e = businessToSearchEntry('b2', { ownerId: OWNER, name, category: 'health', subtype: 'Х'.repeat(60) });
  assert.ok(e.searchTokens.length <= SEARCH_INDEX_MAX_TOKENS);
  assert.strictEqual(e.searchTokens[0], 'ааааа');
  // Ортиқча матн (манзил 200 белги) — чегара кесади, номи ва тури сақланади.
  const long = businessToSearchEntry('b3', {
    ownerId: OWNER, name, category: 'health', subtype: 'Х'.repeat(60),
    address: Array.from({ length: 40 }, (_, i) => `kocha${i}`).join(' '),
  });
  assert.strictEqual(long.searchTokens.length, SEARCH_INDEX_MAX_TOKENS);
  assert.ok(long.searchTokens.includes('тиббиёт') && long.searchTokens.includes('ааааа'));
});

check('I1 shop_item: kind service — «Хизмат», do\'kon so\'zlari yo\'q; product — avvalgidek; tokenlar o\'zgarmaydi', () => {
  const base = { ownerPhone: OWNER, title: 'Soch olish', status: 'active' };
  const sv = shopItemToSearchEntry('i1', { ...base, kind: 'service' });
  const pr = shopItemToSearchEntry('i1', { ...base });
  assert.strictEqual(sv.subtitle, 'Хизмат');
  assert.deepStrictEqual(sv.keywords, ['хизмат', 'xizmat', 'услуга']);
  assert.strictEqual(pr.subtitle, 'Онлайн дўкон');
  assert.deepStrictEqual(pr.keywords, SHOP_WORDS);
  assert.deepStrictEqual(sv.searchTokens, pr.searchTokens, 'mahsulot hujjati qayta yozilmaydi');
  assert.strictEqual(shopItemToSearchEntry('i1', { ...base, kind: 'service', ownerName: 'Ali' }).subtitle, 'Ali');
});

const failed = results.filter((r) => !r).length;
console.log(`\n${results.length - failed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
