'use strict';

/**
 * ULGURJI BUYURTMA — HOLATLAR VA O'TISHLAR (yagona jadval, CLAUDE.md 17).
 *
 * Hujjat: docs/ulgurji_buyurtma_zanjiri_uz.md §2 «Буюртма ҳолатлари».
 *
 *   placed      → in_delivery | cancelled
 *   in_delivery → delivered | cancelled | refused | payment_dispute (3b, karta)
 *   cancelled, delivered, returned — oxirgi holat (3b o'tishlari pastda).
 *
 * SOTUVCHI QABUL/RAD QILMAYDI (ega, 2026-10-31): xaridor «Buyurtma berish»ni
 * bosgach zanjir avtomatik — server yetkazishni o'zi ochadi (3-bosqich). Shu
 * sababli `accepted`/`rejected` holatlari va sotuvchi o'tishlari YO'Q.
 *
 * Kim qaysi o'tishni qiladi (19-band: autentifikatsiya ≠ avtorizatsiya):
 *   buyer  : placed → cancelled           (yetkazish hali ochilmagan bo'lsa)
 *   admin  : placed | in_delivery → cancelled (kuryer hali olmagan bo'lsa — 3-bosqich)
 *   system : placed → in_delivery → delivered (relay — 3-bosqich)
 *
 * Bu jadval FAQAT SHU YERDA. Default codebase (`functions/wholesale_orders.js`)
 * boshlang'ich `placed` ni yozadi va `cancelled` da pulni qaytaradi —
 * u yerdagi nomlar shu fayl bilan paritet testida tekshiriladi
 * (`functions/test/wholesale_orders.test.js`).
 *
 * `refundStatus`: `null` → `pending` (shu codebase holatni o'zgartirganda) →
 * `done` (default codebase ledger REFUND + qoldiq qaytarilganda).
 *
 * ── 3b-BOSQICH: «yetkazilganda karta orqali» (ega, 2026-10-31) ──────────
 *   in_delivery     → refused         (courier: xaridor to'lamadi/rad etdi; faqat karta,
 *                                      to'lov `awaiting` — chek yuborilgan bo'lsa EMAS)
 *   in_delivery     → payment_dispute (system: chek ≥30 daqiqa tasdiqlanmadi — RECEIPT_TIMEOUT_MS)
 *   payment_dispute → in_delivery     (admin: to'lov tasdiqlandi)
 *   payment_dispute → refused         (admin: to'lov rad etildi)
 *   refused         → returning       (system: qaytish jo'natmasi to'landi — sotuvchi hamyonidan)
 *   returning       → returned        (system: qaytish jo'natmasi sotuvchiga yetdi; qoldiq +N SHU YERDA)
 * `refused` da `refundStatus: pending` — default codebase sotuvchining AVA ulushi
 * ushlanmasini qaytaradi (sotuv bo'lmadi — PROPOSED), qoldiq EMAS.
 */

const STATUS = Object.freeze({
  PLACED: 'placed',
  CANCELLED: 'cancelled',
  IN_DELIVERY: 'in_delivery',
  DELIVERED: 'delivered',
  REFUSED: 'refused',
  PAYMENT_DISPUTE: 'payment_dispute',
  RETURNING: 'returning',
  RETURNED: 'returned',
});

const ALLOWED = Object.freeze({
  [STATUS.PLACED]: [STATUS.IN_DELIVERY, STATUS.CANCELLED],
  [STATUS.IN_DELIVERY]: [STATUS.DELIVERED, STATUS.CANCELLED, STATUS.REFUSED, STATUS.PAYMENT_DISPUTE],
  [STATUS.PAYMENT_DISPUTE]: [STATUS.IN_DELIVERY, STATUS.REFUSED],
  [STATUS.REFUSED]: [STATUS.RETURNING],
  [STATUS.RETURNING]: [STATUS.RETURNED],
  [STATUS.CANCELLED]: [],
  [STATUS.DELIVERED]: [],
  [STATUS.RETURNED]: [],
});

const ACTOR = Object.freeze({
  BUYER: 'buyer', ADMIN: 'admin', SYSTEM: 'system', COURIER: 'courier',
});

/** `actor` → `from` → ruxsat etilgan `to` lar. */
const ACTOR_ALLOWED = Object.freeze({
  [ACTOR.BUYER]: { [STATUS.PLACED]: [STATUS.CANCELLED] },
  [ACTOR.ADMIN]: {
    [STATUS.PLACED]: [STATUS.CANCELLED],
    [STATUS.IN_DELIVERY]: [STATUS.CANCELLED],
    [STATUS.PAYMENT_DISPUTE]: [STATUS.IN_DELIVERY, STATUS.REFUSED],
  },
  [ACTOR.SYSTEM]: {
    [STATUS.PLACED]: [STATUS.IN_DELIVERY],
    [STATUS.IN_DELIVERY]: [STATUS.DELIVERED, STATUS.PAYMENT_DISPUTE],
    [STATUS.REFUSED]: [STATUS.RETURNING],
    [STATUS.RETURNING]: [STATUS.RETURNED],
  },
  [ACTOR.COURIER]: { [STATUS.IN_DELIVERY]: [STATUS.REFUSED] },
});

