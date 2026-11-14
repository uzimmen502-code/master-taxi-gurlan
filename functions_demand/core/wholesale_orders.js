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
 * SOTUVCHI QABUL/RAD QILADI (ega qarori 2026-11-13; avvalgi 2026-10-31 «avtomatik
 * zanjir» qarori shu bilan almashdi). Yangi HOLAT YO'Q — qaror alohida maydonda
 * (`order.sellerDecision`), holat `placed` qoladi:
 *   - onCreate (demand) → `sellerDecision: 'pending'` + `acceptDeadlineAt` = yaratilish
 *     + 2 ISH KUNI (`acceptDeadlineFor`, Du–Ju, Asia/Tashkent). Jo'natma OCHILMAYDI.
 *   - `acceptWholesaleOrder` → `accepted` + `acceptedAt`; shundan keyin jo'natma (3-bosqich).
 *   - `rejectWholesaleOrder` → `rejected`, placed → cancelled (seller, `seller_rejected`).
 *   - muddat o'tdi (sweeper) → `timeout`, placed → cancelled (system, `seller_timeout`).
 *   Pul/qoldiq — xaridor bekor qilgandagi bilan AYNAN bitta yo'l (`refundStatus: pending`
 *   → default `onWholesaleOrderStatusChange`).
 * ESKI buyurtma (`sellerDecision` maydoni YO'Q — shu o'zgarishdan oldin yaratilgan) —
 * avvalgidek avtomatik jo'natma (`shipmentAllowed`), qaror so'ralmaydi (26-band).
 *
 * Kim qaysi o'tishni qiladi (19-band: autentifikatsiya ≠ avtorizatsiya):
 *   buyer  : placed → cancelled           (yetkazish hali ochilmagan bo'lsa; bank o'tkazmasida — sotuvchi
 *                                          «Пул тушди» bosguncha, PROPOSED 2026-11-14)
 *   seller : placed → cancelled           (rad: faqat `sellerDecision == pending`, muddat ichida)
 *   admin  : placed | in_delivery → cancelled (kuryer hali olmagan bo'lsa — 3-bosqich)
 *   system : placed → in_delivery → delivered (relay — 3-bosqich); in_delivery | payment_dispute → lost;
 *            placed → cancelled (sotuvchi muddatda qaror qilmadi; bank o'tkazmasi muddatda tasdiqlanmadi)
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
 *
 * ── YO'QOLGAN POSILKA (ega, 2026-10-31) ────────────────────────────────
 *   in_delivery     → lost (system: chiqish jo'natmasi relay'da `loss_settled`)
 *   payment_dispute → lost (system: o'sha; karta, chek yuborilgan — pul admin ko'rib chiqishida)
 * `lost` — oxirgi holat. Kuryer (custody) tovar qiymatini SOTUVCHIGA to'laydi (relay
 * `settleLoss`, jonli). Xaridor tomoni — default codebase `settleLost`: hamyon buyurtmasi —
 * eskrou qoldig'i (goodsTotal) xaridorga; karta (xaridor to'lamagan) — AVA ulushi sotuvchiga.
 * Qoldiq TIKLANMAYDI (tovar yo'q).
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
  LOST: 'lost',
});

const ALLOWED = Object.freeze({
  [STATUS.PLACED]: [STATUS.IN_DELIVERY, STATUS.CANCELLED],
  [STATUS.IN_DELIVERY]: [STATUS.DELIVERED, STATUS.CANCELLED, STATUS.REFUSED, STATUS.PAYMENT_DISPUTE, STATUS.LOST],
  [STATUS.PAYMENT_DISPUTE]: [STATUS.IN_DELIVERY, STATUS.REFUSED, STATUS.LOST],
  // S4: o'z yetkazishi radi — tovar sotuvchining o'zida, qaytish jo'natmasi yo'q: refused → returned.
  [STATUS.REFUSED]: [STATUS.RETURNING, STATUS.RETURNED],
  [STATUS.RETURNING]: [STATUS.RETURNED],
  [STATUS.CANCELLED]: [],
  [STATUS.DELIVERED]: [],
  [STATUS.RETURNED]: [],
  [STATUS.LOST]: [],
});

