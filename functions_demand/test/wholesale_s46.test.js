/**
 * Ulgurji S6 + S4 (ega CONFIRMED 2026-11-13/14) — demand codebase, FakeFirestore:
 *
 *   node functions_demand/test/wholesale_s46.test.js
 *
 * S6 — yetkazish haqini HAMMA usulda xaridor to'laydi (karta: yangi belgi `deliveryPaidBy: 'buyer'`):
 *   - core: deliveryPaidByBuyer / isNewCard matritsasi (belgisiz eski karta — false)
 *   - getWholesaleCardPaymentInfo: yangi karta — eshikda FAQAT tovar; eski — tovar + yetkazish
 *   - «етказилмади»: yangi karta — hamyon sabablari (other yo'q) + karta to'lovi awaiting
 *   - xabarlar: rad (sotuvchiga yangi matn), qaytish haqi, yo'qolish (yetkazish haqi qaytdi / qisman), {amount}
 * S4 — sotuvchining o'z yetkazishi:
 *   - parseQuoteRequest (deliveryMethod), selfAvailability (district/region/nation chegaralari), payPlanOf
 *   - kvota: self (deliveryFee 0, tarif chaqirilmaydi, vaznsiz mahsulot), qamrovdan tashqari — rad, kvota yozilmaydi;
 *     karta/bank o'z yetkazishida (sotuvchi balansi 0 bo'lsa ham, bankHold yo'q)
 *   - start / kod / complete (xato kod, qulf chegarasi 4↔5) / refused (sabab 2↔3) / return (refund_pending, qoldiq bir marta)
 *   - relay: jo'natma ham, qaytish jo'natmasi ham OCHILMAYDI
 *   - AVA ulushi hisoboti: o'z yetkazishi karta — kiradi; kuryerli karta / o'z yetkazishi hamyon — yo'q
 *   - xabarlar ws_self_* × 3 til
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const tariffCore = require('../core/tariff');
const config = require('../core/config');
const L = require('../core/logistics');
const WO = require('../core/wholesale_orders');
const api = require('../api/wholesale_orders');
const C = require('../api/wholesale_card');
const E = require('../api/wholesale_events');
const S = require('../api/wholesale_self');
const R = require('../api/wholesale_return');
const DF = require('../api/wholesale_failed');
const F = require('../api/wholesale_fee_statement');
const N = require('../notify/wholesale_notify');
const CC = require('../core/card_crypto');
const { makeFakeKms } = require('./helpers/fake_kms');

const KMS = makeFakeKms();
const cardCrypto = CC.createCardCrypto({ fetchImpl: KMS.fetchImpl, getAccessToken: KMS.getAccessToken });

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const BUYER = '998901110001';
const SELLER = '998901234567';
const STRANGER = '998907770007';
const ADMIN = '998909990000';
const NOW = new Date('2026-11-14T07:00:00.000Z');
const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });
const CARD = '4111111111111111';

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
  packs: [{
    id: 'p1', label: '1 кг', priceTiers: [{ minQty: 1, price: 15000 }, { minQty: 10, price: 14000 }], unitWeightG: 1000,
  }],
};
// Vazni kiritilmagan mahsulot — kuryer bilan bo'lmaydi, o'z yetkazishi bilan bo'ladi.
const NOWEIGHT = { ...RICE, packs: [{ id: 'p1', label: 'quti', priceTiers: [{ minQty: 1, price: 14000 }] }] };
const DEST_TASH = { regionId: 'toshkent_shahri', districtId: 'chilonzor', addressText: 'Chilonzor 5-kvartal' };
const DEST_GURLAN = { regionId: 'xorazm', districtId: 'gurlan', addressText: 'Gurlan, Bog\'cha 5' };
const DEST_URGENCH = { regionId: 'xorazm', districtId: 'urganch', addressText: 'Urganch, Al-Xorazmiy 1' };
const G = 140000;
const AVA = 3500; // 140 000 × 250 bps

const SELF_ON = (coverage, dropoff = 'buyer_address') => ({ enabled: true, coverage, dropoff });

function makeDb(seed = {}, sellerExtra = {}) {
  tariffCore.clearCache();
  config.clearCache();
  const db = new FakeFirestore({
    'geo_regions/xorazm': { name: 'Xorazm' },
    'geo_regions/toshkent_shahri': { name: 'Toshkent' },
    'geo_districts/gurlan': { regionId: 'xorazm' },
    'geo_districts/urganch': { regionId: 'xorazm' },
    'geo_districts/chilonzor': { regionId: 'toshkent_shahri' },
    'module_tariffs/logistics': { activeVersion: 3 },
    'module_tariffs/logistics_v3': TARIFF,
    'module_config/wholesale_orders_all': { enabled: true, stage: 'public' },
    'settings/wholesale_orders': { avaFeeBps: 250, feeVersion: 3 },
    [`wholesale_sellers/${SELLER}`]: {
      phone: SELLER, companyName: 'Guruch savdo', approvalStatus: 'approved', regionId: 'xorazm', districtId: 'gurlan', address: 'Markaz 1', ...sellerExtra,
    },
    'wholesale_products/rice': RICE,
    'wholesale_products/box': { ...NOWEIGHT },
    'wholesale_stock/rice': { packs: { p1: 100 }, version: 1 },
    'wholesale_stock/box': { packs: { p1: 100 }, version: 1 },
    [`users/${ADMIN}`]: { role: 'admin' },
    [`users/${BUYER}`]: { role: 'user', fcmToken: 'tokBuyer', appLang: 'uz_Latn' },
    [`users/${SELLER}`]: { role: 'user', fcmToken: 'tokSeller' },
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
const withCard = (extra = {}) => ({
  [`wholesale_sellers/${SELLER}/private/payout`]: { cardNumber: CARD, holderName: 'ALI VALIYEV', last4: '1111', version: 1 },
  ...extra,
});

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
const origLog = console.log;
const origErr = console.error;
const origWarn = console.warn;
const quiet = () => { console.log = () => {}; console.error = () => {}; console.warn = () => {}; };
const loud = () => { console.log = origLog; console.error = origErr; console.warn = origWarn; };
async function q(fn) { quiet(); try { return await fn(); } finally { loud(); } }

const quote = (db) => api.makeQuoteWholesaleOrder({ db, now: () => NOW });
const qreq = (extra = {}) => ({ productId: 'rice', packId: 'p1', qty: 10, destination: DEST_GURLAN, ...extra });
const order = (db, id = 's1') => db.docs.get(`wholesale_orders/${id}`);

/** O'z yetkazishi buyurtmasi (default `placeWholesaleOrder` yozgan shakl). */
function selfOrder(extra = {}) {
  return {
    buyerId: BUYER, buyerWalletUid: BUYER, sellerId: SELLER, productId: 'rice', productTitle: 'Гуруч', packId: 'p1', qty: 10,
    goodsTotal: G, deliveryFee: 0, total: G, paymentMethod: 'wallet', deliveryMethod: 'self',
    selfDelivery: { status: 'pending', coverage: 'district', dropoff: 'buyer_address' },
    payment: { status: 'held', amount: G, payer: 'buyer' },
    stock: { packId: 'p1', qty: 10, decremented: true, restored: false },
    status: 'placed', historySeq: 2, sellerDecision: 'accepted', acceptedAt: NOW, shipment: null, refundStatus: null,
    ...extra,
  };
}
const CARD_SELF = {
  paymentMethod: 'card_on_delivery', payment: { status: 'none', amount: 0, payer: null }, cardPayment: { status: 'awaiting', confirmedAt: null },
};
const NEW_CARD = {
  buyerId: BUYER, sellerId: SELLER, status: 'in_delivery', paymentMethod: 'card_on_delivery', deliveryPaidBy: 'buyer',
  cardPayment: { status: 'awaiting', confirmedAt: null }, goodsTotal: G, deliveryFee: 60000, total: G + 60000,
  productTitle: 'Гуруч', qty: 10, historySeq: 3, refundStatus: null, payment: { status: 'held', amount: 60000, payer: 'buyer' },
};
const LEGACY_CARD = { ...NEW_CARD, deliveryPaidBy: undefined, payment: { status: 'held_seller', amount: 63500, payer: 'seller' } };
delete LEGACY_CARD.deliveryPaidBy;

