/**
 * users/{userId}/favorites/{favId} — «Бозорлар» STAGE 10 ❤ Танланганлар (ega 2026-11-15).
 *
 *   firebase emulators:exec --only firestore --project demo-user-favorites \
 *     "node test/user_favorites_rules.test.js"
 *   (boshqa qoida matnini sinash: RULES_FILE=<yo'l>)
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { serverTimestamp, Timestamp } = require('firebase/firestore');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080').split(':');

const OWNER = '998911000001';
const OTHER = '998911000002';

function fav(extra = {}) {
  return {
    collection: 'tv_shop_items',
    itemId: 'item1',
    title: 'Non',
    photoUrl: 'https://x/a.jpg',
    price: 5000,
    priceUnit: 'piece',
    market: 'farm',
    addedAt: serverTimestamp(),
    ...extra,
  };
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-user-favorites',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  async function check(name, fn) {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }
  const as = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const anonAuth = () => testEnv.authenticatedContext('anon_uid', { firebase: { sign_in_provider: 'anonymous' } }).firestore();
  const unauth = () => testEnv.unauthenticatedContext().firestore();
  const seed = (fn) => testEnv.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));
  const p = (u, id) => `users/${u}/favorites/${id}`;

  await testEnv.clearFirestore();
  await seed(async (db) => {
    await db.doc(`users/${OWNER}`).set({ role: 'user' });
    await db.doc(`users/${OTHER}`).set({ role: 'user' });
    await db.doc(p(OWNER, 'ads_seeded')).set({ collection: 'ads', itemId: 'seeded', title: 'x', addedAt: Timestamp.now() });
  });

  // Positive
  await check('owner creates full doc', () => assertSucceeds(as(OWNER).doc(p(OWNER, 'tv_shop_items_item1')).set(fav())));
  await check('owner creates minimal doc (no optional fields)', () => assertSucceeds(as(OWNER).doc(p(OWNER, 'realty_listings_r1'))
    .set({ collection: 'realty_listings', itemId: 'r1', title: '', addedAt: serverTimestamp() })));
  for (const c of ['wholesale_products', 'ads']) {
    await check(`owner creates collection=${c}`, () => assertSucceeds(as(OWNER).doc(p(OWNER, `${c}_z`)).set(fav({ collection: c, itemId: 'z' }))));
  }
  await check('owner reads own doc', () => assertSucceeds(as(OWNER).doc(p(OWNER, 'ads_seeded')).get()));
  await check('owner lists own favorites', () => assertSucceeds(as(OWNER).collection(`users/${OWNER}/favorites`).get()));
  await check('owner deletes own doc', () => assertSucceeds(as(OWNER).doc(p(OWNER, 'ads_seeded')).delete()));
  await check('boundary: price 0 and 999999999', async () => {
    await assertSucceeds(as(OWNER).doc(p(OWNER, 'ads_p0')).set(fav({ collection: 'ads', itemId: 'p0', price: 0 })));
    await assertSucceeds(as(OWNER).doc(p(OWNER, 'ads_pmax')).set(fav({ collection: 'ads', itemId: 'pmax', price: 999999999 })));
  });
  await check('boundary: itemId 128 chars, title 200', () => assertSucceeds(as(OWNER).doc(p(OWNER, `ads_${'a'.repeat(128)}`))
    .set(fav({ collection: 'ads', itemId: 'a'.repeat(128), title: 't'.repeat(200) }))));

  // Other user
  await check('other user cannot read', () => assertFails(as(OTHER).doc(p(OWNER, 'tv_shop_items_item1')).get()));
  await check('other user cannot list', () => assertFails(as(OTHER).collection(`users/${OWNER}/favorites`).get()));
  await check('other user cannot create in owner list', () => assertFails(as(OTHER).doc(p(OWNER, 'ads_o')).set(fav({ collection: 'ads', itemId: 'o' }))));
  await check('other user cannot delete', () => assertFails(as(OTHER).doc(p(OWNER, 'tv_shop_items_item1')).delete()));

  // Guests
  await check('unauthenticated cannot read', () => assertFails(unauth().doc(p(OWNER, 'tv_shop_items_item1')).get()));
  await check('unauthenticated cannot create', () => assertFails(unauth().doc(p(OWNER, 'ads_g')).set(fav({ collection: 'ads', itemId: 'g' }))));
  await check('anonymous (no phone) cannot create', () => assertFails(anonAuth().doc(p(OWNER, 'ads_g')).set(fav({ collection: 'ads', itemId: 'g' }))));
  await check('anonymous (no phone) cannot list', () => assertFails(anonAuth().collection(`users/${OWNER}/favorites`).get()));

  // Shape
  const bad = [
    ['id mismatch', 'tv_shop_items_other', fav()],
    ['id without prefix', 'item1', fav()],
    ['extra field', 'tv_shop_items_item1x', fav({ itemId: 'item1x', ownerPhone: OWNER })],
    ['unknown collection', 'orders_o1', fav({ collection: 'orders', itemId: 'o1' })],
    ['missing title', 'ads_m1', (() => { const d = fav({ collection: 'ads', itemId: 'm1' }); delete d.title; return d; })()],
    ['missing addedAt', 'ads_m2', (() => { const d = fav({ collection: 'ads', itemId: 'm2' }); delete d.addedAt; return d; })()],
    ['client addedAt', 'ads_m3', fav({ collection: 'ads', itemId: 'm3', addedAt: Timestamp.fromMillis(1000) })],
    ['float price', 'ads_m4', fav({ collection: 'ads', itemId: 'm4', price: 10.5 })],
    ['negative price', 'ads_m5', fav({ collection: 'ads', itemId: 'm5', price: -1 })],
    ['price too big', 'ads_m6', fav({ collection: 'ads', itemId: 'm6', price: 1000000000 })],
    ['string price', 'ads_m7', fav({ collection: 'ads', itemId: 'm7', price: '5000' })],
    ['title 201', 'ads_m8', fav({ collection: 'ads', itemId: 'm8', title: 't'.repeat(201) })],
    ['photoUrl 1001', 'ads_m9', fav({ collection: 'ads', itemId: 'm9', photoUrl: 'u'.repeat(1001) })],
    ['priceUnit 21', 'ads_m10', fav({ collection: 'ads', itemId: 'm10', priceUnit: 'u'.repeat(21) })],
    ['market 21', 'ads_m11', fav({ collection: 'ads', itemId: 'm11', market: 'm'.repeat(21) })],
    ['itemId 129', `ads_${'a'.repeat(129)}`, fav({ collection: 'ads', itemId: 'a'.repeat(129) })],
    ['itemId empty', 'ads_', fav({ collection: 'ads', itemId: '' })],
    ['itemId not string', 'ads_5', fav({ collection: 'ads', itemId: 5 })],
  ];
  for (const [name, id, data] of bad) {
    await check(`deny shape: ${name}`, () => assertFails(as(OWNER).doc(p(OWNER, id)).set(data)));
  }
  await check('deny update (even same shape)', () => assertFails(as(OWNER).doc(p(OWNER, 'tv_shop_items_item1')).set(fav())));
  await check('deny update partial', () => assertFails(as(OWNER).doc(p(OWNER, 'tv_shop_items_item1')).update({ title: 'y' })));

  await testEnv.cleanup();
  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
