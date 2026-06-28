/**
 * Settlement Ledger — Deferred (offline-lite) yadrosi uchun XAVFSIZ test.
 *
 * submitDeferredSettlement CF'idagi ledger kompozitsiyasini (postEntry +
 * assert(headroom) + accountExtras(blok) + onCommit) tekshiradi:
 *   1) topUp 100000 → float 100000, lastTopUpAmount 100000 → floor = -10000
 *   2) deferred 105000 → float -5000 (qarz, headroom ichida): BLOK, taymer,
 *        passenger_credit 105000, bonusBalance 105000, settlement 'completed'
 *   3) headroom: deferred yana 10000 (→ -15000 < -10000) → assert XATO, post yo'q
 *   4) idempotent deferred → ikkilanmaydi
 *   5) topUp 20000 → float 15000 (>=0) → BLOK yechiladi (taymer tozalanadi)
 *
 * Hammasi tozalanadi; reconcile OLDIN == KEYIN (net-zero).
 * Ishlatish: node tools/settlement_deferred_test.js
 */
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();
const ledger = require(path.join(__dirname, '..', 'settlement_ledger'));

const DRIVER = '998000000004';
const PASS = '998000000005';
const floatAcc = ledger.driverFloatAccount(DRIVER);
const pcAcc = ledger.passengerCreditAccount(PASS);

let pass = 0;
let fail = 0;
function check(name, cond) {
  if (cond) { pass++; console.log(`  ✓ ${name}`); } else { fail++; console.log(`  ✗ ${name}`); }
}

async function accountDoc(accId) {
  const s = await db.collection(ledger.COL_ACCOUNTS).doc(accId).get();
  return s.exists ? (s.data() || {}) : {};
}
async function balanceOf(accId) {
  return (await accountDoc(accId)).balance || 0;
}

async function topUp(opId, amount) {
  return ledger.postEntry(db, {
    idempotencyKey: `floatTopUp:${opId}`,
    kind: 'float_topup', refType: 'float_topup', refId: opId,
    postedBy: 'test', postedRole: 'system',
    legs: [{ account: 'admin_cash', dr: amount }, { account: floatAcc, cr: amount }],
  }, {
    mirrorBonus: false,
    meta: { test: true },
    accountExtras: (id, st) => {
      if (id !== floatAcc) return null;
      const cleared = st.next >= 0;
      return {
        lastTopUpAmount: amount,
        blocked: !cleared,
        ...(cleared ? { blockedReason: '', deferredTimeoutAt: null } : {}),
      };
    },
    onCommit: (tx, { balances }) => {
      tx.set(db.collection('users').doc(DRIVER),
          { settlementBlocked: (balances[floatAcc] || 0) < 0 }, { merge: true });
    },
  });
}

