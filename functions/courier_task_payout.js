/**
 * KURYER VAZIFA HAQI - gilam yuvish / agro qabul / yig'ib olish (D5, ega qarori 2026-10-16).
 *
 * Qaror: kuryerning bu vazifalar uchun haqi - vazifa narxidan FOIZ (butun bps),
 * admin panelda tahrirlanadi. Standart foiz YO'Q (CLAUDE.md 1, 9): foiz
 * sozlanmagan bo'lsa haq HISOBLANMAYDI (`payout: null`, sabab yoziladi).
 *
 * Sozlama hujjati `settings/courier_task_payout`:
 *   { version, modules: { carpet: {bps}, agro: {bps}, collection: {bps} },
 *     reason, updatedAt, updatedBy }
 * Har haqiqiy o'zgarish yangi `version` + o'zgarmas tarix
 * `courier_task_payout_history/v{n}` (previous bilan) + `admin_audit`
 * (`courier_task_payout_pct`) - bitta tranzaksiyada (9, 16, 41-qoida).
 * Haq hujjatidagi `version` = hisoblash paytidagi sozlama hujjati versiyasi.
 *
 * Hisob: `courierPayout = floor(base * bps / 10000)`, butun so'm (8-qoida).
 * floor: ijrochi haqi platformaga zarar qilmaydi (`tariff.splitInternal` bilan bir xil:
 * platforma ulushi ceil, ijrochi haqi floor).
 * Baza (mijoz haqiqatda to'laydigan narx, CLAUDE.md 14 - alohida maydon):
 *   carpet     -> carpet_wash_orders.finalPrice (admin qo'yadi)
 *   agro       -> agro_pickup_orders.finalPrice (admin qo'yadi)
 *   collection -> collection_tasks.finalValue   (server hisoblaydi; bu yerda AVA
 *                 mijozga TO'LAYDI - "mijoz to'laydigan narx" ma'nosi yo'q, qiymat
 *                 asos qilib olindi: UNKNOWN/NEEDS CONFIRMATION)
 *
 * MAXFIYLIK (CLAUDE.md 14, 40): kuryer haqi - ICHKI xarajat. Vazifa hujjatlarini
 * (carpet_wash_orders / agro_pickup_orders / collection_tasks) mijoz (yig'ib olishda
 * kuryer ham) to'liq o'qiydi - shuning uchun haq vazifa hujjatiga YOZILMAYDI. U
 * serverga xos courier_task_payouts/{modul}_{vazifaId} hujjatiga yoziladi: bu
 * kolleksiyaga firestore.rules'da match YO'Q = klient uchun o'qish ham, yozish ham
 * taqiqlangan (default-deny; faqat Admin SDK). Test: courier_task_payout_rules.test.js.
 *
 * PUL HARAKATI YO'Q: bu modul ledger/hamyonga HECH NIMA yozmaydi - faqat hisoblangan
 * qiymatni alohida hujjatga muhrlaydi (buxgalteriya hisobi - ochiq savol).
 */
'use strict';

const MODULE_KEYS = Object.freeze(['carpet', 'agro', 'collection']);
const SETTINGS_DOC = Object.freeze(['settings', 'courier_task_payout']);
const HISTORY_COLLECTION = 'courier_task_payout_history';
const PAYOUT_COLLECTION = 'courier_task_payouts';
const ADMIN_AUDIT = 'admin_audit';
const BPS_MIN = 0;
const BPS_MAX = 10000;

const isInt = (n) => typeof n === 'number' && Number.isInteger(n);
const isBps = (n) => isInt(n) && n >= BPS_MIN && n <= BPS_MAX;

function codeError(code, status, details) {
  const e = new Error(code);
  e.code = code;
  e.status = status || 'invalid-argument';
  e.details = { code, ...(details || {}) };
  return e;
}

/** floor(base * bps / 10000); noto'g'ri kirish -> null. Faqat HAQIQIY butun sonlar. */
function computePayout(base, bps) {
  if (!isInt(base) || base <= 0 || !isBps(bps)) return null;
  const product = base * bps;
  return (product - (product % 10000)) / 10000;
}

/** Sozlangan foiz va hujjat versiyasi; sozlanmagan / noto'g'ri -> null (standart YO'Q). */
function resolveRate(settingsDoc, moduleKey) {
  if (!MODULE_KEYS.includes(moduleKey)) return null;
  const d = settingsDoc && typeof settingsDoc === 'object' ? settingsDoc : null;
  const modules = d && d.modules && typeof d.modules === 'object' ? d.modules : null;
  const entry = modules && Object.prototype.hasOwnProperty.call(modules, moduleKey) ? modules[moduleKey] : null;
  if (!entry || typeof entry !== 'object' || !isBps(entry.bps)) return null;
  return { bps: entry.bps, version: isInt(d.version) && d.version >= 0 ? d.version : 0 };
}

