/**
 * ХИТОЙ БОЗОРИ — «Сўров қолдириш» (ega qarori 2026-10-20: variant A, operator qo'lda yuboradi).
 *
 * Оқим: мижоз сўров қолдиради → оператор хитойча матн тайёрлайди → ҳар таъминотчига АВАнинг
 * WeChat'идан ҚЎЛДА юборади ва шу ерда «юборилди» деб белгилайди → жавобни киритади → мижозга
 * хабар боради. WeChat'нинг ўзи билан ҳеч қандай автомат алоқа йўқ (шахсий аккаунтга расмий API йўқ).
 *
 * Нега demand core эмас: у таклиф берувчини АВА фойдаланувчиси деб билади (`submitOffer` →
 * `assertIsMatched`) ва ҳудуд бўйича мослайди; Хитой таъминотчиси фойдаланувчи эмас.
 *
 * Коллекциялар (ҳаммаси client-write ЁПИҚ, фақат шу CF'лар ёзади):
 *   china_inquiries/{id}              — сўров (мижоз ўз сўровини ўқийди)
 *     /offers/{qid}                   — мижозга КЎРИНАДИГАН таклиф (таъминотчи номи/ички изоҳ ЙЎҚ)
 *     /quotes/{qid}                   — ички тўлиқ таклиф (supplierId, internalNote) — фақат админ
 *     /dispatches/{supplierId}        — кимга қачон юборилган (ID = supplierId → идемпотент)
 *     /events/{auto}                  — ўзгармас тарих (16-банд)
 *   china_suppliers/{id}              — таъминотчилар рўйхати (фақат админ; мижозга кўринмайди)
 *   china_inquiry_config/main         — босқич (off|internal|public) + testerIds, версияли
 *   china_inquiry_config_history/v{n} — ўзгармас тарих
 *   china_inquiry_meta/counter        — REQ рақами ҳисоблагичи
 *
 * Пул: `priceMinor` — бутун сон (cent/fen), float йўқ (8-банд). Валюталар рўйхати — PROPOSED
 * (CURRENCIES), эга тасдиқлагунча ўзгартириш осон.
 *
 * Диагностика кодлари: CHINA_INQUIRY_DISABLED, CONSENT_REQUIRED, TEXT_INVALID, QUANTITY_INVALID,
 * PRODUCT_INVALID, REQUEST_ID_INVALID, TOO_MANY_OPEN, INQUIRY_NOT_FOUND, NOT_OWNER, INVALID_TRANSITION,
 * SUPPLIER_NOT_FOUND, SUPPLIER_INACTIVE, TEXT_ZH_REQUIRED, NOT_DISPATCHED, PRICE_INVALID,
 * CURRENCY_INVALID, QUOTE_NOT_FOUND, TOO_MANY_QUOTES, STAGE_INVALID, TESTERS_INVALID, REASON_REQUIRED.
 */
'use strict';

const { render, langOfPhone } = require('./notif_i18n');

const INQUIRIES = 'china_inquiries';
const SUPPLIERS = 'china_suppliers';
const CONFIG_DOC = ['china_inquiry_config', 'main'];
const CONFIG_HISTORY = 'china_inquiry_config_history';
const COUNTER_DOC = ['china_inquiry_meta', 'counter'];
const ADMIN_AUDIT = 'admin_audit';

const STAGES = Object.freeze(['off', 'internal', 'public']);
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);

const S = Object.freeze({
  NEW: 'new',
  SENT: 'sent',
  QUOTED: 'quoted',
  CLOSED: 'closed',
  CANCELLED: 'cancelled',
});
/** Марказлашган state machine (17-банд): қайси ҳолатдан қайси ҳолатга. Терминал: closed, cancelled. */
const TRANSITIONS = Object.freeze({
  [S.NEW]: [S.SENT, S.CANCELLED, S.CLOSED],
  [S.SENT]: [S.SENT, S.QUOTED, S.CANCELLED, S.CLOSED],
  [S.QUOTED]: [S.QUOTED, S.CANCELLED, S.CLOSED],
  [S.CLOSED]: [],
  [S.CANCELLED]: [],
});
const OPEN_STATUSES = Object.freeze([S.NEW, S.SENT, S.QUOTED]);

