/**
 * Ўзбек лотин алифбоси (эга 2026-11-19): `geo_regions` / `geo_districts` даги лотин номи (`name`) ни янги
 * алифбога ўтказиш — o‘→ö, g‘→ğ, sh→ş, ch→ç (tools/uz_latin_alphabet.js, бренд/URL/placeholder истисно).
 * Кирилл (`nameUz`), рус (`nameRu*`) ва бошқа майдонларга ТЕГИЛМАЙДИ. Ҳужжат ID лари ўзгармайди.
 *
 * Хавфсизлик (27, 28-банд):
 *   - DRY RUN — сукут (фақат ўқийди, режани кўрсатади). `--project <id>` МАЖБУРИЙ (сукут йўқ).
 *   - `--apply`: аввал backup JSON (`functions/tools/backup/geo_latin_alphabet_<project>_<ts>.json`: id + эски/янги
 *     ном + updateTime), кейин ≤400 тали commit'лар, ҳар ёзувда `updateTime` шарти (орада ўзгарган ҳужжат
 *     ёзилмайди — қайта ишга туширинг), прогресс лог, якунда текширув (қайта ўқиб солиштиради).
 *   - Rollback: `--rollback <backup.json> [--apply]` — фақат backup'даги ҳужжатларда ВА `name` ҳозир айнан шу
 *     скрипт ёзган қийматга тенг бўлса эски номни қайтаради (кейин қўлда тузатилганлар тегилмайди).
 *   - Идемпотент: қайта ишга туширилса — янги алифбодаги номлар ўзгармайди (0 ёзув).
 *
 * Ишлатиш:
 *   node functions/tools/migrate_geo_latin_alphabet.js --project <id>                 # DRY RUN
 *   node functions/tools/migrate_geo_latin_alphabet.js --project <id> --apply         # ёзиш
 *   node functions/tools/migrate_geo_latin_alphabet.js --project <id> --rollback <f>  # rollback DRY RUN (+ --apply)
 *   ADC йўқ машинада: $env:GCLOUD_ACCESS_TOKEN = (gcloud auth print-access-token) — Firestore REST (токен лог'га чиқмайди).
 *   Эмулятор: FIRESTORE_EMULATOR_HOST=127.0.0.1:<port> ... --project demo-xxx
 *
 * Эслатма: мижоз ва сервер қидируви эски/янги шаклни бирдек қабул қилади (UzScript.foldLatin,
 * market_search_tokens.foldLatin), лекин номни лотин матн бўйича солиштирадиган бошқа код бўлса — deploy'дан олдин
 * текширилсин (ҳисоботдаги очиқ масалалар).
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { convertText } = require('./uz_latin_alphabet');

const PAGE = 400;
const COLLECTIONS = Object.freeze(['geo_regions', 'geo_districts']);
const FIELD = 'name';
const KIND = 'geo_latin_alphabet_migration';
const BACKUP_DIR = path.join(__dirname, 'backup');

function parseArgs(argv) {
  const val = (flag) => {
    const i = argv.indexOf(flag);
    if (i < 0) return undefined;
    return argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : '';
  };
  return { apply: argv.includes('--apply'), project: val('--project'), rollback: val('--rollback') };
}

/** Тоза: битта ҳужжат учун ёзув ёки null. doc: {collection, id, name, updateTime}. */
function planDoc(doc) {
  if (typeof doc.name !== 'string' || !doc.name.trim()) return null;
  const after = convertText(doc.name);
  if (after === doc.name) return null;
  return { collection: doc.collection, id: doc.id, updateTime: doc.updateTime, before: doc.name, after };
}

/** Тоза: rollback ёзувлари — фақат ҳозирги ном скрипт ёзганига тенг бўлса. current: [{collection,id,exists,name,updateTime}]. */
function planRollback(backupDocs, current) {
  const byKey = new Map(current.map((c) => [`${c.collection}/${c.id}`, c]));
  const writes = [];
  let skipped = 0;
  for (const b of backupDocs) {
    const c = byKey.get(`${b.collection}/${b.id}`);
    if (c && c.exists && c.name === b.after) {
      writes.push({ collection: b.collection, id: b.id, updateTime: c.updateTime, before: b.after, after: b.before });
    } else skipped += 1;
  }
  return { writes, skipped };
}

// ─── Firestore қатлами: Admin SDK ёки REST ───

