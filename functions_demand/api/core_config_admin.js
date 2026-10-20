'use strict';

/**
 * ADMIN «ТАЛАБ ЯДРОСИ» — ҳудуд бўйича ёқиш/ўчириш ва push чегараси
 * (ега қарори 2026-10-20).
 *
 * `module_config/{module}_{region}` калити ва `push.minScore`ни админ панелдан
 * бошқариш. Қоидалар СЕРВЕРДА текширилади (18, 44-банд); экран фақат сабабни
 * кўрсатади:
 *   - ёзиш фақат admin / superadmin (dispatcher — фақат ўқийди);
 *   - ҳолат фақат аниқ ҳудуд учун (вариант А), `all` рад этилади;
 *   - shadow/push: ҳудудда ишлай оладиган таклифчи >= N (стандарт 5);
 *   - push: чегара (push.minScore) ўлчаб қўйилган бўлиши шарт (вариант 3);
 *   - ҳар ўзгариш `admin_audit`га ёзилади (41-банд), конфиг ҳужжати билан БИР
 *     транзакцияда; ўзгармаса — ёзув ҳам, аудит ҳам йўқ (идемпотент, 21-банд).
 *
 * Конфиг 60 сонияда кучга киради (`core/config.js` кеши).
 */

const caps = require('../core/capabilities');
const { DEFAULTS, deepMerge, validateConfig } = require('../core/config');
const ca = require('../core/core_admin');
const { moduleRegionKey } = require('../core/ids');
const { modeFor } = require('../core/registry');
const { summarizeSupply } = require('../core/supply');
const { assertAnalyticsAdmin, assertCoreConfigAdmin } = require('../analytics/access');

const COLLECTION = 'module_config';
const GLOBAL_DOC_ID = 'global';
const AUDIT_KIND = 'core_config_changed';
/** `admin_audit` кам ёзилади: `at` бўйича охирги N таси ўқилиб, `kind` хотирада филтрланади. */
const AUDIT_SCAN_LIMIT = 300;
const AUDIT_SHOWN = 20;
const PROVIDER_SCAN_LIMIT = 2000;
const APPLIES_WITHIN_SECONDS = 60;

function httpError(code, message, details) {
  const e = new Error(message);
  e.code = code;
  if (details) e.details = details;
  return e;
}

function log(fields) {
  console.log(JSON.stringify({ module: 'core_config_admin', ...fields }));
}

function toMs(v) {
  if (!v) return null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return null;
}

function clone(v) {
  return v === undefined ? undefined : JSON.parse(JSON.stringify(v));
}

/** Фаол ҳудудлар (geo_regions), `order` бўйича. */
async function loadRegions(db) {
  const snap = await db.collection('geo_regions').get();
  return snap.docs
    .map((d) => {
      const x = d.data() || {};
      return {
        id: d.id,
        name: String(x.nameUz || x.name || d.id),
        order: Number.isFinite(x.order) ? x.order : 0,
      };
    })
    .sort((a, b) => (a.order - b.order) || a.id.localeCompare(b.id));
}

/** Қатламли конфиг: DEFAULTS < `{module}_all` < `{module}_{ҳудуд}` (`core/config.getModuleConfig`). */
function layered(allDoc, regionDoc) {
  return deepMerge(deepMerge(DEFAULTS, allDoc || {}), regionDoc || {});
}

