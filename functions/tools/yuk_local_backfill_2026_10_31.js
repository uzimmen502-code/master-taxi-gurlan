/**
 * yuk_local аудит тузатишлари учун БИР МАРТАЛИК маълумот тайёрлаш (2026-10-31).
 * Сервер триггери (`onYukLocalDriverWrite`) deploy қилинишидан ОЛДИН ишга туширилади.
 *
 *   A. `yuk_local_owner_state/{ownerId}` — эълон берган эгалар (мавжуд эълонлар +
 *      `yuk_local_owner_meta.everPublished`): уларнинг кейинги эълони 10 кун бўлади
 *      (биринчи эълон 60 кун қоидаси сервер ҳолатига кўчди).
 *   B. Намуналар (`isDemo`, координаталари seed'да «Гурлан») — `districtId: gurlan`,
 *      `regionId: xorazm` (аввал туман йўқ эди → ҳар бир туманда кўринарди, O-4).
 *   C. Муддатсиз эски ҳақиқий эълон — `expiresAt` = ҳозир + 30 кун (узайтириш
 *      муддати; эгаси 3/2/1 кун пушларини олади ва узайтира олади), O-3.
 *   D. Эски телефон-ID эълон: тумани 'yashnobod' (Тошкент), GPS эса Гурлан
 *      намуналари қутисида (41.80–41.92 N, 60.33–60.45 E) → 'gurlan' (эга қарори:
 *      туман GPS'дан, O-5). INFERRED: Гурлан намуналари билан бир ҳудуд.
 *   E. `districtId` йўқ ҳақиқий эълонлар → '' (аниқ сўров учун).
 *
 *   node yuk_local_backfill_2026_10_31.js            — DRY-RUN (ҳеч нарса ёзмайди)
 *   node yuk_local_backfill_2026_10_31.js --apply    — backup + ёзиш + текширув
 *   node yuk_local_backfill_2026_10_31.js --rollback <backup.json>
 * Ҳисобот телефонларни ниқоблайди. SA=<service-account.json> (ихтиёрий).
 */
'use strict';
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const SA = process.env.SA || path.join(__dirname, '..', 'service-account.json');
admin.initializeApp({ credential: admin.credential.cert(require(SA)) });
const db = admin.firestore();
const { FieldValue, Timestamp } = admin.firestore;
const DAY = 24 * 60 * 60 * 1000;
const RUN_ID = new Date().toISOString().replace(/[:.]/g, '-');
const BACKUP_DIR = process.env.BACKUP_DIR || path.join(__dirname, 'backup');

const digits = (v) => String(v || '').replace(/\D/g, '');
const canon = (v) => { const d = digits(v); return d.length === 9 ? `998${d}` : d; };
const mask = (v) => { const s = String(v || ''); return s.length > 4 ? `***${s.slice(-4)}` : s; };
const inGurlanBox = (x) => typeof x.lat === 'number' && typeof x.lng === 'number'
  && x.lat >= 41.80 && x.lat <= 41.92 && x.lng >= 60.33 && x.lng <= 60.45;

