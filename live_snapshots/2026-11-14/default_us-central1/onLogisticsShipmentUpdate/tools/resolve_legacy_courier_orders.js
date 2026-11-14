#!/usr/bin/env node
/** Cancel non-terminal legacy courier_orders before deprecation. */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const keyPath = path.join(__dirname, '..', 'service-account.json');
if (!fs.existsSync(keyPath)) {
  console.error('service-account.json topilmadi');
  process.exit(1);
}
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(require(keyPath)),
    preferRest: true,
  });
}
const db = admin.firestore();

async function main() {
  const snap = await db.collection('courier_orders').get();
  let cancelled = 0;
  for (const doc of snap.docs) {
    const status = String((doc.data() || {}).status || '');
    if (status === 'delivered' || status === 'cancelled') continue;
    await doc.ref.update({
      status: 'cancelled',
      cancelReason: 'legacy_courier_orders_deprecation',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('cancelled', doc.id, 'was', status);
    cancelled += 1;
  }
  console.log(`Done. Cancelled ${cancelled} / ${snap.size} docs.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
