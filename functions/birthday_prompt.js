/**
 * «Туғилган кунингизни киритинг» — ҲАФТАЛИК ПУШ (эга 2026-11-28, 9-банд).
 *
 * Мақсад: туғилган санаси ЙЎҚ фойдаланувчиларга ҳафтада бир марта эслатма — шунда holiday.js
 * ўз туғилган куни эслатмалари (runSelfBirthdayReminders, users.birthDate) ишлай бошлайди.
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
 *   settings/birthday_prompt          — {stage, internalPhones, pilotDistrictIds, maxSends, version, updatedAt, updatedBy}
 *                                        ҳужжат йўқ = OFF. Ёзиш ФАҚАТ adminSetBirthdayPromptSettings (admin_audit).
 *   birthday_prompt_state/{998…}      — {sends, lastWeek, firstAt, lastAt} — ҳафтада бир марта + N тагача (идемпотентлик).
 *   birthday_prompt_runs/{week}_{stage} — тарқатиш курсори, lease, статистика.
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
const SETTINGS_KEYS = Object.freeze(['stage', 'internalPhones', 'pilotDistrictIds', 'maxSends']);

/** PROPOSED (эга тасдиқлаши керак): 4 ҳафта (≈1 ой) — кейин тўхтайди. Админ 1–12 оралиғида ўзгартиради. */
const DEFAULT_MAX_SENDS = 4;
const LIMITS = Object.freeze({
  maxSendsMin: 1, maxSendsMax: 12, phones: 50, districts: 30, // Firestore `in` — 30 тагача
  page: 300, concurrency: 20, runBudgetMs: 420000, leaseMs: 570000, // lease > timeout 540 s, < cron оралиғи 600 s reasonMax: 300,
});
/** Юбориш ойнаси (PROPOSED): ЯКШАНБА 11:00–18:59 Тошкент. Cron шу ойнада ҳар 10 дақиқада давом эттиради. */
const WINDOW = Object.freeze({ weekday: 0, fromHour: 11, toHour: 19 });
const SCHEDULE = '*/10 11-18 * * 0';

// ── Хабар матни (3 тил; uz_Latn — янги ҳарфлар Ö Ğ Ş Ç). PROPOSED матн; бош саҳифа карточкаси сарлавҳаси билан бир хил. ──
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

