/**
 * `requestPayout` — qurilma ko'chirilgandan keyingi 24 soatlik cheklov
 * (hamyon auditi O-17). Avval Telegram yechish tekshirardi, ilova payout'i
 * esa tekshirmasdi. Firestore Emulator, Admin SDK.
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
}
let seq = 0;
const req = (amount) => fns.requestPayout.run(
    { userPhone: USER, amount, idempotencyKey: `payout_t_${Date.now()}_${seq++}` }, ctxOf(USER));

(async () => {
  await reset({ deviceTrustMode: 'limited', deviceTrustUntil: admin.firestore.Timestamp.fromMillis(Date.now() + 3600000) });
  await check('P1 qurilma cheklovi faol — payout so\'rovi rad (device_trust_limited)', async () => {
    try {
      await req(10000);
      throw new Error('muvaffaqiyatli bajarildi');
    } catch (e) {
      assert.strictEqual(e.code, 'failed-precondition', e.message);
      assert.strictEqual((e.details || {}).code, 'device_trust_limited');
    }
    assert.strictEqual((await db.collection('payout_requests').get()).size, 0);
  });

  await reset({ deviceTrustMode: 'limited', deviceTrustUntil: admin.firestore.Timestamp.fromMillis(Date.now() - 1000) });
  await check('P2 cheklov muddati o\'tgan — payout so\'rovi yaratiladi', async () => {
    const r = await req(10000);
    assert.strictEqual(r.ok, true);
    assert.strictEqual((await db.collection('payout_requests').get()).size, 1);
  });

  await reset(null);
  await check('P3 cheklov yo\'q — oddiy oqim ishlaydi', async () => {
    const r = await req(10000);
    assert.strictEqual(r.ok, true);
  });

  // ─── O-5: checkWithdrawalLimit ──────────────────────────────────────
  const OTHER = '998901000002';
  const FIN = '998905000001';
  const limit = (data, ctx) => fns.checkWithdrawalLimit.run(data, ctx);
  const codeOf = async (p) => { try { await p; return 'ok'; } catch (e) { return e.code; } };
  await reset(null);
  await db.collection('users').doc(FIN).set({ role: 'finance', phone: FIN });
  await check('C1 autentifikatsiyasiz — unauthenticated', async () => {
    assert.strictEqual(await codeOf(limit({ userId: USER, amount: 1000 }, {})), 'unauthenticated');
  });
  await check('C2 begona foydalanuvchi uchun — permission-denied', async () => {
    assert.strictEqual(await codeOf(limit({ userId: USER, amount: 1000 }, ctxOf(OTHER))), 'permission-denied');
  });
  await check('C3 o\'zi uchun — ruxsat, anomaliya sozlamalari qaytarilmaydi', async () => {
    const r = await limit({ userId: USER, amount: 1000 }, ctxOf(USER));
    assert.strictEqual(r.allowed, true);
    assert.strictEqual(r.settings, undefined);
  });
  await check('C4 finance boshqa foydalanuvchi uchun — ruxsat', async () => {
    const r = await limit({ userId: USER, amount: 1000 }, ctxOf(FIN));
    assert.strictEqual(r.allowed, true);
  });

  const passed = results.filter(Boolean).length;
  const failed = results.length - passed;
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
