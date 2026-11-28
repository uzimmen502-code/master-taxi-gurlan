/* NUSXA — manba: functions/module_gate.js. QO'LDA TAHRIRLANMAYDI.
 * Firebase deploy faqat o'z codebase papkasini yuklaydi, shuning uchun
 * demand codebase (requestCapability: courier) uchun nusxa kerak. Paritet:
 * functions/test/module_gate_parity.test.js (bayt-ma-bayt).
 * Yangilash: node functions/tools/sync_module_gate.js */
/**
 * МОДУЛ ДАРВОЗАСИ — СЕРВЕР ТОМОНИ (аудит 2026-10-31, MEDIUM-4).
 *
 * Муаммо: админ «Ҳудудлар ва хизматлар»даги модул ҳолати (enabled / coming_soon / soon / hidden)
 * фақат Flutter клиентида текширилар эди — эски/ўзгартирилган клиент ёпиқ модулда ҳам «＋» орқали
 * янги объект ярата оларди (18-банд: клиентга ишонма).
 *
 * Бу файл клиент мантиғининг АЙНАН нусхаси (манба):
 *   lib/core/service_config_holder.dart        — statusOf / effective / _isConfigured, enforce=false
 *   lib/models/service_module_config.dart      — ModuleStatus.fromWire, fromMap, merge
 *   lib/repositories/service_config_repository — тумани/MFY override фақат `manualModules` калитлари
 *
 * Қатламлар (чапдан ўнгга устунлик): `config/module_defaults` → `geo_district_modules/{districtId}`
 * → `service_area_modules/{areaId}`. Фойдаланувчи ҳудуди — `users/{uid}.districtId` /
 * `.serviceAreaId` (zone_gate.dart ва home_screen.dart: `applyGeo`); `districtId` бўш бўлиб
 * `serviceAreaId` бор бўлса — `service_areas/{areaId}.districtId` (`applyServiceArea`).
 *
 *   enforce == true  → effective = (defaults бўш ? {} : defaults) ⊕ district ⊕ area; топилмаса hidden.
 *   enforce != true  → модул бирор қатламда БОР бўлса enabled, бўлмаса hidden (клиент kill-switch'и).
 *   open             ⇔ status == 'enabled' (`ModuleStatus.isOpenable`).
 *
 * Клиентдан ОНГЛИ фарқлар (сабаби билан):
 *   • FAIL-OPEN: конфиг/фойдаланувчи ҳужжатини ўқиш хатоси → `open: true` (reason
 *     `CONFIG_READ_FAILED`) + structured warning. Вақтинчалик Firestore хатоси ҳақиқий
 *     фойдаланувчиларни тўсиб қўймасин (эга шарти).
 *   • `config/module_defaults` ҲУЖЖАТИ УМУМАН ЙЎҚ → `open: true` (reason `CONFIG_MISSING`).
 *     Клиент бу ҳолда ҳаммасини яширади; сервер эса конфиг ўрнатилмаган муҳитни (янги лойиҳа,
 *     demo/emulator) «ҳамма ёпиқ» деб талқин қилмайди. Prod'да ҳужжат бор (enforce=true).
 *   • APK `kKnownModuleIds` runtime gate'и серверда йўқ — сервер фақат ўзига маълум модул
 *     id'лари учун чақирилади.
 *
 * Кэш: конфиг ҳужжатлари (defaults, district, area, service_areas) инстанс хотирасида
 * `CACHE_TTL_MS` (60 с) — админ ўзгартиргандан кейин энг кўпи 60 с эски ҳолат. `users`
 * ҳужжати кэшланмайди (ҳудудни ўзгартирган фойдаланувчи дарҳол янги қоидани олади).
 * Ўқишлар: биринчи чақирувда ≤4, кэш иссиқ бўлса 1 (users) — 37-банд.
 *
 * ЭСЛАТМА: `functions_demand/core/module_gate.js` — шу файлнинг байтма-байт НУСХАСИ
 * (Firebase deploy фақат ўз codebase папкасини юклайди). Янгилаш:
 *   node functions/tools/sync_module_gate.js
 * Паритет: functions/test/module_gate_parity.test.js
 */
'use strict';

const MODULE_CLOSED = 'MODULE_CLOSED';
const CACHE_TTL_MS = 60 * 1000;
const ID_RE = /^[A-Za-z0-9_-]{1,128}$/;

