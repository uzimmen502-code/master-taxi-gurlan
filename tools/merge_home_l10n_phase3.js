#!/usr/bin/env node
/**
 * Home l10n Phase 3 — pastki nav kalitlari + uz_Cyrl qayta tiklash.
 * Ishlatish: node tools/merge_home_l10n_phase3.js
 */
const fs = require('fs');
const path = require('path');
const { latinToUzCyrl } = require('./latin_to_uz_cyrl');

const root = path.join(__dirname, '..', 'assets', 'lang');

/** @type {Record<string, { uz_Cyrl: string, uz_Latn: string, ru: string }>} */
const newKeys = {
  bottom_home: {
    uz_Cyrl: 'Бош саҳифа',
    uz_Latn: 'Bosh sahifa',
    ru: 'Главная',
  },
  bottom_orders: {
    uz_Cyrl: 'Буюртмалар',
    uz_Latn: 'Buyurtmalar',
    ru: 'Заказы',
  },
};

function mergeNewKeys() {
  for (const locale of ['uz_Cyrl', 'uz_Latn', 'ru']) {
    const p = path.join(root, `${locale}.json`);
    const data = JSON.parse(fs.readFileSync(p, 'utf8'));
    let n = 0;
    for (const [key, tr] of Object.entries(newKeys)) {
      data[key] =
        locale === 'uz_Cyrl' && tr.uz_Cyrl
          ? tr.uz_Cyrl
          : tr[locale] ?? latinToUzCyrl(tr.uz_Latn);
      n++;
    }
    const sorted = Object.fromEntries(
      Object.entries(data).sort(([a], [b]) => a.localeCompare(b)),
    );
    fs.writeFileSync(p, JSON.stringify(sorted, null, 2) + '\n');
    console.log(`${locale}: +${n} yangi kalit`);
  }
}

mergeNewKeys();
require('./rebuild_uz_cyrl_from_latn.js');
