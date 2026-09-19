// Generates docs/landing/kitob.html from assets/book/ava_imkoniyatlar_kitobi.json
// Run: node docs/landing/build_kitob.js

const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '..', '..', 'assets', 'book', 'ava_imkoniyatlar_kitobi.json');
const OUT = path.join(__dirname, 'kitob.html');

const book = JSON.parse(fs.readFileSync(SRC, 'utf8'));

function esc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function renderBlocks(blocks) {
  let html = '';
  for (const b of blocks || []) {
    switch (b.t) {
      case 'divider':
        html += `<hr class="divider" />\n`;
        break;
      case 'p':
        html += `<p>${esc(b.text)}</p>\n`;
        break;
      case 'subhead':
        html += `<h4>${esc(b.text)}</h4>\n`;
        break;
      case 'label':
        html += `<div class="label">${esc(b.text)}</div>\n`;
        break;
      case 'rule':
        html += `<div class="rule">${esc(b.text)}</div>\n`;
        break;
      case 'quote':
        html += `<blockquote class="quote">${esc(b.text)}</blockquote>\n`;
        break;
      case 'bulletlist':
        html += `<ul class="bullets">${(b.items || []).map((i) => `<li>${esc(i)}</li>`).join('')}</ul>\n`;
        break;
      case 'dialoguelist':
        html += `<ul class="dialogue">${(b.items || []).map((i) => `<li>${esc(i)}</li>`).join('')}</ul>\n`;
        break;
      case 'warning':
        html += `<div class="callout warning"><div class="callout-label">${esc(b.label)}</div><p>${esc(b.text)}</p></div>\n`;
        break;
      case 'exercise':
        html += `<div class="callout exercise"><div class="callout-label">${esc(b.label)}</div><ol>${(b.items || []).map((i) => `<li>${esc(i)}</li>`).join('')}</ol></div>\n`;
        break;
      default:
        if (b.text) html += `<p>${esc(b.text)}</p>\n`;
    }
  }
  return html;
}

function slug(prefix, n) {
  return `${prefix}-${n}`;
}

// --- Table of contents ---
let toc = '<nav class="toc" aria-label="Мундарижа"><ol>\n';
book.parts.forEach((part, pi) => {
  toc += `<li><a href="#${slug('part', pi + 1)}"><span class="toc-roman">${esc(part.roman)}</span> ${esc(part.title)}</a>`;
  if (part.chapters && part.chapters.length) {
    toc += '<ol class="toc-sub">';
    for (const ch of part.chapters) {
      toc += `<li><a href="#${slug('ch', ch.num)}">${ch.num}. ${esc(ch.title)}</a></li>`;
    }
    toc += '</ol>';
  }
  toc += '</li>\n';
});
toc += '</ol></nav>\n';

// --- Body content ---
let body = '';

body += `<section class="intro">\n<h2>${esc(book.intro.title)}</h2>\n${renderBlocks(book.intro.blocks)}</section>\n`;

book.parts.forEach((part, pi) => {
  body += `<section class="part" id="${slug('part', pi + 1)}">\n`;
  body += `<div class="part-head"><div class="part-roman">${esc(part.roman)}</div><h2>${esc(part.title)}</h2>`;
  if (part.epigraph) body += `<p class="epigraph">${esc(part.epigraph)}</p>`;
  body += `</div>\n`;
  if (part.preamble && part.preamble.length) {
    body += `<div class="chapter">${renderBlocks(part.preamble)}</div>\n`;
  }
  for (const ch of part.chapters || []) {
    body += `<article class="chapter" id="${slug('ch', ch.num)}">\n`;
    body += `<h3><span class="ch-num">${ch.num}</span> ${esc(ch.title)}</h3>\n`;
    body += renderBlocks(ch.blocks);
    body += `</article>\n`;
  }
  body += `</section>\n`;
});

