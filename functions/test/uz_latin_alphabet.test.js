'use strict';
/**
 * Ўзбек лотин алифбоси (эга 2026-11-19) — tools/uz_latin_alphabet.js соф тестлари.
 *   node test/uz_latin_alphabet.test.js
 */
const assert = require('assert');
const U = require('../tools/uz_latin_alphabet');

let passed = 0;
let failed = 0;
function check(name, fn) {
  try {
    fn();
    passed++;
    console.log(`PASS - ${name}`);
  } catch (e) {
    failed++;
    console.log(`FAIL - ${name}\n  ${e.message}`);
  }
}
const c = U.convertText;

check('o‘/g‘ — all apostrophe variants', () => {
  for (const a of ["'", '‘', '’', 'ʻ', '`']) {
    assert.strictEqual(c(`yo${a}q`), 'yöq');
    assert.strictEqual(c(`tog${a}`), 'toğ');
    assert.strictEqual(c(`O${a}zbekcha`), 'Özbekça');
    assert.strictEqual(c(`G${a}isht`), 'Ğişt');
  }
});
check('sh/ch — case', () => {
  assert.strictEqual(c('Toshkent shahri'), 'Toşkent şahri');
  assert.strictEqual(c('SHOSHILINCH'), 'ŞOŞILINÇ');
  assert.strictEqual(c('Chiqish'), 'Çiqiş');
  assert.strictEqual(c('uchun'), 'uçun');
});
check('ʼ (U+02BC) is tutuq, not a letter mark', () => {
  assert.strictEqual(c('maʼlumot'), 'maʼlumot');
  assert.strictEqual(c('moʼjiza'), 'moʼjiza');
});
check("separator s'h / sʼh stays (Is'hoq)", () => {
  assert.strictEqual(c("Is'hoq"), "Is'hoq");
  assert.strictEqual(c('Isʼhoq'), 'Isʼhoq');
  assert.strictEqual(c('as’hob'), 'as’hob');
});
check('placeholders, URLs, e-mails untouched', () => {
  assert.strictEqual(c('{shop} o‘chirildi'), '{shop} öçirildi');
  assert.strictEqual(c('https://ava.uz/shop?ch=1 ko\'ring'), 'https://ava.uz/shop?ch=1 köring');
  assert.strictEqual(c('www.chat.uz'), 'www.chat.uz');
  assert.strictEqual(c('help@ashyo.uz ga yozing'), 'help@ashyo.uz ga yozing');
});
check('brands / foreign words untouched (whole word and before suffix apostrophe)', () => {
  assert.strictEqual(c('WhatsApp, Telegram, Chrome, Push, Chat, Shop, AVAGram'), 'WhatsApp, Telegram, Chrome, Push, Chat, Shop, AVAGram');
  assert.strictEqual(c("Telegram'ga o'ting"), "Telegram'ga öting");
  assert.strictEqual(c('Cashback, Click, Payme, Paynet, YouTube, Facebook, Instagram'), 'Cashback, Click, Payme, Paynet, YouTube, Facebook, Instagram');
  assert.strictEqual(c('Dispatcher'), 'Dispatcher');
});
check('foreign stem + Uzbek suffix kept; other words convert', () => {
  assert.strictEqual(c('Chatlar'), 'Chatlar');
  assert.strictEqual(c('Matchni'), 'Matchni');
  assert.strictEqual(c('chatoq'), 'çatoq');
  assert.strictEqual(c('pushti'), 'puşti');
});
check("Uzbek word starting like a short brand still converts (Go'sht)", () => {
  assert.strictEqual(c("Go'sht"), 'Göşt');
  assert.strictEqual(c("go'shtlarni"), 'göştlarni');
});
check('Cyrillic and mixed text: Cyrillic untouched', () => {
  assert.strictEqual(c('5 000 сўм, Qo‘shish'), '5 000 сўм, Qöşiş');
  assert.strictEqual(c('Шаҳар'), 'Шаҳар');
});
check('idempotent', () => {
  const s = "O'zbekiston shaharlari: Toshkent, G'ijduvon, Chilonzor";
  assert.strictEqual(c(c(s)), c(s));
});
check('non-string / empty', () => {
  assert.strictEqual(c(''), '');
  assert.strictEqual(c(null), null);
});
check('lang JSON: values only, keys and format kept', () => {
  const src = '{\n  "o\'chirish_key": "O\'chirish",\n  "sh": "{n} ta shahar\\nyangi"\n}\n';
  const { text, changes } = U.convertLangJson(src);
  assert.strictEqual(text, '{\n  "o\'chirish_key": "Öçiriş",\n  "sh": "{n} ta şahar\\nyangi"\n}\n');
  assert.strictEqual(changes.length, 2);
  assert.throws(() => U.convertLangJson('{"a":"b"}'), /FORMAT_NOT_ROUNDTRIP/);
});
check('CRLF format preserved', () => {
  const src = '{\r\n  "a": "shu"\r\n}\r\n';
  assert.strictEqual(U.convertLangJson(src).text, '{\r\n  "a": "şu"\r\n}\r\n');
});
check('letterCounts Cyrillic vs new Latin agree on a sample', () => {
  assert.deepStrictEqual(U.letterCounts('Ўзбекча шаҳар ғишт', 'cyrl'), U.letterCounts(c("O'zbekcha shahar g'isht"), 'latn'));
});

console.log(`\n${passed}/${passed + failed} passed`);
if (failed) process.exitCode = 1;
