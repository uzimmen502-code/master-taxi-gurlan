/**
 * «Splash реклама» — Firestore rules (эга 2026-11-28).
 *
 *   firebase emulators:exec --only firestore --project demo-splash-ads-rules "node test/splash_ads_rules.test.js"
 *
 *   splash_ads/{id}          — ҳамма фақат visible==true ни ўқийди (кирмаган ҳам); админ ҳаммасини; ёзиш йўқ (фақат CF)
 *   splash_ad_stats/{id}     — фақат админ ўқийди; ёзиш йўқ
 *   splash_ad_imp_log/{id}   — ҳеч ким
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, collection, query, where } = require('firebase/firestore');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const USER = '998904445566';
const ADMIN = '998901112233';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-splash-ads-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  async function check(name, fn) {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }
  const as = (p) => testEnv.authenticatedContext(`u${p}`, { phone_number: `+${p}` }).firestore();
  const anon = () => testEnv.unauthenticatedContext().firestore();

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `users/${ADMIN}`), { role: 'admin' });
    await setDoc(doc(db, `users/${USER}`), { role: 'user' });
    await setDoc(doc(db, 'splash_ads/on'), { title: 'On', visible: true, active: true, priority: 1 });
    await setDoc(doc(db, 'splash_ads/off'), { title: 'Off', visible: false, active: false, priority: 1 });
    await setDoc(doc(db, 'splash_ad_stats/on_2026-11-27'), { adId: 'on', impressions: 3 });
    await setDoc(doc(db, `splash_ad_imp_log/${USER}_2026-11-27`), { n: 3 });
  });

  await check('R1 splash_ads: visible==true — кирмаган ва фойдаланувчи ўқийди (get + visible сўрови)', async () => {
    await assertSucceeds(getDoc(doc(anon(), 'splash_ads/on')));
    await assertSucceeds(getDoc(doc(as(USER), 'splash_ads/on')));
    await assertSucceeds(getDocs(query(collection(anon(), 'splash_ads'), where('visible', '==', true))));
  });
  await check('R2 splash_ads: ўчиқ рекламани ва филтрсиз рўйхатни фойдаланувчи ўқий олмайди; админ ўқийди', async () => {
    await assertFails(getDoc(doc(anon(), 'splash_ads/off')));
    await assertFails(getDoc(doc(as(USER), 'splash_ads/off')));
    await assertFails(getDocs(collection(as(USER), 'splash_ads')));
    await assertSucceeds(getDoc(doc(as(ADMIN), 'splash_ads/off')));
    await assertSucceeds(getDocs(collection(as(ADMIN), 'splash_ads')));
  });
  await check('R3 splash_ads: ҳеч ким тўғридан-тўғри ёза олмайди (админ ҳам — фақат CF, аудит)', async () => {
    await assertFails(setDoc(doc(as(ADMIN), 'splash_ads/new'), { title: 'x', visible: true }));
    await assertFails(updateDoc(doc(as(ADMIN), 'splash_ads/on'), { priority: 9 }));
    await assertFails(deleteDoc(doc(as(ADMIN), 'splash_ads/on')));
    await assertFails(setDoc(doc(as(USER), 'splash_ads/new'), { title: 'x', visible: true }));
  });
  await check('R4 splash_ad_stats: фақат админ ўқийди; ёзиш йўқ', async () => {
    await assertSucceeds(getDoc(doc(as(ADMIN), 'splash_ad_stats/on_2026-11-27')));
    await assertFails(getDoc(doc(as(USER), 'splash_ad_stats/on_2026-11-27')));
    await assertFails(setDoc(doc(as(USER), 'splash_ad_stats/on_2026-11-28'), { adId: 'on', impressions: 999 }));
    await assertFails(setDoc(doc(as(ADMIN), 'splash_ad_stats/on_2026-11-28'), { adId: 'on', impressions: 1 }));
  });
  await check('R5 splash_ad_imp_log: ёпиқ (админ ҳам)', async () => {
    await assertFails(getDoc(doc(as(ADMIN), `splash_ad_imp_log/${USER}_2026-11-27`)));
    await assertFails(getDoc(doc(as(USER), `splash_ad_imp_log/${USER}_2026-11-27`)));
    await assertFails(setDoc(doc(as(USER), `splash_ad_imp_log/${USER}_2026-11-28`), { n: 0 }));
  });

  const OTHER = '998907778899';
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'splash_ad_orders/o1'), { uid: USER, status: 'pending', amount: 60000 });
    await setDoc(doc(db, 'splash_ad_orders/o2'), { uid: OTHER, status: 'approved', amount: 20000 });
    await setDoc(doc(db, 'splash_ad_config/main'), { stage: 'public', activeTariffVersion: 1 });
    await setDoc(doc(db, 'splash_ad_tariffs/v1'), { version: 1, perDay: { district: 1 } });
    await setDoc(doc(db, 'splash_ad_events/e1'), { orderId: 'o1', type: 'paid' });
  });
  await check('R6 splash_ad_orders: эгаси ўзиникини ўқийди (get + uid сўрови), бегонасини йўқ; админ ҳаммасини', async () => {
    await assertSucceeds(getDoc(doc(as(USER), 'splash_ad_orders/o1')));
    await assertSucceeds(getDocs(query(collection(as(USER), 'splash_ad_orders'), where('uid', '==', USER))));
    await assertFails(getDoc(doc(as(USER), 'splash_ad_orders/o2')));
    await assertFails(getDocs(collection(as(USER), 'splash_ad_orders')));
    await assertFails(getDoc(doc(anon(), 'splash_ad_orders/o1')));
    await assertSucceeds(getDocs(query(collection(as(ADMIN), 'splash_ad_orders'), where('status', '==', 'pending'))));
  });
  await check('R7 splash_ad_orders: пул/ҳолат клиентдан ёзилмайди (эгаси ва админ ҳам)', async () => {
    await assertFails(updateDoc(doc(as(USER), 'splash_ad_orders/o1'), { status: 'approved' }));
    await assertFails(updateDoc(doc(as(USER), 'splash_ad_orders/o1'), { amount: 1 }));
    await assertFails(setDoc(doc(as(USER), 'splash_ad_orders/o3'), { uid: USER, status: 'approved', amount: 0 }));
    await assertFails(updateDoc(doc(as(ADMIN), 'splash_ad_orders/o1'), { status: 'approved' }));
    await assertFails(deleteDoc(doc(as(ADMIN), 'splash_ad_orders/o1')));
  });
  await check('R8 splash_ad_config / tariffs / events: ёпиқ (фақат CF)', async () => {
    for (const p of ['splash_ad_config/main', 'splash_ad_tariffs/v1', 'splash_ad_events/e1']) {
      await assertFails(getDoc(doc(as(USER), p)));
      await assertFails(setDoc(doc(as(ADMIN), p), { x: 1 }));
    }
  });

  await testEnv.cleanup();
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed} passed, ${results.length - passed} failed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
