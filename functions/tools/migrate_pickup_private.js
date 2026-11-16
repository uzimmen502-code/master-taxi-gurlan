/**
 * «Бозорлар» 11 (эга 2026-11-16): эски ОММАВИЙ олиб кетиш нуқтасини private'га кўчириш.
 *
 * Олдинги клиент (жонли 2cfa0a20, бир неча соат) аниқ нуқтани `tv_shops/{phone}` га оммавий ёзган:
 * `pickupLat` / `pickupLng` / `pickupAddress`. Энди аниқ нуқта — `tv_shops/{phone}/private/pickup`
 * {lat,lng,address,updatedAt} (rules: фақат эга), оммавийда эса фақат тахминий `areaLat/areaLng`
 * (0.005° тўр ≈ 500 м, клиентдаги `approxShopCoord` билан бир хил; `showExactLocation == true` бўлса аниқ).
 *
 * Ҳар бир `tv_shops` ҳужжати (pickup* дан камида биттаси бор) учун, ДЎКОН БЎЙИЧА АТОМАР commit:
 *   1) private/pickup ни ёзади — ФАҚАТ у ҳали ЙЎҚ бўлса (`currentDocument.exists = false`), updatedAt = REQUEST_TIME;
 *      бор бўлса (янги клиент сақлаган) — тегилмайди.
 *   2) оммавий: areaLat/areaLng ни қўяди (агар улар ҳали йўқ бўлса; бор бўлса — янги клиентники, тегилмайди),
 *      pickupLat/pickupLng/pickupAddress ни ўчиради. Шарт: `currentDocument.updateTime` (ўқилгандан бери
 *      ўзгармаган) — ўзгарган бўлса шу дўкон ўтказилади (PRECONDITION_FAILED), қайта ишга тушириш хавфсиз.
 *   Координатаси яроқсиз ҳужжат (масалан фақат pickupAddress) — тегилмайди, ҳисоботда `invalid` (эга қарори).
 *
 * Хавфсизлик (27, 28-банд):
 *   - DRY RUN — сукут. `--apply` бўлмаса ҳеч нарса ёзилмайди. `--project` МАЖБУРИЙ (сукут йўқ).
 *   - Ёзишдан ОЛДИН backup: `functions/tools/backup/pickup_private_<project>_<ts>.json` (ID + эски қийматлар,
 *     ҳар batch'дан кейин натижа билан янгиланади). Backup'да PII (манзил, координата) бор — commit ҚИЛИНМАСИН.
 *   - batch ≤ 400 ёзув (≤ 200 дўкон); batch рад этилса — дўконма-дўкон қайта уринилади (битта шарт бутун batch'ни
 *     тўхтатмасин).
 *   - `--rollback <backup.json>` (+ `--apply`): `applied` ёзувлар учун оммавий майдонларни эски қийматига қайтаради
 *     ва ФАҚАТ шу восита яратган private ҳужжатни ўчиради; иккаласи ҳам updateTime шарти билан — кейин эга
 *     ўзгартирган бўлса тегилмайди (`conflict`).
 *
 * Ишлатиш (prod — ADC йўқ машинада REST, токен лог'га чиқмайди):
 *   $env:GCLOUD_ACCESS_TOKEN = (gcloud auth print-access-token)
 *   node functions/tools/migrate_pickup_private.js --project <id>                    # DRY RUN
 *   node functions/tools/migrate_pickup_private.js --project <id> --apply            # кўчиради
 *   node functions/tools/migrate_pickup_private.js --project <id> --rollback <file>  # DRY RUN rollback
 *   node functions/tools/migrate_pickup_private.js --project <id> --rollback <file> --apply
 *   Эмулятор: FIRESTORE_EMULATOR_HOST=127.0.0.1:<port> ... --project demo-xxx
 */
'use strict';

const fs = require('fs');
const path = require('path');

const COLLECTION = 'tv_shops';
const LEGACY = ['pickupLat', 'pickupLng', 'pickupAddress'];
const AREA = ['areaLat', 'areaLng'];
const AREA_STEP_DEG = 0.005; // = клиент kShopAreaStepDeg (lib/features/tv_market/models/tv_shop.dart)
const ADDRESS_MAX = 200; // = rules tvShopPickupPrivOk
const MAX_WRITES = 400;
const BACKUP_DIR = path.join(__dirname, 'backup');

