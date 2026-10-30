'use strict';

/**
 * ULGURJI BUYURTMA ZANJIRI — 5-bosqich (admin), demand codebase (europe-west1).
 * Hujjat: docs/ulgurji_buyurtma_zanjiri_uz.md (Q-7: ichki sinov rejimi, tester'lar;
 * hammaga ochish — ega qarori).
 *
 *   adminGetWholesaleOrdersStage()   darvoza holati (admin paneli uchun)
 *   adminSetWholesaleOrdersStage({enabled?, stage?, addTesterIds?, removeTesterIds?, reason})
 *
 * Darvoza hujjati — `module_config/wholesale_orders_all` `{enabled, stage, testerIds}`:
 * AYNAN shu maydonlarni `api/wholesale_orders.js` `requireOrdersGate` (kvota) o'qiydi —
 * `enabled !== true` = yopiq; bosqich qoidasi relay bilan bitta (`core/logistics.js`
 * `stageOf` / `isStageAllowed`; noma'lum bosqich = `internal`).
 *
 * NEGA CALLABLE: `module_config` rules'da `isAdmin()` (dispatcher ham) to'g'ridan-to'g'ri
 * yoza oladi va audit yo'q. Bu yerda: faqat admin/superadmin (`assertStrictAdmin` —
 * `setWholesaleOrderSettings` / `adminSetLogisticsStage` bilan bir xil, 19-band),
 * kanonik telefon ID, tranzaksiya (22), idempotent (21: o'zgarish yo'q — yozuv ham,
 * audit ham yo'q), APPEND-ONLY `admin_audit` (41; klientga yopiq). Telefonlar auditga
 * va setter javobiga CHIQMAYDI (faqat soni, 40-band) — `adminSetLogisticsStage` naqshi.
 *
 * Hujjat yo'q bo'lsa (jonli holat: 2-bosqich «yopiq: darvoza hujjati yo'q») — setter
 * uni YARATADI (logistikadan farqi: bu darvozaning boshqa manbasi yo'q). Yaratishda
 * standart: `enabled: false`, `stage: 'internal'`, `testerIds: []` — ya'ni faqat
 * admin aniq ko'rsatgan narsa ochiladi.
 *
 * DIQQAT (hujjat §4): 3-bosqich relay guard'lari jonliga chiqmaguncha darvoza YOPIQ
 * turishi kerak — bu ega qarori/operatsion qoida; server uni majburlamaydi (UI ogohlantiradi).
 */

const { toCanonicalId } = require('../core/ids');
const { getGlobalConfig } = require('../core/config');
const L = require('../core/logistics');
const { assertStrictAdmin } = require('../analytics/access');
const { GATE_DOC, ADMIN_AUDIT } = require('./wholesale_orders');

/** Sinovchilar ro'yxati chegarasi — `adminSetLogisticsStage` bilan bir xil (hujjat o'lchami himoyasi). */
const TESTERS_MAX = 500;
const REASON_MIN = 3;
const REASON_MAX = 300;
const AUDIT_KIND = 'wholesale_orders_gate';

function fail(code, message, reason, extra) {
  const e = new Error(message);
  e.code = code;
  e.httpErrorCode = code;
  e.details = { reason: reason || code, ...(extra || {}) };
  return e;
}

function log(action, fields) {
  console.log(JSON.stringify({ module: 'wholesale_orders_admin', action, ...fields }));
}

/** `undefined` — berilmagan; aks holda kanonik, takrorsiz ro'yxat (bo'sh qatorlar tashlanadi). */
function parseTesterList(raw) {
  if (raw === undefined || raw === null) return undefined;
  if (!Array.isArray(raw)) throw fail('invalid-argument', 'Sinovchilar ro\'yxati massiv bo\'lishi kerak', 'tester_invalid');
  const out = [];
  for (const item of raw) {
    const s = String(item === null || item === undefined ? '' : item).trim();
    if (!s) continue;
    const id = toCanonicalId(s);
    if (!id) throw fail('invalid-argument', 'Telefon raqami noto\'g\'ri', 'tester_invalid');
    if (!out.includes(id)) out.push(id);
  }
  return out;
}

