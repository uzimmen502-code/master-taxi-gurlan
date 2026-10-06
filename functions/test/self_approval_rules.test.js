/**
 * ЎЗИГА ЎЗИ ҲУҚУҚ БЕРИШ — 13.6.4 (0a · 0b · 0c).
 *
 * D-14: «Фойдаланувчи ўзига ўзи `approved` capability беролмасин».
 * Шу қоидани текшираётганда учта жой топилди, учаласи ҳам продакшнда:
 *
 *   0a. `couriers/{id}` ни ЎЗИ яратиш = ўзига курьерлик ҳуқуқини
 *       бериш, чунки ҳужжат МАВЖУДЛИГИ `resolveAuthorizedCourierUid`
 *       (`functions/index.js:2399`) да ҳуқуқ сифатида ишлатилади ва 14
 *       та callable'ни очади.
 *
 *   0b. `drivers/{id}` — `create` да auth УМУМАН ЙЎҚ эди, ва
 *       `driverApprovalPatchOnly()` ҳам auth'сиз `approved: true` га
 *       рухсат берарди. Яъни аутентификациясиз ҳам тасдиқланган
 *       ҳайдовчи «ясаш» мумкин эди.
 *
 *   0c. `driver_requests` — `read: if isAdmin() || true`, яъни барча
 *       аризачиларнинг исми ва телефони очиқ рўйхат эди.
 *
 * Бу тест ҳам тешикларни, ҳам ҚОНУНИЙ оқимларни (regression) қулфлайди:
 * ҳайдовчи иш ҳолатини ўзгартириши, marshrut рўйхатдан ўтиши, аризачи
 * ўз ҳолатини кўриши, админ амаллари.
 *
 * Ишлатиш: репо илдизидан
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/self_approval_rules.test.js"
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
/** Оддий фойдаланувчи — ҳужум қилувчи томон. */
const ATTACKER = '998902223344';
/** Тасдиқланган marshrut ҳайдовчиси. */
const DRIVER = '998903334455';
/**
 * ТАСДИҚЛАНМАГАН ҳайдовчи — «ўзини тасдиқлаш» синови учун.
 *
 * Аввалги уриниш шу жойда НОТЎҒРИ ёзилган эди: синов аллақачон
 * тасдиқланган ҳайдовчида ўтказилганди, яъни `approved: true` ёзиш
 * ҳеч нарсани ЎЗГАРТИРМАЙДИ (`affectedKeys` да у йўқ) ва тест
 * ҳимояни эмас, no-op ёзувни текширарди.
 */
