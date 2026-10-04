'use strict';

/**
 * 13.2.3 — MATCHING ORKESTRATORI.
 *
 * Konsepsiyadagi quvur, aniq qadamlar bilan:
 *   1) Nomzod manbalari (adapter tanlaydi)
 *   2) Deduplikatsiya `providerId` bo'yicha, `sourceCount` bilan
 *   3) Qattiq filtrlar (modul, hudud, imkoniyat, trust, bloklar, egasi)
 *   4) Modul qoidalari (adapter)
 *   5) Score va chegara
 *   6) Tartiblash (fairness band ichida)
 *   7) `demand_matches` yozish + `matchedBucket`
 *
 * MUHIM: push BU YERDA YUBORILMAYDI. Matcher kimlar mosligini topadi,
 * Notification Policy kimga xabar berishni hal qiladi — konsepsiyaning
 * eng muhim ajratmasi (`notify/policy.js`).
 *
 * `dedupe` va `fairness` alohida fayl qilinmadi: ikkisi ham bir necha
 * o'n qatorlik mantiq va shu quvurdan tashqarida ishlatilmaydi.
 * Alohida fayl faqat navigatsiyani qiyinlashtirardi.
 */

const scoring = require('./scoring');
const geo = require('../geo/geo');
const { matchKey, requireCanonicalId } = require('../core/ids');
const { MATCHING_STATE } = require('../core/state_machine');
const trust = require('../trust/compute');

const MATCHES_COLLECTION = 'demand_matches';
const STATS_COLLECTION = 'provider_stats';

/**
 * 2-QADAM — DEDUPLIKATSIYA.
 *
 * Konsepsiya: «Barcha manbalardan kelgan nomzodlar providerId bo'yicha
 * birlashtiriladi. Score'ga manbalar soni ijobiy ta'sir qiladi.»
 *
 * Birlashtirishda kategoriya va hudud ro'yxatlari qo'shiladi, `consentGiven`
 * esa OR bilan: bitta manbada rozilik bo'lsa, yetarli.
 */
function dedupe(lists) {
  const byId = new Map();
  for (const list of lists) {
    for (const c of (list || [])) {
      if (!c || !c.providerId) continue;
      const prev = byId.get(c.providerId);
      if (!prev) {
        byId.set(c.providerId, {
          ...c,
          sources: [c.source],
          sourceCount: 1,
          categoryIds: [...(c.categoryIds || [])],
          categoryGroups: [...(c.categoryGroups || [])],
          regionIds: [...(c.regionIds || [])],
          districtIds: [...(c.districtIds || [])],
        });
        continue;
      }
      if (!prev.sources.includes(c.source)) {
        prev.sources.push(c.source);
        prev.sourceCount += 1;
      }
      for (const f of ['categoryIds', 'categoryGroups', 'regionIds', 'districtIds']) {
        for (const v of (c[f] || [])) if (!prev[f].includes(v)) prev[f].push(v);
      }
      prev.consentGiven = prev.consentGiven || c.consentGiven;
      // `capabilities` manbasi ishonchliroq — uning maydonlari ustun.
      if (c.source === 'capabilities') {
        prev.vehicle = c.vehicle || prev.vehicle;
        prev.wholesale = c.wholesale || prev.wholesale;
        prev.acceptsParcels = c.acceptsParcels || prev.acceptsParcels;
        prev.pushOptOut = c.pushOptOut || prev.pushOptOut;
        prev.digestOnly = c.digestOnly || prev.digestOnly;
      }
    }
  }
  return Array.from(byId.values());
}

/**
 * 3-QADAM — QATTIQ FILTRLAR.
 *
 * Bu yerda o'tmagan nomzod MOS EMAS va hech qanday score uni qaytara
 * olmaydi.
 */
function applyHardFilters(demand, candidates, config, adapter) {
  const kept = [];
  const rejected = [];

  for (const c of candidates) {
    const why = hardFilterReason(demand, c, config, adapter);
    if (why) rejected.push({ providerId: c.providerId, reason: why });
    else kept.push(c);
  }
  return { kept, rejected };
}