/** Hujjatdagi holat → kanonik ko'rinish (kvota darvozasi bilan bir xil o'qish). */
function gateStateOf(data, exists) {
  const d = exists ? (data || {}) : {};
  const list = (Array.isArray(d.testerIds) ? d.testerIds : [])
    .map((t) => toCanonicalId(String(t || ''))).filter(Boolean);
  return {
    exists: !!exists,
    enabled: d.enabled === true,
    stage: L.stageOf({ logistics: { stage: d.stage } }),
    rawStage: typeof d.stage === 'string' ? d.stage : null,
    testerIds: [...new Set(list)],
  };
}

/**
 * Sof: so'rovni tekshirish. @returns {{enabled, stage, add, remove, reason}}
 * (`enabled`/`stage` — `null` = o'zgarmaydi; `add`/`remove` — `undefined` = berilmagan).
 */
function parseStageRequest(data) {
  const d = data || {};
  const reason = String(d.reason === undefined || d.reason === null ? '' : d.reason).trim();
  if (reason.length < REASON_MIN) {
    throw fail('invalid-argument', `Sabab kamida ${REASON_MIN} belgi (audit)`, 'reason_required', { min: REASON_MIN });
  }
  let enabled = null;
  if (d.enabled !== undefined && d.enabled !== null) {
    if (typeof d.enabled !== 'boolean') throw fail('invalid-argument', 'enabled true/false bo\'lishi kerak', 'enabled_invalid');
    enabled = d.enabled;
  }
  let stage = null;
  if (d.stage !== undefined && d.stage !== null) {
    if (!Object.values(L.STAGE).includes(d.stage)) {
      throw fail('invalid-argument', 'Bosqich noma\'lum', 'stage_invalid', { allowed: Object.values(L.STAGE) });
    }
    stage = d.stage;
  }
  const add = parseTesterList(d.addTesterIds);
  const remove = parseTesterList(d.removeTesterIds);
  if (add && remove && add.some((t) => remove.includes(t))) {
    throw fail('invalid-argument', 'Bitta raqam ham qo\'shilib, ham olinmaydi', 'tester_args_conflict');
  }
  if (enabled === null && stage === null && add === undefined && remove === undefined) {
    throw fail('invalid-argument', 'O\'zgartirish yo\'q', 'nothing_to_change');
  }
  return {
    enabled, stage, add, remove, reason: reason.slice(0, REASON_MAX),
  };
}

