/**
 * BIZNES XARITASI — Firestore rules (functions/business_directory.js).
 *
 *   firebase emulators:exec --only firestore --project demo-business-rules \
 *     "node test/business_directory_rules.test.js"
 *
 * Qulflanadi: o'qish faqat login qilgan foydalanuvchiga; yozish (create/update/delete) hammaga yopiq —
 * egasiga ham, adminga ham (faqat Cloud Functions, Admin SDK).
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const ADMIN = '998901110000';
const OWNER = '998911000001';
const OTHER = '998911000002';
const BIZ = 'biz_owner';

const VALID = {
  ownerId: OWNER, name: 'Test', category: 'retail', phone: '998901234567', lat: 41.3, lng: 69.2,
  geohash: 'tn', geohash4: 'tn', status: 'active',
};

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-business-rules',
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
    await db.doc(`users/${OWNER}`).set({ role: 'user' });
    await db.doc(`users/${OTHER}`).set({ role: 'user' });
    await db.doc(`businesses/${BIZ}`).set(VALID);
  });

  await check('R1 login qilgan foydalanuvchi get va list qiladi', async () => {
    await assertSucceeds(as(OTHER).doc(`businesses/${BIZ}`).get());
    await assertSucceeds(as(OTHER).collection('businesses').where('geohash4', 'in', ['tn']).get());
  });

  await check('R2 loginsiz o\'qiy olmaydi (telefon/manzil ommaviy skrapingga ochiq emas)', async () => {
    await assertFails(anon().doc(`businesses/${BIZ}`).get());
    await assertFails(anon().collection('businesses').get());
  });

  await check('R3 mijoz yaratolmaydi (egasi o\'zi uchun ham, boshqa nom bilan ham)', async () => {
    await assertFails(as(OWNER).doc('businesses/new1').set(VALID));
    await assertFails(as(OTHER).doc('businesses/new2').set({ ...VALID, ownerId: OTHER }));
  });

  await check('R4 egasi o\'z yozuvini to\'g\'ridan-to\'g\'ri o\'zgartira/o\'chira olmaydi', async () => {
    await assertFails(as(OWNER).doc(`businesses/${BIZ}`).update({ name: 'Boshqa' }));
    await assertFails(as(OWNER).doc(`businesses/${BIZ}`).delete());
  });

  await check('R5 begona egasining yozuvini o\'zgartira/o\'chira olmaydi', async () => {
    await assertFails(as(OTHER).doc(`businesses/${BIZ}`).update({ name: 'Hack' }));
    await assertFails(as(OTHER).doc(`businesses/${BIZ}`).delete());
  });

  await check('R6 admin ham to\'g\'ridan-to\'g\'ri yoza olmaydi (faqat audit bilan callable)', async () => {
    await assertFails(as(ADMIN).doc(`businesses/${BIZ}`).update({ name: 'Admin' }));
    await assertFails(as(ADMIN).doc(`businesses/${BIZ}`).delete());
    await assertFails(as(ADMIN).doc('businesses/new3').set(VALID));
  });

  await testEnv.cleanup();
  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