function hardFilterReason(demand, c, config, adapter) {
  // Talab egasining o'zi.
  if (c.providerId === demand.ownerId) return 'self';

  // Bloklar (ikki tomonlama).
  if (Array.isArray(demand.blockedProviderIds)
    && demand.blockedProviderIds.includes(c.providerId)) return 'blocked_by_owner';
  if (Array.isArray(c.blockedOwnerIds)
    && c.blockedOwnerIds.includes(demand.ownerId)) return 'blocked_by_provider';

  // Trust — juda past bo'lsa matching'dan butunlay chiqariladi.
  const stats = c.stats || {};
  const trustScore = Number.isFinite(stats.trustScore)
    ? stats.trustScore
    : config.trust.initial;
  if (trust.excludedFromMatching(trustScore, config)) return 'trust_too_low';

  // Moderator bloki.
  if (stats.matchingBlocked === true) return 'moderator_block';

  // Yangi taklifchi bir vaqtda ko'p ish olmaydi (cold start cheklovi).
  const np = config.newProvider;
  const completed = Number(stats.completedCount) || 0;
  if (completed < np.completedThreshold
    && Number(stats.activeAssignments) >= np.maxConcurrent) {
    return 'new_provider_busy';
  }

  // Qarz — to'lanmaguncha yangi buyurtma olinmaydi (Т-11, mavjud
  // `blockedReason: 'deferred_debt'` mexanizmi bilan bir xil mantiq).
  if (stats.debtBlocked === true) return 'debt';

  // Modul qoidalari (adapter): vazn, hajm, transport, bo'sh joy...
  if (adapter && typeof adapter.isEligible === 'function') {
    const r = adapter.isEligible(demand, c, config);
    if (r !== true) return typeof r === 'string' ? r : 'adapter';
  }

  return null;
}

/**
 * Nomzod uchun masofa/ETA o'lchovlari.
 *
 * Т-4: tashqi so'rov YO'Q — geohash + haversine x yo'l koeffitsienti.
 */
function metricsFor(demand, c, config) {
  const loc = demand.location || {};
  const p = c.presence || {};
  const out = {};

  if (Number.isFinite(p.lat) && Number.isFinite(p.lng)
    && Number.isFinite(loc.lat) && Number.isFinite(loc.lng)) {
    out.distanceKm = Number(
      geo.roadKm(p.lat, p.lng, loc.lat, loc.lng, config.roadFactor).toFixed(2),
    );
    out.etaMinutes = geo.etaMinutes(
      p.lat, p.lng, loc.lat, loc.lng, p.vehicle || c.vehicle, config.roadFactor,
    );
  }

  // Shaharlararo: «yo'lim ustida» chetlashishi.
  const trip = c.trip;
  const dest = demand.destination;
  if (trip && trip.from && trip.to && dest
    && Number.isFinite(loc.lat) && Number.isFinite(dest.lat)) {
    out.detourKm = geo.detourKm(
      trip.from, { lat: loc.lat, lng: loc.lng },
      { lat: dest.lat, lng: dest.lng }, trip.to, config.roadFactor,
    );
  }

  return out;
}

/**
 * TO'LIQ MATCHING.
 *
 * @param {object} deps
 * @param {object} deps.db Firestore
 * @param {object} deps.demand `demands` hujjati (`id` bilan)
 * @param {object} deps.config module_config
 * @param {object} deps.adapter modul adapteri
 * @param {Array<Function>} deps.sources `(db, demand, config, kwIndex) => candidates[]`
 * @param {object} deps.keywordIndex
 * @param {boolean} [deps.dryRun] shadow mode uchun: hisoblaydi, YOZMAYDI
 */
