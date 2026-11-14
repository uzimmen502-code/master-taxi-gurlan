/**
 * Ижара хабарномаси — Firestore қоидалари (эга қарори 2026-10-08).
 *
 * Қулфланади:
 *   - `realty_alerts`: эгаси ўзиникини ўқийди (рўйхат сўрови ҳам),
 *     бегона ўқий олмайди; клиент ҲЕЧ ҚАЧОН ёзмайди (лимит/муддат CF'да);
 *   - `realty_alert_hits`, `realty_alert_meta`: клиентга ёпиқ;
 *   - `users/{uid}/realty_matches`: эгаси ўқийди, фақат `seen`ни
 *     ўзгартиради ва ўчиради; бегона ўқий олмайди; яратиш — фақат CF.
 *
 * Ишлатиш: firebase emulators:exec --only firestore "node functions/test/realty_alerts_rules.test.js"
 */
'use strict';
const path = require('path');
const fs = require('fs');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const SEEKER = '998901110001';
const STRANGER = '998907778899';
const ADMIN_PHONE = '998909998877';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-realty-alerts',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  async function check(name, fn) {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }
  await testEnv.clearFirestore();

  const seeker = testEnv.authenticatedContext('uSeeker', { phone_number: `+${SEEKER}` }).firestore();
  const stranger = testEnv.authenticatedContext('uStranger', { phone_number: `+${STRANGER}` }).firestore();
  const adminDb = testEnv.authenticatedContext('uAdmin', { phone_number: `+${ADMIN_PHONE}` }).firestore();
  const anon = testEnv.authenticatedContext('guest', { firebase: { sign_in_provider: 'anonymous' } }).firestore();

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${ADMIN_PHONE}`).set({ role: 'admin' });
    await db.doc(`users/${SEEKER}`).set({ phone: SEEKER });
    await db.doc('realty_alerts/a1').set({ ownerId: SEEKER, deal: 'rent', status: 'active', radiusKm: 3 });
    await db.doc('realty_alerts/a2').set({ ownerId: STRANGER, deal: 'rent', status: 'active', radiusKm: 3 });
    await db.doc('realty_alert_hits/a1_L1').set({ alertId: 'a1', listingId: 'L1', ownerId: SEEKER });
    await db.doc(`users/${SEEKER}/realty_matches/L1`).set({ listingId: 'L1', alertId: 'a1', seen: false, title: 'Уй' });
    await db.doc(`users/${SEEKER}/realty_alert_meta/push`).set({ day: '2026-10-08', count: 1 });
  });

  await check('хабарнома: эгаси ўзиникини ўқийди (get ва рўйхат)', async () => {
    await assertSucceeds(seeker.doc('realty_alerts/a1').get());
    await assertSucceeds(seeker.collection('realty_alerts').where('ownerId', '==', SEEKER).get());
  });
  await check('хабарнома: бегона ва меҳмон ўқий олмайди; фильтрсиз рўйхат рад', async () => {
    await assertFails(stranger.doc('realty_alerts/a1').get());
    await assertFails(anon.doc('realty_alerts/a1').get());
    await assertFails(seeker.collection('realty_alerts').get());
  });
  await check('хабарнома: клиент ёза олмайди (ўзиники ҳам) — лимит CF\'да', async () => {
    await assertFails(seeker.doc('realty_alerts/new').set({ ownerId: SEEKER, deal: 'rent', status: 'active' }));
    await assertFails(seeker.doc('realty_alerts/a1').update({ radiusKm: 100 }));
    await assertFails(seeker.doc('realty_alerts/a1').delete());
  });
  await check('hit ва push саноғи: клиентга ёпиқ', async () => {
    await assertFails(seeker.doc('realty_alert_hits/a1_L1').get());
    await assertFails(seeker.doc('realty_alert_hits/a1_L2').set({ alertId: 'a1' }));
    await assertFails(seeker.doc(`users/${SEEKER}/realty_alert_meta/push`).get());
    await assertFails(seeker.doc(`users/${SEEKER}/realty_alert_meta/push`).set({ count: 0 }));
    await assertSucceeds(adminDb.doc('realty_alert_hits/a1_L1').get());
  });
  await check('inbox: эгаси ўқийди, фақат `seen`ни ўзгартиради, ўчиради', async () => {
    await assertSucceeds(seeker.doc(`users/${SEEKER}/realty_matches/L1`).get());
    await assertSucceeds(seeker.collection(`users/${SEEKER}/realty_matches`).get());
    await assertSucceeds(seeker.doc(`users/${SEEKER}/realty_matches/L1`).update({ seen: true }));
    await assertFails(seeker.doc(`users/${SEEKER}/realty_matches/L1`).update({ title: 'Бошқа' }));
    await assertFails(seeker.doc(`users/${SEEKER}/realty_matches/L9`).set({ listingId: 'L9' }));
    await assertSucceeds(seeker.doc(`users/${SEEKER}/realty_matches/L1`).delete());
  });
  await check('inbox: бегона ўқий ҳам, ўзгартира ҳам олмайди', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`users/${SEEKER}/realty_matches/L2`).set({ listingId: 'L2', seen: false });
    });
    await assertFails(stranger.doc(`users/${SEEKER}/realty_matches/L2`).get());
    await assertFails(stranger.doc(`users/${SEEKER}/realty_matches/L2`).update({ seen: true }));
    await assertFails(stranger.doc(`users/${SEEKER}/realty_matches/L2`).delete());
  });

  await testEnv.cleanup();
  const ok = results.filter(Boolean).length;
  console.log(`\n${ok}/${results.length} realty alerts rules checks passed.`);
  process.exit(ok === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
