/**
 * KAFE-RESTORAN — taom bahosi `submitDishRatings` (D-REST-18) — HAQIQIY `functions/index.js`
 * callable'i `.run()` orqali, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-dish-ratings \
 *     "node functions/test/restaurant_dish_ratings_cf.test.js"
 *
 * Qulflanadi:
 *   - faqat YETKAZILGAN (`delivered`) buyurtma; boshqa holatlar rad
 *   - faqat buyurtma egasi; begona/boshqa buyurtma taomi rad; restoran buyurtmasi bo'lmagan hujjat rad
 *   - baho faqat HAQIQIY butun son 1..5 (0, 6, 4.5, '5', null — rad), bo'sh/ko'p ro'yxat rad
 *   - takroriy chaqiruv agregatni ikki marta oshirmaydi (idempotent); baho o'zgarmaydi
 *   - parallel chaqiruv — agregat aniq (ikki marta emas); turli mijozlar yig'indisi to'g'ri
 *   - bir chaqiruvda bir taom ikki marta kelsa — birinchisi hisobga olinadi
 *   - order_events ga `dish_rated`; `orders.dishRatings` xaritasi
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-dish-ratings';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require('../index');
const admin = require('firebase-admin');
const ratings = require('../restaurant_dish_ratings');

const db = admin.firestore();

const CUSTOMER = '998912000001';
const CUSTOMER2 = '998912000002';
const STRANGER = '998914000001';
const RID = 'rest1';

const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (data, who) => fns.submitDishRatings.run(data, ctxOf(who));

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

const items = [
  { itemId: 'osh', name: 'Osh', price: 40000, count: 1, lineTotal: 40000 },
  { itemId: 'somsa', name: 'Somsa', price: 10000, count: 2, lineTotal: 20000 },
];
async function seedOrder(id, over = {}) {
  await db.collection('orders').doc(id).set({
    type: 'restaurant', restaurantId: RID, userPhone: CUSTOMER, restaurantStatus: 'delivered',
    items, itemsTotal: 60000, ...over,
  });
}
const stats = async (itemId) => (await db.collection('restaurants').doc(RID).collection('menu_item_stats').doc(itemId).get()).data() || {};
const order = async (id) => (await db.collection('orders').doc(id).get()).data() || {};
const ratingDoc = async (orderId, itemId) => (await db.collection('restaurant_dish_ratings').doc(ratings.ratingDocId(orderId, itemId)).get());
const eventsOf = async (id) => (await db.collection('orders').doc(id).collection('order_events').where('reason', '==', 'dish_rated').get()).size;

async function main() {
  await clearEmulator();

  await check('RT1 yetkazilgan buyurtma: ikki taomga baho — hujjatlar, agregat, order.dishRatings, order_events', async () => {
    await seedOrder('o1');
    const r = await call({ orderId: 'o1', ratings: [{ itemId: 'osh', stars: 5 }, { itemId: 'somsa', stars: 4 }] }, CUSTOMER);
    assert.deepStrictEqual([r.ok, r.saved.sort(), r.alreadyRated], [true, ['osh', 'somsa'], []]);
    const d = (await ratingDoc('o1', 'osh')).data();
    assert.deepStrictEqual([d.stars, d.userId, d.restaurantId, d.orderId], [5, CUSTOMER, RID, 'o1']);
    assert.deepStrictEqual([(await stats('osh')).ratingSum, (await stats('osh')).ratingCount], [5, 1]);
    assert.deepStrictEqual([(await stats('somsa')).ratingSum, (await stats('somsa')).ratingCount], [4, 1]);
    assert.deepStrictEqual((await order('o1')).dishRatings, { osh: 5, somsa: 4 });
    assert.strictEqual(await eventsOf('o1'), 1);
  });

  await check('RT2 takroriy chaqiruv (hatto boshqa baho bilan): agregat OSHMAYDI, baho o\'zgarmaydi, alreadyRated', async () => {
    const r = await call({ orderId: 'o1', ratings: [{ itemId: 'osh', stars: 1 }] }, CUSTOMER);
    assert.deepStrictEqual([r.saved, r.alreadyRated], [[], ['osh']]);
    assert.deepStrictEqual([(await stats('osh')).ratingSum, (await stats('osh')).ratingCount], [5, 1]);
    assert.strictEqual((await ratingDoc('o1', 'osh')).data().stars, 5);
    assert.strictEqual(await eventsOf('o1'), 1, 'yangi baho yo\'q — yangi hodisa ham yo\'q');
  });

  await check('RT3 qisman: bahosi bor taom o\'tkaziladi, yangisi saqlanadi', async () => {
    await seedOrder('o3');
    await call({ orderId: 'o3', ratings: [{ itemId: 'osh', stars: 3 }] }, CUSTOMER);
    const r = await call({ orderId: 'o3', ratings: [{ itemId: 'osh', stars: 5 }, { itemId: 'somsa', stars: 2 }] }, CUSTOMER);
    assert.deepStrictEqual([r.saved, r.alreadyRated], [['somsa'], ['osh']]);
    assert.deepStrictEqual((await order('o3')).dishRatings, { osh: 3, somsa: 2 });
  });

  await check('RT4 turli mijozlar: agregat yig\'indisi to\'g\'ri (5+4+3=12, 3 ta)', async () => {
    await clearEmulator();
    await seedOrder('a', { userPhone: CUSTOMER });
    await seedOrder('b', { userPhone: CUSTOMER2 });
    await seedOrder('c', { userPhone: CUSTOMER });
    await call({ orderId: 'a', ratings: [{ itemId: 'osh', stars: 5 }] }, CUSTOMER);
    await call({ orderId: 'b', ratings: [{ itemId: 'osh', stars: 4 }] }, CUSTOMER2);
    await call({ orderId: 'c', ratings: [{ itemId: 'osh', stars: 3 }] }, CUSTOMER);
    const s = await stats('osh');
    assert.deepStrictEqual([s.ratingSum, s.ratingCount], [12, 3]);
  });

  await check('RT5 PARALLEL bir xil chaqiruv (10 marta): agregat faqat BIR marta oshadi', async () => {
    await seedOrder('p1');
    const calls = Array.from({ length: 10 }, () => call({ orderId: 'p1', ratings: [{ itemId: 'osh', stars: 5 }] }, CUSTOMER));
    const out = await Promise.allSettled(calls);
    const ok = out.filter((x) => x.status === 'fulfilled');
    assert.ok(ok.length >= 1, 'kamida bittasi muvaffaqiyatli');
    for (const x of out) {
      if (x.status === 'rejected') assert.strictEqual((x.reason.details && x.reason.details.code), 'CONTENTION_RETRY');
    }
    const before = (await stats('osh')).ratingCount; // RT4 dan 3 + shu 1
    assert.strictEqual(before, 4, `agregat ${before}, kutilgan 4`);
    assert.strictEqual((await order('p1')).dishRatings.osh, 5);
    assert.strictEqual((await db.collection('restaurant_dish_ratings').where('orderId', '==', 'p1').get()).size, 1);
  });

  await check('RT6 yetkazilmagan buyurtma (placed/accepted/ready/picked/cancelled/delivery_failed) — ORDER_NOT_DELIVERED', async () => {
    for (const st of ['placed', 'accepted', 'ready', 'picked', 'arrived', 'rejected', 'cancelled', 'delivery_failed']) {
      await seedOrder(`st_${st}`, { restaurantStatus: st });
      await expectCode(call({ orderId: `st_${st}`, ratings: [{ itemId: 'osh', stars: 5 }] }, CUSTOMER), 'ORDER_NOT_DELIVERED', 'failed-precondition');
    }
    assert.strictEqual((await db.collection('restaurant_dish_ratings').where('orderId', '>=', 'st_').where('orderId', '<=', 'st_').get()).size, 0);
  });

  await check('RT7 begona mijoz baholay olmaydi (NOT_ORDER_OWNER); baho yozilmaydi', async () => {
    await seedOrder('own');
    await expectCode(call({ orderId: 'own', ratings: [{ itemId: 'osh', stars: 1 }] }, STRANGER), 'NOT_ORDER_OWNER', 'permission-denied');
    assert.strictEqual((await ratingDoc('own', 'osh')).exists, false);
  });

  await check('RT8 buyurtmada YO\'Q taom (ITEM_NOT_IN_ORDER) — hech narsa yozilmaydi (hatto to\'g\'ri taom ham)', async () => {
    await seedOrder('nt');
    const before = (await stats('osh')).ratingCount;
    await expectCode(call({ orderId: 'nt', ratings: [{ itemId: 'osh', stars: 5 }, { itemId: 'boshqa', stars: 5 }] }, CUSTOMER), 'ITEM_NOT_IN_ORDER', 'failed-precondition');
    assert.strictEqual((await ratingDoc('nt', 'osh')).exists, false, 'tranzaksiya butunlay bekor');
    assert.strictEqual((await stats('osh')).ratingCount, before);
  });

  await check('RT9 baho qiymati: 0, 6, -1, 4.5, "5", null, NaN, true — RATING_INVALID', async () => {
    await seedOrder('bad');
    for (const stars of [0, 6, -1, 4.5, '5', null, Number.NaN, true, undefined]) {
      await expectCode(call({ orderId: 'bad', ratings: [{ itemId: 'osh', stars }] }, CUSTOMER), 'RATING_INVALID', 'invalid-argument');
    }
    assert.strictEqual((await ratingDoc('bad', 'osh')).exists, false);
  });

  await check('RT10 chegara qiymatlari: 1 va 5 qabul', async () => {
    await seedOrder('lim');
    const r = await call({ orderId: 'lim', ratings: [{ itemId: 'osh', stars: 1 }, { itemId: 'somsa', stars: 5 }] }, CUSTOMER);
    assert.strictEqual(r.saved.length, 2);
  });

  await check('RT11 kirish tekshiruvi: orderId yo\'q, ro\'yxat bo\'sh/ko\'p, itemId noto\'g\'ri, auth yo\'q', async () => {
    await expectCode(call({ ratings: [{ itemId: 'osh', stars: 5 }] }, CUSTOMER), 'ORDER_ID_REQUIRED', 'invalid-argument');
    await expectCode(call({ orderId: 'o1', ratings: [] }, CUSTOMER), 'RATINGS_REQUIRED', 'invalid-argument');
    await expectCode(call({ orderId: 'o1' }, CUSTOMER), 'RATINGS_REQUIRED', 'invalid-argument');
    const many = Array.from({ length: ratings.MAX_RATINGS + 1 }, (_, i) => ({ itemId: `i${i}`, stars: 5 }));
    await expectCode(call({ orderId: 'o1', ratings: many }, CUSTOMER), 'RATING_INVALID', 'invalid-argument');
    await expectCode(call({ orderId: 'o1', ratings: [{ itemId: 'a/b', stars: 5 }] }, CUSTOMER), 'RATING_INVALID', 'invalid-argument');
    await expectCode(call({ orderId: 'o1', ratings: [{ itemId: '', stars: 5 }] }, CUSTOMER), 'RATING_INVALID', 'invalid-argument');
    await assert.rejects(fns.submitDishRatings.run({ orderId: 'o1', ratings: [{ itemId: 'osh', stars: 5 }] }, {}), (e) => (e.details && e.details.code) === 'AUTH_REQUIRED');
    await expectCode(call({ orderId: 'yo_q', ratings: [{ itemId: 'osh', stars: 5 }] }, CUSTOMER), 'ORDER_NOT_FOUND', 'not-found');
  });

  await check('RT12 restoran buyurtmasi bo\'lmagan hujjat (non/taksi va h.k.) — NOT_RESTAURANT_ORDER', async () => {
    await seedOrder('bread', { type: 'bread' });
    await expectCode(call({ orderId: 'bread', ratings: [{ itemId: 'osh', stars: 5 }] }, CUSTOMER), 'NOT_RESTAURANT_ORDER', 'failed-precondition');
  });

  await check('RT13 bir chaqiruvda bir taom ikki marta — birinchisi hisobga olinadi, agregat +1', async () => {
    await seedOrder('dup');
    const before = (await stats('osh')).ratingCount;
    const r = await call({ orderId: 'dup', ratings: [{ itemId: 'osh', stars: 2 }, { itemId: 'osh', stars: 5 }] }, CUSTOMER);
    assert.deepStrictEqual(r.saved, ['osh']);
    assert.strictEqual((await ratingDoc('dup', 'osh')).data().stars, 2);
    assert.strictEqual((await stats('osh')).ratingCount, before + 1);
  });

  await check('RT14 bir taom turli buyurtmalarda — har buyurtma o\'z bahosi (hujjat identifikatori orderId_itemId)', async () => {
    assert.strictEqual(ratings.ratingDocId('o1', 'osh'), 'o1_osh');
    assert.notStrictEqual(ratings.ratingDocId('o1', 'osh'), ratings.ratingDocId('o3', 'osh'));
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
