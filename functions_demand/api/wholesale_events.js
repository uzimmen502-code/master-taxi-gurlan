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
 * Yangi karta buyurtmasi haqida sotuvchiga xabar — onCreate (`notifyNewCardOrder`,
 * `onWholesaleOrderCreated` dan chaqiriladi).
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

module.exports = {
  transitionNotifications, refusedBuyerKey, onWholesaleOrderUpdated, notifyNewCardOrder,
};
