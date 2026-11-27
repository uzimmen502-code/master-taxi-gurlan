/**
 * AVA Logistics tarif dvigateli — sof funksiyalar (D-2, D-8, 12-band).
 *
 *   node functions_demand/test/tariff.test.js
 *
 * Qulflanadi:
 *   - zona FAQAT matritsadan (tuman juftligi ustun, simmetrik)
 *   - hajmiy vazn L×W×H/divisor, chargeable = max — butun gramm
 *   - narx butun so'm; pog'onadan og'ir — qo'shimcha kg
 *   - qoralama tarif NARXSIZ faol qilinmaydi; draft kotirovka bermaydi
 *   - ichki ulush: platforma + LEG haqlari, qoldiq oxirgi LEG'ga
 */
const assert = require('assert');
const path = require('path');
const fs = require('fs');
const tariff = require('../core/tariff');

const fixture = JSON.parse(fs.readFileSync(
  path.join(__dirname, 'fixtures', 'logistics_tariff_test.json'), 'utf8',
));
const draft = JSON.parse(fs.readFileSync(
  path.join(__dirname, '..', 'core', 'seed', 'logistics_tariff_draft.json'), 'utf8',
));
const T = fixture.tariff;

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

// ── validatsiya ──────────────────────────────────────────────────────
ok('test tarifi to\'liq va faol qilishga yaroqli', () => {
  assert.deepStrictEqual(tariff.validateTariff(T), []);
  assert.deepStrictEqual(tariff.validateTariff(T, { forActivation: true }), []);
});
ok('QORALAMA (seed): EGA JADVALI 6 zona × 5 pog\'ona + 1 kg + ulushlar (2026-10-07 kech, AVA_DECIDED) aynan; faol qilishga TAYYOR', () => {
  const asDraft = tariff.validateTariff(draft);
  assert.deepStrictEqual(asDraft, [], asDraft.join('; '));
  // Ega jadvali ≤1/≤3/≤5/≤10/≤20 kg. Ertalabki N=1 (0–21 kg) modeli shu
  // qaror bilan BEKOR. O'zgartirish — ega qarori (CLAUDE.md 1, 49).
  assert.deepStrictEqual(draft.weightBrackets, [1000, 3000, 5000, 10000, 20000]);
  assert.deepStrictEqual(draft.prices, {
    ZONE_0: { brackets: [29000, 36000, 43000, 59000, 88000], extraPerKg: 2500 },
    ZONE_1: { brackets: [34000, 52000, 69000, 110000, 187000], extraPerKg: 6000 },
    ZONE_2: { brackets: [36000, 55000, 74000, 117000, 200000], extraPerKg: null },
    ZONE_3: { brackets: [40000, 60000, 80000, 126000, 213000], extraPerKg: null },
    ZONE_4: { brackets: [42000, 64000, 85000, 133000, 225000], extraPerKg: 8500 },
    ZONE_5: { brackets: [46000, 69000, 92000, 143000, 240000], extraPerKg: null },
  });
  // Maksimal vazn chegarasi YO'Q (ega qarori 2026-10-07): maxWeightG
  // yozilmaydi — og'ir posilka extraPerKg bilan narxlanadi, rad etilmaydi.
  assert.strictEqual(draft.limits.maxWeightG, undefined);
  // O'lcham limitlari INFERRED — ega tasdig'ini kutadi (hozircha turadi).
  assert.deepStrictEqual(draft.limits, { maxDimCm: 150, maxSumDimCm: 300 });
  // Platforma 20 %, qolgan 80 % LEG'larga 25/50/25 (yig'indi 10000 —
  // 20/40/20 rad etiladi). ZONE_2/3/5 +1 kg null — matritsada yo'q, to'sqinlik yo'q.
  assert.deepStrictEqual(draft.internal, {
    platformMarginBps: 2000,
    legShareBps: { first_mile: 2500, line_haul: 5000, last_mile: 2500 },
  });
  const errs = tariff.validateTariff(draft, { forActivation: true });
  assert.deepStrictEqual(errs, [], errs.join('; '));
  const bad = JSON.parse(JSON.stringify(draft));
  bad.internal.legShareBps = { first_mile: 2000, line_haul: 4000, last_mile: 2000 };
  assert.ok(tariff.validateTariff(bad).some((e) => e.includes('yig\'indisi 10000')));
  // Ulush vektorlari (ega misoli): ZONE_4 20 kg 225 000, 3 LEG → 45 000 / 45 000 / 90 000 / 45 000.
  const s = tariff.splitInternal({ ...draft, status: 'active' }, 225000, tariff.legKindsFor(3));
  assert.strictEqual(s.platformShare, 45000);
  assert.deepStrictEqual(s.legPayouts.map((p) => p.amount), [45000, 90000, 45000]);
});
ok('QORALAMA: pog\'onalar chegarasi — 1/1,001/3/5/10/20 kg; hajmiy vazn ustun; 20 kg dan og\'ir — narx yo\'q xatosi (jimgina 0 emas)', () => {
  // Faqat FORMULANI ko'rsatish uchun: status active + ichki ulushlar
  // (seed'ning o'zi o'zgarmaydi).
  const live = {
    ...draft, status: 'active',
    internal: { platformMarginBps: 2000, legShareBps: { first_mile: 2500, line_haul: 5000, last_mile: 2500 } },
  };
  const g = { regionId: 'xorazm', districtId: 'gurlan' };
  const u = { regionId: 'xorazm', districtId: 'urganch_shahri' };
  const t = { regionId: 'toshkent_shahri', districtId: 'chilonzor' };
  const qg = (grams, from, to, dims = [10, 10, 10]) => tariff.quoteParcel(live,
    { actualWeightG: grams, lengthCm: dims[0], widthCm: dims[1], heightCm: dims[2], declaredValue: 0 }, from, to);
  const q = (kg, from, to, dims) => qg(kg * 1000, from, to, dims);

  // ZONE_0 (Gurlan ichi) — har pog'ona chegarasi o'z ustunida.
  assert.strictEqual(q(1, g, g).customerPrice, 29000);
  assert.strictEqual(qg(1001, g, g).customerPrice, 36000, '1,001 kg → ≤3 kg');
  assert.strictEqual(q(3, g, g).customerPrice, 36000);
  assert.strictEqual(q(5, g, g).customerPrice, 43000);
  assert.strictEqual(q(10, g, g).customerPrice, 59000);
  assert.strictEqual(q(20, g, g).customerPrice, 88000);
  // ZONE_1 (Gurlan → Urganch, tuman juftligi yo'q → viloyat).
  assert.strictEqual(q(3, g, u).zone, 'ZONE_1');
  assert.strictEqual(q(3, g, u).customerPrice, 52000);
  assert.strictEqual(q(20, g, u).customerPrice, 187000);
  // ZONE_4 (Xorazm → Toshkent).
  assert.strictEqual(q(5, g, t).customerPrice, 85000);
  assert.strictEqual(q(10, g, t).customerPrice, 133000);
  // Hajmiy vazn: haqiqiy 2 kg, 30×30×30 → 27 000 cm³ / 6000 = 4,5 kg → ≤5 kg.
  const vol = q(2, g, g, [30, 30, 30]);
  assert.strictEqual(vol.volumetricWeightG, 4500);
  assert.strictEqual(vol.customerPrice, 43000);
  // 20 kg dan og'ir — har BOSHLANGAN kg × extraPerKg (ega: ZONE_0 2 500, ZONE_4 8 500).
  assert.strictEqual(qg(20001, g, g).customerPrice, 88000 + 2500, '20,001 kg → +1');
  assert.strictEqual(q(25, g, g).customerPrice, 88000 + 5 * 2500);
  assert.strictEqual(q(25, g, t).customerPrice, 225000 + 5 * 8500);
  // Hajmiy 25 kg (haqiqiy 8 kg, 50×60×50) → +5 kg.
  assert.strictEqual(q(8, g, g, [50, 60, 50]).customerPrice, 88000 + 5 * 2500);
  // +1 kg narxi yo'q bo'lsa → typed xato, 88 000 EMAS (jimgina 0 yo'q).
  const noExtra = JSON.parse(JSON.stringify(live));
  noExtra.prices.ZONE_0.extraPerKg = null;
  assert.throws(() => tariff.quoteParcel(noExtra, { actualWeightG: 20001, lengthCm: 10, widthCm: 10, heightCm: 10 }, g, g),
    (e) => e.details.reason === 'tariff_extra_price_missing');
  const withExtra = live;
  // Limit qo'yilsa — HAQIQIY vaznga ishlaydi (hajmiy vaznga emas).
  const limited = { ...withExtra, limits: { ...withExtra.limits, maxWeightG: 20000 } };
  assert.strictEqual(tariff.quoteParcel(limited, { actualWeightG: 8000, lengthCm: 50, widthCm: 60, heightCm: 50 }, g, g).customerPrice, 88000 + 5 * 2500);
  assert.throws(() => tariff.quoteParcel(limited, { actualWeightG: 21000, lengthCm: 10, widthCm: 10, heightCm: 10 }, g, g),
    (e) => e.details.reason === 'over_weight');
});
ok('extraPerKg: qoralamada null mumkin; faol qilishda chegara yo\'q bo\'lsa SHART; 0 — ataylab qaror; manfiy/float rad', () => {
  const base = JSON.parse(JSON.stringify(T));
  const n = JSON.parse(JSON.stringify(base)); n.prices.ZONE_0.extraPerKg = null;
  assert.deepStrictEqual(tariff.validateTariff(n), []);
  const needs = (doc) => tariff.validateTariff(doc, { forActivation: true }).some((e) => e.includes('prices.ZONE_0.extraPerKg'));
  // T: maxWeightG 30000 > oxirgi pog'ona 20000 → 20–30 kg extra bilan → SHART.
  assert.ok(needs(n));
  // Chegara yo'q → SHART.
  const noLimit = JSON.parse(JSON.stringify(n)); delete noLimit.limits.maxWeightG;
  assert.ok(needs(noLimit));
  // Chegara = oxirgi pog'ona → og'irrog'i qabul qilinmaydi → talab yo'q.
  const capped = JSON.parse(JSON.stringify(n)); capped.limits.maxWeightG = 20000;
  assert.ok(!needs(capped));
  // 0 — ataylab «qo'shimcha haq yo'q» qarori, qabul.
  const zero = JSON.parse(JSON.stringify(noLimit)); zero.prices.ZONE_0.extraPerKg = 0;
  assert.deepStrictEqual(tariff.validateTariff(zero, { forActivation: true }), []);
  const neg = JSON.parse(JSON.stringify(base)); neg.prices.ZONE_0.extraPerKg = -1;
  assert.ok(tariff.validateTariff(neg).some((e) => e.includes('extraPerKg')));
  const fl = JSON.parse(JSON.stringify(base)); fl.prices.ZONE_0.extraPerKg = 2500.5;
  assert.ok(tariff.validateTariff(fl).some((e) => e.includes('extraPerKg')));
});
ok('6 ta zona aynan ZONE_0…ZONE_5 (D-2); boshqa nom rad', () => {
  const bad = { ...T, zones: ['Z1', 'Z2', 'Z3', 'Z4', 'Z5'] };
  assert.ok(tariff.validateTariff(bad).some((e) => e.includes('6 zona')));
  const bad2 = JSON.parse(JSON.stringify(T));
  bad2.matrix.regions.xorazm.xorazm = 'Z3';
  assert.ok(tariff.validateTariff(bad2).some((e) => e.includes('noma\'lum zona')));
});
ok('pog\'onalar o\'sish tartibida; narx pog\'onalari soni mos; ulushlar 10000', () => {
  const b = JSON.parse(JSON.stringify(T)); b.weightBrackets = [1000, 900];
  assert.ok(tariff.validateTariff(b).some((e) => e.includes('oldingisidan katta')));
  const p = JSON.parse(JSON.stringify(T)); p.prices.ZONE_1.brackets = [1, 2];
  assert.ok(tariff.validateTariff(p).some((e) => e.includes('uzunligi')));
  const s = JSON.parse(JSON.stringify(T)); s.internal.legShareBps.last_mile = 3000;
  assert.ok(tariff.validateTariff(s).some((e) => e.includes('yig\'indisi 10000')));
  const f = JSON.parse(JSON.stringify(T)); f.prices.ZONE_1.brackets[0] = 15000.5;
  assert.ok(tariff.validateTariff(f).some((e) => e.includes('butun so\'m')), 'float narx rad (8-band)');
});

