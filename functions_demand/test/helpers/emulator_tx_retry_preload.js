/**
 * `node --require` uchun (functions/test/run_all_suites.js har test faylidan oldin yuklaydi):
 * emulator deadlock artefaktini («Transaction is invalid or closed») ishlab chiqarish SDK kabi qayta
 * uradi. Tafsilot — emulator_hooks.js `installEmulatorClosedTxRetry` (2026-11-28).
 */
'use strict';
require('./emulator_hooks').installEmulatorClosedTxRetry();
