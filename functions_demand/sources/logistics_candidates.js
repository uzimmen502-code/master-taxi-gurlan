'use strict';

/**
 * NOMZOD MANBASI — AVA Logistics LEG'lari uchun.
 *
 * `logistics` — bu CAPABILITY EMAS (`core/capabilities.js` → SERVICES'da
 * yo'q va bo'lmaydi): posilkani olib boradigan odam KURYER yoki YUK
 * tashuvchi. Shuning uchun LEG nomzodlari MAVJUD capability'lardan
 * olinadi (4-band: yangi ro'yxat qurilmaydi):
 *
 *   courier  — `acceptsParcels: true` bo'lganlar (shahar ichi, first/last mile)
 *   freight  — yuk tashuvchilar (line_haul, shaharlararo)
 *
 * `sources/capabilities.fetchCandidates` qayta ishlatiladi: unga
 * `module` ni almashtirib berilgan talab nusxasi uzatiladi — so'rov
 * `courier.active + courier.regionIds` bo'yicha ketadi, lifecycle
 * (`isEligible`) o'sha yerda tekshiriladi.
 *
 * INFERRED: freight capability'sining maydonlari (`vehicle` va h.k.)
 * hali filtr sifatida ishlatilmaydi — mavjud bo'lmagan maydon bo'yicha
 * filtr taxmin bo'lardi (courier adapteridagi qoida bilan bir xil).
 */

const capabilities = require('./capabilities');

/** Qaysi capability qaysi LEG turini olib boradi. */
const SERVICES_BY_LEG_KIND = {
  direct: ['courier', 'freight'],
  first_mile: ['courier', 'freight'],
  last_mile: ['courier', 'freight'],
  line_haul: ['freight', 'courier'],
};

async function fetchCandidates(db, demand, config, keywordIndex) {
  const kind = ((demand && demand.attributes) || {}).legKind || 'direct';
  const services = SERVICES_BY_LEG_KIND[kind] || SERVICES_BY_LEG_KIND.direct;

  const out = [];
  const seen = new Set();
  for (const service of services) {
    // Kategoriya LEG uchun ma'nosiz — `categoryId` olib tashlanadi, aks
    // holda manba kategoriya bo'yicha filtrlab hammani rad etadi.
    const asService = { ...demand, module: service, categoryId: null, categoryGroup: null };
    let list = [];
    try {
      list = await capabilities.fetchCandidates(db, asService, config, keywordIndex);
    } catch (e) {
      console.error(`logistics manbasi (${service}) xato: ${e.message}`);
      continue;
    }
    for (const c of list) {
      if (seen.has(c.providerId)) continue;
      if (service === 'courier' && c.acceptsParcels !== true) continue;
      seen.add(c.providerId);
      out.push({
        ...c,
        source: 'capabilities',
        /** Qaysi capability orqali kelgan — adapter `isEligible` ishlatadi. */
        viaService: service,
      });
    }
  }
  return out;
}

module.exports = { SERVICES_BY_LEG_KIND, fetchCandidates };
