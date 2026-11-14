#!/usr/bin/env node
/**
 * `geo_regions` / `geo_districts` ҳужжатларига РУСЧА ном ёзиш:
 * `nameRu` (тўлиқ) ва `nameRuShort` (қисқа, сарлавҳа/чип учун).
 * Манба: `data/geo_names_ru.js` (PROPOSED — ёзишдан олдин эга кўриб чиқади).
 *
 * ХАВФСИЗ:
 *   - сукут бўйича DRY RUN — ҳеч нарса ёзмайди, фақат режани кўрсатади;
 *   - фақат шу икки майдон (+ updatedAt/updatedBy) ёзилади;
 *   - фақат МАВЖУД ҳужжат янгиланади (`update`) — янги ҳужжат яратилмайди;
 *   - майдонда аллақачон бошқа қиймат бўлса (масалан, қўлда тузатилган) —
 *     ТЕГИЛМАЙДИ, рўйхатда кўрсатилади (`--overwrite` билангина алмашади);
 *   - `--apply` олдидан эски қийматлар JSON'га сақланади → `--rollback`.
 *
 * Ишлатиш:
 *   node functions/tools/backfill-geo-name-ru.js                  # dry run
 *   node functions/tools/backfill-geo-name-ru.js --apply          # ёзиш
 *   node functions/tools/backfill-geo-name-ru.js --rollback <file.json>
 */
const fs = require('fs');
const path = require('path');
const {
  REGIONS_RU,
  DISTRICTS_RU,
  REGIONS_RU_SHORT,
  DISTRICTS_RU_SHORT,
} = require('./data/geo_names_ru');

const BY = 'backfill-geo-name-ru';
const FIELDS = ['nameRu', 'nameRuShort'];

/**
 * Соф режа (тест қилинади). [docs] — `{collection, id, nameRu, nameRuShort}`.
 * Қайтаради: ёзиладиганлар (`data` — фақат ўзгарадиган майдонлар,
 * `before` — уларнинг эски қиймати ёки `null`), тегилмайдиганлар,
 * номсиз ҳужжатлар, ҳужжатсиз номлар.
 */
function planNameRu(docs, { overwrite = false } = {}) {
  const maps = {
    geo_regions: { nameRu: REGIONS_RU, nameRuShort: REGIONS_RU_SHORT },
    geo_districts: { nameRu: DISTRICTS_RU, nameRuShort: DISTRICTS_RU_SHORT },
  };
  const writes = [];
  const conflicts = [];
  const missingName = [];
  const seen = { geo_regions: new Set(), geo_districts: new Set() };
  for (const d of docs) {
    const m = maps[d.collection];
    if (!m) continue;
    seen[d.collection].add(d.id);
    const docPath = `${d.collection}/${d.id}`;
    if (!m.nameRu[d.id]) {
      missingName.push(docPath);
      continue;
    }
    const data = {};
    const before = {};
    for (const f of FIELDS) {
      const want = m[f][d.id];
      if (!want) continue;
      const have = typeof d[f] === 'string' ? d[f].trim() : '';
      if (have === want) continue;
      if (have && !overwrite) {
        conflicts.push({ path: docPath, field: f, have, want });
        continue;
      }
      data[f] = want;
      before[f] = have || null;
    }
    if (Object.keys(data).length) writes.push({ path: docPath, before, data });
  }
  const missingDoc = [];
  for (const [col, m] of Object.entries(maps)) {
    for (const id of Object.keys(m.nameRu)) {
      if (!seen[col].has(id)) missingDoc.push(`${col}/${id}`);
    }
  }
  return { writes, conflicts, missingName, missingDoc };
}