const start = (db) => S.makeStartWholesaleSelfDelivery({ db, now: () => NOW });
const complete = (db) => S.makeCompleteWholesaleSelfDelivery({ db, now: () => NOW });
const refuse = (db) => S.makeMarkWholesaleSelfDeliveryRefused({ db, now: () => NOW });
const selfReturn = (db) => S.makeCompleteWholesaleSelfReturn({ db, now: () => NOW });
const getCode = (db) => api.makeGetWholesaleDeliveryCode({ db });

// ═══════════════════════════════════════════════════════════════════════
// CORE
// ═══════════════════════════════════════════════════════════════════════

ok('core S6: deliveryPaidByBuyer — hamyon/bank/yangi karta ha, BELGISIZ eski karta YO\'Q; isNewCard faqat karta+buyer', () => {
  assert.strictEqual(WO.deliveryPaidByBuyer({}), true);
  assert.strictEqual(WO.deliveryPaidByBuyer({ paymentMethod: 'bank_transfer' }), true);
  assert.strictEqual(WO.deliveryPaidByBuyer({ paymentMethod: 'card_on_delivery' }), false, 'eski karta — eski semantika');
  assert.strictEqual(WO.deliveryPaidByBuyer({ paymentMethod: 'card_on_delivery', deliveryPaidBy: 'buyer' }), true);
  assert.strictEqual(WO.deliveryPaidByBuyer({ paymentMethod: 'card_on_delivery', deliveryPaidBy: 'seller' }), false);
  assert.strictEqual(WO.isNewCard({ paymentMethod: 'wallet', deliveryPaidBy: 'buyer' }), false);
  assert.strictEqual(WO.isNewCard({ paymentMethod: 'card_on_delivery', deliveryPaidBy: 'buyer' }), true);
});

ok('core S4: deliveryMethodOf (yo\'q/noma\'lum = ava_courier), shipmentAllowed self — qabul qilingan bo\'lsa ham YO\'Q; feeViaStatement matritsasi', () => {
  assert.strictEqual(WO.deliveryMethodOf({}), 'ava_courier');
  assert.strictEqual(WO.deliveryMethodOf({ deliveryMethod: 'drone' }), 'ava_courier');
  assert.strictEqual(WO.deliveryMethodOf({ deliveryMethod: 'self' }), 'self');
  const accepted = { sellerDecision: 'accepted', acceptedAt: NOW };
  assert.strictEqual(WO.shipmentAllowed(accepted), true);
  assert.strictEqual(WO.shipmentAllowed({ ...accepted, deliveryMethod: 'self' }), false);
  assert.strictEqual(WO.feeViaStatement({ paymentMethod: 'bank_transfer' }), true);
  assert.strictEqual(WO.feeViaStatement({ paymentMethod: 'bank_transfer', deliveryMethod: 'self' }), true);
  assert.strictEqual(WO.feeViaStatement({ paymentMethod: 'card_on_delivery', deliveryMethod: 'self' }), true);
  assert.strictEqual(WO.feeViaStatement({ paymentMethod: 'card_on_delivery' }), false, 'kuryerli karta — ushlanma orqali');
  assert.strictEqual(WO.feeViaStatement({ paymentMethod: 'wallet', deliveryMethod: 'self' }), false, 'o\'z yetkazishi hamyon — RELEASE da');
  assert.deepStrictEqual([...WO.SELF_COVERAGES], ['district', 'region', 'nation']);
  assert.deepStrictEqual([...WO.SELF_DROPOFFS], ['district_center', 'buyer_address']);
});

ok('parseQuoteRequest: deliveryMethod yo\'q/bo\'sh = ava_courier; self; noma\'lum — RAD; bank+self + deliveryPaymentMethod — not_applicable', () => {
  assert.strictEqual(api.parseQuoteRequest(qreq()).deliveryMethod, 'ava_courier');
  assert.strictEqual(api.parseQuoteRequest(qreq({ deliveryMethod: '' })).deliveryMethod, 'ava_courier');
  assert.strictEqual(api.parseQuoteRequest(qreq({ deliveryMethod: 'self' })).deliveryMethod, 'self');
  assert.throws(() => api.parseQuoteRequest(qreq({ deliveryMethod: 'drone' })), (e) => e.details.reason === 'delivery_method_invalid');
  const b = api.parseQuoteRequest(qreq({ deliveryMethod: 'self', paymentMethod: 'bank_transfer' }));
  assert.strictEqual(b.deliveryPaymentMethod, null);
  assert.throws(() => api.parseQuoteRequest(qreq({ deliveryMethod: 'self', paymentMethod: 'bank_transfer', deliveryPaymentMethod: 'wallet' })),
    (e) => e.details.reason === 'delivery_payment_method_not_applicable');
});

