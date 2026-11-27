/**
 * «AVA Супермаркет» 2-босқич — callable/trigger/scheduler, ҲАҚИҚИЙ `functions/index.js`, Firestore Emulator.
 * Импорт — ҳақиқий модуль, Storage/расм — сохта (DI), Firestore — эмулятор.
 *
 *   firebase emulators:exec --only firestore --project demo-supermarket2 "node test/supermarket_stage2_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-supermarket2';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const functions = require('firebase-functions');
const ExcelJS = require('exceljs');
const { attachSupermarket } = require('../supermarket');
const SI = require('../supermarket_import');
const SM = require('../supermarket');
const { USER_SUBCOLLECTIONS } = require('../account_deletion');
const TAX2 = require('../tools/data/supermarket_taxonomy_v2.json');
const SETTINGS = require('../tools/data/supermarket_settings_v1.json');

const db = admin.firestore();
const ADMIN = '998915000001';
const USER = '998912000001'; // users/912000001 (эски 9 хонали ҳужжат)
const OTHER = '998912000003';
const DISP = '998915000004';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, who ? ctxOf(who) : {});

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
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
const news = async (source) => (await db.collection('admin_news').where('source', '==', source).get()).docs.map((d) => d.data());
const bal = async () => (await get('users/912000001')).bonusBalance;
const stock = async (id) => (await get(`platform_products/${id}`)).stock;
const variety = (id, c, l, r) => ({ id, names: { uz_Cyrl: c, uz_Latn: l, ru: r } });
const ADDR = { districtId: 'gurlan', mahalla: 'Navoiy', street: 'Mustaqillik', house: '12', phone: '901234567' };
let rq = 0;
const rid = (p = 'req') => `${p}-${String(++rq).padStart(8, '0')}`;
const place = (items) => call('placeSupermarketOrder', { clientRequestId: rid('ord'), items, address: ADDR, slotId: 'morning', day: 'tomorrow' }, USER);
const report = (orderId, productId, availableQty, substitutes, who = DISP) => call('adminReportSupermarketShortage', { orderId, productId, availableQty, substitutes }, who);
const respond = (orderId, productId, choice, extra = {}, who = USER) => call('respondSupermarketShortage', { orderId, productId, choice, clientRequestId: rid('sh'), ...extra }, who);

// ── импорт: маҳаллий attach (сохта Storage/расм), ролни users ҳужжатидан ──
const files = new Map();
let imageCalls = [];
const fakeStore = {
  async saveFile(p, buf) { files.set(p, Buffer.from(buf)); },
  async readFile(p) { if (!files.has(p)) throw new Error('nf'); return files.get(p); },
  async saveImage(p) { files.set(p, Buffer.from('jpg')); return `https://firebasestorage.googleapis.com/v0/b/demo/o/${encodeURIComponent(p)}?alt=media&token=t`; },
  async deleteByUrl() { return true; },
};
const HttpsError = functions.https.HttpsError;
const requireCallerRoles = async (context, roles) => {
  if (!context || !context.auth) throw new HttpsError('unauthenticated', 'x');
  const p = String(context.auth.token.phone_number || '').replace(/\D/g, '');
  const s = await db.doc(`users/${p}`).get();
  if (!roles.includes((s.data() || {}).role)) throw new HttpsError('permission-denied', 'x');
  return p;
};
const localSm = {};
const smApi = attachSupermarket(localSm, {
  functions, db, admin, requireCallerRoles, settlementLedger: {}, notifyUserInApp: async () => {},
  callerPhone: (c) => String(c.auth.token.phone_number || '').replace(/\D/g, ''),
  canonicalUid: (v) => { const d = String(v).replace(/\D/g, ''); return d.length === 9 ? `998${d}` : d; },
});
const imp = {};
SI.attachSupermarketImport(imp, {
  functions, db, admin, smApi, fileStore: fakeStore,
  processImage: async (url) => { imageCalls.push(url); return Buffer.from('jpeg'); },
});
const icall = (name, data, who) => imp[name].run(data, ctxOf(who));
async function xlsxB64(rows) {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet('Products');
  ws.addRow(SI.COLUMNS.map(SI.headerText));
  for (const r of rows) ws.addRow(SI.COLUMNS.map((c) => (r[c.key] === undefined ? null : r[c.key])));
  return Buffer.from(await wb.xlsx.writeBuffer()).toString('base64');
}

async function main() {
  await clearEmulator();
  await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
  await db.doc(`users/${DISP}`).set({ role: 'dispatcher' });
  await db.doc('users/912000001').set({ role: 'user', name: 'Ali', bonusBalance: 1000000, districtId: 'gurlan', appLang: 'uz_Latn' });
  await db.doc(`users/${OTHER}`).set({ role: 'user', bonusBalance: 500000, districtId: 'gurlan' });
  await db.doc('settings/app').set({ platformDeliveryFeePercent: 11, platformDeliveryFeeVersion: 2 });

  await check('K1 таксономия v2 (pairs) callable орқали; нотўғри pair — TAXONOMY_INVALID', async () => {
    const bad = JSON.parse(JSON.stringify(TAX2)); bad.categories[0].groups[0].pairs = ['caviar'];
    const e = await expectCode(call('adminSetSupermarketTaxonomy', { taxonomy: bad, expectedVersion: 0 }, ADMIN), 'TAXONOMY_INVALID');
    assert.ok(e.details.errors.includes('PAIR_UNKNOWN categories[0].groups[0].pairs[0]'));
    const r = await call('adminSetSupermarketTaxonomy', { taxonomy: TAX2, expectedVersion: 0 }, ADMIN);
    assert.strictEqual(r.version, 1);
    assert.deepStrictEqual((await get('taxonomy/supermarket')).categories[0].groups[0].pairs, ['onion', 'carrot', 'rice', 'cottonseed_oil']);
    await call('adminSetSupermarketSettings', { settings: { ...SETTINGS, testerIds: [USER, OTHER] }, expectedVersion: 0 }, ADMIN);
    const up = (productId, offer) => call('adminUpsertSupermarketOffer', { productId, offer }, ADMIN);
    await up('beef_lean_1', { smGroupId: 'beef', smVariety: variety('lean', 'Лаҳм', 'Lahm', 'Постная'), stock: 20, smStatus: 'active', price: 80000 });
    await up('milk_1l_1', { smGroupId: 'milk', smVariety: variety('cow', 'Сигир', 'Sigir', 'Коровье'), stock: 10, smStatus: 'active', price: 12000 });
    await up('kefir_1l_1', { smGroupId: 'kefir', smVariety: variety('cow', 'Сигир', 'Sigir', 'Коровье'), stock: 5, smStatus: 'active', price: 15000 });
    await up('ayran_1l_1', { smGroupId: 'katyk', smVariety: variety('ayran', 'Айрон', 'Ayron', 'Айран'), stock: 3, smStatus: 'active', price: 9000 });
  });

  let o1;
  await check('K2 етишмовчилик хабари: мижоз/аноним рад; dispatcher — қатор shortage, пул ўзгармайди, мижозга хабар (ўз тилида), аудит; такрор — changed:false; хато сўровлар', async () => {
    o1 = (await place([{ productId: 'beef_lean_1', qty: 1.5 }, { productId: 'milk_1l_1', qty: 2 }])).orderId;
    assert.strictEqual((await get(`orders/${o1}`)).balanceApplied, 171840);
    await assert.rejects(report(o1, 'milk_1l_1', 1, [], USER), (e) => e.code === 'permission-denied');
    await assert.rejects(report(o1, 'milk_1l_1', 1, [], null), (e) => e.code === 'unauthenticated');
    await expectCode(report(o1, 'milk_1l_1', 1, ['beef_lean_1']), 'SUBSTITUTE_INVALID');
    await expectCode(report(o1, 'milk_1l_1', 1, ['a_000001', 'b_000001', 'c_000001', 'd_000001']), 'INVALID_REQUEST');
    await expectCode(report(o1, 'milk_1l_1', 2, []), 'AVAILABLE_QTY_INVALID');
    const r = await report(o1, 'milk_1l_1', 1, ['kefir_1l_1', 'ayran_1l_1']);
    assert.deepStrictEqual([r.changed, r.answerWithinMin], [true, 30]);
    const o = await get(`orders/${o1}`);
    assert.deepStrictEqual([o.items[1].shortage.state, o.items[1].shortage.substitutes.length, o.smShortagePending, o.balanceApplied], ['pending', 2, true, 171840]);
    const n = await news('supermarket_shortage');
    assert.strictEqual(n.length, 1);
    assert.ok(n[0].title.startsWith('Buyurtmada') && n[0].body.includes('«Сут Сигир»') && n[0].body.includes('30 daqiqa') && n[0].orderId === o1 && n[0].productId === 'milk_1l_1', JSON.stringify(n[0]));
    const a = (await audits('supermarket_shortage_report'))[0];
    assert.deepStrictEqual([a.actorRole, a.refund, a.debit, a.chargedAfter], ['dispatcher', 0, 0, 171840]);
    const again = await report(o1, 'milk_1l_1', 1, ['kefir_1l_1', 'ayran_1l_1']);
    assert.strictEqual(again.changed, false);
    assert.strictEqual((await news('supermarket_shortage')).length, 1, 'такрор — хабар йўқ');
  });

  await check('K3 жавоб: бошқа мижоз PERMISSION_DENIED; нотўғри choice/қадам; маблағ етмаса INSUFFICIENT_FUNDS (3 тил, ҳеч нарса ўзгармайди)', async () => {
    await expectCode(respond(o1, 'milk_1l_1', 'remove', {}, OTHER), 'PERMISSION_DENIED');
    await expectCode(respond(o1, 'milk_1l_1', 'swap'), 'INVALID_REQUEST');
    await expectCode(respond(o1, 'milk_1l_1', 'substitute'), 'INVALID_REQUEST');
    await expectCode(respond(o1, 'milk_1l_1', 'remove', { qty: 1 }), 'INVALID_REQUEST');
    await expectCode(respond(o1, 'milk_1l_1', 'substitute', { offerId: 'kefir_1l_1', qty: 1.5 }), 'QTY_STEP_INVALID');
    await db.doc('users/912000001').update({ bonusBalance: 6659 });
    const e = await expectCode(respond(o1, 'milk_1l_1', 'substitute', { offerId: 'kefir_1l_1' }), 'INSUFFICIENT_FUNDS');
    assert.deepStrictEqual([e.details.required, e.details.balance], [6660, 6659]);
    assert.ok(e.details.messages.uz_Latn.includes('hamyon') && e.details.messages.ru);
    const o = await get(`orders/${o1}`);
    assert.deepStrictEqual([o.items[1].productId, o.items[1].shortage.state, o.balanceApplied, await stock('kefir_1l_1'), await bal()], ['milk_1l_1', 'pending', 171840, 5, 6659]);
  });

  await check('K4 қимматроқ алмаштириш (баланс етарли, чегара 6660): фарқ ечилади, stock, ledger/journal, идемпотент такрор, иккинчи жавоб рад', async () => {
    await db.doc('users/912000001').update({ bonusBalance: 6660 });
    const clientRequestId = rid('sh');
    const r = await call('respondSupermarketShortage', { orderId: o1, productId: 'milk_1l_1', choice: 'substitute', offerId: 'kefir_1l_1', clientRequestId }, USER);
    assert.deepStrictEqual([r.debit, r.refund, r.total], [6660, 0, 178500]);
    assert.strictEqual(await bal(), 0);
    const o = await get(`orders/${o1}`);
    assert.deepStrictEqual([o.items[1].productId, o.items[1].total, o.items[1].substitutedFrom.productId, o.balanceApplied, o.total, o.smExtraChargedTotal, o.smShortagePending],
      ['kefir_1l_1', 30000, 'milk_1l_1', 178500, 178500, 6660, false]);
    assert.deepStrictEqual([await stock('kefir_1l_1'), await stock('milk_1l_1')], [3, 10]);
    const wl = (await db.collection('users/912000001/wallet_ledger').where('refId', '==', o1).get()).docs.map((d) => d.data()).find((d) => d.meta && d.meta.noteKey === 'sm_debit_substitute');
    assert.deepStrictEqual([wl.type, wl.amount, wl.createdBy], ['purchase_debit', -6660, 'respondSupermarketShortage']);
    assert.ok(wl.meta.messages.uz_Latn && wl.meta.messages.ru);
    const j = await get(`journal_entries/bonus:sm_adjust_${o1}_2`);
    assert.deepStrictEqual([j.kind, j.postedRole], ['sm_adjust_debit', 'client']);
    const dup = await call('respondSupermarketShortage', { orderId: o1, productId: 'milk_1l_1', choice: 'substitute', offerId: 'kefir_1l_1', clientRequestId }, USER);
    assert.deepStrictEqual([dup.duplicate, dup.debit], [true, 6660]);
    assert.strictEqual(await bal(), 0, 'такрор — иккинчи ечим йўқ');
    await expectCode(respond(o1, 'milk_1l_1', 'remove'), 'LINE_SHORTAGE_RESOLVED');
    await db.doc('users/912000001').update({ bonusBalance: 1000000 });
    // мавжуд бекор қилиш — ҳамма ечилган (қўшимча ҳам) қайтади
    await call('customerCancelOrder', { orderId: o1 }, USER);
    assert.strictEqual(await bal(), 1000000 + 178500);
    await db.doc('users/912000001').update({ bonusBalance: 1000000 });
  });

  await check('K5 арзонроқ алмаштириш: қайтим 3330 (айрон 1 л)', async () => {
    const o = (await place([{ productId: 'beef_lean_1', qty: 1 }, { productId: 'milk_1l_1', qty: 1 }])).orderId;
    await report(o, 'milk_1l_1', 0, ['ayran_1l_1']);
    const r = await respond(o, 'milk_1l_1', 'substitute', { offerId: 'ayran_1l_1' });
    assert.deepStrictEqual([r.refund, r.debit, r.total], [3330, 0, 106790]);
    assert.strictEqual(await bal(), 1000000 - 110120 + 3330);
    const wl = (await db.collection('users/912000001/wallet_ledger').where('refId', '==', o).get()).docs.map((d) => d.data()).find((d) => d.type === 'order_partial_refund');
    assert.strictEqual(wl.meta.noteKey, 'sm_refund_substitute');
  });

  await check('K6 камайтириш (3→1 л): қайтим 26640; K7 олиб ташлаш: қайтим 13320 + stock', async () => {
    const before = await bal();
    const o = (await place([{ productId: 'milk_1l_1', qty: 3 }, { productId: 'beef_lean_1', qty: 1 }])).orderId;
    await report(o, 'milk_1l_1', 1, []);
    const r = await respond(o, 'milk_1l_1', 'reduce');
    assert.deepStrictEqual([r.refund, r.total], [26640, 110120]);
    assert.strictEqual(await bal(), before - 136760 + 26640);
    const m0 = await stock('milk_1l_1');
    const o2 = (await place([{ productId: 'milk_1l_1', qty: 1 }, { productId: 'beef_lean_1', qty: 1 }])).orderId;
    await report(o2, 'milk_1l_1', 0, []);
    await expectCode(respond(o2, 'milk_1l_1', 'reduce'), 'QTY_STEP_INVALID');
    const rm = await respond(o2, 'milk_1l_1', 'remove');
    assert.deepStrictEqual([rm.refund, rm.total], [13320, 96800]);
    assert.strictEqual(await stock('milk_1l_1'), m0, 'олинган қатор омборга қайтди');
    assert.strictEqual((await get(`orders/${o2}`)).items[0].removed.reason, 'shortage');
  });

  await check('K8 30 дақиқадан кейин: админ мавжуд adminRemoveSupermarketLine билан олади — shortage.state admin_removed', async () => {
    const o = (await place([{ productId: 'milk_1l_1', qty: 1 }, { productId: 'beef_lean_1', qty: 1 }])).orderId;
    await report(o, 'milk_1l_1', 0, []);
    const rm = await call('adminRemoveSupermarketLine', { orderId: o, productId: 'milk_1l_1', reason: 'Жавоб йўқ' }, ADMIN);
    assert.strictEqual(rm.refund, 13320);
    const od = await get(`orders/${o}`);
    assert.deepStrictEqual([od.items[0].shortage.state, od.smShortagePending], ['admin_removed', false]);
    await expectCode(respond(o, 'milk_1l_1', 'remove'), 'LINE_SHORTAGE_RESOLVED');
  });

  const listRef = db.doc('users/912000001/sm_lists/weekly1');
  const runTrigger = async () => { const s = await listRef.get(); await fns.onSmListWrite.run({ before: s, after: s }, { params: { userId: '912000001', listId: 'weekly1' } }); return get(listRef.path); };
  await check('K9 onSmListWrite: remindNextAt сервер ҳисоблайди (келажак, Тошкент), такрор — ўзгармайди; бузуқ қатор — smInvalid, эслатма йўқ; ўчирилса — remindNextAt ўчади', async () => {
    const base = { name: 'Ҳафталик', items: [{ groupId: 'beef', qty: 1 }, { groupId: 'milk', offerId: 'milk_1l_1', qty: 2 }], remind: { enabled: true, weekday: 6, minute: 600 }, createdAt: new Date(), updatedAt: new Date() };
    await listRef.set(base);
    const a = await runTrigger();
    const next = a.remindNextAt.toMillis();
    assert.ok(next > Date.now() && next - Date.now() <= 7 * 86400000, String(next));
    assert.strictEqual(new Date(next + 5 * 3600000).getUTCDay(), 6);
    assert.strictEqual(new Date(next + 5 * 3600000).getUTCHours(), 10);
    assert.strictEqual(a.remindKey, '6:600');
    const b = await runTrigger();
    assert.strictEqual(b.remindNextAt.toMillis(), next);
    await listRef.update({ items: [{ groupId: 'beef', qty: 0 }] });
    const c = await runTrigger();
    assert.deepStrictEqual([c.smInvalid, c.remindNextAt, c.remindKey], ['ITEM_INVALID', undefined, undefined]);
    await listRef.update({ items: base.items, remind: { enabled: false, weekday: 6, minute: 600 } });
    const d = await runTrigger();
    assert.deepStrictEqual([d.smInvalid, d.remindNextAt], [undefined, undefined]);
    await listRef.update({ remind: base.remind });
    assert.ok((await runTrigger()).remindNextAt);
  });

  await check('K10 smWeeklyReminder: муддати етган рўйхат → хабар (ўз тилида, 3 тил матни), +7 кун; такрор — хабар йўқ; буюртма/ечим ЙЎҚ; босқич off — юборилмайди, лекин олдинга суради', async () => {
    const ordersBefore = (await db.collection('orders').get()).size;
    const balBefore = await bal();
    const due = Date.now() - 60000;
    await listRef.update({ remindNextAt: admin.firestore.Timestamp.fromMillis(due) });
    await fns.smWeeklyReminder.run({});
    const n = await news('sm_weekly_reminder');
    assert.strictEqual(n.length, 1);
    assert.deepStrictEqual([n[0].targetUserId, n[0].smListId, n[0].title], [USER, 'weekly1', 'AVA Supermarket']);
    assert.ok(n[0].body.includes('haftalik savatingiz tayyor'));
    const l = await get(listRef.path);
    assert.strictEqual(l.remindNextAt.toMillis(), due + 7 * 86400000);
    assert.ok(l.remindLastSentAt);
    await fns.smWeeklyReminder.run({});
    assert.strictEqual((await news('sm_weekly_reminder')).length, 1);
    assert.strictEqual((await db.collection('orders').get()).size, ordersBefore);
    assert.strictEqual(await bal(), balBefore);
    // Эга 2026-11-28: ёпиқлик — модул созламаси (settings stage эмас).
    await db.doc('config/module_defaults').set({ enforce: true, modules: { supermarket: 'hidden' } });
    require('../module_gate').resetCache();
    await listRef.update({ remindNextAt: admin.firestore.Timestamp.fromMillis(due) });
    await fns.smWeeklyReminder.run({});
    assert.strictEqual((await news('sm_weekly_reminder')).length, 1);
    assert.strictEqual((await get(listRef.path)).remindNextAt.toMillis(), due + 7 * 86400000);
    await db.doc('config/module_defaults').delete();
    require('../module_gate').resetCache();
    assert.ok(USER_SUBCOLLECTIONS.includes('sm_lists'), 'ҳисоб ўчирилганда рўйхатлар ҳам ўчади');
  });

  // ── Excel импорт ──
  const IMG1 = 'https://cdn.example.com/potato.jpg';
  const rowsA = [
    { sku: 'potato_local_1', categoryId: 'vegetables', groupId: 'potato', variety_uz_Cyrl: 'Маҳаллий', variety_uz_Latn: 'Mahalliy', variety_ru: 'Местный', price: 5000, stock: 100, purchasePrice: 3500, supplier: 'Фермер', imageUrl: IMG1 },
    { sku: 'onion_1', groupId: 'onion', price: 4000, stock: 50 },
    { sku: 'water_15_1', groupId: 'drinking_water', packLabel: '1.5 л', packQty: 1.5, packUnit: 'l', price: 4500, stock: 40 },
    { sku: 'caviar_01', groupId: 'caviar', price: 1, stock: 1 },
    { sku: 'legacy_01', groupId: 'beef', price: 1, stock: 1 },
    { sku: 'dup_000001', groupId: 'beef', price: 1, stock: 1 },
    { sku: 'dup_000001', groupId: 'beef', price: 2, stock: 1 },
  ];
  let batchA;
  await check('I1 шаблон/preview: фақат админ; preview ҳеч нарса ёзмайди; хатолар (GROUP_UNKNOWN, SKU_NOT_SUPERMARKET, SKU_DUPLICATE); такрор preview — duplicate', async () => {
    await db.doc('platform_products/legacy_01').set({ name: 'Эски', price: 1000, active: true });
    await assert.rejects(icall('adminSupermarketImportTemplate', {}, DISP), (e) => e.code === 'permission-denied');
    const tpl = await icall('adminSupermarketImportTemplate', {}, ADMIN);
    assert.ok(tpl.base64.length > 1000 && tpl.fileName.endsWith('.xlsx'));
    const fileBase64 = await xlsxB64(rowsA);
    await assert.rejects(icall('adminSupermarketImportPreview', { fileBase64, clientRequestId: 'imp-a-000001' }, USER), (e) => e.code === 'permission-denied');
    const p = await icall('adminSupermarketImportPreview', { fileName: 'a.xlsx', fileBase64, clientRequestId: 'imp-a-000001' }, ADMIN);
    batchA = p.batchId;
    assert.deepStrictEqual(p.counts, { total: 7, ready: 3, errors: 4, create: 3, update: 0 });
    assert.deepStrictEqual(p.rows.map((r) => r.errors.join(',')), ['', '', '', 'GROUP_UNKNOWN', 'SKU_NOT_SUPERMARKET', 'SKU_DUPLICATE', 'SKU_DUPLICATE']);
    assert.strictEqual((await db.doc('platform_products/potato_local_1').get()).exists, false);
    const again = await icall('adminSupermarketImportPreview', { fileBase64, clientRequestId: 'imp-a-000001' }, ADMIN);
    assert.deepStrictEqual([again.duplicate, again.batchId], [true, batchA]);
  });

  await check('I2 confirm: 3 яратилди (upsertOfferTx — бир йўл), нарх аудити source import, харид нархи private/cost, расм бир марта; legacy тегилмади; такрор confirm — duplicate', async () => {
    await assert.rejects(icall('adminSupermarketImportConfirm', { batchId: batchA }, DISP), (e) => e.code === 'permission-denied');
    const c = await icall('adminSupermarketImportConfirm', { batchId: batchA }, ADMIN);
    assert.deepStrictEqual([c.status, c.counts.created, c.counts.error, c.counts.pending], ['done', 3, 4, 0]);
    const p = await get('platform_products/potato_local_1');
    assert.deepStrictEqual([p.smGroupId, p.smCategoryId, p.price, p.stock, p.smStatus, p.active, p.smImageSrc, p.smImportBatchId, p.smVariety.names.ru], ['potato', 'vegetables', 5000, 100, 'active', false, IMG1, batchA, 'Местный']);
    assert.ok(p.imageUrl.startsWith('https://firebasestorage.googleapis.com/') && p.searchTokens.includes('картошка'));
    assert.strictEqual((await get('platform_products/potato_local_1/private/cost')).purchasePrice, 3500);
    assert.deepStrictEqual([(await get('platform_products/water_15_1')).packQty, (await get('platform_products/onion_1')).unit], [1.5, 'kg']);
    const pa = (await audits('supermarket_offer_price')).filter((a) => a.source === 'import');
    assert.strictEqual(pa.length, 3);
    assert.strictEqual(pa[0].batchId, batchA);
    assert.strictEqual(imageCalls.length, 1);
    assert.strictEqual((await get('platform_products/legacy_01')).smGroupId, undefined);
    assert.strictEqual((await audits('supermarket_import')).length, 1);
    const again = await icall('adminSupermarketImportConfirm', { batchId: batchA }, ADMIN);
    assert.strictEqual(again.duplicate, true);
  });

  await check('I3 қайта юклаш (SKU бўйича идемпотент): ўзгармаган — unchanged (аудитсиз, расм қайта юкланмайди); нарх ўзгарса — updated + аудит old/new', async () => {
    const rows = rowsA.slice(0, 3);
    rows[1] = { ...rows[1], price: 4200 };
    const p = await icall('adminSupermarketImportPreview', { fileBase64: await xlsxB64(rows), clientRequestId: 'imp-b-000001' }, ADMIN);
    assert.deepStrictEqual([p.counts.update, p.counts.create], [3, 0]);
    const before = (await audits('supermarket_offer_price')).length;
    const c = await icall('adminSupermarketImportConfirm', { batchId: p.batchId }, ADMIN);
    assert.deepStrictEqual([c.counts.unchanged, c.counts.updated], [2, 1]);
    const pa = await audits('supermarket_offer_price');
    assert.strictEqual(pa.length, before + 1);
    assert.ok(pa.some((a) => a.target === 'platform_products/onion_1' && a.oldPrice === 4000 && a.newPrice === 4200));
    assert.strictEqual(imageCalls.length, 1, 'расм кеши');
    assert.strictEqual((await get('platform_products/onion_1')).price, 4200);
  });

  await check('I4 чегара: 500 қатор — preview OK; 501 — TOO_MANY_ROWS; файл эмас — FILE_NOT_XLSX', async () => {
    const many = (n) => Array.from({ length: n }, (_, i) => ({ sku: `bulk_${String(i).padStart(4, '0')}`, groupId: 'salt', price: 3000, stock: 10 }));
    const p = await icall('adminSupermarketImportPreview', { fileBase64: await xlsxB64(many(500)), clientRequestId: 'imp-c-000001' }, ADMIN);
    assert.deepStrictEqual([p.counts.total, p.counts.ready], [500, 500]);
    await expectCode(icall('adminSupermarketImportPreview', { fileBase64: await xlsxB64(many(501)), clientRequestId: 'imp-d-000001' }, ADMIN), 'TOO_MANY_ROWS');
    await expectCode(icall('adminSupermarketImportPreview', { fileBase64: Buffer.from('hello').toString('base64'), clientRequestId: 'imp-e-000001' }, ADMIN), 'FILE_NOT_XLSX');
  });

  await check('I9 ҳамкор импорти (эга 2026-11-28): фақат тасдиқланган Улгуржи сотувчиси; SKU ўз калитига (ps_…), харид нархи эътиборсиз, модерация pending → hidden; бегона партия/SKU — рад', async () => {
    const PA = '998913000011';
    await db.doc(`wholesale_sellers/${PA}`).set({ approvalStatus: 'approved', companyName: 'Ферма', districtId: 'gurlan' });
    const rowsP = [
      { sku: 'p-onion-1', groupId: 'onion', price: 4100, stock: 30, purchasePrice: 999, supplier: 'x' },
      { sku: 'potato_local_1', groupId: 'potato', price: 1, stock: 1 },
    ];
    const fileBase64 = await xlsxB64(rowsP);
    await assert.rejects(icall('partnerSupermarketImportPreview', { fileBase64, clientRequestId: 'pimp-000001' }, USER), (e) => e.details && e.details.code === 'PARTNER_NOT_APPROVED');
    const pv = await icall('partnerSupermarketImportPreview', { fileName: 'p.xlsx', fileBase64, clientRequestId: 'pimp-000001' }, PA);
    assert.deepStrictEqual([pv.counts.create, pv.counts.errors], [2, 0], 'potato_local_1 — бошқа (ps_) ID, админникига тегмайди');
    await assert.rejects(icall('adminSupermarketImportConfirm', { batchId: pv.batchId }, ADMIN), (e) => e.code === 'not-found');
    const c = await icall('partnerSupermarketImportConfirm', { batchId: pv.batchId }, PA);
    assert.deepStrictEqual([c.status, c.counts.created], ['done', 2]);
    const key = SM.partnerKeyOf(PA);
    const d = await get(`platform_products/ps_${key}_p-onion-1`);
    assert.deepStrictEqual([d.smPartnerKey, d.smModeration, d.smStatus, d.smPartnerStatus, d.price], [key, 'pending', 'hidden', 'active', 4100]);
    assert.strictEqual((await db.doc(`platform_products/ps_${key}_p-onion-1/private/cost`).get()).exists, false, 'ҳамкор харид нархи ёзилмайди');
    assert.strictEqual((await get('platform_products/potato_local_1')).price, 5000, 'админ таклифи ўзгармади');
  });
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
