/**
 * Kafe-restoran — YETKAZISH TARIFI va AVA ULUSHI (sof funksiyalar).
 *
 * Ega qarorlari (2026-10-08, docs/kafe_restoran_taklifi_uz.md §10):
 *   D-REST-2  AVA ulushi = taom summasining 2 % (yetkazish narxidan EMAS);
 *   D-REST-4  AVA kuryeri narxi masofaga qarab, ALOHIDA tarif: 1 km gacha
 *             bazaviy narx + har keyingi km, 500 ga yaxlitlash, tunda ×1.5;
 *             admin mintaqa bo'yicha o'zgartiradi, har buyurtmada versiya;
 *             o'z kuryerli restoran o'z narxini qo'yadi.
 *
 * Namuna — `local_taxi.js` (haversine, tun, mintaqa kaliti qayta ishlatiladi,
 * 4-qoida). Masofa koeffitsienti (uzoq yo'lda arzonlashuv) YO'Q — yetkazish
 * qisqa. Pul — butun so'm, koeffitsientlar permille, BigInt (8-qoida).
 *
 * Tarif hujjati `settings/restaurant_delivery`:
 *   { base, perKm, nightCoef, nightStart, nightEnd, roadFactor, maxKm,
 *     version, regions: { xorazm: { base, perKm, ... }, ... } }
 * Hujjat yoki `base`/`perKm` bo'lmasa — `null` (hardcode default YO'Q,
 * `TARIFF_NOT_CONFIGURED`), `local_taxi.resolvePrices` bilan bir xil yondashuv.
 */
'use strict';

const localTaxi = require('./local_taxi');

/** 2 % = 200 bps. Butun son arifmetikasi uchun. */
const AVA_FEE_RATE_BPS = 200;
const AVA_FEE_VERSION = 1;
const ROUND_TO = 500;
const DEFAULT_NIGHT_PERMILLE = 1500;
const DEFAULT_NIGHT_START_H = 23;
const DEFAULT_NIGHT_END_H = 6;
const DEFAULT_ROAD_FACTOR_PERMILLE = 1300;
const DEFAULT_MAX_KM = 15;
/** Bazaviy narx qamrab oladigan masofa (D-REST-4: «1 km gacha»). */
const BASE_METERS = 1000;

function intOr(v, def, min, max) {
  if (v == null || v === '') return def; // Number(null) === 0 — tuzoq
  const n = Number(v);
  return Number.isInteger(n) && n >= min && n <= max ? n : def;
}

function toPermille(coef) {
  const n = Number(coef);
  if (!Number.isFinite(n) || n <= 0) return 1000;
  return Math.round(n * 1000);
}

/** a / b, yarim yuqoriga yaxlitlash (musbat BigInt). */
function divRoundHalfUp(a, b) {
  return (a * 2n + b) / (2n * b);
}

/** AVA ulushi (bps) va tungi koeffitsient chegaralari — admin callable bilan BITTA manba. */
const AVA_FEE_BPS_MIN = 0;
const AVA_FEE_BPS_MAX = 10000;
/** Tungi koeffitsient (×): 1 = tungi qo'shimcha yo'q; 3 — mavjud admin tarif muharriri chegarasi. */
const NIGHT_COEF_MIN = 1;
const NIGHT_COEF_MAX = 3;

/**
 * D9 (ega qarori 2026-10-16): AVA ulushi `settings/restaurant_delivery.avaFeeBps`
 * (butun bps, 0..10000) — tarif hujjati bilan BITTA versiya (`version`), tarixi
 * `restaurant_delivery_tariffs/v{n}`. Maydon yo'q / noto'g'ri → standart
 * `AVA_FEE_RATE_BPS` (200): admin o'zgartirmaguncha hech narsa o'zgarmaydi.
 * Faqat HAQIQIY butun son qabul qilinadi (satr `'300'` — standart).
 * @return {{rateBps:number, source:'default'|'setting', settingsVersion:number}}
 */
