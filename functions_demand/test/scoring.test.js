/**
 * Т-18 — score va fairness.
 *
 *   npm --prefix functions_demand run test:scoring
 *
 * Bu testning markaziy vazifasi KONSEPSIYANING ASOSIY QOIDASINI qulflash:
 * «900 metrdagi kuryer 11 km uzoqdagiga faqat kam ishlagani uchun hech
 *  qachon yutqazmaydi.» Agar kelajakda kimdir fairness vaznini oshirsa,
 * ayni shu test sinadi.
 */
const assert = require('assert');
const sc = require('../matching/scoring');
const { DEFAULTS } = require('../core/config');

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

const cfg = DEFAULTS;

function cand(over = {}) {
  return {
    providerId: '998901234567',
    categoryIds: ['santexnik'],
    categoryGroups: ['uy_tamir'],
    sourceCount: 1,
    trustScore: 50,
    rating: 4,
    todayOrders: 0,
    completedCount: 20,
    ...over,
  };
}

console.log('categoryMatchScore');
ok('aynan mos -> 1.0', () => {
  assert.strictEqual(sc.categoryMatchScore('santexnik', cand()), 1);
});
ok('mos emas -> 0', () => {
  assert.strictEqual(sc.categoryMatchScore('fotograf', cand()), 0);
});
ok('qo`shni kategoriya -> 0.7', () => {
  const c = cand({ categoryIds: ['isitish_tizimi'], demandCategoryGroup: 'uy_tamir' });
  assert.strictEqual(sc.categoryMatchScore('santexnik', c), 0.7);
});
ok('kategoriya belgilanmagan talab -> 0.4', () => {
  assert.strictEqual(sc.categoryMatchScore('', cand()), 0.4);
});
ok('imkoniyati belgilanmagan nomzod -> 0.4', () => {
  assert.strictEqual(sc.categoryMatchScore('santexnik', cand({ categoryIds: [] })), 0.4);
});

console.log('proximityScore');
ok('dispatch: 0 daqiqa -> 1.0', () => {
  assert.strictEqual(sc.proximityScore('dispatch', { etaMinutes: 0 }), 1);
});
ok('dispatch: 30+ daqiqa -> 0', () => {
  assert.strictEqual(sc.proximityScore('dispatch', { etaMinutes: 30 }), 0);
  assert.strictEqual(sc.proximityScore('dispatch', { etaMinutes: 99 }), 0);
});
ok('dispatch: 15 daqiqa -> 0.5', () => {
  assert.ok(Math.abs(sc.proximityScore('dispatch', { etaMinutes: 15 }) - 0.5) < 1e-9);
});
ok('dispatch: ETA yo`q -> 0', () => {
  assert.strictEqual(sc.proximityScore('dispatch', {}), 0);
});
ok('quote: chetlashish 0 km -> 1.0', () => {
  assert.strictEqual(sc.proximityScore('quote', { detourKm: 0 }), 1);
});
ok('quote: chetlashish 20+ km -> 0', () => {
  assert.strictEqual(sc.proximityScore('quote', { detourKm: 25 }), 0);
});
ok('quote: masofa ahamiyatsiz modul -> 0.5', () => {
  assert.strictEqual(sc.proximityScore('quote', {}), 0.5);
});
ok('quote: chetlashish masofadan ustun', () => {
  const r = sc.proximityScore('quote', { detourKm: 2, distanceKm: 500 });
  assert.ok(r > 0.8, `kutilmagan: ${r}`);
});

console.log('sourceStrengthScore');
ok('0 -> 0, 1 -> 0.4, 2 -> 0.7, 3+ -> 1.0', () => {
  assert.strictEqual(sc.sourceStrengthScore(0), 0);
  assert.strictEqual(sc.sourceStrengthScore(1), 0.4);
  assert.strictEqual(sc.sourceStrengthScore(2), 0.7);
  assert.strictEqual(sc.sourceStrengthScore(3), 1);
  assert.strictEqual(sc.sourceStrengthScore(10), 1);
});

console.log('baseScore');
ok('ideal nomzod base ~ 0.76 (3 manba, aynan mos, 0 chetlashish)', () => {
  const r = sc.baseScore(
    { categoryId: 'santexnik', mode: 'quote' },
    cand({ sourceCount: 3 }),
    { detourKm: 0 },
    cfg,
  );
  // 0.4*1 + 0.4*1 + 0.2*1 = 1.0
  assert.ok(Math.abs(r.base - 1) < 1e-9, `base=${r.base}`);
});
ok('mos kelmaydigan kategoriya base`ni keskin tushiradi', () => {
  const r = sc.baseScore(
    { categoryId: 'fotograf', mode: 'quote' },
    cand({ sourceCount: 1 }),
    { detourKm: 0 },
    cfg,
  );
  // 0.4*0 + 0.4*1 + 0.2*0.4 = 0.48
  assert.ok(Math.abs(r.base - 0.48) < 1e-9, `base=${r.base}`);
});
ok('base har doim 0..1', () => {
  const r = sc.baseScore(
    { categoryId: 'santexnik', mode: 'dispatch' },
    cand({ sourceCount: 99 }),
    { etaMinutes: -5 },
    cfg,
  );
  assert.ok(r.base >= 0 && r.base <= 1);
});

