'use strict';

/**
 * ULGURJI buyurtma hodisalari (3b, demand codebase): `wholesale_orders/{id}` onUpdate
 * triggeri `onWholesaleOrderUpdated` uchun mantiq.
 *
 *   1) `refused` + qaytish jo'natmasi yo'q → `ensureWholesaleReturnShipment` (narx muhri, LEG-1
 *      posilka qo'lidagi kuryerga). Yiqilsa — `wholesaleShipmentReconcile` qayta urinadi.
 *   2) Holat/to'lov o'tishlari bo'yicha xabarlar (in-app + push, 3 til) — `transitionNotifications`
 *      (sof funksiya, testlanadi). Har xabar idempotent (`wholesale_notify` deterministik ID).
 *
 *   3) Sotuvchi qabul qildi (ega, 2026-11-13; `pending → accepted`) → `ensureWholesaleShipment`.
 *
 * Yangi buyurtma haqida sotuvchiga «qabul qiling» xabari — onCreate (`notifySellerDecide`,
 * `onWholesaleOrderCreated` dan). Karta buyurtmasi xabari (`ws_card_new_order`) — qabuldan keyin;
 * `notifyNewCardOrder` (eski onCreate yo'li) testlar va moslik uchun saqlanadi.
 *
 * Pul — bu yerda YO'Q (default codebase `onWholesaleOrderStatusChange`).
 */

const WO = require('../core/wholesale_orders');
const notify = require('../notify/wholesale_notify');
const { ensureWholesaleReturnShipment } = require('./wholesale_return');

const cpStatus = (o) => ((o || {}).cardPayment || {}).status || null;
const changedTo = (b, a, v) => (b || {}).status !== v && (a || {}).status === v;
const AFTER_REFUSAL = [WO.STATUS.REFUSED, WO.STATUS.RETURNING, WO.STATUS.RETURNED];

/**
 * Karta buyurtmasi rad etilganda xaridor xabari — SABABGA qarab (ega, 2026-11-01). Admin nizoni rad etgan
 * (`via: admin_dispute`) yoki sabab kodi yo'q eski yozuv — avvalgi `ws_refused_buyer` («тўлов амалга ошмади»).
 */
function refusedBuyerKey(o) {
  const r = (o || {}).refusal || {};
  // Eski kuryer APK («Харидор тўламади» tugmasi, sabab kodi yo'q → `deliveryFailed.legacyClient`) — avvalgi ma'no.
  const legacy = ((o || {}).deliveryFailed || {}).legacyClient === true;
  if (r.via === 'admin_dispute' || !r.reasonCode || legacy) return 'ws_refused_buyer';
  return {
    customer_absent: 'ws_refused_buyer_absent',
    customer_refused: 'ws_refused_buyer_refused',
    courier_problem: 'ws_refused_buyer_courier',
  }[r.reasonCode] || 'ws_refused_buyer_other';
}

/**
 * Qaysi xabarlar yuborilishi kerak (before → after). Qabul qiluvchi: seller | buyer | admins | courier.
 * @returns {Array<{to: string, key: string}>}
 */
