/**
 * ЛУҒАТ ЭСКИРМАГАНМИ — ҚУЛФ.
 *
 *   npm --prefix functions_demand run test:dict
 *
 * НЕГА БУ ТЕСТ БОР (ҳақиқий ҳолат, 2026-10-03):
 * `canonText` ўзгартирилди (апостроф тушириб юбориладиган бўлди), лекин
 * генератор ишга тушмай қолди — PowerShell буйруғи parse хатоси билан
 * тўхтаган эди. Натижада `assets/data/intent_keywords.json` ЭСКИ
 * қолди ва илова «ток йўқ» сўровини тополмай қўйди.
 *
 * Хато ЖИМГИНА содир бўлди: сервер тестлари яшил эди (улар модулларни
 * бевосита `require` қилади), фақат Dart тестлари йиқилди — ва сабабни
 * топиш учун луғатни қўлда текшириш керак бўлди.
 *
 * Бу тест генераторни ҚАЙТА ЮРГИЗАДИ (вақтинчалик файлга) ва
 * коммитланган нусха билан солиштиради. Фарқ бўлса — луғатни қайта
 * генерация қилиш керак:
 *
 *   node functions_demand/tools/build_intent_keywords.js
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

let passed = 0;
function ok(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`  OK  ${name}`);
  } catch (e) {
    console.error(`  XATO ${name}\n       ${e.message}`);
    process.exitCode = 1;
  }
}

const ROOT = path.join(__dirname, '..', '..');
const ASSET = path.join(ROOT, 'assets', 'data', 'intent_keywords.json');
const GENERATOR = path.join(__dirname, '..', 'tools', 'build_intent_keywords.js');

console.log('lug`at yangiligi');

ok('lug`at fayli bor', () => {
  assert.ok(fs.existsSync(ASSET), `topilmadi: ${ASSET}`);
});

ok('KOMMITLANGAN nusxa generator natijasi bilan AYNAN bir xil', () => {
  const committed = fs.readFileSync(ASSET, 'utf8');

  // Generator fayl ustiga yozadi, shuning uchun avval zaxira olamiz va
  // keyin qaytaramiz — test hech narsani o'zgartirmasligi kerak.
  const backup = path.join(os.tmpdir(), `intent_keywords_backup_${process.pid}.json`);
  fs.writeFileSync(backup, committed, 'utf8');

  try {
    execFileSync(process.execPath, [GENERATOR], { stdio: 'pipe' });
    const regenerated = fs.readFileSync(ASSET, 'utf8');

    if (regenerated !== committed) {
      // Farqni tushunarli ko'rsatamiz: qaysi kalitlar o'zgargan.
      const a = JSON.parse(committed);
      const b = JSON.parse(regenerated);
      const ak = Object.keys(a.keywords || {});
      const bk = Object.keys(b.keywords || {});
      const missing = ak.filter((k) => !(k in (b.keywords || {}))).slice(0, 8);
      const extra = bk.filter((k) => !(k in (a.keywords || {}))).slice(0, 8);
      throw new Error(
        'Lug\'at ESKIRGAN. Qayta generatsiya qiling:\n'
        + '       node functions_demand/tools/build_intent_keywords.js\n'
        + `       kalit soni: kommitlangan ${ak.length}, kutilgan ${bk.length}\n`
        + (missing.length ? `       kommitlangan nusxada ORTIQCHA: ${missing.join(', ')}\n` : '')
        + (extra.length ? `       kommitlangan nusxada YETMAYDI: ${extra.join(', ')}` : ''),
      );
    }
  } finally {
    // Nima bo'lsa ham kommitlangan holatni qaytaramiz.
    fs.writeFileSync(ASSET, committed, 'utf8');
    try { fs.unlinkSync(backup); } catch (_) { /* muhim emas */ }
  }
});

ok('lug`at kanon shaklda — apostrof YO`Q', () => {
  // Apostrof tushirib yuborilishi `canonText` qarori; lug'at ham shunga
  // mos bo'lishi kerak.
  const j = JSON.parse(fs.readFileSync(ASSET, 'utf8'));
  const withApostrophe = Object.keys(j.keywords || {}).filter((k) => k.includes("'"));
  assert.strictEqual(
    withApostrophe.length, 0,
    `apostrofli kalit qoldi: ${withApostrophe.slice(0, 5).join(', ')}`,
  );
  const sup = (j.suppressWords || []).filter((k) => k.includes("'"));
  assert.strictEqual(sup.length, 0, `suppressWords da apostrof: ${sup.join(', ')}`);
});

ok('asosiy kalitlar joyida (regressiya qulfi)', () => {
  const j = JSON.parse(fs.readFileSync(ASSET, 'utf8'));
  const kw = j.keywords || {};
  // Ega keltirgan misollar va parity testdagi kalitlar.
  const must = {
    santexnik: 'santexnik',
    elektrik: 'elektrik',
    'tok yoq': 'elektrik',
    'mebel yigish': 'mebel_yigish',
    'gisht teruvchi': 'qurilish_brigada',
  };
  for (const [key, cat] of Object.entries(must)) {
    assert.ok(kw[key], `«${key}» kaliti yo'q`);
    assert.ok(
      kw[key].includes(cat),
      `«${key}» -> ${kw[key].join(',')} (kutilgan: ${cat})`,
    );
  }
});

ok('modul kalitlari joyida', () => {
  const j = JSON.parse(fs.readFileSync(ASSET, 'utf8'));
  const mk = j.moduleKeywords || {};
  // «Курьер керак» -> canon «kurer kerak» -> «kurer» kaliti.
  assert.ok(mk.kurer, '«kurer» modul kaliti yo`q');
  assert.ok(mk.kurer.includes('courier'));
  assert.ok(mk.taksi, '«taksi» modul kaliti yo`q');
  assert.ok(mk.kvartira, '«kvartira» modul kaliti yo`q');
});

console.log(`\n${passed} test o'tdi.`);
