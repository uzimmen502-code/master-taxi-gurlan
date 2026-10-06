/**
 * `provider_presence` manbasi — `sources/presence_geo.js`.
 *
 *   node functions_demand/test/presence_geo.test.js
 *
 * Nega bu test muhim: `provider_presence` uchun qoida va indeks ANCHADAN
 * BERI bor edi, lekin na yozuvchi, na o'quvchi yozilgan edi
 * (production'da 0 hujjat). Ya'ni bu manba birinchi marta ishga tushyapti
 * va uning har bir chekka holati shu yerda qulflanadi.
 *
 * Alohida tekshiriladigan ikkita nozik joy:
 *   1. KATAK CHEGARASI — talab nuqtasi geohash katagining chetida bo'lsa,
 *      qo'shni katakdagi kuryer TUSHIB QOLMASLIGI kerak
 *      (`geo.neighborPrefixes` aynan shuning uchun bor).
 *   2. `dedupe` da `presence` SAQLANISHI — taklifchi avval
 *      `capabilities`dan tushgan bo'lsa ham, `presence` yo'qolmasligi
 *      kerak, aks holda masofa va ETA umuman hisoblanmaydi.
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const presence = require('../sources/presence_geo');
const orchestrator = require('../matching/orchestrator');
const geo = require('../geo/geo');
const { encode } = require('../geo/geo_hash');
const baseConfig = require('../core/config');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

/** Urganch markazi — talab shu yerda. */
const LAT = 41.5500;
const LNG = 60.6300;

const A = '998901110001';
const B = '998902220002';
const FAR = '998903330003';

const cfg = { ...baseConfig, searchRadiusKm: 15, maxLocationAgeSec: 120 };

function demandAt(lat = LAT, lng = LNG, module = 'courier') {
  return { module, location: { lat, lng } };
}

/** Klient aynan shunday yozadi: to'liq aniqlikdagi geohash. */
function presenceDoc(uid, lat, lng, over = {}) {
  return {
    providerId: uid,
    isOnline: true,
    module: 'courier',
    lat,
    lng,
    geohash: encode(lat, lng, 7),
    vehicle: 'car',
    updatedAt: new Date(),
    ...over,
  };
}

// ─── asosiy oqim ──────────────────────────────────────────────────────
ok('yaqindagi onlayn kuryer topiladi va `presence` biriktiriladi', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc(A, LAT, LNG),
  });
  const res = await presence.fetchCandidates(db, demandAt(), cfg);
  assert.strictEqual(res.length, 1);
  assert.strictEqual(res[0].providerId, A);
  assert.strictEqual(res[0].source, 'presence');
  assert.strictEqual(res[0].presence.lat, LAT);
  assert.strictEqual(res[0].presence.lng, LNG);
  assert.strictEqual(res[0].consentGiven, true, 'onlayn bosgan = rozilik bergan');
});

ok('KATAK CHEGARASI: qo\'shni katakdagi kuryer tushib qolmaydi', async () => {
  // Talab katagining chetini topamiz va undan SAL NARIDAGI nuqtani olamiz —
  // ya'ni kuryer boshqa geohash katagida, lekin bir necha km narida.
  const precision = geo.precisionForRadiusKm(cfg.searchRadiusKm);
  const cell = encode(LAT, LNG, precision);
  // Kuryerni shimolga surib, boshqa katakka tushguncha qadam tashlaymiz.
  let nLat = LAT;
  for (let i = 0; i < 400; i += 1) {
    nLat += 0.01;
    if (encode(nLat, LNG, precision) !== cell) break;
  }
  assert.notStrictEqual(encode(nLat, LNG, precision), cell,
      'test sozlamasi: kuryer boshqa katakda bo\'lishi kerak');

  const db = new FakeFirestore({
    [`provider_presence/${B}`]: presenceDoc(B, nLat, LNG),
  });
  const res = await presence.fetchCandidates(db, demandAt(), cfg);
  assert.strictEqual(res.length, 1, 'qo\'shni katak so\'ralmagan');
  assert.strictEqual(res[0].providerId, B);
});

ok('uzoqdagi kuryer qaytarilmaydi', async () => {
  const db = new FakeFirestore({
    // Toshkent — Urganchdan ~450 km.
    [`provider_presence/${FAR}`]: presenceDoc(FAR, 41.3111, 69.2797),
  });
  const res = await presence.fetchCandidates(db, demandAt(), cfg);
  assert.strictEqual(res.length, 0);
});

// ─── filtrlar ─────────────────────────────────────────────────────────
ok('offline kuryer qaytarilmaydi', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc(A, LAT, LNG, { isOnline: false }),
  });
  assert.strictEqual((await presence.fetchCandidates(db, demandAt(), cfg)).length, 0);
});

ok('boshqa modul qaytarilmaydi', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc(A, LAT, LNG, { module: 'taxi' }),
  });
  assert.strictEqual((await presence.fetchCandidates(db, demandAt(), cfg)).length, 0);
});

ok('ESKIRGAN GPS qaytarilmaydi (isOnline true bo\'lsa ham)', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc(A, LAT, LNG, {
      updatedAt: new Date(Date.now() - 10 * 60 * 1000),
    }),
  });
  const res = await presence.fetchCandidates(db, demandAt(), cfg);
  assert.strictEqual(res.length, 0,
      'ilova yopilgan, sweep hali yetmagan — nomzod bo\'lmasligi kerak');
});