/** Юбориш ойнасидами (Тошкент): якшанба 11:00–18:59. Кечикиб келган Scheduler қайта уриниши кечаси юбормасин. */
function inSendWindow(ms) {
  const t = new Date(ms + TZ_OFFSET_MS);
  const hr = t.getUTCHours();
  return t.getUTCDay() === WINDOW.weekday && hr >= WINDOW.fromHour && hr < WINDOW.toHour;
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

/** Шу ҳафтада юборса бўладими (идемпотентлик + чегара). state — birthday_prompt_state ҳужжати ёки null. */
function claimDecision(state, week, maxSends) {
  const s = isObj(state) ? state : {};
  const sends = Number.isInteger(s.sends) && s.sends > 0 ? s.sends : 0;
  if (s.lastWeek === week) return { ok: false, reason: 'ALREADY_THIS_WEEK' };
  if (sends >= maxSends) return { ok: false, reason: 'CAP_REACHED' };
  return { ok: true, sends: sends + 1 };
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
  if (!Number.isInteger(s.maxSends) || s.maxSends < LIMITS.maxSendsMin || s.maxSends > LIMITS.maxSendsMax) errors.push('MAX_SENDS_INVALID maxSends');
  if (s.stage === 'pilot' && Array.isArray(s.pilotDistrictIds) && s.pilotDistrictIds.length === 0
    && Array.isArray(s.internalPhones) && s.internalPhones.length === 0) errors.push('PILOT_EMPTY pilotDistrictIds');
  return { ok: errors.length === 0, errors };
}

/** Сақланган ҳужжат → самарали созлама (йўқ/бузуқ = OFF; эски ҳужжатда йўқ майдон — сукут, 26-банд). */
function normalizeSettings(raw) {
  const r = isObj(raw) ? raw : {};
  const list = (v, re, max) => (Array.isArray(v) ? v.filter((x) => typeof x === 'string' && re.test(x)).slice(0, max) : []);
  return {
    stage: STAGES.includes(r.stage) ? r.stage : 'off',
    internalPhones: list(r.internalPhones, PHONE_RE, LIMITS.phones),
    pilotDistrictIds: list(r.pilotDistrictIds, DISTRICT_RE, LIMITS.districts),
    maxSends: Number.isInteger(r.maxSends) && r.maxSends >= LIMITS.maxSendsMin && r.maxSends <= LIMITS.maxSendsMax ? r.maxSends : DEFAULT_MAX_SENDS,
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
  const PROJECTION = ['birthDate', 'fcmToken', 'appLang', 'holidayRemindersOptIn', 'deleted', 'deletion'];

  const requireAdmin = async (context) => {
    try {
      return await requireCallerRoles(context, ADMIN_ROLES, 'Admin role required');
    } catch (e) {
      if (e instanceof HttpsError) throw fail(e.code, e.code === 'unauthenticated' ? 'UNAUTHENTICATED' : 'PERMISSION_DENIED');
      throw e;
    }
  };

  /**
   * Битта номзод: транзакцияда «шу ҳафта — бир марта, жами ≤ maxSends» белгиси олинади, кейин хабар.
   * Энг кўпи бир марта (retry/параллел чақирув иккинчи марта юбормайди). Хабар хатоси — шу ҳафта ўтказилади (log).
   */
  async function promptOne(uid, u, week, maxSends, stat) {
    const ref = db.collection(STATE).doc(uid);
    const claim = await db.runTransaction(async (t) => {
      const s = await t.get(ref);
      const dec = claimDecision(s.exists ? s.data() : null, week, maxSends);
      if (!dec.ok) return dec;
      t.set(ref, { sends: dec.sends, lastWeek: week, lastAt: ts(), ...(s.exists ? {} : { firstAt: ts() }) }, { merge: true });
      return dec;
    });
    if (!claim.ok) { stat[claim.reason] = (stat[claim.reason] || 0) + 1; return; }
    const m = promptTextFor(u.appLang);
    try {
      await notifyUserInApp({
        userId: uid, title: m.title, body: m.body, category: 'info', source: SOURCE, dataType: SOURCE, screen: SCREEN,
        extraNews: { promptWeek: week, promptSend: claim.sends }, extraData: { promptWeek: week },
      });
      stat.sent += 1;
    } catch (e) {
      stat.NOTIFY_FAILED = (stat.NOTIFY_FAILED || 0) + 1;
      log({ action: 'birthdayPromptSend', result: 'error', errorCode: 'NOTIFY_FAILED', userId: tail(uid), week });
    }
  }

  async function processDocs(docs, week, maxSends, stat) {
    const candidates = [];
    for (const d of docs) {
      stat.scanned += 1;
      const reason = skipReasonOf(d.id, d.data());
      if (reason) stat[reason] = (stat[reason] || 0) + 1; else candidates.push(d);
    }
    await mapPool(candidates, LIMITS.concurrency, (d) => promptOne(d.id, d.data() || {}, week, maxSends, stat));
  }

  async function processPhones(phones, week, maxSends, stat) {
    const snaps = phones.length ? await db.getAll(...phones.map((p) => db.collection('users').doc(p)), { fieldMask: PROJECTION }) : [];
    const docs = snaps.filter((s) => s.exists);
    stat.MISSING_USER = (stat.MISSING_USER || 0) + (snaps.length - docs.length);
    await processDocs(docs, week, maxSends, stat);
  }

  /**
   * Бир чақирув: lease → (тестерлар) → курсор бўйича саҳифалар (вақт бюджети тугагунча) → курсор сақланади.
   * internal — фақат internalPhones; pilot — internalPhones + pilotDistrictIds туманлари (`districtId in`);
   * public — бутун users (ҳужжат ID бўйича курсор). Ҳафта/босқич учун битта run ҳужжати.
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
    const week = weekKeyOfMs(nowMs);
    const runRef = db.collection(RUNS).doc(`${week}_${cfg.stage}`);
    const lease = await db.runTransaction(async (t) => {
      const s = await t.get(runRef);
      const r = s.exists ? (s.data() || {}) : {};
      if (r.done === true) return { ok: false, reason: 'DONE' };
      const leaseMs = r.leaseUntil && typeof r.leaseUntil.toMillis === 'function' ? r.leaseUntil.toMillis() : 0;
      if (leaseMs > nowMs) return { ok: false, reason: 'LEASED' };
      t.set(runRef, {
        week, stage: cfg.stage, leaseUntil: admin.firestore.Timestamp.fromMillis(nowMs + LIMITS.leaseMs), updatedAt: ts(),
        ...(s.exists ? {} : { startedAt: ts(), done: false, testersDone: false, cursor: null }),
      }, { merge: true });
      return { ok: true, run: r };
    });
    if (!lease.ok) { log({ action: 'birthdayPrompt', result: 'skip', reason: lease.reason, week, stage: cfg.stage }); return { result: 'skip', reason: lease.reason }; }
    const stat = { scanned: 0, sent: 0 };
    let cursor = lease.run.cursor || null;
    let done = false;
    let errorCode = null;
    try {
      if (cfg.stage !== 'public' && lease.run.testersDone !== true) {
        await processPhones(cfg.internalPhones, week, cfg.maxSends, stat);
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
          await processDocs(snap.docs, week, cfg.maxSends, stat);
          cursor = snap.docs[snap.docs.length - 1].id;
          await runRef.set({ cursor, updatedAt: ts() }, { merge: true }); // саҳифадан КЕЙИН: узилса — саҳифа қайта, юбориш бир марта
          if (snap.size < pageSize) { done = true; break; }
        }
      }
    } catch (e) {
      errorCode = 'RUN_FAILED';
      log({ action: 'birthdayPrompt', result: 'error', errorCode, week, stage: cfg.stage, message: String((e && e.message) || e).slice(0, 200) });
    }
    const inc = {};
    for (const [k, v] of Object.entries(stat)) if (v) inc[`stats.${k}`] = FV.increment(v);
    await runRef.update({ ...inc, ...(done ? { done: true, doneAt: ts() } : {}), leaseUntil: FV.delete(), updatedAt: ts() });
    const out = { result: errorCode ? 'error' : 'ok', week, stage: cfg.stage, done, ...stat, ...(errorCode ? { errorCode } : {}), duration: Date.now() - started };
    log({ action: 'birthdayPrompt', ...out });
    return out;
  }

  // Ҳафтада бир марта: якшанба 11:00 дан (Тошкент) ҳар 10 дақиқада давом — курсор тугаса `done`, қолганлари бўш ишлайди.
  exportsObj.birthdayPromptWeekly = functions
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
      defaults: { maxSends: DEFAULT_MAX_SENDS, schedule: SCHEDULE, timeZone: 'Asia/Tashkent' },
      runs: runs.docs.map((d) => { const r = d.data() || {}; return { id: d.id, week: r.week || '', stage: r.stage || '', done: r.done === true, stats: r.stats || {} }; }),
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
      t.set(settingsRef(), { ...pick(s), version, updatedAt: ts(), updatedBy: actor, ...(cur ? {} : { createdAt: ts() }) });
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
  isoWeekKey, weekKeyOfMs, inSendWindow, hasBirthDate, skipReasonOf, claimDecision, validateSettings, normalizeSettings,
  promptTextFor, mapPool, messagesOf,
  PROMPT_TEXT, DEFAULT_MAX_SENDS, LIMITS, WINDOW, SCHEDULE, SETTINGS_DOC, STATE, RUNS, SOURCE, SCREEN,
};
