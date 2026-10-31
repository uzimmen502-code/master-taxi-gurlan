/**
 * Ulgurji — YO'QOLGAN POSILKA, xaridor tomoni (ega, 2026-10-31), HAQIQIY ledger (Firestore Emulator).
 * To'liq zanjir AYNI emulatorda: demand `adminMarkShipmentLost` → relay `settleLoss` (jonli bilan
 * bir xil kod, O'ZGARTIRILMAGAN) → `onWholesaleShipmentLoss` / reconcile (`settleLost`).
 *
 *   firebase emulators:exec --only firestore --project demo-ulgloss \
 *     "node functions/test/wholesale_lost_cf.test.js"
 *
 * Qulflanadi:
 *   - hamyon: loss_pending — hech narsa; loss_settled → xaridorga goodsTotal BIR MARTA (parallel trigger +
 *     reconcile), eskrou 0, qoldiq o'zgarmaydi, buyurtma lost (+history), sotuvchiga eskroudan 0
 *     (u faqat kuryerdan G oladi), yetkazish haqi relay'da (qaytarilmaydi)
 *   - kuryer hamyoni bo'sh (G qarz bo'ladi) — xaridor baribir qaytarib oladi; reconcile 10 daqiqa chegarasi
 *   - karta (to'lanmagan): avaFee sotuvchiga qaytadi, xaridor hamyoniga tegilmaydi
 *   - karta (chek yuborilgan / payment_dispute): pul YO'Q, lost_review, eskrou qoladi
 *   - eskrou mos emas — anomaliya, pul YO'Q, reconcile qayta urinmaydi
 *   - yetkazilgan buyurtma / boshqa jo'natma / loss_settled emas — tegilmaydi
 *   - Σdr == Σcr, aktiv == passiv, passenger_credit == bonusBalance
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18377';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-ulgloss';
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
const T0 = new Date('2026-10-31T12:00:00Z');
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
const accExists = async (acc) => (await db.collection(settlementLedger.COL_ACCOUNTS).doc(acc).get()).exists;
const bonusOf = async (uid) => ((await db.collection('users').doc(uid).get()).data() || {}).bonusBalance || 0;
const orderOf = async (id) => (await db.collection('wholesale_orders').doc(id).get()).data();
const shipOf = async (id = SHIP) => (await db.collection('shipments').doc(id).get()).data();
const stockOf = async () => (await db.collection('wholesale_stock').doc('rice').get()).data();
const journal = async (id) => (await db.collection(settlementLedger.COL_JOURNAL).doc(id).get());
const historyOf = async (id) => (await db.collection('wholesale_orders').doc(id).collection('history').get()).docs.map((d) => d.data());
const walletLedger = async (uid, type) => (await db.collection('users').doc(uid).collection('wallet_ledger').where('type', '==', type).get()).docs.map((d) => d.data());
async function assertLedgerSound() {
  const rec = await settlementLedger.reconcile(db);
  assert.strictEqual(rec.balanced, true, `Σdr==Σcr buzildi: ${rec.totalDr} != ${rec.totalCr}`);
  assert.strictEqual(rec.identityOk, true, `aktiv/passiv: ${rec.assets} != ${rec.liabilities}`);
  assert.strictEqual(rec.projectionOk, true, `bonusBalance ko'zgusi: ${JSON.stringify(rec.mismatches)}`);
}
let topupSeq = 0;
const topup = (uid, amount) => settlementLedger.postEntry(db, {
  idempotencyKey: `topupL:${uid}:${topupSeq += 1}`, kind: 'test_topup',
  legs: [{ account: 'admin_clearing', dr: amount }, { account: pcOf(uid), cr: amount }],
}, { mirrorBonus: true, walletLedgerType: 'test_topup' });
const quiet = async (fn) => {
  const l = console.log; const e = console.error; const w = console.warn;
  console.log = () => {}; console.error = () => {}; console.warn = () => {};
  try { return await fn(); } finally { console.log = l; console.error = e; console.warn = w; }
};

// 10 × 14 000 = 140 000 (G = declaredValue); yetkazish 60 000; AVA 3 500. Karta: sotuvchi ushlanmasi 63 500.
const GOODS = 140000;
const FEE = 60000;
const AVA = 3500;
function quoteDoc(card) {
  return {
    buyerId: BUYER, sellerId: SELLER, productId: 'rice', productTitle: 'Гуруч', packId: 'p1', packLabel: '1 кг',
    qty: 10, unitPrice: 14000, goodsTotal: GOODS, deliveryFee: FEE, total: GOODS + FEE, currency: 'UZS',
    delivery: { tariffVersion: 3, zone: 'ZONE_4', actualWeightG: 10000, chargeableWeightG: 10000, dims: null, priceSnapshot: { customerPrice: FEE } },
    avaFeeBps: 250, feeVersion: 3, avaFee: AVA, sellerPayout: GOODS - AVA,
    origin: { regionId: 'xorazm' }, destination: { regionId: 'toshkent_shahri', addressText: 'Chilonzor' },
    ...(card ? { paymentMethod: 'card_on_delivery', cardHold: FEE + AVA } : {}),
    createdAt: clock, expiresAt: new Date(clock.getTime() + 15 * 60 * 1000), used: false,
  };
}
async function seed({ card = false, courierWallet = 200000 } = {}) {
  clock = T0;
  await resetAll();
  await db.collection('module_config').doc('wholesale_orders_all').set({ enabled: true, stage: 'internal', testerIds: [BUYER] });
  for (const u of [BUYER, SELLER]) await db.collection('users').doc(u).set({ bonusBalance: 0 });
  await db.collection('users').doc(K1).set({ bonusBalance: 0, accountId: 'acc_k1' });
  await db.collection('users').doc(ADMIN).set({ bonusBalance: 0, role: 'admin' });
  await db.collection('wholesale_products').doc('rice').set({ sellerId: SELLER, status: 'active', market: 'wholesale' });
  await db.collection('wholesale_stock').doc('rice').set({ productId: 'rice', sellerId: SELLER, packs: { p1: 100 }, version: 1 });
  await db.collection('wholesale_sellers').doc(SELLER).set({ phone: SELLER, companyName: 'Guruch savdo', approvalStatus: 'approved' });
  if (card) {
    await db.collection('wholesale_sellers').doc(SELLER).collection('private').doc('payout')
      .set({ cardNumber: '4111111111111111', holderName: 'ALI VALIYEV', last4: '1111', version: 1 });
    await topup(SELLER, 100000);
  } else {
    await topup(BUYER, 300000);
  }
  if (courierWallet > 0) await topup(K1, courierWallet);
  await db.collection('wholesale_quotes').doc('q1').set(quoteDoc(card));
}
const place = () => quiet(() => api.place({ quoteId: 'q1', clientRequestId: 'req-00000001' }, ctx(BUYER)));

const SHIP = 'S1';
/** Demand `ensureWholesaleShipment` + default SHIP_FUND + relay acceptLeg/scanHandover maydonlari. */
async function shipAndFund(orderId) {
  await db.collection('shipments').doc(SHIP).set({
    orderId: `lo_${orderId}`, ownerId: SELLER, recipientId: BUYER, source: 'wholesale', wholesaleOrderId: orderId,
    trackingNumber: 'AVA-26-1031-000001', status: 'awaiting_payment', paymentStatus: 'pending',
    priceSnapshot: { customerPrice: FEE, tariffVersion: 3, declaredValue: GOODS }, legIds: ['leg0'], legCount: 1,
    createdAt: clock, updatedAt: clock,
  });
  await db.collection('shipments').doc(SHIP).collection('private').doc('internal').set({
    platformShare: 12000, providerPool: 48000, legPayouts: [{ index: 0, kind: 'direct', amount: 48000 }], tariffVersion: 3,
  });
  const ref = db.collection('wholesale_orders').doc(orderId);
  const before = (await ref.get()).data();
  await ref.update({ shipment: { shipmentId: SHIP, orderId: `lo_${orderId}`, trackingNumber: 'AVA-26-1031-000001', createdAt: clock }, historySeq: 2 });
  const r = await quiet(async () => api.onStatusChange(before, (await ref.get()).data(), orderId));
  assert.strictEqual(r.funded, FEE, JSON.stringify(r));
  await db.collection('shipments').doc(SHIP).update({
    status: 'in_transit', legAssignments: { leg0: K1 }, currentLegId: 'leg0', currentCustodian: { kind: 'provider', id: K1, since: clock },
  });
  await db.collection('demands').doc('leg0').set({ module: 'logistics', status: 'in_progress', assignment: { providerId: K1 }, attributes: { shipmentId: SHIP } });
}
/** Admin yo'qolgan deb belgilaydi (demand, haqiqiy callable) → `loss_pending` + incident. */
async function adminMarksLost() {
  const r = await quiet(() => markLost({ shipmentId: SHIP, reason: 'kuryer yo\'qotdi', opId: 'op-lost-001' }, ctx(ADMIN)));
  assert.deepStrictEqual([r.status, r.paymentStatus, r.goodsValue], ['lost', 'loss_pending', GOODS]);
}
/** Relay `onLogisticsShipmentUpdate` (jonli kod) — `loss_pending` → `loss_settled`. */
async function relaySettles() {
  const r = await quiet(() => relayApi.settleLoss(SHIP));
  assert.strictEqual(r.settled, true, JSON.stringify(r));
  assert.strictEqual((await shipOf()).paymentStatus, 'loss_settled');
  return r;
}
const lossTrigger = (before, after) => quiet(() => api.onShipmentLossUpdate(before, after));

