/** Bitta buyurtmani 'ready' ga suradi (accepted -> ready stuck holatdan). */
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

const orderId = process.argv[2] || '0hVG6lD434bVx4eZFq4B';

async function main() {
  const ref = db.collection('orders').doc(orderId);
  const snap = await ref.get();
  if (!snap.exists) {
    console.log('Order topilmadi:', orderId);
    return;
  }
  const d = snap.data() || {};
  console.log(`Before: ${orderId} status=${d.status} fulfil=${d.fulfillmentStatus} mfy="${d.mfy}"`);

  await ref.update({
    status: 'ready',
    fulfillmentStatus: 'confirmed',
    statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const after = (await ref.get()).data() || {};
  console.log(`After:  ${orderId} status=${after.status} fulfil=${after.fulfillmentStatus}`);
  console.log('OK ✅ — kuryer MFY ekranida ko\'rinishi kerak');
}
main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
