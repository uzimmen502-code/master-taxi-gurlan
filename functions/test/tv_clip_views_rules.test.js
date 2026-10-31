/**
 * tv_clips/{clipId}/views/{viewerId} Firestore rules —
 * `TvClipsRepository.recordView` (lib/features/tv_market/repositories/
 * tv_clips_repository.dart) TRANZAKSIYASI klip egasi bo'lmagan
 * tomoshabin uchun o'tishini tasdiqlaydi.
 *
 * Nega kerak (Crashlytics bf50ddae…, 2026-11-01): tranzaksiya avval
 * `tx.get(viewRef)` qiladi, `views` esa `allow read: if isAdmin()` edi —
 * oddiy foydalanuvchida har bir ko'rish PERMISSION_DENIED, ushlanmagan
 * async xato esa Crashlytics'da «fatal» bo'lib tushardi. Endi tomoshabin
 * faqat O'Z hujjatini `get` qila oladi; `list` — faqat admin.
 *
 * To'liq izolyatsiyalangan Firestore Emulator ustida ishlaydi, real
 * ma'lumotga tegmaydi. RULES_PATH bilan boshqa rules faylini (masalan
 * jonli manba) tekshirish mumkin.
 *
 * Ishlatish: npm run test:tv-views-rules
 */
'use strict';
const path = require('path');
const fs = require('fs');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_PATH ||
  path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const OWNER_PHONE = '998901112233';
const VIEWER_PHONE = '998907778899';
const OTHER_PHONE = '998905556677';
const CLIP_ID = 'clip1';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-tv-clip-views',
    firestore: {
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
      host: HOST,
      port: Number(PORT),
    },
  });
  console.log(`rules: ${RULES_PATH}`);

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

  async function seed({viewedAt} = {}) {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('tv_clips').doc(CLIP_ID).set({
        ownerPhone: OWNER_PHONE,
        status: 'active',
        category: 'product',
        viewCount: 5,
        likeCount: 0,
      });
      await db.collection('tv_clips').doc(CLIP_ID)
          .collection('views').doc(OTHER_PHONE)
          .set({viewedAt: new Date(Date.now() - 3 * 86400000)});
      if (viewedAt) {
        await db.collection('tv_clips').doc(CLIP_ID)
            .collection('views').doc(VIEWER_PHONE).set({viewedAt});
      }
    });
  }

  function dbFor(phone) {
    return testEnv.authenticatedContext('uid_' + phone, {
      phone_number: '+' + phone,
    }).firestore();
  }

  // `recordView` bilan bir xil shakl: get → set/update view → viewCount +1.
  // Rules qiymatni increment QO'LLANGANDAN KEYIN ko'radi, shuning uchun
  // viewCount literal 6 sifatida yoziladi.
  function recordViewTx(db, viewerId) {
    const clipRef = db.collection('tv_clips').doc(CLIP_ID);
    const viewRef = clipRef.collection('views').doc(viewerId);
    return db.runTransaction(async (tx) => {
      const snap = await tx.get(viewRef);
      if (snap.exists) {
        tx.update(viewRef, {viewedAt: new Date()});
      } else {
        tx.set(viewRef, {viewedAt: new Date()});
      }
      tx.update(clipRef, {viewCount: 6});
      return true;
    });
  }

  const viewer = dbFor(VIEWER_PHONE);

  await seed();
  await check(
      'tomoshabin birinchi ko\'rishni yozadi (recordView tranzaksiyasi, hujjat yo\'q)',
      () => assertSucceeds(recordViewTx(viewer, VIEWER_PHONE)));

  await seed({viewedAt: new Date(Date.now() - 2 * 86400000)});
  await check(
      'tomoshabin 24 soatdan keyin qayta ko\'rishni yozadi (hujjat bor)',
      () => assertSucceeds(recordViewTx(viewer, VIEWER_PHONE)));

  await seed();
  await check(
      '9 xonali viewerId hujjati ham o\'ziniki sifatida o\'qiladi',
      () => assertSucceeds(viewer.collection('tv_clips').doc(CLIP_ID)
          .collection('views').doc(VIEWER_PHONE.substring(3)).get()));

  // Negativ — maxfiylik o'zgarmadi.
  await seed();
  await check(
      'begona tomoshabin hujjatini o\'qib bo\'lmaydi',
      () => assertFails(viewer.collection('tv_clips').doc(CLIP_ID)
          .collection('views').doc(OTHER_PHONE).get()));

  await seed();
  await check(
      'views ro\'yxati (list) admin bo\'lmaganga yopiq',
      () => assertFails(viewer.collection('tv_clips').doc(CLIP_ID)
          .collection('views').get()));

  await seed();
  await check(
      'begona nomidan ko\'rish yozib bo\'lmaydi',
      () => assertFails(recordViewTx(viewer, OTHER_PHONE)));

  await seed();
  await check(
      'autentifikatsiyasiz o\'qib bo\'lmaydi',
      () => assertFails(testEnv.unauthenticatedContext().firestore()
          .collection('tv_clips').doc(CLIP_ID)
          .collection('views').doc(VIEWER_PHONE).get()));

  // Regressiya qorovuli.
  await seed();
  await check(
      'regressiya: view hujjatiga ortiqcha maydon yozilmaydi',
      () => assertFails(viewer.collection('tv_clips').doc(CLIP_ID)
          .collection('views').doc(VIEWER_PHONE)
          .set({viewedAt: new Date(), extra: 1})));

  await seed();
  await check(
      'regressiya: viewCount +2 yozilmaydi',
      () => assertFails(viewer.collection('tv_clips').doc(CLIP_ID)
          .update({viewCount: 7})));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} tv_clips views rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
