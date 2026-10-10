'use strict';

/**
 * LIFECYCLE — STATUS VA RUXSAT ETILGAN O'TISHLAR.
 *
 * Konsepsiyadagi `matched` statusi OLIB TASHLANDI: u status emas, matching
 * holati. O'rniga `in_progress` qo'shildi, `matching.state` esa butunlay
 * alohida maydon.
 *
 * Т-19 bo'yicha konsepsiyada aniqlanmagan uchta holat yopildi:
 *   1) `accepted` da hech narsa bo'lmasa -> `assignmentDeadline` -> `active`
 *   2) Ijrochi bekor qilganda rad etilgan taklif `active`ga QAYTMAYDI
 *   3) `disputed` uchun egasi va SLA (48 soat, admin panel)
 *
 * Qoida: statusni FAQAT server o'zgartiradi va faqat shu jadval bo'yicha.
 * Noto'g'ri o'tish urinishi jimgina o'tib ketmaydi — xato tashlanadi.
 */

/** Talab statuslari. */
const STATUS = {
  DRAFT: 'draft',
  ACTIVE: 'active',
  ACCEPTED: 'accepted',
  IN_PROGRESS: 'in_progress',
  COMPLETED: 'completed',
  CANCELLED: 'cancelled',
  EXPIRED: 'expired',
  DISPUTED: 'disputed',
};

/** Matching holati — statusdan BUTUNLAY ajratilgan. */
const MATCHING_STATE = {
  PENDING: 'pending',
  RUNNING: 'running',
  DONE: 'done',
  NO_PROVIDERS: 'no_providers',
  FAILED: 'failed',
};

/** Taklif statuslari. */
const OFFER_STATUS = {
  ACTIVE: 'active',
  WITHDRAWN: 'withdrawn',
  ACCEPTED: 'accepted',
  REJECTED: 'rejected',
  EXPIRED: 'expired',
};

/**
 * Ruxsat etilgan o'tishlar.
 *
 * `accepted -> active` ataylab bor: ijrochi bekor qilsa talab qaytib ochiladi
 * (konsepsiya talabi). `completed` va `cancelled` — oxirgi holat.
 */
const ALLOWED = {
  [STATUS.DRAFT]: [STATUS.ACTIVE, STATUS.CANCELLED],
  [STATUS.ACTIVE]: [STATUS.ACCEPTED, STATUS.CANCELLED, STATUS.EXPIRED],
  [STATUS.ACCEPTED]: [STATUS.IN_PROGRESS, STATUS.CANCELLED, STATUS.ACTIVE],
  [STATUS.IN_PROGRESS]: [STATUS.COMPLETED, STATUS.DISPUTED, STATUS.CANCELLED],
  [STATUS.COMPLETED]: [STATUS.DISPUTED],
  [STATUS.CANCELLED]: [],
  [STATUS.EXPIRED]: [STATUS.ACTIVE],
  [STATUS.DISPUTED]: [STATUS.COMPLETED, STATUS.CANCELLED],
};

/**
 * `in_progress` qaysi modullarda ishlatiladi.
 *
 * Konsepsiya: «Har bir modulga barcha statuslar majburiy emas. Masalan,
 * alert rejimida in_progress ishlatilmaydi.» Shuning uchun REJIM bo'yicha.
 */
const MODES_WITH_IN_PROGRESS = new Set(['dispatch', 'quote']);

/** Oxirgi holatmi (boshqa o'tish yo'q yoki faqat nizo). */
function isTerminal(status) {
  return status === STATUS.CANCELLED
    || status === STATUS.COMPLETED;
}

/** Talab hali taklif kutyaptimi. */
function isOpenForOffers(status) {
  return status === STATUS.ACTIVE;
}

/** O'tish ruxsat etilganmi. */
function canTransition(from, to) {
  if (from === to) return false;
  const allowed = ALLOWED[from];
  if (!allowed) return false;
  return allowed.includes(to);
}

/**
 * O'tishni tekshiradi va xato tashlaydi.
 *
 * Nega xato: jimgina `return` qilsa, chaqiruvchi «bajarildi» deb o'ylaydi
 * va status o'zgarmagan holda davom etadi — bu eng yomon xato turi.
 */
function assertTransition(from, to, context) {
  if (canTransition(from, to)) return to;
  const where = context ? ` (${context})` : '';
  const err = new Error(
    `Ruxsat etilmagan status o'tishi: «${from}» -> «${to}»${where}. `
    + `«${from}» dan mumkin: ${(ALLOWED[from] || []).join(', ') || 'hech qayerga'}`,
  );
  err.code = 'failed-precondition';
  throw err;
}

/**
 * `in_progress` bu rejimda ishlatiladimi.
 *
 * `quote` rejimida ham ishlatiladi (masalan usta ishni boshladi), lekin
 * `alert` va `recurring` da yo'q: u yerda «bajarish» tushunchasi boshqa.
 */
function usesInProgress(mode) {
  return MODES_WITH_IN_PROGRESS.has(mode);
}

/**
 * Qabul qilingandan keyingi keyingi status.
 *
 * `alert`/`recurring` da `in_progress` bo'lmagani uchun to'g'ridan-to'g'ri
 * `completed`ga o'tadi.
 */
function nextAfterAccept(mode) {
  return usesInProgress(mode) ? STATUS.IN_PROGRESS : STATUS.COMPLETED;
}

