/**
 * price_search.js — соф қисм: сўров токенлари, таклиф шакли, етказиш усули (маҳаллий / зона), вазнсиз «…дан»,
 * тариф фаол эмас, зона йўқ, катта товар, тартиб (жами бўйича; реклама таъсир қилмайди), улгуржи MOQ, Хитой йўқ.
 *
 *   node functions/test/price_search_pure.test.js
 */
'use strict';
const assert = require('assert');
const ps = require('../price_search');
const zone = require('../logistics_tariff');
const local = require('../restaurant_delivery_tariff');

let passed = 0;
let failed = 0;
function check(name, fn) {
  try { fn(); passed += 1; console.log(`PASS - ${name}`); } catch (e) { failed += 1; console.error(`FAIL - ${name}\n  ${e.stack}`); }
}

// Фикстура — prod logistics_v1 шакли (2026-11-17 ўқилган қийматлардан бир қисми).
const TARIFF = {
  module: 'logistics', version: 1, status: 'active', currency: 'UZS', volumetricDivisor: 6000,
  zones: zone.ZONES, weightBrackets: [1000, 3000, 5000, 10000, 20000],
  prices: {
    ZONE_0: { brackets: [29000, 36000, 43000, 59000, 88000], extraPerKg: 2500 },
    ZONE_1: { brackets: [34000, 52000, 69000, 110000, 187000], extraPerKg: 6000 },
    ZONE_4: { brackets: [42000, 64000, 85000, 133000, 225000], extraPerKg: 8500 },
  },
  matrix: { symmetric: true, regions: { xorazm: { xorazm: 'ZONE_1', toshkent_shahri: 'ZONE_4' } }, districts: { gurlan: { gurlan: 'ZONE_0' } } },
  limits: { maxDimCm: 150, maxSumDimCm: 300 },
  declaredValue: { feeBps: 100, maxValue: 50000000 },
};
const LOCAL_DOC = { base: 6000, perKm: 1500, maxKm: 20, version: 3, nightStart: 23, nightEnd: 6 };
const DAY = new Date(Date.UTC(2026, 10, 17, 7, 0, 0)); // 12:00 Тошкент — кундузи
const NOW = DAY.getTime();
// Гурлан атрофи (xorazm регион калити: lat 41.2–42.1, lng 60–61.1)
const GURLAN_A = { lat: 41.844, lng: 60.392 };
const GURLAN_B = { lat: 41.86, lng: 60.40 };

check('parseQuery: сўзлар + лотин/кирилл вариантлари, ≤4 сўз, ≤30 токен', () => {
  const q = ps.parseQuery('Олма  sharbati olma 1 kg extra extra2');
  assert.deepStrictEqual(q.words[0], ['олма', 'olma']);
  assert.ok(q.words[1].includes('sharbati') && q.words[1].includes('шарбати'));
  assert.strictEqual(q.words.length, 4, 'такрор «olma» лотин/кирилл варианти бошқа сўз; ≤4');
  assert.ok(q.tokens.length <= 30);
  assert.deepStrictEqual(ps.parseQuery(' a ').words, [], '1 ҳарф — сўз эмас');
});

check('matchCount: токен ёки сарлавҳа қисми', () => {
  const q = ps.parseQuery('olma sharbat');
  assert.strictEqual(ps.matchCount(q.words, { title: 'Олма шарбати', searchTokens: ['олма'] }), 2);
  assert.strictEqual(ps.matchCount(q.words, { title: 'Нок', searchTokens: ['olma'] }), 1);
});

