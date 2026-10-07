/**
 * 13.2.6 / 13.2.7 / 13.2.8 — taklif, qabul, bekor qilish.
 *
 *   node functions_demand/test/offers.test.js
 *
 * Markaziy qulflar:
 *   - Bitta taklifchi = bitta taklif, <=3 tahrir
 *   - Birinchi `acceptOffer` g'olib (ikkinchisi to'xtaydi)
 *   - Т-9: kontakt FAQAT 1-pog'ona ochiladi (qabul qiluvchi telefoni YO'Q)
 *   - Т-19.2: qayta ochilganda rad etilgan taklif `active`ga QAYTMAYDI
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const offersApi = require('../api/offers');
const config = require('../core/config');
const sm = require('../core/state_machine');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const OWNER = '998901110001';
const USTA_A = '998902220002';
const USTA_B = '998903330003';
const DEMAND_ID = 'demAbc123XyZ';

const ctxOwner = { auth: { token: { phone_number: `+${OWNER}` } } };
const ctxA = { auth: { token: { phone_number: `+${USTA_A}` } } };
const ctxB = { auth: { token: { phone_number: `+${USTA_B}` } } };

/** Transaksiyani qo'llaydigan fake (runTransaction = ketma-ket bajarish). */
function makeDb(seed) {
  const db = new FakeFirestore(seed);
  db.runTransaction = async (fn) => {
    const tx = {
      // Haqiqiy SDK kabi: yozuvdan keyin o'qish — xato (lenient fake
      // accountId bug'ini yashirgan edi, emulatorda topildi).
      get: (ref) => {
        if (tx._ops.length) throw new Error('Firestore transactions require all reads to be executed before all writes.');
        return ref.get();
      },
      set: (ref, data, opts) => { tx._ops.push(() => ref.set(data, opts)); },
      update: (ref, data) => { tx._ops.push(() => ref.update(data)); },
      delete: (ref) => { tx._ops.push(() => ref.delete()); },
      _ops: [],
    };
    const out = await fn(tx);
    for (const op of tx._ops) await op();
    return out;
  };
  return db;
}

function seed(extra = {}) {
  const future = new Date(Date.now() + 3600 * 1000);
  return {
    'module_config/global': { enabled: true, matchingEnabled: true, pushEnabled: true },
    'module_config/service_xorazm': { enabled: true, pushEnabled: true },
    [`demands/${DEMAND_ID}`]: {
      ownerId: OWNER,
      module: 'service',
      mode: 'quote',
      status: sm.STATUS.ACTIVE,
      categoryId: 'santexnik',
      location: {
        lat: 41.55, lng: 60.63, regionId: 'xorazm', districtId: 'urganch_sh',
        addressText: 'Al-Xorazmiy 15-uy, 3-xonadon',
      },
      contact: { recipientName: 'Ali', recipientPhone: '998909998877' },
      timeWindow: { expiresAt: future },
      assignment: { providerId: null, offerId: null, acceptedAt: null },
      matching: { state: 'done', matchedBucket: '1-2' },
    },
    [`demand_matches/${DEMAND_ID}_${USTA_A}`]: {
      demandId: DEMAND_ID, providerId: USTA_A, status: 'new', score: 0.8,
    },
    [`demand_matches/${DEMAND_ID}_${USTA_B}`]: {
      demandId: DEMAND_ID, providerId: USTA_B, status: 'new', score: 0.7,
    },
    ...extra,
  };
}

function offerPayload(over = {}) {
  return {
    demandId: DEMAND_ID,
    clientRequestId: 'req-offer-0001',
    price: 150000,
    message: '18:00 gacha boraman',
    ...over,
  };
}

// ── submitOffer ──────────────────────────────────────────────────────
ok('taklif beriladi', async () => {
  const db = makeDb(seed());
  config.clearCache();
  const submitOffer = offersApi.makeSubmitOffer({ db });
  const r = await submitOffer(offerPayload(), ctxA);
  assert.strictEqual(r.offerId, USTA_A);
  const o = db.docs.get(`demands/${DEMAND_ID}/offers/${USTA_A}`);
  assert.ok(o, 'taklif yozilmadi');
  assert.strictEqual(o.status, 'active');
  assert.strictEqual(o.price, 150000);
  assert.strictEqual(o.ownerId, OWNER, 'ownerId denormalizatsiyasi (Т-2.2) yo`q');
});

