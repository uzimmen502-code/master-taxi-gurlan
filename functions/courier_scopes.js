'use strict';

/**
 * KURYER TOIFALARI — tuman / viloyat / respublika (ega qarorlari 2026-10-31,
 * docs/kuryer_qarorlar_loyiha_2026-10-31_uz.md, 3-bo'lim + A-4):
 *   - kuryer toifani O'ZI tanlaydi, bir nechtasini olishi mumkin;
 *   - «Туман» (`district`) — darhol faol (tekshiruvsiz);
 *   - «Вилоят» (`region`) va «Республика» (`republic`) — MASHINA va hujjat shart
 *     (`courier_documents/{uid}`), admin tasdiqlaydi; adminda Avto/Mануал tugmasi
 *     (`settings/courier.scopeApprovalMode`, standart `manual`).
 *
 * Saqlanishi (yangi kolleksiya yo'q):
 *   - `provider_capabilities/{accountId}.courier.scopes` — kuryer TANLAGAN toifalar (klient ham yoza oladi —
 *     u o'zicha hech narsa bermaydi);
 *   - `provider_capabilities/{accountId}.review.courierScopes.{region|republic}` — TASDIQ holati.
 *     `review` — server kaliti (firestore.rules `capabilityServerKeysUntouched`), klient yozolmaydi.
 *   - `courier_documents/{uid12}` — mashina/hujjat ma'lumoti (egasi yozadi; `verified*` faqat admin).
 *
 * Faollik (server hisoblaydi, 18-qoida): `district` — tanlangan bo'lsa; `region`/`republic` — tanlangan VA
 * `review.courierScopes.<scope>.status === 'approved'`. `courier.scopes` YO'Q eski hujjat = `['district']`
 * (orqaga moslik: avvalgi xatti-harakat — kuryer mahalliy ishni oladi).
 */

const SCOPES = Object.freeze(['district', 'region', 'republic']);
const LOCAL_SCOPE = 'district';
const REVIEWED_SCOPES = Object.freeze(['region', 'republic']);
const APPROVAL_MODES = Object.freeze(['manual', 'auto']);
const DEFAULT_APPROVAL_MODE = 'manual';
const REVIEW_STATUSES = Object.freeze({ pending: 'pending', approved: 'approved', rejected: 'rejected' });

// ── sof yordamchilar (test: courier_scopes_pure.test.js) ─────────────────

/** Kuryer TANLAGAN toifalar. Maydon yo'q / bo'sh emas massiv emas → ['district'] (eski hujjatlar). */
function requestedScopes(capDoc) {
  const raw = capDoc && capDoc.courier && capDoc.courier.scopes;
  if (!Array.isArray(raw)) return [LOCAL_SCOPE];
  return SCOPES.filter((s) => raw.includes(s));
}

/** Tasdiq holati (`region`/`republic`) — `pending` | `approved` | `rejected` | ''. */
function reviewStatus(capDoc, scope) {
  const r = capDoc && capDoc.review && capDoc.review.courierScopes && capDoc.review.courierScopes[scope];
  return r && typeof r.status === 'string' ? r.status : '';
}

/** Toifa FAOLmi (kuryer shu toifadagi ishni olishi mumkinmi). */
function isScopeActive(capDoc, scope) {
  if (!SCOPES.includes(scope)) return false;
  if (!requestedScopes(capDoc).includes(scope)) return false;
  if (scope === LOCAL_SCOPE) return true;
  return reviewStatus(capDoc, scope) === REVIEW_STATUSES.approved;
}

/** Viloyat/respublika uchun talab: mashina + raqam + model + guvohnoma raqami. Yetishmaganlar ro'yxati. */
function missingRequirements(docsDoc) {
  const d = docsDoc || {};
  const missing = [];
  if (String(d.vehicleType || '') !== 'car') missing.push('vehicleType');
  for (const k of ['carPlate', 'carModel', 'driverLicenseNo']) {
    if (!(typeof d[k] === 'string' && d[k].trim().length >= 2)) missing.push(k);
  }
  return missing;
}

/** Kiruvchi `scopes` → toza ro'yxat yoki xato kodi. */
function parseScopes(raw) {
  if (!Array.isArray(raw) || raw.length < 1 || raw.length > SCOPES.length) return { error: 'SCOPES_INVALID' };
  const set = new Set();
  for (const s of raw) {
    if (!SCOPES.includes(s)) return { error: 'SCOPES_INVALID' };
    set.add(s);
  }
  return { scopes: SCOPES.filter((s) => set.has(s)) };
}

function approvalModeOf(settingsDoc) {
  const m = settingsDoc && settingsDoc.scopeApprovalMode;
  return APPROVAL_MODES.includes(m) ? m : DEFAULT_APPROVAL_MODE;
}

// ── Cloud Functions ──────────────────────────────────────────────────────

/**
 * @param {object} exportsObj `exports`
 * @param {object} deps { functions, db, admin, callerPhone, canonicalUid, requireCallerRoles, caps }
 */