function transitionNotifications(before, after) {
  const b = before || {};
  const a = after || {};
  const out = [];
  // Sotuvchi qabuli (ega, 2026-11-13). Karta buyurtmasi haqidagi sotuvchi xabari endi qabuldan keyin
  // (yaratilganda — `ws_seller_decide`). Bekor qilish sababi `cancelReason` dan.
  if (b.sellerDecision !== WO.SELLER_DECISION.ACCEPTED && a.sellerDecision === WO.SELLER_DECISION.ACCEPTED) {
    out.push({ to: 'buyer', key: 'ws_seller_accepted_buyer' });
    if (WO.methodOf(a) === WO.PAYMENT_METHOD.CARD) out.push({ to: 'seller', key: 'ws_card_new_order' });
  }
  if (changedTo(b, a, WO.STATUS.CANCELLED)) {
    if (a.cancelReason === WO.CANCEL_REASON.SELLER_REJECTED) out.push({ to: 'buyer', key: 'ws_seller_rejected_buyer' });
    if (a.cancelReason === WO.CANCEL_REASON.SELLER_TIMEOUT) {
      out.push({ to: 'buyer', key: 'ws_seller_timeout_buyer' }, { to: 'seller', key: 'ws_seller_timeout_seller' });
    }
  }
  if (WO.methodOf(a) === WO.PAYMENT_METHOD.CARD) {
    if (cpStatus(b) !== WO.CARD_PAYMENT.RECEIPT_SUBMITTED && cpStatus(a) === WO.CARD_PAYMENT.RECEIPT_SUBMITTED) {
      out.push({ to: 'seller', key: 'ws_card_receipt' });
    }
    if (cpStatus(b) !== WO.CARD_PAYMENT.CONFIRMED && cpStatus(a) === WO.CARD_PAYMENT.CONFIRMED) {
      out.push({ to: 'buyer', key: 'ws_card_confirmed' });
    }
  }
  const isWallet = WO.methodOf(a) === WO.PAYMENT_METHOD.WALLET;
  if (changedTo(b, a, WO.STATUS.REFUSED)) {
    // Hamyon: xaridorga xabar pul hisoblangach (summalar bilan, pastda); sotuvchi qaytish haqini to'lamaydi.
    if (isWallet) out.push({ to: 'seller', key: 'ws_refused_seller_wallet' });
    else out.push({ to: 'buyer', key: refusedBuyerKey(a) }, { to: 'seller', key: 'ws_refused_seller' });
  }
  if (isWallet && b.refundStatus !== WO.REFUND_STATUS.DONE && a.refundStatus === WO.REFUND_STATUS.DONE
    && AFTER_REFUSAL.includes(a.status) && a.walletRefusal) {
    out.push({ to: 'buyer', key: a.walletRefusal.fault === 'courier' ? 'ws_refused_buyer_wallet_courier' : 'ws_refused_buyer_wallet' });
  }
  if (isWallet && ((b.returnPayment || {}).status !== 'funded') && (a.returnPayment || {}).status === 'funded'
    && (a.returnPayment || {}).payer === 'courier' && !a.courierReturnDebt) {
    out.push({ to: 'refusal_courier', key: 'ws_return_fee_courier' });
  }
  // Kuryer hamyoni yetmadi (ega, 2026-11-01): qolgani kuryer qarziga yozildi, AVA vaqtincha to'ladi, qaytish darhol.
  if (isWallet && !b.courierReturnDebt && a.courierReturnDebt) {
    out.push({ to: 'refusal_courier', key: 'ws_return_courier_debt' }, { to: 'admins', key: 'ws_return_courier_debt_admin' });
  }
  if (changedTo(b, a, WO.STATUS.PAYMENT_DISPUTE)) out.push({ to: 'admins', key: 'ws_dispute_admin' });
  if (!b.returnDebt && a.returnDebt) {
    // Qarzdor: karta — sotuvchi (avvalgidek); hamyon — xaridor yoki mas'ul kuryer (`returnDebt.payer`).
    const payer = (a.returnDebt || {}).payer;
    if (payer === 'buyer') out.push({ to: 'buyer', key: 'ws_return_debt_buyer' }, { to: 'admins', key: 'ws_return_debt_admin_buyer' });
    else if (payer === 'courier') out.push({ to: 'refusal_courier', key: 'ws_return_debt_courier' }, { to: 'admins', key: 'ws_return_debt_admin_courier' });
    else out.push({ to: 'seller', key: 'ws_return_debt_seller' }, { to: 'admins', key: 'ws_return_debt_admin' });
  }
  if (!((b.returnShipment || {}).shipmentId) && (a.returnShipment || {}).courierId) {
    out.push({ to: 'courier', key: 'ws_return_courier' });
  }
  if (changedTo(b, a, WO.STATUS.RETURNING)) out.push({ to: 'seller', key: 'ws_returning_seller' });
  if (changedTo(b, a, WO.STATUS.RETURNED)) out.push({ to: 'seller', key: 'ws_returned_seller' });
  // Yo'qolgan posilka (ega, 2026-10-31): default `settleLost` yozgan to'lov holatiga qarab.
  if (changedTo(b, a, WO.STATUS.LOST)) {
    if ((a.payment || {}).status === WO.LOST_PAYMENT.REVIEW) {
      out.push({ to: 'buyer', key: 'ws_lost_buyer_review' }, { to: 'seller', key: 'ws_lost_seller' },
        { to: 'admins', key: 'ws_lost_review_admin' });
    } else if (WO.methodOf(a) === WO.PAYMENT_METHOD.CARD) {
      out.push({ to: 'buyer', key: 'ws_lost_buyer_card' }, { to: 'seller', key: 'ws_lost_seller' });
    } else {
      // Hamyon: yetkazish haqi ham qaytadi (ega, 2026-10-31). `lost.deliveryFeeRefunded` yo'q (eski server)
      // yoki haq anomaliyasi — eski matn (faqat tovar puli); qoldiq bo'lsa — qisman matn + adminlarga.
      const l = a.lost || {};
      const outstanding = Number.isInteger(l.deliveryFeeOutstanding) ? l.deliveryFeeOutstanding : 0;
      let key = 'ws_lost_buyer_wallet';
      if (Number.isInteger(l.deliveryFeeRefunded) && !l.deliveryFeeAnomaly) {
        key = outstanding > 0 ? 'ws_lost_buyer_wallet_partial' : 'ws_lost_buyer_wallet_full';
      }
      out.push({ to: 'buyer', key }, { to: 'seller', key: 'ws_lost_seller' });
      if (outstanding > 0 || l.deliveryFeeAnomaly) out.push({ to: 'admins', key: 'ws_lost_fee_admin' });
    }
  }
  // Admin kuryer to'lovini yozib, yetkazish haqi qoldig'i 0 ga tushdi — xaridorga.
  const feeLeft = (o) => (Number.isInteger(((o || {}).lost || {}).deliveryFeeOutstanding) ? o.lost.deliveryFeeOutstanding : 0);
  if (b.status === WO.STATUS.LOST && a.status === WO.STATUS.LOST && feeLeft(b) > 0 && feeLeft(a) === 0
    && Number.isInteger((a.lost || {}).deliveryFeeOutstanding)) {
    out.push({ to: 'buyer', key: 'ws_lost_fee_done_buyer' });
  }
  return out;
}

