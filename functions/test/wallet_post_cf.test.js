/**
 * `settlement_ledger.walletPost` — ҳамён ягона ёзиш йўли (Firestore Emulator).
 *
 *   firebase emulators:exec --only firestore --project demo-wallet-post \
 *     "node functions/test/wallet_post_cf.test.js"
 *
 * Қулфланади: учала омбор битта транзакцияда (журнал + ҳисоб, bonusBalance, wallet_ledger детерминистик id),
 * qayta chaqiruv hech narsa yozmaydi, ҳамёндан ҳамёнга (counterparty), мутлақ nextBalance, update режими,
 * selfMirror:false + mirrorWalletInTx йиғма, ҳамма амалдан кейин I-1/I-2/I-3/I-3F яшил.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-wallet-post';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const admin = require('firebase-admin');
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const L = require('../settlement_ledger');
const inv = require('../wallet_invariants');

const A = '998950000001';
const B = '998950000002';
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
const user = async (u) => (await db.collection('users').doc(u).get()).data() || {};
const pc = async (u) => ((await db.collection(L.COL_ACCOUNTS).doc(L.passengerCreditAccount(u)).get()).data() || {}).balance || 0;
const rows = async (u) => (await db.collection('users').doc(u).collection('wallet_ledger').get()).docs;
const post = (uid, key, opts, prepOpts = {}) => db.runTransaction(async (t) => {
  const ctx = await L.prepareWalletPost(t, db, uid, { idempotencyKey: key, ...prepOpts });
  return L.walletPost(t, ctx, opts);
});

(async () => {
  await clearEmulator();
  await db.collection('users').doc(A).set({ phone: A });
  await db.collection('users').doc(B).set({ phone: B });

  await check('P1 kredit: jurnal + hisob + bonusBalance + wallet_ledger (deterministik id), bir tranzaksiya', async () => {
    const r = await post(A, 'k1', {
      delta: 10000, kind: 'test_credit', refType: 'order', refId: 'o1', walletLedgerType: 'change_accrued',
      walletLedger: { module: 'bread', refType: 'order', refId: 'o1', meta: { x: 1 }, createdBy: 'server' },
    });
    assert.deepStrictEqual([r.applied, r.pcBalance], [true, 10000]);
    assert.strictEqual((await user(A)).bonusBalance, 10000);
    assert.ok((await user(A)).balanceUpdatedAt);
    assert.strictEqual(await pc(A), 10000);
    const j = (await db.collection(L.COL_JOURNAL).doc('bonus:k1').get()).data();
    assert.strictEqual(j.kind, 'test_credit');
    const w = (await db.collection('users').doc(A).collection('wallet_ledger').doc('wl_k1').get()).data();
    assert.strictEqual(w.type, 'change_accrued');
    assert.strictEqual(w.amount, 10000);
    assert.strictEqual(w.module, 'bread');
    assert.deepStrictEqual(w.meta, { x: 1 });
    assert.ok(w.createdAt);
  });

  await check('P2 qayta chaqiruv (jurnal bor) — HECH NARSA yozilmaydi', async () => {
    const r = await post(A, 'k1', { delta: 10000, kind: 'test_credit', walletLedgerType: 'change_accrued' });
    assert.deepStrictEqual([r.applied, r.idempotent], [false, true]);
    assert.strictEqual((await user(A)).bonusBalance, 10000);
    assert.strictEqual((await rows(A)).length, 1);
  });

  await check('P3 yechim + walletAmount (realty: musbat + debitCredit debit), update rejimi, balanceUpdatedAt yo\'q', async () => {
    await db.collection('users').doc(A).update({ balanceUpdatedAt: admin.firestore.FieldValue.delete() });
    await post(A, 'k2', {
      delta: -2000, kind: 'realty_tier_purchase', walletLedgerType: 'realty_tier_purchase', walletAmount: 2000,
      walletLedger: { debitCredit: 'debit', note: 'n' }, userWrite: 'update', balanceUpdatedAt: false,
    });
    const u = await user(A);
    assert.strictEqual(u.bonusBalance, 8000);
    assert.strictEqual(u.balanceUpdatedAt, undefined);
    const w = (await db.collection('users').doc(A).collection('wallet_ledger').doc('wl_k2').get()).data();
    assert.deepStrictEqual([w.amount, w.debitCredit], [2000, 'debit']);
  });

  await check('P4 nextBalance (mutlaq) va o\'z walletLedgerId', async () => {
    await post(A, 'k3', { delta: -500, kind: 'x', nextBalance: 7500, walletLedgerType: 'purchase_debit', walletLedgerId: 'insurance_pay_r1' });
    assert.strictEqual((await user(A)).bonusBalance, 7500);
    assert.ok((await db.collection('users').doc(A).collection('wallet_ledger').doc('insurance_pay_r1').get()).exists);
  });

  await check('P5 hamyondan hamyonga (counterparty): A −1000, B +1000, ikkala tarix', async () => {
    await post(A, 'k4', {
      delta: -1000, kind: 'restaurant_delivery_fee', walletLedgerType: 'restaurant_delivery_debit',
      counterparty: { walletLedgerType: 'restaurant_delivery_credit', walletLedger: { module: 'restaurant' } },
    }, { fundingAccount: L.passengerCreditAccount(B) });
    assert.strictEqual((await user(A)).bonusBalance, 6500);
    assert.strictEqual((await user(B)).bonusBalance, 1000);
    assert.strictEqual(await pc(B), 1000);
    const wb = (await db.collection('users').doc(B).collection('wallet_ledger').doc('wl_k4:cp').get()).data();
    assert.deepStrictEqual([wb.type, wb.amount, wb.module], ['restaurant_delivery_credit', 1000, 'restaurant']);
  });

  await check('P6 selfMirror:false + mirrorWalletInTx yig\'ma (split)', async () => {
    await db.runTransaction(async (t) => {
      const c1 = await L.prepareWalletPost(t, db, A, { idempotencyKey: 's1', fundingAccount: L.passengerCreditAccount(B) });
      const c2 = await L.prepareWalletPost(t, db, A, { idempotencyKey: 's2', fundingAccount: L.passengerCreditAccount(B) });
      // Бир транзакцияда бир ҳисоб икки марта: commitBonusInTx мутлақ баланс ёзади — кейинги ctx олдингисидан
      // кейинги қолдиқ билан берилади (restaurant_orders split'даги каби). Акс ҳолда I-2 ушлайди (текширилган).
      c2.pcPrev = c1.pcPrev - 300;
      c2.fundPrev = c1.fundPrev + 300;
      L.walletPost(t, c1, { delta: -300, kind: 'share', selfMirror: false, counterparty: { walletLedgerType: 'cr' } });
      L.walletPost(t, c2, { delta: -200, kind: 'share', selfMirror: false, counterparty: { walletLedgerType: 'cr', walletLedgerId: 'cr2' } });
      L.mirrorWalletInTx(t, db, { uid: A, delta: -500, walletLedgerType: 'restaurant_delivery_debit', walletLedgerId: 'agg', walletLedger: { meta: { split: 2 } } });
    });
    assert.strictEqual((await user(A)).bonusBalance, 6000);
    assert.strictEqual(await pc(A), 6000);
    assert.strictEqual((await user(B)).bonusBalance, 1500);
  });

  await check('P7 xato kirish: delta 0 / kind yo\'q / counterparty funding\'siz — rad, hech narsa yozilmaydi', async () => {
    await assert.rejects(post(A, 'z1', { delta: 0, kind: 'x' }));
    await assert.rejects(post(A, 'z2', { delta: 5 }));
    await assert.rejects(post(A, 'z3', { delta: -5, kind: 'x', counterparty: {} }));
    assert.strictEqual((await db.collection(L.COL_JOURNAL).doc('bonus:z3').get()).exists, false);
    assert.strictEqual((await user(A)).bonusBalance, 6000);
  });

  await check('P8 barcha amallardan keyin invariantlar yashil (I-1/I-2/I-3/I-3F)', async () => {
    const r = inv.evaluate(await inv.collectState(db));
    assert.strictEqual(r.ok, true, JSON.stringify(r.invariants));
  });

  const passed = results.filter(Boolean).length;
  const failed = results.length - passed;
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
