/**
 * `payout_requests` Firestore rules — S3.
 *
 * Muammo: qoida `allow read: if true` edi, ya'ni HAR KIM — hatto tizimga
 * kirmagan odam ham — barcha pul yechish so'rovlarini o'qiy olardi.
 * Hujjatda `userPhone` va `amount` bor, ya'ni bu shaxsiy ma'lumot va
 * moliyaviy ma'lumot oqimi edi.
 *
 * Yozish allaqachon yopiq (`create/update/delete: if false`) — faqat
 * Cloud Functions admin SDK orqali yoziladi. Bu test shuni ham qulflaydi.
 *
 * Kim o'qishi kerak (repo bo'yicha tekshirilgan):
 *   - admin panel: payout_management_screen.dart, admin_shell.dart:1000
 *   - analitika:   analytics_repository.dart:107, 1167
 *   - so'rov egasi o'zinikini (hozir ekran yo'q, lekin semantik to'g'ri)
 *
 * To'liq izolyatsiyalangan Firestore Emulator ustida ishlaydi, real
 * ma'lumotga tegmaydi.
 *
 * Ishlatish: npm --prefix functions run test:payout-rules
 *   (emulator alohida turgan bo'lsa), yoki repo ildizidan:
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/payout_requests_rules.test.js"
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
const FINANCE_PHONE = '998902223344';
const OWNER_PHONE = '998903334455';
const STRANGER_PHONE = '998904445566';
const REQ_ID = 'req1';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-payout-requests',
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
      await db.collection('users').doc(FINANCE_PHONE).set({role: 'finance'});
      await db.collection('users').doc(OWNER_PHONE).set({role: 'user'});
      await db.collection('users').doc(STRANGER_PHONE).set({role: 'user'});
      await db.collection('payout_requests').doc(REQ_ID).set({
        userPhone: OWNER_PHONE,
        amount: 500000,
        status: 'pending',
        createdAt: new Date(),
      });
    });
  }

  /** `isOwner()` token.phone_number'dan o'qiydi — '+' bilan. */
  function ctxFor(phone) {
    return testEnv.authenticatedContext(`uid_${phone}`, {
      phone_number: '+' + phone,
    });
  }

  await testEnv.clearFirestore();
  await seed();

  const unauth = testEnv.unauthenticatedContext().firestore();
  const stranger = ctxFor(STRANGER_PHONE).firestore();
  const owner = ctxFor(OWNER_PHONE).firestore();
  const adminDb = ctxFor(ADMIN_PHONE).firestore();
  const finance = ctxFor(FINANCE_PHONE).firestore();

  const doc = (db) => db.collection('payout_requests').doc(REQ_ID);
  const col = (db) => db.collection('payout_requests');

  // ── Teshik: begona ko'z ─────────────────────────────────────────────
  await check(
      'autentifikatsiyasiz bitta so\'rovni o\'qiy olmaydi',
      () => assertFails(doc(unauth).get()));

  await check(
      'begona foydalanuvchi birovning so\'rovini o\'qiy olmaydi',
      () => assertFails(doc(stranger).get()));

  await check(
      'begona foydalanuvchi ro\'yxatni so\'rov bilan ham o\'qiy olmaydi',
      () => assertFails(col(stranger).where('status', '==', 'pending').get()));

  await check(
      'autentifikatsiyasiz ro\'yxatni o\'qiy olmaydi',
      () => assertFails(col(unauth).where('status', '==', 'pending').get()));

  // ── Ishlashda davom etishi kerak ────────────────────────────────────
  await check(
      'admin bitta so\'rovni o\'qiydi',
      () => assertSucceeds(doc(adminDb).get()));

  await check(
      'admin ro\'yxatni so\'rov bilan o\'qiydi (admin_shell, analytics)',
      () => assertSucceeds(col(adminDb).where('status', '==', 'pending').get()));

  await check(
      'finance roli o\'qiydi (isFinanceReader)',
      () => assertSucceeds(doc(finance).get()));

  await check(
      'so\'rov egasi o\'zinikini o\'qiydi',
      () => assertSucceeds(doc(owner).get()));

  // ── Regressiya: yozish hamon butunlay yopiq ─────────────────────────
  await check(
      'egasi yangi so\'rov yarata olmaydi (faqat CF)',
      () => assertFails(col(owner).doc('req2').set({
        userPhone: OWNER_PHONE, amount: 1, status: 'pending',
      })));

  await check(
      'autentifikatsiyasiz yarata olmaydi',
      () => assertFails(col(unauth).doc('req3').set({
        userPhone: OWNER_PHONE, amount: 1, status: 'pending',
      })));

  await check(
      'admin ham yangilay olmaydi (faqat CF)',
      () => assertFails(doc(adminDb).update({status: 'confirmed'})));

  await check(
      'admin ham o\'chira olmaydi',
      () => assertFails(doc(adminDb).delete()));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} payout_requests rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