/** `courier_task_payouts` hujjat id: `{modul}_{vazifaId}` (bir vazifa - bitta hujjat). */
function payoutDocId(moduleKey, taskId) {
  if (!MODULE_KEYS.includes(moduleKey)) throw codeError('MODULE_INVALID', 'invalid-argument', { allowed: [...MODULE_KEYS] });
  const id = typeof taskId === 'string' ? taskId : '';
  if (!id || id.includes('/')) throw codeError('TASK_ID_INVALID', 'invalid-argument');
  return `${moduleKey}_${id}`;
}

/**
 * `courier_task_payouts/{modul}_{vazifaId}` hujjat maydonlari (computedAt chaqiruvchida qo'shiladi).
 * Sabab: narx noma'lum -> `price_unknown`; foiz yo'q -> `not_configured`.
 * VAZIFA hujjatiga yozilmaydi (maxfiylik, yuqoriga qarang).
 */
function buildPayout(moduleKey, taskId, base, settingsDoc, courierId) {
  const rate = resolveRate(settingsDoc, moduleKey);
  const baseOk = isInt(base) && base > 0;
  const docVersion = settingsDoc && isInt(settingsDoc.version) && settingsDoc.version >= 0 ? settingsDoc.version : 0;
  let reason = null;
  if (!baseOk) reason = 'price_unknown';
  else if (!rate) reason = 'not_configured';
  return {
    module: moduleKey,
    taskId: String(taskId || ''),
    courierId: String(courierId || ''),
    payout: reason ? null : computePayout(base, rate.bps),
    bps: rate ? rate.bps : null,
    version: rate ? rate.version : docVersion,
    base: baseOk ? base : null,
    reason,
  };
}

/** Tranzaksiyada haq hujjati havolasi (o'qish ham, yozish ham shu orqali). */
function payoutRef(db, moduleKey, taskId) {
  return db.collection(PAYOUT_COLLECTION).doc(payoutDocId(moduleKey, taskId));
}

/**
 * Haq hujjatini YOZISH (tranzaksiyaning yozuv fazasida). `previous` - qayta hisoblashda
 * avvalgi qiymat izi (16-qoida: eski hisob yo'qolmasin), birinchi yozuvda berilmaydi.
 */
function writePayoutInTx(t, db, moduleKey, taskId, payout, computedAt, previous) {
  const doc = { ...payout, computedAt };
  if (previous) doc.previous = previous;
  t.set(payoutRef(db, moduleKey, taskId), doc);
}
/** Admin kirishi: modul + bps (null = sozlamani olib tashlash). */
function validatePctInput(data) {
  const d = data && typeof data === 'object' ? data : {};
  const moduleKey = typeof d.module === 'string' ? d.module : '';
  if (!MODULE_KEYS.includes(moduleKey)) throw codeError('MODULE_INVALID', 'invalid-argument', { allowed: [...MODULE_KEYS] });
  if (d.bps === null) return { module: moduleKey, bps: null };
  if (!isBps(d.bps)) throw codeError('COURIER_PAYOUT_BPS_INVALID', 'invalid-argument', { min: BPS_MIN, max: BPS_MAX });
  return { module: moduleKey, bps: d.bps };
}

/**
 * Yakun tranzaksiyasi uchun yordamchi: sozlamani O'QISH fazasida o'qiydi.
 * (Admin SDK tranzaksiyasi: barcha o'qishlar yozuvdan OLDIN bo'lishi shart.)
 */
async function readSettingsInTx(t, db) {
  const snap = await t.get(db.collection(SETTINGS_DOC[0]).doc(SETTINGS_DOC[1]));
  return snap.exists ? (snap.data() || {}) : null;
}

/** Tranzaksiyadan KEYIN: tuzilgan jurnal (telefon/ism YO'Q - 24, 40-qoida). */
function logPayout(moduleKey, taskId, fields, extra) {
  const base = {
    action: 'courierTaskPayout', module: moduleKey, taskId: String(taskId || ''),
    base: fields.base, bps: fields.bps,
    settingsVersion: fields.version, payout: fields.payout, ...(extra || {}),
  };
  if (fields.reason) {
    console.warn(JSON.stringify({
      ...base, result: 'skipped',
      errorCode: fields.reason === 'price_unknown'
        ? 'COURIER_PAYOUT_PRICE_UNKNOWN' : 'COURIER_PAYOUT_NOT_CONFIGURED',
    }));
  } else {
    console.log(JSON.stringify({ ...base, result: 'computed' }));
  }
}