// ── zona ─────────────────────────────────────────────────────────────
ok('zona matritsadan: tuman juftligi viloyatdan USTUN', () => {
  assert.strictEqual(tariff.resolveZone(T, { regionId: 'xorazm', districtId: 'gurlan' }, { regionId: 'xorazm', districtId: 'gurlan' }), 'ZONE_0');
  assert.strictEqual(tariff.resolveZone(T, { regionId: 'xorazm', districtId: 'xonqa' }, { regionId: 'xorazm', districtId: 'shovot' }), 'ZONE_1');
});
ok('simmetrik: teskari yo\'nalish ham topiladi; `symmetric:false` da topilmaydi', () => {
  assert.strictEqual(tariff.resolveZone(T, { regionId: 'toshkent_shahri' }, { regionId: 'xorazm' }), 'ZONE_4');
  const asym = JSON.parse(JSON.stringify(T)); asym.matrix.symmetric = false;
  assert.strictEqual(tariff.resolveZone(asym, { regionId: 'toshkent_shahri' }, { regionId: 'xorazm' }), null);
});
ok('matritsada yo\'q yo\'nalish — null (zona «ma\'nosi» kodga yozilmaydi)', () => {
  assert.strictEqual(tariff.resolveZone(T, { regionId: 'xorazm' }, { regionId: 'andijon' }), null);
  assert.strictEqual(tariff.resolveZone(T, {}, {}), null);
});

