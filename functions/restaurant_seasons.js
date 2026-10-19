/**
 * KAFE-RESTORAN — mavsumiy bo'limlar va Ramazon jadvali (S5/S7, D-REST-22; docs/kafe_restoran_taklifi_uz.md §10.1).
 *
 * Ega qarori (CONFIRMED, 2026-10-19): mavsumiy bo'limlar (Ramazon, Navro'z, Qurbon hayit, Yangi yil, to'y mavsumi)
 * sanadan 9–10 kun OLDIN avtomatik ochiladi va muddat tugagach yopiladi (sozlama: 10 kun). Ramazon va Qurbon sanasi oy
 * taqvimidan hisoblanadi; rasmiy boshlanishni Musulmonlar idorasi oyni kuzatib tasdiqlaydi (2026: Saudiyada 18 fevral,
 * O'zbekistonda 19 fevral) → taxminiy sana avtomat, admin tasdiqlaydi yoki 1 kunga suradi. Saharlik/iftor vaqti — idoraning
 * rasmiy taqvimi: Toshkent vaqti + hududlar bo'yicha daqiqa farqi (Nukus +42, Andijon −11), har yili AVA jamoasi
 * versiyalangan jadval qilib kiritadi (sotuvchilar emas — 7-qoida). Jadvalda hudud bo'lmasa vaqt TAXMIN QILINMAYDI (1-qoida).
 *
 * Ma'lumot:
 *   - `settings/restaurant_seasons`: `periods: [{ key, from, to, confirmed }]` (`YYYY-MM-DD`, Toshkent kuni, ikkala chekka
 *     ham kiradi), `opensDaysBefore` (10). Faqat CF yozadi (versiya + `restaurant_seasons_history/v{n}` + audit).
 *   - `settings/restaurant_ramadan`: `days: { 'YYYY-MM-DD': { sahar:'HH:mm', iftar:'HH:mm' } }` (Toshkent vaqti),
 *     `offsets: { <geo_regions id>: daqiqa }`. Faqat CF yozadi (versiya + `restaurant_ramadan_history/v{n}` + audit).
 *   - Taxminiy davrlar: kunlik `ensureRestaurantSeasons` yetishmayotgan YILLAR uchun qo'shadi (`confirmed:false`), admin
 *     o'zgartirganiga (yoki tasdiqlaganiga) TEGMAYDI. Navro'z (21 mart) va Yangi yil (31 dekabr–1 yanvar) — qat'iy sanalar
 *     (INFERRED: davr uzunligini ega aytmagan — admin o'zgartiradi); to'y mavsumi sanasi UNKNOWN — faqat admin kiritadi.
 *
 * Diagnostika kodlari: PERIODS_INVALID, OPENS_INVALID, RAMADAN_DAYS_INVALID, RAMADAN_OFFSETS_INVALID, REASON_REQUIRED.
 * Bo'lim kirishi mavsum teglari bo'yicha (`restaurant_dish_index.js`); qaysi mavsum HOZIR ochiqligi shu yerdagi
 * `activeSeasons` qoidasi (klientda nusxasi — parity testi).
 */
'use strict';

const { SEASON_KEYS } = require('./restaurant_dish_index');

const SEASONS_DOC = ['settings', 'restaurant_seasons'];
const SEASONS_HISTORY = 'restaurant_seasons_history';
const RAMADAN_DOC = ['settings', 'restaurant_ramadan'];
const RAMADAN_HISTORY = 'restaurant_ramadan_history';
const ADMIN_AUDIT = 'admin_audit';
const MODULE_ID = 'restaurants';

const DEFAULT_OPENS_DAYS = 10;
const MAX_PERIODS = 60;
const MAX_SPAN_DAYS = 120;
const MAX_RAMADAN_DAYS = 45;
const MAX_OFFSETS = 100;
const TASHKENT_UTC_OFFSET_H = 5;
const DAY = 24 * 60 * 60 * 1000;

const pad = (n) => String(n).padStart(2, '0');

/** `YYYY-MM-DD` ni qat'iy tekshiradi (mavjud sana bo'lishi shart: 2027-02-30 — yo'q). */
function parseIsoDate(s) {
  if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
  const [y, m, d] = s.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) return null;
  return dt.getTime();
}

const isoOfUtcMs = (ms) => {
  const d = new Date(ms);
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
};

/** Hozirgi Toshkent kuni (`YYYY-MM-DD`). */
function tashkentToday(nowMs) {
  return isoOfUtcMs(nowMs + TASHKENT_UTC_OFFSET_H * 3600 * 1000);
}

