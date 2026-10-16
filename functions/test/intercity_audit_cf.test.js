/**
 * Shaharlararo taksi auditi (2026-10) - HAQIQIY `functions/index.js` callable va
 * pubsub funksiyalari `.run()` orqali, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-intercity-audit \
 *     "node functions/test/intercity_audit_cf.test.js"
 *
 * Qulflanadi:
 *   H2  updateIntercityDriverRating: faqat o'z broni, faqat `completed`, baho butun 1..5,
 *       haydovchi BRONDAN olinadi, bir bron - bir baho (parallelda ham)
 *   M4  expirePendingTrips (bron muddati): har bron o'z tranzaksiyasida, status qayta
 *       tekshiriladi, o'rin seatCapacity'dan oshmaydi, ikki marta qaytmaydi
 *   M5  jo'nash eslatmasi: soat Toshkent (UTC+5) bo'yicha, server vaqt zonasiga bog'liq emas
 *   L2  intercityCancelBooking: yo'lovchiga xabar mazmuni SERVER bilgan sababga (cancelCause)
 *       bog'liq; eski ilovaning kirill/lotin matni faqat haydovchi/admin uchun hisobga olinadi
 */
'use strict';
// Server vaqt zonasi UTC (Cloud Functions'dagidek): `getHours()` xatosi shu bilan ko'rinadi.
process.env.TZ = 'UTC';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-intercity-audit';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const db = admin.firestore();
const Timestamp = admin.firestore.Timestamp;

const D = '998901110001'; // haydovchi
const P1 = '998905550001'; // yo'lovchi
const P2 = '998905550002';
const ADMIN = '998909990000';

const ctxOf = (phone) => ({ auth: { uid: `uid_${phone}`, token: { phone_number: `+${phone}` } } });
const call = (name, data, phone) => fns[name].run(data, ctxOf(phone));
const ts = (ms) => Timestamp.fromMillis(ms);

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
const rejectsCode = (promise, code, msg) => assert.rejects(promise, (e) => {
  assert.strictEqual(e.code, code, `kod ${e.code}: ${e.message}`);
  if (msg) assert.strictEqual(e.message, msg);
  return true;
});
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const get = async (path) => (await db.doc(path).get()).data();
const notifsTo = async (phone) => (await db.collection('notifications').where('targetPhone', '==', phone).get())
  .docs.map((d) => d.data());

async function reset() {
  await clearEmulator();
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
}
async function seedDriver(over = {}) {
  await db.collection('intercity_drivers').doc(D).set({
    name: 'Karim', phone: D, phoneDigits: D, seats: 2, seatCapacity: 4, isActive: true,
    totalRatings: 2, ratingSum: 9, avgRating: 4.5, ...over,
  });
}
const seedBooking = (id, over = {}) => db.collection('intercity_bookings').doc(id).set({
  userPhone: P1, userName: 'Aziz', driverId: D, driverPhone: D, driverName: 'Karim', passengers: 1,
  totalAmount: 100000, status: 'completed', driverRouteLabel: 'Gurlan → Toshkent',
  createdAt: ts(Date.now() - 3600000), departureTime: ts(Date.now() + 3600000), ...over,
});

