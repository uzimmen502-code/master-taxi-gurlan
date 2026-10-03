/**
 * 13.2.2 + 13.2.3 — `createDemand` va `runMatching` BIRGA.
 *
 *   node functions_demand/test/matching.test.js
 *
 * Qabul mezonlari shu yerda tekshiriladi:
 *   13.2.2 «Ikki marta tap -> bitta `demands` hujjati»
 *   13.2.3 «Egasi o'zi nomzod bo'lmaydi», proyeksiya maxfiyligi,
 *          `matchedBucket` (aniq raqam oshkor emas), cold start.
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const { makeCreateDemand } = require('../api/create_demand');
const orchestrator = require('../matching/orchestrator');
const kw = require('../core/keywords');
const taxonomy = require('../core/seed/taxonomy_services.json');
const config = require('../core/config');
const serviceAdapter = require('../adapters/service');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const keywordIndex = kw.buildIndex(taxonomy);
const OWNER = '998901110001';
const USTA_A = '998902220002';
const USTA_B = '998903330003';

/** Standart urug': yoqilgan modul + egasi profili. */
function seed(extra = {}) {
  return {
    'module_config/global': { enabled: true, matchingEnabled: true, pushEnabled: true },
    'module_config/service_xorazm': {
      enabled: true, matchingEnabled: true, pushEnabled: true,
    },
    [`users/${OWNER}`]: { regionId: 'xorazm', districtId: 'urganch_sh', name: 'Mijoz' },
    ...extra,
  };
}

function capability(uid, over = {}) {
  return {
    providerId: uid,
    module: 'service',
    active: true,
    categoryIds: ['santexnik'],
    categoryGroups: ['uy_tamir'],
    regionIds: ['xorazm'],
    districtIds: ['urganch_sh'],
    ...over,
  };
}

function payload(over = {}) {
  return {
    module: 'service',
    clientRequestId: 'req-test-0001',
    categoryId: 'santexnik',
    input: { type: 'form' },
    title: 'Kran oqyapti',
    location: { lat: 41.55, lng: 60.63, addressText: 'Al-Xorazmiy 15-uy' },
    attributes: { visitType: 'at_my_place' },
    ...over,
  };
}

const ctx = { auth: { token: { phone_number: `+${OWNER}` } } };

function build(db, opts = {}) {
  config.clearCache();
  return makeCreateDemand({
    db, admin: null, keywordIndex, ...opts,
  });
}

// ─────────────────────────────────────────────────────────────────────
ok('talab yaratiladi va matching ishlaydi', async () => {
  const db = new FakeFirestore(seed({
    [`provider_capabilities/${USTA_A}_service`]: capability(USTA_A),
    [`provider_stats/${USTA_A}`]: { trustScore: 60, completedCount: 10, rating: 4.5 },
  }));
  const createDemand = build(db);
  const r = await createDemand(payload(), ctx);

  assert.ok(r.demandId, 'demandId qaytmadi');
  assert.strictEqual(r.duplicate, false);
  assert.strictEqual(r.matchingState, 'done', JSON.stringify(r));

  const demands = db.dump('demands');
  assert.strictEqual(Object.keys(demands).length, 1);
  const d = demands[r.demandId];
  assert.strictEqual(d.ownerId, OWNER);
  assert.strictEqual(d.status, 'active');
  assert.strictEqual(d.mode, 'quote', 'rejim adapterdan olinishi kerak');

  const matches = db.dump('demand_matches');
  assert.strictEqual(Object.keys(matches).length, 1);
  const m = matches[`${r.demandId}_${USTA_A}`];
  assert.ok(m, `kalit topilmadi: ${Object.keys(matches).join(', ')}`);
  assert.strictEqual(m.providerId, USTA_A, 'providerId MAYDON sifatida bo`lishi SHART (Т-2.1)');
});

ok('QABUL MEZONI 13.2.2: ikki marta tap -> bitta talab', async () => {
  const db = new FakeFirestore(seed({
    [`provider_capabilities/${USTA_A}_service`]: capability(USTA_A),
  }));
  const createDemand = build(db);
  const r1 = await createDemand(payload(), ctx);
  const r2 = await createDemand(payload(), ctx);

  assert.strictEqual(r2.duplicate, true, 'ikkinchi chaqiruv dublikat deb belgilanishi kerak');
  assert.strictEqual(r1.demandId, r2.demandId, 'bir xil demandId qaytishi kerak');
  assert.strictEqual(Object.keys(db.dump('demands')).length, 1);
});