function resolveAvaFeeSettings(tariffDoc) {
  const d = tariffDoc && typeof tariffDoc === 'object' ? tariffDoc : {};
  const v = d.avaFeeBps;
  const valid = typeof v === 'number' && Number.isInteger(v) && v >= AVA_FEE_BPS_MIN && v <= AVA_FEE_BPS_MAX;
  return {
    rateBps: valid ? v : AVA_FEE_RATE_BPS,
    source: valid ? 'setting' : 'default',
    settingsVersion: intOr(d.version, 0, 0, 1000000),
  };
}

/**
 * AVA ulushi — SOF, DETERMINISTIK, BUTUN SO'M (D-REST-2, 8-qoida).
 *   amount = ceil(itemsTotal × rateBps / 10000)
 * `settings` — `resolveAvaFeeSettings` natijasi; berilmasa standart 200 bps
 * (eski chaqiruvlar o'zgarmaydi). `ceil`: AVA o'ziga zarar qilmaydi, farq
 * eng ko'pi 1 so'm (taxi T-4 bilan bir xil). Faqat HAQIQIY musbat butun son
 * qabul qilinadi (18-qoida). `version` — hisob-kitob (ledger kalit) versiyasi,
 * O'ZGARMAYDI; sozlama versiyasi `settingsVersion`da (buyurtmaga muhrlanadi).
 */
function computeAvaFee(itemsTotal, settings) {
  const basis = typeof itemsTotal === 'number' ? itemsTotal : Number.NaN;
  if (!Number.isInteger(basis) || basis <= 0) {
    const e = new Error('itemsTotal musbat butun son bo\'lishi kerak');
    e.code = 'invalid-argument';
    throw e;
  }
  const s = settings && typeof settings === 'object' ? settings : null;
  const rateBps = s && Number.isInteger(s.rateBps) && s.rateBps >= AVA_FEE_BPS_MIN && s.rateBps <= AVA_FEE_BPS_MAX
    ? s.rateBps : AVA_FEE_RATE_BPS;
  const product = basis * rateBps;
  const out = {
    rateBps,
    basis,
    amount: Math.floor(product / 10000) + (product % 10000 === 0 ? 0 : 1),
    version: AVA_FEE_VERSION,
  };
  // Muhr FAQAT admin sozlamasi ishlaganda: standart (sozlamasiz) buyurtma
  // hujjati AVVALGIDEK bir xil shaklda qoladi (orqaga moslik, 26-qoida).
  if (s && s.source === 'setting') {
    out.rateSource = 'setting';
    out.settingsVersion = Number.isInteger(s.settingsVersion) ? s.settingsVersion : 0;
  }
  return out;
}

/**
 * `settings/restaurant_delivery` dan mintaqa narxi. Topilmasa null.
 * @return {{regionKey, base, perKm, nightPermille, nightStartH, nightEndH,
 *           roadFactorPermille, maxKm, version, source}|null}
 */
function resolveDeliveryPrices(tariffDoc, regionKey) {
  const data = tariffDoc || {};
  const regions = (data.regions && typeof data.regions === 'object') ? data.regions : {};
  let region = null;
  let source = 'global';
  if (regions[regionKey] && typeof regions[regionKey] === 'object') {
    region = regions[regionKey];
    source = `region:${regionKey}`;
  } else if (regions.default && typeof regions.default === 'object') {
    region = regions.default;
    source = 'region:default';
  }
  const pick = (k) => {
    const v = region && region[k] != null ? region[k] : data[k];
    return v == null ? null : Number(v);
  };
  const base = pick('base');
  const perKm = pick('perKm');
  if (!Number.isInteger(base) || base <= 0 || !Number.isInteger(perKm) || perKm < 0) {
    return null;
  }
  const nightCoef = pick('nightCoef');
  const roadFactor = pick('roadFactor');
  return {
    regionKey,
    base,
    perKm,
    nightPermille: nightCoef == null ? DEFAULT_NIGHT_PERMILLE : toPermille(nightCoef),
    nightStartH: intOr(pick('nightStart'), DEFAULT_NIGHT_START_H, 0, 23),
    nightEndH: intOr(pick('nightEnd'), DEFAULT_NIGHT_END_H, 0, 23),
    roadFactorPermille: roadFactor == null
      ? DEFAULT_ROAD_FACTOR_PERMILLE : toPermille(roadFactor),
    maxKm: intOr(pick('maxKm'), DEFAULT_MAX_KM, 1, 100),
    version: intOr(data.version, 0, 0, 1000000),
    source,
  };
}

