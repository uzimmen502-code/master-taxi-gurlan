/**
 * Оила боғланиши (эга 2026-11-28) — firestore.rules: family_invites / family_links / family_link_state фақат CF
 * (қоида йўқ = ёпиқ). Ўзининг ҳужжати ҳам ўқилмайди/ёзилмайди (мижоз getMyFamilyLinks callable орқали).
 *   firebase emulators:exec --only firestore --project demo-family-rules "node functions/test/family_links_rules.test.js"
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_PATH || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
const A = '998901000001';
const B = '998901000002';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-family-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const check = async (n, fn) => {
    try { await fn(); results.push(true); console.log(`PASS - ${n}`); } catch (e) { results.push(false); console.log(`FAIL - ${n} :: ${e.message}`); }
  };
  const user = testEnv.authenticatedContext(`uid_${A}`, { phone_number: `+${A}` }).firestore();
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await db.doc(`family_invites/${B}_${A}`).set({ fromKey: B, toKey: A, status: 'pending' });
    await db.doc(`family_links/${A}_${B}`).set({ keys: [A, B], status: 'active' });
    await db.doc(`family_link_state/${A}`).set({ spousePair: null });
  });
  await check('R1 мижоз family_* ни ўқий/ёза олмайди (ўзиники ҳам)', async () => {
    await assertFails(user.doc(`family_invites/${B}_${A}`).get());
    await assertFails(user.collection('family_invites').where('toKey', '==', A).get());
    await assertFails(user.doc(`family_invites/${A}_${B}`).set({ fromKey: A, toKey: B, status: 'accepted' }));
    await assertFails(user.doc(`family_links/${A}_${B}`).get());
    await assertFails(user.doc(`family_links/${A}_${B}`).update({ status: 'unlinked' }));
    await assertFails(user.doc(`family_link_state/${A}`).set({ parents: 0 }));
    await assertFails(user.doc('incentive_programs/spouse_link').set({ kind: 'spouse_link', amount: 999999 }));
    await assertFails(user.doc(`incentive_grants/spouse_link_${A}`).set({ uid: A, amount: 10000 }));
  });
  await testEnv.cleanup();
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed} passed, ${results.length - passed} failed`);
  process.exit(passed === results.length ? 0 : 1);
}
main().catch((e) => { console.error(e); process.exit(1); });
