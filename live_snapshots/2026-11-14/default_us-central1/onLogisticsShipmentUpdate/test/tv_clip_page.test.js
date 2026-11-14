/**
 * `/clip/{id}` ulashish sahifasi HTML quruvchisi — toza funksiya, emulator
 * kerak emas. Ishga tushirish: npm run test:clip-page
 *
 * Asosiy e'tibor: klip sarlavhasi/tavsifi FOYDALANUVCHI matni — u ommaviy
 * sahifaga chiqadi, shuning uchun ekranlash (XSS) va havola sxemasi
 * tekshiruvi qat'iy sinaladi.
 */
'use strict';
const assert = require('assert');
const p = require('../tv_clip_page');

const results = [];
function check(name, fn) {
  try {
    fn();
    results.push({name, pass: true});
    console.log(`PASS - ${name}`);
  } catch (e) {
    results.push({name, pass: false});
    console.log(`FAIL - ${name} :: ${e.message}`);
  }
}

const APP = 'https://master-taxi-gurlan.web.app/downloads/';
const PLAY = 'https://play.google.com/store/apps/details?id=uz.ava.gurlan';
const URL = 'https://master-taxi-gurlan.web.app/clip/abc123';

function clip(over = {}) {
  return {
    title: 'Sotiladi Nexia 3',
    description: 'Holati zo\'r',
    price: 95000000,
    districtLabel: 'Gurlan',
    posterUrl: 'https://cdn.example.com/p.jpg',
    videoVariants: {
      '360p': 'https://cdn.example.com/v360.mp4',
      '720p': 'https://cdn.example.com/v720.mp4',
    },
    videoUrl: 'https://cdn.example.com/orig.mp4',
    status: 'active',
    processingStatus: 'ready',
    ...over,
  };
}

// ─── id validatsiyasi ───────────────────────────────────────────────
check('isSafeClipId accepts normal firestore ids', () => {
  assert.strictEqual(p.isSafeClipId('aB3_x-9'), true);
});
check('isSafeClipId rejects path traversal / injection', () => {
  assert.strictEqual(p.isSafeClipId('../../etc'), false);
  assert.strictEqual(p.isSafeClipId('a b'), false);
  assert.strictEqual(p.isSafeClipId(''), false);
  assert.strictEqual(p.isSafeClipId('a'.repeat(129)), false);
});

// ─── XSS / ekranlash ────────────────────────────────────────────────
check('script tag in title is escaped (not executable)', () => {
  const html = p.buildClipPageHtml({
    clip: clip({title: '<script>alert(1)</script>'}), pageUrl: URL, appUrl: APP,
  });
  assert.ok(!html.includes('<script>alert(1)</script>'), 'raw script leaked');
  assert.ok(html.includes('&lt;script&gt;'), 'not escaped');
});
check('quote in title cannot break out of og:title attribute', () => {
  const html = p.buildClipPageHtml({
    clip: clip({title: '" onmouseover="alert(1)'}), pageUrl: URL, appUrl: APP,
  });
  assert.ok(!html.includes('" onmouseover="alert(1)'), 'attribute escape broken');
  assert.ok(html.includes('&quot;'), 'quote not escaped');
});
check('description newlines do not break og:description', () => {
  const html = p.buildClipPageHtml({
    clip: clip({description: 'bir\nikki\nuch'}), pageUrl: URL, appUrl: APP,
  });
  const m = html.match(/<meta property="og:description" content="([^"]*)"/);
  assert.ok(m, 'og:description yo\'q');
  assert.ok(!m[1].includes('\n'), 'og:description ichida yangi qator bor');
});

// ─── havola sxemasi ─────────────────────────────────────────────────
check('javascript: poster url is dropped', () => {
  // eslint-disable-next-line no-script-url
  const html = p.buildClipPageHtml({
    clip: clip({posterUrl: 'javascript:alert(1)', videoVariants: {}, videoUrl: ''}),
    pageUrl: URL, appUrl: APP,
  });
  assert.ok(!html.includes('javascript:'), 'javascript: sxemasi o\'tib ketdi');
});

// ─── OG teglari (Telegram/FB preview uchun) ─────────────────────────
check('og tags present with poster and mp4', () => {
  const html = p.buildClipPageHtml({clip: clip(), pageUrl: URL, appUrl: APP});
  assert.ok(html.includes('<meta property="og:title" content="Sotiladi Nexia 3">'));
  assert.ok(html.includes(`<meta property="og:url" content="${URL}">`));
  assert.ok(html.includes('og:image" content="https://cdn.example.com/p.jpg"'));
  assert.ok(html.includes('og:video" content="https://cdn.example.com/v720.mp4"'));
  assert.ok(html.includes('twitter:card" content="summary_large_image"'));
});
check('mp4 preference: 720p > 480p > 360p > original', () => {
  assert.strictEqual(
      p.pickMp4Url({videoVariants: {'360p': 'a', '720p': 'b'}}), 'b');
  assert.strictEqual(
      p.pickMp4Url({videoVariants: {}, videoUrl: 'orig'}), 'orig');
});
check('price is formatted, zero price hidden', () => {
  assert.strictEqual(p.formatMoneyUz(95000000), '95 000 000 сўм');
  assert.strictEqual(p.formatMoneyUz(0), '');
});
check('CTA and brand tagline present', () => {
  const html = p.buildClipPageHtml({clip: clip(), pageUrl: URL, appUrl: APP});
  assert.ok(html.includes(APP), 'yuklab olish havolasi yo\'q');
  assert.ok(html.includes('олиб келувчи'), 'CTA taglayn yo\'q');
});
check('Play is primary CTA, APK page is secondary', () => {
  const html = p.buildClipPageHtml({
    clip: clip(), pageUrl: URL, appUrl: PLAY, altUrl: APP,
  });
  assert.ok(html.includes(`class="cta" href="${PLAY}"`), 'Play asosiy tugma emas');
  assert.ok(html.includes(`class="alt" href="${APP}"`), 'APK zaxira havolasi yo\'q');
});
check('altUrl omitted — only the primary CTA renders', () => {
  const html = p.buildClipPageHtml({clip: clip(), pageUrl: URL, appUrl: PLAY});
  assert.ok(html.includes('class="cta"'));
  assert.ok(!html.includes('class="alt"'), 'alt bo\'lmasligi kerak');
});

// ─── fallback ───────────────────────────────────────────────────────
check('not-found page is noindex and still offers the app', () => {
  const html = p.buildClipNotFoundHtml({appUrl: APP});
  assert.ok(html.includes('noindex'));
  assert.ok(html.includes(APP));
});
check('clip without poster/video still renders', () => {
  const html = p.buildClipPageHtml({
    clip: clip({posterUrl: '', videoVariants: {}, videoUrl: ''}),
    pageUrl: URL, appUrl: APP,
  });
  assert.ok(html.includes('og:title'));
  assert.ok(html.includes('twitter:card" content="summary"'));
});

const failed = results.filter((r) => !r.pass);
console.log(`\n${results.length - failed.length}/${results.length} clip page checks passed.`);
if (failed.length) {
  console.log('FAILED:', failed.map((f) => f.name).join(', '));
  process.exit(1);
}
