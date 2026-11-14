/**
 * tv_clips.playbackStats Firestore rules — `TvPlaybackAnalyticsRecorder`
 * (lib/features/tv_market/services/tv_playback_analytics_recorder.dart →
 * `TvClipsRepository.recordPlaybackStats`) yozadigan aniq maydon shaklini
 * klip EGASI BO'LMAGAN tomoshabin ham yozolishini tasdiqlaydi, va ayni
 * paytda shu teshikdan boshqa maydonga o'tib bo'lmasligini.
 *
 * Nega kerak: `tvClipPlaybackStatsOnly()` qo'shilgunga qadar bu yozuv
 * PERMISSION_DENIED bo'lardi (qurilma logida ko'rindi), va
 * `recordPlaybackStats()`dagi best-effort `catch (_)` xatoni jimgina
 * yutib yuborardi — ya'ni playback metrikasi faqat o'z klipini ko'rgan
 * egalardan yig'ilgan, umumiy auditoriyadan emas.
 *
 * To'liq izolyatsiyalangan Firestore Emulator ustida ishlaydi, real
 * ma'lumotga tegmaydi.
 *
 * Ishlatish: npm run test:tv-playback-stats
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

const OWNER_PHONE = '998901112233';
const VIEWER_PHONE = '998907778899';
const CLIP_ID = 'clip1';

// Seed — allaqachon bir marta ko'rilgan klip.
const SEEDED_STATS = {
  views: 2,
  watchedMs: 30000,
  bufferMs: 500,
  bufferEvents: 1,
  firstFrameMsSum: 240,
  firstFrameSamples: 2,
  completedViews: 1,
  skippedViews: 1,
  errors: 0,
};

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-tv-playback-stats',
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

  async function seedClip() {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('tv_clips').doc(CLIP_ID).set({
        ownerPhone: OWNER_PHONE,
        status: 'active',
        category: 'product',
        viewCount: 5,
        likeCount: 1,
        playbackStats: {...SEEDED_STATS},
      });
    });
  }

  await testEnv.clearFirestore();
  await seedClip();

  const viewer = testEnv.authenticatedContext('viewerUid', {
    phone_number: '+' + VIEWER_PHONE,
  });
  const viewerDb = viewer.firestore();
  const clip = () => viewerDb.collection('tv_clips').doc(CLIP_ID);

  // Rules qiymatlarni increment QO'LLANGANDAN KEYIN ko'radi, shuning uchun
  // testda increment natijasi to'g'ridan-to'g'ri literal sifatida yoziladi.
  await check(
      'egasi bo\'lmagan tomoshabin playbackStats increment yozadi (recordPlaybackStats shakli)',
      () => assertSucceeds(clip().update({
        'playbackStats.views': SEEDED_STATS.views + 1,
        'playbackStats.watchedMs': SEEDED_STATS.watchedMs + 24000,
        'playbackStats.bufferMs': SEEDED_STATS.bufferMs + 0,
        'playbackStats.bufferEvents': SEEDED_STATS.bufferEvents + 0,
        'playbackStats.firstFrameMsSum': SEEDED_STATS.firstFrameMsSum + 110,
        'playbackStats.firstFrameSamples': SEEDED_STATS.firstFrameSamples + 1,
        'playbackStats.completedViews': SEEDED_STATS.completedViews + 1,
        'playbackStats.updatedAt': new Date(),
      })));

  await seedClip();
  await check(
      'skip bo\'lgan ko\'rish (skippedViews + errors) ham yoziladi',
      () => assertSucceeds(clip().update({
        'playbackStats.views': SEEDED_STATS.views + 1,
        'playbackStats.watchedMs': SEEDED_STATS.watchedMs + 900,
        'playbackStats.bufferMs': SEEDED_STATS.bufferMs + 300,
        'playbackStats.bufferEvents': SEEDED_STATS.bufferEvents + 1,
        'playbackStats.skippedViews': SEEDED_STATS.skippedViews + 1,
        'playbackStats.errors': SEEDED_STATS.errors + 1,
        'playbackStats.updatedAt': new Date(),
      })));

  await seedClip();
  await check(
      'playbackStats bilan birga boshqa maydon (status) yozilmaydi',
      () => assertFails(clip().update({
        'playbackStats.views': SEEDED_STATS.views + 1,
        status: 'blocked',
      })));

  await seedClip();
  await check(
      'moderatsiya maydonlari shu yo\'l bilan o\'zgartirilmaydi (rejectReason)',
      () => assertFails(clip().update({
        'playbackStats.views': SEEDED_STATS.views + 1,
        rejectReason: 'hacked',
      })));

  await seedClip();
  await check(
      'statistikani KAMAYTIRISH mumkin emas (views pastga)',
      () => assertFails(clip().update({
        'playbackStats.views': SEEDED_STATS.views - 1,
      })));

  await seedClip();
  await check(
      'bufferMs ni nolga tushirib ko\'rsatkichni chiroyilashtirish mumkin emas',
      () => assertFails(clip().update({
        'playbackStats.bufferMs': 0,
      })));

  await seedClip();
  await check(
      'playbackStats ichiga notanish kalit yozilmaydi',
      () => assertFails(clip().update({
        'playbackStats.injected': 1,
      })));

  await seedClip();
  await check(
      'son bo\'lmagan qiymat yozilmaydi (views: string)',
      () => assertFails(clip().update({
        'playbackStats.views': 'many',
      })));

  await seedClip();
  await check(
      'autentifikatsiyasiz playbackStats yozilmaydi',
      () => assertFails(testEnv.unauthenticatedContext().firestore()
          .collection('tv_clips').doc(CLIP_ID).update({
            'playbackStats.views': SEEDED_STATS.views + 1,
          })));

  // Regressiya qorovuli — mavjud yo'llar buzilmaganini tasdiqlaydi.
  await seedClip();
  await check(
      'regressiya: egasi bo\'lmagan tomoshabin viewCount +1 hamon yozadi',
      () => assertSucceeds(clip().update({viewCount: 6})));

  await seedClip();
  await check(
      'regressiya: egasi bo\'lmagan tomoshabin status\'ni hamon o\'zgartira olmaydi',
      () => assertFails(clip().update({status: 'blocked'})));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} tv_clips.playbackStats rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
