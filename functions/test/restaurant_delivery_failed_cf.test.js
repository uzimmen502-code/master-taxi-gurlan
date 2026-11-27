/**
 * «ЕТКАЗИЛМАДИ» — МИЖОЗ ТАСДИҒИ БИЛАН (ega qarori 2026-10-31: C-1, C-2, C-3, A-1).
 * HAQIQIY `functions/index.js` callable'lari va jadvali `.run()` orqali, Firestore Emulator, haqiqiy ledger.
 *
 *   firebase emulators:exec --only firestore --project demo-delivery-failed \
 *     "node functions/test/restaurant_delivery_failed_cf.test.js"
 *
 * Qulflanadi:
 *   - kuryer 'failed' YAKUNLAMAYDI (sozlama o'chiq bo'lsa ham — hamma mijoz uchun majburiy):
 *     holat va pul o'zgarmaydi, belgi + muddat (standart 15 daq) yoziladi; takror chaqiruv idempotent
 *   - mijoz tasdig'i → delivery_failed (2 % bir marta qaytadi, strike sababga qarab); takror idempotent
 *   - mijoz rad («Олмоқчиман») → yetkazish davom etadi, belgi/muddat o'chadi, kuryer yetkaza oladi
 *   - begona mijoz / noto'g'ri qadamda rad / eskirgan so'rov (requestedAtMs) — rad
 *   - restoran muddatgacha qaror qila olmaydi (DECISION_NOT_YET); begona — NOT_RESTAURANT_MEMBER
 *   - jadval: chegaradan oldin eskalatsiya yo'q, keyin bir marta; eskirgan maydon tozalanadi
 *   - restoran 'failed' / 'continue'; admin qarori audit bilan; parallel mijoz+restoran → bitta g'olib
 *   - admin muddatni o'zgartiradi (1..240), noto'g'ri qiymat va dispatcher rad, audit
 *   - sverka: Σdr == Σcr
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-delivery-failed';
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.CUSTOMER_CONFIRM_CACHE_MS = '0';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require('../index');
const admin = require('firebase-admin');
const ledger = require('../settlement_ledger');

const db = admin.firestore();

const ADMIN = '998909990010';
const DISPATCHER = '998909990011';
const OWNER = '998909990020'; // restoran egasi (a'zo)
const OTHER_OWNER = '998909990021'; // boshqa restoran a'zosi
const A = '998909990030'; // kuryer
const B = '998909990031'; // boshqa kuryer
const C1 = '998909990040'; // mijoz
const C2 = '998909990041'; // boshqa mijoz
const ACC = { [A]: 'accFAILCOURIER00000A', [B]: 'accFAILCOURIER00000B' };
const FEE = 1200;

const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, ctxOf(who));
const at = (ms) => admin.firestore.Timestamp.fromMillis(ms);

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
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
const pcBal = async (uid) => {
  const s = await db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(uid)).get();
  return s.exists ? Number(s.data().balance || 0) : 0;
};
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
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(DISPATCHER).set({ role: 'dispatcher' });
  await db.collection('users').doc(OWNER).set({ role: 'user', appLang: 'ru' });
  await db.collection('users').doc(OTHER_OWNER).set({ role: 'user' });
  await db.collection('users').doc(C1).set({ role: 'user', bonusBalance: 0, appLang: 'uz_Latn' });
  await db.collection('users').doc(C2).set({ role: 'user', bonusBalance: 0 });
  await seedCourier(A);
  await seedCourier(B);
  await db.collection('restaurants').doc('rest1').set({ status: 'approved', ownerUid: OWNER, name: 'R1' });
  await db.collection('restaurants').doc('rest1').collection('members').doc(OWNER).set({ role: 'owner' });
  await db.collection('restaurants').doc('rest2').set({ status: 'approved', ownerUid: OTHER_OWNER, name: 'R2' });
  await db.collection('restaurants').doc('rest2').collection('members').doc(OTHER_OWNER).set({ role: 'owner' });
}

let seq = 0;
const uniq = (p) => `${p}${(seq += 1)}`;
const orderRef = (id) => db.collection('orders').doc(id);
const order = async (id) => (await orderRef(id).get()).data() || {};
const eventsOf = async (id) => (await orderRef(id).collection('order_events').get()).docs.map((d) => d.data());
async function seedOrder(id, { customer = C1, courier = A, status = 'arrived', paymentMethod = 'cash' } = {}) {
  await orderRef(id).set({
    type: 'restaurant', restaurantId: 'rest1', restaurantStatus: status, status: 'in_delivery',
    fulfillmentStatus: status, userPhone: customer, courierId: courier, deliveryRouteId: `rt_${id}`,
    deliveryMode: 'ava_courier', deliveryFee: 6000, deliveryPaymentMethod: paymentMethod, foodPaymentMethod: 'prepay',
    itemsTotal: 60000, packagingTotal: 0, paymentStatus: 'paid', createdAt: at(1000),
    restaurantWalletUid: OWNER,
    avaFee: { amount: FEE, charged: true, version: 1, basis: 60000, rateBps: 200 },
  });
  await db.collection('delivery_routes').doc(`rt_${id}`).set({ courierId: courier, status: 'active', orders: [id], currentIndex: 0 });
}
const courierFail = (id, who = A, reason = 'customer_absent') => call('courierCompleteRestaurantDelivery', { orderId: id, outcome: 'failed', failReason: reason }, who);
const custDecide = (id, who, decision, extra = {}) => call('customerConfirmHandover', { module: 'restaurant', id, step: 'delivery_failed', ...(decision ? { decision } : {}), ...extra }, who);
const resolve = (id, who, decision) => call('restaurantResolveDeliveryFailed', { orderId: id, decision }, who);
const escalate = () => fns.escalateRestaurantDeliveryFailed.run({});
const pastDeadline = (id) => orderRef(id).update({
  deliveryFailedEscalateAt: at(Date.now() - 1000), 'awaitingCustomerConfirm.escalateAt': at(Date.now() - 1000),
});
const strikes = async (uid) => {
  const s = await db.collection('restaurant_customer_stats').doc(uid).get();
  return s.exists ? Number(s.data().strikes || 0) : 0;
};

async function main() {
  await reset();

  // ═════════════ 1. Kuryer so'rovi ═════════════════════════════════════
  await check('kuryer \'failed\' (sozlama YO\'Q) → yakunlanmaydi: holat/pul/strike o\'zgarmaydi, belgi + 15 daq muddat, hodisa', async () => {
    const id = uniq('f_');
    await seedOrder(id);
    const o0 = await pcBal(OWNER);
    const t0 = Date.now();
    const r = await courierFail(id);
    assert.strictEqual(r.ok, true);
    assert.strictEqual(r.awaitingCustomer, true);
    assert.strictEqual(r.step, 'delivery_failed');
    const d = await order(id);
    assert.strictEqual(d.restaurantStatus, 'arrived');
    assert.strictEqual(d.status, 'in_delivery');
    assert.strictEqual(d.awaitingCustomerConfirm.step, 'delivery_failed');
    assert.strictEqual(d.awaitingCustomerConfirm.failReason, 'customer_absent');
    assert.strictEqual(d.awaitingCustomerConfirm.courierId, A);
    assert.strictEqual(d.hasAwaitingCustomerConfirm, true);
    const dl = d.deliveryFailedEscalateAt.toMillis();
    assert.ok(dl >= t0 + 15 * 60000 - 2000 && dl <= Date.now() + 15 * 60000 + 2000, `muddat ${dl - t0}`);
    assert.strictEqual(d.awaitingCustomerConfirm.escalateAt.toMillis(), dl);
    assert.strictEqual(r.escalateAtMs, dl);
    assert.strictEqual(await pcBal(OWNER), o0, '2 % qaytmadi');
    assert.strictEqual(await strikes(C1), 0);
    assert.ok(!(await db.collection('wallet_idempotency').doc(`rest_complete_${id}`).get()).exists);
    const ev = await eventsOf(id);
    assert.strictEqual(ev.filter((e) => e.reason === 'delivery_failed_requested').length, 1);
  });

  await check('takror kuryer chaqiruvi va PARALLEL 3 ta → bitta so\'rov, muddat va sabab o\'zgarmaydi', async () => {
    const id = uniq('f_');
    await seedOrder(id);
    const rs = await Promise.all([courierFail(id), courierFail(id, A, 'other'), courierFail(id, A, 'courier_problem')]);
    for (const r of rs) assert.strictEqual(r.awaitingCustomer, true);
    const d1 = await order(id);
    const again = await courierFail(id, A, 'other');
    assert.strictEqual(again.escalateAtMs, d1.deliveryFailedEscalateAt.toMillis());
    const d2 = await order(id);
    assert.strictEqual(d2.awaitingCustomerConfirm.failReason, d1.awaitingCustomerConfirm.failReason);
    assert.strictEqual((await eventsOf(id)).filter((e) => e.reason === 'delivery_failed_requested').length, 1);
  });

  await check('boshqa kuryer \'failed\' — COURIER_ASSIGNMENT_CONFLICT yoki marshrut rad; ready holatda ORDER_NOT_PICKED', async () => {
    const id = uniq('f_');
    await seedOrder(id);
    await assert.rejects(courierFail(id, B));
    assert.ok(!(await order(id)).awaitingCustomerConfirm);
    const id2 = uniq('f_');
    await seedOrder(id2, { status: 'ready' });
    await assert.rejects(courierFail(id2), (e) => /ORDER_INVALID_TRANSITION|ORDER_NOT_PICKED/.test(JSON.stringify(e.details || {}) + e.message));
  });

  // ═════════════ 2. Mijoz ro'yxati ═════════════════════════════════════
  await check('getCustomerPendingConfirmations: sozlama o\'chiq bo\'lsa ham «yetkazilmadi» ko\'rinadi (canReject, failReason, lotin matn); begonaga yo\'q', async () => {
    const id = uniq('f_');
    await seedOrder(id);
    await courierFail(id, A, 'customer_refused');
    const res = await call('getCustomerPendingConfirmations', {}, C1);
    const it = res.items.find((x) => x.id === id);
    assert.ok(it, 'element bor');
    assert.strictEqual(it.step, 'delivery_failed');
    assert.strictEqual(it.canReject, true);
    assert.strictEqual(it.details.failReason, 'customer_refused');
    assert.ok(/Kuryer/.test(it.title), `lotin matn: ${it.title}`);
    assert.ok(!JSON.stringify(it).includes(A), 'kuryer telefoni yo\'q');
    const other = await call('getCustomerPendingConfirmations', {}, C2);
    assert.ok(!other.items.some((x) => x.id === id));
  });

  // ═════════════ 3. Mijoz tasdig'i ═════════════════════════════════════
  await check('mijoz tasdig\'i → delivery_failed, 2 % BIR marta qaytadi, strike (customer_absent); takror idempotent', async () => {
    const id = uniq('f_');
    await seedOrder(id);
    await courierFail(id);
    const o0 = await pcBal(OWNER);
    const s0 = await strikes(C1);
    const r = await custDecide(id, C1);
    assert.strictEqual(r.status, 'delivery_failed');
    const d = await order(id);
    assert.strictEqual(d.restaurantStatus, 'delivery_failed');
    assert.strictEqual(d.status, 'cancelled');
    assert.strictEqual(d.failReason, 'customer_absent');
    assert.ok(d.customerConfirmed && d.customerConfirmed.delivery_failed);
    assert.ok(!('awaitingCustomerConfirm' in d) && !('deliveryFailedEscalateAt' in d));
    assert.strictEqual(d.deliveryFailedResolution.by, 'customer');
    assert.strictEqual(d.deliveryFailedResolution.decision, 'failed');
    assert.strictEqual(await pcBal(OWNER), o0 + FEE);
    assert.strictEqual(await strikes(C1), s0 + 1);
    const again = await custDecide(id, C1);
    assert.strictEqual(again.idempotent, true);
    assert.strictEqual(await pcBal(OWNER), o0 + FEE, 'ikkinchi marta qaytmadi');
    const ev = await eventsOf(id);
    assert.ok(ev.some((e) => e.reason === 'customer_confirmed' && e.to === 'delivery_failed' && e.actor === 'customer'));
  });

  await check('courier_problem sababi bilan mijoz tasdig\'i → strike YO\'Q (avvalgi qoida)', async () => {
    const id = uniq('f_');
    await seedOrder(id, { customer: C2 });
    await courierFail(id, A, 'courier_problem');
    const s0 = await strikes(C2);
    await custDecide(id, C2);
    assert.strictEqual(await strikes(C2), s0);
  });

  await check('begona mijoz — NOT_YOUR_ORDER; noto\'g\'ri decision / \'received\' da reject — CONFIRM_ARGS_INVALID', async () => {
    const id = uniq('f_');
    await seedOrder(id);
    await courierFail(id);
    await expectReason(custDecide(id, C2), 'NOT_YOUR_ORDER', 'permission-denied');
    await expectReason(custDecide(id, C1, 'maybe'), 'CONFIRM_ARGS_INVALID', 'invalid-argument');
    await expectReason(call('customerConfirmHandover', { module: 'restaurant', id, step: 'received', decision: 'reject' }, C1), 'CONFIRM_ARGS_INVALID');
    assert.strictEqual((await order(id)).restaurantStatus, 'arrived');
  });

  // ═════════════ 4. Mijoz rad etadi («Олмоқчиман») ═════════════════════
  await check('mijoz rad → holat arrived qoladi, belgi/muddat o\'chadi, qaror izi; takror idempotent; kuryer keyin yetkazadi', async () => {
    const id = uniq('f_');
    await seedOrder(id);
    await courierFail(id);
    const o0 = await pcBal(OWNER);
    const r = await custDecide(id, C1, 'reject');
    assert.strictEqual(r.status, 'arrived');
    assert.strictEqual(r.decision, 'reject');
    let d = await order(id);
    assert.strictEqual(d.restaurantStatus, 'arrived');
    assert.ok(!('awaitingCustomerConfirm' in d) && !('hasAwaitingCustomerConfirm' in d) && !('deliveryFailedEscalateAt' in d));
    assert.strictEqual(d.deliveryFailedResolution.by, 'customer');
    assert.strictEqual(d.deliveryFailedResolution.decision, 'continue');
    assert.ok(d.customerRejected.delivery_failed);
    assert.strictEqual(await pcBal(OWNER), o0);
    const again = await custDecide(id, C1, 'reject');
    assert.strictEqual(again.idempotent, true);
    await expectReason(custDecide(id, C1), 'NOT_AWAITING');
    const del = await call('courierCompleteRestaurantDelivery', { orderId: id, outcome: 'delivered' }, A);
    assert.strictEqual(del.outcome, 'delivered');
    d = await order(id);
    assert.strictEqual(d.restaurantStatus, 'delivered');
    assert.ok((await eventsOf(id)).some((e) => e.reason === 'delivery_failed_rejected' && e.actor === 'customer'));
  });

  await check('eskirgan so\'rov (requestedAtMs boshqa) — STATE_CHANGED, belgi QOLADI', async () => {
    const id = uniq('f_');
    await seedOrder(id);
    await courierFail(id);
    const ms = (await order(id)).awaitingCustomerConfirm.requestedAt.toMillis();
    await expectReason(custDecide(id, C1, 'reject', { requestedAtMs: ms - 5000 }), 'STATE_CHANGED');
    assert.strictEqual((await order(id)).awaitingCustomerConfirm.step, 'delivery_failed');
    const ok = await custDecide(id, C1, 'reject', { requestedAtMs: ms });
    assert.strictEqual(ok.status, 'arrived');
  });

  await check('kutishda kuryer «yetkazdim» (sozlama o\'chiq) → delivered, «yetkazilmadi» belgisi va muddati o\'chadi', async () => {
    const id = uniq('f_');
    await seedOrder(id);
    await courierFail(id);
    const r = await call('courierCompleteRestaurantDelivery', { orderId: id, outcome: 'delivered' }, A);
    assert.strictEqual(r.outcome, 'delivered');
    const d = await order(id);
    assert.strictEqual(d.restaurantStatus, 'delivered');
    assert.ok(!('awaitingCustomerConfirm' in d) && !('deliveryFailedEscalateAt' in d) && !('deliveryFailedEscalatedAt' in d));
    await expectReason(custDecide(id, C1), 'NOT_AWAITING');
  });

  // ═════════════ 5. Restoran qarori va jadval ══════════════════════════
  await check('muddatgacha restoran qaror qila olmaydi (DECISION_NOT_YET); begona restoran va mijoz — NOT_RESTAURANT_MEMBER; noto\'g\'ri decision', async () => {
    const id = uniq('f_');
    await seedOrder(id);
    await courierFail(id);
    await expectReason(resolve(id, OWNER, 'failed'), 'DECISION_NOT_YET', 'failed-precondition');
    await expectReason(resolve(id, OTHER_OWNER, 'failed'), 'NOT_RESTAURANT_MEMBER', 'permission-denied');
    await expectReason(resolve(id, C1, 'failed'), 'NOT_RESTAURANT_MEMBER');
    await expectReason(resolve(id, OWNER, 'cancel'), 'RESOLVE_ARGS_INVALID', 'invalid-argument');
    assert.strictEqual((await order(id)).restaurantStatus, 'arrived');
  });

  await check('jadval: muddat 1 s keyin — eskalatsiya YO\'Q; o\'tgach — bir marta (escalatedAt + hodisa), ikkinchi ishga tushish hech narsa qilmaydi', async () => {
    const id = uniq('f_');
    await seedOrder(id);
    await courierFail(id);
    await orderRef(id).update({ deliveryFailedEscalateAt: at(Date.now() + 1500), 'awaitingCustomerConfirm.escalateAt': at(Date.now() + 1500) });
    await escalate();
    assert.ok(!('deliveryFailedEscalatedAt' in (await order(id))), 'chegaradan oldin yo\'q');
    await pastDeadline(id);
    await escalate();
    const d = await order(id);
    assert.ok(d.deliveryFailedEscalatedAt, 'eskalatsiya bo\'ldi');
    assert.ok(!('deliveryFailedEscalateAt' in d), 'muddat maydoni o\'chdi (qayta so\'ralmaydi)');
    assert.strictEqual(d.awaitingCustomerConfirm.step, 'delivery_failed', 'mijoz hali ham tasdiqlay oladi');
    await escalate();
    const ev = await eventsOf(id);
    assert.strictEqual(ev.filter((e) => e.reason === 'delivery_failed_escalated').length, 1);
    const news = (await db.collection('admin_news').where('targetUserId', '==', OWNER).get()).docs.map((x) => x.data())
      .filter((n) => n.orderId === id);
    assert.strictEqual(news.length, 1, 'restoran a\'zosiga BIR xabar');
    assert.strictEqual(news[0].title, 'Нужно решение по заказу', 'egasi tili ru');
  });

  await check('jadval: buyurtma boshqa yo\'l bilan yakunlangan bo\'lsa eskirgan muddat maydoni tozalanadi', async () => {
    const id = uniq('f_');
    await seedOrder(id);
    await courierFail(id);
    await orderRef(id).update({ restaurantStatus: 'rejected', deliveryFailedEscalateAt: at(Date.now() - 1000) });
    await escalate();
    const d = await order(id);
    assert.ok(!('deliveryFailedEscalateAt' in d));
    assert.ok(!('deliveryFailedEscalatedAt' in d));
  });

  await check('muddatdan keyin restoran \'failed\' → delivery_failed, 2 % qaytadi, qaror izi; takror idempotent; mijoz endi NOT_AWAITING', async () => {
    const id = uniq('f_');
    await seedOrder(id);
    await courierFail(id);
    await pastDeadline(id);
    await escalate();
    const o0 = await pcBal(OWNER);
    const r = await resolve(id, OWNER, 'failed');
    assert.strictEqual(r.status, 'delivery_failed');
    const d = await order(id);
    assert.strictEqual(d.restaurantStatus, 'delivery_failed');
    assert.strictEqual(d.deliveryFailedResolution.by, 'restaurant');
    assert.strictEqual(d.deliveryFailedResolution.decision, 'failed');
    assert.ok(!('awaitingCustomerConfirm' in d) && !('deliveryFailedEscalatedAt' in d));
    assert.strictEqual(await pcBal(OWNER), o0 + FEE);
    assert.strictEqual((await resolve(id, OWNER, 'failed')).idempotent, true);
    assert.strictEqual(await pcBal(OWNER), o0 + FEE);
    await expectReason(custDecide(id, C1), 'NOT_AWAITING');
    await expectReason(resolve(id, OWNER, 'continue'), 'NOT_AWAITING_DECISION');
    const ev = await eventsOf(id);
    assert.ok(ev.some((e) => e.actor === 'restaurant' && e.to === 'delivery_failed' && /^delivery_failed_decided:/.test(e.reason)));
  });

  await check('muddat o\'tgan (jadval hali ishlamagan) — restoran baribir qaror qila oladi; \'continue\' → arrived, kuryer davom etadi', async () => {
    const id = uniq('f_');
    await seedOrder(id);
    await courierFail(id);
    await pastDeadline(id);
    const r = await resolve(id, OWNER, 'continue');
    assert.strictEqual(r.status, 'arrived');
    const d = await order(id);
    assert.strictEqual(d.restaurantStatus, 'arrived');
    assert.strictEqual(d.deliveryFailedResolution.by, 'restaurant');
    assert.ok(!('awaitingCustomerConfirm' in d) && !('deliveryFailedEscalateAt' in d));
    assert.ok(!(d.customerRejected && d.customerRejected.delivery_failed), 'mijoz rad etmadi');
    assert.strictEqual((await resolve(id, OWNER, 'continue')).idempotent, true);
    await escalate();
    assert.ok(!('deliveryFailedEscalatedAt' in (await order(id))));
  });

  await check('admin qarori (zaxira) → admin_audit yozuvi; dispatcher — NOT_RESTAURANT_MEMBER', async () => {
    const id = uniq('f_');
    await seedOrder(id);
    await courierFail(id);
    await pastDeadline(id);
    await expectReason(resolve(id, DISPATCHER, 'failed'), 'NOT_RESTAURANT_MEMBER');
    await resolve(id, ADMIN, 'failed');
    const d = await order(id);
    assert.strictEqual(d.deliveryFailedResolution.by, 'admin');
    const a = await db.collection('admin_audit').where('kind', '==', 'restaurant_delivery_failed_decision').get();
    assert.ok(a.docs.some((x) => x.data().target === `orders/${id}` && x.data().actor === ADMIN));
  });

  await check('PARALLEL: mijoz tasdig\'i + restoran \'failed\' + restoran \'continue\' → bitta yakun, 2 % BIR marta', async () => {
    const id = uniq('f_');
    await seedOrder(id);
    await courierFail(id);
    await pastDeadline(id);
    const o0 = await pcBal(OWNER);
    const rs = await Promise.allSettled([custDecide(id, C1), resolve(id, OWNER, 'failed'), resolve(id, OWNER, 'continue')]);
    const d = await order(id);
    const refunded = (await pcBal(OWNER)) - o0;
    if (d.restaurantStatus === 'delivery_failed') {
      assert.strictEqual(refunded, FEE, 'bir marta');
    } else {
      assert.strictEqual(d.restaurantStatus, 'arrived');
      assert.strictEqual(refunded, 0);
    }
    assert.ok(rs.some((x) => x.status === 'fulfilled'));
    const finals = (await eventsOf(id)).filter((e) => e.to === 'delivery_failed' || e.reason === 'delivery_failed_rejected');
    assert.strictEqual(finals.length, 1, `bitta yakun hodisasi: ${finals.map((e) => e.reason)}`);
  });

  // ═════════════ 6. Admin sozlamasi (muddat) ═══════════════════════════
  await check('admin muddatni 30 daq qiladi → audit; yangi so\'rov +30 daq; noto\'g\'ri (0, 241, 1.5, "15") va dispatcher rad', async () => {
    for (const bad of [0, 241, 1.5, '15']) {
      await expectReason(call('adminSetCustomerConfirmation', { failedTimeoutMin: bad, reason: 'test muddat' }, ADMIN), 'CC_FAILED_TIMEOUT_INVALID');
    }
    await assert.rejects(call('adminSetCustomerConfirmation', { failedTimeoutMin: 30, reason: 'test muddat' }, DISPATCHER));
    const r = await call('adminSetCustomerConfirmation', { failedTimeoutMin: 30, reason: 'test muddat' }, ADMIN);
    assert.strictEqual(r.failedTimeoutMin, 30);
    const g = await call('adminGetCustomerConfirmation', {}, ADMIN);
    assert.strictEqual(g.failedTimeoutMin, 30);
    assert.strictEqual(g.modules.restaurant, 'off', 'boshqa sozlama o\'zgarmadi');
    const again = await call('adminSetCustomerConfirmation', { failedTimeoutMin: 30, reason: 'test muddat' }, ADMIN);
    assert.strictEqual(again.unchanged, true);
    const audits = await db.collection('admin_audit').where('kind', '==', 'customer_confirm_config').get();
    assert.strictEqual(audits.size, 1);
    assert.strictEqual(audits.docs[0].data().detail.failedTimeoutMinNew, 30);
    const id = uniq('f_');
    await seedOrder(id);
    const t0 = Date.now();
    await courierFail(id);
    const dl = (await order(id)).deliveryFailedEscalateAt.toMillis();
    assert.ok(Math.abs(dl - (t0 + 30 * 60000)) < 5000, `30 daq: ${dl - t0}`);
    // Chegara: 1 va 240 qabul qilinadi.
    assert.strictEqual((await call('adminSetCustomerConfirmation', { failedTimeoutMin: 1, reason: 'chegara' }, ADMIN)).failedTimeoutMin, 1);
    assert.strictEqual((await call('adminSetCustomerConfirmation', { failedTimeoutMin: 240, reason: 'chegara' }, ADMIN)).failedTimeoutMin, 240);
    // Modul bosqichini o'zgartirish muddatni saqlaydi.
    await call('adminSetCustomerConfirmation', { module: 'carpet', stage: 'internal', reason: 'bosqich' }, ADMIN);
    assert.strictEqual((await call('adminGetCustomerConfirmation', {}, ADMIN)).failedTimeoutMin, 240);
    await call('adminSetCustomerConfirmation', { module: 'carpet', stage: 'off', failedTimeoutMin: 15, reason: 'qaytarish' }, ADMIN);
  });

  await check('sverka: Σdr == Σcr', async () => { await journalBalanced(); });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}
main().catch((e) => { console.error('FATAL', e); process.exit(1); });
