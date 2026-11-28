/**
 * «Туғилган кунингизни киритинг» — ЭСЛАТМА ПУШ (эга 2026-11-28, 9-банд).
 *
 * Эга қарори (2026-11-28, сўзма-сўз): «Матн маъқул, 4 кун давомида кунига бир мартада хабар берилсин,
 * кейин ҳафтадан сўнг ҳар якшанба!»; «вақтининг аҳамияти йўқ» (соат созламаси йўқ); «соат 8:00 - 20:00 гача бўлсин»
 * (ойна 08:00–19:59 Тошкент, 20:00 ва ундан кейин — йўқ).
 *   1-фаза (daily):  биринчи `dailyCount` (сукут 4) Тошкент кунида кунига БИР марта.
 *   2-фаза (weekly): охирги кунлик юборишдан 7 кун танаффус, кейин ҲАР ЯКШАНБА бир марта, ЧЕКСИЗ —
 *                    сана киритилгунча / рад этилгунча (holidayRemindersOptIn === false) / ўчирилгунча / токен йўқолгунча.
 *
 * Мақсад: туғилган санаси ЙЎҚ фойдаланувчига эслатма — шунда holiday.js ўз туғилган куни эслатмалари
 * (runSelfBirthdayReminders, users.birthDate) ишлай бошлайди.
 *
 * МАВЖУД занжир устида (параллел тизим ЙЎҚ, 3/4/43-банд):
 *   - манба — `users/{uid}.birthDate` (сатр; клиент `setBirthDateIfEmpty`, бош саҳифа карточкаси
 *     `birthDatePromptVisibleFor` билан АЙНАН бир хил қоида: бўш/йўқ = киритилмаган);
 *   - хабар — `notifyUserInApp` (admin_news + FCM); тил — notif_i18n.normalizeLang;
 *   - рад этиш — мавжуд `users.holidayRemindersOptIn === false` (байрам эслатмалари учун) — юборилмайди;
 *   - босқич — off · internal · pilot · public (supermarket.STAGES; оила/рағбат дастурлари каби
 *     `internalPhones` + `pilotDistrictIds`).
 *
 * Коллекциялар (қоида йўқ = клиентга ёпиқ, фақат CF):
 *   settings/birthday_prompt          — {stage, internalPhones, pilotDistrictIds, dailyCount, weeklySunday, version, updatedAt, updatedBy}
 *                                        ҳужжат йўқ = OFF. Ёзиш ФАҚАТ adminSetBirthdayPromptSettings (admin_audit).
 *   birthday_prompt_state/{998…}      — {phase, dailySends, weeklySends, lastDay, lastWeek, dailyDoneDay, firstSentAt, lastAt}
 *                                        (идемпотентлик: кунда бир марта / ISO ҳафтада бир марта). Эски шакл {sends, lastWeek,
 *                                        firstAt, lastAt} ҳам ўқилади (normalizeState).
 *   birthday_prompt_runs/{day}_{stage} — кунлик тарқатиш курсори, lease, статистика.
 *
 * Пул йўқ. Ҳеч нарса сотилмайди/ечилмайди.
 */
'use strict';

const sm = require('./supermarket');
const h = require('./holiday');
const { normalizeLang } = require('./notif_i18n');

const MODULE = 'birthday_prompt';
const SETTINGS_DOC = Object.freeze(['settings', 'birthday_prompt']);
const STATE = 'birthday_prompt_state';
const RUNS = 'birthday_prompt_runs';
const ADMIN_AUDIT = 'admin_audit';
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);
const STAGES = sm.STAGES; // off · internal · pilot · public
const SOURCE = 'birthday_prompt'; // admin_news.source = FCM data.type (клиент йўналиши)
const SCREEN = 'user_info'; // клиент: UserInfoScreen (туғилган сана шу ерда киритилади)
const TZ_OFFSET_MS = 5 * 3600000;
const PHONE_RE = /^998\d{9}$/;
const DISTRICT_RE = /^[a-z0-9_-]{2,40}$/;
const SETTINGS_KEYS = Object.freeze(['stage', 'internalPhones', 'pilotDistrictIds', 'dailyCount', 'weeklySunday']);

