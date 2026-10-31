/**
 * Ulgurji HAMYON buyurtmasi «етказилмади» (ega, 2026-11-01: «тавсияларга розиман») — default codebase,
 * HAQIQIY ledger (Firestore Emulator):
 *
 *   firebase emulators:exec --only firestore --project demo-ulgwallet \
 *     "node functions/test/wholesale_wallet_refusal_cf.test.js"
 *
 * Demand rad natijasi (`writeRefusal`: status refused + refundStatus pending + refusal{by, reasonCode} +
 * returnStatus pending_shipment) — demand testida qulflangan shakl, bu yerda hujjat sifatida yoziladi.
 * Trigger zanjiri — `onStatusChange` har yozuvdan keyin qayta chaqiriladi (Firestore onUpdate kabi).
 *
 * Qulflanadi:
 *   - xaridor aybi (customer_absent / customer_refused): tovar summasi G xaridorga, yetkazish haqi QAYTMAYDI,
 *     qaytish haqi F refunddan ushlanadi (AYNI tranzaksiya), F ma'lum bo'lguncha pul YO'Q; kuryer haqi kutmaydi
 *   - chegara: F == G (refund 0 net); F = G + 1, hamyon 0 → 1 so'm qarz (manfiy YO'Q), reconcile; xaridorda
 *     qo'shimcha balans bo'lsa — undan
 *   - kuryer aybi (courier_problem): G darhol (qaytish jo'natmasini kutmaydi), F — kuryer hamyonidan; yetmasa
 *     qisman + qarz (manfiy YO'Q), qolgan qism faqat to'liq
 *   - `other` / sabab yo'q → anomaliya, pul YO'Q
 *   - idempotentlik: refundOrder / fundReturn parallel va takror — bir marta
 *   - Σdr == Σcr, aktiv == passiv, passenger_credit == bonusBalance
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18282';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-ulgwallet';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const settlementLedger = require('../settlement_ledger');
const W = require('../wholesale_orders');
const relay = require('../relay_escrow');

const BUYER = '998901110001';
const SELLER = '998901234567';
const K1 = '998902220002';
const T0 = new Date('2026-11-01T12:00:00Z');
let clock = T0;
const digits = (v) => String(v || '').replace(/\D/g, '');
const canon = (v) => { const d = digits(v); return d.length === 9 ? `998${d}` : d; };
const depsCommon = {
  functions, db, admin, callerPhone: (c) => digits(c.auth.token.phone_number), canonicalUid: canon, settlementLedger, now: () => clock,
};
const api = W.attachWholesaleOrders({}, depsCommon);
const relayApi = relay.attachRelayEscrow({}, {
  ...depsCommon, notifyUserInApp: async () => {}, requireCallerRoles: async () => { throw new Error('not used'); },
});
const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
async function resetAll() {
  const url = `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`;
  const res = await fetch(url, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator tozalanmadi: ${res.status}`);
}
const pcOf = (uid) => settlementLedger.passengerCreditAccount(uid);
const bal = async (acc) => ((await db.collection(settlementLedger.COL_ACCOUNTS).doc(acc).get()).data() || {}).balance || 0;
const bonusOf = async (uid) => ((await db.collection('users').doc(uid).get()).data() || {}).bonusBalance || 0;
const orderOf = async (id) => (await db.collection('wholesale_orders').doc(id).get()).data();
const stockOf = async () => (await db.collection('wholesale_stock').doc('rice').get()).data();
const journal = async (id) => (await db.collection(settlementLedger.COL_JOURNAL).doc(id).get()).data();
const journalCount = async (refId) => (await db.collection(settlementLedger.COL_JOURNAL).where('refId', '==', refId).get()).size;
const walletLedger = async (uid, type) => (await db.collection('users').doc(uid).collection('wallet_ledger').where('type', '==', type).get())
  .docs.map((d) => d.data().amount).sort((a, b) => a - b);
async function assertLedgerSound() {
  const rec = await settlementLedger.reconcile(db);
  assert.strictEqual(rec.balanced, true, `Σdr==Σcr buzildi: ${rec.totalDr} != ${rec.totalCr}`);
  assert.strictEqual(rec.identityOk, true, `aktiv/passiv: ${rec.assets} != ${rec.liabilities}`);
  assert.strictEqual(rec.projectionOk, true, `bonusBalance ko'zgusi: ${JSON.stringify(rec.mismatches)}`);
}
let topupSeq = 0;
const topup = (uid, amount) => settlementLedger.postEntry(db, {
  idempotencyKey: `topupW:${uid}:${topupSeq += 1}`, kind: 'test_topup',
  legs: [{ account: 'admin_clearing', dr: amount }, { account: pcOf(uid), cr: amount }],
});
// Ichma-ich / parallel chaqiruvda ham console tiklanadi (hisoblagich bilan).
let quietDepth = 0; let savedLog = null; let savedErr = null;
const quiet = async (fn) => {
  if (quietDepth === 0) { savedLog = console.log; savedErr = console.error; console.log = () => {}; console.error = () => {}; }
  quietDepth += 1;
  try { return await fn(); } finally {
    quietDepth -= 1;
    if (quietDepth === 0) { console.log = savedLog; console.error = savedErr; }
  }
};

// 10 × 14 000 = 140 000 (G); yetkazish 60 000; jami 200 000. Qaytish narxi F (standart 40 000).
const G = 140000;
const FEE = 60000;
const TOTAL = G + FEE;
function quoteDoc(extra = {}) {
  return {
    buyerId: BUYER, sellerId: SELLER, productId: 'rice', productTitle: 'Гуруч', packId: 'p1', packLabel: '1 кг',
    qty: 10, unitPrice: 14000, goodsTotal: G, deliveryFee: FEE, total: TOTAL, currency: 'UZS',
    delivery: { tariffVersion: 3, zone: 'ZONE_4', actualWeightG: 10000, chargeableWeightG: 10000, dims: null, priceSnapshot: { customerPrice: FEE } },
    avaFeeBps: 250, feeVersion: 3, avaFee: 3500, sellerPayout: 136500,
    origin: { regionId: 'xorazm' }, destination: { regionId: 'toshkent_shahri', addressText: 'Chilonzor' },
    paymentMethod: 'wallet',
    createdAt: clock, expiresAt: new Date(clock.getTime() + 15 * 60 * 1000), used: false,
    ...extra,
  };
}
const K1_ACC = 'acc_k1';
const capsDebt = async () => ((((await db.collection('provider_capabilities').doc(K1_ACC).get()).data() || {}).debt) || {}).logistics || 0;
async function seed({ buyerExtra = 0, courierWallet = 0, courierAccount = true } = {}) {
  clock = T0;
  await resetAll();
  await db.collection('module_config').doc('wholesale_orders_all').set({ enabled: true, stage: 'internal', testerIds: [BUYER] });
  for (const u of [BUYER, SELLER, K1]) await db.collection('users').doc(u).set({ bonusBalance: 0 });
  if (courierAccount) await db.collection('users').doc(K1).set({ accountId: K1_ACC }, { merge: true });
  await db.collection('wholesale_products').doc('rice').set({ sellerId: SELLER, status: 'active', market: 'wholesale' });
  await db.collection('wholesale_stock').doc('rice').set({ productId: 'rice', sellerId: SELLER, packs: { p1: 100 }, version: 1 });
  await db.collection('wholesale_sellers').doc(SELLER).set({ phone: SELLER, companyName: 'Guruch savdo', approvalStatus: 'approved' });
  await db.collection('wholesale_quotes').doc('q1').set(quoteDoc());
  await topup(BUYER, TOTAL + buyerExtra);
  if (courierWallet > 0) await topup(K1, courierWallet);
}
const SHIP = 'S1';
async function seedShipment(orderId) {
  await db.collection('shipments').doc(SHIP).set({
    orderId: `lo_${orderId}`, ownerId: SELLER, recipientId: BUYER, source: 'wholesale', wholesaleOrderId: orderId,
    trackingNumber: 'AVA-26-1101-000001', status: 'awaiting_payment', paymentStatus: 'pending',
    priceSnapshot: { customerPrice: FEE, tariffVersion: 3, declaredValue: G }, legIds: ['leg0'], legCount: 1,
    createdAt: clock, updatedAt: clock,
  });
  await db.collection('shipments').doc(SHIP).collection('private').doc('internal').set({
    platformShare: 12000, providerPool: 48000, legPayouts: [{ index: 0, kind: 'direct', amount: 48000 }], tariffVersion: 3,
  });
}
/** Trigger zanjiri: har yozuvdan keyin onStatusChange (before → after), o'zgarish to'xtaguncha. */
async function chain(orderId, before) {
  let prev = before;
  const outs = [];
  for (let i = 0; i < 10; i += 1) {
    const cur = await orderOf(orderId);
    if (JSON.stringify(cur) === JSON.stringify(prev)) break;
    outs.push(await quiet(() => api.onStatusChange(prev, cur, orderId)));
    prev = cur;
  }
  return outs;
}
async function placeAndFund() {
  const r = await quiet(() => api.place({ quoteId: 'q1', clientRequestId: 'req-00000001' }, ctx(BUYER)));
  assert.strictEqual(r.paymentMethod, 'wallet');
  const id = r.orderId;
  await seedShipment(id);
  const ref = db.collection('wholesale_orders').doc(id);
  const before = await orderOf(id);
  await ref.update({ shipment: { shipmentId: SHIP, orderId: `lo_${id}`, trackingNumber: 'AVA-26-1101-000001', createdAt: clock }, historySeq: 2 });
  const f = await quiet(async () => api.onStatusChange(before, await orderOf(id), id));
  assert.strictEqual(f.funded, FEE, JSON.stringify(f));
  await db.collection('shipments').doc(SHIP).update({
    status: 'in_transit', legAssignments: { leg0: K1 }, currentLegId: 'leg0', currentCustodian: { kind: 'provider', id: K1, since: clock },
  });
  await db.collection('demands').doc('leg0').set({ module: 'logistics', status: 'in_progress', assignment: { providerId: K1 }, attributes: { shipmentId: SHIP } });
  await db.collection('demand_matches').doc(`leg0_${K1}`).set({ status: 'in_progress', providerId: K1, contactUnlocked: { recipientPhone: BUYER } });
  assert.strictEqual(await bal(W.escrowAccount(id)), G, 'eskrouda tovar summasi');
  return id;
}
/** Demand `writeRefusal` natijasi (wholesale_failed.js finalizeInTx → wholesale_card.js writeRefusal). */
async function refuse(id, reasonCode) {
  const before = await orderOf(id);
  const seq = before.historySeq + 1;
  const refusal = {
    by: K1, via: 'courier', reason: '', at: clock, shipmentId: SHIP, legId: 'leg0', confirmedBy: 'buyer', confirmedById: BUYER, deliveryFailedSeq: 1,
  };
  if (reasonCode !== undefined) refusal.reasonCode = reasonCode;
  await db.collection('wholesale_orders').doc(id).update({
    status: 'refused', refundStatus: 'pending', refusedAt: clock, statusUpdatedAt: clock, updatedAt: clock, historySeq: seq,
    refusal, returnStatus: 'pending_shipment',
  });
  await db.collection('wholesale_orders').doc(id).collection('history').doc(String(seq)).set({ seq, from: 'in_delivery', to: 'refused', actor: 'buyer', at: clock });
  return chain(id, before);
}
/** Demand `ensureWholesaleReturnShipment` natijasi. */
async function linkReturn(id, fee) {
  await db.collection('shipments').doc('R1').set({
    orderId: 'lo_ret', ownerId: SELLER, recipientId: SELLER, source: 'wholesale_return', wholesaleOrderId: id, wholesaleReturn: true,
    trackingNumber: 'AVA-26-1101-000002', status: 'awaiting_payment', paymentStatus: 'pending',
    priceSnapshot: { customerPrice: fee, tariffVersion: 4, declaredValue: G }, legIds: ['rleg0'], legCount: 1,
    legAssignments: { rleg0: K1 }, createdAt: clock, updatedAt: clock,
  });
  await db.collection('shipments').doc('R1').collection('private').doc('internal').set({
    platformShare: Math.floor(fee / 5), providerPool: fee - Math.floor(fee / 5), legPayouts: [{ index: 0, kind: 'direct', amount: fee - Math.floor(fee / 5) }], tariffVersion: 4,
  });
  const before = await orderOf(id);
  await db.collection('wholesale_orders').doc(id).update({
    returnShipment: { shipmentId: 'R1', orderId: 'lo_ret', legId: 'rleg0', trackingNumber: 'AVA-26-1101-000002', fee, tariffVersion: 4, courierId: K1, createdAt: clock },
    returnStatus: 'awaiting_payment',
  });
  return chain(id, before);
}
async function deliverReturn() {
  await db.collection('shipments').doc('R1').update({ status: 'delivered', deliveredAt: clock, updatedAt: clock });
  const ev = {
    shipmentId: 'R1', legId: 'rleg0', orderId: 'lo_ret', ownerId: SELLER, kind: 'delivery', completesLegId: 'rleg0',
    completedLegProviderId: K1, completedLegPayout: 32000, legIndex: 0, legCount: 1, deliversShipment: true,
  };
  await quiet(() => relayApi.onCustodyEvent(ev));
  return quiet(() => api.onCustodyEvent(ev));
}