check('retailOfferFrom: фаол маҳсулот; хизмат/келишилади/нархсиз/нофаол/муддати ўтган/блок — йўқ', () => {
  const ok = ps.retailOfferFrom('i1', { title: 'Олма', price: 12000, status: 'active', ownerPhone: '998901111111', createdAt: NOW - 1000, unitWeightG: 1500 }, NOW);
  assert.strictEqual(ok.kind, 'retail');
  assert.strictEqual(ok.goodsTotal, 12000);
  assert.strictEqual(ok.unitWeightG, 1500);
  assert.strictEqual(ok.qty, 1);
  assert.strictEqual(ps.retailOfferFrom('x', { price: 1, kind: 'service' }, NOW), null);
  assert.strictEqual(ps.retailOfferFrom('x', { price: 5000, priceUnit: 'negotiable' }, NOW), null);
  assert.strictEqual(ps.retailOfferFrom('x', { price: 0 }, NOW), null);
  assert.strictEqual(ps.retailOfferFrom('x', { price: '5000' }, NOW), null, 'сатр нарх — рад');
  assert.strictEqual(ps.retailOfferFrom('x', { price: 5000, market: 'meat', status: 'pending' }, NOW), null);
  assert.strictEqual(ps.retailOfferFrom('x', { price: 5000, market: 'meat' }, NOW), null, 'бозор эълонида status аниқ active');
  assert.ok(ps.retailOfferFrom('x', { price: 5000 }, NOW), 'эски (бозорсиз) ҳужжат — status йўқ = active');
  assert.strictEqual(ps.retailOfferFrom('x', { price: 5000, expiresAt: NOW - 1 }, NOW), null);
  assert.strictEqual(ps.retailOfferFrom('x', { price: 5000, blockedByParent: true }, NOW), null);
  assert.strictEqual(ps.retailOfferFrom('x', { price: 5000, unitWeightG: 0 }, NOW).unitWeightG, null, 'вазн 0 — йўқ');
  assert.strictEqual(ps.retailOfferFrom('x', { price: 5000, boostUntil: NOW + 1000 }, NOW).sponsored, true);
});

check('wholesaleOfferFrom: Хитой йўқ; MOQ = max(minOrderQty, 1-поғона); энг арзон қадоқ', () => {
  assert.strictEqual(ps.wholesaleOfferFrom('c', { status: 'active', market: 'china', priceTiers: [{ minQty: 1, price: 10 }] }), null);
  assert.strictEqual(ps.wholesaleOfferFrom('p', { status: 'pending', priceTiers: [{ minQty: 1, price: 10 }] }), null);
  const simple = ps.wholesaleOfferFrom('w1', { status: 'active', priceTiers: [{ minQty: 10, price: 9000 }, { minQty: 50, price: 8000 }], minOrderQty: 20, unit: 'кг', unitWeightG: 1000, sellerId: '998902222222' });
  assert.strictEqual(simple.kind, 'wholesale');
  assert.strictEqual(simple.moq, 20);
  assert.strictEqual(simple.price, 9000);
  assert.strictEqual(simple.goodsTotal, 180000);
  assert.strictEqual(simple.unit, 'кг');
  const packs = ps.wholesaleOfferFrom('w2', { status: 'active', packs: [
    { id: 'a', label: 'Қути 12', priceTiers: [{ minQty: 5, price: 50000 }], unitWeightG: 6000 },
    { id: 'b', label: 'Дона', priceTiers: [{ minQty: 2, price: 5000 }], unitWeightG: 500 },
  ] });
  assert.strictEqual(packs.packLabel, 'Дона');
  assert.strictEqual(packs.goodsTotal, 10000);
  assert.strictEqual(packs.packsCount, 2);
  assert.strictEqual(packs.unitWeightG, 500);
});

check('маҳаллий (шу туман): бизнес буюртмаси тарифи — computeDeliveryFee билан АЙНАН бир хил', () => {
  const d = ps.localDelivery({ tariffDoc: LOCAL_DOC, from: GURLAN_A, to: GURLAN_B, now: DAY });
  const prices = local.resolveDeliveryPrices(LOCAL_DOC, 'xorazm');
  const dist = Math.round((local.haversineMeters(GURLAN_A.lat, GURLAN_A.lng, GURLAN_B.lat, GURLAN_B.lng) * prices.roadFactorPermille) / 1000);
  assert.strictEqual(d.fee, local.computeDeliveryFee({ distanceMeters: dist, prices, night: false }).fee);
  assert.strictEqual(d.method, 'local');
  assert.strictEqual(d.tariffVersion, 3);
  assert.strictEqual(d.fee % 500, 0, '500 га яхлит');
});

