'use strict';

/**
 * 13.1.4 + 13.1.5 — MODUL KONFIGI, FEATURE FLAG VA KILL SWITCH.
 *
 * Konsepsiyada «qiymatlar moduleConfig'da saqlanadi va analitika asosida
 * o'zgartiriladi» deb yozilgan, lekin BIRORTA RAQAM berilmagan — shunday
 * holatda joriy etib bo'lmaydi. Shuning uchun Т-7 va Т-18 dagi barcha
 * boshlang'ich qiymatlar ayni shu faylda, KODDA yashaydi.
 *
 * Firestore (`module_config/{module}_{regionId}`) faqat USTIGA YOZADI (override):
 * admin bir maydonni o'zgartirsa, qolgani koddagi standart qiymatda qoladi.
 * Shunda bo'sh yoki chala konfig hujjati yadroni to'xtatib qo'ymaydi.
 *
 * Kesh: 60 soniya (13.1.4 qabul mezoni). Sovuq start bo'lsa birinchi
 * chaqiruv o'qiydi, keyingilari keshdan oladi.
 *
 * KILL SWITCH (13.1.5) uch pog'onada, eng kuchli birinchi:
 *   module_config/global           -> butun yadro
 *   module_config/{module}_{region}-> bitta modul + hudud
 *   deploy                         -> `firebase deploy --only functions:demand`
 */

const { moduleRegionKey } = require('./ids');

/** Kesh muddati (ms). */
const CACHE_TTL_MS = 60 * 1000;

/**
 * KODDAGI STANDART QIYMATLAR.
 *
 * Har bir raqamning sababi izohda. Shadow mode o'lchovidan keyin
 * Firestore'da ustiga yoziladi — kod o'zgarmaydi.
 */
