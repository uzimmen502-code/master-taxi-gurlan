/**
 * «Туғилган кунингизни киритинг» пуш (4 кун + ҳар якшанба) — firestore.rules (эга 2026-11-28).
 *   firebase emulators:exec --only firestore --project demo-bday-prompt-rules "node test/birthday_prompt_rules.test.js"
 *   (RULES_PATH — бошқа файл, масалан stripped build)
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_PATH || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
const USER = '998901000001';
const ADMIN = '998909990001';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-bday-prompt-rules',
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
    await db.doc('settings/birthday_prompt').set({ stage: 'internal', internalPhones: [USER], pilotDistrictIds: [], dailyCount: 4, weeklySunday: true, version: 1 });
    await db.doc('settings/app').set({ x: 1 });
    await db.doc(`birthday_prompt_state/${USER}`).set({ sends: 1, lastWeek: '2026-W48' });
    await db.doc('birthday_prompt_runs/2026-W48_internal').set({ done: true });
  });

  await check('R1 settings/birthday_prompt: мижоз/anon ўқимайди (телефонлар), админ ўқийди', async () => {
    await assertFails(user.doc('settings/birthday_prompt').get());
    await assertFails(anon.doc('settings/birthday_prompt').get());
    await assertSucceeds(adm.doc('settings/birthday_prompt').get());
  });

  await check('R2 settings/birthday_prompt: ёзиш ҳеч кимга (админ ҳам — фақат CF adminSetBirthdayPromptSettings)', async () => {
    await assertFails(adm.doc('settings/birthday_prompt').set({ stage: 'public' }, { merge: true }));
    await assertFails(user.doc('settings/birthday_prompt').set({ stage: 'public' }, { merge: true }));
    await assertFails(adm.doc('settings/birthday_prompt').delete());
  });

  await check('R3 регрессия: бошқа settings ҳужжатлари аввалгидек (app — ўқиш ҳамма auth, админ ёзади)', async () => {
    await assertSucceeds(user.doc('settings/app').get());
    await assertSucceeds(adm.doc('settings/app').set({ y: 2 }, { merge: true }));
    await assertFails(user.doc('settings/app').set({ y: 3 }, { merge: true }));
  });

  await check('R4 birthday_prompt_state / runs — клиентга тўлиқ ёпиқ (эгаси ҳам, админ ҳам)', async () => {
    await assertFails(user.doc(`birthday_prompt_state/${USER}`).get());
    await assertFails(user.doc(`birthday_prompt_state/${USER}`).set({ sends: 0 }));
    await assertFails(adm.doc(`birthday_prompt_state/${USER}`).get());
    await assertFails(user.doc('birthday_prompt_runs/2026-W48_internal').get());
    await assertFails(adm.collection('birthday_prompt_runs').get());
  });

  await testEnv.cleanup();
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(1); });
