/**
 * `functions/module_gate.js` → `functions_demand/core/module_gate.js` nusxasini yangilaydi
 * (sarlavha + manba, bayt-ma-bayt).
 *
 *   node functions/tools/sync_module_gate.js
 *
 * Paritet testi: functions/test/module_gate_parity.test.js
 */
const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '..', 'module_gate.js');
const DST = path.join(__dirname, '..', '..', 'functions_demand', 'core', 'module_gate.js');

const HEADER = [
  "/* NUSXA — manba: functions/module_gate.js. QO'LDA TAHRIRLANMAYDI.",
  " * Firebase deploy faqat o'z codebase papkasini yuklaydi, shuning uchun",
  ' * demand codebase (requestCapability: courier) uchun nusxa kerak. Paritet:',
  ' * functions/test/module_gate_parity.test.js (bayt-ma-bayt).',
  ' * Yangilash: node functions/tools/sync_module_gate.js */',
  '',
].join('\n');

function expected() {
  return HEADER + fs.readFileSync(SRC, 'utf8');
}

if (require.main === module) {
  fs.writeFileSync(DST, expected(), 'utf8');
  console.log(`yangilandi: ${DST}`);
}

module.exports = { SRC, DST, HEADER, expected };
