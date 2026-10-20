/**
 * PUSH CHEGARASINI O'LCHAB TANLASH (ega 2026-10-20, variant 3).
 *
 *   1) node functions_demand/tools/review_matches.js 50 --csv > matches.csv
 *   2) matches.csv ni oching va HAR QATORGA `relevant` ustuniga ha/yo'q yozing
 *      («bu talab bu taklifchiga mantiqan mosmi?»). Qolgan ustunlarga tegmang.
 *   3) node functions_demand/tools/calibrate_push_threshold.js matches.csv
 *   4) Chiqqan buyruq bilan chegarani yozing:
 *      node functions_demand/tools/seed_module_config.js --min-score 0.75 [--region xorazm]
 *
 * HECH QAYERGA ULANMAYDI: faqat lokal CSV fayl o'qiladi, hech narsa yozilmaydi.
 * Natija — taklif; chegarani ega tasdiqlaydi (49-band).
 *
 * Nega o'lchov: `score` formula (kategoriya 40 % + yaqinlik 40 % + manba 20 %),
 * «necha foiz mantiqan mos» emas. Chegara = «score >= t» bo'lganlar orasida
 * `relevant` ulushi >= nishon (standart 90 %) bo'ladigan ENG PAST t.
 */
'use strict';
const fs = require('fs');

const { suggestThreshold, parseLabeledCsv } = require('../core/calibration');

const pct = (x) => (x === null || x === undefined ? '—' : `${(x * 100).toFixed(1)} %`);

/** Hisobot matni (sof funksiya — testlanadi). */
function formatReport(res, region) {
  const lines = [];
  lines.push(`Baholangan moslik: ${res.total}  (bahosiz: ${res.unlabeled}, yaroqsiz score: ${res.invalid})`);
  lines.push(`Nishon aniqlik: ${pct(res.target)}`);
  lines.push('');
  lines.push('score oralig\'i    soni   mos   aniqlik');
  for (const b of res.buckets) {
    const lo = b.from.toFixed(1);
    const hi = (b.from + 0.1).toFixed(1);
    lines.push(`${lo} .. ${hi}`.padEnd(17) + String(b.count).padEnd(7) + String(b.relevant).padEnd(6) + pct(b.precision));
  }
  lines.push('');
  if (res.threshold === null) {
    const why = res.reason === 'sample_too_small'
      ? 'baholangan moslik yetarli emas — ko\'proq moslikni baholang'
      : 'hech bir chegara nishon aniqlikka yetmadi — matching sifatini yaxshilash kerak (push ketmaydi)';
    lines.push(`NATIJA: chegara TAVSIYA QILINMAYDI: ${why}.`);
    return lines.join('\n');
  }
  const use = res.rounded !== null ? res.rounded : res.threshold;
  lines.push(`Aniq chegara: ${res.threshold}  (>= bu score: ${res.count} ta, shundan mos ${res.relevant} = ${pct(res.precision)})`);
  if (res.rounded !== null && res.rounded !== res.threshold) {
    lines.push(`Qulay yaxlitlangan qiymat: ${res.rounded} (nishon saqlanadi)`);
  }
  lines.push('');
  lines.push('Yozish buyrug\'i (production — faqat ega ruxsati bilan):');
  lines.push(`  node functions_demand/tools/seed_module_config.js --min-score ${use}${region ? ` --region ${region}` : ''}`);
  return lines.join('\n');
}

function main(argv) {
  const file = argv[0];
  if (!file || file.startsWith('--')) {
    console.error('Ishlatish: node functions_demand/tools/calibrate_push_threshold.js <fayl.csv> [--target 0.9] [--min-sample 20] [--min-total 30] [--region xorazm]');
    return 1;
  }
  const arg = (name, def) => {
    const i = argv.indexOf(`--${name}`);
    return i >= 0 && argv[i + 1] ? argv[i + 1] : def;
  };
  const target = Number(arg('target', '0.9'));
  const minSample = Number(arg('min-sample', '20'));
  const minTotal = Number(arg('min-total', '30'));
  const region = arg('region', '');

  let rows;
  try {
    ({ rows } = parseLabeledCsv(fs.readFileSync(file, 'utf8')));
  } catch (e) {
    console.error(`XATO: ${e.message}`);
    return 1;
  }
  try {
    console.log(formatReport(suggestThreshold(rows, { target, minSample, minTotal }), region));
  } catch (e) {
    console.error(`XATO: ${e.message}`);
    return 1;
  }
  return 0;
}

if (require.main === module) process.exit(main(process.argv.slice(2)));

module.exports = { formatReport, main };