const DEFAULTS = {
  // ─── Feature flag va kill switch (13.1.5) ───────────────────────────
  /** Modul umuman ishlaydimi. `false` -> talab yaratish ham to'xtaydi. */
  enabled: false,
  /** Matching ishlaydimi. `false` -> talab yaratiladi, nomzod izlanmaydi. */
  matchingEnabled: true,
  /**
   * Push yuboriladimi. SHADOW MODE ayni shu flag:
   * `matchingEnabled: true` + `pushEnabled: false` -> hisob ishlaydi,
   * `demand_matches` yoziladi, lekin hech kimga xabar ketmaydi (13.5.1).
   */
  pushEnabled: false,

  // ─── Rejim ──────────────────────────────────────────────────────────
  /** dispatch | quote | alert | recurring */
  mode: 'quote',

  // ─── Matching (Т-18) ────────────────────────────────────────────────
  /** Mos hisoblanish chegarasi. Bundan past nomzod MOS EMAS. */
  minScore: 0.35,
  /** Bitta talabga maksimal nomzod (Firestore va push narxini chegaralaydi). */
  maxCandidates: 500,
  /** Qidiruv radiusi (km) — quote rejimi uchun. */
  searchRadiusKm: 15,
  /** Yo'l koeffitsienti (geo.js standarti bilan bir xil). */
  roadFactor: 1.35,
  /** Score vaznlari. Yig'indisi 1.0 bo'lishi SHART (validateConfig tekshiradi). */
  weights: {
    categoryMatch: 0.40,
    proximity: 0.40,
    sourceStrength: 0.20,
  },
  /**
   * Tenglashtiruvchi qism (fairness).
   *
   * `band` — faqat SHU oraliqdagi nomzodlar orasida ishlaydi: base score
   * farqi 0.05 dan kam bo'lsa. Shunda 900 metrdagi kuryer 11 km uzoqdagiga
   * «kam ishlagani uchun» hech qachon yutqazmaydi (konsepsiya talabi).
   */
  equalizer: {
    band: 0.05,
    maxShift: 0.05,
    todayOrdersWeight: 0.50,
    trustWeight: 0.30,
    ratingWeight: 0.20,
    dailyOrderTarget: 8,
  },
  /** Cold start: yangi taklifchiga kichik yordam. */
  newProvider: {
    completedThreshold: 5,
    scoreBoost: 0.03,
    maxConcurrent: 2,
  },

  // ─── Trust (Т-18) ───────────────────────────────────────────────────
  trust: {
    initial: 50,
    min: 0,
    max: 100,
    /** dispatch 1-to'lqinga kirish chegarasi. */
    firstWaveMin: 40,
    /** Bundan past -> matching'dan vaqtincha chiqariladi + moderator. */
    excludeBelow: 20,
    /** Voqea vaznlari. */
    events: {
      completed: 2,
      lateCancel: -5,
      noShow: -15,
      confirmedComplaint: -20,
      rating5: 1,
      ratingLow: -3,
    },
    /** So'nish: eski voqea kuchsizlanadi (bir marta xato qilgan abadiy jazolanmasin). */
    decay: {
      halfAfterDays: 90,
      quarterAfterDays: 180,
    },
  },

  // ─── Notification Policy (Т-7) ──────────────────────────────────────
  /**
   * Konsepsiyada «kunlik limit yo'q» deb yozilgan edi. Urganch hajmida bu
   * kunda 20-40 push degani -> taklifchi push'ni o'chiradi yoki ilovani
   * o'chiradi. KO'RINISHGA tegilmaydi (inbox limitsiz), faqat PUSH chegaralanadi.
   */
  push: {
    quote: { perHour: 5, perDay: 20 },
    alert: { perHour: 3, perDay: 10 },
    /** dispatch — bitta kuryer kerak, har soniya muhim. Limit yo'q. */
    dispatch: { perHour: 0, perDay: 0 },
    /** Limitdan oshganlar bitta dayjestga yig'iladi. */
    digest: { enabled: true, everyMinutes: 180, minItems: 2 },
    /** Tinch soatlar — Asia/Tashkent (server UTC'da ishlaydi, Т-6.5). */
    quietHours: { from: 23, to: 7, timezoneOffsetMinutes: 300 },
  },

  // ─── dispatch to'lqinlari (P2) ──────────────────────────────────────
  waves: [
    { etaMaxMinutes: 5, waitSeconds: 20 },
    { etaMaxMinutes: 12, waitSeconds: 20 },
    { etaMaxMinutes: 20, waitSeconds: 30 },
  ],
  minCandidatesPerWave: 3,
  /** Bundan eski GPS'li kuryer birinchi to'lqinga kirmaydi. */
  maxLocationAgeSec: 120,
  onExhausted: 'keepOpen',

  // ─── Lifecycle (Т-19) ───────────────────────────────────────────────
  /** Standart muddat — forma boshqa vaqt bermasa. */
  defaultTtlMinutes: 24 * 60,
  /** Qabul qilingandan keyin ish boshlanmasa, talab qaytib ochiladi. */
  assignmentDeadlineMinutes: { dispatch: 15, quote: 120 },
  /** Bitta taklifchi bitta talabga necha marta taklifini o'zgartira oladi. */
  maxOfferRevisions: 3,

  // ─── Limitlar va suiiste'moldan himoya ──────────────────────────────
  limits: {
    /** Bitta foydalanuvchi kuniga nechta talab yaratadi (soxta talab himoyasi). */
    demandsPerDay: 10,
    /** Bir vaqtda ochiq talab. */
    activeDemands: 5,
    /** Bitta taklifchi kuniga nechta taklif beradi (shablon spam himoyasi). */
    offersPerDay: 50,
    /** `clientRequestId` idempotentlik oynasi (Т-12). */
    idempotencyWindowMinutes: 10,
  },

  // ─── Proyeksiya (Т-20) ──────────────────────────────────────────────
  projection: {
    approxMinMeters: 300,
    approxMaxMeters: 600,
    /** Proyeksiyadagi geohash uzunligi: 5 ~ 4.9 km. To'liq 7-8 BERILMAYDI. */
    geohashPrecision: 5,
  },

  // ─── AVA Logistics (Relay) — LEG sozlamalari ─────────────────────────
  logistics: {
    /** LEG taklif kutish muddati: 3 kun (shaharlararo yo'nalish). */
    legTtlMinutes: 3 * 24 * 60,
    /**
     * Keyingi LEG qachon ochiladi: `in_progress` — oldingi ijrochi
     * posilkani OLGANDA (hujjat 7.3 «completed» degan edi — u DEADLOCK:
     * LEG(n) faqat LEG(n+1) ijrochisi olganda tugaydi, LEG(n+1) esa
     * LEG(n) tugamaguncha ochilmasdi).
     */
    openNextLegOn: 'in_progress',
    /**
     * Ishga tushirish bosqichi (CLAUDE.md 42; lug'at `core/logistics.js` STAGE):
     * `off` — hech kim; `internal` / `pilot` — faqat `testerIds` jo'natadi va
     * LEG oladi; `public` — hamma. Standart — `internal` (yopiq): hujjatda
     * yozilmasa ham xizmat ommaga ochilmaydi.
     */
    stage: 'internal',
    /** Kanonik telefon ID'lari (ids.toCanonicalId) — jo'natuvchi VA ijrochi. */
    testerIds: [],
    /**
     * Topshirish/yetkazish kodini terib topishdan himoya (audit S4/L7): bitta
     * (jo'natma, LEG, ijrochi) uchun shuncha XATO urinishdan keyin ...
     */
    codeMaxFailedAttempts: 5,
    /** ... shuncha daqiqa qulf. Bu NARX EMAS — xavfsizlik sozlamasi. */
    codeLockMinutes: 15,
  },

  // ─── Javobgarlik shifti (Т-10, Қ-2) ─────────────────────────────────
  liabilityCaps: {
    unverified: 300000,
    passportVerified: 1000000,
    fullyVerified: 3000000,
    fullyVerifiedMinCompleted: 20,
  },
};

