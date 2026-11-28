/**
 * Moderatsiya rejimlari (AVTO / QO'LDA) — YAGONA manba (ega 2026-11-28, takrorlanishlar auditi C-1 / 14-band).
 *
 * Avval: `settings/app` da 12 ta alohida `*AutoApprove` kaliti, har modul o'z o'quvchisini yozgan, ikki xil yozish
 * yo'li (callable vs admin klienti to'g'ridan-to'g'ri, auditsiz) va turli standart qiymat.
 *
 * Endi:
 *  - SAQLASH JOYI O'ZGARMAYDI: o'sha `settings/app.<field>` maydonlari (eski hujjatlar, rules, eski APK'lar ularni
 *    to'g'ridan-to'g'ri o'qiydi — migration KERAK EMAS, har bir kalitning hozirgi samarali qiymati saqlanadi).
 *  - O'qish: faqat `isModeAuto(settings, mode)` (standart qiymat registrdan).
 *  - Yozish: faqat `setModerationModeTx` (callable `adminSetModerationMode` + eski callable'lar shu orqali) —
 *    har o'zgarish `admin_audit` ga (41-band), bir xil qiymat — noop (21-band, idempotent).
 *
 * Samarali qiymat qoidasi (eski xatti-harakat AYNAN saqlangan):
 *  - `defaultOn: false` (11 ta) — faqat aniq `true` yoqadi; yo'q/null/'true'/1 — QO'LDA.
 *  - `defaultOn: true` (faqat `realty`) — faqat aniq `false` o'chiradi; yo'q/null — AVTO
 *    (`realty.js` dagi `appSetting(app,'realtyAutoApprove',true) !== false` bilan bir xil).
 *
 * ISTE'FODAGI kalitlar (`RETIRED_MODES`) — yozib bo'lmaydi, UI'da ko'rsatilmaydi:
 *  - `deviceBinding` — XAVFSIZLIK qarori (ega 2026-11-28): server sozlamani e'tiborsiz qoldiradi
 *    (`index.js` `isDeviceBindingAutoApproveEnabled`, `device_security.js`). Bu modul uni HECH QACHON yoqmaydi.
 *  - `restaurant` — server 2026-10-31 dan o'qimaydi (`restaurant_orders.js`).
 *
 * Diagnostik kodlar: MODE_UNKNOWN, MODE_RETIRED, MODE_ENABLED_INVALID, PERMISSION_DENIED, UNAUTHENTICATED.
 */
'use strict';

const SETTINGS_COLLECTION = 'settings';
const SETTINGS_DOC_ID = 'app';
const ADMIN_AUDIT = 'admin_audit';
const AUDIT_KIND = 'moderation_mode_set';

const PANEL_ROLES = Object.freeze(['admin', 'superadmin', 'dispatcher']);
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);

/**
 * Rejim → maydon. `roles` — HOZIRGI kim yoqib/o'chira olishi (o'zgartirilmadi):
 *  - dating/market/jobs — eski `assertAdmin` (admin, superadmin, dispatcher);
 *  - tv, shopItem, wholesaleProduct, wholesaleSeller, realty — eski rules `isAdmin()` (admin, superadmin, dispatcher);
 *  - producerVerify — `factories.js` ADMIN_ROLES; supermarketPartner — `supermarket.js` ADMIN_ROLES.
 */
const MODERATION_MODES = Object.freeze({
  dating: Object.freeze({ field: 'datingAutoApprove', defaultOn: false, roles: PANEL_ROLES }),
  market: Object.freeze({ field: 'marketAutoApprove', defaultOn: false, roles: PANEL_ROLES }),
  jobs: Object.freeze({ field: 'jobsAutoApprove', defaultOn: false, roles: PANEL_ROLES }),
  tv: Object.freeze({ field: 'tvAutoApprove', defaultOn: false, roles: PANEL_ROLES }),
  shopItem: Object.freeze({ field: 'shopItemAutoApprove', defaultOn: false, roles: PANEL_ROLES }),
  wholesaleProduct: Object.freeze({ field: 'wholesaleProductAutoApprove', defaultOn: false, roles: PANEL_ROLES }),
  wholesaleSeller: Object.freeze({ field: 'wholesaleSellerAutoApprove', defaultOn: false, roles: PANEL_ROLES }),
  realty: Object.freeze({ field: 'realtyAutoApprove', defaultOn: true, roles: PANEL_ROLES }),
  producerVerify: Object.freeze({ field: 'producerVerifyAutoApprove', defaultOn: false, roles: ADMIN_ROLES }),
  supermarketPartner: Object.freeze({ field: 'supermarketPartnerAutoApprove', defaultOn: false, roles: ADMIN_ROLES }),
});

const RETIRED_MODES = Object.freeze({
  deviceBinding: Object.freeze({ field: 'deviceBindingAutoApprove', reason: 'security_server_ignored_2026_11_28' }),
  restaurant: Object.freeze({ field: 'restaurantAutoApprove', reason: 'not_read_since_2026_10_31' }),
});

/** Barcha moderatsiya maydonlari (faol + iste'fodagi) — rules testi va UI uchun. */
const ALL_MODE_FIELDS = Object.freeze([
  ...Object.values(MODERATION_MODES).map((m) => m.field),
  ...Object.values(RETIRED_MODES).map((m) => m.field),
]);

function modeSpec(mode) {
  return Object.prototype.hasOwnProperty.call(MODERATION_MODES, mode) ? MODERATION_MODES[mode] : null;
}

