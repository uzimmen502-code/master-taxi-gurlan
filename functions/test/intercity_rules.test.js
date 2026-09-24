/**
 * intercity_bookings / intercity_drivers Firestore rules — «ШАҲАРЛАРАРО
 * ТАКСИ» QA (2026-09-24). Тўлиқ изоляцияланган Firestore Emulator устида
 * ишлайди, реал маълумотга тегмайди.
 *
 * Талаб: `firebase emulators:exec --only firestore "node test/intercity_rules.test.js"`
 * ёки `npm run test:intercity` (эмулятор ишлаб турганда).
 *
 * QA топилмалари #1 (seat-patch тешиги) ва #2 (йўловчи ўзини `confirmed`
 * қилиши) callable CF'ларга кўчириш билан ёпилди — бу тест ўшани
 * исботлайди: клиент энди бронь яратолмайди, бекор қилолмайди ва
 * `intercity_drivers.seats` га ёзолмайди. Seat/бронь мутацияси faqat
 * `intercityCreateBooking` / `intercityCancelBooking` /
 * `intercityCompleteBooking` (Admin SDK) орқали.
 *
 * Шу билан бирга seat'га тегмайдиган клиент патчлари ишлашда давом
 * этишини ҳам текширади (регрессия гарди): ҳайдовчи тасдиғи, pickup
 * манзили, архив, "олиб кетилди".
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

const USER_A = '998901112233';
const USER_B = '998904445566';
const DRIVER = '998907776655';

function bookingData(overrides = {}) {
  return {
    userPhone: USER_A,
    userName: 'A',
    userGender: 'male',
    driverId: DRIVER,
    driverPhone: DRIVER,
    driverName: 'D',
    carNumber: '01A111AA',
    fromCity: 'Xorazm',
    toCity: 'Toshkent',
    district: '',
    passengers: 1,
    pricePerSeat: 50000,
    totalAmount: 50000,
    status: 'pending',
    createdAt: new Date(),
    expiresAt: new Date(Date.now() + 30 * 60000),
    departureTime: new Date(Date.now() + 3600000),
    ...overrides,
  };
}

function driverDoc(overrides = {}) {
  return {
    name: 'D',
    phone: DRIVER,
    isActive: true,
    seats: 4,
    seatCapacity: 4,
    from: 'Xorazm',
    to: 'Toshkent',
    hour: 8,
    ...overrides,
  };
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-intercity',
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

  const userA = testEnv.authenticatedContext('uidA', {phone_number: '+' + USER_A});
  const userB = testEnv.authenticatedContext('uidB', {phone_number: '+' + USER_B});
  const driver = testEnv.authenticatedContext('uidD', {phone_number: '+' + DRIVER});
  const anon = testEnv.authenticatedContext('guest', {firebase: {sign_in_provider: 'anonymous'}});
  const dbA = userA.firestore();
  const dbB = userB.firestore();
  const dbD = driver.firestore();
  const dbAnon = anon.firestore();

  // Admin SDK simulyatsiyasi — CF shu tarzda yozadi (rules bypass).
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const fdb = ctx.firestore();
    await fdb.collection('intercity_drivers').doc(DRIVER).set(driverDoc());
    await fdb.collection('intercity_bookings').doc('bkA').set(bookingData());
    await fdb.collection('intercity_bookings').doc('bkB').set(bookingData());
    await fdb.collection('intercity_bookings').doc('bkC').set(bookingData());
  });

  // ─── Бронь яратиш: клиент учун ЁПИҚ (топилма #1/#2 тузатилди) ────────
  await check('client CANNOT create booking directly (moved to CF)', () =>
    assertFails(
      dbA.collection('intercity_bookings').doc('new1').set(bookingData()),
    ));

  await check('client CANNOT self-create CONFIRMED booking (fix #2)', () =>
    assertFails(
      dbA.collection('intercity_bookings').doc('new2')
        .set(bookingData({status: 'confirmed'})),
    ));

  await check('client CANNOT create booking for another phone', () =>
    assertFails(
      dbA.collection('intercity_bookings').doc('new3')
        .set(bookingData({userPhone: USER_B})),
    ));

  // ─── seats: bron yo'li yopildi, lekin scheduleSync hali ochiq ────────
  // `intercityDriverSeatBookingPatch()` olib tashlandi (bron yo'li), ammo
  // `intercityDriverScheduleSync()` hamon `seats`ni ruxsat etilgan kalitlar
  // ro'yxatida saqlaydi va auth/egalik talab qilmaydi — u driver_schedule
  // sync uchun ataylab ochiq qoldirilgan. QOLGAN XAVF: uni yopish
  // driver_schedule auditiga bog'liq (haydovchi "ishga chiqish" oqimi
  // doim Phone Auth bilanmi — shuni tasdiqlash kerak).
  // Quyidagi 3 tekshiruv SHU HOLATNI hujjatlashtiradi (hali ochiq).
  await check('STILL OPEN (scheduleSync): stranger can set driver.seats to 0', () =>
    assertSucceeds(
      dbB.collection('intercity_drivers').doc(DRIVER).update({
        seats: 0, updatedAt: new Date(),
      }),
    ));
  await check('STILL OPEN (scheduleSync): stranger can inflate driver.seats', () =>
    assertSucceeds(
      dbB.collection('intercity_drivers').doc(DRIVER).update({
        seats: 999, updatedAt: new Date(),
      }),
    ));
  await check('STILL OPEN (scheduleSync): anonymous session can patch seats', () =>
    assertSucceeds(
      dbAnon.collection('intercity_drivers').doc(DRIVER).update({
        seats: 1, updatedAt: new Date(),
      }),
    ));
  // Haydovchining o'zi (isOwner) — bu KUTILGAN, o'z e'lonini tahrirlaydi.
  await check('driver (owner) can still edit own listing seats', () =>
    assertSucceeds(
      dbD.collection('intercity_drivers').doc(DRIVER).update({
        seats: 2, lastBookedAt: new Date(), updatedAt: new Date(),
      }),
    ));

  // ─── Бекор қилиш / якунлаш: клиент учун ЁПИҚ (серверга кўчди) ────────
  await check('client CANNOT cancel booking directly (moved to CF)', () =>
    assertFails(
      dbA.collection('intercity_bookings').doc('bkA').update({
        status: 'cancelled', cancelReason: 'x', cancelledAt: new Date(),
      }),
    ));
  await check('driver CANNOT complete booking directly (moved to CF)', () =>
    assertFails(
      dbD.collection('intercity_bookings').doc('bkA').update({
        status: 'completed', completedAt: new Date(),
      }),
    ));
  await check('non-participant CANNOT touch someone else booking', () =>
    assertFails(
      dbB.collection('intercity_bookings').doc('bkA').update({
        status: 'cancelled', cancelReason: 'x', cancelledAt: new Date(),
      }),
    ));

  // ─── Ўқиш (ўзгармади) ────────────────────────────────────────────────
  await check('participant (passenger) can read own booking', () =>
    assertSucceeds(dbA.collection('intercity_bookings').doc('bkA').get()));
  await check('participant (driver) can read booking', () =>
    assertSucceeds(dbD.collection('intercity_bookings').doc('bkA').get()));
  await check('non-participant CANNOT read booking', () =>
    assertFails(dbB.collection('intercity_bookings').doc('bkA').get()));

  // ─── Регрессия: seat'га тегмайдиган клиент патчлари ишлашда давом ────
  await check('REGRESSION: driver can still confirm (pending -> confirmed)', () =>
    assertSucceeds(
      dbD.collection('intercity_bookings').doc('bkB').update({
        status: 'confirmed', confirmedAt: new Date(),
      }),
    ));
  await check('REGRESSION: passenger can still set pickup address', () =>
    assertSucceeds(
      dbA.collection('intercity_bookings').doc('bkC').update({
        pickupAddress: 'Uy 12', pickupLat: 41.5, pickupLng: 60.6,
        updatedAt: new Date(),
      }),
    ));
  await check('REGRESSION: driver can still mark pickedUp', () =>
    assertSucceeds(
      dbD.collection('intercity_bookings').doc('bkC').update({
        pickedUp: true, pickedUpAt: new Date(), updatedAt: new Date(),
      }),
    ));
  await check('REGRESSION: passenger CANNOT confirm own booking', () =>
    assertFails(
      dbA.collection('intercity_bookings').doc('bkC').update({
        status: 'confirmed', confirmedAt: new Date(),
      }),
    ));
  await check('REGRESSION: driver can still end listing (isActive=false)', () =>
    assertSucceeds(
      dbD.collection('intercity_drivers').doc(DRIVER).update({
        isActive: false, isOnPanel: false, updatedAt: new Date(),
      }),
    ));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(
    `\n${results.length - failed.length}/${results.length} intercity rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exit(1);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
