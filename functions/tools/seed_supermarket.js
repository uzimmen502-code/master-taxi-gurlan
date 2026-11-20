/**
 * «AVA Супермаркет» — бошланғич `taxonomy/supermarket` (v1, 9 бўлим / 90 гуруҳ) ва `settings/supermarket` (v1).
 *
 * Текширув — `supermarket.js` даги validateSupermarketTaxonomy / validateSupermarketSettings (callable билан бир хил);
 * ёзиладиган шакл — buildTaxonomyVersionDocs (ҳужжат + taxonomy_history/supermarket_v1 + admin_audit).
 *
 * Хавфсизлик (28, 41-банд):
 *   - DRY RUN — сукут. Лойиҳа ФАҚАТ `--project <id>` билан.
 *   - `--apply` ФАҚАТ ҳужжат ЙЎҚ бўлса яратади (exists=false). Бор бўлса тегилмайди — ўзгартириш:
 *     adminSetSupermarketTaxonomy / adminSetSupermarketSettings (версия қулфи + аудит).
 *   - `--only taxonomy|settings` — фақат биттаси.
 *
 *   node functions/tools/seed_supermarket.js                                   # офлайн текширув
 *   node functions/tools/seed_supermarket.js --project <id>                    # DRY RUN (бор/йўқ ўқийди)
 *   node functions/tools/seed_supermarket.js --project <id> --apply [--only taxonomy]
 *   Prod ADC йўқ бўлса: $env:GCLOUD_ACCESS_TOKEN = (gcloud auth print-access-token)  → REST commit.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const sm = require('../supermarket');

const TAX_FILE = path.join(__dirname, 'data', 'supermarket_taxonomy_v1.json');
const SET_FILE = path.join(__dirname, 'data', 'supermarket_settings_v1.json');
const ACTOR = 'seed';

function parseArgs(argv) {
  const out = { apply: argv.includes('--apply'), project: null, only: null, taxFile: TAX_FILE, setFile: SET_FILE };
  const val = (flag) => { const i = argv.indexOf(flag); return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : (i >= 0 ? '' : null); };
  out.project = val('--project');
  out.only = val('--only');
  const tf = val('--taxonomy-file'); if (tf) out.taxFile = path.resolve(tf);
  const sf = val('--settings-file'); if (sf) out.setFile = path.resolve(sf);
  return out;
}

function load(args) {
  const taxonomy = sm.trimDeep(JSON.parse(fs.readFileSync(args.taxFile, 'utf8')));
  const settings = sm.trimDeep(JSON.parse(fs.readFileSync(args.setFile, 'utf8')));
  return { taxonomy, settings };
}

function plan(args, { taxonomy, settings }) {
  const docs = [];
  if (args.only !== 'settings') {
    const v = sm.buildTaxonomyVersionDocs({ categories: taxonomy.categories, version: 1, previousVersion: null, actor: ACTOR, ts: null });
    docs.push({ path: sm.TAXONOMY_DOC.join('/'), data: v.doc, tsField: 'updatedAt', guard: true });
    docs.push({ path: `${sm.HISTORY_COLLECTION}/${sm.HISTORY_PREFIX}1`, data: v.history, tsField: 'updatedAt', guard: true });
    docs.push({ path: 'admin_audit/supermarket_taxonomy_seed_v1', data: v.audit, tsField: 'at', guard: true });
  }
  if (args.only !== 'taxonomy') {
    docs.push({ path: sm.SETTINGS_DOC.join('/'), data: { ...settings, version: 1, updatedAt: null, updatedBy: ACTOR }, tsField: 'updatedAt', guard: true });
    docs.push({
      path: 'admin_audit/supermarket_settings_seed_v1',
      data: { kind: 'supermarket_settings_set', actor: ACTOR, target: 'settings/supermarket v1', version: 1, before: null, after: settings, reason: 'seed', at: null },
      tsField: 'at', guard: true,
    });
  }
  return docs;
}

function toValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === 'string') return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toValue) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, toValue(x)])) } };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const data = load(args);
  const tv = sm.validateSupermarketTaxonomy(data.taxonomy);
  const sv = sm.validateSupermarketSettings(data.settings);
  if (!tv.ok || !sv.ok) {
    for (const e of [...tv.errors, ...sv.errors]) console.error(`  ${e}`);
    process.exit(1);
  }
  const groups = data.taxonomy.categories.reduce((n, c) => n + c.groups.length, 0);
  console.log(`Tekshiruv OK: ${data.taxonomy.categories.length} bo'lim / ${groups} guruh; settings stage=${data.settings.stage} districts=${data.settings.districtIds.join(',')}`);
  const docs = plan(args, data);
  console.log('Yoziladi (faqat yo\'q bo\'lsa):', docs.map((d) => d.path).join(', '));
  if (args.project === '') throw new Error('--project qiymati berilmadi');
  if (args.apply && !args.project) throw new Error('--apply faqat --project <id> bilan');
  if (!args.project) { console.log('DRY RUN (oflayn).'); return; }

  if (!process.env.FIRESTORE_EMULATOR_HOST && process.env.GCLOUD_ACCESS_TOKEN) return restSeed(args, docs, process.env.GCLOUD_ACCESS_TOKEN);
  const admin = require('firebase-admin');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) admin.initializeApp({ projectId: args.project });
    else admin.initializeApp({ projectId: args.project, credential: admin.credential.applicationDefault() });
  }
  const db = admin.firestore();
  console.log(`${args.apply ? 'APPLY' : 'DRY RUN'} — ${args.project} (${process.env.FIRESTORE_EMULATOR_HOST ? 'emulator' : 'PRODUCTION API'})`);
  const existing = [];
  for (const d of docs) if ((await db.doc(d.path).get()).exists) existing.push(d.path);
  if (existing.length) { console.log('BOR — tegilmaydi:', existing.join(', ')); process.exitCode = args.apply ? 1 : 0; return; }
  if (!args.apply) { console.log('Hammasi yo\'q — --apply bilan yaratiladi.'); return; }
  const ts = admin.firestore.FieldValue.serverTimestamp();
  await db.runTransaction(async (t) => {
    for (const d of docs) if ((await t.get(db.doc(d.path))).exists) throw new Error(`Parallel yaratildi: ${d.path}`);
    for (const d of docs) t.create(db.doc(d.path), { ...d.data, [d.tsField]: ts });
  });
  console.log('YARATILDI:', docs.map((d) => d.path).join(', '));
}

async function restSeed(args, docs, token) {
  const base = `https://firestore.googleapis.com/v1/projects/${args.project}/databases/(default)/documents`;
  const headers = { Authorization: `Bearer ${token}`, 'x-goog-user-project': args.project, 'Content-Type': 'application/json' };
  console.log(`${args.apply ? 'APPLY' : 'DRY RUN'} — ${args.project} (PRODUCTION REST)`);
  const existing = [];
  for (const d of docs) {
    const r = await fetch(`${base}/${d.path}`, { headers });
    if (r.status === 200) existing.push(d.path);
    else if (r.status !== 404) throw new Error(`O'qish xatosi ${d.path}: HTTP ${r.status}`);
  }
  if (existing.length) { console.log('BOR — tegilmaydi:', existing.join(', ')); process.exitCode = args.apply ? 1 : 0; return; }
  if (!args.apply) { console.log('Hammasi yo\'q — --apply bilan yaratiladi.'); return; }
  const name = (p) => `projects/${args.project}/databases/(default)/documents/${p}`;
  const writes = docs.map((d) => {
    const body = Object.fromEntries(Object.entries(d.data).filter(([k]) => k !== d.tsField));
    return {
      update: { name: name(d.path), fields: toValue(body).mapValue.fields },
      updateTransforms: [{ fieldPath: d.tsField, setToServerValue: 'REQUEST_TIME' }],
      currentDocument: { exists: false },
    };
  });
  const res = await fetch(`${base}:commit`, { method: 'POST', headers, body: JSON.stringify({ writes }) });
  if (res.status !== 200) throw new Error(`Commit xatosi HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
  console.log('YARATILDI:', docs.map((d) => d.path).join(', '));
}

if (require.main === module) main().catch((e) => { console.error(e.message || e); process.exit(1); });

module.exports = { parseArgs, load, plan, toValue };
