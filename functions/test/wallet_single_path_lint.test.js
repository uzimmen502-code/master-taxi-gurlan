/**
 * Ҳамён ягона ёзиш йўли — линт (W-1, 2-қадам). Emulator керак эмас.
 *
 *   node functions/test/wallet_single_path_lint.test.js
 *
 * Қоида: `users.bonusBalance` ва `users/{uid}/wallet_ledger` га ЁЗИШ фақат `settlement_ledger.js` орқали
 * (`walletPost` / `postEntry`). Ҳозирги ёзувчилар `ALLOW` рўйхатида — рўйхат ФАҚАТ ҚИСҚАРАДИ:
 *   - янги файл ёки кўпроқ ўхшаш жой пайдо бўлса — FAIL;
 *   - жой камайса (модул кўчирилди) — FAIL «рўйхатни камайтиринг» (рўйхат ҳақиқатга тенг бўлиб туради);
 *   - Σ рўйхат `BASELINE_TOTAL` дан ошса — FAIL (рўйхатни катталаштириш тақиқ).
 *
 * Қамров: деплой қилинадиган код (`functions/*.js` ва ички папкалар), `test/`, `tools/`, `node_modules/`
 * бундан мустасно (tools — эга қўлда ишга туширадиган бир марталик миграция скриптлари, алоҳида кўриб чиқилади).
 *
 * Ҳисобланадиган нақшлар (консерватив — ўқиш/жавоб объектидаги `bonusBalance:` ҳам санаади):
 *   P1  `bonusBalance:` (объект майдони)        P2  `'bonusBalance'` (string майдон йўли)
 *   P3  `collection('wallet_ledger')` дан кейин `.doc(` ёки `.add(`
 */
'use strict';
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const ROOT = path.join(__dirname, '..');
const OWNER = 'settlement_ledger.js';
const SKIP_DIRS = new Set(['node_modules', 'test', 'tools', '.git', 'lib']);

/** Файл → ўхшаш жойлар сони. ФАҚАТ КАМАЯДИ. (2026-11-28, feat/wallet-single-path бошланиши.) */
const ALLOW = {
  'account_deletion.js': 4,
  'assistant_chat.js': 2,
  'business_orders.js': 4,
  'car_insurance.js': 4,
  'ev_charging.js': 2,
  'index.js': 49,
  'realty.js': 6,
  'splash_ads.js': 4,
  'supermarket.js': 4,
  'wholesale_orders.js': 3,
};
// Бошланғич 94 (2026-11-28). Ҳар кўчиришда шу сон ҳам камайтирилади.
const BASELINE_TOTAL = 82;

