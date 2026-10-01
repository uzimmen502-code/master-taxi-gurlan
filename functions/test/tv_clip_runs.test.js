/**
 * TV клип transcode run'лари — `functions/tv_clip_runs.js`.
 *
 * ЭНГ МУҲИМ ТЕКШИРУВ: версияланган йўлга ўтиш ЭСКИ КЛИПЛАРНИ
 * СИНДИРМАСЛИГИ КЕРАК. Эски клипларда ҳужжатда `variantRun` йўқ ва
 * файллар версиясиз йўлда (`tv_clip_variants/{clipId}/720p.mp4`) туради.
 * Улар шу пайтда томоша қилинаётган бўлиши мумкин — демак янги transcode
 * уларни ЎЧИРМАСЛИГИ шарт.
 *
 * Soф мантиқ: Storage ҳам, эмулятор ҳам керак эмас.
 *
 * Ишлатиш (functions/ ичидан):
 *   npm run test:tv-clip-runs
 */
'use strict';
const {tvClipRunId, staleRunFiles} = require('../tv_clip_runs');

const results = [];
function check(name, pass) {
  results.push({name, pass});
  console.log(`${pass ? '  ok  ' : ' FAIL '} ${name}`);
}

const ROOTS = ['tv_clip_variants', 'tv_clip_hls'];
const CLIP = 'clipA';

// Эски (версиясиз) клипнинг Storage'даги ҳолати.
function legacyFiles(root, clipId) {
  return [
    `${root}/${clipId}/720p.mp4`,
    `${root}/${clipId}/480p.mp4`,
    `${root}/${clipId}/360p.mp4`,
  ];
}

function runFiles(root, clipId, runId) {
  return [
    `${root}/${clipId}/${runId}/720p.mp4`,
    `${root}/${clipId}/${runId}/480p.mp4`,
    `${root}/${clipId}/${runId}/360p.mp4`,
  ];
}

// ── 1. ЭСКИ КЛИП ОМОН ҚОЛАДИ ────────────────────────────────────────
// Ҳужжатда `variantRun` йўқ → keepRun бўш → ҳеч нарса ўчирилмайди.
function testLegacyClipSurvives() {
  for (const root of ROOTS) {
    const files = legacyFiles(root, CLIP);
    const stale = staleRunFiles(files, root, CLIP, '');
    check(
        `[${root}] variantRun yo'q — eski fayllar O'CHIRILMAYDI`,
        stale.length === 0);
  }
  // Янги run юкланаётган пайтда ҳам (иккала авлод бирга турганда).
  for (const root of ROOTS) {
    const files = [...legacyFiles(root, CLIP), ...runFiles(root, CLIP, 'r1')];
    const stale = staleRunFiles(files, root, CLIP, '');
    check(
        `[${root}] birinchi versiyali transcode paytida ham hech nima o'chmaydi`,
        stale.length === 0);
  }
}

// ── 2. КЕЙИНГИ TRANSCODE ────────────────────────────────────────────
// Энди ҳужжатда `variantRun: 'r1'` бор — r1 томоша қилинмоқда, уни
// сақлаймиз; эскилари (версиясиз ва r0) кетади.
function testKeepsLiveRun() {
  for (const root of ROOTS) {
    const files = [
      ...legacyFiles(root, CLIP),
      ...runFiles(root, CLIP, 'r0'),
      ...runFiles(root, CLIP, 'r1'),
    ];
    const stale = staleRunFiles(files, root, CLIP, 'r1');
    const keptR1 = runFiles(root, CLIP, 'r1').every((f) => !stale.includes(f));
    const droppedLegacy =
        legacyFiles(root, CLIP).every((f) => stale.includes(f));
    const droppedR0 = runFiles(root, CLIP, 'r0').every((f) => stale.includes(f));

    check(`[${root}] jonli run (r1) saqlanadi`, keptR1);
    check(`[${root}] versiyasiz eski fayllar o'chadi`, droppedLegacy);
    check(`[${root}] eski run (r0) o'chadi`, droppedR0);
    check(`[${root}] faqat shular — ortiqchasi yo'q`, stale.length === 6);
  }
}

