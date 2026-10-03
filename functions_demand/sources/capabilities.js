'use strict';

/**
 * NOMZOD MANBASI 1 — `provider_capabilities`.
 *
 * Taklifchining O'ZI belgilagan yo'nalishlar: «men santexnikman»,
 * «Xorazm bo'ylab ishlayman», «ulgurji sotaman», «posilka olaman».
 *
 * Bu ENG ISHONCHLI manba (odam o'zi roziligini bergan), lekin birinchi
 * kunda BO'SH bo'ladi — hech kim hali hech narsa belgilamagan. Shuning
 * uchun `active_listings.js` (cold start) bilan birga ishlaydi.
 */

const { candidateIdsFor } = require('../core/ids');

const COLLECTION = 'provider_capabilities';

/**
 * Modul + hudud + kategoriya bo'yicha taklifchilarni topadi.
 *
 * Firestore cheklovi: `array-contains` bitta so'rovda bittadan ortiq
 * bo'lmaydi, shuning uchun kategoriya bo'yicha `array-contains`, hudud
 * bo'yicha `in` — ikkisi birga ishlaydi.
 *
 * @param {object} db Firestore
 * @param {object} demand
 * @param {object} config module_config
 * @returns {Promise<Array<object>>} nomzodlar
 */
async function fetchCandidates(db, demand, config) {
  const regions = regionKeysFor(demand);
  if (regions.length === 0) return [];

  let q = db.collection(COLLECTION)
    .where('module', '==', demand.module)
    .where('active', '==', true)
    .where('regionIds', 'array-contains-any', regions.slice(0, 10));

  const snap = await q.limit(config.maxCandidates || 500).get();

  const out = [];
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    // Kategoriya filtri SERVERDA, so'rovda emas: `array-contains-any`
    // allaqachon hudud uchun ishlatilgan va Firestore ikkinchisini
    // ruxsat bermaydi. Nomzodlar soni kichik (bitta tuman, bitta modul),
    // shuning uchun bu arzon.
    if (demand.categoryId) {
      const cats = Array.isArray(d.categoryIds) ? d.categoryIds : [];
      const groups = Array.isArray(d.categoryGroups) ? d.categoryGroups : [];
      const catMatch = cats.includes(demand.categoryId);
      const groupMatch = demand.categoryGroup && groups.includes(demand.categoryGroup);
      if (!catMatch && !groupMatch && cats.length > 0) continue;
    }
    out.push({
      providerId: d.providerId || String(doc.id).split('_')[0],
      source: 'capabilities',
      categoryIds: d.categoryIds || [],
      categoryGroups: d.categoryGroups || [],
      regionIds: d.regionIds || [],
      districtIds: d.districtIds || [],
      vehicle: d.vehicle || null,
      wholesale: d.wholesale === true,
      minOrderQty: Number(d.minOrderQty) || 0,
      acceptsParcels: d.acceptsParcels === true,
      pushOptOut: d.pushOptOut === true,
      digestOnly: d.digestOnly === true,
      /**
       * ROZILIK BOR.
       *
       * Bu manbaga tushgan odam `provider_capabilities`ni O'ZI to'ldirgan
       * («men santexnikman, Urganchda ishlayman») — ya'ni talablar olishga
       * aniq rozilik bergan. Shuning uchun u push OLADI.
       *
       * Taqqoslash uchun: `active_listings` manbasidagi odam hech narsaga
       * rozilik bermagan (`consentGiven: false`) va push olmaydi.
       */
      consentGiven: true,
      raw: d,
    });
  }
  return out;
}

/** Talab uchun hudud kalitlari — tumandan viloyatgacha. */
function regionKeysFor(demand) {
  const loc = demand.location || {};
  const keys = [];
  if (loc.districtId) keys.push(loc.districtId);
  if (loc.regionId) keys.push(loc.regionId);
  // Shaharlararo: manzil hududi ham mos keladi.
  const dest = demand.destination || {};
  if (dest.districtId && !keys.includes(dest.districtId)) keys.push(dest.districtId);
  if (dest.regionId && !keys.includes(dest.regionId)) keys.push(dest.regionId);
  return keys;
}

/**
 * Bitta taklifchining imkoniyatlari (teskari matching uchun).
 *
 * 9/12 xonali ikki shakl sababli ikkala ID bo'yicha ham qaraladi
 * (eski hujjatlar migratsiya qilinmaydi — strangler pattern).
 */
async function fetchForProvider(db, providerId, module) {
  const ids = candidateIdsFor(providerId);
  for (const id of ids) {
    const snap = await db.collection(COLLECTION).doc(`${id}_${module}`).get();
    if (snap.exists) return { id: snap.id, ...(snap.data() || {}) };
  }
  return null;
}

module.exports = { COLLECTION, fetchCandidates, fetchForProvider, regionKeysFor };
