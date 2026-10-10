/**
 * READ-ONLY АУДИТ: муддат / тайинлаш / Relay зиддиятлари (2026-10-11).
 *
 *   # Эмулятор (стандарт; FIRESTORE_EMULATOR_HOST шарт):
 *   node functions_demand/tools/audit_expired_assignments.js
 *   # Production — ФАҚАТ эгасининг алоҳида рухсати билан:
 *   node functions_demand/tools/audit_expired_assignments.js --prod [--out <файл.json>] [--max-reads 20000]
 *
 * НЕГА: `expireDemandsSweeper` (ba2b69f гача) сўров ва ёзув орасида
 * қабул қилинган талабни `expired` билан босиб кетарди; `acceptOffer`
 * муддатни текширмасди. Production'да шундай ҳолатлар борми — шуни топади.
 *
 * ҲЕЧ НАРСА ЁЗМАЙДИ ВА ТИКЛАМАЙДИ (эга қарори: ҳар ҳолат алоҳида таҳлил).
 * Кафолат кодда: `lockWrites()` Firestore'нинг БАРЧА ёзиш йўлларини
 * (set/update/create/delete, batch, transaction, bulkWriter,
 * recursiveDelete) процесс даражасида ўчиради — ёзишга уриниш хато.
 *
 * Текширувлар:
 *   C1  `expired` талаб + `assignment.providerId` бор (барча модуллар);
 *       унинг match'лари ва қабул қилинган таклифи билан
 *   C2  `accepted` match, лекин талаб ишда эмас (accepted/in_progress/
 *       completed/disputed дан бошқа)
 *   C3  очиқ match (new/seen/offered), лекин талаб ёпиқ
 *       (expired/cancelled/completed) — `--max-reads` чеклови билан
 *   C4  Relay: shipment ↔ LEG зиддиятлари (legAssignments, assignedProviderIds,
 *       legProblem, currentLegId, жорий режада йўқ «етим» LEG)
 *
 * Шахсий маълумот (40-банд): телефон ID'лари ниқобланади (9989012****01),
 * манзил/исм чиқарилмайди. Ҳисобот — фақат ҳужжат ID, ҳолат, вақт.
 */
'use strict';
const path = require('path');

const admin = require(path.join(__dirname, '..', 'node_modules', 'firebase-admin'));

const SA = path.join(__dirname, '..', '..', 'functions', 'service-account.json');
const PROD_PROJECT = 'master-taxi-gurlan';

const WORKING = new Set(['accepted', 'in_progress', 'completed', 'disputed']);
const CLOSED = new Set(['expired', 'cancelled', 'completed']);
const OPEN_MATCH = ['new', 'seen', 'offered'];

// ── Ёзишни процесс даражасида ўчириш ──────────────────────────────────

function lockWrites(firestoreNs) {
  const deny = (what) => function denied() {
    throw new Error(`READ-ONLY AUDIT: ${what} taqiqlangan`);
  };
  const DR = firestoreNs.DocumentReference.prototype;
  for (const m of ['set', 'update', 'create', 'delete']) DR[m] = deny(`DocumentReference.${m}`);
  const CR = firestoreNs.CollectionReference.prototype;
  CR.add = deny('CollectionReference.add');
  const F = firestoreNs.Firestore.prototype;
  for (const m of ['batch', 'runTransaction', 'bulkWriter', 'recursiveDelete']) F[m] = deny(`Firestore.${m}`);
  const WB = firestoreNs.WriteBatch && firestoreNs.WriteBatch.prototype;
  if (WB) for (const m of ['set', 'update', 'create', 'delete', 'commit']) WB[m] = deny(`WriteBatch.${m}`);
}

// ── Ёрдамчилар ────────────────────────────────────────────────────────

