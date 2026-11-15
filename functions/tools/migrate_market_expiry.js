/**
 * «Бозорлар» 2a (эга 2026-11-15, қарор 3): мавжуд фаол эълонларга `expiresAt` = <ишга туширилган вақт + 30 кун>.
 *
 * Қамров (эга қарори 2): tv_shop_items, realty_listings, ads (type == 'cheap_product'). wholesale_products — ЙЎҚ.
 * Фақат `status == 'active'` ВА `expiresAt` ЙЎҚ ҳужжатлар. Мавжуд `expiresAt` ҲЕЧ ҚАЧОН ўзгартирилмайди
 * (realty/ads да у аллақачон бор — улар одатда тегилмайди).
 *
 * Хавфсизлик (27, 28-банд):
 *   - DRY RUN — сукут (фақат ўқийди ва санайди). `--project <id>` МАЖБУРИЙ (сукут йўқ).
 *   - `--apply`: аввал backup JSON (`functions/tools/backup/market_expiry_<project>_<ts>.json`: id + эски ҳолат),
 *     кейин ≤400 тали commit'лар, ҳар ёзувда `updateTime` шарти (орада ўзгарган ҳужжат ёзилмайди — қайта ишга
 *     туширинг), прогресс лог, якунда текширув (қайта ўқиб санайди).
 *   - Rollback: `--rollback <backup.json> [--apply]` — фақат backup'даги ҳужжатларда ВА `expiresAt` айнан шу скрипт
 *     қўйган қийматга тенг бўлса `expiresAt` ни ўчиради (кейин модерация/янгилаш ўзгартирганлар тегилмайди).
 *
 * Ишлатиш:
 *   node functions/tools/migrate_market_expiry.js --project <id>                 # DRY RUN
 *   node functions/tools/migrate_market_expiry.js --project <id> --apply         # ёзиш
 *   node functions/tools/migrate_market_expiry.js --project <id> --rollback <f>  # rollback DRY RUN
 *   ADC йўқ машинада: $env:GCLOUD_ACCESS_TOKEN = (gcloud auth print-access-token) — Firestore REST (токен лог'га чиқмайди).
 *   Эмулятор: FIRESTORE_EMULATOR_HOST=127.0.0.1:<port> ... --project demo-xxx
 */
'use strict';

const fs = require('fs');
const path = require('path');

const DAYS = 30;
const PAGE = 400;
const TARGETS = Object.freeze([
  { collection: 'tv_shop_items', type: null },
  { collection: 'realty_listings', type: null },
  { collection: 'ads', type: 'cheap_product' },
]);
const BACKUP_DIR = path.join(__dirname, 'backup');

function parseArgs(argv) {
  const val = (flag) => {
    const i = argv.indexOf(flag);
    if (i < 0) return undefined;
    return argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : '';
  };
  return { apply: argv.includes('--apply'), project: val('--project'), rollback: val('--rollback') };
}

