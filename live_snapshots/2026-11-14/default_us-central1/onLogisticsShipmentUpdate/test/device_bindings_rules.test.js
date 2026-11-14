/**
 * `device_bindings` va `device_bindings_legacy` Firestore rules.
 *
 * Muammo: ikkalasida ham `read: if true` — 557 hujjat (2026-10-06 holati)
 * har kimga ochiq. Hujjat qurilma izi ↔ telefon raqami bog'lanishi, ya'ni
 * butun ro'yxatni yuklab olish mumkin edi.
 *
 * Nega `get` butunlay yopilmaydi: ilova qurilma bog'langanmi yo'qmi deb
 * O'Z hash'i bo'yicha BITTA hujjatni o'qiydi, va buni AUTH'DAN OLDIN
 * qiladi — `isDeviceBound()` / `getBinding()`
 * (lib/repositories/device_binding_repository.dart:90, :105). Telefon
 * tasdiqlashdan oldingi qadam. `isAuth()` talab qilinsa, onboarding
 * buziladi.
 *
 * Yechim — Firestore'ning `get` va `list` ajratmasi:
 *   get  — ochiq (hash'ni biladigan qurilma o'zinikini o'qiydi)
 *   list — faqat admin (enumeratsiya yopiladi)
 *
 * Qoladigan xavf: kimdir biror qurilmaning hash'ini bilsa, o'sha bitta
 * bog'lanishni o'qiy oladi. Hash — qurilma xossalaridan olingan uzun
 * qiymat, taxmin qilib topilmaydi, va qurilmaning o'zi uni kalit sifatida
 * ishlatadi. Ro'yxatni yuklab olishdan ko'ra tubdan kichik xavf.
 *
 * `device_bindings_legacy` ni esa klient UMUMAN o'qimaydi — unga faqat bir
 * martalik migratsiya CF tegadi (functions/index.js:6475, :6492). Shuning
 * uchun u butunlay adminga yopiladi.
 *
 * Ishlatish: repo ildizidan
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/device_bindings_rules.test.js"
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
const STRANGER = '998904445566';
const HASH = 'a3f1c9e2b7d04856a3f1c9e2b7d04856a3f1c9e2b7d04856a3f1c9e2b7d04856';
const LEGACY_ID = 'legacy_doc_1';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-device-bindings',
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
    await db.collection('device_bindings').doc(HASH).set({
      phone: '998905556677', approved: true, updatedAt: new Date(),
    });
    await db.collection('device_bindings_legacy').doc(LEGACY_ID).set({
      phone: '998905556677', updatedAt: new Date(),
    });
  });

  function ctxFor(phone) {
    return testEnv.authenticatedContext(`uid_${phone}`, {
      phone_number: '+' + phone,
    });
  }

  const unauth = testEnv.unauthenticatedContext().firestore();
  const stranger = ctxFor(STRANGER).firestore();
  const adminDb = ctxFor(ADMIN_PHONE).firestore();

  const bindings = (db) => db.collection('device_bindings');
  const legacy = (db) => db.collection('device_bindings_legacy');

  // ── Ilova oqimi: auth'dan OLDIN o'z hash'ini o'qish ─────────────────
  await check(
      'autentifikatsiyasiz O\'Z hash\'i bo\'yicha bitta hujjatni o\'qiydi (isDeviceBound)',
      () => assertSucceeds(bindings(unauth).doc(HASH).get()));

  // ── Teshik: butun ro'yxatni yuklab olish ────────────────────────────
  await check(
      'autentifikatsiyasiz RO\'YXATNI ola olmaydi',
      () => assertFails(bindings(unauth).limit(100).get()));

  await check(
      'begona foydalanuvchi ro\'yxatni ola olmaydi',
      () => assertFails(bindings(stranger).limit(100).get()));

  await check(
      'admin ro\'yxatni oladi (users_devices_screen:405)',
      () => assertSucceeds(bindings(adminDb).limit(100).get()));

  // ── Yozish hamon butunlay yopiq ─────────────────────────────────────
  await check(
      'autentifikatsiyasiz bog\'lanish yarata olmaydi',
      () => assertFails(bindings(unauth).doc('new_hash').set({phone: '998900000000'})));

  await check(
      'admin ham bog\'lanishni o\'zgartira olmaydi (faqat CF)',
      () => assertFails(bindings(adminDb).doc(HASH).update({phone: '998900000000'})));

  await check(
      'admin ham o\'chira olmaydi',
      () => assertFails(bindings(adminDb).doc(HASH).delete()));

  // ── legacy — klient umuman o'qimaydi ────────────────────────────────
  await check(
      'legacy: autentifikatsiyasiz bitta hujjatni o\'qiy olmaydi',
      () => assertFails(legacy(unauth).doc(LEGACY_ID).get()));

  await check(
      'legacy: begona foydalanuvchi o\'qiy olmaydi',
      () => assertFails(legacy(stranger).doc(LEGACY_ID).get()));

  await check(
      'legacy: admin o\'qiydi',
      () => assertSucceeds(legacy(adminDb).doc(LEGACY_ID).get()));

  await check(
      'legacy: yozish yopiq',
      () => assertFails(legacy(adminDb).doc(LEGACY_ID).update({phone: 'x'})));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} device_bindings rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
