/**
 * «Уй-жой бозори» — эълоннинг ИХТИЁРИЙ қўшимча майдонлари (эга қарори
 * 2026-11-19). СОФ мантиқ: `functions/realty.js` ишлатади, алоҳида тест —
 * `functions/test/realty_fields.test.js`.
 *
 * Орқага мослик (CLAUDE §26): ҳамма майдон ихтиёрий.
 *  - Калит сўровда ЙЎҚ бўлса — натижада ҳам йўқ: яратишда ёзилмайди,
 *    таҳрирда ҳужжатдаги эски қиймат ТЕГИЛМАЙДИ (эски APK янги майдонларни
 *    юбормайди — уларни ўчириб юбормаслиги керак).
 *  - Калит бор, қиймат `null`/'' — «тозалаш» (таҳрирда FieldValue.delete).
 *  - Нотўғри қиймат — `{ error: '<field>_invalid' }` (чақирувчи
 *    `invalid-argument` қилади; клиент дўстона матн кўрсатади).
 *
 * Пул — бутун сон (CLAUDE §8): `deposit` бутун; `priceCurrency` фақат
 * `priceAmount` нинг валютаси (йўқ бўлса — UZS, эски ёзувлар ҳам UZS).
 */
'use strict';

const PROPERTY_TYPES = ['apartment', 'house', 'land', 'commercial', 'office', 'other'];
const RENOVATIONS = ['none', 'cosmetic', 'euro', 'design'];
const BUILDING_TYPES = ['brick', 'panel', 'monolith', 'block', 'wood', 'other'];
const UTILITIES = ['gas', 'water', 'electricity', 'sewer', 'heating', 'internet'];
const DOCUMENTS = ['ready', 'in_progress', 'none'];
const BATHROOMS = ['separate', 'combined'];
const CURRENCIES = ['UZS', 'USD'];
const RENT_PERIODS = ['month', 'day'];

/** Эълондаги расмлар чегараси (эга 2026-11-19: 5 → 10). */
const MAX_IMAGES = 10;

const LAND_SOTIX_MIN = 0.1;
const LAND_SOTIX_MAX = 10000;
const YEAR_MIN = 1900;
const DEPOSIT_MAX = 1e12;

/** Сотих фақат шу турларда маъноли (ҳовли ва ер). */
const SOTIX_TYPES = ['house', 'land'];

/** Ер участкасида маъносиз майдонлар — сервер тозалайди. */
const LAND_CLEARS = ['renovation', 'buildingType', 'bathroom', 'balcony', 'furnished'];
const LAND_CLEARS_BASE = ['rooms', 'floor', 'totalFloors'];

const ENUMS = {
  propertyType: [PROPERTY_TYPES, 'property_type_invalid'],
  renovation: [RENOVATIONS, 'renovation_invalid'],
  buildingType: [BUILDING_TYPES, 'building_type_invalid'],
  documents: [DOCUMENTS, 'documents_invalid'],
  bathroom: [BATHROOMS, 'bathroom_invalid'],
  rentPeriod: [RENT_PERIODS, 'rent_period_invalid'],
};

const FLAGS = {
  furnished: 'furnished_invalid',
  balcony: 'balcony_invalid',
  parking: 'parking_invalid',
  negotiable: 'negotiable_invalid',
  mortgage: 'mortgage_invalid',
  barter: 'barter_invalid',
};

/** Барча қўшимча калитлар (таҳрирда «тегилмайди/ўчирилади» учун). */
const EXTRA_KEYS = [
  'propertyType', 'landSotix', 'renovation', 'buildingType', 'yearBuilt',
  'utilities', 'documents', 'furnished', 'bathroom', 'balcony', 'parking',
  'priceCurrency', 'rentPeriod', 'deposit', 'negotiable', 'mortgage', 'barter',
];

const isEmpty = (v) => v === undefined || v === null || v === '';

/**
 * [d] — callable `data`. [deal] — текширилган битим ('sale'|'rent').
 * [currentPropertyType] — таҳрирда ҳужжатдаги жорий тур (калит келмаса
 * шу ҳисобга олинади). Қайтаради: `{ values, clearBase }` ёки `{ error }`.
 * `values[k] === null` — тозалаш; `clearBase` — асосий майдонлар
 * (`rooms`/`floor`/`totalFloors`) ер участкасида тозаланади.
 */