function sdkStore(project) {
  const admin = require('firebase-admin');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) admin.initializeApp({ projectId: project });
    else admin.initializeApp({ projectId: project, credential: admin.credential.applicationDefault() });
  }
  const db = admin.firestore();
  return {
    label: process.env.FIRESTORE_EMULATOR_HOST ? `emulator ${process.env.FIRESTORE_EMULATOR_HOST}` : 'PRODUCTION (Admin SDK)',
    async* listAll(collection) {
      let last = null;
      for (;;) {
        let q = db.collection(collection).orderBy(admin.firestore.FieldPath.documentId()).limit(PAGE);
        if (last) q = q.startAfter(last);
        const snap = await q.get();
        for (const doc of snap.docs) {
          const d = doc.data() || {};
          yield { collection, id: doc.id, updateTime: doc.updateTime, name: d[FIELD] };
        }
        if (snap.size < PAGE) break;
        last = snap.docs[snap.docs.length - 1];
      }
    },
    async getMany(collection, ids) {
      const refs = ids.map((id) => db.collection(collection).doc(id));
      const snaps = refs.length ? await db.getAll(...refs) : [];
      return snaps.map((s) => ({
        collection, id: s.id, exists: s.exists, updateTime: s.exists ? s.updateTime : null,
        name: s.exists ? (s.data() || {})[FIELD] : undefined,
      }));
    },
    /** writes: [{collection, id, updateTime, after}] */
    async commit(writes) {
      const batch = db.batch();
      for (const w of writes) {
        batch.update(db.collection(w.collection).doc(w.id), { [FIELD]: w.after }, { lastUpdateTime: w.updateTime });
      }
      await batch.commit();
    },
  };
}

