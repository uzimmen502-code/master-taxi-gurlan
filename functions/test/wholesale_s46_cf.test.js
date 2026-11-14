/**
 * Ulgurji S6 (karta — yetkazish haqini XARIDOR to'laydi) + S4 (sotuvchining o'z yetkazishi) — default codebase,
 * HAQIQIY ledger (Firestore Emulator):
 *
 *   firebase emulators:exec --only firestore --project demo-ulgs46 \
 *     "node functions/test/wholesale_s46_cf.test.js"
 *
 * Qulflanadi:
 *   - paritet: DELIVERY_PAID_BY / DELIVERY_METHOD / SELF_STATUS / buyerPaysDelivery / isNewCard / isSelf ↔ demand
 *   - S6 place: xaridordan AYNAN yetkazish haqi (haq−1 → rad, hech narsa yozilmaydi), sotuvchidan AYNAN AVA ulushi
 *     (AVA−1 → rad); ikki ushlanma bitta eskrouda; belgisiz kvota — ESKI karta (held_seller)
 *   - S6 bekor: yetkazish haqi xaridorga, AVA sotuvchiga, qoldiq — BIR MARTA; AVA 0 — faqat xaridor ushlanmasi
 *   - S6 yetkazildi: SHIP_FUND → eskrouda AVA → RELEASE AVA ga, eskrou 0
 *   - S6 rad: xaridor aybi (qaytish haqi xaridordan, ishlanmagan ulush xaridorga, AVA sotuvchiga, sotuvchi qarzi/blok YO'Q),
 *     kuryer aybi (qaytish haqi kuryerdan)
 *   - S6 yo'qolish: AVA sotuvchiga, yetkazish haqi kuryerdan xaridorga; review (chek yuborilgan) — AVA qoladi, haq baribir qaytadi
 *   - S4 place: hamyon (goodsTotal ushlanadi), karta/bank (pul YO'Q, `payment.status: none`, `avaFeeCollection: statement`);
 *     deliveryFee ≠ 0 — quote_invalid
 *   - S4 yetkazildi (`selfDelivery.status: completed`): hamyon — sotuvchiga sellerPayout + AVA; karta — ledger yo'q; reconcile C
 *   - S4 bekor / rad: hamyon — tovar summasi xaridorga; karta — pul yo'q; qoldiq (bekorda) tiklanadi
 *   - Σdr == Σcr, aktiv == passiv, passenger_credit == bonusBalance
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18767';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-ulgs46';
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
  idempotencyKey: `topupS46:${uid}:${topupSeq += 1}`, kind: 'test_topup',
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

// 10 × 14 000 = 140 000 (G); yetkazish 60 000; AVA 200 bps = 2 800.
const G = 140000;
const FEE = 60000;
const AVA = 2800;
function cardQuote(extra = {}) {
  return {
    buyerId: BUYER, sellerId: SELLER, productId: 'rice', productTitle: 'Гуруч', packId: 'p1', packLabel: '1 кг',
    qty: 10, unitPrice: 14000, goodsTotal: G, deliveryFee: FEE, total: G + FEE, currency: 'UZS',
    delivery: { tariffVersion: 3, zone: 'ZONE_4', actualWeightG: 10000, chargeableWeightG: 10000, dims: null, priceSnapshot: { customerPrice: FEE } },
    avaFeeBps: 200, feeVersion: 4, avaFee: AVA, sellerPayout: G - AVA,
    origin: { regionId: 'xorazm' }, destination: { regionId: 'toshkent_shahri', addressText: 'Chilonzor' },
    paymentMethod: 'card_on_delivery', deliveryMethod: 'ava_courier', deliveryPaidBy: 'buyer', sellerFeeHold: AVA,
    createdAt: clock, expiresAt: new Date(clock.getTime() + 15 * 60 * 1000), used: false,
    ...extra,
  };
}
function selfQuote(paymentMethod, extra = {}) {
  return {
    ...cardQuote(),
    deliveryFee: 0,
    total: G,
    delivery: null,
    destination: { regionId: 'xorazm', districtId: 'gurlan', addressText: 'Gurlan' },
    paymentMethod,
    deliveryMethod: 'self',
    deliveryPaidBy: undefined,
    sellerFeeHold: undefined,
    selfDelivery: { coverage: 'district', dropoff: 'buyer_address' },
    ...extra,
  };
}
const clean = (o) => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined));
async function seed({
  buyerWallet = 0, sellerWallet = 0, courierWallet = 0, quote,
} = {}) {
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
  await db.collection('wholesale_sellers').doc(SELLER).collection('private').doc('payout').set({ cardNumber: '4111111111111111', holderName: 'ALI VALIYEV' });
  await db.collection('wholesale_quotes').doc('q1').set(clean(quote || cardQuote()));
  if (buyerWallet > 0) await topup(BUYER, buyerWallet);
  if (sellerWallet > 0) await topup(SELLER, sellerWallet);
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
async function chain(orderId, before) {
  let prev = before;
  for (let i = 0; i < 10; i += 1) {
    const cur = await orderOf(orderId);
    if (JSON.stringify(cur) === JSON.stringify(prev)) break;
    await quiet(() => api.onStatusChange(prev, cur, orderId));
    prev = cur;
  }
}
async function patchAndChain(id, patch) {
  const before = await orderOf(id);
  await db.collection('wholesale_orders').doc(id).update({ ...patch, historySeq: before.historySeq + 1, updatedAt: clock });
  return chain(id, before);
}
const cancelAs = (id, by) => patchAndChain(id, {
  status: 'cancelled', refundStatus: 'pending', cancelledBy: by, statusUpdatedAt: clock,
});
const refuse = (id, reasonCode) => patchAndChain(id, {
  status: 'refused', refundStatus: 'pending', refusedAt: clock, statusUpdatedAt: clock,
  refusal: {
    by: K1, via: 'courier', reason: '', at: clock, shipmentId: SHIP, legId: 'leg0', reasonCode, confirmedBy: 'buyer',
  },
  returnStatus: 'pending_shipment',
});
async function linkReturn(id, fee) {
  await db.collection('shipments').doc('R1').set({
    orderId: 'lo_ret', ownerId: SELLER, recipientId: SELLER, source: 'wholesale_return', wholesaleOrderId: id, wholesaleReturn: true,
    trackingNumber: 'AVA-26-1114-000002', status: 'awaiting_payment', paymentStatus: 'pending',
    priceSnapshot: { customerPrice: fee, tariffVersion: 4, declaredValue: G }, legIds: ['rleg0'], legCount: 1,
    legAssignments: { rleg0: K1 }, createdAt: clock, updatedAt: clock,
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
  await check('paritet: DELIVERY_PAID_BY / DELIVERY_METHOD / SELF_STATUS / ro\'yxatlar va buyerPaysDelivery / isNewCard / isSelf — demand bilan bir xil', async () => {
    assert.deepStrictEqual({ ...W.DELIVERY_PAID_BY }, { ...WO.DELIVERY_PAID_BY });
    assert.deepStrictEqual({ ...W.DELIVERY_METHOD }, { ...WO.DELIVERY_METHOD });
    assert.deepStrictEqual({ ...W.SELF_STATUS }, { ...WO.SELF_STATUS });
    assert.deepStrictEqual([...W.SELF_COVERAGES], [...WO.SELF_COVERAGES]);
    assert.deepStrictEqual([...W.SELF_DROPOFFS], [...WO.SELF_DROPOFFS]);
    for (const d of [{}, { paymentMethod: 'wallet' }, { paymentMethod: 'card_on_delivery' }, { paymentMethod: 'card_on_delivery', deliveryPaidBy: 'buyer' },
      { paymentMethod: 'card_on_delivery', deliveryPaidBy: 'x' }, { paymentMethod: 'bank_transfer' }, { deliveryMethod: 'self' },
      { paymentMethod: 'card_on_delivery', deliveryMethod: 'self' }, { deliveryMethod: 'drone' }]) {
      assert.strictEqual(W.buyerPaysDelivery(d), WO.deliveryPaidByBuyer(d), JSON.stringify(d));
      assert.strictEqual(W.isNewCard(d), WO.isNewCard(d), JSON.stringify(d));
      assert.strictEqual(W.isSelf(d), WO.isSelf(d), JSON.stringify(d));
      assert.strictEqual(W.deliveryMethodOf(d), WO.deliveryMethodOf(d), JSON.stringify(d));
    }
  });

  // ─── S6 ─────────────────────────────────────────────────────────────
  await check('S6 place: xaridor hamyonidan AYNAN yetkazish haqi, sotuvchidan AYNAN AVA ulushi (chegara: ikkalasi 0 ga tushadi); eskrou = haq+AVA; takror — bitta', async () => {
    await seed({ buyerWallet: FEE, sellerWallet: AVA });
    const r = await place();
    assert.deepStrictEqual([r.ok, r.paymentMethod, r.deliveryMethod], [true, 'card_on_delivery', 'ava_courier']);
    const id = r.orderId;
    assert.deepStrictEqual([await bal(pcOf(BUYER)), await bal(pcOf(SELLER)), await bal(W.escrowAccount(id))], [0, 0, FEE + AVA]);
    assert.deepStrictEqual((await journal(`bonus:${W.holdKey(id)}`)).data().legs, [{ account: pcOf(BUYER), dr: FEE }, { account: W.escrowAccount(id), cr: FEE }]);
    const sj = (await journal(`bonus:${W.sellerFeeHoldKey(id)}`)).data();
    assert.deepStrictEqual([sj.kind, sj.legs], ['wholesale_seller_fee_hold', [{ account: pcOf(SELLER), dr: AVA }, { account: W.escrowAccount(id), cr: AVA }]]);
    assert.deepStrictEqual(await walletLedger(BUYER, 'wholesale_delivery_hold'), [-FEE]);
    assert.deepStrictEqual(await walletLedger(SELLER, 'wholesale_seller_fee_hold'), [-AVA]);
    const o = await orderOf(id);
    assert.deepStrictEqual([o.deliveryPaidBy, o.deliveryMethod, o.payment.status, o.payment.amount, o.payment.payer, o.payment.covers],
      ['buyer', 'ava_courier', 'held', FEE, 'buyer', 'delivery_fee']);
    assert.deepStrictEqual([o.payment.sellerFeeHold.amount, o.payment.sellerFeeHold.payerWalletUid], [AVA, SELLER]);
    assert.strictEqual(o.cardPayment.status, 'awaiting');
    assert.strictEqual((await place()).idempotent, true);
    assert.strictEqual(await journalCount(id), 2);
    await assertLedgerSound();
  });

  await check('S6 place: xaridorda haq−1 → insufficient_balance; sotuvchida AVA−1 → seller_balance_insufficient; HECH NARSA yozilmaydi', async () => {
    await seed({ buyerWallet: FEE - 1, sellerWallet: AVA });
    const e = await quiet(() => expectErr(api.place({ quoteId: 'q1', clientRequestId: 'req-00000001' }, ctx(BUYER)), 'failed-precondition', 'insufficient_balance'));
    assert.deepStrictEqual([e.details.required, e.details.balance], [FEE, FEE - 1]);
    assert.deepStrictEqual([await count('wholesale_orders'), (await stockOf()).packs.p1, await bal(pcOf(SELLER))], [0, 100, AVA]);
    await seed({ buyerWallet: FEE, sellerWallet: AVA - 1 });
    await quiet(() => expectErr(api.place({ quoteId: 'q1', clientRequestId: 'req-00000001' }, ctx(BUYER)), 'failed-precondition', 'seller_balance_insufficient'));
    assert.deepStrictEqual([await count('wholesale_orders'), await bal(pcOf(BUYER)), await bal(pcOf(SELLER))], [0, FEE, AVA - 1]);
    // Muhr buzilgan: cardHold yangi kartada bo'lmasligi kerak / sellerFeeHold ≠ AVA.
    for (const extra of [{ cardHold: FEE + AVA }, { sellerFeeHold: AVA - 1 }]) {
      await seed({ buyerWallet: FEE, sellerWallet: AVA, quote: cardQuote(extra) });
      await quiet(() => expectErr(api.place({ quoteId: 'q1', clientRequestId: 'req-00000001' }, ctx(BUYER)), 'failed-precondition', 'quote_invalid'));
    }
  });

  await check('S6 moslik: belgisiz karta kvotasi (deploydan oldingi) — ESKI semantika: sotuvchidan haq+AVA (held_seller), xaridorga tegilmaydi', async () => {
    await seed({ buyerWallet: 0, sellerWallet: FEE + AVA, quote: cardQuote({ deliveryPaidBy: undefined, sellerFeeHold: undefined, deliveryMethod: undefined }) });
    const id = (await place()).orderId;
    const o = await orderOf(id);
    assert.deepStrictEqual([o.deliveryPaidBy, o.payment.status, o.payment.amount, o.payment.payer], [undefined, 'held_seller', FEE + AVA, 'seller']);
    assert.deepStrictEqual([await bal(pcOf(SELLER)), await bal(W.escrowAccount(id))], [0, FEE + AVA]);
    assert.strictEqual((await journal(`bonus:${W.sellerFeeHoldKey(id)}`)).exists, false);
    await cancelAs(id, 'buyer');
    assert.deepStrictEqual([await bal(pcOf(SELLER)), await bal(pcOf(BUYER))], [FEE + AVA, 0], 'eski: hammasi sotuvchiga');
    await assertLedgerSound();
  });

  await check('S6 bekor (xaridor / sotuvchi rad / muddat): yetkazish haqi xaridorga, AVA sotuvchiga, qoldiq +10 — BIR MARTA; takror va reconcile — yo\'q', async () => {
    for (const by of ['buyer', 'seller', 'system']) {
      await seed({ buyerWallet: FEE, sellerWallet: AVA });
      const id = (await place()).orderId;
      await cancelAs(id, by);
      const o = await orderOf(id);
      assert.deepStrictEqual([o.status, o.refundStatus, o.payment.status, o.payment.sellerFeeRefund, o.stock.restored], ['cancelled', 'done', 'refunded', AVA, true], by);
      assert.deepStrictEqual([await bal(pcOf(BUYER)), await bal(pcOf(SELLER)), await bal(W.escrowAccount(id))], [FEE, AVA, 0], by);
      assert.strictEqual((await stockOf()).packs.p1, 100);
      assert.deepStrictEqual((await journal(`bonus:${W.sellerFeeRefundKey(id)}`)).data().legs, [{ account: W.escrowAccount(id), dr: AVA }, { account: pcOf(SELLER), cr: AVA }]);
      assert.strictEqual((await quiet(() => api.refundOrder(id))).skipped, 'already_refunded');
      clock = new Date(T0.getTime() + 60 * 60 * 1000);
      await quiet(() => api.reconcile());
      assert.strictEqual(await journalCount(id), 4, 'hold×2 + refund×2');
      await assertLedgerSound();
    }
  });

  await check('S6 AVA ulushi 0 (bps 0): faqat xaridor ushlanmasi; sotuvchi hamyoni kerak emas; bekor — faqat xaridorga', async () => {
    await seed({ buyerWallet: FEE, quote: cardQuote({ avaFee: 0, avaFeeBps: 0, sellerPayout: G, sellerFeeHold: 0 }) });
    const id = (await place()).orderId;
    const o = await orderOf(id);
    assert.deepStrictEqual([o.payment.sellerFeeHold, await bal(W.escrowAccount(id))], [null, FEE]);
    await cancelAs(id, 'buyer');
    assert.deepStrictEqual([await bal(pcOf(BUYER)), await journalCount(id)], [FEE, 2]);
    await assertLedgerSound();
  });

  await check('S6 yetkazildi: SHIP_FUND (eskrouda AVA qoladi) → RELEASE AVA → earnings, eskrou 0; sotuvchiga ilova orqali 0', async () => {
    await seed({ buyerWallet: FEE, sellerWallet: AVA });
    const id = (await place()).orderId;
    await shipAndFund(id);
    assert.deepStrictEqual([await bal(W.escrowAccount(id)), (await orderOf(id)).status], [AVA, 'in_delivery']);
    await db.collection('shipments').doc(SHIP).update({ status: 'delivered', deliveredAt: clock, updatedAt: clock });
    const ev = deliveryEvent(SHIP, 'leg0', 48000);
    await quiet(() => relayApi.onCustodyEvent(ev));
    const out = await quiet(() => api.onCustodyEvent(ev));
    assert.deepStrictEqual([out.card, out.released, out.avaFee], [true, AVA, AVA], JSON.stringify(out));
    const o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.payment.status], ['delivered', 'released']);
    assert.deepStrictEqual([await bal(W.escrowAccount(id)), await bal(W.AVA_FEE_ACCOUNT), await bal(pcOf(SELLER))], [0, AVA, 0]);
    await assertLedgerSound();
  });

  await check('S6 rad, XARIDOR aybi: AVA sotuvchiga; qaytish haqi xaridor hamyonidan; ishlanmagan ulush yo\'q; sotuvchi qarzi/karta bloki YO\'Q', async () => {
    await seed({ buyerWallet: FEE + 40000, sellerWallet: AVA });
    const id = (await place()).orderId;
    await shipAndFund(id);
    await refuse(id, 'customer_absent');
    let o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.refundStatus, o.outboundSettlement.status], ['refused', 'pending', 'settled'], 'F ma\'lum emas — kutadi; kuryer haqi kutmaydi');
    await linkReturn(id, 40000);
    o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.refundStatus, o.payment.status, o.payment.sellerFeeRefund, o.payment.refusalRefund],
      ['returning', 'done', 'refusal_settled', AVA, 0]);
    assert.deepStrictEqual([o.walletRefusal.fault, o.walletRefusal.returnFeeCharged, o.walletRefusal.sellerFeeRefunded, o.returnPayment.payer],
      ['buyer', 40000, AVA, 'buyer']);
    assert.deepStrictEqual([await bal(pcOf(BUYER)), await bal(pcOf(SELLER)), await bal(W.escrowAccount(id))], [0, AVA, 0]);
    assert.strictEqual((await db.collection('wholesale_seller_stats').doc(SELLER).get()).exists, false, 'cardBlocked yozilmaydi');
    assert.strictEqual(o.returnDebt, null);
    await assertLedgerSound();
  });

  await check('S6 rad, KURYER aybi: qaytish haqi kuryerdan; AVA sotuvchiga; xaridorga pul harakati yo\'q', async () => {
    await seed({ buyerWallet: FEE, sellerWallet: AVA, courierWallet: 100000 });
    const id = (await place()).orderId;
    await shipAndFund(id);
    await refuse(id, 'courier_problem');
    await linkReturn(id, 40000);
    const o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.returnPayment.payer, o.walletRefusal.sellerFeeRefunded], ['returning', 'courier', AVA]);
    assert.deepStrictEqual([await bal(pcOf(K1)), await bal(pcOf(BUYER)), await bal(pcOf(SELLER))], [60000, 0, AVA]);
    await assertLedgerSound();
  });

  await check('S6 yo\'qolish: AVA sotuvchiga, yetkazish haqi mas\'ul kuryerdan xaridorga (to\'liq); review (chek yuborilgan) — AVA qoladi, haq BARIBIR xaridorga', async () => {
    for (const review of [false, true]) {
      await seed({ buyerWallet: FEE, sellerWallet: AVA, courierWallet: 250000 });
      const id = (await place()).orderId;
      await shipAndFund(id);
      if (review) await db.collection('wholesale_orders').doc(id).update({ 'cardPayment.status': 'receipt_submitted' });
      await quiet(() => markLost({ shipmentId: SHIP, reason: 'kuryer yo\'qotdi', opId: `op-lost-s46${review ? 'r' : 'n'}` }, ctx(ADMIN)));
      const rel = await quiet(() => relayApi.settleLoss(SHIP));
      assert.strictEqual(rel.settled, true, JSON.stringify(rel));
      const out = await quiet(() => api.settleLost(id));
      assert.deepStrictEqual([out.lost, out.review, out.feeRefunded, out.feeOutstanding], [true, review, FEE, 0], JSON.stringify(out));
      const o = await orderOf(id);
      assert.strictEqual(o.lost.deliveryFeeRefunded, FEE);
      assert.strictEqual(await bal(pcOf(BUYER)), FEE, 'yetkazish haqi qaytdi');
      if (review) {
        assert.deepStrictEqual([o.payment.status, o.lost.refunded, await bal(W.escrowAccount(id))], ['lost_review', 0, AVA]);
      } else {
        assert.deepStrictEqual([o.payment.status, o.lost.refundTo, o.lost.refunded, await bal(W.escrowAccount(id))], ['refunded_lost', 'seller', AVA, 0]);
      }
      await assertLedgerSound();
    }
  });

  // ─── S4 ─────────────────────────────────────────────────────────────
  await check('S4 place (hamyon): xaridordan goodsTotal (aynan — chegara), eskrou G, deliveryFee 0, deliveryMethod self + selfDelivery muhri', async () => {
    await seed({ buyerWallet: G, quote: selfQuote('wallet') });
    const id = (await place()).orderId;
    const o = await orderOf(id);
    assert.deepStrictEqual([o.deliveryMethod, o.deliveryFee, o.total, o.payment.status, o.payment.amount], ['self', 0, G, 'held', G]);
    assert.deepStrictEqual(o.selfDelivery, { status: 'pending', coverage: 'district', dropoff: 'buyer_address' });
    assert.deepStrictEqual([await bal(pcOf(BUYER)), await bal(W.escrowAccount(id))], [0, G]);
    const st = (await db.collection('wholesale_orders').doc(id).collection('private').doc('settlement').get()).data();
    assert.strictEqual(st.avaFeeCollection, undefined, 'hamyon — RELEASE da ushlanadi');
    await seed({ buyerWallet: G - 1, quote: selfQuote('wallet') });
    await quiet(() => expectErr(api.place({ quoteId: 'q1', clientRequestId: 'req-00000001' }, ctx(BUYER)), 'failed-precondition', 'insufficient_balance'));
    await assertLedgerSound();
  });

  await check('S4 place (karta / bank): ilovada pul YO\'Q (payment none, ledger yozuvi yo\'q), hamyonlar 0 bo\'lsa ham; settlement statement; haq ≠ 0 — quote_invalid', async () => {
    for (const pm of ['card_on_delivery', 'bank_transfer']) {
      await seed({ quote: selfQuote(pm) });
      const id = (await place()).orderId;
      const o = await orderOf(id);
      assert.deepStrictEqual([o.payment.status, o.payment.amount, o.deliveryPaymentMethod, o.deliveryPaidBy], ['none', 0, undefined, undefined], pm);
      assert.strictEqual(await journalCount(id), 0, pm);
      const st = (await db.collection('wholesale_orders').doc(id).collection('private').doc('settlement').get()).data();
      assert.deepStrictEqual([st.avaFeeCollection, st.avaFee], ['statement', AVA], pm);
      assert.strictEqual((await stockOf()).packs.p1, 90);
      await seed({ buyerWallet: 999999, quote: selfQuote(pm, { deliveryFee: 5000, total: G + 5000 }) });
      await quiet(() => expectErr(api.place({ quoteId: 'q1', clientRequestId: 'req-00000001' }, ctx(BUYER)), 'failed-precondition', 'quote_invalid'));
    }
  });

  await check('S4 yetkazildi (hamyon): completed bo\'lmaguncha — kutadi; completed → sotuvchiga G−AVA, AVA earnings, eskrou 0, delivered; takror — bir marta', async () => {
    await seed({ buyerWallet: G, quote: selfQuote('wallet') });
    const id = (await place()).orderId;
    await patchAndChain(id, { status: 'in_delivery', 'selfDelivery.status': 'in_delivery', statusUpdatedAt: clock });
    assert.strictEqual((await quiet(() => api.releaseGoods(id))).skipped, 'self_not_completed');
    await patchAndChain(id, { 'selfDelivery.status': 'completed', 'selfDelivery.completedAt': clock });
    const o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.payment.status, o.payment.sellerPayoutViaAva], ['delivered', 'released', G - AVA]);
    assert.deepStrictEqual([await bal(pcOf(SELLER)), await bal(W.AVA_FEE_ACCOUNT), await bal(W.escrowAccount(id))], [G - AVA, AVA, 0]);
    assert.deepStrictEqual(await walletLedger(SELLER, 'wholesale_payout'), [G - AVA]);
    assert.strictEqual((await quiet(() => api.releaseGoods(id))).skipped, 'already_released');
    assert.strictEqual(await journalCount(id), 2, 'hold + release');
    await assertLedgerSound();
  });

  await check('S4 yetkazildi (karta): ledger yozuvi YO\'Q, delivered, history avaFeeDue + statement; reconcile C qotganni yopadi', async () => {
    await seed({ quote: selfQuote('card_on_delivery') });
    const id = (await place()).orderId;
    // Trigger yiqilgan: completed yozilgan, lekin onStatusChange chaqirilmagan.
    await db.collection('wholesale_orders').doc(id).update({
      status: 'in_delivery', 'selfDelivery.status': 'completed', 'selfDelivery.completedAt': clock, updatedAt: clock,
    });
    clock = new Date(T0.getTime() + 11 * 60 * 1000);
    const rc = await quiet(() => api.reconcile());
    assert.deepStrictEqual([rc.selfReleaseChecked, rc.released], [1, 1], JSON.stringify(rc));
    const o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.payment.status, o.payment.releaseEntryId, o.payment.sellerPayoutViaAva], ['delivered', 'released', null, 0]);
    const h = (await db.collection('wholesale_orders').doc(id).collection('history').get()).docs.map((d) => d.data()).find((x) => x.event === 'goods_released');
    assert.deepStrictEqual([h.meta.deliveryMethod, h.meta.avaFeeDue, h.meta.avaFeeCollection], ['self', AVA, 'statement']);
    assert.strictEqual(await journalCount(id), 0);
    await assertLedgerSound();
  });

  await check('S4 bekor: hamyon — G xaridorga + qoldiq; karta — pul yo\'q, faqat qoldiq (payment cancelled); takror — yo\'q', async () => {
    await seed({ buyerWallet: G, quote: selfQuote('wallet') });
    let id = (await place()).orderId;
    await cancelAs(id, 'seller');
    assert.deepStrictEqual([(await orderOf(id)).refundStatus, await bal(pcOf(BUYER)), (await stockOf()).packs.p1], ['done', G, 100]);
    await seed({ quote: selfQuote('card_on_delivery') });
    id = (await place()).orderId;
    await cancelAs(id, 'buyer');
    const o = await orderOf(id);
    assert.deepStrictEqual([o.refundStatus, o.payment.status, o.stock.restored, (await stockOf()).packs.p1], ['done', 'cancelled', true, 100]);
    assert.strictEqual((await quiet(() => api.refundOrder(id))).skipped, 'already_refunded');
    assert.strictEqual((await stockOf()).packs.p1, 100, 'qoldiq bir marta');
    assert.strictEqual(await journalCount(id), 0);
    await assertLedgerSound();
  });

  await check('S4 rad: hamyon — G xaridorga (refusal_refunded), qoldiq TIKLANMAYDI (sotuvchi tasdiqlaguncha); karta — pul yo\'q, done; qaytish jo\'natmasi yo\'q', async () => {
    await seed({ buyerWallet: G, quote: selfQuote('wallet') });
    let id = (await place()).orderId;
    await patchAndChain(id, { status: 'in_delivery', 'selfDelivery.status': 'in_delivery' });
    await patchAndChain(id, {
      status: 'refused', refundStatus: 'pending', refusal: { by: SELLER, via: 'self_delivery', reason: 'olmadi' }, 'selfDelivery.status': 'refused',
    });
    let o = await orderOf(id);
    assert.deepStrictEqual([o.refundStatus, o.payment.status, o.payment.refusalRefund, o.stock.restored], ['done', 'refusal_refunded', G, false]);
    assert.deepStrictEqual([await bal(pcOf(BUYER)), await bal(pcOf(SELLER)), await bal(W.escrowAccount(id)), (await stockOf()).packs.p1], [G, 0, 0, 90]);
    assert.strictEqual(o.outboundSettlement, undefined);
    await seed({ quote: selfQuote('card_on_delivery') });
    id = (await place()).orderId;
    await patchAndChain(id, { status: 'in_delivery', 'selfDelivery.status': 'in_delivery' });
    await patchAndChain(id, { status: 'refused', refundStatus: 'pending', refusal: { by: SELLER, via: 'self_delivery', reason: 'olmadi' } });
    o = await orderOf(id);
    assert.deepStrictEqual([o.refundStatus, o.payment.status, o.payment.refusalRefund], ['done', 'refusal_settled', 0]);
    assert.strictEqual(await journalCount(id), 0);
    await assertLedgerSound();
  });

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\nwholesale_s46_cf: ${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
})();