// Ёзиш нақшлари (ўқиш — масалан жавоб объектидаги `bonusBalance` ёки `where('bonusBalance', ...)` — санаалмайди).
//   W1 `.set/.update/.create(…, { … bonusBalance: …` (объект литерали ичида)
//   W2 `bonusBalance: …increment(` / `bonusBalance: inc(` (қаерда бўлмасин)
//   W3 `.update(ref, 'bonusBalance', …)` (string йўл)
//   W4 `collection('wallet_ledger').doc(…)` (кейин `.get(` бўлмаса) ёки `.add(`
// Чеклов: патч олдин ўзгарувчида йиғилиб кейин `set(ref, patch)` қилинса — ушланмайди; бунга қарши кунлик
// `walletInvariantDailyCheck` (I-1/I-3) ва код кўриги.
const W1 = /\.(?:set|update|create)\([^;{}]*\{[^{}]*?\b(bonusBalance)\s*:/g;
const W2 = /\b(bonusBalance)\s*:\s*(?:admin\.firestore\.)?(?:FieldValue\.)?(?:increment|inc)\(/g;
const W3 = /\.update\([^;]*?['"](bonusBalance)['"]/g;
const W4 = /collection\(\s*['"]wallet_ledger['"]\s*\)\s*\.\s*(?:doc\([^)]*\)(?!\s*\.\s*get\()|add\()/g;

function stripComments(src) {
  return src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`\\])\/\/[^\n]*/g, '$1');
}
function listFiles(dir, rel = '') {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) {
      if (!SKIP_DIRS.has(e.name) && !e.name.startsWith('.')) out.push(...listFiles(path.join(dir, e.name), path.join(rel, e.name)));
    } else if (e.name.endsWith('.js')) {
      out.push(path.join(rel, e.name).split(path.sep).join('/'));
    }
  }
  return out;
}
function countSites(file) {
  return countSrc(fs.readFileSync(path.join(ROOT, file), 'utf8'));
}
function countSrc(raw) {
  const src = stripComments(raw);
  // bonusBalance ёзувлари — токен ўрни бўйича бир марта (W1 ва W2 бир жойни икки марта санамасин).
  const pos = new Set();
  for (const re of [W1, W2, W3]) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(src)) !== null) {
      pos.add(m.index + m[0].lastIndexOf(m[1]));
      re.lastIndex = m.index + 1;
    }
  }
  return pos.size + (src.match(W4) || []).length;
}

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};

check('L0 detektor: yozuvlarni ushlaydi, o\'qishlarni sanamaydi', () => {
  const writes = [
    't.set(userRef, { bonusBalance: inc(delta), balanceUpdatedAt: ts() }, { merge: true });',
    't.update(customerRef, {\n  bonusBalance: admin.firestore.FieldValue.increment(-walletSum),\n});',
    'tx.set(db.collection(\'users\').doc(uid), { a: 1, bonusBalance: prev - price });',
    'const patch = { bonusBalance: admin.firestore.FieldValue.increment(5) };',
    't.update(ref, \'bonusBalance\', 0);',
    't.set(userRef.collection(\'wallet_ledger\').doc(), { type: \'x\' });',
    'const r = userRef.collection(\'wallet_ledger\').doc(`k_${id}`);',
    'await ref.collection(\'wallet_ledger\').add({ type: \'x\' });',
  ];
  writes.forEach((w) => assert.strictEqual(countSrc(w), 1, w));
  const reads = [
    'const b = (snap.data() || {}).bonusBalance || 0;',
    'return { ok: true, bonusBalance };',
    'return { ok: true, bonusBalance: bal };',
    'db.collection(\'users\').where(\'bonusBalance\', \'>\', 0).get();',
    'await userRef.collection(\'wallet_ledger\').doc(id).get();',
    'userRef.collection(\'wallet_ledger\').orderBy(\'createdAt\').limit(5).get();',
    '// t.set(userRef, { bonusBalance: 0 })',
  ];
  reads.forEach((r) => assert.strictEqual(countSrc(r), 0, r));
});

const actual = {};
for (const f of listFiles(ROOT)) {
  if (f === OWNER) continue;
  const c = countSites(f);
  if (c > 0) actual[f] = c;
}

check('L1 ruxsat ro\'yxatidan tashqari fayl bonusBalance/wallet_ledger\'ga yozmaydi', () => {
  const extra = Object.keys(actual).filter((f) => !(f in ALLOW));
  assert.deepStrictEqual(extra, [], `yangi yozuvchi(lar): ${extra.map((f) => `${f}=${actual[f]}`).join(', ')} — settlement_ledger.walletPost ishlating`);
});
check('L2 ro\'yxatdagi fayllarda joylar ko\'paymagan', () => {
  const grown = Object.keys(ALLOW).filter((f) => (actual[f] || 0) > ALLOW[f]);
  assert.deepStrictEqual(grown, [], grown.map((f) => `${f}: ${actual[f]} > ${ALLOW[f]}`).join(', '));
});
check('L3 ro\'yxat haqiqatga teng (ko\'chirilgan modul ro\'yxatdan chiqariladi / soni kamaytiriladi)', () => {
  const shrunk = Object.keys(ALLOW).filter((f) => (actual[f] || 0) < ALLOW[f]);
  assert.deepStrictEqual(shrunk, [], `ALLOW'ni kamaytiring: ${shrunk.map((f) => `${f}: ${ALLOW[f]} → ${actual[f] || 0}`).join(', ')}`);
});
check('L4 ro\'yxat yig\'indisi bazadan oshmaydi (faqat qisqaradi)', () => {
  const total = Object.values(ALLOW).reduce((a, b) => a + b, 0);
  assert.ok(total <= BASELINE_TOTAL, `Σ ALLOW ${total} > ${BASELINE_TOTAL}`);
});

check('L5 settlement_ledger.js yagona yo\'lni eksport qiladi (prepareWalletPost / walletPost)', () => {
  const sl = require('../settlement_ledger');
  assert.strictEqual(typeof sl.walletPost, 'function');
  assert.strictEqual(typeof sl.prepareWalletPost, 'function');
});

const passed = results.filter(Boolean).length;
console.log(`\n${passed} passed, ${results.length - passed} failed`);
if (process.env.LINT_PRINT) console.log(JSON.stringify(actual, null, 1));
process.exit(results.length - passed ? 1 : 0);