(async () => {
  await check('paritet: lost holati va o\'tishlari demand jadvali bilan bir xil; kalit/hisob nomlari', async () => {
    assert.strictEqual(W.STATUS.LOST, WO.STATUS.LOST);
    assert.deepStrictEqual([...W.LOST_FROM_STATUSES], [...WO.LOST_FROM_STATUSES]);
    assert.deepStrictEqual({ ...W.LOST_PAYMENT }, { ...WO.LOST_PAYMENT });
    for (const from of W.LOST_FROM_STATUSES) assert.ok(WO.canActorTransition('system', from, W.STATUS.LOST), from);
    assert.ok(WO.isTerminal(W.STATUS.LOST));
    assert.ok(!W.REFUND_STATUSES.includes(W.STATUS.LOST), 'lost — cancelled/refused qaytarish oqimi emas');
    assert.strictEqual(W.lostKey('o1'), 'wholesaleLost:o1');
    assert.strictEqual(W.SHIPMENT_LOSS_SETTLED, 'loss_settled');
  });

  let orderId;
  await check('hamyon: loss_pending — HECH NARSA (trigger ham, settleLost ham); buyurtma in_delivery, eskrou 140 000', async () => {
    await seed();
    orderId = (await place()).orderId;
    await shipAndFund(orderId);
    assert.strictEqual(await bal(W.escrowAccount(orderId)), GOODS);
    const before = await shipOf();
    await adminMarksLost();
    const after = await shipOf();
    assert.deepStrictEqual(await lossTrigger(before, after), { skipped: 'not_loss_settled' });
    assert.deepStrictEqual(await quiet(() => api.settleLost(orderId)), { skipped: 'shipment_loss_pending' });
    const o = await orderOf(orderId);
    assert.deepStrictEqual([o.status, o.payment.status], ['in_delivery', 'held']);
    assert.strictEqual(await bal(W.escrowAccount(orderId)), GOODS);
    assert.strictEqual((await journal(`bonus:${W.lostKey(orderId)}`)).exists, false);
    await assertLedgerSound();
  });

  await check('hamyon: relay loss_settled (sotuvchiga kuryerdan G) → parallel trigger ×2 + settleLost → xaridorga 140 000 BIR MARTA; eskrou 0; lost; qoldiq 90', async () => {
    const before = await shipOf();
    const rel = await relaySettles();
    assert.deepStrictEqual([rel.taken, rel.outstanding], [GOODS, 0]);
    assert.strictEqual(await bal(pcOf(SELLER)), GOODS, 'sotuvchi — FAQAT kuryer kompensatsiyasi');
    assert.strictEqual(await bal(pcOf(K1)), 200000 - GOODS);
    const after = await shipOf();
    const outs = await Promise.all([lossTrigger(before, after), lossTrigger(before, after), quiet(() => api.settleLost(orderId))]);
    assert.strictEqual(outs.filter((r) => r.lost === true).length, 1, JSON.stringify(outs));
    assert.strictEqual(await bal(pcOf(BUYER)), 300000 - (GOODS + FEE) + GOODS, 'xaridor: tovar puli qaytdi, yetkazish haqi — yo\'q');
    assert.strictEqual(await bonusOf(BUYER), 300000 - FEE);
    assert.strictEqual(await bal(W.escrowAccount(orderId)), 0, 'eskrou AYNAN 0');
    assert.strictEqual(await bal(W.shipmentEscrowAccount(SHIP)), 0, 'relay eskrou 0 (relay yopgan)');
    const j = (await journal(`bonus:${W.lostKey(orderId)}`)).data();
    assert.strictEqual(j.kind, 'wholesale_lost_refund');
    assert.deepStrictEqual(j.legs, [{ account: W.escrowAccount(orderId), dr: GOODS }, { account: pcOf(BUYER), cr: GOODS }]);
    const wl = await walletLedger(BUYER, 'wholesale_lost_refund');
    assert.deepStrictEqual([wl.length, wl[0].amount, wl[0].refId], [1, GOODS, orderId]);
    const o = await orderOf(orderId);
    assert.deepStrictEqual([o.status, o.payment.status, o.payment.lostRefund, o.payment.lostRefundEntryId, o.refundStatus],
      ['lost', 'refunded_lost', GOODS, `bonus:${W.lostKey(orderId)}`, 'done']);
    assert.deepStrictEqual([o.lost.shipmentId, o.lost.incidentId, o.lost.refundTo, o.lost.refunded, o.lost.review], [SHIP, SHIP, 'buyer', GOODS, false]);
    assert.deepStrictEqual([o.stock.decremented, o.stock.restored], [true, false]);
    assert.strictEqual((await stockOf()).packs.p1, 90, 'qoldiq TIKLANMAYDI (tovar yo\'q)');
    const h = (await historyOf(orderId)).find((x) => x.event === 'lost_settled');
    assert.deepStrictEqual([h.from, h.to, h.actor, h.meta.refunded, h.meta.incidentId], ['in_delivery', 'lost', 'system', GOODS, SHIP]);
    assert.strictEqual((await historyOf(orderId)).filter((x) => x.event === 'lost_settled').length, 1);
    await assertLedgerSound();
  });

  await check('hamyon: takror trigger / reconcile (+11 daq) / releaseGoods — ikkinchi pul YO\'Q; sotuvchiga eskroudan hech narsa', async () => {
    const s = await shipOf();
    assert.deepStrictEqual(await lossTrigger({ ...s, paymentStatus: 'loss_pending' }, s), { skipped: 'already_lost' });
    clock = new Date(T0.getTime() + 11 * 60 * 1000);
    const rec = await quiet(() => api.reconcile());
    assert.deepStrictEqual([rec.lostChecked, rec.lostSettled, rec.released, rec.failed], [0, 0, 0, 0]);
    assert.deepStrictEqual(await quiet(() => api.releaseGoods(orderId)), { skipped: 'status_lost' });
    assert.strictEqual(await bal(pcOf(BUYER)), 300000 - FEE);
    assert.strictEqual(await bal(pcOf(SELLER)), GOODS);
    assert.strictEqual(await accExists(W.AVA_FEE_ACCOUNT), false, 'AVA ulgurji ulushi olinmadi (sotuv bo\'lmadi)');
    assert.strictEqual(await bal(W.escrowAccount(orderId)), 0);
    await assertLedgerSound();
  });

  await check('hamyon, kuryer hamyoni BO\'SH (G — kuryer qarzi): trigger yiqilgan — reconcile 9 daq → kutadi, 11 daq → xaridorga 140 000', async () => {
    await seed({ courierWallet: 0 });
    orderId = (await place()).orderId;
    await shipAndFund(orderId);
    await adminMarksLost();
    const rel = await relaySettles();
    assert.deepStrictEqual([rel.taken, rel.outstanding], [0, GOODS]);
    assert.strictEqual(await bal(pcOf(SELLER)), 0, 'sotuvchi kompensatsiyasi — kuryer qarzi (admin undiradi)');
    clock = new Date(T0.getTime() + 9 * 60 * 1000);
    let rec = await quiet(() => api.reconcile());
    assert.deepStrictEqual([rec.lostChecked, rec.lostSettled], [0, 0]);
    assert.strictEqual((await orderOf(orderId)).status, 'in_delivery');
    clock = new Date(T0.getTime() + 11 * 60 * 1000);
    rec = await quiet(() => api.reconcile());
    assert.deepStrictEqual([rec.lostChecked, rec.lostSettled, rec.failed], [1, 1, 0]);
    rec = await quiet(() => api.reconcile());
    assert.deepStrictEqual([rec.lostChecked, rec.lostSettled], [0, 0], 'lost — endi in_delivery so\'rovida yo\'q');
    assert.strictEqual(await bal(pcOf(BUYER)), 300000 - FEE);
    assert.strictEqual(await bal(W.escrowAccount(orderId)), 0);
    assert.strictEqual((await orderOf(orderId)).status, 'lost');
    assert.strictEqual((await stockOf()).packs.p1, 90);
    await assertLedgerSound();
  });

  await check('karta (xaridor to\'lamagan): avaFee 3 500 sotuvchiga qaytadi; xaridor hamyoniga tegilmaydi; eskrou 0; lost', async () => {
    await seed({ card: true });
    orderId = (await place()).orderId;
    assert.strictEqual(await bal(pcOf(SELLER)), 100000 - (FEE + AVA));
    await shipAndFund(orderId);
    assert.strictEqual(await bal(W.escrowAccount(orderId)), AVA);
    await adminMarksLost();
    const before = await shipOf();
    await relaySettles();
    const r = await lossTrigger(before, await shipOf());
    assert.deepStrictEqual([r.lost, r.refunded, r.refundTo, r.review], [true, AVA, 'seller', false]);
    assert.strictEqual(await bal(pcOf(SELLER)), 100000 - (FEE + AVA) + GOODS + AVA, 'sotuvchi: kuryerdan G + AVA ulushi qaytdi');
    assert.strictEqual(await bonusOf(SELLER), 100000 - FEE + GOODS);
    assert.strictEqual(await accExists(pcOf(BUYER)), false, 'xaridor hisobiga yozuv yo\'q');
    assert.strictEqual(await bal(W.escrowAccount(orderId)), 0);
    const j = (await journal(`bonus:${W.lostKey(orderId)}`)).data();
    assert.deepStrictEqual(j.legs, [{ account: W.escrowAccount(orderId), dr: AVA }, { account: pcOf(SELLER), cr: AVA }]);
    const o = await orderOf(orderId);
    assert.deepStrictEqual([o.status, o.payment.status, o.lost.refundTo, o.cardPayment.status], ['lost', 'refunded_lost', 'seller', 'awaiting']);
    assert.strictEqual((await stockOf()).packs.p1, 90);
    assert.deepStrictEqual(await lossTrigger(before, await shipOf()), { skipped: 'already_lost' });
    assert.strictEqual(await bal(pcOf(SELLER)), 100000 - FEE + GOODS);
    await assertLedgerSound();
  });

  await check('karta, chek yuborilgan (in_delivery) va payment_dispute: pul YO\'Q — lost_review, eskrou avaFee qoladi, jurnal yo\'q', async () => {
    for (const variant of [{ status: 'in_delivery', cp: 'receipt_submitted' }, { status: 'payment_dispute', cp: 'disputed' }]) {
      await seed({ card: true });
      orderId = (await place()).orderId;
      await shipAndFund(orderId);
      await db.collection('wholesale_orders').doc(orderId).update({ status: variant.status, 'cardPayment.status': variant.cp });
      await adminMarksLost();
      const before = await shipOf();
      await relaySettles();
      const sellerBefore = await bal(pcOf(SELLER));
      const r = await lossTrigger(before, await shipOf());
      assert.deepStrictEqual([r.lost, r.refunded, r.refundTo, r.review, r.from], [true, 0, null, true, variant.status], JSON.stringify(r));
      const o = await orderOf(orderId);
      assert.deepStrictEqual([o.status, o.payment.status, o.payment.lostRefundEntryId, o.refundStatus], ['lost', 'lost_review', null, null]);
      assert.strictEqual(await bal(W.escrowAccount(orderId)), AVA, 'eskrou admin qaroriga qadar qoladi');
      assert.strictEqual(await bal(pcOf(SELLER)), sellerBefore);
      assert.strictEqual((await journal(`bonus:${W.lostKey(orderId)}`)).exists, false);
      const h = (await historyOf(orderId)).find((x) => x.event === 'lost_settled');
      assert.deepStrictEqual([h.from, h.meta.review, h.meta.cardPaymentStatus], [variant.status, true, variant.cp]);
      assert.deepStrictEqual(await quiet(() => api.settleLost(orderId)), { skipped: 'already_lost' });
      await assertLedgerSound();
    }
  });

  await check('eskrou mos emas (140 001): anomaliya — pul YO\'Q, holat in_delivery, lostAnomaly; reconcile qayta URINMAYDI', async () => {
    await seed();
    orderId = (await place()).orderId;
    await shipAndFund(orderId);
    await settlementLedger.postEntry(db, {
      idempotencyKey: 'tamper:1', kind: 'test_topup',
      legs: [{ account: 'admin_clearing', dr: 1 }, { account: W.escrowAccount(orderId), cr: 1 }],
    });
    await adminMarksLost();
    const before = await shipOf();
    await relaySettles();
    const r = await lossTrigger(before, await shipOf());
    assert.deepStrictEqual([r.skipped, r.anomaly, r.escrow], ['escrow_mismatch', true, GOODS + 1]);
    const o = await orderOf(orderId);
    assert.deepStrictEqual([o.status, o.payment.status, o.lostAnomaly.code], ['in_delivery', 'held', 'escrow_mismatch']);
    assert.strictEqual(await bal(W.escrowAccount(orderId)), GOODS + 1);
    assert.strictEqual(await bal(pcOf(BUYER)), 300000 - (GOODS + FEE));
    clock = new Date(T0.getTime() + 30 * 60 * 1000);
    const rec = await quiet(() => api.reconcile());
    assert.deepStrictEqual([rec.lostChecked, rec.lostSettled], [0, 0]);
    await assertLedgerSound();
  });

  await check('tegilmaydi: yetkazilgan buyurtma; boshqa (oddiy) jo\'natma loss_settled; ulgurji jo\'natma boshqa o\'zgarishi', async () => {
    await seed();
    orderId = (await place()).orderId;
    await shipAndFund(orderId);
    await db.collection('shipments').doc(SHIP).update({ status: 'delivered', deliveredAt: clock, updatedAt: clock });
    const rel = await quiet(() => api.releaseGoods(orderId));
    assert.strictEqual(rel.released, GOODS);
    assert.deepStrictEqual(await quiet(() => api.settleLost(orderId)), { skipped: 'status_delivered' });
    const s = await shipOf();
    assert.deepStrictEqual(await lossTrigger(s, { ...s, status: 'closed' }), { skipped: 'not_loss_settled' });
    assert.deepStrictEqual(await lossTrigger({ paymentStatus: 'loss_pending' }, { paymentStatus: 'loss_settled', source: 'logistics' }), { skipped: 'not_wholesale' });
    assert.deepStrictEqual(await lossTrigger({ paymentStatus: 'loss_pending' }, { paymentStatus: 'loss_settled', source: 'wholesale_return', wholesaleOrderId: orderId }), { skipped: 'not_wholesale' });
    const o = await orderOf(orderId);
    assert.deepStrictEqual([o.status, o.payment.status], ['delivered', 'released']);
    assert.strictEqual(await bal(pcOf(BUYER)), 300000 - (GOODS + FEE));
    await assertLedgerSound();
  });

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length} passed, ${failed.length} failed`);
  process.exit(failed.length ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
