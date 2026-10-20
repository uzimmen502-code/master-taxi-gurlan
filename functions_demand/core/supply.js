'use strict';

/**
 * HUDUD BO'YICHA TAKLIFCHILAR HISOBI (sof funksiya, Firestore'siz).
 *
 * Variant A (ega 2026-10-20): hudud faqat shu yerda ishlay oladigan taklifchi
 * yetarli (N = 5) bo'lganda yoqiladi. Bitta hisob — ikki joyda ishlatiladi:
 *   - `tools/provider_supply_report.js` (read-only hisobot);
 *   - admin «Talab yadrosi» (`api/core_config_admin.js`): tayyorlik ko'rsatish
 *     va yoqishni SERVERDA tekshirish.
 *
 * «Ishlay oladigan» = `core/capabilities.isEligible` (huquq `status` + xohish
 * `active`) — matching/onProviderAvailable ishlatadigan shart bilan bir xil.
 */

const caps = require('./capabilities');

/**
 * @param {object} p
 * @param {Array<object>} p.capDocs `provider_capabilities` hujjatlari
 * @param {string[]} p.regionIds `geo_regions` ID'lari
 * @param {number} p.min tayyorlik chegarasi (butun, >= 1)
 * @param {string} p.service `caps.SERVICES` dan biri
 */
function summarizeSupply({ capDocs, regionIds, min, service }) {
  if (!Number.isInteger(min) || min < 1) {
    throw new Error(`min butun son >= 1 bo'lishi kerak, berilgan: ${min}`);
  }
  if (!caps.SERVICES.includes(service)) {
    throw new Error(`service noto'g'ri: «${service}» (mumkin: ${caps.SERVICES.join(', ')})`);
  }
  const counts = new Map(regionIds.map((r) => [r, 0]));
  const unknown = new Set();
  let total = 0;
  let withoutRegion = 0;

  for (const doc of capDocs || []) {
    if (!caps.isEligible(doc, service)) continue;
    total += 1;
    const regions = Array.isArray((doc[service] || {}).regionIds) ? doc[service].regionIds : [];
    if (regions.length === 0) { withoutRegion += 1; continue; }
    for (const r of new Set(regions)) {
      if (counts.has(r)) counts.set(r, counts.get(r) + 1);
      else unknown.add(r);
    }
  }

  const rows = regionIds.map((regionId) => ({
    regionId,
    providers: counts.get(regionId),
    ready: counts.get(regionId) >= min,
  }));
  return {
    service,
    min,
    totalProviders: total,
    withoutRegion,
    unknownRegions: Array.from(unknown).sort(),
    readyRegions: rows.filter((r) => r.ready).map((r) => r.regionId),
    rows,
  };
}

module.exports = { summarizeSupply };
