/**
 * «AVA Супермаркет» намуналари (эга 2026-11-28): эски 59 та «AVA» platform_products ҳужжатида `smGroupId` ЙЎҚ —
 * шунинг учун mark_supermarket_samples.js 0 та белгилайди. Бу восита ҳар бир маҳсулот НОМИНИ жорий
 * `taxonomy/supermarket` гуруҳлари (номлар + synonyms) билан солиштириб `smGroupId` + `smCategoryId` ёзади
 * (upsertOfferTx ҳам иккаласини ёзади; мижоз smCategoryId бўлмаса гуруҳдан олади, ҳисобот — smCategoryId'дан).
 * Бошқа майдонга (нарх, unit, stock, active, smStatus, smSample) ТЕГИЛМАЙДИ. Кейинги қадам — mark_supermarket_samples.js.
 *
 * Мослаштириш (тоза функция `matchProduct`):
 *   - кўп сўзли ибора (гуруҳ номи ёки synonym, масалан «кўк чой», «пахта ёғи») — 3 балл;
 *   - бир сўзли гуруҳ номи — 2; бир сўзли synonym — 1; бир нечта гуруҳда учрайдиган сўз («чой», «ёғ», «посуда») — 0.5;
 *   - ALIASES (пастда; эга 2026-11-28 тасдиқлади — CONFIRMED) — 3;
 *   - сўз охиридаги ўзбекча қўшимча (-и, -си, -ни, -лар, ...) қабул қилинади: «уни» = «ун», «чойи» = «чой»;
 *   - энг юқори балл ягона ва ≥ 1 бўлса — мос; тенг бўлса AMBIGUOUS, йўқ бўлса NO_MATCH → ТЕГИЛМАЙДИ, рўйхатда чиқади;
 *   - EXCLUDE сўзи бор ном («тузланган», «қуриқ», ...) — EXCLUDED (фақат `--map` билан);
 *   - `--map <file.json>` — қўлда: {"<productId>": "<groupId>"} (мослаштиришдан устун) ёки {"<productId>": null} (тегилмасин).
 *
 * Нишон: platform_products; `smGroupId` ёки `smPartnerKey` БОР ҳужжат — SKIP (идемпотент: қайта ишга тушса 0 ёзув).
 *
 * Хавфсизлик (27, 28, 41-банд):
 *   - DRY RUN — сукут (фақат ўқийди, жадвал чиқаради). `--project <id>` МАЖБУРИЙ.
 *   - `--apply`: аввал backup JSON (`functions/tools/backup/sm_sample_groups_<project>_<ts>.json`), кейин партиялар
 *     (≤200), ҳар ёзувда `updateTime` шарти (орада ўзгарган ҳужжат ёзилмайди), ҳар ҳужжатга admin_audit, якунда текширув.
 *   - Rollback: `--rollback <backup.json> [--apply]` — фақат майдонлар ҳозир айнан шу скрипт ёзган қийматга тенг ва
 *     `smSample !== true` бўлса олиб ташлайди (намуна бўлса — аввал mark_supermarket_samples.js --undo --apply).
 *
 *   node functions/tools/assign_supermarket_sample_groups.js --project <id>                      # DRY RUN
 *   node functions/tools/assign_supermarket_sample_groups.js --project <id> --map m.json         # DRY RUN + қўлда
 *   node functions/tools/assign_supermarket_sample_groups.js --project <id> [--map m.json] --apply
 *   node functions/tools/assign_supermarket_sample_groups.js --project <id> --rollback <f> [--apply]
 *   node functions/tools/assign_supermarket_sample_groups.js --project <id> --taxonomy-file <v.json>  # DRY RUN: prod маҳсулотлари
 *        + ФАЙЛДАГИ таксономия (янги гуруҳларни олдиндан кўриш). --apply билан ТАҚИҚЛАНГАН — ёзув фақат prod таксономия бўйича.
 *   ADC йўқ машинада: $env:GCLOUD_ACCESS_TOKEN = (gcloud auth print-access-token) — Firestore REST (токен лог'га чиқмайди).
 *   Эмулятор: FIRESTORE_EMULATOR_HOST=127.0.0.1:<port> ... --project demo-xxx
 */
