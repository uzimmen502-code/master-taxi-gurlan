/**
 * `provider_capabilities` Firestore rules — D-12…D-16, T-1a.
 *
 * Shakl: kalit = barqaror `accountId` (`users/{phone}.accountId`, server
 * beradi). Ichida xizmatlar (klient), `identity`/`status`/`window`/
 * `review`/`suspend` — FAQAT server.
 *
 * ENG MUHIM (D-14): foydalanuvchi o'ziga `approved`/`verified` berolmasin;
 * `accountId` ni o'zgartirib boshqaning starter davrini ololmasin.
 *
 * Ishlatish: repo ildizidan
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/provider_capabilities_rules.test.js"
 */
'use strict';
const path = require('path');
const fs = require('fs');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');

const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const ADMIN = '998901112233';
const OWNER = '998902223344';
const OWNER_ACC = 'accOWNER00000000000000';
/** Eski 9 xonali `users` kaliti bilan foydalanuvchi. */
const OLD9 = '903334455';
const OLD9_FULL = '998903334455';
const OLD9_ACC = 'accOLD9000000000000000';
const STRANGER = '998904445566';
const STRANGER_ACC = 'accSTRANGER00000000000';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-capabilities',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });

  const results = [];
  const record = (name, pass, detail) => {
    results.push({ name, pass, detail });
    console.log(`${pass ? 'PASS' : 'FAIL'} - ${name}${detail ? ' :: ' + detail : ''}`);
  };
  async function check(name, fn) {
    try { await fn(); record(name, true); } catch (e) { record(name, false, e.message); }
  }

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('users').doc(ADMIN).set({ role: 'admin' });
    await db.collection('users').doc(OWNER).set({ role: 'user', accountId: OWNER_ACC });
    await db.collection('users').doc(OLD9).set({ role: 'user', accountId: OLD9_ACC });
    await db.collection('users').doc(STRANGER).set({ role: 'user', accountId: STRANGER_ACC });
    // Server (`requestCapability`) yozgan holat.
    await db.collection('provider_capabilities').doc(OWNER_ACC).set({
      identity: { accountId: OWNER_ACC, primaryUid: OWNER },
      courier: { active: true, regionIds: ['xorazm'] },
      taxi: { active: true, regionIds: ['xorazm'] },
      status: { courier: 'trial', taxi: 'starter' },
      window: { courier: { endsAt: new Date(), graceGrantedAt: null }, taxi: { verificationDueAt: new Date() } },
    });
    await db.collection('provider_capabilities').doc(OLD9_ACC).set({
      identity: { accountId: OLD9_ACC, primaryUid: OLD9_FULL },
      courier: { active: true },
      status: { courier: 'approved' },
    });
  });

  const ctxFor = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: '+' + phone });
  const unauth = testEnv.unauthenticatedContext().firestore();
  const owner = ctxFor(OWNER).firestore();
  const old9 = ctxFor(OLD9_FULL).firestore();
  const stranger = ctxFor(STRANGER).firestore();
  const adminDb = ctxFor(ADMIN).firestore();
  const doc = (db, id) => db.collection('provider_capabilities').doc(id);
  const users = (db, id) => db.collection('users').doc(id);

  // ── O'QISH ──────────────────────────────────────────────────────────
  await check('egasi o\'z capability\'sini o\'qiydi (accountId orqali)', () => assertSucceeds(doc(owner, OWNER_ACC).get()));
  await check('9 xonali eski users kalitli ega ham o\'qiydi', () => assertSucceeds(doc(old9, OLD9_ACC).get()));
  await check('admin o\'qiydi', () => assertSucceeds(doc(adminDb, OWNER_ACC).get()));
  await check('begona o\'qiy olmaydi', () => assertFails(doc(stranger, OWNER_ACC).get()));
  await check('autentifikatsiyasiz o\'qiy olmaydi', () => assertFails(doc(unauth, OWNER_ACC).get()));
  await check('ro\'yxatni olib bo\'lmaydi', () => assertFails(stranger.collection('provider_capabilities').get()));

  // ── D-14: SERVER KALITLARI ──────────────────────────────────────────
  await check('egasi `status` ni o\'zgartira OLMAYDI', () => assertFails(doc(owner, OWNER_ACC).update({ 'status.courier': 'approved' })));
  await check('egasi taksini `verified` qila OLMAYDI (D-TAXI-4)', () => assertFails(doc(owner, OWNER_ACC).update({ 'status.taxi': 'verified' })));
  await check('egasi 4 oylik oynani cho\'za olmaydi (D-TAXI-2)', () => assertFails(doc(owner, OWNER_ACC).update({ 'window.taxi.verificationDueAt': new Date(Date.now() + 999 * 86400000) })));
  await check('egasi `identity` ni o\'zgartira olmaydi', () => assertFails(doc(owner, OWNER_ACC).update({ 'identity.primaryUid': STRANGER })));
  await check('egasi `review`/`suspend` ga tegolmaydi', () => assertFails(doc(owner, OWNER_ACC).update({ 'suspend.courier': null, 'review.courier': {} })));
  await check('egasi `debt` (qarz) ni o\'chira olmaydi (D-TAXI-CANCEL-6)', () => assertFails(doc(owner, OWNER_ACC).update({ 'debt.taxi': 0 })));
  await check('YANGI xizmat ham avtomatik himoyalangan (`status.freight`)', () => assertFails(doc(owner, OWNER_ACC).update({ 'status.freight': 'enabled' })));
  await check('egasi hujjat YARATA OLMAYDI — faqat server', () => assertFails(doc(stranger, STRANGER_ACC).set({ courier: { active: true } })));
  await check('yaratishda ham `status`/`identity` bera olmaydi', () => assertFails(doc(stranger, STRANGER_ACC).set({
    identity: { accountId: STRANGER_ACC, primaryUid: STRANGER }, status: { taxi: 'verified' },
  })));

  // ── KLIENT O'Z MA'LUMOTINI YOZADI ───────────────────────────────────
  await check('egasi xizmat map\'ini yozadi (regression)', () => assertSucceeds(doc(owner, OWNER_ACC).set({
    courier: { active: true, categoryIds: ['posilka'], regionIds: ['xorazm'] }, updatedAt: new Date(),
  }, { merge: true })));
  await check('TUZOQ: server status yozgandan keyin ham klient yozuvi o\'tadi', () => assertSucceeds(doc(owner, OWNER_ACC).update({ 'courier.active': false })));
  await check('egasi boshqa xizmatni ham qo\'shadi (D-13)', () => assertSucceeds(doc(owner, OWNER_ACC).set({ seller: { active: true } }, { merge: true })));
  await check('egasi `trustScore` yoza olmaydi', () => assertFails(doc(owner, OWNER_ACC).update({ trustScore: 99 })));

  // ── BEGONA ──────────────────────────────────────────────────────────
  await check('begona boshqaning capability\'sini yoza olmaydi', () => assertFails(doc(stranger, OWNER_ACC).set({ courier: { active: false } }, { merge: true })));
  await check('autentifikatsiyasiz yoza olmaydi', () => assertFails(doc(unauth, OWNER_ACC).set({ courier: { active: false } }, { merge: true })));

  // ── accountId O'G'IRLASH (T-1a) ─────────────────────────────────────
  await check('foydalanuvchi o\'z `users.accountId` sini O\'ZGARTIRA OLMAYDI', () => assertFails(users(stranger, STRANGER).update({ accountId: OWNER_ACC })));
  await check('foydalanuvchi `users` yaratishda accountId bera olmaydi', () => assertFails(users(ctxFor('998909998877').firestore(), '998909998877').set({ phone: '998909998877', accountId: OWNER_ACC })));
  await check('oddiy profil yangilash hamon ishlaydi (regression)', () => assertSucceeds(users(stranger, STRANGER).update({ name: 'Sardor', updatedAt: new Date() })));

  // ── ADMIN ───────────────────────────────────────────────────────────
  await check('ADMIN taksini verified qiladi', () => assertSucceeds(doc(adminDb, OWNER_ACC).update({ 'status.taxi': 'verified', 'review.taxi': { reviewedBy: ADMIN, at: new Date() } })));
  await check('ADMIN to\'xtatadi', () => assertSucceeds(doc(adminDb, OWNER_ACC).update({ 'status.courier': 'suspended', 'suspend.courier': { reason: 'documents_missing', by: ADMIN } })));
  await check('egasi hujjatni o\'chira olmaydi (16-qoida)', () => assertFails(doc(owner, OWNER_ACC).delete()));
  await check('admin o\'chiradi', () => assertSucceeds(doc(adminDb, OLD9_ACC).delete()));

  await testEnv.cleanup();
  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} provider_capabilities rules checks passed.`);
  if (failed.length) { console.log('FAILED:', failed.map((f) => f.name).join(', ')); process.exitCode = 1; }
}

main().catch((e) => { console.error('FATAL', e); process.exitCode = 1; });
