/**
 * Settlement Ledger — to'liq E2E runner (CI uchun).
 * reconcile + open (pending) + confirm + deferred + reconcile invariant.
 * Ishlatish: node tools/settlement_e2e_test.js
 */
const { spawnSync } = require('child_process');
const path = require('path');

const toolsDir = __dirname;
const node = process.execPath;
const tests = [
  'settlement_spend_test.js',
  'settlement_trip_test.js',
  'settlement_deferred_test.js',
];

let failed = 0;
console.log('=== Settlement E2E suite ===\n');

for (const file of tests) {
  const full = path.join(toolsDir, file);
  console.log(`--- ${file} ---`);
  const r = spawnSync(node, [full], { stdio: 'inherit', cwd: path.join(toolsDir, '..') });
  if (r.status !== 0) {
    failed++;
    console.error(`FAILED: ${file}\n`);
  } else {
    console.log(`OK: ${file}\n`);
  }
}

if (failed > 0) {
  console.error(`=== E2E suite: ${failed} test file(s) failed ===`);
  process.exit(1);
}
console.log('=== E2E suite: all passed ===');
process.exit(0);
