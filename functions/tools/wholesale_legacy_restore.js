#!/usr/bin/env node
/**
 * `wholesaleLegacyCleanup` яширган Улгуржи товарларини қайтариш (rollback).
 *
 *   node functions/tools/wholesale_legacy_restore.js              # DRY-RUN (фақат ўқийди)
 *   node functions/tools/wholesale_legacy_restore.js --apply      # қайтаради
 *   node functions/tools/wholesale_legacy_restore.js --apply --ids a,b   # фақат шулар
 *
 * Қайтарилади: тозалаш яширган ва ҳали шу ҳолатда турган товарлар
 * (`legacyArchived`, `status: inactive`, `adminNote: legacy_test_cleanup`) —
 * аввалги `status`/`adminNote` (`legacyPrev*`). `legacyArchived` белгиси
 * қолади: товар «ишланган» ҳисобланади, тозалаш уни қайта яширмайди.
 * Тозалашни бутунлай тўхтатиш — функцияни ўчириш (README).
 * Audit: `admin_audit` (`kind: wholesale_legacy_restore`).
 */
'use strict';

const { restoreLegacyArchived } = require('../wholesale_geo');

if (require.main === module) {
  const fs = require('fs');
  const path = require('path');
  const admin = require('firebase-admin');
  const args = process.argv.slice(2);
  const APPLY = args.includes('--apply');
  const idsArg = args.includes('--ids') ? args[args.indexOf('--ids') + 1] : '';
  const ids = idsArg ? idsArg.split(',').map((s) => s.trim()).filter(Boolean) : null;

  if (process.env.FIRESTORE_EMULATOR_HOST) {
    admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-wholesale-restore' });
  } else {
    const keyPath = path.join(__dirname, '..', 'service-account.json');
    if (!fs.existsSync(keyPath)) {
      console.error('service-account.json topilmadi:', keyPath);
      process.exit(1);
    }
    admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
  }
  const db = admin.firestore();
  restoreLegacyArchived(db, admin, { apply: APPLY, ids, actor: 'tool:wholesale_legacy_restore' })
    .then((r) => {
      console.log(JSON.stringify({ mode: APPLY ? 'APPLY' : 'DRY-RUN', candidates: r.candidates.length, restored: r.restored, ids: r.candidates }, null, 2));
      process.exit(0);
    })
    .catch((e) => { console.error('ERR', e.message); process.exit(1); });
}
