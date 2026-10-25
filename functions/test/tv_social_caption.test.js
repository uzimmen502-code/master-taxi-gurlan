/**
 * Ijtimoiy tarmoq podpisi va yuboriladigan fayl — toza funksiyalar,
 * emulator kerak emas. Ishga tushirish: npm run test:tv-social
 *
 * Asosiy e'tibor:
 *   1. Telegram'ning 1024 belgi chegarasida Play HAVOLASI kesilib
 *      qolmasligi (avval butun matn oxiridan kesilardi).
 *   2. Instagram podpisiga havola QO'SHILMASLIGI — u yerda caption
 *      ichidagi URL bosilmaydi, `captionPrefix` "profildagi havola" deydi.
 *   3. Tarmoqqa xom fayl emas, transcode qilingan 720p ketishi.
 */
'use strict';
const assert = require('assert');
const { buildCaption, socialVideoUrl, requestedNetworks, consentRecord } = require('../tv_social_publish');

const results = [];
function check(name, fn) {
  try {
    fn();
    results.push({ name, pass: true });
    console.log(`PASS - ${name}`);
  } catch (e) {
    results.push({ name, pass: false });
    console.log(`FAIL - ${name} :: ${e.message}`);
  }
}

const PLAY = 'https://play.google.com/store/apps/details?id=uz.ava.gurlan';
const PREFIX = '📲 AVA — video, e\'lon, xizmat. Profildagi havoladan yuklab oling.';

function clip(over = {}) {
  return Object.assign({
    title: 'Sotiladi Nexia 3',
    description: 'Holati zo\'r, bo\'yoqsiz',
    districtLabel: 'Gurlan',
    ownerName: 'Aziz',
    videoUrl: 'https://cdn.example.com/orig.mp4',
    videoVariants: {
      '720p': 'https://cdn.example.com/v720.mp4',
      '480p': 'https://cdn.example.com/v480.mp4',
      '360p': 'https://cdn.example.com/v360.mp4',
    },
  }, over);
}

check('telegram — havola bor va 1000 belgidan oshmaydi', () => {
  const c = buildCaption(clip(), PREFIX, 'telegram', PLAY);
  assert.ok(c.includes(PLAY), 'Play havolasi yo\'q');
  assert.ok(c.length <= 1000, `uzun: ${c.length}`);
});

check('telegram — juda uzun tavsifda ham havola SAQLANADI', () => {
  const c = buildCaption(
    clip({ description: 'x'.repeat(5000) }), PREFIX, 'telegram', PLAY);
  assert.ok(c.length <= 1000, `uzun: ${c.length}`);
  assert.ok(c.includes(PLAY), 'uzun tavsifda havola kesilib ketdi');
  assert.ok(c.includes(PREFIX), 'uzun tavsifda CTA kesilib ketdi');
});

check('instagram — havola QO\'SHILMAYDI, o\'rniga profil ko\'rsatkichi', () => {
  const c = buildCaption(clip(), PREFIX, 'instagram', PLAY);
  assert.ok(!c.includes(PLAY), 'IG podpisiga havola qo\'shilib qolgan');
  assert.ok(c.includes(PREFIX), 'CTA yo\'q');
  assert.ok(c.includes('профилда'), 'profil ko\'rsatkichi yo\'q');
});

check('linkable tarmoqlarda profil ko\'rsatkichi TAKRORLANMAYDI', () => {
  for (const net of ['facebook', 'youtube', 'telegram']) {
    const c = buildCaption(clip(), PREFIX, net, PLAY);
    assert.ok(!c.includes('профилда'), `${net}: ortiqcha ko'rsatkich`);
  }
});

check('facebook / youtube — havola bor', () => {
  for (const net of ['facebook', 'youtube']) {
    const c = buildCaption(clip(), PREFIX, net, PLAY);
    assert.ok(c.includes(PLAY), `${net}: havola yo'q`);
  }
});

check('podpis tartibi — CTA birinchi, #AVA oxirgi', () => {
  const c = buildCaption(clip(), PREFIX, 'facebook', PLAY);
  const lines = c.split('\n');
  assert.strictEqual(lines[0], PREFIX);
  assert.strictEqual(lines[lines.length - 1], '#AVA');
});

check('pullik reklama — birinchi qator «Реклама» (barcha tarmoq, uzun tavsifda ham)', () => {
  for (const net of ['instagram', 'facebook', 'youtube', 'telegram']) {
    const c = buildCaption(clip({ category: 'ad', description: 'x'.repeat(5000) }), PREFIX, net, PLAY);
    const lines = c.split('\n');
    assert.strictEqual(lines[0], 'Реклама', `${net}: belgi yo'q`);
    assert.strictEqual(lines[1], PREFIX);
    assert.strictEqual(lines[lines.length - 1], '#AVA');
  }
});

check('oddiy klipda «Реклама» belgisi YO\'Q', () => {
  for (const cat of [undefined, 'product', 'service', 'news']) {
    const c = buildCaption(clip({ category: cat }), PREFIX, 'telegram', PLAY);
    assert.ok(!c.split('\n').includes('Реклама'), `${cat}: ortiqcha belgi`);
  }
});

