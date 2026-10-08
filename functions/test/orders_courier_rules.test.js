/**
 * `orders` Firestore rules — kuryer (capability) va buyurtma o'qish.
 *
 * Muammo (2026-10-08): D-SERVICE-4 / D-CLEAN-1 `courier`ni `isStaff()`dan
 * olib tashladi (jonli qoidada 2026-10-06 13:21 UTC dan beri), `orders`
 * o'qish qoidasi esa faqat `isStaff()` yoki `userPhone` egasini
 * tanirdi. Natijada `role: 'user'` + tasdiqlangan courier capability'li
 * kuryer:
 *   1) MFY ekranida `orders where status == 'ready'` ro'yxatini ololmaydi
 *      (`OrdersRepository.watchReadyOrders`, `courier_mfy_selection_screen`);
 *   2) o'z marshrutidagi buyurtmalarni ham o'qiy olmaydi
 *      (`CourierController._applyRoute` → `getByIds(route.orderIds)`).
 *
 * Tuzatish:
 *   1) ro'yxat qoida orqali OCHILMAYDI — qoida maydonlarni kesa olmaydi,
 *      ochilsa har bir kuryer HAMMA `ready` buyurtmaning telefoni, ismi,
 *      manzili va savatini olardi (40-qoida). Ro'yxat `courierListReadyOrders`
 *      callable orqali, faqat id/MFY/koordinata bilan
 *      (`functions/test/courier_orders_cf.test.js`).
 *   2) `get` — buyurtma kuryerning FAOL marshrutida bo'lsa
 *      (`courierId` + `deliveryRouteId` → `delivery_routes` `ready|active`,
 *      marshrut egasi ham shu kuryer). `list` bu yo'ldan o'tmaydi.
 *
 * Ishlatish: repo ildizidan
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/orders_courier_rules.test.js"
 * Jonli qoidaga qarshi: `RULES_FILE=<yuklab olingan fayl>` bilan.
 */
'use strict';
const path = require('path');
const fs = require('fs');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_FILE
  || path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const ADMIN = '998901112233';
const DISPATCHER = '998901112244';
const COURIER = '998905556677';
const COURIER_ACC = 'accCOURIER0000000000A';
const OTHER = '998907778899';
const OTHER_ACC = 'accCOURIER0000000000B';
/** Eski `role: 'courier'` — capability'siz (D-CLEAN-1 dan keyin huquq yo'q). */
const LEGACY = '998906660000';
const CUSTOMER = '998909990000';
const STRANGER = '998904445566';

function order(over = {}) {
  return {
    type: 'bread', userName: 'Mijoz', userPhone: CUSTOMER, phone: CUSTOMER,
    address: 'Gurlan, Navoiy ko\'chasi 1', mfy: 'Navoiy', lat: 41.84, lng: 60.39,
    items: [{ name: 'Non', count: 2, price: 5000 }], total: 10000,
    status: 'ready', fulfillmentStatus: 'confirmed', createdAt: new Date(),
    ...over,
  };
}

