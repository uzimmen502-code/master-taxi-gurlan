'use strict';

/**
 * AVA LOGISTICS — ORDER / SHIPMENT / LEG / CUSTODY modeli (D-3…D-10).
 *
 * Sof funksiyalar: status mashinalari, tracking raqami, QR/kod sirlari,
 * ORDER'ning hisoblanadigan statusi. Firestore YO'Q — testlar tez.
 *
 * ── TUSHUNCHALAR (13-band) ─────────────────────────────────────────────
 *   ORDER     logistics_orders/{orderId}   — mijozning buyurtmasi
 *   SHIPMENT  shipments/{shipmentId}       — bitta jismoniy quti (D-4)
 *   LEG       demands/{legId}              — marshrutning bir bo'lagi,
 *                                            MAVJUD yadro hujjati (§5)
 *   CUSTODY   custody_events/{eventId}     — O'ZGARMAS, faqat qo'shiladi (15, 16)
 *
 * ── SHIPMENT statusi ───────────────────────────────────────────────────
 *   awaiting_payment → ready → in_transit → delivered → closed
 *   side: cancelled (in_transit'gacha) · disputed · lost
 *
 * ── TO'LOV statusi (7.6) ───────────────────────────────────────────────
 *   pending → escrow_funded → release_approved → settled
 *     ├─ escrow_frozen        (nizo — avtomat payout to'xtaydi)
 *     └─ refund_pending → refunded
 *   Statusni DEMAND codebase yozadi, PULNI default codebase (ledger) —
 *   ikkisi Firestore orqali bog'lanadi (`functions/relay_escrow.js`).
 *
 * ── KIMLIK SIRLARI (D-5, D-6) ──────────────────────────────────────────
 *   qrSecret   — faqat server (shipments/{id}/private/secrets)
 *   handover   — QR payload + 6 xonali kod (sender→provider, provider→provider)
 *   delivery   — 6 xonali kod (oxirgi LEG → recipient), ALOHIDA
 */

const crypto = require('crypto');
const { toCanonicalId } = require('./ids');

const ORDERS = 'logistics_orders';
const SHIPMENTS = 'shipments';
const CUSTODY = 'custody_events';
const ROUTE_PLANS = 'route_plans';
const COUNTERS = 'logistics_counters';
const MODULE = 'logistics';

const SHIPMENT_STATUS = {
  AWAITING_PAYMENT: 'awaiting_payment',
  READY: 'ready',
  IN_TRANSIT: 'in_transit',
  DELIVERED: 'delivered',
  CLOSED: 'closed',
  CANCELLED: 'cancelled',
  DISPUTED: 'disputed',
  LOST: 'lost',
};

const SHIPMENT_ALLOWED = {
  [SHIPMENT_STATUS.AWAITING_PAYMENT]: [SHIPMENT_STATUS.READY, SHIPMENT_STATUS.CANCELLED],
  [SHIPMENT_STATUS.READY]: [SHIPMENT_STATUS.IN_TRANSIT, SHIPMENT_STATUS.CANCELLED],
  [SHIPMENT_STATUS.IN_TRANSIT]: [SHIPMENT_STATUS.DELIVERED, SHIPMENT_STATUS.DISPUTED, SHIPMENT_STATUS.LOST],
  [SHIPMENT_STATUS.DELIVERED]: [SHIPMENT_STATUS.CLOSED, SHIPMENT_STATUS.DISPUTED],
  [SHIPMENT_STATUS.DISPUTED]: [SHIPMENT_STATUS.DELIVERED, SHIPMENT_STATUS.LOST, SHIPMENT_STATUS.CLOSED],
  [SHIPMENT_STATUS.CLOSED]: [],
  [SHIPMENT_STATUS.CANCELLED]: [],
  [SHIPMENT_STATUS.LOST]: [SHIPMENT_STATUS.CLOSED],
};

const PAYMENT_STATUS = {
  PENDING: 'pending',
  ESCROW_FUNDED: 'escrow_funded',
  RELEASE_APPROVED: 'release_approved',
  SETTLED: 'settled',
  ESCROW_FROZEN: 'escrow_frozen',
  REFUND_PENDING: 'refund_pending',
  REFUNDED: 'refunded',
};

