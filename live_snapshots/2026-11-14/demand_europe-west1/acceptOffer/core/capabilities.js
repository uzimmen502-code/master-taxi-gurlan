'use strict';

/**
 * CAPABILITY MODELI — «nimaga ruxsati bor» (D-12…D-16, D-TAXI, D-SERVICE).
 *
 * Bu fayl YAGONA haqiqat manbai: status nomlari, ruxsat beradigan
 * holatlar, o'tish qoidalari va muddat matematikasi faqat shu yerda.
 * Qoida (`firestore.rules`), manba (`sources/capabilities.js`), sweeper
 * va callable'lar shu yerdan oladi (7-qoida).
 *
 * ── HUJJAT SHAKLI (ega qarori, 2026-10-06; T-1a bilan yangilangan) ────
 *
 *   provider_capabilities/{accountId}
 *     identity: { accountId, primaryUid }              ← FAQAT SERVER
 *     courier:  { active: true, regionIds: [...], ... } ← KLIENT
 *     taxi:     { active: true, ... }                   ← KLIENT
 *     status:   { courier: 'trial', taxi: 'starter' }   ← FAQAT SERVER
 *     window:   { courier: { startedAt, endsAt, graceGrantedAt, graceEndsAt },
 *                 taxi:    { startedAt, verificationDueAt, billingGraceUntil } }
 *     review:   { courier: { submittedAt, reviewedBy } } ← FAQAT SERVER
 *     suspend:  { courier: { at, reason, by } }          ← FAQAT SERVER
 *
 * KALIT — `accountId` (T-1a): `users/{phoneId}.accountId`, server beradi,
 * o'zgarmas. Telefon almashsa ham starter davri shu yerda qoladi
 * (D-TAXI-2). `identity.primaryUid` — kanon telefon: matching, presence
 * va `demand_matches` shu ID bilan ishlaydi, shuning uchun manba
 * nomzodga `providerId = primaryUid` beradi.
 *
 * ── HAR XIZMATNING O'Z LIFECYCLE'I (T-2) ───────────────────────────────
 * Kuryer: 3 kun sinov + bir martalik 5 kun grace + hujjat (D-15, D-15.1).
 * Taksi: 4 oy starter (ishlaydi, bepul) → verification_required →
 * verified (D-TAXI-1…6). Qolganlari (D-SERVICE-1): yoqdi → ishlaydi.
 *
 * ── `active` ≠ `status` (T-3) ──────────────────────────────────────────
 * `active` — foydalanuvchining XOHISHI («hozir so'rov olmoqchiman»),
 * `status` — HUQUQIY holat. Ega misollarida `courier = active` deb
 * yozilgan; T-3 bo'yicha huquqiy holat alohida nom oladi (`enabled`),
 * `active` esa xohish belgisi bo'lib qoladi.
 *
 * ── NEGA `status` XIZMAT ICHIDA EMAS, ALOHIDA KALITDA ──────────────────
 * D-14: foydalanuvchi o'ziga o'zi `approved`/`verified` berolmasin.
 * `diff().affectedKeys()` faqat YUQORI DARAJADAGI kalitlarni ko'radi,
 * shuning uchun server kalitlari alohida turadi va himoya bitta qatorga
 * sig'adi — yangi xizmat qo'shilganda qoidaga tegish kerak emas.
 */

/** Xizmat kalitlari — `DemandModule.wire` bilan BIR XIL bo'lishi shart. */
const SERVICES = ['courier', 'taxi', 'service', 'seller', 'freight'];

/**
 * Server egalik qiladigan TOP-LEVEL kalitlar. Qoida ayni shu ro'yxatni
 * ishlatadi (`capabilityServerKeysUntouched`).
 */
const SERVER_KEYS = ['identity', 'status', 'window', 'review', 'suspend', 'debt'];

const DAY_MS = 24 * 60 * 60 * 1000;

/** Hamma xizmat uchun umumiy holatlar. */
const COMMON = {
  notRegistered: 'not_registered',
  suspended: 'suspended',
};

