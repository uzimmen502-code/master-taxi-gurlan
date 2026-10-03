'use strict';

/**
 * `service` ADAPTERI — P0 PILOTI (Т-17, Қ-1).
 *
 * Nega aynan shu modul pilot: bugun bu oqim UMUMAN YO'Q. Odamlar `ads`ga
 * «электрикман» deb e'lon berib, mijoz o'zi topib qo'ng'iroq qilishini
 * kutadi. Demak:
 *   - ko'chiriladigan ma'lumot yo'q,
 *   - dual-write yo'q,
 *   - buziladigan production oqimi yo'q,
 *   - foydalanuvchi uchun qiymat aniq: «Usta chaqirish» -> 3 ta taklif.
 *
 * Konsepsiyadagi pilot (gilam yuvish) buning teskarisi edi: to'liq ishlab
 * turgan oqim, nol yangi qiymat, regressiya xavfi.
 *
 * Rejim: `quote` — eng oddiy. To'lqin yo'q, trips yo'q, to'lov yo'q,
 * jonli kuzatuv yo'q. Yadroni ayni shunday sodda muhitda sinash kerak.
 */

const capabilities = require('../sources/capabilities');
const activeListings = require('../sources/active_listings');
const { defaultProjection } = require('../matching/orchestrator');
const { buildPushText } = require('../notify/policy');

/** @type {import('../core/types').DemandModuleAdapter} */
const serviceAdapter = {
  module: 'service',
  mode: 'quote',

  /**
   * Nomzod manbalari.
   *
   * Tartib muhim: `capabilities` ishonchli (odam o'zi rozilik bergan),
   * `active_listings` esa COLD START uchun (birinchi kunda
   * `provider_capabilities` bo'sh bo'ladi — konsepsiyada bu muammo
   * ko'rilmagan edi).
   */
  sources: [
    capabilities.fetchCandidates,
    activeListings.fetchCandidates,
  ],

  /**
   * Qattiq filtr — modul qoidalari.
   * `true` qaytarsa o'tadi, satr qaytarsa sabab bilan rad etiladi.
   */
  isEligible(demand, candidate) {
    // Usta mijozga boradigan bo'lsa, hudud mos kelishi SHART.
    const visitType = (demand.attributes || {}).visitType || 'at_my_place';
    if (visitType === 'at_my_place') {
      const loc = demand.location || {};
      const districts = candidate.districtIds || [];
      const regions = candidate.regionIds || [];
      const districtOk = !loc.districtId
        || districts.length === 0
        || districts.includes(loc.districtId);
      const regionOk = !loc.regionId
        || regions.length === 0
        || regions.includes(loc.regionId);
      if (!districtOk && !regionOk) return 'out_of_area';
    }

    // Brigada kerak bo'lsa, yolg'iz usta mos emas.
    const needed = Number((demand.attributes || {}).workersNeeded) || 0;
    if (needed > 1) {
      const canCrew = Number(candidate.raw && candidate.raw.crewSize) || 1;
      if (canCrew < needed) return 'crew_too_small';
    }

    return true;
  },

  /**
   * Modulga xos qo'shimcha score (-0.1 .. +0.1 oralig'ida bo'lishi kerak).
   *
   * Shoshilinch ishda o'z tumanidagi usta ustun: «ток йўқ» deganda
   * qo'shni tumandan kelish 40 daqiqa degani.
   */
  score(demand, candidate) {
    let bonus = 0;
    const loc = demand.location || {};
    if (loc.districtId && (candidate.districtIds || []).includes(loc.districtId)) {
      bonus += 0.05;
    }
    // Rozilik bergan taklifchi oldinroq: u haqiqatan ish kutyapti.
    if (candidate.consentGiven !== false) bonus += 0.03;
    return bonus;
  },

  minScore(config) {
    return config.minScore;
  },

  buildProjection(demand, config) {
    const p = defaultProjection(demand, config);
    // Xizmat so'rovida «kirish izohlari» ustaga keraklik ma'lumot
    // («ikkinchi qavat, lift yo'q»), lekin ANIQ MANZIL emas.
    const attrs = demand.attributes || {};
    p.attributes = {
      visitType: attrs.visitType || null,
      objectType: attrs.objectType || null,
      areaM2: attrs.areaM2 || null,
      workersNeeded: attrs.workersNeeded || null,
      hasMaterials: attrs.hasMaterials === undefined ? null : attrs.hasMaterials,
      preferredTimeOfDay: attrs.preferredTimeOfDay || null,
      accessNotes: String(attrs.accessNotes || '').slice(0, 200),
    };
    return p;
  },

  buildPushTemplate(demand, ctx = {}) {
    return buildPushText({
      mode: 'quote',
      categoryName: ctx.categoryName || 'Xizmat so\'rovi',
      districtName: ctx.districtName || '',
      landmark: '',
      distanceKm: ctx.distanceKm,
    });
  },
};

module.exports = serviceAdapter;
