/**
 * Marshrut yo'lovchi dispatch'i SERVERDA (2-bosqich, ega qarori 2026-10-08).
 *
 *   firebase emulators:exec --only firestore --project demo-marshrut-dispatch \
 *     "node functions/test/marshrut_passenger_dispatch_cf.test.js"
 *
 * Avval yo'lovchi ilovasi BEGONA haydovchi hujjatlariga o'zi yozardi
 * (`rides_repository.dart`): offer timeout → drivers/schedules/queue
 * `todayTimeouts` +1, streak, avto-pauza; kutishda bekor → queue streak 0;
 * qabuldan keyin bekor → `isBusy:false`, o'rin +1. Shu sabab rules begona
 * yozuvni yopa olmasdi (driver_work_patch_rules.test.js R11–R19).
 * Endi bular callable'larda:
 *   `marshrutPassengerCloseOffer` {tripId, outcome: expired|cancelled}
 *   `marshrutPassengerCancelAfterAccept` (mavjud) — qayta chaqiruv xavfsiz.
 * Sweep (`expirePendingTrips`) va callable bir trip'ni IKKI MARTA
 * hisoblamaydi: yopish + siyosat bitta tranzaksiyada, faqat `pending` bo'lsa.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-marshrut-dispatch';
process.env.FUNCTIONS_EMULATOR = 'true';

const fns = require('../index.js');
const admin = require('firebase-admin');
const db = admin.firestore();

const PASSENGER = '998901000001';
const DRIVER = '998902000001';
const STRANGER = '998903000001';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const close = (data, who = PASSENGER) => fns.marshrutPassengerCloseOffer.run(data, ctxOf(who));
const cancelAccepted = (data, who = PASSENGER) =>
  fns.marshrutPassengerCancelAfterAccept.run(data, ctxOf(who));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
const rejects = async (p, code) => {
  try { await p; } catch (e) {
    assert.strictEqual(e.code, code, `kutilgan ${code}, keldi ${e.code}: ${e.message}`);
    return;
  }
  throw new Error(`kutilgan xato ${code}, lekin muvaffaqiyat`);
};

async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => d.ref.delete()));
}
const get = async (col, id) => (await db.collection(col).doc(id).get()).data() || {};
const active = async () => (await db.collection('users').doc(PASSENGER)
    .collection('marshrut_state').doc('active').get()).data() || {};
const events = async (type) => (await db.collection('marshrut_dispatch_events')
    .where('type', '==', type).get()).size;

async function reset({ streak = 0, pauseAt = 3, trip = {} } = {}) {
  await Promise.all(['users', 'trips', 'drivers', 'schedules', 'queue', 'settings',
    'marshrut_dispatch_events'].map(wipe));
  await wipe(`users/${PASSENGER}/marshrut_state`);
  await wipe(`users/${PASSENGER}/marshrut_block`);
  await db.collection('settings').doc('app').set({ marshrutTimeoutAutoPauseStreak: pauseAt });
  await db.collection('users').doc(PASSENGER).set({ role: 'user' });
  await db.collection('users').doc(DRIVER).set({ role: 'user' });
  await db.collection('drivers').doc(DRIVER).set({
    name: 'Rustam', phone: `+${DRIVER}`, taxiType: 'marshrut', isBusy: true, todayTimeouts: 0,
  });
  await db.collection('schedules').doc('S1').set({
    driverId: DRIVER, taxiType: 'marshrut', seats: 7, seatsLeft: 3, todayTimeouts: 0, isActive: true,
  });
  await db.collection('queue').doc(DRIVER).set({
    driverId: DRIVER, taxiType: 'marshrut', seats: 7, seatsLeft: 3, isActive: true,
    dispatchTimeoutStreak: streak, dispatchTimeoutCount: 0, todayTimeouts: 0,
  });
  await db.collection('trips').doc('T1').set({
    userPhone: PASSENGER, taxiType: 'marshrut', status: 'pending', pickupAddr: 'A',
    targetDriverId: DRIVER, scheduleId: 'S1', dispatchSessionId: 'md_1',
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 60000),
    ...trip,
  });
  await db.collection('users').doc(PASSENGER).collection('marshrut_state').doc('active')
      .set({ tripId: 'T1', sessionId: 'md_1', status: 'pending' });
}

async function main() {
  // ── E. Offer timeout → server (avval yo'lovchi klienti) ──────────────
  await reset();
  await check('E1 timeout: trip expired + drivers/schedules/queue todayTimeouts +1, streak +1, event, state', async () => {
    const r = await close({ tripId: 'T1', outcome: 'expired' });
    assert.strictEqual(r.closed, true);
    assert.strictEqual((await get('trips', 'T1')).status, 'expired');
    assert.ok((await get('trips', 'T1')).expiredAt, 'expiredAt');
    assert.strictEqual((await get('drivers', DRIVER)).todayTimeouts, 1);
    assert.strictEqual((await get('schedules', 'S1')).todayTimeouts, 1);
    const q = await get('queue', DRIVER);
    assert.strictEqual(q.dispatchTimeoutStreak, 1);
    assert.strictEqual(q.dispatchTimeoutCount, 1);
    assert.strictEqual(q.todayTimeouts, 1);
    assert.strictEqual(q.isActive, true, 'streak 1 < 3 — pauza yo\'q');
    assert.strictEqual(await events('timeout'), 1);
    assert.strictEqual((await active()).status, 'expired');
  });
  await check('E2 qayta chaqiruv (retry) — ikkinchi marta HISOBLANMAYDI', async () => {
    const r = await close({ tripId: 'T1', outcome: 'expired' });
    assert.strictEqual(r.closed, false);
    assert.strictEqual(r.status, 'expired');
    assert.strictEqual((await get('drivers', DRIVER)).todayTimeouts, 1);
    assert.strictEqual((await get('queue', DRIVER)).dispatchTimeoutStreak, 1);
    assert.strictEqual(await events('timeout'), 1);
  });
  await check('E3 sweep keyin ham — ikkinchi marta hisoblamaydi (trip endi pending emas)', async () => {
    await fns.expirePendingTrips.run({});
    assert.strictEqual((await get('drivers', DRIVER)).todayTimeouts, 1);
    assert.strictEqual(await events('timeout'), 1);
  });

  await reset({ streak: 2, pauseAt: 3 });
  await check('E4 streak chegarasida avto-pauza: queue isActive=false + driver_auto_paused event', async () => {
    await close({ tripId: 'T1', outcome: 'expired' });
    const q = await get('queue', DRIVER);
    assert.strictEqual(q.dispatchTimeoutStreak, 3);
    assert.strictEqual(q.isActive, false);
    assert.strictEqual(q.autoPausedReason, 'dispatch_timeout_streak');
    assert.ok(q.autoPausedAt);
    assert.strictEqual(await events('driver_auto_paused'), 1);
  });

  await reset();
  await check('E5 begona odam boshqaning taklifini yopa OLMAYDI (permission-denied, o\'zgarish yo\'q)', async () => {
    await rejects(close({ tripId: 'T1', outcome: 'expired' }, STRANGER), 'permission-denied');
    assert.strictEqual((await get('trips', 'T1')).status, 'pending');
    assert.strictEqual((await get('drivers', DRIVER)).todayTimeouts, 0);
  });
  await check('E6 haydovchi ham yo\'lovchi taklifini yopa olmaydi', async () => {
    await rejects(close({ tripId: 'T1', outcome: 'expired' }, DRIVER), 'permission-denied');
  });
  await check('E7 telefonsiz/kirmagan — unauthenticated', async () => {
    await rejects(fns.marshrutPassengerCloseOffer.run({ tripId: 'T1', outcome: 'expired' }, {}), 'unauthenticated');
    await rejects(fns.marshrutPassengerCloseOffer.run({ tripId: 'T1', outcome: 'expired' },
        { auth: { uid: 'anon', token: {} } }), 'unauthenticated');
  });
  await check('E8 noto\'g\'ri outcome / tripId yo\'q — invalid-argument', async () => {
    await rejects(close({ tripId: 'T1', outcome: 'completed' }), 'invalid-argument');
    await rejects(close({ outcome: 'expired' }), 'invalid-argument');
  });
  await check('E9 mavjud bo\'lmagan trip — not-found', async () => {
    await rejects(close({ tripId: 'NOPE', outcome: 'expired' }), 'not-found');
  });
  await check('E10 marshrut bo\'lmagan trip — failed-precondition', async () => {
    await db.collection('trips').doc('L1').set({ userPhone: PASSENGER, taxiType: 'local', status: 'searching' });
    await rejects(close({ tripId: 'L1', outcome: 'cancelled' }), 'failed-precondition');
  });

  // ── C. Kutishda bekor (pending) — avval klient queue streak'ini 0 qilardi
  await reset({ streak: 2 });
  await check('C1 pending bekor: trip cancelled (user), queue streak 0, timeout HISOBLANMAYDI, event, state', async () => {
    const r = await close({ tripId: 'T1', outcome: 'cancelled' });
    assert.strictEqual(r.closed, true);
    const t = await get('trips', 'T1');
    assert.strictEqual(t.status, 'cancelled');
    assert.strictEqual(t.cancelledBy, 'user');
    assert.ok(t.cancelledAt);
    assert.strictEqual((await get('queue', DRIVER)).dispatchTimeoutStreak, 0);
    assert.strictEqual((await get('drivers', DRIVER)).todayTimeouts, 0);
    assert.strictEqual(await events('cancelled'), 1);
    assert.strictEqual((await active()).status, 'cancelled');
  });
  await reset({ trip: { status: 'accepted', acceptedDriverId: DRIVER } });
  await check('C2 bekor paytida haydovchi allaqachon qabul qilgan — o\'zgarishsiz status:accepted qaytadi', async () => {
    const r = await close({ tripId: 'T1', outcome: 'cancelled' });
    assert.strictEqual(r.closed, false);
    assert.strictEqual(r.status, 'accepted');
    assert.strictEqual((await get('trips', 'T1')).status, 'accepted');
    assert.strictEqual((await get('drivers', DRIVER)).isBusy, true);
  });

  // ── A. Qabuldan keyin bekor — mavjud CF, endi yagona yo'l ─────────────
  await check('A1 accepted bekor: o\'rin +1 (schedules, queue), isBusy=false, trip cancelled', async () => {
    const r = await cancelAccepted({ tripId: 'T1', reason: 'passenger_cancel_after_accept' });
    assert.strictEqual(r.ok, true);
    const t = await get('trips', 'T1');
    assert.strictEqual(t.status, 'cancelled');
    assert.strictEqual(t.cancelledBy, 'passenger');
    assert.strictEqual((await get('schedules', 'S1')).seatsLeft, 4);
    assert.strictEqual((await get('queue', DRIVER)).seatsLeft, 4);
    assert.strictEqual((await get('drivers', DRIVER)).isBusy, false);
  });
  await check('A2 qayta chaqiruv (javob yo\'qolgan) — ok, o\'rin IKKINCHI marta qaytmaydi', async () => {
    const r = await cancelAccepted({ tripId: 'T1', reason: 'passenger_cancel_after_accept' });
    assert.strictEqual(r.ok, true);
    assert.strictEqual(r.duplicate, true);
    assert.strictEqual((await get('schedules', 'S1')).seatsLeft, 4);
    assert.strictEqual((await get('queue', DRIVER)).seatsLeft, 4);
  });
  await reset({ trip: { status: 'accepted', acceptedDriverId: DRIVER } });
  await check('A3 begona qabul qilingan safarni bekor qila olmaydi', async () => {
    await rejects(cancelAccepted({ tripId: 'T1' }, STRANGER), 'permission-denied');
    assert.strictEqual((await get('trips', 'T1')).status, 'accepted');
  });
  await reset({ trip: { status: 'cancelled', cancelledBy: 'driver' } });
  await check('A4 haydovchi bekor qilgan safar — yo\'lovchi uchun duplicate EMAS (failed-precondition)', async () => {
    await rejects(cancelAccepted({ tripId: 'T1' }), 'failed-precondition');
  });

  // ── S. Sweep (`expirePendingTrips`) — eski xatti-harakat saqlanadi ────
  await reset({ trip: { expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 5000) } });
  await check('S1 sweep muddati o\'tgan pending marshrut trip\'ni yopadi va BIR MARTA hisoblaydi', async () => {
    await fns.expirePendingTrips.run({});
    assert.strictEqual((await get('trips', 'T1')).status, 'expired');
    assert.strictEqual((await get('drivers', DRIVER)).todayTimeouts, 1);
    assert.strictEqual((await get('queue', DRIVER)).dispatchTimeoutStreak, 1);
    assert.strictEqual(await events('timeout'), 1);
    assert.strictEqual((await active()).status, 'expired');
  });
  await check('S2 sweep qayta ishlasa — o\'zgarish yo\'q', async () => {
    await fns.expirePendingTrips.run({});
    assert.strictEqual((await get('drivers', DRIVER)).todayTimeouts, 1);
    assert.strictEqual(await events('timeout'), 1);
  });
  await check('S3 sweep\'dan keyin callable — yopilgan, hisoblamaydi', async () => {
    const r = await close({ tripId: 'T1', outcome: 'expired' });
    assert.strictEqual(r.closed, false);
    assert.strictEqual((await get('drivers', DRIVER)).todayTimeouts, 1);
  });
  await reset({ trip: { taxiType: 'local', status: 'searching',
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 5000) } });
  await check('S4 sweep mahalliy taksini avvalgidek expired qiladi, marshrut siyosati qo\'llanmaydi', async () => {
    await fns.expirePendingTrips.run({});
    assert.strictEqual((await get('trips', 'T1')).status, 'expired');
    assert.strictEqual((await get('drivers', DRIVER)).todayTimeouts, 0);
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed}/${results.length} marshrut passenger dispatch CF checks passed.`);
  process.exit(failed ? 1 : 0);
}
main().catch((e) => { console.error('FATAL', e); process.exit(1); });
