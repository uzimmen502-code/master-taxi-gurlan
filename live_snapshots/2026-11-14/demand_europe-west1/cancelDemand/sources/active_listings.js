'use strict';

/**
 * NOMZOD MANBASI 2 — MAVJUD `ads` E'LONLARI (COLD START).
 *
 * MUAMMO: birinchi kunda `provider_capabilities` BO'SH. Hech kim hali
 * «men santexnikman» deb belgilamagan, demak pilot ishga tushgan zahoti
 * har bir talab `no_providers` bo'lib qaytadi va foydalanuvchi ikkinchi
 * marta urinmaydi. Konsepsiyada bu muammo umuman ko'rilmagan.
 *
 * YECHIM (2026-10-03 auditida topildi): `ads` kolleksiyasida ALLAQACHON
 * `type: 'service'` bo'lgan e'lonlar bor — odamlar o'zini usta sifatida
 * e'lon qilgan. Jami 124 e'lon, shundan 21 tasi xizmat, 75 tasi Xorazmda.
 *
 * Haqiqiy matnlar (namuna): «электрикман, от А до Я», «pol patalok
 * ustaman», «usyaman», «maslahat hizmati». Ya'ni erkin matn, aralash
 * yozuv, sheva. Shuning uchun kategoriya `core/keywords.js` orqali
 * chiqariladi va MOS KELMASA e'lon o'tkazib yuboriladi.
 *
 * MUHIM — STRANGLER PATTERN: bu manba `ads`ni faqat O'QIYDI. Bironta
 * maydon yozilmaydi, eski ekranlar ishlashda davom etadi.
 *
 * MUHIM — SPAM EMAS: e'lon muallifi hech narsaga rozilik bermagan.
 * Shuning uchun u `demand_matches`ga PUSH OLMAYDIGAN nomzod sifatida
 * tushadi (`consentGiven: false`): talabni inbox'da ko'radi, lekin
 * telefoni jiringlamaydi. Konsepsiyadagi «o'tmishdagi faoliyat — rozilik
 * orqali» qoidasi ayni shu.
 */

const { toCanonicalId } = require('../core/ids');
const { providerCategoriesFromText } = require('../core/keywords');

const COLLECTION = 'ads';

/** `ads.type` -> yadro moduli. */
const AD_TYPE_TO_MODULE = {
  service: 'service',
  sell: 'sell',
  cheap_product: 'market',
  work: null, // ish qidirish — talab emas, nomzod ham emas
  ad: null,
};

/**
 * Mavjud e'lonlardan nomzod topadi.
 *
 * @param {object} db
 * @param {object} demand
 * @param {object} config
 * @param {object} keywordIndex `core/keywords.buildIndex()` natijasi
 */
async function fetchCandidates(db, demand, config, keywordIndex) {
  const adType = moduleToAdType(demand.module);
  if (!adType) return [];

  const loc = demand.location || {};
  if (!loc.regionId) return [];

  // `status: 'active'` — muddati o'tgan yoki o'chirilgan e'lon hisobga
  // olinmaydi. `completed` e'lonlar ham olinadi: usta ishni tugatgan
  // bo'lishi mumkin, lekin usta bo'lib qolaveradi. Shuning uchun
  // `status` bo'yicha filtr YO'Q, faqat muddat bo'yicha.
  const snap = await db.collection(COLLECTION)
    .where('type', '==', adType)
    .where('regionId', '==', loc.regionId)
    .limit(config.maxCandidates || 500)
    .get();

  const byProvider = new Map();

  for (const doc of snap.docs) {
    const d = doc.data() || {};
    const providerId = toCanonicalId(d.authorPhone || d.phone || d.ownerId || '');
    if (!providerId) continue;
    // Talab egasining o'zi nomzod bo'lmaydi.
    if (providerId === demand.ownerId) continue;

    const text = [d.title, d.text, d.description].filter(Boolean).join(' ');
    const cats = providerCategoriesFromText(text, keywordIndex);

    // Kategoriya chiqmasa — TAXMIN QILMAYMIZ, o'tkazib yuboramiz.
    // «usyaman» yoki «нон конвейри ишлашни бошлийди» kabi matnlardan
    // hech qanday ishonchli xulosa chiqmaydi.
    if (cats.length === 0) continue;

    if (demand.categoryId && !cats.includes(demand.categoryId)) {
      const group = keywordIndex.groupOf.get(demand.categoryId);
      const sameGroup = cats.some((c) => keywordIndex.groupOf.get(c) === group);
      if (!sameGroup) continue;
    }

    const prev = byProvider.get(providerId);
    if (prev) {
      // Bir odamning bir nechta e'loni — kategoriyalarni birlashtiramiz.
      for (const c of cats) if (!prev.categoryIds.includes(c)) prev.categoryIds.push(c);
      continue;
    }

    byProvider.set(providerId, {
      providerId,
      source: 'active_listings',
      categoryIds: cats,
      categoryGroups: cats
        .map((c) => keywordIndex.groupOf.get(c))
        .filter((g, i, a) => g && a.indexOf(g) === i),
      regionIds: [d.regionId].filter(Boolean),
      districtIds: [d.districtId].filter(Boolean),
      /**
       * ROZILIK YO'Q — bu nomzod push OLMAYDI.
       *
       * E'lon muallifi «menga talablar yuboringlar» demagan. Shuning
       * uchun u talabni inbox'da ko'radi va rozilik so'rovini oladi
       * («Siz elektrik xizmati e'lon qilgansiz. Shu yo'nalishda
       * talablar olishni xohlaysizmi?»), lekin bu talab uchun telefoni
       * jiringlamaydi.
       */
      consentGiven: false,
      sourceAdId: doc.id,
      sourceAdText: text.slice(0, 200),
      raw: { authorName: d.authorName || '' },
    });
  }

  return Array.from(byProvider.values());
}

/** Yadro moduli -> `ads.type`. */
function moduleToAdType(module) {
  for (const [adType, mod] of Object.entries(AD_TYPE_TO_MODULE)) {
    if (mod === module) return adType;
  }
  return null;
}

module.exports = { COLLECTION, AD_TYPE_TO_MODULE, fetchCandidates, moduleToAdType };
