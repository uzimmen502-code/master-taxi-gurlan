/**
 * Settlement Ledger — bonus ko'zgusi (prepare/commit) uchun XAVFSIZ test.
 *
 * Mavjud to'lov CF'lari uslubini (bonusBalance + ledger ko'zgusi BIR txn'da)
 * takrorlab, invariant passenger_credit == bonusBalance saqlanishini tekshiradi:
 *   1) credit 50000 (admin_clearing) → pc 50000, bonus 50000
 *   2) idempotent credit → ikkilanmaydi (bonus ham, pc ham)
 *   3) spend 20000 (admin_clearing) → pc 30000, bonus 30000
 *   4) payout 30000 (admin_cash, naqd echish) → pc 0, bonus 0, admin_cash -30000
 *
 * Hammasi tozalanadi; reconcile OLDIN == KEYIN (net-zero, projectionOk).
 * Ishlatish: node tools/settlement_spend_test.js
 */
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();
const ledger = require(path.join(__dirname, '..', 'settlement_ledger'));

const PASS = '998000000006';
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
async function bonusOf() {
  const s = await db.collection('users').doc(PASS).get();
  return s.exists ? (s.data().bonusBalance || 0) : 0;
}

// Mavjud CF uslubi: bonusBalance + ledger ko'zgusi AYNI tranzaksiyada.
async function applyBonus(delta, idempotencyKey, fundingAccount, kind) {
  await db.runTransaction(async (t) => {
    const userRef = db.collection('users').doc(PASS);
    const userSnap = await t.get(userRef);
    const ctx = await ledger.prepareBonusInTx(t, db, PASS, {
      idempotencyKey, fundingAccount,
    });
    if (ctx.jExists) return; // idempotent — bonus ham yozilmaydi
    const prev = userSnap.exists ? (userSnap.data().bonusBalance || 0) : 0;
    t.set(userRef, { bonusBalance: prev + delta }, { merge: true });
    ledger.commitBonusInTx(t, ctx, {
      delta, kind, refType: 'test', refId: idempotencyKey,
      meta: {}, postedBy: 'test', postedRole: 'test',
    });
  });
}

// Batch varianti: bonusBalance increment + ledger ko'zgusi AYNI batch'da.
async function applyBonusBatch(delta, idempotencyKey, fundingAccount, kind) {
  const batch = db.batch();
  batch.set(db.collection('users').doc(PASS), {
    bonusBalance: admin.firestore.FieldValue.increment(delta),
  }, { merge: true });
  ledger.commitBonusInBatch(batch, db, {
    uid: PASS, delta, kind, idempotencyKey, fundingAccount,
    refType: 'test', refId: idempotencyKey, meta: {},
    postedBy: 'test', postedRole: 'test',
  });
  await batch.commit();
}

async function cleanup(clearingBefore, cashBefore, passUserExisted) {
  for (const id of [
    'bonus:credit_test_1', 'bonus:spend_test_1', 'bonus:payout_test_1',
    'bonus:batch_credit_1', 'bonus:batch_spend_1',
  ]) {
    await db.collection(ledger.COL_JOURNAL).doc(id).delete().catch(() => {});
  }
  await db.collection(ledger.COL_ACCOUNTS).doc(pcAcc).delete().catch(() => {});
  await restoreOrDelete('admin_clearing', clearingBefore);
  await restoreOrDelete('admin_cash', cashBefore);
  if (!passUserExisted) {
    await db.collection('users').doc(PASS).delete().catch(() => {});
  } else {
    await db.collection('users').doc(PASS)
        .set({ bonusBalance: 0 }, { merge: true }).catch(() => {});
  }
}

async function restoreOrDelete(accId, before) {
  if (before.existed) {
    await db.collection(ledger.COL_ACCOUNTS).doc(accId).set({
      balance: before.balance,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  } else {
    await db.collection(ledger.COL_ACCOUNTS).doc(accId).delete().catch(() => {});
  }
}

async function snapAcc(accId) {
  const s = await db.collection(ledger.COL_ACCOUNTS).doc(accId).get();
  return { existed: s.exists, balance: s.exists ? (s.data().balance || 0) : 0 };
}

async function main() {
  console.log('=== Bonus ko\'zgusi (spendCredit) testi (self-cleaning) ===');
  const before = await ledger.reconcile(db);
  const clearingBefore = await snapAcc('admin_clearing');
  const cashBefore = await snapAcc('admin_cash');
  const passUserExisted = (await db.collection('users').doc(PASS).get()).exists;

  try {
    // 1) credit 50000
    await applyBonus(50000, 'credit_test_1', 'admin_clearing', 'change_accrued');
    check('credit → pc 50000', (await balanceOf(pcAcc)) === 50000);
    check('credit → bonus 50000', (await bonusOf()) === 50000);
    check('credit → admin_clearing +50000',
        (await balanceOf('admin_clearing')) === clearingBefore.balance + 50000);

    // 2) idempotent credit
    await applyBonus(50000, 'credit_test_1', 'admin_clearing', 'change_accrued');
    check('idempotent credit → pc hamon 50000', (await balanceOf(pcAcc)) === 50000);
    check('idempotent credit → bonus hamon 50000', (await bonusOf()) === 50000);

    // 3) spend 20000
    await applyBonus(-20000, 'spend_test_1', 'admin_clearing', 'purchase_debit');
    check('spend → pc 30000', (await balanceOf(pcAcc)) === 30000);
    check('spend → bonus 30000', (await bonusOf()) === 30000);

    // 4) payout 30000 (naqd echish, admin_cash)
    await applyBonus(-30000, 'payout_test_1', 'admin_cash', 'payout_paid');
    check('payout → pc 0', (await balanceOf(pcAcc)) === 0);
    check('payout → bonus 0', (await bonusOf()) === 0);
    check('payout → admin_cash -30000',
        (await balanceOf('admin_cash')) === cashBefore.balance - 30000);

    // 5) batch credit 40000 (commitBonusInBatch)
    await applyBonusBatch(40000, 'batch_credit_1', 'admin_clearing', 'order_courier_submit');
    check('batch credit → pc 40000', (await balanceOf(pcAcc)) === 40000);
    check('batch credit → bonus 40000', (await bonusOf()) === 40000);

    // 6) batch spend 40000 → pc 0
    await applyBonusBatch(-40000, 'batch_spend_1', 'admin_clearing', 'order_courier_submit');
    check('batch spend → pc 0', (await balanceOf(pcAcc)) === 0);
    check('batch spend → bonus 0', (await bonusOf()) === 0);

    // invariant: pc == bonus
    check('invariant pc == bonus', (await balanceOf(pcAcc)) === (await bonusOf()));
  } finally {
    await cleanup(clearingBefore, cashBefore, passUserExisted);
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
