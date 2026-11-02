/**
 * Рағбат занжирини ишга тушириш (эга 2026-11-03: «занжирнинг бу учини охиригача етказиб бажар»):
 *   1. Иккита дастур — `incentive_programs/{key}`, босқич ICHKI SINOV (`internal`): фақат `internalPhones`
 *      даги рақамлар олади, бошқа ҳеч кимга бонус берилмайди. Ёзув шакли `adminUpsertIncentiveProgram`
 *      (incentives.js) билан БИР ХИЛ: `validateProgram` + counters + `admin_audit` бир транзакцияда.
 *      Мавжуд бўлса — ТЕГИЛМАЙДИ (идемпотент; таҳрир — админ экранида).
 *   2. «Менинг машинам» (`tire`) модули — `--tire-districts` даги туманларда (стандарт: пилот Гурлан, Урганч ш.)
 *      `enabled`; ёзув `enable_business_map.js` / `adminSaveModuleConfig` билан бир хил (+ admin_audit).
 *
 * Параметрлар (сумма, улуш %, муддат, бюджет, туркумлар) — PROPOSED, эга тасдиқлагунча фақат ички синов.
 *
 *   node functions/tools/setup_incentive_programs.js --internal-suffix=8777            (DRY RUN)
 *   node functions/tools/setup_incentive_programs.js --internal-suffix=8777 --apply
 * Орқага: админ экранида босқични «Ўчиқ» (off) қилиш; модулни «Ҳудудлар ва хизматлар»да «Ёпиқ».
 * Логда телефон тўлиқ чиқмайди (40-банд).
 */
'use strict';

const path = require('path');
const { validateProgram } = require('../incentives');
const { currentStatus } = require('../module_config');

const APPLY = process.argv.includes('--apply');
const arg = (n, d) => ((process.argv.find((a) => a.startsWith(`--${n}=`)) || '').split('=')[1]) || d;
const ACTOR = 'script:setup_incentive_programs';
const mask = (p) => (p ? `***${String(p).slice(-4)}` : '');

/** PROPOSED (эга 2026-11-03 тасдиқлагунча). newUsersSince — шу скрипт ишлаган пайт (фақат янгилар, 8-қарор). */
function proposedPrograms(nowMs, internalPhones) {
  const base = { stage: 'internal', internalPhones, pilotDistrictIds: [] };
  return [
    {
      ...base,
      key: 'women_100k',
      title: {
        uz_Cyrl: 'Аёллар учун 100 000 сўм совға',
        uz_Latn: "Ayollar uchun 100 000 so'm sovg'a",
        ru: 'Подарок 100 000 сум для женщин',
      },
      audience: { gender: 'female', ageMin: 15, ageMax: 60, requireCar: false, newUsersSince: nowMs },
      amount: 100000,
      buckets: [],
      maxOrderSharePct: 50,
      validityDays: 30,
      budgetTotal: 10000000,
      budgetDaily: 1000000,
    },
    {
      ...base,
      key: 'car_200k',
      title: {
        uz_Cyrl: 'Машина эгалари учун 200 000 сўм',
        uz_Latn: "Mashina egalari uchun 200 000 so'm",
        ru: '200 000 сум владельцам автомобилей',
      },
      audience: { gender: 'any', ageMin: 0, ageMax: 120, requireCar: true, newUsersSince: nowMs },
      amount: 200000,
      buckets: [
        { category: 'tire', amount: 100000 },
        { category: 'oil', amount: 50000 },
        { category: 'battery', amount: 50000 },
      ],
      maxOrderSharePct: 50,
      validityDays: 60,
      budgetTotal: 20000000,
      budgetDaily: 2000000,
    },
  ];
}

