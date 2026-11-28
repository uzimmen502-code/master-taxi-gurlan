/**
 * Server matnlari: `uz_Latn` satrlari YANGI lotin alifbosida (ega 2026-11-19: o'→ö, g'→ğ, sh→ş, ch→ç;
 * 2026-11-28 audit 18-band — bildirishnomalar). Emulatorsiz.
 *   node test/uz_latn_new_alphabet_lint.test.js
 *
 * Qoida: `functions/*.js` va `functions_demand/**` (test/tools/node_modules'dan tashqari) da `uz_Latn` bor qatordagi
 * (yoki `uz_Latn: { ... }` bloki ichidagi) har bir satr literal `tools/uz_latin_alphabet.js` convertText dan
 * o'zgarmasdan o'tishi kerak (brend/URL/placeholder — converter istisnosi).
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { convertText } = require('../tools/uz_latin_alphabet');

const ROOT = path.join(__dirname, '..', '..');
const SKIP = /node_modules|[\\/]test[\\/]|[\\/]tools[\\/]|[\\/]lib[\\/]|\.min\./;
const STR = /'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)"|`((?:[^`\\]|\\.)*)`/g;

function walk(d, out) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (SKIP.test(p)) continue;
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.js')) out.push(p);
  }
  return out;
}

/** Sof: fayl matnidan uz_Latn literal'lari (scan_latn bilan bir xil evristika). */
function latnLiterals(src) {
  const res = [];
  let depth = 0;
  let carry = 0;
  src.split(/\r?\n/).forEach((line, i) => {
    const hit = /uz_Latn/.test(line);
    const opens = (line.match(/[{[(]/g) || []).length - (line.match(/[}\])]/g) || []).length;
    const inBlock = depth > 0 || carry > 0;
    if (hit && !inBlock && opens > 0) depth = opens; else if (depth > 0) depth += opens;
    if (carry > 0) carry--;
    if (hit && /\?\s*$|===\s*'uz_Latn'\s*$/.test(line)) carry = 2;
    if (depth < 0) depth = 0;
    if ((!hit && !inBlock) || /^\s*(\/\/|\*)/.test(line)) return;
    let m;
    STR.lastIndex = 0;
    while ((m = STR.exec(line)) !== null) {
      const raw = m[1] ?? m[2] ?? m[3];
      if (!raw || raw === 'uz_Latn' || !/[A-Za-z]/.test(raw)) continue;
      res.push({ line: i + 1, text: raw.replace(/\\'/g, "'").replace(/\\"/g, '"') });
    }
  });
  return res;
}

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};

check('L1 evristika: eski shakl topiladi, yangi shakl/brend/placeholder — yo\'q', () => {
  const src = "x = { uz_Latn: { title: 'Jo\\'natma', body: '{name} söm' } };\nconst y = { uz_Latn: 'Telegram chat' };";
  const found = latnLiterals(src).filter((l) => convertText(l.text) !== l.text).map((l) => l.text);
  assert.deepStrictEqual(found, ["Jo'natma"]);
});

const files = [...walk(path.join(ROOT, 'functions'), []), ...walk(path.join(ROOT, 'functions_demand'), [])];
check(`L2 server uz_Latn matnlari yangi alifboda (${files.length} fayl)`, () => {
  const bad = [];
  let scanned = 0;
  for (const f of files) {
    for (const l of latnLiterals(fs.readFileSync(f, 'utf8'))) {
      scanned++;
      const c = convertText(l.text);
      if (c !== l.text) bad.push(`${path.relative(ROOT, f)}:${l.line}: «${l.text}» → «${c}»`);
    }
  }
  assert.ok(scanned > 300, `kam literal topildi: ${scanned}`);
  assert.deepStrictEqual(bad.slice(0, 20), [], `${bad.length} ta eski shakl`);
});

const passed = results.filter(Boolean).length;
console.log(`\n${passed}/${results.length} passed`);
process.exit(passed === results.length ? 0 : 1);
