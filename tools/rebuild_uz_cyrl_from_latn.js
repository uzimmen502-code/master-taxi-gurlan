#!/usr/bin/env node
/**
 * uz_Cyrl.json ni uz_Latn.json dan qayta tiklash (placeholder buzilishini tuzatish).
 * Ishlatish: node tools/rebuild_uz_cyrl_from_latn.js
 */
const fs = require('fs');
const path = require('path');
const { latinToUzCyrl } = require('./latin_to_uz_cyrl');

const root = path.join(__dirname, '..', 'assets', 'lang');
const latn = JSON.parse(
  fs.readFileSync(path.join(root, 'uz_Latn.json'), 'utf8'),
);
const cyrlPath = path.join(root, 'uz_Cyrl.json');
const cyrl = JSON.parse(fs.readFileSync(cyrlPath, 'utf8'));

/** Lotin qoldiriladigan yoki qo'lda yozilgan qiymatlar. */
const MANUAL = {
  app_name: 'AVA Gurlan',
  ok: 'ОК',
  auto_accept_bookings: 'Авто-тасдиқ (бронлар дарҳол tasdiqlanadi)',
  complete_trip_confirm:
    '{from} → {to} safarini yakunlashni tasdiqlaysizmi?',
  enter_car_model: 'Масalan: Shevrolet Kobalt',
  role_accountant: '💰 Buxgalter',
  home_display_name_aka: '{name} aka',
};

let n = 0;
for (const key of Object.keys(latn)) {
  if (!(key in cyrl)) continue;
  if (MANUAL[key] != null) {
    cyrl[key] =
      key === 'app_name' || key === 'ok'
        ? MANUAL[key]
        : latinToUzCyrl(MANUAL[key]);
    n++;
    continue;
  }
  cyrl[key] = latinToUzCyrl(latn[key]);
  n++;
}

const sorted = Object.fromEntries(
  Object.entries(cyrl).sort(([a], [b]) => a.localeCompare(b)),
);
fs.writeFileSync(cyrlPath, JSON.stringify(sorted, null, 2) + '\n');

const lat = /[A-Za-z]/;
const remaining = Object.entries(cyrl).filter(
  ([k, v]) => lat.test(v) && k !== 'app_name',
);
console.log(`Yangilandi: ${n} kalit`);
console.log(`Qolgan lotin (app_name dan tashqari): ${remaining.length}`);
remaining.forEach(([k, v]) => console.log(`  ${k}: ${v}`));
