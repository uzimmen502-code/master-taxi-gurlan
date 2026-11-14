/**
 * settings/app.orderReadyMode = 'auto' qilib qo'yadi (merge).
 * Natija: accepted -> ready avtomatik (onOrderUpdate CF orqali).
 */
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

async function main() {
  const ref = db.collection('settings').doc('app');
  const before = (await ref.get()).data() || {};
  console.log('Before: orderAcceptMode=%s orderReadyMode=%s', before.orderAcceptMode, before.orderReadyMode);

  await ref.set(
    { orderReadyMode: 'auto', updatedAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true },
  );

  const after = (await ref.get()).data() || {};
  console.log('After:  orderAcceptMode=%s orderReadyMode=%s', after.orderAcceptMode, after.orderReadyMode);
  console.log('OK ✅');
}
main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
