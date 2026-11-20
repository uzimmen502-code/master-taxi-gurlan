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
  const out = { apply: argv.includes('--apply'), upgrade: argv.includes('--upgrade'), project: null, only: null, taxFile: TAX_FILE, setFile: SET_FILE };
  const val = (flag) => { const i = argv.indexOf(flag); return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : (i >= 0 ? '' : null); };
  out.project = val('--project');
  out.expectedVersion = val('--expected-version');
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

/**
 * ЯНГИЛАШ (2-босқич, эга 2026-11-21): мавжуд taxonomy/supermarket vN → v(N+1) (масалан pairs қўшилган v2 файл).
 *   node functions/tools/seed_supermarket.js --upgrade --taxonomy-file functions/tools/data/supermarket_taxonomy_v2.json \
 *     --expected-version 1 --project <id> [--apply]
 * Версия қулфи: ҳужжатдаги version == --expected-version бўлмаса — тўхтайди. Бир хил мазмун — ёзилмайди.
 * Ёзилади (adminSetSupermarketTaxonomy билан бир хил шакл): taxonomy/supermarket, taxonomy_history/supermarket_v{N+1},
 * admin_audit/supermarket_taxonomy_upgrade_v{N+1}. DRY RUN — сукут.
 */
async function upgrade(args, taxonomy) {
  const expected = Number(args.expectedVersion);
  if (!Number.isInteger(expected) || expected < 1) throw new Error('--expected-version <N> (>=1) kerak');
  if (!args.project) throw new Error('--upgrade faqat --project <id> bilan');
  const plan2 = (cur) => {
    const version = Number.isInteger(cur.version) ? cur.version : 0;
    if (version !== expected) throw new Error(`Versiya mos emas: hujjatda v${version}, kutilgan v${expected}`);
    if (sm.stableStringify(cur.categories) === sm.stableStringify(taxonomy.categories)) return null;
    const v = version + 1;
    const docs = sm.buildTaxonomyVersionDocs({ categories: taxonomy.categories, version: v, previousVersion: version, actor: ACTOR, ts: null });
    return { v, docs, auditPath: `admin_audit/supermarket_taxonomy_upgrade_v${v}`, historyPath: `${sm.HISTORY_COLLECTION}/${sm.HISTORY_PREFIX}${v}` };
  };
  if (!process.env.FIRESTORE_EMULATOR_HOST && process.env.GCLOUD_ACCESS_TOKEN) {
    const token = process.env.GCLOUD_ACCESS_TOKEN;
    const base = `https://firestore.googleapis.com/v1/projects/${args.project}/databases/(default)/documents`;
    const headers = { Authorization: `Bearer ${token}`, 'x-goog-user-project': args.project, 'Content-Type': 'application/json' };
    const r = await fetch(`${base}/${sm.TAXONOMY_DOC.join('/')}`, { headers });
    if (r.status !== 200) throw new Error(`taxonomy/supermarket o'qilmadi: HTTP ${r.status}`);
    const raw = await r.json();
    const f = raw.fields || {};
    const cur = { version: f.version ? Number(f.version.integerValue) : 0, categories: fromValue(f.categories) };
    const p = plan2(cur);
    if (!p) { console.log("O'zgarish yo'q — yozilmaydi."); return; }
    console.log(`${args.apply ? 'APPLY' : 'DRY RUN'} — v${expected} → v${p.v} (PRODUCTION REST): ${sm.TAXONOMY_DOC.join('/')}, ${p.historyPath}, ${p.auditPath}`);
    if (!args.apply) return;
    const name = (x) => `projects/${args.project}/databases/(default)/documents/${x}`;
    const w = (path, data, tsField, precondition) => ({
      update: { name: name(path), fields: toValue(Object.fromEntries(Object.entries(data).filter(([k]) => k !== tsField))).mapValue.fields },
      updateTransforms: [{ fieldPath: tsField, setToServerValue: 'REQUEST_TIME' }],
      currentDocument: precondition,
    });
    const writes = [
      w(sm.TAXONOMY_DOC.join('/'), p.docs.doc, 'updatedAt', { updateTime: raw.updateTime }),
      w(p.historyPath, p.docs.history, 'updatedAt', { exists: false }),
      w(p.auditPath, p.docs.audit, 'at', { exists: false }),
    ];
    const res = await fetch(`${base}:commit`, { method: 'POST', headers, body: JSON.stringify({ writes }) });
    if (res.status !== 200) throw new Error(`Commit xatosi HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
    console.log(`YANGILANDI: v${p.v}`);
    return;
  }
  const admin = require('firebase-admin');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) admin.initializeApp({ projectId: args.project });
    else admin.initializeApp({ projectId: args.project, credential: admin.credential.applicationDefault() });
  }
  const db = admin.firestore();
  const ts = admin.firestore.FieldValue.serverTimestamp();
  const out = await db.runTransaction(async (t) => {
    const ref = db.doc(sm.TAXONOMY_DOC.join('/'));
    const s = await t.get(ref);
    if (!s.exists) throw new Error("taxonomy/supermarket yo'q — avval seed (--apply)");
    const p = plan2(s.data() || {});
    if (!p || !args.apply) return p;
    t.set(ref, { ...p.docs.doc, updatedAt: ts });
    t.create(db.doc(p.historyPath), { ...p.docs.history, updatedAt: ts });
    t.create(db.doc(p.auditPath), { ...p.docs.audit, at: ts });
    return p;
  });
  if (!out) console.log("O'zgarish yo'q — yozilmaydi.");
  else console.log(`${args.apply ? 'YANGILANDI' : 'DRY RUN (yoziladi)'}: v${expected} → v${out.v} (${process.env.FIRESTORE_EMULATOR_HOST ? 'emulator' : 'PRODUCTION API'})`);
}

function fromValue(v) {
  if (!v) return null;
  if ('nullValue' in v) return null;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('stringValue' in v) return v.stringValue;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(fromValue);
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k, x]) => [k, fromValue(x)]));
  return null;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const data = load(args);
  if (args.upgrade) {
    const tv = sm.validateSupermarketTaxonomy(data.taxonomy);
    if (!tv.ok) { for (const e of tv.errors) console.error(`  ${e}`); process.exit(1); }
    return upgrade(args, data.taxonomy);
  }
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

module.exports = { parseArgs, load, plan, toValue, fromValue, upgrade };