ok('bitta taklifchi = bitta taklif (yangi hujjat yasalmaydi)', async () => {
  const db = makeDb(seed());
  config.clearCache();
  const submitOffer = offersApi.makeSubmitOffer({ db });
  await submitOffer(offerPayload({ clientRequestId: 'req-offer-0001' }), ctxA);
  await submitOffer(offerPayload({ clientRequestId: 'req-offer-0002', price: 140000 }), ctxA);
  const offers = [...db.docs.keys()].filter((k) => k.includes(`${DEMAND_ID}/offers/`));
  assert.strictEqual(offers.length, 1, offers.join(', '));
  const o = db.docs.get(`demands/${DEMAND_ID}/offers/${USTA_A}`);
  assert.strictEqual(o.price, 140000, 'mavjud taklif yangilanishi kerak');
  assert.strictEqual(o.revision, 1, 'tahrir hisoblanishi kerak');
});

ok('idempotentlik: bir xil clientRequestId -> dublikat', async () => {
  const db = makeDb(seed());
  config.clearCache();
  const submitOffer = offersApi.makeSubmitOffer({ db });
  await submitOffer(offerPayload(), ctxA);
  const r2 = await submitOffer(offerPayload({ price: 999 }), ctxA);
  assert.strictEqual(r2.duplicate, true);
  assert.strictEqual(db.docs.get(`demands/${DEMAND_ID}/offers/${USTA_A}`).price, 150000);
});

ok('Т-19.4: 3 tahrirdan ko`p o`zgartirib bo`lmaydi', async () => {
  const db = makeDb(seed());
  config.clearCache();
  const submitOffer = offersApi.makeSubmitOffer({ db });
  for (let i = 0; i <= 3; i += 1) {
    await submitOffer(offerPayload({ clientRequestId: `req-rev-000${i}` }), ctxA);
  }
  await assert.rejects(
    () => submitOffer(offerPayload({ clientRequestId: 'req-rev-0009' }), ctxA),
    (e) => e.code === 'resource-exhausted',
  );
});

ok('mos kelmagan taklifchi taklif bera olmaydi', async () => {
  const s = seed();
  delete s[`demand_matches/${DEMAND_ID}_${USTA_B}`];
  const db = makeDb(s);
  config.clearCache();
  const submitOffer = offersApi.makeSubmitOffer({ db });
  await assert.rejects(
    () => submitOffer(offerPayload(), ctxB),
    (e) => e.code === 'permission-denied',
  );
});

ok('egasi o`z so`roviga taklif bera olmaydi', async () => {
  const db = makeDb(seed({
    [`demand_matches/${DEMAND_ID}_${OWNER}`]: {
      demandId: DEMAND_ID, providerId: OWNER, status: 'new',
    },
  }));
  config.clearCache();
  const submitOffer = offersApi.makeSubmitOffer({ db });
  await assert.rejects(
    () => submitOffer(offerPayload(), ctxOwner),
    (e) => e.code === 'permission-denied',
  );
});

ok('muddati o`tgan so`rovga taklif berilmaydi', async () => {
  const db = makeDb(seed({
    [`demands/${DEMAND_ID}`]: {
      ...seed()[`demands/${DEMAND_ID}`],
      timeWindow: { expiresAt: new Date(Date.now() - 1000) },
    },
  }));
  config.clearCache();
  const submitOffer = offersApi.makeSubmitOffer({ db });
  await assert.rejects(
    () => submitOffer(offerPayload(), ctxA),
    (e) => e.code === 'failed-precondition',
  );
});

ok('accepted so`rovga yangi taklif berilmaydi', async () => {
  const db = makeDb(seed({
    [`demands/${DEMAND_ID}`]: {
      ...seed()[`demands/${DEMAND_ID}`], status: sm.STATUS.ACCEPTED,
    },
  }));
  config.clearCache();
  const submitOffer = offersApi.makeSubmitOffer({ db });
  await assert.rejects(
    () => submitOffer(offerPayload(), ctxA),
    (e) => e.code === 'failed-precondition',
  );
});

ok('taklif berilgach match statusi `offered`', async () => {
  const db = makeDb(seed());
  config.clearCache();
  const submitOffer = offersApi.makeSubmitOffer({ db });
  await submitOffer(offerPayload(), ctxA);
  assert.strictEqual(
    db.docs.get(`demand_matches/${DEMAND_ID}_${USTA_A}`).status, 'offered',
  );
});