/** Global kill switch hujjatining standart qiymati. */
const GLOBAL_DEFAULTS = {
  /** `false` -> BUTUN yadro to'xtaydi (eng kuchli kalit). */
  enabled: true,
  matchingEnabled: true,
  pushEnabled: true,
  /** Moderator ko'rishi uchun sabab. */
  reason: '',
};

const GLOBAL_DOC_ID = 'global';
const COLLECTION = 'module_config';

/** @type {Map<string, {at: number, value: object}>} */
const cache = new Map();

/** Oddiy chuqur birlashtirish — massivlar BUTUNLAY almashtiriladi. */
function deepMerge(base, override) {
  if (!override || typeof override !== 'object' || Array.isArray(override)) {
    return override === undefined ? base : override;
  }
  const out = Array.isArray(base) ? [...base] : { ...base };
  for (const [k, v] of Object.entries(override)) {
    if (v === undefined || v === null) continue;
    if (
      typeof v === 'object' && !Array.isArray(v)
      && typeof out[k] === 'object' && out[k] !== null && !Array.isArray(out[k])
    ) {
      out[k] = deepMerge(out[k], v);
    } else {
      out[k] = v;
    }
  }
  return out;
}

/**
 * Konfig sog'ligini tekshiradi.
 *
 * Nega kerak: admin `weights`ni qo'lda tahrirlab yig'indisini 1.0 dan
 * chiqarib yuborsa, score jimgina buziladi va buni hech kim sezmaydi.
 * Shuning uchun xato ro'yxati qaytariladi va logga yoziladi.
 */
function validateConfig(cfg) {
  const errors = [];
  const w = cfg.weights || {};
  const sum = (w.categoryMatch || 0) + (w.proximity || 0) + (w.sourceStrength || 0);
  if (Math.abs(sum - 1) > 0.001) {
    errors.push(`weights yig'indisi 1.0 bo'lishi kerak, hozir ${sum.toFixed(3)}`);
  }
  if (cfg.minScore < 0 || cfg.minScore > 1) {
    errors.push(`minScore 0..1 oralig'ida bo'lishi kerak, hozir ${cfg.minScore}`);
  }
  const t = cfg.trust || {};
  if (t.excludeBelow >= t.firstWaveMin) {
    errors.push(
      `trust.excludeBelow (${t.excludeBelow}) trust.firstWaveMin (${t.firstWaveMin}) dan `
      + 'kichik bo\'lishi kerak',
    );
  }
  if (!Array.isArray(cfg.waves) || cfg.waves.length === 0) {
    errors.push('waves bo\'sh bo\'lishi mumkin emas');
  } else {
    for (let i = 1; i < cfg.waves.length; i += 1) {
      if (cfg.waves[i].etaMaxMinutes <= cfg.waves[i - 1].etaMaxMinutes) {
        errors.push(`waves[${i}].etaMaxMinutes oldingisidan katta bo'lishi kerak`);
      }
    }
  }
  const q = (cfg.push || {}).quietHours || {};
  if (q.from === q.to) {
    errors.push('push.quietHours.from va .to teng — tinch soatlar 24/7 bo\'lib qoladi');
  }
  const eq = cfg.equalizer || {};
  if (eq.maxShift > 0.2) {
    errors.push(
      `equalizer.maxShift juda katta (${eq.maxShift}) — fairness yaqinlikdan ustun bo'lib qoladi`,
    );
  }
  return errors;
}

