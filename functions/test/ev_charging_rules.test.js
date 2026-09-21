/**
 * ev_charging_stations Firestore rules — texnik topshiriq 8-bandidagi
 * Security Rules unit testlari: avtorizatsiyasiz foydalanuvchi yoza
 * olmasligi, boshqa foydalanuvchi nomidan yozib bo'lmasligi, report
 * limitidan (config'dan) oshib yozib bo'lmasligi, confirmation idempotent
 * ekanligi, verificationStatus/confirmationCount/reportCount/status'ni
 * client to'g'ridan-to'g'ri o'zgartira olmasligi.
 *
 * `anon_session_fields.test.js` shabloniga mos — to'liq izolyatsiyalangan
 * Firestore Emulator ustida ishlaydi, hech qanday real ma'lumotga tegmaydi.
 * Talab qilinadi: `firebase emulators:start --only firestore`.
 *
 * Ishlatish: npm run test:ev-charging
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

const STATION_ID = 'station1';
const USER_A = '998901112233';
const USER_B = '998904445566';

function baseStation(overrides = {}) {
  return {
    location: {latitude: 41.55, longitude: 60.6},
    geohash4: 'abcd',
    chargingTypes: [],
    connectors: [],
    status: 'unknown',
    verificationStatus: 'community',
    confirmationCount: 0,
    reportCount: 0,
    createdBy: USER_A,
    isActive: true,
    ...overrides,
  };
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-ev-charging',
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

  const anon = testEnv.authenticatedContext('guestUid', {firebase: {sign_in_provider: 'anonymous'}});
  const userA = testEnv.authenticatedContext('uidA', {phone_number: '+' + USER_A});
  const userB = testEnv.authenticatedContext('uidB', {phone_number: '+' + USER_B});
  const dbAnon = anon.firestore();
  const dbA = userA.firestore();
  const dbB = userB.firestore();

  await check('anon (guest) cannot read stations', () =>
    assertFails(dbAnon.collection('ev_charging_stations').doc(STATION_ID).get()));

  await check('registered user can create station with valid coords + own createdBy', () =>
    assertSucceeds(
      dbA.collection('ev_charging_stations').doc(STATION_ID).set(baseStation()),
    ));

  await check('registered user can read stations', () =>
    assertSucceeds(dbB.collection('ev_charging_stations').doc(STATION_ID).get()));

  await check('create without coordinates fails', () =>
    assertFails(
      dbA.collection('ev_charging_stations').doc('noCoords').set(
        baseStation({location: null}),
      ),
    ));

  await check('create with spoofed createdBy fails', () =>
    assertFails(
      dbB.collection('ev_charging_stations').doc('spoof').set(
        baseStation({createdBy: USER_A}),
      ),
    ));

  await check('create with verificationStatus escalated at creation fails', () =>
    assertFails(
      dbB.collection('ev_charging_stations').doc('escalate').set(
        baseStation({createdBy: USER_B, verificationStatus: 'verified'}),
      ),
    ));

  await check('registered user can patch optional fields', () =>
    assertSucceeds(
      dbB.collection('ev_charging_stations').doc(STATION_ID).update({
        powerKw: 60,
        updatedAt: new Date(),
      }),
    ));

  await check('client cannot directly change confirmationCount', () =>
    assertFails(
      dbB.collection('ev_charging_stations').doc(STATION_ID).update({
        confirmationCount: 99,
      }),
    ));

  await check('client cannot directly change verificationStatus', () =>
    assertFails(
      dbB.collection('ev_charging_stations').doc(STATION_ID).update({
        verificationStatus: 'verified',
      }),
    ));

  await check('own confirmation create succeeds', () =>
    assertSucceeds(
      dbA.collection('ev_charging_stations').doc(STATION_ID)
        .collection('confirmations').doc(USER_A)
        .set({userId: USER_A, confirmedAt: new Date()}),
    ));

  await check('confirmation is idempotent (re-set succeeds)', () =>
    assertSucceeds(
      dbA.collection('ev_charging_stations').doc(STATION_ID)
        .collection('confirmations').doc(USER_A)
        .set({userId: USER_A, confirmedAt: new Date()}),
    ));

  await check('cannot create confirmation under another userId', () =>
    assertFails(
      dbA.collection('ev_charging_stations').doc(STATION_ID)
        .collection('confirmations').doc(USER_B)
        .set({userId: USER_B, confirmedAt: new Date()}),
    ));

  await check('registered user can create report with valid reason', () =>
    assertSucceeds(
      dbB.collection('ev_charging_stations').doc(STATION_ID)
        .collection('reports').add({
          reporterId: USER_B,
          reason: 'not_working',
          comment: '',
          createdAt: new Date(),
        }),
    ));

  await check('report with spoofed reporterId fails', () =>
    assertFails(
      dbB.collection('ev_charging_stations').doc(STATION_ID)
        .collection('reports').add({
          reporterId: USER_A,
          reason: 'not_working',
          createdAt: new Date(),
        }),
    ));

  await check('report with invalid reason fails', () =>
    assertFails(
      dbB.collection('ev_charging_stations').doc(STATION_ID)
        .collection('reports').add({
          reporterId: USER_B,
          reason: 'not_a_real_reason',
          createdAt: new Date(),
        }),
    ));

  await testEnv.withSecurityRulesDisabled((ctx) =>
    ctx.firestore()
      .collection('ev_charging_stations').doc(STATION_ID)
      .collection('reportLimits').doc(USER_B)
      .set({count: 3, lastReportAt: new Date()}));

  await check('report blocked after reaching maxReportsPerUserPerStation', () =>
    assertFails(
      dbB.collection('ev_charging_stations').doc(STATION_ID)
        .collection('reports').add({
          reporterId: USER_B,
          reason: 'other',
          createdAt: new Date(),
        }),
    ));

  await check('client cannot write reportLimits directly', () =>
    assertFails(
      dbB.collection('ev_charging_stations').doc(STATION_ID)
        .collection('reportLimits').doc(USER_B)
        .set({count: 0}),
    ));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} ev_charging_stations rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
