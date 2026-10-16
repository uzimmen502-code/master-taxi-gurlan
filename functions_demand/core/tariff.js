'use strict';

/**
 * AVA LOGISTICS — TARIF DVIGATELI (D-2, D-8; CLAUDE.md 9…14-bandlar).
 *
 * ── NIMA ────────────────────────────────────────────────────────────────
 * Mijoz narxi (`customerPrice`) ZONA va O'LCHOVLI VAZN bo'yicha hisoblanadi.
 * Zona — origin↔destination MATRITSASIDAN olinadi (D-2): zona «ma'nosi»
 * kodga YOZILMAYDI, matritsa yagona manba. Eski Z1–Z5 modeli bekor.
 *
 * ── TARIF HUJJATI (versiyali, 9-band) ───────────────────────────────────
 *   module_tariffs/logistics            ← ko'rsatkich: { activeVersion }
 *   module_tariffs/logistics_v{N}       ← versiya: { status: draft|active|retired, ... }
 *
 * Har buyurtma o'z `tariffVersion` ini saqlaydi (PriceSnapshot, D-8) —
 * tarif o'zgarsa eski buyurtma narxi o'zgarmaydi.
 *
 * ── RAQAMLAR ────────────────────────────────────────────────────────────
 * Tarif QIYMATLARI (zona narxlari, ulushlar) bu faylda YO'Q — ular ega
 * qarori va Firestore hujjatida turadi (1-band: taxmin qilma). Bu yerda
 * faqat HISOB QOIDASI. `BTS_DOMESTIC_DIVISOR = 6000` — BTS benchmark
 * (BTS_CONFIRMED), AVA qiymati tarif hujjatidagi `volumetricDivisor`.
 *
 * ── PUL ─────────────────────────────────────────────────────────────────
 * Faqat BUTUN SO'M, faqat butun son arifmetikasi (8-band). Vazn — GRAMM
 * (butun), o'lcham — SM (butun). Float yo'q.
 *
 * ── IKKI QATLAM (14-band) ───────────────────────────────────────────────
 * TASHQI: `customerPrice` — mijoz ko'radi.
 * ICHKI:  `internal` — platforma ulushi va LEG bo'yicha ijrochi haqi.
 *         Mijozga ko'rsatilmaydi, proyeksiya uni kesadi.
 */

const ZONES = ['ZONE_0', 'ZONE_1', 'ZONE_2', 'ZONE_3', 'ZONE_4', 'ZONE_5'];

const COLLECTION = 'module_tariffs';
const MODULE = 'logistics';
const POINTER_DOC_ID = 'logistics';

const STATUS = { DRAFT: 'draft', ACTIVE: 'active', RETIRED: 'retired' };

/** BTS «Umumiy shartlar» 1-ilova, 20-bet — BTS_CONFIRMED. AVA qiymati tarifda. */
const BTS_DOMESTIC_DIVISOR = 6000;

/** LEG turlari — ichki ulush kaliti. */
const LEG_KINDS = ['direct', 'first_mile', 'line_haul', 'last_mile'];

function versionDocId(version) {
  return `${MODULE}_v${Number(version)}`;
}

function isPosInt(n) {
  return typeof n === 'number' && Number.isInteger(n) && n > 0;
}
function isNonNegInt(n) {
  return typeof n === 'number' && Number.isInteger(n) && n >= 0;
}
function isBps(n) {
  return isNonNegInt(n) && n <= 10000;
}

/** ceil(a / b) — butun sonlar. */
function ceilDiv(a, b) {
  return Math.floor((a + b - 1) / b);
}

function typedError(code, message, reason) {
  const e = new Error(message);
  e.code = code;
  e.details = { reason };
  return e;
}

// ═══════════════════════════════════════════════════════════════════════
// VALIDATSIYA
// ═══════════════════════════════════════════════════════════════════════

