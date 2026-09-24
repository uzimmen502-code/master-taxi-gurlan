/**
 * AVAGram klip uchun ULASHISH SAHIFASI (deep link landing) — `/clip/{id}`.
 *
 * Nega server tomonda HTML? Telegram / Facebook / Instagram havolani
 * ochganda preview kartochkasini `<meta property="og:*">` teglaridan
 * o'qiydi va JS ishlatmaydi. Shuning uchun Flutter web SPA (hosting'dagi
 * `**` → /index.html) bu ish uchun yaramaydi — sahifa server tomonda
 * tayyor HTML bo'lib qaytishi kerak.
 *
 * Bu modul FAQAT matn quradi (toza funksiya) — Firestore/HTTP bilan
 * ishlamaydi, shuning uchun emulatorsiz unit-test qilinadi.
 */
'use strict';

/** Firestore hujjat id'si uchun xavfsiz shakl (path'dan keladi). */
function isSafeClipId(id) {
  return typeof id === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(id);
}

/**
 * HTML matn/atribut uchun ekranlash. Klip sarlavhasi va tavsifi
 * FOYDALANUVCHI matni — ekranlanmasa sahifaga skript kiritish mumkin.
 */
function escapeHtml(value) {
  return String(value == null ? '' : value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** Faqat http(s) havolaga ruxsat — `javascript:` kabi sxemalar kesiladi. */
function safeUrl(value) {
  const s = String(value == null ? '' : value).trim();
  if (!/^https?:\/\//i.test(s)) return '';
  return escapeHtml(s);
}

function formatMoneyUz(value) {
  const n = Number(value) || 0;
  if (n <= 0) return '';
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + ' сўм';
}

/** Klip hujjatidan eng mos progressiv MP4 (HLS emas — brauzer uchun). */
function pickMp4Url(clip) {
  const v = (clip && clip.videoVariants) || {};
  return v['720p'] || v['480p'] || v['360p'] || (clip && clip.videoUrl) || '';
}

const BRAND_CTA = 'AVA — сизга олиб келувчи';

function pageShell({title, description, head, body}) {
  return `<!DOCTYPE html>
<html lang="uz">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title>
<meta name="description" content="${description}">
${head}
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body {
    margin: 0; background: #0d0d0d; color: #fff;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    display: flex; justify-content: center;
  }
  .wrap { width: 100%; max-width: 480px; padding: 16px; }
  .media {
    width: 100%; aspect-ratio: 9/16; background: #000;
    border-radius: 16px; overflow: hidden; display: block;
  }
  .media video, .media img { width: 100%; height: 100%; object-fit: cover; display: block; }
  h1 { font-size: 19px; line-height: 1.3; margin: 16px 0 6px; }
  .desc { color: #bdbdbd; font-size: 14px; line-height: 1.45; margin: 0 0 10px; white-space: pre-wrap; }
  .meta { display: flex; flex-wrap: wrap; gap: 10px; align-items: center; margin-bottom: 18px; }
  .price { color: #00e676; font-weight: 800; font-size: 17px; }
  .chip { color: #9e9e9e; font-size: 13px; }
  .cta {
    display: block; text-align: center; text-decoration: none;
    background: #00e676; color: #06210f; font-weight: 800; font-size: 16px;
    padding: 15px 18px; border-radius: 14px; margin-bottom: 10px;
  }
  .tagline { text-align: center; color: #8d8d8d; font-size: 13px; margin-top: 18px; }
  .empty { text-align: center; padding: 48px 0; color: #bdbdbd; }
</style>
</head>
<body><div class="wrap">${body}
<p class="tagline">🚚 ${BRAND_CTA}</p>
</div></body>
</html>`;
}

/**
 * Klip sahifasi. `clip` — Firestore `tv_clips/{id}` ma'lumoti.
 * `pageUrl` — kanonik havola (og:url), `appUrl` — ilovani yuklab olish.
 */
function buildClipPageHtml({clip, pageUrl, appUrl}) {
  const rawTitle = String((clip && clip.title) || '').trim();
  const rawDesc = String((clip && clip.description) || '').trim();
  const title = escapeHtml(rawTitle || 'AVA видео');
  // og:description bitta qatorda bo'lishi kerak.
  const descSource = rawDesc || rawTitle || BRAND_CTA;
  const ogDesc = escapeHtml(descSource.replace(/\s+/g, ' ').slice(0, 200));
  const poster = safeUrl(clip && clip.posterUrl);
  const video = safeUrl(pickMp4Url(clip));
  const url = safeUrl(pageUrl);
  const app = safeUrl(appUrl);
  const price = formatMoneyUz(clip && clip.price);
  const district = escapeHtml(String((clip && clip.districtLabel) || '').trim());

  const head = [
    '<meta property="og:site_name" content="AVA">',
    '<meta property="og:type" content="video.other">',
    `<meta property="og:title" content="${title}">`,
    `<meta property="og:description" content="${ogDesc}">`,
    url ? `<meta property="og:url" content="${url}">` : '',
    poster ? `<meta property="og:image" content="${poster}">` : '',
    video ? `<meta property="og:video" content="${video}">` : '',
    video ? `<meta property="og:video:secure_url" content="${video}">` : '',
    video ? '<meta property="og:video:type" content="video/mp4">' : '',
    poster
      ? '<meta name="twitter:card" content="summary_large_image">'
      : '<meta name="twitter:card" content="summary">',
    `<meta name="twitter:title" content="${title}">`,
    `<meta name="twitter:description" content="${ogDesc}">`,
    poster ? `<meta name="twitter:image" content="${poster}">` : '',
    url ? `<link rel="canonical" href="${url}">` : '',
  ].filter(Boolean).join('\n');

  const media = video
    ? `<video class="media" controls playsinline preload="metadata"` +
      `${poster ? ` poster="${poster}"` : ''} src="${video}"></video>`
    : (poster
      ? `<div class="media"><img src="${poster}" alt="${title}"></div>`
      : '');

  const body = [
    media,
    `<h1>${title}</h1>`,
    rawDesc ? `<p class="desc">${escapeHtml(rawDesc)}</p>` : '',
    (price || district)
      ? `<div class="meta">${price ? `<span class="price">${price}</span>` : ''}` +
        `${district ? `<span class="chip">📍 ${district}</span>` : ''}</div>`
      : '',
    app ? `<a class="cta" href="${app}">📲 AVA иловасини юклаб олиш</a>` : '',
  ].filter(Boolean).join('\n');

  return pageShell({title, description: ogDesc, head, body});
}

/** Klip topilmadi / faol emas — havola o'lik bo'lmasin, ilovaga yo'naltiramiz. */
function buildClipNotFoundHtml({appUrl}) {
  const app = safeUrl(appUrl);
  const title = 'Видео топилмади';
  const desc = 'Бу видео ўчирилган ёки мавжуд эмас.';
  const head = [
    '<meta property="og:site_name" content="AVA">',
    '<meta property="og:type" content="website">',
    `<meta property="og:title" content="${title}">`,
    `<meta property="og:description" content="${desc}">`,
    '<meta name="robots" content="noindex">',
  ].join('\n');
  const body = `<div class="empty"><h1>${title}</h1><p class="desc">${desc}</p></div>` +
    (app ? `<a class="cta" href="${app}">📲 AVA иловасини юклаб олиш</a>` : '');
  return pageShell({title, description: desc, head, body});
}

module.exports = {
  isSafeClipId,
  escapeHtml,
  safeUrl,
  pickMp4Url,
  formatMoneyUz,
  buildClipPageHtml,
  buildClipNotFoundHtml,
};
