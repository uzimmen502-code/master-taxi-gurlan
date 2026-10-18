/**
 * Telegram ҳамён боти — авто тасдиқ ўчирилган (ҳамён аудити 2026-10-07, K-2;
 * эга қарори 2026-10-08). ҲАҚИҚИЙ ledger билан (Firestore Emulator).
 *
 *   firebase emulators:exec --only firestore --project demo-wallet-audit \
 *     "node functions/test/wallet_bot_manual_cf.test.js"
 *
 * - `settings/wallet_bot`да `auto` ёзилиб қолган бўлса ҳам (rules ёки эски
 *   CF орқали) — ечиш админсиз БАЖАРИЛМАЙДИ, ўқилган созлама `manual`.
 * - `adminSetWalletBotSettings` `auto`ни рад этади; ҳар ўзгариш
 *   `admin_audit`га (карта рақамисиз) ёзилади.
 * - K-3 регрессияси: телефонсиз (аноним) сессия ечиш сўрови бера олмайди.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-wallet-audit';
process.env.FUNCTIONS_EMULATOR = 'true';

const fns = require('../index.js');
const admin = require('firebase-admin');
const db = admin.firestore();
const ledger = require('../settlement_ledger');

const USER = '998901000001';
const FINANCE = '998905000001';
const DISPATCHER = '998905000002';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const anonCtx = { auth: { uid: 'anon_1', token: { firebase: { sign_in_provider: 'anonymous' } } } };
const CARD = '8600123412341234';

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
async function reset() {
  await Promise.all(['users', 'settings', 'admin_audit', 'wallet_withdraw_requests',
    'wallet_topup_requests', ledger.COL_JOURNAL, ledger.COL_ACCOUNTS].map(wipe));
  await db.collection('users').doc(USER).set({ role: 'user', phone: USER, name: 'Test', bonusBalance: 100000 });
  // Ledger проекцияси мос (passenger_credit == bonusBalance) — акс ҳолда
  // эски авто йўл ledger текширувида йиқилиб, тест ҳеч нарсани исботламасди.
  await db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(USER))
      .set({ type: 'liability', ownerUid: USER, balance: 100000 });
  await db.collection('users').doc(FINANCE).set({ role: 'finance', phone: FINANCE });
  await db.collection('users').doc(DISPATCHER).set({ role: 'dispatcher', phone: DISPATCHER });
  // Эски ҳолат: production'да 2026-10-07 гача шундай эди.
  await db.doc('settings/wallet_bot').set({
    enabled: true, topUpApproveMode: 'auto', withdrawApproveMode: 'auto',
    withdrawAutoLimit: 50000, depositCardNumber: '8600000000000001',
  });
}
async function rejects(promise, code) {
  try {
    await promise;
  } catch (e) {
    assert.strictEqual(e.code, code, `kutilgan ${code}, keldi ${e.code}: ${e.message}`);
    return e;
  }
  throw new Error(`kutilgan ${code}, lekin muvaffaqiyatli bajarildi`);
}
const bal = async (uid) => (await db.collection('users').doc(uid).get()).data().bonusBalance || 0;

(async () => {
  await reset();
  await check('W1 saqlangan `auto` bo\'lsa ham yechish avtomatik BAJARILMAYDI — pending', async () => {
    const r = await fns.requestWalletWithdraw.run({
      phone: USER, amount: 20000, payoutCardNumber: CARD, payoutCardHolder: 'Test User',
    }, ctxOf(USER));
    assert.strictEqual(r.status, 'pending');
    assert.notStrictEqual(r.auto, true);
    assert.strictEqual(await bal(USER), 100000, 'hamyon o\'zgarmasligi kerak');
    assert.strictEqual((await db.collection(ledger.COL_JOURNAL).get()).size, 0);
    const req = (await db.collection('wallet_withdraw_requests').doc(r.requestId).get()).data();
    assert.strictEqual(req.status, 'pending');
  });

  await reset();
  await check('W2 o\'qilgan sozlama har doim manual (saqlangan auto e\'tiborsiz)', async () => {
    const r = await fns.adminGetWalletBotSettings.run({}, ctxOf(FINANCE));
    assert.strictEqual(r.settings.topUpApproveMode, 'manual');
    assert.strictEqual(r.settings.withdrawApproveMode, 'manual');
  });

  await reset();
  await check('W3 adminSetWalletBotSettings auto → invalid-argument, audit yozilmaydi', async () => {
    const e = await rejects(fns.adminSetWalletBotSettings.run(
        { topUpApproveMode: 'auto' }, ctxOf(FINANCE)), 'invalid-argument');
    assert.strictEqual((e.details || {}).errorCode, 'AUTO_MODE_DISABLED');
    await rejects(fns.adminSetWalletBotSettings.run(
        { withdrawApproveMode: 'AUTO' }, ctxOf(FINANCE)), 'invalid-argument');
    assert.strictEqual((await db.collection('admin_audit').get()).size, 0);
  });

  await reset();
  await check('W4 o\'zgarish admin_audit\'ga — kim, nima; karta raqami yozilmaydi', async () => {
    await fns.adminSetWalletBotSettings.run({
      enabled: false, topUpApproveMode: 'manual', withdrawApproveMode: 'manual',
      // Луна текширувидан ўтадиган намуна (2026-10-18: хато карта сақланмайди).
      depositCardNumber: '8600 0000 0000 0007',
    }, ctxOf(FINANCE));
    const s = (await db.doc('settings/wallet_bot').get()).data();
    assert.strictEqual(s.enabled, false);
    assert.strictEqual(s.topUpApproveMode, 'manual');
    assert.strictEqual(s.withdrawApproveMode, 'manual');
    assert.strictEqual(s.updatedBy, FINANCE);
    const audit = await db.collection('admin_audit').get();
    assert.strictEqual(audit.size, 1);
    const a = audit.docs[0].data();
    assert.strictEqual(a.kind, 'wallet_bot_settings');
    assert.strictEqual(a.actor, FINANCE);
    assert.deepStrictEqual(a.changed.enabled, { from: true, to: false });
    assert.deepStrictEqual(a.changed.depositCardNumber, { changed: true });
    assert.ok(!JSON.stringify(a).includes('8600000000000007'), 'karta raqami auditda bo\'lmasin');
  });

  await reset();
  await check('W5 o\'zgarishsiz saqlash → audit yozilmaydi', async () => {
    await fns.adminSetWalletBotSettings.run({ enabled: true }, ctxOf(FINANCE));
    assert.strictEqual((await db.collection('admin_audit').get()).size, 0);
  });

  await reset();
  await check('W6 dispatcher sozlamani o\'zgartira olmaydi', async () => {
    await rejects(fns.adminSetWalletBotSettings.run({ enabled: false }, ctxOf(DISPATCHER)),
        'permission-denied');
  });

  await reset();
  await check('W7 (K-3) anonim sessiya begona hamyondan yechish so\'rovi bera olmaydi', async () => {
    await rejects(fns.requestWalletWithdraw.run({
      phone: USER, amount: 20000, payoutCardNumber: CARD, payoutCardHolder: 'X',
    }, anonCtx), 'permission-denied');
    assert.strictEqual((await db.collection('wallet_withdraw_requests').get()).size, 0);
  });

  const passed = results.filter(Boolean).length;
  const failed = results.length - passed;
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