/**
 * Tarif hujjatini tekshiradi.
 *
 * `forActivation: false` (standart) — qoralama: narxlar TO'LIQ bo'lmasa
 * ham bo'ladi (ega hali to'ldirmagan). `forActivation: true` — faol
 * qilishdan oldin HAMMASI to'liq va izchil bo'lishi SHART.
 *
 * @returns {string[]} xatolar (bo'sh — to'g'ri)
 */
function validateTariff(t, { forActivation = false } = {}) {
  const errors = [];
  if (!t || typeof t !== 'object') return ['tarif hujjati bo\'sh'];

  if (t.module !== MODULE) errors.push(`module «${t.module}» emas, «${MODULE}» bo'lishi kerak`);
  if (!isPosInt(t.version)) errors.push('version musbat butun son bo\'lishi kerak');
  if (!Object.values(STATUS).includes(t.status)) errors.push(`status noma'lum: «${t.status}»`);
  if (t.currency !== 'UZS') errors.push('currency faqat UZS');
  if (!isPosInt(t.volumetricDivisor)) errors.push('volumetricDivisor musbat butun son bo\'lishi kerak');

  if (!Array.isArray(t.zones) || t.zones.length !== ZONES.length
    || t.zones.some((z, i) => z !== ZONES[i])) {
    errors.push(`zones aynan ${ZONES.join(', ')} bo'lishi kerak (6 zona, D-2)`);
  }

  const matrix = t.matrix || {};
  const regions = matrix.regions;
  if (!regions || typeof regions !== 'object' || Object.keys(regions).length === 0) {
    errors.push('matrix.regions bo\'sh — kamida bitta origin→destination juftligi kerak');
  } else {
    for (const [o, row] of Object.entries(regions)) {
      if (!row || typeof row !== 'object') { errors.push(`matrix.regions.${o} obyekt emas`); continue; }
      for (const [d, z] of Object.entries(row)) {
        if (!ZONES.includes(z)) errors.push(`matrix.regions.${o}.${d}: noma'lum zona «${z}»`);
      }
    }
  }
  if (matrix.districts && typeof matrix.districts === 'object') {
    for (const [o, row] of Object.entries(matrix.districts)) {
      if (!row || typeof row !== 'object') { errors.push(`matrix.districts.${o} obyekt emas`); continue; }
      for (const [d, z] of Object.entries(row)) {
        if (!ZONES.includes(z)) errors.push(`matrix.districts.${o}.${d}: noma'lum zona «${z}»`);
      }
    }
  }

  const brackets = t.weightBrackets;
  if (!Array.isArray(brackets) || brackets.length === 0) {
    errors.push('weightBrackets bo\'sh');
  } else {
    for (let i = 0; i < brackets.length; i += 1) {
      if (!isPosInt(brackets[i])) errors.push(`weightBrackets[${i}] musbat butun gramm bo'lishi kerak`);
      else if (i > 0 && brackets[i] <= brackets[i - 1]) errors.push(`weightBrackets[${i}] oldingisidan katta bo'lishi kerak`);
    }
  }

  const dv = t.declaredValue || {};
  if (dv.feeBps != null && !isBps(dv.feeBps)) errors.push('declaredValue.feeBps 0..10000');
  if (dv.maxValue != null && !isPosInt(dv.maxValue)) errors.push('declaredValue.maxValue musbat butun so\'m');
  // Audit L15: haq `ceil(v × bps / 10000)`; `maxValue` yo'q bo'lsa v cheksiz va
  // v × bps xavfsiz butun sondan oshib, narx jimgina buzilardi. Faol qilishda
  // haq sozlangan bo'lsa (feeBps > 0) chegara SHART va ko'paytma sig'ishi kerak.
  if (forActivation && isBps(dv.feeBps) && dv.feeBps > 0) {
    if (!isPosInt(dv.maxValue)) {
      errors.push('faol qilish uchun declaredValue.maxValue kerak (e\'lon qiymati haqi sozlangan — musbat butun so\'m)');
    } else if (!Number.isSafeInteger(dv.maxValue * dv.feeBps)) {
      errors.push('declaredValue.maxValue × feeBps xavfsiz butun sondan oshadi — maxValue kamaytirilsin');
    }
  }

  const lim = t.limits || {};
  for (const k of ['maxWeightG', 'maxDimCm', 'maxSumDimCm']) {
    if (lim[k] != null && !isPosInt(lim[k])) errors.push(`limits.${k} musbat butun son bo'lishi kerak`);
  }

  // Qoralamada `null` — «hali to'ldirilmagan» (seed JSON shunday). Faol
  // qilishda esa pastda SHART qilib so'raladi.
  const internal = t.internal || {};
  if (internal.platformMarginBps != null && !isBps(internal.platformMarginBps)) {
    errors.push('internal.platformMarginBps 0..10000');
  }
  const share = internal.legShareBps;
  if (share != null) {
    const keys = ['first_mile', 'line_haul', 'last_mile'];
    let sum = 0;
    for (const k of keys) {
      if (!isBps(share[k])) errors.push(`internal.legShareBps.${k} 0..10000 bo'lishi kerak`);
      else sum += share[k];
    }
    if (sum !== 10000) errors.push(`internal.legShareBps yig'indisi 10000 bo'lishi kerak, hozir ${sum}`);
  }

  // ── Narxlar: qoralamada to'liqsiz bo'lishi mumkin, faol qilishda SHART.
  const prices = t.prices || {};
  const usedZones = new Set();
  for (const row of Object.values(regions || {})) {
    if (row && typeof row === 'object') for (const z of Object.values(row)) usedZones.add(z);
  }
  for (const row of Object.values(matrix.districts || {})) {
    if (row && typeof row === 'object') for (const z of Object.values(row)) usedZones.add(z);
  }
  for (const z of Object.keys(prices)) {
    if (!ZONES.includes(z)) { errors.push(`prices.${z}: noma'lum zona`); continue; }
    const p = prices[z] || {};
    if (!Array.isArray(p.brackets) || (Array.isArray(brackets) && p.brackets.length !== brackets.length)) {
      errors.push(`prices.${z}.brackets uzunligi weightBrackets bilan bir xil bo'lishi kerak`);
    } else if (p.brackets.some((v) => !isPosInt(v))) {
      errors.push(`prices.${z}.brackets faqat musbat butun so'm`);
    }
    // `null` — qoralamada «hali berilmagan» (ega 2026-10-07: 20 kg dan
    // og'ir narx keyin). 0 — ataylab «qo'shimcha haq yo'q» qarori.
    if (p.extraPerKg != null && !isNonNegInt(p.extraPerKg)) errors.push(`prices.${z}.extraPerKg butun so'm (>=0) bo'lishi kerak`);
  }
  if (forActivation) {
    // Oxirgi pog'onadan og'ir posilka qabul qilinadimi? (chegara yo'q yoki
    // chegara oxirgi pog'onadan katta) — unda extraPerKg SHART, aks holda
    // narx noto'g'ri (jimgina 0) chiqardi.
    const lastBracket = Array.isArray(brackets) && brackets.length ? brackets[brackets.length - 1] : 0;
    const maxW = (t.limits || {}).maxWeightG;
    const needsExtra = !maxW || maxW > lastBracket;
    for (const z of usedZones) {
      if (!prices[z]) errors.push(`faol qilish uchun prices.${z} to'ldirilishi SHART (matritsada ishlatilgan)`);
      else if (needsExtra && !isNonNegInt(prices[z].extraPerKg)) {
        errors.push(`faol qilish uchun prices.${z}.extraPerKg kerak (oxirgi pog'onadan og'ir posilka qabul qilinadi)`);
      }
    }
    if (usedZones.size === 0) errors.push('faol qilish uchun matritsa bo\'sh bo\'lmasligi kerak');
    if (!isPosInt(t.volumetricDivisor)) errors.push('faol qilish uchun volumetricDivisor kerak');
    if (share == null) errors.push('faol qilish uchun internal.legShareBps kerak');
    if (!isBps(internal.platformMarginBps)) errors.push('faol qilish uchun internal.platformMarginBps kerak');
  }

  return errors;
}