/** Kuryer lifecycle'i (D-15, D-15.1). */
const COURIER = {
  trial: 'trial',
  /**
   * 3 kun tugadi, BIR MARTALIK 5 kunlik grace ichida. Nomi «expired»
   * bo'lsa ham kuryer ISHLASHDA DAVOM ETADI — ega qarori.
   */
  trialExpired: 'trial_expired',
  documentSubmitted: 'document_submitted',
  underReview: 'under_review',
  approved: 'approved',
  documentRejected: 'document_rejected',
};

/** Taksi lifecycle'i (D-TAXI-1, D-TAXI-4). */
const TAXI = {
  /** Ariza EMAS — real ishlash huquqi, 4 oy bepul (D-TAXI-1, 3). */
  starter: 'starter',
  /** 4 oy tugadi: mavjud ish davom etadi, YANGI PULLIK reys yo'q (D-TAXI-5). */
  verificationRequired: 'verification_required',
  /** Faqat admin beradi (D-TAXI-4). */
  verified: 'verified',
};

/** Oddiy xizmatlar (D-SERVICE-1): yoqdi → ishlaydi. */
const SIMPLE = {
  enabled: 'enabled',
};

/** Hamma status nomlari bitta joyda — UI va admin uchun. */
const STATUS = { ...COMMON, ...COURIER, ...TAXI, ...SIMPLE };

const TRIAL_DAYS = 3;
const GRACE_DAYS = 5;
const STARTER_MONTHS = 4;
const BILLING_GRACE_MONTHS = 4;

/**
 * Har xizmatning JORIY kelishuv versiyasi (D-SERVICE-2, D-TAXI-24).
 * Matn o'zgarsa raqam oshiriladi — eski versiyani qabul qilgan odam
 * yangisini qayta qabul qilmaguncha pullik reys e'lon qila olmaydi.
 * Ikkala codebase ham shu raqamni ko'radi (nusxa pariteti).
 */
const AGREEMENT_VERSIONS = { taxi: 1, courier: 1, seller: 1, freight: 1, service: 1 };

/**
 * Kelishuv xizmatni YOQISHDAN OLDIN shartmi.
 *
 * Taksi — YO'Q (D-TAXI-24.1, ega qarori 2026-10-06): starter uchun
 * kelishuv shart emas, u 4 oy o'tib `verification_required` bo'lganda
 * tizim tomonidan taqdim qilinadi (`AGREEMENT_DUE_STATUSES`).
 *
 * Boshqa xizmatlar uchun kelishuv MATNI hali ega tomonidan berilmagan —
 * matnsiz «qabul qildim» tugmasi yuridik jihatdan bo'sh bo'lardi (1-qoida:
 * biznes qoidani o'ylab topma). Matn kelganda `true` qilinadi; o'sha
 * paytgacha ularda kelishuv ixtiyoriy.
 */
const AGREEMENT_GATED = { taxi: false, courier: false, seller: false, freight: false, service: false };

/**
 * Kelishuv lifecycle'ning QAYSI holatlarida TALAB qilinadi (D-TAXI-24.1).
 *
 * Taksi: `verification_required` (tizim taqdim qiladi) va `verified`
 * (pullik e'lon oldidan tekshiriladi; admin `verified` berishdan oldin
 * ham). `starter` — YO'Q. Boshqa xizmatlar: ro'yxatda yo'q = hech qachon
 * (gate orqali yoqilganda `AGREEMENT_GATED` ishlaydi).
 */
const AGREEMENT_DUE_STATUSES = {
  taxi: [TAXI.verificationRequired, TAXI.verified],
};

/** Shu xizmat shu holatda kelishuvsiz davom eta olmaydimi. */
function agreementDue(service, status) {
  const list = AGREEMENT_DUE_STATUSES[service];
  return Array.isArray(list) && list.includes(normalizeStatus(service, status));
}

