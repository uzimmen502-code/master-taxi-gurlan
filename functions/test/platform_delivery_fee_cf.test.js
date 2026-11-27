/**
 * AVA дўкони етказиб бериш ҳақи — `placeOrderPostPaid` (platform) ва
 * `adminSetPlatformDeliveryFeePercent`, HAQIQIY `functions/index.js`, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-platform-fee "node test/platform_delivery_fee_cf.test.js"
 *
 * Bug 2026-11-03:
 *   Symptom — `settings/app.platformDeliveryFeePercent` yo'q/buzuq bo'lsa jimgina 5 % olinardi
 *     (hardcode tarif, 9-qoida), hisob float (`Math.round(x*pct/100)`, 8-qoida), versiya yo'q.
 *   Fix — fail closed `TARIFF_NOT_CONFIGURED`; butun son (bps) hisobi; `deliveryFeeVersion`
 *     buyurtmada; admin o'zgarishi versiya + yopiq tarix (`platform_delivery_fee_history/v{n}`).
 * Qulflanadi:
 *   - 11 % (prod) — natija avvalgi `Math.round` bilan AYNAN bir xil (yarim holatlar ham)
 *   - % yo'q / null / matn / manfiy — TARIFF_NOT_CONFIGURED, buyurtma yaratilmaydi
 *   - versiya yo'q (hozirgi prod) — buyurtmada `deliveryFeeVersion: 0`
 *   - admin: versiya +1, tarix hujjati, `{ok, percent, version}`; admin emas — rad;
 *     noto'g'ri % — versiya o'zgarmaydi; `settings/app`ga admin telefoni yozilmaydi (PII)
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-platform-fee';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require(process.env.COURIER_CF_INDEX || '../index');
const admin = require('firebase-admin');

const db = admin.firestore();
const TS = admin.firestore.Timestamp;
const ADMIN = '998909990000';
const U = '998917000001';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
let seq = 0;
const key = () => `pfee-${Date.now()}-${++seq}`;

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const order = async (id) => (await db.collection('orders').doc(id).get()).data();
const appSettings = async () => (await db.collection('settings').doc('app').get()).data() || {};
const place = (productId, qty = 1) => fns.placeOrderPostPaid.run({
  userPhone: U, idempotencyKey: key(),
  orderBase: { type: 'platform', userName: 'Test', address: 'Gurlan', phone: U, pricingVersion: 2,
    items: [{ productId, qty }] },
}, ctxOf(U));
const setPct = (percent, who = ADMIN) => fns.adminSetPlatformDeliveryFeePercent.run({ adminPhone: who, percent }, ctxOf(who));
async function expectCode(promise, code, detailsCode) {
  await assert.rejects(promise, (e) => {
    assert.strictEqual(e.code, code, `kod ${e.code}: ${e.message}`);
    if (detailsCode) {
      assert.strictEqual(e.message, detailsCode);
      assert.strictEqual(e.details && e.details.code, detailsCode, JSON.stringify(e.details));
    }
    return true;
  });
}

async function main() {
  await clearEmulator();
  const now = TS.now();
  await db.collection('users').doc(ADMIN).set({ role: 'admin', phone: ADMIN });
  await db.collection('users').doc(U).set({ role: 'user', phone: U, bonusBalance: 0 });
  // Narxlar yarim holatlarni ham qamraydi: 50×11% = 5.5, 150×11% = 16.5, 1×11% = 0.11.
  const prices = { p123457: 123457, p50: 50, p150: 150, p1: 1, p100k: 100000, p99999: 99999 };
  for (const [id, price] of Object.entries(prices)) {
    await db.collection('platform_products').doc(id).set({ name: id, price, unit: 'dona', active: true, createdAt: now });
  }

  // Hozirgi prod holati: 11 %, versiya maydoni YO'Q.
  await db.collection('settings').doc('app').set({ platformDeliveryFeePercent: 11 });

  await check('F1 11 % (prod): yetkazish ham avvalgi Math.round bilan AYNAN teng (butun son), versiya 0', async () => {
    for (const [id, price] of Object.entries(prices)) {
      const expectedFee = Math.round(price * 11 / 100); // avvalgi formula
      const r = await place(id);
      const o = await order(r.orderId);
      assert.strictEqual(o.itemsTotal, price, id);
      assert.strictEqual(o.deliveryFee, expectedFee, `${id}: ${o.deliveryFee} != ${expectedFee}`);
      assert.ok(Number.isInteger(o.deliveryFee), `${id}: butun son emas`);
      assert.strictEqual(o.total, price + expectedFee, id);
      assert.strictEqual(r.total, price + expectedFee, id);
      assert.strictEqual(o.deliveryFeePercent, 11);
      assert.strictEqual(o.deliveryFeeVersion, 0, `${id}: versiya yo'q → 0`);
    }
    // aniq qiymatlar (qo'lda): 123457 → 13580, 50 → 6, 150 → 17, 1 → 0
    assert.deepStrictEqual([123457, 50, 150, 1].map((x) => Math.floor((x * 1100 + 5000) / 10000)), [13580, 6, 17, 0]);
  });

  await check('F2 qty > 1: itemsTotal × % (qator emas, jami bo\'yicha)', async () => {
    const r = await place('p150', 3); // 450 × 11 % = 49.5 → 50
    const o = await order(r.orderId);
    assert.deepStrictEqual([o.itemsTotal, o.deliveryFee, o.total], [450, 50, 500]);
  });

  for (const [label, val] of [['yo\'q', undefined], ['null', null], ['matn', 'abc'], ['bo\'sh matn', ''], ['manfiy', -1]]) {
    await check(`F3 % ${label} — TARIFF_NOT_CONFIGURED (hardcode 5 % YO'Q), buyurtma yaratilmaydi`, async () => {
      const ref = db.collection('settings').doc('app');
      if (val === undefined) await ref.set({ other: true });
      else await ref.set({ platformDeliveryFeePercent: val });
      const before = (await db.collection('orders').get()).size;
      await expectCode(place('p100k'), 'failed-precondition', 'TARIFF_NOT_CONFIGURED');
      assert.strictEqual((await db.collection('orders').get()).size, before, 'buyurtma yozildi');
    });
  }

  await check('F4 0 % — ruxsat (bepul yetkazish), fee 0', async () => {
    await db.collection('settings').doc('app').set({ platformDeliveryFeePercent: 0 });
    const o = await order((await place('p100k')).orderId);
    assert.deepStrictEqual([o.deliveryFee, o.total, o.deliveryFeePercent, o.deliveryFeeVersion], [0, 100000, 0, 0]);
  });

  await db.collection('settings').doc('app').set({ platformDeliveryFeePercent: 11 });

  await check('A1 admin emas — rad, versiya/tarix yo\'q', async () => {
    await assert.rejects(setPct(50, U), (e) => e.code === 'permission-denied');
    const s = await appSettings();
    assert.strictEqual(s.platformDeliveryFeePercent, 11);
    assert.strictEqual(s.platformDeliveryFeeVersion, undefined);
    assert.strictEqual((await db.collection('platform_delivery_fee_history').get()).size, 0);
  });

  await check('A2 admin 12 %: versiya 0 → 1, tarix v1 {percent, prevPercent, version, by, at}; javob mos', async () => {
    const r = await setPct(12);
    assert.deepStrictEqual(r, { ok: true, percent: 12, version: 1 });
    const s = await appSettings();
    assert.deepStrictEqual([s.platformDeliveryFeePercent, s.platformDeliveryFeeVersion], [12, 1]);
    assert.strictEqual(s.updatedBy, undefined, 'settings/app hammaga ochiq — admin telefoni yozilmaydi');
    const h = (await db.collection('platform_delivery_fee_history').doc('v1').get()).data();
    assert.deepStrictEqual([h.percent, h.prevPercent, h.version, h.by], [12, 11, 1, ADMIN]);
    assert.ok(h.at, 'at');
  });

  await check('A3 buyurtma yangi versiya bilan: 12 %, deliveryFeeVersion 1', async () => {
    const o = await order((await place('p123457')).orderId);
    assert.deepStrictEqual([o.deliveryFee, o.deliveryFeePercent, o.deliveryFeeVersion], [Math.round(123457 * 12 / 100), 12, 1]);
  });

  await check('A4 yana 11 %: v2 (prevPercent 12), v1 o\'zgarmaydi; noto\'g\'ri % — invalid-argument, versiya 2 qoladi', async () => {
    const r = await setPct(11);
    assert.deepStrictEqual(r, { ok: true, percent: 11, version: 2 });
    const h2 = (await db.collection('platform_delivery_fee_history').doc('v2').get()).data();
    assert.deepStrictEqual([h2.percent, h2.prevPercent, h2.version], [11, 12, 2]);
    const h1 = (await db.collection('platform_delivery_fee_history').doc('v1').get()).data();
    assert.strictEqual(h1.percent, 12, 'eski tarix qayta yozilmadi');
    await assert.rejects(setPct(101), (e) => e.code === 'invalid-argument');
    await assert.rejects(setPct('x'), (e) => e.code === 'invalid-argument');
    assert.strictEqual((await appSettings()).platformDeliveryFeeVersion, 2);
    assert.strictEqual((await db.collection('platform_delivery_fee_history').get()).size, 2);
  });

  await check('A5 PARALLEL ikki o\'zgarish — versiyalar 3 va 4, ikkala tarix hujjati (yo\'qolmaydi)', async () => {
    const rs = await Promise.all([setPct(13), setPct(14)]);
    assert.deepStrictEqual(rs.map((x) => x.version).sort(), [3, 4]);
    const hs = (await db.collection('platform_delivery_fee_history').get()).docs.map((d) => d.id).sort();
    assert.deepStrictEqual(hs, ['v1', 'v2', 'v3', 'v4']);
  });

  const passed = results.filter(Boolean).length;
  console.log(`${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
