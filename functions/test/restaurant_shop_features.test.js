/**
 * Кафе-ресторан: доимий ҳавола + QR, кўришлар статистикаси, глобал қидирув, backfill — ҲАҚИҚИЙ `functions/index.js`,
 * Firestore Emulator (дўкон модуллари `shop_links.js`, `shop_stats.js`, `shop_search_index.js` умумлаштирилди).
 *
 *   firebase emulators:exec --only firestore --project demo-restaurant-shop "node test/restaurant_shop_features.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-restaurant-shop';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const links = require('../shop_links');
const stats = require('../shop_stats');
const { restaurantToSearchEntry, restaurantSearchFingerprint } = require('../shop_search_index');

const db = admin.firestore();
const OWNER = '998915100001';
const STAFF = '998915100002';
const STRANGER = '998915100003';
const VIEWER = '998915100004';
const R1 = 'rAppr1';
const R2 = 'rApplied2';
const RHOME = 'rHome3';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const ctxAnon = (u) => ({ auth: { uid: u, token: {} } });
const call = (name, data, who) => fns[name].run(data, who ? ctxOf(who) : {});
const rec = (data, ctx) => fns.recordShopEvent.run(data, ctx);
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
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
async function renderPage(path, lang = 'uz') {
  let status = 0;
  let body = '';
  const headers = {};
  const [p, qs] = path.split('?');
  const query = Object.fromEntries(new URLSearchParams(qs || ''));
  const req = { path: p, query, get: (h) => (h.toLowerCase() === 'accept-language' ? lang : '') };
  const res = {
    set: (k, v) => { headers[k] = v; return res; },
    status: (s) => { status = s; return res; },
    send: (b) => { body = String(b); return res; },
  };
  await fns.shopPage(req, res);
  return { status, body, headers };
}
const rRef = (id) => db.collection('restaurants').doc(id);
const idx = async (id) => (await db.collection('search_index').doc(id).get()).data();
/** v2 триггер: ҳақиқий ҳужжат ҳолати, [before] — ихтиёрий снапшот. */
async function fireRestaurant(id, before) {
  const after = await rRef(id).get();
  await fns.onSearchIndexRestaurantWrite.run({ params: { rid: id }, data: before ? { before, after } : { after } });
}

async function seed() {
  await rRef(R1).set({
    name: 'Gurlan <Osh> markazi', status: 'approved', ownerUid: OWNER, legalType: 'llc', venueType: 'cafe',
    address: 'Gurlan, Mustaqillik 5', contactPhone: '+998915100001', coverUrl: 'https://x/cover.jpg',
    cuisineTags: ['milliy'], lat: 41.84, lng: 60.39,
  });
  await rRef(R1).collection('members').doc(OWNER).set({ role: 'owner' });
  await rRef(R1).collection('members').doc(STAFF).set({ role: 'staff' });
  const m = rRef(R1).collection('menu_items');
  await m.doc('osh').set({ name: 'Osh', price: 40000, available: true, sort: 2, photoUrl: 'https://x/osh.jpg' });
  await m.doc('somsa').set({ name: 'Somsa', price: 8000, available: true, sort: 1 });
  await m.doc('stop').set({ name: 'Manti (tugadi)', price: 30000, available: false, sort: 3 });
  // Stop-list (`stopUntil` kelajakda) — sotuvda emas; muddati o'tgan stop — yana sotuvda (restaurant_orders.js qoidasi).
  await m.doc('chuchvara').set({ name: 'Chuchvara (stop)', price: 25000, available: true, sort: 4,
    stopUntil: admin.firestore.Timestamp.fromMillis(Date.now() + 3600000) });
  await m.doc('lagmon').set({ name: 'Lagmon', price: 35000, available: true, sort: 5,
    stopUntil: admin.firestore.Timestamp.fromMillis(Date.now() - 3600000) });
  await rRef(R2).set({ name: 'Yangi kafe', status: 'applied', ownerUid: OWNER, legalType: 'llc' });
  await rRef(R2).collection('members').doc(OWNER).set({ role: 'owner' });
  await rRef(RHOME).set({ name: 'Onamning oshxonasi', status: 'approved', ownerUid: STRANGER, legalType: 'individual', address: 'uy manzili' });
  await rRef(RHOME).collection('members').doc(STRANGER).set({ role: 'owner' });
}

