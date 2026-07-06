#!/usr/bin/env node
/**
 * uz_Cyrl.json ni uz_Latn.json dan to'liq qayta generatsiya (СҺ/CҺ buzilishini tuzatish).
 * Ishlatish: node tools/fix_uz_cyrl_corruption.js
 */
const fs = require('fs');
const path = require('path');
const { latinToUzCyrl } = require('./latin_to_uz_cyrl');

const root = path.join(__dirname, '..', 'assets', 'lang');
const latn = JSON.parse(
  fs.readFileSync(path.join(root, 'uz_Latn.json'), 'utf8'),
);
const cyrlPath = path.join(root, 'uz_Cyrl.json');
const before = JSON.parse(fs.readFileSync(cyrlPath, 'utf8'));

/** Lotin qoldiriladi. */
const MANUAL = {
  app_name: 'AVA Gurlan',
  ok: 'ОК',
};

const cyrl = { ...before };
const changed = [];

for (const key of Object.keys(latn)) {
  if (!(key in cyrl)) continue;
  const next =
    MANUAL[key] != null ? MANUAL[key] : latinToUzCyrl(latn[key]);
  if (cyrl[key] !== next) {
    changed.push({ key, old: cyrl[key], new: next });
    cyrl[key] = next;
  }
}

fs.writeFileSync(
  cyrlPath,
  JSON.stringify(
    Object.fromEntries(
      Object.entries(cyrl).sort(([a], [b]) => a.localeCompare(b)),
    ),
    null,
    2,
  ) + '\n',
);

require('./fix_home_cyrl_modules.js');

const after = JSON.parse(fs.readFileSync(cyrlPath, 'utf8'));
const stillBad = Object.entries(after).filter(
  ([k, v]) => k !== 'app_name' && /СҺ|CҺ|CҲ/.test(v),
);
const stillLatin = Object.entries(after).filter(
  ([k, v]) => k !== 'app_name' && /[A-Za-z]/.test(v),
);

console.log(`O'zgardi: ${changed.length} kalit`);
const important = changed.filter(
  ({ key, old }) =>
    /СҺ|CҺ|CҲ/.test(old) ||
    ['search_driver', 'intercity_search', 'accept', 'continue'].includes(key),
);
important.forEach(({ key, old, new: n }) => {
  console.log(`  ${key}`);
  console.log(`    - ${old}`);
  console.log(`    + ${n}`);
});
console.log(`Qolgan СҺ/CҺ: ${stillBad.length}`);
stillBad.forEach(([k, v]) => console.log(`  ${k}: ${v}`));
console.log(`Qolgan lotin (app_name dan tashqari): ${stillLatin.length}`);
stillLatin.slice(0, 15).forEach(([k, v]) => console.log(`  ${k}: ${v}`));
