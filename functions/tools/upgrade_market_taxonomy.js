/**
 * «Бозорлар» — мавжуд `taxonomy/markets` ҳужжатини янги версияга кўтариш (эга 2026-11-16: +electronics, +appliances).
 *
 * `seed_market_taxonomy.js` фақат ҳужжат ЙЎҚ бўлса v1 яратади; бу восита эса v{n} → v{n+1} (тўлиқ алмаштириш),
 * `adminSetMarketTaxonomy` билан бир хил шаклда (`buildVersionDocs`: ҳужжат + `taxonomy_history/v{n+1}` + `admin_audit`).
 *
 * Хавфсизлик (27, 28, 41-банд):
 *   - DRY RUN — сукут: файлни текширади, жорий ҳужжатни ўқиб фарқни (added/changed/removed) чиқаради, ёзмайди.
 *   - `--expect-version <n>` шарт: жорий версия n бўлмаса → TAXONOMY_VERSION_CONFLICT (ёзилмайди).
 *   - Бозорни ўчириш (removed) рад этилади — мавжуд эълонлар `market` майдони етим қолмасин.
 *   - Таркиб бир хил бўлса (қайта ишга тушириш) — ёзилмайди, версия ошмайди (идемпотент).
 *   - REST режими: ҳужжат `currentDocument.updateTime` шарти билан (оралиқда ўзгарса — commit рад), тарих ва аудит
 *     `exists:false` (аудит id детерминистик: `market_taxonomy_upgrade_v{n+1}`). Admin SDK режими: транзакция.
 *   - Audit actor = `seed`. Токен лог'га чиқмайди.
 *
 * Ишлатиш:
 *   node functions/tools/upgrade_market_taxonomy.js --file functions/tools/data/market_taxonomy_v2.json --expect-version 1
 *        (офлайн: фақат файл текшируви)
 *   ... --project <id>            # DRY RUN: жорий ҳужжат билан фарқ
 *   ... --project <id> --apply    # v{n+1} ёзади
 *   ADC йўқ машинада: $env:GCLOUD_ACCESS_TOKEN = (gcloud auth print-access-token)  → Firestore REST
 *   Эмулятор: FIRESTORE_EMULATOR_HOST=127.0.0.1:<port> ... --project demo-xxx [--apply]
 */
'use strict';

const path = require('path');
const {
  validateMarketTaxonomy, stableStringify, buildVersionDocs, TAXONOMY_DOC, HISTORY_COLLECTION,
} = require('../market_taxonomy');
const { loadTaxonomy, summarize, toValue } = require('./seed_market_taxonomy');

const ACTOR = 'seed';

function parseArgs(argv) {
  const val = (flag) => {
    const i = argv.indexOf(flag);
    if (i < 0) return null;
    const v = argv[i + 1];
    return v && !v.startsWith('--') ? v : '';
  };
  const file = val('--file');
  const ev = val('--expect-version');
  return {
    apply: argv.includes('--apply'),
    project: val('--project'),
    file: file ? path.resolve(file) : file,
    expectVersion: ev == null ? null : (/^\d+$/.test(ev) ? Number(ev) : NaN),
  };
}

/** Бозор даражасидаги фарқ (тартиб — янги/эски файлдаги тартиб). */
function diffMarkets(oldMarkets, newMarkets) {
  const o = oldMarkets || {};
  const out = { added: [], changed: [], removed: [], unchanged: [] };
  for (const id of Object.keys(newMarkets)) {
    if (!Object.prototype.hasOwnProperty.call(o, id)) out.added.push(id);
    else if (stableStringify(o[id]) !== stableStringify(newMarkets[id])) out.changed.push(id);
    else out.unchanged.push(id);
  }
  for (const id of Object.keys(o)) if (!Object.prototype.hasOwnProperty.call(newMarkets, id)) out.removed.push(id);
  return out;
}

/**
 * Тоза қарор: cur = { exists, version, markets }.
 * → { action: 'MISSING'|'NOOP'|'TAXONOMY_VERSION_CONFLICT'|'REMOVE_REFUSED'|'WRITE', currentVersion, version?, diff }
 */