ok('selfAvailability: o\'chiq/yo\'q; buzuq sozlama; district (bir tuman ✓, qo\'shni tuman ✗, tumansiz manzil ✗); region; nation', () => {
  const o = { regionId: 'xorazm', districtId: 'gurlan' };
  const s = (sd) => ({ selfDelivery: sd });
  assert.strictEqual(api.selfAvailability({}, o, o).reason, 'self_disabled');
  assert.strictEqual(api.selfAvailability(s({ ...SELF_ON('district'), enabled: false }), o, o).reason, 'self_disabled');
  assert.strictEqual(api.selfAvailability(s({ enabled: true, coverage: 'world', dropoff: 'buyer_address' }), o, o).reason, 'self_settings_invalid');
  assert.strictEqual(api.selfAvailability(s({ enabled: true, coverage: 'district', dropoff: 'home' }), o, o).reason, 'self_settings_invalid');
  assert.deepStrictEqual(api.selfAvailability(s(SELF_ON('district', 'district_center')), o, { regionId: 'xorazm', districtId: 'gurlan' }),
    { available: true, reason: null, coverage: 'district', dropoff: 'district_center' });
  assert.strictEqual(api.selfAvailability(s(SELF_ON('district')), o, { regionId: 'xorazm', districtId: 'urganch' }).reason, 'out_of_coverage');
  assert.strictEqual(api.selfAvailability(s(SELF_ON('district')), o, { regionId: 'xorazm', districtId: '' }).reason, 'out_of_coverage');
  assert.strictEqual(api.selfAvailability(s(SELF_ON('district')), { regionId: 'xorazm', districtId: '' }, { regionId: 'xorazm', districtId: '' }).reason,
    'out_of_coverage', 'sotuvchi tumani yo\'q — tuman qamrovi yopiq');
  assert.strictEqual(api.selfAvailability(s(SELF_ON('region')), o, { regionId: 'xorazm', districtId: 'urganch' }).available, true);
  assert.strictEqual(api.selfAvailability(s(SELF_ON('region')), o, { regionId: 'toshkent_shahri', districtId: 'chilonzor' }).reason, 'out_of_coverage');
  assert.strictEqual(api.selfAvailability(s(SELF_ON('nation')), o, { regionId: 'toshkent_shahri', districtId: 'chilonzor' }).available, true);
});

ok('payPlanOf: hamyon — hammasi hozir; karta — hozir yetkazish, eshikda FAQAT tovar; bank — hozir yetkazish, bank orqali tovar; o\'z yetkazishi (haq 0)', () => {
  assert.deepStrictEqual(api.payPlanOf('wallet', G, 60000), { walletNow: G + 60000, atDoorToSellerCard: 0, bankTransfer: 0 });
  assert.deepStrictEqual(api.payPlanOf('card_on_delivery', G, 60000), { walletNow: 60000, atDoorToSellerCard: G, bankTransfer: 0 });
  assert.deepStrictEqual(api.payPlanOf('bank_transfer', G, 60000), { walletNow: 60000, atDoorToSellerCard: 0, bankTransfer: G });
  assert.deepStrictEqual(api.payPlanOf('card_on_delivery', G, 0), { walletNow: 0, atDoorToSellerCard: G, bankTransfer: 0 });
});

// ═══════════════════════════════════════════════════════════════════════
// KVOTA
// ═══════════════════════════════════════════════════════════════════════

ok('kvota self (hamyon): deliveryFee 0, jami = tovar, tarif/vazn kerak emas; muhr deliveryMethod + selfDelivery, delivery null; usullar', async () => {
  const db = makeDb({}, { selfDelivery: SELF_ON('district', 'district_center') });
  const r = await q(() => quote(db)(qreq({ deliveryMethod: 'self' }), ctx(BUYER)));
  assert.deepStrictEqual([r.deliveryFee, r.total, r.goodsTotal, r.deliveryMethod], [0, G, G, 'self']);
  assert.deepStrictEqual(r.deliveryMethods, { ava_courier: true, self: true });
  assert.deepStrictEqual(r.selfDelivery, { coverage: 'district', dropoff: 'district_center' });
  assert.deepStrictEqual(r.payPlan, { walletNow: G, atDoorToSellerCard: 0, bankTransfer: 0 });
  const qd = db.dump('wholesale_quotes')[r.quoteId];
  assert.deepStrictEqual([qd.deliveryMethod, qd.deliveryFee, qd.total, qd.delivery, qd.avaFee, qd.sellerPayout],
    ['self', 0, G, null, AVA, G - AVA]);
  assert.deepStrictEqual(qd.selfDelivery, { coverage: 'district', dropoff: 'district_center' });
  assert.strictEqual(qd.deliveryPaidBy, undefined);
  assert.strictEqual(qd.destination.districtId, 'gurlan');
});

ok('kvota self: qamrovdan tashqari (tuman ✗) / o\'chiq — self_delivery_unavailable, kvota YOZILMAYDI; kuryer kvotasida self: false + sabab', async () => {
  let db = makeDb({}, { selfDelivery: SELF_ON('district') });
  const e = await q(() => rejects(quote(db)(qreq({ deliveryMethod: 'self', destination: DEST_URGENCH }), ctx(BUYER)),
    'failed-precondition', 'self_delivery_unavailable'));
  assert.strictEqual(e.details.selfUnavailableReason, 'out_of_coverage');
  assert.strictEqual(Object.keys(db.dump('wholesale_quotes')).length, 0);
  db = makeDb();
  await q(() => rejects(quote(db)(qreq({ deliveryMethod: 'self' }), ctx(BUYER)), 'failed-precondition', 'self_delivery_unavailable'));
  db = makeDb({}, { selfDelivery: SELF_ON('region') });
  const r = await q(() => quote(db)(qreq({ destination: DEST_TASH }), ctx(BUYER)));
  assert.deepStrictEqual([r.deliveryMethod, r.deliveryMethods, r.selfUnavailableReason], ['ava_courier', { ava_courier: true, self: false }, 'out_of_coverage']);
  assert.strictEqual(r.deliveryFee, 60000);
});

