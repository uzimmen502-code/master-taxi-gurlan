/**
 * `reports` — ресторан/таом/кўчмас мулк шикояти (restaurant_content, realty_content) мижоз ЁЗОЛМАЙДИ;
 * мавжуд турлар хатти-ҳаракати ўзгармаган; `report_open_keys` (CF қулфи) ёпиқ. 2026-10-25.
 *
 *   firebase emulators:exec --only firestore --project demo-content-complaints-rules \
 *     "node test/content_complaints_rules.test.js"
 *   (бошқа қоида матнини синаш: RULES_FILE=<йўл>)
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { serverTimestamp } = require('firebase/firestore');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080').split(':');

const ADMIN = '998901110000';
const USER = '998913100001';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-content-complaints-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  async function check(name, fn) {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }
  const as = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const anon = () => testEnv.unauthenticatedContext().firestore();
  const seed = (fn) => testEnv.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));

  await testEnv.clearFirestore();
  await seed(async (db) => {
    await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
    await db.doc(`users/${USER}`).set({ role: 'user' });
    await db.doc('reports/r_open').set({ type: 'restaurant_content', targetType: 'restaurant', targetId: 'r1', reporterId: USER, reason: 'fraud', status: 'open' });
    await db.doc('report_open_keys/k1').set({ reportId: 'r_open', type: 'restaurant_content' });
  });
  const report = (type, extra = {}) => ({ type, targetType: 'restaurant', targetId: 'r1', reporterId: USER, reason: 'fraud', comment: '', status: 'open', createdAt: serverTimestamp(), ...extra });

  await check('R1 restaurant_content / realty_content: mijoz bevosita yaratolmaydi (add va set, o\'z nomidan ham)', async () => {
    await assertFails(as(USER).collection('reports').add(report('restaurant_content')));
    await assertFails(as(USER).collection('reports').add(report('restaurant_content', { targetType: 'restaurant_item', restaurantId: 'r1' })));
    await assertFails(as(USER).collection('reports').add(report('realty_content', { targetType: 'realty_listing' })));
    await assertFails(as(USER).doc('reports/my_fixed_id').set(report('realty_content')));
    await assertFails(anon().collection('reports').add(report('restaurant_content')));
  });

  await check('R2 mavjud server turlari avvalgidek yopiq: shop_content, market_ad, dating_profile', async () => {
    for (const t of ['shop_content', 'market_ad', 'dating_profile']) {
      await assertFails(as(USER).collection('reports').add(report(t)));
    }
  });

  await check('R3 mavjud mijoz turlari avvalgidek ochiq: tv_clip, yuk_listing, turi yo\'q (circles); loginsiz — yo\'q', async () => {
    await assertSucceeds(as(USER).collection('reports').add({ type: 'tv_clip', targetId: 'c1', reporterId: USER, reason: 'spam' }));
    await assertSucceeds(as(USER).collection('reports').add({ type: 'yuk_listing', module: 'yuk_intercity', listingId: 'y1', reporterId: USER }));
    await assertSucceeds(as(USER).collection('reports').add({ module: 'circles', circleId: 'c1', targetType: 'post', reporterId: USER }));
    await assertFails(anon().collection('reports').add({ type: 'tv_clip', targetId: 'c1' }));
  });

  await check('R4 shikoyatni oddiy foydalanuvchi o\'qiy/yopa/o\'chira olmaydi (o\'ziniki ham); admin o\'qiydi', async () => {
    await assertFails(as(USER).doc('reports/r_open').get());
    await assertFails(as(USER).doc('reports/r_open').update({ status: 'resolved' }));
    await assertFails(as(USER).doc('reports/r_open').delete());
    await assertFails(as(USER).collection('reports').where('type', '==', 'restaurant_content').get());
    await assertSucceeds(as(ADMIN).doc('reports/r_open').get());
    await assertSucceeds(as(ADMIN).collection('reports').where('type', '==', 'restaurant_content').where('status', '==', 'open').get());
  });

  await check('R5 report_open_keys (CF qulfi): hech kim o\'qiy/yoza olmaydi (admin ham — faqat Admin SDK)', async () => {
    await assertFails(as(USER).doc('report_open_keys/k1').get());
    await assertFails(as(USER).doc('report_open_keys/k1').set({ reportId: 'x' }));
    await assertFails(as(USER).doc('report_open_keys/k1').delete());
    await assertFails(as(ADMIN).doc('report_open_keys/k1').get());
    await assertFails(as(ADMIN).doc('report_open_keys/k2').set({ reportId: 'x' }));
    await assertFails(anon().doc('report_open_keys/k1').get());
  });

  await testEnv.cleanup();
  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
