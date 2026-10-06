/**
 * `notifications` Firestore rules.
 *
 * Ikkita muammo, ikkinchisi jiddiyroq:
 *   1. `read: if true` — 953 hujjat (2026-10-06 holati) har kimga ochiq:
 *      `targetPhone`, `title`, `body`.
 *   2. `create` da AUTH YO'Q edi — ya'ni tizimga kirmagan istalgan odam
 *      istalgan raqamga ixtiyoriy matnli yozuv yarata olardi. Bu shunchaki
 *      yozuv emas: `onNotificationCreate` (functions/index.js) uni ko'rib
 *      haqiqiy push yuboradi. Ya'ni tashqaridan push-spam / fishing.
 *
 * Nega `create` butunlay yopilmaydi: klient BOSHQA foydalanuvchiga xabar
 * yozishi — mahsulot oqimi (`NotificationDelivery.write()`,
 * lib/services/notification_delivery.dart:181). Haydovchi yo'lovchiga,
 * yo'lovchi haydovchiga xabar beradi. Shuning uchun minimal qattiqlashtirish:
 * `isAuth()` — tashqaridan kirish yopiladi, ilova oqimi saqlanadi.
 * Tezlik chegarasi (rate limit) qoidada ifodalanmaydi — u CF vazifasi.
 *
 * O'qish/yangilash esa EGASIGA bog'lanadi. Klient aynan shunday so'raydi:
 *   fcm_service.dart:92           where targetPhone == alias, sent == false
 *   driver_force_leave_service.dart:82  + type == 'driver_request_approved'
 * `phoneAliases()` 9 va 12 xonali ikkala shaklni ham beradi, `isOwner()`
 * ikkalasini ham qabul qiladi — quyida test bilan qulflangan.
 *
 * Ishlatish: repo ildizidan
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/notifications_rules.test.js"
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
const TARGET = '998905556677';
const TARGET9 = '905556677';
const STRANGER = '998904445566';

const N_FOR_TARGET = 'n_target';
const N_FOR_TARGET9 = 'n_target9';

function notif(targetPhone) {
  return {
    targetPhone,
    title: 'Buyurtma',
    body: 'Kuryer yo‘lda',
    sent: false,
    type: 'order_update',
    createdAt: new Date(),
  };
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-notifications',
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
      await db.collection('notifications').doc(N_FOR_TARGET).set(notif(TARGET));
      // `phoneAliases()` 9 xonali shaklni ham beradi — eski yozuvlar shunday.
      await db.collection('notifications').doc(N_FOR_TARGET9).set(notif(TARGET9));
    });
  }

  function ctxFor(phone) {
    return testEnv.authenticatedContext(`uid_${phone}`, {
      phone_number: '+' + phone,
    });
  }

  const doc = (db, id) => db.collection('notifications').doc(id);
  const col = (db) => db.collection('notifications');

  await testEnv.clearFirestore();
  await seed();

  const unauth = testEnv.unauthenticatedContext().firestore();
  const stranger = ctxFor(STRANGER).firestore();
  const target = ctxFor(TARGET).firestore();
  const adminDb = ctxFor(ADMIN_PHONE).firestore();

  // ── Teshik 1: begona ko'z ───────────────────────────────────────────
  await check(
      'autentifikatsiyasiz xabarni o\'qiy olmaydi',
      () => assertFails(doc(unauth, N_FOR_TARGET).get()));

  await check(
      'begona foydalanuvchi birovning xabarini o\'qiy olmaydi',
      () => assertFails(doc(stranger, N_FOR_TARGET).get()));

  await check(
      'begona foydalanuvchi birovning xabarlarini so\'rov bilan ola olmaydi',
      () => assertFails(col(stranger)
          .where('targetPhone', '==', TARGET)
          .where('sent', '==', false).get()));

  // ── Teshik 2: tashqaridan push-spam ─────────────────────────────────
  await check(
      'autentifikatsiyasiz xabar YARATA OLMAYDI (push-spam yo\'li)',
      () => assertFails(col(unauth).doc('n_spam').set(notif(TARGET))));

  await check(
      'autentifikatsiyasiz birovning xabarini sent qila olmaydi',
      () => assertFails(doc(unauth, N_FOR_TARGET).update({sent: true})));

  await check(
      'begona foydalanuvchi birovning xabarini sent qila olmaydi',
      () => assertFails(doc(stranger, N_FOR_TARGET).update({sent: true})));

  // ── Ilova oqimi ishlashda davom etsin ───────────────────────────────
  await check(
      'qabul qiluvchi o\'z xabarini o\'qiydi',
      () => assertSucceeds(doc(target, N_FOR_TARGET).get()));

  await check(
      'qabul qiluvchi o\'z xabarlarini so\'rov bilan oladi (fcm_service)',
      () => assertSucceeds(col(target)
          .where('targetPhone', '==', TARGET)
          .where('sent', '==', false).get()));

  await check(
      '9 xonali alias bo\'yicha ham o\'qiydi (phoneAliases)',
      () => assertSucceeds(col(target)
          .where('targetPhone', '==', TARGET9)
          .where('sent', '==', false).get()));

  await check(
      'qabul qiluvchi o\'z xabarini sent qiladi',
      () => assertSucceeds(doc(target, N_FOR_TARGET).update({sent: true})));

  await check(
      'tizimga kirgan foydalanuvchi BOSHQAGA xabar yozadi (mahsulot oqimi)',
      () => assertSucceeds(col(stranger).doc('n_ok').set(notif(TARGET))));

  await check(
      'admin xabarni o\'qiydi',
      () => assertSucceeds(doc(adminDb, N_FOR_TARGET9).get()));

  // ── Chegara holatlari ───────────────────────────────────────────────
  await check(
      'sent=true bilan yaratib bo\'lmaydi',
      () => assertFails(col(stranger).doc('n_bad1')
          .set({...notif(TARGET), sent: true})));

  await check(
      'majburiy maydonsiz yaratib bo\'lmaydi',
      () => assertFails(col(stranger).doc('n_bad2')
          .set({targetPhone: TARGET, sent: false})));

  await check(
      'qabul qiluvchi xabar matnini o\'zgartira olmaydi',
      () => assertFails(doc(target, N_FOR_TARGET9).update({title: 'boshqa'})));

  await check(
      'hech kim o\'chira olmaydi, admin ham',
      () => assertFails(doc(adminDb, N_FOR_TARGET9).delete()));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} notifications rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
