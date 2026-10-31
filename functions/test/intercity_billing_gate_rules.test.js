/**
 * intercity_drivers: e'lonni YOQISH (`isActive: true`) yoki `billingTripId`ni O'ZGARTIRISH
 * faqat HAQIQIY to'langan reys bilan (audit H1, 2026-10).
 *
 *   firebase emulators:exec --only firestore --project demo-ic-gate \
 *     "node functions/test/intercity_billing_gate_rules.test.js"
 *
 * Teshik: eski qoida faqat `billingTripId` bo'sh emasligini tekshirardi. `endTripListing`
 * (to'liq refund) dan keyin haydovchi eski `billingTripId` bilan `isActive: true` qilib,
 * komissiyasiz e'lon qilib qo'ya olardi. Endi yoqish / reys almashtirish uchun
 * `taxi_trips/{billingTripId}` mavjud, `status == 'published'` va `driverUid` chaqiruvchi
 * bo'lishi shart. Ilova yozadigan boshqa hamma maydonlar (o'rin, narx, ko'chirish,
 * tripStatus, isOnPanel, autoAccept, isActive:false) ERKIN qoladi.
 *
 * Ilova yozuvlari (lib/taxi/intercity, schedules_repository, intercity_driver_panel_controller,
 * intercity_rides_repository, intercity_bookings_repository) - sanab o'tilgan.
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080').split(':');

const DRIVER = '998907776655';
const OTHER = '998904445566';

(async () => {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-ic-gate',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const check = async (name, fn) => {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  };
  const dbD = testEnv.authenticatedContext('uidD', { phone_number: `+${DRIVER}` }).firestore();
  const dbO = testEnv.authenticatedContext('uidO', { phone_number: `+${OTHER}` }).firestore();
  const ref = (db, id = DRIVER) => db.collection('intercity_drivers').doc(id);
  const listing = (over = {}) => ({
    name: 'D', phone: DRIVER, phoneDigits: DRIVER, seats: 2, seatCapacity: 4, price: 70000,
    from: 'Xorazm', to: 'Toshkent', hour: 8, minute: 0, scheduleDate: '2026-10-20', ...over,
  });
  async function seed({ active, tripId }) {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (c) => {
      const f = c.firestore();
      await f.collection('taxi_trips').doc('tPub').set({ driverUid: DRIVER, status: 'published' });
      await f.collection('taxi_trips').doc('tPub2').set({ driverUid: DRIVER, status: 'published' });
      await f.collection('taxi_trips').doc('tCancelled').set({ driverUid: DRIVER, status: 'cancelled', refunded: true });
      await f.collection('taxi_trips').doc('tDone').set({ driverUid: DRIVER, status: 'completed' });
      await f.collection('taxi_trips').doc('tPayReq').set({ driverUid: DRIVER, status: 'payment_required' });
      await f.collection('taxi_trips').doc('tOther').set({ driverUid: OTHER, status: 'published' });
      await f.collection('taxi_trips').doc('tPub9').set({ driverUid: DRIVER.slice(3), status: 'published' });
      if (tripId !== undefined) {
        await f.collection('intercity_drivers').doc(DRIVER).set(listing({ isActive: active, billingTripId: tripId }));
      }
    });
  }

  // ── Teshik: to'liq refunddan keyin bepul qayta yoqish ────────────────
  await seed({ active: false, tripId: 'tCancelled' });
  await check('H1: refunddan keyin eski (cancelled) billingTripId bilan isActive:true -> RAD', () =>
    assertFails(ref(dbD).set({ isActive: true, isOnPanel: true, updatedAt: new Date() }, { merge: true })));
  await check('H1: cancelled reys bilan update({isActive:true}) -> RAD', () =>
    assertFails(ref(dbD).update({ isActive: true })));
  await check('H1: completed reys bilan yoqish -> RAD', async () => {
    await seed({ active: false, tripId: 'tDone' });
    await assertFails(ref(dbD).update({ isActive: true }));
  });
  await check('H1: payment_required (to\'lanmagan) reys bilan yoqish -> RAD', async () => {
    await seed({ active: false, tripId: 'tPayReq' });
    await assertFails(ref(dbD).update({ isActive: true }));
  });
  await check('H1: mavjud bo\'lmagan reys id bilan yoqish -> RAD', async () => {
    await seed({ active: false, tripId: 'noSuchTrip' });
    await assertFails(ref(dbD).update({ isActive: true }));
  });
  await check('H1: BEGONA haydovchining published reysi bilan yoqish -> RAD', async () => {
    await seed({ active: false, tripId: 'tOther' });
    await assertFails(ref(dbD).update({ isActive: true }));
    await assertFails(ref(dbD).set({ isActive: true, billingTripId: 'tOther' }, { merge: true }));
  });
  await check('H1: yo\'l qo\'yilmagan belgili id ("a/b") bilan yoqish -> RAD', async () => {
    await seed({ active: false, tripId: 'x' });
    await assertFails(ref(dbD).set({ isActive: true, billingTripId: 'tPub/evil' }, { merge: true }));
  });

  // ── Qonuniy oqim: yangi reys e'lon qilish ───────────────────────────
  await check('OK: o\'zining published reysi bilan yoqish (billingTripId o\'zgarmagan, nofaoldan) -> RUXSAT', async () => {
    await seed({ active: false, tripId: 'tPub' });
    await assertSucceeds(ref(dbD).set({ isActive: true, isOnPanel: true, updatedAt: new Date() }, { merge: true }));
  });
  await check('OK: registerDriverSchedule shakli - eski cancelled reysdan YANGI published reysga o\'tib yoqish -> RUXSAT', async () => {
    await seed({ active: false, tripId: 'tCancelled' });
    await assertSucceeds(ref(dbD).set(listing({
      isActive: true, isOnPanel: true, billingTripId: 'tPub', rating: 4.5, updatedAt: new Date(),
    }), { merge: true }));
  });
  await check('OK: 9 xonali driverUid shaklidagi published reys ham o\'ziniki (phone match)', async () => {
    await seed({ active: false, tripId: 'tPub9' });
    await assertSucceeds(ref(dbD).update({ isActive: true }));
  });
  await check('OK: yangi e\'lon hujjati yaratish (published reys) -> RUXSAT; cancelled -> RAD; reyssiz -> RAD', async () => {
    await seed({});
    await assertFails(ref(dbD).set(listing({ isActive: true, billingTripId: 'tCancelled' })));
    await assertFails(ref(dbD).set(listing({ isActive: true })));
    await assertFails(ref(dbD).set(listing({ isActive: true, billingTripId: 'tOther' })));
    await assertSucceeds(ref(dbD).set(listing({ isActive: true, billingTripId: 'tPub' })));
  });
  await check('OK: setDriverAutoAccept - hujjat yo\'q, isActive yozilmaydi -> RUXSAT', async () => {
    await seed({});
    await assertSucceeds(ref(dbD).set({ autoAcceptBookings: true, updatedAt: new Date() }, { merge: true }));
  });

  // ── Faol e'lon: ilovaning oddiy yozuvlari ERKIN ───────────────────────
  await seed({ active: true, tripId: 'tPub' });
  await check('OK: faol e\'londa o\'rin / narx / yo\'nalish yangilash', () =>
    assertSucceeds(ref(dbD).update({ seats: 1, price: 80000, from: 'Urganch', to: 'Toshkent', updatedAt: new Date() })));
  await check('OK: ko\'chirish (scheduleDate/hour/minute) - rescheduleTrip yozuvi', () =>
    assertSucceeds(ref(dbD).set({ scheduleDate: '2026-10-22', hour: 15, minute: 30, updatedAt: new Date() }, { merge: true })));
  await check('OK: tripStatus (startTrip), isOnPanel, autoAccept', async () => {
    await assertSucceeds(ref(dbD).update({ tripStatus: 'in_progress', tripStartedAt: new Date(), updatedAt: new Date() }));
    await assertSucceeds(ref(dbD).set({ isOnPanel: false, updatedAt: new Date() }, { merge: true }));
    await assertSucceeds(ref(dbD).update({ autoAcceptBookings: true, updatedAt: new Date() }));
  });
  await check('OK: yopish (isActive:false) - endTripListing / closeExpiredForDriver', () =>
    assertSucceeds(ref(dbD).set({ isActive: false, isOnPanel: false, updatedAt: new Date() }, { merge: true })));
  await check('H1: yopilgandan keyin (reys cancelled bo\'lsa) qayta yoqish -> RAD', async () => {
    await testEnv.withSecurityRulesDisabled(async (c) => {
      await c.firestore().collection('taxi_trips').doc('tPub').update({ status: 'cancelled' });
    });
    await assertFails(ref(dbD).update({ isActive: true }));
  });

  // ── Faol e'londa reysni almashtirish ─────────────────────────────────
  await check('OK: faol e\'londa o\'zining BOSHQA published reysiga almashtirish', async () => {
    await seed({ active: true, tripId: 'tPub' });
    await assertSucceeds(ref(dbD).set({ billingTripId: 'tPub2', updatedAt: new Date() }, { merge: true }));
  });
  await check('H1: faol e\'londa billingTripId ni cancelled / begona / yo\'q reysga almashtirish -> RAD', async () => {
    await seed({ active: true, tripId: 'tPub' });
    await assertFails(ref(dbD).set({ billingTripId: 'tCancelled' }, { merge: true }));
    await assertFails(ref(dbD).set({ billingTripId: 'tOther' }, { merge: true }));
    await assertFails(ref(dbD).set({ billingTripId: 'none' }, { merge: true }));
    await assertFails(ref(dbD).set({ billingTripId: '' }, { merge: true }));
  });
  await check('OK: nofaol e\'londa billingTripId yozish (faollashtirilmaydi) cheklanmaydi', async () => {
    await seed({ active: false, tripId: 'tCancelled' });
    await assertSucceeds(ref(dbD).set({ billingTripId: 'tPub', updatedAt: new Date() }, { merge: true }));
  });

  // ── Boshqalar o'zgarmadi ───────────────────────────────────────────
  await check('begona foydalanuvchi baribir hech narsa yoza olmaydi (published reys bilan ham)', async () => {
    await seed({ active: false, tripId: 'tPub' });
    await assertFails(ref(dbO).update({ isActive: true }));
    await assertFails(ref(dbO).set({ isActive: true, billingTripId: 'tOther' }, { merge: true }));
  });
  await check('taxi_publish_requests / taxi_reschedules: mijoz o\'qiy ham yoza ham olmaydi (default-deny)', async () => {
    await testEnv.withSecurityRulesDisabled(async (c) => {
      await c.firestore().collection('taxi_publish_requests').doc(`${DRIVER}_req-AAAA-0001`).set({ tripId: 'tPub', status: 'published' });
    });
    await assertFails(dbD.collection('taxi_publish_requests').doc(`${DRIVER}_req-AAAA-0001`).get());
    await assertFails(dbD.collection('taxi_publish_requests').doc(`${DRIVER}_req-ZZZZ-0002`).set({ tripId: 'x', status: 'published' }));
    await assertFails(dbD.collection('taxi_reschedules').doc('r1').set({ tripId: 'x' }));
  });

  await testEnv.cleanup();
  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed}/${results.length} intercity billing gate rules checks passed.`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
