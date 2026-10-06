/**
 * `functions_demand/core/capabilities.js` → `functions/capabilities_model.js`
 * nusxasini yangilaydi (sarlavha + manba, bayt-ma-bayt).
 *
 *   node functions/tools/sync_capabilities_model.js
 *
 * Paritet testi: functions/test/capabilities_model_parity.test.js
 */
const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '..', '..', 'functions_demand', 'core', 'capabilities.js');
const DST = path.join(__dirname, '..', 'capabilities_model.js');

const HEADER = [
  "/* NUSXA — manba: functions_demand/core/capabilities.js. QO'LDA TAHRIRLANMAYDI.",
  ' * Firebase deploy faqat o\'z codebase papkasini yuklaydi, shuning uchun ',
  ' * default codebase (taxi billing) uchun nusxa kerak. Paritet:',
  ' * functions/test/capabilities_model_parity.test.js (bayt-ma-bayt).',
  ' * Yangilash: node functions/tools/sync_capabilities_model.js */',
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
