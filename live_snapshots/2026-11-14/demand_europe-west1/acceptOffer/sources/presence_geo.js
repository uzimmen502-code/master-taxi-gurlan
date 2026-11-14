'use strict';

/**
 * NOMZOD MANBASI 3 — `provider_presence`.
 *
 * «Hozir shu yerda, onlayn va ishga tayyor» taklifchilar. `capabilities`
 * «men umuman shu ishni qilaman» desa, bu manba «men AYNAN HOZIR shu
 * yerdaman» deydi — ya'ni `dispatch` rejimi (kuryer, taksi) uchun asosiy
 * manba.
 *
 * Qoida va indeks allaqachon bor edi (`firestore.rules` →
 * `provider_presence/{uid}`, `firestore.indexes.json` → `isOnline + module
 * + geohash`), lekin yozuvchi ham, o'quvchi ham yo'q edi. Bu fayl —
 * o'quvchi tomoni.
 *
 * ── Nega `in` emas, DIAPAZON so'rovi ────────────────────────────────────
 * `geo.neighborPrefixes()` izohida «9 ta prefiksni `in` ga joylash
 * mumkin» deyilgan. Bu faqat SAQLANGAN geohash aynan so'rov aniqligida
 * bo'lsa ishlaydi. Aniqlik esa radiusdan kelib chiqadi
 * (`precisionForRadiusKm`), radius esa konfig — ya'ni `in` saqlangan
 * aniqlikni konfigga bog'lab qo'yadi va `searchRadiusKm` o'zgarishi
 * BARCHA presence hujjatlarini yaroqsiz qiladi.
 *
 * Shuning uchun klient geohash'ni to'liq aniqlikda yozadi, bu yerda esa
 * har bir prefiks uchun `>= prefix && < prefix~` diapazoni so'raladi
 * (`geo.prefixRange`). Narxi: bitta so'rov o'rniga 9 ta. Evaziga radius
 * istalgan vaqtda o'zgaradi va hech narsa qayta yozilmaydi.
 *
 * ── Nega `isOnline` ga ishonib bo'lmaydi ────────────────────────────────
 * Kuryer ilovani yopsa yoki tarmoq uzilsa, `isOnline: true` hujjatda
 * qolib ketadi. Sweep uni keyinroq o'chiradi, lekin oradagi vaqtda u
 * nomzod bo'lib chiqaveradi. Shuning uchun `updatedAt` ham tekshiriladi:
 * `config.maxLocationAgeSec` (standart 120 s) dan eski bo'lsa — chiqarib
 * tashlanadi. Bu qiymat konfigda ALLAQACHON bor edi, yangisi
 * kiritilmadi.
 */

const geo = require('../geo/geo');
const { toMillis } = require('../core/state_machine');
const { toCanonicalId } = require('../core/ids');

const COLLECTION = 'provider_presence';

/**
 * Koordinata uchun xavfsiz son.
 *
 * `Number(null)` va `Number('')` — bu NOL, NaN emas. Ya'ni to'g'ridan-to'g'ri
 * `Number(d.lat)` yozilsa, koordinatasi yo'q hujjat «0,0 nuqtada» deb
 * qaytariladi va kuryer Afrika qirg'og'iga ko'chadi. Test shuni ushladi.
 */
function coord(v) {
  if (v === null || v === undefined || v === '') return Number.NaN;
  return Number(v);
}

/**
 * Talab nuqtasi atrofidagi onlayn taklifchilar.
 *
 * @param {object} db Firestore
 * @param {object} demand
 * @param {object} config module_config
 * @returns {Promise<Array<object>>} nomzodlar
 */
