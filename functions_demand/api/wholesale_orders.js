'use strict';

/**
 * ULGURJI BUYURTMA ZANJIRI — 2-bosqich, demand codebase (europe-west1).
 * Hujjat: docs/ulgurji_buyurtma_zanjiri_uz.md (ega qarorlari Q-1…Q-8, 2026-10-31).
 *
 *   quoteWholesaleOrder        narx (pulsiz): qadoq pog'onasi × miqdor + relay
 *                              tarifi bo'yicha yetkazish; `wholesale_quotes/{id}`
 *                              ga MUHRLANADI (15 daqiqa). Pul ushlash — default
 *                              codebase `placeWholesaleOrder` (ledger o'sha yerda).
 *   rejectWholesaleOrder       sotuvchi: placed → rejected
 *   cancelWholesaleOrder       xaridor:  placed → cancelled
 *                              Ikkalasi FAQAT holatni + `refundStatus: 'pending'`
 *                              yozadi; pulni qaytarish va qoldiqni tiklash —
 *                              default trigger `onWholesaleOrderStatusChange`.
 *   setWholesaleOrderSettings  admin: AVA ulushi (bps) — versiya + audit.
 *
 * NEGA SOZLAMA SHU CODEBASE'DA: ulush birinchi bo'lib KVOTADA (shu yerda)
 * muhrlanadi; admin tekshiruvi (`assertStrictAdmin`) va audit naqshi
 * (`wholesale_admin.js`, `adminSetLogisticsStage`) shu yerda. Default codebase
 * (3-bosqich RELEASE) faqat buyurtmadagi muhrlangan qiymatni o'qiydi —
 * sozlamaning o'zini o'qimaydi.
 *
 * Pul — faqat butun so'm (8-band). Narx, ulush, yetkazish — faqat serverda (18, 44).
 * Log — telefon/manzil YO'Q (24, 40-band).
 */

const { callerIdFrom, sameUser } = require('../core/ids');
const { getGlobalConfig } = require('../core/config');
const L = require('../core/logistics');
const WO = require('../core/wholesale_orders');
const { packIdsOf, STOCK, MAX_QTY, DEFAULT_PACK } = require('./wholesale_stock');
const { marketOf } = require('./wholesale_admin');
const { quoteParcelForPoints } = require('./logistics');
const { assertStrictAdmin } = require('../analytics/access');

const PRODUCTS = 'wholesale_products';
const SELLERS = 'wholesale_sellers';
const QUOTES = 'wholesale_quotes';
const ORDERS = 'wholesale_orders';
const HISTORY = 'history';
const SETTINGS_DOC = ['settings', 'wholesale_orders'];
const GATE_DOC = ['module_config', 'wholesale_orders_all'];
const ADMIN_AUDIT = 'admin_audit';

/** Kvota amal qilish muddati (topshiriq, 2026-10-31). */
const QUOTE_TTL_MS = 15 * 60 * 1000;
/** Bitta buyurtma tovar summasi chegarasi — 100 mlrd so'm (toshib ketish himoyasi, biznes qoida emas). */
const MAX_GOODS_TOTAL = 100000000000;
/** AVA ulushi chegarasi: 0..30 % (topshiriq). */
const AVA_FEE_BPS_MAX = 3000;
const BPS_DENOM = 10000;
const MAX_DIM_CM = 1000;
const ID_RE = /^[A-Za-z0-9_-]{1,128}$/;

function fail(code, message, reason, extra) {
  const e = new Error(message);
  e.code = code;
  e.httpErrorCode = code;
  e.details = { reason: reason || code, ...(extra || {}) };
  return e;
}

const isInt = (n) => typeof n === 'number' && Number.isInteger(n);
const isPosInt = (n) => isInt(n) && n > 0;

function log(action, fields) {
  console.log(JSON.stringify({ module: 'wholesale_orders', action, ...fields }));
}

// ═══════════════════════════════════════════════════════════════════════
// SOF FUNKSIYALAR (testlanadi)
// ═══════════════════════════════════════════════════════════════════════

