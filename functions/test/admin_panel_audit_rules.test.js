/**
 * Admin panel ↔ ilova muvofiqlik auditi (2026-10-07/08) — Firestore rules.
 *
 * Qulflanadi:
 *   risk_events          — avval create/read/update `if true` edi
 *   admin_news           — create/update auth'siz edi (hammaga push)
 *   users.role           — admin/dispatcher to'g'ridan-to'g'ri istalgan rol
 *   entertainment_catalog — «admin PIN» yo'li auth'siz edi
 *   intercity_drivers.entertainmentAllowed — auth'siz yoqish/o'chirish
 *   tv_clips create      — moderatsiyani chetlab `active`; begona ownerPhone;
 *                          socialRetryAt (AVA sahifalariga takroriy post)
 *   marshrut_state       — admin «Dispatch history → Yakunlandi» yoza olmasdi
 *
 * Ishlatish: repo ildizidan
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/admin_panel_audit_rules.test.js"
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

const ADMIN = '998901112233';
const SUPER = '998901112255';
const DISPATCHER = '998901112244';
const OWNER = '998905556677';
const STRANGER = '998904445566';
const DRIVER = '998907778899';

function riskEvent(userId, extra = {}) {
  return {
    userId,
    type: 'birthdate_change_request',
    severity: 'medium',
    status: 'open',
    deviceId: '',
    message: 'Tug\'ilgan kun o\'zgartirish so\'rovi',
    meta: {},
    createdAt: new Date(),
    updatedAt: new Date(),
    ...extra,
  };
}

function news(extra = {}) {
  return {
    title: 'Yangilik',
    body: 'Matn',
    category: 'info',
    audience: 'all',
    priority: 0,
    createdAt: new Date(),
    ...extra,
  };
}

function film(extra = {}) {
  return {
    title: 'Safar filmi',
    storagePath: 'entertainment/1700000000000.mp4',
    downloadUrl: 'https://example.com/film.mp4',
    durationSec: 0,
    active: true,
    sortOrder: 1,
    createdAt: new Date(),
    ...extra,
  };
}

function clip(extra = {}) {
  return {
    videoUrl: 'https://example.com/v.mp4',
    posterUrl: '',
    title: 'Non',
    price: 0,
    districtId: 'gurlan',
    ownerPhone: OWNER,
    ownerName: 'Aziz',
    category: 'product',
    status: 'pending',
    socialConsent: false,
    socialNetworks: [],
    createdAt: new Date(),
    ...extra,
  };
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-admin-audit',
    firestore: {
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
      host: HOST,
      port: Number(PORT),
    },
  });

  const results = [];
  function record(name, pass, detail) {
    results.push({name, pass, detail});
    console.log(`${pass ? 'PASS' : 'FAIL'} - ${name}${detail ? ' :: ' + detail : ''}`);
  }
  async function check(name, fn) {
    try {
      await fn();
      record(name, true);
    } catch (e) {
      record(name, false, e.message);
    }
  }

  async function seed(tvAutoApprove) {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('users').doc(ADMIN).set({role: 'admin', phone: '+' + ADMIN});
      await db.collection('users').doc(DISPATCHER).set({role: 'dispatcher', phone: '+' + DISPATCHER});
      await db.collection('users').doc(SUPER).set({role: 'superadmin', phone: '+' + SUPER});
      await db.collection('settings').doc('wallet_bot').set({
        depositCardNumber: '8600000000000000', topUpApproveMode: 'manual',
      });
      await db.collection('settings').doc('anomaly_settings').set({maxDailyWithdraw: 1000000});
      await db.collection('users').doc(OWNER).set({role: 'user', phone: '+' + OWNER, name: 'Aziz'});
      await db.collection('users').doc(STRANGER).set({role: 'user', phone: '+' + STRANGER});
      await db.collection('settings').doc('app').set({tvAutoApprove});
      await db.collection('risk_events').doc('r1').set(riskEvent(OWNER));
      await db.collection('admin_news').doc('n1').set(news());
      await db.collection('entertainment_catalog').doc('f1').set(film());
      await db.collection('intercity_drivers').doc(DRIVER).set({
        isActive: false, entertainmentAllowed: false, seats: 4,
      });
      await db.collection('tv_clips').doc('c1').set(clip({status: 'active'}));
      await db.collection('users').doc(OWNER)
          .collection('marshrut_state').doc('active').set({
            tripId: 't1', status: 'accepted', updatedAt: new Date(),
          });
    });
  }

  function ctxFor(phone) {
    return testEnv.authenticatedContext(`uid_${phone}`, {phone_number: '+' + phone});
  }
  const unauth = () => testEnv.unauthenticatedContext().firestore();
  /** Anonim sessiya: auth bor, telefon claim yo'q. */
  const anon = () => testEnv.authenticatedContext('anon_uid_1', {}).firestore();
  const as = (phone) => ctxFor(phone).firestore();

  await seed(false);

  // ── risk_events ─────────────────────────────────────────────────────
  await check('risk_events: kirmagan o\'qiy olmaydi',
      () => assertFails(unauth().collection('risk_events').doc('r1').get()));
  await check('risk_events: anonim ro\'yxatni o\'qiy olmaydi',
      () => assertFails(anon().collection('risk_events').where('status', '==', 'open').get()));
  await check('risk_events: egasi ham ro\'yxatni o\'qiy olmaydi (faqat admin)',
      () => assertFails(as(OWNER).collection('risk_events').doc('r1').get()));
  await check('risk_events: kirmagan yarata olmaydi',
      () => assertFails(unauth().collection('risk_events').add(riskEvent(OWNER))));
  await check('risk_events: begona boshqa odam nomidan yarata olmaydi',
      () => assertFails(as(STRANGER).collection('risk_events').add(riskEvent(OWNER))));
  await check('risk_events: egasi o\'zi uchun `open` yaratadi (requestBirthDateChange)',
      () => assertSucceeds(as(OWNER).collection('risk_events').add(riskEvent(OWNER))));
  await check('risk_events: egasi `resolved` holatda yarata olmaydi',
      () => assertFails(as(OWNER).collection('risk_events').add(
          riskEvent(OWNER, {status: 'resolved'}))));
  await check('risk_events: egasi hodisani yopa olmaydi',
      () => assertFails(as(OWNER).collection('risk_events').doc('r1').set(
          {status: 'resolved'}, {merge: true})));
  await check('risk_events: admin `status==open` ro\'yxatini o\'qiydi (badge + Risk review)',
      () => assertSucceeds(as(ADMIN).collection('risk_events').where('status', '==', 'open').get()));
  await check('risk_events: admin yopadi (resolveRiskEvent)',
      () => assertSucceeds(as(ADMIN).collection('risk_events').doc('r1').set({
        status: 'resolved', resolvedAt: new Date(), resolvedBy: ADMIN, updatedAt: new Date(),
      }, {merge: true})));

  // ── admin_news ──────────────────────────────────────────────────────
  await check('admin_news: o\'qish hamon ochiq (ilova lentasi buzilmaydi)',
      () => assertSucceeds(unauth().collection('admin_news').doc('n1').get()));
  await check('admin_news: kirmagan yarata olmaydi (hammaga push)',
      () => assertFails(unauth().collection('admin_news').add(news())));
  await check('admin_news: oddiy foydalanuvchi yarata olmaydi',
      () => assertFails(as(OWNER).collection('admin_news').add(news())));
  await check('admin_news: oddiy foydalanuvchi pushResendAt ni o\'zgartira olmaydi',
      () => assertFails(as(OWNER).collection('admin_news').doc('n1').set(
          {pushResendAt: new Date()}, {merge: true})));
  await check('admin_news: admin yaratadi (compose)',
      () => assertSucceeds(as(ADMIN).collection('admin_news').add(news())));
  await check('admin_news: admin push qayta yuboradi (requestPushResend)',
      () => assertSucceeds(as(ADMIN).collection('admin_news').doc('n1').set(
          {pushResendAt: new Date()}, {merge: true})));
  await check('admin_news: admin ham noto\'g\'ri audience bilan yarata olmaydi',
      () => assertFails(as(ADMIN).collection('admin_news').add(news({audience: 'hack'}))));

  // ── users.role ──────────────────────────────────────────────────────
  await check('users.role: dispatcher o\'ziga superadmin yoza olmaydi',
      () => assertFails(as(DISPATCHER).collection('users').doc(DISPATCHER).update({role: 'superadmin'})));
  await check('users.role: dispatcher boshqaga admin bera olmaydi',
      () => assertFails(as(DISPATCHER).collection('users').doc(OWNER).update({role: 'admin'})));
  await check('users.role: admin ham to\'g\'ridan-to\'g\'ri rol bera olmaydi (faqat CF)',
      () => assertFails(as(ADMIN).collection('users').doc(OWNER).update({role: 'seller'})));
  await check('users: admin rolga tegmay profil maydonini yangilaydi',
      () => assertSucceeds(as(ADMIN).collection('users').doc(OWNER).update({name: 'Aziz A.'})));
  await check('users: egasi o\'z ismini yangilaydi',
      () => assertSucceeds(as(OWNER).collection('users').doc(OWNER).update({name: 'Aziz B.'})));

  // ── entertainment_catalog ───────────────────────────────────────────
  await check('kino: kirmagan katalogga film qo\'sha olmaydi',
      () => assertFails(unauth().collection('entertainment_catalog').doc('f2').set(film())));
  await check('kino: oddiy foydalanuvchi film qo\'sha olmaydi',
      () => assertFails(as(OWNER).collection('entertainment_catalog').doc('f2').set(film())));
  await check('kino: kirmagan filmni o\'chira (active=false) olmaydi',
      () => assertFails(unauth().collection('entertainment_catalog').doc('f1').update(
          {active: false, updatedAt: new Date()})));
  await check('kino: admin film qo\'shadi (Kino katalogi tabi)',
      () => assertSucceeds(as(ADMIN).collection('entertainment_catalog').doc('f3').set(film())));
  await check('kino: admin ham noto\'g\'ri storagePath bilan qo\'sha olmaydi',
      () => assertFails(as(ADMIN).collection('entertainment_catalog').doc('f4').set(
          film({storagePath: 'other/x.mp4'}))));
  await check('kino: admin filmni o\'chiradi/yoqadi',
      () => assertSucceeds(as(ADMIN).collection('entertainment_catalog').doc('f1').update(
          {active: false, updatedAt: new Date()})));

  // ── intercity_drivers.entertainmentAllowed ──────────────────────────
  await check('kino ruxsati: kirmagan haydovchiga yoqa olmaydi',
      () => assertFails(unauth().collection('intercity_drivers').doc(DRIVER).update(
          {entertainmentAllowed: true, updatedAt: new Date()})));
  await check('kino ruxsati: kirmagan yangi hujjat yarata olmaydi',
      () => assertFails(unauth().collection('intercity_drivers').doc('998900000000').set(
          {entertainmentAllowed: true, updatedAt: new Date()})));
  await check('kino ruxsati: begona yoqa olmaydi',
      () => assertFails(as(STRANGER).collection('intercity_drivers').doc(DRIVER).update(
          {entertainmentAllowed: true, updatedAt: new Date()})));
  await check('kino ruxsati: admin yoqadi (Shaharlararo → Kino switch)',
      () => assertSucceeds(as(ADMIN).collection('intercity_drivers').doc(DRIVER).update(
          {entertainmentAllowed: true, updatedAt: new Date()})));

  // ── tv_clips (QO'LDA rejim: tvAutoApprove=false) ────────────────────
  await check('tv_clips: egasi `pending` klip yaratadi',
      () => assertSucceeds(as(OWNER).collection('tv_clips').add(clip())));
  await check('tv_clips: QO\'LDA rejimda egasi `active` yarata olmaydi (moderatsiya chetlab)',
      () => assertFails(as(OWNER).collection('tv_clips').add(clip({status: 'active'}))));
  await check('tv_clips: begona `ownerPhone` bilan yarata olmaydi',
      () => assertFails(as(STRANGER).collection('tv_clips').add(clip())));
  await check('tv_clips: yaratishda socialRetryAt yoza olmaydi',
      () => assertFails(as(OWNER).collection('tv_clips').add(clip({socialRetryAt: 123}))));
  await check('tv_clips: `ad` kategoriya hamon faqat CF',
      () => assertFails(as(OWNER).collection('tv_clips').add(clip({category: 'ad'}))));
  await check('tv_clips: kirmagan yarata olmaydi',
      () => assertFails(unauth().collection('tv_clips').add(clip())));
  await check('tv_clips: egasi socialRetryAt ni o\'zgartira olmaydi (takroriy post)',
      () => assertFails(as(OWNER).collection('tv_clips').doc('c1').update({socialRetryAt: 999})));
  await check('tv_clips: egasi sarlavhani tahrirlaydi (updateOwnClip)',
      () => assertSucceeds(as(OWNER).collection('tv_clips').doc('c1').update({title: 'Yangi'})));
  await check('tv_clips: admin `active` yaratadi',
      () => assertSucceeds(as(ADMIN).collection('tv_clips').add(clip({status: 'active'}))));
  await check('tv_clips: admin socialRetryAt qo\'yadi («Соцсетга жойлаш»)',
      () => assertSucceeds(as(ADMIN).collection('tv_clips').doc('c1').update({socialRetryAt: 1000})));

  // ── settings/wallet_bot, settings/anomaly_settings ──────────────────
  const settings = (db, id) => db.collection('settings').doc(id);
  await check('wallet_bot: kirmagan o\'qiy olmaydi (depozit kartasi)',
      () => assertFails(settings(unauth(), 'wallet_bot').get()));
  await check('wallet_bot: dispatcher depozit kartasini o\'zgartira olmaydi',
      () => assertFails(settings(as(DISPATCHER), 'wallet_bot').set(
          {depositCardNumber: '9860111122223333'}, {merge: true})));
  await check('wallet_bot: superadmin ham klientdan yoza olmaydi (faqat CF)',
      () => assertFails(settings(as(SUPER), 'wallet_bot').set(
          {topUpApproveMode: 'auto'}, {merge: true})));
  await check('anomaly_settings: admin yoza olmaydi (panelda superadmin bo\'limi)',
      () => assertFails(settings(as(ADMIN), 'anomaly_settings').set(
          {maxDailyWithdraw: 99999999}, {merge: true})));
  await check('anomaly_settings: superadmin yozadi',
      () => assertSucceeds(settings(as(SUPER), 'anomaly_settings').set(
          {maxDailyWithdraw: 2000000, updatedAt: new Date()}, {merge: true})));
  await check('anomaly_settings: o\'qish ochiq (ekran o\'qiydi)',
      () => assertSucceeds(settings(as(ADMIN), 'anomaly_settings').get()));
  await check('settings/app: admin hamon yozadi (regressiya yo\'q)',
      () => assertSucceeds(settings(as(ADMIN), 'app').set(
          {jobsAutoApprove: true}, {merge: true})));
  await check('settings/app: hamma o\'qiydi (ilova)',
      () => assertSucceeds(settings(unauth(), 'app').get()));

  // ── ads (Onlayn bozor): admin rad etgani egasi qayta ocholmaydi ─────
  const marketAd = (extra) => ({
    type: 'cheap_product', ownerId: OWNER, phone: OWNER, price: 50000,
    title: 'Velosiped', description: 'Yaxshi holatda', imageUrls: ['https://x/1.jpg'],
    status: 'inactive', ...extra,
  });
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('ads').doc('mk1').set(marketAd({adminRejected: true}));
    await ctx.firestore().collection('ads').doc('mk2').set(marketAd({autoExpiredAt: new Date()}));
    await ctx.firestore().collection('ads').doc('mk3').set(marketAd({status: 'active'}));
  });
  const ad = (db, id) => db.collection('ads').doc(id);
  await check('bozor: admin rad etgan e\'lonni egasi qayta joylashtira olmaydi',
      () => assertFails(ad(as(OWNER), 'mk1').update({status: 'pending', updatedAt: new Date()})));
  await check('bozor: egasi adminRejected belgisini o\'chira olmaydi',
      () => assertFails(ad(as(OWNER), 'mk1').update({adminRejected: false})));
  await check('bozor: muddati o\'tgan (admin rad etmagan) e\'lonni egasi qayta joylaydi',
      () => assertSucceeds(ad(as(OWNER), 'mk2').update({status: 'pending', updatedAt: new Date()})));
  await check('bozor: egasi faol e\'lonni yashiradi (regressiya yo\'q)',
      () => assertSucceeds(ad(as(OWNER), 'mk3').update({status: 'inactive', updatedAt: new Date()})));

  // Rasmlar soni 1..7 (ega qarori, 2026-10-17; avval 1..5). Yaratish CF orqali
  // (`marketImageUrlsOk`), egasining tahriri esa shu qoida orqali.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('ads').doc('mk4').set(marketAd({}));
  });
  const adImgs = (n) => Array.from({length: n}, (_, i) => `https://x/${i}.jpg`);
  await check('bozor rasm: egasi tahrirda 5 ta rasm (eski ilova) — o\'tadi',
      () => assertSucceeds(ad(as(OWNER), 'mk4').update({imageUrls: adImgs(5), status: 'pending', updatedAt: new Date()})));
  await check('bozor rasm: egasi tahrirda 7 ta rasm (chegara) — o\'tadi',
      () => assertSucceeds(ad(as(OWNER), 'mk4').update({imageUrls: adImgs(7), updatedAt: new Date()})));
  await check('bozor rasm: egasi tahrirda 8 ta rasm — rad',
      () => assertFails(ad(as(OWNER), 'mk4').update({imageUrls: adImgs(8), updatedAt: new Date()})));
  await check('bozor rasm: egasi barcha rasmni o\'chira olmaydi (0 ta) — rad',
      () => assertFails(ad(as(OWNER), 'mk4').update({imageUrls: [], updatedAt: new Date()})));

  // ── admin_credentials / admin_audit (faqat Admin SDK) ───────────────
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('admin_credentials').doc(ADMIN).set({pin: {hash: 'x'}});
    await ctx.firestore().collection('admin_audit').doc('a1').set({kind: 'x'});
  });
  await check('admin_credentials: superadmin ham PIN xeshini o\'qiy olmaydi',
      () => assertFails(as(SUPER).collection('admin_credentials').doc(ADMIN).get()));
  await check('admin_credentials: admin o\'z PIN\'ini klientdan yoza olmaydi',
      () => assertFails(as(ADMIN).collection('admin_credentials').doc(ADMIN).set({pin: {}})));
  await check('admin_audit: klient o\'qiy/yoza olmaydi',
      () => assertFails(as(SUPER).collection('admin_audit').doc('a1').get()));

  // ── marshrut_state ──────────────────────────────────────────────────
  const ms = (db) => db.collection('users').doc(OWNER).collection('marshrut_state').doc('active');
  await check('marshrut_state: admin yo\'lovchi holatini tozalaydi (Dispatch history)',
      () => assertSucceeds(ms(as(ADMIN)).set({status: 'cleared', updatedAt: new Date()}, {merge: true})));
  await check('marshrut_state: begona tozalay olmaydi',
      () => assertFails(ms(as(STRANGER)).set({status: 'cleared', updatedAt: new Date()}, {merge: true})));

  // ── support_chats: awaitingAdmin faqat CF (O-5) ─────────────────────
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('support_chats').doc(OWNER).set({
      userPhone: OWNER, lastFromAdmin: true, awaitingAdmin: false,
    });
  });
  const chat = (db, id = OWNER) => db.collection('support_chats').doc(id);
  await check('support_chats: ilova xabar yuborishi (sendMessage merge) — o\'tadi',
      () => assertSucceeds(chat(as(OWNER)).set({
        userPhone: OWNER, updatedAt: new Date(), lastMessage: 'salom', lastFromAdmin: false,
      }, {merge: true})));
  await check('support_chats: ilova markUserRead (lastFromAdmin:false) — o\'tadi',
      () => assertSucceeds(chat(as(OWNER)).set({lastFromAdmin: false}, {merge: true})));
  await check('support_chats: egasi awaitingAdmin ni yoza olmaydi',
      () => assertFails(chat(as(OWNER)).set({awaitingAdmin: true}, {merge: true})));
  await check('support_chats: admin klienti ham awaitingAdmin ni yoza olmaydi',
      () => assertFails(chat(as(ADMIN)).update({awaitingAdmin: true})));
  await check('support_chats: yangi chat awaitingAdmin bilan yaratilmaydi',
      () => assertFails(chat(as(STRANGER), STRANGER).set({userPhone: STRANGER, awaitingAdmin: false})));
  await check('support_chats: admin badge so\'rovi (awaitingAdmin == true) — o\'tadi',
      () => assertSucceeds(as(ADMIN).collection('support_chats').where('awaitingAdmin', '==', true).get()));

  // ── tv_clips (AVTO rejim: tvAutoApprove=true) ───────────────────────
  await seed(true);
  await check('tv_clips: AVTO rejimda egasi `active` yaratadi (ilova aynan shunday yozadi)',
      () => assertSucceeds(as(OWNER).collection('tv_clips').add(clip({status: 'active'}))));
  await check('tv_clips: AVTO rejimda ham begona ownerPhone — rad',
      () => assertFails(as(STRANGER).collection('tv_clips').add(clip({status: 'active'}))));

  // «Овқат» модули олиб ташланди (2026-10-11): каталог ва омборга ҳеч ким
  // (админ ҳам) ёзолмайди; ўқиш тозалангунча қолади (эски APK йиқилмасин).
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('food_catalog').doc('food_1').set({name: 'Osh', price: 1});
    await ctx.firestore().collection('food_inventory').doc('food_1').set({totalStock: 0});
  });
  for (const col of ['food_catalog', 'food_inventory']) {
    await check(`${col}: admin ham yoza olmaydi (create/update/delete)`, async () => {
      await assertFails(as(ADMIN).collection(col).doc('food_2').set({price: 1}));
      await assertFails(as(ADMIN).collection(col).doc('food_1').update({price: 2}));
      await assertFails(as(ADMIN).collection(col).doc('food_1').delete());
    });
    await check(`${col}: o'qish qoldi`, () => assertSucceeds(unauth().collection(col).doc('food_1').get()));
  }

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} admin-audit rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(' | '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
