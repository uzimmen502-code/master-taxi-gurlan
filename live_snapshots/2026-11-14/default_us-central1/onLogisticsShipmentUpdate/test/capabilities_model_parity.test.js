/**
 * `functions/capabilities_model.js` — `functions_demand/core/capabilities.js`
 * nusxasi BAYT-MA-BAYT bir xilmi (7-qoida: bitta manba).
 *
 *   node functions/test/capabilities_model_parity.test.js
 *
 * Nega: taxi billing (default codebase) va capability API (demand
 * codebase) bir xil lifecycle mantiqini ishlatadi. Nusxa ajralib ketsa
 * «publish ruxsat berdi, sweeper esa to'xtatdi» holati paydo bo'ladi.
 * Tuzatish: node functions/tools/sync_capabilities_model.js
 */
const assert = require('assert');
const fs = require('fs');
const { DST, expected } = require('../tools/sync_capabilities_model');

let passed = 0;
try {
  assert.strictEqual(fs.readFileSync(DST, 'utf8'), expected(),
    'nusxa manbadan farq qiladi — sync_capabilities_model.js ni ishga tushiring');
  passed += 1;
  console.log('  OK  capabilities_model.js nusxasi manba bilan bir xil');
} catch (e) {
  console.error(`  XATO ${e.message}`);
  process.exitCode = 1;
}
console.log(`\n${passed} test o'tdi.`);
