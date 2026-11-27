/**
 * Qurilma xavfsizligi (ega qarori 2026-11-28, docs/qurilma_va_qr_kirish_2026-11-28_uz.md).
 *
 * - `settings/app.deviceBindingAutoApprove` ENDI HISOBGA OLINMAYDI: yangi qurilma tasdiqsiz token olmaydi.
 *   Favqulodda qaytarish — faqat KOD orqali (`DEVICE_SEC.EMERGENCY_HONOR_AUTO_APPROVE = true` + redeploy),
 *   klient yoki admin panel tugmasi bilan EMAS; imtiyozli (panel rolli) raqamlarga hech qachon.
 * - Tasdiq yo'llari: (a) bog'langan qurilma «Бу сизми?» → Ҳа/Йўқ (`device_transfer_requests`,
 *   channel `old_device_push`); (b) «Эски телефоним йўқ» → admin ko'rigi (shu kolleksiya, channel
 *   `admin_review`) → admin panel «Қурилма тасдиқлари».
 * - Har bir bog'lash o'zgarishi/urinishi — `device_binding_events` (append-only, faqat server yozadi,
 *   klient o'qiy olmaydi: rules'da match yo'q = deny).
 * - Rate limit (`device_binding_rate`), «Йўқ» → 24 soat blok (`device_binding_denials`).
 *
 * Bu faylda: sof yordamchilar (testlanadi) + `makeDeviceSecurity` (Firestore/Auth yordamchilari) +
 * `attachDeviceSecurity` (yangi callable'lar).
 */
'use strict';

const crypto = require('crypto');
const { PANEL_ROLES } = require('./admin_pin');

const DEVICE_SEC = Object.freeze({
  // FAVQULODDA QAYTARISH (rollback): true bo'lsa `settings/app.deviceBindingAutoApprove === true`
  // yana ishlaydi — faqat imtiyozsiz raqamlar uchun. O'zgartirish = kod + functions redeploy.
  EMERGENCY_HONOR_AUTO_APPROVE: false,
  RATE_WINDOW_MS: 60 * 60 * 1000,
  RATE_MAX_PER_PHONE: 5,
  RATE_MAX_PER_DEVICE: 5,
  // CGNAT: UZ mobil operatorlarida ko'p abonent bitta IP'da — shuning uchun telefon/qurilmadan kengroq.
  RATE_MAX_PER_IP: 30,
  ATTEMPT_NOTIFY_THROTTLE_MS: 15 * 60 * 1000,
  DENIAL_MS: 24 * 60 * 60 * 1000,
  TRUST_LIMITED_MS: 24 * 60 * 60 * 1000,
  ADMIN_REVIEW_TTL_MS: 72 * 60 * 60 * 1000,
  ADMIN_REVIEW_MAX_PER_DAY: 3,
  NOTE_MAX: 300,
  ADMIN_ALERT_ROLES: ['admin', 'superadmin'],
  ADMIN_ALERT_MAX: 30,
  DECIDER_ROLES: ['admin', 'superadmin'],
  PLAY_URL: 'https://play.google.com/store/apps/details?id=uz.ava.gurlan',
});

const COL = Object.freeze({
  EVENTS: 'device_binding_events',
  DENIALS: 'device_binding_denials',
  RATE: 'device_binding_rate',
  REQUESTS: 'device_transfer_requests',
});

const CHANNEL_PEER = 'old_device_push';
const CHANNEL_ADMIN = 'admin_review';

