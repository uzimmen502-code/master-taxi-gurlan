#!/usr/bin/env node
'use strict';
/**
 * Ўзбек лотин алифбоси янгиланиши (эга 2026-11-19):
 *   O‘ o‘ → Ö ö · G‘ g‘ → Ğ ğ · Sh sh → Ş ş · Ch ch → Ç ç
 * (o/g дан кейинги апостроф вариантлари: ' ‘ ’ ʻ `). ʼ (U+02BC) — тутуқ белгиси, ҳарф эмас.
 *
 * Қоидалар:
 *  - фақат ЛОТИН ўзбек матни ўзгаради; кирилл/бошқа ёзув тегилмайди;
 *  - {placeholder}, URL (http(s)://…, www.…), e-mail — ўзгармайди;
 *  - бренд/хорижий сўзлар (EXCLUDE) — ўзгармайди; «Telegram'ga» каби қўшимчали шаклда бренд қисми
 *    сақланади, қўшимча апострофдан кейин алоҳида;
 *  - ажратувчи: «s'h» / «sʼh» (Is'hoq) ş бўлмайди (апостроф s ва h ни ажратади — табиий);
 *  - катта ҳарф: «Sh»/«SH» → «Ş», «Ch»/«CH» → «Ç».
 *
 * CLI:
 *   node tools/uz_latin_alphabet.js <uz_Latn.json> [--write] [--compare <uz_Cyrl.json>]
 *     — JSON қийматларини (калитлар эмас) айлантиради; --write бўлмаса фақат ҳисобот (dry-run).
 *     --compare: ҳар калит учун кирилл ш/ч/ў/ғ сони билан лотин ş/ç/ö/ğ сонини солиштиради (кўриб чиқиш рўйхати).
 */

const fs = require('fs');

const APOS = "'‘’ʻ`"; // ' ‘ ’ ʻ `

/** Бренд ва хорижий сўзлар (кичик ҳарфда). Сўз бутунича (ёки апострофгача бўлган биринчи қисми) мос келса — тегилмайди. */
const EXCLUDE = new Set([
  'ava', 'avagram', 'whatsapp', 'telegram', 'chrome', 'push', 'chat', 'chats', 'shop', 'shops', 'youtube', 'facebook',
  'instagram', 'click', 'payme', 'paynet', 'cashback', 'google', 'play', 'android', 'iphone', 'ios', 'apple',
  'samsung', 'xiaomi', 'huawei', 'chatgpt', 'openai', 'deepseek', 'excel', 'microsoft', 'yandex', 'uzum',
  'wechat', 'tiktok', 'twitter', 'linkedin', 'gmail', 'email', 'e-mail', 'bluetooth', 'wifi', 'wi-fi', 'qr',
  'sms', 'pdf', 'xlsx', 'csv', 'url', 'link', 'online', 'offline', 'premium', 'plus', 'pro', 'smart', 'cash',
  'flash', 'touch', 'switch', 'match', 'search', 'dispatcher', 'crashlytics', 'firebase', 'cloudflare', 'chevrolet',
  'cherry', 'chery', 'changan', 'shopping', 'checkout', 'chess', 'chip', 'chips', 'chiller',
  'ketchup', 'sandwich', 'shawarma', 'shake', 'milkshake', 'cheesecake', 'cheese', 'chocolate', 'nachos', 'sushi',
  'hashtag', 'dashboard', 'splash', 'refresh', 'cache', 'beach', 'coach', 'pitch', 'sketch', 'watch', 'smartwatch',
  'mastercard', 'visa', 'humo', 'uzcard', 'paypal', 'zoom', 'skype', 'viber', 'botim',
]);

/**
 * Хорижий ўзаклар + ўзбек қўшимчаси («Chatlar», «Matchni»): ўзак сақланади, қўшимча айланади.
 * Фақат рўйхатдаги қўшимчалар (бошқа сўз — масалан «chatoq» — оддий айланади).
 */
const EXCLUDE_STEMS = ['chat', 'match', 'shop'];
const UZ_SUFFIX_RE = /^(?:lar|ni|ga|da|dan|ning|dagi|i|im|ing|ingiz|imiz|si|ri)*$/i;

/** Матндан ўзгармайдиган бўлакларни (placeholder, URL, e-mail) ажратиш. */
const PROTECT_RE = /\{[^{}]*\}|https?:\/\/\S+|www\.\S+|[\w.+-]+@[\w-]+\.[\w.]+/g;

/** Лотин сўз: ҳарфлар + апостроф вариантлари + ʼ (сўз ичида). */
const WORD_RE = new RegExp(`[A-Za-z\\u00C0-\\u024F${APOS}\\u02BC]+`, 'g');

function isUpper(ch) {
  return ch !== ch.toLowerCase() && ch === ch.toUpperCase();
}

/** Бир бўлакни (бренд текширувисиз) айлантиради. */
function convertChunk(s) {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    const n = s[i + 1];
    const lc = c.toLowerCase();
    if ((lc === 'o' || lc === 'g') && n !== undefined && APOS.includes(n)) {
      // Апостроф олдидаги o/g — ҳарф (бренд эмас; брендлар convertWord да ажратилган).
      const map = lc === 'o' ? 'ö' : 'ğ';
      out += isUpper(c) ? map.toUpperCase() : map;
      i += 1;
      continue;
    }
    if ((lc === 's' || lc === 'c') && n !== undefined && n.toLowerCase() === 'h') {
      const map = lc === 's' ? 'ş' : 'ç';
      out += isUpper(c) ? map.toUpperCase() : map;
      i += 1;
      continue;
    }
    out += c;
  }
  return out;
}

