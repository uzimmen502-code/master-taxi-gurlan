/**
 * E2E "Non buyurtma -> kuryer yetkazish -> to'lov" holatini Firestore'dan
 * o'qish (READ-ONLY).
 *
 * Ishlatish (root'dan):
 *   node functions/tools/e2e_bread_check.js [customerPhone] [courierPhone]
 *
 * Misol:
 *   node functions/tools/e2e_bread_check.js 998912778777 998920224017
 */
const path = require('path');
const admin = require('firebase-admin');

const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

const db = admin.firestore();

const customerPhone = (process.argv[2] || '998912778777').replace(/\D/g, '');
const courierPhone = (process.argv[3] || '998920224017').replace(/\D/g, '');

function ts(v) {
  try {
    if (v && typeof v.toDate === 'function') return v.toDate().toISOString();
  } catch (_) {}
  return v;
}

async function showUser() {
  console.log('\n=== USER (mijoz) ===', customerPhone);
  const snap = await db.collection('users').doc(customerPhone).get();
  if (!snap.exists) {
    console.log('  (user doc topilmadi)');
    return;
  }
  const d = snap.data() || {};
  console.log('  bonusBalance:', d.bonusBalance, '| role:', d.role, '| name:', d.name);
}

async function showCourier() {
  console.log('\n=== COURIER ===', courierPhone);
  const snap = await db.collection('couriers').doc(courierPhone).get();
  if (!snap.exists) {
    console.log('  (courier doc topilmadi -> kuryer roli/aktiv emas?)');
    return;
  }
  const d = snap.data() || {};
  console.log(`  online=${d.online} | name=${d.name} | activeRouteId=${d.activeRouteId}`);
}

async function showRecentOrders() {
  console.log('\n=== ORDERS (oxirgi 6, customer bo\'yicha) ===');
  let snap;
  try {
    snap = await db
      .collection('orders')
      .where('userPhone', '==', customerPhone)
      .orderBy('createdAt', 'desc')
      .limit(6)
      .get();
  } catch (e) {
    snap = await db.collection('orders').where('userPhone', '==', customerPhone).limit(6).get();
  }
  if (snap.empty) {
    console.log('  (buyurtma yo\'q)');
    return;
  }
  snap.docs.forEach((doc) => {
    const d = doc.data() || {};
    console.log(
      `  ${doc.id} | type=${d.type} status=${d.status} fulfil=${d.fulfillmentStatus} pay=${d.paymentStatus}\n` +
        `      total=${d.total} cashDue=${d.cashDue} cashPaid=${d.cashPaid} balanceApplied=${d.balanceApplied} ` +
        `courierId=${d.courierId}\n` +
        `      createdAt=${ts(d.createdAt)} deliveredAt=${ts(d.deliveredAt)}`,
    );
  });
}

async function showDeliveryRoutes() {
  console.log('\n=== DELIVERY_ROUTES (courier bo\'yicha, oxirgi 4) ===');
  let snap;
  try {
    snap = await db
      .collection('delivery_routes')
      .where('courierId', '==', courierPhone)
      .orderBy('createdAt', 'desc')
      .limit(4)
      .get();
  } catch (e) {
    snap = await db.collection('delivery_routes').where('courierId', '==', courierPhone).limit(4).get();
  }
  if (snap.empty) {
    console.log('  (marshrut yo\'q)');
    return;
  }
  snap.docs.forEach((doc) => {
    const d = doc.data() || {};
    const ids = Array.isArray(d.orderIds) ? d.orderIds : [];
    console.log(
      `  ${doc.id} | status=${d.status} currentIndex=${d.currentIndex} orders=[${ids.join(', ')}]`,
    );
  });
}

async function showWalletLedger() {
  console.log('\n=== WALLET_LEDGER (mijoz, oxirgi 8) ===');
  const col = db.collection('users').doc(customerPhone).collection('wallet_ledger');
  let snap;
  try {
    snap = await col.orderBy('createdAt', 'desc').limit(8).get();
  } catch (e) {
    snap = await col.limit(8).get();
  }
  if (snap.empty) {
    console.log('  (yozuv yo\'q)');
    return;
  }
  snap.docs.forEach((doc) => {
    const d = doc.data() || {};
    console.log(
      `  ${ts(d.createdAt)} | type=${d.type} amount=${d.amount} module=${d.module} ref=${d.refType}/${d.refId}`,
    );
  });
}

async function main() {
  console.log('========= BREAD E2E SNAPSHOT =========');
  console.log('customer:', customerPhone, '| courier:', courierPhone);
  await showUser();
  await showCourier();
  await showRecentOrders();
  await showDeliveryRoutes();
  await showWalletLedger();
  console.log('\n========= END =========');
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('ERROR:', e);
    process.exit(1);
  });