ok('boshqa clientRequestId -> yangi talab', async () => {
  const db = new FakeFirestore(seed({
    [`provider_capabilities/${USTA_A}_service`]: capability(USTA_A),
  }));
  const createDemand = build(db);
  await createDemand(payload({ clientRequestId: 'req-test-0001' }), ctx);
  await createDemand(payload({ clientRequestId: 'req-test-0002' }), ctx);
  assert.strictEqual(Object.keys(db.dump('demands')).length, 2);
});

ok('QABUL MEZONI 13.2.3: egasi o`zi nomzod bo`lmaydi', async () => {
  const db = new FakeFirestore(seed({
    // Egasining o'zi ham santexnik bo'lib ro'yxatdan o'tgan.
    [`provider_capabilities/${OWNER}_service`]: capability(OWNER),
    [`provider_capabilities/${USTA_A}_service`]: capability(USTA_A),
  }));
  const createDemand = build(db);
  const r = await createDemand(payload(), ctx);
  const matches = db.dump('demand_matches');
  assert.ok(!matches[`${r.demandId}_${OWNER}`], 'egasi o`ziga taklif bermasligi kerak');
  assert.ok(matches[`${r.demandId}_${USTA_A}`]);
});

ok('MAXFIYLIK: proyeksiyada aniq manzil va telefon YO`Q', async () => {
  const db = new FakeFirestore(seed({
    [`provider_capabilities/${USTA_A}_service`]: capability(USTA_A),
  }));
  const createDemand = build(db);
  const r = await createDemand(payload({
    contact: { recipientName: 'Ali', recipientPhone: '998909998877' },
    location: { lat: 41.55, lng: 60.63, addressText: 'Al-Xorazmiy 15-uy, 3-xonadon' },
  }), ctx);

  const m = db.dump('demand_matches')[`${r.demandId}_${USTA_A}`];
  const text = JSON.stringify(m);
  assert.ok(!/15-uy/.test(text), 'aniq manzil proyeksiyaga tushdi');
  assert.ok(!/998909998877/.test(text), 'telefon proyeksiyaga tushdi');
  assert.ok(!/3-xonadon/.test(text), 'xonadon raqami proyeksiyaga tushdi');
  assert.ok(!new RegExp(OWNER).test(text), 'ownerId proyeksiyaga tushdi');
  // Lekin ishlash uchun kerakli ma'lumot BOR.
  assert.strictEqual(m.projection.districtId, 'urganch_sh');
  assert.strictEqual(m.projection.categoryId, 'santexnik');
});

ok('MAXFIYLIK: taxminiy nuqta aniq nuqtadan 300-600 m uzoqda', async () => {
  const db = new FakeFirestore(seed({
    [`provider_capabilities/${USTA_A}_service`]: capability(USTA_A),
  }));
  const createDemand = build(db);
  const r = await createDemand(payload(), ctx);
  const m = db.dump('demand_matches')[`${r.demandId}_${USTA_A}`];
  const geo = require('../geo/geo');
  const meters = geo.haversineKm(
    41.55, 60.63, m.projection.approxLat, m.projection.approxLng,
  ) * 1000;
  assert.ok(meters >= 280 && meters <= 640, `kutilmagan: ${Math.round(meters)} m`);
  assert.notStrictEqual(m.projection.approxLat, 41.55);
});

ok('MAXFIYLIK: proyeksiyadagi geohash qisqartirilgan (5 belgi)', async () => {
  const db = new FakeFirestore(seed({
    [`provider_capabilities/${USTA_A}_service`]: capability(USTA_A),
  }));
  const createDemand = build(db);
  const r = await createDemand(payload(), ctx);
  const m = db.dump('demand_matches')[`${r.demandId}_${USTA_A}`];
  assert.strictEqual(m.projection.geohash.length, 5, m.projection.geohash);
  // Hujjatning o'zida esa to'liq (7 belgi) — server hisobi uchun.
  assert.strictEqual(db.dump('demands')[r.demandId].location.geohash.length, 7);
});