function attachCourierScopes(exportsObj, deps) {
  const { functions, db, admin, callerPhone, canonicalUid, requireCallerRoles, caps } = deps;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const fail = (code, msg, details) => new functions.https.HttpsError(code, msg, { code: msg, ...(details || {}) });
  const log = (o) => console.log(JSON.stringify({ module: 'courier_scopes', ...o }));
  const settingsRef = () => db.collection('settings').doc('courier');

  /** Chaqiruvchi → { uid12, accountId, capRef } yoki xato. */
  async function callerCapability(context) {
    if (!context || !context.auth) throw fail('unauthenticated', 'AUTH_REQUIRED');
    const uid = canonicalUid(callerPhone(context));
    if (!/^998\d{9}$/.test(uid)) throw fail('unauthenticated', 'PHONE_TOKEN_REQUIRED');
    let accountId = '';
    for (const id of [uid, uid.slice(3)]) {
      const u = await db.collection('users').doc(id).get();
      if (u.exists) { accountId = String((u.data() || {}).accountId || ''); break; }
    }
    if (!accountId) throw fail('failed-precondition', 'NOT_A_COURIER');
    return { uid, accountId, capRef: db.collection('provider_capabilities').doc(accountId) };
  }

  /**
   * Kuryer toifalarini tanlaydi. data: { scopes: ['district'|'region'|'republic', ...] }.
   * Faqat ishlayotgan kuryer (`isWorking`). Viloyat/respublika — `courier_documents` talabi; rejim `auto` →
   * darhol `approved`, `manual` → `pending` (avval tasdiqlangan bo'lsa — o'zgarmaydi). Idempotent.
   */
  exportsObj.courierRequestScopes = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const { uid, accountId, capRef } = await callerCapability(context);
    const parsed = parseScopes(data && data.scopes);
    if (parsed.error) throw fail('invalid-argument', parsed.error);
    const wanted = parsed.scopes;
    const needsReview = wanted.filter((s) => REVIEWED_SCOPES.includes(s));

    const docsSnap = needsReview.length ? await db.collection('courier_documents').doc(uid).get() : null;
    if (needsReview.length) {
      const missing = missingRequirements(docsSnap && docsSnap.exists ? docsSnap.data() : null);
      if (missing.length) throw fail('failed-precondition', 'SCOPE_REQUIREMENTS_MISSING', { missing });
    }

    const out = await db.runTransaction(async (t) => {
      const [capSnap, setSnap] = await Promise.all([t.get(capRef), t.get(settingsRef())]);
      if (!capSnap.exists) throw fail('failed-precondition', 'NOT_A_COURIER');
      const cap = capSnap.data() || {};
      const status = caps.statusOf(cap, 'courier');
      if (!caps.isWorking('courier', status)) throw fail('permission-denied', 'COURIER_NOT_WORKING');
      const mode = approvalModeOf(setSnap.exists ? setSnap.data() : null);
      const patch = { 'courier.scopes': wanted, 'courier.updatedAt': ts(), updatedAt: ts() };
      const result = {};
      for (const s of REVIEWED_SCOPES) {
        if (!wanted.includes(s)) continue;
        const prev = reviewStatus(cap, s);
        if (prev === REVIEW_STATUSES.approved) { result[s] = prev; continue; }
        if (prev === REVIEW_STATUSES.pending && mode === 'manual') { result[s] = prev; continue; }
        const next = mode === 'auto' ? REVIEW_STATUSES.approved : REVIEW_STATUSES.pending;
        patch[`review.courierScopes.${s}`] = {
          status: next, requestedAt: ts(), mode,
          ...(next === REVIEW_STATUSES.approved ? { decidedAt: ts(), decidedBy: 'auto' } : {}),
        };
        t.create(db.collection('capability_audit').doc(), {
          accountId, service: 'courier_scope', scope: s, from: prev || 'none', to: next,
          reason: mode === 'auto' ? 'auto_mode' : 'requested', by: uid, at: ts(), kind: 'scope_request',
        });
        result[s] = next;
      }
      t.update(capRef, patch);
      return { scopes: wanted, review: result, mode };
    });
    log({ action: 'courierRequestScopes', userId: uid, accountId, scopes: out.scopes, review: out.review,
      result: 'ok', duration: Date.now() - started });
    return { ok: true, ...out };
  });

  /** Admin: viloyat/respublika so'rovini tasdiqlash/rad etish. data: { accountId, scope, decision, reason }. */
  exportsObj.adminDecideCourierScope = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, ['admin', 'superadmin'], 'Admin role required');
    const d = data || {};
    const accountId = String(d.accountId || '').trim();
    const scope = String(d.scope || '');
    const decision = String(d.decision || '');
    const reason = String(d.reason || '').slice(0, 300);
    if (!accountId || !/^[A-Za-z0-9_-]{1,64}$/.test(accountId)) throw fail('invalid-argument', 'ACCOUNT_INVALID');
    if (!REVIEWED_SCOPES.includes(scope)) throw fail('invalid-argument', 'SCOPE_INVALID');
    if (!['approve', 'reject'].includes(decision)) throw fail('invalid-argument', 'DECISION_INVALID');
    if (decision === 'reject' && !reason) throw fail('invalid-argument', 'REASON_REQUIRED');
    const capRef = db.collection('provider_capabilities').doc(accountId);
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(capRef);
      if (!snap.exists) throw fail('not-found', 'NOT_A_COURIER');
      const cap = snap.data() || {};
      const prev = reviewStatus(cap, scope);
      if (!prev) throw fail('failed-precondition', 'NO_SCOPE_REQUEST');
      const next = decision === 'approve' ? REVIEW_STATUSES.approved : REVIEW_STATUSES.rejected;
      if (prev === next) return { status: next, unchanged: true };
      const prevEntry = (cap.review && cap.review.courierScopes && cap.review.courierScopes[scope]) || {};
      t.update(capRef, {
        [`review.courierScopes.${scope}`]: {
          ...prevEntry, status: next, decidedAt: ts(), decidedBy: actor, reason,
        },
        updatedAt: ts(),
      });
      t.create(db.collection('capability_audit').doc(), {
        accountId, service: 'courier_scope', scope, from: prev, to: next, reason, by: actor, at: ts(),
        kind: 'scope_decision',
      });
      t.create(db.collection('admin_audit').doc(), {
        kind: 'courier_scope_decision', actor, target: `provider_capabilities/${accountId}`,
        from: prev, to: next, reason, detail: { scope }, at: ts(),
      });
      return { status: next, unchanged: false };
    });
    log({ action: 'adminDecideCourierScope', userId: actor, accountId, scope, result: 'ok', status: out.status });
    return { ok: true, ...out };
  });

  /** Admin: Avto/Мануал. data: { mode: 'auto'|'manual', reason? }. */
  exportsObj.adminSetCourierScopeApprovalMode = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, ['admin', 'superadmin'], 'Admin role required');
    const mode = String((data && data.mode) || '');
    if (!APPROVAL_MODES.includes(mode)) throw fail('invalid-argument', 'MODE_INVALID');
    const reason = String((data && data.reason) || '').slice(0, 300);
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(settingsRef());
      const prev = approvalModeOf(snap.exists ? snap.data() : null);
      if (prev === mode && snap.exists && snap.data().scopeApprovalMode === mode) return { mode, unchanged: true };
      t.set(settingsRef(), { scopeApprovalMode: mode, scopeApprovalModeUpdatedAt: ts(), scopeApprovalModeUpdatedBy: actor },
        { merge: true });
      t.create(db.collection('admin_audit').doc(), {
        kind: 'courier_scope_approval_mode', actor, target: 'settings/courier', from: prev, to: mode, reason, at: ts(),
      });
      return { mode, unchanged: false };
    });
    log({ action: 'adminSetCourierScopeApprovalMode', userId: actor, mode, result: 'ok' });
    return { ok: true, ...out };
  });

  /** Admin: kutayotgan (yoki berilgan holatdagi) viloyat/respublika so'rovlari. data: { status? }. */
  exportsObj.adminListCourierScopeRequests = functions.https.onCall(async (data, context) => {
    await requireCallerRoles(context, ['admin', 'superadmin', 'dispatcher'], 'Admin role required');
    const status = Object.values(REVIEW_STATUSES).includes(data && data.status) ? data.status : REVIEW_STATUSES.pending;
    const rows = new Map();
    for (const scope of REVIEWED_SCOPES) {
      const snap = await db.collection('provider_capabilities')
        .where(`review.courierScopes.${scope}.status`, '==', status).limit(200).get();
      for (const d of snap.docs) {
        const cap = d.data() || {};
        const row = rows.get(d.id) || {
          accountId: d.id,
          phone: String((cap.identity && cap.identity.primaryUid) || ''),
          scopes: requestedScopes(cap),
          requests: {},
        };
        const e = cap.review.courierScopes[scope] || {};
        row.requests[scope] = {
          status: e.status || '',
          requestedAt: e.requestedAt && e.requestedAt.toMillis ? e.requestedAt.toMillis() : null,
          reason: e.reason || '',
        };
        rows.set(d.id, row);
      }
    }
    const list = [...rows.values()];
    // Mashina ma'lumoti — admin qaror qilishi uchun (faqat admin ko'radi; PII minimal, 40-qoida).
    for (const r of list) {
      if (!r.phone) continue;
      const doc = await db.collection('courier_documents').doc(r.phone).get();
      const x = doc.exists ? (doc.data() || {}) : {};
      r.vehicle = {
        vehicleType: String(x.vehicleType || ''), carPlate: String(x.carPlate || ''),
        carModel: String(x.carModel || ''), driverLicenseNo: String(x.driverLicenseNo || ''),
      };
    }
    return { ok: true, status, items: list };
  });
}

module.exports = {
  SCOPES, LOCAL_SCOPE, REVIEWED_SCOPES, APPROVAL_MODES, DEFAULT_APPROVAL_MODE, REVIEW_STATUSES,
  requestedScopes, reviewStatus, isScopeActive, missingRequirements, parseScopes, approvalModeOf,
  attachCourierScopes,
};
