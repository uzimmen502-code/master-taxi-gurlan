/**
 * `tools/order_index_backfill.js` — DRY-RUN / apply / recompute / purge.
 *   firebase emulators:exec --only firestore --project demo-order-index \
 *     "node functions/test/order_index_backfill.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-order-index';

const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const oi = require('../order_index');
const tool = require('../tools/order_index_backfill');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
const quiet = { log: () => {} };
const ts = (m) => admin.firestore.Timestamp.fromMillis(m);
const T0 = Date.UTC(2026, 9, 12, 5, 0);

async function wipe(col) {
  const docs = await db.collection(col).listDocuments();
  await Promise.all(docs.map((d) => db.recursiveDelete(d)));
}
const count = async () => (await db.collection('order_index').count().get()).data().count;

(async () => {
  await Promise.all([...oi.SOURCES, 'order_index', 'settings'].map(wipe));
  oi._resetSettingsCache();
  await db.doc('orders/b1').set({ type: 'bread', status: 'new', statusUpdatedAt: ts(T0) });
  await db.doc('orders/w1').set({ type: 'platform', status: 'accepted', statusUpdatedAt: ts(T0) });
  await db.doc('orders/r1').set({ type: 'restaurant', restaurantStatus: 'ready', statusUpdatedAt: ts(T0) });
  await db.doc('orders/f1').set({ type: 'food', status: 'delivered' });
  await db.doc('carpet_wash_orders/k1').set({ status: 'washing', updatedAt: ts(T0) });
  await db.doc('agro_pickup_orders/m1').set({ status: 'new', updatedAt: ts(T0) });
  await db.doc('shipments/s1').set({ status: 'awaiting_payment', updatedAt: ts(T0) });
  await db.doc('demands/c1').set({ module: 'courier', status: 'active', updatedAt: ts(T0) });
  await db.doc('demands/l1').set({ module: 'logistics', status: 'active' });
  await db.doc('carpet_wash_orders/k2').set({ status: 'mystery' });

  await check('B1 DRY-RUN: ҳеч нарса ёзилмайди; food ва LEG ўтказилади; номаълум статус кўрсатилади', async () => {
    const p = await tool.planBackfill(db);
    assert.strictEqual(await count(), 0);
    assert.strictEqual(p.indexable, 8);
    assert.strictEqual(p.byModule.bread.total, 1);
    assert.strictEqual(p.byModule.carpet.total, 2);
    assert.strictEqual(p.unknown['carpet:mystery'], 1);
    assert.ok(!p.byModule.food);
  });

  await check('B2 apply: 8 та индекс, sinceApprox, текширув сонлари', async () => {
    const r = await tool.applyBackfill(db, admin, quiet);
    assert.strictEqual(r.written, 8);
    assert.strictEqual(r.failed, 0);
    assert.strictEqual(await count(), 8);
    assert.strictEqual(r.verify.carpet, 2);
    const d = (await db.doc('order_index/bread_b1').get()).data();
    assert.strictEqual(d.sinceApprox, true);
    assert.strictEqual(d.stageSince.toMillis(), T0);
  });

  await check('B3 қайта apply — ҳеч нарса қайта ёзилмайди (idempotent)', async () => {
    const r = await tool.applyBackfill(db, admin, quiet);
    assert.strictEqual(r.written || 0, 0);
    assert.strictEqual(r.stale_skipped, 8);
    assert.strictEqual(await count(), 8);
  });

  await check('B4 recompute: чегара ўзгарса stuckAt янгиланади, stageSince сақланади', async () => {
    await db.doc('settings/all_orders_stuck').set({ rules: { bread: { stages: { new: { min: 45 } } } } });
    oi._resetSettingsCache();
    await tool.applyBackfill(db, admin, { ...quiet, force: true });
    const d = (await db.doc('order_index/bread_b1').get()).data();
    assert.strictEqual(d.stuckAt.toMillis(), T0 + 45 * 60000);
    assert.strictEqual(d.stageSince.toMillis(), T0);
  });

  await check('B5 purge: индекс ўчади, манба тегилмайди', async () => {
    const r = await tool.purgeIndex(db, quiet);
    assert.strictEqual(r.deleted, 8);
    assert.strictEqual(await count(), 0);
    assert.ok((await db.doc('orders/b1').get()).exists);
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} order_index backfill checks passed.`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
