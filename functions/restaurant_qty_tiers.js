/**
 * KAFE-RESTORAN — miqdorga chegirma pog'onalari (D-REST-25, docs/kafe_restoran_taklifi_uz.md §10.1).
 *
 * Ega qarori (2026-10-19, 1-variant): restoran O'Z taomiga pog'ona qo'yadi (misol: osh 35 000; 10 tadan
 * 32 000; 30 tadan 30 000) va chegirmani O'Z hisobidan beradi — AVA chegirma bermaydi. Server menyudan
 * hisoblaydi (klient chegirma yubormaydi, 18-qoida); buyurtmaga qo'llangan pog'ona saqlanadi (9-qoida:
 * keyin menyu o'zgarsa eski buyurtma narxi o'zgarmaydi). AVA 2 % chegirmali `itemsTotal` dan.
 *
 * Pog'ona: `qtyTiers: [{ minQty, price }]` taom hujjatida. Ma'nosi (PROPOSED — ega «10 tadan ko'pga» degan,
 * chegara tengligi aytilmagan): buyurtmadagi shu taom SONI `minQty` VA UNDAN KO'P bo'lsa, har bir dona `price`
 * dan. Bir taom bir nechta qatorda kelsa son YIG'INDI bo'yicha (placeRestaurantOrder shunday yig'adi).
 *
 * Yagona manba (7-qoida): shu fayl; `firestore.rules` (`qtyTiersOk`) va klientdagi `QtyTier` xuddi shu
 * qoidani takrorlaydi — moslik testlar bilan qulflangan. Server himoyasi: noto'g'ri/tartibsiz pog'ona
 * ishonchsiz — `sanitizeTiers` birinchi noto'g'ri pog'onadan keyingisini tashlaydi (chegirma kamayadi,
 * hech qachon oshmaydi), shuning uchun buzilgan hujjat orqali asosiy narxdan PASTGA tushib bo'lmaydi.
 */
'use strict';

const MAX_TIERS = 3;
const MAX_TIER_QTY = 500;

/**
 * Faqat TO'G'RI prefiks: `minQty` butun, oldingisidan katta (birinchisi ≥ 2) va ≤ 500; `price` butun, ≥ 1 va
 * oldingi narxdan KAM (birinchisi — asosiy narxdan kam). Birinchi noto'g'ri pog'onadan keyin to'xtaydi.
 */
function sanitizeTiers(basePrice, raw) {
  if (!Array.isArray(raw) || !Number.isInteger(basePrice) || basePrice < 1) return [];
  const out = [];
  let prevMin = 1;
  let prevPrice = basePrice;
  for (const t of raw.slice(0, MAX_TIERS)) {
    if (!t || typeof t !== 'object') break;
    const { minQty, price } = t;
    if (!Number.isInteger(minQty) || minQty <= prevMin || minQty > MAX_TIER_QTY) break;
    if (!Number.isInteger(price) || price < 1 || price >= prevPrice) break;
    out.push({ minQty, price });
    prevMin = minQty;
    prevPrice = price;
  }
  return out;
}

/** `count` dona uchun bir dona narxi: { unitPrice, tierMinQty } (`tierMinQty` 0 — pog'ona qo'llanmadi). */
function unitPriceFor(basePrice, rawTiers, count) {
  let unitPrice = basePrice;
  let tierMinQty = 0;
  for (const t of sanitizeTiers(basePrice, rawTiers)) {
    if (count >= t.minQty) {
      unitPrice = t.price;
      tierMinQty = t.minQty;
    }
  }
  return { unitPrice, tierMinQty };
}

module.exports = { sanitizeTiers, unitPriceFor, MAX_TIERS, MAX_TIER_QTY };
