/** READ-ONLY: маълум буюртма/курьер бўйича барча delivery_routes. */
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();
const courier = (process.argv[2] || '998920224017').replace(/\D/g, '');
const orderId = process.argv[3] || 'GU7PcsG33zCOlAn67AwC';

function ts(v) {
  try {
    if (!v) return '-';
    if (typeof v.toDate === 'function') return v.toDate().toISOString();
    return String(v);
  } catch (_) { return '-'; }
}

async function main() {
  console.log(`=== delivery_routes for courier ${courier} (all statuses) ===`);
  const snap = await db.collection('delivery_routes')
    .where('courierId', '==', courier)
    .get();
  if (snap.empty) console.log('  (yo\'q)');
  snap.docs
    .sort((a, b) => {
      const ta = a.data().createdAt?.toMillis?.() || 0;
      const tb = b.data().createdAt?.toMillis?.() || 0;
      return tb - ta;
    })
    .forEach((doc) => {
      const d = doc.data() || {};
      const ids = d.orderIds || d.stops || [];
      const hasOrder = Array.isArray(ids) && ids.includes(orderId);
      console.log(`\n  ${doc.id}  ${hasOrder ? '⭐ (буюртма шу ерда)' : ''}`);
      console.log(`    status=${d.status} currentIndex=${d.currentIndex} count=${Array.isArray(ids) ? ids.length : '?'}`);
      console.log(`    createdAt=${ts(d.createdAt)} updatedAt=${ts(d.updatedAt)} completedAt=${ts(d.completedAt)}`);
      console.log(`    orderIds=${JSON.stringify(ids)}`);
    });
}
main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