/** Davrlar ro'yxatini tekshiradi: to'g'ri bo'lsa tozalangan nusxa, aks holda `null`. */
function sanitizePeriods(raw) {
  if (!Array.isArray(raw) || raw.length > MAX_PERIODS) return null;
  const out = [];
  const seen = new Set();
  for (const p of raw) {
    if (!p || typeof p !== 'object') return null;
    if (!SEASON_KEYS.includes(p.key)) return null;
    const from = parseIsoDate(p.from);
    const to = parseIsoDate(p.to);
    if (from == null || to == null || to < from) return null;
    if ((to - from) / DAY + 1 > MAX_SPAN_DAYS) return null;
    const id = `${p.key}|${p.from}`;
    if (seen.has(id)) return null;
    seen.add(id);
    out.push({ key: p.key, from: p.from, to: p.to, confirmed: p.confirmed === true });
  }
  out.sort((a, b) => (a.from < b.from ? -1 : a.from > b.from ? 1 : a.key < b.key ? -1 : 1));
  return out;
}

/**
 * Hozir ochiq mavsumlar: bugungi Toshkent kuni `[from − opensDaysBefore, to]` ichida bo'lsa. Natija — kalitlar
 * (SEASON_KEYS tartibida), har biri uchun eng yaqin davr.
 */
function activeSeasons(periods, nowMs, opensDaysBefore = DEFAULT_OPENS_DAYS) {
  const today = parseIsoDate(tashkentToday(nowMs));
  const out = [];
  for (const key of SEASON_KEYS) {
    const hit = (periods || [])
      .filter((p) => p.key === key)
      .map((p) => ({ ...p, fromMs: parseIsoDate(p.from), toMs: parseIsoDate(p.to) }))
      .filter((p) => p.fromMs != null && p.toMs != null && today >= p.fromMs - opensDaysBefore * DAY && today <= p.toMs)
      .sort((a, b) => a.fromMs - b.fromMs)[0];
    if (hit) out.push({ key, from: hit.from, to: hit.to, confirmed: hit.confirmed === true, opensOn: isoOfUtcMs(hit.fromMs - opensDaysBefore * DAY) });
  }
  return out;
}

/**
 * Hijriy (Umm al-Qura) kunlardan taxminiy Gregorian sana: `year` ichida `month`/`day` ga to'g'ri kelgan birinchi kun.
 * Ramazon boshlanishi = 9-oy 1-kun; Qurbon hayit = 12-oy 10-kun. Node'ning to'liq ICU'si kerak (Cloud Functions'da bor);
 * ICU yo'q bo'lsa `null` (taxmin qilinmaydi).
 */
function hijriToGregorian(year, month, day) {
  let fmt;
  try {
    fmt = new Intl.DateTimeFormat('en-u-ca-islamic-umalqura', { month: 'numeric', day: 'numeric', timeZone: 'UTC' });
    if (!/\d/.test(fmt.format(new Date(Date.UTC(year, 0, 1))))) return null;
  } catch (e) {
    return null;
  }
  for (let ms = Date.UTC(year, 0, 1); ms <= Date.UTC(year, 11, 31); ms += DAY) {
    const parts = Object.fromEntries(fmt.formatToParts(new Date(ms)).map((p) => [p.type, p.value]));
    if (Number(parts.month) === month && Number(parts.day) === day) return ms;
  }
  return null;
}

/** Bitta mavsumning `year` yilidagi taxminiy davri (yoki `null` — taxmin qilib bo'lmaydi / admin kiritadi). */
function estimatePeriod(key, year) {
  if (key === 'navruz') return { key, from: `${year}-03-21`, to: `${year}-03-21`, confirmed: false };
  if (key === 'newyear') return { key, from: `${year}-12-31`, to: `${year + 1}-01-01`, confirmed: false };
  if (key === 'ramadan') {
    const start = hijriToGregorian(year, 9, 1);
    if (start == null) return null;
    const shawwal = hijriToGregorian(year, 10, 1);
    // Ramazon 29 yoki 30 kun: 1-shavvol ayni yilda topilsa undan oldingi kun, topilmasa 30 kun.
    const end = shawwal != null && shawwal > start ? shawwal - DAY : start + 29 * DAY;
    return { key, from: isoOfUtcMs(start), to: isoOfUtcMs(end), confirmed: false };
  }
  if (key === 'qurbon') {
    const eid = hijriToGregorian(year, 12, 10);
    if (eid == null) return null;
    return { key, from: isoOfUtcMs(eid), to: isoOfUtcMs(eid + 3 * DAY), confirmed: false }; // 10–13 zulhijja
  }
  return null; // wedding: sana manbasi UNKNOWN
}

/**
 * Yetishmayotgan yillar uchun taxminiy davrlarni qo'shadi. Mavjud (admin kiritgan/tasdiqlagan) davrga TEGILMAYDI:
 * `key` uchun `from` shu Gregorian yilda bo'lgan davr bor bo'lsa — o'tkaziladi.
 */