async function runMatching(deps) {
  const {
    db, demand, config, adapter, sources, keywordIndex, dryRun = false,
  } = deps;

  const started = Date.now();

  // 1) Manbalar — parallel.
  const lists = await Promise.all(
    sources.map(async (fn) => {
      try {
        return await fn(db, demand, config, keywordIndex);
      } catch (e) {
        console.error(`manba xatosi (${fn.name || 'anon'}): ${e.message}`);
        return [];
      }
    }),
  );

  // 2) Deduplikatsiya.
  let candidates = dedupe(lists);

  // Taklifchilar statistikasi — qattiq filtrlar uchun kerak.
  await attachStats(db, candidates);

  // 3-4) Qattiq filtrlar + modul qoidalari.
  const { kept, rejected } = applyHardFilters(demand, candidates, config, adapter);
  candidates = kept;

  // 5) Score.
  const scored = candidates.map((c) => {
    const metrics = metricsFor(demand, c, config);
    const stats = c.stats || {};
    const s = scoring.scoreCandidate(
      demand,
      {
        providerId: c.providerId,
        categoryIds: c.categoryIds,
        categoryGroups: c.categoryGroups,
        demandCategoryGroup: demand.categoryGroup,
        sourceCount: c.sourceCount,
        trustScore: stats.trustScore,
        rating: stats.rating,
        todayOrders: stats.todayOrders,
        completedCount: stats.completedCount,
      },
      metrics,
      config,
    );
    // Adapter o'z score'ini qo'shishi mumkin (modul qoidalari).
    if (adapter && typeof adapter.score === 'function') {
      const bonus = Number(adapter.score(demand, c, config)) || 0;
      s.adapterBonus = bonus;
      s.finalScore = scoring.clamp01(s.finalScore + bonus);
    }
    s.candidate = c;
    return s;
  });

  // Chegara — adapter o'z chegarasini belgilashi mumkin.
  const minScore = adapter && typeof adapter.minScore === 'function'
    ? adapter.minScore(config)
    : config.minScore;
  const passing = scored.filter((s) => s.finalScore >= minScore);

  // 6) Tartiblash — fairness faqat band ichida.
  const ranked = scoring.rankCandidates(passing, config, demand.mode);

  const result = {
    demandId: demand.id,
    state: ranked.length > 0 ? MATCHING_STATE.DONE : MATCHING_STATE.NO_PROVIDERS,
    matchedCount: ranked.length,
    matchedBucket: scoring.matchedBucket(ranked.length),
    candidateCount: candidates.length + rejected.length,
    rejected,
    ranked,
    durationMs: 0,
    written: 0,
  };

  // 7) Yozish.
  if (!dryRun && ranked.length > 0) {
    result.written = await writeMatches(db, demand, ranked, config, adapter);
  }

  result.durationMs = Date.now() - started;
  return result;
}

/**
 * Taklifchilar statistikasini biriktirish.
 *
 * `provider_stats` faqat server yozadi (trust, rating, bugungi buyurtma).
 * Firestore `getAll` 1000 tagacha hujjatni bitta so'rovda oladi.
 */
async function attachStats(db, candidates) {
  if (candidates.length === 0) return;
  const refs = candidates.map((c) => db.collection(STATS_COLLECTION).doc(c.providerId));
  const snaps = await db.getAll(...refs);
  for (let i = 0; i < candidates.length; i += 1) {
    const s = snaps[i];
    candidates[i].stats = s && s.exists ? (s.data() || {}) : {};
  }
}

/**
 * `demand_matches` yozish — PROYEKSIYA bilan.
 *
 * Taklifchi `demands` hujjatini HECH QACHON o'qimaydi. Bu yerda yozilgan
 * qisqartirilgan nusxa — uning ko'radigan hamma narsasi.
 */
