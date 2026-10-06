/**
 * `presenceSweeper` — `api/maintenance.js` → `makePresenceSweeper`.
 *
 *   node functions_demand/test/presence_sweeper.test.js
 *
 * Bu sweep `provider_presence` hujjatining HOLATINI o'zgartiradi, ya'ni
 * u bilan klient yozuvchisi (3-qadam) o'rtasida SHARTNOMA bor. Shu
 * shartnomaning har bir bandi shu yerda qulflangan:
 *
 *   1. Eskirish chegarasi matching bilan BIR XIL (`maxLocationAgeSec`) —
 *      «matching ko'rmayapti, lekin admin onlayn deb turibdi» oynasi
 *      bo'lmasligi kerak.
 *   2. `updatedAt` GA TEGILMAYDI — u faqat qurilmadan kelgan oxirgi
 *      heartbeat. Sweep uni yangilasa, eskilik mezoni o'z-o'zini yo'q
 *      qilardi va hujjat abadiy «yangi» bo'lib qolardi.
 *   3. Sweep FAQAT `isOnline: true` ni ko'radi, ya'ni ikkinchi marta
 *      ishga tushganda hech narsa yozmaydi (21-qoida: idempotentlik).
 *   4. Bitta hujjatdagi yozish xatosi qolganlarini TO'XTATMAYDI.
 *
 * 2-banddan kelib chiqadigan klient talabi: har bir heartbeat
 * `isOnline: true` ni ham yozishi SHART. Aks holda bir marta offline
 * qilingan kuryer hech qachon qaytib onlayn bo'lmaydi.
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const maintenance = require('../api/maintenance');
const { DEFAULTS } = require('../core/config');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const A = '998901110001';
const B = '998902220002';
const C = '998903330003';

/** Test vaqti qotirilgan: «hozir» har doim shu nuqta. */
const NOW = new Date('2026-10-06T10:00:00.000Z');
const now = () => NOW;

/** Sekundlar oldin. */
function agoSec(sec) {
  return new Date(NOW.getTime() - sec * 1000);
}

function presenceDoc(over = {}) {
  return {
    isOnline: true,
    module: 'courier',
    lat: 41.55,
    lng: 60.63,
    geohash: 'tz2abcd',
    updatedAt: agoSec(10),
    ...over,
  };
}

/**
 * Sweep'ni jim ishga tushiradi va log qatorlarini qaytaradi.
 *
 * Testda konsol ifloslanmasligi uchun, LEKIN diagnostika yo'qolmasligi
 * uchun: xato testi aynan shu loglarni tekshiradi.
 */
async function sweep(db, deps = {}) {
  const logs = [];
  const errs = [];
  const origLog = console.log;
  const origErr = console.error;
  console.log = (...a) => logs.push(a.join(' '));
  console.error = (...a) => errs.push(a.join(' '));
  try {
    const run = maintenance.makePresenceSweeper({ db, now, ...deps });
    const res = await run();
    return { res, logs, errs };
  } finally {
    console.log = origLog;
    console.error = origErr;
  }
}

// ─── asosiy oqim ──────────────────────────────────────────────────────
ok('eskirgan yozuv offline qilinadi', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc({ updatedAt: agoSec(600) }),
  });
  const { res } = await sweep(db);
  assert.strictEqual(res.offlined, 1);

  const doc = db.dump('provider_presence')[A];
  assert.strictEqual(doc.isOnline, false);
  assert.strictEqual(doc.offlineReason, 'stale_heartbeat');
  assert.strictEqual(doc.offlineAt.getTime(), NOW.getTime(), '`now` dan olinmagan');
});

ok('YANGI yozuvga TEGILMAYDI', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc({ updatedAt: agoSec(10) }),
  });
  const { res } = await sweep(db);
  assert.strictEqual(res.offlined, 0);
  assert.strictEqual(db.writes, 0, 'keraksiz yozish — 37-qoida (narx)');
  assert.strictEqual(db.dump('provider_presence')[A].isOnline, true);
});

ok('`updatedAt` O\'ZGARMAYDI — eskilik mezoni saqlanadi', async () => {
  const stale = agoSec(600);
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc({ updatedAt: stale }),
  });
  await sweep(db);
  const doc = db.dump('provider_presence')[A];
  assert.strictEqual(doc.updatedAt.getTime(), stale.getTime(),
      'sweep heartbeat vaqtini yangilab yuborgan');
});

ok('`updatedAt` umuman yo\'q bo\'lsa ham offline qilinadi', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc({ updatedAt: null }),
  });
  const { res } = await sweep(db);
  assert.strictEqual(res.offlined, 1, 'noto\'g\'ri shakldagi yozuv abadiy onlayn qolardi');
});

// ─── chegara ──────────────────────────────────────────────────────────
ok('chegara matching bilan BIR XIL (DEFAULTS.maxLocationAgeSec)', async () => {
  assert.strictEqual(DEFAULTS.maxLocationAgeSec, 120, 'konfig o\'zgargan — testni ko\'rib chiqing');

  const db = new FakeFirestore({
    // Chegaraning ichida: 119 s.
    [`provider_presence/${A}`]: presenceDoc({ updatedAt: agoSec(119) }),
    // Chegaradan tashqarida: 121 s.
    [`provider_presence/${B}`]: presenceDoc({ updatedAt: agoSec(121) }),
  });
  const { res } = await sweep(db);
  assert.strictEqual(res.offlined, 1);

  const docs = db.dump('provider_presence');
  assert.strictEqual(docs[A].isOnline, true, '119 s — hali yangi');
  assert.strictEqual(docs[B].isOnline, false, '121 s — eskirgan');
});

