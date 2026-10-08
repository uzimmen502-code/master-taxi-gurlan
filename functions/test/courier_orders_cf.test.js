/**
 * Kuryer buyurtma callable'lari — BIRLASHTIRILGAN versiya (2026-10-08):
 * huquq + marshrut egaligi (`courier_auth.js`) + tranzaksiyali, idempotent
 * `courierSubmitPayment` (parallel `fix/courier-order-authz` ishidan) +
 * «kuryer ≠ mijoz» (ega qarori 2026-10-08).
 * HAQIQIY `functions/index.js` callable'lari `.run()` orqali, Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-courier-orders \
 *     "node functions/test/courier_orders_cf.test.js"
 *
 * Qulflanadi:
 *   - capability'siz foydalanuvchi va begona kuryer pulga tegolmaydi
 *   - marshrut eskirgan / ikki marshrutda: `COURIER_ASSIGNMENT_CONFLICT`
 *   - kuryer o'zi mijoz bo'lgan buyurtma: `COURIER_OWN_ORDER`, marshrutga
 *     ham olinmaydi; yig'ib olish vazifasi ham
 *   - suspended kuryer qo'lidagini tugatadi
 *   - `courierListReadyOrders`: faqat ishlaydigan kuryer, faqat id/MFY/
 *     koordinata (telefon, ism, manzil, savat — yo'q), o'z buyurtmasi yo'q
 *   - ikki parallel submit → bitta to'lov, bitta yechim, bitta jurnal,
 *     qaytim BIR marta; qayta urinish saqlangan natijani oladi
 *   - sverka: Σdr == Σcr, aktiv == passiv, ledger == bonusBalance
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-courier-orders';
// Production'ga yozmaslik (28-qoida): faqat emulator `demo-*` loyihasi.
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

// `COURIER_CF_INDEX` — eski versiyaga qarshi qayta tekshirish uchun (bug avval
// mavjud bo'lganini isbotlash: tegishli testlar YIQILISHI kerak).
const fns = require(process.env.COURIER_CF_INDEX || '../index');
const admin = require('firebase-admin');
const settlementLedger = require('../settlement_ledger');

const db = admin.firestore();

const A = '998901110001'; // tasdiqlangan kuryer
const B = '998902220002'; // tasdiqlangan kuryer (begona)
const S = '998903330003'; // suspended kuryer
const STRANGER = '998904440004'; // capability yo'q
const CUSTOMER = '998905550005';
const ACC = { [A]: 'accCOURIER0000000000A', [B]: 'accCOURIER0000000000B', [S]: 'accCOURIER0000000000S' };

const ctxOf = (phone) => ({ auth: { uid: `uid_${phone}`, token: { phone_number: `+${phone}` } } });
const call = (name, data, phone) => fns[name].run(data, ctxOf(phone));
const picked = (orderId, phone) => call('courierMarkPicked', { orderId, courierPhone: phone }, phone);
const arrived = (orderId, phone) => call('courierMarkArrived', { orderId, courierPhone: phone }, phone);
const submit = (orderId, phone, lines) => call('courierSubmitPayment', { orderId, courierPhone: phone, lines }, phone);

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function expectDenied(promise, reason) {
  await assert.rejects(promise, (e) => {
    assert.strictEqual(e.code, 'permission-denied', `kod ${e.code}: ${e.message}`);
    if (reason) assert.strictEqual(e.details && e.details.reason, reason, `sabab: ${JSON.stringify(e.details)}`);
    return true;
  });
}

async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
async function seedCourier(phone, status) {
  await db.collection('users').doc(phone).set({ role: 'user', accountId: ACC[phone], bonusBalance: 0 });
  await db.collection('provider_capabilities').doc(ACC[phone]).set({
    identity: { accountId: ACC[phone], primaryUid: phone },
    courier: { active: true },
    status: { courier: status },
  });
}
async function reset({ wallet = 50000 } = {}) {
  await clearEmulator();
  await seedCourier(A, 'approved');
  await seedCourier(B, 'approved');
  await seedCourier(S, 'suspended');
  await db.collection('users').doc(STRANGER).set({ role: 'user', bonusBalance: 0 });
  await db.collection('users').doc(CUSTOMER).set({ role: 'user', bonusBalance: 0 });
  if (wallet > 0) {
    await settlementLedger.postEntry(db, {
      idempotencyKey: `topup:${CUSTOMER}:test`, kind: 'test_topup',
      legs: [
        { account: 'admin_clearing', dr: wallet },
        { account: settlementLedger.passengerCreditAccount(CUSTOMER), cr: wallet },
      ],
    });
  }
}
/** Buyurtma + uni o'z ichiga olgan FAOL marshrut (marshrut egasi = `routeOwner`). */
async function seedOrder(id, over = {}, routeOwner = A) {
  await db.collection('orders').doc(id).set({
    type: 'bread', userPhone: CUSTOMER, total: 30000, balanceApplied: 0,
    paymentStatus: 'unpaid', status: 'in_delivery', fulfillmentStatus: 'arrived',
    courierId: routeOwner, ...over,
  });
  if (routeOwner) {
    await db.collection('delivery_routes').doc(`r_${id}_${routeOwner}`).set({
      courierId: routeOwner, status: 'active', orders: [id], currentIndex: 0,
    });
  }
}
const order = async (id) => (await db.collection('orders').doc(id).get()).data();
const bonusOf = async (phone) => (await db.collection('users').doc(phone).get()).data().bonusBalance || 0;
const bonus = () => bonusOf(CUSTOMER);
const pcBalance = async () => ((await db.collection(settlementLedger.COL_ACCOUNTS)
  .doc(settlementLedger.passengerCreditAccount(CUSTOMER)).get()).data() || {}).balance || 0;