ok('kvota self: vaznsiz mahsulot — o\'z yetkazishi bilan bo\'ladi (ava_courier: false), kuryer bilan — no_shipping_data', async () => {
  const db = makeDb({}, { selfDelivery: SELF_ON('nation') });
  const r = await q(() => quote(db)(qreq({ productId: 'box', deliveryMethod: 'self', destination: DEST_TASH }), ctx(BUYER)));
  assert.deepStrictEqual([r.deliveryFee, r.deliveryMethods], [0, { ava_courier: false, self: true }]);
  await q(() => rejects(quote(db)(qreq({ productId: 'box', destination: DEST_TASH }), ctx(BUYER)), 'failed-precondition', 'no_shipping_data'));
});

ok('kvota self + karta: sotuvchi balansi 0 bo\'lsa ham ochiq (ushlanma 0); deliveryPaidBy/sellerFeeHold muhrda YO\'Q; eshikda tovar', async () => {
  const db = makeDb(withCard(), { selfDelivery: SELF_ON('district') });
  const r = await q(() => quote(db)(qreq({ deliveryMethod: 'self', paymentMethod: 'card_on_delivery' }), ctx(BUYER)));
  assert.deepStrictEqual([r.paymentMethods.card_on_delivery, r.payPlan.walletNow, r.payPlan.atDoorToSellerCard], [true, 0, G]);
  const qd = db.dump('wholesale_quotes')[r.quoteId];
  assert.deepStrictEqual([qd.deliveryPaidBy, qd.sellerFeeHold, qd.cardHold], [undefined, undefined, undefined]);
});

ok('kvota kuryer + karta (S6), sotuvchi balansi: AVA−1 → seller_balance; AVA ulushi = 0 (bps 0) bo\'lsa balans 0 ham ochiq', async () => {
  let db = makeDb(withCard({ [`ledger_accounts/passenger_credit:${SELLER}`]: { balance: AVA - 1 } }));
  let r = await q(() => quote(db)(qreq({ destination: DEST_TASH }), ctx(BUYER)));
  assert.deepStrictEqual([r.paymentMethods.card_on_delivery, r.cardUnavailableReason], [false, 'seller_balance']);
  db = makeDb(withCard({ 'settings/wholesale_orders': { avaFeeBps: 0, feeVersion: 4 } }));
  r = await q(() => quote(db)(qreq({ destination: DEST_TASH, paymentMethod: 'card_on_delivery' }), ctx(BUYER)));
  const qd = db.dump('wholesale_quotes')[r.quoteId];
  assert.deepStrictEqual([r.paymentMethods.card_on_delivery, qd.sellerFeeHold, qd.deliveryPaidBy], [true, 0, 'buyer']);
});

ok('kvota self + bank: yetkazish haqi 0 bo\'lsa ham ochiq; bankHold/deliveryPaymentMethod muhrda YO\'Q', async () => {
  const db = makeDb({}, { selfDelivery: SELF_ON('district') });
  const r = await q(() => quote(db)(qreq({ deliveryMethod: 'self', paymentMethod: 'bank_transfer' }), ctx(BUYER)));
  assert.deepStrictEqual([r.paymentMethods.bank_transfer, r.payPlan.bankTransfer, r.walletHold], [true, G, undefined]);
  const qd = db.dump('wholesale_quotes')[r.quoteId];
  assert.deepStrictEqual([qd.bankHold, qd.deliveryPaymentMethod], [undefined, undefined]);
  // Kuryerli bank — avvalgidek (haq musbat bo'lishi shart).
  assert.strictEqual(api.bankAvailability({ approvalStatus: 'approved' }, 0).reason, 'delivery_fee_invalid');
  assert.strictEqual(api.bankAvailability({ approvalStatus: 'approved' }, 0, { self: true }).available, true);
});

// ═══════════════════════════════════════════════════════════════════════
// S6 — karta
// ═══════════════════════════════════════════════════════════════════════

ok('getWholesaleCardPaymentInfo: yangi karta — FAQAT tovar (140 000); belgisiz eski karta — tovar + yetkazish (200 000)', async () => {
  const db = makeDb(withCard({ 'wholesale_orders/n1': NEW_CARD, 'wholesale_orders/l1': LEGACY_CARD }));
  const info = C.makeGetWholesaleCardPaymentInfo({ db, cardCrypto });
  assert.strictEqual((await q(() => info({ orderId: 'n1' }, ctx(BUYER)))).amount, G);
  assert.strictEqual((await q(() => info({ orderId: 'l1' }, ctx(BUYER)))).amount, G + 60000);
});

ok('«етказилмади» yangi karta: sabablar — hamyon ro\'yxati; stillRefusable — karta to\'lovi VA hamyon shartlari; eski karta — avvalgidek', () => {
  assert.deepStrictEqual(DF.allowedReasonsOf(NEW_CARD), [...DF.WALLET_REASONS]);
  assert.deepStrictEqual(DF.allowedReasonsOf(LEGACY_CARD), [...DF.REASONS]);
  const ship = { currentLegId: 'leg0', currentCustodian: { kind: 'provider', id: '998902220002' } };
  const df = (reasonCode) => ({ open: true, legId: 'leg0', courierId: '998902220002', reasonCode });
  assert.strictEqual(DF.stillRefusable({ ...NEW_CARD, deliveryFailed: df('customer_absent') }, ship), null);
  assert.strictEqual(DF.stillRefusable({ ...NEW_CARD, deliveryFailed: df('other') }, ship), 'reason_not_allowed_wallet');
  assert.strictEqual(DF.stillRefusable({ ...NEW_CARD, cardPayment: { status: 'receipt_submitted' }, deliveryFailed: df('customer_absent') }, ship),
    'card_payment_progressed');
  assert.strictEqual(DF.stillRefusable({ ...NEW_CARD, payment: { status: 'refunded' }, deliveryFailed: df('customer_absent') }, ship), 'wallet_payment_state');
  assert.strictEqual(DF.stillRefusable({ ...LEGACY_CARD, deliveryFailed: df('other') }, ship), null, 'eski karta — other ruxsat');
});

