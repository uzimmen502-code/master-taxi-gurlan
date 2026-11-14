/**
 * E2E test holatini Firestore'dan o'qish (READ-ONLY).
 *
 * Ishlatish (functions/ ichidan yoki root'dan):
 *   node functions/tools/e2e_check.js [customerPhone] [courierPhone]
 *
 * Misol:
 *   node functions/tools/e2e_check.js 998912778777 998920224017
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
  console.log('  bonusBalance:', d.bonusBalance);
  console.log('  role:', d.role, '| name:', d.name);
}

async function showWalletLedger() {
  console.log('\n=== WALLET_LEDGER (oxirgi 8) ===');
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

async function showCollectionTasks() {
  console.log('\n=== COLLECTION_TASKS (oxirgi 5) ===');
  let snap;
  try {
    snap = await db.collection('collection_tasks').orderBy('createdAt', 'desc').limit(5).get();
  } catch (e) {
    snap = await db.collection('collection_tasks').limit(5).get();
  }
  if (snap.empty) {
    console.log('  (task yo\'q)');
    return;
  }
  snap.docs.forEach((doc) => {
    const d = doc.data() || {};
    console.log(
      `  ${doc.id} | status=${d.status} V=${d.totalValue}/${d.finalValue} cashGiven=${d.cashGiven} ` +
        `walletDelta=${d.walletDelta} walletCredited=${d.walletCredited} withdrawn=${d.withdrawnFromBalance} ` +
        `courier=${d.courierId} customer=${d.customerPhone}`,
    );
  });
}

async function showSellSubmissions() {
  console.log('\n=== SELL_SUBMISSIONS (oxirgi 5) ===');
  let snap;
  try {
    snap = await db.collection('sell_submissions').orderBy('createdAt', 'desc').limit(5).get();
  } catch (e) {
    snap = await db.collection('sell_submissions').limit(5).get();
  }
  if (snap.empty) {
    console.log('  (so\'rov yo\'q)');
    return;
  }
  snap.docs.forEach((doc) => {
    const d = doc.data() || {};
    console.log(
      `  ${doc.id} | status=${d.status} inCollection=${d.inCollection} ` +
        `collectionTaskId=${d.collectionTaskId} collectionCompleted=${d.collectionCompleted} ` +
        `userPhone=${d.userPhone}`,
    );
  });
}

async function showWarehouse() {
  console.log('\n=== WAREHOUSE_STOCK ===');
  const snap = await db.collection('warehouse_stock').get();
  if (snap.empty) {
    console.log('  (bo\'sh)');
    return;
  }
  let total = 0;
  snap.docs.forEach((doc) => {
    const d = doc.data() || {};
    console.log(`  ${d.code} | ${d.label} | qty=${d.quantity} ${d.unit} | updatedAt=${ts(d.updatedAt)}`);
  });
}

async function main() {
  console.log('================ E2E SNAPSHOT ================');
  console.log('customer:', customerPhone, '| courier:', courierPhone);
  await showUser();
  await showWalletLedger();
  await showCollectionTasks();
  await showSellSubmissions();
  await showWarehouse();
  console.log('\n================ END ================');
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('ERROR:', e);
    process.exit(1);
  });