const PENDING = '998905556677';
/** Админ яратган курьер. */
const COURIER = '998904445566';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-self-approval',
    firestore: {
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
      host: HOST,
      port: Number(PORT),
    },
  });

  const results = [];
  function record(name, pass, detail) {
    results.push({ name, pass, detail });
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
      await db.collection('users').doc(ADMIN).set({ role: 'admin' });
      await db.collection('users').doc(ATTACKER).set({ role: 'user' });
      await db.collection('users').doc(DRIVER).set({ role: 'user' });
      await db.collection('users').doc(COURIER).set({ role: 'user' });
      await db.collection('users').doc(PENDING).set({ role: 'user' });

      // Ариза берган, лекин ҲАЛИ ТАСДИҚЛАНМАГАН ҳайдовчи.
      await db.collection('drivers').doc(PENDING).set({
        name: 'Jasur', phone: `+${PENDING}`,
        taxiType: 'marshrut',
        approved: false, approvalStatus: 'pending',
      });

      // CF `index.js:8431` айнан шундай ёзади (Admin SDK).
      await db.collection('drivers').doc(DRIVER).set({
        name: 'Rustam', phone: `+${DRIVER}`,
        taxiType: 'marshrut', taxiTypes: ['marshrut'],
        approved: true, approvalStatus: 'approved',
        isOnline: false, seats: 7,
      });
      // Админ яратган курьер реестри.
      await db.collection('couriers').doc(COURIER).set({
        name: 'Bobur', phone: `+${COURIER}`, isOnline: false,
      });
      // Ариза — аризачининг ўз ҳужжати.
      await db.collection('driver_requests').doc(ATTACKER).set({
        uid: ATTACKER, name: 'Sardor', phone: `+${ATTACKER}`,
        taxiType: 'marshrut', status: 'pending',
      });
      await db.collection('driver_requests').doc(DRIVER).set({
        uid: DRIVER, name: 'Rustam', phone: `+${DRIVER}`,
        taxiType: 'marshrut', status: 'approved',
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
  const attacker = ctxFor(ATTACKER).firestore();
  const driver = ctxFor(DRIVER).firestore();
  const pending = ctxFor(PENDING).firestore();
  const courier = ctxFor(COURIER).firestore();
  const adminDb = ctxFor(ADMIN).firestore();

  // ══ 0a. couriers — реестр ══════════════════════════════════════════
  await check(
      '0a: оддий фойдаланувчи ЎЗИГА курьер ҳужжати ясай ОЛМАЙДИ',
      () => assertFails(attacker.collection('couriers').doc(ATTACKER).set({
        isOnline: true, name: 'Sardor', phone: `+${ATTACKER}`,
      })));

  await check(
      '0a: аутентификациясиз ҳам ясай олмайди',
      () => assertFails(unauth.collection('couriers').doc('998909990011').set({
        isOnline: true, name: 'Soxta', phone: '+998909990011',
      })));

  await check(
      '0a: `set(merge)` орқали ҳам яратиб бўлмайди (heartbeat йўли)',
      () => assertFails(attacker.collection('couriers').doc(ATTACKER).set({
        isOnline: true, name: 'Sardor', phone: `+${ATTACKER}`,
        lat: 41.5, lng: 60.6,
      }, { merge: true })));

  await check(
      '0a: АДМИН курьер реестрини яратади (regression)',
      () => assertSucceeds(adminDb.collection('couriers').doc('998907778899').set({
        isOnline: false, name: 'Yangi', phone: '+998907778899',
      })));

  await check(
      '0a: мавжуд ҳужжатда курьер GPS heartbeat ёзади (regression)',
      () => assertSucceeds(courier.collection('couriers').doc(COURIER).set({
        name: 'Bobur', phone: `+${COURIER}`, isOnline: true,
        lat: 41.55, lng: 60.63, updatedAt: new Date(),
      }, { merge: true })));

  await check(
      '0a: курьер ўзини offline қилади (regression)',
      () => assertSucceeds(courier.collection('couriers').doc(COURIER).update({
        isOnline: false, updatedAt: new Date(),
      })));

  await check(
      '0a: бегона одам курьер ҳужжатини ўзгартира олмайди',
      () => assertFails(attacker.collection('couriers').doc(COURIER).update({
        fcmToken: 'tok_ogri_'.padEnd(40, 'x'),
      })));

  // ══ 0b. drivers — ўзини тасдиқлаш ══════════════════════════════════
  await check(
      '0b: АУТЕНТИФИКАЦИЯСИЗ ҳайдовчи ҳужжати ясаб бўлмайди',
      () => assertFails(unauth.collection('drivers').doc('998909990022').set({
        name: 'Soxta', phone: '+998909990022',
      })));

  await check(
      '0b: бегона рақамга ҳайдовчи ҳужжати ясаб бўлмайди',
      () => assertFails(attacker.collection('drivers').doc('998909990033').set({
        name: 'Soxta', phone: '+998909990033',
      })));

  await check(
      '0b: ЎЗИНИ ЯРАТИШДА `approved: true` бериб бўлмайди (асосий тешик)',
      () => assertFails(attacker.collection('drivers').doc(ATTACKER).set({
        name: 'Sardor', phone: `+${ATTACKER}`,
        taxiType: 'marshrut', taxiTypes: ['marshrut'],
        approved: true, approvalStatus: 'approved',
      })));

  await check(
      '0b: ТАСДИҚЛАНМАГАН ҳайдовчи ЎЗИНИ тасдиқлай олмайди',
      () => assertFails(pending.collection('drivers').doc(PENDING).update({
        approved: true, approvalStatus: 'approved', updatedAt: new Date(),
      })));

  await check(
      '0b: тасдиқланмаган ҳайдовчини аутентификациясиз тасдиқлаб бўлмайди',
      () => assertFails(unauth.collection('drivers').doc(PENDING).update({
        approved: true, approvalStatus: 'approved', updatedAt: new Date(),
      })));

  await check(
      '0b: бегона одам тасдиқланмаган ҳайдовчини тасдиқлай олмайди',
      () => assertFails(attacker.collection('drivers').doc(PENDING).update({
        approved: true, approvalStatus: 'approved',
      })));

  await check(
      '0b: тасдиқланмаган ҳайдовчи ўз исмини ўзгартира олади (regression)',
      () => assertSucceeds(pending.collection('drivers').doc(PENDING).update({
        name: 'Jasurbek', updatedAt: new Date(),
      })));

  await check(
      '0b: ўз ҳужжатини яратиш мумкин (лекин тасдиқсиз)',
      () => assertSucceeds(attacker.collection('drivers').doc(ATTACKER).set({
        name: 'Sardor', phone: `+${ATTACKER}`,
      })));

  await check(
      '0b: ЎЗ ҳужжатини кейин ҳам `approved` қила олмайди',
      () => assertFails(attacker.collection('drivers').doc(ATTACKER).update({
        approved: true, approvalStatus: 'approved',
      })));

  await check(
      '0b: тасдиқланган ҳайдовчи `approvalStatus`ни ўзгартира олмайди',
      () => assertFails(driver.collection('drivers').doc(DRIVER).update({
        approvalStatus: 'super', updatedAt: new Date(),
      })));

  await check(
      '0b: тасдиқланган ҳайдовчи иш ҳолатини ўзгартиради (regression)',
      () => assertSucceeds(driver.collection('drivers').doc(DRIVER).update({
        isOnline: true, lat: 41.3, lng: 60.4, updatedAt: new Date(),
      })));

  await check(
      '0b: marshrut рўйхатдан ўтиш patch\'и ишлайди (regression)',
      () => assertSucceeds(driver.collection('drivers').doc(DRIVER).update({
        name: 'Rustam', car: 'Damas', plate: '95 A 123 BB',
        seats: 7, stops: ['Gurlan', 'Urganch'], updatedAt: new Date(),
      })));

  await check(
      '0b: АДМИН ҳайдовчини тасдиқлай олади (regression)',
      () => assertSucceeds(adminDb.collection('drivers').doc(PENDING).update({
        approved: true, approvalStatus: 'approved',
        taxiTypes: ['marshrut'], updatedAt: new Date(),
      })));

  await check(
      '0b: админ тасдиқланган ҳужжат ҳам яратади (CF йўли, regression)',
      () => assertSucceeds(adminDb.collection('drivers').doc('998909992200').set({
        name: 'Admin yaratdi', phone: '+998909992200',
        taxiType: 'local', approved: true, approvalStatus: 'approved',
      })));

  // ══ 0c. driver_requests — аризачилар PII ═══════════════════════════
  await check(
      '0c: БУТУН АРИЗАЛАР РЎЙХАТИНИ юклаб бўлмайди',
      () => assertFails(attacker.collection('driver_requests').get()));

  await check(
      '0c: аутентификациясиз ҳам рўйхат юклаб бўлмайди',
      () => assertFails(unauth.collection('driver_requests').get()));

  await check(
      '0c: `where` фильтри билан ҳам рўйхат олиб бўлмайди',
      () => assertFails(attacker.collection('driver_requests')
          .where('status', '==', 'pending').get()));

  await check(
      '0c: аризачи ЎЗ ҳолатини кўради (regression, ID бўйича)',
      () => assertSucceeds(attacker.collection('driver_requests')
          .doc(ATTACKER).get()));

  await check(
      '0c: Phone Auth\'дан ОЛДИН ҳам ўз ҳолатини кўради (regression)',
      () => assertSucceeds(unauth.collection('driver_requests')
          .doc(ATTACKER).get()));

  await check(
      '0c: админ рўйхатни олади (regression)',
      () => assertSucceeds(adminDb.collection('driver_requests').get()));

  await check(
      '0c: админ pending фильтри билан олади (regression)',
      () => assertSucceeds(adminDb.collection('driver_requests')
          .where('status', '==', 'pending').get()));

  await check(
      '0c: ариза бериш ишлайди (regression)',
      () => assertSucceeds(ctxFor('998909991100').firestore()
          .collection('driver_requests').doc('998909991100').set({
            uid: '998909991100', name: 'Yangi', phone: '+998909991100',
            taxiType: 'local', status: 'pending',
          })));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} self-approval rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