/**
 * Modul konfigini oladi (standart + Firestore ustiga yozilgani).
 *
 * @param {import('firebase-admin').firestore.Firestore} db
 * @param {string} module
 * @param {string} regionId
 * @param {{skipCache?: boolean}} [opts]
 */
async function getModuleConfig(db, module, regionId, opts = {}) {
  const key = moduleRegionKey(module, regionId);
  const now = Date.now();
  if (!opts.skipCache) {
    const hit = cache.get(key);
    if (hit && now - hit.at < CACHE_TTL_MS) return hit.value;
  }

  let override = {};
  try {
    const snap = await db.collection(COLLECTION).doc(key).get();
    if (snap.exists) override = snap.data() || {};
  } catch (e) {
    // Konfig o'qilmasa standart qiymatlar bilan davom etamiz, lekin
    // `pushEnabled` ni MAJBURAN o'chiramiz: noma'lum holatda push yubormaslik
    // yuborishdan xavfsizroq.
    console.error(`module_config o'qilmadi (${key}): ${e.message}`);
    const safe = deepMerge(DEFAULTS, { pushEnabled: false, module, regionId });
    cache.set(key, { at: now, value: safe });
    return safe;
  }

  const merged = deepMerge(DEFAULTS, override);
  merged.module = module;
  merged.regionId = regionId;
  merged.configKey = key;

  const errors = validateConfig(merged);
  if (errors.length) {
    console.error(`module_config/${key} nosog'lom: ${errors.join('; ')}`);
    merged.configErrors = errors;
  }

  cache.set(key, { at: now, value: merged });
  return merged;
}

/** Global kill switch. */
async function getGlobalConfig(db, opts = {}) {
  const now = Date.now();
  if (!opts.skipCache) {
    const hit = cache.get(GLOBAL_DOC_ID);
    if (hit && now - hit.at < CACHE_TTL_MS) return hit.value;
  }
  let override = {};
  try {
    const snap = await db.collection(COLLECTION).doc(GLOBAL_DOC_ID).get();
    if (snap.exists) override = snap.data() || {};
  } catch (e) {
    console.error(`module_config/global o'qilmadi: ${e.message}`);
    // Global hujjat o'qilmasa yadro ISHLASHDA DAVOM ETADI (aks holda bitta
    // o'qish xatosi butun xizmatni o'ldiradi), lekin push o'chadi.
    const safe = { ...GLOBAL_DEFAULTS, pushEnabled: false };
    cache.set(GLOBAL_DOC_ID, { at: now, value: safe });
    return safe;
  }
  const merged = { ...GLOBAL_DEFAULTS, ...override };
  cache.set(GLOBAL_DOC_ID, { at: now, value: merged });
  return merged;
}

/**
 * Yakuniy flaglar: global VA modul — ikkisi ham ruxsat bersa ishlaydi.
 *
 * `AND` mantiqi ataylab: global kalit har doim kuchliroq, modul konfigidagi
 * `enabled: true` uni bekor qila olmaydi.
 */
async function resolveFlags(db, module, regionId) {
  const [g, m] = await Promise.all([
    getGlobalConfig(db),
    getModuleConfig(db, module, regionId),
  ]);
  return {
    enabled: g.enabled !== false && m.enabled === true,
    matchingEnabled: g.matchingEnabled !== false && m.matchingEnabled !== false,
    pushEnabled: g.pushEnabled !== false && m.pushEnabled === true,
    killReason: g.enabled === false ? (g.reason || 'global kill switch') : '',
    config: m,
  };
}

/** Testlar va `skipCache` uchun. */
function clearCache() {
  cache.clear();
}

module.exports = {
  COLLECTION,
  GLOBAL_DOC_ID,
  CACHE_TTL_MS,
  DEFAULTS,
  GLOBAL_DEFAULTS,
  deepMerge,
  validateConfig,
  getModuleConfig,
  getGlobalConfig,
  resolveFlags,
  clearCache,
};
