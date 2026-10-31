/**
 * Курьер модулини МФЙ (service_area) даражасида «мерос»га қайтариш (эга, 2026-10-31: «Гурлан маркази ва Урганч
 * шаҳрида курьер атайлаб ёпилганми? — йўқ, буни текшир ва тузат»).
 *
 * Ҳолат (2026-10-31, жонли конфиг ўқилди): `service_area_modules/svc_gurlan_markaz` ва `svc_urganch_shahri` да
 * `courier = hidden` ва `courier` `manualModules` ичида (2026-08-19 дан бери). Туманлар (`gurlan`,
 * `urganch_shahri`) ва `config/module_defaults` да `courier = enabled`. МФЙ override устун бўлгани учун шу
 * махаллалардаги одамлар «＋» да курьер қаторини кўрмайди ва `requestCapability` MODULE_CLOSED қайтаради.
 * Аудит: docs/kuryer_paneli_audit_2026-10-31_uz.md, K-1.
 *
 * Ёзув админ «Ҳудудлар ва хизматлар» → `adminSaveModuleConfig` (`functions/module_config.js`) нинг «мерос»
 * (to: null) шохи билан БИР ХИЛ: `manualModules` дан `courier` чиқади, `modules.courier` ўчирилади, ва
 * `admin_audit` (`module_config_changed`) — ҳаммаси БИР транзакцияда. Бошқа модулларга тегилмайди.
 *
 * Хавфсизлик (28, 41-банд):
 *   - DRY RUN — стандарт; `--apply` — ёзади.
 *   - Идемпотент: `courier` `manualModules` да бўлмаса тегмайди.
 *   - Фақат ҳозирги ҳолат `hidden` бўлса ўзгартиради (бошқа ҳолат — конфликт, тегмайди).
 *   - Backup: ўзгаришдан олдинги ҳужжатлар `functions/tools/backup/` га JSON бўлиб ёзилади.
 *   - Орқага қайтариш: админ экранида шу МФЙ'да курьерни «Ёпиқ» қилиш, ёки backup'даги ҳолат.
 *
 * Ишлатиш: node functions/tools/inherit_courier_mfy.js [--areas=svc_gurlan_markaz,svc_urganch_shahri] [--apply]
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { currentStatus } = require('../module_config');

const MODULE_ID = 'courier';
const DEFAULT_AREAS = ['svc_gurlan_markaz', 'svc_urganch_shahri'];

async function inheritCourierMfy(db, admin, { areas = DEFAULT_AREAS, apply = false, actor = 'script:inherit_courier_mfy', backupDir = null } = {}) {
  const ts = admin.firestore.FieldValue.serverTimestamp();
  const out = [];
  const backup = {};
  for (const id of areas) {
    const ref = db.collection('service_area_modules').doc(id);
    const res = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) return { area: id, action: 'skip_no_doc' };
      const cur = snap.data() || {};
      const manual = new Set((Array.isArray(cur.manualModules) ? cur.manualModules : []).map(String));
      const from = currentStatus(cur, 'area', MODULE_ID);
      if (!manual.has(MODULE_ID)) return { area: id, action: 'already_inherit', from };
      if (from !== 'hidden') return { area: id, action: 'skip_unexpected_status', from };
      backup[id] = cur;
      if (!apply) return { area: id, action: 'would_inherit', from, to: null };
      manual.delete(MODULE_ID);
      t.set(ref, {
        modules: { [MODULE_ID]: admin.firestore.FieldValue.delete() },
        manualModules: [...manual].sort(),
        updatedAt: ts,
        updatedBy: actor,
      }, { merge: true });
      t.create(db.collection('admin_audit').doc(), {
        kind: 'module_config_changed', actor, actorRole: 'script', scope: 'area', targetId: id,
        changes: [{ moduleId: MODULE_ID, from, to: null }], enforce: null, source: 'script', at: ts,
      });
      return { area: id, action: 'inherited', from, to: null };
    });
    out.push(res);
  }
  if (backupDir && Object.keys(backup).length) {
    const file = path.join(backupDir, `courier-mfy-inherit-backup-${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
    fs.writeFileSync(file, JSON.stringify(backup, (k, v) => (v && typeof v.toDate === 'function' ? v.toDate().toISOString() : v), 2));
    out.push({ backup: file });
  }
  return out;
}

async function main() {
  const admin = require('firebase-admin');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-courier-mfy' });
    } else {
      admin.initializeApp({ credential: admin.credential.cert(require(path.join(__dirname, '..', 'service-account.json'))) });
    }
  }
  const arg = (n, d) => ((process.argv.find((a) => a.startsWith(`--${n}=`)) || '').split('=')[1]) || d;
  const areas = arg('areas', DEFAULT_AREAS.join(',')).split(',').map((s) => s.trim()).filter(Boolean);
  const apply = process.argv.includes('--apply');
  console.log(`${apply ? 'APPLY' : 'DRY RUN'} ${MODULE_ID} -> inherit, areas=${areas.join(',')}`);
  const res = await inheritCourierMfy(admin.firestore(), admin, {
    areas, apply, backupDir: path.join(__dirname, 'backup'),
  });
  console.log(JSON.stringify(res, null, 2));
  if (!apply) console.log('DRY RUN: ҳеч нарса ёзилмади. Ёзиш учун --apply.');
}

if (require.main === module) {
  main().catch((e) => { console.error(e); process.exit(1); });
}

module.exports = { inheritCourierMfy };
