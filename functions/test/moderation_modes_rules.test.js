/**
 * Moderatsiya rejimlari (rules, ega 2026-11-28, audit C-1): `settings/app` dagi `*AutoApprove` maydonlarini admin
 * klienti to'g'ridan-to'g'ri yoza OLMAYDI (faqat CF + audit); boshqa maydonlar (realtyPricing va h.k.) — avvalgidek.
 *   npm run test:moderation-modes-rules   (functions/ ichidan)
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080').split(':');
const { ALL_MODE_FIELDS } = require('../moderation_modes');

const ADMIN = '998914200009';
const USER = '998914200001';

async function main() {
  const env = await initializeTestEnvironment({
    projectId: 'demo-moderation-modes-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  async function check(name, fn) {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }
  const as = (phone) => env.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${ADMIN}`).set({ phone: ADMIN, role: 'admin' });
    await db.doc(`users/${USER}`).set({ phone: USER, role: 'user' });
    await db.doc('settings/app').set({ tvAutoApprove: false, realtyAutoApprove: true, realtyAgentPhone: '' });
  });

  for (const f of ALL_MODE_FIELDS) {
    await check(`R1 admin ${f} ni to'g'ridan-to'g'ri o'zgartira olmaydi`, () =>
      assertFails(as(ADMIN).doc('settings/app').set({ [f]: f === 'realtyAutoApprove' ? false : true }, { merge: true })));
  }
  await check('R2 admin shopItemAutoApproveUpdatedBy ni soxtalashtira olmaydi', () =>
    assertFails(as(ADMIN).doc('settings/app').set({ shopItemAutoApproveUpdatedBy: 'x' }, { merge: true })));
  await check('R3 admin boshqa maydonlarni (realtyPricing, realtyAgentPhone) yoza oladi', () =>
    assertSucceeds(as(ADMIN).doc('settings/app').set({ realtyAgentPhone: '998901234567', realtyPricing: { promo: { 7: 1000 } } }, { merge: true })));
  await check('R4 eski realty paneli: o\'zgarmagan realtyAutoApprove bilan birga saqlash — OK (diff\'da yo\'q)', () =>
    assertSucceeds(as(ADMIN).doc('settings/app').set({ realtyAgentPhone: '', realtyAutoApprove: true }, { merge: true })));
  await check('R5 eski realty paneli: realtyAutoApprove o\'zgarsa — RAD', () =>
    assertFails(as(ADMIN).doc('settings/app').set({ realtyAgentPhone: '', realtyAutoApprove: false }, { merge: true })));
  await check('R6 boshqa settings hujjatida o\'sha nomli maydon — cheklanmaydi (faqat settings/app)', () =>
    assertSucceeds(as(ADMIN).doc('settings/other_doc').set({ tvAutoApprove: true })));
  await check('R7 user settings/app ga yoza olmaydi (avvalgidek)', () =>
    assertFails(as(USER).doc('settings/app').set({ realtyAgentPhone: '1' }, { merge: true })));
  await check('R8 hamma settings/app ni o\'qiy oladi (avvalgidek — ilova tvAutoApprove ni o\'qiydi)', () =>
    assertSucceeds(as(USER).doc('settings/app').get()));

  await env.cleanup();
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