/** Foydalanuvchiga ko'rinadigan matnlar — 3 til (§25: ichki kod alohida). */
const MESSAGES = Object.freeze({
  DEVICE_BINDING_RATE_LIMITED: {
    uz_Cyrl: 'Жуда кўп уриниш бўлди. Бир соатдан кейин қайта уриниб кўринг.',
    uz_Latn: 'Juda köp uriniş böldi. Bir soatdan keyin qayta urinib köring.',
    ru: 'Слишком много попыток. Повторите через час.',
  },
  DEVICE_DENIED_24H: {
    uz_Cyrl: 'Бу қурилмадан кириш ҳисоб эгаси томонидан рад этилди. 24 соатдан кейин уриниб кўринг ёки операторга мурожаат қилинг.',
    uz_Latn: 'Bu qurilmadan kiriş hisob egasi tomonidan rad etildi. 24 soatdan keyin urinib köring yoki operatorga murojaat qiling.',
    ru: 'Вход с этого устройства отклонён владельцем аккаунта. Повторите через 24 часа или обратитесь к оператору.',
  },
  ADMIN_REVIEW_LIMIT: {
    uz_Cyrl: 'Бугунги сўровлар лимити тугади. Эртага қайта уриниб кўринг ёки операторга мурожаат қилинг.',
    uz_Latn: 'Bugungi sörovlar limiti tugadi. Ertaga qayta urinib köring yoki operatorga murojaat qiling.',
    ru: 'Лимит запросов на сегодня исчерпан. Повторите завтра или обратитесь к оператору.',
  },
  PHONE_NOT_BOUND: {
    uz_Cyrl: 'Бу рақамда тасдиқлайдиган қурилма йўқ. «Эски телефоним йўқ» орқали администраторга сўров юборинг.',
    uz_Latn: 'Bu raqamda tasdiqlaydigan qurilma yöq. «Eski telefonim yöq» orqali administratorga sörov yuboring.',
    ru: 'У этого номера нет устройства для подтверждения. Отправьте запрос администратору через «Старого телефона нет».',
  },
  DEVICE_NOT_BOUND: {
    uz_Cyrl: 'Фақат рақам боғланган (асосий) телефондан тасдиқлаш мумкин.',
    uz_Latn: 'Faqat raqam boğlangan (asosiy) telefondan tasdiqlaş mumkin.',
    ru: 'Подтвердить можно только с основного телефона, к которому привязан номер.',
  },
  ENDPOINT_RETIRED: {
    uz_Cyrl: 'Бу йўл ёпилган. Иловани янгиланг.',
    uz_Latn: 'Bu yöl yopilgan. Ilovani yangilang.',
    ru: 'Этот способ отключён. Обновите приложение.',
  },
  DEVICE_TRUST_LIMITED: {
    uz_Cyrl: 'Янги қурилма тасдиқланганига 24 соат бўлмади: пул ечиш ва ўтказмалар вақтинча ёпиқ.',
    uz_Latn: 'Yangi qurilma tasdiqlanganiga 24 soat bölmadi: pul yeçiş va ötkazmalar vaqtinça yopiq.',
    ru: 'С подтверждения нового устройства не прошло 24 часа: вывод и переводы денег временно закрыты.',
  },
  ADMIN_TARGET_NEEDS_SUPERADMIN: {
    uz_Cyrl: 'Бу рақам администраторники — фақат superadmin тасдиқлайди.',
    uz_Latn: 'Bu raqam administratorniki — faqat superadmin tasdiqlaydi.',
    ru: 'Это номер администратора — подтвердить может только superadmin.',
  },
  REQUEST_NOT_PENDING: {
    uz_Cyrl: 'Сўров аллақачон кўриб чиқилган ёки муддати тугаган.',
    uz_Latn: 'Sörov allaqaçon körib çiqilgan yoki muddati tugagan.',
    ru: 'Запрос уже рассмотрен или истёк.',
  },
});

function messagesFor(code) {
  return MESSAGES[code] || MESSAGES.REQUEST_NOT_PENDING;
}

function secError(functions, httpsCode, code, extra = {}) {
  return new functions.https.HttpsError(httpsCode, code, {
    code,
    messages: messagesFor(code),
    ...extra,
  });
}

// ── Sof yordamchilar ─────────────────────────────────────────────────────

function isPrivilegedRole(role) {
  return PANEL_ROLES.includes(String(role || '').trim().toLowerCase());
}

/** Avto-tasdiq faqat favqulodda kod bayrog'i + sozlama + imtiyozsiz raqam bo'lsa. */
function shouldHonorAutoApprove({
  settingEnabled,
  privileged,
  emergency = DEVICE_SEC.EMERGENCY_HONOR_AUTO_APPROVE,
}) {
  return emergency === true && settingEnabled === true && privileged !== true;
}

/** Klient yuborgan fingerprint xaritasi: ≤16 kalit, qiymat ≤256 belgi (saqlash uchun). */
function cleanFingerprint(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
  const out = {};
  let n = 0;
  for (const [k, v] of Object.entries(raw)) {
    if (n >= 16) break;
    const key = String(k || '').trim();
    if (!key || key.length > 40) continue;
    const val = String(v == null ? '' : v).trim();
    if (val.length > 256) continue;
    out[key] = val;
    n += 1;
  }
  return out;
}

const fpStr = (m, k) => String((m && m[k]) == null ? '' : m[k]).trim();

/**
 * Bir xil o'rnatma (OS yangilanishi `Build.fingerprint`ni o'zgartirib hash «siljiganda»):
 * Android/iOS, bir xil Firebase Installation ID (o'rnatma) + bir xil apparat ID + model/brend.
 * Web hech qachon mos kelmaydi (androidId yo'q, FID brauzer profiliga bog'liq).
 */
function sameInstall(stored, current) {
  const platform = fpStr(current, 'platform').toLowerCase();
  if (platform !== 'android' && platform !== 'ios') return false;
  const storedPlatform = fpStr(stored, 'platform').toLowerCase();
  if (storedPlatform && storedPlatform !== platform) return false;
  const fidA = fpStr(stored, 'firebaseInstallationId');
  if (fidA.length < 10 || fidA !== fpStr(current, 'firebaseInstallationId')) return false;
  const hwKey = platform === 'android' ? 'androidId' : 'hardwareId';
  const hwA = fpStr(stored, hwKey);
  if (hwA.length < 6 || hwA !== fpStr(current, hwKey)) return false;
  return fpStr(stored, 'model') === fpStr(current, 'model')
    && fpStr(stored, 'brand') === fpStr(current, 'brand');
}

function hashPrefix(hash) {
  return String(hash || '').slice(0, 12);
}

function platformOf(fp) {
  const p = fpStr(fp, 'platform').toLowerCase();
  return ['android', 'ios', 'web'].includes(p) ? p : (p ? 'other' : '');
}

