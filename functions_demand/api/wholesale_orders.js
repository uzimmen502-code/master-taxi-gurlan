'use strict';

/**
 * ULGURJI BUYURTMA ZANJIRI — 2-bosqich, demand codebase (europe-west1).
 * Hujjat: docs/ulgurji_buyurtma_zanjiri_uz.md (ega qarorlari Q-1…Q-8, 2026-10-31).
 *
 *   quoteWholesaleOrder        narx (pulsiz): qadoq pog'onasi × miqdor + relay
 *                              tarifi bo'yicha yetkazish; `wholesale_quotes/{id}`
 *                              ga MUHRLANADI (15 daqiqa). Pul ushlash — default
 *                              codebase `placeWholesaleOrder` (ledger o'sha yerda).
 *   cancelWholesaleOrder       xaridor:  placed → cancelled. Sotuvchi qabul/rad
 *                              QILMAYDI (ega, 2026-10-31) — zanjir avtomatik.
 *                              FAQAT holatni + `refundStatus: 'pending'`
 *                              yozadi; pulni qaytarish va qoldiqni tiklash —
 *                              default trigger `onWholesaleOrderStatusChange`.
 *   setWholesaleOrderSettings  admin: AVA ulushi (bps) — versiya + audit.
 *   onWholesaleOrderCreated    (3-bosqich, trigger) relay jo'natmasi avtomatik
 *   reconcileWholesaleShipments (3-bosqich, har 10 daqiqa) yiqilgan yaratishni qayta urinadi
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
const {
  quoteParcelForPoints, createShipmentInternal, prepareCancelUnpaidShipmentInTx,
} = require('./logistics');
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
// BEKOR — faqat holat (pul — default trigger)
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
        // Faqat xaridor (sotuvchi buyurtmaga aralashmaydi, ega 2026-10-31).
        if (!sameUser(o.buyerId, callerId)) {
          throw fail('permission-denied', 'Bu buyurtma sizniki emas', 'not_order_party');
        }
        const from = String(o.status || '');
        // 21-band: takror chaqiruv (tarmoq qayta urinishi) — xato emas, ikkinchi yozuv yo'q.
        if (from === to) return { idempotent: true, from };
        WO.assertTransition(actor, from, to);
        // 3-bosqich: yetkazish hali TO'LANMAGAN jo'natma ochilgan bo'lsa — u ham bekor
        // (LEG kuryerga chiqmasin). O'QISH — yozuvdan oldin. To'langan bo'lsa buyurtma
        // allaqachon `in_delivery` (xaridor bekor qila olmaydi — yuqoridagi tekshiruv).
        const shipmentId = to === WO.STATUS.CANCELLED ? String((o.shipment || {}).shipmentId || '') : '';
        const cancelShipment = shipmentId ? await prepareCancelUnpaidShipmentInTx(tx, db, shipmentId) : null;
        const seq = (isInt(o.historySeq) ? o.historySeq : 0) + 1;
        const patch = {
          status: to,
          statusUpdatedAt: now,
          updatedAt: now,
          historySeq: seq,
        };
        if (WO.needsRefund(to)) patch.refundStatus = WO.REFUND_STATUS.PENDING;
        if (to === WO.STATUS.CANCELLED) {
          patch.cancelledAt = now;
          patch.cancelledBy = actor;
        }
        tx.update(ref, patch);
        tx.set(ref.collection(HISTORY).doc(String(seq)), {
          seq, from, to, actor, actorId: callerId, reason, at: now,
          ...(cancelShipment ? { meta: { shipmentCancelled: shipmentId } } : {}),
        });
        if (cancelShipment) cancelShipment(now, `wholesale_${actor}`);
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

function makeCancelWholesaleOrder(deps) {
  return makeOrderTransition(deps, {
    actor: WO.ACTOR.BUYER, to: WO.STATUS.CANCELLED, action: 'cancelWholesaleOrder',
  });
}

// ═══════════════════════════════════════════════════════════════════════
// 3-BOSQICH: buyurtma berilishi bilan relay jo'natmasi AVTOMATIK
// ═══════════════════════════════════════════════════════════════════════
//
// Sotuvchi qabul/rad QILMAYDI (ega, 2026-10-31). `wholesale_orders` onCreate
// (`placed`) → `createShipmentInternal` (egasi/jo'natuvchi = sotuvchi, LEG-1 olish
// kontakti = sotuvchi; qabul qiluvchi = xaridor, `recipientId`), narx — kvotada
// MUHRLANGAN (`order.delivery`, qayta hisoblanmaydi). Keyin tranzaksiyada
// `order.shipment = {shipmentId, orderId, trackingNumber, createdAt}`; HOLAT
// O'ZGARMAYDI — `placed → in_delivery` yetkazish haqi eskrouga o'tganda (default
// codebase, `wholesaleShipFund:{orderId}`), shu paytda relay `onShipmentFunded` LEG'ni ochadi.
// Xato: `order.shipmentError = {code, at, attempts, final}` (PII yo'q); reconcile
// (har 10 daqiqa) `placed` + shipment yo'q + 2 daqiqadan eski buyurtmalarni qayta
// urinadi, `SHIPMENT_MAX_ATTEMPTS` dan keyin `final: true` — admin (5-bosqich).

const SHIPMENT_MAX_ATTEMPTS = 5;
const SHIPMENT_RECONCILE_MIN_AGE_MS = 2 * 60 * 1000;
const SHIPMENT_RECONCILE_LIMIT = 100;

function msOf(v) {
  if (v == null) return null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return null;
}

/** Xaridor ismi — `users` hujjatidan (repo naqshi `name || fullName || displayName`); yo'q bo'lsa bo'sh (o'ylab topilmaydi). */
async function buyerDisplayName(db, o) {
  for (const id of [o.buyerWalletUid, o.buyerId]) {
    if (!id || typeof id !== 'string') continue;
    const s = await db.collection('users').doc(id).get();
    if (s.exists) {
      const u = s.data() || {};
      return String(u.name || u.fullName || u.displayName || '').trim().slice(0, 80);
    }
  }
  return '';
}