// ── vazn ─────────────────────────────────────────────────────────────
ok('hajmiy vazn: 50×40×40 / 6000 = 13.333 kg → 13334 g (yuqoriga, butun)', () => {
  assert.strictEqual(tariff.volumetricWeightG(50, 40, 40, 6000), 13334);
  assert.strictEqual(tariff.volumetricWeightG(10, 10, 10, 6000), 167);
  assert.strictEqual(tariff.volumetricWeightG(0, 10, 10, 6000), 0);
});
ok('chargeable = max(actual, volumetric)', () => {
  assert.strictEqual(tariff.chargeableWeightG(5000, 13334), 13334);
  assert.strictEqual(tariff.chargeableWeightG(800, 500), 800);
});
ok('pog\'ona indeksi: chegaraga TENG bo\'lsa shu pog\'ona; hammasidan og\'ir -1', () => {
  assert.strictEqual(tariff.bracketIndex(T, 1000), 0);
  assert.strictEqual(tariff.bracketIndex(T, 1001), 1);
  assert.strictEqual(tariff.bracketIndex(T, 20000), 4);
  assert.strictEqual(tariff.bracketIndex(T, 20001), -1);
});
ok('og\'ir: 23 500 g ZONE_1 → 56 000 + ceil(3.5)=4 kg × 2 500 = 66 000', () => {
  assert.strictEqual(tariff.basePriceFor(T, 'ZONE_1', 23500), 66000);
  assert.strictEqual(tariff.basePriceFor(T, 'ZONE_1', 20001), 56000 + 2500);
});

