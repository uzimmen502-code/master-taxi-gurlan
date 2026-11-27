/**
 * «ЕТКАЗИЛМАДИ» — нон/бозор, гилам, сут, йиғиш (эга қарорлари 2026-10-31; delivery_failed.js).
 * HAQIQIY `functions/index.js` callable'lari va jadvali `.run()` orqali, Firestore Emulator, haqiqiy ledger.
 *
 *   firebase emulators:exec --only firestore --project demo-df-other --config <cfg> \
 *     "node functions/test/delivery_failed_cf.test.js"
 *
 * Qulflanadi (positive / negative / boundary / idempotency / concurrency):
 *   - kuryer xabari holat va pulni O'ZGARTIRMAYDI: belgi + muddat; takror/parallel — bitta so'rov; nonda marshrut oxiriga
 *   - mijoz tasdig'i → yakun (non: hamyon qismi deliveryFee bilan TO'LIQ, soldToday tiklanadi, marshrutdan chiqadi;
 *     gilam → navbat/sex; sut → navbat; yig'ish → failed + ariza bo'shaydi); mijoz rad → davom
 *   - muddatgacha qaror yo'q (DECISION_NOT_YET); sotuvchi faqat non/bozor; admin hammasi; audit
 *   - jadval: chegara, bir marta, eskirgan maydon tozalanadi; restoran jadvali non maydoniga tegmaydi
 *   - parallel: mijoz + sotuvchi 'failed' + sotuvchi 'continue' → bitta g'olib, pul bir marta
 *   - eski APK: yakundan keyin courierSubmitPayment rad etiladi; restoran moduli bilan non belgisini tasdiqlab bo'lmaydi
 *   - sverka: Σdr == Σcr
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18282';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-df-other';
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.CUSTOMER_CONFIRM_CACHE_MS = '0';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require('../index');
const admin = require('firebase-admin');
const ledger = require('../settlement_ledger');
const dfLib = require('../delivery_failed');

const db = admin.firestore();

// Soxta raqamlar (PII yo'q).
const ADMIN = '998900000101';
const SELLER = '998900000102';
const DISPATCHER = '998900000103';
const A = '998900000201'; // kuryer
const B = '998900000202'; // boshqa kuryer
const C1 = '998900000301'; // mijoz
const C2 = '998900000302'; // boshqa mijoz
const ACC = { [A]: 'accDFOTHERCOURIER0A', [B]: 'accDFOTHERCOURIER0B' };
const PRICE = 30000;
const FEE_PCT = 10;
const FEE = PRICE * FEE_PCT / 100; // 3000
const TOTAL = PRICE + FEE;

const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, ctxOf(who));
const at = (ms) => admin.firestore.Timestamp.fromMillis(ms);

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
async function expectReason(promise, reason, httpsCode) {
  await assert.rejects(promise, (e) => {
    const got = (e.details && (e.details.reason || e.details.code)) || e.message;
    assert.strictEqual(got, reason, `sabab ${got} (${e.code}): ${e.message}`);
    if (httpsCode) assert.strictEqual(e.code, httpsCode, `kod ${e.code}`);
    return true;
  });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
async function journalBalanced() {
  const s = await db.collection(ledger.COL_JOURNAL).get();
  for (const d of s.docs) {
    const legs = d.data().legs || [];
    const dr = legs.reduce((x, l) => x + (l.dr || 0), 0);
    const cr = legs.reduce((x, l) => x + (l.cr || 0), 0);
    assert.strictEqual(dr, cr, `journal ${d.id}`);
  }
}
async function seedCourier(phone) {
  await db.collection('users').doc(phone).set({ role: 'user', accountId: ACC[phone], bonusBalance: 0 });
  await db.collection('provider_capabilities').doc(ACC[phone]).set({
    identity: { accountId: ACC[phone], primaryUid: phone }, courier: { active: true }, status: { courier: 'approved' },
  });
}
async function reset() {
  await clearEmulator();
  await db.collection('users').doc(ADMIN).set({ role: 'admin', phone: ADMIN });
  await db.collection('users').doc(SELLER).set({ role: 'seller', phone: SELLER, appLang: 'ru' });
  await db.collection('users').doc(DISPATCHER).set({ role: 'dispatcher', phone: DISPATCHER });
  await db.collection('users').doc(C1).set({ role: 'user', phone: C1, bonusBalance: 500000, appLang: 'uz_Latn' });
  await db.collection('users').doc(C2).set({ role: 'user', phone: C2, bonusBalance: 500000 });
  await seedCourier(A);
  await seedCourier(B);
  await db.collection('platform_products').doc('plov').set({ name: 'Plov', price: PRICE, unit: 'porsiya', totalStock: 100, soldToday: 0 });
  await db.collection('settings').doc('app').set({ platformDeliveryFeePercent: FEE_PCT });
}

let seq = 0;
const uniq = (p) => `${p}${(seq += 1)}`;
const col = (m) => dfLib.SPECS[m].collection;
const get = async (m, id) => (await db.collection(col(m)).doc(id).get()).data() || {};
const bal = async (uid) => ((await db.collection('users').doc(uid).get()).data() || {}).bonusBalance || 0;
const events = async (m, id) => (await db.collection('delivery_failed_events').where('refId', '==', id).get()).docs
  .map((d) => d.data()).filter((e) => e.module === m);
const sold = async () => ((await db.collection('platform_products').doc('plov').get()).data() || {}).soldToday || 0;
const routeOf = async (id) => {
  const s = await db.collection('delivery_routes').where('courierId', '==', A).get();
  return s.docs.map((d) => ({ id: d.id, ...d.data() })).find((r) => (r.orders || []).includes(id)) || null;
};

/** Haqiqiy oqim: placeOrderPostPaid (hamyon bilan, platform + 10 % yetkazish) → ready → courierCreateRoute. */
async function placeRouted(n = 1, { customer = C1, wallet = true } = {}) {
  const ids = [];
  for (let i = 0; i < n; i += 1) {
    const r = await call('placeOrderPostPaid', {
      userPhone: customer, idempotencyKey: uniq('k_'),
      orderBase: {
        type: 'platform', userName: 'Test', address: 'Gurlan', phone: customer,
        items: [{ productId: 'plov', qty: 1 }], useWallet: wallet, balanceApplied: wallet ? TOTAL : 0,
      },
    }, customer);
    await db.collection('orders').doc(r.orderId).update({ status: 'ready' });
    ids.push(r.orderId);
  }
  // Har stsenariy — yangi marshrut (kuryerda bitta faol marshrut; eskisi yopiladi).
  const old = await db.collection('delivery_routes').where('courierId', '==', A).where('status', 'in', ['active', 'ready']).get();
  await Promise.all(old.docs.map((d) => d.ref.update({ status: 'completed' })));
  await call('courierCreateRoute', { courierPhone: A, orderedOrderIds: ids }, A);
  return ids;
}
const arrive = (id, who = A) => call('courierMarkArrived', { orderId: id, courierPhone: who }, who);
const report = (m, id, who = A, reason = 'customer_absent') => call('courierReportDeliveryFailed', { module: m, id, reason }, who);
const custDecide = (m, id, who, decision, extra = {}) => call('customerConfirmHandover',
  { module: m, id, step: 'delivery_failed', ...(decision ? { decision } : {}), ...extra }, who);
