/**
 * «AVA Супермаркет» — callable'лар, ҲАҚИҚИЙ `functions/index.js`, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-supermarket "node test/supermarket_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-supermarket';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const TAX = require('../tools/data/supermarket_taxonomy_v1.json');
const SETTINGS = require('../tools/data/supermarket_settings_v1.json');

const db = admin.firestore();
const ADMIN = '998915000001';
const USER = '998912000001'; // мижоз (9 хонали users ҳужжати — эски шакл)
const POOR = '998912000002';
const OTHER = '998912000003';
const DISP = '998915000004';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, who ? ctxOf(who) : {});

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function expectCode(promise, code) {
  let caught;
  await assert.rejects(promise, (e) => {
    const got = (e.details && e.details.code) || e.message;
    assert.strictEqual(got, code, `kod ${got}: ${e.message}`);
    caught = e;
    return true;
  });
  return caught;
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const get = async (path) => (await db.doc(path).get()).data();
const audits = async (kind) => (await db.collection('admin_audit').where('kind', '==', kind).get()).docs.map((d) => d.data());
const variety = (id, c, l, r) => ({ id, names: { uz_Cyrl: c, uz_Latn: l, ru: r } });
const ADDR = { districtId: 'gurlan', mahalla: 'Navoiy', street: 'Mustaqillik', house: '12', phone: '901234567', lat: 41.84, lng: 60.39 };
// Эга 2026-11-28: оддий буюртма — вақт оралиғисиз (имкон қадар тез). Эски клиент шакли — legacyOrder.
const order = (rid, items, extra = {}) => ({ clientRequestId: rid, items, address: ADDR, ...extra });
const legacyOrder = (rid, items, extra = {}) => order(rid, items, { slotId: 'morning', day: 'tomorrow', ...extra });
const moduleGate = require('../module_gate');
async function setModules(defaults, districts = {}) {
  await db.doc('config/module_defaults').set({ enforce: true, modules: defaults });
  for (const [id, status] of Object.entries(districts)) {
    await db.doc(`geo_district_modules/${id}`).set({ manualModules: ['supermarket'], modules: { supermarket: status } });
  }
  moduleGate.resetCache();
}

async function main() {
  await clearEmulator();
  await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
  await db.doc(`users/${DISP}`).set({ role: 'dispatcher' });
  await db.doc('users/912000001').set({ role: 'user', name: 'Ali', bonusBalance: 500000, districtId: 'gurlan', regionId: 'xorazm' });
  await db.doc(`users/${POOR}`).set({ role: 'user', bonusBalance: 1000, districtId: 'gurlan' });
  await db.doc(`users/${OTHER}`).set({ role: 'user', bonusBalance: 500000, districtId: 'urganch' });
  await db.doc('settings/app').set({ platformDeliveryFeeVersion: 2 }); // % йўқ — fail closed текшируви учун (C2)

  await check('C1 таксономия: оддий фойдаланувчи рад; admin v0→v1 (+тарих supermarket_v1, audit); такрор — версия ошмайди; конфликт; нотўғри', async () => {
    await assert.rejects(call('adminSetSupermarketTaxonomy', { taxonomy: TAX, expectedVersion: 0 }, USER), (e) => e.code === 'permission-denied');
    await assert.rejects(call('adminSetSupermarketTaxonomy', { taxonomy: TAX, expectedVersion: 0 }, null), (e) => e.code === 'unauthenticated');
    const bad = JSON.parse(JSON.stringify(TAX)); bad.categories[0].groups[0].unit = 'ton';
    const e = await expectCode(call('adminSetSupermarketTaxonomy', { taxonomy: bad, expectedVersion: 0 }, ADMIN), 'TAXONOMY_INVALID');
    assert.ok(e.details.errors.includes('UNIT_INVALID categories[0].groups[0].unit'));
    assert.ok(e.details.messages.uz_Latn && e.details.messages.ru);
    const r = await call('adminSetSupermarketTaxonomy', { taxonomy: TAX, expectedVersion: 0 }, ADMIN);
    assert.deepStrictEqual([r.version, r.changed], [1, true]);
    const doc = await get('taxonomy/supermarket');
    assert.strictEqual(doc.categories.length, 9);
    assert.ok((await db.doc('taxonomy_history/supermarket_v1').get()).exists);
    assert.strictEqual((await db.doc('taxonomy_history/v1').get()).exists, false, 'markets тарихи билан тўқнашмасин');
    const again = await call('adminSetSupermarketTaxonomy', { taxonomy: TAX, expectedVersion: 0 }, ADMIN);
    assert.deepStrictEqual([again.version, again.changed], [1, false]);
    const t2 = JSON.parse(JSON.stringify(TAX)); t2.categories[0].groups[0].synonyms.push('beef');
    await expectCode(call('adminSetSupermarketTaxonomy', { taxonomy: t2, expectedVersion: 0 }, ADMIN), 'TAXONOMY_VERSION_CONFLICT');
    assert.strictEqual((await audits('supermarket_taxonomy_set')).length, 1);
  });

  await check('C2 дарвоза (эга 2026-11-28): ФАҚАТ модул созламаси — hidden/coming_soon рад, туман override enabled; settings ҳужжати йўқ — ёпиқ ЭМАС; % йўқ → TARIFF_NOT_CONFIGURED', async () => {
    await setModules({ supermarket: 'hidden' });
    const hid = await call('getSupermarketAccess', {}, USER);
    assert.deepStrictEqual([hid.allowed, hid.reason, !!hid.messages.uz_Latn], [false, 'MODULE_CLOSED', true]);
    await expectCode(call('placeSupermarketOrder', order('req-hidden-001', [{ productId: 'beef_lean_1', qty: 1 }]), USER), 'MODULE_CLOSED');
    await setModules({ supermarket: 'hidden' }, { gurlan: 'enabled', urganch: 'coming_soon' });
    // settings/supermarket ҳали ЙЎҚ — эски «STAGE_OFF» эмас; фақат тариф (fail closed).
    assert.strictEqual((await db.doc('settings/supermarket').get()).exists, false);
    const nf = await call('getSupermarketAccess', {}, USER);
    assert.deepStrictEqual([nf.allowed, nf.reason, nf.feePercent], [false, 'TARIFF_NOT_CONFIGURED', null]);
    await expectCode(call('placeSupermarketOrder', order('req-nofee-0001', [{ productId: 'beef_lean_1', qty: 1 }]), USER), 'TARIFF_NOT_CONFIGURED');
    await db.doc('settings/app').set({ platformDeliveryFeePercent: 11 }, { merge: true });
    const ok = await call('getSupermarketAccess', {}, USER);
    assert.deepStrictEqual([ok.allowed, ok.feePercent, ok.weighHoldPercent, ok.slots.tomorrow.length], [true, 11, 10, 0]);
    const soon = await call('getSupermarketAccess', {}, OTHER);
    assert.deepStrictEqual([soon.allowed, soon.reason], [false, 'MODULE_CLOSED'], 'urganch — coming_soon');
    const farOk = await call('getSupermarketAccess', { districtId: 'gurlan' }, OTHER);
    assert.strictEqual(farOk.allowed, true, 'фаол (тепада танланган) туман');
    const dates = await call('getSupermarketAccess', { withDates: true }, USER);
    assert.strictEqual(dates.deliveryDates.length, 15);
    // Созламалар: эски шакл (stage/slots…) ҳам, янги минимал шакл ҳам қабул қилинади; stage дарвозага таъсир қилмайди.
    await assert.rejects(call('adminSetSupermarketSettings', { settings: SETTINGS, expectedVersion: 0 }, USER), (e) => e.code === 'permission-denied');
    await expectCode(call('adminSetSupermarketSettings', { settings: { ...SETTINGS, stage: 'beta' }, expectedVersion: 0 }, ADMIN), 'SETTINGS_INVALID');
    const s1 = await call('adminSetSupermarketSettings', { settings: { ...SETTINGS, stage: 'off' }, expectedVersion: 0, reason: 'legacy' }, ADMIN);
    assert.deepStrictEqual([s1.version, s1.changed], [1, true]);
    assert.strictEqual((await call('getSupermarketAccess', {}, USER)).allowed, true, 'эски stage off — эътиборсиз');
    const s2 = await call('adminSetSupermarketSettings', { settings: { weighHoldPercent: 10 }, expectedVersion: 1 }, ADMIN);
    assert.strictEqual(s2.version, 2);
    assert.strictEqual((await get('settings/supermarket')).slots, undefined, 'янги сақлаш эски майдонларни олиб ташлайди');
    assert.strictEqual((await audits('supermarket_settings_set')).length, 2);
    // Эски клиент синови учун оралиқлар қайтадан (legacyOrder).
    await call('adminSetSupermarketSettings', { settings: { weighHoldPercent: 10, slots: SETTINGS.slots, cutoffMin: 60 }, expectedVersion: 2 }, ADMIN);
  });

  await check('C3 таклиф: admin яратади (active:false, sm майдонлар, searchTokens, private/cost), нарх аудити; такрор — аудитсиз; GROUP_UNKNOWN', async () => {
    await assert.rejects(call('adminUpsertSupermarketOffer', { productId: 'beef_lean_1', offer: {} }, USER), (e) => e.code === 'permission-denied');
    const beefOffer = { smGroupId: 'beef', smVariety: variety('lean', 'Лаҳм', 'Lahm', 'Постная'), smQuality: { uz_Cyrl: 'Олий', uz_Latn: 'Oliy', ru: 'Высший' }, stock: 10, smStatus: 'active', price: 80000 };
    const r = await call('adminUpsertSupermarketOffer', { productId: 'beef_lean_1', offer: beefOffer, cost: { purchasePrice: 70000, supplier: 'Гурлан бозори' } }, ADMIN);
    assert.deepStrictEqual([r.created, r.priceChanged, r.costChanged], [true, true, true]);
    const d = await get('platform_products/beef_lean_1');
    assert.deepStrictEqual([d.active, d.smCategoryId, d.unit, d.qtyStep, d.weighed, d.stock, d.price, d.name], [false, 'meat_fish', 'kg', 0.5, true, 10, 80000, 'Мол гўшти Лаҳм']);
    assert.ok(d.priceUpdatedAt && d.searchTokens.includes('говядина') && d.searchTokens.includes('mol'));
    assert.strictEqual(d.purchasePrice, undefined, 'харид нархи оммавий ҳужжатда йўқ');
    assert.deepStrictEqual((await get('platform_products/beef_lean_1/private/cost')).purchasePrice, 70000);
    await call('adminUpsertSupermarketOffer', { productId: 'milk_1l_1', offer: { smGroupId: 'milk', smVariety: variety('cow', 'Сигир', 'Sigir', 'Коровье'), packLabel: '1 л', stock: 5, smStatus: 'active', price: 12000 } }, ADMIN);
    await call('adminUpsertSupermarketOffer', { productId: 'potato_1', offer: { smGroupId: 'potato', smVariety: variety('local', 'Маҳаллий', 'Mahalliy', 'Местный'), stock: 100, smStatus: 'active', price: 5000 } }, ADMIN);
    const same = await call('adminUpsertSupermarketOffer', { productId: 'beef_lean_1', offer: beefOffer, cost: { purchasePrice: 70000, supplier: 'Гурлан бозори' } }, ADMIN);
    assert.deepStrictEqual([same.created, same.priceChanged, same.costChanged], [false, false, false]);
    assert.strictEqual((await audits('supermarket_offer_price')).length, 3);
    await call('adminUpsertSupermarketOffer', { productId: 'potato_1', offer: { smGroupId: 'potato', smVariety: variety('local', 'Маҳаллий', 'Mahalliy', 'Местный'), stock: 100, smStatus: 'active', price: 5500 } }, ADMIN);
    const pa = (await audits('supermarket_offer_price')).find((a) => a.target === 'platform_products/potato_1' && a.oldPrice === 5000);
    assert.deepStrictEqual([pa.newPrice, pa.actor], [5500, ADMIN]);
    await expectCode(call('adminUpsertSupermarketOffer', { productId: 'zz_unknown', offer: { ...beefOffer, smGroupId: 'caviar' } }, ADMIN), 'GROUP_UNKNOWN');
    await expectCode(call('adminUpsertSupermarketOffer', { productId: 'beef_lean_1', offer: { ...beefOffer, price: 1.5 } }, ADMIN), 'OFFER_INVALID');
  });

  let orderId;
  await check('C4 буюртма: сервер нархи, hold = goods + ceil10% + fee(11%), ҳамён/journal/ledger, stock, orders type platform/supermarket', async () => {
    const r = await call('placeSupermarketOrder', order('req-order-0001', [{ productId: 'beef_lean_1', qty: 1.5 }, { productId: 'milk_1l_1', qty: 2 }]), USER);
    orderId = r.orderId;
    assert.deepStrictEqual([r.itemsTotal, r.weighHold, r.deliveryFee, r.total, r.deliveryFeePercent, r.paymentStatus], [144000, 12000, 15840, 171840, 11, 'paid']);
    assert.strictEqual((await get('users/912000001')).bonusBalance, 500000 - 171840);
    const o = await get(`orders/${orderId}`);
    assert.deepStrictEqual([o.type, o.subtype, o.status, o.fulfillmentStatus, o.paymentStatus, o.balanceApplied, o.cashDue, o.walletUserDocId, o.tariffVersion, o.districtId],
      ['platform', 'supermarket', 'new', 'pending', 'paid', 171840, 0, '912000001', 'sm-v1', 'gurlan']);
    assert.deepStrictEqual([o.deliveryFeePercent, o.deliveryFeeVersion, r.deliveryFeeVersion], [11, 2, 2]);
    assert.deepStrictEqual([o.items[0].price, o.items[0].qty, o.items[0].holdExtra, o.items[1].total], [80000, 1.5, 12000, 24000]);
    // Эга 2026-11-28: вақт оралиғисиз — имкон қадар тез (бугун); slot.date — статистика асоси сақланади.
    assert.deepStrictEqual([o.slot.id, o.slot.day, o.slot.asap, o.slot.date === o.deliveryDate, r.asap, o.lat, o.contactPhone], ['asap', 'today', true, true, true, 41.84, '998901234567']);
    assert.strictEqual(o.address, 'Navoiy, Mustaqillik, 12');
    assert.deepStrictEqual([(await get('platform_products/beef_lean_1')).stock, (await get('platform_products/milk_1l_1')).stock], [8.5, 3]);
    const j = await get(`journal_entries/bonus:sm_order_${orderId}`);
    assert.deepStrictEqual([j.kind, j.amount, j.refId], ['order_wallet', 171840, orderId]);
    const wl = (await db.collection('users/912000001/wallet_ledger').get()).docs.map((x) => x.data());
    assert.deepStrictEqual([wl.length, wl[0].type, wl[0].amount], [1, 'purchase_debit', -171840]);
  });

  await check('C5 идемпотент: шу clientRequestId қайта — шу orderId, ҳамён ўзгармайди, иккинчи буюртма йўқ', async () => {
    const r = await call('placeSupermarketOrder', order('req-order-0001', [{ productId: 'beef_lean_1', qty: 1.5 }, { productId: 'milk_1l_1', qty: 2 }]), USER);
    assert.deepStrictEqual([r.orderId, r.duplicate], [orderId, true]);
    assert.strictEqual((await get('users/912000001')).bonusBalance, 500000 - 171840);
    assert.strictEqual((await db.collection('orders').where('subtype', '==', 'supermarket').get()).size, 1);
    const [a, b] = await Promise.all([
      call('placeSupermarketOrder', order('req-race-00001', [{ productId: 'potato_1', qty: 2 }]), USER),
      call('placeSupermarketOrder', order('req-race-00001', [{ productId: 'potato_1', qty: 2 }]), USER),
    ]);
    assert.strictEqual(a.orderId, b.orderId);
    assert.strictEqual((await get('platform_products/potato_1')).stock, 98);
  });

  await check('C6 рад этишлар: маблағ етмайди, қадам, stock, номаълум товар, оралиқ, ҳудуд, дубликат', async () => {
    await expectCode(call('placeSupermarketOrder', order('req-poor-00001', [{ productId: 'milk_1l_1', qty: 1 }]), POOR), 'INSUFFICIENT_BALANCE');
    await expectCode(call('placeSupermarketOrder', order('req-step-00001', [{ productId: 'beef_lean_1', qty: 1.3 }]), USER), 'QTY_STEP_INVALID');
    await expectCode(call('placeSupermarketOrder', order('req-stock-0001', [{ productId: 'milk_1l_1', qty: 4 }]), USER), 'OUT_OF_STOCK');
    await expectCode(call('placeSupermarketOrder', order('req-nf-0000001', [{ productId: 'nope_123', qty: 1 }]), USER), 'PRODUCT_NOT_FOUND');
    await expectCode(call('placeSupermarketOrder', legacyOrder('req-slot-00001', [{ productId: 'milk_1l_1', qty: 1 }], { slotId: 'night' }), USER), 'SLOT_UNAVAILABLE');
    await expectCode(call('placeSupermarketOrder', order('req-dist-00001', [{ productId: 'milk_1l_1', qty: 1 }], { address: { ...ADDR, districtId: 'urganch' } }), USER), 'MODULE_CLOSED');
    // Совға/байрам санаси: нотўғри шакл, ўтган кун, +15 кун — рад (бугун..+14).
    const today = new Date(Date.now() + 5 * 3600000).toISOString().slice(0, 10);
    const plus = (n) => new Date(Date.now() + 5 * 3600000 + n * 86400000).toISOString().slice(0, 10);
    await expectCode(call('placeSupermarketOrder', order('req-date-bad01', [{ productId: 'milk_1l_1', qty: 1 }], { deliveryDate: '2026-13-01' }), USER), 'INVALID_REQUEST');
    await expectCode(call('placeSupermarketOrder', order('req-date-past1', [{ productId: 'milk_1l_1', qty: 1 }], { deliveryDate: plus(-1) }), USER), 'INVALID_REQUEST');
    await expectCode(call('placeSupermarketOrder', order('req-date-far01', [{ productId: 'milk_1l_1', qty: 1 }], { deliveryDate: plus(15) }), USER), 'INVALID_REQUEST');
    assert.ok(today.length === 10);
    await expectCode(call('placeSupermarketOrder', order('req-dup-000001', [{ productId: 'milk_1l_1', qty: 1 }, { productId: 'milk_1l_1', qty: 1 }]), USER), 'DUPLICATE_ITEM');
    await expectCode(call('placeSupermarketOrder', order('bad', [{ productId: 'milk_1l_1', qty: 1 }]), USER), 'INVALID_REQUEST');
    await assert.rejects(call('placeSupermarketOrder', order('req-anon-00001', [{ productId: 'milk_1l_1', qty: 1 }]), null), (e) => e.code === 'unauthenticated');
    assert.strictEqual((await get(`users/${POOR}`)).bonusBalance, 1000);
    assert.strictEqual((await get('platform_products/milk_1l_1')).stock, 3);
    await db.doc('platform_products/legacy_1').set({ name: 'Эски товар', price: 1000, active: true });
    await expectCode(call('placeSupermarketOrder', order('req-legacy-001', [{ productId: 'legacy_1', qty: 1 }]), USER), 'PRODUCT_UNAVAILABLE');
  });

  await check('C7 тортиш: 1.4 кг → фарқ 20880 ҳамёнга, balanceApplied 150960, stock +0.1; такрор — ўзгармайди; чегарадан ортиқ рад; мижоз рад', async () => {
    const bal0 = (await get('users/912000001')).bonusBalance;
    await assert.rejects(call('adminSettleSupermarketWeights', { orderId, lines: [{ productId: 'beef_lean_1', actualQty: 1.4 }] }, USER), (e) => e.code === 'permission-denied');
    await expectCode(call('adminSettleSupermarketWeights', { orderId, lines: [{ productId: 'beef_lean_1', actualQty: 1.66 }] }, ADMIN), 'ACTUAL_QTY_OVER_LIMIT');
    await expectCode(call('adminSettleSupermarketWeights', { orderId, lines: [{ productId: 'milk_1l_1', actualQty: 2 }] }, ADMIN), 'LINE_NOT_WEIGHED');
    const r = await call('adminSettleSupermarketWeights', { orderId, lines: [{ productId: 'beef_lean_1', actualQty: 1.4 }] }, ADMIN);
    assert.deepStrictEqual([r.changed, r.refund, r.total], [true, 20880, 150960]);
    const o = await get(`orders/${orderId}`);
    assert.deepStrictEqual([o.balanceApplied, o.total, o.itemsTotal, o.deliveryFee, o.weighHold, o.smWeighPending, o.items[0].finalTotal, o.smRefundedTotal],
      [150960, 150960, 136000, 14960, 0, false, 112000, 20880]);
    assert.strictEqual(bal0, 500000 - 171840 - 13310); // C5 картошка: 11000 + 1100 + 1210
    assert.strictEqual((await get('users/912000001')).bonusBalance, bal0 + 20880);
    assert.strictEqual((await get('platform_products/beef_lean_1')).stock, 8.6);
    const again = await call('adminSettleSupermarketWeights', { orderId, lines: [{ productId: 'beef_lean_1', actualQty: 1.4 }] }, ADMIN);
    assert.deepStrictEqual([again.changed, again.refund], [false, 0]);
    await expectCode(call('adminSettleSupermarketWeights', { orderId, lines: [{ productId: 'beef_lean_1', actualQty: 1.5 }] }, ADMIN), 'LINE_ALREADY_SETTLED');
    const j = await get(`journal_entries/bonus:sm_adjust_${orderId}_1`);
    assert.deepStrictEqual([j.kind, j.amount], ['sm_adjust_refund', 20880]);
    assert.strictEqual((await audits('supermarket_weigh_settle')).length, 1);
  });

  await check('C8 қаторни олиш: сут (24000 + fee улуши 2640) қайтади, stock +2, мижозга хабар; такрор — идемпотент; охирги қатор рад; сабаб шарт', async () => {
    const before = (await get('users/912000001')).bonusBalance;
    await expectCode(call('adminRemoveSupermarketLine', { orderId, productId: 'milk_1l_1', reason: '' }, ADMIN), 'REASON_REQUIRED');
    const r = await call('adminRemoveSupermarketLine', { orderId, productId: 'milk_1l_1', reason: 'Сут тугади' }, ADMIN);
    // қолди: мол 112000 + fee 12320 = 124320; аввал 150960 → қайтим 26640
    assert.deepStrictEqual([r.changed, r.refund, r.total], [true, 26640, 124320]);
    assert.strictEqual((await get('users/912000001')).bonusBalance, before + 26640);
    assert.strictEqual((await get('platform_products/milk_1l_1')).stock, 5);
    const o = await get(`orders/${orderId}`);
    assert.ok(o.items[1].removed && o.items[1].removed.reason === 'Сут тугади');
    const news = (await db.collection('admin_news').where('targetUserId', '==', USER).get()).docs.map((d) => d.data());
    assert.ok(news.some((n) => n.source === 'supermarket_line_removed' && n.orderId === orderId), JSON.stringify(news));
    const again = await call('adminRemoveSupermarketLine', { orderId, productId: 'milk_1l_1', reason: 'Сут тугади' }, ADMIN);
    assert.deepStrictEqual([again.changed, again.refund], [false, 0]);
    await expectCode(call('adminRemoveSupermarketLine', { orderId, productId: 'beef_lean_1', reason: 'x' }, ADMIN), 'LAST_LINE');
  });

  await check('C9 мавжуд customerCancelOrder: қолган balanceApplied қайтади; trigger stock\'ни БИР МАРТА қайтаради; кейин тортиш рад', async () => {
    const before = (await get('users/912000001')).bonusBalance;
    const ref = db.doc(`orders/${orderId}`);
    const snapBefore = await ref.get();
    await call('customerCancelOrder', { orderId }, USER);
    const o = await get(`orders/${orderId}`);
    assert.ok(['cancelled', 'rejected'].includes(o.status) || o.fulfillmentStatus === 'cancelled', JSON.stringify([o.status, o.fulfillmentStatus]));
    assert.strictEqual((await get('users/912000001')).bonusBalance, before + 124320);
    const snapAfter = await ref.get();
    await fns.onSupermarketOrderCancelStock.run({ before: snapBefore, after: snapAfter }, { params: { orderId } });
    assert.strictEqual((await get('platform_products/beef_lean_1')).stock, 10); // 8.6 + 1.4
    assert.strictEqual((await get('platform_products/milk_1l_1')).stock, 5); // олинган қатор — қайта қўшилмайди
    await fns.onSupermarketOrderCancelStock.run({ before: snapBefore, after: await ref.get() }, { params: { orderId } });
    assert.strictEqual((await get('platform_products/beef_lean_1')).stock, 10);
    await expectCode(call('adminRemoveSupermarketLine', { orderId, productId: 'beef_lean_1', reason: 'x' }, ADMIN), 'ORDER_STATE_LOCKED');
  });

  await check('C10 stock 0 → out_of_stock (авто); бекорда қайта active (авто белги ўчади)', async () => {
    const r = await call('placeSupermarketOrder', order('req-zero-00001', [{ productId: 'milk_1l_1', qty: 5 }]), USER);
    const p = await get('platform_products/milk_1l_1');
    assert.deepStrictEqual([p.stock, p.smStatus, p.smAutoOutOfStock], [0, 'out_of_stock', true]);
    await expectCode(call('placeSupermarketOrder', order('req-zero-00002', [{ productId: 'milk_1l_1', qty: 1 }]), USER), 'OUT_OF_STOCK');
    const ref = db.doc(`orders/${r.orderId}`);
    const b = await ref.get();
    await call('customerCancelOrder', { orderId: r.orderId }, USER);
    await fns.onSupermarketOrderCancelStock.run({ before: b, after: await ref.get() }, { params: { orderId: r.orderId } });
    const p2 = await get('platform_products/milk_1l_1');
    assert.deepStrictEqual([p2.stock, p2.smStatus, p2.smAutoOutOfStock], [5, 'active', false]);
  });

  await check('C11 тортилмаган қаторни олиш — унинг 10% ушлаши ҳам қайтади (картошка 3 кг + мол 1 кг)', async () => {
    const r = await call('placeSupermarketOrder', order('req-mix-000001', [{ productId: 'potato_1', qty: 3 }, { productId: 'beef_lean_1', qty: 1 }]), USER);
    // goods 16500 + 80000 = 96500; extras 1650 + 8000 = 9650; fee 10615 → 116765
    assert.strictEqual(r.total, 116765);
    const rm = await call('adminRemoveSupermarketLine', { orderId: r.orderId, productId: 'potato_1', reason: 'Йўқ' }, ADMIN);
    // қолди: 80000 + 8000 + 8800 = 96800 → қайтим 19965
    assert.deepStrictEqual([rm.refund, rm.total], [19965, 96800]);
  });

  await check('C12 dispatcher тортади/олади (аудитда роль); ҳамён изоҳи калит + 3 тил; packQty/packUnit сақланади', async () => {
    await call('adminUpsertSupermarketOffer', { productId: 'water_15_1', offer: { smGroupId: 'drinking_water', smVariety: variety('still', 'Газсиз', 'Gazsiz', 'Без газа'), packLabel: '1.5 л', packQty: 1.5, packUnit: 'l', stock: 50, smStatus: 'active', price: 4500 } }, ADMIN);
    const w = await get('platform_products/water_15_1');
    assert.deepStrictEqual([w.packQty, w.packUnit], [1.5, 'l']);
    await assert.rejects(call('adminUpsertSupermarketOffer', { productId: 'water_15_2', offer: { smGroupId: 'drinking_water', smVariety: variety('still', 'Газсиз', 'Gazsiz', 'Без газа'), stock: 1, smStatus: 'active', price: 1 } }, DISP), (e) => e.code === 'permission-denied');
    const r = await call('placeSupermarketOrder', order('req-disp-00001', [{ productId: 'beef_lean_1', qty: 1 }, { productId: 'water_15_1', qty: 2 }]), USER);
    const s = await call('adminSettleSupermarketWeights', { orderId: r.orderId, lines: [{ productId: 'beef_lean_1', actualQty: 0.9 }] }, DISP);
    assert.ok(s.refund > 0);
    const a = (await audits('supermarket_weigh_settle')).find((x) => x.target === `orders/${r.orderId}`);
    assert.deepStrictEqual([a.actor, a.actorRole], [DISP, 'dispatcher']);
    const rm = await call('adminRemoveSupermarketLine', { orderId: r.orderId, productId: 'water_15_1', reason: 'Тугади' }, DISP);
    assert.ok(rm.refund > 0);
    assert.strictEqual((await audits('supermarket_line_remove')).find((x) => x.target === `orders/${r.orderId}`).actorRole, 'dispatcher');
    const wl = (await db.collection('users/912000001/wallet_ledger').where('refId', '==', r.orderId).get()).docs.map((d) => d.data()).filter((d) => d.type === 'order_partial_refund');
    assert.deepStrictEqual(wl.map((d) => d.meta.noteKey).sort(), ['sm_refund_line_removed', 'sm_refund_weigh']);
    for (const d of wl) assert.ok(d.meta.messages.uz_Latn && d.meta.messages.ru && d.meta.note === d.meta.messages.uz_Cyrl);
    assert.strictEqual((await get(`journal_entries/bonus:sm_adjust_${r.orderId}_1`)).postedRole, 'dispatcher');
  });

  await check('C13 сана (эга 2026-11-28): совға/байрам — deliveryDate +2 кун, оралиқсиз (scheduled); эски клиент slotId — аввалгидек', async () => {
    await db.doc('platform_products/potato_1').update({ stock: 100 });
    await db.doc('users/912000001').update({ bonusBalance: 500000 });
    const plus2 = new Date(Date.now() + 5 * 3600000 + 2 * 86400000).toISOString().slice(0, 10);
    const r = await call('placeSupermarketOrder', order('req-sched-0001', [{ productId: 'potato_1', qty: 1 }], { deliveryDate: plus2, origin: 'holiday' }), USER);
    const o = await get(`orders/${r.orderId}`);
    assert.deepStrictEqual([o.slot.id, o.slot.day, o.slot.asap, o.slot.date, o.deliveryDate, r.asap], ['date', 'scheduled', false, plus2, plus2, false]);
    const l = await call('placeSupermarketOrder', legacyOrder('req-legacy-001', [{ productId: 'potato_1', qty: 1 }]), USER);
    const lo = await get(`orders/${l.orderId}`);
    assert.deepStrictEqual([lo.slot.id, lo.slot.day, lo.slot.startMin], ['morning', 'tomorrow', 600]);
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
