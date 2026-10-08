/**
 * Haydovchi ish holati — BEGONA yozuv (2026-10-08 topilma).
 *
 *   firebase emulators:exec --only firestore --project demo-driver-work \
 *     "node functions/test/driver_work_patch_rules.test.js"
 *
 * `drivers/{id}` update qoidasidagi `driverWorkPatchOnly()` va
 * `marshrutDriverRegisterPatch()` faqat ikki narsani tekshiradi:
 * MAQSAD haydovchining taksi capability'si va o'zgargan maydon nomlari.
 * Kim yozayotgani (`isAuth()` / `isOwner()`) — tekshirilmaydi. Xuddi shu
 * shakl `schedules` dagi `scheduleLifecyclePatchOnly()` va
 * `users/{id}/driverProfiles` dagi `marshrutDriverProfileGuestWriteOk()`
 * da ham bor. Bu 2026-09-24 da olib tashlangan
 * `intercityDriverSeatBookingPatch` bilan bir xil teshik.
 *
 * Qo'shimcha: mahalliy taksi broadcast accept (`localTripLifecycleUpdate`
 * → `isBroadcastAccept`) haydovchi ≠ yo'lovchi ekanini tekshirmaydi.
 *
 * `queue/{driverId}` da undan ham keng edi: oxirgi shoxcha auth'siz HAR
 * QANDAY maydonga (yo'lovchi qo'ng'iroq qiladigan `driverPhone` ham) ruxsat
 * berardi, `queueGuestDispatchPatchOnly` esa aynan KIRMAGAN klientga.
 *
 * Guruhlar:
 *   H. Teshik — FAIL bo'lsa, begona/anonim yozuv o'tyapti.
 *   R. Qonuniy oqim (regression) — ishlashi SHART. R11–R19 — marshrut
 *      YO'LOVCHISINING begona haydovchi hujjatlariga yozuvi (ilovada bor,
 *      1.0.32 da ham): shu sabab begona yozuv to'liq yopilmadi.
 *
 * Tuzatishdan oldin (2026-10-08, feat/ev-trip-planner dd394d3): 21/40 —
 * H12/H13 dan boshqa barcha H o'tib ketardi.
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { increment, serverTimestamp } = require('firebase/firestore');

const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');

const ADMIN = '998909990001';
/** Mahalliy taksi haydovchisi (verified, alone). */
const LOCAL = '998902000001';
/** Marshrut haydovchisi (starter). */
const MARSH = '998902000002';
/** Shahar-aro haydovchi (verification_required — operate ruxsat). */
const INTER = '998902000003';
/** Oddiy foydalanuvchi — hujumchi. */
const ATTACKER = '998903000001';
/** Yo'lovchi. */
const PASSENGER = '998901000001';
/** O'zi ham haydovchi bo'lgan yo'lovchi (self-accept). */
const SELF = '998902000004';

