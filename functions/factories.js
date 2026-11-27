/**
 * «ИШЛАБ ЧИҚАРУВЧИ ЗАВОД/ФАБРИКАЛАР» (эга қарори 2026-11-28).
 *
 * Завод = мавжуд бизнес харитаси объекти `businesses/{id}` (category `manufacturing` — 30 турдан бири,
 * `business_directory.js` CATEGORIES). Янги коллекция ЙЎҚ (3/4-банд); бу модул фақат иккита сервер майдонини
 * ёзади (rules: `businesses` client-write ЁПИҚ):
 *
 *   factory: {                 — эганинг ЎЗ танлови (тизим таклиф қилади, завод ўзи ёқади)
 *     sellWholesale            Улгуржида сотиш (мавжуд `wholesale_sellers/{эга}` sellerType manufacturer — илова улайди)
 *     showVideos               саҳифада эганинг AVAGram видеолари
 *     publishVacancies         саҳифада ва «Вакансиялар»да шу заводнинг вакансиялари
 *     avaSupplierReady         «AVA'га таъминотчи бўлишга тайёрман» — фақат белги, админ кўради (буюртма мантиғи ЙЎҚ)
 *     avaSupplierReadyAt       белги ёқилган пайт (ўчирилса ўчирилади)
 *     updatedAt
 *   }
 *   producerVerification: {    — «Тасдиқланган ишлаб чиқарувчи» нишони
 *     status                   pending | approved | rejected
 *     requestedAt, decidedAt?, decidedBy? ('auto' | админ телефони), note?
 *   }
 *
 * Тасдиқлаш режими: `settings/app.producerVerifyAutoApprove` (true — AUTO: сўров дарҳол `approved`; йўқ/false —
 * MANUAL: `pending`, админ рўйхатидан қарор) — бошқа авто-тасдиқ калитлари каби. Ҳар қарор ва режим алмашуви
 * `admin_audit`га (41-банд): kind `producer_verification` / `producer_auto_approve_set`.
 *
 * Диагностика кодлари: BUSINESS_NOT_FOUND, BUSINESS_NOT_OWNER, BUSINESS_BLOCKED, FACTORY_NOT_MANUFACTURING,
 * FACTORY_OPTIONS_INVALID, VERIFY_DECISION_INVALID, REASON_REQUIRED.
 */
'use strict';

const COLLECTION = 'businesses';
const ADMIN_AUDIT = 'admin_audit';
const SETTINGS_DOC = 'settings/app';
const AUTO_KEY = 'producerVerifyAutoApprove';
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);
const FACTORY_CATEGORY = 'manufacturing';
const OPTION_KEYS = Object.freeze(['sellWholesale', 'showVideos', 'publishVacancies', 'avaSupplierReady']);
const VERIFY_STATUSES = Object.freeze(['pending', 'approved', 'rejected']);
const DOC_ID_RE = /^[A-Za-z0-9_-]{1,128}$/;

/** Келган танлов → 4 та bool (соф функция). Бирортаси bool бўлмаса — `null`. */
function normalizeOptions(raw) {
  const d = raw && typeof raw === 'object' ? raw : {};
  const out = {};
  for (const k of OPTION_KEYS) {
    if (typeof d[k] !== 'boolean') return null;
    out[k] = d[k];
  }
  return out;
}

/** Ҳозирги `factory` харитасидаги танлов (йўқ — ҳаммаси false). */
function currentOptions(cur) {
  const f = cur && cur.factory && typeof cur.factory === 'object' ? cur.factory : {};
  const out = {};
  for (const k of OPTION_KEYS) out[k] = f[k] === true;
  return out;
}

/**
 * Тасдиқ сўровининг кейинги ҳолати (соф функция): [cur] — ҳозирги `producerVerification.status` ('' йўқ).
 * Аллақачон pending/approved — ўзгармайди (`null`); йўқ ёки rejected — auto бўлса approved, акс ҳолда pending.
 */
function nextVerifyStatus(cur, auto) {
  if (cur === 'pending' || cur === 'approved') return null;
  return auto ? 'approved' : 'pending';
}