// ═══════════════════════════════════════════════════════════════════════
// ZONA
// ═══════════════════════════════════════════════════════════════════════

/**
 * Zona — matritsadan. Tuman juftligi viloyat juftligidan USTUN.
 * `matrix.symmetric !== false` bo'lsa teskari yo'nalish ham qaraladi.
 *
 * @returns {string|null}
 */
function resolveZone(t, origin, dest) {
  const m = (t && t.matrix) || {};
  const o = origin || {};
  const d = dest || {};
  const sym = m.symmetric !== false;
  const lookup = (table, a, b) => {
    if (!table || !a || !b) return null;
    const direct = table[a] && table[a][b];
    if (ZONES.includes(direct)) return direct;
    if (sym) {
      const rev = table[b] && table[b][a];
      if (ZONES.includes(rev)) return rev;
    }
    return null;
  };
  return lookup(m.districts, o.districtId, d.districtId)
    || lookup(m.regions, o.regionId, d.regionId)
    || null;
}

// ═══════════════════════════════════════════════════════════════════════
// VAZN (12-band)
// ═══════════════════════════════════════════════════════════════════════

/** L×W×H / divisor — kg; grammga: ×1000. Yuqoriga butun grammgacha. */
function volumetricWeightG(lengthCm, widthCm, heightCm, divisor) {
  if (![lengthCm, widthCm, heightCm].every(isPosInt) || !isPosInt(divisor)) return 0;
  return ceilDiv(lengthCm * widthCm * heightCm * 1000, divisor);
}

