'use strict';

/**
 * KALIT SO'Z MOSLASHTIRGICH — IKKI JOYDA ISHLATILADI.
 *
 * Konsepsiyada Intent Router (foydalanuvchi matnini tushunish) va nomzod
 * manbalari (taklifchini topish) ikki alohida mexanizm sifatida yozilgan.
 * Lekin ularning ishi AYNI BIR XIL: erkin matndan kategoriya chiqarish.
 *
 *   Foydalanuvchi:  «кран оқяпти»           -> santexnik
 *   E'lon (`ads`):  «электрикман, от А до Я» -> elektrik
 *
 * Shuning uchun bitta modul. Natija: luhat bir joyda tahrirlanadi, ikki
 * tomon hech qachon ajralib ketmaydi.
 *
 * NEGA BU MUHIM (production ma'lumoti, 2026-10-03 auditi):
 * `ads` kolleksiyasida `type: 'service'` bo'lgan 21 e'lon bor, 75 e'lon
 * Xorazmda. Ularning matni haqiqatda shunday:
 *   «электрикман, от А до Я», «pol patalok ustaman», «usyaman»,
 *   «maslahat hizmati», «нон конвейри ишлашни бошлийди худо халаса»
 * Ya'ni: aralash yozuv, sheva, xato terilgan so'zlar, ba'zan umuman
 * tushunarsiz. Shuning uchun moslashtirgich:
 *   - ikkala yozuvda ishlaydi (kirill/lotin),
 *   - prefiks bo'yicha moslashadi («электрикман» -> «электрик»),
 *   - MOS KELMASA JIM TURADI (noto'g'ri taxmin qilmaydi).
 *
 * Oxirgi nuqta eng muhimi: «usyaman» hech qanday kategoriyaga tushmaydi va
 * bu TO'G'RI xatti-harakat — foydalanuvchi kategoriyani o'zi tanlaydi.
 * Konsepsiya ham shunday deydi: «AVA adashsa, foydalanuvchi kartochkani
 * o'tkazib, oddiy natijalarni ko'radi.»
 */

const { canonText, variants } = require('./text');

/** Prefiks mosligi uchun minimal kalit so'z uzunligi. */
const MIN_PREFIX_LEN = 4;

/**
 * Taksonomiyadan tez qidiriladigan indeks quradi.
 *
 * Bir marta quriladi va keshlanadi: har chaqiruvda 40 kategoriya x 655
 * sinonim ustida aylanish qimmat.
 *
 * @param {{categories: Array, ambiguous?: Array}} taxonomy
 */
function buildIndex(taxonomy) {
  /** @type {Map<string, Set<string>>} kanon kalit so'z -> kategoriyalar */
  const byKeyword = new Map();
  /** @type {Map<string, string>} kategoriya -> guruh */
  const groupOf = new Map();
  /** @type {Map<string, object>} kategoriya -> to'liq yozuv */
  const categoryById = new Map();

  for (const cat of (taxonomy.categories || [])) {
    categoryById.set(cat.id, cat);
    groupOf.set(cat.id, cat.group || '');

    // Kategoriya nomining o'zi ham kalit so'z.
    const phrases = [];
    for (const lang of ['uz_Cyrl', 'uz_Latn', 'ru']) {
      if (cat.names && cat.names[lang]) phrases.push(cat.names[lang]);
      if (cat.syn && Array.isArray(cat.syn[lang])) phrases.push(...cat.syn[lang]);
    }

    for (const phrase of phrases) {
      for (const v of variants(phrase)) {
        const key = canonText(v);
        if (key.length < 2) continue;
        if (!byKeyword.has(key)) byKeyword.set(key, new Set());
        byKeyword.get(key).add(cat.id);
      }
    }
  }

  /** @type {Map<string, string[]>} kanon kalit so'z -> ko'p ma'noli kategoriyalar */
  const ambiguous = new Map();
  for (const entry of (taxonomy.ambiguous || [])) {
    for (const kw of (entry.keywords || [])) {
      for (const v of variants(kw)) {
        ambiguous.set(canonText(v), entry.categories || []);
      }
    }
  }

  return { byKeyword, ambiguous, groupOf, categoryById };
}

/**
 * Matndan kategoriyalarni topadi.
 *
 * @returns {{
 *   categoryId: string|null,
 *   candidates: Array<{categoryId: string, score: number, matched: string[]}>,
 *   needsChoice: boolean,
 *   matchedKeywords: string[]
 * }}
 *
 * `needsChoice: true` -> UI ikki variantni ko'rsatadi, O'ZI TANLAMAYDI.
 */
