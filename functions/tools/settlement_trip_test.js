/**
 * Settlement Ledger — Trip settlement (confirm) yadrosi uchun XAVFSIZ test.
 *
 * Soxta haydovchi/yo'lovchi ustida confirmSettlement'ning ledger kompozitsiyasini
 * (postEntry + precheck + assert + onCommit) tekshiradi:
 *   1) float topUp 200000
 *   2) settlement 'pending' (7000) yaratish
 *   3) confirm → Dr driver_float / Cr passenger_credit 7000:
 *        driver_float 193000, passenger_credit 7000, bonusBalance 7000,
 *        wallet_ledger 'settlement_credit' 7000, settlement state 'completed'
 *   4) idempotent confirm → ikkilanmaydi
 *   5) float yetmaganda confirm → assert XATO, post yo'q, state 'pending'
 *
 * Hammasi tozalanadi; reconcile OLDIN == KEYIN.
 * Ishlatish: node tools/settlement_trip_test.js
 */
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();
const ledger = require(path.join(__dirname, '..', 'settlement_ledger'));

const DRIVER = '998000000002';
const PASS = '998000000003';
const floatAcc = ledger.driverFloatAccount(DRIVER);
const pcAcc = ledger.passengerCreditAccount(PASS);

let pass = 0;
let fail = 0;
function check(name, cond) {
  if (cond) { pass++; console.log(`  ✓ ${name}`); } else { fail++; console.log(`  ✗ ${name}`); }
}

async function balanceOf(accId) {
  const s = await db.collection(ledger.COL_ACCOUNTS).doc(accId).get();
  return s.exists ? (s.data().balance || 0) : 0;
}

async function topUp(opId, amount) {
  return ledger.postEntry(db, {
    idempotencyKey: `floatTopUp:${opId}`,
    kind: 'float_topup', refType: 'float_topup', refId: opId,
    postedBy: 'test', postedRole: 'system',
    legs: [{ account: 'admin_cash', dr: amount }, { account: floatAcc, cr: amount }],
  }, { mirrorBonus: false, meta: { test: true } });
}

async function createPending(settlementId, amount) {
  await db.collection(ledger.COL_SETTLEMENTS).doc(settlementId).set({
    tripId: 'trip_test', driverUid: DRIVER, passengerUid: PASS,
    totalChange: amount + 10000, cashGiven: 10000, settlementAmount: amount,
    state: 'pending', createdBy: DRIVER,
    createdAt: admin.firestore.FieldValue.serverTimestamp(), journalEntryId: '',
  });
}

// confirmSettlement CF'idagi ledger kompozitsiyasini takrorlaydi.
async function confirm(settlementId, amount) {
  const sref = db.collection(ledger.COL_SETTLEMENTS).doc(settlementId);
  return ledger.postEntry(db, {
    idempotencyKey: `settle:${settlementId}`,
    kind: 'trip_settlement', refType: 'settlement', refId: settlementId,
    postedBy: PASS, postedRole: 'passenger',
    legs: [{ account: floatAcc, dr: amount }, { account: pcAcc, cr: amount }],
  }, {
    mirrorBonus: true,
    walletLedgerType: 'settlement_credit',
    meta: { test: true, settlementId, driverUid: DRIVER },
    precheck: async (tx) => {
      const fresh = await tx.get(sref);
      const fd = fresh.exists ? (fresh.data() || {}) : {};
      if (!fresh.exists || fd.state !== 'pending') {
        throw new Error('not pending');
      }
      return fd;
    },
    assert: ({ accounts }) => {
      const fa = accounts.get(floatAcc);
      if (fa && fa.next < 0) throw new Error('insufficient float');
    },
    onCommit: (tx, { entryId }) => {
      tx.update(sref, {
        state: 'completed',
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        journalEntryId: entryId,
      });
    },
  });
}

