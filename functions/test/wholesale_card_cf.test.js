/**
 * Ulgurji 3b — «yetkazilganda karta orqali», default codebase, HAQIQIY ledger (Firestore Emulator)
 * + demand callable'lari (confirm / markRefused / getWholesaleDeliveryCode) AYNI emulatorda:
 *
 *   firebase emulators:exec --only firestore --project demo-ulgcard \
 *     "node functions/test/wholesale_card_cf.test.js"
 *
 * Qulflanadi:
 *   - place (karta): SOTUVCHI hamyonidan deliveryFee+avaFee, xaridor hamyoniga tegilmaydi; rad sabablari
 *     (balans hold−1 ↔ hold, kartasiz, qarz bloki, xaridor 2 rad, muhr buzilgan) — HECH NARSA yozilmaydi
 *   - bekor (yetkazish haqi o'tmasdan) → ushlanma SOTUVCHIGA, qoldiq +N
 *   - to'liq zanjir: SHIP_FUND → kod tasdiqdan oldin YO'Q → «Pul tushdi» → kod → yetkazildi → avaFee
 *     earnings ga, sotuvchiga AVA orqali 0, barcha eskroular 0; takror — bir marta; avaFee=0 varianti
 *   - rad: avaFee sotuvchiga qaytadi, kuryer haqi relay eskrouda qoladi, qoldiq HALI tiklanmaydi;
 *     qaytish: sotuvchi hamyonidan → relay eskrou → returning → yetkazildi → returned + qoldiq +N
 *   - qaytish qarzi: manfiyga tushmaydi, returnDebt + cardBlocked (karta usuli yopiladi), trigger
 *     aylanmaydi, hamyon to'ldirilgach reconcile to'laydi va blokni yechadi
 *   - Σdr == Σcr, aktiv == passiv, passenger_credit == bonusBalance
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18195';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-ulgcard';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const settlementLedger = require('../settlement_ledger');
const W = require('../wholesale_orders');
const relay = require('../relay_escrow');
const WO = require('../../functions_demand/core/wholesale_orders');
const DC = require('../../functions_demand/api/wholesale_card');
const DW = require('../../functions_demand/api/wholesale_orders');

const BUYER = '998901110001';
const BUYER2 = '998901110002';
const SELLER = '998901234567';
const K1 = '998902220002';
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
const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });
const dDeps = { db, now: () => clock };

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
const stockOf = async () => (await db.collection('wholesale_stock').doc('rice').get()).data();
const count = async (col) => (await db.collection(col).get()).size;
const journal = async (id) => (await db.collection(settlementLedger.COL_JOURNAL).doc(id).get()).data();
async function assertLedgerSound() {
  const rec = await settlementLedger.reconcile(db);
  assert.strictEqual(rec.balanced, true, `Σdr==Σcr buzildi: ${rec.totalDr} != ${rec.totalCr}`);
  assert.strictEqual(rec.identityOk, true, `aktiv/passiv: ${rec.assets} != ${rec.liabilities}`);
  assert.strictEqual(rec.projectionOk, true, `bonusBalance ko'zgusi: ${JSON.stringify(rec.mismatches)}`);
}
async function expectErr(promise, code, reason) {
  try { await promise; } catch (e) {
    assert.strictEqual(e.code, code, `kod: kutilgan ${code}, keldi ${e.code} (${e.message})`);
    if (reason) assert.strictEqual((e.details || {}).reason, reason, `reason: ${JSON.stringify(e.details)}`);
    return e;
  }
  throw new Error(`${code}/${reason} kutilgan edi`);
}
let topupSeq = 0;
const topup = (uid, amount) => settlementLedger.postEntry(db, {
  idempotencyKey: `topupC:${uid}:${topupSeq += 1}`, kind: 'test_topup',
  legs: [{ account: 'admin_clearing', dr: amount }, { account: pcOf(uid), cr: amount }],
});
const quiet = async (fn) => {
  const l = console.log; const e = console.error;
  console.log = () => {}; console.error = () => {};
  try { return await fn(); } finally { console.log = l; console.error = e; }
};

// 10 × 14 000 = 140 000; yetkazish 60 000; AVA 3 500 → sotuvchi ushlanmasi 63 500.
const HOLD = 63500;
function quoteDoc(extra = {}) {
  return {
    buyerId: BUYER, sellerId: SELLER, productId: 'rice', productTitle: 'Гуруч', packId: 'p1', packLabel: '1 кг',
    qty: 10, unitPrice: 14000, goodsTotal: 140000, deliveryFee: 60000, total: 200000, currency: 'UZS',
    delivery: { tariffVersion: 3, zone: 'ZONE_4', actualWeightG: 10000, chargeableWeightG: 10000, dims: null, priceSnapshot: { customerPrice: 60000 } },
    avaFeeBps: 250, feeVersion: 3, avaFee: 3500, sellerPayout: 136500,
    origin: { regionId: 'xorazm' }, destination: { regionId: 'toshkent_shahri', addressText: 'Chilonzor' },
    paymentMethod: 'card_on_delivery', cardHold: HOLD,
    createdAt: clock, expiresAt: new Date(clock.getTime() + 15 * 60 * 1000), used: false,
    ...extra,
  };
}
async function seed({ sellerWallet = 100000, card = true, extra = {} } = {}) {
  clock = T0;
  await resetAll();
  await db.collection('module_config').doc('wholesale_orders_all').set({ enabled: true, stage: 'internal', testerIds: [BUYER] });
  for (const u of [BUYER, BUYER2, SELLER, K1]) await db.collection('users').doc(u).set({ bonusBalance: 0 });
  await db.collection('wholesale_products').doc('rice').set({ sellerId: SELLER, status: 'active', market: 'wholesale' });
  await db.collection('wholesale_stock').doc('rice').set({ productId: 'rice', sellerId: SELLER, packs: { p1: 100 }, version: 1 });
  await db.collection('wholesale_sellers').doc(SELLER).set({ phone: SELLER, companyName: 'Guruch savdo', approvalStatus: 'approved' });
  if (card) {
    await db.collection('wholesale_sellers').doc(SELLER).collection('private').doc('payout')
      .set({ cardNumber: '4111111111111111', holderName: 'ALI VALIYEV', last4: '1111', version: 1 });
  }
  await db.collection('wholesale_quotes').doc('q1').set(quoteDoc(extra.quote || {}));
  if (sellerWallet > 0) await topup(SELLER, sellerWallet);
}
const place = (extra = {}, who = BUYER) => quiet(() => api.place({ quoteId: 'q1', clientRequestId: 'req-00000001', ...extra }, ctx(who)));

const SHIP = 'S1';
async function seedShipment(orderId, { id = SHIP, price = 60000 } = {}) {
  await db.collection('shipments').doc(id).set({
    orderId: `lo_${orderId}`, ownerId: SELLER, recipientId: BUYER, source: 'wholesale', wholesaleOrderId: orderId,
    trackingNumber: 'AVA-26-1031-000001', status: 'awaiting_payment', paymentStatus: 'pending',
    priceSnapshot: { customerPrice: price, tariffVersion: 3, declaredValue: 140000 }, legIds: ['leg0'], legCount: 1,
    createdAt: clock, updatedAt: clock,
  });
  await db.collection('shipments').doc(id).collection('private').doc('internal').set({
    platformShare: 12000, providerPool: 48000, legPayouts: [{ index: 0, kind: 'direct', amount: 48000 }], tariffVersion: 3,
  });
  await db.collection('shipments').doc(id).collection('private').doc('secrets').set({ qrSecret: 'q'.repeat(32) });
}
async function linkAndFund(orderId) {
  const ref = db.collection('wholesale_orders').doc(orderId);
  const before = (await ref.get()).data();
  await ref.update({ shipment: { shipmentId: SHIP, orderId: `lo_${orderId}`, trackingNumber: 'AVA-26-1031-000001', createdAt: clock }, historySeq: 2 });
  const r = await quiet(async () => api.onStatusChange(before, (await ref.get()).data(), orderId));
  assert.strictEqual(r.funded, 60000, JSON.stringify(r));
  // K1 oxirgi LEG ijrochisi, posilka unda (relay acceptLeg + scanHandover yozadigan maydonlar).
  await db.collection('shipments').doc(SHIP).update({
    status: 'in_transit', legAssignments: { leg0: K1 }, currentLegId: 'leg0', currentCustodian: { kind: 'provider', id: K1, since: clock },
  });
}
async function deliverEvent(id) {
  await db.collection('shipments').doc(id).update({ status: 'delivered', deliveredAt: clock, updatedAt: clock });
  return {
    shipmentId: id, legId: id === SHIP ? 'leg0' : 'rleg0', orderId: 'lo_x', ownerId: SELLER, kind: 'delivery', completesLegId: id === SHIP ? 'leg0' : 'rleg0',
    completedLegProviderId: K1, completedLegPayout: id === SHIP ? 48000 : 32000, legIndex: 0, legCount: 1, deliversShipment: true,
  };
}
async function custodyTriggers(ev) {
  const relayOut = await quiet(() => relayApi.onCustodyEvent(ev));
  const wholesale = await quiet(() => api.onCustodyEvent(ev));
  return { ...relayOut, wholesale };
}
/** Demand `ensureWholesaleReturnShipment` natijasi (jo'natma shakli demand testida qulflangan). */
async function linkReturn(orderId, { fee = 40000, shipPrice = fee } = {}) {
  await db.collection('shipments').doc('R1').set({
    orderId: 'lo_ret', ownerId: SELLER, recipientId: SELLER, source: 'wholesale_return', wholesaleOrderId: orderId, wholesaleReturn: true,
    trackingNumber: 'AVA-26-1031-000002', status: 'awaiting_payment', paymentStatus: 'pending',
    priceSnapshot: { customerPrice: shipPrice, tariffVersion: 4, declaredValue: 140000 }, legIds: ['rleg0'], legCount: 1,
    legAssignments: { rleg0: K1 }, createdAt: clock, updatedAt: clock,
  });
  await db.collection('shipments').doc('R1').collection('private').doc('internal').set({
    platformShare: fee / 5, providerPool: fee - fee / 5, legPayouts: [{ index: 0, kind: 'direct', amount: fee - fee / 5 }], tariffVersion: 4,
  });
  const ref = db.collection('wholesale_orders').doc(orderId);
  const before = (await ref.get()).data();
  await ref.update({
    returnShipment: { shipmentId: 'R1', orderId: 'lo_ret', legId: 'rleg0', trackingNumber: 'AVA-26-1031-000002', fee, tariffVersion: 4, courierId: K1, createdAt: clock },
    returnStatus: 'awaiting_payment',
  });
  return quiet(async () => api.onStatusChange(before, (await ref.get()).data(), orderId));
}
async function refuse(orderId) {
  const ref = db.collection('wholesale_orders').doc(orderId);
  const before = (await ref.get()).data();
  const r = await quiet(() => DC.makeMarkWholesaleBuyerRefused(dDeps)({ orderId, reason: 'to\'lamadi' }, ctx(K1)));
  assert.strictEqual(r.status, 'refused');
  const after = (await ref.get()).data();
  return quiet(() => api.onStatusChange(before, after, orderId));
}

