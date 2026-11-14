'use strict';

/**
 * 13.5.2 — SHADOW MODE АНАЛИТИКАСИ.
 *
 * Эга рўйхати (2026-10-03) — АЙНАН шу тўққиз кўрсаткич:
 *   demandsCreated · providersMatched · pushEligible · offersReceived
 *   timeToFirstOffer · acceptedOffer · expiredWithoutOffer
 *   completedDemand · cancelledDemand
 *
 * Эга тўртта саволга жавоб кутади:
 *   1) matching тўғрими?            -> offersReceived / providersMatched
 *   2) номос provider чиқяптими?    -> rejectReasons + qўlda tekshiruv
 *   3) provider сони кам/кўпми?     -> noProviders + expiredWithoutOffer
 *   4) push спам бўляптими?         -> pushEligible vs pushSent + digest
 *
 * НЕГА АЛОҲИДА ВОҚЕА ОҚИМИ (event stream) ЯСАЛМАДИ:
 * Урганч ҳажмида кунлик талаб сони юзларда. Шунинг учун кунлик
 * агрегация мавжуд ҳужжатларни СКАНЕР қилиб ҳисоблайди — янги
 * коллекция, янги trigger ва янги харажат керак эмас.
 *
 * `timeToFirstOffer` эса скандан ҳисоблаб бўлмайди (ҳар талабнинг
 * таклифлар субколлекциясини ўқиш керак бўларди), шунинг учун
 * `submitOffer` талаб ҳужжатига `firstOfferAt` ва `offerCount`
 * ёзади — битта қўшимча майдон, нол қўшимча ўқиш.
 */

const { STATUS, MATCHING_STATE, toMillis } = require('../core/state_machine');

const COLLECTION = 'analytics_demand_daily';

/** Эга рўйхатидаги тўққиз кўрсаткичнинг номлари — ЎЗГАРТИРИЛМАЙДИ. */
const METRIC_NAMES = [
  'demandsCreated',
  'providersMatched',
  'pushEligible',
  'offersReceived',
  'timeToFirstOffer',
  'acceptedOffer',
  'expiredWithoutOffer',
  'completedDemand',
  'cancelledDemand',
];

/** Бўш ҳисоб. */
function emptyBucket() {
  return {
    // ── Эга рўйхати ───────────────────────────────────────────────────
    demandsCreated: 0,
    providersMatched: 0,
    pushEligible: 0,
    offersReceived: 0,
    /** Медиана ҳисоблаш учун барча қийматлар (сония). */
    timeToFirstOfferSamples: [],
    acceptedOffer: 0,
    expiredWithoutOffer: 0,
    completedDemand: 0,
    cancelledDemand: 0,

    // ── Эга саволларига жавоб берувчи қўшимчалар ──────────────────────
    /** «provider сони кам/кўпми» — умуман мос одам топилмаган талаблар. */
    noProviders: 0,
    /** «push спам бўляптими» — ҳақиқатан юборилган. */
    pushSent: 0,
    /** Лимит ёки тинч соат сабабли дайжестга тушган. */
    pushDigest: 0,
    /** Розилик бермаган номзодга push умуман кетмаган (cold start). */
    pushNoConsent: 0,
    /** «номос provider чиқяптими» — қаттиқ фильтрлар сабаблари. */
    rejectReasons: {},
    /** Камида битта таклиф олган талаблар (fill rate учун). */
    demandsWithOffer: 0,
    /** Таклиф бермаган, лекин мос деб топилган таклифчилар сони. */
    matchedWithoutOffer: 0,
  };
}

/**
 * Битта талабни ҳисобга қўшади.
 *
 * @param {object} bucket
 * @param {object} demand `demands` ҳужжати
 * @param {object} stats  `demands/{id}/private/stats` ҳужжати (бўлмаса `{}`)
 */
function addDemand(bucket, demand, stats = {}) {
  bucket.demandsCreated += 1;

  const matched = Number(stats.matchedCount) || 0;
  bucket.providersMatched += matched;

  const offers = Number(demand.offerCount) || 0;
  bucket.offersReceived += offers;
  if (offers > 0) bucket.demandsWithOffer += 1;

  // Мос деб топилган, лекин таклиф бермаганлар — «номос provider»
  // саволининг энг тўғридан-тўғри белгиси.
  if (matched > offers) bucket.matchedWithoutOffer += (matched - offers);

  // timeToFirstOffer — фақат таклиф келган талабларда.
  const createdMs = toMillis(demand.createdAt);
  const firstMs = toMillis(demand.firstOfferAt);
  if (createdMs > 0 && firstMs > createdMs) {
    bucket.timeToFirstOfferSamples.push(Math.round((firstMs - createdMs) / 1000));
  }

  // Статус кесими.
  switch (demand.status) {
    case STATUS.COMPLETED:
      bucket.completedDemand += 1;
      break;
    case STATUS.CANCELLED:
      bucket.cancelledDemand += 1;
      break;
    case STATUS.EXPIRED:
      if (offers === 0) bucket.expiredWithoutOffer += 1;
      break;
    default:
      break;
  }

  // Қабул қилинган таклиф — статусдан ЭМАС, тайинловдан.
  //
  // Сабаб: талаб `accepted`дан `in_progress` ва `completed`га ўтади,
  // шунинг учун статус бўйича санаш «қабул қилинган» сонини
  // йўқотиб юборарди.
  if (demand.assignment && demand.assignment.providerId) {
    bucket.acceptedOffer += 1;
  }

  if ((demand.matching || {}).state === MATCHING_STATE.NO_PROVIDERS) {
    bucket.noProviders += 1;
  }

  // Push ҳисоби — `dispatchNotifications` ёзган хулоса.
  const push = stats.push || {};
  bucket.pushEligible += Number(push.eligible) || 0;
  bucket.pushSent += Number(push.sent) || 0;
  bucket.pushDigest += Number(push.digest) || 0;
  bucket.pushNoConsent += Number(push.noConsent) || 0;

  // Қаттиқ фильтр сабаблари.
  for (const [reason, n] of Object.entries(stats.rejectReasons || {})) {
    bucket.rejectReasons[reason] = (bucket.rejectReasons[reason] || 0) + (Number(n) || 0);
  }
}