// ── 3. БОШҚА КЛИПГА ТЕГМАЙДИ ────────────────────────────────────────
function testOtherClipsUntouched() {
  const root = 'tv_clip_variants';
  const files = [
    ...runFiles(root, CLIP, 'r0'),
    `${root}/clipB/720p.mp4`,
    `${root}/clipB/r9/720p.mp4`,
    // Префикс ўхшаш, лекин бошқа клип: `clipA2` ⊃ `clipA` эмас.
    `${root}/clipA2/r0/720p.mp4`,
  ];
  const stale = staleRunFiles(files, root, CLIP, 'r1');
  const noForeign = !stale.some((f) =>
    f.includes('/clipB/') || f.includes('/clipA2/'));
  check('boshqa kliplarning fayllariga tegilmaydi', noForeign);
  check('faqat clipA ning 3 ta eski fayli', stale.length === 3);
}

// ── 4. ЧЕГАРАВИЙ ҲОЛАТЛАР ───────────────────────────────────────────
function testEdgeCases() {
  const root = 'tv_clip_variants';
  check('bo\'sh ro\'yxat — bo\'sh natija',
      staleRunFiles([], root, CLIP, 'r1').length === 0);
  check('null ro\'yxat yiqilmaydi',
      staleRunFiles(null, root, CLIP, 'r1').length === 0);
  check('keepRun null — hech nima o\'chmaydi',
      staleRunFiles(legacyFiles(root, CLIP), root, CLIP, null).length === 0);
  // keepRun ўзи рўйхатда бўлмаса ҳам (ҳали юкланмаган) эскилари кетади.
  const stale = staleRunFiles(legacyFiles(root, CLIP), root, CLIP, 'rNEW');
  check('keepRun hali yuklanmagan bo\'lsa ham eskilari o\'chadi',
      stale.length === 3);
}

// ── 5. runId ────────────────────────────────────────────────────────
function testRunId() {
  const id = tvClipRunId();
  check('runId bo\'sh emas', typeof id === 'string' && id.length > 0);
  check('runId yo\'lda xavfsiz (faqat [a-z0-9])', /^[a-z0-9]+$/.test(id));
  // Вақт бўйича ўсади — кейинги transcode олдингисидан катта бўлади.
  const later = Date.now() + 1000;
  check('runId vaqt bo\'yicha o\'sadi', later.toString(36) > id);
}

// ── 6. ҲАҚИҚИЙ СЦЕНАРИЙ: эски клип икки transcode'дан ўтади ─────────
function testTwoTranscodeNarrative() {
  const root = 'tv_clip_hls';
  // Боши: эски клип, версиясиз файллар, ҳужжатда variantRun йўқ.
  let storage = legacyFiles(root, CLIP);
  let variantRun = '';

  // 1-transcode (backfill): тозалаш ҳеч нарса ўчирмайди.
  let stale = staleRunFiles(storage, root, CLIP, variantRun);
  storage = storage.filter((f) => !stale.includes(f));
  const legacyAlive = legacyFiles(root, CLIP).every((f) => storage.includes(f));
  check('1-transcode: eski fayllar hamon joyida (tomoshabin uzilmaydi)',
      legacyAlive);
  // Янги run юкланди ва ҳужжатга ёзилди.
  storage = [...storage, ...runFiles(root, CLIP, 'rA')];
  variantRun = 'rA';

  // 2-transcode: энди rA жонли — эскилари кетади, rA қолади.
  stale = staleRunFiles(storage, root, CLIP, variantRun);
  storage = storage.filter((f) => !stale.includes(f));
  const rAAlive = runFiles(root, CLIP, 'rA').every((f) => storage.includes(f));
  const legacyGone = legacyFiles(root, CLIP).every((f) => !storage.includes(f));
  check('2-transcode: jonli run (rA) saqlandi', rAAlive);
  check('2-transcode: versiyasiz eskilari tozalandi', legacyGone);
  check('2-transcode: Storage\'da faqat rA qoldi', storage.length === 3);
}

function main() {
  testLegacyClipSurvives();
  testKeepsLiveRun();
  testOtherClipsUntouched();
  testEdgeCases();
  testRunId();
  testTwoTranscodeNarrative();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} passed`);
  process.exit(failed.length ? 1 : 0);
}

main();
