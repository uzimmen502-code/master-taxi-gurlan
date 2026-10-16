/**
 * tv_clips.linkKind / linkId — эълон/хизмат/Аҳоли бозори/ресторанга ИХТИЁРИЙ
 * видео (эга, 2026-10-16). Тасдиқланадиган даъво: боғлаш фақат КЛИП ҳужжатида,
 * мавжуд қоидалар ЎЗГАРМАСДАН етарли ва хавфсиз (қоида файлига тегилмаган).
 *
 *   firebase emulators:exec --only firestore --project demo-clip-link \
 *     "node functions/test/tv_clip_link_rules.test.js"
 *
 *   A  эгаси `linkKind`/`linkId` билан ОДДИЙ клип яратади
 *   B  боғлаш билан ҳам `category: ad` яратиб бўлмайди (пуллик реклама йўли ёпиқ)
 *   C  бегона одам клип ҳужжатидаги боғлашни ўзгартира олмайди
 *   D  эгаси ўз клипидаги боғлашни ўзгартира/олиб ташлай олади
 *   E  боғлаш орқали статус/тугаш муддати/реклама майдонларини айланиб ўтиб бўлмайди
 *   F  боғлаш `ads` эълон ҳужжатига ҳеч нарса ёзмайди (эълон қоидаси ўзгармаган: create — йўқ)
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

const OWNER = '998901112233';
const OTHER = '998907778899';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-tv-clip-link',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  async function check(name, fn) {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }
  async function reset({ autoApprove = false } = {}) {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('settings').doc('app').set({ tvAutoApprove: autoApprove });
      await ctx.firestore().collection('tv_clips').doc('c1').set({
        ownerPhone: OWNER, status: 'active', category: 'product',
        linkKind: 'ad', linkId: 'A1', viewCount: 0, likeCount: 0,
      });
    });
  }
  const owner = () => testEnv.authenticatedContext('uOwner', { phone_number: `+${OWNER}` }).firestore();
  const other = () => testEnv.authenticatedContext('uOther', { phone_number: `+${OTHER}` }).firestore();

  const newClip = (extra = {}) => ({
    ownerPhone: OWNER, ownerName: 'Али', title: 'Обзор', videoUrl: 'https://x/v.mp4',
    category: 'product', status: 'pending', ...extra,
  });

  await reset();
  await check('A эгаси боғлашли оддий клип яратади (pending)', () =>
    assertSucceeds(owner().collection('tv_clips').doc('n1').set(
      newClip({ linkKind: 'ad', linkId: 'A1' }))));

  await reset({ autoApprove: true });
  await check('A2 авто-тасдиқ ёқиқ — active ҳам яратилади', () =>
    assertSucceeds(owner().collection('tv_clips').doc('n2').set(
      newClip({ status: 'active', linkKind: 'market_ad', linkId: 'M1' }))));

  await reset();
  await check('B боғлаш билан category: ad яратиб бўлмайди', () =>
    assertFails(owner().collection('tv_clips').doc('n3').set(
      newClip({ category: 'ad', linkKind: 'ad', linkId: 'A1' }))));

  await check('B2 бегона номдан (ownerPhone бошқа) яратиб бўлмайди', () =>
    assertFails(other().collection('tv_clips').doc('n4').set(
      newClip({ linkKind: 'ad', linkId: 'A1' }))));

  await reset();
  await check('C бегона одам боғлашни ўзгартира олмайди', () =>
    assertFails(other().collection('tv_clips').doc('c1').update({ linkId: 'HACK' })));
  await check('C2 бегона одам боғлашни олиб ташлай олмайди', () =>
    assertFails(other().collection('tv_clips').doc('c1').update({ linkKind: '', linkId: '' })));

  await check('D эгаси ўз клипидаги боғлашни ўзгартиради', () =>
    assertSucceeds(owner().collection('tv_clips').doc('c1').update({ linkKind: 'service', linkId: 'S9' })));

  await check('E боғлаш билан бирга status ўзгартириб бўлмайди (модерация айланиб ўтилмайди)', () =>
    assertFails(owner().collection('tv_clips').doc('c1').update({ linkId: 'A2', status: 'pending' })));
  await check('E2 боғлаш билан бирга category ad га ўтказиб бўлмайди', () =>
    assertFails(owner().collection('tv_clips').doc('c1').update({ linkId: 'A2', category: 'ad' })));
  await check('E3 боғлаш билан бирга expiresAt ёзиб бўлмайди', () =>
    assertFails(owner().collection('tv_clips').doc('c1').update({ linkId: 'A2', expiresAt: new Date() })));

  await check('F клиент орқали ads ҳужжати яратиб бўлмайди (эълон фақат CF) — боғлаш уни четлаб ўтмайди', () =>
    assertFails(owner().collection('ads').doc('A-new').set({
      type: 'cheap_product', ownerId: OWNER, status: 'active', title: 'x', videoClipId: 'c1',
    })));

  await testEnv.cleanup();
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi`);
  process.exit(failed ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(2); });
