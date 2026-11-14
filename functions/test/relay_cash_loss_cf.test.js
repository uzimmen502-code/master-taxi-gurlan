/**
 * AVA Logistics — NAQD yetkazish haqi jo'natmasi YO'QOLDI (ega CONFIRMED 2026-11-14), default codebase
 * `relay_escrow.settleLoss` → `settleCashLoss`, HAQIQIY ledger (Firestore Emulator).
 *
 *   firebase emulators:exec --only firestore --project demo-relay-cash-loss "node functions/test/relay_cash_loss_cf.test.js"
 *
 * Demand `adminMarkShipmentLost` yozadigan holat qo'lda seed qilinadi (shipment lost/loss_pending, naqd
 * `deliveryPayment.status: pending`, `logistics_incidents`). Qulflanadi:
 *   - 1 LEG, kuryer boy: G kuryerdan egaga (bitta `relayCashLost:{id}`), eskrou YO'Q (escrow:{id} yaratilmaydi),
 *     xaridor naqdi tegilmaydi (deliveryPayment.status pending), incident repaid, audit, xabar
 *   - ko'p LEG: oldingi LEG EARNED (trigger yiqilgan bo'lsa ham yoziladi), accrual kuryer hamyonidan yopiladi (0)
 *   - hamyon kam: G qisman + qarz; oldingi LEG haqi AVA (admin_clearing) + qarz; keyin adminRecordLostParcelPayment
 *   - hamyon 0, 1 LEG: pul yozuvi yo'q, G to'liq qarz; reconcile tiklaydi, takrori — yo'q
 *   - poyga: 3 × settleLoss + reconcile + trigger parallel — bitta yozuv, qarz bir marta
 *   - anomaliyalar (pul YO'Q, loss_pending qoladi): naqd collected/refusal_*, escrowEntryId bor, EARNED > pool,
 *     kuryer = ega; releaseEscrow naqdda hech qachon yozmaydi
 *   - eskrou yo'qolishi (regressiya): o'zgarmagan
 *   - Σdr == Σcr, aktiv == passiv, passenger_credit == bonusBalance
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18770';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-relay-cash-loss';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const settlementLedger = require('../settlement_ledger');
const relay = require('../relay_escrow');

const OWNER = '998901234567';
const K1 = '998902220002';
const F1 = '998904440004';
const ADMIN_U = '998909990000';
const ACC_F1 = 'accF1';
const NOW = new Date('2026-11-14T10:00:00Z');
const G = 150000;
const PRICE = 60000;
const SHARE = 12000;
const POOL = 48000;
const E1 = 20000; // 1-LEG (K1) haqi; 2-LEG (F1, yo'qotgan) 28 000
const SID = 'shpCASH1';
const notified = [];
const digits = (v) => String(v || '').replace(/\D/g, '');
const canon = (v) => { const d = digits(v); return d.length === 9 ? `998${d}` : d; };
const api = relay.attachRelayEscrow({}, {
  functions, db, admin,
  callerPhone: (c) => digits(c.auth.token.phone_number),
  canonicalUid: canon,
  settlementLedger,
  notifyUserInApp: async (m) => { notified.push(m); },
  requireCallerRoles: async (context, roles, msg) => {
    const uid = canon(context && context.auth && context.auth.token.phone_number);
    const role = ((await db.collection('users').doc(uid).get()).data() || {}).role || 'user';
    if (!roles.includes(role)) throw new functions.https.HttpsError('permission-denied', msg || 'no');
    return uid;
  },
  now: () => NOW,
});
const asCtx = (uid) => ({ auth: { token: { phone_number: `+${uid}` } } });

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
const realConsole = { log: console.log, error: console.error, warn: console.warn };
let quietDepth = 0;
const quiet = async (fn) => {
  quietDepth += 1;
  console.log = () => {}; console.error = () => {}; console.warn = () => {};
  try { return await fn(); } finally {
    quietDepth -= 1;
    if (quietDepth === 0) Object.assign(console, realConsole);
  }
};
async function resetAll() {
  const url = `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`;
  const res = await fetch(url, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator tozalanmadi: ${res.status}`);
}
const pcOf = (uid) => settlementLedger.passengerCreditAccount(uid);
const accDoc = async (acc) => db.collection(settlementLedger.COL_ACCOUNTS).doc(acc).get();
const bal = async (acc) => ((await accDoc(acc)).data() || {}).balance || 0;
const bonusOf = async (uid) => ((await db.collection('users').doc(uid).get()).data() || {}).bonusBalance || 0;
const journal = async (key) => db.collection(settlementLedger.COL_JOURNAL).doc(key).get();
const shipOf = async (id = SID) => (await db.collection('shipments').doc(id).get()).data();
const incOf = async (id = SID) => (await db.collection('logistics_incidents').doc(id).get()).data();
const debtOf = async () => Number(((((await db.collection('provider_capabilities').doc(ACC_F1).get()).data() || {}).debt) || {}).logistics) || 0;
const walletLedger = async (uid, type) => (await db.collection('users').doc(uid).collection('wallet_ledger').where('type', '==', type).get()).docs.map((d) => d.data());
const journalsOf = async (kind) => (await db.collection(settlementLedger.COL_JOURNAL).where('kind', '==', kind).get()).docs;
async function assertLedgerSound() {
  const rec = await settlementLedger.reconcile(db);
  assert.strictEqual(rec.balanced, true, `Σdr==Σcr buzildi: ${rec.totalDr} != ${rec.totalCr}`);
  assert.strictEqual(rec.identityOk, true, `aktiv/passiv: ${rec.assets} != ${rec.liabilities}`);
  assert.strictEqual(rec.projectionOk, true, `bonusBalance ko'zgusi: ${JSON.stringify(rec.mismatches)}`);
}
let topupSeq = 0;
const topup = (uid, amount) => settlementLedger.postEntry(db, {
  idempotencyKey: `topupCL:${uid}:${topupSeq += 1}`, kind: 'test_topup',
  legs: [{ account: 'admin_clearing', dr: amount }, { account: pcOf(uid), cr: amount }],
}, { mirrorBonus: true });

/**
 * Demand e'lon qilgan naqd yo'qolish. legs=1: F1 yagona LEG'da yo'qotdi. legs=2: K1 1-LEG'ni tugatgan
 * (custody hodisasi `completedLegPayout: E1`), F1 2-LEG'da yo'qotdi. earnedPosted=false — EARNED triggeri yiqilgan.
 */
