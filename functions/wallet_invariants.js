/**
 * Ҳамён инвариантлари — кунлик текширув (W-1, 3-босқич). ФАҚАТ ЎҚИЙДИ ВА ҲИСОБОТ ЁЗАДИ, ҲЕЧ НАРСАНИ ТУЗАТМАЙДИ.
 *
 * Учта омбор: `users/{uid}.bonusBalance` (проекция), `users/{uid}/wallet_ledger` (фойдаланувчи тарихи),
 * `ledger_accounts` + `journal_entries` (икки томонлама ledger). Нол толерантлик (эга 2026-11-28:
 * «Ҳисоб дафтар жуда тоза ва мукаммал бўлсин»): ҳар қандай фарқ — drift.
 *
 *   I-1  ҳар uid: bonusBalance == passenger_credit:{uid}.balance (ҳисоби йўқ → bonusBalance 0 бўлиши шарт;
 *        user ҳужжати йўқ → ҳисоб 0 бўлиши шарт).
 *   I-2  ledger ички: ҳар журнал ёзуви тўғри (бутун, манфий эмас, ҳар legда битта томон, Σdr==Σcr>0, маълум ҳисоб);
 *        глобал Σdr==Σcr; Σактив==Σмажбурият; ҳар ҳисоб баланси == журналдан қайта ҳисобланган; ҳисоб тури тўғри.
 *   I-3  тарих ↔ баланс, базадан кейин: bonusBalance == opening:{uid} + Σ wallet_ledger (createdAt ≥ BASELINE).
 *   I-3F тарих тўлиқ: bonusBalance == Σ БАРЧА wallet_ledger (базагача бўлган эски давр ҳам). Тарихий тузатиш
 *        ёзувлари (`pre_ledger_adjustment`) шу ерда ҳисобга олинади.
 *   A    аномалиялар: манфий баланс, бутун бўлмаган қиймат (bonusBalance / wallet_ledger.amount / ҳисоб).
 *
 * wallet_ledger белги қоидаси (CONFIRMED, код): `order_payment_*` балансга таъсир қилмайди; юқори даражадаги
 * `debitCredit: 'debit'` → −|amount| (realty/tv_ad харидлари); `'credit'` → +|amount|; қолгани — amount белгиси билан.
 *
 * Масштаб: ҳамма ўқиш саҳифалаб (documentId / курсор). Ҳозир ~13 ҳамён, 44 журнал, 401 тарих → ~500 ўқиш/кун.
 * Келажак (PROPOSED): инкрементал режим — `ledger_reconcile_state` да ҳисоб бўйича журнал йиғиндиси + охирги
 * курсор сақланади, кунда фақат янги журнал ёзувлари ва `balanceUpdatedAt` ўзгарган ҳамёнлар ўқилади; тўлиқ
 * текширув ҳафтада бир марта.
 */
'use strict';
const ledger = require('./settlement_ledger');

const REPORT_COLLECTION = 'ledger_reconcile_runs';
/** I-3 базавий сана: `tools/settlement_opening_balances.js` (opening:{uid}) ишга тушган пайт. */
const BASELINE_ISO = '2026-06-28T08:44:00.000Z';
const BASELINE_MS = Date.parse(BASELINE_ISO);
const DRIFT_CODE = 'WALLET_PROJECTION_DRIFT';
const SAMPLE_LIMIT = 100;
const PC_PREFIX = 'passenger_credit:';

const isInt = (n) => Number.isInteger(n);
const mask = (uid) => `***${String(uid).slice(-4)}`;
const toMs = (v) => {
  if (!v) return null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  if (typeof v === 'number') return v;
  return null;
};

/** wallet_ledger қаторининг балансга таъсири (белгили). `null` — бутун сон эмас. */
function walletRowEffect(row) {
  const r = row || {};
  const type = String(r.type || '');
  if (type.startsWith('order_payment_')) return 0;
  const amount = r.amount;
  if (amount === undefined || amount === null) return 0;
  if (!isInt(amount)) return null;
  if (r.debitCredit === 'debit') return -Math.abs(amount);
  if (r.debitCredit === 'credit') return Math.abs(amount);
  return amount;
}

/** Саҳифалаб бутун коллекцияни ўқийди (documentId тартибида). */
async function scanCollection(db, col, pageSize, onDoc) {
  const FieldPath = require('firebase-admin').firestore.FieldPath;
  let last = null;
  let reads = 0;
  for (;;) {
    let q = db.collection(col).orderBy(FieldPath.documentId()).limit(pageSize);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    reads += snap.size;
    snap.docs.forEach(onDoc);
    if (snap.size < pageSize) break;
    last = snap.docs[snap.docs.length - 1];
  }
  return reads;
}

