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
    assert.strictEqual(r.radiusKm, null, 'GPS\'siz — filtr yo\'q (eski APK)');
  });
  // Geo 4-bosqich (D-GEO-3): kuryer GPS'i + 15 km.
  await check('courierListReadyOrders: GPS berilsa — 15 km ichidagilar + koordinatasizlar; uzoqdagi yo\'q', async () => {
    await db.collection('orders').doc('lrFar').set({
      userPhone: CUSTOMER, status: 'ready', mfy: 'Chilonzor', lat: 41.29, lng: 69.2,
      createdAt: admin.firestore.Timestamp.fromMillis(3000),
    });
    // ~16.7 km shimolda (0.15° kenglik) — chegaradan tashqari.
    await db.collection('orders').doc('lrEdge').set({
      userPhone: CUSTOMER, status: 'ready', mfy: 'Chegara', lat: 41.84 + 0.15, lng: 60.39,
      createdAt: admin.firestore.Timestamp.fromMillis(500),
    });
    const near = await call('courierListReadyOrders', { lat: 41.84, lng: 60.39 }, A);
    assert.deepStrictEqual(near.orders.map((o) => o.id), ['lr2', 'lr1', 'lrNoGeo']);
    assert.strictEqual(near.radiusKm, 15);
    const wide = await call('courierListReadyOrders', { lat: 41.84, lng: 60.39, radiusKm: 20 }, A);
    assert.ok(wide.orders.some((o) => o.id === 'lrEdge'), '20 km — chegaradagi kiradi');
    assert.ok(!wide.orders.some((o) => o.id === 'lrFar'));
    const all = await listReady(A);
    assert.ok(all.orders.some((o) => o.id === 'lrFar'), 'GPS\'siz — avvalgidek hammasi');
    const bad = await call('courierListReadyOrders', { lat: 'x', lng: 60.39 }, A);
    assert.strictEqual(bad.radiusKm, null, 'noto\'g\'ri koordinata — filtr yo\'q');
    await db.collection('orders').doc('lrFar').delete();
    await db.collection('orders').doc('lrEdge').delete();
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

  // R1 (C-1): courier_field_cash ledger posti yiqilsa, «naqd qo'lda» yozuvi
  // YO'QOLMASLIGI kerak: niyat tranzaksiyada saqlanadi, sweeper/takror chaqiruv tiklaydi.
  await check('naqd ledger posti yiqilsa: niyat saqlanadi, sweeper BIR marta tiklaydi, takror ikkilamaydi', async () => {
    await reset({ wallet: 0 });
    await seedOrder('fc1', { total: 30000 });
    const realPost = settlementLedger.postEntry;
    settlementLedger.postEntry = async (d, entry, opts) => {
      if (String(entry.idempotencyKey).startsWith('courierCash:')) throw new Error('boom');
      return realPost(d, entry, opts);
    };
    try {
      const r = await submit('fc1', A, [{ kind: 'cash', amount: 30000 }]);
      assert.strictEqual(r.ok, true);
    } finally { settlementLedger.postEntry = realPost; }
    const jRef = db.collection(settlementLedger.COL_JOURNAL).doc('courierCash:fc1');
    assert.strictEqual((await jRef.get()).exists, false, 'post yiqilgan edi');
    assert.strictEqual((await db.collection('courier_cash_pending').doc('fc1').get()).exists, true, 'niyat saqlanmagan');
    await fns.courierCashPendingSweep.run({});
    assert.strictEqual((await jRef.get()).exists, false, 'sweeper yangi niyatga tegmasligi kerak (60 s kutish)');
    await db.collection('courier_cash_pending').doc('fc1').update({
      createdAt: admin.firestore.Timestamp.fromMillis(Date.now() - 10 * 60 * 1000),
    });
    await fns.courierCashPendingSweep.run({});
    assert.strictEqual((await jRef.get()).exists, true, 'sweeper tiklamadi');
    assert.strictEqual((await db.collection('courier_cash_pending').doc('fc1').get()).exists, false, 'niyat o\'chmagan');
    const cashAcc = () => db.collection(settlementLedger.COL_ACCOUNTS)
      .doc(settlementLedger.courierCashAccount(`998${A.slice(3)}`)).get();
    assert.strictEqual(Math.abs(((await cashAcc()).data() || {}).balance || 0), 30000, 'kuryer naqd balansi');
    // takror chaqiruv va takror sweeper — ikkilanmaydi
    const again = await submit('fc1', A, [{ kind: 'cash', amount: 30000 }]);
    assert.strictEqual(again.idempotent, true);
    await fns.courierCashPendingSweep.run({});
    assert.strictEqual(Math.abs(((await cashAcc()).data() || {}).balance || 0), 30000, 'ikkilandi');
  });

  // ── C-9: courierMarkPicked orqaga qaytarmaydi (audit 2026-10-16) ──────────
  await check('C-9: arrived / payment_pending_confirm / courier_picked holatda picked — ok, holat ORQAGA qaytmaydi', async () => {
    await reset({ wallet: 0 });
    const t0 = admin.firestore.Timestamp.fromMillis(1000);
    for (const fs of ['arrived', 'payment_pending_confirm', 'courier_picked']) {
      await seedOrder(`c9_${fs}`, { fulfillmentStatus: fs, status: 'in_delivery', pickedAt: t0 });
      const r = await picked(`c9_${fs}`, A);
      assert.strictEqual(r.ok, true, `${fs}: ok`);
      const od = await order(`c9_${fs}`);
      assert.strictEqual(od.fulfillmentStatus, fs, `${fs} -> ${od.fulfillmentStatus}`);
      assert.strictEqual(od.pickedAt.toMillis(), 1000, `${fs}: pickedAt qayta yozilgan`);
      const ev = (await sub(`c9_${fs}`, 'payment_events')).filter((e) => e.action === 'courier_picked');
      assert.strictEqual(ev.length, 0, `${fs}: ortiqcha audit yozuvi`);
    }
    // oddiy birinchi olish avvalgidek ishlaydi
    await seedOrder('c9_ready', { status: 'ready', fulfillmentStatus: 'ready' });
    await picked('c9_ready', A);
    assert.strictEqual((await order('c9_ready')).fulfillmentStatus, 'courier_picked');
  });

  // ── C-8: 9 xonali (eski) mijoz raqami ishlaydi, begona rad (audit) ─────────
  await check('C-8: courierPhone 9 xonali, token 12 xonali — picked/arrived/submit ishlaydi; begona rad', async () => {
    await reset({ wallet: 0 });
    const A9 = A.slice(3);
    await seedOrder('c8', { status: 'ready', fulfillmentStatus: 'ready' });
    const viaA9 = (name, extra) => call(name, { orderId: 'c8', courierPhone: A9, ...extra }, A);
    await expectDenied(call('courierMarkPicked', { orderId: 'c8', courierPhone: A9 }, B));
    await expectDenied(call('courierMarkArrived', { orderId: 'c8', courierPhone: A9 }, B));
    await expectDenied(call('courierSubmitPayment', { orderId: 'c8', courierPhone: A9, lines: [{ kind: 'cash', amount: 30000 }] }, B));
    assert.deepStrictEqual(await viaA9('courierMarkPicked'), { ok: true });
    assert.deepStrictEqual(await viaA9('courierMarkArrived'), { ok: true });
    const r = await viaA9('courierSubmitPayment', { lines: [{ kind: 'cash', amount: 30000 }] });
    assert.strictEqual(r.ok, true);
    const od = await order('c8');
    assert.strictEqual(od.paymentStatus, 'paid');
    assert.strictEqual(od.courierId, A, 'kanon (12 xonali) ID yoziladi');
  });

  // ── C-3/C-4: courierRecoverOrphanRoute (audit 2026-10-16) ─────────────────
  const FS = require('@google-cloud/firestore');
  const activeRoutesOf = async (cid) => (await db.collection('delivery_routes')
    .where('courierId', '==', cid).where('status', '==', 'active').get()).docs;
  const seedLoose = (id, over = {}) => db.collection('orders').doc(id).set({
    type: 'bread', userPhone: CUSTOMER, total: 30000, balanceApplied: 0,
    paymentStatus: 'unpaid', status: 'in_delivery', fulfillmentStatus: 'courier_picked',
    courierId: A, ...over,
  });
  await check('C-3/C-4: faqat O\'Z (9 va 12 xonali) in_delivery buyurtmalar; restoran, to\'langan, begona yo\'q; boshqa kuryer hujjati O\'QILMAYDI', async () => {
    await reset({ wallet: 0 });
    await seedLoose('lo1');
    await seedLoose('lo2', { courierId: A.slice(3) }); // eski 9 xonali
    await seedLoose('lo_rest', { type: 'restaurant', restaurantStatus: 'on_the_way' });
    await seedLoose('lo_paid', { paymentStatus: 'paid' });
    await seedLoose('lo_B', { courierId: B });
    await seedLoose('lo_B2', { courierId: B });
    const seen = [];
    const origQ = FS.Query.prototype.get;
    const origT = FS.Transaction.prototype.get;
    const rec = (res) => { for (const d of (res && res.docs) || []) if (d.ref.parent.id === 'orders') seen.push(d.id); return res; };
    FS.Query.prototype.get = async function qget(...a) { return rec(await origQ.apply(this, a)); };
    FS.Transaction.prototype.get = async function tget(r, ...a) { return rec(await origT.call(this, r, ...a)); };
    let r;
    try { r = await call('courierRecoverOrphanRoute', { courierPhone: A }, A); } finally {
      FS.Query.prototype.get = origQ; FS.Transaction.prototype.get = origT;
    }
    assert.strictEqual(r.revived, true);
    assert.strictEqual(r.count, 2, JSON.stringify(r));
    const route = (await db.collection('delivery_routes').doc(r.routeId).get()).data();
    assert.deepStrictEqual([...route.orders].sort(), ['lo1', 'lo2']);
    assert.strictEqual((await order('lo_rest')).deliveryRouteId, undefined, 'restoran buyurtmasi marshrutga tushmadi');
    assert.strictEqual((await order('lo_B')).deliveryRouteId, undefined);
    assert.strictEqual((await order('lo1')).deliveryRouteId, r.routeId);
    assert.strictEqual((await order('lo2')).courierId, A, '9 xonali ID kanonga keltirildi');
    assert.ok(!seen.includes('lo_B') && !seen.includes('lo_B2'), `begona kuryer buyurtmalari o'qildi: ${seen}`);
    const again = await call('courierRecoverOrphanRoute', { courierPhone: A }, A);
    assert.strictEqual(again.revived, false);
    assert.strictEqual(again.reason, 'has_active');
  });
  await check('C-3: ikki/besh PARALLEL chaqiruv — BITTA faol marshrut, buyurtmalar bitta marshrutda', async () => {
    await reset({ wallet: 0 });
    await seedLoose('pr1'); await seedLoose('pr2'); await seedLoose('pr3');
    const rs = await Promise.all([1, 2, 3, 4, 5].map(() => call('courierRecoverOrphanRoute', { courierPhone: A }, A)));
    assert.strictEqual(rs.filter((x) => x.revived === true).length, 1, JSON.stringify(rs));
    const routes = await activeRoutesOf(A);
    assert.strictEqual(routes.length, 1, `faol marshrutlar: ${routes.length}`);
    for (const id of ['pr1', 'pr2', 'pr3']) assert.strictEqual((await order(id)).deliveryRouteId, routes[0].id);
    assert.deepStrictEqual([...routes[0].data().orders].sort(), ['pr1', 'pr2', 'pr3']);
  });
  await check('C-3: tranzaksiyada buyurtma boshqa kuryerga o\'tgan bo\'lsa marshrutga QO\'SHILMAYDI', async () => {
    await reset({ wallet: 0 });
    await seedLoose('mv1'); await seedLoose('mv2');
    // so'rovdan keyin, tranzaksiyadan oldin mv2 boshqa kuryerga o'tadi
    const origQ = FS.Query.prototype.get;
    let moved = false;
    FS.Query.prototype.get = async function qget(...a) {
      const res = await origQ.apply(this, a);
      if (!moved && (res.docs || []).some((d) => d.id === 'mv2')) {
        moved = true;
        await db.collection('orders').doc('mv2').update({ courierId: B });
      }
      return res;
    };
    let r;
    try { r = await call('courierRecoverOrphanRoute', { courierPhone: A }, A); } finally { FS.Query.prototype.get = origQ; }
    assert.ok(moved, 'hook ishladi');
    const route = (await db.collection('delivery_routes').doc(r.routeId).get()).data();
    assert.deepStrictEqual(route.orders, ['mv1']);
    assert.strictEqual((await order('mv2')).courierId, B);
    assert.strictEqual((await order('mv2')).deliveryRouteId, undefined);
  });

  // ── C-10: route push xatosi jim yutilmaydi (audit 2026-10-16) ─────────────
  await check('C-10: onDeliveryRouteCreate/Assign push xatosi bitta qatorli JSON log (COURIER_PUSH_FAILED)', async () => {
    await reset({ wallet: 0 });
    await db.collection('users').doc(A).update({ fcmToken: 'tok-A-0123456789-abcdef' });
    const msgr = admin.messaging(); // keshlangan nusxa — index.js ham shuni oladi
    const origSend = msgr.send;
    msgr.send = async () => { throw new Error('fcm down'); };
    const lines = [];
    const origErr = console.error; const origWarn = console.warn; const origLog = console.log;
    const grab = (...a) => lines.push(a.join(' '));
    console.error = grab; console.warn = grab; console.log = grab;
    try {
      await fns.onDeliveryRouteCreate.run({ data: () => ({ courierId: A, orders: ['x'] }), id: 'rt1' }, {});
      await fns.onDeliveryRouteAssign.run({
        before: { data: () => ({ courierId: '' }) },
        after: { data: () => ({ courierId: A, orders: ['x'] }), id: 'rt2' },
      }, {});
    } finally {
      msgr.send = origSend; console.error = origErr; console.warn = origWarn; console.log = origLog;
    }
    const logs = lines.map((l) => { try { return JSON.parse(l); } catch (_) { return null; } })
      .filter((j) => j && j.errorCode === 'COURIER_PUSH_FAILED');
    assert.deepStrictEqual(logs.map((j) => j.routeId).sort(), ['rt1', 'rt2']);
    for (const j of logs) {
      assert.strictEqual(j.result, 'push_failed');
      assert.ok(j.action && j.message);
    }
  });

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} o'tdi.`);
  process.exit(failed.length ? 1 : 0);
}
main().catch((e) => { console.error('FATAL', e); process.exit(1); });