console.log('equalizerScore');
ok('bo`sh + ishonchli + yaxshi bahosi -> yuqori', () => {
  const r = sc.equalizerScore(cand({ todayOrders: 0, trustScore: 100, rating: 5 }), cfg);
  assert.ok(r > 0.95, `kutilmagan: ${r}`);
});
ok('band + ishonchsiz -> past', () => {
  const r = sc.equalizerScore(cand({ todayOrders: 8, trustScore: 20, rating: 2 }), cfg);
  assert.ok(r < 0.25, `kutilmagan: ${r}`);
});
ok('bahosi yo`q odam o`rtachadan past hisoblanmaydi', () => {
  const noRating = sc.equalizerScore(cand({ rating: undefined }), cfg);
  const lowRating = sc.equalizerScore(cand({ rating: 2 }), cfg);
  assert.ok(noRating > lowRating, 'yangi odam yomon bahodan past bo`lmasligi kerak');
});
ok('kunlik maqsaddan oshsa loadRelief 0 ga tushadi (manfiy emas)', () => {
  const r = sc.equalizerScore(cand({ todayOrders: 99, trustScore: 0, rating: 0 }), cfg);
  assert.ok(r >= 0, `manfiy: ${r}`);
});

console.log('newProviderBoost');
ok('5 tadan kam bajargan -> boost', () => {
  assert.strictEqual(sc.newProviderBoost(cand({ completedCount: 0 }), cfg), 0.03);
  assert.strictEqual(sc.newProviderBoost(cand({ completedCount: 4 }), cfg), 0.03);
});
ok('5 va undan ko`p -> boost yo`q', () => {
  assert.strictEqual(sc.newProviderBoost(cand({ completedCount: 5 }), cfg), 0);
});

console.log('ASOSIY QOIDA: fairness yaqinlikdan ustun EMAS');
ok('11 km dagi bo`sh kuryer 900 m dagi band kuryerni ORTDA QOLDIRMAYDI', () => {
  const demand = { categoryId: 'santexnik', mode: 'dispatch' };
  const yaqin = sc.scoreCandidate(
    demand,
    cand({ providerId: '998901111111', todayOrders: 8, trustScore: 50, rating: 4 }),
    { etaMinutes: 3 },
    cfg,
  );
  const uzoq = sc.scoreCandidate(
    demand,
    cand({ providerId: '998902222222', todayOrders: 0, trustScore: 100, rating: 5 }),
    { etaMinutes: 28 },
    cfg,
  );
  const ranked = sc.rankCandidates([uzoq, yaqin], cfg, 'dispatch');
  assert.strictEqual(
    ranked[0].providerId, '998901111111',
    'yaqin kuryer birinchi bo`lishi SHART — konsepsiyaning asosiy qoidasi',
  );
});
ok('fairness faqat band ichida ishlaydi', () => {
  const demand = { categoryId: 'santexnik', mode: 'quote' };
  // Ikkisi ham 2 km, base deyarli teng -> bitta guruh.
  const band = sc.scoreCandidate(
    demand, cand({ providerId: '998901111111', todayOrders: 8 }), { detourKm: 2 }, cfg,
  );
  const bosh = sc.scoreCandidate(
    demand, cand({ providerId: '998902222222', todayOrders: 0 }), { detourKm: 2 }, cfg,
  );
  const ranked = sc.rankCandidates([band, bosh], cfg, 'quote');
  assert.strictEqual(
    ranked[0].providerId, '998902222222',
    'teng yaqinlikda kam ishlagan oldinroq turishi kerak',
  );
});
ok('dispatch: ETA farqi 2 daqiqadan kam -> bitta guruh', () => {
  // Konsepsiyada aynan shunday yozilgan.
  const demand = { categoryId: 'santexnik', mode: 'dispatch' };
  const a = sc.scoreCandidate(
    demand, cand({ providerId: '998901111111', todayOrders: 8 }), { etaMinutes: 4 }, cfg,
  );
  const b = sc.scoreCandidate(
    demand, cand({ providerId: '998902222222', todayOrders: 0 }), { etaMinutes: 5 }, cfg,
  );
  const ranked = sc.rankCandidates([a, b], cfg, 'dispatch');
  assert.strictEqual(ranked[0].providerId, '998902222222');
});
ok('fairness vazni oshirilsa ham base farqi katta bo`lsa ta`sir qilmaydi', () => {
  // Himoya: kimdir `maxShift`ni oshirsa ham tartib buzilmasligi kerak,
  // chunki fairness score'ga QO'SHILMAYDI, faqat guruh ichida saralaydi.
  const kuchli = JSON.parse(JSON.stringify(cfg));
  kuchli.equalizer.maxShift = 0.2;
  const demand = { categoryId: 'santexnik', mode: 'dispatch' };
  const yaqin = sc.scoreCandidate(
    demand, cand({ providerId: '998901111111', todayOrders: 8 }), { etaMinutes: 2 }, kuchli,
  );
  const uzoq = sc.scoreCandidate(
    demand, cand({ providerId: '998902222222', todayOrders: 0 }), { etaMinutes: 25 }, kuchli,
  );
  const ranked = sc.rankCandidates([uzoq, yaqin], kuchli, 'dispatch');
  assert.strictEqual(ranked[0].providerId, '998901111111');
});

