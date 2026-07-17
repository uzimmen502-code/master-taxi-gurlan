#!/usr/bin/env node
/**
 * Home Phase 2 — feed/featured/seller l10n + uz_Cyrl lotin qoldiqlarini tozalash.
 * Ishlatish: node tools/merge_home_l10n_phase2.js
 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', 'assets', 'lang');

/** @type {Record<string, { uz_Cyrl: string, uz_Latn: string, ru: string }>} */
const newKeys = {
  home_feed_title: {
    uz_Cyrl: 'Барча маҳсулотлар',
    uz_Latn: 'Barcha mahsulotlar',
    ru: 'Все товары',
  },
  home_feed_tab_bread: {
    uz_Cyrl: 'Нон',
    uz_Latn: 'Non',
    ru: 'Хлеб',
  },
  home_feed_tab_food: {
    uz_Cyrl: 'Таом',
    uz_Latn: 'Taom',
    ru: 'Еда',
  },
  home_feed_tab_market: {
    uz_Cyrl: 'Бозор',
    uz_Latn: 'Bozor',
    ru: 'Рынок',
  },
  home_feed_empty: {
    uz_Latn: 'Hozircha mahsulotlar yo\u2018q',
    ru: 'Пока нет товаров',
  },
  home_feed_no_more: {
    uz_Latn: 'Boshqa mahsulot yo\u2018q',
    ru: 'Больше товаров нет',
  },
  home_feed_load_more: {
    uz_Latn: 'Yana yuklash',
    ru: 'Загрузить ещё',
  },
  home_featured_title: {
    uz_Latn: 'Tavsiya etamiz',
    ru: 'Рекомендуем',
  },
  home_featured_empty: {
    uz_Latn: 'Hozircha tavsiyalar yo\u2018q',
    ru: 'Пока нет рекомендаций',
  },
  home_seller_cta: {
    uz_Latn: 'Siz ham soting',
    ru: 'Продавайте и вы',
  },
};

/** Promo matnlari (Phase 1 qoldiqlari). Qolgan scoped kalitlar uz_Latn dan olinadi. */
const cyrlOverrides = {
  non_promo_title: 'Non buyurtma qiling',
  non_promo_subtitle: 'Yangi non \u2014 500 so\u2018m, eshigingizga',
  home_promo_order_cta: 'Buyurtma bering \u2192',
};

const SCOPED_PREFIXES = [
  'milk_',
  'agro_',
  'marshrut_',
  'carpet_',
  'courier_hub',
  'intercity_pickup',
  'intercity_enter',
  'non_promo',
  'home_promo',
  'home_feed',
  'home_featured',
  'home_seller',
  'bread_flour_milk',
];

const LATIN = /[A-Za-z]/;

/** @param {string} text */
function latinToUzCyrl(text) {
  if (!text || !LATIN.test(text)) return text;

  /** @type {string[]} */
  const placeholders = [];
  let s = text.replace(/\{[^}]+\}/g, (m) => {
    placeholders.push(m);
    return `\x00P${placeholders.length - 1}\x00`;
  });

  const digraphs = [
    ["G'", 'Ғ'],
    ["g'", 'ғ'],
    ["O'", 'Ў'],
    ["o'", 'ў'],
    ['Yu', 'Ю'],
    ['yu', 'ю'],
    ['Ya', 'Я'],
    ['ya', 'я'],
    ['Yo', 'Ё'],
    ['yo', 'ё'],
    ['YA', 'Я'],
    ['YO', 'Ё'],
    ['YU', 'Ю'],
    ['Sh', 'Ш'],
    ['sh', 'ш'],
    ['Ch', 'Ч'],
    ['ch', 'ч'],
    ['Ng', 'Нг'],
    ['ng', 'нг'],
  ];
  for (const [from, to] of digraphs) {
    s = s.split(from).join(to);
  }

  /** @type {Record<string, string>} */
  const map = {
    A: 'А',
    B: 'Б',
    D: 'Д',
    E: 'Е',
    F: 'Ф',
    G: 'Г',
    H: 'Ҳ',
    I: 'И',
    J: 'Ж',
    K: 'К',
    L: 'Л',
    M: 'М',
    N: 'Н',
    O: 'О',
    P: 'П',
    Q: 'Қ',
    R: 'Р',
    S: 'С',
    T: 'Т',
    U: 'У',
    V: 'В',
    X: 'Х',
    Y: 'Й',
    Z: 'З',
    a: 'а',
    b: 'б',
    d: 'д',
    e: 'е',
    f: 'ф',
    g: 'г',
    h: 'ҳ',
    i: 'и',
    j: 'ж',
    k: 'к',
    l: 'л',
    m: 'м',
    n: 'н',
    o: 'о',
    p: 'п',
    q: 'қ',
    r: 'р',
    s: 'с',
    t: 'т',
    u: 'у',
    v: 'в',
    x: 'х',
    y: 'й',
    z: 'з',
  };

  s = s.replace(/[A-Za-z]/g, (c) => map[c] ?? c);
  s = s.replace(/\x00P(\d+)\x00/g, (_, i) => placeholders[Number(i)]);

  // Texnik atamalar
  s = s
    .replace(/\bGPS\b/g, 'GPS')
    .replace(/\bMFY\b/g, 'МФY')
    .replace(/\bETA\b/g, 'ETA')
    .replace(/\bkm\b/g, 'km')
    .replace(/\bml\b/g, 'ml')
    .replace(/\bmin\b/g, 'мин')
    .replace(/\bsek\b/g, 'сек')
    .replace(/\bpush\b/g, 'push')
    .replace(/\bOnlayn\b/g, 'Онлайн')
    .replace(/\bonlayn\b/g, 'онлайн');

  return s;
}