/** Тоза: ҳужжат миграцияга тушадими. */
function needsExpiry(target, data) {
  const d = data || {};
  if (d.status !== 'active') return false;
  if (target.type && d.type !== target.type) return false;
  return d.expiresAt === undefined || d.expiresAt === null;
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
    async* listActive(collection) {
      let last = null;
      for (;;) {
        let q = db.collection(collection).where('status', '==', 'active')
          .orderBy(admin.firestore.FieldPath.documentId()).limit(PAGE);
        if (last) q = q.startAfter(last);
        const snap = await q.get();
        for (const doc of snap.docs) {
          const d = doc.data() || {};
          yield {
            id: doc.id, updateTime: doc.updateTime, // Timestamp (наносекунд аниқлиги — шарт учун)
            data: { status: d.status, type: d.type, expiresAt: d.expiresAt === undefined ? undefined : d.expiresAt },
          };
        }
        if (snap.size < PAGE) break;
        last = snap.docs[snap.docs.length - 1];
      }
    },
    async getMany(collection, ids) {
      const refs = ids.map((id) => db.collection(collection).doc(id));
      const snaps = refs.length ? await db.getAll(...refs) : [];
      return snaps.map((s) => ({
        id: s.id, exists: s.exists, updateTime: s.exists ? s.updateTime : null,
        expiresAtMs: s.exists && s.data().expiresAt && s.data().expiresAt.toMillis ? s.data().expiresAt.toMillis() : null,
      }));
    },
    /** writes: [{collection, id, updateTime, expiresAtMs|null(=delete)}] → { ok, failed } */
    async commit(writes) {
      const batch = db.batch();
      for (const w of writes) {
        const ref = db.collection(w.collection).doc(w.id);
        const value = w.expiresAtMs == null
          ? admin.firestore.FieldValue.delete()
          : admin.firestore.Timestamp.fromMillis(w.expiresAtMs);
        batch.update(ref, { expiresAt: value }, { lastUpdateTime: w.updateTime });
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
  const tsMs = (v) => (v && v.timestampValue ? Date.parse(v.timestampValue) : null);
  return {
    label: 'PRODUCTION (REST)',
    async* listActive(collection) {
      let cursor = null;
      for (;;) {
        const structuredQuery = {
          from: [{ collectionId: collection }],
          where: { fieldFilter: { field: { fieldPath: 'status' }, op: 'EQUAL', value: { stringValue: 'active' } } },
          orderBy: [{ field: { fieldPath: '__name__' }, direction: 'ASCENDING' }],
          limit: PAGE,
          ...(cursor ? { startAt: { values: [{ referenceValue: cursor }], before: false } } : {}),
        };
        const rows = (await post(`${base}:runQuery`, { structuredQuery })).filter((r) => r.document);
        for (const r of rows) {
          const f = r.document.fields || {};
          yield {
            id: r.document.name.split('/').pop(), updateTime: r.document.updateTime,
            data: {
              status: f.status && f.status.stringValue, type: f.type && f.type.stringValue,
              expiresAt: f.expiresAt === undefined ? undefined : (f.expiresAt.nullValue !== undefined ? null : f.expiresAt),
            },
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
        ? { id: r.found.name.split('/').pop(), exists: true, updateTime: r.found.updateTime, expiresAtMs: tsMs((r.found.fields || {}).expiresAt) }
        : { id: String(r.missing).split('/').pop(), exists: false, updateTime: null, expiresAtMs: null }));
    },
    async commit(writes) {
      await post(`${base}:commit`, {
        writes: writes.map((w) => ({
          update: {
            name: `${root}/${w.collection}/${w.id}`,
            fields: w.expiresAtMs == null ? {} : { expiresAt: { timestampValue: new Date(w.expiresAtMs).toISOString() } },
          },
          updateMask: { fieldPaths: ['expiresAt'] },
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

async function migrate(store, args) {
  const nowMs = Date.now();
  const expiresAtMs = nowMs + DAYS * 24 * 60 * 60 * 1000;
  console.log(`${args.apply ? 'APPLY' : 'DRY RUN'} — loyiha ${args.project} (${store.label}); expiresAt = ${new Date(expiresAtMs).toISOString()}`);
  const plan = [];
  for (const target of TARGETS) {
    let scanned = 0;
    let picked = 0;
    for await (const doc of store.listActive(target.collection)) {
      scanned += 1;
      if (!needsExpiry(target, doc.data)) continue;
      picked += 1;
      plan.push({ collection: target.collection, id: doc.id, updateTime: doc.updateTime, expiresAtMs });
    }
    console.log(`  ${target.collection}: active=${scanned}, expiresAt'siz (yoziladi)=${picked}`);
  }
  if (!args.apply) { console.log(`DRY RUN — jami ${plan.length} ta yoziladi. Yozish: --apply`); return { planned: plan.length }; }
  if (!plan.length) { console.log('Yoziladigan hujjat yo\'q.'); return { planned: 0, done: 0 }; }

  fs.mkdirSync(BACKUP_DIR, { recursive: true });
  const file = path.join(BACKUP_DIR, `market_expiry_${args.project}_${new Date(nowMs).toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(file, JSON.stringify({
    kind: 'market_expiry_migration', project: args.project, createdAt: new Date(nowMs).toISOString(),
    expiresAtMs, docs: plan.map((p) => ({ collection: p.collection, id: p.id, oldExpiresAt: null, updateTime: isoOf(p.updateTime) })),
  }, null, 1));
  console.log(`Backup: ${file}`);

  const res = await commitInChunks(store, plan, 'yozildi');
  // Текширув: қайта ўқиб, нечтасида қийматимиз турибди.
  let verified = 0;
  for (const target of TARGETS) {
    const ids = plan.filter((p) => p.collection === target.collection).map((p) => p.id);
    for (let i = 0; i < ids.length; i += 100) {
      const got = await store.getMany(target.collection, ids.slice(i, i + 100));
      verified += got.filter((g) => g.exists && g.expiresAtMs === expiresAtMs).length;
    }
  }
  console.log(`Natija: yozildi=${res.done}/${plan.length}, tekshiruv=${verified}, xato chunk=${res.failedChunks}`);
  console.log(`ROLLBACK: node functions/tools/migrate_market_expiry.js --project ${args.project} --rollback "${file}" --apply`);
  if (res.failedChunks) process.exitCode = 1;
  return { planned: plan.length, done: res.done, verified, backup: file };
}

async function rollback(store, args) {
  const bk = JSON.parse(fs.readFileSync(path.resolve(args.rollback), 'utf8'));
  if (bk.kind !== 'market_expiry_migration' || bk.project !== args.project) throw new Error('Backup boshqa loyiha/tur uchun');
  console.log(`ROLLBACK ${args.apply ? 'APPLY' : 'DRY RUN'} — ${bk.docs.length} ta hujjat, faqat expiresAt == ${new Date(bk.expiresAtMs).toISOString()} bo'lsa`);
  const writes = [];
  for (const target of TARGETS) {
    const ids = bk.docs.filter((d) => d.collection === target.collection).map((d) => d.id);
    for (let i = 0; i < ids.length; i += 100) {
      const got = await store.getMany(target.collection, ids.slice(i, i + 100));
      for (const g of got) {
        if (g.exists && g.expiresAtMs === bk.expiresAtMs) {
          writes.push({ collection: target.collection, id: g.id, updateTime: g.updateTime, expiresAtMs: null });
        }
      }
    }
  }
  console.log(`  qaytariladi (expiresAt o'chiriladi): ${writes.length}; o'tkazib yuborildi (keyin o'zgargan/yo'q): ${bk.docs.length - writes.length}`);
  if (!args.apply) return { planned: writes.length };
  const res = await commitInChunks(store, writes, 'qaytarildi');
  if (res.failedChunks) process.exitCode = 1;
  return { planned: writes.length, done: res.done };
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

module.exports = { parseArgs, needsExpiry, main, TARGETS, DAYS };
