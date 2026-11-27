/**
 * «Splash реклама» — СЕРВЕР (эга 2026-11-28).
 *
 * Илова очилишидаги 2 сониялик реклама ўрни. Админ рекламачи креативини (расм ва/ёки матн, ихтиёрий ҳавола,
 * муддат, туманлар, устуворлик, ёқиш/ўчириш) киритади; мижоз фақат `visible == true` ҳужжатларни ўқийди
 * (rules), креативни кейинги очилиш учун олдиндан юклаб қўяди. Сана ва туман текшируви — клиентда
 * (кўрсатиш қарори; пул/ҳуқуқ эмас).
 *
 * Коллекциялар:
 *   splash_ads/{id}                — креатив (ёзиш ФАҚАТ шу CF'лар, `admin_audit` билан, 41-банд)
 *   splash_ad_stats/{adId}_{day}   — кунлик кўрсатишлар {adId, day, impressions, devices} (фақат CF, админ ўқийди)
 *   splash_ad_imp_log/{key}_{day}  — идемпотентлик: бир қурилма/фойдаланувчи бир кунни бир марта юборади
 *                                    (`expireAt` — ихтиёрий TTL сиёсати учун)
 *
 * Арзонлик (37-банд): мижоз бир кунлик кўрсатишларни йиғиб, кейинги кун БИТТА чақирув билан юборади
 * (кунига ≤ 1 чақирув/қурилма, фақат реклама кўрсатилган бўлса).
 */
'use strict';

const MODULE = 'splash_ads';
const ADS = 'splash_ads';
const STATS = 'splash_ad_stats';
const IMP_LOG = 'splash_ad_imp_log';
const ADMIN_AUDIT = 'admin_audit';
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);
const LANGS = Object.freeze(['uz_Cyrl', 'uz_Latn', 'ru']);
const AD_ID_RE = /^[A-Za-z0-9_-]{2,40}$/;
const DISTRICT_RE = /^[a-z0-9_-]{2,40}$/;
const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;
const STORAGE_URL_PREFIX = 'https://firebasestorage.googleapis.com/';
const TZ_OFFSET_MS = 5 * 3600000; // Тошкент
const DAY_MS = 86400000;
/** Бир қурилмада кунига энг кўпи 3 марта рекламачи креативи (эга 2026-11-28). */
const MAX_IMPRESSIONS_PER_DAY = 3;
const LIMITS = Object.freeze({
  title: 80, text: 140, imageUrl: 1000, linkUrl: 500, districts: 50, priorityMax: 100, reason: 300,
  maxDurationDays: 366, statsDays: 7, statsAdsPerDay: 5, logTtlDays: 30,
});
const AD_KEYS = Object.freeze(['title', 'text', 'imageUrl', 'linkUrl', 'startAtMs', 'endAtMs', 'districts', 'priority', 'active']);

const MSG = Object.freeze({
  UNAUTHENTICATED: ['Илтимос, тизимга киринг.', 'Iltimos, tizimga kiring.', 'Пожалуйста, войдите в систему.'],
  PERMISSION_DENIED: ['Бу амал учун рухсат йўқ.', 'Bu amal uçun ruxsat yöq.', 'Нет доступа к этому действию.'],
  SPLASH_AD_INVALID: ['Реклама маълумоти нотўғри.', "Reklama ma'lumoti notöğri.", 'Неверные данные рекламы.'],
  SPLASH_AD_NOT_FOUND: ['Реклама топилмади.', 'Reklama topilmadi.', 'Реклама не найдена.'],
  INVALID_REQUEST: ['Маълумот нотўғри. Қайта уриниб кўринг.', "Ma'lumot notöğri. Qayta urinib köring.", 'Неверные данные. Попробуйте ещё раз.'],
});
const messagesOf = (code) => { const m = MSG[code] || MSG.INVALID_REQUEST; return { uz_Cyrl: m[0], uz_Latn: m[1], ru: m[2] }; };

