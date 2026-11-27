/**
 * Кафе-ресторан кўришлар статистикаси rules (2026-10-25): `restaurants/{rid}/view_stats/{yyyymmdd}`.
 *
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/restaurant_view_stats_rules.test.js"
 *
 * Қулфланади:
 *   - эга ва ходим (а'зо) ўз ресторанининг кунини `get` қилади (ҳали йўқ кун ҳам), админ ҳам;
 *   - бошқа ресторан эгаси, мижоз, логинсиз — йўқ;
 *   - рўйхат (list) — ҳеч ким (а'зо ҳам); ёзув (create/update/delete) — ҳеч ким (фақат CF);
 *   - а'зо ресторан ҳужжатига `publicId` / `searchIndexedAt` ёза олмайди (сервер майдонлари).
 */
'use strict';
const path = require('path');
const fs = require('fs');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const ADMIN = '998901110000';
const OWNER = '998911500001';
const STAFF = '998911500002';
const OWNER2 = '998911500003';
const CUSTOMER = '998911500004';
const R1 = 'rest_view_1';
const R2 = 'rest_view_2';
const DAY = '20261025';

async function main() {
  console.log(`rules: ${RULES_PATH}`);
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-restaurant-view-stats',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const record = (name, pass, detail) => {
    results.push({ name, pass });
    console.log(`${pass ? 'PASS' : 'FAIL'} - ${name}${detail ? ' :: ' + detail : ''}`);
  };
  async function check(name, fn) {
    try { await fn(); record(name, true); } catch (e) { record(name, false, e.message); }
  }
  const as = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const anon = () => testEnv.unauthenticatedContext().firestore();
  const statsPath = (rid, day = DAY) => `restaurants/${rid}/view_stats/${day}`;

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
    for (const u of [OWNER, STAFF, OWNER2, CUSTOMER]) await db.doc(`users/${u}`).set({ role: 'user' });
    const base = {
      status: 'approved', prepTimeMin: 20, minOrderAmount: 0, delivery: { mode: 'none', pickup: true }, payment: { prepay: true, cash: true },
    };
    await db.doc(`restaurants/${R1}`).set({ ...base, name: 'Gurlan osh', ownerUid: OWNER });
    await db.doc(`restaurants/${R1}/members/${OWNER}`).set({ role: 'owner' });
    await db.doc(`restaurants/${R1}/members/${STAFF}`).set({ role: 'staff' });
    await db.doc(`restaurants/${R2}`).set({ ...base, name: 'Boshqa', ownerUid: OWNER2 });
    await db.doc(`restaurants/${R2}/members/${OWNER2}`).set({ role: 'owner' });
    await db.doc(statsPath(R1)).set({ restaurantId: R1, day: DAY, restaurantViews: 3 });
  });

  await check('V1 egasi va xodim o\'z restoranining kunini o\'qiydi (yo\'q kun ham); admin ham', async () => {
    await assertSucceeds(as(OWNER).doc(statsPath(R1)).get());
    await assertSucceeds(as(STAFF).doc(statsPath(R1)).get());
    await assertSucceeds(as(OWNER).doc(statsPath(R1, '20261024')).get());
    await assertSucceeds(as(ADMIN).doc(statsPath(R1)).get());
  });
  await check('V2 boshqa restoran egasi, mijoz, loginsiz — o\'qiy olmaydi', async () => {
    await assertFails(as(OWNER2).doc(statsPath(R1)).get());
    await assertFails(as(CUSTOMER).doc(statsPath(R1)).get());
    await assertFails(anon().doc(statsPath(R1)).get());
    await assertFails(as(OWNER).doc(statsPath(R2)).get(), 'begona restoran');
  });
  await check('V3 ro\'yxat — hech kim (a\'zo ham); yozish — hech kim (faqat CF)', async () => {
    await assertFails(as(OWNER).collection(`restaurants/${R1}/view_stats`).get());
    await assertFails(as(OWNER).doc(statsPath(R1)).set({ restaurantViews: 999 }));
    await assertFails(as(OWNER).doc(statsPath(R1)).update({ restaurantViews: 999 }));
    await assertFails(as(OWNER).doc(statsPath(R1, '20261026')).set({ restaurantViews: 1 }));
    await assertFails(as(OWNER).doc(statsPath(R1)).delete());
    await assertFails(as(ADMIN).doc(statsPath(R1)).set({ restaurantViews: 1 }));
  });
  await check('V4 a\'zo restoran hujjatiga publicId / searchIndexedAt yoza olmaydi; oddiy profil tahriri ishlaydi', async () => {
    await assertFails(as(OWNER).doc(`restaurants/${R1}`).update({ publicId: 'AbCdEfGh23' }));
    await assertFails(as(OWNER).doc(`restaurants/${R1}`).update({ searchIndexedAt: new Date() }));
    await assertSucceeds(as(OWNER).doc(`restaurants/${R1}`).update({ name: 'Gurlan osh markazi' }));
  });

  await testEnv.cleanup();
  const failed = results.filter((r) => !r.pass).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
