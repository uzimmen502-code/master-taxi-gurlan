#!/usr/bin/env node
/**
 * «Овқат» модулининг прод маълумотини тозалаш (эга қарори 2026-10-11:
 * «Овқатни барча жойдан олиб ташла … эски буюртмалар ҳам керакмас»).
 *
 *   node functions/tools/food_cleanup.js                       # DRY-RUN (фақат ўқийди)
 *   node functions/tools/food_cleanup.js --backup <file.json>  # тўлиқ нусха (ўқийди + файл)
 *   node functions/tools/food_cleanup.js --apply --backup <file.json>   # ЎЧИРАДИ
 *   node functions/tools/food_cleanup.js --restore <file.json> # қайтариш
 *
 * Нима ўчирилади:
 *   - `orders` (`type == 'food'`) — ички коллекциялари билан (`payment_lines`…)
 *   - `admin_news` (`orderType == 'food'`) — шу буюртмалар хабарлари
 *   - `food_catalog`, `food_inventory` — барча ҳужжатлар
 *   - `search_index`: `type == 'food_product'` ва `service_food`
 *
 * Нима ЎЧИРИЛМАЙДИ (16-қоида, пул ҳаракати тарихи): `journal_entries`,
 * `users/*\/wallet_ledger`. DRY-RUN уларнинг сонини кўрсатади — ўчирилган
 * буюртмага ишора қилиб қолади.
 *
 * Хавфсизлик:
 *   - Очиқ (якунланмаган) «Овқат» буюртмаси бўлса `--apply` РАД этилади:
 *     аввал админда бекор қилинсин — ҳамён қайтими одатий йўл билан ўтади.
 *   - `--apply` фақат шу режага мос backup файли билан ишлайди (ID'лар хеши).
 *   - Ёзиш 400 талик batch'ларда, жараён ҳисоботи, охирида текширув (0 қолди).
 *   - `food_images/` (Storage) бу восита тегмайди — DRY-RUN сонини айтади,
 *     ўчириш алоҳида буйруқ (README).
 */
'use strict';

const crypto = require('crypto');

const WRITE_BATCH = 400;
const FINAL_STATUSES = new Set(['delivered', 'rejected', 'cancelled', 'canceled', 'completed']);

function isActiveOrder(d) {
  const st = String(d.status || '').toLowerCase();
  const fs = String(d.fulfillmentStatus || '').toLowerCase();
  if (FINAL_STATUSES.has(st)) return false;
  if (fs === 'completed' || fs === 'cancelled' || fs === 'canceled') return false;
  return true;
}

/** Firestore қийматини JSON'га (Timestamp/DocumentReference/GeoPoint/Buffer). */
function encode(v) {
  if (v === null || v === undefined) return v;
  if (Array.isArray(v)) return v.map(encode);
  if (typeof v === 'object') {
    if (typeof v.toDate === 'function' && typeof v.seconds === 'number') {
      return { __t: 'ts', s: v.seconds, n: v.nanoseconds };
    }
    if (typeof v.latitude === 'number' && typeof v.longitude === 'number' && Object.keys(v).length <= 2) {
      return { __t: 'geo', lat: v.latitude, lng: v.longitude };
    }
    if (v.path && v.firestore) return { __t: 'ref', path: v.path };
    if (Buffer.isBuffer(v)) return { __t: 'bytes', b64: v.toString('base64') };
    const out = {};
    for (const [k, x] of Object.entries(v)) out[k] = encode(x);
    return out;
  }
  return v;
}

function decode(v, admin, db) {
  if (v === null || v === undefined) return v;
  if (Array.isArray(v)) return v.map((x) => decode(x, admin, db));
  if (typeof v === 'object') {
    if (v.__t === 'ts') return new admin.firestore.Timestamp(v.s, v.n);
    if (v.__t === 'geo') return new admin.firestore.GeoPoint(v.lat, v.lng);
    if (v.__t === 'ref') return db.doc(v.path);
    if (v.__t === 'bytes') return Buffer.from(v.b64, 'base64');
    const out = {};
    for (const [k, x] of Object.entries(v)) out[k] = decode(x, admin, db);
    return out;
  }
  return v;
}

async function allDocs(query) {
  const snap = await query.get();
  return snap.docs;
}

