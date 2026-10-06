/**
 * `intercity_booking_locks` Firestore rules.
 *
 * Muammo: `read: if true` VA `create, update: if true`. Ya'ni tizimga
 * kirmagan istalgan odam:
 *   - 15 ta (2026-10-06 holati) qulf yozuvini o'qiy olardi;
 *   - yangi qulf yaratib, haydovchining o'rindiqlarini band qila olardi;
 *   - mavjud qulfni o'zgartirib, boshqa yo'lovchining bandligini buzardi.
 *
 * Hujjat ID: `{driverId}_{userKey}`, yozuvchi — Cloud Functions
 * (functions/index.js:9920, :10120), Admin SDK orqali, ya'ni qoidalardan
 * o'tmaydi.
 *
 * Repo bo'yicha tekshirildi: Flutter ilovasi bu kolleksiyaga UMUMAN
 * tegmaydi — `lib/` da birorta ham havola yo'q. Shuning uchun o'qish
 * adminga yopiladi, yozish esa butunlay (CF baribir qoidalardan o'tmaydi).
 *
 * `delete` qoidasiga TEGILMAYDI: u allaqachon auth va egalik bilan
 * himoyalangan, va uni o'zgartirish uchun asos yo'q (31-qoida —
 * minimal diff).
 *
 * Ishlatish: repo ildizidan
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/booking_locks_rules.test.js"
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
const USER_KEY = '998904445566';
const LOCK_ID = `${DRIVER}_${USER_KEY}`;

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-booking-locks',
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
    await db.collection('intercity_booking_locks').doc(LOCK_ID).set({
      driverId: DRIVER, userKey: USER_KEY, bookingId: 'b1',
      createdAt: new Date(),
    });
  });

  function ctxFor(phone) {
    return testEnv.authenticatedContext(`uid_${phone}`, {
      phone_number: '+' + phone,
    });
  }

  const unauth = testEnv.unauthenticatedContext().firestore();
  const stranger = ctxFor('998903334455').firestore();
  const adminDb = ctxFor(ADMIN_PHONE).firestore();
  const col = (db) => db.collection('intercity_booking_locks');

  // ── Teshik: o'qish ──────────────────────────────────────────────────
  await check(
      'autentifikatsiyasiz qulfni o\'qiy olmaydi',
      () => assertFails(col(unauth).doc(LOCK_ID).get()));

  await check(
      'begona foydalanuvchi qulflar ro\'yxatini ola olmaydi',
      () => assertFails(col(stranger).limit(50).get()));

  // ── Teshik: yozish ──────────────────────────────────────────────────
  await check(
      'autentifikatsiyasiz YANGI qulf yarata olmaydi (o\'rindiq band qilish)',
      () => assertFails(col(unauth).doc('998900000000_998911111111').set({
        driverId: '998900000000', userKey: '998911111111',
      })));

  await check(
      'begona foydalanuvchi mavjud qulfni o\'zgartira olmaydi',
      () => assertFails(col(stranger).doc(LOCK_ID).update({bookingId: 'buzildi'})));

  await check(
      'autentifikatsiyasiz qulfni o\'zgartira olmaydi',
      () => assertFails(col(unauth).doc(LOCK_ID).update({bookingId: 'buzildi'})));

  // ── Admin ───────────────────────────────────────────────────────────
  await check(
      'admin qulfni o\'qiydi',
      () => assertSucceeds(col(adminDb).doc(LOCK_ID).get()));

  await check(
      'admin ro\'yxatni oladi',
      () => assertSucceeds(col(adminDb).limit(50).get()));

  await check(
      'admin ham yoza olmaydi (faqat CF)',
      () => assertFails(col(adminDb).doc(LOCK_ID).update({bookingId: 'x'})));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} intercity_booking_locks rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
