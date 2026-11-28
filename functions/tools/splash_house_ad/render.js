/**
 * «Splash реклама» НАМУНА (уй) креативини расмга айлантиради (эга 2026-11-28).
 *
 * `template.html` (3 тил) → Chrome headless скриншот 1080×1920 → `sharp` (functions боғлиқлиги, янги пакет йўқ)
 * билан PNG (сиқилган) ва WebP. Натижа: `out/house_{lang}.png|webp` (+ ихтиёрий `--copy <dir>` нусха).
 * Production'га ҲЕЧ НАРСА ёзмайди.
 *
 *   node functions/tools/splash_house_ad/render.js [--chrome <path>] [--copy <dir>]
 *
 * Чегара (SplashAdTexts.creativeSpec / SplashAdPrefetcher.maxImageBytes): ≤ 500 КБ тавсия, 1500 КБ — қатъий.
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const LANGS = ['uz_Cyrl', 'uz_Latn', 'ru'];
const W = 1080;
const H = 1920;
const HARD_MAX = 1500 * 1024;
const SOFT_MAX = 500 * 1024;

function findChrome(argv) {
  const i = argv.indexOf('--chrome');
  const cands = [
    i >= 0 ? argv[i + 1] : '', process.env.CHROME || '',
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
    '/usr/bin/google-chrome', '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ];
  const hit = cands.find((p) => p && fs.existsSync(p));
  if (!hit) throw new Error('Chrome/Edge топилмади (--chrome <path>).');
  return hit;
}

async function main() {
  const argv = process.argv.slice(2);
  const sharp = require('sharp');
  const chrome = findChrome(argv);
  const ci = argv.indexOf('--copy');
  const copyDir = ci >= 0 ? path.resolve(argv[ci + 1]) : '';
  const tpl = path.join(__dirname, 'template.html');
  const outDir = path.join(__dirname, 'out');
  fs.mkdirSync(outDir, { recursive: true });
  if (copyDir) fs.mkdirSync(copyDir, { recursive: true });
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'splash-house-'));
  const url = (lang) => `file:///${tpl.replace(/\\/g, '/')}?lang=${lang}`;
  const report = [];
  try {
    for (const lang of LANGS) {
      const raw = path.join(profile, `raw_${lang}.png`);
      execFileSync(chrome, [
        '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
        `--window-size=${W},${H}`, '--virtual-time-budget=4000', `--user-data-dir=${profile}`,
        `--screenshot=${raw}`, url(lang),
      ], { stdio: 'ignore' });
      const meta = await sharp(raw).metadata();
      if (meta.width !== W || meta.height !== H) throw new Error(`${lang}: ${meta.width}×${meta.height} ≠ ${W}×${H}`);
      const png = await sharp(raw).png({ compressionLevel: 9, palette: true, quality: 95, effort: 10 }).toBuffer();
      const webp = await sharp(raw).webp({ quality: 90, effort: 6 }).toBuffer();
      for (const [ext, buf] of [['png', png], ['webp', webp]]) {
        if (buf.length > HARD_MAX) throw new Error(`${lang}.${ext}: ${buf.length} B > 1500 КБ`);
        const name = `house_${lang}.${ext}`;
        fs.writeFileSync(path.join(outDir, name), buf);
        if (copyDir) fs.writeFileSync(path.join(copyDir, name), buf);
        report.push({ name, bytes: buf.length, kb: Math.round(buf.length / 1024), underSoft: buf.length <= SOFT_MAX });
      }
    }
  } finally {
    fs.rmSync(profile, { recursive: true, force: true });
  }
  console.table(report);
}

if (require.main === module) main().catch((e) => { console.error(e.message || e); process.exit(1); });
