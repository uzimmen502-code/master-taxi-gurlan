/**
 * «AVA Супермаркет» таклифи эски `placeOrderPostPaid` (platform) йўлидан олинмайди (эга 2026-11-20).
 *
 *   firebase emulators:exec --only firestore --project demo-platform-sm-guard "node test/platform_sm_guard_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-platform-sm-guard';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');

const db = admin.firestore();
const U = '998917000001';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
let seq = 0;
const place = (items) => fns.placeOrderPostPaid.run({
  userPhone: U, idempotencyKey: `smg-${Date.now()}-${++seq}`,
  orderBase: { type: 'platform', userName: 'Test', address: 'Gurlan', phone: U, pricingVersion: 2, items },
}, ctxOf(U));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const orderCount = async () => (await db.collection('orders').get()).size;

async function main() {
  await clearEmulator();
  await db.doc(`users/${U}`).set({ role: 'user', phone: U, bonusBalance: 0 });
  await db.doc('settings/app').set({ platformDeliveryFeePercent: 11 });
  await db.doc('platform_products/legacy').set({ name: 'Эски', price: 1000, unit: 'dona', active: true });
  await db.doc('platform_products/sm1').set({ name: 'Мол гўшти', price: 80000, unit: 'kg', smGroupId: 'beef', smStatus: 'active', stock: 10, active: false });
  await db.doc('platform_products/sm_empty').set({ name: 'X', price: 500, unit: 'dona', smGroupId: '  ', active: true });

  await check('G1 супермаркет таклифи → failed-precondition SUPERMARKET_PRODUCT_USE_SUPERMARKET (3 тил), буюртма йўқ, stock ўзгармайди', async () => {
    await assert.rejects(place([{ productId: 'sm1', qty: 1 }]), (e) => {
      assert.strictEqual(e.code, 'failed-precondition');
      assert.strictEqual(e.details.code, 'SUPERMARKET_PRODUCT_USE_SUPERMARKET');
      assert.strictEqual(e.details.productId, 'sm1');
      for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) assert.ok(e.details.messages[l], l);
      return true;
    });
    assert.strictEqual(await orderCount(), 0);
    const p = (await db.doc('platform_products/sm1').get()).data();
    assert.deepStrictEqual([p.stock, p.soldToday], [10, undefined]);
  });

  await check('G2 аралаш сават (эски + супермаркет) ҳам рад — қисман буюртма йўқ', async () => {
    await assert.rejects(place([{ productId: 'legacy', qty: 1 }, { productId: 'sm1', qty: 1 }]), (e) => e.details.code === 'SUPERMARKET_PRODUCT_USE_SUPERMARKET');
    assert.strictEqual(await orderCount(), 0);
  });

  await check('G3 эски товар аввалгидек (regression); бўш smGroupId — эски товар', async () => {
    const r = await place([{ productId: 'legacy', qty: 2 }]);
    const o = (await db.doc(`orders/${r.orderId}`).get()).data();
    // Ягона нарх (эга 2026-11-28: поғоналар йўқ) → 1000 × 2 = 2000; fee 11 % = 220
    assert.deepStrictEqual([o.type, o.itemsTotal, o.deliveryFee, o.total], ['platform', 2000, 220, 2220]);
    const r2 = await place([{ productId: 'sm_empty', qty: 1 }]);
    assert.ok(r2.orderId);
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}
main().catch((e) => { console.error(e); process.exit(1); });