/** Ўчириладиган ҳужжат йўллари ва таъсир — ФАҚАТ ўқийди. */
async function planCleanup(db) {
  const orderDocs = await allDocs(db.collection('orders').where('type', '==', 'food'));
  const orders = { total: orderDocs.length, active: [], pos: 0, withWallet: 0, byStatus: {} };
  for (const d of orderDocs) {
    const x = d.data() || {};
    const st = String(x.status || '—');
    orders.byStatus[st] = (orders.byStatus[st] || 0) + 1;
    if (String(x.fulfillmentMode || '') === 'pos') orders.pos += 1;
    if ((Number(x.balanceApplied) || 0) > 0) orders.withWallet += 1;
    if (isActiveOrder(x)) {
      orders.active.push({
        id: d.id, status: st, balanceApplied: Number(x.balanceApplied) || 0,
      });
    }
  }
  const orderIds = orderDocs.map((d) => d.id);

  const newsDocs = await allDocs(db.collection('admin_news').where('orderType', '==', 'food'));
  const catalogDocs = await allDocs(db.collection('food_catalog'));
  const inventoryDocs = await allDocs(db.collection('food_inventory'));
  const searchDocs = await allDocs(db.collection('search_index').where('type', '==', 'food_product'));
  const serviceCard = await db.collection('search_index').doc('service_food').get();

  // Ўчирилмайди — фақат таъсирни кўрсатиш учун.
  let journalRefs = 0;
  for (let i = 0; i < orderIds.length; i += 30) {
    const part = orderIds.slice(i, i + 30);
    const s = await db.collection('journal_entries')
        .where('refType', '==', 'order').where('refId', 'in', part).get();
    journalRefs += s.size;
  }

  const paths = [
    ...orderDocs.map((d) => d.ref.path),
    ...newsDocs.map((d) => d.ref.path),
    ...catalogDocs.map((d) => d.ref.path),
    ...inventoryDocs.map((d) => d.ref.path),
    ...searchDocs.map((d) => d.ref.path),
    ...(serviceCard.exists ? [serviceCard.ref.path] : []),
  ].sort();

  return {
    orders,
    orderIds,
    counts: {
      orders: orderDocs.length,
      adminNews: newsDocs.length,
      foodCatalog: catalogDocs.length,
      foodInventory: inventoryDocs.length,
      searchIndex: searchDocs.length + (serviceCard.exists ? 1 : 0),
    },
    keptJournalRefs: journalRefs,
    paths,
    planHash: crypto.createHash('sha256').update(paths.join('\n')).digest('hex'),
  };
}

/** Ҳужжат + барча ички коллекциялари (рекурсив) — backup учун. */
async function dumpDoc(ref, out) {
  const snap = await ref.get();
  if (snap.exists) out.push({ path: ref.path, data: encode(snap.data()) });
  const subs = await ref.listCollections();
  for (const col of subs) {
    const docs = await col.listDocuments();
    for (const child of docs) await dumpDoc(child, out);
  }
}

async function backupCleanup(db, plan) {
  const docs = [];
  for (const p of plan.paths) await dumpDoc(db.doc(p), docs);
  return {
    tool: 'food_cleanup',
    version: 1,
    createdAt: new Date().toISOString(),
    planHash: plan.planHash,
    counts: plan.counts,
    docs,
  };
}

async function applyCleanup(db, plan, backup, { log = console.log } = {}) {
  if (plan.orders.active.length > 0) {
    const e = new Error(`ACTIVE_FOOD_ORDERS: ${plan.orders.active.length} ta ochiq buyurtma — avval adminda bekor qiling`);
    e.code = 'ACTIVE_FOOD_ORDERS';
    throw e;
  }
  if (!backup || backup.tool !== 'food_cleanup' || backup.planHash !== plan.planHash) {
    const e = new Error('BACKUP_MISMATCH: backup fayli joriy rejaga mos emas — qayta --backup qiling');
    e.code = 'BACKUP_MISMATCH';
    throw e;
  }
  let done = 0;
  for (let i = 0; i < plan.paths.length; i += WRITE_BATCH) {
    const part = plan.paths.slice(i, i + WRITE_BATCH);
    // Ички коллекциялар (`payment_lines`…) ҳам кетсин.
    for (const p of part) await db.recursiveDelete(db.doc(p));
    done += part.length;
    log(`… ${done}/${plan.paths.length}`);
  }
  const after = await planCleanup(db);
  return { deleted: done, remaining: after.paths.length, remainingCounts: after.counts };
}