async function plan() {
  const [drivers, metas, states] = await Promise.all([
    db.collection('yuk_local_drivers').get(),
    db.collection('yuk_local_owner_meta').get(),
    db.collection('yuk_local_owner_state').get(),
  ]);
  const haveState = new Set(states.docs.map((d) => d.id));
  const owners = new Map();
  const ops = [];
  for (const doc of drivers.docs) {
    const x = doc.data();
    if (x.isDemo === true) {
      if (!String(x.districtId || '').trim()) {
        ops.push({ kind: 'B', ref: doc.ref, patch: { districtId: 'gurlan', regionId: 'xorazm' }, before: { districtId: x.districtId ?? null, regionId: x.regionId ?? null } });
      }
      continue;
    }
    const o = canon(x.ownerId);
    if (o.length >= 9) owners.set(o, (owners.get(o) || 0) + 1);
    const patch = {};
    const before = {};
    if (!x.expiresAt) { patch.expiresAt = Timestamp.fromMillis(Date.now() + 30 * DAY); before.expiresAt = null; }
    if (x.districtId === 'yashnobod' && /^\d{9,}$/.test(doc.id) && inGurlanBox(x)) {
      patch.districtId = 'gurlan'; patch.regionId = 'xorazm';
      before.districtId = x.districtId; before.regionId = x.regionId ?? null;
    } else if (typeof x.districtId !== 'string') {
      patch.districtId = ''; before.districtId = null;
    }
    if (Object.keys(patch).length) ops.push({ kind: patch.expiresAt ? 'C' : 'D/E', ref: doc.ref, patch, before });
  }
  for (const m of metas.docs) {
    if (m.data().everPublished === true) {
      const o = canon(m.id);
      if (o.length >= 9 && !owners.has(o)) owners.set(o, 0);
    }
  }
  for (const [o, n] of owners) {
    if (haveState.has(o)) continue;
    ops.push({ kind: 'A', ref: db.collection('yuk_local_owner_state').doc(o), create: true,
      patch: { ownerId: o, listingsCreated: n, backfilledAt: FieldValue.serverTimestamp(), source: 'backfill-2026-10-31' } });
  }
  return ops;
}

function describe(op) {
  const id = op.ref.id;
  const shownId = /^\d{9,}$/.test(id) ? mask(id) : id;
  const p = { ...op.patch };
  if (p.ownerId) p.ownerId = mask(p.ownerId);
  if (p.expiresAt && p.expiresAt.toDate) p.expiresAt = p.expiresAt.toDate().toISOString();
  if (p.backfilledAt) p.backfilledAt = '<server>';
  return `${op.kind}  ${op.ref.parent.id}/${shownId}  ${JSON.stringify(p)}`;
}

async function apply(ops) {
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
  const file = path.join(BACKUP_DIR, `yuk_local_backfill_${RUN_ID}.json`);
  fs.writeFileSync(file, JSON.stringify(ops.map((o) => ({
    path: o.ref.path, create: !!o.create, before: o.before || null,
  })), null, 1));
  console.log(`backup: ${file}`);
  const batch = db.batch();
  for (const op of ops) {
    if (op.create) batch.create(op.ref, op.patch);
    else batch.update(op.ref, op.patch);
  }
  await batch.commit();
  // Текширув: қайта режа бўш бўлиши керак.
  const again = await plan();
  console.log(`verify: remaining ops = ${again.length}`);
  if (again.length) { again.forEach((o) => console.log('  left ' + describe(o))); process.exitCode = 2; }
}

async function rollback(file) {
  const items = JSON.parse(fs.readFileSync(file, 'utf8'));
  const batch = db.batch();
  for (const it of items) {
    const ref = db.doc(it.path);
    if (it.create) { batch.delete(ref); continue; }
    const restore = {};
    for (const [k, v] of Object.entries(it.before || {})) {
      restore[k] = v === null ? FieldValue.delete()
        : (v && v._seconds != null ? new Timestamp(v._seconds, v._nanoseconds || 0) : v);
    }
    batch.update(ref, restore);
  }
  await batch.commit();
  console.log(`rollback: ${items.length} item(s) restored from ${file}`);
}

(async () => {
  const args = process.argv.slice(2);
  if (args[0] === '--rollback') { await rollback(args[1]); process.exit(0); }
  const ops = await plan();
  console.log(`runId=${RUN_ID} ops=${ops.length} (${args.includes('--apply') ? 'APPLY' : 'DRY-RUN'})`);
  ops.forEach((o) => console.log('  ' + describe(o)));
  if (args.includes('--apply') && ops.length) await apply(ops);
  process.exit(process.exitCode || 0);
})().catch((e) => { console.error(e.message); process.exit(1); });
