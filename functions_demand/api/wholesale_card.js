'use strict';

/**
 * ULGURJI — «YETKAZILGANDA KARTA ORQALI» (3b-bosqich, demand codebase, europe-west1).
 * Ega qarorlari (2026-10-31, yakuniy): xaridor hammasini (tovar + yetkazish) eshik oldida
 * SOTUVCHI KARTASIGA o'tkazadi (ekvayring yo'q). Sotuvchining yagona amali — «Pul tushdi».
 * Kuryer haqi + AVA ulushi buyurtma paytida SOTUVCHI HAMYONIDAN ushlanadi (default
 * codebase `placeWholesaleOrder`). Rad/to'lamaslik → tovar sotuvchiga qaytadi (qaytish
 * jo'natmasi — `wholesale_return.js`, haqi sotuvchi hamyonidan), qoldiq qaytganda tiklanadi,
 * kuryer haqi qaytarilmaydi; xaridor 2 marta rad etgach karta usuli unga yopiladi.
 *
 *   setWholesaleSellerCard            sotuvchi (tasdiqlangan): karta (16 raqam, Luhn) + egasi
 *                                      → `wholesale_sellers/{tel}/private/payout` (FAQAT server)
 *   getWholesaleCardPaymentInfo       xaridor, karta buyurtma `in_delivery`: summa + karta
 *   submitWholesaleCardReceipt        xaridor: chek rasmi yo'li (Storage) → `receipt_submitted`
 *   confirmWholesaleCardPayment       sotuvchi: «Pul tushdi» (awaiting | receipt_submitted)
 *   markWholesaleBuyerRefused         oxirgi LEG kuryeri (posilka qo'lida): in_delivery → refused
 *   adminResolveWholesaleCardDispute  qat'iy admin: payment_dispute → in_delivery | refused (+audit)
 *   wholesaleCardDisputeSweeper       har 5 daq: chek ≥ RECEIPT_TIMEOUT_MS tasdiqlanmagan → payment_dispute
 *   getWholesaleReturnHandoverCode    qaytish LEG-1 kuryeri: qaytish jo'natmasining TOPSHIRISH kodi
 *
 * Pul bu yerda YO'Q (ledger — default codebase): bu fayl faqat holat + server-only hujjatlar.
 * Log — karta raqami FAQAT oxirgi 4 raqam, telefon/manzil yo'q (24, 40-band).
 */

const {
  callerIdFrom, sameUser, candidateIdsFor, toCanonicalId,
} = require('../core/ids');
const L = require('../core/logistics');
const WO = require('../core/wholesale_orders');
const { assertStrictAdmin } = require('../analytics/access');