/** Учала омборни ўқийди (саҳифалаб). */
async function collectState(db, { pageSize = 500 } = {}) {
  const state = {
    accounts: new Map(), // id -> {type, balance}
    journal: [], // {id, legs, ts}
    users: new Map(), // uid -> bonusBalance (raw, ≠ 0)
    wallet: new Map(), // uid -> [{effect, createdAtMs, type}]
    userExists: new Map(),
    reads: 0,
  };
  state.reads += await scanCollection(db, ledger.COL_ACCOUNTS, pageSize, (d) => {
    const x = d.data() || {};
    state.accounts.set(d.id, { type: x.type || null, balance: x.balance === undefined ? 0 : x.balance });
  });
  state.reads += await scanCollection(db, ledger.COL_JOURNAL, pageSize, (d) => {
    const x = d.data() || {};
    state.journal.push({ id: d.id, legs: Array.isArray(x.legs) ? x.legs : null, kind: x.kind || '' });
  });
  // bonusBalance ≠ 0 бўлган ҳамма (манфий ва бутун бўлмаган ҳам) — `!=` сўрови, курсор билан.
  let last = null;
  for (;;) {
    let q = db.collection('users').where('bonusBalance', '!=', 0).orderBy('bonusBalance').limit(pageSize);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    state.reads += snap.size;
    snap.docs.forEach((d) => {
      state.users.set(d.id, (d.data() || {}).bonusBalance);
      state.userExists.set(d.id, true);
    });
    if (snap.size < pageSize) break;
    last = snap.docs[snap.docs.length - 1];
  }
  // Ҳисоби бор, лекин bonusBalance 0/йўқ — user ҳужжати борлигини getAll пакети билан аниқлаймиз.
  const pcOnly = [...state.accounts.keys()]
      .filter((id) => id.startsWith(PC_PREFIX))
      .map((id) => ledger.ownerUidOf(id))
      .filter((u) => u && !state.users.has(u));
  for (let i = 0; i < pcOnly.length; i += 100) {
    const refs = pcOnly.slice(i, i + 100).map((u) => db.collection('users').doc(u));
    const snaps = await db.getAll(...refs);
    state.reads += snaps.length;
    snaps.forEach((s, j) => state.userExists.set(pcOnly[i + j], s.exists));
  }
  // wallet_ledger — текшириладиган ҳар ҳамён учун (саҳифалаб).
  const uids = new Set([...state.users.keys(), ...pcOnly]);
  for (const uid of uids) {
    const rows = [];
    let cur = null;
    for (;;) {
      const FieldPath = require('firebase-admin').firestore.FieldPath;
      let q = db.collection('users').doc(uid).collection('wallet_ledger')
          .orderBy(FieldPath.documentId()).limit(pageSize);
      if (cur) q = q.startAfter(cur);
      const snap = await q.get();
      state.reads += snap.size;
      snap.docs.forEach((d) => {
        const x = d.data() || {};
        rows.push({ id: d.id, type: String(x.type || ''), effect: walletRowEffect(x), createdAtMs: toMs(x.createdAt) });
      });
      if (snap.size < pageSize) break;
      cur = snap.docs[snap.docs.length - 1];
    }
    state.wallet.set(uid, rows);
  }
  return state;
}

function capPush(arr, item) { if (arr.length < SAMPLE_LIMIT) arr.push(item); }

