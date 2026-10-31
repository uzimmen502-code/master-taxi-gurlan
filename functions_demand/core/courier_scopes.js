'use strict';

/**
 * KURYER TOIFALARI — LEG uchun (ega qarorlari 2026-10-31).
 *
 * Asosiy manba — default codebase `functions/courier_scopes.js` (callable'lar, `courier_auth` tekshiruvi).
 * `functions_demand` alohida deploy bo'ladi va u modulni `require` qila olmaydi, shuning uchun bu yerda
 * FAQAT o'qish mantig'i takrorlanadi — o'sha fayldagi `requestedScopes` / `isScopeActive` bilan BIR XIL
 * bo'lishi shart (test: test/courier_scopes_leg.test.js tekshiradi; o'zgartirsangiz ikkalasini birga).
 *
 *   `courier.scopes` — kuryer tanlagan toifalar (yo'q = ['district'], eski hujjatlar);
 *   `review.courierScopes.{region|republic}.status === 'approved'` — admin (yoki Avto) tasdig'i.
 *
 * LEG toifasi yo'nalishdan (`location` → `destination`):
 *   bir tuman ichida (yoki manzil tumani noma'lum emas va bir xil) → district;
 *   bir viloyat, boshqa (yoki noma'lum) tuman → region;
 *   boshqa viloyat → republic.
 * Noma'lum holatda QATTIQROQ toifa olinadi (ruxsatsiz ish berilmasin).
 */

const SCOPES = Object.freeze(['district', 'region', 'republic']);

function requestedScopes(capDoc) {
  const raw = capDoc && capDoc.courier && capDoc.courier.scopes;
  if (!Array.isArray(raw)) return ['district'];
  return SCOPES.filter((s) => raw.includes(s));
}

function reviewStatus(capDoc, scope) {
  const r = capDoc && capDoc.review && capDoc.review.courierScopes && capDoc.review.courierScopes[scope];
  return r && typeof r.status === 'string' ? r.status : '';
}

function isScopeActive(capDoc, scope) {
  if (!SCOPES.includes(scope)) return false;
  if (!requestedScopes(capDoc).includes(scope)) return false;
  if (scope === 'district') return true;
  return reviewStatus(capDoc, scope) === 'approved';
}

/** LEG yo'nalishi → toifa. */
function legScope(from, to) {
  const a = from || {};
  const b = to || {};
  if (!a.regionId || !b.regionId || a.regionId !== b.regionId) return 'republic';
  if (a.districtId && b.districtId && a.districtId === b.districtId) return 'district';
  return 'region';
}

module.exports = { SCOPES, requestedScopes, reviewStatus, isScopeActive, legScope };
