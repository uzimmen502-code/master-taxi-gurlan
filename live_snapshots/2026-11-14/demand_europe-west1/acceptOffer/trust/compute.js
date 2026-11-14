'use strict';

/**
 * Т-18 — INTERNAL TRUST.
 *
 * Konsepsiya: «Eski voqealarning ta'siri vaqt o'tishi bilan kamayadi.
 * Shunda bir marta xato qilgan odam abadiy jazolanmaydi.»
 *
 * Shuning uchun trust SAQLANMAYDI, HISOBLANADI: `trust_events` jurnalidan
 * har safar qaytadan. Natija `provider_stats`ga keshlanadi (faqat server
 * yozadi), lekin haqiqat manbai — o'zgarmas voqealar jurnali.
 *
 * Nega shunday: agar trust «joriy qiymat ± delta» tarzida saqlansa, bitta
 * xato hisob abadiy qolib ketadi va uni tuzatish imkonsiz bo'ladi.
 * Jurnal esa har doim qayta hisoblashga imkon beradi.
 *
 * MIJOZ (HARIDOR) UCHUN HAM TRUST BOR — konsepsiya talabi: «Ko'p talab
 * berib, hech birini qabul qilmaslik yoki ko'p bekor qilish unga ta'sir
 * qiladi.» Ayni shu funksiyalar ikkala tomon uchun ishlaydi.
 */

/** Voqea turlari — `trust_events.type`. */
const EVENT = {
  COMPLETED: 'completed',
  LATE_CANCEL: 'lateCancel',
  NO_SHOW: 'noShow',
  CONFIRMED_COMPLAINT: 'confirmedComplaint',
  RATING_5: 'rating5',
  RATING_LOW: 'ratingLow',
  /** Haridor tomoni: ko'p talab berib hech birini qabul qilmaslik. */
  DEMAND_ABANDONED: 'demandAbandoned',
};

/** Haridor tomoni uchun qo'shimcha vaznlar (konfigda bo'lmasa). */
const BUYER_WEIGHTS = {
  [EVENT.DEMAND_ABANDONED]: -3,
};

const DAY_MS = 24 * 3600 * 1000;

/**
 * So'nish koeffitsienti.
 *
 *   < 90 kun   -> 1.00  (to'liq)
 *   90-180 kun -> 0.50
 *   > 180 kun  -> 0.25
 *
 * Nega pog'onali, nega uzluksiz eksponenta emas: pog'onali variantni
 * moderator va egasi tushuntirib bera oladi («3 oydan keyin yarmi»),
 * eksponentani esa tushuntirib bo'lmaydi. Aniqlik bu yerda muhim emas.
 */
function decayFactor(eventAtMs, nowMs, decay) {
  const d = decay || {};
  const halfAfter = Number(d.halfAfterDays) || 90;
  const quarterAfter = Number(d.quarterAfterDays) || 180;
  const ageDays = Math.max(0, (nowMs - eventAtMs) / DAY_MS);
  if (ageDays > quarterAfter) return 0.25;
  if (ageDays > halfAfter) return 0.5;
  return 1;
}

/** Voqea vazni (konfigdan, bo'lmasa haridor jadvalidan, bo'lmasa 0). */
function eventWeight(type, config) {
  const w = (config && config.trust && config.trust.events) || {};
  if (Object.prototype.hasOwnProperty.call(w, type)) return Number(w[type]) || 0;
  if (Object.prototype.hasOwnProperty.call(BUYER_WEIGHTS, type)) return BUYER_WEIGHTS[type];
  return 0;
}

/**
 * Trust'ni voqealar jurnalidan hisoblaydi.
 *
 * @param {Array<{type: string, at: *, weight?: number}>} events
 * @param {object} config module_config
 * @param {Date} [now]
 * @returns {{score: number, raw: number, counted: number, ignored: number}}
 */
