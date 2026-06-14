const admin = require('firebase-admin');
const serviceAccount = require('../functions/service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();
const PHONE    = '+998912778777';
const DIGITS   = '998912778777';
const NAME     = 'Сидабилла';
const NOW      = admin.firestore.FieldValue.serverTimestamp();

async function run() {
  // 1. users — admin role
  await db.collection('users').doc(DIGITS).set({
    phone:     PHONE,
    name:      NAME,
    role:      'admin',
    updatedAt: NOW,
  }, { merge: true });
  console.log('✅ users/' + DIGITS + ' → role: admin');

  // 2. couriers
  await db.collection('couriers').doc(DIGITS).set({
    phone:     PHONE,
    name:      NAME,
    isOnline:  false,
    createdAt: NOW,
    updatedAt: NOW,
  }, { merge: true });
  console.log('✅ couriers/' + DIGITS);

  // 3. drivers
  await db.collection('drivers').doc(DIGITS).set({
    phone:          PHONE,
    name:           NAME,
    approved:       true,
    approvalStatus: 'approved',
    taxiType:       'local',
    taxiTypes:      ['local', 'alone'],
    isAvailable:    false,
    isOnline:       false,
    createdAt:      NOW,
    updatedAt:      NOW,
  }, { merge: true });
  console.log('✅ drivers/' + DIGITS);

  console.log('\n🎉 Барча ролlar tayinlandi!');
  process.exit(0);
}

run().catch(e => { console.error(e); process.exit(1); });