const PAYMENT_ALLOWED = {
  [PAYMENT_STATUS.PENDING]: [PAYMENT_STATUS.ESCROW_FUNDED, PAYMENT_STATUS.REFUNDED],
  [PAYMENT_STATUS.ESCROW_FUNDED]: [
    PAYMENT_STATUS.RELEASE_APPROVED, PAYMENT_STATUS.ESCROW_FROZEN, PAYMENT_STATUS.REFUND_PENDING,
  ],
  [PAYMENT_STATUS.ESCROW_FROZEN]: [PAYMENT_STATUS.RELEASE_APPROVED, PAYMENT_STATUS.REFUND_PENDING],
  [PAYMENT_STATUS.RELEASE_APPROVED]: [PAYMENT_STATUS.SETTLED],
  [PAYMENT_STATUS.REFUND_PENDING]: [PAYMENT_STATUS.REFUNDED],
  [PAYMENT_STATUS.SETTLED]: [],
  [PAYMENT_STATUS.REFUNDED]: [],
};

/** Custody egasi turlari. HUB YO'Q — bu AVA qizil chizig'i (7.5). */
const CUSTODIAN_KIND = { SENDER: 'sender', PROVIDER: 'provider', RECIPIENT: 'recipient' };

/** Handover holat belgilari (7.4, 3-qadam). */
const CONDITION_FLAGS = ['intact', 'package_damaged', 'opened', 'wet', 'other'];

function transitionError(kind, from, to, context) {
  const e = new Error(
    `Ruxsat etilmagan ${kind} o'tishi: «${from}» -> «${to}»${context ? ` (${context})` : ''}`,
  );
  e.code = 'failed-precondition';
  e.details = { reason: `${kind}_transition_denied`, from, to };
  return e;
}

function canTransitionShipment(from, to) {
  if (from === to) return false;
  return (SHIPMENT_ALLOWED[from] || []).includes(to);
}
function assertShipmentTransition(from, to, context) {
  if (canTransitionShipment(from, to)) return to;
  throw transitionError('shipment', from, to, context);
}

function canTransitionPayment(from, to) {
  if (from === to) return false;
  return (PAYMENT_ALLOWED[from] || []).includes(to);
}
function assertPaymentTransition(from, to, context) {
  if (canTransitionPayment(from, to)) return to;
  throw transitionError('payment', from, to, context);
}

/** Pul harakati boshlangan — bekor qilish endi refund orqali. */
function isShipmentCancellable(status) {
  return status === SHIPMENT_STATUS.AWAITING_PAYMENT || status === SHIPMENT_STATUS.READY;
}

/**
 * ORDER statusi — HISOBLANADI (7.2), o'z mashinasi yo'q.
 * Mijozga BITTA holat ko'rinadi (45-band).
 */
function deriveOrderStatus(shipmentStatuses) {
  const s = Array.isArray(shipmentStatuses) ? shipmentStatuses : [];
  if (s.length === 0) return 'empty';
  const all = (st) => s.every((x) => x === st);
  const any = (st) => s.some((x) => x === st);
  if (all(SHIPMENT_STATUS.CANCELLED)) return 'cancelled';
  if (s.every((x) => x === SHIPMENT_STATUS.CLOSED || x === SHIPMENT_STATUS.CANCELLED)) return 'closed';
  if (any(SHIPMENT_STATUS.DISPUTED)) return 'disputed';
  if (any(SHIPMENT_STATUS.LOST)) return 'problem';
  if (s.every((x) => [SHIPMENT_STATUS.DELIVERED, SHIPMENT_STATUS.CLOSED, SHIPMENT_STATUS.CANCELLED].includes(x))) return 'delivered';
  if (any(SHIPMENT_STATUS.IN_TRANSIT)) return 'in_transit';
  if (any(SHIPMENT_STATUS.AWAITING_PAYMENT)) return 'awaiting_payment';
  return 'ready';
}

// ═══════════════════════════════════════════════════════════════════════
// TRACKING RAQAMI (D-5) — AVA-YY-MMDD-NNNNNN
// ═══════════════════════════════════════════════════════════════════════