const mask = (id) => {
  const s = String(id || '');
  if (!/^\d{9,12}$/.test(s)) return s ? '***' : null;
  return `${s.slice(0, 7)}****${s.slice(-2)}`;
};
const iso = (v) => {
  if (!v) return null;
  if (typeof v.toDate === 'function') return v.toDate().toISOString();
  if (v instanceof Date) return v.toISOString();
  return String(v);
};

const ms = (v) => {
  if (!v) return 0;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return Date.parse(String(v)) || 0;
};

class Budget {
  constructor(max) { this.max = max; this.used = 0; this.exhausted = false; }
  take(n) {
    this.used += n;
    if (this.used >= this.max) this.exhausted = true;
    return !this.exhausted;
  }
}

/** Ҳужжат ID бўйича саҳифалаб ўқийди (бюджет тугаса тўхтайди). */
async function* paged(query, budget, pageSize = 300) {
  let last = null;
  for (;;) {
    let q = query.orderBy(admin.firestore.FieldPath.documentId()).limit(pageSize);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) return;
    const ok = budget.take(snap.size);
    for (const d of snap.docs) yield d;
    if (!ok || snap.size < pageSize) return;
    last = snap.docs[snap.size - 1];
  }
}

async function getAllChunked(db, refs, budget) {
  const out = [];
  for (let i = 0; i < refs.length; i += 100) {
    const chunk = refs.slice(i, i + 100);
    budget.take(chunk.length);
    out.push(...await db.getAll(...chunk));
  }
  return out;
}

// ── Текширувлар ───────────────────────────────────────────────────────

async function checkExpiredAssigned(db, budget) {
  const rows = [];
  let scanned = 0;
  const q = db.collection('demands').where('status', '==', 'expired');
  for await (const d of paged(q, budget)) {
    scanned += 1;
    const x = d.data() || {};
    const providerId = (x.assignment || {}).providerId;
    if (!providerId) continue;
    const matchSnap = await db.collection('demand_matches').where('demandId', '==', d.id).get();
    budget.take(Math.max(matchSnap.size, 1));
    const offerSnap = await d.ref.collection('offers').doc(String(providerId)).get();
    budget.take(1);
    rows.push({
      demandId: d.id,
      module: x.module || null,
      provider: mask(providerId),
      owner: mask(x.ownerId),
      acceptedAt: iso((x.assignment || {}).acceptedAt),
      expiresAt: iso((x.timeWindow || {}).expiresAt),
      expiredAt: iso(x.expiredAt),
      // Қабул муддатдан КЕЙИН бўлганми (acceptOffer текширмаган) ёки ОЛДИН (sweeper пойгаси).
      acceptedAfterExpiry: !!((x.assignment || {}).acceptedAt && (x.timeWindow || {}).expiresAt
        && (ms(x.assignment.acceptedAt) > ms(x.timeWindow.expiresAt))),
      offerStatus: offerSnap.exists ? (offerSnap.data() || {}).status : null,
      matches: matchSnap.docs.map((m) => {
        const md = m.data() || {};
        return { provider: mask(md.providerId), status: md.status || null, contactUnlocked: !!md.contactUnlocked };
      }),
      shipmentId: (x.attributes || {}).shipmentId || null,
    });
  }
  return { scanned, rows };
}

async function checkAcceptedMatches(db, budget) {
  const rows = [];
  const matches = [];
  for await (const m of paged(db.collection('demand_matches').where('status', '==', 'accepted'), budget)) matches.push(m);
  const ids = [...new Set(matches.map((m) => (m.data() || {}).demandId).filter(Boolean))];
  const demands = new Map();
  for (const s of await getAllChunked(db, ids.map((id) => db.collection('demands').doc(id)), budget)) {
    demands.set(s.id, s.exists ? (s.data() || {}) : null);
  }
  for (const m of matches) {
    const md = m.data() || {};
    const dem = demands.get(md.demandId);
    const st = dem ? dem.status : 'MISSING';
    const assigned = dem ? (dem.assignment || {}).providerId : null;
    if (dem && WORKING.has(st) && assigned === md.providerId) continue;
    rows.push({
      matchId: `${md.demandId}_${mask(md.providerId)}`,
      demandId: md.demandId,
      module: dem ? dem.module || null : null,
      demandStatus: st,
      assignedIsThisProvider: assigned === md.providerId,
      contactUnlocked: !!md.contactUnlocked,
    });
  }
  return { scanned: matches.length, rows };
}

