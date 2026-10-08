/**
 * Modul sozlamasi («Ҳудудлар ва хизматлар») — SERVER orqali saqlash
 * (ega, 2026-10-08).
 *
 * Sabab: admin ekrani avval Global ustunning HAMMA modulini sahifa ochilgan
 * paytdagi holatdan qayta yozardi (eski tab = boshqa admin o'zgarishini
 * jimgina qaytarish) va kim/qachon nimani o'zgartirgani hech qayerda
 * qolmasdi — mahalliy taksi va marshrut qachon yopilganini tiklab bo'lmadi.
 *
 *  - faqat o'zgargan kataklar keladi: `{moduleId, from, to}`;
 *  - tranzaksiyada serverdagi joriy qiymat tekshiriladi: `from` → yoziladi,
 *    `to` → allaqachon shunday (qayta yuborish, idempotent), boshqasi →
 *    `MODULE_CONFIG_CONFLICT` va HECH NARSA yozilmaydi;
 *  - har saqlash `admin_audit`ga (kind `module_config_changed`) o'sha
 *    tranzaksiyada — konfig va audit birga yoziladi yoki birga yozilmaydi.
 *
 * Holat qiymatlari Dart `ModuleStatus.wire` bilan bir xil. Tuman/MFY
 * katagida `null` — «meros» (override yo'q, `manualModules`da emas).
 */
'use strict';

const STATUSES = ['enabled', 'coming_soon', 'soon', 'hidden'];
const SCOPES = ['global', 'district', 'area'];
const SOURCES = ['admin_ui', 'apk_module_sync'];
// `firestore.rules` `isAdmin()` (userHasAdminRole) bilan bir xil.
const ROLES = ['admin', 'superadmin', 'dispatcher'];
const MODULE_ID_RE = /^[a-z][a-z0-9_]{1,39}$/;
const TARGET_ID_RE = /^[A-Za-z0-9_-]{1,80}$/;
const MAX_CHANGES = 60;

/** Dart `ModuleStatus.fromWire` bilan bir xil (noma'lum → hidden). */
function normalizeStatus(raw) {
  switch (String(raw == null ? '' : raw).trim().toLowerCase()) {
    case 'enabled':
    case 'true':
      return 'enabled';
    case 'coming_soon':
    case 'comingsoon':
      return 'coming_soon';
    case 'soon':
      return 'soon';
    default:
      return 'hidden';
  }
}

/**
 * Hujjatdagi joriy holat. Global: modul yo'q → `null`. Tuman/MFY: ilova
 * faqat `manualModules`dagi kalitlarni o'qiydi — qolgani `null` (meros).
 */
function currentStatus(data, scope, moduleId) {
  const d = data || {};
  const modules = d.modules && typeof d.modules === 'object' ? d.modules : {};
  if (scope !== 'global') {
    const manual = Array.isArray(d.manualModules) ? d.manualModules.map(String) : [];
    if (!manual.includes(moduleId)) return null;
  }
  if (!Object.prototype.hasOwnProperty.call(modules, moduleId)) return null;
  const v = modules[moduleId];
  return normalizeStatus(v && typeof v === 'object' ? v.status : v);
}

/** `null` — meros; noto'g'ri qiymat — `undefined`. */
function parseStatus(v) {
  if (v === null) return null;
  return typeof v === 'string' && STATUSES.includes(v) ? v : undefined;
}

/** Kiruvchi so'rovni tekshirish; xato bo'lsa `{error}` qaytaradi. */
function parseRequest(data) {
  const d = data || {};
  if (!SCOPES.includes(d.scope)) return { error: 'SCOPE_INVALID' };
  const scope = d.scope;
  let targetId = '';
  if (scope !== 'global') {
    targetId = String(d.targetId || '').trim();
    if (!TARGET_ID_RE.test(targetId)) return { error: 'TARGET_INVALID' };
  }
  const raw = Array.isArray(d.changes) ? d.changes : [];
  if (raw.length > MAX_CHANGES) return { error: 'TOO_MANY_CHANGES' };
  const seen = new Set();
  const changes = [];
  for (const c of raw) {
    const moduleId = String((c && c.moduleId) || '').trim();
    if (!MODULE_ID_RE.test(moduleId) || seen.has(moduleId)) {
      return { error: 'MODULE_INVALID', moduleId };
    }
    seen.add(moduleId);
    const from = parseStatus(c.from);
    const to = parseStatus(c.to);
    // Global ustunda «meros» yo'q — u o'zi baza.
    if (from === undefined || to === undefined || (scope === 'global' && to === null)) {
      return { error: 'STATUS_INVALID', moduleId };
    }
    if (from === to) return { error: 'NO_CHANGE', moduleId };
    changes.push({ moduleId, from, to });
  }
  let enforce = null;
  if (d.enforce != null) {
    const e = d.enforce;
    if (scope !== 'global' || typeof e.from !== 'boolean' || typeof e.to !== 'boolean'
        || e.from === e.to) {
      return { error: 'ENFORCE_INVALID' };
    }
    enforce = { from: e.from, to: e.to };
  }
  if (!changes.length && !enforce) return { error: 'NO_CHANGES' };
  const source = SOURCES.includes(d.source) ? d.source : 'admin_ui';
  return { scope, targetId, changes, enforce, source };
}

