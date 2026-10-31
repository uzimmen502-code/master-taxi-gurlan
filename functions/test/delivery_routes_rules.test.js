/**
 * `delivery_routes` Firestore rules — S1.
 *
 * Muammo: `update` qoidasi shunday edi —
 *
 *   allow update: if isAdmin()
 *       || request.resource.data.keys().hasAny(
 *            ['status','currentIndex','startedAt','completedAt','courierId']);
 *
 * `request.resource.data` — yozishdan KEYINGI to'liq hujjat. Reysda bu
 * maydonlar doim mavjud, ya'ni `hasAny(...)` HAR DOIM `true`. Amalda:
 * tizimga kirmagan odam ham istalgan reysni istalgancha o'zgartira olardi
 * — tugatilgan deb belgilash, boshqa kuryerga o'tkazish, indeksni surish.
 *
 * To'g'ri shakl `hasAny` emas, `diff(resource.data).affectedKeys().hasOnly(...)`:
 * ya'ni QAYSI MAYDON O'ZGARDI, qaysi maydon mavjud emas.
 *
 * Kuryer oqimi (`delivery_routes_repository.dart`):
 *   startRoute     ready -> active, courierId, startedAt   (tranzaksiya)
 *   advanceIndex   currentIndex
 *   completeRoute  status, completedAt
 *
 * Diqqat: kuryer EGASIZ reysni egallamaydi — `courier_controller.dart:168`
 * avval `getActiveForCourier(uid)` chaqiradi, u esa `where courierId == uid`
 * bilan qidiradi. Ya'ni reys unga ALLAQACHON tayinlangan, u faqat
 * `ready -> active` qiladi. `getNextReady()` (egasiz reys) hech qayerdan
 * chaqirilmaydi — o'lik kod.
 *
 * To'liq izolyatsiyalangan Firestore Emulator ustida ishlaydi.
 *
 * Ishlatish: repo ildizidan
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/delivery_routes_rules.test.js"
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
const COURIER = '998905556677';
const OTHER_COURIER = '998907778899';
const READY_ROUTE = 'route_ready';
const ACTIVE_ROUTE = 'route_active';
const ORPHAN_ROUTE = 'route_orphan';
const PENDING_ROUTE = 'route_pending';

function routeDoc(courierId, status) {
  return {
    courierId,
    status,
    orders: ['o1', 'o2'],
    currentIndex: 0,
    directionLabel: 'Gurlan MFY',
    createdAt: new Date(),
  };
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-delivery-routes',
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
      await db.collection('delivery_routes').doc(READY_ROUTE)
          .set(routeDoc(COURIER, 'ready'));
      await db.collection('delivery_routes').doc(ACTIVE_ROUTE)
          .set(routeDoc(COURIER, 'active'));
      // Egasiz reys — `onDeliveryRouteCreate` courierId'siz ham yaratadi.
      await db.collection('delivery_routes').doc(PENDING_ROUTE)
          .set(routeDoc(COURIER, 'active'));
      await db.collection('delivery_routes').doc(ORPHAN_ROUTE)
          .set(routeDoc('', 'ready'));
    });
  }

  function ctxFor(phone) {
    return testEnv.authenticatedContext(`uid_${phone}`, {
      phone_number: '+' + phone,
    });
  }

  const doc = (db, id) => db.collection('delivery_routes').doc(id);
  const col = (db) => db.collection('delivery_routes');

  await testEnv.clearFirestore();
  await seed();

  const unauth = testEnv.unauthenticatedContext().firestore();
  const other = ctxFor(OTHER_COURIER).firestore();
  const mine = ctxFor(COURIER).firestore();
  const adminDb = ctxFor(ADMIN_PHONE).firestore();

  // ── Teshik: har kim har qanday reysni o'zgartira olardi ─────────────
  await check(
      'autentifikatsiyasiz reysni tugatilgan deb belgilay olmaydi',
      () => assertFails(doc(unauth, ACTIVE_ROUTE).update({
        status: 'completed', completedAt: new Date(),
      })));

  await check(
      'autentifikatsiyasiz currentIndex\'ni sura olmaydi',
      () => assertFails(doc(unauth, ACTIVE_ROUTE).update({currentIndex: 9})));

  await check(
      'begona kuryer birovning reysini o\'ziga o\'tkaza olmaydi',
      () => assertFails(doc(other, READY_ROUTE).update({
        status: 'active', courierId: OTHER_COURIER, startedAt: new Date(),
      })));

  await check(
      'begona kuryer birovning reysini tugata olmaydi',
      () => assertFails(doc(other, ACTIVE_ROUTE).update({
        status: 'completed', completedAt: new Date(),
      })));

  await check(
      'autentifikatsiyasiz reysni o\'qiy olmaydi',
      () => assertFails(doc(unauth, ACTIVE_ROUTE).get()));

  await check(
      'begona kuryer birovning reysini o\'qiy olmaydi',
      () => assertFails(doc(other, ACTIVE_ROUTE).get()));

  // ── Kuryerning haqiqiy oqimi ishlashda davom etsin ──────────────────
  await check(
      'kuryer o\'z reysini o\'qiydi',
      () => assertSucceeds(doc(mine, ACTIVE_ROUTE).get()));

  await check(
      'kuryer o\'z reyslarini so\'rov bilan oladi (getActiveForCourier)',
      () => assertSucceeds(col(mine)
          .where('courierId', '==', COURIER)
          .where('status', 'in', ['active', 'ready'])
          .get()));

  await check(
      'kuryer o\'z reysini boshlaydi: ready -> active (startRoute)',
      () => assertSucceeds(doc(mine, READY_ROUTE).update({
        status: 'active', courierId: COURIER, startedAt: new Date(),
      })));

  await check(
      'kuryer currentIndex\'ni suradi (advanceIndex)',
      () => assertSucceeds(doc(mine, ACTIVE_ROUTE).update({currentIndex: 1})));

  // C5/F11: tugatish faqat reys tugaganda (currentIndex >= orders.length).
  // Ilova avval advanceIndex, keyin completeRoute yozadi (2 ta alohida yozuv).
  await check(
      'kuryer oxirgi bekatga o\'tadi (advanceIndex -> 2/2)',
      () => assertSucceeds(doc(mine, ACTIVE_ROUTE).update({currentIndex: 2})));

  await check(
      'kuryer reysni tugatadi, reys tugagan (completeRoute)',
      () => assertSucceeds(doc(mine, ACTIVE_ROUTE).update({
        status: 'completed', completedAt: new Date(),
      })));

  // C5/F11: yetkazilmagan buyurtma bor reysni kuryer tugata olmaydi.
  await check(
      'C5: kuryer currentIndex=0 (2 buyurtma) reysni tugata olmaydi',
      () => assertFails(doc(mine, PENDING_ROUTE).update({
        status: 'completed', completedAt: new Date(),
      })));

  await check(
      'C5: kuryer currentIndex=1 (1 buyurtma qolgan) reysni tugata olmaydi',
      async () => {
        await assertSucceeds(doc(mine, PENDING_ROUTE).update({currentIndex: 1}));
        await assertFails(doc(mine, PENDING_ROUTE).update({
          status: 'completed', completedAt: new Date(),
        }));
      });

  await check(
      'C5: kuryer reysni cancelled qila olmaydi',
      () => assertFails(doc(mine, PENDING_ROUTE).update({status: 'cancelled'})));

  await check(
      'C5: kuryer faol reysni ready ga qaytara olmaydi',
      () => assertFails(doc(mine, PENDING_ROUTE).update({status: 'ready'})));

  await check(
      'C5: kuryer tugagan reysni qayta active qila olmaydi',
      () => assertFails(doc(mine, ACTIVE_ROUTE).update({status: 'active'})));

  await check(
      'C5: begona kuryer tugagan reysni ham o\'zgartira olmaydi',
      () => assertFails(doc(other, PENDING_ROUTE).update({currentIndex: 2})));

  await check(
      'C5: admin yetkazilmagan buyurtmali reysni tugata/bekor qila oladi',
      async () => {
        await assertSucceeds(doc(adminDb, PENDING_ROUTE).update({
          status: 'cancelled',
        }));
      });

  // ── Admin ───────────────────────────────────────────────────────────
  await check(
      'admin barcha faol reyslarni o\'qiydi (watchActiveRoutes)',
      () => assertSucceeds(col(adminDb)
          .where('status', 'in', ['ready', 'active']).get()));

  await check(
      'admin yangi reys yaratadi',
      () => assertSucceeds(doc(adminDb, 'route_new')
          .set(routeDoc(COURIER, 'ready'))));

  await check(
      'admin reysni boshqa kuryerga o\'tkazadi',
      () => assertSucceeds(doc(adminDb, 'route_new')
          .update({courierId: OTHER_COURIER})));

  // ── Chegara holatlari ───────────────────────────────────────────────
  await check(
      'kuryer ruxsat etilmagan maydonni o\'zgartira olmaydi (orders)',
      () => assertFails(doc(mine, READY_ROUTE).update({orders: ['x']})));

  await check(
      'kuryer reysni boshqa kuryerga o\'tkaza olmaydi',
      () => assertFails(doc(mine, READY_ROUTE)
          .update({courierId: OTHER_COURIER})));

  await check(
      'egasiz reysni kuryer o\'qiy olmaydi (getNextReady o\'lik kod)',
      () => assertFails(doc(mine, ORPHAN_ROUTE).get()));

  await check(
      'hech kim reysni o\'chira olmaydi, admin ham',
      () => assertFails(doc(adminDb, 'route_new').delete()));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} delivery_routes rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
