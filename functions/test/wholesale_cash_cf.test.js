/**
 * Ulgurji S57 — yetkazish haqi NAQD kuryerga (S5) + zanjir muddati — default codebase, HAQIQIY ledger
 * (Firestore Emulator):
 *
 *   firebase emulators:exec --only firestore --project demo-ulgcash "node functions/test/wholesale_cash_cf.test.js"
 *
 * Qulflanadi (ega CONFIRMED 2026-11-13/14; PROPOSED — alohida belgilangan):
 *   - paritet: DELIVERY_PAYMENT_METHODS / isCashDelivery ↔ demand
 *   - place: hamyon+naqd — AYNAN tovar summasi (G−1 → rad), yangi karta+naqd — xaridordan 0, sotuvchidan AVA ulushi,
 *     bank+naqd — pul YO'Q (`none`); muhrsiz/naqdsiz kvota farqi — quote_invalid
 *   - SHIP_FUND naqdda YO'Q (trigger + reconcile B), relay eskrou 0
 *   - yetkazildi: hamyon — sotuvchiga sellerPayout + AVA, eskrou 0; yangi karta — AVA ulushi AVA ga; bank — ledger yo'q;
 *     relay_cash yig'uvchi hamyonidan AVA logistika ulushini oladi (ikki hisob bir-biriga tegmaydi)
 *   - bekor: hamyon+naqd — G xaridorga + qoldiq; yangi karta+naqd — AVA ulushi sotuvchiga; bank+naqd — pulsiz
 *   - zanjir muddati [PROPOSED]: hamyon usuli — relay eskrou → buyurtma eskrousi → bekor → xaridorga TO'LIQ; naqd — bekor
 *     → tovar ushlanmasi qaytadi; ikkalasi idempotent; reconcile C
 *   - naqd rad TO'LADI: tovar puli xaridorga, chiqish LEG pulsiz yopiladi, qaytish eskrousi yig'uvchidan (relay_cash),
 *     buyurtma returning (payer buyer_cash), qarz yo'q
 *   - naqd rad TO'LAMADI (yangi karta): AVA ulushi sotuvchiga, AVA qaytishni qoplaydi, buyurtma returning (ava_cover),
 *     xaridor qarzi (`returnDebt`) SAQLANADI
 *   - yo'qolgan naqd posilka — pul YO'Q, anomaliya `cash_loss_unsupported`
 *   - Σdr == Σcr, aktiv == passiv, passenger_credit == bonusBalance
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18769';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-ulgcash';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const settlementLedger = require('../settlement_ledger');
const W = require('../wholesale_orders');
const C = require('../relay_cash');
const WO = require('../../functions_demand/core/wholesale_orders');

const BUYER = '998901110001';
const SELLER = '998901234567';
const K1 = '998902220002';
const T0 = new Date('2026-11-14T12:00:00Z');
let clock = T0;
const digits = (v) => String(v || '').replace(/\D/g, '');
const canon = (v) => { const d = digits(v); return d.length === 9 ? `998${d}` : d; };
const requireCallerRoles = async () => { throw new functions.https.HttpsError('permission-denied', 'no'); };
const depsCommon = {
  functions, db, admin, callerPhone: (c) => digits(c.auth.token.phone_number), canonicalUid: canon, settlementLedger, now: () => clock,
};
const relayCash = C.attachRelayCash({}, depsCommon);
const api = W.attachWholesaleOrders({}, { ...depsCommon, requireCallerRoles, relayCash });
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
const shipOf = async (id) => (await db.collection('shipments').doc(id).get()).data();
const stockOf = async () => (await db.collection('wholesale_stock').doc('rice').get()).data();
const journal = async (id) => (await db.collection(settlementLedger.COL_JOURNAL).doc(id).get());
async function assertLedgerSound() {
  const rec = await settlementLedger.reconcile(db);
  assert.strictEqual(rec.balanced, true, `Σdr==Σcr buzildi: ${rec.totalDr} != ${rec.totalCr}`);
  assert.strictEqual(rec.identityOk, true, `aktiv/passiv: ${rec.assets} != ${rec.liabilities}`);
  assert.strictEqual(rec.projectionOk, true, `bonusBalance ko'zgusi: ${JSON.stringify(rec.mismatches)}`);
}
let topupSeq = 0;
const topup = (uid, amount) => settlementLedger.postEntry(db, {
  idempotencyKey: `topupCash:${uid}:${topupSeq += 1}`, kind: 'test_topup',
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

// 10 × 14 000 = 140 000 (G); yetkazish 60 000 (AVA logistika 12 000 + kuryer puli 48 000); AVA ulushi 2 800.
const G = 140000;
const FEE = 60000;
const AVA = 2800;
const SHARE = 12000;
const POOL = 48000;
const RET = 25000;
function quoteDoc(paymentMethod, extra = {}) {
  return {
    buyerId: BUYER, sellerId: SELLER, productId: 'rice', productTitle: 'Guruch', packId: 'p1', packLabel: '1 kg',
    qty: 10, unitPrice: 14000, goodsTotal: G, deliveryFee: FEE, total: G + FEE, currency: 'UZS',
    delivery: { tariffVersion: 3, zone: 'ZONE_4', actualWeightG: 10000, chargeableWeightG: 10000, dims: null, priceSnapshot: { customerPrice: FEE } },
    avaFeeBps: 200, feeVersion: 4, avaFee: AVA, sellerPayout: G - AVA,
    origin: { regionId: 'xorazm' }, destination: { regionId: 'toshkent_shahri', addressText: 'Chilonzor' },
    paymentMethod, deliveryMethod: 'ava_courier', deliveryPaymentMethod: 'cash',
    ...(paymentMethod === 'card_on_delivery' ? { deliveryPaidBy: 'buyer', sellerFeeHold: AVA } : {}),
    ...(paymentMethod === 'bank_transfer' ? { bankHold: 0 } : {}),
    createdAt: clock, expiresAt: new Date(clock.getTime() + 15 * 60 * 1000), used: false,
    ...extra,
  };
}
const clean = (o) => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined));
async function seed({
  buyerWallet = 0, sellerWallet = 0, courierWallet = 0, quote,
} = {}) {
  clock = T0;
  await resetAll();
  await db.collection('module_config').doc('wholesale_orders_all').set({ enabled: true, stage: 'public', cashDeliveryEnabled: true });
  await db.collection('users').doc(BUYER).set({ bonusBalance: 0, accountId: 'acc_buyer' });
  await db.collection('users').doc(SELLER).set({ bonusBalance: 0 });
  await db.collection('users').doc(K1).set({ bonusBalance: 0, accountId: 'acc_k1' });
  await db.collection('wholesale_products').doc('rice').set({ sellerId: SELLER, status: 'active', market: 'wholesale' });
  await db.collection('wholesale_stock').doc('rice').set({ productId: 'rice', sellerId: SELLER, packs: { p1: 100 }, version: 1 });
  await db.collection('wholesale_sellers').doc(SELLER).set({ phone: SELLER, approvalStatus: 'approved' });
  await db.collection('wholesale_sellers').doc(SELLER).collection('private').doc('payout').set({ cardNumber: '4111111111111111', holderName: 'ALI VALIYEV' });
  await db.collection('wholesale_quotes').doc('q1').set(clean(quote || quoteDoc('wallet')));
  if (buyerWallet > 0) await topup(BUYER, buyerWallet);
  if (sellerWallet > 0) await topup(SELLER, sellerWallet);
  if (courierWallet > 0) await topup(K1, courierWallet);
}
const place = (req = 'req-00000001') => quiet(() => api.place({ quoteId: 'q1', clientRequestId: req }, ctx(BUYER)));

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

const SHIP = 'S1';
/** Demand `ensureWholesaleShipment` + `openWholesaleCashShipment` yozadigan holat (naqd jo'natma, LEG K1 qo'lida). */
async function linkAndOpenCash(orderId, { inHand = true } = {}) {
  await db.collection('shipments').doc(SHIP).set({
    orderId: `lo_${orderId}`, ownerId: SELLER, recipientId: BUYER, source: 'wholesale', wholesaleOrderId: orderId,
    trackingNumber: 'AVA-26-1114-000001', status: 'awaiting_payment', paymentStatus: 'pending',
    priceSnapshot: { customerPrice: FEE, tariffVersion: 3, declaredValue: G }, legIds: ['leg0'], legCount: 1, custodyCount: 0,
    deliveryPayment: {
      method: 'cash', amount: FEE, currency: 'UZS', status: 'pending', collectedBy: null, collectedAt: null,
      collectorLegId: 'leg0', collectorLegPayout: POOL,
    },
    createdAt: clock, updatedAt: clock,
  });
  await db.collection('shipments').doc(SHIP).collection('private').doc('internal').set({
    platformShare: SHARE, providerPool: POOL, legPayouts: [{ index: 0, kind: 'direct', amount: POOL }], tariffVersion: 3,
  });
  const ref = db.collection('wholesale_orders').doc(orderId);
  const before = (await ref.get()).data();
  await ref.update({ shipment: { shipmentId: SHIP, orderId: `lo_${orderId}`, trackingNumber: 'AVA-26-1114-000001', createdAt: clock }, historySeq: before.historySeq + 1 });
  // Default trigger shu bog'lanishni ko'radi — naqdda SHIP_FUND QILMAYDI.
  const r = await quiet(async () => api.onStatusChange(before, (await ref.get()).data(), orderId));
  assert.ok(!r || !r.funded, `naqdda SHIP_FUND yo'q: ${JSON.stringify(r)}`);
  // Demand: relay openCashShipment + buyurtma in_delivery.
  await db.collection('shipments').doc(SHIP).update({ status: 'ready', paymentStatus: 'cash_on_delivery', fundedAt: clock });
  const o = (await ref.get()).data();
  await ref.update({
    status: 'in_delivery', statusUpdatedAt: clock, historySeq: o.historySeq + 1,
    cashDelivery: { status: 'opened', shipmentId: SHIP, amount: FEE, currency: 'UZS', openedAt: clock },
  });
  if (inHand) {
    await db.collection('shipments').doc(SHIP).update({
      status: 'in_transit', custodyCount: 1, legAssignments: { leg0: K1 }, currentLegId: 'leg0', currentCustodian: { kind: 'provider', id: K1, since: clock },
    });
    await db.collection('demands').doc('leg0').set({ module: 'logistics', status: 'in_progress', assignment: { providerId: K1 }, attributes: { shipmentId: SHIP } });
    await db.collection('demand_matches').doc(`leg0_${K1}`).set({ status: 'in_progress', providerId: K1, contactUnlocked: { recipientPhone: BUYER } });
  }
}
/** Relay `confirmDelivery` (naqd, cashCollected) yozadigan holat. */
async function deliverCash() {
  await db.collection('shipments').doc(SHIP).update({
    status: 'delivered', deliveredAt: clock, currentCustodian: { kind: 'recipient', id: null, since: clock },
    'deliveryPayment.status': 'collected', 'deliveryPayment.collectedBy': K1, 'deliveryPayment.collectedAt': clock,
  });
}
/** Demand yakuniy rad (relay `recordCashRefusal` + `finalizeInTx`) yozadigan holat. */
async function refuseCash(orderId, paid) {
  const refusal = {
    paid, deliveryFee: FEE, returnFee: RET, total: FEE + RET, returnTariffVersion: 3, currency: 'UZS',
    collectorId: K1, legId: 'leg0', collectorLegPayout: POOL, at: clock,
  };
  await db.collection('shipments').doc(SHIP).update({
    'deliveryPayment.status': paid ? 'refusal_collected' : 'refusal_unpaid',
    'deliveryPayment.refusal': refusal,
    ...(paid ? { 'deliveryPayment.collectedBy': K1, 'deliveryPayment.collectedAt': clock } : {}),
  });
  await patchAndChain(orderId, {
    status: 'refused', refundStatus: 'pending', refusedAt: clock, statusUpdatedAt: clock,
    refusal: { by: K1, via: 'courier', reasonCode: paid ? 'customer_refused' : 'customer_absent', shipmentId: SHIP, legId: 'leg0', cashPaid: paid },
    returnStatus: 'pending_shipment',
    cashRefusal: {
      paid, deliveryFee: FEE, returnFee: RET, total: FEE + RET, returnTariffVersion: 3, collectorId: K1, at: clock,
    },
    ...(paid ? {} : {
      returnDebt: {
        payer: 'buyer', kind: 'cash_refusal', amount: FEE + RET, deliveryFee: FEE, returnFee: RET, status: 'open', shipmentId: SHIP, at: clock,
      },
    }),
  });
}
/** Demand `ensureWholesaleReturnShipment` (naqd: AYNAN refusal.returnFee). */
async function linkReturn(orderId) {
  await db.collection('shipments').doc('R1').set({
    ownerId: SELLER, recipientId: SELLER, status: 'awaiting_payment', paymentStatus: 'pending', source: 'wholesale_return',
    wholesaleOrderId: orderId, wholesaleReturn: true, outboundShipmentId: SHIP, priceSnapshot: { customerPrice: RET, tariffVersion: 3 },
    legIds: ['rleg0'], legCount: 1, createdAt: clock, updatedAt: clock,
  });
  await db.collection('shipments').doc('R1').collection('private').doc('internal').set({
    platformShare: 5000, providerPool: 20000, legPayouts: [{ index: 0, amount: 20000 }], tariffVersion: 3,
  });
  await patchAndChain(orderId, {
    returnShipment: { shipmentId: 'R1', orderId: 'lo_r1', legId: 'rleg0', trackingNumber: 'AVA-R', fee: RET, tariffVersion: 3, courierId: K1, createdAt: clock },
    returnStatus: 'awaiting_payment',
  });
}

