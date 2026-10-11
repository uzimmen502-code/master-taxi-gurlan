/**
 * Kafe-restoran Firestore rules (D-REST, docs/kafe_restoran_taklifi_uz.md §11.6).
 *
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/restaurant_rules.test.js"
 *
 * Qulflanadi:
 *   - `restaurants`: create faqat CF; approved — hamma o'qiydi (loginsiz ham),
 *     applied — faqat a'zo/admin; list faqat `status == approved` yoki
 *     `ownerUid == men` filtri bilan; a'zo profil whitelist'ini yozadi,
 *     `status`/`ownerUid`/rating ni YOZOLMAYDI; begona hech narsa yozolmaydi
 *   - `members`: a'zo o'qiydi, hech kim yozmaydi
 *   - `private/payment`: a'zo/finance/admin o'qiydi, begona yo'q
 *   - `menu_items`: approved restoran menyusi ochiq; applied — yopiq;
 *     narx `int` > 0; begona kalit rad
 *   - `orders`: restoran a'zosi o'z restoranining buyurtmasini o'qiydi
 *     (get va `where restaurantId ==` list), boshqa restoran a'zosi — yo'q;
 *     filtrsiz list — yo'q; a'zo buyurtmani yozolmaydi
 *   - `order_events`: egasi/a'zo/staff o'qiydi; `private/secrets`: faqat a'zo
 *   - `restaurant_customer_stats` / `restaurant_courier_prefs`: faqat o'ziniki
 */
'use strict';
const path = require('path');
const fs = require('fs');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const ADMIN = '998901110000';
const FINANCE = '998901120000';
const OWNER = '998911000001';
const STAFF = '998911000002';
const OWNER2 = '998911000003';
const CUSTOMER = '998912000001';
const COURIER = '998913000001';
const STRANGER = '998914000001';
const R1 = 'rest_approved';
const R2 = 'rest_applied';
const O1 = 'order_r1';