/** `service_agreements/{accountId}` da shu xizmat uchun joriy versiya qabul qilinganmi. */
function hasCurrentAgreement(agreementDoc, service) {
  const a = ((agreementDoc || {})[service]) || {};
  const required = AGREEMENT_VERSIONS[service];
  return !!required && Number(a.version) >= required && !!a.acceptedAt;
}

/**
 * Oyni qo'shish — oy oxiriga QISQARTIRIB (31-yanvar + 1 oy = 28/29-fevral).
 * JS `setMonth` oshib ketadi (3-mart), bu esa muddatni bir necha kunga
 * uzaytiradi va deterministik emas.
 */
function addMonths(date, months) {
  const d = new Date(date instanceof Date ? date.getTime() : date);
  const day = d.getUTCDate();
  d.setUTCDate(1);
  d.setUTCMonth(d.getUTCMonth() + months);
  const lastDay = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).getUTCDate();
  d.setUTCDate(Math.min(day, lastDay));
  return d;
}

const simpleLifecycle = {
  initial: SIMPLE.enabled,
  statuses: [COMMON.notRegistered, SIMPLE.enabled, COMMON.suspended],
  working: [SIMPLE.enabled],
  paidPublish: [SIMPLE.enabled],
  transitions: {
    [COMMON.notRegistered]: { [SIMPLE.enabled]: ['provider', 'admin'] },
    [SIMPLE.enabled]: { [COMMON.suspended]: ['admin'] },
    [COMMON.suspended]: { [SIMPLE.enabled]: ['admin'] },
  },
  /** Boshlanganda yoziladigan muddat oynasi — oddiy xizmatda yo'q. */
  window: () => null,
};

/**
 * Har xizmatning lifecycle'i (T-2).
 *
 * `working`     — mavjud ishni davom ettirish / nomzod bo'lish ruxsati.
 * `paidPublish` — YANGI PULLIK e'lon ruxsati (taksida farq qiladi: D-TAXI-5).
 */