ok('xabarlar S6: rad → sotuvchiga ws_refused_seller_newcard (eski karta — ws_refused_seller); xaridor aybi hisob-kitobi → ws_refused_buyer_card_fee', () => {
  const keys = (b, a) => E.transitionNotifications(b, a).map((x) => `${x.to}:${x.key}`);
  const refusedNew = { ...NEW_CARD, status: 'refused', refusal: { reasonCode: 'customer_refused' } };
  assert.deepStrictEqual(keys(NEW_CARD, refusedNew), ['buyer:ws_refused_buyer_refused', 'seller:ws_refused_seller_newcard']);
  assert.deepStrictEqual(keys(LEGACY_CARD, { ...LEGACY_CARD, status: 'refused', refusal: { reasonCode: 'customer_refused' } }),
    ['buyer:ws_refused_buyer_refused', 'seller:ws_refused_seller']);
  const settled = {
    ...refusedNew, status: 'returning', refundStatus: 'done', walletRefusal: { fault: 'buyer', returnFeeCharged: 40000 },
  };
  assert.ok(keys({ ...refusedNew, status: 'returning', refundStatus: 'pending' }, settled).includes('buyer:ws_refused_buyer_card_fee'));
  // Kuryer aybi / qaytish haqi 0 — xabar yo'q.
  assert.ok(!keys({ ...refusedNew, refundStatus: 'pending' }, { ...settled, walletRefusal: { fault: 'courier', returnFeeCharged: null } })
    .includes('buyer:ws_refused_buyer_card_fee'));
  // Hamyon xabari yangi kartaga yuborilmaydi (tovar summasi yo'q).
  assert.ok(!keys({ ...refusedNew, refundStatus: 'pending' }, settled).includes('buyer:ws_refused_buyer_wallet'));
});

ok('xabarlar S6 yo\'qolish: yangi karta — yetkazish haqi qaytdi (to\'liq / qisman + admin); review — avvalgidek; eski karta — ws_lost_buyer_card', () => {
  const keys = (a) => E.transitionNotifications(NEW_CARD, a).map((x) => `${x.to}:${x.key}`);
  const lost = (l, pay = {}) => ({ ...NEW_CARD, status: 'lost', lost: l, payment: { status: 'refunded_lost', lostRefund: AVA, lostFeeRefund: 60000, ...pay } });
  assert.deepStrictEqual(keys(lost({ deliveryFeeOutstanding: 0, deliveryFeeRefunded: 60000 })), ['buyer:ws_lost_buyer_card_fee', 'seller:ws_lost_seller']);
  assert.deepStrictEqual(keys(lost({ deliveryFeeOutstanding: 20000, deliveryFeeRefunded: 40000 })),
    ['buyer:ws_lost_buyer_card_fee_partial', 'seller:ws_lost_seller', 'admins:ws_lost_fee_admin']);
  assert.ok(keys({ ...lost({}), payment: { status: 'lost_review' } }).includes('buyer:ws_lost_buyer_review'));
  assert.deepStrictEqual(E.transitionNotifications(LEGACY_CARD, { ...LEGACY_CARD, status: 'lost', payment: { status: 'refunded_lost' } })
    .map((x) => x.key), ['ws_lost_buyer_card', 'ws_lost_seller']);
  // {feeRefund} — faqat yetkazish haqi (AVA ulushi sotuvchiga qaytgan summa xaridor matniga TUSHMAYDI).
  const t = N.render('ws_lost_buyer_card_fee', 'uz_Latn', { product: 'Guruch', qty: 10, feeRefund: 60000 });
  assert.ok(t.body.includes('60000') && !t.body.includes(String(AVA)));
});

// ═══════════════════════════════════════════════════════════════════════
// S4 — o'z yetkazishi callable'lari
// ═══════════════════════════════════════════════════════════════════════

ok('start: auth; begona / xaridor — RAD; kuryerli buyurtma — not_self_delivery; qaror kutilmoqda — seller_not_accepted; bank awaiting — bank_payment_unconfirmed', async () => {
  const db = makeDb({
    'wholesale_orders/s1': selfOrder(),
    'wholesale_orders/c1': selfOrder({ deliveryMethod: 'ava_courier' }),
    'wholesale_orders/p1': selfOrder({ sellerDecision: 'pending', acceptedAt: null }),
    'wholesale_orders/b1': selfOrder({ paymentMethod: 'bank_transfer', payment: { status: 'none', amount: 0 }, bankPayment: { status: 'awaiting' } }),
  });
  await q(async () => {
    await rejects(start(db)({ orderId: 's1' }, {}), 'unauthenticated');
    await rejects(start(db)({ orderId: 's1' }, ctx(STRANGER)), 'permission-denied', 'not_order_party');
    await rejects(start(db)({ orderId: 's1' }, ctx(BUYER)), 'permission-denied', 'not_order_party');
    await rejects(start(db)({ orderId: 'c1' }, ctx(SELLER)), 'failed-precondition', 'not_self_delivery');
    await rejects(start(db)({ orderId: 'p1' }, ctx(SELLER)), 'failed-precondition', 'seller_not_accepted');
    await rejects(start(db)({ orderId: 'b1' }, ctx(SELLER)), 'failed-precondition', 'bank_payment_unconfirmed');
    await rejects(start(db)({ orderId: '../x' }, ctx(SELLER)), 'invalid-argument', 'order_required');
  });
  assert.strictEqual(order(db, 's1').status, 'placed');
  assert.ok(!db.docs.get('wholesale_orders/s1/private/self_delivery'));
});

