/**
 * НАМУНА кафе/уй ошпазлари — seed tool + авто-ўчириш (functions/restaurant_demo.js), Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-restaurant-demo \
 *     "node test/restaurant_demo_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-restaurant-demo';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const demo = require('../restaurant_demo');
const { seedDemos, removeAllDemos } = require('../tools/seed_demo_restaurants');

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
const exists = async (id) => (await db.collection('restaurants').doc(id).get()).exists;
const ids = async () => (await db.collection('restaurants').where('isDemo', '==', true).get()).docs.map((d) => d.id).sort();

/** `venueType` 'home' → legalType individual (restaurantRegister qoidasi); `legacyHome` — eski hujjat: legalType bor, venueType YO'Q. */
async function addReal(id, venueType, status = 'approved', { legacyHome = false } = {}) {
  const home = venueType === 'home' || legacyHome;
  await db.collection('restaurants').doc(id).set({
    name: id, status, legalType: home ? 'individual' : 'llc',
    ...(venueType && !legacyHome ? { venueType } : {}), ownerUid: `owner_${id}`, lat: 41.3, lng: 69.2,
  });
}

async function main() {
  await clearEmulator();

  await check('P1 tuplam: 6 ta (3 kafe + 3 uy), har birida 5 taom, 2 kategoriya; ID/tur/narx to\'g\'ri', () => {
    assert.strictEqual(demo.DEMO_SET.length, 6);
    assert.strictEqual(demo.DEMO_SET.filter((s) => s.kind === 'cafe').length, 3);
    assert.strictEqual(demo.DEMO_SET.filter((s) => s.kind === 'home').length, 3);
    assert.strictEqual(new Set(demo.DEMO_SET.map((s) => s.id)).size, 6);
    for (const s of demo.DEMO_SET) {
      assert.strictEqual(s.dishes.length, 5, s.id);
      assert.strictEqual(s.categories.length, 2, s.id);
      assert.strictEqual(s.cat.length, 5, s.id);
      assert.ok(s.cat.every((c) => c === 0 || c === 1), s.id);
      for (const d of s.dishes) {
        assert.ok(Number.isInteger(d.price) && d.price > 0 && d.price <= 50000000, `${s.id} narx butun (8-qoida)`);
        assert.ok(d.name.length >= 1 && d.name.length <= 80 && d.description.length <= 500);
        assert.ok(d.servings >= 1 && d.servings <= 50 && d.weightG >= 10 && d.weightG <= 5000);
      }
      assert.strictEqual(s.kind === 'home', s.venueType === 'home');
      assert.strictEqual(s.kind === 'home', s.legalType === 'individual');
    }
  });

  await check('P2 hujjat shakli: demo belgisi, lentada KO\'RINADI (pauza ham, ish vaqti ham yo\'q), telefon bo\'sh, koordinata O\'zbekistonda', () => {
    const ts = new Date();
    for (const s of demo.DEMO_SET) {
      const d = demo.buildDemoDocs(s, { ts });
      assert.strictEqual(d.restaurant.isDemo, true);
      assert.strictEqual(d.restaurant.status, 'approved');
      assert.strictEqual(d.restaurant.pausedUntil, null, 'pauza bo\'lsa lenta/bosh sahifadan yashiriladi');
      assert.strictEqual(d.restaurant.openingHours, null, 'ish vaqti bo\'lsa kechasi yopiq ko\'rinadi');
      assert.strictEqual(d.restaurant.contactPhone, '');
      assert.ok(d.restaurant.lat >= 36 && d.restaurant.lat <= 46 && d.restaurant.lng >= 55 && d.restaurant.lng <= 74);
      assert.ok(d.restaurant.address.length >= 5 && d.restaurant.geohash.length === 7);
      assert.ok(d.restaurant.announcement.includes('Намуна'));
      assert.strictEqual(d.items.length, 5);
      assert.ok(d.items.every((i) => ['c1', 'c2'].includes(i.data.categoryId)));
    }
  });

  await check('K1 kindOf: legalType individual = uy oshpazi (venueType bo\'lmasa ham); yatt/llc = kafe; bo\'sh = kafe', () => {
    assert.strictEqual(demo.kindOf({ legalType: 'individual' }), 'home');
    assert.strictEqual(demo.kindOf({ legalType: 'individual', venueType: 'home' }), 'home');
    assert.strictEqual(demo.kindOf({ venueType: 'home' }), 'home');
    assert.strictEqual(demo.kindOf({ legalType: 'llc' }), 'cafe');
    assert.strictEqual(demo.kindOf({ legalType: 'yatt', venueType: 'chaikhana' }), 'cafe');
    assert.strictEqual(demo.kindOf({}), 'cafe');
    assert.strictEqual(demo.kindOf(null), 'cafe');
  });

  await check('P3 har bir namuna taomi uchun bosh sahifa indeksi (restaurant_dish_index) hujjati hosil bo\'ladi', () => {
    const { buildIndexDoc } = require('../restaurant_dish_index');
    const ts = new Date();
    for (const s of demo.DEMO_SET) {
      const d = demo.buildDemoDocs(s, { ts });
      for (const i of d.items) {
        const x = buildIndexDoc({ rid: s.id, iid: i.id, item: i.data, restaurant: d.restaurant, stats: null });
        assert.ok(x, `${s.id}/${i.id} indeksga kirmaydi`);
        assert.strictEqual(x.restaurantId, s.id);
      }
    }
  });

  await check('S1 dry-run: hech narsa yozilmaydi, reja 6 ta create', async () => {
    const r = await seedDemos(db, admin, { apply: false });
    assert.strictEqual(r.applied, false);
    assert.strictEqual(r.plan.filter((p) => p.action === 'create').length, 6);
    assert.deepStrictEqual(await ids(), []);
  });

  await check('S2 apply: 6 restoran, har birida 5 taom + 2 kategoriya; audit yoziladi', async () => {
    const r = await seedDemos(db, admin, { apply: true });
    assert.strictEqual(r.created.length, 6);
    assert.deepStrictEqual(await ids(), demo.DEMO_SET.map((s) => s.id).sort());
    for (const s of demo.DEMO_SET) {
      const base = db.collection('restaurants').doc(s.id);
      assert.strictEqual((await base.collection('menu_items').get()).size, 5, s.id);
      assert.strictEqual((await base.collection('menu_categories').get()).size, 2, s.id);
    }
    assert.strictEqual((await db.collection('admin_audit').where('kind', '==', 'demo_restaurants_seed').get()).size, 1);
  });

  await check('S3 qayta apply — takror yaratmaydi, mavjudga tegmaydi (idempotent)', async () => {
    await db.collection('restaurants').doc('demo_cafe_1').update({ name: 'Admin o\'zgartirgan' });
    const r = await seedDemos(db, admin, { apply: true });
    assert.deepStrictEqual(r.created, []);
    assert.strictEqual(r.plan.filter((p) => p.action === 'exists').length, 6);
    assert.strictEqual((await db.collection('restaurants').doc('demo_cafe_1').get()).data().name, 'Admin o\'zgartirgan');
    assert.strictEqual((await db.collection('admin_audit').where('kind', '==', 'demo_restaurants_seed').get()).size, 1);
  });

  await check('T1 shouldEvaluate: faqat yangi approved va demo emas', () => {
    assert.ok(demo.shouldEvaluate(null, { status: 'approved' }));
    assert.ok(demo.shouldEvaluate({ status: 'applied' }, { status: 'approved' }));
    assert.ok(!demo.shouldEvaluate({ status: 'approved' }, { status: 'approved', name: 'x' }), 'oddiy tahrir');
    assert.ok(!demo.shouldEvaluate({ status: 'applied' }, { status: 'rejected' }));
    assert.ok(!demo.shouldEvaluate(null, { status: 'approved', isDemo: true }), 'demo o\'zi trigger bermaydi');
    assert.ok(!demo.shouldEvaluate({ status: 'approved' }, null), 'o\'chirish');
  });

  await check('C1 2 ta haqiqiy kafe — hech narsa o\'chmaydi (chegara: 3 dan kam)', async () => {
    await addReal('real_cafe_1', 'cafe');
    await addReal('real_cafe_2', 'restaurant');
    const out = await demo.cleanupDemos(db, { admin });
    assert.deepStrictEqual(out.removed, []);
    assert.deepStrictEqual(out.real, { home: 0, cafe: 2 });
    assert.strictEqual((await ids()).length, 6);
  });

  await check('C2 applied/rejected haqiqiy subyektlar hisoblanmaydi (faqat approved)', async () => {
    await addReal('real_cafe_pending', 'cafe', 'applied');
    await addReal('real_cafe_rej', 'cafe', 'rejected');
    const out = await demo.cleanupDemos(db, { admin });
    assert.deepStrictEqual(out.removed, []);
    assert.deepStrictEqual(out.real, { home: 0, cafe: 2 });
  });

  await check('C3 3-haqiqiy kafe approved — faqat KAFE namunalari o\'chadi, uy ovqatchilari qoladi; indeks va menyu ham', async () => {
    await db.collection('restaurant_dish_index').doc('demo_cafe_2_d1').set({ restaurantId: 'demo_cafe_2', itemId: 'd1' });
    await addReal('real_cafe_3', undefined); // venueType yo'q (eski hujjat) = kafe
    const out = await demo.cleanupDemos(db, { admin });
    assert.deepStrictEqual(out.removed.sort(), ['demo_cafe_1', 'demo_cafe_2', 'demo_cafe_3']);
    assert.deepStrictEqual(await ids(), ['demo_home_1', 'demo_home_2', 'demo_home_3']);
    assert.strictEqual((await db.collection('restaurants').doc('demo_cafe_1').collection('menu_items').get()).size, 0, 'menyu ham o\'chdi');
    assert.strictEqual((await db.collection('restaurant_dish_index').where('restaurantId', '==', 'demo_cafe_2').get()).size, 0);
    assert.strictEqual(await exists('real_cafe_1'), true, 'haqiqiy subyektga tegilmaydi');
    const audit = (await db.collection('admin_audit').where('kind', '==', 'demo_restaurants_cleanup').get()).docs.map((d) => d.data());
    assert.strictEqual(audit.length, 1);
    assert.deepStrictEqual(audit[0].removed.sort(), ['demo_cafe_1', 'demo_cafe_2', 'demo_cafe_3']);
    assert.strictEqual(audit[0].actor, 'system:demo_cleanup');
  });

  await check('C4 takror chaqiruv — hech narsa qilmaydi, yangi audit yo\'q (idempotent)', async () => {
    const out = await demo.cleanupDemos(db, { admin });
    assert.deepStrictEqual(out.removed, []);
    assert.strictEqual((await db.collection('admin_audit').where('kind', '==', 'demo_restaurants_cleanup').get()).size, 1);
  });

  await check('C5 uy ovqatchilari: 3 ta haqiqiy approved uy ovqatchisi — uy namunalari o\'chadi', async () => {
    await addReal('real_home_1', 'home');
    // ESKI hujjat (prodagi 2 ta shunday): legalType individual, venueType YO'Q — uy oshpazi sifatida sanalishi shart.
    await addReal('real_home_2', undefined, 'approved', { legacyHome: true });
    assert.deepStrictEqual((await demo.cleanupDemos(db, { admin })).removed, []);
    await addReal('real_home_3', 'home');
    const out = await demo.cleanupDemos(db, { admin });
    assert.deepStrictEqual(out.removed.sort(), ['demo_home_1', 'demo_home_2', 'demo_home_3']);
    assert.deepStrictEqual(await ids(), []);
    // kafe haqiqiylari uy hisobiga aralashmagan edi
    assert.deepStrictEqual(out.real, { home: 3, cafe: 3 });
  });

  await check('S4 haqiqiy soni yetarli bo\'lsa seed shu turni yaratmaydi (skip_real_enough)', async () => {
    const r = await seedDemos(db, admin, { apply: true });
    assert.strictEqual(r.plan.filter((p) => p.action === 'skip_real_enough').length, 6);
    assert.deepStrictEqual(r.created, []);
    assert.deepStrictEqual(await ids(), []);
  });

  await check('F1 --refresh: eski (pausedUntil 2099 + ish vaqti) namunalar tuzatiladi; toza namunaga tegilmaydi; dry-run yozmaydi', async () => {
    await clearEmulator();
    await seedDemos(db, admin, { apply: true });
    // Eski holatni taqlid qilamiz (prodagi 6 ta shunday yaratilgan edi).
    await db.collection('restaurants').doc('demo_cafe_1').update({
      pausedUntil: admin.firestore.Timestamp.fromDate(new Date('2099-01-01T00:00:00Z')),
      openingHours: { open: '09:00', close: '22:00' },
    });
    await db.collection('restaurants').doc('demo_home_2').update({ pausedUntil: admin.firestore.Timestamp.fromDate(new Date('2099-01-01T00:00:00Z')) });
    const { refreshDemos } = require('../tools/seed_demo_restaurants');
    const dry = await refreshDemos(db, admin, { apply: false });
    assert.deepStrictEqual(dry.ids.sort(), ['demo_cafe_1', 'demo_home_2']);
    assert.notStrictEqual((await db.collection('restaurants').doc('demo_cafe_1').get()).data().pausedUntil, null, 'dry-run yozmaydi');
    const r = await refreshDemos(db, admin, { apply: true });
    assert.strictEqual(r.applied, true);
    for (const id of ['demo_cafe_1', 'demo_home_2']) {
      const x = (await db.collection('restaurants').doc(id).get()).data();
      assert.strictEqual(x.pausedUntil, null, id);
      assert.strictEqual(x.openingHours, null, id);
      assert.strictEqual(x.isDemo, true);
      assert.strictEqual(x.status, 'approved');
    }
    assert.deepStrictEqual((await refreshDemos(db, admin, { apply: true })).ids, [], 'takror — hech narsa (idempotent)');
  });

  await check('R1 --remove: barcha demo qo\'lda olib tashlanadi; haqiqiylar qoladi', async () => {
    await clearEmulator();
    await addReal('real_x', 'cafe');
    await seedDemos(db, admin, { apply: true });
    assert.strictEqual((await ids()).length, 6);
    const dry = await removeAllDemos(db, admin, { apply: false });
    assert.strictEqual(dry.ids.length, 6);
    assert.strictEqual((await ids()).length, 6, 'dry-run o\'chirmaydi');
    const r = await removeAllDemos(db, admin, { apply: true });
    assert.strictEqual(r.ids.length, 6);
    assert.deepStrictEqual(await ids(), []);
    assert.strictEqual(await exists('real_x'), true);
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