/**
 * Pog'onalar — `functions/platform_pricing.js` `cleanTiers` bilan AYNAN bir xil
 * (paritet testi: test/wholesale_orders.test.js). Ikki codebase umumiy kod
 * ishlatolmaydi (har biri o'z papkasini deploy qiladi), shuning uchun nusxa +
 * paritet testi (relay `logistics_parity` naqshi).
 */
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

/** Bir dona narxi: `qty >= minQty` bo'lgan OXIRGI pog'ona (platform_pricing / price_tier.dart qoidasi). */
function tierUnitPrice(tiers, qty) {
  if (!tiers.length) return null;
  let result = tiers[0].price;
  for (const t of tiers) {
    if (qty >= t.minQty) result = t.price;
    else break;
  }
  return result;
}

/** `{l,w,h}` — butun 1..1000 sm (ilova `ShippingDims` bilan bir xil); aks holda null. */
function validDims(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const d = { l: raw.l, w: raw.w, h: raw.h };
  if (![d.l, d.w, d.h].every((x) => isInt(x) && x >= 1 && x <= MAX_DIM_CM)) return null;
  return d;
}

/**
 * Qadoq: `packs[]` dan (ID `packIdsOf` bo'yicha haqiqiy bo'lishi SHART), qadoqsiz
 * eski mahsulotda `default` — mahsulot darajasidagi `priceTiers`/`unitWeightG`/
 * `unitDims` (ilova `WholesaleProduct.effectivePacks` bilan bir xil).
 * @returns {null|{id,label,tiers,moq,unitWeightG,unitDims}}
 */
function resolvePack(product, packId) {
  const p = product || {};
  if (!packIdsOf(p).includes(packId)) return null;
  const src = packId === DEFAULT_PACK
    ? { label: '', priceTiers: p.priceTiers, unitWeightG: p.unitWeightG, unitDims: p.unitDims }
    : (p.packs || []).find((x) => x && typeof x.id === 'string' && x.id.trim() === packId);
  if (!src) return null;
  const tiers = cleanTiers(src.priceTiers);
  const w = src.unitWeightG;
  return {
    id: packId,
    label: String(src.label || '').trim().slice(0, 40),
    tiers,
    moq: tiers.length ? tiers[0].minQty : 1,
    unitWeightG: isPosInt(w) ? w : null,
    unitDims: validDims(src.unitDims),
  };
}

/** AVA ulushi — ceil(goods × bps / 10000), butun so'm (relay `splitInternal` yaxlitlashi; PROPOSED). */
function avaFeeOf(goodsTotal, bps) {
  if (!bps) return 0;
  const x = goodsTotal * bps;
  if (!Number.isSafeInteger(x)) throw fail('failed-precondition', 'Summa juda katta', 'amount_too_large');
  return Math.floor(x / BPS_DENOM) + (x % BPS_DENOM === 0 ? 0 : 1);
}

function parseQuoteRequest(data) {
  const d = data || {};
  const productId = String(d.productId || '').trim();
  if (!ID_RE.test(productId)) throw fail('invalid-argument', 'Mahsulot tanlanmagan', 'product_required');
  const packId = String(d.packId || '').trim();
  if (!/^(p[1-9]|default)$/.test(packId)) throw fail('invalid-argument', 'Qadoq tanlanmagan', 'pack_required');
  const qty = d.qty;
  if (!isInt(qty) || qty < 1 || qty > MAX_QTY) {
    throw fail('invalid-argument', `Miqdor 1–${MAX_QTY} butun son bo'lishi kerak`, 'qty_invalid', { max: MAX_QTY });
  }
  const dest = d.destination && typeof d.destination === 'object' ? d.destination : null;
  if (!dest) throw fail('invalid-argument', 'Yetkazish manzili kerak', 'destination_required');
  const addressText = String(dest.addressText || '').trim();
  if (addressText.length < 3) throw fail('invalid-argument', 'Yetkazish manzilini yozing', 'address_required');
  return {
    productId,
    packId,
    qty,
    destination: {
      regionId: dest.regionId, districtId: dest.districtId, lat: dest.lat, lng: dest.lng, addressText,
    },
  };
}

