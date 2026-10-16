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

  // ══ M4: bron muddati (expirePendingTrips) ════════════════════════════
  const past = () => ts(Date.now() - 60000);
  const seedExpiring = async (id, over = {}) => {
    await seedBooking(id, { status: 'pending', expiresAt: past(), passengers: 2, totalAmount: 100000, userGender: 'male', ...over });
    await db.collection('intercity_drivers').doc(D).collection('clients').doc(P1)
      .set({ bookingCount: 1, totalSpent: 100000 }, { merge: true });
    await db.collection('intercity_booking_locks').doc(`${D}_${P1}`).set({ bookingId: id, driverId: D });
    await db.collection('intercity_passenger_locks').doc(P1).set({ bookingId: id, driverId: D });
  };
  await reset(); await seedDriver({ seats: 1, seatCapacity: 4 });
  await check('M4: muddati o\'tgan pending -> expired, o\'rin qaytdi, mijoz statistikasi va qulflar tozalandi, xabar bor', async () => {
    await seedExpiring('e1');
    await fns.expirePendingTrips.run({});
    assert.strictEqual((await get('intercity_bookings/e1')).status, 'expired');
    assert.strictEqual((await get(`intercity_drivers/${D}`)).seats, 3);
    const c = await get(`intercity_drivers/${D}/clients/${P1}`);
    assert.strictEqual(c.bookingCount, 0); assert.strictEqual(c.totalSpent, 0);
    assert.ok(!(await db.doc(`intercity_booking_locks/${D}_${P1}`).get()).exists);
    assert.ok(!(await db.doc(`intercity_passenger_locks/${P1}`).get()).exists);
    const n = (await notifsTo(P1)).filter((x) => x.bookingId === 'e1');
    assert.strictEqual(n.length, 1); assert.strictEqual(n[0].type, 'intercity_booking_cancelled');
  });
  await check('M4: ikkinchi ishga tushirish o\'rinni YANA qaytarmaydi (idempotent)', async () => {
    await fns.expirePendingTrips.run({}); await fns.expirePendingTrips.run({});
    assert.strictEqual((await get(`intercity_drivers/${D}`)).seats, 3);
    assert.strictEqual((await notifsTo(P1)).filter((x) => x.bookingId === 'e1').length, 1);
  });
  await check('M4: o\'rin seatCapacity\'dan OSHMAYDI (3 + 2 -> 4)', async () => {
    await seedDriver({ seats: 3, seatCapacity: 4 }); await seedExpiring('e2');
    await fns.expirePendingTrips.run({});
    assert.strictEqual((await get('intercity_bookings/e2')).status, 'expired');
    assert.strictEqual((await get(`intercity_drivers/${D}`)).seats, 4);
  });
  await check('M4: haydovchi hujjati yo\'q - bron baribir expired bo\'ladi (avval butun batch yiqilardi)', async () => {
    await db.collection('intercity_drivers').doc(D).delete(); await seedExpiring('e3');
    await fns.expirePendingTrips.run({});
    assert.strictEqual((await get('intercity_bookings/e3')).status, 'expired');
    assert.ok(!(await db.doc(`intercity_drivers/${D}`).get()).exists, 'hujjat qayta yaratilmadi');
  });
  await check('M4: qulf BOSHQA (yangi) bronga tegishli bo\'lsa o\'chirilmaydi', async () => {
    await seedDriver({ seats: 1, seatCapacity: 4 }); await seedExpiring('e4');
    await db.collection('intercity_booking_locks').doc(`${D}_${P1}`).set({ bookingId: 'newer', driverId: D });
    await fns.expirePendingTrips.run({});
    assert.strictEqual((await get('intercity_bookings/e4')).status, 'expired');
    assert.strictEqual((await get(`intercity_booking_locks/${D}_${P1}`)).bookingId, 'newer');
  });
  await check('M4: confirmed bron muddati o\'tgan bo\'lsa ham tegilmaydi (#10)', async () => {
    await seedDriver({ seats: 1, seatCapacity: 4 });
    await seedBooking('e5', { status: 'confirmed', expiresAt: past(), passengers: 1 });
    await fns.expirePendingTrips.run({});
    assert.strictEqual((await get('intercity_bookings/e5')).status, 'confirmed');
    assert.strictEqual((await get(`intercity_drivers/${D}`)).seats, 1);
  });
  const { expireIntercityBooking } = require('../intercity_expiry');
  await check('M4 (poyga): so\'rovdan keyin haydovchi qabul qildi (confirmed) - tranzaksiya qayta tekshiradi, o\'rin QAYTMAYDI', async () => {
    await seedDriver({ seats: 1, seatCapacity: 4 }); await seedExpiring('e6');
    await db.collection('intercity_bookings').doc('e6').update({ status: 'confirmed' }); // accept yutdi
    const r = await expireIntercityBooking({ db, admin, bookingRef: db.collection('intercity_bookings').doc('e6'), nowMs: Date.now() });
    assert.strictEqual(r.skipped, 'not_pending');
    assert.strictEqual((await get('intercity_bookings/e6')).status, 'confirmed');
    assert.strictEqual((await get(`intercity_drivers/${D}`)).seats, 1);
    assert.ok((await db.doc(`intercity_booking_locks/${D}_${P1}`).get()).exists, 'qulf tegilmadi');
  });
  await check('M4 (poyga): bekor qilingan bron expired qilinmaydi; muddati hali o\'tmagan ham', async () => {
    await seedDriver({ seats: 1, seatCapacity: 4 }); await seedExpiring('e7');
    await db.collection('intercity_bookings').doc('e7').update({ status: 'cancelled' });
    const ref = db.collection('intercity_bookings').doc('e7');
    assert.strictEqual((await expireIntercityBooking({ db, admin, bookingRef: ref, nowMs: Date.now() })).skipped, 'not_pending');
    await db.collection('intercity_bookings').doc('e7').update({ status: 'pending', expiresAt: ts(Date.now() + 600000) });
    assert.strictEqual((await expireIntercityBooking({ db, admin, bookingRef: ref, nowMs: Date.now() })).skipped, 'not_expired');
    assert.strictEqual((await get(`intercity_drivers/${D}`)).seats, 1);
  });
  await check('M4 (poyga): parallel ikki expire - o\'rin faqat BIR marta', async () => {
    await seedDriver({ seats: 0, seatCapacity: 4 }); await seedExpiring('e8');
    const ref = db.collection('intercity_bookings').doc('e8');
    const out = await Promise.all([1, 2, 3].map(() => expireIntercityBooking({ db, admin, bookingRef: ref, nowMs: Date.now() })));
    assert.strictEqual(out.filter((o) => o.ok).length, 1);
    assert.strictEqual((await get(`intercity_drivers/${D}`)).seats, 2);
  });

  // ══ M5: eslatma soati ═══════════════════════════════════════════════
  const hhmmTashkent = (ms) => {
    const d = new Date(ms + 5 * 3600000);
    return `${String(d.getUTCHours()).padStart(2, '0')}:${String(d.getUTCMinutes()).padStart(2, '0')}`;
  };
  await reset(); await seedDriver();
  await check('M5: eslatma soati Toshkent (UTC+5) bo\'yicha, server UTC bo\'lsa ham', async () => {
    assert.strictEqual(new Date(Date.UTC(2026, 0, 1, 10, 0)).getHours(), 10, 'test jarayoni UTC\'da bo\'lishi shart');
    const dep = Date.now() + 30 * 60000;
    await seedBooking('m5a', { status: 'confirmed', departureTime: ts(dep), fromCity: 'Gurlan', toCity: 'Toshkent' });
    await fns.expirePendingTrips.run({});
    const n = (await notifsTo(P1)).filter((x) => x.type === 'intercity_departure_reminder');
    assert.strictEqual(n.length, 1);
    assert.ok(n[0].body.includes(`соат ${hhmmTashkent(dep)} да`), `matn: ${n[0].body}, kutilgan ${hhmmTashkent(dep)}`);
    assert.strictEqual((await get('intercity_bookings/m5a')).departureReminderSent, true);
  });
  await check('M5: eslatma BIR marta; oyna tashqarisidagi bron (5 daq / 2 soat) eslatma olmaydi', async () => {
    await seedBooking('m5b', { status: 'confirmed', userPhone: P2, departureTime: ts(Date.now() + 5 * 60000) });
    await seedBooking('m5c', { status: 'confirmed', userPhone: P2, departureTime: ts(Date.now() + 120 * 60000) });
    await fns.expirePendingTrips.run({});
    assert.strictEqual((await notifsTo(P1)).filter((x) => x.type === 'intercity_departure_reminder').length, 1);
    assert.strictEqual((await notifsTo(P2)).filter((x) => x.type === 'intercity_departure_reminder').length, 0);
  });

  // ══ L2: bekor sababi ═══════════════════════════════════════════════
  const TITLE_ENDED = '❌ Рейс бекор — бронингиз ҳам ёпилди';
  const TITLE_PAX = '❌ Брон бекор қилинди';
  const TITLE_DRV = '❌ Ҳайдовчи бронни рад этди';
  const TITLE_TO_DRIVER = '❌ Йўловчи бронни бекор қилди';
  async function cancelCase(id, caller, data, status = 'confirmed') {
    await reset(); await seedDriver(); await seedBooking(id, { status });
    await call('intercityCancelBooking', { bookingId: id, ...data }, caller);
    return {
      b: await get(`intercity_bookings/${id}`),
      pax: await notifsTo(P1),
      drv: await notifsTo(D),
    };
  }
  await check('L2: haydovchi eski ilova matni "рейсни бекор" -> "Рейс бекор" xabari, cancelCause=trip_ended, haydovchiga xabar YO\'Q', async () => {
    const r = await cancelCase('l1', D, { reason: 'Ҳайдовчи рейсни бекор қилди' });
    assert.strictEqual(r.pax[0].title, TITLE_ENDED); assert.strictEqual(r.b.cancelCause, 'trip_ended');
    assert.strictEqual(r.b.cancelReason, 'Ҳайдовчи рейсни бекор қилди', 'eski matn saqlanadi');
    assert.strictEqual(r.drv.length, 0);
  });
  await check('L2: haydovchi eski "yangi reys" matni -> new_trip, "Рейс бекор"', async () => {
    const r = await cancelCase('l2', D, { reason: 'Ҳайдовчи янги рейс очди — аввалги бронлар бекор' });
    // kirill "янги рейс" (ilovaning haqiqiy matni) - avval tripEnded sifatida tanilmagan edi
    assert.strictEqual(r.pax[0].title, TITLE_ENDED); assert.strictEqual(r.b.cancelCause, 'new_trip');
  });
  await check('L2: eski lotin matni "yangi reys" (haydovchi) ham ishlaydi', async () => {
    const r = await cancelCase('l2b', D, { reason: 'Haydovchi yangi reys ochdi' });
    assert.strictEqual(r.pax[0].title, TITLE_ENDED); assert.strictEqual(r.b.cancelCause, 'new_trip');
  });
  await check('L2: aniq `cause`: trip_ended (matnsiz) - haydovchi', async () => {
    const r = await cancelCase('l3', D, { cause: 'trip_ended', reason: 'x' });
    assert.strictEqual(r.pax[0].title, TITLE_ENDED); assert.strictEqual(r.b.cancelCause, 'trip_ended');
  });
  await check('L2: yo\'lovchi "рейсни бекор" matni yuborsa - YO\'LOVCHI bekori bo\'lib qoladi: haydovchiga xabar boradi', async () => {
    const r = await cancelCase('l4', P1, { reason: 'Ҳайдовчи рейсни бекор қилди (soxta)' });
    assert.strictEqual(r.b.cancelCause, 'passenger');
    assert.strictEqual(r.pax[0].title, TITLE_PAX);
    assert.strictEqual(r.drv.length, 1); assert.strictEqual(r.drv[0].title, TITLE_TO_DRIVER);
  });
  await check('L2: yo\'lovchi `cause: trip_ended` yuborsa ham e\'tiborsiz', async () => {
    const r = await cancelCase('l5', P1, { cause: 'trip_ended', reason: '' });
    assert.strictEqual(r.b.cancelCause, 'passenger'); assert.strictEqual(r.drv.length, 1);
  });
  await check('L2: haydovchi sababsiz rad etadi (pending) -> driver_reject, "Ҳайдовчи бронни рад этди"', async () => {
    const r = await cancelCase('l6', D, { reason: '' }, 'pending');
    assert.strictEqual(r.b.cancelCause, 'driver_reject'); assert.strictEqual(r.pax[0].title, TITLE_DRV);
  });
  await check('L2: noma\'lum `cause` qiymati e\'tiborsiz (haydovchi) -> driver_reject', async () => {
    const r = await cancelCase('l7', D, { cause: 'bogus', reason: '' });
    assert.strictEqual(r.b.cancelCause, 'driver_reject');
  });
  await check('L2: admin bekor qiladi -> cancelCause=admin, yo\'lovchiga oddiy bekor xabari', async () => {
    const r = await cancelCase('l8', ADMIN, { reason: 'admin' });
    assert.strictEqual(r.b.cancelCause, 'admin'); assert.strictEqual(r.pax[0].title, TITLE_PAX);
  });
  await check('L2: o\'rin qaytishi o\'zgarmagan (cap bilan), ikkinchi bekor {ok:false, skipped}', async () => {
    await reset(); await seedDriver({ seats: 1, seatCapacity: 4 }); await seedBooking('l9', { status: 'confirmed', passengers: 2 });
    await call('intercityCancelBooking', { bookingId: 'l9', reason: '' }, P1);
    assert.strictEqual((await get(`intercity_drivers/${D}`)).seats, 3);
    const again = await call('intercityCancelBooking', { bookingId: 'l9', reason: '' }, P1);
    assert.deepStrictEqual({ ok: again.ok, skipped: again.skipped }, { ok: false, skipped: 'not_active' });
    assert.strictEqual((await get(`intercity_drivers/${D}`)).seats, 3);
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed}/${results.length} intercity audit CF checks passed.`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
