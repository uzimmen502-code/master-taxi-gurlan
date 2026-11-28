/**
 * Barcha *.test.js fayllarini ketma-ket, har biri TOZA emulator ma'lumoti
 * bilan ishga tushiradi (functions/test yoki functions_demand/test).
 *
 *   firebase emulators:exec --only firestore,storage,auth --project demo-testall \
 *     --config <abs>/firebase.tests.json \
 *     "node functions/test/run_all_suites.js functions/test"
 *
 * Qoidalar (2026-11-28, testlar tahlili):
 *  - Har fayl alohida node jarayonida; fayllar orasida umumiy holat yo'q.
 *  - Loyiha (GCLOUD_PROJECT) package.json'dagi `--project` dan olinadi;
 *    ro'yxatda bo'lmasa — o'rnatilmaydi (test o'z standartini ishlatadi).
 *  - Fayldan oldin u ishlatadigan barcha demo-* loyihalarning ma'lumoti
 *    tozalanadi (emulator REST DELETE) — oldingi fayl qoldig'i ta'sir qilmaydi.
 *  - FIREBASE_AUTH_EMULATOR_HOST faqat `--only firestore,auth` talab qilgan testlarga.
 *  - FIREBASE_STORAGE_EMULATOR_HOST faqat storage_* testlariga beriladi
 *    (qolganlari o'z «yo'q» standartini kutadi).
 *  - Har faylga emulator_tx_retry_preload.js yuklanadi (emulator «Transaction is invalid or
 *    closed» artefakti ishlab chiqarish SDK kabi qayta uriladi; biznes xatolar o'zgarmaydi).
 *  - Natija: har fayl PASS/FAIL, jami, va --json <fayl> bo'lsa JSON.
 *
 * Bayroqlar: --only a.test.js,b.test.js  --json out.json  --timeout 600
 */
'use strict';
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const dirArg = args.find((a) => !a.startsWith('--') && !isFlagValue(a));
function isFlagValue(a) {
  const i = args.indexOf(a);
  return i > 0 && ['--only', '--json', '--timeout'].includes(args[i - 1]);
}
function flag(name) {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
}
if (!dirArg) {
  console.error('ishlatish: node run_all_suites.js <testDir> [--only ...] [--json out]');
  process.exit(2);
}
const TEST_DIR = path.resolve(dirArg);
const PKG_DIR = path.dirname(TEST_DIR);
const ONLY = (flag('--only') || '').split(',').filter(Boolean);
const JSON_OUT = flag('--json');
const TIMEOUT_MS = Number(flag('--timeout') || 600) * 1000;

const FS_HOST = process.env.FIRESTORE_EMULATOR_HOST;
// Emulator deadlock artefakti («Transaction is invalid or closed», kod 3) — ishlab chiqarish SDK kabi
// qayta uriladi (functions_demand/test/helpers/emulator_hooks.js installEmulatorClosedTxRetry).
const PRELOAD = path.join(__dirname, '..', '..', 'functions_demand', 'test', 'helpers', 'emulator_tx_retry_preload.js');
const ST_HOST = process.env.FIREBASE_STORAGE_EMULATOR_HOST;
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST;
// emulators:exec --project qiymati. Storage emulatorining cross-service `firestore.get()`
// qoidalari Firestore'ni SHU loyihada o'qiydi — storage testlari shu loyihada ishlashi shart.
const EXEC_PROJECT = process.env.GCLOUD_PROJECT;

// package.json: test fayl -> --project
const projectByFile = {};
try {
  const pkg = JSON.parse(fs.readFileSync(path.join(PKG_DIR, 'package.json'), 'utf8'));
  for (const cmd of Object.values(pkg.scripts || {})) {
    const m = /--project\s+(\S+)\s+"node\s+test\/([^"\s]+)"/.exec(cmd);
    if (m) projectByFile[m[2]] = m[1];
  }
} catch (_) { /* package.json yo'q bo'lsa — standartlar */ }