ok('chegaradagi yangilik o\'tadi', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc(A, LAT, LNG, {
      updatedAt: new Date(Date.now() - 60 * 1000),
    }),
  });
  assert.strictEqual((await presence.fetchCandidates(db, demandAt(), cfg)).length, 1);
});

ok('koordinatasiz presence hujjati o\'tkazib yuboriladi', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc(A, LAT, LNG, { lat: null, lng: null }),
  });
  assert.strictEqual((await presence.fetchCandidates(db, demandAt(), cfg)).length, 0);
});

ok('koordinatasiz TALAB uchun manba umuman ishlamaydi', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc(A, LAT, LNG),
  });
  const res = await presence.fetchCandidates(db, { module: 'courier', location: {} }, cfg);
  assert.strictEqual(res.length, 0, 'xato tashlamasligi ham kerak');
});

ok('bir kuryer bir necha prefiksga tushsa ham bir marta qaytadi', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc(A, LAT, LNG),
  });
  const res = await presence.fetchCandidates(db, demandAt(), cfg);
  assert.strictEqual(res.length, 1);
});

// ─── kimlik: faqat hujjat kaliti ──────────────────────────────────────
ok('SOXTA `providerId` MAYDONI inkor qilinadi, kalit ustun', async () => {
  // Kuryer A o'z hujjatiga B ning ID'sini yozib qo'ydi. Qoida buni
  // to'xtatmaydi (`provider_presence/{uid}` faqat KALITni qulflaydi).
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc(A, LAT, LNG, { providerId: B }),
  });
  const res = await presence.fetchCandidates(db, demandAt(), cfg);
  assert.strictEqual(res.length, 1);
  assert.strictEqual(res[0].providerId, A,
      'maydonga ishonilgan — push va tayinlash boshqa odamga ketardi');
});

ok('kanon bo\'lmagan kalitli hujjat o\'tkazib yuboriladi', async () => {
  const db = new FakeFirestore({
    'provider_presence/abc_xyz': presenceDoc(A, LAT, LNG),
  });
  const res = await presence.fetchCandidates(db, demandAt(), cfg);
  assert.strictEqual(res.length, 0, 'matchKey() keyinroq baribir xato tashlardi');
});

ok('9 xonali eski kalit kanon shaklda qaytadi', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A.slice(3)}`]: presenceDoc(A, LAT, LNG),
  });
  const res = await presence.fetchCandidates(db, demandAt(), cfg);
  assert.strictEqual(res.length, 1);
  assert.strictEqual(res[0].providerId, A);
});

ok('fetchForProvider hujjatni qaytaradi', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc(A, LAT, LNG),
  });
  const got = await presence.fetchForProvider(db, A);
  assert.strictEqual(got.id, A);
  assert.strictEqual(got.isOnline, true);
  // 9 xonali shakl bilan ham topiladi.
  assert.strictEqual((await presence.fetchForProvider(db, A.slice(3))).id, A);
  assert.strictEqual(await presence.fetchForProvider(db, 'yo_q'), null);
  assert.strictEqual(db.reads, 2, 'noto\'g\'ri ID uchun Firestore o\'qilmasligi kerak');
});

// ─── dedupe: `presence` yo'qolmasligi ─────────────────────────────────
ok('dedupe `presence`ni SAQLAYDI (capabilities birinchi kelsa ham)', () => {
  const fromCapabilities = [{
    providerId: A, source: 'capabilities', vehicle: 'moto',
    categoryIds: [], categoryGroups: [], regionIds: [], districtIds: [],
    consentGiven: true,
  }];
  const fromPresence = [{
    providerId: A, source: 'presence',
    presence: { lat: LAT, lng: LNG, vehicle: 'car' },
    categoryIds: [], categoryGroups: [], regionIds: [], districtIds: [],
    consentGiven: true,
  }];
  const merged = orchestrator.dedupe([fromCapabilities, fromPresence]);
  assert.strictEqual(merged.length, 1);
  assert.ok(merged[0].presence, '`presence` yo\'qolgan — masofa hisoblanmaydi');
  assert.strictEqual(merged[0].presence.lat, LAT);
  assert.strictEqual(merged[0].sourceCount, 2);
});

ok('saqlangan `presence` bilan masofa va ETA hisoblanadi', () => {
  const merged = orchestrator.dedupe([
    [{
      providerId: A, source: 'capabilities',
      categoryIds: [], categoryGroups: [], regionIds: [], districtIds: [],
    }],
    [{
      providerId: A, source: 'presence',
      presence: { lat: 41.56, lng: 60.64, vehicle: 'car' },
      categoryIds: [], categoryGroups: [], regionIds: [], districtIds: [],
    }],
  ]);
  const m = orchestrator.metricsFor({ location: { lat: LAT, lng: LNG } }, merged[0], cfg);
  assert.ok(Number.isFinite(m.distanceKm), 'masofa hisoblanmadi');
  assert.ok(m.distanceKm > 0 && m.distanceKm < 5, `kutilmagan masofa: ${m.distanceKm}`);
  assert.ok(Number.isFinite(m.etaMinutes), 'ETA hisoblanmadi');
});

// ──────────────────────────────────────────────────────────────────────
(async () => {
  for (const t of tests) {
    try {
      await t.fn();
      passed += 1;
      console.log(`  OK  ${t.name}`);
    } catch (e) {
      console.error(`  XATO ${t.name}\n       ${e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