(async () => {
  await check('paritet: hamyon ayb jadvali (demand WALLET_REASONS bilan AYNAN shu 3 kalit, `other` YO\'Q)', async () => {
    assert.deepStrictEqual({ ...W.WALLET_REFUSAL_FAULT }, { customer_absent: 'buyer', customer_refused: 'buyer', courier_problem: 'courier' });
    assert.strictEqual(settlementLedger.accountTypeOf(W.returnEscrowAccount('x')), 'liability');
    assert.notStrictEqual(W.returnHoldRestKey('x'), W.returnHoldKey('x'));
  });

  await check('XARIDOR AYBI (customer_absent): F kutiladi (pul YO\'Q), kuryer haqi kutmaydi; F=40 000 → G xaridorga, F ushlanadi, yetkazish haqi qaytmaydi; FUND → returning → returned + qoldiq', async () => {
    await seed();
    const id = await placeAndFund();
    assert.strictEqual(await bal(pcOf(BUYER)), 0);
    await refuse(id, 'customer_absent');
    let o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.refundStatus], ['refused', 'pending'], 'F ma\'lum emas — pul yo\'q');
    assert.strictEqual(await bal(pcOf(BUYER)), 0);
    assert.strictEqual(await bal(W.escrowAccount(id)), G);
    assert.ok(!o.refundAnomaly && !o.returnAnomaly);
    // Kuryer haqi kutmaydi: chiqish jo'natmasi yopildi (o'zgarmagan qoida — ishlangan LEG kuryerga).
    assert.strictEqual(o.outboundSettlement.status, 'settled');
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), 48000);
    assert.strictEqual(await bal(relay.escrowAccount(SHIP)), 0);
    assert.strictEqual((await quiet(() => api.refundOrder(id))).skipped, 'awaiting_return_fee');
    await linkReturn(id, 40000);
    o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.refundStatus, o.returnStatus, o.returnPayment.status, o.returnPayment.payer, o.returnDebt || null],
      ['returning', 'done', 'in_transit', 'funded', 'buyer', null]);
    assert.deepStrictEqual(
      [o.walletRefusal.fault, o.walletRefusal.reasonCode, o.walletRefusal.goodsRefunded, o.walletRefusal.deliveryFeeRefunded, o.walletRefusal.returnFee, o.walletRefusal.returnFeeCharged, o.walletRefusal.returnFeeOutstanding],
      ['buyer', 'customer_absent', G, 0, 40000, 40000, 0],
    );
    assert.strictEqual(await bal(pcOf(BUYER)), G - 40000, 'G − F; yetkazish haqi 60 000 qaytmadi');
    assert.strictEqual(await bonusOf(BUYER), G - 40000);
    assert.deepStrictEqual(await walletLedger(BUYER, 'wholesale_refusal_refund'), [G]);
    assert.deepStrictEqual(await walletLedger(BUYER, 'wholesale_return_hold'), [-40000]);
    assert.strictEqual(await bal(W.escrowAccount(id)), 0);
    assert.strictEqual(await bal(W.returnEscrowAccount(id)), 0);
    assert.strictEqual(await bal(relay.escrowAccount('R1')), 40000);
    assert.strictEqual(await bal(pcOf(SELLER)), 0, 'sotuvchiga pul yo\'q');
    assert.strictEqual(await bal(W.AVA_FEE_ACCOUNT), 0, 'avaFee olinmadi');
    assert.deepStrictEqual((await journal(`bonus:${W.refusedKey(id)}`)).legs, [{ account: W.escrowAccount(id), dr: G }, { account: pcOf(BUYER), cr: G }]);
    assert.deepStrictEqual((await journal(`bonus:${W.returnHoldKey(id)}`)).legs, [{ account: pcOf(BUYER), dr: 40000 }, { account: W.returnEscrowAccount(id), cr: 40000 }]);
    assert.strictEqual((await stockOf()).packs.p1, 90);
    const out = await deliverReturn();
    assert.deepStrictEqual([out.returned, out.stockRestored], [true, true]);
    assert.strictEqual((await stockOf()).packs.p1, 100);
    assert.strictEqual((await orderOf(id)).status, 'returned');
    const h = (await db.collection('wholesale_orders').doc(id).collection('history').get()).docs.map((d) => d.data().event).filter(Boolean);
    for (const ev of ['ship_funded', 'outbound_settled', 'refusal_settled', 'return_funded', 'goods_returned']) assert.ok(h.includes(ev), ev);
    await assertLedgerSound();
  });

  await check('chegara: F == G (customer_refused) → refund G, ushlanma G, xaridor net 0, qarz YO\'Q', async () => {
    await seed();
    const id = await placeAndFund();
    await refuse(id, 'customer_refused');
    await linkReturn(id, G);
    const o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.walletRefusal.returnFeeCharged, o.walletRefusal.returnFeeOutstanding, o.returnDebt || null], ['returning', G, 0, null]);
    assert.strictEqual(await bal(pcOf(BUYER)), 0);
    await assertLedgerSound();
  });

  await check('chegara: F = G + 1, hamyon 0 → G ushlanadi, 1 so\'m qarz (manfiy YO\'Q), trigger aylanmaydi; reconcile to\'ldirilmaguncha — pul yo\'q; +1 → to\'liq qolgan qism → returning', async () => {
    await seed();
    const id = await placeAndFund();
    await refuse(id, 'customer_absent');
    await linkReturn(id, G + 1);
    let o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.refundStatus, o.returnStatus, o.returnPayment.status, o.returnPayment.held, o.returnDebt.amount, o.returnDebt.payer, o.returnDebt.attempts],
      ['refused', 'done', 'awaiting_payment', 'partial', G, 1, 'buyer', 1]);
    assert.deepStrictEqual([o.walletRefusal.returnFeeCharged, o.walletRefusal.returnFeeOutstanding], [G, 1]);
    assert.strictEqual(await bal(pcOf(BUYER)), 0, 'manfiyga tushmadi');
    assert.strictEqual(await bal(W.returnEscrowAccount(id)), G);
    assert.strictEqual(await bal(relay.escrowAccount('R1')), 0, 'qaytish hali to\'lanmagan');
    assert.strictEqual((await quiet(() => api.onStatusChange(o, o, id))).skipped, 'no_refund_needed', 'qarz bilan trigger qayta urinmaydi');
    let rc = await quiet(() => api.reconcile());
    assert.deepStrictEqual([rc.returnFundChecked, rc.returnFunded, rc.returnDebts], [1, 0, 1]);
    o = await orderOf(id);
    assert.deepStrictEqual([o.returnDebt.attempts, o.returnPayment.held], [2, G]);
    assert.strictEqual(await bal(pcOf(BUYER)), 0);
    await topup(BUYER, 1);
    rc = await quiet(() => api.reconcile());
    assert.deepStrictEqual([rc.returnFundChecked, rc.returnFunded], [1, 1]);
    o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.returnDebt, o.returnPayment.status, o.walletRefusal.returnFeeCharged, o.walletRefusal.returnFeeOutstanding], ['returning', null, 'funded', G + 1, 0]);
    assert.ok(o.returnDebtSettledAt);
    assert.deepStrictEqual((await journal(`bonus:${W.returnHoldRestKey(id)}`)).legs, [{ account: pcOf(BUYER), dr: 1 }, { account: W.returnEscrowAccount(id), cr: 1 }]);
    assert.strictEqual(await bal(pcOf(BUYER)), 0);
    assert.strictEqual(await bal(relay.escrowAccount('R1')), G + 1);
    assert.strictEqual((await db.collection('wholesale_seller_stats').doc(SELLER).get()).exists, false, 'sotuvchi karta blokiga tegilmadi');
    await assertLedgerSound();
  });

  await check('xaridorda qo\'shimcha balans (5 000): F = G + 3 000 → hammasi bir tranzaksiyada, qoldiq 2 000, qarz yo\'q', async () => {
    await seed({ buyerExtra: 5000 });
    const id = await placeAndFund();
    await refuse(id, 'customer_refused');
    await linkReturn(id, G + 3000);
    const o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.walletRefusal.returnFeeCharged, o.returnDebt || null], ['returning', G + 3000, null]);
    assert.strictEqual(await bal(pcOf(BUYER)), 2000);
    await assertLedgerSound();
  });

  await check('KURYER AYBI (courier_problem): G DARHOL (qaytish jo\'natmasisiz), hisoblagich yo\'q; F=40 000 kuryer hamyonidan (50 000) → returning; xaridor yetkazish haqini ham qaytarib olmaydi', async () => {
    await seed({ courierWallet: 50000 });
    const id = await placeAndFund();
    await refuse(id, 'courier_problem');
    let o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.refundStatus, o.walletRefusal.fault, o.walletRefusal.returnFee, o.walletRefusal.returnFeePayer], ['refused', 'done', 'courier', null, 'courier']);
    assert.strictEqual(await bal(pcOf(BUYER)), G);
    assert.strictEqual(await bal(W.escrowAccount(id)), 0);
    await linkReturn(id, 40000);
    o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.returnPayment.status, o.returnPayment.payer, o.returnPayment.payerWalletUid, o.walletRefusal.returnFeeCharged], ['returning', 'funded', 'courier', K1, 40000]);
    assert.strictEqual(await bal(pcOf(K1)), 10000);
    assert.strictEqual(await bonusOf(K1), 10000);
    assert.deepStrictEqual(await walletLedger(K1, 'wholesale_return_hold'), [-40000]);
    assert.strictEqual(await bal(pcOf(BUYER)), G, 'xaridorga tegilmadi');
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), 48000, 'kuryer chiqish LEG haqi — o\'zgarmagan qoida');
    await assertLedgerSound();
  });

  await check('KURYER AYBI, hamyon yetmaydi (15 000 < 40 000) — ega 2026-11-01: 15 000 kuryerdan, 25 000 KURYER QARZI (debt.logistics) + AVA qoplaydi (admin_clearing), qaytish DARHOL returning; manfiy YO\'Q; tarix + audit', async () => {
    await seed({ courierWallet: 15000 });
    const id = await placeAndFund();
    await refuse(id, 'courier_problem');
    await linkReturn(id, 40000);
    const o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.returnStatus, o.returnPayment.status, o.returnPayment.held, o.returnPayment.avaCover, o.returnPayment.avaCoverStatus, o.returnDebt || null],
      ['returning', 'in_transit', 'funded', 15000, 25000, 'posted', null]);
    assert.deepStrictEqual([o.courierReturnDebt.amount, o.courierReturnDebt.accountId, o.courierReturnDebt.courierId, o.courierReturnDebt.coveredBy], [25000, K1_ACC, K1, 'ava']);
    assert.deepStrictEqual([o.walletRefusal.returnFeeCharged, o.walletRefusal.returnFeeCourierDebt, o.walletRefusal.returnFeeAvaCovered, o.walletRefusal.returnFeeOutstanding], [15000, 25000, 25000, 0]);
    assert.strictEqual(await bal(pcOf(K1)), 0, 'manfiyga tushmadi');
    assert.strictEqual(await bonusOf(K1), 0);
    assert.strictEqual(await capsDebt(), 25000, 'yo\'qolish precedenti bilan AYNI qarz maydoni');
    assert.strictEqual(await bal(relay.escrowAccount('R1')), 40000, 'qaytish to\'liq to\'landi');
    assert.strictEqual(await bal(W.returnEscrowAccount(id)), 0);
    assert.deepStrictEqual((await journal(W.returnAvaCoverKey(id))).legs,
      [{ account: 'admin_clearing', dr: 25000, cr: 0 }, { account: W.returnEscrowAccount(id), dr: 0, cr: 25000 }]);
    const h = (await db.collection('wholesale_orders').doc(id).collection('history').get()).docs.map((d) => d.data().event).filter(Boolean);
    for (const ev of ['return_fee_courier_debt', 'return_fee_ava_covered', 'return_funded']) assert.ok(h.includes(ev), ev);
    const au = (await db.collection('logistics_audit').doc(`wholesale_return_ava_cover_${id}`).get()).data();
    assert.deepStrictEqual([au.amount, au.courierAccountId, au.entryId], [25000, K1_ACC, W.returnAvaCoverKey(id)]);
    // Takror: fundReturn ×2 parallel + reconcile — qarz va AVA qoplamasi BIR marta.
    const before = await journalCount(id);
    await quiet(() => Promise.allSettled([api.fundReturn(id), api.fundReturn(id)]));
    await quiet(() => api.reconcile());
    assert.strictEqual(await journalCount(id), before);
    assert.strictEqual(await capsDebt(), 25000);
    await assertLedgerSound();
  });

  await check('KURYER AYBI, hamyon 0: hammasi (40 000) qarz + AVA; fundReturn ×2 PARALLEL — qarz +40 000 BIR marta, jurnal bitta', async () => {
    await seed();
    const id = await placeAndFund();
    await refuse(id, 'courier_problem');
    // Trigger'siz bog'lab, ikki yo'l bir vaqtda.
    await db.collection('shipments').doc('R1').set({
      ownerId: SELLER, recipientId: SELLER, source: 'wholesale_return', wholesaleOrderId: id, status: 'awaiting_payment', paymentStatus: 'pending',
      priceSnapshot: { customerPrice: 40000 }, legIds: ['rleg0'], legCount: 1, createdAt: clock, updatedAt: clock,
    });
    await db.collection('wholesale_orders').doc(id).update({ returnShipment: { shipmentId: 'R1', fee: 40000, createdAt: clock }, returnStatus: 'awaiting_payment' });
    const rs = await quiet(() => Promise.allSettled([api.fundReturn(id), api.fundReturn(id)]));
    assert.ok(rs.every((x) => x.status === 'fulfilled'), JSON.stringify(rs.map((x) => (x.reason || {}).message)));
    const o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.returnPayment.held, o.returnPayment.avaCover, o.courierReturnDebt.amount], ['returning', 0, 40000, 40000]);
    assert.strictEqual(await capsDebt(), 40000);
    assert.strictEqual(await bal(pcOf(K1)), 0);
    assert.strictEqual(await bal(relay.escrowAccount('R1')), 40000);
    assert.strictEqual((await db.collection(settlementLedger.COL_JOURNAL).where('kind', '==', 'wholesale_return_ava_cover').get()).size, 1);
    await assertLedgerSound();
  });

  await check('KURYER AYBI: accountId yo\'q → anomaliya (pul YO\'Q, qarz yo\'q, qaytish to\'lanmaydi); hamyoni yetsa — accountId kerak emas', async () => {
    await seed({ courierWallet: 1000, courierAccount: false });
    const id = await placeAndFund();
    await refuse(id, 'courier_problem');
    await linkReturn(id, 40000);
    const o = await orderOf(id);
    assert.deepStrictEqual([o.status, (o.returnAnomaly || {}).code], ['refused', 'courier_account_missing']);
    assert.strictEqual(await bal(pcOf(K1)), 1000, 'kuryerdan ham yechilmadi');
    assert.strictEqual(await bal(W.returnEscrowAccount(id)), 0);
    assert.strictEqual(await bal(relay.escrowAccount('R1')), 0);
    await seed({ courierWallet: 50000, courierAccount: false });
    const id2 = await placeAndFund();
    await refuse(id2, 'courier_problem');
    await linkReturn(id2, 40000);
    assert.strictEqual((await orderOf(id2)).status, 'returning');
    await assertLedgerSound();
  });

  await check('ESKI holat (55542134 yozgan): kuryer qisman + returnDebt{payer:courier} → reconcile qolganini qarz + AVA bilan yopadi, returning', async () => {
    await seed({ courierWallet: 15000 });
    const id = await placeAndFund();
    await refuse(id, 'courier_problem');
    // Eski kod natijasini qo'lda: 15 000 ushlangan (wholesaleReturnHold), 25 000 returnDebt.
    await db.collection('shipments').doc('R1').set({
      ownerId: SELLER, recipientId: SELLER, source: 'wholesale_return', wholesaleOrderId: id, status: 'awaiting_payment', paymentStatus: 'pending',
      priceSnapshot: { customerPrice: 40000 }, legIds: ['rleg0'], legCount: 1, createdAt: clock, updatedAt: clock,
    });
    await settlementLedger.postEntry(db, {
      idempotencyKey: `bonus:${W.returnHoldKey(id)}`, kind: 'wholesale_return_hold', refType: 'wholesale_order', refId: id,
      legs: [{ account: pcOf(K1), dr: 15000 }, { account: W.returnEscrowAccount(id), cr: 15000 }],
    });
    await db.collection('wholesale_orders').doc(id).update({
      returnShipment: { shipmentId: 'R1', fee: 40000, createdAt: clock },
      returnStatus: 'awaiting_payment',
      returnPayment: { status: 'partial', amount: 40000, held: 15000, payer: 'courier', payerWalletUid: K1 },
      returnDebt: { amount: 25000, payer: 'courier', courierId: K1, attempts: 1 },
    });
    const rc = await quiet(() => api.reconcile());
    assert.strictEqual(rc.returnFunded, 1, JSON.stringify(rc));
    const o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.returnDebt, o.returnPayment.avaCover, o.courierReturnDebt.amount], ['returning', null, 25000, 25000]);
    assert.strictEqual(await capsDebt(), 25000);
    assert.strictEqual(await bal(pcOf(K1)), 0);
    await assertLedgerSound();
  });

  await check('sabab `other` / yo\'q (eski yo\'l) — hamyonda ANOMALIYA: pul YO\'Q, refundStatus pending, eskrou G', async () => {
    for (const code of ['other', undefined]) {
      await seed();
      const id = await placeAndFund();
      await refuse(id, code);
      const r = await quiet(() => api.refundOrder(id));
      assert.deepStrictEqual([r.skipped, r.anomaly], ['wallet_refusal_reason_invalid', true], String(code));
      const o = await orderOf(id);
      assert.strictEqual(o.refundStatus, 'pending');
      assert.strictEqual(await bal(pcOf(BUYER)), 0);
      assert.strictEqual(await bal(W.escrowAccount(id)), G);
      await assertLedgerSound();
    }
  });

  await check('IDEMPOTENTLIK / POYGA: refundOrder ×3 parallel + reconcile; fundReturn ×2 parallel — pul BIR marta', async () => {
    await seed({ courierWallet: 50000 });
    const id = await placeAndFund();
    // Trigger'siz: holatni yozamiz, keyin bir vaqtda bir necha yo'l.
    await db.collection('wholesale_orders').doc(id).update({
      status: 'refused', refundStatus: 'pending', statusUpdatedAt: clock, updatedAt: clock,
      refusal: { by: K1, via: 'courier', reason: '', at: clock, shipmentId: SHIP, legId: 'leg0', reasonCode: 'courier_problem' },
      returnStatus: 'pending_shipment',
    });
    const rs = await quiet(() => Promise.allSettled([api.refundOrder(id), api.refundOrder(id), api.refundOrder(id)]));
    const ok = rs.filter((x) => x.status === 'fulfilled' && x.value.refunded === G);
    assert.strictEqual(ok.length, 1, JSON.stringify(rs.map((x) => (x.value || {}).skipped || (x.reason || {}).message)));
    assert.strictEqual(await bal(pcOf(BUYER)), G);
    assert.strictEqual((await quiet(() => api.refundOrder(id))).skipped, 'already_refunded');
    // Qaytish bog'landi (triggersiz), ikki fundReturn bir vaqtda.
    await db.collection('shipments').doc('R1').set({
      ownerId: SELLER, recipientId: SELLER, source: 'wholesale_return', wholesaleOrderId: id, status: 'awaiting_payment', paymentStatus: 'pending',
      priceSnapshot: { customerPrice: 40000 }, legIds: ['rleg0'], legCount: 1, createdAt: clock, updatedAt: clock,
    });
    await db.collection('wholesale_orders').doc(id).update({ returnShipment: { shipmentId: 'R1', fee: 40000, createdAt: clock }, returnStatus: 'awaiting_payment' });
    const fr = await quiet(() => Promise.allSettled([api.fundReturn(id), api.fundReturn(id)]));
    assert.ok(fr.every((x) => x.status === 'fulfilled'), JSON.stringify(fr.map((x) => (x.reason || {}).message)));
    assert.strictEqual(await bal(pcOf(K1)), 10000, 'kuryerdan bir marta');
    assert.strictEqual(await bal(relay.escrowAccount('R1')), 40000);
    assert.strictEqual((await orderOf(id)).status, 'returning');
    const before = await journalCount(id);
    await quiet(() => api.reconcile());
    await quiet(() => api.refundOrder(id));
    await quiet(() => api.fundReturn(id));
    assert.strictEqual(await journalCount(id), before, 'takror — yangi jurnal yozuvi yo\'q');
    await assertLedgerSound();
  });

  await check('karta oqimi O\'ZGARMAGAN: karta buyurtma rad → settleRefusalInTx (walletRefusal maydoni yo\'q)', async () => {
    // To'liq karta zanjiri wholesale_card_cf.test.js da; bu yerda faqat dispetcherlik.
    await seed();
    const id = await placeAndFund();
    await db.collection('wholesale_orders').doc(id).update({ paymentMethod: 'card_on_delivery', status: 'refused', refundStatus: 'pending' });
    const r = await quiet(() => api.refundOrder(id));
    assert.deepStrictEqual([r.skipped, r.anomaly], ['refusal_payment_invalid', true], 'karta yo\'li (held_seller kutadi)');
    assert.strictEqual((await orderOf(id)).walletRefusal, undefined);
  });

  const passed = results.filter((r) => r.pass).length;
  console.log(`\nwholesale_wallet_refusal (default): ${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
})();
