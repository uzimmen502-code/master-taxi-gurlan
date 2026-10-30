'use strict';

/**
 * ULGURJI BUYURTMA — HOLATLAR VA O'TISHLAR (yagona jadval, CLAUDE.md 17).
 *
 * Hujjat: docs/ulgurji_buyurtma_zanjiri_uz.md §2 «Буюртма ҳолатлари».
 *
 *   placed      → accepted | rejected | cancelled
 *   accepted    → in_delivery | cancelled
 *   in_delivery → delivered
 *   rejected, cancelled, delivered — oxirgi holat.
 *
 * Kim qaysi o'tishni qiladi (19-band: autentifikatsiya ≠ avtorizatsiya):
 *   buyer  : placed → cancelled           (faqat sotuvchi qabul qilmaguncha)
 *   seller : placed → accepted | rejected (accepted — 3-bosqich, relay bilan)
 *   admin  : accepted → cancelled         (kuryer hali olmagan bo'lsa — 3-bosqich)
 *   system : accepted → in_delivery → delivered (relay custody — 3-bosqich)
 *
 * Bu jadval FAQAT SHU YERDA. Default codebase (`functions/wholesale_orders.js`)
 * boshlang'ich `placed` ni yozadi va `rejected|cancelled` da pulni qaytaradi —
 * u yerdagi nomlar shu fayl bilan paritet testida tekshiriladi
 * (`functions/test/wholesale_orders.test.js`).
 *
 * `refundStatus`: `null` → `pending` (shu codebase holatni o'zgartirganda) →
 * `done` (default codebase ledger REFUND + qoldiq qaytarilganda).
 */

const STATUS = Object.freeze({
  PLACED: 'placed',
  ACCEPTED: 'accepted',
  REJECTED: 'rejected',
  CANCELLED: 'cancelled',
  IN_DELIVERY: 'in_delivery',
  DELIVERED: 'delivered',
});

const ALLOWED = Object.freeze({
  [STATUS.PLACED]: [STATUS.ACCEPTED, STATUS.REJECTED, STATUS.CANCELLED],
  [STATUS.ACCEPTED]: [STATUS.IN_DELIVERY, STATUS.CANCELLED],
  [STATUS.IN_DELIVERY]: [STATUS.DELIVERED],
  [STATUS.REJECTED]: [],
  [STATUS.CANCELLED]: [],
  [STATUS.DELIVERED]: [],
});

const ACTOR = Object.freeze({
  BUYER: 'buyer', SELLER: 'seller', ADMIN: 'admin', SYSTEM: 'system',
});

/** `actor` → `from` → ruxsat etilgan `to` lar. */
const ACTOR_ALLOWED = Object.freeze({
  [ACTOR.BUYER]: { [STATUS.PLACED]: [STATUS.CANCELLED] },
  [ACTOR.SELLER]: { [STATUS.PLACED]: [STATUS.ACCEPTED, STATUS.REJECTED] },
  [ACTOR.ADMIN]: { [STATUS.ACCEPTED]: [STATUS.CANCELLED] },
  [ACTOR.SYSTEM]: {
    [STATUS.ACCEPTED]: [STATUS.IN_DELIVERY],
    [STATUS.IN_DELIVERY]: [STATUS.DELIVERED],
  },
});

/** Shu holatga o'tilganda xaridorga pul to'liq qaytariladi (default trigger). */
const REFUND_STATUSES = Object.freeze([STATUS.REJECTED, STATUS.CANCELLED]);

const REFUND_STATUS = Object.freeze({ PENDING: 'pending', DONE: 'done' });

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
  canTransition,
  canActorTransition,
  assertTransition,
  isTerminal,
  needsRefund,
};