console.log('rankCandidates — barqarorlik');
ok('teng nomzodlarda tartib BARQAROR (tasodifiy emas)', () => {
  const demand = { categoryId: 'santexnik', mode: 'quote' };
  const a = sc.scoreCandidate(demand, cand({ providerId: '998903333333' }), { detourKm: 1 }, cfg);
  const b = sc.scoreCandidate(demand, cand({ providerId: '998901111111' }), { detourKm: 1 }, cfg);
  const r1 = sc.rankCandidates([a, b], cfg, 'quote').map((x) => x.providerId);
  const r2 = sc.rankCandidates([b, a], cfg, 'quote').map((x) => x.providerId);
  assert.deepStrictEqual(r1, r2, 'bir xil kirish -> bir xil tartib');
});
ok('bo`sh ro`yxat ishlaydi', () => {
  assert.deepStrictEqual(sc.rankCandidates([], cfg, 'quote'), []);
});
ok('bitta nomzod ishlaydi', () => {
  const demand = { categoryId: 'santexnik', mode: 'quote' };
  const a = sc.scoreCandidate(demand, cand(), { detourKm: 1 }, cfg);
  assert.strictEqual(sc.rankCandidates([a], cfg, 'quote').length, 1);
});

console.log('aboveThreshold');
ok('minScore dan past nomzod MOS EMAS', () => {
  const demand = { categoryId: 'fotograf', mode: 'quote' };
  const weak = sc.scoreCandidate(
    demand, cand({ categoryIds: ['santexnik'], sourceCount: 1 }), { detourKm: 19 }, cfg,
  );
  // 0.4*0 + 0.4*0.05 + 0.2*0.4 = 0.10 -> 0.35 dan past
  assert.ok(weak.finalScore < cfg.minScore, `finalScore=${weak.finalScore}`);
  assert.strictEqual(sc.aboveThreshold([weak], cfg).length, 0);
});
ok('chegaradan o`tgan qoladi', () => {
  const demand = { categoryId: 'santexnik', mode: 'quote' };
  const strong = sc.scoreCandidate(demand, cand({ sourceCount: 2 }), { detourKm: 1 }, cfg);
  assert.strictEqual(sc.aboveThreshold([strong], cfg).length, 1);
});

console.log('Т-8 — matchedBucket');
ok('aniq raqam oshkor qilinmaydi', () => {
  assert.strictEqual(sc.matchedBucket(0), '0');
  assert.strictEqual(sc.matchedBucket(1), '1-2');
  assert.strictEqual(sc.matchedBucket(2), '1-2');
  assert.strictEqual(sc.matchedBucket(5), '3-5');
  assert.strictEqual(sc.matchedBucket(10), '6-10');
  assert.strictEqual(sc.matchedBucket(29), '10+');
  assert.strictEqual(sc.matchedBucket(37), '30+');
  assert.strictEqual(sc.matchedBucket(137), '100+');
});
ok('bucket`dan aniq raqamni tiklash mumkin emas', () => {
  // 30..99 oralig'idagi hamma narsa bir xil ko'rinadi.
  const buckets = new Set([30, 37, 55, 99].map(sc.matchedBucket));
  assert.strictEqual(buckets.size, 1);
});
ok('axlat kirish -> 0', () => {
  assert.strictEqual(sc.matchedBucket(null), '0');
  assert.strictEqual(sc.matchedBucket(-5), '0');
  assert.strictEqual(sc.matchedBucket('abc'), '0');
});

console.log(`\n${passed} test o'tdi.`);
