/**
 * Lenta JSON builderining SOF qismi — `functions/tv_feed.js`.
 * Firestore ham, R2 ham kerak emas.
 *
 * Ishlatish (functions/ ichidan):
 *   npm run test:tv-feed
 */
'use strict';
const {
  FEED_PAGE_SIZE,
  FEED_MAX_CLIPS,
  FEED_TABS,
  feedPoolPrefix,
  feedPageKey,
  clipToFeedJson,
  clipMatchesTab,
  isFeedPlayable,
  buildFeedPages,
} = require('../tv_feed');

const results = [];
function check(name, pass) {
  results.push({name, pass});
  console.log(`${pass ? '  ok  ' : ' FAIL '} ${name}`);
}

function testKeys() {
  check('prefiks shakli',
      feedPoolPrefix('gurlan', 'all') === 'feed/v1/gurlan/all');
  check('sahifa kaliti',
      feedPageKey('gurlan', 'news', 3) === 'feed/v1/gurlan/news/p3.json');
  check('versiya yo‘lda bor',
      feedPageKey('x', 'all', 1).startsWith('feed/v1/'));
}

function testTabs() {
  const clip = (c) => ({category: c});
  check('all tabi hamma kategoriyani oladi',
      clipMatchesTab(clip('product'), FEED_TABS.all) &&
      clipMatchesTab(clip('news'), FEED_TABS.all) &&
      clipMatchesTab(clip('ad'), FEED_TABS.all));
  check('news tabi faqat news',
      clipMatchesTab(clip('news'), FEED_TABS.news) &&
      !clipMatchesTab(clip('product'), FEED_TABS.news));
  check('market tabi product/service/ad',
      clipMatchesTab(clip('product'), FEED_TABS.market) &&
      clipMatchesTab(clip('service'), FEED_TABS.market) &&
      clipMatchesTab(clip('ad'), FEED_TABS.market) &&
      !clipMatchesTab(clip('news'), FEED_TABS.market));
  check('kategoriyasiz klip market tabiga tushmaydi',
      !clipMatchesTab({}, FEED_TABS.market));
}

function testPlayable() {
  check('error — lentaga chiqmaydi',
      !isFeedPlayable({processingStatus: 'error'}));
  check('ready — chiqadi', isFeedPlayable({processingStatus: 'ready'}));
  check('processing — chiqadi (muqova ko‘rinadi)',
      isFeedPlayable({processingStatus: 'processing'}));
  check('maydon yo‘q (eski klip) — chiqadi', isFeedPlayable({}));
}

function testLean() {
  const ts = {toMillis: () => 1700000000000};
  const full = {
    videoUrl: 'v', hlsUrl: 'h', posterUrl: 'p', title: 't',
    category: 'product', ownerPhone: '998', viewCount: 5,
    createdAt: ts,
    // Lentaga KERAK EMAS:
    playbackStats: {views: 999}, socialPost: {status: 'posted'},
    processedVideoUrl: 'x', variantRun: 'r1', backfillVariantsAt: ts,
  };
  const lean = clipToFeedJson('abc', full);
  check('id qo‘shiladi', lean.id === 'abc');
  check('kerakli maydonlar bor',
      lean.videoUrl === 'v' && lean.title === 't' && lean.viewCount === 5);
  check('createdAt -> createdAtMs', lean.createdAtMs === 1700000000000);
  check('ortiqcha maydonlar TASHLANADI',
      lean.playbackStats === undefined &&
      lean.socialPost === undefined &&
      lean.processedVideoUrl === undefined &&
      lean.variantRun === undefined);
  check('null/undefined maydon yozilmaydi',
      clipToFeedJson('x', {title: null, videoUrl: undefined}).title ===
          undefined);
  check('Date ham qabul qilinadi',
      clipToFeedJson('x', {createdAt: new Date(5)}).createdAtMs === 5);
}

function testPages() {
  const clips = Array.from({length: 45}, (_, i) => ({id: `c${i}`}));
  const pages = buildFeedPages(clips, {
    districtId: 'gurlan', tab: 'all', builtAtMs: 1,
  });
  check('45 klip -> 3 sahifa', pages.length === 3);
  check('sahifa hajmi', pages[0].clips.length === FEED_PAGE_SIZE &&
      pages[1].clips.length === FEED_PAGE_SIZE &&
      pages[2].clips.length === 5);
  check('har sahifada pages/total bor',
      pages.every((p) => p.pages === 3 && p.total === 45));
  check('tartib saqlanadi',
      pages[0].clips[0].id === 'c0' && pages[2].clips[4].id === 'c44');
  check('meta sahifada bor',
      pages[0].districtId === 'gurlan' && pages[0].tab === 'all' &&
      pages[0].builtAtMs === 1 && pages[0].v === 'v1');

  const one = buildFeedPages([{id: 'a'}], {districtId: 'd', tab: 'all',
    builtAtMs: 1});
  check('1 klip -> 1 sahifa', one.length === 1 && one[0].pages === 1);

  const none = buildFeedPages([], {districtId: 'd', tab: 'all', builtAtMs: 1});
  check('0 klip -> 1 bo‘sh sahifa (klient 404 olmasin)',
      none.length === 1 && none[0].clips.length === 0 && none[0].total === 0);

  const many = buildFeedPages(
      Array.from({length: FEED_MAX_CLIPS + 50}, (_, i) => ({id: `c${i}`})),
      {districtId: 'd', tab: 'all', builtAtMs: 1});
  const count = many.reduce((s, p) => s + p.clips.length, 0);
  check(`${FEED_MAX_CLIPS} tadan oshmaydi`, count === FEED_MAX_CLIPS);
}

function main() {
  testKeys();
  testTabs();
  testPlayable();
  testLean();
  testPages();
  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} passed`);
  process.exit(failed.length ? 1 : 0);
}

main();