function parseArgs(argv) {
  const val = (flag) => {
    const i = argv.indexOf(flag);
    if (i < 0) return null;
    return argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : '';
  };
  return { apply: argv.includes('--apply'), project: val('--project'), rollback: val('--rollback') };
}

/** Клиент `approxShopCoord` билан бир хил: Dart `round()` (ноль'дан узоққа) + 3 хона. */
function approxCoord(v) {
  const steps = Math.sign(v) * Math.round(Math.abs(v) / AREA_STEP_DEG);
  return Number((steps * AREA_STEP_DEG).toFixed(3));
}

/** REST Value → JS сон (фақат чекли сон; бошқаси null). */
function num(v) {
  if (!v) return null;
  let n = null;
  if ('doubleValue' in v) n = Number(v.doubleValue);
  else if ('integerValue' in v) n = Number(v.integerValue);
  else if ('stringValue' in v && v.stringValue.trim() !== '') n = Number(v.stringValue);
  return Number.isFinite(n) ? n : null;
}

function str(v) {
  if (!v) return '';
  if ('stringValue' in v) return v.stringValue;
  return '';
}

/** Бир ҳужжатнинг режаси (соф). `doc` — REST Document, `privateExists` — private/pickup бор-йўқлиги. */
function planDoc(doc, privateExists) {
  const f = doc.fields || {};
  const id = doc.name.split('/').pop();
  const old = {};
  for (const k of [...LEGACY, ...AREA, 'showExactLocation']) old[k] = k in f ? f[k] : null;
  const lat = num(f.pickupLat);
  const lng = num(f.pickupLng);
  const base = { id, publicUpdateTimeBefore: doc.updateTime, old, privateExisted: privateExists };
  if (lat === null || lng === null || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    return { ...base, action: 'invalid', status: 'skipped' };
  }
  const exact = f.showExactLocation && f.showExactLocation.booleanValue === true;
  const keepArea = AREA.some((k) => k in f);
  const address = str(f.pickupAddress).trim().slice(0, ADDRESS_MAX);
  return {
    ...base,
    action: 'migrate',
    status: 'planned',
    createPrivate: !privateExists,
    privateValue: privateExists ? null : { lat, lng, address },
    setArea: keepArea ? null : { areaLat: exact ? lat : approxCoord(lat), areaLng: exact ? lng : approxCoord(lng) },
  };
}

function client(project) {
  const emu = process.env.FIRESTORE_EMULATOR_HOST;
  let base;
  let headers;
  if (emu) {
    base = `http://${emu}/v1/projects/${project}/databases/(default)/documents`;
    headers = { Authorization: 'Bearer owner', 'Content-Type': 'application/json' };
  } else {
    const token = process.env.GCLOUD_ACCESS_TOKEN;
    if (!token) throw new Error('GCLOUD_ACCESS_TOKEN kerak ($env:GCLOUD_ACCESS_TOKEN = (gcloud auth print-access-token))');
    base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
    headers = { Authorization: `Bearer ${token}`, 'x-goog-user-project': project, 'Content-Type': 'application/json' };
  }
  const name = (p) => `projects/${project}/databases/(default)/documents/${p}`;
  const call = async (url, opts = {}) => {
    const res = await fetch(url, { headers, ...opts });
    const text = await res.text();
    let body = null;
    try { body = text ? JSON.parse(text) : null; } catch (_) { body = null; }
    return { status: res.status, body, text };
  };
  return { base, name, call, target: emu ? `emulator ${emu}` : 'PRODUCTION REST' };
}

async function listCandidates(c) {
  const out = [];
  let pageToken = '';
  const mask = [...LEGACY, ...AREA, 'showExactLocation'].map((k) => `mask.fieldPaths=${k}`).join('&');
  for (;;) {
    const r = await c.call(`${c.base}/${COLLECTION}?pageSize=300&${mask}${pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : ''}`);
    if (r.status !== 200) throw new Error(`LIST_FAILED HTTP ${r.status}`);
    for (const d of (r.body && r.body.documents) || []) {
      if (LEGACY.some((k) => k in (d.fields || {}))) out.push(d);
    }
    pageToken = r.body && r.body.nextPageToken;
    if (!pageToken) return out;
  }
}