async function seedCashLoss({
  legs = 1, courierWallet = 500000, earnedPosted = true, cashStatus = 'pending', extraShip = {}, ownerId = OWNER,
} = {}) {
  notified.length = 0;
  await resetAll();
  await db.collection('users').doc(OWNER).set({ bonusBalance: 0 });
  await db.collection('users').doc(K1).set({ bonusBalance: 0, accountId: 'accK1' });
  await db.collection('users').doc(F1).set({ bonusBalance: 0, accountId: ACC_F1 });
  await db.collection('users').doc(ADMIN_U).set({ role: 'admin' });
  if (courierWallet > 0) await topup(F1, courierWallet);
  const legIds = legs === 1 ? ['leg0'] : ['leg0', 'leg1'];
  const lostLeg = legIds[legIds.length - 1];
  await db.collection('shipments').doc(SID).set({
    ownerId, trackingNumber: 'AVA-26-1114-000777', status: 'lost', paymentStatus: 'loss_pending',
    priceSnapshot: { customerPrice: PRICE, tariffVersion: 3, declaredValue: G }, legIds, currentLegId: lostLeg,
    lostLegId: lostLeg, lossIncidentId: SID,
    deliveryPayment: {
      method: 'cash', amount: PRICE, currency: 'UZS', status: cashStatus, collectedBy: null, collectedAt: null,
      collectorLegId: lostLeg, collectorLegPayout: legs === 1 ? POOL : POOL - E1,
    },
    ...extraShip,
  });
  await db.collection('shipments').doc(SID).collection('private').doc('internal').set({
    platformShare: SHARE, providerPool: POOL,
    legPayouts: legs === 1 ? [{ index: 0, amount: POOL }] : [{ index: 0, amount: E1 }, { index: 1, amount: POOL - E1 }],
  });
  if (legs === 2) {
    await db.collection('custody_events').doc('ev1').set({
      shipmentId: SID, completesLegId: 'leg0', completedLegProviderId: K1, completedLegPayout: E1, legIndex: 0,
    });
    if (earnedPosted) await api.postEarned({ shipmentId: SID, completesLegId: 'leg0', completedLegProviderId: K1, completedLegPayout: E1, legIndex: 0 });
  }
  await db.collection('logistics_incidents').doc(SID).set({
    type: 'lost', status: 'declared', shipmentId: SID, trackingNumber: 'AVA-26-1114-000777', legId: lostLeg,
    legIndex: legIds.length - 1, courier: { uid: F1, accountId: ACC_F1 }, customer: { uid: ownerId },
    goodsValue: G, customerPrice: PRICE, deliveryPaymentMethod: 'cash', buyerCashPaid: 0,
    refundedNow: null, outstanding: null, paidTotal: 0, declaredAt: NOW,
  });
}
const settle = () => quiet(() => api.settleLoss(SID));
const normLegs = (legs) => legs.map((l) => (l.dr > 0 ? { account: l.account, dr: l.dr } : { account: l.account, cr: l.cr }));
const j0legsHasClearing = (j) => (j.legs || []).some((l) => l.account === 'admin_clearing');

