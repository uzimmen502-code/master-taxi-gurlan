/**
 * `tools/fix_wallet_8777_cancel_refund.js` — журналсиз бекор қайтимларини ledger'га ёзиш
 * (Firestore Emulator, ҲАҚИҚИЙ ledger).
 *
 *   firebase emulators:exec --only firestore --project demo-wallet-fix \
 *     "node functions/test/fix_wallet_cancel_refund.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-wallet-fix';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const admin = require('firebase-admin');
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const ledger = require('../settlement_ledger');
const tool = require('../tools/fix_wallet_8777_cancel_refund');

const U = '998900008777'; // 2 та журналсиз қайтим (17 000 + 2 562), ечимлар журналда
const OK = '998900000002'; // мос ҳамён
const BAD = '998900000003'; // фарқ қайтимлардан катта → needsReview

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const pc = (uid) => db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(uid));
const pcBal = async (uid) => { const s = await pc(uid).get(); return s.exists ? s.data().balance : 0; };
const bonus = async (uid) => (await db.collection('users').doc(uid).get()).data().bonusBalance;

async function topup(uid, amount, key) {
  await ledger.postEntry(db, {
    idempotencyKey: key, kind: 'test_topup',
    legs: [{ account: 'admin_clearing', dr: amount }, { account: ledger.passengerCreditAccount(uid), cr: amount }],
  }, { mirrorBonus: true });
}
/** Буюртма тўлови журнал билан (ечим), бекор қайтими эса ЖУРНАЛСИЗ (07-27 даги эски версия каби). */
async function orderPaidThenCancelledWithoutJournal(uid, orderId, amount) {
  await db.collection('orders').doc(orderId).set({ status: 'cancelled', balanceApplied: amount, userPhone: uid });
  await ledger.postEntry(db, {
    idempotencyKey: `bonus:order_wallet_${orderId}`, kind: 'order_wallet', refType: 'order', refId: orderId,
    legs: [{ account: ledger.passengerCreditAccount(uid), dr: amount }, { account: 'admin_clearing', cr: amount }],
  }, { mirrorBonus: true });
  await db.collection('users').doc(uid).update({ bonusBalance: admin.firestore.FieldValue.increment(amount) });
  const now = admin.firestore.FieldValue.serverTimestamp();
  await db.collection('users').doc(uid).collection('wallet_ledger').add({
    type: 'purchase_debit', amount: -amount, refType: 'order', refId: orderId, module: 'platform', createdAt: now,
  });
  await db.collection('users').doc(uid).collection('wallet_ledger').add({
    type: 'order_cancel_refund', amount, refType: 'order', refId: orderId, module: 'platform', createdAt: now,
  });
}
async function seed() {
  await clearEmulator();
  await db.collection('users').doc(U).set({ phone: U });
  await topup(U, 19562, `opening:${U}`);
  await orderPaidThenCancelledWithoutJournal(U, 'ord_Ix7u', 17000);
  await orderPaidThenCancelledWithoutJournal(U, 'ord_5xum', 2562);
  await db.collection('users').doc(OK).set({ phone: OK });
  await topup(OK, 5000, `opening:${OK}`);
  await db.collection('users').doc(BAD).set({ phone: BAD });
  await topup(BAD, 1000, `opening:${BAD}`);
  await orderPaidThenCancelledWithoutJournal(BAD, 'ord_bad', 1000);
  await db.collection('users').doc(BAD).update({ bonusBalance: admin.firestore.FieldValue.increment(500) });
}

