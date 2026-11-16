/**
 * «Бозорлар» — `taxonomy/markets` бошланғич мазмуни (v1, эга 2026-11-15).
 *
 * Манба: `tools/data/market_taxonomy_v1.json`. Текширув — `validateMarketTaxonomy` (callable билан бир хил);
 * ёзиладиган ҳужжатлар — `buildVersionDocs` (callable билан бир хил шакл: ҳужжат + `taxonomy_history/v1` + `admin_audit`).
 *
 * Хавфсизлик (28, 41-банд):
 *   - DRY RUN — сукут: JSON текширилади ва нима ёзилиши чиқади, ҳеч нарса ёзилмайди.
 *   - Лойиҳа ФАҚАТ `--project <id>` билан (сукут йўқ — prod'га адашиб ёзилмасин). `--project`сиз — офлайн текширув.
 *   - `--apply`: ФАҚАТ `taxonomy/markets` ҳали ЙЎҚ бўлса яратади (v1); бор бўлса тўхтайди — ўзгартириш учун
 *     `adminSetMarketTaxonomy` (версия қулфи + аудит).
 *   - Audit: actor = `seed`.
 *
 * Ишлатиш:
 *   node functions/tools/seed_market_taxonomy.js                         # офлайн DRY RUN
 *   node functions/tools/seed_market_taxonomy.js --project <id>          # DRY RUN + ҳужжат борлигини ўқийди
 *   node functions/tools/seed_market_taxonomy.js --project <id> --apply  # яратади (фақат ҳужжат йўқ бўлса)
 *   Эмулятор: FIRESTORE_EMULATOR_HOST=127.0.0.1:<port> ... --project demo-xxx [--apply]
 */
'use strict';

const fs = require('fs');
const path = require('path');
const {
  validateMarketTaxonomy, normalizeTaxonomy, buildVersionDocs, TAXONOMY_DOC, HISTORY_COLLECTION,
} = require('../market_taxonomy');

const DATA_FILE = path.join(__dirname, 'data', 'market_taxonomy_v1.json');
const ACTOR = 'seed';

function parseArgs(argv) {
  const out = { apply: argv.includes('--apply'), project: null, file: DATA_FILE };
  const pi = argv.indexOf('--project');
  if (pi >= 0) out.project = argv[pi + 1] && !argv[pi + 1].startsWith('--') ? argv[pi + 1] : '';
  const fi = argv.indexOf('--file');
  if (fi >= 0 && argv[fi + 1]) out.file = path.resolve(argv[fi + 1]);
  return out;
}

function loadTaxonomy(file) {
  const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
  return normalizeTaxonomy(raw);
}

function summarize(taxonomy) {
  return Object.entries(taxonomy.markets).map(([id, m]) => ({
    id,
    moduleId: m.moduleId,
    order: m.order,
    name: m.names.uz_Cyrl,
    categories: m.categories.map((c) => `${c.id}${c.orderable ? '*' : ''}`).join(','),
    fields: m.fields.map((f) => `${f.key}:${f.type}`).join(','),
    priceUnits: m.priceUnits.map((u) => (u === '' ? "''" : u)).join(','),
  }));
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const taxonomy = loadTaxonomy(args.file);
  const v = validateMarketTaxonomy(taxonomy);
  console.log(`Fayl: ${args.file}`);
  if (!v.ok) {
    console.error('TAXONOMY_INVALID:');
    for (const e of v.errors) console.error(`  ${e}`);
    process.exit(1);
  }
  console.log('Tekshiruv: OK');
  console.table(summarize(taxonomy));
  console.log(`Yoziladi: ${TAXONOMY_DOC.join('/')} (version 1), ${HISTORY_COLLECTION}/v1, admin_audit (actor '${ACTOR}')`);

  if (args.project === '') throw new Error('--project qiymati berilmadi');
  if (args.apply && !args.project) throw new Error('--apply faqat --project <id> bilan');
  if (!args.project) { console.log('DRY RUN (oflayn) — Firestore\'ga ulanmadi.'); return; }

  // ADC йўқ машинада: GCLOUD_ACCESS_TOKEN (`gcloud auth print-access-token`) → Firestore REST commit
  // (exists=false шартлари билан, атомар). Токен лог'га чиқмайди.
  if (!process.env.FIRESTORE_EMULATOR_HOST && process.env.GCLOUD_ACCESS_TOKEN) {
    await restSeed(args, taxonomy, process.env.GCLOUD_ACCESS_TOKEN);
    return;
  }
  const admin = require('firebase-admin');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) admin.initializeApp({ projectId: args.project });
    else admin.initializeApp({ projectId: args.project, credential: admin.credential.applicationDefault() });
  }
  const db = admin.firestore();
  const target = process.env.FIRESTORE_EMULATOR_HOST ? `emulator ${process.env.FIRESTORE_EMULATOR_HOST}` : 'PRODUCTION API';
  console.log(`${args.apply ? 'APPLY' : 'DRY RUN'} — loyiha ${args.project} (${target})`);

  const ref = db.collection(TAXONOMY_DOC[0]).doc(TAXONOMY_DOC[1]);
  const snap = await ref.get();
  if (snap.exists) {
    console.log(`Hujjat BOR (version ${(snap.data() || {}).version}) — tegilmaydi. O'zgartirish: adminSetMarketTaxonomy.`);
    process.exitCode = args.apply ? 1 : 0;
    return;
  }
  if (!args.apply) { console.log('Hujjat yo\'q — --apply bilan v1 yaratiladi.'); return; }

  const ts = admin.firestore.FieldValue.serverTimestamp();
  await db.runTransaction(async (t) => {
    const again = await t.get(ref);
    if (again.exists) throw new Error('Hujjat parallel yaratildi — to\'xtadi');
    const docs = buildVersionDocs({ markets: taxonomy.markets, version: 1, previousVersion: null, actor: ACTOR, ts });
    t.create(ref, docs.doc);
    t.create(db.collection(HISTORY_COLLECTION).doc('v1'), docs.history);
    t.set(db.collection('admin_audit').doc(), docs.audit);
  });
  console.log('YARATILDI: taxonomy/markets v1');
}

