/**
 * Qurilma xavfsizligi (ega 2026-11-28) — Firestore rules.
 *
 * Yangi kolleksiyalar (`device_binding_events`, `device_binding_denials`, `device_binding_rate`)
 * uchun rules'da ATAYLAB match YO'Q: deny-by-default — klient (hatto admin) o'qiy/yoza olmaydi,
 * faqat Cloud Functions (Admin SDK). Admin panel ma'lumotni callable orqali oladi
 * (`adminListDeviceApprovals`). `device_transfer_requests`: o'qish egasi/admin, yozish — yo'q.
 *
 * Ishlatish: repo ildizidan
 *   firebase emulators:exec --only firestore --project demo-rules-devsec \
 *     "node functions/test/device_security_rules.test.js"
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

const ADMIN = '998901112233';
const OWNER = '998905556677';
const STRANGER = '998904445566';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-device-security',
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
    await db.collection('device_binding_events').doc('e1').set({ phone: OWNER, action: 'bind' });
    await db.collection('device_binding_denials').doc(`${OWNER}__h`).set({ phone: OWNER });
    await db.collection('device_binding_rate').doc(`p_${OWNER}`).set({ count: 1 });
    await db.collection('device_transfer_requests').doc('r1').set({
      phone: OWNER, status: 'pending', channel: 'admin_review',
    });
  });
  const ctxFor = (p) => testEnv.authenticatedContext(`uid_${p}`, { phone_number: `+${p}` }).firestore();
  const unauth = testEnv.unauthenticatedContext().firestore();
  const owner = ctxFor(OWNER);
  const stranger = ctxFor(STRANGER);
  const adminDb = ctxFor(ADMIN);

  for (const col of ['device_binding_events', 'device_binding_denials', 'device_binding_rate']) {
    await check(`${col}: egasi o'qiy olmaydi (get/list)`, async () => {
      await assertFails(owner.collection(col).limit(5).get());
      const id = col === 'device_binding_events' ? 'e1' : (col === 'device_binding_denials' ? `${OWNER}__h` : `p_${OWNER}`);
      await assertFails(owner.collection(col).doc(id).get());
    });
    await check(`${col}: admin ham klientdan o'qiy olmaydi (faqat callable)`, () => assertFails(adminDb.collection(col).limit(5).get()));
    await check(`${col}: hech kim yoza olmaydi (auditni o'chirish/soxtalashtirish yo'q)`, async () => {
      await assertFails(unauth.collection(col).doc('x').set({ a: 1 }));
      await assertFails(owner.collection(col).doc('x').set({ a: 1 }));
      await assertFails(adminDb.collection(col).doc('x').set({ a: 1 }));
    });
  }
  await check('device_binding_events: admin ham yozuvni o\'chira olmaydi', () => assertFails(adminDb.collection('device_binding_events').doc('e1').delete()));

  await check('device_transfer_requests: egasi o\'z so\'rovini o\'qiydi', () => assertSucceeds(owner.collection('device_transfer_requests').doc('r1').get()));
  await check('device_transfer_requests: begona va auth\'siz o\'qiy olmaydi', async () => {
    await assertFails(stranger.collection('device_transfer_requests').doc('r1').get());
    await assertFails(unauth.collection('device_transfer_requests').doc('r1').get());
  });
  await check('device_transfer_requests: admin o\'qiydi', () => assertSucceeds(adminDb.collection('device_transfer_requests').doc('r1').get()));
  await check('device_transfer_requests: hech kim o\'zi tasdiqlay olmaydi (status yozish yo\'q)', async () => {
    await assertFails(owner.collection('device_transfer_requests').doc('r1').update({ status: 'approved' }));
    await assertFails(adminDb.collection('device_transfer_requests').doc('r1').update({ status: 'approved' }));
    await assertFails(unauth.collection('device_transfer_requests').doc('r2').set({ phone: OWNER, status: 'approved' }));
  });

  await testEnv.cleanup();
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
