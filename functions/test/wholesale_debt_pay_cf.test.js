/**
 * Ulgurji — XARIDOR QARZINI HAMYONDAN TO'LASH (`payWholesaleBuyerDebt`, ega CONFIRMED 2026-11-15, A varianti) —
 * default codebase, HAQIQIY ledger (Firestore Emulator):
 *
 *   firebase emulators:exec --only firestore --project demo-ulgdebt "node functions/test/wholesale_debt_pay_cf.test.js"
 *
 * Qulflanadi:
 *   - sof reja `relay_cash.planBuyerDebtPayment`: komponentlar Σ == amount; har bir nomuvofiqlik — kod, pul yo'q
 *   - naqd rad qarzi (`kind: cash_refusal`): hamyon yetmaydi (0 va amount−1) → insufficient_balance {amount, balance},
 *     hech narsa yozilmaydi; amount → bitta postEntry: xaridor −amount, admin_clearing −avaCovered (AVA qoplamasi
 *     qaytdi), yig'uvchi +keep−serviceFee, xizmat haqi +serviceFee, AVA logistika +platformShare; returnDebt null +
 *     returnDebtPaid, shipment buyerDebt paid, history, audit, wallet_ledger, xabarlar (xaridor + admin, 3 til);
 *     demand `buyerHasOpenDebt` → false
 *   - relay_cash C yo'li tugamagan (qaytish eskrousi hali yo'q) → debt_not_ready, pul yo'q
 *   - parallel/takror bosish → BITTA to'lov (idempotent)
 *   - muhrlangan summa buzilgan (avaCovered / platformShare) → anomaliya, pul YO'Q
 *   - xaridor emas / kirmagan → rad; qarz yo'q → debt_not_open
 *   - hamyon radi qarzi (kind yo'q): mavjud `fundReturn` orqali darhol — rest ushlanma + FUND, returning
 *   - Σdr == Σcr, aktiv == passiv, passenger_credit == bonusBalance
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18771';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-ulgdebt';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const settlementLedger = require('../settlement_ledger');
const W = require('../wholesale_orders');
const C = require('../relay_cash');
const DW = require('../../functions_demand/api/wholesale_orders');

const BUYER = '998901110001';
const SELLER = '998901234567';
const K1 = '998902220002';
const ADMIN = '998905550005';
const T0 = new Date('2026-11-15T09:00:00Z');
let clock = T0;
const digits = (v) => String(v || '').replace(/\D/g, '');
const canon = (v) => { const d = digits(v); return d.length === 9 ? `998${d}` : d; };
const requireCallerRoles = async () => { throw new functions.https.HttpsError('permission-denied', 'no'); };
const depsCommon = {
  functions, db, admin, callerPhone: (c) => digits(c.auth.token.phone_number), canonicalUid: canon, settlementLedger, now: () => clock,
};
const relayCash = C.attachRelayCash({}, depsCommon);
const exported = {};
const api = W.attachWholesaleOrders(exported, { ...depsCommon, requireCallerRoles, relayCash });
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
const shipOf = async (id) => (await db.collection('shipments').doc(id).get()).data();
const journal = async (id) => (await db.collection(settlementLedger.COL_JOURNAL).doc(id).get());
const journalSize = async () => (await db.collection(settlementLedger.COL_JOURNAL).get()).size;
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
  idempotencyKey: `topupDebt:${uid}:${topupSeq += 1}`, kind: 'test_topup',
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
const pay = (orderId, phone = BUYER) => quiet(() => api.payBuyerDebt({ orderId }, ctx(phone)));

// Naqd: 10 × 14 000 = 140 000 (G); yetkazish 60 000 = AVA logistika 12 000 + kuryer puli 48 000; qaytish 25 000.
const G = 140000;
const FEE = 60000;
const AVA = 2800;
const SHARE = 12000;
const POOL = 48000;
const RET = 25000;
const DEBT = FEE + RET; // 85 000 = SHARE 12 000 + avaCovered (0 + 25 000) + owed 48 000
const FEE_BPS = 1000; // kuryer xizmat haqi 10% → 4 800, sof 43 200
const SVC = 4800;
function quoteDoc(paymentMethod, extra = {}) {
  return {
    buyerId: BUYER, sellerId: SELLER, productId: 'rice', productTitle: 'Guruch', packId: 'p1', packLabel: '1 kg',
    qty: 10, unitPrice: 14000, goodsTotal: G, deliveryFee: FEE, total: G + FEE, currency: 'UZS',
    delivery: { tariffVersion: 3, zone: 'ZONE_4', actualWeightG: 10000, chargeableWeightG: 10000, dims: null, priceSnapshot: { customerPrice: FEE } },
    avaFeeBps: 200, feeVersion: 4, avaFee: AVA, sellerPayout: G - AVA,
    origin: { regionId: 'xorazm' }, destination: { regionId: 'toshkent_shahri', addressText: 'Chilonzor' },
    paymentMethod, deliveryMethod: 'ava_courier', deliveryPaymentMethod: 'cash',
    ...(paymentMethod === 'card_on_delivery' ? { deliveryPaidBy: 'buyer', sellerFeeHold: AVA } : {}),
    createdAt: clock, expiresAt: new Date(clock.getTime() + 15 * 60 * 1000), used: false,
    ...extra,
  };
}
async function seed({ buyerWallet = 0, sellerWallet = 0, courierWallet = 0, quote } = {}) {
  clock = T0;
  await resetAll();
  await db.collection('module_config').doc('wholesale_orders_all').set({ enabled: true, stage: 'public', cashDeliveryEnabled: true });
  await db.collection('settings').doc('courier_service_fee').set({ feeBps: FEE_BPS, feeVersion: 2, autoPayoutEnabled: true });
  await db.collection('users').doc(BUYER).set({ bonusBalance: 0, accountId: 'acc_buyer', appLang: 'uz_Latn' });
  await db.collection('users').doc(SELLER).set({ bonusBalance: 0 });
  await db.collection('users').doc(K1).set({ bonusBalance: 0, accountId: 'acc_k1' });
  await db.collection('users').doc(ADMIN).set({ role: 'admin', appLang: 'ru' });
  await db.collection('wholesale_products').doc('rice').set({ sellerId: SELLER, status: 'active', market: 'wholesale', packs: [{ id: 'p1', label: '1 kg', priceTiers: [{ minQty: 1, price: 15000 }, { minQty: 10, price: 14000 }], unitWeightG: 1000 }] }); // place narxni qayta hisoblaydi (ega 2026-11-20)
  await db.collection('wholesale_stock').doc('rice').set({ productId: 'rice', sellerId: SELLER, packs: { p1: 100 }, version: 1 });
  await db.collection('wholesale_sellers').doc(SELLER).set({ phone: SELLER, approvalStatus: 'approved' });
  await db.collection('wholesale_sellers').doc(SELLER).collection('private').doc('payout').set({ cardNumber: '4111111111111111', holderName: 'ALI VALIYEV' });
  await db.collection('wholesale_quotes').doc('q1').set(quote || quoteDoc('card_on_delivery'));
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
/** Demand `ensureWholesaleShipment` + `openWholesaleCashShipment` (bitta LEG, K1 qo'lida). */
async function linkAndOpenCash(orderId) {
  await db.collection('shipments').doc(SHIP).set({
    orderId: `lo_${orderId}`, ownerId: SELLER, recipientId: BUYER, source: 'wholesale', wholesaleOrderId: orderId,
    trackingNumber: 'AVA-26-1115-000001', status: 'awaiting_payment', paymentStatus: 'pending',
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
  await ref.update({ shipment: { shipmentId: SHIP, orderId: `lo_${orderId}`, trackingNumber: 'AVA-26-1115-000001', createdAt: clock }, historySeq: before.historySeq + 1 });
  await quiet(async () => api.onStatusChange(before, (await ref.get()).data(), orderId));
  await db.collection('shipments').doc(SHIP).update({ status: 'ready', paymentStatus: 'cash_on_delivery', fundedAt: clock });
  const o = (await ref.get()).data();
  await ref.update({
    status: 'in_delivery', statusUpdatedAt: clock, historySeq: o.historySeq + 1,
    cashDelivery: { status: 'opened', shipmentId: SHIP, amount: FEE, currency: 'UZS', openedAt: clock },
  });
  await db.collection('shipments').doc(SHIP).update({
    status: 'in_transit', custodyCount: 1, legAssignments: { leg0: K1 }, currentLegId: 'leg0', currentCustodian: { kind: 'provider', id: K1, since: clock },
  });
  await db.collection('demands').doc('leg0').set({ module: 'logistics', status: 'in_progress', assignment: { providerId: K1 }, attributes: { shipmentId: SHIP } });
  await db.collection('demand_matches').doc(`leg0_${K1}`).set({ status: 'in_progress', providerId: K1, contactUnlocked: { recipientPhone: BUYER } });
}
/** Demand yakuniy rad, xaridor TO'LAMADI (relay `recordCashRefusal` + `finalizeInTx`). */
async function refuseCashUnpaid(orderId) {
  await db.collection('shipments').doc(SHIP).update({
    'deliveryPayment.status': 'refusal_unpaid',
    'deliveryPayment.refusal': {
      paid: false, deliveryFee: FEE, returnFee: RET, total: DEBT, returnTariffVersion: 3, currency: 'UZS',
      collectorId: K1, legId: 'leg0', collectorLegPayout: POOL, at: clock,
    },
  });
  await patchAndChain(orderId, {
    status: 'refused', refundStatus: 'pending', refusedAt: clock, statusUpdatedAt: clock,
    refusal: { by: K1, via: 'courier', reasonCode: 'customer_absent', shipmentId: SHIP, legId: 'leg0', cashPaid: false },
    returnStatus: 'pending_shipment',
    cashRefusal: { paid: false, deliveryFee: FEE, returnFee: RET, total: DEBT, returnTariffVersion: 3, collectorId: K1, at: clock },
    returnDebt: {
      payer: 'buyer', kind: 'cash_refusal', amount: DEBT, deliveryFee: FEE, returnFee: RET, status: 'open', shipmentId: SHIP, at: clock,
    },
  });
}
/** Demand `ensureWholesaleReturnShipment` → relay_cash C (AVA qoplaydi) → returning. */
async function linkReturnCash(orderId) {
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
async function cashDebtOrder() {
  await seed({ sellerWallet: AVA });
  const r = await place();
  await linkAndOpenCash(r.orderId);
  await refuseCashUnpaid(r.orderId);
  await linkReturnCash(r.orderId);
  const o = await orderOf(r.orderId);
  assert.deepStrictEqual([o.status, o.returnDebt.kind, o.returnDebt.amount, o.returnDebt.status], ['returning', 'cash_refusal', DEBT, 'open']);
  const s = await shipOf(SHIP);
  assert.deepStrictEqual([s.paymentStatus, s.deliveryPayment.buyerDebt.status, s.deliveryPayment.buyerDebt.avaCovered, s.deliveryPayment.buyerDebt.owedToCollector],
    ['settled', 'open', RET, POOL]);
  return r.orderId;
}

(async () => {
  // ── Sof reja ──
  await check('sof: planBuyerDebtPayment — komponentlar Σ == amount, oyoqlar; har nomuvofiqlik — kod', async () => {
    const base = {
      amount: DEBT, deliveryFee: FEE, returnFee: RET, platformShare: SHARE, providerPool: POOL, keep: POOL, avaCovered: RET,
      owedToCollector: POOL, serviceFee: SVC, buyerAccount: pcOf(BUYER), collectorAccount: pcOf(K1),
    };
    const p = C.planBuyerDebtPayment(base);
    assert.deepStrictEqual([p.avaCovered, p.collectorNet, p.serviceFee, p.platformShare], [RET, POOL - SVC, SVC, SHARE]);
    assert.deepStrictEqual(p.legs, [
      { account: pcOf(BUYER), dr: DEBT }, { account: 'admin_clearing', cr: RET }, { account: pcOf(K1), cr: POOL - SVC },
      { account: 'earnings:ava_courier_service_fee', cr: SVC }, { account: 'earnings:ava_logistics_fee', cr: SHARE },
    ]);
    settlementLedger.buildEntry({ idempotencyKey: 'x', kind: 'k', legs: p.legs }); // Σdr == Σcr
    // Ko'p LEG: oldingi kuryerlar (pool 48 000, keep 30 000) — AVA 18 000 + R qoplagan.
    const multi = C.planBuyerDebtPayment({ ...base, keep: 30000, owedToCollector: 30000, avaCovered: 18000 + RET, serviceFee: 0 });
    assert.deepStrictEqual([multi.avaCovered, multi.collectorNet, multi.legs.length], [18000 + RET, 30000, 4]);
    const code = (patch) => { try { C.planBuyerDebtPayment({ ...base, ...patch }); return null; } catch (e) { return e.code; } };
    assert.strictEqual(code({ amount: DEBT + 1 }), 'debt_total_mismatch');
    assert.strictEqual(code({ platformShare: SHARE + 1 }), 'cash_split_mismatch');
    assert.strictEqual(code({ avaCovered: RET + 1 }), 'debt_ava_cover_mismatch');
    assert.strictEqual(code({ owedToCollector: POOL - 1 }), 'debt_collector_mismatch');
    assert.strictEqual(code({ keep: POOL + 1 }), 'debt_collector_mismatch');
    assert.strictEqual(code({ serviceFee: POOL + 1 }), 'cash_service_fee_invalid');
    assert.strictEqual(code({ amount: 1.5 }), 'debt_amounts_invalid');
    assert.strictEqual(code({ returnFee: 0, amount: FEE }), 'debt_amounts_invalid');
    assert.strictEqual(code({ collectorAccount: null }), 'debt_accounts_invalid');
    // Chegara: xizmat haqi = butun keep → yig'uvchiga 0 (hisob shart emas), Σ saqlanadi.
    const all = C.planBuyerDebtPayment({ ...base, serviceFee: POOL, collectorAccount: null });
    assert.deepStrictEqual([all.collectorNet, all.legs.reduce((s, l) => s + (l.cr || 0), 0)], [0, DEBT]);
  });

  // ── Naqd rad qarzi ──
  await check('naqd qarz: hamyon 0 va amount−1 → insufficient_balance {amount, balance}, hech narsa yozilmaydi; amount → to\'landi (komponentlar, returnDebt null, buyerDebt paid, audit, xabarlar), naqd qayta ochiladi', async () => {
    const id = await cashDebtOrder();
    assert.strictEqual(await DW.buyerHasOpenDebt(db, BUYER), true, 'oldin — qarz to\'sadi');
    const j0 = await journalSize();
    const clearing0 = await bal('admin_clearing');
    let e = await expectErr(pay(id), 'failed-precondition', 'insufficient_balance');
    assert.deepStrictEqual([e.details.amount, e.details.balance], [DEBT, 0]);
    await topup(BUYER, DEBT - 1);
    e = await expectErr(pay(id), 'failed-precondition', 'insufficient_balance');
    assert.deepStrictEqual([e.details.amount, e.details.balance], [DEBT, DEBT - 1]);
    assert.strictEqual(await journalSize(), j0 + 1, 'faqat to\'ldirish yozuvi');
    assert.strictEqual((await orderOf(id)).returnDebt.status, 'open');
    await topup(BUYER, 1);
    const clearing1 = await bal('admin_clearing');
    assert.strictEqual(clearing1, clearing0 + DEBT, 'test to\'ldirishi admin_clearing dan');
    const k0 = await bal(pcOf(K1));
    const r = await pay(id);
    assert.deepStrictEqual([r.ok, r.paid, r.idempotent, r.kind, r.amount, r.entryId], [true, true, false, 'cash_refusal', DEBT, W.buyerDebtPayKey(id)]);
    assert.strictEqual(await bal(pcOf(BUYER)), 0);
    assert.strictEqual(await bonusOf(BUYER), 0);
    assert.strictEqual(await bal('admin_clearing'), clearing1 - RET, 'AVA qoplamasi (qaytish) qaytdi');
    assert.strictEqual(await bal(pcOf(K1)) - k0, POOL - SVC, 'yig\'uvchi: keep − xizmat haqi');
    assert.strictEqual(await bal('earnings:ava_courier_service_fee'), SVC);
    assert.strictEqual(await bal('earnings:ava_logistics_fee'), SHARE);
    const jr = (await journal(W.buyerDebtPayKey(id))).data();
    assert.deepStrictEqual([jr.kind, jr.amount, jr.legs.length, jr.postedRole], ['wholesale_buyer_debt_payment', DEBT, 5, 'client']);
    const o = await orderOf(id);
    assert.strictEqual(o.returnDebt, null);
    assert.ok(o.returnDebtSettledAt);
    assert.deepStrictEqual([o.returnDebtPaid.status, o.returnDebtPaid.kind, o.returnDebtPaid.amount, o.returnDebtPaid.paidEntryId, o.returnDebtPaid.paidBy],
      ['paid', 'cash_refusal', DEBT, W.buyerDebtPayKey(id), 'buyer']);
    assert.deepStrictEqual(o.returnDebtPaid.components, { avaCovered: RET, collectorNet: POOL - SVC, serviceFee: SVC, platformShare: SHARE });
    const h = (await db.collection('wholesale_orders').doc(id).collection('history').doc(String(o.historySeq)).get()).data();
    assert.deepStrictEqual([h.event, h.actor, h.meta.amount], ['buyer_debt_paid', 'buyer', DEBT]);
    const s = await shipOf(SHIP);
    assert.deepStrictEqual([s.deliveryPayment.buyerDebt.status, s.deliveryPayment.buyerDebt.paidEntryId], ['paid', W.buyerDebtPayKey(id)]);
    assert.strictEqual(s.paymentStatus, 'settled', 'jo\'natma holati o\'zgarmadi');
    const audit = (await db.collection('logistics_audit').doc(`cash_buyer_debt_paid_${SHIP}`).get()).data();
    assert.deepStrictEqual([audit.amount, audit.avaCovered, audit.collectorNet, audit.serviceFee, audit.platformShare, audit.feeBps],
      [DEBT, RET, POOL - SVC, SVC, SHARE, FEE_BPS]);
    assert.deepStrictEqual(await walletLedger(BUYER, 'wholesale_debt_payment'), [-DEBT]);
    assert.deepStrictEqual(await walletLedger(K1, 'logistics_cash_debt_payout'), [POOL - SVC]);
    const nb = (await db.collection('admin_news').doc(`wholesale_${id}_ws_debt_paid_buyer_${BUYER}`).get()).data();
    assert.ok(nb && nb.title === 'Qarz tölandi' && nb.body.includes(String(DEBT)), JSON.stringify(nb));
    const na = (await db.collection('admin_news').doc(`wholesale_${id}_ws_debt_paid_admin_${ADMIN}`).get()).data();
    assert.ok(na && na.title.startsWith('Оптовый рынок') && na.body.includes(id), JSON.stringify(na));
    assert.strictEqual(await DW.buyerHasOpenDebt(db, BUYER), false, 'demand kvota tekshiruvi endi to\'smaydi');
    // Takror bosish — o'sha natija, pul yo'q, xabar takrorlanmaydi.
    const again = await pay(id);
    assert.deepStrictEqual([again.ok, again.paid, again.idempotent, again.amount], [true, true, true, DEBT]);
    assert.strictEqual(await bal(pcOf(BUYER)), 0);
    await assertLedgerSound();
  });

  await check('naqd qarz: parallel 3 bosish → BITTA to\'lov (boshqalari idempotent), pul bir marta', async () => {
    const id = await cashDebtOrder();
    await topup(BUYER, DEBT * 2);
    const outs = await Promise.all([pay(id), pay(id), pay(id)]);
    assert.ok(outs.every((x) => x.ok && x.paid), JSON.stringify(outs));
    assert.strictEqual(outs.filter((x) => !x.idempotent).length, 1, JSON.stringify(outs));
    assert.strictEqual(await bal(pcOf(BUYER)), DEBT, 'faqat bir marta yechildi');
    assert.strictEqual(await bal('earnings:ava_logistics_fee'), SHARE);
    assert.deepStrictEqual(await walletLedger(BUYER, 'wholesale_debt_payment'), [-DEBT]);
    const news = await db.collection('admin_news').where('dataType', '==', 'ws_debt_paid_buyer').get();
    assert.strictEqual(news.size, 1);
    await assertLedgerSound();
  });

  await check('naqd qarz: relay_cash C tugamagan (qaytish jo\'natmasi yo\'q) → debt_not_ready, pul YO\'Q', async () => {
    await seed({ sellerWallet: AVA, buyerWallet: DEBT });
    const r = await place();
    await linkAndOpenCash(r.orderId);
    await refuseCashUnpaid(r.orderId);
    const j0 = await journalSize();
    await expectErr(pay(r.orderId), 'failed-precondition', 'debt_not_ready');
    assert.strictEqual(await journalSize(), j0);
    assert.strictEqual(await bal(pcOf(BUYER)), DEBT);
    assert.strictEqual((await orderOf(r.orderId)).returnDebt.status, 'open');
  });

  await check('naqd qarz: muhrlangan summa buzilgan (avaCovered +1 / platformShare +1) → anomaliya, pul YO\'Q', async () => {
    const id = await cashDebtOrder();
    await topup(BUYER, DEBT);
    const j0 = await journalSize();
    await db.collection('shipments').doc(SHIP).update({ 'deliveryPayment.buyerDebt.avaCovered': RET + 1 });
    await expectErr(pay(id), 'failed-precondition', 'debt_ava_cover_mismatch');
    await db.collection('shipments').doc(SHIP).update({ 'deliveryPayment.buyerDebt.avaCovered': RET });
    await db.collection('shipments').doc(SHIP).collection('private').doc('internal').update({ platformShare: SHARE + 1 });
    await expectErr(pay(id), 'failed-precondition', 'cash_split_mismatch');
    await db.collection('shipments').doc(SHIP).update({ 'deliveryPayment.buyerDebt.amount': DEBT + 1 });
    await expectErr(pay(id), 'failed-precondition', 'debt_components_mismatch');
    assert.strictEqual(await journalSize(), j0, 'ledger yozuvi yo\'q');
    assert.strictEqual(await bal(pcOf(BUYER)), DEBT);
    assert.strictEqual((await orderOf(id)).returnDebt.status, 'open');
    await assertLedgerSound();
  });

  await check('ruxsat: sotuvchi / boshqa telefon → not_order_party; kirmagan → unauthenticated; noto\'g\'ri id; qarz yo\'q → debt_not_open', async () => {
    const id = await cashDebtOrder();
    await topup(BUYER, DEBT);
    await expectErr(pay(id, SELLER), 'permission-denied', 'not_order_party');
    await expectErr(pay(id, K1), 'permission-denied', 'not_order_party');
    await expectErr(quiet(() => api.payBuyerDebt({ orderId: id }, {})), 'unauthenticated', 'auth_required');
    await expectErr(pay('bad/id'), 'invalid-argument', 'order_required');
    await expectErr(pay('nope'), 'not-found', 'order_not_found');
    assert.strictEqual(await bal(pcOf(BUYER)), DEBT);
    // Qarzsiz buyurtma (naqd rad, xaridor TO'LADI tipidagi) — to'lanadigan narsa yo'q.
    await db.collection('wholesale_orders').doc('noDebt').set({ buyerId: BUYER, buyerWalletUid: BUYER, status: 'returning' });
    await expectErr(pay('noDebt'), 'failed-precondition', 'debt_not_open');
    // Kuryer qarzi (payer courier) — xaridor to'lamaydi.
    await db.collection('wholesale_orders').doc('courierDebt').set({ buyerId: BUYER, buyerWalletUid: BUYER, status: 'refused', returnDebt: { payer: 'courier', amount: 5 } });
    await expectErr(pay('courierDebt'), 'failed-precondition', 'debt_not_open');
    assert.ok(typeof exported.payWholesaleBuyerDebt === 'function', 'callable eksport qilingan');
  });

  // ── Hamyon radi qarzi (mavjud fundReturn yo'li) ──
  const WG = 140000;
  const WFEE = 60000;
  const walletQuote = () => ({
    buyerId: BUYER, sellerId: SELLER, productId: 'rice', productTitle: 'Гуруч', packId: 'p1', packLabel: '1 кг',
    qty: 10, unitPrice: 14000, goodsTotal: WG, deliveryFee: WFEE, total: WG + WFEE, currency: 'UZS',
    delivery: { tariffVersion: 3, zone: 'ZONE_4', actualWeightG: 10000, chargeableWeightG: 10000, dims: null, priceSnapshot: { customerPrice: WFEE } },
    avaFeeBps: 250, feeVersion: 3, avaFee: 3500, sellerPayout: 136500,
    origin: { regionId: 'xorazm' }, destination: { regionId: 'toshkent_shahri', addressText: 'Chilonzor' },
    paymentMethod: 'wallet', createdAt: clock, expiresAt: new Date(clock.getTime() + 15 * 60 * 1000), used: false,
  });
  async function walletDebtOrder() {
    await seed({ buyerWallet: WG + WFEE, quote: walletQuote() });
    const r = await place();
    const id = r.orderId;
    await db.collection('shipments').doc(SHIP).set({
      orderId: `lo_${id}`, ownerId: SELLER, recipientId: BUYER, source: 'wholesale', wholesaleOrderId: id,
      trackingNumber: 'AVA-26-1115-000009', status: 'awaiting_payment', paymentStatus: 'pending',
      priceSnapshot: { customerPrice: WFEE, tariffVersion: 3, declaredValue: WG }, legIds: ['leg0'], legCount: 1, createdAt: clock, updatedAt: clock,
    });
    await db.collection('shipments').doc(SHIP).collection('private').doc('internal').set({
      platformShare: 12000, providerPool: 48000, legPayouts: [{ index: 0, kind: 'direct', amount: 48000 }], tariffVersion: 3,
    });
    const ref = db.collection('wholesale_orders').doc(id);
    const before = await orderOf(id);
    await ref.update({ shipment: { shipmentId: SHIP, orderId: `lo_${id}`, trackingNumber: 'AVA-26-1115-000009', createdAt: clock }, historySeq: before.historySeq + 1 });
    await chain(id, before);
    await db.collection('shipments').doc(SHIP).update({
      status: 'in_transit', legAssignments: { leg0: K1 }, currentLegId: 'leg0', currentCustodian: { kind: 'provider', id: K1, since: clock },
    });
    await db.collection('demands').doc('leg0').set({ module: 'logistics', status: 'in_progress', assignment: { providerId: K1 }, attributes: { shipmentId: SHIP } });
    await db.collection('demand_matches').doc(`leg0_${K1}`).set({ status: 'in_progress', providerId: K1, contactUnlocked: { recipientPhone: BUYER } });
    await patchAndChain(id, {
      status: 'refused', refundStatus: 'pending', refusedAt: clock, statusUpdatedAt: clock, returnStatus: 'pending_shipment',
      refusal: { by: K1, via: 'courier', reason: '', reasonCode: 'customer_absent', at: clock, shipmentId: SHIP, legId: 'leg0', confirmedBy: 'buyer', confirmedById: BUYER },
    });
    // Qaytish narxi F = G + 1 → G ushlanadi, 1 so'm xaridor qarzi.
    await db.collection('shipments').doc('R1').set({
      orderId: 'lo_ret', ownerId: SELLER, recipientId: SELLER, source: 'wholesale_return', wholesaleOrderId: id, wholesaleReturn: true,
      status: 'awaiting_payment', paymentStatus: 'pending', priceSnapshot: { customerPrice: WG + 1, tariffVersion: 4 }, legIds: ['rleg0'], legCount: 1,
      createdAt: clock, updatedAt: clock,
    });
    await patchAndChain(id, {
      returnShipment: { shipmentId: 'R1', orderId: 'lo_ret', legId: 'rleg0', trackingNumber: 'AVA-R2', fee: WG + 1, tariffVersion: 4, courierId: K1, createdAt: clock },
      returnStatus: 'awaiting_payment',
    });
    const o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.returnDebt.payer, o.returnDebt.amount, o.returnDebt.kind || null, o.returnPayment.held], ['refused', 'buyer', 1, null, WG]);
    assert.strictEqual(await bal(pcOf(BUYER)), 0);
    return id;
  }

  await check('hamyon radi qarzi (kind yo\'q): 0 → insufficient {1, 0}; +1 → mavjud fundReturn darhol (rest ushlanma + FUND), returning, returnDebt null; takror — idempotent', async () => {
    const id = await walletDebtOrder();
    const e = await expectErr(pay(id), 'failed-precondition', 'insufficient_balance');
    assert.deepStrictEqual([e.details.amount, e.details.balance], [1, 0]);
    assert.strictEqual((await orderOf(id)).returnDebt.amount, 1);
    await topup(BUYER, 1);
    const r = await pay(id);
    assert.deepStrictEqual([r.ok, r.paid, r.idempotent, r.kind, r.amount, r.entryId], [true, true, false, 'return_fee', 1, `bonus:${W.returnHoldRestKey(id)}`]);
    const o = await orderOf(id);
    assert.deepStrictEqual([o.status, o.returnDebt, o.returnPayment.status, o.walletRefusal.returnFeeOutstanding], ['returning', null, 'funded', 0]);
    assert.ok(o.returnDebtSettledAt);
    assert.strictEqual(await bal(pcOf(BUYER)), 0);
    assert.strictEqual(await bal(W.shipmentEscrowAccount('R1')), WG + 1, 'kreditor — qaytish jo\'natmasi eskrousi');
    assert.deepStrictEqual((await journal(`bonus:${W.returnHoldRestKey(id)}`)).data().legs,
      [{ account: pcOf(BUYER), dr: 1 }, { account: W.returnEscrowAccount(id), cr: 1 }]);
    assert.ok((await db.collection('admin_news').doc(`wholesale_${id}_ws_debt_paid_buyer_${BUYER}`).get()).exists);
    const again = await pay(id);
    assert.deepStrictEqual([again.ok, again.idempotent], [true, true]);
    assert.strictEqual(await DW.buyerHasOpenDebt(db, BUYER), false);
    await assertLedgerSound();
  });

  await check('hamyon radi qarzi: parallel 2 bosish → bitta ushlanma, bitta FUND', async () => {
    const id = await walletDebtOrder();
    await topup(BUYER, 5);
    // Emulator/Firestore tranzaksiya to'qnashuvi: yutqazgan bosish ok (idempotent) YOKI aborted/debt_changed (qayta bosadi).
    const outs = await Promise.all([pay(id), pay(id)].map((p) => p.catch((e) => ({ err: `${e.code}/${(e.details || {}).reason}` }))));
    assert.ok(outs.some((x) => x.ok && x.paid), JSON.stringify(outs));
    assert.ok(outs.every((x) => (x.ok && x.paid) || x.err === 'aborted/debt_changed'), JSON.stringify(outs));
    const retry = await pay(id);
    assert.deepStrictEqual([retry.ok, retry.idempotent], [true, true]);
    assert.strictEqual(await bal(pcOf(BUYER)), 4, 'faqat 1 so\'m yechildi');
    assert.strictEqual(await bal(W.shipmentEscrowAccount('R1')), WG + 1);
    assert.strictEqual((await orderOf(id)).status, 'returning');
    await assertLedgerSound();
  });

  const passed = results.filter((x) => x.pass).length;
  console.log(`\n${passed}/${results.length} wholesale debt pay CF checks passed.`);
  process.exit(passed === results.length ? 0 : 1);
})();
