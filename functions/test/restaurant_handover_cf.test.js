/**
 * TOPSHIRISH — boshqa kuryerga / restoranga (ega qarorlari 2026-10-31: C-4..C-7, A-2, A-3).
 * HAQIQIY `functions/index.js` callable'lari va jadvali `.run()` orqali, Firestore Emulator, haqiqiy ledger.
 *
 *   firebase emulators:exec --only firestore --project demo-handover \
 *     "node functions/test/restaurant_handover_cf.test.js"
 *
 * Qulflanadi:
 *   - olishdan oldin qo'yib yuborish: kuryer/marshrut o'chadi, 30 daq qidiruv, boshqa kuryer oladi
 *   - olgandan keyin kod: idempotent boshlash; noto'g'ri kod / GPS yo'q / o'zi — rad; to'g'ri kod → B,
 *     marshrutlar, custody_events (from/to/joy/dalil), bo'lak masofasi; takror idempotent; parallel — bitta g'olib
 *   - yetkazilganda ulush: hamyon — har kuryerga masofa ulushi (butun so'm, jami = haq); naqd — qayd, pul yo'q
 *   - vykup (kuryerga) va «yetkazilmadi» kutilayotganda — rad
 *   - restoranga qaytarish: kod, begona restoran rad, holat ready + yangi olish kodi, vykup belgisi tiklanadi
 *   - 30 daq jadval: chegaradan oldin yo'q, keyin bekor + 2 % bir marta; olingan buyurtmada maydon tozalanadi
 *   - bekor qilish, muddati o'tgan kod, kuryer boshiga urinish chegarasi
 *   - sverka: Σdr == Σcr
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-handover';
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.CUSTOMER_CONFIRM_CACHE_MS = '0';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require('../index');
const admin = require('firebase-admin');
const ledger = require('../settlement_ledger');
const ro = require('../restaurant_orders');

const db = admin.firestore();

const OWNER = '998909991020';
const OTHER_OWNER = '998909991021';
const A = '998909991030';
const B = '998909991031';
const C = '998909991032';
const CUST = '998909991040';
const ACC = { [A]: 'accHANDOVERCOURIERA', [B]: 'accHANDOVERCOURIERB', [C]: 'accHANDOVERCOURIERC' };
const FEE = 1200;
const R_PT = { lat: 41.8406, lng: 60.3917 };
const MID = { lat: 41.8496, lng: 60.3917 }; // ~1 km shimolda
const C_PT = { lat: 41.8586, lng: 60.3917 }; // yana ~1 km

const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, ctxOf(who));
const at = (ms) => admin.firestore.Timestamp.fromMillis(ms);

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function expectCode(promise, code, httpsCode) {
  await assert.rejects(promise, (e) => {
    const got = (e.details && (e.details.code || e.details.reason)) || e.message;
    assert.strictEqual(got, code, `kod ${got} (${e.code}): ${e.message}`);
    if (httpsCode) assert.strictEqual(e.code, httpsCode, `http ${e.code}`);
    return true;
  });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
async function topUp(uid, amount, key) {
  await ledger.postEntry(db, {
    idempotencyKey: `topup:${uid}:${key}`, kind: 'test_topup',
    legs: [{ account: 'admin_clearing', dr: amount }, { account: ledger.passengerCreditAccount(uid), cr: amount }],
  });
}
const pcBal = async (uid) => {
  const s = await db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(uid)).get();
  return s.exists ? Number(s.data().balance || 0) : 0;
};
const bonus = async (uid) => Number(((await db.collection('users').doc(uid).get()).data() || {}).bonusBalance || 0);
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
  await db.collection('users').doc(OWNER).set({ role: 'user' });
  await db.collection('users').doc(OTHER_OWNER).set({ role: 'user' });
  await db.collection('users').doc(CUST).set({ role: 'user', bonusBalance: 0 });
  for (const c of [A, B, C]) await seedCourier(c);
  await db.collection('restaurants').doc('rest1').set({ status: 'approved', ownerUid: OWNER, name: 'R1' });
  await db.collection('restaurants').doc('rest1').collection('members').doc(OWNER).set({ role: 'owner' });
  await db.collection('restaurants').doc('rest2').set({ status: 'approved', ownerUid: OTHER_OWNER, name: 'R2' });
  await db.collection('restaurants').doc('rest2').collection('members').doc(OTHER_OWNER).set({ role: 'owner' });
}

let seq = 0;
const uniq = (p) => `${p}${(seq += 1)}`;
const orderRef = (id) => db.collection('orders').doc(id);
const order = async (id) => (await orderRef(id).get()).data() || {};
const route = async (rid) => (await db.collection('delivery_routes').doc(rid).get()).data() || {};
const eventsOf = async (id) => (await orderRef(id).collection('order_events').get()).docs.map((d) => d.data());
const secret = async (id) => (await orderRef(id).collection('private').doc('secrets').get()).data() || {};
async function seedOrder(id, {
  status = 'picked', courier = A, pay = 'wallet', food = 'prepay', paymentStatus = 'paid', extra = {},
} = {}) {
  await orderRef(id).set({
    type: 'restaurant', restaurantId: 'rest1', restaurantStatus: status, status: 'in_delivery', fulfillmentStatus: status,
    userPhone: CUST, courierId: courier, deliveryRouteId: courier ? `rt_${id}` : null,
    deliveryMode: 'ava_courier', deliveryFee: 6000, deliveryPaymentMethod: pay, foodPaymentMethod: food,
    itemsTotal: 60000, packagingTotal: 0, paymentStatus, createdAt: at(1000),
    restaurantLat: R_PT.lat, restaurantLng: R_PT.lng, lat: C_PT.lat, lng: C_PT.lng,
    restaurantWalletUid: OWNER, avaFee: { amount: FEE, charged: true, version: 1, basis: 60000, rateBps: 200 },
    ...extra,
  });
  await orderRef(id).collection('private').doc('secrets').set({ pickupCode: '1234', pickupAttempts: 0 });
  if (courier) await db.collection('delivery_routes').doc(`rt_${id}`).set({ courierId: courier, status: 'active', orders: [id], currentIndex: 0 });
}
const start = (id, target, who = A, loc) => call('courierStartRestaurantHandover', { orderId: id, target, ...(loc || {}) }, who);
const accept = (code, who, loc = MID) => call('courierAcceptRestaurantHandover', { code, ...(loc ? { lat: loc.lat, lng: loc.lng } : {}) }, who);
const resetAttempts = () => Promise.all([A, B, C].map((c) => db.collection('courier_handover_attempts').doc(c).delete()));

async function main() {
  await reset();

  // ═════════════ 0. Sof: ulush ════════════════════════════════════════
  await check('computeCourierShares: butun so\'m, jami = haq, qoldiq oxirgiga; takror kuryer qo\'shiladi; 0 masofa → oxirgiga', () => {
    const s = ro.computeCourierShares(10001, [{ courierId: 'a', meters: 1000 }, { courierId: 'b', meters: 2000 }, { courierId: 'a', meters: 500 }]);
    assert.deepStrictEqual(s.map((x) => [x.courierId, x.meters]), [['a', 1500], ['b', 2000]]);
    assert.strictEqual(s.reduce((x, y) => x + y.amount, 0), 10001);
    // Oxirgi bo'lak — 'a' (qaytib olgan): qoldiq unga, 'b' — floor.
    assert.strictEqual(s.find((x) => x.courierId === 'b').amount, Math.floor(10001 * 2000 / 3500));
    assert.strictEqual(s.find((x) => x.courierId === 'a').amount, 10001 - Math.floor(10001 * 2000 / 3500));
    const z = ro.computeCourierShares(6000, [{ courierId: 'a', meters: 0 }, { courierId: 'b', meters: 0 }]);
    assert.deepStrictEqual(z.map((x) => x.amount), [0, 6000]);
    assert.deepStrictEqual(ro.computeCourierShares(6000, []), []);
    for (const x of ro.computeCourierShares(7, [{ courierId: 'a', meters: 1 }, { courierId: 'b', meters: 1 }, { courierId: 'c', meters: 1 }])) {
      assert.ok(Number.isInteger(x.amount));
    }
  });

  // ═════════════ 1. Olishdan oldin — qo'yib yuborish ═══════════════════
  await check('ready (olinmagan): qo\'yib yuborish → courierId null, marshrutdan olinadi, 30 daq qidiruv; B oladi → qidiruv tugaydi', async () => {
    const id = uniq('pre_');
    await seedOrder(id, { status: 'ready', paymentStatus: 'paid' });
    const t0 = Date.now();
    const r = await start(id, 'seller');
    assert.strictEqual(r.released, true);
    let d = await order(id);
    assert.strictEqual(d.courierId, null);
    assert.ok(!('deliveryRouteId' in d));
    const until = d.returnSearchUntil.toMillis();
    assert.ok(Math.abs(until - (t0 + 30 * 60000)) < 5000, `30 daq: ${until - t0}`);
    assert.deepStrictEqual((await route(`rt_${id}`)).orders, []);
    assert.ok((await eventsOf(id)).some((e) => e.reason === 'courier_released'));
    await call('courierClaimRestaurantOrder', { orderId: id }, B);
    d = await order(id);
    assert.strictEqual(d.courierId, B);
    assert.ok(!('returnSearchUntil' in d), 'kuryer topildi — qidiruv tugadi');
  });

  // ═════════════ 2. Kuryerdan kuryerga ═════════════════════════════════
  let idWallet;
  await check('picked: boshlash → 6 xonali kod, kutish belgisi; takror — o\'sha kod; begona kuryer boshlay olmaydi', async () => {
    idWallet = uniq('w_');
    await seedOrder(idWallet);
    const r = await start(idWallet, 'courier');
    assert.ok(/^\d{6}$/.test(r.code));
    const again = await start(idWallet, 'courier');
    assert.strictEqual(again.code, r.code);
    assert.strictEqual(again.idempotent, true);
    const d = await order(idWallet);
    assert.strictEqual(d.handover.status, 'pending');
    assert.strictEqual(d.handover.target, 'courier');
    assert.ok(!JSON.stringify(d).includes(r.code), 'kod buyurtma hujjatida yo\'q (faqat private)');
    assert.ok((await db.collection('courier_handover_codes').doc(r.code).get()).exists);
    await assert.rejects(start(idWallet, 'courier', B));
  });

  await check('qabul: noto\'g\'ri kod / GPS yo\'q / o\'zi — rad; to\'g\'ri → B, marshrutlar, custody hodisasi, bo\'lak masofasi; takror idempotent', async () => {
    const { code } = await start(idWallet, 'courier');
    await expectCode(accept('000000', B), 'HANDOVER_CODE_MISMATCH');
    await expectCode(accept(code, B, null), 'HANDOVER_LOCATION_REQUIRED', 'invalid-argument');
    await expectCode(accept('12ab', B), 'HANDOVER_CODE_INVALID');
    await expectCode(accept(code, A), 'HANDOVER_SAME_COURIER');
    const r = await accept(code, B);
    assert.strictEqual(r.orderId, idWallet);
    const d = await order(idWallet);
    assert.strictEqual(d.courierId, B);
    assert.strictEqual(d.restaurantStatus, 'picked');
    assert.ok(!('handover' in d));
    assert.strictEqual(d.courierLegs.length, 1);
    assert.strictEqual(d.courierLegs[0].courierId, A);
    assert.ok(d.courierLegs[0].meters > 900 && d.courierLegs[0].meters < 1100, `~1 km: ${d.courierLegs[0].meters}`);
    assert.deepStrictEqual((await route(`rt_${idWallet}`)).orders, [], 'A marshrutidan olindi');
    const bRoute = await route(d.deliveryRouteId);
    assert.strictEqual(bRoute.courierId, B);
    assert.ok(bRoute.orders.includes(idWallet));
    const ev = (await db.collection('custody_events').where('orderId', '==', idWallet).get()).docs.map((x) => x.data());
    assert.strictEqual(ev.length, 1);
    assert.deepStrictEqual(ev[0].from, { kind: 'courier', id: A });
    assert.deepStrictEqual(ev[0].to, { kind: 'courier', id: B });
    assert.strictEqual(ev[0].kind, 'handover');
    assert.strictEqual(ev[0].orderType, 'restaurant');
    assert.strictEqual(ev[0].location.lat, MID.lat);
    assert.strictEqual(ev[0].proof.codeVerified, true);
    assert.ok(ev[0].timestamp && ev[0].createdBy === B && ev[0].shipmentId === null && ev[0].deliversShipment === false);
    assert.ok(!(await db.collection('courier_handover_codes').doc(code).get()).exists, 'kod o\'chdi');
    await expectCode(accept(code, C), 'HANDOVER_CODE_MISMATCH');
    await assert.rejects(start(idWallet, 'courier', A), 'A endi topshira olmaydi (marshrutida emas)');
  });

  await check('yetkazildi (hamyon): haq A va B ga masofa ulushi bo\'yicha, jami = 6000, mijozdan 6000; jurnal muvozanatli', async () => {
    await topUp(CUST, 20000, idWallet);
    const c0 = await pcBal(CUST);
    const a0 = await pcBal(A);
    const b0 = await pcBal(B);
    await call('courierArriveRestaurantOrder', { orderId: idWallet }, B);
    const r = await call('courierCompleteRestaurantDelivery', { orderId: idWallet, outcome: 'delivered' }, B);
    assert.strictEqual(r.outcome, 'delivered');
    assert.strictEqual(r.walletPaid, 6000);
    assert.strictEqual(r.payoutSettlement, 'wallet_split');
    const d = await order(idWallet);
    const sa = d.payoutShares.find((x) => x.courierId === A).amount;
    const sb = d.payoutShares.find((x) => x.courierId === B).amount;
    assert.strictEqual(sa + sb, 6000);
    assert.ok(sa > 2500 && sa < 3500, `teng-ga yaqin: ${sa}`);
    assert.strictEqual(await pcBal(CUST), c0 - 6000);
    assert.strictEqual(await pcBal(A), a0 + sa);
    assert.strictEqual(await pcBal(B), b0 + sb);
    assert.strictEqual(await bonus(A), sa, 'ko\'zgu bonusBalance');
    assert.strictEqual(await bonus(B), sb);
    await journalBalanced();
    const again = await call('courierCompleteRestaurantDelivery', { orderId: idWallet, outcome: 'delivered' }, B);
    assert.strictEqual(again.idempotent, true);
    assert.strictEqual(await pcBal(A), a0 + sa, 'takror ikki marta to\'lamaydi');
  });

  await check('yetkazildi (naqd): ulush qayd etiladi (cash_unsettled), hamyonlar o\'zgarmaydi', async () => {
    const id = uniq('c_');
    await seedOrder(id, { pay: 'cash' });
    const { code } = await start(id, 'courier');
    await accept(code, B);
    const a0 = await pcBal(A);
    await call('courierArriveRestaurantOrder', { orderId: id }, B);
    const r = await call('courierCompleteRestaurantDelivery', { orderId: id, outcome: 'delivered' }, B);
    assert.strictEqual(r.payoutSettlement, 'cash_unsettled');
    assert.strictEqual(r.cashCollected, 6000);
    assert.strictEqual(await pcBal(A), a0);
    assert.strictEqual((await order(id)).payoutShares.reduce((x, y) => x + y.amount, 0), 6000);
  });

  await check('PARALLEL: B va C bir kod bilan → bitta g\'olib, bitta custody hodisasi', async () => {
    await resetAttempts();
    const id = uniq('par_');
    await seedOrder(id);
    const { code } = await start(id, 'courier');
    const rs = await Promise.allSettled([accept(code, B), accept(code, C)]);
    assert.strictEqual(rs.filter((x) => x.status === 'fulfilled').length, 1, JSON.stringify(rs.map((x) => x.status)));
    const d = await order(id);
    assert.ok([B, C].includes(d.courierId));
    const ev = await db.collection('custody_events').where('orderId', '==', id).get();
    assert.strictEqual(ev.size, 1);
  });

  await check('vykup buyurtmasini kuryerga — HANDOVER_BUYOUT_UNSUPPORTED; «yetkazilmadi» kutilayotganda — HANDOVER_BLOCKED_FAILED_PENDING; ready → seller emas courier ham qo\'yib yuboradi', async () => {
    const id = uniq('bo_');
    await seedOrder(id, { food: 'cash_buyout', pay: 'cash', extra: { paidBy: 'courier_buyout', buyoutAmount: 60000 } });
    await expectCode(start(id, 'courier'), 'HANDOVER_BUYOUT_UNSUPPORTED');
    const id2 = uniq('fp_');
    await seedOrder(id2, { status: 'arrived' });
    await call('courierCompleteRestaurantDelivery', { orderId: id2, outcome: 'failed', failReason: 'customer_absent' }, A);
    await expectCode(start(id2, 'courier'), 'HANDOVER_BLOCKED_FAILED_PENDING');
    await expectCode(start(id2, 'x'), 'HANDOVER_ARGS_INVALID', 'invalid-argument');
  });

  await check('bekor qilish: kod o\'chadi, B ololmaydi; muddati o\'tgan kod — rad', async () => {
    await resetAttempts();
    const id = uniq('cn_');
    await seedOrder(id);
    const { code } = await start(id, 'courier');
    await call('courierCancelRestaurantHandover', { orderId: id }, A);
    assert.ok(!('handover' in (await order(id))));
    await expectCode(accept(code, B), 'HANDOVER_CODE_MISMATCH');
    const r2 = await start(id, 'courier');
    await db.collection('courier_handover_codes').doc(r2.code).update({ expiresAt: at(Date.now() - 1000) });
    await orderRef(id).update({ 'handover.expiresAt': at(Date.now() - 1000) });
    await expectCode(accept(r2.code, B), 'HANDOVER_CODE_MISMATCH');
    assert.strictEqual((await order(id)).courierId, A);
  });

  await check('kuryer boshiga urinish chegarasi: 10 ta noto\'g\'ri → 11-si HANDOVER_TOO_MANY_ATTEMPTS', async () => {
    await resetAttempts();
    for (let i = 0; i < 10; i += 1) await expectCode(accept(String(100000 + i), C), 'HANDOVER_CODE_MISMATCH');
    await expectCode(accept('100099', C), 'HANDOVER_TOO_MANY_ATTEMPTS', 'resource-exhausted');
  });

  // ═════════════ 3. Restoranga qaytarish ═══════════════════════════════
  await check('restoranga: kod; begona restoran rad; noto\'g\'ri kod (qolgan urinish); to\'g\'ri → ready, yangi olish kodi, kuryer yo\'q, vykup belgisi tiklanadi, custody; takror idempotent', async () => {
    const id = uniq('ret_');
    await seedOrder(id, { status: 'arrived', food: 'cash_buyout', pay: 'cash', extra: { paidBy: 'courier_buyout', buyoutAmount: 60000 } });
    const { code } = await start(id, 'seller');
    await expectCode(call('restaurantAcceptReturn', { orderId: id, code }, OTHER_OWNER), 'NOT_RESTAURANT_MEMBER', 'permission-denied');
    await assert.rejects(call('restaurantAcceptReturn', { orderId: id, code: code === '000000' ? '111111' : '000000' }, OWNER), (e) => {
      assert.strictEqual(e.details.code, 'HANDOVER_CODE_MISMATCH');
      assert.strictEqual(e.details.attemptsLeft, 4);
      return true;
    });
    const t0 = Date.now();
    const r = await call('restaurantAcceptReturn', { orderId: id, code }, OWNER);
    assert.strictEqual(r.buyoutReturnDue, 60000);
    const d = await order(id);
    assert.strictEqual(d.restaurantStatus, 'ready');
    assert.strictEqual(d.courierId, null);
    assert.strictEqual(d.paymentStatus, 'unpaid', 'yangi kuryer qayta vykup qiladi');
    assert.ok(Math.abs(d.returnSearchUntil.toMillis() - (t0 + 30 * 60000)) < 5000);
    assert.ok(d.courierLegs[0].returned === true);
    const sec = await secret(id);
    assert.ok(/^\d{4}$/.test(sec.pickupCode) && sec.pickupAttempts === 0);
    assert.ok(!sec.handoverCode);
    const ev = (await db.collection('custody_events').where('orderId', '==', id).get()).docs.map((x) => x.data());
    assert.strictEqual(ev.length, 1);
    assert.strictEqual(ev[0].kind, 'return_to_seller');
    assert.deepStrictEqual(ev[0].to, { kind: 'restaurant', id: 'rest1' });
    assert.strictEqual(ev[0].meta.buyoutReturnDue, 60000);
    assert.strictEqual((await call('restaurantAcceptReturn', { orderId: id, code }, OWNER)).idempotent, true);
    assert.deepStrictEqual((await route(`rt_${id}`)).orders, []);
  });

  await check('qaytarilgan buyurtmani yangi kuryer oladi va yangi kod bilan olib ketadi', async () => {
    const id = uniq('ret2_');
    await seedOrder(id, { status: 'picked' });
    const { code } = await start(id, 'seller');
    await call('restaurantAcceptReturn', { orderId: id, code }, OWNER);
    await call('courierClaimRestaurantOrder', { orderId: id }, C);
    await call('courierPickupRestaurantOrder', { orderId: id, pickupCode: (await secret(id)).pickupCode }, C);
    const d = await order(id);
    assert.strictEqual(d.restaurantStatus, 'picked');
    assert.strictEqual(d.courierId, C);
    assert.ok(!('returnSearchUntil' in d));
  });

  // ═════════════ 4. 30 daqiqa jadvali ══════════════════════════════════
  await check('jadval: muddat kelajakda — o\'zgarmaydi; o\'tgach — bekor (rejected, no_courier_after_return), 2 % BIR marta; takror — hech narsa', async () => {
    const id = uniq('exp_');
    await seedOrder(id, { status: 'picked' });
    const { code } = await start(id, 'seller');
    await call('restaurantAcceptReturn', { orderId: id, code }, OWNER);
    await orderRef(id).update({ returnSearchUntil: at(Date.now() + 60000) });
    await fns.expireReturnedRestaurantOrders.run({});
    assert.strictEqual((await order(id)).restaurantStatus, 'ready');
    await orderRef(id).update({ returnSearchUntil: at(Date.now() - 1000) });
    const o0 = await pcBal(OWNER);
    await fns.expireReturnedRestaurantOrders.run({});
    const d = await order(id);
    assert.strictEqual(d.restaurantStatus, 'rejected');
    assert.strictEqual(d.rejectReason, 'no_courier_after_return');
    assert.strictEqual(d.rejectedBy, 'system');
    assert.ok(!('returnSearchUntil' in d));
    assert.strictEqual(await pcBal(OWNER), o0 + FEE);
    await fns.expireReturnedRestaurantOrders.run({});
    assert.strictEqual(await pcBal(OWNER), o0 + FEE, 'ikki marta qaytmaydi');
    const news = (await db.collection('admin_news').where('targetUserId', '==', CUST).get()).docs.filter((x) => x.data().orderId === id);
    assert.strictEqual(news.length, 1, 'mijozga bitta xabar');
  });

  await check('jadval: kuryer olgan buyurtmada eskirgan maydon tozalanadi, bekor bo\'lmaydi', async () => {
    const id = uniq('st_');
    await seedOrder(id, { status: 'ready', extra: { returnSearchUntil: at(Date.now() - 1000) } });
    await fns.expireReturnedRestaurantOrders.run({});
    const d = await order(id);
    assert.strictEqual(d.restaurantStatus, 'ready');
    assert.ok(!('returnSearchUntil' in d));
  });

  await check('sverka: Σdr == Σcr', async () => { await journalBalanced(); });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}
main().catch((e) => { console.error('FATAL', e); process.exit(1); });