/** Соф функция: ҳолатдан ҳисобот. */
function evaluate(state, { baselineMs = BASELINE_MS } = {}) {
  // ── I-2: журнал ва ҳисоблар ─────────────────────────────────────────
  const i2 = {
    ok: true, totalDr: 0, totalCr: 0, assets: 0, liabilities: 0,
    entryErrors: [], entryErrorCount: 0, accountMismatches: [], accountMismatchCount: 0,
  };
  const recomputed = new Map();
  const opening = new Map(); // uid -> amount
  for (const e of state.journal) {
    let dr = 0;
    let cr = 0;
    let err = null;
    if (!e.legs || e.legs.length < 2) err = 'legs_missing';
    for (const l of e.legs || []) {
      const a = String((l && l.account) || '');
      const ldr = (l && l.dr) || 0;
      const lcr = (l && l.cr) || 0;
      if (!ledger.accountTypeOf(a)) { err = err || 'unknown_account'; continue; }
      if (!isInt(ldr) || !isInt(lcr) || ldr < 0 || lcr < 0) { err = err || 'non_integer_or_negative_leg'; continue; }
      if ((ldr > 0) === (lcr > 0)) err = err || 'leg_needs_one_side';
      dr += ldr;
      cr += lcr;
      recomputed.set(a, (recomputed.get(a) || 0) + ledger.naturalDelta(a, ldr, lcr));
    }
    if (!err && dr !== cr) err = 'unbalanced';
    if (!err && dr <= 0) err = 'zero_amount';
    if (err) { i2.entryErrorCount += 1; capPush(i2.entryErrors, { id: e.id, error: err, dr, cr }); }
    i2.totalDr += dr;
    i2.totalCr += cr;
    if (e.id.startsWith('opening:')) {
      const uid = e.id.slice('opening:'.length);
      const leg = (e.legs || []).find((l) => l && l.account === `${PC_PREFIX}${uid}`);
      if (leg) opening.set(uid, (opening.get(uid) || 0) + ledger.naturalDelta(leg.account, leg.dr || 0, leg.cr || 0));
    }
  }
  const accIds = new Set([...state.accounts.keys(), ...recomputed.keys()]);
  for (const id of accIds) {
    const acc = state.accounts.get(id);
    const stored = acc ? acc.balance : 0;
    const type = ledger.accountTypeOf(id);
    const fromJournal = recomputed.get(id) || 0;
    if (isInt(stored)) {
      if (type === 'liability') i2.liabilities += stored; else i2.assets += stored;
    }
    let problem = null;
    if (!type) problem = 'unknown_account_type';
    else if (!isInt(stored)) problem = 'non_integer_balance';
    else if (stored !== fromJournal) problem = 'balance_ne_journal';
    else if (acc && acc.type && acc.type !== type) problem = 'type_mismatch';
    if (problem) {
      i2.accountMismatchCount += 1;
      capPush(i2.accountMismatches, { account: id, stored, fromJournal, problem });
    }
  }
  if (i2.totalDr !== i2.totalCr || i2.assets !== i2.liabilities
      || i2.entryErrorCount || i2.accountMismatchCount) i2.ok = false;

  // ── I-1 / I-3 / I-3F / аномалиялар (ҳар ҳамён) ──────────────────────
  const i1 = { ok: true, mismatches: [], mismatchCount: 0, sumAbsDiff: 0 };
  const i3 = { ok: true, baselineIso: new Date(baselineMs).toISOString(), mismatches: [], mismatchCount: 0 };
  const i3f = { ok: true, mismatches: [], mismatchCount: 0 };
  const anomalies = { ok: true, items: [], count: 0 };
  const flag = (item) => { anomalies.count += 1; capPush(anomalies.items, item); };

  const pcBalance = new Map();
  for (const [id, a] of state.accounts) {
    if (id.startsWith(PC_PREFIX)) pcBalance.set(ledger.ownerUidOf(id), a.balance);
  }
  const uids = new Set([...state.users.keys(), ...pcBalance.keys()]);
  let wallets = 0;
  for (const uid of uids) {
    wallets += 1;
    const rawBonus = state.users.has(uid) ? state.users.get(uid) : 0;
    const exists = state.userExists.get(uid) !== false;
    const pc = pcBalance.has(uid) ? pcBalance.get(uid) : 0;
    if (!isInt(rawBonus)) flag({ uid, kind: 'non_integer_bonus', value: rawBonus });
    if (!isInt(pc)) flag({ uid, kind: 'non_integer_ledger', value: pc });
    if (isInt(rawBonus) && rawBonus < 0) flag({ uid, kind: 'negative_bonus', value: rawBonus });
    if (isInt(pc) && pc < 0) flag({ uid, kind: 'negative_ledger', value: pc });
    if (!exists && pc !== 0) flag({ uid, kind: 'ledger_without_user', value: pc });
    const bonus = isInt(rawBonus) ? rawBonus : NaN;

    // I-1
    if (bonus !== pc) {
      i1.mismatchCount += 1;
      i1.sumAbsDiff += Math.abs((Number(bonus) || 0) - (Number(pc) || 0));
      capPush(i1.mismatches, {
        uid, bonusBalance: rawBonus, ledger: pc, diff: (Number(bonus) || 0) - (Number(pc) || 0),
        hasAccount: pcBalance.has(uid),
      });
    }

    // I-3 / I-3F
    const rows = state.wallet.get(uid) || [];
    let after = 0;
    let all = 0;
    let badRows = 0;
    let undated = 0;
    for (const r of rows) {
      if (r.effect === null) { badRows += 1; continue; }
      all += r.effect;
      if (r.createdAtMs === null) { undated += 1; continue; }
      if (r.createdAtMs >= baselineMs) after += r.effect;
    }
    if (badRows) flag({ uid, kind: 'non_integer_wallet_row', value: badRows });
    if (undated) flag({ uid, kind: 'wallet_row_without_createdAt', value: undated });
    const open = opening.get(uid) || 0;
    if (bonus !== open + after) {
      i3.mismatchCount += 1;
      capPush(i3.mismatches, { uid, bonusBalance: rawBonus, opening: open, walletSinceBaseline: after, diff: (Number(bonus) || 0) - open - after });
    }
    if (bonus !== all) {
      i3f.mismatchCount += 1;
      capPush(i3f.mismatches, { uid, bonusBalance: rawBonus, walletAllTime: all, diff: (Number(bonus) || 0) - all });
    }
  }
  if (i1.mismatchCount) i1.ok = false;
  if (i3.mismatchCount) i3.ok = false;
  if (i3f.mismatchCount) i3f.ok = false;
  if (anomalies.count) anomalies.ok = false;

  const ok = i1.ok && i2.ok && i3.ok && i3f.ok && anomalies.ok;
  return {
    version: 1,
    ok,
    wallets,
    accountCount: state.accounts.size,
    entryCount: state.journal.length,
    reads: state.reads,
    invariants: { I1: i1, I2: i2, I3: i3, I3F: i3f, anomalies },
  };
}

