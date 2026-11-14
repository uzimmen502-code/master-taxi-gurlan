/**
 * AVAGram лентаси — олдиндан тайёрланган JSON (Phase 3).
 *
 * НИМА УЧУН. Ҳозир лента ҳар очилганда Firestore'дан ўқилади ва сўров
 * ҚАЙТАРГАН ҲАР ҲУЖЖАТ учун битта read ҳисобланади — саҳифада 20 та.
 * Шу билан бирга лента МАЗМУНИ барча томошабин учун бир хил, яъни ҳар
 * киши бир хил нарсани қайта-қайта ўқийди.
 *
 * Ечим: сервер лентани даврий равишда тайёрлаб, R2'га JSON қилиб
 * ёзади, клиент эса уни CDN'дан олади. Лента учун Firestore read → 0,
 * кечикиш эса ~200 мс дан ~50 мс га тушади
 * (`docs/video-architecture/cost_model.py`).
 *
 * БУ ФАЙЛДА фақат СОФ қарорлар бор (қайси ҳовуз, қайси майдонлар,
 * саҳифалаш) — Firestore ҳам, R2 ҳам йўқ. Шунинг учун уни ташқи
 * хизматларсиз тестлаш мумкин: `test/tv_feed.test.js`.
 */
'use strict';

/** JSON схемаси версияси — йўлга киради, бузувчи ўзгаришда ошади. */
const FEED_VERSION = 'v1';

/** Бир саҳифадаги клип сони — клиентдаги `_pageSize` билан бир хил. */
const FEED_PAGE_SIZE = 20;

/** Бир ҳовузда сақланадиган энг кўп клип (эскилари лентада керак эмас). */
const FEED_MAX_CLIPS = 200;

/**
 * Таб → категориялар. Клиентдаги `_categoriesForTab` нинг жуфти
 * (`lib/features/tv_market/screens/tv_market_feed_screen.dart`).
 * `null` — фильтрсиз (AVAGram, ҳамма категория).
 */
const FEED_TABS = {
  all: null,
  news: ['news'],
  market: ['product', 'service', 'ad'],
};

/**
 * Лентага чиқадиган майдонлар. Клип ҳужжатида булардан кўп нарса бор
 * (`socialPost`, `playbackStats`, `processedVideoUrl`, `variantRun` …) —
 * улар лентага КЕРАК ЭМАС ва JSON'ни бекорга катта қиларди.
 */
const FEED_FIELDS = [
  'videoUrl', 'hlsUrl', 'videoVariants', 'posterUrl',
  'title', 'price', 'category', 'status', 'processingStatus',
  'ownerPhone', 'ownerName', 'showPhone',
  'districtId', 'districtLabel', 'regionId', 'adScope', 'adTier',
  'viewCount', 'likeCount', 'commentCount',
];

/**
 * Ҳовуз йўли: `feed/v1/{districtId}/{tab}`.
 * @param {string} districtId туман id.
 * @param {string} tab [FEED_TABS] калити.
 * @return {string} R2 калит префикси.
 */
function feedPoolPrefix(districtId, tab) {
  return `feed/${FEED_VERSION}/${districtId}/${tab}`;
}

/**
 * @param {string} districtId туман id.
 * @param {string} tab таб калити.
 * @param {number} page 1 дан бошланади.
 * @return {string} саҳифа файлининг R2 калити.
 */
function feedPageKey(districtId, tab, page) {
  return `${feedPoolPrefix(districtId, tab)}/p${page}.json`;
}

/**
 * Клип ҳужжатини лента JSON'ига ўгиради.
 *
 * `createdAt` — Firestore Timestamp'и JSON'да йўқ, шунинг учун epoch
 * миллисекунд. Клиент уни ўқиганда `DateTime.fromMillisecondsSinceEpoch`
 * билан тиклайди.
 * @param {string} id ҳужжат id.
 * @param {object} data ҳужжат маълумоти.
 * @return {object} лентага ёзиладиган қисқартирилган объект.
 */
function clipToFeedJson(id, data) {
  const d = data || {};
  const out = {id};
  for (const f of FEED_FIELDS) {
    if (d[f] !== undefined && d[f] !== null) out[f] = d[f];
  }
  const t = d.createdAt;
  if (t && typeof t.toMillis === 'function') {
    out.createdAtMs = t.toMillis();
  } else if (t instanceof Date) {
    out.createdAtMs = t.getTime();
  }
  return out;
}

/**
 * Клип шу табга тушадими?
 * @param {object} clip клип маълумоти.
 * @param {Array|null} categories таб категориялари (`null` — ҳаммаси).
 * @return {boolean}
 */
function clipMatchesTab(clip, categories) {
  if (!categories) return true;
  return categories.includes(String((clip || {}).category || ''));
}

/**
 * Лентага чиқариладими?
 *
 * `processingStatus === 'error'` — transcode йиқилган клип; клиентдаги
 * `TvClip.isPlayable` ҳам айнан шуни чиқариб ташлайди. Майдон умуман
 * йўқ бўлса (эски клиплар) — чиқарилади.
 * @param {object} clip клип маълумоти.
 * @return {boolean}
 */
function isFeedPlayable(clip) {
  return String((clip || {}).processingStatus || '') !== 'error';
}

/**
 * Клипларни саҳифаларга бўлади.
 * @param {Array} clips тартибланган клиплар (JSON шаклида).
 * @param {object} meta `{districtId, tab, builtAtMs}`.
 * @param {number} perPage саҳифа ҳажми.
 * @return {Array<object>} ҳар бири ёзиладиган саҳифа объекти.
 */
function buildFeedPages(clips, meta, perPage = FEED_PAGE_SIZE) {
  const list = clips.slice(0, FEED_MAX_CLIPS);
  const pages = Math.max(1, Math.ceil(list.length / perPage));
  const out = [];
  for (let i = 0; i < pages; i++) {
    out.push({
      v: FEED_VERSION,
      districtId: meta.districtId,
      tab: meta.tab,
      page: i + 1,
      pages,
      total: list.length,
      builtAtMs: meta.builtAtMs,
      clips: list.slice(i * perPage, (i + 1) * perPage),
    });
  }
  return out;
}

module.exports = {
  FEED_VERSION,
  FEED_PAGE_SIZE,
  FEED_MAX_CLIPS,
  FEED_TABS,
  FEED_FIELDS,
  feedPoolPrefix,
  feedPageKey,
  clipToFeedJson,
  clipMatchesTab,
  isFeedPlayable,
  buildFeedPages,
};