async function clearProject(project) {
  if (!FS_HOST) return;
  try {
    await fetch(`http://${FS_HOST}/emulator/v1/projects/${project}/databases/(default)/documents`,
      { method: 'DELETE' });
  } catch (_) { /* emulator yo'q — pure test */ }
  if (!AUTH_HOST) return;
  try {
    await fetch(`http://${AUTH_HOST}/emulator/v1/projects/${project}/accounts`, { method: 'DELETE' });
  } catch (_) { /* auth emulator yo'q */ }
}

function runOne(file, src) {
  return new Promise((resolve) => {
    const env = { ...process.env };
    // Auth emulator faqat sarlavhasida `--only firestore,auth` deb yozilgan testlarga
    // (admin PIN / custom token / setCustomUserClaims). Qolganlari uni kutmaydi.
    delete env.FIREBASE_AUTH_EMULATOR_HOST;
    if (AUTH_HOST && /--only firestore,auth/.test(src)) env.FIREBASE_AUTH_EMULATOR_HOST = AUTH_HOST;
    delete env.GCLOUD_PROJECT;
    delete env.GOOGLE_CLOUD_PROJECT;
    delete env.FIREBASE_CONFIG;
    if (projectByFile[file]) env.GCLOUD_PROJECT = projectByFile[file];
    if (!/^storage_/.test(file)) delete env.FIREBASE_STORAGE_EMULATOR_HOST;
    else {
      if (ST_HOST) env.FIREBASE_STORAGE_EMULATOR_HOST = ST_HOST;
      if (EXEC_PROJECT) env.GCLOUD_PROJECT = EXEC_PROJECT;
    }
    const started = Date.now();
    const child = spawn(process.execPath, ['--require', PRELOAD, path.join(TEST_DIR, file)],
      { cwd: PKG_DIR, env, stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '';
    child.stdout.on('data', (d) => { out += d; });
    child.stderr.on('data', (d) => { out += d; });
    const timer = setTimeout(() => { out += '\n[TIMEOUT]'; child.kill('SIGKILL'); }, TIMEOUT_MS);
    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({ file, code, ms: Date.now() - started, out });
    });
  });
}

(async () => {
  const files = fs.readdirSync(TEST_DIR)
    .filter((f) => f.endsWith('.test.js'))
    .filter((f) => !ONLY.length || ONLY.includes(f))
    .sort();
  const results = [];
  for (const file of files) {
    const src = fs.readFileSync(path.join(TEST_DIR, file), 'utf8');
    const projects = new Set(src.match(/demo-[a-z0-9-]+/g) || []);
    if (projectByFile[file]) projects.add(projectByFile[file]);
    if (/^storage_/.test(file) && EXEC_PROJECT) projects.add(EXEC_PROJECT);
    for (const p of projects) await clearProject(p);
    const r = await runOne(file, src);
    const ok = r.code === 0;
    // Yiqilgan tekshiruv qatorlari (FAIL/XATO + 6 qator kontekst) — log shovqinida yo'qolmasin.
    const lines = r.out.split('\n');
    const failLines = [];
    lines.forEach((l, i) => {
      if (/^\s*(FAIL|XATO|✗|not ok)\b|\[TIMEOUT\]/.test(l)) failLines.push(...lines.slice(i, i + 7));
    });
    results.push({
      file, ok, code: r.code, ms: r.ms,
      failLines: ok ? [] : failLines.slice(0, 200), tail: ok ? '' : r.out.slice(-4000),
    });
    process.stdout.write(`${ok ? 'PASS' : 'FAIL'}  ${file}  (${(r.ms / 1000).toFixed(1)} s)\n`);
    if (!ok) process.stdout.write((failLines.length ? failLines : lines.slice(-40)).slice(0, 80).join('\n') + '\n');
  }
  const failed = results.filter((r) => !r.ok);
  console.log(`\nJAMI: ${results.length} fayl, ${results.length - failed.length} o'tdi, ${failed.length} yiqildi`);
  for (const f of failed) console.log(`  FAIL ${f.file}`);
  if (JSON_OUT) fs.writeFileSync(JSON_OUT, JSON.stringify(results, null, 2));
  process.exit(failed.length ? 1 : 0);
})();