function decide(cur, expectVersion, markets) {
  const currentVersion = cur.exists && Number.isInteger(cur.version) ? cur.version : 0;
  const diff = diffMarkets(cur.exists ? cur.markets : {}, markets);
  if (!cur.exists) return { action: 'MISSING', currentVersion, diff };
  const same = stableStringify(cur.markets) === stableStringify(markets);
  if (same && (currentVersion === expectVersion || currentVersion === expectVersion + 1)) {
    return { action: 'NOOP', currentVersion, diff };
  }
  if (currentVersion !== expectVersion) return { action: 'TAXONOMY_VERSION_CONFLICT', currentVersion, diff };
  if (diff.removed.length) return { action: 'REMOVE_REFUSED', currentVersion, diff };
  return { action: 'WRITE', currentVersion, version: currentVersion + 1, diff };
}

// Firestore REST Value → JS.
function fromValue(v) {
  if (!v || typeof v !== 'object') return null;
  if ('nullValue' in v) return null;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return Number(v.doubleValue);
  if ('stringValue' in v) return v.stringValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(fromValue);
  if ('mapValue' in v) {
    return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k, x]) => [k, fromValue(x)]));
  }
  return null;
}

function report(d, expectVersion, newMarkets) {
  console.log(`Joriy: ${d.currentVersion ? `version ${d.currentVersion}` : 'hujjat YO\'Q'}; kutilgan: ${expectVersion}`);
  console.log(`Farq: added=[${d.diff.added}] changed=[${d.diff.changed}] removed=[${d.diff.removed}] unchanged=[${d.diff.unchanged}]`);
  const touched = [...d.diff.added, ...d.diff.changed];
  if (touched.length) {
    console.table(summarize({ markets: Object.fromEntries(touched.map((id) => [id, newMarkets[id]])) }));
  }
  const msg = {
    MISSING: 'Hujjat yo\'q — avval seed_market_taxonomy.js (v1). Yozilmaydi.',
    NOOP: 'Tarkib bir xil — yozish shart emas (versiya oshmaydi).',
    TAXONOMY_VERSION_CONFLICT: `TAXONOMY_VERSION_CONFLICT — joriy ${d.currentVersion} ≠ ${expectVersion}. Yozilmaydi.`,
    REMOVE_REFUSED: 'REMOVE_REFUSED — bozorni o\'chirish bu vosita bilan taqiqlangan. Yozilmaydi.',
    WRITE: `Yoziladi: ${TAXONOMY_DOC.join('/')} v${d.version}, ${HISTORY_COLLECTION}/v${d.version}, admin_audit (actor '${ACTOR}')`,
  };
  console.log(msg[d.action]);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.file) throw new Error('--file <json> shart');
  if (!Number.isInteger(args.expectVersion) || args.expectVersion < 1) throw new Error('--expect-version <n ≥ 1> shart');
  if (args.project === '') throw new Error('--project qiymati berilmadi');
  if (args.apply && !args.project) throw new Error('--apply faqat --project <id> bilan');

  const taxonomy = loadTaxonomy(args.file);
  const v = validateMarketTaxonomy(taxonomy);
  console.log(`Fayl: ${args.file}`);
  if (!v.ok) {
    console.error('TAXONOMY_INVALID:');
    for (const e of v.errors) console.error(`  ${e}`);
    process.exit(1);
  }
  console.log(`Tekshiruv: OK (${Object.keys(taxonomy.markets).length} bozor)`);
  if (!args.project) { console.log('DRY RUN (oflayn) — Firestore\'ga ulanmadi.'); return; }

  if (!process.env.FIRESTORE_EMULATOR_HOST && process.env.GCLOUD_ACCESS_TOKEN) {
    await restUpgrade(args, taxonomy.markets, process.env.GCLOUD_ACCESS_TOKEN);
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
  const curOf = (snap) => ({
    exists: snap.exists, version: (snap.data() || {}).version, markets: (snap.data() || {}).markets,
  });

  if (!args.apply) {
    const d = decide(curOf(await ref.get()), args.expectVersion, taxonomy.markets);
    report(d, args.expectVersion, taxonomy.markets);
    if (d.action !== 'WRITE' && d.action !== 'NOOP') process.exitCode = 1;
    return;
  }
  const ts = admin.firestore.FieldValue.serverTimestamp();
  const d = await db.runTransaction(async (t) => {
    const dd = decide(curOf(await t.get(ref)), args.expectVersion, taxonomy.markets);
    if (dd.action !== 'WRITE') return dd;
    const docs = buildVersionDocs({
      markets: taxonomy.markets, version: dd.version, previousVersion: dd.currentVersion, actor: ACTOR, ts,
    });
    t.set(ref, docs.doc);
    t.create(db.collection(HISTORY_COLLECTION).doc(`v${dd.version}`), docs.history);
    t.set(db.collection('admin_audit').doc(), docs.audit);
    return dd;
  });
  report(d, args.expectVersion, taxonomy.markets);
  if (d.action === 'WRITE') console.log(`YOZILDI: taxonomy/markets v${d.version}`);
  else if (d.action !== 'NOOP') process.exitCode = 1;
}

