/**
 * MIJOZ TASDIG'I — "Oldim" / "Berdim" (ega qarori D2/D7, 2026-10-16).
 *
 * AVA kuryeri oqimlarida kuryerning "yetkazdim / olib ketdim" deyishi YETARLI EMAS:
 * mijoz buni O'Z qurilmasida tasdiqlashi shart (majburiy, avto-tasdiq ham, vaqt
 * tugashi ham YO'Q — qotib qolgan vazifani admin "qotib qolgan vazifalar" ro'yxatidan
 * hal qiladi). Yig'ib olishda (kuryer mijozdan sut/mahsulot sotib oladi) mijoz kuryer
 * kiritgan yakuniy miqdor/summani PUL HARAKATIDAN OLDIN tasdiqlaydi.
 *
 * QADAMLAR (modul -> qadam):
 *   restaurant -> received          (courierCompleteRestaurantDelivery, outcome 'delivered')
 *   carpet     -> handover_pickup   (courierMarkCarpetPickedUp)
 *                 handover_return   (courierMarkCarpetDelivered)
 *   agro       -> handover_pickup   (courierMarkAgroPickedUp)
 *   collection -> finalize          (courierFinalizeCollection)
 *
 * SOZLAMA (faqat server): `server_config/customer_confirm`
 *   { modules: { restaurant|carpet|agro|collection: { stage: 'off'|'internal'|'public' } },
 *     testerIds: [kanonik 12 xonali telefonlar], version, reason, updatedAt, updatedBy }
 *   - hujjat yo'q / noto'g'ri qiymat -> 'off' (fail-closed: eski oqim O'ZGARMAYDI);
 *   - 'internal' -> faqat mijoz telefoni `testerIds` da bo'lsa; 'public' -> hamma mijoz.
 *   `server_config` — YANGI kolleksiya, firestore.rules da match YO'Q = klient uchun
 *   o'qish ham yozish ham taqiqlangan (default-deny); test: customer_confirm_rules.test.js.
 *   Ommaviy belgi `module_config/customer_confirm` { enabled } — ilova so'rovni
 *   o'tkazib yuborishi uchun (faqat maslahat; SERVER undan o'qimaydi — qaror
 *   faqat `server_config` dan, shuning uchun belgini buzish xavfsizlikka ta'sir qilmaydi).
 *   Sozlama xotirada ~30 s keshlanadi (`CUSTOMER_CONFIRM_CACHE_MS` bilan o'zgartiriladi;
 *   boshqa instansiyalarda o'zgarish shuncha vaqtda ko'rinadi).
 *
 * KUTISH BELGISI (vazifa/buyurtma hujjatida):
 *   awaitingCustomerConfirm: { step, requestedAt (server vaqti), courierId, ...kerakli kirishlar }
 *   hasAwaitingCustomerConfirm: true     (faqat tenglik so'rovi uchun, indeks kerak emas)
 *   Tasdiqdan keyin ikkalasi o'chadi, `customerConfirmed.{step} = { at, courierId }` qoladi.
 *   Belgi yozilganda `updatedAt` O'ZGARTIRILMAYDI — "qotib qolgan vazifalar" ro'yxati
 *   (D6) holat o'zgarishidan boshlab sanaydi, shuning uchun tasdiqsiz qolganlar ko'rinadi.
 *   Hujjatlarni mijoz klienti YOZA OLMAYDI (rules: orders — faqat staff/admin,
 *   carpet/agro/collection — create/update yopiq), belgini faqat server yozadi.
 *
 * CALLABLE'LAR (default codebase, us-central1):
 *   getCustomerPendingConfirmations, customerConfirmHandover (mijoz);
 *   adminSetCustomerConfirmation, adminGetCustomerConfirmation (admin/superadmin).
 *
 * Har modul o'z "yadro"sini shu yerda `registerHandler` bilan ro'yxatdan o'tkazadi
 * (restoran: restaurant_orders.js; gilam/agro/yig'ib olish: index.js) — pul va holat
 * mantiqi bitta joyda qoladi, kuryer ham, mijoz ham shu yadroni ishlatadi (7-qoida).
 *
 * Loglar tuzilgan (action, module, id, step, result, errorCode); telefon YO'Q (24, 40-qoida).
 */
'use strict';