// PROPOSED — эга тасдиқлагунча (47-банд). Ўзгартириш = шу константалар.
const CURRENCIES = Object.freeze(['USD', 'CNY']);
const LIMITS = Object.freeze({
  textMin: 10,
  textMax: 500,
  quantityMax: 60,
  textZhMax: 1500,
  noteMax: 500,
  nameMax: 80,
  maxOpenPerUser: 5,
  maxQuotesPerInquiry: 20,
  maxTesters: 200,
  priceMinorMax: 1e12,
  moqMax: 1e9,
  leadDaysMax: 365,
});

const ID_RE = /^[A-Za-z0-9_-]{8,64}$/;
const DOC_ID_RE = /^[A-Za-z0-9_-]{1,128}$/;

function str(v, max) {
  return String(v == null ? '' : v).trim().slice(0, max);
}

/** state machine текшируви — соф функция (тест учун экспорт). */
function canTransition(from, to) {
  return Array.isArray(TRANSITIONS[from]) && TRANSITIONS[from].includes(to);
}

/** Босқич қуриб беради ёки йўқ: `off` — ҳеч кимга; `internal` — фақат testerIds; `public` — ҳамма. */
function stageAllows(config, uid) {
  const stage = config && STAGES.includes(config.stage) ? config.stage : 'off';
  if (stage === 'public') return true;
  if (stage === 'internal') return Array.isArray(config.testerIds) && config.testerIds.includes(uid);
  return false;
}

/** Қисман ўзгартириш: берилмаган қиймат сақланади. Ёки HttpsError. */
function mergeConfig(input, current, { fail, canonicalUid }) {
  const d = input || {};
  const cur = current || {};
  let stage = STAGES.includes(cur.stage) ? cur.stage : 'off';
  if (d.stage != null) {
    if (!STAGES.includes(d.stage)) throw fail('invalid-argument', 'STAGE_INVALID');
    stage = d.stage;
  }
  let testerIds = Array.isArray(cur.testerIds) ? cur.testerIds : [];
  if (d.testerIds != null) {
    if (!Array.isArray(d.testerIds) || d.testerIds.length > LIMITS.maxTesters) {
      throw fail('invalid-argument', 'TESTERS_INVALID');
    }
    testerIds = [...new Set(d.testerIds.map((x) => canonicalUid(String(x || ''))))];
    if (testerIds.some((x) => !/^\d{12}$/.test(x))) throw fail('invalid-argument', 'TESTERS_INVALID');
  }
  return { stage, testerIds };
}

