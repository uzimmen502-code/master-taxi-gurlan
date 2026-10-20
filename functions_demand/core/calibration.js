'use strict';

/**
 * PUSH ЧЕГАРАСИНИ ЎЛЧАБ ТАНЛАШ (ега 2026-10-20, вариант 3).
 *
 * Ега қоидаси: «push фақат сўров таклифчига мантиқан ≥90 % мос бўлса».
 * `score` формула (категория 40 % + яқинлик 40 % + манба 20 %), «неча фоиз
 * мантиқан мос» эмас. Шу сабабли чегара ҳисобдан эмас, ЎЛЧОВДАН танланади:
 * `tools/review_matches.js --csv` дан чиққан мосликлар одам томонидан
 * «мантиқан мосми?» деб баҳоланади (`relevant` устуни), сўнг бу модул:
 *
 *   «score >= t» бўлган мосликлар орасида «мос» улуши (аниқлик) >= нишон (90 %)
 *   бўладиган ЭНГ ПАСТ t ни топади. Энг паст — чунки чегара қанчалик паст
 *   бўлса, шунчалик кўп мослик push олади (қамров), аниқлик эса барибир нишонда.
 *
 * Тоза функциялар: Фирестор ва тармоқ йўқ.
 */

const TRUE_WORDS = new Set(['yes', 'y', '1', 'true', 'ha', 'ҳа', 'да', 'x', '+']);
const FALSE_WORDS = new Set([
  'no', 'n', '0', 'false', 'yoq', 'yo\'q', 'yo`q', 'йўқ', 'йук', 'нет', '-',
]);

/** Баҳо қиймати: true / false / null (баҳосиз). */
function parseRelevant(v) {
  if (v === null || v === undefined) return null;
  const s = String(v).trim().toLowerCase();
  if (s === '') return null;
  if (TRUE_WORDS.has(s)) return true;
  if (FALSE_WORDS.has(s)) return false;
  return null;
}

/** score ни 0.1 қадамли гуруҳга (0.8 = [0.8, 0.9)) ажратади. */
function bucketOf(score) {
  return Math.floor(score * 10 + 1e-9) / 10;
}

/** 0.01 гача ЮҚОРИГА юмалатиш: 0.7449 -> 0.75; 0.75 -> 0.75. */
function ceil2(t) {
  return Math.ceil(t * 100 - 1e-9) / 100;
}

function countAtOrAbove(labeled, t) {
  let n = 0;
  let k = 0;
  for (const r of labeled) {
    if (r.score >= t) {
      n += 1;
      if (r.relevant) k += 1;
    }
  }
  return { n, k };
}

/**
 * @param {Array<{score: number, relevant: boolean|null|undefined}>} rows
 * @param {object} [opts]
 * @param {number} [opts.target=0.9]    керакли аниқлик (0, 1]
 * @param {number} [opts.minSample=20]  чегарадан юқори мослик сони камида (ишончлилик)
 * @param {number} [opts.minTotal=30]   баҳоланган мослик сони камида
 * @returns {{
 *   threshold: (number|null), rounded: (number|null), precision: (number|null),
 *   count: number, relevant: number, reason: (string|null),
 *   total: number, unlabeled: number, invalid: number,
 *   target: number, buckets: Array<object>
 * }}
 */
