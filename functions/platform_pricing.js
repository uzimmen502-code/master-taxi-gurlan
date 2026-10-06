'use strict';

/**
 * AVA DO'KONI — ULGURJI NARX POG'ONALARI (ega qarori, 2026-10-06).
 *
 * Bazadagi `platform_products.price` — O'RTA pog'ona (10–50 dona) narxi.
 * Admin o'zi pog'ona qo'ymagan tovar uchun pog'onalar shundan HISOBLANADI:
 *
 *   1–9 dona   : price × 105%   (+5%)
 *   10–50 dona : price
 *   50+ dona   : price × 95%    (−5%)
 *
 * Admin `priceTiers` qo'ygan bo'lsa — o'shalar ishlatiladi, hisoblanmaydi.
 * Hisoblash FAQAT ESKI tovarlarga (`DERIVED_TIERS_CUTOFF_MS`); yangi
 * tovarda pog'onani qo'shuvchining o'zi belgilaydi.
 *
 * PUL — BUTUN SO'M (8-qoida). Yaxlitlash: yuqoriga, butun so'mgacha
 * (taksi T-4 bilan bir xil: AVA o'ziga zarar qilmaydi, farq ≤ 1 so'm).
 * Faqat butun son arifmetikasi — float yo'q.
 *
 * YAGONA QOIDA ikki tilda: shu fayl va `lib/models/price_tier.dart`.
 * Paritet: `functions/test/fixtures/platform_price_vectors.json` — ikkala
 * test (Node va Dart) bir xil vektorlarni tekshiradi.
 *
 * VERSIYA (9-qoida, orqaga moslik 26-qoida): `pricingVersion`
 *   1 — eski: yagona `price` (Play'dagi 1.0.32 va undan eski ilova shu
 *       narxni ko'rsatadi; unga boshqa narx yechilmasin).
 *   2 — pog'onali (1.0.33+ ilova yuboradi).
 * Minimal versiya darvozasi (`config/app_version`) eski ilovalarni
 * yangilatgach, 1-versiya yo'li olib tashlanadi.
 */

const PRICING_VERSION_LEGACY = 1;
const PRICING_VERSION_TIERED = 2;

/**
 * Hisoblangan (+5% / −5%) pog'onalar FAQAT ESKI tovarlarga (ega qarori,
 * 2026-10-06): `createdAt` shu vaqtdan OLDIN (2026-10-07 00:00 Toshkent).
 * Yangi tovarda pog'onani qo'shayotgan odamning O'ZI belgilaydi (admin
 * formasi / Ulgurji sotuvchi formasi) — hisoblanmaydi. `createdAt` yo'q
 * yozuv — eski deb olinadi (eng eski hujjatlarda bo'lmasligi mumkin).
 * Prodakshn 2026-10-06: 59 ta tovar, hammasi 2026-07-27…08-06 da yaratilgan.
 */
const DERIVED_TIERS_CUTOFF_MS = Date.parse('2026-10-06T19:00:00Z');

function toMillis(v) {
  if (v == null || v === '') return null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  if (typeof v === 'string') { const t = Date.parse(v); return Number.isFinite(t) ? t : null; }
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

/** Eski tovarmi — hisoblangan pog'onalar faqat shunga. */
function isLegacyProduct(product) {
  const ms = toMillis((product || {}).createdAt);
  return ms == null || ms < DERIVED_TIERS_CUTOFF_MS;
}

const MID_MIN_QTY = 10;
const HIGH_MIN_QTY = 50;
const LOW_MARKUP_PCT = 5;
const HIGH_DISCOUNT_PCT = 5;

/** ceil(a × num / den) — faqat butun sonlar bilan. */
function ceilMulDiv(a, num, den) {
  return Math.floor((a * num + den - 1) / den);
}

/** O'rta pog'ona narxidan 3 ta pog'ona. */
function derivedTiers(midPrice) {
  const p = Math.trunc(Number(midPrice));
  if (!Number.isInteger(p) || p <= 0) return [];
  return [
    { minQty: 1, price: ceilMulDiv(p, 100 + LOW_MARKUP_PCT, 100) },
    { minQty: MID_MIN_QTY, price: p },
    { minQty: HIGH_MIN_QTY, price: ceilMulDiv(p, 100 - HIGH_DISCOUNT_PCT, 100) },
  ];
}

/** Firestore `priceTiers` — to'g'ri yozuvlar, `minQty` bo'yicha o'sish tartibida. */
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

/**
 * Amaldagi pog'onalar: qo'yilgani; bo'lmasa ESKI tovarda `price` dan
 * hisoblangan; yangi tovarda — bo'sh (yagona `price` ishlatiladi).
 */
function effectiveTiers(product) {
  const d = product || {};
  const explicit = cleanTiers(d.priceTiers);
  if (explicit.length) return explicit;
  return isLegacyProduct(d) ? derivedTiers(d.price) : [];
}

/**
 * Bir dona narxi — [qty] dan kichik yoki teng eng yuqori pog'ona.
 * `pricingVersion` 2 dan kichik bo'lsa — eski yagona `price`.
 */
function unitPriceForQty(product, qty, pricingVersion) {
  const d = product || {};
  // `!(v >= 2)`: versiya yo'q (`undefined` → NaN) yoki noto'g'ri bo'lsa
  // ham ESKI narx — `NaN < 2` false bo'lgani uchun oddiy taqqoslash
  // eski ilovaga pog'onali narx qo'llab yuborardi (test ushlagan).
  const v = Number(pricingVersion);
  if (!(v >= PRICING_VERSION_TIERED)) {
    return Math.trunc(Number(d.price || 0));
  }
  const tiers = effectiveTiers(d);
  // Pog'onasiz (yangi) tovar — yagona narx; ilova ham shunday ko'rsatadi.
  if (!tiers.length) return Math.trunc(Number(d.price || 0));
  let result = tiers[0].price;
  for (const t of tiers) {
    if (qty >= t.minQty) result = t.price;
    else break;
  }
  return result;
}

module.exports = {
  PRICING_VERSION_LEGACY,
  PRICING_VERSION_TIERED,
  MID_MIN_QTY,
  HIGH_MIN_QTY,
  LOW_MARKUP_PCT,
  HIGH_DISCOUNT_PCT,
  DERIVED_TIERS_CUTOFF_MS,
  isLegacyProduct,
  derivedTiers,
  cleanTiers,
  effectiveTiers,
  unitPriceForQty,
};
