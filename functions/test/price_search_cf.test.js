/**
 * «AVA AI — Ақлли нарх қидируви» — ҲАҚИҚИЙ `functions/index.js` callable `assistantPriceSearch` (`.run()`),
 * Firestore Emulator (array-contains-any, getAll, geo_districts, module_tariffs кўрсаткичи).
 *
 *   firebase emulators:exec --only firestore --project demo-price-search "node test/price_search_cf.test.js"
 *
 * Қулфланади: босқич OFF; Plus йўқ → plus_required; чакана шу туман → маҳаллий тариф (settings/restaurant_delivery);
 * чакана бошқа вилоят → зона (фаол logistics_v{N}, tariffVersion); вазнсиз → fromPrice; улгуржи MOQ + зона;
 * Хитой йўқ; pending/хизмат йўқ; блокланган дўкон йўқ; реклама тартибга таъсир қилмайди; тариф draft → tariff_not_active;
 * туман нотўғри → location_required (ҳисоблагич қайтади); кунлик ҳисоблагич ошади.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18497';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-price-search';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* лойиҳа керак, берилган: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require('../index');
const admin = require('firebase-admin');
const zoneTariff = require('../logistics_tariff');
const { tashkentDayKey } = require('../assistant_chat');

const db = admin.firestore();
const TS = admin.firestore.Timestamp;

const BUYER = '998935000001';
const FREE = '998935000002';
const SHOP = '998935100001'; // Гурлан, ўз дўкони
const SHOP_FAR = '998935100002'; // Тошкент, ўз дўкони
const SHOP_BLOCKED = '998935100003';
const WS_SELLER = '998935200001';

const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (data, who) => fns.assistantPriceSearch.run(data, ctxOf(who));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.error(`FAIL - ${name}\n  ${e && e.stack}`);
  }
};
async function expectErr(p, code, reason) {
  try { await p; } catch (e) {
    assert.strictEqual(e.code, code, `code ${e.code} (${e.message})`);
    if (reason) assert.strictEqual((e.details || {}).reason, reason);
    return e;
  }
  assert.fail(`expected ${code}/${reason}`);
}

const TARIFF_V1 = {
  module: 'logistics', version: 1, status: 'active', currency: 'UZS', volumetricDivisor: 6000,
  zones: zoneTariff.ZONES, weightBrackets: [1000, 3000, 5000, 10000, 20000],
  prices: {
    ZONE_0: { brackets: [29000, 36000, 43000, 59000, 88000], extraPerKg: 2500 },
    ZONE_1: { brackets: [34000, 52000, 69000, 110000, 187000], extraPerKg: 6000 },
    ZONE_4: { brackets: [42000, 64000, 85000, 133000, 225000], extraPerKg: 8500 },
  },
  matrix: { symmetric: true, regions: { xorazm: { xorazm: 'ZONE_1', toshkent_shahri: 'ZONE_4' } }, districts: { gurlan: { gurlan: 'ZONE_0' } } },
  declaredValue: { feeBps: 100, maxValue: 50000000 },
};

async function seed() {
  const now = Date.now();
  const b = db.batch();
  b.set(db.doc('settings/assistant'), { priceSearchStage: 'public', priceSearchDailyLimit: 5 });
  b.set(db.doc(`users/${BUYER}`), { phone: BUYER, bonusBalance: 0, assistantPaidUntil: TS.fromMillis(now + 3600000) });
  b.set(db.doc(`users/${FREE}`), { phone: FREE, bonusBalance: 0 });
  b.set(db.doc('geo_districts/gurlan'), { regionId: 'xorazm', name: 'Гурлан' });
  b.set(db.doc('geo_districts/urganch'), { regionId: 'xorazm', name: 'Урганч' });
  b.set(db.doc('geo_districts/chilonzor'), { regionId: 'toshkent_shahri', name: 'Чилонзор' });
  b.set(db.doc('settings/restaurant_delivery'), { base: 6000, perKm: 1500, maxKm: 20, version: 2, nightStart: 23, nightEnd: 23 });
  b.set(db.doc('module_tariffs/logistics'), { activeVersion: 1 });
  b.set(db.doc('module_tariffs/logistics_v1'), TARIFF_V1);
  // Сотувчилар
  b.set(db.doc(`tv_shops/${SHOP}`), { name: 'Гурлан дўкон', areaLat: 41.85, areaLng: 60.39 });
  b.set(db.doc(`tv_shops/${SHOP}/private/pickup`), { lat: 41.844, lng: 60.392, address: 'x' });
  b.set(db.doc(`tv_shops/${SHOP_FAR}`), { name: 'Тошкент дўкон', areaLat: 41.29, areaLng: 69.2 });
  b.set(db.doc(`tv_shops/${SHOP_BLOCKED}`), { name: 'Блок', status: 'blocked', areaLat: 41.85, areaLng: 60.39 });
  b.set(db.doc(`wholesale_sellers/${WS_SELLER}`), { regionId: 'xorazm', districtId: 'gurlan', lat: 41.84, lng: 60.39, status: 'approved' });
  const item = (id, d) => b.set(db.doc(`tv_shop_items/${id}`), {
    status: 'active', kind: 'product', createdAt: TS.fromMillis(now - 1000), searchTokens: ['olma', 'олма'], ...d,
  });
  item('near', { title: 'Олма', price: 10000, ownerPhone: SHOP, ownerName: 'Гурлан дўкон', districtId: 'gurlan' });
  item('far', { title: 'Олма Тошкент', price: 5000, ownerPhone: SHOP_FAR, ownerName: 'Т', districtId: 'chilonzor', unitWeightG: 2500, boostUntil: TS.fromMillis(now + 86400000) });
  item('farNoW', { title: 'Олма ширин', price: 6000, ownerPhone: SHOP_FAR, ownerName: 'Т', districtId: 'chilonzor' });
  item('pending', { title: 'Олма', price: 100, ownerPhone: SHOP, districtId: 'gurlan', status: 'pending' });
  item('service', { title: 'Олма териш', price: 100, ownerPhone: SHOP, districtId: 'gurlan', kind: 'service' });
  item('blocked', { title: 'Олма', price: 100, ownerPhone: SHOP_BLOCKED, districtId: 'gurlan' });
  item('nok', { title: 'Нок', price: 100, ownerPhone: SHOP, districtId: 'gurlan', searchTokens: ['nok', 'нок'] });
  b.set(db.doc('wholesale_products/ws1'), {
    status: 'active', market: 'wholesale', title: 'Олма (улгуржи)', sellerId: WS_SELLER, sellerCompanyName: 'Боғ',
    priceTiers: [{ minQty: 10, price: 4000 }], unit: 'кг', unitWeightG: 1000, searchTokens: ['olma', 'олма'], districtId: 'gurlan',
  });
  b.set(db.doc('wholesale_sellers/998935200002'), { regionId: 'xorazm', districtId: 'urganch', lat: 41.55, lng: 60.63, status: 'approved' });
  b.set(db.doc('wholesale_products/ws2'), {
    status: 'active', title: 'Олма Урганч', sellerId: '998935200002', sellerCompanyName: 'У',
    priceTiers: [{ minQty: 10, price: 4500 }], unit: 'кг', unitWeightG: 1000, searchTokens: ['olma', 'олма'], districtId: 'urganch',
  });
  b.set(db.doc('wholesale_products/cn1'), {
    status: 'active', market: 'china', title: 'Olma', sellerId: WS_SELLER, priceTiers: [{ minQty: 1, price: 1 }], searchTokens: ['olma'],
  });
  await b.commit();
}

async function main() {
  await seed();
  const BUY = { query: 'олма', districtId: 'gurlan', lat: 41.86, lng: 60.40 };

  await check('Plus йўқ → plus_required (ҳисоблагич ошмайди)', async () => {
    await expectErr(call(BUY, FREE), 'permission-denied', 'plus_required');
    const u = await db.doc(`users/${FREE}/assistant_usage/${tashkentDayKey()}`).get();
    assert.strictEqual(u.exists ? (u.data().priceSearches || 0) : 0, 0);
  });

  let res;
  await check('натижа: манбалар, фильтрлар, етказиш усуллари, тартиб', async () => {
    res = await call(BUY, BUYER);
    assert.strictEqual(res.ok, true);
    assert.ok(res.requestId);
    const ids = res.offers.map((o) => o.id);
    for (const bad of ['pending', 'service', 'blocked', 'nok', 'cn1']) assert.ok(!ids.includes(bad), `${bad} кирмаслиги керак`);
    for (const good of ['near', 'far', 'farNoW', 'ws1', 'ws2']) assert.ok(ids.includes(good), `${good} бўлиши керак`);
    const by = Object.fromEntries(res.offers.map((o) => [o.id, o]));
    assert.strictEqual(by.near.delivery.method, 'local');
    assert.ok(by.near.delivery.fee > 0 && by.near.delivery.fee % 500 === 0);
    assert.strictEqual(by.near.delivery.tariffVersion, 2);
    assert.strictEqual(by.far.delivery.method, 'zone');
    assert.strictEqual(by.far.delivery.fee, 64000 + 50, 'ZONE_4 ≤3 кг + 1%');
    assert.strictEqual(by.far.delivery.tariffVersion, 1);
    assert.strictEqual(by.far.sponsored, true);
    assert.strictEqual(by.farNoW.delivery.fromPrice, true);
    assert.strictEqual(by.farNoW.totalFrom, true);
    assert.strictEqual(by.ws1.kind, 'wholesale');
    assert.strictEqual(by.ws1.moq, 10);
    assert.strictEqual(by.ws1.goodsTotal, 40000);
    assert.strictEqual(by.ws1.delivery.method, 'local', 'улгуржи шу туман — маҳаллий тариф (эга 2026-11-17)');
    assert.ok(by.ws1.delivery.fee > 0 && by.ws1.delivery.fee % 500 === 0);
    assert.strictEqual(by.ws1.delivery.tariffVersion, 2);
    assert.strictEqual(by.ws2.delivery.method, 'zone', 'улгуржи бошқа туман — зона');
    assert.strictEqual(by.ws2.delivery.fee, 110000 + 450, 'xorazm↔xorazm ZONE_1, 10 кг + 1%');
    assert.strictEqual(by.ws2.delivery.tariffVersion, 1);
    const totals = res.offers.filter((o) => o.total != null).map((o) => o.total);
    assert.deepStrictEqual(totals, [...totals].sort((a, b) => a - b), 'жами бўйича ўсиш');
    assert.strictEqual(res.zoneTariffVersion, 1);
    assert.strictEqual(JSON.stringify(res).includes('ZONE_'), false, 'мижозга зона номи йўқ');
  });

  await check('кунлик ҳисоблагич ошади; чегара → price_search_limit', async () => {
    const u = await db.doc(`users/${BUYER}/assistant_usage/${tashkentDayKey()}`).get();
    assert.strictEqual(u.data().priceSearches, 1);
    await db.doc('settings/assistant').set({ priceSearchStage: 'public', priceSearchDailyLimit: 1 });
    await expectErr(call(BUY, BUYER), 'resource-exhausted', 'price_search_limit');
    await db.doc('settings/assistant').set({ priceSearchStage: 'public', priceSearchDailyLimit: 5 });
  });

  await check('нотўғри туман → location_required, ҳисоблагич қайтарилади', async () => {
    const before = (await db.doc(`users/${BUYER}/assistant_usage/${tashkentDayKey()}`).get()).data().priceSearches;
    await expectErr(call({ ...BUY, districtId: 'nowhere' }, BUYER), 'invalid-argument', 'location_required');
    const after = (await db.doc(`users/${BUYER}/assistant_usage/${tashkentDayKey()}`).get()).data().priceSearches;
    assert.strictEqual(after, before);
  });

  await check('зона тарифи draft (фаол эмас) → зона таклифларида null + tariff_not_active; маҳаллий ишлайди', async () => {
    await db.doc('module_tariffs/logistics_v1').set({ ...TARIFF_V1, status: 'draft' });
    zoneTariff.clearCache();
    const r = await call(BUY, BUYER);
    const by = Object.fromEntries(r.offers.map((o) => [o.id, o]));
    assert.strictEqual(by.far.delivery.fee, null);
    assert.strictEqual(by.far.delivery.reason, 'tariff_not_active');
    assert.strictEqual(by.far.total, null);
    assert.ok(by.near.delivery.fee > 0, 'шу туман маҳаллий тариф билан');
    assert.strictEqual(r.zoneTariffActive, false);
    assert.strictEqual(r.offers[r.offers.length - 1].total, null, 'нархсизлар охирида');
    await db.doc('module_tariffs/logistics_v1').set(TARIFF_V1);
    zoneTariff.clearCache();
  });

  await check('харидор координатасиз → маҳаллий таклифда buyer_location_missing (нарх ўйлаб топилмайди)', async () => {
    const r = await call({ query: 'олма', districtId: 'gurlan' }, BUYER);
    const near = r.offers.find((o) => o.id === 'near');
    assert.strictEqual(near.delivery.fee, null);
    assert.strictEqual(near.delivery.reason, 'buyer_location_missing');
  });

  await check('босқич OFF → price_search_off', async () => {
    await db.doc('settings/assistant').set({});
    await expectErr(call(BUY, BUYER), 'failed-precondition', 'price_search_off');
  });

  const ok = results.every(Boolean);
  console.log(`\n${results.filter(Boolean).length} passed, ${results.filter((x) => !x).length} failed`);
  process.exit(ok ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
