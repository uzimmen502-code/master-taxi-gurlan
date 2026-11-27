/**
 * `demand_matches` Firestore rules - S2/L9.
 *
 * Symptom: taklifchi o'z match'ining `status`ini new/seen/skipped ga o'zgartira
 * olardi, match allaqachon accepted / in_progress bo'lsa ham.
 * Root cause: `update` qoidasi faqat YANGI qiymatni (`request.resource.data`)
 * tekshirardi, joriy holatni (`resource.data.status`) emas.
 *
 * Ilova (`match_repository.dart` markSeen/markSkipped) faqat new/seen/skipped
 * orasida yozadi; xato yutiladi.
 *
 * Ishlatish: functions/ ichidan
 *   firebase emulators:exec --only firestore --project demo-demand-matches-rules \
 *     "node test/demand_matches_rules.test.js"
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

const PROVIDER = '998905556677';
const OTHER = '998907778899';

function matchDoc(status) {
  return {providerId: PROVIDER, demandId: 'd1', status, score: 10};
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-demand-matches',
    firestore: {rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT)},
  });
  const results = [];
  async function check(name, fn) {
    try {
      await fn();
      results.push({name, pass: true});
      console.log(`PASS - ${name}`);
    } catch (e) {
      results.push({name, pass: false});
      console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }
  const ctxFor = (phone) => testEnv.authenticatedContext(`uid_${phone}`, {
    phone_number: '+' + phone,
  }).firestore();
  const doc = (db, id) => db.collection('demand_matches').doc(id);

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const s of ['new', 'seen', 'skipped', 'offered', 'accepted', 'in_progress', 'completed']) {
      await db.collection('demand_matches').doc(`m_${s}`).set(matchDoc(s));
    }
  });

  const mine = ctxFor(PROVIDER);
  const other = ctxFor(OTHER);
  const seen = () => ({status: 'seen', seenAt: new Date()});

  await check('provider new matchni seen qiladi (markSeen)',
      () => assertSucceeds(doc(mine, 'm_new').update(seen())));
  await check('provider seen matchni skipped qiladi',
      () => assertSucceeds(doc(mine, 'm_seen').update({status: 'skipped', seenAt: new Date()})));
  await check('provider skipped matchni seen qiladi',
      () => assertSucceeds(doc(mine, 'm_skipped').update(seen())));

  for (const s of ['accepted', 'in_progress', 'offered', 'completed']) {
    await check(`S2: provider ${s} matchni seen ga tushira olmaydi`,
        () => assertFails(doc(mine, `m_${s}`).update(seen())));
    await check(`S2: provider ${s} matchni skipped ga tushira olmaydi`,
        () => assertFails(doc(mine, `m_${s}`).update({status: 'skipped', seenAt: new Date()})));
  }

  await check('provider accepted qila olmaydi (new -> accepted)',
      () => assertFails(doc(mine, 'm_new').update({status: 'accepted', seenAt: new Date()})));
  await check('provider boshqa maydonni (score) o\'zgartira olmaydi',
      () => assertFails(doc(mine, 'm_new').update({score: 99})));
  await check('begona provider birovning matchini o\'zgartira olmaydi',
      () => assertFails(doc(other, 'm_new').update(seen())));
  await check('provider matchni o\'chira olmaydi',
      () => assertFails(doc(mine, 'm_new').delete()));
  await check('provider o\'z matchlarini filtr bilan o\'qiydi',
      () => assertSucceeds(mine.collection('demand_matches')
          .where('providerId', '==', PROVIDER).get()));

  await testEnv.cleanup();
  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} demand_matches rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}
main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});