ok('start: placed → in_delivery (seller, history), sir yaratiladi; takror — idempotent, sir O\'ZGARMAYDI; bank — «Пул тушди» dan keyin o\'tadi', async () => {
  const db = makeDb({
    'wholesale_orders/s1': selfOrder(),
    'wholesale_orders/b1': selfOrder({
      paymentMethod: 'bank_transfer', payment: { status: 'none', amount: 0 }, bankPayment: { status: 'confirmed', confirmedAt: NOW },
    }),
  });
  const r = await q(() => start(db)({ orderId: 's1' }, ctx(SELLER)));
  assert.deepStrictEqual([r.ok, r.status, r.idempotent], [true, 'in_delivery', false]);
  const o = order(db, 's1');
  assert.deepStrictEqual([o.status, o.selfDelivery.status, o.historySeq], ['in_delivery', 'in_delivery', 3]);
  const h = db.docs.get('wholesale_orders/s1/history/3');
  assert.deepStrictEqual([h.event, h.actor, h.from, h.to], ['self_delivery_started', 'seller', 'placed', 'in_delivery']);
  const secret = db.docs.get('wholesale_orders/s1/private/self_delivery').secret;
  assert.ok(/^[0-9a-f]{32}$/.test(secret));
  const r2 = await q(() => start(db)({ orderId: 's1' }, ctx(SELLER)));
  assert.strictEqual(r2.idempotent, true);
  assert.strictEqual(db.docs.get('wholesale_orders/s1/private/self_delivery').secret, secret);
  assert.strictEqual(order(db, 's1').historySeq, 3, 'ikkinchi yozuv yo\'q');
  assert.strictEqual((await q(() => start(db)({ orderId: 'b1' }, ctx(SELLER)))).status, 'in_delivery');
});

ok('kod: xaridor oladi (relay hosilasi wsself:{id}); boshlanmagan — self_delivery_not_started; sotuvchi — RAD; karta: «Пул тушди» gacha — RAD', async () => {
  const db = makeDb({
    'wholesale_orders/s1': selfOrder(),
    'wholesale_orders/k1': selfOrder({ ...CARD_SELF }),
  });
  await q(() => rejects(getCode(db)({ orderId: 's1' }, ctx(BUYER)), 'failed-precondition', 'self_delivery_not_started'));
  await q(() => start(db)({ orderId: 's1' }, ctx(SELLER)));
  const r = await q(() => getCode(db)({ orderId: 's1' }, ctx(BUYER)));
  const secret = db.docs.get('wholesale_orders/s1/private/self_delivery').secret;
  assert.deepStrictEqual([r.deliveryMethod, r.shipmentId, r.deliveryCode], ['self', null, L.deliveryCodeFor('wsself:s1', secret)]);
  assert.ok(/^\d{6}$/.test(r.deliveryCode));
  await q(() => rejects(getCode(db)({ orderId: 's1' }, ctx(SELLER)), 'permission-denied', 'not_order_party'));
  await q(() => start(db)({ orderId: 'k1' }, ctx(SELLER)));
  await q(() => rejects(getCode(db)({ orderId: 'k1' }, ctx(BUYER)), 'failed-precondition', 'card_payment_unconfirmed'));
});

ok('complete: kod formati; xato kod — delivery_code_invalid (hisoblagich SAQLANADI); 4 xato — hali ochiq, 5-chi — qulf; qulfda to\'g\'ri kod ham — code_locked', async () => {
  const db = makeDb({ 'wholesale_orders/s1': selfOrder() });
  await q(() => start(db)({ orderId: 's1' }, ctx(SELLER)));
  const secret = db.docs.get('wholesale_orders/s1/private/self_delivery').secret;
  const good = L.deliveryCodeFor('wsself:s1', secret);
  const bad = good === '000000' ? '111111' : '000000';
  await q(() => rejects(complete(db)({ orderId: 's1', code: '12345' }, ctx(SELLER)), 'invalid-argument', 'code_format'));
  for (let i = 1; i <= 4; i += 1) {
    const e = await q(() => rejects(complete(db)({ orderId: 's1', code: bad }, ctx(SELLER)), 'invalid-argument', 'delivery_code_invalid'));
    assert.strictEqual(e.details.attemptsLeft, 5 - i);
  }
  assert.strictEqual(db.docs.get('wholesale_orders/s1/private/self_delivery').fails, 4);
  assert.ok(!db.docs.get('wholesale_orders/s1/private/self_delivery').lockedUntil, '4 xato — qulf yo\'q (chegara)');
  await q(() => rejects(complete(db)({ orderId: 's1', code: bad }, ctx(SELLER)), 'invalid-argument', 'delivery_code_invalid'));
  assert.ok(db.docs.get('wholesale_orders/s1/private/self_delivery').lockedUntil, '5-xato — qulf');
  await q(() => rejects(complete(db)({ orderId: 's1', code: good }, ctx(SELLER)), 'resource-exhausted', 'code_locked'));
  assert.strictEqual(order(db, 's1').selfDelivery.status, 'in_delivery');
});

ok('complete: to\'g\'ri kod → selfDelivery completed (holat in_delivery qoladi — delivered ni default yozadi); takror — idempotent; begona — RAD', async () => {
  const db = makeDb({ 'wholesale_orders/s1': selfOrder() });
  await q(() => start(db)({ orderId: 's1' }, ctx(SELLER)));
  const code = L.deliveryCodeFor('wsself:s1', db.docs.get('wholesale_orders/s1/private/self_delivery').secret);
  await q(() => rejects(complete(db)({ orderId: 's1', code }, ctx(BUYER)), 'permission-denied', 'not_order_party'));
  const r = await q(() => complete(db)({ orderId: 's1', code }, ctx(SELLER)));
  assert.deepStrictEqual([r.ok, r.selfDeliveryStatus, r.idempotent], [true, 'completed', false]);
  const o = order(db, 's1');
  assert.deepStrictEqual([o.status, o.selfDelivery.status, !!o.selfDelivery.completedAt], ['in_delivery', 'completed', true]);
  assert.strictEqual(db.docs.get(`wholesale_orders/s1/history/${o.historySeq}`).event, 'self_delivery_completed');
  assert.strictEqual((await q(() => complete(db)({ orderId: 's1', code: '999999' }, ctx(SELLER)))).idempotent, true);
});

