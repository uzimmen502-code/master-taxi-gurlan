/**
 * Modul sozlamasi — Firestore rules (ega, 2026-10-08): `config/module_defaults`,
 * `geo_district_modules`, `service_area_modules` faqat `adminSaveModuleConfig`
 * (server, audit bilan) orqali yoziladi; o'qish hammaga ochiq (ilova Home).
 *
 * Ishlatish: repo ildizidan
 *   firebase emulators:exec --only firestore --project demo-module-config-rules \
 *     "node functions/test/module_config_rules.test.js"
 */
'use strict';
const path = require('path');
const fs = require('fs');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const ADMIN = '998901112233';
const SUPER = '998901112255';
const USER = '998904445566';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-module-config-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });

  const results = [];
  async function check(name, fn) {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('users').doc(ADMIN).set({ role: 'admin' });
    await db.collection('users').doc(SUPER).set({ role: 'superadmin' });
    await db.collection('users').doc(USER).set({ role: 'user' });
    await db.collection('config').doc('module_defaults').set({
      enforce: true, modules: { local_taxi: { status: 'enabled' } },
    });
    await db.collection('config').doc('home_news_badge').set({ v: 1 });
    await db.collection('geo_district_modules').doc('gurlan').set({ manualModules: [], modules: {} });
    await db.collection('service_area_modules').doc('svc_gurlan_markaz')
      .set({ manualModules: [], modules: {} });
  });
  const as = (p) => testEnv.authenticatedContext(`uid_${p}`, { phone_number: '+' + p }).firestore();
  const anon = testEnv.unauthenticatedContext().firestore();

  await check('R1 hamma o\'qiy oladi (ilova Home, mehmon ham)', async () => {
    await assertSucceeds(anon.collection('config').doc('module_defaults').get());
    await assertSucceeds(anon.collection('geo_district_modules').doc('gurlan').get());
    await assertSucceeds(anon.collection('service_area_modules').doc('svc_gurlan_markaz').get());
  });
  await check('R2 admin ham, superadmin ham module_defaults ga to\'g\'ridan-to\'g\'ri yoza olmaydi', async () => {
    for (const p of [ADMIN, SUPER]) {
      await assertFails(as(p).collection('config').doc('module_defaults')
        .set({ modules: { local_taxi: { status: 'hidden' } } }, { merge: true }));
      await assertFails(as(p).collection('config').doc('module_defaults').delete());
    }
  });
  await check('R3 tuman va MFY override — klientdan yozish yopiq', async () => {
    await assertFails(as(ADMIN).collection('geo_district_modules').doc('gurlan')
      .set({ manualModules: ['local_taxi'], modules: { local_taxi: { status: 'hidden' } } }));
    await assertFails(as(ADMIN).collection('service_area_modules').doc('svc_gurlan_markaz')
      .set({ manualModules: [], modules: {} }));
    await assertFails(as(ADMIN).collection('geo_district_modules').doc('new_district').set({ x: 1 }));
  });
  await check('R4 boshqa config hujjatlari — admin avvalgidek yoza oladi, user yo\'q', async () => {
    await assertSucceeds(as(ADMIN).collection('config').doc('home_news_badge').set({ v: 2 }));
    await assertFails(as(USER).collection('config').doc('home_news_badge').set({ v: 3 }));
  });

  await testEnv.cleanup();
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