async function privateExistence(c, ids) {
  const exists = new Map();
  for (let i = 0; i < ids.length; i += 100) {
    const chunk = ids.slice(i, i + 100);
    const r = await c.call(`${c.base}:batchGet`, {
      method: 'POST',
      body: JSON.stringify({ documents: chunk.map((id) => c.name(`${COLLECTION}/${id}/private/pickup`)), mask: { fieldPaths: ['updatedAt'] } }),
    });
    if (r.status !== 200) throw new Error(`BATCH_GET_FAILED HTTP ${r.status}`);
    for (const x of r.body || []) {
      const n = x.found ? x.found.name : x.missing;
      if (!n) continue;
      exists.set(n.split('/').slice(-3)[0], Boolean(x.found));
    }
  }
  return exists;
}

const dbl = (n) => ({ doubleValue: n });

function migrateWrites(c, e) {
  const writes = [];
  if (e.createPrivate) {
    const v = e.privateValue;
    writes.push({
      update: { name: c.name(`${COLLECTION}/${e.id}/private/pickup`), fields: { lat: dbl(v.lat), lng: dbl(v.lng), address: { stringValue: v.address } } },
      updateTransforms: [{ fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME' }],
      currentDocument: { exists: false },
    });
  }
  const fields = {};
  const maskPaths = [...LEGACY];
  if (e.setArea) {
    fields.areaLat = dbl(e.setArea.areaLat);
    fields.areaLng = dbl(e.setArea.areaLng);
    maskPaths.push(...AREA);
  }
  writes.push({
    update: { name: c.name(`${COLLECTION}/${e.id}`), fields },
    updateMask: { fieldPaths: maskPaths }, // маскада бор, fields'да йўқ → ўчади (pickup*)
    currentDocument: { updateTime: e.publicUpdateTimeBefore },
  });
  return writes;
}

function rollbackWrites(c, e) {
  const writes = [];
  const fields = {};
  const maskPaths = [...LEGACY];
  for (const k of LEGACY) if (e.old[k] !== null) fields[k] = e.old[k];
  if (e.setArea) {
    maskPaths.push(...AREA);
    for (const k of AREA) if (e.old[k] !== null) fields[k] = e.old[k];
  }
  writes.push({
    update: { name: c.name(`${COLLECTION}/${e.id}`), fields },
    updateMask: { fieldPaths: maskPaths },
    currentDocument: { updateTime: e.publicUpdateTimeAfter },
  });
  if (e.createPrivate && e.privateUpdateTime) {
    writes.push({ delete: c.name(`${COLLECTION}/${e.id}/private/pickup`), currentDocument: { updateTime: e.privateUpdateTime } });
  }
  return writes;
}

/**
 * Ёзувларни batch'лаб commit қилади (≤ MAX_WRITES). Batch рад этилса — ҳар бир дўкон алоҳида.
 * `onDone(entry, writeResults|null, errorCode|null)`.
 */
async function commitGrouped(c, entries, build, onDone, progress) {
  let i = 0;
  while (i < entries.length) {
    const group = [];
    let n = 0;
    while (i < entries.length) {
      const w = build(c, entries[i]);
      if (group.length && n + w.length > MAX_WRITES) break;
      group.push({ e: entries[i], w });
      n += w.length;
      i += 1;
    }
    const r = await c.call(`${c.base}:commit`, { method: 'POST', body: JSON.stringify({ writes: group.flatMap((g) => g.w) }) });
    if (r.status === 200) {
      let k = 0;
      for (const g of group) { onDone(g.e, r.body.writeResults.slice(k, k + g.w.length), null); k += g.w.length; }
    } else {
      for (const g of group) {
        const one = await c.call(`${c.base}:commit`, { method: 'POST', body: JSON.stringify({ writes: g.w }) });
        if (one.status === 200) onDone(g.e, one.body.writeResults, null);
        else onDone(g.e, null, (one.body && one.body.error && one.body.error.status) || `HTTP_${one.status}`);
      }
    }
    progress(i, entries.length);
  }
}

function writeJson(file, obj) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(obj, null, 2), 'utf8');
  fs.renameSync(tmp, file);
}

const log = (o) => console.log(JSON.stringify({ tool: 'migrate_pickup_private', ...o }));