check('маҳаллий: тариф йўқ / харидор жойи йўқ / сотувчи жойи йўқ / жуда узоқ → null + сабаб', () => {
  assert.strictEqual(ps.localDelivery({ tariffDoc: {}, from: GURLAN_A, to: GURLAN_B, now: DAY }).reason, 'local_tariff_missing');
  assert.strictEqual(ps.localDelivery({ tariffDoc: LOCAL_DOC, from: GURLAN_A, to: { lat: null, lng: null }, now: DAY }).reason, 'buyer_location_missing');
  assert.strictEqual(ps.localDelivery({ tariffDoc: LOCAL_DOC, from: { lat: 0, lng: 0 }, to: GURLAN_B, now: DAY }).reason, 'seller_location_missing');
  const far = ps.localDelivery({ tariffDoc: LOCAL_DOC, from: GURLAN_A, to: { lat: 41.55, lng: 60.63 }, now: DAY });
  assert.strictEqual(far.fee, null);
  assert.strictEqual(far.reason, 'delivery_too_far');
});

check('зона: вазн бор — аниқ поғона + declaredValue ҳақи (quoteParcel билан бир хил), tariffVersion', () => {
  const offer = { kind: 'retail', qty: 1, unitWeightG: 2500, goodsTotal: 100000, dims: null };
  const d = ps.zoneDelivery({ tariff: TARIFF, origin: { regionId: 'xorazm', districtId: 'urganch' }, dest: { regionId: 'toshkent_shahri', districtId: 'chilonzor' }, offer });
  assert.strictEqual(d.fee, 64000 + 1000, 'ZONE_4 ≤3 кг + 1%');
  assert.strictEqual(d.fromPrice, false);
  assert.strictEqual(d.tariffVersion, 1);
});

check('зона: вазн йўқ → энг кичик поғона, fromPrice=true («≈ … дан»)', () => {
  const offer = { kind: 'retail', qty: 1, unitWeightG: null, goodsTotal: 10000, dims: null };
  const d = ps.zoneDelivery({ tariff: TARIFF, origin: { regionId: 'xorazm' }, dest: { regionId: 'xorazm' }, offer });
  assert.strictEqual(d.fee, 34000 + 100);
  assert.strictEqual(d.fromPrice, true);
});

check('зона: тариф фаол эмас / draft → null tariff_not_active; маршрут матрицада йўқ → zone_not_found', () => {
  const offer = { kind: 'retail', qty: 1, unitWeightG: 100, goodsTotal: 1000 };
  assert.strictEqual(ps.zoneDelivery({ tariff: null, origin: { regionId: 'xorazm' }, dest: { regionId: 'xorazm' }, offer }).reason, 'tariff_not_active');
  const draft = ps.zoneDelivery({ tariff: { ...TARIFF, status: 'draft' }, origin: { regionId: 'xorazm' }, dest: { regionId: 'xorazm' }, offer });
  assert.strictEqual(draft.fee, null);
  assert.strictEqual(draft.reason, 'tariff_not_active');
  assert.strictEqual(ps.zoneDelivery({ tariff: TARIFF, origin: { regionId: 'xorazm' }, dest: { regionId: 'andijon' }, offer }).reason, 'zone_not_found');
});