ok('Т-8: aniq matchedCount hujjatda YO`Q, faqat bucket', async () => {
  const extra = {};
  for (let i = 0; i < 7; i += 1) {
    const uid = `99890444${String(i).padStart(4, '0')}`;
    extra[`provider_capabilities/${uid}_service`] = capability(uid);
  }
  const db = new FakeFirestore(seed(extra));
  const createDemand = build(db);
  const r = await createDemand(payload(), ctx);

  const d = db.dump('demands')[r.demandId];
  assert.strictEqual(d.matching.matchedBucket, '6-10');
  assert.strictEqual(
    d.matching.matchedCount, undefined,
    'aniq raqam `demands` hujjatida bo`lmasligi SHART — egasi uni o`qiydi',
  );
  // Aniq raqam server-only joyda.
  const stats = db.docs.get(`demands/${r.demandId}/private/stats`);
  assert.strictEqual(stats.matchedCount, 7);
  assert.strictEqual(r.matchedBucket, '6-10');
});

ok('COLD START: `provider_capabilities` bo`sh, `ads`dan nomzod topiladi', async () => {
  // Pilotning birinchi kuni: hech kim imkoniyat belgilamagan, lekin
  // `ads`da «электрикман» deb e'lon bergan odam bor.
  const db = new FakeFirestore(seed({
    'ads/ad1': {
      type: 'service',
      regionId: 'xorazm',
      districtId: 'urganch_sh',
      authorPhone: '+998 94 111 05 04',
      authorName: 'Alisher',
      title: 'электрикман, от А до Я',
      text: 'электрикман',
      status: 'active',
    },
  }));
  const createDemand = build(db);
  const r = await createDemand(payload({ categoryId: 'elektrik', title: 'Tok yoq' }), ctx);

  assert.strictEqual(r.matchingState, 'done', 'cold start`da ham nomzod topilishi kerak');
  const matches = db.dump('demand_matches');
  const keys = Object.keys(matches);
  assert.strictEqual(keys.length, 1, keys.join(', '));
  const m = matches[keys[0]];
  assert.strictEqual(m.providerId, '998941110504', 'telefon kanon shaklga kelishi kerak');
  assert.deepStrictEqual(m.sources, ['active_listings']);
  assert.strictEqual(
    m.consentGiven, false,
    'rozilik bermagan odam PUSH OLMAYDIGAN nomzod bo`lishi SHART',
  );
});

ok('SPAM EMAS: tushunarsiz e`londan nomzod YASALMAYDI', async () => {
  const db = new FakeFirestore(seed({
    'ads/ad1': {
      type: 'service', regionId: 'xorazm', authorPhone: '998941110504',
      text: 'usyaman', status: 'active',
    },
    'ads/ad2': {
      type: 'service', regionId: 'xorazm', authorPhone: '998941110505',
      text: 'нон конвейри ишлашни бошлийди худо халаса', status: 'active',
    },
  }));
  const createDemand = build(db);
  const r = await createDemand(payload(), ctx);
  assert.strictEqual(r.matchingState, 'no_providers');
  assert.strictEqual(Object.keys(db.dump('demand_matches')).length, 0);
});

ok('no_providers: talab `active` holatda qoladi', async () => {
  // Konsepsiya: «mijoz bo'sh ekranni ko'rmaydi, talab active holatda qoladi».
  const db = new FakeFirestore(seed());
  const createDemand = build(db);
  const r = await createDemand(payload(), ctx);
  assert.strictEqual(r.matchingState, 'no_providers');
  assert.strictEqual(db.dump('demands')[r.demandId].status, 'active');
});

ok('KILL SWITCH: global o`chiq -> talab yaratilmaydi', async () => {
  const db = new FakeFirestore(seed({
    'module_config/global': { enabled: false, reason: 'incident' },
  }));
  const createDemand = build(db);
  await assert.rejects(
    () => createDemand(payload(), ctx),
    (e) => e.code === 'unavailable',
  );
  assert.strictEqual(Object.keys(db.dump('demands')).length, 0);
});

ok('SHADOW MODE: matching ishlaydi, push chaqirilmaydi', async () => {
  const db = new FakeFirestore(seed({
    'module_config/service_xorazm': {
      enabled: true, matchingEnabled: true, pushEnabled: false,
    },
    [`provider_capabilities/${USTA_A}_service`]: capability(USTA_A),
  }));
  let notifyCalled = 0;
  const createDemand = build(db, {
    notify: async () => { notifyCalled += 1; },
  });
  const r = await createDemand(payload(), ctx);

  assert.strictEqual(r.matchingState, 'done');
  assert.strictEqual(Object.keys(db.dump('demand_matches')).length, 1, 'match yozilishi kerak');
  // DIQQAT: `notify` chaqiriladi, lekin uning ichidagi policy push
  // yubormaydi. Shuning uchun bu yerda chaqirilgani normal — muhimi
  // `pushEnabled: false` flagi notify`ga yetib borishi.
  assert.strictEqual(notifyCalled, 1);
});

