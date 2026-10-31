/**
 * functions/tools/build_firestore_rules.js — izohsiz deploy nusxasi.
 * Emulator kerak emas. Ishlatish: npm run test:build-rules
 */
'use strict';
const fs = require('fs');
const path = require('path');
const {lex, strip, build} = require('../tools/build_firestore_rules');

const results = [];
function check(name, fn) {
  try {
    fn();
    results.push(true);
    console.log(`PASS - ${name}`);
  } catch (e) {
    results.push(false);
    console.log(`FAIL - ${name} :: ${e.message}`);
  }
}
function eq(a, b) {
  if (a !== b) throw new Error(`\n  kutilgan: ${JSON.stringify(b)}\n  olingan:  ${JSON.stringify(a)}`);
}

check('qator izohi va to\'liq izoh qatori olib tashlanadi', () => {
  eq(strip('// sarlavha\nallow read: if true; // izoh\n'),
      'allow read: if true;\n');
});

check('satr ichidagi // izoh emas (URL)', () => {
  const s = "x.matches('https://a.b/o/' + p) // izoh\n";
  eq(strip(s), "x.matches('https://a.b/o/' + p)\n");
});

check('izohdagi apostrof satr ochmaydi', () => {
  eq(strip("// o'chirdi va O'ZINING\nallow get: if a == 'b';\n"),
      "allow get: if a == 'b';\n");
});

check('ekranlangan satr: \'\\\\+\' va \\\' to\'g\'ri o\'qiladi', () => {
  const s = "p.replace('\\\\+', '') // x\nq == 'it\\'s' // y\n";
  eq(strip(s), "p.replace('\\\\+', '')\nq == 'it\\'s'\n");
});

check('/* blok */ izoh, tokenlar yopishmaydi', () => {
  eq(strip('a/*x*/b\n/**\n * doc\n */\nc\n'), 'a b\nc\n');
});

check('CRLF → LF, bo\'sh qatorlar va oxirgi bo\'shliqlar olinadi', () => {
  eq(strip('a  \r\n\r\n   \r\nb\r\n'), 'a\nb\n');
});

check('build: sarlavhada manba sha256', () => {
  const out = build('allow read: if true;\n');
  if (!/^\/\/ built from firestore\.rules sha256:[0-9a-f]{64}\n/.test(out)) {
    throw new Error(out.split('\n')[0]);
  }
});

check('yopilmagan satr — xato (jimgina noto\'g\'ri chiqish yo\'q)', () => {
  let threw = false;
  try {
    lex("a == 'oops\n");
  } catch (_) {
    threw = true;
  }
  if (!threw) throw new Error('xato kutilgan edi');
});

check('haqiqiy firestore.rules: tokenlar bir xil va 256 KB dan kichik', () => {
  const src = fs.readFileSync(
      path.join(__dirname, '..', '..', 'firestore.rules'), 'utf8');
  const out = build(src);
  const bytes = Buffer.byteLength(out, 'utf8');
  if (bytes > 256 * 1024) throw new Error(`${bytes} bayt`);
});

const failed = results.filter((r) => !r).length;
console.log(`\n${results.length - failed}/${results.length} build_firestore_rules checks passed.`);
if (failed) process.exitCode = 1;