function convertWord(w) {
  // «Telegram'ga», «Go'da»: биринчи қисм бренд бўлса — у сақланади, қолгани (апострофдан бошлаб) айланади.
  const m = w.match(new RegExp(`^([^${APOS}\\u02BC]+)([${APOS}\\u02BC].*)?$`));
  const head = m ? m[1] : w;
  const tail = m && m[2] ? m[2] : '';
  if (EXCLUDE.has(head.toLowerCase())) return head + (tail ? tail[0] + convertChunk(tail.slice(1)) : '');
  if (EXCLUDE.has(w.toLowerCase())) return w;
  for (const st of EXCLUDE_STEMS) {
    if (head.length > st.length && head.toLowerCase().startsWith(st) && UZ_SUFFIX_RE.test(head.slice(st.length))) {
      return head + (tail ? tail[0] + convertChunk(tail.slice(1)) : '');
    }
  }
  return convertChunk(w);
}

/** Матнни янги алифбога айлантиради. */
function convertText(text) {
  if (typeof text !== 'string' || !text) return text;
  let out = '';
  let last = 0;
  PROTECT_RE.lastIndex = 0;
  let m;
  while ((m = PROTECT_RE.exec(text)) !== null) {
    out += text.slice(last, m.index).replace(WORD_RE, convertWord) + m[0];
    last = m.index + m[0].length;
  }
  return out + text.slice(last).replace(WORD_RE, convertWord);
}

/** Ўзгарган сўзлар рўйхати (кўриб чиқиш учун): [{from, to}] (такрорсиз; placeholder/URL ичидагилар ҳисобга олинмайди). */
function changedWords(before) {
  const res = new Map();
  for (const w of (before.replace(PROTECT_RE, ' ').match(WORD_RE) || [])) {
    const c = convertWord(w);
    if (c !== w) res.set(w, c);
  }
  return [...res].map(([from, to]) => ({ from, to }));
}

/** Ҳарф сонлари (кирилл ↔ янги лотин солиштириш учун). */
function letterCounts(s, script) {
  const cnt = (re) => (s.match(re) || []).length;
  if (script === 'cyrl') {
    return { sh: cnt(/[шщШЩ]/g), ch: cnt(/[чЧ]/g), o: cnt(/[ўЎ]/g), g: cnt(/[ғҒ]/g) };
  }
  return { sh: cnt(/[şŞ]/g), ch: cnt(/[çÇ]/g), o: cnt(/[öÖ]/g), g: cnt(/[ğĞ]/g) };
}

/** JSON (калит → қиймат) ни айлантиради; формат сақланади (2 пробел, LF). */
function convertLangJson(src) {
  const obj = JSON.parse(src);
  const nl = src.includes('\r\n') ? '\r\n' : '\n';
  const roundtrip = JSON.stringify(obj, null, 2) + nl;
  if (roundtrip.replace(/\r\n/g, '\n') !== src.replace(/\r\n/g, '\n')) {
    throw new Error('FORMAT_NOT_ROUNDTRIP: JSON.stringify(parse(src), null, 2) манбага тенг эмас');
  }
  const out = {};
  const changes = [];
  for (const [k, v] of Object.entries(obj)) {
    const c = convertText(v);
    out[k] = c;
    if (c !== v) changes.push({ key: k, from: v, to: c });
  }
  let text = JSON.stringify(out, null, 2) + '\n';
  if (nl === '\r\n') text = text.replace(/\n/g, '\r\n');
  return { text, changes, out };
}

function main(argv) {
  const args = argv.filter((a) => !a.startsWith('--'));
  const file = args[0];
  if (!file) {
    console.error('usage: node tools/uz_latin_alphabet.js <uz_Latn.json> [--write] [--compare <uz_Cyrl.json>]');
    process.exitCode = 2;
    return;
  }
  const write = argv.includes('--write');
  const ci = argv.indexOf('--compare');
  const src = fs.readFileSync(file, 'utf8');
  const { text, changes, out } = convertLangJson(src);
  const words = new Map();
  for (const ch of changes) for (const { from, to } of changedWords(ch.from)) words.set(from, to);
  const foreignRisk = [...words].filter(([, to]) => /[şŞçÇ]/.test(to)).map(([f, t]) => `${f} → ${t}`).sort();
  console.log(`keys changed: ${changes.length}; unique words changed: ${words.size}`);
  console.log(`--- review: sh/ch words (${foreignRisk.length}) ---`);
  for (const l of foreignRisk) console.log(l);
  if (ci >= 0) {
    const cyr = JSON.parse(fs.readFileSync(argv[ci + 1], 'utf8'));
    const mism = [];
    for (const [k, v] of Object.entries(out)) {
      if (typeof cyr[k] !== 'string') continue;
      const a = letterCounts(cyr[k], 'cyrl');
      const b = letterCounts(v, 'latn');
      if (a.sh !== b.sh || a.ch !== b.ch || a.o !== b.o || a.g !== b.g) mism.push({ k, a, b, v, c: cyr[k] });
    }
    console.log(`--- compare with Cyrillic: ${mism.length} keys differ ---`);
    for (const x of mism) console.log(`${x.k}\n  cyr ${JSON.stringify(x.a)} ${x.c}\n  lat ${JSON.stringify(x.b)} ${x.v}`);
  }
  if (write) {
    fs.writeFileSync(file, text);
    console.log(`written: ${file}`);
  } else {
    console.log('dry-run (no --write)');
  }
}

module.exports = { convertText, convertWord, convertLangJson, letterCounts, changedWords, EXCLUDE };

if (require.main === module) main(process.argv.slice(2));