function attachChinaInquiries(exportsObj, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, requireCallerRoles, notifyUserInApp,
  } = deps;
  const HttpsError = functions.https.HttpsError;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const fail = (status, code, message, extra = {}) => new HttpsError(status, message || code, { code, ...extra });
  const log = (o) => console.log(JSON.stringify({ module: 'china_inquiry', ...o }));

  /** Мижоз: токендаги телефондан 12 хонали uid. */
  function requireUser(context) {
    if (!context || !context.auth) throw new HttpsError('unauthenticated', 'Authentication required');
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length < 12) throw new HttpsError('unauthenticated', 'Phone token required');
    return uid;
  }
  const requireAdmin = (context) => requireCallerRoles(context, ADMIN_ROLES, 'Admin role required');

  async function readConfig() {
    const snap = await db.collection(CONFIG_DOC[0]).doc(CONFIG_DOC[1]).get();
    return snap.exists ? (snap.data() || {}) : {};
  }

  function docId(v, code) {
    const s = str(v, 128);
    if (!DOC_ID_RE.test(s)) throw fail('invalid-argument', code);
    return s;
  }

  function reasonOf(data) {
    const r = str(data && data.reason, 300);
    if (r.length < 3) throw fail('invalid-argument', 'REASON_REQUIRED');
    return r;
  }

  function event(t, inquiryRef, type, actor, extra = {}) {
    t.set(inquiryRef.collection('events').doc(), { type, actor, at: ts(), ...extra });
  }

  // ───────────────────────── Мижоз ─────────────────────────

  /** Илова тугмани кўрсатиш-кўрсатмасликни билади. Рўйхат/тестерлар клиентга БЕРИЛМАЙДИ (40-банд). */
  exportsObj.getChinaInquiryAccess = functions.https.onCall(async (data, context) => {
    const uid = requireUser(context);
    return { enabled: stageAllows(await readConfig(), uid) };
  });

  /**
   * data: { text, quantity?, productId?, consent: true, clientRequestId }
   * → { ok, inquiryId, refNo, duplicate }. clientRequestId бўйича идемпотент (21-банд).
   */
  exportsObj.createChinaInquiry = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = requireUser(context);
    const d = data || {};
    const clientRequestId = str(d.clientRequestId, 64);
    if (!ID_RE.test(clientRequestId)) throw fail('invalid-argument', 'REQUEST_ID_INVALID');

    if (!stageAllows(await readConfig(), uid)) {
      throw fail('failed-precondition', 'CHINA_INQUIRY_DISABLED', 'Хизмат ҳозирча ишга тушмаган.');
    }
    if (d.consent !== true) {
      throw fail('failed-precondition', 'CONSENT_REQUIRED', 'Давом этиш учун розилик беринг.');
    }
    const text = str(d.text, 2000);
    if (text.length < LIMITS.textMin || text.length > LIMITS.textMax) {
      throw fail('invalid-argument', 'TEXT_INVALID', `Сўров ${LIMITS.textMin}–${LIMITS.textMax} белги бўлсин.`);
    }
    const quantity = str(d.quantity, 200);
    if (quantity.length > LIMITS.quantityMax) {
      throw fail('invalid-argument', 'QUANTITY_INVALID', 'Миқдор матни жуда узун.');
    }

    // Маҳсулот (ихтиёрий): серверда текширилади — клиентга ишонилмайди (18-банд).
    let productId = '';
    if (d.productId != null && d.productId !== '') {
      productId = docId(d.productId, 'PRODUCT_INVALID');
      const p = await db.collection('wholesale_products').doc(productId).get();
      if (!p.exists || (p.data() || {}).market !== 'china') {
        throw fail('invalid-argument', 'PRODUCT_INVALID', 'Маҳсулот топилмади.');
      }
    }

    const ref = db.collection(INQUIRIES).doc(`${uid}_${clientRequestId}`);
    const counterRef = db.collection(COUNTER_DOC[0]).doc(COUNTER_DOC[1]);
    const out = await db.runTransaction(async (t) => {
      const [snap, openSnap, counterSnap] = await Promise.all([
        t.get(ref),
        t.get(db.collection(INQUIRIES).where('ownerId', '==', uid)
          .where('status', 'in', OPEN_STATUSES).limit(LIMITS.maxOpenPerUser)),
        t.get(counterRef),
      ]);
      if (snap.exists) return { inquiryId: ref.id, refNo: snap.data().refNo, duplicate: true };
      if (openSnap.size >= LIMITS.maxOpenPerUser) {
        throw fail('resource-exhausted', 'TOO_MANY_OPEN',
          'Очиқ сўровларингиз кўп. Аввалгилари якунлангандан кейин яна ёзинг.');
      }
      const n = (counterSnap.exists && Number.isInteger(counterSnap.data().n) ? counterSnap.data().n : 0) + 1;
      const refNo = `CN-${String(n).padStart(4, '0')}`;
      t.set(counterRef, { n, updatedAt: ts() });
      t.create(ref, {
        ownerId: uid,
        refNo,
        status: S.NEW,
        text,
        quantity,
        productId,
        textZh: '',
        consentAt: ts(),
        consentVersion: 1,
        quoteCount: 0,
        createdAt: ts(),
        updatedAt: ts(),
      });
      event(t, ref, 'created', uid);
      return { inquiryId: ref.id, refNo, duplicate: false };
    });
    log({ action: 'createChinaInquiry', userId: uid, inquiryId: out.inquiryId, result: out.duplicate ? 'duplicate' : 'ok', durationMs: Date.now() - started });
    return { ok: true, ...out };
  });

  /** Мижоз ўз сўровини бекор қилади (терминал бўлмаган ҳолатдан). */
  exportsObj.cancelChinaInquiry = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = requireUser(context);
    const ref = db.collection(INQUIRIES).doc(docId(data && data.inquiryId, 'INQUIRY_NOT_FOUND'));
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) throw fail('not-found', 'INQUIRY_NOT_FOUND', 'Сўров топилмади.');
      const inq = snap.data();
      if (inq.ownerId !== uid) throw fail('permission-denied', 'NOT_OWNER', 'Сўров топилмади.');
      if (inq.status === S.CANCELLED) return { changed: false };
      if (!canTransition(inq.status, S.CANCELLED)) {
        throw fail('failed-precondition', 'INVALID_TRANSITION', 'Бу сўровни энди бекор қилиб бўлмайди.');
      }
      t.update(ref, { status: S.CANCELLED, updatedAt: ts() });
      event(t, ref, 'cancelled', uid);
      return { changed: true };
    });
    log({ action: 'cancelChinaInquiry', userId: uid, inquiryId: ref.id, result: out.changed ? 'ok' : 'noop', durationMs: Date.now() - started });
    return { ok: true, ...out };
  });

  // ───────────────────────── Админ ─────────────────────────

  /** Босқич/тестерлар: версияли, тарих + audit; ўзгармаса версия ОШМАЙДИ (идемпотент). */
  exportsObj.adminSetChinaInquiryConfig = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const reason = reasonOf(data);
    const ref = db.collection(CONFIG_DOC[0]).doc(CONFIG_DOC[1]);
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const cur = snap.exists ? (snap.data() || {}) : {};
      const next = mergeConfig(data, cur, { fail, canonicalUid });
      const same = snap.exists && cur.stage === next.stage
        && JSON.stringify(cur.testerIds || []) === JSON.stringify(next.testerIds);
      if (same) return { version: Number.isInteger(cur.version) ? cur.version : 0, changed: false };
      const version = (Number.isInteger(cur.version) ? cur.version : 0) + 1;
      const doc = { ...next, version, reason, updatedAt: ts(), updatedBy: actor };
      t.set(ref, doc);
      t.create(db.collection(CONFIG_HISTORY).doc(`v${version}`), {
        ...doc, previous: snap.exists ? { version: cur.version || 0, stage: cur.stage || 'off' } : null,
      });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'china_inquiry_config_set', actor, target: `v${version}`, reason, at: ts(),
      });
      return { version, changed: true };
    });
    log({ action: 'adminSetChinaInquiryConfig', userId: actor, version: out.version, changed: out.changed, result: 'ok' });
    return { ok: true, ...out };
  });

  /**
   * Таъминотчини қўшиш/таҳрирлаш. data: { supplierId?, displayName, wechatId?, note?, active? }
   * Ўчириш йўқ — `active:false` (тарих сақланади).
   */
  exportsObj.adminUpsertChinaSupplier = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const d = data || {};
    const displayName = str(d.displayName, LIMITS.nameMax);
    if (displayName.length < 2) throw fail('invalid-argument', 'SUPPLIER_NAME_INVALID');
    const fields = {
      displayName,
      wechatId: str(d.wechatId, 64),
      note: str(d.note, LIMITS.noteMax),
      active: d.active !== false,
    };
    const ref = d.supplierId ? db.collection(SUPPLIERS).doc(docId(d.supplierId, 'SUPPLIER_NOT_FOUND'))
      : db.collection(SUPPLIERS).doc();
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (d.supplierId && !snap.exists) throw fail('not-found', 'SUPPLIER_NOT_FOUND');
      const cur = snap.exists ? snap.data() : null;
      if (cur && Object.keys(fields).every((k) => cur[k] === fields[k])) return { changed: false };
      if (cur) t.update(ref, { ...fields, updatedAt: ts(), updatedBy: actor });
      else t.create(ref, { ...fields, createdAt: ts(), createdBy: actor, updatedAt: ts(), updatedBy: actor });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: cur ? 'china_supplier_update' : 'china_supplier_create', actor, target: ref.id,
        active: fields.active, at: ts(),
      });
      return { changed: true };
    });
    log({ action: 'adminUpsertChinaSupplier', userId: actor, supplierId: ref.id, changed: out.changed, result: 'ok' });
    return { ok: true, supplierId: ref.id, ...out };
  });

  /** Оператор жўнатиладиган хитойча матнни сақлайди. data: { inquiryId, textZh } */
  exportsObj.adminSetChinaInquiryTextZh = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const ref = db.collection(INQUIRIES).doc(docId(data && data.inquiryId, 'INQUIRY_NOT_FOUND'));
    const textZh = str(data && data.textZh, LIMITS.textZhMax);
    if (!textZh) throw fail('invalid-argument', 'TEXT_ZH_REQUIRED');
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) throw fail('not-found', 'INQUIRY_NOT_FOUND');
      const inq = snap.data();
      if (!OPEN_STATUSES.includes(inq.status)) throw fail('failed-precondition', 'INVALID_TRANSITION');
      if (inq.textZh === textZh) return { changed: false };
      t.update(ref, { textZh, textZhBy: actor, textZhAt: ts(), updatedAt: ts() });
      event(t, ref, 'text_zh_set', actor);
      return { changed: true };
    });
    log({ action: 'adminSetChinaInquiryTextZh', userId: actor, inquiryId: ref.id, changed: out.changed, result: 'ok' });
    return { ok: true, ...out };
  });

  /**
   * Оператор «WeChat'га юборилди» деб белгилайди. data: { inquiryId, supplierId }
   * Идемпотент: ҳужжат ID = supplierId, иккинчи босиш ҳеч нарсани ўзгартирмайди (22-банд).
   */
  exportsObj.adminMarkChinaInquirySent = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const ref = db.collection(INQUIRIES).doc(docId(data && data.inquiryId, 'INQUIRY_NOT_FOUND'));
    const supplierRef = db.collection(SUPPLIERS).doc(docId(data && data.supplierId, 'SUPPLIER_NOT_FOUND'));
    const out = await db.runTransaction(async (t) => {
      const [snap, supSnap, dispSnap] = await Promise.all([
        t.get(ref), t.get(supplierRef), t.get(ref.collection('dispatches').doc(supplierRef.id)),
      ]);
      if (!snap.exists) throw fail('not-found', 'INQUIRY_NOT_FOUND');
      if (!supSnap.exists) throw fail('not-found', 'SUPPLIER_NOT_FOUND');
      if (dispSnap.exists) return { duplicate: true };
      const inq = snap.data();
      const sup = supSnap.data();
      if (sup.active !== true) throw fail('failed-precondition', 'SUPPLIER_INACTIVE');
      if (!inq.textZh) throw fail('failed-precondition', 'TEXT_ZH_REQUIRED');
      if (!canTransition(inq.status, S.SENT)) throw fail('failed-precondition', 'INVALID_TRANSITION');
      t.create(ref.collection('dispatches').doc(supplierRef.id), {
        supplierId: supplierRef.id,
        supplierName: sup.displayName,
        textZh: inq.textZh,
        sentAt: ts(),
        sentBy: actor,
      });
      if (inq.status === S.NEW) t.update(ref, { status: S.SENT, updatedAt: ts() });
      event(t, ref, 'sent', actor, { supplierId: supplierRef.id });
      return { duplicate: false };
    });
    log({ action: 'adminMarkChinaInquirySent', userId: actor, inquiryId: ref.id, supplierId: supplierRef.id, result: out.duplicate ? 'duplicate' : 'ok' });
    return { ok: true, ...out };
  });

  /**
   * Таъминотчи жавобини киритиш. data: { inquiryId, supplierId, priceMinor, currency,
   *   minOrderQty?, leadTimeDays?, customerNote?, internalNote?, clientRequestId }
   * Мижозга `offers`га ТАЪМИНОТЧИСИЗ нусха ёзилади; тўлиқ ёзув `quotes`да (фақат админ).
   */
  exportsObj.adminAddChinaQuote = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const actor = await requireAdmin(context);
    const d = data || {};
    const ref = db.collection(INQUIRIES).doc(docId(d.inquiryId, 'INQUIRY_NOT_FOUND'));
    const supplierId = docId(d.supplierId, 'SUPPLIER_NOT_FOUND');
    const clientRequestId = str(d.clientRequestId, 64);
    if (!ID_RE.test(clientRequestId)) throw fail('invalid-argument', 'REQUEST_ID_INVALID');
    const priceMinor = d.priceMinor;
    if (!Number.isInteger(priceMinor) || priceMinor < 1 || priceMinor > LIMITS.priceMinorMax) {
      throw fail('invalid-argument', 'PRICE_INVALID');
    }
    if (!CURRENCIES.includes(d.currency)) throw fail('invalid-argument', 'CURRENCY_INVALID');
    const optInt = (v, max, code) => {
      if (v == null || v === '') return null;
      if (!Number.isInteger(v) || v < 1 || v > max) throw fail('invalid-argument', code);
      return v;
    };
    const minOrderQty = optInt(d.minOrderQty, LIMITS.moqMax, 'MOQ_INVALID');
    const leadTimeDays = optInt(d.leadTimeDays, LIMITS.leadDaysMax, 'LEAD_TIME_INVALID');
    const customerNote = str(d.customerNote, LIMITS.noteMax);
    const internalNote = str(d.internalNote, LIMITS.noteMax);
    const quoteId = `q_${clientRequestId}`;

    const out = await db.runTransaction(async (t) => {
      const [snap, dispSnap, quoteSnap] = await Promise.all([
        t.get(ref), t.get(ref.collection('dispatches').doc(supplierId)), t.get(ref.collection('quotes').doc(quoteId)),
      ]);
      if (!snap.exists) throw fail('not-found', 'INQUIRY_NOT_FOUND');
      if (quoteSnap.exists) return { duplicate: true, ownerId: snap.data().ownerId };
      const inq = snap.data();
      if (!dispSnap.exists) throw fail('failed-precondition', 'NOT_DISPATCHED');
      if (!canTransition(inq.status, S.QUOTED)) throw fail('failed-precondition', 'INVALID_TRANSITION');
      if ((inq.quoteCount || 0) >= LIMITS.maxQuotesPerInquiry) throw fail('resource-exhausted', 'TOO_MANY_QUOTES');
      const common = { priceMinor, currency: d.currency, minOrderQty, leadTimeDays, createdAt: ts() };
      t.create(ref.collection('quotes').doc(quoteId), {
        ...common, supplierId, supplierName: dispSnap.data().supplierName, internalNote, customerNote,
        withdrawn: false, createdBy: actor,
      });
      t.create(ref.collection('offers').doc(quoteId), { ...common, customerNote, withdrawn: false });
      t.update(ref, {
        status: S.QUOTED,
        quoteCount: admin.firestore.FieldValue.increment(1),
        updatedAt: ts(),
      });
      event(t, ref, 'quote_added', actor, { supplierId, quoteId });
      return { duplicate: false, ownerId: inq.ownerId, refNo: inq.refNo };
    });

    if (!out.duplicate) {
      // Хабар муваффақиятсиз бўлса ҳам таклиф сақланган — хато логга (23-банд).
      try {
        const lang = await langOfPhone(db, out.ownerId);
        const m = render('china_quote_ready', lang, { refNo: out.refNo });
        await notifyUserInApp({
          userId: out.ownerId, title: m.title, body: m.body, category: 'info', source: 'china_inquiry',
          dataType: 'china_quote', screen: 'china_inquiry', extraData: { inquiryId: ref.id },
        });
      } catch (e) {
        log({ action: 'notify_quote', inquiryId: ref.id, result: 'error', errorCode: 'NOTIFY_FAILED', message: String(e && e.message).slice(0, 200) });
      }
    }
    log({ action: 'adminAddChinaQuote', userId: actor, inquiryId: ref.id, result: out.duplicate ? 'duplicate' : 'ok', durationMs: Date.now() - started });
    return { ok: true, quoteId, duplicate: out.duplicate };
  });

  /** Хато киритилган таклифни қайтариб олиш (мижоз ойнасида «бекор қилинган»). data: { inquiryId, quoteId, reason } */
  exportsObj.adminWithdrawChinaQuote = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const reason = reasonOf(data);
    const ref = db.collection(INQUIRIES).doc(docId(data && data.inquiryId, 'INQUIRY_NOT_FOUND'));
    const quoteId = docId(data && data.quoteId, 'QUOTE_NOT_FOUND');
    const out = await db.runTransaction(async (t) => {
      const [snap, qSnap, oSnap] = await Promise.all([
        t.get(ref), t.get(ref.collection('quotes').doc(quoteId)), t.get(ref.collection('offers').doc(quoteId)),
      ]);
      if (!snap.exists) throw fail('not-found', 'INQUIRY_NOT_FOUND');
      if (!qSnap.exists || !oSnap.exists) throw fail('not-found', 'QUOTE_NOT_FOUND');
      if (snap.data().status === S.CANCELLED) throw fail('failed-precondition', 'INVALID_TRANSITION');
      if (qSnap.data().withdrawn === true) return { changed: false };
      t.update(ref.collection('quotes').doc(quoteId), { withdrawn: true, withdrawnBy: actor, withdrawnAt: ts() });
      t.update(ref.collection('offers').doc(quoteId), { withdrawn: true });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'china_quote_withdraw', actor, target: `${ref.id}/${quoteId}`, reason, at: ts(),
      });
      event(t, ref, 'quote_withdrawn', actor, { quoteId });
      return { changed: true };
    });
    log({ action: 'adminWithdrawChinaQuote', userId: actor, inquiryId: ref.id, changed: out.changed, result: 'ok' });
    return { ok: true, ...out };
  });

  /** Оператор сўровни якунлайди. data: { inquiryId, reason } */
  exportsObj.adminCloseChinaInquiry = functions.https.onCall(async (data, context) => {
    const actor = await requireAdmin(context);
    const reason = reasonOf(data);
    const ref = db.collection(INQUIRIES).doc(docId(data && data.inquiryId, 'INQUIRY_NOT_FOUND'));
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) throw fail('not-found', 'INQUIRY_NOT_FOUND');
      const cur = snap.data().status;
      if (cur === S.CLOSED) return { changed: false };
      if (!canTransition(cur, S.CLOSED)) throw fail('failed-precondition', 'INVALID_TRANSITION');
      t.update(ref, { status: S.CLOSED, closedReason: reason, updatedAt: ts() });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'china_inquiry_close', actor, target: ref.id, reason, at: ts(),
      });
      event(t, ref, 'closed', actor, { reason });
      return { changed: true };
    });
    log({ action: 'adminCloseChinaInquiry', userId: actor, inquiryId: ref.id, changed: out.changed, result: 'ok' });
    return { ok: true, ...out };
  });
}

module.exports = {
  attachChinaInquiries, canTransition, stageAllows, mergeConfig,
  STAGES, TRANSITIONS, OPEN_STATUSES, CURRENCIES, LIMITS,
};