function attachFactories(exportsObj, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, requireCallerRoles,
  } = deps;
  const HttpsError = functions.https.HttpsError;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const fail = (status, code) => new HttpsError(status, code, { code });
  const log = (o) => console.log(JSON.stringify({ module: 'factories', ...o }));

  function requireUser(context) {
    if (!context || !context.auth) throw new HttpsError('unauthenticated', 'Authentication required');
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length < 12) throw new HttpsError('unauthenticated', 'Phone token required');
    return uid;
  }

  function businessRef(v) {
    const id = String(v == null ? '' : v).trim();
    if (!DOC_ID_RE.test(id)) throw fail('invalid-argument', 'BUSINESS_NOT_FOUND');
    return db.collection(COLLECTION).doc(id);
  }

  async function autoMode() {
    const s = await db.doc(SETTINGS_DOC).get();
    return (s.data() || {})[AUTO_KEY] === true;
  }

  /**
   * Эга: data { businessId, sellWholesale, showVideos, publishVacancies, avaSupplierReady, requestVerification? }
   * → { ok, changed, verification }. Идемпотент: ўша танлов қайта — ёзув йўқ (21-банд).
   */
  exportsObj.setMyFactoryOptions = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = requireUser(context);
    const d = data || {};
    const ref = businessRef(d.businessId);
    const options = normalizeOptions(d);
    if (!options) throw fail('invalid-argument', 'FACTORY_OPTIONS_INVALID');
    const wantVerify = d.requestVerification === true;
    const auto = wantVerify ? await autoMode() : false;
    let out;
    try {
      out = await db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        const cur = snap.exists ? (snap.data() || {}) : null;
        if (!cur) throw fail('not-found', 'BUSINESS_NOT_FOUND');
        if (cur.ownerId !== uid) throw fail('permission-denied', 'BUSINESS_NOT_OWNER');
        if (cur.status === 'blocked') throw fail('failed-precondition', 'BUSINESS_BLOCKED');
        if (cur.category !== FACTORY_CATEGORY) throw fail('failed-precondition', 'FACTORY_NOT_MANUFACTURING');
        const before = currentOptions(cur);
        const optsChanged = OPTION_KEYS.some((k) => before[k] !== options[k]);
        const curStatus = cur.producerVerification && VERIFY_STATUSES.includes(cur.producerVerification.status)
          ? cur.producerVerification.status : '';
        const nextStatus = wantVerify ? nextVerifyStatus(curStatus, auto) : null;
        if (!optsChanged && !nextStatus) return { changed: false, verification: curStatus };
        const patch = {};
        if (optsChanged) {
          patch.factory = {
            ...options,
            ...(options.avaSupplierReady
              ? { avaSupplierReadyAt: before.avaSupplierReady && cur.factory.avaSupplierReadyAt
                ? cur.factory.avaSupplierReadyAt : ts() }
              : {}),
            updatedAt: ts(),
          };
        }
        if (nextStatus) {
          patch.producerVerification = {
            status: nextStatus,
            requestedAt: ts(),
            ...(nextStatus === 'approved' ? { decidedAt: ts(), decidedBy: 'auto' } : {}),
          };
          if (nextStatus === 'approved') {
            t.set(db.collection(ADMIN_AUDIT).doc(), {
              kind: 'producer_verification', actor: 'auto', target: ref.id, from: curStatus || 'none',
              to: 'approved', reason: 'auto_approve', at: ts(),
            });
          }
        }
        t.update(ref, patch);
        return { changed: true, verification: nextStatus || curStatus };
      });
    } catch (e) {
      log({ action: 'setMyFactoryOptions', userId: uid, businessId: ref.id, result: 'error',
        errorCode: (e && e.details && e.details.code) || 'INTERNAL', durationMs: Date.now() - started });
      throw e;
    }
    log({ action: 'setMyFactoryOptions', userId: uid, businessId: ref.id, result: out.changed ? 'updated' : 'noop',
      verification: out.verification || 'none', durationMs: Date.now() - started });
    return { ok: true, ...out };
  });

  /**
   * Админ: data { businessId, decision: 'approved' | 'rejected', reason? (rejected — шарт, ≥ 3) }
   * → { ok, changed }. `admin_audit` (producer_verification). Ўша қарор қайта — ёзув йўқ.
   */
  exportsObj.adminSetProducerVerification = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const actor = await requireCallerRoles(context, ADMIN_ROLES, 'Admin role required');
    const d = data || {};
    const decision = String(d.decision || '');
    if (decision !== 'approved' && decision !== 'rejected') throw fail('invalid-argument', 'VERIFY_DECISION_INVALID');
    const reason = String(d.reason == null ? '' : d.reason).trim().slice(0, 300);
    if (decision === 'rejected' && reason.length < 3) throw fail('invalid-argument', 'REASON_REQUIRED');
    const ref = businessRef(d.businessId);
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const cur = snap.exists ? (snap.data() || {}) : null;
      if (!cur) throw fail('not-found', 'BUSINESS_NOT_FOUND');
      if (cur.category !== FACTORY_CATEGORY) throw fail('failed-precondition', 'FACTORY_NOT_MANUFACTURING');
      const pv = cur.producerVerification && typeof cur.producerVerification === 'object' ? cur.producerVerification : {};
      const from = VERIFY_STATUSES.includes(pv.status) ? pv.status : 'none';
      if (from === decision) return { changed: false };
      t.update(ref, {
        producerVerification: {
          status: decision,
          ...(pv.requestedAt ? { requestedAt: pv.requestedAt } : { requestedAt: ts() }),
          decidedAt: ts(),
          decidedBy: actor,
          ...(reason ? { note: reason } : {}),
        },
      });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'producer_verification', actor, target: ref.id, from, to: decision, reason, at: ts(),
      });
      return { changed: true };
    });
    log({ action: 'adminSetProducerVerification', userId: actor, businessId: ref.id, decision,
      result: out.changed ? 'updated' : 'noop', durationMs: Date.now() - started });
    return { ok: true, ...out };
  });

  /** Админ: data { enabled } → { ok, enabled, changed }. `settings/app.producerVerifyAutoApprove` + audit. */
  exportsObj.adminSetProducerAutoApprove = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, ADMIN_ROLES, 'Admin role required');
    const enabled = !!(data && data.enabled === true);
    const ref = db.doc(SETTINGS_DOC);
    const out = await db.runTransaction(async (t) => {
      const s = await t.get(ref);
      const raw = (s.data() || {})[AUTO_KEY];
      const was = raw === true;
      if (raw === enabled) return { changed: false };
      t.set(ref, { [AUTO_KEY]: enabled, updatedAt: ts() }, { merge: true });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'producer_auto_approve_set', actor, target: SETTINGS_DOC, from: was, to: enabled, at: ts(),
      });
      return { changed: true };
    });
    log({ action: 'adminSetProducerAutoApprove', userId: actor, enabled, result: out.changed ? 'updated' : 'noop' });
    return { ok: true, enabled, ...out };
  });
}

module.exports = {
  attachFactories, normalizeOptions, currentOptions, nextVerifyStatus,
  OPTION_KEYS, VERIFY_STATUSES, AUTO_KEY, FACTORY_CATEGORY,
};
