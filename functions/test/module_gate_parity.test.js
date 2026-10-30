/**
 * `functions/module_gate.js` — `functions_demand/core/module_gate.js` nusxasi
 * BAYT-MA-BAYT bir xilmi (7-qoida: bitta manba).
 *
 *   node functions/test/module_gate_parity.test.js
 *
 * Tuzatish: node functions/tools/sync_module_gate.js
 */
const assert = require('assert');
const fs = require('fs');
const { DST, expected } = require('../tools/sync_module_gate');

let passed = 0;
try {
  assert.strictEqual(fs.readFileSync(DST, 'utf8'), expected(),
    'nusxa manbadan farq qiladi — sync_module_gate.js ni ishga tushiring');
  passed += 1;
  console.log('  OK  module_gate.js nusxasi manba bilan bir xil');
} catch (e) {
  console.error(`  XATO ${e.message}`);
  process.exitCode = 1;
}
console.log(`\n${passed} test o'tdi.`);
