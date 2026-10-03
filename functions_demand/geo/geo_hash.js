'use strict';

/**
 * 13.1.2 — `functions/geo_hash.js`ning AYNAN NUSXASI.
 *
 * Nega nusxa, nega `require('../functions/geo_hash')` emas: deploy paytida
 * faqat codebase manba papkasi yuklanadi, yondosh papka ketmaydi.
 *
 * Shuning uchun nusxa `test/fixtures/geohash_vectors.json` orqali qulflangan:
 * ayni shu fixture'ni (a) shu modul, (b) `functions/geo_hash.js`, va
 * (c) Dart'dagi `lib/utils/geo_hash.dart` tekshiradi. Uchtadan biri
 * o'zgarsa test sinadi — matching'da server bir katakni, ilova boshqasini
 * hisoblashi mumkin bo'lmaydi.
 */
const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

function encode(lat, lng, precision = 4) {
  let minLat = -90;
  let maxLat = 90;
  let minLng = -180;
  let maxLng = 180;
  let buf = '';
  let bit = 0;
  let ch = 0;
  let even = true;
  while (buf.length < precision) {
    if (even) {
      const mid = (minLng + maxLng) / 2;
      if (lng >= mid) { ch |= 1 << (4 - bit); minLng = mid; } else { maxLng = mid; }
    } else {
      const mid = (minLat + maxLat) / 2;
      if (lat >= mid) { ch |= 1 << (4 - bit); minLat = mid; } else { maxLat = mid; }
    }
    even = !even;
    bit += 1;
    if (bit === 5) { buf += BASE32[ch]; bit = 0; ch = 0; }
  }
  return buf;
}

function decodeBounds(hash) {
  let minLat = -90;
  let maxLat = 90;
  let minLng = -180;
  let maxLng = 180;
  let even = true;
  for (const ch of String(hash || '')) {
    const idx = BASE32.indexOf(ch);
    if (idx < 0) continue;
    for (let bit = 4; bit >= 0; bit -= 1) {
      const on = (idx >> bit) & 1;
      if (even) {
        const mid = (minLng + maxLng) / 2;
        if (on) minLng = mid; else maxLng = mid;
      } else {
        const mid = (minLat + maxLat) / 2;
        if (on) minLat = mid; else maxLat = mid;
      }
      even = !even;
    }
  }
  return { minLat, maxLat, minLng, maxLng };
}

function cellCenter(lat, lng, precision = 4) {
  const b = decodeBounds(encode(lat, lng, precision));
  return {
    lat: (b.minLat + b.maxLat) / 2,
    lng: (b.minLng + b.maxLng) / 2,
  };
}

module.exports = { encode, decodeBounds, cellCenter, BASE32 };
