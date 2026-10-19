/**
 * `users/{uid}/dismissed_news/{newsId}` — фойдаланувчи «Хабарлар»дан ўчирган хабарлар (эга, 2026-10-20).
 * Фақат эга ўқийди/яратади/ўчиради; `at` == сервер вақти, бошқа майдон йўқ; бошқа одам ва кирмаган — рад; ўзгартириш йўқ.
 *
 * Ишлатиш: repo ildizidan
 *   firebase emulators:exec --only firestore --project demo-news-dismissed \
 *     "node functions/test/news_dismissed_rules.test.js"
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { serverTimestamp } = require('firebase/firestore');

const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const OWNER = '998901112233';
const OTHER = '998904445566';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-news-dismissed',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const check = async (name, fn) => {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  };
  await testEnv.clearFirestore();
  const ctxFor = (p) => testEnv.authenticatedContext(`uid_${p}`, { phone_number: `+${p}` }).firestore();
  const owner = ctxFor(OWNER);
  const other = ctxFor(OTHER);
  const unauth = testEnv.unauthenticatedContext().firestore();
  const ref = (db, uid, id) => db.collection('users').doc(uid).collection('dismissed_news').doc(id);

  await check('D1 эга ўз рўйхатига ёзади (`at` == сервер вақти) ва ўқийди', async () => {
    await assertSucceeds(ref(owner, OWNER, 'n1').set({ at: serverTimestamp() }));
    await assertSucceeds(ref(owner, OWNER, 'n1').get());
    await assertSucceeds(owner.collection('users').doc(OWNER).collection('dismissed_news').get());
  });
  await check('D2 бошқа одам ўқий ҳам, ёза ҳам олмайди (бегона рўйхат)', async () => {
    await assertFails(ref(other, OWNER, 'n2').set({ at: serverTimestamp() }));
    await assertFails(ref(other, OWNER, 'n1').get());
    await assertFails(other.collection('users').doc(OWNER).collection('dismissed_news').get());
    await assertFails(ref(other, OWNER, 'n1').delete());
  });
  await check('D3 кирмаган фойдаланувчи — рад', async () => {
    await assertFails(ref(unauth, OWNER, 'n3').set({ at: serverTimestamp() }));
    await assertFails(ref(unauth, OWNER, 'n1').get());
  });
  await check('D4 шакл: қўшимча майдон, сохта вақт, `at` йўқ — рад', async () => {
    await assertFails(ref(owner, OWNER, 'n4').set({ at: serverTimestamp(), x: 1 }));
    await assertFails(ref(owner, OWNER, 'n5').set({ at: new Date(2020, 1, 1) }));
    await assertFails(ref(owner, OWNER, 'n6').set({}));
    await assertFails(ref(owner, OWNER, 'n7').set({ x: 1 }));
  });
  await check('D5 ўзгартириш йўқ (update рад); эга ўчира олади', async () => {
    await assertFails(ref(owner, OWNER, 'n1').update({ at: serverTimestamp() }));
    await assertSucceeds(ref(owner, OWNER, 'n1').delete());
  });

  await testEnv.cleanup();
  const failed = results.filter((r) => !r).length;
  console.log(`${results.length - failed}/${results.length} passed`);
  if (failed) process.exit(1);
}
main().catch((e) => { console.error(e); process.exit(1); });
