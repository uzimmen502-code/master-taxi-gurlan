/**
 * Marshrut taksi E2E holati (READ-ONLY).
 *
 *   node functions/tools/marshrut_e2e_check.js
 *   node functions/tools/marshrut_e2e_check.js 998920224017
 */
const path = require('path');
const admin = require('firebase-admin');

const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

const focusDriver = (process.argv[2] || '').replace(/\D/g, '');
const today = new Date();
const dateKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;

function ts(v) {
  try {
    if (v && typeof v.toDate === 'function') return v.toDate().toISOString();
  } catch (_) {}
  return null;
}

async function showDriver(id) {
  if (!id) return;
  console.log(`\n=== DRIVER ${id} ===`);
  const [drv, q, prof, schedSnap] = await Promise.all([
    db.collection('drivers').doc(id).get(),
    db.collection('queue').doc(id).get(),
    db.collection('users').doc(id).collection('driverProfiles').doc('marshrut').get(),
    db
      .collection('schedules')
      .where('driverId', '==', id)
      .where('date', '==', dateKey)
      .where('isActive', '==', true)
      .limit(1)
      .get(),
  ]);
  if (drv.exists) {
    const x = drv.data();
    console.log('  name:', x.name, '| isOnline:', x.isOnline, '| taxiType:', x.taxiType);
    if (x.lat != null) console.log('  GPS:', x.lat, x.lng);
  } else console.log('  drivers doc: yo\'q');
  if (q.exists) {
    const x = q.data();
    console.log('  queue active:', x.isActive, '| seatsLeft:', x.seatsLeft, '| autoPaused:', x.autoPausedReason || '-');
  } else console.log('  queue doc: yo\'q');
  if (prof.exists) {
    const x = prof.data();
    console.log('  profile stops:', (x.stops || []).join(' → '));
    console.log('  seats:', x.seats, '| start:', x.startTime);
  }
  if (!schedSnap.empty) {
    const s = schedSnap.docs[0].data();
    console.log('  schedule:', schedSnap.docs[0].id);
    console.log('  route:', s.from, '->', s.to, '| dir:', s.direction);
    console.log('  seatsLeft:', s.seatsLeft, '/', s.seats);
  } else console.log('  bugungi schedule: yo\'q');
}

async function showOnlineQueue() {
  const snap = await db.collection('queue').where('isActive', '==', true).get();
  const marshrut = snap.docs.filter((d) => (d.data().taxiType || '') === 'marshrut');
  console.log(`\n=== ONLINE MARSHRUT QUEUE (${marshrut.length}) ===`);
  marshrut.forEach((d) => {
    const x = d.data();
    console.log(`  ${d.id} | ${x.driverName || '?'} | seatsLeft: ${x.seatsLeft}`);
  });
}

async function showRecentTrips() {
  let snap;
  try {
    snap = await db.collection('trips').orderBy('createdAt', 'desc').limit(12).get();
  } catch (_) {
    snap = await db.collection('trips').limit(12).get();
  }
  console.log('\n=== RECENT MARSHRUT TRIPS ===');
  snap.docs
    .filter((d) => (d.data().taxiType || '') === 'marshrut')
    .slice(0, 8)
    .forEach((d) => {
      const x = d.data();
      console.log(`  ${d.id}`);
      console.log(`    ${x.status} | ${x.userPhone} | ${x.pickupMfy} -> ${x.dropoffMfy}`);
      console.log(`    driver: ${x.driverId || '-'} | created: ${ts(x.createdAt) || '?'}`);
    });
}

async function main() {
  console.log('=== MARSHRUT E2E ===', dateKey);
  if (focusDriver) await showDriver(focusDriver);
  await showOnlineQueue();
  await showRecentTrips();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
