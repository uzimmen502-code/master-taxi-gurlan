/**
 * «Бизнес харитаси» (`business_map`) ни ПИЛОТ туманларда ёқиш (эга, 2026-10-23: «қурилмада кўринмаяпти»; 42-банд:
 * OFF → пилот → ҳамма). Админ «Ҳудудлар ва хизматлар» → `adminSaveModuleConfig` (`functions/module_config.js`)
 * билан БИР ХИЛ ёзув: туман ҳужжати (`modules` + `manualModules`) ва `admin_audit` (`module_config_changed`) БИР
 * транзакцияда. Фақат `business_map` катаги; бошқа модулларга тегилмайди.
 *
 * Хавфсизлик (28, 41-банд):
 *   - DRY RUN — стандарт; `--apply` — ёзади.
 *   - Идемпотент: катак аллақачон `enabled` бўлса тегмайди; бошқа ҳолатда (coming_soon/soon/hidden) ҳам фақат шу катак
 *     `enabled` бўлади (аудитда `from` сақланади).
 *   - Орқага қайтариш: админ экранида катакни «Ёпиқ»/«мерос»га қайтариш (ёки `--status=hidden`).
 *
 * Ишлатиш: node functions/tools/enable_business_map.js [--districts=gurlan,urganch_shahri] [--status=enabled] [--apply]
 */
'use strict';

const { currentStatus } = require('../module_config');

const MODULE_ID = 'business_map';
const DEFAULT_DISTRICTS = ['gurlan', 'urganch_shahri'];
const STATUSES = ['enabled', 'coming_soon', 'soon', 'hidden'];

async function enableBusinessMap(db, admin, { districts = DEFAULT_DISTRICTS, status = 'enabled', apply = false, actor = 'script:enable_business_map' } = {}) {
  if (!STATUSES.includes(status)) throw new Error(`status noto'g'ri: ${status}`);
  const ts = admin.firestore.FieldValue.serverTimestamp();
  const out = [];
  for (const id of districts) {
    const geo = await db.collection('geo_districts').doc(id).get();
    if (!geo.exists) { out.push({ district: id, action: 'skip_no_such_district' }); continue; }
    const ref = db.collection('geo_district_modules').doc(id);
    const res = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const cur = snap.exists ? (snap.data() || {}) : {};
      const from = currentStatus(cur, 'district', MODULE_ID);
      if (from === status) return { district: id, action: 'already', from };
      if (!apply) return { district: id, action: 'would_set', from, to: status };
      const manual = new Set((Array.isArray(cur.manualModules) ? cur.manualModules : []).map(String));
      manual.add(MODULE_ID);
      t.set(ref, {
        modules: { [MODULE_ID]: { status } },
        manualModules: [...manual].sort(),
        districtId: id,
        regionId: String(geo.data().regionId || ''),
        updatedAt: ts,
        updatedBy: actor,
      }, { merge: true });
      t.create(db.collection('admin_audit').doc(), {
        kind: 'module_config_changed', actor, actorRole: 'script', scope: 'district', targetId: id,
        changes: [{ moduleId: MODULE_ID, from, to: status }], enforce: null, source: 'script', at: ts,
      });
      return { district: id, action: 'set', from, to: status };
    });
    out.push(res);
  }
  return out;
}

async function main() {
  const admin = require('firebase-admin');
  const path = require('path');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-bm' });
    } else {
      admin.initializeApp({ credential: admin.credential.cert(require(path.join(__dirname, '..', 'service-account.json'))) });
    }
  }
  const arg = (n, d) => ((process.argv.find((a) => a.startsWith(`--${n}=`)) || '').split('=')[1]) || d;
  const districts = arg('districts', DEFAULT_DISTRICTS.join(',')).split(',').map((s) => s.trim()).filter(Boolean);
  const apply = process.argv.includes('--apply');
  console.log(`${apply ? 'APPLY' : 'DRY RUN'} ${MODULE_ID}=${arg('status', 'enabled')} districts=${districts.join(',')}`);
  console.log(JSON.stringify(await enableBusinessMap(admin.firestore(), admin, { districts, status: arg('status', 'enabled'), apply }), null, 2));
  if (!apply) console.log('DRY RUN: ҳеч нарса ёзилмади. Ёзиш учун --apply.');
}

if (require.main === module) {
  main().catch((e) => { console.error(e); process.exit(1); });
}

module.exports = { enableBusinessMap };
