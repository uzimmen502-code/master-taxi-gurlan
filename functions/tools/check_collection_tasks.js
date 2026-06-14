/** READ-ONLY: barcha collection_tasks — courierId + status. */
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();
const courier = (process.argv[2] || '998920224017').replace(/\D/g, '');

async function main() {
  const snap = await db.collection('collection_tasks').get();
  console.log(`=== ALL collection_tasks: ${snap.size} ta (courier filter: ${courier}) ===`);
  const active = ['assigned', 'collecting'];
  let mineActive = 0;
  snap.docs.forEach((doc) => {
    const d = doc.data() || {};
    const mine = String(d.courierId || '').replace(/\D/g, '') === courier;
    const isActive = active.includes(String(d.status || ''));
    if (mine && isActive) mineActive += 1;
    console.log(
      `  ${doc.id} | status=${d.status} courierId=${d.courierId} customer=${d.customerPhone} ` +
        `${mine ? '<<MINE' : ''}${mine && isActive ? ' ACTIVE' : ''}`,
    );
  });
  console.log(`\n>>> Bannerda ko'rinishi kerak (mine + active): ${mineActive} ta`);
}
main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
