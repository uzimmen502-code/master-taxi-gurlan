/**
 * «Кун янгиликлари» 24 соатлик ойнаси — СОФ қоидалар (`functions/tv_news_window.js`).
 * Эга қарори 2026-11-19: янгилик 24 соат яшайди; бошқа занжир клиплари
 * (товар/хизмат, реклама эмас) фаоллашгандан кейинги 24 соат фақат
 * «Кун янгиликлари»да, кейин AVAGram'да. Ҳисоб `activatedAt`дан.
 *
 * Ишлатиш (functions/ ичидан):
 *   npm run test:tv-news-window
 */
'use strict';
const {
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
} = require('../tv_news_window');

const results = [];
function check(name, pass) {
  results.push({name, pass});
  console.log(`${pass ? '  ok  ' : ' FAIL '} ${name}`);
}

const H = 60 * 60 * 1000;
const M = 60 * 1000;
const NOW = Date.UTC(2026, 10, 19, 12, 0, 0);
const ts = (ms) => ({toMillis: () => ms});

function testWindow() {
  check('ойна 24 соат', TV_NEWS_WINDOW_MS === 24 * H);
  check('янги категориялар = product, service',
      JSON.stringify(TV_FRESH_CATEGORIES) === '["product","service"]');
}

function testTimeMillis() {
  check('Timestamp', timeMillis(ts(5)) === 5);
  check('Date', timeMillis(new Date(7)) === 7);
  check('сон (JSON ms)', timeMillis(9) === 9);
  check('йўқ/бузуқ → null',
      timeMillis(undefined) === null && timeMillis('x') === null &&
      timeMillis(0) === null && timeMillis({}) === null);
  check('activatedAtMs (CDN JSON) ҳам ўқилади',
      clipActivatedMs({activatedAtMs: 11}) === 11);
  check('shownAt: activatedAt бор бўлса — у',
      clipShownAtMs({createdAt: ts(1), activatedAt: ts(2)}) === 2);
  check('shownAt: activatedAt йўқ — createdAt',
      clipShownAtMs({createdAt: ts(1)}) === 1);
}

function testFresh() {
  const p = (ageMs, extra = {}) => ({
    category: 'product', status: 'active', activatedAt: ts(NOW - ageMs), ...extra,
  });
  check('P1 товар 23:59 — янги', isFreshNonNews(p(24 * H - M), NOW) === true);
  check('P2 хизмат 1 соат — янги',
      isFreshNonNews(p(H, {category: 'service'}), NOW) === true);
  check('B1 роппа-роса 24:00 — эски', isFreshNonNews(p(24 * H), NOW) === false);
  check('B2 24:01 — эски', isFreshNonNews(p(24 * H + M), NOW) === false);
  check('N1 реклама (ad) ҳеч қачон янги эмас',
      isFreshNonNews(p(H, {category: 'ad'}), NOW) === false);
  check('N2 янгилик (news) бу рўйхатда эмас',
      isFreshNonNews(p(H, {category: 'news'}), NOW) === false);
  check('N3 activatedAt йўқ (эски ҳужжат) — эски',
      isFreshNonNews({category: 'product', status: 'active', createdAt: ts(NOW - H)},
          NOW) === false);
  check('N4 нотаниш категория — янги эмас (AVAGram)',
      isFreshNonNews(p(H, {category: 'xyz'}), NOW) === false);
  check('N5 фаол эмас — янги эмас',
      isFreshNonNews(p(H, {status: 'pending'}), NOW) === false);
  check('B3 келажакдаги вақт (соат фарқи) — янги',
      isFreshNonNews(p(-5 * M), NOW) === true);
}

function testNewsExpiry() {
  const n = (createdAge, activatedAge) => ({
    category: 'news', status: 'active',
    createdAt: ts(NOW - createdAge),
    ...(activatedAge === undefined ? {} : {activatedAt: ts(NOW - activatedAge)}),
  });
  check('E1 янгилик 23:59 (activatedAt) — тирик',
      isNewsExpired(n(30 * H, 24 * H - M), NOW) === false);
  check('E2 янгилик 24:00 — тугади', isNewsExpired(n(30 * H, 24 * H), NOW) === true);
  check('E3 эски ҳужжат: createdAt 24:01 — тугади',
      isNewsExpired(n(24 * H + M), NOW) === true);
  check('E4 эски ҳужжат: createdAt 23:00 — тирик',
      isNewsExpired(n(23 * H), NOW) === false);
  check('E5 модерацияда 30 соат турди, 1 соат олдин тасдиқланди — тирик',
      isNewsExpired(n(31 * H, H), NOW) === false);
  check('E6 товар — бу функцияга тегишли эмас',
      isNewsExpired({...n(30 * H, 30 * H), category: 'product'}, NOW) === false);
  check('E7 вақт умуман йўқ — тугатилмайди (маълумот йўқ)',
      isNewsExpired({category: 'news', status: 'active'}, NOW) === false);
}