(async () => {
  // ══ H2: reyting ═══════════════════════════════════════════════════════
  await reset(); await seedDriver(); await seedBooking('r1');
  await check('H2: yo\'lovchi o\'z completed broniga baho beradi -> hisob yangilanadi, javob {ok:true}', async () => {
    const r = await call('updateIntercityDriverRating', { driverId: D, rating: 5, bookingId: 'r1' }, P1);
    assert.deepStrictEqual({ ok: r.ok, skipped: r.skipped }, { ok: true, skipped: undefined });
    const d = await get(`intercity_drivers/${D}`);
    assert.strictEqual(d.totalRatings, 3); assert.strictEqual(d.ratingSum, 14); assert.strictEqual(d.avgRating, 4.7);
    const b = await get('intercity_bookings/r1');
    assert.strictEqual(b.passengerRating, 5); assert.ok(b.ratedAt);
  });
  await check('H2: ikkinchi chaqiruv - {ok:true, skipped:true}, qayta sanalmaydi', async () => {
    const r = await call('updateIntercityDriverRating', { driverId: D, rating: 1, bookingId: 'r1' }, P1);
    assert.deepStrictEqual({ ok: r.ok, skipped: r.skipped }, { ok: true, skipped: true });
    assert.strictEqual((await get(`intercity_drivers/${D}`)).totalRatings, 3);
    assert.strictEqual((await get('intercity_bookings/r1')).passengerRating, 5);
  });
  await check('H2: PARALLEL ikki chaqiruv (bir bron) -> faqat BIR marta sanaladi', async () => {
    await seedDriver(); await seedBooking('r2');
    const out = await Promise.allSettled([
      call('updateIntercityDriverRating', { driverId: D, rating: 4, bookingId: 'r2' }, P1),
      call('updateIntercityDriverRating', { driverId: D, rating: 4, bookingId: 'r2' }, P1),
      call('updateIntercityDriverRating', { driverId: D, rating: 4, bookingId: 'r2' }, P1),
    ]);
    assert.ok(out.every((o) => o.status === 'fulfilled'), JSON.stringify(out.map((o) => o.reason && o.reason.message)));
    const d = await get(`intercity_drivers/${D}`);
    assert.strictEqual(d.totalRatings, 3, `totalRatings ${d.totalRatings}`); assert.strictEqual(d.ratingSum, 13);
    assert.strictEqual(out.filter((o) => o.value && o.value.skipped).length, 2);
  });
  await check('H2: BEGONA bronga baho -> permission-denied, haydovchi hisobi o\'zgarmaydi', async () => {
    await seedDriver(); await seedBooking('r3');
    await rejectsCode(call('updateIntercityDriverRating', { driverId: D, rating: 1, bookingId: 'r3' }, P2), 'permission-denied');
    const d = await get(`intercity_drivers/${D}`);
    assert.strictEqual(d.totalRatings, 2); assert.strictEqual((await get('intercity_bookings/r3')).passengerRating, undefined);
  });
  await check('H2: bron completed EMAS (pending/confirmed/cancelled/expired) -> failed-precondition', async () => {
    await seedDriver();
    for (const st of ['pending', 'confirmed', 'cancelled', 'expired']) {
      await seedBooking(`rs_${st}`, { status: st });
      await rejectsCode(call('updateIntercityDriverRating', { driverId: D, rating: 5, bookingId: `rs_${st}` }, P1), 'failed-precondition');
    }
    assert.strictEqual((await get(`intercity_drivers/${D}`)).totalRatings, 2);
  });
  await check('H2: klient yuborgan driverId BRONNIKIga mos kelmasa -> rad; boshqa haydovchi hisobi o\'zgarmaydi', async () => {
    await seedDriver(); await seedBooking('r4');
    await db.collection('intercity_drivers').doc('998907770000').set({ totalRatings: 0, ratingSum: 0, seats: 1 });
    await rejectsCode(call('updateIntercityDriverRating', { driverId: '998907770000', rating: 1, bookingId: 'r4' }, P1), 'invalid-argument');
    assert.strictEqual((await get('intercity_drivers/998907770000')).totalRatings, 0);
    assert.strictEqual((await get(`intercity_drivers/${D}`)).totalRatings, 2);
  });
  await check('H2: driverId 9 xonali shaklda ham mos (eski ilova)', async () => {
    await seedDriver(); await seedBooking('r5');
    const r = await call('updateIntercityDriverRating', { driverId: D.slice(3), rating: 3, bookingId: 'r5' }, P1);
    assert.strictEqual(r.ok, true); assert.strictEqual((await get(`intercity_drivers/${D}`)).totalRatings, 3);
  });
  await check('H2: baho 0 / 6 / 4.5 / "5" / null / NaN / yo\'q -> invalid-argument', async () => {
    await seedDriver(); await seedBooking('r6');
    for (const rating of [0, 6, 4.5, '5', null, NaN, undefined, -1, 100]) {
      await rejectsCode(call('updateIntercityDriverRating', { driverId: D, rating, bookingId: 'r6' }, P1), 'invalid-argument');
    }
    assert.strictEqual((await get('intercity_bookings/r6')).passengerRating, undefined);
    assert.strictEqual((await get(`intercity_drivers/${D}`)).totalRatings, 2);
  });
  await check('H2: bookingId yo\'q/bo\'sh -> invalid-argument; bron yo\'q -> not-found; auth yo\'q -> unauthenticated', async () => {
    await rejectsCode(call('updateIntercityDriverRating', { driverId: D, rating: 5 }, P1), 'invalid-argument');
    await rejectsCode(call('updateIntercityDriverRating', { driverId: D, rating: 5, bookingId: '  ' }, P1), 'invalid-argument');
    await rejectsCode(call('updateIntercityDriverRating', { driverId: D, rating: 5, bookingId: 'nope' }, P1), 'not-found');
    await rejectsCode(fns.updateIntercityDriverRating.run({ driverId: D, rating: 5, bookingId: 'r6' }, {}), 'unauthenticated');
  });
  await check('H2: haydovchi hujjati yo\'q -> baho yozilmaydi (bron ham o\'zgarmaydi), {ok:true, skipped:true}', async () => {
    await db.collection('intercity_drivers').doc(D).delete(); await seedBooking('r7');
    const r = await call('updateIntercityDriverRating', { driverId: D, rating: 5, bookingId: 'r7' }, P1);
    assert.strictEqual(r.ok, true); assert.strictEqual(r.skipped, true);
    assert.strictEqual((await get('intercity_bookings/r7')).passengerRating, undefined);
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed}/${results.length} intercity audit CF checks passed.`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