ok('matchingEnabled: false -> talab yaratiladi, nomzod izlanmaydi', async () => {
  const db = new FakeFirestore(seed({
    'module_config/service_xorazm': { enabled: true, matchingEnabled: false },
    [`provider_capabilities/${USTA_A}_service`]: capability(USTA_A),
  }));
  const createDemand = build(db);
  const r = await createDemand(payload(), ctx);
  assert.strictEqual(r.matchingState, 'pending');
  assert.strictEqual(Object.keys(db.dump('demand_matches')).length, 0);
  assert.strictEqual(Object.keys(db.dump('demands')).length, 1);
});

ok('autentifikatsiya: telefon claim`i yo`q -> rad etiladi', async () => {
  const db = new FakeFirestore(seed());
  const createDemand = build(db);
  await assert.rejects(
    () => createDemand(payload(), { auth: { token: {} } }),
    (e) => e.code === 'unauthenticated',
  );
});

ok('hudud aniqlanmasa rad etiladi (profil to`ldirilmagan)', async () => {
  const db = new FakeFirestore({
    'module_config/global': { enabled: true },
    'module_config/service_xorazm': { enabled: true },
    [`users/${OWNER}`]: { name: 'Mijoz' },
  });
  const createDemand = build(db);
  await assert.rejects(
    () => createDemand(payload(), ctx),
    (e) => e.code === 'failed-precondition',
  );
});

ok('ulanmagan modul -> unimplemented', async () => {
  const db = new FakeFirestore(seed());
  const createDemand = build(db);
  await assert.rejects(
    // `attributes` bo'sh: `courier` uchun attribut sxemasi hali yo'q va
    // sxema tekshiruvi adapter tekshiruvidan OLDIN ishlaydi.
    () => createDemand(payload({ module: 'courier', attributes: {}, categoryId: undefined }), ctx),
    (e) => e.code === 'unimplemented',
  );
});
ok('sxemasi yo`q modulga attribut yuborilsa invalid-argument', async () => {
  const db = new FakeFirestore(seed());
  const createDemand = build(db);
  await assert.rejects(
    () => createDemand(payload({ module: 'courier' }), ctx),
    (e) => e.code === 'invalid-argument',
  );
});

ok('noma`lum kategoriya rad etiladi', async () => {
  const db = new FakeFirestore(seed());
  const createDemand = build(db);
  await assert.rejects(
    () => createDemand(payload({ categoryId: 'xayoliy_kasb' }), ctx),
    (e) => e.code === 'invalid-argument',
  );
});

ok('LIMIT: kunlik chegara', async () => {
  const extra = {};
  const now = new Date();
  for (let i = 0; i < 10; i += 1) {
    extra[`demands/old${i}`] = {
      ownerId: OWNER, status: 'completed', createdAt: now, module: 'service',
    };
  }
  const db = new FakeFirestore(seed(extra));
  const createDemand = build(db);
  await assert.rejects(
    () => createDemand(payload(), ctx),
    (e) => e.code === 'resource-exhausted' && /Kuniga/.test(e.message),
  );
});

ok('LIMIT: bir vaqtda ochiq talablar', async () => {
  const extra = {};
  const old = new Date(Date.now() - 48 * 3600 * 1000);
  for (let i = 0; i < 5; i += 1) {
    extra[`demands/open${i}`] = {
      ownerId: OWNER, status: 'active', createdAt: old, module: 'service',
    };
  }
  const db = new FakeFirestore(seed(extra));
  const createDemand = build(db);
  await assert.rejects(
    () => createDemand(payload(), ctx),
    (e) => e.code === 'resource-exhausted' && /ochiq/.test(e.message),
  );
});