async function createProgram(db, admin, input) {
  const clean = validateProgram(input);
  const { Timestamp, FieldValue } = admin.firestore;
  const ts = FieldValue.serverTimestamp();
  const ref = db.collection('incentive_programs').doc(clean.key);
  return db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (snap.exists) return { programId: ref.id, action: 'exists_untouched', stage: snap.data().stage };
    if (!APPLY) return { programId: ref.id, action: 'would_create', stage: clean.stage, amount: clean.amount };
    t.create(ref, {
      key: clean.key, title: clean.title, stage: clean.stage,
      internalPhones: clean.internalPhones, pilotDistrictIds: clean.pilotDistrictIds,
      audience: {
        gender: clean.audience.gender, ageMin: clean.audience.ageMin, ageMax: clean.audience.ageMax,
        requireCar: clean.audience.requireCar, newUsersSince: Timestamp.fromMillis(clean.audience.newUsersSinceMs),
      },
      amount: clean.amount, buckets: clean.buckets, maxOrderSharePct: clean.maxOrderSharePct,
      validityDays: clean.validityDays, budgetTotal: clean.budgetTotal, budgetDaily: clean.budgetDaily,
      startAt: null, endAt: null, updatedAt: ts, updatedBy: ACTOR,
      version: 1, createdAt: ts, createdBy: ACTOR,
      counters: { grantedAmount: 0, grantedCount: 0, spentAmount: 0, expiredAmount: 0, revokedAmount: 0 },
    });
    t.create(db.collection('admin_audit').doc(), {
      action: 'incentiveProgramCreate', programId: ref.id, actor: ACTOR, stage: clean.stage,
      amount: clean.amount, budgetTotal: clean.budgetTotal, at: ts,
    });
    return { programId: ref.id, action: 'created', stage: clean.stage, amount: clean.amount };
  });
}

async function enableModuleInDistrict(db, admin, moduleId, districtId) {
  const ts = admin.firestore.FieldValue.serverTimestamp();
  const geo = await db.collection('geo_districts').doc(districtId).get();
  if (!geo.exists) return { district: districtId, action: 'skip_no_such_district' };
  const ref = db.collection('geo_district_modules').doc(districtId);
  return db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    const cur = snap.exists ? (snap.data() || {}) : {};
    const from = currentStatus(cur, 'district', moduleId);
    if (from === 'enabled') return { district: districtId, action: 'already' };
    if (!APPLY) return { district: districtId, action: 'would_set', from, to: 'enabled' };
    const manual = new Set((Array.isArray(cur.manualModules) ? cur.manualModules : []).map(String));
    manual.add(moduleId);
    t.set(ref, {
      modules: { [moduleId]: { status: 'enabled' } },
      manualModules: [...manual].sort(),
      districtId,
      regionId: String(geo.data().regionId || ''),
      updatedAt: ts,
      updatedBy: ACTOR,
    }, { merge: true });
    t.create(db.collection('admin_audit').doc(), {
      kind: 'module_config_changed', actor: ACTOR, actorRole: 'script', scope: 'district', targetId: districtId,
      changes: [{ moduleId, from, to: 'enabled' }], enforce: null, source: 'script', at: ts,
    });
    return { district: districtId, action: 'set', from, to: 'enabled' };
  });
}

async function main() {
  const admin = require('firebase-admin');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-inc' });
    else admin.initializeApp({ credential: admin.credential.cert(require(arg('sa', path.join(__dirname, '..', 'service-account.json')))) });
  }
  const db = admin.firestore();
  const suffix = arg('internal-suffix', '');
  if (!/^\d{4}$/.test(suffix)) throw new Error('--internal-suffix=<4 рақам> керак (ички синовчи админ)');
  const admins = await db.collection('users').where('role', 'in', ['admin', 'superadmin']).get();
  const hits = admins.docs.map((d) => d.id).filter((id) => /^998\d{9}$/.test(id) && id.endsWith(suffix));
  if (hits.length !== 1) throw new Error(`ички синовчи топилмади ёки бир нечта: ${hits.length}`);
  console.log(`${APPLY ? 'APPLY' : 'DRY RUN'} internal=${mask(hits[0])}`);

  for (const p of proposedPrograms(Date.now(), hits)) console.log(JSON.stringify(await createProgram(db, admin, p)));
  const districts = arg('tire-districts', 'gurlan,urganch_shahri').split(',').map((s) => s.trim()).filter(Boolean);
  for (const d of districts) console.log(JSON.stringify(await enableModuleInDistrict(db, admin, 'tire', d)));
  if (!APPLY) console.log('DRY RUN: ҳеч нарса ёзилмади. Ёзиш учун --apply.');
}

if (require.main === module) main().catch((e) => { console.error(e.message || e); process.exit(1); });

module.exports = { proposedPrograms };
