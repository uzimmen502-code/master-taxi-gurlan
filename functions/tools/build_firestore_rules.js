#!/usr/bin/env node
/**
 * firestore.rules → deploy uchun izohsiz nusxa.
 *
 * Nega: Firebase rules manbasi 256 KB bilan cheklangan (oshirib bo'lmaydi);
 * repodagi fayl ~45% izoh (kirill harfi 2 bayt). Ega qarori (2026-11-01,
 * «А» varianti): repodagi IZOHLI `firestore.rules` — yagona manba; deploy
 * faqat shu skript chiqargan izohsiz nusxadan qilinadi.
 *
 * Kafolat: chiqish faqat izoh va qator oxiri/bo'sh qatorlar bilan farq
 * qiladi. Skript buni o'zi tekshiradi — manba va chiqishning izoh/bo'shliqsiz
 * token ketma-ketligi AYNAN bir xil bo'lmasa, yozmaydi (exit 1).
 * Satr ichidagi `//` (masalan 'https://...') izoh hisoblanmaydi.
 *
 * Birinchi qator: `// built from firestore.rules sha256:<hash>` — jonli
 * ruleset qaysi manbadan qurilganini shu bilan tekshirish mumkin.
 *
 * Ishlatish (repo ildizidan):
 *   node functions/tools/build_firestore_rules.js [manba] [chiqish]
 *   standart: firestore.rules → build/firestore_rules/firestore.rules
 *   --check : faqat tekshiradi va hajmni chiqaradi, yozmaydi.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const LIMIT_BYTES = 256 * 1024;

/**
 * Manbani bo'laklarga ajratadi: {type: 'code'|'string'|'comment', text}.
 * `//` va `/* *\/` faqat satr tashqarisida izoh. Satr — '...' yoki "...",
 * `\` bilan ekranlash.
 */
function lex(src) {
  const parts = [];
  let i = 0;
  let buf = '';
  const flush = () => {
    if (buf) parts.push({type: 'code', text: buf});
    buf = '';
  };
  while (i < src.length) {
    const c = src[i];
    const n = src[i + 1];
    if (c === '/' && n === '/') {
      flush();
      let j = src.indexOf('\n', i);
      if (j < 0) j = src.length;
      parts.push({type: 'comment', text: src.slice(i, j)});
      i = j;
    } else if (c === '/' && n === '*') {
      flush();
      const j = src.indexOf('*/', i + 2);
      if (j < 0) throw new Error(`yopilmagan /* izoh (offset ${i})`);
      parts.push({type: 'comment', text: src.slice(i, j + 2)});
      i = j + 2;
    } else if (c === '\'' || c === '"') {
      flush();
      let j = i + 1;
      while (j < src.length && src[j] !== c) {
        if (src[j] === '\\') j++;
        if (src[j] === '\n') throw new Error(`yopilmagan satr (offset ${i})`);
        j++;
      }
      if (j >= src.length) throw new Error(`yopilmagan satr (offset ${i})`);
      parts.push({type: 'string', text: src.slice(i, j + 1)});
      i = j + 1;
    } else {
      buf += c;
      i++;
    }
  }
  flush();
  return parts;
}

/** Izoh va bo'shliqsiz token ketma-ketligi (tekshiruv uchun). */
function tokens(src) {
  const out = [];
  for (const p of lex(src)) {
    if (p.type === 'comment') continue;
    if (p.type === 'string') {
      out.push(p.text);
      continue;
    }
    for (const t of p.text.split(/\s+/)) if (t) out.push(t);
  }
  return out;
}

function strip(src) {
  // `//` izoh qator oxirigacha (\n o'zi qoladi); `/* */` o'rniga bo'shliq —
  // `a/*x*/b` `ab` bo'lib qolmasin.
  const body = lex(src.replace(/\r\n/g, '\n'))
      .map((p) => p.type !== 'comment' ? p.text
          : p.text.startsWith('/*') ? ' ' : '')
      .join('');
  return body
      .split('\n')
      .map((l) => l.replace(/[ \t]+$/, ''))
      .filter((l) => l.length > 0)
      .join('\n') + '\n';
}

function build(src) {
  const out = strip(src);
  const a = tokens(src);
  const b = tokens(out);
  if (a.length !== b.length || a.some((t, k) => t !== b[k])) {
    const k = a.findIndex((t, idx) => t !== b[idx]);
    throw new Error(`token ketma-ketligi farq qiladi (#${k}: ${a[k]} ≠ ${b[k]})`);
  }
  const hash = crypto.createHash('sha256').update(src).digest('hex');
  return `// built from firestore.rules sha256:${hash}\n` + out;
}

function main() {
  const args = process.argv.slice(2).filter((a) => !a.startsWith('--'));
  const checkOnly = process.argv.includes('--check');
  const root = path.join(__dirname, '..', '..');
  const srcPath = path.resolve(args[0] || path.join(root, 'firestore.rules'));
  const outPath = path.resolve(
      args[1] || path.join(root, 'build', 'firestore_rules', 'firestore.rules'));
  const src = fs.readFileSync(srcPath, 'utf8');
  const out = build(src);
  const srcBytes = Buffer.byteLength(src, 'utf8');
  const outBytes = Buffer.byteLength(out, 'utf8');
  console.log(`manba: ${srcBytes} bayt → chiqish: ${outBytes} bayt ` +
      `(chegara ${LIMIT_BYTES}, bo'sh ${LIMIT_BYTES - outBytes}); tokenlar bir xil`);
  if (outBytes > LIMIT_BYTES) {
    console.error('XATO: chiqish 256 KB dan katta');
    process.exitCode = 1;
    return;
  }
  if (checkOnly) return;
  fs.mkdirSync(path.dirname(outPath), {recursive: true});
  fs.writeFileSync(outPath, out, 'utf8');
  console.log(`yozildi: ${outPath}`);
}

module.exports = {lex, tokens, strip, build};

if (require.main === module) {
  try {
    main();
  } catch (e) {
    console.error('XATO:', e.message);
    process.exitCode = 1;
  }
}
