'use strict';

/**
 * Т-18 — SCORE VA FAIRNESS.
 *
 * Konsepsiyada formula TASVIRLANGAN, lekin birorta raqam berilmagan —
 * shunday holatda joriy etib bo'lmaydi. Barcha vaznlar `core/config.js`da,
 * bu fayl faqat hisob mantiqini ushlab turadi.
 *
 * ENG MUHIM QOIDA (konsepsiyadan):
 *   «Tenglashtiruvchi qism faqat asosiy qismlari yaqin bo'lgan nomzodlar
 *    orasida ishlaydi. Shunda 900 metrdagi kuryer 11 km uzoqdagi kuryerga
 *    faqat kam ishlagani uchun hech qachon yutqazmaydi.»
 *
 * Shuning uchun fairness `base` score'ga QO'SHILMAYDI, balki faqat
 * `band` (0.05) oralig'idagi nomzodlarni o'zaro saralashda ishlaydi va
 * `maxShift` (0.05) bilan qattiq chegaralangan. Test bu xususiyatni
 * aniq qulflaydi: uzoqdagi bo'sh kuryer yaqindagi band kuryerni
 * HECH QACHON ortda qoldirmaydi.
 */

/** 0..1 oralig'iga qisadi. */
function clamp01(v) {
  if (!Number.isFinite(v)) return 0;
  return Math.max(0, Math.min(1, v));
}

/**
 * Kategoriya mosligi (0..1).
 *
 *   1.00 — aynan shu kategoriya
 *   0.70 — bir guruhdagi qo'shni kategoriya (santexnik <-> isitish_tizimi)
 *   0.40 — faqat modul mos (kategoriya belgilanmagan)
 *   0.00 — mos emas
 */
function categoryMatchScore(demandCategoryId, candidate) {
  if (!demandCategoryId) return 0.4;
  const own = candidate.categoryIds || [];
  if (own.includes(demandCategoryId)) return 1;
  const groups = candidate.categoryGroups || [];
  if (candidate.demandCategoryGroup && groups.includes(candidate.demandCategoryGroup)) {
    return 0.7;
  }
  return own.length === 0 ? 0.4 : 0;
}

/**
 * Yaqinlik (0..1).
 *
 * dispatch: ETA bo'yicha (30 daqiqadan uzoq -> 0)
 * quote:    chetlashish yoki masofa bo'yicha (20 km dan uzoq -> 0)
 *
 * Nega chiziqli, nega eksponensial emas: shadow mode'gacha hech qanday
 * o'lchov yo'q, chiziqli eng tushunarli va sozlashga oson. O'lchovdan
 * keyin o'zgartirish mumkin.
 */
function proximityScore(mode, metrics) {
  if (mode === 'dispatch') {
    const eta = Number(metrics.etaMinutes);
    if (!Number.isFinite(eta)) return 0;
    return clamp01(1 - (Math.min(eta, 30) / 30));
  }
  const km = Number.isFinite(metrics.detourKm)
    ? metrics.detourKm
    : metrics.distanceKm;
  if (!Number.isFinite(km)) return 0.5; // masofa ahamiyatsiz bo'lgan modul
  return clamp01(1 - (Math.min(km, 20) / 20));
}

/**
 * Manba kuchi (0..1) — nechta mustaqil manbadan topilgani.
 *
 * Konsepsiya: «Score'ga manbalar soni ijobiy ta'sir qiladi.» Mantiq:
 * ham aktiv e'loni bor, ham imkoniyat belgilagan, ham yaqinda shu ishni
 * qilgan odam tasodifiy mos keluvchidan ishonchliroq.
 */
function sourceStrengthScore(sourceCount) {
  const n = Math.max(0, Math.floor(Number(sourceCount) || 0));
  if (n <= 0) return 0;
  if (n === 1) return 0.4;
  if (n === 2) return 0.7;
  return 1;
}

/**
 * Asosiy (samaradorlik) score — 0..1.
 *
 * Fairness bu yerda YO'Q va bo'lishi ham mumkin emas.
 */
function baseScore(demand, candidate, metrics, config) {
  const w = config.weights;
  const cat = categoryMatchScore(demand.categoryId, candidate);
  const prox = proximityScore(demand.mode, metrics);
  const src = sourceStrengthScore(candidate.sourceCount);
  const s = (w.categoryMatch * cat) + (w.proximity * prox) + (w.sourceStrength * src);
  return {
    base: clamp01(s),
    parts: { categoryMatch: cat, proximity: prox, sourceStrength: src },
  };
}

/**
 * Tenglashtiruvchi qism — 0..1 (keyin `maxShift`ga ko'paytiriladi).
 *
 * Uch komponent:
 *   todayOrders — bugun kam ishlagan oldinroq (asosiy fairness richagi)
 *   trust       — ishonchli oldinroq
 *   rating      — mijozlar yaxshi baholagan oldinroq
 */
