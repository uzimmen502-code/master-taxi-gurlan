const fs = require('fs');
const p = 'c:/projects/ava_gurlan/assets/lang/uz_Cyrl.json';
const d = JSON.parse(fs.readFileSync(p, 'utf8'));
d.non_promo_title = 'Нон буюртма qiling';
d.non_promo_subtitle = 'Яangi non \u2014 500 \u0441\u045e\u043c, eshigingizga';
d.home_promo_order_cta = 'Буюртма bering \u2192';
const sorted = Object.fromEntries(
  Object.entries(d).sort(([a], [b]) => a.localeCompare(b)),
);
fs.writeFileSync(p, JSON.stringify(sorted, null, 2) + '\n');
console.log('fixed cyrl promo strings');
