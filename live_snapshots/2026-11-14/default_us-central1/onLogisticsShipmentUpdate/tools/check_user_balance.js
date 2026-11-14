/** READ-ONLY: foydalanuvchi balansi + buyurtma to'lov holati. */
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();
const phone = (process.argv[2] || '998941110504').replace(/\D/g, '');

function uid9(p) { return p.length > 9 ? p.slice(-9) : p; }

async function main() {
  console.log('=== USER docs for', phone, '===');
  for (const id of new Set([phone, uid9(phone), '998' + uid9(phone)])) {
    const snap = await db.collection('users').doc(id).get();
    if (snap.exists) {
      const d = snap.data() || {};
      console.log(`  users/${id}: bonusBalance=${d.bonusBalance} phone=${d.phone} role=${d.role}`);
    } else {
      console.log(`  users/${id}: (yo'q)`);
    }
  }

  console.log('\n=== Order GU7PcsG33zCOlAn67AwC ===');
  const od = await db.collection('orders').doc('GU7PcsG33zCOlAn67AwC').get();
  if (od.exists) {
    const d = od.data() || {};
    console.log(`  total=${d.total} grandTotal=${d.grandTotal} status=${d.status} fulfillment=${d.fulfillmentStatus} payment=${d.paymentStatus}`);
    console.log(`  userPhone=${d.userPhone} phone=${d.phone}`);
  }
}
main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