const LIFECYCLES = {
  courier: {
    initial: COURIER.trial,
    statuses: [
      COMMON.notRegistered, COURIER.trial, COURIER.trialExpired,
      COURIER.documentSubmitted, COURIER.underReview, COURIER.approved,
      COURIER.documentRejected, COMMON.suspended,
    ],
    working: [
      COURIER.trial, COURIER.trialExpired, COURIER.documentSubmitted,
      COURIER.underReview, COURIER.approved,
    ],
    paidPublish: [
      COURIER.trial, COURIER.trialExpired, COURIER.documentSubmitted,
      COURIER.underReview, COURIER.approved,
    ],
    transitions: {
      [COMMON.notRegistered]: { [COURIER.trial]: ['provider', 'admin'] },
      [COURIER.trial]: {
        [COURIER.documentSubmitted]: ['provider'],
        [COURIER.trialExpired]: ['system'],
        [COURIER.approved]: ['admin'],
        [COMMON.suspended]: ['admin'],
      },
      [COURIER.trialExpired]: {
        [COURIER.documentSubmitted]: ['provider'],
        [COMMON.suspended]: ['system', 'admin'],
        [COURIER.approved]: ['admin'],
      },
      [COURIER.documentSubmitted]: {
        [COURIER.underReview]: ['admin'],
        [COURIER.approved]: ['admin'],
        [COURIER.documentRejected]: ['admin'],
        [COMMON.suspended]: ['admin'],
      },
      [COURIER.underReview]: {
        [COURIER.approved]: ['admin'],
        [COURIER.documentRejected]: ['admin'],
        [COMMON.suspended]: ['admin'],
      },
      [COURIER.documentRejected]: {
        [COURIER.documentSubmitted]: ['provider'],
        [COMMON.suspended]: ['admin'],
      },
      // TIKLANISH (D-15.1): `suspended` tupik emas.
      [COMMON.suspended]: {
        [COURIER.documentSubmitted]: ['provider'],
        [COURIER.approved]: ['admin'],
      },
      [COURIER.approved]: {
        [COMMON.suspended]: ['admin'],
        [COURIER.underReview]: ['admin'],
      },
    },
    window: (now) => ({
      startedAt: now,
      endsAt: new Date(now.getTime() + TRIAL_DAYS * DAY_MS),
      graceGrantedAt: null,
      graceEndsAt: null,
    }),
  },

  taxi: {
    initial: TAXI.starter,
    statuses: [
      COMMON.notRegistered, TAXI.starter, TAXI.verificationRequired,
      TAXI.verified, COMMON.suspended,
    ],
    // `verification_required` da mavjud ish DAVOM ETADI (D-TAXI-5).
    working: [TAXI.starter, TAXI.verificationRequired, TAXI.verified],
    // Yangi pullik reys — faqat starter (bepul davr) yoki verified.
    paidPublish: [TAXI.starter, TAXI.verified],
    transitions: {
      [COMMON.notRegistered]: { [TAXI.starter]: ['provider', 'admin'] },
      [TAXI.starter]: {
        [TAXI.verificationRequired]: ['system'],
        [TAXI.verified]: ['admin'],
        [COMMON.suspended]: ['admin'],
      },
      [TAXI.verificationRequired]: {
        [TAXI.verified]: ['admin'],
        [COMMON.suspended]: ['admin'],
      },
      [TAXI.verified]: {
        [TAXI.verificationRequired]: ['admin'],
        [COMMON.suspended]: ['admin'],
      },
      [COMMON.suspended]: {
        [TAXI.verified]: ['admin'],
        [TAXI.verificationRequired]: ['admin'],
      },
    },
    /**
     * D-TAXI-2: `verificationDueAt = startedAt + 4 oy`. Bir accountId
     * uchun BIR MARTA — `requestCapability` mavjud oynani qayta yozmaydi.
     */
    window: (now) => ({
      startedAt: now,
      verificationDueAt: addMonths(now, STARTER_MONTHS),
      billingGraceUntil: null,
    }),
  },

  service: simpleLifecycle,
  seller: simpleLifecycle,
  freight: simpleLifecycle,
};

/**
 * ADMIN QO'SHGANDA qaysi holatgacha olib boriladi (`adminGrantCapability`).
 *
 * Kuryer — darhol `approved` (ega qarori 2026-10-07): admin odamni o'zi
 * kafolatlaydi; hujjat oqimi (`submitCapabilityDocument`) hali yo'q,
 * `trial` bersa 8 kunda sweeper to'xtatib qo'yardi. Yo'l state machine
 * BO'YLAB yuradi — har qadam `canTransition(..., 'admin')` bilan
 * tekshiriladi va auditga alohida tushadi; yangi o'tish qo'shilmaydi.
 *
 * Ro'yxatda yo'q xizmatni admin qo'sha olmaydi — ega qarori yo'q.
 */
const ADMIN_GRANT_PATH = {
  courier: [COURIER.trial, COURIER.approved],
};

/**
 * KURYER ARIZASINI TASDIQLASH REJIMI (D-15.3, ega qarori 2026-10-07) —
 * `settings/courier.approvalMode`, admin panelda almashtiriladi
 * (`adminSetCourierApprovalMode`, audit bilan).
 *
 *   manual — ariza → `trial` (D-15: 3 kun + bir martalik 5 kun grace),
 *            admin ro'yxatdan tasdiqlaydi. STANDART.
 *   auto   — ariza → darhol `approved`: state machine bo'ylab
 *            (`trial → approved`, admin siyosati sifatida), auditga tushadi.
 *
 * Noma'lum yoki bo'sh qiymat — `manual` (xavfsiz tomon). Rejim faqat
 * ARIZA paytida qo'llanadi: `auto`ga o'tish mavjud `trial`larni
 * o'zgartirmaydi — ularni admin ro'yxatdan tasdiqlaydi.
 */
const COURIER_APPROVAL_MODES = Object.freeze({ manual: 'manual', auto: 'auto' });