(async () => {
  await check('1 LEG, kuryer BOY: G kuryerdan EGAGA (relayCashLost), eskrou yo\'q, xaridor naqdi tegilmaydi, incident repaid, qarz 0, audit, xabar', async () => {
    await seedCashLoss();
    const r = await settle();
    assert.deepStrictEqual(
      [r.settled, r.cash, r.flipped, r.taken, r.outstanding, r.earlier, r.takeEarlier, r.avaCovered, r.courierDebt],
      [true, true, true, G, 0, 0, 0, 0, 0],
    );
    assert.strictEqual(await bal(pcOf(OWNER)), G);
    assert.strictEqual(await bonusOf(OWNER), G);
    assert.strictEqual(await bal(pcOf(F1)), 500000 - G);
    assert.strictEqual(await bonusOf(F1), 500000 - G);
    assert.strictEqual(await debtOf(), 0);
    assert.strictEqual((await accDoc(relay.escrowAccount(SID))).exists, false, 'naqd: escrow:{id} hech qachon yaratilmaydi');
    assert.strictEqual(await bal('platform_accrual'), 0);
    assert.strictEqual((await accDoc(relay.PLATFORM_FEE_ACCOUNT)).exists, false, 'AVA ulushi yo\'q (yetkazilmadi)');
    const j = (await journal(relay.cashLostKey(SID))).data();
    assert.strictEqual(j.kind, 'logistics_cash_lost');
    assert.deepStrictEqual(normLegs(j.legs), [{ account: pcOf(F1), dr: G }, { account: pcOf(OWNER), cr: G }]);
    assert.deepStrictEqual([j.meta.takeGoods, j.meta.avaCovered, j.meta.courierDebt, j.meta.cash], [G, 0, 0, true]);
    assert.strictEqual((await journal(`relayRelease:${SID}`)).exists, false);
    assert.strictEqual((await journal(`relayLostRefund:${SID}`)).exists, false);
    const s = await shipOf();
    assert.deepStrictEqual([s.paymentStatus, s.lossRefundEntryId, s.deliveryPayment.status], ['loss_settled', relay.cashLostKey(SID), 'pending']);
    assert.deepStrictEqual([s.deliveryPayment.lossSettlement.buyerCashPaid, s.deliveryPayment.lossSettlement.buyerOwes], [0, 0]);
    const inc = await incOf();
    assert.deepStrictEqual([inc.status, inc.refundedNow, inc.outstanding, inc.unearnedToAva, inc.refundEntryId], ['repaid', G, 0, 0, relay.cashLostKey(SID)]);
    assert.deepStrictEqual([inc.cashLoss.earlier, inc.cashLoss.avaCovered, inc.cashLoss.courierDebt], [0, 0, 0]);
    const ev = (await db.collection('logistics_incidents').doc(SID).collection('events').doc('settled').get()).data();
    assert.deepStrictEqual([ev.cash, ev.refunded, ev.outstanding], [true, G, 0]);
    const audit = (await db.collection('logistics_audit').doc(`cash_loss_${SID}`).get()).data();
    assert.deepStrictEqual([audit.kind, audit.goodsFromCourier, audit.accountId], ['cash_loss_settle', G, ACC_F1]);
    assert.deepStrictEqual((await walletLedger(OWNER, 'logistics_lost_refund')).map((x) => x.amount), [G]);
    assert.deepStrictEqual((await walletLedger(F1, 'logistics_lost_refund')).map((x) => x.amount), [-G]);
    assert.deepStrictEqual(notified.map((n) => n.userId).sort(), [OWNER, F1].sort());
    await assertLedgerSound();
  });

  await check('takror: settleLoss / trigger retry / reconcile — ikkinchi pul YO\'Q', async () => {
    assert.deepStrictEqual(await settle(), { skipped: 'already_settled' });
    const s = await shipOf();
    assert.deepStrictEqual(await quiet(() => api.onShipmentUpdate({ ...s, paymentStatus: 'loss_pending' }, s, SID)), { skipped: 'payment_loss_settled' });
    const rec = await quiet(() => api.reconcile());
    assert.deepStrictEqual([rec.lossSettled, rec.failed], [0, 0]);
    assert.strictEqual(await bal(pcOf(OWNER)), G);
    assert.strictEqual(await bal(pcOf(F1)), 500000 - G);
    assert.strictEqual((await journalsOf('logistics_cash_lost')).length, 1);
    await assertLedgerSound();
  });

  await check('ko\'p LEG, EARNED triggeri YIQILGAN: settle 1-LEG EARNED\'ini yozadi (K1 haqi saqlanadi), accrual kuryer hamyonidan yopiladi (0)', async () => {
    await seedCashLoss({ legs: 2, earnedPosted: false });
    assert.strictEqual((await journal(`relayEarned:${SID}:leg0`)).exists, false);
    const r = await settle();
    assert.deepStrictEqual([r.taken, r.earlier, r.takeEarlier, r.avaCovered, r.courierDebt], [G, E1, E1, 0, 0]);
    assert.strictEqual((await journal(`relayEarned:${SID}:leg0`)).exists, true);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), E1, 'K1 ishlab topgani');
    assert.strictEqual(await bal('platform_accrual'), 0, 'accrual yopildi (AVA o\'z cho\'ntagidan bermadi)');
    assert.strictEqual(await bal(pcOf(OWNER)), G);
    assert.strictEqual(await bal(pcOf(F1)), 500000 - G - E1);
    assert.ok(!j0legsHasClearing((await journal(relay.cashLostKey(SID))).data()), 'AVA qoplamadi (admin_clearing oyog\'i yo\'q)');
    const j = (await journal(relay.cashLostKey(SID))).data();
    assert.deepStrictEqual(normLegs(j.legs), [
      { account: pcOf(F1), dr: G + E1 }, { account: pcOf(OWNER), cr: G }, { account: 'platform_accrual', cr: E1 },
    ]);
    assert.strictEqual(await debtOf(), 0);
    await assertLedgerSound();
  });

  await check('ko\'p LEG, kuryer hamyoni KAM (100 000): G dan 100 000 egaga (50 000 qarz), oldingi LEG 20 000 — AVA + qarz; hamyon 0 (manfiy emas)', async () => {
    await seedCashLoss({ legs: 2, courierWallet: 100000 });
    const r = await settle();
    assert.deepStrictEqual([r.taken, r.outstanding, r.takeEarlier, r.avaCovered, r.courierDebt], [100000, G - 100000, 0, E1, G - 100000 + E1]);
    assert.strictEqual(await bal(pcOf(OWNER)), 100000);
    assert.strictEqual(await bal(pcOf(F1)), 0);
    assert.strictEqual(await bal('platform_accrual'), 0);
    assert.strictEqual(await debtOf(), G - 100000 + E1);
    const j = (await journal(relay.cashLostKey(SID))).data();
    assert.deepStrictEqual(normLegs(j.legs), [
      { account: pcOf(F1), dr: 100000 }, { account: 'admin_clearing', dr: E1 },
      { account: pcOf(OWNER), cr: 100000 }, { account: 'platform_accrual', cr: E1 },
    ]);
    const inc = await incOf();
    assert.deepStrictEqual([inc.status, inc.refundedNow, inc.outstanding], ['settled', 100000, G - 100000]);
    assert.deepStrictEqual([inc.cashLoss.earlierFromCourier, inc.cashLoss.avaCovered, inc.cashLoss.courierDebt], [0, E1, G - 100000 + E1]);
    const audit = (await db.collection('logistics_audit').doc(`cash_loss_${SID}`).get()).data();
    assert.deepStrictEqual([audit.avaCovered, audit.courierDebt], [E1, G - 100000 + E1]);
    await assertLedgerSound();
  });

  await check('keyin admin kuryer to\'lovini yozadi (adminRecordLostParcelPayment): 50 000 egaga, incident repaid, qarzda faqat AVA qoplagan 20 000 qoladi', async () => {
    const r = await quiet(() => api.recordLostPayment({ shipmentId: SID, amount: G - 100000, opId: 'op-cash-pay-1' }, asCtx(ADMIN_U)));
    assert.deepStrictEqual([r.ok, r.outstanding], [true, 0]);
    assert.strictEqual(await bal(pcOf(OWNER)), G);
    assert.strictEqual(await debtOf(), E1);
    assert.strictEqual((await incOf()).status, 'repaid');
    await assertLedgerSound();
  });

  await check('1 LEG, kuryer hamyoni 0: pul yozuvi YO\'Q, G to\'liq qarz; trigger yiqilgan — reconcile tiklaydi, takrori yo\'q', async () => {
    await seedCashLoss({ courierWallet: 0 });
    let rec = await quiet(() => api.reconcile());
    assert.deepStrictEqual([rec.lossSettled, rec.failed], [1, 0]);
    rec = await quiet(() => api.reconcile());
    assert.deepStrictEqual([rec.lossSettled, rec.failed], [0, 0]);
    assert.strictEqual((await journal(relay.cashLostKey(SID))).exists, false);
    const s = await shipOf();
    assert.deepStrictEqual([s.paymentStatus, s.lossRefundEntryId], ['loss_settled', null]);
    const inc = await incOf();
    assert.deepStrictEqual([inc.status, inc.refundedNow, inc.outstanding], ['settled', 0, G]);
    assert.strictEqual(await debtOf(), G);
    assert.strictEqual((await accDoc(pcOf(F1))).exists, false);
    assert.strictEqual(await bal(pcOf(OWNER)), 0);
    await assertLedgerSound();
  });

  await check('poyga: 3 × settleLoss + trigger + reconcile PARALLEL (ko\'p LEG, kam hamyon) — bitta yozuv, qarz va pul bir marta', async () => {
    await seedCashLoss({ legs: 2, courierWallet: 100000 });
    const s = await shipOf();
    const outs = await quiet(() => Promise.all([
      api.settleLoss(SID), api.settleLoss(SID), api.settleLoss(SID),
      api.onShipmentUpdate({ ...s, paymentStatus: 'cash_on_delivery' }, s, SID), api.reconcile(),
    ]));
    assert.strictEqual(outs.slice(0, 4).filter((x) => x && x.flipped === true).length + (outs[4].lossSettled || 0), 1, JSON.stringify(outs));
    assert.strictEqual((await journalsOf('logistics_cash_lost')).length, 1);
    assert.strictEqual((await journalsOf('logistics_leg_earned')).length, 1);
    assert.strictEqual(await bal(pcOf(OWNER)), 100000);
    assert.strictEqual(await bal(pcOf(F1)), 0);
    assert.strictEqual(await debtOf(), G - 100000 + E1, 'qarz bir marta');
    assert.strictEqual(await bal('platform_accrual'), 0);
    await assertLedgerSound();
  });

  for (const st of ['collected', 'refusal_collected', 'refusal_unpaid', 'settled']) {
    await check(`anomaliya: naqd holati ${st} (xaridor to'lagan/qayd etilgan) — pul YO'Q, loss_pending qoladi`, async () => {
      await seedCashLoss({ legs: 2, cashStatus: st });
      const r = await settle();
      assert.deepStrictEqual([r.skipped, r.anomaly], ['cash_not_pending', true]);
      assert.strictEqual((await shipOf()).paymentStatus, 'loss_pending');
      assert.strictEqual((await incOf()).status, 'declared');
      assert.strictEqual((await journal(relay.cashLostKey(SID))).exists, false);
      assert.strictEqual(await bal(pcOf(F1)), 500000);
      assert.strictEqual(await debtOf(), 0);
      await assertLedgerSound();
    });
  }

  await check('anomaliya: naqd + escrowEntryId (bo\'lishi mumkin emas) / EARNED > pool / kuryer = ega — pul YO\'Q', async () => {
    await seedCashLoss({ extraShip: { escrowEntryId: 'relayEscrow:x:v1' } });
    assert.deepStrictEqual(await settle(), { skipped: 'cash_has_escrow', anomaly: true });
    await seedCashLoss({ legs: 2 });
    await db.collection('shipments').doc(SID).collection('private').doc('internal').update({ providerPool: E1 - 1 });
    assert.deepStrictEqual(await settle(), { skipped: 'earned_exceeds_pool', anomaly: true });
    assert.strictEqual((await journal(relay.cashLostKey(SID))).exists, false);
    await seedCashLoss({ ownerId: F1 });
    assert.deepStrictEqual(await settle(), { skipped: 'same_account' });
    assert.strictEqual((await shipOf()).paymentStatus, 'loss_pending');
    assert.strictEqual(await bal(pcOf(F1)), 500000);
    await assertLedgerSound();
  });

  await check('releaseEscrow naqd jo\'natmada HECH QACHON yozmaydi (forLoss ham, yetkazildi ham) — escrow:{id} yaratilmaydi', async () => {
    await seedCashLoss();
    assert.deepStrictEqual(await quiet(() => api.releaseEscrow(SID, { forLoss: true })), { skipped: 'cash_no_escrow' });
    await db.collection('shipments').doc(SID).update({ status: 'delivered', paymentStatus: 'escrow_funded' });
    assert.deepStrictEqual(await quiet(() => api.releaseEscrow(SID)), { skipped: 'cash_no_escrow' });
    assert.strictEqual((await journal(`relayRelease:${SID}`)).exists, false);
    assert.strictEqual((await accDoc(relay.escrowAccount(SID))).exists, false);
  });

  await check('regressiya: ESKROU jo\'natmasi yo\'qolishi o\'zgarmagan (relayRelease + relayLostRefund, unearned AVA ga)', async () => {
    await seedCashLoss();
    // Shu jo'natmani eskrou holatiga keltiramiz: deliveryPayment yo'q, eskrou to'ldirilgan.
    await db.collection('shipments').doc(SID).update({ deliveryPayment: admin.firestore.FieldValue.delete(), escrowEntryId: 'relayEscrow:test:v1' });
    await settlementLedger.postEntry(db, {
      idempotencyKey: 'relayEscrow:test:v1', kind: 'logistics_escrow_fund',
      legs: [{ account: 'admin_clearing', dr: PRICE }, { account: relay.escrowAccount(SID), cr: PRICE }],
    }, { mirrorBonus: false });
    const r = await settle();
    assert.deepStrictEqual([r.settled, r.cash, r.taken, r.unearned], [true, undefined, G, POOL]);
    assert.strictEqual((await journal(`relayRelease:${SID}`)).exists, true);
    assert.strictEqual((await journal(`relayLostRefund:${SID}`)).exists, true);
    assert.strictEqual((await journal(relay.cashLostKey(SID))).exists, false);
    assert.strictEqual(await bal(relay.escrowAccount(SID)), 0);
    assert.strictEqual(await bal(pcOf(OWNER)), G);
    await assertLedgerSound();
  });

  const passed = results.filter((x) => x.pass).length;
  console.log(`\n${passed}/${results.length} relay cash loss CF checks passed.`);
  process.exit(passed === results.length ? 0 : 1);
})();
