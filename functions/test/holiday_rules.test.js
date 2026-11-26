/**
 * Байрам саватчаси — firestore.rules (эга 2026-11-26).
 *   firebase emulators:exec --only firestore --project demo-holiday-rules "node test/holiday_rules.test.js"
 *   (RULES_PATH — бошқа файл, масалан stripped build)
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { serverTimestamp } = require('firebase/firestore');

const RULES_PATH = process.env.RULES_PATH || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
const USER = '998901000001';
const ADMIN = '998909990001';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-holiday-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  console.log(`rules: ${RULES_PATH}`);
  const results = [];
  const check = async (n, fn) => {
    try { await fn(); results.push(true); console.log(`PASS - ${n}`); } catch (e) { results.push(false); console.log(`FAIL - ${n} :: ${e.message}`); }
  };
  const ctx = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const user = ctx(USER);
  const adm = ctx(ADMIN);
  const anon = testEnv.unauthenticatedContext().firestore();
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
    await db.doc(`users/${USER}`).set({ role: 'user' });
    await db.doc('holiday_occasions/navruz').set({ id: 'navruz', stage: 'public', visible: true });
    await db.doc('holiday_occasions/birthday').set({ id: 'birthday', stage: 'internal', visible: false });
    await db.doc('holiday_baskets/navruz_simple').set({ id: 'navruz_simple', occasionId: 'navruz', active: true, visible: true });
    await db.doc('holiday_baskets/birthday_simple').set({ id: 'birthday_simple', occasionId: 'birthday', active: true, visible: false });
    await db.doc(`holiday_birthday_index/${USER}_p1`).set({ ownerId: USER, personId: 'p1', md: '03-21' });
    await db.doc(`holiday_reminder_log/bd_${USER}_p1_2027`).set({ kind: 'birthday' });
    await db.doc('holiday_reminder_runs/bd_2027-03-16').set({ done: true });
    await db.doc(`holiday_self_birthday_index/${USER}`).set({ ownerId: USER, personId: 'me', md: '07-10' }); // эга 2026-11-27
  });

  await check('H1 байрам/сават: фақат visible ўқилади (auth), яширин — фақат админ; anon — йўқ; ёзиш — ҳеч ким', async () => {
    await assertSucceeds(user.doc('holiday_occasions/navruz').get());
    await assertFails(user.doc('holiday_occasions/birthday').get());
    await assertSucceeds(adm.doc('holiday_occasions/birthday').get());
    await assertFails(anon.doc('holiday_occasions/navruz').get());
    await assertSucceeds(user.collection('holiday_occasions').where('visible', '==', true).get());
    await assertFails(user.collection('holiday_occasions').get());
    await assertSucceeds(user.doc('holiday_baskets/navruz_simple').get());
    await assertFails(user.doc('holiday_baskets/birthday_simple').get());
    await assertSucceeds(user.collection('holiday_baskets').where('visible', '==', true).where('occasionId', '==', 'navruz').get());
    await assertFails(user.doc('holiday_occasions/x').set({ visible: true }));
    await assertFails(adm.doc('holiday_occasions/navruz').update({ stage: 'off' }));
    await assertFails(adm.doc('holiday_baskets/navruz_simple').update({ active: false }));
  });

  await check('H2 ички коллекциялар (индекс/лог/курсор) — мижоз ҳам, админ ҳам ўқимайди/ёзмайди', async () => {
    for (const p of [`holiday_birthday_index/${USER}_p1`, `holiday_reminder_log/bd_${USER}_p1_2027`, 'holiday_reminder_runs/bd_2027-03-16',
      `holiday_self_birthday_index/${USER}`, `holiday_reminder_log/self_${USER}_2027_d7`]) {
      await assertFails(user.doc(p).get());
      await assertFails(adm.doc(p).get());
      await assertFails(user.doc(p).set({ x: 1 }));
    }
  });

  await check('H3 sm_lists: occasionId ихтиёрий (тўғри — ок, бузуқ — рад), эски шакл ўзгармади', async () => {
    const base = { name: 'Туғилган кун', items: [{ groupId: 'beef', qty: 1 }], remind: { enabled: false, weekday: 1, minute: 600 } };
    const col = user.collection(`users/${USER}/sm_lists`);
    await assertSucceeds(col.doc('l1').set({ ...base, createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertSucceeds(col.doc('l2').set({ ...base, occasionId: 'birthday', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertFails(col.doc('l3').set({ ...base, occasionId: 'Bad Id', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertFails(col.doc('l4').set({ ...base, occasionId: 5, createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertSucceeds(col.doc('l1').update({ occasionId: 'navruz', updatedAt: serverTimestamp() }));
    await assertFails(col.doc('l1').update({ occasionId: 'x!', updatedAt: serverTimestamp() }));
    await assertFails(col.doc('l1').update({ remindNextAt: 1, updatedAt: serverTimestamp() }));
  });

  await check('H4 users.holidayRemindersOptIn — эгаси ўзгартира олади (мавжуд қоида), бегона — йўқ', async () => {
    await assertSucceeds(user.doc(`users/${USER}`).update({ holidayRemindersOptIn: false }));
    await assertFails(ctx('998901000002').doc(`users/${USER}`).update({ holidayRemindersOptIn: true }));
  });

  await testEnv.cleanup();
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed} passed, ${results.length - passed} failed`);
  process.exit(passed === results.length ? 0 : 1);
}
main().catch((e) => { console.error(e); process.exit(1); });
