/**
 * 13.4.2 — SERVER TOMONI PARITET TESTI (Т-16).
 *
 *   node functions_demand/test/parity.test.js
 *
 * Juftligi: `test/features/demand_offer/demand_parity_test.dart`.
 * Ikkisi AYNI BIR fixturani o'qiydi. Sxema yoki Dart modeli o'zgarsa,
 * biri sinadi — shunda server bir shaklni, ilova boshqasini kutishi
 * mumkin bo'lmaydi (codegen o'rnini bosadigan himoya).
 */
const assert = require('assert');
const path = require('path');
const fs = require('fs');

const schema = require('../core/schema');

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

const fixture = JSON.parse(fs.readFileSync(
  path.join(__dirname, 'fixtures', 'demand_parity.json'), 'utf8',
));

console.log('validInputs — sxemadan O`TISHI kerak');
for (const c of fixture.validInputs) {
  ok(c.name, () => {
    const r = schema.validateCreateDemand(c.payload);
    assert.ok(r.valid, r.errors.join('; '));
  });
}

console.log('invalidInputs — sxemadan O`TMASLIGI kerak');
for (const c of fixture.invalidInputs) {
  ok(`${c.name} (${c.why})`, () => {
    const r = schema.validateCreateDemand(c.payload);
    assert.ok(!r.valid, 'yuklama o`tib ketdi — bu XAVFLI');
  });
}

console.log('docs — hujjat shakli izchilligi');
ok('demand hujjatidagi maydonlar fixtura kutganiga teng', () => {
  const d = fixture.docs.demand.data;
  const e = fixture.docs.demand.expect;
  assert.strictEqual(d.ownerId, e.ownerId);
  assert.strictEqual(d.module, e.module);
  assert.strictEqual(d.mode, e.mode);
  assert.strictEqual(d.status, e.status);
  assert.strictEqual(d.matching.state, e.matchingState);
  assert.strictEqual(d.matching.matchedBucket, e.matchedBucket);
  assert.strictEqual(d.location.regionId, e.locationRegionId);
  assert.strictEqual(d.budget.max, e.budgetMax);
  assert.strictEqual(d.media.images.length, e.imageCount);
  assert.strictEqual(d.attributes.visitType, e.attributeVisitType);
});

ok('Т-8: demand hujjatida aniq `matchedCount` YO`Q', () => {
  // Fixtura ham shu qoidani buzmasligi kerak — aks holda test
  // noto'g'ri narsani qulflab qo'yardi.
  for (const [name, doc] of Object.entries(fixture.docs)) {
    const m = doc.data.matching;
    if (!m) continue;
    assert.strictEqual(
      m.matchedCount, undefined,
      `«${name}» fixturasida matchedCount bor — egasi uni o'qiydi`,
    );
  }
});

ok('MAXFIYLIK: proyeksiyada aniq manzil va telefon YO`Q', () => {
  for (const [name, doc] of Object.entries(fixture.docs)) {
    const p = doc.data.projection;
    if (!p) continue;
    const text = JSON.stringify(p);
    assert.ok(!/15-uy/.test(text), `«${name}»: aniq manzil proyeksiyada`);
    assert.ok(!/3-xonadon/.test(text), `«${name}»: xonadon raqami proyeksiyada`);
    assert.ok(!/998\d{9}/.test(text), `«${name}»: telefon proyeksiyada`);
  }
});

ok('MAXFIYLIK: proyeksiya geohash`i 5 belgidan uzun EMAS', () => {
  for (const [name, doc] of Object.entries(fixture.docs)) {
    const p = doc.data.projection;
    if (!p || !p.geohash) continue;
    assert.ok(
      p.geohash.length <= 5,
      `«${name}»: geohash ${p.geohash.length} belgi — 5 dan uzun bo'lmasligi kerak`,
    );
  }
});

ok('Т-9: 1-pog`onada qabul qiluvchi telefoni YO`Q', () => {
  const c = fixture.docs.match_accepted_stage1.data.contactUnlocked;
  assert.strictEqual(c.stage, 1);
  assert.ok(c.ownerPhone, 'yuboruvchi telefoni ochilishi kerak');
  assert.strictEqual(
    c.recipientPhone, undefined,
    'qabul qiluvchi telefoni 1-pog`onada ochilmasligi SHART',
  );
});

ok('cold start match`ida `consentGiven: false`', () => {
  const d = fixture.docs.match_cold_start_no_consent.data;
  assert.strictEqual(d.consentGiven, false);
  assert.deepStrictEqual(d.sources, ['active_listings']);
});

ok('statuslar state machine jadvalida bor', () => {
  const sm = require('../core/state_machine');
  const valid = new Set(Object.values(sm.STATUS));
  for (const [name, doc] of Object.entries(fixture.docs)) {
    const s = doc.data.status;
    if (!s) continue;
    // `demand_matches` statuslari boshqa to'plam — faqat `demands`ni
    // tekshiramiz.
    if (!name.startsWith('demand')) continue;
    assert.ok(valid.has(s), `«${name}»: «${s}» noma'lum status`);
  }
});

console.log(`\n${passed} test o'tdi.`);