async function main() {
  console.log(`rules: ${RULES_PATH}`);
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-restaurants',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const record = (name, pass, detail) => {
    results.push({ name, pass });
    console.log(`${pass ? 'PASS' : 'FAIL'} - ${name}${detail ? ' :: ' + detail : ''}`);
  };
  async function check(name, fn) {
    try { await fn(); record(name, true); } catch (e) { record(name, false, e.message); }
  }
  const as = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const anon = () => testEnv.unauthenticatedContext().firestore();

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
    await db.doc(`users/${FINANCE}`).set({ role: 'finance' });
    for (const u of [OWNER, STAFF, OWNER2, CUSTOMER, COURIER, STRANGER]) await db.doc(`users/${u}`).set({ role: 'user' });
    await db.doc(`restaurants/${R1}`).set({
      name: 'Gurlan osh', status: 'approved', ownerUid: OWNER, walletUserDocId: OWNER, prepTimeMin: 20,
      minOrderAmount: 30000, delivery: { mode: 'ava_courier', pickup: true }, payment: { prepay: true, cash: true },
      ratingAvg: 4.5, ratingCount: 10, lat: 41.84, lng: 60.39,
    });
    await db.doc(`restaurants/${R1}/members/${OWNER}`).set({ role: 'owner' });
    await db.doc(`restaurants/${R1}/members/${STAFF}`).set({ role: 'staff' });
    await db.doc(`restaurants/${R1}/private/payment`).set({ cardNumber: '8600123412341234', cardHolder: 'OSHPAZ' });
    await db.doc(`restaurants/${R1}/menu_items/osh`).set({ name: 'Osh', price: 40000, available: true, categoryId: 'c1', sort: 1 });
    await db.doc(`restaurants/${R1}/menu_categories/c1`).set({ name: 'Asosiy', sort: 1 });
    await db.doc(`restaurants/${R2}`).set({
      name: 'Yangi kafe', status: 'applied', ownerUid: OWNER2, walletUserDocId: OWNER2, prepTimeMin: 20,
      minOrderAmount: 0, delivery: { mode: 'own_courier', pickup: false }, payment: { prepay: true, cash: true },
    });
    await db.doc(`restaurants/${R2}/members/${OWNER2}`).set({ role: 'owner' });
    await db.doc(`restaurants/${R2}/menu_items/somsa`).set({ name: 'Somsa', price: 10000, available: true });
    await db.doc(`orders/${O1}`).set({
      type: 'restaurant', restaurantId: R1, restaurantStatus: 'accepted', status: 'accepted', fulfillmentStatus: 'confirmed',
      userPhone: CUSTOMER, phone: CUSTOMER, address: 'Mijoz uyi', total: 60000, courierId: null, deliveryRouteId: null,
    });
    await db.doc(`orders/${O1}/order_events/e1`).set({ from: null, to: 'placed', actor: 'customer' });
    await db.doc(`orders/${O1}/private/secrets`).set({ pickupCode: '1234', pickupAttempts: 0 });
    await db.doc(`restaurant_customer_stats/${CUSTOMER}`).set({ strikes: 0, completedCount: 1 });
    await db.doc(`restaurant_courier_prefs/${COURIER}`).set({ buyoutEnabled: true, buyoutLimit: 100000 });
    await db.doc('settings/restaurant_delivery').set({ base: 5000, perKm: 1500, version: 1 });
    await db.doc('restaurant_delivery_tariffs/v1').set({ version: 1, base: 5000, perKm: 1500 });
  });

  // ── restaurants ────────────────────────────────────────────────────
  await check('approved restoranni loginsiz ham o\'qish mumkin; applied — yo\'q', async () => {
    await assertSucceeds(anon().doc(`restaurants/${R1}`).get());
    await assertFails(anon().doc(`restaurants/${R2}`).get());
    await assertFails(as(STRANGER).doc(`restaurants/${R2}`).get());
  });
  await check('applied restoranni a\'zosi va admin o\'qiydi', async () => {
    await assertSucceeds(as(OWNER2).doc(`restaurants/${R2}`).get());
    await assertSucceeds(as(ADMIN).doc(`restaurants/${R2}`).get());
  });
  await check('list: `status == approved` filtri bilan ha; filtrsiz yo\'q; `ownerUid == men` ha', async () => {
    await assertSucceeds(as(STRANGER).collection('restaurants').where('status', '==', 'approved').get());
    await assertSucceeds(anon().collection('restaurants').where('status', '==', 'approved').get());
    await assertFails(as(STRANGER).collection('restaurants').get());
    await assertFails(as(STRANGER).collection('restaurants').where('status', '==', 'applied').get());
    await assertSucceeds(as(OWNER2).collection('restaurants').where('ownerUid', '==', OWNER2).get());
    await assertFails(as(STRANGER).collection('restaurants').where('ownerUid', '==', OWNER2).get());
    await assertSucceeds(as(ADMIN).collection('restaurants').get());
  });
  // Geo 4-bosqich (D-GEO-4): «yaqindagilar» — geohash prefiksi bo'yicha
  // (`RestaurantsRepository.watchNearby`). status filtrisiz — yo'q.
  await check('yaqindagilar: approved + geohash prefiks diapazoni ha; status filtrisiz yo\'q', async () => {
    await assertSucceeds(as(STRANGER).collection('restaurants')
      .where('status', '==', 'approved').orderBy('geohash').startAt('txp7').endAt('txp7~').limit(50).get());
    await assertSucceeds(anon().collection('restaurants')
      .where('status', '==', 'approved').orderBy('geohash').startAt('txp7').endAt('txp7~').get());
    await assertFails(as(STRANGER).collection('restaurants')
      .orderBy('geohash').startAt('txp7').endAt('txp7~').get());
  });
  await check('restoran yaratish — hech kim (faqat CF)', async () => {
    await assertFails(as(OWNER).doc('restaurants/new1').set({ name: 'X', status: 'approved', ownerUid: OWNER }));
    await assertFails(as(ADMIN).doc('restaurants/new2').set({ name: 'X', status: 'approved' }));
  });
  await check('a\'zo profilni yozadi (whitelist); status/ownerUid/rating — yo\'q; begona — yo\'q', async () => {
    await assertSucceeds(as(STAFF).doc(`restaurants/${R1}`).update({ name: 'Gurlan osh markazi', announcement: 'Bugun osh 12:00', updatedAt: new Date() }));
    await assertSucceeds(as(OWNER).doc(`restaurants/${R1}`).update({ delivery: { mode: 'own_courier', pickup: true, ownFee: { type: 'fixed', fixed: 7000 } } }));
    await assertFails(as(OWNER).doc(`restaurants/${R1}`).update({ status: 'suspended' }));
    await assertFails(as(OWNER2).doc(`restaurants/${R2}`).update({ status: 'approved' }), 'o\'zini tasdiqlash');
    await assertFails(as(OWNER).doc(`restaurants/${R1}`).update({ ownerUid: STRANGER }));
    await assertFails(as(OWNER).doc(`restaurants/${R1}`).update({ ratingAvg: 5 }));
    await assertFails(as(OWNER).doc(`restaurants/${R1}`).update({ walletUserDocId: STRANGER }));
    await assertFails(as(STRANGER).doc(`restaurants/${R1}`).update({ name: 'Hack' }));
    await assertFails(as(OWNER).doc(`restaurants/${R1}`).update({ name: 'X' }), 'nom qisqa');
    await assertFails(as(OWNER).doc(`restaurants/${R1}`).update({ prepTimeMin: '20' }), 'satr');
    await assertFails(as(OWNER).doc(`restaurants/${R1}`).update({ minOrderAmount: -1 }));
    await assertFails(as(OWNER).doc(`restaurants/${R1}`).update({ delivery: { mode: 'drone' } }));
    await assertFails(as(OWNER).doc(`restaurants/${R1}`).delete());
  });
  await check('members: a\'zo o\'qiydi, begona yo\'q, hech kim yozmaydi', async () => {
    await assertSucceeds(as(STAFF).doc(`restaurants/${R1}/members/${OWNER}`).get());
    await assertSucceeds(as(ADMIN).collection(`restaurants/${R1}/members`).get());
    await assertFails(as(STRANGER).doc(`restaurants/${R1}/members/${OWNER}`).get());
    await assertFails(as(OWNER).doc(`restaurants/${R1}/members/${STRANGER}`).set({ role: 'staff' }));
    await assertFails(as(STRANGER).doc(`restaurants/${R1}/members/${STRANGER}`).set({ role: 'owner' }));
  });
  await check('private/payment: a\'zo, finance, admin o\'qiydi; begona/mijoz yo\'q; a\'zo whitelist bilan yozadi', async () => {
    await assertSucceeds(as(STAFF).doc(`restaurants/${R1}/private/payment`).get());
    await assertSucceeds(as(FINANCE).doc(`restaurants/${R1}/private/payment`).get());
    await assertSucceeds(as(ADMIN).doc(`restaurants/${R1}/private/payment`).get());
    await assertFails(as(STRANGER).doc(`restaurants/${R1}/private/payment`).get());
    await assertFails(as(CUSTOMER).doc(`restaurants/${R1}/private/payment`).get());
    await assertFails(anon().doc(`restaurants/${R1}/private/payment`).get());
    await assertSucceeds(as(OWNER).doc(`restaurants/${R1}/private/payment`).set({ cardNumber: '8600000000000001', cardHolder: 'A', updatedAt: new Date() }));
    await assertFails(as(OWNER).doc(`restaurants/${R1}/private/payment`).set({ cardNumber: '8600000000000001', balance: 1 }));
    await assertFails(as(STRANGER).doc(`restaurants/${R1}/private/payment`).set({ cardNumber: '8600000000000002' }));
    await assertSucceeds(as(OWNER).doc(`restaurants/${R1}/private/legal`).set({ tin: '123456789', updatedAt: new Date() }));
    await assertFails(as(OWNER).doc(`restaurants/${R1}/private/other`).set({ x: 1 }));
  });
  await check('menu: approved menyu loginsiz ochiq; applied menyu faqat a\'zoga; a\'zo yozadi, narx int > 0, begona kalit yo\'q', async () => {
    await assertSucceeds(anon().doc(`restaurants/${R1}/menu_items/osh`).get());
    await assertSucceeds(anon().collection(`restaurants/${R1}/menu_items`).get());
    await assertFails(anon().doc(`restaurants/${R2}/menu_items/somsa`).get());
    await assertFails(as(STRANGER).collection(`restaurants/${R2}/menu_items`).get());
    await assertSucceeds(as(OWNER2).collection(`restaurants/${R2}/menu_items`).get());
    await assertSucceeds(as(STAFF).doc(`restaurants/${R1}/menu_items/lagmon`).set({ name: 'Lag\'mon', price: 35000, available: true, packagingFee: 500, categoryId: 'c1', sort: 2, description: 'Uyg\'ur' }));
    await assertSucceeds(as(STAFF).doc(`restaurants/${R1}/menu_items/lagmon`).update({ available: false, stopUntil: new Date(Date.now() + 3600000) }));
    await assertFails(as(STAFF).doc(`restaurants/${R1}/menu_items/x1`).set({ name: 'X', price: '35000' }), 'narx satr');
    await assertFails(as(STAFF).doc(`restaurants/${R1}/menu_items/x2`).set({ name: 'X', price: 0 }), 'narx 0');
    await assertFails(as(STAFF).doc(`restaurants/${R1}/menu_items/x3`).set({ name: 'X', price: 35000.5 }), 'float');
    await assertFails(as(STAFF).doc(`restaurants/${R1}/menu_items/x4`).set({ name: 'X', price: 35000, sold: 99 }), 'begona kalit');
    await assertFails(as(STAFF).doc(`restaurants/${R1}/menu_items/x5`).set({ name: '', price: 35000 }), 'nom bo\'sh');
    await assertFails(as(STRANGER).doc(`restaurants/${R1}/menu_items/x6`).set({ name: 'X', price: 35000 }));
    await assertFails(as(OWNER2).doc(`restaurants/${R1}/menu_items/x7`).set({ name: 'X', price: 35000 }), 'boshqa restoran egasi');
    await assertSucceeds(as(STAFF).doc(`restaurants/${R1}/menu_items/lagmon`).delete());
    await assertSucceeds(as(STAFF).doc(`restaurants/${R1}/menu_categories/c2`).set({ name: 'Ichimlik', sort: 2 }));
    await assertFails(as(STAFF).doc(`restaurants/${R1}/menu_categories/c3`).set({ name: 'X', price: 1 }));
  });

  await check('D-REST-15: BOSHQA restoran egasi (OWNER2, o\'z restorani bor) R1 ga rid orqali tegolmaydi — profil, private/payment, members, menyu, kategoriya, list', async () => {
    await assertFails(as(OWNER2).doc(`restaurants/${R1}`).update({ name: 'Raqib nomi' }));
    await assertFails(as(OWNER2).doc(`restaurants/${R1}`).update({ delivery: { mode: 'own_courier', pickup: true } }));
    await assertFails(as(OWNER2).doc(`restaurants/${R1}/private/payment`).get());
    await assertFails(as(OWNER2).doc(`restaurants/${R1}/private/payment`).set({ cardNumber: '8600999999999999', cardHolder: 'RAQIB' }));
    await assertFails(as(OWNER2).doc(`restaurants/${R1}/private/legal`).set({ tin: '000' }));
    await assertFails(as(OWNER2).doc(`restaurants/${R1}/members/${OWNER}`).get());
    await assertFails(as(OWNER2).doc(`restaurants/${R1}/members/${OWNER2}`).set({ role: 'owner' }), 'o\'zini a\'zo qilish');
    await assertFails(as(OWNER2).doc(`restaurants/${R1}/menu_items/osh`).update({ price: 1 }));
    await assertFails(as(OWNER2).doc(`restaurants/${R1}/menu_items/osh`).delete());
    await assertFails(as(OWNER2).doc(`restaurants/${R1}/menu_categories/c1`).update({ name: 'X' }));
    await assertFails(as(OWNER2).doc(`restaurants/${R1}/menu_categories/c9`).set({ name: 'Yangi', sort: 9 }));
    await assertFails(as(OWNER2).collection('restaurants').where('ownerUid', '==', OWNER).get());
    // O'ziniki — ishlaydi (nazorat).
    await assertSucceeds(as(OWNER2).doc(`restaurants/${R2}`).update({ announcement: 'Tez kunda' }));
    await assertSucceeds(as(OWNER2).doc(`restaurants/${R2}/menu_items/somsa`).update({ available: false }));
  });

  // ── orders ─────────────────────────────────────────────────────────
  await check('orders: restoran a\'zosi get + `where restaurantId ==` list; filtrsiz/boshqa restoran/begona — yo\'q', async () => {
    await assertSucceeds(as(STAFF).doc(`orders/${O1}`).get());
    await assertSucceeds(as(OWNER).collection('orders').where('restaurantId', '==', R1).get());
    await assertFails(as(OWNER).collection('orders').get());
    await assertFails(as(OWNER).collection('orders').where('type', '==', 'restaurant').get());
    await assertFails(as(OWNER2).doc(`orders/${O1}`).get(), 'boshqa restoran egasi');
    await assertFails(as(OWNER2).collection('orders').where('restaurantId', '==', R1).get());
    await assertFails(as(STRANGER).doc(`orders/${O1}`).get());
    await assertFails(as(COURIER).doc(`orders/${O1}`).get(), 'olmagan kuryer');
    await assertSucceeds(as(CUSTOMER).doc(`orders/${O1}`).get(), 'egasi');
    await assertSucceeds(as(ADMIN).doc(`orders/${O1}`).get());
  });
  await check('orders: a\'zo buyurtmani YOZOLMAYDI (holat faqat CF)', async () => {
    await assertFails(as(OWNER).doc(`orders/${O1}`).update({ restaurantStatus: 'delivered' }));
    await assertFails(as(OWNER).doc(`orders/${O1}`).update({ status: 'ready' }));
    await assertFails(as(CUSTOMER).doc(`orders/${O1}`).update({ total: 1 }));
    await assertFails(as(OWNER).doc('orders/new_rest').set({ type: 'restaurant', restaurantId: R1, userPhone: CUSTOMER }));
  });
  await check('order_events: egasi/a\'zo/admin o\'qiydi; begona yo\'q; yozish yo\'q', async () => {
    await assertSucceeds(as(CUSTOMER).collection(`orders/${O1}/order_events`).get());
    await assertSucceeds(as(STAFF).collection(`orders/${O1}/order_events`).get());
    await assertSucceeds(as(ADMIN).collection(`orders/${O1}/order_events`).get());
    await assertFails(as(STRANGER).collection(`orders/${O1}/order_events`).get());
    await assertFails(as(OWNER2).collection(`orders/${O1}/order_events`).get());
    await assertFails(as(OWNER).doc(`orders/${O1}/order_events/e9`).set({ to: 'delivered' }));
  });
  await check('private/secrets (pickupCode): faqat restoran a\'zosi va admin; mijoz/kuryer yo\'q', async () => {
    await assertSucceeds(as(STAFF).doc(`orders/${O1}/private/secrets`).get());
    await assertSucceeds(as(ADMIN).doc(`orders/${O1}/private/secrets`).get());
    await assertFails(as(CUSTOMER).doc(`orders/${O1}/private/secrets`).get());
    await assertFails(as(COURIER).doc(`orders/${O1}/private/secrets`).get());
    await assertFails(as(OWNER2).doc(`orders/${O1}/private/secrets`).get());
    await assertFails(as(OWNER).doc(`orders/${O1}/private/secrets`).update({ pickupCode: '0000' }));
  });
  await check('stats / prefs: faqat o\'ziniki o\'qiladi, yozilmaydi', async () => {
    await assertSucceeds(as(CUSTOMER).doc(`restaurant_customer_stats/${CUSTOMER}`).get());
    await assertFails(as(STRANGER).doc(`restaurant_customer_stats/${CUSTOMER}`).get());
    await assertFails(as(CUSTOMER).doc(`restaurant_customer_stats/${CUSTOMER}`).update({ strikes: 0 }));
    await assertSucceeds(as(COURIER).doc(`restaurant_courier_prefs/${COURIER}`).get());
    await assertFails(as(COURIER).doc(`restaurant_courier_prefs/${COURIER}`).set({ buyoutEnabled: true, buyoutLimit: 999999999 }));
    await assertFails(as(STRANGER).doc(`restaurant_courier_prefs/${COURIER}`).get());
  });
  await check('yetkazish tarifi: o\'qish ochiq; to\'g\'ridan-to\'g\'ri yozish ADMIN uchun ham yo\'q (faqat CF); tarix faqat admin o\'qiydi, hech kim yozmaydi', async () => {
    await assertSucceeds(as(ADMIN).doc('settings/restaurant_delivery').get());
    await assertSucceeds(as(CUSTOMER).doc('settings/restaurant_delivery').get());
    await assertFails(as(ADMIN).doc('settings/restaurant_delivery').update({ base: 1 }));
    await assertFails(as(ADMIN).doc('settings/restaurant_delivery').set({ base: 1, perKm: 1, version: 9 }));
    await assertSucceeds(as(ADMIN).doc('restaurant_delivery_tariffs/v1').get());
    await assertSucceeds(as(ADMIN).collection('restaurant_delivery_tariffs').get());
    await assertFails(as(STRANGER).doc('restaurant_delivery_tariffs/v1').get());
    await assertFails(as(ADMIN).doc('restaurant_delivery_tariffs/v2').set({ version: 2 }));
    await assertSucceeds(as(ADMIN).doc('module_config/restaurants_all').get());
  });

  await testEnv.cleanup();
  const passed = results.filter((r) => r.pass).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
