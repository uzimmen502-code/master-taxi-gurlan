/**
 * `home_ticker_ads` (бош экран баннери) — Firestore rules, 3 тил майдонлари (2026-10-26).
 *
 *   firebase emulators:exec --only firestore --project demo-ticker-rules "node test/home_ticker_rules.test.js"
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { serverTimestamp } = require('firebase/firestore');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
const ADMIN = '998901112233';
const USER = '998905556677';

const base = (extra = {}) => ({
  text: 'Тошкентга такси?', audience: 'all', active: true, priority: 0, module: 'home_search',
  durationSec: 6, scrollSpeed: 45, animationStyle: 'auto', fontSize: 13,
  createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra,
});

async function main() {
  const env = await initializeTestEnvironment({
    projectId: 'demo-ticker-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const check = async (name, fn) => {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.message}`); }
  };
  await env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('users').doc(ADMIN).set({ role: 'admin', phone: `+${ADMIN}` });
    await ctx.firestore().collection('users').doc(USER).set({ role: 'user', phone: `+${USER}` });
    await ctx.firestore().collection('home_ticker_ads').doc('old').set({ ...base(), createdAt: new Date(), updatedAt: new Date() });
  });
  const as = (p) => env.authenticatedContext(`uid_${p}`, { phone_number: `+${p}` }).firestore();
  const col = (db) => db.collection('home_ticker_ads');

  await check('admin: 3 тилли матн яратади', () => assertSucceeds(col(as(ADMIN)).add(base({ textLatn: 'Toshkentga taksi?', textRu: 'Такси в Ташкент?' }))));
  await check('admin: фақат кирилл (эски тартиб) — ўтади', () => assertSucceeds(col(as(ADMIN)).add(base())));
  await check('admin: бўш лотин/рус матн — рад (бўш бўлса майдон ўчирилади)', async () => {
    await assertFails(col(as(ADMIN)).add(base({ textLatn: '' })));
    await assertFails(col(as(ADMIN)).add(base({ textRu: '' })));
  });
  await check('admin: 500 белгидан узун ёки матн бўлмаган — рад', async () => {
    await assertFails(col(as(ADMIN)).add(base({ textRu: 'я'.repeat(501) })));
    await assertFails(col(as(ADMIN)).add(base({ textLatn: 5 })));
  });
  await check('admin: эски ҳужжатга лотин/рус қўшади ва кейин ўчиради', async () => {
    const ref = col(as(ADMIN)).doc('old');
    await assertSucceeds(ref.update({ textLatn: 'Toshkentga taksi?', textRu: 'Такси?', updatedAt: serverTimestamp() }));
    const { deleteField } = require('firebase/firestore');
    await assertSucceeds(ref.update({ textRu: deleteField(), updatedAt: serverTimestamp() }));
  });
  await check('оддий фойдаланувчи ёза олмайди, ўқий олади', async () => {
    await assertFails(col(as(USER)).add(base({ textLatn: 'x' })));
    await assertFails(col(as(USER)).doc('old').update({ textRu: 'x' }));
    await assertSucceeds(col(env.unauthenticatedContext().firestore()).doc('old').get());
  });

  await env.cleanup();
  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exitCode = failed ? 1 : 0;
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
