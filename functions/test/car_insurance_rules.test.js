/**
 * «Автомобил суғуртаси» (эга 2026-11-28) — firestore.rules: insurance_requests / insurance_enrollments — эгаси ва админ
 * ўқийди, ҳеч ким ёзмайди; бошқа insurance_* (config, тариф, файл токени, индекс, ҳисобот) — мижоз учун ёпиқ.
 *   firebase emulators:exec --only firestore --project demo-insurance-rules "node functions/test/car_insurance_rules.test.js"
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_PATH || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
const A = '998901000001';
const B = '998901000002';
const ADM = '998901000009';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-insurance-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const check = async (n, fn) => {
    try { await fn(); results.push(true); console.log(`PASS - ${n}`); } catch (e) { results.push(false); console.log(`FAIL - ${n} :: ${e.message}`); }
  };
  const as = (p) => testEnv.authenticatedContext(`uid_${p}`, { phone_number: `+${p}` }).firestore();
  const a = as(A); const b = as(B); const adm = as(ADM);
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await db.doc(`users/${ADM}`).set({ role: 'admin' });
    await db.doc(`users/${A}`).set({ role: 'user', bonusBalance: 1000 });
    await db.doc(`insurance_requests/ins_${A}_k1`).set({ uid: A, status: 'paid', price: 200000 });
    await db.doc(`insurance_requests/ins_${B}_k1`).set({ uid: B, status: 'paid', price: 200000 });
    await db.doc(`insurance_enrollments/2026_01A123BC`).set({ uid: A, option: 'oil', oilChanges: 1 });
    await db.doc(`insurance_policy_files/ins_${A}_k1`).set({ uid: A, token: 'secret' });
    await db.doc('insurance_config/main').set({ stage: 'internal', agentPhones: [ADM] });
    await db.doc('insurance_tariffs/v1').set({ version: 1, rows: [] });
    await db.doc(`insurance_expiry_index/${A}`).set({ uid: A, expiresOn: '2027-01-01' });
  });
  await check('R1 эгаси ўз аризаси/рағбатини ўқийди (get + uid бўйича list); бегонаникини — йўқ', async () => {
    await assertSucceeds(a.doc(`insurance_requests/ins_${A}_k1`).get());
    await assertSucceeds(a.collection('insurance_requests').where('uid', '==', A).get());
    await assertSucceeds(a.collection('insurance_enrollments').where('uid', '==', A).get());
    await assertFails(a.doc(`insurance_requests/ins_${B}_k1`).get());
    await assertFails(a.collection('insurance_requests').get());
    await assertFails(b.doc('insurance_enrollments/2026_01A123BC').get());
  });
  await check('R2 ҳеч ким (эгаси ҳам, админ ҳам) клиентдан ёзолмайди: ҳолат/нарх/рағбат', async () => {
    await assertFails(a.doc(`insurance_requests/ins_${A}_k1`).update({ status: 'issued' }));
    await assertFails(a.doc(`insurance_requests/ins_${A}_k2`).set({ uid: A, status: 'paid', price: 1 }));
    await assertFails(a.doc('insurance_enrollments/2026_01A123BC').update({ oilChanges: 2 }));
    await assertFails(adm.doc(`insurance_requests/ins_${A}_k1`).update({ status: 'issued' }));
  });
  await check('R3 файл токени, созлама, тариф, индекс — мижоз учун ёпиқ; админ аризаларни ўқийди', async () => {
    await assertFails(a.doc(`insurance_policy_files/ins_${A}_k1`).get());
    await assertFails(a.doc('insurance_config/main').get());
    await assertFails(a.doc('insurance_tariffs/v1').get());
    await assertFails(a.doc('insurance_tariffs/v2').set({ version: 2, rows: [] }));
    await assertFails(a.doc(`insurance_expiry_index/${A}`).get());
    await assertFails(a.collection('insurance_service_reports').add({ plates: ['X'] }));
    await assertFails(a.doc(`insurance_oil_credits/01A123BC_2026-11-28`).set({ result: 'credited' }));
    await assertSucceeds(adm.collection('insurance_requests').where('status', '==', 'paid').get());
  });
  await testEnv.cleanup();
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed} passed, ${results.length - passed} failed`);
  process.exit(passed === results.length ? 0 : 1);
}
main().catch((e) => { console.error(e); process.exit(1); });