const ACTOR = Object.freeze({
  BUYER: 'buyer', SELLER: 'seller', ADMIN: 'admin', SYSTEM: 'system', COURIER: 'courier',
});

/** `actor` → `from` → ruxsat etilgan `to` lar. */
const ACTOR_ALLOWED = Object.freeze({
  [ACTOR.BUYER]: { [STATUS.PLACED]: [STATUS.CANCELLED] },
  // S4: in_delivery / refused / returned — FAQAT o'z yetkazishi buyurtmasida (callable'lar `isSelf` tekshiradi).
  [ACTOR.SELLER]: {
    [STATUS.PLACED]: [STATUS.CANCELLED, STATUS.IN_DELIVERY],
    [STATUS.IN_DELIVERY]: [STATUS.REFUSED],
    [STATUS.REFUSED]: [STATUS.RETURNED],
  },
  [ACTOR.ADMIN]: {
    [STATUS.PLACED]: [STATUS.CANCELLED],
    [STATUS.IN_DELIVERY]: [STATUS.CANCELLED],
    [STATUS.PAYMENT_DISPUTE]: [STATUS.IN_DELIVERY, STATUS.REFUSED],
  },
  [ACTOR.SYSTEM]: {
    [STATUS.PLACED]: [STATUS.IN_DELIVERY, STATUS.CANCELLED],
    [STATUS.IN_DELIVERY]: [STATUS.DELIVERED, STATUS.PAYMENT_DISPUTE, STATUS.LOST],
    [STATUS.PAYMENT_DISPUTE]: [STATUS.LOST],
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

/**
 * To'lov usuli (kvotada muhrlanadi). Yo'q (eski buyurtma/kvota) = `wallet`.
 *
 * ── BANK O'TKAZMASI (`bank_transfer`, ega qarori 2026-11-13/14) ──────────
 * Tovar puli ILOVADAN TASHQARIDA (hisob-faktura bo'yicha bank o'tkazmasi) — ilova tovar puliga
 * UMUMAN aralashmaydi (ega, 2026-11-14): ushlamaydi, qaytarmaydi, «ilovadan tashqari qaytaring»
 * kabi belgi/xabar ham YO'Q. Ilova faqat: kuryer (yetkazish) haqi — XARIDOR hamyonidan
 * (`deliveryPaymentMethod: 'wallet'`; naqd kuryerga — keyingi bosqich), logistika (jo'natma, rad
 * bo'lsa qaytish jo'natmasi) va AVA ulushi HISOBOTI (10 kunlik, admin; buyurtma paytida olinmaydi).
 *   placed (sellerDecision pending) → qabul → `bankPayment.status: awaiting`,
 *   `bankPayDeadlineAt` = qabul + 5 ISH KUNI → sotuvchi «Пул тушди» (`confirmWholesaleBankPayment`)
 *   → `confirmed` → FAQAT SHUNDAN KEYIN jo'natma (`shipmentAllowed`) → odatdagi relay oqimi.
 *   Muddatda tasdiqlanmasa → cancelled (`bank_payment_timeout`) → yetkazish haqi xaridorga
 *   (default `refundOrder`, hamyon bekor qilish yo'li bilan bir xil).
 *   Rad / yo'qolish — yetkazish haqi qismi HAMYON usuli ayb qoidalari bilan (default codebase).
 */
const PAYMENT_METHOD = Object.freeze({ WALLET: 'wallet', CARD: 'card_on_delivery', BANK: 'bank_transfer' });
const PAYMENT_METHODS = Object.freeze([PAYMENT_METHOD.WALLET, PAYMENT_METHOD.CARD, PAYMENT_METHOD.BANK]);
/**
 * Bank o'tkazmasida yetkazish haqini xaridor qanday to'laydi. Hozir FAQAT `wallet` (buyurtma paytida
 * AVA hamyonidan ushlanadi); naqd kuryerga — keyingi bosqich (shu ro'yxatga qo'shiladi).
 */
const DELIVERY_PAYMENT_METHOD = Object.freeze({ WALLET: 'wallet' });
const DELIVERY_PAYMENT_METHODS = Object.freeze([DELIVERY_PAYMENT_METHOD.WALLET]);
/** `order.bankPayment.status`. Maydon yo'q — bank buyurtmasi emas yoki hali qabul qilinmagan. */
const BANK_PAYMENT = Object.freeze({
  AWAITING: 'awaiting', CONFIRMED: 'confirmed', TIMEOUT: 'timeout', CANCELLED: 'cancelled',
});
/** Qabuldan keyin tovar puli tushishi muddati — ish kunlari (ega: 5 ish kuni). YAGONA joy. */
const BANK_PAY_BUSINESS_DAYS = 5;
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

/** `lost` ga faqat shu holatlardan (system) — default `settleLost` paritet testi bilan. */
const LOST_FROM_STATUSES = Object.freeze([STATUS.IN_DELIVERY, STATUS.PAYMENT_DISPUTE]);
/**
 * `order.payment.status` yo'qolishdan keyin:
 *   refunded_lost — eskrou qoldig'i to'lovchiga qaytdi (hamyon: xaridor goodsTotal; karta: sotuvchi avaFee);
 *   lost_review   — karta, xaridor to'lovni bildirgan (chek / tasdiq / nizo): pul YO'Q, admin hal qiladi.
 */
const LOST_PAYMENT = Object.freeze({ REFUNDED: 'refunded_lost', REVIEW: 'lost_review' });

// ── SOTUVCHI QABULI (ega, 2026-11-13) ──────────────────────────────────
/** `order.sellerDecision`. Maydon YO'Q — eski buyurtma (qaror so'ralmaydi). */
const SELLER_DECISION = Object.freeze({
  PENDING: 'pending', ACCEPTED: 'accepted', REJECTED: 'rejected', TIMEOUT: 'timeout',
});
/** `order.cancelReason` (sotuvchi qarori bilan bog'liq bekor qilishlar). */
const CANCEL_REASON = Object.freeze({
  SELLER_REJECTED: 'seller_rejected', SELLER_TIMEOUT: 'seller_timeout', BANK_PAYMENT_TIMEOUT: 'bank_payment_timeout',
});
/** Qaror muddati — ish kunlari (ega: «2 ish kuni»). YAGONA joy. */
const ACCEPT_BUSINESS_DAYS = 2;
/** Asia/Tashkent = UTC+5, yozgi vaqt YO'Q (2026 holatiga). */
const TASHKENT_OFFSET_MS = 5 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
/** Rad sababi uzunligi (topshiriq: 3..300 belgi). */
const REJECT_REASON_MIN = 3;
const REJECT_REASON_MAX = 300;

/** Mahalliy (Toshkent) «soxta UTC» vaqtida hafta kuni: 0 = Yakshanba, 6 = Shanba. */
const isWeekendLocal = (localMs) => {
  const d = new Date(localMs).getUTCDay();
  return d === 0 || d === 6;
};

/**
 * Qaror muddati (ms, UTC). Ta'rif (ega, 2026-11-13): yaratilgandan keyin 2 TO'LIQ ish kuni
 * o'tgan payt — o'sha mahalliy soat. Ish kuni = Dushanba–Juma, Asia/Tashkent; Shanba/Yakshanba
 * hisoblanmaydi; bayram kalendari YO'Q. Dam olish kunida yaratilsa — hisob Dushanba 00:00 dan.
 *   Du 10:00 → Ch 10:00;  Pa 15:00 → Du 15:00;  Ju 23:59 → Se 23:59;  Sh/Ya istalgan → Ch 00:00.
 * Algoritm: (dam olish kuni bo'lsa Du 00:00 ga suriladi), keyin N marta «+1 kun, dam olish
 * kunlarini o'tkazib yuborish». Sof funksiya, butun ms.
 */
function acceptDeadlineFor(createdAtMs, businessDays = ACCEPT_BUSINESS_DAYS) {
  if (!Number.isSafeInteger(createdAtMs)) throw new Error('acceptDeadlineFor: createdAtMs butun ms bo\'lishi kerak');
  let t = createdAtMs + TASHKENT_OFFSET_MS;
  if (isWeekendLocal(t)) {
    t -= ((t % DAY_MS) + DAY_MS) % DAY_MS; // mahalliy kun boshi 00:00
    while (isWeekendLocal(t)) t += DAY_MS;
  }
  for (let i = 0; i < businessDays; i += 1) {
    t += DAY_MS;
    while (isWeekendLocal(t)) t += DAY_MS;
  }
  return t - TASHKENT_OFFSET_MS;
}

/**
 * Bank o'tkazmasi muddati: qabul paytidan 5 ish kuni (`acceptDeadlineFor` bilan AYNI ish kuni
 * qoidasi — Du–Ju, Asia/Tashkent, bayram kalendari yo'q; umumlashtirilgan N kun).
 */
function bankPayDeadlineFor(acceptedAtMs) {
  return acceptDeadlineFor(acceptedAtMs, BANK_PAY_BUSINESS_DAYS);
}

const methodOf = (doc) => {
  const m = (doc || {}).paymentMethod;
  if (m === PAYMENT_METHOD.CARD) return PAYMENT_METHOD.CARD;
  if (m === PAYMENT_METHOD.BANK) return PAYMENT_METHOD.BANK;
  return PAYMENT_METHOD.WALLET;
};

/**
 * Yetkazish haqini XARIDOR AVA hamyonidan to'laganmi (hamyon va bank o'tkazmasi). Rad/yo'qolishdagi
 * yetkazish haqi va qaytish haqi qoidalari (ayb sababi, `WALLET_REASONS`) — shu ikkalasida bir xil.
 */
/**
 * S6 (ega CONFIRMED 2026-11-13): yetkazish haqini HAMMA usulda xaridor to'laydi. Karta buyurtmasida belgi
 * `deliveryPaidBy: 'buyer'` (kvota muhri → default `placeWholesaleOrder` buyurtmaga ko'chiradi). Belgisiz karta
 * buyurtmasi (deploydan OLDIN) — ESKI semantika (sotuvchi hamyonidan kuryer haqi + AVA ulushi) oxirigacha.
 */
const DELIVERY_PAID_BY = Object.freeze({ BUYER: 'buyer' });
const isNewCard = (doc) => methodOf(doc) === PAYMENT_METHOD.CARD && (doc || {}).deliveryPaidBy === DELIVERY_PAID_BY.BUYER;
const deliveryPaidByBuyer = (doc) => methodOf(doc) !== PAYMENT_METHOD.CARD || isNewCard(doc);

/**
 * ── S4: SOTUVCHINING O'Z YETKAZISHI (ega CONFIRMED 2026-11-13/14) ─────────────────────────────
 * `deliveryMethod: 'self'` (kvota → buyurtma; yo'q = `ava_courier`). Yetkazish narxi tovar narxi ICHIDA —
 * deliveryFee 0, kuryer/relay jo'natmasi HECH QACHON ochilmaydi (`shipmentAllowed` false).
 *   placed (qabul; bank — «Пул тушди» ham) → in_delivery   (seller, `startWholesaleSelfDelivery`)
 *   in_delivery → delivered (system: default `releaseSelf`, sotuvchi xaridor kodini kiritgach — `selfDelivery.status: completed`)
 *   in_delivery → refused   (seller, `markWholesaleSelfDeliveryRefused`)
 *   refused     → returned  (seller, `completeWholesaleSelfReturn` — tovar qaytdi, qoldiq +N)
 * Sotuvchi o'tishlari FAQAT o'z yetkazishi buyurtmasida (callable'lar `isSelf` ni tekshiradi).
 * Boshlash muddati — YO'Q (PROPOSED: hozircha timeout qo'yilmaydi).
 */
const DELIVERY_METHOD = Object.freeze({ AVA_COURIER: 'ava_courier', SELF: 'self' });
const DELIVERY_METHODS = Object.freeze([DELIVERY_METHOD.AVA_COURIER, DELIVERY_METHOD.SELF]);
const deliveryMethodOf = (doc) => ((doc || {}).deliveryMethod === DELIVERY_METHOD.SELF ? DELIVERY_METHOD.SELF : DELIVERY_METHOD.AVA_COURIER);
const isSelf = (doc) => deliveryMethodOf(doc) === DELIVERY_METHOD.SELF;
const SELF_STATUS = Object.freeze({
  PENDING: 'pending', IN_DELIVERY: 'in_delivery', COMPLETED: 'completed', REFUSED: 'refused', RETURNED: 'returned',
});
/** Sotuvchi sozlamasi `wholesale_sellers.selfDelivery` qiymatlari (Firestore Rules bilan AYNAN bir xil). */
const SELF_COVERAGES = Object.freeze(['district', 'region', 'nation']);
const SELF_DROPOFFS = Object.freeze(['district_center', 'buyer_address']);

/**
 * AVA ulushi buyurtma paytida OLINMAYDI — 10 kunlik hisobot orqali yig'iladi (`avaFeeCollection: 'statement'`):
 * bank o'tkazmasi (hamma) va o'z yetkazishi karta orqali (tovar puli ilovaga kirmaydi). O'z yetkazishi hamyon —
 * RELEASE da ushlanadi (odatdagidek).
 */
function feeViaStatement(o) {
  const m = methodOf(o);
  if (m === PAYMENT_METHOD.BANK) return true;
  return m === PAYMENT_METHOD.CARD && isSelf(o);
}

/**
 * Jo'natma ochish mumkinmi (3-bosqich darvozasi). Maydon yo'q — ESKI buyurtma, avvalgidek
 * ruxsat; `accepted` + `acceptedAt` — ruxsat; qolgani (pending/rejected/timeout/noma'lum) — YO'Q.
 * Bank o'tkazmasi: qo'shimcha — sotuvchi «Пул тушди» bosgan (`bankPayment.status == confirmed`).
 * O'z yetkazishi (S4) — HECH QACHON (relay jo'natmasi yo'q).
 */
function shipmentAllowed(o) {
  if (isSelf(o)) return false;
  const d = (o || {}).sellerDecision;
  if (d === undefined || d === null) return true;
  if (!(d === SELLER_DECISION.ACCEPTED && !!o.acceptedAt)) return false;
  if (methodOf(o) === PAYMENT_METHOD.BANK) {
    const bp = o.bankPayment || {};
    return bp.status === BANK_PAYMENT.CONFIRMED && !!bp.confirmedAt;
  }
  return true;
}

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
  DELIVERY_PAYMENT_METHOD,
  DELIVERY_PAYMENT_METHODS,
  BANK_PAYMENT,
  BANK_PAY_BUSINESS_DAYS,
  bankPayDeadlineFor,
  deliveryPaidByBuyer,
  DELIVERY_PAID_BY,
  isNewCard,
  DELIVERY_METHOD,
  DELIVERY_METHODS,
  deliveryMethodOf,
  isSelf,
  SELF_STATUS,
  SELF_COVERAGES,
  SELF_DROPOFFS,
  feeViaStatement,
  CARD_PAYMENT,
  CARD_REFUSAL_LIMIT,
  RECEIPT_TIMEOUT_MS,
  RECEIPT_TIMEOUT_MINUTES,
  RETURN_STATUS,
  LOST_FROM_STATUSES,
  LOST_PAYMENT,
  SELLER_DECISION,
  CANCEL_REASON,
  ACCEPT_BUSINESS_DAYS,
  TASHKENT_OFFSET_MS,
  REJECT_REASON_MIN,
  REJECT_REASON_MAX,
  acceptDeadlineFor,
  shipmentAllowed,
  methodOf,
  canTransition,
  canActorTransition,
  assertTransition,
  isTerminal,
  needsRefund,
};
