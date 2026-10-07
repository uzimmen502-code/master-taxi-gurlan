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
ok('QORALAMA (seed): ega narxlari (2026-10-07, AVA_DECIDED) aynan; ichki ulushsiz faol qilib bo\'lmaydi', () => {
  const asDraft = tariff.validateTariff(draft);
  assert.deepStrictEqual(asDraft, [], asDraft.join('; '));
  // Ega jadvali — 6 zona × ≤1/≤3/≤5/≤10/≤20 kg, butun so'm. O'zgartirish —
  // ega qarori (CLAUDE.md 1, 49); admin paneldagi «% ga» tugmasi YANGI
  // versiya ochadi, seed'ni emas.
  assert.deepStrictEqual(draft.weightBrackets, [1000, 3000, 5000, 10000, 20000]);
  assert.deepStrictEqual(draft.prices, {
    ZONE_0: { brackets: [29000, 36000, 43000, 59000, 88000], extraPerKg: 0 },
    ZONE_1: { brackets: [34000, 52000, 69000, 110000, 187000], extraPerKg: 0 },
    ZONE_2: { brackets: [36000, 55000, 74000, 117000, 200000], extraPerKg: 0 },
    ZONE_3: { brackets: [40000, 60000, 80000, 126000, 213000], extraPerKg: 0 },
    ZONE_4: { brackets: [42000, 64000, 85000, 133000, 225000], extraPerKg: 0 },
    ZONE_5: { brackets: [46000, 69000, 92000, 143000, 240000], extraPerKg: 0 },
  });
  // Jadval 20 kg da tugaydi → og'irroq posilka qabul qilinmaydi (20–30 kg
  // narxi UNKNOWN); shuning uchun extraPerKg hech qachon ishlamaydi.
  assert.strictEqual(draft.limits.maxWeightG, 20000);
  const errs = tariff.validateTariff(draft, { forActivation: true });
  assert.ok(!errs.some((e) => e.includes('prices.')), `narx xatosi bo'lmasligi kerak: ${errs.join('; ')}`);
  assert.ok(errs.some((e) => e.includes('legShareBps')), errs.join('; '));
  assert.ok(errs.some((e) => e.includes('platformMarginBps')), errs.join('; '));
});
ok('QORALAMA: ega narxlari bilan kotirovka — Gurlan ichi 1 kg = 29 000, Xorazm→Toshkent 5 kg = 85 000', () => {
  const live = { ...draft, status: 'active', internal: { platformMarginBps: 2000, legShareBps: { first_mile: 2500, line_haul: 5000, last_mile: 2500 } } };
  const q1 = tariff.quoteParcel(live, { actualWeightG: 900, lengthCm: 10, widthCm: 10, heightCm: 10, declaredValue: 0 },
    { regionId: 'xorazm', districtId: 'gurlan' }, { regionId: 'xorazm', districtId: 'gurlan' });
  assert.strictEqual(q1.zone, 'ZONE_0');
  assert.strictEqual(q1.customerPrice, 29000);
  const q2 = tariff.quoteParcel(live, { actualWeightG: 5000, lengthCm: 20, widthCm: 20, heightCm: 20, declaredValue: 0 },
    { regionId: 'xorazm', districtId: 'gurlan' }, { regionId: 'toshkent_shahri', districtId: 'chilonzor' });
  assert.strictEqual(q2.zone, 'ZONE_4');
  assert.strictEqual(q2.customerPrice, 85000);
  // 20 kg dan og'ir — limit (jadval tugagan joy).
  assert.throws(() => tariff.quoteParcel(live, { actualWeightG: 20001, lengthCm: 10, widthCm: 10, heightCm: 10, declaredValue: 0 },
    { regionId: 'xorazm', districtId: 'gurlan' }, { regionId: 'xorazm', districtId: 'gurlan' }), (e) => e.details.reason === 'over_weight');
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

(async () => {
  for (const t of tests) {
    try { await t.fn(); passed += 1; console.log(`  OK  ${t.name}`); } catch (e) {
      console.error(`  XATO ${t.name}\n       ${e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
