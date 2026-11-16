/**
 * `functions_demand/core/tariff.js` (MANBA — AVA Logistics zona tarifi) → `functions/logistics_tariff.js`
 * nusxasini yangilaydi (sarlavha + manba, bayt-ma-bayt).
 *
 *   node functions/tools/sync_logistics_tariff.js
 *
 * Nima uchun nusxa: Firebase deploy faqat o'z codebase papkasini yuklaydi. «AVA AI — Ақлли нарх
 * қидируви» (default codebase, `functions/price_search.js`) viloyatlararo yetkazish narxini AYNAN
 * logistika tarif dvigateli bilan hisoblashi kerak (CLAUDE.md 7: bitta manba). Shu sabab
 * `module_gate.js` / `capabilities_model.js` dagi kabi nusxa + paritet testi:
 * functions/test/logistics_tariff_parity.test.js. Nusxani QO'LDA TAHRIRLAMANG — manbani o'zgartirib,
 * shu skriptni ishga tushiring.
 */
const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '..', '..', 'functions_demand', 'core', 'tariff.js');
const DST = path.join(__dirname, '..', 'logistics_tariff.js');

const HEADER = [
  "/* NUSXA — manba: functions_demand/core/tariff.js. QO'LDA TAHRIRLANMAYDI.",
  " * Firebase deploy faqat o'z codebase papkasini yuklaydi, shuning uchun default",
  ' * codebase (assistantPriceSearch) uchun nusxa kerak. Paritet:',
  ' * functions/test/logistics_tariff_parity.test.js (bayt-ma-bayt).',
  ' * Yangilash: node functions/tools/sync_logistics_tariff.js */',
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
