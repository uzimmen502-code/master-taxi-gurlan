/**
 * Ulgurji BANK O'TKAZMASI (`bank_transfer`, ega qarorlari 2026-11-13/14) — default codebase, HAQIQIY ledger
 * (Firestore Emulator):
 *
 *   firebase emulators:exec --only firestore --project demo-ulgbank \
 *     "node functions/test/wholesale_bank_cf.test.js"
 *
 * Tovar puli ILOVADAN TASHQARIDA — ilova unga aralashmaydi (ega, 2026-11-14). Qulflanadi:
 *   - paritet: to'lov usullari, methodOf, buyerPaysDelivery ↔ demand deliveryPaidByBuyer
 *   - place: xaridor hamyonidan FAQAT yetkazish haqi (chegara: haq − 1 → rad, HECH NARSA yozilmaydi; aynan haq — o'tadi),
 *     kvota muhri (deliveryPaymentMethod / bankHold), idempotent takror; settlement `avaFeeCollection: 'statement'`
 *   - bekor (muddat / rad / xaridor): yetkazish haqi + qoldiq BIR MARTA qaytadi
 *   - yetkazildi: SHIP_FUND → eskrou 0 → releaseBank (ledger yozuvi YO'Q, sotuvchiga/AVA ga 0); eskrou ≠ 0 — anomaliya
 *   - «етказилмади» (xaridor aybi / kuryer aybi / xaridorda mablag' yo'q): tovar refund YO'Q, qaytish haqi aybdordan,
 *     ishlanmagan LEG ulushi xaridorga, qaytgach qoldiq +N
 *   - yo'qolish: tovar refund YO'Q (eskrou 0), yetkazish haqi mas'ul kuryerdan xaridorga
 *   - reconcile B: jo'natmasiz 150 ta `placed` qotgan SHIP_FUND ni siqib chiqarmaydi
 *   - Σdr == Σcr, aktiv == passiv, passenger_credit == bonusBalance
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18380';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-ulgbank';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const settlementLedger = require('../settlement_ledger');
const W = require('../wholesale_orders');
const relay = require('../relay_escrow');
const WO = require('../../functions_demand/core/wholesale_orders');
const DL = require('../../functions_demand/api/logistics');

const BUYER = '998901110001';
const SELLER = '998901234567';
const K1 = '998902220002';
const ADMIN = '998905550005';
const T0 = new Date('2026-11-14T12:00:00Z');
let clock = T0;
const digits = (v) => String(v || '').replace(/\D/g, '');
const canon = (v) => { const d = digits(v); return d.length === 9 ? `998${d}` : d; };
const requireCallerRoles = async (c, roles, msg) => {
  const uid = canon(c && c.auth && c.auth.token && c.auth.token.phone_number);
  const role = ((await db.collection('users').doc(uid).get()).data() || {}).role;
  if (!roles.includes(role)) throw new functions.https.HttpsError('permission-denied', msg);
  return uid;
};
const depsCommon = {
  functions, db, admin, callerPhone: (c) => digits(c.auth.token.phone_number), canonicalUid: canon, settlementLedger, now: () => clock,
};
const api = W.attachWholesaleOrders({}, { ...depsCommon, requireCallerRoles });
const relayApi = relay.attachRelayEscrow({}, { ...depsCommon, notifyUserInApp: async () => {}, requireCallerRoles });
const markLost = DL.makeAdminMarkShipmentLost({ db, now: () => clock });
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
const journal = async (id) => (await db.collection(settlementLedger.COL_JOURNAL).doc(id).get());
const journalCount = async (refId) => (await db.collection(settlementLedger.COL_JOURNAL).where('refId', '==', refId).get()).size;
const walletLedger = async (uid, type) => (await db.collection('users').doc(uid).collection('wallet_ledger').where('type', '==', type).get())
  .docs.map((d) => d.data().amount).sort((a, b) => a - b);
const count = async (col) => (await db.collection(col).get()).size;
async function assertLedgerSound() {
  const rec = await settlementLedger.reconcile(db);
  assert.strictEqual(rec.balanced, true, `Σdr==Σcr buzildi: ${rec.totalDr} != ${rec.totalCr}`);
  assert.strictEqual(rec.identityOk, true, `aktiv/passiv: ${rec.assets} != ${rec.liabilities}`);
  assert.strictEqual(rec.projectionOk, true, `bonusBalance ko'zgusi: ${JSON.stringify(rec.mismatches)}`);
}
let topupSeq = 0;
const topup = (uid, amount) => settlementLedger.postEntry(db, {
  idempotencyKey: `topupB:${uid}:${topupSeq += 1}`, kind: 'test_topup',
  legs: [{ account: 'admin_clearing', dr: amount }, { account: pcOf(uid), cr: amount }],
}, { mirrorBonus: true, walletLedgerType: 'test_topup' });
let quietDepth = 0; let savedLog = null; let savedErr = null;
const quiet = async (fn) => {
  if (quietDepth === 0) { savedLog = console.log; savedErr = console.error; console.log = () => {}; console.error = () => {}; }
  quietDepth += 1;
  try { return await fn(); } finally {
    quietDepth -= 1;
    if (quietDepth === 0) { console.log = savedLog; console.error = savedErr; }
  }
};
async function expectErr(promise, code, reason) {
  try { await promise; } catch (e) {
    assert.strictEqual(e.code, code, `kod: kutilgan ${code}, keldi ${e.code} (${e.message})`);
    if (reason) assert.strictEqual((e.details || {}).reason, reason, `reason: ${JSON.stringify(e.details)}`);
    return e;
  }
  throw new Error(`${code}/${reason} kutilgan edi`);
}

// 10 × 14 000 = 140 000 (G — xaridor sotuvchiga BANK orqali to'laydi, ilovaga kirmaydi); yetkazish 60 000 (hamyondan);
// AVA 200 bps = 2 800 (muhr, hisobot orqali).
const G = 140000;
const FEE = 60000;
const AVA = 2800;
function quoteDoc(extra = {}) {
  return {
    buyerId: BUYER, sellerId: SELLER, productId: 'rice', productTitle: 'Гуруч', packId: 'p1', packLabel: '1 кг',
    qty: 10, unitPrice: 14000, goodsTotal: G, deliveryFee: FEE, total: G + FEE, currency: 'UZS',
    delivery: { tariffVersion: 3, zone: 'ZONE_4', actualWeightG: 10000, chargeableWeightG: 10000, dims: null, priceSnapshot: { customerPrice: FEE } },
    avaFeeBps: 200, feeVersion: 4, avaFee: AVA, sellerPayout: G - AVA,
    origin: { regionId: 'xorazm' }, destination: { regionId: 'toshkent_shahri', addressText: 'Chilonzor' },
    paymentMethod: 'bank_transfer', deliveryPaymentMethod: 'wallet', bankHold: FEE,
    createdAt: clock, expiresAt: new Date(clock.getTime() + 15 * 60 * 1000), used: false,
    ...extra,
  };
}
async function seed({ wallet = FEE, courierWallet = 0, quote = {} } = {}) {
  clock = T0;
  await resetAll();
  await db.collection('module_config').doc('wholesale_orders_all').set({ enabled: true, stage: 'internal', testerIds: [BUYER] });
  await db.collection('users').doc(BUYER).set({ bonusBalance: 0, accountId: 'acc_buyer' });
  await db.collection('users').doc(SELLER).set({ bonusBalance: 0 });
  await db.collection('users').doc(K1).set({ bonusBalance: 0, accountId: 'acc_k1' });
  await db.collection('users').doc(ADMIN).set({ bonusBalance: 0, role: 'admin' });
  await db.collection('wholesale_products').doc('rice').set({ sellerId: SELLER, status: 'active', market: 'wholesale' });
  await db.collection('wholesale_stock').doc('rice').set({ productId: 'rice', sellerId: SELLER, packs: { p1: 100 }, version: 1 });
  await db.collection('wholesale_sellers').doc(SELLER).set({ phone: SELLER, companyName: 'Guruch savdo', approvalStatus: 'approved' });
  await db.collection('wholesale_quotes').doc('q1').set(quoteDoc(quote));
  if (wallet > 0) await topup(BUYER, wallet);
  if (courierWallet > 0) await topup(K1, courierWallet);
}
const place = (req = 'req-00000001') => quiet(() => api.place({ quoteId: 'q1', clientRequestId: req }, ctx(BUYER)));

const SHIP = 'S1';
async function shipAndFund(orderId) {
  await db.collection('shipments').doc(SHIP).set({
    orderId: `lo_${orderId}`, ownerId: SELLER, recipientId: BUYER, source: 'wholesale', wholesaleOrderId: orderId,
    trackingNumber: 'AVA-26-1114-000001', status: 'awaiting_payment', paymentStatus: 'pending',
    priceSnapshot: { customerPrice: FEE, tariffVersion: 3, declaredValue: G }, legIds: ['leg0'], legCount: 1,
    createdAt: clock, updatedAt: clock,
  });
  await db.collection('shipments').doc(SHIP).collection('private').doc('internal').set({
    platformShare: 12000, providerPool: 48000, legPayouts: [{ index: 0, kind: 'direct', amount: 48000 }], tariffVersion: 3,
  });
  const ref = db.collection('wholesale_orders').doc(orderId);
  const before = (await ref.get()).data();
  await ref.update({ shipment: { shipmentId: SHIP, orderId: `lo_${orderId}`, trackingNumber: 'AVA-26-1114-000001', createdAt: clock }, historySeq: 4 });
  const r = await quiet(async () => api.onStatusChange(before, (await ref.get()).data(), orderId));
  assert.strictEqual(r.funded, FEE, JSON.stringify(r));
  await db.collection('shipments').doc(SHIP).update({
    status: 'in_transit', legAssignments: { leg0: K1 }, currentLegId: 'leg0', currentCustodian: { kind: 'provider', id: K1, since: clock },
  });
  await db.collection('demands').doc('leg0').set({ module: 'logistics', status: 'in_progress', assignment: { providerId: K1 }, attributes: { shipmentId: SHIP } });
  await db.collection('demand_matches').doc(`leg0_${K1}`).set({ status: 'in_progress', providerId: K1, contactUnlocked: { recipientPhone: BUYER } });
}
/** Trigger zanjiri: har yozuvdan keyin onStatusChange (before → after), o'zgarish to'xtaguncha. */
async function chain(orderId, before) {
  let prev = before;
  for (let i = 0; i < 10; i += 1) {
    const cur = await orderOf(orderId);
    if (JSON.stringify(cur) === JSON.stringify(prev)) break;
    await quiet(() => api.onStatusChange(prev, cur, orderId));
    prev = cur;
  }
}
/** Demand cancel (muddat / rad / xaridor) natijasi: placed → cancelled + refundStatus pending. */
async function cancelAs(id, by, reason) {
  const before = await orderOf(id);
  await db.collection('wholesale_orders').doc(id).update({
    status: 'cancelled', refundStatus: 'pending', cancelledBy: by, cancelReason: reason || null, statusUpdatedAt: clock, updatedAt: clock,
    historySeq: before.historySeq + 1,
  });
  return chain(id, before);
}
async function refuse(id, reasonCode) {
  const before = await orderOf(id);
  const seq = before.historySeq + 1;
  await db.collection('wholesale_orders').doc(id).update({
    status: 'refused', refundStatus: 'pending', refusedAt: clock, statusUpdatedAt: clock, updatedAt: clock, historySeq: seq,
    refusal: {
      by: K1, via: 'courier', reason: '', at: clock, shipmentId: SHIP, legId: 'leg0', reasonCode, confirmedBy: 'buyer',
    },
    returnStatus: 'pending_shipment',
  });
  return chain(id, before);
}
async function linkReturn(id, fee) {
  await db.collection('shipments').doc('R1').set({
    orderId: 'lo_ret', ownerId: SELLER, recipientId: SELLER, source: 'wholesale_return', wholesaleOrderId: id, wholesaleReturn: true,
    trackingNumber: 'AVA-26-1114-000002', status: 'awaiting_payment', paymentStatus: 'pending',
    priceSnapshot: { customerPrice: fee, tariffVersion: 4, declaredValue: G }, legIds: ['rleg0'], legCount: 1,
    legAssignments: { rleg0: K1 }, createdAt: clock, updatedAt: clock,
  });
  await db.collection('shipments').doc('R1').collection('private').doc('internal').set({
    platformShare: Math.floor(fee / 5), providerPool: fee - Math.floor(fee / 5), legPayouts: [{ index: 0, kind: 'direct', amount: fee - Math.floor(fee / 5) }], tariffVersion: 4,
  });
  const before = await orderOf(id);
  await db.collection('wholesale_orders').doc(id).update({
    returnShipment: { shipmentId: 'R1', orderId: 'lo_ret', legId: 'rleg0', trackingNumber: 'AVA-26-1114-000002', fee, tariffVersion: 4, courierId: K1, createdAt: clock },
    returnStatus: 'awaiting_payment',
  });
  return chain(id, before);
}
const deliveryEvent = (id, legId, payout) => ({
  shipmentId: id, legId, orderId: 'lo_x', ownerId: SELLER, kind: 'delivery', completesLegId: legId,
  completedLegProviderId: K1, completedLegPayout: payout, legIndex: 0, legCount: 1, deliversShipment: true,
});

