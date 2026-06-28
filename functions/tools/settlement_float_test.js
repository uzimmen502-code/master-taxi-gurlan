/**
 * Settlement Ledger — Float yadrosi uchun XAVFSIZ (self-cleaning) test.
 *
 * Soxta test haydovchi (998000000001) ustida:
 *   1) floatTopUp 200000  → driver_float +200000, zona 'healthy'
 *   2) cap: topUp 400000  → assert XATO (600000 > floatMax) — yozuv yaratilmaydi
 *   3) manfiylik: return 250000 → assert XATO (-50000 < 0)
 *   4) floatReturn 200000 → driver_float 0 (net-zero)
 *   5) BARCHA test hujjatlarini o'chiradi (journal + ledger_accounts)
 *
 * Oxirida reconcile OLDIN == reconcile KEYIN (ledger holati o'zgarmaydi).
 * Bu PRODUCTION DB'ga yozadi, lekin to'liq tozalanadi va net-zero tekshiriladi.
 *
 * Ishlatish: node tools/settlement_float_test.js
 */
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();
const ledger = require(path.join(__dirname, '..', 'settlement_ledger'));

const DRIVER = '998000000001';
const floatAcc = ledger.driverFloatAccount(DRIVER);

let pass = 0;
let fail = 0;
function check(name, cond) {
  if (cond) {
    pass++;
    console.log(`  ✓ ${name}`);
  } else {
    fail++;
    console.log(`  ✗ ${name}`);
  }
}

async function topUp(opId, amount, config) {
  return ledger.postEntry(db, {
    idempotencyKey: `floatTopUp:${opId}`,
    kind: 'float_topup', refType: 'float_topup', refId: opId,
    postedBy: 'test', postedRole: 'system',
    legs: [
      { account: 'admin_cash', dr: amount },
      { account: floatAcc, cr: amount },
    ],
  }, {
    mirrorBonus: false,
    meta: { test: true, driverUid: DRIVER },
    assert: ({ accounts }) => {
      const fa = accounts.get(floatAcc);
      if (fa && fa.next > config.floatMax) {
        throw new Error(`cap (${config.floatMax})`);
      }
    },
  });
}

async function returnFloat(opId, amount) {
  return ledger.postEntry(db, {
    idempotencyKey: `floatReturn:${opId}`,
    kind: 'float_return', refType: 'float_return', refId: opId,
    postedBy: 'test', postedRole: 'system',
    legs: [
      { account: floatAcc, dr: amount },
      { account: 'admin_cash', cr: amount },
    ],
  }, {
    mirrorBonus: false,
    meta: { test: true, driverUid: DRIVER },
    assert: ({ accounts }) => {
      const fa = accounts.get(floatAcc);
      if (fa && fa.next < 0) throw new Error('insufficient float');
    },
  });
}

async function floatBalance() {
  const s = await db.collection(ledger.COL_ACCOUNTS).doc(floatAcc).get();
  return s.exists ? (s.data().balance || 0) : 0;
}

async function cleanup(adminCashExistedBefore) {
  const ids = [
    'floatTopUp:test_t1', 'floatTopUp:test_t2',
    'floatReturn:test_r1', 'floatReturn:test_r2',
  ];
  for (const id of ids) {
    await db.collection(ledger.COL_JOURNAL).doc(id).delete().catch(() => {});
  }
  await db.collection(ledger.COL_ACCOUNTS).doc(floatAcc).delete().catch(() => {});
  // admin_cash net-zero bo'lsa va test yaratgan bo'lsa — o'chiramiz.
  if (!adminCashExistedBefore) {
    const ac = await db.collection(ledger.COL_ACCOUNTS).doc('admin_cash').get();
    if (ac.exists && (ac.data().balance || 0) === 0) {
      await db.collection(ledger.COL_ACCOUNTS).doc('admin_cash').delete().catch(() => {});
    }
  }
}

async function main() {
  console.log('=== Float yadrosi testi (self-cleaning) ===');
  const config = await ledger.getConfig(db);
  console.log(`config: ${JSON.stringify(config)}`);

  const before = await ledger.reconcile(db);
  const adminCashBefore = await db.collection(ledger.COL_ACCOUNTS)
      .doc('admin_cash').get();
  const adminCashExisted = adminCashBefore.exists;

  try {
    // 1) topUp 200000
    await topUp('test_t1', 200000, config);
    let bal = await floatBalance();
    check('topUp 200000 → balance 200000', bal === 200000);
    check('zona healthy', ledger.floatZone(bal, config) === 'healthy');
    check('settlementEnabled', ledger.settlementEnabled(bal, config) === true);

    // 2) cap: topUp 400000 (200000+400000 > 500000) → XATO
    let capThrew = false;
    try {
      await topUp('test_t2', 400000, config);
    } catch (e) {
      capThrew = true;
    }
    check('cap topUp 400000 → assert XATO', capThrew);
    const capDoc = await db.collection(ledger.COL_JOURNAL)
        .doc('floatTopUp:test_t2').get();
    check('cap → yozuv yaratilmagan (atomar)', !capDoc.exists);
    bal = await floatBalance();
    check('cap → balance hamon 200000', bal === 200000);

    // 3) manfiylik: return 250000 → XATO
    let negThrew = false;
    try {
      await returnFloat('test_r1', 250000);
    } catch (e) {
      negThrew = true;
    }
    check('return 250000 → assert XATO (manfiylik)', negThrew);
    bal = await floatBalance();
    check('manfiylik → balance hamon 200000', bal === 200000);

    // 4) return 200000 → 0 (net-zero)
    await returnFloat('test_r2', 200000);
    bal = await floatBalance();
    check('return 200000 → balance 0', bal === 0);
    check('zona critical (0)', ledger.floatZone(bal, config) === 'critical');
    check('settlementEnabled false (0)', ledger.settlementEnabled(bal, config) === false);
  } finally {
    await cleanup(adminCashExisted);
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

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