const ORDERS = 'wholesale_orders';
const SELLERS = 'wholesale_sellers';
const HISTORY = 'history';
const BUYER_STATS = 'wholesale_buyer_stats';
const SELLER_STATS = 'wholesale_seller_stats';
const LEDGER_ACCOUNTS = 'ledger_accounts';
const ADMIN_AUDIT = 'admin_audit';
const ID_RE = /^[A-Za-z0-9_-]{1,128}$/;
const HOLDER_RE = /^[\p{L}][\p{L} .'-]{1,59}$/u;
const HOLDER_MAX = 60;
const RECEIPT_PREFIX = 'wholesale_receipts';
const RECEIPT_FILE_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$/;
const RECEIPT_PATH_MAX = 300;
const DISPUTE_SWEEP_LIMIT = 200;

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

function msOf(v) {
  if (v == null) return null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return null;
}

// ═══════════════════════════════════════════════════════════════════════
// SOF FUNKSIYALAR
// ═══════════════════════════════════════════════════════════════════════

/** Luhn (ISO/IEC 7812) — raqamlar satri. */
function luhnOk(digits) {
  let sum = 0;
  let dbl = false;
  for (let i = digits.length - 1; i >= 0; i -= 1) {
    let n = digits.charCodeAt(i) - 48;
    if (n < 0 || n > 9) return false;
    if (dbl) { n *= 2; if (n > 9) n -= 9; }
    sum += n;
    dbl = !dbl;
  }
  return sum % 10 === 0;
}

/** Bo'sh joy / chiziqcha olib tashlanadi; AYNAN 16 raqam + Luhn. Aks holda xato. */
function parseCardNumber(raw) {
  if (typeof raw !== 'string') throw fail('invalid-argument', 'Karta raqami 16 ta raqam bo\'lishi kerak', 'card_number_invalid', { check: 'format' });
  const s = raw.replace(/[\s-]/g, '');
  if (!/^\d{16}$/.test(s)) throw fail('invalid-argument', 'Karta raqami 16 ta raqam bo\'lishi kerak', 'card_number_invalid', { check: 'format' });
  if (!luhnOk(s)) throw fail('invalid-argument', 'Karta raqami noto\'g\'ri', 'card_number_invalid', { check: 'luhn' });
  return s;
}

/** Karta egasi: 2..60 belgi, harf bilan boshlanadi; harf, bo'sh joy, . ' - . */
function parseHolderName(raw) {
  const s = String(raw == null ? '' : raw).replace(/\s+/g, ' ').trim();
  if (s.length < 2 || s.length > HOLDER_MAX || !HOLDER_RE.test(s)) {
    throw fail('invalid-argument', `Karta egasi ismi 2–${HOLDER_MAX} harf`, 'holder_name_invalid', { max: HOLDER_MAX });
  }
  return s;
}

const last4Of = (card) => String(card || '').slice(-4);

/**
 * Chek yo'li: `wholesale_receipts/{xaridorTel}/{orderId}/{fayl}` (Storage qoidasi shu
 * shaklni talab qiladi). Tel — xaridorning 12 yoki 9 xonali shakli.
 */
function parseReceiptPath(raw, buyerId, orderId) {
  const s = String(raw == null ? '' : raw).trim();
  const bad = () => fail('invalid-argument', 'Chek fayli noto\'g\'ri', 'receipt_path_invalid');
  if (!s || s.length > RECEIPT_PATH_MAX || s.includes('..') || s.includes('\\') || s.startsWith('/')) throw bad();
  const parts = s.split('/');
  if (parts.length !== 4 || parts[0] !== RECEIPT_PREFIX) throw bad();
  if (!/^\d{9}$|^998\d{9}$/.test(parts[1]) || !sameUser(parts[1], buyerId)) throw bad();
  if (parts[2] !== orderId) throw bad();
  if (!RECEIPT_FILE_RE.test(parts[3])) throw bad();
  return s;
}

// ═══════════════════════════════════════════════════════════════════════
// O'QISH YORDAMCHILARI (kvota va callable'lar uchun)
// ═══════════════════════════════════════════════════════════════════════

/** Sotuvchi hujjati (`wholesale_sellers/{id}`, 12 yoki eski 9 xonali). */
async function findSellerDoc(db, id) {
  const ids = [...new Set([String(id || ''), ...candidateIdsFor(id)].filter(Boolean))];
  for (const x of ids) {
    const ref = db.collection(SELLERS).doc(x);
    const s = await ref.get();
    if (s.exists) return { id: x, ref, data: s.data() || {} };
  }
  return null;
}

/** Sotuvchi kartasi (server-only `private/payout`) — yaroqli bo'lsa. */
async function readPayoutCard(db, sellerId) {
  const ids = [...new Set([String(sellerId || ''), ...candidateIdsFor(sellerId)].filter(Boolean))];
  for (const x of ids) {
    const s = await db.collection(SELLERS).doc(x).collection('private').doc('payout').get();
    if (!s.exists) continue;
    const d = s.data() || {};
    if (typeof d.cardNumber === 'string' && /^\d{16}$/.test(d.cardNumber) && typeof d.holderName === 'string' && d.holderName) {
      return { sellerDocId: x, cardNumber: d.cardNumber, holderName: d.holderName, last4: last4Of(d.cardNumber) };
    }
  }
  return null;
}

/** Hamyon egasi hujjati — default codebase `walletUidOf` bilan bir xil (12, keyin 9 xonali). */
async function walletUidFor(db, uid) {
  for (const id of candidateIdsFor(uid)) {
    const s = await db.collection('users').doc(id).get();
    if (s.exists) return id;
  }
  return null;
}

/** Ledger `passenger_credit:{walletUid}` balansi (default codebase yozadi; bu yerda faqat o'qiladi). */
async function walletBalance(db, walletUid) {
  if (!walletUid) return 0;
  const s = await db.collection(LEDGER_ACCOUNTS).doc(`passenger_credit:${walletUid}`).get();
  const b = s.exists ? (s.data() || {}).balance : 0;
  return isInt(b) ? b : 0;
}

async function buyerRefusals(db, buyerId) {
  const id = toCanonicalId(buyerId);
  if (!id) return 0;
  const s = await db.collection(BUYER_STATS).doc(id).get();
  const n = s.exists ? (s.data() || {}).cardRefusals : 0;
  return isInt(n) && n > 0 ? n : 0;
}

async function sellerCardBlocked(db, sellerId) {
  const id = toCanonicalId(sellerId);
  if (!id) return false;
  const s = await db.collection(SELLER_STATS).doc(id).get();
  return s.exists && (s.data() || {}).cardBlocked === true;
}

/**
 * Karta usuli shu buyurtma uchun ochiqmi (kvota). Sabab tartibi: kartasi yo'q →
 * qaytish qarzi → xaridor cheklangan → hamyon yetmaydi. `placeWholesaleOrder`
 * (default) HAMMASINI tranzaksiyada qayta tekshiradi.
 * @returns {{available: boolean, reason: null|'seller_no_card'|'seller_debt'|'buyer_limited'|'seller_balance'}}
 */
async function cardAvailability(db, { sellerId, buyerId, sellerHold }) {
  if (!(await readPayoutCard(db, sellerId))) return { available: false, reason: 'seller_no_card' };
  if (await sellerCardBlocked(db, sellerId)) return { available: false, reason: 'seller_debt' };
  if ((await buyerRefusals(db, buyerId)) >= WO.CARD_REFUSAL_LIMIT) return { available: false, reason: 'buyer_limited' };
  const bal = await walletBalance(db, await walletUidFor(db, sellerId));
  if (!isPosInt(sellerHold) || bal < sellerHold) return { available: false, reason: 'seller_balance' };
  return { available: true, reason: null };
}

function requireOrderId(data) {
  const orderId = String((data || {}).orderId || '').trim();
  if (!ID_RE.test(orderId)) throw fail('invalid-argument', 'Buyurtma tanlanmagan', 'order_required');
  return orderId;
}

function denied(action, orderId, e) {
  log(action, { result: 'denied', orderId, errorCode: (e && e.details && e.details.reason) || (e && e.code) || 'UNKNOWN' });
}

function historyWrite(tx, ref, o, entry, now) {
  const seq = (isInt(o.historySeq) ? o.historySeq : 0) + 1;
  tx.set(ref.collection(HISTORY).doc(String(seq)), { seq, reason: '', at: now, ...entry });
  return seq;
}

// ═══════════════════════════════════════════════════════════════════════
// SOTUVCHI KARTASI
// ═══════════════════════════════════════════════════════════════════════

/**
 * `setWholesaleSellerCard({cardNumber, holderName})` — faqat mavjud, TASDIQLANGAN Ulgurji
 * sotuvchi (`wholesale_sellers/{o'z tel}`, `approvalStatus == 'approved'`). To'liq raqam
 * FAQAT `private/payout` da (klientga yopiq — qoida yo'q = rad); ommaviy hujjatda
 * `hasPayoutCard` + `cardLast4` (Admin SDK; egasi qoidasi o'zgargan maydonlarnigina
 * tekshiradi). O'zgarish tarixi — `private/payout/history/v{n}` (faqat oxirgi 4 raqam).
 * Bir xil karta+ism — `unchanged`, yozuv yo'q.
 */
function makeSetWholesaleSellerCard(deps) {
  const { db, now: nowFn } = deps;
  return async function setWholesaleSellerCard(data, context) {
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const d = data || {};
    try {
      const cardNumber = parseCardNumber(d.cardNumber);
      const holderName = parseHolderName(d.holderName);
      const seller = await findSellerDoc(db, callerId);
      if (!seller) throw fail('permission-denied', 'Siz Ulgurji sotuvchi emassiz', 'not_wholesale_seller');
      if (seller.data.approvalStatus !== 'approved') {
        throw fail('failed-precondition', 'Sotuvchi hali tasdiqlanmagan', 'seller_not_approved');
      }
      const last4 = last4Of(cardNumber);
      const now = nowFn ? nowFn() : new Date();
      const payoutRef = seller.ref.collection('private').doc('payout');
      const out = await db.runTransaction(async (tx) => {
        const s = await tx.get(payoutRef);
        const cur = s.exists ? (s.data() || {}) : {};
        if (cur.cardNumber === cardNumber && cur.holderName === holderName) return { unchanged: true, version: cur.version || 1 };
        const version = (isInt(cur.version) ? cur.version : 0) + 1;
        tx.set(payoutRef, {
          cardNumber, holderName, last4, version, updatedAt: now, updatedBy: callerId, createdAt: cur.createdAt || now,
        });
        tx.set(payoutRef.collection('history').doc(`v${version}`), {
          version, last4, prevLast4: cur.last4 || null, holderChanged: cur.holderName !== holderName, at: now, by: callerId,
        });
        tx.set(seller.ref, { hasPayoutCard: true, cardLast4: last4, payoutCardUpdatedAt: now }, { merge: true });
        return { unchanged: false, version };
      });
      log('setSellerCard', { result: out.unchanged ? 'unchanged' : 'ok', last4, version: out.version });
      return { ok: true, last4, unchanged: out.unchanged };
    } catch (e) {
      log('setSellerCard', { result: 'denied', errorCode: (e.details && e.details.reason) || e.code || 'UNKNOWN' });
      throw e;
    }
  };
}

// ═══════════════════════════════════════════════════════════════════════
// XARIDOR: to'lov ma'lumoti va chek
// ═══════════════════════════════════════════════════════════════════════

/**
 * `getWholesaleCardPaymentInfo({orderId})` — FAQAT xaridor, karta buyurtma, `in_delivery`.
 * `amount` = tovar + yetkazish (eshik oldida to'lanadigan hammasi).
 */
function makeGetWholesaleCardPaymentInfo(deps) {
  const { db } = deps;
  return async function getWholesaleCardPaymentInfo(data, context) {
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const orderId = requireOrderId(data);
    try {
      const s = await db.collection(ORDERS).doc(orderId).get();
      if (!s.exists) throw fail('not-found', 'Buyurtma topilmadi', 'order_not_found');
      const o = s.data() || {};
      if (!sameUser(o.buyerId, callerId)) throw fail('permission-denied', 'Bu buyurtma sizniki emas', 'not_order_party');
      if (WO.methodOf(o) !== WO.PAYMENT_METHOD.CARD) throw fail('failed-precondition', 'Buyurtma karta orqali emas', 'not_card_order');
      if (o.status !== WO.STATUS.IN_DELIVERY) throw fail('failed-precondition', 'Buyurtma hozir yetkazilmoqda emas', 'order_not_in_delivery');
      const amount = o.goodsTotal + o.deliveryFee;
      if (!isPosInt(o.goodsTotal) || !isInt(o.deliveryFee) || !Number.isSafeInteger(amount)) {
        throw fail('failed-precondition', 'Buyurtma summasi yaroqsiz', 'order_amount_invalid');
      }
      const card = await readPayoutCard(db, o.sellerId);
      if (!card) throw fail('failed-precondition', 'Sotuvchi kartasi topilmadi', 'seller_no_card');
      const seller = await findSellerDoc(db, o.sellerId);
      const sd = seller ? seller.data : {};
      const sellerName = String(sd.companyName || sd.ownerName || '').trim().slice(0, 200);
      log('getCardPaymentInfo', { result: 'ok', orderId, last4: card.last4 });
      return { amount, cardNumber: card.cardNumber, holderName: card.holderName, sellerName };
    } catch (e) {
      denied('getCardPaymentInfo', orderId, e);
      throw e;
    }
  };
}

/**
 * `submitWholesaleCardReceipt({orderId, receiptPath})` — xaridor, karta, `in_delivery`,
 * to'lov `awaiting`. Yo'l: `wholesale_receipts/{xaridorTel}/{orderId}/{fayl}` (server
 * tekshiradi; faylning o'zi — Storage qoidasi). `submittedAt` — nizo soati (RECEIPT_TIMEOUT_MS).
 * Bir xil yo'l bilan takror — idempotent; boshqa yo'l — `receipt_already_submitted`.
 */
function makeSubmitWholesaleCardReceipt(deps) {
  const { db, now: nowFn } = deps;
  return async function submitWholesaleCardReceipt(data, context) {
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const orderId = requireOrderId(data);
    const ref = db.collection(ORDERS).doc(orderId);
    try {
      const now = nowFn ? nowFn() : new Date();
      const out = await db.runTransaction(async (tx) => {
        const s = await tx.get(ref);
        if (!s.exists) throw fail('not-found', 'Buyurtma topilmadi', 'order_not_found');
        const o = s.data() || {};
        if (!sameUser(o.buyerId, callerId)) throw fail('permission-denied', 'Bu buyurtma sizniki emas', 'not_order_party');
        if (WO.methodOf(o) !== WO.PAYMENT_METHOD.CARD) throw fail('failed-precondition', 'Buyurtma karta orqali emas', 'not_card_order');
        const receiptPath = parseReceiptPath((data || {}).receiptPath, o.buyerId, orderId);
        const cp = o.cardPayment || {};
        if (cp.status === WO.CARD_PAYMENT.RECEIPT_SUBMITTED && cp.receiptPath === receiptPath) return { idempotent: true };
        if (o.status !== WO.STATUS.IN_DELIVERY) throw fail('failed-precondition', 'Buyurtma hozir yetkazilmoqda emas', 'order_not_in_delivery');
        if (cp.status === WO.CARD_PAYMENT.CONFIRMED) throw fail('failed-precondition', 'To\'lov allaqachon tasdiqlangan', 'card_payment_confirmed');
        if (cp.status === WO.CARD_PAYMENT.RECEIPT_SUBMITTED) throw fail('failed-precondition', 'Chek allaqachon yuborilgan', 'receipt_already_submitted');
        if (cp.status !== WO.CARD_PAYMENT.AWAITING) throw fail('failed-precondition', 'To\'lov holati mos emas', 'card_payment_state');
        const seq = historyWrite(tx, ref, o, {
          from: o.status, to: o.status, event: 'card_receipt_submitted', actor: WO.ACTOR.BUYER, actorId: callerId,
        }, now);
        tx.update(ref, {
          'cardPayment.status': WO.CARD_PAYMENT.RECEIPT_SUBMITTED,
          'cardPayment.receiptPath': receiptPath,
          'cardPayment.submittedAt': now,
          historySeq: seq,
          updatedAt: now,
        });
        return { idempotent: false };
      });
      log('submitCardReceipt', { result: out.idempotent ? 'already' : 'ok', orderId });
      return { ok: true, orderId, cardPaymentStatus: WO.CARD_PAYMENT.RECEIPT_SUBMITTED, idempotent: out.idempotent };
    } catch (e) {
      denied('submitCardReceipt', orderId, e);
      throw e;
    }
  };
}

// ═══════════════════════════════════════════════════════════════════════
// SOTUVCHI: «Pul tushdi»
// ═══════════════════════════════════════════════════════════════════════

/**
 * `confirmWholesaleCardPayment({orderId})` — FAQAT sotuvchi (`order.sellerId`), karta,
 * `in_delivery`, to'lov `awaiting` yoki `receipt_submitted`. Takror — idempotent.
 * Nizoda (`payment_dispute`) — faqat admin hal qiladi. Shundan keyin xaridor yetkazish
 * kodini oladi (`getWholesaleDeliveryCode`).
 */
function makeConfirmWholesaleCardPayment(deps) {
  const { db, now: nowFn } = deps;
  return async function confirmWholesaleCardPayment(data, context) {
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const orderId = requireOrderId(data);
    const ref = db.collection(ORDERS).doc(orderId);
    try {
      const now = nowFn ? nowFn() : new Date();
      const out = await db.runTransaction(async (tx) => {
        const s = await tx.get(ref);
        if (!s.exists) throw fail('not-found', 'Buyurtma topilmadi', 'order_not_found');
        const o = s.data() || {};
        if (!sameUser(o.sellerId, callerId)) throw fail('permission-denied', 'Bu buyurtma sizniki emas', 'not_order_party');
        if (WO.methodOf(o) !== WO.PAYMENT_METHOD.CARD) throw fail('failed-precondition', 'Buyurtma karta orqali emas', 'not_card_order');
        const cp = o.cardPayment || {};
        if (cp.status === WO.CARD_PAYMENT.CONFIRMED) return { idempotent: true };
        if (o.status === WO.STATUS.PAYMENT_DISPUTE) throw fail('failed-precondition', 'To\'lov admin ko\'rib chiqmoqda', 'payment_disputed');
        if (o.status !== WO.STATUS.IN_DELIVERY) throw fail('failed-precondition', 'Buyurtma hozir yetkazilmoqda emas', 'order_not_in_delivery');
        if (![WO.CARD_PAYMENT.AWAITING, WO.CARD_PAYMENT.RECEIPT_SUBMITTED].includes(cp.status)) {
          throw fail('failed-precondition', 'To\'lov holati mos emas', 'card_payment_state');
        }
        const seq = historyWrite(tx, ref, o, {
          from: o.status, to: o.status, event: 'card_payment_confirmed', actor: 'seller', actorId: callerId,
          meta: { fromCardStatus: cp.status || null },
        }, now);
        tx.update(ref, {
          'cardPayment.status': WO.CARD_PAYMENT.CONFIRMED,
          'cardPayment.confirmedAt': now,
          'cardPayment.confirmedBy': callerId,
          'cardPayment.confirmedVia': 'seller',
          historySeq: seq,
          updatedAt: now,
        });
        return { idempotent: false };
      });
      log('confirmCardPayment', { result: out.idempotent ? 'already' : 'ok', orderId });
      return { ok: true, orderId, cardPaymentStatus: WO.CARD_PAYMENT.CONFIRMED, idempotent: out.idempotent };
    } catch (e) {
      denied('confirmCardPayment', orderId, e);
      throw e;
    }
  };
}

// ═══════════════════════════════════════════════════════════════════════
// KURYER: xaridor to'lamadi / rad etdi
// ═══════════════════════════════════════════════════════════════════════

/**
 * Rad etilgandagi umumiy yozuvlar (kuryer va admin `reject` uchun BITTA joy):
 * buyurtma → refused (+ `refundStatus: pending` — default AVA ulushini sotuvchiga qaytaradi),
 * `returnStatus: pending_shipment` (demand triggeri qaytish jo'natmasini ochadi), history,
 * `wholesale_buyer_stats/{xaridor}.cardRefusals + 1` (server-only). O'qishlar chaqiruvchida.
 */
function writeRefusal(tx, db, { ref, o, from, actor, actorId, via, reason, shipmentId, legId, statsSnap, now }) {
  const buyerId = toCanonicalId(o.buyerId);
  const prev = statsSnap && statsSnap.exists && isInt((statsSnap.data() || {}).cardRefusals)
    ? (statsSnap.data() || {}).cardRefusals : 0;
  const seq = historyWrite(tx, ref, o, {
    from, to: WO.STATUS.REFUSED, actor, actorId, reason, meta: { via, shipmentId: shipmentId || null },
  }, now);
  tx.update(ref, {
    status: WO.STATUS.REFUSED,
    refundStatus: WO.REFUND_STATUS.PENDING,
    refusedAt: now,
    statusUpdatedAt: now,
    updatedAt: now,
    historySeq: seq,
    refusal: {
      by: actorId, via, reason, at: now, shipmentId: shipmentId || null, legId: legId || null,
    },
    returnStatus: WO.RETURN_STATUS.PENDING_SHIPMENT,
  });
  if (buyerId) {
    tx.set(db.collection(BUYER_STATS).doc(buyerId), {
      buyerId, cardRefusals: prev + 1, lastRefusalAt: now, lastRefusalOrderId: ref.id, updatedAt: now,
    }, { merge: true });
  }
  return prev + 1;
}

/**
 * `markWholesaleBuyerRefused({orderId, reason})` — chaqiruvchi = buyurtma jo'natmasining
 * OXIRGI LEG'iga tayinlangan ijrochi (`shipment.legAssignments[legIds[-1]]`) VA posilka
 * hozir uning qo'lida (`currentLegId` = oxirgi LEG, `currentCustodian` = u). Faqat karta,
 * `in_delivery`, to'lov `awaiting` (chek yuborilgan bo'lsa — kuryer emas, nizo/admin).
 * Relay funksiyalariga TEGILMAYDI: jo'natma o'zgarmaydi (qaytish — alohida jo'natma).
 */
function makeMarkWholesaleBuyerRefused(deps) {
  const { db, now: nowFn } = deps;
  return async function markWholesaleBuyerRefused(data, context) {
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const orderId = requireOrderId(data);
    const reason = String((data || {}).reason || '').trim().slice(0, 300);
    const ref = db.collection(ORDERS).doc(orderId);
    try {
      const pre = await ref.get();
      if (!pre.exists) throw fail('not-found', 'Buyurtma topilmadi', 'order_not_found');
      const shipmentId = String(((pre.data() || {}).shipment || {}).shipmentId || '');
      if (!shipmentId) throw fail('permission-denied', 'Ruxsat yo\'q', 'not_last_leg_courier');
      const shipRef = db.collection(L.SHIPMENTS).doc(shipmentId);
      const now = nowFn ? nowFn() : new Date();
      const out = await db.runTransaction(async (tx) => {
        const [s, ss] = await Promise.all([tx.get(ref), tx.get(shipRef)]);
        const o = s.data() || {};
        const ship = ss.exists ? (ss.data() || {}) : {};
        if (String((o.shipment || {}).shipmentId || '') !== shipmentId || ship.wholesaleOrderId !== orderId) {
          throw fail('permission-denied', 'Ruxsat yo\'q', 'not_last_leg_courier');
        }
        const legIds = Array.isArray(ship.legIds) ? ship.legIds : [];
        const lastLeg = legIds.length ? legIds[legIds.length - 1] : '';
        const assigned = lastLeg ? (ship.legAssignments || {})[lastLeg] : null;
        // 19-band: avval «kim» (oxirgi LEG ijrochisi), keyin «ruxsat» (holat).
        if (!assigned || !sameUser(assigned, callerId)) throw fail('permission-denied', 'Ruxsat yo\'q', 'not_last_leg_courier');
        if (o.status === WO.STATUS.REFUSED && sameUser((o.refusal || {}).by, callerId)) return { idempotent: true };
        if (WO.methodOf(o) !== WO.PAYMENT_METHOD.CARD) throw fail('failed-precondition', 'Buyurtma karta orqali emas', 'not_card_order');
        const cur = ship.currentCustodian || {};
        if (ship.currentLegId !== lastLeg || cur.kind !== L.CUSTODIAN_KIND.PROVIDER || !sameUser(cur.id, callerId)) {
          throw fail('failed-precondition', 'Posilka sizda emas', 'parcel_not_in_hand');
        }
        const cp = o.cardPayment || {};
        if (o.status === WO.STATUS.IN_DELIVERY) {
          if (cp.status === WO.CARD_PAYMENT.CONFIRMED) throw fail('failed-precondition', 'To\'lov tasdiqlangan', 'card_payment_confirmed');
          if (cp.status === WO.CARD_PAYMENT.RECEIPT_SUBMITTED) {
            throw fail('failed-precondition', 'Xaridor chek yuborgan — sotuvchi yoki admin hal qiladi', 'receipt_submitted');
          }
          if (cp.status !== WO.CARD_PAYMENT.AWAITING) throw fail('failed-precondition', 'To\'lov holati mos emas', 'card_payment_state');
        }
        WO.assertTransition(WO.ACTOR.COURIER, o.status, WO.STATUS.REFUSED);
        const statsSnap = await tx.get(db.collection(BUYER_STATS).doc(toCanonicalId(o.buyerId) || '_'));
        writeRefusal(tx, db, {
          ref, o, from: o.status, actor: WO.ACTOR.COURIER, actorId: callerId, via: 'courier', reason, shipmentId, legId: lastLeg, statsSnap, now,
        });
        return { idempotent: false };
      });
      log('markBuyerRefused', { result: out.idempotent ? 'already' : 'ok', orderId, shipmentId });
      return { ok: true, orderId, status: WO.STATUS.REFUSED, idempotent: out.idempotent };
    } catch (e) {
      denied('markBuyerRefused', orderId, e);
      throw e;
    }
  };
}

// ═══════════════════════════════════════════════════════════════════════
// NIZO: chek tasdiqlanmadi → payment_dispute; admin hal qiladi
// ═══════════════════════════════════════════════════════════════════════

/**
 * Sweeper (har 5 daqiqa): `cardPayment.status == receipt_submitted` (bitta maydon tengligi —
 * yangi indeks kerak emas) + `in_delivery` + `submittedAt <= now − RECEIPT_TIMEOUT_MS` →
 * tranzaksiyada `payment_dispute` (system) + `cardPayment.status: disputed` (so'rovdan chiqadi —
 * AYNAN BIR MARTA). Adminlarga xabar — demand triggeri (`ws_dispute_admin`).
 */
async function runWholesaleCardDisputeSweep(deps, { limit = DISPUTE_SWEEP_LIMIT } = {}) {
  const { db, now: nowFn } = deps;
  const now = nowFn ? nowFn() : new Date();
  const cutoff = now.getTime() - WO.RECEIPT_TIMEOUT_MS;
  const out = { checked: 0, disputed: 0, young: 0, failed: 0 };
  const snap = await db.collection(ORDERS).where('cardPayment.status', '==', WO.CARD_PAYMENT.RECEIPT_SUBMITTED).limit(limit).get();
  for (const d of snap.docs) {
    const o0 = d.data() || {};
    if (o0.status !== WO.STATUS.IN_DELIVERY) continue;
    const at0 = msOf((o0.cardPayment || {}).submittedAt);
    if (at0 == null || at0 > cutoff) { out.young += 1; continue; }
    out.checked += 1;
    try {
      const r = await db.runTransaction(async (tx) => {
        const s = await tx.get(d.ref);
        const o = s.data() || {};
        const cp = o.cardPayment || {};
        const at = msOf(cp.submittedAt);
        if (o.status !== WO.STATUS.IN_DELIVERY || cp.status !== WO.CARD_PAYMENT.RECEIPT_SUBMITTED || at == null || at > cutoff) {
          return { skipped: true };
        }
        WO.assertTransition(WO.ACTOR.SYSTEM, o.status, WO.STATUS.PAYMENT_DISPUTE);
        const seq = historyWrite(tx, d.ref, o, {
          from: o.status, to: WO.STATUS.PAYMENT_DISPUTE, event: 'card_payment_timeout', actor: WO.ACTOR.SYSTEM, actorId: null,
          meta: { timeoutMinutes: WO.RECEIPT_TIMEOUT_MINUTES },
        }, now);
        tx.update(d.ref, {
          status: WO.STATUS.PAYMENT_DISPUTE,
          'cardPayment.status': WO.CARD_PAYMENT.DISPUTED,
          'cardPayment.disputedAt': now,
          dispute: { openedAt: now, reason: 'receipt_timeout', resolution: null, resolvedAt: null, resolvedBy: null },
          statusUpdatedAt: now,
          updatedAt: now,
          historySeq: seq,
        });
        return { skipped: false };
      });
      if (!r.skipped) out.disputed += 1;
    } catch (e) {
      out.failed += 1;
      console.error(JSON.stringify({
        module: 'wholesale_orders', action: 'disputeSweep', result: 'failed', orderId: d.id, errorCode: 'DISPUTE_SWEEP_FAILED',
        message: String((e && e.message) || e).slice(0, 200),
      }));
    }
  }
  log('disputeSweep', { result: 'ok', ...out });
  return out;
}

/**
 * `adminResolveWholesaleCardDispute({orderId, decision: 'confirm'|'reject', reason})` — qat'iy
 * admin (admin/superadmin). Faqat `payment_dispute`. confirm → `in_delivery` + to'lov
 * `confirmed` (xaridor kodni oladi); reject → `refused` (qaytish oqimi, xaridor hisoblagichi
 * +1 — PROPOSED). `admin_audit` (append-only) AYNI tranzaksiyada. Takror (o'sha qaror) —
 * idempotent; boshqa qaror — `already_resolved`.
 */
function makeAdminResolveWholesaleCardDispute(deps) {
  const { db, now: nowFn } = deps;
  return async function adminResolveWholesaleCardDispute(data, context) {
    const adminId = await assertStrictAdmin(db, context);
    const orderId = requireOrderId(data);
    const decision = String((data || {}).decision || '');
    if (!['confirm', 'reject'].includes(decision)) throw fail('invalid-argument', 'Qaror: confirm yoki reject', 'decision_invalid');
    const reason = String((data || {}).reason || '').trim().slice(0, 300);
    if (decision === 'reject' && reason.length < 3) throw fail('invalid-argument', 'Rad etish sababini yozing', 'reason_required');
    const ref = db.collection(ORDERS).doc(orderId);
    try {
      const now = nowFn ? nowFn() : new Date();
      const out = await db.runTransaction(async (tx) => {
        const s = await tx.get(ref);
        if (!s.exists) throw fail('not-found', 'Buyurtma topilmadi', 'order_not_found');
        const o = s.data() || {};
        if (WO.methodOf(o) !== WO.PAYMENT_METHOD.CARD) throw fail('failed-precondition', 'Buyurtma karta orqali emas', 'not_card_order');
        const prevRes = (o.dispute || {}).resolution || null;
        if (o.status !== WO.STATUS.PAYMENT_DISPUTE) {
          if (prevRes === decision) return { idempotent: true, status: o.status };
          if (prevRes) throw fail('failed-precondition', 'Nizo allaqachon hal qilingan', 'already_resolved', { resolution: prevRes });
          throw fail('failed-precondition', 'Buyurtmada nizo yo\'q', 'not_in_dispute');
        }
        const to = decision === 'confirm' ? WO.STATUS.IN_DELIVERY : WO.STATUS.REFUSED;
        WO.assertTransition(WO.ACTOR.ADMIN, o.status, to);
        const statsSnap = decision === 'reject'
          ? await tx.get(db.collection(BUYER_STATS).doc(toCanonicalId(o.buyerId) || '_')) : null;
        const disputePatch = {
          'dispute.resolution': decision, 'dispute.resolvedAt': now, 'dispute.resolvedBy': adminId, 'dispute.resolveReason': reason,
        };
        if (decision === 'confirm') {
          const seq = historyWrite(tx, ref, o, {
            from: o.status, to, event: 'dispute_confirmed', actor: WO.ACTOR.ADMIN, actorId: adminId, reason,
          }, now);
          tx.update(ref, {
            status: to,
            'cardPayment.status': WO.CARD_PAYMENT.CONFIRMED,
            'cardPayment.confirmedAt': now,
            'cardPayment.confirmedBy': adminId,
            'cardPayment.confirmedVia': 'admin',
            ...disputePatch,
            statusUpdatedAt: now,
            updatedAt: now,
            historySeq: seq,
          });
        } else {
          const shipmentId = String((o.shipment || {}).shipmentId || '');
          writeRefusal(tx, db, {
            ref, o, from: o.status, actor: WO.ACTOR.ADMIN, actorId: adminId, via: 'admin_dispute', reason, shipmentId, legId: null, statsSnap, now,
          });
          tx.update(ref, disputePatch);
        }
        tx.set(db.collection(ADMIN_AUDIT).doc(), {
          kind: 'wholesale_card_dispute',
          actor: adminId,
          target: `${ORDERS}/${orderId}`,
          from: o.status,
          to,
          reason,
          detail: { decision, cardPaymentStatus: (o.cardPayment || {}).status || null },
          at: now,
        });
        return { idempotent: false, status: to };
      });
      log('resolveCardDispute', { result: out.idempotent ? 'already' : 'ok', orderId, decision, status: out.status });
      return { ok: true, orderId, status: out.status, idempotent: out.idempotent };
    } catch (e) {
      denied('resolveCardDispute', orderId, e);
      throw e;
    }
  };
}

// ═══════════════════════════════════════════════════════════════════════
// QAYTISH: LEG-1 topshirish kodi (posilka qo'lidagi kuryerga)
// ═══════════════════════════════════════════════════════════════════════

/**
 * `getWholesaleReturnHandoverCode({orderId})` — qaytish jo'natmasi LEG-1 ni olish uchun
 * TOPSHIRISH kodi (relay `getShipmentSecrets` bilan AYNI hosila, `L.handoverCodeFor`).
 * Qaytishda «jo'natuvchi» jismonan — posilkani ushlab turgan kuryer (sotuvchi uzoqda),
 * shuning uchun kod unga beriladi: chaqiruvchi = qaytish LEG-1 ga biriktirilgan kuryer
 * (`returnShipment.courierId`) yoki asl jo'natmaning joriy custodian'i. Yetkazish kodi
 * BERILMAYDI (u sotuvchida — egasi, relay `getShipmentSecrets`).
 */
function makeGetWholesaleReturnHandoverCode(deps) {
  const { db } = deps;
  return async function getWholesaleReturnHandoverCode(data, context) {
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const orderId = requireOrderId(data);
    try {
      const s = await db.collection(ORDERS).doc(orderId).get();
      if (!s.exists) throw fail('not-found', 'Buyurtma topilmadi', 'order_not_found');
      const o = s.data() || {};
      const rs = o.returnShipment || {};
      const outboundId = String((o.shipment || {}).shipmentId || '');
      let allowed = !!rs.courierId && sameUser(rs.courierId, callerId);
      if (!allowed && outboundId) {
        const os = await db.collection(L.SHIPMENTS).doc(outboundId).get();
        const cur = os.exists ? ((os.data() || {}).currentCustodian || {}) : {};
        allowed = cur.kind === L.CUSTODIAN_KIND.PROVIDER && sameUser(cur.id, callerId);
      }
      if (!allowed) throw fail('permission-denied', 'Ruxsat yo\'q', 'not_return_courier');
      if (![WO.STATUS.REFUSED, WO.STATUS.RETURNING].includes(o.status) || !rs.shipmentId) {
        throw fail('failed-precondition', 'Qaytish jo\'natmasi hali ochilmagan', 'return_not_ready');
      }
      const shipRef = db.collection(L.SHIPMENTS).doc(String(rs.shipmentId));
      const [ss, sec] = await Promise.all([shipRef.get(), shipRef.collection('private').doc('secrets').get()]);
      if (!ss.exists || !sec.exists) throw fail('not-found', 'Jo\'natma topilmadi', 'shipment_missing');
      const ship = ss.data() || {};
      if (ship.wholesaleOrderId !== orderId || ship.source !== 'wholesale_return') {
        throw fail('permission-denied', 'Ruxsat yo\'q', 'not_return_shipment');
      }
      if ([L.SHIPMENT_STATUS.DELIVERED, L.SHIPMENT_STATUS.CLOSED, L.SHIPMENT_STATUS.CANCELLED].includes(ship.status)) {
        throw fail('failed-precondition', 'Jo\'natma yakunlangan', 'shipment_closed');
      }
      log('getReturnHandoverCode', { result: 'ok', orderId, shipmentId: rs.shipmentId });
      return {
        orderId,
        shipmentId: String(rs.shipmentId),
        trackingNumber: ship.trackingNumber || '',
        handoverCode: L.handoverCodeFor(String(rs.shipmentId), (sec.data() || {}).qrSecret),
      };
    } catch (e) {
      denied('getReturnHandoverCode', orderId, e);
      throw e;
    }
  };
}

module.exports = {
  SELLERS,
  BUYER_STATS,
  SELLER_STATS,
  RECEIPT_PREFIX,
  HOLDER_MAX,
  luhnOk,
  parseCardNumber,
  parseHolderName,
  parseReceiptPath,
  last4Of,
  findSellerDoc,
  readPayoutCard,
  walletUidFor,
  walletBalance,
  buyerRefusals,
  sellerCardBlocked,
  cardAvailability,
  makeSetWholesaleSellerCard,
  makeGetWholesaleCardPaymentInfo,
  makeSubmitWholesaleCardReceipt,
  makeConfirmWholesaleCardPayment,
  makeMarkWholesaleBuyerRefused,
  runWholesaleCardDisputeSweep,
  makeAdminResolveWholesaleCardDispute,
  makeGetWholesaleReturnHandoverCode,
};