check('deliveryFor: чакана шу туман → local; чакана бошқа туман → zone; улгуржи шу туман → local, бошқа туман → zone (эга 2026-11-17); катта товар → сўров', () => {
  const buyer = { districtId: 'gurlan', regionId: 'xorazm', ...GURLAN_B };
  const seller = { districtId: 'gurlan', regionId: 'xorazm', ...GURLAN_A };
  const retail = { kind: 'retail', qty: 1, unitWeightG: 1000, goodsTotal: 5000, market: '', category: '' };
  assert.strictEqual(ps.deliveryFor({ offer: retail, seller, buyer, tariffDoc: LOCAL_DOC, tariff: TARIFF, now: DAY }).method, 'local');
  const other = ps.deliveryFor({ offer: retail, seller: { ...seller, districtId: 'urganch' }, buyer, tariffDoc: LOCAL_DOC, tariff: TARIFF, now: DAY });
  assert.strictEqual(other.method, 'zone');
  assert.strictEqual(other.fee, 34000 + 50, 'xorazm↔xorazm ZONE_1');
  const ws = { kind: 'wholesale', qty: 10, unitWeightG: 100, goodsTotal: 50000 };
  const wsd = ps.deliveryFor({ offer: ws, seller, buyer, tariffDoc: LOCAL_DOC, tariff: TARIFF, now: DAY });
  assert.strictEqual(wsd.method, 'local', 'улгуржи шу туманда — маҳаллий тариф (вазнга боғлиқ эмас)');
  assert.strictEqual(wsd.fee, ps.localDelivery({ tariffDoc: LOCAL_DOC, from: seller, to: buyer, now: DAY }).fee);
  const wso = ps.deliveryFor({ offer: ws, seller: { ...seller, districtId: 'urganch' }, buyer, tariffDoc: LOCAL_DOC, tariff: TARIFF, now: DAY });
  assert.strictEqual(wso.method, 'zone');
  assert.strictEqual(wso.fee, 34000 + 500, 'улгуржи бошқа туман: xorazm↔xorazm ZONE_1, 1 кг + 1%');
  assert.strictEqual(ps.deliveryFor({ offer: ws, seller, buyer: { ...buyer, lat: null, lng: null }, tariffDoc: LOCAL_DOC, tariff: TARIFF, now: DAY }).reason, 'buyer_location_missing');
  const fridge = ps.deliveryFor({ offer: { ...retail, market: 'appliances', category: 'fridges' }, seller, buyer, tariffDoc: LOCAL_DOC, tariff: TARIFF, now: DAY });
  assert.strictEqual(fridge.fee, null);
  assert.strictEqual(fridge.reason, 'delivery_quote_required');
  assert.strictEqual(ps.deliveryFor({ offer: retail, seller: { lat: 1, lng: 1 }, buyer, tariffDoc: LOCAL_DOC, tariff: TARIFF, now: DAY }).reason, 'seller_location_missing');
});

check('rankOffers: жами бўйича; етказишсизлар охирида; реклама тартибга таъсир қилмайди', () => {
  const a = { id: 'a', total: 50000, goodsTotal: 40000, sponsored: true };
  const b = { id: 'b', total: 30000, goodsTotal: 20000 };
  const c = { id: 'c', total: null, goodsTotal: 1000 };
  const d = { id: 'd', total: 30000, goodsTotal: 25000, matched: 2 };
  const r = ps.rankOffers([a, c, b, d]).map((x) => x.id);
  assert.deepStrictEqual(r, ['d', 'b', 'a', 'c']);
  const noAd = ps.rankOffers([{ ...a, sponsored: false }, c, b, d]).map((x) => x.id);
  assert.deepStrictEqual(noAd, r, 'sponsored байроғи тартибни ўзгартирмайди');
});

check('publicOffer: ZONE номи/координата йўқ; totalFrom вазнсиз зонада', () => {
  const o = ps.publicOffer({ id: 'x', source: 'tv_shop_items', kind: 'retail', title: 't', price: 1, qty: 1, goodsTotal: 1, delivery: { fee: 100, method: 'zone', fromPrice: true, reason: null, tariffVersion: 1, zone: 'ZONE_1' }, total: 101, lat: 1, lng: 2 });
  assert.strictEqual(o.totalFrom, true);
  assert.strictEqual(JSON.stringify(o).includes('ZONE'), false);
  assert.strictEqual(o.lat, undefined);
  assert.strictEqual(o.delivery.estimate, true);
});

console.log(`\n${passed} passed, ${failed} failed`);
if (failed) process.exit(1);