function isScopedKey(key) {
  return SCOPED_PREFIXES.some((p) => key.startsWith(p) || key.includes(p));
}

function mergeNewKeys() {
  for (const locale of ['uz_Cyrl', 'uz_Latn', 'ru']) {
    const p = path.join(root, `${locale}.json`);
    const data = JSON.parse(fs.readFileSync(p, 'utf8'));
    let n = 0;
    for (const [key, tr] of Object.entries(newKeys)) {
      if (locale === 'uz_Cyrl') {
        data[key] =
          tr.uz_Cyrl != null
            ? tr.uz_Cyrl
            : latinToUzCyrl(tr.uz_Latn);
      } else {
        data[key] = tr[locale];
      }
      n++;
    }
    const sorted = Object.fromEntries(
      Object.entries(data).sort(([a], [b]) => a.localeCompare(b)),
    );
    fs.writeFileSync(p, JSON.stringify(sorted, null, 2) + '\n');
    console.log(`${locale}: +${n} yangi kalit`);
  }
}

function fixCyrlScoped() {
  const latnPath = path.join(root, 'uz_Latn.json');
  const cyrlPath = path.join(root, 'uz_Cyrl.json');
  const latn = JSON.parse(fs.readFileSync(latnPath, 'utf8'));
  const cyrl = JSON.parse(fs.readFileSync(cyrlPath, 'utf8'));

  let fixed = 0;
  for (const key of Object.keys(cyrl)) {
    if (!isScopedKey(key)) continue;
    if (!LATIN.test(cyrl[key] ?? '')) continue;

    const source = cyrlOverrides[key] ?? latn[key] ?? cyrl[key];
    cyrl[key] = latinToUzCyrl(source);
    fixed++;
  }

  // Qo'lda override (har doim ustun)
  for (const [key, value] of Object.entries(cyrlOverrides)) {
    cyrl[key] = latinToUzCyrl(value);
  }

  const sorted = Object.fromEntries(
    Object.entries(cyrl).sort(([a], [b]) => a.localeCompare(b)),
  );
  fs.writeFileSync(cyrlPath, JSON.stringify(sorted, null, 2) + '\n');
  console.log(`uz_Cyrl: ${fixed} scoped kalit kirillga o'tkazildi`);
}

mergeNewKeys();
fixCyrlScoped();

// Qolgan lotin (scoped) tekshiruv
const cyrl = JSON.parse(fs.readFileSync(path.join(root, 'uz_Cyrl.json'), 'utf8'));
const remaining = Object.entries(cyrl).filter(
  ([k, v]) => isScopedKey(k) && LATIN.test(v),
);
if (remaining.length) {
  console.warn(`\nDiqqat: ${remaining.length} scoped kalitda hali lotin qoldi:`);
  remaining.slice(0, 15).forEach(([k, v]) => console.warn(`  ${k}: ${v}`));
} else {
  console.log('\nScoped uz_Cyrl kalitlarida lotin qolmadi.');
}