function restStore(project, token) {
  const root = `projects/${project}/databases/(default)/documents`;
  const base = `https://firestore.googleapis.com/v1/${root}`;
  const headers = { Authorization: `Bearer ${token}`, 'x-goog-user-project': project, 'Content-Type': 'application/json' };
  const post = async (url, body) => {
    const res = await fetch(url, { method: 'POST', headers, body: JSON.stringify(body) });
    if (res.status !== 200) throw new Error(`HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
    return res.json();
  };
  const str = (f) => (f && typeof f.stringValue === 'string' ? f.stringValue : undefined);
  return {
    label: 'PRODUCTION (REST)',
    async* listAll(collection) {
      let cursor = null;
      for (;;) {
        const structuredQuery = {
          from: [{ collectionId: collection }],
          orderBy: [{ field: { fieldPath: '__name__' }, direction: 'ASCENDING' }],
          limit: PAGE,
          ...(cursor ? { startAt: { values: [{ referenceValue: cursor }], before: false } } : {}),
        };
        const rows = (await post(`${base}:runQuery`, { structuredQuery })).filter((r) => r.document);
        for (const r of rows) {
          yield {
            collection, id: r.document.name.split('/').pop(), updateTime: r.document.updateTime,
            name: str((r.document.fields || {})[FIELD]),
          };
        }
        if (rows.length < PAGE) break;
        cursor = rows[rows.length - 1].document.name;
      }
    },
    async getMany(collection, ids) {
      if (!ids.length) return [];
      const out = await post(`${base}:batchGet`, { documents: ids.map((id) => `${root}/${collection}/${id}`) });
      return out.map((r) => (r.found
        ? { collection, id: r.found.name.split('/').pop(), exists: true, updateTime: r.found.updateTime, name: str((r.found.fields || {})[FIELD]) }
        : { collection, id: String(r.missing).split('/').pop(), exists: false, updateTime: null, name: undefined }));
    },
    async commit(writes) {
      await post(`${base}:commit`, {
        writes: writes.map((w) => ({
          update: { name: `${root}/${w.collection}/${w.id}`, fields: { [FIELD]: { stringValue: w.after } } },
          updateMask: { fieldPaths: [FIELD] },
          currentDocument: { updateTime: w.updateTime },
        })),
      });
    },
  };
}

/** Backup учун (фақат маълумот): SDK Timestamp ёки REST ISO сатр. */
function isoOf(v) {
  return typeof v === 'string' ? v : (v && v.toDate ? v.toDate().toISOString() : null);
}

async function commitInChunks(store, writes, label) {
  let done = 0;
  let failedChunks = 0;
  for (let i = 0; i < writes.length; i += PAGE) {
    const chunk = writes.slice(i, i + PAGE);
    try {
      await store.commit(chunk);
      done += chunk.length;
    } catch (e) {
      failedChunks += 1;
      console.error(`  ${label}: chunk ${i / PAGE + 1} XATO (hech narsa yozilmadi, qayta ishga tushiring): ${e.message || e}`);
    }
    console.log(`  ${label}: ${done}/${writes.length}`);
  }
  return { done, failedChunks };
}

async function verify(store, writes) {
  let ok = 0;
  for (const col of COLLECTIONS) {
    const ws = writes.filter((w) => w.collection === col);
    for (let i = 0; i < ws.length; i += 100) {
      const part = ws.slice(i, i + 100);
      const got = await store.getMany(col, part.map((w) => w.id));
      const want = new Map(part.map((w) => [w.id, w.after]));
      ok += got.filter((g) => g.exists && g.name === want.get(g.id)).length;
    }
  }
  return ok;
}

async function migrate(store, args, { backupDir = BACKUP_DIR, now = Date.now() } = {}) {
  console.log(`${args.apply ? 'APPLY' : 'DRY RUN'} — loyiha ${args.project} (${store.label}); maydon: ${FIELD}`);
  const plan = [];
  for (const col of COLLECTIONS) {
    let scanned = 0;
    let picked = 0;
    for await (const doc of store.listAll(col)) {
      scanned += 1;
      const w = planDoc(doc);
      if (!w) continue;
      picked += 1;
      plan.push(w);
      console.log(`  ${col}/${w.id}: «${w.before}» → «${w.after}»`);
    }
    console.log(`  ${col}: jami=${scanned}, o'zgaradi=${picked}`);
  }
  if (!args.apply) { console.log(`DRY RUN — jami ${plan.length} ta yoziladi. Yozish: --apply`); return { planned: plan.length, plan }; }
  if (!plan.length) { console.log('Yoziladigan hujjat yo\'q.'); return { planned: 0, done: 0 }; }

  fs.mkdirSync(backupDir, { recursive: true });
  const file = path.join(backupDir, `geo_latin_alphabet_${args.project}_${new Date(now).toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(file, JSON.stringify({
    kind: KIND, project: args.project, field: FIELD, createdAt: new Date(now).toISOString(),
    docs: plan.map((p) => ({ collection: p.collection, id: p.id, before: p.before, after: p.after, updateTime: isoOf(p.updateTime) })),
  }, null, 1));
  console.log(`Backup: ${file}`);

  const res = await commitInChunks(store, plan, 'yozildi');
  const verified = await verify(store, plan);
  console.log(`Natija: yozildi=${res.done}/${plan.length}, tekshiruv=${verified}, xato chunk=${res.failedChunks}`);
  console.log(`ROLLBACK: node functions/tools/migrate_geo_latin_alphabet.js --project ${args.project} --rollback "${file}" --apply`);
  if (res.failedChunks) process.exitCode = 1;
  return { planned: plan.length, done: res.done, verified, backup: file };
}

async function rollback(store, args) {
  const bk = JSON.parse(fs.readFileSync(path.resolve(args.rollback), 'utf8'));
  if (bk.kind !== KIND || bk.project !== args.project) throw new Error('Backup boshqa loyiha/tur uchun');
  const current = [];
  for (const col of COLLECTIONS) {
    const ids = bk.docs.filter((d) => d.collection === col).map((d) => d.id);
    for (let i = 0; i < ids.length; i += 100) current.push(...await store.getMany(col, ids.slice(i, i + 100)));
  }
  const { writes, skipped } = planRollback(bk.docs, current);
  console.log(`ROLLBACK ${args.apply ? 'APPLY' : 'DRY RUN'} — qaytariladi: ${writes.length}; o'tkazib yuborildi (keyin o'zgargan/yo'q): ${skipped}`);
  if (!args.apply) return { planned: writes.length, skipped };
  const res = await commitInChunks(store, writes, 'qaytarildi');
  const verified = await verify(store, writes);
  console.log(`Natija: qaytarildi=${res.done}/${writes.length}, tekshiruv=${verified}`);
  if (res.failedChunks) process.exitCode = 1;
  return { planned: writes.length, done: res.done, verified, skipped };
}

async function main(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  if (!args.project) throw new Error('--project <id> majburiy');
  if (args.rollback === '') throw new Error('--rollback <backup.json> fayli berilmadi');
  const store = (!process.env.FIRESTORE_EMULATOR_HOST && process.env.GCLOUD_ACCESS_TOKEN)
    ? restStore(args.project, process.env.GCLOUD_ACCESS_TOKEN)
    : sdkStore(args.project);
  return args.rollback ? rollback(store, args) : migrate(store, args);
}

if (require.main === module) {
  main().catch((e) => { console.error(e.message || e); process.exit(1); });
}

module.exports = { parseArgs, planDoc, planRollback, migrate, rollback, main, sdkStore, COLLECTIONS, FIELD };
