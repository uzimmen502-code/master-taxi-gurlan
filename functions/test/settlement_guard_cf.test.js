/**
 * Settlement (haydovchi qaytimi hamyondan) — hamyon auditi O-7, O-8.
 * HAQIQIY ledger bilan (Firestore Emulator, Admin SDK).
 *
 *   firebase emulators:exec --only firestore --project demo-wallet-audit \
 *     "node functions/test/settlement_guard_cf.test.js"
 *
 * O-7: openSettlement idempotent javobni begona haydovchiga ham qaytarardi
 *      (opId oldindan ma'lum), `settlementId/State` istalgan reysga yozilardi.
 * O-8: submitDeferredSettlement settlement holatini o'qimasdi — bekor
 *      qilingan settlement `completed` bo'lib «tirilardi», pul o'tardi.
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

const DRIVER = '998902000001';
const OTHERD = '998902000002';
const PASS = '998901000001';
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
async function reset() {
  await Promise.all(['users', 'trips', 'intercity_bookings', 'settlements', 'wallet_idempotency',
    ledger.COL_JOURNAL, ledger.COL_ACCOUNTS].map(wipe));
  for (const [uid, bal] of [[DRIVER, 50000], [OTHERD, 50000], [PASS, 0]]) {
    await db.collection('users').doc(uid).set({ role: 'user', phone: uid, name: 'T', bonusBalance: bal });
    if (bal) {
      await db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(uid))
          .set({ type: 'liability', ownerUid: uid, balance: bal });
    }
  }
  await db.collection('trips').doc('T_MINE').set({ acceptedDriverId: DRIVER, userPhone: PASS, status: 'completed' });
  await db.collection('trips').doc('T_OTHER').set({ acceptedDriverId: OTHERD, userPhone: PASS, status: 'completed' });
}
const bal = async (uid) => ((await db.collection('users').doc(uid).get()).data() || {}).bonusBalance || 0;
const open = (who, d) => fns.openSettlement.run(d, ctxOf(who));
const deferred = (who, d) => fns.submitDeferredSettlement.run(d, ctxOf(who));
async function codeOf(p) {
  try { await p; return 'ok'; } catch (e) { return `${e.code}:${(e.details || {}).errorCode || ''}`; }
}

(async () => {
  await reset();
  await check('S1 begona haydovchi o\'zganing opId\'si bilan openSettlement — SETTLEMENT_ID_TAKEN', async () => {
    await open(DRIVER, { passengerPhone: PASS, tripId: 'T_MINE', opId: 'settle_trip_T_MINE', totalChange: 7000, cashGiven: 0 });
    const c = await codeOf(open(OTHERD, { passengerPhone: PASS, tripId: 'T_MINE', opId: 'settle_trip_T_MINE', totalChange: 7000, cashGiven: 0 }));
    assert.strictEqual(c, 'permission-denied:SETTLEMENT_ID_TAKEN');
  });

  await reset();
  await check('S2 openSettlement begona reysga settlementId YOZMAYDI', async () => {
    await open(DRIVER, { passengerPhone: PASS, tripId: 'T_OTHER', opId: 'settle_x_1', totalChange: 7000, cashGiven: 0 });
    const t = (await db.collection('trips').doc('T_OTHER').get()).data();
    assert.strictEqual(t.settlementId, undefined);
  });

  await reset();
  await check('S3 o\'z reysiga — yoziladi (avvalgidek)', async () => {
    await open(DRIVER, { passengerPhone: PASS, tripId: 'T_MINE', opId: 'settle_x_2', totalChange: 7000, cashGiven: 0 });
    const t = (await db.collection('trips').doc('T_MINE').get()).data();
    assert.strictEqual(t.settlementId, 'settle_x_2');
    assert.strictEqual(t.settlementState, 'pending');
  });

  await reset();
  await check('S4 bekor qilingan settlement deferred bilan «tirilmaydi», pul o\'tmaydi', async () => {
    await open(DRIVER, { passengerPhone: PASS, tripId: 'T_MINE', opId: 'settle_x_3', totalChange: 7000, cashGiven: 0 });
    await fns.cancelSettlement.run({ settlementId: 'settle_x_3' }, ctxOf(PASS));
    const c = await codeOf(deferred(DRIVER, { passengerPhone: PASS, tripId: 'T_MINE', opId: 'settle_x_3', settlementAmount: 7000 }));
    assert.strictEqual(c, 'failed-precondition:SETTLEMENT_CANCELLED');
    assert.strictEqual(await bal(PASS), 0);
    assert.strictEqual(await bal(DRIVER), 50000);
    assert.strictEqual((await db.collection('settlements').doc('settle_x_3').get()).data().state, 'cancelled');
  });

  await reset();
  await check('S5 mavjud settlement bilan summa mos emas — SETTLEMENT_MISMATCH', async () => {
    await open(DRIVER, { passengerPhone: PASS, tripId: 'T_MINE', opId: 'settle_x_4', totalChange: 7000, cashGiven: 0 });
    const c = await codeOf(deferred(DRIVER, { passengerPhone: PASS, tripId: 'T_MINE', opId: 'settle_x_4', settlementAmount: 40000 }));
    assert.strictEqual(c, 'failed-precondition:SETTLEMENT_MISMATCH');
    assert.strictEqual(await bal(PASS), 0);
  });

  await reset();
  await check('S6 open → (tarmoq uzildi) → deferred shu ma\'lumot bilan — yakunlanadi', async () => {
    await open(DRIVER, { passengerPhone: PASS, tripId: 'T_MINE', opId: 'settle_x_5', totalChange: 7000, cashGiven: 0 });
    const r = await deferred(DRIVER, { passengerPhone: PASS, tripId: 'T_MINE', opId: 'settle_x_5', settlementAmount: 7000 });
    assert.strictEqual(r.state, 'completed');
    assert.strictEqual(await bal(PASS), 7000);
    assert.strictEqual(await bal(DRIVER), 43000);
  });

  await reset();
  await check('S7 deferred begona reys bilan — pul o\'tadi, lekin begona reysga yozilmaydi', async () => {
    const r = await deferred(DRIVER, { passengerPhone: PASS, tripId: 'T_OTHER', opId: 'settle_x_6', settlementAmount: 5000 });
    assert.strictEqual(r.state, 'completed');
    const t = (await db.collection('trips').doc('T_OTHER').get()).data();
    assert.strictEqual(t.settlementId, undefined);
  });

  await reset();
  await check('S8 yo\'lovchi o\'z reysidagi settlement\'ni bekor qiladi — reys holati «cancelled»', async () => {
    await open(DRIVER, { passengerPhone: PASS, tripId: 'T_MINE', opId: 'settle_x_7', totalChange: 7000, cashGiven: 0 });
    const r = await fns.cancelSettlement.run({ settlementId: 'settle_x_7' }, ctxOf(PASS));
    assert.strictEqual(r.state, 'cancelled');
    const t = (await db.collection('trips').doc('T_MINE').get()).data();
    assert.strictEqual(t.settlementState, 'cancelled');
  });

  await reset();
  await check('S9 begona reysga bog\'langan settlement bekor/tasdiq — begona reysga yozilmaydi', async () => {
    await open(DRIVER, { passengerPhone: PASS, tripId: 'T_OTHER', opId: 'settle_x_8', totalChange: 7000, cashGiven: 0 });
    await fns.cancelSettlement.run({ settlementId: 'settle_x_8' }, ctxOf(PASS));
    await open(DRIVER, { passengerPhone: PASS, tripId: 'T_OTHER', opId: 'settle_x_9', totalChange: 3000, cashGiven: 0 });
    await fns.confirmSettlement.run({ settlementId: 'settle_x_9' }, ctxOf(PASS));
    const t = (await db.collection('trips').doc('T_OTHER').get()).data();
    assert.strictEqual(t.settlementState, undefined);
    assert.strictEqual(await bal(PASS), 3000);
  });

  await reset();
  await check('S10 deferred mavjud settlement\'ning asl totalChange/cashGiven\'ini saqlaydi', async () => {
    await open(DRIVER, { passengerPhone: PASS, tripId: 'T_MINE', opId: 'settle_x_10', totalChange: 10000, cashGiven: 3000 });
    await deferred(DRIVER, { passengerPhone: PASS, tripId: 'T_MINE', opId: 'settle_x_10', settlementAmount: 7000 });
    const s = (await db.collection('settlements').doc('settle_x_10').get()).data();
    assert.strictEqual(s.totalChange, 10000);
    assert.strictEqual(s.cashGiven, 3000);
    assert.strictEqual(s.state, 'completed');
  });

  const passed = results.filter(Boolean).length;
  const failed = results.length - passed;
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
