/**
 * «AVA Супермаркет» — firestore.rules: platform_products sm майдонлари, private/cost, settings/supermarket, taxonomy.
 *
 *   firebase emulators:exec --only firestore --project demo-supermarket-rules "node test/supermarket_rules.test.js"
 *   (RULES_PATH билан бошқа файл, масалан stripped build, текширилади)
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_PATH || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
const USER = '998901000001';
const ADMIN = '998909990001';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-supermarket-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  console.log(`rules: ${RULES_PATH}`);
  const results = [];
  const check = async (n, fn) => {
    try { await fn(); results.push(true); console.log(`PASS - ${n}`); } catch (e) { results.push(false); console.log(`FAIL - ${n} :: ${e.message}`); }
  };
  const ctx = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const user = ctx(USER);
  const adm = ctx(ADMIN);
  const anon = testEnv.unauthenticatedContext().firestore();

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
    await db.doc(`users/${USER}`).set({ role: 'user' });
    await db.doc('platform_products/legacy').set({ name: 'Эски', price: 1000, active: true, goodsKind: 'food' });
    await db.doc('platform_products/sm1').set({ name: 'Мол гўшти', price: 80000, smGroupId: 'beef', smStatus: 'active', stock: 10, active: false, goodsKind: 'food' });
    await db.doc('platform_products/sm1/private/cost').set({ purchasePrice: 70000, supplier: 'X' });
    await db.doc('settings/supermarket').set({ stage: 'internal', testerIds: [USER] });
    await db.doc('settings/app').set({ platformDeliveryFeePercent: 11 });
    await db.doc('taxonomy/supermarket').set({ version: 1, categories: [] });
    await db.doc('taxonomy_history/supermarket_v1').set({ version: 1 });
  });

  await check('R1 platform_products ўқиш — ҳамма; private/cost — фақат админ ўқийди, ҳеч ким ёзмайди', async () => {
    await assertSucceeds(anon.doc('platform_products/sm1').get());
    await assertSucceeds(user.doc('platform_products/sm1').get());
    await assertFails(anon.doc('platform_products/sm1/private/cost').get());
    await assertFails(user.doc('platform_products/sm1/private/cost').get());
    await assertSucceeds(adm.doc('platform_products/sm1/private/cost').get());
    await assertFails(adm.doc('platform_products/sm1/private/cost').set({ purchasePrice: 1, supplier: 'Y' }));
    await assertFails(user.doc('platform_products/sm1/private/cost').set({ purchasePrice: 1, supplier: 'Y' }));
    await assertFails(user.collection('platform_products/sm1/private').get());
  });

  await check('R2 мижоз platform_products ёзолмайди (sm майдонлари ҳам)', async () => {
    await assertFails(user.doc('platform_products/sm1').update({ stock: 999 }));
    await assertFails(user.doc('platform_products/legacy').update({ price: 1 }));
    await assertFails(user.doc('platform_products/new1').set({ name: 'x', price: 1 }));
    await assertFails(anon.doc('platform_products/sm1').update({ price: 1 }));
  });

  await check('R3 админ эски ҳужжат: аввалгидек (яратиш/нарх/ўчириш), лекин sm майдон қўшолмайди', async () => {
    await assertSucceeds(adm.doc('platform_products/legacy').update({ price: 1200, active: false }));
    await assertSucceeds(adm.doc('platform_products/new2').set({ name: 'Янги', price: 5000, active: true }));
    await assertFails(adm.doc('platform_products/new3').set({ name: 'x', price: 1, smGroupId: 'beef' }));
    await assertFails(adm.doc('platform_products/new3').set({ name: 'x', price: 1, stock: 5 }));
    for (const f of ['smGroupId', 'smStatus', 'stock', 'qtyStep', 'weighed', 'priceUpdatedAt', 'searchTokens', 'smAutoOutOfStock', 'packQty', 'packUnit']) {
      await assertFails(adm.doc('platform_products/legacy').update({ [f]: f === 'weighed' ? true : 'x' }));
    }
    await assertSucceeds(adm.doc('platform_products/new2').delete());
  });

  await check('R4 админ супермаркет таклифи: нарх/stock/ҳолат — фақат CF; goodsKind/sortOrder — мумкин; ўчириш йўқ', async () => {
    await assertFails(adm.doc('platform_products/sm1').update({ price: 1 }));
    await assertFails(adm.doc('platform_products/sm1').update({ stock: 1000 }));
    await assertFails(adm.doc('platform_products/sm1').update({ smStatus: 'hidden' }));
    await assertFails(adm.doc('platform_products/sm1').update({ active: true }));
    await assertFails(adm.doc('platform_products/sm1').update({ smGroupId: 'pork' }));
    await assertSucceeds(adm.doc('platform_products/sm1').update({ goodsKind: 'non_food', sortOrder: 3 }));
    await assertFails(adm.doc('platform_products/sm1').delete());
  });

  await check('R5 settings/supermarket: мижоз ўқимайди (testerIds), админ ўқийди; ҳеч ким ёзмайди; settings/app ўқилади', async () => {
    await assertFails(user.doc('settings/supermarket').get());
    await assertFails(anon.doc('settings/supermarket').get());
    await assertSucceeds(adm.doc('settings/supermarket').get());
    await assertFails(adm.doc('settings/supermarket').set({ stage: 'public' }));
    await assertFails(adm.doc('settings/supermarket').update({ stage: 'public' }));
    await assertFails(user.doc('settings/supermarket').set({ stage: 'public' }));
    await assertSucceeds(user.doc('settings/app').get());
  });

  await check('R6 taxonomy/supermarket — ҳамма ўқийди, ҳеч ким ёзмайди; тарих — фақат админ ўқийди', async () => {
    await assertSucceeds(anon.doc('taxonomy/supermarket').get());
    await assertFails(adm.doc('taxonomy/supermarket').set({ version: 2, categories: [] }));
    await assertFails(user.doc('taxonomy_history/supermarket_v1').get());
    await assertSucceeds(adm.doc('taxonomy_history/supermarket_v1').get());
  });

  await testEnv.cleanup();
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