/**
 * Buyurtma → `createShipmentInternal` kirishi. Hamma qiymat BUYURTMADAGI muhrdan
 * (kvota yozgan, default codebase ko'chirgan): narx surati, tarif versiyasi,
 * vazn, o'lcham (bo'lmasligi mumkin), e'lon qilingan qiymat = tovar summasi.
 */
function shipmentInputFromOrder(orderId, o, recipientName) {
  const d = o.delivery && typeof o.delivery === 'object' ? o.delivery : {};
  const snap = d.priceSnapshot && typeof d.priceSnapshot === 'object' ? d.priceSnapshot : null;
  if (!snap) throw fail('failed-precondition', 'Yetkazish narxi muhri yo\'q', 'delivery_snapshot_missing');
  if (!isPosInt(o.deliveryFee) || snap.customerPrice !== o.deliveryFee) {
    throw fail('failed-precondition', 'Yetkazish narxi muhrga mos emas', 'delivery_price_mismatch');
  }
  if (!isPosInt(d.tariffVersion) || snap.tariffVersion !== d.tariffVersion) {
    throw fail('failed-precondition', 'Tarif versiyasi muhrga mos emas', 'tariff_version_mismatch');
  }
  if (!isPosInt(d.actualWeightG)) throw fail('failed-precondition', 'Vazn yo\'q', 'parcel_weight_missing');
  if (!isPosInt(o.goodsTotal)) throw fail('failed-precondition', 'Tovar summasi yo\'q', 'goods_total_invalid');
  const dims = d.dims ? validDims(d.dims) : null;
  if (d.dims && !dims) throw fail('failed-precondition', 'O\'lcham yaroqsiz', 'parcel_dims_invalid');
  const title = String(o.productTitle || '').trim();
  const pack = String(o.packLabel || '').trim();
  return {
    idempotencyKey: `wholesale_ship_${orderId}`,
    ownerId: o.sellerId,
    recipientId: o.buyerId,
    recipient: { name: recipientName },
    origin: o.origin,
    destination: o.destination,
    parcel: {
      actualWeightG: d.actualWeightG,
      lengthCm: dims ? dims.l : null,
      widthCm: dims ? dims.w : null,
      heightCm: dims ? dims.h : null,
      declaredValue: o.goodsTotal,
      description: `${title}${pack ? ` (${pack})` : ''} × ${o.qty}`.slice(0, 200),
      fragile: false,
    },
    priceSnapshot: snap,
    pricedAt: o.createdAt || null,
    source: 'wholesale',
    extra: { wholesaleOrderId: orderId },
  };
}

/**
 * Buyurtma uchun jo'natma (bor bo'lsa — o'sha). Idempotent: trigger takrori,
 * reconcile va parallel chaqiruv — bitta jo'natma (`createShipmentInternal`
 * kaliti `wholesale_ship_{orderId}`) va bitta bog'lanish (tranzaksiya).
 */
