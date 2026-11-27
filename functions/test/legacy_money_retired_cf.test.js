/**
 * W-2 (takrorlanishlar auditi 2026-11-28, ega 2026-11-28): eski pul endpointlari —
 * debitForOrder, requestPayout, checkWithdrawalLimit — ENDPOINT_RETIRED stub.
 * Export'lar qoladi; hech qanday pul/ledger/ariza yozuvi yo'q (dispatcher ham, egasi ham).
 * creditSupplier (admin) — QOLDI: courier_payout.js qo'lda to'lov yo'li (courier_payout_cf).
 *
 *   firebase emulators:exec --only firestore --project demo-legacy-money "node test/legacy_money_retired_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-legacy-money';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');

const db = admin.firestore();
const VICTIM = '998917200001';
const DISPATCHER = '998917200002';
const ADMIN = '998917200003';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const isRetired = (name) => (e) => {
  assert.strictEqual(e.code, 'failed-precondition');
  assert.strictEqual(e.details.code, 'ENDPOINT_RETIRED');
  assert.strictEqual(e.details.endpoint, name);
  for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) assert.ok(e.details.messages[l], l);
  return true;
};
const size = async (col) => (await db.collection(col).get()).size;

async function main() {
  await clearEmulator();
  await db.doc(`users/${VICTIM}`).set({ role: 'user', phone: VICTIM, bonusBalance: 200000, kycVerified: true });
  await db.doc(`users/${DISPATCHER}`).set({ role: 'dispatcher', phone: DISPATCHER, bonusBalance: 0 });
  await db.doc(`users/${ADMIN}`).set({ role: 'superadmin', phone: ADMIN, bonusBalance: 0 });

  await check('E1 dispatcher boshqaning hamyonidan debitForOrder → ENDPOINT_RETIRED, balans o\'zgarmaydi', async () => {
    await assert.rejects(fns.debitForOrder.run({
      userPhone: VICTIM, amount: 150000, idempotencyKey: 'w2-e1', refType: 'order', refId: 'x',
    }, ctxOf(DISPATCHER)), isRetired('debitForOrder'));
    assert.strictEqual((await db.doc(`users/${VICTIM}`).get()).data().bonusBalance, 200000);
  });

  await check('E2 egasi o\'z hamyonidan debitForOrder ham → ENDPOINT_RETIRED', async () => {
    await assert.rejects(fns.debitForOrder.run({ userPhone: VICTIM, amount: 1, idempotencyKey: 'w2-e2' }, ctxOf(VICTIM)),
      isRetired('debitForOrder'));
  });

  await check('E3 creditSupplier QOLDI (courier_payout qo\'lda yo\'li): dispatcher → permission-denied; stub EMAS', async () => {
    await assert.rejects(fns.creditSupplier.run({ userPhone: VICTIM, amount: 5000, dateKey: '2026-11-28' }, ctxOf(DISPATCHER)),
      (e) => e.code === 'permission-denied');
    assert.strictEqual((await db.doc(`users/${VICTIM}`).get()).data().bonusBalance, 200000);
  });

  await check('E4 requestPayout → ENDPOINT_RETIRED, payout_requests yozilmaydi', async () => {
    await assert.rejects(fns.requestPayout.run({ userPhone: VICTIM, amount: 1000, idempotencyKey: 'w2-e4' }, ctxOf(VICTIM)),
      isRetired('requestPayout'));
  });

  await check('E5 checkWithdrawalLimit → ENDPOINT_RETIRED (limit ma\'lumoti chiqmaydi)', async () => {
    await assert.rejects(fns.checkWithdrawalLimit.run({ userId: VICTIM, amount: 1000 }, ctxOf(VICTIM)),
      isRetired('checkWithdrawalLimit'));
  });

  await check('E6 autentifikatsiyasiz ham bir xil stub (chegara), hech qanday yozuv yo\'q', async () => {
    for (const n of ['debitForOrder', 'requestPayout', 'checkWithdrawalLimit']) {
      await assert.rejects(fns[n].run({ userPhone: VICTIM, amount: 1, idempotencyKey: `w2-e6-${n}` }, {}), isRetired(n));
    }
    for (const c of ['payout_requests', 'wallet_idempotency', 'journal_entries', 'ledger_accounts']) {
      assert.strictEqual(await size(c), 0, c);
    }
    assert.strictEqual((await db.collection(`users/${VICTIM}/wallet_ledger`).get()).size, 0);
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}
main().catch((e) => { console.error(e); process.exit(1); });
