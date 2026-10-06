/**
 * To'rtta qolgan ochiq o'qish — `queue`, `marshrut_dispatch_events`,
 * `users/{id}/driverProfiles`, `users/{id}/marshrut_state`.
 *
 * Har biri alohida tahlil qilindi, chunki oqimlari har xil:
 *
 * `queue` (6 hujjat) — YO'LOVCHI RO'YXAT SO'RAYDI:
 *   marshrut_search_controller.dart:366  where taxiType == 'marshrut'
 * Ya'ni egalikka bog'lab bo'lmaydi va `get`/`list` ajratmasi ham ish
 * bermaydi. Shuning uchun faqat `isAuth()`. ESLATMA: hujjatda
 * `driverPhone` bor va u yo'lovchiga ko'rinadi — buni qoida hal qilmaydi,
 * ma'lumot modeli o'zgarishi kerak (ommaviy proyeksiya).
 *
 * `marshrut_dispatch_events` (194) — klient faqat YARATADI
 * (rides_repository.dart:619). Yagona o'qish yo'li
 * `watchRecentMarshrutDispatchEvents()` (:175) — lekin uni HECH KIM
 * chaqirmaydi, o'lik kod. Shuning uchun o'qish adminga yopiladi.
 * `create` qoidasiga TEGILMAYDI.
 *
 * `users/{uid}/driverProfiles` — faqat EGASI o'qiydi: `getProfile(uid)`
 * doim `prefs['user_phone']` bilan chaqiriladi
 * (push_navigation.dart:186, :338). Egalikka bog'lanadi.
 *
 * `users/{uid}/marshrut_state` — HAYDOVCHI YO'LOVCHINING holatini
 * sinxronlaydi (firestore.rules:636 izohi, rides_repository.dart:1274).
 * Ya'ni o'qish ham kesishgan. Faqat `isAuth()`.
 *
 * Ishlatish: repo ildizidan
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/marshrut_misc_rules.test.js"
 */
'use strict';
const path = require('path');
const fs = require('fs');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const ADMIN_PHONE = '998901112233';
const DRIVER = '998905556677';
const PASSENGER = '998904445566';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-marshrut-misc',
    firestore: {
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
      host: HOST,
      port: Number(PORT),
    },
  });

  const results = [];
  function record(name, pass, detail) {
    results.push({name, pass, detail});
    console.log(`${pass ? 'PASS' : 'FAIL'} - ${name}${detail ? ' :: ' + detail : ''}`);
  }

  async function check(name, fn) {
    try {
      await fn();
      record(name, true);
    } catch (e) {
      record(name, false, e.message);
    }
  }

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('users').doc(ADMIN_PHONE).set({role: 'admin'});
    await db.collection('queue').doc(DRIVER).set({
      driverId: DRIVER, driverName: 'Shahzod', driverPhone: '+998905556677',
      car: 'Nexia', plate: '01A111AA', taxiType: 'marshrut',
      isActive: true, seats: 4, seatsLeft: 2, updatedAt: new Date(),
    });
    await db.collection('marshrut_dispatch_events').doc('ev1').set({
      tripId: 't1', type: 'passenger_cancel_after_accept',
      cancelledBy: 'passenger', createdAt: new Date(),
    });
    await db.collection('users').doc(DRIVER)
        .collection('driverProfiles').doc('marshrut')
        .set({carModel: 'Nexia', plate: '01A111AA', seats: 4});
    await db.collection('users').doc(PASSENGER)
        .collection('marshrut_state').doc('active')
        .set({tripId: 't1', sessionId: 's1', status: 'active'});
  });

  function ctxFor(phone) {
    return testEnv.authenticatedContext(`uid_${phone}`, {
      phone_number: '+' + phone,
    });
  }

  const unauth = testEnv.unauthenticatedContext().firestore();
  const passenger = ctxFor(PASSENGER).firestore();
  const driver = ctxFor(DRIVER).firestore();
  const adminDb = ctxFor(ADMIN_PHONE).firestore();

  // ── queue ───────────────────────────────────────────────────────────
  await check(
      'queue: autentifikatsiyasiz ro\'yxatni ola olmaydi',
      () => assertFails(unauth.collection('queue')
          .where('taxiType', '==', 'marshrut').get()));

  await check(
      'queue: autentifikatsiyasiz bitta hujjatni ham o\'qiy olmaydi',
      () => assertFails(unauth.collection('queue').doc(DRIVER).get()));

  await check(
      'queue: yo\'lovchi ro\'yxatni oladi (marshrut_search_controller:366)',
      () => assertSucceeds(passenger.collection('queue')
          .where('taxiType', '==', 'marshrut').get()));

  await check(
      'queue: yo\'lovchi haydovchi hujjatini o\'qiydi (rides_repository:580)',
      () => assertSucceeds(passenger.collection('queue').doc(DRIVER).get()));

  // ── marshrut_dispatch_events ────────────────────────────────────────
  await check(
      'dispatch_events: autentifikatsiyasiz o\'qiy olmaydi',
      () => assertFails(unauth.collection('marshrut_dispatch_events').doc('ev1').get()));

  await check(
      'dispatch_events: oddiy foydalanuvchi o\'qiy olmaydi',
      () => assertFails(passenger.collection('marshrut_dispatch_events')
          .orderBy('createdAt', 'desc').limit(50).get()));

  await check(
      'dispatch_events: admin o\'qiydi',
      () => assertSucceeds(adminDb.collection('marshrut_dispatch_events')
          .orderBy('createdAt', 'desc').limit(50).get()));

  // ── driverProfiles ──────────────────────────────────────────────────
  const prof = (db, uid) => db.collection('users').doc(uid)
      .collection('driverProfiles').doc('marshrut');

  await check(
      'driverProfiles: autentifikatsiyasiz o\'qiy olmaydi',
      () => assertFails(prof(unauth, DRIVER).get()));

  await check(
      'driverProfiles: begona foydalanuvchi o\'qiy olmaydi',
      () => assertFails(prof(passenger, DRIVER).get()));

  await check(
      'driverProfiles: egasi o\'qiydi (push_navigation:186)',
      () => assertSucceeds(prof(driver, DRIVER).get()));

  await check(
      'driverProfiles: admin o\'qiydi',
      () => assertSucceeds(prof(adminDb, DRIVER).get()));

  // ── marshrut_state ──────────────────────────────────────────────────
  const state = (db, uid) => db.collection('users').doc(uid)
      .collection('marshrut_state').doc('active');

  await check(
      'marshrut_state: autentifikatsiyasiz o\'qiy olmaydi',
      () => assertFails(state(unauth, PASSENGER).get()));

  await check(
      'marshrut_state: egasi o\'qiydi',
      () => assertSucceeds(state(passenger, PASSENGER).get()));

  await check(
      'marshrut_state: haydovchi yo\'lovchi holatini o\'qiydi (sync oqimi)',
      () => assertSucceeds(state(driver, PASSENGER).get()));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} marshrut misc rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