/** Qaror muddati — Toshkent vaqtida «dd.MM HH:mm» (Asia/Tashkent, UTC+5); yo'q — bo'sh. */
function deadlineText(v) {
  let ms = null;
  if (v && typeof v.toMillis === 'function') ms = v.toMillis();
  else if (v instanceof Date) ms = v.getTime();
  if (ms == null || !Number.isFinite(ms)) return '';
  const d = new Date(ms + WO.TASHKENT_OFFSET_MS);
  const p = (n) => String(n).padStart(2, '0');
  return `${p(d.getUTCDate())}.${p(d.getUTCMonth() + 1)} ${p(d.getUTCHours())}:${p(d.getUTCMinutes())}`;
}

function paramsOf(o, orderId) {
  const rs = o.returnShipment || {};
  const debt = o.returnDebt || {};
  const wr = o.walletRefusal || {};
  const cd = o.courierReturnDebt || {};
  return {
    orderId,
    product: String(o.productTitle || '').slice(0, 60),
    qty: o.qty,
    amount: Number.isInteger(o.goodsTotal) && Number.isInteger(o.deliveryFee) ? o.goodsTotal + o.deliveryFee : '',
    tracking: rs.trackingNumber || '',
    ...(Number.isInteger(debt.amount) ? { amount: debt.amount } : {}),
    // Yo'qolish: xaridorga qaytgan summa (hamyon — goodsTotal + qaytgan yetkazish haqi); hamyon radda — qaytgan tovar summasi.
    // {left} (haq qoldig'i), {fee} (yetkazish haqi) faqat lost; {returnFee} faqat hamyon rad xabarlarida.
    refund: Number.isInteger((o.payment || {}).lostRefund)
      ? o.payment.lostRefund + (Number.isInteger(o.payment.lostFeeRefund) ? o.payment.lostFeeRefund : 0)
      : (Number.isInteger(wr.goodsRefunded) ? wr.goodsRefunded : ''),
    left: Number.isInteger((o.lost || {}).deliveryFeeOutstanding) ? o.lost.deliveryFeeOutstanding : '',
    fee: Number.isInteger((o.lost || {}).deliveryFee) ? o.lost.deliveryFee : '',
    returnFee: Number.isInteger(wr.returnFeeCharged) ? wr.returnFeeCharged : '',
    // Kuryer qarzi (default `courierReturnDebt`): qaytish narxi jami va qarzga yozilgan qism.
    returnFeeTotal: Number.isInteger(cd.returnFee) ? cd.returnFee : '',
    courierDebt: Number.isInteger(cd.amount) ? cd.amount : '',
    deadline: deadlineText(o.acceptDeadlineAt),
  };
}