function computeTrust(events, config, now = new Date()) {
  const t = (config && config.trust) || {};
  const initial = Number.isFinite(t.initial) ? t.initial : 50;
  const min = Number.isFinite(t.min) ? t.min : 0;
  const max = Number.isFinite(t.max) ? t.max : 100;
  const nowMs = now.getTime();

  let delta = 0;
  let counted = 0;
  let ignored = 0;

  for (const e of events || []) {
    const atMs = toMillis(e.at);
    if (!atMs) { ignored += 1; continue; }
    // Kelajakdagi voqea — soat buzilgan yoki ma'lumot noto'g'ri.
    // Hisobga olinmaydi: aks holda kelajak sanasi bilan trust «abadiy
    // yangi» bo'lib qolardi.
    if (atMs > nowMs + DAY_MS) { ignored += 1; continue; }

    const w = Number.isFinite(e.weight) ? e.weight : eventWeight(e.type, config);
    if (w === 0) { ignored += 1; continue; }

    delta += w * decayFactor(atMs, nowMs, t.decay);
    counted += 1;
  }

  const raw = initial + delta;
  return {
    score: Math.round(Math.max(min, Math.min(max, raw))),
    raw: Number(raw.toFixed(2)),
    counted,
    ignored,
  };
}

/** dispatch 1-to'lqinga kiradimi. */
function allowedInFirstWave(trustScore, config) {
  const t = (config && config.trust) || {};
  const threshold = Number.isFinite(t.firstWaveMin) ? t.firstWaveMin : 40;
  return Number(trustScore) >= threshold;
}

/**
 * Matching'dan butunlay chiqariladimi.
 *
 * Konsepsiya: «Juda past bo'lsa, matching'dan vaqtincha chiqariladi va
 * moderatorga xabar ketadi.»
 */
function excludedFromMatching(trustScore, config) {
  const t = (config && config.trust) || {};
  const threshold = Number.isFinite(t.excludeBelow) ? t.excludeBelow : 20;
  return Number(trustScore) < threshold;
}

/**
 * Т-10 — JAVOBGARLIK SHIFTI.
 *
 * Konsepsiyada `declaredValue`ni yuboruvchi o'zi yozadi va kuryer
 * CHEKLANMAGAN pul to'laydi. Bu hujum uchun ochiq: yomon niyatli yuboruvchi
 * 50 mln deb yozib, posilka «yo'qolgan» deb talab qilishi mumkin.
 *
 * Shuning uchun shift kuryerning TASDIQLANGANLIK darajasiga bog'lanadi.
 * Qiymat shiftdan yuqori bo'lsa, bunday kuryer matching'da nomzod bo'lmaydi.
 */
function liabilityCap(provider, config) {
  const caps = (config && config.liabilityCaps) || {};
  const unverified = Number(caps.unverified) || 300000;
  const passportVerified = Number(caps.passportVerified) || 1000000;
  const fullyVerified = Number(caps.fullyVerified) || 3000000;
  const minCompleted = Number(caps.fullyVerifiedMinCompleted) || 20;

  const p = provider || {};
  const trustOk = !excludedFromMatching(p.trustScore, config)
    && Number(p.trustScore) >= ((config.trust && config.trust.firstWaveMin) || 40);

  if (!p.passportVerified || !trustOk) return unverified;
  if (p.selfEmploymentVerified && Number(p.completedCount) >= minCompleted) {
    return fullyVerified;
  }
  return passportVerified;
}

/** Posilka qiymati shu kuryerga ruxsat etilganmi. */
function canCarryDeclaredValue(declaredValue, provider, config) {
  const v = Number(declaredValue) || 0;
  return v <= liabilityCap(provider, config);
}

/** Turli shakllardan millisekund. */
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

module.exports = {
  EVENT,
  BUYER_WEIGHTS,
  decayFactor,
  eventWeight,
  computeTrust,
  allowedInFirstWave,
  excludedFromMatching,
  liabilityCap,
  canCarryDeclaredValue,
  toMillis,
};