async function writeMatches(db, demand, ranked, config, adapter) {
  const projection = adapter && typeof adapter.buildProjection === 'function'
    ? adapter.buildProjection(demand, config)
    : defaultProjection(demand, config);

  let written = 0;
  // Firestore batch — 500 operatsiya cheklovi.
  for (let i = 0; i < ranked.length; i += 450) {
    const chunk = ranked.slice(i, i + 450);
    const batch = db.batch();
    for (let rank = 0; rank < chunk.length; rank += 1) {
      const s = chunk[rank];
      const providerId = requireCanonicalId(s.providerId, 'providerId');
      const ref = db.collection(MATCHES_COLLECTION).doc(matchKey(demand.id, providerId));
      batch.set(ref, {
        demandId: demand.id,
        /**
         * `providerId` MAYDON sifatida — qoidalar ayni shuni tekshiradi
         * (Т-2.1). Kalitga ishonib qoida yozilmaydi.
         */
        providerId,
        module: demand.module,
        mode: demand.mode,
        status: 'new',
        score: Number(s.finalScore.toFixed(4)),
        /**
         * 13.5.4 — «НЕГА МОС?» САВОЛИГА ЖАВОБ.
         *
         * Эга саволи: «номос provider чиқяптими?». Унга жавоб бериш
         * учун 50 тасодифий match'ни қўлда текшириш керак, лекин
         * `score: 0.76` рақами ҳеч нарса тушунтирмайди.
         *
         * Шунинг учун score таркиби ҳам сақланади. Қўшимча ўқиш йўқ:
         * бу маълумот `scoreCandidate` да аллақачон ҳисобланган.
         *
         * Бу майдон ТАКЛИФЧИГА кўринади (match ҳужжати унинг учун),
         * лекин у махфий эмас: фақат «қанча мос» деган ўз баҳоси.
         */
        scoreParts: {
          base: Number(s.base.toFixed(4)),
          categoryMatch: Number(s.parts.categoryMatch.toFixed(3)),
          proximity: Number(s.parts.proximity.toFixed(3)),
          sourceStrength: Number(s.parts.sourceStrength.toFixed(3)),
          newProviderBoost: Number((s.boost || 0).toFixed(3)),
          adapterBonus: Number((s.adapterBonus || 0).toFixed(3)),
          equalizer: Number(s.equalizer.toFixed(3)),
        },
        rank: i + rank + 1,
        sources: s.candidate.sources,
        consentGiven: s.candidate.consentGiven !== false,
        metrics: s.metrics || {},
        projection,
        expiresAt: demand.timeWindow ? demand.timeWindow.expiresAt : null,
        createdAt: new Date(),
      }, { merge: true });
      written += 1;
    }
    await batch.commit();
  }
  return written;
}

/**
 * STANDART PROYEKSIYA — MAXFIYLIK QOIDASI SHU YERDA.
 *
 * Taklifchi ko'radi: tuman, TAXMINIY nuqta (300-600 m, Т-20), kategoriya,
 * qisqa izoh, muddat, rasm.
 * Taklifchi KO'RMAYDI: aniq manzil, telefon, qabul qiluvchi ismi,
 * `ownerId`, boshqa takliflar.
 */
function defaultProjection(demand, config) {
  const loc = demand.location || {};
  const pr = config.projection || {};
  const approx = (Number.isFinite(loc.lat) && Number.isFinite(loc.lng))
    ? geo.approxPoint(
      loc.lat, loc.lng, demand.id,
      pr.approxMinMeters || 300, pr.approxMaxMeters || 600,
    )
    : null;

  return {
    title: demand.title || '',
    description: String(demand.description || '').slice(0, 300),
    categoryId: demand.categoryId || null,
    districtId: loc.districtId || null,
    regionId: loc.regionId || null,
    approxLat: approx ? approx.lat : null,
    approxLng: approx ? approx.lng : null,
    geohash: (loc.geohash || '').slice(0, pr.geohashPrecision || 5),
    budget: demand.budget || null,
    quantity: demand.quantity || null,
    images: ((demand.media || {}).images || []).slice(0, 3),
    neededBy: (demand.timeWindow || {}).neededBy || null,
    attributes: demand.attributes || {},
  };
}

module.exports = {
  MATCHES_COLLECTION,
  STATS_COLLECTION,
  dedupe,
  applyHardFilters,
  hardFilterReason,
  metricsFor,
  runMatching,
  writeMatches,
  defaultProjection,
  attachStats,
};