check('playUrl berilmasa — havola qatori umuman bo\'lmaydi', () => {
  const c = buildCaption(clip(), PREFIX, 'telegram', '');
  assert.ok(!c.includes('play.google.com'));
  assert.ok(c.includes('#AVA'));
});

check('socialVideoUrl — 720p afzal, xom fayl emas', () => {
  assert.strictEqual(socialVideoUrl(clip()), 'https://cdn.example.com/v720.mp4');
});

check('socialVideoUrl — suv belgili `share` nusxasi hammasidan ustun', () => {
  const c = clip();
  c.videoVariants.share = 'https://cdn.example.com/share.mp4';
  assert.strictEqual(socialVideoUrl(c), 'https://cdn.example.com/share.mp4');
});

check('socialVideoUrl — eski klipda `share` yo\'q -> 720p', () => {
  const c = clip();
  delete c.videoVariants.share;
  assert.strictEqual(socialVideoUrl(c), 'https://cdn.example.com/v720.mp4');
});

check('socialVideoUrl — 720p yo\'q bo\'lsa 480p, keyin 360p', () => {
  assert.strictEqual(
    socialVideoUrl(clip({ videoVariants: { '480p': 'b', '360p': 'c' } })), 'b');
  assert.strictEqual(
    socialVideoUrl(clip({ videoVariants: { '360p': 'c' } })), 'c');
});

check('socialVideoUrl — variantlar hali tayyor emas -> xom faylga qaytadi', () => {
  assert.strictEqual(
    socialVideoUrl(clip({ videoVariants: {} })),
    'https://cdn.example.com/orig.mp4');
  assert.strictEqual(
    socialVideoUrl(clip({ videoVariants: undefined })),
    'https://cdn.example.com/orig.mp4');
});

// ── requestedNetworks — egasi rozilik bergan tarmoqlar (admin audit, 2026-10-08) ──
check('requestedNetworks — eski `[\'tiktok\']` klip HECH QAYERGA ketmaydi (avval 4 tarmoq)', () => {
  assert.deepStrictEqual(
    requestedNetworks({ socialNetworks: ['tiktok'], socialConsent: true }), []);
});
check('requestedNetworks — tanlangan tarmoqlar tartib bilan', () => {
  assert.deepStrictEqual(
    requestedNetworks({ socialNetworks: ['telegram', 'TikTok', 'instagram'], socialConsent: true }),
    ['instagram', 'telegram']);
});
check('requestedNetworks — `socialNetworks`siz eski klip + rozilik → 4 tarmoq (o\'zgarmagan)', () => {
  assert.deepStrictEqual(
    requestedNetworks({ socialConsent: true }),
    ['instagram', 'facebook', 'youtube', 'telegram']);
});
check('requestedNetworks — rozilik yo\'q → hech qayer', () => {
  assert.deepStrictEqual(requestedNetworks({ socialNetworks: [] }), []);
});
check('requestedNetworks — pullik reklama — majburiy 3 tarmoq', () => {
  assert.deepStrictEqual(
    requestedNetworks({ category: 'ad', socialNetworks: ['tiktok'] }),
    ['instagram', 'facebook', 'telegram']);
});

// ── 7-bosqich (2026-10-25): rozilik belgisi va uning asosi ──
check('requestedNetworks — tarmoq tanlangan, lekin socialConsent yo\'q/false → hech qayer', () => {
  assert.deepStrictEqual(requestedNetworks({ socialNetworks: ['telegram'] }), []);
  assert.deepStrictEqual(requestedNetworks({ socialNetworks: ['telegram'], socialConsent: false }), []);
});
check('requestedNetworks — eski ilova (chip + socialConsent:true, versiyasiz) — o\'zgarmagan', () => {
  assert.deepStrictEqual(
    requestedNetworks({ socialNetworks: ['youtube'], socialConsent: true }), ['youtube']);
});
const ts = { toMillis: () => 1761400000000 };
check('consentRecord — «Рухсат бераман»: explicit, versiya, vaqt', () => {
  const r = consentRecord({ socialConsent: true, socialConsentVersion: 1, socialConsentAt: ts }, ['telegram']);
  assert.deepStrictEqual(r, { basis: 'explicit', version: 1, networks: ['telegram'], consentAt: ts });
});
check('consentRecord — eski ilova: legacy, vaqt yozilmaydi', () => {
  const r = consentRecord({ socialConsent: true, socialConsentAt: ts }, ['instagram']);
  assert.deepStrictEqual(r, { basis: 'legacy', version: 0, networks: ['instagram'], consentAt: null });
});
check('consentRecord — reklama: ad_terms + ogohlantirish versiyasi (eski ilovada 0)', () => {
  assert.strictEqual(consentRecord({ category: 'ad', socialNoticeVersion: 1 }, ['facebook']).version, 1);
  const old = consentRecord({ category: 'ad' }, ['facebook']);
  assert.deepStrictEqual([old.basis, old.version], ['ad_terms', 0]);
});
check('consentRecord — noto\'g\'ri versiya (matn, 0, 500) → 0', () => {
  for (const v of ['1', 0, 500, 1.5]) {
    assert.strictEqual(consentRecord({ socialConsentVersion: v }, []).basis, 'legacy');
  }
});

const failed = results.filter((r) => !r.pass).length;
console.log(`\n${results.length - failed}/${results.length} o'tdi`);
process.exit(failed ? 1 : 0);
