/**
 * Admin «qotib qolgan vazifalar» ro'yxati (D6, ega qarori 2026-10-16): `adminListStaleTasks({hours})`.
 * HAQIQIY `functions/index.js` callable'i `.run()` orqali, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-stale-tasks \
 *     "node functions/test/admin_stale_tasks_cf.test.js"
 *
 * Qulflanadi:
 *   - faqat admin/superadmin; soat: standart 3, 1..168 ga qisqartiriladi, matn emas
 *   - modullar: courier_orders (in_delivery, restoransiz), restaurant_orders (ready/picked/arrived
 *     KURYERLI), carpet, agro, relay_shipments (in_transit), relay_legs (accepted/in_progress)
 *   - faqat id, holat, vaqt, kuryer id, yosh (soat) - mijoz telefoni/manzili/ismi YO'Q
 *   - avtomatik qayta tayinlash/vaqt tugashi YO'Q (faqat o'qish): hujjatlar o'zgarmaydi
 *   - chegaralangan: modul bo'yicha <= 100, so'rov <= 200 (indeks fayli qo'shilmagan)
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-stale-tasks';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require('../index');
const admin = require('firebase-admin');

const db = admin.firestore();

const ADMIN = '998909990000';
const SUPER = '998909990001';
const DISPATCHER = '998909990002';
const STRANGER = '998904440004';
const A = '998901110001';
const B = '998902220002';
const CUSTOMER = '998905550005';
const ADDRESS = 'Gurlan, Navoiy ko\'chasi 7';
const NOW = Date.now();
const ago = (h) => admin.firestore.Timestamp.fromMillis(NOW - Math.round(h * 3600 * 1000));

const ctxOf = (phone) => ({ auth: { uid: `uid_${phone}`, token: { phone_number: `+${phone}` } } });
const list = (data, who = ADMIN) => fns.adminListStaleTasks.run(data, ctxOf(who));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function expectCode(promise, code, httpsCode) {
  await assert.rejects(promise, (e) => {
    const got = (e.details && e.details.code) || e.message;
    assert.strictEqual(got, code, `kod ${got} (${e.code}): ${e.message}`);
    if (httpsCode) assert.strictEqual(e.code, httpsCode);
    return true;
  });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const ids = (r, key) => r.modules[key].items.map((i) => i.id).sort();

async function seed() {
  await clearEmulator();
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(SUPER).set({ role: 'superadmin' });
  await db.collection('users').doc(DISPATCHER).set({ role: 'dispatcher' });
  await db.collection('users').doc(STRANGER).set({ role: 'user' });
  const pii = { userPhone: CUSTOMER, customerPhone: CUSTOMER, customerName: 'Mijoz Ismi', address: ADDRESS, pickupAddress: ADDRESS, note: 'tel 998901234567' };
  // courier orders (orders, type != restaurant)
  await db.collection('orders').doc('o_old').set({ ...pii, type: 'bread', status: 'in_delivery', courierId: A, statusUpdatedAt: ago(5), updatedAt: ago(5) });
  await db.collection('orders').doc('o_fresh').set({ ...pii, type: 'bread', status: 'in_delivery', courierId: A, statusUpdatedAt: ago(1) });
  await db.collection('orders').doc('o_fallback').set({ ...pii, type: 'platform', status: 'in_delivery', courierId: B, updatedAt: ago(4) });
  await db.collection('orders').doc('o_new').set({ ...pii, type: 'bread', status: 'new', courierId: '', statusUpdatedAt: ago(50) });
  // restaurant orders (their legacy status is also in_delivery, but they belong to restaurant_orders)
  await db.collection('orders').doc('r_picked').set({ ...pii, type: 'restaurant', restaurantStatus: 'picked', status: 'in_delivery', courierId: A, statusUpdatedAt: ago(6) });
  await db.collection('orders').doc('r_arrived').set({ ...pii, type: 'restaurant', restaurantStatus: 'arrived', status: 'in_delivery', courierId: B, statusUpdatedAt: ago(3.5) });
  await db.collection('orders').doc('r_ready_courier').set({ ...pii, type: 'restaurant', restaurantStatus: 'ready', status: 'ready', courierId: A, statusUpdatedAt: ago(10) });
  await db.collection('orders').doc('r_ready_nocourier').set({ ...pii, type: 'restaurant', restaurantStatus: 'ready', status: 'ready', courierId: null, statusUpdatedAt: ago(10) });
  await db.collection('orders').doc('r_picked_fresh').set({ ...pii, type: 'restaurant', restaurantStatus: 'picked', status: 'in_delivery', courierId: A, statusUpdatedAt: ago(0.5) });
  await db.collection('orders').doc('r_delivered').set({ ...pii, type: 'restaurant', restaurantStatus: 'delivered', status: 'delivered', courierId: A, statusUpdatedAt: ago(90) });
  // carpet
  const cp = (over) => ({ ...pii, finalPrice: 40000, pickupCourierId: '', returnCourierId: '', ...over });
  await db.collection('carpet_wash_orders').doc('c_pick').set(cp({ status: 'pickup_in_delivery', pickupCourierId: A, updatedAt: ago(8) }));
  await db.collection('carpet_wash_orders').doc('c_ret').set(cp({ status: 'return_in_delivery', returnCourierId: B, updatedAt: ago(7) }));
  await db.collection('carpet_wash_orders').doc('c_acc').set(cp({ status: 'accepted', updatedAt: ago(20) }));
  await db.collection('carpet_wash_orders').doc('c_washing').set(cp({ status: 'washing', updatedAt: ago(99) }));
  await db.collection('carpet_wash_orders').doc('c_fresh').set(cp({ status: 'pickup_in_delivery', pickupCourierId: A, updatedAt: ago(0.2) }));
  // agro
  const ag = (over) => ({ ...pii, finalPrice: 0, ...over });
  await db.collection('agro_pickup_orders').doc('a_pick').set(ag({ status: 'pickup_in_delivery', pickupCourierId: A, updatedAt: ago(9) }));
  await db.collection('agro_pickup_orders').doc('a_acc').set(ag({ status: 'accepted', updatedAt: ago(30) }));
  await db.collection('agro_pickup_orders').doc('a_done').set(ag({ status: 'completed', updatedAt: ago(300) }));
  // relay
  await db.collection('shipments').doc('s_old').set({ status: 'in_transit', ownerId: CUSTOMER, currentCustodian: { kind: 'provider', id: A }, updatedAt: ago(12), recipient: { phone: '998905556677' } });
  await db.collection('shipments').doc('s_fresh').set({ status: 'in_transit', ownerId: CUSTOMER, currentCustodian: { kind: 'provider', id: A }, updatedAt: ago(1) });
  await db.collection('shipments').doc('s_ready').set({ status: 'ready', ownerId: CUSTOMER, updatedAt: ago(100) });
  await db.collection('demands').doc('l_acc').set({ module: 'logistics', status: 'accepted', ownerId: CUSTOMER, assignment: { providerId: B }, updatedAt: ago(15) });
  await db.collection('demands').doc('l_prog').set({ module: 'logistics', status: 'in_progress', ownerId: CUSTOMER, assignment: { providerId: A }, updatedAt: ago(4) });
  await db.collection('demands').doc('l_active').set({ module: 'logistics', status: 'active', ownerId: CUSTOMER, updatedAt: ago(40) });
  await db.collection('demands').doc('d_other').set({ module: 'service', status: 'in_progress', ownerId: CUSTOMER, assignment: { providerId: A }, updatedAt: ago(40) });
}

async function main() {
  await seed();
  const snapshotOf = async () => JSON.stringify([
    (await db.collection('orders').get()).docs.map((d) => d.data()),
    (await db.collection('carpet_wash_orders').get()).docs.map((d) => d.data()),
    (await db.collection('shipments').get()).docs.map((d) => d.data()),
  ].map((x) => JSON.stringify(x)));
  const before = await snapshotOf();

  await check('H1 huquq: faqat admin/superadmin; begona / dispatcher / tokensiz rad', async () => {
    await expectCode(list({}, STRANGER), 'Admin role required', 'permission-denied');
    await expectCode(list({}, DISPATCHER), 'Admin role required', 'permission-denied');
    await assert.rejects(fns.adminListStaleTasks.run({}, {}), (e) => e.code === 'unauthenticated');
    assert.strictEqual((await list({}, SUPER)).ok, true);
  });
  await check('H2 soat: standart 3; 0 -> 1, 1000 -> 168 (qisqartiriladi); "7" qabul; matn / NaN rad', async () => {
    assert.strictEqual((await list({})).hours, 3);
    assert.strictEqual((await list({ hours: null })).hours, 3);
    assert.strictEqual((await list({ hours: 0 })).hours, 1);
    assert.strictEqual((await list({ hours: -5 })).hours, 1);
    assert.strictEqual((await list({ hours: 1000 })).hours, 168);
    assert.strictEqual((await list({ hours: 6.7 })).hours, 7, 'butun soatga yaxlitlanadi');
    assert.strictEqual((await list({ hours: '7' })).hours, 7);
    for (const bad of ['abc', NaN, {}, [], true]) await expectCode(list({ hours: bad }), 'HOURS_INVALID', 'invalid-argument');
  });
  await check('M1 courier_orders: in_delivery va >= 3 soat; restoran buyurtmasi bu yerda EMAS; yangi/yopilgan yo\'q', async () => {
    const r = await list({});
    assert.deepStrictEqual(ids(r, 'courier_orders'), ['o_fallback', 'o_old']);
    const it = r.modules.courier_orders.items.find((i) => i.id === 'o_old');
    assert.deepStrictEqual(Object.keys(it).sort(), ['ageHours', 'courierId', 'id', 'status', 'updatedAtMs']);
    assert.strictEqual(it.status, 'in_delivery');
    assert.strictEqual(it.courierId, A);
    assert.ok(it.ageHours >= 4.9 && it.ageHours < 5.2, `ageHours ${it.ageHours}`);
    assert.ok(Number.isInteger(it.updatedAtMs));
  });
  await check('M2 restaurant_orders: picked/arrived/ready FAQAT kuryerli; kuryersiz ready va yangi yo\'q; eng eskisi birinchi', async () => {
    const r = await list({});
    assert.deepStrictEqual(ids(r, 'restaurant_orders'), ['r_arrived', 'r_picked', 'r_ready_courier']);
    assert.deepStrictEqual(r.modules.restaurant_orders.items.map((i) => i.id), ['r_ready_courier', 'r_picked', 'r_arrived'], 'yosh kamayish tartibida');
    const st = Object.fromEntries(r.modules.restaurant_orders.items.map((i) => [i.id, i.status]));
    assert.deepStrictEqual(st, { r_ready_courier: 'ready', r_picked: 'picked', r_arrived: 'arrived' }, 'restaurantStatus qaytariladi');
  });
  await check('M3 carpet: pickup/return_in_delivery + accepted; kuryer id to\'g\'ri maydondan', async () => {
    const r = await list({});
    assert.deepStrictEqual(ids(r, 'carpet'), ['c_acc', 'c_pick', 'c_ret']);
    const by = Object.fromEntries(r.modules.carpet.items.map((i) => [i.id, i]));
    assert.deepStrictEqual([by.c_pick.courierId, by.c_ret.courierId, by.c_acc.courierId], [A, B, '']);
  });
  await check('M4 agro: pickup_in_delivery + accepted', async () => {
    const r = await list({});
    assert.deepStrictEqual(ids(r, 'agro'), ['a_acc', 'a_pick']);
    assert.strictEqual(r.modules.agro.items.find((i) => i.id === 'a_pick').courierId, A);
  });
  await check('M5 relay: in_transit jo\'natma (>= soat) va accepted/in_progress LEG; boshqa modul demand\'i va active LEG yo\'q', async () => {
    const r = await list({});
    assert.deepStrictEqual(ids(r, 'relay_shipments'), ['s_old']);
    assert.strictEqual(r.modules.relay_shipments.items[0].courierId, A);
    assert.deepStrictEqual(ids(r, 'relay_legs'), ['l_acc', 'l_prog']);
    const by = Object.fromEntries(r.modules.relay_legs.items.map((i) => [i.id, i]));
    assert.deepStrictEqual([by.l_acc.courierId, by.l_prog.courierId, by.l_acc.status, by.l_prog.status], [B, A, 'accepted', 'in_progress']);
  });
  await check('H3 soat chegarasi: 1 soat -> yangilari ham; 9 soat -> faqat juda eskilar', async () => {
    const r1 = await list({ hours: 1 });
    assert.deepStrictEqual(ids(r1, 'courier_orders'), ['o_fallback', 'o_fresh', 'o_old'], '1 soatdan oshgan hammasi');
    assert.deepStrictEqual(ids(r1, 'restaurant_orders'), ['r_arrived', 'r_picked', 'r_ready_courier'], 'r_picked_fresh (0.5 soat) hali yo\'q');
    const r12 = await list({ hours: 9 });
    assert.deepStrictEqual(ids(r12, 'courier_orders'), []);
    assert.deepStrictEqual(ids(r12, 'restaurant_orders'), ['r_ready_courier']);
    assert.deepStrictEqual(ids(r12, 'relay_shipments'), ['s_old']);
    assert.deepStrictEqual(ids(r12, 'relay_legs'), ['l_acc']);
  });
  await check('P1 PII YO\'Q: mijoz telefoni / ismi / manzili / izoh / qabul qiluvchi telefoni javobda yo\'q; faqat belgilangan kalitlar', async () => {
    const r = await list({ hours: 1 });
    const s = JSON.stringify(r);
    for (const bad of [CUSTOMER, 'Mijoz Ismi', ADDRESS, 'Navoiy', '998901234567', '998905556677']) {
      assert.ok(!s.includes(bad), `PII sizdi: ${bad}`);
    }
    for (const m of Object.values(r.modules)) {
      assert.deepStrictEqual(Object.keys(m).sort(), ['items', 'scanned', 'total', 'truncated']);
      for (const it of m.items) assert.deepStrictEqual(Object.keys(it).sort(), ['ageHours', 'courierId', 'id', 'status', 'updatedAtMs']);
    }
  });
  await check('R1 faqat o\'qish: hujjatlar o\'zgarmadi, avtomatik qayta tayinlash/yopish yo\'q', async () => {
    await list({ hours: 1 });
    assert.strictEqual(await snapshotOf(), before);
  });
  await check('L1 chegara: 130 ta eski buyurtma -> 100 ta qaytadi, total 130, truncated true; eng eskisi birinchi', async () => {
    const batch = db.batch();
    for (let i = 0; i < 130; i += 1) {
      batch.set(db.collection('orders').doc(`bulk${String(i).padStart(3, '0')}`), {
        type: 'bread', status: 'in_delivery', courierId: A, statusUpdatedAt: ago(10 + i / 10),
      });
    }
    await batch.commit();
    const r = await list({});
    const m = r.modules.courier_orders;
    assert.strictEqual(m.items.length, 100);
    assert.strictEqual(m.total, 132);
    assert.strictEqual(m.truncated, true);
    assert.ok(m.items[0].ageHours >= m.items[99].ageHours, 'yoshi katta birinchi');
    assert.strictEqual(r.modules.carpet.truncated, false);
  });
  await check('L2 so\'rov chegarasi: 250 ta in_delivery bo\'lsa ham <= 200 hujjat o\'qiladi (scanned), truncated true', async () => {
    const batch = db.batch();
    for (let i = 0; i < 120; i += 1) {
      batch.set(db.collection('orders').doc(`bulkb${String(i).padStart(3, '0')}`), {
        type: 'bread', status: 'in_delivery', courierId: B, statusUpdatedAt: ago(20),
      });
    }
    await batch.commit();
    const r = await list({});
    assert.ok(r.modules.courier_orders.scanned <= 200, `scanned ${r.modules.courier_orders.scanned}`);
    assert.strictEqual(r.modules.courier_orders.truncated, true);
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
