/**
 * `provider_presence` Firestore rules — 13.6.3.
 *
 * Bu kolleksiya uchun qoida ANCHADAN BERI bor edi, lekin na yozuvchi, na
 * o'quvchi yozilgan edi (production'da 0 hujjat). Yozuvchi 3-qadamda
 * yoziladi — ya'ni bu test o'sha yozuvchining SHARTNOMASI.
 *
 * Yopilgan uchta teshik:
 *
 *   1. `updatedAt` ni KLIENT qo'yardi. Kuryer KELAJAK vaqtni yozib
 *      qo'ysa, u abadiy «hozir shu yerda» bo'lib turardi:
 *        - sweep hech qachon offline qilmaydi
 *          (`maintenance.makePresenceSweeper` — `ms >= cutoffMs`),
 *        - matching filtri ham tutmaydi
 *          (`sources/presence_geo.js` — `ms < cutoffMs`),
 *        - GPS yangiligi bonusini doim TO'LIQ oladi
 *          (`adapters/courier.js` — `score`).
 *      Endi `updatedAt == request.time`, ya'ni `serverTimestamp()` shart.
 *
 *   2. Hujjat ichidagi `providerId` MAYDONI tekshirilmagan edi — kuryer
 *      unga boshqa odamning raqamini yozib qo'yishi mumkin edi. Server
 *      tomoni endi kimlikni KALITdan oladi (`presence_geo.js`), qoida
 *      esa maydonni kalit bilan mos bo'lishga majburlaydi.
 *
 *   3. `allow write` DELETE'ni ham qamrab olgan edi, lekin delete'da
 *      `request.resource` bo'lmaydi — ya'ni egasi o'z joylashuv
 *      ma'lumotini umuman o'chira olmay turgan edi (40-qoida).
 *
 * TUZOQ, ataylab test bilan qulflangan: `offlineAt`/`offlineReason` ni
 * faqat sweep yozadi, lekin bu tekshiruv `affectedKeys()` bo'yicha
 * bo'lishi SHART. `keys().hasAny()` bilan yozilsa, sweep bir marta
 * ishlagandan keyin kuryerning HAR BIR heartbeat'i rad etilardi va
 * kuryer boshqa onlayn bo'la olmasdi.
 *
 * Ishlatish: repo ildizidan
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/provider_presence_rules.test.js"
 */
'use strict';
const path = require('path');
const fs = require('fs');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
// `@firebase/rules-unit-testing` ham AYNAN shu modulni ishlatadi
// (`dist/index.cjs.js` → `require('firebase/compat/app')`), shuning uchun
// sentinel mos keladi.
const firebase = require('firebase/compat/app');
require('firebase/compat/firestore');

const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

/** Har chaqiruvda YANGI sentinel. */
const serverTs = () => firebase.firestore.FieldValue.serverTimestamp();

const ADMIN_PHONE = '998901112233';
const COURIER = '998905556677';
/** Eski shakl: hujjat 9 xonali kalit bilan (`isOwner` ikkisini ham oladi). */
const OLD9_DOC = '906667788';
const OLD9_FULL = '998906667788';
const STRANGER = '998904445566';

/**
 * 3-QADAMDAGI DART YOZUVCHISI AYNAN SHU SHAKLNI YOZADI.
 *
 * `module` — `sources/presence_geo.js` so'rovidagi majburiy filtr
 * (`where('module','==',demand.module)`), `geohash` esa diapazon
 * so'rovining kaliti.
 */