async function checkOpenMatchesOnClosed(db, budget) {
  const rows = [];
  let scanned = 0;
  const q = db.collection('demand_matches').where('status', 'in', OPEN_MATCH);
  const byDemand = new Map();
  for await (const m of paged(q, budget)) {
    scanned += 1;
    const md = m.data() || {};
    if (!md.demandId) continue;
    if (!byDemand.has(md.demandId)) byDemand.set(md.demandId, []);
    byDemand.get(md.demandId).push(md);
  }
  const ids = [...byDemand.keys()];
  for (const s of await getAllChunked(db, ids.map((id) => db.collection('demands').doc(id)), budget)) {
    const st = s.exists ? (s.data() || {}).status : 'MISSING';
    if (!CLOSED.has(st) && st !== 'MISSING') continue;
    rows.push({
      demandId: s.id,
      module: s.exists ? (s.data() || {}).module || null : null,
      demandStatus: st,
      openMatches: byDemand.get(s.id).length,
      statuses: [...new Set(byDemand.get(s.id).map((m) => m.status))],
    });
  }
  return { scanned, rows };
}

async function checkRelay(db, budget) {
  const rows = [];
  const add = (shipmentId, kind, detail) => rows.push({ shipmentId, kind, ...detail });
  const ships = [];
  for await (const s of paged(db.collection('shipments'), budget)) ships.push(s);
  const legs = [];
  for await (const l of paged(db.collection('demands').where('module', '==', 'logistics'), budget)) legs.push(l);
  const legById = new Map(legs.map((l) => [l.id, l.data() || {}]));
  const shipById = new Map(ships.map((s) => [s.id, s.data() || {}]));

  for (const s of ships) {
    const x = s.data() || {};
    const legIds = Array.isArray(x.legIds) ? x.legIds : [];
    const la = x.legAssignments || {};
    for (const [legId, p] of Object.entries(la)) {
      const leg = legById.get(legId);
      if (!legIds.includes(legId)) add(s.id, 'legAssignment_not_in_plan', { legId, provider: mask(p) });
      else if (!leg || !WORKING.has(leg.status) || (leg.assignment || {}).providerId !== p) {
        add(s.id, 'legAssignment_mismatch', { legId, provider: mask(p), legStatus: leg ? leg.status : 'MISSING' });
      }
    }
    for (const legId of legIds) {
      const leg = legById.get(legId);
      if (!leg) { add(s.id, 'plan_leg_missing', { legId }); continue; }
      const p = (leg.assignment || {}).providerId;
      if (['accepted', 'in_progress'].includes(leg.status) && la[legId] !== p) {
        add(s.id, 'assigned_leg_not_in_legAssignments', { legId, legStatus: leg.status, provider: mask(p) });
      }
      if (leg.status === 'expired' && p) add(s.id, 'expired_leg_with_provider', { legId, provider: mask(p) });
    }
    const holders = new Set(Object.values(la));
    const stale = (x.assignedProviderIds || []).filter((p) => !holders.has(p));
    if (stale.length) add(s.id, 'stale_assignedProviderIds', { providers: stale.map(mask), shipmentStatus: x.status });
    if (x.legProblem && x.legProblem.legId) {
      const lp = legById.get(x.legProblem.legId);
      if (!legIds.includes(x.legProblem.legId) || !lp || lp.status !== 'expired') {
        add(s.id, 'legProblem_stale', { legId: x.legProblem.legId, legStatus: lp ? lp.status : 'MISSING' });
      }
    }
    if (x.status === 'in_transit' && x.currentLegId && !legIds.includes(x.currentLegId)) {
      add(s.id, 'currentLeg_not_in_plan', { legId: x.currentLegId });
    }
  }
  for (const l of legs) {
    const x = l.data() || {};
    if (!['active', 'accepted', 'in_progress'].includes(x.status)) continue;
    const sid = (x.attributes || {}).shipmentId;
    const sh = sid ? shipById.get(sid) : null;
    if (!sh || !(sh.legIds || []).includes(l.id)) {
      add(sid || null, 'orphan_open_leg', { legId: l.id, legStatus: x.status, provider: mask((x.assignment || {}).providerId) });
    }
  }
  return { scannedShipments: ships.length, scannedLegs: legs.length, rows };
}

