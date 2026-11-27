'use strict';

/**
 * ULGURJI — SOTUVCHINING O'Z YETKAZISHI (S4, ega CONFIRMED 2026-11-13/14), demand codebase (europe-west1).
 *
 * Sotuvchi sozlamasi `wholesale_sellers/{tel}.selfDelivery = {enabled, coverage, dropoff}` (o'zi yozadi, Rules
 * shaklni tekshiradi). Kvota (`quoteWholesaleOrder`, `deliveryMethod: 'self'`) — deliveryFee 0 (narx tovar ichida),
 * relay jo'natmasi HECH QACHON ochilmaydi (`WO.shipmentAllowed` false). Qabul/rad — umumiy (`acceptWholesaleOrder`).
 *
 *   startWholesaleSelfDelivery({orderId})          sotuvchi: placed → in_delivery (qabuldan keyin; bank — «Пул тушди»
 *                                                   dan keyin). Yetkazish kodi siri yaratiladi (`private/self_delivery`).
 *   completeWholesaleSelfDelivery({orderId, code}) sotuvchi xaridorning yetkazish kodini kiritadi → `selfDelivery.status:
 *                                                   completed`. Holat `delivered` ni (pul bilan BITTA tranzaksiyada) default
 *                                                   codebase yozadi (`releaseSelf`). Karta: kod faqat «Пул тушди» dan keyin.
 *   markWholesaleSelfDeliveryRefused({orderId, reason}) sotuvchi: in_delivery → refused (`refundStatus: pending`):
 *                                                   hamyon — tovar summasi xaridorga (default); karta/bank — ilova tovar
 *                                                   puliga tegmaydi (ega qoidasi).
 *   completeWholesaleSelfReturn({orderId})          sotuvchi: tovar qaytdi — refused → returned + qoldiq +N (pul hisob-kitobi
 *                                                   `refundStatus: done` bo'lgach).
 *
 * Yetkazish kodi — relay bilan AYNI hosila (`core/logistics.deliveryCodeFor` / `verifyDeliveryCode`), «jo'natma ID»
 * o'rnida `wsself:{orderId}`; sir — `wholesale_orders/{id}/private/self_delivery.secret` (klientga yopiq: Rules'da
 * `private` subkolleksiyasiga qoida yo'q = rad). Xato urinishlar cheklovi — relay `registerFailedCodeAttempt` (5 xato →
 * 15 daqiqa qulf, standart qiymatlar).
 *
 * Boshlash muddati (qabuldan keyin N ish kuni) — YO'Q (PROPOSED: hozircha timeout qo'yilmaydi).
 * Xaridor rad hisoblagichi (`cardRefusals`) o'z yetkazishida OSHIRILMAYDI — radni sotuvchi yolg'iz belgilaydi
 * (xaridor tasdig'i yo'q), hisoblagich uning karta usulini yopib qo'yishi mumkin edi (PROPOSED, ega tasdig'i kerak).
 * Log — kodsiz, telefonsiz (24, 40-band).
 */

const { callerIdFrom, sameUser } = require('../core/ids');
const L = require('../core/logistics');
const WO = require('../core/wholesale_orders');
const { STOCK } = require('./wholesale_stock');

const ORDERS = 'wholesale_orders';
const HISTORY = 'history';
const PRIVATE = 'private';
const SECRET_DOC = 'self_delivery';
const ID_RE = /^[A-Za-z0-9_-]{1,128}$/;
const CODE_RE = /^\d{6}$/;

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
  console.log(JSON.stringify({ module: 'wholesale_self', action, ...fields }));
}

function denied(action, orderId, e, started) {
  log(action, {
    result: 'denied', orderId, errorCode: (e && e.details && e.details.reason) || (e && e.code) || 'UNKNOWN', durationMs: Date.now() - started,
  });
}

/** Yetkazish kodi (sof): relay hosilasi, «jo'natma ID» = `wsself:{orderId}`. */
const selfCodeKey = (orderId) => `wsself:${orderId}`;
const selfDeliveryCodeFor = (orderId, secret) => L.deliveryCodeFor(selfCodeKey(orderId), secret);

function requireOrderId(data) {
  const orderId = String((data || {}).orderId || '').trim();
  if (!ID_RE.test(orderId)) throw fail('invalid-argument', 'Buyurtma tanlanmagan', 'order_required');
  return orderId;
}