(async () => {
  await check('paritet: to\'lov usullari / methodOf / buyerPaysDelivery / yetkazish to\'lash usullari — demand bilan bir xil', async () => {
    assert.deepStrictEqual({ ...W.PAYMENT_METHOD }, { ...WO.PAYMENT_METHOD });
    assert.deepStrictEqual([...W.DELIVERY_PAYMENT_METHODS], [...WO.DELIVERY_PAYMENT_METHODS]);
    for (const d of [{}, { paymentMethod: 'wallet' }, { paymentMethod: 'card_on_delivery' }, { paymentMethod: 'bank_transfer' }, { paymentMethod: 'x' }]) {
      assert.strictEqual(W.methodOf(d), WO.methodOf(d), JSON.stringify(d));
      assert.strictEqual(W.buyerPaysDelivery(d), WO.deliveryPaidByBuyer(d), JSON.stringify(d));
    }
  });

  await check('place (bank): xaridor hamyonidan FAQAT yetkazish haqi (aynan 60 000 — chegara); tovar puli ushlanmaydi; muhr va settlement', async () => {
    await seed({ wallet: FEE });
    const r = await place();
    assert.deepStrictEqual([r.ok, r.status, r.paymentMethod, r.total], [true, 'placed', 'bank_transfer', G + FEE]);
    const id = r.orderId;
    assert.strictEqual(await bal(pcOf(BUYER)), 0);
    assert.strictEqual(await bonusOf(BUYER), 0);
    assert.strictEqual(await bal(W.escrowAccount(id)), FEE, 'eskrouda FAQAT yetkazish haqi');
    const j = (await journal(`bonus:${W.holdKey(id)}`)).data();
    assert.strictEqual(j.kind, 'wholesale_delivery_hold');
    assert.deepStrictEqual(j.legs, [{ account: pcOf(BUYER), dr: FEE }, { account: W.escrowAccount(id), cr: FEE }]);
    assert.deepStrictEqual(await walletLedger(BUYER, 'wholesale_delivery_hold'), [-FEE]);
    const o = await orderOf(id);
    assert.deepStrictEqual([o.paymentMethod, o.deliveryPaymentMethod, o.payment.status, o.payment.amount, o.payment.payer, o.payment.covers],
      ['bank_transfer', 'wallet', 'held', FEE, 'buyer', 'delivery_fee']);
    assert.deepStrictEqual([o.goodsTotal, o.deliveryFee, o.cardPayment], [G, FEE, undefined]);
    const st = (await db.collection('wholesale_orders').doc(id).collection('private').doc('settlement').get()).data();
    assert.deepStrictEqual([st.avaFee, st.avaFeeBps, st.sellerPayout, st.avaFeeCollection], [AVA, 200, G - AVA, 'statement']);
    assert.strictEqual((await stockOf()).packs.p1, 90);
    // Takror (o'sha clientRequestId) — o'sha buyurtma, ikkinchi ushlanma yo'q.
    const again = await place();
    assert.deepStrictEqual([again.orderId, again.idempotent], [id, true]);
    assert.strictEqual(await journalCount(id), 1);
    await assertLedgerSound();
  });

  await check('place (bank): hamyon = haq − 1 → insufficient_balance (required = 60 000), HECH NARSA yozilmaydi', async () => {
    await seed({ wallet: FEE - 1 });
    const e = await quiet(() => expectErr(api.place({ quoteId: 'q1', clientRequestId: 'req-00000001' }, ctx(BUYER)), 'failed-precondition', 'insufficient_balance'));
    assert.deepStrictEqual([e.details.required, e.details.balance], [FEE, FEE - 1]);
    assert.strictEqual(await count('wholesale_orders'), 0);
    assert.strictEqual((await stockOf()).packs.p1, 100);
    assert.strictEqual((await db.collection('wholesale_quotes').doc('q1').get()).data().used, false);
    assert.strictEqual(await bal(pcOf(BUYER)), FEE - 1);
  });

  await check('place (bank): muhr buzilgan — deliveryPaymentMethod cash → unsupported; bankHold ≠ haq / haq 0 → quote_invalid', async () => {
    for (const [extra, reason] of [
      [{ deliveryPaymentMethod: 'cash' }, 'delivery_payment_method_unsupported'],
      [{ bankHold: FEE - 1 }, 'quote_invalid'],
      [{ deliveryFee: 0, total: G, bankHold: 0 }, 'quote_invalid'],
    ]) {
      await seed({ wallet: 300000, quote: extra });
      await quiet(() => expectErr(api.place({ quoteId: 'q1', clientRequestId: 'req-00000001' }, ctx(BUYER)), 'failed-precondition', reason));
      assert.strictEqual(await count('wholesale_orders'), 0, JSON.stringify(extra));
      assert.strictEqual(await bal(pcOf(BUYER)), 300000);
    }
  });

  await check('bekor (bank to\'lovi muddati / sotuvchi rad / xaridor): yetkazish haqi + qoldiq BIR MARTA; takror va reconcile — ikkinchi yo\'q', async () => {
    for (const [by, reason] of [['system', 'bank_payment_timeout'], ['seller', 'seller_rejected'], ['buyer', null]]) {
      await seed({ wallet: FEE });
      const id = (await place()).orderId;
      await cancelAs(id, by, reason);
      const o = await orderOf(id);
      assert.deepStrictEqual([o.status, o.refundStatus, o.payment.status, o.stock.restored], ['cancelled', 'done', 'refunded', true], by);
      assert.strictEqual(await bal(pcOf(BUYER)), FEE, by);
      assert.strictEqual(await bal(W.escrowAccount(id)), 0);
      assert.strictEqual((await stockOf()).packs.p1, 100);
      assert.deepStrictEqual((await journal(`bonus:${W.refundKey(id)}`)).data().legs, [{ account: W.escrowAccount(id), dr: FEE }, { account: pcOf(BUYER), cr: FEE }]);
      const r2 = await quiet(() => api.refundOrder(id));
      assert.strictEqual(r2.skipped, 'already_refunded');
      clock = new Date(T0.getTime() + 60 * 60 * 1000);
      await quiet(() => api.reconcile());
      assert.strictEqual(await bal(pcOf(BUYER)), FEE);
      assert.strictEqual(await journalCount(id), 2, 'hold + refund');
      await assertLedgerSound();
    }
  });

  let deliveredId;
  await check('yetkazildi: SHIP_FUND (eskrou → 0) → relay RELEASE (kuryer) + releaseBank: ledger yozuvi YO\'Q, sotuvchiga/AVA ga 0, delivered', async () => {
    await seed({ wallet: FEE });
    const id = (await place()).orderId;
    deliveredId = id;
    await shipAndFund(id);
    assert.strictEqual(await bal(W.escrowAccount(id)), 0);
    assert.strictEqual(await bal(W.shipmentEscrowAccount(SHIP)), FEE);
    assert.strictEqual((await orderOf(id)).status, 'in_delivery');
    await db.collection('shipments').doc(SHIP).update({ status: 'delivered', deliveredAt: clock, updatedAt: clock });
    const ev = deliveryEvent(SHIP, 'leg0', 48000);
    await quiet(() => relayApi.onCustodyEvent(ev));
    const out = await quiet(() => api.onCustodyEvent(ev));
    assert.deepStrictEqual([out.bank, out.released, out.avaFeeDue], [true, 0, AVA], JSON.stringify(out));
    const o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.payment.status, o.payment.sellerPayoutViaAva, o.payment.releaseEntryId], ['delivered', 'released', 0, null]);
    assert.ok(o.deliveredAt, 'deliveredAt — hisobot davri shundan');
    assert.strictEqual((await journal(W.releaseKey(id))).exists, false, 'tovar RELEASE yozuvi yo\'q');
    assert.strictEqual(await bal(pcOf(SELLER)), 0, 'sotuvchiga ilova orqali pul yo\'q');
    assert.strictEqual(await bal(W.AVA_FEE_ACCOUNT), 0, 'AVA ulushi hozir olinmaydi (hisobot)');
    assert.strictEqual(await bal(W.shipmentEscrowAccount(SHIP)), 0, 'kuryer haqi relay orqali');
    const h = (await db.collection('wholesale_orders').doc(id).collection('history').get()).docs.map((d) => d.data()).find((x) => x.event === 'goods_released');
    assert.deepStrictEqual([h.meta.paymentMethod, h.meta.avaFeeDue, h.meta.avaFeeCollection], ['bank_transfer', AVA, 'statement']);
    // Takror custody hodisasi / reconcile — o'zgarish yo'q.
    assert.strictEqual((await quiet(() => api.onCustodyEvent(ev))).skipped, 'already_released');
    await assertLedgerSound();
  });

  await check('yetkazildi: eskrou 0 emas (ortiqcha pul) — anomaliya, holat in_delivery qoladi, pul YO\'Q', async () => {
    await seed({ wallet: FEE });
    const id = (await place()).orderId;
    await shipAndFund(id);
    await settlementLedger.postEntry(db, {
      idempotencyKey: 'inject:esc', kind: 'test_inject', legs: [{ account: 'admin_clearing', dr: 5 }, { account: W.escrowAccount(id), cr: 5 }],
    });
    await db.collection('shipments').doc(SHIP).update({ status: 'delivered', deliveredAt: clock, updatedAt: clock });
    const out = await quiet(() => api.releaseGoods(id));
    assert.deepStrictEqual([out.skipped, out.anomaly], ['escrow_not_zero', true]);
    const o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.releaseAnomaly.code], ['in_delivery', 'escrow_not_zero']);
  });

  await check('«етказилмади», XARIDOR aybi: tovar refund YO\'Q; qaytish haqi F xaridor hamyonidan; ishlanmagan ulush yo\'q; qaytgach qoldiq +N', async () => {
    await seed({ wallet: FEE + 50000 });
    const id = (await place()).orderId;
    await shipAndFund(id);
    await refuse(id, 'customer_absent');
    let o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.refundStatus], ['refused', 'pending'], 'F ma\'lum emas — pul yo\'q');
    assert.strictEqual(o.outboundSettlement.status, 'settled', 'kuryer haqi kutmaydi');
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), 48000);
    await linkReturn(id, 40000);
    o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.refundStatus, o.payment.status, o.payment.refusalRefund, o.payment.refusalEntryId],
      ['returning', 'done', 'refusal_settled', 0, null]);
    assert.deepStrictEqual([o.walletRefusal.fault, o.walletRefusal.goodsRefunded, o.walletRefusal.returnFee, o.walletRefusal.returnFeeCharged, o.walletRefusal.returnFeeOutstanding],
      ['buyer', null, 40000, 40000, 0]);
    assert.strictEqual(o.outsideRefundRequired, undefined, 'ega 2026-11-14: tovar puli bo\'yicha belgi YO\'Q');
    assert.strictEqual(await bal(pcOf(BUYER)), 50000 - 40000, 'faqat qaytish haqi ushlandi; yetkazish haqi qaytmaydi');
    assert.strictEqual((await journal(`bonus:${W.refusedKey(id)}`)).exists, false, 'tovar refund yozuvi yo\'q');
    assert.deepStrictEqual(await walletLedger(BUYER, 'wholesale_refusal_refund'), []);
    assert.strictEqual(await bal(W.escrowAccount(id)), 0);
    assert.strictEqual(await bal(relay.escrowAccount('R1')), 40000);
    assert.strictEqual(await bal(pcOf(SELLER)), 0);
    await db.collection('shipments').doc('R1').update({ status: 'delivered', deliveredAt: clock, updatedAt: clock });
    const ev = deliveryEvent('R1', 'rleg0', 32000);
    await quiet(() => relayApi.onCustodyEvent(ev));
    const back = await quiet(() => api.onCustodyEvent(ev));
    assert.deepStrictEqual([back.returned, back.stockRestored], [true, true]);
    assert.strictEqual((await stockOf()).packs.p1, 100);
    await assertLedgerSound();
  });

  await check('«етказилмади», XARIDOR aybi, hamyon 0: qaytish haqi — returnDebt (payer buyer), manfiyga tushmaydi; to\'ldirgach reconcile yopadi', async () => {
    await seed({ wallet: FEE });
    const id = (await place()).orderId;
    await shipAndFund(id);
    await refuse(id, 'customer_refused');
    await linkReturn(id, 40000);
    let o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.refundStatus, o.returnDebt.payer, o.returnDebt.amount], ['refused', 'done', 'buyer', 40000]);
    assert.strictEqual(await bal(pcOf(BUYER)), 0);
    await topup(BUYER, 40000);
    clock = new Date(T0.getTime() + 60 * 60 * 1000);
    await quiet(() => api.reconcile());
    o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.returnPayment.status, o.returnDebt], ['returning', 'funded', null]);
    assert.strictEqual(await bal(pcOf(BUYER)), 0);
    await assertLedgerSound();
  });

  await check('«етказилмади», KURYER aybi: refund kutmaydi (done darhol), F kuryer hamyonidan, xaridorga pul harakati yo\'q', async () => {
    await seed({ wallet: FEE, courierWallet: 100000 });
    const id = (await place()).orderId;
    await shipAndFund(id);
    await refuse(id, 'courier_problem');
    let o = await orderOf(id);
    assert.deepStrictEqual([o.refundStatus, o.walletRefusal.fault, o.walletRefusal.goodsRefunded], ['done', 'courier', null]);
    await linkReturn(id, 40000);
    o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.returnPayment.payer, o.returnPayment.status], ['returning', 'courier', 'funded']);
    assert.strictEqual(await bal(pcOf(K1)), 100000 - 40000);
    assert.strictEqual(await bal(pcOf(BUYER)), 0);
    await assertLedgerSound();
  });

  await check('yo\'qolish (bank): tovar refund YO\'Q (eskrou 0, refunded 0); yetkazish haqi mas\'ul kuryerdan xaridorga; lost', async () => {
    await seed({ wallet: FEE, courierWallet: 250000 });
    const id = (await place()).orderId;
    await shipAndFund(id);
    const r = await quiet(() => markLost({ shipmentId: SHIP, reason: 'kuryer yo\'qotdi', opId: 'op-lost-b01' }, ctx(ADMIN)));
    assert.strictEqual(r.paymentStatus, 'loss_pending');
    const rel = await quiet(() => relayApi.settleLoss(SHIP));
    assert.strictEqual(rel.settled, true, JSON.stringify(rel));
    const out = await quiet(() => api.settleLost(id));
    assert.deepStrictEqual([out.lost, out.refunded, out.refundTo, out.feeRefunded, out.feeOutstanding], [true, 0, null, FEE, 0], JSON.stringify(out));
    const o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.lost.refunded, o.lost.refundTo, o.lost.deliveryFeeRefunded, o.payment.lostRefundEntryId],
      ['lost', 0, null, FEE, null]);
    assert.strictEqual(o.outsideRefundRequired, undefined);
    assert.strictEqual((await journal(`bonus:${W.lostKey(id)}`)).exists, false, 'tovar refund yozuvi yo\'q');
    assert.strictEqual(await bal(pcOf(BUYER)), FEE, 'xaridorga faqat yetkazish haqi');
    assert.strictEqual(await bal(W.escrowAccount(id)), 0);
    assert.strictEqual((await quiet(() => api.settleLost(id))).skipped, 'already_lost');
    await assertLedgerSound();
  });

  await check('reconcile B: jo\'natmasiz 150 ta placed (qaror/bank kutilmoqda) — qotgan SHIP_FUND (jo\'natma bog\'langan) baribir to\'lanadi', async () => {
    await seed({ wallet: FEE });
    const id = (await place()).orderId;
    const batch = db.batch();
    for (let i = 0; i < 150; i += 1) {
      batch.set(db.collection('wholesale_orders').doc(`00${String(i).padStart(3, '0')}`), {
        status: 'placed', shipment: null, paymentMethod: 'bank_transfer', sellerDecision: 'accepted', bankPayment: { status: 'awaiting' }, updatedAt: clock,
      });
    }
    await batch.commit();
    // Trigger yiqilgan: jo'natma bog'langan, lekin onStatusChange chaqirilmagan.
    await db.collection('shipments').doc(SHIP).set({
      orderId: `lo_${id}`, ownerId: SELLER, recipientId: BUYER, source: 'wholesale', wholesaleOrderId: id,
      trackingNumber: 'AVA-26-1114-000001', status: 'awaiting_payment', paymentStatus: 'pending',
      priceSnapshot: { customerPrice: FEE, tariffVersion: 3, declaredValue: G }, legIds: ['leg0'], legCount: 1, createdAt: clock, updatedAt: clock,
    });
    await db.collection('wholesale_orders').doc(id).update({ shipment: { shipmentId: SHIP, createdAt: clock } });
    clock = new Date(T0.getTime() + 11 * 60 * 1000);
    const rc = await quiet(() => api.reconcile());
    assert.deepStrictEqual([rc.shipFundChecked, rc.shipFunded], [1, 1], JSON.stringify(rc));
    assert.strictEqual((await orderOf(id)).status, 'in_delivery');
    assert.strictEqual((await orderOf('00000')).status, 'placed');
    await assertLedgerSound();
  });

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\nwholesale_bank_cf: ${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
})();