ok('MODERATSIYA: taqiqlangan so`z -> rad etiladi va shikoyat yoziladi', async () => {
  const db = new FakeFirestore(seed());
  const createDemand = build(db, {
    moderation: {
      check: async (text) => ({
        blocked: /taqiqlangan/.test(text),
        matched: ['taqiqlangan'],
      }),
    },
  });
  await assert.rejects(
    () => createDemand(payload({ title: 'taqiqlangan mahsulot' }), ctx),
    (e) => e.code === 'invalid-argument',
  );
  assert.strictEqual(Object.keys(db.dump('demands')).length, 0);
  assert.strictEqual(Object.keys(db.dump('complaints')).length, 1);
});

ok('matching yiqilsa TALAB SAQLANIB QOLADI', async () => {
  const db = new FakeFirestore(seed({
    [`provider_capabilities/${USTA_A}_service`]: capability(USTA_A),
  }));
  // Manbani ataylab buzamiz.
  const broken = {
    ...serviceAdapter,
    sources: [async () => { throw new Error('simulyatsiya'); }],
    isEligible: () => { throw new Error('simulyatsiya: adapter yiqildi'); },
  };
  const registry = require('../core/registry');
  registry.adapters.set('service', broken);
  try {
    const createDemand = build(db);
    const r = await createDemand(payload(), ctx);
    // Mijoz ishini qaytadan kiritmaydi.
    assert.ok(r.demandId);
    assert.strictEqual(Object.keys(db.dump('demands')).length, 1);
  } finally {
    registry.adapters.set('service', serviceAdapter);
  }
});

ok('ulgurji: quantity >= 5 -> wholesale: true', async () => {
  const db = new FakeFirestore(seed());
  const createDemand = build(db);
  const r1 = await createDemand(payload({ quantity: 5, clientRequestId: 'req-w-00001' }), ctx);
  const r2 = await createDemand(payload({ quantity: 4, clientRequestId: 'req-w-00002' }), ctx);
  assert.strictEqual(db.dump('demands')[r1.demandId].wholesale, true);
  assert.strictEqual(db.dump('demands')[r2.demandId].wholesale, false);
});

ok('dedupe: ikki manbadan kelgan bir odam -> sourceCount 2', async () => {
  const db = new FakeFirestore(seed({
    [`provider_capabilities/${USTA_A}_service`]: capability(USTA_A, {
      categoryIds: ['elektrik'], categoryGroups: ['uy_tamir'],
    }),
    'ads/ad1': {
      type: 'service', regionId: 'xorazm', districtId: 'urganch_sh',
      authorPhone: USTA_A, text: 'электрикман', status: 'active',
    },
  }));
  const createDemand = build(db);
  const r = await createDemand(payload({ categoryId: 'elektrik' }), ctx);
  const matches = db.dump('demand_matches');
  assert.strictEqual(Object.keys(matches).length, 1, 'bir odam ikki marta yozilmasligi kerak');
  const m = matches[`${r.demandId}_${USTA_A}`];
  assert.strictEqual(m.sources.length, 2, JSON.stringify(m.sources));
  assert.strictEqual(m.consentGiven, true, 'capabilities manbasi rozilik beradi');
});

ok('trust juda past -> matching`dan chiqariladi', async () => {
  const db = new FakeFirestore(seed({
    [`provider_capabilities/${USTA_A}_service`]: capability(USTA_A),
    [`provider_stats/${USTA_A}`]: { trustScore: 10 },
    [`provider_capabilities/${USTA_B}_service`]: capability(USTA_B),
    [`provider_stats/${USTA_B}`]: { trustScore: 60 },
  }));
  const createDemand = build(db);
  const r = await createDemand(payload(), ctx);
  const matches = db.dump('demand_matches');
  assert.ok(!matches[`${r.demandId}_${USTA_A}`], 'trust 10 bo`lgan odam chiqarilishi kerak');
  assert.ok(matches[`${r.demandId}_${USTA_B}`]);
});

ok('qarzdor taklifchi nomzod bo`lmaydi', async () => {
  const db = new FakeFirestore(seed({
    [`provider_capabilities/${USTA_A}_service`]: capability(USTA_A),
    [`provider_stats/${USTA_A}`]: { trustScore: 60, debtBlocked: true },
  }));
  const createDemand = build(db);
  const r = await createDemand(payload(), ctx);
  assert.strictEqual(Object.keys(db.dump('demand_matches')).length, 0);
  const stats = db.docs.get(`demands/${r.demandId}/private/stats`);
  assert.strictEqual(stats.rejectReasons.debt, 1);
});