// ── withdrawOffer ────────────────────────────────────────────────────
ok('taklif qaytarib olinadi', async () => {
  const db = makeDb(seed());
  config.clearCache();
  await offersApi.makeSubmitOffer({ db })(offerPayload(), ctxA);
  await offersApi.makeWithdrawOffer({ db })({ demandId: DEMAND_ID }, ctxA);
  assert.strictEqual(
    db.docs.get(`demands/${DEMAND_ID}/offers/${USTA_A}`).status, 'withdrawn',
  );
});

ok('qaytarib olingan taklif ikkinchi marta qaytarilmaydi', async () => {
  const db = makeDb(seed());
  config.clearCache();
  await offersApi.makeSubmitOffer({ db })(offerPayload(), ctxA);
  const withdraw = offersApi.makeWithdrawOffer({ db });
  await withdraw({ demandId: DEMAND_ID }, ctxA);
  await assert.rejects(
    () => withdraw({ demandId: DEMAND_ID }, ctxA),
    (e) => e.code === 'failed-precondition',
  );
});

// ── acceptOffer ──────────────────────────────────────────────────────
ok('taklif qabul qilinadi', async () => {
  const db = makeDb(seed());
  config.clearCache();
  await offersApi.makeSubmitOffer({ db })(offerPayload(), ctxA);
  const r = await offersApi.makeAcceptOffer({ db })(
    { demandId: DEMAND_ID, providerId: USTA_A }, ctxOwner,
  );
  assert.strictEqual(r.ok, true);
  const d = db.docs.get(`demands/${DEMAND_ID}`);
  assert.strictEqual(d.status, 'accepted');
  assert.strictEqual(d.assignment.providerId, USTA_A);
  assert.strictEqual(
    db.docs.get(`demands/${DEMAND_ID}/offers/${USTA_A}`).status, 'accepted',
  );
});

ok('BIRINCHI QABUL G`OLIB: ikkinchisi to`xtaydi', async () => {
  const db = makeDb(seed());
  config.clearCache();
  await offersApi.makeSubmitOffer({ db })(offerPayload(), ctxA);
  await offersApi.makeSubmitOffer({ db })(
    offerPayload({ clientRequestId: 'req-offer-b001' }), ctxB,
  );
  const accept = offersApi.makeAcceptOffer({ db });
  await accept({ demandId: DEMAND_ID, providerId: USTA_A }, ctxOwner);
  await assert.rejects(
    () => accept({ demandId: DEMAND_ID, providerId: USTA_B }, ctxOwner),
    (e) => e.code === 'failed-precondition',
  );
  assert.strictEqual(db.docs.get(`demands/${DEMAND_ID}`).assignment.providerId, USTA_A);
});

ok('Т-9: KONTAKT 1-POG`ONA — qabul qiluvchi telefoni OCHILMAYDI', async () => {
  const db = makeDb(seed());
  config.clearCache();
  await offersApi.makeSubmitOffer({ db })(offerPayload(), ctxA);
  await offersApi.makeAcceptOffer({ db })(
    { demandId: DEMAND_ID, providerId: USTA_A }, ctxOwner,
  );
  const m = db.docs.get(`demand_matches/${DEMAND_ID}_${USTA_A}`);
  assert.strictEqual(m.contactUnlocked.stage, 1);
  assert.strictEqual(m.contactUnlocked.ownerPhone, OWNER, 'yuboruvchi telefoni ochilishi kerak');
  const text = JSON.stringify(m);
  assert.ok(
    !/998909998877/.test(text),
    'QABUL QILUVCHI telefoni 1-pog`onada ochilmasligi SHART (manzil yig`ish hujumi)',
  );
});

ok('boshqa odam qabul qila olmaydi', async () => {
  const db = makeDb(seed());
  config.clearCache();
  await offersApi.makeSubmitOffer({ db })(offerPayload(), ctxA);
  await assert.rejects(
    () => offersApi.makeAcceptOffer({ db })(
      { demandId: DEMAND_ID, providerId: USTA_A }, ctxB,
    ),
    (e) => e.code === 'permission-denied',
  );
});

ok('mavjud bo`lmagan taklif qabul qilinmaydi', async () => {
  const db = makeDb(seed());
  config.clearCache();
  await assert.rejects(
    () => offersApi.makeAcceptOffer({ db })(
      { demandId: DEMAND_ID, providerId: USTA_A }, ctxOwner,
    ),
    (e) => e.code === 'not-found',
  );
});

