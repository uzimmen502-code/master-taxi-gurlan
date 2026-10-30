/**
 * Ulgurji buyurtma zanjiri, 2-bosqich — default codebase, HAQIQIY ledger bilan
 * (Firestore Emulator, Admin SDK):
 *
 *   firebase emulators:exec --only firestore --project demo-wholesale-orders \
 *     "node functions/test/wholesale_orders.test.js"
 *
 * Qulflanadi:
 *   - placeWholesaleOrder: bitta tranzaksiyada kvota used + qoldiq −N (+history) +
 *     HOLD (Dr passenger_credit / Cr escrow:wholesale:{id}) + bonusBalance ko'zgusi +
 *     buyurtma + history + idempotentlik; yetmasa — HECH NARSA yozilmaydi
 *   - takror / parallel chaqiruv — bitta buyurtma, bitta yechim
 *   - eskirgan / ishlatilgan / begona / buzilgan kvota, qoldiq kamaygan, kill switch
 *   - REFUND (trigger): pul + qoldiq BIR MARTA (takror va parallel chaqiruvda ham)
 *   - reconcile: 10 daqiqadan eski `pending` qaytariladi, yangisi kutadi
 *   - Σdr == Σcr, aktiv == passiv, passenger_credit == bonusBalance
 *   - 3-bosqich: SHIP_FUND (escrow:wholesale → escrow:{shipment}, placed → in_delivery) →
 *     custody delivery → relay RELEASE + tovar RELEASE (sotuvchi + AVA ulushi), eskroular 0;
 *     takror/parallel hodisa — bir marta; narx mos emas — anomaliya; haq o'tgach to'liq qaytarish
 *     yo'q; reconcile; sotuvchi relay FUND qila olmaydi; relay REFUND → escrow:wholesale
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-wholesale-orders';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const settlementLedger = require('../settlement_ledger');
const W = require('../wholesale_orders');
// Paritet: holatlar jadvalining yagona manbasi (demand codebase).
const WO = require('../../functions_demand/core/wholesale_orders');

const BUYER = '998901110001';
const BUYER9 = '902220002'; // eski 9 xonali `users` hujjati
const SELLER = '998901234567';
const OTHER = '998907770007';
const T0 = new Date('2026-10-31T12:00:00Z');
let clock = T0;
const digits = (v) => String(v || '').replace(/\D/g, '');
const api = W.attachWholesaleOrders({}, {
  functions, db, admin,
  callerPhone: (ctx) => digits(ctx.auth.token.phone_number),
  canonicalUid: (v) => { const d = digits(v); return d.length === 9 ? `998${d}` : d; },
  settlementLedger,
  now: () => clock,
});
const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });
// 3-bosqich: relay eskrou HAQIQIY modul bilan (custody triggeri tovar pulini chaqiradi).
const relay = require('../relay_escrow');
const relayApi = relay.attachRelayEscrow({}, {
  functions, db, admin,
  callerPhone: (c) => digits(c.auth.token.phone_number),
  canonicalUid: (v) => { const d = digits(v); return d.length === 9 ? `998${d}` : d; },
  settlementLedger,
  notifyUserInApp: async () => {},
  requireCallerRoles: async () => { throw new Error('not used'); },
  now: () => clock,
  wholesaleOrders: api,
});
const K1 = '998902220002';

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
const quoteOf = async (id) => (await db.collection('wholesale_quotes').doc(id).get()).data();
const count = async (col) => (await db.collection(col).get()).size;
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
  idempotencyKey: `topupW:${uid}:${topupSeq += 1}`, kind: 'test_topup',
  legs: [{ account: 'admin_clearing', dr: amount }, { account: pcOf(uid), cr: amount }],
});

/** Demand `quoteWholesaleOrder` yozadigan shakl (10 × 14 000 + 60 000 yetkazish). */
function quoteDoc(extra = {}) {
  return {
    buyerId: BUYER, sellerId: SELLER, productId: 'rice', productTitle: 'Гуруч', packId: 'p1', packLabel: '1 кг',
    qty: 10, unitPrice: 14000, goodsTotal: 140000, deliveryFee: 60000, total: 200000, currency: 'UZS',
    delivery: { tariffVersion: 3, zone: 'ZONE_4', actualWeightG: 10000, chargeableWeightG: 10000, dims: null, priceSnapshot: { customerPrice: 60000 } },
    avaFeeBps: 250, feeVersion: 3, avaFee: 3500, sellerPayout: 136500,
    origin: { regionId: 'xorazm' }, destination: { regionId: 'toshkent_shahri', addressText: 'Chilonzor' },
    createdAt: clock, expiresAt: new Date(clock.getTime() + 15 * 60 * 1000), used: false,
    ...extra,
  };
}

