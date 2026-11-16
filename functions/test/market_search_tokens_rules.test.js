/**
 * Сервер қидируви (2026-11-16) — Firestore rules: `searchTokens` фақат сервер (триггер) ёзади.
 *
 *   firebase emulators:exec --only firestore --project demo-search-tokens-rules \
 *     "node test/market_search_tokens_rules.test.js"
 *   (бошқа қоида матнини синаш: RULES_FILE=<йўл>)
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { deleteField } = require('firebase/firestore');

const RULES_PATH = process.env.RULES_FILE
  ? path.resolve(process.env.RULES_FILE)
  : path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080').split(':');

const OWNER = '998901112233';
const ADMIN = '998901110000';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-search-tokens-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const check = async (name, fn) => {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  };
  const as = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const item = (extra = {}) => ({
    ownerPhone: OWNER, title: 'Sigir', description: '', price: 100, photoUrls: [], clipIds: [],
    kind: 'product', status: 'active', viewCount: 0, ...extra,
  });
  const seed = (fn) => testEnv.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));

  await testEnv.clearFirestore();
  await seed(async (db) => {
    await db.collection('users').doc(ADMIN).set({ role: 'admin' });
    await db.collection('users').doc(OWNER).set({ role: 'user', realtyOwnerKey: 'k1' });
    await db.collection('tv_shop_items').doc('i1').set(item({ searchTokens: ['sigir', 'сигир'] }));
    await db.collection('tv_shop_items').doc('i0').set(item());
    await db.collection('realty_listings').doc('r1').set({ ownerKey: 'k1', title: 'Uy', status: 'active', searchTokens: ['uy'] });
  });
  const ownerItems = () => as(OWNER).collection('tv_shop_items');

  await check('K1 эга searchTokens билан ЯРАТОЛМАЙДИ; усиз — яратади', async () => {
    await assertFails(ownerItems().doc('c1').set(item({ searchTokens: ['spam'] })));
    await assertFails(ownerItems().doc('c2').set(item({ searchTokens: [] })));
    await assertSucceeds(ownerItems().doc('c3').set(item()));
  });
  await check('K2 эга searchTokens ни ўзгартиролмайди/қўшолмайди/ўчиролмайди', async () => {
    await assertFails(ownerItems().doc('i1').update({ searchTokens: ['spam'] }));
    await assertFails(ownerItems().doc('i0').update({ searchTokens: ['spam'] }));
    await assertFails(ownerItems().doc('i1').update({ searchTokens: deleteField() }));
    await assertFails(ownerItems().doc('i1').update({ title: 'Buqa', searchTokens: ['buqa'] }));
  });
  await check('K3 эга контент таҳрири (токенга тегмасдан) — ўтади; ўчириш (status deleted) — ўтади', async () => {
    await assertSucceeds(ownerItems().doc('i1').update({ title: 'Buqa', description: 'yangi' }));
    await assertSucceeds(ownerItems().doc('i1').update({ status: 'deleted' }));
  });
  await check('K4 админ searchTokens ёза олади (мавжуд isAdmin йўли ўзгармади)', async () => {
    await assertSucceeds(as(ADMIN).collection('tv_shop_items').doc('i0').update({ searchTokens: ['x'] }));
  });
  await check('K5 realty_listings: эга (ownerKey мос) ҳам ёзолмайди — фақат админ/CF; ўқиш — auth', async () => {
    await assertFails(as(OWNER).collection('realty_listings').doc('r1').update({ searchTokens: ['spam'] }));
    await assertSucceeds(as(OWNER).collection('realty_listings').doc('r1').get());
    await assertSucceeds(as(ADMIN).collection('realty_listings').doc('r1').update({ searchTokens: ['uy2'] }));
  });
  await check('K6 очиқ ўқиш: tv_shop_items array-contains сўрови (status active) — меҳмон ҳам', async () => {
    const guest = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(guest.collection('tv_shop_items').where('status', '==', 'active').where('searchTokens', 'array-contains', 'sigir').get());
  });

  await testEnv.cleanup();
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(1); });