const CAP = {
  [LOCAL]: ['accLOCAL', 'verified', ['alone']],
  [MARSH]: ['accMARSH', 'starter', ['marshrut']],
  [INTER]: ['accINTER', 'verification_required', ['intercity']],
  [SELF]: ['accSELF', 'verified', ['alone']],
};

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-driver-work',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const record = (n, p, d) => { results.push({ n, p }); console.log(`${p ? 'PASS' : 'FAIL'} - ${n}${d ? ' :: ' + d : ''}`); };
  const check = async (n, fn) => { try { await fn(); record(n, true); } catch (e) { record(n, false, e.message); } };

  const seed = async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('users').doc(ADMIN).set({ role: 'admin' });
      await db.collection('users').doc(ATTACKER).set({ role: 'user' });
      await db.collection('users').doc(PASSENGER).set({ role: 'user' });
      for (const [uid, [acc, status, types]] of Object.entries(CAP)) {
        await db.collection('users').doc(uid).set({ role: 'user', accountId: acc });
        await db.collection('provider_capabilities').doc(acc).set({
          identity: { accountId: acc, primaryUid: uid },
          taxi: { active: true, taxiTypes: types },
          status: { taxi: status },
        });
      }
      // `drivers/{id}` — CF (Admin SDK) yaratgan profil.
      await db.collection('drivers').doc(LOCAL).set({
        name: 'Ali', phone: `+${LOCAL}`, car: 'Cobalt', plate: '90A123AA',
        taxiType: 'alone', isOnline: true, isAvailable: true, isBusy: false,
        lat: 41.84, lng: 60.39,
      });
      await db.collection('drivers').doc(MARSH).set({
        name: 'Rustam', phone: `+${MARSH}`, car: 'Damas', plate: '95A123BB',
        taxiType: 'marshrut', seats: 7, seatsLeft: 7, stops: ['Gurlan', 'Urganch'],
        isOnline: true, isAvailable: true,
      });
      await db.collection('drivers').doc(INTER).set({
        name: 'Vali', phone: `+${INTER}`, taxiType: 'intercity',
        isOnline: false, seats: 4, seatsLeft: 4,
      });
      await db.collection('schedules').doc('sched_inter').set({
        driverId: INTER, taxiType: 'intercity', date: '2026-10-08',
        seats: 4, seatsLeft: 4, isActive: true,
      });
      await db.collection('schedules').doc('sched_marsh').set({
        driverId: MARSH, taxiType: 'marshrut', date: '2026-10-08',
        seats: 7, seatsLeft: 3, isActive: true, todayTimeouts: 2,
      });
      // Yo'lovchilar ko'radigan navbat hujjati (driverPhone ochiq).
      await db.collection('queue').doc(MARSH).set({
        driverId: MARSH, driverName: 'Rustam', driverPhone: `+${MARSH}`,
        car: 'Damas', plate: '95A123BB', taxiType: 'marshrut',
        seats: 7, seatsLeft: 3, isActive: true, dispatchTimeoutStreak: 1,
      });
      await db.collection('users').doc(MARSH).collection('driverProfiles').doc('marshrut').set({
        carModel: 'Damas', plate: '95A123BB', seats: 7, stops: ['Gurlan', 'Urganch'],
        driverName: 'Rustam', driverPhone: `+${MARSH}`,
      });
      // Mahalliy taksi: SELF o'zi yaratgan qidiruv.
      await db.collection('trips').doc('self_trip').set({
        userPhone: SELF, fromAddr: 'Gurlan markaz', fromLat: 41.84, fromLng: 60.39,
        status: 'searching', taxiType: 'local', radiusKm: 3,
      });
      await db.collection('trips').doc('pass_trip').set({
        userPhone: PASSENGER, fromAddr: 'Gurlan markaz', fromLat: 41.84, fromLng: 60.39,
        status: 'searching', taxiType: 'local', radiusKm: 3,
      });
    });
  };

  const ctxFor = (p) => testEnv.authenticatedContext(`uid_${p}`, { phone_number: '+' + p });
  const unauth = testEnv.unauthenticatedContext().firestore();
  /** Anonymous Auth — token bor, telefon yo'q. */
  const anon = testEnv.authenticatedContext('anon_uid_1', {}).firestore();
  const attacker = ctxFor(ATTACKER).firestore();
  const local = ctxFor(LOCAL).firestore();
  const marsh = ctxFor(MARSH).firestore();
  const inter = ctxFor(INTER).firestore();
  const self = ctxFor(SELF).firestore();
  const adminDb = ctxFor(ADMIN).firestore();

  const drv = (db, id) => db.collection('drivers').doc(id);
  const prof = (db, id) => db.collection('users').doc(id).collection('driverProfiles').doc('marshrut');
  const now = () => new Date();

  await seed();

  // ── H. drivers — driverWorkPatchOnly ────────────────────────────────
  await check('H1 kirmagan klient mahalliy haydovchini OFFLINE qila olmaydi',
    () => assertFails(drv(unauth, LOCAL).update({ isOnline: false, isAvailable: false, updatedAt: now() })));
  await check('H2 kirmagan klient haydovchi joylashuvini (lat/lng) siljita olmaydi',
    () => assertFails(drv(unauth, LOCAL).update({ lat: 40.0, lng: 70.0, updatedAt: now() })));
  await check('H3 anonim (telefonsiz token) haydovchini band (isBusy) qila olmaydi',
    () => assertFails(drv(anon, LOCAL).update({ isBusy: true, updatedAt: now() })));
  await check('H4 begona foydalanuvchi haydovchini offline qila olmaydi',
    () => assertFails(drv(attacker, LOCAL).update({ isOnline: false, updatedAt: now() })));
  await check('H5 boshqa HAYDOVCHI raqibini offline qila olmaydi',
    () => assertFails(drv(marsh, LOCAL).update({ isOnline: false, isAvailable: false, updatedAt: now() })));
  await check('H6 begona verification_required haydovchining o\'rinlarini 0 qila olmaydi',
    () => assertFails(drv(attacker, INTER).update({ seatsLeft: 0, updatedAt: now() })));
  await check('H7 begona hisoblagichlarni (todayRejects) buzolmaydi',
    () => assertFails(drv(attacker, LOCAL).update({ todayRejects: 99, todayTimeouts: 99 })));

  // ── H. drivers — marshrutDriverRegisterPatch ────────────────────────
  await check('H8 kirmagan klient marshrut haydovchining TELEFONINI almashtira olmaydi',
    () => assertFails(drv(unauth, MARSH).update({ phone: `+${ATTACKER}`, updatedAt: now() })));
  await check('H9 begona marshrut haydovchining ism/mashina/raqamini o\'zgartira olmaydi',
    () => assertFails(drv(attacker, MARSH).update({
      name: 'Soxta', car: 'Matiz', plate: '00X000XX', updatedAt: now(),
    })));

  // ── H. schedules — scheduleLifecyclePatchOnly ───────────────────────
  await check('H10 kirmagan klient begona jadvalni o\'chira (isActive:false) olmaydi',
    () => assertFails(unauth.collection('schedules').doc('sched_inter').update({ isActive: false, updatedAt: now() })));
  await check('H11 begona foydalanuvchi jadvaldagi bo\'sh o\'rinni 0 qila olmaydi',
    () => assertFails(attacker.collection('schedules').doc('sched_inter').update({ seatsLeft: 0, updatedAt: now() })));

  // ── H. users/{id}/driverProfiles — marshrutDriverProfileGuestWriteOk
  await check('H12 kirmagan klient marshrut profilidagi driverPhone ni almashtira olmaydi',
    () => assertFails(prof(unauth, MARSH).update({ driverPhone: `+${ATTACKER}`, updatedAt: now() })));
  await check('H13 begona marshrut profilidagi raqam/mashinani o\'zgartira olmaydi',
    () => assertFails(prof(attacker, MARSH).update({ plate: '00X000XX', carModel: 'Matiz' })));

  // ── H. trips — mahalliy accept: haydovchi ≠ yo'lovchi ───────────────
  const acceptPatch = (uid) => ({
    status: 'accepted',
    acceptedDriverId: uid, driverId: uid,
    acceptedDriverName: 'D', driverName: 'D',
    acceptedDriverPhone: uid, driverPhone: uid,
    acceptedDriverCar: 'Cobalt', acceptedDriverPlate: '90A123AA',
    acceptedAt: now(),
  });
  await check('H14 haydovchi O\'ZI yaratgan safarni qabul qila olmaydi (driver == passenger)',
    () => assertFails(self.collection('trips').doc('self_trip').update(acceptPatch(SELF))));

  // ── H. queue — yo'lovchilar ko'radigan navbat hujjati ───────────────
  const q = (db) => db.collection('queue').doc(MARSH);
  await check('H15 kirmagan klient navbatni o\'chira / o\'rinni 0 qila olmaydi (queueGuestDispatchPatchOnly)',
    () => assertFails(q(unauth).update({ seatsLeft: 0, isActive: false, updatedAt: now() })));
  await check('H16 kirmagan klient navbatdagi driverPhone ni almashtira olmaydi',
    () => assertFails(q(unauth).update({ driverPhone: `+${ATTACKER}` })));
  await check('H17 begona navbatdagi driverPhone/ism/mashinani almashtira olmaydi',
    () => assertFails(q(attacker).update({ driverPhone: `+${ATTACKER}`, driverName: 'Soxta', plate: '00X000XX' })));

  // ── H. Qiymat cheklovi — kirgan begona ham faqat yo'lovchi oqimi shaklida
  await check('H18 begona haydovchini BAND (isBusy:true) qila olmaydi',
    () => assertFails(drv(attacker, LOCAL).update({ isBusy: true, updatedAt: now() })));
  await check('H19 begona todayTimeouts ni sakratib (+48) qo\'ya olmaydi',
    () => assertFails(drv(attacker, MARSH).update({ todayTimeouts: 50, updatedAt: now() })));
  await check('H20 begona jadvalga +1 dan ortiq o\'rin qo\'sha olmaydi (overbooking)',
    () => assertFails(attacker.collection('schedules').doc('sched_marsh').update({ seatsLeft: 7, updatedAt: now() })));
  await check('H21 begona jadval o\'rnini KAMAYTIRA olmaydi',
    () => assertFails(attacker.collection('schedules').doc('sched_marsh').update({ seatsLeft: 2, updatedAt: now() })));

  // ── R. Qonuniy oqim ─────────────────────────────────────────────────
  await seed();
  await check('R1 haydovchi O\'ZINI online/offline qiladi va joylashuv yozadi',
    () => assertSucceeds(drv(local, LOCAL).update({
      isOnline: false, isAvailable: false, lat: 41.85, lng: 60.4, updatedAt: now(),
    })));
  await check('R2 haydovchi o\'z hisoblagichlarini yozadi',
    () => assertSucceeds(drv(local, LOCAL).update({ todayTrips: 3, todayRejects: 1, updatedAt: now() })));
  await check('R3 marshrut haydovchi o\'z profilini (ism/mashina/raqam) yangilaydi',
    () => assertSucceeds(drv(marsh, MARSH).update({
      name: 'Rustam', car: 'Damas', plate: '95A123BB', seats: 7,
      stops: ['Gurlan', 'Urganch'], updatedAt: now(),
    })));
  await check('R4 verification_required haydovchi o\'z jadvalida seatsLeft yozadi',
    () => assertSucceeds(inter.collection('schedules').doc('sched_inter').update({ seatsLeft: 3, updatedAt: now() })));
  await check('R5 marshrut haydovchi o\'z driverProfiles hujjatini yangilaydi',
    () => assertSucceeds(prof(marsh, MARSH).update({ plate: '95A777BB', updatedAt: now() })));
  await check('R6 admin istalgan haydovchini offline qiladi',
    () => assertSucceeds(drv(adminDb, LOCAL).update({ isOnline: false, updatedAt: now() })));
  await check('R7 admin jadvalni o\'chiradi',
    () => assertSucceeds(adminDb.collection('schedules').doc('sched_inter').update({ isActive: false })));
  await check('R8 boshqa haydovchi yo\'lovchining safarini qabul qiladi',
    () => assertSucceeds(self.collection('trips').doc('pass_trip').update(acceptPatch(SELF))));
  await check('R9 haydovchi ham o\'z approval maydonini yoza olmaydi (o\'zgarmagan himoya)',
    () => assertFails(drv(local, LOCAL).update({ approvalStatus: 'approved' })));
  await check('R10 marshrut haydovchi o\'z navbat hujjatini yangilaydi (heartbeat)',
    () => assertSucceeds(q(marsh).set({ lat: 41.8, lng: 60.4, updatedAt: now(), lastSeenAt: now() }, { merge: true })));

  // ── R. Yo'lovchi → BEGONA haydovchi (marshrut dispatch, ilova 1.0.32/1.0.33)
  // Aynan klient yozuvlari shakli: `rides_repository.dart`.
  const passenger = ctxFor(PASSENGER).firestore();
  const pdb = (c) => passenger.collection(c);
  await seed();
  // P1 — offer timeout: `_applyDispatchPolicy('timeout')` :1443-1475.
  await check('R11 P1 yo\'lovchi timeout: drivers.todayTimeouts +1 (set merge, increment)',
    () => assertSucceeds(pdb('drivers').doc(MARSH).set(
      { todayTimeouts: increment(1), updatedAt: serverTimestamp() }, { merge: true })));
  await check('R12 P1 yo\'lovchi timeout: schedules.todayTimeouts +1',
    () => assertSucceeds(pdb('schedules').doc('sched_marsh').set(
      { todayTimeouts: increment(1), updatedAt: serverTimestamp() }, { merge: true })));
  await check('R13 P1 yo\'lovchi timeout: queue streak/hisoblagich + avto-pauza',
    () => assertSucceeds(pdb('queue').doc(MARSH).set({
      dispatchTimeoutStreak: 2, dispatchTimeoutCount: increment(1), todayTimeouts: increment(1),
      lastTimeoutAt: serverTimestamp(), updatedAt: serverTimestamp(),
      isActive: false, autoPausedReason: 'dispatch_timeout_streak', autoPausedAt: serverTimestamp(),
    }, { merge: true })));
  // P2/P3 — cancel-after-accept: `cancelMarshrutByPassenger` :594/:609/:616,
  // `_writeMarshrutSeatInTransaction` :1072/:1081, `_cancelMarshrutTripInTransaction` :921.
  await seed();
  await check('R14 P2 yo\'lovchi bekor: schedules.seatsLeft +1 (update)',
    () => assertSucceeds(pdb('schedules').doc('sched_marsh').update({ seatsLeft: 4, updatedAt: serverTimestamp() })));
  await check('R15 P2 yo\'lovchi bekor: queue seatsLeft/isActive (update)',
    () => assertSucceeds(pdb('queue').doc(MARSH).update({ seatsLeft: 4, isActive: true, updatedAt: serverTimestamp() })));
  await check('R16 P2 yo\'lovchi bekor: drivers.isBusy=false (set merge)',
    () => assertSucceeds(pdb('drivers').doc(MARSH).set({ isBusy: false, updatedAt: serverTimestamp() }, { merge: true })));
  await check('R17 P3 markCancelled: queue dispatchTimeoutStreak=0 (`_resetDriverDispatchStats`)',
    () => assertSucceeds(pdb('queue').doc(MARSH).set({ dispatchTimeoutStreak: 0, updatedAt: serverTimestamp() }, { merge: true })));
  await check('R18 P2 batch: trip bilan birga — schedules +1, queue, drivers isBusy',
    async () => {
      const b = passenger.batch();
      b.update(pdb('schedules').doc('sched_marsh'), { seatsLeft: 4, updatedAt: serverTimestamp() });
      b.update(pdb('queue').doc(MARSH), { seatsLeft: 4, isActive: true, updatedAt: serverTimestamp() });
      b.set(pdb('drivers').doc(MARSH), { isBusy: false, updatedAt: serverTimestamp() }, { merge: true });
      await assertSucceeds(b.commit());
    });
  await seed();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    // Jadval to'la (seatsLeft == seats) — klient clamp qiladi: o'zgarish yo'q.
    await ctx.firestore().collection('schedules').doc('sched_marsh').update({ seatsLeft: 7 });
  });
  await check('R19 P2 o\'rin to\'la bo\'lsa clamp — seatsLeft o\'zgarmaydi, faqat updatedAt',
    () => assertSucceeds(pdb('schedules').doc('sched_marsh').update({ seatsLeft: 7, updatedAt: serverTimestamp() })));

  await testEnv.cleanup();
  const failed = results.filter((r) => !r.p);
  console.log(`\n${results.length - failed.length}/${results.length} driver work patch rules checks passed.`);
  if (failed.length) { console.log('FAILED:', failed.map((f) => f.n).join(', ')); process.exitCode = 1; }
}
main().catch((e) => { console.error('FATAL', e); process.exitCode = 1; });