function ownMinScore(doc) {
  const v = doc && doc.push ? doc.push.minScore : undefined;
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

/** Ҳудудда ишлай оладиган таклифчилар (`isEligible`: ҳуқуқ + хоҳиш). */
async function countProviders(db, module, regionId) {
  const snap = await db.collection('provider_capabilities')
    .where(`${module}.active`, '==', true)
    .where(`${module}.regionIds`, 'array-contains', regionId)
    .limit(1000)
    .get();
  return snap.docs.filter((d) => caps.isEligible(d.data() || {}, module)).length;
}

/**
 * `adminSetCoreConfig({module, regionId, state?, minScore?})`.
 */
function makeAdminSetCoreConfig(deps) {
  const { db, now: nowFn } = deps;

  return async function adminSetCoreConfig(data, context) {
    const started = Date.now();
    const adminId = await assertCoreConfigAdmin(db, context);
    const regions = await loadRegions(db);
    const req = ca.parseSetRequest(data, regions.map((r) => r.id));
    const now = nowFn ? nowFn() : new Date();
    const { module, regionId } = req;
    const mode = modeFor(module);

    // Таклифчи сони — ёқишдан олдинги шарт (транзакциядан ташқарида: сўров).
    const needProviders = req.state !== null && req.state !== 'off';
    const providers = needProviders ? await countProviders(db, module, regionId) : 0;

    const targetKey = moduleRegionKey(module, regionId);
    const allKey = moduleRegionKey(module, 'all');

    try {
      const out = await db.runTransaction(async (tx) => {
        const targetRef = db.collection(COLLECTION).doc(targetKey);
        const tSnap = await tx.get(targetRef);
        const aSnap = regionId === 'all'
          ? tSnap
          : await tx.get(db.collection(COLLECTION).doc(allKey));
        const gSnap = await tx.get(db.collection(COLLECTION).doc(GLOBAL_DOC_ID));

        const tDoc = tSnap.exists ? (tSnap.data() || {}) : {};
        const aDoc = aSnap.exists ? (aSnap.data() || {}) : {};
        const gDoc = gSnap.exists ? (gSnap.data() || {}) : {};

        const regionDocBefore = regionId === 'all' ? {} : tDoc;
        const allDocBefore = regionId === 'all' ? tDoc : aDoc;
        const cfgBefore = layered(allDocBefore, regionDocBefore);
        const from = {
          state: ca.stateOf(gDoc, cfgBefore),
          minScore: ca.effectiveMinScore(regionDocBefore, allDocBefore),
        };

        // Нима ёзилади.
        const patch = {};
        if (req.state) Object.assign(patch, ca.presetFor(req.state));
        if (req.minScore.set) patch.push = { minScore: req.minScore.value };

        // Ўзгариш борми: ҲУЖЖАТНИНГ ўз қийматлари бўйича (глобал kill ҳолатида ҳам
        // модул ҳужжати ёзилиши мумкин, амалдаги ҳолат эса «off»да қолади).
        const flagsChanged = req.state
          ? Object.keys(patch).filter((k) => k !== 'push').some((k) => tDoc[k] !== patch[k])
          : false;
        const minChanged = req.minScore.set && ownMinScore(tDoc) !== req.minScore.value;

        // Ёзилгандан кейинги ҳужжат (null майдонлар ҳам сақланади).
        const tAfter = clone(tDoc);
        if (req.state) Object.assign(tAfter, ca.presetFor(req.state));
        if (req.minScore.set) tAfter.push = { ...(tAfter.push || {}), minScore: req.minScore.value };
        const regionDocAfter = regionId === 'all' ? {} : tAfter;
        const allDocAfter = regionId === 'all' ? tAfter : aDoc;
        const cfgAfter = layered(allDocAfter, regionDocAfter);
        const to = {
          state: ca.stateOf(gDoc, cfgAfter),
          minScore: ca.effectiveMinScore(regionDocAfter, allDocAfter),
        };
        const globalKill = gDoc.enabled === false;

        if (!flagsChanged && !minChanged) {
          return {
            changed: false, module, regionId, configKey: targetKey, from, to: from, globalKill,
          };
        }

        // Қоида: сервер ҳал қилади (экран эмас).
        if (req.state) {
          const verdict = ca.checkEnable({
            state: req.state,
            mode,
            providers,
            minProviders: cfgAfter.enableMinProviders,
            effectiveMinScore: to.minScore,
          });
          if (!verdict.ok) {
            throw httpError('failed-precondition', verdict.message, { reason: verdict.reason });
          }
        }

        const auditRef = db.collection('admin_audit').doc();
        tx.set(targetRef, {
          ...patch,
          module,
          regionId,
          updatedAt: now,
          updatedBy: adminId,
        }, { merge: true });
        tx.set(auditRef, {
          kind: AUDIT_KIND,
          actor: adminId,
          module,
          regionId,
          configKey: targetKey,
          from,
          to,
          requested: {
            state: req.state,
            minScore: req.minScore.set ? req.minScore.value : null,
            minScoreSet: req.minScore.set,
          },
          providers: needProviders ? providers : null,
          at: now,
        });
        return {
          changed: true, module, regionId, configKey: targetKey, from, to, globalKill,
        };
      });

      log({
        action: 'adminSetCoreConfig', result: 'ok', userId: ca.maskActor(adminId), module, regionId,
        changed: out.changed, from: out.from.state, to: out.to.state, duration: Date.now() - started,
      });
      return { ok: true, appliesWithinSeconds: APPLIES_WITHIN_SECONDS, ...out };
    } catch (e) {
      log({
        action: 'adminSetCoreConfig', result: 'error', errorCode: e.code || 'INTERNAL',
        reason: (e.details && e.details.reason) || null, userId: ca.maskActor(adminId), module, regionId,
        duration: Date.now() - started,
      });
      throw e;
    }
  };
}

/**
 * `adminGetCoreOverview({module?})` — ҳудудлар бўйича ҳолат, таклифчилар, аудит.
 * ўқиш: admin / superadmin / dispatcher.
 */
function makeAdminGetCoreOverview(deps) {
  const { db } = deps;

  return async function adminGetCoreOverview(data, context) {
    await assertAnalyticsAdmin(db, context);
    const module = data && data.module !== undefined ? data.module : 'service';
    if (typeof module !== 'string' || !ca.ADMIN_MODULES.includes(module)) {
      throw httpError('invalid-argument', `modul boshqaruvga berilmagan: «${String(module)}»`);
    }
    const mode = modeFor(module);

    const regions = await loadRegions(db);
    const col = db.collection(COLLECTION);
    const refs = [
      col.doc(GLOBAL_DOC_ID),
      col.doc(moduleRegionKey(module, 'all')),
      ...regions.map((r) => col.doc(moduleRegionKey(module, r.id))),
    ];
    const snaps = await db.getAll(...refs);
    const read = (i) => (snaps[i] && snaps[i].exists ? (snaps[i].data() || {}) : {});
    const gDoc = read(0);
    const allDoc = read(1);
    const exists = (i) => Boolean(snaps[i] && snaps[i].exists);

    const minProviders = deepMerge(DEFAULTS, allDoc).enableMinProviders;

    const provSnap = await db.collection('provider_capabilities')
      .where(`${module}.active`, '==', true)
      .limit(PROVIDER_SCAN_LIMIT)
      .get();
    const supply = summarizeSupply({
      capDocs: provSnap.docs.map((d) => d.data() || {}),
      regionIds: regions.map((r) => r.id),
      min: minProviders,
      service: module,
    });
    const supplyBy = new Map(supply.rows.map((r) => [r.regionId, r]));

    const rows = regions.map((r, i) => {
      const regionDoc = read(2 + i);
      const cfg = layered(allDoc, regionDoc);
      const errors = validateConfig(cfg);
      const s = supplyBy.get(r.id) || { providers: 0, ready: false };
      const row = {
        regionId: r.id,
        name: r.name,
        state: ca.stateOf(gDoc, cfg),
        providers: s.providers,
        ready: s.ready,
        minScore: ca.effectiveMinScore(regionDoc, allDoc),
        ownConfig: exists(2 + i),
      };
      if (errors.length) row.configErrors = errors;
      return row;
    });

    const auditSnap = await db.collection('admin_audit')
      .orderBy('at', 'desc').limit(AUDIT_SCAN_LIMIT).get();
    const audit = auditSnap.docs
      .map((d) => ({ id: d.id, a: d.data() || {} }))
      .filter((x) => x.a.kind === AUDIT_KIND)
      .map((x) => ({
        id: x.id,
        at: toMs(x.a.at),
        actor: ca.maskActor(x.a.actor),
        module: x.a.module || '',
        regionId: x.a.regionId || '',
        from: x.a.from || null,
        to: x.a.to || null,
      }))
      .sort((p, q) => (q.at || 0) - (p.at || 0))
      .slice(0, AUDIT_SHOWN);

    return {
      ok: true,
      module,
      mode,
      minProviders,
      minScoreAll: ca.effectiveMinScore({}, allDoc),
      globalKill: { active: gDoc.enabled === false, reason: String(gDoc.reason || '') },
      rows,
      audit,
    };
  };
}

module.exports = { makeAdminSetCoreConfig, makeAdminGetCoreOverview, AUDIT_KIND };
