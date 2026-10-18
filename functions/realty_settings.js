/**
 * «Кўчмас мулк» — объект сонлари созламалари (СОФ мантиқ).
 *
 * Аввал бу сонлар кодда қотирилган эди (бепул лимит — 2, ахборот пакети — 5/10
 * объект) ва ўзгартириш учун релиз керак эди. Энди ҳаммаси `settings/app`да
 * (веб админ панел: «Кўчмас мулк кластери — нарх ва созламалар»); код фақат
 * БОШЛАНҒИЧ қийматни ва ХАВФСИЗ ЧЕГАРАНИ сақлайди — админ панелдаги хато
 * (масалан, лимитга иккита қўшимча ноль) тизимни ишдан чиқармасин.
 *
 *   realtyFreeLimit        — бепул ОДДИЙ объект ўринлари (1…50, бошланғич 2)
 *   realtyPackagePricing   — ахборот пакети: `{ "5": 30000, "10": 50000 }`;
 *                            ўлчамлар — калитлар (1…100, энг кўпи 6 та)
 *   realtyProPlans         — профессионал режалар (`functions/realty.js`
 *                            `proPlans`; объект сони `MAX_PRO_OBJECTS` дан ошмайди)
 */
'use strict';

const FREE_LIMIT_DEFAULT = 2;
const FREE_LIMIT_MIN = 1;
const FREE_LIMIT_MAX = 50;

const PACKAGE_SIZES_DEFAULT = [5, 10];
const PACKAGE_SIZE_MAX = 100;
const PACKAGE_SIZES_MAX_COUNT = 6;

/**
 * Бепул ОДДИЙ объект лимити. Йўқ/яроқсиз — бошланғич (2); чегарадан
 * ташқарида — энг яқин чегара. Камида 1: 0 бўлса иловада «маълумот йўқ»
 * (`limit == 0`) билан чалкашарди.
 */
function freeLimitFrom(app) {
  const raw = (app || {}).realtyFreeLimit;
  if (raw === undefined || raw === null || raw === '') return FREE_LIMIT_DEFAULT;
  const v = Math.round(Number(raw));
  if (!Number.isFinite(v)) return FREE_LIMIT_DEFAULT;
  return Math.min(FREE_LIMIT_MAX, Math.max(FREE_LIMIT_MIN, v));
}

/**
 * Ахборот пакети ўлчамлари — `realtyPackagePricing` калитларидан (нархи
 * тўғри ва ≥ 0 бўлганлари), ўсиш тартибида. Бўш/яроқсиз бўлса — бошланғич
 * [5, 10] (эски ҳужжатлар учун орқага мослик).
 */
function packageSizesFrom(app) {
  const map = (app || {}).realtyPackagePricing;
  if (!map || typeof map !== 'object') return PACKAGE_SIZES_DEFAULT.slice();
  const sizes = [];
  for (const [k, price] of Object.entries(map)) {
    if (!/^\d+$/.test(k)) continue;
    const size = Number(k);
    const p = Number(price);
    if (size < 1 || size > PACKAGE_SIZE_MAX) continue;
    if (price === null || price === undefined || !Number.isFinite(p) || p < 0) continue;
    sizes.push(size);
  }
  const unique = [...new Set(sizes)].sort((a, b) => a - b).slice(0, PACKAGE_SIZES_MAX_COUNT);
  return unique.length ? unique : PACKAGE_SIZES_DEFAULT.slice();
}

const PLAN_ID_RE = /^[a-z0-9_]{2,24}$/;
const MAX_PLANS = 6;
const MAX_PLAN_DAYS = 365;
const MAX_MONEY = 1e10; // бутун сўм (8-қоида)

class CountsError extends Error {
  constructor(reason, details) {
    super(reason);
    this.reason = reason;
    this.details = details || {};
  }
}

function intIn(v, min, max) {
  if (v === '' || v === null || v === undefined) return null;
  const n = typeof v === 'number' ? v : Number(String(v).trim());
  return Number.isInteger(n) && n >= min && n <= max ? n : null;
}

