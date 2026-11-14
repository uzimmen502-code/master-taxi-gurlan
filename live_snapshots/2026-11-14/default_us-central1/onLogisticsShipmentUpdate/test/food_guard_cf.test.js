/**
 * «Овқат» модули олиб ташланди (эга, 2026-10-11) — сервер ҳимояси:
 * `placeOrderPostPaid` ва `sellerPlaceSale` `food` ни FOOD_MODULE_REMOVED
 * билан рад этади, нон эса аввалгидек.
 *
 *   firebase emulators:exec --only firestore --project demo-food-guard \
 *     "node functions/test/food_guard_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-food-guard';
process.env.FUNCTIONS_EMULATOR = 'true';

const fns = require('../index.js');
const admin = require('firebase-admin');
const db = admin.firestore();

const BUYER = '998901000011';
const SELLER = '998904000011';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => d.ref.delete()));
}
async function rejectsWith(promise, code) {
  try {
    await promise;
  } catch (e) {
    const got = (e && e.details && e.details.code) || (e && e.code);
    assert.strictEqual(got, code, `kutilgan ${code}, keldi ${got} (${e.message})`);
    return;
  }
  throw new Error(`rad etilishi kerak edi (${code})`);
}
const count = async (col) => (await db.collection(col).get()).size;

(async () => {
  await Promise.all(['users', 'orders', 'food_catalog', 'food_inventory', 'bread_products',
    'wallet_idempotency'].map(wipe));
  await db.collection('users').doc(BUYER).set({ role: 'user', phone: BUYER, bonusBalance: 0 });
  await db.collection('users').doc(SELLER).set({ role: 'seller', phone: SELLER });
  await db.collection('food_catalog').doc('food_plov').set({ name: 'Plov', price: 30000, unit: 'porsiya' });
  await db.collection('bread_products').doc('non1').set({ name: 'Non', price: 5000, unit: 'dona' });

  await check('F1 placeOrderPostPaid: food — FOOD_MODULE_REMOVED, buyurtma yozilmaydi', async () => {
    await rejectsWith(fns.placeOrderPostPaid.run({
      userPhone: BUYER, idempotencyKey: `k_${Date.now()}`,
      orderBase: { type: 'food', phone: BUYER, userName: 'T', address: 'Gurlan',
        items: [{ inventoryId: 'food_plov', qty: 1 }] },
    }, ctxOf(BUYER)), 'FOOD_MODULE_REMOVED');
    assert.strictEqual(await count('orders'), 0);
  });
  await check('F2 sellerPlaceSale: food — FOOD_MODULE_REMOVED, savdo yozilmaydi', async () => {
    await rejectsWith(fns.sellerPlaceSale.run({
      idempotencyKey: `s_${Date.now()}`, cashPaid: 30000,
      items: [{ kind: 'food', inventoryId: 'food_plov', qty: 1 }],
    }, ctxOf(SELLER)), 'FOOD_MODULE_REMOVED');
    assert.strictEqual(await count('orders'), 0);
    assert.strictEqual(await count('wallet_idempotency'), 0);
  });
  await check('F3 sellerPlaceSale: non + food aralash — rad, hech narsa yozilmaydi', async () => {
    await rejectsWith(fns.sellerPlaceSale.run({
      idempotencyKey: `s2_${Date.now()}`, cashPaid: 35000,
      items: [{ kind: 'bread', inventoryId: 'non1', qty: 1 }, { kind: 'food', inventoryId: 'food_plov', qty: 1 }],
    }, ctxOf(SELLER)), 'FOOD_MODULE_REMOVED');
    assert.strictEqual(await count('orders'), 0);
  });
  await check('F4 sellerPlaceSale: non — avvalgidek ishlaydi (type bread)', async () => {
    const r = await fns.sellerPlaceSale.run({
      idempotencyKey: `s3_${Date.now()}`, cashPaid: 10000,
      items: [{ kind: 'bread', inventoryId: 'non1', qty: 2 }],
    }, ctxOf(SELLER));
    assert.ok(r && r.ok !== false, JSON.stringify(r));
    const orders = await db.collection('orders').get();
    assert.strictEqual(orders.size, 1);
    assert.strictEqual(orders.docs[0].data().type, 'bread');
    assert.strictEqual(orders.docs[0].data().total, 10000);
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} food guard checks passed.`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