/** Эга 2026-11-28: «4 кун давомида кунига бир мартада». Админ 1–14 оралиғида ўзгартиради. */
const DEFAULT_DAILY_COUNT = 4;
/** Эга 2026-11-28: «кейин ҳафтадан сўнг ҳар якшанба». Админ ўчириши мумкин (сукут — ёқиқ). */
const DEFAULT_WEEKLY_SUNDAY = true;
/** «ҳафтадан сўнг» — охирги кунлик юборишдан 7 кун (шу куни ҳам мумкин: 4-юбориш якшанба бўлса — кейинги якшанба). */
const PAUSE_DAYS = 7;
const LIMITS = Object.freeze({
  dailyCountMin: 1, dailyCountMax: 14, phones: 50, districts: 30, // Firestore `in` — 30 тагача
  page: 300, concurrency: 20, runBudgetMs: 420000, leaseMs: 570000, // lease > timeout 540 s, < cron оралиғи 600 s
  reasonMax: 300,
});
/** Юбориш ойнаси: ҲАР КУНИ 08:00–19:59 Тошкент (эга 2026-11-28: «соат 8:00 - 20:00 гача бўлсин»; соат созламаси йўқ). */
const WINDOW = Object.freeze({ fromHour: 8, toHour: 20 });
const SCHEDULE = '*/10 8-19 * * *';
const PHASES = Object.freeze(['daily', 'weekly']);

// ── Хабар матни (3 тил; uz_Latn — янги ҳарфлар Ö Ğ Ş Ç). Эга 2026-11-28: «Матн маъқул» — ЎЗГАРТИРИЛМАСИН. ──
const PROMPT_TEXT = Object.freeze({
  uz_Cyrl: {
    title: 'Туғилган кунингизни киритинг',
    body: 'Туғилган кун саватчаси, совғалар ва байрам эслатмалари очилади. Бир дақиқада киритинг.',
  },
  uz_Latn: {
    title: 'Tuğilgan kuningizni kiriting',
    body: 'Tuğilgan kun savatçasi, sovğalar va bayram eslatmalari oçiladi. Bir daqiqada kiriting.',
  },
  ru: {
    title: 'Укажите дату рождения',
    body: 'Откроются корзина ко дню рождения, подарки и праздничные напоминания. Это займёт минуту.',
  },
});

const MSG = Object.freeze({
  UNAUTHENTICATED: ['Илтимос, тизимга киринг.', 'Iltimos, tizimga kiring.', 'Пожалуйста, войдите в систему.'],
  PERMISSION_DENIED: ['Бу амал учун рухсат йўқ.', 'Bu amal uçun ruxsat yöq.', 'Нет доступа к этому действию.'],
  SETTINGS_INVALID: ['Созлама нотўғри. Қайта текширинг.', "Sozlama notöğri. Qayta tekşiring.", 'Неверные настройки. Проверьте ещё раз.'],
  VERSION_CONFLICT: ['Созламани бошқа админ ўзгартирди. Саҳифани янгиланг.', "Sozlamani boşqa admin özgartirdi. Sahifani yangilang.", 'Настройки изменил другой админ. Обновите страницу.'],
  INTERNAL: ['Амални бажариб бўлмади. Қайта уриниб кўринг.', "Amalni bajarib bölmadi. Qayta urinib köring.", 'Не удалось выполнить. Попробуйте ещё раз.'],
});
const messagesOf = (code) => { const m = MSG[code] || MSG.INTERNAL; return { uz_Cyrl: m[0], uz_Latn: m[1], ru: m[2] }; };

const isObj = sm.isPlainObject;
const pad = (n) => String(n).padStart(2, '0');

// ══════════════════════ ТОЗА ФУНКЦИЯЛАР (тестлар) ══════════════════════

