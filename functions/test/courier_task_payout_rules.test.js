/**
 * Kuryer vazifa haqi (D5) - Firestore rules: maxfiylik qulfi.
 *
 * `courier_task_payouts/{modul}_{vazifaId}` - kuryerga to'lanadigan haq (ICHKI xarajat,
 * CLAUDE.md 14). Kolleksiyaga firestore.rules'da `match` YO'Q => default-deny: hech bir klient
 * (mijoz, kuryer, begona kuryer, admin, superadmin, kirmagan) o'qiy ham, yoza ham olmaydi;
 * faqat Admin SDK (Cloud Functions). Kimdir "qulaylik uchun" match qo'shsa - bu test yiqiladi.
 *
 *   firebase emulators:exec --only firestore --project demo-courier-payout-rules \
 *     "node test/courier_task_payout_rules.test.js"
 */
'use strict';
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');

const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080').split(':');
const SUPER = '998901112255';
const ADMIN = '998901112233';
const CUSTOMER = '998909990000';
const COURIER = '998905556677';
const COURIER_ACC = 'accCOURIER0000000000A';
const OTHER_COURIER = '998906667788';
const OTHER_ACC = 'accCOURIER0000000000B';

const results = [];
async function check(name, fn) {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
}

async function main() {
  const env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || 'demo-courier-payout-rules',
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '..', '..', 'firestore.rules'), 'utf8'),
      host: HOST, port: Number(PORT),
    },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${SUPER}`).set({ role: 'superadmin' });
    await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
    await db.doc(`users/${CUSTOMER}`).set({ role: 'user' });
    await db.doc(`users/${COURIER}`).set({ role: 'user', accountId: COURIER_ACC });
    await db.doc(`users/${OTHER_COURIER}`).set({ role: 'user', accountId: OTHER_ACC });
    await db.doc(`provider_capabilities/${COURIER_ACC}`).set({
      identity: { accountId: COURIER_ACC, primaryUid: COURIER }, courier: { active: true }, status: { courier: 'approved' },
    });
    await db.doc(`provider_capabilities/${OTHER_ACC}`).set({
      identity: { accountId: OTHER_ACC, primaryUid: OTHER_COURIER }, courier: { active: true }, status: { courier: 'approved' },
    });
    // Vazifa hujjati (mijoz o'qiydi) va server yozgan haq hujjatlari.
    await db.doc('carpet_wash_orders/c1').set({ customerId: CUSTOMER, customerPhone: CUSTOMER, status: 'completed', finalPrice: 40000, returnCourierId: COURIER });
    await db.doc('courier_task_payouts/carpet_c1').set({ module: 'carpet', taskId: 'c1', courierId: COURIER, payout: 6000, bps: 1500, version: 3, base: 40000, reason: null });
    await db.doc('collection_tasks/t1').set({ customerId: CUSTOMER, courierId: COURIER, status: 'completed', finalValue: 50000 });
    await db.doc('courier_task_payouts/collection_t1').set({ module: 'collection', taskId: 't1', courierId: COURIER, payout: 2500, bps: 500, version: 7, base: 50000, reason: null });
  });
  const as = (p) => env.authenticatedContext(`uid_${p}`, { phone_number: `+${p}` }).firestore();
  const anon = () => env.unauthenticatedContext().firestore();
  const WHO = {
    mijoz: () => as(CUSTOMER),
    'vazifa kuryeri': () => as(COURIER),
    'begona kuryer': () => as(OTHER_COURIER),
    admin: () => as(ADMIN),
    superadmin: () => as(SUPER),
    kirmagan: () => anon(),
  };

  await check('R0 nazorat: rules yuklangan (settings/prices hamma uchun o\'qiladi)', async () => {
    await assertSucceeds(anon().doc('settings/prices').get());
  });
  for (const [name, ctx] of Object.entries(WHO)) {
    await check(`P-${name}: courier_task_payouts o'qish (get/list) - RAD`, async () => {
      await assertFails(ctx().doc('courier_task_payouts/carpet_c1').get());
      await assertFails(ctx().doc('courier_task_payouts/collection_t1').get());
      await assertFails(ctx().collection('courier_task_payouts').get());
      await assertFails(ctx().collection('courier_task_payouts').where('courierId', '==', COURIER).get());
    });
    await check(`P-${name}: courier_task_payouts yozish (create/update/delete) - RAD`, async () => {
      await assertFails(ctx().doc('courier_task_payouts/carpet_new').set({ payout: 1 }));
      await assertFails(ctx().doc('courier_task_payouts/carpet_c1').update({ payout: 99999 }));
      await assertFails(ctx().doc('courier_task_payouts/carpet_c1').delete());
    });
  }
  await check('P-hujjat o\'zgarmadi (yozuvlar rad etilgani Admin SDK bilan tasdiqlandi)', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const d = (await ctx.firestore().doc('courier_task_payouts/carpet_c1').get()).data();
      if (d.payout !== 6000) throw new Error(`payout ${d.payout}`);
    });
  });
  await check('T1 vazifa hujjati: mijoz o\'z gilam buyurtmasini o\'qiydi - unda courierPayout* maydoni yo\'q', async () => {
    const snap = await assertSucceeds(as(CUSTOMER).doc('carpet_wash_orders/c1').get());
    const keys = Object.keys(snap.data()).filter((k) => /^courierPayout/.test(k));
    if (keys.length) throw new Error(`oqib chiqqan maydonlar: ${keys}`);
  });

  await env.cleanup();
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} courier_task_payout rules checks passed.`);
  process.exit(failed ? 1 : 0);
}
main().catch((e) => { console.error('FATAL', e); process.exit(1); });