/** Umumiy: buyurtma bor, chaqiruvchi — uning SOTUVCHISI, o'z yetkazishi buyurtmasi. */
function assertSellerSelf(s, callerId) {
  if (!s.exists) throw fail('not-found', 'Buyurtma topilmadi', 'order_not_found');
  const o = s.data() || {};
  if (!sameUser(o.sellerId, callerId)) throw fail('permission-denied', 'Bu buyurtma sizniki emas', 'not_order_party');
  if (!WO.isSelf(o)) throw fail('failed-precondition', 'Bu buyurtmani AVA kuryeri yetkazadi', 'not_self_delivery');
  return o;
}

function writeHistory(tx, ref, o, entry, now) {
  const seq = (isInt(o.historySeq) ? o.historySeq : 0) + 1;
  tx.set(ref.collection(HISTORY).doc(String(seq)), { seq, reason: '', at: now, ...entry });
  return seq;
}

/** Yetkazish boshlanishi mumkinmi (sof): qabul qilingan; bank — tovar puli tasdiqlangan. */
function startBlockedReason(o) {
  if (o.sellerDecision !== WO.SELLER_DECISION.ACCEPTED || !o.acceptedAt) return 'seller_not_accepted';
  if (WO.methodOf(o) === WO.PAYMENT_METHOD.BANK) {
    const bp = o.bankPayment || {};
    if (bp.status !== WO.BANK_PAYMENT.CONFIRMED || !bp.confirmedAt) return 'bank_payment_unconfirmed';
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════
// 1. BOSHLASH
// ═══════════════════════════════════════════════════════════════════════

function makeStartWholesaleSelfDelivery(deps) {
  const { db, now: nowFn } = deps;
  return async function startWholesaleSelfDelivery(data, context) {
    const started = Date.now();
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const orderId = requireOrderId(data);
    const ref = db.collection(ORDERS).doc(orderId);
    const secretRef = ref.collection(PRIVATE).doc(SECRET_DOC);
    try {
      const now = nowFn ? nowFn() : new Date();
      const out = await db.runTransaction(async (tx) => {
        const [s, sec] = await Promise.all([tx.get(ref), tx.get(secretRef)]);
        const o = assertSellerSelf(s, callerId);
        // 21-band: takror — xato emas, ikkinchi yozuv yo'q.
        if (o.status === WO.STATUS.IN_DELIVERY && (o.selfDelivery || {}).status === WO.SELF_STATUS.IN_DELIVERY) {
          return { idempotent: true };
        }
        if (o.status !== WO.STATUS.PLACED) {
          throw fail('failed-precondition', 'Buyurtma holati mos emas', 'order_not_placed', { status: o.status || null });
        }
        const why = startBlockedReason(o);
        if (why) throw fail('failed-precondition', 'Yetkazishni hozir boshlab bo\'lmaydi', why);
        WO.assertTransition(WO.ACTOR.SELLER, o.status, WO.STATUS.IN_DELIVERY);
        const seq = writeHistory(tx, ref, o, {
          from: o.status, to: WO.STATUS.IN_DELIVERY, event: 'self_delivery_started', actor: WO.ACTOR.SELLER, actorId: callerId,
          meta: { deliveryMethod: WO.DELIVERY_METHOD.SELF, dropoff: (o.selfDelivery || {}).dropoff || null },
        }, now);
        tx.update(ref, {
          status: WO.STATUS.IN_DELIVERY,
          statusUpdatedAt: now,
          updatedAt: now,
          historySeq: seq,
          'selfDelivery.status': WO.SELF_STATUS.IN_DELIVERY,
          'selfDelivery.startedAt': now,
          'selfDelivery.startedBy': callerId,
        });
        // Sir bir marta yaratiladi (bor bo'lsa — o'zgarmaydi: kod xaridorda allaqachon ko'ringan bo'lishi mumkin).
        if (!sec.exists || !(sec.data() || {}).secret) {
          tx.set(secretRef, {
            secret: L.newQrSecret(), createdAt: now, fails: 0, lastFailAt: null, lockedUntil: null,
          });
        }
        return { idempotent: false };
      });
      log('startSelfDelivery', { result: out.idempotent ? 'already' : 'ok', orderId, durationMs: Date.now() - started });
      return {
        ok: true, orderId, status: WO.STATUS.IN_DELIVERY, idempotent: out.idempotent,
      };
    } catch (e) {
      denied('startSelfDelivery', orderId, e, started);
      throw e;
    }
  };
}

// ═══════════════════════════════════════════════════════════════════════
// 2. YAKUNLASH — xaridor kodi
// ═══════════════════════════════════════════════════════════════════════

function makeCompleteWholesaleSelfDelivery(deps) {
  const { db, now: nowFn } = deps;
  return async function completeWholesaleSelfDelivery(data, context) {
    const started = Date.now();
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const orderId = requireOrderId(data);
    const code = String((data || {}).code == null ? '' : data.code).trim();
    if (!CODE_RE.test(code)) throw fail('invalid-argument', 'Kod 6 ta raqam', 'code_format');
    const ref = db.collection(ORDERS).doc(orderId);
    const secretRef = ref.collection(PRIVATE).doc(SECRET_DOC);
    try {
      const now = nowFn ? nowFn() : new Date();
      const limits = L.codeAttemptLimits({});
      const out = await db.runTransaction(async (tx) => {
        const [s, sec] = await Promise.all([tx.get(ref), tx.get(secretRef)]);
        const o = assertSellerSelf(s, callerId);
        const sd = o.selfDelivery || {};
        if (sd.status === WO.SELF_STATUS.COMPLETED || o.status === WO.STATUS.DELIVERED) return { idempotent: true };
        if (o.status !== WO.STATUS.IN_DELIVERY || sd.status !== WO.SELF_STATUS.IN_DELIVERY) {
          throw fail('failed-precondition', 'Buyurtma yetkazilmoqda emas', 'order_not_in_delivery', { status: o.status || null });
        }
        // Karta: kod xaridorga faqat «Пул тушди» dan keyin ko'rinadi — yakunlash ham shundan keyin.
        if (WO.methodOf(o) === WO.PAYMENT_METHOD.CARD && (o.cardPayment || {}).status !== WO.CARD_PAYMENT.CONFIRMED) {
          throw fail('failed-precondition', 'Avval to\'lov tushganini tasdiqlang', 'card_payment_unconfirmed');
        }
        const sd2 = sec.exists ? (sec.data() || {}) : {};
        if (!sd2.secret) throw fail('failed-precondition', 'Yetkazish kodi tayyor emas', 'code_not_ready');
        const lockMs = L.codeLockRemainingMs(sd2, now);
        if (lockMs > 0) return { locked: true, retryAfterSec: Math.ceil(lockMs / 1000) };
        if (!L.verifyDeliveryCode(selfCodeKey(orderId), sd2.secret, code)) {
          // Xato urinish — hisoblagich SAQLANADI (tranzaksiya commit bo'ladi), xato tashqarida.
          const next = L.registerFailedCodeAttempt(sd2, now, limits);
          tx.update(secretRef, next);
          return { wrong: true, locked: !!next.lockedUntil, left: Math.max(0, limits.maxFailed - next.fails) };
        }
        const seq = writeHistory(tx, ref, o, {
          from: o.status, to: o.status, event: 'self_delivery_completed', actor: WO.ACTOR.SELLER, actorId: callerId,
          meta: { deliveryMethod: WO.DELIVERY_METHOD.SELF, proof: 'delivery_code' },
        }, now);
        tx.update(ref, {
          'selfDelivery.status': WO.SELF_STATUS.COMPLETED,
          'selfDelivery.completedAt': now,
          'selfDelivery.completedBy': callerId,
          historySeq: seq,
          updatedAt: now,
        });
        tx.update(secretRef, { fails: 0, lockedUntil: null, usedAt: now });
        return { completed: true };
      });
      if (out.wrong) {
        log('completeSelfDelivery', { result: 'wrong_code', orderId, locked: out.locked, durationMs: Date.now() - started });
        throw fail('invalid-argument', 'Kod noto\'g\'ri', 'delivery_code_invalid', { attemptsLeft: out.left });
      }
      if (out.locked) {
        log('completeSelfDelivery', { result: 'locked', orderId, durationMs: Date.now() - started });
        throw fail('resource-exhausted', 'Juda ko\'p xato urinish. Keyinroq qayta urinib ko\'ring', 'code_locked', { retryAfterSec: out.retryAfterSec });
      }
      log('completeSelfDelivery', { result: out.idempotent ? 'already' : 'ok', orderId, durationMs: Date.now() - started });
      return {
        ok: true, orderId, selfDeliveryStatus: WO.SELF_STATUS.COMPLETED, idempotent: !!out.idempotent,
      };
    } catch (e) {
      if (!(e && e.details && ['delivery_code_invalid', 'code_locked'].includes(e.details.reason))) denied('completeSelfDelivery', orderId, e, started);
      throw e;
    }
  };
}

// ═══════════════════════════════════════════════════════════════════════
// 3. RAD (eshik oldida)
// ═══════════════════════════════════════════════════════════════════════

function makeMarkWholesaleSelfDeliveryRefused(deps) {
  const { db, now: nowFn } = deps;
  return async function markWholesaleSelfDeliveryRefused(data, context) {
    const started = Date.now();
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const orderId = requireOrderId(data);
    const raw = (data || {}).reason;
    const reason = typeof raw === 'string' ? raw.trim() : '';
    if (reason.length < WO.REJECT_REASON_MIN || reason.length > WO.REJECT_REASON_MAX) {
      throw fail('invalid-argument', `Sababni yozing (${WO.REJECT_REASON_MIN}–${WO.REJECT_REASON_MAX} belgi)`, 'reason_invalid', {
        min: WO.REJECT_REASON_MIN, max: WO.REJECT_REASON_MAX,
      });
    }
    const ref = db.collection(ORDERS).doc(orderId);
    try {
      const now = nowFn ? nowFn() : new Date();
      const out = await db.runTransaction(async (tx) => {
        const s = await tx.get(ref);
        const o = assertSellerSelf(s, callerId);
        if (o.status === WO.STATUS.REFUSED && (o.refusal || {}).via === 'self_delivery') return { idempotent: true };
        const sd = o.selfDelivery || {};
        if (o.status !== WO.STATUS.IN_DELIVERY || sd.status !== WO.SELF_STATUS.IN_DELIVERY) {
          throw fail('failed-precondition', 'Buyurtma yetkazilmoqda emas', 'order_not_in_delivery', { status: o.status || null });
        }
        // Karta: sotuvchi «Пул тушди» bosgan — xaridor to'lagan, rad emas (yetkazishni yakunlang).
        if (WO.methodOf(o) === WO.PAYMENT_METHOD.CARD && (o.cardPayment || {}).status === WO.CARD_PAYMENT.CONFIRMED) {
          throw fail('failed-precondition', 'To\'lov tasdiqlangan — yetkazishni yakunlang', 'card_payment_confirmed');
        }
        WO.assertTransition(WO.ACTOR.SELLER, o.status, WO.STATUS.REFUSED);
        const seq = writeHistory(tx, ref, o, {
          from: o.status, to: WO.STATUS.REFUSED, event: 'self_delivery_refused', actor: WO.ACTOR.SELLER, actorId: callerId, reason,
          meta: { deliveryMethod: WO.DELIVERY_METHOD.SELF, paymentMethod: WO.methodOf(o) },
        }, now);
        tx.update(ref, {
          status: WO.STATUS.REFUSED,
          refundStatus: WO.REFUND_STATUS.PENDING,
          refusedAt: now,
          statusUpdatedAt: now,
          updatedAt: now,
          historySeq: seq,
          refusal: {
            by: callerId, via: 'self_delivery', reason, at: now, shipmentId: null, legId: null,
          },
          'selfDelivery.status': WO.SELF_STATUS.REFUSED,
          'selfDelivery.refusedAt': now,
        });
        return { idempotent: false };
      });
      // Log — sabab matnisiz (erkin matnda shaxsiy ma'lumot bo'lishi mumkin).
      log('markSelfRefused', { result: out.idempotent ? 'already' : 'ok', orderId, durationMs: Date.now() - started });
      return {
        ok: true, orderId, status: WO.STATUS.REFUSED, idempotent: out.idempotent,
      };
    } catch (e) {
      denied('markSelfRefused', orderId, e, started);
      throw e;
    }
  };
}

// ═══════════════════════════════════════════════════════════════════════
// 4. TOVAR QAYTDI — qoldiq +N
// ═══════════════════════════════════════════════════════════════════════

function makeCompleteWholesaleSelfReturn(deps) {
  const { db, now: nowFn } = deps;
  return async function completeWholesaleSelfReturn(data, context) {
    const started = Date.now();
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const orderId = requireOrderId(data);
    const ref = db.collection(ORDERS).doc(orderId);
    try {
      const now = nowFn ? nowFn() : new Date();
      const out = await db.runTransaction(async (tx) => {
        const s = await tx.get(ref);
        const o = assertSellerSelf(s, callerId);
        if (o.status === WO.STATUS.RETURNED) return { idempotent: true, stockRestored: false };
        if (o.status !== WO.STATUS.REFUSED) {
          throw fail('failed-precondition', 'Buyurtma rad etilmagan', 'order_not_refused', { status: o.status || null });
        }
        // Pul hisob-kitobi (hamyon: tovar summasi xaridorga) tugamagan — `returned` ga o'tib bo'lmaydi
        // (default `refundOrder` faqat `refused` holatida ishlaydi).
        if (o.refundStatus !== WO.REFUND_STATUS.DONE) {
          throw fail('failed-precondition', 'Hisob-kitob hali tugamagan. Birozdan keyin qayta urinib ko\'ring', 'refund_pending');
        }
        WO.assertTransition(WO.ACTOR.SELLER, o.status, WO.STATUS.RETURNED);
        const so = o.stock || {};
        const restore = so.decremented === true && so.restored !== true
          && isPosInt(so.qty) && typeof so.packId === 'string' && so.packId !== '';
        const stockRef = db.collection(STOCK).doc(String(o.productId || '_'));
        const ss = restore ? await tx.get(stockRef) : null;
        if (restore) {
          // Default `writeStockRestore` bilan AYNI shakl (versiya + history `order_return`).
          const st = ss && ss.exists ? (ss.data() || {}) : {};
          const packs = st.packs && typeof st.packs === 'object' ? st.packs : {};
          const cur = isInt(packs[so.packId]) && packs[so.packId] >= 0 ? packs[so.packId] : 0;
          const nextPacks = { ...packs, [so.packId]: cur + so.qty };
          const version = (isInt(st.version) ? st.version : 0) + 1;
          tx.set(stockRef, {
            productId: String(o.productId), sellerId: String(st.sellerId || o.sellerId || ''), packs: nextPacks, version, updatedAt: now,
          });
          tx.set(stockRef.collection(HISTORY).doc(`v${version}`), {
            kind: 'order_return', from: packs, to: nextPacks, packId: so.packId, qty: so.qty, orderId, by: 'seller', at: now, version,
          });
        }
        const seq = writeHistory(tx, ref, o, {
          from: o.status, to: WO.STATUS.RETURNED, event: 'goods_returned', actor: WO.ACTOR.SELLER, actorId: callerId,
          meta: { deliveryMethod: WO.DELIVERY_METHOD.SELF, stockRestored: restore },
        }, now);
        tx.update(ref, {
          status: WO.STATUS.RETURNED,
          returnedAt: now,
          statusUpdatedAt: now,
          updatedAt: now,
          historySeq: seq,
          returnStatus: WO.RETURN_STATUS.RETURNED,
          'selfDelivery.status': WO.SELF_STATUS.RETURNED,
          'selfDelivery.returnedAt': now,
          'stock.restored': restore || so.restored === true,
          'stock.restoredAt': restore ? now : (so.restoredAt || null),
        });
        return { idempotent: false, stockRestored: restore };
      });
      log('completeSelfReturn', {
        result: out.idempotent ? 'already' : 'ok', orderId, stockRestored: out.stockRestored, durationMs: Date.now() - started,
      });
      return {
        ok: true, orderId, status: WO.STATUS.RETURNED, stockRestored: out.stockRestored, idempotent: out.idempotent,
      };
    } catch (e) {
      denied('completeSelfReturn', orderId, e, started);
      throw e;
    }
  };
}

module.exports = {
  SECRET_DOC,
  selfCodeKey,
  selfDeliveryCodeFor,
  startBlockedReason,
  makeStartWholesaleSelfDelivery,
  makeCompleteWholesaleSelfDelivery,
  makeMarkWholesaleSelfDeliveryRefused,
  makeCompleteWholesaleSelfReturn,
};