(async () => {
  await check('paritet: karta nomlari va holatlar demand jadvali bilan bir xil', async () => {
    assert.deepStrictEqual({ ...W.PAYMENT_METHOD }, { ...WO.PAYMENT_METHOD });
    assert.deepStrictEqual({ ...W.CARD_PAYMENT }, { ...WO.CARD_PAYMENT });
    assert.deepStrictEqual({ ...W.RETURN_STATUS }, { ...WO.RETURN_STATUS });
    assert.strictEqual(W.CARD_REFUSAL_LIMIT, WO.CARD_REFUSAL_LIMIT);
    for (const k of ['REFUSED', 'PAYMENT_DISPUTE', 'RETURNING', 'RETURNED']) assert.strictEqual(W.STATUS[k], WO.STATUS[k], k);
    assert.deepStrictEqual([...W.REFUND_STATUSES], [...WO.REFUND_STATUSES]);
    for (const d of [{}, { paymentMethod: 'wallet' }, { paymentMethod: 'card_on_delivery' }, { paymentMethod: 'x' }]) {
      assert.strictEqual(W.methodOf(d), WO.methodOf(d));
    }
    assert.strictEqual(settlementLedger.accountTypeOf(W.returnEscrowAccount('x')), 'liability');
  });

  let orderId;
  await check('place (karta): SOTUVCHI hamyonidan 63 500 (deliveryFee+avaFee), xaridor hamyoniga TEGILMAYDI; buyurtma maydonlari; qoldiq −10', async () => {
    await seed();
    const r = await place();
    assert.deepStrictEqual([r.ok, r.paymentMethod, r.total], [true, 'card_on_delivery', 200000]);
    orderId = r.orderId;
    assert.strictEqual(await bal(pcOf(SELLER)), 100000 - HOLD);
    assert.strictEqual(await bonusOf(SELLER), 100000 - HOLD, 'sotuvchi hamyoni ko\'zgusi');
    assert.strictEqual(await accExists(pcOf(BUYER)), false, 'xaridor hisobiga yozuv yo\'q');
    assert.strictEqual(await bonusOf(BUYER), 0);
    assert.strictEqual(await bal(W.escrowAccount(orderId)), HOLD);
    const j = await journal(`bonus:${W.holdKey(orderId)}`);
    assert.strictEqual(j.kind, 'wholesale_card_hold');
    assert.deepStrictEqual(j.legs, [{ account: pcOf(SELLER), dr: HOLD }, { account: W.escrowAccount(orderId), cr: HOLD }]);
    const o = await orderOf(orderId);
    assert.strictEqual(o.paymentMethod, 'card_on_delivery');
    assert.deepStrictEqual([o.payment.status, o.payment.amount, o.payment.payer, o.payment.payerWalletUid], ['held_seller', HOLD, 'seller', SELLER]);
    assert.deepStrictEqual(o.cardPayment, { status: 'awaiting', confirmedAt: null });
    assert.strictEqual(o.total, 200000);
    assert.strictEqual((await stockOf()).packs.p1, 90);
    const wl = (await db.collection('users').doc(SELLER).collection('wallet_ledger').where('type', '==', 'wholesale_card_hold').get()).docs.map((d) => d.data());
    assert.deepStrictEqual([wl.length, wl[0].amount], [1, -HOLD]);
    await assertLedgerSound();
  });

  await check('place (karta) rad: balans hold−1 / kartasiz / qarz bloki / xaridor 2 rad / muhr buzilgan — HECH NARSA yozilmaydi; balans = hold (chegara) o\'tadi', async () => {
    const nothing = async (sellerBal) => {
      assert.strictEqual(await count('wholesale_orders'), 0);
      assert.strictEqual((await stockOf()).packs.p1, 100);
      assert.strictEqual(await bal(pcOf(SELLER)), sellerBal);
      await assertLedgerSound();
    };
    await seed({ sellerWallet: HOLD - 1 });
    const e = await expectErr(place(), 'failed-precondition', 'seller_balance_insufficient');
    assert.ok(!('balance' in (e.details || {})), 'sotuvchi balansi xaridorga oshkor emas');
    await nothing(HOLD - 1);
    await seed({ card: false });
    await expectErr(place(), 'failed-precondition', 'seller_no_card');
    await nothing(100000);
    await seed();
    await db.collection('wholesale_seller_stats').doc(SELLER).set({ cardBlocked: true });
    await expectErr(place(), 'failed-precondition', 'seller_debt');
    await nothing(100000);
    await seed();
    await db.collection('wholesale_buyer_stats').doc(BUYER).set({ cardRefusals: 2 });
    await expectErr(place(), 'failed-precondition', 'buyer_limited');
    await nothing(100000);
    await seed({ extra: { quote: { cardHold: HOLD - 1 } } });
    await expectErr(place(), 'failed-precondition', 'quote_invalid');
    await nothing(100000);
    await seed({ sellerWallet: HOLD });
    await db.collection('wholesale_buyer_stats').doc(BUYER).set({ cardRefusals: 1 });
    await place();
    assert.strictEqual(await bal(pcOf(SELLER)), 0, 'chegara: aynan hold');
    await assertLedgerSound();
  });

  await check('bekor (yetkazish haqi o\'tmasdan, karta) → 63 500 SOTUVCHIGA, qoldiq +10, xaridor tegilmagan; takror — bir marta', async () => {
    await seed();
    const { orderId: id } = await place();
    const ref = db.collection('wholesale_orders').doc(id);
    await ref.update({ status: 'cancelled', refundStatus: 'pending', statusUpdatedAt: clock, historySeq: 2 });
    const after = (await ref.get()).data();
    const r = await quiet(() => api.onStatusChange({ status: 'placed' }, after, id));
    assert.strictEqual(r.refunded, HOLD);
    assert.strictEqual((await quiet(() => api.refundOrder(id))).skipped, 'already_refunded');
    assert.strictEqual(await bal(pcOf(SELLER)), 100000);
    assert.strictEqual(await bonusOf(SELLER), 100000);
    assert.strictEqual(await accExists(pcOf(BUYER)), false);
    assert.strictEqual(await bal(W.escrowAccount(id)), 0);
    assert.strictEqual((await stockOf()).packs.p1, 100);
    const j = await journal(`bonus:${W.refundKey(id)}`);
    assert.deepStrictEqual(j.legs, [{ account: W.escrowAccount(id), dr: HOLD }, { account: pcOf(SELLER), cr: HOLD }]);
    await assertLedgerSound();
  });

  await check('TO\'LIQ ZANJIR (karta): SHIP_FUND → kod tasdiqdan oldin YO\'Q → «Pul tushdi» → kod → yetkazildi → avaFee earnings, sotuvchiga 0, eskroular 0; takror — bir marta', async () => {
    await seed();
    const { orderId: id } = await place();
    await seedShipment(id);
    await linkAndFund(id);
    assert.strictEqual(await bal(W.escrowAccount(id)), 3500, 'SHIP_FUND dan keyin eskrouda aynan avaFee');
    assert.strictEqual(await bal(relay.escrowAccount(SHIP)), 60000);
    let o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.payment.status, o.payment.deliveryFunded], ['in_delivery', 'held_seller', true]);
    const getCode = DW.makeGetWholesaleDeliveryCode({ db });
    await quiet(() => expectErr(getCode({ orderId: id }, ctx(BUYER)), 'failed-precondition', 'card_payment_unconfirmed'));
    await quiet(() => expectErr(DC.makeConfirmWholesaleCardPayment(dDeps)({ orderId: id }, ctx(BUYER)), 'permission-denied', 'not_order_party'));
    const c = await quiet(() => DC.makeConfirmWholesaleCardPayment(dDeps)({ orderId: id }, ctx(SELLER)));
    assert.strictEqual(c.cardPaymentStatus, 'confirmed');
    const code = await quiet(() => getCode({ orderId: id }, ctx(BUYER)));
    assert.ok(/^\d{6}$/.test(code.deliveryCode));
    const ev = await deliverEvent(SHIP);
    const out = await custodyTriggers(ev);
    assert.strictEqual(out.release.released, 60000);
    assert.deepStrictEqual([out.wholesale.released, out.wholesale.sellerPayout, out.wholesale.card], [3500, 0, true], JSON.stringify(out.wholesale));
    assert.strictEqual(await bal(W.AVA_FEE_ACCOUNT), 3500);
    assert.strictEqual(await bal(W.escrowAccount(id)), 0);
    assert.strictEqual(await bal(relay.escrowAccount(SHIP)), 0);
    assert.strictEqual(await bal(pcOf(SELLER)), 100000 - HOLD, 'tovar puli AVA orqali EMAS — kartaga tushgan');
    assert.strictEqual(await accExists(pcOf(BUYER)), false);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), 48000);
    o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.payment.status, o.payment.sellerPayoutViaAva, o.payment.releaseEntryId], ['delivered', 'released', 0, W.releaseKey(id)]);
    const jr = await journal(W.releaseKey(id));
    assert.deepStrictEqual(jr.legs, [{ account: W.escrowAccount(id), dr: 3500, cr: 0 }, { account: W.AVA_FEE_ACCOUNT, dr: 0, cr: 3500 }]);
    const out2 = await custodyTriggers(ev);
    assert.strictEqual(out2.wholesale.skipped, 'already_released');
    clock = new Date(T0.getTime() + 60 * 60 * 1000);
    const rc = await quiet(() => api.reconcile());
    assert.deepStrictEqual([rc.released, rc.returnFunded, rc.returned], [0, 0, 0]);
    assert.strictEqual(await bal(W.AVA_FEE_ACCOUNT), 3500);
    await assertLedgerSound();
  });

  await check('karta, AVA ulushi 0: ushlanma = yetkazish haqi; yetkazilganda jurnal yozuvi YO\'Q, eskrou 0, delivered', async () => {
    await seed({ extra: { quote: { avaFeeBps: 0, avaFee: 0, sellerPayout: 140000, cardHold: 60000 } } });
    const { orderId: id } = await place();
    assert.strictEqual(await bal(pcOf(SELLER)), 40000);
    await seedShipment(id);
    await linkAndFund(id);
    assert.strictEqual(await bal(W.escrowAccount(id)), 0);
    const out = await custodyTriggers(await deliverEvent(SHIP));
    assert.deepStrictEqual([out.wholesale.released, out.wholesale.card], [0, true]);
    assert.strictEqual((await journal(W.releaseKey(id))), undefined);
    const o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.payment.releaseEntryId], ['delivered', null]);
    assert.strictEqual(await bal(W.AVA_FEE_ACCOUNT), 0);
    await assertLedgerSound();
  });

  await check('RAD + QAYTISH: avaFee sotuvchiga, kuryer haqi relay eskrouda; qoldiq HALI emas → qaytish haqi sotuvchidan → returning → yetkazildi → returned + qoldiq +10', async () => {
    await seed({ sellerWallet: 200000 });
    const { orderId: id } = await place();
    await seedShipment(id);
    await linkAndFund(id);
    const r = await refuse(id);
    assert.deepStrictEqual([r.refunded, r.refusal, r.stockRestored], [3500, true, false], JSON.stringify(r));
    let o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.refundStatus, o.payment.status, o.payment.refusalRefund], ['refused', 'done', 'refusal_settled', 3500]);
    assert.strictEqual(await bal(W.escrowAccount(id)), 0);
    assert.strictEqual(await bal(pcOf(SELLER)), 200000 - HOLD + 3500);
    assert.strictEqual(await bal(relay.escrowAccount(SHIP)), 60000, 'kuryer haqi qaytarilmaydi (relay eskrouda)');
    assert.strictEqual((await stockOf()).packs.p1, 90, 'qoldiq rad paytida tiklanmaydi');
    assert.strictEqual((await db.collection('wholesale_buyer_stats').doc(BUYER).get()).data().cardRefusals, 1);
    const jr = await journal(`bonus:${W.refusedKey(id)}`);
    assert.deepStrictEqual(jr.legs, [{ account: W.escrowAccount(id), dr: 3500 }, { account: pcOf(SELLER), cr: 3500 }]);
    assert.strictEqual((await quiet(() => api.refundOrder(id))).skipped, 'already_refunded');
    // Qaytish jo'natmasi (demand bog'laydi) → trigger → sotuvchi hamyonidan 40 000.
    const f = await linkReturn(id);
    assert.strictEqual(f.funded, 40000, JSON.stringify(f));
    o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.returnStatus, o.returnPayment.status, o.returnPayment.amount], ['returning', 'in_transit', 'funded', 40000]);
    assert.strictEqual(await bal(pcOf(SELLER)), 200000 - HOLD + 3500 - 40000);
    assert.strictEqual(await bonusOf(SELLER), 200000 - HOLD + 3500 - 40000);
    assert.strictEqual(await bal(W.returnEscrowAccount(id)), 0);
    assert.strictEqual(await bal(relay.escrowAccount('R1')), 40000);
    const rs = (await db.collection('shipments').doc('R1').get()).data();
    assert.deepStrictEqual([rs.paymentStatus, rs.status, rs.escrowEntryId, rs.escrowAmount], ['escrow_funded', 'ready', W.returnFundKey(id), 40000]);
    assert.deepStrictEqual((await journal(`bonus:${W.returnHoldKey(id)}`)).legs,
      [{ account: pcOf(SELLER), dr: 40000 }, { account: W.returnEscrowAccount(id), cr: 40000 }]);
    assert.deepStrictEqual((await journal(W.returnFundKey(id))).legs,
      [{ account: W.returnEscrowAccount(id), dr: 40000, cr: 0 }, { account: relay.escrowAccount('R1'), dr: 0, cr: 40000 }]);
    assert.strictEqual((await quiet(() => api.fundReturn(id))).skipped, 'status_returning');
    // Qaytish yetkazildi (relay confirmDelivery → custody) → relay kuryerga, bizniki returned + qoldiq.
    const out = await custodyTriggers(await deliverEvent('R1'));
    assert.strictEqual(out.release.released, 40000);
    assert.deepStrictEqual([out.wholesale.returned, out.wholesale.stockRestored], [true, true]);
    o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.returnStatus, o.stock.restored], ['returned', 'returned', true]);
    assert.strictEqual((await stockOf()).packs.p1, 100);
    assert.strictEqual(await bal(relay.escrowAccount('R1')), 0);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), 32000);
    const out2 = await custodyTriggers(await deliverEvent('R1'));
    assert.strictEqual(out2.wholesale.skipped, 'already_returned');
    assert.strictEqual((await stockOf()).packs.p1, 100, 'qoldiq bir marta');
    const h = (await db.collection('wholesale_orders').doc(id).collection('history').get()).docs.map((d) => d.data().event).filter(Boolean);
    for (const ev of ['ship_funded', 'refusal_settled', 'return_funded', 'goods_returned']) assert.ok(h.includes(ev), ev);
    await assertLedgerSound();
  });

  await check('QAYTISH QARZI: hamyon yetmaydi → manfiyga tushmaydi, returnDebt + cardBlocked, trigger aylanmaydi, karta usuli yopiq; to\'ldirilgach reconcile to\'laydi, blok yechiladi', async () => {
    await seed({ sellerWallet: HOLD });
    const { orderId: id } = await place();
    await seedShipment(id);
    await linkAndFund(id);
    await refuse(id);
    assert.strictEqual(await bal(pcOf(SELLER)), 3500);
    const f = await linkReturn(id);
    assert.deepStrictEqual([f.debt, f.amount, f.attempts], [true, 40000, 1]);
    let o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.returnStatus, o.returnDebt.amount, o.returnDebt.attempts], ['refused', 'awaiting_payment', 40000, 1]);
    assert.strictEqual(await bal(pcOf(SELLER)), 3500, 'manfiyga tushmadi, hech narsa yechilmadi');
    assert.strictEqual(await bal(relay.escrowAccount('R1')), 0);
    const st = (await db.collection('wholesale_seller_stats').doc(SELLER).get()).data();
    assert.deepStrictEqual([st.cardBlocked, st.debtOrderIds], [true, [id]]);
    // Qarz yozuvi triggerni yana chaqiradi — u qayta urinmaydi.
    assert.strictEqual((await quiet(() => api.onStatusChange(o, o, id))).skipped, 'no_refund_needed');
    assert.strictEqual((await orderOf(id)).returnDebt.attempts, 1);
    // Karta usuli shu sotuvchi uchun yopiq (boshqa xaridor ham).
    await db.collection('wholesale_quotes').doc('q2').set(quoteDoc({ buyerId: BUYER2 }));
    await topup(SELLER, 100000);
    await expectErr(quiet(() => api.place({ quoteId: 'q2', clientRequestId: 'req-00000002' }, ctx(BUYER2))), 'failed-precondition', 'seller_debt');
    // Reconcile (qarz — yoshidan qat'i nazar): 100 000 + 3 500 ≥ 40 000 → to'landi.
    const rc = await quiet(() => api.reconcile());
    assert.deepStrictEqual([rc.returnFundChecked, rc.returnFunded], [1, 1]);
    o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.returnDebt, o.returnPayment.status], ['returning', null, 'funded']);
    assert.ok(o.returnDebtSettledAt);
    const st2 = (await db.collection('wholesale_seller_stats').doc(SELLER).get()).data();
    assert.deepStrictEqual([st2.cardBlocked, st2.debtOrderIds], [false, []]);
    assert.strictEqual(await bal(pcOf(SELLER)), 3500 + 100000 - 40000);
    assert.strictEqual(await bal(relay.escrowAccount('R1')), 40000);
    const rc2 = await quiet(() => api.reconcile());
    assert.strictEqual(rc2.returnFundChecked, 0);
    // Blok yechilgach karta usuli yana ochiq.
    const ok2 = await quiet(() => api.place({ quoteId: 'q2', clientRequestId: 'req-00000003' }, ctx(BUYER2)));
    assert.strictEqual(ok2.paymentMethod, 'card_on_delivery');
    await assertLedgerSound();
  });

  await check('qaytish haqi ≠ jo\'natma narxi → anomaliya: relay eskrouga pul O\'TMAYDI, buyurtma refused, trigger aylanmaydi', async () => {
    await seed({ sellerWallet: 200000 });
    const { orderId: id } = await place();
    await seedShipment(id);
    await linkAndFund(id);
    await refuse(id);
    const f = await linkReturn(id, { fee: 40000, shipPrice: 39999 });
    assert.deepStrictEqual([f.skipped, f.anomaly], ['return_fee_mismatch', true], JSON.stringify(f));
    const o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.returnAnomaly.code], ['refused', 'return_fee_mismatch']);
    assert.strictEqual(await bal(relay.escrowAccount('R1')), 0, 'relay eskrouga o\'tmadi');
    assert.strictEqual(await bal(W.returnEscrowAccount(id)), 40000, 'ushlanma o\'z eskrouda (admin ko\'radi)');
    assert.strictEqual((await quiet(() => api.onStatusChange(o, o, id))).skipped, 'no_refund_needed');
    clock = new Date(T0.getTime() + 60 * 60 * 1000);
    assert.strictEqual((await quiet(() => api.reconcile())).returnFundChecked, 0, 'anomaliya — reconcile ham urinmaydi');
    await assertLedgerSound();
  });

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\nwholesale_card (default): ${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
})();
