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

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
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

  // videoUrl — эганинг `tv_clips/<ownerPhone>/` папкасидан (аудит 2026-10-31 HIGH-1 қоидаси).
  const newClip = (extra = {}) => {
    const d = { ownerPhone: OWNER, ownerName: 'Али', title: 'Обзор', category: 'product', status: 'pending', ...extra };
    if (!('videoUrl' in extra)) {
      d.videoUrl = `https://firebasestorage.googleapis.com/v0/b/master-taxi-gurlan.firebasestorage.app/o/tv_clips%2F${d.ownerPhone}%2Fv.mp4?alt=media`;
    }
    return d;
  };

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

  // ─── Ресторан видеоси (2026-10-18): ваколат ЯРАТИШ/ЎЗГАРТИРИШда ───
  //   G  эга (а'зо) ва ходим (а'зо) ўз рестораниникига боғлаб яратади
  //   H  а'зо БЎЛМАГАН одам ресторанга боғлаб яратолмайди (ёлғон боғлаш ёпиқ)
  //   I  а'зо бўлмаган одам ўз клипини ресторанга КЎЧИРА олмайди; а'зо кўчира олади
  //   J  боғлаш ўзгармаса — оддий таҳрир (сарлавҳа) ишлайди; бошқа linkKind'лар таъсирланмайди
  const STAFF = '998905554433';
  const staff = () => testEnv.authenticatedContext('uStaff', { phone_number: `+${STAFF}` }).firestore();
  async function resetRestaurant() {
    await reset();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const r = ctx.firestore().collection('restaurants').doc('r1');
      await r.set({ name: 'Ош', status: 'approved', ownerUid: OWNER });
      await r.collection('members').doc(OWNER).set({ role: 'owner' });
      await r.collection('members').doc(STAFF).set({ role: 'staff' });
      await ctx.firestore().collection('tv_clips').doc('own').set({
        ownerPhone: OTHER, status: 'active', category: 'product', title: 'x', viewCount: 0, likeCount: 0,
      });
      await ctx.firestore().collection('tv_clips').doc('rc1').set({
        ownerPhone: STAFF, status: 'active', category: 'product', title: 'x',
        linkKind: 'restaurant', linkId: 'r1', viewCount: 0, likeCount: 0,
      });
    });
  }
  const restClip = (ownerPhone, extra = {}) => newClip({
    ownerPhone, linkKind: 'restaurant', linkId: 'r1', ...extra,
  });

  await resetRestaurant();
  await check('G эга ресторанга боғлаб клип яратади', () =>
    assertSucceeds(owner().collection('tv_clips').doc('g1').set(restClip(OWNER))));
  await check('G2 ходим (а\'зо) ресторанга боғлаб клип яратади', () =>
    assertSucceeds(staff().collection('tv_clips').doc('g2').set(restClip(STAFF))));
  await check('H бегона (а\'зо эмас) ресторанга боғлаб яратолмайди', () =>
    assertFails(other().collection('tv_clips').doc('h1').set(restClip(OTHER))));
  await check('H2 мавжуд бўлмаган ресторан id — яратолмайди', () =>
    assertFails(owner().collection('tv_clips').doc('h2').set(
      newClip({ linkKind: 'restaurant', linkId: 'nope' }))));
  await check('H3 linkId бўш бўлса — яратолмайди', () =>
    assertFails(owner().collection('tv_clips').doc('h3').set(
      newClip({ linkKind: 'restaurant', linkId: '' }))));

  await check('I бегона ўз клипини ресторанга кўчира олмайди', () =>
    assertFails(other().collection('tv_clips').doc('own').update({ linkKind: 'restaurant', linkId: 'r1' })));
  await check('I2 а\'зо (эга) ўз клипини ресторанга боғлайди', () =>
    assertSucceeds(owner().collection('tv_clips').doc('c1').update({ linkKind: 'restaurant', linkId: 'r1' })));
  await check('J ходим ўз боғланган клипини таҳрирлайди (боғлаш ўзгармайди)', () =>
    assertSucceeds(staff().collection('tv_clips').doc('rc1').update({ title: 'Янги' })));
  await check('J2 ходим бошқа ресторанга кўчира олмайди (а\'зоси эмас)', () =>
    assertFails(staff().collection('tv_clips').doc('rc1').update({ linkId: 'r2' })));
  await check('J3 бошқа linkKind (ad) аввалгидек — а\'золик талаб қилинмайди', () =>
    assertSucceeds(other().collection('tv_clips').doc('n9').set(
      newClip({ ownerPhone: OTHER, linkKind: 'ad', linkId: 'A1' }))));

  // ─── Таом видеоси (2026-10-19): linkKind 'restaurant_item', linkId = ресторан, linkItemId = таом ───
  //   K  а'зо (эга/ходим) ўз рестораннинг МАВЖУД таомига боғлаб яратади; бошқа ҳеч ким
  //   L  таом йўқ / бўш / бошқа рестораннинг таоми / ўта узун id — яратиб бўлмайди
  //   M  кўчириш ва ўзгартириш: боғлаш ўзгармаса таҳрир ишлайди; бегона ёки сохта таомга кўчириб бўлмайди
  //   N  ресторан видеоси (restaurant) аввалгидек ишлайди
  async function resetDish() {
    await resetRestaurant();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('restaurants').doc('r1').collection('menu_items').doc('osh').set({ name: 'Osh', price: 40000 });
      await db.collection('restaurants').doc('r1').collection('menu_items').doc('somsa').set({ name: 'Somsa', price: 10000 });
      const r2 = db.collection('restaurants').doc('r2');
      await r2.set({ name: 'Boshqa', status: 'approved', ownerUid: OTHER });
      await r2.collection('members').doc(OTHER).set({ role: 'owner' });
      await r2.collection('menu_items').doc('x').set({ name: 'X', price: 1000 });
      await db.collection('tv_clips').doc('dc1').set({
        ownerPhone: STAFF, status: 'active', category: 'product', title: 'x',
        linkKind: 'restaurant_item', linkId: 'r1', linkItemId: 'osh', viewCount: 0, likeCount: 0,
      });
    });
  }
  const dishClip = (ownerPhone, extra = {}) => newClip({
    ownerPhone, linkKind: 'restaurant_item', linkId: 'r1', linkItemId: 'osh', ...extra,
  });

  await resetDish();
  await check('K эга рестораннинг мавжуд таомига боғлаб клип яратади', () =>
    assertSucceeds(owner().collection('tv_clips').doc('k1').set(dishClip(OWNER))));
  await check('K2 ходим (а\'зо) ҳам яратади', () =>
    assertSucceeds(staff().collection('tv_clips').doc('k2').set(dishClip(STAFF, { linkItemId: 'somsa' }))));
  await check('K3 бегона (а\'зо эмас) яратолмайди', () =>
    assertFails(other().collection('tv_clips').doc('k3').set(dishClip(OTHER))));
  await check('K4 модерация қоидаси сақланади: авто-тасдиқ ўчиқ бўлса active яратиб бўлмайди (pending шарт)', () =>
    assertFails(owner().collection('tv_clips').doc('k4').set(dishClip(OWNER, { status: 'active' }))));

  await check('L таом id мавжуд эмас — яратолмайди', () =>
    assertFails(owner().collection('tv_clips').doc('l1').set(dishClip(OWNER, { linkItemId: 'yoq' }))));
  await check('L2 таом id бўш — яратолмайди', () =>
    assertFails(owner().collection('tv_clips').doc('l2').set(dishClip(OWNER, { linkItemId: '' }))));
  await check('L3 таом id умуман йўқ — яратолмайди', () => {
    const c = dishClip(OWNER); delete c.linkItemId;
    return assertFails(owner().collection('tv_clips').doc('l3').set(c));
  });
  await check('L4 БОШҚА рестораннинг таоми (r2/x) r1 га боғлаб бўлмайди', () =>
    assertFails(owner().collection('tv_clips').doc('l4').set(dishClip(OWNER, { linkItemId: 'x' }))));
  await check('L5 бегона рестораннинг (r2) таомига а\'золиги йўқ одам боғлай олмайди', () =>
    assertFails(owner().collection('tv_clips').doc('l5').set(dishClip(OWNER, { linkId: 'r2', linkItemId: 'x' }))));
  await check('L6 ўта узун таом id (>64) — яратолмайди', () =>
    assertFails(owner().collection('tv_clips').doc('l6').set(dishClip(OWNER, { linkItemId: 'a'.repeat(65) }))));
  await check('L7 таом id матн эмас — яратолмайди', () =>
    assertFails(owner().collection('tv_clips').doc('l7').set(dishClip(OWNER, { linkItemId: 5 }))));

  await check('M ходим ўз таом клипини таҳрирлайди (боғлаш ўзгармайди)', () =>
    assertSucceeds(staff().collection('tv_clips').doc('dc1').update({ title: 'Янги' })));
  await check('M2 ходим клипни ўз рестораннинг ЯНА БИР таомига кўчиради', () =>
    assertSucceeds(staff().collection('tv_clips').doc('dc1').update({ linkItemId: 'somsa' })));
  await check('M3 сохта/бегона таомга кўчира олмайди', () =>
    assertFails(staff().collection('tv_clips').doc('dc1').update({ linkItemId: 'x' })));
  await check('M4 бошқа ресторанга кўчира олмайди (а\'зоси эмас)', () =>
    assertFails(staff().collection('tv_clips').doc('dc1').update({ linkId: 'r2', linkItemId: 'x' })));
  await check('M5 боғлаш олиб ташланганда (таом видеоси оддий клипга айланади) — рухсат', () =>
    assertSucceeds(staff().collection('tv_clips').doc('dc1').update({ linkKind: '', linkId: '', linkItemId: '' })));
  await check('M6 бегона одам ўз клипини таомга кўчира олмайди', () =>
    assertFails(other().collection('tv_clips').doc('own').update({ linkKind: 'restaurant_item', linkId: 'r1', linkItemId: 'osh' })));
  await check('M7 а\'зо (эга) ўз клипини таомга боғлайди', () =>
    assertSucceeds(owner().collection('tv_clips').doc('c1').update({ linkKind: 'restaurant_item', linkId: 'r1', linkItemId: 'osh' })));
  await check('M8 ресторан видеосини (restaurant) таом видеосига айлантириш — таом мавжуд бўлиши шарт', () =>
    assertFails(staff().collection('tv_clips').doc('rc1').update({ linkKind: 'restaurant_item', linkItemId: 'yoq' })));

  await check('N ресторан видеоси аввалгидек: таом id талаб қилинмайди', () =>
    assertSucceeds(owner().collection('tv_clips').doc('n10').set(restClip(OWNER))));

  // ─── Ko'chmas mulk e'loni videosi (2026-10-19): linkKind 'realty_listing', linkId = realty_listings id ───
  //   P  e'lon egasi (va bir xil realtyOwnerKey li jamoa a'zosi) o'z MAVJUD e'loniga bog'lab yaratadi
  //      (sotish ham, ijara ham); begona / e'lon yo'q / id noto'g'ri shakl / kalitsiz foydalanuvchi — yo'q
  //   Q  moderatsiya va pullik reklama yo'li o'zgarmaydi
  //   R  ko'chirish: mavjud klipni e'longa bog'lab bo'lmaydi (60 s chegarasini aylanib o'tish), boshqa e'longa ham;
  //      bog'lash o'zgarmasa tahrir va bog'lashni olib tashlash ishlaydi
  const TEAM = '998906665544'; // bir xil realtyOwnerKey — jamoa hisobi
  const KEYLESS = '998903332211'; // realtyOwnerKey yo'q
  const team = () => testEnv.authenticatedContext('uTeam', { phone_number: `+${TEAM}` }).firestore();
  const keyless = () => testEnv.authenticatedContext('uKeyless', { phone_number: `+${KEYLESS}` }).firestore();
  async function resetRealty({ autoApprove = false } = {}) {
    await reset({ autoApprove });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('users').doc(OWNER).set({ phone: OWNER, realtyOwnerKey: 'keyA' });
      await db.collection('users').doc(TEAM).set({ phone: TEAM, realtyOwnerKey: 'keyA' });
      await db.collection('users').doc(OTHER).set({ phone: OTHER, realtyOwnerKey: 'keyB' });
      await db.collection('users').doc(KEYLESS).set({ phone: KEYLESS });
      await db.collection('realty_listings').doc('Lsale').set({ ownerKey: 'keyA', deal: 'sale', status: 'active' });
      await db.collection('realty_listings').doc('Lrent').set({ ownerKey: 'keyA', deal: 'rent', status: 'pending' });
      await db.collection('realty_listings').doc('Lother').set({ ownerKey: 'keyB', deal: 'sale', status: 'active' });
      await db.collection('tv_clips').doc('rl1').set({
        ownerPhone: OWNER, status: 'active', category: 'product', title: 'x',
        linkKind: 'realty_listing', linkId: 'Lsale', viewCount: 0, likeCount: 0,
      });
    });
  }
  const realtyClip = (ownerPhone, linkId, extra = {}) => newClip({ ownerPhone, linkKind: 'realty_listing', linkId, ...extra });

  await resetRealty();
  await check('P egasi o\'z SOTISH e\'loniga bog\'lab klip yaratadi (pending)', () =>
    assertSucceeds(owner().collection('tv_clips').doc('p1').set(realtyClip(OWNER, 'Lsale'))));
  await check('P2 IJARA e\'loniga ham (deal farqi yo\'q; e\'lon pending bo\'lsa ham)', () =>
    assertSucceeds(owner().collection('tv_clips').doc('p2').set(realtyClip(OWNER, 'Lrent'))));
  await check('P3 jamoa a\'zosi (bir xil realtyOwnerKey) kompaniya e\'loniga yaratadi', () =>
    assertSucceeds(team().collection('tv_clips').doc('p3').set(realtyClip(TEAM, 'Lsale'))));
  await check('P4 BEGONA e\'longa (ownerKey boshqa) bog\'lab bo\'lmaydi', () =>
    assertFails(owner().collection('tv_clips').doc('p4').set(realtyClip(OWNER, 'Lother'))));
  await check('P5 begona odam egasining e\'loniga bog\'lab bo\'lmaydi', () =>
    assertFails(other().collection('tv_clips').doc('p5').set(realtyClip(OTHER, 'Lsale'))));
  await check('P6 mavjud bo\'lmagan e\'lon id — yaratolmaydi', () =>
    assertFails(owner().collection('tv_clips').doc('p6').set(realtyClip(OWNER, 'yoq_elon'))));
  await check('P7 linkId bo\'sh — yaratolmaydi', () =>
    assertFails(owner().collection('tv_clips').doc('p7').set(realtyClip(OWNER, ''))));
  await check('P8 linkId matn emas — yaratolmaydi', () =>
    assertFails(owner().collection('tv_clips').doc('p8').set(realtyClip(OWNER, 5))));
  await check('P9 linkId yo\'l qismlari bilan (Lsale/private/detail) — yaratolmaydi', () =>
    assertFails(owner().collection('tv_clips').doc('p9').set(realtyClip(OWNER, 'Lsale/private/detail'))));
  await check('P10 realtyOwnerKey yo\'q foydalanuvchi — yaratolmaydi', () =>
    assertFails(keyless().collection('tv_clips').doc('p10').set(realtyClip(KEYLESS, 'Lsale'))));
  await check('P11 begona nomdan (ownerPhone boshqa) — yaratolmaydi', () =>
    assertFails(other().collection('tv_clips').doc('p11').set(realtyClip(OWNER, 'Lsale'))));

  await check('Q moderatsiya saqlanadi: avto-tasdiq o\'chiq bo\'lsa active yaratib bo\'lmaydi', () =>
    assertFails(owner().collection('tv_clips').doc('q1').set(realtyClip(OWNER, 'Lsale', { status: 'active' }))));
  await check('Q2 pullik reklama yo\'li yopiq: category ad bilan yaratib bo\'lmaydi', () =>
    assertFails(owner().collection('tv_clips').doc('q2').set(realtyClip(OWNER, 'Lsale', { category: 'ad' }))));
  await resetRealty({ autoApprove: true });
  await check('Q3 avto-tasdiq yoqiq — active ham yaratiladi', () =>
    assertSucceeds(owner().collection('tv_clips').doc('q3').set(realtyClip(OWNER, 'Lsale', { status: 'active' }))));

  await resetRealty();
  await check('R egasi bog\'lash o\'zgarmaydigan tahrirni qiladi (sarlavha)', () =>
    assertSucceeds(owner().collection('tv_clips').doc('rl1').update({ title: 'Yangi' })));
  await check('R2 e\'lon bog\'lashni olib tashlash (oddiy klipga aylanadi) — ruxsat', () =>
    assertSucceeds(owner().collection('tv_clips').doc('rl1').update({ linkKind: '', linkId: '' })));
  await resetRealty();
  await check('R3 klipni BOSHQA (o\'z) e\'loniga ko\'chirib bo\'lmaydi', () =>
    assertFails(owner().collection('tv_clips').doc('rl1').update({ linkId: 'Lrent' })));
  await check('R4 MAVJUD oddiy klipni (ad, c1) e\'longa bog\'lab bo\'lmaydi — 60 s chegarasi aylanib o\'tilmaydi', () =>
    assertFails(owner().collection('tv_clips').doc('c1').update({ linkKind: 'realty_listing', linkId: 'Lsale' })));
  await check('R5 begona e\'lon klipini o\'zgartira olmaydi', () =>
    assertFails(other().collection('tv_clips').doc('rl1').update({ title: 'Hack' })));
  await check('R6 boshqa turlar ta\'sirlanmaydi: ad klipi (c1) ad/service ga o\'tkazish ishlaydi', () =>
    assertSucceeds(owner().collection('tv_clips').doc('c1').update({ linkKind: 'service', linkId: 'S9' })));

  await testEnv.cleanup();
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi`);
  process.exit(failed ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(2); });
