'use strict';

/**
 * `logistics` ADAPTERI — AVA Logistics (Relay) LEG'lari.
 *
 * LEG — yadroning `demand` hujjati (hujjat §5), lekin ikki farq bilan:
 *
 *   1) LEG'ni KLIENT YARATMAYDI — `createLogisticsOrder` serverda
 *      yaratadi (`demand_input.schema.json` enum'ida `logistics` YO'Q,
 *      bu ataylab). Shuning uchun `attributes` sxemasi ham kerak emas.
 *   2) TAKLIF (offer) YO'Q: narx tarifdan qotgan (D-8), ijrochi
 *      `acceptLeg` bilan oladi — birinchi qabul g'olib. Mijoz (sender)
 *      LEG'ni ko'rmaydi va tanlamaydi (45-band).
 *
 * Rejim `quote`: push limiti va 120 daqiqalik qabul muddati (konfig)
 * shaharlararo yo'nalishga mos; `dispatch` (15 daqiqa, limitsiz push)
 * esa shahar ichidagi «hozir kutyapman» uchun.
 */

const logisticsCandidates = require('../sources/logistics_candidates');
const { defaultProjection } = require('../matching/orchestrator');
const { buildPushText } = require('../notify/policy');

/** @type {import('../core/types').DemandModuleAdapter} */
const logisticsAdapter = {
  module: 'logistics',
  mode: 'quote',

  sources: [logisticsCandidates.fetchCandidates],

  /**
   * Qattiq filtr: olish nuqtasi nomzodning hududida bo'lishi SHART;
   * hudud kesib o'tiladigan LEG'da yetkazish hududi ham (yoki `freight`).
   */
  isEligible(demand, candidate) {
    const loc = demand.location || {};
    const dest = demand.destination || {};
    const regions = candidate.regionIds || [];
    const districts = candidate.districtIds || [];
    const inArea = (p) => (!!p.districtId && districts.includes(p.districtId))
      || (!!p.regionId && regions.includes(p.regionId));

    if (!inArea(loc)) return 'out_of_area';
    const crossesRegion = !!dest.regionId && dest.regionId !== loc.regionId;
    if (crossesRegion && candidate.viaService !== 'freight' && !inArea(dest)) {
      return 'destination_out_of_area';
    }
    return true;
  },

  /** O'z tumanidagi ijrochi — kichik ustunlik; line_haul'da freight ustun. */
  score(demand, candidate) {
    let bonus = 0;
    const loc = demand.location || {};
    if (loc.districtId && (candidate.districtIds || []).includes(loc.districtId)) bonus += 0.04;
    const kind = ((demand.attributes || {}).legKind) || 'direct';
    if (kind === 'line_haul' && candidate.viaService === 'freight') bonus += 0.04;
    return bonus;
  },

  minScore(config) {
    return config.minScore;
  },

  /**
   * Ijrochi ko'radigan proyeksiya: posilka o'lchami, yo'nalish (tuman
   * darajasida), HAQ (ijrochi uchun ochiq — bu uning daromadi).
   * Aniq manzil va telefon — `acceptLeg` dan keyin, bosqichma-bosqich (Т-9).
   * Mijoz narxi (`customerPrice`) ijrochiga KO'RSATILMAYDI (14-band).
   */
  buildProjection(demand, config) {
    const p = defaultProjection(demand, config);
    const a = demand.attributes || {};
    const parcel = a.parcel || {};
    p.attributes = {
      // Jo'natma ID — ijrochi custodian bo'lgach `getShipmentSecrets`
      // (kod/QR ni keyingi ijrochiga ko'rsatish) uchun kerak. Sir emas:
      // `shipments` hujjatini faqat tayinlangan ijrochi o'qiydi (qoida),
      // sirlarni esa faqat egasi/custodian oladi (callable).
      shipmentId: a.shipmentId || '',
      trackingNumber: a.trackingNumber || '',
      legKind: a.legKind || 'direct',
      legIndex: Number(a.legIndex) || 0,
      legCount: Number(a.legCount) || 1,
      payout: Number(a.payout) || 0,
      chargeableWeightG: Number(parcel.chargeableWeightG) || 0,
      lengthCm: Number(parcel.lengthCm) || 0,
      widthCm: Number(parcel.widthCm) || 0,
      heightCm: Number(parcel.heightCm) || 0,
      fragile: parcel.fragile === true,
      fromDistrictId: (demand.location || {}).districtId || '',
      toDistrictId: (demand.destination || {}).districtId || '',
      toRegionId: (demand.destination || {}).regionId || '',
    };
    return p;
  },

  buildPushTemplate(demand, ctx = {}) {
    return buildPushText({
      mode: 'quote',
      categoryName: ctx.categoryName || 'Jo\'natma',
      districtName: ctx.districtName || '',
      landmark: '',
      distanceKm: ctx.distanceKm,
    });
  },
};

module.exports = logisticsAdapter;