/** `settings/wholesale_orders` — yo'q bo'lsa ulush 0, versiya 0 (hujjatlashtirilgan standart). */
async function readFeeSettings(db) {
  const snap = await db.collection(SETTINGS_DOC[0]).doc(SETTINGS_DOC[1]).get();
  if (!snap.exists) return { avaFeeBps: 0, feeVersion: 0 };
  const d = snap.data() || {};
  const bps = d.avaFeeBps === undefined || d.avaFeeBps === null ? 0 : d.avaFeeBps;
  const ver = d.feeVersion === undefined || d.feeVersion === null ? 0 : d.feeVersion;
  // Noto'g'ri sozlama — JIMGINA 0 emas: kvota rad etiladi (8, 53-band).
  if (!isInt(bps) || bps < 0 || bps > AVA_FEE_BPS_MAX || !isInt(ver) || ver < 0) {
    throw fail('failed-precondition', 'Buyurtma xizmati vaqtincha ishlamayapti', 'fee_settings_invalid');
  }
  return { avaFeeBps: bps, feeVersion: ver };
}

/**
 * Darvoza (42-band; logistika naqshi): `module_config/wholesale_orders_all`
 * `{enabled, stage: off|internal|pilot|public, testerIds}`. Hujjat yo'q /
 * o'qilmadi / `enabled !== true` / global kill switch — YOPIQ. Bosqich qoidasi
 * relay bilan bitta (`core/logistics.js` `isStageAllowed`); noma'lum bosqich =
 * `internal`. (`core/config.js` keshi ishlatilmaydi: `moduleRegionKey` `_` li
 * modul nomini qabul qilmaydi.)
 */
async function requireOrdersGate(db, uid) {
  let d = null;
  try {
    const snap = await db.collection(GATE_DOC[0]).doc(GATE_DOC[1]).get();
    d = snap.exists ? (snap.data() || {}) : null;
  } catch (e) {
    console.error(JSON.stringify({ module: 'wholesale_orders', action: 'gate', result: 'failed', errorCode: 'GATE_READ_FAILED' }));
    d = null;
  }
  const g = await getGlobalConfig(db);
  if (!d || d.enabled !== true || g.enabled === false) {
    throw fail('unavailable', 'Ulgurji buyurtma hali ishga tushmagan', 'module_disabled');
  }
  const cfg = { logistics: { stage: d.stage, testerIds: d.testerIds } };
  if (!L.isStageAllowed(cfg, uid)) {
    throw fail('unavailable', 'Ulgurji buyurtma hali ishga tushmagan', 'module_internal_only');
  }
  return { stage: L.stageOf(cfg) };
}

function sellerOrigin(seller) {
  const s = seller || {};
  const regionId = String(s.regionId || '').trim();
  if (!regionId) return null;
  return {
    regionId,
    districtId: String(s.districtId || '').trim(),
    lat: s.lat,
    lng: s.lng,
    addressText: String(s.address || ''),
  };
}

// ═══════════════════════════════════════════════════════════════════════
// KVOTA
// ═══════════════════════════════════════════════════════════════════════

