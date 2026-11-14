/**
 * `yuk_listings` Firestore rules — 5 sutka muddat va jo'nash kuni
 * (ega qarori 2026-10-11).
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/yuk_listings_rules.test.js"
 *
 * Qulflanadi:
 *   - yaratish: `expiresAt` < hozir + 6 sutka (5 sutka + soat farqi);
 *     eski APK (48 soat) ham o'tadi; 30 kun — yo'q
 *   - `departDate` ixtiyoriy, faqat `YYYY-MM-DD` satr
 *   - egasi `departDate`ni o'zgartira oladi; `expiresAt`ni — yo'q;
 *     begona — hech narsa
 */
'use strict';
const path = require('path');
const fs = require('fs');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const { Timestamp } = require('firebase/firestore');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const OWNER = '998915000001';
const STRANGER = '998915000002';
const H = 3600 * 1000;
const D = 24 * H;

async function main() {
  console.log(`rules: ${RULES_PATH}`);
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-yuk-listings',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  async function check(name, fn) {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }
  const as = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const u of [OWNER, STRANGER]) await db.doc(`users/${u}`).set({ role: 'user' });
  });

  const now = Date.now();
  const listing = (over = {}) => ({
    type: 'cargo', from: 'Urganch', to: 'Toshkent', stops: [], vehicleType: 'fura',
    ownerId: OWNER, ownerName: 'Egasi', phone: `+${OWNER}`, status: 'active',
    cargo: 'Paxta', unit: 'kg', weight: 1000, price: 0, comment: '', stars: 5,
    createdAt: Timestamp.fromMillis(now), expiresAt: Timestamp.fromMillis(now + 5 * D),
    departDate: '2026-10-13',
    ...over,
  });
  const col = (phone) => as(phone).collection('yuk_listings');

  await check('yaratish: 5 sutka + departDate — ha', async () => {
    await assertSucceeds(col(OWNER).doc('l5').set(listing()));
  });
  await check('yaratish: eski APK (48 soat, departDate yo\'q) — ha', async () => {
    const d = listing({ expiresAt: Timestamp.fromMillis(now + 48 * H) });
    delete d.departDate;
    await assertSucceeds(col(OWNER).doc('l48').set(d));
  });
  await check('chegara: 5 sutka 23 soat — ha; 6 sutka 1 soat — yo\'q; 30 kun — yo\'q', async () => {
    await assertSucceeds(col(OWNER).doc('lEdge').set(listing({ expiresAt: Timestamp.fromMillis(now + 6 * D - H) })));
    await assertFails(col(OWNER).doc('lOver').set(listing({ expiresAt: Timestamp.fromMillis(now + 6 * D + H) })));
    await assertFails(col(OWNER).doc('l30').set(listing({ expiresAt: Timestamp.fromMillis(now + 30 * D) })));
  });
  await check('departDate noto\'g\'ri shakl — yo\'q', async () => {
    await assertFails(col(OWNER).doc('lBad1').set(listing({ departDate: '13.10.2026' })));
    await assertFails(col(OWNER).doc('lBad2').set(listing({ departDate: 20261013 })));
  });
  await check('egasi departDate ni o\'zgartiradi — ha; expiresAt — yo\'q; noto\'g\'ri shakl — yo\'q', async () => {
    await assertSucceeds(col(OWNER).doc('l5').update({ departDate: '2026-10-14', updatedAt: Timestamp.now() }));
    await assertFails(col(OWNER).doc('l5').update({ expiresAt: Timestamp.fromMillis(now + 5.5 * D) }));
    await assertFails(col(OWNER).doc('l5').update({ departDate: 'ertaga' }));
  });
  await check('begona departDate ni o\'zgartirolmaydi', async () => {
    await assertFails(col(STRANGER).doc('l5').update({ departDate: '2026-10-15' }));
  });

  await testEnv.cleanup();
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
