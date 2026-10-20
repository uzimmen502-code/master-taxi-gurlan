/**
 * Push чегарасини қўлда баҳолашдан ЎЛЧАБ танлаш (ега 2026-10-20, вариант 3).
 *
 *   node functions_demand/test/calibration.test.js
 *
 * Фирестор ва тармоқ йўқ: тоза функциялар.
 */
const assert = require('assert');
const { suggestThreshold, parseLabeledCsv, parseRelevant } = require('../core/calibration');

let passed = 0;
function ok(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`  OK  ${name}`);
  } catch (e) {
    console.error(`  XATO ${name}\n       ${e.message}`);
    process.exitCode = 1;
  }
}

/** n та қатор: берилган score ва k таси «мос». */
function rows(score, n, k) {
  return Array.from({ length: n }, (_, i) => ({ score, relevant: i < k }));
}

// Тушунтириш жадвали (ега мисоли): 0.8+:12/12, 0.70-0.79:20/19, 0.60-0.69:10/5, <0.60:8/1
const EXAMPLE = [
  ...rows(0.85, 12, 12),
  ...rows(0.75, 20, 19),
  ...rows(0.65, 10, 5),
  ...rows(0.5, 8, 1),
];

console.log('suggestThreshold');
ok('ега мисоли: 50 мослик -> чегара 0.75 (энг пасти, аниқлик >= 90 %)', () => {
  const r = suggestThreshold(EXAMPLE, { target: 0.9, minSample: 20 });
  // 0.75 ва юқори: 12 + 20 = 32 та, 12 + 19 = 31 мос -> 96.9 %.
  // 0.65 ва юқори: 42 та, 36 мос -> 85.7 % (<90 %) — яроқсиз.
  assert.strictEqual(r.threshold, 0.75);
  assert.strictEqual(r.count, 32);
  assert.strictEqual(r.relevant, 31);
  assert.ok(Math.abs(r.precision - 31 / 32) < 1e-9);
});
ok('чегара ЭНГ ПАСТ яроқли қиймат (қамров энг катта)', () => {
  const r = suggestThreshold(EXAMPLE, { target: 0.9, minSample: 10 });
  // minSample 10 бўлса 0.85 ҳам яроқли, лекин энг пасти 0.75 (32 та).
  assert.strictEqual(r.threshold, 0.75);
});
ok('нишон юқорироқ (97 %) бўлса чегара кўтарилади', () => {
  const r = suggestThreshold(EXAMPLE, { target: 0.97, minSample: 10 });
  // 0.75+ = 96.9 % < 97 % -> фақат 0.85 (100 %).
  assert.strictEqual(r.threshold, 0.85);
  assert.strictEqual(r.count, 12);
});
ok('ҳеч бир чегара нишонга етмаса -> threshold: null ва сабаб', () => {
  const bad = [...rows(0.9, 30, 20), ...rows(0.5, 20, 2)];
  const r = suggestThreshold(bad, { target: 0.9, minSample: 20 });
  assert.strictEqual(r.threshold, null);
  assert.strictEqual(r.reason, 'no_threshold_meets_target');
});
ok('юқори қисм жуда кичик (minSample) бўлса ишончсиз -> null', () => {
  const tiny = [...rows(0.95, 3, 3), ...rows(0.4, 40, 0)];
  const r = suggestThreshold(tiny, { target: 0.9, minSample: 20 });
  assert.strictEqual(r.threshold, null);
  assert.strictEqual(r.reason, 'no_threshold_meets_target');
});
ok('умумий намуна жуда кичик (< minTotal) -> null, sample_too_small', () => {
  const r = suggestThreshold(rows(0.9, 10, 10), { target: 0.9, minSample: 5, minTotal: 30 });
  assert.strictEqual(r.threshold, null);
  assert.strictEqual(r.reason, 'sample_too_small');
});
ok('баҳосиз (relevant: null) қаторлар ҳисобга олинмайди, лекин санаб кўрсатилади', () => {
  const r = suggestThreshold(
    [...EXAMPLE, { score: 0.99, relevant: null }, { score: 0.1, relevant: undefined }],
    { target: 0.9, minSample: 20 },
  );
  assert.strictEqual(r.unlabeled, 2);
  assert.strictEqual(r.total, 50);
  assert.strictEqual(r.threshold, 0.75);
});
ok('яроқсиз score (NaN, матн) ташлаб юборилади, санаб кўрсатилади', () => {
  const r = suggestThreshold(
    [...EXAMPLE, { score: NaN, relevant: true }, { score: 'x', relevant: true }],
    { target: 0.9, minSample: 20 },
  );
  assert.strictEqual(r.invalid, 2);
  assert.strictEqual(r.threshold, 0.75);
});
ok('жадвал: 0.1 қадамли гуруҳлар ва аниқлик', () => {
  const r = suggestThreshold(EXAMPLE, { target: 0.9, minSample: 20 });
  const b = Object.fromEntries(r.buckets.map((x) => [x.from, x]));
  assert.strictEqual(b[0.8].count, 12);
  assert.strictEqual(b[0.8].relevant, 12);
  assert.strictEqual(b[0.7].count, 20);
  assert.strictEqual(b[0.7].relevant, 19);
  assert.strictEqual(b[0.6].count, 10);
  assert.strictEqual(b[0.5].count, 8);
});
ok('чегара 0.75 дан 2 хонага юқорига юмалатилса ҳам нишон сақланса — юмалоқ қиймат', () => {
  const data = [...rows(0.7449, 5, 5), ...rows(0.8, 30, 29)];
  const r = suggestThreshold(data, { target: 0.9, minSample: 20 });
  // Аниқ қиймат 0.7449 (35 та, 34 мос = 97 %), 0.75 га юмалатсак 30 та (29 мос = 96.7 %) — яроқли.
  assert.strictEqual(r.rounded, 0.75);
  assert.strictEqual(r.threshold, 0.7449);
});
ok('юмалоқ қиймат нишонни бузса — аниқ қиймат қайтади (юмалоқ йўқ)', () => {
  // 0.7449 даги 5 та мос; 0.75+ да мос камайса аниқлик тушади.
  const data = [...rows(0.7449, 5, 5), ...rows(0.8, 24, 21)];
  const r = suggestThreshold(data, { target: 0.9, minSample: 20 });
  // аниқ: 29 та, 26 мос = 89.7 % (<90 %) -> 0.7449 яроқсиз. 0.8: 24 та, 21 мос = 87.5 %. -> null
  assert.strictEqual(r.threshold, null);
});
ok('қайтадиган чегара ҳамма вақт (0, 1] оралиғида', () => {
  const r = suggestThreshold(rows(1, 40, 40), { target: 0.9, minSample: 20 });
  assert.strictEqual(r.threshold, 1);
});
ok('нишон ёки minSample нотўғри бўлса xato', () => {
  for (const bad of [0, -1, 1.5, NaN]) {
    assert.throws(() => suggestThreshold(EXAMPLE, { target: bad }), /target/);
  }
  for (const bad of [0, -1, 2.5, NaN]) {
    assert.throws(() => suggestThreshold(EXAMPLE, { target: 0.9, minSample: bad }), /minSample/);
  }
});