function equalizerScore(candidate, config) {
  const eq = config.equalizer;
  const target = Math.max(1, eq.dailyOrderTarget);
  const today = Math.max(0, Number(candidate.todayOrders) || 0);
  const loadRelief = clamp01(1 - (today / target));

  const trust = clamp01((Number(candidate.trustScore) || config.trust.initial) / 100);
  const rating = Number.isFinite(candidate.rating)
    ? clamp01(candidate.rating / 5)
    : 0.6; // bahosi yo'q odamni o'rtachadan past deb hisoblamaslik uchun

  return clamp01(
    (eq.todayOrdersWeight * loadRelief)
    + (eq.trustWeight * trust)
    + (eq.ratingWeight * rating),
  );
}

/** Cold start yordami — faqat yangi taklifchiga. */
function newProviderBoost(candidate, config) {
  const np = config.newProvider;
  const completed = Math.max(0, Number(candidate.completedCount) || 0);
  return completed < np.completedThreshold ? np.scoreBoost : 0;
}

/**
 * Bitta nomzod uchun to'liq score.
 *
 * `finalScore` = base + newProviderBoost. Fairness BU YERDA QO'SHILMAYDI —
 * u faqat `rankCandidates` ichida, `band` oralig'idagilar o'zaro
 * saralanayotganda ishlaydi.
 */
function scoreCandidate(demand, candidate, metrics, config) {
  const { base, parts } = baseScore(demand, candidate, metrics, config);
  const boost = newProviderBoost(candidate, config);
  const equalizer = equalizerScore(candidate, config);
  return {
    providerId: candidate.providerId,
    base,
    boost,
    equalizer,
    finalScore: clamp01(base + boost),
    parts,
    metrics,
  };
}

/**
 * Nomzodlarni tartiblash — KONSEPSIYANING ENG MUHIM QOIDASI SHU YERDA.
 *
 * Avval `finalScore` bo'yicha kamayish tartibida. Keyin: ketma-ket
 * turgan va farqi `band`dan kichik bo'lgan nomzodlar BITTA GURUH
 * hisoblanadi va guruh ICHIDA `equalizer` bo'yicha qayta saralanadi.
 *
 * Shunda:
 *   - 900 m dagi band kuryer (base 0.90) va 11 km dagi bo'sh kuryer
 *     (base 0.40) — turli guruhda, fairness ta'sir qilmaydi;
 *   - ikkita 900 m dagi kuryer (base 0.90 va 0.88) — bitta guruhda,
 *     kam ishlagani oldinroq turadi.
 *
 * dispatch rejimida qo'shimcha: ETA farqi 2 daqiqadan kam bo'lsa ham
 * bitta guruh (konsepsiyada aniq shunday yozilgan).
 */
function rankCandidates(scored, config, mode) {
  const band = config.equalizer.band;
  const sorted = [...scored].sort((a, b) => b.finalScore - a.finalScore);

  /** @type {Array<Array<object>>} */
  const groups = [];
  for (const item of sorted) {
    const g = groups[groups.length - 1];
    if (!g) { groups.push([item]); continue; }
    const head = g[0];
    const scoreClose = (head.finalScore - item.finalScore) <= band;
    const etaClose = mode === 'dispatch'
      && Number.isFinite(head.metrics.etaMinutes)
      && Number.isFinite(item.metrics.etaMinutes)
      && Math.abs(head.metrics.etaMinutes - item.metrics.etaMinutes) <= 2;
    if (scoreClose || etaClose) g.push(item);
    else groups.push([item]);
  }

  const out = [];
  for (const g of groups) {
    g.sort((a, b) => {
      const d = b.equalizer - a.equalizer;
      if (Math.abs(d) > 1e-9) return d;
      // Teng bo'lsa barqaror tartib: providerId bo'yicha (tasodifiy emas,
      // aks holda har qayta hisoblashda tartib o'zgarib, tahlil buzilardi).
      return String(a.providerId).localeCompare(String(b.providerId));
    });
    out.push(...g);
  }
  return out;
}

/** Chegaradan o'tganlar (mos deb hisoblanadiganlar). */
function aboveThreshold(scored, config) {
  return scored.filter((s) => s.finalScore >= config.minScore);
}

/**
 * Т-8 — MATCHEDCOUNT ZIDDIYATI.
 *
 * Konsepsiya: haridor UI'da «30+» ko'radi, lekin `matchedCount: 37` hujjatda
 * yozilgan va hujjatni haridorning O'ZI o'qiydi -> aniq raqam oshkor.
 * Yechim: hujjatda faqat BUCKET, aniq raqam `demands/{id}/private/stats`da.
 */
function matchedBucket(n) {
  const c = Math.max(0, Math.floor(Number(n) || 0));
  if (c === 0) return '0';
  if (c <= 2) return '1-2';
  if (c <= 5) return '3-5';
  if (c <= 10) return '6-10';
  if (c < 30) return '10+';
  if (c < 100) return '30+';
  return '100+';
}

module.exports = {
  clamp01,
  categoryMatchScore,
  proximityScore,
  sourceStrengthScore,
  baseScore,
  equalizerScore,
  newProviderBoost,
  scoreCandidate,
  rankCandidates,
  aboveThreshold,
  matchedBucket,
};
