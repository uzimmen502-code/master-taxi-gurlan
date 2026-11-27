'use strict';

/**
 * NARX QOIDALARI — AVA DO'KONI (`platform_products`) va ULGURJI pog'ona yordamchilari.
 *
 * AVA DO'KONI — YAGONA NARX (ega 2026-11-28): «narx pog'onalari biznes qoida sifatida olib
 * tashlangan». Hisoblangan pog'onalar (2026-10-06 qarori: 1–9 dona +5 %, 50+ −5 %, eski tovarlar
 * uchun `DERIVED_TIERS_CUTOFF_MS`) O'CHIRILDI. Buyurtma narxi = tovarning `price` maydoni,
 * miqdordan qat'i nazar (`platformUnitPrice`). `platform_products.priceTiers` ham E'TIBORSIZ:
 * prod'da (2026-11-28, faqat o'qish) 59 tovarning birortasida `priceTiers` yo'q.
 *
 * VERSIYA (9-qoida): buyurtmaga SERVER yozadi — `SERVER_PRICING_VERSION` (3 = yagona narx).
 * Klient `pricingVersion` e'tiborsiz (18-qoida; T-3). Eski buyurtmalardagi 1/2 o'zgarmaydi.
 *   1 — eski yagona narx (≤1.0.32 ilova), 2 — hisoblangan/admin pog'onalari (2026-10-06…11-28),
 *   3 — yagona narx, pog'onasiz (ega 2026-11-28).
 *
 * ULGURJI (`wholesale_products` qadoqlari, boshqa domen): sotuvchi qo'ygan ANIQ pog'onalar —
 * `cleanTiers` + `tierUnitPrice` / `unitPriceForQty` (wholesale_orders.js, price_search.js).
 * Ular hisoblanmaydi (derived yo'q) va AVA do'koni narxiga ta'sir qilmaydi.
 *
 * PUL — BUTUN SO'M (8-qoida), faqat butun son arifmetikasi.
 *
 * Klient ko'zgusi `lib/models/price_tier.dart` / `platform_product.dart` hali hisoblangan
 * pog'onalarni ko'rsatadi — klient tomonda olib tashlanishi kerak (server bu qoidani qo'llamaydi).
 */

const PRICING_VERSION_LEGACY = 1;
const PRICING_VERSION_TIERED = 2;
/** Yagona narx, pog'onasiz (ega 2026-11-28). */
const PRICING_VERSION_SINGLE = 3;
/** Server AVA do'koni buyurtma/oldindan hisob yo'li ishlatadigan YAGONA versiya. */
const SERVER_PRICING_VERSION = PRICING_VERSION_SINGLE;

/** AVA do'koni: bir dona narxi = `price` (butun so'm), miqdor va `priceTiers` e'tiborsiz. */
function platformUnitPrice(product) {
  const p = Math.trunc(Number((product || {}).price || 0));
  return Number.isFinite(p) ? p : 0;
}

/** Firestore `priceTiers` (ulgurji) — to'g'ri yozuvlar, `minQty` bo'yicha o'sish tartibida. */
function cleanTiers(raw) {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((t) => ({
      minQty: Math.trunc(Number((t || {}).minQty)),
      price: Math.trunc(Number((t || {}).price)),
    }))
    .filter((t) => Number.isInteger(t.minQty) && t.minQty >= 1
      && Number.isInteger(t.price) && t.price > 0)
    .sort((a, b) => a.minQty - b.minQty);
}

/** Aniq pog'onalardan bir dona narxi: [qty] dan kichik/teng eng yuqori; qty birinchisidan kichik — birinchisi. */
function tierUnitPrice(tiers, qty) {
  const t = cleanTiers(tiers);
  if (!t.length) return null;
  let result = t[0].price;
  for (const x of t) {
    if (qty >= x.minQty) result = x.price;
    else break;
  }
  return result;
}

/**
 * ULGURJI moslik (wholesale_orders.js): aniq `priceTiers` bo'lsa — pog'ona, bo'lmasa `price`.
 * `pricingVersion` < 2 — `price`. Hisoblangan pog'ona YO'Q. AVA do'koni buni ISHLATMAYDI
 * (`platformUnitPrice`).
 */
function unitPriceForQty(product, qty, pricingVersion) {
  const d = product || {};
  const v = Number(pricingVersion);
  if (!(v >= PRICING_VERSION_TIERED)) return Math.trunc(Number(d.price || 0));
  const p = tierUnitPrice(d.priceTiers, qty);
  return p == null ? Math.trunc(Number(d.price || 0)) : p;
}

module.exports = {
  PRICING_VERSION_LEGACY,
  PRICING_VERSION_TIERED,
  PRICING_VERSION_SINGLE,
  SERVER_PRICING_VERSION,
  platformUnitPrice,
  cleanTiers,
  tierUnitPrice,
  unitPriceForQty,
};
