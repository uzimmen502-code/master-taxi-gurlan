/**
 * `requestPayout` / `checkWithdrawalLimit` — W-2 (takrorlanishlar auditi 2026-11-28, ega 2026-11-28):
 * ikkalasi ham ENDPOINT_RETIRED stub (klient chaqirmaydi, 30 kun — 0 chaqiruv). Avvalgi O-17
 * (qurilma cheklovi) va O-5 (auth) tekshiruvlari o'rnida: HECH KIM (egasi, begona, finance,
 * autentsiz) payout arizasi yarata olmaydi va limit ma'lumotini ololmaydi. Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-wallet-audit \
 *     "node functions/test/payout_controls_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-wallet-audit';
process.env.FUNCTIONS_EMULATOR = 'true';

const fns = require('../index.js');
const admin = require('firebase-admin');
const db = admin.firestore();

const USER = '998901000001';
const OTHER = '998901000002';
const FIN = '998905000001';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });

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
async function reset(security) {
  await Promise.all(['users', 'payout_requests', 'wallet_idempotency', 'settings'].map(wipe));
  await db.collection('users').doc(USER).set({
    role: 'user', phone: USER, name: 'Ali Valiyev', birthDate: '1990-01-01', bonusBalance: 100000,
    ...(security ? { security } : {}),
  });
  await db.collection('users').doc(FIN).set({ role: 'finance', phone: FIN });
}
let seq = 0;
const req = (amount, ctx = ctxOf(USER)) => fns.requestPayout.run(
    { userPhone: USER, amount, idempotencyKey: `payout_t_${Date.now()}_${seq++}` }, ctx);
const limit = (data, ctx) => fns.checkWithdrawalLimit.run(data, ctx);
const retiredCode = async (p) => {
  try { await p; return 'ok'; } catch (e) { return `${e.code}/${(e.details || {}).code}`; }
};
const RETIRED = 'failed-precondition/ENDPOINT_RETIRED';

(async () => {
  await reset({ deviceTrustMode: 'limited', deviceTrustUntil: admin.firestore.Timestamp.fromMillis(Date.now() + 3600000) });
  await check('P1 qurilma cheklovi faol — requestPayout ENDPOINT_RETIRED, ariza yo\'q', async () => {
    assert.strictEqual(await retiredCode(req(10000)), RETIRED);
    assert.strictEqual((await db.collection('payout_requests').get()).size, 0);
  });

  await reset(null);
  await check('P2 cheklovsiz egasi ham — ENDPOINT_RETIRED, ariza yo\'q, balans o\'zgarmaydi', async () => {
    assert.strictEqual(await retiredCode(req(10000)), RETIRED);
    assert.strictEqual((await db.collection('payout_requests').get()).size, 0);
    assert.strictEqual((await db.collection('wallet_idempotency').get()).size, 0);
    assert.strictEqual((await db.collection('users').doc(USER).get()).data().bonusBalance, 100000);
  });

  await check('C1 checkWithdrawalLimit: autentsiz / begona / egasi / finance — hammasi ENDPOINT_RETIRED (limit chiqmaydi)', async () => {
    assert.strictEqual(await retiredCode(limit({ userId: USER, amount: 1000 }, {})), RETIRED);
    assert.strictEqual(await retiredCode(limit({ userId: USER, amount: 1000 }, ctxOf(OTHER))), RETIRED);
    assert.strictEqual(await retiredCode(limit({ userId: USER, amount: 1000 }, ctxOf(USER))), RETIRED);
    assert.strictEqual(await retiredCode(limit({ userId: USER, amount: 1000 }, ctxOf(FIN))), RETIRED);
  });

  const passed = results.filter(Boolean).length;
  const failed = results.length - passed;
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