const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const str = (v) => (typeof v === 'string' ? v.trim() : '');

/** Тошкент санаси `YYYY-MM-DD`. */
function dayKeyOf(ms) {
  return new Date(ms + TZ_OFFSET_MS).toISOString().slice(0, 10);
}

/**
 * Админ киритган креативни текширади. Қайтаради: {ok, errors, clean}.
 * Вақт — миллисекунд (int). Расм — фақат Firebase Storage ҳаволаси; ҳавола — фақат https.
 */
function validateAd(raw) {
  const errors = [];
  if (!isObj(raw)) return { ok: false, errors: ['ad'], clean: null };
  const title = str(raw.title);
  if (!title || title.length > LIMITS.title) errors.push('title');
  const textIn = isObj(raw.text) ? raw.text : {};
  const text = {};
  for (const l of LANGS) {
    const t = str(textIn[l]);
    if (t.length > LIMITS.text) errors.push(`text.${l}`);
    if (t) text[l] = t;
  }
  const imageUrl = str(raw.imageUrl);
  if (imageUrl && (!imageUrl.startsWith(STORAGE_URL_PREFIX) || imageUrl.length > LIMITS.imageUrl)) errors.push('imageUrl');
  if (!imageUrl && !text.uz_Cyrl) errors.push('content'); // расм ёки камида кирилл матн
  const linkUrl = str(raw.linkUrl);
  if (linkUrl && (!/^https:\/\/[^\s]+$/.test(linkUrl) || linkUrl.length > LIMITS.linkUrl)) errors.push('linkUrl');
  const startAtMs = raw.startAtMs;
  const endAtMs = raw.endAtMs;
  if (!Number.isSafeInteger(startAtMs) || startAtMs <= 0) errors.push('startAtMs');
  if (!Number.isSafeInteger(endAtMs) || endAtMs <= 0) errors.push('endAtMs');
  if (Number.isSafeInteger(startAtMs) && Number.isSafeInteger(endAtMs)
    && (endAtMs <= startAtMs || endAtMs - startAtMs > LIMITS.maxDurationDays * DAY_MS)) errors.push('window');
  const districtsIn = raw.districts === undefined ? [] : raw.districts;
  if (!Array.isArray(districtsIn) || districtsIn.length > LIMITS.districts) errors.push('districts');
  const districts = Array.isArray(districtsIn) ? [...new Set(districtsIn.map(str))] : [];
  if (districts.some((d) => !DISTRICT_RE.test(d))) errors.push('districts');
  districts.sort();
  const priority = raw.priority === undefined ? 0 : raw.priority;
  if (!Number.isInteger(priority) || priority < 0 || priority > LIMITS.priorityMax) errors.push('priority');
  if (typeof raw.active !== 'boolean') errors.push('active');
  if (errors.length) return { ok: false, errors: [...new Set(errors)], clean: null };
  return {
    ok: true, errors: [],
    clean: { title, text, imageUrl, linkUrl, startAtMs, endAtMs, districts, priority, active: raw.active },
  };
}

/**
 * Мижоз юборган кунлик кўрсатишларни тозалайди: охирги [statsDays] кун (бугун ҳам), кунига ≤ 5 реклама,
 * кунига жами ≤ 3 (қурилма чегараси). Қайтаради: [{day, ads: {adId: n}, total}].
 */
function sanitizeImpressions(days, nowMs) {
  if (!isObj(days)) return null;
  const today = dayKeyOf(nowMs);
  const oldest = dayKeyOf(nowMs - LIMITS.statsDays * DAY_MS);
  const out = [];
  for (const [day, ads] of Object.entries(days)) {
    if (!DAY_RE.test(day) || day > today || day < oldest || !isObj(ads)) continue;
    let left = MAX_IMPRESSIONS_PER_DAY;
    const clean = {};
    for (const [adId, n] of Object.entries(ads).slice(0, LIMITS.statsAdsPerDay)) {
      if (!AD_ID_RE.test(adId) || !Number.isInteger(n) || n <= 0 || left <= 0) continue;
      const take = Math.min(n, left);
      clean[adId] = take;
      left -= take;
    }
    const total = MAX_IMPRESSIONS_PER_DAY - left;
    if (total > 0) out.push({ day, ads: clean, total });
    if (out.length >= LIMITS.statsDays + 1) break;
  }
  return out;
}

