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
    for (const [id, st] of [['live_picked', 'picked'], ['live_accepted', 'accepted'], ['live_placed', 'placed'], ['live_delivered', 'delivered']]) {
      await db.doc(`orders/${id}`).set({
        type: 'restaurant', restaurantId: R1, restaurantStatus: st, userPhone: CUSTOMER, courierId: COURIER, courierName: 'Ali',
      });
    }
    await db.doc('orders/live_bread').set({ type: 'bread', restaurantStatus: 'picked', userPhone: CUSTOMER, courierId: COURIER });
    // Нон/бозор буюртмаси: курьер олгач (courier_picked) ва етгач (arrived) — фаол; completed — йўқ.
    await db.doc('orders/live_bread_picked').set({ type: 'bread', fulfillmentStatus: 'courier_picked', status: 'in_delivery', userPhone: CUSTOMER, courierId: COURIER });
    await db.doc('orders/live_market_arrived').set({ type: 'platform', fulfillmentStatus: 'arrived', status: 'in_delivery', userPhone: CUSTOMER, courierId: COURIER });
    await db.doc('orders/live_bread_ready').set({ type: 'bread', fulfillmentStatus: 'ready', status: 'ready', userPhone: CUSTOMER, courierId: COURIER });
    await db.doc('orders/live_bread_done').set({ type: 'bread', fulfillmentStatus: 'completed', status: 'delivered', userPhone: CUSTOMER, courierId: COURIER });
    await db.doc('orders/live_other_type').set({ type: 'carpet', fulfillmentStatus: 'courier_picked', userPhone: CUSTOMER, courierId: COURIER });
    await db.doc(`orders/${O1}/order_events/e1`).set({ from: null, to: 'placed', actor: 'customer' });
    await db.doc(`orders/${O1}/private/secrets`).set({ pickupCode: '1234', pickupAttempts: 0 });
    await db.doc(`restaurant_customer_stats/${CUSTOMER}`).set({ strikes: 0, completedCount: 1 });
    await db.doc(`restaurant_courier_prefs/${COURIER}`).set({ buyoutEnabled: true, buyoutLimit: 100000 });
    await db.doc(`restaurants/${R1}/menu_item_stats/osh`).set({ ratingSum: 9, ratingCount: 2 });
    await db.doc(`restaurants/${R2}/menu_item_stats/somsa`).set({ ratingSum: 5, ratingCount: 1 });
    await db.doc(`restaurant_dish_ratings/${O1}_osh`).set({ orderId: O1, itemId: 'osh', restaurantId: R1, userId: CUSTOMER, stars: 5 });
    await db.doc(`restaurant_dish_index/${R1}_osh`).set({ restaurantId: R1, itemId: 'osh', sections: ['cheap'], geo4: 'tzh1', price: 40000 });
    await db.doc('settings/restaurant_sections').set({ version: 1, sections: { cheap: 'public' }, cheapRatingThreshold: 5 });
    await db.doc('restaurant_sections_history/v1').set({ version: 1 });
    await db.doc('restaurant_cuisines/national_ozbek').set({ name: 'Ўзбек', group: 'national', hidden: false });
    await db.doc('restaurant_cuisines/world_turk').set({ name: 'Турк', group: 'world', hidden: false });
    await db.doc('restaurant_bookings/bk1').set({ restaurantId: R1, userPhone: CUSTOMER, guests: 4, status: 'requested', fee: { amount: 50000, charged: false } });
    await db.doc('restaurant_bookings/bk1/events/e1').set({ to: 'requested', actor: 'customer' });
    await db.doc('restaurant_bookings/bk2').set({ restaurantId: R2, userPhone: STRANGER, guests: 2, status: 'requested', fee: { amount: 50000, charged: false } });
    await db.doc('settings/restaurant_bookings').set({ version: 1, stage: 'public', tiers: [{ upTo: 5, fee: 50000 }] });
    await db.doc('restaurant_bookings_history/v1').set({ version: 1 });
    await db.doc('settings/restaurant_seasons').set({ version: 1, periods: [{ key: 'ramadan', from: '2027-02-09', to: '2027-03-09', confirmed: true }], opensDaysBefore: 10 });
    await db.doc('settings/restaurant_ramadan').set({ version: 1, days: {}, offsets: { toshkent: 0 } });
    await db.doc('restaurant_seasons_history/v1').set({ version: 1 });
    await db.doc('restaurant_ramadan_history/v1').set({ version: 1 });
    await db.doc(`restaurants/${R2}`).update({ acceptsBookings: false, bookingsDisabledReason: 'cancel_limit', bookingCancels: [1, 2, 3] });
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
  await check('D-REST-26 maxQtyPerItem: a\'zo 1…500 butun yozadi (chegaralar ham); 0, 501, satr, kasr, begona — yo\'q', async () => {
    const ref = (who) => as(who).doc(`restaurants/${R1}`);
    await assertSucceeds(ref(OWNER).update({ maxQtyPerItem: 200 }));
    await assertSucceeds(ref(STAFF).update({ maxQtyPerItem: 1 }), 'quyi chegara');
    await assertSucceeds(ref(OWNER).update({ maxQtyPerItem: 500 }), 'yuqori chegara');
    await assertFails(ref(OWNER).update({ maxQtyPerItem: 0 }));
    await assertFails(ref(OWNER).update({ maxQtyPerItem: 501 }));
    await assertFails(ref(OWNER).update({ maxQtyPerItem: -5 }));
    await assertFails(ref(OWNER).update({ maxQtyPerItem: '100' }), 'satr');
    await assertFails(ref(OWNER).update({ maxQtyPerItem: 100.5 }), 'kasr');
    await assertFails(ref(OWNER).update({ maxQtyPerItem: null }), 'null');
    await assertFails(ref(STRANGER).update({ maxQtyPerItem: 100 }), 'begona');
    await assertFails(as(OWNER2).doc(`restaurants/${R1}`).update({ maxQtyPerItem: 100 }), 'boshqa restoran egasi');
    await assertSucceeds(ref(OWNER).update({ maxQtyPerItem: 50 })); // keyingi testlar uchun default
  });
  // ── Taom ma'lumotlari (D-REST-16/17/24): hammasi ixtiyoriy, bor bo'lsa qat'iy ──
  const dish = (extra) => ({ name: 'Osh', price: 40000, available: true, ...extra });
  const putDish = (who, id, extra) => as(who).doc(`restaurants/${R1}/menu_items/${id}`).set(dish(extra));
  await check('taom ma\'lumotlari: to\'liq to\'plam (porsiya, gramm, KBJU, kuxna, teglar) yoziladi; faktsiz taom ham (ixtiyoriy)', async () => {
    await assertSucceeds(putDish(OWNER, 'f_all', {
      servings: 4, weightG: 450, kcal: 600, protein: 30, fat: 25, carbs: 60, // 4*30+4*60+9*25 = 585, farq 15
      cuisineGroup: 'national', cuisineId: 'national_ozbek', tags: ['kids', 'light'],
    }));
    await assertSucceeds(putDish(STAFF, 'f_none', {}));
    await assertSucceeds(putDish(OWNER, 'f_tags_empty', { tags: [] }));
    await assertSucceeds(putDish(OWNER, 'f_world', { cuisineGroup: 'world', cuisineId: 'world_turk' }));
    // mavjud taomga faqat narx o'zgarishi (faktlar saqlanadi) va faktlarni olib tashlash (merge emas — to'liq set)
    await assertSucceeds(as(OWNER).doc(`restaurants/${R1}/menu_items/f_all`).update({ price: 42000 }));
    await assertSucceeds(as(OWNER).doc(`restaurants/${R1}/menu_items/f_all`).set(dish({ price: 42000 })));
  });
  await check('porsiya va gramm: chegaralar (1…50, 10…5000); 0, 51, 9, 5001, satr, kasr, null — rad', async () => {
    await assertSucceeds(putDish(OWNER, 'f_s1', { servings: 1, weightG: 10 }));
    await assertSucceeds(putDish(OWNER, 'f_s50', { servings: 50, weightG: 5000 }));
    for (const bad of [{ servings: 0 }, { servings: 51 }, { servings: '4' }, { servings: 2.5 }, { servings: null },
      { weightG: 9 }, { weightG: 5001 }, { weightG: '450' }, { weightG: 450.5 }]) {
      await assertFails(putDish(OWNER, 'f_bad', bad), JSON.stringify(bad));
    }
  });
  await check('KBJU: to\'rttasi birga; kaloriya mosligi — 15 % yoki 20 kkal chegarasida (ikki tomon); qismi/diapazon/tip rad', async () => {
    const kb = (kcal, protein, fat, carbs) => ({ kcal, protein, fat, carbs });
    // calc = 400 (carbs 100): 15 % = 60 → 340…460 ok
    await assertSucceeds(putDish(OWNER, 'k_hi', kb(460, 0, 0, 100)));
    await assertSucceeds(putDish(OWNER, 'k_lo', kb(340, 0, 0, 100)));
    await assertFails(putDish(OWNER, 'k_hi2', kb(461, 0, 0, 100)), '461');
    await assertFails(putDish(OWNER, 'k_lo2', kb(339, 0, 0, 100)), '339');
    // calc = 40: 15 % = 6, lekin mutlaq 20 ккал → 20…60 ok
    await assertSucceeds(putDish(OWNER, 'k_abs_hi', kb(60, 0, 0, 10)));
    await assertSucceeds(putDish(OWNER, 'k_abs_lo', kb(20, 0, 0, 10)));
    await assertFails(putDish(OWNER, 'k_abs_hi2', kb(61, 0, 0, 10)), '61');
    // suv: hammasi 0
    await assertSucceeds(putDish(OWNER, 'k_zero', kb(0, 0, 0, 0)));
    await assertSucceeds(putDish(OWNER, 'k_zero20', kb(20, 0, 0, 0)));
    await assertFails(putDish(OWNER, 'k_zero21', kb(21, 0, 0, 0)));
    // qismi
    await assertFails(putDish(OWNER, 'k_part1', { kcal: 300 }));
    await assertFails(putDish(OWNER, 'k_part3', { kcal: 300, protein: 10, fat: 10 }));
    // diapazon / tip
    await assertFails(putDish(OWNER, 'k_neg', kb(-1, 0, 0, 0)));
    // diapazon chegarasi ALOHIDA tekshiriladi: kaloriya mosligi bajarilgan (calc = 4·500 + 4·500 + 9·111 = 4999)
    await assertSucceeds(putDish(OWNER, 'k_max', kb(5000, 500, 111, 500)));
    await assertFails(putDish(OWNER, 'k_big', kb(5001, 500, 111, 500)), 'kcal 5001');
    await assertFails(putDish(OWNER, 'k_p501', kb(2200, 501, 0, 0)), 'protein 501 (calc 2004 — mos)');
    await assertFails(putDish(OWNER, 'k_str', kb('600', 30, 25, 60)));
    await assertFails(putDish(OWNER, 'k_float', kb(600, 30.5, 25, 60)));
    await assertFails(putDish(OWNER, 'k_null', kb(600, null, 25, 60)));
  });
  await check('kuxna: ikkalasi birga va guruh mos; bo\'lmagan id, guruh nomos, faqat bittasi, noto\'g\'ri guruh — rad', async () => {
    await assertFails(putDish(OWNER, 'c_nogroup', { cuisineId: 'national_ozbek' }));
    await assertFails(putDish(OWNER, 'c_noid', { cuisineGroup: 'national' }));
    await assertFails(putDish(OWNER, 'c_mismatch', { cuisineGroup: 'world', cuisineId: 'national_ozbek' }));
    await assertFails(putDish(OWNER, 'c_missing', { cuisineGroup: 'national', cuisineId: 'national_yoq' }));
    await assertFails(putDish(OWNER, 'c_badgroup', { cuisineGroup: 'asia', cuisineId: 'national_ozbek' }));
    await assertFails(putDish(OWNER, 'c_empty', { cuisineGroup: 'national', cuisineId: '' }));
    await assertFails(putDish(OWNER, 'c_num', { cuisineGroup: 'national', cuisineId: 5 }));
  });
  await check('teglar: kids/breakfast/night/light, ≤ 4; boshqa teg, 5 ta, satr — rad; begona taom yozolmaydi', async () => {
    await assertSucceeds(putDish(OWNER, 't_all4', { tags: ['kids', 'breakfast', 'night', 'light'] }));
    await assertFails(putDish(OWNER, 't_spicy', { tags: ['spicy'] }));
    await assertSucceeds(putDish(OWNER, 't_season', { tags: ['ramadan', 'dastarxon'] }));
    for (const tag of ['navruz', 'qurbon', 'newyear', 'wedding']) await assertSucceeds(putDish(OWNER, 't_season_' + tag, { tags: [tag] }));
    await assertFails(putDish(OWNER, 't_season_bad', { tags: ['ramazon'] }));
    await assertFails(putDish(OWNER, 't_five_new', { tags: ['kids', 'ramadan', 'dastarxon', 'navruz', 'night'] }), 'ko\'pi bilan 4 ta teg');
    await assertFails(putDish(OWNER, 't_five', { tags: ['kids', 'breakfast', 'night', 'light', 'kids'] }));
    await assertFails(putDish(OWNER, 't_str', { tags: 'kids' }));
    await assertFails(putDish(STRANGER, 't_stranger', { tags: ['kids'] }));
    await assertFails(putDish(OWNER2, 't_owner2', { servings: 2 }), 'boshqa restoran egasi');
    await assertFails(putDish(OWNER, 't_unknown_key', { rating: 5 }), 'rating — server-only, hasOnly');
  });
  await check('D-REST-18 menu_item_stats: approved restoranniki hamma o\'qiydi; applied — faqat a\'zo/admin; HECH KIM yozmaydi (a\'zo, admin, mijoz ham)', async () => {
    await assertSucceeds(anon().doc(`restaurants/${R1}/menu_item_stats/osh`).get());
    await assertSucceeds(anon().collection(`restaurants/${R1}/menu_item_stats`).get());
    await assertFails(anon().doc(`restaurants/${R2}/menu_item_stats/somsa`).get());
    await assertFails(as(STRANGER).doc(`restaurants/${R2}/menu_item_stats/somsa`).get());
    await assertSucceeds(as(OWNER2).doc(`restaurants/${R2}/menu_item_stats/somsa`).get());
    await assertSucceeds(as(ADMIN).doc(`restaurants/${R2}/menu_item_stats/somsa`).get());
    const ref = (who) => as(who).doc(`restaurants/${R1}/menu_item_stats/osh`);
    for (const who of [OWNER, STAFF, ADMIN, CUSTOMER, STRANGER]) {
      await assertFails(ref(who).update({ ratingSum: 99, ratingCount: 2 }), `update ${who}`);
      await assertFails(ref(who).set({ ratingSum: 99, ratingCount: 1 }), `set ${who}`);
      await assertFails(ref(who).delete(), `delete ${who}`);
    }
    await assertFails(as(OWNER).doc(`restaurants/${R1}/menu_item_stats/yangi`).set({ ratingSum: 5, ratingCount: 1 }), 'yangi stats hujjati');
  });
  await check('D-REST-18 restaurant_dish_ratings: faqat admin o\'qiydi (kim baholagani PII); hech kim yozmaydi; mijoz o\'z bahosini ham ko\'rmaydi/yozmaydi', async () => {
    await assertSucceeds(as(ADMIN).doc(`restaurant_dish_ratings/${O1}_osh`).get());
    for (const who of [OWNER, STAFF, CUSTOMER, STRANGER]) {
      await assertFails(as(who).doc(`restaurant_dish_ratings/${O1}_osh`).get(), `read ${who}`);
    }
    await assertFails(anon().doc(`restaurant_dish_ratings/${O1}_osh`).get());
    for (const who of [OWNER, ADMIN, CUSTOMER]) {
      await assertFails(as(who).doc(`restaurant_dish_ratings/${O1}_somsa`).set({ orderId: O1, itemId: 'somsa', restaurantId: R1, userId: CUSTOMER, stars: 5 }), `create ${who}`);
      await assertFails(as(who).doc(`restaurant_dish_ratings/${O1}_osh`).update({ stars: 1 }), `update ${who}`);
      await assertFails(as(who).doc(`restaurant_dish_ratings/${O1}_osh`).delete(), `delete ${who}`);
    }
  });
  await check('D-REST-25 qtyTiers: to\'g\'ri pog\'onalar yoziladi (1, 2, 3 ta); tartibsiz, narxi oshuvchi, asosiy narxdan past emas, 4 ta, begona kalit, tip xatosi — rad', async () => {
    const t = (minQty, price) => ({ minQty, price });
    await assertSucceeds(putDish(OWNER, 'q_none', {}));
    await assertSucceeds(putDish(OWNER, 'q_empty', { qtyTiers: [] }), 'bo\'sh ro\'yxat — pog\'ona yo\'q');
    await assertSucceeds(putDish(OWNER, 'q1', { qtyTiers: [t(10, 38000)] }));
    await assertSucceeds(putDish(STAFF, 'q2', { qtyTiers: [t(10, 38000), t(30, 35000)] }));
    await assertSucceeds(putDish(OWNER, 'q3', { qtyTiers: [t(2, 39999), t(3, 39998), t(500, 1)] }), 'chegaralar: minQty 2…500, narx 1');
    const bad = {
      'asosiy narxga teng': [t(10, 40000)],
      'asosiydan baland': [t(10, 41000)],
      'minQty = 1': [t(1, 30000)],
      'minQty = 0': [t(0, 30000)],
      'minQty 501': [t(501, 30000)],
      'narx 0': [t(10, 0)],
      'narx manfiy': [t(10, -5)],
      'ikkinchi minQty kichik': [t(10, 38000), t(10, 35000)],
      'ikkinchi minQty orqaga': [t(10, 38000), t(5, 35000)],
      'ikkinchi narx oshdi': [t(10, 38000), t(30, 38000)],
      'uchinchi narx oshdi': [t(10, 38000), t(30, 35000), t(50, 36000)],
      '4 ta': [t(2, 39000), t(3, 38000), t(4, 37000), t(5, 36000)],
      'begona kalit': [{ minQty: 10, price: 38000, note: 'x' }],
      'minQty satr': [{ minQty: '10', price: 38000 }],
      'narx kasr': [{ minQty: 10, price: 37999.5 }],
      'narx satr': [{ minQty: 10, price: '38000' }],
      'minQty kasr': [{ minQty: 10.5, price: 38000 }],
      'element xarita emas': [10],
      'kalit yo\'q': [{ minQty: 10 }],
    };
    for (const [name, tiers] of Object.entries(bad)) await assertFails(putDish(OWNER, `qb_${name.length}`, { qtyTiers: tiers }), name);
    await assertFails(putDish(OWNER, 'qb_list', { qtyTiers: 'x' }), 'ro\'yxat emas');
    await assertFails(putDish(OWNER, 'qb_map', { qtyTiers: { minQty: 10, price: 100 } }), 'xarita');
    await assertFails(putDish(OWNER, 'qb_null', { qtyTiers: null }), 'null — klient yo\'q maydonni o\'chiradi');
    // asosiy narx o'zgarganda pog'ona yangi narxga nisbatan tekshiriladi
    await assertFails(as(OWNER).doc(`restaurants/${R1}/menu_items/q1`).update({ price: 30000 }), 'asosiy narx pog\'onadan past bo\'lib qoldi (hujjat natijasi tekshiriladi)');
    await assertSucceeds(as(OWNER).doc(`restaurants/${R1}/menu_items/q1`).update({ price: 50000 }));
    await assertFails(putDish(STRANGER, 'q_stranger', { qtyTiers: [t(10, 38000)] }), 'begona yozolmaydi');
  });
  await check('S6 order_courier_live: faqat tayinlangan kuryer, faqat FAOL holatda yozadi; mijoz, restoran a\'zosi va admin o\'qiydi; begona va boshqa kuryer — yo\'q', async () => {
    const { serverTimestamp } = require('firebase/firestore');
    const live = (who, oid = 'live_picked') => as(who).doc(`order_courier_live/${oid}`);
    const pos = (extra = {}) => ({ orderId: 'live_picked', lat: 41.84, lng: 60.39, updatedAt: serverTimestamp(), ...extra });
    // yozish
    await assertSucceeds(live(COURIER).set(pos()));
    await assertSucceeds(live(COURIER).set(pos({ lat: 41.85, heading: 90, speed: 7.5, accuracy: 12, courierId: COURIER })));
    await assertSucceeds(live(COURIER, 'live_accepted').set(pos({ orderId: 'live_accepted' })), 'qabul qilingan, kuryer biriktirilgan — ruxsat');
    await assertFails(live(COURIER, 'live_placed').set(pos({ orderId: 'live_placed' })), 'placed — hali emas');
    await assertFails(live(COURIER, 'live_delivered').set(pos({ orderId: 'live_delivered' })), 'yetkazilgach yozib bo\'lmaydi');
    await assertFails(live(COURIER, 'live_bread').set(pos({ orderId: 'live_bread' })), 'restoran buyurtmasi emas');
    await assertFails(live(COURIER, 'yoq_buyurtma').set(pos({ orderId: 'yoq_buyurtma' })), 'buyurtma yo\'q');
    for (const who of [CUSTOMER, OWNER, STAFF, STRANGER, ADMIN]) await assertFails(live(who).set(pos()), `yozish ${who}`);
    // qiymatlar
    await assertFails(live(COURIER).set(pos({ lat: 91 })), 'lat > 90');
    await assertFails(live(COURIER).set(pos({ lng: -181 })), 'lng');
    await assertFails(live(COURIER).set(pos({ lat: '41.8' })), 'lat satr');
    await assertFails(live(COURIER).set(pos({ heading: 361 })));
    await assertFails(live(COURIER).set(pos({ speed: -1 })));
    await assertFails(live(COURIER).set(pos({ orderId: 'boshqa' })), 'orderId yo\'lga mos emas');
    await assertFails(live(COURIER).set(pos({ courierId: STRANGER })), 'courierId o\'zi emas');
    await assertFails(live(COURIER).set(pos({ extra: 1 })), 'begona kalit');
    await assertFails(live(COURIER).set(pos({ updatedAt: new Date() })), 'updatedAt server vaqti emas');
    await assertFails(live(COURIER).set({ orderId: 'live_picked', lat: 41.8, lng: 60.3 }), 'updatedAt yo\'q');
    // o'qish
    await assertSucceeds(live(CUSTOMER).get(), 'mijoz');
    await assertSucceeds(live(OWNER).get(), 'restoran egasi');
    await assertSucceeds(live(STAFF).get(), 'restoran xodimi');
    await assertSucceeds(live(ADMIN).get(), 'admin');
    await assertFails(live(COURIER).get(), 'kuryer faqat yozadi — o\'qish unga kerak emas (minimal ruxsat)');
  });
  await check('S6 order_courier_live: NON / BOZOR buyurtmasi (bread, platform) — courier_picked va arrived da yoziladi; ready/completed/boshqa tur — yo\'q', async () => {
    const { serverTimestamp } = require('firebase/firestore');
    const live = (who, oid) => as(who).doc(`order_courier_live/${oid}`);
    const pos = (oid, extra = {}) => ({ orderId: oid, lat: 41.84, lng: 60.39, updatedAt: serverTimestamp(), ...extra });
    await assertSucceeds(live(COURIER, 'live_bread_picked').set(pos('live_bread_picked')), 'non, kuryer oldi');
    await assertSucceeds(live(COURIER, 'live_market_arrived').set(pos('live_market_arrived', { speed: 3 })), 'bozor, yetib keldi');
    await assertFails(live(COURIER, 'live_bread_ready').set(pos('live_bread_ready')), 'tayyor, hali olinmagan');
    await assertFails(live(COURIER, 'live_bread_done').set(pos('live_bread_done')), 'yakunlangan');
    await assertFails(live(COURIER, 'live_other_type').set(pos('live_other_type')), 'boshqa tur (gilam)');
    for (const who of [STRANGER, OWNER, ADMIN]) await assertFails(live(who, 'live_bread_picked').set(pos('live_bread_picked')), `yozish ${who}`);
    // o'qish: mijoz va admin; begona yo'q; yakunlangach mijoz ham o'qiy olmaydi, admin o'qiydi
    await assertSucceeds(live(CUSTOMER, 'live_bread_picked').get(), 'mijoz');
    await assertSucceeds(live(ADMIN, 'live_bread_picked').get(), 'admin');
    await assertFails(live(STRANGER, 'live_bread_picked').get(), 'begona');
    await assertFails(live(OWNER, 'live_bread_picked').get(), 'restoran egasi bu buyurtmaga aloqasiz');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('order_courier_live/live_bread_done').set({ orderId: 'live_bread_done', lat: 1, lng: 1 });
    });
    await assertFails(live(CUSTOMER, 'live_bread_done').get(), 'yakunlangan buyurtma nuqtasi mijozga yopiq');
    await assertSucceeds(live(ADMIN, 'live_bread_done').get(), 'admin ko\'radi');
    await assertSucceeds(live(COURIER, 'live_bread_done').delete(), 'kuryer o\'chira oladi');
  });
  await check('S6 order_courier_live: restoran buyurtmasi yetkazilgach (delivered) mijoz va restoran nuqtani o\'qiy olmaydi (o\'chirish kutilmasdan)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('order_courier_live/live_delivered').set({ orderId: 'live_delivered', lat: 1, lng: 1 });
    });
    await assertFails(as(CUSTOMER).doc('order_courier_live/live_delivered').get());
    await assertFails(as(OWNER).doc('order_courier_live/live_delivered').get());
    await assertSucceeds(as(ADMIN).doc('order_courier_live/live_delivered').get());
  });  await check('S6 order_courier_live: begona/boshqa restoran a\'zosi va anonim o\'qiy olmaydi; ro\'yxat yo\'q; o\'chirish — faqat kuryer yoki admin', async () => {
    const live = (who) => as(who).doc('order_courier_live/live_picked');
    await assertFails(live(STRANGER).get());
    await assertFails(live(OWNER2).get(), 'boshqa restoran egasi');
    await assertFails(anon().doc('order_courier_live/live_picked').get());
    await assertFails(as(ADMIN).collection('order_courier_live').get(), 'ro\'yxat umuman yo\'q');
    await assertFails(as(CUSTOMER).collection('order_courier_live').where('orderId', '==', 'live_picked').get());
    await assertFails(live(CUSTOMER).delete());
    await assertFails(live(OWNER).delete());
    await assertFails(live(STRANGER).delete());
    await assertSucceeds(live(COURIER).delete());
    await assertSucceeds(as(COURIER).doc('order_courier_live/live_picked').set({ orderId: 'live_picked', lat: 41.8, lng: 60.3, updatedAt: require('firebase/firestore').serverTimestamp() }));
    await assertSucceeds(live(ADMIN).delete());
  });
  await check('S4b acceptsPreorder: a\'zo bool yozadi; satr/son/null — rad; begona yozolmaydi', async () => {
    const ref = (who) => as(who).doc(`restaurants/${R1}`);
    await assertSucceeds(ref(OWNER).update({ acceptsPreorder: true }));
    await assertSucceeds(ref(STAFF).update({ acceptsPreorder: false }));
    for (const v of ['true', 1, 0, null, {}]) await assertFails(ref(OWNER).update({ acceptsPreorder: v }), String(v));
    await assertFails(ref(STRANGER).update({ acceptsPreorder: true }));
    await assertFails(ref(CUSTOMER).update({ acceptsPreorder: true }));
    await assertFails(as(OWNER).doc(`orders/${O1}`).update({ scheduledFor: new Date(), isPreorder: true }), 'buyurtmaga oldindan vaqt yozib bo\'lmaydi');
  });
  await check('S5 acceptsBookings/bookingSeats/bookingNote: a\'zo yozadi (tur/chegara qat\'iy); begona yozolmaydi; bookingCancels va sabab belgisi — a\'zo yozolmaydi', async () => {
    const ref = (who) => as(who).doc(`restaurants/${R1}`);
    await assertSucceeds(ref(OWNER).update({ acceptsBookings: true, bookingSeats: 20, bookingNote: 'Zakalat 100 000' }));
    await assertSucceeds(ref(STAFF).update({ bookingSeats: 500 }));
    for (const v of ['true', 1, null]) await assertFails(ref(OWNER).update({ acceptsBookings: v }), `acceptsBookings ${v}`);
    for (const v of [0, -1, 501, 2.5, '20', null]) await assertFails(ref(OWNER).update({ bookingSeats: v }), `bookingSeats ${v}`);
    await assertFails(ref(OWNER).update({ bookingNote: 'x'.repeat(301) }));
    await assertFails(ref(OWNER).update({ bookingNote: 5 }));
    await assertFails(ref(STRANGER).update({ acceptsBookings: true }));
    await assertFails(ref(CUSTOMER).update({ bookingSeats: 5 }));
    await assertFails(ref(OWNER).update({ bookingCancels: [] }), 'bekor qilish tarixi faqat CF');
    await assertFails(ref(OWNER).update({ bookingsDisabledReason: '' }), 'sabab belgisi faqat CF');
  });
  await check('D-REST-41 venueType: kafe-restoran a\'zosi cafe/restaurant/chaikhana yozadi (home — yo\'q); uy ovqatchisida faqat home; begona yozolmaydi; eski hujjat (maydon yo\'q) tegilmasa buzilmaydi', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`restaurants/${R1}`).update({ legalType: 'yatt' });
      await ctx.firestore().doc(`restaurants/${R2}`).update({ legalType: 'individual' });
    });
    const ref = (who, id = R1) => as(who).doc(`restaurants/${id}`);
    for (const v of ['cafe', 'restaurant', 'chaikhana']) await assertSucceeds(ref(OWNER).update({ venueType: v }), v);
    for (const v of ['home', 'bar', 'CAFE', 5, null]) await assertFails(ref(OWNER).update({ venueType: v }), `kafe: ${v}`);
    await assertSucceeds(ref(OWNER).update({ prepTimeMin: 21 }), 'turga tegilmaydigan yozuv');
    await assertFails(ref(STRANGER).update({ venueType: 'cafe' }));
    await assertSucceeds(ref(OWNER2, R2).update({ venueType: 'home' }), 'uy ovqatchisi — home');
    for (const v of ['cafe', 'restaurant', 'chaikhana']) await assertFails(ref(OWNER2, R2).update({ venueType: v }), `uy ovqatchisi: ${v}`);
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const { deleteField } = require('firebase/firestore');
      await ctx.firestore().doc(`restaurants/${R1}`).update({ legalType: deleteField(), venueType: deleteField() });
      await ctx.firestore().doc(`restaurants/${R2}`).update({ legalType: deleteField(), venueType: deleteField() });
    });
  });  await check('S5 limitdan avtomat o\'chirilgan restoran: a\'zo o\'zi qayta yoqolmaydi (false yozish mumkin)', async () => {
    const ref = (who) => as(who).doc(`restaurants/${R2}`);
    await assertFails(ref(OWNER2).update({ acceptsBookings: true }), 'cancel_limit — qayta yoqib bo\'lmaydi');
    await assertSucceeds(ref(OWNER2).update({ acceptsBookings: false }));
    await assertSucceeds(ref(OWNER2).update({ bookingSeats: 12 }), 'boshqa maydonlar ochiq');
  });
  await check('S5 restaurant_bookings: mijoz o\'zinikini, restoran a\'zosi o\'z restoraninikini, admin hammasini o\'qiydi; begona va anonim — yo\'q; HECH KIM yozmaydi', async () => {
    const col = (who) => as(who).collection('restaurant_bookings');
    await assertSucceeds(as(CUSTOMER).doc('restaurant_bookings/bk1').get());
    await assertSucceeds(as(OWNER).doc('restaurant_bookings/bk1').get());
    await assertSucceeds(as(STAFF).doc('restaurant_bookings/bk1').get());
    await assertSucceeds(as(ADMIN).doc('restaurant_bookings/bk1').get());
    await assertFails(as(STRANGER).doc('restaurant_bookings/bk1').get(), 'begona mijoz');
    await assertFails(as(OWNER2).doc('restaurant_bookings/bk1').get(), 'boshqa restoran egasi');
    await assertFails(anon().doc('restaurant_bookings/bk1').get());
    await assertSucceeds(col(CUSTOMER).where('userPhone', '==', CUSTOMER).get());
    await assertSucceeds(col(OWNER).where('restaurantId', '==', R1).get());
    await assertSucceeds(col(ADMIN).get());
    await assertFails(col(STRANGER).where('userPhone', '==', CUSTOMER).get(), 'boshqa odam so\'rovi');
    await assertFails(col(CUSTOMER).get(), 'filtrsiz ro\'yxat');
    await assertFails(col(OWNER2).where('restaurantId', '==', R1).get());
    await assertFails(anon().collection('restaurant_bookings').where('restaurantId', '==', R1).get());
    for (const who of [CUSTOMER, OWNER, STAFF, ADMIN, STRANGER]) {
      await assertFails(as(who).doc('restaurant_bookings/bk1').update({ status: 'confirmed' }), `update ${who}`);
      await assertFails(as(who).doc('restaurant_bookings/bk1').update({ 'fee.amount': 0 }), `fee ${who}`);
      await assertFails(as(who).doc('restaurant_bookings/bk1').delete(), `delete ${who}`);
      await assertFails(as(who).doc(`restaurant_bookings/new_${who}`).set({ restaurantId: R1, userPhone: who, guests: 1, status: 'confirmed' }), `create ${who}`);
    }
  });
  await check('S5 bron hodisalari faqat admin; settings/restaurant_bookings hamma o\'qiydi, admin ham TO\'G\'RIDAN-TO\'G\'RI yozolmaydi; tarix faqat admin', async () => {
    await assertSucceeds(as(ADMIN).doc('restaurant_bookings/bk1/events/e1').get());
    await assertFails(as(CUSTOMER).doc('restaurant_bookings/bk1/events/e1').get());
    await assertFails(as(OWNER).doc('restaurant_bookings/bk1/events/e1').get());
    await assertFails(as(ADMIN).doc('restaurant_bookings/bk1/events/e2').set({ to: 'x' }));
    await assertSucceeds(anon().doc('settings/restaurant_bookings').get());
    for (const who of [ADMIN, OWNER, CUSTOMER]) {
      await assertFails(as(who).doc('settings/restaurant_bookings').update({ stage: 'public' }), `update ${who}`);
      await assertFails(as(who).doc('settings/restaurant_bookings').set({ stage: 'public', tiers: [{ upTo: 100, fee: 0 }] }), `set ${who}`);
    }
    await assertSucceeds(as(ADMIN).doc('restaurant_bookings_history/v1').get());
    await assertFails(as(CUSTOMER).doc('restaurant_bookings_history/v1').get());
    await assertFails(as(ADMIN).doc('restaurant_bookings_history/v2').set({ version: 2 }));
  });  await check('D-REST-22 settings/restaurant_seasons va restaurant_ramadan: hamma o\'qiydi; admin ham TO\'G\'RIDAN-TO\'G\'RI yozolmaydi (faqat CF); tarix faqat admin o\'qiydi', async () => {
    for (const doc of ['settings/restaurant_seasons', 'settings/restaurant_ramadan']) {
      await assertSucceeds(anon().doc(doc).get());
      for (const who of [ADMIN, OWNER, CUSTOMER]) {
        await assertFails(as(who).doc(doc).update({ version: 99 }), `${doc} update ${who}`);
        await assertFails(as(who).doc(doc).set({ periods: [], days: {}, offsets: {} }), `${doc} set ${who}`);
      }
    }
    for (const h of ['restaurant_seasons_history/v1', 'restaurant_ramadan_history/v1']) {
      await assertSucceeds(as(ADMIN).doc(h).get());
      await assertFails(as(CUSTOMER).doc(h).get());
      await assertFails(anon().doc(h).get());
      await assertFails(as(ADMIN).doc(h.replace('v1', 'v2')).set({ version: 2 }));
    }
  });
  await check('D-REST-33 restaurant_dish_index: hamma o\'qiydi (loginsiz ham; bo\'lim + geo so\'rovi); HECH KIM yozmaydi (a\'zo, admin, mijoz ham)', async () => {
    await assertSucceeds(anon().doc(`restaurant_dish_index/${R1}_osh`).get());
    await assertSucceeds(anon().collection('restaurant_dish_index').where('sections', 'array-contains', 'cheap').where('geo4', 'in', ['tzh1', 'tzh2']).limit(50).get());
    const ref = (who) => as(who).doc(`restaurant_dish_index/${R1}_osh`);
    for (const who of [OWNER, STAFF, ADMIN, CUSTOMER, STRANGER]) {
      await assertFails(ref(who).update({ price: 1, sections: ['cheap', 'kids'] }), `update ${who}`);
      await assertFails(ref(who).delete(), `delete ${who}`);
      await assertFails(as(who).doc(`restaurant_dish_index/${R1}_yangi`).set({ restaurantId: R1, itemId: 'yangi', sections: ['cheap'] }), `create ${who}`);
    }
  });
  await check('D-REST-33 settings/restaurant_sections: hamma o\'qiydi; admin ham TO\'G\'RIDAN-TO\'G\'RI yozolmaydi (faqat CF, versiya+audit); tarix faqat admin o\'qiydi', async () => {
    await assertSucceeds(anon().doc('settings/restaurant_sections').get());
    for (const who of [ADMIN, OWNER, CUSTOMER]) {
      await assertFails(as(who).doc('settings/restaurant_sections').update({ cheapRatingThreshold: 1 }), `update ${who}`);
      await assertFails(as(who).doc('settings/restaurant_sections').set({ sections: { cheap: 'public' } }), `set ${who}`);
    }
    await assertSucceeds(as(ADMIN).doc('restaurant_sections_history/v1').get());
    await assertFails(as(CUSTOMER).doc('restaurant_sections_history/v1').get());
    await assertFails(anon().doc('restaurant_sections_history/v1').get());
    await assertFails(as(ADMIN).doc('restaurant_sections_history/v2').set({ version: 2 }));
  });
  await check('D-REST-18 mijoz buyurtmasiga `dishRatings` yozolmaydi (faqat CF)', async () => {
    await assertFails(as(CUSTOMER).doc(`orders/${O1}`).update({ dishRatings: { osh: 5 } }));
  });
  await check('restaurant_cuisines: hamma o\'qiydi (loginsiz ham); hech kim yozmaydi (admin ham)', async () => {
    await assertSucceeds(anon().doc('restaurant_cuisines/national_ozbek').get());
    await assertSucceeds(anon().collection('restaurant_cuisines').get());
    await assertFails(as(OWNER).doc('restaurant_cuisines/national_mening').set({ name: 'X', group: 'national' }));
    await assertFails(as(ADMIN).doc('restaurant_cuisines/national_ozbek').update({ hidden: true }));
    await assertFails(as(STRANGER).doc('restaurant_cuisines/national_ozbek').delete());
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
