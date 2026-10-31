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
 *   YETKAZISH HAQI (ega, 2026-10-31 — xaridor to'laganini to'liq oladi, haqni mas'ul kuryer to'laydi):
 *   - kuryer boy: xaridorga tovar + haq; kuryer −G (relay) −haq; `bonus:wholesaleLostFee:{id}`, wallet_ledger
 *     `wholesale_lost_fee_charge/_refund`; qarz yo'q
 *   - kuryer qisman / bo'sh: take = min(haq, hamyon), qolgani `provider_capabilities.debt.logistics` (relay
 *     qarziga QO'SHILADI) + `lost.deliveryFeeOutstanding`; admin to'lovni yozadi → xaridorga, qarz kamayadi
 *   - karta (to'lanmagan) — haq qaytarilmaydi; kuryer = xaridor — pul yo'q (anomaliya)
 *   - takror trigger / reconcile — ikkinchi haq yo'q
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
/** Admin tekshiruvi (index.js `requireCallerRoles` o'rnida): `users/{tel}.role` ro'yxatda bo'lsin. */
const requireCallerRoles = async (c, roles, msg) => {
  const uid = canon(c && c.auth && c.auth.token && c.auth.token.phone_number);
  const role = ((await db.collection('users').doc(uid).get()).data() || {}).role;
  if (!roles.includes(role)) throw new functions.https.HttpsError('permission-denied', msg);
  return uid;
};
const api = W.attachWholesaleOrders({}, { ...depsCommon, requireCallerRoles });
const relayApi = relay.attachRelayEscrow({}, {
  ...depsCommon, notifyUserInApp: async () => {}, requireCallerRoles,
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
// Parallel `quiet()` (Promise.all) xavfsiz: chuqurlik hisoblagichi — oxirgisi tugaganda asl console qaytadi
// (aks holda no-op saqlanib qolib, keyingi PASS/FAIL qatorlari va yakuniy natija yutilardi).
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
async function seed({ card = false, courierWallet = 250000 } = {}) {
  clock = T0;
  await resetAll();
  await db.collection('module_config').doc('wholesale_orders_all').set({ enabled: true, stage: 'internal', testerIds: [BUYER] });
  // Xaridorda ham accountId (kuryer = xaridor anomaliyasi testi uchun; boshqa testlarda ishlatilmaydi).
  await db.collection('users').doc(BUYER).set({ bonusBalance: 0, accountId: 'acc_buyer' });
  await db.collection('users').doc(SELLER).set({ bonusBalance: 0 });
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
async function shipAndFund(orderId, courier = K1) {
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
    status: 'in_transit', legAssignments: { leg0: courier }, currentLegId: 'leg0', currentCustodian: { kind: 'provider', id: courier, since: clock },
  });
  await db.collection('demands').doc('leg0').set({ module: 'logistics', status: 'in_progress', assignment: { providerId: courier }, attributes: { shipmentId: SHIP } });
}
const debtOf = async (acc = 'acc_k1') => Number(((((await db.collection('provider_capabilities').doc(acc).get()).data() || {}).debt) || {}).logistics) || 0;
const feeJournal = (id) => journal(`bonus:${W.lostFeeKey(id)}`);
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

  await check('hamyon, kuryer BOY: relay loss_settled (sotuvchiga kuryerdan G) → parallel trigger ×2 + settleLost → xaridorga 140 000 + haq 60 000 BIR MARTA; kuryer −G −haq; qarz yo\'q; eskrou 0; lost; qoldiq 90', async () => {
    const before = await shipOf();
    const rel = await relaySettles();
    assert.deepStrictEqual([rel.taken, rel.outstanding], [GOODS, 0]);
    assert.strictEqual(await bal(pcOf(SELLER)), GOODS, 'sotuvchi — FAQAT kuryer kompensatsiyasi');
    assert.strictEqual(await bal(pcOf(K1)), 250000 - GOODS);
    const after = await shipOf();
    const outs = await Promise.all([lossTrigger(before, after), lossTrigger(before, after), quiet(() => api.settleLost(orderId))]);
    assert.strictEqual(outs.filter((r) => r.lost === true).length, 1, JSON.stringify(outs));
    const won = outs.find((r) => r.lost === true);
    assert.deepStrictEqual([won.feeRefunded, won.feeOutstanding, won.feeDebt, won.feeAnomaly], [FEE, 0, 0, null]);
    assert.strictEqual(await bal(pcOf(BUYER)), 300000, 'xaridor: to\'lagani TO\'LIQ qaytdi (tovar + yetkazish haqi)');
    assert.strictEqual(await bonusOf(BUYER), 300000);
    assert.strictEqual(await bal(pcOf(K1)), 250000 - GOODS - FEE, 'kuryer: relay G + yetkazish haqi');
    assert.strictEqual(await bonusOf(K1), 250000 - GOODS - FEE);
    assert.strictEqual(await debtOf(), 0, 'qarz yozilmadi');
    const fj = (await feeJournal(orderId)).data();
    assert.strictEqual(fj.kind, 'wholesale_lost_fee_refund');
    assert.deepStrictEqual(fj.legs, [{ account: pcOf(K1), dr: FEE }, { account: pcOf(BUYER), cr: FEE }]);
    assert.deepStrictEqual([fj.meta.courierAccountId, fj.meta.deliveryFee, fj.meta.outstanding], ['acc_k1', FEE, 0]);
    const wlr = await walletLedger(BUYER, 'wholesale_lost_fee_refund');
    assert.deepStrictEqual([wlr.length, wlr[0].amount, wlr[0].refId], [1, FEE, orderId]);
    const wlc = await walletLedger(K1, 'wholesale_lost_fee_charge');
    assert.deepStrictEqual([wlc.length, wlc[0].amount, wlc[0].refId], [1, -FEE, orderId]);
    const of = await orderOf(orderId);
    assert.deepStrictEqual(
      [of.lost.deliveryFee, of.lost.deliveryFeeRefunded, of.lost.deliveryFeeOutstanding, of.lost.deliveryFeePaidTotal,
        of.lost.deliveryFeeEntryId, of.lost.deliveryFeeAnomaly, of.lost.courierAccountId, of.payment.lostFeeRefund],
      [FEE, FEE, 0, 0, `bonus:${W.lostFeeKey(orderId)}`, null, 'acc_k1', FEE],
    );
    const hf = (await historyOf(orderId)).find((x) => x.event === 'lost_settled');
    assert.deepStrictEqual([hf.meta.deliveryFeeRefunded, hf.meta.deliveryFeeOutstanding, hf.meta.deliveryFeeAnomaly], [FEE, 0, null]);
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
    assert.deepStrictEqual(await quiet(() => api.settleLost(orderId)), { skipped: 'already_lost' });
    assert.strictEqual(await bal(pcOf(BUYER)), 300000);
    assert.strictEqual(await bal(pcOf(K1)), 250000 - GOODS - FEE, 'kuryerdan haq ikkinchi marta olinmadi');
    assert.strictEqual((await walletLedger(K1, 'wholesale_lost_fee_charge')).length, 1);
    assert.strictEqual(await debtOf(), 0);
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
    assert.strictEqual(await bal(pcOf(BUYER)), 300000 - FEE, 'tovar puli qaytdi; haq — kuryer qarzi');
    assert.strictEqual(await bal(W.escrowAccount(orderId)), 0);
    const o = await orderOf(orderId);
    assert.strictEqual(o.status, 'lost');
    assert.deepStrictEqual([o.lost.deliveryFeeRefunded, o.lost.deliveryFeeOutstanding, o.lost.deliveryFeeEntryId, o.payment.lostFeeRefund],
      [0, FEE, null, 0]);
    assert.strictEqual(await debtOf(), GOODS + FEE, 'relay qarzi G + haq qoldig\'i (bitta debt.logistics)');
    assert.strictEqual((await feeJournal(orderId)).exists, false);
    assert.strictEqual(await accExists(pcOf(K1)), false, 'bo\'sh kuryer hisobiga yozuv yo\'q');
    assert.strictEqual((await stockOf()).packs.p1, 90);
    await assertLedgerSound();
  });

  await check('hamyon, kuryer QISMAN (G + 20 000): relay G oladi; haqdan 20 000 xaridorga, 40 000 — qarz + deliveryFeeOutstanding; kuryer hamyoni 0 (manfiy emas)', async () => {
    await seed({ courierWallet: GOODS + 20000 });
    orderId = (await place()).orderId;
    await shipAndFund(orderId);
    await adminMarksLost();
    const before = await shipOf();
    const rel = await relaySettles();
    assert.deepStrictEqual([rel.taken, rel.outstanding], [GOODS, 0]);
    const r = await lossTrigger(before, await shipOf());
    assert.deepStrictEqual([r.lost, r.refunded, r.feeRefunded, r.feeOutstanding, r.feeDebt], [true, GOODS, 20000, 40000, 40000]);
    assert.strictEqual(await bal(pcOf(BUYER)), 300000 - 40000);
    assert.strictEqual(await bonusOf(BUYER), 300000 - 40000);
    assert.strictEqual(await bal(pcOf(K1)), 0, 'kuryer hamyoni AYNAN 0');
    assert.strictEqual(await bonusOf(K1), 0);
    assert.strictEqual(await debtOf(), 40000, 'qarz faqat haq qoldig\'i (relay G to\'liq olingan)');
    const fj = (await feeJournal(orderId)).data();
    assert.deepStrictEqual(fj.legs, [{ account: pcOf(K1), dr: 20000 }, { account: pcOf(BUYER), cr: 20000 }]);
    const o = await orderOf(orderId);
    assert.deepStrictEqual([o.lost.deliveryFeeRefunded, o.lost.deliveryFeeOutstanding, o.lost.courierAccountId, o.payment.lostFeeRefund],
      [20000, 40000, 'acc_k1', 20000]);
    // Takror trigger / reconcile — qarz va pul ikkilanmaydi.
    assert.deepStrictEqual(await lossTrigger(before, await shipOf()), { skipped: 'already_lost' });
    clock = new Date(T0.getTime() + 11 * 60 * 1000);
    await quiet(() => api.reconcile());
    assert.strictEqual(await debtOf(), 40000);
    assert.strictEqual(await bal(pcOf(BUYER)), 300000 - 40000);
    await assertLedgerSound();
  });

  await check('admin kuryer to\'lovini yozadi (adminRecordWholesaleLostFeePayment): 15 000 + 25 000 → xaridor to\'liq, qarz 0; idempotent opId; rad holatlari', async () => {
    const call = (d, who = ADMIN) => quiet(() => api.recordLostFeePayment(d, ctx(who)));
    const reason = async (p) => { try { await p; return 'ok'; } catch (e) { return (e.details && e.details.reason) || e.code || e.message; } };
    assert.strictEqual(await reason(call({ orderId, amount: 1000, opId: 'op-fee-0001' }, BUYER)), 'permission-denied', 'oddiy foydalanuvchi — RAD');
    assert.strictEqual(await reason(call({ orderId, amount: 40001, opId: 'op-fee-0001' })), 'exceeds_outstanding');
    assert.strictEqual(await reason(call({ orderId, amount: 1.5, opId: 'op-fee-0001' })), 'bad_amount');
    assert.strictEqual(await reason(call({ orderId, amount: 1000, opId: 'x' })), 'bad_op_id');
    const r1 = await call({ orderId, amount: 15000, opId: 'op-fee-0001', note: 'naqd' });
    assert.deepStrictEqual([r1.ok, r1.idempotent, r1.outstanding, r1.paidTotal], [true, false, 25000, 15000]);
    const r1b = await call({ orderId, amount: 15000, opId: 'op-fee-0001' });
    assert.deepStrictEqual([r1b.idempotent, r1b.outstanding], [true, 25000], 'takror — ikkinchi pul yo\'q');
    assert.strictEqual(await reason(call({ orderId, amount: 14000, opId: 'op-fee-0001' })), 'op_id_reused');
    assert.strictEqual(await bal(pcOf(BUYER)), 300000 - 25000);
    assert.strictEqual(await debtOf(), 25000);
    const r2 = await call({ orderId, amount: 25000, opId: 'op-fee-0002' });
    assert.deepStrictEqual([r2.outstanding, r2.paidTotal], [0, 40000]);
    assert.strictEqual(await bal(pcOf(BUYER)), 300000, 'xaridor to\'lagani to\'liq qaytdi');
    assert.strictEqual(await bonusOf(BUYER), 300000);
    assert.strictEqual(await debtOf(), 0);
    assert.strictEqual(await reason(call({ orderId, amount: 1, opId: 'op-fee-0003' })), 'nothing_outstanding');
    const o = await orderOf(orderId);
    assert.deepStrictEqual([o.status, o.lost.deliveryFeeOutstanding, o.lost.deliveryFeePaidTotal, o.payment.lostFeeRefund], ['lost', 0, 40000, FEE]);
    const pays = (await historyOf(orderId)).filter((x) => x.event === 'lost_fee_payment');
    assert.deepStrictEqual(pays.map((x) => [x.meta.amount, x.meta.outstandingAfter, x.actor, x.actorId]).sort((a, b) => b[1] - a[1]),
      [[15000, 25000, 'admin', ADMIN], [25000, 0, 'admin', ADMIN]]);
    const j = (await journal(W.lostFeePaymentKey(orderId, 'op-fee-0002'))).data();
    assert.deepStrictEqual([j.kind, j.postedRole, j.meta.amount], ['wholesale_lost_fee_payment', 'admin', 25000]);
    assert.strictEqual((await db.collection('logistics_audit').doc(`wholesale_lost_fee_payment_${orderId}_op-fee-0002`).get()).exists, true);
    await assertLedgerSound();
  });

  await check('kuryer bo\'sh: relay G-to\'lovi (adminRecordLostParcelPayment) va Ulgurji haq to\'lovi BIR qarzdan — ikkalasi ishlaydi, qarz 0', async () => {
    await seed({ courierWallet: 0 });
    orderId = (await place()).orderId;
    await shipAndFund(orderId);
    await adminMarksLost();
    const before = await shipOf();
    await relaySettles();
    await lossTrigger(before, await shipOf());
    assert.strictEqual(await debtOf(), GOODS + FEE);
    const g = await quiet(() => relayApi.recordLostPayment({ shipmentId: SHIP, amount: GOODS, opId: 'op-goods-01' }, ctx(ADMIN)));
    assert.strictEqual(g.outstanding, 0);
    assert.strictEqual(await debtOf(), FEE, 'relay faqat G ni kamaytirdi');
    assert.strictEqual(await bal(pcOf(SELLER)), GOODS);
    const f = await quiet(() => api.recordLostFeePayment({ orderId, amount: FEE, opId: 'op-fee-01' }, ctx(ADMIN)));
    assert.strictEqual(f.outstanding, 0);
    assert.strictEqual(await debtOf(), 0);
    assert.strictEqual(await bal(pcOf(BUYER)), 300000);
    await assertLedgerSound();
  });

  await check('kuryer = xaridor (o\'zi yo\'qotgan): haq pulsiz — anomaliya fee_same_account, qarz yo\'q; tovar puli baribir qaytadi', async () => {
    await seed({ courierWallet: 0 });
    orderId = (await place()).orderId;
    await shipAndFund(orderId, BUYER);
    await adminMarksLost();
    const before = await shipOf();
    const rel = await relaySettles();
    assert.deepStrictEqual([rel.taken, rel.outstanding], [100000, GOODS - 100000], 'relay: xaridor-kuryer hamyonidan (100 000) sotuvchiga');
    const r = await lossTrigger(before, await shipOf());
    assert.deepStrictEqual([r.lost, r.refunded, r.feeRefunded, r.feeOutstanding, r.feeDebt, r.feeAnomaly], [true, GOODS, 0, 0, 0, 'fee_same_account']);
    assert.strictEqual(await bal(pcOf(BUYER)), GOODS, '0 + tovar puli 140 000; haq o\'zidan o\'ziga — yo\'q');
    assert.strictEqual(await debtOf('acc_buyer'), GOODS - 100000, 'faqat relay qarzi');
    assert.strictEqual((await feeJournal(orderId)).exists, false);
    const o = await orderOf(orderId);
    assert.deepStrictEqual([o.lost.deliveryFeeAnomaly, o.lost.deliveryFeeRefunded, o.lost.deliveryFeeOutstanding], ['fee_same_account', 0, 0]);
    await assertLedgerSound();
  });

  await check('incident yo\'q (relay settle\'dan keyin buzilgan): tovar puli qaytadi; haq — anomaliya, qoldiq ko\'rinadi, qarz yozilmaydi; admin to\'lovi RAD', async () => {
    await seed();
    orderId = (await place()).orderId;
    await shipAndFund(orderId);
    await adminMarksLost();
    const before = await shipOf();
    await relaySettles();
    await db.collection('logistics_incidents').doc(SHIP).update({ courier: admin.firestore.FieldValue.delete() });
    const r = await lossTrigger(before, await shipOf());
    assert.deepStrictEqual([r.lost, r.refunded, r.feeRefunded, r.feeOutstanding, r.feeDebt, r.feeAnomaly], [true, GOODS, 0, FEE, 0, 'fee_incident_invalid']);
    assert.strictEqual(await bal(pcOf(BUYER)), 300000 - FEE);
    assert.strictEqual(await bal(pcOf(K1)), 250000 - GOODS);
    assert.strictEqual(await debtOf(), 0);
    const o = await orderOf(orderId);
    assert.deepStrictEqual([o.lost.deliveryFeeAnomaly, o.lost.deliveryFeeOutstanding, o.lost.courierAccountId], ['fee_incident_invalid', FEE, null]);
    let reasonCode = 'ok';
    try { await quiet(() => api.recordLostFeePayment({ orderId, amount: 1000, opId: 'op-fee-0009' }, ctx(ADMIN))); } catch (e) { reasonCode = e.details.reason; }
    assert.strictEqual(reasonCode, 'fee_debt_not_recorded');
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
    // Xaridor hech narsa to'lamagan — yetkazish haqi qaytarilmaydi, kuryerdan faqat relay G.
    assert.deepStrictEqual([r.feeRefunded, r.feeOutstanding, o.lost.deliveryFeeRefunded, o.lost.deliveryFeeOutstanding, o.payment.lostFeeRefund],
      [0, 0, 0, 0, 0]);
    assert.strictEqual((await feeJournal(orderId)).exists, false);
    assert.strictEqual(await bal(pcOf(K1)), 250000 - GOODS);
    assert.strictEqual(await debtOf(), 0);
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
      assert.strictEqual((await feeJournal(orderId)).exists, false);
      assert.deepStrictEqual([o.lost.deliveryFeeRefunded, o.lost.deliveryFeeOutstanding], [null, null], 'review — admin hal qiladi');
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
    assert.strictEqual((await feeJournal(orderId)).exists, false, 'anomaliya — haq ham olinmadi');
    assert.strictEqual(await bal(pcOf(K1)), 250000 - GOODS);
    assert.strictEqual(await debtOf(), 0);
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