'use strict';

const fs = require('fs');
const path = require('path');

const COLLECTION = 'platform_products';
const TAXONOMY_PATH = 'taxonomy/supermarket';
const PAGE = 200;
const KIND = 'supermarket_sample_group_assign';
const ACTOR = 'tool:assign_supermarket_sample_groups';
const BACKUP_DIR = path.join(__dirname, 'backup');

/**
 * Таксономияда йўқ, лекин «AVA» маҳсулот номларида учрайдиган сўзлар → гуруҳ.
 * CONFIRMED (эга 2026-11-28: «тўғри»): «семичка мойи» → sunflower_oil, «мойка» → dish_wash; таксономия синоними орқали
 * «горох» → chickpea ва «Океан … ювиш гели» → laundry (synonym «гель») ҳам тасдиқланган.
 * Таксономия v2 (supermarket_taxonomy_v4.json, эга 2026-11-28 «қўш») янги гуруҳлари ўз синонимлари билан мос келади:
 * Перловка → pearl_barley, Фунчоза → funchoza, Пишевая сода → baking_soda, Гугурт / резина қўлқоп / банка қопқоғи → small_household,
 * Қуриқ қаймоқ / тузланган бодиринг / тузланган қалампир → preserves_pickles («Консерва ва тузламалар», эга «ҳа»).
 * CONFIRMED (эга 2026-11-28 «Ҳа»): «писта ёғи» (MILTER) → sunflower_oil.
 */
const ALIASES = Object.freeze({
  семичка: 'sunflower_oil',
  мойка: 'dish_wash',
  'писта ёғи': 'sunflower_oil',
  'писта мойи': 'sunflower_oil',
});

/**
 * Номда шу сўз бўлса янги (тортиладиган) сабзавот ёки совуқ сут гуруҳига тушмайди («тузланган қалампир» ≠ «Булғор
 * қалампири»): фақат калити ўзи шу сўзни ўз ичига олган гуруҳлар ҳисобланади (таксономия v2 да — preserves_pickles,
 * синонимлари «тузланган», «қуриқ», ...). Бундай гуруҳ йўқ бўлса — EXCLUDED (фақат `--map` билан).
 */
const EXCLUDE = Object.freeze(['тузланган', 'консерва', 'маринад', 'маринадланган', 'қуриқ', 'қуритилган']);

const SUFFIXES = Object.freeze(['и', 'си', 'ни', 'ы', 'лар', 'лари', 'ларни']);

