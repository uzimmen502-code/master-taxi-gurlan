/** READ-ONLY: "Курьерда" қолиб кетган буюртмаларни диагностика. */
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

function ts(v) {
  try {
    if (!v) return '-';
    if (typeof v.toDate === 'function') return v.toDate().toISOString();
    return String(v);
  } catch (_) {
    return '-';
  }
}

async function dumpOrders(label, statuses) {
  console.log(`\n=== ${label} ===`);
  let total = 0;
  for (const st of statuses) {
    const snap = await db.collection('orders').where('status', '==', st).get();
    snap.docs.forEach((doc) => {
      total += 1;
      const d = doc.data() || {};
      console.log(`\n  • ${doc.id}`);
      console.log(`    status=${d.status} fulfillment=${d.fulfillmentStatus} payment=${d.paymentStatus}`);
      console.log(`    type=${d.type} total=${d.total} courierId=${d.courierId || d.courierPhone || '-'}`);
      console.log(`    userPhone=${d.userPhone || d.phone || '-'} mfy="${d.mfy || ''}"`);
      console.log(`    createdAt=${ts(d.createdAt)} statusUpdatedAt=${ts(d.statusUpdatedAt)}`);
      console.log(`    arrivedAt=${ts(d.arrivedAt)} paidAt=${ts(d.paidAt)} deliveredAt=${ts(d.deliveredAt)}`);
    });
  }
  if (total === 0) console.log('  (yo\'q)');
  console.log(`\n  JAMI: ${total} ta`);
}

async function main() {
  // Веб Админда "Курьерда" одатда in_delivery / courier статуслари.
  await dumpOrders('Курьерда (in_delivery / courier)', ['in_delivery', 'courier']);

  // Қўшимча: тўлиқ бўлмаган барча статуслар (диагностика учун)
  console.log('\n=== Барча буюртма статуслари (count) ===');
  const all = await db.collection('orders').get();
  const byStatus = {};
  all.docs.forEach((doc) => {
    const s = (doc.data() || {}).status || '(none)';
    byStatus[s] = (byStatus[s] || 0) + 1;
  });
  Object.entries(byStatus)
    .sort((a, b) => b[1] - a[1])
    .forEach(([s, c]) => console.log(`  ${s}: ${c}`));
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