// ── kotirovka vektorlari (Dart paritet manbasi) ───────────────────────
ok('fixture vektorlari — snapshot maydonlari', () => {
  for (const v of fixture.vectors) {
    const q = tariff.quoteParcel(T, v.parcel, v.origin, v.dest);
    for (const [k, val] of Object.entries(v.expect)) {
      assert.strictEqual(q[k], val, `${v.name}.${k}: ${q[k]} !== ${val}`);
    }
    assert.strictEqual(q.tariffVersion, T.version);
    assert.ok(Number.isInteger(q.customerPrice));
  }
});
ok('e\'lon qilingan qiymat haqi: ceil(1 234 567 × 1%) = 12 346', () => {
  assert.strictEqual(tariff.declaredValueFee(T, 1234567), 12346);
  assert.strictEqual(tariff.declaredValueFee(T, 0), 0);
});
ok('draft tarif KOTIROVKA BERMAYDI (tariff_not_active)', () => {
  const d = { ...T, status: 'draft' };
  assert.throws(() => tariff.quoteParcel(d, fixture.vectors[0].parcel, fixture.vectors[0].origin, fixture.vectors[0].dest),
    (e) => e.code === 'failed-precondition' && e.details.reason === 'tariff_not_active');
});
ok('noto\'g\'ri kirish: float vazn, 0 o\'lcham, chegaradan oshish — aniq sabab bilan rad', () => {
  const o = { regionId: 'xorazm', districtId: 'gurlan' };
  const bad = (parcel, reason) => assert.throws(
    () => tariff.quoteParcel(T, parcel, o, o), (e) => e.details.reason === reason, reason,
  );
  bad({ actualWeightG: 1.5, lengthCm: 1, widthCm: 1, heightCm: 1 }, 'bad_weight');
  bad({ actualWeightG: 100, lengthCm: 0, widthCm: 1, heightCm: 1 }, 'bad_dimensions');
  bad({ actualWeightG: 31000, lengthCm: 1, widthCm: 1, heightCm: 1 }, 'over_weight');
  bad({ actualWeightG: 100, lengthCm: 151, widthCm: 1, heightCm: 1 }, 'over_dimension');
  bad({ actualWeightG: 100, lengthCm: 120, widthCm: 120, heightCm: 120 }, 'over_dimension_sum');
  bad({ actualWeightG: 100, lengthCm: 1, widthCm: 1, heightCm: 1, declaredValue: 60000000 }, 'over_declared_value');
  assert.throws(() => tariff.quoteParcel(T, { actualWeightG: 100, lengthCm: 1, widthCm: 1, heightCm: 1 }, { regionId: 'xorazm' }, { regionId: 'andijon' }),
    (e) => e.details.reason === 'zone_not_found');
});