/**
 * Админ панелдан келган объект сонлари созламаларини текширади (СЕРВЕР
 * ҲАЛ ҚИЛУВЧИ: клиент текшируви фақат қулайлик учун — 18-қоида).
 *
 * Киришда: `freeLimit` (бўш/`null` — бошланғичга қайтариш), `packages`
 * `[{size, price}]`, `proPlans` `[{id, objects, days, price}]`.
 * Қайтаради тозаланган `{freeLimit, packagePricing, proPlans}`; хатода
 * [CountsError] (`reason` + `details.index`).
 */
function parseCounts(input, { maxProObjects }) {
  const d = input || {};

  // ── бепул лимит ──
  let freeLimit = null;
  if (d.freeLimit !== '' && d.freeLimit !== null && d.freeLimit !== undefined) {
    freeLimit = intIn(d.freeLimit, FREE_LIMIT_MIN, FREE_LIMIT_MAX);
    if (freeLimit === null) {
      throw new CountsError('free_limit_invalid', { min: FREE_LIMIT_MIN, max: FREE_LIMIT_MAX });
    }
  }

  // ── ахборот пакети ──
  const pk = Array.isArray(d.packages) ? d.packages : [];
  if (pk.length < 1 || pk.length > PACKAGE_SIZES_MAX_COUNT) {
    throw new CountsError('package_count_invalid', { min: 1, max: PACKAGE_SIZES_MAX_COUNT });
  }
  const rows = [];
  pk.forEach((p, index) => {
    const size = intIn((p || {}).size, 1, PACKAGE_SIZE_MAX);
    const price = intIn((p || {}).price, 0, MAX_MONEY);
    if (size === null || price === null) {
      throw new CountsError('package_invalid', { index, maxSize: PACKAGE_SIZE_MAX });
    }
    rows.push({ size, price, index });
  });
  if (new Set(rows.map((r) => r.size)).size !== rows.length) {
    throw new CountsError('package_duplicate_size');
  }
  rows.sort((a, b) => a.size - b.size);
  // Катта пакет битта объект ҳисобида қиммат бўлмаслиги шарт, акс ҳолда уни
  // ҳеч ким олмайди. Бутун сўмда солиштирамиз (суратни кесиш: p1*s2 > p2*s1).
  for (let i = 1; i < rows.length; i += 1) {
    const small = rows[i - 1];
    const big = rows[i];
    if (big.price * small.size > small.price * big.size) {
      throw new CountsError('package_per_object', { size: big.size, than: small.size });
    }
  }
  const packagePricing = {};
  for (const r of rows) packagePricing[String(r.size)] = r.price;

  // ── профессионал режалар ──
  const pl = Array.isArray(d.proPlans) ? d.proPlans : [];
  if (pl.length < 1 || pl.length > MAX_PLANS) {
    throw new CountsError('plan_count_invalid', { min: 1, max: MAX_PLANS });
  }
  const plans = [];
  const ids = new Set();
  pl.forEach((p, index) => {
    const x = p || {};
    const id = String(x.id || '').trim();
    const objects = intIn(x.objects, 1, maxProObjects);
    const days = intIn(x.days, 1, MAX_PLAN_DAYS);
    const price = intIn(x.price, 0, MAX_MONEY);
    if (!PLAN_ID_RE.test(id) || objects === null || days === null || price === null) {
      throw new CountsError('plan_invalid', { index, maxObjects: maxProObjects, maxDays: MAX_PLAN_DAYS });
    }
    if (ids.has(id)) throw new CountsError('plan_duplicate_id', { index });
    ids.add(id);
    plans.push({ id, objects, days, price });
  });

  return { freeLimit, packagePricing, proPlans: plans };
}

module.exports = {
  CountsError,
  parseCounts,
  MAX_PLANS,
  FREE_LIMIT_DEFAULT,
  FREE_LIMIT_MIN,
  FREE_LIMIT_MAX,
  PACKAGE_SIZES_DEFAULT,
  PACKAGE_SIZE_MAX,
  PACKAGE_SIZES_MAX_COUNT,
  freeLimitFrom,
  packageSizesFrom,
};