/**
 * Shu holatga o'tilganda TO'LOVCHIGA pul qaytariladi (default trigger, `refundStatus`):
 *   cancelled — to'lovchiga to'liq ushlanma (hamyon: xaridor; karta: sotuvchi);
 *   refused   — karta: eskrouda qolgan AVA ulushi sotuvchiga (yetkazish haqi kuryerlarda).
 */
const REFUND_STATUSES = Object.freeze([STATUS.CANCELLED, STATUS.REFUSED]);
const REFUND_STATUS = Object.freeze({ PENDING: 'pending', DONE: 'done' });

/** To'lov usuli (kvotada muhrlanadi). Yo'q (eski buyurtma/kvota) = `wallet`. */
const PAYMENT_METHOD = Object.freeze({ WALLET: 'wallet', CARD: 'card_on_delivery' });
const PAYMENT_METHODS = Object.freeze([PAYMENT_METHOD.WALLET, PAYMENT_METHOD.CARD]);
/** `order.cardPayment.status`. */
const CARD_PAYMENT = Object.freeze({
  AWAITING: 'awaiting', RECEIPT_SUBMITTED: 'receipt_submitted', CONFIRMED: 'confirmed', DISPUTED: 'disputed',
});
/** Xaridor shuncha rad etgach karta usuli yopiladi (ega, 2026-10-31: «2 marta»). */
const CARD_REFUSAL_LIMIT = 2;
/**
 * Chek yuborilgach sotuvchi shuncha vaqtda tasdiqlamasa — nizo (ega, 2026-10-31: 30 daqiqa;
 * avval 15 edi). YAGONA joy: sweeper, xabar matni (`{minutes}`) va testlar shundan o'qiydi.
 */
const RECEIPT_TIMEOUT_MS = 30 * 60 * 1000;
const RECEIPT_TIMEOUT_MINUTES = RECEIPT_TIMEOUT_MS / 60000;
/** Kartaga qaytish jo'natmasi holati (`order.returnStatus`). */
//   pending_shipment — rad etildi, qaytish jo'natmasi hali ochilmagan (demand triggeri ochadi);
//   awaiting_payment — jo'natma ochildi (narx muhrlandi), sotuvchi hamyonidan hali to'lanmagan
//                      (`returnDebt` bo'lsa — mablag' yetmagan, reconcile qayta urinadi);
//   in_transit       — to'landi (`returning`), LEG ochiq; returned — sotuvchiga yetdi.
const RETURN_STATUS = Object.freeze({
  PENDING_SHIPMENT: 'pending_shipment', AWAITING_PAYMENT: 'awaiting_payment', IN_TRANSIT: 'in_transit', RETURNED: 'returned',
});

const methodOf = (doc) => ((doc || {}).paymentMethod === PAYMENT_METHOD.CARD ? PAYMENT_METHOD.CARD : PAYMENT_METHOD.WALLET);

function canTransition(from, to) {
  const allowed = ALLOWED[from];
  return Array.isArray(allowed) && allowed.includes(to);
}

function canActorTransition(actor, from, to) {
  if (!canTransition(from, to)) return false;
  const byFrom = ACTOR_ALLOWED[actor] || {};
  return Array.isArray(byFrom[from]) && byFrom[from].includes(to);
}

function transitionError(from, to, actor) {
  const e = new Error('Buyurtma holatini o\'zgartirib bo\'lmaydi');
  e.code = 'failed-precondition';
  e.httpErrorCode = 'failed-precondition';
  e.details = { reason: 'invalid_transition', from: from || null, to, actor };
  return e;
}

/** Noqonuniy o'tish — xato (jimgina o'tib ketmaydi). */
function assertTransition(actor, from, to) {
  if (!canActorTransition(actor, from, to)) throw transitionError(from, to, actor);
}

function isTerminal(status) {
  return Array.isArray(ALLOWED[status]) && ALLOWED[status].length === 0;
}

function needsRefund(status) {
  return REFUND_STATUSES.includes(status);
}

module.exports = {
  STATUS,
  ALLOWED,
  ACTOR,
  ACTOR_ALLOWED,
  REFUND_STATUSES,
  REFUND_STATUS,
  PAYMENT_METHOD,
  PAYMENT_METHODS,
  CARD_PAYMENT,
  CARD_REFUSAL_LIMIT,
  RECEIPT_TIMEOUT_MS,
  RECEIPT_TIMEOUT_MINUTES,
  RETURN_STATUS,
  methodOf,
  canTransition,
  canActorTransition,
  assertTransition,
  isTerminal,
  needsRefund,
};
