/**
 * «Вакансиялар» (эга 2026-11-28) — `ads` rules: вакансия (`vacancy` бор) эгаси матнни таҳрирлай олади, лекин
 * `type`/`isUrgent`/`vacancy`ни ўзгартира олмайди; оддий эълон эгаси аввалгидек `type`ни алмаштиради; ўқиш —
 * завод саҳифаси сўрови (`vacancy.employerKey` + `status == active`).
 *
 *   firebase emulators:exec --only firestore --project demo-vacancy-rules "node test/vacancy_rules.test.js"
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.ADS_RULES_PATH || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080').split(':');
const OWNER = '998905556601';
const STRANGER = '998905556602';

async function main() {
  const env = await initializeTestEnvironment({
    projectId: 'demo-vacancy-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const check = async (name, fn) => {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  };
  const now = new Date();
  const future = new Date(Date.now() + 86400000);
  const base = {
    text: 'Тажриба 1 йил', title: 'Тикувчи', authorName: 'A', authorPhone: OWNER, address: 'Гурлан',
    isUrgent: false, status: 'active', createdAt: now, editedAt: null, expiresAt: future,
  };
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc('ads/vac').set({
      ...base, type: 'work',
      vacancy: { v: 1, position: 'Тикувчи', employerKey: 'business:f1', requirements: 'Тажриба 1 йил' },
    });
    await db.doc('ads/plain').set({ ...base, type: 'ad' });
    await db.doc(`users/${OWNER}`).set({ role: 'user' });
  });
  const as = (p) => env.authenticatedContext(`uid_${p}`, { phone_number: `+${p}` }).firestore();
  const ts = () => new Date();

  await check('R1 egasi vakansiya matnini tahrirlaydi', () =>
    assertSucceeds(as(OWNER).doc('ads/vac').update({ text: 'Янги талаб', editedAt: ts() })));
  await check('R2 egasi vakansiya turini o\'zgartira olmaydi (work → ad)', () =>
    assertFails(as(OWNER).doc('ads/vac').update({ type: 'ad', editedAt: ts() })));
  await check('R3 egasi vakansiyani shoshilinch qila olmaydi', () =>
    assertFails(as(OWNER).doc('ads/vac').update({ isUrgent: true, editedAt: ts() })));
  await check('R4 egasi vacancy xaritasini o\'zgartira olmaydi', () =>
    assertFails(as(OWNER).doc('ads/vac').update({ 'vacancy.employerKey': 'business:x', editedAt: ts() })));
  await check('R5 oddiy e\'lon egasi turini avvalgidek o\'zgartiradi (ad → service)', () =>
    assertSucceeds(as(OWNER).doc('ads/plain').update({ type: 'service', editedAt: ts() })));
  await check('R6 begona vakansiyani tahrirlay olmaydi', () =>
    assertFails(as(STRANGER).doc('ads/vac').update({ text: 'x', editedAt: ts() })));
  await check('R7 zavod sahifasi so\'rovi (employerKey + active) — ruxsat', () =>
    assertSucceeds(as(STRANGER).collection('ads').where('vacancy.employerKey', '==', 'business:f1')
      .where('status', '==', 'active').limit(20).get()));
  await check('R8 mijoz vakansiya yarata olmaydi (faqat CF)', () =>
    assertFails(as(OWNER).collection('ads').add({ ...base, type: 'work', vacancy: { position: 'x' } })));

  await env.cleanup();
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(1); });