function matchCategories(text, index, opts = {}) {
  const limit = opts.limit || 3;
  const haystack = canonText(text);
  if (!haystack) {
    return { categoryId: null, candidates: [], needsChoice: false, matchedKeywords: [] };
  }
  const words = haystack.split(' ');

  /** @type {Map<string, {score: number, matched: Set<string>}>} */
  const hits = new Map();
  const matchedKeywords = new Set();
  let ambiguousHit = null;

  for (const [keyword, cats] of index.byKeyword) {
    let weight = 0;

    if (keyword.includes(' ')) {
      // Ko'p so'zli ibora: to'liq mos kelishi kerak («сув оқяпти»).
      //
      // Vazni x3 — ataylab yuqori. Sabab (test topgan haqiqiy holat):
      // «уй тозалаш керак» da «уй тозалаш» (ibora) va «тозалаш» (yakka
      // so'z, boshqa kategoriyaning sinonimi) ikkisi ham mos keladi.
      // Ibora ANIQROQ ma'lumot, shuning uchun u yakka so'zni qat'iy
      // ortda qoldirishi kerak, aks holda tanlov so'ralib foydalanuvchi
      // bekorga bezovta qilinadi.
      //
      // SO'Z CHEGARASI SHART — oddiy `includes` YARAMAYDI.
      // Test topgan haqiqiy xato: «kuryer kerak» ichida «yer kerak»
      // (ko'chmas mulk iborasi) substring sifatida bor edi, shuning
      // uchun «Курьер керак» so'rovi KO'CHMAS MULK deb tanilardi.
      if (containsPhrase(haystack, keyword)) weight = keyword.length * 3;
    } else {
      for (const w of words) {
        if (w === keyword) { weight = Math.max(weight, keyword.length * 2); continue; }
        // Prefiks: «электрикман» -> «электрик». Faqat yetarlicha uzun
        // kalit so'zlar uchun, aks holda «ток» -> «токайгача» kabi
        // tasodifiy mosliklar paydo bo'ladi.
        if (keyword.length >= MIN_PREFIX_LEN && w.startsWith(keyword)) {
          weight = Math.max(weight, keyword.length);
        }
      }
    }

    if (weight <= 0) continue;
    matchedKeywords.add(keyword);
    if (index.ambiguous.has(keyword)) ambiguousHit = keyword;

    for (const cat of cats) {
      if (!hits.has(cat)) hits.set(cat, { score: 0, matched: new Set() });
      const h = hits.get(cat);
      h.score += weight;
      h.matched.add(keyword);
    }
  }

  const candidates = Array.from(hits.entries())
    .map(([categoryId, h]) => ({
      categoryId,
      score: Number(h.score.toFixed(2)),
      matched: Array.from(h.matched).sort(),
    }))
    .sort((a, b) => (b.score - a.score)
      || a.categoryId.localeCompare(b.categoryId))
    .slice(0, limit);

  if (candidates.length === 0) {
    return {
      categoryId: null, candidates: [], needsChoice: false,
      matchedKeywords: Array.from(matchedKeywords).sort(),
    };
  }

  // Ko'p ma'noli kalit so'z ikkita kategoriyaga teng tushgan bo'lsa,
  // O'ZIMIZ TANLAMAYMIZ. Masalan «котёл» -> gaz_ustasi yoki isitish_tizimi.
  const top = candidates[0];
  const second = candidates[1];
  // Chegara TOR (10%): keng chegara har kichik farqda tanlov so'rab,
  // foydalanuvchini bezovta qilardi. Tanlov so'rash qimmat — faqat
  // haqiqatan ajratib bo'lmaydigan holatda.
  const tie = Boolean(second && (top.score - second.score) < top.score * 0.1);
  const needsChoice = Boolean(ambiguousHit && tie);

  return {
    categoryId: needsChoice ? null : top.categoryId,
    candidates,
    needsChoice,
    matchedKeywords: Array.from(matchedKeywords).sort(),
  };
}

/**
 * Taklifchining e'lon matnidan u xizmat ko'rsatadigan kategoriyalar.
 *
 * `matchCategories`dan farqi: bu yerda BIR NECHTA kategoriya normal holat
 * («pol patalok ustaman» -> gipsokarton + shpatlyovka_boyoq), chunki usta
 * bir vaqtda bir nechta ishni qiladi. Shuning uchun `needsChoice` yo'q,
 * chegaradan o'tgan hammasi qaytariladi.
 *
 * MUHIM ASIMMETRIYA — UMUMIY KALITLAR BU YERDA ISHLATILMAYDI.
 *
 * Taksonomiyada `generic` ro'yxati bor («уста», «ремонт», «хизмат») va
 * u Intent Router uchun: foydalanuvchi «Уста керак» deb yozsa, xizmat
 * kartochkasi ko'rsatilishi SHART (ega qarori, 2026-10-03 — asosiy
 * kirish nuqtasi qidiruv maydoni).
 *
 * Lekin TESKARI yo'nalishda bu halokatli bo'lardi: `ads`da «ustaman»
 * deb yozgan odam 40 ta kategoriyaning HAMMASIGA tayinlanib, har bir
 * xizmat so'rovi uchun nomzod bo'lib qolardi — ya'ni aniq spam.
 *
 * Himoya: `buildIndex` indeksni FAQAT `taxonomy.categories` dan quradi,
 * `taxonomy.generic` ga umuman qaramaydi. `test/keywords.test.js` buni
 * aniq qulflaydi.
 */
function providerCategoriesFromText(text, index, opts = {}) {
  const minScore = opts.minScore || 6;
  const r = matchCategories(text, index, { limit: 5 });
  return r.candidates
    .filter((c) => c.score >= minScore)
    .map((c) => c.categoryId);
}

/**
 * Ibora SO'Z CHEGARASI bilan topilganmi.
 *
 * Oddiy `includes` yaramaydi: «kuryer kerak» ichida «yer kerak» bor
 * (substring), ya'ni «Курьер керак» so'rovi ko'chmas mulk deb
 * tanilardi. Bo'shliq bilan o'rab tekshirish buni yopadi.
 */
function containsPhrase(haystack, phrase) {
  return ` ${haystack} `.includes(` ${phrase} `);
}

module.exports = {
  MIN_PREFIX_LEN,
  buildIndex,
  matchCategories,
  providerCategoriesFromText,
  containsPhrase,
};
