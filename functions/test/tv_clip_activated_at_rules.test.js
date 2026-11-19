/**
 * tv_clips.activatedAt — фақат сервер ёзади (эга қарори 2026-11-19).
 *
 * «Кун янгиликлари» 24 соати `activatedAt`дан ҳисобланади: эга уни ўзи
 * ёзса (масалан 2030 йил) клипи доим «янги» бўлиб, янгиликлар табининг
 * бошида қоларди. Шунинг учун клиент яратишда ҳам, таҳрирда ҳам бу
 * майдонга тега олмайди; админ (модерация) ва Admin SDK (CF) — мумкин.
 * Эски илова майдонни умуман ёзмайди — унинг оқими ўзгармайди.
 *
 * Ишлатиш (functions/ ичидан):
 *   firebase emulators:exec --only firestore --project demo-tv-activated-rules \
 *     "node test/tv_clip_activated_at_rules.test.js"
 *   (RULES_PATH билан бошқа файл, масалан stripped build, текширилади)
 */
'use strict';
const path = require('path');
const fs = require('fs');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {serverTimestamp, Timestamp} = require('firebase/firestore');

const RULES_PATH = process.env.RULES_PATH ||
  path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const OWNER = '998901112233';
const ADMIN = '998905550001';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-tv-activated-rules',
    firestore: {rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT)},
  });
  console.log(`rules: ${RULES_PATH}`);
  const results = [];
  async function check(name, fn) {
    try {
      await fn();
      results.push(true);
      console.log(`PASS - ${name}`);
    } catch (e) {
      results.push(false);
      console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }
  const as = (phone) => testEnv.authenticatedContext('uid_' + phone, {phone_number: '+' + phone})
      .firestore();

  async function seed({autoApprove = true} = {}) {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('settings/app').set({tvAutoApprove: autoApprove});
      await db.doc(`users/${ADMIN}`).set({role: 'admin', phone: ADMIN});
      await db.doc('tv_clips/c1').set({
        ownerPhone: OWNER, status: 'active', category: 'product', title: 't',
        createdAt: new Date(Date.now() - 3600 * 1000),
        activatedAt: new Date(Date.now() - 3600 * 1000),
      });
    });
  }
  const newClip = (extra = {}) => ({
    ownerPhone: OWNER, status: 'active', category: 'product', title: 'yangi',
    createdAt: serverTimestamp(), socialConsent: false, ...extra,
  });

  await seed();
  await check('C1 egasi activatedAt siz yaratadi (eski/yangi ilova oqimi) — ruxsat',
      () => assertSucceeds(as(OWNER).collection('tv_clips').add(newClip())));
  await check('C2 egasi activatedAt bilan yaratadi — RAD',
      () => assertFails(as(OWNER).collection('tv_clips').add(
          newClip({activatedAt: Timestamp.fromDate(new Date('2030-01-01'))}))));
  await check('C3 egasi activatedAt = serverTimestamp bilan yaratadi — RAD',
      () => assertFails(as(OWNER).collection('tv_clips').add(
          newClip({activatedAt: serverTimestamp()}))));
  await check('C4 yangilik (news) 24 soatlik expiresAt bilan — ruxsat',
      () => assertSucceeds(as(OWNER).collection('tv_clips').add(newClip({
        category: 'news', expiresAt: Timestamp.fromMillis(Date.now() + 24 * 3600 * 1000),
      }))));

  await seed();
  await check('U1 egasi sarlavhani tahrirlaydi — ruxsat',
      () => assertSucceeds(as(OWNER).doc('tv_clips/c1').update({title: 'yangi'})));
  await check('U2 egasi activatedAt ni o\'zgartiradi — RAD',
      () => assertFails(as(OWNER).doc('tv_clips/c1').update(
          {activatedAt: Timestamp.fromDate(new Date('2030-01-01'))})));
  await check('U3 egasi activatedAt ni o\'chiradi — RAD',
      () => assertFails(as(OWNER).doc('tv_clips/c1').update(
          {activatedAt: require('firebase/firestore').deleteField()})));
  await check('U4 boshqa foydalanuvchi activatedAt — RAD',
      () => assertFails(as('998907778899').doc('tv_clips/c1').update(
          {activatedAt: Timestamp.now()})));
  await check('U5 admin (moderatsiya) — ruxsat',
      () => assertSucceeds(as(ADMIN).doc('tv_clips/c1').update({activatedAt: Timestamp.now()})));

  await testEnv.cleanup();
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