ok('afterAccept: qolgan takliflar rejected, matchlar `taken`', async () => {
  const db = makeDb(seed());
  config.clearCache();
  await offersApi.makeSubmitOffer({ db })(offerPayload(), ctxA);
  await offersApi.makeSubmitOffer({ db })(
    offerPayload({ clientRequestId: 'req-offer-b001' }), ctxB,
  );
  const afterAccept = offersApi.makeAfterAccept({ db, messaging: null });
  await offersApi.makeAcceptOffer({ db, onAccepted: afterAccept })(
    { demandId: DEMAND_ID, providerId: USTA_A }, ctxOwner,
  );
  assert.strictEqual(
    db.docs.get(`demands/${DEMAND_ID}/offers/${USTA_B}`).status, 'rejected',
  );
  assert.strictEqual(db.docs.get(`demand_matches/${DEMAND_ID}_${USTA_B}`).status, 'taken');
  assert.strictEqual(
    db.docs.get(`demand_matches/${DEMAND_ID}_${USTA_A}`).status, 'accepted',
  );
});

// ── cancelDemand ─────────────────────────────────────────────────────
ok('mijoz bekor qiladi', async () => {
  const db = makeDb(seed());
  config.clearCache();
  await offersApi.makeCancelDemand({ db })({ demandId: DEMAND_ID }, ctxOwner);
  const d = db.docs.get(`demands/${DEMAND_ID}`);
  assert.strictEqual(d.status, 'cancelled');
  assert.strictEqual(d.cancelledBy, 'owner');
  // Barcha match yozuvlari yopiladi.
  assert.strictEqual(db.docs.get(`demand_matches/${DEMAND_ID}_${USTA_A}`).status, 'cancelled');
});

ok('boshqa odam bekor qila olmaydi', async () => {
  const db = makeDb(seed());
  config.clearCache();
  await assert.rejects(
    () => offersApi.makeCancelDemand({ db })({ demandId: DEMAND_ID }, ctxA),
    (e) => e.code === 'permission-denied',
  );
});

ok('bekor qilingan talab ikkinchi marta bekor qilinmaydi', async () => {
  const db = makeDb(seed());
  config.clearCache();
  const cancel = offersApi.makeCancelDemand({ db });
  await cancel({ demandId: DEMAND_ID }, ctxOwner);
  await assert.rejects(
    () => cancel({ demandId: DEMAND_ID }, ctxOwner),
    (e) => e.code === 'failed-precondition',
  );
});

// ── cancelAssignment (Т-19.2) ────────────────────────────────────────
ok('ijrochi bekor qiladi -> talab QAYTA OCHILADI', async () => {
  const db = makeDb(seed());
  config.clearCache();
  await offersApi.makeSubmitOffer({ db })(offerPayload(), ctxA);
  await offersApi.makeAcceptOffer({ db })(
    { demandId: DEMAND_ID, providerId: USTA_A }, ctxOwner,
  );
  const r = await offersApi.makeCancelAssignment({ db })({ demandId: DEMAND_ID }, ctxA);
  assert.strictEqual(r.reopened, true);
  const d = db.docs.get(`demands/${DEMAND_ID}`);
  assert.strictEqual(d.status, 'active');
  assert.strictEqual(d.assignment.providerId, null);
  assert.strictEqual(d.reopenCount, 1);
});

ok('Т-19.2: qabul qilingan taklif `rejected` bo`ladi (withdrawn EMAS)', async () => {
  const db = makeDb(seed());
  config.clearCache();
  await offersApi.makeSubmitOffer({ db })(offerPayload(), ctxA);
  await offersApi.makeAcceptOffer({ db })(
    { demandId: DEMAND_ID, providerId: USTA_A }, ctxOwner,
  );
  await offersApi.makeCancelAssignment({ db })({ demandId: DEMAND_ID }, ctxA);
  assert.strictEqual(
    db.docs.get(`demands/${DEMAND_ID}/offers/${USTA_A}`).status, 'rejected',
  );
});