function withEstimates(periods, years) {
  const out = [...(periods || [])];
  const added = [];
  for (const year of years) {
    for (const key of ['ramadan', 'qurbon', 'navruz', 'newyear']) {
      if (out.some((p) => p.key === key && String(p.from).startsWith(`${year}-`))) continue;
      const est = estimatePeriod(key, year);
      if (est) {
        out.push(est);
        added.push(est);
      }
    }
  }
  return { periods: sanitizePeriods(out) || (periods || []), added };
}

// ── Ramazon jadvali ──────────────────────────────────────────────────
const HHMM = /^([01]\d|2[0-3]):[0-5]\d$/;

function sanitizeRamadanDays(raw) {
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const keys = Object.keys(raw);
  if (keys.length > MAX_RAMADAN_DAYS) return null;
  const out = {};
  for (const k of keys.sort()) {
    const v = raw[k];
    if (parseIsoDate(k) == null || !v || typeof v !== 'object') return null;
    if (!HHMM.test(v.sahar) || !HHMM.test(v.iftar)) return null;
    out[k] = { sahar: v.sahar, iftar: v.iftar };
  }
  return out;
}

function sanitizeRamadanOffsets(raw) {
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const keys = Object.keys(raw);
  if (keys.length > MAX_OFFSETS) return null;
  const out = {};
  for (const k of keys.sort()) {
    const v = raw[k];
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(k) || typeof v !== 'number' || !Number.isInteger(v) || v < -120 || v > 120) return null;
    out[k] = v;
  }
  return out;
}

/** Toshkent `HH:mm` + daqiqa farqi → `HH:mm` (yarim tundan o'tsa aylanadi). */
function shiftHhmm(hhmm, minutes) {
  if (!HHMM.test(hhmm)) return null;
  const [h, m] = hhmm.split(':').map(Number);
  const total = (((h * 60 + m + minutes) % 1440) + 1440) % 1440;
  return `${pad(Math.floor(total / 60))}:${pad(total % 60)}`;
}

/**
 * Bugungi saharlik/iftor vaqti `regionId` uchun: kun jadvalda va hudud farqi kiritilgan bo'lsa — `{ sahar, iftar }`;
 * aks holda `null` (vaqt TAXMIN QILINMAYDI). Klientda nusxasi bor (parity testi).
 */
function ramadanTimesFor(cfg, isoDay, regionId) {
  if (!cfg || !cfg.days || !cfg.offsets) return null;
  const day = cfg.days[isoDay];
  if (!day || typeof regionId !== 'string' || !Object.prototype.hasOwnProperty.call(cfg.offsets, regionId)) return null;
  const off = cfg.offsets[regionId];
  if (!Number.isInteger(off)) return null;
  const sahar = shiftHhmm(day.sahar, off);
  const iftar = shiftHhmm(day.iftar, off);
  return sahar && iftar ? { sahar, iftar } : null;
}

function str(v, max) {
  return String(v == null ? '' : v).trim().slice(0, max);
}

