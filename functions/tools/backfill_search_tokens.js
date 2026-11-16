/**
 * Сервер қидируви (2026-11-16): мавжуд `tv_shop_items` / `realty_listings` ҳужжатларига `searchTokens` ёзиш.
 * Токенлар — `functions/market_search_tokens.js` (триггерлар билан бир хил функция).
 *
 *   node functions/tools/backfill_search_tokens.js --project <id> --collection tv_shop_items|realty_listings|all          # DRY RUN
 *   node functions/tools/backfill_search_tokens.js --project <id> --collection all --apply                                 # ёзади
 *   ADC йўқ машинада: GCLOUD_ACCESS_TOKEN=$(gcloud auth print-access-token) → Firestore REST (`:runQuery` / `:commit`).
 *   Эмулятор: FIRESTORE_EMULATOR_HOST=127.0.0.1:<port> ... --project demo-xxx
 *
 *   - `--project` шарт (сукут йўқ — prod'га адашиб ёзилмасин). Сукут — DRY RUN (ҳеч нарса ёзилмайди).
 *   - `--apply`: фақат `searchTokens` йўқ ёки фарқли ҳужжатлар; фақат шу майдон (updateMask / update),
 *     шарт `updateTime` (орада ўзгарган ҳужжат — ўтказиб юборилади, қайта ишга туширинг); batch ≤ 400.
 *   - Аввал backup: `functions/tools/backup/search_tokens_<project>_<ts>.json` (id + эски searchTokens|null).
 *     Rollback зарурати паст (майдонни ҳеч бир мавжуд сўров ўқимайди); керак бўлса backup'дан тиклаш мумкин.
 *   - Қайта ишга туширилса — тенг ҳужжатлар тегилмайди (идемпотент).
 *   - Эслатма: ёзувлар onShopItemModeration / onRealtyListingActivated ни уйғотади — улар токен ёзувини
 *     контент таҳрири ёки фаоллашув деб ҳисобламайди (status/контент ўзгармайди).
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { SOURCES, sameTokens } = require('../market_search_tokens');

const PAGE = 400;
const BACKUP_DIR = path.join(__dirname, 'backup');
const COLLECTIONS = Object.keys(SOURCES);

function parseArgs(argv) {
  const val = (flag) => {
    const i = argv.indexOf(flag);
    if (i < 0) return null;
    return argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : '';
  };
  const out = { apply: argv.includes('--apply'), project: val('--project'), collection: val('--collection') || 'all' };
  if (!out.project) throw new Error('--project <id> shart');
  if (out.collection !== 'all' && !COLLECTIONS.includes(out.collection)) {
    throw new Error(`--collection: ${COLLECTIONS.join('|')}|all`);
  }
  out.targets = out.collection === 'all' ? COLLECTIONS : [out.collection];
  return out;
}

function sdkStore(project) {
  const admin = require('firebase-admin');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) admin.initializeApp({ projectId: project });
    else admin.initializeApp({ projectId: project, credential: admin.credential.applicationDefault() });
  }
  const db = admin.firestore();
  return {
    label: process.env.FIRESTORE_EMULATOR_HOST ? `emulator ${process.env.FIRESTORE_EMULATOR_HOST}` : 'PRODUCTION (Admin SDK)',
    async* list(collection) {
      const fields = [...SOURCES[collection].fields, 'searchTokens'];
      let last = null;
      for (;;) {
        let q = db.collection(collection).select(...fields)
          .orderBy(admin.firestore.FieldPath.documentId()).limit(PAGE);
        if (last) q = q.startAfter(last);
        const snap = await q.get();
        for (const doc of snap.docs) yield { id: doc.id, updateTime: doc.updateTime, data: doc.data() || {} };
        if (snap.size < PAGE) break;
        last = snap.docs[snap.docs.length - 1];
      }
    },
    async commit(writes) {
      const batch = db.batch();
      for (const w of writes) {
        batch.update(db.collection(w.collection).doc(w.id), { searchTokens: w.tokens }, { lastUpdateTime: w.updateTime });
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
  const plain = (v) => {
    if (!v) return undefined;
    if (v.stringValue !== undefined) return v.stringValue;
    if (v.arrayValue) return (v.arrayValue.values || []).map(plain);
    if (v.nullValue !== undefined) return null;
    return v.integerValue !== undefined ? v.integerValue : v.booleanValue; // токен/матн эмас — фарқли деб ҳисобланади
  };
  return {
    label: 'PRODUCTION (REST)',
    async* list(collection) {
      const fields = [...SOURCES[collection].fields, 'searchTokens'];
      let cursor = null;
      for (;;) {
        const structuredQuery = {
          from: [{ collectionId: collection }],
          select: { fields: fields.map((f) => ({ fieldPath: f })) },
          orderBy: [{ field: { fieldPath: '__name__' }, direction: 'ASCENDING' }],
          limit: PAGE,
          ...(cursor ? { startAt: { values: [{ referenceValue: cursor }], before: false } } : {}),
        };
        const rows = (await post(`${base}:runQuery`, { structuredQuery })).filter((r) => r.document);
        for (const r of rows) {
          const f = r.document.fields || {};
          const data = {};
          for (const k of fields) if (f[k] !== undefined) data[k] = plain(f[k]);
          yield { id: r.document.name.split('/').pop(), updateTime: r.document.updateTime, data };
        }
        if (rows.length < PAGE) break;
        cursor = rows[rows.length - 1].document.name;
      }
    },
    async commit(writes) {
      await post(`${base}:commit`, {
        writes: writes.map((w) => ({
          update: {
            name: `${root}/${w.collection}/${w.id}`,
            fields: { searchTokens: { arrayValue: { values: w.tokens.map((t) => ({ stringValue: t })) } } },
          },
          updateMask: { fieldPaths: ['searchTokens'] },
          currentDocument: { updateTime: w.updateTime },
        })),
      });
    },
  };
}

async function main(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  const store = (!process.env.FIRESTORE_EMULATOR_HOST && process.env.GCLOUD_ACCESS_TOKEN)
    ? restStore(args.project, process.env.GCLOUD_ACCESS_TOKEN)
    : sdkStore(args.project);
  console.log(`Loyiha: ${args.project} | ${store.label} | ${args.apply ? 'APPLY' : 'DRY RUN'} | ${args.targets.join(', ')}`);

  const plan = [];
  for (const collection of args.targets) {
    let scanned = 0;
    let missing = 0;
    for await (const doc of store.list(collection)) {
      scanned += 1;
      const next = SOURCES[collection].build(doc.data);
      if (sameTokens(doc.data.searchTokens, next)) continue;
      if (!Array.isArray(doc.data.searchTokens)) missing += 1;
      plan.push({
        collection, id: doc.id, updateTime: doc.updateTime, tokens: next,
        prev: doc.data.searchTokens === undefined ? null : doc.data.searchTokens,
      });
    }
    console.log(`  ${collection}: ko'rildi ${scanned}, yoziladi ${plan.filter((p) => p.collection === collection).length} (yo'q: ${missing})`);
  }
  if (!args.apply || plan.length === 0) {
    if (!args.apply) console.log('DRY RUN — hech narsa yozilmadi. Yozish: --apply');
    return { planned: plan.length, done: 0, backup: null };
  }

  fs.mkdirSync(BACKUP_DIR, { recursive: true });
  const file = path.join(BACKUP_DIR, `search_tokens_${args.project}_${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(file, JSON.stringify({
    kind: 'search_tokens_backfill', project: args.project, at: new Date().toISOString(),
    docs: plan.map((p) => ({ collection: p.collection, id: p.id, searchTokens: p.prev })),
  }, null, 1));
  console.log(`Backup: ${file}`);

  let done = 0;
  let failedChunks = 0;
  for (let i = 0; i < plan.length; i += PAGE) {
    const chunk = plan.slice(i, i + PAGE);
    try {
      await store.commit(chunk);
      done += chunk.length;
    } catch (e) {
      failedChunks += 1;
      console.error(`  chunk ${i / PAGE + 1} XATO (hech narsa yozilmadi, qayta ishga tushiring): ${e.message || e}`);
    }
    console.log(`  ${done}/${plan.length}`);
  }
  console.log(`Tayyor: ${done}/${plan.length} yozildi, xato chunk: ${failedChunks}`);
  return { planned: plan.length, done, failedChunks, backup: file };
}

if (require.main === module) {
  main().catch((e) => { console.error(e.message || e); process.exit(1); });
}

module.exports = { parseArgs, main, PAGE };