/** chargeable = max(actual, volumetric) (BTS_CONFIRMED qoida, AVA ham shu). */
function chargeableWeightG(actualG, volumetricG) {
  return Math.max(Number(actualG) || 0, Number(volumetricG) || 0);
}

/** Vazn pog'onasi indeksi; hammasidan og'ir bo'lsa -1. */
function bracketIndex(t, chargeableG) {
  const b = (t && t.weightBrackets) || [];
  for (let i = 0; i < b.length; i += 1) if (chargeableG <= b[i]) return i;
  return -1;
}

/** Zona + vazn → bazaviy narx (butun so'm). */
function basePriceFor(t, zone, chargeableG) {
  const p = ((t && t.prices) || {})[zone];
  if (!p) throw typedError('failed-precondition', `«${zone}» uchun narx yo'q`, 'tariff_zone_price_missing');
  const idx = bracketIndex(t, chargeableG);
  if (idx >= 0) return p.brackets[idx];
  if (!isNonNegInt(p.extraPerKg)) {
    throw typedError('failed-precondition', `«${zone}» uchun oxirgi pog'onadan og'ir narx yo'q`, 'tariff_extra_price_missing');
  }
  const lastMax = t.weightBrackets[t.weightBrackets.length - 1];
  const extraKg = ceilDiv(chargeableG - lastMax, 1000);
  return p.brackets[p.brackets.length - 1] + extraKg * p.extraPerKg;
}

/** E'lon qilingan qiymat haqi — ceil(value × bps / 10000). */
function declaredValueFee(t, declaredValue) {
  const v = Number(declaredValue) || 0;
  if (v <= 0) return 0;
  const bps = Number(((t && t.declaredValue) || {}).feeBps) || 0;
  if (bps <= 0) return 0;
  // Audit L15: v × bps xavfsiz butun sondan oshsa ceilDiv jim noto'g'ri son
  // berardi. `maxValue` bo'lmagan eski hujjatda ham shu yerda to'xtaydi.
  if (!Number.isSafeInteger(v * bps)) {
    throw typedError('failed-precondition', 'E\'lon qilingan qiymat chegaradan oshdi', 'over_declared_value');
  }
  const x = v * bps;
  // `ceilDiv` (a + b - 1) chegarada o'zi toshib ketardi — shuning uchun qoldiq bilan.
  return Math.floor(x / 10000) + (x % 10000 === 0 ? 0 : 1);
}