const resolve = (m, id, who, decision) => call('resolveDeliveryFailed', { module: m, id, decision }, who);
const escalate = () => fns.escalateDeliveryFailed.run({});
const pastDue = (m, id) => db.collection(col(m)).doc(id).update({
  deliveryFailedDueAt: at(Date.now() - 1000), 'awaitingCustomerConfirm.escalateAt': at(Date.now() - 1000),
});

async function seedCarpet(id, { leg = 'pickup', courier = A, arrived = true, customer = C1 } = {}) {
  const pickup = leg === 'pickup';
  await db.collection('carpet_wash_orders').doc(id).set({
    customerId: customer, customerPhone: customer, customerName: 'Mijoz', pickupAddress: 'Gurlan, test',
    carpetCount: 2, finalPrice: 100000, status: pickup ? 'pickup_in_delivery' : 'return_in_delivery',
    pickupCourierId: pickup ? courier : B, returnCourierId: pickup ? '' : courier,
    ...(arrived ? { [pickup ? 'pickupArrivedAt' : 'returnArrivedAt']: at(Date.now() - 60000) } : {}),
    createdAt: at(Date.now() - 3600000), updatedAt: at(Date.now() - 3600000),
  });
}
async function seedAgro(id, { courier = A, arrived = true } = {}) {
  await db.collection('agro_pickup_orders').doc(id).set({
    customerId: C1, customerPhone: C1, customerName: 'Mijoz', productType: 'milk', literCount: 10,
    pickupAddress: 'Gurlan, test', finalPrice: 0, status: 'pickup_in_delivery', pickupCourierId: courier,
    ...(arrived ? { arrivedAt: at(Date.now() - 60000) } : {}),
    createdAt: at(Date.now() - 3600000), updatedAt: at(Date.now() - 3600000),
  });
}
async function seedCollection(id, { courier = A } = {}) {
  await db.collection('procurement_products').doc('milk').set({ code: 'milk', label: 'Sut', unit: 'l', price: 5000, active: true });
  await db.collection('sell_submissions').doc(`sub_${id}`).set({
    userId: C1, userPhone: C1, userName: 'Mijoz', status: 'reviewed', collectionTaskId: id, inCollection: true,
  });
  await db.collection('collection_tasks').doc(id).set({
    submissionId: `sub_${id}`, customerPhone: C1, customerUid: C1, customerName: 'Mijoz', pickupAddress: 'Gurlan',
    items: [{ code: 'milk', label: 'Sut', unit: 'l', qty: 10, unitPrice: 5000, lineTotal: 50000 }],
    totalValue: 50000, courierId: courier, status: 'assigned', createdAt: at(Date.now() - 3600000), createdBy: ADMIN,
  });
}

