/**
 * 13.1.2 — `functions/geo_hash.js` yadro nusxasi bilan bir xil ekanini qulflaydi.
 *
 *   npm --prefix functions run test:geo-parity
 *
 * Nega kerak: yadro alohida codebase'da (`functions_demand/geo/geo_hash.js`)
 * ayni shu algoritmning NUSXASINI ishlatadi (deploy faqat o'z papkasini
 * yuklaydi). Nusxalar ajralib ketsa, matching serverda bir katakni, EV/realty
 * kodi boshqasini hisoblaydi — buni hech kim sezmaydi, hisob jimgina buziladi.
 *
 * Fixture manbasi: `functions_demand/test/fixtures/geohash_vectors.json`.
 * Emulator kerak emas — sof funksiya.
 */
const assert = require('assert');
const path = require('path');
const fs = require('fs');

const gh = require('../geo_hash');

let passed = 0;
function ok(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`  OK  ${name}`);
  } catch (e) {
    console.error(`  XATO ${name}\n       ${e.message}`);
    process.exitCode = 1;
  }
}

const fixturePath = path.join(
  __dirname, '..', '..', 'functions_demand', 'test', 'fixtures', 'geohash_vectors.json',
);

console.log('geohash fixture pariteti');

if (!fs.existsSync(fixturePath)) {
  console.error(`  XATO fixture topilmadi: ${fixturePath}`);
  process.exitCode = 1;
} else {
  const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
  for (const v of fixture.vectors) {
    ok(`${v.name} -> ${v.geohash}`, () => {
      assert.strictEqual(gh.encode(v.lat, v.lng, v.precision), v.geohash);
    });
  }

  ok('yadro nusxasi bilan bit-babit bir xil (200 tasodifiy nuqta)', () => {
    const core = require('../../functions_demand/geo/geo_hash');
    for (let i = 0; i < 200; i += 1) {
      const lat = (Math.random() * 180) - 90;
      const lng = (Math.random() * 360) - 180;
      const p = 1 + Math.floor(Math.random() * 8);
      assert.strictEqual(gh.encode(lat, lng, p), core.encode(lat, lng, p));
    }
  });

  ok('BASE32 alifbosi bir xil', () => {
    const core = require('../../functions_demand/geo/geo_hash');
    assert.strictEqual(gh.BASE32, core.BASE32);
  });
}

console.log(`\n${passed} test o'tdi.`);
