/**
 * Taxi billing kolleksiyalari — Firestore rules (D-TAXI-13…23).
 * `taxi_trips`, `taxi_price_changes`, `taxi_fraud_cases`,
 * `service_agreements`, `capability_audit` — HAMMASINI faqat server yozadi.
 *
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/taxi_billing_rules.test.js"
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');

const ADMIN = '998901112233';
const DRIVER = '998902223344';
const DRIVER_ACC = 'accDRIVER0000000000000';
const STRANGER = '998904445566';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-taxi-billing',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const record = (n, p, d) => { results.push({ n, p }); console.log(`${p ? 'PASS' : 'FAIL'} - ${n}${d ? ' :: ' + d : ''}`); };
  const check = async (n, fn) => { try { await fn(); record(n, true); } catch (e) { record(n, false, e.message); } };

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('users').doc(ADMIN).set({ role: 'admin' });
    await db.collection('users').doc(DRIVER).set({ role: 'user', accountId: DRIVER_ACC });
    await db.collection('users').doc(STRANGER).set({ role: 'user' });
    await db.collection('taxi_trips').doc('t1').set({ driverUid: DRIVER, status: 'published', feeAmount: 28000, farePerSeat: 350000 });
    await db.collection('taxi_price_changes').doc('p1').set({ uid: DRIVER, tripId: 't1', oldFare: 200000, newFare: 350000 });
    await db.collection('taxi_fraud_cases').doc('f1').set({ driverUid: DRIVER, verdict: 'suspicious' });
    await db.collection('service_agreements').doc(DRIVER_ACC).set({ taxi: { version: 1 } });
    await db.collection('capability_audit').doc('a1').set({ accountId: DRIVER_ACC, to: 'verified' });
  });
  const ctxFor = (p) => testEnv.authenticatedContext(`uid_${p}`, { phone_number: '+' + p });
  const driver = ctxFor(DRIVER).firestore();
  const stranger = ctxFor(STRANGER).firestore();
  const adminDb = ctxFor(ADMIN).firestore();
  const unauth = testEnv.unauthenticatedContext().firestore();

  // taxi_trips
  await check('haydovchi O\'Z reysini o\'qiydi', () => assertSucceeds(driver.collection('taxi_trips').doc('t1').get()));
  await check('begona reysni o\'qiy olmaydi', () => assertFails(stranger.collection('taxi_trips').doc('t1').get()));
  await check('haydovchi reys statusini O\'ZI `published` qila olmaydi (D-TAXI-13)', () => assertFails(driver.collection('taxi_trips').doc('t1').update({ status: 'published' })));
  await check('haydovchi `feeAmount`ni o\'zgartira olmaydi (D-TAXI-21)', () => assertFails(driver.collection('taxi_trips').doc('t1').update({ feeAmount: 0 })));
  await check('haydovchi reysni `cancelled` qilib refund ololmaydi — faqat callable', () => assertFails(driver.collection('taxi_trips').doc('t1').update({ status: 'cancelled', refunded: true })));
  await check('haydovchi reys yarata olmaydi', () => assertFails(driver.collection('taxi_trips').doc('t2').set({ driverUid: DRIVER, status: 'published', feeAmount: 0 })));
  await check('admin ham klient SDK bilan yoza olmaydi (faqat Admin SDK)', () => assertFails(adminDb.collection('taxi_trips').doc('t1').update({ feeAmount: 1 })));
  await check('admin o\'qiydi', () => assertSucceeds(adminDb.collection('taxi_trips').doc('t1').get()));
  await check('autentifikatsiyasiz o\'qiy olmaydi', () => assertFails(unauth.collection('taxi_trips').doc('t1').get()));

  // price changes / fraud / agreements / audit
  await check('narx audit\'i: egasi o\'qiydi, yoza olmaydi', async () => {
    await assertSucceeds(driver.collection('taxi_price_changes').doc('p1').get());
    await assertFails(driver.collection('taxi_price_changes').doc('p1').update({ newFare: 1 }));
  });
  await check('fraud holatlari faqat admin', async () => {
    await assertFails(driver.collection('taxi_fraud_cases').doc('f1').get());
    await assertSucceeds(adminDb.collection('taxi_fraud_cases').doc('f1').get());
    await assertFails(adminDb.collection('taxi_fraud_cases').doc('f1').update({ verdict: 'normal' }));
  });
  await check('kelishuv: egasi o\'qiydi (accountId orqali), yoza olmaydi', async () => {
    await assertSucceeds(driver.collection('service_agreements').doc(DRIVER_ACC).get());
    await assertFails(driver.collection('service_agreements').doc(DRIVER_ACC).set({ taxi: { version: 99 } }, { merge: true }));
    await assertFails(stranger.collection('service_agreements').doc(DRIVER_ACC).get());
  });
  await check('capability audit faqat admin o\'qiydi, hech kim yozmaydi', async () => {
    await assertFails(driver.collection('capability_audit').doc('a1').get());
    await assertSucceeds(adminDb.collection('capability_audit').doc('a1').get());
    await assertFails(adminDb.collection('capability_audit').doc('a2').set({ to: 'verified' }));
  });

  await testEnv.cleanup();
  const failed = results.filter((r) => !r.p);
  console.log(`\n${results.length - failed.length}/${results.length} taxi billing rules checks passed.`);
  if (failed.length) { console.log('FAILED:', failed.map((f) => f.n).join(', ')); process.exitCode = 1; }
}
main().catch((e) => { console.error('FATAL', e); process.exitCode = 1; });