async function main() {
  await reset();

  // ═════════════ 0. Sof qism ═══════════════════════════════════════════
  await check('routeAfter: oxiriga surish / chiqarish (indeks tuzatiladi) / chegaralar', async () => {
    assert.deepStrictEqual(dfLib.routeAfter({ orders: ['a', 'b', 'c'], currentIndex: 0 }, 'a', 'to_end'), { orders: ['b', 'c', 'a'], currentIndex: 0, exhausted: false });
    assert.strictEqual(dfLib.routeAfter({ orders: ['a', 'b'], currentIndex: 1 }, 'b', 'to_end'), null, 'oxirgisi — o\'zgarmaydi');
    assert.strictEqual(dfLib.routeAfter({ orders: ['a', 'b'], currentIndex: 0 }, 'b', 'to_end'), null, 'joriy emas — o\'zgarmaydi');
    assert.deepStrictEqual(dfLib.routeAfter({ orders: ['a', 'b', 'c'], currentIndex: 2 }, 'a', 'remove'), { orders: ['b', 'c'], currentIndex: 1, exhausted: false });
    assert.deepStrictEqual(dfLib.routeAfter({ orders: ['a'], currentIndex: 0 }, 'a', 'remove'), { orders: [], currentIndex: 0, exhausted: true });
    assert.deepStrictEqual(dfLib.routeAfter({ orders: ['a', 'b'], currentIndex: 1 }, 'b', 'remove'), { orders: ['a'], currentIndex: 1, exhausted: true });
    assert.strictEqual(dfLib.routeAfter({ orders: ['a'], currentIndex: 0 }, 'x', 'remove'), null);
  });

  // ═════════════ 1. NON/BOZOR: kuryer xabari ══════════════════════════
  await check('order: noto\'g\'ri sabab / modul — invalid-argument; begona kuryer — rad; ready (marshrutsiz) — rad', async () => {
    const [id] = await placeRouted(1);
    await arrive(id);
    await expectReason(report('order', id, A, 'bogus'), 'DF_REASON_INVALID', 'invalid-argument');
    await expectReason(call('courierReportDeliveryFailed', { module: 'wholesale', id, reason: 'other' }, A), 'DF_ARGS_INVALID');
    await assert.rejects(report('order', id, B), (e) => e.code === 'permission-denied');
    assert.ok(!(await get('order', id)).awaitingCustomerConfirm);
  });

  let mainId;
  let otherId;
  await check('order: xabar → holat/pul O\'ZGARMAYDI, belgi + 15 daq, marshrut oxiriga suriladi, bitta hodisa; takror+parallel idempotent', async () => {
    [mainId, otherId] = await placeRouted(2);
    await arrive(mainId);
    const b0 = await bal(C1);
    const t0 = Date.now();
    const rs = await Promise.all([report('order', mainId), report('order', mainId, A, 'other'), report('order', mainId, A, 'courier_problem')]);
    for (const r of rs) assert.strictEqual(r.awaitingCustomer, true);
    const d = await get('order', mainId);
    assert.strictEqual(d.status, 'in_delivery');
    assert.strictEqual(d.fulfillmentStatus, 'arrived');
    const m = d.awaitingCustomerConfirm;
    assert.strictEqual(m.step, 'delivery_failed');
    assert.strictEqual(m.module, 'order');
    assert.strictEqual(m.leg, 'delivery');
    assert.strictEqual(m.courierId, A);
    assert.strictEqual(d.deliveryFailedOpen, true);
    const due = d.deliveryFailedDueAt.toMillis();
    assert.ok(due >= t0 + 15 * 60000 - 3000 && due <= Date.now() + 15 * 60000 + 3000, `muddat ${due - t0}`);
    assert.strictEqual(m.escalateAt.toMillis(), due);
    assert.ok(!('deliveryFailedEscalateAt' in d), 'restoran maydoni ishlatilmaydi');
    assert.strictEqual(await bal(C1), b0, 'hamyon o\'zgarmadi');
    const r = await routeOf(mainId);
    assert.deepStrictEqual(r.orders, [otherId, mainId], 'oxiriga surildi');
    assert.strictEqual(r.currentIndex, 0);
    assert.strictEqual((await events('order', mainId)).filter((e) => e.kind === 'requested').length, 1);
    const again = await report('order', mainId, A, 'other');
    assert.strictEqual(again.idempotent, true);
    assert.strictEqual(again.escalateAtMs, due);
    assert.strictEqual((await get('order', mainId)).awaitingCustomerConfirm.failReason, m.failReason, 'sabab o\'zgarmaydi');
  });

  await check('order: getCustomerPendingConfirmations — modul order, canReject, sabab; begonaga yo\'q; restoran moduli bilan tasdiqlab bo\'lmaydi (belgi QOLADI)', async () => {
    const res = await call('getCustomerPendingConfirmations', {}, C1);
    const it = res.items.find((x) => x.id === mainId);
    assert.ok(it, 'element bor');
    assert.strictEqual(it.module, 'order');
    assert.strictEqual(it.step, 'delivery_failed');
    assert.strictEqual(it.canReject, true);
    assert.ok(['customer_absent', 'other', 'courier_problem'].includes(it.details.failReason));
    assert.ok(/Kuryer/.test(it.title), `lotin: ${it.title}`);
    assert.ok(!JSON.stringify(it).includes(A), 'kuryer telefoni yo\'q');
    assert.strictEqual(res.items.filter((x) => x.id === mainId).length, 1, 'restoran ro\'yxatida takrorlanmaydi');
    assert.ok(!(await call('getCustomerPendingConfirmations', {}, C2)).items.some((x) => x.id === mainId));
    await expectReason(custDecide('restaurant', mainId, C1), 'NOT_AWAITING');
    await expectReason(custDecide('order', mainId, C2), 'NOT_YOUR_ORDER', 'permission-denied');
    await expectReason(call('customerConfirmHandover', { module: 'order', id: mainId, step: 'received' }, C1), 'CONFIRM_ARGS_INVALID');
    assert.strictEqual((await get('order', mainId)).awaitingCustomerConfirm.step, 'delivery_failed');
  });

  await check('order: muddatgacha sotuvchi qaror qila olmaydi (DECISION_NOT_YET); oddiy foydalanuvchi/dispetcher — DF_NOT_ALLOWED; ro\'yxatda canDecide=false', async () => {
    await expectReason(resolve('order', mainId, SELLER, 'failed'), 'DECISION_NOT_YET', 'failed-precondition');
    await expectReason(resolve('order', mainId, C1, 'failed'), 'DF_NOT_ALLOWED', 'permission-denied');
    await expectReason(resolve('order', mainId, DISPATCHER, 'failed'), 'DF_NOT_ALLOWED');
    await expectReason(resolve('order', mainId, SELLER, 'cancel'), 'DF_ARGS_INVALID', 'invalid-argument');
    const l = await call('listDeliveryFailedPending', {}, SELLER);
    const it = l.items.find((x) => x.id === mainId);
    assert.ok(it && it.canDecide === false && it.escalated === false);
    assert.strictEqual(it.customerPhoneTail, C1.slice(-4));
    assert.ok(!JSON.stringify(l).includes(C1), 'to\'liq telefon yo\'q');
    await expectReason(call('listDeliveryFailedPending', {}, C1), 'DF_NOT_ALLOWED');
  });

  await check('order: mijoz tasdig\'i → cancelled/delivery_failed, hamyon qismi (deliveryFee bilan) BIR marta qaytadi, soldToday tiklanadi, marshrutdan chiqadi, strike hisoblagichi; takror idempotent', async () => {
    const b0 = await bal(C1);
    const s0 = await sold();
    await db.collection('order_courier_live').doc(mainId).set({ lat: 41, lng: 60 });
    const r = await custDecide('order', mainId, C1);
    assert.strictEqual(r.status, 'cancelled');
    const d = await get('order', mainId);
    assert.strictEqual(d.status, 'cancelled');
    assert.strictEqual(d.fulfillmentStatus, 'delivery_failed');
    assert.ok(/^delivery_failed:/.test(d.cancelReason));
    assert.strictEqual(d.deliveryFailedResolution.by, 'customer');
    assert.strictEqual(d.deliveryFailedResolution.decision, 'failed');
    assert.ok(d.customerConfirmed && d.customerConfirmed.delivery_failed);
    for (const f of ['awaitingCustomerConfirm', 'hasAwaitingCustomerConfirm', 'deliveryFailedDueAt', 'deliveryFailedOpen']) assert.ok(!(f in d), f);
    assert.strictEqual(d.balanceApplied, TOTAL, 'deliveryFee hamyon qismi ichida');
    assert.strictEqual(await bal(C1), b0 + TOTAL, 'to\'liq qaytdi');
    assert.strictEqual(await sold(), s0 - 1, 'soldToday tiklandi');
    assert.ok(!(await db.collection('order_courier_live').doc(mainId).get()).exists, 'kuryer nuqtasi o\'chdi');
    const rt = await routeOf(otherId);
    assert.deepStrictEqual(rt.orders, [otherId]);
    assert.strictEqual(rt.status, 'active');
    // Parallel xabarlardan qaysi sabab yutgani — strike faqat customer_absent/customer_refused da (4-qaror).
    const st = (await db.collection('customer_delivery_stats').doc(C1).get()).data() || {};
    if (['customer_absent', 'customer_refused'].includes(d.failReason)) assert.ok(st.failedStrikes >= 1 && st.failedStrikesByModule.order >= 1, JSON.stringify(st));
    else assert.ok(!st.failedStrikes, 'boshqa sababda strike yo\'q');
    assert.ok(!(await db.collection('restaurant_customer_stats').doc(C1).get()).exists, 'restoran strike\'iga qo\'shilmaydi');
    const ev = await events('order', mainId);
    assert.strictEqual(ev.filter((e) => e.kind === 'failed').length, 1);
    assert.strictEqual(ev.filter((e) => e.kind === 'goods_return_to_seller').length, 1);
    const again = await custDecide('order', mainId, C1);
    assert.strictEqual(again.idempotent, true);
    assert.strictEqual(await bal(C1), b0 + TOTAL, 'ikkinchi marta qaytmadi');
    assert.strictEqual((await resolve('order', mainId, SELLER, 'failed')).idempotent, true);
    await expectReason(resolve('order', mainId, SELLER, 'continue'), 'DF_NOT_AWAITING_DECISION');
    await journalBalanced();
  });

  await check('order (eski APK): yakundan keyin courierSubmitPayment va courierMarkArrived RAD etiladi; xabar ham rad', async () => {
    await assert.rejects(call('courierSubmitPayment', { orderId: mainId, courierPhone: A, lines: [{ kind: 'cash', amount: TOTAL }] }, A));
    await assert.rejects(arrive(mainId));
    await assert.rejects(report('order', mainId));
    assert.strictEqual((await get('order', mainId)).status, 'cancelled');
  });

  await check('order: oxirgi buyurtma yakunlansa marshrut YOPILADI (completed)', async () => {
    await arrive(otherId);
    await report('order', otherId, A, 'customer_refused');
    await custDecide('order', otherId, C1);
    const s = await db.collection('delivery_routes').where('courierId', '==', A).get();
    const r = s.docs.map((x) => x.data()).find((x) => x.completedReason === 'delivery_failed');
    assert.ok(r, 'marshrut yopildi');
    assert.strictEqual(r.status, 'completed');
    assert.deepStrictEqual(r.orders, []);
    const st = (await db.collection('customer_delivery_stats').doc(C1).get()).data() || {};
    assert.ok(st.failedStrikes >= 1 && st.failedStrikesByModule.order >= 1, `customer_refused → strike: ${JSON.stringify(st)}`);
  });

  await check('order: mijoz rad («Олмоқчиман») → davom: belgi o\'chadi, holat arrived, pul yo\'q; takror idempotent; keyin kuryer naqd to\'lov bilan yakunlaydi', async () => {
    const [id] = await placeRouted(1, { customer: C2, wallet: false });
    await arrive(id);
    await report('order', id);
    const b0 = await bal(C2);
    const r = await custDecide('order', id, C2, 'reject');
    assert.strictEqual(r.decision, 'reject');
    let d = await get('order', id);
    assert.strictEqual(d.fulfillmentStatus, 'arrived');
    assert.strictEqual(d.deliveryFailedResolution.decision, 'continue');
    assert.ok(d.customerRejected.delivery_failed);
    for (const f of ['awaitingCustomerConfirm', 'deliveryFailedDueAt', 'deliveryFailedOpen']) assert.ok(!(f in d), f);
    assert.strictEqual((await custDecide('order', id, C2, 'reject')).idempotent, true);
    await expectReason(custDecide('order', id, C2), 'NOT_AWAITING');
    assert.strictEqual(await bal(C2), b0);
    const pay = await call('courierSubmitPayment', { orderId: id, courierPhone: A, lines: [{ kind: 'cash', amount: TOTAL }] }, A);
    assert.ok(pay && pay.ok !== false);
    d = await get('order', id);
    assert.strictEqual(d.fulfillmentStatus, 'completed');
    assert.strictEqual((await events('order', id)).filter((e) => e.kind === 'continue').length, 1);
  });

  await check('order: to\'lov yuborilgan buyurtma — DF_PAYMENT_SUBMITTED; arrived-dan oldin (courier_picked) ham xabar mumkin', async () => {
    const [id1, id2] = await placeRouted(2, { customer: C2, wallet: false });
    await db.collection('wallet_idempotency').doc(`courier_submit_${id1}`).set({ result: { ok: true } });
    await expectReason(report('order', id1), 'DF_PAYMENT_SUBMITTED', 'failed-precondition');
    const r = await report('order', id2, A, 'courier_problem');
    assert.strictEqual(r.awaitingCustomer, true);
    assert.strictEqual((await get('order', id2)).fulfillmentStatus, 'courier_picked');
  });

  // ═════════════ 2. NON: jadval va sotuvchi qarori ════════════════════
  await check('jadval: chegaradan 1.5 s oldin — yo\'q; o\'tgach BIR marta (escalatedAt, hodisa, sotuvchi+admin xabari), ikkinchi ishga tushish — hech narsa; restoran jadvali non maydoniga TEGMAYDI', async () => {
    const [id] = await placeRouted(1);
    await arrive(id);
    await report('order', id);
    await db.collection('orders').doc(id).update({ deliveryFailedDueAt: at(Date.now() + 1500), 'awaitingCustomerConfirm.escalateAt': at(Date.now() + 1500) });
    await escalate();
    assert.ok(!('deliveryFailedEscalatedAt' in (await get('order', id))));
    await pastDue('order', id);
    await fns.escalateRestaurantDeliveryFailed.run({});
    assert.ok('deliveryFailedDueAt' in (await get('order', id)), 'restoran jadvali tozalab yubormadi');
    await escalate();
    const d = await get('order', id);
    assert.ok(d.deliveryFailedEscalatedAt);
    assert.ok(!('deliveryFailedDueAt' in d));
    assert.strictEqual(d.deliveryFailedOpen, true);
    assert.strictEqual(d.awaitingCustomerConfirm.step, 'delivery_failed', 'mijoz hali ham javob bera oladi');
    await escalate();
    assert.strictEqual((await events('order', id)).filter((e) => e.kind === 'escalated').length, 1);
    const news = (await db.collection('admin_news').where('targetUserId', '==', SELLER).get()).docs.map((x) => x.data())
      .filter((n) => n.source === 'delivery_failed');
    assert.strictEqual(news.length, 1, 'sotuvchiga BIR xabar');
    assert.strictEqual(news[0].title, 'Нужно решение по заданию курьера', 'sotuvchi tili ru');
    assert.strictEqual((await db.collection('admin_news').where('targetUserId', '==', ADMIN).get()).docs
      .filter((x) => x.data().source === 'delivery_failed').length, 1, 'admin ham oladi');
    // Sotuvchi 'failed' → yakun + audit (actorRole seller).
    const b0 = await bal(C1);
    const r = await resolve('order', id, SELLER, 'failed');
    assert.strictEqual(r.status, 'cancelled');
    assert.strictEqual(await bal(C1), b0 + TOTAL);
    const dd = await get('order', id);
    assert.strictEqual(dd.deliveryFailedResolution.by, 'seller');
    assert.ok(!('deliveryFailedEscalatedAt' in dd) && !('deliveryFailedOpen' in dd));
    const au = await db.collection('admin_audit').where('kind', '==', 'delivery_failed_decision').get();
    assert.ok(au.docs.some((x) => x.data().target === `orders/${id}` && x.data().actorRole === 'seller' && x.data().actor === SELLER));
  });

  await check('jadval: buyurtma boshqa yo\'l bilan yopilgan (admin delivered) — eskirgan maydonlar tozalanadi, eskalatsiya yo\'q', async () => {
    const [id] = await placeRouted(1);
    await arrive(id);
    await report('order', id);
    await db.collection('orders').doc(id).update({ status: 'delivered', fulfillmentStatus: 'completed', deliveryFailedDueAt: at(Date.now() - 1000) });
    await escalate();
    const d = await get('order', id);
    assert.ok(!('deliveryFailedDueAt' in d) && !('deliveryFailedOpen' in d) && !('deliveryFailedEscalatedAt' in d));
  });

  await check('muddat o\'tgan (jadval ishlamagan) — sotuvchi \'continue\' qila oladi; takror idempotent; admin \'failed\' keyin rad', async () => {
    const [id] = await placeRouted(1);
    await arrive(id);
    await report('order', id);
    await pastDue('order', id);
    const r = await resolve('order', id, SELLER, 'continue');
    assert.strictEqual(r.status, 'in_delivery');
    const d = await get('order', id);
    assert.strictEqual(d.deliveryFailedResolution.by, 'seller');
    assert.strictEqual(d.deliveryFailedResolution.decision, 'continue');
    assert.ok(!(d.customerRejected && d.customerRejected.delivery_failed));
    assert.strictEqual((await resolve('order', id, SELLER, 'continue')).idempotent, true);
    await expectReason(resolve('order', id, ADMIN, 'failed'), 'DF_NOT_AWAITING_DECISION');
  });

  await check('PARALLEL: mijoz tasdig\'i + sotuvchi \'failed\' + admin \'continue\' → bitta yakun, pul BIR marta', async () => {
    const [id] = await placeRouted(1);
    await arrive(id);
    await report('order', id);
    await pastDue('order', id);
    const b0 = await bal(C1);
    const rs = await Promise.allSettled([custDecide('order', id, C1), resolve('order', id, SELLER, 'failed'), resolve('order', id, ADMIN, 'continue')]);
    assert.ok(rs.some((x) => x.status === 'fulfilled'));
    const d = await get('order', id);
    const diff = (await bal(C1)) - b0;
    if (d.status === 'cancelled') assert.strictEqual(diff, TOTAL, 'bir marta');
    else { assert.strictEqual(d.fulfillmentStatus, 'arrived'); assert.strictEqual(diff, 0); }
    const finals = (await events('order', id)).filter((e) => e.kind === 'failed' || e.kind === 'continue');
    assert.strictEqual(finals.length, 1, `bitta yakun: ${finals.map((e) => e.kind)}`);
    const refunds = (await db.collection(ledger.COL_JOURNAL).where('refId', '==', id).get()).docs.filter((x) => x.data().kind === 'order_cancel_refund');
    assert.ok(refunds.length <= 1);
  });

  // ═════════════ 3. GILAM ══════════════════════════════════════════════
  await check('gilam: kelmasdan — DF_ARRIVE_FIRST; begona kuryer — DF_NOT_YOUR_TASK; xabar → holat o\'zgarmaydi, kuryer ro\'yxatida kutish belgisi', async () => {
    const id = uniq('cw_');
    await seedCarpet(id, { arrived: false });
    await expectReason(report('carpet', id), 'DF_ARRIVE_FIRST', 'failed-precondition');
    await expectReason(report('carpet', id, B), 'DF_NOT_YOUR_TASK', 'permission-denied');
    await db.collection('carpet_wash_orders').doc(id).update({ pickupArrivedAt: at(Date.now()) });
    const r = await report('carpet', id);
    assert.strictEqual(r.awaitingCustomer, true);
    const d = await get('carpet', id);
    assert.strictEqual(d.status, 'pickup_in_delivery');
    assert.strictEqual(d.awaitingCustomerConfirm.leg, 'pickup');
    const list = await call('courierListCarpetTasks', { list: 'active' }, A);
    const t = list.tasks.find((x) => x.id === id);
    assert.strictEqual(t.deliveryFailedPending, true);
    assert.ok(t.deliveryFailedEscalateAtMs > Date.now());
    assert.strictEqual(t.deliveryFailedReason, 'customer_absent');
    // Mijoz tasdig'i → navbatga (pickup_ready), kuryer maydonlari tozalanadi, haq yo'q.
    const c = await custDecide('carpet', id, C1);
    assert.strictEqual(c.status, 'pickup_ready');
    const dd = await get('carpet', id);
    assert.strictEqual(dd.status, 'pickup_ready');
    assert.strictEqual(dd.pickupCourierId, '');
    assert.ok(!('pickupArrivedAt' in dd));
    assert.strictEqual(dd.pickupFailedCount, 1);
    assert.ok(!(await db.collection('courier_task_payouts').doc(`carpet_${id}`).get()).exists, 'kuryer haqi yo\'q');
    await assert.rejects(call('courierMarkCarpetPickedUp', { orderId: id, courierPhone: A }, A));
    const pick = await call('courierListCarpetTasks', { list: 'pickup' }, B);
    assert.ok(pick.tasks.some((x) => x.id === id), 'boshqa kuryer olishi mumkin');
  });

  await check('gilam qaytarish: sotuvchi — DF_NOT_ALLOWED; admin muddatdan keyin \'failed\' → return_ready (sex), returnFailedCount, hodisa; mijoz rad → davom va yakunlash ishlaydi', async () => {
    const id = uniq('cw_');
    await seedCarpet(id, { leg: 'return' });
    await report('carpet', id, A, 'customer_refused');
    await pastDue('carpet', id);
    await expectReason(resolve('carpet', id, SELLER, 'failed'), 'DF_NOT_ALLOWED');
    const r = await resolve('carpet', id, ADMIN, 'failed');
    assert.strictEqual(r.status, 'return_ready');
    const d = await get('carpet', id);
    assert.strictEqual(d.returnCourierId, '');
    assert.strictEqual(d.returnFailedCount, 1);
    assert.ok((await events('carpet', id)).some((e) => e.kind === 'goods_return_to_workshop'));
    const id2 = uniq('cw_');
    await seedCarpet(id2, { leg: 'pickup' });
    await report('carpet', id2);
    await custDecide('carpet', id2, C1, 'reject');
    assert.strictEqual((await get('carpet', id2)).status, 'pickup_in_delivery');
    const p = await call('courierMarkCarpetPickedUp', { orderId: id2, courierPhone: A }, A);
    assert.strictEqual(p.ok, true);
    assert.strictEqual((await get('carpet', id2)).status, 'picked_up');
  });

  await check('gilam: admin release (adminSetCarpetWashStatus) kutishni bekor qiladi — mijoz endi tasdiqlay olmaydi, jadval eskirgan maydonni tozalaydi', async () => {
    const id = uniq('cw_');
    await seedCarpet(id);
    await report('carpet', id);
    await call('adminSetCarpetWashStatus', { adminPhone: ADMIN, orderId: id, status: 'pickup_ready', reason: 'test' }, ADMIN);
    await expectReason(custDecide('carpet', id, C1), 'NOT_AWAITING');
    await pastDue('carpet', id).catch(() => db.collection('carpet_wash_orders').doc(id).update({ deliveryFailedDueAt: at(Date.now() - 1000) }));
    await escalate();
    const d = await get('carpet', id);
    assert.ok(!('deliveryFailedDueAt' in d) && !('deliveryFailedOpen' in d));
  });

  // ═════════════ 4. SUT (agro) ═════════════════════════════════════════
  await check('sut: xabar → kuryer ro\'yxatida kutish; admin \'continue\' (muddatdan keyin) → davom; qayta xabar + mijoz tasdig\'i → accepted (navbat)', async () => {
    const id = uniq('ag_');
    await seedAgro(id);
    await report('agro', id);
    const l = await call('courierListAgroTasks', { list: 'active' }, A);
    assert.strictEqual(l.tasks.find((x) => x.id === id).deliveryFailedPending, true);
    await expectReason(resolve('agro', id, ADMIN, 'continue'), 'DECISION_NOT_YET');
    await pastDue('agro', id);
    await escalate();
    assert.strictEqual((await resolve('agro', id, ADMIN, 'continue')).status, 'pickup_in_delivery');
    const l2 = await call('courierListAgroTasks', { list: 'active' }, A);
    assert.ok(!('deliveryFailedPending' in l2.tasks.find((x) => x.id === id)), 'kutish yo\'q');
    await report('agro', id, A, 'other');
    const c = await custDecide('agro', id, C1);
    assert.strictEqual(c.status, 'accepted');
    const d = await get('agro', id);
    assert.strictEqual(d.pickupCourierId, '');
    assert.ok(!('arrivedAt' in d));
    assert.ok(!(await db.collection('courier_task_payouts').doc(`agro_${id}`).get()).exists);
    const st = (await db.collection('customer_delivery_stats').doc(C1).get()).data() || {};
    assert.ok(!(st.failedStrikesByModule && st.failedStrikesByModule.agro), '\'other\' sababida strike yo\'q');
  });

  // ═════════════ 5. YIG'ISH ════════════════════════════════════════════
  await check('yig\'ish: kelmasdan — DF_ARRIVE_FIRST; courierMarkCollectionArrived (tranzaksiya, takror idempotent); xabar → mijoz tasdig\'i → failed, ariza bo\'shaydi; yakunlash rad; admin YANGI vazifa ocha oladi', async () => {
    const id = uniq('ct_');
    await seedCollection(id);
    await expectReason(report('collection', id), 'DF_ARRIVE_FIRST');
    const a1 = await call('courierMarkCollectionArrived', { taskId: id, courierPhone: A }, A);
    assert.strictEqual(a1.ok, true);
    assert.strictEqual((await call('courierMarkCollectionArrived', { taskId: id, courierPhone: A }, A)).idempotent, true);
    assert.strictEqual((await get('collection', id)).status, 'collecting');
    // Aktiv vazifa bor — admin yangisini ocha olmaydi (avvalgidek).
    await assert.rejects(call('adminCreateCollectionTask', { adminPhone: ADMIN, submissionId: `sub_${id}`, courierPhone: B, items: [{ code: 'milk', qty: 5 }] }, ADMIN),
      (e) => /already in collection/.test(e.message));
    await report('collection', id);
    const c = await custDecide('collection', id, C1);
    assert.strictEqual(c.status, 'failed');
    const d = await get('collection', id);
    assert.strictEqual(d.status, 'failed');
    assert.strictEqual(d.failReason, 'customer_absent');
    const sub = (await db.collection('sell_submissions').doc(`sub_${id}`).get()).data();
    assert.strictEqual(sub.inCollection, false);
    assert.strictEqual(sub.collectionTaskId, id, 'bog\'lanish saqlanadi');
    assert.strictEqual(sub.collectionFailedTaskId, id);
    await assert.rejects(call('courierFinalizeCollection', { taskId: id, courierPhone: A, items: [{ code: 'milk', qty: 10 }], cashGiven: 0 }, A),
      (e) => /task not active/.test(e.message));
    await assert.rejects(call('courierMarkCollectionArrived', { taskId: id, courierPhone: A }, A));
    const n = await call('adminCreateCollectionTask', { adminPhone: ADMIN, submissionId: `sub_${id}`, courierPhone: B, items: [{ code: 'milk', qty: 5 }] }, ADMIN);
    assert.ok(n.taskId && n.taskId !== id);
    const sub2 = (await db.collection('sell_submissions').doc(`sub_${id}`).get()).data();
    assert.strictEqual(sub2.inCollection, true);
    assert.strictEqual(sub2.collectionTaskId, n.taskId);
  });

  await check('yig\'ish: admin ro\'yxatida ko\'rinadi, sotuvchida YO\'Q; admin \'failed\' muddatdan keyin', async () => {
    const id = uniq('ct_');
    await seedCollection(id);
    await call('courierMarkCollectionArrived', { taskId: id, courierPhone: A }, A);
    await report('collection', id, A, 'customer_refused');
    assert.ok((await call('listDeliveryFailedPending', {}, ADMIN)).items.some((x) => x.module === 'collection' && x.id === id));
    assert.ok(!(await call('listDeliveryFailedPending', {}, SELLER)).items.some((x) => x.module === 'collection'));
    await pastDue('collection', id);
    const r = await resolve('collection', id, ADMIN, 'failed');
    assert.strictEqual(r.status, 'failed');
    assert.strictEqual((await get('collection', id)).deliveryFailedResolution.by, 'admin');
  });

  await check('admin muddatni 30 daq qiladi → yangi xabar +30 daq (bitta sozlama, 9-qaror)', async () => {
    await call('adminSetCustomerConfirmation', { failedTimeoutMin: 30, reason: 'test muddat' }, ADMIN);
    const id = uniq('ag_');
    await seedAgro(id);
    const t0 = Date.now();
    await report('agro', id);
    const due = (await get('agro', id)).deliveryFailedDueAt.toMillis();
    assert.ok(Math.abs(due - (t0 + 30 * 60000)) < 5000, `30 daq: ${due - t0}`);
    const g = await call('adminGetCustomerConfirmation', {}, ADMIN);
    assert.ok(!('order' in g.modules), 'order — sozlama bosqichi yo\'q');
    await call('adminSetCustomerConfirmation', { failedTimeoutMin: 15, reason: 'qaytarish' }, ADMIN);
  });

  await check('sverka: Σdr == Σcr', async () => { await journalBalanced(); });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}
main().catch((e) => { console.error('FATAL', e); process.exit(1); });