ok('bekor qilgach KONTAKT YOPILADI', async () => {
  const db = makeDb(seed());
  config.clearCache();
  await offersApi.makeSubmitOffer({ db })(offerPayload(), ctxA);
  await offersApi.makeAcceptOffer({ db })(
    { demandId: DEMAND_ID, providerId: USTA_A }, ctxOwner,
  );
  await offersApi.makeCancelAssignment({ db })({ demandId: DEMAND_ID }, ctxA);
  const m = db.docs.get(`demand_matches/${DEMAND_ID}_${USTA_A}`);
  assert.strictEqual(m.contactUnlocked, null, 'bekor qilgach manzil yopilishi SHART');
  assert.strictEqual(m.status, 'cancelled_by_provider');
});

ok('tayinlanmagan odam cancelAssignment qila olmaydi', async () => {
  const db = makeDb(seed());
  config.clearCache();
  await offersApi.makeSubmitOffer({ db })(offerPayload(), ctxA);
  await offersApi.makeAcceptOffer({ db })(
    { demandId: DEMAND_ID, providerId: USTA_A }, ctxOwner,
  );
  await assert.rejects(
    () => offersApi.makeCancelAssignment({ db })({ demandId: DEMAND_ID }, ctxB),
    (e) => e.code === 'permission-denied',
  );
});

ok('trust voqeasi yoziladi (tez bekor qilish vs kech)', async () => {
  const db = makeDb(seed());
  config.clearCache();
  await offersApi.makeSubmitOffer({ db })(offerPayload(), ctxA);
  await offersApi.makeAcceptOffer({ db })(
    { demandId: DEMAND_ID, providerId: USTA_A }, ctxOwner,
  );
  await offersApi.makeCancelAssignment({ db })({ demandId: DEMAND_ID }, ctxA);
  const events = Object.values(db.dump('trust_events'));
  assert.strictEqual(events.length, 1, JSON.stringify(events));
  // 2 daqiqa ichida bekor qilindi -> `quickCancel` (jarima yo'q).
  assert.strictEqual(events[0].type, 'quickCancel');
  assert.strictEqual(events[0].subjectId, USTA_A);
});

// Relay LEG'ida `assignment.offerId: null` — taklif hujjati umuman yo'q.
// Bu shox ham avval yozuvdan keyin o'qirdi (emulatorda isbotlangan).
ok('cancelAssignment: taklif hujjati YO`Q (Relay LEG) -> qayta ochiladi', async () => {
  const db = makeDb(seed({
    [`demands/${DEMAND_ID}`]: {
      ownerId: OWNER,
      module: 'logistics',
      status: sm.STATUS.ACCEPTED,
      assignment: { providerId: USTA_A, offerId: null, acceptedAt: new Date() },
      matching: { state: 'done' },
    },
  }));
  config.clearCache();
  await offersApi.makeCancelAssignment({ db })({ demandId: DEMAND_ID }, ctxA);
  const d = db.docs.get(`demands/${DEMAND_ID}`);
  assert.strictEqual(d.status, 'active');
  assert.strictEqual(d.assignment.providerId, null);
  assert.ok(!db.docs.has(`demands/${DEMAND_ID}/offers/${USTA_A}`), 'taklif hujjati yaratilmasligi kerak');
});

// Fake'ning o'zi qulflanadi: yana «yumshoq» bo'lib qolsa, yuqoridagi
// testlar haqiqiy SDK'da yiqiladigan kodni yashil ko'rsatadi.
ok('fake tranzaksiya haqiqiy SDK kabi: yozuvdan KEYIN o`qish XATO', async () => {
  const db = makeDb(seed());
  const ref = db.collection('demands').doc(DEMAND_ID);
  await assert.rejects(
    () => db.runTransaction(async (tx) => {
      tx.update(ref, { x: 1 });
      await tx.get(ref);
    }),
    /all reads to be executed before all writes/,
  );
});

// ── autentifikatsiya ─────────────────────────────────────────────────
ok('telefon claim`i yo`q -> hamma amal rad etiladi', async () => {
  const db = makeDb(seed());
  config.clearCache();
  const noAuth = { auth: { token: {} } };
  await assert.rejects(
    () => offersApi.makeSubmitOffer({ db })(offerPayload(), noAuth),
    (e) => e.code === 'unauthenticated',
  );
  await assert.rejects(
    () => offersApi.makeAcceptOffer({ db })(
      { demandId: DEMAND_ID, providerId: USTA_A }, noAuth,
    ),
    (e) => e.code === 'unauthenticated',
  );
  await assert.rejects(
    () => offersApi.makeCancelDemand({ db })({ demandId: DEMAND_ID }, noAuth),
    (e) => e.code === 'unauthenticated',
  );
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
