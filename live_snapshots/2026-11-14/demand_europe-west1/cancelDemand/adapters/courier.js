'use strict';

/**
 * `courier` ADAPTERI — shahar ichi kuryer (13.6.3).
 *
 * `service` adapteridan farqi rejimda: u `quote` (usta narx taklif qiladi,
 * shoshilinch emas), bu esa `dispatch` — mijoz HOZIR kutyapti, bitta
 * kuryer yetarli, har soniya muhim. Yadro `dispatch`ni allaqachon
 * biladi:
 *   - `push.dispatch` limiti YO'Q va tinch soatlar to'xtatmaydi
 *     (`notify/policy.js:150`);
 *   - `assignmentDeadlineMinutes.dispatch = 15` — qabul qilib yo'q bo'lsa,
 *     talab 15 daqiqada qaytib ochiladi (`core/config.js:146`);
 *   - `MODES_WITH_IN_PROGRESS` ichida (`core/state_machine.js:72`);
 *   - `waves` va `minCandidatesPerWave` konfigda tayyor.
 *
 * Ya'ni bu fayl yadroga yangi mexanizm qo'shmaydi — mavjudini modul
 * qoidalari bilan ulaydi.
 *
 * ── Manbalar tartibi ───────────────────────────────────────────────────
 * `presence_geo` BIRINCHI: dispatch'da «hozir qayerdasan» hal qiluvchi,
 * va `dedupe` birinchi kelgan nusxaga `presence`ni biriktiradi.
 * `capabilities` ikkinchi — u «men umuman kuryerlik qilaman» degan
 * ro'yxat, undan `vehicle` va `acceptsParcels` kabi maydonlar keladi
 * (`dedupe` da `capabilities` maydonlari ustun).
 */

const presenceGeo = require('../sources/presence_geo');
const capabilities = require('../sources/capabilities');
const geo = require('../geo/geo');
const { defaultProjection } = require('../matching/orchestrator');
const { buildPushText } = require('../notify/policy');
const { toMillis } = require('../core/state_machine');

/** @type {import('../core/types').DemandModuleAdapter} */
const courierAdapter = {
  module: 'courier',
  mode: 'dispatch',

  sources: [
    presenceGeo.fetchCandidates,
    capabilities.fetchCandidates,
  ],

  /**
   * Qattiq filtr.
   *
   * ATAYLAB QISQA. Vazn, hajm va «posilka sig'adimi» filtrlari shu yerga
   * qo'shilishi kerak, LEKIN `provider_capabilities` da hali
   * `parcelCapacity` maydoni YO'Q (13.6.5 vazifasi). Mavjud bo'lmagan
   * maydon bo'yicha filtr yozish — taxmin, shuning uchun yozilmadi.
   */
  isEligible(demand, candidate, config) {
    const p = candidate.presence || null;
    // `coord()` — `Number(null)` NOL bo'lgani uchun kerak, aks holda
    // koordinatasiz kuryer «0,0 nuqtada» deb qabul qilinadi va
    // `too_far` sababi bilan rad etiladi. Sabab kodi `rejectReasons`
    // analitikasiga tushadi, ya'ni noto'g'ri sabab diagnostikani chalg'itadi.
    const pLat = p ? presenceGeo.coord(p.lat) : Number.NaN;
    const pLng = p ? presenceGeo.coord(p.lng) : Number.NaN;
    // Dispatch'da joylashuvsiz nomzod bo'lmaydi: mijozga «qancha vaqtda
    // yetib keladi» deb aytib bo'lmaydi va to'lqin tartibi qurilmaydi.
    if (!Number.isFinite(pLat) || !Number.isFinite(pLng)) return 'no_presence';

    const loc = demand.location || {};
    const dLat = presenceGeo.coord(loc.lat);
    const dLng = presenceGeo.coord(loc.lng);
    if (!Number.isFinite(dLat) || !Number.isFinite(dLng)) {
      return 'no_demand_location';
    }

    const radiusKm = Number(config && config.searchRadiusKm) || 15;
    const km = geo.roadKm(pLat, pLng, dLat, dLng, config && config.roadFactor);
    // Manba geohash KATAGI bo'yicha oladi, katak esa radiusdan kattaroq.
    // Aniq chegara shu yerda qo'yiladi.
    if (km > radiusKm) return 'too_far';

    return true;
  },

  /**
   * Modulga xos qo'shimcha score (-0.1 .. +0.1).
   *
   * Masofa va ETA'ni yadro allaqachon hisobga oladi (`scoring.scoreCandidate`
   * ga `metrics` uzatiladi), shuning uchun bu yerda TAKRORLANMAYDI.
   *
   * Qo'shiladigan yagona signal — GPS YANGILIGI. 10 soniya oldin joyini
   * yuborgan kuryer «hozir shu yerda» ekani ancha ishonchli; 110 soniya
   * oldingisi chegarada turibdi va u yo'lda bo'lishi mumkin. Yadro
   * presence yoshini bilmaydi.
   */
  score(demand, candidate, config) {
    const p = candidate.presence || {};
    const ms = toMillis(p.updatedAt);
    if (!ms) return 0;

    const maxAgeSec = Number(config && config.maxLocationAgeSec) || 120;
    const ageSec = Math.max(0, (Date.now() - ms) / 1000);
    if (ageSec >= maxAgeSec) return 0;

    // Yangi -> +0.05, chegaraga yaqin -> 0.
    return Number((0.05 * (1 - ageSec / maxAgeSec)).toFixed(4));
  },

  minScore(config) {
    return config.minScore;
  },

  /**
   * Kuryerga ko'rsatiladigan proyeksiya.
   *
   * Aniq manzil BERILMAYDI — `defaultProjection` taxminiy nuqtani
   * qaytaradi (Т-20). Kuryer qabul qilgandan keyingina aniq manzil
   * ochiladi; bu `acceptOffer` oqimining vazifasi, proyeksiyaniki emas.
   */
  buildProjection(demand, config) {
    const p = defaultProjection(demand, config);
    const attrs = demand.attributes || {};
    p.attributes = {
      // Faqat sxemada BOR maydonlar.
      preferredTimeOfDay: attrs.preferredTimeOfDay || null,
      accessNotes: String(attrs.accessNotes || '').slice(0, 200),
    };
    return p;
  },

  buildPushTemplate(demand, ctx = {}) {
    return buildPushText({
      mode: 'dispatch',
      categoryName: ctx.categoryName || 'Yetkazib berish',
      districtName: ctx.districtName || '',
      landmark: '',
      distanceKm: ctx.distanceKm,
    });
  },
};

module.exports = courierAdapter;
