/**
 * HISOBNI O'CHIRISH — blokirovka ro'yxati (`account_deletion_core.js`), Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-acct-del-blockers \
 *     "node test/account_deletion_blockers_cf.test.js"
 *
 * Faqat O'QISH modulini tekshiradi: faol holatlar blokirovka qiladi, yakunlanganlari va begona
 * hujjatlar — yo'q; 9 xonali eski shakl topiladi; kesilgan skan = blok (xavfsiz yo'nalish).
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-acct-del-blockers';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const admin = require('firebase-admin');
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const core = require('../account_deletion_core');

const U = '998901112233'; // o'chirmoqchi bo'lgan foydalanuvchi
const U9 = '901112233';
const OTHER = '998907776655';

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const blockersOf = async (uid = U, opts) => {
  const id = await core.resolveIdentity(db, uid);
  return core.findBlockers(db, id, opts);
};
const codes = (bl) => bl.map((b) => b.code).sort();

async function main() {
  await clearEmulator();
  await db.collection('users').doc(U).set({ role: 'user', phone: `+${U}`, accountId: 'acc_u' });

  // ── Sof funksiyalar
  await check('P1 phoneForms: 12, 9, +12 va chiqindi shakllar', () => {
    assert.deepStrictEqual(core.phoneForms('+998 90 111-22-33').all, [U, U9, `+${U}`]);
    assert.deepStrictEqual(core.phoneForms(U9).all, [U, U9, `+${U}`]);
    assert.deepStrictEqual(core.phoneForms('12345').all, []);
    assert.deepStrictEqual(core.phoneForms('').all, []);
    assert.deepStrictEqual(core.phoneForms(null).all, []);
  });
  await check('P2 resolveIdentity: noto\'g\'ri uid — xato; users, accountId, qurilma xeshlari yig\'iladi', async () => {
    await assert.rejects(() => core.resolveIdentity(db, '123'), /ACCOUNT_UID_INVALID/);
    await db.collection('device_bindings').doc('a'.repeat(64)).set({ phone: U });
    await db.collection('device_bindings').doc('b'.repeat(64)).set({ phone: OTHER });
    const id = await core.resolveIdentity(db, U);
    assert.deepStrictEqual(id.userDocIds, [U]);
    assert.deepStrictEqual(id.accountIds, ['acc_u']);
    assert.deepStrictEqual(id.deviceHashes, ['a'.repeat(64)]);
    assert.ok(id.forms.includes(U9) && id.forms.includes(`+${U}`));
  });
  await check('P3 changeDevicePhone: users.phone boshqa raqam bo\'lsa u ham identity\'ga kiradi', async () => {
    await db.collection('users').doc('998909990001').set({ role: 'user', phone: '+998909990002' });
    const id = await core.resolveIdentity(db, '998909990001');
    assert.ok(id.forms.includes('998909990002'), 'eski/yangi telefon shakli yo\'q');
  });

  // ── Hech narsa yo'q
  await check('B0 toza hisob — blok yo\'q', async () => {
    assert.deepStrictEqual(await blockersOf(), []);
  });

  // ── Buyurtmalar
  await check('B1 faol buyurtma blokirovka qiladi; yakunlangan va begona — yo\'q', async () => {
    await db.collection('orders').doc('o_done').set({ userPhone: U, status: 'completed', fulfillmentStatus: 'delivered' });
    await db.collection('orders').doc('o_cancel').set({ userPhone: U, status: 'cancelled' });
    await db.collection('orders').doc('o_other').set({ userPhone: OTHER, status: 'new' });
    assert.deepStrictEqual(await blockersOf(), []);
    await db.collection('orders').doc('o_new').set({ userPhone: U, status: 'new' });
    const bl = await blockersOf();
    assert.deepStrictEqual(codes(bl), ['ORDER_ACTIVE']);
    assert.strictEqual(bl[0].area, 'orders');
    assert.deepStrictEqual(bl[0].sample, ['o_new']);
  });
  await check('B2 har bir faol status qiymati alohida blokirovka qiladi (ACTIVE ro\'yxati qulflangan)', async () => {
    for (const s of core.ACTIVE.ordersStatus) {
      await clearOrders();
      await db.collection('orders').doc('x').set({ userPhone: U, status: s });
      assert.deepStrictEqual(codes(await blockersOf()), ['ORDER_ACTIVE'], `status ${s}`);
    }
    for (const s of core.ACTIVE.ordersFulfillment) {
      await clearOrders();
      await db.collection('orders').doc('x').set({ userPhone: U, status: 'x', fulfillmentStatus: s });
      assert.deepStrictEqual(codes(await blockersOf()), ['ORDER_ACTIVE'], `fulfillment ${s}`);
    }
    for (const s of core.ACTIVE.restaurantStatus) {
      await clearOrders();
      await db.collection('orders').doc('x').set({ userPhone: U, status: 'x', restaurantStatus: s });
      assert.deepStrictEqual(codes(await blockersOf()), ['ORDER_ACTIVE'], `restaurant ${s}`);
    }
    await clearOrders();
  });
  await check('B3 eski 9 xonali va +998 shakldagi userPhone ham topiladi', async () => {
    await clearOrders();
    await db.collection('orders').doc('l9').set({ userPhone: U9, status: 'accepted' });
    assert.deepStrictEqual(codes(await blockersOf()), ['ORDER_ACTIVE']);
    await clearOrders();
    await db.collection('orders').doc('lp').set({ userPhone: `+${U}`, status: 'ready' });
    assert.deepStrictEqual(codes(await blockersOf()), ['ORDER_ACTIVE']);
    await clearOrders();
  });
  await check('B4 kuryer tomoni: courierId bo\'yicha faol buyurtma', async () => {
    await db.collection('orders').doc('cr').set({ userPhone: OTHER, courierId: U, status: 'in_delivery' });
    const bl = await blockersOf();
    assert.deepStrictEqual(codes(bl), ['COURIER_ORDER_ACTIVE']);
    assert.strictEqual(bl[0].area, 'courier');
    await clearOrders();
  });
  await check('B5 gilam/agro: faol bloklaydi, yakunlangan — yo\'q', async () => {
    await db.collection('carpet_wash_orders').doc('c1').set({ customerPhone: U, status: 'washing' });
    await db.collection('agro_pickup_orders').doc('a1').set({ customerPhone: U, status: 'picked_up' });
    await db.collection('carpet_wash_orders').doc('c2').set({ customerPhone: U, status: 'completed' });
    assert.deepStrictEqual(codes(await blockersOf()), ['AGRO_ACTIVE', 'CARPET_ACTIVE']);
    await db.collection('carpet_wash_orders').doc('c1').delete();
    await db.collection('agro_pickup_orders').doc('a1').delete();
    assert.deepStrictEqual(await blockersOf(), []);
  });
  await check('B6 restoran egasi: o\'z restoraniga kelgan faol buyurtma', async () => {
    await db.collection('restaurants').doc('r1').set({ ownerUid: U });
    await db.collection('orders').doc('ro1').set({ userPhone: OTHER, restaurantId: 'r1', restaurantStatus: 'placed' });
    await db.collection('orders').doc('ro2').set({ userPhone: OTHER, restaurantId: 'r_other', restaurantStatus: 'placed' });
    assert.deepStrictEqual(codes(await blockersOf()), ['RESTAURANT_ORDER_ACTIVE']);
    await db.collection('orders').doc('ro1').update({ restaurantStatus: 'delivered' });
    assert.deepStrictEqual(await blockersOf(), []);
    await clearOrders();
    await db.collection('restaurants').doc('r1').delete();
  });

  // ── Safarlar va bronlar
  await check('T1 taksi: yo\'lovchi va haydovchi tomoni; yakunlangan — yo\'q', async () => {
    await db.collection('trips').doc('t1').set({ userPhone: U, status: 'searching' });
    await db.collection('trips').doc('t2').set({ userPhone: OTHER, driverId: U, status: 'accepted' });
    await db.collection('trips').doc('t3').set({ userPhone: OTHER, acceptedDriverId: U, status: 'pending' });
    await db.collection('trips').doc('t4').set({ userPhone: U, status: 'completed' });
    const bl = await blockersOf();
    assert.deepStrictEqual(codes(bl), ['TRIP_ACTIVE', 'TRIP_DRIVER_ACTIVE']);
    assert.strictEqual(bl.find((b) => b.code === 'TRIP_DRIVER_ACTIVE').count, 2); // t2 + t3 birlashtirildi
    for (const id of ['t1', 't2', 't3', 't4']) await db.collection('trips').doc(id).delete();
  });
  await check('T2 shaharlararo / stol / moy bronlari', async () => {
    await db.collection('intercity_bookings').doc('i1').set({ userPhone: U9, status: 'confirmed' });
    await db.collection('restaurant_bookings').doc('b1').set({ userPhone: U, status: 'requested' });
    await db.collection('oil_change_bookings').doc('m1').set({ uid: U, status: 'new' });
    assert.deepStrictEqual(codes(await blockersOf()), ['INTERCITY_ACTIVE', 'OIL_BOOKING_ACTIVE', 'TABLE_BOOKING_ACTIVE']);
    await db.collection('intercity_bookings').doc('i1').update({ status: 'cancelled' });
    await db.collection('restaurant_bookings').doc('b1').update({ status: 'completed' });
    await db.collection('oil_change_bookings').doc('m1').update({ status: 'done' });
    assert.deepStrictEqual(await blockersOf(), []);
  });

  // ── Yuk, talab, Xitoy
  await check('Y1 yuk: egasi va tayinlangan ijrochi; yetkazilgan — yo\'q', async () => {
    await db.collection('shipments').doc('s1').set({ ownerId: U, status: 'in_transit', paymentStatus: 'escrow_funded' });
    await db.collection('shipments').doc('s2').set({ ownerId: OTHER, assignedProviderIds: [U], status: 'ready' });
    await db.collection('shipments').doc('s3').set({ ownerId: U, status: 'delivered', paymentStatus: 'released' });
    assert.deepStrictEqual(codes(await blockersOf()), ['SHIPMENT_ACTIVE']);
    await db.collection('shipments').doc('s1').update({ status: 'delivered', paymentStatus: 'released' });
    // s2 hali ijrochi sifatida faol
    assert.deepStrictEqual(codes(await blockersOf()), ['SHIPMENT_ACTIVE']);
    await db.collection('shipments').doc('s2').update({ status: 'delivered' });
    assert.deepStrictEqual(await blockersOf(), []);
  });
  await check('Y2 to\'lov holati faol bo\'lsa status yakunlangan bo\'lsa ham blok (escrow_frozen)', async () => {
    await db.collection('shipments').doc('s4').set({ ownerId: U, status: 'delivered', paymentStatus: 'escrow_frozen' });
    assert.deepStrictEqual(codes(await blockersOf()), ['SHIPMENT_ACTIVE']);
    await db.collection('shipments').doc('s4').delete();
  });
  await check('Y3 talab va Xitoy so\'rovi', async () => {
    await db.collection('demands').doc('d1').set({ ownerId: U, status: 'in_progress' });
    await db.collection('china_inquiries').doc('ch1').set({ ownerId: U, status: 'quoted' });
    assert.deepStrictEqual(codes(await blockersOf()), ['CHINA_ACTIVE', 'DEMAND_ACTIVE']);
    await db.collection('demands').doc('d1').update({ status: 'completed' });
    await db.collection('china_inquiries').doc('ch1').update({ status: 'closed' });
    assert.deepStrictEqual(await blockersOf(), []);
  });

  // ── Hisob-kitob, kuryer, qarz
  await check('S1 kutilayotgan settlement (haydovchi yoki yo\'lovchi)', async () => {
    await db.collection('settlements').doc('st1').set({ driverUid: U, passengerUid: OTHER, state: 'pending' });
    await db.collection('settlements').doc('st2').set({ driverUid: OTHER, passengerUid: U, state: 'completed' });
    assert.deepStrictEqual(codes(await blockersOf()), ['SETTLEMENT_PENDING']);
    await db.collection('settlements').doc('st1').update({ state: 'completed' });
    assert.deepStrictEqual(await blockersOf(), []);
  });
  await check('K1 kuryer: faol marshrut, qo\'ldagi naqd, driver_float, taksi qarzi', async () => {
    await db.collection('delivery_routes').doc('dr1').set({ courierId: U, status: 'active' });
    await db.collection('ledger_accounts').doc(`courier_cash:${U}`).set({ balance: 50000 });
    await db.collection('ledger_accounts').doc(`driver_float:${U}`).set({ balance: -1 });
    await db.collection('provider_capabilities').doc('acc_u').set({ debt: { taxi: 7000 } });
    assert.deepStrictEqual(codes(await blockersOf()),
      ['COURIER_CASH_HELD', 'COURIER_ROUTE_ACTIVE', 'DRIVER_FLOAT_NONZERO', 'TAXI_DEBT']);
    await db.collection('delivery_routes').doc('dr1').update({ status: 'done' });
    await db.collection('ledger_accounts').doc(`courier_cash:${U}`).update({ balance: 0 });
    await db.collection('ledger_accounts').doc(`driver_float:${U}`).update({ balance: 0 });
    await db.collection('provider_capabilities').doc('acc_u').update({ debt: { taxi: 0 } });
    assert.deepStrictEqual(await blockersOf(), []);
  });
  await check('K2 courier_cash 9 xonali kalit ostida ham topiladi', async () => {
    await db.collection('ledger_accounts').doc(`courier_cash:${U9}`).set({ balance: 10 });
    assert.deepStrictEqual(codes(await blockersOf()), ['COURIER_CASH_HELD']);
    await db.collection('ledger_accounts').doc(`courier_cash:${U9}`).delete();
  });

  // ── Pul harakatda
  await check('M1 payout / yechish / to\'ldirish kutilayotgan — blok; yakunlangan — yo\'q', async () => {
    await db.collection('payout_requests').doc('p1').set({ userPhone: U9, status: 'pending' });
    await db.collection('wallet_withdraw_requests').doc('w1').set({ uid: U, status: 'approved' });
    await db.collection('wallet_topup_requests').doc('tp1').set({ uid: U, status: 'awaiting_review' });
    await db.collection('wallet_topup_requests').doc('tp2').set({ uid: U, status: 'credited' });
    const bl = await blockersOf();
    assert.deepStrictEqual(codes(bl), ['PAYOUT_PENDING', 'TOPUP_PENDING', 'WITHDRAW_PENDING']);
    assert.ok(bl.every((b) => b.area === 'money'));
    await db.collection('payout_requests').doc('p1').update({ status: 'paid' });
    await db.collection('wallet_withdraw_requests').doc('w1').update({ status: 'paid' });
    await db.collection('wallet_topup_requests').doc('tp1').update({ status: 'credited' });
    assert.deepStrictEqual(await blockersOf(), []);
  });

  // ── A1 tahlilidan keyingi qoidalar
  await check('A1 collection_tasks: assigned/collecting bloklaydi (mijoz va kuryer tomoni), completed — yo\'q', async () => {
    await db.collection('collection_tasks').doc('ct1').set({ customerPhone: U9, status: 'assigned' });
    await db.collection('collection_tasks').doc('ct2').set({ customerUid: U, status: 'collecting' });
    await db.collection('collection_tasks').doc('ct3').set({ courierId: U, status: 'assigned' });
    await db.collection('collection_tasks').doc('ct4').set({ customerUid: U, status: 'completed' });
    const bl = await blockersOf();
    // mijoz tomoni (2 ta) 'orders' ostida, kuryer tomoni (1 ta) 'courier' ostida alohida yozuv
    assert.deepStrictEqual(codes(bl), ['COLLECTION_TASK_ACTIVE', 'COLLECTION_TASK_ACTIVE']);
    assert.deepStrictEqual(bl.map((b) => `${b.area}:${b.count}`).sort(), ['courier:1', 'orders:2']);
    for (const id of ['ct1', 'ct2', 'ct3', 'ct4']) await db.collection('collection_tasks').doc(id).delete();
    assert.deepStrictEqual(await blockersOf(), []);
  });
  await check('A2 gilam \'delivered\' (eski qiymat) FAOL hisoblanadi — xavfsiz tomon', async () => {
    await db.collection('carpet_wash_orders').doc('cd').set({ customerPhone: U, status: 'delivered' });
    assert.deepStrictEqual(codes(await blockersOf()), ['CARPET_ACTIVE']);
    await db.collection('carpet_wash_orders').doc('cd').update({ status: 'completed' });
    assert.deepStrictEqual(await blockersOf(), []);
  });
  await check('A3 supplier_payable: faqat MUSBAT qoldiq bloklaydi; manfiy/0 — yo\'q', async () => {
    await db.collection('ledger_accounts').doc(`supplier_payable:${U}`).set({ balance: 90000 });
    assert.deepStrictEqual(codes(await blockersOf()), ['SUPPLIER_PAYABLE_OWED']);
    await db.collection('ledger_accounts').doc(`supplier_payable:${U}`).update({ balance: -40000 });
    assert.deepStrictEqual(await blockersOf(), []);
    await db.collection('ledger_accounts').doc(`supplier_payable:${U}`).update({ balance: 0 });
    assert.deepStrictEqual(await blockersOf(), []);
    await db.collection('ledger_accounts').doc(`supplier_payable:${U9}`).set({ balance: 5 });
    assert.deepStrictEqual(codes(await blockersOf()), ['SUPPLIER_PAYABLE_OWED']); // 9 xonali kalit ham
    await db.collection('ledger_accounts').doc(`supplier_payable:${U9}`).delete();
  });
  await check('A4 ochiq restoran egasi bloklanadi (approved/applied/suspended); closed/rejected — yo\'q', async () => {
    for (const s of core.ACTIVE.restaurantOwned) {
      await db.collection('restaurants').doc('rx').set({ ownerUid: U, status: s });
      assert.deepStrictEqual(codes(await blockersOf()), ['RESTAURANT_OWNER'], `status ${s}`);
    }
    for (const s of ['closed', 'rejected']) {
      await db.collection('restaurants').doc('rx').set({ ownerUid: U, status: s });
      assert.deepStrictEqual(await blockersOf(), [], `status ${s}`);
    }
    await db.collection('restaurants').doc('rx').delete();
  });

  // ── Xodim roli
  await check('R1 admin/moliya/dispetcher/staff/auditor roli — blok; oddiy rol — yo\'q', async () => {
    for (const r of core.STAFF_ROLES) {
      await db.collection('users').doc(U).update({ role: r });
      const bl = await blockersOf();
      assert.deepStrictEqual(codes(bl), ['STAFF_ROLE'], `rol ${r}`);
      assert.strictEqual(bl[0].area, 'staff');
    }
    await db.collection('users').doc(U).update({ role: 'courier' });
    assert.deepStrictEqual(await blockersOf(), []);
    await db.collection('users').doc(U).update({ role: 'user' });
  });
  await check('R2 rol faqat eski 9 xonali hujjatda bo\'lsa ham topiladi', async () => {
    await db.collection('users').doc(U9).set({ role: 'admin' });
    assert.deepStrictEqual(codes(await blockersOf()), ['STAFF_ROLE']);
    await db.collection('users').doc(U9).delete();
  });

  // ── Xavfsiz yo'nalish
  await check('X1 skan chegaradan oshsa — SCAN_TRUNCATED (blok), sukut bilan "ruxsat" emas', async () => {
    for (let i = 0; i < 4; i++) await db.collection('orders').doc(`bulk${i}`).set({ userPhone: U, status: 'completed' });
    const bl = await blockersOf(U, { cap: 3 });
    assert.ok(bl.some((b) => b.code === 'SCAN_TRUNCATED'), `kodlar: ${codes(bl)}`);
    // chegara ichida — blok yo'q
    assert.deepStrictEqual(await blockersOf(U, { cap: 10 }), []);
    await clearOrders();
  });
  await check('X2 findBlockers faqat o\'qiydi: hech qanday hujjat o\'zgarmaydi', async () => {
    await db.collection('orders').doc('keep').set({ userPhone: U, status: 'new' });
    const before = (await db.collection('orders').doc('keep').get()).updateTime.toMillis();
    await blockersOf();
    const after = (await db.collection('orders').doc('keep').get()).updateTime.toMillis();
    assert.strictEqual(before, after);
    await clearOrders();
  });
}

async function clearOrders() {
  const snap = await db.collection('orders').get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}

main().then(() => {
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}).catch((e) => { console.error(e); process.exit(1); });
