/**
 * Onlayn bozor e'loni rasmlari: 1..7 (ega qarori, 2026-10-17; avval 1..5).
 * `submitMarketAd` shu qoidadan foydalanadi (functions/market_images.js).
 *
 *   node functions/test/market_images.test.js
 */
'use strict';
const assert = require('assert');
const { marketImageUrlsOk, MARKET_MIN_IMAGES, MARKET_MAX_IMAGES } = require('../market_images');

const MARKERS = ['ads/998901112233/', 'ads%2F998901112233%2F'];
const url = (i, marker = 'ads/998901112233/') => `https://storage.example.test/o/${marker}img_${i}.jpg`;
const urls = (n) => Array.from({ length: n }, (_, i) => url(i));

let failed = 0;
function t(name, fn) {
  try { fn(); console.log(`PASS - ${name}`); } catch (e) { failed++; console.log(`FAIL - ${name} :: ${e.message}`); }
}

t('chegara qiymatlari 1 va 7', () => {
  assert.strictEqual(MARKET_MIN_IMAGES, 1);
  assert.strictEqual(MARKET_MAX_IMAGES, 7);
});
t('1 ta rasm — o\'tadi', () => assert.strictEqual(marketImageUrlsOk(urls(1), MARKERS), true));
t('5 ta rasm (eski ilova) — o\'tadi (orqaga moslik)', () => assert.strictEqual(marketImageUrlsOk(urls(5), MARKERS), true));
t('6 ta rasm — o\'tadi', () => assert.strictEqual(marketImageUrlsOk(urls(6), MARKERS), true));
t('7 ta rasm (chegara) — o\'tadi', () => assert.strictEqual(marketImageUrlsOk(urls(7), MARKERS), true));
t('8 ta rasm — rad', () => assert.strictEqual(marketImageUrlsOk(urls(8), MARKERS), false));
t('0 ta rasm — rad', () => assert.strictEqual(marketImageUrlsOk([], MARKERS), false));
t('massiv emas (satr / null / obyekt) — rad', () => {
  assert.strictEqual(marketImageUrlsOk('https://x', MARKERS), false);
  assert.strictEqual(marketImageUrlsOk(null, MARKERS), false);
  assert.strictEqual(marketImageUrlsOk({ 0: url(0) }, MARKERS), false);
});
t('boshqa foydalanuvchi yo\'lidagi rasm — rad (bitta bo\'lsa ham)', () => {
  const list = [...urls(6), url(9, 'ads/998909998877/')];
  assert.strictEqual(marketImageUrlsOk(list, MARKERS), false);
});
t('encoded yo\'l (ads%2F...%2F) — o\'tadi', () => {
  const list = [url(1, 'ads%2F998901112233%2F')];
  assert.strictEqual(marketImageUrlsOk(list, MARKERS), true);
});
t('http (https emas) va juda uzun URL — rad', () => {
  assert.strictEqual(marketImageUrlsOk(['http://storage.example.test/o/ads/998901112233/a.jpg'], MARKERS), false);
  assert.strictEqual(marketImageUrlsOk([`https://s.test/ads/998901112233/${'a'.repeat(2001)}`], MARKERS), false);
});

console.log(failed ? `\n${failed} FAILED` : '\nall passed');
process.exit(failed ? 1 : 0);