const sub = async (id, col) => (await db.collection('orders').doc(id).collection(col).get()).docs.map((d) => d.data());
const walletLedger = async (type) => (await db.collection('users').doc(CUSTOMER)
  .collection('wallet_ledger').where('type', '==', type).get()).size;

async function main() {
  // ── huquq va egalik ──────────────────────────────────────────────────
  await reset();
  await check('STRANGER: submit rad — to\'lov, hamyon, ledger tegilmaydi', async () => {
    await seedOrder('o1');
    await expectDenied(submit('o1', STRANGER, [{ kind: 'cash', amount: 10000000 }]));
    assert.notStrictEqual((await order('o1')).paymentStatus, 'paid');
    assert.strictEqual(await bonus(), 50000);
  });
  await check('B: A marshrutidagi buyurtmaga tegolmaydi (Not your order)', async () => {
    await expectDenied(arrived('o1', B));
    await expectDenied(submit('o1', B, [{ kind: 'cash', amount: 30000 }]));
    assert.strictEqual((await order('o1')).courierId, A);
  });
  await check('ikki marshrutda (B ham), lekin courierId = A → B ga COURIER_ASSIGNMENT_CONFLICT', async () => {
    await db.collection('delivery_routes').doc('r_o1_B').set({ courierId: B, status: 'active', orders: ['o1'] });
    await expectDenied(submit('o1', B, [{ kind: 'cash', amount: 30000 }]), 'COURIER_ASSIGNMENT_CONFLICT');
    await expectDenied(picked('o1', B), 'COURIER_ASSIGNMENT_CONFLICT');
    assert.strictEqual(await bonus(), 50000);
  });
  await check('A (o\'z marshruti): picked → arrived → submit ishlaydi', async () => {
    await seedOrder('o2', { status: 'ready', fulfillmentStatus: 'ready' });
    assert.deepStrictEqual(await picked('o2', A), { ok: true });
    assert.deepStrictEqual(await arrived('o2', A), { ok: true });
    const r = await submit('o2', A, [{ kind: 'cash', amount: 30000 }]);
    assert.strictEqual(r.ok, true);
    assert.strictEqual((await order('o2')).status, 'delivered');
  });
  await check('restoran buyurtmasi: eski picked/arrived rad (USE_RESTAURANT_PICKUP / _ARRIVE) — kodsiz in_delivery yo\'q', async () => {
    await seedOrder('rest1', { type: 'restaurant', restaurantStatus: 'ready', status: 'ready', fulfillmentStatus: 'confirmed' });
    const failsWith = (p, code) => assert.rejects(p, (e) => {
      assert.strictEqual(e.code, 'failed-precondition', `kod ${e.code}: ${e.message}`);
      assert.strictEqual(e.details && e.details.code, code);
      return true;
    });
    await failsWith(picked('rest1', A), 'USE_RESTAURANT_PICKUP');
    await failsWith(arrived('rest1', A), 'USE_RESTAURANT_ARRIVE');
    const od = await order('rest1');
    assert.strictEqual(od.status, 'ready');
    assert.strictEqual(od.restaurantStatus, 'ready');
    assert.strictEqual(od.fulfillmentStatus, 'confirmed');
  });
  await check('suspended S: o\'z marshrutidagini tugatadi', async () => {
    await seedOrder('o3', { fulfillmentStatus: 'courier_picked', courierId: S }, S);
    await arrived('o3', S);
    const r = await submit('o3', S, [{ kind: 'cash', amount: 30000 }]);
    assert.strictEqual(r.ok, true);
  });

  // ── kuryer ≠ mijoz (ega qarori 2026-10-08) ───────────────────────────
  await check('O\'Z BUYURTMASI: marshrutda bo\'lsa ham COURIER_OWN_ORDER, «naqd 10 mln» o\'tmaydi', async () => {
    await seedOrder('own1', { userPhone: A });
    await expectDenied(arrived('own1', A), 'COURIER_OWN_ORDER');
    await expectDenied(submit('own1', A, [{ kind: 'cash', amount: 10000000 }]), 'COURIER_OWN_ORDER');
    assert.strictEqual(await bonusOf(A), 0, 'qaytim kuryer hamyoniga TUSHMADI');
    assert.notStrictEqual((await order('own1')).paymentStatus, 'paid');
  });
  await check('9 xonali mijoz raqami ham o\'z buyurtmasi deb taniladi', async () => {
    await seedOrder('own2', { phone: A.slice(3), userPhone: '' });
    await expectDenied(arrived('own2', A), 'COURIER_OWN_ORDER');
  });
  await check('courierCreateRoute: o\'z ready buyurtmasini OLMAYDI, begonasini oladi', async () => {
    await db.collection('orders').doc('rOwn').set({ userPhone: A, status: 'ready', total: 10000 });
    await db.collection('orders').doc('rOther').set({ userPhone: CUSTOMER, status: 'ready', total: 10000 });
    await assert.rejects(() => call('courierCreateRoute', { courierPhone: B, orderedOrderIds: ['rOther'] }, B)
      .then(() => call('courierCreateRoute', { courierPhone: A, orderedOrderIds: ['rOwn'] }, A)),
    (e) => e.code === 'failed-precondition', 'faqat o\'z buyurtmasi → no_ready_orders');
    assert.strictEqual((await order('rOwn')).status, 'ready');
    await db.collection('orders').doc('rOther2').set({ userPhone: CUSTOMER, status: 'ready', total: 10000 });
    await db.collection('orders').doc('rOwn2').set({ userPhone: A, status: 'ready', total: 10000 });
    const r = await call('courierCreateRoute', { courierPhone: A, orderedOrderIds: ['rOwn2', 'rOther2'] }, A);
    assert.strictEqual(r.count, 1);
    assert.strictEqual((await order('rOwn2')).status, 'ready');
    assert.strictEqual((await order('rOther2')).courierId, A);
  });
  await check('yig\'ib olish: kuryer o\'zi mijoz bo\'lgan vazifani YAKUNLAMAYDI', async () => {
    await db.collection('collection_tasks').doc('t1').set({
      courierId: A, customerPhone: A, status: 'collecting',
      arrivedAt: admin.firestore.Timestamp.now(), items: [],
    });
    await expectDenied(call('courierFinalizeCollection', {
      courierPhone: A, taskId: 't1', cashGiven: 0,
      items: [{ code: 'milk', label: 'Sut', unit: 'l', qty: 1000, unitPrice: 100000 }],
    }, A), 'COURIER_OWN_ORDER');
    assert.strictEqual(await bonusOf(A), 0);
    assert.strictEqual((await db.collection('collection_tasks').doc('t1').get()).data().status, 'collecting');
  });

  // ── `ready` ro'yxati (MFY ekrani) — faqat marshrut maydonlari ─────────
  // Qoida capability kuryerga `orders` ro'yxatini bermaydi va maydonlarni
  // kesa olmaydi (`functions/test/orders_courier_rules.test.js`).
  await reset();
  const listReady = (phone) => call('courierListReadyOrders', {}, phone);
  await check('courierListReadyOrders: autentifikatsiyasiz — unauthenticated', async () => {
    await assert.rejects(fns.courierListReadyOrders.run({}, {}), (e) => e.code === 'unauthenticated');
  });
  await check('courierListReadyOrders: capability\'siz va suspended — rad (yangi ish yo\'q)', async () => {
    await expectDenied(listReady(STRANGER));
    await expectDenied(listReady(S));
  });
  await check('courierListReadyOrders: faqat `ready`, o\'z buyurtmasi yo\'q, telefon/ism/manzil/savat YO\'Q', async () => {
    const at = (ms) => admin.firestore.Timestamp.fromMillis(ms);
    const pii = { userName: 'Mijoz', address: 'Navoiy 1', items: [{ name: 'Non', count: 2 }], total: 10000 };
    await db.collection('orders').doc('lr1').set({
      ...pii, userPhone: CUSTOMER, phone: CUSTOMER, status: 'ready', mfy: 'Navoiy', lat: 41.84, lng: 60.39,
      createdAt: at(1000),
    });
    await db.collection('orders').doc('lr2').set({
      ...pii, userPhone: CUSTOMER, status: 'ready', mfy: 'Yangiobod', lat: 41.85, lng: 60.4, createdAt: at(2000),
    });
    await db.collection('orders').doc('lrNoGeo').set({ ...pii, userPhone: CUSTOMER, status: 'ready' });
    await db.collection('orders').doc('lrOwn').set({ ...pii, userPhone: A, status: 'ready', mfy: 'Navoiy' });
    await db.collection('orders').doc('lrOwn9').set({ ...pii, userPhone: '', phone: A.slice(3), status: 'ready' });
    await db.collection('orders').doc('lrBusy').set({ ...pii, userPhone: CUSTOMER, status: 'in_delivery', courierId: B });
    const r = await listReady(A);
    assert.deepStrictEqual(r.orders.map((o) => o.id), ['lr2', 'lr1', 'lrNoGeo'], 'yangisi birinchi, sanasizi oxirida');
    for (const o of r.orders) {
      assert.deepStrictEqual(Object.keys(o).sort(), ['createdAtMs', 'id', 'lat', 'lng', 'mfy'], `ortiqcha maydon: ${o.id}`);
    }
    assert.deepStrictEqual(r.orders[1], { id: 'lr1', mfy: 'Navoiy', lat: 41.84, lng: 60.39, createdAtMs: 1000 });
    assert.deepStrictEqual(r.orders[2], { id: 'lrNoGeo', mfy: null, lat: null, lng: null, createdAtMs: null });
    assert.strictEqual(r.truncated, false);
  });
  await check('courierListReadyOrders: ro\'yxatdagi buyurtmadan courierCreateRoute marshrut quradi', async () => {
    const { orders } = await listReady(B);
    const ids = orders.map((o) => o.id);
    assert.ok(ids.includes('lrOwn'), 'A ning buyurtmasi B ga ko\'rinadi');
    const r = await call('courierCreateRoute', { courierPhone: B, orderedOrderIds: ids }, B);
    assert.strictEqual(r.count, ids.length, 'ko\'ringan hammasi qabul qilindi');
    assert.deepStrictEqual((await listReady(A)).orders, [], 'olingandan keyin ro\'yxat bo\'sh');
  });

  // ── parallel submit / idempotentlik ──────────────────────────────────
  await reset();
  await check('PARALLEL submit (hamyon 10 000 + naqd 20 000): bitta to\'lov, bitta yechim, bitta jurnal', async () => {
    await seedOrder('p1');
    const lines = [{ kind: 'wallet', amount: 10000 }, { kind: 'cash', amount: 20000 }];
    const rs = await Promise.allSettled([submit('p1', A, lines), submit('p1', A, lines)]);
    const bad = rs.filter((r) => r.status === 'rejected');
    assert.strictEqual(bad.length, 0, `rad: ${bad.map((r) => r.reason.message).join('; ')}`);
    const vals = rs.map((r) => r.value);
    assert.strictEqual(vals.filter((v) => v.idempotent === true).length, 1, 'bittasi takror (idempotent)');
    for (const v of vals) {
      assert.strictEqual(v.walletDebited, 10000); assert.strictEqual(v.newBalance, 40000);
    }
    assert.strictEqual(await bonus(), 40000, 'hamyondan BIR marta yechildi');
    assert.strictEqual(await pcBalance(), 40000, 'ledger == bonusBalance');
    assert.strictEqual(await walletLedger('purchase_debit'), 1);
    assert.strictEqual((await sub('p1', 'payment_lines')).length, 2, 'ikki qator, BIR marta');
    const j = await db.collection(settlementLedger.COL_JOURNAL).doc('bonus:courier_submit_p1').get();
    assert.ok(j.exists); assert.strictEqual(j.data().amount, 10000);
    const cc = await db.collection(settlementLedger.COL_ACCOUNTS).doc(settlementLedger.courierCashAccount(A)).get();
    assert.strictEqual(cc.data().balance, 20000, 'courier_cash BIR marta');
  });
  await check('PARALLEL submit (naqd 50 000, qaytim 20 000): qaytim BIR marta', async () => {
    await seedOrder('p2');
    const before = await bonus();
    const lines = [{ kind: 'cash', amount: 50000 }];
    const rs = await Promise.allSettled([submit('p2', A, lines), submit('p2', A, lines)]);
    assert.strictEqual(rs.filter((r) => r.status === 'rejected').length, 0);
    assert.strictEqual(await bonus(), before + 20000, 'qaytim ikki marta yozilmasin');
    assert.strictEqual(await pcBalance(), before + 20000);
    assert.strictEqual(await walletLedger('change_accrued'), 1);
  });
  await check('qayta urinish (javob yo\'qolgan): saqlangan natija, yangi harakat yo\'q', async () => {
    const before = await bonus();
    const r = await submit('p2', A, [{ kind: 'cash', amount: 50000 }]);
    assert.strictEqual(r.ok, true); assert.strictEqual(r.idempotent, true); assert.strictEqual(r.changeCredit, 20000);
    assert.strictEqual(await bonus(), before);
    assert.strictEqual((await sub('p2', 'payment_lines')).length, 1);
  });
  await check('takror javobni BOSHQA kuryer ololmaydi (marshrutda bo\'lsa ham)', async () => {
    await db.collection('delivery_routes').doc('r_p2_B').set({ courierId: B, status: 'active', orders: ['p2'] });
    await expectDenied(submit('p2', B, [{ kind: 'cash', amount: 50000 }]), 'COURIER_ASSIGNMENT_CONFLICT');
  });
  await check('sverka: Σdr == Σcr, aktiv == passiv, passenger_credit == bonusBalance', async () => {
    const rec = await settlementLedger.reconcile(db);
    assert.strictEqual(rec.balanced, true, `dr ${rec.totalDr} cr ${rec.totalCr}`);
    assert.strictEqual(rec.identityOk, true, `aktiv ${rec.assets} passiv ${rec.liabilities}`);
    assert.strictEqual(rec.projectionOk, true, JSON.stringify(rec.mismatches));
  });

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} o'tdi.`);
  process.exit(failed.length ? 1 : 0);
}
main().catch((e) => { console.error('FATAL', e); process.exit(1); });