function attachCourierTaskPayout(exportsObj, deps) {
  const { functions, db, admin, requireCallerRoles } = deps;
  const { HttpsError } = functions.https;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const ROLES = ['admin', 'superadmin'];

  function toHttps(e) {
    if (e instanceof HttpsError) return e;
    if (e && e.status && e.details) return new HttpsError(e.status, e.code, e.details);
    return e;
  }

  const view = (d) => {
    const doc = d || {};
    const modules = {};
    for (const k of MODULE_KEYS) {
      const r = resolveRate(doc, k);
      modules[k] = r ? { bps: r.bps } : null;
    }
    const at = doc.updatedAt && typeof doc.updatedAt.toMillis === 'function' ? doc.updatedAt.toMillis() : null;
    return {
      version: isInt(doc.version) ? doc.version : 0,
      modules,
      updatedAtMs: at,
      updatedBy: typeof doc.updatedBy === 'string' ? doc.updatedBy : '',
    };
  };

  /** Admin - joriy sozlama (hujjat yo'q bo'lsa hammasi `null`, versiya 0). */
  exportsObj.adminGetCourierTaskPayoutSettings = functions.https.onCall(async (data, context) => {
    await requireCallerRoles(context, ROLES, 'Admin role required');
    const snap = await db.collection(SETTINGS_DOC[0]).doc(SETTINGS_DOC[1]).get();
    return { ok: true, ...view(snap.exists ? snap.data() : null) };
  });

  /**
   * Admin - bitta modul uchun foiz. data: { module: 'carpet'|'agro'|'collection',
   * bps: butun 0..10000 | null (null = "sozlanmagan"ga qaytarish), reason }.
   * Bir xil qiymat qayta yuborilsa - versiya OCHILMAYDI (`unchanged: true`).
   */
  exportsObj.adminSetCourierTaskPayoutPct = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, ROLES, 'Admin role required');
    let input;
    try {
      input = validatePctInput(data);
    } catch (e) {
      throw toHttps(e);
    }
    const reason = String((data && data.reason) || '').trim().slice(0, 300);
    const ref = db.collection(SETTINGS_DOC[0]).doc(SETTINGS_DOC[1]);
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const cur = snap.exists ? (snap.data() || {}) : {};
      const prevVersion = isInt(cur.version) ? cur.version : 0;
      const curRate = resolveRate(cur, input.module);
      const curBps = curRate ? curRate.bps : null;
      if (curBps === input.bps) {
        return { version: prevVersion, unchanged: true, module: input.module, bps: curBps };
      }
      const next = prevVersion + 1;
      const modules = { ...((cur.modules && typeof cur.modules === 'object') ? cur.modules : {}) };
      if (input.bps === null) delete modules[input.module];
      else modules[input.module] = { bps: input.bps };
      const doc = { modules, version: next, reason, updatedAt: ts(), updatedBy: actor };
      t.set(ref, doc);
      t.create(db.collection(HISTORY_COLLECTION).doc(`v${next}`), {
        ...doc,
        changedModule: input.module,
        previous: { version: prevVersion, bps: curBps, modules: (cur.modules && typeof cur.modules === 'object') ? cur.modules : {} },
        changedBy: actor,
        changedAt: ts(),
      });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'courier_task_payout_pct', actor, target: SETTINGS_DOC.join('/'),
        from: String(prevVersion), to: String(next), reason,
        detail: { module: input.module, bps: input.bps, prevBps: curBps },
        at: ts(),
      });
      return { version: next, unchanged: false, module: input.module, bps: input.bps };
    });
    console.log(JSON.stringify({
      action: 'adminSetCourierTaskPayoutPct', result: 'ok', module: out.module, version: out.version,
      unchanged: out.unchanged, userId: actor,
    }));
    return { ok: true, ...out };
  });
}

module.exports = {
  MODULE_KEYS,
  SETTINGS_DOC,
  HISTORY_COLLECTION,
  PAYOUT_COLLECTION,
  BPS_MIN,
  BPS_MAX,
  computePayout,
  resolveRate,
  buildPayout,
  payoutDocId,
  payoutRef,
  writePayoutInTx,
  validatePctInput,
  readSettingsInTx,
  logPayout,
  attachCourierTaskPayout,
};
