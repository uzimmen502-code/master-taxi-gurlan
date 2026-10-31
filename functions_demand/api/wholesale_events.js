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
  if (changedTo(b, a, WO.STATUS.REFUSED)) {
    out.push({ to: 'buyer', key: 'ws_refused_buyer' }, { to: 'seller', key: 'ws_refused_seller' });
  }
  if (changedTo(b, a, WO.STATUS.PAYMENT_DISPUTE)) out.push({ to: 'admins', key: 'ws_dispute_admin' });
  if (!b.returnDebt && a.returnDebt) {
    out.push({ to: 'seller', key: 'ws_return_debt_seller' }, { to: 'admins', key: 'ws_return_debt_admin' });
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
    } else {
      out.push({ to: 'buyer', key: WO.methodOf(a) === WO.PAYMENT_METHOD.CARD ? 'ws_lost_buyer_card' : 'ws_lost_buyer_wallet' },
        { to: 'seller', key: 'ws_lost_seller' });
    }
  }
  return out;
}

function paramsOf(o, orderId) {
  const rs = o.returnShipment || {};
  const debt = o.returnDebt || {};
  return {
    orderId,
    product: String(o.productTitle || '').slice(0, 60),
    qty: o.qty,
    amount: Number.isInteger(o.goodsTotal) && Number.isInteger(o.deliveryFee) ? o.goodsTotal + o.deliveryFee : '',
    tracking: rs.trackingNumber || '',
    ...(Number.isInteger(debt.amount) ? { amount: debt.amount } : {}),
    // Yo'qolish: xaridorga qaytgan summa (hamyon — goodsTotal); `{refund}` faqat lost xabarlarida.
    refund: Number.isInteger((o.payment || {}).lostRefund) ? o.payment.lostRefund : '',
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

module.exports = { transitionNotifications, onWholesaleOrderUpdated, notifyNewCardOrder };