function makeAdminSetWholesaleOrdersStage(deps) {
  const { db, now: nowFn } = deps;
  const ref = db.collection(GATE_DOC[0]).doc(GATE_DOC[1]);

  return async function adminSetWholesaleOrdersStage(data, context) {
    const started = Date.now();
    const adminId = await assertStrictAdmin(db, context);
    try {
      const req = parseStageRequest(data);
      const now = nowFn ? nowFn() : new Date();
      const out = await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const cur = gateStateOf(snap.exists ? snap.data() : null, snap.exists);
        let nextList = cur.testerIds.filter((t) => !(req.remove || []).includes(t));
        for (const t of (req.add || [])) if (!nextList.includes(t)) nextList.push(t);
        if (nextList.length > TESTERS_MAX) {
          throw fail('invalid-argument', `Sinovchilar ${TESTERS_MAX} tadan oshmasin`, 'testers_limit', { max: TESTERS_MAX });
        }
        const nextEnabled = req.enabled === null ? cur.enabled : req.enabled;
        const nextStage = req.stage === null ? cur.stage : req.stage;
        const added = nextList.filter((t) => !cur.testerIds.includes(t)).length;
        const removed = cur.testerIds.filter((t) => !nextList.includes(t)).length;
        // Hujjatdagi xom bosqich noma'lum bo'lsa (masalan «beta») — kanonik qiymat yozilishi
        // uchun «o'zgarish bor» hisoblanadi (o'qish bilan yozuv bir xil bo'lsin).
        const rawDiffers = cur.exists && cur.rawStage !== nextStage;
        const same = nextEnabled === cur.enabled && nextStage === cur.stage
          && added === 0 && removed === 0 && !rawDiffers;
        if (same) {
          return {
            unchanged: true, created: false, enabled: cur.enabled, stage: cur.stage,
            testerCount: cur.testerIds.length, added: 0, removed: 0,
          };
        }
        tx.set(ref, {
          enabled: nextEnabled,
          stage: nextStage,
          testerIds: nextList,
          updatedAt: now,
          updatedBy: adminId,
          ...(cur.exists ? {} : { createdAt: now, createdBy: adminId }),
        }, { merge: true });
        tx.set(db.collection(ADMIN_AUDIT).doc(), {
          kind: AUDIT_KIND,
          actor: adminId,
          target: GATE_DOC.join('/'),
          from: { exists: cur.exists, enabled: cur.enabled, stage: cur.stage, testerCount: cur.testerIds.length },
          to: { enabled: nextEnabled, stage: nextStage, testerCount: nextList.length },
          added,
          removed,
          reason: req.reason,
          at: now,
        });
        return {
          unchanged: false, created: !cur.exists, enabled: nextEnabled, stage: nextStage,
          testerCount: nextList.length, added, removed,
        };
      });
      log('adminSetWholesaleOrdersStage', {
        result: out.unchanged ? 'unchanged' : 'ok', enabled: out.enabled, stage: out.stage,
        testerCount: out.testerCount, added: out.added, removed: out.removed, created: out.created,
        durationMs: Date.now() - started,
      });
      return { ok: true, ...out };
    } catch (e) {
      log('adminSetWholesaleOrdersStage', {
        result: 'denied', errorCode: (e.details && e.details.reason) || e.code || 'UNKNOWN',
        durationMs: Date.now() - started,
      });
      throw e;
    }
  };
}

/**
 * Admin uchun holat: tester telefonlari BERILADI (ro'yxatni boshqarish uchun; faqat
 * admin/superadmin). `effectiveOpen` — kvota darvozasi hozir kimgadir ochiqmi
 * (hujjat bor + enabled + global kalit + bosqich `off` emas).
 */
function makeAdminGetWholesaleOrdersStage(deps) {
  const { db } = deps;
  return async function adminGetWholesaleOrdersStage(data, context) {
    await assertStrictAdmin(db, context);
    const snap = await db.collection(GATE_DOC[0]).doc(GATE_DOC[1]).get();
    const st = gateStateOf(snap.exists ? snap.data() : null, snap.exists);
    const g = await getGlobalConfig(db);
    const globalEnabled = g.enabled !== false;
    const d = snap.exists ? (snap.data() || {}) : {};
    const ms = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : (v instanceof Date ? v.getTime() : null));
    return {
      exists: st.exists,
      enabled: st.enabled,
      stage: st.stage,
      rawStage: st.rawStage,
      testerIds: st.testerIds,
      testerCount: st.testerIds.length,
      globalEnabled,
      effectiveOpen: st.exists && st.enabled && globalEnabled && st.stage !== L.STAGE.OFF,
      updatedAtMs: ms(d.updatedAt),
      updatedBy: typeof d.updatedBy === 'string' ? d.updatedBy : null,
      testersMax: TESTERS_MAX,
    };
  };
}

module.exports = {
  TESTERS_MAX,
  AUDIT_KIND,
  parseTesterList,
  parseStageRequest,
  gateStateOf,
  makeAdminSetWholesaleOrdersStage,
  makeAdminGetWholesaleOrdersStage,
};