async function restUpgrade(args, markets, token) {
  const base = `https://firestore.googleapis.com/v1/projects/${args.project}/databases/(default)/documents`;
  const headers = { Authorization: `Bearer ${token}`, 'x-goog-user-project': args.project, 'Content-Type': 'application/json' };
  console.log(`${args.apply ? 'APPLY' : 'DRY RUN'} — loyiha ${args.project} (PRODUCTION REST)`);
  const res0 = await fetch(`${base}/${TAXONOMY_DOC.join('/')}`, { headers });
  if (res0.status !== 200 && res0.status !== 404) throw new Error(`O'qish xatosi HTTP ${res0.status}`);
  const raw = res0.status === 200 ? await res0.json() : null;
  const data = raw ? fromValue({ mapValue: { fields: raw.fields || {} } }) : {};
  const d = decide({ exists: !!raw, version: data.version, markets: data.markets }, args.expectVersion, markets);
  report(d, args.expectVersion, markets);
  if (d.action !== 'WRITE') { if (d.action !== 'NOOP') process.exitCode = 1; return; }
  if (!args.apply) return;

  const docs = buildVersionDocs({ markets, version: d.version, previousVersion: d.currentVersion, actor: ACTOR, ts: null });
  const name = (p) => `projects/${args.project}/databases/(default)/documents/${p}`;
  const strip = (o, k) => Object.fromEntries(Object.entries(o).filter(([key]) => key !== k));
  const write = (p, obj, tsField, precondition) => ({
    update: { name: name(p), fields: toValue(strip(obj, tsField)).mapValue.fields },
    updateTransforms: [{ fieldPath: tsField, setToServerValue: 'REQUEST_TIME' }],
    currentDocument: precondition,
  });
  const auditId = `market_taxonomy_upgrade_v${d.version}`;
  const body = {
    writes: [
      // Ўқилгандан бери ҳужжат ўзгарган бўлса — бутун commit рад (оптимистик қулф).
      write(TAXONOMY_DOC.join('/'), docs.doc, 'updatedAt', { updateTime: raw.updateTime }),
      write(`${HISTORY_COLLECTION}/v${d.version}`, docs.history, 'updatedAt', { exists: false }),
      write(`admin_audit/${auditId}`, docs.audit, 'at', { exists: false }),
    ],
  };
  const res = await fetch(`${base}:commit`, { method: 'POST', headers, body: JSON.stringify(body) });
  if (res.status !== 200) throw new Error(`Commit xatosi HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
  console.log(`YOZILDI: taxonomy/markets v${d.version} (+ ${HISTORY_COLLECTION}/v${d.version}, admin_audit/${auditId})`);
}

if (require.main === module) {
  main().catch((e) => { console.error(e.message || e); process.exit(1); });
}

module.exports = { parseArgs, diffMarkets, decide, fromValue };