/** Тоза: кичик ҳарф, ҳ→х, ь/ъ/апостроф олиб ташланади. */
function normalize(s) {
  return String(s || '').toLowerCase().replace(/ҳ/g, 'х').replace(/[ьъʻʼ‘’'`]/g, '');
}

/** Тоза: сўзлар (фақат ҳарф/рақам). */
function tokenize(s) {
  return normalize(s).split(/[^\p{L}\p{N}]+/u).filter(Boolean);
}

/** Тоза: token kw'га тенг ёки kw + рухсат этилган қўшимча. */
function tokenMatches(token, kw) {
  if (token === kw) return true;
  return token.startsWith(kw) && SUFFIXES.includes(token.slice(kw.length));
}

/** Тоза: калит ибора (сўзлар кетма-кетлиги) номда борми. */
function phraseIn(tokens, phrase) {
  for (let i = 0; i + phrase.length <= tokens.length; i += 1) {
    if (phrase.every((w, j) => tokenMatches(tokens[i + j], w))) return true;
  }
  return false;
}

/**
 * Тоза: taxonomy {categories:[{id, groups:[{id, names, synonyms}]}]} → индекс.
 * Ҳар калит: {phrase: string[], groupId, weight, via}.
 */
function buildIndex(taxonomy, aliases = ALIASES) {
  const groups = {};
  const raw = []; // {phrase, groupId, kind: 'name'|'synonym'|'alias'}
  for (const c of (taxonomy && taxonomy.categories) || []) {
    for (const g of c.groups || []) {
      groups[g.id] = { groupId: g.id, categoryId: c.id, name: (g.names && g.names.uz_Cyrl) || g.id };
      const names = g.names || {};
      for (const n of [names.uz_Cyrl, names.uz_Latn, names.ru]) if (n) raw.push({ phrase: tokenize(n), groupId: g.id, kind: 'name' });
      for (const s of g.synonyms || []) raw.push({ phrase: tokenize(s), groupId: g.id, kind: 'synonym' });
    }
  }
  for (const [word, groupId] of Object.entries(aliases || {})) {
    if (groups[groupId]) raw.push({ phrase: tokenize(word), groupId, kind: 'alias' });
  }
  // Бир сўзли калит бир нечта гуруҳда учраса — кучсиз (0.5).
  const owners = new Map();
  for (const r of raw) {
    if (r.phrase.length !== 1) continue;
    const k = r.phrase[0];
    if (!owners.has(k)) owners.set(k, new Set());
    owners.get(k).add(r.groupId);
  }
  const seen = new Set();
  const keys = [];
  for (const r of raw) {
    if (!r.phrase.length) continue;
    const id = `${r.groupId}|${r.phrase.join(' ')}`;
    if (seen.has(id)) continue;
    seen.add(id);
    let weight;
    if (r.kind === 'alias' || r.phrase.length > 1) weight = 3;
    else if (owners.get(r.phrase[0]).size > 1) weight = 0.5;
    else weight = r.kind === 'name' ? 2 : 1;
    keys.push({ phrase: r.phrase, groupId: r.groupId, weight, via: `${r.kind}:${r.phrase.join(' ')}` });
  }
  return { groups, keys };
}

/**
 * Тоза: номни гуруҳга мослаштириш.
 * → {groupId, categoryId, score, via[]} | {groupId: null, reason: 'NO_MATCH'|'AMBIGUOUS', candidates[]}
 */
function matchProduct(name, index) {
  const tokens = tokenize(name);
  const excluded = tokens.find((t) => EXCLUDE.includes(t));
  const score = new Map();
  const via = new Map();
  for (const k of index.keys) {
    if (excluded && !k.phrase.some((w) => EXCLUDE.includes(w))) continue; // фақат консерва/тузлама калитлари
    if (!phraseIn(tokens, k.phrase)) continue;
    score.set(k.groupId, (score.get(k.groupId) || 0) + k.weight);
    if (!via.has(k.groupId)) via.set(k.groupId, []);
    via.get(k.groupId).push(k.via);
  }
  const ranked = [...score.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  const candidates = ranked.map(([g, s]) => `${g}:${s}`);
  if (excluded && (!ranked.length || ranked[0][1] < 1)) return { groupId: null, reason: `EXCLUDED:${excluded}`, candidates };
  if (!ranked.length || ranked[0][1] < 1) return { groupId: null, reason: 'NO_MATCH', candidates };
  if (ranked.length > 1 && ranked[1][1] === ranked[0][1]) return { groupId: null, reason: 'AMBIGUOUS', candidates };
  const g = index.groups[ranked[0][0]];
  return { groupId: g.groupId, categoryId: g.categoryId, score: ranked[0][1], via: via.get(g.groupId), candidates };
}

/**
 * Тоза: режа. docs: [{id, name, smGroupId?, smPartnerKey?, updateTime}], overrides: {id: groupId|null}.
 * → rows [{id, name, action: 'ASSIGN'|'SKIP_HAS_GROUP'|'SKIP_PARTNER'|'SKIP_MAP_NULL'|'UNMATCHED', groupId?, categoryId?, source, detail}]
 */
function planAssign(docs, taxonomy, overrides = {}, aliases = ALIASES) {
  const index = buildIndex(taxonomy, aliases);
  for (const [id, g] of Object.entries(overrides || {})) {
    if (g !== null && !index.groups[g]) throw new Error(`--map: ${id} → «${g}» taxonomy/supermarket'да йўқ (GROUP_UNKNOWN)`);
  }
  return docs.map((d) => {
    const base = { id: d.id, name: d.name || '', updateTime: d.updateTime };
    if (typeof d.smPartnerKey === 'string' && d.smPartnerKey) return { ...base, action: 'SKIP_PARTNER', source: '-', detail: '' };
    if (typeof d.smGroupId === 'string' && d.smGroupId.trim()) return { ...base, action: 'SKIP_HAS_GROUP', source: '-', detail: d.smGroupId };
    if (Object.prototype.hasOwnProperty.call(overrides || {}, d.id)) {
      const g = overrides[d.id];
      if (g === null) return { ...base, action: 'SKIP_MAP_NULL', source: 'map', detail: '' };
      return { ...base, action: 'ASSIGN', groupId: g, categoryId: index.groups[g].categoryId, source: 'map', detail: '' };
    }
    const m = matchProduct(d.name, index);
    if (!m.groupId) return { ...base, action: 'UNMATCHED', source: 'auto', detail: `${m.reason}${m.candidates.length ? ` (${m.candidates.join(', ')})` : ''}` };
    return { ...base, action: 'ASSIGN', groupId: m.groupId, categoryId: m.categoryId, source: 'auto', detail: `${m.score} [${m.via.join('; ')}]` };
  });
}

/** Тоза: rollback ёзувлари — фақат ҳозирги қиймат скрипт ёзганига тенг ва намуна эмас. */
function planRollback(backupDocs, current) {
  const byId = new Map(current.map((c) => [c.id, c]));
  const writes = [];
  const skipped = [];
  for (const b of backupDocs) {
    const c = byId.get(b.id);
    if (!c || !c.exists) { skipped.push({ id: b.id, why: 'MISSING' }); continue; }
    if (c.smSample === true) { skipped.push({ id: b.id, why: 'IS_SAMPLE (аввал mark_supermarket_samples.js --undo --apply)' }); continue; }
    if (c.smGroupId !== b.after.smGroupId || c.smCategoryId !== b.after.smCategoryId) { skipped.push({ id: b.id, why: 'CHANGED_SINCE' }); continue; }
    writes.push({ id: b.id, updateTime: c.updateTime });
  }
  return { writes, skipped };
}

// ─── Firestore қатлами: Admin SDK ёки REST ───

function sdkStore(project) {
  const admin = require('firebase-admin');
  if (!admin.apps.length) admin.initializeApp({ projectId: project });
  const db = admin.firestore();
  const FV = admin.firestore.FieldValue;
  const pick = (s) => {
    const d = s.data() || {};
    return { id: s.id, exists: s.exists, updateTime: s.exists ? s.updateTime : null, name: d.name, smGroupId: d.smGroupId, smCategoryId: d.smCategoryId, smPartnerKey: d.smPartnerKey, smSample: d.smSample };
  };
  return {
    label: process.env.FIRESTORE_EMULATOR_HOST ? `emulator ${process.env.FIRESTORE_EMULATOR_HOST}` : 'PRODUCTION (Admin SDK)',
    async taxonomy() { const s = await db.doc(TAXONOMY_PATH).get(); return s.exists ? s.data() : null; },
    async listAll() { return (await db.collection(COLLECTION).get()).docs.map(pick); },
    async getMany(ids) { return ids.length ? (await db.getAll(...ids.map((id) => db.collection(COLLECTION).doc(id)))).map(pick) : []; },
    /** ops: [{id, updateTime, set: {smGroupId, smCategoryId} | null (= олиб ташлаш), audit}] */
    async commit(ops) {
      const b = db.batch();
      for (const o of ops) {
        const patch = o.set ? { ...o.set } : { smGroupId: FV.delete(), smCategoryId: FV.delete() };
        patch.updatedAt = FV.serverTimestamp();
        b.update(db.collection(COLLECTION).doc(o.id), patch, { lastUpdateTime: o.updateTime });
        b.set(db.collection('admin_audit').doc(), { ...o.audit, at: FV.serverTimestamp() });
      }
      await b.commit();
    },
  };
}

function restStore(project, token) {
  const root = `projects/${project}/databases/(default)/documents`;
  const base = `https://firestore.googleapis.com/v1/${root}`;
  const headers = { Authorization: `Bearer ${token}`, 'x-goog-user-project': project, 'Content-Type': 'application/json' };
  const call = async (url, body) => {
    const res = await fetch(url, body ? { method: 'POST', headers, body: JSON.stringify(body) } : { headers });
    if (res.status === 404 && !body) return null;
    if (res.status !== 200) throw new Error(`HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
    return res.json();
  };
  const fv = (v) => {
    if (!v) return undefined;
    if ('stringValue' in v) return v.stringValue;
    if ('booleanValue' in v) return v.booleanValue;
    if ('integerValue' in v) return Number(v.integerValue);
    if ('doubleValue' in v) return v.doubleValue;
    if ('nullValue' in v) return null;
    if ('timestampValue' in v) return v.timestampValue;
    if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k, x]) => [k, fv(x)]));
    if ('arrayValue' in v) return (v.arrayValue.values || []).map(fv);
    return undefined;
  };
  const toV = (x) => {
    if (x === null) return { nullValue: null };
    if (typeof x === 'string') return { stringValue: x };
    if (typeof x === 'boolean') return { booleanValue: x };
    if (Number.isInteger(x)) return { integerValue: String(x) };
    if (typeof x === 'number') return { doubleValue: x };
    if (Array.isArray(x)) return { arrayValue: { values: x.map(toV) } };
    return { mapValue: { fields: Object.fromEntries(Object.entries(x).map(([k, y]) => [k, toV(y)])) } };
  };
  const pick = (doc) => {
    const f = doc.fields || {};
    return { id: doc.name.split('/').pop(), exists: true, updateTime: doc.updateTime, name: fv(f.name), smGroupId: fv(f.smGroupId), smCategoryId: fv(f.smCategoryId), smPartnerKey: fv(f.smPartnerKey), smSample: fv(f.smSample) };
  };
  return {
    label: 'PRODUCTION (REST)',
    async taxonomy() { const j = await call(`${base}/${TAXONOMY_PATH}`); return j ? fv({ mapValue: { fields: j.fields || {} } }) : null; },
    async listAll() {
      const out = [];
      let pageToken = '';
      for (;;) {
        const j = await call(`${base}/${COLLECTION}?pageSize=300${pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : ''}`);
        for (const d of (j && j.documents) || []) out.push(pick(d));
        if (!j || !j.nextPageToken) break;
        pageToken = j.nextPageToken;
      }
      return out;
    },
    async getMany(ids) {
      if (!ids.length) return [];
      const out = await call(`${base}:batchGet`, { documents: ids.map((id) => `${root}/${COLLECTION}/${id}`) });
      return out.map((r) => (r.found ? pick(r.found) : { id: String(r.missing).split('/').pop(), exists: false }));
    },
    async commit(ops) {
      const writes = [];
      for (const o of ops) {
        writes.push({
          update: { name: `${root}/${COLLECTION}/${o.id}`, fields: o.set ? { smGroupId: toV(o.set.smGroupId), smCategoryId: toV(o.set.smCategoryId) } : {} },
          updateMask: { fieldPaths: ['smGroupId', 'smCategoryId'] },
          updateTransforms: [{ fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME' }],
          currentDocument: { updateTime: o.updateTime },
        });
        writes.push({
          update: { name: `${root}/admin_audit/${o.auditId}`, fields: toV(o.audit).mapValue.fields },
          updateTransforms: [{ fieldPath: 'at', setToServerValue: 'REQUEST_TIME' }],
          currentDocument: { exists: false },
        });
      }
      await call(`${base}:commit`, { writes });
    },
  };
}

function isoOf(v) {
  return typeof v === 'string' ? v : (v && v.toDate ? v.toDate().toISOString() : null);
}

async function commitInChunks(store, ops, label) {
  let done = 0;
  let failedChunks = 0;
  for (let i = 0; i < ops.length; i += PAGE) {
    const chunk = ops.slice(i, i + PAGE);
    try {
      await store.commit(chunk);
      done += chunk.length;
    } catch (e) {
      failedChunks += 1;
      console.error(`  ${label}: chunk ${i / PAGE + 1} XATO (hech narsa yozilmadi, qayta ishga tushiring): ${e.message || e}`);
    }
    console.log(`  ${label}: ${done}/${ops.length}`);
  }
  return { done, failedChunks };
}

/** Таксономия файли ({categories}) — фақат симуляция (DRY RUN). */
function loadTaxonomyFile(file) {
  const t = JSON.parse(fs.readFileSync(path.resolve(file), 'utf8'));
  if (!t || !Array.isArray(t.categories)) throw new Error('--taxonomy-file: {categories:[...]} kerak');
  return t;
}

function loadMap(file) {
  if (!file) return {};
  const m = JSON.parse(fs.readFileSync(path.resolve(file), 'utf8'));
  if (!m || typeof m !== 'object' || Array.isArray(m)) throw new Error('--map: {"productId": "groupId"|null} JSON kerak');
  return m;
}

async function assign(store, args, { backupDir = BACKUP_DIR, now = Date.now() } = {}) {
  console.log(`${args.apply ? 'APPLY' : 'DRY RUN'} — loyiha ${args.project} (${store.label})`);
  const prodTaxonomy = await store.taxonomy();
  if (!prodTaxonomy) throw new Error(`${TAXONOMY_PATH} йўқ — аввал seed_supermarket.js`);
  const taxonomy = args.taxonomyFile ? loadTaxonomyFile(args.taxonomyFile) : prodTaxonomy;
  if (args.taxonomyFile) console.log(`SIMULYATSIYA: taksonomiya fayldan (${args.taxonomyFile}); prod taxonomy/supermarket v${prodTaxonomy.version || '?'}`);
  const docs = await store.listAll();
  const rows = planAssign(docs, taxonomy, loadMap(args.map));
  const groupName = buildIndex(taxonomy).groups;
  const sorted = [...rows].sort((a, b) => a.action.localeCompare(b.action) || String(a.groupId || '').localeCompare(String(b.groupId || '')) || a.name.localeCompare(b.name));
  for (const r of sorted) {
    const tgt = r.groupId ? `${r.categoryId}/${r.groupId} (${groupName[r.groupId].name})` : '';
    console.log(`  ${r.action.padEnd(14)} ${r.id} · ${r.name}${tgt ? ` → ${tgt}` : ''} · ${r.source} ${r.detail}`);
  }
  const count = (a) => rows.filter((r) => r.action === a).length;
  const plan = rows.filter((r) => r.action === 'ASSIGN');
  console.log(`Jami ${rows.length}: ASSIGN=${plan.length}, UNMATCHED=${count('UNMATCHED')}, SKIP_HAS_GROUP=${count('SKIP_HAS_GROUP')}, SKIP_PARTNER=${count('SKIP_PARTNER')}, SKIP_MAP_NULL=${count('SKIP_MAP_NULL')}`);
  if (!args.apply) { console.log('DRY RUN — hech narsa yozilmadi. Yozish: --apply'); return { rows, planned: plan.length }; }
  if (!plan.length) { console.log('Yoziladigan hujjat yo\'q.'); return { rows, planned: 0, done: 0 }; }

  fs.mkdirSync(backupDir, { recursive: true });
  const stamp = new Date(now).toISOString().replace(/[:.]/g, '-');
  const file = path.join(backupDir, `sm_sample_groups_${args.project}_${stamp}.json`);
  fs.writeFileSync(file, JSON.stringify({
    kind: KIND, project: args.project, createdAt: new Date(now).toISOString(), taxonomyVersion: taxonomy.version || null,
    docs: plan.map((p) => ({ id: p.id, name: p.name, before: { smGroupId: null, smCategoryId: null }, after: { smGroupId: p.groupId, smCategoryId: p.categoryId }, source: p.source, updateTime: isoOf(p.updateTime) })),
  }, null, 1));
  console.log(`Backup: ${file}`);

  const ops = plan.map((p) => ({
    id: p.id, updateTime: p.updateTime, set: { smGroupId: p.groupId, smCategoryId: p.categoryId },
    auditId: `${KIND}_${stamp}_${p.id}`,
    audit: { kind: KIND, actor: ACTOR, target: `${COLLECTION}/${p.id}`, before: null, after: { smGroupId: p.groupId, smCategoryId: p.categoryId }, reason: `${p.source}; taxonomy v${taxonomy.version || '?'}` },
  }));
  const res = await commitInChunks(store, ops, 'yozildi');
  const got = await store.getMany(plan.map((p) => p.id));
  const want = new Map(plan.map((p) => [p.id, p.groupId]));
  const verified = got.filter((g) => g.exists && g.smGroupId === want.get(g.id)).length;
  console.log(`Natija: yozildi=${res.done}/${plan.length}, tekshiruv=${verified}, xato chunk=${res.failedChunks}`);
  console.log(`ROLLBACK: node functions/tools/assign_supermarket_sample_groups.js --project ${args.project} --rollback "${file}" --apply`);
  if (res.failedChunks) process.exitCode = 1;
  return { rows, planned: plan.length, done: res.done, verified, backup: file };
}

async function rollback(store, args, { now = Date.now() } = {}) {
  const bk = JSON.parse(fs.readFileSync(path.resolve(args.rollback), 'utf8'));
  if (bk.kind !== KIND || bk.project !== args.project) throw new Error('Backup boshqa loyiha/tur uchun');
  const current = await store.getMany(bk.docs.map((d) => d.id));
  const { writes, skipped } = planRollback(bk.docs, current);
  for (const s of skipped) console.log(`  SKIP ${s.id}: ${s.why}`);
  console.log(`ROLLBACK ${args.apply ? 'APPLY' : 'DRY RUN'} — qaytariladi: ${writes.length}; o'tkazib yuborildi: ${skipped.length}`);
  if (!args.apply || !writes.length) return { planned: writes.length, skipped: skipped.length };
  const stamp = new Date(now).toISOString().replace(/[:.]/g, '-');
  const ops = writes.map((w) => ({
    id: w.id, updateTime: w.updateTime, set: null, auditId: `${KIND}_undo_${stamp}_${w.id}`,
    audit: { kind: KIND, actor: ACTOR, target: `${COLLECTION}/${w.id}`, before: 'assigned', after: null, reason: 'rollback' },
  }));
  const res = await commitInChunks(store, ops, 'qaytarildi');
  if (res.failedChunks) process.exitCode = 1;
  return { planned: writes.length, done: res.done, skipped: skipped.length };
}

function parseArgs(argv) {
  const val = (flag) => {
    const i = argv.indexOf(flag);
    if (i < 0) return undefined;
    return argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : '';
  };
  return { apply: argv.includes('--apply'), project: val('--project'), map: val('--map'), rollback: val('--rollback'), taxonomyFile: val('--taxonomy-file') };
}

async function main(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  if (!args.project) throw new Error('--project <id> majburiy (DRY RUN сукут, --apply — ёзиш)');
  if (args.map === '') throw new Error('--map <file.json> fayli berilmadi');
  if (args.rollback === '') throw new Error('--rollback <backup.json> fayli berilmadi');
  if (args.taxonomyFile === '') throw new Error('--taxonomy-file <v.json> fayli berilmadi');
  if (args.taxonomyFile && (args.apply || args.rollback)) throw new Error('--taxonomy-file faqat DRY RUN uchun (--apply/--rollback bilan emas): avval taksonomiyani prodga ko\'taring');
  const store = (!process.env.FIRESTORE_EMULATOR_HOST && process.env.GCLOUD_ACCESS_TOKEN)
    ? restStore(args.project, process.env.GCLOUD_ACCESS_TOKEN)
    : sdkStore(args.project);
  return args.rollback ? rollback(store, args) : assign(store, args);
}

if (require.main === module) {
  main().catch((e) => { console.error(e.message || e); process.exit(1); });
}

module.exports = { ALIASES, EXCLUDE, normalize, tokenize, tokenMatches, buildIndex, matchProduct, planAssign, planRollback, parseArgs, main };
