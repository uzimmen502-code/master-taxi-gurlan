/**
 * Kompyuterda QR orqali kirish — WhatsApp Web uslubi (ega 2026-11-28, 10-band).
 *
 * Nega: hamkorlar (ulgurji sotuvchilar) mahsulotni kompyuterdan qo'shishi kerak. Oddiy web kirish
 * (telefon + brauzer fingerprint) mavjud hisobda «Бу сизми?» orqali bog'lanishni BRAUZERGA KO'CHIRADI
 * (telefon bog'lanishdan chiqadi). QR kirish telefon bog'lanishiga TEGMAYDI — alohida web sessiya.
 *
 * Oqim:
 *  1. Web `qrLoginStart` (auth yo'q) → {sid, secret, watchId, expiresAtMs, qrPayload}. QR'da faqat `sid`.
 *     `secret` va `watchId` faqat shu brauzerda (QR'da YO'Q).
 *  2. Web `qr_login_watch/{watchId}` hujjatini tinglaydi (rules: faqat `get`, `list` yo'q; watchId —
 *     256 bit tasodifiy = «sirni bilgan o'qiydi»). Hujjatda faqat {status, expiresAt} — PII/token YO'Q.
 *  3. Bog'langan telefon (auth + joriy alias qurilmasi) QR'ni skanerlaydi → `qrLoginPeek` (pending →
 *     scanned, egasi = shu telefon) → «Компьютерда киришни тасдиқлайсизми?» → `qrLoginApprove`.
 *  4. Web status `approved` ni ko'radi → `qrLoginConsume({sid, secret})` — bir martalik, tranzaksiyada
 *     approved → consumed + `qr_web_sessions/{wsid}` (active) + custom token (faqat javobda).
 *  5. Web sessiya `renewSecret` bilan jim yangilanadi (`qrWebSessionRenew`) — refresh token'lar bekor
 *     qilinganda (telefondan «Чиқиш»). Telefondan «Чиқиш» → sessiya revoked + hisob refresh token'lari
 *     bekor (telefon o'zi darhol qayta kiradi; boshqa faol web sessiyalar renewSecret bilan tiklanadi,
 *     revoked sessiya tiklana olmaydi).
 *
 * Holatlar (yagona manba — QR_STATES / canTransitionQr): pending → scanned → approved → consumed;
 * istalgan faol holat → expired; scanned → rejected; pending/scanned → cancelled.
 *
 * Bosqich (42-qoida): `server_config/qr_web_login` {stage: off|internal|public, testerIds}. Hujjat yo'q
 * → OFF. «Чиқиш» va ro'yxat OFF'da ham ishlaydi (xavfsizlik).
 *
 * Audit: `device_binding_events` (mavjud, append-only, faqat server) — action `qr_*`.
 * Rate limit: `device_binding_rate` (mavjud) — `q*_` prefikslari.
 */
'use strict';

const crypto = require('crypto');

const QR_WEB = Object.freeze({
  QR_TTL_MS: 2 * 60 * 1000,
  /** Telefon tasdiqlagach web shu vaqt ichida token olishi kerak. */
  CONSUME_WINDOW_MS: 60 * 1000,
  /** PROPOSED: web sessiyaning eng uzoq umri (keyin qayta QR). */
  SESSION_TTL_MS: 30 * 24 * 60 * 60 * 1000,
  /**
   * Ega 2026-11-28: «битта рақам 1 та компьютер». Yangi consume — oldingi faol web sessiya(lar)
   * shu tranzaksiyada `revoked` (revokedBy `replaced`). Almashtirish (rad etish emas) — PROPOSED.
   */
  MAX_ACTIVE_SESSIONS: 1,
  RATE_WINDOW_MS: 60 * 60 * 1000,
  /** CGNAT: UZ mobil operatorlarida ko'p abonent bitta IP'da; bitta QR sahifasi soatiga ≤6 ta. */
  RATE_START_PER_IP: 120,
  /** Firestore TTL (expireAt) — QR hujjatlari muddatidan shuncha keyin o'chiriladi (TTL siyosati yoqilsa). */
  TTL_GRACE_MS: 24 * 60 * 60 * 1000,
  RATE_CONSUME_PER_IP: 60,
  RATE_APPROVER_PER_PHONE: 20,
  RATE_RENEW_PER_SESSION: 30,
  RATE_RENEW_PER_IP: 120,
  // Ega 2026-11-28: QR tasdig'idan keyin pul chiqimi bloki YO'Q («тасдиқлаяптику ўзи эканлигини»).
  // Telefon bog'lanishidagi yangi qurilma 24 soat qoidasi o'zgarmagan (device_security.js).
  LIST_LIMIT: 20,
});

const QR_COL = Object.freeze({
  SESSIONS: 'qr_login_sessions',
  WATCH: 'qr_login_watch',
  WEB_SESSIONS: 'qr_web_sessions',
  CONFIG: ['server_config', 'qr_web_login'],
});

const QR_STATES = Object.freeze({
  PENDING: 'pending',
  SCANNED: 'scanned',
  APPROVED: 'approved',
  CONSUMED: 'consumed',
  REJECTED: 'rejected',
  EXPIRED: 'expired',
  CANCELLED: 'cancelled',
});

