'use strict';

/**
 * XARID NARXI — FAQAT KATALOGDAN (K-5, ega qarori 2026-10-08).
 *
 * `procurement_products/{code}`: { code, label, unit, price (butun so'm),
 * active, updatedAt } — faqat admin yozadi (`firestore.rules`).
 *
 * Avval yig'ib olish (`adminCreateCollectionTask`, `courierFinalizeCollection`)
 * va kuryer to'lovidagi «mahsulot» qatori (`courierSubmitPayment`) narxni
 * KLIENTDAN olardi — kuryer narxni oshirib, mijoz hamyoniga ortiqcha pul
 * yozdira olardi. Endi narx, nom va o'lchov birligi katalogdan; klient
 * yuborgan narx faqat taqqoslash uchun (farq — logga).
 *
 * Yig'ib olishda narx VAZIFA YARATILGANDA qotadi (ega tanlovi, 9-qoida):
 * vazifa qatorida `priceSource: 'catalog'` va `catalogUpdatedAt` saqlanadi,
 * yakunlashda shu narx ishlatiladi.
 */

const COLLECTION = 'procurement_products';

/**
 * @param {object} deps
 * @param {FirebaseFirestore.Firestore} deps.db
 * @param {Function} deps.HttpsError `functions.https.HttpsError`
 */
function makeProcurementCatalog(deps) {
  const { db, HttpsError } = deps;

  /**
   * Kodlar bo'yicha katalog yozuvlari. `getDoc` — `(ref) => ref.get()` yoki
   * tranzaksiyada `(ref) => t.get(ref)` (o'qishlar yozuvlardan oldin).
   * Yo'q yoki nofaol yoki narxi noto'g'ri kod — `failed-precondition`.
   *
   * @returns {Promise<Map<string, {code, label, unit, price, updatedAt}>>}
   */
  async function load(codes, getDoc = (ref) => ref.get()) {
    const unique = [...new Set(codes.map((c) => String(c || '').trim()).filter(Boolean))];
    const snaps = await Promise.all(unique.map((code) => getDoc(db.collection(COLLECTION).doc(code))));
    const out = new Map();
    snaps.forEach((snap, i) => {
      const code = unique[i];
      if (!snap.exists) {
        throw new HttpsError('failed-precondition', `Katalogda yo'q: ${code}`,
          { reason: 'PRICE_NOT_IN_CATALOG', code });
      }
      const d = snap.data() || {};
      if (d.active === false) {
        throw new HttpsError('failed-precondition', `Katalogda nofaol: ${code}`,
          { reason: 'PRODUCT_INACTIVE', code });
      }
      const price = Number(d.price);
      if (!Number.isInteger(price) || price < 0) {
        throw new HttpsError('failed-precondition', `Katalog narxi noto'g'ri: ${code}`,
          { reason: 'CATALOG_PRICE_INVALID', code });
      }
      out.set(code, {
        code,
        label: String(d.label || code),
        unit: String(d.unit || ''),
        price,
        updatedAt: d.updatedAt || null,
      });
    });
    return out;
  }

  /** Klient narxi katalogdan farq qilsa — faqat log (pul katalog bo'yicha). */
  function logMismatch(action, ref, code, clientPrice, catalogPrice) {
    if (clientPrice == null || clientPrice === '') return;
    const n = Number(clientPrice);
    if (Number.isFinite(n) && Math.abs(n - catalogPrice) <= 1) return;
    console.warn(JSON.stringify({
      action, ref, code, result: 'catalog_price_used', errorCode: 'CLIENT_PRICE_IGNORED',
      clientPrice: Number.isFinite(n) ? n : String(clientPrice), catalogPrice,
    }));
  }

  return { load, logMismatch };
}

module.exports = { COLLECTION, makeProcurementCatalog };