/** «Samsung SM-A515F», «Web · chrome · Win32». */
function deviceLabelOf(fp) {
  const platform = platformOf(fp);
  if (platform === 'web') {
    return ['Web', fpStr(fp, 'device'), fpStr(fp, 'product')].filter(Boolean).join(' · ').slice(0, 80);
  }
  return [fpStr(fp, 'brand'), fpStr(fp, 'model')].filter(Boolean).join(' ').slice(0, 80);
}

function clientIpOf(context) {
  const req = context && context.rawRequest;
  if (!req) return '';
  const xff = String((req.headers || {})['x-forwarded-for'] || '').split(',')[0].trim();
  return xff || String(req.ip || '').trim();
}

/** IP xom saqlanmaydi (§40) — tuzli SHA-256 prefiksi. */
function ipKeyOf(context) {
  const ip = clientIpOf(context);
  if (!ip) return '';
  return crypto.createHash('sha256').update(`ava-devsec-v1|${ip}`).digest('hex').slice(0, 24);
}

/**
 * Taxminiy shahar — Google Front End sarlavhasi bo'lsa (Cloud Functions gen1'da borligi
 * UNKNOWN: bo'lmasa bo'sh qoladi, hech narsa buzilmaydi).
 */
function approxCityOf(context) {
  const h = (context && context.rawRequest && context.rawRequest.headers) || {};
  const c = String(h['x-appengine-city'] || '').trim();
  if (!c || c === '?' || c.length > 60) return '';
  return c.replace(/\b\w/g, (ch) => ch.toUpperCase());
}

/** Bir soatlik oyna hisoblagichi (sof). */
function rateStep(doc, nowMs, windowMs, limit) {
  const start = Number(doc && doc.windowStartMs) || 0;
  const count = Number(doc && doc.count) || 0;
  if (!start || nowMs - start >= windowMs) {
    return { allowed: true, next: { windowStartMs: nowMs, count: 1 }, retryAfterMs: 0 };
  }
  if (count >= limit) {
    return { allowed: false, next: null, retryAfterMs: Math.max(0, start + windowMs - nowMs) };
  }
  return { allowed: true, next: { windowStartMs: start, count: count + 1 }, retryAfterMs: 0 };
}

/**
 * Admin qaror qila oladimi: so'rov oxirgi 72 soatda yaratilgan va hali hal qilinmagan
 * (`pending` / `expired` / `cancelled`). Muddati o'tgan peer so'rov ham — eski APK foydalanuvchisi
 * operatorga murojaat qilganda (ega 2026-11-28). `approved`/`rejected`/`approving` — yo'q.
 */
function adminDecidable(req, nowMs) {
  const r = req || {};
  if (!['pending', 'expired', 'cancelled'].includes(String(r.status || ''))) return false;
  const c = r.createdAt;
  const createdMs = c && typeof c.toMillis === 'function' ? c.toMillis() : 0;
  return createdMs > 0 && createdMs >= nowMs - DEVICE_SEC.ADMIN_REVIEW_TTL_MS;
}

function denialDocId(phone, hash) {
  return `${phone}__${String(hash || '').toLowerCase()}`;
}

function tashkentTime(ms) {
  try {
    return new Date(ms).toLocaleString('ru-RU', {
      timeZone: 'Asia/Tashkent', hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit',
    });
  } catch (_) {
    return '';
  }
}

function clip(s, n) {
  return String(s == null ? '' : s).trim().slice(0, n);
}

