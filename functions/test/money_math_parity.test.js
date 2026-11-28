/**
 * `functions_demand/core/money_math.js` — `functions/money_math.js` nusxasi BAYT-MA-BAYT
 * bir xilmi (7-qoida: bitta manba; CRLF/LF farqi hisobga olinmaydi).
 *
 *   node functions/test/money_math_parity.test.js
 *
 * Tuzatish: node functions/tools/sync_money_math.js
 */
const assert = require('assert');
const fs = require('fs');
const { DST, expected, normalize } = require('../tools/sync_money_math');

let passed = 0;
try {
  assert.strictEqual(normalize(fs.readFileSync(DST, 'utf8')), expected(),
    'nusxa manbadan farq qiladi — sync_money_math.js ni ishga tushiring');
  passed += 1;
  console.log('  OK  functions_demand/core/money_math.js nusxasi manba bilan bir xil');
} catch (e) {
  console.error(`  XATO ${e.message}`);
  process.exitCode = 1;
}
console.log(`\n${passed} test o'tdi.`);