async function fetchCandidates(db, demand, config) {
  const loc = (demand && demand.location) || {};
  const lat = coord(loc.lat);
  const lng = coord(loc.lng);
  // Koordinatasiz talab uchun bu manba ishlamaydi — `capabilities` qoladi.
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return [];

  const radiusKm = Number(config && config.searchRadiusKm) || 15;
  const maxAgeSec = Number(config && config.maxLocationAgeSec) || 120;
  const limit = Number(config && config.maxCandidates) || 500;

  const precision = geo.precisionForRadiusKm(radiusKm);
  const prefixes = geo.neighborPrefixes(lat, lng, precision);
  const cutoffMs = Date.now() - maxAgeSec * 1000;

  const out = [];
  const seen = new Set();

  for (const prefix of prefixes) {
    if (out.length >= limit) break;
    const { start, end } = geo.prefixRange(prefix);
    const snap = await db.collection(COLLECTION)
      .where('isOnline', '==', true)
      .where('module', '==', demand.module)
      .where('geohash', '>=', start)
      .where('geohash', '<', end)
      .limit(limit)
      .get();

    for (const doc of snap.docs) {
      if (out.length >= limit) break;
      const d = doc.data() || {};
      /**
       * TAKLIFCHI KIMLIGI — FAQAT HUJJAT KALITIDAN (18-qoida).
       *
       * Hujjat ichidagi `providerId` MAYDONI klient yozadi, va qoida
       * (`provider_presence/{uid}`) uning QIYMATINI tekshirmaydi — ya'ni
       * kuryer o'z hujjatiga boshqa odamning ID'sini yozib qo'yishi
       * mumkin edi. Avval shu maydon birinchi o'rinda ishlatilgandi
       * (`d.providerId || doc.id`), ya'ni matching, push va tayinlash
       * BOSHQA odamga ketardi.
       *
       * Kalit esa `isOwner(uid)` bilan qulflangan — uni soxtalashtirish
       * uchun o'sha raqamning SMS'ini olish kerak.
       *
       * Kanon bo'lmagan kalit umuman o'tkazib yuboriladi: `matchKey()`
       * keyinroq baribir xato tashlardi (`core/ids.js:99`).
       */
      const providerId = toCanonicalId(doc.id);
      if (!providerId || seen.has(providerId)) continue;

      // Eskirgan GPS — ilova yopilgan, sweep hali yetib bormagan.
      const ms = toMillis(d.updatedAt);
      if (ms && ms < cutoffMs) continue;

      const pLat = coord(d.lat);
      const pLng = coord(d.lng);
      if (!Number.isFinite(pLat) || !Number.isFinite(pLng)) continue;

      seen.add(providerId);
      out.push({
        providerId,
        source: 'presence',
        /**
         * `metricsFor()` shu maydondan masofa va ETA hisoblaydi
         * (`matching/orchestrator.js:147`).
         */
        presence: {
          lat: pLat,
          lng: pLng,
          vehicle: d.vehicle || null,
          updatedAt: d.updatedAt || null,
        },
        vehicle: d.vehicle || null,
        regionIds: d.regionId ? [d.regionId] : [],
        districtIds: d.districtId ? [d.districtId] : [],
        /**
         * ROZILIK BOR: odam «onlayn» tugmasini O'ZI bosgan, ya'ni ayni
         * hozir ish olishga tayyorligini bildirgan. `active_listings`dan
         * farqi shu — u yerda hech kim hech narsaga rozilik bermagan.
         */
        consentGiven: true,
        raw: d,
      });
    }
  }

  return out;
}

/**
 * Bitta taklifchining joriy holati (teskari matching va admin uchun).
 *
 * Kalit kanon shaklda bo'ladi (yozuvchi shunday yozadi), shuning uchun
 * kiruvchi qiymat ham kanonga keltiriladi — 9 xonali shakl bilan
 * chaqirilsa ham hujjat topiladi.
 */
async function fetchForProvider(db, providerId) {
  const id = toCanonicalId(providerId);
  // Noto'g'ri ID uchun Firestore'ga umuman borilmaydi.
  if (!id) return null;
  const snap = await db.collection(COLLECTION).doc(id).get();
  if (!snap.exists) return null;
  return { id: snap.id, ...(snap.data() || {}) };
}

module.exports = { COLLECTION, coord, fetchCandidates, fetchForProvider };
