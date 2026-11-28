/**
 * `functions/money_math.js` (MANBA — pul yaxlitlash, T-4) → `functions_demand/core/money_math.js`
 * nusxasini yangilaydi (sarlavha + manba, bayt-ma-bayt).
 *
 *   node functions/tools/sync_money_math.js
 *
 * Nima uchun nusxa: Firebase deploy faqat o'z codebase papkasini yuklaydi; demand codebase
 * (Ulgurji `avaFeeOf`) ham AYNAN shu yaxlitlash qoidasini ishlatishi kerak (CLAUDE.md 7).
 * `sync_logistics_tariff.js` / `sync_module_gate.js` dagi kabi nusxa + paritet testi:
 * functions/test/money_math_parity.test.js. Nusxani QO'LDA TAHRIRLAMANG.
 */
const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '..', 'money_math.js');
const DST = path.join(__dirname, '..', '..', 'functions_demand', 'core', 'money_math.js');

const HEADER = [
  "/* NUSXA — manba: functions/money_math.js. QO'LDA TAHRIRLANMAYDI.",
  ' * Firebase deploy faqat o\'z codebase papkasini yuklaydi, shuning uchun demand',
  ' * codebase uchun nusxa kerak. Paritet: functions/test/money_math_parity.test.js.',
  ' * Yangilash: node functions/tools/sync_money_math.js */',
  '',
].join('\n');

/** CRLF/LF farqi (git autocrlf) paritetni buzmasin — LF ga keltiriladi. */
function normalize(s) {
  return String(s).replace(/\r\n/g, '\n');
}

function expected() {
  return HEADER + normalize(fs.readFileSync(SRC, 'utf8'));
}

if (require.main === module) {
  fs.writeFileSync(DST, expected(), 'utf8');
  console.log(`yangilandi: ${DST}`);
}

module.exports = { SRC, DST, HEADER, expected, normalize };