/** Фарқлар имзоси — бир кунда қайта ишга тушса, хабар такрорланмасин. */
function driftSignature(rep) {
  const inv = rep.invariants;
  const parts = [
    ...inv.I1.mismatches.map((m) => `1:${m.uid}:${m.diff}`),
    ...inv.I2.entryErrors.map((m) => `2e:${m.id}:${m.error}`),
    ...inv.I2.accountMismatches.map((m) => `2a:${m.account}:${m.stored}:${m.fromJournal}`),
    `2t:${inv.I2.totalDr}:${inv.I2.totalCr}:${inv.I2.assets}:${inv.I2.liabilities}`,
    ...inv.I3.mismatches.map((m) => `3:${m.uid}:${m.diff}`),
    ...inv.I3F.mismatches.map((m) => `3f:${m.uid}:${m.diff}`),
    ...inv.anomalies.items.map((m) => `a:${m.uid}:${m.kind}:${m.value}`),
  ].sort();
  let h = 0;
  const s = parts.join('|');
  for (let i = 0; i < s.length; i += 1) h = ((h * 31) + s.charCodeAt(i)) | 0;
  return `${parts.length}:${(h >>> 0).toString(16)}`;
}

/** Тошкент санаси (YYYY-MM-DD) — ҳисобот ҳужжати id'си. */
function tashkentDate(nowMs) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Tashkent', year: 'numeric', month: '2-digit', day: '2-digit' })
      .format(new Date(nowMs));
}

function summaryText(rep) {
  const inv = rep.invariants;
  return [
    `I-1 bonusBalance≠ledger: ${inv.I1.mismatchCount} (Σ|фарқ| ${inv.I1.sumAbsDiff})`,
    `I-2 ledger ички: ${inv.I2.ok ? 'OK' : `ХАТО (ёзув ${inv.I2.entryErrorCount}, ҳисоб ${inv.I2.accountMismatchCount}, Σdr ${inv.I2.totalDr}/Σcr ${inv.I2.totalCr})`}`,
    `I-3 тарих (базадан кейин): ${inv.I3.mismatchCount}`,
    `I-3F тарих (тўлиқ): ${inv.I3F.mismatchCount}`,
    `Аномалия: ${inv.anomalies.count}`,
  ].join('\n');
}

/**
 * Битта текширув: ўқийди → баҳолайди → `ledger_reconcile_runs/{сана}` ёзади → drift бўлса structured log
 * `WALLET_PROJECTION_DRIFT` + молияга хабар (имзо ўзгармаган бўлса — шу куни қайта юборилмайди). Тузатмайди.
 */
