/**
 * HISOBNI O'CHIRISH — Firestore rules.
 *
 *   firebase emulators:exec --only firestore --project demo-acct-del-rules \
 *     "node test/account_deletion_rules.test.js"
 *
 * Qulflanadi: klient `users.deletion/deleted/deletedAt/revivedAt` ni yoza/yarata olmaydi (oddiy profil
 * yangilash buzilmaydi); `account_deletions*` va arxiv kolleksiyalariga hech kim (egasi ham, admin ham, mehmon ham)
 * klient orqali kira olmaydi — faqat Admin SDK.
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const ADMIN = '998901110000';
const OWNER = '998911000001';
const OTHER = '998911000002';
const NEWBIE = '998911000003';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-acct-del-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  async function check(name, fn) {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }
  const as = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const anon = () => testEnv.unauthenticatedContext().firestore();

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${ADMIN}`).set({ role: 'admin', phone: `+${ADMIN}` });
    await db.doc(`users/${OWNER}`).set({ role: 'user', phone: `+${OWNER}`, name: 'Ali' });
    await db.doc(`users/${OTHER}`).set({ role: 'user', phone: `+${OTHER}`, name: 'Vali' });
    await db.doc(`account_deletions/${OWNER}`).set({ status: 'PENDING' });
    await db.doc(`account_deletions/${OWNER}/events/e1`).set({ type: 'requested' });
    await db.doc(`account_deletions/${OWNER}/hidden/ads__a1`).set({ prev: 'active' });
    await db.doc(`account_deletion_history/${OWNER}_1`).set({ status: 'DONE' });
    await db.doc(`account_deletion_archive/${OWNER}/wallet_ledger/x`).set({ amount: 1 });
  });

  await check('R1 oddiy profil yangilash buzilmaydi (ism, fcmToken)', async () => {
    await assertSucceeds(as(OWNER).doc(`users/${OWNER}`).update({ name: 'Ali yangi', fcmToken: 'tok' }));
  });

  await check('R2 klient `deletion` holatini yoza olmaydi (soxta holat yoki bekor qilish)', async () => {
    await assertFails(as(OWNER).doc(`users/${OWNER}`).update({ deletion: { status: 'PENDING' } }));
    await assertFails(as(OWNER).doc(`users/${OWNER}`).update({ 'deletion.status': 'CANCELLED' }));
  });

  await check('R3 klient `deleted`, `deletedAt`, `revivedAt` qo\'ya olmaydi', async () => {
    await assertFails(as(OWNER).doc(`users/${OWNER}`).update({ deleted: true }));
    await assertFails(as(OWNER).doc(`users/${OWNER}`).update({ deletedAt: 1 }));
    await assertFails(as(OWNER).doc(`users/${OWNER}`).update({ revivedAt: 1 }));
  });

  await check('R4 qobiq belgisini klient olib tashlay olmaydi (server tiriltiradi)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`users/${NEWBIE}`).set({ deleted: true, deletedAt: 1, role: 'user', bonusBalance: 0 });
    });
    await assertFails(as(NEWBIE).doc(`users/${NEWBIE}`).update({ deleted: false }));
    await assertFails(as(NEWBIE).doc(`users/${NEWBIE}`).update({ phone: `+${NEWBIE}`, deleted: false }));
  });

  await check('R5 yangi hujjat yaratishda ham bu kalitlar taqiqlangan', async () => {
    await assertFails(as('998911000009').doc('users/998911000009').set({ phone: '+998911000009', deleted: true }));
    await assertFails(as('998911000009').doc('users/998911000009').set({ phone: '+998911000009', deletion: { status: 'PENDING' } }));
    await assertSucceeds(as('998911000008').doc('users/998911000008').set({ phone: '+998911000008' }));
  });

  await check('R6 account_deletions va ost-yo\'llari: egasi, begona, mehmon ham o\'qiy/yoza olmaydi', async () => {
    for (const who of [as(OWNER), as(OTHER), anon()]) {
      await assertFails(who.doc(`account_deletions/${OWNER}`).get());
      await assertFails(who.doc(`account_deletions/${OWNER}`).set({ status: 'CANCELLED' }));
      await assertFails(who.doc(`account_deletions/${OWNER}/events/e1`).get());
      await assertFails(who.doc(`account_deletions/${OWNER}/hidden/ads__a1`).get());
      await assertFails(who.collection(`account_deletions/${OWNER}/events`).get());
    }
  });

  await check('R7 tarix va arxiv kolleksiyalari yopiq (admin ham klient orqali yoza/o\'qiy olmaydi)', async () => {
    for (const who of [as(OWNER), as(ADMIN), anon()]) {
      await assertFails(who.doc(`account_deletion_history/${OWNER}_1`).get());
      await assertFails(who.doc(`account_deletion_archive/${OWNER}/wallet_ledger/x`).get());
      await assertFails(who.doc(`account_deletion_archive/${OWNER}/wallet_ledger/y`).set({ amount: 5 }));
    }
    await assertFails(as(ADMIN).doc(`account_deletions/${OWNER}`).set({ status: 'DONE' }));
  });

  await testEnv.cleanup();
  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