/** Тошкент санаси 'YYYY-MM-DD' → ISO ҳафта 'YYYY-Www' (душанба бошланади; ҳафта йили — пайшанба йили). */
function isoWeekKey(dateKey) {
  if (!h.validDateKey(dateKey)) return null;
  const [y, m, d] = dateKey.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d));
  const dow = t.getUTCDay() || 7; // душанба=1 … якшанба=7
  t.setUTCDate(t.getUTCDate() + 4 - dow); // шу ҳафтанинг пайшанбаси
  const wy = t.getUTCFullYear();
  const week = Math.ceil(((t.getTime() - Date.UTC(wy, 0, 1)) / 86400000 + 1) / 7);
  return `${wy}-W${pad(week)}`;
}
const weekKeyOfMs = (ms) => isoWeekKey(h.dateKeyOf(ms));
const dayKeyOfMs = (ms) => h.dateKeyOf(ms);

/** Тошкент санаси якшанбами. */
function isSundayKey(dateKey) {
  if (!h.validDateKey(dateKey)) return false;
  const [y, m, d] = dateKey.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay() === 0;
}

/** Юбориш ойнасидами (Тошкент): ҳар куни 08:00–19:59. Кечикиб келган Scheduler қайта уриниши кечаси юбормасин. */
function inSendWindow(ms) {
  const hr = new Date(ms + TZ_OFFSET_MS).getUTCHours();
  return hr >= WINDOW.fromHour && hr < WINDOW.toHour;
}

/** Туғилган сана киритилганми — клиент `birthDatePromptVisibleFor` қоидаси: null/йўқ/бўш сатр = киритилмаган. */
function hasBirthDate(v) {
  if (v == null) return false;
  if (typeof v === 'string') return v.trim() !== '';
  return true; // Timestamp (эски) ёки бошқа қиймат — киритилган (setBirthDateIfEmpty уни қулфлайди)
}

/**
 * Фойдаланувчи ҳужжати бўйича ўтказиб юбориш сабаби (null — номзод).
 * Фақат 12 хонали 998… ҳужжат: notifyUserInApp push'ни ФАҚАТ users/{998…}.fcmToken га юборади.
 */
function skipReasonOf(docId, u) {
  const x = u || {};
  if (!PHONE_RE.test(String(docId || ''))) return 'NOT_CANONICAL';
  if (hasBirthDate(x.birthDate)) return 'HAS_BIRTHDATE';
  if (x.deleted === true || x.deletion != null) return 'DELETION';
  if (x.holidayRemindersOptIn === false) return 'OPTED_OUT';
  if (typeof x.fcmToken !== 'string' || !x.fcmToken.trim()) return 'NO_TOKEN';
  return null;
}

const nonNegInt = (v) => (Number.isInteger(v) && v > 0 ? v : 0);
const msOf = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : null);

/**
 * Ҳолат ҳужжати → ягона шакл (26-банд). Эски шакл {sends, lastWeek, firstAt, lastAt} (ҳафталик версия, deploy
 * қилинмаган): `sends` — кунлик юборишлар сифатида ҳисобланади, `lastDay` — `lastAt`дан (бир кунда иккинчи марта йўқ),
 * `lastWeek` сақланади (шу ҳафтада иккинчи якшанба юбориши йўқ).
 */
function normalizeState(raw) {
  const s = isObj(raw) ? raw : {};
  const legacy = !PHASES.includes(s.phase) && Number.isInteger(s.sends);
  const lastAtMs = msOf(s.lastAt);
  const lastDay = h.validDateKey(s.lastDay) ? s.lastDay : (lastAtMs != null ? h.dateKeyOf(lastAtMs) : null);
  return {
    legacy,
    phase: PHASES.includes(s.phase) ? s.phase : 'daily',
    dailySends: legacy ? nonNegInt(s.sends) : nonNegInt(s.dailySends),
    weeklySends: nonNegInt(s.weeklySends),
    lastDay,
    lastWeek: typeof s.lastWeek === 'string' && s.lastWeek ? s.lastWeek : null,
    dailyDoneDay: h.validDateKey(s.dailyDoneDay) ? s.dailyDoneDay : null,
  };
}