ok('complete (karta): «Пул тушди» gacha — card_payment_unconfirmed; tasdiqdan keyin — o\'tadi', async () => {
  const db = makeDb({ 'wholesale_orders/k1': selfOrder({ ...CARD_SELF }) });
  await q(() => start(db)({ orderId: 'k1' }, ctx(SELLER)));
  const code = L.deliveryCodeFor('wsself:k1', db.docs.get('wholesale_orders/k1/private/self_delivery').secret);
  await q(() => rejects(complete(db)({ orderId: 'k1', code }, ctx(SELLER)), 'failed-precondition', 'card_payment_unconfirmed'));
  await q(() => C.makeConfirmWholesaleCardPayment({ db, now: () => NOW })({ orderId: 'k1' }, ctx(SELLER)));
  assert.strictEqual((await q(() => complete(db)({ orderId: 'k1', code }, ctx(SELLER)))).selfDeliveryStatus, 'completed');
});

ok('refused: sabab 2 belgi — RAD, 3 — o\'tadi; boshlanmagan — RAD; → refused + refundStatus pending + refusal.via; takror idempotent; cardRefusals OSHMAYDI', async () => {
  const db = makeDb({ 'wholesale_orders/s1': selfOrder(), 'wholesale_orders/k1': selfOrder({ ...CARD_SELF }) });
  await q(() => rejects(refuse(db)({ orderId: 's1', reason: 'Yoq' }, ctx(SELLER)), 'failed-precondition', 'order_not_in_delivery'));
  await q(() => start(db)({ orderId: 's1' }, ctx(SELLER)));
  await q(() => rejects(refuse(db)({ orderId: 's1', reason: 'ab' }, ctx(SELLER)), 'invalid-argument', 'reason_invalid'));
  const r = await q(() => refuse(db)({ orderId: 's1', reason: 'abc' }, ctx(SELLER)));
  assert.deepStrictEqual([r.status, r.idempotent], ['refused', false]);
  const o = order(db, 's1');
  assert.deepStrictEqual([o.status, o.refundStatus, o.refusal.via, o.selfDelivery.status], ['refused', 'pending', 'self_delivery', 'refused']);
  assert.strictEqual((await q(() => refuse(db)({ orderId: 's1', reason: 'abc' }, ctx(SELLER)))).idempotent, true);
  assert.ok(!db.docs.get(`wholesale_buyer_stats/${BUYER}`), 'xaridor hisoblagichi yozilmaydi');
  // Karta: «Пул тушди» bosilgan — rad emas.
  await q(() => start(db)({ orderId: 'k1' }, ctx(SELLER)));
  await q(() => C.makeConfirmWholesaleCardPayment({ db, now: () => NOW })({ orderId: 'k1' }, ctx(SELLER)));
  await q(() => rejects(refuse(db)({ orderId: 'k1', reason: 'olmadi' }, ctx(SELLER)), 'failed-precondition', 'card_payment_confirmed'));
});

ok('qaytish: hisob-kitob tugamagan — refund_pending; done → returned + qoldiq +10 (history order_return); takror — qoldiq BIR MARTA', async () => {
  const db = makeDb({ 'wholesale_orders/s1': selfOrder({ status: 'refused', refundStatus: 'pending', selfDelivery: { status: 'refused' } }) });
  await q(() => rejects(selfReturn(db)({ orderId: 's1' }, ctx(SELLER)), 'failed-precondition', 'refund_pending'));
  await db.collection('wholesale_orders').doc('s1').update({ refundStatus: 'done' });
  await q(() => rejects(selfReturn(db)({ orderId: 's1' }, ctx(BUYER)), 'permission-denied', 'not_order_party'));
  const r = await q(() => selfReturn(db)({ orderId: 's1' }, ctx(SELLER)));
  assert.deepStrictEqual([r.status, r.stockRestored, r.idempotent], ['returned', true, false]);
  const st = db.docs.get('wholesale_stock/rice');
  assert.deepStrictEqual([st.packs.p1, st.version], [110, 2]);
  assert.strictEqual(db.docs.get('wholesale_stock/rice/history/v2').kind, 'order_return');
  assert.deepStrictEqual([order(db, 's1').status, order(db, 's1').stock.restored], ['returned', true]);
  const r2 = await q(() => selfReturn(db)({ orderId: 's1' }, ctx(SELLER)));
  assert.strictEqual(r2.idempotent, true);
  assert.strictEqual(db.docs.get('wholesale_stock/rice').packs.p1, 110);
});

ok('relay: o\'z yetkazishi qabul qilingan buyurtmada jo\'natma OCHILMAYDI; rad etilganda qaytish jo\'natmasi ham YO\'Q', async () => {
  const db = makeDb({
    'wholesale_orders/s1': selfOrder(),
    'wholesale_orders/s2': selfOrder({ status: 'refused', refundStatus: 'pending' }),
  });
  const r1 = await q(() => api.ensureWholesaleShipment({ db, now: () => NOW }, 's1'));
  assert.ok(String(r1.skipped).startsWith('seller_decision'), JSON.stringify(r1));
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 0);
  assert.deepStrictEqual(await q(() => R.ensureWholesaleReturnShipment({ db, now: () => NOW }, 's2')), { skipped: 'self_delivery' });
  const out = await q(() => E.onWholesaleOrderUpdated({ db, now: () => NOW }, selfOrder({ status: 'in_delivery' }), order(db, 's2'), 's2'));
  assert.strictEqual(out.return, undefined);
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 0);
});

ok('xabarlar S4: qabul / boshlash (karta varianti) / topshirildi / rad (hamyon vs karta) — ws_self_*; kuryer rad matnlari YO\'Q', () => {
  const keys = (b, a) => E.transitionNotifications(b, a).map((x) => `${x.to}:${x.key}`);
  const pend = selfOrder({ sellerDecision: 'pending', acceptedAt: null });
  assert.deepStrictEqual(keys(pend, selfOrder()), ['buyer:ws_self_accepted_buyer', 'seller:ws_self_start_seller']);
  assert.deepStrictEqual(keys({ ...pend, ...CARD_SELF }, selfOrder({ ...CARD_SELF })),
    ['buyer:ws_self_accepted_buyer', 'seller:ws_self_start_seller', 'seller:ws_card_new_order']);
  assert.deepStrictEqual(keys(selfOrder(), selfOrder({ status: 'in_delivery' })), ['buyer:ws_self_started_buyer']);
  assert.deepStrictEqual(keys(selfOrder({ ...CARD_SELF }), selfOrder({ ...CARD_SELF, status: 'in_delivery' })), ['buyer:ws_self_started_buyer_card']);
  assert.deepStrictEqual(keys(selfOrder({ status: 'in_delivery' }), selfOrder({ status: 'delivered' })),
    ['buyer:ws_self_delivered_buyer', 'seller:ws_self_delivered_seller']);
  assert.deepStrictEqual(keys(selfOrder({ status: 'in_delivery' }), selfOrder({ status: 'refused' })), ['buyer:ws_self_refused_buyer_wallet']);
  assert.deepStrictEqual(keys(selfOrder({ ...CARD_SELF, status: 'in_delivery' }), selfOrder({ ...CARD_SELF, status: 'refused' })),
    ['buyer:ws_self_refused_buyer']);
  // Bank o'z yetkazishi: «Пул тушди» → xaridorga + sotuvchiga «o'zingiz yetkazasiz».
  const bank = selfOrder({ paymentMethod: 'bank_transfer', bankPayment: { status: 'awaiting' } });
  assert.deepStrictEqual(keys(bank, { ...bank, bankPayment: { status: 'confirmed', confirmedAt: NOW } }),
    ['buyer:ws_bank_confirmed_buyer', 'seller:ws_self_start_seller']);
});