/** Hisob egasiga xabarlar (3 til). `title/body` — uz_Cyrl (push), `i18n` — news hujjatida. */
function texts(kind, { label = '', city = '', at = '' } = {}) {
  const dev = label || '';
  const where = city ? ` · ${city}` : '';
  const when = at ? ` · ${at}` : '';
  const meta = `${dev}${where}${when}`.replace(/^ · /, '');
  const T = {
    attempt: {
      uz_Cyrl: ['🔐 Янги қурилмадан кириш уриниши', `Рақамингиз билан янги қурилмадан киришга уринилди${meta ? ` (${meta})` : ''}. Тасдиқсиз кира олмайди. Сиз бўлмасангиз — ҳеч нарса қилманг.`],
      uz_Latn: ['🔐 Yangi qurilmadan kiriş urinişi', `Raqamingiz bilan yangi qurilmadan kirişga urinildi${meta ? ` (${meta})` : ''}. Tasdiqsiz kira olmaydi. Siz bölmasangiz — heç narsa qilmang.`],
      ru: ['🔐 Попытка входа с нового устройства', `С вашим номером пытались войти с нового устройства${meta ? ` (${meta})` : ''}. Без подтверждения вход невозможен. Если это не вы — ничего не делайте.`],
    },
    prompt: {
      uz_Cyrl: ['🔐 Бу сизми?', `Янги қурилма${meta ? ` (${meta})` : ''} рақамингиз билан киришни сўрамоқда. «Ҳа» ёки «Йўқ» ни танланг. Ойна очилмаса — иловани янгиланг: ${DEVICE_SEC.PLAY_URL}`],
      uz_Latn: ['🔐 Bu sizmi?', `Yangi qurilma${meta ? ` (${meta})` : ''} raqamingiz bilan kirişni söramoqda. «Ha» yoki «Yöq» ni tanlang. Oyna oçilmasa — ilovani yangilang: ${DEVICE_SEC.PLAY_URL}`],
      ru: ['🔐 Это вы?', `Новое устройство${meta ? ` (${meta})` : ''} запрашивает вход с вашим номером. Выберите «Да» или «Нет». Если окно не открылось — обновите приложение: ${DEVICE_SEC.PLAY_URL}`],
    },
    admin_review_requested: {
      uz_Cyrl: ['🔐 Янги қурилма учун администратор тасдиғи сўралди', `Рақамингиз учун янги қурилмадан${meta ? ` (${meta})` : ''} администраторга сўров юборилди. Сиз бўлмасангиз — шу телефонда «Йўқ» ни босинг.`],
      uz_Latn: ['🔐 Yangi qurilma uçun administrator tasdiği söraldi', `Raqamingiz uçun yangi qurilmadan${meta ? ` (${meta})` : ''} administratorga sörov yuborildi. Siz bölmasangiz — şu telefonda «Yöq» ni bosing.`],
      ru: ['🔐 Запрошено подтверждение администратора', `Для вашего номера с нового устройства${meta ? ` (${meta})` : ''} отправлен запрос администратору. Если это не вы — нажмите «Нет» на этом телефоне.`],
    },
    approved: {
      uz_Cyrl: ['✅ Янги қурилма тасдиқланди', `Янги қурилма${meta ? ` (${meta})` : ''} ҳисобингизга уланди. 24 соат пул ечиш ва ўтказмалар ёпиқ.`],
      uz_Latn: ['✅ Yangi qurilma tasdiqlandi', `Yangi qurilma${meta ? ` (${meta})` : ''} hisobingizga ulandi. 24 soat pul yeçiş va ötkazmalar yopiq.`],
      ru: ['✅ Новое устройство подтверждено', `Новое устройство${meta ? ` (${meta})` : ''} подключено к аккаунту. 24 часа вывод и переводы денег закрыты.`],
    },
  };
  const t = T[kind] || T.attempt;
  const i18n = {};
  for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) i18n[l] = { title: t[l][0], body: t[l][1] };
  return { title: t.uz_Cyrl[0], body: t.uz_Cyrl[1], i18n };
}

// ── Firestore / Auth yordamchilari ───────────────────────────────────────