const RESTORE_ROOTS = ['orders/', 'admin_news/', 'food_catalog/', 'food_inventory/', 'search_index/'];

async function restoreCleanup(db, admin, backup, { log = console.log } = {}) {
  if (!backup || backup.tool !== 'food_cleanup') throw new Error('food_cleanup backup emas');
  const foreign = (backup.docs || []).filter((d) => !RESTORE_ROOTS.some((r) => String(d.path).startsWith(r)));
  if (foreign.length) throw new Error(`RESTORE_FOREIGN_PATH: ${foreign[0].path}`);
  let restored = 0;
  let skipped = 0;
  for (let i = 0; i < backup.docs.length; i += WRITE_BATCH) {
    const part = backup.docs.slice(i, i + WRITE_BATCH);
    const refs = part.map((d) => db.doc(d.path));
    const snaps = await db.getAll(...refs);
    const batch = db.batch();
    let n = 0;
    snaps.forEach((s, k) => {
      // Ўша йўлда янги ҳужжат пайдо бўлган бўлса — устидан ёзмаймиз.
      if (s.exists) { skipped += 1; return; }
      batch.set(refs[k], decode(part[k].data, admin, db));
      n += 1;
    });
    if (n > 0) await batch.commit();
    restored += n;
    log(`… ${Math.min(i + WRITE_BATCH, backup.docs.length)}/${backup.docs.length}`);
  }
  return { restored, skipped };
}

module.exports = {
  planCleanup, backupCleanup, applyCleanup, restoreCleanup, isActiveOrder, encode, decode,
};

if (require.main === module) {
  const fs = require('fs');
  const path = require('path');
  const admin = require('firebase-admin');
  const args = process.argv.slice(2);
  const flag = (name) => {
    const i = args.indexOf(name);
    return i >= 0 ? String(args[i + 1] || '') : '';
  };
  const APPLY = args.includes('--apply');
  const BACKUP = flag('--backup');
  const RESTORE = flag('--restore');

  if (process.env.FIRESTORE_EMULATOR_HOST) {
    admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-food-cleanup' });
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

  const summary = (plan) => {
    console.log(JSON.stringify({
      counts: plan.counts,
      ordersByStatus: plan.orders.byStatus,
      posSales: plan.orders.pos,
      ordersWithWallet: plan.orders.withWallet,
      activeOrders: plan.orders.active.length,
      keptJournalRefs: plan.keptJournalRefs,
      planHash: plan.planHash.slice(0, 12),
    }, null, 2));
    if (plan.orders.active.length) {
      console.log('OCHIQ buyurtmalar (avval bekor qilinsin):');
      for (const a of plan.orders.active.slice(0, 50)) {
        console.log(`  ${a.id}  status=${a.status}  hamyondan=${a.balanceApplied}`);
      }
    }
  };

  (async () => {
    if (RESTORE) {
      const backup = JSON.parse(fs.readFileSync(RESTORE, 'utf8'));
      const r = await restoreCleanup(db, admin, backup);
      console.log(`Qaytarildi: ${r.restored}, o'tkazib yuborildi (mavjud): ${r.skipped}.`);
      return;
    }
    const plan = await planCleanup(db);
    summary(plan);
    if (!APPLY && !BACKUP) {
      console.log('DRY-RUN — hech narsa yozilmadi. Nusxa: --backup <fayl>, o\'chirish: --apply --backup <fayl>.');
      return;
    }
    if (!APPLY) {
      if (fs.existsSync(BACKUP)) throw new Error(`fayl allaqachon bor: ${BACKUP}`);
      const backup = await backupCleanup(db, plan);
      fs.writeFileSync(BACKUP, JSON.stringify(backup));
      console.log(`Backup: ${backup.docs.length} ta hujjat (ichki kolleksiyalar bilan) → ${BACKUP}`);
      return;
    }
    if (!BACKUP || !fs.existsSync(BACKUP)) throw new Error('--apply uchun --backup <mavjud fayl> shart');
    const backup = JSON.parse(fs.readFileSync(BACKUP, 'utf8'));
    const r = await applyCleanup(db, plan, backup);
    console.log(`O'chirildi: ${r.deleted}. Qoldi: ${r.remaining}. Qaytarish: --restore ${BACKUP}`);
  })().catch((e) => { console.error(e.code || '', e.message || e); process.exit(1); });
}
