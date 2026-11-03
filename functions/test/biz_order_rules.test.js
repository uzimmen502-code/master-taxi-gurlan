/**
 * «Менинг бизнесим» буюртмаси — Firestore rules (эга 2026-11-03; патч: biz_order_rules.patch).
 *
 *   RULES_FILE=<патчланган firestore.rules> firebase emulators:exec --only firestore --project demo-biz-rules \
 *     "node test/biz_order_rules.test.js"
 *
 * Қулфланади:
 *   - `orders` (type business): сотувчи (`sellerUid`) get ва `where sellerUid == ўзи` list; бошқа сотувчи
 *     филтри / филтрсиз list — йўқ; харидор get (мавжуд userPhone қоидаси); бегона — йўқ; сотувчи ёзолмайди
 *   - телефонсиз токен (аноним) бўш `sellerUid` ҳужжатни ҳам, бизнес буюртмасини ҳам ўқий олмайди
 *   - `order_events`: сотувчи ўқийди, бегона йўқ; `private/secrets` (олиб кетиш коди): сотувчи ўқийди,
 *     харидор ва бегона йўқ
 *   - `order_courier_live`: фаол бизнес буюртмасида сотувчи ўқийди; якунланганда — йўқ
 */
'use strict';
const path = require('path');
const fs = require('fs');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const SELLER = '998941000001';
const SELLER2 = '998941000002';
const BUYER = '998942000001';
const STRANGER = '998944000001';
const COURIER = '998943000001';

async function main() {
  console.log(`rules: ${RULES_PATH}`);
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-biz-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  async function check(name, fn) {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.code || ''} ${e.message || String(e)}`);
    }
  }
  const as = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const noPhone = () => testEnv.authenticatedContext('anon_uid', {}).firestore();

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const u of [SELLER, SELLER2, BUYER, STRANGER, COURIER]) await db.doc(`users/${u}`).set({ role: 'user' });
    await db.doc('orders/bo1').set({ type: 'business', sellerUid: SELLER, userPhone: BUYER, businessStatus: 'accepted', courierId: COURIER, total: 1000 });
    await db.doc('orders/bo2').set({ type: 'business', sellerUid: SELLER2, userPhone: BUYER, businessStatus: 'placed', total: 1000 });
    await db.doc('orders/bo3').set({ type: 'business', sellerUid: SELLER, userPhone: BUYER, businessStatus: 'delivered', total: 1000 });
    await db.doc('orders/bread1').set({ type: 'bread', userPhone: STRANGER, status: 'new', total: 500 });
    await db.doc('orders/bo1/private/secrets').set({ pickupCode: '1234' });
    await db.doc('orders/bo1/order_events/e1').set({ to: 'placed' });
    await db.doc('order_courier_live/bo1').set({ orderId: 'bo1', lat: 41, lng: 60 });
    await db.doc('order_courier_live/bo3').set({ orderId: 'bo3', lat: 41, lng: 60 });
  });

  await check('сотувчи ўз буюртмасини get; бошқа сотувчиникини — йўқ; нон буюртмасини — йўқ', async () => {
    await assertSucceeds(as(SELLER).doc('orders/bo1').get());
    await assertFails(as(SELLER).doc('orders/bo2').get());
    await assertFails(as(SELLER).doc('orders/bread1').get());
  });
  await check('харидор list `where userPhone == ўзи` (мавжуд қоида бузилмади)', async () => {
    await assertSucceeds(as(BUYER).collection('orders').where('userPhone', '==', BUYER).get());
  });
  await check('сотувчи list: `where sellerUid == ўзи` — мумкин', async () => {
    await assertSucceeds(as(SELLER).collection('orders').where('sellerUid', '==', SELLER).get());
  });
  await check('сотувчи list: бошқа сотувчи филтри — йўқ', async () => {
    await assertFails(as(SELLER).collection('orders').where('sellerUid', '==', SELLER2).get());
  });
  await check('сотувчи list: филтрсиз / фақат type — йўқ', async () => {
    await assertFails(as(SELLER).collection('orders').get());
    await assertFails(as(SELLER).collection('orders').where('type', '==', 'business').get());
  });
  await check('харидор get (мавжуд userPhone қоидаси); бегона — йўқ', async () => {
    await assertSucceeds(as(BUYER).doc('orders/bo1').get());
    await assertFails(as(STRANGER).doc('orders/bo1').get());
  });
  await check('телефонсиз токен: бўш sellerUid (нон) ва бизнес буюртмаси — йўқ; sellerUid == "" list — йўқ', async () => {
    await assertFails(noPhone().doc('orders/bread1').get());
    await assertFails(noPhone().doc('orders/bo1').get());
    await assertFails(noPhone().collection('orders').where('sellerUid', '==', '').get());
  });
  await check('сотувчи буюртмани ЁЗОЛМАЙДИ (фақат CF)', async () => {
    await assertFails(as(SELLER).doc('orders/bo1').update({ businessStatus: 'delivered' }));
    await assertFails(as(SELLER).doc('orders/bo1').update({ total: 1 }));
  });
  await check('private/secrets: сотувчи ўқийди; харидор, курьер, бегона — йўқ; ҳеч ким ёзолмайди', async () => {
    await assertSucceeds(as(SELLER).doc('orders/bo1/private/secrets').get());
    await assertFails(as(BUYER).doc('orders/bo1/private/secrets').get());
    await assertFails(as(COURIER).doc('orders/bo1/private/secrets').get());
    await assertFails(as(STRANGER).doc('orders/bo1/private/secrets').get());
    await assertFails(as(SELLER2).doc('orders/bo1/private/secrets').get());
    await assertFails(as(SELLER).doc('orders/bo1/private/secrets').set({ pickupCode: '0000' }));
  });
  await check('order_events: сотувчи ва харидор ўқийди; бегона — йўқ', async () => {
    await assertSucceeds(as(SELLER).doc('orders/bo1/order_events/e1').get());
    await assertSucceeds(as(BUYER).doc('orders/bo1/order_events/e1').get());
    await assertFails(as(STRANGER).doc('orders/bo1/order_events/e1').get());
  });
  await check('order_courier_live: фаол бизнес буюртмасида сотувчи ва харидор ўқийди; якунланганда — йўқ; бегона — йўқ', async () => {
    await assertSucceeds(as(SELLER).doc('order_courier_live/bo1').get());
    await assertSucceeds(as(BUYER).doc('order_courier_live/bo1').get());
    await assertFails(as(STRANGER).doc('order_courier_live/bo1').get());
    await assertFails(as(SELLER).doc('order_courier_live/bo3').get());
  });

  await testEnv.cleanup();
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
