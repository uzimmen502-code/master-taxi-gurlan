/**
 * «AVA Супермаркет» 3-босқич — харид режаси, кунлик статистика (идемпотент), origin, ҳақиқий `functions/index.js`, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-supermarket3 "node test/supermarket_reports_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-supermarket3';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const functions = require('firebase-functions');
const { tashkentParts } = require('../supermarket');
const R = require('../supermarket_reports');
const TAX2 = require('../tools/data/supermarket_taxonomy_v2.json');
const SETTINGS = require('../tools/data/supermarket_settings_v1.json');

const db = admin.firestore();
const ADMIN = '998915000001';
const USER = '998912000001';
const OTHER = '998912000003';
const DISP = '998915000004';
const DAY = 86400000;
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, who ? ctxOf(who) : {});

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
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
const get = async (path) => (await db.doc(path).get()).data();
const variety = (id, c) => ({ id, names: { uz_Cyrl: c, uz_Latn: c, ru: c } });
const ADDR = { districtId: 'gurlan', mahalla: 'Navoiy', street: 'Mustaqillik', house: '12', phone: '901234567' };
let rq = 0;
const rid = () => `rep-${String(++rq).padStart(8, '0')}`;
const place = (items, who = USER, extra = {}) => call('placeSupermarketOrder', { clientRequestId: rid(), items, address: ADDR, slotId: 'morning', day: 'tomorrow', ...extra }, who);

// Кейинги кун (эртадан кейин) деб маҳаллий attach — smDailyStats «кеча» = эртанги слот куни.
const HttpsError = functions.https.HttpsError;
const requireCallerRoles = async (context, roles) => {
  if (!context || !context.auth) throw new HttpsError('unauthenticated', 'x');
  const p = String(context.auth.token.phone_number || '').replace(/\D/g, '');
  const s = await db.doc(`users/${p}`).get();
  if (!roles.includes((s.data() || {}).role)) throw new HttpsError('permission-denied', 'x');
  return p;
};
const TOMORROW = tashkentParts(Date.now() + DAY).dateKey;
const TODAY = tashkentParts(Date.now()).dateKey;
const local = {};
const api = R.attachSupermarketReports(local, { functions, db, admin, requireCallerRoles, nowMs: () => Date.now() + 2 * DAY });
const lcall = (name, data, who) => local[name].run(data, ctxOf(who));

async function main() {
  await clearEmulator();
  await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
  await db.doc(`users/${DISP}`).set({ role: 'dispatcher' });
  await db.doc('users/912000001').set({ role: 'user', name: 'Ali', bonusBalance: 2000000, districtId: 'gurlan' });
  await db.doc(`users/${OTHER}`).set({ role: 'user', name: 'Vali', bonusBalance: 2000000, districtId: 'gurlan' });
  await db.doc('settings/app').set({ platformDeliveryFeePercent: 10, platformDeliveryFeeVersion: 1 });
  await call('adminSetSupermarketTaxonomy', { taxonomy: TAX2, expectedVersion: 0 }, ADMIN);
  await call('adminSetSupermarketSettings', { settings: { ...SETTINGS, testerIds: [USER, OTHER] }, expectedVersion: 0 }, ADMIN);
  const up = (productId, offer) => call('adminUpsertSupermarketOffer', { productId, offer }, ADMIN);
  await up('beef_lean_1', { smGroupId: 'beef', smVariety: variety('lean', 'Лаҳм'), stock: 4, smStatus: 'active', price: 80000 });
  await up('milk_1l_01', { smGroupId: 'milk', smVariety: variety('cow', 'Сигир'), stock: 10, smStatus: 'active', price: 12000 });

  const ids = {};
  await check('K1 origin: weekly/quick сақланади, йўқ → catalog, нотўғри → INVALID_REQUEST (field origin), пул ечилмайди', async () => {
    const before = (await get('users/912000001')).bonusBalance;
    await expectCode(place([{ productId: 'milk_1l_01', qty: 1 }], USER, { origin: 'bogus' }), 'INVALID_REQUEST');
    await expectCode(place([{ productId: 'milk_1l_01', qty: 1 }], USER, { origin: 5 }), 'INVALID_REQUEST');
    assert.strictEqual((await get('users/912000001')).bonusBalance, before);
    ids.o1 = (await place([{ productId: 'beef_lean_1', qty: 1.5 }, { productId: 'milk_1l_01', qty: 2 }], USER, { origin: 'weekly' })).orderId;
    ids.o2 = (await place([{ productId: 'beef_lean_1', qty: 1 }], OTHER)).orderId;
    ids.o3 = (await place([{ productId: 'milk_1l_01', qty: 3 }], OTHER, { origin: 'quick' })).orderId;
    ids.o4 = (await place([{ productId: 'beef_lean_1', qty: 0.5 }], USER, { origin: 'reorder' })).orderId;
    assert.strictEqual((await get(`orders/${ids.o1}`)).smOrigin, 'weekly');
    assert.strictEqual((await get(`orders/${ids.o2}`)).smOrigin, 'catalog');
    assert.strictEqual((await get(`orders/${ids.o2}`)).slot.date, TOMORROW);
    await db.doc(`orders/${ids.o4}`).update({ status: 'rejected' }); // рад (stock trigger эмуляторда йўқ)
    await db.doc(`orders/${ids.o3}`).update({ status: 'accepted' });
  });

  await check('K2 харид режаси: dispatcher ўқийди; user/anon рад; сана нотўғри; талаб/stock/shortfall; бекор чиқарилади; PII йўқ', async () => {
    await expectCode(call('adminSupermarketProcurementReport', { date: TOMORROW }, USER), 'PERMISSION_DENIED');
    await expectCode(call('adminSupermarketProcurementReport', { date: TOMORROW }), 'UNAUTHENTICATED');
    await expectCode(call('adminSupermarketProcurementReport', { date: '2026-02-30' }, DISP), 'DATE_INVALID');
    await expectCode(call('adminSupermarketProcurementReport', { date: '2020-01-01' }, DISP), 'DATE_INVALID');
    // Бошқа сана (бугун) 'ready' буюртма — жисмоний қолдиқда банд (ҳар қандай сана), харид режасига кирмайди.
    await db.doc('orders/ready_today').set({ type: 'platform', subtype: 'supermarket', status: 'ready', paymentStatus: 'paid', slot: { date: TODAY }, items: [{ productId: 'beef_lean_1', groupId: 'beef', qty: 0.5, smUnit: 'kg' }] });
    // Етказилган — банд эмас.
    await db.doc('orders/delivered_x').set({ type: 'platform', subtype: 'supermarket', status: 'delivered', fulfillmentStatus: 'completed', slot: { date: TODAY }, items: [{ productId: 'beef_lean_1', groupId: 'beef', qty: 9, smUnit: 'kg' }] });
    const r = await call('adminSupermarketProcurementReport', { date: TOMORROW }, DISP);
    assert.strictEqual(r.orderCount, 3);
    assert.strictEqual(r.onHandSource, 'stock+open_orders');
    const beef = r.offers.find((o) => o.productId === 'beef_lean_1');
    // бўш stock 4 − 1.5 − 1 − 0.5 = 1; банд = 1.5 + 1 (эртага) + 0.5 (бугун ready) = 3 (рад 0.5, етказилган 9 кирмайди)
    // жисмоний = 4; талаб 2.5 → shortfall 0
    assert.deepStrictEqual([beef.demandQty, beef.stock, beef.reserved, beef.onHand, beef.shortfall, beef.orderCount, beef.unit, beef.weighed], [2.5, 1, 3, 4, 0, 2, 'kg', true]);
    assert.strictEqual(beef.categoryId, 'meat_fish');
    assert.strictEqual(beef.varietyId, 'lean');
    const milk = r.offers.find((o) => o.productId === 'milk_1l_01');
    assert.deepStrictEqual([milk.demandQty, milk.stock, milk.reserved, milk.onHand, milk.shortfall, milk.unit], [5, 5, 5, 10, 0, 'l']);
    // Жисмоний қолдиқ талабдан кам бўлса: бўш stock'ни 0 га (админ инвентаризацияси) — onHand = банд 3 + 0, талаб 2.5 → 0;
    // бугунги ready'ни бекор қилиб, stock 0 → onHand 2.5 = талаб → 0 (чегара); талаб > onHand ҳолати pure тестда.
    await db.doc('platform_products/beef_lean_1').update({ stock: 0 });
    await db.doc('orders/ready_today').update({ status: 'cancelled' });
    const r0 = await call('adminSupermarketProcurementReport', { date: TOMORROW }, DISP);
    const b0 = r0.offers.find((o) => o.productId === 'beef_lean_1');
    assert.deepStrictEqual([b0.stock, b0.reserved, b0.onHand, b0.shortfall], [0, 2.5, 2.5, 0]);
    await db.doc('platform_products/beef_lean_1').update({ stock: 1 });
    assert.ok(r.categories.find((c) => c.categoryId === 'dairy'));
    assert.strictEqual(r.stockIsNetOfReservations, true);
    const json = JSON.stringify(r);
    for (const k of ['userPhone', '998912000001', 'Mustaqillik', 'Ali', 'contactPhone']) assert.ok(!json.includes(k), k);
    const admin2 = await call('adminSupermarketProcurementReport', { date: TODAY }, ADMIN);
    assert.strictEqual(admin2.orderCount, 0);
  });

  await check('K3 тортиш қайтими smRefundByAction.weigh га ёзилади (smRefundedTotal билан тенг)', async () => {
    const r = await call('adminSettleSupermarketWeights', { orderId: ids.o1, lines: [{ productId: 'beef_lean_1', actualQty: 1.4 }] }, DISP);
    assert.ok(r.refund > 0);
    const od = await get(`orders/${ids.o1}`);
    assert.strictEqual(od.smRefundByAction.weigh, r.refund);
    assert.strictEqual(od.smRefundedTotal, r.refund);
    ids.weighRefund = r.refund;
  });

  await check('K4 smDailyStats: кечаги кун (slot.date) ёзилади, икки марта — бир хил; такрорий мижоз; эслатмали рўйхатлар', async () => {
    // USER аввал ҳам буюртма берган (эски сана) — такрорий; OTHER — биринчи марта.
    await db.collection('orders').doc('old_user_order').set({ subtype: 'supermarket', userPhone: USER, slot: { date: '2026-01-05' }, status: 'delivered', items: [] });
    await db.doc('users/912000001/sm_lists/w1').set({ name: 'Ҳафта', items: [], remind: { enabled: true, weekday: 1, minute: 600 }, remindNextAt: admin.firestore.Timestamp.fromMillis(Date.now() + DAY) });
    await db.doc('users/912000001/sm_lists/w2').set({ name: 'Off', items: [], remind: { enabled: false, weekday: 1, minute: 600 } });
    const a = await api.runDailyStats();
    assert.strictEqual(a.date, TOMORROW);
    const s1 = await get(`supermarket_stats/${TOMORROW}`);
    const o1 = await get(`orders/${ids.o1}`);
    const o2 = await get(`orders/${ids.o2}`);
    const o3 = await get(`orders/${ids.o3}`);
    assert.deepStrictEqual([s1.orders, s1.cancelled, s1.delivered, s1.open], [4, 1, 0, 3]);
    assert.strictEqual(s1.gmv, o1.itemsTotal + o2.itemsTotal + o3.itemsTotal);
    assert.strictEqual(s1.deliveryFeeRevenue, o1.deliveryFee + o2.deliveryFee + o3.deliveryFee);
    assert.strictEqual(s1.refundsTotal, ids.weighRefund);
    assert.strictEqual(s1.refundsByType.weigh, ids.weighRefund);
    assert.deepStrictEqual(s1.byOrigin, { catalog: 1, quick: 1, weekly: 1, reorder: 1, unknown: 0 });
    assert.deepStrictEqual([s1.uniqueCustomers, s1.repeatCustomers], [2, 1]);
    assert.strictEqual(s1.listsWithReminders, 1);
    assert.strictEqual(s1.courierPayout, null);
    assert.strictEqual(s1.netLogistics, null);
    assert.strictEqual(s1.source, 'schedule');
    assert.strictEqual(s1.dateBasis, 'slot.date');
    await api.runDailyStats();
    const s2 = await get(`supermarket_stats/${TOMORROW}`);
    const strip = ({ computedAt, ...x }) => x;
    assert.deepStrictEqual(strip(s2), strip(s1), 'qayta hisob — bir xil');
  });

  await check('K5 adminSupermarketStats: фақат admin; оралиқ ≤92; бор кун ўқилади; йўқ кун missing; backfill ёзади + audit; тугамаган кун ёзилмайди', async () => {
    await expectCode(lcall('adminSupermarketStats', { from: TOMORROW, to: TOMORROW }, DISP), 'PERMISSION_DENIED');
    await expectCode(lcall('adminSupermarketStats', { from: TOMORROW, to: R.addDays(TOMORROW, 92) }, ADMIN), 'RANGE_INVALID');
    await expectCode(lcall('adminSupermarketStats', { from: TOMORROW, to: R.addDays(TOMORROW, -1) }, ADMIN), 'RANGE_INVALID');
    await expectCode(lcall('adminSupermarketStats', { from: 'x', to: TOMORROW }, ADMIN), 'RANGE_INVALID');
    const okMax = await lcall('adminSupermarketStats', { from: R.addDays(TOMORROW, -91), to: TOMORROW }, ADMIN);
    assert.strictEqual(okMax.missing.length, 91);
    const prev = R.addDays(TOMORROW, -1);
    const r = await lcall('adminSupermarketStats', { from: prev, to: TOMORROW }, ADMIN);
    assert.deepStrictEqual(r.missing, [prev]);
    assert.strictEqual(r.days.length, 1);
    assert.strictEqual(r.summary.orders, 4);
    assert.strictEqual(r.summary.weeklyOrders, 1);
    assert.strictEqual(r.summary.netLogistics, null);
    assert.strictEqual(r.listsWithReminders, 1);
    assert.strictEqual((await db.doc(`supermarket_stats/${prev}`).get()).exists, false, 'backfillsiz yozilmaydi');
    const b = await lcall('adminSupermarketStats', { from: prev, to: R.addDays(TOMORROW, 1) }, ADMIN);
    assert.deepStrictEqual(b.missing, [prev, R.addDays(TOMORROW, 1)]);
    const bf = await lcall('adminSupermarketStats', { from: prev, to: R.addDays(TOMORROW, 1), backfill: true }, ADMIN);
    assert.deepStrictEqual(bf.backfilled, [prev]);
    assert.deepStrictEqual(bf.partial, [R.addDays(TOMORROW, 1)], 'bugun/kelajak — yozilmaydi');
    assert.deepStrictEqual(bf.missing, []);
    assert.strictEqual((await get(`supermarket_stats/${prev}`)).source, 'backfill');
    assert.strictEqual((await db.doc(`supermarket_stats/${R.addDays(TOMORROW, 1)}`).get()).exists, false);
    const au = (await db.collection('admin_audit').where('kind', '==', 'supermarket_stats_backfill').get()).docs.map((d) => d.data());
    assert.strictEqual(au.length, 1);
    assert.deepStrictEqual(au[0].dates, [prev]);
  });

  await check('K6 index.js экспорти: adminSupermarketProcurementReport, adminSupermarketStats, smDailyStats', async () => {
    for (const n of ['adminSupermarketProcurementReport', 'adminSupermarketStats', 'smDailyStats']) assert.ok(fns[n], n);
  });

  const passed = results.filter(Boolean).length;
  console.log(`\nsupermarket_reports_cf: ${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
