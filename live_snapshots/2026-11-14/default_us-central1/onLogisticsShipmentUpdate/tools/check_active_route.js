/** READ-ONLY: courier active route + in_delivery orders. */
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();
const courier = (process.argv[2] || '998920224017').replace(/\D/g, '');

async function main() {
  console.log('=== ACTIVE routes for courier', courier, '===');
  const snap = await db.collection('delivery_routes')
    .where('courierId', '==', courier)
    .where('status', '==', 'active')
    .get();
  if (snap.empty) console.log('  (faol marshrut yo\'q)');
  snap.docs.forEach((doc) => {
    const d = doc.data() || {};
    const ids = d.orderIds || d.stops || [];
    console.log(`  ${doc.id} | status=${d.status} currentIndex=${d.currentIndex} count=${(Array.isArray(ids) ? ids.length : '?')}`);
    console.log('     orderIds=', JSON.stringify(ids));
  });

  console.log('\n=== in_delivery orders (global) ===');
  const od = await db.collection('orders').where('status', '==', 'in_delivery').get();
  console.log(`  jami: ${od.size} ta`);
  od.docs.forEach((doc) => {
    const d = doc.data() || {};
    console.log(`  ${doc.id} | total=${d.total} courierId=${d.courierId} mfy="${d.mfy}"`);
  });
}
main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
