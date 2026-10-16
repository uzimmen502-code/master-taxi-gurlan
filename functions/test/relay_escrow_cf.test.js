/**
 * AVA Logistics eskrou — HAQIQIY ledger bilan (Firestore Emulator, Admin SDK).
 *
 *   firebase emulators:exec --only firestore --project demo-relay-escrow \
 *     "node functions/test/relay_escrow_cf.test.js"
 *
 * Qulflanadi (D-11, relay 7.6):
 *   - FUND: hamyon → eskrou, ATOMAR (holat + ledger bir tranzaksiyada); yetmasa rad
 *   - EARNED eskrouni KAMAYTIRMAYDI; ijrochiga `supplier_payable`
 *   - RELEASE: eskrou → payable pool + AVA ulushi; `settled`; frozen → yo'q
 *   - REFUND: eskrou → hamyon; `refunded`
 *   - hammasi idempotent; Σdr == Σcr
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-relay-escrow';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const settlementLedger = require('../settlement_ledger');
const relay = require('../relay_escrow');

const OWNER = '998901110001';
const K1 = '998902220002';
const F1 = '998904440004';
const NOW = new Date('2026-10-07T06:00:00Z');
const notified = [];
const digits = (v) => String(v || '').replace(/\D/g, '');
const api = relay.attachRelayEscrow({}, {
  functions, db, admin,
  callerPhone: (ctx) => digits(ctx.auth.token.phone_number),
  canonicalUid: (v) => { const d = digits(v); return d.length === 9 ? `998${d}` : d; },
  settlementLedger,
  notifyUserInApp: async (m) => { notified.push(m); },
  now: () => NOW,
});
const ctx = { auth: { token: { phone_number: `+${OWNER}` } } };

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => d.ref.delete()));
}
const bal = async (acc) => (await db.collection(settlementLedger.COL_ACCOUNTS).doc(acc).get()).data()?.balance || 0;
const wallet = () => bal(settlementLedger.passengerCreditAccount(OWNER));
const ship = async (id) => (await db.collection('shipments').doc(id).get()).data();

async function seedShipment(id, { price = 240000, platformShare = 48000, pool = 192000, wallet: w = 300000 } = {}) {
  notified.length = 0;
  await Promise.all(['shipments', 'users', 'custody_events', settlementLedger.COL_JOURNAL, settlementLedger.COL_ACCOUNTS].map(wipe));
  await db.collection('users').doc(OWNER).set({ bonusBalance: 0 });
  await db.collection('shipments').doc(id).set({
    ownerId: OWNER, trackingNumber: 'AVA-26-1007-000001', status: 'awaiting_payment', paymentStatus: 'pending',
    priceSnapshot: { customerPrice: price, tariffVersion: 7 }, legIds: ['leg0', 'leg1'],
  });
  await db.collection('shipments').doc(id).collection('private').doc('internal').set({
    platformShare, providerPool: pool, legPayouts: [{ index: 0, amount: 96000 }, { index: 1, amount: 96000 }],
  });
  if (w > 0) {
    await settlementLedger.postEntry(db, {
      idempotencyKey: `topup:${OWNER}:${id}`, kind: 'test_topup',
      legs: [{ account: 'admin_clearing', dr: w }, { account: settlementLedger.passengerCreditAccount(OWNER), cr: w }],
    });
  }
}

async function main() {
  const S = 'shpTEST0001';
  await seedShipment(S);

  await check('FUND: hamyon → eskrou, holat escrow_funded/ready AYNI tranzaksiyada', async () => {
    const r = await api.fund({ shipmentId: S }, ctx);
    assert.strictEqual(r.paymentStatus, 'escrow_funded'); assert.strictEqual(r.amount, 240000);
    assert.strictEqual(await wallet(), 60000);
    assert.strictEqual(await bal(relay.escrowAccount(S)), 240000);
    const s = await ship(S);
    assert.strictEqual(s.status, 'ready'); assert.strictEqual(s.paymentStatus, 'escrow_funded');
    assert.strictEqual(s.escrowAmount, 240000);
    assert.strictEqual((await db.collection('users').doc(OWNER).get()).data().bonusBalance, 60000, 'bonusBalance ko\'zgusi');
  });
  await check('FUND idempotent: ikkinchi chaqiruv pul olmaydi', async () => {
    const r = await api.fund({ shipmentId: S }, ctx);
    assert.strictEqual(r.idempotent, true);
    assert.strictEqual(await wallet(), 60000);
  });
  await check('FUND: egasi bo\'lmagan — permission-denied', async () => {
    await assert.rejects(() => api.fund({ shipmentId: S }, { auth: { token: { phone_number: `+${K1}` } } }), (e) => e.code === 'permission-denied');
  });

  await check('EARNED (LEG-1 tugadi): payable K1 +96 000, eskrou O\'ZGARMAYDI', async () => {
    const r = await api.onCustodyEvent({
      shipmentId: S, legId: 'leg1', kind: 'pickup', completesLegId: 'leg0', completedLegProviderId: K1,
      completedLegPayout: 96000, legIndex: 1, deliversShipment: false,
    });
    assert.strictEqual(r.earned.earned, 96000);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), 96000);
    assert.strictEqual(await bal(relay.escrowAccount(S)), 240000, 'eskrou to\'liq turadi (7.6)');
    assert.strictEqual(await bal(relay.ACCRUAL_ACCOUNT), -96000);
    const again = await api.onCustodyEvent({ shipmentId: S, completesLegId: 'leg0', completedLegProviderId: K1, completedLegPayout: 96000 });
    assert.strictEqual(again.earned.idempotent, true);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), 96000, 'takror trigger — takror pul yo\'q');
  });

  await check('DELIVERED: EARNED F1 + RELEASE: eskrou 0, AVA ulushi 48 000, payable pool yopildi, settled, xabar', async () => {
    const r = await api.onCustodyEvent({
      shipmentId: S, legId: 'leg1', kind: 'delivery', completesLegId: 'leg1', completedLegProviderId: F1,
      completedLegPayout: 96000, legIndex: 1, deliversShipment: true, trackingNumber: 'AVA-26-1007-000001',
    });
    assert.strictEqual(r.release.released, 240000);
    assert.strictEqual(await bal(relay.escrowAccount(S)), 0);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(F1)), 96000);
    assert.strictEqual(await bal(relay.PLATFORM_FEE_ACCOUNT), 48000);
    assert.strictEqual(await bal(relay.ACCRUAL_ACCOUNT), 0, 'EARNED (−192 000) + RELEASE (+192 000) = 0');
    assert.strictEqual((await ship(S)).paymentStatus, 'settled');
    assert.strictEqual(notified.length, 1);
    const j = await db.collection(settlementLedger.COL_JOURNAL).doc(`relayRelease:${S}`).get();
    const dr = j.data().legs.reduce((s, l) => s + l.dr, 0); const cr = j.data().legs.reduce((s, l) => s + l.cr, 0);
    assert.strictEqual(dr, cr);
  });
  await check('RELEASE idempotent', async () => {
    const r = await api.releaseEscrow(S);
    assert.strictEqual(r.skipped, 'already_settled');
    assert.strictEqual(await bal(relay.PLATFORM_FEE_ACCOUNT), 48000);
  });

  const S2 = 'shpTEST0002';
  await seedShipment(S2, { wallet: 100000 });
  await check('FUND: hamyon yetmasa — rad, holat o\'zgarmaydi, pul olinmaydi', async () => {
    await assert.rejects(() => api.fund({ shipmentId: S2 }, ctx), (e) => e.code === 'failed-precondition' && e.details.reason === 'insufficient' && e.details.shortfall === 140000);
    assert.strictEqual(await wallet(), 100000);
    assert.strictEqual((await ship(S2)).paymentStatus, 'pending');
  });

  const S3 = 'shpTEST0003';
  await seedShipment(S3);
  await check('REFUND: bekor (refund_pending) → eskrou hamyonga, refunded; idempotent', async () => {
    await api.fund({ shipmentId: S3 }, ctx);
    assert.strictEqual(await wallet(), 60000);
    // demand codebase bekor qildi:
    const before = await ship(S3);
    await db.collection('shipments').doc(S3).update({ status: 'cancelled', paymentStatus: 'refund_pending' });
    const r = await api.onShipmentUpdate(before, await ship(S3), S3);
    assert.strictEqual(r.refunded, 240000);
    assert.strictEqual(await wallet(), 300000);
    assert.strictEqual(await bal(relay.escrowAccount(S3)), 0);
    assert.strictEqual((await ship(S3)).paymentStatus, 'refunded');
    const again = await api.onShipmentUpdate({ paymentStatus: 'pending' }, await ship(S3), S3);
    assert.strictEqual(again.skipped, 'payment_refunded');
    assert.strictEqual(await wallet(), 300000);
  });

  const S4 = 'shpTEST0004';
  await seedShipment(S4);
  await check('FROZEN (nizo): yetkazilsa ham RELEASE qilinmaydi', async () => {
    await api.fund({ shipmentId: S4 }, ctx);
    await db.collection('shipments').doc(S4).update({ paymentStatus: 'escrow_frozen' });
    const r = await api.onCustodyEvent({ shipmentId: S4, completesLegId: 'leg1', completedLegProviderId: F1, completedLegPayout: 96000, deliversShipment: true });
    assert.strictEqual(r.release.skipped, 'frozen');
    assert.strictEqual(await bal(relay.escrowAccount(S4)), 240000);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(F1)), 96000, 'EARNED baribir yoziladi — mehnat yo\'qolmaydi');
  });

  const S5 = 'shpTEST0005';
  await seedShipment(S5, { platformShare: 48000, pool: 100000 });
  await check('RELEASE: ichki summa mos kelmasa — yozilmaydi (xato logga)', async () => {
    await api.fund({ shipmentId: S5 }, ctx);
    const r = await api.releaseEscrow(S5);
    assert.strictEqual(r.skipped, 'amount_mismatch');
    assert.strictEqual(await bal(relay.escrowAccount(S5)), 240000);
  });

  // R2/R3 (L2, L1-natija): trigger yiqilsa ham pul qotib qolmasin — reconcile tiklaydi.
  const S6 = 'shpTEST0006';
  await seedShipment(S6);
  await check('RECONCILE: refund_pending qotib qolgan (trigger yiqilgan) → refunded', async () => {
    await api.fund({ shipmentId: S6 }, ctx);
    await db.collection('shipments').doc(S6).update({ status: 'cancelled', paymentStatus: 'refund_pending' });
    const r = await api.reconcile();
    assert.strictEqual(r.refunded, 1);
    assert.strictEqual(await wallet(), 300000);
    assert.strictEqual((await ship(S6)).paymentStatus, 'refunded');
  });
  const S7 = 'shpTEST0007';
  await seedShipment(S7);
  await check('RECONCILE: bekor qilingan, lekin escrow_funded qolgan (cancel/fund poygasi) → refund', async () => {
    await api.fund({ shipmentId: S7 }, ctx);
    await db.collection('shipments').doc(S7).update({ status: 'cancelled' });
    const r = await api.reconcile();
    assert.strictEqual(r.refunded, 1);
    assert.strictEqual(await wallet(), 300000);
    assert.strictEqual(await bal(relay.escrowAccount(S7)), 0);
    assert.strictEqual((await ship(S7)).paymentStatus, 'refunded');
    const again = await api.reconcile();
    assert.strictEqual(again.refunded, 0, 'takror reconcile pul qaytarmaydi');
    assert.strictEqual(await wallet(), 300000);
  });
  const S8 = 'shpTEST0008';
  await seedShipment(S8);
  await check('RECONCILE: delivered, lekin RELEASE/EARNED yozilmagan → settled, ijrochilarga payable, takror ikkilamaydi', async () => {
    await api.fund({ shipmentId: S8 }, ctx);
    await db.collection('shipments').doc(S8).update({ status: 'delivered' });
    await db.collection('custody_events').doc('e1').set({
      shipmentId: S8, legId: 'leg1', completesLegId: 'leg0', completedLegProviderId: K1,
      completedLegPayout: 96000, deliversShipment: false,
    });
    await db.collection('custody_events').doc('e2').set({
      shipmentId: S8, legId: 'leg1', completesLegId: 'leg1', completedLegProviderId: F1,
      completedLegPayout: 96000, deliversShipment: true,
    });
    const r = await api.reconcile();
    assert.strictEqual(r.released, 1);
    assert.strictEqual((await ship(S8)).paymentStatus, 'settled');
    assert.strictEqual(await bal(relay.escrowAccount(S8)), 0);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), 96000);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(F1)), 96000);
    assert.strictEqual(await bal(relay.PLATFORM_FEE_ACCOUNT), 48000);
    await api.reconcile();
    assert.strictEqual(await bal(relay.PLATFORM_FEE_ACCOUNT), 48000);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), 96000);
  });
  await check('RECONCILE: escrow_frozen (nizo) ga tegilmaydi', async () => {
    const S9 = 'shpTEST0009';
    await seedShipment(S9);
    await api.fund({ shipmentId: S9 }, ctx);
    await db.collection('shipments').doc(S9).update({ status: 'delivered', paymentStatus: 'escrow_frozen' });
    await api.reconcile();
    assert.strictEqual(await bal(relay.escrowAccount(S9)), 240000);
    assert.strictEqual((await ship(S9)).paymentStatus, 'escrow_frozen');
  });

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} relay escrow CF checks passed.`);
  if (failed.length) process.exitCode = 1;
}
main().catch((e) => { console.error('FATAL', e); process.exitCode = 1; });