(async () => {
  await check('paritet: DELIVERY_PAYMENT_METHODS / isCashDelivery ↔ demand; naqd SHIP_FUND va lost kalitlari', async () => {
    assert.deepStrictEqual([...W.DELIVERY_PAYMENT_METHODS], [...WO.DELIVERY_PAYMENT_METHODS]);
    for (const d of [{}, { deliveryPaymentMethod: 'cash' }, { deliveryPaymentMethod: 'cash', deliveryMethod: 'self' }, { deliveryPaymentMethod: 'wallet' }]) {
      assert.strictEqual(W.isCashDelivery(d), WO.isCashDelivery(d), JSON.stringify(d));
    }
    assert.strictEqual(W.CHAIN_EXPIRED_REASON, WO.CANCEL_REASON.COURIER_CHAIN_EXPIRED);
    assert.strictEqual(W.chainExpiredKey('x'), 'wholesaleChainExpired:x');
  });

  await check('place hamyon+naqd: AYNAN tovar summasi ushlanadi (G−1 → rad, hech narsa yozilmaydi), order.deliveryPaymentMethod cash', async () => {
    await seed({ buyerWallet: G - 1 });
    await expectErr(place('req-low-0001'), 'failed-precondition', 'insufficient_balance');
    assert.strictEqual((await db.collection('wholesale_orders').get()).size, 0);
    await topup(BUYER, 1);
    const r = await place();
    const o = await orderOf(r.orderId);
    assert.deepStrictEqual([o.deliveryPaymentMethod, o.payment.status, o.payment.amount, o.payment.covers], ['cash', 'held', G, 'goods']);
    assert.strictEqual(o.total, G + FEE, 'jami (ko\'rsatish) o\'zgarmagan');
    assert.strictEqual(await bal(pcOf(BUYER)), 0);
    assert.strictEqual(await bal(W.escrowAccount(r.orderId)), G);
    const h1 = (await db.collection('wholesale_orders').doc(r.orderId).collection('history').doc('1').get()).data();
    assert.deepStrictEqual([h1.meta.deliveryPaymentMethod, h1.meta.cashToCourier, h1.meta.walletHold], ['cash', FEE, G]);
    await assertLedgerSound();
  });

  await check('place: kvota muhri mos emas (naqd belgisi olib tashlangan / boshqacha) — quote_invalid', async () => {
    await seed({ buyerWallet: G + FEE, quote: quoteDoc('wallet', { deliveryPaymentMethod: 'cash' }) });
    await db.collection('wholesale_quotes').doc('q1').update({ deliveryPaymentMethod: admin.firestore.FieldValue.delete() });
    // tranzaksiyadan oldin naqd deb o'qilgan, ichida — hamyon: muhr o'zgargan (poyga) — bu yerda boshqa holat:
    // naqdsiz muhr — oddiy hamyon (tovar + haq ushlanadi), quote_invalid emas.
    const r = await place();
    assert.strictEqual((await orderOf(r.orderId)).payment.amount, G + FEE);
    await seed({ buyerWallet: G, quote: quoteDoc('wallet', { deliveryFee: 0, total: G }) });
    await expectErr(place('req-zero-0001'), 'failed-precondition', 'quote_invalid');
  });

  await check('place yangi karta+naqd: xaridordan 0 (hamyon 0 bilan ham), sotuvchidan AVA ulushi; bank+naqd: pul YO\'Q', async () => {
    await seed({ sellerWallet: AVA, quote: quoteDoc('card_on_delivery') });
    const r = await place();
    const o = await orderOf(r.orderId);
    assert.deepStrictEqual([o.payment.status, o.payment.amount, o.payment.covers, o.payment.holdEntryId], ['held', 0, 'none', null]);
    assert.strictEqual(o.payment.sellerFeeHold.amount, AVA);
    assert.strictEqual(await bal(W.escrowAccount(r.orderId)), AVA);
    assert.strictEqual(await bal(pcOf(SELLER)), 0);
    assert.strictEqual((await journal(`bonus:${W.holdKey(r.orderId)}`)).exists, false, 'xaridor ushlanmasi yozilmagan');
    await assertLedgerSound();

    await seed({ quote: quoteDoc('bank_transfer') });
    const b = await place();
    const ob = await orderOf(b.orderId);
    assert.deepStrictEqual([ob.payment.status, ob.payment.amount, ob.deliveryPaymentMethod], ['none', 0, 'cash']);
    assert.strictEqual(await bal(W.escrowAccount(b.orderId)), 0);
    const st = (await db.collection('wholesale_orders').doc(b.orderId).collection('private').doc('settlement').get()).data();
    assert.strictEqual(st.avaFeeCollection, 'statement');
  });

  await check('naqd: SHIP_FUND YO\'Q (trigger + reconcile B); hamyon yetkazildi → sotuvchiga sellerPayout + AVA, eskrou 0; relay_cash yig\'uvchidan AVA logistika ulushi', async () => {
    await seed({ buyerWallet: G, courierWallet: SHARE });
    const r = await place();
    await linkAndOpenCash(r.orderId);
    assert.strictEqual((await journal(W.shipFundKey(r.orderId))).exists, false);
    assert.strictEqual(await bal(W.shipmentEscrowAccount(SHIP)), 0);
    clock = new Date(T0.getTime() + 60 * 60 * 1000);
    const rec = await quiet(() => api.reconcile({ minAgeMs: 0 }));
    assert.strictEqual(rec.shipFundChecked, 0, 'reconcile B naqdni o\'tkazadi');
    await deliverCash();
    const rel = await quiet(() => api.onShipmentDelivered(SHIP));
    assert.deepStrictEqual([rel.released, rel.sellerPayout, rel.avaFee], [G, G - AVA, AVA]);
    const o = await orderOf(r.orderId);
    assert.deepStrictEqual([o.status, o.payment.status], ['delivered', 'released']);
    assert.strictEqual(await bal(W.escrowAccount(r.orderId)), 0);
    assert.strictEqual(await bal(pcOf(SELLER)), G - AVA);
    // Relay naqd hisobi (functions/relay_cash.js) — yig'uvchi hamyonidan AVA logistika ulushi (bitta LEG: oldingi LEG yo'q).
    const rc = await quiet(() => relayCash.processShipment(SHIP));
    assert.strictEqual(rc.final.settled, true);
    assert.strictEqual(await bal(pcOf(K1)), 0);
    assert.strictEqual(await bal('earnings:ava_logistics_fee'), SHARE);
    assert.strictEqual((await shipOf(SHIP)).paymentStatus, 'settled');
    await assertLedgerSound();
  });

  await check('naqd yetkazildi: yangi karta — AVA ulushi AVA ga (eskrou 0); bank — ledger yozuvi yo\'q, delivered', async () => {
    await seed({ sellerWallet: AVA, quote: quoteDoc('card_on_delivery') });
    const r = await place();
    await linkAndOpenCash(r.orderId);
    await deliverCash();
    const rel = await quiet(() => api.onShipmentDelivered(SHIP));
    assert.strictEqual(rel.released, AVA);
    assert.strictEqual(await bal(W.escrowAccount(r.orderId)), 0);
    assert.strictEqual(await bal(W.AVA_FEE_ACCOUNT), AVA);
    assert.strictEqual((await orderOf(r.orderId)).status, 'delivered');
    await assertLedgerSound();

    await seed({ quote: quoteDoc('bank_transfer') });
    const b = await place();
    await linkAndOpenCash(b.orderId);
    await deliverCash();
    const rb = await quiet(() => api.onShipmentDelivered(SHIP));
    assert.strictEqual(rb.bank, true);
    assert.strictEqual((await orderOf(b.orderId)).status, 'delivered');
    assert.strictEqual((await journal(W.releaseKey(b.orderId))).exists, false);
  });

  await check('naqd bekor: hamyon — G xaridorga + qoldiq; yangi karta — AVA ulushi sotuvchiga (xaridorga 0); bank — pulsiz, qoldiq', async () => {
    await seed({ buyerWallet: G });
    const r = await place();
    await patchAndChain(r.orderId, { status: 'cancelled', refundStatus: 'pending', cancelledBy: 'buyer', statusUpdatedAt: clock });
    let o = await orderOf(r.orderId);
    assert.deepStrictEqual([o.refundStatus, o.payment.status], ['done', 'refunded']);
    assert.strictEqual(await bal(pcOf(BUYER)), G);
    assert.strictEqual((await stockOf()).packs.p1, 100);
    await assertLedgerSound();

    await seed({ sellerWallet: AVA, quote: quoteDoc('card_on_delivery') });
    const c = await place();
    await patchAndChain(c.orderId, { status: 'cancelled', refundStatus: 'pending', cancelledBy: 'buyer', statusUpdatedAt: clock });
    o = await orderOf(c.orderId);
    assert.deepStrictEqual([o.refundStatus, o.payment.sellerFeeRefund, o.payment.refundEntryId], ['done', AVA, null]);
    assert.deepStrictEqual([await bal(pcOf(SELLER)), await bal(pcOf(BUYER)), await bal(W.escrowAccount(c.orderId))], [AVA, 0, 0]);
    await assertLedgerSound();

    await seed({ quote: quoteDoc('bank_transfer') });
    const b = await place();
    await patchAndChain(b.orderId, { status: 'cancelled', refundStatus: 'pending', cancelledBy: 'buyer', statusUpdatedAt: clock });
    o = await orderOf(b.orderId);
    assert.deepStrictEqual([o.refundStatus, o.payment.status], ['done', 'cancelled']);
    assert.strictEqual((await stockOf()).packs.p1, 100);
  });

  await check('zanjir muddati [PROPOSED], NAQD: jo\'natma cancelled + expired → buyurtma bekor (courier_chain_expired) → G xaridorga, qoldiq; idempotent', async () => {
    await seed({ buyerWallet: G });
    const r = await place();
    await linkAndOpenCash(r.orderId, { inHand: false });
    await db.collection('shipments').doc(SHIP).update({ status: 'cancelled', chain: { mode: 'assemble_all', state: 'expired', expiredAt: clock } });
    const before = await orderOf(r.orderId);
    const out = await quiet(() => api.onChainExpired(SHIP));
    assert.strictEqual(out.cancelled, true);
    await chain(r.orderId, before);
    const o = await orderOf(r.orderId);
    assert.deepStrictEqual([o.status, o.cancelReason, o.cancelledBy, o.refundStatus], ['cancelled', 'courier_chain_expired', 'system', 'done']);
    assert.strictEqual(await bal(pcOf(BUYER)), G);
    assert.strictEqual((await stockOf()).packs.p1, 100);
    const again = await quiet(() => api.onChainExpired(SHIP));
    assert.strictEqual(again.skipped, 'status_cancelled');
    assert.strictEqual(await bal(pcOf(BUYER)), G);
    await assertLedgerSound();
  });

  await check('zanjir muddati [PROPOSED], HAMYON usuli: relay eskrou → buyurtma eskrousi (bitta yozuv) → bekor → xaridorga tovar + haq TO\'LIQ; takror/reconcile — bir marta', async () => {
    await seed({ buyerWallet: G + FEE, quote: quoteDoc('wallet', { deliveryPaymentMethod: undefined }) });
    const r = await place();
    // SHIP_FUND (hamyon usuli) — default haqiqiy yo'l.
    await db.collection('shipments').doc(SHIP).set({
      orderId: `lo_${r.orderId}`, ownerId: SELLER, recipientId: BUYER, source: 'wholesale', wholesaleOrderId: r.orderId,
      status: 'awaiting_payment', paymentStatus: 'pending', priceSnapshot: { customerPrice: FEE, tariffVersion: 3, declaredValue: G },
      legIds: ['leg0'], legCount: 1, createdAt: clock, updatedAt: clock,
    });
    const ref = db.collection('wholesale_orders').doc(r.orderId);
    const b0 = (await ref.get()).data();
    await ref.update({ shipment: { shipmentId: SHIP, orderId: 'lo', trackingNumber: 'T', createdAt: clock }, historySeq: b0.historySeq + 1 });
    const sf = await quiet(async () => api.onStatusChange(b0, (await ref.get()).data(), r.orderId));
    assert.strictEqual(sf.funded, FEE);
    assert.strictEqual(await bal(W.shipmentEscrowAccount(SHIP)), FEE);
    // Relay `expireChain` (Ulgurji): wholesale_refund_pending, chain expired, cancelled.
    await db.collection('shipments').doc(SHIP).update({
      status: 'cancelled', paymentStatus: 'wholesale_refund_pending', chain: { mode: 'assemble_all', state: 'expired', expiredAt: clock },
    });
    clock = new Date(T0.getTime() + 49 * 3600 * 1000);
    const before = await orderOf(r.orderId);
    const rec = await quiet(() => api.reconcile({ minAgeMs: 0 }));
    assert.strictEqual(rec.chainExpiredCancelled, 1, JSON.stringify(rec));
    await chain(r.orderId, before);
    const o = await orderOf(r.orderId);
    assert.deepStrictEqual([o.status, o.cancelReason, o.refundStatus, o.payment.status, o.payment.deliveryFunded],
      ['cancelled', 'courier_chain_expired', 'done', 'refunded', false]);
    assert.strictEqual(o.payment.deliveryReturnEntryId, W.chainExpiredKey(r.orderId));
    assert.strictEqual(await bal(pcOf(BUYER)), G + FEE, 'xaridor TO\'LIQ oldi (tovar + yetkazish haqi)');
    assert.deepStrictEqual([await bal(W.shipmentEscrowAccount(SHIP)), await bal(W.escrowAccount(r.orderId))], [0, 0]);
    const s = await shipOf(SHIP);
    assert.deepStrictEqual([s.paymentStatus, s.refundEntryId], ['refunded', W.chainExpiredKey(r.orderId)]);
    assert.strictEqual((await stockOf()).packs.p1, 100);
    const again = await quiet(() => api.onChainExpired(SHIP));
    assert.ok(again.skipped, JSON.stringify(again));
    assert.strictEqual(await bal(pcOf(BUYER)), G + FEE);
    await assertLedgerSound();
  });

  await check('naqd rad TO\'LADI (hamyon): tovar puli xaridorga, chiqish LEG pulsiz yopiladi, qaytish eskrousi yig\'uvchidan, returning (buyer_cash), qarz yo\'q', async () => {
    await seed({ buyerWallet: G, courierWallet: SHARE + RET });
    const r = await place();
    await linkAndOpenCash(r.orderId);
    await refuseCash(r.orderId, true);
    let o = await orderOf(r.orderId);
    assert.deepStrictEqual([o.refundStatus, o.payment.status, o.cashRefusalSettlement.goodsRefunded, o.cashRefusalSettlement.buyerDebt],
      ['done', 'refusal_refunded', G, 0]);
    assert.strictEqual(await bal(pcOf(BUYER)), G, 'tovar summasi qaytdi');
    assert.strictEqual(o.walletRefusal, undefined, 'hamyon rad yo\'li ishlamadi (qaytish ushlanmasi yo\'q)');
    assert.deepStrictEqual([o.outboundSettlement.status, o.outboundSettlement.cash], ['settled', true]);
    assert.strictEqual((await db.collection('demands').doc('leg0').get()).data().status, 'completed');
    assert.strictEqual((await shipOf(SHIP)).wholesaleOutcome, 'refused');
    assert.strictEqual((await journal(W.relayReleaseKey(SHIP))).exists, false, 'relay eskrou yozuvi YO\'Q (naqd)');
    await linkReturn(r.orderId);
    o = await orderOf(r.orderId);
    assert.deepStrictEqual([o.status, o.returnPayment.status, o.returnPayment.payer, o.returnPayment.amount], ['returning', 'funded', 'buyer_cash', RET]);
    const rs = await shipOf('R1');
    assert.deepStrictEqual([rs.paymentStatus, rs.status, rs.fundedBy], ['escrow_funded', 'ready', 'cash_refusal']);
    assert.strictEqual(await bal(W.shipmentEscrowAccount('R1')), RET);
    assert.strictEqual(await bal(pcOf(K1)), 0, 'yig\'uvchi: AVA ulushi + qaytish haqi hamyonidan (naqd qo\'lida)');
    assert.strictEqual((await journal(`bonus:${W.returnHoldKey(r.orderId)}`)).exists, false, 'Ulgurji qaytish ushlanmasi YO\'Q');
    assert.strictEqual((await shipOf(SHIP)).paymentStatus, 'settled');
    assert.strictEqual(o.returnDebt, undefined);
    await assertLedgerSound();
  });

  await check('naqd rad TO\'LAMADI (yangi karta): AVA ulushi sotuvchiga, AVA qaytishni qoplaydi, returning (ava_cover), xaridor qarzi SAQLANADI', async () => {
    await seed({ sellerWallet: AVA, quote: quoteDoc('card_on_delivery') });
    const r = await place();
    await linkAndOpenCash(r.orderId);
    await refuseCash(r.orderId, false);
    let o = await orderOf(r.orderId);
    assert.deepStrictEqual([o.refundStatus, o.payment.status, o.cashRefusalSettlement.sellerFeeRefunded, o.cashRefusalSettlement.buyerDebt],
      ['done', 'refusal_settled', AVA, FEE + RET]);
    assert.strictEqual(await bal(pcOf(SELLER)), AVA);
    await linkReturn(r.orderId);
    o = await orderOf(r.orderId);
    assert.deepStrictEqual([o.status, o.returnPayment.payer], ['returning', 'ava_cover']);
    assert.deepStrictEqual([o.returnDebt.payer, o.returnDebt.kind, o.returnDebt.amount], ['buyer', 'cash_refusal', FEE + RET], 'qarz yopilmagan');
    assert.strictEqual(await bal(W.shipmentEscrowAccount('R1')), RET);
    assert.strictEqual(await bal(pcOf(K1)), 0, 'kuryer hamyoniga tegilmadi');
    const s = await shipOf(SHIP);
    assert.strictEqual(s.deliveryPayment.buyerDebt.amount, FEE + RET);
    // Reconcile D qarzli naqd buyurtmani qayta to'lamaydi (bir marta).
    clock = new Date(T0.getTime() + 2 * 3600 * 1000);
    await quiet(() => api.reconcile({ minAgeMs: 0 }));
    assert.strictEqual(await bal(W.shipmentEscrowAccount('R1')), RET);
    await assertLedgerSound();
  });

  await check('yo\'qolgan naqd posilka: settleLost — pul YO\'Q, anomaliya cash_loss_unsupported', async () => {
    await seed({ buyerWallet: G });
    const r = await place();
    await linkAndOpenCash(r.orderId);
    await db.collection('shipments').doc(SHIP).update({ paymentStatus: 'loss_settled' });
    const out = await quiet(() => api.settleLost(r.orderId));
    assert.deepStrictEqual([out.skipped, out.anomaly], ['cash_loss_unsupported', true]);
    const o = await orderOf(r.orderId);
    assert.strictEqual(o.status, 'in_delivery');
    assert.strictEqual(o.lostAnomaly.code, 'cash_loss_unsupported');
    assert.strictEqual(await bal(W.escrowAccount(r.orderId)), G);
  });

  const passed = results.filter((x) => x.pass).length;
  console.log(`\n${passed}/${results.length} wholesale cash CF checks passed.`);
  process.exit(passed === results.length ? 0 : 1);
})();