console.log('parseRelevant');
ok('ҳа/йўқ шакллари: yes/no, 1/0, true/false, ҳа/йўқ, ha/yoq, да/нет', () => {
  for (const v of ['yes', 'YES', '1', 'true', 'ha', 'ҳа', 'да', 'x', '+']) {
    assert.strictEqual(parseRelevant(v), true, v);
  }
  for (const v of ['no', 'NO', '0', 'false', 'yoq', "yo'q", 'йўқ', 'нет', '-']) {
    assert.strictEqual(parseRelevant(v), false, v);
  }
});
ok('бўш ёки номаълум -> null (баҳосиз)', () => {
  for (const v of ['', '  ', null, undefined, 'balki', '?']) {
    assert.strictEqual(parseRelevant(v), null, String(v));
  }
});

console.log('parseLabeledCsv');
ok('score ва relevant устунларини ўқийди (бошқа устунлар эътиборсиз)', () => {
  const csv = [
    'key,demandTitle,score,relevant,region',
    '"d1_9989011****11","elektrik kerak","0.79","yes","xorazm"',
    '"d2_9989022****22","santexnik","0.62","no","xorazm"',
    '"d3_9989033****33","fotograf","0.71","","xorazm"',
  ].join('\n');
  const r = parseLabeledCsv(csv);
  assert.deepStrictEqual(r.rows, [
    { score: 0.79, relevant: true },
    { score: 0.62, relevant: false },
    { score: 0.71, relevant: null },
  ]);
});
ok('қўштирноқ ичидаги вергул ва қўш қўштирноқ тўғри ўқилади', () => {
  const csv = 'demandTitle,score,relevant\n"elektrik, tez ""kerak""","0.8","ha"';
  const r = parseLabeledCsv(csv);
  assert.deepStrictEqual(r.rows, [{ score: 0.8, relevant: true }]);
});
ok('CRLF сатр охирлари ва БОМ ишлайди', () => {
  const csv = '﻿score,relevant\r\n0.9,yes\r\n0.4,no\r\n';
  assert.deepStrictEqual(parseLabeledCsv(csv).rows, [
    { score: 0.9, relevant: true },
    { score: 0.4, relevant: false },
  ]);
});
ok('score ёки relevant устуни йўқ бўлса аниқ xato', () => {
  assert.throws(() => parseLabeledCsv('a,b\n1,2'), /score/);
  assert.throws(() => parseLabeledCsv('score,b\n0.5,2'), /relevant/);
});
ok('бўш файл -> бўш рўйхат (йиқилмайди)', () => {
  assert.deepStrictEqual(parseLabeledCsv('').rows, []);
  assert.deepStrictEqual(parseLabeledCsv('score,relevant\n').rows, []);
});