/**
 * Бугун (Тошкент `day`, ISO ҳафта `week`) юборса бўладими. cfg — {dailyCount, weeklySunday}.
 * ok — {ok:true, kind:'daily'|'weekly', patch} (patch — ҳолатга ёзиладиган майдонлар); акс ҳолда {ok:false, reason}.
 *   ALREADY_TODAY · ALREADY_THIS_WEEK · PAUSE (7 кун ичида) · NOT_SUNDAY · WEEKLY_OFF.
 * `weekly` фазаси қайтмас: админ dailyCount ни оширса ҳам кунлик фазага қайтмайди.
 */
function claimDecision(state, day, week, cfg) {
  const c = isObj(cfg) ? cfg : {};
  const dailyCount = Number.isInteger(c.dailyCount) && c.dailyCount >= 1 ? c.dailyCount : DEFAULT_DAILY_COUNT;
  const weeklySunday = c.weeklySunday !== false;
  const s = normalizeState(state);
  if (s.lastDay === day) return { ok: false, reason: 'ALREADY_TODAY' };
  if (s.phase !== 'weekly' && s.dailySends < dailyCount) {
    const n = s.dailySends + 1;
    const done = n >= dailyCount;
    return {
      ok: true, kind: 'daily', send: n,
      patch: { phase: done ? 'weekly' : 'daily', dailySends: n, weeklySends: s.weeklySends, lastDay: day, ...(done ? { dailyDoneDay: day } : {}) },
    };
  }
  if (!weeklySunday) return { ok: false, reason: 'WEEKLY_OFF' };
  if (!isSundayKey(day)) return { ok: false, reason: 'NOT_SUNDAY' };
  if (s.lastWeek === week) return { ok: false, reason: 'ALREADY_THIS_WEEK' };
  const anchor = s.dailyDoneDay || s.lastDay; // 4-кунлик юбориш куни (эски/камайтирилган ҳолатда — охирги юбориш)
  if (anchor && h.daysBetween(anchor, day) < PAUSE_DAYS) return { ok: false, reason: 'PAUSE' };
  const n = s.weeklySends + 1;
  return {
    ok: true, kind: 'weekly', send: n,
    patch: { phase: 'weekly', dailySends: s.dailySends, weeklySends: n, lastDay: day, lastWeek: week, dailyDoneDay: anchor || null },
  };
}

/** Админ юборган созлама (фақат SETTINGS_KEYS). */
function validateSettings(s) {
  const errors = [];
  if (!isObj(s)) return { ok: false, errors: ['SETTINGS_NOT_OBJECT'] };
  for (const k of Object.keys(s)) if (!SETTINGS_KEYS.includes(k)) errors.push(`UNKNOWN_KEY ${k}`);
  if (!STAGES.includes(s.stage)) errors.push('STAGE_INVALID stage');
  if (!Array.isArray(s.internalPhones) || s.internalPhones.length > LIMITS.phones || !s.internalPhones.every((x) => typeof x === 'string' && PHONE_RE.test(x))
    || new Set(s.internalPhones).size !== s.internalPhones.length) errors.push('INTERNAL_PHONES_INVALID internalPhones');
  if (!Array.isArray(s.pilotDistrictIds) || s.pilotDistrictIds.length > LIMITS.districts || !s.pilotDistrictIds.every((x) => typeof x === 'string' && DISTRICT_RE.test(x))
    || new Set(s.pilotDistrictIds).size !== s.pilotDistrictIds.length) errors.push('PILOT_DISTRICTS_INVALID pilotDistrictIds');
  if (!Number.isInteger(s.dailyCount) || s.dailyCount < LIMITS.dailyCountMin || s.dailyCount > LIMITS.dailyCountMax) errors.push('DAILY_COUNT_INVALID dailyCount');
  if (typeof s.weeklySunday !== 'boolean') errors.push('WEEKLY_SUNDAY_INVALID weeklySunday');
  if (s.stage === 'pilot' && Array.isArray(s.pilotDistrictIds) && s.pilotDistrictIds.length === 0
    && Array.isArray(s.internalPhones) && s.internalPhones.length === 0) errors.push('PILOT_EMPTY pilotDistrictIds');
  return { ok: errors.length === 0, errors };
}