/** Dart `ModuleStatus.fromWire` (номаълум → hidden). */
function statusFromWire(raw) {
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

const isPlainMap = (v) => v != null && typeof v === 'object' && !Array.isArray(v);

/**
 * Dart `ServiceModuleConfig.fromMap`: `modules` Map бўлса — у, бўлмаса бутун ҳужжат;
 * қиймат `{status}` ёки тўғридан-тўғри сатр.
 */
function configFromMap(data) {
  if (!isPlainMap(data) || Object.keys(data).length === 0) return {};
  const source = isPlainMap(data.modules) ? data.modules : data;
  const out = {};
  for (const key of Object.keys(source)) {
    const v = source[key];
    out[String(key)] = statusFromWire(isPlainMap(v) ? v.status : v);
  }
  return out;
}

/** Туман/MFY override: фақат `manualModules` даги ВА конфигда бор калитлар (репозиторий). */
function overrideFromDoc(data) {
  if (!isPlainMap(data)) return {};
  const manual = new Set();
  if (Array.isArray(data.manualModules)) {
    for (const e of data.manualModules) {
      const id = String(e == null ? '' : e).trim();
      if (id) manual.add(id);
    }
  }
  if (manual.size === 0) return {};
  const cfg = configFromMap(data);
  const out = {};
  for (const id of manual) {
    if (Object.prototype.hasOwnProperty.call(cfg, id)) out[id] = cfg[id];
  }
  return out;
}

/**
 * СОФ ҳисоб (клиент `ServiceConfigHolder.statusOf` нинг нусхаси).
 * @param {{defaults: object|null, enforce: boolean, district: object, area: object}} layers
 *   `defaults` — `configFromMap` натижаси, `district`/`area` — `overrideFromDoc` натижаси.
 */
function computeModuleStatus(layers, moduleId) {
  const defaults = layers.defaults || {};
  const district = layers.district || {};
  const area = layers.area || {};
  const has = (m) => Object.prototype.hasOwnProperty.call(m, moduleId);
  if (layers.enforce !== true) {
    return has(defaults) || has(district) || has(area) ? 'enabled' : 'hidden';
  }
  // enforce=true ва defaults бўш → база бўш (fallback allEnabled ИШЛАТИЛМАЙДИ).
  const effective = { ...defaults, ...district, ...area };
  return has(effective) ? effective[moduleId] : 'hidden';
}

// ── Кэш ───────────────────────────────────────────────────────────────
const cache = new Map();

function resetCache() {
  cache.clear();
}

async function cachedDoc(db, collection, id, nowMs) {
  const key = `${collection}/${id}`;
  const hit = cache.get(key);
  if (hit && hit.expires > nowMs) return hit.value;
  const snap = await db.collection(collection).doc(id).get();
  const value = snap.exists ? (snap.data() || {}) : null;
  cache.set(key, { value, expires: nowMs + CACHE_TTL_MS });
  return value;
}

function phoneDocIds(userId) {
  const d = String(userId == null ? '' : userId).replace(/\D/g, '');
  if (d.length === 12 && d.startsWith('998')) return [d, d.slice(3)];
  if (d.length === 9) return [`998${d}`, d];
  return d ? [d] : [];
}

async function userGeo(db, userId) {
  for (const id of phoneDocIds(userId)) {
    const snap = await db.collection('users').doc(id).get();
    if (!snap.exists) continue;
    const u = snap.data() || {};
    return {
      districtId: String(u.districtId || '').trim(),
      serviceAreaId: String(u.serviceAreaId || '').trim(),
    };
  }
  return { districtId: '', serviceAreaId: '' };
}

function warn(fields) {
  console.warn(JSON.stringify({ module: 'module_gate', severity: 'WARNING', ...fields }));
}

/**
 * Фойдаланувчи учун модул очиқми.
 * @returns {Promise<{open: boolean, status: string, reason: string|null}>}
 *   reason: null (очиқ), 'MODULE_CLOSED', 'CONFIG_MISSING', 'CONFIG_READ_FAILED'.
 */
/**
 * Клиент юборган ФАОЛ туман (бош экран тепасида танланган ҳудуд, `data.geoDistrictId`).
 * Эга қарори (2026-10-31, «А вариант»): хизматлар танланган ҳудуд бўйича — клиент
 * `ServiceConfigHolder.applyActiveDistrict` билан бир хил. Нотўғри шакл — эътиборсиз (профил туман).
 * Хавфсизлик: бу маҳсулот мавжудлиги қоидаси; фойдаланувчи тепада исталган туманни танлай олади,
 * шунинг учун уни юбориш ортиқча ҳуқуқ бермайди.
 */
function activeDistrictFrom(raw) {
  const id = String(raw == null ? '' : raw).trim();
  return /^[a-z0-9_]{1,64}$/.test(id) ? id : '';
}

async function moduleOpenFor(db, moduleId, userId, opts = {}) {
  const nowMs = typeof opts.nowMs === 'number' ? opts.nowMs : Date.now();
  try {
    const defaultsDoc = await cachedDoc(db, 'config', 'module_defaults', nowMs);
    if (defaultsDoc == null) {
      return { open: true, status: 'unknown', reason: 'CONFIG_MISSING' };
    }
    const geo = await userGeo(db, userId);
    let districtId = geo.districtId;
    let areaId = geo.serviceAreaId;
    if (!districtId && areaId && ID_RE.test(areaId)) {
      const areaDoc = await cachedDoc(db, 'service_areas', areaId, nowMs);
      districtId = String((areaDoc && areaDoc.districtId) || '').trim();
    }
    // Фаол туман яшаш жойидан бошқа — ўша туман override'и; МФЙ override'и яшаш жойиники, қўлланмайди.
    const active = activeDistrictFrom(opts.activeDistrictId);
    if (active && active !== districtId) {
      districtId = active;
      areaId = '';
    }
    const [districtDoc, areaModulesDoc] = await Promise.all([
      districtId && ID_RE.test(districtId)
        ? cachedDoc(db, 'geo_district_modules', districtId, nowMs) : null,
      areaId && ID_RE.test(areaId)
        ? cachedDoc(db, 'service_area_modules', areaId, nowMs) : null,
    ]);
    const status = computeModuleStatus({
      defaults: configFromMap(defaultsDoc),
      enforce: defaultsDoc.enforce === true,
      district: overrideFromDoc(districtDoc),
      area: overrideFromDoc(areaModulesDoc),
    }, moduleId);
    const open = status === 'enabled';
    return { open, status, reason: open ? null : MODULE_CLOSED };
  } catch (e) {
    warn({
      action: 'moduleOpenFor', result: 'fail_open', errorCode: 'CONFIG_READ_FAILED',
      moduleId, error: String((e && e.message) || e).slice(0, 200),
    });
    return { open: true, status: 'unknown', reason: 'CONFIG_READ_FAILED' };
  }
}

module.exports = {
  MODULE_CLOSED,
  CACHE_TTL_MS,
  statusFromWire,
  configFromMap,
  overrideFromDoc,
  computeModuleStatus,
  activeDistrictFrom,
  moduleOpenFor,
  resetCache,
};