async function seed({ wallet = 300000, stock = 100, buyerDocId = BUYER } = {}) {
  clock = T0;
  await resetAll();
  await db.collection('module_config').doc('wholesale_orders_all').set({ enabled: true, stage: 'internal', testerIds: [BUYER] });
  await db.collection('users').doc(buyerDocId).set({ bonusBalance: 0 });
  await db.collection('users').doc(SELLER).set({ bonusBalance: 0 });
  await db.collection('users').doc(OTHER).set({ bonusBalance: 0 });
  await db.collection('wholesale_products').doc('rice').set({ sellerId: SELLER, status: 'active', market: 'wholesale' });
  await db.collection('wholesale_stock').doc('rice').set({ productId: 'rice', sellerId: SELLER, packs: { p1: stock, p2: 7 }, version: 1 });
  await db.collection('wholesale_quotes').doc('q1').set(quoteDoc());
  if (wallet > 0) await topup(buyerDocId, wallet);
}
const place = (extra = {}, who = BUYER) => api.place({ quoteId: 'q1', clientRequestId: 'req-00000001', ...extra }, ctx(who));

/** Demand `cancelWholesaleOrder` (xaridor) yozadigan holat — sotuvchi aralashmaydi. */
async function demandFlip(orderId, to) {
  const ref = db.collection('wholesale_orders').doc(orderId);
  await ref.update({ status: to, refundStatus: 'pending', statusUpdatedAt: clock, updatedAt: clock, historySeq: 2 });
  await ref.collection('history').doc('2').set({ seq: 2, from: 'placed', to, actor: 'buyer', at: clock });
  const after = (await ref.get()).data();
  return after;
}

