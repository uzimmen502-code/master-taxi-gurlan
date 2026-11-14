/** READ-ONLY: status=='ready' buyurtmalar va ularning mfy/lat/lng. */
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

async function main() {
  const snap = await db.collection('orders').where('status', '==', 'ready').get();
  console.log(`=== READY orders: ${snap.size} ta ===`);
  snap.docs.forEach((doc) => {
    const d = doc.data() || {};
    console.log(
      `  ${doc.id} | type=${d.type} total=${d.total} userPhone=${d.userPhone}\n` +
        `      mfy="${d.mfy}" lat=${d.lat} lng=${d.lng} address="${d.address}"`,
    );
  });
}
main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