async function ensureWholesaleShipment(deps, orderId) {
  const { db, now: nowFn } = deps;
  const started = Date.now();
  const ref = db.collection(ORDERS).doc(orderId);
  const snap = await ref.get();
  if (!snap.exists) return { skipped: 'order_missing' };
  const o0 = snap.data() || {};
  if (o0.shipment && o0.shipment.shipmentId) return { skipped: 'already_linked', shipmentId: o0.shipment.shipmentId };
  if (o0.status !== WO.STATUS.PLACED) return { skipped: `status_${o0.status || 'none'}` };
  try {
    const name = await buyerDisplayName(db, o0);
    const r = await createShipmentInternal(deps, shipmentInputFromOrder(orderId, o0, name));
    const now = nowFn ? nowFn() : new Date();
    const out = await db.runTransaction(async (tx) => {
      const s = await tx.get(ref);
      const o = s.data() || {};
      if (o.shipment && o.shipment.shipmentId) return { already: true, shipmentId: o.shipment.shipmentId };
      // Orada xaridor bekor qilgan bo'lsa — jo'natma ham bekor (pul tegmagan).
      const cancel = o.status !== WO.STATUS.PLACED
        ? await prepareCancelUnpaidShipmentInTx(tx, db, r.shipmentId) : null;
      const seq = (isInt(o.historySeq) ? o.historySeq : 0) + 1;
      tx.update(ref, {
        shipment: {
          shipmentId: r.shipmentId, orderId: r.orderId, trackingNumber: r.trackingNumber, createdAt: now,
        },
        shipmentError: null,
        historySeq: seq,
        updatedAt: now,
      });
      tx.set(ref.collection(HISTORY).doc(String(seq)), {
        seq, from: o.status, to: o.status, event: 'shipment_created', actor: WO.ACTOR.SYSTEM, actorId: null,
        reason: '', meta: { shipmentId: r.shipmentId, trackingNumber: r.trackingNumber, cancelled: !!cancel }, at: now,
      });
      if (cancel) cancel(now, 'wholesale_order_cancelled');
      return { already: false, shipmentId: r.shipmentId, cancelled: !!cancel };
    });
    log('ensureShipment', {
      result: out.already ? 'already' : 'ok', orderId, shipmentId: out.shipmentId,
      duplicateShipment: r.duplicate, cancelled: !!out.cancelled, durationMs: Date.now() - started,
    });
    return { linked: !out.already, shipmentId: out.shipmentId, trackingNumber: r.trackingNumber, cancelled: !!out.cancelled };
  } catch (e) {
    const code = String((e && e.details && e.details.reason) || (e && e.code) || 'UNKNOWN').slice(0, 64);
    const now = nowFn ? nowFn() : new Date();
    let rec = null;
    try {
      rec = await db.runTransaction(async (tx) => {
        const s = await tx.get(ref);
        const o = s.data() || {};
        if (o.shipment && o.shipment.shipmentId) return null;
        const prev = o.shipmentError && isInt(o.shipmentError.attempts) ? o.shipmentError.attempts : 0;
        const attempts = prev + 1;
        const err = { code, at: now, attempts, final: attempts >= SHIPMENT_MAX_ATTEMPTS };
        tx.update(ref, { shipmentError: err, updatedAt: now });
        return err;
      });
    } catch (e2) {
      rec = null;
    }
    console.error(JSON.stringify({
      module: 'wholesale_orders', action: 'ensureShipment', result: 'failed', orderId,
      errorCode: code, attempts: rec ? rec.attempts : null, final: rec ? rec.final : null,
      message: String((e && e.message) || e).slice(0, 200), durationMs: Date.now() - started,
    }));
    return { failed: true, code, attempts: rec ? rec.attempts : null, final: rec ? rec.final : null };
  }
}

/** Trigger: `wholesale_orders/{id}` onCreate. */
async function onWholesaleOrderCreated(deps, data, orderId) {
  if ((data || {}).status !== WO.STATUS.PLACED) return { skipped: 'not_placed' };
  return ensureWholesaleShipment(deps, orderId);
}

/**
 * Reconcile: `placed` + `shipment == null` (ikki tenglik filtri — yangi kompozit
 * indeks kerak emas) + 2 daqiqadan eski + `final` emas. Har chaqiruv idempotent.
 */