function heartbeat(uid, over = {}) {
  return {
    providerId: uid,
    module: 'courier',
    isOnline: true,
    lat: 41.55,
    lng: 60.63,
    geohash: 'tz2abcdefg',
    vehicle: 'moto',
    updatedAt: serverTs(),
    ...over,
  };
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-presence',
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
      await db.collection('users').doc(ADMIN_PHONE).set({ role: 'admin' });
      await db.collection('users').doc(STRANGER).set({ role: 'user' });
      await db.collection('users').doc(COURIER).set({ role: 'courier' });
      await db.collection('provider_presence').doc(COURIER).set({
        providerId: COURIER, module: 'courier', isOnline: true,
        lat: 41.55, lng: 60.63, geohash: 'tz2abcdefg', updatedAt: new Date(),
      });
      await db.collection('provider_presence').doc(OLD9_DOC).set({
        providerId: OLD9_DOC, module: 'courier', isOnline: false,
        lat: 41.1, lng: 60.1, geohash: 'tz2zzzzzz', updatedAt: new Date(),
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
  const stranger = ctxFor(STRANGER).firestore();
  const own = ctxFor(COURIER).firestore();
  const own9 = ctxFor(OLD9_FULL).firestore();
  const adminDb = ctxFor(ADMIN_PHONE).firestore();

  const doc = (db, id) => db.collection('provider_presence').doc(id);
  const col = (db) => db.collection('provider_presence');

  // ── O'QISH: jonli GPS — PII (40-qoida) ──────────────────────────────
  await check(
      'autentifikatsiyasiz presence o\'qiy olmaydi',
      () => assertFails(doc(unauth, COURIER).get()));

  await check(
      'begona odam kuryerning jonli joylashuvini o\'qiy olmaydi',
      () => assertFails(doc(stranger, COURIER).get()));

  await check(
      'begona odam butun ro\'yxatni o\'qiy olmaydi',
      () => assertFails(col(stranger).where('isOnline', '==', true).get()));

  await check(
      'kuryer O\'Z holatini o\'qiydi',
      () => assertSucceeds(doc(own, COURIER).get()));

  await check(
      'admin kuryer holatini o\'qiydi (admin panel)',
      () => assertSucceeds(doc(adminDb, COURIER).get()));

  // ── YOZISH: asosiy oqim (3-qadam yozuvchisi) ────────────────────────
  await check(
      'kuryer heartbeat yozadi (update, serverTimestamp)',
      () => assertSucceeds(doc(own, COURIER).set(heartbeat(COURIER), { merge: true })));

  await check(
      'kuryer YANGI presence hujjati yaratadi (create)',
      () => assertSucceeds(doc(ctxFor(STRANGER).firestore(), STRANGER)
          .set(heartbeat(STRANGER))));

  await check(
      'kuryer o\'zini offline qiladi (isOnline: false)',
      () => assertSucceeds(doc(own, COURIER).update({
        isOnline: false, updatedAt: serverTs(),
      })));

  await check(
      'mavjud hujjatga qisman heartbeat (faqat lat + updatedAt) o\'tadi',
      () => assertSucceeds(doc(own, COURIER).update({
        lat: 41.57, updatedAt: serverTs(),
      })));

  await check(
      '`providerId` SIZ yangi hujjat yaratib bo\'lmaydi',
      () => assertFails(doc(ctxFor('998907778899').firestore(), '998907778899')
          .set({
            module: 'courier', isOnline: true, lat: 41.5, lng: 60.6,
            geohash: 'tz2aaaaaa', updatedAt: serverTs(),
          })));

  await check(
      '`updatedAt` SIZ yangi hujjat yaratib bo\'lmaydi',
      () => assertFails(doc(ctxFor('998907778899').firestore(), '998907778899')
          .set({
            providerId: '998907778899', module: 'courier', isOnline: true,
            lat: 41.5, lng: 60.6, geohash: 'tz2aaaaaa',
          })));

  await check(
      '9 xonali kalitli hujjatga 12 xonali `providerId` ham mos keladi',
      () => assertSucceeds(doc(own9, OLD9_DOC).update({
        isOnline: true, providerId: OLD9_FULL, updatedAt: serverTs(),
      })));

  // ── Teshik 1: VAQTNI KLIENT QO'YARDI ────────────────────────────────
  await check(
      'KLIENT SOATI bilan yozib bo\'lmaydi',
      () => assertFails(doc(own, COURIER).update({
        lat: 41.6, updatedAt: new Date(),
      })));

  await check(
      'KELAJAK vaqt bilan yozib bo\'lmaydi (abadiy «onlayn» ekspluati)',
      () => assertFails(doc(own, COURIER).update({
        lat: 41.6, updatedAt: new Date(Date.now() + 3600 * 1000),
      })));

  await check(
      '`updatedAt` siz yozib bo\'lmaydi',
      () => assertFails(doc(own, COURIER).update({ lat: 41.6 })));

  // ── Teshik 2: SOXTA `providerId` ────────────────────────────────────
  await check(
      'kuryer o\'z hujjatiga BOSHQA odamning `providerId`sini yoza olmaydi',
      () => assertFails(doc(own, COURIER).update({
        providerId: STRANGER, updatedAt: serverTs(),
      })));

  await check(
      '`providerId` son bo\'lsa rad etiladi',
      () => assertFails(doc(own, COURIER).update({
        providerId: 998905556677, updatedAt: serverTs(),
      })));

  // ── Begona va autentifikatsiyasiz ───────────────────────────────────
  await check(
      'begona odam kuryerni «onlayn» qila olmaydi',
      () => assertFails(doc(stranger, COURIER).update({
        isOnline: true, updatedAt: serverTs(),
      })));

  await check(
      'begona odam kuryer joylashuvini surib qo\'ya olmaydi',
      () => assertFails(doc(stranger, COURIER).update({
        lat: 0, lng: 0, geohash: 's00000000', updatedAt: serverTs(),
      })));

  await check(
      'autentifikatsiyasiz yoza olmaydi',
      () => assertFails(doc(unauth, COURIER).set(heartbeat(COURIER), { merge: true })));

  // ── Server egalik qiladigan maydonlar ───────────────────────────────
  await check(
      'kuryer `trustScore` yoza olmaydi',
      () => assertFails(doc(own, COURIER).update({
        trustScore: 99, updatedAt: serverTs(),
      })));

  await check(
      'kuryer `matchingBlocked`ni o\'chira olmaydi',
      () => assertFails(doc(own, COURIER).update({
        matchingBlocked: false, updatedAt: serverTs(),
      })));

  await check(
      'kuryer `offlineAt`ni O\'ZI yoza olmaydi (sweep maydoni)',
      () => assertFails(doc(own, COURIER).update({
        offlineAt: serverTs(), updatedAt: serverTs(),
      })));

  await check(
      'kuryer `offlineReason`ni o\'zgartira olmaydi',
      () => assertFails(doc(own, COURIER).update({
        offlineReason: 'soxta', updatedAt: serverTs(),
      })));

  // ── TUZOQ: sweep yozgandan KEYIN heartbeat ishlashda davom etsin ────
  //
  // Agar qoida `keys().hasAny(['offlineAt'])` bilan yozilsa, bu yerdan
  // keyin kuryer BOSHQA ONLAYN BO'LA OLMAYDI — `request.resource.data`
  // o'zgarmagan maydonlarni ham o'z ichiga oladi.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('provider_presence').doc(COURIER).update({
      isOnline: false, offlineAt: new Date(), offlineReason: 'stale_heartbeat',
    });
  });

  await check(
      'SWEEP offline qilgandan keyin kuryer qaytib onlayn bo\'ladi',
      () => assertSucceeds(doc(own, COURIER).set(heartbeat(COURIER), { merge: true })));

  await check(
      'sweep maydonlari turgan hujjatga oddiy heartbeat ham o\'tadi',
      () => assertSucceeds(doc(own, COURIER).update({
        lat: 41.58, lng: 60.64, updatedAt: serverTs(),
      })));

  // ── O'chirish (teshik 3) ────────────────────────────────────────────
  await check(
      'begona odam kuryer hujjatini o\'chira olmaydi',
      () => assertFails(doc(stranger, COURIER).delete()));

  await check(
      'egasi O\'Z joylashuv hujjatini o\'chiradi (40-qoida)',
      () => assertSucceeds(doc(own9, OLD9_DOC).delete()));

  await check(
      'admin presence hujjatini o\'chiradi',
      () => assertSucceeds(doc(adminDb, COURIER).delete()));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} provider_presence rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
