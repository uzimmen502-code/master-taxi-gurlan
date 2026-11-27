/**
 * T-3 (takrorlanishlar auditi 2026-11-28, ega 2026-11-28): `platform_products` narx versiyasini SERVER
 * tanlaydi — klient `pricingVersion` (yo'q / 1 / 0 / '1' / 99) e'tiborsiz; pog'onasi bor tovarda pog'ona
 * DOIM; buyurtmaga `pricingVersion: 2` yoziladi; eski ilova so'rovi rad etilmaydi.
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

async function main() {
  await clearEmulator();
  await db.doc(`users/${U}`).set({ role: 'user', phone: U, bonusBalance: 0 });
  await db.doc('settings/app').set({ platformDeliveryFeePercent: 0 });
  // Eski tovar (createdAt yo'q) — hisoblangan pog'onalar: 1–9 = 1050, 10–49 = 1000, 50+ = 950.
  await db.doc('platform_products/old').set({ name: 'Eski', price: 1000, unit: 'dona' });
  // Admin pog'onalari bor yangi tovar.
  await db.doc('platform_products/tiered').set({
    name: 'Pog\'onali', price: 2000, unit: 'dona', createdAt: new Date('2026-11-01T00:00:00Z'),
    priceTiers: [{ minQty: 1, price: 2200 }, { minQty: 5, price: 2000 }],
  });
  // Pog'onasiz yangi tovar — yagona narx.
  await db.doc('platform_products/plain').set({ name: 'Oddiy', price: 3000, unit: 'dona', createdAt: new Date('2026-11-01T00:00:00Z') });

  await check('S0 sof: SERVER_PRICING_VERSION = 2 (pog\'onali)', () => {
    assert.strictEqual(pricing.SERVER_PRICING_VERSION, pricing.PRICING_VERSION_TIERED);
    assert.strictEqual(pricing.SERVER_PRICING_VERSION, 2);
  });

  await check('S1 klient pricingVersion 1 / yo\'q / 0 / \'1\' / null → baribir pog\'ona (1 dona = 1050), buyurtmada pricingVersion 2', async () => {
    for (const extra of [{ pricingVersion: 1 }, {}, { pricingVersion: 0 }, { pricingVersion: '1' }, { pricingVersion: null }]) {
      const r = await place([{ productId: 'old', qty: 1 }], extra);
      const o = await orderOf(r);
      assert.deepStrictEqual([o.itemsTotal, o.total, o.pricingVersion], [1050, 1050, 2], JSON.stringify(extra));
    }
  });

  await check('S2 klient pricingVersion 2 (yangi ilova) — avvalgidek; 99 ham server versiyasi', async () => {
    const r = await place([{ productId: 'old', qty: 10 }], { pricingVersion: 2 });
    assert.deepStrictEqual([(await orderOf(r)).itemsTotal, (await orderOf(r)).pricingVersion], [10000, 2]);
    const r2 = await place([{ productId: 'old', qty: 50 }], { pricingVersion: 99 });
    assert.deepStrictEqual([(await orderOf(r2)).itemsTotal, (await orderOf(r2)).pricingVersion], [47500, 2]);
  });

  await check('S3 admin pog\'onasi chetlab o\'tilmaydi: pricingVersion 1 bilan 1 dona = 2200 (price 2000 emas); chegara 5 dona = 2000', async () => {
    const r = await place([{ productId: 'tiered', qty: 1 }], { pricingVersion: 1 });
    assert.strictEqual((await orderOf(r)).itemsTotal, 2200);
    const r2 = await place([{ productId: 'tiered', qty: 5 }], { pricingVersion: 1 });
    assert.strictEqual((await orderOf(r2)).itemsTotal, 10000);
  });

  await check('S4 pog\'onasiz yangi tovar — yagona narx (pog\'ona yo\'q joyda o\'zgarish yo\'q)', async () => {
    const r = await place([{ productId: 'plain', qty: 2 }], {});
    assert.strictEqual((await orderOf(r)).itemsTotal, 6000);
  });

  await check('S5 oldindan hisob (previewIncentiveForOrder) ham server versiyasida', async () => {
    const pv = await fns.previewIncentiveForOrder.run({ items: [{ productId: 'old', qty: 1 }], pricingVersion: 1 }, ctxOf(U));
    assert.strictEqual(pv.itemsTotal, 1050, JSON.stringify(pv).slice(0, 300));
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}
main().catch((e) => { console.error(e); process.exit(1); });
