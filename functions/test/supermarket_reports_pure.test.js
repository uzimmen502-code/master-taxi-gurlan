/**
 * «AVA Супермаркет» 3-босқич — тоза агрегация: харид режаси + кунлик статистика.
 *   node test/supermarket_reports_pure.test.js
 */
'use strict';
const assert = require('assert');
const R = require('../supermarket_reports');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`); }
};

const n = (c) => ({ uz_Cyrl: c, uz_Latn: c, ru: c });
const TAX = { categories: [
  { id: 'meat', order: 2, names: n('Гўшт'), groups: [{ id: 'beef', order: 1, names: n('Мол гўшти') }] },
  { id: 'veg', order: 1, names: n('Сабзавот'), groups: [{ id: 'potato', order: 1, names: n('Картошка') }, { id: 'onion', order: 2, names: n('Пиёз') }] },
] };
const line = (productId, groupId, qty, extra = {}) => ({ productId, groupId, qty, smUnit: 'piece', total: 1000, ...extra });
const order = (id, items, extra = {}) => ({ __id: id, subtype: 'supermarket', paymentStatus: 'paid', status: 'new', items, ...extra });
const PRODUCTS = {
  beef1: { name: 'Мол гўшти лаҳм', smGroupId: 'beef', smCategoryId: 'meat', smVariety: { id: 'lean', names: n('Лаҳм') }, stock: 2, unit: 'kg' },
  pot1: { name: 'Картошка', smGroupId: 'potato', smCategoryId: 'veg', smVariety: { id: 'local', names: n('Маҳаллий') }, stock: 100, unit: 'kg' },
  egg10: { name: 'Тухум 10', smGroupId: 'eggs', stock: 0, unit: 'pack' },
};

check('P1 харид: бирлик аралаш, тортилган (кг каср, actualQty), олинган қатор ва бекор/етказилган/ready буюртма чиқарилади', () => {
  const orders = [
    order('o1', [line('beef1', 'beef', 1.5, { smUnit: 'kg', weighed: true }), line('pot1', 'potato', 3, { smUnit: 'kg', weighed: true })]),
    order('o2', [line('beef1', 'beef', 1, { smUnit: 'kg', weighed: true, actualQty: 1.05 }), line('egg10', 'eggs', 2, { smUnit: 'pack' }), line('pot1', 'potato', 9, { smUnit: 'kg', removed: true })], { status: 'accepted' }),
    order('o3', [line('beef1', 'beef', 5, { smUnit: 'kg' })], { status: 'rejected' }),
    order('o4', [line('beef1', 'beef', 5, { smUnit: 'kg' })], { status: 'accepted', fulfillmentStatus: 'cancelled' }),
    order('o5', [line('beef1', 'beef', 5, { smUnit: 'kg' })], { status: 'delivered' }),
    order('o6', [line('beef1', 'beef', 5, { smUnit: 'kg' })], { status: 'ready' }),
    order('o7', [line('beef1', 'beef', 5, { smUnit: 'kg' })], { paymentStatus: 'pending' }),
    { ...order('o8', [line('beef1', 'beef', 5, { smUnit: 'kg' })]), subtype: 'aralash' },
  ];
  const a = R.aggregateProcurement(orders, PRODUCTS, TAX);
  assert.strictEqual(a.orderCount, 2);
  const beef = a.offers.find((o) => o.productId === 'beef1');
  assert.strictEqual(beef.demandQty, 2.55); // 1.5 + 1.05 (милли бутун — float хатоси йўқ)
  assert.strictEqual(beef.stock, 2);
  assert.strictEqual(beef.shortfall, 0.55);
  assert.strictEqual(beef.orderCount, 2);
  assert.strictEqual(beef.unit, 'kg');
  assert.strictEqual(beef.categoryId, 'meat');
  assert.strictEqual(beef.varietyId, 'lean');
  const pot = a.offers.find((o) => o.productId === 'pot1');
  assert.strictEqual(pot.demandQty, 3);
  assert.strictEqual(pot.shortfall, 0, 'stock > talab → 0');
  assert.strictEqual(pot.orderCount, 1, 'olingan qator buyurtma sanamaydi');
  const egg = a.offers.find((o) => o.productId === 'egg10');
  assert.strictEqual(egg.unit, 'pack');
  assert.strictEqual(egg.shortfall, 2, 'stock 0');
  assert.strictEqual(egg.categoryId, 'unknown');
  assert.deepStrictEqual(a.offers.map((o) => o.categoryId), ['veg', 'meat', 'unknown'], 'bölim tartibi');
  const cat = a.categories.find((c) => c.categoryId === 'veg');
  assert.deepStrictEqual(cat.demandQty, { kg: 3 });
  // ҳеч қандай шахсий майдон йўқ
  const json = JSON.stringify(a);
  for (const k of ['userPhone', 'address', 'userName', 'contactPhone']) assert.ok(!json.includes(k), k);
});

check('P2 харид: маҳсулот ҳужжати йўқ → stock null, shortfall = талаб; гуруҳ йиғмаси бирлик бўйича', () => {
  const orders = [order('a', [line('gone', 'onion', 2, { smUnit: 'kg' })]), order('b', [line('gone', 'onion', 0.5, { smUnit: 'kg' }), line('onion_bunch', 'onion', 3, { smUnit: 'bunch' })])];
  const a = R.aggregateProcurement(orders, { gone: null, onion_bunch: { smGroupId: 'onion', stock: 1 } }, TAX);
  const g = a.offers.find((o) => o.productId === 'gone');
  assert.strictEqual(g.stock, null); assert.strictEqual(g.shortfall, 2.5); assert.strictEqual(g.productMissing, true);
  const grp = a.groups.find((x) => x.groupId === 'onion');
  assert.deepStrictEqual(grp.demandQty, { bunch: 3, kg: 2.5 });
  assert.deepStrictEqual(grp.shortfall, { bunch: 2, kg: 2.5 });
  assert.strictEqual(grp.orderCount, 2);
  assert.strictEqual(grp.categoryId, 'veg', 'taksonomiyadan');
});

check('P3 харид: чегара — талаб == stock → 0; бўш рўйхат', () => {
  const a = R.aggregateProcurement([order('a', [line('pot1', 'potato', 100, { smUnit: 'kg' })])], PRODUCTS, TAX);
  assert.strictEqual(a.offers[0].shortfall, 0);
  const e = R.aggregateProcurement([], {}, null);
  assert.deepStrictEqual([e.orderCount, e.offers.length, e.groups.length], [0, 0, 0]);
});

check('P8 жисмоний қолдиқ: reserved = очиқ (new/accepted/ready, ҳар сана) буюртмалар; бекор/рад/етказилган/олинган/бошқа subtype кирмайди', () => {
  const open = [
    order('a', [line('beef1', 'beef', 1.5, { smUnit: 'kg' }), line('pot1', 'potato', 9, { removed: true })]),
    order('b', [line('beef1', 'beef', 1, { smUnit: 'kg', actualQty: 1.05 })], { status: 'accepted' }),
    order('c', [line('beef1', 'beef', 2, { smUnit: 'kg' })], { status: 'ready', slot: { date: '2026-12-01' } }),
    order('d', [line('beef1', 'beef', 5)], { status: 'rejected' }),
    order('e', [line('beef1', 'beef', 5)], { status: 'accepted', fulfillmentStatus: 'cancelled' }),
    order('f', [line('beef1', 'beef', 5)], { status: 'ready', fulfillmentStatus: 'completed' }),
    order('g', [line('beef1', 'beef', 5)], { status: 'delivered' }),
    { ...order('h', [line('beef1', 'beef', 5)]), subtype: 'aralash' },
  ];
  const res = R.reservedByOffer(open);
  assert.deepStrictEqual(res, { beef1: 4550 }); // 1.5 + 1.05 + 2 (милли)
  assert.deepStrictEqual(R.RESERVING_STATUSES, ['new', 'accepted', 'ready']);
});

check('P9 shortfall = max(0, талаб − (stock + reserved)) — чегаралар: тенг → 0, +0.001 → 0.001, маҳсулот йўқ → талаб', () => {
  const P = { beef1: { ...PRODUCTS.beef1, stock: 2 }, gone: null };
  const ord = (q) => [order('a', [line('beef1', 'beef', q, { smUnit: 'kg' }), line('gone', 'beef', 1, { smUnit: 'kg' })])];
  const of = (a, id) => a.offers.find((o) => o.productId === id);
  // stock 2 + reserved 3.5 = onHand 5.5
  let a = R.aggregateProcurement(ord(5.5), P, TAX, { beef1: 3500 });
  assert.deepStrictEqual([of(a, 'beef1').stock, of(a, 'beef1').reserved, of(a, 'beef1').onHand, of(a, 'beef1').shortfall], [2, 3.5, 5.5, 0]);
  a = R.aggregateProcurement(ord(5.501), P, TAX, { beef1: 3500 });
  assert.strictEqual(of(a, 'beef1').shortfall, 0.001);
  a = R.aggregateProcurement(ord(1), P, TAX, { beef1: 3500 });
  assert.strictEqual(of(a, 'beef1').shortfall, 0);
  a = R.aggregateProcurement(ord(8), P, TAX, {});
  assert.deepStrictEqual([of(a, 'beef1').onHand, of(a, 'beef1').shortfall], [2, 6], 'reserved yöq → onHand = stock');
  assert.deepStrictEqual([of(a, 'gone').stock, of(a, 'gone').onHand, of(a, 'gone').shortfall], [null, null, 1]);
  // shu кун буюртмалари ҳам банд ичида — демак талаб ўз-ўзидан қопланади (stock 0, банд = талаб)
  a = R.aggregateProcurement(ord(3), { beef1: { ...PRODUCTS.beef1, stock: 0 } }, TAX, R.reservedByOffer(ord(3)));
  assert.deepStrictEqual([of(a, 'beef1').onHand, of(a, 'beef1').shortfall], [3, 0]);
});

check('P4 кунлик: сонлар, GMV/fee фақат бекор қилинмаган, қайтим турлари, origin, avg, unique, top', () => {
  const orders = [
    order('d1', [line('beef1', 'beef', 1.2, { smUnit: 'kg', weighed: true, actualQty: 1, total: 96000, finalTotal: 80000 })], { status: 'delivered', itemsTotal: 80000, deliveryFee: 8800, userPhone: '998900000001', smOrigin: 'weekly', smRefundedTotal: 17000, smRefundByAction: { weigh: 17000 } }),
    order('d2', [line('pot1', 'potato', 3, { smUnit: 'kg', total: 15000 }), line('egg10', 'eggs', 1, { smUnit: 'pack', total: 20000, removed: true })], { status: 'accepted', fulfillmentStatus: 'completed', itemsTotal: 15000, deliveryFee: 1650, userPhone: '998900000001', smOrigin: 'quick', smRefundedTotal: 25000, smRefundByAction: { remove: 22200 } }),
    order('d3', [line('pot1', 'potato', 2, { smUnit: 'kg', total: 10000 })], { status: 'new', itemsTotal: 10000, deliveryFee: 1100, userPhone: '998900000002', smRefundByAction: { shortage_reduce: 0 } }),
    order('c1', [line('beef1', 'beef', 9, { smUnit: 'kg', total: 720000 })], { status: 'cancelled', itemsTotal: 720000, deliveryFee: 79200, userPhone: '998900000003', smOrigin: 'reorder', smRefundedTotal: 1000, smRefundByAction: { shortage_substitute: 1000 } }),
    order('x', [], { subtype: 'restaurant' }),
  ];
  const { stats: s, customers } = R.aggregateDailyStats(orders);
  assert.deepStrictEqual([s.orders, s.delivered, s.cancelled, s.open], [4, 2, 1, 1]);
  assert.strictEqual(s.gmv, 105000);
  assert.strictEqual(s.deliveryFeeRevenue, 11550);
  assert.strictEqual(s.avgBasket, 35000);
  assert.strictEqual(s.uniqueCustomers, 2);
  assert.deepStrictEqual(customers, ['998900000001', '998900000002']);
  assert.strictEqual(s.refundsTotal, 43000);
  assert.deepStrictEqual(s.refundsByType, { weigh: 17000, shortage: 1000, removed: 22200, unattributed: 2800 });
  assert.deepStrictEqual(s.byOrigin, { catalog: 0, quick: 1, weekly: 1, reorder: 1, unknown: 1 });
  assert.deepStrictEqual(s.topGroupsBySum.map((g) => [g.groupId, g.sum]), [['beef', 80000], ['potato', 25000]], 'bekor qilingan va olingan qator yoq; finalTotal');
  assert.deepStrictEqual(s.topGroupsBySum[0].qty, { kg: 1 });
  assert.deepStrictEqual(s.topGroupsBySum[1].qty, { kg: 5 });
  assert.strictEqual(s.topGroupsByQty[0].groupId, 'potato');
  assert.strictEqual(s.courierPayout, null);
  assert.strictEqual(s.netLogistics, null);
  assert.strictEqual(s.courierPayoutSource, 'UNKNOWN');
});

check('P5 кунлик: бўш кун → 0 лар, avg 0; top 20 чегараси', () => {
  const e = R.aggregateDailyStats([]).stats;
  assert.deepStrictEqual([e.orders, e.gmv, e.avgBasket, e.uniqueCustomers, e.topGroupsBySum.length], [0, 0, 0, 0, 0]);
  const many = Array.from({ length: 25 }, (_, i) => line(`p${i}`, `g${String(i).padStart(2, '0')}`, 1, { total: 1000 + i }));
  const s = R.aggregateDailyStats([order('m', many, { itemsTotal: 1, userPhone: 'u' })]).stats;
  assert.strictEqual(s.topGroupsBySum.length, 20);
  assert.strictEqual(s.topGroupsBySum[0].groupId, 'g24');
});

check('P6 summarizeDays: йиғинди, payout UNKNOWN → net null; маълум бўлса fee − payout (манфий)', () => {
  const a = R.summarizeDays([{ orders: 3, cancelled: 1, gmv: 100000, deliveryFeeRevenue: 11000, courierPayout: null, byOrigin: { weekly: 2 } }, { orders: 1, cancelled: 0, gmv: 50000, deliveryFeeRevenue: 5500, byOrigin: {} }]);
  assert.deepStrictEqual([a.orders, a.gmv, a.avgBasket, a.weeklyOrders, a.netLogistics, a.courierPayout], [4, 150000, 50000, 2, null, null]);
  const b = R.summarizeDays([{ orders: 1, cancelled: 0, gmv: 1, deliveryFeeRevenue: 5000, courierPayout: 8000 }]);
  assert.strictEqual(b.netLogistics, -3000);
});

check('P7 сана валидацияси ва оралиқ', () => {
  assert.ok(R.validDateKey('2026-11-21'));
  for (const bad of ['2026-02-30', '2026-13-01', '26-11-21', '', null, '2026-1-01']) assert.ok(!R.validDateKey(bad), String(bad));
  assert.strictEqual(R.addDays('2026-12-31', 1), '2027-01-01');
  assert.strictEqual(R.daysBetween('2026-11-01', '2027-01-31'), 91);
  assert.ok(R.procurementEligible(order('a', [])));
  assert.ok(!R.procurementEligible(order('a', [], { status: 'ready' })));
});

const passed = results.filter(Boolean).length;
console.log(`\nsupermarket_reports_pure: ${passed}/${results.length} passed`);
process.exit(passed === results.length ? 0 : 1);
