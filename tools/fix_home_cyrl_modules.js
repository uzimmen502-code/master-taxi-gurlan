const fs = require('fs');
const path = require('path');

const p = path.join(__dirname, '..', 'assets', 'lang', 'uz_Cyrl.json');
const d = JSON.parse(fs.readFileSync(p, 'utf8'));

/** Bosh ekran modullari — qo'lda tekshirilgan kirill. */
Object.assign(d, {
  bottom_wallet: '\u04B2\u0430\u043c\u0451\u043d',
  home_featured_title: '\u0422\u0430\u0432\u0441\u0438\u044f \u044d\u0442\u0430\u043c\u0438\u0437',
  home_module_local: '\u041c\u0410\u04B2\u0410\u041b\u041b\u0418\u0419 \u0422\u0410\u041a\u0421\u0418',
  home_module_intercity: '\u0428\u0410\u04B2\u0410\u0420\u041b\u0410\u0420\u0410\u0420\u041e \u0422\u0410\u041a\u0421\u0418',
  home_module_marshrut: '\u041c\u0410\u0420\u0428\u0420\u0423\u0422 \u0422\u0410\u041a\u0421\u0418',
  home_module_courier: '\u041a\u0443\u0440\u044c\u0435\u0440 \u0445\u0438\u0437\u043c\u0430\u0442\u0438',
  home_module_sell: '\u0421\u041e\u0422\u0418\u0428 \u0422\u0410\u041a\u041b\u0418\u0424\u0418',
  home_module_food: '\u0422\u0410\u041e\u041c \u0431\u0443\u044e\u0440\u0442\u043c\u0430',
  home_module_jobs: '\u0418\u0428 \u0414\u041e\u0421\u041a\u0410\u0421\u0418',
  home_module_bread: '\u041d\u041e\u041d \u0401\u041f\u0418\u0428',
  home_module_relatives: '\u041c\u0435\u043d\u0438\u043d\u0433 \u044f\u049b\u0438\u043d\u043b\u0430\u0440\u0438\u043c',
});

const sorted = Object.fromEntries(
  Object.entries(d).sort(([a], [b]) => a.localeCompare(b)),
);
fs.writeFileSync(p, JSON.stringify(sorted, null, 2) + '\n');
console.log('fixed home module uz_Cyrl strings');
