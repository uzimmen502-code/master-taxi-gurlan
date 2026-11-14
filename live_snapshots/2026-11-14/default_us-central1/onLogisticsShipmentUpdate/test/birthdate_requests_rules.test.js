/**
 * `birthdate_change_requests` Firestore rules.
 *
 * Qoida to'liq ochiq edi:
 *   create: if true;  read, update: if true;  delete: if isAdmin();
 *
 * Ya'ni istalgan odam (tizimga kirmagan ham):
 *   - barcha tug'ilgan sana so'rovlarini o'qiy olardi (shaxsiy ma'lumot);
 *   - BOSHQA foydalanuvchi nomidan so'rov yarata olardi;
 *   - so'rovni o'zi «approved» deb belgilay olardi va admin navbatini
 *     buzib yuborardi.
 *
 * Koddagi izoh buni vaqtinchalik deb tushuntirardi: «Admin web hozir PIN
 * session bilan ishlaydi; Phone Auth admin bo'lgach `isAdmin()`ga
 * qaytaramiz». Admin panel ALLAQACHON Phone Auth'da
 * (lib/features/admin_web/services/admin_auth_service.dart:114-122) —
 * ya'ni izoh eskirgan va shart bajarilgan.
 *
 * Haqiqiy oqim (lib/repositories/user_repository.dart):
 *   :289  foydalanuvchi o'zi uchun yaratadi — userId, status 'pending'
 *   :310  admin `where status == 'pending'` bilan kuzatadi
 *   :325  admin tasdiqlaydi — tranzaksiyada o'qiydi va update qiladi
 *   :348  admin rad etadi — set(merge)
 * Tasdiqlash/rad etish KLIENTDAN (admin web) bajariladi, CF emas.
 *
 * Ishlatish: repo ildizidan
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/birthdate_requests_rules.test.js"
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
const OWNER = '998905556677';
const STRANGER = '998904445566';
const REQ_ID = 'bd_req_1';

function req(userId, status) {
  return {
    userId,
    currentBirthDate: '1990-01-01',
    requestedBirthDate: '1991-02-02',
    status: status || 'pending',
    createdAt: new Date(),
    updatedAt: new Date(),
  };
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-birthdate',
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

  async function seed() {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('users').doc(ADMIN_PHONE).set({role: 'admin'});
      await db.collection('birthdate_change_requests').doc(REQ_ID).set(req(OWNER));
    });
  }

  function ctxFor(phone) {
    return testEnv.authenticatedContext(`uid_${phone}`, {
      phone_number: '+' + phone,
    });
  }

  const doc = (db, id) => db.collection('birthdate_change_requests').doc(id);
  const col = (db) => db.collection('birthdate_change_requests');

  await testEnv.clearFirestore();
  await seed();

  const unauth = testEnv.unauthenticatedContext().firestore();
  const stranger = ctxFor(STRANGER).firestore();
  const owner = ctxFor(OWNER).firestore();
  const adminDb = ctxFor(ADMIN_PHONE).firestore();

  // ── Teshik: begona ko'z va begona qo'l ──────────────────────────────
  await check(
      'autentifikatsiyasiz so\'rovni o\'qiy olmaydi',
      () => assertFails(doc(unauth, REQ_ID).get()));

  await check(
      'begona foydalanuvchi birovning so\'rovini o\'qiy olmaydi',
      () => assertFails(doc(stranger, REQ_ID).get()));

  await check(
      'autentifikatsiyasiz so\'rov yarata olmaydi',
      () => assertFails(col(unauth).doc('x1').set(req(OWNER))));

  await check(
      'begona odam BOSHQA foydalanuvchi nomidan so\'rov yarata olmaydi',
      () => assertFails(col(stranger).doc('x2').set(req(OWNER))));

  await check(
      'begona odam so\'rovni o\'zi tasdiqlay olmaydi',
      () => assertFails(doc(stranger, REQ_ID).update({status: 'approved'})));

  await check(
      'autentifikatsiyasiz so\'rovni o\'zgartira olmaydi',
      () => assertFails(doc(unauth, REQ_ID).update({status: 'approved'})));

  // ── Haqiqiy oqim ishlashda davom etsin ──────────────────────────────
  await check(
      'foydalanuvchi o\'zi uchun so\'rov yaratadi (user_repository:289)',
      () => assertSucceeds(col(owner).doc('own1').set(req(OWNER))));

  await check(
      'foydalanuvchi o\'z so\'rovini o\'qiydi',
      () => assertSucceeds(doc(owner, REQ_ID).get()));

  await check(
      'admin pending ro\'yxatni kuzatadi (user_repository:310)',
      () => assertSucceeds(col(adminDb)
          .where('status', '==', 'pending').limit(100).get()));

  await check(
      'admin tasdiqlaydi (user_repository:325)',
      () => assertSucceeds(doc(adminDb, REQ_ID).update({
        status: 'approved', reviewedAt: new Date(), updatedAt: new Date(),
      })));

  await check(
      'admin rad etadi — set(merge) (user_repository:348)',
      () => assertSucceeds(doc(adminDb, 'own1').set({
        status: 'rejected', reviewedAt: new Date(), updatedAt: new Date(),
      }, {merge: true})));

  await check(
      'admin o\'chiradi',
      () => assertSucceeds(doc(adminDb, 'own1').delete()));

  // ── Chegara holatlari ───────────────────────────────────────────────
  await check(
      'foydalanuvchi darhol approved holatda yarata olmaydi',
      () => assertFails(col(owner).doc('x3').set(req(OWNER, 'approved'))));

  await check(
      'foydalanuvchi o\'z so\'rovini o\'zi tasdiqlay olmaydi',
      () => assertFails(doc(owner, REQ_ID).update({status: 'approved'})));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} birthdate_change_requests rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