async function runWalletInvariantCheck({
  db, admin, nowMs = Date.now(), pageSize = 500, notify = null, writeReport = true, log = console,
}) {
  const t0 = Date.now();
  const requestId = `wic_${nowMs}`;
  const state = await collectState(db, { pageSize });
  const rep = evaluate(state);
  const date = tashkentDate(nowMs);
  const signature = rep.ok ? 'ok' : driftSignature(rep);
  const durationMs = Date.now() - t0;
  const logBase = {
    action: 'walletInvariantCheck', requestId, date, durationMs, wallets: rep.wallets,
    entries: rep.entryCount, accounts: rep.accountCount, reads: rep.reads,
    i1: rep.invariants.I1.mismatchCount, i2ok: rep.invariants.I2.ok, i3: rep.invariants.I3.mismatchCount,
    i3f: rep.invariants.I3F.mismatchCount, anomalies: rep.invariants.anomalies.count,
  };
  if (rep.ok) {
    log.log(JSON.stringify({ ...logBase, result: 'ok' }));
  } else {
    log.error(JSON.stringify({
      ...logBase, result: 'drift', errorCode: DRIFT_CODE, signature,
      sample: rep.invariants.I1.mismatches.slice(0, 10).map((m) => ({ uid: mask(m.uid), diff: m.diff })),
    }));
  }
  let notified = null;
  if (writeReport) {
    const ref = db.collection(REPORT_COLLECTION).doc(date);
    const prev = await ref.get();
    const prevData = prev.exists ? (prev.data() || {}) : {};
    const alreadyNotified = prevData.notifiedSignature === signature;
    if (!rep.ok && notify && !alreadyNotified) {
      try {
        notified = await notify({ report: rep, date, text: summaryText(rep) });
      } catch (e) {
        log.error(JSON.stringify({ action: 'walletInvariantCheck', requestId, result: 'notify_failed', errorCode: 'NOTIFY_FAILED', message: String(e && e.message) }));
      }
    }
    await ref.set({
      ...rep,
      date,
      signature,
      baselineIso: BASELINE_ISO,
      checkedAt: admin.firestore.FieldValue.serverTimestamp(),
      durationMs,
      runs: (Number(prevData.runs) || 0) + 1,
      ...(notified
        ? { notifiedSignature: signature, notifiedAt: admin.firestore.FieldValue.serverTimestamp(), notifiedCount: notified.notified || 0 }
        : (alreadyNotified ? { notifiedSignature: prevData.notifiedSignature, notifiedAt: prevData.notifiedAt || null, notifiedCount: prevData.notifiedCount || 0 } : {})),
    }, { merge: false });
  }
  return { ...rep, date, signature, durationMs, notified };
}

/** index.js'га уланади: кунлик 04:00 (Тошкент) scheduled функция. */
function attachWalletInvariants(exportsObj, { functions, db, admin, notifyUserInApp, sendAdminTelegram }) {
  // eslint-disable-next-line global-require
  const { broadcastToFinance } = require('./wallet_topup_support');
  const notify = async ({ report, date, text }) => {
    const res = await broadcastToFinance({
      db,
      notifyUserInApp,
      sendTelegram: null,
      title: 'Ҳамён ҳисоб дафтарида фарқ топилди',
      body: `${date}: I-1 ${report.invariants.I1.mismatchCount}, I-2 ${report.invariants.I2.ok ? 'OK' : 'ХАТО'}, ` +
        `I-3 ${report.invariants.I3.mismatchCount}, I-3F ${report.invariants.I3F.mismatchCount}, аномалия ${report.invariants.anomalies.count}`,
      tgText: '',
      extraData: { kind: 'wallet_invariant_drift', date },
    });
    if (typeof sendAdminTelegram === 'function') {
      await sendAdminTelegram(`⚠️ <b>Ҳамён инвариантлари</b> ${date}\n${text}\nАдмин → ${REPORT_COLLECTION}/${date}`);
    }
    return res;
  };
  exportsObj.walletInvariantDailyCheck = functions
    .runWith({ timeoutSeconds: 540, memory: '512MB' })
    .pubsub.schedule('0 4 * * *')
    .timeZone('Asia/Tashkent')
    .onRun(async () => {
      await runWalletInvariantCheck({ db, admin, notify });
      return null;
    });
}

module.exports = {
  REPORT_COLLECTION,
  BASELINE_ISO,
  BASELINE_MS,
  DRIFT_CODE,
  walletRowEffect,
  collectState,
  evaluate,
  driftSignature,
  tashkentDate,
  runWalletInvariantCheck,
  attachWalletInvariants,
};