// ═══════════════════════════════════════════════════════════════════════
// KOTIROVKA — PriceSnapshot (D-8)
// ═══════════════════════════════════════════════════════════════════════

/**
 * Bitta jo'natma (SHIPMENT) uchun narx.
 *
 * @param {object} t tarif (active)
 * @param {{actualWeightG:number,lengthCm:number,widthCm:number,heightCm:number,declaredValue?:number}} parcel
 * @param {{regionId:string,districtId?:string}} origin
 * @param {{regionId:string,districtId?:string}} dest
 * @returns {object} PriceSnapshot — SAQLANADIGAN shakl
 */
function quoteParcel(t, parcel, origin, dest) {
  if (!t || t.status !== STATUS.ACTIVE) {
    throw typedError('failed-precondition', 'Logistika tarifi hali faol emas', 'tariff_not_active');
  }
  const p = parcel || {};
  const actual = p.actualWeightG;
  const dims = [p.lengthCm, p.widthCm, p.heightCm];
  if (!isPosInt(actual)) throw typedError('invalid-argument', 'actualWeightG musbat butun gramm', 'bad_weight');
  if (!dims.every(isPosInt)) throw typedError('invalid-argument', 'o\'lchamlar musbat butun sm', 'bad_dimensions');
  const declared = p.declaredValue === undefined || p.declaredValue === null ? 0 : p.declaredValue;
  if (!isNonNegInt(declared)) throw typedError('invalid-argument', 'declaredValue butun so\'m', 'bad_declared_value');

  const lim = t.limits || {};
  if (lim.maxWeightG && actual > lim.maxWeightG) throw typedError('failed-precondition', 'Vazn chegaradan oshdi', 'over_weight');
  if (lim.maxDimCm && dims.some((x) => x > lim.maxDimCm)) throw typedError('failed-precondition', 'O\'lcham chegaradan oshdi', 'over_dimension');
  if (lim.maxSumDimCm && dims[0] + dims[1] + dims[2] > lim.maxSumDimCm) throw typedError('failed-precondition', 'O\'lchamlar yig\'indisi chegaradan oshdi', 'over_dimension_sum');
  const dvMax = (t.declaredValue || {}).maxValue;
  if (dvMax && declared > dvMax) throw typedError('failed-precondition', 'E\'lon qilingan qiymat chegaradan oshdi', 'over_declared_value');

  const zone = resolveZone(t, origin, dest);
  if (!zone) throw typedError('failed-precondition', 'Bu yo\'nalish uchun tarif zonasi yo\'q', 'zone_not_found');

  const volumetric = volumetricWeightG(dims[0], dims[1], dims[2], t.volumetricDivisor);
  const chargeable = chargeableWeightG(actual, volumetric);
  const base = basePriceFor(t, zone, chargeable);
  const dvFee = declaredValueFee(t, declared);
  const customerPrice = base + dvFee;

  return {
    zone,
    tariffVersion: t.version,
    volumetricDivisor: t.volumetricDivisor,
    actualWeightG: actual,
    lengthCm: dims[0],
    widthCm: dims[1],
    heightCm: dims[2],
    volumetricWeightG: volumetric,
    chargeableWeightG: chargeable,
    bracketIndex: bracketIndex(t, chargeable),
    basePrice: base,
    declaredValue: declared,
    declaredValueFee: dvFee,
    extras: dvFee > 0 ? [{ kind: 'declared_value', amount: dvFee }] : [],
    customerPrice,
    currency: 'UZS',
  };
}

