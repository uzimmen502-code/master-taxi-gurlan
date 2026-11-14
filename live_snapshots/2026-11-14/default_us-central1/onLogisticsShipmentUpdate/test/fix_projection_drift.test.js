/**
 * `tools/fix_wallet_projection_drift.js` — Y-1 тарихий дрейф тузатиш воситаси
 * (Firestore Emulator, ҲАҚИҚИЙ ledger).
 *
 *   firebase emulators:exec --only firestore --project demo-wallet-audit \
 *     "node functions/test/fix_projection_drift.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-wallet-audit';

const admin = require('firebase-admin');
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const ledger = require('../settlement_ledger');
const tool = require('../tools/fix_wallet_projection_drift');

const U1 = '998901000001'; // ledger'сиз харид: ledger 100k, bonus 70k → тузатилади
const U2 = '998901000002'; // мос
const U3 = '998901000003'; // ledger < bonus → тузатилмайди
const U4 = '998901000004'; // users ҳужжати йўқ
const U5 = '998901000005'; // ledger ҳисоби йўқ

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => d.ref.delete()));
}
const acc = (uid) => db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(uid));
async function reset() {
  await Promise.all(['users', ledger.COL_JOURNAL, ledger.COL_ACCOUNTS].map(wipe));
  const users = { [U1]: 70000, [U2]: 50000, [U3]: 90000, [U5]: 10000 };
  for (const [uid, b] of Object.entries(users)) {
    await db.collection('users').doc(uid).set({ phone: uid, bonusBalance: b });
  }
  const pcs = { [U1]: 100000, [U2]: 50000, [U3]: 60000, [U4]: 20000 };
  for (const [uid, b] of Object.entries(pcs)) {
    await acc(uid).set({ type: 'liability', ownerUid: uid, balance: b });
  }
}
const pcBal = async (uid) => ((await acc(uid).get()).data() || {}).balance;
const bonus = async (uid) => (await db.collection('users').doc(uid).get()).data().bonusBalance;
async function journalBalanced() {
  const s = await db.collection(ledger.COL_JOURNAL).get();
  for (const d of s.docs) {
    const legs = d.data().legs || [];
    const dr = legs.reduce((a, l) => a + (l.dr || 0), 0);
    const cr = legs.reduce((a, l) => a + (l.cr || 0), 0);
    assert.strictEqual(dr, cr, `journal ${d.id}`);
  }
  return s.size;
}

(async () => {
  await reset();
  await check('D1 reja: faqat U1 tuzatiladi; U3/U4/U5 hisobotda', async () => {
    const p = await tool.planDrift(db);
    assert.deepStrictEqual(p.fixable.map((r) => [r.uid, r.diff]), [[U1, 30000]]);
    assert.deepStrictEqual(p.untrackedCredit.map((r) => r.uid), [U3]);
    assert.deepStrictEqual(p.invalid.map((r) => [r.uid, r.reason]), [[U4, 'no_user_doc']]);
    assert.deepStrictEqual(p.noAccount.map((r) => r.uid), [U5]);
  });

  await reset();
  await check('D2 dry-run (faqat reja) hech narsa yozmaydi', async () => {
    await tool.planDrift(db);
    assert.strictEqual(await journalBalanced(), 0);
    assert.strictEqual(await pcBal(U1), 100000);
  });

  await reset();
  await check('D3 apply: U1 ledger → bonusBalance, bonusBalance o\'zgarmaydi, boshqalarga tegilmaydi', async () => {
    const res = await tool.applyPlan(db, await tool.planDrift(db));
    assert.strictEqual(res.posted.length, 1);
    assert.strictEqual(await pcBal(U1), 70000);
    assert.strictEqual(await bonus(U1), 70000);
    assert.strictEqual(await pcBal(U3), 60000);
    assert.strictEqual(await bonus(U3), 90000);
    assert.strictEqual(await journalBalanced(), 1);
  });

  await reset();
  await check('D4 qayta ishga tushirish idempotent — yangi yozuv yo\'q', async () => {
    const plan = await tool.planDrift(db);
    await tool.applyPlan(db, plan);
    const res2 = await tool.applyPlan(db, plan);
    assert.strictEqual(res2.posted.length, 0);
    assert.strictEqual(res2.idempotent.length, 1);
    assert.strictEqual(await pcBal(U1), 70000);
    assert.strictEqual(await journalBalanced(), 1);
  });

  await reset();
  await check('D5 reja va yozish orasida balans o\'zgarsa — STALE, yozilmaydi', async () => {
    const plan = await tool.planDrift(db);
    await db.collection('users').doc(U1).update({ bonusBalance: 60000 });
    const res = await tool.applyPlan(db, plan);
    assert.strictEqual(res.stale.length, 1);
    assert.strictEqual(res.posted.length, 0);
    assert.strictEqual(await pcBal(U1), 100000);
    assert.strictEqual(await journalBalanced(), 0);
  });

  await reset();
  await check('D6 rollback (storno) qaytaradi va idempotent', async () => {
    await tool.applyPlan(db, await tool.planDrift(db));
    const r1 = await tool.rollback(db);
    assert.strictEqual(r1.reversed, 1);
    assert.strictEqual(await pcBal(U1), 100000);
    const r2 = await tool.rollback(db);
    assert.strictEqual(r2.reversed, 0);
    assert.strictEqual(await journalBalanced(), 2);
  });

  await reset();
  await check('D7 tuzatishdan keyin reconcile: faqat U3 (va hisobsiz U4) qoladi', async () => {
    await tool.applyPlan(db, await tool.planDrift(db));
    const rep = await ledger.reconcile(db);
    const mm = rep.mismatches.map((m) => m.uid).sort();
    assert.deepStrictEqual(mm, [U3, U4].sort());
    assert.strictEqual(rep.balanced, true);
  });

  const passed = results.filter(Boolean).length;
  const failed = results.length - passed;
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
