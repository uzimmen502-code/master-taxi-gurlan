/**
 * anon_sessions Firestore rules — AnonSessionService (Flutter client,
 * lib/services/anon_session_service.dart) yozadigan aniq maydon shaklini
 * mavjud firestore.rules haqiqatan ruxsat berishini tasdiqlaydi.
 *
 * `functions/tools/*_test.js` skriptlaridan farqli o'laroq (ular real
 * loyihaga service-account.json orqali ulanadi) — bu test to'liq
 * izolyatsiyalangan Firestore Emulator ustida ishlaydi, hech qanday real
 * ma'lumotga tegmaydi. Talab qilinadi: `firebase emulators:start --only
 * firestore` allaqachon ishga tushirilgan bo'lishi (yoki `firebase
 * emulators:exec` orqali o'ralgan holda).
 *
 * Ishlatish: npm run test:anon-sessions
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

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-anon-session-fields',
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

  await testEnv.clearFirestore();

  const anon = testEnv.authenticatedContext('guestUid1', {firebase: {sign_in_provider: 'anonymous'}});
  const db = anon.firestore();

  try {
    await assertSucceeds(
        db.collection('anon_sessions').doc('guestUid1').set({
          status: 'active',
          createdAt: new Date(),
          lastActiveAt: new Date(),
          deviceFingerprintHash: 'abc123',
          regionId: 'r1',
          districtId: 'd1',
          serviceAreaId: 'a1',
        }),
    );
    record('create: AnonSessionService shape (status/timestamps/fingerprint/geo)', true);
  } catch (e) {
    record('create: AnonSessionService shape (status/timestamps/fingerprint/geo)', false, e.message);
  }

  try {
    await assertSucceeds(
        db.collection('anon_sessions').doc('guestUid1').set(
            {lastActiveAt: new Date()}, {merge: true}),
    );
    record('update: lastActiveAt-only merge (returning guest)', true);
  } catch (e) {
    record('update: lastActiveAt-only merge (returning guest)', false, e.message);
  }

  try {
    await assertFails(
        db.collection('anon_sessions').doc('guestUid1').set(
            {status: 'merged'}, {merge: true}),
    );
    record('client cannot flip status to merged directly', true);
  } catch (e) {
    record('client cannot flip status to merged directly', false, e.message);
  }

  const anon2 = testEnv.authenticatedContext('guestUid2', {firebase: {sign_in_provider: 'anonymous'}});
  try {
    await assertSucceeds(
        anon2.firestore().collection('anon_sessions').doc('guestUid2').set({
          status: 'active',
          createdAt: new Date(),
          lastActiveAt: new Date(),
          deviceFingerprintHash: 'xyz789',
          regionId: '',
          districtId: '',
          serviceAreaId: '',
        }),
    );
    record('create with empty geo fields (no region selected yet) is allowed', true);
  } catch (e) {
    record('create with empty geo fields (no region selected yet) is allowed', false, e.message);
  }

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} anon_sessions field-shape checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