async function reconcileWholesaleShipments(deps, { limit = SHIPMENT_RECONCILE_LIMIT, minAgeMs = SHIPMENT_RECONCILE_MIN_AGE_MS } = {}) {
  const { db, now: nowFn } = deps;
  const nowMs = (nowFn ? nowFn() : new Date()).getTime();
  const out = {
    checked: 0, linked: 0, failed: 0, final: 0, young: 0,
  };
  const snap = await db.collection(ORDERS)
    .where('status', '==', WO.STATUS.PLACED).where('shipment', '==', null).limit(limit).get();
  for (const d of snap.docs) {
    const o = d.data() || {};
    const err = o.shipmentError || null;
    if (err && (err.final === true || (isInt(err.attempts) && err.attempts >= SHIPMENT_MAX_ATTEMPTS))) {
      out.final += 1;
      continue;
    }
    const at = msOf(o.createdAt) || 0;
    if (nowMs - at < minAgeMs) { out.young += 1; continue; } // trigger hali ishlayotgan bo'lishi mumkin
    out.checked += 1;
    const r = await ensureWholesaleShipment(deps, d.id);
    if (r.linked) out.linked += 1;
    else if (r.failed) out.failed += 1;
  }
  log('reconcileShipments', { result: 'ok', ...out });
  return out;
}

/**
 * `getWholesaleDeliveryCode({orderId})` — FAQAT xaridor (`order.buyerId`). Jo'natmaning
 * `private/secrets.qrSecret` dan YETKAZISH kodi — relay `getShipmentSecrets` bilan AYNI
 * hosila (`core/logistics.deliveryCodeFor`; `confirmDelivery` shu bilan tekshiradi).
 * QR/topshirish kodi BERILMAYDI (u jo'natuvchi — sotuvchi ishi). Jo'natma shu buyurtmaniki
 * (`wholesaleOrderId`, `recipientId`) bo'lishi shart. Yakunlangan jo'natma — `shipment_closed`
 * (relay qoidasi bilan bir xil). Log — kodsiz, telefonsiz.
 */
function makeGetWholesaleDeliveryCode(deps) {
  const { db } = deps;
  return async function getWholesaleDeliveryCode(data, context) {
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const orderId = String((data || {}).orderId || '').trim();
    if (!ID_RE.test(orderId)) throw fail('invalid-argument', 'Buyurtma tanlanmagan', 'order_required');
    try {
      const oSnap = await db.collection(ORDERS).doc(orderId).get();
      if (!oSnap.exists) throw fail('not-found', 'Buyurtma topilmadi', 'order_not_found');
      const o = oSnap.data() || {};
      if (!sameUser(o.buyerId, callerId)) throw fail('permission-denied', 'Bu buyurtma sizniki emas', 'not_order_party');
      const shipmentId = String((o.shipment || {}).shipmentId || '');
      if (!shipmentId) throw fail('failed-precondition', 'Yetkazish hali ochilmagan', 'shipment_not_ready');
      const shipRef = db.collection(L.SHIPMENTS).doc(shipmentId);
      const [sSnap, secSnap] = await Promise.all([shipRef.get(), shipRef.collection('private').doc('secrets').get()]);
      if (!sSnap.exists || !secSnap.exists) throw fail('not-found', 'Jo\'natma topilmadi', 'shipment_missing');
      const ship = sSnap.data() || {};
      if (ship.wholesaleOrderId !== orderId || !sameUser(ship.recipientId, callerId)) {
        throw fail('permission-denied', 'Ruxsat yo\'q', 'not_recipient');
      }
      if ([L.SHIPMENT_STATUS.DELIVERED, L.SHIPMENT_STATUS.CLOSED, L.SHIPMENT_STATUS.CANCELLED].includes(ship.status)) {
        throw fail('failed-precondition', 'Jo\'natma yakunlangan', 'shipment_closed');
      }
      const qrSecret = (secSnap.data() || {}).qrSecret;
      log('getDeliveryCode', { result: 'ok', orderId, shipmentId });
      return {
        orderId,
        shipmentId,
        trackingNumber: ship.trackingNumber || '',
        deliveryCode: L.deliveryCodeFor(shipmentId, qrSecret),
      };
    } catch (e) {
      log('getDeliveryCode', { result: 'denied', orderId, errorCode: (e.details && e.details.reason) || e.code || 'UNKNOWN' });
      throw e;
    }
  };
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
  makeCancelWholesaleOrder,
  makeSetWholesaleOrderSettings,
  SHIPMENT_MAX_ATTEMPTS,
  SHIPMENT_RECONCILE_MIN_AGE_MS,
  shipmentInputFromOrder,
  ensureWholesaleShipment,
  onWholesaleOrderCreated,
  reconcileWholesaleShipments,
  makeGetWholesaleDeliveryCode,
};