async function main() {
  const admin = require('firebase-admin');
  const keyPath = path.join(__dirname, '..', 'service-account.json');
  if (!fs.existsSync(keyPath)) {
    console.error('service-account.json topilmadi:', keyPath);
    process.exit(1);
  }
  admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
  const db = admin.firestore();
  db.settings({ preferRest: true });
  const now = admin.firestore.FieldValue.serverTimestamp();

  const argv = process.argv.slice(2);
  const rbIdx = argv.indexOf('--rollback');
  if (rbIdx >= 0) {
    const file = argv[rbIdx + 1];
    const backup = JSON.parse(fs.readFileSync(file, 'utf8'));
    console.log(`Rollback: ${backup.writes.length} ta hujjat (${file})`);
    for (const w of backup.writes) {
      const patch = { updatedAt: now, updatedBy: `${BY}-rollback` };
      for (const [f, v] of Object.entries(w.before)) {
        patch[f] = v == null ? admin.firestore.FieldValue.delete() : v;
      }
      await db.doc(w.path).update(patch);
      console.log('  ↺', w.path);
    }
    console.log('✅ Rollback tugadi.');
    return;
  }

  const APPLY = argv.includes('--apply');
  const OVERWRITE = argv.includes('--overwrite');

  const docs = [];
  for (const col of ['geo_regions', 'geo_districts']) {
    const snap = await db.collection(col).get();
    snap.forEach((s) => {
      const x = s.data() || {};
      docs.push({ collection: col, id: s.id, nameRu: x.nameRu, nameRuShort: x.nameRuShort });
    });
  }
  const plan = planNameRu(docs, { overwrite: OVERWRITE });

  console.log(`Hujjatlar: ${docs.length}; yoziladi: ${plan.writes.length}${APPLY ? '' : ' — DRY RUN'}`);
  for (const w of plan.writes) {
    const parts = Object.keys(w.data).map((f) => `${f}: ${w.before[f] ?? '∅'} → ${w.data[f]}`);
    console.log(`  • ${w.path}: ${parts.join('; ')}`);
  }
  if (plan.conflicts.length) {
    console.log(`Tegilmaydi (qiymat boshqa, --overwrite yo'q): ${plan.conflicts.length}`);
    for (const c of plan.conflicts) console.log(`  ! ${c.path} ${c.field}: «${c.have}» (taklif: «${c.want}»)`);
  }
  if (plan.missingName.length) {
    console.log(`Ruscha nomi yo'q hujjatlar (ilova kirillni ko'rsatadi): ${plan.missingName.length}`);
    for (const p of plan.missingName) console.log('  ?', p);
  }
  if (plan.missingDoc.length) {
    console.log(`Bazada yo'q ID'lar (yozilmaydi): ${plan.missingDoc.length}`);
    for (const p of plan.missingDoc) console.log('  -', p);
  }

  if (!APPLY) {
    console.log('DRY: hech narsa yozilmadi.');
    return;
  }
  if (!plan.writes.length) {
    console.log('Yoziladigan narsa yo\'q.');
    return;
  }

  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupFile = path.join(__dirname, `geo-name-ru-backup-${stamp}.json`);
  fs.writeFileSync(backupFile, JSON.stringify({ createdAt: stamp, writes: plan.writes }, null, 2));
  console.log('Zaxira (rollback uchun):', backupFile);

  for (let i = 0; i < plan.writes.length; i += 400) {
    const batch = db.batch();
    for (const w of plan.writes.slice(i, i + 400)) {
      batch.update(db.doc(w.path), { ...w.data, updatedAt: now, updatedBy: BY });
    }
    await batch.commit();
    console.log(`  ✓ ${Math.min(i + 400, plan.writes.length)}/${plan.writes.length}`);
  }

  // Tekshirish: yozilganlarni qayta o'qish.
  let bad = 0;
  for (const w of plan.writes) {
    const x = (await db.doc(w.path).get()).data() || {};
    if (Object.entries(w.data).some(([f, v]) => x[f] !== v)) {
      bad++;
      console.log('  ✗', w.path);
    }
  }
  console.log(bad ? `⚠ ${bad} ta hujjat mos emas` : '✅ Hammasi yozildi va tekshirildi.');
}

module.exports = { planNameRu };

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((e) => {
      console.error('Xato:', e.message || e);
      process.exit(1);
    });
}