async function cleanup(adminCashExisted, passUserExisted) {
  const jids = [
    'floatTopUp:test_td', 'settle:sett_test1', 'settle:sett_test2',
  ];
  for (const id of jids) {
    await db.collection(ledger.COL_JOURNAL).doc(id).delete().catch(() => {});
  }
  for (const id of ['sett_test1', 'sett_test2']) {
    await db.collection(ledger.COL_SETTLEMENTS).doc(id).delete().catch(() => {});
  }
  for (const id of [floatAcc, pcAcc]) {
    await db.collection(ledger.COL_ACCOUNTS).doc(id).delete().catch(() => {});
  }
  if (!adminCashExisted) {
    await db.collection(ledger.COL_ACCOUNTS).doc('admin_cash').delete().catch(() => {});
  }
  // Soxta yo'lovchi users hujjati (test yaratgan bo'lsa) + wallet_ledger.
  if (!passUserExisted) {
    const wl = await db.collection('users').doc(PASS)
        .collection('wallet_ledger').get();
    for (const d of wl.docs) await d.ref.delete().catch(() => {});
    await db.collection('users').doc(PASS).delete().catch(() => {});
  }
}

async function main() {
  console.log('=== Trip settlement (confirm) testi (self-cleaning) ===');
  const before = await ledger.reconcile(db);
  const adminCashExisted = (await db.collection(ledger.COL_ACCOUNTS).doc('admin_cash').get()).exists;
  const passUserExisted = (await db.collection('users').doc(PASS).get()).exists;

  try {
    // 1) float topUp 200000
    await topUp('test_td', 200000);
    check('topUp → float 200000', (await balanceOf(floatAcc)) === 200000);

    // 2) pending settlement 7000
    await createPending('sett_test1', 7000);

    // 3) confirm
    const r1 = await confirm('sett_test1', 7000);
    check('confirm → idempotent=false', r1.idempotent === false);
    check('driver_float 193000', (await balanceOf(floatAcc)) === 193000);
    check('passenger_credit 7000', (await balanceOf(pcAcc)) === 7000);

    const u = await db.collection('users').doc(PASS).get();
    check('bonusBalance 7000 (proeksiya)', ((u.data() || {}).bonusBalance || 0) === 7000);

    const wl = await db.collection('users').doc(PASS).collection('wallet_ledger')
        .where('type', '==', 'settlement_credit').get();
    check('wallet_ledger settlement_credit 7000',
        wl.size === 1 && (wl.docs[0].data().amount === 7000));

    const s1 = await db.collection(ledger.COL_SETTLEMENTS).doc('sett_test1').get();
    check('settlement state completed', (s1.data() || {}).state === 'completed');
    check('journalEntryId yozildi', !!(s1.data() || {}).journalEntryId);

    // 4) idempotent confirm
    const r2 = await confirm('sett_test1', 7000);
    check('qayta confirm → idempotent=true', r2.idempotent === true);
    check('driver_float hamon 193000', (await balanceOf(floatAcc)) === 193000);
    check('passenger_credit hamon 7000', (await balanceOf(pcAcc)) === 7000);

    // 5) float yetmaganda confirm → XATO
    await createPending('sett_test2', 999999);
    let threw = false;
    try {
      await confirm('sett_test2', 999999);
    } catch (e) {
      threw = true;
    }
    check('float yetmaganda confirm → assert XATO', threw);
    const noJ = await db.collection(ledger.COL_JOURNAL).doc('settle:sett_test2').get();
    check('post yaratilmagan (atomar)', !noJ.exists);
    const s2 = await db.collection(ledger.COL_SETTLEMENTS).doc('sett_test2').get();
    check('settlement state hamon pending', (s2.data() || {}).state === 'pending');
    check('driver_float hamon 193000', (await balanceOf(floatAcc)) === 193000);
  } finally {
    await cleanup(adminCashExisted, passUserExisted);
  }

  const after = await ledger.reconcile(db);
  console.log('\n=== Reconcile (test tozalangach) ===');
  check('balanced', after.balanced);
  check('identityOk', after.identityOk);
  check('projectionOk', after.projectionOk);
  check('entryCount o\'zgarmadi', after.entryCount === before.entryCount);
  check('accountCount o\'zgarmadi', after.accountCount === before.accountCount);
  check('assets o\'zgarmadi', after.assets === before.assets);
  check('liabilities o\'zgarmadi', after.liabilities === before.liabilities);

  console.log(`\n=== Natija: ${pass} ✓ / ${fail} ✗ ===`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
