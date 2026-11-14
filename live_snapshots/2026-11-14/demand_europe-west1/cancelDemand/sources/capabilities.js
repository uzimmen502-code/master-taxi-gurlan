'use strict';

/**
 * NOMZOD MANBASI 1 — `provider_capabilities`.
 *
 * Taklifchining O'ZI belgilagan yo'nalishlar: «men santexnikman»,
 * «Xorazm bo'ylab ishlayman», «posilka olaman».
 *
 * ── HUJJAT SHAKLI (D-12…D-16, T-1a) ────────────────────────────────────
 *   provider_capabilities/{accountId}
 *     identity: { accountId, primaryUid }   ← faqat server
 *     courier:  { active, regionIds, ... }  ← klient
 *     status:   { courier: 'approved' }     ← faqat server
 *
 * KALIT — barqaror `accountId` (telefon emas). Matching, presence va
 * `demand_matches` esa kanon TELEFON bilan ishlaydi, shuning uchun
 * nomzodga `providerId = identity.primaryUid` beriladi. Bu maydonni
 * FAQAT SERVER yozadi (`identity` — SERVER_KEYS ichida), ya'ni unga
 * ishonish mumkin (18-qoida). `identity`siz hujjat — noto'g'ri shakl,
 * o'tkazib yuboriladi.
 *
 * ── NEGA STATUS SO'ROVDA EMAS, XOTIRADA ────────────────────────────────
 * `in` va `array-contains-any` bitta so'rovda birga bo'lmaydi. So'rov
 * `active` + `regionIds` bo'yicha, `status` esa `isEligible` da.
 */

const { SERVICES, isEligible, statusOf, identityOf } = require('../core/capabilities');
const { toCanonicalId } = require('../core/ids');
const { fetchByPhone } = require('../api/capabilities');

const COLLECTION = 'provider_capabilities';

async function fetchCandidates(db, demand, config) {
  const service = String((demand && demand.module) || '');
  if (!SERVICES.includes(service)) return [];

  const regions = regionKeysFor(demand);
  if (regions.length === 0) return [];

  const snap = await db.collection(COLLECTION)
    .where(`${service}.active`, '==', true)
    .where(`${service}.regionIds`, 'array-contains-any', regions.slice(0, 10))
    .limit(config.maxCandidates || 500)
    .get();

  const out = [];
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    // HUQUQ + XOHISH — ikkalasi ham (T-3).
    if (!isEligible(d, service)) continue;

    // Kimlik — server yozgan `identity.primaryUid` (kanon telefon).
    const providerId = toCanonicalId(identityOf(d).primaryUid);
    if (!providerId) continue;

    const svc = d[service] || {};
    if (demand.categoryId) {
      const cats = Array.isArray(svc.categoryIds) ? svc.categoryIds : [];
      const groups = Array.isArray(svc.categoryGroups) ? svc.categoryGroups : [];
      const catMatch = cats.includes(demand.categoryId);
      const groupMatch = demand.categoryGroup && groups.includes(demand.categoryGroup);
      if (!catMatch && !groupMatch && cats.length > 0) continue;
    }

    out.push({
      providerId,
      accountId: doc.id,
      source: 'capabilities',
      categoryIds: svc.categoryIds || [],
      categoryGroups: svc.categoryGroups || [],
      regionIds: svc.regionIds || [],
      districtIds: svc.districtIds || [],
      vehicle: svc.vehicle || null,
      wholesale: svc.wholesale === true,
      minOrderQty: Number(svc.minOrderQty) || 0,
      acceptsParcels: svc.acceptsParcels === true,
      pushOptOut: svc.pushOptOut === true,
      digestOnly: svc.digestOnly === true,
      capabilityStatus: statusOf(d, service),
      /** ROZILIK BOR — odam capability'ni o'zi to'ldirgan, push oladi. */
      consentGiven: true,
      raw: svc,
    });
  }
  return out;
}

/** Talab uchun hudud kalitlari — tumandan viloyatgacha. */
function regionKeysFor(demand) {
  const loc = demand.location || {};
  const keys = [];
  if (loc.districtId) keys.push(loc.districtId);
  if (loc.regionId) keys.push(loc.regionId);
  const dest = demand.destination || {};
  if (dest.districtId && !keys.includes(dest.districtId)) keys.push(dest.districtId);
  if (dest.regionId && !keys.includes(dest.regionId)) keys.push(dest.regionId);
  return keys;
}

/**
 * Bitta taklifchining capability hujjati — TELEFON bo'yicha
 * (`users` → accountId → hujjat). Teskari matching va admin uchun.
 */
async function fetchForProvider(db, providerId) {
  const id = toCanonicalId(providerId);
  if (!id) return null;
  return fetchByPhone(db, id);
}

module.exports = {
  COLLECTION, fetchCandidates, fetchForProvider, regionKeysFor,
};
