/**
 * `couriers` Firestore rules — S2.
 *
 * Muammo (uchta, bittasi ichida):
 *   1. `read: if true`  — har kim, hatto tizimga kirmagan odam ham HAR BIR
 *      kuryerning telefoni va JONLI koordinatasini o'qiy olardi.
 *   2. `create` — faqat maydon borligini tekshirardi, auth YO'Q.
 *   3. `update` — maydon ro'yxati to'g'ri edi, lekin EGALIK tekshiruvi yo'q:
 *      istalgan odam birovning `fcmToken`ini almashtirib, push'ini
 *      o'g'irlashi mumkin edi.
 *
 * Hujjat ID — telefon raqami (admin `couriers/{id}` ni `phone: '+$id'`
 * bilan yaratadi), 9 va 12 xonali ikki shaklda uchraydi. `isOwner()`
 * `phoneDocIdsMatch()` orqali IKKALASINI ham to'g'ri taqqoslaydi, shuning
 * uchun ID migratsiyasini kutish shart emas — bu quyida test bilan
 * qulflangan.
 *
 * O'rnatilgan ilovani buzmaslik: `couriers_repository.dart` AYNAN shu
 * maydonlarni yozadi (`CourierStatus.toUpsertMap()` + `updatedAt`), va
 * `courier_controller.dart:57` hujjat ID sifatida `phoneDigits(phone)`
 * ishlatadi — ya'ni xom raqamlar, kanonik shaklga keltirilmagan. Shu ikki
 * yo'l ham regressiya testi bilan qulflangan.
 *
 * To'liq izolyatsiyalangan Firestore Emulator ustida ishlaydi.
 *
 * Ishlatish: repo ildizidan
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/couriers_rules.test.js"
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
/** Kuryer — hujjati 12 xonali ID bilan. */
const COURIER12 = '998905556677';
/** Kuryer — hujjati 9 xonali ID bilan (eski yozuvlar shunday). */
const COURIER9_DOC = '906667788';
const COURIER9_FULL = '998906667788';
const STRANGER_PHONE = '998904445566';

/** `couriers_repository.dart` `upsertStatus()` aynan shu shaklni yozadi. */
const HEARTBEAT = {
  name: 'Bobur',
  phone: '+998905556677',
  isOnline: true,
  lat: 41.55,
  lng: 60.63,
  fcmToken: 'tok_courier_own',
};

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-couriers',
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
      await db.collection('users').doc(STRANGER_PHONE).set({role: 'user'});
      await db.collection('couriers').doc(COURIER12).set({
        ...HEARTBEAT, updatedAt: new Date(),
      });
      await db.collection('couriers').doc(COURIER9_DOC).set({
        name: 'Shahzod', phone: '+998906667788', isOnline: false,
        fcmToken: 'tok_courier9', updatedAt: new Date(),
      });
    });
  }

  function ctxFor(phone) {
    return testEnv.authenticatedContext(`uid_${phone}`, {
      phone_number: '+' + phone,
    });
  }

  await testEnv.clearFirestore();
  await seed();

  const unauth = testEnv.unauthenticatedContext().firestore();
  const stranger = ctxFor(STRANGER_PHONE).firestore();
  const own12 = ctxFor(COURIER12).firestore();
  const own9 = ctxFor(COURIER9_FULL).firestore();
  const adminDb = ctxFor(ADMIN_PHONE).firestore();

  const doc = (db, id) => db.collection('couriers').doc(id);
  const col = (db) => db.collection('couriers');

  // ── Teshik 1: jonli joylashuv va telefon ochiq edi ──────────────────
  await check(
      'autentifikatsiyasiz kuryer hujjatini o\'qiy olmaydi',
      () => assertFails(doc(unauth, COURIER12).get()));

  await check(
      'autentifikatsiyasiz butun ro\'yxatni o\'qiy olmaydi',
      () => assertFails(col(unauth).where('isOnline', '==', true).get()));

  await check(
      'begona foydalanuvchi birovning joylashuvini o\'qiy olmaydi',
      () => assertFails(doc(stranger, COURIER12).get()));

  // ── Teshik 2: auth'siz yaratish ─────────────────────────────────────
  await check(
      'autentifikatsiyasiz yangi kuryer yarata olmaydi',
      () => assertFails(doc(unauth, '998909998877').set({
        isOnline: true, name: 'Soxta', phone: '+998909998877',
      })));

  await check(
      'begona odam BOSHQA raqamga kuryer hujjati yarata olmaydi',
      () => assertFails(doc(stranger, '998909998878').set({
        isOnline: true, name: 'Soxta', phone: '+998909998878',
      })));

  // ── Teshik 3: birovning push tokenini o'g'irlash ────────────────────
  await check(
      'autentifikatsiyasiz birovning fcmToken\'ini almashtira olmaydi',
      () => assertFails(doc(unauth, COURIER12).update({
        fcmToken: 'tok_o_g_ri',
      })));

  await check(
      'begona foydalanuvchi birovning fcmToken\'ini almashtira olmaydi',
      () => assertFails(doc(stranger, COURIER12).update({
        fcmToken: 'tok_o_g_ri',
      })));

  await check(
      'begona foydalanuvchi birovni offline qila olmaydi',
      () => assertFails(doc(stranger, COURIER12).update({isOnline: false})));

  // ── Regressiya: o'rnatilgan ilova ishlashda davom etsin ─────────────
  await check(
      'kuryer o\'z GPS heartbeat\'ini yozadi (upsertStatus, 12 xonali ID)',
      () => assertSucceeds(doc(own12, COURIER12).set({
        ...HEARTBEAT, lat: 41.56, updatedAt: new Date(),
      }, {merge: true})));

  await check(
      'kuryer o\'zini offline qiladi (goOffline)',
      () => assertSucceeds(doc(own12, COURIER12).update({
        isOnline: false, updatedAt: new Date(),
      })));

  await check(
      '9 xonali ID\'li eski hujjatni egasi yangilaydi (migratsiya kutilmaydi)',
      () => assertSucceeds(doc(own9, COURIER9_DOC).update({
        isOnline: true, lat: 41.1, lng: 60.1, updatedAt: new Date(),
      })));

  await check(
      'admin yangi kuryer yaratadi (courier_management_screen)',
      () => assertSucceeds(doc(adminDb, '998901234567').set({
        phone: '+998901234567', name: 'Yangi', isOnline: false,
      })));

  await check(
      'admin jonli ro\'yxatni o\'qiydi (courier_admin_screen)',
      () => assertSucceeds(col(adminDb).where('isOnline', '==', true).get()));

  await check(
      'admin kuryerni o\'chiradi',
      () => assertSucceeds(doc(adminDb, COURIER9_DOC).delete()));

  // ── Maydon cheklovi hamon kuchda ────────────────────────────────────
  await check(
      'kuryer ruxsat etilmagan maydon qo\'sha olmaydi (rating)',
      () => assertFails(doc(own12, COURIER12).update({rating: 5})));

  await check(
      'kuryer o\'zini o\'chira olmaydi (faqat admin)',
      () => assertFails(doc(own12, COURIER12).delete()));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} couriers rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
