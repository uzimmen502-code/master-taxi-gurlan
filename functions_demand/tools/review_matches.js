/**
 * 13.5.4 — ҚЎЛДА ТЕКШИРУВ: «НЕГА МОС?»
 *
 *   node functions_demand/tools/review_matches.js            # 50 тасодифий
 *   node functions_demand/tools/review_matches.js 20         # 20 та
 *   node functions_demand/tools/review_matches.js 50 --csv   # CSV
 *
 * НЕГА БУ ВОСИТА БОР (эга саволи): «номос provider чиқяптими?»
 *
 * Бу саволга рақам жавоб бермайди. `precision: 0.12` деган қиймат
 * «нима учун» деган саволга жавоб эмас. Шунинг учун 50 тасодифий
 * мосликни ОДАМ кўриб, «мантиқан мосми?» деб баҳолаши керак.
 *
 * Воситанинг иши — ўша 50 тани ЎҚИЛАДИГАН шаклда чиқариш:
 *   - талаб матни (нима керак эди)
 *   - таклифчи қайси манбадан топилди
 *   - score ТАРКИБИ (нега мос деб топилди)
 *   - масофа, категория, ҳудуд
 *
 * `scoreParts` майдони айни шу учун `demand_matches`га ёзилади
 * (`matching/orchestrator.js`).
 *
 * ФАҚАТ ЎҚИЙДИ. Ҳеч нарса ёзмайди.
 */
const path = require('path');

const admin = require(path.join(__dirname, '..', 'node_modules', 'firebase-admin'));
const SA = path.join(__dirname, '..', '..', 'functions', 'service-account.json');

function initDb() {
  if (admin.apps.length === 0) {
    // eslint-disable-next-line global-require, import/no-dynamic-require
    admin.initializeApp({ credential: admin.credential.cert(require(SA)) });
  }
  return admin.firestore();
}

/** Fisher–Yates — тасодифий намуна. */
function sample(arr, n) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a.slice(0, n);
}

function fmt(v, width) {
  const s = v === null || v === undefined ? '—' : String(v);
  return width ? s.padEnd(width).slice(0, width) : s;
}

(async () => {
  const limit = Number(process.argv[2]) || 50;
  const asCsv = process.argv.includes('--csv');
  const db = initDb();

  const snap = await db.collection('demand_matches').limit(2000).get();
  if (snap.empty) {
    console.log('demand_matches bo\'sh — shadow mode hali ishlamagan.');
    process.exit(0);
  }

  const picked = sample(snap.docs, limit);

  // Талаб матнини олиш учун `demands` ҳужжатлари керак.
  //
  // ДИҚҚАТ: бу восита АДМИН сифатида ишлайди (service account), шунинг
  // учун тўлиқ талабни ўқийди. Таклифчи эса фақат проекцияни кўради —
  // бу восита қоидаларни четлаб ўтмайди, у умуман илова эмас.
  const demandIds = [...new Set(picked.map((d) => (d.data() || {}).demandId))]
    .filter(Boolean);
  const demands = new Map();
  for (let i = 0; i < demandIds.length; i += 10) {
    const chunk = demandIds.slice(i, i + 10);
    const refs = chunk.map((id) => db.collection('demands').doc(id));
    const docs = await db.getAll(...refs);
    for (const d of docs) if (d.exists) demands.set(d.id, d.data());
  }

  const rows = picked.map((doc) => {
    const m = doc.data() || {};
    const d = demands.get(m.demandId) || {};
    const sp = m.scoreParts || {};
    const metrics = m.metrics || {};
    return {
      key: doc.id,
      demandTitle: (d.title || (d.input || {}).rawText || '').slice(0, 44),
      demandCategory: d.categoryId || '—',
      providerId: m.providerId,
      score: m.score,
      base: sp.base,
      cat: sp.categoryMatch,
      prox: sp.proximity,
      src: sp.sourceStrength,
      boost: sp.newProviderBoost,
      adapter: sp.adapterBonus,
      sources: (m.sources || []).join('+'),
      consent: m.consentGiven === false ? 'NO' : 'yes',
      distKm: metrics.distanceKm,
      region: (m.projection || {}).regionId || '—',
      status: m.status,
    };
  });

  if (asCsv) {
    const cols = Object.keys(rows[0]);
    console.log(cols.join(','));
    for (const r of rows) {
      console.log(cols.map((c) => JSON.stringify(r[c] ?? '')).join(','));
    }
    process.exit(0);
  }

  console.log(`\nJami demand_matches: ${snap.size} (2000 gacha o'qildi)`);
  console.log(`Tasodifiy namuna: ${rows.length}\n`);
  console.log(
    `${fmt('TALAB', 46)}${fmt('KATEGORIYA', 20)}${fmt('score', 8)}`
    + `${fmt('cat', 6)}${fmt('prox', 7)}${fmt('src', 6)}`
    + `${fmt('MANBA', 26)}${fmt('rozi', 6)}${fmt('km', 7)}`,
  );
  console.log('-'.repeat(132));

  for (const r of rows) {
    console.log(
      `${fmt(r.demandTitle, 46)}${fmt(r.demandCategory, 20)}${fmt(r.score, 8)}`
      + `${fmt(r.cat, 6)}${fmt(r.prox, 7)}${fmt(r.src, 6)}`
      + `${fmt(r.sources, 26)}${fmt(r.consent, 6)}${fmt(r.distKm, 7)}`,
    );
  }

  // Хулоса — одам баҳолашдан олдин кўриши учун.
  const byCat = {};
  for (const r of rows) {
    const k = r.cat === 1 ? 'aynan mos (1.0)'
      : (r.cat === 0.7 ? 'qo\'shni (0.7)'
        : (r.cat === 0.4 ? 'faqat modul (0.4)' : `boshqa (${r.cat})`));
    byCat[k] = (byCat[k] || 0) + 1;
  }
  const noConsent = rows.filter((r) => r.consent === 'NO').length;

  console.log('\nKATEGORIYA MOSLIGI TAQSIMOTI:');
  for (const [k, n] of Object.entries(byCat).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${fmt(k, 22)} ${n}`);
  }
  console.log(`\nRozilik bermagan (cold start, push olmagan): ${noConsent}/${rows.length}`);
  console.log(
    '\nBAHOLASH: har qatorni ko\'rib «mantiqan mosmi?» deb belgilang.\n'
    + 'Darvoza: >=90% «mos» bo\'lishi kerak (6-bo\'lim).\n',
  );

  process.exit(0);
})().catch((e) => {
  console.error('XATO:', e.message);
  process.exit(1);
});
