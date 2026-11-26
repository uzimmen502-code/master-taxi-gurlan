/**
 * «Туғилган кун ва байрам саватчаси» — бошланғич holiday_occasions (4) ва holiday_baskets (12), ҳаммаси stage=off (эга 2026-11-26).
 * Таркиб — PROPOSED (tools/data/holiday_seed_v1.json); ўзгартириш — админ callable'лари (adminUpsertHolidayOccasion/Basket).
 *
 * Хавфсизлик (27, 28, 41-банд): DRY RUN — сукут; лойиҳа ФАҚАТ `--project <id>` билан; `--apply` фақат ЙЎҚ ҳужжатни яратади
 * (бор бўлса тегилмайди), ҳар яратилган ҳужжатга admin_audit. Текширув — holiday.js валидаторлари (callable билан бир хил),
 * сават гуруҳлари — жорий taxonomy/supermarket бўйича.
 *
 *   node functions/tools/seed_holiday.js                          # офлайн текширув (таксономия — tools/data/supermarket_taxonomy_v2.json)
 *   node functions/tools/seed_holiday.js --project <id>           # DRY RUN
 *   node functions/tools/seed_holiday.js --project <id> --apply
 */
'use strict';

const path = require('path');
const fs = require('fs');
const h = require('../holiday');
const sm = require('../supermarket');

const SEED = path.join(__dirname, 'data', 'holiday_seed_v1.json');
const ACTOR = 'seed:holiday_v1';

function groupsOf(tax) {
  const g = {};
  for (const c of (tax.categories || [])) for (const x of (c.groups || [])) g[x.id] = true;
  return g;
}
function check(seed, groups) {
  const errors = [];
  for (const o of seed.occasions) { const v = h.validateOccasion(o); if (!v.ok) errors.push(`occasion ${o.id}: ${v.errors.join(', ')}`); }
  const occIds = new Set(seed.occasions.map((o) => o.id));
  for (const b of seed.baskets) {
    const v = h.validateBasket(b, groups);
    if (!v.ok) errors.push(`basket ${b.id}: ${v.errors.join(', ')}`);
    if (!occIds.has(b.occasionId)) errors.push(`basket ${b.id}: OCCASION_UNKNOWN`);
  }
  return errors;
}

async function main() {
  const argv = process.argv.slice(2);
  const pi = argv.indexOf('--project');
  const project = pi >= 0 ? argv[pi + 1] : null;
  const apply = argv.includes('--apply');
  const seed = sm.trimDeep(JSON.parse(fs.readFileSync(SEED, 'utf8')));
  if (!project) {
    const tax = JSON.parse(fs.readFileSync(path.join(__dirname, 'data', 'supermarket_taxonomy_v2.json'), 'utf8'));
    const errors = check(seed, groupsOf(tax));
    console.log(errors.length ? `OFFLINE FAIL\n${errors.join('\n')}` : `OFFLINE OK: ${seed.occasions.length} occasions, ${seed.baskets.length} baskets`);
    process.exit(errors.length ? 1 : 0);
  }
  const admin = require('firebase-admin');
  admin.initializeApp({ projectId: project });
  const db = admin.firestore();
  const ts = admin.firestore.FieldValue.serverTimestamp();
  const taxSnap = await db.doc(sm.TAXONOMY_DOC.join('/')).get();
  if (!taxSnap.exists) throw new Error('taxonomy/supermarket йўқ — аввал seed_supermarket');
  const errors = check(seed, groupsOf(taxSnap.data()));
  if (errors.length) { console.log(`FAIL\n${errors.join('\n')}`); process.exit(1); }
  const plan = [];
  for (const o of seed.occasions) {
    const clean = h.normalizeOccasion(o);
    plan.push({ path: `${h.OCCASIONS}/${o.id}`, data: { ...clean, visible: clean.stage === 'public', version: 1, updatedBy: ACTOR } });
  }
  const stageOf = Object.fromEntries(seed.occasions.map((o) => [o.id, o.stage]));
  for (const b of seed.baskets) {
    plan.push({ path: `${h.BASKETS}/${b.id}`, data: { ...b, visible: b.active === true && stageOf[b.occasionId] === 'public', version: 1, updatedBy: ACTOR } });
  }
  let created = 0;
  for (const p of plan) {
    const ref = db.doc(p.path);
    const exists = (await ref.get()).exists;
    console.log(`${exists ? 'SKIP (бор)' : (apply ? 'CREATE' : 'WOULD CREATE')} ${p.path}`);
    if (exists || !apply) continue;
    await db.runTransaction(async (t) => {
      if ((await t.get(ref)).exists) return;
      t.create(ref, { ...p.data, createdAt: ts, updatedAt: ts });
      t.create(db.collection('admin_audit').doc(), {
        kind: p.path.startsWith(h.OCCASIONS) ? 'holiday_occasion_set' : 'holiday_basket_set', actor: ACTOR,
        target: `${p.path} v1`, before: null, after: p.data, reason: 'seed holiday_seed_v1', at: ts,
      });
    });
    created += 1;
  }
  console.log(`${apply ? 'APPLIED' : 'DRY RUN'}: ${plan.length} docs, created ${created}`);
}

main().catch((e) => { console.error(e.message || e); process.exit(1); });
