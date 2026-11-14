/**
 * Mahalliy taksi `trips` (taxiType local/alone) — Firestore rules.
 * Qoida: firestore.rules → `trips/{tripId}` + `localTripLifecycleUpdate()`.
 *
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/local_taxi_rules.test.js"
 *
 * Ikki guruh:
 *   A. Mavjud oqim (yaratish, broadcast accept, bekor, release, arrival) —
 *      ishlashi SHART.
 *   B. Xavfsizlik talablari (qoida 18/20) — FAIL bo'lsa, rules'da teshik bor.
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { serverTimestamp, deleteField } = require('firebase/firestore');

const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');

const PASSENGER = '998901000001';
const VICTIM = '998901000002';
const DRIVER = '998902000001';
const DRIVER2 = '998902000002';
const NOT_DRIVER = '998903000001';
const ADMIN = '998909990001';
const ACC1 = 'accLOCALDRV0000000001';
const ACC2 = 'accLOCALDRV0000000002';

function searchingTrip(extra = {}) {
  return {
    userPhone: PASSENGER,
    fromAddr: 'Gurlan markaz',
    fromLat: 41.84, fromLng: 60.39,
    status: 'searching',
    taxiType: 'local',
    radiusKm: 3,
    ...extra,
  };
}

function acceptedTrip(extra = {}) {
  return searchingTrip({
    status: 'accepted',
    acceptedDriverId: DRIVER, driverId: DRIVER,
    acceptedDriverName: 'Ali', driverName: 'Ali',
    acceptedDriverPhone: DRIVER, driverPhone: DRIVER,
    lockedFare: 15000, estimatedPrice: 15000, fareLockVersion: 1,
    ...extra,
  });
}

function acceptPatch(uid) {
  return {
    status: 'accepted',
    acceptedDriverId: uid, driverId: uid,
    acceptedDriverName: 'D', driverName: 'D',
    acceptedDriverPhone: uid, driverPhone: uid,
    acceptedDriverCar: 'Cobalt', acceptedDriverPlate: '90A123AA',
    acceptedAt: new Date(),
  };
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-local-taxi',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const record = (n, p, d) => { results.push({ n, p }); console.log(`${p ? 'PASS' : 'FAIL'} - ${n}${d ? ' :: ' + d : ''}`); };
  const check = async (n, fn) => { try { await fn(); record(n, true); } catch (e) { record(n, false, e.message); } };

  const seed = async (trips) => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('users').doc(PASSENGER).set({ role: 'user', bonusBalance: 50000 });
      await db.collection('users').doc(VICTIM).set({ role: 'user', bonusBalance: 200000 });
      await db.collection('users').doc(DRIVER).set({ role: 'user', accountId: ACC1 });
      await db.collection('users').doc(DRIVER2).set({ role: 'user', accountId: ACC2 });
      await db.collection('users').doc(NOT_DRIVER).set({ role: 'user' });
      for (const [acc, uid] of [[ACC1, DRIVER], [ACC2, DRIVER2]]) {
        await db.collection('provider_capabilities').doc(acc).set({
          identity: { accountId: acc, primaryUid: uid },
          taxi: { active: true, taxiTypes: ['alone'] },
          status: { taxi: 'verified' },
        });
      }
      for (const [id, data] of Object.entries(trips)) {
        await db.collection('trips').doc(id).set(data);
      }
    });
  };

  const ctxFor = (p) => testEnv.authenticatedContext(`uid_${p}`, { phone_number: '+' + p });
  const passenger = ctxFor(PASSENGER).firestore();
  const driver = ctxFor(DRIVER).firestore();
  const driver2 = ctxFor(DRIVER2).firestore();
  const notDriver = ctxFor(NOT_DRIVER).firestore();
  const noPhone = testEnv.authenticatedContext('anon_uid_1', {}).firestore();
  const unauth = testEnv.unauthenticatedContext().firestore();

  // ── A. Mavjud oqim ───────────────────────────────────────────────────
  await seed({ s1: searchingTrip(), a1: acceptedTrip() });

  await check('A1 yo\'lovchi o\'z nomidan searching trip yaratadi',
    () => assertSucceeds(passenger.collection('trips').doc('n1').set(searchingTrip())));
  await check('A2 tasdiqlangan haydovchi searching taklifni o\'qiydi',
    () => assertSucceeds(driver.collection('trips').doc('s1').get()));
  await check('A3 haydovchi bo\'lmagan foydalanuvchi begona taklifni o\'qiy olmaydi',
    () => assertFails(notDriver.collection('trips').doc('s1').get()));
  await check('A4 autentifikatsiyasiz o\'qish yo\'q',
    () => assertFails(unauth.collection('trips').doc('s1').get()));
  await check('A5 haydovchi bo\'lmagan accept qila olmaydi',
    () => assertFails(notDriver.collection('trips').doc('s1').update(acceptPatch(NOT_DRIVER))));
  await check('A6 boshqa haydovchi nomidan accept yo\'q (uid != acceptedDriverId)',
    () => assertFails(driver.collection('trips').doc('s1').update(acceptPatch(DRIVER2))));
  await check('A7 broadcast accept: tasdiqlangan haydovchi searching → accepted',
    () => assertSucceeds(driver.collection('trips').doc('s1').update(acceptPatch(DRIVER))));
  await check('A8 ikkinchi haydovchi allaqachon accepted trip\'ni tortib ololmaydi',
    () => assertFails(driver2.collection('trips').doc('s1').update(acceptPatch(DRIVER2))));
  await check('A9 haydovchi trip\'ni o\'zi `completed` qila olmaydi (faqat CF)',
    () => assertFails(driver.collection('trips').doc('a1').update({ status: 'completed', fare: 15000 })));
  await check('A10 yo\'lovchi trip\'ni `completed` qila olmaydi',
    () => assertFails(passenger.collection('trips').doc('a1').update({ status: 'completed' })));
  await check('A11 «Yetib keldim» — biriktirilgan haydovchi arrivedAt yozadi',
    () => assertSucceeds(driver.collection('trips').doc('a1').update({ arrivedAt: new Date() })));
  await check('A12 begona haydovchi arrivedAt yoza olmaydi',
    () => assertFails(driver2.collection('trips').doc('a1').update({ arrivedAt: new Date() })));
  await check('A13 yo\'lovchi `localTaxiBlockCounted`ni o\'zgartira olmaydi',
    () => assertFails(passenger.collection('trips').doc('a1').update({ localTaxiBlockCounted: true })));
  await check('A14 yo\'lovchi radiusni kengaytiradi (searching)',
    () => assertSucceeds(passenger.collection('trips').doc('n1').update({ radiusKm: 5 })));
  await check('A15 yo\'lovchi accepted trip\'ni bekor qiladi',
    () => assertSucceeds(passenger.collection('trips').doc('a1').update({
      status: 'cancelled', cancelledBy: 'passenger', cancelledAt: new Date(), cancelReason: 'x',
    })));
  await check('A16 yo\'lovchi bekor qilishda cancelledBy=driver deb yozolmaydi',
    () => assertFails(passenger.collection('trips').doc('n1').update({
      status: 'cancelled', cancelledBy: 'driver', cancelledAt: new Date(),
    })));

  await seed({ a2: acceptedTrip() });
  await check('A17 haydovchi release: accepted → searching',
    () => assertSucceeds(driver.collection('trips').doc('a2').update({
      status: 'searching',
      acceptedDriverId: '', driverId: '', acceptedDriverName: '', driverName: '',
      acceptedDriverPhone: '', driverPhone: '',
    })));
  await check('A18 trip o\'chirish yo\'q',
    () => assertFails(passenger.collection('trips').doc('a2').delete()));

  // ── B. Xavfsizlik talablari (FAIL = rules'da teshik) ─────────────────
  await seed({ a3: acceptedTrip({ passengerWalletIntent: 15000 }) });

  await check('B1 BOSHQA odam nomidan (userPhone=VICTIM) trip yaratib bo\'lmasligi kerak',
    () => assertFails(passenger.collection('trips').doc('x1').set(searchingTrip({ userPhone: VICTIM }))));
  await check('B2 begona nomidan trip + passengerWalletIntent + lockedFare yaratib bo\'lmasligi kerak (hamyon yechiladi)',
    () => assertFails(driver.collection('trips').doc('x2').set(searchingTrip({
      userPhone: VICTIM, passengerWalletIntent: 10000000, lockedFare: 10000000,
    }))));
  await check('B3 telefon tokenisiz (anonim) sessiya trip yaratmasligi kerak',
    () => assertFails(noPhone.collection('trips').doc('x3').set(searchingTrip())));
  await check('B4 yaratishda status=accepted/acceptedDriverId oldindan qo\'yib bo\'lmaydi',
    () => assertFails(passenger.collection('trips').doc('x4').set(searchingTrip({
      status: 'accepted', acceptedDriverId: DRIVER, driverId: DRIVER,
    }))));
  await check('B5 yo\'lovchi accepted safarda lockedFare\'ni 15000 → 1000 ga tushira olmasligi kerak',
    () => assertFails(passenger.collection('trips').doc('a3').update({ lockedFare: 1000, estimatedPrice: 1000 })));
  await check('B6 haydovchi accepted safarda lockedFare\'ni 15000 → 9 000 000 ga oshira olmasligi kerak',
    () => assertFails(driver.collection('trips').doc('a3').update({ lockedFare: 9000000, estimatedPrice: 9000000 })));
  await check('B7 haydovchi jabrlanuvchi nomidan hamyon intent\'li trip yarata olmaydi (self-dealing zanjiri)',
    () => assertFails(driver.collection('trips').doc('x7').set(searchingTrip({
      userPhone: VICTIM, passengerWalletIntent: 200000, lockedFare: 200000,
    }))));
  await check('B8 o\'z nomidan ham server maydonlarini (fareSource/lockedFare/tariffVersion) yozib bo\'lmaydi',
    () => assertFails(passenger.collection('trips').doc('x8').set(searchingTrip({
      fareSource: 'server', lockedFare: 1000, tariffVersion: 1,
    }))));
  await check('B9 eski ilova: o\'z nomidan oddiy trip (narxsiz) yaratiladi',
    () => assertSucceeds(passenger.collection('trips').doc('x9').set(searchingTrip({
      toAddr: 'B', toLat: 41.85, toLng: 60.40, geohash4: 'tp5m', driverId: '', driverName: '',
      price: 0, cancelCount: 0, createdAt: new Date(), expiresAt: new Date(Date.now() + 180000),
      userName: 'X', userGender: '', userBirthDate: '', regionId: 'r1',
    }))));
  await check('B10 yaratishda driverId oldindan to\'ldirib bo\'lmaydi',
    () => assertFails(passenger.collection('trips').doc('x10').set(searchingTrip({ driverId: DRIVER }))));
  await check('B11 yo\'lovchi accepted safarda manzil (toAddr) ni o\'zi o\'zgartira olmaydi — faqat CF',
    () => assertFails(passenger.collection('trips').doc('a3').update({ toAddr: 'Z', toLat: 1, toLng: 1 })));
  await check('B12 yo\'lovchi hamyon intent\'ini o\'zgartira oladi (o\'z safari)',
    () => assertSucceeds(passenger.collection('trips').doc('a3').update({
      passengerWalletIntent: 5000, passengerWalletUpdatedAt: new Date(),
    })));

  // ── C. Release muddati + tarif hujjatlari ─────────────────────────────
  await seed({ a4: acceptedTrip(), a5: acceptedTrip() });
  const releasePatch = {
    status: 'searching',
    acceptedDriverId: '', driverId: '', acceptedDriverName: '', driverName: '',
    acceptedDriverPhone: '', driverPhone: '',
  };
  await check('C1 release + releasedAt = server vaqti — ruxsat',
    () => assertSucceeds(driver.collection('trips').doc('a4').update({
      ...releasePatch, releasedAt: serverTimestamp(),
    })));
  await check('C2 release + releasedAt kelajakdagi soxta vaqt — rad',
    () => assertFails(driver.collection('trips').doc('a5').update({
      ...releasePatch, releasedAt: new Date(Date.now() + 3600000),
    })));
  await seed({ ar1: acceptedTrip({ arrivedAt: new Date() }), ar2: acceptedTrip({ arrivedAt: new Date() }) });
  await check('C2b release paytida eski «yetib keldim» (arrivedAt) o\'chiriladi — ruxsat',
    () => assertSucceeds(driver.collection('trips').doc('ar1').update({
      ...releasePatch, releasedAt: serverTimestamp(), arrivedAt: deleteField(),
    })));
  await check('C2c release paytida arrivedAt\'ni yangi qiymatga qo\'yib bo\'lmaydi',
    () => assertFails(driver.collection('trips').doc('ar2').update({
      ...releasePatch, arrivedAt: new Date(Date.now() + 60000),
    })));
  await seed({ a5: acceptedTrip() });
  await check('C3 release + expiresAt\'ni klient o\'zi cho\'za olmaydi',
    () => assertFails(driver.collection('trips').doc('a5').update({
      ...releasePatch, expiresAt: new Date(Date.now() + 3600000),
    })));

  await seed({
    old1: searchingTrip({ expiresAt: new Date(Date.now() - 60000) }),
    rel1: searchingTrip({ expiresAt: new Date(Date.now() - 600000), releasedAt: new Date(Date.now() - 60000) }),
    rel2: searchingTrip({ expiresAt: new Date(Date.now() - 600000), releasedAt: new Date(Date.now() - 240000) }),
  });
  await check('C3b muddati o\'tgan qidiruvni qabul qilib bo\'lmaydi',
    () => assertFails(driver.collection('trips').doc('old1').update(acceptPatch(DRIVER))));
  await check('C3c tark etilgan (releasedAt 1 daq oldin) trip qabul qilinadi',
    () => assertSucceeds(driver.collection('trips').doc('rel1').update(acceptPatch(DRIVER))));
  await check('C3d tark etilganiga 4 daq bo\'lgan trip qabul qilinmaydi',
    () => assertFails(driver.collection('trips').doc('rel2').update(acceptPatch(DRIVER))));

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('users').doc(ADMIN).set({ role: 'admin' });
    await ctx.firestore().collection('settings').doc('prices').set({ local_base: 5000, bread_price: 3000 });
    await ctx.firestore().collection('local_taxi_tariffs').doc('v1').set({ version: 1 });
  });
  const adminDb = ctxFor(ADMIN).firestore();
  await check('C4 admin klient orqali mahalliy taksi tarifini to\'g\'ridan yoza olmaydi (faqat CF, versiya bilan)',
    () => assertFails(adminDb.collection('settings').doc('prices').set({ local_base: 1 }, { merge: true })));
  await check('C4b admin tun/yo\'l koeffitsientini ham to\'g\'ridan yoza olmaydi',
    () => assertFails(adminDb.collection('settings').doc('prices').set({ local_night_coef: 3 }, { merge: true })));
  await check('C5 admin non narxini (boshqa kalit) yozishi buzilmagan',
    () => assertSucceeds(adminDb.collection('settings').doc('prices').set({ bread_price: 3500 }, { merge: true })));
  await check('C6b kalibrovka: admin o\'qiydi, hech kim yozmaydi (faqat CF)',
    async () => {
      await assertSucceeds(adminDb.collection('local_taxi_calibration').doc('road_factor').get());
      await assertFails(adminDb.collection('local_taxi_calibration').doc('road_factor').set({ regions: {} }));
      await assertFails(passenger.collection('local_taxi_calibration').doc('road_factor').get());
    });
  await check('C6 tarif tarixi: admin o\'qiydi, hech kim yozmaydi',
    async () => {
      await assertSucceeds(adminDb.collection('local_taxi_tariffs').doc('v1').get());
      await assertFails(adminDb.collection('local_taxi_tariffs').doc('v2').set({ version: 2 }));
      await assertFails(passenger.collection('local_taxi_tariffs').doc('v1').get());
    });

  const failed = results.filter((r) => !r.p);
  console.log(`\n${results.length - failed.length} passed, ${failed.length} failed`);
  await testEnv.cleanup();
  process.exit(failed.length ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
