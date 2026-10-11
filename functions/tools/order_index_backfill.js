#!/usr/bin/env node
/**
 * «Барча буюртмалар» — `order_index` ни мавжуд буюртмалардан тўлдириш
 * (docs/barcha_buyurtmalar_taklifi_uz.md §3, 27-қоида).
 *
 *   node functions/tools/order_index_backfill.js              # DRY-RUN (фақат ўқийди)
 *   node functions/tools/order_index_backfill.js --apply      # тўлдиради
 *   node functions/tools/order_index_backfill.js --recompute  # чегара ўзгарса: ҳаммасини қайта ҳисоблаш
 *   node functions/tools/order_index_backfill.js --purge --yes  # қайтариш: order_index ни бутунлай ўчириш
 *
 * Хавфсизлик:
 *   - Манба коллекцияларига ЁЗМАЙДИ; фақат `order_index`.
 *   - Триггерлар билан бир хил `syncOne` (транзакция, эскирган ҳодиса
 *     ёзилмайди) — иккаласи бир вақтда ишласа ҳам натижа тўғри.
 *   - Эски ҳужжатларда «ҳолатга ўтган вақт» тахминий (`sinceApprox: true`).
 *   - `--purge` — индекс ҳосила маълумот: ўчирилса манба йўқолмайди,
 *     кейин `--apply` билан қайта қурилади.
 */
'use strict';

const oi = require('../order_index');

const PAGE = 500;
const CONCURRENCY = 8;

function sourceQuery(db, col) {
  const base = db.collection(col);
  return col === 'demands' ? base.where('module', '==', 'courier') : base;
}

async function* scan(db, col) {
  let last = null;
  for (;;) {
    let q = sourceQuery(db, col).orderBy('__name__').limit(PAGE);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) return;
    for (const d of snap.docs) yield d;
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE) return;
  }
}

/** DRY-RUN: модул/босқич бўйича сон, номаълум статуслар. */
async function planBackfill(db) {
  const out = { scanned: 0, indexable: 0, skipped: 0, byModule: {}, unknown: {} };
  for (const col of oi.SOURCES) {
    for await (const d of scan(db, col)) {
      out.scanned += 1;
      const n = oi.normalize(col, d.data() || {}, {});
      if (!n) { out.skipped += 1; continue; }
      out.indexable += 1;
      const m = (out.byModule[n.module] = out.byModule[n.module] || { total: 0, byNorm: {} });
      m.total += 1;
      m.byNorm[n.normStatus] = (m.byNorm[n.normStatus] || 0) + 1;
      if (n.normStatus === oi.NORM.UNKNOWN) {
        const k = `${n.module}:${n.rawStatus || '—'}`;
        out.unknown[k] = (out.unknown[k] || 0) + 1;
      }
    }
  }
  return out;
}

async function applyBackfill(db, admin, { force = false, log = console.log } = {}) {
  const tally = { written: 0, removed: 0, stale_skipped: 0, failed: 0 };
  let seen = 0;
  for (const col of oi.SOURCES) {
    const pending = [];
    const run = async (d) => {
      try {
        const r = await oi.syncOne(db, admin, {
          sourceCollection: col, sourceId: d.id, data: d.data() || {},
          updateMs: d.updateTime ? d.updateTime.toMillis() : Date.now(),
          eventMs: Date.now(), approx: true, force,
        });
        tally[r.action] = (tally[r.action] || 0) + 1;
      } catch (e) {
        tally.failed += 1;
        log(JSON.stringify({ action: 'orderIndexBackfill', sourceCollection: col, sourceId: d.id, result: 'failed', error: String(e.message || e) }));
      }
    };
    for await (const d of scan(db, col)) {
      pending.push(run(d));
      seen += 1;
      if (pending.length >= CONCURRENCY) await Promise.all(pending.splice(0));
      if (seen % 500 === 0) log(`… ${seen}`);
    }
    await Promise.all(pending);
  }
  // Текширув: индексдаги модуллар бўйича сон.
  const verify = {};
  for (const m of ['bread', 'wholesale', 'restaurant', 'carpet', 'milk', 'logistics', 'courier']) {
    const c = await db.collection(oi.INDEX_COL).where('module', '==', m).count().get();
    verify[m] = c.data().count;
  }
  return { ...tally, scanned: seen, verify };
}

async function purgeIndex(db, { log = console.log } = {}) {
  let deleted = 0;
  for (;;) {
    const snap = await db.collection(oi.INDEX_COL).limit(400).get();
    if (snap.empty) break;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    deleted += snap.size;
    log(`… ${deleted}`);
  }
  return { deleted };
}

module.exports = { planBackfill, applyBackfill, purgeIndex };

if (require.main === module) {
  const fs = require('fs');
  const path = require('path');
  const admin = require('firebase-admin');
  const args = process.argv.slice(2);
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-order-index' });
  } else {
    const keyPath = path.join(__dirname, '..', 'service-account.json');
    if (!fs.existsSync(keyPath)) {
      console.error('service-account.json topilmadi:', keyPath);
      process.exit(1);
    }
    admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
  }
  const db = admin.firestore();
  db.settings({ preferRest: true });
  (async () => {
    if (args.includes('--purge')) {
      if (!args.includes('--yes')) throw new Error('--purge uchun --yes kerak (order_index butunlay o\'chadi)');
      console.log(await purgeIndex(db));
      return;
    }
    if (args.includes('--apply') || args.includes('--recompute')) {
      const r = await applyBackfill(db, admin, { force: args.includes('--recompute') });
      console.log(JSON.stringify(r, null, 2));
      return;
    }
    const p = await planBackfill(db);
    console.log(JSON.stringify(p, null, 2));
    console.log('DRY-RUN — hech narsa yozilmadi. To\'ldirish: --apply');
  })().catch((e) => { console.error(e.message || e); process.exit(1); });
}
