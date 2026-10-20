'use strict';

/**
 * «ТАЛАБ ЯДРОСИ» АДМИН ҚОИДАЛАРИ — тоза функциялар (Фирестор йўқ).
 *
 * `module_config/{module}_{region}` калити ва `push.minScore` чегарасини
 * админ панелдан бошқариш (ега 2026-10-20). Қарорлар:
 *   - Вариант А: ҳудуд бўйича, ишлай оладиган таклифчи >= N (стандарт 5) бўлганда;
 *   - Вариант 3: push чегараси ўлчаб қўйилмагунча push ёқилмайди.
 * Бу қоидалар ЭКРАНДА эмас, СЕРВЕРДА текширилади (18, 44-банд): экран фақат
 * сабабни кўрсатади.
 */

/** Админ экрани бошқарадиган модуллар (адаптери бор, quote режими). */
const ADMIN_MODULES = ['service'];

/** Бошқариладиган ҳолатлар. */
const STATES = ['off', 'shadow', 'push'];

const ALLOWED_KEYS = new Set(['module', 'regionId', 'state', 'minScore']);
const MIN_SCORE_LOW = 0.01;

function fail(code, message) {
  const e = new Error(message);
  e.code = code;
  return e;
}

/** `module_config` модул ҳужжатига ёзиладиган калитлар. */
function presetFor(state) {
  switch (state) {
    case 'off': return { enabled: false, matchingEnabled: false, pushEnabled: false };
    case 'shadow': return { enabled: true, matchingEnabled: true, pushEnabled: false };
    case 'push': return { enabled: true, matchingEnabled: true, pushEnabled: true };
    default: throw new Error(`noma'lum holat: «${String(state)}»`);
  }
}

/**
 * Амалдаги ҳолат — `core/config.resolveFlags` мантиғи (глобал VA модул, AND).
 *
 * @param {object} globalDoc `module_config/global` (бўш бўлса — рухсат берувчи)
 * @param {object} cfg модулнинг ЯКУНИЙ (қатламли) конфиги
 * @returns {'off'|'matching_off'|'shadow'|'push'}
 */
function stateOf(globalDoc, cfg) {
  const g = globalDoc || {};
  const c = cfg || {};
  const enabled = g.enabled !== false && c.enabled === true;
  if (!enabled) return 'off';
  const matching = g.matchingEnabled !== false && c.matchingEnabled !== false;
  if (!matching) return 'matching_off';
  const push = g.pushEnabled !== false && c.pushEnabled === true;
  return push ? 'push' : 'shadow';
}

/**
 * Клиент юкламасини текширади. Ортиқча майдонлар РАД этилади: клиент
 * `enabled`/`pushEnabled`ни ўзи юбориб, қоидаларни четлаб ўтмасин.
 *
 * @returns {{module: string, regionId: string, state: (string|null),
 *            minScore: {set: boolean, value: (number|null)}}}
 */
function parseSetRequest(data, regionIds) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw fail('invalid-argument', 'so\'rov noto\'g\'ri');
  }
  for (const k of Object.keys(data)) {
    if (!ALLOWED_KEYS.has(k)) throw fail('invalid-argument', `noma'lum maydon: «${k}»`);
  }
  if (typeof data.module !== 'string' || !ADMIN_MODULES.includes(data.module)) {
    throw fail('invalid-argument', `modul boshqaruvga berilmagan: «${String(data.module)}»`);
  }
  const hasState = data.state !== undefined;
  const hasMin = Object.prototype.hasOwnProperty.call(data, 'minScore');
  if (!hasState && !hasMin) {
    throw fail('invalid-argument', 'holat yoki minScore berilishi kerak');
  }
  if (typeof data.regionId !== 'string' || data.regionId === '') {
    throw fail('invalid-argument', 'regionId majburiy');
  }
  const regions = new Set(regionIds || []);

  let state = null;
  if (hasState) {
    if (typeof data.state !== 'string' || !STATES.includes(data.state)) {
      throw fail('invalid-argument', `noma'lum holat: «${String(data.state)}»`);
    }
    if (!regions.has(data.regionId)) {
      // `all` ham shu yerda: variant A — hudud faqat shu yerda taklifchi yetarli bo'lganda yoqiladi.
      throw fail(
        'invalid-argument',
        `holat faqat aniq hudud uchun (variant A); noma'lum hudud: «${data.regionId}»`,
      );
    }
    state = data.state;
  }

  const minScore = { set: false, value: null };
  if (hasMin) {
    const v = data.minScore;
    if (v !== null && (typeof v !== 'number' || !Number.isFinite(v) || v < MIN_SCORE_LOW || v > 1)) {
      throw fail('invalid-argument', `minScore null yoki ${MIN_SCORE_LOW}..1 bo'lishi kerak, berilgan: ${String(v)}`);
    }
    if (data.regionId !== 'all' && !regions.has(data.regionId)) {
      throw fail('invalid-argument', `noma'lum hudud: «${data.regionId}»`);
    }
    minScore.set = true;
    minScore.value = v;
  }
  return { module: data.module, regionId: data.regionId, state, minScore };
}

/**
 * Ёқиш мумкинми — сервер қоидаси.
 *
 * @param {object} p
 * @param {'off'|'shadow'|'push'} p.state
 * @param {string} p.mode модул режими (`dispatch` | `quote` | ...)
 * @param {number} p.providers ҳудудда ишлай оладиган таклифчилар
 * @param {number} p.minProviders N (эга: 5)
 * @param {(number|null)} p.effectiveMinScore қатламли push чегараси
 * @returns {{ok: boolean, reason: (string|null), message: string}}
 */
function checkEnable({ state, mode, providers, minProviders, effectiveMinScore }) {
  if (!Number.isInteger(minProviders) || minProviders < 1) {
    throw new Error(`minProviders butun son >= 1 bo'lishi kerak, berilgan: ${String(minProviders)}`);
  }
  if (state === 'off') return { ok: true, reason: null, message: '' };
  if (!(providers >= minProviders)) {
    return {
      ok: false,
      reason: 'not_enough_providers',
      message: `Hududda ishlay oladigan taklifchi ${providers} ta, kamida ${minProviders} ta kerak`,
    };
  }
  if (state === 'push' && mode !== 'dispatch' && (effectiveMinScore === null || effectiveMinScore === undefined)) {
    return {
      ok: false,
      reason: 'min_score_not_calibrated',
      message: 'Push chegarasi (push.minScore) hali o\'lchab tanlanmagan: avval 50 moslikni baholang',
    };
  }
  return { ok: true, reason: null, message: '' };
}

/**
 * Қатламли push чегараси: ҳудуд ҳужжатидаги СОН `_all`дагидан устун;
 * `null`/яроқсиз қиймат ҳеч нарсани бекор қилмайди (`core/config.deepMerge`
 * қоидаси: null ва undefined ўтказиб юборилади).
 */
function effectiveMinScore(regionDoc, allDoc) {
  const pick = (d) => {
    const v = d && d.push ? d.push.minScore : undefined;
    return typeof v === 'number' && Number.isFinite(v) ? v : null;
  };
  const own = pick(regionDoc);
  return own !== null ? own : pick(allDoc);
}

/** Телефон ниқоби: 9989012****67 (аудит асбоблари билан бир хил). */
function maskActor(id) {
  const s = String(id || '');
  if (!/^\d{9,12}$/.test(s)) return s ? '***' : '';
  return `${s.slice(0, 7)}****${s.slice(-2)}`;
}

module.exports = {
  ADMIN_MODULES, STATES, presetFor, stateOf, parseSetRequest, checkEnable,
  effectiveMinScore, maskActor,
};