// JS қиймат → Firestore REST Value (сонлар фақат бутун — таксономияда каср йўқ).
function toValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') {
    if (!Number.isInteger(v)) throw new Error(`Kasr son taxonomy'da kutilmagan: ${v}`);
    return { integerValue: String(v) };
  }
  if (typeof v === 'string') return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toValue) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, toValue(x)])) } };
}

async function restSeed(args, taxonomy, token) {
  const base = `https://firestore.googleapis.com/v1/projects/${args.project}/databases/(default)/documents`;
  const headers = { Authorization: `Bearer ${token}`, 'x-goog-user-project': args.project, 'Content-Type': 'application/json' };
  console.log(`${args.apply ? 'APPLY' : 'DRY RUN'} — loyiha ${args.project} (PRODUCTION REST)`);
  const cur = await fetch(`${base}/${TAXONOMY_DOC.join('/')}`, { headers });
  if (cur.status === 200) {
    const d = await cur.json();
    console.log(`Hujjat BOR (version ${d.fields && d.fields.version && d.fields.version.integerValue}) — tegilmaydi.`);
    process.exitCode = args.apply ? 1 : 0;
    return;
  }
  if (cur.status !== 404) throw new Error(`O'qish xatosi HTTP ${cur.status}`);
  if (!args.apply) { console.log('Hujjat yo\'q — --apply bilan v1 yaratiladi.'); return; }
  const docs = buildVersionDocs({ markets: taxonomy.markets, version: 1, previousVersion: null, actor: ACTOR, ts: null });
  const name = (p) => `projects/${args.project}/databases/(default)/documents/${p}`;
  const strip = (o, k) => Object.fromEntries(Object.entries(o).filter(([key]) => key !== k));
  const write = (path, obj, tsField, mustNotExist) => ({
    update: { name: name(path), fields: toValue(strip(obj, tsField)).mapValue.fields },
    updateTransforms: [{ fieldPath: tsField, setToServerValue: 'REQUEST_TIME' }],
    ...(mustNotExist ? { currentDocument: { exists: false } } : {}),
  });
  const auditId = `market_taxonomy_seed_v1`;
  const body = {
    writes: [
      write(TAXONOMY_DOC.join('/'), docs.doc, 'updatedAt', true),
      write(`${HISTORY_COLLECTION}/v1`, docs.history, 'updatedAt', true),
      write(`admin_audit/${auditId}`, docs.audit, 'at', true),
    ],
  };
  const res = await fetch(`${base}:commit`, { method: 'POST', headers, body: JSON.stringify(body) });
  if (res.status !== 200) throw new Error(`Commit xatosi HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
  console.log('YARATILDI: taxonomy/markets v1 (+ taxonomy_history/v1, admin_audit/' + auditId + ')');
}

if (require.main === module) {
  main().catch((e) => { console.error(e.message || e); process.exit(1); });
}

module.exports = { parseArgs, loadTaxonomy, summarize, toValue, DATA_FILE };
