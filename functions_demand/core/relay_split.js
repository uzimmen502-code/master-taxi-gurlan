'use strict';

/**
 * AVA LOGISTICS (RELAY) — AVTOMATIK LEG BO'LINISHI (ega qarori 2026-11-07, CONFIRMED).
 *
 * Sof funksiya: Firestore YO'Q. Nuqtalar ketma-ketligi:
 *
 *   O → C(viloyat O) → [C(poytaxt), agar viaCapital] → C(viloyat D) → D
 *
 * C — viloyatning transfer nuqtasi = RASMIY ma'muriy markaz tumani (ega).
 * Ketma-ket bir xil tuman (regionId + districtId) nuqtalari bitta bo'ladi:
 *   - bir tuman            → 1 LEG (to'g'ridan-to'g'ri);
 *   - bir viloyat          → 2 LEG (O→C→D); O yoki D markazning o'zi bo'lsa 1;
 *   - turli viloyat        → 3 LEG (O→C1→C2→D); markazlar bilan ustma-ust tushsa kamroq;
 *   - viaCapital: true     → poytaxt markazi qo'shiladi (C1→Cp→C2).
 *
 * Kerakli markaz konfigda YO'Q bo'lsa — bitta to'g'ridan-to'g'ri LEG (mavjud
 * xatti-harakat) va `fallback.errorCode = TRANSFER_POINT_MISSING` (chaqiruvchi
 * logga yozadi). Markaz TAXMIN QILINMAYDI (CLAUDE.md 1-band).
 *
 * Standart jadval — `core/seed/transfer_points_default.json`; konfig
 * (`module_config/logistics_all.logistics.transferPoints`) ustiga yozadi
 * (`core/config.js` DEFAULTS orqali, har viloyat alohida).
 */

const geoHash = require('../geo/geo_hash');

const ERROR_TRANSFER_POINT_MISSING = 'TRANSFER_POINT_MISSING';
const DEFAULT_CAPITAL_REGION_ID = 'toshkent_shahri';
const GEO_ID_RE = /^[a-z0-9][a-z0-9_-]{0,63}$/;

function finiteOrNull(v) {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

/** Ikki nuqta bitta tumanmi (bo'sh tuman — faqat aynan bir xil bo'sh bilan teng). */
function samePlace(a, b) {
  return String(a.regionId || '') === String(b.regionId || '')
    && String(a.districtId || '') === String(b.districtId || '');
}

/**
 * Viloyat markazi nuqtasi (validatePoint natijasi bilan bir xil shakl) yoki null.
 * Konfig yozuvi: `{ districtId, addressText?, lat?, lng? }`.
 */
function centrePointFor(regionId, transferPoints) {
  const regions = ((transferPoints || {}).regions) || {};
  const rid = String(regionId || '');
  if (!GEO_ID_RE.test(rid)) return null;
  const tp = regions[rid];
  if (!tp || typeof tp !== 'object') return null;
  const districtId = String(tp.districtId || '').trim();
  if (!GEO_ID_RE.test(districtId)) return null;
  let lat = finiteOrNull(tp.lat);
  let lng = finiteOrNull(tp.lng);
  if (lat === null || lng === null || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    lat = null;
    lng = null;
  }
  return {
    regionId: rid,
    districtId,
    lat,
    lng,
    geohash: lat !== null ? geoHash.encode(lat, lng, 7) : '',
    addressText: String(tp.addressText || '').slice(0, 300),
  };
}

/**
 * @param {{regionId:string,districtId?:string}} origin
 * @param {{regionId:string,districtId?:string}} destination
 * @param {{regions?:object, viaCapital?:boolean, capitalRegionId?:string}} transferPoints
 * @returns {{
 *   points: object[],
 *   segments: Array<{from:object,to:object}>,
 *   legCount: number,
 *   reason: 'same_district'|'split'|'fallback',
 *   fallback: null|{errorCode:string, missingRegionIds:string[]},
 * }}
 */
function planRelayPoints(origin, destination, transferPoints) {
  const o = origin || {};
  const d = destination || {};
  const tp = transferPoints || {};
  const direct = (reason, fallback) => ({
    points: [o, d],
    segments: [{ from: o, to: d }],
    legCount: 1,
    reason,
    fallback: fallback || null,
  });

  if (o.regionId === d.regionId && o.districtId && o.districtId === d.districtId) {
    return direct('same_district');
  }

  const sameRegion = o.regionId === d.regionId;
  const capital = String(tp.capitalRegionId || DEFAULT_CAPITAL_REGION_ID);
  const regionChain = sameRegion
    ? [o.regionId]
    : [o.regionId, ...(tp.viaCapital === true ? [capital] : []), d.regionId];

  const centres = regionChain.map((r) => centrePointFor(r, tp));
  const missing = [...new Set(regionChain.filter((r, i) => !centres[i]).map(String))];
  if (missing.length) {
    return direct('fallback', { errorCode: ERROR_TRANSFER_POINT_MISSING, missingRegionIds: missing });
  }

  const seq = [];
  for (const p of [o, ...centres, d]) {
    if (seq.length && samePlace(seq[seq.length - 1], p)) continue;
    seq.push(p);
  }
  // O va D ham markazga tushib, bitta nuqta qolsa — to'g'ridan-to'g'ri.
  if (seq.length < 2) return direct('same_district');
  // Oxirgi nuqta D bo'lishi SHART (D markaz bilan ustma-ust tushsa, D ning
  // o'zi qoladi — manzil matni va koordinatasi mijozniki).
  if (seq[seq.length - 1] !== d) seq[seq.length - 1] = d;
  if (seq[0] !== o) seq[0] = o;

  const segments = [];
  for (let i = 0; i < seq.length - 1; i += 1) segments.push({ from: seq[i], to: seq[i + 1] });
  return { points: seq, segments, legCount: segments.length, reason: 'split', fallback: null };
}

module.exports = {
  ERROR_TRANSFER_POINT_MISSING,
  DEFAULT_CAPITAL_REGION_ID,
  samePlace,
  centrePointFor,
  planRelayPoints,
};