function attachSplashAds(exportsObj, deps) {
  const { functions, db, admin, callerPhone, canonicalUid, requireCallerRoles } = deps;
  const HttpsError = functions.https.HttpsError;
  const FV = admin.firestore.FieldValue;
  const TS = admin.firestore.Timestamp;
  const ts = () => FV.serverTimestamp();
  const now = () => (deps.nowMs ? deps.nowMs() : Date.now());
  const fail = (status, code, extra = {}) => new HttpsError(status, messagesOf(code).uz_Cyrl, { code, messages: messagesOf(code), ...extra });
  const log = (o) => console.log(JSON.stringify({ module: MODULE, ...o }));
  const tail = (p) => String(p || '').slice(-4);
  const reasonOf = (data) => (typeof (data && data.reason) === 'string' ? data.reason.trim().slice(0, LIMITS.reason) : '');

  const requireAdmin = async (context) => {
    try {
      return await requireCallerRoles(context, ADMIN_ROLES, 'Admin role required');
    } catch (e) {
      if (e instanceof HttpsError) throw fail(e.code, e.code === 'unauthenticated' ? 'UNAUTHENTICATED' : 'PERMISSION_DENIED');
      throw e;
    }
  };
  /** Ҳужжатдаги майдонларни аудит/солиштириш шаклига келтиради. */
  const pick = (d) => {
    if (!d) return null;
    const ms = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : (Number.isSafeInteger(v) ? v : null));
    return {
      title: d.title || '', text: isObj(d.text) ? d.text : {}, imageUrl: d.imageUrl || '', linkUrl: d.linkUrl || '',
      startAtMs: ms(d.startAt), endAtMs: ms(d.endAt), districts: Array.isArray(d.districts) ? d.districts : [],
      priority: Number.isInteger(d.priority) ? d.priority : 0, active: d.active === true,
    };
  };
  const same = (a, b) => JSON.stringify(AD_KEYS.map((k) => a[k])) === JSON.stringify(AD_KEYS.map((k) => b[k]));

  // ── 1. Админ: яратиш / таҳрирлаш ──
  exportsObj.adminUpsertSplashAd = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const v = validateAd(data && data.ad);
    if (!v.ok) throw fail('invalid-argument', 'SPLASH_AD_INVALID', { errors: v.errors.slice(0, 30) });
    const rawId = str(data && data.ad && data.ad.id);
    if (rawId && !AD_ID_RE.test(rawId)) throw fail('invalid-argument', 'SPLASH_AD_INVALID', { errors: ['id'] });
    const ref = rawId ? db.collection(ADS).doc(rawId) : db.collection(ADS).doc();
    const clean = v.clean;
    const reason = reasonOf(data);
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const cur = snap.exists ? pick(snap.data() || {}) : null;
      if (cur && same(cur, clean)) return { changed: false, version: (snap.data() || {}).version || 1 };
      const version = (snap.exists && Number.isInteger((snap.data() || {}).version) ? snap.data().version : 0) + 1;
      // Оммавий ҳужжат: админ телефони ЁЗИЛМАЙДИ (40-банд) — ким ўзгартиргани `admin_audit`да.
      t.set(ref, {
        title: clean.title, text: clean.text, imageUrl: clean.imageUrl, linkUrl: clean.linkUrl,
        startAt: TS.fromMillis(clean.startAtMs), endAt: TS.fromMillis(clean.endAtMs),
        districts: clean.districts, priority: clean.priority, active: clean.active, visible: clean.active,
        version, updatedAt: ts(), ...(snap.exists ? {} : { createdAt: ts() }),
      });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'splash_ad_set', actor, target: `${ADS}/${ref.id} v${version}`, before: cur, after: clean, reason, at: ts(),
      });
      return { changed: true, version };
    });
    log({ action: 'adminUpsertSplashAd', result: 'ok', userId: tail(actor), adId: ref.id, ...out });
    return { ok: true, adId: ref.id, ...out };
  });

  // ── 2. Админ: ўчириш (аудитда аввалги ҳолат сақланади) ──
  exportsObj.adminDeleteSplashAd = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const id = str(data && data.id);
    if (!AD_ID_RE.test(id)) throw fail('invalid-argument', 'SPLASH_AD_INVALID', { errors: ['id'] });
    const ref = db.collection(ADS).doc(id);
    const reason = reasonOf(data);
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) return { deleted: false }; // идемпотент: қайта чақирув — хато эмас
      t.delete(ref);
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'splash_ad_delete', actor, target: `${ADS}/${id}`, before: pick(snap.data() || {}), after: null, reason, at: ts(),
      });
      return { deleted: true };
    });
    log({ action: 'adminDeleteSplashAd', result: 'ok', userId: tail(actor), adId: id, ...out });
    return { ok: true, adId: id, ...out };
  });

  // ── 3. Мижоз: кунлик кўрсатишлар (йиғма, идемпотент) ──
  exportsObj.recordSplashImpressions = functions.https.onCall(async (data, context) => {
    if (!context || !context.auth) throw fail('unauthenticated', 'UNAUTHENTICATED');
    const phone = canonicalUid(callerPhone(context) || '');
    const key = phone && phone.length >= 9 ? phone : `a_${String(context.auth.uid || '').slice(0, 64)}`;
    if (key === 'a_') throw fail('unauthenticated', 'UNAUTHENTICATED');
    const days = sanitizeImpressions(data && data.days, now());
    if (days === null) throw fail('invalid-argument', 'INVALID_REQUEST');
    if (!days.length) return { ok: true, recorded: 0 };
    const out = await db.runTransaction(async (t) => {
      const logRefs = days.map((d) => db.collection(IMP_LOG).doc(`${key}_${d.day}`));
      const adIds = [...new Set(days.flatMap((d) => Object.keys(d.ads)))];
      const [logSnaps, adSnaps] = await Promise.all([
        Promise.all(logRefs.map((r) => t.get(r))),
        Promise.all(adIds.map((id) => t.get(db.collection(ADS).doc(id)))),
      ]);
      const known = new Set(adSnaps.filter((s) => s.exists).map((s) => s.id));
      let recorded = 0;
      days.forEach((d, i) => {
        if (logSnaps[i].exists) return; // бу кун аллақачон ҳисобланган (retry)
        const ads = Object.entries(d.ads).filter(([id]) => known.has(id));
        t.set(logRefs[i], {
          day: d.day, n: ads.reduce((s, [, n]) => s + n, 0), at: ts(),
          expireAt: TS.fromMillis(now() + LIMITS.logTtlDays * DAY_MS),
        });
        ads.forEach(([adId, n]) => {
          t.set(db.collection(STATS).doc(`${adId}_${d.day}`), {
            adId, day: d.day, impressions: FV.increment(n), devices: FV.increment(1), updatedAt: ts(),
          }, { merge: true });
          recorded += n;
        });
      });
      return { recorded };
    });
    log({ action: 'recordSplashImpressions', result: 'ok', userId: tail(key), days: days.length, ...out });
    return { ok: true, ...out };
  });

  return { validateAd, sanitizeImpressions, dayKeyOf };
}

module.exports = {
  attachSplashAds, validateAd, sanitizeImpressions, dayKeyOf, MAX_IMPRESSIONS_PER_DAY, ADS, STATS, IMP_LOG,
};