/**
 * Т-19.1 — QABUL QILINDI, LEKIN HECH NARSA BO'LMADI.
 *
 * Konsepsiyada bu holat umuman yo'q edi: kuryer «Qabul qilish»ni bosib
 * yo'q bo'lib ketsa, talab abadiy `accepted` holatda qolardi va mijoz
 * hech narsa qila olmasdi.
 *
 * @returns {{expired: boolean, deadlineAt: Date}}
 */
function assignmentDeadline(acceptedAt, mode, config, now = new Date()) {
  const minutes = (config && config.assignmentDeadlineMinutes
    && config.assignmentDeadlineMinutes[mode]) || 120;
  const at = new Date(toMillis(acceptedAt) + minutes * 60 * 1000);
  return { expired: now.getTime() >= at.getTime(), deadlineAt: at };
}

/**
 * Т-19.2 — IJROCHI BEKOR QILGANDA TAKLIFLAR NIMA BO'LADI.
 *
 * `rejected` taklif `active`ga QAYTMAYDI: narxi eskirgan, taklifchi
 * allaqachon boshqa ish olgan bo'lishi mumkin. Talab `active`ga qaytadi va
 * FAQAT yangi taklif kutiladi; eski taklifchilarga «talab yana ochiq»
 * dayjest xabari ketadi (push limiti ichida, Т-7).
 */
function offerStatusOnReopen(currentOfferStatus) {
  switch (currentOfferStatus) {
    case OFFER_STATUS.ACCEPTED:
      // Qabul qilingan taklif bekor qilindi -> withdrawn emas, rejected:
      // taklifchining o'zi qaytarib olmadi, ish bekor bo'ldi.
      return OFFER_STATUS.REJECTED;
    case OFFER_STATUS.REJECTED:
      return OFFER_STATUS.REJECTED;
    default:
      return currentOfferStatus;
  }
}

/** Taklif statusi o'tishlari. */
const OFFER_ALLOWED = {
  [OFFER_STATUS.ACTIVE]: [
    OFFER_STATUS.WITHDRAWN, OFFER_STATUS.ACCEPTED,
    OFFER_STATUS.REJECTED, OFFER_STATUS.EXPIRED,
  ],
  [OFFER_STATUS.ACCEPTED]: [OFFER_STATUS.REJECTED],
  [OFFER_STATUS.WITHDRAWN]: [],
  [OFFER_STATUS.REJECTED]: [],
  [OFFER_STATUS.EXPIRED]: [],
};

function canTransitionOffer(from, to) {
  if (from === to) return false;
  return (OFFER_ALLOWED[from] || []).includes(to);
}

function assertOfferTransition(from, to, context) {
  if (canTransitionOffer(from, to)) return to;
  const where = context ? ` (${context})` : '';
  const err = new Error(
    `Ruxsat etilmagan taklif o'tishi: «${from}» -> «${to}»${where}`,
  );
  err.code = 'failed-precondition';
  throw err;
}

/**
 * Т-19.3 — NIZO SLA.
 *
 * Nizo 48 soat ichida hal qilinishi kerak. Muddati o'tganlar admin
 * panelida qizil bo'lib ko'rinadi (13.2.x emas, admin panel vazifasi).
 */
const DISPUTE_SLA_HOURS = 48;

function disputeOverdue(disputedAt, now = new Date()) {
  return now.getTime() - toMillis(disputedAt) > DISPUTE_SLA_HOURS * 3600 * 1000;
}

/**
 * Baholash ochiqmi.
 *
 * Konsepsiya: «Platformadan tashqarida tugaydigan quote savdolarida mijoz
 * «Kelishdik» tugmasini bosadi. Shundan keyingina baholash ochiladi.»
 * Ya'ni baho FAQAT `completed` bo'yicha — `accepted` yetarli emas.
 */
function canRate(status) {
  return status === STATUS.COMPLETED;
}

/** Turli shakllardan millisekund (Firestore Timestamp, Date, ISO, number). */
function toMillis(v) {
  if (v == null) return 0;
  if (typeof v === 'number') return v;
  if (v instanceof Date) return v.getTime();
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (typeof v.toDate === 'function') return v.toDate().getTime();
  if (typeof v === 'string') {
    const t = Date.parse(v);
    return Number.isNaN(t) ? 0 : t;
  }
  if (typeof v.seconds === 'number') return v.seconds * 1000;
  return 0;
}

/**
 * Talab/LEG muddati o'tganmi — BITTA qoida (7-band): `expiresAt <= now`.
 * `expireDemandsSweeper` so'rovi ham ayni shu chegarani ishlatadi
 * (`timeWindow.expiresAt <= now`), shuning uchun «sweeper yopadi, lekin
 * acceptOffer hali qabul qiladi» oralig'i yo'q. `now` — SERVER vaqti.
 * `expiresAt` yo'q → muddatsiz (eski hujjatlar).
 */
function isPastExpiry(expiresAt, now) {
  if (!expiresAt) return false;
  return toMillis(expiresAt) <= now.getTime();
}

module.exports = {
  STATUS,
  MATCHING_STATE,
  OFFER_STATUS,
  ALLOWED,
  OFFER_ALLOWED,
  DISPUTE_SLA_HOURS,
  isTerminal,
  isOpenForOffers,
  canTransition,
  assertTransition,
  canTransitionOffer,
  assertOfferTransition,
  usesInProgress,
  nextAfterAccept,
  assignmentDeadline,
  offerStatusOnReopen,
  disputeOverdue,
  canRate,
  toMillis,
  isPastExpiry,
};
