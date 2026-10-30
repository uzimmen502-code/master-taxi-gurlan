/**
 * `wholesale_orders` o'qish va `settings/wholesale_orders` yozish qoidalari (2026-10-31).
 *
 *   RULES_FILE=<live+patch> firebase emulators:exec --only firestore \
 *     --project demo-ulg-orders-rules "node functions/test/wholesale_orders_rules.test.js"
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');

const BUYER = '998901000011';
const SELLER = '998901000012';
const OTHER = '998901000013';
const ADMIN = '998909990011';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-ulg-orders',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const record = (n, p, d) => { results.push(p); console.log(`${p ? 'PASS' : 'FAIL'} - ${n}${d ? ' :: ' + d : ''}`); };
  const check = async (n, fn) => { try { await fn(); record(n, true); } catch (e) { record(n, false, e.message); } };
  const ctx = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();

  await testEnv.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await db.collection('users').doc(ADMIN).set({ role: 'admin' });
    await db.collection('wholesale_orders').doc('o1').set({ buyerId: BUYER, sellerId: SELLER, total: 100, status: 'placed' });
    await db.collection('wholesale_orders').doc('o1').collection('private').doc('settlement').set({ avaFee: 2 });
    await db.collection('wholesale_quotes').doc('q1').set({ buyerId: BUYER, total: 100 });
  });

  const order = (db) => db.collection('wholesale_orders').doc('o1');
  await check('A1 xaridor o\'z buyurtmasini o\'qiydi', () => assertSucceeds(order(ctx(BUYER)).get()));
  await check('A2 sotuvchi o\'qiydi', () => assertSucceeds(order(ctx(SELLER)).get()));
  await check('A3 admin o\'qiydi', () => assertSucceeds(order(ctx(ADMIN)).get()));
  await check('A4 xaridor o\'z ro\'yxatini so\'raydi (buyerId ==)', () =>
    assertSucceeds(ctx(BUYER).collection('wholesale_orders').where('buyerId', '==', BUYER).get()));
  await check('B1 begona o\'qiy olmaydi', () => assertFails(order(ctx(OTHER)).get()));
  await check('B2 kirmagan o\'qiy olmaydi', () => assertFails(order(testEnv.unauthenticatedContext().firestore()).get()));
  await check('B3 xaridor yoza olmaydi (status)', () => assertFails(order(ctx(BUYER)).update({ status: 'delivered' })));
  await check('B4 sotuvchi yarata olmaydi', () =>
    assertFails(ctx(SELLER).collection('wholesale_orders').doc('x').set({ buyerId: BUYER, sellerId: SELLER })));
  await check('B5 private/settlement o\'qilmaydi (xaridor)', () =>
    assertFails(order(ctx(BUYER)).collection('private').doc('settlement').get()));
  await check('B6 kvota o\'qilmaydi', () => assertFails(ctx(BUYER).collection('wholesale_quotes').doc('q1').get()));
  await check('B7 admin ham settings/wholesale_orders ni klientdan yozolmaydi', () =>
    assertFails(ctx(ADMIN).collection('settings').doc('wholesale_orders').set({ avaFeeBps: 9000 })));
  await check('B8 begona ro\'yxatni so\'ray olmaydi', () =>
    assertFails(ctx(OTHER).collection('wholesale_orders').where('buyerId', '==', BUYER).get()));

  const passed = results.filter(Boolean).length;
  console.log(`\nwholesale_orders_rules: ${passed}/${results.length} passed`);
  await testEnv.cleanup();
  if (passed !== results.length) process.exit(1);
}

main().catch((e) => { console.error(e); process.exit(1); });