function makeQuoteWholesaleOrder(deps) {
  const { db, now: nowFn } = deps;

  return async function quoteWholesaleOrder(data, context) {
    const started = Date.now();
    const buyerId = callerIdFrom(context);
    if (!buyerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const req = parseQuoteRequest(data);
    try {
      await requireOrdersGate(db, buyerId);
      const now = nowFn ? nowFn() : new Date();

      const pSnap = await db.collection(PRODUCTS).doc(req.productId).get();
      if (!pSnap.exists) throw fail('not-found', 'Mahsulot topilmadi', 'product_not_found');
      const product = pSnap.data() || {};
      const sellerId = String(product.sellerId || '');
      if (!sellerId) throw fail('failed-precondition', 'Mahsulotni buyurtma qilib bo\'lmaydi', 'product_unavailable');
      if (sameUser(sellerId, buyerId)) {
        throw fail('failed-precondition', 'O\'z mahsulotingizga buyurtma bera olmaysiz', 'own_product');
      }
      if (product.status !== 'active') {
        throw fail('failed-precondition', 'Mahsulot hozir sotuvda emas', 'product_unavailable');
      }
      // Xitoy bozori — xorijiy valyuta ($/¥): so'mli hamyondan to'lab bo'lmaydi.
      const currency = typeof product.currency === 'string' ? product.currency.trim() : '';
      if (marketOf(product) !== 'wholesale' || currency !== '') {
        throw fail('failed-precondition', 'Bu mahsulotni ilova orqali buyurtma qilib bo\'lmaydi', 'foreign_market');
      }

      const pack = resolvePack(product, req.packId);
      if (!pack) throw fail('invalid-argument', 'Bunday qadoq yo\'q', 'pack_not_found');
      if (!pack.tiers.length) throw fail('failed-precondition', 'Qadoq narxi yo\'q', 'pack_price_missing');
      if (req.qty < pack.moq) {
        throw fail('invalid-argument', `Eng kam buyurtma — ${pack.moq}`, 'below_moq', { moq: pack.moq });
      }

      const stSnap = await db.collection(STOCK).doc(req.productId).get();
      const stockPacks = stSnap.exists ? ((stSnap.data() || {}).packs || {}) : {};
      const available = stockPacks[req.packId];
      // Qoldiq kiritilmagan qadoq — buyurtma yo'q: kamaytirib bo'lmaydigan sonni sotmaymiz.
      if (!isInt(available) || available < 0) {
        throw fail('failed-precondition', 'Sotuvchi qoldiqni kiritmagan', 'stock_unknown');
      }
      if (req.qty > available) {
        throw fail('failed-precondition', 'Omborda yetarli emas', 'insufficient_stock', { available });
      }

      const unitPrice = tierUnitPrice(pack.tiers, req.qty);
      const goodsTotal = unitPrice * req.qty;
      if (!Number.isSafeInteger(goodsTotal) || goodsTotal > MAX_GOODS_TOTAL) {
        throw fail('invalid-argument', 'Buyurtma summasi juda katta', 'amount_too_large', { max: MAX_GOODS_TOTAL });
      }

      if (!pack.unitWeightG) {
        throw fail('failed-precondition', 'Sotuvchi qadoq vaznini kiritmagan', 'no_shipping_data');
      }
      const weightG = pack.unitWeightG * req.qty;
      if (!Number.isSafeInteger(weightG)) throw fail('invalid-argument', 'Vazn juda katta', 'over_weight');

      const sSnap = await db.collection(SELLERS).doc(sellerId).get();
      const originRaw = sSnap.exists ? sellerOrigin(sSnap.data()) : null;
      if (!originRaw) throw fail('failed-precondition', 'Sotuvchi jo\'natish manzilini kiritmagan', 'seller_location_missing');

      const fee = await readFeeSettings(db);

      // PROPOSED (hujjat §2): o'lcham faqat 1 dona bo'lsa ma'lum — ko'p donada
      // umumiy quti o'lchami noma'lum, pullik vazn = haqiqiy vazn.
      const dims = req.qty === 1 ? pack.unitDims : null;
      const parcel = {
        actualWeightG: weightG,
        ...(dims ? { lengthCm: dims.l, widthCm: dims.w, heightCm: dims.h } : {}),
        declaredValue: goodsTotal,
      };
      const rq = await quoteParcelForPoints(db, originRaw, req.destination, parcel, { dimsOptional: true });
      const deliveryFee = rq.quote.customerPrice;
      if (!isInt(deliveryFee) || deliveryFee < 0) {
        throw fail('failed-precondition', 'Yetkazish narxi hisoblanmadi', 'delivery_price_invalid');
      }
      const total = goodsTotal + deliveryFee;
      if (!Number.isSafeInteger(total)) throw fail('invalid-argument', 'Summa juda katta', 'amount_too_large');
      const avaFee = avaFeeOf(goodsTotal, fee.avaFeeBps);
      const expiresAt = new Date(now.getTime() + QUOTE_TTL_MS);

      const ref = db.collection(QUOTES).doc();
      const quoteDoc = {
        buyerId,
        sellerId,
        productId: req.productId,
        productTitle: String(product.title || '').slice(0, 200),
        packId: pack.id,
        packLabel: pack.label,
        qty: req.qty,
        unitPrice,
        goodsTotal,
        deliveryFee,
        total,
        currency: 'UZS',
        delivery: {
          tariffVersion: rq.quote.tariffVersion,
          zone: rq.quote.zone,
          actualWeightG: weightG,
          chargeableWeightG: rq.quote.chargeableWeightG,
          dims: dims || null,
          priceSnapshot: rq.quote,
        },
        avaFeeBps: fee.avaFeeBps,
        feeVersion: fee.feeVersion,
        avaFee,
        sellerPayout: goodsTotal - avaFee,
        pricing: { rule: 'pack_tiers', tiers: pack.tiers, moq: pack.moq },
        stockAtQuote: available,
        origin: rq.origin,
        destination: rq.destination,
        createdAt: now,
        expiresAt,
        used: false,
      };
      await ref.set(quoteDoc);

      log('quote', {
        result: 'ok', quoteId: ref.id, productId: req.productId, packId: pack.id, qty: req.qty,
        goodsTotal, deliveryFee, tariffVersion: rq.quote.tariffVersion, durationMs: Date.now() - started,
      });
      return {
        quoteId: ref.id,
        productId: req.productId,
        productTitle: quoteDoc.productTitle,
        packId: pack.id,
        packLabel: pack.label,
        qty: req.qty,
        unitPrice,
        goodsTotal,
        deliveryFee,
        total,
        currency: 'UZS',
        expiresAtMs: expiresAt.getTime(),
      };
    } catch (e) {
      log('quote', {
        result: 'denied', productId: req.productId, packId: req.packId,
        errorCode: (e.details && e.details.reason) || e.code || 'UNKNOWN', durationMs: Date.now() - started,
      });
      throw e;
    }
  };
}

// ═══════════════════════════════════════════════════════════════════════
// RAD / BEKOR — faqat holat (pul — default trigger)
// ═══════════════════════════════════════════════════════════════════════

function makeOrderTransition({ db, now: nowFn }, { actor, to, action }) {
  return async function transition(data, context) {
    const started = Date.now();
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const d = data || {};
    const orderId = String(d.orderId || '').trim();
    if (!ID_RE.test(orderId)) throw fail('invalid-argument', 'Buyurtma tanlanmagan', 'order_required');
    const reason = String(d.reason || '').trim().slice(0, 300);
    const now = nowFn ? nowFn() : new Date();
    const ref = db.collection(ORDERS).doc(orderId);
    try {
      const out = await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) throw fail('not-found', 'Buyurtma topilmadi', 'order_not_found');
        const o = snap.data() || {};
        const partyId = actor === WO.ACTOR.SELLER ? o.sellerId : o.buyerId;
        if (!sameUser(partyId, callerId)) {
          throw fail('permission-denied', 'Bu buyurtma sizniki emas', 'not_order_party');
        }
        const from = String(o.status || '');
        // 21-band: takror chaqiruv (tarmoq qayta urinishi) — xato emas, ikkinchi yozuv yo'q.
        if (from === to) return { idempotent: true, from };
        WO.assertTransition(actor, from, to);
        const seq = (isInt(o.historySeq) ? o.historySeq : 0) + 1;
        const patch = {
          status: to,
          statusUpdatedAt: now,
          updatedAt: now,
          historySeq: seq,
        };
        if (WO.needsRefund(to)) patch.refundStatus = WO.REFUND_STATUS.PENDING;
        if (to === WO.STATUS.REJECTED) {
          patch.rejectedAt = now;
          patch.rejectReason = reason;
        } else if (to === WO.STATUS.CANCELLED) {
          patch.cancelledAt = now;
          patch.cancelledBy = actor;
        }
        tx.update(ref, patch);
        tx.set(ref.collection(HISTORY).doc(String(seq)), {
          seq, from, to, actor, actorId: callerId, reason, at: now,
        });
        return { idempotent: false, from };
      });
      log(action, {
        result: out.idempotent ? 'already' : 'ok', orderId, from: out.from, to, durationMs: Date.now() - started,
      });
      return { ok: true, orderId, status: to, idempotent: out.idempotent };
    } catch (e) {
      log(action, {
        result: 'denied', orderId, to, errorCode: (e.details && e.details.reason) || e.code || 'UNKNOWN',
      });
      throw e;
    }
  };
}