async function main() {
  await clearEmulator();
  await seed();

  // ── 1. Ҳавола ва QR ──────────────────────────────────────────────────────
  let rid1;
  await check('L1 getMyShopLink(restaurantId): loginsiz rad; egasi — havola (telefonsiz), takror — o\'sha; xodim ham o\'sha havolani oladi', async () => {
    await assert.rejects(call('getMyShopLink', { restaurantId: R1 }, null));
    const a = await call('getMyShopLink', { restaurantId: R1 }, OWNER);
    assert.ok(links.isPublicId(a.publicId), a.publicId);
    assert.strictEqual(a.url, `https://master-taxi-gurlan.web.app/s/${a.publicId}`);
    assert.ok(!a.url.includes(OWNER.slice(3)));
    rid1 = a.publicId;
    assert.strictEqual((await call('getMyShopLink', { restaurantId: R1 }, OWNER)).publicId, rid1, 'idempotent');
    assert.strictEqual((await call('getMyShopLink', { restaurantId: R1 }, STAFF)).publicId, rid1, 'xodim');
    assert.strictEqual((await rRef(R1).get()).data().publicId, rid1);
  });

  await check('L2 begona / yo\'q / axlat ID — RESTAURANT_NOT_FOUND; tasdiqlanmagan — RESTAURANT_NOT_APPROVED (havola yozilmaydi)', async () => {
    await expectCode(call('getMyShopLink', { restaurantId: R1 }, STRANGER), 'RESTAURANT_NOT_FOUND');
    await expectCode(call('getMyShopLink', { restaurantId: 'yoq' }, OWNER), 'RESTAURANT_NOT_FOUND');
    await expectCode(call('getMyShopLink', { restaurantId: '../x' }, OWNER), 'RESTAURANT_NOT_FOUND');
    await expectCode(call('getMyShopLink', { restaurantId: R2 }, OWNER), 'RESTAURANT_NOT_APPROVED');
    assert.strictEqual((await rRef(R2).get()).data().publicId, undefined);
  });

  await check('L3 resolveShopLink: restoran -> {kind, restaurantId}, ownerPhone YO\'Q (eski ilova «mavjud emas» ko\'rsatadi); do\'kon javobi o\'zgarmagan', async () => {
    assert.deepStrictEqual(await call('resolveShopLink', { publicId: rid1 }), { ok: true, available: true, kind: 'restaurant', restaurantId: R1 });
    await db.collection('tv_shops').doc(OWNER).set({ name: 'Do\'kon', ownerPhone: OWNER });
    const shop = await call('getMyShopLink', {}, OWNER);
    assert.notStrictEqual(shop.publicId, rid1);
    assert.deepStrictEqual(await call('resolveShopLink', { publicId: shop.publicId }), { ok: true, available: true, ownerPhone: OWNER, businessId: '' });
  });

  await check('L4 /s/<id>: nom (ekranlangan), turi, sotuvdagi taomlar sort bo\'yicha; telefon/manzil YO\'Q; manba qr/link; OG rasm — muqova', async () => {
    const p = await renderPage(`/s/${rid1}`);
    assert.strictEqual(p.status, 200);
    assert.ok(p.body.includes('Gurlan &lt;Osh&gt; markazi'), 'nom ekranlangan');
    assert.ok(p.body.includes('Кафе-ресторан') && p.body.includes('Менюни очиш') && p.body.includes('Таомлар'));
    assert.ok(p.body.indexOf('Somsa') < p.body.indexOf('>Osh<'), 'sort tartibi');
    assert.ok(!p.body.includes('Manti'), 'sotuvda yo\'q taom ko\'rinmaydi');
    assert.ok(!p.body.includes('Chuchvara'), 'stop-list (stopUntil kelajakda) taomi ko\'rinmaydi');
    assert.ok(p.body.includes('Lagmon'), 'stop muddati o\'tgan taom yana ko\'rinadi');
    assert.ok(!p.body.includes('915100001') && !p.body.includes('Mustaqillik'), 'telefon va manzil yo\'q');
    assert.ok(p.body.includes('og:image" content="https://x/cover.jpg'));
    assert.ok(p.body.includes(`?shop=${rid1}&amp;src=link`));
    assert.ok((await renderPage(`/s/${rid1}?src=qr`)).body.includes(`?shop=${rid1}&amp;src=qr`));
    assert.ok((await renderPage(`/s/${rid1}`, 'ru')).body.includes('Открыть меню'));
    // Deferred deep link: Play + referrer (restoran ham o'sha publicId — ilova resolveShopLink orqali restoranni ochadi).
    const PLAY = 'https://play.google.com/store/apps/details?id=uz.ava.gurlan';
    assert.ok(p.body.includes(`<a class="alt" href="${PLAY}&amp;referrer=ava_shop%3D${rid1}%26src%3Dlink">📲 AVA иловасида очиш</a>`), 'referrer: havola');
    assert.ok((await renderPage(`/s/${rid1}?src=qr`)).body.includes(`href="${PLAY}&amp;referrer=ava_shop%3D${rid1}%26src%3Dqr"`), 'referrer: QR');
    assert.ok(!/referrer=[^"]*(915100|rAppr1)/.test(p.body), 'referrer\'da telefon/ichki ID yo\'q');
  });

  await check('L5 to\'xtatilgan/yopilgan restoran: havola ochilmaydi (noindex «topilmadi»), yangi havola berilmaydi; qayta tasdiqlansa — o\'sha havola ishlaydi', async () => {
    for (const st of ['suspended', 'closed']) {
      await rRef(R1).update({ status: st });
      assert.deepStrictEqual(await call('resolveShopLink', { publicId: rid1 }), { ok: true, available: false }, st);
      const p = await renderPage(`/s/${rid1}`);
      assert.ok(p.body.includes('noindex') && !p.body.includes('Gurlan'), st);
      assert.ok(!p.body.includes('referrer='), `${st}: topilmadi sahifasida referrer yo'q`);
      await expectCode(call('getMyShopLink', { restaurantId: R1 }, OWNER), 'RESTAURANT_NOT_APPROVED');
    }
    await rRef(R1).update({ status: 'approved' });
    assert.strictEqual((await call('resolveShopLink', { publicId: rid1 })).available, true);
    assert.strictEqual((await call('getMyShopLink', { restaurantId: R1 }, OWNER)).publicId, rid1, 'havola o\'zgarmaydi');
  });

  await check('L6 parallel 5 chaqiruv — bitta havola (tranzaksiya, 22-band)', async () => {
    await rRef(RHOME).update({ publicId: admin.firestore.FieldValue.delete() });
    const out = await Promise.all([1, 2, 3, 4, 5].map(() => call('getMyShopLink', { restaurantId: RHOME }, STRANGER)));
    assert.strictEqual(new Set(out.map((o) => o.publicId)).size, 1);
    const p = await renderPage(`/s/${out[0].publicId}`);
    assert.ok(p.body.includes('Уй ошпази') && !p.body.includes('uy manzili'));
  });

  // ── 2. Статистика ────────────────────────────────────────────────────────
  const statsDoc = async () => (await rRef(R1).collection('view_stats').doc(stats.dayKey()).get()).data();

  await check('S1 restoran ko\'rishi: bir xaridor bir kunda 1; manba bo\'yicha; restoran ichida saqlanadi (telefon kaliti yo\'q)', async () => {
    assert.strictEqual((await rec({ kind: 'restaurant_view', restaurantId: R1, source: 'list' }, ctxAnon('v1'))).counted, true);
    assert.strictEqual((await rec({ kind: 'restaurant_view', restaurantId: R1, source: 'list' }, ctxAnon('v1'))).counted, false, 'takror');
    assert.strictEqual((await rec({ kind: 'restaurant_view', restaurantId: R1, source: 'qr' }, ctxOf(VIEWER))).counted, true);
    assert.strictEqual((await rec({ kind: 'restaurant_view', restaurantId: R1, source: 'zzz' }, ctxAnon('v2'))).counted, true, 'notanish manba -> other');
    const d = await statsDoc();
    assert.deepStrictEqual([d.restaurantViews, d.src.list, d.src.qr, d.src.other, d.restaurantSrc.list, d.restaurantId], [3, 1, 1, 1, 1, R1]);
    assert.strictEqual((await db.collection('shop_stats').get()).size, 0, 'do\'kon statistikasi tegilmagan');
  });

  await check('S2 taom ko\'rishi: faqat mavjud va sotuvdagi taom; taom bo\'yicha', async () => {
    assert.strictEqual((await rec({ kind: 'dish_view', restaurantId: R1, itemId: 'osh', source: 'restaurant' }, ctxAnon('v3'))).counted, true);
    assert.strictEqual((await rec({ kind: 'dish_view', restaurantId: R1, itemId: 'osh', source: 'restaurant' }, ctxAnon('v3'))).counted, false);
    assert.strictEqual((await rec({ kind: 'dish_view', restaurantId: R1, itemId: 'somsa', source: 'section' }, ctxAnon('v3'))).counted, true, 'boshqa taom — alohida');
    assert.strictEqual((await rec({ kind: 'dish_view', restaurantId: R1, itemId: 'stop' }, ctxAnon('v3'))).counted, false, 'sotuvda yo\'q');
    assert.strictEqual((await rec({ kind: 'dish_view', restaurantId: R1, itemId: 'yoq' }, ctxAnon('v3'))).counted, false);
    assert.strictEqual((await rec({ kind: 'dish_view', restaurantId: R1 }, ctxAnon('v3'))).counted, false, 'itemId shart');
    const d = await statsDoc();
    assert.deepStrictEqual([d.dishViews, d.items.osh, d.items.somsa, d.dishSrc.restaurant, d.dishSrc.section], [2, 1, 1, 1, 1]);
    assert.strictEqual(d.items.stop, undefined);
  });

  await check('S3 sanalmaydi: egasi va xodim (a\'zo), loginsiz, tasdiqlanmagan/yo\'q restoran, axlat ID', async () => {
    assert.strictEqual((await rec({ kind: 'restaurant_view', restaurantId: R1 }, ctxOf(OWNER))).reason, 'own');
    assert.strictEqual((await rec({ kind: 'restaurant_view', restaurantId: R1 }, ctxOf(STAFF))).reason, 'own');
    assert.strictEqual((await rec({ kind: 'restaurant_view', restaurantId: R1 }, {})).counted, false);
    assert.strictEqual((await rec({ kind: 'restaurant_view', restaurantId: R2 }, ctxAnon('v4'))).reason, 'unavailable');
    assert.strictEqual((await rec({ kind: 'restaurant_view', restaurantId: 'yoq' }, ctxAnon('v4'))).reason, 'unavailable');
    assert.strictEqual((await rec({ kind: 'restaurant_view', restaurantId: '../x' }, ctxAnon('v4'))).reason, 'id');
    assert.strictEqual((await rRef(R2).collection('view_stats').get()).size, 0);
    assert.strictEqual((await rRef('yoq').collection('view_stats').get()).size, 0, 'begona hujjat ochilmaydi');
    assert.strictEqual((await statsDoc()).restaurantViews, 3, 'o\'zgarmagan');
  });

  await check('S4 parallel bir xil ko\'rish — 1 marta sanaladi; do\'kon ko\'rishi avvalgidek ishlaydi (regressiya)', async () => {
    const out = await Promise.all([1, 2, 3, 4].map(() => rec({ kind: 'restaurant_view', restaurantId: R1, source: 'map' }, ctxAnon('v5')).catch(() => ({ counted: false }))));
    assert.strictEqual(out.filter((o) => o.counted).length, 1);
    assert.strictEqual((await statsDoc()).src.map, 1);
    await db.collection('tv_shop_items').doc('si1').set({ ownerPhone: OWNER, title: 'Non', status: 'active' });
    assert.strictEqual((await rec({ kind: 'product_view', ownerPhone: OWNER, itemId: 'si1', source: 'market' }, ctxAnon('v5'))).counted, true);
  });

  // ── 3. Қидирув ───────────────────────────────────────────────────────────
  await check('Q1 qidiruv yozuvi: tur restaurant, modul restaurants, sourceId=rid; manzil/telefon yo\'q; uy oshpazi; namuna/tasdiqlanmagan — nofaol', () => {
    const e = restaurantToSearchEntry(R1, { name: 'Gurlan osh', status: 'approved', legalType: 'llc', venueType: 'cafe', address: 'Mustaqillik 5', contactPhone: '+998915100001', logoUrl: 'https://x/l.png', cuisineTags: ['milliy'] });
    assert.deepStrictEqual([e.type, e.moduleId, e.sourceCollection, e.sourceId, e.active, e.subtitle, e.imageUrl], ['restaurant', 'restaurants', 'restaurants', R1, true, 'Кафе-ресторан', 'https://x/l.png']);
    assert.ok(!JSON.stringify(e).includes('Mustaqillik') && !JSON.stringify(e).includes('915100001'));
    assert.ok(e.keywords.includes('kafe') && e.keywords.includes('milliy'));
    assert.strictEqual(restaurantToSearchEntry('h', { name: 'Ona', status: 'approved', legalType: 'individual' }).subtitle, 'Уй ошпази');
    for (const st of ['applied', 'suspended', 'closed', 'rejected']) assert.strictEqual(restaurantToSearchEntry('x', { name: 'Kafe', status: st }).active, false, st);
    assert.strictEqual(restaurantToSearchEntry('x', { name: 'Kafe', status: 'approved', isDemo: true }).active, false, 'namuna');
    assert.strictEqual(restaurantToSearchEntry('x', { name: 'K', status: 'approved' }).active, false, 'nom 2+');
  });

  await check('Q2 trigger: approved -> search_index/restaurant_<id> faol (kirill+lotin token); suspend -> nofaol; qayta approved -> faol; o\'chirilsa — yozuv o\'chadi', async () => {
    await fireRestaurant(R1);
    let e = await idx(`restaurant_${R1}`);
    assert.deepStrictEqual([e.type, e.active, e.sourceId, e.moduleId], ['restaurant', true, R1, 'restaurants']);
    assert.ok(e.searchTokens.includes('gurlan') && e.searchTokens.includes('гурлан'), e.searchTokens.join(','));
    assert.strictEqual(e.target, undefined, 'target yozilmaydi — sourceId ochiladi');
    const before = await rRef(R1).get();
    await rRef(R1).update({ status: 'suspended' });
    await fireRestaurant(R1, before);
    assert.strictEqual((await idx(`restaurant_${R1}`)).active, false);
    await rRef(R1).update({ status: 'approved' });
    await fireRestaurant(R1);
    assert.strictEqual((await idx(`restaurant_${R1}`)).active, true);
    await rRef('tmpDel').set({ name: 'Vaqtincha', status: 'approved' });
    await fireRestaurant('tmpDel');
    assert.ok(await idx('restaurant_tmpDel'));
    const b2 = await rRef('tmpDel').get();
    await rRef('tmpDel').delete();
    await fireRestaurant('tmpDel', b2);
    assert.strictEqual(await idx('restaurant_tmpDel'), undefined);
  });

  await check('Q3 indeksga ta\'sir qilmaydigan o\'zgarish (reyting, publicId, pauza) — indeks QAYTA yozilmaydi', async () => {
    const before = await rRef(R1).get();
    await rRef(R1).update({ ratingAvg: 4.5, ratingCount: 3, pausedUntil: null, publicId: rid1 });
    const t0 = (await db.collection('search_index').doc(`restaurant_${R1}`).get()).updateTime;
    await fireRestaurant(R1, before);
    const t1 = (await db.collection('search_index').doc(`restaurant_${R1}`).get()).updateTime;
    assert.ok(t0.isEqual(t1), 'yozilmadi');
    const a = before.data();
    assert.strictEqual(restaurantSearchFingerprint(a), restaurantSearchFingerprint({ ...a, ratingAvg: 5, timeoutStreak: 2 }));
    assert.notStrictEqual(restaurantSearchFingerprint(a), restaurantSearchFingerprint({ ...a, name: 'Boshqa' }));
  });

  // ── 4. Backfill (фақат emulator) ─────────────────────────────────────────
  await check('B1 backfill: reja (yo\'q/eskirgan) -> yozish (faqat searchIndexedAt) -> trigger -> reja bo\'sh -> qaytarish', async () => {
    const tool = require('../tools/backfill_restaurant_search_index');
    await db.collection('search_index').doc(`restaurant_${RHOME}`).delete();
    const steps = await tool.plan(db);
    const ids = steps.map((s) => s.id);
    assert.ok(ids.includes(RHOME) && ids.includes(R2), ids.join(','));
    assert.ok(!ids.includes(R1), 'indeksi to\'g\'ri — tegilmaydi');
    const r2Before = (await rRef(R2).get()).data();
    await tool.applyPlan(db, admin, steps);
    const r2After = (await rRef(R2).get()).data();
    assert.ok(r2After.searchIndexedAt);
    assert.deepStrictEqual(Object.keys(r2After).sort(), [...Object.keys(r2Before), 'searchIndexedAt'].sort(), 'boshqa maydon tegilmagan');
    for (const id of ids) await fireRestaurant(id);
    assert.strictEqual((await idx(`restaurant_${RHOME}`)).active, true);
    assert.strictEqual((await idx(`restaurant_${R2}`)).active, false, 'tasdiqlanmagan — nofaol');
    assert.strictEqual((await tool.plan(db)).length, 0, 'idempotent: ikkinchi reja bo\'sh');
    await tool.rollback(db, admin, JSON.parse(JSON.stringify(steps)));
    assert.strictEqual((await rRef(R2).get()).data().searchIndexedAt, undefined);
    assert.strictEqual((await rRef(R2).get()).data().name, 'Yangi kafe');
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