/** Сақланган ҳужжат → самарали созлама (йўқ/бузуқ = OFF; эски ҳужжатда йўқ майдон — сукут, 26-банд; эски maxSends эътиборсиз). */
function normalizeSettings(raw) {
  const r = isObj(raw) ? raw : {};
  const list = (v, re, max) => (Array.isArray(v) ? v.filter((x) => typeof x === 'string' && re.test(x)).slice(0, max) : []);
  return {
    stage: STAGES.includes(r.stage) ? r.stage : 'off',
    internalPhones: list(r.internalPhones, PHONE_RE, LIMITS.phones),
    pilotDistrictIds: list(r.pilotDistrictIds, DISTRICT_RE, LIMITS.districts),
    dailyCount: Number.isInteger(r.dailyCount) && r.dailyCount >= LIMITS.dailyCountMin && r.dailyCount <= LIMITS.dailyCountMax ? r.dailyCount : DEFAULT_DAILY_COUNT,
    weeklySunday: typeof r.weeklySunday === 'boolean' ? r.weeklySunday : DEFAULT_WEEKLY_SUNDAY,
    version: Number.isInteger(r.version) ? r.version : 0,
  };
}

/** Тил бўйича матн (номаълум тил — uz_Cyrl, notif_i18n қоидаси). */
const promptTextFor = (lang) => PROMPT_TEXT[normalizeLang(lang)] || PROMPT_TEXT.uz_Cyrl;

/** Чекланган параллеллик (N+1 эмас: саҳифа бир сўровда, юбориш — 20 тадан параллел). */
async function mapPool(items, n, fn) {
  let i = 0;
  const workers = Array.from({ length: Math.min(n, items.length) }, async () => {
    while (i < items.length) { const k = i; i += 1; await fn(items[k], k); }
  });
  await Promise.all(workers);
}

// ══════════════════════ CLOUD FUNCTIONS ══════════════════════

