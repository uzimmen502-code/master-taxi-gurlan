/**
 * `drivers` Firestore rules — FAQAT O'QISH tomoni.
 *
 * Muammo: `read: if true` — 16 haydovchi (2026-10-06 holati) hujjati har
 * kimga ochiq: telefon raqami va JONLI GPS. `couriers` bilan bir xil shakl,
 * lekin 5 barobar kattaroq.
 *
 * Nega butunlay yopilmaydi: yo'lovchi O'Z haydovchisining joylashuvini
 * ko'rishi kerak. Lekin repo bo'yicha tekshirilganda bu HAR DOIM bitta
 * hujjat, ID bo'yicha:
 *   local_taxi_active_trip_screen.dart:109  .doc(driverId).snapshots()
 *   marshrut_taxi_screen.dart:217           .doc(docId).snapshots()
 * RO'YXATNI esa faqat admin oladi:
 *   marshrut_admin_screen.dart:88  where isOnline==true, taxiType=='marshrut'
 *
 * Shuning uchun `get` / `list` ajratmasi: get — autentifikatsiya bilan,
 * list — faqat admin. Enumeratsiya yopiladi, yo'lovchi oqimi saqlanadi.
 *
 * DIQQAT: bu test `create`/`update` qoidalariga TEGMAYDI. Ularda uchta
 * maxsus yordamchi bor (`driverWorkPatchOnly`, `marshrutDriverRegisterPatch`,
 * `driverApprovalPatchOnly`) — ular alohida o'rganilishi kerak. `create` da
 * auth yo'qligi hamon ochiq masala.
 *
 * Ishlatish: repo ildizidan
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/drivers_read_rules.test.js"
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
    projectId: 'rules-test-drivers-read',
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
    await db.collection('drivers').doc(DRIVER).set({
      phone: '+998905556677', name: 'Shahzod', isOnline: true,
      taxiType: 'marshrut', lat: 41.55, lng: 60.63, updatedAt: new Date(),
    });
  });

  function ctxFor(phone) {
    return testEnv.authenticatedContext(`uid_${phone}`, {
      phone_number: '+' + phone,
    });
  }

  const unauth = testEnv.unauthenticatedContext().firestore();
  const passenger = ctxFor(PASSENGER).firestore();
  const adminDb = ctxFor(ADMIN_PHONE).firestore();
  const col = (db) => db.collection('drivers');

  // ── Teshik: butun haydovchilar ro'yxatini telefon va GPS bilan olish ─
  await check(
      'autentifikatsiyasiz RO\'YXATNI ola olmaydi',
      () => assertFails(col(unauth).limit(50).get()));

  await check(
      'yo\'lovchi butun ro\'yxatni ola olmaydi',
      () => assertFails(col(passenger).limit(50).get()));

  await check(
      'yo\'lovchi onlayn haydovchilarni so\'rov bilan ham ola olmaydi',
      () => assertFails(col(passenger).where('isOnline', '==', true).get()));

  await check(
      'autentifikatsiyasiz bitta haydovchini ham o\'qiy olmaydi',
      () => assertFails(col(unauth).doc(DRIVER).get()));

  // ── Yo'lovchi va admin oqimi saqlansin ──────────────────────────────
  await check(
      'yo\'lovchi O\'Z haydovchisini ID bo\'yicha o\'qiydi (active_trip:109)',
      () => assertSucceeds(col(passenger).doc(DRIVER).get()));

  await check(
      'haydovchi o\'z hujjatini o\'qiydi',
      () => assertSucceeds(col(ctxFor(DRIVER).firestore()).doc(DRIVER).get()));

  await check(
      'admin ro\'yxatni oladi (marshrut_admin_screen:88)',
      () => assertSucceeds(col(adminDb)
          .where('isOnline', '==', true)
          .where('taxiType', '==', 'marshrut').get()));

  await check(
      'admin bitta haydovchini o\'qiydi (driver_applications:1099)',
      () => assertSucceeds(col(adminDb).doc(DRIVER).get()));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} drivers read rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