function courierApprovalModeOf(settingsDoc) {
  return (settingsDoc && settingsDoc.approvalMode) === COURIER_APPROVAL_MODES.auto
    ? COURIER_APPROVAL_MODES.auto
    : COURIER_APPROVAL_MODES.manual;
}

function isService(v) {
  return Object.prototype.hasOwnProperty.call(LIFECYCLES, String(v || ''));
}

function lifecycleOf(service) {
  return isService(service) ? LIFECYCLES[service] : null;
}

/** Noto'g'ri yoki yo'q qiymat -> `not_registered`. */
function normalizeStatus(service, v) {
  const lc = lifecycleOf(service);
  const s = String(v || '').trim();
  return lc && lc.statuses.includes(s) ? s : COMMON.notRegistered;
}

function statusOf(doc, service) {
  const st = (doc && doc.status) || {};
  return normalizeStatus(service, st[service]);
}

/** Mavjud ishni davom ettirish / nomzod bo'lish ruxsati. */
function isWorking(service, status) {
  const lc = lifecycleOf(service);
  return !!lc && lc.working.includes(normalizeStatus(service, status));
}

/** YANGI PULLIK e'lon ruxsati (taksida `verification_required` YO'Q). */
function canPublishPaid(doc, service) {
  const lc = lifecycleOf(service);
  return !!lc && lc.paidPublish.includes(statusOf(doc, service));
}

/**
 * Nomzod sifatida olinadimi — IKKI shart (T-3):
 * `status` (HUQUQ) ishlaydigan holatda **va** `active` (XOHISH) true.
 */
function isEligible(doc, service) {
  if (!doc || !isService(service)) return false;
  const svc = doc[service] || {};
  return isWorking(service, statusOf(doc, service)) && svc.active === true;
}

/**
 * SUSPENSION QO'LDAGI ISHNI TO'XTATMAYDI (ega tasdiqlagan).
 * `suspended` yangi tayinlashni yopadi, lekin boshlangan ishni
 * tugatishga ruxsat beradi — custody uzilmasin (15-qoida).
 */
function canFinishActive(doc, service) {
  if (!doc || !isService(service)) return false;
  return statusOf(doc, service) !== COMMON.notRegistered;
}

/** O'tish ruxsat etilganmi (17-qoida: markazlashgan state machine). */
function canTransition(service, from, to, actor) {
  const lc = lifecycleOf(service);
  if (!lc) return false;
  const f = normalizeStatus(service, from);
  const t = normalizeStatus(service, to);
  if (f === t) return false;
  const allowed = (lc.transitions[f] || {})[t];
  return Array.isArray(allowed) && allowed.includes(actor);
}

/** Boshlanganda yoziladigan muddat oynasi (yoki `null`). */
function windowFor(service, now) {
  const lc = lifecycleOf(service);
  const n = now instanceof Date ? now : new Date(now);
  return lc ? lc.window(n) : null;
}

