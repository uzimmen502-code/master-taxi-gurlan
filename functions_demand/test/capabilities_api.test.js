/**
 * Capability API — `api/capabilities.js` (T-1a accountId, T-2, D-TAXI-2).
 *
 *   node functions_demand/test/capabilities_api.test.js
 *
 * Qulflanadi:
 *   1. `accountId` server beradi, BIR MARTA, tranzaksiyada; 9 xonali
 *      eski `users` kaliti ham topiladi.
 *   2. Ariza: xizmat lifecycle'ining BOSHLANG'ICH holati + oyna.
 *   3. IDEMPOTENT: qayta ariza, capability'ni o'chirib-qayta yoqish
 *      taksi starter oynasini QAYTA BOSHLAMAYDI (D-TAXI-2).
 *   4. Sweeper: kuryer grace bir marta; taksi 4 oydan keyin
 *      verification_required, grace yo'q, boshqa capability tegilmaydi.
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const api = require('../api/capabilities');
const caps = require('../core/capabilities');

// Kelishuv (D-TAXI-24.1) ALOHIDA testda (`agreements_admin.test.js`).
// Taksida darvoza YO'Q — starter kelishuvsiz beriladi; bu yerda
// lifecycle/idempotentlik sinaladi.

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const A = '998901110001';
const B9 = '902220002';
const B12 = '998902220002';
const NOW = new Date('2026-10-06T10:00:00.000Z');
const day = (n) => new Date(NOW.getTime() + n * caps.DAY_MS);
const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });

function makeDb(seed = {}) {
  const db = new FakeFirestore(seed);
  db.runTransaction = async (fn) => {
    const tx = {
      // Haqiqiy SDK kabi: yozuvdan keyin o'qish — xato (accountId bug'i
      // fake'da ko'rinmagan edi, emulatorda topildi).
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

const capsDump = (db) => db.dump('provider_capabilities');
const onlyDoc = (db) => {
  const all = capsDump(db);
  const keys = Object.keys(all);
  assert.strictEqual(keys.length, 1, `1 ta hujjat kutilgan, ${keys.length} ta bor`);
  return { id: keys[0], data: all[keys[0]] };
};

async function silent(fn) {
  const o = { log: console.log, error: console.error };
  console.log = () => {}; console.error = () => {};
  try { return await fn(); } finally { console.log = o.log; console.error = o.error; }
}

// ─── accountId ────────────────────────────────────────────────────────
ok('birinchi ariza accountId YARATADI va users ga yozadi', async () => {
  const db = makeDb({ [`users/${A}`]: { role: 'user', phone: A } });
  const res = await api.makeRequestCapability({ db, now: () => NOW })({ service: 'courier' }, ctx(A));
  assert.ok(/^acc[A-Za-z0-9]{20}$/.test(res.accountId), res.accountId);
  assert.ok(!res.accountId.includes('_'), 'composite kalit uchun `_` bo\'lmasin');
  assert.strictEqual(db.dump('users')[A].accountId, res.accountId);
  const { id, data } = onlyDoc(db);
  assert.strictEqual(id, res.accountId, 'hujjat kaliti = accountId');
  assert.deepStrictEqual(data.identity, { accountId: res.accountId, primaryUid: A });
});

ok('accountId BIR MARTA: ikkinchi xizmat arizasi bir xil kalitga tushadi', async () => {
  const db = makeDb({ [`users/${A}`]: { role: 'user' } });
  const req = api.makeRequestCapability({ db, now: () => NOW });
  const a = await req({ service: 'courier' }, ctx(A));
  const b = await req({ service: 'taxi' }, ctx(A));
  assert.strictEqual(a.accountId, b.accountId);
  const { data } = onlyDoc(db);
  assert.strictEqual(data.status.courier, caps.COURIER.applied);
  assert.strictEqual(data.status.taxi, caps.TAXI.starter);
});

ok('eski 9 xonali `users` kaliti topiladi, yangisi yaratilmaydi', async () => {
  const db = makeDb({ [`users/${B9}`]: { role: 'user', accountId: 'accEXISTING0000000000X' } });
  const res = await api.makeRequestCapability({ db, now: () => NOW })({ service: 'courier' }, ctx(B12));
  assert.strictEqual(res.accountId, 'accEXISTING0000000000X');
  assert.strictEqual(db.dump('users')[B12], undefined, '12 xonali dublikat yaratilgan');
  assert.strictEqual(onlyDoc(db).data.identity.primaryUid, B12, 'primaryUid kanon shaklda');
});

ok('`users` hujjati umuman yo\'q bo\'lsa — yaratiladi (Phone Auth bor)', async () => {
  const db = makeDb();
  const res = await api.makeRequestCapability({ db, now: () => NOW })({ service: 'seller' }, ctx(A));
  assert.strictEqual(db.dump('users')[A].accountId, res.accountId);
  assert.strictEqual(res.status, caps.SIMPLE.enabled);
});

// ─── ariza va idempotentlik ───────────────────────────────────────────
ok('kuryer D-15.5 (manual): `applied` — admin tasdig\'igacha ISHLAMAYDI, sinov oynasi YO\'Q', async () => {
  const db = makeDb({ [`users/${A}`]: {} });
  const res = await api.makeRequestCapability({ db, now: () => NOW })({ service: 'courier' }, ctx(A));
  assert.strictEqual(res.status, caps.COURIER.applied);
  assert.strictEqual(res.changed, true);
  assert.strictEqual(res.trialEndsAt, undefined, 'sinov soati yurmaydi');
  const { data } = onlyDoc(db);
  assert.strictEqual(data.courier.active, true, 'xohish yozildi');
  assert.strictEqual(caps.isEligible(data, 'courier'), false, 'tasdiqsiz nomzod emas');
  assert.strictEqual(caps.canFinishActive(data, 'courier'), false);
  assert.strictEqual((data.window || {}).courier, undefined, 'oyna yozilmaydi');
  assert.strictEqual(data.review.courier.submittedAt.getTime(), NOW.getTime(), 'ariza vaqti — admin uchun');
  assert.deepStrictEqual(db.dump('capability_audit'), {}, 'ariza — admin amali emas');
});

ok('kuryer D-15.5: qayta ariza IDEMPOTENT — `applied` o\'zgarmaydi, ariza vaqti qayta yozilmaydi', async () => {
  const db = makeDb({ [`users/${A}`]: {} });
  await api.makeRequestCapability({ db, now: () => NOW })({ service: 'courier' }, ctx(A));
  const again = await api.makeRequestCapability({ db, now: () => day(2) })({ service: 'courier' }, ctx(A));
  assert.strictEqual(again.changed, false);
  assert.strictEqual(again.status, caps.COURIER.applied);
  assert.strictEqual(onlyDoc(db).data.review.courier.submittedAt.getTime(), NOW.getTime());
});

ok('taksi: `starter` + 4 oylik oyna, DARHOL ishlaydi (D-TAXI-1, 2)', async () => {
  const db = makeDb({ [`users/${A}`]: {} });
  const res = await api.makeRequestCapability({ db, now: () => NOW })({ service: 'taxi' }, ctx(A));
  assert.strictEqual(res.status, caps.TAXI.starter);
  assert.strictEqual(res.verificationDueAt, '2027-02-06T10:00:00.000Z');
  const { data } = onlyDoc(db);
  assert.strictEqual(caps.isEligible(data, 'taxi'), true);
  assert.strictEqual(caps.canPublishPaid(data, 'taxi'), true);
  assert.strictEqual(caps.isTaxiBillable(data, NOW), false, 'starter bepul (D-TAXI-3)');
});

ok('taksi starter oynasi BIR MARTA: o\'chirib-qayta yoqish, qayta ariza (D-TAXI-2)', async () => {
  const db = makeDb({ [`users/${A}`]: {} });
  const first = await api.makeRequestCapability({ db, now: () => NOW })({ service: 'taxi' }, ctx(A));
  // Capability'ni o'chirdi (xohish) — status tegilmaydi.
  await db.collection('provider_capabilities').doc(first.accountId).set({ taxi: { active: false } }, { merge: true });
  // Admin verification_required qildi, keyin yana ariza berdi (60 kun keyin).
  await db.collection('provider_capabilities').doc(first.accountId)
    .set({ status: { taxi: caps.TAXI.verificationRequired } }, { merge: true });
  const again = await api.makeRequestCapability({ db, now: () => day(60) })({ service: 'taxi' }, ctx(A));
  assert.strictEqual(again.changed, false, 'verification_required ishlaydigan holat — o\'zgarmaydi');
  const { data } = onlyDoc(db);
  assert.strictEqual(data.window.taxi.verificationDueAt.toISOString(), '2027-02-06T10:00:00.000Z', 'oyna qayta boshlangan');
  assert.strictEqual(data.status.taxi, caps.TAXI.verificationRequired);
});

ok('taksi: suspended dan qayta ariza bilan starter OLIB BO\'LMAYDI', async () => {
  const db = makeDb({ [`users/${A}`]: {} });
  const first = await api.makeRequestCapability({ db, now: () => NOW })({ service: 'taxi' }, ctx(A));
  await db.collection('provider_capabilities').doc(first.accountId)
    .set({ status: { taxi: caps.COMMON.suspended } }, { merge: true });
  await assert.rejects(
    () => api.makeRequestCapability({ db, now: () => day(200) })({ service: 'taxi' }, ctx(A)),
    (e) => e.code === 'failed-precondition');
  assert.strictEqual(onlyDoc(db).data.window.taxi.startedAt.getTime(), NOW.getTime(), 'oyna tegilmagan');
});

ok('kuryer: qayta ariza muddatni cho\'zmaydi; tasdiq `trial`ga tushmaydi', async () => {
  const db = makeDb({ [`users/${A}`]: {} });
  const req = api.makeRequestCapability({ db, now: () => NOW });
  const first = await req({ service: 'courier' }, ctx(A));
  const again = await api.makeRequestCapability({ db, now: () => day(2) })({ service: 'courier' }, ctx(A));
  assert.strictEqual(again.changed, false);
  await db.collection('provider_capabilities').doc(first.accountId)
    .set({ status: { courier: caps.COURIER.approved } }, { merge: true });
  const third = await api.makeRequestCapability({ db, now: () => day(2) })({ service: 'courier' }, ctx(A));
  assert.strictEqual(third.status, caps.COURIER.approved);
});

ok('autentifikatsiyasiz / noma\'lum xizmat rad etiladi', async () => {
  const db = makeDb();
  await assert.rejects(() => api.makeRequestCapability({ db })({ service: 'courier' }, {}), (e) => e.code === 'unauthenticated');
  await assert.rejects(() => api.makeRequestCapability({ db })({ service: 'kosmonavt' }, ctx(A)), (e) => e.code === 'invalid-argument');
});

ok('fetchByPhone: users -> accountId -> hujjat (9 xonali bilan ham)', async () => {
  const db = makeDb({ [`users/${B9}`]: {} });
  const res = await api.makeRequestCapability({ db, now: () => NOW })({ service: 'courier' }, ctx(B12));
  const got = await api.fetchByPhone(db, B9);
  assert.strictEqual(got.id, res.accountId);
  assert.strictEqual(await api.fetchByPhone(db, '998909999999'), null);
});

// ─── sweeper ──────────────────────────────────────────────────────────
async function withTrial(service, over = {}, status) {
  const db = makeDb({ [`users/${A}`]: {} });
  const res = await api.makeRequestCapability({ db, now: () => NOW })({ service }, ctx(A));
  const ref = db.collection('provider_capabilities').doc(res.accountId);
  const patch = { window: { [service]: over } };
  if (status) patch.status = { [service]: status };
  await ref.set(patch, { merge: true });
  return { db, id: res.accountId, data: () => capsDump(db)[res.accountId] };
}

ok('kuryer sweeper: grace bir marta, keyin suspended; retry cho\'zmaydi', async () => {
  // D-15.5 dan oldin ariza bergan, hali `trial` da turgan kuryer (orqaga moslik).
  const t = await withTrial('courier', caps.windowFor('courier', NOW), caps.COURIER.trial);
  const sw = (n) => silent(() => api.makeCapabilitySweeper({ db: t.db, now: () => day(n) })());
  assert.deepStrictEqual(await sw(2), { graceGranted: 0, suspended: 0, verificationRequired: 0 });
  assert.strictEqual((await sw(4)).graceGranted, 1);
  const ends = t.data().window.courier.graceEndsAt.getTime();
  assert.deepStrictEqual(await sw(4.1), { graceGranted: 0, suspended: 0, verificationRequired: 0 });
  assert.strictEqual(t.data().window.courier.graceEndsAt.getTime(), ends);
  assert.strictEqual(caps.isEligible(t.data(), 'courier'), true, 'grace da ishlaydi');
  assert.strictEqual((await sw(10)).suspended, 1);
  assert.strictEqual(t.data().suspend.courier.reason, 'documents_missing');
  assert.deepStrictEqual(await sw(20), { graceGranted: 0, suspended: 0, verificationRequired: 0 });
});

ok('taksi sweeper: 4 oydan keyin verification_required, GRACE YO\'Q (D-TAXI-4)', async () => {
  const t = await withTrial('taxi');
  const sw = (n) => silent(() => api.makeCapabilitySweeper({ db: t.db, now: () => day(n) })());
  assert.strictEqual((await sw(100)).verificationRequired, 0);
  assert.strictEqual((await sw(124)).verificationRequired, 1);
  assert.strictEqual(t.data().status.taxi, caps.TAXI.verificationRequired);
  assert.strictEqual(t.data().suspend, undefined, 'suspend emas — akkaunt ochiq');
  assert.strictEqual(caps.isEligible(t.data(), 'taxi'), true, 'mavjud ish davom etadi (D-TAXI-5)');
  assert.strictEqual(caps.canPublishPaid(t.data(), 'taxi'), false);
  assert.deepStrictEqual(await sw(200), { graceGranted: 0, suspended: 0, verificationRequired: 0 }, 'idempotent');
});

ok('D-TAXI-24.1 sweeper: starter tugadi → kelishuv TAQDIM (agreementRequestedAt + inbox xabari + push, BIR MARTA)', async () => {
  const db = makeDb({ [`users/${A}`]: { fcmToken: 'tok-A' } });
  const res = await api.makeRequestCapability({ db, now: () => NOW })({ service: 'taxi' }, ctx(A));
  const sent = [];
  const messaging = { sendEach: async (msgs) => { sent.push(...msgs); return { responses: msgs.map(() => ({ success: true })) }; } };
  const sw = (n) => silent(() => api.makeCapabilitySweeper({ db, messaging, now: () => day(n) })());
  assert.strictEqual((await sw(124)).verificationRequired, 1);
  const d = capsDump(db)[res.accountId];
  assert.strictEqual(d.status.taxi, caps.TAXI.verificationRequired);
  assert.strictEqual(d.window.taxi.agreementRequestedAt.getTime(), day(124).getTime(), 'tizim taqdim qilgan vaqt (server kaliti)');
  assert.strictEqual(d.window.taxi.verificationDueAt.toISOString(), '2027-02-06T10:00:00.000Z', 'oyna buzilmagan');
  const news = db.dump('admin_news');
  const ids = Object.keys(news);
  assert.strictEqual(ids.length, 1);
  assert.strictEqual(ids[0], api.taxiDueNewsId(res.accountId), 'deterministik ID — qayta ishlasa dublikat yo\'q');
  assert.strictEqual(news[ids[0]].targetUserId, A);
  assert.strictEqual(news[ids[0]].audience, 'user');
  assert.ok(news[ids[0]].body.includes('kelishuv'), 'kelishuv so\'raladi');
  assert.strictEqual(sent.length, 1); assert.strictEqual(sent[0].token, 'tok-A');
  assert.strictEqual(sent[0].data.type, 'taxi_verification_due');
  // Qayta sweep: hech narsa yo'q (idempotent).
  assert.deepStrictEqual(await sw(130), { graceGranted: 0, suspended: 0, verificationRequired: 0 });
  assert.strictEqual(Object.keys(db.dump('admin_news')).length, 1);
  assert.strictEqual(sent.length, 1);
});

ok('D-TAXI-24.1 sweeper: kelishuv ALLAQACHON qabul qilingan → marker yo\'q, xabar faqat tekshiruv haqida', async () => {
  const db = makeDb({ [`users/${A}`]: {} });
  const res = await api.makeRequestCapability({ db, now: () => NOW })({ service: 'taxi' }, ctx(A));
  await db.collection('service_agreements').doc(res.accountId)
    .set({ taxi: { version: caps.AGREEMENT_VERSIONS.taxi, acceptedAt: NOW, acceptedByUid: A } });
  await silent(() => api.makeCapabilitySweeper({ db, now: () => day(124) })());
  const d = capsDump(db)[res.accountId];
  assert.strictEqual(d.status.taxi, caps.TAXI.verificationRequired);
  assert.strictEqual(d.window.taxi.agreementRequestedAt, undefined);
  const news = Object.values(db.dump('admin_news'));
  assert.strictEqual(news.length, 1);
  assert.ok(!news[0].body.includes('kelishuv'));
  assert.ok(news[0].body.includes('admin tekshiruvi'));
});

ok('taksi chekloviga courier TEGILMAYDI (D-TAXI-5, D-13)', async () => {
  const db = makeDb({ [`users/${A}`]: {} });
  const req = api.makeRequestCapability({ db, now: () => NOW });
  await req({ service: 'taxi' }, ctx(A));
  await req({ service: 'courier' }, ctx(A));
  // Kuryer hujjatni topshirdi — uning soati to'xtagan.
  const { id } = onlyDoc(db);
  await db.collection('provider_capabilities').doc(id)
    .set({ status: { courier: caps.COURIER.approved } }, { merge: true });
  await silent(() => api.makeCapabilitySweeper({ db, now: () => day(130) })());
  const d = capsDump(db)[id];
  assert.strictEqual(d.status.taxi, caps.TAXI.verificationRequired);
  assert.strictEqual(d.status.courier, caps.COURIER.approved);
  assert.strictEqual(caps.isEligible(d, 'courier'), true);
});

ok('bo\'sh baza va batchSize', async () => {
  const db = makeDb();
  assert.deepStrictEqual(await silent(() => api.makeCapabilitySweeper({ db, now: () => NOW })()),
    { graceGranted: 0, suspended: 0, verificationRequired: 0 });
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
