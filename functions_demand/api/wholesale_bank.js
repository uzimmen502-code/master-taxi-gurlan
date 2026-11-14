'use strict';

/**
 * ULGURJI — «BANK O'TKAZMASI» (`bank_transfer`, ega qarorlari 2026-11-13/14), demand codebase (europe-west1).
 *
 * Tovar puli ILOVADAN TASHQARIDA (hisob-faktura bo'yicha bank o'tkazmasi). Ilova tovar puliga UMUMAN
 * aralashmaydi (ega, 2026-11-14): ushlamaydi, qaytarmaydi, «tashqarida qaytaring» belgisi/xabari yo'q.
 * Ilova yuritadigani: kuryer haqi (xaridor hamyonidan, default `placeWholesaleOrder`), logistika va
 * sotuvchining «Пул тушди» tasdig'i — jo'natma FAQAT shundan keyin ochiladi (`WO.shipmentAllowed`).
 *
 *   confirmWholesaleBankPayment     sotuvchi: «Пул тушди» — `bankPayment: awaiting → confirmed`
 *                                    (tranzaksiya, idempotent). Jo'natmani demand onUpdate triggeri ochadi
 *                                    (`wholesale_events.onWholesaleOrderUpdated`, kalit `wholesale_ship_{id}`).
 *   wholesaleBankPaymentSweeper     har 15 daqiqa: `awaiting` + `bankPayDeadlineAt <= now` → placed → cancelled
 *                                    (system, `bank_payment_timeout`, `refundStatus: pending` → default
 *                                    `refundOrder` xaridorga ushlangan yetkazish haqini qaytaradi).
 *
 * Pul bu yerda YO'Q (ledger — default codebase). Log — telefon/manzil yo'q (24, 40-band).
 */

const { callerIdFrom, sameUser } = require('../core/ids');
const WO = require('../core/wholesale_orders');
const { prepareCancelInTx } = require('./wholesale_orders');

const ORDERS = 'wholesale_orders';
const HISTORY = 'history';
const ID_RE = /^[A-Za-z0-9_-]{1,128}$/;
const BANK_SWEEP_LIMIT = 200;

function fail(code, message, reason, extra) {
  const e = new Error(message);
  e.code = code;
  e.httpErrorCode = code;
  e.details = { reason: reason || code, ...(extra || {}) };
  return e;
}

const isInt = (n) => typeof n === 'number' && Number.isInteger(n);

function msOf(v) {
  if (v == null) return null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return null;
}

function log(action, fields) {
  console.log(JSON.stringify({ module: 'wholesale_orders', action, ...fields }));
}

/**
 * «Пул тушди» sharti (sof, tranzaksiyada o'qilgan `o` ustida).
 * @returns {null|{idempotent: true}}
 */
function checkBankConfirmState(o, nowMs) {
  if (WO.methodOf(o) !== WO.PAYMENT_METHOD.BANK) {
    throw fail('failed-precondition', 'Buyurtma bank o\'tkazmasi orqali emas', 'not_bank_order');
  }
  const bp = o.bankPayment || {};
  if (bp.status === WO.BANK_PAYMENT.CONFIRMED) return { idempotent: true };
  if (o.status !== WO.STATUS.PLACED) {
    throw fail('failed-precondition', 'Buyurtma endi faol emas', 'order_not_placed', { status: o.status || null });
  }
  if (o.sellerDecision !== WO.SELLER_DECISION.ACCEPTED || !o.acceptedAt) {
    throw fail('failed-precondition', 'Avval buyurtmani qabul qiling', 'seller_not_accepted');
  }
  if (bp.status !== WO.BANK_PAYMENT.AWAITING) {
    throw fail('failed-precondition', 'To\'lov holati mos emas', 'bank_payment_state', { bankPaymentStatus: bp.status || null });
  }
  const deadline = msOf(o.bankPayDeadlineAt);
  // Muddat yo'q/buzilgan — tasdiq qabul qilinmaydi (jimgina «cheksiz» emas, 53-band).
  if (deadline == null) throw fail('failed-precondition', 'To\'lov muddati aniqlanmagan', 'bank_pay_deadline_missing');
  // Muddat o'tgan — buyurtma bekor qilinadi (sweeper); kech tasdiq qabul qilinmaydi (qabul muddati qoidasi bilan bir xil).
  if (nowMs > deadline) throw fail('failed-precondition', 'To\'lov muddati o\'tgan', 'bank_pay_deadline_passed');
  return null;
}

/**
 * `confirmWholesaleBankPayment({orderId})` — FAQAT buyurtma sotuvchisi (`order.sellerId`, kanon tel).
 * Shart: bank buyurtmasi, `placed`, `sellerDecision == accepted`, `bankPayment.status == awaiting`,
 * `now <= bankPayDeadlineAt`. Takror — idempotent (ikkinchi yozuv yo'q). Shundan keyin jo'natma ochiladi.
 */
