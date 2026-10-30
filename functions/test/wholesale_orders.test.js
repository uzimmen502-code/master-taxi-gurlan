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

/** Demand `cancelWholesaleOrder` / `rejectWholesaleOrder` yozadigan holat. */
async function demandFlip(orderId, to) {
  const ref = db.collection('wholesale_orders').doc(orderId);
  await ref.update({ status: to, refundStatus: 'pending', statusUpdatedAt: clock, updatedAt: clock, historySeq: 2 });
  await ref.collection('history').doc('2').set({ seq: 2, from: 'placed', to, actor: to === 'cancelled' ? 'buyer' : 'seller', at: clock });
  const after = (await ref.get()).data();
  return after;
}

(async () => {
  await check('paritet: holat nomlari demand jadvali bilan bir xil; eskrou hisob turi', async () => {
    assert.strictEqual(W.STATUS.PLACED, WO.STATUS.PLACED);
    assert.strictEqual(W.STATUS.REJECTED, WO.STATUS.REJECTED);
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
    await demandFlip(id, 'rejected');
    const rs = await Promise.allSettled([api.refundOrder(id), api.refundOrder(id), api.refundOrder(id)]);
    const refunded = rs.filter((x) => x.status === 'fulfilled' && x.value.refunded).length;
    assert.strictEqual(refunded, 1, JSON.stringify(rs));
    assert.strictEqual(await bal(pcOf(BUYER)), 300000);
    assert.strictEqual((await stockOf()).packs.p1, 100);
    await assertLedgerSound();
  });

  await check('trigger: refund kerak bo\'lmagan holatlar (placed, accepted, pending yo\'q) — tegmaydi', async () => {
    await seed();
    const { orderId: id } = await place();
    assert.strictEqual((await api.onStatusChange({}, { status: 'accepted', refundStatus: null }, id)).skipped, 'no_refund_needed');
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
    await demandFlip(newId, 'rejected'); // T0+9
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

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\nwholesale_orders (default): ${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
})();
