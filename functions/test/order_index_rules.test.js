/**
 * firestore.rules — «Барча буюртмалар» (D-ALL-5/6/9): `order_index`,
 * `admin_section_grants`, `settings/all_orders_stuck`.
 *   firebase emulators:exec --only firestore --project demo-order-index-rules \
 *     "node functions/test/order_index_rules.test.js"
 */
'use strict';
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');

const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
const SUPER = '998901112255';
const ADMIN = '998901112233';
const FIN = '998901112244';
const FIN_NOGRANT = '998901112266';
const EX_ADMIN = '998901112277'; // рухсати бор, лекин роли олинган
const USER = '998905556677';
const LEGACY_DISP = '998901112288'; // users ҳужжати 9 хонали

const results = [];
async function check(name, fn) {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
}

async function main() {
  const env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || 'demo-order-index-rules',
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '..', '..', 'firestore.rules'), 'utf8'),
      host: HOST, port: Number(PORT),
    },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${SUPER}`).set({ role: 'superadmin' });
    await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
    await db.doc(`users/${FIN}`).set({ role: 'finance' });
    await db.doc(`users/${FIN_NOGRANT}`).set({ role: 'finance' });
    await db.doc(`users/${EX_ADMIN}`).set({ role: 'user' });
    await db.doc(`users/${USER}`).set({ role: 'user' });
    await db.doc(`users/${LEGACY_DISP.slice(3)}`).set({ role: 'dispatcher' });
    await db.doc(`admin_section_grants/${FIN}`).set({ sections: ['all_orders'] });
    await db.doc(`admin_section_grants/${EX_ADMIN}`).set({ sections: ['all_orders'] });
    await db.doc(`admin_section_grants/${LEGACY_DISP}`).set({ sections: ['all_orders'] });
    await db.doc('order_index/bread_o1').set({ module: 'bread', normStatus: 'NEW' });
  });
  const as = (p) => env.authenticatedContext(`uid_${p}`, { phone_number: `+${p}` }).firestore();
  const anon = () => env.unauthenticatedContext().firestore();

  await check('O1 superadmin рухсатсиз ҳам ўқийди (get + list)', async () => {
    await assertSucceeds(as(SUPER).doc('order_index/bread_o1').get());
    await assertSucceeds(as(SUPER).collection('order_index').limit(10).get());
  });
  await check('O2 рухсати бор finance ўқийди', () => assertSucceeds(as(FIN).collection('order_index').limit(10).get()));
  await check('O3 рухсатсиз finance — рад', () => assertFails(as(FIN_NOGRANT).collection('order_index').limit(10).get()));
  await check('O4 рухсатсиз admin ҳам — рад (D-ALL-5: фақат рухсат берилганлар)', () =>
    assertFails(as(ADMIN).doc('order_index/bread_o1').get()));
  await check('O5 рухсати қолган, лекин роли олинган — рад', () =>
    assertFails(as(EX_ADMIN).doc('order_index/bread_o1').get()));
  await check('O6 эски 9 хонали users ҳужжатли dispatcher + рухсат — ўқийди', () =>
    assertSucceeds(as(LEGACY_DISP).doc('order_index/bread_o1').get()));
  await check('O7 оддий фойдаланувчи ва кирмаган — рад', async () => {
    await assertFails(as(USER).collection('order_index').limit(1).get());
    await assertFails(anon().collection('order_index').limit(1).get());
  });
  await check('O8 ҳеч ким ёзолмайди (superadmin ҳам)', async () => {
    await assertFails(as(SUPER).doc('order_index/x').set({ module: 'bread' }));
    await assertFails(as(SUPER).doc('order_index/bread_o1').update({ normStatus: 'DELIVERED' }));
    await assertFails(as(SUPER).doc('order_index/bread_o1').delete());
  });

  await check('S1 ўз рухсат ҳужжатини ўқийди; бегонасини — йўқ', async () => {
    await assertSucceeds(as(FIN).doc(`admin_section_grants/${FIN}`).get());
    await assertFails(as(FIN).doc(`admin_section_grants/${EX_ADMIN}`).get());
  });
  await check('S2 admin рўйхатни ўқийди; ҳеч ким тўғридан-тўғри ёзолмайди', async () => {
    await assertSucceeds(as(ADMIN).collection('admin_section_grants').get());
    await assertFails(as(SUPER).doc(`admin_section_grants/${FIN_NOGRANT}`).set({ sections: ['all_orders'] }));
    await assertFails(as(FIN_NOGRANT).doc(`admin_section_grants/${FIN_NOGRANT}`).set({ sections: ['all_orders'] }));
  });
  await check('S3 settings/all_orders_stuck: ўқиш очиқ, админ ёзолмайди (фақат CF)', async () => {
    await assertSucceeds(as(USER).doc('settings/all_orders_stuck').get());
    await assertFails(as(ADMIN).doc('settings/all_orders_stuck').set({ rules: {} }));
    await assertFails(as(SUPER).doc('settings/all_orders_stuck').set({ rules: {} }));
  });
  await check('S4 бошқа settings (app) — admin аввалгидек ёзади (регрессия)', () =>
    assertSucceeds(as(ADMIN).doc('settings/app').set({ orderAcceptMode: 'manual' }, { merge: true })));

  await env.cleanup();
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} order_index rules checks passed.`);
  process.exit(failed ? 1 : 0);
}
main().catch((e) => { console.error('FATAL', e); process.exit(1); });