function testTabs() {
  const fresh = {category: 'product', status: 'active', activatedAt: ts(NOW - H)};
  const old = {category: 'product', status: 'active', activatedAt: ts(NOW - 25 * H)};
  const legacy = {category: 'service', status: 'active', createdAt: ts(NOW - H)};
  const news = {category: 'news', status: 'active', activatedAt: ts(NOW - H)};
  const ad = {category: 'ad', status: 'active', activatedAt: ts(NOW - H)};
  check('T1 all: янги товар ЙЎҚ', clipInFeedTab(fresh, 'all', NOW) === false);
  check('T2 all: эски товар бор', clipInFeedTab(old, 'all', NOW) === true);
  check('T3 all: activatedAt йўқ — бор', clipInFeedTab(legacy, 'all', NOW) === true);
  check('T4 all: янгилик ва реклама бор (ўзгармаган)',
      clipInFeedTab(news, 'all', NOW) && clipInFeedTab(ad, 'all', NOW));
  check('T5 news: янгилик + янги товар',
      clipInFeedTab(news, 'news', NOW) && clipInFeedTab(fresh, 'news', NOW));
  check('T6 news: эски товар, реклама, activatedAt йўқ — йўқ',
      !clipInFeedTab(old, 'news', NOW) && !clipInFeedTab(ad, 'news', NOW) &&
      !clipInFeedTab(legacy, 'news', NOW));
  check('T7 market: ўзгармаган (товар/хизмат/реклама, янгисиям)',
      clipInFeedTab(fresh, 'market', NOW) && clipInFeedTab(old, 'market', NOW) &&
      clipInFeedTab(ad, 'market', NOW) && !clipInFeedTab(news, 'market', NOW));
  check('T8 нотаниш таб — false', clipInFeedTab(old, 'zzz', NOW) === false);
}

function testStamp() {
  check('S1 яратилди active', becameActive(null, {status: 'active'}) === true);
  check('S2 pending → active', becameActive({status: 'pending'}, {status: 'active'}) === true);
  check('S3 active → active — йўқ', becameActive({status: 'active'}, {status: 'active'}) === false);
  check('S4 яратилди pending — йўқ', becameActive(null, {status: 'pending'}) === false);
  check('S5 ўчирилди — йўқ', becameActive({status: 'active'}, null) === false);
  check('S6 blocked → active — ҳа', becameActive({status: 'blocked'}, {status: 'active'}) === true);
  const ev = NOW;
  check('S7 ҳали йўқ — ёзилади', shouldStampActivation({status: 'active'}, ev) === true);
  check('S8 айнан шу вақт ёзилган (retry) — ёзилмайди',
      shouldStampActivation({status: 'active', activatedAt: ts(ev)}, ev) === false);
  check('S9 кейинги фаоллашув ёзилган — эски ҳодиса устидан ёзмайди',
      shouldStampActivation({status: 'active', activatedAt: ts(ev + 5000)}, ev) === false);
  check('S10 олдинги фаоллашув эскироқ — янгиланади',
      shouldStampActivation({status: 'active', activatedAt: ts(ev - 3 * H)}, ev) === true);
  check('S11 ҳозир active эмас — ёзилмайди',
      shouldStampActivation({status: 'pending'}, ev) === false);
  check('S12 ҳужжат йўқ — ёзилмайди', shouldStampActivation(null, ev) === false);
  check('S13 ҳодиса вақти йўқ — ёзилмайди',
      shouldStampActivation({status: 'active'}, null) === false);
}

testWindow();
testTimeMillis();
testFresh();
testNewsExpiry();
testTabs();
testStamp();

const failed = results.filter((r) => !r.pass).length;
console.log(`\n${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