// ── ichki qatlam ─────────────────────────────────────────────────────
ok('LEG turlari: 1 direct; 2 first+last; 3 first+line+last; 4 first+line+line+last', () => {
  assert.deepStrictEqual(tariff.legKindsFor(1), ['direct']);
  assert.deepStrictEqual(tariff.legKindsFor(2), ['first_mile', 'last_mile']);
  assert.deepStrictEqual(tariff.legKindsFor(3), ['first_mile', 'line_haul', 'last_mile']);
  assert.deepStrictEqual(tariff.legKindsFor(4), ['first_mile', 'line_haul', 'line_haul', 'last_mile']);
  assert.deepStrictEqual(tariff.legKindsFor(0), []);
});
ok('ulush vektorlari: butun so\'m, Σ = providerPool, qoldiq oxirgi LEG\'ga', () => {
  for (const v of fixture.splitVectors) {
    const r = tariff.splitInternal(T, v.customerPrice, tariff.legKindsFor(v.legs));
    assert.strictEqual(r.platformShare, v.expect.platformShare, `${v.customerPrice}/${v.legs} platform`);
    assert.strictEqual(r.providerPool, v.expect.providerPool);
    assert.deepStrictEqual(r.legPayouts.map((l) => l.amount), v.expect.legPayouts, `${v.customerPrice}/${v.legs}`);
    assert.strictEqual(r.platformShare + r.legPayouts.reduce((s, l) => s + l.amount, 0), v.customerPrice, 'pul yo\'qolmaydi');
  }
});
ok('2 ta LEG: line_haul yo\'q — ulush mavjudlar orasida normallashadi', () => {
  const r = tariff.splitInternal(T, 80000, ['first_mile', 'last_mile']);
  assert.deepStrictEqual(r.legPayouts.map((l) => l.amount), [32000, 32000]);
});

