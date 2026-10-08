/**
 * Marshrut `trips` — Firestore rules (admin audit O-2, 2026-10-08).
 *
 * Avval `marshrutTripLifecycleUpdate()` hech qanday auth/egalik talab
 * qilmasdi: har kim (hatto kirmagan) istalgan marshrut safarining `status`,
 * `fare`, `cashPaid`, `acceptedDriverId`… maydonlarini o'zgartira olardi.
 * Create esa `userPhone`ni token bilan solishtirmasdi.
 *
 * Yozuvchilar (lib/repositories/rides_repository.dart):
 *   yo'lovchi — muddati o'tgan pending → expired; pending/accepted → cancelled
 *   haydovchi (target) — pending → accepted / rejected / no_seats / expired
 *   haydovchi (accepted) — accepted → cancelled / completed (+cashPaid)
 *   admin — «Dispatch history» (isAdmin)
 * O'qish: haydovchi o'ziga yo'naltirilgan (`targetDriverId`) va qabul
 * qilgan (`acceptedDriverId`) safarlarni ro'yxat so'rovi bilan o'qiydi.
 *
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/marshrut_trips_rules.test.js"
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

const ADMIN = '998901112233';
const PAX = '998905556677';
const STRANGER = '998904445566';
const DRV = '998907770001';
const DRV2 = '998907770002';

const now = () => new Date();

function trip(extra = {}) {
  return {
    userPhone: PAX, pickupAddr: 'Gurlan bozor', taxiType: 'marshrut',
    status: 'pending', targetDriverId: DRV, driverPhone: DRV, driverName: 'Ali',
    scheduleId: 's1', fare: 5000, createdAt: now(),
    ...extra,
  };
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-marshrut-trips',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const record = (name, pass, detail) => {
    results.push({ name, pass });
    console.log(`${pass ? 'PASS' : 'FAIL'} - ${name}${detail ? ' :: ' + detail : ''}`);
  };
  const check = async (name, fn) => {
    try { await fn(); record(name, true); } catch (e) { record(name, false, e.message); }
  };

  async function seed(docs) {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('users').doc(ADMIN).set({ role: 'admin' });
      for (const [id, d] of Object.entries(docs)) await db.collection('trips').doc(id).set(d);
    });
  }
  const as = (p) => testEnv.authenticatedContext(`uid_${p}`, { phone_number: '+' + p }).firestore();
  const anon = () => testEnv.authenticatedContext('anon_1', {}).firestore();
  const unauth = () => testEnv.unauthenticatedContext().firestore();
  const t = (db, id) => db.collection('trips').doc(id);

  await seed({
    p1: trip(),
    a1: trip({ status: 'accepted', acceptedDriverId: DRV, acceptedAt: now() }),
  });

  // ── O'qish ────────────────────────────────────────────────────────
  await check('o\'qish: haydovchi o\'ziga yo\'naltirilgan pending ro\'yxatini o\'qiydi (watchPendingForDriver)',
      () => assertSucceeds(as(DRV).collection('trips')
          .where('targetDriverId', '==', DRV).where('status', '==', 'pending').get()));
  await check('o\'qish: haydovchi qabul qilganlarini o\'qiydi (watchAcceptedForDriver)',
      () => assertSucceeds(as(DRV).collection('trips')
          .where('acceptedDriverId', '==', DRV).where('status', '==', 'accepted').get()));
  await check('o\'qish: boshqa haydovchi boshqaning ro\'yxatini o\'qiy olmaydi',
      () => assertFails(as(DRV2).collection('trips').where('targetDriverId', '==', DRV).get()));
  await check('o\'qish: yo\'lovchi o\'z safarini o\'qiydi',
      () => assertSucceeds(t(as(PAX), 'p1').get()));
  await check('o\'qish: begona o\'qiy olmaydi', () => assertFails(t(as(STRANGER), 'p1').get()));

  // ── Yaratish ──────────────────────────────────────────────────────
  const newTrip = { userPhone: PAX, pickupAddr: 'X', taxiType: 'marshrut', status: 'pending', targetDriverId: DRV };
  await check('create: yo\'lovchi o\'z nomidan pending yaratadi', () => assertSucceeds(t(as(PAX), 'n1').set(newTrip)));
  await check('create: begona raqam nomidan — rad', () => assertFails(t(as(STRANGER), 'n2').set(newTrip)));
  await check('create: anonim — rad', () => assertFails(t(anon(), 'n3').set(newTrip)));

  // ── Yangilash: kirmagan / begona ──────────────────────────────────
  await check('update: kirmagan status/fare/cashPaid o\'zgartira olmaydi',
      () => assertFails(t(unauth(), 'a1').update({ status: 'completed', cashPaid: 0 })));
  await check('update: anonim sessiya — rad',
      () => assertFails(t(anon(), 'a1').update({ status: 'cancelled', cancelledBy: 'passenger', cancelledAt: now() })));
  await check('update: begona foydalanuvchi bekor qila olmaydi',
      () => assertFails(t(as(STRANGER), 'a1').update({ status: 'cancelled', cancelledBy: 'passenger', cancelledAt: now() })));
  await check('update: boshqa haydovchi yakunlay olmaydi',
      () => assertFails(t(as(DRV2), 'a1').update({ status: 'completed', completedBy: DRV2, completedAt: now(), cashPaid: 5000 })));

  // ── Yo'lovchi ─────────────────────────────────────────────────────
  await check('yo\'lovchi: pending → expired (P1/P2)',
      () => assertSucceeds(t(as(PAX), 'p1').update({ status: 'expired', expiredAt: now() })));
  await seed({ p1: trip(), a1: trip({ status: 'accepted', acceptedDriverId: DRV }) });
  await check('yo\'lovchi: pending → cancelled (markCancelled, cancelledBy=user)',
      () => assertSucceeds(t(as(PAX), 'p1').set({ status: 'cancelled', cancelledBy: 'user', cancelledAt: now() }, { merge: true })));
  await check('yo\'lovchi: accepted → cancelled (cancelMarshrutByPassenger)',
      () => assertSucceeds(t(as(PAX), 'a1').update({
        status: 'cancelled', cancelledBy: 'passenger', cancelReason: 'x', cancelledAt: now(), notifyPassengerReroute: false,
      })));
  await seed({ a1: trip({ status: 'accepted', acceptedDriverId: DRV }) });
  await check('yo\'lovchi: o\'zi completed / fare / cashPaid yoza olmaydi',
      () => assertFails(t(as(PAX), 'a1').update({ status: 'completed', cashPaid: 0 })));
  await check('yo\'lovchi: haydovchi o\'rnida qabul qila olmaydi',
      () => assertFails(t(as(PAX), 'a1').update({ acceptedDriverId: PAX })));

  // ── Haydovchi (target) ────────────────────────────────────────────
  await seed({ p1: trip(), p2: trip(), p3: trip() });
  await check('haydovchi: pending → accepted (acceptMarshrutRide)',
      () => assertSucceeds(t(as(DRV), 'p1').update({
        status: 'accepted', acceptedDriverId: DRV, acceptedDriverName: 'Ali', acceptedDriverPhone: DRV,
        acceptedDriverCar: 'Damas', acceptedDriverPlate: '90A', acceptedAt: now(),
      })));
  await check('haydovchi: o\'zini emas, boshqani acceptedDriverId qila olmaydi',
      () => assertFails(t(as(DRV), 'p2').update({ status: 'accepted', acceptedDriverId: DRV2, acceptedAt: now() })));
  await check('haydovchi: pending → rejected (rejectRide)',
      () => assertSucceeds(t(as(DRV), 'p2').update({ status: 'rejected', rejectedBy: DRV, rejectedAt: now() })));
  await check('haydovchi: pending → no_seats',
      () => assertSucceeds(t(as(DRV), 'p3').update({ status: 'no_seats' })));
  await check('haydovchi: unga yo\'naltirilmagan safarni qabul qila olmaydi',
      () => assertFails(t(as(DRV2), 'p3').update({ status: 'accepted', acceptedDriverId: DRV2, acceptedAt: now() })));

  // ── Haydovchi (accepted) ──────────────────────────────────────────
  await seed({
    a1: trip({ status: 'accepted', acceptedDriverId: DRV }),
    a2: trip({ status: 'accepted', acceptedDriverId: DRV }),
  });
  await check('haydovchi: accepted → completed + cashPaid (_completeMarshrutRide, set merge)',
      () => assertSucceeds(t(as(DRV), 'a1').set({
        status: 'completed', completedBy: DRV, completedAt: now(), fare: 5000, cashPaid: 5000,
      }, { merge: true })));
  await check('haydovchi: yakunlashda fare\'ni o\'zgartira olmaydi',
      () => assertFails(t(as(DRV), 'a2').set({
        status: 'completed', completedBy: DRV, completedAt: now(), fare: 99999, cashPaid: 99999,
      }, { merge: true })));
  await check('haydovchi: accepted → cancelled (cancelMarshrutAcceptedByDriver)',
      () => assertSucceeds(t(as(DRV), 'a2').set({
        status: 'cancelled', cancelledBy: 'driver', cancelledByPhone: DRV, cancelReason: 'x',
        notifyPassengerReroute: true, cancelledAt: now(),
      }, { merge: true })));

  // ── Admin ─────────────────────────────────────────────────────────
  await seed({ a1: trip({ status: 'accepted', acceptedDriverId: DRV }) });
  await check('admin: Dispatch history yakunlash (completedByPhone bilan)',
      () => assertSucceeds(t(as(ADMIN), 'a1').set({
        status: 'completed', completedBy: 'admin', completedByPhone: ADMIN, completedAt: now(), fare: 5000, cashPaid: 5000,
      }, { merge: true })));

  await testEnv.cleanup();
  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} marshrut trips rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(' | '));
    process.exitCode = 1;
  }
}

main().catch((e) => { console.error('FATAL', e); process.exitCode = 1; });
