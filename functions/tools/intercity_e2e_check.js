/**
 * Шаҳарлараро такси E2E holati (READ-ONLY + optional activate).
 *
 *   node functions/tools/intercity_e2e_check.js
 *   node functions/tools/intercity_e2e_check.js --activate 998941110504
 */
const path = require('path');
const admin = require('firebase-admin');

const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

const today = new Date();
const dateKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;

async function listActiveDrivers() {
  const snap = await db.collection('intercity_drivers').where('isActive', '==', true).get();
  console.log(`\n=== ACTIVE DRIVERS (${snap.size}) ===`);
  snap.docs.forEach((d) => {
    const x = d.data();
    console.log(`  ${d.id} | ${x.name || x.driverName || '?'} | ${x.routeLabel || ''}`);
    console.log(`    seats=${x.seats} price=${x.price} date=${x.scheduleDate}`);
  });
  return snap;
}

async function listRecentBookings() {
  let snap;
  try {
    snap = await db.collection('intercity_bookings').orderBy('createdAt', 'desc').limit(8).get();
  } catch (_) {
    snap = await db.collection('intercity_bookings').limit(8).get();
  }
  console.log(`\n=== RECENT BOOKINGS (${snap.size}) ===`);
  snap.docs.forEach((d) => {
    const x = d.data();
    console.log(`  ${d.id} | ${x.status} | ${x.userPhone} -> ${x.driverId}`);
    console.log(`    ${x.fromCity} -> ${x.toCity} | ${x.passengers} x ${x.pricePerSeat}`);
  });
}

async function activateDriver(driverId) {
  const ref = db.collection('intercity_drivers').doc(driverId);
  const snap = await ref.get();
  if (!snap.exists) {
    console.error('Driver doc not found:', driverId);
    process.exit(1);
  }
  const x = snap.data();
  const stops =
    x.stops && x.stops.length >= 2
      ? x.stops
      : ['Хоразм • Гурлан', 'Хоразм • Янгибозор', 'Тошкент'];
  await ref.set(
    {
      isActive: true,
      isOnPanel: true,
      scheduleDate: dateKey,
      seats: x.seatCapacity || x.seats || 4,
      routeLabel: stops.join(' → '),
      from: stops[0],
      to: stops[stops.length - 1],
      stops,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  console.log(`\nActivated ${driverId} for ${dateKey}`);
}

async function main() {
  const activateId = process.argv.includes('--activate')
    ? process.argv[process.argv.indexOf('--activate') + 1]
    : null;
  console.log('=== INTERCITY E2E ===', dateKey);
  if (activateId) await activateDriver(activateId.replace(/\D/g, ''));
  await listActiveDrivers();
  await listRecentBookings();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