function attachModuleConfig(exportsObj, deps) {
  const { functions, db, admin, callerPhone, canonicalUid } = deps;
  const HttpsError = functions.https.HttpsError;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const fail = (status, code, extra = {}) => new HttpsError(status, code, { code, ...extra });
  const log = (fields) => console.log(JSON.stringify({ module: 'module_config', ...fields }));

  function targetRef(req) {
    if (req.scope === 'global') return db.collection('config').doc('module_defaults');
    if (req.scope === 'district') return db.collection('geo_district_modules').doc(req.targetId);
    return db.collection('service_area_modules').doc(req.targetId);
  }

  /** Tuman/MFY hujjatiga yoziladigan geo maydonlar — serverdagi geo'dan. */
  async function geoFields(req) {
    if (req.scope === 'district') {
      const g = await db.collection('geo_districts').doc(req.targetId).get();
      if (!g.exists) throw fail('not-found', 'TARGET_NOT_FOUND');
      return { districtId: req.targetId, regionId: String(g.data().regionId || '') };
    }
    if (req.scope === 'area') {
      const a = await db.collection('service_areas').doc(req.targetId).get();
      if (!a.exists) throw fail('not-found', 'TARGET_NOT_FOUND');
      const ad = a.data() || {};
      return {
        serviceAreaId: req.targetId,
        districtId: String(ad.districtId || ''),
        regionId: String(ad.regionId || ''),
      };
    }
    return {};
  }

  exportsObj.adminSaveModuleConfig = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    if (!context || !context.auth) throw fail('unauthenticated', 'AUTH_REQUIRED');
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length < 12) throw fail('unauthenticated', 'PHONE_TOKEN_REQUIRED');
    const userSnap = await db.collection('users').doc(uid).get();
    const role = String((userSnap.data() || {}).role || 'user').trim().toLowerCase();
    if (!ROLES.includes(role)) throw fail('permission-denied', 'ADMIN_REQUIRED');

    const req = parseRequest(data);
    if (req.error) {
      throw fail('invalid-argument', req.error, req.moduleId ? { moduleId: req.moduleId } : {});
    }
    const ref = targetRef(req);
    const geo = await geoFields(req);

    let result;
    try {
      result = await db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        const cur = snap.exists ? (snap.data() || {}) : {};
        const apply = [];
        const conflicts = [];
        for (const c of req.changes) {
          const now = currentStatus(cur, req.scope, c.moduleId);
          if (now === c.from) apply.push(c);
          else if (now !== c.to) conflicts.push({ moduleId: c.moduleId, expected: c.from, actual: now });
        }
        let applyEnforce = null;
        if (req.enforce && (cur.enforce === true) === req.enforce.from) applyEnforce = req.enforce;
        if (conflicts.length) throw fail('failed-precondition', 'MODULE_CONFIG_CONFLICT', { conflicts });
        if (!apply.length && !applyEnforce) return { applied: 0, auditId: null };

        const modules = {};
        const patch = { modules, updatedAt: ts(), updatedBy: uid };
        if (req.scope === 'global') {
          for (const c of apply) modules[c.moduleId] = { status: c.to };
          if (applyEnforce) patch.enforce = applyEnforce.to;
        } else {
          const manual = new Set(
            (Array.isArray(cur.manualModules) ? cur.manualModules : []).map(String));
          for (const c of apply) {
            if (c.to === null) {
              manual.delete(c.moduleId);
              modules[c.moduleId] = admin.firestore.FieldValue.delete();
            } else {
              manual.add(c.moduleId);
              modules[c.moduleId] = { status: c.to };
            }
          }
          patch.manualModules = [...manual].sort();
          Object.assign(patch, geo);
        }
        t.set(ref, patch, { merge: true });

        const auditRef = db.collection('admin_audit').doc();
        t.create(auditRef, {
          kind: 'module_config_changed',
          actor: uid,
          actorRole: role,
          scope: req.scope,
          targetId: req.scope === 'global' ? 'module_defaults' : req.targetId,
          changes: apply,
          enforce: applyEnforce,
          source: req.source,
          at: ts(),
        });
        return { applied: apply.length + (applyEnforce ? 1 : 0), auditId: auditRef.id };
      });
    } catch (e) {
      const code = (e && e.details && e.details.code) || 'INTERNAL';
      log({
        action: 'adminSaveModuleConfig', result: 'error', errorCode: code, userId: uid,
        scope: req.scope, targetId: req.targetId, duration: Date.now() - started,
      });
      throw e;
    }
    log({
      action: 'adminSaveModuleConfig', result: 'ok', userId: uid, scope: req.scope,
      targetId: req.targetId, applied: result.applied, auditId: result.auditId,
      source: req.source, duration: Date.now() - started,
    });
    return { ok: true, ...result };
  });
}

module.exports = {
  attachModuleConfig,
  normalizeStatus,
  currentStatus,
  parseRequest,
};