const TRANSITIONS = Object.freeze({
  pending: ['scanned', 'approved', 'rejected', 'expired', 'cancelled'],
  scanned: ['scanned', 'approved', 'rejected', 'expired', 'cancelled'],
  approved: ['consumed', 'expired'],
  consumed: [],
  rejected: [],
  expired: [],
  cancelled: [],
});

const STAGES = Object.freeze(['off', 'internal', 'public']);
const QR_PREFIX = 'AVAQR1:';
const SID_RE = /^[a-f0-9]{32}$/;
const SECRET_RE = /^[a-f0-9]{64}$/;
const WSID_RE = /^[a-f0-9]{32}$/;

const MESSAGES = Object.freeze({
  QR_LOGIN_DISABLED: {
    uz_Cyrl: 'Компьютерда QR орқали кириш ҳозирча ёпиқ.',
    uz_Latn: 'Kompyuterda QR orqali kiriş hozirça yopiq.',
    ru: 'Вход на компьютере по QR пока недоступен.',
  },
  QR_SESSION_INVALID: {
    uz_Cyrl: 'QR код эскирган ёки нотўғри. Компьютердаги янги QR кодни сканерланг.',
    uz_Latn: 'QR kod eskirgan yoki notöğri. Kompyuterdagi yangi QR kodni skanerlang.',
    ru: 'QR-код устарел или неверный. Отсканируйте новый QR-код на компьютере.',
  },
  QR_SESSION_OTHER_USER: {
    uz_Cyrl: 'Бу QR кодни бошқа телефон сканерлаган.',
    uz_Latn: 'Bu QR kodni boşqa telefon skanerlagan.',
    ru: 'Этот QR-код уже отсканирован другим телефоном.',
  },
  QR_SESSION_NOT_PENDING: {
    uz_Cyrl: 'Бу QR код аллақачон ишлатилган ёки муддати тугаган.',
    uz_Latn: 'Bu QR kod allaqaçon işlatilgan yoki muddati tugagan.',
    ru: 'Этот QR-код уже использован или истёк.',
  },
  QR_WEB_SESSION_LIMIT: {
    uz_Cyrl: 'Компьютерлардаги фаол киришлар сони чегарага етди. Аввал биттасидан чиқинг.',
    uz_Latn: 'Kompyuterlardagi faol kirişlar soni çegaraga yetdi. Avval bittasidan çiqing.',
    ru: 'Достигнут лимит активных входов на компьютерах. Сначала завершите один из них.',
  },
  QR_RATE_LIMITED: {
    uz_Cyrl: 'Жуда кўп уриниш бўлди. Бироздан кейин қайта уриниб кўринг.',
    uz_Latn: 'Juda köp uriniş böldi. Birozdan keyin qayta urinib köring.',
    ru: 'Слишком много попыток. Повторите немного позже.',
  },
  QR_WEB_SESSION_INVALID: {
    uz_Cyrl: 'Компьютердаги кириш тугаган. QR код орқали қайта киринг.',
    uz_Latn: 'Kompyuterdagi kiriş tugagan. QR kod orqali qayta kiring.',
    ru: 'Сеанс на компьютере завершён. Войдите снова по QR-коду.',
  },
  QR_TOKEN_FAILED: {
    uz_Cyrl: 'Киришни якунлаб бўлмади. Қайта уриниб кўринг.',
    uz_Latn: 'Kirişni yakunlab bölmadi. Qayta urinib köring.',
    ru: 'Не удалось завершить вход. Попробуйте ещё раз.',
  },
  DEVICE_NOT_BOUND: {
    uz_Cyrl: 'Фақат рақам боғланган (асосий) телефондан тасдиқлаш мумкин.',
    uz_Latn: 'Faqat raqam boğlangan (asosiy) telefondan tasdiqlaş mumkin.',
    ru: 'Подтвердить можно только с основного телефона, к которому привязан номер.',
  },
});

function qrMessagesFor(code) {
  return MESSAGES[code] || MESSAGES.QR_SESSION_INVALID;
}

function qrError(functions, httpsCode, code, extra = {}) {
  return new functions.https.HttpsError(httpsCode, code, { code, messages: qrMessagesFor(code), ...extra });
}

// ── Sof yordamchilar (testlanadi) ────────────────────────────────────────

function canTransitionQr(from, to) {
  return (TRANSITIONS[String(from || '')] || []).includes(String(to || ''));
}

const toMs = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : 0);

/** Faol (yakunlanmagan) holat muddati o'tgan bo'lsa — `expired`. */
function effectiveStatus(doc, nowMs) {
  const st = String((doc && doc.status) || '');
  if (!['pending', 'scanned', 'approved'].includes(st)) return st;
  const exp = toMs(doc.expiresAt);
  return exp > 0 && exp <= nowMs ? QR_STATES.EXPIRED : st;
}

function normalizeStage(cfg) {
  const s = String((cfg && cfg.stage) || '').trim().toLowerCase();
  return STAGES.includes(s) ? s : 'off';
}