(async () => {
  await seed();
  await check('F0 boshlang\'ich holat: U bonus 19562, ledger 0 (prod ***8777 bilan bir xil)', async () => {
    assert.strictEqual(await bonus(U), 19562);
    assert.strictEqual(await pcBal(U), 0);
  });

  await check('F1 dry-run reja: U fixable (2 qator), OK skip, BAD needsReview; hech narsa yozilmaydi', async () => {
    const before = (await db.collection(ledger.COL_JOURNAL).get()).size;
    const plan = await tool.planAll(db);
    const byUid = Object.fromEntries(plan.map((p) => [p.uid, p]));
    assert.strictEqual(byUid[U].status, 'fixable');
    assert.strictEqual(byUid[U].sumMissing, 19562);
    assert.deepStrictEqual(byUid[U].rows.map((r) => r.orderId).sort(), ['ord_5xum', 'ord_Ix7u']);
    assert.strictEqual(byUid[OK].status, 'skip');
    assert.strictEqual(byUid[BAD].status, 'needsReview');
    assert.strictEqual(byUid[BAD].reason, 'sum_ne_drift');
    assert.strictEqual((await db.collection(ledger.COL_JOURNAL).get()).size, before);
  });

  await check('F2 apply: U ledger 19562 ga tenglashadi, bonusBalance o\'zgarmaydi, jonli kalit ishlatiladi', async () => {
    const res = await tool.applyPlan(db, await tool.planAll(db));
    assert.strictEqual(res.posted.length, 2);
    assert.strictEqual(await pcBal(U), 19562);
    assert.strictEqual(await bonus(U), 19562);
    const j = await db.collection(ledger.COL_JOURNAL).doc('bonus:order_cancel_refund_ord_Ix7u').get();
    assert.ok(j.exists);
    assert.strictEqual(j.data().kind, 'order_cancel_refund');
    assert.deepStrictEqual(j.data().legs, [
      { account: 'admin_clearing', dr: 17000, cr: 0 }, { account: ledger.passengerCreditAccount(U), cr: 17000, dr: 0 },
    ].map((l) => (l.dr ? { account: l.account, dr: l.dr } : { account: l.account, cr: l.cr })));
    assert.strictEqual(j.data().meta.migration, tool.TAG);
    assert.strictEqual(await pcBal(BAD), 0, 'BAD ga tegilmaydi');
    const rep = await ledger.reconcile(db);
    assert.deepStrictEqual(rep.mismatches.map((m) => m.uid), [BAD]);
    assert.strictEqual(rep.balanced, true);
    assert.strictEqual(rep.identityOk, true);
  });

  await check('F3 qayta ishga tushirish: yangi yozuv yo\'q (idempotent / in_sync)', async () => {
    const n = (await db.collection(ledger.COL_JOURNAL).get()).size;
    const plan = await tool.planAll(db);
    assert.strictEqual(plan.find((p) => p.uid === U).status, 'skip');
    const res = await tool.applyPlan(db, plan);
    assert.strictEqual(res.posted.length, 0);
    assert.strictEqual((await db.collection(ledger.COL_JOURNAL).get()).size, n);
  });

  await check('F4 eski reja bilan qayta apply ham idempotent (jurnal kaliti bor)', async () => {
    await seed();
    const plan = await tool.planAll(db);
    await tool.applyPlan(db, plan);
    const res2 = await tool.applyPlan(db, plan);
    assert.strictEqual(res2.posted.length, 0);
    assert.strictEqual(res2.idempotent.length, 2);
    assert.strictEqual(await pcBal(U), 19562);
  });

  await check('F5 reja va yozish orasida bonusBalance o\'zgarsa — STALE, yozilmaydi', async () => {
    await seed();
    const plan = await tool.planAll(db);
    await db.collection('users').doc(U).update({ bonusBalance: 20000 });
    const res = await tool.applyPlan(db, plan);
    assert.strictEqual(res.posted.length, 0);
    assert.strictEqual(res.stale.length, 1);
    assert.strictEqual(await pcBal(U), 0);
  });

  await check('F6 rollback: storno, ledger 0 ga qaytadi, idempotent; bonusBalance tegilmaydi', async () => {
    await seed();
    await tool.applyPlan(db, await tool.planAll(db));
    const r1 = await tool.rollback(db);
    assert.strictEqual(r1.reversed, 2);
    assert.strictEqual(await pcBal(U), 0);
    assert.strictEqual(await bonus(U), 19562);
    const r2 = await tool.rollback(db);
    assert.strictEqual(r2.reversed, 0);
    assert.strictEqual(r2.idempotent, 2);
  });

  await check('F7 balanceApplied mos kelmasa — needsReview (row_check_failed)', async () => {
    await seed();
    await db.collection('orders').doc('ord_5xum').update({ balanceApplied: 2000 });
    const plan = await tool.planAll(db, { uid: U });
    assert.strictEqual(plan[0].status, 'needsReview');
    assert.strictEqual(plan[0].reason, 'row_check_failed');
    const res = await tool.applyPlan(db, plan);
    assert.strictEqual(res.posted.length, 0);
  });

  await check('F8 yozishdan keyingi tekshiruv: BAD qolsa — ok:false; BAD tuzatilsa — I-1/I-2/I-3 hammasi yashil', async () => {
    await seed();
    await tool.applyPlan(db, await tool.planAll(db));
    const quiet = console.log;
    console.log = () => {};
    let v1;
    let v2;
    try {
      v1 = await tool.verifyAfterApply(db);
      // BAD'даги қўшимча 500 олиб ташланса — фарқ айнан журналсиз қайтимга тенг бўлади ва восита уни ҳам ёпади.
      await db.collection('users').doc(BAD).update({ bonusBalance: admin.firestore.FieldValue.increment(-500) });
      const res = await tool.applyPlan(db, await tool.planAll(db));
      assert.strictEqual(res.posted.length, 1);
      v2 = await tool.verifyAfterApply(db);
    } finally { console.log = quiet; }
    assert.strictEqual(v1.ok, false);
    assert.deepStrictEqual(v1.report.invariants.I1.mismatches.map((m) => m.uid), [BAD]);
    assert.strictEqual(v2.ok, true, JSON.stringify(v2.report.invariants));
    assert.strictEqual(v2.report.invariants.I1.ok && v2.report.invariants.I2.ok && v2.report.invariants.I3.ok, true);
  });

  const passed = results.filter(Boolean).length;
  const failed = results.length - passed;
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