async function runAudit(db, opts = {}) {
  const budget = new Budget(opts.maxReads || 20000);
  const startedAt = new Date().toISOString();
  const c1 = await checkExpiredAssigned(db, budget);
  const c2 = await checkAcceptedMatches(db, budget);
  const c3 = budget.exhausted ? { skipped: 'budget' } : await checkOpenMatchesOnClosed(db, budget);
  const c4 = budget.exhausted ? { skipped: 'budget' } : await checkRelay(db, budget);
  return {
    kind: 'audit_expired_assignments',
    readOnly: true,
    startedAt,
    finishedAt: new Date().toISOString(),
    reads: budget.used,
    budgetExhausted: budget.exhausted,
    summary: {
      C1_expired_with_provider: c1.rows.length,
      C2_accepted_match_on_non_working_demand: c2.rows.length,
      C3_open_match_on_closed_demand: c3.rows ? c3.rows.length : c3.skipped,
      C4_relay_inconsistencies: c4.rows ? c4.rows.length : c4.skipped,
    },
    C1: c1, C2: c2, C3: c3, C4: c4,
  };
}

// ── CLI ───────────────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);
  const prod = args.includes('--prod');
  const outIdx = args.indexOf('--out');
  const out = outIdx >= 0 ? args[outIdx + 1] : null;
  const maxIdx = args.indexOf('--max-reads');
  const maxReads = maxIdx >= 0 ? Number(args[maxIdx + 1]) : 20000;

  if (prod) {
    if (process.env.FIRESTORE_EMULATOR_HOST) throw new Error('--prod: FIRESTORE_EMULATOR_HOST o\'rnatilgan — aralashtirmang');
    // eslint-disable-next-line global-require, import/no-dynamic-require
    admin.initializeApp({ credential: admin.credential.cert(require(SA)), projectId: PROD_PROJECT });
  } else {
    if (!process.env.FIRESTORE_EMULATOR_HOST) {
      throw new Error('Emulator topilmadi (FIRESTORE_EMULATOR_HOST). Production uchun --prod (FAQAT ega ruxsati bilan).');
    }
    admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-audit' });
  }
  lockWrites(admin.firestore);
  const db = admin.firestore();
  console.error(`READ-ONLY audit: ${prod ? `PRODUCTION ${PROD_PROJECT}` : 'emulator'}; o'qish chegarasi ${maxReads}`);
  const report = await runAudit(db, { maxReads });
  const text = JSON.stringify(report, null, 2);
  if (out) {
    // Mahalliy fayl (Firestore emas).
    require('fs').writeFileSync(out, text, 'utf8'); // eslint-disable-line global-require
    console.error(`hisobot: ${out}`);
  }
  console.log(JSON.stringify({ summary: report.summary, reads: report.reads, budgetExhausted: report.budgetExhausted }, null, 2));
}

if (require.main === module) {
  main().catch((e) => { console.error(`AUDIT XATO: ${e.message}`); process.exit(1); });
}

module.exports = { runAudit, lockWrites, mask };
