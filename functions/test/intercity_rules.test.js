/**
 * intercity_bookings / intercity_drivers Firestore rules — «ШАҲАРЛАРАРО
 * ТАКСИ» QA (2026-09-24). Тўлиқ изоляцияланган Firestore Emulator устида
 * ишлайди, реал маълумотга тегмайди.
 *
 * Талаб: `firebase emulators:exec --only firestore "node test/intercity_rules.test.js"`.
 *
 * Текширилади:
 *   - Бронь яратиш рухсатлари (ўз телефони, totalAmount>0, status чекланган).
 *   - Бошқа телефон номидан бронь яратиб бўлмаслиги (spoofing).
 *   - Йўловчи ўз бронини бекор қила олиши; бегона — йўқ.
 *   - Иштирокчи ўқий олиши; бегона — йўқ.
 *   - [ХАВФ] intercity_drivers.seats'ни исталган авторизацияланган клиент
 *     исталган қийматга ёза олиши (seat-patch тешиги) — ҳозирги ҳолатни
 *     ҳужжатлаштиради (assertSucceeds). Ҳисоботда «блокловчи» деб белгиланган.
 *   - [ХАВФ] Йўловчи бронни бирдан `confirmed` қилиб яратиши (autoAccept
 *     клиентда) — ҳозир рухсат этилган (assertSucceeds), ҳисоботда қайд.
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

  // Ҳайдовчи ҳужжатини seed қиламиз (rules bypass — Admin SDK каби).
  await testEnv.withSecurityRulesDisabled((ctx) =>
    ctx.firestore().collection('intercity_drivers').doc(DRIVER).set(driverDoc()));

  // ─── Бронь яратиш ────────────────────────────────────────────────────
  await check('passenger creates OWN pending booking', () =>
    assertSucceeds(
      dbA.collection('intercity_bookings').doc('bkA').set(bookingData()),
    ));

  await check('passenger CANNOT create booking for another phone (spoof)', () =>
    assertFails(
      dbA.collection('intercity_bookings').doc('bkSpoof')
        .set(bookingData({userPhone: USER_B})),
    ));

  await check('booking with totalAmount<=0 is denied', () =>
    assertFails(
      dbA.collection('intercity_bookings').doc('bkZero')
        .set(bookingData({totalAmount: 0})),
    ));

  await check('booking with status=completed is denied (create)', () =>
    assertFails(
      dbA.collection('intercity_bookings').doc('bkDone')
        .set(bookingData({status: 'completed'})),
    ));

  // [ХАВФ #2] autoAccept клиентда ўқилгани учун йўловчи ўзини confirmed
  // қилиб яратиши мумкин — драйвер тасдиғини айланиб ўтади. Ҳозир РУХСАТ.
  await check('VULN: passenger can self-create CONFIRMED booking (autoAccept bypass)', () =>
    assertSucceeds(
      dbA.collection('intercity_bookings').doc('bkConf')
        .set(bookingData({status: 'confirmed', id: 'bkConf'})),
    ));

  // ─── Ўқиш ────────────────────────────────────────────────────────────
  await check('participant (passenger) can read own booking', () =>
    assertSucceeds(dbA.collection('intercity_bookings').doc('bkA').get()));
  await check('participant (driver) can read booking', () =>
    assertSucceeds(dbD.collection('intercity_bookings').doc('bkA').get()));
  await check('non-participant CANNOT read booking', () =>
    assertFails(dbB.collection('intercity_bookings').doc('bkA').get()));

  // ─── Бекор қилиш ─────────────────────────────────────────────────────
  await check('passenger cancels OWN booking (pending -> cancelled)', () =>
    assertSucceeds(
      dbA.collection('intercity_bookings').doc('bkA').update({
        status: 'cancelled',
        cancelReason: 'test',
        cancelledAt: new Date(),
      }),
    ));

  await testEnv.withSecurityRulesDisabled((ctx) =>
    ctx.firestore().collection('intercity_bookings').doc('bkA2').set(bookingData()));
  await check('non-participant CANNOT cancel someone else booking', () =>
    assertFails(
      dbB.collection('intercity_bookings').doc('bkA2').update({
        status: 'cancelled',
        cancelReason: 'x',
        cancelledAt: new Date(),
      }),
    ));

  // ─── Тасдиқлаш ───────────────────────────────────────────────────────
  await check('driver confirms pending booking (pending -> confirmed)', () =>
    assertSucceeds(
      dbD.collection('intercity_bookings').doc('bkA2').update({
        status: 'confirmed',
        confirmedAt: new Date(),
      }),
    ));

  await testEnv.withSecurityRulesDisabled((ctx) =>
    ctx.firestore().collection('intercity_bookings').doc('bkA3').set(bookingData()));
  await check('passenger CANNOT confirm own booking via update', () =>
    assertFails(
      dbA.collection('intercity_bookings').doc('bkA3').update({
        status: 'confirmed',
        confirmedAt: new Date(),
      }),
    ));

  // ─── [ХАВФ #1] seat-patch тешиги ─────────────────────────────────────
  // intercityDriverSeatBookingPatch() фақат ўзгарган майдонларни текширади,
  // қийматни ёки эгаликни эмас. Шунинг учун бегона авторизацияланган клиент
  // ҳайдовчининг seats'ини исталган қийматга ёзиши мумкин.
  await check('VULN: stranger can set driver.seats to 0 (sabotage)', () =>
    assertSucceeds(
      dbB.collection('intercity_drivers').doc(DRIVER).update({
        seats: 0,
        updatedAt: new Date(),
      }),
    ));
  await check('VULN: stranger can set driver.seats to negative / inflated', () =>
    assertSucceeds(
      dbB.collection('intercity_drivers').doc(DRIVER).update({
        seats: 999,
        updatedAt: new Date(),
      }),
    ));
  await check('VULN: even anonymous session can patch driver.seats', () =>
    assertSucceeds(
      dbAnon.collection('intercity_drivers').doc(DRIVER).update({
        seats: 1,
        updatedAt: new Date(),
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
