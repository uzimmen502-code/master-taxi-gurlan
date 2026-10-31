/**
 * Kuryer vazifa haqi (D5) - Firestore rules: maxfiylik qulfi.
 *
 * `courier_task_payouts/{modul}_{vazifaId}` - kuryerga to'lanadigan haq (ICHKI xarajat,
 * CLAUDE.md 14). Kolleksiyaga firestore.rules'da `match` YO'Q => default-deny: hech bir klient
 * (mijoz, kuryer, begona kuryer, admin, superadmin, kirmagan) o'qiy ham, yoza ham olmaydi;
 * faqat Admin SDK (Cloud Functions). Kimdir "qulaylik uchun" match qo'shsa - bu test yiqiladi.
 *
 * settings/courier_task_payout (foizlar, ICHKI xarajat) va courier_task_payout_history:
 * klientdan o'qish ham, yozish ham taqiqlangan (admin ham) - o'zgartirish faqat
 * dminSetCourierTaskPayoutPct (versiya + tarix + admin_audit); ko'rish -
 * dminGetCourierTaskPayoutSettings. Boshqa settings/* hujjatlari o'zgarmagan (regressiya).
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
    await db.doc('settings/courier_task_payout').set({ version: 3, modules: { carpet: { bps: 1500 } }, updatedBy: ADMIN });
    await db.doc('courier_task_payout_history/v3').set({ version: 3, changedModule: 'carpet', changedBy: ADMIN });
    await db.doc('settings/app').set({ orderAcceptMode: 'auto' });
    await db.doc('settings/courier').set({ deliveryFee: 5000 });
    await db.doc('settings/restaurant_delivery').set({ base: 5000, version: 1 });
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
  // ── settings/courier_task_payout ─────────────────────────────────
  for (const [name, ctx] of Object.entries(WHO)) {
    await check(`S-${name}: settings/courier_task_payout o'qish - RAD`, async () => {
      await assertFails(ctx().doc('settings/courier_task_payout').get());
    });
    await check(`S-${name}: settings/courier_task_payout yozish (create/update/merge/delete) - RAD`, async () => {
      await assertFails(ctx().doc('settings/courier_task_payout').set({ version: 4, modules: { carpet: { bps: 9999 } } }));
      await assertFails(ctx().doc('settings/courier_task_payout').update({ 'modules.carpet.bps': 9999 }));
      await assertFails(ctx().doc('settings/courier_task_payout').set({ modules: { carpet: { bps: 9999 } } }, { merge: true }));
      await assertFails(ctx().doc('settings/courier_task_payout').delete());
    });
    await check(`H-${name}: courier_task_payout_history o'qish/yozish - RAD`, async () => {
      await assertFails(ctx().doc('courier_task_payout_history/v3').get());
      await assertFails(ctx().collection('courier_task_payout_history').get());
      await assertFails(ctx().doc('courier_task_payout_history/v4').set({ version: 4 }));
    });
  }
  await check('S-hujjat o\'zgarmadi (Admin SDK bilan)', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const d = (await ctx.firestore().doc('settings/courier_task_payout').get()).data();
      if (d.version !== 3 || d.modules.carpet.bps !== 1500) throw new Error(JSON.stringify(d));
    });
  });
  await check('S-ro\'yxat: settings kolleksiyasini so\'rab courier_task_payout ni olib bo\'lmaydi', async () => {
    for (const [name, ctx] of Object.entries(WHO)) {
      let ids = [];
      try { ids = (await ctx().collection('settings').get()).docs.map((x) => x.id); } catch (e) { ids = []; }
      if (ids.includes('courier_task_payout')) throw new Error(`: royxatda courier_task_payout bor`);
    }
  });
  // Regressiya: ilova o'qiydigan / admin yozadigan boshqa settings hujjatlari ISHLAYDI.
  await check('G1 settings/app: hamma o\'qiydi, admin yozadi (regressiya)', async () => {
    await assertSucceeds(as(CUSTOMER).doc('settings/app').get());
    await assertSucceeds(anon().doc('settings/app').get());
    await assertSucceeds(as(ADMIN).doc('settings/app').set({ orderAcceptMode: 'manual' }, { merge: true }));
    await assertFails(as(CUSTOMER).doc('settings/app').set({ orderAcceptMode: 'x' }, { merge: true }));
  });
  await check('G2 settings/prices, settings/splash, settings/oil_change: o\'qish ochiq; admin yozadi (regressiya)', async () => {
    for (const id of ['prices', 'splash', 'oil_change']) {
      await assertSucceeds(anon().doc(`settings/${id}`).get());
      await assertSucceeds(as(ADMIN).doc(`settings/${id}`).set({ x: 1 }, { merge: true }));
    }
  });
  await check('G3 settings/courier (alohida match): kirgan o\'qiydi, admin yozadi (regressiya)', async () => {
    await assertSucceeds(as(COURIER).doc('settings/courier').get());
    await assertSucceeds(as(ADMIN).doc('settings/courier').set({ deliveryFee: 6000 }, { merge: true }));
    await assertFails(as(COURIER).doc('settings/courier').set({ deliveryFee: 1 }, { merge: true }));
  });
  await check('G4 settings/restaurant_delivery: o\'qish ochiq, klient yozmaydi (o\'zgarmagan)', async () => {
    await assertSucceeds(as(CUSTOMER).doc('settings/restaurant_delivery').get());
    await assertFails(as(ADMIN).doc('settings/restaurant_delivery').set({ base: 1 }, { merge: true }));
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