// ═══════════════════════════════════════════════════════════════════════
// ICHKI QATLAM (14-band) — LEG bo'yicha ijrochi haqi
// ═══════════════════════════════════════════════════════════════════════

/** LEG soni → turlar. 1: direct; 2: first+last; 3+: first, line…, last. */
function legKindsFor(count) {
  const n = Number(count) || 0;
  if (n <= 0) return [];
  if (n === 1) return ['direct'];
  if (n === 2) return ['first_mile', 'last_mile'];
  return ['first_mile', ...Array(n - 2).fill('line_haul'), 'last_mile'];
}

/**
 * Mijoz narxini platforma ulushi va LEG haqlariga bo'ladi — BUTUN so'm,
 * qoldiq OXIRGI LEG'ga. Har haq ATRIBUTSIYALANGAN (qaysi LEG, 7.5).
 *
 * @returns {{platformShare:number, providerPool:number, legPayouts:Array<{index:number,kind:string,amount:number}>}}
 */
function splitInternal(t, customerPrice, legKinds) {
  const price = Number(customerPrice) || 0;
  const internal = (t && t.internal) || {};
  const marginBps = Number(internal.platformMarginBps) || 0;
  const platformShare = ceilDiv(price * marginBps, 10000);
  const pool = Math.max(0, price - platformShare);
  const kinds = Array.isArray(legKinds) ? legKinds : [];
  if (kinds.length === 0) return { platformShare, providerPool: pool, legPayouts: [] };

  if (kinds.length === 1) {
    return { platformShare, providerPool: pool, legPayouts: [{ index: 0, kind: kinds[0], amount: pool }] };
  }
  const share = internal.legShareBps || {};
  const weights = kinds.map((k) => Number(share[k]) || 0);
  const total = weights.reduce((s, w) => s + w, 0);
  const out = [];
  let given = 0;
  for (let i = 0; i < kinds.length; i += 1) {
    let amount;
    if (i === kinds.length - 1) amount = pool - given;
    else amount = total > 0 ? Math.floor((pool * weights[i]) / total) : 0;
    given += amount;
    out.push({ index: i, kind: kinds[i], amount });
  }
  return { platformShare, providerPool: pool, legPayouts: out };
}

// ═══════════════════════════════════════════════════════════════════════
// FIRESTORE — faol tarif (60 s kesh)
// ═══════════════════════════════════════════════════════════════════════

const CACHE_TTL_MS = 60 * 1000;
let cache = { at: 0, value: null };

/** Faol tarif; yo'q bo'lsa `null`. */
async function getActiveTariff(db, { skipCache = false } = {}) {
  const now = Date.now();
  if (!skipCache && cache.value && now - cache.at < CACHE_TTL_MS) return cache.value;
  const ptr = await db.collection(COLLECTION).doc(POINTER_DOC_ID).get();
  const v = ptr.exists ? Number((ptr.data() || {}).activeVersion) : 0;
  if (!isPosInt(v)) { cache = { at: now, value: null }; return null; }
  const snap = await db.collection(COLLECTION).doc(versionDocId(v)).get();
  const t = snap.exists ? (snap.data() || {}) : null;
  const value = t && t.status === STATUS.ACTIVE ? t : null;
  cache = { at: now, value };
  return value;
}

function clearCache() {
  cache = { at: 0, value: null };
}

module.exports = {
  ZONES,
  COLLECTION,
  MODULE,
  POINTER_DOC_ID,
  STATUS,
  BTS_DOMESTIC_DIVISOR,
  LEG_KINDS,
  versionDocId,
  ceilDiv,
  validateTariff,
  resolveZone,
  volumetricWeightG,
  chargeableWeightG,
  bracketIndex,
  basePriceFor,
  declaredValueFee,
  quoteParcel,
  legKindsFor,
  splitInternal,
  getActiveTariff,
  clearCache,
};