ok('aynan chegarada turgan yozuv SAQLANADI', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc({ updatedAt: agoSec(120) }),
  });
  const { res } = await sweep(db);
  assert.strictEqual(res.offlined, 0, 'chegara `>=` bo\'yicha, matching bilan bir xil');
});

ok('deps.maxLocationAgeSec chegarani almashtiradi', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc({ updatedAt: agoSec(100) }),
  });
  const { res } = await sweep(db, { maxLocationAgeSec: 60 });
  assert.strictEqual(res.offlined, 1);
});

// ─── tanlash doirasi ──────────────────────────────────────────────────
ok('ALLAQACHON offline yozuv umuman o\'qilmaydi', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc({
      isOnline: false, updatedAt: agoSec(99999),
    }),
  });
  const { res } = await sweep(db);
  assert.strictEqual(res.offlined, 0);
  assert.strictEqual(db.reads, 0, 'so\'rov `isOnline == true` bilan cheklanmagan');
  assert.strictEqual(db.writes, 0);
});

ok('IDEMPOTENT: ikkinchi ishga tushishda hech narsa yozilmaydi', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc({ updatedAt: agoSec(600) }),
  });
  const first = await sweep(db);
  assert.strictEqual(first.res.offlined, 1);
  const writesAfterFirst = db.writes;

  const second = await sweep(db);
  assert.strictEqual(second.res.offlined, 0);
  assert.strictEqual(db.writes, writesAfterFirst, 'ikkinchi sweep qayta yozdi');
});

ok('sweep MODULGA qaramaydi — taxi presence ham tozalanadi', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc({ module: 'taxi', updatedAt: agoSec(600) }),
    [`provider_presence/${B}`]: presenceDoc({ module: 'courier', updatedAt: agoSec(600) }),
  });
  const { res } = await sweep(db);
  assert.strictEqual(res.offlined, 2, 'gigiyena modulga bog\'liq emas');
});

ok('boshqa kolleksiyalarga tegilmaydi', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc({ updatedAt: agoSec(600) }),
    [`provider_capabilities/${A}_courier`]: { providerId: A, active: true },
    [`couriers/${A}`]: { isOnline: true, updatedAt: agoSec(600) },
  });
  await sweep(db);
  assert.strictEqual(db.dump('couriers')[A].isOnline, true,
      'eski `couriers` kolleksiyasi bu sweep\'ning ishi EMAS');
  assert.strictEqual(db.dump('provider_capabilities')[`${A}_courier`].active, true);
});

ok('kolleksiya nomi deps orqali almashtiriladi', async () => {
  const db = new FakeFirestore({
    [`presence_shadow/${A}`]: presenceDoc({ updatedAt: agoSec(600) }),
  });
  const { res } = await sweep(db, { collection: 'presence_shadow' });
  assert.strictEqual(res.offlined, 1);
});

// ─── hajm va xatolar ──────────────────────────────────────────────────
ok('batchSize bir ishga tushishdagi hajmni cheklaydi', async () => {
  const seed = {};
  for (let i = 0; i < 5; i += 1) {
    seed[`provider_presence/99890111000${i}`] = presenceDoc({ updatedAt: agoSec(600) });
  }
  const db = new FakeFirestore(seed);
  const { res } = await sweep(db, { batchSize: 2 });
  assert.strictEqual(res.offlined, 2, 'cheklov ishlamagan — katta kolleksiyada timeout bo\'lardi');

  // Qolganlari KEYINGI ishga tushishda tozalanadi.
  const next = await sweep(db, { batchSize: 2 });
  assert.strictEqual(next.res.offlined, 2);
});

ok('bitta hujjatdagi xato qolganlarini to\'xtatmaydi', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc({ updatedAt: agoSec(600) }),
    [`provider_presence/${B}`]: presenceDoc({ updatedAt: agoSec(600) }),
    [`provider_presence/${C}`]: presenceDoc({ updatedAt: agoSec(600) }),
  });

  // `FakeDoc` eksport qilinmagan, shuning uchun prototip nusxa orqali
  // olinadi va test oxirida QAYTARILADI.
  const proto = Object.getPrototypeOf(db.collection('provider_presence').doc('x'));
  const orig = proto.update;
  proto.update = async function patched(data) {
    if (this.id === B) throw new Error('soxta tarmoq xatosi');
    return orig.call(this, data);
  };

  let out;
  try {
    out = await sweep(db);
  } finally {
    proto.update = orig;
  }

  assert.strictEqual(out.res.offlined, 2, 'hisob faqat MUVAFFAQIYATLI yozishlarni sanashi kerak');
  const docs = db.dump('provider_presence');
  assert.strictEqual(docs[A].isOnline, false);
  assert.strictEqual(docs[B].isOnline, true, 'xato bo\'lgan hujjat o\'zgarmasligi kerak');
  assert.strictEqual(docs[C].isOnline, false, 'xatodan keyin aylanish to\'xtab qolgan');
  assert.ok(out.errs.some((l) => l.includes(B)), 'diagnostika logga tushmagan (24-qoida)');
});

ok('bo\'sh kolleksiyada xato tashlamaydi', async () => {
  const db = new FakeFirestore({});
  const { res, logs } = await sweep(db);
  assert.strictEqual(res.offlined, 0);
  assert.strictEqual(logs.length, 0, 'ish yo\'q bo\'lsa log ham bo\'lmasin');
});

ok('ish qilinganda log qoldiradi', async () => {
  const db = new FakeFirestore({
    [`provider_presence/${A}`]: presenceDoc({ updatedAt: agoSec(600) }),
  });
  const { logs } = await sweep(db);
  assert.ok(logs.some((l) => l.includes('presenceSweeper') && l.includes('1')),
      'kuzatuvsiz feature tayyor emas (24-qoida)');
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