ok('xabar matnlari: 12 yangi kalit × 3 til, o\'rinbosarlar to\'ldiriladi; {amount} — yangi karta/o\'z yetkazishi: tovar, eski karta: tovar+haq', async () => {
  const KEYS = ['ws_self_accepted_buyer', 'ws_self_start_seller', 'ws_self_started_buyer', 'ws_self_started_buyer_card',
    'ws_self_delivered_buyer', 'ws_self_delivered_seller', 'ws_self_refused_buyer_wallet', 'ws_self_refused_buyer',
    'ws_refused_seller_newcard', 'ws_refused_buyer_card_fee', 'ws_lost_buyer_card_fee', 'ws_lost_buyer_card_fee_partial'];
  assert.deepStrictEqual(Object.keys(N.MESSAGES).filter((k) => k.startsWith('ws_self_')).sort(), KEYS.filter((k) => k.startsWith('ws_self_')).sort());
  const p = {
    product: 'Guruch', qty: 10, amount: G, returnFee: 40000, feeRefund: 60000, left: 20000,
  };
  for (const key of KEYS) {
    for (const lang of N.LANGS) {
      const t = N.render(key, lang, p);
      assert.ok(t.title && t.body, `${key}/${lang}`);
      assert.ok(!/\{\w+\}/.test(t.title + t.body), `${key}/${lang}: ${t.body}`);
    }
  }
  // {amount} parametri (haqiqiy yetkazish orqali): yangi karta — 140 000, eski — 200 000.
  const db = makeDb();
  await q(() => E.onWholesaleOrderUpdated({ db, now: () => NOW }, { ...NEW_CARD, cardPayment: { status: 'awaiting' } },
    { ...NEW_CARD, cardPayment: { status: 'confirmed' } }, 'n1'));
  await q(() => E.onWholesaleOrderUpdated({ db, now: () => NOW }, { ...LEGACY_CARD, cardPayment: { status: 'awaiting' } },
    { ...LEGACY_CARD, cardPayment: { status: 'confirmed' } }, 'l1'));
  const news = db.dump('admin_news');
  assert.ok(news[`wholesale_n1_ws_card_confirmed_${BUYER}`].body.includes('140000'));
  assert.ok(news[`wholesale_l1_ws_card_confirmed_${BUYER}`].body.includes('200000'));
});

// ═══════════════════════════════════════════════════════════════════════
// AVA ulushi hisoboti
// ═══════════════════════════════════════════════════════════════════════

ok('hisobot: o\'z yetkazishi KARTA — kiradi; kuryerli karta va o\'z yetkazishi HAMYON — kirmaydi; bank — avvalgidek; oylik — avaFeeVia', async () => {
  const db = makeDb();
  const P = F.parsePeriod('2026-11-11');
  const at = new Date(P.startMs + 60 * 60 * 1000);
  const put = async (id, o, fee) => {
    await db.collection('wholesale_orders').doc(id).set({
      sellerId: SELLER, buyerId: BUYER, status: 'delivered', goodsTotal: 100000, deliveryFee: 0, deliveredAt: at, ...o,
    });
    await db.collection('wholesale_orders').doc(id).collection('private').doc('settlement')
      .set({ goodsTotal: 100000, avaFee: fee, avaFeeBps: 200, sellerPayout: 100000 - fee });
  };
  await put('selfCard', { paymentMethod: 'card_on_delivery', deliveryMethod: 'self' }, 2000);
  await put('courierCard', { paymentMethod: 'card_on_delivery', deliveryPaidBy: 'buyer', deliveryFee: 30000 }, 2000);
  await put('selfWallet', { paymentMethod: 'wallet', deliveryMethod: 'self' }, 2000);
  await put('bank', { paymentMethod: 'bank_transfer', deliveryFee: 30000 }, 2000);
  await put('selfBank', { paymentMethod: 'bank_transfer', deliveryMethod: 'self' }, 2000);
  const r = await q(() => F.makeAdminGetWholesaleFeeStatement({ db, now: () => new Date(P.endMs + 1) })({ periodStart: '2026-11-11' }, ctx(ADMIN)));
  assert.deepStrictEqual(r.totals, {
    sellers: 1, count: 3, goodsTotal: 300000, avaFeeDue: 6000,
  });
  assert.deepStrictEqual(r.sellers[0].orderIds.sort(), ['bank', 'selfBank', 'selfCard']);
  const m = await q(() => F.makeAdminGetWholesaleOrdersReport({ db })({ month: '2026-11' }, ctx(ADMIN)));
  const via = Object.fromEntries(m.rows.map((x) => [`${x.paymentMethod}|${x.deliveryMethod}`, x.avaFeeVia]));
  assert.deepStrictEqual(via, {
    'card_on_delivery|self': 'statement',
    'card_on_delivery|ava_courier': 'release',
    'wallet|self': 'release',
    'bank_transfer|ava_courier': 'statement',
    'bank_transfer|self': 'statement',
  });
});

(async () => {
  for (const t of tests) {
    try {
      await t.fn();
      passed += 1;
      console.log(`  ok  ${t.name}`);
    } catch (e) {
      loud();
      console.log(`  XATO ${t.name}\n       ${e.stack || e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
