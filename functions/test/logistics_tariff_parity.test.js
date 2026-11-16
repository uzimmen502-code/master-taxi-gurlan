/**
 * `functions/logistics_tariff.js` — `functions_demand/core/tariff.js` nusxasi
 * BAYT-MA-BAYT bir xilmi (7-qoida: bitta manba; CRLF/LF farqi hisobga olinmaydi).
 *
 *   node functions/test/logistics_tariff_parity.test.js
 *
 * Tuzatish: node functions/tools/sync_logistics_tariff.js
 */
const assert = require('assert');
const fs = require('fs');
const { DST, expected, normalize } = require('../tools/sync_logistics_tariff');

let passed = 0;
try {
  assert.strictEqual(normalize(fs.readFileSync(DST, 'utf8')), expected(),
    'nusxa manbadan farq qiladi — sync_logistics_tariff.js ni ishga tushiring');
  passed += 1;
  console.log('  OK  logistics_tariff.js nusxasi manba bilan bir xil');
} catch (e) {
  console.error(`  XATO ${e.message}`);
  process.exitCode = 1;
}
console.log(`\n${passed} test o'tdi.`);
