/**
 * `tools/food_cleanup.js` — «Овқат» маълумотини тозалаш (2026-10-11).
 * Firestore Emulator, Admin SDK:
 *   firebase emulators:exec --only firestore --project demo-food-cleanup \
 *     "node functions/test/food_cleanup_tool.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-food-cleanup';

const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const tool = require('../tools/food_cleanup');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
const quiet = { log: () => {} };
const exists = async (p) => (await db.doc(p).get()).exists;

async function wipeAll() {
  for (const col of ['orders', 'admin_news', 'food_catalog', 'food_inventory', 'search_index', 'journal_entries']) {
    const docs = await db.collection(col).listDocuments();
    for (const d of docs) await db.recursiveDelete(d);
  }
}

async function seed() {
  const ts = admin.firestore.Timestamp.fromMillis(1760000000000);
  await db.doc('orders/f_done').set({ type: 'food', status: 'delivered', total: 30000, createdAt: ts, balanceApplied: 10000 });
  await db.doc('orders/f_done/payment_lines/l1').set({ amount: 20000, kind: 'cash', at: ts });
  await db.doc('orders/f_pos').set({ type: 'food', status: 'delivered', fulfillmentMode: 'pos', total: 15000 });
  await db.doc('orders/f_open').set({ type: 'food', status: 'new', balanceApplied: 5000, total: 5000 });
  await db.doc('orders/b1').set({ type: 'bread', status: 'new', total: 8000 });
  await db.doc('admin_news/n_food').set({ category: 'order', orderType: 'food', orderId: 'f_done' });
  await db.doc('admin_news/n_bread').set({ category: 'order', orderType: 'bread', orderId: 'b1' });
  await db.doc('food_catalog/food_1').set({ name: 'Osh', price: 45000, loc: new admin.firestore.GeoPoint(41.8, 60.4) });
  await db.doc('food_catalog/food_2').set({ name: 'Shashlik', price: 85000 });
  await db.doc('food_inventory/food_1').set({ totalStock: 10, soldToday: 2 });
  await db.doc('search_index/food_product_food_1').set({ type: 'food_product', sourceId: 'food_1' });
  await db.doc('search_index/service_food').set({ type: 'service', sourceId: 'food' });
  await db.doc('search_index/service_bread').set({ type: 'service', sourceId: 'bread' });
  await db.doc('journal_entries/j1').set({ refType: 'order', refId: 'f_done', legs: [] });
}

(async () => {
  await wipeAll();
  await seed();

  let plan = await tool.planCleanup(db);
  await check('T1 reja: faqat food hujjatlari; ochiq 1, POS 1, journal saqlanadi', async () => {
    assert.deepStrictEqual(plan.counts, { orders: 3, adminNews: 1, foodCatalog: 2, foodInventory: 1, searchIndex: 2 });
    assert.strictEqual(plan.orders.active.length, 1);
    assert.strictEqual(plan.orders.active[0].id, 'f_open');
    assert.strictEqual(plan.orders.pos, 1);
    assert.strictEqual(plan.keptJournalRefs, 1);
    assert.ok(!plan.paths.includes('orders/b1'));
    assert.ok(!plan.paths.includes('search_index/service_bread'));
    assert.ok(!plan.paths.some((p) => p.startsWith('journal_entries/')));
  });

  await check('T2 ochiq buyurtma bor — apply RAD, hech narsa o\'chmaydi', async () => {
    const backup = await tool.backupCleanup(db, plan);
    await assert.rejects(tool.applyCleanup(db, plan, backup, quiet), (e) => e.code === 'ACTIVE_FOOD_ORDERS');
    assert.ok(await exists('orders/f_done'));
    assert.ok(await exists('food_catalog/food_1'));
  });

  // Adminda bekor qilindi (hamyon qaytimi oddiy yo'l bilan).
  await db.doc('orders/f_open').update({ status: 'cancelled' });
  const staleBackup = await tool.backupCleanup(db, plan);
  await db.doc('food_catalog/food_3').set({ name: 'Yangi' }); // reja o'zgardi
  plan = await tool.planCleanup(db);

  await check('T3 eski backup joriy rejaga mos emas — RAD', async () => {
    await assert.rejects(tool.applyCleanup(db, plan, staleBackup, quiet), (e) => e.code === 'BACKUP_MISMATCH');
    assert.ok(await exists('food_catalog/food_3'));
  });

  const backup = await tool.backupCleanup(db, plan);
  await check('T4 backup ichki kolleksiyani ham oladi', async () => {
    assert.ok(backup.docs.some((d) => d.path === 'orders/f_done/payment_lines/l1'));
    assert.strictEqual(backup.docs.length, plan.paths.length + 1);
  });

  let applied;
  await check('T5 apply: hammasi o\'chdi (ichki kolleksiya bilan), non/journal qoldi, qoldiq 0', async () => {
    applied = await tool.applyCleanup(db, plan, backup, quiet);
    assert.strictEqual(applied.remaining, 0);
    assert.ok(!(await exists('orders/f_done')));
    assert.ok(!(await exists('orders/f_done/payment_lines/l1')));
    assert.ok(!(await exists('search_index/service_food')));
    assert.ok(await exists('orders/b1'));
    assert.ok(await exists('admin_news/n_bread'));
    assert.ok(await exists('search_index/service_bread'));
    assert.ok(await exists('journal_entries/j1'));
  });

  await check('T6 restore: hujjatlar va turlari (Timestamp, GeoPoint) qaytadi; qayta restore — o\'tkaziladi', async () => {
    const r = await tool.restoreCleanup(db, admin, JSON.parse(JSON.stringify(backup)), quiet);
    assert.strictEqual(r.restored, backup.docs.length);
    const o = (await db.doc('orders/f_done').get()).data();
    assert.ok(o.createdAt instanceof admin.firestore.Timestamp);
    assert.strictEqual(o.createdAt.toMillis(), 1760000000000);
    const line = (await db.doc('orders/f_done/payment_lines/l1').get()).data();
    assert.strictEqual(line.amount, 20000);
    const cat = (await db.doc('food_catalog/food_1').get()).data();
    assert.ok(cat.loc instanceof admin.firestore.GeoPoint);
    const r2 = await tool.restoreCleanup(db, admin, JSON.parse(JSON.stringify(backup)), quiet);
    assert.strictEqual(r2.restored, 0);
    assert.strictEqual(r2.skipped, backup.docs.length);
  });

  await check('T7 qayta ishga tushirish xavfsiz: bo\'sh reja → 0 o\'chiriladi', async () => {
    const p1 = await tool.planCleanup(db);
    const b1 = await tool.backupCleanup(db, p1);
    await tool.applyCleanup(db, p1, b1, quiet);
    const p2 = await tool.planCleanup(db);
    assert.strictEqual(p2.paths.length, 0);
    const b2 = await tool.backupCleanup(db, p2);
    const r = await tool.applyCleanup(db, p2, b2, quiet);
    assert.strictEqual(r.deleted, 0);
    assert.ok(await exists('orders/b1'));
  });

  await check('T7b restore begona yo\'lga yozmaydi (users/…) — RAD', async () => {
    const bad = { tool: 'food_cleanup', docs: [{ path: 'users/998900000000', data: { role: 'superadmin' } }] };
    await assert.rejects(tool.restoreCleanup(db, admin, bad, quiet), /RESTORE_FOREIGN_PATH/);
    assert.ok(!(await exists('users/998900000000')));
  });

  await check('T8 isActiveOrder chegaralari', async () => {
    assert.strictEqual(tool.isActiveOrder({ status: 'ready' }), true);
    assert.strictEqual(tool.isActiveOrder({ status: 'in_delivery' }), true);
    assert.strictEqual(tool.isActiveOrder({ status: 'rejected' }), false);
    assert.strictEqual(tool.isActiveOrder({ status: 'new', fulfillmentStatus: 'completed' }), false);
    assert.strictEqual(tool.isActiveOrder({}), true);
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} food cleanup checks passed.`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