ok('rejectReasons analitika uchun yoziladi', async () => {
  const db = new FakeFirestore(seed({
    [`provider_capabilities/${OWNER}_service`]: capability(OWNER),
    [`provider_capabilities/${USTA_A}_service`]: capability(USTA_A),
    [`provider_stats/${USTA_A}`]: { trustScore: 5 },
  }));
  const createDemand = build(db);
  const r = await createDemand(payload(), ctx);
  const stats = db.docs.get(`demands/${r.demandId}/private/stats`);
  assert.strictEqual(stats.rejectReasons.self, 1);
  assert.strictEqual(stats.rejectReasons.trust_too_low, 1);
});

ok('batch 500 cheklovi: 600 nomzod ikki batch`da yoziladi', async () => {
  const extra = {};
  for (let i = 0; i < 600; i += 1) {
    const uid = `9989055${String(i).padStart(5, '0')}`;
    extra[`provider_capabilities/${uid}_service`] = capability(uid);
  }
  const db = new FakeFirestore(seed(extra));
  const createDemand = build(db);
  const r = await createDemand(payload(), ctx);
  const n = Object.keys(db.dump('demand_matches')).length;
  // `maxCandidates` standart 500 — shuning uchun 500 ta yoziladi.
  assert.strictEqual(n, 500, `yozilgan: ${n}`);
  assert.strictEqual(db.dump('demands')[r.demandId].matching.matchedBucket, '100+');
});

ok('muddat: ttlMinutes hisobga olinadi', async () => {
  const db = new FakeFirestore(seed());
  const fixedNow = new Date('2026-10-03T10:00:00Z');
  config.clearCache();
  const createDemand = makeCreateDemand({
    db, admin: null, keywordIndex, now: () => fixedNow,
  });
  const r = await createDemand(payload({ timeWindow: { ttlMinutes: 60 } }), ctx);
  const d = db.dump('demands')[r.demandId];
  const expires = d.timeWindow.expiresAt;
  assert.strictEqual(expires.getTime() - fixedNow.getTime(), 60 * 60 * 1000);
});

ok('qabul qiluvchi telefoni kanon shaklga keltiriladi', async () => {
  const db = new FakeFirestore(seed());
  const createDemand = build(db);
  const r = await createDemand(payload({
    contact: { recipientName: 'Ali', recipientPhone: '909998877' },
  }), ctx);
  assert.strictEqual(db.dump('demands')[r.demandId].contact.recipientPhone, '998909998877');
});

ok('hudud mos kelmasa nomzod bo`lmaydi (adapter qoidasi)', async () => {
  const db = new FakeFirestore(seed({
    [`provider_capabilities/${USTA_A}_service`]: capability(USTA_A, {
      regionIds: ['toshkent_shahri'], districtIds: ['yashnobod'],
    }),
  }));
  const createDemand = build(db);
  const r = await createDemand(payload(), ctx);
  assert.strictEqual(Object.keys(db.dump('demand_matches')).length, 0, 'hudud filtri ishlamadi');
  assert.ok(r.demandId);
});

ok('dryRun (shadow): hisoblaydi, YOZMAYDI', async () => {
  const db = new FakeFirestore(seed({
    [`provider_capabilities/${USTA_A}_service`]: capability(USTA_A),
  }));
  config.clearCache();
  const cfg = await config.getModuleConfig(db, 'service', 'xorazm');
  const demand = {
    id: 'dem_dry',
    ownerId: OWNER,
    module: 'service',
    mode: 'quote',
    categoryId: 'santexnik',
    categoryGroup: 'uy_tamir',
    location: { lat: 41.55, lng: 60.63, regionId: 'xorazm', districtId: 'urganch_sh', geohash: 'tr7h7ev' },
    attributes: { visitType: 'at_my_place' },
    timeWindow: { expiresAt: new Date(Date.now() + 3600000) },
  };
  const res = await orchestrator.runMatching({
    db, demand, config: cfg, adapter: serviceAdapter,
    sources: serviceAdapter.sources, keywordIndex, dryRun: true,
  });
  assert.strictEqual(res.matchedCount, 1);
  assert.strictEqual(res.written, 0, 'dryRun`da yozilmasligi SHART');
  assert.strictEqual(Object.keys(db.dump('demand_matches')).length, 0);
});

// ─────────────────────────────────────────────────────────────────────
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