async function deliver(deps, orderId, o, items) {
  const params = paramsOf(o, orderId);
  const res = [];
  for (const it of items) {
    try {
      let r;
      if (it.to === 'admins') r = await notify.notifyAdmins(deps, { key: it.key, params, orderId });
      else {
        const uid = it.to === 'seller' ? o.sellerId
          : it.to === 'buyer' ? o.buyerId
            // Hamyon rad, kuryer aybi: «етказилмади» ni bosgan (mas'ul) kuryer — default `refusal.by` dan to'lovchi.
            : it.to === 'refusal_courier' ? (o.refusal || {}).by
              : (o.returnShipment || {}).courierId;
        r = await notify.notifyUser(deps, { uid, key: it.key, params, orderId });
      }
      res.push({ ...it, ...r });
    } catch (e) {
      console.error(JSON.stringify({
        module: 'wholesale_orders', action: 'notify', result: 'failed', orderId, key: it.key, errorCode: 'NOTIFY_FAILED',
        message: String((e && e.message) || e).slice(0, 200),
      }));
      res.push({ ...it, failed: true });
    }
  }
  return res;
}

/** Trigger: `wholesale_orders/{id}` onUpdate. */
async function onWholesaleOrderUpdated(deps, before, after, orderId) {
  const a = after || {};
  const out = {};
  // Xato belgisi bor bo'lsa trigger QAYTA urinmaydi (belgi yozuvi shu triggerni yana
  // chaqiradi — aylanish bo'lmasin); qayta urinish — `wholesaleShipmentReconcile`.
  if (a.status === WO.STATUS.REFUSED && !((a.returnShipment || {}).shipmentId) && !a.returnShipmentError) {
    out.return = await ensureWholesaleReturnShipment(deps, orderId);
  }
  // Sotuvchi qabul qildi (ega, 2026-11-13) → relay jo'natmasi (idempotent, kalit `wholesale_ship_{orderId}`).
  // Faqat `pending → accepted` o'tishida; xato belgisi bo'lsa qayta urinish — reconcile (aylanish yo'q).
  const b = before || {};
  if (b.sellerDecision !== WO.SELLER_DECISION.ACCEPTED && a.sellerDecision === WO.SELLER_DECISION.ACCEPTED
    && a.status === WO.STATUS.PLACED && !((a.shipment || {}).shipmentId) && !a.shipmentError) {
    // Kechiktirilgan require: wholesale_orders.js shu fayldan `notifySellerDecide`ni oladi (aylana import).
    // eslint-disable-next-line global-require
    out.shipment = await require('./wholesale_orders').ensureWholesaleShipment(deps, orderId);
  }
  const items = transitionNotifications(before, a);
  out.notifications = items.length ? await deliver(deps, orderId, a, items) : [];
  return out;
}

/** onCreate: yangi KARTA buyurtmasi — sotuvchiga (hamyon buyurtmasi — 4-bosqich ilovasida). */
async function notifyNewCardOrder(deps, data, orderId) {
  const o = data || {};
  if (WO.methodOf(o) !== WO.PAYMENT_METHOD.CARD || o.status !== WO.STATUS.PLACED) return [];
  return deliver(deps, orderId, o, [{ to: 'seller', key: 'ws_card_new_order' }]);
}

/** onCreate (ega, 2026-11-13): sotuvchiga «buyurtmani {deadline} gacha qabul qiling» (`ws_seller_decide`). */
async function notifySellerDecide(deps, data, orderId) {
  const o = data || {};
  if (o.status !== WO.STATUS.PLACED || !o.acceptDeadlineAt) return [];
  return deliver(deps, orderId, o, [{ to: 'seller', key: 'ws_seller_decide' }]);
}

module.exports = {
  transitionNotifications, refusedBuyerKey, onWholesaleOrderUpdated, notifyNewCardOrder, notifySellerDecide, deadlineText,
};