async function migrate(args, c, opts = {}) {
  const docs = await listCandidates(c);
  const priv = await privateExistence(c, docs.map((d) => d.name.split('/').pop()));
  const entries = docs.map((d) => planDoc(d, priv.get(d.name.split('/').pop()) === true));
  const todo = entries.filter((e) => e.action === 'migrate');
  const summary = {
    mode: args.apply ? 'APPLY' : 'DRY_RUN',
    candidates: entries.length,
    migrate: todo.length,
    createPrivate: todo.filter((e) => e.createPrivate).length,
    privateAlreadyExists: todo.filter((e) => !e.createPrivate).length,
    areaKept: todo.filter((e) => !e.setArea).length,
    invalid: entries.filter((e) => e.action === 'invalid').map((e) => e.id),
  };
  if (!args.apply || todo.length === 0) {
    log({ result: args.apply ? 'nothing_to_do' : 'dry_run', ...summary });
    return { summary, entries, backupFile: null };
  }
  if (opts.beforeApply) await opts.beforeApply(entries); // тест учун (параллел ўзгариш)
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupFile = opts.backupFile || path.join(BACKUP_DIR, `pickup_private_${args.project}_${stamp}.json`);
  const backup = { tool: 'migrate_pickup_private', project: args.project, createdAt: new Date().toISOString(), entries };
  writeJson(backupFile, backup); // ЁЗИШДАН ОЛДИН
  console.log(`Backup: ${backupFile}`);
  let applied = 0;
  let failed = 0;
  await commitGrouped(c, todo, migrateWrites, (e, wr, err) => {
    if (err) { e.status = 'failed'; e.errorCode = err; failed += 1; return; }
    e.status = 'applied';
    e.appliedAt = new Date().toISOString();
    if (e.createPrivate) e.privateUpdateTime = wr[0].updateTime;
    e.publicUpdateTimeAfter = wr[wr.length - 1].updateTime;
    applied += 1;
  }, (done, total) => { writeJson(backupFile, backup); console.log(`progress ${done}/${total}`); });
  Object.assign(summary, { applied, failed, failedIds: todo.filter((e) => e.status === 'failed').map((e) => `${e.id}:${e.errorCode}`) });
  log({ result: failed ? 'partial' : 'ok', backupFile, ...summary });
  return { summary, entries, backupFile };
}

async function rollback(args, c) {
  const file = path.resolve(args.rollback);
  const backup = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (backup.tool !== 'migrate_pickup_private') throw new Error('BACKUP_INVALID');
  if (backup.project !== args.project) throw new Error(`BACKUP_PROJECT_MISMATCH (${backup.project} ≠ ${args.project})`);
  const todo = backup.entries.filter((e) => e.status === 'applied');
  const summary = {
    mode: args.apply ? 'ROLLBACK_APPLY' : 'ROLLBACK_DRY_RUN',
    entries: backup.entries.length,
    toRestore: todo.length,
    privateToDelete: todo.filter((e) => e.createPrivate && e.privateUpdateTime).length,
    notApplied: backup.entries.filter((e) => e.status !== 'applied' && e.status !== 'rolled_back').length,
  };
  if (!args.apply || todo.length === 0) { log({ result: 'rollback_dry_run', backupFile: file, ...summary }); return { summary }; }
  let restored = 0;
  const conflicts = [];
  await commitGrouped(c, todo, rollbackWrites, (e, wr, err) => {
    if (err) { e.rollbackError = err; conflicts.push(`${e.id}:${err}`); return; }
    e.status = 'rolled_back';
    e.rolledBackAt = new Date().toISOString();
    restored += 1;
  }, (done, total) => { writeJson(file, backup); console.log(`progress ${done}/${total}`); });
  Object.assign(summary, { restored, conflicts });
  log({ result: conflicts.length ? 'partial' : 'ok', backupFile: file, ...summary });
  return { summary };
}

async function main(argv, opts = {}) {
  const args = parseArgs(argv);
  if (!args.project) throw new Error('--project <id> MAJBURIY');
  if (args.rollback === '') throw new Error('--rollback <backup.json> fayl yo\'li kerak');
  const c = client(args.project);
  console.log(`${args.rollback !== null ? 'ROLLBACK ' : ''}${args.apply ? 'APPLY' : 'DRY RUN'} — loyiha ${args.project} (${c.target})`);
  return args.rollback !== null ? rollback(args, c) : migrate(args, c, opts);
}

if (require.main === module) {
  main(process.argv.slice(2)).catch((e) => { console.error(e.message || e); process.exit(1); });
}

module.exports = { main, parseArgs, approxCoord, planDoc, AREA_STEP_DEG };
