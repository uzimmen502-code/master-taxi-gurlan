/**
 * AVA do'koni narxi — SERVER tanlaydi, YAGONA narx (T-3 + ega 2026-11-28: pog'onalar olib tashlangan).
 * Klient `pricingVersion` (yo'q / 1 / 0 / '1' / null / 2 / 99) e'tiborsiz; istalgan miqdorda
 * unitPrice = `price`; eski va yangi ilova bir xil (ko'rsatilgan `price`) to'laydi; buyurtmaga
 * `pricingVersion: 3` yoziladi; eski ilova so'rovi rad etilmaydi.
 *
 *   firebase emulators:exec --only firestore --project demo-pricing-server "node test/platform_pricing_server_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-pricing-server';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const pricing = require('../platform_pricing');

const db = admin.firestore();
const U = '998917300001';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
let seq = 0;
const place = (items, extra) => fns.placeOrderPostPaid.run({
  userPhone: U, idempotencyKey: `t3-${Date.now()}-${++seq}`,
  orderBase: { type: 'platform', userName: 'Test', address: 'Gurlan', phone: U, items, ...(extra || {}) },
}, ctxOf(U));
const orderOf = async (r) => (await db.doc(`orders/${r.orderId}`).get()).data();

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
const CLIENTS = [{}, { pricingVersion: 1 }, { pricingVersion: 0 }, { pricingVersion: '1' }, { pricingVersion: null },
  { pricingVersion: 2 }, { pricingVersion: 99 }];

async function main() {
  await clearEmulator();
  await db.doc(`users/${U}`).set({ role: 'user', phone: U, bonusBalance: 0 });
  await db.doc('settings/app').set({ platformDeliveryFeePercent: 0 });
  // Eski tovar (createdAt yo'q) — avval 1–9 dona +5 % hisoblanardi; endi yagona narx.
  await db.doc('platform_products/old').set({ name: 'Eski', price: 1000, unit: 'dona' });
  // priceTiers yozilgan bo'lsa ham (prod'da yo'q) — e'tiborsiz.
  await db.doc('platform_products/tiered').set({
    name: 'Pog\'onali', price: 2000, unit: 'dona', createdAt: new Date('2026-11-01T00:00:00Z'),
    priceTiers: [{ minQty: 1, price: 2200 }, { minQty: 5, price: 1800 }],
  });

  await check('S0 sof: SERVER_PRICING_VERSION = 3 (yagona narx)', () => {
    assert.strictEqual(pricing.SERVER_PRICING_VERSION, 3);
  });

  await check('S1 eski va yangi klient (versiya yo\'q/1/0/\'1\'/null/2/99) — 1 dona = 1000 (ko\'rsatilgan narx), pricingVersion 3', async () => {
    for (const extra of CLIENTS) {
      const r = await place([{ productId: 'old', qty: 1 }], extra);
      const o = await orderOf(r);
      assert.deepStrictEqual([o.itemsTotal, o.total, o.pricingVersion], [1000, 1000, 3], JSON.stringify(extra));
    }
  });

  await check('S2 istalgan miqdor — bir xil dona narxi: 9 → 9000, 10 → 10 000, 50 → 50 000 (−5 % yo\'q), 500 → 500 000', async () => {
    for (const [q, want] of [[9, 9000], [10, 10000], [50, 50000], [500, 500000]]) {
      const r = await place([{ productId: 'old', qty: q }], { pricingVersion: 2 });
      assert.strictEqual((await orderOf(r)).itemsTotal, want, `qty ${q}`);
    }
  });

  await check('S3 priceTiers e\'tiborsiz: 1 dona = 2000 (2200 emas), 5 dona = 10 000 (1800 emas); qator narxi = 2000', async () => {
    const r = await place([{ productId: 'tiered', qty: 1 }], { pricingVersion: 2 });
    assert.strictEqual((await orderOf(r)).itemsTotal, 2000);
    const r2 = await place([{ productId: 'tiered', qty: 5 }], {});
    const o2 = await orderOf(r2);
    assert.deepStrictEqual([o2.itemsTotal, o2.items[0].price], [10000, 2000]);
  });

  await check('S4 oldindan hisob (previewIncentiveForOrder) ham yagona narx', async () => {
    const pv = await fns.previewIncentiveForOrder.run({ items: [{ productId: 'old', qty: 1 }], pricingVersion: 2 }, ctxOf(U));
    assert.strictEqual(pv.itemsTotal, 1000, JSON.stringify(pv).slice(0, 300));
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}
main().catch((e) => { console.error(e); process.exit(1); });