// ─── Audit L15 (2026-10-16): e'lon qiymati haqi butun son chegarasidan chiqmasin ───
ok('L15: faol qilish — haq sozlangan bo\'lsa declaredValue.maxValue SHART (musbat butun)', () => {
  const base = JSON.parse(JSON.stringify(T));
  assert.deepStrictEqual(tariff.validateTariff(base, { forActivation: true }), [], 'asos tarif yaroqli');
  // maxValue yo'q + feeBps>0 -> rad
  const noMax = JSON.parse(JSON.stringify(base));
  delete noMax.declaredValue.maxValue;
  const e1 = tariff.validateTariff(noMax, { forActivation: true });
  assert.ok(e1.some((m) => /declaredValue\.maxValue/.test(m)), `maxValue talab qilinishi kerak: ${e1}`);
  // QORALAMA (forActivation:false) maxValue'siz ham yaroqli (ega hali to'ldirmagan)
  assert.deepStrictEqual(tariff.validateTariff(noMax), []);
  // float / 0 / manfiy / satr -> rad
  for (const bad of [1.5, 0, -5, '50000000']) {
    const t2 = JSON.parse(JSON.stringify(base));
    t2.declaredValue.maxValue = bad;
    assert.ok(tariff.validateTariff(t2, { forActivation: true }).some((m) => /declaredValue\.maxValue/.test(m)), `rad: ${bad}`);
  }
  // maxValue × feeBps xavfsiz butun sondan oshsa -> rad
  const big = JSON.parse(JSON.stringify(base));
  big.declaredValue.maxValue = Number.MAX_SAFE_INTEGER;
  big.declaredValue.feeBps = 100;
  assert.ok(tariff.validateTariff(big, { forActivation: true }).some((m) => /declaredValue/.test(m)), 'maxValue*feeBps > MAX_SAFE_INTEGER rad');
  // haq sozlanmagan (feeBps yo'q yoki 0) -> maxValue shart emas
  const noFee = JSON.parse(JSON.stringify(base));
  noFee.declaredValue = {};
  assert.deepStrictEqual(tariff.validateTariff(noFee, { forActivation: true }), []);
  const zeroFee = JSON.parse(JSON.stringify(base));
  zeroFee.declaredValue = { feeBps: 0 };
  assert.deepStrictEqual(tariff.validateTariff(zeroFee, { forActivation: true }), []);
});

ok('L15: declaredValueFee — v × bps xavfsiz butun sondan oshsa jim noto\'g\'ri son EMAS, aniq xato', () => {
  const t = { declaredValue: { feeBps: 100 } }; // maxValue yo'q (eski/qo'lda yozilgan hujjat)
  assert.strictEqual(tariff.declaredValueFee(t, 1234567), 12346, 'oddiy qiymat o\'zgarmaydi');
  const edge = Math.floor(Number.MAX_SAFE_INTEGER / 100);
  assert.ok(Number.isSafeInteger(tariff.declaredValueFee(t, edge)), 'chegarada hisoblanadi');
  assert.throws(() => tariff.declaredValueFee(t, edge + 1),
    (e) => e.code === 'failed-precondition' && e.details.reason === 'over_declared_value');
});

(async () => {
  for (const t of tests) {
    try { await t.fn(); passed += 1; console.log(`  OK  ${t.name}`); } catch (e) {
      console.error(`  XATO ${t.name}\n       ${e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
