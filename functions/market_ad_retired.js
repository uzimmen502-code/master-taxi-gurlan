'use strict';

/**
 * F-1 (takrorlanishlar auditi 2026-11-28, ega 2026-11-28): eski «Аралаш» e'lonlari
 * (`ads`, type `cheap_product`) — YANGI e'lon va QAYTA JOYLASHTIRISH yopiq.
 * Mahsulot «＋» orqali (`tv_shop_items`) qo'shiladi.
 *
 * Mavjud e'lonlar tegilmaydi (migration yo'q): ega yashira (`inactive`) va o'chira oladi,
 * tahrir avvalgidek moderatsiyadan o'tadi, lekin muddat (`expiresAt`) UZAYTIRILMAYDI —
 * mavjud 30 kunlik TTL (`expirePendingTrips` / `marketListingsExpirySweep`) bilan tugaydi.
 *
 * Yagona manba: `submitMarketAd` (index.js), `onAdUpdate` (index.js),
 * `renewMarketListing` (market_moderation.js) shu modulni ishlatadi.
 */

const MARKET_AD_RETIRED = 'MARKET_AD_RETIRED';

/** `true` — eski bozor e'lonlari yopiq. Qaytarish (ega qarori bilan) — shu bitta joy. */
const MARKET_ADS_RETIRED = true;

const MARKET_AD_RETIRED_MESSAGES = Object.freeze({
  uz_Cyrl: 'Бу бўлимга эълон бериш ёпилди. Маҳсулотни «＋» орқали қўшинг.',
  uz_Latn: "Bu bölimga e'lon beriş yopildi. Mahsulotni «＋» orqali qöşing.",
  ru: 'Подача объявлений в этот раздел закрыта. Добавьте товар через «＋».',
});

/** `failed-precondition` MARKET_AD_RETIRED (3 til). `HttpsError` — `functions.https.HttpsError`. */
function marketAdRetiredError(HttpsError, extra) {
  return new HttpsError('failed-precondition', MARKET_AD_RETIRED_MESSAGES.uz_Cyrl, {
    code: MARKET_AD_RETIRED,
    ...(extra || {}),
    messages: { ...MARKET_AD_RETIRED_MESSAGES },
  });
}

module.exports = {
  MARKET_AD_RETIRED,
  MARKET_ADS_RETIRED,
  MARKET_AD_RETIRED_MESSAGES,
  marketAdRetiredError,
};
