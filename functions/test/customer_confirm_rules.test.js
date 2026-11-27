/**
 * Mijoz tasdig'i — Firestore rules: SERVER-ONLY sozlama va kutish belgisi.
 *
 * `server_config/*` — YANGI kolleksiya, firestore.rules da `match` YO'Q => default-deny:
 * hech bir klient (mijoz, kuryer, admin, superadmin, kirmagan) o'qiy ham, yoza ham olmaydi
 * (faqat Admin SDK). Kimdir "qulaylik uchun" match qo'shsa — bu test yiqiladi.
 *
 * `module_config/customer_confirm` — ommaviy belgi (ilova so'rovni o'tkazib yuborishi uchun).
 * Kirgan foydalanuvchi o'qiydi; mijoz/kuryer yoza olmaydi. ESLATMA: `module_config/{key}` qoidasi
 * `write: isAdmin()` — admin klienti bevosita yozishi MUMKIN (belgi faqat maslahat; server
 * qarori `server_config` dan, shuning uchun bu xavfsizlikka ta'sir qilmaydi). Natija
 * pastda KUZATUV sifatida chop etiladi, yiqilmaydi.
 *
 * Kutish belgisi (`awaitingCustomerConfirm`, `hasAwaitingCustomerConfirm`, `customerConfirmed`)
 * mijoz o'qiydigan hujjatlarda: mijoz klienti ularni yoza/o'chira olmaydi.
 *
 *   firebase emulators:exec --only firestore --project demo-customer-confirm-rules \
 *     "node test/customer_confirm_rules.test.js"
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
const OTHER = '998909990001';
const COURIER = '998905556677';
const COURIER_ACC = 'accCOURIER0000000000A';

const results = [];
async function check(name, fn) {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
}

async function main() {
  const env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || 'demo-customer-confirm-rules',
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '..', '..', 'firestore.rules'), 'utf8'),
      host: HOST, port: Number(PORT),
    },
  });
  const marker = { step: 'x', courierId: COURIER };
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${SUPER}`).set({ role: 'superadmin' });
    await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
    await db.doc(`users/${CUSTOMER}`).set({ role: 'user' });
    await db.doc(`users/${OTHER}`).set({ role: 'user' });
    await db.doc(`users/${COURIER}`).set({ role: 'user', accountId: COURIER_ACC });
    await db.doc(`provider_capabilities/${COURIER_ACC}`).set({
      identity: { accountId: COURIER_ACC, primaryUid: COURIER }, courier: { active: true }, status: { courier: 'approved' },
    });
    await db.doc('server_config/customer_confirm').set({ modules: { carpet: { stage: 'public' } }, testerIds: [CUSTOMER], version: 1 });
    await db.doc('module_config/customer_confirm').set({ enabled: true });
    await db.doc('orders/o1').set({
      type: 'restaurant', userPhone: CUSTOMER, courierId: COURIER, restaurantStatus: 'arrived', status: 'in_delivery',
      awaitingCustomerConfirm: marker, hasAwaitingCustomerConfirm: true,
    });
    await db.doc('carpet_wash_orders/c1').set({
      customerId: CUSTOMER, customerPhone: CUSTOMER, status: 'pickup_in_delivery', pickupCourierId: COURIER,
      awaitingCustomerConfirm: marker, hasAwaitingCustomerConfirm: true,
    });
    await db.doc('agro_pickup_orders/a1').set({
      customerId: CUSTOMER, customerPhone: CUSTOMER, status: 'pickup_in_delivery', pickupCourierId: COURIER,
      awaitingCustomerConfirm: marker, hasAwaitingCustomerConfirm: true,
    });
    await db.doc('collection_tasks/t1').set({
      customerPhone: CUSTOMER, customerUid: CUSTOMER, courierId: COURIER, status: 'collecting',
      awaitingCustomerConfirm: marker, hasAwaitingCustomerConfirm: true,
    });
  });
  const as = (p) => env.authenticatedContext(`uid_${p}`, { phone_number: `+${p}` }).firestore();
  const anon = () => env.unauthenticatedContext().firestore();
  const WHO = {
    mijoz: () => as(CUSTOMER),
    'begona mijoz': () => as(OTHER),
    kuryer: () => as(COURIER),
    admin: () => as(ADMIN),
    superadmin: () => as(SUPER),
    kirmagan: () => anon(),
  };

  await check('R0 nazorat: rules yuklangan (settings/prices hamma uchun o\'qiladi)', async () => {
    await assertSucceeds(anon().doc('settings/prices').get());
  });
  for (const [name, ctx] of Object.entries(WHO)) {
    await check(`S-${name}: server_config o'qish (get/list) - RAD`, async () => {
      await assertFails(ctx().doc('server_config/customer_confirm').get());
      await assertFails(ctx().collection('server_config').get());
    });
    await check(`S-${name}: server_config yozish (create/update/merge/delete) - RAD`, async () => {
      await assertFails(ctx().doc('server_config/customer_confirm').set({ modules: { carpet: { stage: 'public' } } }));
      await assertFails(ctx().doc('server_config/customer_confirm').update({ testerIds: [] }));
      await assertFails(ctx().doc('server_config/customer_confirm').set({ testerIds: [OTHER] }, { merge: true }));
      await assertFails(ctx().doc('server_config/customer_confirm').delete());
      await assertFails(ctx().doc('server_config/yangi').set({ x: 1 }));
    });
  }
  await check('S-hujjat o\'zgarmadi (Admin SDK bilan)', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const d = (await ctx.firestore().doc('server_config/customer_confirm').get()).data();
      if (d.version !== 1 || d.testerIds.length !== 1) throw new Error(JSON.stringify(d));
    });
  });
  await check('M1 module_config/customer_confirm: kirgan o\'qiydi, kirmagan o\'qiy olmaydi', async () => {
    for (const w of ['mijoz', 'begona mijoz', 'kuryer', 'admin', 'superadmin']) {
      await assertSucceeds(WHO[w]().doc('module_config/customer_confirm').get());
    }
    await assertFails(anon().doc('module_config/customer_confirm').get());
  });
  await check('M2 module_config/customer_confirm: mijoz va kuryer yoza olmaydi', async () => {
    for (const w of ['mijoz', 'begona mijoz', 'kuryer', 'kirmagan']) {
      await assertFails(WHO[w]().doc('module_config/customer_confirm').set({ enabled: false }));
      await assertFails(WHO[w]().doc('module_config/customer_confirm').update({ enabled: false }));
      await assertFails(WHO[w]().doc('module_config/customer_confirm').delete());
    }
  });
  await check('M3 KUZATUV: admin klienti ommaviy belgini bevosita yoza oladimi (faqat chop etiladi)', async () => {
    let allowed = true;
    try { await assertSucceeds(as(ADMIN).doc('module_config/customer_confirm').set({ enabled: true })); } catch (e) { allowed = false; }
    console.log(`   KUZATUV: admin klienti module_config/customer_confirm ga yoza oladi = ${allowed} (server qarori server_config dan)`);
  });
  const DOCS = ['orders/o1', 'carpet_wash_orders/c1', 'agro_pickup_orders/a1', 'collection_tasks/t1'];
  for (const p of DOCS) {
    await check(`D-${p}: mijoz o'z hujjatini o'qiydi (belgi ko'rinadi), lekin belgini yoza/o'chira/o'zgartira OLMAYDI`, async () => {
      const snap = await assertSucceeds(as(CUSTOMER).doc(p).get());
      if (!snap.data().awaitingCustomerConfirm) throw new Error('mijoz belgini ko\'rmadi');
      await assertFails(as(CUSTOMER).doc(p).update({ awaitingCustomerConfirm: { step: 'x', courierId: CUSTOMER } }));
      await assertFails(as(CUSTOMER).doc(p).update({ hasAwaitingCustomerConfirm: false }));
      await assertFails(as(CUSTOMER).doc(p).update({ customerConfirmed: { x: { courierId: CUSTOMER } } }));
      await assertFails(as(CUSTOMER).doc(p).set({ userPhone: CUSTOMER, customerPhone: CUSTOMER, awaitingCustomerConfirm: {} }, { merge: true }));
      await assertFails(as(CUSTOMER).doc(p).delete());
    });
    await check(`D-${p}: begona mijoz o'qiy ham, yoza ham olmaydi`, async () => {
      await assertFails(as(OTHER).doc(p).get());
      await assertFails(as(OTHER).doc(p).update({ hasAwaitingCustomerConfirm: false }));
    });
  }

  await env.cleanup();
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} customer_confirm rules checks passed.`);
  process.exit(failed ? 1 : 0);
}
main().catch((e) => { console.error('FATAL', e); process.exit(1); });