const i18n = require('./notif_i18n');

const MODULES = Object.freeze(['restaurant', 'carpet', 'agro', 'collection']);
const STAGES = Object.freeze(['off', 'internal', 'public']);
const CONFIG_DOC = Object.freeze(['server_config', 'customer_confirm']);
const MARKER_DOC = Object.freeze(['module_config', 'customer_confirm']);
const STEPS = Object.freeze({
  restaurant: Object.freeze(['received']),
  carpet: Object.freeze(['handover_pickup', 'handover_return']),
  agro: Object.freeze(['handover_pickup']),
  collection: Object.freeze(['finalize']),
});
const MARKER_FIELD = 'awaitingCustomerConfirm';
const FLAG_FIELD = 'hasAwaitingCustomerConfirm';
const DONE_FIELD = 'customerConfirmed';
const ADMIN_AUDIT = 'admin_audit';
const CACHE_MS_DEFAULT = 30 * 1000;
const MAX_TESTERS = 500;
const MAX_TESTERS_PER_CALL = 200;
const PENDING_LIMIT_PER_QUERY = 20;
const TESTER_RE = /^998\d{9}$/;
/** Tranzaksiya ichidagi yadro shu xatolarni bersa — holat o'zgargan (STATE_CHANGED). */
const STATE_ERROR_CODES = Object.freeze(['failed-precondition', 'permission-denied', 'not-found']);

const str = (v, max) => String(v == null ? '' : v).trim().slice(0, max);
const msOf = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : null);
const maskPhone = (v) => {
  const d = String(v || '').replace(/\D/g, '');
  return d.length >= 4 ? `***${d.slice(-4)}` : '';
};
const log = (fields) => console.log(JSON.stringify(fields));

// ─────────────────────────────────────────────────────────────────────────────
// SOF QISM (testlanadi): sozlamani me'yorlash va darvoza qarori
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Xom hujjat -> { modules: {modul: stage}, testerIds: [kanonik, tartiblangan] }.
 * Har qanday noto'g'ri qiymat 'off' bo'ladi / tashlab yuboriladi ("fail-closed to off":
 * noaniq holatda eski, ishlab turgan oqim o'zgarmaydi).
 */
function normalizeConfig(raw, canon) {
  const doc = raw && typeof raw === 'object' ? raw : {};
  const src = doc.modules && typeof doc.modules === 'object' ? doc.modules : {};
  const modules = {};
  for (const m of MODULES) {
    const entry = Object.prototype.hasOwnProperty.call(src, m) ? src[m] : null;
    modules[m] = entry && typeof entry === 'object' && STAGES.includes(entry.stage) ? entry.stage : 'off';
  }
  const testers = [];
  for (const x of (Array.isArray(doc.testerIds) ? doc.testerIds : [])) {
    if (typeof x !== 'string' && typeof x !== 'number') continue;
    const c = canon(String(x));
    if (TESTER_RE.test(c) && !testers.includes(c)) testers.push(c);
  }
  testers.sort();
  return { modules, testerIds: testers };
}

function stageOf(cfg, moduleKey) {
  const s = cfg && cfg.modules ? cfg.modules[moduleKey] : null;
  return STAGES.includes(s) ? s : 'off';
}

/** Shu mijoz uchun shu modulda tasdiq YOQILGANMI. */
function isGatedBy(cfg, moduleKey, phone, canon) {
  const stage = stageOf(cfg, moduleKey);
  if (stage === 'public') return true;
  if (stage !== 'internal') return false;
  const c = canon(String(phone || ''));
  return TESTER_RE.test(c) && Array.isArray(cfg.testerIds) && cfg.testerIds.includes(c);
}

/** Ommaviy belgi: biror modul 'off' emas. */
function markerEnabled(cfg) {
  return MODULES.some((m) => stageOf(cfg, m) !== 'off');
}

/**
 * Sozlama o'qigich: qisqa xotira keshi. O'qish xatosi -> oldingi (eskirgan) qiymat,
 * u ham yo'q bo'lsa 'off'. `ttlMs <= 0` — keshsiz (testlar uchun).
 */
