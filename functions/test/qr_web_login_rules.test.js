/**
 * Kompyuterda QR orqali kirish (ega 2026-11-28) — Firestore rules.
 *
 *   firebase emulators:exec --only firestore --project demo-rules-qrweb \
 *     "node functions/test/qr_web_login_rules.test.js"
 *
 * - `qr_login_sessions`: match YO'Q — hech kim (admin ham) klientdan o'qiy/yoza olmaydi.
 * - `qr_login_watch/{64 hex}`: auth'siz ham faqat `get` (ID = sir); `list` yo'q; yozish yo'q.
 * - `qr_web_sessions`: faqat egasi `get`; begona/auth'siz/admin-list yo'q; yozish yo'q.
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_PATH || path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const ADMIN = '998901112233';
const OWNER = '998905556677';
const STRANGER = '998904445566';
const WATCH = 'a'.repeat(64);

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-qr-web',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const check = async (name, fn) => {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  };
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('users').doc(ADMIN).set({ role: 'admin' });
    await db.collection('qr_login_sessions').doc('s1').set({ status: 'approved', secretHash: 'h', scannedBy: OWNER });
    await db.collection('qr_login_watch').doc(WATCH).set({ status: 'approved' });
    await db.collection('qr_login_watch').doc('short').set({ status: 'approved' });
    await db.collection('qr_web_sessions').doc('w1').set({ phone: OWNER, status: 'active', renewSecretHash: 'h' });
  });
  const ctxFor = (p) => testEnv.authenticatedContext(`uid_${p}`, { phone_number: `+${p}` }).firestore();
  const unauth = testEnv.unauthenticatedContext().firestore();
  const anon = testEnv.authenticatedContext('anon_1', { firebase: { sign_in_provider: 'anonymous' } }).firestore();
  const owner = ctxFor(OWNER);
  const stranger = ctxFor(STRANGER);
  const adminDb = ctxFor(ADMIN);

  await check('qr_login_sessions: hech kim o\'qiy olmaydi (sir hash/telefon)', async () => {
    for (const d of [unauth, anon, owner, adminDb]) {
      await assertFails(d.collection('qr_login_sessions').doc('s1').get());
      await assertFails(d.collection('qr_login_sessions').limit(5).get());
    }
  });
  await check('qr_login_sessions: hech kim yoza olmaydi (o\'zini tasdiqlash yo\'q)', async () => {
    await assertFails(unauth.collection('qr_login_sessions').doc('s1').update({ status: 'approved', scannedBy: STRANGER }));
    await assertFails(owner.collection('qr_login_sessions').doc('s2').set({ status: 'approved' }));
    await assertFails(adminDb.collection('qr_login_sessions').doc('s1').delete());
  });
  await check('qr_login_watch: sir egasi (auth\'siz ham) o\'z hujjatini get qiladi', async () => {
    await assertSucceeds(unauth.collection('qr_login_watch').doc(WATCH).get());
    await assertSucceeds(anon.collection('qr_login_watch').doc(WATCH).get());
  });
  await check('qr_login_watch: list yo\'q (boshqa sessiyalarni sanab bo\'lmaydi), qisqa ID yo\'q', async () => {
    await assertFails(unauth.collection('qr_login_watch').limit(5).get());
    await assertFails(adminDb.collection('qr_login_watch').limit(5).get());
    await assertFails(unauth.collection('qr_login_watch').doc('short').get());
  });
  await check('qr_login_watch: yozish yo\'q (soxta «approved» qo\'yib bo\'lmaydi)', async () => {
    await assertFails(unauth.collection('qr_login_watch').doc(WATCH).set({ status: 'approved' }));
    await assertFails(owner.collection('qr_login_watch').doc('b'.repeat(64)).set({ status: 'approved' }));
    await assertFails(adminDb.collection('qr_login_watch').doc(WATCH).delete());
  });
  await check('qr_web_sessions: egasi o\'z sessiyasini get qiladi', () => assertSucceeds(owner.collection('qr_web_sessions').doc('w1').get()));
  await check('qr_web_sessions: begona, auth\'siz, anonim o\'qiy olmaydi', async () => {
    await assertFails(stranger.collection('qr_web_sessions').doc('w1').get());
    await assertFails(unauth.collection('qr_web_sessions').doc('w1').get());
    await assertFails(anon.collection('qr_web_sessions').doc('w1').get());
  });
  await check('qr_web_sessions: list yo\'q (egasi va admin ham — callable orqali)', async () => {
    await assertFails(owner.collection('qr_web_sessions').where('phone', '==', OWNER).get());
    await assertFails(adminDb.collection('qr_web_sessions').limit(5).get());
  });
  await check('qr_web_sessions: egasi ham yoza olmaydi (revoked → active qaytarib bo\'lmaydi)', async () => {
    await assertFails(owner.collection('qr_web_sessions').doc('w1').update({ status: 'active', expiresAt: null }));
    await assertFails(owner.collection('qr_web_sessions').doc('w2').set({ phone: OWNER, status: 'active' }));
    await assertFails(adminDb.collection('qr_web_sessions').doc('w1').delete());
  });

  await testEnv.cleanup();
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
