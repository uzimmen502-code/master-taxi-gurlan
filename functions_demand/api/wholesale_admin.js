'use strict';

/**
 * ADMIN — Ulgurji / Xitoy bozori: mahsulotni bir bozordan boshqasiga
 * ko'chirish (ega topshirig'i 2026-10-07).
 *
 * NEGA SERVERDA. Ikkala bozor bitta `wholesale_products` kolleksiyasida,
 * `market` maydoni bilan ajraladi. Firestore Rules `market`ni na egaga,
 * na admin'ga o'zgartirishga ruxsat beradi — ataylab: sotuvchi
 * mahsulotini boshqa bozorga o'zi o'tkaza olmasin. Lekin xato joyda
 * qolgan mahsulot bo'ladi (2026-10-07 auditi: Xitoy bozori ochilishidan
 * oldin qo'yilgan 2 ta Xitoy traktori Ulgurjida «3 800 so'm» bo'lib
 * turibdi). Rules'ni kengaytirish o'rniga — shu callable: admin tekshiruvi
 * (19-qoida), tranzaksiya (22), idempotentlik (21) va APPEND-ONLY audit
 * (41-qoida) serverda.
 *
 * NARX VALYUTASI. Ulgurji bozor faqat so'mda (`currency` yo'q). Xitoy
 * bozorida sotuvchi so'm, $ yoki ¥ tanlaydi (ilovadagi forma bilan bir
 * xil ro'yxat). Narx RAQAMLARI o'zgarmaydi — ular sotuvchiniki. Shuning
 * uchun valyutali (`$`/`¥`) mahsulotni Ulgurjiga o'tkazish RAD etiladi:
 * aks holda «3 800 $» jimgina «3 800 so'm» bo'lib qolardi.
 */

const { assertAnalyticsAdmin } = require('../analytics/access');

const COLLECTION = 'wholesale_products';
const AUDIT = 'wholesale_market_audit';

const MARKET_WHOLESALE = 'wholesale';
const MARKET_CHINA = 'china';
const MARKETS = [MARKET_WHOLESALE, MARKET_CHINA];

/** Xitoy bozori valyutalari — `wholesale_product_form_screen.dart` dagi `_kCurrencies`. '' = so'm. */
const CHINA_CURRENCIES = ['', '$', '¥'];

const MAX_DELIVERY_DAYS = 365;

function httpError(code, message, details) {
  const e = new Error(message);
  e.code = code;
  if (details) e.details = details;
  return e;
}

/** Hujjatdagi bozor — `market` maydoni yo'q eski yozuvlar Ulgurji. */
function marketOf(doc) {
  return doc && doc.market === MARKET_CHINA ? MARKET_CHINA : MARKET_WHOLESALE;
}

function currencyOf(doc) {
  return doc && typeof doc.currency === 'string' ? doc.currency.trim() : '';
}

function deliveryDaysOf(doc) {
  const d = doc ? Number(doc.deliveryDays) : NaN;
  return Number.isInteger(d) && d > 0 ? d : null;
}

/**
 * Kiruvchi so'rovni tekshirish — sof funksiya (testlanadi).
 *
 * @returns {{productId: string, market: string, currency: string,
 *            deliveryDays: (number|null), reason: string}}
 */
function parseMarketRequest(data) {
  const d = data || {};
  const productId = String(d.productId || '').trim();
  if (!productId || productId.includes('/')) {
    throw httpError('invalid-argument', 'productId kerak');
  }
  const market = String(d.market || '').trim();
  if (!MARKETS.includes(market)) {
    throw httpError('invalid-argument', `noma'lum bozor: «${market}»`);
  }
  const reason = String(d.reason || '').trim().slice(0, 500);

  if (market === MARKET_WHOLESALE) {
    // Ulgurjida valyuta va yetkazish muddati yo'q.
    return { productId, market, currency: '', deliveryDays: null, reason };
  }

  const currency = String(d.currency === undefined || d.currency === null ? '' : d.currency).trim();
  if (!CHINA_CURRENCIES.includes(currency)) {
    throw httpError('invalid-argument', `noma'lum valyuta: «${currency}»`);
  }
  let deliveryDays = null;
  if (d.deliveryDays !== undefined && d.deliveryDays !== null && d.deliveryDays !== '') {
    const n = Number(d.deliveryDays);
    if (!Number.isInteger(n) || n < 1 || n > MAX_DELIVERY_DAYS) {
      throw httpError('invalid-argument', `yetkazish muddati 1–${MAX_DELIVERY_DAYS} kun bo'lishi kerak`);
    }
    deliveryDays = n;
  }
  return { productId, market, currency, deliveryDays, reason };
}

