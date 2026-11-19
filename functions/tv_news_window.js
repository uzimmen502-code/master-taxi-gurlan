/**
 * «Кун янгиликлари» 24 соатлик ойнаси — СОФ қоидалар (Firestore йўқ).
 *
 * ЭГА ҚАРОРИ 2026-11-19 (AVAGram, 3 таб: all / news / market):
 *   a) Янгилик (`category == 'news'`) 24 соат яшайди (аввал 48).
 *   b) Бошқа занжир клиплари — `product`/`service` (ресторан, таом,
 *      кўчмас мулк ва ҳ.к. боғланганлари ҳам шу категорияларда) —
 *      фаоллашгандан кейинги 24 соат ФАҚАТ «Кун янгиликлари»да, кейин
 *      фақат AVAGram'да. Пуллик реклама (`ad`) бу қоидага кирмайди.
 *      «Реклама ва Эълонлар» (market) — ФАҚАТ пуллик реклама; органик клип у ерда ҳеч қачон йўқ.
 *   c) 24 соат ФАОЛЛАШУВДАН (модерация тасдиғи ёки авто-тасдиқ) —
 *      `activatedAt`, уни фақат сервер ёзади (`onTvClipSocialPublish`).
 *
 * ЭСКИ ҲУЖЖАТЛАР (`activatedAt` йўқ) — «эски» ҳисобланади: AVAGram'да
 * қолади, «Кун янгиликлари»га тушмайди. Сабаб: «янги» сўрови
 * `activatedAt` индекси бўйича ишлайди ва майдони йўқ ҳужжатни
 * қайтармайди — `createdAt`га қайтиш клипни иккала табдан ҳам
 * йўқотарди. Янгилик муддати учун эса `activatedAt ?? createdAt`
 * (эски янгилик ҳам 24 соатда тугайди).
 *
 * Клиент жуфти: `lib/features/tv_market/utils/tv_news_window.dart`.
 * Тест: `test/tv_news_window.test.js`.
 */
'use strict';

/** Ойна — 24 соат. */
const TV_NEWS_WINDOW_MS = 24 * 60 * 60 * 1000;

/** «Янги» бўлиши мумкин бўлган категориялар (news ва ad эмас). */
const TV_FRESH_CATEGORIES = ['product', 'service'];

/**
 * Вақт → epoch мс. Firestore Timestamp, Date ёки сон (CDN JSON).
 * @param {*} t қиймат.
 * @return {number|null} мс ёки `null` (йўқ/бузуқ).
 */
function timeMillis(t) {
  if (t === null || t === undefined) return null;
  if (typeof t === 'number') return Number.isFinite(t) && t > 0 ? t : null;
  if (t instanceof Date) {
    const ms = t.getTime();
    return Number.isFinite(ms) && ms > 0 ? ms : null;
  }
  if (typeof t.toMillis === 'function') {
    const ms = t.toMillis();
    return Number.isFinite(ms) && ms > 0 ? ms : null;
  }
  return null;
}

/**
 * @param {object} clip клип (Firestore маълумоти ёки CDN JSON).
 * @return {number|null} фаоллашув вақти мс.
 */
function clipActivatedMs(clip) {
  const d = clip || {};
  return timeMillis(d.activatedAt) ?? timeMillis(d.activatedAtMs);
}

/**
 * Лентада «чиққан вақт»: фаоллашув, бўлмаса яратилиш.
 * @param {object} clip клип.
 * @return {number|null} мс.
 */
function clipShownAtMs(clip) {
  const d = clip || {};
  return clipActivatedMs(d) ?? timeMillis(d.createdAt) ?? timeMillis(d.createdAtMs);
}

/**
 * Фаоллашгандан кейинги 24 соат ичидаги товар/хизмат клипи.
 * Чегара: роппа-роса 24:00 — энди эски.
 * @param {object} clip клип.
 * @param {number} nowMs ҳозирги вақт.
 * @return {boolean}
 */
function isFreshNonNews(clip, nowMs) {
  const d = clip || {};
  if (String(d.status || 'active') !== 'active') return false;
  if (!TV_FRESH_CATEGORIES.includes(String(d.category || ''))) return false;
  const at = clipActivatedMs(d);
  if (at === null) return false;
  return nowMs - at < TV_NEWS_WINDOW_MS;
}

/**
 * Янгилик муддати тугадими (`activatedAt ?? createdAt` + 24 соат).
 * @param {object} clip клип.
 * @param {number} nowMs ҳозирги вақт.
 * @return {boolean}
 */
function isNewsExpired(clip, nowMs) {
  const d = clip || {};
  if (String(d.category || '') !== 'news') return false;
  const at = clipActivatedMs(d) ?? timeMillis(d.createdAt);
  if (at === null) return false;
  return nowMs - at >= TV_NEWS_WINDOW_MS;
}

/**
 * Клип шу табга тушадими (`tv_feed.js` FEED_TABS калитлари).
 *   all    — ҳамма, ЯНГИ товар/хизматдан ташқари;
 *   news   — янгилик + янги товар/хизмат;
 *   market — фақат пуллик реклама `ad` (эга 2026-11-19).
 * @param {object} clip клип.
 * @param {string} tab таб калити.
 * @param {number} nowMs ҳозирги вақт.
 * @return {boolean}
 */
function clipInFeedTab(clip, tab, nowMs) {
  const d = clip || {};
  const cat = String(d.category || '');
  switch (tab) {
    case 'all':
      return !isFreshNonNews(d, nowMs);
    case 'news':
      return cat === 'news' || isFreshNonNews(d, nowMs);
    case 'market':
      // Эга 2026-11-19 (3-жавоб): бу таб — ФАҚАТ пуллик реклама (`ad`); органик товар/хизмат
      // ҳеч қачон бу ерда эмас (24 соат «Кун янгиликлари»да, кейин AVAGram'да).
      return cat === 'ad';
    default:
      return false;
  }
}

/**
 * Ҳужжат ҳозиргина `active` бўлдими (яратилиш ҳам).
 * @param {object|null} before олдинги маълумот (`null` — йўқ эди).
 * @param {object|null} after кейинги маълумот (`null` — ўчирилди).
 * @return {boolean}
 */
function becameActive(before, after) {
  if (!after) return false;
  return after.status === 'active' && (!before || before.status !== 'active');
}

/**
 * Транзакция ичида: `activatedAt`ни ҳодиса вақтига ёзиш керакми.
 * Такрорий чақирув (retry) айнан шу қийматни топади → ёзмайди; кейинроқ
 * бўлган фаоллашув ёзилган бўлса — эски ҳодиса уни босмайди.
 * @param {object|null} current ҳозирги ҳужжат маълумоти.
 * @param {number|null} eventMs фаоллашган ёзувнинг `updateTime` мс.
 * @return {boolean}
 */
function shouldStampActivation(current, eventMs) {
  if (!current || current.status !== 'active') return false;
  if (!Number.isFinite(eventMs) || eventMs <= 0) return false;
  const have = clipActivatedMs(current);
  return have === null || have < eventMs;
}

module.exports = {
  TV_NEWS_WINDOW_MS,
  TV_FRESH_CATEGORIES,
  timeMillis,
  clipActivatedMs,
  clipShownAtMs,
  isFreshNonNews,
  isNewsExpired,
  clipInFeedTab,
  becameActive,
  shouldStampActivation,
};
