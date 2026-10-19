/**
 * AVAGram klip davomiyligi chegarasi: taom videosi — 60 s, qolganlari — umumiy (D-REST-30).
 *
 *   node functions/test/tv_clip_limits.test.js
 *
 * Sof funksiya (emulator kerak emas). Klient jufti bilan moslikni `tv_clip_duration_limit_test.dart`
 * tekshiradi.
 */
'use strict';
const assert = require('assert');
const { TV_CLIP_ITEM_MAX_SECONDS, ITEM_LINK_KIND, tvClipMaxSecondsFor } = require('../tv_clip_limits');

const DEFAULT = 600;
let failed = 0;
function check(name, fn) {
  try { fn(); console.log(`PASS - ${name}`); } catch (e) { failed += 1; console.log(`FAIL - ${name} :: ${e.message}`); }
}

check('taom videosi (restaurant_item) — 60 soniya', () => {
  assert.strictEqual(TV_CLIP_ITEM_MAX_SECONDS, 60);
  assert.strictEqual(ITEM_LINK_KIND, 'restaurant_item');
  assert.strictEqual(tvClipMaxSecondsFor({ linkKind: 'restaurant_item', linkId: 'r1', linkItemId: 'osh' }, DEFAULT), 60);
});

check('boshqa turlar va bog\'lanmagan klip — umumiy chegara (eski klip buzilmaydi)', () => {
  for (const clip of [
    { linkKind: 'restaurant', linkId: 'r1' }, // restoran videosi — qisqartirilmaydi
    { linkKind: 'ad', linkId: 'a1' },
    { linkKind: 'market_ad' },
    { linkKind: 'wholesale_product' },
    { linkKind: '' },
    {},
    { category: 'news' },
  ]) {
    assert.strictEqual(tvClipMaxSecondsFor(clip, DEFAULT), DEFAULT, JSON.stringify(clip));
  }
});

check('hujjat yo\'q (o\'qib bo\'lmadi) — umumiy chegara, xato yo\'q', () => {
  assert.strictEqual(tvClipMaxSecondsFor(null, DEFAULT), DEFAULT);
  assert.strictEqual(tvClipMaxSecondsFor(undefined, DEFAULT), DEFAULT);
});

check('umumiy chegara parametr sifatida (index.js dagi TV_CLIP_MAX_SECONDS) o\'zgarsa, taom chegarasi o\'zgarmaydi', () => {
  assert.strictEqual(tvClipMaxSecondsFor({ linkKind: 'restaurant_item' }, 1200), 60);
  assert.strictEqual(tvClipMaxSecondsFor({ linkKind: 'ad' }, 1200), 1200);
});

check('tur nomi aniq mos: katta-kichik harf yoki kengaytma 60 s bermaydi', () => {
  for (const k of ['Restaurant_Item', 'restaurant_items', 'restaurant-item', ' restaurant_item']) {
    assert.strictEqual(tvClipMaxSecondsFor({ linkKind: k }, DEFAULT), DEFAULT, k);
  }
});

console.log(failed ? `\n${failed} ta yiqildi` : '\nhammasi o\'tdi');
process.exit(failed ? 1 : 0);