function attachRestaurantSeasons(exportsObj, deps) {
  const { functions, db, admin, requireCallerRoles, now: nowFn } = deps;
  const now = nowFn || (() => new Date());
  const HttpsError = functions.https.HttpsError;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const fail = (status, code, extra = {}) => new HttpsError(status, code, { code, ...extra });

  function log(action, fields) {
    console.log(JSON.stringify({ module: MODULE_ID, action: `seasons_${action}`, ...fields }));
  }

  /** Versiyalab yozadi (o'zgarish bo'lmasa versiya OSHMAYDI — idempotent). */
  async function writeVersioned({ doc, history, audit, next, actor, reason }) {
    const ref = db.collection(doc[0]).doc(doc[1]);
    return db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const cur = snap.exists ? (snap.data() || {}) : {};
      const pick = (o) => JSON.stringify(Object.fromEntries(Object.keys(next).map((k) => [k, o[k]])));
      if (snap.exists && pick(cur) === JSON.stringify(next)) {
        return { version: Number.isInteger(cur.version) ? cur.version : 0, changed: false };
      }
      const version = (Number.isInteger(cur.version) ? cur.version : 0) + 1;
      const payload = { ...next, version, reason, updatedAt: ts(), updatedBy: actor };
      t.set(ref, payload);
      t.create(db.collection(history).doc(`v${version}`), { ...payload, previousVersion: snap.exists ? (cur.version || 0) : null });
      t.set(db.collection(ADMIN_AUDIT).doc(), { kind: audit, actor, target: `v${version}`, reason, at: ts() });
      return { version, changed: true };
    });
  }

  /**
   * Admin — mavsum davrlari (TO'LIQ ro'yxat almashtiriladi; berilmagan qiymat saqlanadi).
   * data: { periods?: [{key, from, to, confirmed?}], opensDaysBefore?, reason }
   */
  exportsObj.adminSetRestaurantSeasons = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, ['admin', 'superadmin'], 'Admin role required');
    const reason = str(data && data.reason, 300);
    if (reason.length < 3) throw fail('invalid-argument', 'REASON_REQUIRED');
    const snap = await db.collection(SEASONS_DOC[0]).doc(SEASONS_DOC[1]).get();
    const cur = snap.exists ? (snap.data() || {}) : {};
    let periods = sanitizePeriods(cur.periods) || [];
    if (data && data.periods != null) {
      periods = sanitizePeriods(data.periods);
      if (!periods) throw fail('invalid-argument', 'PERIODS_INVALID');
    }
    let opens = Number.isInteger(cur.opensDaysBefore) ? cur.opensDaysBefore : DEFAULT_OPENS_DAYS;
    if (data && data.opensDaysBefore != null) {
      opens = data.opensDaysBefore;
      if (!Number.isInteger(opens) || opens < 0 || opens > 30) throw fail('invalid-argument', 'OPENS_INVALID');
    }
    const out = await writeVersioned({
      doc: SEASONS_DOC, history: SEASONS_HISTORY, audit: 'restaurant_seasons_set',
      next: { periods, opensDaysBefore: opens }, actor, reason,
    });
    log('set', { userId: actor, version: out.version, changed: out.changed, periods: periods.length, result: 'ok' });
    return { ok: true, ...out };
  });

  /**
   * Admin — Ramazon jadvali (saharlik/iftor, Toshkent vaqti) va hududlar bo'yicha daqiqa farqi. TO'LIQ almashtiriladi.
   * data: { days: { 'YYYY-MM-DD': { sahar, iftar } }, offsets: { <regionId>: daqiqa }, reason }
   */
  exportsObj.adminSetRestaurantRamadan = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, ['admin', 'superadmin'], 'Admin role required');
    const reason = str(data && data.reason, 300);
    if (reason.length < 3) throw fail('invalid-argument', 'REASON_REQUIRED');
    const days = sanitizeRamadanDays(data && data.days);
    if (!days) throw fail('invalid-argument', 'RAMADAN_DAYS_INVALID');
    const offsets = sanitizeRamadanOffsets(data && data.offsets);
    if (!offsets) throw fail('invalid-argument', 'RAMADAN_OFFSETS_INVALID');
    const out = await writeVersioned({
      doc: RAMADAN_DOC, history: RAMADAN_HISTORY, audit: 'restaurant_ramadan_set',
      next: { days, offsets }, actor, reason,
    });
    log('ramadan_set', { userId: actor, version: out.version, changed: out.changed, days: Object.keys(days).length, result: 'ok' });
    return { ok: true, ...out };
  });

  /** Kunlik: joriy va keyingi yil uchun yetishmayotgan TAXMINIY davrlarni qo'shadi (admin kiritganiga tegmaydi). */
  async function ensureEstimates() {
    const year = new Date(now().getTime() + TASHKENT_UTC_OFFSET_H * 3600 * 1000).getUTCFullYear();
    const ref = db.collection(SEASONS_DOC[0]).doc(SEASONS_DOC[1]);
    const snap = await ref.get();
    const cur = snap.exists ? (snap.data() || {}) : {};
    const periods = sanitizePeriods(cur.periods) || [];
    const { periods: merged, added } = withEstimates(periods, [year, year + 1]);
    if (added.length === 0) return { added: 0 };
    const opens = Number.isInteger(cur.opensDaysBefore) ? cur.opensDaysBefore : DEFAULT_OPENS_DAYS;
    const out = await writeVersioned({
      doc: SEASONS_DOC, history: SEASONS_HISTORY, audit: 'restaurant_seasons_set',
      next: { periods: merged, opensDaysBefore: opens }, actor: 'system:ensureRestaurantSeasons',
      reason: `Taxminiy davrlar qo'shildi: ${added.map((p) => `${p.key} ${p.from}`).join(', ')}`.slice(0, 300),
    });
    log('ensure', { added: added.length, version: out.version, result: 'ok' });
    return { added: added.length, version: out.version };
  }

  exportsObj.ensureRestaurantSeasons = functions.pubsub
    .schedule('every 24 hours')
    .timeZone('Asia/Tashkent')
    .onRun(async () => ensureEstimates());

  return { ensureEstimates };
}

module.exports = {
  attachRestaurantSeasons,
  parseIsoDate, tashkentToday, sanitizePeriods, activeSeasons, hijriToGregorian, estimatePeriod, withEstimates,
  sanitizeRamadanDays, sanitizeRamadanOffsets, shiftHhmm, ramadanTimesFor,
  SEASONS_DOC, RAMADAN_DOC, DEFAULT_OPENS_DAYS,
};
