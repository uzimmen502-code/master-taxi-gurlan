/**
 * XITOY BOZORI «So'rov qoldirish» — Firestore rules (functions/china_inquiries.js).
 *
 *   firebase emulators:exec --only firestore --project demo-china-rules \
 *     "node test/china_inquiries_rules.test.js"
 *
 * Qulflanadi: mijoz faqat O'Z so'rovini va `offers` (ta'minotchisiz nusxa) ni o'qiydi; ta'minotchilar,
 * ichki `quotes`, `dispatches`, `events`, config va hisoblagich — faqat admin / hech kim; hamma yozuv yopiq.
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const ADMIN = '998901110000';
const ME = '998911000001';
const OTHER = '998911000002';
const INQ = 'inq_me';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-china-rules',
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

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
    await db.doc(`users/${ME}`).set({ role: 'user' });
    await db.doc(`users/${OTHER}`).set({ role: 'user' });
    await db.doc(`china_inquiries/${INQ}`).set({ ownerId: ME, refNo: 'CN-0001', status: 'quoted', text: 'x' });
    await db.doc(`china_inquiries/${INQ}/offers/q1`).set({ priceMinor: 100, currency: 'USD' });
    await db.doc(`china_inquiries/${INQ}/quotes/q1`).set({ supplierId: 's1', priceMinor: 100 });
    await db.doc(`china_inquiries/${INQ}/dispatches/s1`).set({ supplierId: 's1' });
    await db.doc(`china_inquiries/${INQ}/events/e1`).set({ type: 'created' });
    await db.doc('china_suppliers/s1').set({ displayName: 'Li', active: true });
    await db.doc('china_inquiry_config/main').set({ stage: 'internal', testerIds: [ME] });
    await db.doc('china_inquiry_config_history/v1').set({ stage: 'internal' });
    await db.doc('china_inquiry_meta/counter').set({ n: 1 });
  });

  await check('R1 egasi o\'z so\'rovini get va list (ownerId filtri) bilan o\'qiydi', async () => {
    await assertSucceeds(as(ME).doc(`china_inquiries/${INQ}`).get());
    await assertSucceeds(as(ME).collection('china_inquiries').where('ownerId', '==', ME).get());
  });

  await check('R2 begona o\'qiy olmaydi; filtrsiz list va begona filtri rad; loginsiz rad', async () => {
    await assertFails(as(OTHER).doc(`china_inquiries/${INQ}`).get());
    await assertFails(as(OTHER).collection('china_inquiries').where('ownerId', '==', ME).get());
    await assertFails(as(ME).collection('china_inquiries').get());
    await assertFails(anon().doc(`china_inquiries/${INQ}`).get());
  });

  await check('R3 admin so\'rovni o\'qiydi', async () => {
    await assertSucceeds(as(ADMIN).doc(`china_inquiries/${INQ}`).get());
  });

  await check('R4 egasi `offers`ni o\'qiydi; begona o\'qiy olmaydi', async () => {
    await assertSucceeds(as(ME).doc(`china_inquiries/${INQ}/offers/q1`).get());
    await assertFails(as(OTHER).doc(`china_inquiries/${INQ}/offers/q1`).get());
  });

  await check('R5 egasi ichki quotes / dispatches / events ni O\'QIY OLMAYDI (ta\'minotchi shaxsi yopiq)', async () => {
    await assertFails(as(ME).doc(`china_inquiries/${INQ}/quotes/q1`).get());
    await assertFails(as(ME).doc(`china_inquiries/${INQ}/dispatches/s1`).get());
    await assertFails(as(ME).doc(`china_inquiries/${INQ}/events/e1`).get());
    await assertSucceeds(as(ADMIN).doc(`china_inquiries/${INQ}/quotes/q1`).get());
    await assertSucceeds(as(ADMIN).doc(`china_inquiries/${INQ}/dispatches/s1`).get());
    await assertSucceeds(as(ADMIN).doc(`china_inquiries/${INQ}/events/e1`).get());
  });

  await check('R6 ta\'minotchilar, config, tarix — faqat admin o\'qiydi; hisoblagich hech kim', async () => {
    for (const p of ['china_suppliers/s1', 'china_inquiry_config/main', 'china_inquiry_config_history/v1']) {
      await assertFails(as(ME).doc(p).get());
      await assertSucceeds(as(ADMIN).doc(p).get());
    }
    await assertFails(as(ADMIN).doc('china_inquiry_meta/counter').get());
    await assertFails(as(ME).doc('china_inquiry_meta/counter').get());
  });

  await check('W1 HECH KIM (admin ham, egasi ham) to\'g\'ridan-to\'g\'ri yozolmaydi', async () => {
    for (const who of [ME, ADMIN, OTHER]) {
      await assertFails(as(who).doc('china_inquiries/new1').set({ ownerId: who, status: 'new' }));
      await assertFails(as(who).doc(`china_inquiries/${INQ}`).update({ status: 'closed' }));
      await assertFails(as(who).doc(`china_inquiries/${INQ}/offers/q2`).set({ priceMinor: 1 }));
      await assertFails(as(who).doc(`china_inquiries/${INQ}/quotes/q2`).set({ priceMinor: 1 }));
      await assertFails(as(who).doc('china_suppliers/s2').set({ displayName: 'x' }));
      await assertFails(as(who).doc('china_inquiry_config/main').set({ stage: 'public' }));
      await assertFails(as(who).doc('china_inquiry_meta/counter').set({ n: 0 }));
    }
    await assertFails(as(ME).doc(`china_inquiries/${INQ}`).delete());
  });

  await testEnv.cleanup();
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