(async () => {
  await check('paritet: holat nomlari demand jadvali bilan bir xil; eskrou hisob turi', async () => {
    assert.strictEqual(W.STATUS.PLACED, WO.STATUS.PLACED);
    assert.strictEqual(W.STATUS.REJECTED, undefined, "rejected holati yo'q (sotuvchi aralashmaydi)");
    assert.strictEqual(WO.STATUS.REJECTED, undefined);
    assert.strictEqual(W.STATUS.CANCELLED, WO.STATUS.CANCELLED);
    assert.deepStrictEqual([...W.REFUND_STATUSES], [...WO.REFUND_STATUSES]);
    assert.deepStrictEqual({ ...W.REFUND_STATUS }, { ...WO.REFUND_STATUS });
    assert.strictEqual(settlementLedger.accountTypeOf(W.escrowAccount('x')), 'liability');
  });

  await check('quoteAmountsOk: izchil — ha; total/goods/ulush buzilgan — yo\'q', async () => {
    assert.strictEqual(W.quoteAmountsOk(quoteDoc()), true);
    assert.strictEqual(W.quoteAmountsOk(quoteDoc({ total: 199999 })), false);
    assert.strictEqual(W.quoteAmountsOk(quoteDoc({ goodsTotal: 140001, total: 200001 })), false);
    assert.strictEqual(W.quoteAmountsOk(quoteDoc({ avaFee: 3501 })), false);
    assert.strictEqual(W.quoteAmountsOk(quoteDoc({ deliveryFee: 60000.5, total: 200000.5 })), false);
    assert.strictEqual(W.quoteAmountsOk(quoteDoc({ deliveryFee: 0, total: 140000 })), true, 'yetkazish 0 — chegara');
  });

  let orderId;
  await check('place: HOLD + ko\'zgu + qoldiq −10 + kvota used + buyurtma/history/idempotentlik', async () => {
    await seed();
    const r = await place();
    assert.strictEqual(r.ok, true);
    assert.strictEqual(r.idempotent, false);
    assert.strictEqual(r.total, 200000);
    orderId = r.orderId;
    assert.strictEqual(await bal(pcOf(BUYER)), 100000);
    assert.strictEqual(await bal(W.escrowAccount(orderId)), 200000);
    assert.strictEqual(await bonusOf(BUYER), 100000);
    const j = (await db.collection(settlementLedger.COL_JOURNAL).doc(`bonus:${W.holdKey(orderId)}`).get()).data();
    assert.strictEqual(j.kind, 'wholesale_hold');
    assert.strictEqual(j.amount, 200000);
    assert.deepStrictEqual(j.legs, [{ account: pcOf(BUYER), dr: 200000 }, { account: W.escrowAccount(orderId), cr: 200000 }]);
    const wl = (await db.collection('users').doc(BUYER).collection('wallet_ledger').where('type', '==', 'wholesale_hold').get()).docs.map((d) => d.data());
    assert.strictEqual(wl.length, 1);
    assert.strictEqual(wl[0].amount, -200000);
    assert.strictEqual(wl[0].refId, orderId);
    const s = await stockOf();
    assert.deepStrictEqual(s.packs, { p1: 90, p2: 7 });
    assert.strictEqual(s.version, 2);
    const sh = (await db.collection('wholesale_stock').doc('rice').collection('history').doc('v2').get()).data();
    assert.strictEqual(sh.kind, 'order_hold');
    assert.strictEqual(sh.orderId, orderId);
    assert.deepStrictEqual([sh.from.p1, sh.to.p1, sh.qty], [100, 90, 10]);
    const q = await quoteOf('q1');
    assert.strictEqual(q.used, true);
    assert.strictEqual(q.orderId, orderId);
    const o = await orderOf(orderId);
    assert.strictEqual(o.status, 'placed');
    assert.strictEqual(o.buyerId, BUYER);
    assert.strictEqual(o.buyerWalletUid, BUYER);
    assert.strictEqual(o.sellerId, SELLER);
    assert.deepStrictEqual([o.qty, o.unitPrice, o.goodsTotal, o.deliveryFee, o.total], [10, 14000, 140000, 60000, 200000]);
    assert.strictEqual(o.total, o.goodsTotal + o.deliveryFee);
    assert.strictEqual(o.payment.status, 'held');
    assert.strictEqual(o.payment.amount, 200000);
    assert.strictEqual(o.payment.escrowAccount, W.escrowAccount(orderId));
    assert.deepStrictEqual(o.stock, { packId: 'p1', qty: 10, decremented: true, restored: false });
    assert.strictEqual(o.shipment, null);
    assert.strictEqual(o.refundStatus, null);
    assert.strictEqual(o.historySeq, 1);
    assert.strictEqual(o.delivery.tariffVersion, 3);
    assert.ok(!('avaFee' in o) && !('sellerPayout' in o), 'ichki qatlam buyurtma hujjatida emas');
    const st = (await db.collection('wholesale_orders').doc(orderId).collection('private').doc('settlement').get()).data();
    assert.deepStrictEqual([st.avaFeeBps, st.feeVersion, st.avaFee, st.sellerPayout], [250, 3, 3500, 136500]);
    const h = (await db.collection('wholesale_orders').doc(orderId).collection('history').doc('1').get()).data();
    assert.deepStrictEqual([h.seq, h.from, h.to, h.actor], [1, null, 'placed', 'buyer']);
    const idem = (await db.collection('wallet_idempotency').doc(`wholesale_place_${BUYER}_req-00000001`).get()).data();
    assert.strictEqual(idem.orderId, orderId);
    await assertLedgerSound();
  });

  await check('idempotent: takror chaqiruv — o\'sha buyurtma, ikkinchi yechim yo\'q', async () => {
    const r = await place();
    assert.strictEqual(r.idempotent, true);
    assert.strictEqual(r.orderId, orderId);
    assert.strictEqual(await count('wholesale_orders'), 1);
    assert.strictEqual(await bal(pcOf(BUYER)), 100000);
    assert.strictEqual((await stockOf()).packs.p1, 90);
    await expectErr(place({ quoteId: 'qOther' }), 'failed-precondition', 'idempotency_key_reused');
  });

  await check('ishlatilgan kvota (yangi clientRequestId) — quote_used, pul yechilmaydi', async () => {
    await expectErr(place({ clientRequestId: 'req-00000002' }), 'failed-precondition', 'quote_used');
    assert.strictEqual(await bal(pcOf(BUYER)), 100000);
    assert.strictEqual(await count('wholesale_orders'), 1);
  });

  await check('parallel: bir xil clientRequestId ×3 — bitta buyurtma, bitta yechim', async () => {
    await seed();
    const rs = await Promise.allSettled([place(), place(), place()]);
    const okIds = rs.filter((x) => x.status === 'fulfilled').map((x) => x.value.orderId);
    assert.ok(okIds.length >= 1, JSON.stringify(rs.map((x) => x.reason && x.reason.message)));
    assert.strictEqual(new Set(okIds).size, 1);
    assert.strictEqual(await count('wholesale_orders'), 1);
    assert.strictEqual(await bal(pcOf(BUYER)), 100000);
    assert.strictEqual((await stockOf()).packs.p1, 90);
    await assertLedgerSound();
  });

  await check('parallel: bitta kvota, turli clientRequestId — faqat bittasi o\'tadi', async () => {
    await seed();
    const rs = await Promise.allSettled([
      place({ clientRequestId: 'req-A0000001' }), place({ clientRequestId: 'req-B0000002' }),
    ]);
    const okN = rs.filter((x) => x.status === 'fulfilled').length;
    assert.strictEqual(okN, 1, JSON.stringify(rs.map((x) => x.reason && x.reason.details)));
    assert.strictEqual(await count('wholesale_orders'), 1);
    assert.strictEqual(await bal(pcOf(BUYER)), 100000);
    await assertLedgerSound();
  });

  await check('hamyon yetmaydi — insufficient_balance, HECH NARSA yozilmaydi', async () => {
    await seed({ wallet: 199999 });
    const e = await expectErr(place(), 'failed-precondition', 'insufficient_balance');
    assert.deepStrictEqual([e.details.required, e.details.balance], [200000, 199999]);
    assert.strictEqual(await count('wholesale_orders'), 0);
    assert.strictEqual(await count('wallet_idempotency'), 0);
    assert.strictEqual((await quoteOf('q1')).used, false);
    assert.deepStrictEqual((await stockOf()).packs, { p1: 100, p2: 7 });
    assert.strictEqual((await stockOf()).version, 1);
    assert.strictEqual(await bal(pcOf(BUYER)), 199999);
    assert.strictEqual(await bonusOf(BUYER), 199999);
    await assertLedgerSound();
  });

  await check('chegara: hamyon aynan total — o\'tadi, hamyon 0', async () => {
    await seed({ wallet: 200000 });
    await place();
    assert.strictEqual(await bal(pcOf(BUYER)), 0);
    await assertLedgerSound();
  });

  await check('kvota eskirgan (15 daq) — quote_expired; muddat oxiridan 1 ms oldin o\'tadi', async () => {
    await seed();
    clock = new Date(T0.getTime() + 15 * 60 * 1000);
    await expectErr(place(), 'failed-precondition', 'quote_expired');
    clock = new Date(T0.getTime() + 15 * 60 * 1000 - 1);
    const r = await place();
    assert.ok(r.orderId);
  });

  await check('kvotadan keyin qoldiq kamaygan — insufficient_stock; qadoq qoldig\'i yo\'q — stock_unknown', async () => {
    await seed({ stock: 9 });
    const e = await expectErr(place(), 'failed-precondition', 'insufficient_stock');
    assert.strictEqual(e.details.available, 9);
    await db.collection('wholesale_stock').doc('rice').set({ packs: { p2: 7 }, version: 2 });
    await expectErr(place(), 'failed-precondition', 'stock_unknown');
    assert.strictEqual(await bal(pcOf(BUYER)), 300000);
    // chegara: qoldiq aynan 10 — o'tadi, 0 qoladi
    await db.collection('wholesale_stock').doc('rice').set({ packs: { p1: 10 }, version: 3 });
    await place();
    assert.strictEqual((await stockOf()).packs.p1, 0);
  });

  await check('begona chaqiruvchi — quote_not_yours; kirmagan — unauthenticated; noto\'g\'ri kirish', async () => {
    await seed();
    await topup(OTHER, 500000);
    await expectErr(place({}, OTHER), 'permission-denied', 'quote_not_yours');
    await expectErr(api.place({ quoteId: 'q1', clientRequestId: 'req-00000001' }, {}), 'unauthenticated');
    await expectErr(place({ clientRequestId: 'short' }), 'invalid-argument', 'client_request_id_invalid');
    await expectErr(place({ quoteId: '' }), 'invalid-argument', 'quote_required');
    await expectErr(place({ quoteId: 'nope' }), 'not-found', 'quote_not_found');
    assert.strictEqual(await bal(pcOf(OTHER)), 500000);
    assert.strictEqual(await count('wholesale_orders'), 0);
  });

  await check('kill switch / mahsulot yopilgan / buzilgan kvota — rad', async () => {
    await seed();
    await db.collection('module_config').doc('wholesale_orders_all').set({ enabled: false });
    await expectErr(place(), 'unavailable', 'module_disabled');
    await db.collection('module_config').doc('wholesale_orders_all').set({ enabled: true });
    await db.collection('wholesale_products').doc('rice').update({ status: 'inactive' });
    await expectErr(place(), 'failed-precondition', 'product_unavailable');
    await db.collection('wholesale_products').doc('rice').update({ status: 'active' });
    await db.collection('wholesale_quotes').doc('q1').update({ total: 1 });
    await expectErr(place(), 'failed-precondition', 'quote_invalid');
    assert.strictEqual(await bal(pcOf(BUYER)), 300000);
    assert.strictEqual(await count('wholesale_orders'), 0);
  });

  await check('eski 9 xonali users hujjati — hamyon o\'sha hujjatda', async () => {
    await seed({ buyerDocId: BUYER9 });
    await db.collection('wholesale_quotes').doc('q1').update({ buyerId: `998${BUYER9}` });
    const r = await place({}, `998${BUYER9}`);
    const o = await orderOf(r.orderId);
    assert.strictEqual(o.buyerWalletUid, BUYER9);
    assert.strictEqual(await bal(pcOf(BUYER9)), 100000);
    assert.strictEqual(await bonusOf(BUYER9), 100000);
    await assertLedgerSound();
  });

  // ── QAYTARISH ─────────────────────────────────────────────────────
  await check('trigger: cancelled → to\'liq qaytarish + qoldiq +10; takror trigger — BIR MARTA', async () => {
    await seed();
    const { orderId: id } = await place();
    const after = await demandFlip(id, 'cancelled');
    const r1 = await api.onStatusChange({ status: 'placed' }, after, id);
    assert.strictEqual(r1.refunded, 200000);
    assert.strictEqual(r1.stockRestored, true);
    // takror hodisa (Functions at-least-once) va eski snapshot bilan
    const r2 = await api.onStatusChange({ status: 'placed' }, after, id);
    assert.strictEqual(r2.skipped, 'already_refunded');
    const r3 = await api.refundOrder(id);
    assert.strictEqual(r3.skipped, 'already_refunded');
    assert.strictEqual(await bal(pcOf(BUYER)), 300000);
    assert.strictEqual(await bonusOf(BUYER), 300000);
    assert.strictEqual(await bal(W.escrowAccount(id)), 0);
    const s = await stockOf();
    assert.deepStrictEqual(s.packs, { p1: 100, p2: 7 });
    assert.strictEqual(s.version, 3);
    const sh = (await db.collection('wholesale_stock').doc('rice').collection('history').doc('v3').get()).data();
    assert.strictEqual(sh.kind, 'order_refund');
    const o = await orderOf(id);
    assert.strictEqual(o.status, 'cancelled');
    assert.strictEqual(o.refundStatus, 'done');
    assert.strictEqual(o.payment.status, 'refunded');
    assert.strictEqual(o.stock.restored, true);
    assert.strictEqual(o.historySeq, 3);
    const h3 = (await db.collection('wholesale_orders').doc(id).collection('history').doc('3').get()).data();
    assert.strictEqual(h3.event, 'refund_done');
    const j = (await db.collection(settlementLedger.COL_JOURNAL).doc(`bonus:${W.refundKey(id)}`).get()).data();
    assert.deepStrictEqual(j.legs, [{ account: W.escrowAccount(id), dr: 200000 }, { account: pcOf(BUYER), cr: 200000 }]);
    const wl = (await db.collection('users').doc(BUYER).collection('wallet_ledger').where('type', '==', 'wholesale_refund').get()).size;
    assert.strictEqual(wl, 1);
    await assertLedgerSound();
  });

  await check('parallel qaytarish (trigger + reconcile bir vaqtda) — pul va qoldiq BIR MARTA', async () => {
    await seed();
    const { orderId: id } = await place();
    await demandFlip(id, 'cancelled');
    const rs = await Promise.allSettled([api.refundOrder(id), api.refundOrder(id), api.refundOrder(id)]);
    const refunded = rs.filter((x) => x.status === 'fulfilled' && x.value.refunded).length;
    assert.strictEqual(refunded, 1, JSON.stringify(rs));
    assert.strictEqual(await bal(pcOf(BUYER)), 300000);
    assert.strictEqual((await stockOf()).packs.p1, 100);
    await assertLedgerSound();
  });

  await check('trigger: refund kerak bo\'lmagan holatlar (placed, in_delivery, pending yo\'q) — tegmaydi', async () => {
    await seed();
    const { orderId: id } = await place();
    assert.strictEqual((await api.onStatusChange({}, { status: 'in_delivery', refundStatus: null }, id)).skipped, 'no_refund_needed');
    assert.strictEqual((await api.onStatusChange({}, { status: 'cancelled', refundStatus: null }, id)).skipped, 'no_refund_needed');
    // hujjatda pending yo'q — refundOrder ham tegmaydi
    assert.ok(String((await api.refundOrder(id)).skipped).startsWith('state_placed'));
    assert.strictEqual(await bal(pcOf(BUYER)), 100000);
    assert.strictEqual((await stockOf()).packs.p1, 90);
  });

  await check('reconcile: 10 daqiqadan eski pending qaytariladi, yangisi kutadi; takror — hech narsa', async () => {
    await seed({ wallet: 600000 });
    const { orderId: oldId } = await place();
    await db.collection('wholesale_quotes').doc('q2').set(quoteDoc());
    const { orderId: newId } = await place({ quoteId: 'q2', clientRequestId: 'req-00000002' });
    await demandFlip(oldId, 'cancelled'); // T0
    clock = new Date(T0.getTime() + 9 * 60 * 1000);
    await demandFlip(newId, 'cancelled'); // T0+9
    clock = new Date(T0.getTime() + 11 * 60 * 1000);
    const r = await api.reconcile();
    assert.deepStrictEqual([r.checked, r.refunded, r.failed], [1, 1, 0]);
    assert.strictEqual((await orderOf(oldId)).refundStatus, 'done');
    assert.strictEqual((await orderOf(newId)).refundStatus, 'pending');
    clock = new Date(T0.getTime() + 20 * 60 * 1000);
    const r2 = await api.reconcile();
    assert.deepStrictEqual([r2.checked, r2.refunded], [1, 1]);
    const r3 = await api.reconcile();
    assert.strictEqual(r3.checked, 0);
    assert.strictEqual(await bal(pcOf(BUYER)), 600000);
    assert.strictEqual((await stockOf()).packs.p1, 100);
    await assertLedgerSound();
  });

  // ── 3-BOSQICH: SHIP_FUND → (custody delivery) → relay RELEASE + tovar RELEASE ──
  const SHIP = 'S1';
  const shipOf = async (id = SHIP) => (await db.collection('shipments').doc(id).get()).data();
  /** Demand `createShipmentInternal` yozadigan jo'natma (narx — muhr: 60 000, ichki: 12 000 + 48 000). */
  async function seedShipment(orderId, { price = 60000, id = SHIP } = {}) {
    await db.collection('shipments').doc(id).set({
      orderId: `lo_${orderId}`, ownerId: SELLER, recipientId: BUYER, source: 'wholesale', wholesaleOrderId: orderId,
      trackingNumber: 'AVA-26-1031-000001', status: 'awaiting_payment', paymentStatus: 'pending',
      priceSnapshot: { customerPrice: price, tariffVersion: 3, declaredValue: 140000 }, legIds: ['leg0'], legCount: 1,
      createdAt: clock, updatedAt: clock,
    });
    await db.collection('shipments').doc(id).collection('private').doc('internal').set({
      platformShare: 12000, providerPool: 48000, legPayouts: [{ index: 0, kind: 'direct', amount: 48000 }], tariffVersion: 3,
    });
  }
  /** Demand `onWholesaleOrderCreated` bog'lanishi → default onUpdate triggeri. */
  async function link(orderId, id = SHIP) {
    const ref = db.collection('wholesale_orders').doc(orderId);
    const before = (await ref.get()).data();
    await ref.update({ shipment: { shipmentId: id, orderId: `lo_${orderId}`, trackingNumber: 'AVA-26-1031-000001', createdAt: clock }, historySeq: 2 });
    return { before, after: (await ref.get()).data() };
  }
  /** Demand `confirmDelivery` yozadigan holat + custody hodisasi. */
  async function deliver(id = SHIP) {
    await db.collection('shipments').doc(id).update({ status: 'delivered', deliveredAt: clock, updatedAt: clock });
    return {
      shipmentId: id, legId: 'leg0', orderId: `lo_x`, ownerId: SELLER, trackingNumber: 'AVA-26-1031-000001', kind: 'delivery',
      completesLegId: 'leg0', completedLegProviderId: K1, completedLegPayout: 48000, legIndex: 0, legCount: 1, deliversShipment: true,
    };
  }
  const historyOf = async (id) => (await db.collection('wholesale_orders').doc(id).collection('history').get()).docs.map((d) => d.data());

  await check('paritet (3-bosqich): in_delivery/delivered nomlari demand jadvali bilan bir xil; hisob turlari', async () => {
    assert.strictEqual(W.STATUS.IN_DELIVERY, WO.STATUS.IN_DELIVERY);
    assert.strictEqual(W.STATUS.DELIVERED, WO.STATUS.DELIVERED);
    assert.ok(WO.canActorTransition('system', WO.STATUS.PLACED, WO.STATUS.IN_DELIVERY));
    assert.ok(WO.canActorTransition('system', WO.STATUS.IN_DELIVERY, WO.STATUS.DELIVERED));
    assert.ok(!WO.canActorTransition('buyer', WO.STATUS.IN_DELIVERY, WO.STATUS.CANCELLED), 'yetkazish ochilgach xaridor bekor qilmaydi');
    assert.strictEqual(W.shipmentEscrowAccount('S'), relay.escrowAccount('S'), 'relay eskrou nomi bilan bir xil');
    assert.strictEqual(settlementLedger.accountTypeOf(W.AVA_FEE_ACCOUNT), 'liability');
  });

  await check('TO\'LIQ OQIM: place → SHIP_FUND → custody delivery → relay RELEASE + tovar RELEASE; balanslar, eskroular 0', async () => {
    await seed();
    const { orderId: id } = await place();
    await seedShipment(id);
    const { before, after } = await link(id);
    const r1 = await api.onStatusChange(before, after, id);
    assert.strictEqual(r1.funded, 60000, JSON.stringify(r1));
    assert.strictEqual(await bal(W.escrowAccount(id)), 140000);
    assert.strictEqual(await bal(relay.escrowAccount(SHIP)), 60000);
    const s1 = await shipOf();
    assert.deepStrictEqual([s1.paymentStatus, s1.status, s1.escrowAmount, s1.escrowEntryId], ['escrow_funded', 'ready', 60000, W.shipFundKey(id)]);
    let o = await orderOf(id);
    assert.strictEqual(o.status, 'in_delivery');
    assert.strictEqual(o.payment.deliveryFunded, true);
    assert.strictEqual(o.payment.status, 'held');
    const j = (await db.collection(settlementLedger.COL_JOURNAL).doc(W.shipFundKey(id)).get()).data();
    // postEntry oyoqlarni normallashtiradi ({account, dr, cr}).
    assert.deepStrictEqual(j.legs, [
      { account: W.escrowAccount(id), dr: 60000, cr: 0 }, { account: relay.escrowAccount(SHIP), dr: 0, cr: 60000 },
    ]);
    // takror trigger / to'g'ridan-to'g'ri chaqiruv — ikkinchi o'tkazma YO'Q
    assert.strictEqual((await api.onStatusChange(before, after, id)).skipped, 'already_funded');
    assert.strictEqual((await api.shipFund(id)).skipped, 'already_funded');
    assert.strictEqual(await bal(relay.escrowAccount(SHIP)), 60000);

    const ev = await deliver();
    const out = await relayApi.onCustodyEvent(ev);
    assert.strictEqual(out.release.released, 60000);
    assert.strictEqual(out.wholesale.released, 140000, JSON.stringify(out.wholesale));
    // Yakuniy balanslar
    assert.strictEqual(await bal(pcOf(BUYER)), 100000, 'xaridor −total');
    assert.strictEqual(await bonusOf(BUYER), 100000);
    assert.strictEqual(await bal(pcOf(SELLER)), 136500, 'sotuvchi +sellerPayout');
    assert.strictEqual(await bonusOf(SELLER), 136500, 'sotuvchi hamyoni ko\'zgusi');
    assert.strictEqual(await bal(W.AVA_FEE_ACCOUNT), 3500, 'AVA ulushi');
    assert.strictEqual(await bal(W.escrowAccount(id)), 0, 'escrow:wholesale AYNAN 0');
    assert.strictEqual(await bal(relay.escrowAccount(SHIP)), 0, 'escrow:{shipment} 0 (relay RELEASE)');
    assert.strictEqual(await bal(relay.PLATFORM_FEE_ACCOUNT), 12000);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), 48000);
    assert.strictEqual(await bal(relay.ACCRUAL_ACCOUNT), 0);
    o = await orderOf(id);
    assert.strictEqual(o.status, 'delivered');
    assert.strictEqual(o.payment.status, 'released');
    assert.strictEqual(o.payment.releaseEntryId, W.releaseKey(id));
    assert.strictEqual((await shipOf()).paymentStatus, 'settled');
    const jr = (await db.collection(settlementLedger.COL_JOURNAL).doc(W.releaseKey(id)).get()).data();
    assert.deepStrictEqual(jr.legs, [
      { account: W.escrowAccount(id), dr: 140000, cr: 0 },
      { account: pcOf(SELLER), dr: 0, cr: 136500 },
      { account: W.AVA_FEE_ACCOUNT, dr: 0, cr: 3500 },
    ]);
    const wl = (await db.collection('users').doc(SELLER).collection('wallet_ledger').where('type', '==', 'wholesale_payout').get()).docs.map((d) => d.data());
    assert.strictEqual(wl.length, 1);
    assert.strictEqual(wl[0].amount, 136500);
    const h = await historyOf(id);
    assert.deepStrictEqual(h.filter((x) => x.event).map((x) => x.event).sort(), ['goods_released', 'ship_funded']);
    assert.ok(h.some((x) => x.from === 'in_delivery' && x.to === 'delivered' && x.actor === 'system'));
    // TAKROR hodisa (at-least-once) va reconcile — ikki marta to'lanmaydi
    const out2 = await relayApi.onCustodyEvent(ev);
    assert.strictEqual(out2.wholesale.skipped, 'already_released');
    assert.strictEqual((await api.releaseGoods(id)).skipped, 'already_released');
    clock = new Date(T0.getTime() + 60 * 60 * 1000);
    const rc = await api.reconcile();
    assert.deepStrictEqual([rc.shipFunded, rc.released], [0, 0]);
    assert.strictEqual(await bal(pcOf(SELLER)), 136500);
    assert.strictEqual(await bal(W.AVA_FEE_ACCOUNT), 3500);
    assert.strictEqual(await bal(W.escrowAccount(id)), 0);
    await assertLedgerSound();
  });

  await check('parallel tovar RELEASE ×3 — bitta to\'lov', async () => {
    await seed();
    const { orderId: id } = await place();
    await seedShipment(id);
    await link(id);
    assert.strictEqual((await api.shipFund(id)).funded, 60000);
    await deliver();
    const rs = await Promise.allSettled([api.releaseGoods(id), api.releaseGoods(id), api.releaseGoods(id)]);
    const paid = rs.filter((x) => x.status === 'fulfilled' && x.value.released && !x.value.idempotent).length;
    assert.strictEqual(paid, 1, JSON.stringify(rs.map((x) => x.value || x.reason.message)));
    assert.strictEqual(await bal(pcOf(SELLER)), 136500);
    assert.strictEqual(await bonusOf(SELLER), 136500);
    assert.strictEqual(await bal(W.escrowAccount(id)), 0);
    await assertLedgerSound();
  });

  await check('deliveryFee ≠ customerPrice → anomaliya, pul YO\'Q; trigger qayta aylanmaydi', async () => {
    await seed();
    const { orderId: id } = await place();
    await seedShipment(id, { price: 59999 });
    const { before, after } = await link(id);
    const r = await api.onStatusChange(before, after, id);
    assert.deepStrictEqual([r.skipped, r.anomaly], ['delivery_fee_mismatch', true]);
    assert.strictEqual(await bal(W.escrowAccount(id)), 200000);
    assert.strictEqual(await bal(relay.escrowAccount(SHIP)), 0);
    assert.strictEqual((await db.collection(settlementLedger.COL_JOURNAL).doc(W.shipFundKey(id)).get()).exists, false);
    const o = await orderOf(id);
    assert.strictEqual(o.status, 'placed');
    assert.strictEqual(o.shipFundAnomaly.code, 'delivery_fee_mismatch');
    const s = await shipOf();
    assert.deepStrictEqual([s.status, s.paymentStatus], ['awaiting_payment', 'pending']);
    // Belgi yozuvi triggerni yana chaqiradi — u qayta urinmaydi (reconcile urinadi).
    assert.strictEqual((await api.onStatusChange(after, o, id)).skipped, 'no_refund_needed');
    await assertLedgerSound();
  });

  await check('himoya: yetkazish haqi o\'tgan buyurtmada to\'liq qaytarish ISHLAMAYDI (pul ikki marta qaytmaydi)', async () => {
    await seed();
    const { orderId: id } = await place();
    await seedShipment(id);
    await link(id);
    await api.shipFund(id);
    // Admin oqimi (5-bosqich) hali yo'q — kimdir holatni majburan o'zgartirgan holat.
    await db.collection('wholesale_orders').doc(id).update({ status: 'cancelled', refundStatus: 'pending', statusUpdatedAt: clock });
    const r = await api.refundOrder(id);
    assert.deepStrictEqual([r.skipped, r.anomaly], ['delivery_funded', true]);
    const r2 = await api.onStatusChange({}, await orderOf(id), id);
    assert.strictEqual(r2.skipped, 'delivery_funded');
    assert.strictEqual(await bal(pcOf(BUYER)), 100000, 'xaridorga qaytmadi');
    assert.strictEqual(await bal(W.escrowAccount(id)), 140000);
    assert.strictEqual(await bal(relay.escrowAccount(SHIP)), 60000);
    assert.strictEqual((await orderOf(id)).refundStatus, 'pending');
    await assertLedgerSound();
  });

  await check('xaridor haq o\'tmasdan bekor qilsa — SHIP_FUND o\'tkazilmaydi, qaytarish to\'liq', async () => {
    await seed();
    const { orderId: id } = await place();
    await seedShipment(id);
    await link(id);
    const after = await demandFlip(id, 'cancelled');
    assert.strictEqual((await api.shipFund(id)).skipped, 'status_cancelled');
    const r = await api.onStatusChange({}, after, id);
    assert.strictEqual(r.refunded, 200000);
    assert.strictEqual(await bal(pcOf(BUYER)), 300000);
    assert.strictEqual(await bal(relay.escrowAccount(SHIP)), 0);
    assert.strictEqual(await bal(W.escrowAccount(id)), 0);
    await assertLedgerSound();
  });

  await check('reconcile: qotgan SHIP_FUND (>10 daq) va qotgan RELEASE (>10 daq) qayta urinadi; yoshlari kutadi', async () => {
    await seed();
    const { orderId: id } = await place();
    await seedShipment(id);
    await link(id); // trigger «yiqilgan» — chaqirilmaydi
    clock = new Date(T0.getTime() + 5 * 60 * 1000);
    let r = await api.reconcile();
    assert.deepStrictEqual([r.shipFundChecked, r.shipFunded], [0, 0]);
    clock = new Date(T0.getTime() + 11 * 60 * 1000);
    r = await api.reconcile();
    assert.deepStrictEqual([r.shipFundChecked, r.shipFunded], [1, 1]);
    assert.strictEqual((await orderOf(id)).status, 'in_delivery');
    await deliver(); // deliveredAt = T0+11; custody triggeri «yiqilgan»
    await relayApi.releaseEscrow(SHIP);
    clock = new Date(T0.getTime() + 15 * 60 * 1000);
    r = await api.reconcile();
    assert.deepStrictEqual([r.releaseChecked, r.released], [0, 0]);
    clock = new Date(T0.getTime() + 22 * 60 * 1000);
    r = await api.reconcile();
    assert.deepStrictEqual([r.releaseChecked, r.released, r.failed], [1, 1, 0]);
    r = await api.reconcile();
    assert.deepStrictEqual([r.releaseChecked, r.released], [0, 0]);
    assert.strictEqual((await orderOf(id)).status, 'delivered');
    assert.strictEqual(await bal(pcOf(SELLER)), 136500);
    assert.strictEqual(await bal(W.escrowAccount(id)), 0);
    assert.strictEqual(await bal(relay.escrowAccount(SHIP)), 0);
    await assertLedgerSound();
  });

  await check('relay: sotuvchi fundShipmentEscrow bilan to\'lay olmaydi; refund_pending — pul escrow:wholesale ga qaytadi (sotuvchiga emas)', async () => {
    await seed();
    await topup(SELLER, 100000);
    const { orderId: id } = await place();
    await seedShipment(id);
    const e = await expectErr(relayApi.fund({ shipmentId: SHIP }, ctx(SELLER)), 'permission-denied');
    assert.strictEqual(e.details.reason, 'wholesale_managed');
    assert.strictEqual(await bal(pcOf(SELLER)), 100000);
    await link(id);
    await api.shipFund(id);
    await db.collection('shipments').doc(SHIP).update({ paymentStatus: 'refund_pending', status: 'cancelled' });
    const rr = await relayApi.refundEscrow(SHIP);
    assert.strictEqual(rr.refunded, 60000);
    assert.strictEqual(await bal(relay.escrowAccount(SHIP)), 0);
    assert.strictEqual(await bal(W.escrowAccount(id)), 200000, 'xaridorning buyurtma eskrousiga qaytdi');
    assert.strictEqual(await bal(pcOf(SELLER)), 100000, 'sotuvchi hamyoniga TUSHMADI');
    assert.strictEqual(await bonusOf(SELLER), 100000);
    await assertLedgerSound();
  });

  await check('tovar RELEASE: jo\'natma yetkazilmagan — kutadi; sotuvchi hamyoni yo\'q — anomaliya, pul YO\'Q', async () => {
    await seed();
    const { orderId: id } = await place();
    await seedShipment(id);
    await link(id);
    await api.shipFund(id);
    assert.strictEqual((await api.releaseGoods(id)).skipped, 'shipment_ready');
    // Yo'qolgan posilka `lost → closed` (deliveredAt yo'q, loss_settled) — tovar puli sotuvchiga KETMAYDI.
    await db.collection('shipments').doc(SHIP).update({ status: 'closed', paymentStatus: 'loss_settled', updatedAt: clock });
    assert.strictEqual((await api.releaseGoods(id)).skipped, 'shipment_closed');
    assert.strictEqual((await api.onShipmentDelivered(SHIP)).skipped, 'shipment_closed');
    clock = new Date(T0.getTime() + 60 * 60 * 1000);
    assert.strictEqual((await api.reconcile()).releaseChecked, 0);
    assert.strictEqual(await bal(W.escrowAccount(id)), 140000);
    await db.collection('shipments').doc(SHIP).update({ status: 'in_transit', paymentStatus: 'escrow_funded' });
    await deliver();
    await db.collection('users').doc(SELLER).delete();
    const r = await api.releaseGoods(id);
    assert.deepStrictEqual([r.skipped, r.anomaly], ['seller_wallet_missing', true]);
    assert.strictEqual(await bal(W.escrowAccount(id)), 140000);
    assert.strictEqual((await orderOf(id)).releaseAnomaly.code, 'seller_wallet_missing');
    assert.strictEqual((await orderOf(id)).status, 'in_delivery');
  });

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\nwholesale_orders (default): ${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
})();