function makeRejectWholesaleOrder(deps) {
  return makeOrderTransition(deps, {
    actor: WO.ACTOR.SELLER, to: WO.STATUS.REJECTED, action: 'rejectWholesaleOrder',
  });
}

function makeCancelWholesaleOrder(deps) {
  return makeOrderTransition(deps, {
    actor: WO.ACTOR.BUYER, to: WO.STATUS.CANCELLED, action: 'cancelWholesaleOrder',
  });
}

// ═══════════════════════════════════════════════════════════════════════
// ADMIN — AVA ulushi (Q-4: admin tahrirlaydi, versiyali, audit)
// ═══════════════════════════════════════════════════════════════════════

/**
 * `setWholesaleOrderSettings({ avaFeeBps, reason? })` — faqat admin/superadmin
 * (pul oqimi: dispatcher EMAS, restoran `adminSetRestaurantFeeSettings` bilan bir xil).
 * Haqiqiy o'zgarish: `feeVersion + 1` + `admin_audit` (append-only, klientga yopiq).
 * Bir xil qiymat — `unchanged: true`, hech narsa yozilmaydi. Mavjud kvota/buyurtmalar
 * o'z muhrlangan ulushi bilan qoladi (9-band).
 */
function makeSetWholesaleOrderSettings(deps) {
  const { db, now: nowFn } = deps;
  return async function setWholesaleOrderSettings(data, context) {
    const adminId = await assertStrictAdmin(db, context);
    const d = data || {};
    const bps = d.avaFeeBps;
    if (!isInt(bps) || bps < 0 || bps > AVA_FEE_BPS_MAX) {
      throw fail('invalid-argument', `AVA ulushi 0–${AVA_FEE_BPS_MAX} bps butun son`, 'ava_fee_bps_invalid', { min: 0, max: AVA_FEE_BPS_MAX });
    }
    const reason = String(d.reason || '').trim().slice(0, 300);
    const now = nowFn ? nowFn() : new Date();
    const ref = db.collection(SETTINGS_DOC[0]).doc(SETTINGS_DOC[1]);
    const out = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const cur = snap.exists ? (snap.data() || {}) : {};
      const prevBps = isInt(cur.avaFeeBps) ? cur.avaFeeBps : null;
      const prevVersion = isInt(cur.feeVersion) ? cur.feeVersion : 0;
      if (snap.exists && prevBps === bps) return { unchanged: true, avaFeeBps: bps, feeVersion: prevVersion };
      const next = prevVersion + 1;
      tx.set(ref, {
        avaFeeBps: bps, feeVersion: next, updatedAt: now, updatedBy: adminId,
      });
      tx.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'wholesale_order_fee_settings',
        actor: adminId,
        target: SETTINGS_DOC.join('/'),
        from: String(prevVersion),
        to: String(next),
        reason,
        detail: { avaFeeBps: bps, prevAvaFeeBps: prevBps },
        at: now,
      });
      return { unchanged: false, avaFeeBps: bps, feeVersion: next };
    });
    log('setWholesaleOrderSettings', {
      result: out.unchanged ? 'unchanged' : 'ok', avaFeeBps: out.avaFeeBps, feeVersion: out.feeVersion,
    });
    return { ok: true, ...out };
  };
}

module.exports = {
  QUOTES,
  ORDERS,
  HISTORY,
  SETTINGS_DOC,
  GATE_DOC,
  ADMIN_AUDIT,
  QUOTE_TTL_MS,
  MAX_GOODS_TOTAL,
  AVA_FEE_BPS_MAX,
  cleanTiers,
  tierUnitPrice,
  validDims,
  resolvePack,
  avaFeeOf,
  parseQuoteRequest,
  readFeeSettings,
  requireOrdersGate,
  makeQuoteWholesaleOrder,
  makeRejectWholesaleOrder,
  makeCancelWholesaleOrder,
  makeSetWholesaleOrderSettings,
};
