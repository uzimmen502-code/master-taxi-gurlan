/**
 * Рағбат — AVA дўкони буюртмасида сарфлаш ва бекорда қайтариш (placeOrderPostPaid, customerCancelOrder,
 * previewIncentiveForOrder), HAQIQIY `functions/index.js`, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-incentive-orders "node test/incentives_order_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-incentive-orders';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const { computeIncentivePlan } = require('../incentives');

const db = admin.firestore();
const TS = admin.firestore.Timestamp;
const DAY = 86400000;
const W = '998916000001'; // ayol: women grant (any)
const C = '998916000002'; // mashina: car grant (toifalar)
const B = '998916000003'; // ikkalasi
const X = '998916000004'; // muddati o'tgan grant bilan bekor qilish
const F = '998916000005'; // to'liq qoplash (100%)
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
let seq = 0;
const key = () => `inc-order-${Date.now()}-${++seq}`;

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
const user = async (id) => (await db.collection('users').doc(id).get()).data();
const grant = async (id) => (await db.collection('incentive_grants').doc(id).get()).data();
const prog = async (id) => (await db.collection('incentive_programs').doc(id).get()).data();
const order = async (id) => (await db.collection('orders').doc(id).get()).data();

async function seedGrant(uid, programId, { amount, buckets, pct = 30, expiresInDays = 90 }) {
  await db.collection('incentive_grants').doc(`${programId}_${uid}`).set({
    uid, programId, programKey: programId, amount, remaining: amount, buckets, maxOrderSharePct: pct,
    status: 'active', expiresAt: TS.fromMillis(Date.now() + expiresInDays * DAY), createdAt: TS.now(),
  });
  await db.collection('users').doc(uid).set({ incentiveBalance: admin.firestore.FieldValue.increment(amount) }, { merge: true });
}

const place = (who, orderBase, extra = {}) => fns.placeOrderPostPaid.run({
  userPhone: who, idempotencyKey: extra.key || key(),
  orderBase: { type: 'platform', userName: 'Test', address: 'Gurlan', phone: who, pricingVersion: 2, ...orderBase },
}, ctxOf(who));

async function main() {
  await clearEmulator();
  const now = TS.now();
  await db.collection('settings').doc('app').set({ platformDeliveryFeePercent: 10 });
  await db.collection('platform_products').doc('tire1').set({ name: 'Shina R15', price: 100000, unit: 'dona', active: true, createdAt: now, incentiveCategory: 'tire' });
  await db.collection('platform_products').doc('oil1').set({ name: 'Moy 4L', price: 50000, unit: 'dona', active: true, createdAt: now, incentiveCategory: 'oil' });
  await db.collection('platform_products').doc('gen1').set({ name: 'Choy', price: 20000, unit: 'dona', active: true, createdAt: now });
  for (const p of ['women', 'car']) {
    await db.collection('incentive_programs').doc(p).set({ key: p, stage: 'public', counters: { grantedAmount: 0, spentAmount: 0, expiredAmount: 0, revokedAmount: 0 } });
  }
  for (const u of [W, C, B, X, F]) await db.collection('users').doc(u).set({ role: 'user', phone: u, bonusBalance: 0 });
  await seedGrant(W, 'women', { amount: 100000, buckets: { any: 100000 } });
  await seedGrant(C, 'car', { amount: 200000, buckets: { tire: 60000, oil: 40000, battery: 50000, insurance: 50000 } });
  await seedGrant(B, 'car', { amount: 200000, buckets: { tire: 60000, oil: 40000, battery: 50000, insurance: 50000 }, expiresInDays: 30 });
  await seedGrant(B, 'women', { amount: 100000, buckets: { any: 100000 } });
  await seedGrant(X, 'women', { amount: 100000, buckets: { any: 100000 } });
  await seedGrant(F, 'women', { amount: 100000, buckets: { any: 100000 }, pct: 100 });

  await check('P1 sof reja: ulush chegarasi, toifa, muddati o\'tgan grant hisobga olinmaydi', () => {
    const nowMs = Date.now();
    const lines = [{ category: 'tire', total: 200000 }, { category: 'oil', total: 50000 }, { category: '', total: 20000 }];
    const car = { id: 'car_1', programId: 'car', remaining: 200000, buckets: { tire: 60000, oil: 40000 }, maxOrderSharePct: 30, expiresAtMs: nowMs + DAY };
    const p = computeIncentivePlan([car], lines, nowMs);
    assert.deepStrictEqual([p.total, p.perGrant[0].byBucket], [75000, { tire: 60000, oil: 15000 }]);
    const expired = { ...car, id: 'car_2', expiresAtMs: nowMs - 1 };
    assert.strictEqual(computeIncentivePlan([expired], lines, nowMs).total, 0);
    const any = { id: 'w_1', programId: 'women', remaining: 100000, buckets: { any: 100000 }, maxOrderSharePct: 30, expiresAtMs: nowMs + DAY };
    assert.strictEqual(computeIncentivePlan([any], [{ category: 'zzz bad', total: 10000 }], nowMs).total, 3000);
  });

  let womanOrder;
  await check('O1 ayol: shina+choy, bonus 30% (mahsulotdan), yetkazish to\'liq; summa netto, grant/balans/jurnal/counters', async () => {
    const r = await place(W, { items: [{ productId: 'tire1', qty: 1 }, { productId: 'gen1', qty: 1 }], useIncentive: true });
    womanOrder = r.orderId;
    // mahsulot 120 000, yetkazish 12 000, brutto 132 000; bonus 36 000 → netto 96 000
    assert.deepStrictEqual([r.total, r.cashDue, r.incentiveApplied, r.paymentStatus], [96000, 96000, 36000, 'unpaid']);
    const o = await order(r.orderId);
    assert.deepStrictEqual([o.total, o.grossTotal, o.itemsTotal, o.deliveryFee, o.incentiveApplied, o.incentiveUid, o.balanceApplied], [96000, 132000, 120000, 12000, 36000, W, 0]);
    assert.deepStrictEqual(o.incentiveGrants, [{ grantId: `women_${W}`, programId: 'women', amount: 36000, byBucket: { any: 36000 } }]);
    assert.strictEqual(o.items[0].incentiveCategory, 'tire');
    assert.strictEqual(o.items[1].incentiveCategory, 'general');
    const g = await grant(`women_${W}`);
    assert.deepStrictEqual([g.remaining, g.buckets.any, g.status], [64000, 64000, 'active']);
    assert.strictEqual((await user(W)).incentiveBalance, 64000);
    assert.strictEqual((await user(W)).bonusBalance, 0);
    assert.strictEqual((await prog('women')).counters.spentAmount, 36000);
    assert.ok((await db.collection('incentive_ledger').doc(`spend_${r.orderId}_women_${W}`).get()).exists);
  });

  await check('O2 useIncentive yo\'q — bonus ishlatilmaydi (eski ilova)', async () => {
    const r = await place(W, { items: [{ productId: 'gen1', qty: 1 }] });
    assert.deepStrictEqual([r.total, r.incentiveApplied], [22000, 0]);
    assert.strictEqual((await user(W)).incentiveBalance, 64000);
    assert.strictEqual((await order(r.orderId)).incentiveApplied, undefined);
  });

  await check('O3 mashina: faqat o\'z toifalari (shina 60k to\'liq, moy qolgan ulushgacha), umumiy mahsulot qoplanmaydi', async () => {
    const r = await place(C, { items: [{ productId: 'tire1', qty: 2 }, { productId: 'oil1', qty: 1 }, { productId: 'gen1', qty: 1 }], useIncentive: true });
    // toifa bazasi 250 000 × 30% = 75 000: shina 60 000 + moy 15 000
    assert.strictEqual(r.incentiveApplied, 75000);
    const g = await grant(`car_${C}`);
    assert.deepStrictEqual(g.buckets, { tire: 0, oil: 25000, battery: 50000, insurance: 50000 });
    assert.strictEqual(g.remaining, 125000);
    assert.strictEqual((await user(C)).incentiveBalance, 125000);
  });

  await check('O4 ikki grant: muddati yaqin (car) birinchi, bir qator ikki marta qoplanmaydi; preview = buyurtma', async () => {
    const items = [{ productId: 'tire1', qty: 1 }, { productId: 'gen1', qty: 1 }];
    const pv = await fns.previewIncentiveForOrder.run({ items, pricingVersion: 2 }, ctxOf(B));
    const r = await place(B, { items, useIncentive: true });
    // car: shina bazasi 100 000 × 30% = 30 000 (shina toifasidan). women: hammasi 120 000 × 30% = 36 000,
    // lekin shinadan 70 000 + choy 20 000 qolgan → 36 000. Jami 66 000.
    assert.strictEqual(r.incentiveApplied, 66000);
    assert.strictEqual(pv.incentiveTotal, 66000, 'preview buyurtma bilan bir xil');
    const o = await order(r.orderId);
    assert.deepStrictEqual(o.incentiveGrants.map((x) => [x.programId, x.amount]), [['car', 30000], ['women', 36000]]);
  });

  await check('O5 hamyon bilan birga: hamyon NETTO summaga qo\'llanadi', async () => {
    await db.collection('users').doc(W).update({ bonusBalance: 200000 });
    const r = await place(W, { items: [{ productId: 'oil1', qty: 1 }], useIncentive: true, useWallet: true, balanceApplied: 999999 });
    // mahsulot 50 000, yetk. 5 000; bonus 15 000 → netto 40 000; hamyon 40 000; naqd 0
    assert.deepStrictEqual([r.incentiveApplied, r.total, r.walletDebit, r.cashDue, r.paymentStatus], [15000, 40000, 40000, 0, 'paid']);
    assert.strictEqual((await user(W)).bonusBalance, 160000);
    assert.strictEqual((await order(r.orderId)).paymentMethod, 'wallet');
  });

  await check('O6 takror (bir xil idempotencyKey) — ikki marta yechilmaydi', async () => {
    const k = key();
    const before = (await user(W)).incentiveBalance;
    const a = await place(W, { items: [{ productId: 'gen1', qty: 1 }], useIncentive: true }, { key: k });
    const b = await place(W, { items: [{ productId: 'gen1', qty: 1 }], useIncentive: true }, { key: k });
    assert.strictEqual(a.orderId, b.orderId);
    assert.strictEqual((await user(W)).incentiveBalance, before - a.incentiveApplied);
  });

  await check('O7 bekor qilish: bonus grantga qaytadi (hamyonga EMAS), jurnal, counters; takror — o\'zgarmaydi', async () => {
    const beforeBonus = (await user(W)).bonusBalance;
    const beforeInc = (await user(W)).incentiveBalance;
    const c = await fns.customerCancelOrder.run({ orderId: womanOrder }, ctxOf(W));
    assert.ok(c.ok !== false);
    assert.strictEqual((await user(W)).incentiveBalance, beforeInc + 36000);
    assert.strictEqual((await user(W)).bonusBalance, beforeBonus, 'hamyonga tushmaydi');
    assert.ok((await db.collection('incentive_ledger').doc(`refund_${womanOrder}_women_${W}`).get()).exists);
    const again = await fns.customerCancelOrder.run({ orderId: womanOrder }, ctxOf(W));
    assert.ok(again.already === true || again.ok);
    assert.strictEqual((await user(W)).incentiveBalance, beforeInc + 36000);
  });

  await check('O8 bekor qilishda grant muddati o\'tgan — qaytmaydi (refund_forfeit), counters spent→expired', async () => {
    const r = await place(X, { items: [{ productId: 'tire1', qty: 1 }], useIncentive: true });
    assert.strictEqual(r.incentiveApplied, 30000);
    await db.collection('incentive_grants').doc(`women_${X}`).update({ expiresAt: TS.fromMillis(Date.now() - 1000) });
    const p0 = (await prog('women')).counters;
    await fns.customerCancelOrder.run({ orderId: r.orderId }, ctxOf(X));
    assert.strictEqual((await user(X)).incentiveBalance, 70000, 'qaytmadi');
    const led = (await db.collection('incentive_ledger').doc(`refund_${r.orderId}_women_${X}`).get()).data();
    assert.strictEqual(led.type, 'refund_forfeit');
    const p1 = (await prog('women')).counters;
    assert.deepStrictEqual([p1.spentAmount - p0.spentAmount, p1.expiredAmount - p0.expiredAmount], [-30000, 30000]);
  });

  await check('O9 100% ulush, yetkazish 0% — to\'liq bonus bilan to\'langan (paymentMethod incentive)', async () => {
    await db.collection('settings').doc('app').set({ platformDeliveryFeePercent: 0 });
    const r = await place(F, { items: [{ productId: 'gen1', qty: 2 }], useIncentive: true });
    assert.deepStrictEqual([r.incentiveApplied, r.total, r.cashDue, r.paymentStatus], [40000, 0, 0, 'paid']);
    assert.strictEqual((await order(r.orderId)).paymentMethod, 'incentive');
    assert.strictEqual((await grant(`women_${F}`)).remaining, 60000);
  });

  await check('O10 begona grantni ishlata olmaydi (uid token bo\'yicha); preview ham', async () => {
    const STR = '998916000099';
    await db.collection('users').doc(STR).set({ role: 'user', phone: STR, bonusBalance: 0 });
    const r = await place(STR, { items: [{ productId: 'tire1', qty: 1 }], useIncentive: true });
    assert.strictEqual(r.incentiveApplied, 0);
    const pv = await fns.previewIncentiveForOrder.run({ items: [{ productId: 'tire1', qty: 1 }] }, ctxOf(STR));
    assert.strictEqual(pv.incentiveTotal, 0);
  });

  const passed = results.filter(Boolean).length;
  console.log(`${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
