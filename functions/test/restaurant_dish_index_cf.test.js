/**
 * KAFE-RESTORAN — bo'limlar indeksi (S3, D-REST-33): `restaurant_dish_index` + sozlama callable'i.
 * HAQIQIY `functions/index.js` (trigger'lar `.run()` bilan), Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-dish-index \
 *     "node functions/test/restaurant_dish_index_cf.test.js"
 *
 * Qulflanadi:
 *   - bo'limga kirish qoidasi (har bo'lim: musbat + manfiy + chegara), bir kishilik narx ceil;
 *   - indeksga kirmaslik shartlari (tasdiqlanmagan restoran, mavjud emas, noto'g'ri narx/joy, bo'limsiz);
 *   - trigger'lar: taom yozildi/o'zgardi/o'chdi, restoran tasdiqlandi/yopildi/nomi o'zgardi (fan-out), baho keldi;
 *   - o'zgarmagan indeks QAYTA YOZILMAYDI; parallel qayta hisoblash — bitta to'g'ri hujjat;
 *   - taomi o'chgan yetim indeks tozalanadi;
 *   - sozlama callable'i: faqat admin, qisman o'zgarish, versiya/tarix/audit, idempotent, noto'g'ri qiymat rad.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-dish-index';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require('../index');
const admin = require('firebase-admin');
const idx = require('../restaurant_dish_index');
const cfg = require('../restaurant_sections_config');

const db = admin.firestore();
const Timestamp = admin.firestore.Timestamp;

const ADMIN = '998915000001';
const NOADMIN = '998912000001';
const RID = 'rest1';
const GURLAN = { lat: 41.8406, lng: 60.3917 };

const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function expectCode(promise, code) {
  await assert.rejects(promise, (e) => {
    const got = (e.details && e.details.code) || e.message;
    assert.strictEqual(got, code, `kod ${got}: ${e.message}`);
    return true;
  });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}

const GURLAN_HASH = require('../geo_hash').encode(GURLAN.lat, GURLAN.lng, 7);
const GEO4 = GURLAN_HASH.slice(0, 4);
const restaurant = (over = {}) => ({
  name: 'Gurlan osh', status: 'approved', ...GURLAN, geohash: GURLAN_HASH, cuisineTags: [], prepTimeMin: 25, ...over,
});
const rRef = () => db.collection('restaurants').doc(RID);
const itemRef = (id) => rRef().collection('menu_items').doc(id);
const ixRef = (id) => db.collection('restaurant_dish_index').doc(`${RID}_${id}`);
const ix = async (id) => (await ixRef(id).get());
const snap = (data) => ({ exists: data != null, data: () => data });
const run = async (name, ...args) => fns[name].run(...args);
const ctx = (iid) => ({ params: { rid: RID, iid } });
const attach = () => idx.attachRestaurantDishIndex({}, { functions: require('firebase-functions'), db });

async function main() {
  await clearEmulator();
  const helpers = attach();

  // ── Sof funksiyalar ────────────────────────────────────────────────
  await check('P1 bir kishilik narx: ceil(narx/porsiya); porsiya yo\'q/0/kasr/narx noto\'g\'ri — null', () => {
    assert.strictEqual(idx.pricePerPerson(35000, 4), 8750);
    assert.strictEqual(idx.pricePerPerson(35001, 4), 8751);
    assert.strictEqual(idx.pricePerPerson(1, 50), 1);
    assert.strictEqual(idx.pricePerPerson(35000, 1), 35000);
    for (const [p, s] of [[35000, 0], [35000, null], [35000, undefined], [35000, 2.5], [0, 2], [-5, 2], ['35000', 2]]) {
      assert.strictEqual(idx.pricePerPerson(p, s), null, `${p}/${s}`);
    }
  });

  await check('P2 bo\'limga kirish: har bo\'lim alohida (musbat + manfiy)', () => {
    const base = { price: 40000 };
    const s = (item, r) => idx.sectionsOf({ ...base, ...item }, r || restaurant());
    assert.deepStrictEqual(s({}), [], 'faktsiz taom — hech qaysi bo\'limda emas');
    assert.deepStrictEqual(s({ servings: 4 }), ['cheap']);
    assert.deepStrictEqual(s({ cuisineGroup: 'national', cuisineId: 'national_ozbek' }), ['national']);
    assert.deepStrictEqual(s({ cuisineGroup: 'world', cuisineId: 'world_turk' }), ['world']);
    assert.deepStrictEqual(s({ cuisineGroup: 'national' }), [], 'kuxna id yo\'q — kirmaydi');
    assert.deepStrictEqual(s({ cuisineGroup: 'other', cuisineId: 'x' }), [], 'noto\'g\'ri guruh');
    const nutri = { kcal: 400, protein: 30, fat: 10, carbs: 40 };
    assert.deepStrictEqual(s({ tags: ['light'], ...nutri }), ['light']);
    assert.deepStrictEqual(s({ tags: ['light'] }), [], '«Yengil» KBJU siz ko\'rinmaydi (ega)');
    assert.deepStrictEqual(s({ ...nutri }), [], 'KBJU bor, teg yo\'q — Yengil emas');
    assert.deepStrictEqual(s({ tags: ['light'], kcal: 400, protein: 30 }), [], 'KBJU to\'liq emas');
    assert.deepStrictEqual(s({ tags: ['kids'] }), ['kids']);
    assert.deepStrictEqual(s({ tags: ['breakfast'] }), ['breakfast']);
    assert.deepStrictEqual(s({ tags: ['night'] }), ['night']);
    assert.deepStrictEqual(s({ tags: ['kids', 'night', 'bunday-teg-yoq'] }), ['kids', 'night']);
    assert.deepStrictEqual(s({}, restaurant({ cuisineTags: ['fastfood'] })), ['fast']);
    assert.deepStrictEqual(s({}, restaurant({ cuisineTags: ['pizza', 'shashlik'] })), []);
    assert.deepStrictEqual(
      s({ servings: 2, cuisineGroup: 'national', cuisineId: 'national_ozbek', tags: ['kids'] }, restaurant({ cuisineTags: ['fastfood'] })).sort(),
      ['cheap', 'fast', 'kids', 'national'].sort(), 'bir taom bir nechta bo\'limda',
    );
  });

  await check('P2b Ofis / Dastarxon / Mavsumiy (D-REST-21/22): oldindan buyurtma + chegirma; teg + oldindan buyurtma; mavsum tegi (musbat + manfiy)', () => {
    const pre = restaurant({ acceptsPreorder: true });
    const tiers = [{ minQty: 10, price: 35000 }];
    const s = (item, r) => idx.sectionsOf({ price: 40000, ...item }, r);
    assert.deepStrictEqual(s({ qtyTiers: tiers }, pre), ['office']);
    assert.deepStrictEqual(s({ qtyTiers: tiers }, restaurant()), [], 'oldindan buyurtma yo\'q — Ofis emas');
    assert.deepStrictEqual(s({ qtyTiers: tiers }, restaurant({ acceptsPreorder: false })), []);
    assert.deepStrictEqual(s({}, pre), [], 'chegirma yo\'q — Ofis emas');
    assert.deepStrictEqual(s({ qtyTiers: [{ minQty: 10, price: 45000 }] }, pre), [], 'narxni ORTTIRADIGAN pog\'ona yaroqsiz — Ofis emas');
    assert.deepStrictEqual(s({ qtyTiers: 'x' }, pre), []);
    assert.deepStrictEqual(s({ tags: ['dastarxon'] }, pre), ['dastarxon']);
    assert.deepStrictEqual(s({ tags: ['dastarxon'] }, restaurant()), [], 'oldindan buyurtma yo\'q — Dastarxon emas');
    assert.deepStrictEqual(s({ tags: ['ramadan'] }, restaurant()), ['seasonal'], 'mavsum tegi oldindan buyurtmasiz ham');
    assert.deepStrictEqual(s({ tags: ['wedding', 'navruz'] }, restaurant()), ['seasonal']);
    assert.deepStrictEqual(s({ tags: ['mavsum-emas'] }, restaurant()), []);
    assert.deepStrictEqual(
      s({ servings: 2, qtyTiers: tiers, tags: ['dastarxon', 'qurbon'] }, pre).sort(),
      ['cheap', 'dastarxon', 'office', 'seasonal'].sort(), 'bir taom bir nechta bo\'limda',
    );
    const d = idx.buildIndexDoc({ rid: RID, iid: 'osh', item: { price: 40000, tags: ['ramadan', 'kids', 'newyear'] }, restaurant: restaurant(), stats: null });
    assert.deepStrictEqual(d.sections.sort(), ['kids', 'seasonal']);
    assert.deepStrictEqual(d.seasons, ['ramadan', 'newyear'], 'indeksda mavsumlar (klient hozir ochiq mavsum bo\'yicha filtrlaydi)');
    assert.deepStrictEqual(idx.buildIndexDoc({ rid: RID, iid: 'osh', item: { price: 40000, servings: 2 }, restaurant: restaurant(), stats: null }).seasons, []);
    assert.strictEqual(idx.MAX_TAGS_PER_DISH, 4);
  });
  await check('P3 indeksga kirmaydi: tasdiqlanmagan restoran, mavjud emas, noto\'g\'ri narx, noto\'g\'ri joy, bo\'limsiz', () => {
    const item = { price: 40000, servings: 4 };
    const b = (i, r, s) => idx.buildIndexDoc({ rid: RID, iid: 'osh', item: i, restaurant: r, stats: s || null });
    assert.ok(b(item, restaurant()));
    for (const st of ['applied', 'rejected', 'suspended', 'closed', undefined]) assert.strictEqual(b(item, restaurant({ status: st })), null, String(st));
    assert.strictEqual(b(null, restaurant()), null);
    assert.strictEqual(b(item, null), null);
    assert.strictEqual(b({ ...item, available: false }, restaurant()), null);
    assert.ok(b({ ...item, available: true }, restaurant()));
    for (const price of ['40000', 0, -1, 40000.5, 50000001, null, undefined]) assert.strictEqual(b({ ...item, price }, restaurant()), null, String(price));
    assert.ok(b({ ...item, price: 50000000 }, restaurant()), 'yuqori chegara kiradi');
    assert.ok(b({ ...item, price: 1 }, restaurant()), 'quyi chegara kiradi');
    for (const loc of [{ lat: 0, lng: 0 }, { lat: 91, lng: 10 }, { lat: 10, lng: 181 }, { lat: 'x', lng: 1 }, { lat: undefined, lng: undefined }]) {
      assert.strictEqual(b(item, restaurant(loc)), null, JSON.stringify(loc));
    }
    assert.strictEqual(b({ price: 40000 }, restaurant()), null, 'hech bir bo\'limga kirmaydi');
  });

  await check('P4 indeks hujjati: maydonlar, geo4 (4 belgi), geohash yo\'q bo\'lsa koordinatadan; baho yig\'indisi; stopUntil/listedAt/ish vaqti nusxasi', () => {
    const created = Timestamp.fromMillis(1_700_000_000_000);
    const stop = Timestamp.fromMillis(1_800_000_000_000);
    const d = idx.buildIndexDoc({
      rid: RID, iid: 'osh',
      item: { name: ' Osh ', price: 40000, servings: 4, weightG: 450, kcal: 600, protein: 30, fat: 25, carbs: 60, cuisineGroup: 'national', cuisineId: 'national_ozbek', tags: ['kids'], createdAt: created, stopUntil: stop, photoUrl: 'https://x/p.jpg' },
      restaurant: restaurant({ openingHours: { open: '09:00', close: '22:00' } }),
      stats: { ratingSum: 47, ratingCount: 10 },
    });
    assert.strictEqual(d.name, 'Osh');
    assert.strictEqual(d.geo4, GEO4);
    assert.strictEqual(d.pricePerPerson, 10000);
    assert.deepStrictEqual([d.servings, d.weightG, d.kcal, d.protein, d.fat, d.carbs], [4, 450, 600, 30, 25, 60]);
    assert.deepStrictEqual([d.cuisineGroup, d.cuisineId], ['national', 'national_ozbek']);
    assert.deepStrictEqual([d.ratingSum, d.ratingCount], [47, 10]);
    assert.strictEqual(d.listedAt, created);
    assert.strictEqual(d.stopUntil, stop);
    assert.deepStrictEqual(d.openingHours, { open: '09:00', close: '22:00' });
    assert.deepStrictEqual([d.restaurantName, d.restaurantLat, d.prepTimeMin, d.v], ['Gurlan osh', GURLAN.lat, 25, idx.INDEX_RULES_VERSION]);
    const noHash = idx.buildIndexDoc({ rid: RID, iid: 'osh', item: { price: 40000, servings: 4 }, restaurant: restaurant({ geohash: undefined }), stats: null });
    assert.strictEqual(noHash.geo4.length, 4);
    assert.strictEqual(noHash.geo4, GEO4, 'koordinatadan hisoblangan geohash ham shu katak');
    const noStats = idx.buildIndexDoc({ rid: RID, iid: 'osh', item: { price: 40000, servings: 4 }, restaurant: restaurant(), stats: { ratingSum: 9, ratingCount: 0 } });
    assert.deepStrictEqual([noStats.ratingSum, noStats.ratingCount], [0, 0], 'soni 0 bo\'lsa yig\'indi ham 0');
    assert.strictEqual('kcal' in noStats, false, 'kiritilmagan fakt hujjatda yo\'q');
  });

  await check('P5 fingerprint barqaror (kalit tartibi/Timestamp); restoran fingerprint\'i reytingga SEZGIR EMAS', () => {
    const t = Timestamp.fromMillis(5000);
    assert.strictEqual(idx.fingerprint({ a: 1, b: { x: t, y: [1, 2] } }), idx.fingerprint({ b: { y: [1, 2], x: Timestamp.fromMillis(5000) }, a: 1 }));
    assert.notStrictEqual(idx.fingerprint({ a: 1 }), idx.fingerprint({ a: 2 }));
    assert.strictEqual(idx.restaurantFingerprint(restaurant()), idx.restaurantFingerprint({ ...restaurant(), ratingAvg: 4.9, ratingCount: 99, ratingSum: 480, description: 'x' }));
    assert.notStrictEqual(idx.restaurantFingerprint(restaurant()), idx.restaurantFingerprint(restaurant({ status: 'suspended' })));
    assert.notStrictEqual(idx.restaurantFingerprint(restaurant()), idx.restaurantFingerprint(restaurant({ name: 'Boshqa' })));
  });

  // ── Emulator: trigger'lar ───────────────────────────────────────────
  await check('T1 taom yozildi → indeks hujjati; menyu trigger\'i orqali; bo\'limsiz taom — hujjat yo\'q', async () => {
    await rRef().set(restaurant());
    await itemRef('osh').set({ name: 'Osh', price: 40000, available: true, servings: 4, categoryId: 'c1', createdAt: Timestamp.now() });
    await run('onRestaurantMenuItemWritten', { before: snap(null), after: snap({}) }, ctx('osh'));
    const d = (await ix('osh')).data();
    assert.deepStrictEqual([d.sections, d.pricePerPerson, d.restaurantId, d.itemId, d.geo4], [['cheap'], 10000, RID, 'osh', GEO4]);
    await itemRef('plain').set({ name: 'Oddiy', price: 10000, available: true });
    await run('onRestaurantMenuItemWritten', { before: snap(null), after: snap({}) }, ctx('plain'));
    assert.strictEqual((await ix('plain')).exists, false);
  });

  await check('T2 o\'zgarmagan taom — QAYTA YOZILMAYDI (updateTime o\'zgarmaydi); narx o\'zgarsa — yoziladi', async () => {
    const before = (await ix('osh')).updateTime.toMillis();
    assert.strictEqual(await helpers.reindexDish(RID, 'osh'), 'unchanged');
    assert.strictEqual((await ix('osh')).updateTime.toMillis(), before);
    await itemRef('osh').update({ price: 44000 });
    assert.strictEqual(await helpers.reindexDish(RID, 'osh'), 'written');
    assert.strictEqual((await ix('osh')).data().pricePerPerson, 11000);
  });

  await check('T3 teg/kuxna qo\'shildi → bo\'limlar kengayadi; olib tashlandi → qisqaradi (ega «ma\'lumot to\'liqligi»)', async () => {
    await itemRef('osh').update({ tags: ['kids', 'night'], cuisineGroup: 'national', cuisineId: 'national_ozbek' });
    await helpers.reindexDish(RID, 'osh');
    assert.deepStrictEqual((await ix('osh')).data().sections.sort(), ['cheap', 'kids', 'national', 'night']);
    await itemRef('osh').update({ tags: ['kids'] });
    await helpers.reindexDish(RID, 'osh');
    assert.deepStrictEqual((await ix('osh')).data().sections.sort(), ['cheap', 'kids', 'national']);
  });

  await check('T4 taom to\'xtatildi (available=false) yoki o\'chirildi → indeks hujjati o\'chadi; qaytarilsa — yana paydo', async () => {
    await itemRef('osh').update({ available: false });
    assert.strictEqual(await helpers.reindexDish(RID, 'osh'), 'deleted');
    assert.strictEqual((await ix('osh')).exists, false);
    assert.strictEqual(await helpers.reindexDish(RID, 'osh'), 'unchanged', 'takroriy o\'chirish xatosiz');
    await itemRef('osh').update({ available: true });
    assert.strictEqual(await helpers.reindexDish(RID, 'osh'), 'written');
    await itemRef('osh').delete();
    await run('onRestaurantMenuItemWritten', { before: snap({}), after: snap(null) }, ctx('osh'));
    assert.strictEqual((await ix('osh')).exists, false);
  });

  await check('T5 baho keldi (stats trigger\'i) → indeksda ratingSum/ratingCount yangilanadi', async () => {
    await itemRef('osh').set({ name: 'Osh', price: 40000, available: true, servings: 4 });
    await helpers.reindexDish(RID, 'osh');
    await rRef().collection('menu_item_stats').doc('osh').set({ ratingSum: 14, ratingCount: 3 });
    await run('onRestaurantDishStatsWritten', { before: snap(null), after: snap({}) }, ctx('osh'));
    const d = (await ix('osh')).data();
    assert.deepStrictEqual([d.ratingSum, d.ratingCount], [14, 3]);
  });

  await check('T6 RESTORAN trigger\'i: tasdiq/yopish/nom — barcha taomlar fan-out; reyting o\'zgarishi fan-out QILMAYDI', async () => {
    await itemRef('a').set({ name: 'A', price: 10000, available: true, servings: 1 });
    await itemRef('b').set({ name: 'B', price: 20000, available: true, tags: ['kids'] });
    const prev = restaurant();
    await run('onRestaurantIndexSourceWritten', { before: snap(prev), after: snap(prev) }, { params: { rid: RID } }); // o'zgarishsiz
    await rRef().update({ name: 'Yangi nom' });
    const next = restaurant({ name: 'Yangi nom' });
    await run('onRestaurantIndexSourceWritten', { before: snap(prev), after: snap(next) }, { params: { rid: RID } });
    for (const id of ['osh', 'a', 'b']) assert.strictEqual((await ix(id)).data().restaurantName, 'Yangi nom', id);
    // reyting o'zgardi — fingerprint bir xil → hech narsa qayta yozilmaydi
    const upd = (await ix('a')).updateTime.toMillis();
    await run('onRestaurantIndexSourceWritten', { before: snap(next), after: snap({ ...next, ratingAvg: 4.9, ratingCount: 50 }) }, { params: { rid: RID } });
    assert.strictEqual((await ix('a')).updateTime.toMillis(), upd);
    // yopildi → hammasi o'chadi
    await rRef().update({ status: 'suspended' });
    await run('onRestaurantIndexSourceWritten', { before: snap(next), after: snap({ ...next, status: 'suspended' }) }, { params: { rid: RID } });
    for (const id of ['osh', 'a', 'b']) assert.strictEqual((await ix(id)).exists, false, id);
    // qayta tasdiqlandi → hammasi qaytadi
    await rRef().update({ status: 'approved' });
    await run('onRestaurantIndexSourceWritten', { before: snap({ ...next, status: 'suspended' }), after: snap(next) }, { params: { rid: RID } });
    for (const id of ['osh', 'a', 'b']) assert.strictEqual((await ix(id)).exists, true, id);
  });

  await check('T6b oldindan buyurtma belgisi o\'zgardi (restoran trigger\'i) → Ofis/Dastarxon bo\'limlari paydo bo\'ladi / yo\'qoladi; chegirma o\'chsa Ofis ketadi', async () => {
    await itemRef('osh').set({ name: 'Osh', price: 40000, available: true, servings: 4 });
    await itemRef('a').set({ name: 'A', price: 10000, available: true, qtyTiers: [{ minQty: 10, price: 9000 }] });
    await itemRef('b').set({ name: 'B', price: 20000, available: true, tags: ['dastarxon', 'ramadan'] });
    const off = restaurant({ acceptsPreorder: false });
    const on = restaurant({ acceptsPreorder: true });
    await rRef().set(off);
    await run('onRestaurantIndexSourceWritten', { before: snap(null), after: snap(off) }, { params: { rid: RID } });
    assert.strictEqual((await ix('a')).exists, false, 'chegirma bor, lekin oldindan buyurtma yo\'q — bo\'limsiz');
    assert.deepStrictEqual((await ix('b')).data().sections, ['seasonal']);
    await rRef().set(on);
    await run('onRestaurantIndexSourceWritten', { before: snap(off), after: snap(on) }, { params: { rid: RID } });
    assert.deepStrictEqual((await ix('a')).data().sections, ['office']);
    assert.deepStrictEqual((await ix('b')).data().sections.sort(), ['dastarxon', 'seasonal']);
    assert.deepStrictEqual((await ix('b')).data().seasons, ['ramadan']);
    await itemRef('a').update({ qtyTiers: admin.firestore.FieldValue.delete() });
    await run('onRestaurantMenuItemWritten', { before: snap({}), after: snap({}) }, ctx('a'));
    assert.strictEqual((await ix('a')).exists, false, 'chegirma olib tashlandi — Ofis ketdi');
    await rRef().set(off);
    await run('onRestaurantIndexSourceWritten', { before: snap(on), after: snap(off) }, { params: { rid: RID } });
    assert.deepStrictEqual((await ix('b')).data().sections, ['seasonal'], 'belgi o\'chdi — Dastarxon ketdi');
    await rRef().set(restaurant());
  });
  await check('T7 restoran o\'chirildi → barcha indeks hujjatlari o\'chadi', async () => {
    const cur = (await rRef().get()).data();
    await rRef().delete();
    await run('onRestaurantIndexSourceWritten', { before: snap(cur), after: snap(null) }, { params: { rid: RID } });
    for (const id of ['osh', 'a', 'b']) assert.strictEqual((await ix(id)).exists, false, id);
  });

  await check('T8 yetim indeks (taomi o\'chgan, trigger o\'tkazib yuborgan) restoran qayta hisoblashda tozalanadi', async () => {
    await rRef().set(restaurant());
    await ixRef('ghost').set({ restaurantId: RID, itemId: 'ghost', sections: ['cheap'], geo4: GEO4 });
    const counts = await helpers.reindexRestaurant(RID);
    assert.strictEqual((await ix('ghost')).exists, false);
    assert.ok(counts.deleted >= 1, JSON.stringify(counts));
  });

  await check('T9 PARALLEL qayta hisoblash (12 marta): bitta to\'g\'ri hujjat, xato yo\'q', async () => {
    await itemRef('p').set({ name: 'P', price: 30000, available: true, servings: 3 });
    const out = await Promise.allSettled(Array.from({ length: 12 }, () => helpers.reindexDish(RID, 'p')));
    assert.strictEqual(out.filter((x) => x.status === 'rejected').length, 0, JSON.stringify(out.filter((x) => x.status === 'rejected').map((x) => String(x.reason))));
    const d = (await ix('p')).data();
    assert.deepStrictEqual([d.price, d.pricePerPerson], [30000, 10000]);
    const n = (await db.collection('restaurant_dish_index').where('itemId', '==', 'p').get()).size;
    assert.strictEqual(n, 1);
  });

  await check('T10 sozlash tartibi: taom o\'zgardi + trigger kechikdi — OXIRGI manba holati yoziladi (eski qiymat qaytib yozilmaydi)', async () => {
    await itemRef('q').set({ name: 'Q', price: 10000, available: true, servings: 1 });
    await helpers.reindexDish(RID, 'q');
    await itemRef('q').update({ price: 20000 });
    // «eski» trigger kechikib ishga tushdi — u ham manbadan o'qiydi, shuning uchun yangi narx
    await Promise.all([helpers.reindexDish(RID, 'q'), helpers.reindexDish(RID, 'q')]);
    assert.strictEqual((await ix('q')).data().price, 20000);
  });

  await check('B1 backfill: dry-run hech narsa yozmaydi; --apply indekslaydi, yetimni va bo\'limsizni o\'chiradi; takror — hammasi o\'zgarmagan', async () => {
    const backfill = require('../tools/backfill_restaurant_dish_index');
    await clearEmulator();
    await rRef().set(restaurant());
    await db.collection('restaurants').doc('rest2').set(restaurant({ status: 'applied' }));
    await itemRef('a').set({ name: 'A', price: 10000, available: true, servings: 2 });
    await itemRef('b').set({ name: 'B', price: 20000, available: true, tags: ['kids'] });
    await itemRef('c').set({ name: 'C', price: 5000, available: true });
    await db.collection('restaurants').doc('rest2').collection('menu_items').doc('z').set({ name: 'Z', price: 9000, available: true, servings: 1 });
    await ixRef('ghost').set({ restaurantId: RID, itemId: 'ghost', sections: ['cheap'], geo4: GEO4 });
    await ixRef('c').set({ restaurantId: RID, itemId: 'c', sections: ['cheap'], geo4: GEO4 }); // endi bo'limsiz — o'chishi kerak
    await rRef().collection('menu_item_stats').doc('a').set({ ratingSum: 9, ratingCount: 2 });

    const dry = await backfill.run(db, { apply: false });
    assert.deepStrictEqual([dry.written, dry.deleted], [2, 2], JSON.stringify(dry));
    assert.strictEqual((await ix('a')).exists, false, 'dry-run yozmadi');
    assert.strictEqual((await ix('ghost')).exists, true, 'dry-run o\'chirmadi');

    const applied = await backfill.run(db, { apply: true });
    assert.deepStrictEqual([applied.written, applied.deleted], [2, 2], JSON.stringify(applied));
    assert.deepStrictEqual((await ix('a')).data().sections, ['cheap']);
    assert.deepStrictEqual([(await ix('a')).data().ratingSum, (await ix('a')).data().ratingCount], [9, 2]);
    assert.deepStrictEqual((await ix('b')).data().sections, ['kids']);
    assert.strictEqual((await ix('c')).exists, false);
    assert.strictEqual((await ix('ghost')).exists, false);
    assert.strictEqual((await db.collection('restaurant_dish_index').doc('rest2_z').get()).exists, false, 'tasdiqlanmagan restoran indeksga kirmaydi');

    const again = await backfill.run(db, { apply: true });
    assert.deepStrictEqual([again.written, again.deleted], [0, 0], JSON.stringify(again));
  });

  // ── Sozlama callable'i ──────────────────────────────────────────────
  await clearEmulator();
  await db.collection('users').doc(ADMIN).set({ role: 'admin', bonusBalance: 0 });
  await db.collection('users').doc(NOADMIN).set({ role: 'user', bonusBalance: 0 });
  const cfgRef = db.collection('settings').doc('restaurant_sections');
  const setCfg = (data, who = ADMIN) => fns.adminSetRestaurantSections.run(data, ctxOf(who));

  await check('C1 faqat admin: oddiy foydalanuvchi va kirmagan — rad; hujjat yaratilmaydi', async () => {
    await assert.rejects(setCfg({ sections: { cheap: 'public' } }, NOADMIN));
    await assert.rejects(fns.adminSetRestaurantSections.run({ sections: { cheap: 'public' } }, {}));
    assert.strictEqual((await cfgRef.get()).exists, false);
  });

  await check('C2 birinchi saqlash: v1, ega qiymatlari (5.0 / 5 / 30 / 3), berilmagan bo\'lim — off; tarix va audit yoziladi', async () => {
    const r = await setCfg({ sections: { cheap: 'internal' }, testerIds: [NOADMIN], reason: 'sinov' });
    assert.deepStrictEqual([r.ok, r.version, r.changed], [true, 1, true]);
    const d = (await cfgRef.get()).data();
    assert.strictEqual(d.version, 1);
    assert.deepStrictEqual([d.cheapRatingThreshold, d.newMaxRatings, d.newMaxDays, d.newPerRestaurantPerSection], [5, 5, 30, 3]);
    assert.strictEqual(d.sections.cheap, 'internal');
    for (const k of idx.SECTION_KEYS.filter((x) => x !== 'cheap')) assert.strictEqual(d.sections[k], 'off', k);
    assert.deepStrictEqual(d.testerIds, [NOADMIN]);
    assert.strictEqual(d.updatedBy, ADMIN);
    assert.strictEqual((await db.collection('restaurant_sections_history').doc('v1').get()).exists, true);
    const audit = await db.collection('admin_audit').where('kind', '==', 'restaurant_sections_set').get();
    assert.strictEqual(audit.size, 1);
    assert.strictEqual(audit.docs[0].data().reason, 'sinov');
  });

  await check('C3 qisman o\'zgarish: faqat berilgani o\'zgaradi (boshqalar saqlanadi); versiya +1', async () => {
    const r = await setCfg({ sections: { national: 'public' }, cheapRatingThreshold: 4.5 });
    assert.deepStrictEqual([r.version, r.changed], [2, true]);
    const d = (await cfgRef.get()).data();
    assert.strictEqual(d.sections.cheap, 'internal', 'avvalgisi saqlandi');
    assert.strictEqual(d.sections.national, 'public');
    assert.strictEqual(d.cheapRatingThreshold, 4.5);
    assert.deepStrictEqual(d.testerIds, [NOADMIN]);
    assert.strictEqual(d.newMaxDays, 30);
  });

  await check('C4 IDEMPOTENT: bir xil takroriy chaqiruv versiyani OSHIRMAYDI va tarix/audit qo\'shmaydi', async () => {
    const hist = (await db.collection('restaurant_sections_history').get()).size;
    const aud = (await db.collection('admin_audit').where('kind', '==', 'restaurant_sections_set').get()).size;
    const r = await setCfg({ sections: { national: 'public' }, cheapRatingThreshold: 4.5 });
    assert.deepStrictEqual([r.version, r.changed], [2, false]);
    assert.strictEqual((await db.collection('restaurant_sections_history').get()).size, hist);
    assert.strictEqual((await db.collection('admin_audit').where('kind', '==', 'restaurant_sections_set').get()).size, aud);
  });

  await check('C5 noto\'g\'ri qiymatlar rad: bosqich, noma\'lum bo\'lim, chegara (0.5, 5.5, 4.999, NaN), «Yangi» qoidalari, testerlar', async () => {
    await expectCode(setCfg({ sections: { cheap: 'PUBLIC' } }), 'STAGE_INVALID');
    await expectCode(setCfg({ sections: { cheap: 'pilot' } }), 'STAGE_INVALID');
    await expectCode(setCfg({ sections: ['cheap'] }), 'STAGE_INVALID');
    await expectCode(setCfg({ sections: { arzon: 'public' } }), 'SECTION_UNKNOWN');
    for (const t of [0.5, 5.5, 4.999, 'abc', -1]) await expectCode(setCfg({ cheapRatingThreshold: t }), 'THRESHOLD_INVALID');
    for (const [k, v] of [['newMaxRatings', 0], ['newMaxRatings', 101], ['newMaxDays', 0], ['newMaxDays', 366], ['newPerRestaurantPerSection', 0], ['newPerRestaurantPerSection', 21], ['newMaxDays', 2.5]]) {
      await expectCode(setCfg({ [k]: v }), 'NEW_RULE_INVALID');
    }
    await expectCode(setCfg({ testerIds: ['123'] }), 'TESTERS_INVALID');
    await expectCode(setCfg({ testerIds: 'x' }), 'TESTERS_INVALID');
    assert.strictEqual((await cfgRef.get()).data().version, 2, 'rad etilganlar versiyani o\'zgartirmadi');
  });

  await check('C6 chegaralar qabul: threshold 1 va 5, 4.25 (2 xona); newMaxRatings 1..100; testerIds takrorlari birlashadi', async () => {
    await setCfg({ cheapRatingThreshold: 1 });
    assert.strictEqual((await cfgRef.get()).data().cheapRatingThreshold, 1);
    await setCfg({ cheapRatingThreshold: 4.25, newMaxRatings: 100, newMaxDays: 365, newPerRestaurantPerSection: 20, testerIds: [NOADMIN, NOADMIN, `+${ADMIN}`] });
    const d = (await cfgRef.get()).data();
    assert.deepStrictEqual([d.cheapRatingThreshold, d.newMaxRatings, d.newMaxDays, d.newPerRestaurantPerSection], [4.25, 100, 365, 20]);
    assert.deepStrictEqual(d.testerIds.sort(), [ADMIN, NOADMIN].sort());
    assert.strictEqual(cfg.DEFAULTS.cheapRatingThreshold, 5, 'ega qarori');
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
