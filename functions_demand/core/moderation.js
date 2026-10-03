'use strict';

/**
 * 13.2.13 — MODERATSIYA.
 *
 * Konsepsiya «matn va rasm uchun avtomatik filtr» deb yozgan. Rasm
 * filtri uchun loyihada vendor YO'Q (Vision API ulanmagan), shuning
 * uchun VA'DA BERILMAYDI: 1-versiyada faqat matn filtri + qo'lda
 * moderator navbati. Rasm moderatsiyasi P3 (8-bo'lim).
 *
 * Taqiqlangan so'zlar ro'yxati KODDA EMAS, `module_config/moderation`da:
 * ro'yxatni to'ldirish moderatorning kundalik ishi, har safar deploy
 * qilish mumkin emas.
 *
 * Ikki daraja:
 *   `blocked` — talab yaratilmaydi (aniq taqiqlangan tovar)
 *   `review`  — talab yaratiladi, lekin moderator navbatiga tushadi
 */

const { canonText } = require('./text');

const CONFIG_DOC = 'moderation';

/**
 * Standart ro'yxat — konfig hujjati bo'lmasa ham minimal himoya ishlaydi.
 *
 * ATAYLAB QISQA va aniq: keng ro'yxat yolg'on pozitiv beradi va
 * foydalanuvchini bekorga to'xtatadi. Kengaytirish moderatorning ishi.
 */
const DEFAULT_BLOCKED = [
  // Qurol va o'q-dori
  // DIQQAT: kirill shakli alohida yozilmaydi — `canonText` hamma narsani
  // lotinga keltiradi, shuning uchun «қурол» ham «qurol» ga tushadi.
  'qurol', 'pistolet', 'avtomat kalashnikov', 'patron', 'granata',
  // Narkotik
  'narkotik', 'geroin', 'kokain', 'tramadol', 'nasvay sotaman',
  // Hujjat soxtalashtirish
  'soxta pasport', 'soxta diplom', 'diplom sotaman', 'prava sotaman',
  // Odam savdosi va shunga yaqin
  'buyrak sotaman', 'organ sotaman',
];

const DEFAULT_REVIEW = [
  'dori', 'tabletka', 'spirt', 'aroq', 'sigaret', 'tamaki',
  'valyuta', 'dollar sotaman', 'kredit beraman', 'qarz beraman',
];

/**
 * Moderatsiya tekshiruvi.
 *
 * @param {object} db
 * @returns {{check: Function}}
 */
function makeModeration(db) {
  let cache = null;
  let cacheAt = 0;

  async function lists(config) {
    const now = Date.now();
    if (cache && now - cacheAt < 60000) return cache;

    let blocked = DEFAULT_BLOCKED;
    let review = DEFAULT_REVIEW;
    try {
      const snap = await db.collection('module_config').doc(CONFIG_DOC).get();
      if (snap.exists) {
        const d = snap.data() || {};
        if (Array.isArray(d.blocked) && d.blocked.length) blocked = d.blocked;
        if (Array.isArray(d.review) && d.review.length) review = d.review;
      }
    } catch (e) {
      // Ro'yxat o'qilmasa standart bilan davom etamiz: moderatsiyasiz
      // ishlashdan ko'ra minimal himoya yaxshiroq.
      console.error(`moderation ro'yxati o'qilmadi: ${e.message}`);
    }
    cache = {
      blocked: blocked.map((s) => canonText(s)).filter(Boolean),
      review: review.map((s) => canonText(s)).filter(Boolean),
    };
    cacheAt = now;
    return cache;
  }

  return {
    /**
     * @returns {Promise<{blocked: boolean, review: boolean, matched: string[]}>}
     */
    async check(text, config) {
      const hay = canonText(text);
      if (!hay) return { blocked: false, review: false, matched: [] };

      const l = await lists(config);
      const matchedBlocked = l.blocked.filter((w) => containsWord(hay, w));
      if (matchedBlocked.length) {
        return { blocked: true, review: true, matched: matchedBlocked };
      }
      const matchedReview = l.review.filter((w) => containsWord(hay, w));
      return {
        blocked: false,
        review: matchedReview.length > 0,
        matched: matchedReview,
      };
    },

    /** Test va admin panel uchun. */
    clearCache() { cache = null; cacheAt = 0; },
  };
}

/**
 * So'z chegarasi bilan tekshirish.
 *
 * Oddiy `includes` YARAMAYDI: «dori» so'zi «koridor» ichida ham bor va
 * «koridor tozalash» talabi bekorga to'xtab qolardi. Shuning uchun
 * ibora bo'lsa `includes`, yakka so'z bo'lsa SO'Z sifatida.
 */
function containsWord(haystack, needle) {
  if (!needle) return false;
  if (needle.includes(' ')) return haystack.includes(needle);
  return haystack.split(' ').some((w) => w === needle);
}

module.exports = {
  CONFIG_DOC,
  DEFAULT_BLOCKED,
  DEFAULT_REVIEW,
  makeModeration,
  containsWord,
};
