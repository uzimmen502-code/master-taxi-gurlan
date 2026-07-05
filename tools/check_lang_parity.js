#!/usr/bin/env node
/**
 * assets/lang/*.json kalitlari bir xil ekanini tekshiradi.
 * Usage: node tools/check_lang_parity.js
 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', 'assets', 'lang');
const files = ['uz_Cyrl.json', 'uz_Latn.json', 'ru.json'];

const maps = files.map((f) => {
  const p = path.join(root, f);
  const keys = Object.keys(JSON.parse(fs.readFileSync(p, 'utf8')));
  return { file: f, keys: new Set(keys) };
});

let ok = true;
for (let i = 0; i < maps.length; i++) {
  for (let j = i + 1; j < maps.length; j++) {
    const a = maps[i];
    const b = maps[j];
    const onlyA = [...a.keys].filter((k) => !b.keys.has(k));
    const onlyB = [...b.keys].filter((k) => !a.keys.has(k));
    if (onlyA.length || onlyB.length) {
      ok = false;
      console.error(`\nMismatch: ${a.file} vs ${b.file}`);
      if (onlyA.length) console.error(`  only in ${a.file}:`, onlyA.slice(0, 20), onlyA.length > 20 ? `...+${onlyA.length - 20}` : '');
      if (onlyB.length) console.error(`  only in ${b.file}:`, onlyB.slice(0, 20), onlyB.length > 20 ? `...+${onlyB.length - 20}` : '');
    }
  }
}

if (ok) {
  console.log(`OK: ${files.join(', ')} — ${maps[0].keys.size} keys each`);
  process.exit(0);
}
process.exit(1);
