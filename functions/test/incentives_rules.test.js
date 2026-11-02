/**
 * Рағбат дастурлари — Firestore rules (functions/incentives.js, эга қарори 2026-11-02).
 *
 *   (RULES_FILE=build/firestore_rules/firestore.rules — deploy qilinadigan izohsiz nusxa uchun)
 *   firebase emulators:exec --only firestore --project demo-incentives-rules \
 *     "node test/incentives_rules.test.js"
 *
 * Qulflanadi: dastur sozlamasi va kunlik budjet — faqat admin o'qiydi; grant va jurnal — egasi
 * (`where uid == o'z raqami`) yoki admin; hamma yozuv yopiq (admin ham — faqat callable);
 * `users.incentiveBalance` / `incentiveUpdatedAt` — klient yarata ham, o'zgartira ham olmaydi.
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_FILE
  ? path.resolve(process.env.RULES_FILE)
  : path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const WOMAN = '998915000001';
const OTHER = '998915000002';
const NEWBIE = '998915000003';
const ADMIN = '998915000009';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-incentives-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  async function check(name, fn) {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }
  const as = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const noAuth = () => testEnv.unauthenticatedContext().firestore();

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${ADMIN}`).set({ role: 'admin', phone: ADMIN });
    await db.doc(`users/${WOMAN}`).set({ role: 'user', phone: WOMAN, gender: 'female', bonusBalance: 5000, incentiveBalance: 100000 });
    await db.doc('incentive_programs/women').set({ key: 'women', stage: 'public', amount: 100000, counters: { grantedAmount: 100000 } });
    await db.doc(`incentive_grants/women_${WOMAN}`).set({ uid: WOMAN, programId: 'women', amount: 100000, remaining: 100000, status: 'active' });
    await db.doc(`incentive_grants/women_${OTHER}`).set({ uid: OTHER, programId: 'women', amount: 100000, remaining: 100000, status: 'active' });
    await db.doc(`incentive_ledger/grant_women_${WOMAN}`).set({ type: 'grant', uid: WOMAN, amount: 100000 });
    await db.doc('incentive_budget_days/women_20261102').set({ grantedAmount: 100000 });
  });

  await check('G1 egasi o\'z grantini get va list (where uid == o\'zi) qiladi; jurnal ham', async () => {
    await assertSucceeds(as(WOMAN).doc(`incentive_grants/women_${WOMAN}`).get());
    const s = await assertSucceeds(as(WOMAN).collection('incentive_grants').where('uid', '==', WOMAN).get());
    if (s.size !== 1) throw new Error(`1 ta kutilgan, ${s.size}`);
    await assertSucceeds(as(WOMAN).collection('incentive_ledger').where('uid', '==', WOMAN).get());
  });

  await check('G2 begona: boshqaning granti get rad; boshqaning uid bilan list rad; filtrsiz list rad', async () => {
    await assertFails(as(WOMAN).doc(`incentive_grants/women_${OTHER}`).get());
    await assertFails(as(WOMAN).collection('incentive_grants').where('uid', '==', OTHER).get());
    await assertFails(as(WOMAN).collection('incentive_grants').get());
    await assertFails(as(WOMAN).collection('incentive_ledger').get());
    await assertFails(noAuth().doc(`incentive_grants/women_${WOMAN}`).get());
  });

  await check('P1 dastur sozlamasi va kunlik budjet: oddiy foydalanuvchi o\'qiy olmaydi, admin o\'qiydi', async () => {
    await assertFails(as(WOMAN).doc('incentive_programs/women').get());
    await assertFails(as(WOMAN).collection('incentive_programs').get());
    await assertFails(as(WOMAN).doc('incentive_budget_days/women_20261102').get());
    await assertSucceeds(as(ADMIN).doc('incentive_programs/women').get());
    await assertSucceeds(as(ADMIN).collection('incentive_programs').get());
    await assertSucceeds(as(ADMIN).collection('incentive_grants').get());
    await assertSucceeds(as(ADMIN).collection('incentive_ledger').get());
    await assertSucceeds(as(ADMIN).doc('incentive_budget_days/women_20261102').get());
  });

  await check('W1 yozuv hammaga yopiq (admin ham): dastur, grant, jurnal, kun', async () => {
    for (const who of [WOMAN, ADMIN]) {
      await assertFails(as(who).doc('incentive_programs/x').set({ stage: 'public' }));
      await assertFails(as(who).doc('incentive_programs/women').update({ stage: 'off' }));
      await assertFails(as(who).doc(`incentive_grants/women_${WOMAN}`).update({ remaining: 999999 }));
      await assertFails(as(who).doc(`incentive_grants/new_${WOMAN}`).set({ uid: WOMAN, remaining: 1 }));
      await assertFails(as(who).doc(`incentive_ledger/x_${WOMAN}`).set({ uid: WOMAN, amount: 1 }));
      await assertFails(as(who).doc(`incentive_grants/women_${WOMAN}`).delete());
    }
  });

  await check('U1 users: incentiveBalance/incentiveUpdatedAt ni egasi o\'zgartira olmaydi; boshqa maydon — mumkin', async () => {
    await assertFails(as(WOMAN).doc(`users/${WOMAN}`).update({ incentiveBalance: 999999 }));
    await assertFails(as(WOMAN).doc(`users/${WOMAN}`).update({ incentiveUpdatedAt: new Date() }));
    await assertSucceeds(as(WOMAN).doc(`users/${WOMAN}`).update({ fullName: 'Malika' }));
  });

  await check('U2 users create: incentiveBalance bilan yaratish rad; oddiy yaratish o\'tadi', async () => {
    await assertFails(as(NEWBIE).doc(`users/${NEWBIE}`).set({ phone: NEWBIE, gender: 'female', incentiveBalance: 100000 }));
    await assertSucceeds(as(NEWBIE).doc(`users/${NEWBIE}`).set({ phone: NEWBIE, gender: 'female' }));
  });

  await testEnv.cleanup();
  const passed = results.filter(Boolean).length;
  console.log(`${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
