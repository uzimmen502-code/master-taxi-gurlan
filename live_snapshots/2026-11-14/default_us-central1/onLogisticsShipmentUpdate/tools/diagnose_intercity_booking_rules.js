/**
 * To'liq createBooking transaction — mavjud client doc bilan.
 * firebase emulators:exec --only firestore "node functions/tools/diagnose_intercity_booking_rules.js"
 */
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const ROOT = path.join(__dirname, '..', '..');
const RULES = fs.readFileSync(path.join(ROOT, 'firestore.rules'), 'utf8');

const phone = (process.argv[2] || '998912778777').replace(/\D/g, '');
const driverId = process.argv[3] || '998941110504';
const userKey = phone.length === 9 ? `998${phone}` : phone;
const e164 = `+${userKey}`;
const withPhoneClaim = process.argv[4] !== 'no-phone';

async function main() {
  const env = await initializeTestEnvironment({
    projectId: 'demo-intercity-booking-rules',
    firestore: { rules: RULES },
  });

  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('intercity_drivers').doc(driverId).set({
      isActive: true,
      seats: 4,
      seatCapacity: 4,
      driverName: 'Алишер',
      autoAcceptBookings: false,
    });
    // Production holati: client doc mavjud
    await db
      .collection('intercity_drivers')
      .doc(driverId)
      .collection('clients')
      .doc(userKey)
      .set({
        userName: 'сидабилла',
        userPhoneRaw: '+998 912778777',
        bookingCount: 1,
        totalSpent: 56,
        completedCount: 0,
      });
  });

  const token = withPhoneClaim ? { phone_number: e164 } : {};
  const authed = env.authenticatedContext('passenger-uid', token);
  const db = authed.firestore();

  const results = [];
  async function step(name, fn, expectFail = false) {
    try {
      if (expectFail) await assertFails(fn());
      else await assertSucceeds(fn());
      results.push({ step: name, ok: true });
    } catch (e) {
      results.push({ step: name, ok: false, error: String(e.message || e) });
    }
  }

  const bookingRef = db.collection('intercity_bookings').doc('testBooking1');
  const driverRef = db.collection('intercity_drivers').doc(driverId);
  const clientRef = driverRef.collection('clients').doc(userKey);
  const lockRef = db.collection('intercity_booking_locks').doc(`${driverId}_${userKey}`);
  const notifRef = db.collection('notifications').doc('notif1');

  await step('READ clients (existing doc)', () => clientRef.get());
  await step('UPDATE driver seats', () =>
    driverRef.update({ seats: 3, lastBookedAt: new Date(), updatedAt: new Date() }),
  );
  await step('SET lock', () =>
    lockRef.set({ bookingId: 'testBooking1', driverId, userKey, updatedAt: new Date() }),
  );
  await step('CREATE intercity_bookings', () =>
    bookingRef.set({
      userPhone: userKey,
      userName: 'Test',
      driverId,
      driverPhone: driverId,
      driverName: 'Алишер',
      carNumber: '01G318OB',
      fromCity: 'Xorazm',
      toCity: 'Toshkent',
      district: '',
      passengers: 1,
      pricePerSeat: 56666666,
      totalAmount: 56666666,
      status: 'pending',
      createdAt: new Date(),
      expiresAt: new Date(Date.now() + 30 * 60 * 1000),
      departureTime: new Date(),
      pickupAddress: '',
      dropoffNote: '',
      archivedByDriver: false,
    }),
  );
  await step('MERGE clients stats (existing)', () =>
    clientRef.set(
      {
        userName: 'Test',
        userPhoneRaw: userKey,
        bookingCount: 1,
        totalSpent: 56666666,
        lastBookingAt: new Date(),
        lastBookingId: 'testBooking1',
      },
      { merge: true },
    ),
  );
  await step('CREATE notifications', () =>
    notifRef.set({
      targetPhone: e164,
      title: 'Test',
      body: 'body',
      sent: false,
      type: 'intercity_booking_pending',
      bookingId: 'testBooking1',
      priority: 'high',
      createdAt: new Date(),
    }),
  );

  console.log('\n=== diagnosis (existing client doc) ===');
  console.log(`token phone claim: ${withPhoneClaim ? e164 : 'NONE'}\n`);
  for (const r of results) {
    console.log(`${r.ok ? 'OK  ' : 'FAIL'}  ${r.step}`);
    if (!r.ok) console.log(`       ${r.error}`);
  }
  const failed = results.filter((r) => !r.ok);
  if (failed.length) {
    console.log(`\n>>> FAIL: ${failed.map((f) => f.step).join(', ')}`);
    process.exitCode = 1;
  }
  await env.cleanup();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