function makeConfigReader({ db, canon, ttlMs, nowFn, onError }) {
  let cache = null;
  const now = nowFn || (() => Date.now());
  async function get() {
    const t = now();
    if (cache && ttlMs > 0 && t - cache.at < ttlMs) return cache.value;
    try {
      const snap = await db.collection(CONFIG_DOC[0]).doc(CONFIG_DOC[1]).get();
      const value = normalizeConfig(snap.exists ? snap.data() : null, canon);
      cache = { at: t, value };
      return value;
    } catch (e) {
      if (onError) onError(e);
      return cache ? cache.value : normalizeConfig(null, canon);
    }
  }
  return { get, invalidate: () => { cache = null; } };
}

function cacheMsFromEnv() {
  const raw = process.env.CUSTOMER_CONFIRM_CACHE_MS;
  if (raw === undefined || raw === '') return CACHE_MS_DEFAULT;
  const n = Number(raw);
  return Number.isFinite(n) && n >= 0 ? n : CACHE_MS_DEFAULT;
}

// ─────────────────────────────────────────────────────────────────────────────
// Asosiy fabrika
// ─────────────────────────────────────────────────────────────────────────────

function createCustomerConfirm(deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, requireCallerRoles, notifyUserInApp,
  } = deps;
  const HttpsError = functions.https.HttpsError;
  const FV = admin.firestore.FieldValue;
  const ts = () => FV.serverTimestamp();
  const canon = (v) => canonicalUid(String(v == null ? '' : v));
  const handlers = new Map();
  const reader = makeConfigReader({
    db, canon, ttlMs: Number.isFinite(deps.cacheMs) ? deps.cacheMs : cacheMsFromEnv(), nowFn: deps.now,
    onError: (e) => console.error(JSON.stringify({
      action: 'customerConfirmConfig', result: 'read_failed', errorCode: 'CUSTOMER_CONFIRM_CONFIG_READ_FAILED',
      message: String((e && e.message) || e).slice(0, 160),
    })),
  });

  const err = (status, code, extra = {}) => new HttpsError(status, code, { reason: code, code, ...extra });

  function requirePhoneUid(context) {
    if (!context || !context.auth) throw err('unauthenticated', 'AUTH_REQUIRED');
    const uid = canon(callerPhone(context));
    if (!uid || uid.length < 12) throw err('unauthenticated', 'PHONE_TOKEN_REQUIRED');
    return uid;
  }

  // ── Yadro ro'yxati ─────────────────────────────────────────────────────
  /**
   * handler = {
   *   collection, phoneField, customerPhoneOf(od), statusOf(od),
   *   describe(od, marker) -> null | { key, params, details? }   // null: belgi holatga mos emas
   *   confirm(t, { ref, id, od, marker, step }) -> { status, after? }   // tranzaksiya ICHIDA
   * }
   */
  function registerHandler(moduleKey, handler) {
    if (!MODULES.includes(moduleKey)) throw new Error(`customer_confirm: unknown module ${moduleKey}`);
    for (const k of ['collection', 'phoneField', 'customerPhoneOf', 'statusOf', 'describe', 'confirm']) {
      if (!handler || handler[k] === undefined) throw new Error(`customer_confirm: handler.${k} missing (${moduleKey})`);
    }
    handlers.set(moduleKey, handler);
  }

  // ── Kuryer tomoni yordamchilari ────────────────────────────────────────
  async function isGated(moduleKey, customerPhone) {
    return isGatedBy(await reader.get(), moduleKey, customerPhone, canon);
  }

  const awaitingResponse = (step) => ({ ok: true, awaitingCustomer: true, step });

  function markerPatch(step, courierId, extra) {
    return {
      [MARKER_FIELD]: { step, requestedAt: ts(), courierId: String(courierId || ''), ...(extra || {}) },
      [FLAG_FIELD]: true,
    };
  }

  /** Hujjatda kutish belgisi bo'lsa — o'chirish yamoqchasi, aks holda `{}` (eski oqim O'ZGARMAYDI). */
  function clearPatch(od) {
    if (!od || (od[MARKER_FIELD] === undefined && od[FLAG_FIELD] === undefined)) return {};
    return { [MARKER_FIELD]: FV.delete(), [FLAG_FIELD]: FV.delete() };
  }

  /** Tasdiq izi (joriy holat; tarix — log va hodisalar). */
  function confirmedPatch(step, courierId) {
    return { [`${DONE_FIELD}.${step}`]: { at: ts(), courierId: String(courierId || '') } };
  }

  /**
   * Tranzaksiya ichida: kutish belgisini yozadi. Shu qadam uchun belgi bor bo'lsa
   * yozmaydi (`created: false`) — takroriy kuryer chaqiruvi bir xil javob oladi.
   */
  function requestInTx(t, ref, od, { step, courierId, extra }) {
    const m = od && od[MARKER_FIELD];
    if (m && m.step === step) return { created: false };
    t.update(ref, markerPatch(step, courierId, extra));
    return { created: true };
  }

  /** Mijozga "tasdiqlang" push'i (3 tilda; users.appLang). Xato asosiy oqimni to'xtatmaydi. */
  async function notifyRequest(moduleKey, id, step, customerPhone, described) {
    try {
      if (!described) return;
      const lang = await i18n.langOfPhone(db, customerPhone);
      const m = i18n.render(described.key, lang, described.params || {});
      await notifyUserInApp({
        userId: canon(customerPhone),
        title: m.title,
        body: m.body,
        category: 'order',
        source: 'customer_confirm',
        dataType: 'customer_confirm',
        screen: 'orders',
        extraData: { module: moduleKey, id: String(id), step },
      });
    } catch (e) {
      console.error(JSON.stringify({
        action: 'customerConfirmNotify', module: moduleKey, id: String(id), step, result: 'failed',
        errorCode: 'CUSTOMER_CONFIRM_NOTIFY_FAILED', message: String((e && e.message) || e).slice(0, 160),
      }));
    }
  }

  /** Kuryer so'rovi yozilgandan KEYIN: jurnal + push (faqat belgi yangi yozilganda). */
  async function afterRequest(moduleKey, id, step, od, markerLike, created) {
    log({ action: 'customerConfirmRequest', module: moduleKey, id: String(id), step, result: created ? 'requested' : 'already_requested' });
    if (!created) return;
    const h = handlers.get(moduleKey);
    let described = null;
    try { described = h ? h.describe(od, { step, ...(markerLike || {}) }) : null; } catch (_) { described = null; }
    await notifyRequest(moduleKey, id, step, h ? h.customerPhoneOf(od) : '', described);
  }

  // ── Mijoz callable'lari ────────────────────────────────────────────────
  /** STATE_CHANGED: belgi hanuz o'sha so'rovniki bo'lsa o'chiradi (kuryer qayta kiritsin). */
  async function clearMarkerIfSame(ref, step, requestedMs) {
    await db.runTransaction(async (t) => {
      const s = await t.get(ref);
      if (!s.exists) return;
      const od = s.data() || {};
      const m = od[MARKER_FIELD];
      if (!m || m.step !== step || msOf(m.requestedAt) !== requestedMs) return;
      t.update(ref, clearPatch(od));
    });
  }

  async function confirmHandover(data, context) {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    const moduleKey = str(data && data.module, 32);
    const id = str(data && data.id, 128);
    const step = str(data && data.step, 40);
    if (!MODULES.includes(moduleKey) || !id || id.includes('/') || !STEPS[moduleKey].includes(step)) {
      throw err('invalid-argument', 'CONFIRM_ARGS_INVALID');
    }
    const h = handlers.get(moduleKey);
    if (!h) throw new HttpsError('internal', 'CONFIRM_HANDLER_MISSING', { reason: 'CONFIRM_HANDLER_MISSING' });
    const ref = db.collection(h.collection).doc(id);
    let seenRequestedMs = null;
    try {
      const out = await db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        if (!snap.exists) throw err('permission-denied', 'NOT_YOUR_ORDER');
        const od = snap.data() || {};
        if (canon(h.customerPhoneOf(od)) !== uid) throw err('permission-denied', 'NOT_YOUR_ORDER');
        const marker = od[MARKER_FIELD];
        if (!marker || marker.step !== step) {
          const done = od[DONE_FIELD];
          if (done && typeof done === 'object' && done[step]) return { idempotent: true, status: h.statusOf(od) };
          throw err('failed-precondition', 'NOT_AWAITING');
        }
        seenRequestedMs = msOf(marker.requestedAt);
        let r;
        try {
          r = await h.confirm(t, { ref, id, od, marker, step });
        } catch (e) {
          if (e instanceof HttpsError && STATE_ERROR_CODES.includes(e.code)) {
            const s = new Error('STATE_CHANGED');
            s.stateChanged = true;
            s.cause = e;
            throw s;
          }
          throw e;
        }
        return { idempotent: false, status: r.status, after: r.after };
      });
      if (out.after) {
        try { await out.after(); } catch (e) {
          console.error(JSON.stringify({
            action: 'customerConfirmAfter', module: moduleKey, id, step, result: 'failed',
            errorCode: 'CUSTOMER_CONFIRM_AFTER_FAILED', message: String((e && e.message) || e).slice(0, 160),
          }));
        }
      }
      log({
        action: 'customerConfirmHandover', module: moduleKey, id, step,
        result: out.idempotent ? 'idempotent' : 'ok', status: out.status, durationMs: Date.now() - t0,
      });
      return { ok: true, status: out.status, ...(out.idempotent ? { idempotent: true } : {}) };
    } catch (e) {
      if (e && e.stateChanged) {
        const inner = e.cause || {};
        try { await clearMarkerIfSame(ref, step, seenRequestedMs); } catch (ce) {
          console.error(JSON.stringify({ action: 'customerConfirmHandover', module: moduleKey, id, step, result: 'clear_failed', errorCode: 'CUSTOMER_CONFIRM_CLEAR_FAILED' }));
        }
        log({
          action: 'customerConfirmHandover', module: moduleKey, id, step, result: 'denied',
          errorCode: 'STATE_CHANGED', cause: (inner.details && inner.details.code) || inner.message || '', durationMs: Date.now() - t0,
        });
        throw err('failed-precondition', 'STATE_CHANGED');
      }
      if (e instanceof HttpsError) {
        log({
          action: 'customerConfirmHandover', module: moduleKey, id, step, result: 'denied',
          errorCode: (e.details && e.details.reason) || e.message, durationMs: Date.now() - t0,
        });
        throw e;
      }
      // Parallel ikki tasdiq: Admin SDK qayta urinishlari tugagach xom "ABORTED/contention" bo'lishi
      // mumkin (restoran `withContention` bilan bir xil sabab). G'olib allaqachon yozgan bo'lsa —
      // bu idempotent muvaffaqiyat; aks holda aniq, qayta uriniladigan kod (22, 25-qoida).
      if (e && (e.code === 10 || /aborted|contention/i.test(String(e.message || '')))) {
        try {
          const s = await ref.get();
          const od = s.exists ? (s.data() || {}) : null;
          if (od && canon(h.customerPhoneOf(od)) === uid && !od[MARKER_FIELD]
              && od[DONE_FIELD] && typeof od[DONE_FIELD] === 'object' && od[DONE_FIELD][step]) {
            log({ action: 'customerConfirmHandover', module: moduleKey, id, step, result: 'idempotent', note: 'contention_resolved', durationMs: Date.now() - t0 });
            return { ok: true, status: h.statusOf(od), idempotent: true };
          }
        } catch (_) { /* pastdagi aniq xatoga tushadi */ }
        log({ action: 'customerConfirmHandover', module: moduleKey, id, step, result: 'denied', errorCode: 'CONTENTION_RETRY', durationMs: Date.now() - t0 });
        throw err('aborted', 'CONTENTION_RETRY');
      }
      throw e;
    }
  }

  async function listPending(data, context) {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    const cfg = await reader.get();
    const lang = await i18n.langOfPhone(db, uid);
    const forms = uid.length === 12 && uid.startsWith('998') ? [uid, uid.slice(3)] : [uid];
    const perModule = await Promise.all(MODULES.map(async (moduleKey) => {
      const h = handlers.get(moduleKey);
      if (!h || !isGatedBy(cfg, moduleKey, uid, canon)) return [];
      // Faqat tenglik filtrlari (telefon shakllari x belgi) — kompozit indeks kerak emas.
      const snaps = await Promise.all(forms.map((f) => db.collection(h.collection)
        .where(h.phoneField, '==', f)
        .where(FLAG_FIELD, '==', true)
        .limit(PENDING_LIMIT_PER_QUERY)
        .get()));
      const seen = new Set();
      const out = [];
      for (const snap of snaps) {
        for (const doc of snap.docs) {
          if (seen.has(doc.id)) continue;
          seen.add(doc.id);
          const od = doc.data() || {};
          const marker = od[MARKER_FIELD];
          if (!marker || !STEPS[moduleKey].includes(marker.step)) continue;
          if (canon(h.customerPhoneOf(od)) !== uid) continue;
          const d = h.describe(od, marker);
          if (!d) continue;
          const r = i18n.render(d.key, lang, d.params || {});
          out.push({
            module: moduleKey,
            id: doc.id,
            step: marker.step,
            title: r.title,
            summary: r.body,
            requestedAtMs: msOf(marker.requestedAt),
            ...(d.details ? { details: d.details } : {}),
          });
        }
      }
      return out;
    }));
    const items = perModule.flat().sort((a, b) => (a.requestedAtMs || 0) - (b.requestedAtMs || 0));
    log({ action: 'getCustomerPendingConfirmations', result: 'ok', count: items.length, durationMs: Date.now() - t0 });
    return { ok: true, items };
  }

  // ── Admin callable'lari ────────────────────────────────────────────────
  const ADMIN_ROLES = ['admin', 'superadmin'];
  const ADMIN_DENIED = 'Faqat admin yoki superadmin';

  function parseTesterList(raw, field) {
    if (raw === undefined) return [];
    if (!Array.isArray(raw) || raw.length > MAX_TESTERS_PER_CALL) {
      throw err('invalid-argument', 'CC_TESTER_INVALID', { field });
    }
    const out = [];
    raw.forEach((x, index) => {
      const c = typeof x === 'string' || typeof x === 'number' ? canon(String(x)) : '';
      if (!TESTER_RE.test(c)) throw err('invalid-argument', 'CC_TESTER_INVALID', { field, index });
      if (!out.includes(c)) out.push(c);
    });
    return out;
  }

  async function adminSet(data, context) {
    const actor = await requireCallerRoles(context, ADMIN_ROLES, ADMIN_DENIED);
    const d = data && typeof data === 'object' ? data : {};
    if (d.module !== undefined && !MODULES.includes(d.module)) {
      throw err('invalid-argument', 'CC_MODULE_INVALID', { allowed: [...MODULES] });
    }
    if (d.stage !== undefined && !STAGES.includes(d.stage)) {
      throw err('invalid-argument', 'CC_STAGE_INVALID', { allowed: [...STAGES] });
    }
    if (d.stage !== undefined && d.module === undefined) throw err('invalid-argument', 'CC_MODULE_REQUIRED');
    const add = parseTesterList(d.addTesterIds, 'addTesterIds');
    const remove = parseTesterList(d.removeTesterIds, 'removeTesterIds');
    if (add.some((x) => remove.includes(x))) throw err('invalid-argument', 'CC_TESTER_CONFLICT');
    if (d.stage === undefined && add.length === 0 && remove.length === 0) throw err('invalid-argument', 'CC_NOTHING_TO_CHANGE');
    const reason = str(d.reason, 300);
    if (reason.length < 3) throw err('invalid-argument', 'CC_REASON_REQUIRED');

    const cfgRef = db.collection(CONFIG_DOC[0]).doc(CONFIG_DOC[1]);
    const markerRef = db.collection(MARKER_DOC[0]).doc(MARKER_DOC[1]);
    const out = await db.runTransaction(async (t) => {
      const [snap, mSnap] = await Promise.all([t.get(cfgRef), t.get(markerRef)]);
      const raw = snap.exists ? (snap.data() || {}) : null;
      const cur = normalizeConfig(raw, canon);
      const next = { modules: { ...cur.modules }, testerIds: [...cur.testerIds] };
      if (d.stage !== undefined) next.modules[d.module] = d.stage;
      for (const x of add) if (!next.testerIds.includes(x)) next.testerIds.push(x);
      next.testerIds = next.testerIds.filter((x) => !remove.includes(x)).sort();
      if (next.testerIds.length > MAX_TESTERS) throw err('invalid-argument', 'CC_TESTERS_LIMIT', { max: MAX_TESTERS });
      const version = raw && Number.isInteger(raw.version) && raw.version >= 0 ? raw.version : 0;
      const enabled = markerEnabled(next);
      const same = MODULES.every((m) => next.modules[m] === cur.modules[m])
        && next.testerIds.join(',') === cur.testerIds.join(',');
      const markerOk = mSnap.exists && (mSnap.data() || {}).enabled === enabled;
      if (same) {
        // Sozlama o'zgarmadi (idempotent). Faqat ommaviy belgi sinxrondan chiqqan bo'lsa tuzatiladi.
        if (!markerOk) t.set(markerRef, { enabled, updatedAt: ts(), updatedBy: actor });
        return { unchanged: true, markerRepaired: !markerOk, version, cfg: cur, enabled };
      }
      const modulesDoc = {};
      for (const m of MODULES) modulesDoc[m] = { stage: next.modules[m] };
      t.set(cfgRef, {
        modules: modulesDoc, testerIds: next.testerIds, version: version + 1, reason, updatedAt: ts(), updatedBy: actor,
      });
      t.set(markerRef, { enabled, updatedAt: ts(), updatedBy: actor });
      const realAdded = add.filter((x) => !cur.testerIds.includes(x));
      const realRemoved = remove.filter((x) => cur.testerIds.includes(x));
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'customer_confirm_config', actor, target: CONFIG_DOC.join('/'),
        from: d.module !== undefined ? cur.modules[d.module] : '', to: d.module !== undefined ? next.modules[d.module] : '',
        reason,
        detail: {
          module: d.module === undefined ? null : d.module,
          stagePrev: d.module !== undefined ? cur.modules[d.module] : null,
          stageNew: d.module !== undefined ? next.modules[d.module] : null,
          testersAdded: realAdded.length,
          testersRemoved: realRemoved.length,
          testersAfter: next.testerIds.length,
          addedMasked: realAdded.slice(0, 20).map(maskPhone),
          removedMasked: realRemoved.slice(0, 20).map(maskPhone),
          enabled,
          version: version + 1,
        },
        at: ts(),
      });
      return { unchanged: false, markerRepaired: false, version: version + 1, cfg: next, enabled };
    });
    reader.invalidate();
    log({
      action: 'adminSetCustomerConfirmation', module: d.module === undefined ? null : d.module,
      result: out.unchanged ? 'unchanged' : 'ok', version: out.version, enabled: out.enabled,
    });
    return {
      ok: true, unchanged: out.unchanged, version: out.version, modules: out.cfg.modules,
      testerCount: out.cfg.testerIds.length, enabled: out.enabled,
    };
  }

  async function adminGet(data, context) {
    await requireCallerRoles(context, ADMIN_ROLES, ADMIN_DENIED);
    const snap = await db.collection(CONFIG_DOC[0]).doc(CONFIG_DOC[1]).get();
    const raw = snap.exists ? (snap.data() || {}) : null;
    const cfg = normalizeConfig(raw, canon);
    return {
      ok: true,
      version: raw && Number.isInteger(raw.version) ? raw.version : 0,
      modules: cfg.modules,
      testerCount: cfg.testerIds.length,
      testersMasked: cfg.testerIds.map(maskPhone),
      enabled: markerEnabled(cfg),
      updatedAtMs: raw ? msOf(raw.updatedAt) : null,
    };
  }

  function attach(exportsObj) {
    exportsObj.getCustomerPendingConfirmations = functions.https.onCall(listPending);
    exportsObj.customerConfirmHandover = functions.https.onCall(confirmHandover);
    exportsObj.adminSetCustomerConfirmation = functions.https.onCall(adminSet);
    exportsObj.adminGetCustomerConfirmation = functions.https.onCall(adminGet);
  }

  return {
    attach,
    registerHandler,
    isGated,
    getConfig: () => reader.get(),
    invalidateConfig: () => reader.invalidate(),
    awaitingResponse,
    markerPatch,
    clearPatch,
    confirmedPatch,
    requestInTx,
    afterRequest,
    notifyRequest,
  };
}

module.exports = {
  MODULES,
  STAGES,
  STEPS,
  CONFIG_DOC,
  MARKER_DOC,
  MARKER_FIELD,
  FLAG_FIELD,
  DONE_FIELD,
  TESTER_RE,
  CACHE_MS_DEFAULT,
  normalizeConfig,
  stageOf,
  isGatedBy,
  markerEnabled,
  makeConfigReader,
  createCustomerConfirm,
};