const html = `<!DOCTYPE html>
<html lang="uz-Cyrl">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>AVA Имкониятлар китоби</title>
  <meta name="description" content="AVA Имкониятлар китоби — касб, маҳсулот, контент ва даромад ҳақида ҳикоялар асосида амалий қўлланма." />
  <meta property="og:title" content="AVA Имкониятлар китоби" />
  <meta property="og:type" content="book" />
  <link rel="icon" href="assets/icon.png" />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&family=Manrope:wght@600;700;800&display=swap" rel="stylesheet" />
  <style>
    :root {
      --ink: #102418; --muted: #4a6741; --bg: #f3f7f2; --bg-deep: #e4efe3;
      --card: #ffffff; --line: #c9dbc6; --green: #1f7a3a; --green-deep: #145c2b;
      --accent: #facc15; --max: 1080px; --read-max: 44rem;
      --shadow: 0 18px 50px rgba(16, 36, 24, 0.08);
    }
    * { box-sizing: border-box; }
    html { scroll-behavior: smooth; }
    body { margin: 0; font-family: "IBM Plex Sans", sans-serif; color: var(--ink); background: var(--bg); line-height: 1.6; }
    a { color: inherit; }
    h1, h2, h3, h4, .brand { font-family: Manrope, sans-serif; letter-spacing: -0.02em; }
    .wrap { width: min(100% - 2rem, var(--max)); margin-inline: auto; }
    .read { width: min(100% - 2rem, var(--read-max)); margin-inline: auto; }

    .site-header {
      position: sticky; top: 0; z-index: 40; backdrop-filter: blur(12px);
      background: rgba(243, 247, 242, 0.9); border-bottom: 1px solid rgba(201, 219, 198, 0.7);
    }
    .site-header .inner { display: flex; align-items: center; justify-content: space-between; gap: 1rem; padding: 0.85rem 0; width: min(100% - 2rem, var(--max)); margin-inline: auto; }
    .brand { font-weight: 800; font-size: 1.3rem; color: var(--green-deep); text-decoration: none; }
    .brand span { display: block; font-size: 0.7rem; font-weight: 600; color: var(--muted); }
    .btn {
      display: inline-flex; align-items: center; gap: 0.4rem; border: 0; border-radius: 999px;
      padding: 0.75rem 1.2rem; font-family: Manrope, sans-serif; font-weight: 700; font-size: 0.9rem;
      text-decoration: none; background: var(--green); color: #fff; box-shadow: 0 8px 20px rgba(31,122,58,.25);
    }

    .cover {
      background: linear-gradient(150deg, #145c2b 0%, #1f7a3a 55%, #0f3d22 100%);
      color: #fff; padding: 5rem 0 4rem; text-align: center;
    }
    .cover .kicker { color: var(--accent); font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; font-size: 0.85rem; margin-bottom: 1rem; }
    .cover h1 { font-size: clamp(1.5rem, 4.4vw, 2.6rem); margin: 0 0 1.2rem; word-spacing: 0.15em; }
    .cover .tagline { color: rgba(255,255,255,0.85); font-size: 1rem; margin: 0.35rem 0; }
    .cover .year { margin-top: 1.5rem; color: rgba(255,255,255,0.6); font-size: 0.85rem; }

    .toc { background: var(--card); border: 1px solid var(--line); border-radius: 18px; padding: 1.6rem 1.8rem; margin: -2.5rem auto 3rem; box-shadow: var(--shadow); }
    .toc h2 { display: none; }
    .toc > ol { list-style: none; margin: 0; padding: 0; columns: 2; column-gap: 2rem; }
    .toc > ol > li { break-inside: avoid; margin-bottom: 1rem; }
    .toc > ol > li > a { font-weight: 700; text-decoration: none; }
    .toc-roman { color: var(--green-deep); margin-right: 0.35rem; }
    .toc-sub { list-style: none; margin: 0.4rem 0 0; padding: 0 0 0 1.1rem; }
    .toc-sub li { margin-bottom: 0.25rem; }
    .toc-sub a { color: var(--muted); text-decoration: none; font-size: 0.92rem; }
    .toc-sub a:hover, .toc > ol > li > a:hover { color: var(--green-deep); }

    section.intro, section.part { padding: 3rem 0; }
    section.intro h2 { font-size: 1.6rem; }

    .part-head { text-align: center; padding: 2.5rem 0 1rem; border-top: 3px solid var(--green-deep); margin-top: 1rem; }
    .part-roman { font-family: Manrope, sans-serif; font-weight: 800; font-size: 1rem; color: var(--green-deep); letter-spacing: 0.2em; }
    .part-head h2 { font-size: clamp(1.5rem, 3vw, 2.1rem); margin: 0.4rem 0 0.8rem; }
    .epigraph { font-style: italic; color: var(--muted); max-width: 30rem; margin: 0 auto; }

    article.chapter, .chapter { margin: 2.2rem auto; }
    article.chapter h3 { font-size: 1.35rem; margin-bottom: 1rem; }
    .ch-num { display: inline-flex; align-items: center; justify-content: center; width: 2rem; height: 2rem; border-radius: 999px; background: var(--bg-deep); color: var(--green-deep); font-size: 0.95rem; margin-right: 0.5rem; }
    h4 { font-size: 1.05rem; margin: 1.6rem 0 0.5rem; color: var(--green-deep); }
    p { margin: 0 0 1rem; }

    hr.divider { border: 0; border-top: 1px solid var(--line); margin: 2rem 0; }
    .label { font-weight: 700; font-size: 0.82rem; letter-spacing: 0.06em; color: var(--green-deep); text-transform: uppercase; margin: 1.4rem 0 0.6rem; }
    .rule {
      font-family: Manrope, sans-serif; font-weight: 700; font-size: 1.05rem; color: var(--green-deep);
      border-left: 4px solid var(--green); padding: 0.4rem 0 0.4rem 1rem; margin: 1.6rem 0;
    }
    blockquote.quote {
      font-style: italic; font-size: 1.15rem; color: var(--ink); border-left: 4px solid var(--accent);
      padding: 0.3rem 0 0.3rem 1.2rem; margin: 1.8rem 0;
    }
    ul.bullets { padding-left: 1.3rem; margin: 0 0 1rem; }
    ul.bullets li { margin-bottom: 0.4rem; }
    ul.dialogue { list-style: none; padding: 0; margin: 0 0 1.2rem; border-left: 3px solid var(--line); padding-left: 1rem; }
    ul.dialogue li { margin-bottom: 0.45rem; color: var(--muted); }

    .callout { border-radius: 14px; padding: 1.2rem 1.4rem; margin: 1.6rem 0; border: 1px solid var(--line); }
    .callout p, .callout li { margin: 0 0 0.4rem; }
    .callout-label { font-family: Manrope, sans-serif; font-weight: 700; margin-bottom: 0.5rem; }
    .callout.warning { background: #fff7e6; border-color: #f3d98b; }
    .callout.warning .callout-label { color: #8a6100; }
    .callout.exercise { background: var(--bg-deep); border-color: var(--line); }
    .callout.exercise .callout-label { color: var(--green-deep); }
    .callout.exercise ol { padding-left: 1.3rem; margin: 0; }

    .final-cta {
      background: linear-gradient(135deg, #145c2b, #1f7a3a 55%, #3d6b1f); color: #fff;
      border-radius: 24px; padding: 2.4rem 1.6rem; text-align: center; margin: 3rem auto; box-shadow: var(--shadow);
      width: min(100% - 2rem, var(--max));
    }
    .final-cta h2 { margin: 0 0 0.6rem; }
    .final-cta p { color: rgba(255,255,255,0.88); max-width: 32rem; margin: 0 auto 1.2rem; }

    footer { padding: 2.5rem 0 3rem; color: var(--muted); font-size: 0.92rem; text-align: center; }
    footer .brand { color: var(--green-deep); }

    @media (max-width: 720px) {
      .toc > ol { columns: 1; }
      .toc { margin-top: -1.5rem; }
    }
  </style>
</head>
<body>
  <header class="site-header">
    <div class="inner">
      <a class="brand" href="index.html">AVA<span>платформа сиз учун</span></a>
      <a class="btn" href="index.html#download">Иловани очиш</a>
    </div>
  </header>

  <div id="top" class="cover">
    <div class="wrap">
      <div class="kicker">AVA · Имкониятлар китоби</div>
      <h1>${esc(book.cover.title)}</h1>
      ${book.cover.taglines.map((t) => `<div class="tagline">${esc(t)}</div>`).join('\n')}
      <div class="year">${esc(book.cover.year)}</div>
    </div>
  </div>

  <div class="wrap">
    ${toc}
  </div>

  <main class="read">
    ${body}
  </main>

  <div class="final-cta">
    <h2>Ўз имкониятингизни ишга солинг</h2>
    <p>Китобдаги ҳикоялар — AVA’даги ҳақиқий бўлимлар билан боғлиқ: такси, юк, савдо, AVAGram ва бошқа хизматлар орқали.</p>
    <a class="btn" href="index.html#modules">Хизматларни кўриш</a>
  </div>

  <footer>
    <div class="brand">AVA</div>
    <div>© AVA · платформа сиз учун</div>
    <div style="margin-top:0.35rem"><a href="index.html">Бош саҳифа</a></div>
  </footer>
</body>
</html>
`;

fs.writeFileSync(OUT, html, 'utf8');
console.log('Written:', OUT, `(${(html.length / 1024).toFixed(1)} KB)`);