async function main() {
  console.log(`rules: ${RULES_PATH}`);
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-orders-courier',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });

  const results = [];
  const record = (name, pass, detail) => {
    results.push({ name, pass, detail });
    console.log(`${pass ? 'PASS' : 'FAIL'} - ${name}${detail ? ' :: ' + detail : ''}`);
  };
  async function check(name, fn) {
    try { await fn(); record(name, true); } catch (e) { record(name, false, e.message); }
  }

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('users').doc(ADMIN).set({ role: 'admin' });
    await db.collection('users').doc(DISPATCHER).set({ role: 'dispatcher' });
    for (const [phone, acc] of [[COURIER, COURIER_ACC], [OTHER, OTHER_ACC]]) {
      await db.collection('users').doc(phone).set({ role: 'user', accountId: acc });
      await db.collection('provider_capabilities').doc(acc).set({
        identity: { accountId: acc, primaryUid: phone },
        courier: { active: true },
        status: { courier: 'approved' },
      });
    }
    await db.collection('users').doc(LEGACY).set({ role: 'courier' });
    await db.collection('users').doc(CUSTOMER).set({ role: 'user' });
    await db.collection('users').doc(STRANGER).set({ role: 'user' });

    const orders = db.collection('orders');
    await orders.doc('o_ready').set(order());
    await orders.doc('o_ready_2').set(order({ mfy: 'Yangiobod' }));
    // Kuryerning FAOL marshrutida (server `courierCreateRoute` yozgan shakl).
    await orders.doc('o_mine').set(order({
      status: 'in_delivery', fulfillmentStatus: 'courier_picked',
      courierId: COURIER, deliveryRouteId: 'r_mine',
    }));
    // Yetkazilgan, lekin marshrut hali faol (`getByIds` uni ham o'qiydi).
    await orders.doc('o_mine_done').set(order({
      status: 'delivered', fulfillmentStatus: 'completed', paymentStatus: 'paid',
      courierId: COURIER, deliveryRouteId: 'r_mine',
    }));
    // Eski 9 xonali `courierId` shakli.
    await orders.doc('o_mine9').set(order({
      status: 'in_delivery', courierId: COURIER.slice(3), deliveryRouteId: 'r_mine9',
    }));
    // Marshrut tugagan — endi o'qilmaydi.
    await orders.doc('o_old').set(order({
      status: 'delivered', courierId: COURIER, deliveryRouteId: 'r_old',
    }));
    await orders.doc('o_theirs').set(order({
      status: 'in_delivery', courierId: OTHER, deliveryRouteId: 'r_theirs',
    }));
    // `courierId` meniki, lekin marshrut boshqaniki — mos kelmaydi.
    await orders.doc('o_mismatch').set(order({
      status: 'in_delivery', courierId: COURIER, deliveryRouteId: 'r_theirs',
    }));
    await orders.doc('o_no_route').set(order({ status: 'in_delivery', courierId: COURIER }));

    const routes = db.collection('delivery_routes');
    await routes.doc('r_mine').set({
      courierId: COURIER, status: 'active', orders: ['o_mine', 'o_mine_done'], currentIndex: 0,
    });
    await routes.doc('r_mine9').set({
      courierId: COURIER.slice(3), status: 'active', orders: ['o_mine9'], currentIndex: 0,
    });
    await routes.doc('r_old').set({ courierId: COURIER, status: 'completed', orders: ['o_old'] });
    await routes.doc('r_theirs').set({ courierId: OTHER, status: 'active', orders: ['o_theirs'] });
  });

  const ctxFor = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: '+' + phone });
  const unauth = testEnv.unauthenticatedContext().firestore();
  const courier = ctxFor(COURIER).firestore();
  const other = ctxFor(OTHER).firestore();
  const legacy = ctxFor(LEGACY).firestore();
  const customer = ctxFor(CUSTOMER).firestore();
  const stranger = ctxFor(STRANGER).firestore();
  const dispatcher = ctxFor(DISPATCHER).firestore();
  const adminDb = ctxFor(ADMIN).firestore();
  const doc = (db, id) => db.collection('orders').doc(id);
  const readyList = (db) => db.collection('orders').where('status', '==', 'ready').get();

  // ── `ready` ro'yxati (`watchReadyOrders`) ────────────────────────────
  await check('capability kuryer: `status == ready` ro\'yxati to\'g\'ridan-to\'g\'ri RAD (PII) — callable orqali',
    () => assertFails(readyList(courier)));
  await check('capability kuryer: olinmagan `ready` buyurtmani get qila olmaydi (telefon/manzil)',
    () => assertFails(doc(courier, 'o_ready').get()));
  await check('eski `role: courier` (capability\'siz) ham ro\'yxatni ololmaydi',
    () => assertFails(readyList(legacy)));
  await check('oddiy foydalanuvchi ro\'yxatni ololmaydi', () => assertFails(readyList(stranger)));
  await check('dispatcher (staff) ro\'yxatni oladi — so\'rov shakli to\'g\'ri, gap faqat huquqda',
    () => assertSucceeds(readyList(dispatcher)));
  await check('admin ro\'yxatni oladi (admin kuryer doskasi)', () => assertSucceeds(readyList(adminDb)));

  // ── O'z FAOL marshrutidagi buyurtmalar (`getByIds`) ──────────────────
  await check('kuryer o\'z faol marshrutidagi buyurtmani o\'qiydi',
    () => assertSucceeds(doc(courier, 'o_mine').get()));
  await check('kuryer marshrutdagi yetkazilgan buyurtmani ham o\'qiydi (marshrut hali faol)',
    () => assertSucceeds(doc(courier, 'o_mine_done').get()));
  await check('9 xonali `courierId` / marshrut kaliti ham taniladi',
    () => assertSucceeds(doc(courier, 'o_mine9').get()));
  await check('marshrut tugagan — kuryer endi o\'qiy olmaydi',
    () => assertFails(doc(courier, 'o_old').get()));
  await check('boshqa kuryerning buyurtmasini o\'qiy olmaydi',
    () => assertFails(doc(courier, 'o_theirs').get()));
  await check('`courierId` meniki, marshrut boshqaniki — rad',
    () => assertFails(doc(courier, 'o_mismatch').get()));
  await check('`deliveryRouteId`siz buyurtma — rad', () => assertFails(doc(courier, 'o_no_route').get()));
  await check('kuryer `courierId == men` ro\'yxatini ololmaydi (faqat get)',
    () => assertFails(courier.collection('orders').where('courierId', '==', COURIER).get()));
  await check('begona kuryer meniki marshrutdagi buyurtmani o\'qiy olmaydi',
    () => assertFails(doc(other, 'o_mine').get()));
  await check('oddiy foydalanuvchi kuryer buyurtmasini o\'qiy olmaydi',
    () => assertFails(doc(stranger, 'o_mine').get()));
  await check('autentifikatsiyasiz o\'qiy olmaydi', () => assertFails(doc(unauth, 'o_mine').get()));

  // ── Mijoz oqimi o'zgarmadi ───────────────────────────────────────────
  await check('mijoz o\'z buyurtmasini o\'qiydi', () => assertSucceeds(doc(customer, 'o_ready').get()));
  await check('mijoz o\'z buyurtmalari ro\'yxatini oladi (recentByPhone)',
    () => assertSucceeds(customer.collection('orders').where('userPhone', '==', CUSTOMER).get()));

  // ── Yozish o'zgarmadi: kuryer holatni faqat callable orqali o'zgartiradi ──
  await check('kuryer o\'z buyurtmasi holatini to\'g\'ridan-to\'g\'ri yoza olmaydi',
    () => assertFails(doc(courier, 'o_mine').update({ status: 'delivered' })));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} orders courier rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