console.log('parseMinScoreArg (--min-score)');
const { parseMinScoreArg } = require('../core/calibration');
ok('тўғри қийматлар: 0.75, 0,75 (вергул), 1, 0.01', () => {
  assert.strictEqual(parseMinScoreArg('0.75'), 0.75);
  assert.strictEqual(parseMinScoreArg('0,75'), 0.75);
  assert.strictEqual(parseMinScoreArg('1'), 1);
  assert.strictEqual(parseMinScoreArg('0.01'), 0.01);
});
ok('off / null -> null (чегара ўчирилади)', () => {
  assert.strictEqual(parseMinScoreArg('off'), null);
  assert.strictEqual(parseMinScoreArg('NULL'), null);
});
ok('хато қийматлар РАД: 90 (фоиз), 0, манфий, матн, бўш, undefined', () => {
  for (const bad of ['90', '0', '-0.5', '1.01', 'yuqori', '', undefined, null, 'NaN']) {
    assert.throws(() => parseMinScoreArg(bad), /min-score/, String(bad));
  }
});

console.log('calibrate_push_threshold — ҳисобот матни');
const { formatReport } = require('../tools/calibrate_push_threshold');
ok('ҳисобот чегара, аниқлик ва ёзиш буйруғини кўрсатади', () => {
  const text = formatReport(suggestThreshold(EXAMPLE, { target: 0.9, minSample: 20 }), 'xorazm');
  assert.ok(/Aniq chegara: 0\.75/.test(text), text);
  assert.ok(/96\.9 %/.test(text), text);
  assert.ok(/seed_module_config\.js --min-score 0\.75 --region xorazm/.test(text), text);
});
ok('ҳисобот: чегара топилмаса буйруқ БЕРИЛМАЙДИ ва сабаб ёзилади', () => {
  const bad = [...rows(0.9, 30, 20), ...rows(0.5, 20, 2)];
  const text = formatReport(suggestThreshold(bad, { target: 0.9, minSample: 20 }));
  assert.ok(/TAVSIYA QILINMAYDI/.test(text), text);
  assert.ok(!/--min-score/.test(text), text);
});
ok('ҳисобот: намуна кичик бўлса «кўпроқ баҳоланг»', () => {
  const text = formatReport(suggestThreshold(rows(0.9, 10, 10), { target: 0.9, minSample: 5 }));
  assert.ok(/yetarli emas/.test(text), text);
});
ok('ҳисоботда телефон/ID йўқ (фақат сонлар)', () => {
  const text = formatReport(suggestThreshold(EXAMPLE, { target: 0.9, minSample: 20 }));
  assert.ok(!/998\d{9}/.test(text));
});

console.log(`\n${passed} test o'tdi.`);