/** Медиана — ўртача эмас: битта узоқ таклиф натижани бузмаслиги учун. */
function median(values) {
  if (!values || values.length === 0) return null;
  const s = [...values].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 === 0
    ? Math.round((s[mid - 1] + s[mid]) / 2)
    : s[mid];
}

function percentile(values, p) {
  if (!values || values.length === 0) return null;
  const s = [...values].sort((a, b) => a - b);
  const idx = Math.min(s.length - 1, Math.floor((p / 100) * s.length));
  return s[idx];
}

/**
 * Ҳисобни якунлайди — ёзишга тайёр ҳужжат.
 *
 * Нисбатлар ҲАМ ҳисобланади: эга саволлари «неча фоиз?» шаклида,
 * хом рақамлар эса жавоб бермайди.
 */
function finalize(bucket, meta) {
  const d = bucket.demandsCreated;
  const samples = bucket.timeToFirstOfferSamples;

  const ratio = (a, b) => (b > 0 ? Number((a / b).toFixed(4)) : null);

  return {
    ...meta,

    // ── Эга рўйхатидаги тўққизта ──────────────────────────────────────
    demandsCreated: d,
    providersMatched: bucket.providersMatched,
    pushEligible: bucket.pushEligible,
    offersReceived: bucket.offersReceived,
    timeToFirstOffer: {
      medianSec: median(samples),
      p90Sec: percentile(samples, 90),
      sampleCount: samples.length,
    },
    acceptedOffer: bucket.acceptedOffer,
    expiredWithoutOffer: bucket.expiredWithoutOffer,
    completedDemand: bucket.completedDemand,
    cancelledDemand: bucket.cancelledDemand,

    // ── Эга тўртта саволига жавоб ─────────────────────────────────────
    /** 1) matching тўғрими — мос топилганларнинг қанчаси таклиф берди. */
    precision: ratio(bucket.offersReceived, bucket.providersMatched),
    /** 1) талабларнинг қанчаси камида битта таклиф олди. */
    fillRate: ratio(bucket.demandsWithOffer, d),
    /** 2) номос provider — мос топилиб, таклиф бермаганлар. */
    matchedWithoutOffer: bucket.matchedWithoutOffer,
    rejectReasons: bucket.rejectReasons,
    /** 3) provider сони кам — умуман мос одам топилмаган талаблар улуши. */
    noProvidersRate: ratio(bucket.noProviders, d),
    noProviders: bucket.noProviders,
    /** 3) ўртача мос таклифчи сони. */
    avgProvidersPerDemand: ratio(bucket.providersMatched, d),
    /** 4) push спами — юборилганнинг улуши ва дайжестга тушгани. */
    pushSent: bucket.pushSent,
    pushDigest: bucket.pushDigest,
    pushNoConsent: bucket.pushNoConsent,
    pushSentRate: ratio(bucket.pushSent, bucket.pushEligible),
    /** Ўртача: битта талабга нечта push. */
    pushPerDemand: ratio(bucket.pushSent, d),

    updatedAt: new Date(),
  };
}

/** Ҳужжат калити: `{YYYY-MM-DD}_{module}_{regionId}`. */
function docKey(dateStr, module, regionId) {
  return `${dateStr}_${module}_${regionId || 'unknown'}`;
}

/**
 * Asia/Tashkent бўйича `YYYY-MM-DD`.
 *
 * Сервер UTC'да ишлайди. Кунлик кесим маҳаллий вақт бўйича бўлиши
 * керак — акс ҳолда «кечаги кун» 05:00да тугаб, ҳисоб аралашади.
 */
function tashkentDateStr(date) {
  const local = new Date(date.getTime() + 300 * 60 * 1000);
  const y = local.getUTCFullYear();
  const m = String(local.getUTCMonth() + 1).padStart(2, '0');
  const d = String(local.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

/** Маҳаллий кун бошланиши ва тугаши (UTC `Date` сифатида). */
function tashkentDayRange(dateStr) {
  const [y, m, d] = dateStr.split('-').map(Number);
  // Маҳаллий 00:00 = UTC 19:00 (олдинги кун).
  const startUtcMs = Date.UTC(y, m - 1, d, 0, 0, 0) - 300 * 60 * 1000;
  return {
    start: new Date(startUtcMs),
    end: new Date(startUtcMs + 24 * 3600 * 1000),
  };
}

module.exports = {
  COLLECTION,
  METRIC_NAMES,
  emptyBucket,
  addDemand,
  finalize,
  median,
  percentile,
  docKey,
  tashkentDateStr,
  tashkentDayRange,
};
