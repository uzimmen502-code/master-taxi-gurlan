/**
 * Ulgurji buyurtma zanjiri, 2-bosqich — demand codebase (2026-10-31):
 * `quoteWholesaleOrder`, `rejectWholesaleOrder`, `cancelWholesaleOrder`,
 * `setWholesaleOrderSettings`, holatlar jadvali, narx pog'onasi pariteti.
 *
 *   node functions_demand/test/wholesale_orders.test.js
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const tariffCore = require('../core/tariff');
const config = require('../core/config');
const WO = require('../core/wholesale_orders');
const api = require('../api/wholesale_orders');
// Paritet: default codebase'dagi YAGONA narx qoidasi (platform_pricing.js).
const platformPricing = require('../../functions/platform_pricing');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const BUYER = '998901110001';
const TESTER = '998902220002';
const SELLER = '998901234567';
const SELLER2 = '998903330003';
const ADMIN = '998909990000';
const SUPER = '998906660000';
const DISP = '998908880000';
const NOW = new Date('2026-10-31T12:00:00.000Z');
const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });

const TARIFF = {
  module: 'logistics',
  version: 3,
  status: 'active',
  currency: 'UZS',
  volumetricDivisor: 6000,
  zones: tariffCore.ZONES,
  matrix: { regions: { xorazm: { xorazm: 'ZONE_1', toshkent_shahri: 'ZONE_4' } } },
  weightBrackets: [1000, 5000, 20000],
  prices: {
    ZONE_1: { brackets: [10000, 15000, 25000], extraPerKg: null },
    ZONE_4: { brackets: [30000, 40000, 60000], extraPerKg: 2000 },
  },
  declaredValue: { feeBps: 0, maxValue: 50000000 },
  limits: {},
  internal: { platformMarginBps: 2000, legShareBps: { first_mile: 3000, line_haul: 4000, last_mile: 3000 } },
};

const RICE = {
  sellerId: SELLER,
  title: 'Гуруч',
  status: 'active',
  market: 'wholesale',
  priceTiers: [{ minQty: 1, price: 15000 }],
  packs: [
    {
      id: 'p1',
      label: '1 кг',
      priceTiers: [{ minQty: 1, price: 15000 }, { minQty: 10, price: 14000 }, { minQty: 50, price: 13000 }],
      unitWeightG: 1000,
      unitDims: { l: 60, w: 40, h: 30 },
    },
    { id: 'p2', label: '25 кг', priceTiers: [{ minQty: 5, price: 320000 }], unitWeightG: 25000 },
    { id: 'p3', label: 'Vaznsiz', priceTiers: [{ minQty: 1, price: 5000 }] },
  ],
};
const FLOUR = {
  sellerId: SELLER, title: 'Ун', status: 'active', priceTiers: [{ minQty: 1, price: 9000 }], unitWeightG: 2000,
};
const GOLD = {
  sellerId: SELLER,
  title: 'Qimmat',
  status: 'active',
  market: 'wholesale',
  packs: [{ id: 'p1', label: 'dona', priceTiers: [{ minQty: 1, price: 1000000000 }], unitWeightG: 1 }],
};
const DEST = { regionId: 'toshkent_shahri', districtId: 'chilonzor', addressText: 'Chilonzor 5-kvartal' };

function makeDb(seed = {}) {
  tariffCore.clearCache();
  config.clearCache();
  const db = new FakeFirestore({
    'geo_regions/xorazm': { name: 'Xorazm' },
    'geo_regions/toshkent_shahri': { name: 'Toshkent' },
    'geo_regions/samarqand': { name: 'Samarqand' },
    'geo_districts/gurlan': { regionId: 'xorazm' },
    'geo_districts/chilonzor': { regionId: 'toshkent_shahri' },
    'module_tariffs/logistics': { activeVersion: 3 },
    'module_tariffs/logistics_v3': TARIFF,
    'module_config/wholesale_orders_all': { enabled: true, stage: 'internal', testerIds: [BUYER, TESTER] },
    [`wholesale_sellers/${SELLER}`]: { phone: SELLER, regionId: 'xorazm', districtId: 'gurlan', address: 'Markaz 1' },
    [`wholesale_sellers/${SELLER2}`]: { phone: SELLER2 },
    'wholesale_products/rice': RICE,
    'wholesale_products/flour': FLOUR,
    'wholesale_products/gold': GOLD,
    'wholesale_products/china': { ...FLOUR, market: 'china' },
    'wholesale_products/usd': { ...FLOUR, currency: '$' },
    'wholesale_products/pending': { ...FLOUR, status: 'pending' },
    'wholesale_products/noloc': { ...FLOUR, sellerId: SELLER2 },
    'wholesale_stock/rice': { packs: { p1: 100, p2: 50, p3: 10 }, version: 1 },
    'wholesale_stock/flour': { packs: { default: 20 }, version: 1 },
    'wholesale_stock/gold': { packs: { p1: 1000 }, version: 1 },
    'wholesale_stock/noloc': { packs: { default: 5 }, version: 1 },
    [`users/${ADMIN}`]: { role: 'admin' },
    [`users/${SUPER}`]: { role: 'superadmin' },
    [`users/${DISP}`]: { role: 'dispatcher' },
    [`users/${BUYER}`]: { role: 'user' },
    ...seed,
  });
  db.runTransaction = async (fn) => {
    const tx = {
      get: (ref) => {
        if (tx._ops.length) throw new Error('Firestore transactions require all reads to be executed before all writes.');
        return ref.get();
      },
      set: (ref, data, opts) => { tx._ops.push(() => ref.set(data, opts)); },
      update: (ref, data) => { tx._ops.push(() => ref.update(data)); },
      _ops: [],
    };
    const out = await fn(tx);
    for (const op of tx._ops) await op();
    return out;
  };
  return db;
}

const quote = (db) => api.makeQuoteWholesaleOrder({ db, now: () => NOW });
const reject = (db) => api.makeRejectWholesaleOrder({ db, now: () => NOW });
const cancel = (db) => api.makeCancelWholesaleOrder({ db, now: () => NOW });
const settings = (db) => api.makeSetWholesaleOrderSettings({ db, now: () => NOW });
const req = (extra = {}) => ({ productId: 'rice', packId: 'p1', qty: 10, destination: DEST, ...extra });

async function rejects(promise, code, reason) {
  try {
    await promise;
  } catch (e) {
    assert.strictEqual(e.code, code, `kutilgan «${code}», keldi «${e.code}»: ${e.message}`);
    if (reason) assert.strictEqual((e.details || {}).reason, reason, `reason: ${JSON.stringify(e.details)}`);
    return e;
  }
  throw new Error(`«${code}/${reason || ''}» xatosi kutilgan edi`);
}

// Konsol log'ini testda o'chiramiz (tuzilgan log — tekshiruvi alohida emas).
const origLog = console.log;
const origErr = console.error;
const quiet = () => { console.log = () => {}; console.error = () => {}; };
const loud = () => { console.log = origLog; console.error = origErr; };

// ─── sof funksiyalar ─────────────────────────────────────────────────
ok('paritet: tierUnitPrice == platform_pricing.unitPriceForQty (1..120)', () => {
  const tiers = RICE.packs[0].priceTiers;
  const product = { priceTiers: tiers, createdAt: '2026-10-30T00:00:00Z' };
  const clean = api.cleanTiers(tiers);
  assert.deepStrictEqual(clean, platformPricing.cleanTiers(tiers));
  for (let q = 1; q <= 120; q += 1) {
    assert.strictEqual(api.tierUnitPrice(clean, q), platformPricing.unitPriceForQty(product, q, 2), `qty=${q}`);
  }
  const messy = [{ minQty: '50', price: '13000' }, { minQty: 1, price: 0 }, { minQty: 10, price: 14000.9 }, null];
  assert.deepStrictEqual(api.cleanTiers(messy), platformPricing.cleanTiers(messy));
});

ok('pog\'ona chegaralari: 9 vs 10, 49 vs 50', () => {
  const t = api.cleanTiers(RICE.packs[0].priceTiers);
  assert.strictEqual(api.tierUnitPrice(t, 9), 15000);
  assert.strictEqual(api.tierUnitPrice(t, 10), 14000);
  assert.strictEqual(api.tierUnitPrice(t, 49), 14000);
  assert.strictEqual(api.tierUnitPrice(t, 50), 13000);
  assert.strictEqual(api.tierUnitPrice([], 5), null);
});

ok('resolvePack: qadoq / eski default / noma\'lum', () => {
  const p1 = api.resolvePack(RICE, 'p1');
  assert.strictEqual(p1.label, '1 кг');
  assert.strictEqual(p1.moq, 1);
  assert.strictEqual(p1.unitWeightG, 1000);
  assert.deepStrictEqual(p1.unitDims, { l: 60, w: 40, h: 30 });
  assert.strictEqual(api.resolvePack(RICE, 'p2').moq, 5);
  assert.strictEqual(api.resolvePack(RICE, 'p3').unitWeightG, null);
  assert.strictEqual(api.resolvePack(RICE, 'p4'), null);
  assert.strictEqual(api.resolvePack(RICE, 'default'), null, 'qadoqli mahsulotda default yo\'q');
  const d = api.resolvePack(FLOUR, 'default');
  assert.strictEqual(d.unitWeightG, 2000);
  assert.deepStrictEqual(d.tiers, [{ minQty: 1, price: 9000 }]);
  assert.strictEqual(api.resolvePack(FLOUR, 'p1'), null);
});

ok('tariff.quoteParcel dimsOptional: relay standarti o\'zgarmagan, chala o\'lcham RAD', () => {
  const o = { regionId: 'xorazm' };
  const d = { regionId: 'toshkent_shahri' };
  const noDims = { actualWeightG: 2000, declaredValue: 1 };
  assert.throws(() => tariffCore.quoteParcel(TARIFF, noDims, o, d), (e) => e.details.reason === 'bad_dimensions');
  const q = tariffCore.quoteParcel(TARIFF, noDims, o, d, { dimsOptional: true });
  assert.deepStrictEqual([q.volumetricWeightG, q.chargeableWeightG, q.customerPrice], [0, 2000, 40000]);
  assert.throws(
    () => tariffCore.quoteParcel(TARIFF, { ...noDims, lengthCm: 10 }, o, d, { dimsOptional: true }),
    (e) => e.details.reason === 'bad_dimensions',
  );
  const withDims = tariffCore.quoteParcel(TARIFF, { ...noDims, lengthCm: 60, widthCm: 40, heightCm: 30 }, o, d, { dimsOptional: true });
  assert.strictEqual(withDims.chargeableWeightG, 12000);
});

ok('validDims: 1..1000 butun; aks holda null', () => {
  assert.deepStrictEqual(api.validDims({ l: 1, w: 1000, h: 5 }), { l: 1, w: 1000, h: 5 });
  assert.strictEqual(api.validDims({ l: 0, w: 1, h: 1 }), null);
  assert.strictEqual(api.validDims({ l: 1001, w: 1, h: 1 }), null);
  assert.strictEqual(api.validDims({ l: 1.5, w: 1, h: 1 }), null);
  assert.strictEqual(api.validDims(null), null);
});

ok('avaFeeOf: 0 bps → 0; yuqoriga yaxlitlash; butun', () => {
  assert.strictEqual(api.avaFeeOf(140000, 0), 0);
  assert.strictEqual(api.avaFeeOf(140000, 250), 3500);
  assert.strictEqual(api.avaFeeOf(1, 250), 1);
  assert.strictEqual(api.avaFeeOf(100000000000, 3000), 30000000000);
});

ok('parseQuoteRequest: noto\'g\'ri kirish RAD', () => {
  const bad = (d, reason) => assert.throws(() => api.parseQuoteRequest(d), (e) => e.details.reason === reason);
  bad({ ...req(), productId: '' }, 'product_required');
  bad({ ...req(), productId: 'a/b' }, 'product_required');
  bad({ ...req(), packId: 'x' }, 'pack_required');
  bad({ ...req(), qty: 0 }, 'qty_invalid');
  bad({ ...req(), qty: 2.5 }, 'qty_invalid');
  bad({ ...req(), qty: '10' }, 'qty_invalid');
  bad({ ...req(), qty: 1000001 }, 'qty_invalid');
  bad({ ...req(), destination: null }, 'destination_required');
  bad({ ...req(), destination: { regionId: 'xorazm', addressText: ' a ' } }, 'address_required');
  assert.strictEqual(api.parseQuoteRequest(req({ qty: 1000000 })).qty, 1000000);
});

ok('holatlar jadvali: ruxsat etilgan va taqiqlangan o\'tishlar (aktor bo\'yicha)', () => {
  const { STATUS: S, ACTOR: A } = WO;
  assert.ok(WO.canActorTransition(A.BUYER, S.PLACED, S.CANCELLED));
  assert.ok(WO.canActorTransition(A.SELLER, S.PLACED, S.REJECTED));
  assert.ok(WO.canActorTransition(A.SELLER, S.PLACED, S.ACCEPTED));
  assert.ok(WO.canActorTransition(A.ADMIN, S.ACCEPTED, S.CANCELLED));
  assert.ok(WO.canActorTransition(A.SYSTEM, S.ACCEPTED, S.IN_DELIVERY));
  assert.ok(WO.canActorTransition(A.SYSTEM, S.IN_DELIVERY, S.DELIVERED));
  assert.ok(!WO.canActorTransition(A.BUYER, S.ACCEPTED, S.CANCELLED), 'xaridor qabuldan keyin bekor qilmaydi');
  assert.ok(!WO.canActorTransition(A.BUYER, S.PLACED, S.REJECTED));
  assert.ok(!WO.canActorTransition(A.SELLER, S.PLACED, S.CANCELLED));
  assert.ok(!WO.canTransition(S.PLACED, S.DELIVERED), 'placed → delivered to\'g\'ridan-to\'g\'ri yo\'q');
  assert.ok(!WO.canTransition(S.CANCELLED, S.PLACED));
  assert.ok(!WO.canTransition(S.DELIVERED, S.CANCELLED));
  assert.ok(WO.isTerminal(S.REJECTED) && WO.isTerminal(S.CANCELLED) && WO.isTerminal(S.DELIVERED));
  assert.deepStrictEqual([...WO.REFUND_STATUSES], ['rejected', 'cancelled']);
  assert.throws(() => WO.assertTransition(A.SELLER, S.REJECTED, S.ACCEPTED), (e) => e.details.reason === 'invalid_transition');
});

// ─── darvoza ─────────────────────────────────────────────────────────
ok('darvoza: hujjat yo\'q / enabled=false / global kill — YOPIQ', async () => {
  quiet();
  try {
    let db = makeDb({ 'module_config/wholesale_orders_all': undefined });
    db.docs.delete('module_config/wholesale_orders_all');
    await rejects(quote(db)(req(), ctx(BUYER)), 'unavailable', 'module_disabled');
    db = makeDb({ 'module_config/wholesale_orders_all': { enabled: false, stage: 'public' } });
    await rejects(quote(db)(req(), ctx(BUYER)), 'unavailable', 'module_disabled');
    db = makeDb({ 'module_config/global': { enabled: false } });
    await rejects(quote(db)(req(), ctx(BUYER)), 'unavailable', 'module_disabled');
  } finally { loud(); }
});

ok('darvoza: internal — sinovchi o\'tadi, boshqa RAD; off — sinovchi ham RAD; public — hamma', async () => {
  quiet();
  try {
    let db = makeDb();
    const r = await quote(db)(req(), ctx(TESTER));
    assert.ok(r.quoteId);
    await rejects(quote(db)(req(), ctx('998907777777')), 'unavailable', 'module_internal_only');
    db = makeDb({ 'module_config/wholesale_orders_all': { enabled: true, stage: 'off', testerIds: [BUYER] } });
    await rejects(quote(db)(req(), ctx(BUYER)), 'unavailable', 'module_internal_only');
    db = makeDb({ 'module_config/wholesale_orders_all': { enabled: true, stage: 'public' } });
    assert.ok((await quote(db)(req(), ctx('998907777777'))).quoteId);
    // noma'lum bosqich — internal (yopiq tomonga)
    db = makeDb({ 'module_config/wholesale_orders_all': { enabled: true, stage: 'weird', testerIds: [] } });
    await rejects(quote(db)(req(), ctx(BUYER)), 'unavailable', 'module_internal_only');
    await rejects(quote(db)(req(), {}), 'unauthenticated');
  } finally { loud(); }
});

// ─── kvota: rad holatlari ────────────────────────────────────────────
ok('xaridor == sotuvchi RAD (9 xonali shakl ham)', async () => {
  quiet();
  try {
    const db = makeDb({
      'module_config/wholesale_orders_all': { enabled: true, stage: 'public' },
      'wholesale_products/own9': { ...FLOUR, sellerId: SELLER.slice(3) },
      'wholesale_stock/own9': { packs: { default: 5 } },
    });
    await rejects(quote(db)(req({ productId: 'flour', packId: 'default', qty: 1 }), ctx(SELLER)), 'failed-precondition', 'own_product');
    await rejects(quote(db)(req({ productId: 'own9', packId: 'default', qty: 1 }), ctx(SELLER)), 'failed-precondition', 'own_product');
  } finally { loud(); }
});

ok('mahsulot: yo\'q / faol emas / Xitoy / valyutali RAD', async () => {
  quiet();
  try {
    const db = makeDb();
    const d = (productId) => req({ productId, packId: 'default', qty: 1 });
    await rejects(quote(db)(d('nope'), ctx(BUYER)), 'not-found', 'product_not_found');
    await rejects(quote(db)(d('pending'), ctx(BUYER)), 'failed-precondition', 'product_unavailable');
    await rejects(quote(db)(d('china'), ctx(BUYER)), 'failed-precondition', 'foreign_market');
    await rejects(quote(db)(d('usd'), ctx(BUYER)), 'failed-precondition', 'foreign_market');
  } finally { loud(); }
});

ok('qadoq: noma\'lum (p4) va qadoqli mahsulotda default RAD', async () => {
  quiet();
  try {
    const db = makeDb();
    await rejects(quote(db)(req({ packId: 'p4' }), ctx(BUYER)), 'invalid-argument', 'pack_not_found');
    await rejects(quote(db)(req({ packId: 'default' }), ctx(BUYER)), 'invalid-argument', 'pack_not_found');
  } finally { loud(); }
});

ok('miqdor: MOQ dan kam RAD, MOQ ga teng o\'tadi (chegara)', async () => {
  quiet();
  try {
    const db = makeDb();
    const e = await rejects(quote(db)(req({ packId: 'p2', qty: 4 }), ctx(BUYER)), 'invalid-argument', 'below_moq');
    assert.strictEqual(e.details.moq, 5);
    const r = await quote(db)(req({ packId: 'p2', qty: 5 }), ctx(BUYER));
    assert.strictEqual(r.goodsTotal, 1600000);
  } finally { loud(); }
});

ok('qoldiq: kiritilmagan RAD; qoldiqdan ko\'p RAD; qoldiqqa teng o\'tadi', async () => {
  quiet();
  try {
    const db = makeDb({ 'wholesale_stock/flour': { packs: {} } });
    await rejects(quote(db)(req({ productId: 'flour', packId: 'default', qty: 1 }), ctx(BUYER)), 'failed-precondition', 'stock_unknown');
    db.docs.delete('wholesale_stock/flour');
    await rejects(quote(db)(req({ productId: 'flour', packId: 'default', qty: 1 }), ctx(BUYER)), 'failed-precondition', 'stock_unknown');
    const e = await rejects(quote(db)(req({ qty: 101 }), ctx(BUYER)), 'failed-precondition', 'insufficient_stock');
    assert.strictEqual(e.details.available, 100);
    const r = await quote(db)(req({ qty: 100 }), ctx(BUYER));
    assert.strictEqual(r.qty, 100);
    const z = makeDb({ 'wholesale_stock/rice': { packs: { p1: 0 } } });
    await rejects(quote(z)(req({ qty: 1 }), ctx(BUYER)), 'failed-precondition', 'insufficient_stock');
  } finally { loud(); }
});

ok('narx pog\'onasi kvotada: 9→15000, 10→14000, 49→14000, 50→13000', async () => {
  quiet();
  try {
    const db = makeDb();
    for (const [qty, unit] of [[9, 15000], [10, 14000], [49, 14000], [50, 13000]]) {
      const r = await quote(db)(req({ qty }), ctx(BUYER));
      assert.strictEqual(r.unitPrice, unit, `qty=${qty}`);
      assert.strictEqual(r.goodsTotal, unit * qty);
      assert.strictEqual(r.total, r.goodsTotal + r.deliveryFee);
    }
  } finally { loud(); }
});

ok('toshish himoyasi: 101 × 1 mlrd > 10^11 RAD; 100 × 1 mlrd — tarif e\'lon qiymati chegarasi', async () => {
  quiet();
  try {
    const db = makeDb();
    await rejects(quote(db)(req({ productId: 'gold', qty: 101 }), ctx(BUYER)), 'invalid-argument', 'amount_too_large');
    // Chegara: 100 × 1 mlrd = 10^11 — summa o'tadi, lekin tarifning e'lon qiymati
    // chegarasi (maxValue 50 mln) aniq kod bilan rad etadi.
    await rejects(quote(db)(req({ productId: 'gold', qty: 100 }), ctx(BUYER)), 'failed-precondition', 'over_declared_value');
    assert.strictEqual(Object.keys(db.dump('wholesale_quotes')).length, 0, 'rad etilgan kvota yozilmaydi');
  } finally { loud(); }
});

ok('vazn yo\'q — no_shipping_data; sotuvchi manzili yo\'q — seller_location_missing', async () => {
  quiet();
  try {
    const db = makeDb();
    await rejects(quote(db)(req({ packId: 'p3', qty: 1 }), ctx(BUYER)), 'failed-precondition', 'no_shipping_data');
    await rejects(quote(db)(req({ productId: 'noloc', packId: 'default', qty: 1 }), ctx(BUYER)), 'failed-precondition', 'seller_location_missing');
  } finally { loud(); }
});

ok('tarif: zona yo\'q — zone_not_found; 20 kg+ narx yo\'q — tariff_extra_price_missing; tarif faol emas', async () => {
  quiet();
  try {
    let db = makeDb();
    await rejects(quote(db)(req({ destination: { regionId: 'samarqand', addressText: 'Markaz' } }), ctx(BUYER)), 'failed-precondition', 'zone_not_found');
    await rejects(quote(db)(req({ qty: 21, destination: { regionId: 'xorazm', addressText: 'Gurlan' } }), ctx(BUYER)), 'failed-precondition', 'tariff_extra_price_missing');
    db = makeDb({ 'module_tariffs/logistics': { activeVersion: 0 } });
    await rejects(quote(db)(req(), ctx(BUYER)), 'failed-precondition', 'tariff_not_active');
    db = makeDb();
    await rejects(quote(db)(req({ destination: { regionId: 'mars', addressText: 'Markaz' } }), ctx(BUYER)), 'invalid-argument', 'geo_region_unknown');
  } finally { loud(); }
});

ok('o\'lcham faqat 1 donada: qty=1 hajmiy vazn (60 000), qty=2 haqiqiy vazn (40 000)', async () => {
  quiet();
  try {
    const db = makeDb();
    const one = await quote(db)(req({ qty: 1 }), ctx(BUYER));
    assert.strictEqual(one.deliveryFee, 60000);
    const q1 = db.dump('wholesale_quotes')[one.quoteId];
    assert.strictEqual(q1.delivery.chargeableWeightG, 12000);
    assert.deepStrictEqual(q1.delivery.dims, { l: 60, w: 40, h: 30 });
    const two = await quote(db)(req({ qty: 2 }), ctx(BUYER));
    assert.strictEqual(two.deliveryFee, 40000);
    const q2 = db.dump('wholesale_quotes')[two.quoteId];
    assert.strictEqual(q2.delivery.dims, null);
    assert.strictEqual(q2.delivery.chargeableWeightG, 2000);
  } finally { loud(); }
});

ok('kvota muhrlanadi: barcha maydonlar, muddat +15 daqiqa, used=false, butun so\'m', async () => {
  quiet();
  try {
    const db = makeDb({ 'settings/wholesale_orders': { avaFeeBps: 250, feeVersion: 3 } });
    const r = await quote(db)(req({ qty: 10 }), ctx(BUYER));
    const q = db.dump('wholesale_quotes')[r.quoteId];
    assert.strictEqual(q.buyerId, BUYER);
    assert.strictEqual(q.sellerId, SELLER);
    assert.strictEqual(q.productId, 'rice');
    assert.strictEqual(q.productTitle, 'Гуруч');
    assert.strictEqual(q.packId, 'p1');
    assert.strictEqual(q.packLabel, '1 кг');
    assert.strictEqual(q.qty, 10);
    assert.strictEqual(q.unitPrice, 14000);
    assert.strictEqual(q.goodsTotal, 140000);
    assert.strictEqual(q.deliveryFee, 60000); // 10 kg, ZONE_4 3-pog'ona
    assert.strictEqual(q.total, 200000);
    assert.strictEqual(q.currency, 'UZS');
    assert.strictEqual(q.delivery.tariffVersion, 3);
    assert.strictEqual(q.delivery.zone, 'ZONE_4');
    assert.strictEqual(q.delivery.actualWeightG, 10000);
    assert.strictEqual(q.delivery.priceSnapshot.customerPrice, 60000);
    assert.strictEqual(q.delivery.priceSnapshot.declaredValue, 140000);
    assert.strictEqual(q.avaFeeBps, 250);
    assert.strictEqual(q.feeVersion, 3);
    assert.strictEqual(q.avaFee, 3500);
    assert.strictEqual(q.sellerPayout, 136500);
    assert.strictEqual(q.stockAtQuote, 100);
    assert.strictEqual(q.origin.regionId, 'xorazm');
    assert.strictEqual(q.destination.districtId, 'chilonzor');
    assert.strictEqual(q.destination.addressText, 'Chilonzor 5-kvartal');
    assert.strictEqual(q.used, false);
    assert.strictEqual(q.createdAt.getTime(), NOW.getTime());
    assert.strictEqual(q.expiresAt.getTime() - NOW.getTime(), 15 * 60 * 1000);
    assert.strictEqual(r.expiresAtMs, q.expiresAt.getTime());
    for (const k of ['unitPrice', 'goodsTotal', 'deliveryFee', 'total', 'avaFee', 'sellerPayout']) {
      assert.ok(Number.isInteger(q[k]), `${k} butun emas`);
    }
    // Xaridorga ichki qatlam (AVA ulushi, sotuvchi puli, zona) qaytarilmaydi (14, 45-band).
    for (const k of ['avaFee', 'avaFeeBps', 'sellerPayout', 'zone', 'sellerId']) assert.ok(!(k in r), `${k} javobda`);
    // Qoldiq kvotada KAMAYMAYDI (faqat buyurtma tranzaksiyasida).
    assert.strictEqual(db.dump('wholesale_stock').rice.packs.p1, 100);
  } finally { loud(); }
});

ok('eski (qadoqsiz) mahsulot — default qadoq; sozlama yo\'q → ulush 0, versiya 0', async () => {
  quiet();
  try {
    const db = makeDb();
    const r = await quote(db)(req({ productId: 'flour', packId: 'default', qty: 3, destination: { regionId: 'xorazm', districtId: 'gurlan', addressText: 'Gurlan' } }), ctx(BUYER));
    const q = db.dump('wholesale_quotes')[r.quoteId];
    assert.strictEqual(q.goodsTotal, 27000);
    assert.strictEqual(q.deliveryFee, 25000); // 6 kg, ZONE_1 3-pog'ona
    assert.strictEqual(q.avaFeeBps, 0);
    assert.strictEqual(q.feeVersion, 0);
    assert.strictEqual(q.avaFee, 0);
    assert.strictEqual(q.packLabel, '');
  } finally { loud(); }
});

ok('noto\'g\'ri ulush sozlamasi — jimgina 0 emas, RAD', async () => {
  quiet();
  try {
    for (const bad of [{ avaFeeBps: 3001, feeVersion: 1 }, { avaFeeBps: 2.5, feeVersion: 1 }, { avaFeeBps: 10, feeVersion: -1 }]) {
      const db = makeDb({ 'settings/wholesale_orders': bad });
      await rejects(quote(db)(req(), ctx(BUYER)), 'failed-precondition', 'fee_settings_invalid');
    }
  } finally { loud(); }
});

// ─── rad / bekor ─────────────────────────────────────────────────────
const ORDER = {
  buyerId: BUYER, sellerId: SELLER, status: 'placed', historySeq: 1, refundStatus: null, total: 200000,
};

ok('sotuvchi rad etadi: placed → rejected, refundStatus=pending, history #2', async () => {
  quiet();
  try {
    const db = makeDb({ 'wholesale_orders/o1': ORDER });
    const r = await reject(db)({ orderId: 'o1', reason: 'Tugadi' }, ctx(SELLER));
    assert.strictEqual(r.status, 'rejected');
    const o = db.dump('wholesale_orders').o1;
    assert.strictEqual(o.status, 'rejected');
    assert.strictEqual(o.refundStatus, 'pending');
    assert.strictEqual(o.rejectReason, 'Tugadi');
    assert.strictEqual(o.historySeq, 2);
    const h = db.dump('wholesale_orders/o1/history');
    assert.deepStrictEqual(Object.keys(h), ['2']);
    assert.strictEqual(h['2'].from, 'placed');
    assert.strictEqual(h['2'].to, 'rejected');
    assert.strictEqual(h['2'].actor, 'seller');
    // pul/qoldiqqa demand TEGMAYDI
    assert.strictEqual(o.total, 200000);
  } finally { loud(); }
});

ok('xaridor bekor qiladi: placed → cancelled; takror — idempotent, yangi history yo\'q', async () => {
  quiet();
  try {
    const db = makeDb({ 'wholesale_orders/o1': ORDER });
    const r1 = await cancel(db)({ orderId: 'o1' }, ctx(BUYER));
    assert.strictEqual(r1.idempotent, false);
    const r2 = await cancel(db)({ orderId: 'o1' }, ctx(BUYER));
    assert.strictEqual(r2.idempotent, true);
    const o = db.dump('wholesale_orders').o1;
    assert.strictEqual(o.status, 'cancelled');
    assert.strictEqual(o.cancelledBy, 'buyer');
    assert.strictEqual(o.refundStatus, 'pending');
    assert.strictEqual(o.historySeq, 2);
    assert.strictEqual(Object.keys(db.dump('wholesale_orders/o1/history')).length, 1);
  } finally { loud(); }
});

ok('begona chaqiruvchi RAD: xaridor rad eta olmaydi, sotuvchi/boshqa bekor qila olmaydi', async () => {
  quiet();
  try {
    const db = makeDb({ 'wholesale_orders/o1': ORDER });
    await rejects(reject(db)({ orderId: 'o1' }, ctx(BUYER)), 'permission-denied', 'not_order_party');
    await rejects(cancel(db)({ orderId: 'o1' }, ctx(SELLER)), 'permission-denied', 'not_order_party');
    await rejects(cancel(db)({ orderId: 'o1' }, ctx('998907777777')), 'permission-denied', 'not_order_party');
    await rejects(cancel(db)({ orderId: 'o1' }, {}), 'unauthenticated');
    await rejects(cancel(db)({ orderId: 'nope' }, ctx(BUYER)), 'not-found', 'order_not_found');
    await rejects(cancel(db)({ orderId: '' }, ctx(BUYER)), 'invalid-argument', 'order_required');
    assert.strictEqual(db.dump('wholesale_orders').o1.status, 'placed');
  } finally { loud(); }
});

ok('taqiqlangan o\'tishlar: qabuldan keyin xaridor bekori, bekordan keyin rad', async () => {
  quiet();
  try {
    const db = makeDb({
      'wholesale_orders/acc': { ...ORDER, status: 'accepted' },
      'wholesale_orders/can': { ...ORDER, status: 'cancelled' },
      'wholesale_orders/del': { ...ORDER, status: 'delivered' },
    });
    await rejects(cancel(db)({ orderId: 'acc' }, ctx(BUYER)), 'failed-precondition', 'invalid_transition');
    await rejects(reject(db)({ orderId: 'can' }, ctx(SELLER)), 'failed-precondition', 'invalid_transition');
    await rejects(reject(db)({ orderId: 'del' }, ctx(SELLER)), 'failed-precondition', 'invalid_transition');
    await rejects(reject(db)({ orderId: 'acc' }, ctx(SELLER)), 'failed-precondition', 'invalid_transition');
    assert.strictEqual(db.dump('wholesale_orders').acc.status, 'accepted');
    assert.strictEqual(db.dump('wholesale_orders').acc.refundStatus, null);
  } finally { loud(); }
});

// ─── sozlama ─────────────────────────────────────────────────────────
ok('sozlama: faqat admin/superadmin (dispatcher va oddiy RAD)', async () => {
  quiet();
  try {
    const db = makeDb();
    await rejects(settings(db)({ avaFeeBps: 100 }, ctx(BUYER)), 'permission-denied');
    await rejects(settings(db)({ avaFeeBps: 100 }, ctx(DISP)), 'permission-denied');
    await rejects(settings(db)({ avaFeeBps: 100 }, {}), 'unauthenticated');
    assert.strictEqual(db.dump('settings').wholesale_orders, undefined);
    const r = await settings(db)({ avaFeeBps: 100 }, ctx(SUPER));
    assert.strictEqual(r.feeVersion, 1);
  } finally { loud(); }
});

ok('sozlama: chegaralar 0 va 3000 o\'tadi; 3001 / -1 / 1.5 / satr RAD', async () => {
  quiet();
  try {
    const db = makeDb();
    for (const bad of [3001, -1, 1.5, '200', null]) {
      await rejects(settings(db)({ avaFeeBps: bad }, ctx(ADMIN)), 'invalid-argument', 'ava_fee_bps_invalid');
    }
    assert.strictEqual((await settings(db)({ avaFeeBps: 3000 }, ctx(ADMIN))).avaFeeBps, 3000);
    assert.strictEqual((await settings(db)({ avaFeeBps: 0 }, ctx(ADMIN))).feeVersion, 2);
  } finally { loud(); }
});

ok('sozlama: versiya + audit; bir xil qiymat — unchanged, audit yo\'q', async () => {
  quiet();
  try {
    const db = makeDb();
    const r1 = await settings(db)({ avaFeeBps: 250, reason: 'boshlang\'ich' }, ctx(ADMIN));
    assert.deepStrictEqual([r1.unchanged, r1.feeVersion], [false, 1]);
    const r2 = await settings(db)({ avaFeeBps: 250 }, ctx(ADMIN));
    assert.deepStrictEqual([r2.unchanged, r2.feeVersion], [true, 1]);
    const r3 = await settings(db)({ avaFeeBps: 300 }, ctx(ADMIN));
    assert.strictEqual(r3.feeVersion, 2);
    const s = db.dump('settings').wholesale_orders;
    assert.deepStrictEqual([s.avaFeeBps, s.feeVersion, s.updatedBy], [300, 2, ADMIN]);
    const audit = Object.values(db.dump('admin_audit'));
    assert.strictEqual(audit.length, 2);
    assert.ok(audit.every((a) => a.kind === 'wholesale_order_fee_settings'));
    assert.ok(audit.some((a) => a.detail.prevAvaFeeBps === 250 && a.detail.avaFeeBps === 300 && a.to === '2'));
    // Yangi ulush keyingi kvotada muhrlanadi.
    const q = await quote(db)(req(), ctx(BUYER));
    const qd = db.dump('wholesale_quotes')[q.quoteId];
    assert.deepStrictEqual([qd.avaFeeBps, qd.feeVersion], [300, 2]);
  } finally { loud(); }
});

(async () => {
  for (const t of tests) {
    try {
      await t.fn();
      passed += 1;
      console.log(`  ok  ${t.name}`);
    } catch (e) {
      loud();
      // `run_all.js` muvaffaqiyatsizlikni qator boshidagi «  XATO » dan taniydi.
      console.log(`  XATO ${t.name}\n       ${e.stack || e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