/**
 * Callable: `{productId, market: 'wholesale'|'china', currency?, deliveryDays?, reason?}`.
 *
 * Qaytaradi: `{productId, changed, from: {market, currency, deliveryDays}, to: {...}}`.
 * Holat bir xil bo'lsa `changed: false` — hech narsa yozilmaydi (21-qoida).
 * `status` (faol/kutilmoqda/yopilgan) O'ZGARMAYDI.
 */
function makeAdminSetWholesaleProductMarket(deps) {
  const { db, now: nowFn, deleteField } = deps;
  if (typeof deleteField !== 'function') {
    throw new Error('deleteField bog\'liqligi kerak (FieldValue.delete)');
  }

  return async function adminSetWholesaleProductMarket(data, context) {
    const adminId = await assertAnalyticsAdmin(db, context);
    const req = parseMarketRequest(data);
    const now = nowFn ? nowFn() : new Date();
    const started = Date.now();

    const result = await db.runTransaction(async (tx) => {
      const ref = db.collection(COLLECTION).doc(req.productId);
      const snap = await tx.get(ref);
      if (!snap.exists) throw httpError('not-found', 'mahsulot topilmadi');
      const doc = snap.data() || {};

      const from = {
        market: marketOf(doc),
        currency: currencyOf(doc),
        deliveryDays: deliveryDaysOf(doc),
      };
      const to = {
        market: req.market,
        currency: req.currency,
        deliveryDays: req.deliveryDays,
      };

      if (to.market === MARKET_WHOLESALE && from.currency !== '') {
        throw httpError(
          'failed-precondition',
          `Narx «${from.currency}» da — Ulgurji bozor faqat so'mda. `
            + 'Avval sotuvchi narxni so\'mda kiritsin.',
          { reason: 'foreign_currency', currency: from.currency },
        );
      }

      // Eski yozuvda `market` maydoni umuman yo'q bo'lsa — Ulgurjiga
      // «ko'chirish» ham uni aniq yozib qo'yadi (keyingi so'rovlar
      // `market == 'wholesale'` bilan topsin).
      const marketFieldMissing = doc.market === undefined;
      const same = from.market === to.market
        && from.currency === to.currency
        && from.deliveryDays === to.deliveryDays
        && !marketFieldMissing;
      if (same) return { changed: false, from, to };

      const patch = {
        market: to.market,
        marketChangedBy: adminId,
        marketChangedAt: now,
      };
      if (to.market === MARKET_CHINA) {
        patch.currency = to.currency;
        patch.deliveryDays = to.deliveryDays === null ? deleteField() : to.deliveryDays;
      } else {
        patch.currency = deleteField();
        patch.deliveryDays = deleteField();
      }
      tx.update(ref, patch);

      // 41-qoida: audit — append-only, klient o'qiy ham, yoza ham olmaydi
      // (Rules'da bu kolleksiya yo'q → standart RAD).
      tx.set(db.collection(AUDIT).doc(), {
        kind: 'market_change',
        productId: req.productId,
        sellerId: String(doc.sellerId || ''),
        status: String(doc.status || ''),
        from,
        to,
        reason: req.reason,
        by: adminId,
        at: now,
      });
      return { changed: true, from, to };
    });

    // 24-qoida: tuzilgan log — telefon (PII) yo'q.
    console.log(JSON.stringify({
      action: 'adminSetWholesaleProductMarket',
      productId: req.productId,
      from: result.from.market,
      to: result.to.market,
      changed: result.changed,
      durationMs: Date.now() - started,
    }));
    return { productId: req.productId, ...result };
  };
}

module.exports = {
  AUDIT,
  CHINA_CURRENCIES,
  makeAdminSetWholesaleProductMarket,
  marketOf,
  parseMarketRequest,
};