function makeConfirmWholesaleBankPayment(deps) {
  const { db, now: nowFn } = deps;
  return async function confirmWholesaleBankPayment(data, context) {
    const started = Date.now();
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const orderId = String((data || {}).orderId || '').trim();
    if (!ID_RE.test(orderId)) throw fail('invalid-argument', 'Buyurtma tanlanmagan', 'order_required');
    const ref = db.collection(ORDERS).doc(orderId);
    try {
      const now = nowFn ? nowFn() : new Date();
      const out = await db.runTransaction(async (tx) => {
        const s = await tx.get(ref);
        if (!s.exists) throw fail('not-found', 'Buyurtma topilmadi', 'order_not_found');
        const o = s.data() || {};
        if (!sameUser(o.sellerId, callerId)) throw fail('permission-denied', 'Bu buyurtma sizniki emas', 'not_order_party');
        const idem = checkBankConfirmState(o, now.getTime());
        if (idem) return idem;
        const seq = (isInt(o.historySeq) ? o.historySeq : 0) + 1;
        tx.update(ref, {
          'bankPayment.status': WO.BANK_PAYMENT.CONFIRMED,
          'bankPayment.confirmedAt': now,
          'bankPayment.confirmedBy': callerId,
          historySeq: seq,
          updatedAt: now,
        });
        tx.set(ref.collection(HISTORY).doc(String(seq)), {
          seq, from: o.status, to: o.status, event: 'bank_payment_confirmed', actor: WO.ACTOR.SELLER, actorId: callerId,
          reason: '', meta: { bankPayDeadlineAt: o.bankPayDeadlineAt || null }, at: now,
        });
        return { idempotent: false };
      });
      log('confirmBankPayment', { result: out.idempotent ? 'already' : 'ok', orderId, durationMs: Date.now() - started });
      return {
        ok: true, orderId, bankPaymentStatus: WO.BANK_PAYMENT.CONFIRMED, idempotent: out.idempotent,
      };
    } catch (e) {
      log('confirmBankPayment', {
        result: 'denied', orderId, errorCode: (e.details && e.details.reason) || e.code || 'UNKNOWN', durationMs: Date.now() - started,
      });
      throw e;
    }
  };
}

/**
 * Sweeper: `bankPayment.status == awaiting` + `bankPayDeadlineAt <= now` (kompozit indeks:
 * wholesale_orders (bankPayment.status ASC, bankPayDeadlineAt ASC)). Har buyurtma alohida
 * tranzaksiyada QAYTA tekshiriladi va placed → cancelled (system, `bank_payment_timeout`,
 * `bankPayment.status: timeout`, `refundStatus: pending`). So'rovdan chiqadi — AYNAN BIR MARTA.
 */
async function runWholesaleBankPaymentSweep(deps, { limit = BANK_SWEEP_LIMIT } = {}) {
  const { db, now: nowFn } = deps;
  const started = Date.now();
  const now = nowFn ? nowFn() : new Date();
  const out = {
    checked: 0, cancelled: 0, skipped: 0, failed: 0,
  };
  const snap = await db.collection(ORDERS)
    .where('bankPayment.status', '==', WO.BANK_PAYMENT.AWAITING)
    .where('bankPayDeadlineAt', '<=', now)
    .limit(limit)
    .get();
  for (const d of snap.docs) {
    out.checked += 1;
    try {
      const r = await db.runTransaction(async (tx) => {
        const s = await tx.get(d.ref);
        if (!s.exists) return { skipped: true };
        const o = s.data() || {};
        const deadline = msOf(o.bankPayDeadlineAt);
        if (WO.methodOf(o) !== WO.PAYMENT_METHOD.BANK || o.status !== WO.STATUS.PLACED
          || (o.bankPayment || {}).status !== WO.BANK_PAYMENT.AWAITING
          || deadline == null || deadline > now.getTime()) {
          return { skipped: true };
        }
        const write = await prepareCancelInTx(tx, db, d.ref, o, {
          actor: WO.ACTOR.SYSTEM,
          actorId: null,
          reason: WO.CANCEL_REASON.BANK_PAYMENT_TIMEOUT,
          event: 'bank_payment_timeout',
          historyMeta: { bankPayDeadlineAt: o.bankPayDeadlineAt || null },
          extraPatch: {
            cancelReason: WO.CANCEL_REASON.BANK_PAYMENT_TIMEOUT,
            'bankPayment.status': WO.BANK_PAYMENT.TIMEOUT,
            'bankPayment.timeoutAt': now,
          },
        });
        write(now);
        return { skipped: false };
      });
      if (r.skipped) out.skipped += 1;
      else out.cancelled += 1;
    } catch (e) {
      out.failed += 1;
      console.error(JSON.stringify({
        module: 'wholesale_orders', action: 'bankPaymentSweep', result: 'failed', orderId: d.id,
        errorCode: 'BANK_PAYMENT_SWEEP_FAILED', message: String((e && e.message) || e).slice(0, 200),
      }));
    }
  }
  log('bankPaymentSweep', { result: 'ok', ...out, durationMs: Date.now() - started });
  return out;
}

module.exports = {
  BANK_SWEEP_LIMIT,
  checkBankConfirmState,
  makeConfirmWholesaleBankPayment,
  runWholesaleBankPaymentSweep,
};