// submitDeferredSettlement CF'idagi ledger kompozitsiyasini takrorlaydi.
async function deferred(opId, amount, floor) {
  const sref = db.collection(ledger.COL_SETTLEMENTS).doc(opId);
  const timeoutAt = admin.firestore.Timestamp.fromMillis(Date.now() + 48 * 3600 * 1000);
  return ledger.postEntry(db, {
    idempotencyKey: `settle:${opId}`,
    kind: 'trip_settlement_deferred', refType: 'settlement', refId: opId,
    postedBy: DRIVER, postedRole: 'driver',
    legs: [{ account: floatAcc, dr: amount }, { account: pcAcc, cr: amount }],
  }, {
    mirrorBonus: true,
    walletLedgerType: 'settlement_credit',
    meta: { test: true, settlementId: opId, deferred: true },
    assert: ({ accounts }) => {
      const fa = accounts.get(floatAcc);
      if (fa && fa.next < floor) throw new Error('headroom exceeded');
    },
    accountExtras: (id, st) => {
      if (id !== floatAcc) return null;
      return st.next < 0
        ? { blocked: true, blockedReason: 'deferred_debt', deferredTimeoutAt: timeoutAt }
        : { blocked: false, blockedReason: '', deferredTimeoutAt: null };
    },
    onCommit: (tx, { entryId, balances }) => {
      const next = balances[floatAcc] || 0;
      tx.set(sref, {
        tripId: 'trip_test', driverUid: DRIVER, passengerUid: PASS,
        totalChange: amount, cashGiven: 0, settlementAmount: amount,
        state: 'completed', origin: 'deferred', attestedBy: 'driver',
        journalEntryId: entryId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      tx.set(db.collection('users').doc(DRIVER),
          { settlementBlocked: next < 0 }, { merge: true });
    },
  });
}

async function cleanup(adminCashBefore, passUserExisted, driverUserExisted) {
  const jids = [
    'floatTopUp:dt_1', 'floatTopUp:dt_2',
    'settle:dft_1', 'settle:dft_2',
  ];
  for (const id of jids) {
    await db.collection(ledger.COL_JOURNAL).doc(id).delete().catch(() => {});
  }
  for (const id of ['dft_1', 'dft_2']) {
    await db.collection(ledger.COL_SETTLEMENTS).doc(id).delete().catch(() => {});
  }
  for (const id of [floatAcc, pcAcc]) {
    await db.collection(ledger.COL_ACCOUNTS).doc(id).delete().catch(() => {});
  }
  // admin_cash: testdan oldingi holatga qaytaramiz (net-zero).
  if (adminCashBefore.existed) {
    await db.collection(ledger.COL_ACCOUNTS).doc('admin_cash').set({
      balance: adminCashBefore.balance,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  } else {
    await db.collection(ledger.COL_ACCOUNTS).doc('admin_cash').delete().catch(() => {});
  }
  if (!passUserExisted) {
    const wl = await db.collection('users').doc(PASS).collection('wallet_ledger').get();
    for (const d of wl.docs) await d.ref.delete().catch(() => {});
    await db.collection('users').doc(PASS).delete().catch(() => {});
  }
  if (!driverUserExisted) {
    await db.collection('users').doc(DRIVER).delete().catch(() => {});
  }
}

async function main() {
  console.log('=== Deferred (offline-lite) testi (self-cleaning) ===');
  const config = await ledger.getConfig(db);
  console.log(`config: ${JSON.stringify(config)}`);

  const before = await ledger.reconcile(db);
  const acSnap = await db.collection(ledger.COL_ACCOUNTS).doc('admin_cash').get();
  const adminCashBefore = { existed: acSnap.exists, balance: acSnap.exists ? (acSnap.data().balance || 0) : 0 };
  const passUserExisted = (await db.collection('users').doc(PASS).get()).exists;
  const driverUserExisted = (await db.collection('users').doc(DRIVER).get()).exists;

  try {
    // 1) topUp 100000 → lastTopUpAmount 100000 → floor -10000
    await topUp('dt_1', 100000);
    check('topUp → float 100000', (await balanceOf(floatAcc)) === 100000);
    const fa1 = await accountDoc(floatAcc);
    check('lastTopUpAmount 100000', fa1.lastTopUpAmount === 100000);
    check('blocked false (topUp)', fa1.blocked === false);
    const floor = ledger.deferredFloor(100000, config);
    check('deferredFloor = -10000', floor === -10000);

    // 2) deferred 105000 → float -5000 (qarz, headroom ichida)
    const r1 = await deferred('dft_1', 105000, floor);
    check('deferred → idempotent=false', r1.idempotent === false);
    check('float -5000 (qarz)', (await balanceOf(floatAcc)) === -5000);
    const fa2 = await accountDoc(floatAcc);
    check('blocked true', fa2.blocked === true);
    check('blockedReason deferred_debt', fa2.blockedReason === 'deferred_debt');
    check('deferredTimeoutAt yozildi', !!fa2.deferredTimeoutAt);
    check('passenger_credit 105000', (await balanceOf(pcAcc)) === 105000);

    const u = await db.collection('users').doc(PASS).get();
    check('bonusBalance 105000 (proeksiya)', ((u.data() || {}).bonusBalance || 0) === 105000);
    const du = await db.collection('users').doc(DRIVER).get();
    check('driver settlementBlocked true', (du.data() || {}).settlementBlocked === true);

    const s1 = await db.collection(ledger.COL_SETTLEMENTS).doc('dft_1').get();
    check('settlement completed', (s1.data() || {}).state === 'completed');
    check('settlement origin deferred', (s1.data() || {}).origin === 'deferred');

    const wl = await db.collection('users').doc(PASS).collection('wallet_ledger')
        .where('type', '==', 'settlement_credit').get();
    check('wallet_ledger settlement_credit 105000',
        wl.size === 1 && wl.docs[0].data().amount === 105000);

    // 3) headroom: yana 10000 (-15000 < -10000) → XATO
    let threw = false;
    try {
      await deferred('dft_2', 10000, floor);
    } catch (e) {
      threw = true;
    }
    check('headroom oshdi → assert XATO', threw);
    const noJ = await db.collection(ledger.COL_JOURNAL).doc('settle:dft_2').get();
    check('post yaratilmagan (atomar)', !noJ.exists);
    check('float hamon -5000', (await balanceOf(floatAcc)) === -5000);

    // 4) idempotent deferred
    const r2 = await deferred('dft_1', 105000, floor);
    check('qayta deferred → idempotent=true', r2.idempotent === true);
    check('float hamon -5000', (await balanceOf(floatAcc)) === -5000);

    // 5) topUp 20000 → float 15000 (>=0) → blok yechiladi
    await topUp('dt_2', 20000);
    check('topUp 20000 → float 15000', (await balanceOf(floatAcc)) === 15000);
    const fa3 = await accountDoc(floatAcc);
    check('blok yechildi (blocked false)', fa3.blocked === false);
    check('deferredTimeoutAt tozalandi', !fa3.deferredTimeoutAt);
    const du2 = await db.collection('users').doc(DRIVER).get();
    check('driver settlementBlocked false', (du2.data() || {}).settlementBlocked === false);
  } finally {
    await cleanup(adminCashBefore, passUserExisted, driverUserExisted);
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
