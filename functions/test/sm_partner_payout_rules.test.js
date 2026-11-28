/**
 * «AVA Супермаркет» ҳамкорга тўлов (эга 2026-11-28) — firestore.rules: қарз/тўлов/жамлама/тарих ва settings/sm_partner_payout
 * клиентга ёпиқ (админ ҳам, ҳамкор ҳам — фақат CF орқали).
 *
 *   firebase emulators:exec --only firestore --project demo-sm-partner-rules "node test/sm_partner_payout_rules.test.js"
 *   (RULES_PATH билан бошқа файл, масалан stripped build, текширилади)
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_PATH || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
const USER = '998901000001';
const ADMIN = '998909990001';
const SUPER = '998909990002';
const FIN = '998909990003';
const PARTNER = '998913000001';
const KEY = 'aaaaaaaaaaaaaaaa';
const PID = `ord1__${KEY}`;

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-sm-partner-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  console.log(`rules: ${RULES_PATH}`);
  const results = [];
  const check = async (n, fn) => {
    try { await fn(); results.push(true); console.log(`PASS - ${n}`); } catch (e) { results.push(false); console.log(`FAIL - ${n} :: ${e.message}`); }
  };
  const ctx = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const who = { anon: testEnv.unauthenticatedContext().firestore(), user: ctx(USER), admin: ctx(ADMIN), superadmin: ctx(SUPER), finance: ctx(FIN), partner: ctx(PARTNER) };

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
    await db.doc(`users/${SUPER}`).set({ role: 'superadmin' });
    await db.doc(`users/${FIN}`).set({ role: 'finance' });
    await db.doc(`users/${USER}`).set({ role: 'user' });
    await db.doc(`users/${PARTNER}`).set({ role: 'user' });
    await db.doc(`wholesale_sellers/${PARTNER}`).set({ approvalStatus: 'approved' });
    await db.doc(`sm_partner_payables/${PID}`).set({ partnerKey: KEY, sellerId: PARTNER, amount: 31860, status: 'accrued' });
    await db.doc(`sm_partner_payables/${PID}/events/e1`).set({ type: 'accrued' });
    await db.doc('sm_partner_payments/p1').set({ partnerKey: KEY, sellerId: PARTNER, amount: 31860 });
    await db.doc(`sm_partner_payout_summary/${KEY}`).set({ sellerId: PARTNER, accruedTotal: 31860 });
    await db.doc('sm_partner_payout_history/v1').set({ commissionBp: 1000 });
    await db.doc('settings/sm_partner_payout').set({ stage: 'internal', commissionBp: 1000, version: 1 });
    await db.doc('settings/app').set({ platformDeliveryFeePercent: 11 });
  });

  const paths = [`sm_partner_payables/${PID}`, `sm_partner_payables/${PID}/events/e1`, 'sm_partner_payments/p1', `sm_partner_payout_summary/${KEY}`, 'sm_partner_payout_history/v1', 'settings/sm_partner_payout'];

  await check('R1 ҳеч ким (anon, мижоз, ҳамкор, admin, superadmin, finance) ўқий олмайди — фақат CF', async () => {
    for (const [name, db] of Object.entries(who)) {
      for (const p of paths) {
        try { await assertFails(db.doc(p).get()); } catch (e) { throw new Error(`${name} ${p}: ${e.message}`); }
      }
      await assertFails(db.collection('sm_partner_payables').where('partnerKey', '==', KEY).get());
      await assertFails(db.collection('sm_partner_payments').get());
    }
  });

  await check('R2 ҳеч ким ёза/ўзгартира/ўчира олмайди (paid белгиси, сумма, комиссия, тарих)', async () => {
    for (const [name, db] of Object.entries(who)) {
      const ops = [
        () => db.doc(`sm_partner_payables/${PID}`).update({ status: 'paid' }),
        () => db.doc(`sm_partner_payables/${PID}`).set({ amount: 99999999 }),
        () => db.doc(`sm_partner_payables/${PID}`).delete(),
        () => db.doc('sm_partner_payables/new__bbbbbbbbbbbbbbbb').set({ amount: 1 }),
        () => db.doc(`sm_partner_payables/${PID}/events/e2`).set({ type: 'paid' }),
        () => db.doc('sm_partner_payments/p2').set({ amount: 1 }),
        () => db.doc(`sm_partner_payout_summary/${KEY}`).update({ accruedTotal: 0 }),
        () => db.doc('sm_partner_payout_history/v2').set({ commissionBp: 0 }),
        () => db.doc('settings/sm_partner_payout').set({ stage: 'public', commissionBp: 0 }),
        () => db.doc('settings/sm_partner_payout').update({ commissionBp: 0 }),
      ];
      for (let i = 0; i < ops.length; i += 1) {
        try { await assertFails(ops[i]()); } catch (e) { throw new Error(`${name} op${i}: ${e.message}`); }
      }
    }
  });

  await check('R3 регрессия: settings/app — админ аввалгидек ёзади, мижоз ўқийди (бошқа settings ҳужжатлари ўзгармади)', async () => {
    await assertSucceeds(who.user.doc('settings/app').get());
    await assertSucceeds(who.admin.doc('settings/app').set({ platformDeliveryFeePercent: 11, note: 'x' }, { merge: true }));
    await assertFails(who.user.doc('settings/app').set({ platformDeliveryFeePercent: 0 }, { merge: true }));
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed} passed, ${results.length - passed} failed`);
  await testEnv.cleanup();
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
