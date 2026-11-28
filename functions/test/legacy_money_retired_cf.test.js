/**
 * W-2 + 17-band (takrorlanishlar auditi 2026-11-28, ega 2026-11-28): ishlatilmaydigan eski endpointlar
 * manbadan OLIB TASHLANDI (export yo'q). Jonli nusxalarni egasi `firebase functions:delete` bilan o'chiradi.
 *   - pul: debitForOrder, requestPayout, checkWithdrawalLimit, placeOrderWithWallet, floatTopUp, floatReturn,
 *     driverFloatStatus;
 *   - admin/kirish: adminWebSignInWithCode, promoteToAdminWithPin, appendAdminSystemChat (= sendSupportChatReply);
 *   - bir martalik migratsiya: migrateCheapProductTitleLower, migratePhoneFormats.
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

const REMOVED = [
  'debitForOrder', 'requestPayout', 'checkWithdrawalLimit', 'placeOrderWithWallet', 'floatTopUp', 'floatReturn',
  'driverFloatStatus', 'adminWebSignInWithCode', 'promoteToAdminWithPin', 'appendAdminSystemChat',
  'migrateCheapProductTitleLower', 'migratePhoneFormats',
];
// O'rnini bosuvchi (jonli) yo'llar — tasodifan o'chib ketmasin.
const REPLACEMENTS = [
  'placeOrderPostPaid', 'requestWalletWithdraw', 'walletToCash', 'cashExchange', 'confirmPayout', 'rejectPayout',
  'sendSupportChatReply', 'adminWebSignIn', 'creditSupplier',
];

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

async function main() {
  await clearEmulator();
  await db.doc(`users/${VICTIM}`).set({ role: 'user', phone: VICTIM, bonusBalance: 200000, kycVerified: true });
  await db.doc(`users/${DISPATCHER}`).set({ role: 'dispatcher', phone: DISPATCHER, bonusBalance: 0 });
  await db.doc(`users/${ADMIN}`).set({ role: 'superadmin', phone: ADMIN, bonusBalance: 0 });

  await check(`R1 ${REMOVED.length} ta eski endpoint export qilinmaydi (deploy ularni qayta yaratmaydi)`, async () => {
    const still = REMOVED.filter((n) => Object.prototype.hasOwnProperty.call(fns, n));
    assert.deepStrictEqual(still, []);
  });

  await check('R2 o\'rnini bosuvchi jonli yo\'llar joyida (chegara: ortiqcha o\'chirilmadi)', async () => {
    const missing = REPLACEMENTS.filter((n) => typeof (fns[n] && fns[n].run) !== 'function');
    assert.deepStrictEqual(missing, []);
  });

  await check('E3 creditSupplier QOLDI (courier_payout qo\'lda yo\'li): dispatcher → permission-denied', async () => {
    await assert.rejects(fns.creditSupplier.run({ userPhone: VICTIM, amount: 5000, dateKey: '2026-11-28' }, ctxOf(DISPATCHER)),
      (e) => e.code === 'permission-denied');
    assert.strictEqual((await db.doc(`users/${VICTIM}`).get()).data().bonusBalance, 200000);
  });

  await check('E6 hech qanday pul/ariza yozuvi paydo bo\'lmadi', async () => {
    for (const c of ['payout_requests', 'wallet_idempotency', 'journal_entries', 'ledger_accounts']) {
      assert.strictEqual((await db.collection(c).get()).size, 0, c);
    }
    assert.strictEqual((await db.collection(`users/${VICTIM}/wallet_ledger`).get()).size, 0);
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}
main().catch((e) => { console.error(e); process.exit(1); });
