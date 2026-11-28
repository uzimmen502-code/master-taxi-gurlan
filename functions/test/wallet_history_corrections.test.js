/**
 * `tools/wallet_history_corrections.js` — I-3F тарих тузатиши (тарих ўчирилмайди, битта тузатувчи ёзув).
 *
 *   firebase emulators:exec --only firestore --project demo-wallet-history \
 *     "node functions/test/wallet_history_corrections.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-wallet-history';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const admin = require('firebase-admin');
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const ledger = require('../settlement_ledger');
const inv = require('../wallet_invariants');
const tool = require('../tools/wallet_history_corrections');

const A = '998940008777'; // базагача Σ 23 672, opening 22 172 (−1 500)
const B = '998940003355'; // тест «қайтим» 100 000 000, кейин тарихсиз камайтирилган
const C = '998940000003'; // мос
const PRE = admin.firestore.Timestamp.fromDate(new Date('2026-05-12T10:00:00Z'));

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
const wl = (uid) => db.collection('users').doc(uid).collection('wallet_ledger');
async function walletWithOpening(uid, preRows, opening) {
  await db.collection('users').doc(uid).set({ phone: uid, bonusBalance: opening });
  for (const a of preRows) await wl(uid).add({ type: 'change_accrued', amount: a, createdAt: PRE });
  await ledger.postEntry(db, {
    idempotencyKey: `opening:${uid}`, kind: 'opening_balance',
    legs: [{ account: 'admin_clearing', dr: opening }, { account: ledger.passengerCreditAccount(uid), cr: opening }],
  }, { mirrorBonus: false });
}
async function seed() {
  await clearEmulator();
  await walletWithOpening(A, [20000, 3672], 22172);
  await walletWithOpening(B, [100000000, 6475], 6475);
  await walletWithOpening(C, [5000], 5000);
}
const evalNow = async () => inv.evaluate(await inv.collectState(db));

(async () => {
  await seed();
  await check('H1 dry-run: A −1 500, B −100 000 000; C yo\'q; hech narsa yozilmaydi', async () => {
    const before = (await wl(A).get()).size;
    const plan = await tool.planCorrections(db);
    const m = Object.fromEntries(plan.map((p) => [p.uid, p]));
    assert.strictEqual(m[A].status, 'fixable');
    assert.strictEqual(m[A].amount, -1500);
    assert.strictEqual(m[A].opening, 22172);
    assert.strictEqual(m[B].amount, -100000000);
    assert.strictEqual(m[C], undefined);
    assert.strictEqual((await wl(A).get()).size, before);
  });

  await check('H2 apply: I-3F yashil, I-1/I-3 o\'zgarmaydi, bonusBalance/jurnal tegilmaydi, eski qatorlar o\'chmaydi', async () => {
    const jBefore = (await db.collection(ledger.COL_JOURNAL).get()).size;
    const res = await tool.applyCorrections(db, await tool.planCorrections(db));
    assert.strictEqual(res.written.length, 2);
    const r = await evalNow();
    assert.strictEqual(r.ok, true, JSON.stringify(r.invariants));
    assert.strictEqual((await db.collection(ledger.COL_JOURNAL).get()).size, jBefore);
    assert.strictEqual((await db.collection('users').doc(A).get()).data().bonusBalance, 22172);
    assert.strictEqual((await wl(B).get()).size, 3, '2 eski + 1 tuzatish');
    const c = (await wl(A).doc(tool.DOC_ID).get()).data();
    assert.strictEqual(c.type, 'admin_adjust');
    assert.strictEqual(c.correction, true);
    assert.strictEqual(c.meta.kind, 'pre_ledger_adjustment');
    assert.ok(c.createdAt.toMillis() < inv.BASELINE_MS);
    assert.ok(c.recordedAt.toMillis() > inv.BASELINE_MS);
  });

  await check('H3 qayta ishga tushirish: reja bo\'sh, yozuv yo\'q', async () => {
    const plan = await tool.planCorrections(db);
    assert.strictEqual(plan.length, 0);
  });

  await seed();
  await check('H4 reja va yozish orasida tarix o\'zgarsa — STALE', async () => {
    const plan = await tool.planCorrections(db);
    await wl(A).add({ type: 'x', amount: 1, createdAt: PRE });
    const res = await tool.applyCorrections(db, plan);
    assert.deepStrictEqual(res.stale, [A]);
    assert.strictEqual((await wl(A).doc(tool.DOC_ID).get()).exists, false);
  });

  await seed();
  await check('H5 rollback: o\'chirmaydi — teskari yozuv qo\'shadi, idempotent', async () => {
    await tool.applyCorrections(db, await tool.planCorrections(db));
    const r1 = await tool.rollbackCorrections(db, [A, B, C]);
    assert.deepStrictEqual(r1, { reversed: 2, idempotent: 0, missing: 1 });
    assert.ok((await wl(A).doc(tool.DOC_ID).get()).exists);
    assert.strictEqual((await wl(A).doc(tool.REVERSAL_ID).get()).data().amount, 1500);
    const r2 = await tool.rollbackCorrections(db, [A, B]);
    assert.strictEqual(r2.idempotent, 2);
    assert.strictEqual((await evalNow()).invariants.I3F.mismatchCount, 2);
  });

  await seed();
  await check('H6 I-3 qizil hamyon — needsReview, yozilmaydi', async () => {
    await db.collection('users').doc(A).update({ bonusBalance: 22000 });
    const plan = await tool.planCorrections(db);
    assert.strictEqual(plan.find((p) => p.uid === A).status, 'needsReview');
    const res = await tool.applyCorrections(db, plan);
    assert.ok(!res.written.includes(A));
  });

  const passed = results.filter(Boolean).length;
  const failed = results.length - passed;
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