/**
 * AVA kuryeri narxi — sof funksiya.
 *   fee = (base + round(extraKm × perKm)) × tun → 500 ga yaxlit
 * `extraKm` — birinchi 1 km dan TASHQARI masofa (bazaga kiradi).
 * @return {{fee, distancePart, nightPermille, extraMeters}}
 */
function computeDeliveryFee({ distanceMeters, prices, night }) {
  const m = Math.max(0, Math.trunc(Number(distanceMeters) || 0));
  const extraMeters = Math.max(0, m - BASE_METERS);
  const distancePart = Number(divRoundHalfUp(BigInt(extraMeters) * BigInt(prices.perKm), 1000n));
  const subtotal = BigInt(prices.base + distancePart);
  const nightPermille = night
    ? (Number.isInteger(prices.nightPermille) ? prices.nightPermille : DEFAULT_NIGHT_PERMILLE)
    : 1000;
  const total = divRoundHalfUp(subtotal * BigInt(nightPermille), 1000n);
  const fee = Number(divRoundHalfUp(total, BigInt(ROUND_TO))) * ROUND_TO;
  return { fee, distancePart, nightPermille, extraMeters };
}

/**
 * Restoranning O'Z kuryeri narxi (D-REST-4, D-REST-5) — restoran yozgan
 * `delivery.ownFee` bo'yicha:
 *   { type: 'fixed',    fixed }                     — qat'iy
 *   { type: 'distance', base, perKm }               — 1 km gacha base + km
 *   + ixtiyoriy `freeAbove` (taom summasi shundan ≥ bo'lsa bepul)
 *   + ixtiyoriy `maxKm` (undan uzoqqa yetkazmaydi → null)
 * Noto'g'ri/yo'q sozlama → 0 (restoran narx qo'ymagan = bepul; u o'z
 * puli, AVA ga ta'sir qilmaydi). Hamma narsa butun so'm.
 */
function computeOwnDeliveryFee(ownFee, { distanceMeters, itemsTotal }) {
  const cfg = ownFee && typeof ownFee === 'object' ? ownFee : {};
  const m = Math.max(0, Math.trunc(Number(distanceMeters) || 0));
  const maxKm = intOr(cfg.maxKm, null, 1, 100);
  if (maxKm != null && m > maxKm * 1000) return null;
  const freeAbove = intOr(cfg.freeAbove, null, 0, 1000000000);
  if (freeAbove != null && Number.isInteger(itemsTotal) && itemsTotal >= freeAbove) return 0;
  if (cfg.type === 'distance') {
    const base = intOr(cfg.base, 0, 0, 1000000000);
    const perKm = intOr(cfg.perKm, 0, 0, 1000000000);
    const extraMeters = Math.max(0, m - BASE_METERS);
    const part = Number(divRoundHalfUp(BigInt(extraMeters) * BigInt(perKm), 1000n));
    return base + part;
  }
  return intOr(cfg.fixed, 0, 0, 1000000000);
}

module.exports = {
  AVA_FEE_RATE_BPS,
  AVA_FEE_VERSION,
  BASE_METERS,
  ROUND_TO,
  DEFAULT_MAX_KM,
  AVA_FEE_BPS_MIN,
  AVA_FEE_BPS_MAX,
  NIGHT_COEF_MIN,
  NIGHT_COEF_MAX,
  resolveAvaFeeSettings,
  // Admin tarif muharriri (`adminSetRestaurantDeliveryPrices`) berilmagan
  // maydonlar uchun shu standartlarni yozadi — hisob bilan bitta manba.
  DEFAULT_NIGHT_COEF: DEFAULT_NIGHT_PERMILLE / 1000,
  DEFAULT_NIGHT_START_H,
  DEFAULT_NIGHT_END_H,
  DEFAULT_ROAD_FACTOR: DEFAULT_ROAD_FACTOR_PERMILLE / 1000,
  computeAvaFee,
  resolveDeliveryPrices,
  computeDeliveryFee,
  computeOwnDeliveryFee,
  isNightAt: localTaxi.isNightAt,
  haversineMeters: localTaxi.haversineMeters,
  resolveRegionKey: localTaxi.resolveRegionKey,
};