function suggestThreshold(rows, opts = {}) {
  const target = opts.target === undefined ? 0.9 : opts.target;
  const minSample = opts.minSample === undefined ? 20 : opts.minSample;
  const minTotal = opts.minTotal === undefined ? 30 : opts.minTotal;
  if (typeof target !== 'number' || !Number.isFinite(target) || target <= 0 || target > 1) {
    throw new Error(`target (0, 1] оралиғида бўлиши керак, берилган: ${String(target)}`);
  }
  if (!Number.isInteger(minSample) || minSample < 1) {
    throw new Error(`minSample бутун сон >= 1 бўлиши керак, берилган: ${String(minSample)}`);
  }

  const labeled = [];
  let unlabeled = 0;
  let invalid = 0;
  for (const r of rows || []) {
    const s = r ? r.score : undefined;
    if (typeof s !== 'number' || !Number.isFinite(s) || s < 0 || s > 1) {
      invalid += 1;
      continue;
    }
    if (typeof r.relevant !== 'boolean') {
      unlabeled += 1;
      continue;
    }
    labeled.push({ score: s, relevant: r.relevant });
  }

  // 0.1 қадамли жадвал (одамга кўрсатиш учун).
  const bucketMap = new Map();
  for (const r of labeled) {
    const key = bucketOf(r.score);
    const b = bucketMap.get(key) || { from: key, count: 0, relevant: 0 };
    b.count += 1;
    if (r.relevant) b.relevant += 1;
    bucketMap.set(key, b);
  }
  const buckets = Array.from(bucketMap.values())
    .sort((a, b) => b.from - a.from)
    .map((b) => ({ ...b, precision: b.relevant / b.count }));

  const base = {
    threshold: null,
    rounded: null,
    precision: null,
    count: 0,
    relevant: 0,
    reason: null,
    total: labeled.length,
    unlabeled,
    invalid,
    target,
    buckets,
  };

  if (labeled.length < minTotal) {
    return { ...base, reason: 'sample_too_small' };
  }

  const distinct = Array.from(new Set(labeled.map((r) => r.score))).sort((a, b) => a - b);
  for (const t of distinct) {
    const { n, k } = countAtOrAbove(labeled, t);
    if (n < minSample || k / n < target) continue;

    // Энг паст яроқли чегара топилди. Конфиг (0, 1] талаб қилади.
    const threshold = Math.max(t, 0.01);
    const at = countAtOrAbove(labeled, threshold);

    // Қулай юмалоқ қиймат (0.7449 -> 0.75): фақат нишонни ВА минимал намунани сақласа.
    const r2 = ceil2(threshold);
    const atR = countAtOrAbove(labeled, r2);
    const roundedOk = r2 <= 1 && atR.n >= minSample && atR.k / atR.n >= target;

    return {
      ...base,
      threshold,
      rounded: roundedOk ? r2 : null,
      precision: at.k / at.n,
      count: at.n,
      relevant: at.k,
      reason: null,
    };
  }
  return { ...base, reason: 'no_threshold_meets_target' };
}

/** Содда CSV (қўштирноқ, қўш қўштирноқ, CRLF, БОМ). */
function parseCsvRecords(text) {
  const src = String(text || '').replace(/^﻿/, '');
  const records = [];
  let row = [];
  let field = '';
  let inQuotes = false;
  for (let i = 0; i < src.length; i += 1) {
    const ch = src[i];
    if (inQuotes) {
      if (ch === '"') {
        if (src[i + 1] === '"') { field += '"'; i += 1; } else { inQuotes = false; }
      } else {
        field += ch;
      }
    } else if (ch === '"') {
      inQuotes = true;
    } else if (ch === ',') {
      row.push(field); field = '';
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && src[i + 1] === '\n') i += 1;
      row.push(field); field = '';
      records.push(row); row = [];
    } else {
      field += ch;
    }
  }
  if (field !== '' || row.length > 0) { row.push(field); records.push(row); }
  return records.filter((r) => !(r.length === 1 && r[0].trim() === ''));
}

/**
 * `review_matches.js --csv` чиқиши + одам тўлдирган `relevant` устуни.
 * Фақат `score` ва `relevant` ўқилади (бошқа устунлар, шу жумладан ҳар қандай
 * шахсий маълумот, эътиборсиз қолдирилади).
 *
 * @returns {{rows: Array<{score: number, relevant: (boolean|null)}>}}
 */
function parseLabeledCsv(text) {
  const records = parseCsvRecords(text);
  if (records.length === 0) return { rows: [] };
  const header = records[0].map((h) => h.trim().toLowerCase());
  const si = header.indexOf('score');
  const ri = header.indexOf('relevant');
  if (si < 0) throw new Error('CSV да «score» устуни йўқ');
  if (ri < 0) throw new Error('CSV да «relevant» устуни йўқ (ҳар қаторга ҳа/йўқ ёзинг)');
  const rows = [];
  for (const rec of records.slice(1)) {
    rows.push({ score: Number(rec[si]), relevant: parseRelevant(rec[ri]) });
  }
  return { rows };
}

/**
 * `--min-score` buyruq qiymati: `0.75` (yoki `0,75`) -> 0.75; `off`/`null` -> null.
 * Oraliq [0.01, 1]. «90» (foiz) kabi xatolar RAD etiladi — jim 1 ga qisilmaydi:
 * noto'g'ri chegara push'ni butunlay to'xtatib qo'yishi mumkin.
 */
function parseMinScoreArg(raw) {
  const s = String(raw === undefined || raw === null ? '' : raw).trim().toLowerCase();
  if (s === 'off' || s === 'null') return null;
  const n = Number(s.replace(',', '.'));
  if (s === '' || !Number.isFinite(n) || n < 0.01 || n > 1) {
    throw new Error(
      `--min-score 0.01..1 oralig'ida bo'lishi kerak (masalan 0.75) yoki «off», berilgan: «${s}»`,
    );
  }
  return n;
}

module.exports = {
  suggestThreshold, parseLabeledCsv, parseRelevant, parseMinScoreArg, bucketOf, ceil2,
};
