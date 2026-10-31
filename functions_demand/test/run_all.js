/**
 * Yadroning barcha testlari bitta buyruq bilan.
 *
 *   npm --prefix functions_demand test
 *
 * Emulator kerak emas: hamma test sof funksiyalar ustida. Firestore'ga
 * tegadigan testlar (`rules.test.js`) alohida ishlaydi va emulator talab
 * qiladi — shuning uchun bu ro'yxatda yo'q.
 */
const { execFileSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const SUITES = [
  'geo.test.js',
  'ids.test.js',
  'config.test.js',
  'capabilities_model.test.js',
  'capabilities_api.test.js',
  'agreements_admin.test.js',
  'schema.test.js',
  'state_machine.test.js',
  'scoring.test.js',
  'notify_policy.test.js',
  'trust.test.js',
  'keywords.test.js',
  'matching.test.js',
  'presence_geo.test.js',
  'presence_sweeper.test.js',
  'courier_adapter.test.js',
  'tariff.test.js',
  'logistics_core.test.js',
  'wholesale_stock.test.js',
  'logistics_api.test.js',
  'logistics_parity.test.js',
  'logistics_stage.test.js',
  'logistics_admin_stage.test.js',
  'logistics_audit.test.js',
  'logistics_loss.test.js',
  'maintenance.test.js',
  'offers.test.js',
  'parity.test.js',
  'dictionary_fresh.test.js',
  'analytics.test.js',
  'wholesale_admin.test.js',
];

let failed = 0;
const results = [];

for (const suite of SUITES) {
  const file = path.join(__dirname, suite);
  if (!fs.existsSync(file)) {
    results.push({ suite, status: 'YO`Q', count: 0 });
    continue;
  }
  process.stdout.write(`\n=== ${suite} ===\n`);
  try {
    const out = execFileSync(process.execPath, [file], { encoding: 'utf8' });
    const m = out.match(/(\d+) test o'tdi/);
    const count = m ? Number(m[1]) : 0;
    // DIQQAT: shunchaki /XATO/ qidirish YARAMAYDI — test NOMIDA ham «XATO»
    // so'zi bo'lishi mumkin (masalan «noto'g'ri o'tish XATO tashlaydi»).
    // Haqiqiy muvaffaqiyatsizlik doim qator boshida `  XATO ` bo'lib chiqadi.
    const hasError = /^ {2}XATO /m.test(out);
    if (hasError) {
      process.stdout.write(out);
      failed += 1;
      results.push({ suite, status: 'XATO', count });
    } else {
      process.stdout.write(`${count} test o'tdi.\n`);
      results.push({ suite, status: 'OK', count });
    }
  } catch (e) {
    process.stdout.write(`${e.stdout || ''}${e.stderr || ''}`);
    failed += 1;
    results.push({ suite, status: 'XATO', count: 0 });
  }
}

const total = results.reduce((s, r) => s + r.count, 0);
console.log('\n──────────────────────────────────────────');
for (const r of results) {
  console.log(`  ${r.status.padEnd(5)} ${r.suite.padEnd(26)} ${r.count}`);
}
console.log('──────────────────────────────────────────');
console.log(`  Jami: ${total} test, ${failed} ta to'plam xato bilan.`);

process.exitCode = failed > 0 ? 1 : 0;