/** Bosqich shu raqamga ruxsat beradimi (`internal` — faqat testerIds). */
function stageAllows(cfg, phone) {
  const stage = normalizeStage(cfg);
  if (stage === 'public') return true;
  if (stage !== 'internal') return false;
  const ids = Array.isArray(cfg && cfg.testerIds) ? cfg.testerIds.map((x) => String(x)) : [];
  return ids.includes(String(phone || ''));
}

function randomHex(bytes) {
  return crypto.randomBytes(bytes).toString('hex');
}

function sha256Hex(s) {
  return crypto.createHash('sha256').update(`ava-qr-v1|${String(s || '')}`).digest('hex');
}

/** Vaqt bo'yicha teng solishtirish (timing-safe). */
function secretMatches(secret, storedHash) {
  const a = Buffer.from(sha256Hex(secret), 'hex');
  const bHex = String(storedHash || '');
  if (!/^[a-f0-9]{64}$/.test(bHex)) return false;
  const b = Buffer.from(bHex, 'hex');
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function qrPayloadFor(sid) {
  return `${QR_PREFIX}${sid}`;
}

/** QR matnidan sid ('AVAQR1:<32 hex>'); noto'g'ri bo'lsa ''. */
function parseQrPayload(raw) {
  const s = String(raw || '').trim();
  if (!s.startsWith(QR_PREFIX)) return '';
  const sid = s.slice(QR_PREFIX.length).toLowerCase();
  return SID_RE.test(sid) ? sid : '';
}

/** User-Agent → «Chrome · Windows» (taxminiy; to'liq UA saqlanmaydi). */
function browserLabelFromUA(ua) {
  const s = String(ua || '');
  let browser = '';
  if (/Edg\//.test(s)) browser = 'Edge';
  else if (/OPR\/|Opera/.test(s)) browser = 'Opera';
  else if (/YaBrowser\//.test(s)) browser = 'Yandex';
  else if (/Firefox\//.test(s)) browser = 'Firefox';
  else if (/Chrome\//.test(s)) browser = 'Chrome';
  else if (/Safari\//.test(s)) browser = 'Safari';
  let os = '';
  if (/Windows/.test(s)) os = 'Windows';
  else if (/Android/.test(s)) os = 'Android';
  else if (/iPhone|iPad|iPod/.test(s)) os = 'iOS';
  else if (/Mac OS X|Macintosh/.test(s)) os = 'macOS';
  else if (/CrOS/.test(s)) os = 'ChromeOS';
  else if (/Linux/.test(s)) os = 'Linux';
  return [browser, os].filter(Boolean).join(' · ');
}

function clip(s, n) {
  return String(s == null ? '' : s).trim().slice(0, n);
}

/** Web sessiya ro'yxati elementi (telefon/IP/sir YO'Q). */
function sessionItem(id, x, nowMs) {
  const exp = toMs(x.expiresAt);
  const status = String(x.status || '') === 'active' && exp > 0 && exp <= nowMs ? 'expired' : String(x.status || '');
  return {
    webSessionId: id,
    status,
    browserLabel: String(x.browserLabel || ''),
    approxCity: String(x.approxCity || ''),
    createdAtMs: toMs(x.createdAt),
    lastActiveAtMs: toMs(x.lastActiveAt),
    expiresAtMs: exp,
  };
}

/** Hisob egasiga xabar (3 til). */
function texts(kind, { label = '', city = '', at = '' } = {}) {
  const meta = [label, city, at].filter(Boolean).join(' · ');
  const m = meta ? ` (${meta})` : '';
  const T = {
    web_login: {
      uz_Cyrl: ['💻 Компьютерда кирилди', `Ҳисобингизга компьютерда кирилди${m}. Сиз бўлмасангиз — «Компьютерда кириш» бўлимида «Чиқиш» ни босинг.`],
      uz_Latn: ['💻 Kompyuterda kirildi', `Hisobingizga kompyuterda kirildi${m}. Siz bölmasangiz — «Kompyuterda kiriş» bölimida «Çiqiş» ni bosing.`],
      ru: ['💻 Вход на компьютере', `В ваш аккаунт вошли на компьютере${m}. Если это не вы — нажмите «Выйти» в разделе «Вход на компьютере».`],
    },
  };
  const t = T[kind] || T.web_login;
  const i18n = {};
  for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) i18n[l] = { title: t[l][0], body: t[l][1] };
  return { title: t.uz_Cyrl[0], body: t.uz_Cyrl[1], i18n };
}

// ── Callable'lar ─────────────────────────────────────────────────────────

function attachQrWebLogin(exports, deps) {
  const {
    functions,
    authFunctions,
    db,
    admin,
    canonicalUid,
    callerPhone,
    isValidFingerprintHash,
    boundDeviceMatch,
    createPhoneCustomToken,
    notifyUserInApp,
    deviceSecurity,
    sec,
  } = deps;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const tsAt = (ms) => admin.firestore.Timestamp.fromMillis(ms);
  const now = () => Date.now();

  function log(o) {
    console.log(JSON.stringify({ module: 'qr_web_login', ...o }));
  }

  async function loadConfig() {
    try {
      const snap = await db.collection(QR_COL.CONFIG[0]).doc(QR_COL.CONFIG[1]).get();
      return snap.exists ? (snap.data() || {}) : {};
    } catch (e) {
      log({ action: 'config_read', result: 'error', err: String(e && e.message).slice(0, 120) });
      return {};
    }
  }

  /** Umumiy 1 soatlik oyna hisoblagichi (`device_binding_rate`, sof `rateStep`). */
  async function rateLimit(specs) {
    const list = specs.filter((s) => s && s.id);
    if (!list.length) return;
    const refs = list.map((s) => db.collection('device_binding_rate').doc(s.id));
    const nowMs = now();
    const res = await db.runTransaction(async (tx) => {
      const snaps = await tx.getAll(...refs);
      const steps = snaps.map((s, i) => deviceSecurity.rateStep(
        s.exists ? s.data() : null, nowMs, QR_WEB.RATE_WINDOW_MS, list[i].limit));
      const denied = steps.filter((s) => !s.allowed);
      if (denied.length) return { allowed: false, retryAfterMs: Math.max(...denied.map((s) => s.retryAfterMs)) };
      steps.forEach((s, i) => tx.set(refs[i], {
        ...s.next, updatedAt: ts(), expireAt: tsAt(nowMs + 2 * QR_WEB.RATE_WINDOW_MS),
      }));
      return { allowed: true };
    });
    if (!res.allowed) {
      log({ action: 'rate_limited', key: list.map((s) => s.id.slice(0, 6)).join(','), retryAfterMs: res.retryAfterMs });
      throw qrError(functions, 'resource-exhausted', 'QR_RATE_LIMITED', { retryAfterMs: res.retryAfterMs });
    }
  }

  function requirePhone(context) {
    if (!context || !context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    }
    const phone = canonicalUid(callerPhone(context));
    if (!phone || phone.length < 12) {
      throw new functions.https.HttpsError('unauthenticated', 'Phone token required');
    }
    return phone;
  }

  /** Faqat bog'langan (asosiy) telefon — web sessiya boshqa web'ni tasdiqlay olmaydi. */
  async function requireBoundDevice(phone, data) {
    const hash = String((data && data.deviceFingerprintHash) || '').trim().toLowerCase();
    if (!isValidFingerprintHash(hash)) {
      throw qrError(functions, 'permission-denied', 'DEVICE_NOT_BOUND');
    }
    const match = await boundDeviceMatch(phone, hash, deviceSecurity.cleanFingerprint(data && data.fingerprint));
    if (!match.ok) throw qrError(functions, 'permission-denied', 'DEVICE_NOT_BOUND');
    return hash;
  }

  function sidOf(data) {
    const raw = String((data && (data.sid || data.qr)) || '').trim();
    const sid = SID_RE.test(raw.toLowerCase()) ? raw.toLowerCase() : parseQrPayload(raw);
    if (!sid) throw qrError(functions, 'invalid-argument', 'QR_SESSION_INVALID');
    return sid;
  }

  /** Web uchun: brauzer QR so'raydi (auth yo'q). `probe: true` — faqat bosqich holati. */
  exports.qrLoginStart = authFunctions
    .runWith({ timeoutSeconds: 30, memory: '256MB' })
    .https.onCall(async (data, context) => {
      const cfg = await loadConfig();
      const enabled = normalizeStage(cfg) !== 'off';
      if (data && data.probe === true) return { enabled };
      if (!enabled) throw qrError(functions, 'failed-precondition', 'QR_LOGIN_DISABLED');

      const ipKey = deviceSecurity.ipKeyOf(context);
      await rateLimit([{ id: `qs_i_${ipKey || 'noip'}`, limit: QR_WEB.RATE_START_PER_IP }]);

      const headers = (context && context.rawRequest && context.rawRequest.headers) || {};
      const browserLabel = clip(browserLabelFromUA(headers['user-agent'])
        || clip(data && data.browserLabel, 60), 60);
      const city = deviceSecurity.approxCityOf(context);
      const sid = randomHex(16);
      const secret = randomHex(32);
      const watchId = randomHex(32);
      const expiresAtMs = now() + QR_WEB.QR_TTL_MS;

      const batch = db.batch();
      batch.set(db.collection(QR_COL.SESSIONS).doc(sid), {
        status: QR_STATES.PENDING,
        secretHash: sha256Hex(secret),
        watchId,
        browserLabel,
        approxCity: city,
        ipKey,
        createdAt: ts(),
        updatedAt: ts(),
        expiresAt: tsAt(expiresAtMs),
        expireAt: tsAt(expiresAtMs + QR_WEB.TTL_GRACE_MS),
        version: 1,
      });
      batch.set(db.collection(QR_COL.WATCH).doc(watchId), {
        status: QR_STATES.PENDING,
        expiresAt: tsAt(expiresAtMs),
        expireAt: tsAt(expiresAtMs + QR_WEB.TTL_GRACE_MS),
      });
      await batch.commit();
      log({ action: 'qr_start', result: 'ok', sid: sid.slice(0, 8) });
      return { sid, secret, watchId, expiresAtMs, qrPayload: qrPayloadFor(sid), ttlMs: QR_WEB.QR_TTL_MS };
    });

  /** Telefon: QR'ni skanerladi — ma'lumot olish va sessiyani shu raqamga «band qilish». */
  exports.qrLoginPeek = authFunctions
    .runWith({ timeoutSeconds: 30, memory: '256MB' })
    .https.onCall(async (data, context) => {
      const phone = requirePhone(context);
      const sid = sidOf(data);
      if (!stageAllows(await loadConfig(), phone)) {
        throw qrError(functions, 'failed-precondition', 'QR_LOGIN_DISABLED');
      }
      const hash = await requireBoundDevice(phone, data);
      await rateLimit([{ id: `qa_p_${phone}`, limit: QR_WEB.RATE_APPROVER_PER_PHONE }]);

      const ref = db.collection(QR_COL.SESSIONS).doc(sid);
      const out = await db.runTransaction(async (tx) => {
        const s = await tx.get(ref);
        if (!s.exists) return { ok: false, code: 'QR_SESSION_INVALID' };
        const x = s.data() || {};
        const st = effectiveStatus(x, now());
        if (st === QR_STATES.EXPIRED && x.status !== QR_STATES.EXPIRED) {
          tx.set(ref, { status: QR_STATES.EXPIRED, updatedAt: ts() }, { merge: true });
          if (x.watchId) tx.set(db.collection(QR_COL.WATCH).doc(x.watchId), { status: QR_STATES.EXPIRED }, { merge: true });
        }
        if (st === QR_STATES.SCANNED && x.scannedBy !== phone) return { ok: false, code: 'QR_SESSION_OTHER_USER' };
        if (st !== QR_STATES.PENDING && st !== QR_STATES.SCANNED) {
          return { ok: false, code: st === QR_STATES.EXPIRED ? 'QR_SESSION_INVALID' : 'QR_SESSION_NOT_PENDING', status: st };
        }
        if (st === QR_STATES.PENDING) {
          tx.set(ref, {
            status: QR_STATES.SCANNED, scannedBy: phone, scannedAt: ts(),
            scannerHashPrefix: deviceSecurity.hashPrefix(hash), updatedAt: ts(),
          }, { merge: true });
          if (x.watchId) tx.set(db.collection(QR_COL.WATCH).doc(x.watchId), { status: QR_STATES.SCANNED }, { merge: true });
        }
        return { ok: true, x, first: st === QR_STATES.PENDING };
      });
      if (!out.ok) {
        await sec.logEvent({ phone, action: 'qr_scan_refused', result: out.code, requestId: sid, channel: 'qr_web', actor: `phone:${phone}` });
        throw qrError(functions, out.code === 'QR_SESSION_OTHER_USER' ? 'permission-denied' : 'failed-precondition',
          out.code, out.status ? { status: out.status } : {});
      }
      if (out.first) {
        await sec.logEvent({
          phone, action: 'qr_scanned', result: 'scanned', hash, requestId: sid, channel: 'qr_web',
          actor: `phone:${phone}`, label: out.x.browserLabel, city: out.x.approxCity,
        });
      }
      return {
        sid,
        status: QR_STATES.SCANNED,
        browserLabel: String(out.x.browserLabel || ''),
        approxCity: String(out.x.approxCity || ''),
        createdAtMs: toMs(out.x.createdAt),
        expiresAtMs: toMs(out.x.expiresAt),
      };
    });

  /** Telefon: «Тасдиқлайман» / «Бекор қилиш». Bitta g'olib (tranzaksiya). */
  exports.qrLoginApprove = authFunctions
    .runWith({ timeoutSeconds: 30, memory: '256MB' })
    .https.onCall(async (data, context) => {
      const phone = requirePhone(context);
      const sid = sidOf(data);
      const approve = data && data.approve === true;
      if (approve && !stageAllows(await loadConfig(), phone)) {
        throw qrError(functions, 'failed-precondition', 'QR_LOGIN_DISABLED');
      }
      const hash = await requireBoundDevice(phone, data);
      await rateLimit([{ id: `qa_p_${phone}`, limit: QR_WEB.RATE_APPROVER_PER_PHONE }]);

      const ref = db.collection(QR_COL.SESSIONS).doc(sid);
      const target = approve ? QR_STATES.APPROVED : QR_STATES.REJECTED;
      const out = await db.runTransaction(async (tx) => {
        const s = await tx.get(ref);
        if (!s.exists) return { ok: false, code: 'QR_SESSION_INVALID' };
        const x = s.data() || {};
        const st = effectiveStatus(x, now());
        if (st === QR_STATES.EXPIRED) {
          if (x.status !== QR_STATES.EXPIRED) {
            tx.set(ref, { status: QR_STATES.EXPIRED, updatedAt: ts() }, { merge: true });
            if (x.watchId) tx.set(db.collection(QR_COL.WATCH).doc(x.watchId), { status: QR_STATES.EXPIRED }, { merge: true });
          }
          return { ok: false, code: 'QR_SESSION_INVALID' };
        }
        if (x.scannedBy && x.scannedBy !== phone) return { ok: false, code: 'QR_SESSION_OTHER_USER' };
        if (!canTransitionQr(st, target) || st === QR_STATES.APPROVED) {
          return { ok: false, code: 'QR_SESSION_NOT_PENDING', status: st };
        }
        const patch = {
          status: target,
          scannedBy: phone,
          decidedAt: ts(),
          approverHashPrefix: deviceSecurity.hashPrefix(hash),
          updatedAt: ts(),
        };
        let expiresAtMs = toMs(x.expiresAt);
        if (approve) {
          expiresAtMs = Math.max(expiresAtMs, now() + QR_WEB.CONSUME_WINDOW_MS);
          patch.expiresAt = tsAt(expiresAtMs);
        }
        tx.set(ref, patch, { merge: true });
        if (x.watchId) {
          tx.set(db.collection(QR_COL.WATCH).doc(x.watchId), { status: target, expiresAt: tsAt(expiresAtMs) }, { merge: true });
        }
        sec.logEventInTx(tx, {
          phone, action: approve ? 'qr_approved' : 'qr_rejected', result: target, hash, requestId: sid,
          channel: 'qr_web', actor: `phone:${phone}`, label: x.browserLabel, city: x.approxCity,
        });
        return { ok: true };
      });
      if (!out.ok) {
        throw qrError(functions, out.code === 'QR_SESSION_OTHER_USER' ? 'permission-denied' : 'failed-precondition',
          out.code, out.status ? { status: out.status } : {});
      }
      log({ action: approve ? 'qr_approved' : 'qr_rejected', sid: sid.slice(0, 8), phoneTail: phone.slice(-4) });
      return { status: target, sid };
    });

  /** Web: tasdiqlangan QR → bir martalik custom token + web sessiya. */
  exports.qrLoginConsume = authFunctions
    .runWith({ timeoutSeconds: 30, memory: '256MB' })
    .https.onCall(async (data, context) => {
      const sid = sidOf(data);
      const secret = String((data && data.secret) || '').trim().toLowerCase();
      if (!SECRET_RE.test(secret)) throw qrError(functions, 'permission-denied', 'QR_SESSION_INVALID');
      if (normalizeStage(await loadConfig()) === 'off') {
        throw qrError(functions, 'failed-precondition', 'QR_LOGIN_DISABLED');
      }
      const ipKey = deviceSecurity.ipKeyOf(context);
      await rateLimit([{ id: `qc_i_${ipKey || 'noip'}`, limit: QR_WEB.RATE_CONSUME_PER_IP }]);

      const ref = db.collection(QR_COL.SESSIONS).doc(sid);
      const wsid = randomHex(16);
      const renewSecret = randomHex(32);
      const sessionExpiresAtMs = now() + QR_WEB.SESSION_TTL_MS;
      const out = await db.runTransaction(async (tx) => {
        const s = await tx.get(ref);
        if (!s.exists) return { ok: false, code: 'QR_SESSION_INVALID' };
        const x = s.data() || {};
        if (!secretMatches(secret, x.secretHash)) return { ok: false, code: 'QR_SESSION_INVALID', badSecret: true };
        const st = effectiveStatus(x, now());
        if (st !== QR_STATES.APPROVED || !canTransitionQr(st, QR_STATES.CONSUMED)) {
          return { ok: false, code: 'QR_SESSION_NOT_PENDING', status: st };
        }
        const phone = canonicalUid(x.scannedBy || '');
        if (phone.length < 12) return { ok: false, code: 'QR_SESSION_INVALID' };
        // «Битта рақам 1 та компьютер»: oldingi faol sessiyalar shu tranzaksiyada almashtiriladi
        // (o'qishlar yozuvlardan oldin; parallel consume'lar tranzaksiya to'qnashuvida ketma-ket bo'ladi).
        const prev = await tx.get(db.collection(QR_COL.WEB_SESSIONS)
          .where('phone', '==', phone).where('status', '==', 'active').limit(QR_WEB.LIST_LIMIT));
        for (const d of prev.docs) {
          tx.set(d.ref, {
            status: 'revoked', revokedBy: 'replaced', replacedBy: wsid, revokedAt: ts(), updatedAt: ts(),
          }, { merge: true });
          sec.logEventInTx(tx, {
            phone, action: 'qr_web_replaced', result: 'revoked', requestId: d.id, channel: 'qr_web',
            actor: 'web', label: (d.data() || {}).browserLabel, note: `by:${wsid}`,
          });
        }
        tx.set(ref, { status: QR_STATES.CONSUMED, consumedAt: ts(), webSessionId: wsid, updatedAt: ts() }, { merge: true });
        if (x.watchId) tx.set(db.collection(QR_COL.WATCH).doc(x.watchId), { status: QR_STATES.CONSUMED }, { merge: true });
        tx.set(db.collection(QR_COL.WEB_SESSIONS).doc(wsid), {
          phone,
          status: 'active',
          browserLabel: clip(x.browserLabel, 60),
          approxCity: clip(x.approxCity, 60),
          ipKey: clip(ipKey, 24),
          qrSessionId: sid,
          approverHashPrefix: clip(x.approverHashPrefix, 12),
          renewSecretHash: sha256Hex(renewSecret),
          createdAt: ts(),
          lastActiveAt: ts(),
          updatedAt: ts(),
          expiresAt: tsAt(sessionExpiresAtMs),
        });
        sec.logEventInTx(tx, {
          phone, action: 'qr_consumed', result: 'web_session_created', requestId: wsid, channel: 'qr_web',
          actor: 'web', label: x.browserLabel, city: x.approxCity, ipKey, note: `qr:${sid}`,
        });
        return { ok: true, phone, x, replaced: prev.size };
      });
      if (!out.ok) {
        if (out.badSecret) {
          await sec.logEvent({ phone: '', action: 'qr_consume_bad_secret', result: 'refused', requestId: sid, channel: 'qr_web', actor: 'web', ipKey });
        }
        log({ action: 'qr_consume', result: out.code, status: out.status || '', sid: sid.slice(0, 8) });
        throw qrError(functions, out.code === 'QR_SESSION_INVALID' ? 'permission-denied' : 'failed-precondition',
          out.code, out.status ? { status: out.status } : {});
      }
      const { phone } = out;

      let customToken = '';
      try {
        customToken = await createPhoneCustomToken(phone);
      } catch (e) {
        await db.collection(QR_COL.WEB_SESSIONS).doc(wsid).set({ status: 'failed', updatedAt: ts() }, { merge: true });
        log({ action: 'qr_consume', result: 'token_failed', sid: sid.slice(0, 8), err: String(e && e.message).slice(0, 120) });
        throw qrError(functions, 'internal', 'QR_TOKEN_FAILED');
      }
      const t = texts('web_login', {
        label: out.x.browserLabel, city: out.x.approxCity, at: deviceSecurity.tashkentTime(now()),
      });
      try {
        await notifyUserInApp({
          userId: phone, title: t.title, body: t.body, category: 'security',
          source: 'qr_web_login', dataType: 'qr_web_login', screen: 'news',
          extraNews: { i18n: t.i18n }, extraData: { webSessionId: wsid },
        });
      } catch (e) {
        log({ action: 'qr_notify', result: 'error', err: String(e && e.message).slice(0, 120) });
      }
      log({ action: 'qr_consume', result: 'ok', sid: sid.slice(0, 8), phoneTail: phone.slice(-4), replaced: out.replaced });
      return { customToken, phone, webSessionId: wsid, renewSecret, sessionExpiresAtMs, replacedSessions: out.replaced };
    });

  /** Web: sessiyani jim yangilash (refresh token'lar bekor qilinganda). */
  exports.qrWebSessionRenew = authFunctions
    .runWith({ timeoutSeconds: 30, memory: '256MB' })
    .https.onCall(async (data, context) => {
      const wsid = String((data && data.webSessionId) || '').trim().toLowerCase();
      const renewSecret = String((data && data.renewSecret) || '').trim().toLowerCase();
      if (!WSID_RE.test(wsid) || !SECRET_RE.test(renewSecret)) {
        throw qrError(functions, 'permission-denied', 'QR_WEB_SESSION_INVALID');
      }
      if (normalizeStage(await loadConfig()) === 'off') {
        throw qrError(functions, 'failed-precondition', 'QR_LOGIN_DISABLED');
      }
      const ipKey = deviceSecurity.ipKeyOf(context);
      await rateLimit([
        { id: `qr_s_${wsid}`, limit: QR_WEB.RATE_RENEW_PER_SESSION },
        { id: `qr_i_${ipKey || 'noip'}`, limit: QR_WEB.RATE_RENEW_PER_IP },
      ]);
      const ref = db.collection(QR_COL.WEB_SESSIONS).doc(wsid);
      const snap = await ref.get();
      const x = snap.exists ? (snap.data() || {}) : null;
      const ok = !!x && secretMatches(renewSecret, x.renewSecretHash);
      const expired = ok && toMs(x.expiresAt) <= now();
      if (!ok || x.status !== 'active' || expired) {
        if (expired && x.status === 'active') {
          await ref.set({ status: 'expired', updatedAt: ts() }, { merge: true });
        }
        if (x) {
          await sec.logEvent({
            phone: String(x.phone || ''), action: 'qr_renew_refused', result: !ok ? 'bad_secret' : (expired ? 'expired' : String(x.status || '')),
            requestId: wsid, channel: 'qr_web', actor: 'web', ipKey,
          });
        }
        throw qrError(functions, 'permission-denied', 'QR_WEB_SESSION_INVALID');
      }
      const phone = canonicalUid(x.phone || '');
      let customToken;
      try {
        customToken = await createPhoneCustomToken(phone);
      } catch (e) {
        throw qrError(functions, 'internal', 'QR_TOKEN_FAILED');
      }
      await ref.set({ lastActiveAt: ts(), updatedAt: ts() }, { merge: true });
      await sec.logEvent({ phone, action: 'qr_renewed', result: 'ok', requestId: wsid, channel: 'qr_web', actor: 'web', ipKey });
      return { customToken, phone, webSessionId: wsid, sessionExpiresAtMs: toMs(x.expiresAt) };
    });

  /** Telefon (yoki web o'zi): faol web sessiyalar ro'yxati. OFF bosqichda ham (chiqish uchun). */
  exports.qrWebSessionsList = authFunctions
    .runWith({ timeoutSeconds: 30, memory: '256MB' })
    .https.onCall(async (data, context) => {
      const phone = requirePhone(context);
      const cfg = await loadConfig();
      let canManage = false;
      const hash = String((data && data.deviceFingerprintHash) || '').trim().toLowerCase();
      if (isValidFingerprintHash(hash)) {
        const m = await boundDeviceMatch(phone, hash, deviceSecurity.cleanFingerprint(data && data.fingerprint));
        canManage = m.ok === true;
      }
      const snap = await db.collection(QR_COL.WEB_SESSIONS)
        .where('phone', '==', phone).where('status', '==', 'active').limit(QR_WEB.LIST_LIMIT).get();
      const nowMs = now();
      const items = snap.docs.map((d) => sessionItem(d.id, d.data() || {}, nowMs))
        .filter((i) => i.status === 'active')
        .sort((a, b) => b.lastActiveAtMs - a.lastActiveAtMs);
      return { enabled: stageAllows(cfg, phone), canManage, items };
    });

  /**
   * «Чиқиш». Ikki rejim:
   *  - telefon (auth + bog'langan qurilma): `webSessionId` yoki `all: true` → revoked + hisob refresh
   *    token'lari bekor (`reauthRequired` — telefon darhol o'z bog'lanishi bilan qayta kiradi);
   *  - web o'zi (`webSessionId` + `renewSecret`): faqat shu sessiya revoked (token bekor qilinmaydi,
   *    web o'zi signOut qiladi).
   * Takroriy chaqiruv xavfsiz (revoked: 0).
   */
  exports.qrWebSessionRevoke = authFunctions
    .runWith({ timeoutSeconds: 30, memory: '256MB' })
    .https.onCall(async (data, context) => {
      const wsidRaw = String((data && data.webSessionId) || '').trim().toLowerCase();
      const renewSecret = String((data && data.renewSecret) || '').trim().toLowerCase();
      const all = data && data.all === true;

      if (renewSecret) {
        if (!WSID_RE.test(wsidRaw) || !SECRET_RE.test(renewSecret)) {
          throw qrError(functions, 'permission-denied', 'QR_WEB_SESSION_INVALID');
        }
        const ref = db.collection(QR_COL.WEB_SESSIONS).doc(wsidRaw);
        const res = await db.runTransaction(async (tx) => {
          const s = await tx.get(ref);
          const x = s.exists ? (s.data() || {}) : null;
          if (!x || !secretMatches(renewSecret, x.renewSecretHash)) return { ok: false };
          if (x.status !== 'active') return { ok: true, revoked: 0, phone: String(x.phone || '') };
          tx.set(ref, { status: 'revoked', revokedBy: 'web_self', revokedAt: ts(), updatedAt: ts() }, { merge: true });
          sec.logEventInTx(tx, {
            phone: String(x.phone || ''), action: 'qr_web_logout', result: 'revoked', requestId: wsidRaw,
            channel: 'qr_web', actor: 'web',
          });
          return { ok: true, revoked: 1, phone: String(x.phone || '') };
        });
        if (!res.ok) throw qrError(functions, 'permission-denied', 'QR_WEB_SESSION_INVALID');
        return { revoked: res.revoked, reauthRequired: false };
      }

      const phone = requirePhone(context);
      const hash = await requireBoundDevice(phone, data);
      if (!all && !WSID_RE.test(wsidRaw)) {
        throw new functions.https.HttpsError('invalid-argument', 'webSessionId');
      }
      let refs;
      if (all) {
        const snap = await db.collection(QR_COL.WEB_SESSIONS)
          .where('phone', '==', phone).where('status', '==', 'active').limit(50).get();
        refs = snap.docs.map((d) => d.ref);
      } else {
        refs = [db.collection(QR_COL.WEB_SESSIONS).doc(wsidRaw)];
      }
      let revoked = 0;
      for (const ref of refs) {
        const r = await db.runTransaction(async (tx) => {
          const s = await tx.get(ref);
          const x = s.exists ? (s.data() || {}) : null;
          if (!x) return 0;
          if (canonicalUid(x.phone || '') !== phone) return -1;
          if (x.status !== 'active') return 0;
          tx.set(ref, { status: 'revoked', revokedBy: 'phone', revokedAt: ts(), updatedAt: ts() }, { merge: true });
          sec.logEventInTx(tx, {
            phone, action: 'qr_web_revoked', result: 'revoked', hash, requestId: ref.id, channel: 'qr_web',
            actor: `phone:${phone}`, label: x.browserLabel,
          });
          return 1;
        });
        if (r === -1) throw new functions.https.HttpsError('permission-denied', 'Not your session');
        revoked += r;
      }
      // Qattiq chiqish: barcha refresh token'lar bekor (Firestore rules bekorni tekshirmaydi —
      // eski ID token ≤1 soat yashashi mumkin; web klient status'ni tinglab darhol chiqadi).
      let tokensRevoked = false;
      if (revoked > 0) tokensRevoked = await sec.revokeAccountSessions(phone);
      log({ action: 'qr_web_revoke', phoneTail: phone.slice(-4), revoked, all, tokensRevoked });
      return { revoked, reauthRequired: tokensRevoked };
    });
}

module.exports = {
  QR_WEB,
  QR_COL,
  QR_STATES,
  QR_PREFIX,
  MESSAGES,
  qrMessagesFor,
  canTransitionQr,
  effectiveStatus,
  normalizeStage,
  stageAllows,
  sha256Hex,
  secretMatches,
  qrPayloadFor,
  parseQrPayload,
  browserLabelFromUA,
  sessionItem,
  texts,
  attachQrWebLogin,
};
