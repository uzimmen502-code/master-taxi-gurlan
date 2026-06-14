/**
 * users/{uid}/driverProfiles/marshrut hujjatlarini ro'yxatlash yoki o'chirish.
 *
 * Ishlatish (loyiha rootidan):
 *   node scripts/cleanup_marshrut_driver_profiles.js           # ro'yxat
 *   node scripts/cleanup_marshrut_driver_profiles.js --delete  # o'chirish (tasdiqlash bilan)
 */
const path = require('path');
const admin = require(path.join(
  __dirname,
  '../functions/node_modules/firebase-admin',
));
const readline = require('readline');
const serviceAccount = require('../functions/service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();
const shouldDelete = process.argv.includes('--delete');

async function fetchMarshrutProfiles() {
  const snap = await db.collectionGroup('driverProfiles').get();
  return snap.docs.filter((d) => d.id === 'marshrut');
}

function summarize(doc) {
  const uid = doc.ref.parent.parent.id;
  const data = doc.data();
  return {
    path: doc.ref.path,
    uid,
    driverName: data.driverName || '',
    carModel: data.carModel || '',
    plate: data.plate || '',
    seats: data.seats ?? null,
    stopsCount: Array.isArray(data.stops) ? data.stops.length : 0,
  };
}

async function confirm(question) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  const answer = await new Promise((resolve) => {
    rl.question(question, resolve);
  });
  rl.close();
  return answer.trim().toLowerCase() === 'yes';
}

async function run() {
  const docs = await fetchMarshrutProfiles();
  console.log(`JAMI: ${docs.length} ta driverProfiles/marshrut hujjati\n`);

  for (const doc of docs) {
    console.log(JSON.stringify(summarize(doc)));
  }

  if (!shouldDelete) {
    console.log('\nO\'chirish uchun:');
    console.log('  node scripts/cleanup_marshrut_driver_profiles.js --delete');
    return;
  }

  if (docs.length === 0) {
    console.log('\nO\'chirish uchun hujjat yo\'q.');
    return;
  }

  const ok = await confirm(
    `\n${docs.length} ta hujjatni o\'chirishni tasdiqlaysizmi? (yes/no): `,
  );
  if (!ok) {
    console.log('Bekor qilindi.');
    return;
  }

  const batch = db.batch();
  for (const doc of docs) {
    batch.delete(doc.ref);
  }
  await batch.commit();
  console.log(`✅ ${docs.length} ta hujjat o\'chirildi.`);
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