/** Sof: `settings/app` ma'lumotidan rejim samarali qiymati. Noma'lum rejim — `false` (xavfsiz: qo'lda). */
function isModeAuto(settings, mode) {
  const spec = modeSpec(mode);
  if (!spec) return false;
  const v = settings && typeof settings === 'object' ? settings[spec.field] : undefined;
  return spec.defaultOn ? v !== false : v === true;
}

/** Sof: barcha faol rejimlar ko'rinishi (admin UI). */
function describeModes(settings) {
  const s = settings && typeof settings === 'object' ? settings : {};
  return Object.keys(MODERATION_MODES).map((mode) => {
    const spec = MODERATION_MODES[mode];
    const raw = s[spec.field];
    return {
      mode,
      field: spec.field,
      defaultOn: spec.defaultOn,
      enabled: isModeAuto(s, mode),
      stored: typeof raw === 'boolean' ? raw : null,
    };
  });
}

/** `db` + rejim → samarali qiymat (bitta hujjat o'qish). */
async function readModeAuto(db, mode) {
  const snap = await db.collection(SETTINGS_COLLECTION).doc(SETTINGS_DOC_ID).get();
  return isModeAuto(snap.data() || {}, mode);
}

/**
 * Tranzaksiyada rejimni o'rnatadi + audit. Bir xil SAMARALI qiymat — noop (yozuv ham, audit ham yo'q).
 * Qaytadi: { changed, from, to }.
 */
async function setModerationModeTx(db, admin, { mode, enabled, actor, reason, source }) {
  const spec = modeSpec(mode);
  if (!spec) throw new Error('MODE_UNKNOWN');
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const ref = db.collection(SETTINGS_COLLECTION).doc(SETTINGS_DOC_ID);
  return db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    const cur = snap.data() || {};
    const from = isModeAuto(cur, mode);
    // Samarali qiymat bir xil — noop (masalan realty: maydon yo'q = AVTO; AVTO qayta bosilsa yozilmaydi).
    if (from === enabled) return { changed: false, from, to: enabled };
    t.set(ref, {
      [spec.field]: enabled,
      [`${spec.field}UpdatedAt`]: ts(),
      [`${spec.field}UpdatedBy`]: actor,
      updatedAt: ts(),
    }, { merge: true });
    t.set(db.collection(ADMIN_AUDIT).doc(), {
      kind: AUDIT_KIND,
      mode,
      field: spec.field,
      from,
      to: enabled,
      actor,
      reason: reason || null,
      source: source || 'adminSetModerationMode',
      target: `${SETTINGS_COLLECTION}/${SETTINGS_DOC_ID}`,
      at: ts(),
    });
    return { changed: true, from, to: enabled };
  });
}

/**
 * Callable'lar:
 *  - `adminSetModerationMode` { mode, enabled, reason? } → { ok, mode, enabled, changed }
 *  - `adminGetModerationModes` {} → { ok, modes: describeModes(...) }
 * Eski `adminSet*AutoApprove` callable'lari o'z autentifikatsiyasini saqlaydi va `setModerationModeTx` ni chaqiradi.
 */
function attachModerationModes(exportsObj, deps) {
  const { functions, db, admin, requireCallerRoles } = deps;
  const HttpsError = functions.https.HttpsError;
  const fail = (status, code) => new HttpsError(status, code, { code });
  const log = (o) => console.log(JSON.stringify({ module: 'moderation_modes', ...o }));

  async function requireRoles(context, roles) {
    try {
      return await requireCallerRoles(context, roles, 'PERMISSION_DENIED');
    } catch (e) {
      if (e instanceof HttpsError) {
        throw fail(e.code, e.code === 'unauthenticated' ? 'UNAUTHENTICATED' : 'PERMISSION_DENIED');
      }
      throw e;
    }
  }

  async function setMode(data, context, source) {
    const started = Date.now();
    const d = data || {};
    const mode = String(d.mode || '');
    if (Object.prototype.hasOwnProperty.call(RETIRED_MODES, mode)) throw fail('failed-precondition', 'MODE_RETIRED');
    const spec = modeSpec(mode);
    if (!spec) throw fail('invalid-argument', 'MODE_UNKNOWN');
    if (typeof d.enabled !== 'boolean') throw fail('invalid-argument', 'MODE_ENABLED_INVALID');
    const actor = await requireRoles(context, spec.roles);
    const reason = typeof d.reason === 'string' ? d.reason.trim().slice(0, 300) : '';
    const out = await setModerationModeTx(db, admin, { mode, enabled: d.enabled, actor, reason, source });
    log({ action: source, userId: actor, mode, enabled: d.enabled,
      result: out.changed ? 'updated' : 'noop', durationMs: Date.now() - started });
    return { ok: true, mode, enabled: d.enabled, changed: out.changed };
  }

  exportsObj.adminSetModerationMode = functions.https.onCall(
    (data, context) => setMode(data, context, 'adminSetModerationMode'));

  exportsObj.adminGetModerationModes = functions.https.onCall(async (data, context) => {
    await requireRoles(context, PANEL_ROLES);
    const snap = await db.collection(SETTINGS_COLLECTION).doc(SETTINGS_DOC_ID).get();
    return { ok: true, modes: describeModes(snap.data() || {}) };
  });

  return { readModeAuto: (mode) => readModeAuto(db, mode) };
}

module.exports = {
  MODERATION_MODES,
  RETIRED_MODES,
  ALL_MODE_FIELDS,
  AUDIT_KIND,
  isModeAuto,
  describeModes,
  readModeAuto,
  setModerationModeTx,
  attachModerationModes,
};