function makeDeviceSecurity({ db, admin, functions, canonicalUid, notifyUserInApp }) {
  const ts = () => admin.firestore.FieldValue.serverTimestamp();

  function eventDoc(e) {
    const out = {
      phone: clip(e.phone, 15),
      action: clip(e.action || 'bind', 40),
      result: clip(e.result || 'ok', 40),
    };
    if (e.method) out.method = clip(e.method, 40);
    if (e.hash) out.hashPrefix = hashPrefix(e.hash);
    if (e.prevHash) out.prevHashPrefix = hashPrefix(e.prevHash);
    if (e.prevPhone) out.prevPhone = clip(e.prevPhone, 15);
    if (e.platform) out.platform = clip(e.platform, 10);
    if (e.label) out.label = clip(e.label, 80);
    if (e.ipKey) out.ipKey = clip(e.ipKey, 24);
    if (e.city) out.city = clip(e.city, 60);
    if (e.requestId) out.requestId = clip(e.requestId, 64);
    if (e.channel) out.channel = clip(e.channel, 20);
    if (e.actor) out.actor = clip(e.actor, 40);
    if (e.note) out.note = clip(e.note, DEVICE_SEC.NOTE_MAX);
    if (typeof e.revoked === 'boolean') out.revoked = e.revoked;
    return out;
  }

  async function logEvent(e) {
    try {
      await db.collection(COL.EVENTS).add({ ...eventDoc(e), at: ts() });
    } catch (err) {
      console.error(JSON.stringify({ action: 'device_event_write_failed', err: String(err && err.message) }));
    }
  }

  function logEventInTx(tx, e) {
    tx.set(db.collection(COL.EVENTS).doc(), { ...eventDoc(e), at: ts() });
  }

  async function enforceRateLimits({ phone, hash, ipKey, nowMs = Date.now() }) {
    const specs = [
      { id: `p_${phone}`, limit: DEVICE_SEC.RATE_MAX_PER_PHONE },
      { id: `h_${hash}`, limit: DEVICE_SEC.RATE_MAX_PER_DEVICE },
    ];
    if (ipKey) specs.push({ id: `i_${ipKey}`, limit: DEVICE_SEC.RATE_MAX_PER_IP });
    const refs = specs.map((s) => db.collection(COL.RATE).doc(s.id));
    const res = await db.runTransaction(async (tx) => {
      const snaps = await tx.getAll(...refs);
      const steps = snaps.map((s, i) => rateStep(
        s.exists ? s.data() : null, nowMs, DEVICE_SEC.RATE_WINDOW_MS, specs[i].limit));
      const denied = steps.filter((s) => !s.allowed);
      if (denied.length) {
        return { allowed: false, retryAfterMs: Math.max(...denied.map((s) => s.retryAfterMs)) };
      }
      steps.forEach((s, i) => tx.set(refs[i], {
        ...s.next,
        updatedAt: ts(),
        expireAt: admin.firestore.Timestamp.fromMillis(nowMs + 2 * DEVICE_SEC.RATE_WINDOW_MS),
      }));
      return { allowed: true };
    });
    if (!res.allowed) {
      console.warn(JSON.stringify({
        action: 'device_binding_rate_limited', phoneTail: String(phone).slice(-4),
        retryAfterMs: res.retryAfterMs,
      }));
      throw secError(functions, 'resource-exhausted', 'DEVICE_BINDING_RATE_LIMITED',
        { retryAfterMs: res.retryAfterMs });
    }
  }

  async function getDenial(phone, hash, nowMs = Date.now()) {
    const snap = await db.collection(COL.DENIALS).doc(denialDocId(phone, hash)).get();
    if (!snap.exists) return { blocked: false, untilMs: 0 };
    const until = snap.data().blockedUntil;
    const untilMs = until && typeof until.toMillis === 'function' ? until.toMillis() : 0;
    return { blocked: untilMs > nowMs, untilMs };
  }

  async function setDenial({ phone, hash, reason, requestId, nowMs = Date.now() }) {
    const untilMs = nowMs + DEVICE_SEC.DENIAL_MS;
    await db.collection(COL.DENIALS).doc(denialDocId(phone, hash)).set({
      phone,
      hashPrefix: hashPrefix(hash),
      reason: clip(reason, 40),
      requestId: clip(requestId, 64),
      blockedUntil: admin.firestore.Timestamp.fromMillis(untilMs),
      createdAt: ts(),
    });
    return untilMs;
  }

  async function userDocOf(phone) {
    const p = canonicalUid(phone);
    for (const id of [p, p.length === 12 ? p.slice(3) : '']) {
      if (!id) continue;
      const snap = await db.collection('users').doc(id).get();
      if (snap.exists) return snap;
    }
    return null;
  }

  async function roleOf(phone) {
    const snap = await userDocOf(phone);
    return snap ? String((snap.data() || {}).role || 'user') : '';
  }

  async function isPrivilegedPhone(phone) {
    return isPrivilegedRole(await roleOf(phone));
  }

  /** Raqamda hisob bormi (Firestore `users` yoki Firebase Auth). Xatoda — «bor» (fail closed). */
  async function accountExists(phone) {
    if (await userDocOf(phone)) return true;
    try {
      await admin.auth().getUserByPhoneNumber(`+${canonicalUid(phone)}`);
      return true;
    } catch (e) {
      if (e && (e.code === 'auth/user-not-found' || (e.errorInfo && e.errorInfo.code === 'auth/user-not-found'))) {
        return false;
      }
      console.error(JSON.stringify({ action: 'account_exists_lookup_failed', err: String(e && e.message) }));
      return true;
    }
  }

  async function notifyAccount(phone, kind, meta, extra = {}) {
    const t = texts(kind, meta);
    try {
      await notifyUserInApp({
        userId: phone,
        title: t.title,
        body: t.body,
        category: 'security',
        source: extra.source || 'device_security',
        dataType: extra.dataType || 'device_security',
        screen: extra.screen || 'news',
        extraNews: { i18n: t.i18n, ...(extra.extraNews || {}) },
        extraData: extra.extraData || {},
      });
    } catch (e) {
      console.error(JSON.stringify({ action: 'device_notify_failed', kind, err: String(e && e.message) }));
    }
  }

  /** «Янги қурилмадан уриниш» — 15 daqiqada ko'pi bilan 1 marta. */
  async function notifyAttempt({ phone, label, city, nowMs = Date.now() }) {
    const ref = db.collection(COL.RATE).doc(`n_${phone}`);
    const send = await db.runTransaction(async (tx) => {
      const s = await tx.get(ref);
      const last = s.exists ? Number(s.data().lastMs) || 0 : 0;
      if (last && nowMs - last < DEVICE_SEC.ATTEMPT_NOTIFY_THROTTLE_MS) return false;
      tx.set(ref, {
        lastMs: nowMs,
        updatedAt: ts(),
        expireAt: admin.firestore.Timestamp.fromMillis(nowMs + 2 * DEVICE_SEC.ATTEMPT_NOTIFY_THROTTLE_MS),
      });
      return true;
    });
    if (!send) return false;
    await notifyAccount(phone, 'attempt', { label, city, at: tashkentTime(nowMs) },
      { dataType: 'device_login_attempt' });
    return true;
  }

  async function alertAdmins({ title, body, extraData = {} }) {
    try {
      const snap = await db.collection('users')
        .where('role', 'in', DEVICE_SEC.ADMIN_ALERT_ROLES)
        .limit(DEVICE_SEC.ADMIN_ALERT_MAX)
        .get();
      await Promise.all(snap.docs.map((d) => notifyUserInApp({
        userId: d.id,
        title,
        body,
        category: 'admin_security',
        source: 'device_security_admin',
        dataType: 'device_security_admin',
        screen: 'news',
        extraData,
      }).catch(() => {})));
      return snap.size;
    } catch (e) {
      console.error(JSON.stringify({ action: 'device_admin_alert_failed', err: String(e && e.message) }));
      return 0;
    }
  }

  async function markTrustLimited(phone, reason, nowMs = Date.now()) {
    const untilMs = nowMs + DEVICE_SEC.TRUST_LIMITED_MS;
    await db.collection('users').doc(canonicalUid(phone)).set({
      security: {
        deviceTrustMode: 'limited',
        deviceTrustUntil: admin.firestore.Timestamp.fromMillis(untilMs),
        deviceTrustReason: clip(reason, 40),
        deviceTrustUpdatedAt: ts(),
      },
      updatedAt: ts(),
    }, { merge: true });
    return untilMs;
  }

  /** Hisobning barcha refresh token'lari bekor (bog'langan qurilma o'z bog'lanishi bilan jim qayta kiradi). */
  async function revokeAccountSessions(phone) {
    try {
      const u = await admin.auth().getUserByPhoneNumber(`+${canonicalUid(phone)}`);
      await admin.auth().revokeRefreshTokens(u.uid);
      return true;
    } catch (e) {
      console.error(JSON.stringify({ action: 'device_revoke_failed', err: String(e && e.message) }));
      return false;
    }
  }

  /** Imtiyozli raqam (panel roli) — faqat superadmin tasdiqlaydi. */
  async function assertCanApproveFor({ callerUid, targetPhone, storedPrivileged = false }) {
    const privileged = storedPrivileged === true || await isPrivilegedPhone(targetPhone);
    if (!privileged) return { privileged: false };
    const callerRole = String(await roleOf(callerUid)).toLowerCase();
    if (callerRole !== 'superadmin') {
      throw secError(functions, 'permission-denied', 'ADMIN_TARGET_NEEDS_SUPERADMIN');
    }
    return { privileged: true };
  }

  return {
    eventDoc,
    logEvent,
    logEventInTx,
    enforceRateLimits,
    getDenial,
    setDenial,
    roleOf,
    isPrivilegedPhone,
    accountExists,
    notifyAccount,
    notifyAttempt,
    alertAdmins,
    markTrustLimited,
    revokeAccountSessions,
    assertCanApproveFor,
  };
}

