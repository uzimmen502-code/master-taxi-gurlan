/**
 * `tv_clip_media_path.js` — соф (Firestore/Storage керак эмас).
 *   node test/tv_clip_media_path.test.js
 */
'use strict';
const assert = require('assert');
const { tvClipOwnedStoragePath } = require('../tv_clip_media_path');

const u = (path) => `https://firebasestorage.googleapis.com/v0/b/master-taxi-gurlan.firebasestorage.app/o/${encodeURIComponent(path)}?alt=media&token=x`;

// Позитив: эганинг папкаси (тўлиқ рақам, 9 рақам, + билан, қисқа синов ID).
assert.strictEqual(tvClipOwnedStoragePath(u('tv_clips/998901234567/a.mp4'), '998901234567'), 'tv_clips/998901234567/a.mp4');
assert.strictEqual(tvClipOwnedStoragePath(u('tv_clips/901234567/a.mp4'), '+998901234567'), 'tv_clips/901234567/a.mp4');
assert.strictEqual(tvClipOwnedStoragePath(u('tv_clips/+998901234567/p.jpg'), '998901234567'), 'tv_clips/+998901234567/p.jpg');
assert.strictEqual(tvClipOwnedStoragePath(u('tv_clips/55021/a.mp4'), '55021'), 'tv_clips/55021/a.mp4');
// Негатив: бошқа эга, бошқа папка, ичкари папка, йўл ўтиш, URL эмас, эга йўқ.
assert.strictEqual(tvClipOwnedStoragePath(u('tv_clips/998911111111/a.mp4'), '998901234567'), null);
assert.strictEqual(tvClipOwnedStoragePath(u('restaurant_images/x/menu.jpg'), '998901234567'), null);
assert.strictEqual(tvClipOwnedStoragePath(u('tv_clips/998901234567/sub/a.mp4'), '998901234567'), null);
assert.strictEqual(tvClipOwnedStoragePath(u('tv_clips/998901234567/../x.mp4'), '998901234567'), null);
assert.strictEqual(tvClipOwnedStoragePath('https://cdn.example.com/a.mp4', '998901234567'), null);
assert.strictEqual(tvClipOwnedStoragePath(u('tv_clips/998901234567/a.mp4'), ''), null);
// Чегара: қисқа ID фақат АЙНАН тенг бўлса (бошқа қисқа ID — йўқ).
assert.strictEqual(tvClipOwnedStoragePath(u('tv_clips/55022/a.mp4'), '55021'), null);
assert.strictEqual(tvClipOwnedStoragePath(u('tv_clips/998901234567/a.mp4'), null), null);
console.log('tv_clip_media_path: 12/12 OK');