/** Kunlik hisoblagich kaliti (Asia/Tashkent kuni, UTC+5). */
function trackingDayKey(now) {
  const local = new Date(now.getTime() + 5 * 3600 * 1000);
  const yy = String(local.getUTCFullYear()).slice(2);
  const mm = String(local.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(local.getUTCDate()).padStart(2, '0');
  return `${yy}${mm}${dd}`;
}

/**
 * `AVA-YY-MMDD-NNNNNN`. `seq` — shu kundagi tranzaksion hisoblagich,
 * ya'ni kolliziya YO'Q (11-bo'lim, 6-savol: PROPOSED shakl).
 */
function formatTrackingNumber(now, seq) {
  const key = trackingDayKey(now);
  return `AVA-${key.slice(0, 2)}-${key.slice(2)}-${String(seq).padStart(6, '0')}`;
}

const TRACKING_RE = /^AVA-\d{2}-\d{4}-\d{6}$/;

// ═══════════════════════════════════════════════════════════════════════
// SIRLAR — QR va kodlar (D-5, D-6, D-7)
// ═══════════════════════════════════════════════════════════════════════

function newQrSecret() {
  return crypto.randomBytes(16).toString('hex');
}

function hmacHex(secret, message) {
  return crypto.createHmac('sha256', String(secret)).update(String(message)).digest('hex');
}

/** 6 xonali kod — HMAC'ning birinchi 4 baytidan. */
function sixDigits(hex) {
  const n = parseInt(hex.slice(0, 8), 16) % 1000000;
  return String(n).padStart(6, '0');
}

/** Topshirish kodi — sender→provider va provider→provider uchun BITTA. */
function handoverCodeFor(shipmentId, qrSecret) {
  return sixDigits(hmacHex(qrSecret, `handover:${shipmentId}`));
}

/** Yetkazish kodi — FAQAT oxirgi LEG → qabul qiluvchi. Alohida kod. */
function deliveryCodeFor(shipmentId, qrSecret) {
  return sixDigits(hmacHex(qrSecret, `delivery:${shipmentId}`));
}

/** QR ichidagi token (16 hex) — kod bilan bir xil sirdan, lekin uzunroq. */
function handoverTokenFor(shipmentId, qrSecret) {
  return hmacHex(qrSecret, `qr:${shipmentId}`).slice(0, 16);
}

/** QR payload — `AVA1|{shipmentId}|{token}`. Klient uni FAQAT ko'rsatadi. */
function qrPayloadFor(shipmentId, qrSecret) {
  return `AVA1|${shipmentId}|${handoverTokenFor(shipmentId, qrSecret)}`;
}

/** QR payload'dan `{shipmentId, token}`; noto'g'ri shakl — null. */
function parseQrPayload(payload) {
  const parts = String(payload || '').split('|');
  if (parts.length !== 3 || parts[0] !== 'AVA1') return null;
  if (!parts[1] || !/^[0-9a-f]{16}$/.test(parts[2])) return null;
  return { shipmentId: parts[1], token: parts[2] };
}

/** Doimiy vaqtli taqqoslash — vaqt bo'yicha hujumga yo'l yo'q. */
function safeEqual(a, b) {
  const x = Buffer.from(String(a || ''));
  const y = Buffer.from(String(b || ''));
  if (x.length !== y.length || x.length === 0) return false;
  return crypto.timingSafeEqual(x, y);
}

/**
 * Taqdim etilgan dalil (6 xonali kod YOKI QR payload) shu jo'natmaga
 * mosmi. Ikkalasi ham bitta sirdan, provider tanlaydi — kamera
 * ruxsati (L13) hal bo'lgunga qadar qo'lda kod ham yetadi.
 */
function verifyHandoverProof(shipmentId, qrSecret, { code, qrPayload } = {}) {
  if (qrPayload) {
    const parsed = parseQrPayload(qrPayload);
    if (!parsed || parsed.shipmentId !== shipmentId) return false;
    return safeEqual(parsed.token, handoverTokenFor(shipmentId, qrSecret));
  }
  if (code) return safeEqual(String(code).trim(), handoverCodeFor(shipmentId, qrSecret));
  return false;
}

function verifyDeliveryCode(shipmentId, qrSecret, code) {
  return safeEqual(String(code || '').trim(), deliveryCodeFor(shipmentId, qrSecret));
}

// ═══════════════════════════════════════════════════════════════════════
// KOD URINISHLARI CHEKLOVI (audit S4/L7, 2026-10-16)
// ═══════════════════════════════════════════════════════════════════════

/** Standart (module_config `logistics.*` ustiga yozadi): pul/tarif QIYMATI EMAS. */
const CODE_ATTEMPT_DEFAULTS = { maxFailed: 5, lockMinutes: 15 };

function msOf(v) {
  if (v == null) return 0;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function posIntOr(v, d) {
  const n = Number(v);
  return Number.isInteger(n) && n > 0 ? n : d;
}

/** Konfigdan `{maxFailed, lockMs}`; noto'g'ri/yo'q qiymat — standart (qattiq tomon). */
function codeAttemptLimits(config) {
  const c = ((config || {}).logistics) || {};
  return {
    maxFailed: posIntOr(c.codeMaxFailedAttempts, CODE_ATTEMPT_DEFAULTS.maxFailed),
    lockMs: posIntOr(c.codeLockMinutes, CODE_ATTEMPT_DEFAULTS.lockMinutes) * 60 * 1000,
  };
}

/** Qulf qolgan millisekund (0 — qulf yo'q yoki muddati o'tgan). */
function codeLockRemainingMs(doc, now) {
  const until = msOf((doc || {}).lockedUntil);
  const left = until - now.getTime();
  return left > 0 ? left : 0;
}

/**
 * Xato urinishdan KEYINGI hujjat maydonlari. Qulf muddati o'tgan bo'lsa
 * hisob noldan boshlanadi. `fails` limitga yetsa — `lockedUntil` qo'yiladi.
 */
function registerFailedCodeAttempt(doc, now, limits) {
  const prev = doc || {};
  const expired = msOf(prev.lockedUntil) > 0 && codeLockRemainingMs(prev, now) === 0;
  const base = expired ? 0 : (Number(prev.fails) || 0);
  const fails = base + 1;
  const locked = fails >= limits.maxFailed;
  return {
    fails,
    lastFailAt: now,
    lockedUntil: locked ? new Date(now.getTime() + limits.lockMs) : null,
  };
}

/**
 * Dalil rasmi URL'i FAQAT shu loyihaning Firebase Storage'idagi
 * `logistics/{callerId}/{fayl}` bo'lishi mumkin (Flutter `LogisticsPhotoStorage`
 * shu yo'lga yuklaydi; `storage.rules` — yuklash faqat o'z papkasiga).
 * `buckets` bo'sh bo'lsa bucket PIN QILINMAYDI (faqat host + yo'l tekshiriladi).
 */
function isOwnProofPhotoUrl(url, callerId, buckets) {
  const id = String(callerId || '');
  if (!id || !/^\d+$/.test(id)) return false;
  let u;
  try { u = new URL(String(url || '')); } catch (_) { return false; }
  if (u.protocol !== 'https:' || u.username || u.password || u.port) return false;
  let bucket;
  let object;
  try {
    if (u.hostname === 'firebasestorage.googleapis.com') {
      const m = /^\/v0\/b\/([^/]+)\/o\/([^/]+)$/.exec(u.pathname);
      if (!m) return false;
      bucket = m[1];
      object = decodeURIComponent(m[2]);
    } else if (u.hostname === 'storage.googleapis.com') {
      const m = /^\/([^/]+)\/(.+)$/.exec(u.pathname);
      if (!m) return false;
      bucket = m[1];
      object = decodeURIComponent(m[2]);
    } else {
      return false;
    }
  } catch (_) { return false; }
  if (Array.isArray(buckets) && buckets.length && !buckets.includes(bucket)) return false;
  const prefix = `logistics/${id}/`;
  if (!object.startsWith(prefix)) return false;
  const name = object.slice(prefix.length);
  return name.length > 0 && !name.includes('/') && !name.includes('..');
}

// ═══════════════════════════════════════════════════════════════════════
// LEG yordamchilari
// ═══════════════════════════════════════════════════════════════════════

/**
 * Custody hodisasi idempotentlik kaliti — TABIIY: bitta LEG bir marta
 * olinadi va bir marta topshiriladi. `clientRequestId` ixtiyoriy
 * qo'shimcha (bo'sh bo'lsa kalit `{shipment}_{leg}_{kind}`): ikkinchi
 * chaqiruv ikkinchi hodisa yaratmaydi (21-band).
 */
function custodyIdempotencyKey(shipmentId, legId, kind, clientRequestId) {
  const suffix = String(clientRequestId || '').slice(0, 64);
  return `${shipmentId}_${legId}_${kind}${suffix ? `_${suffix}` : ''}`;
}

/** LEG uchun handover tomonlari: kimdan oladi, kimga beradi. */
function handoverKindsFor(index, count) {
  return {
    fromKind: index === 0 ? CUSTODIAN_KIND.SENDER : CUSTODIAN_KIND.PROVIDER,
    toKind: index === count - 1 ? CUSTODIAN_KIND.RECIPIENT : CUSTODIAN_KIND.PROVIDER,
  };
}

function normalizeConditionFlags(flags) {
  if (!Array.isArray(flags)) return ['intact'];
  const out = flags.map((f) => String(f)).filter((f) => CONDITION_FLAGS.includes(f));
  return out.length ? [...new Set(out)] : ['intact'];
}

// ═══════════════════════════════════════════════════════════════════════
// ISHGA TUSHIRISH BOSQICHI (CLAUDE.md 42) — INTERNAL → PUBLIC
// ═══════════════════════════════════════════════════════════════════════

/**
 * `module_config/logistics_all.logistics.stage`:
 *   internal — FAQAT `testerIds` (kanonik telefon ID) jo'natadi VA LEG oladi;
 *   public   — hamma.
 * Noma'lum/yo'q qiymat — `internal` (yopiq tomonga xato, 53-band): sinov
 * ro'yxatisiz hech kim kirmaydi. PILOT — UNKNOWN (ega qarori yo'q).
 */
const STAGE = { INTERNAL: 'internal', PUBLIC: 'public' };

function stageOf(config) {
  const s = ((config || {}).logistics || {}).stage;
  return s === STAGE.PUBLIC ? STAGE.PUBLIC : STAGE.INTERNAL;
}

/** Shu foydalanuvchi joriy bosqichda logistikadan foydalana oladimi. */
function isStageAllowed(config, userId) {
  if (stageOf(config) === STAGE.PUBLIC) return true;
  const id = toCanonicalId(userId || '');
  if (!id) return false;
  const list = ((config || {}).logistics || {}).testerIds;
  if (!Array.isArray(list)) return false;
  return list.some((t) => toCanonicalId(String(t || '')) === id);
}

module.exports = {
  ORDERS,
  SHIPMENTS,
  CUSTODY,
  ROUTE_PLANS,
  COUNTERS,
  MODULE,
  SHIPMENT_STATUS,
  SHIPMENT_ALLOWED,
  PAYMENT_STATUS,
  PAYMENT_ALLOWED,
  CUSTODIAN_KIND,
  CONDITION_FLAGS,
  TRACKING_RE,
  canTransitionShipment,
  assertShipmentTransition,
  canTransitionPayment,
  assertPaymentTransition,
  isShipmentCancellable,
  deriveOrderStatus,
  trackingDayKey,
  formatTrackingNumber,
  newQrSecret,
  handoverCodeFor,
  deliveryCodeFor,
  handoverTokenFor,
  qrPayloadFor,
  parseQrPayload,
  verifyHandoverProof,
  verifyDeliveryCode,
  CODE_ATTEMPT_DEFAULTS,
  codeAttemptLimits,
  codeLockRemainingMs,
  registerFailedCodeAttempt,
  isOwnProofPhotoUrl,
  custodyIdempotencyKey,
  handoverKindsFor,
  normalizeConditionFlags,
  STAGE,
  stageOf,
  isStageAllowed,
};