function parseRealtyExtras(d, {
  deal = 'sale',
  currentPropertyType = null,
  nowYear = new Date().getUTCFullYear(),
} = {}) {
  const src = d || {};
  const has = (k) => Object.prototype.hasOwnProperty.call(src, k);
  const values = {};

  for (const [key, [allowed, code]] of Object.entries(ENUMS)) {
    if (!has(key)) continue;
    const raw = src[key];
    if (isEmpty(raw)) { values[key] = null; continue; }
    if (typeof raw !== 'string' || !allowed.includes(raw)) return { error: code };
    values[key] = raw;
  }

  for (const [key, code] of Object.entries(FLAGS)) {
    if (!has(key)) continue;
    const raw = src[key];
    if (isEmpty(raw)) { values[key] = null; continue; }
    if (typeof raw !== 'boolean') return { error: code };
    values[key] = raw;
  }

  if (has('landSotix')) {
    const raw = src.landSotix;
    if (isEmpty(raw)) {
      values.landSotix = null;
    } else {
      const n = Number(raw);
      if (typeof raw === 'boolean' || !Number.isFinite(n)
          || n < LAND_SOTIX_MIN || n > LAND_SOTIX_MAX) {
        return { error: 'land_sotix_invalid' };
      }
      // 2 хонагача — «6.25 сотих»; ортиғи маъносиз ва float шовқини.
      values.landSotix = Math.round(n * 100) / 100;
    }
  }

  if (has('yearBuilt')) {
    const raw = src.yearBuilt;
    if (isEmpty(raw)) {
      values.yearBuilt = null;
    } else {
      const n = Number(raw);
      if (typeof raw === 'boolean' || !Number.isInteger(n)
          || n < YEAR_MIN || n > nowYear + 2) {
        return { error: 'year_built_invalid' };
      }
      values.yearBuilt = n;
    }
  }

  if (has('deposit')) {
    const raw = src.deposit;
    if (isEmpty(raw)) {
      values.deposit = null;
    } else {
      const n = Number(raw);
      if (typeof raw === 'boolean' || !Number.isInteger(n) || n < 1 || n > DEPOSIT_MAX) {
        return { error: 'deposit_invalid' };
      }
      values.deposit = n;
    }
  }

  if (has('priceCurrency')) {
    const raw = src.priceCurrency;
    if (isEmpty(raw)) {
      values.priceCurrency = null;
    } else {
      const c = typeof raw === 'string' ? raw.trim().toUpperCase() : '';
      if (!CURRENCIES.includes(c)) return { error: 'currency_invalid' };
      values.priceCurrency = c;
    }
  }

  if (has('utilities')) {
    const raw = src.utilities;
    if (isEmpty(raw)) {
      values.utilities = null;
    } else {
      if (!Array.isArray(raw) || raw.length > UTILITIES.length * 2) {
        return { error: 'utilities_invalid' };
      }
      for (const u of raw) {
        if (typeof u !== 'string' || !UTILITIES.includes(u)) {
          return { error: 'utilities_invalid' };
        }
      }
      // Каноник тартиб, такрорсиз — бир хил танлов бир хил ёзилсин.
      const set = UTILITIES.filter((u) => raw.includes(u));
      values.utilities = set.length ? set : null;
    }
  }

  // ─── Майдонлараро қоидалар ───
  // Сотувда ижара шартлари маъносиз — доим тозаланади (эски APK битимни
  // «сотув»га ўзгартирса ҳам эски депозит қолиб кетмасин).
  if (deal !== 'rent') {
    values.rentPeriod = null;
    values.deposit = null;
  }
  const type = has('propertyType') ? values.propertyType : (currentPropertyType || null);
  if (type && !SOTIX_TYPES.includes(type)) values.landSotix = null;
  let clearBase = [];
  if (type === 'land') {
    for (const k of LAND_CLEARS) values[k] = null;
    clearBase = LAND_CLEARS_BASE.slice();
  }
  return { values, clearBase };
}

/** Яратиш учун: фақат қиймати борлари (null — ёзилмайди). */
function extrasForCreate(values) {
  const out = {};
  for (const [k, v] of Object.entries(values || {})) {
    if (v !== null && v !== undefined) out[k] = v;
  }
  return out;
}

/** Таҳрир учун: null → [del] (ўчириш), калити йўқ → тегилмайди. */
function extrasForUpdate(values, del) {
  const out = {};
  for (const [k, v] of Object.entries(values || {})) {
    out[k] = v === null || v === undefined ? del : v;
  }
  return out;
}

module.exports = {
  PROPERTY_TYPES,
  RENOVATIONS,
  BUILDING_TYPES,
  UTILITIES,
  DOCUMENTS,
  BATHROOMS,
  CURRENCIES,
  RENT_PERIODS,
  MAX_IMAGES,
  LAND_SOTIX_MIN,
  LAND_SOTIX_MAX,
  YEAR_MIN,
  EXTRA_KEYS,
  parseRealtyExtras,
  extrasForCreate,
  extrasForUpdate,
};