// ── Yangi callable'lar ───────────────────────────────────────────────────

function attachDeviceSecurity(exports, deps) {
  const {
    functions,
    authFunctions,
    db,
    admin,
    canonicalUid,
    requireCallerRoles,
    isValidFingerprintHash,
    forceDeviceBindingLink,
    oldDeviceLabelFromBinding,
    sec,
  } = deps;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const toMs = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : 0);

  /**
   * «Эски телефоним йўқ»: yangi qurilma admin ko'rigini so'raydi (auth yo'q — hali sessiya yo'q).
   * Bir (raqam, qurilma) uchun bitta faol so'rov (qayta chaqiruv o'shani qaytaradi — idempotent).
   */
  exports.requestDeviceAdminReview = authFunctions
    .runWith({ timeoutSeconds: 60, memory: '256MB' })
    .https.onCall(async (data, context) => {
      const phone = canonicalUid((data && data.phone) || '');
      const toHash = String((data && data.deviceFingerprintHash) || '').trim().toLowerCase();
      const fingerprint = cleanFingerprint(data && data.fingerprint);
      const note = clip(data && data.note, DEVICE_SEC.NOTE_MAX);
      if (phone.length < 12) {
        throw new functions.https.HttpsError('invalid-argument', 'Telefon raqami noto\'g\'ri');
      }
      if (!isValidFingerprintHash(toHash)) {
        throw new functions.https.HttpsError('invalid-argument', 'deviceFingerprintHash noto\'g\'ri');
      }
      const ipKey = ipKeyOf(context);
      const city = approxCityOf(context);

      const bindingSnap = await db.collection('device_bindings').doc(toHash).get();
      if (bindingSnap.exists && canonicalUid(bindingSnap.data().phone || '') === phone) {
        return { status: 'already_bound' };
      }
      const denial = await sec.getDenial(phone, toHash);
      if (denial.blocked) {
        throw secError(functions, 'failed-precondition', 'DEVICE_DENIED_24H', { untilMs: denial.untilMs });
      }

      const dayAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
      const recent = await db.collection(COL.REQUESTS)
        .where('phone', '==', phone)
        .where('createdAt', '>=', dayAgo)
        .limit(30)
        .get();
      const mine = recent.docs.filter((d) => (d.data() || {}).channel === CHANNEL_ADMIN);
      const existing = mine.find((d) => {
        const x = d.data() || {};
        return x.status === 'pending' && x.toHash === toHash && toMs(x.expiresAt) > Date.now();
      });
      if (existing) {
        const x = existing.data();
        return {
          status: 'pending', requestId: existing.id, channel: CHANNEL_ADMIN,
          expiresAtMs: toMs(x.expiresAt), oldDeviceLabel: String(x.oldDeviceLabel || ''),
        };
      }
      if (mine.length >= DEVICE_SEC.ADMIN_REVIEW_MAX_PER_DAY) {
        throw secError(functions, 'resource-exhausted', 'ADMIN_REVIEW_LIMIT');
      }
      await sec.enforceRateLimits({ phone, hash: toHash, ipKey });

      const aliasSnap = await db.collection('device_aliases').doc(phone).get();
      const fromHash = aliasSnap.exists
        ? String(aliasSnap.data().deviceFingerprintHash || '').toLowerCase()
        : '';
      let oldDeviceLabel = '';
      if (isValidFingerprintHash(fromHash)) {
        try {
          const ob = await db.collection('device_bindings').doc(fromHash).get();
          if (ob.exists) oldDeviceLabel = oldDeviceLabelFromBinding(ob.data());
        } catch (_) { /* ixtiyoriy */ }
      }
      const privileged = await sec.isPrivilegedPhone(phone);
      const label = deviceLabelOf(fingerprint);
      const platform = platformOf(fingerprint);
      const expiresAtMs = Date.now() + DEVICE_SEC.ADMIN_REVIEW_TTL_MS;

      const batch = db.batch();
      for (const d of mine) {
        if ((d.data() || {}).status === 'pending') {
          batch.set(d.ref, { status: 'cancelled', updatedAt: ts() }, { merge: true });
        }
      }
      const ref = db.collection(COL.REQUESTS).doc();
      batch.set(ref, {
        phone,
        fromHash: isValidFingerprintHash(fromHash) ? fromHash : '',
        toHash,
        toFingerprint: fingerprint,
        newDeviceLabel: label,
        oldDeviceLabel,
        platform,
        approxCity: city,
        ipKey,
        note,
        privileged,
        status: 'pending',
        channel: CHANNEL_ADMIN,
        createdAt: ts(),
        updatedAt: ts(),
        expiresAt: admin.firestore.Timestamp.fromMillis(expiresAtMs),
      });
      await batch.commit();

      await sec.logEvent({
        phone, action: 'admin_review_requested', result: 'pending', hash: toHash, platform, label,
        ipKey, city, requestId: ref.id, channel: CHANNEL_ADMIN, actor: 'new_device',
      });
      if (isValidFingerprintHash(fromHash)) {
        await sec.notifyAccount(phone, 'admin_review_requested',
          { label, city, at: tashkentTime(Date.now()) },
          {
            source: 'device_transfer', dataType: 'device_transfer_request', screen: 'device_transfer',
            extraNews: { requestId: ref.id }, extraData: { requestId: ref.id, newDeviceLabel: label },
          });
      }
      await sec.alertAdmins({
        title: '🔐 Қурилма тасдиғи сўрови',
        body: `${privileged ? 'АДМИН РАҚАМИ · ' : ''}${label || 'Янги қурилма'} · …${phone.slice(-4)} — «Қурилма тасдиқлари»`,
        extraData: { kind: 'device_admin_review', requestId: ref.id },
      });
      console.log(JSON.stringify({ action: 'admin_review_requested', requestId: ref.id, phoneTail: phone.slice(-4) }));
      return { status: 'pending', requestId: ref.id, channel: CHANNEL_ADMIN, expiresAtMs, oldDeviceLabel };
    });

  /**
   * Admin: ko'rik so'rovlari ro'yxati (`admin`/`superadmin`).
   * `phone` berilsa — shu raqamning oxirgi 72 soatdagi BARCHA so'rovlari (har ikki kanal):
   * eski APK'da «Эски телефоним йўқ» tugmasi yo'q — foydalanuvchi operatorga qo'ng'iroq qilganda
   * admin uning «eski qurilmadan tasdiqlash» so'rovini topib, shu yerdan tasdiqlaydi.
   */
  exports.adminListDeviceApprovals = authFunctions
    .runWith({ timeoutSeconds: 60, memory: '256MB' })
    .https.onCall(async (data, context) => {
      const callerUid = await requireCallerRoles(context, DEVICE_SEC.DECIDER_ROLES, 'Admin only');
      const status = ['pending', 'approved', 'rejected'].includes(String((data && data.status) || ''))
        ? String(data.status)
        : 'pending';
      const searchPhone = canonicalUid((data && data.phone) || '');
      const now = Date.now();
      let docs;
      if (searchPhone.length >= 12) {
        const s = await db.collection(COL.REQUESTS).where('phone', '==', searchPhone).limit(30).get();
        docs = s.docs.filter((d) => toMs((d.data() || {}).createdAt) >= now - DEVICE_SEC.ADMIN_REVIEW_TTL_MS);
      } else {
        const s = await db.collection(COL.REQUESTS)
          .where('channel', '==', CHANNEL_ADMIN)
          .where('status', '==', status)
          .limit(100)
          .get();
        docs = s.docs;
      }
      const callerRole = String(await sec.roleOf(callerUid)).toLowerCase();
      const items = [];
      for (const d of docs) {
        const x = d.data() || {};
        const expiresAtMs = toMs(x.expiresAt);
        if (!searchPhone && status === 'pending' && expiresAtMs && expiresAtMs <= now) continue;
        const userSnap = await db.collection('users').doc(String(x.phone || '')).get();
        const u = userSnap.exists ? (userSnap.data() || {}) : {};
        const privileged = x.privileged === true || isPrivilegedRole(u.role);
        items.push({
          requestId: d.id,
          phone: String(x.phone || ''),
          name: clip(u.name || u.fullName || '', 80),
          role: String(u.role || ''),
          accountExists: userSnap.exists,
          newDeviceLabel: String(x.newDeviceLabel || ''),
          oldDeviceLabel: String(x.oldDeviceLabel || ''),
          platform: String(x.platform || ''),
          approxCity: String(x.approxCity || ''),
          note: String(x.note || ''),
          privileged,
          canDecide: !privileged || callerRole === 'superadmin',
          hasBoundDevice: !!x.fromHash,
          createdAtMs: toMs(x.createdAt),
          expiresAtMs,
          status: String(x.status || ''),
          channel: String(x.channel || CHANNEL_PEER),
          decidable: adminDecidable(x, now),
        });
      }
      items.sort((a, b) => b.createdAtMs - a.createdAtMs);
      return { items };
    });

  /** Admin: tasdiqlash / rad etish (audit bilan). Imtiyozli raqam — faqat superadmin. */
  exports.adminDecideDeviceApproval = authFunctions
    .runWith({ timeoutSeconds: 60, memory: '256MB' })
    .https.onCall(async (data, context) => {
      const callerUid = await requireCallerRoles(context, DEVICE_SEC.DECIDER_ROLES, 'Admin only');
      const requestId = clip(data && data.requestId, 64);
      const approve = data && data.approve === true;
      const note = clip(data && data.note, DEVICE_SEC.NOTE_MAX);
      const identityCheck = clip(data && data.identityCheck, DEVICE_SEC.NOTE_MAX);
      if (!requestId) throw new functions.https.HttpsError('invalid-argument', 'requestId');
      const ref = db.collection(COL.REQUESTS).doc(requestId);
      const pre = await ref.get();
      if (!pre.exists) {
        throw new functions.https.HttpsError('not-found', 'So\'rov topilmadi');
      }
      const req0 = pre.data() || {};
      const phone = canonicalUid(req0.phone || '');
      const channel = String(req0.channel || CHANNEL_PEER);
      await sec.assertCanApproveFor({ callerUid, targetPhone: phone, storedPrivileged: req0.privileged === true });
      if (approve) {
        const denial = await sec.getDenial(phone, String(req0.toHash || ''));
        if (denial.blocked) {
          throw secError(functions, 'failed-precondition', 'DEVICE_DENIED_24H', { untilMs: denial.untilMs });
        }
      }

      const claim = await db.runTransaction(async (tx) => {
        const s = await tx.get(ref);
        const r = s.data() || {};
        if (!adminDecidable(r, Date.now())) return { ok: false, status: String(r.status || '') };
        tx.set(ref, {
          status: approve ? 'approving' : 'rejected',
          decidedBy: 'admin',
          decidedAt: ts(),
          updatedAt: ts(),
        }, { merge: true });
        return { ok: true };
      });
      if (!claim.ok) {
        throw secError(functions, 'failed-precondition', 'REQUEST_NOT_PENDING', { status: claim.status });
      }

      const auditBase = {
        actor: callerUid, target: phone, requestId,
        note, identityCheck, at: ts(),
      };
      if (!approve) {
        await sec.logEvent({
          phone, action: 'admin_rejected', result: 'rejected', hash: req0.toHash, requestId,
          channel, actor: `admin:${callerUid}`, note: [note, identityCheck].filter(Boolean).join(' | '),
        });
        await db.collection('admin_audit').add({ kind: 'device_approval_rejected', ...auditBase });
        return { status: 'rejected', requestId };
      }

      const toHash = String(req0.toHash || '').toLowerCase();
      try {
        await forceDeviceBindingLink({
          hash: toHash,
          phone,
          verifiedMethod: 'admin_review',
          fingerprint: cleanFingerprint(req0.toFingerprint),
          event: {
            action: 'admin_approved', requestId, channel, actor: `admin:${callerUid}`,
            label: req0.newDeviceLabel, platform: req0.platform,
            note: [note, identityCheck].filter(Boolean).join(' | '),
          },
        });
      } catch (e) {
        await ref.set({ status: 'pending', updatedAt: ts() }, { merge: true });
        console.error(JSON.stringify({ action: 'admin_device_approve_failed', requestId, err: String(e && e.message) }));
        throw new functions.https.HttpsError('internal', 'DEVICE_APPROVE_FAILED');
      }
      const limitedUntilMs = await sec.markTrustLimited(phone, 'admin_review');
      await ref.set({
        status: 'approved',
        limitedUntil: admin.firestore.Timestamp.fromMillis(limitedUntilMs),
        updatedAt: ts(),
      }, { merge: true });
      await db.collection('admin_audit').add({ kind: 'device_approval_approved', ...auditBase });
      await sec.notifyAccount(phone, 'approved', { label: req0.newDeviceLabel, at: tashkentTime(Date.now()) },
        { dataType: 'device_approved' });
      return { status: 'approved', requestId, limitedUntilMs };
    });
}

module.exports = {
  DEVICE_SEC,
  COL,
  CHANNEL_PEER,
  CHANNEL_ADMIN,
  MESSAGES,
  messagesFor,
  secError,
  isPrivilegedRole,
  shouldHonorAutoApprove,
  cleanFingerprint,
  sameInstall,
  hashPrefix,
  platformOf,
  deviceLabelOf,
  ipKeyOf,
  approxCityOf,
  rateStep,
  adminDecidable,
  denialDocId,
  tashkentTime,
  texts,
  makeDeviceSecurity,
  attachDeviceSecurity,
};
