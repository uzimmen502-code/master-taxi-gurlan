/**
 * `ledger_reconcile_runs` rules — кунлик ҳамён инвариантлари ҳисоботи фақат молия/аудит ўқийди, клиент ёза олмайди.
 *
 *   firebase emulators:exec --only firestore --project demo-wic-rules \
 *     "node functions/test/wallet_invariants_rules.test.js"
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const ROLES = {
  '998901000001': 'superadmin',
  '998901000002': 'finance',
  '998901000003': 'auditor',
  '998901000004': 'admin',
  '998901000005': 'dispatcher',
  '998901000006': 'client',
};

(async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-wic-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    for (const [p, role] of Object.entries(ROLES)) await db.collection('users').doc(p).set({ role, phone: p });
    await db.collection('ledger_reconcile_runs').doc('2026-11-28').set({ ok: false });
  });
  const as = (p) => env.authenticatedContext(`uid_${p}`, { phone_number: `+${p}` }).firestore();
  const results = [];
  const check = async (name, fn) => {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  };
  const doc = (db) => db.collection('ledger_reconcile_runs').doc('2026-11-28');

  for (const p of ['998901000001', '998901000002', '998901000003']) {
    await check(`R1 ${ROLES[p]} o'qiy oladi`, () => assertSucceeds(doc(as(p)).get()));
    await check(`R2 ${ROLES[p]} ham yoza olmaydi`, () => assertFails(doc(as(p)).set({ ok: true })));
  }
  for (const p of ['998901000004', '998901000005', '998901000006']) {
    await check(`R3 ${ROLES[p]} o'qiy olmaydi`, () => assertFails(doc(as(p)).get()));
    await check(`R4 ${ROLES[p]} ro'yxatni o'qiy olmaydi`, () => assertFails(as(p).collection('ledger_reconcile_runs').get()));
    await check(`R5 ${ROLES[p]} yarata olmaydi`, () => assertFails(as(p).collection('ledger_reconcile_runs').doc('x').set({ ok: true })));
  }
  await check('R6 anonim o\'qiy olmaydi', () => assertFails(doc(env.unauthenticatedContext().firestore()).get()));

  await env.cleanup();
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed} passed, ${results.length - passed} failed`);
  process.exit(results.length - passed ? 1 : 0);
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
