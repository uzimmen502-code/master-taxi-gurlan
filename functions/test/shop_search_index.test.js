/**
 * Онлайн дўкон қидируви (search_index: shop_item / shop) — ҲАҚИҚИЙ `functions/index.js`, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-shop-search \
 *     "node test/shop_search_index.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-shop-search';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const { shopItemToSearchEntry, tvShopToSearchEntry, businessToSearchEntry, shopItemTokens } = require('../shop_search_index');
const { buildSearchIndexTokens, marketToLatin, marketToCyrillic } = require('../search_tokens');

const db = admin.firestore();
const OWNER = '998914100001';
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
const idx = async (id) => (await db.collection('search_index').doc(id).get()).data();
/** Триггерни ҳақиқий ҳужжат ҳолати билан чақириш (v2 `run`). */
async function fire(fn, col, id, param) {
  const after = await db.collection(col).doc(id).get();
  await fns[fn].run({ params: { [param]: id }, data: { after } });
}

async function main() {
  await clearEmulator();

  await check('P1 tokenizator ko\'chirildi, natija o\'zgarmadi: kirill+lotin, 2+ belgi', () => {
    const t = buildSearchIndexTokens('Қизил кўйлак', "Sidabilla do'koni");
    for (const w of ['қизил', 'qizil', 'кўйлак', "ko'ylak", 'sidabilla', 'сидабилла']) assert.ok(t.includes(w), w);
    assert.strictEqual(marketToLatin('ўғил'), "o'g'il");
    assert.strictEqual(marketToCyrillic("o'g'il"), 'ўғил');
  });

  await check('P2 shop_item yozuvi: target (egasi+yo\'nalish), geo, faqat faol; egasi 12 raqam bo\'lmasa — nofaol', () => {
    const e = shopItemToSearchEntry('i1', {
      ownerPhone: OWNER, ownerName: 'Sidabilla', title: 'Televizor', description: 'Samsung 43', price: 3000000,
      photoUrls: ['https://x/a.jpg'], status: 'active', districtId: 'gurlan', businessId: 'b1',
    });
    assert.deepStrictEqual([e.type, e.active, e.price, e.imageUrl, e.geo.districtId], ['shop_item', true, 3000000, 'https://x/a.jpg', 'gurlan']);
    assert.deepStrictEqual(e.target, { ownerPhone: OWNER, businessId: 'b1' });
    assert.ok(e.searchTokens.includes('samsung') && e.searchTokens.includes('televizor'));
    assert.strictEqual(shopItemToSearchEntry('i2', { ownerPhone: OWNER, title: 'X1', status: 'blocked' }).active, false);
    assert.strictEqual(shopItemToSearchEntry('i3', { ownerPhone: 'admin', title: 'X1', status: 'active' }).active, false);
  });

  await check('P3 shop yozuvlari: do\'kon nomi; bloklangan — nofaol; filial — target otaga; egasiz obyekt — nofaol', () => {
    assert.deepStrictEqual(tvShopToSearchEntry(OWNER, { name: 'Sidabilla' }).target, { ownerPhone: OWNER, businessId: '' });
    assert.strictEqual(tvShopToSearchEntry(OWNER, { name: 'Sidabilla', status: 'blocked' }).active, false);
    assert.strictEqual(tvShopToSearchEntry(OWNER, { name: 'S' }).active, false, 'nom 2+ belgi');
    const br = businessToSearchEntry('f1', { ownerId: OWNER, name: 'Kiyim (Urganch)', branchOf: 'm1', address: 'Urganch' });
    assert.deepStrictEqual([br.target.businessId, br.subtitle, br.active], ['m1', 'Urganch', true]);
    assert.strictEqual(businessToSearchEntry('a1', { ownerId: 'admin', name: 'Admin obyekt' }).active, false);
    assert.strictEqual(businessToSearchEntry('m2', { ownerId: OWNER, name: 'Blok', status: 'blocked' }).active, false);
  });

  await check('T1 trigger: mahsulot -> search_index/shop_item_<id> + mahsulotga searchTokens; takror chaqiruv qayta yozmaydi', async () => {
    const ref = db.collection('tv_shop_items').doc('it1');
    await ref.set({ ownerPhone: OWNER, ownerName: 'Sidabilla', title: 'Qizil ko\'ylak', description: 'paxta', price: 90000, photoUrls: [], status: 'active' });
    await fire('onSearchIndexShopItemWrite', 'tv_shop_items', 'it1', 'id');
    const e = await idx('shop_item_it1');
    assert.deepStrictEqual([e.type, e.active, e.target.ownerPhone, e.moduleId], ['shop_item', true, OWNER, 'cheap_products_home']);
    const item = (await ref.get()).data();
    assert.deepStrictEqual(item.searchTokens, shopItemTokens(item));
    assert.ok(item.searchTokens.includes('қизил'), 'kirill ham');
    const before = (await ref.get()).updateTime;
    await fire('onSearchIndexShopItemWrite', 'tv_shop_items', 'it1', 'id');
    assert.strictEqual((await ref.get()).updateTime.isEqual(before), true, 'tokenlar bir xil — mahsulot qayta yozilmaydi (cheksiz trigger yo\'q)');
  });

  await check('T2 mijoz «begona» token yozsa — trigger tuzatadi; bloklansa nofaol; o\'chirilsa yozuv o\'chadi', async () => {
    const ref = db.collection('tv_shop_items').doc('it1');
    await ref.update({ searchTokens: ['iphone', 'arzon'] });
    await fire('onSearchIndexShopItemWrite', 'tv_shop_items', 'it1', 'id');
    assert.ok(!(await ref.get()).data().searchTokens.includes('iphone'));
    await ref.update({ status: 'blocked' });
    await fire('onSearchIndexShopItemWrite', 'tv_shop_items', 'it1', 'id');
    assert.strictEqual((await idx('shop_item_it1')).active, false);
    await ref.delete();
    await fire('onSearchIndexShopItemWrite', 'tv_shop_items', 'it1', 'id');
    assert.strictEqual(await idx('shop_item_it1'), undefined);
  });

  await check('T3 trigger: tv_shops va businesses -> shop_<id>; nom o\'zgarsa yangilanadi; filial target otaga', async () => {
    await db.collection('tv_shops').doc(OWNER).set({ name: 'Sidabilla', ownerPhone: OWNER });
    await fire('onSearchIndexTvShopWrite', 'tv_shops', OWNER, 'phone');
    assert.deepStrictEqual([(await idx(`shop_${OWNER}`)).title, (await idx(`shop_${OWNER}`)).active], ['Sidabilla', true]);
    await db.collection('tv_shops').doc(OWNER).update({ name: 'Sidabilla Market' });
    await fire('onSearchIndexTvShopWrite', 'tv_shops', OWNER, 'phone');
    const e = await idx(`shop_${OWNER}`);
    assert.strictEqual(e.title, 'Sidabilla Market');
    assert.ok(e.searchTokens.includes('market') && e.searchTokens.includes('маркет'));
    await db.collection('businesses').doc('f1').set({ ownerId: OWNER, name: 'Kiyim (Urganch)', branchOf: 'm1', status: 'active' });
    await fire('onSearchIndexBusinessWrite', 'businesses', 'f1', 'id');
    assert.strictEqual((await idx('shop_f1')).target.businessId, 'm1');
    await db.collection('businesses').doc('f1').delete();
    await fire('onSearchIndexBusinessWrite', 'businesses', 'f1', 'id');
    assert.strictEqual(await idx('shop_f1'), undefined);
  });

  await check('B1 backfill vositasi: reja -> yozish (keyingi reja bo\'sh) -> qaytarish (avvalgi holat)', async () => {
    const tool = require('../tools/backfill_shop_search_index');
    await db.collection('tv_shop_items').doc('old1').set({ ownerPhone: OWNER, title: 'Eski non', status: 'active' });
    await db.collection('tv_shop_items').doc('ok1').set({ ownerPhone: OWNER, title: 'Tayyor', status: 'active', searchTokens: shopItemTokens({ title: 'Tayyor' }) });
    const steps = await tool.plan(db);
    const ids = steps.map((s) => `${s.col}/${s.id}`);
    assert.ok(ids.includes('tv_shop_items/old1'));
    assert.ok(!ids.includes('tv_shop_items/ok1'), 'tokeni to\'g\'ri — tegilmaydi');
    assert.ok(ids.includes(`tv_shops/${OWNER}`));
    await tool.applyPlan(db, admin, steps);
    assert.deepStrictEqual((await db.collection('tv_shop_items').doc('old1').get()).data().searchTokens, shopItemTokens({ title: 'Eski non' }));
    assert.ok((await db.collection('tv_shops').doc(OWNER).get()).data().searchIndexedAt);
    assert.strictEqual((await tool.plan(db)).filter((s) => s.col === 'tv_shop_items').length, 0);
    await tool.rollback(db, admin, JSON.parse(JSON.stringify(steps)));
    assert.strictEqual((await db.collection('tv_shop_items').doc('old1').get()).data().searchTokens, undefined);
    assert.strictEqual((await db.collection('tv_shops').doc(OWNER).get()).data().searchIndexedAt, undefined);
    assert.strictEqual((await db.collection('tv_shops').doc(OWNER).get()).data().name, 'Sidabilla Market', 'boshqa maydon tegilmagan');
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