function attachBirthdayPrompt(exportsObj, deps) {
  const { functions, db, admin, requireCallerRoles, notifyUserInApp } = deps;
  const HttpsError = functions.https.HttpsError;
  const FV = admin.firestore.FieldValue;
  const FieldPath = admin.firestore.FieldPath;
  const ts = () => FV.serverTimestamp();
  const now = () => (deps.nowMs ? deps.nowMs() : Date.now());
  const fail = (status, code, extra = {}) => new HttpsError(status, messagesOf(code).uz_Cyrl, { code, messages: messagesOf(code), ...extra });
  const log = (o) => console.log(JSON.stringify({ module: MODULE, ...o }));
  const tail = (p) => String(p || '').slice(-4);
  const settingsRef = () => db.collection(SETTINGS_DOC[0]).doc(SETTINGS_DOC[1]);
  const stateRef = (uid) => db.collection(STATE).doc(uid);
  const PROJECTION = ['birthDate', 'fcmToken', 'appLang', 'holidayRemindersOptIn', 'deleted', 'deletion'];
  const bump = (stat, k) => { stat[k] = (stat[k] || 0) + 1; };

  const requireAdmin = async (context) => {
    try {
      return await requireCallerRoles(context, ADMIN_ROLES, 'Admin role required');
    } catch (e) {
      if (e instanceof HttpsError) throw fail(e.code, e.code === 'unauthenticated' ? 'UNAUTHENTICATED' : 'PERMISSION_DENIED');
      throw e;
    }
  };

  /**
   * Битта номзод: транзакцияда «бугун — бир марта / шу ҳафта — бир марта» белгиси олинади (claimDecision ҚАЙТА),
   * кейин хабар. Энг кўпи бир марта (retry/параллел чақирув иккинчи марта юбормайди). Хабар хатоси — бугун ўтказилади (log).
   */
  async function promptOne(uid, u, ctx, stat) {
    const ref = stateRef(uid);
    const claim = await db.runTransaction(async (t) => {
      const s = await t.get(ref);
      const raw = s.exists ? (s.data() || {}) : null;
      const dec = claimDecision(raw, ctx.day, ctx.week, ctx.cfg);
      if (!dec.ok) return dec;
      const first = raw && (raw.firstSentAt || raw.firstAt);
      t.set(ref, { ...dec.patch, lastAt: ts(), firstSentAt: first || ts() }, { merge: true });
      return dec;
    });
    if (!claim.ok) { bump(stat, claim.reason); return; }
    const m = promptTextFor(u.appLang);
    try {
      await notifyUserInApp({
        userId: uid, title: m.title, body: m.body, category: 'info', source: SOURCE, dataType: SOURCE, screen: SCREEN,
        extraNews: { promptDay: ctx.day, promptPhase: claim.kind, promptSend: claim.send },
        extraData: { promptDay: ctx.day, promptPhase: claim.kind },
      });
      stat.sent += 1;
      bump(stat, claim.kind === 'daily' ? 'sentDaily' : 'sentWeekly');
    } catch (e) {
      bump(stat, 'NOTIFY_FAILED');
      log({ action: 'birthdayPromptSend', result: 'error', errorCode: 'NOTIFY_FAILED', userId: tail(uid), day: ctx.day, phase: claim.kind });
    }
  }

  /**
   * Саҳифа: (1) users майдонлари бўйича сараланади; (2) номзодлар ҳолати БИТТА getAll билан ўқилади ва
   * claimDecision олдиндан текширилади (2-фазадаги кўпчилик якшанбадан ташқари шу ерда тўхтайди — транзакция йўқ);
   * (3) фақат ўтганлар учун транзакция (қайта текширув — ягона ғолиб, 22-банд).
   */
  async function processDocs(docs, ctx, stat) {
    const candidates = [];
    for (const d of docs) {
      stat.scanned += 1;
      const reason = skipReasonOf(d.id, d.data());
      if (reason) bump(stat, reason); else candidates.push(d);
    }
    if (!candidates.length) return;
    const states = await db.getAll(...candidates.map((d) => stateRef(d.id)));
    const due = [];
    candidates.forEach((d, i) => {
      const dec = claimDecision(states[i].exists ? states[i].data() : null, ctx.day, ctx.week, ctx.cfg);
      if (dec.ok) due.push(d); else bump(stat, dec.reason);
    });
    await mapPool(due, LIMITS.concurrency, (d) => promptOne(d.id, d.data() || {}, ctx, stat));
  }

  async function processPhones(phones, ctx, stat) {
    const snaps = phones.length ? await db.getAll(...phones.map((p) => db.collection('users').doc(p)), { fieldMask: PROJECTION }) : [];
    const docs = snaps.filter((s) => s.exists);
    stat.MISSING_USER = (stat.MISSING_USER || 0) + (snaps.length - docs.length);
    await processDocs(docs, ctx, stat);
  }

  /**
   * Бир чақирув: lease → (тестерлар) → курсор бўйича саҳифалар (вақт бюджети тугагунча) → курсор сақланади.
   * internal — фақат internalPhones; pilot — internalPhones + pilotDistrictIds туманлари (`districtId in`);
   * public — бутун users (ҳужжат ID бўйича курсор). Кун/босқич учун битта run ҳужжати.
   */
  async function runBirthdayPrompt(opts = {}) {
    const started = Date.now();
    const nowMs = now();
    const budgetMs = Number.isInteger(opts.budgetMs) ? opts.budgetMs : LIMITS.runBudgetMs;
    const pageSize = Number.isInteger(opts.pageSize) ? opts.pageSize : LIMITS.page;
    if (!opts.ignoreWindow && !inSendWindow(nowMs)) { log({ action: 'birthdayPrompt', result: 'skip', reason: 'OUT_OF_WINDOW' }); return { result: 'skip', reason: 'OUT_OF_WINDOW' }; }
    const cfgSnap = await settingsRef().get();
    const cfg = normalizeSettings(cfgSnap.exists ? cfgSnap.data() : null);
    if (cfg.stage === 'off') { log({ action: 'birthdayPrompt', result: 'skip', reason: 'STAGE_OFF' }); return { result: 'skip', reason: 'STAGE_OFF' }; }
    const day = dayKeyOfMs(nowMs);
    const week = weekKeyOfMs(nowMs);
    const ctx = { day, week, cfg };
    const runRef = db.collection(RUNS).doc(`${day}_${cfg.stage}`);
    const lease = await db.runTransaction(async (t) => {
      const s = await t.get(runRef);
      const r = s.exists ? (s.data() || {}) : {};
      if (r.done === true) return { ok: false, reason: 'DONE' };
      const leaseMs = msOf(r.leaseUntil) || 0;
      if (leaseMs > nowMs) return { ok: false, reason: 'LEASED' };
      t.set(runRef, {
        day, week, stage: cfg.stage, leaseUntil: admin.firestore.Timestamp.fromMillis(nowMs + LIMITS.leaseMs), updatedAt: ts(),
        ...(s.exists ? {} : { startedAt: ts(), done: false, testersDone: false, cursor: null }),
      }, { merge: true });
      return { ok: true, run: r };
    });
    if (!lease.ok) { log({ action: 'birthdayPrompt', result: 'skip', reason: lease.reason, day, stage: cfg.stage }); return { result: 'skip', reason: lease.reason }; }
    const stat = { scanned: 0, sent: 0 };
    let cursor = lease.run.cursor || null;
    let done = false;
    let errorCode = null;
    try {
      if (cfg.stage !== 'public' && lease.run.testersDone !== true) {
        await processPhones(cfg.internalPhones, ctx, stat);
        await runRef.set({ testersDone: true, updatedAt: ts() }, { merge: true });
      }
      if (cfg.stage === 'internal' || (cfg.stage === 'pilot' && cfg.pilotDistrictIds.length === 0)) {
        done = true;
      } else {
        while (Date.now() - started < budgetMs) {
          let q = db.collection('users');
          if (cfg.stage === 'pilot') q = q.where('districtId', 'in', cfg.pilotDistrictIds);
          q = q.orderBy(FieldPath.documentId()).select(...PROJECTION).limit(pageSize);
          if (cursor) q = q.startAfter(cursor);
          const snap = await q.get();
          if (snap.empty) { done = true; break; }
          // Пилотда тестерлар аллақачон ўтди — такрор ҳолатда ҳолат ҳужжати иккинчи юборишни барибир тўсади.
          await processDocs(snap.docs, ctx, stat);
          cursor = snap.docs[snap.docs.length - 1].id;
          await runRef.set({ cursor, updatedAt: ts() }, { merge: true }); // саҳифадан КЕЙИН: узилса — саҳифа қайта, юбориш бир марта
          if (snap.size < pageSize) { done = true; break; }
        }
      }
    } catch (e) {
      errorCode = 'RUN_FAILED';
      log({ action: 'birthdayPrompt', result: 'error', errorCode, day, stage: cfg.stage, message: String((e && e.message) || e).slice(0, 200) });
    }
    const inc = {};
    for (const [k, v] of Object.entries(stat)) if (v) inc[`stats.${k}`] = FV.increment(v);
    await runRef.update({ ...inc, ...(done ? { done: true, doneAt: ts() } : {}), leaseUntil: FV.delete(), updatedAt: ts() });
    const out = { result: errorCode ? 'error' : 'ok', day, week, stage: cfg.stage, done, ...stat, ...(errorCode ? { errorCode } : {}), duration: Date.now() - started };
    log({ action: 'birthdayPrompt', ...out });
    return out;
  }

  // Ҳар куни 08:00 дан 19:50 гача (Тошкент) ҳар 10 дақиқада давом — курсор тугаса `done`, қолганлари бўш ишлайди.
  // Ном: аввал birthdayPromptWeekly (deploy қилинмаган, 2026-11-28) → birthdayPromptDaily.
  exportsObj.birthdayPromptDaily = functions
    .runWith({ timeoutSeconds: 540, memory: '512MB' })
    .pubsub.schedule(SCHEDULE)
    .timeZone('Asia/Tashkent')
    .onRun(() => runBirthdayPrompt());

  /** Админ: жорий созлама + охирги тарқатишлар (статистика). */
  exportsObj.adminGetBirthdayPromptSettings = functions.https.onCall(async (data, context) => {
    await requireAdmin(context);
    const [s, runs] = await Promise.all([settingsRef().get(), db.collection(RUNS).orderBy('startedAt', 'desc').limit(8).get()]);
    return {
      ok: true,
      settings: normalizeSettings(s.exists ? s.data() : null),
      defaults: {
        dailyCount: DEFAULT_DAILY_COUNT, weeklySunday: DEFAULT_WEEKLY_SUNDAY, pauseDays: PAUSE_DAYS,
        dailyCountMin: LIMITS.dailyCountMin, dailyCountMax: LIMITS.dailyCountMax, schedule: SCHEDULE, timeZone: 'Asia/Tashkent',
      },
      runs: runs.docs.map((d) => {
        const r = d.data() || {};
        return { id: d.id, day: r.day || '', week: r.week || '', stage: r.stage || '', done: r.done === true, stats: r.stats || {} };
      }),
    };
  });

  /** Админ: созлама (ЯГОНА ёзиш йўли), версия текшируви, admin_audit (41-банд). */
  exportsObj.adminSetBirthdayPromptSettings = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const s = sm.trimDeep(data && data.settings);
    const v = validateSettings(s);
    if (!v.ok) throw fail('invalid-argument', 'SETTINGS_INVALID', { errors: v.errors.slice(0, 20) });
    const expected = data && Number.isInteger(data.expectedVersion) ? data.expectedVersion : null;
    const reason = typeof (data && data.reason) === 'string' ? data.reason.trim().slice(0, LIMITS.reasonMax) : '';
    const pick = (o) => (o ? Object.fromEntries(SETTINGS_KEYS.map((k) => [k, o[k] === undefined ? null : o[k]])) : null);
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(settingsRef());
      const cur = snap.exists ? (snap.data() || {}) : null;
      const curVersion = cur && Number.isInteger(cur.version) ? cur.version : 0;
      if (expected != null && expected !== curVersion) throw fail('failed-precondition', 'VERSION_CONFLICT', { version: curVersion });
      if (cur && sm.stableStringify(pick(cur)) === sm.stableStringify(pick(s))) return { changed: false, version: curVersion };
      const version = curVersion + 1;
      t.set(settingsRef(), { ...pick(s), version, updatedAt: ts(), updatedBy: actor, ...(cur ? { createdAt: cur.createdAt || ts() } : { createdAt: ts() }) });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'birthday_prompt_settings', actor, target: `${SETTINGS_DOC.join('/')} v${version}`, before: pick(cur), after: pick(s), reason, at: ts(),
      });
      return { changed: true, version };
    });
    log({ action: 'adminSetBirthdayPromptSettings', result: 'ok', userId: tail(actor), stage: s.stage, ...out });
    return { ok: true, ...out };
  });

  return { runBirthdayPrompt };
}

module.exports = {
  attachBirthdayPrompt,
  // тоза (тестлар)
  isoWeekKey, weekKeyOfMs, dayKeyOfMs, isSundayKey, inSendWindow, hasBirthDate, skipReasonOf, normalizeState, claimDecision,
  validateSettings, normalizeSettings, promptTextFor, mapPool, messagesOf,
  PROMPT_TEXT, DEFAULT_DAILY_COUNT, DEFAULT_WEEKLY_SUNDAY, PAUSE_DAYS, LIMITS, WINDOW, SCHEDULE, SETTINGS_DOC, STATE, RUNS, SOURCE, SCREEN,
};
