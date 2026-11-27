'use strict';

/**
 * Ulgurji bozor — qadoqlar bo'yicha QOLDIQ (ega, 2026-10-31).
 *
 * NEGA ALOHIDA HUJJAT VA SERVER. Qoldiq `wholesale_stock/{productId}` da,
 * Rules: o'qish hammaga, yozish HECH KIMGA (faqat shu callable va keyingi
 * bosqichdagi buyurtma tranzaksiyasi). Agar qoldiq mahsulot hujjatida
 * bo'lsa, sotuvchining tahriri (butun `packs` massivini yozadi) buyurtma
 * kamaytirgan sonni bosib ketardi (22-qoida: read→check→write poygasi).
 *
 * Callable `setWholesaleStock({productId, stock: {packId: qty}})`:
 *  - 19: chaqiruvchi = mahsulot egasi (`sellerId`), aks holda RAD;
 *  - packId faqat mahsulotning hozirgi qadoqlari (qadoqsiz eski mahsulot —
 *    `default`); qty — butun son 0..1 000 000;
 *  - 22: tranzaksiya; 21: qiymatlar o'zgarmasa hech narsa yozilmaydi;
 *  - 16/41: har o'zgarish `wholesale_stock/{id}/history` ga (append-only,
 *    Rules'da yo'q → klient o'qiy ham, yoza ham olmaydi).
 */

const { callerIdFrom } = require('../core/ids');

const PRODUCTS = 'wholesale_products';
const STOCK = 'wholesale_stock';
const HISTORY = 'history';
const DEFAULT_PACK = 'default';
const MAX_QTY = 1000000;
const MAX_PACKS = 5;
const PACK_ID_RE = /^(p[1-9]|default)$/;

function httpError(code, message, details) {
  const e = new Error(message);
  e.code = code;
  if (details) e.details = details;
  return e;
}

/** Mahsulotning hozirgi qadoq ID'lari (ilovadagi `WholesalePack.parseList` bilan bir xil). */
function packIdsOf(product) {
  const raw = product && Array.isArray(product.packs) ? product.packs : [];
  const ids = [];
  for (const p of raw) {
    const id = p && typeof p.id === 'string' ? p.id.trim() : '';
    const label = p && typeof p.label === 'string' ? p.label.trim() : '';
    const tiers = p && Array.isArray(p.priceTiers) ? p.priceTiers : [];
    if (!PACK_ID_RE.test(id) || id === DEFAULT_PACK || !label || !tiers.length) continue;
    if (ids.includes(id)) continue;
    ids.push(id);
    if (ids.length >= MAX_PACKS) break;
  }
  return ids.length ? ids : [DEFAULT_PACK];
}

/** Kiruvchi so'rov — sof funksiya (testlanadi). */
function parseStockRequest(data) {
  const d = data || {};
  const productId = String(d.productId || '').trim();
  if (!productId || productId.includes('/') || productId.length > 128) {
    throw httpError('invalid-argument', 'productId kerak');
  }
  const raw = d.stock;
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw httpError('invalid-argument', 'stock {packId: qty} kerak');
  }
  const entries = Object.entries(raw);
  if (!entries.length || entries.length > MAX_PACKS) {
    throw httpError('invalid-argument', `stock 1–${MAX_PACKS} ta qadoq`);
  }
  const stock = {};
  for (const [k, v] of entries) {
    if (!PACK_ID_RE.test(k)) throw httpError('invalid-argument', `noto'g'ri qadoq: «${k}»`);
    if (!Number.isInteger(v) || v < 0 || v > MAX_QTY) {
      throw httpError('invalid-argument', `qoldiq 0–${MAX_QTY} butun son bo'lishi kerak`, { packId: k });
    }
    stock[k] = v;
  }
  return { productId, stock };
}

function makeSetWholesaleStock(deps) {
  const { db, now: nowFn } = deps;

  return async function setWholesaleStock(data, context) {
    const caller = callerIdFrom(context);
    if (!caller) throw httpError('unauthenticated', 'telefon bilan kiring');
    const req = parseStockRequest(data);
    const now = nowFn ? nowFn() : new Date();
    const started = Date.now();

    const result = await db.runTransaction(async (tx) => {
      const productRef = db.collection(PRODUCTS).doc(req.productId);
      const stockRef = db.collection(STOCK).doc(req.productId);
      const pSnap = await tx.get(productRef);
      const sSnap = await tx.get(stockRef);
      if (!pSnap.exists) throw httpError('not-found', 'mahsulot topilmadi');
      const product = pSnap.data() || {};
      if (String(product.sellerId || '') !== caller) {
        throw httpError('permission-denied', 'faqat mahsulot egasi', { reason: 'not_owner' });
      }
      const allowed = packIdsOf(product);
      for (const k of Object.keys(req.stock)) {
        if (!allowed.includes(k)) {
          throw httpError('invalid-argument', `mahsulotda bunday qadoq yo'q: «${k}»`, { packId: k });
        }
      }

      const prevDoc = sSnap.exists ? (sSnap.data() || {}) : {};
      const prev = prevDoc.packs && typeof prevDoc.packs === 'object' ? prevDoc.packs : {};
      // Faqat hozirgi qadoqlar qoladi — o'chirilgan qadoqning eski qoldig'i tashlanadi.
      const next = {};
      for (const id of allowed) {
        if (Object.prototype.hasOwnProperty.call(req.stock, id)) next[id] = req.stock[id];
        else if (Number.isInteger(prev[id])) next[id] = prev[id];
      }
      const same = Object.keys(next).length === Object.keys(prev).length
        && Object.entries(next).every(([k, v]) => prev[k] === v);
      if (same) return { changed: false, packs: next };

      const version = (Number.isInteger(prevDoc.version) ? prevDoc.version : 0) + 1;
      tx.set(stockRef, {
        productId: req.productId,
        sellerId: caller,
        packs: next,
        version,
        updatedAt: now,
      });
      tx.set(stockRef.collection(HISTORY).doc(`v${version}`), {
        kind: 'seller_set',
        from: prev,
        to: next,
        by: caller,
        at: now,
        version,
      });
      return { changed: true, packs: next, version };
    });

    // 24: tuzilgan log — telefon (PII) yo'q.
    console.log(JSON.stringify({
      action: 'setWholesaleStock',
      productId: req.productId,
      changed: result.changed,
      packs: Object.keys(result.packs).length,
      durationMs: Date.now() - started,
    }));
    return { productId: req.productId, ...result };
  };
}

module.exports = {
  STOCK,
  HISTORY,
  DEFAULT_PACK,
  MAX_QTY,
  makeSetWholesaleStock,
  packIdsOf,
  parseStockRequest,
};