function toMillis(v) {
  if (!v) return 0;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

/**
 * Muddat bo'yicha KEYINGI qadam — sweeper shu qarorni bajaradi.
 * Sof funksiya, xizmatga qarab tarmoqlanadi.
 *
 * @returns {{action: 'none'|'grant_grace'|'suspend'|'require_verification', patch?: object}}
 */
function nextStep(doc, service, now) {
  const nowMs = (now instanceof Date ? now : new Date(now)).getTime();
  const status = statusOf(doc, service);
  const win = ((doc && doc.window) || {})[service] || {};

  if (service === 'courier') {
    const endsMs = toMillis(win.endsAt);
    const graceEndsMs = toMillis(win.graceEndsAt);
    if (status === COURIER.trial) {
      // Muddat ma'lum emas — tegilmaydi (yangi arizani to'xtatib qo'ymasin).
      if (!endsMs || nowMs <= endsMs) return { action: 'none' };
      // EXTENSION BIR MARTA: `graceGrantedAt` bo'sh bo'lishi shart.
      if (win.graceGrantedAt) {
        return { action: 'suspend', patch: { status: COMMON.suspended, reason: 'documents_missing' } };
      }
      return {
        action: 'grant_grace',
        patch: {
          status: COURIER.trialExpired,
          graceGrantedAt: new Date(nowMs),
          graceEndsAt: new Date(nowMs + GRACE_DAYS * DAY_MS),
        },
      };
    }
    if (status === COURIER.trialExpired) {
      if (!graceEndsMs || nowMs <= graceEndsMs) return { action: 'none' };
      return { action: 'suspend', patch: { status: COMMON.suspended, reason: 'documents_missing' } };
    }
    // Hujjat yuklangan / ko'rilmoqda / tasdiqlangan — soat TO'XTAGAN.
    return { action: 'none' };
  }

  if (service === 'taxi') {
    // D-TAXI-4: 4 oy tugadi -> verification_required. Grace YO'Q, akkaunt
    // bloklanmaydi, boshqa capability'lar tegilmaydi (D-TAXI-5).
    if (status !== TAXI.starter) return { action: 'none' };
    const dueMs = toMillis(win.verificationDueAt);
    if (!dueMs || nowMs <= dueMs) return { action: 'none' };
    return {
      action: 'require_verification',
      patch: { status: TAXI.verificationRequired },
    };
  }

  return { action: 'none' };
}

/**
 * TAKSI BILLING ruxsati (D-TAXI-6, D-TAXI-6.1, T-6) — YAGONA mezon.
 *
 * 2% faqat: `verified` **va** billing grace tugagan bo'lsa. Grace —
 * mavjud tasdiqlangan haydovchilar uchun (migratsiya + 4 oy); yangi
 * haydovchi `starter` davrida umuman billing ko'rmaydi (`starter`
 * `paidPublish`da bor, lekin `isBillable` false).
 *
 * D-TAXI-6.1: global flag YO'Q — billing har haydovchi uchun shu
 * funksiya `true` bo'lishi bilan avtomatik ochiladi.
 */
function isTaxiBillable(doc, now) {
  if (statusOf(doc, 'taxi') !== TAXI.verified) return false;
  const win = ((doc && doc.window) || {}).taxi || {};
  const graceMs = toMillis(win.billingGraceUntil);
  const nowMs = (now instanceof Date ? now : new Date(now)).getTime();
  return !graceMs || nowMs > graceMs;
}

/** Sweeper so'rovi uchun: shu xizmatda muddat kutayotgan statuslar. */
function sweepableStatuses(service) {
  if (service === 'courier') return [COURIER.trial, COURIER.trialExpired];
  if (service === 'taxi') return [TAXI.starter];
  return [];
}

/** Server yozgan kimlik (T-1a). */
function identityOf(doc) {
  const id = (doc && doc.identity) || {};
  return {
    accountId: String(id.accountId || ''),
    primaryUid: String(id.primaryUid || ''),
  };
}

module.exports = {
  SERVICES,
  SERVER_KEYS,
  STATUS,
  COMMON,
  COURIER,
  TAXI,
  SIMPLE,
  LIFECYCLES,
  ADMIN_GRANT_PATH,
  COURIER_APPROVAL_MODES,
  courierApprovalModeOf,
  TRIAL_DAYS,
  GRACE_DAYS,
  STARTER_MONTHS,
  BILLING_GRACE_MONTHS,
  AGREEMENT_VERSIONS,
  AGREEMENT_GATED,
  AGREEMENT_DUE_STATUSES,
  agreementDue,
  hasCurrentAgreement,
  DAY_MS,
  addMonths,
  isService,
  lifecycleOf,
  normalizeStatus,
  statusOf,
  isWorking,
  canPublishPaid,
  isEligible,
  canFinishActive,
  canTransition,
  windowFor,
  nextStep,
  isTaxiBillable,
  sweepableStatuses,
  identityOf,
  toMillis,
};
