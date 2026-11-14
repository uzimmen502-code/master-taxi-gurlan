'use strict';

/**
 * AVA LOGISTICS — NAQD YETKAZISH HAQI HISOBI (S5, ega CONFIRMED 2026-11-14). Default codebase
 * (pul faqat `settlement_ledger.js` orqali — 43-band; `relay_escrow.js` ga TEGILMAYDI).
 *
 * Demand codebase (`functions_demand/api/logistics.js`) naqd jo'natmada:
 *   shipments.deliveryPayment = { method: 'cash', amount, collectorLegId, collectorLegPayout, status, refusal? }
 *   paymentStatus `cash_on_delivery` (eskrou YO'Q), oxirgi LEG kuryeri xaridordan naqd oladi;
 *   yig'uvchining yetkazish hodisasida `completedLegPayout: 0` (uning haqi naqdda — EARNED yo'q),
 *   oldingi LEG'lar EARNED'i (`relayEarned:{s}:{leg}`, Dr platform_accrual / Cr supplier_payable)
 *   pickup hodisalaridan odatdagidek (`relay_escrow.postEarned`) → `onRelayEarnedCourierPayout` hamyonga.
 *
 * Bu modul `deliveryPayment.status` ga qarab (trigger + reconcile; har qadam idempotent kalit bilan):
 *
 * A) `collected` (yetkazildi) va B1) `refusal_collected` ning CHIQISH qismi — `relayCashSettle:{s}`:
 *      due  = platformShare + (providerPool − keep) + serviceFee(keep)
 *      take = min(due, yig'uvchi hamyoni ≥ 0);  gap = due − take
 *      Dr passenger_credit:{yig'uvchi}  take          (naqd uning qo'lida — hamyondan yechiladi)
 *      Dr admin_clearing               gap           (AVA vaqtincha qoplaydi — Ulgurji `wholesaleReturnAvaCover` naqshi)
 *      Cr platform_accrual             providerPool − keep   (oldingi LEG'lar EARNED'ini yopadi)
 *      Cr earnings:ava_logistics_fee   platformShare
 *      Cr earnings:ava_courier_service_fee  serviceFee(keep)  (`courier_payout.computeFee`, AYNI sozlama)
 *      gap > 0 → `provider_capabilities/{accountId}.debt.logistics += gap` (AYNI tranzaksiya; yo'qolish precedenti).
 *    Yig'uvchi: naqd +amount, hamyon −due → sof = keep − serviceFee (eskrou yetkazishdagi bilan AYNAN teng).
 *
 * B2) `refusal_collected` QAYTISH qismi — `relayCashReturnFund:{returnShipmentId}` (ega 2026-11-14:
 *     xaridor qaytish haqini ham naqd to'laydi): qaytish jo'natmasi (`outboundShipmentId == s`,
 *     `source: wholesale_return`) eskrouga — Dr passenger_credit:{yig'uvchi} take / Dr admin_clearing gap /
 *     Cr escrow:{qaytish} R; qaytish jo'natmasi `escrow_funded/ready` (relay `fund()` bilan bir xil maydonlar,
 *     `fundedBy: 'cash_refusal'`). R = muhrlangan `refusal.returnFee` == qaytish `priceSnapshot.customerPrice`,
 *     aks holda pul YO'Q (anomaliya). Qaytish jo'natmasi hali yo'q → kutiladi (reconcile).
 *
 * C) `refusal_unpaid` (xaridor to'lamadi) — XARIDOR QARZI + AVA qoplaydi:
 *      `relayCashCover:{s}`        Dr admin_clearing (providerPool − keep) / Cr platform_accrual  — oldingi kuryerlar
 *      `relayCashReturnFund:{r}`   Dr admin_clearing R / Cr escrow:{qaytish}                       — qaytish yo'lga chiqadi
 *      `deliveryPayment.buyerDebt = { amount: deliveryFee + R, deliveryFee, returnFee, owedToCollector: keep,
 *        avaCovered: (providerPool − keep) + R }` + `logistics_audit/cash_buyer_debt_{s}`.
 *      Yig'uvchining o'z chiqish LEG haqi (keep) va AVA ulushi — XARIDOR QARZIDAN (avtomatik to'lanmaydi;
 *      OCHIQ SAVOL egaga — hisobotda).
 *
 * Yakun: `paymentStatus: settled`, `deliveryPayment.status: settled`, `deliveryPayment.settlement`.
 * Anomaliya (pul yo'q): `deliveryPayment.settleAnomaly = { code, at, attempts }` — reconcile qayta urinadi.
 * Log: PII yo'q (telefon yo'q) — faqat jo'natma/LEG identifikatorlari va summalar (24-band).
 */

const courierPayout = require('./courier_payout');

const SHIPMENTS = 'shipments';
const CAPS = 'provider_capabilities';
const LOGISTICS_AUDIT = 'logistics_audit';
const PLATFORM_FEE_ACCOUNT = 'earnings:ava_logistics_fee';
const SERVICE_FEE_ACCOUNT = courierPayout.FEE_ACCOUNT;
const ACCRUAL_ACCOUNT = 'platform_accrual';
const AVA_COVER_ACCOUNT = 'admin_clearing';
const CASH = 'cash';
const ST = Object.freeze({
  PENDING: 'pending',
  COLLECTED: 'collected',
  REFUSAL_COLLECTED: 'refusal_collected',
  REFUSAL_UNPAID: 'refusal_unpaid',
  SETTLED: 'settled',
});
const SETTLE_STATUSES = Object.freeze([ST.COLLECTED, ST.REFUSAL_COLLECTED, ST.REFUSAL_UNPAID]);
const RECONCILE_LIMIT = 100;

const isInt = (n) => typeof n === 'number' && Number.isSafeInteger(n);
const isNonNeg = (n) => isInt(n) && n >= 0;
const settleKey = (s) => `relayCashSettle:${s}`;
const coverKey = (s) => `relayCashCover:${s}`;
const returnFundKey = (r) => `relayCashReturnFund:${r}`;
const anomalyErr = (code, extra) => Object.assign(new Error(code), { cashAnomaly: true, code, ...(extra || {}) });

/**
 * A/B1 — sof hisob (Firestore yo'q). Qaytaradi `{ due, take, gap, earlier, legs }`;
 * noto'g'ri kirish → Error(code). `legs` — settlement_ledger shakli (0 lar tashlab ketiladi).
 */
function planCashOutbound({
  amount, platformShare, providerPool, keep, serviceFee, balance, walletAccount,
}) {
  if (![amount, platformShare, providerPool, keep, serviceFee].every(isNonNeg) || amount <= 0) throw anomalyErr('cash_amounts_invalid');
  if (platformShare + providerPool !== amount) throw anomalyErr('cash_split_mismatch');
  if (keep > providerPool) throw anomalyErr('cash_keep_exceeds_pool');
  if (serviceFee > keep) throw anomalyErr('cash_service_fee_invalid');
  const earlier = providerPool - keep;
  const due = platformShare + earlier + serviceFee;
  const avail = isInt(balance) && balance > 0 ? balance : 0;
  const take = Math.min(due, avail);
  const gap = due - take;
  const legs = [];
  if (take > 0) legs.push({ account: walletAccount, dr: take });
  if (gap > 0) legs.push({ account: AVA_COVER_ACCOUNT, dr: gap });
  if (earlier > 0) legs.push({ account: ACCRUAL_ACCOUNT, cr: earlier });
  if (platformShare > 0) legs.push({ account: PLATFORM_FEE_ACCOUNT, cr: platformShare });
  if (serviceFee > 0) legs.push({ account: SERVICE_FEE_ACCOUNT, cr: serviceFee });
  return {
    due, take, gap, earlier, legs,
  };
}

/** B2 — qaytish haqi: yig'uvchi hamyonidan (yetmasa AVA + qarz) yoki (C) to'liq AVA. */
function planReturnFund({
  returnFee, balance, walletAccount, escrowAccount, avaOnly,
}) {
  if (!isInt(returnFee) || returnFee <= 0) throw anomalyErr('return_fee_invalid');
  const avail = !avaOnly && isInt(balance) && balance > 0 ? balance : 0;
  const take = Math.min(returnFee, avail);
  const gap = returnFee - take;
  const legs = [];
  if (take > 0) legs.push({ account: walletAccount, dr: take });
  if (gap > 0) legs.push({ account: AVA_COVER_ACCOUNT, dr: gap });
  legs.push({ account: escrowAccount, cr: returnFee });
  return { take, gap, legs };
}

/** C — xaridor to'lamadi: AVA qoplaydigan va xaridor qarzi. */
function planUnpaidRefusal({
  deliveryFee, returnFee, providerPool, keep,
}) {
  if (![deliveryFee, returnFee, providerPool, keep].every(isNonNeg) || deliveryFee <= 0 || returnFee <= 0) {
    throw anomalyErr('cash_amounts_invalid');
  }
  if (keep > providerPool) throw anomalyErr('cash_keep_exceeds_pool');
  const coverOutbound = providerPool - keep;
  return {
    coverOutbound,
    coverReturn: returnFee,
    avaCovered: coverOutbound + returnFee,
    buyerDebt: deliveryFee + returnFee,
    owedToCollector: keep,
  };
}

function attachRelayCash(exportsObj, deps) {
  const {
    functions, db, admin, canonicalUid, settlementLedger, now: nowFn,
  } = deps;
  const now = () => (nowFn ? nowFn() : new Date());
  const inc = (n) => admin.firestore.FieldValue.increment(n);
  const balOf = async (acc) => {
    const s = await db.collection(settlementLedger.COL_ACCOUNTS).doc(acc).get();
    return s.exists ? (Number((s.data() || {}).balance) || 0) : 0;
  };
  const journalExists = async (key) => (await db.collection(settlementLedger.COL_JOURNAL).doc(key).get()).exists;
  const log = (fields, level) => {
    const line = JSON.stringify({ module: 'relay_cash', ...fields });
    if (level === 'error') console.error(line); else if (level === 'warn') console.warn(line); else console.log(line);
  };

  /** Kanonik telefon → `users` hujjat id (12, keyin 9 xonali) va `accountId` (qarz uchun). */
  async function userOf(phone) {
    const canon = canonicalUid(phone || '');
    if (!/^998\d{9}$/.test(canon)) return null;
    for (const id of [canon, canon.slice(3)]) {
      const s = await db.collection('users').doc(id).get();
      if (s.exists) {
        const a = (s.data() || {}).accountId;
        return { walletUid: id, accountId: typeof a === 'string' && a.trim() ? a.trim() : '' };
      }
    }
    return null;
  }

  async function serviceFeeOf(keep) {
    if (!keep) return { fee: 0, feeBps: 0, feeVersion: 0 };
    const s = await db.collection(courierPayout.SETTINGS_DOC[0]).doc(courierPayout.SETTINGS_DOC[1]).get();
    const st = courierPayout.parseSettings(s.exists ? s.data() : null);
    if (!st.valid) throw anomalyErr('fee_config_invalid');
    return { fee: courierPayout.computeFee(keep, st.feeBps), feeBps: st.feeBps, feeVersion: st.feeVersion };
  }

  async function markAnomaly(shipmentId, code) {
    const ref = db.collection(SHIPMENTS).doc(shipmentId);
    await db.runTransaction(async (t) => {
      const s = await t.get(ref);
      const dp = (s.data() || {}).deliveryPayment || {};
      const prev = dp.settleAnomaly && isInt(dp.settleAnomaly.attempts) ? dp.settleAnomaly.attempts : 0;
      t.update(ref, { 'deliveryPayment.settleAnomaly': { code, at: now(), attempts: prev + 1 }, updatedAt: now() });
    });
  }

  /**
   * Hamyondan yechish — balans tashqarida o'qiladi, tranzaksiyada `prev` AYNAN shu bo'lishi shart
   * (o'zgargan bo'lsa qayta hisob — 3 urinish): `take` deterministik, hamyon manfiyga TUSHMAYDI.
   */
  async function postWithWallet(walletAccount, build, post) {
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const balance = await balOf(walletAccount);
      const plan = build(balance);
      try {
        return { plan, res: await post(plan, balance) };
      } catch (e) {
        if (e && e.reason === 'balance_changed') continue;
        throw e;
      }
    }
    throw anomalyErr('wallet_balance_race');
  }

  // ── A / B1: chiqish qismi ─────────────────────────────────────────────
  async function settleOutbound(shipmentId, ship, internal, kind) {
    const key = settleKey(shipmentId);
    if (await journalExists(key)) return { idempotent: true };
    const dp = ship.deliveryPayment || {};
    const collectorId = canonicalUid(kind === 'delivery' ? dp.collectedBy : (dp.refusal || {}).collectorId);
    const user = await userOf(collectorId);
    if (!user) throw anomalyErr('collector_wallet_missing');
    const amount = kind === 'delivery' ? dp.amount : (dp.refusal || {}).deliveryFee;
    if (amount !== (ship.priceSnapshot || {}).customerPrice) throw anomalyErr('cash_amount_mismatch');
    const keep = dp.collectorLegPayout;
    const fee = await serviceFeeOf(keep);
    const walletAccount = settlementLedger.passengerCreditAccount(user.walletUid);
    const shipRef = db.collection(SHIPMENTS).doc(shipmentId);
    const { plan, res } = await postWithWallet(walletAccount, (balance) => planCashOutbound({
      amount, platformShare: internal.platformShare, providerPool: internal.providerPool, keep, serviceFee: fee.fee,
      balance, walletAccount,
    }), (p, balance) => {
      if (p.gap > 0 && !user.accountId) throw anomalyErr('collector_account_missing');
      const when = now();
      return settlementLedger.postEntry(db, {
        idempotencyKey: key,
        kind: 'logistics_cash_settle',
        refType: 'shipment',
        refId: shipmentId,
        postedBy: 'system',
        postedRole: 'system',
        legs: p.legs,
      }, {
        mirrorBonus: true,
        walletLedgerType: 'logistics_cash_settle',
        meta: {
          shipmentId, kind, amount, keep, earlier: p.earlier, platformShare: internal.platformShare,
          serviceFee: fee.fee, feeBps: fee.feeBps, feeVersion: fee.feeVersion, take: p.take, gap: p.gap,
          legId: dp.collectorLegId || null,
        },
        precheck: async (tx) => {
          const s = await tx.get(shipRef);
          const d = s.exists ? (s.data() || {}) : {};
          const st = (d.deliveryPayment || {}).status;
          if (d.paymentStatus !== 'cash_on_delivery' || st !== dp.status) {
            throw anomalyErr('cash_state_changed', { status: st || null });
          }
          return d;
        },
        assert: ({ accounts }) => {
          const w = accounts.get(walletAccount);
          if (p.take > 0 && (!w || w.prev !== balance)) throw Object.assign(new Error('balance_changed'), { reason: 'balance_changed' });
          if (w && w.next < 0) throw Object.assign(new Error('balance_changed'), { reason: 'balance_changed' });
        },
        onCommit: (tx) => {
          if (p.gap > 0) {
            tx.set(db.collection(CAPS).doc(user.accountId), { debt: { logistics: inc(p.gap) }, updatedAt: when }, { merge: true });
          }
          tx.update(shipRef, {
            'deliveryPayment.settlement.outbound': {
              entryId: key, kind, due: p.due, take: p.take, gap: p.gap, keep, earlier: p.earlier,
              platformShare: internal.platformShare, serviceFee: fee.fee, at: when,
            },
            updatedAt: when,
          });
          tx.set(db.collection(LOGISTICS_AUDIT).doc(`cash_settle_${shipmentId}`), {
            kind: 'cash_settle', shipmentId, settleKind: kind, entryId: key, amount, due: p.due, take: p.take,
            courierDebt: p.gap, avaCovered: p.gap, accountId: p.gap > 0 ? user.accountId : null, by: 'system', at: when,
          });
        },
      });
    });
    log({ action: 'cashSettle', result: res.idempotent ? 'idempotent' : 'ok', shipmentId, kind, due: plan.due, take: plan.take, gap: plan.gap });
    return { posted: !res.idempotent, ...plan };
  }

  // ── C: AVA oldingi kuryerlarni qoplaydi ───────────────────────────────
  async function coverOutbound(shipmentId, ship, internal) {
    const key = coverKey(shipmentId);
    if (await journalExists(key)) return { idempotent: true };
    const dp = ship.deliveryPayment || {};
    const r = dp.refusal || {};
    const plan = planUnpaidRefusal({
      deliveryFee: r.deliveryFee, returnFee: r.returnFee, providerPool: internal.providerPool, keep: dp.collectorLegPayout,
    });
    if (r.deliveryFee !== (ship.priceSnapshot || {}).customerPrice) throw anomalyErr('cash_amount_mismatch');
    const shipRef = db.collection(SHIPMENTS).doc(shipmentId);
    const when = now();
    const write = (tx) => {
      tx.update(shipRef, {
        'deliveryPayment.buyerDebt': {
          amount: plan.buyerDebt, deliveryFee: r.deliveryFee, returnFee: r.returnFee,
          owedToCollector: plan.owedToCollector, avaCovered: plan.avaCovered, status: 'open', at: when,
        },
        'deliveryPayment.settlement.outbound': { entryId: plan.coverOutbound > 0 ? key : null, kind: 'refusal_unpaid', avaCovered: plan.coverOutbound, at: when },
        updatedAt: when,
      });
      tx.set(db.collection(LOGISTICS_AUDIT).doc(`cash_buyer_debt_${shipmentId}`), {
        kind: 'cash_buyer_debt', shipmentId, wholesaleOrderId: ship.wholesaleOrderId || null,
        amount: plan.buyerDebt, deliveryFee: r.deliveryFee, returnFee: r.returnFee,
        owedToCollector: plan.owedToCollector, avaCovered: plan.avaCovered, by: 'system', at: when,
      });
    };
    if (plan.coverOutbound === 0) {
      // Oldingi LEG yo'q (bitta LEG) — pul yozuvi yo'q, faqat qarz qaydi (bir marta).
      await db.runTransaction(async (tx) => {
        const s = await tx.get(shipRef);
        if (((s.data() || {}).deliveryPayment || {}).buyerDebt) return;
        write(tx);
      });
      return { posted: false, ...plan };
    }
    const res = await settlementLedger.postEntry(db, {
      idempotencyKey: key,
      kind: 'logistics_cash_ava_cover',
      refType: 'shipment',
      refId: shipmentId,
      postedBy: 'system',
      postedRole: 'system',
      legs: [{ account: AVA_COVER_ACCOUNT, dr: plan.coverOutbound }, { account: ACCRUAL_ACCOUNT, cr: plan.coverOutbound }],
    }, {
      mirrorBonus: false,
      meta: { shipmentId, coverOutbound: plan.coverOutbound, buyerDebt: plan.buyerDebt },
      precheck: async (tx) => {
        const s = await tx.get(shipRef);
        const d = s.exists ? (s.data() || {}) : {};
        if (d.paymentStatus !== 'cash_on_delivery' || (d.deliveryPayment || {}).status !== ST.REFUSAL_UNPAID) {
          throw anomalyErr('cash_state_changed');
        }
        return d;
      },
      onCommit: (tx) => write(tx),
    });
    log({ action: 'cashCover', result: res.idempotent ? 'idempotent' : 'ok', shipmentId, avaCovered: plan.avaCovered, buyerDebt: plan.buyerDebt });
    return { posted: !res.idempotent, ...plan };
  }

  // ── B2 / C: qaytish jo'natmasi eskrousi ───────────────────────────────
  async function findReturnShipment(shipmentId) {
    const q = await db.collection(SHIPMENTS).where('outboundShipmentId', '==', shipmentId).limit(5).get();
    const docs = q.docs.filter((d) => (d.data() || {}).source === 'wholesale_return');
    if (docs.length > 1) throw anomalyErr('return_shipment_ambiguous');
    return docs[0] || null;
  }

  async function fundReturn(shipmentId, ship, avaOnly) {
    const dp = ship.deliveryPayment || {};
    const r = dp.refusal || {};
    const ret = await findReturnShipment(shipmentId);
    if (!ret) return { waiting: true };
    const key = returnFundKey(ret.id);
    if (await journalExists(key)) return { idempotent: true, returnShipmentId: ret.id };
    const rs = ret.data() || {};
    if ((rs.priceSnapshot || {}).customerPrice !== r.returnFee) throw anomalyErr('return_fee_mismatch');
    if (rs.status !== 'awaiting_payment' || rs.paymentStatus !== 'pending') throw anomalyErr('return_not_payable');
    const user = avaOnly ? null : await userOf(r.collectorId);
    if (!avaOnly && !user) throw anomalyErr('collector_wallet_missing');
    const walletAccount = user ? settlementLedger.passengerCreditAccount(user.walletUid) : null;
    const escrow = `escrow:${ret.id}`;
    const retRef = ret.ref;
    const outRef = db.collection(SHIPMENTS).doc(shipmentId);
    const post = (p, balance) => {
      if (p.gap > 0 && !avaOnly && !user.accountId) throw anomalyErr('collector_account_missing');
      const when = now();
      return settlementLedger.postEntry(db, {
        idempotencyKey: key,
        kind: 'logistics_cash_return_fund',
        refType: 'shipment',
        refId: ret.id,
        postedBy: 'system',
        postedRole: 'system',
        legs: p.legs,
      }, {
        mirrorBonus: !avaOnly,
        walletLedgerType: avaOnly ? null : 'logistics_cash_return_fund',
        meta: {
          shipmentId: ret.id, outboundShipmentId: shipmentId, returnFee: r.returnFee, take: p.take, gap: p.gap, avaOnly: !!avaOnly,
        },
        precheck: async (tx) => {
          const [s, o] = await Promise.all([tx.get(retRef), tx.get(outRef)]);
          const d = s.exists ? (s.data() || {}) : {};
          if (d.status !== 'awaiting_payment' || d.paymentStatus !== 'pending') throw anomalyErr('return_not_payable');
          const ost = ((o.data() || {}).deliveryPayment || {}).status;
          if (ost !== dp.status) throw anomalyErr('cash_state_changed');
          return d;
        },
        assert: ({ accounts }) => {
          if (!walletAccount) return;
          const w = accounts.get(walletAccount);
          if (p.take > 0 && (!w || w.prev !== balance)) throw Object.assign(new Error('balance_changed'), { reason: 'balance_changed' });
          if (w && w.next < 0) throw Object.assign(new Error('balance_changed'), { reason: 'balance_changed' });
        },
        onCommit: (tx) => {
          if (p.gap > 0 && !avaOnly) {
            tx.set(db.collection(CAPS).doc(user.accountId), { debt: { logistics: inc(p.gap) }, updatedAt: when }, { merge: true });
          }
          tx.update(retRef, {
            paymentStatus: 'escrow_funded', status: 'ready', fundedAt: when,
            escrowEntryId: key, escrowAmount: r.returnFee, fundedBy: 'cash_refusal', updatedAt: when,
          });
          tx.update(outRef, {
            'deliveryPayment.settlement.return': {
              entryId: key, returnShipmentId: ret.id, returnFee: r.returnFee, take: p.take, gap: p.gap, avaOnly: !!avaOnly, at: when,
            },
            updatedAt: when,
          });
        },
      });
    };
    let out;
    if (avaOnly) {
      const p = planReturnFund({ returnFee: r.returnFee, escrowAccount: escrow, avaOnly: true });
      out = { plan: p, res: await post(p, 0) };
    } else {
      out = await postWithWallet(walletAccount, (balance) => planReturnFund({
        returnFee: r.returnFee, balance, walletAccount, escrowAccount: escrow,
      }), post);
    }
    log({
      action: 'cashReturnFund', result: out.res.idempotent ? 'idempotent' : 'ok', shipmentId, returnShipmentId: ret.id,
      returnFee: r.returnFee, take: out.plan.take, gap: out.plan.gap, avaOnly: !!avaOnly,
    });
    return { posted: !out.res.idempotent, returnShipmentId: ret.id, ...out.plan };
  }

  /** Hamma kerakli yozuvlar bor → `settled` (bir marta, tranzaksiyada). */
  async function finalize(shipmentId, needKeys) {
    for (const k of needKeys) if (!(await journalExists(k))) return { pending: k };
    const ref = db.collection(SHIPMENTS).doc(shipmentId);
    const when = now();
    return db.runTransaction(async (tx) => {
      const s = await tx.get(ref);
      const d = s.data() || {};
      if (d.paymentStatus === 'settled') return { already: true };
      if (d.paymentStatus !== 'cash_on_delivery') return { skipped: `payment_${d.paymentStatus}` };
      tx.update(ref, {
        paymentStatus: 'settled', settledAt: when,
        'deliveryPayment.status': ST.SETTLED, 'deliveryPayment.settledFrom': (d.deliveryPayment || {}).status || null,
        'deliveryPayment.settleAnomaly': null, updatedAt: when,
      });
      return { settled: true };
    });
  }

  /** Bitta naqd jo'natma — trigger va reconcile shu yerdan. */
  async function processShipment(shipmentId) {
    const started = Date.now();
    const ref = db.collection(SHIPMENTS).doc(shipmentId);
    const [s, i] = await Promise.all([ref.get(), ref.collection('private').doc('internal').get()]);
    if (!s.exists) return { skipped: 'missing' };
    const ship = s.data() || {};
    const dp = ship.deliveryPayment || {};
    if (dp.method !== CASH) return { skipped: 'not_cash' };
    if (!SETTLE_STATUSES.includes(dp.status)) return { skipped: `status_${dp.status || 'none'}` };
    if (ship.paymentStatus !== 'cash_on_delivery') return { skipped: `payment_${ship.paymentStatus}` };
    const internal = i.exists ? (i.data() || {}) : {};
    try {
      let out;
      if (dp.status === ST.COLLECTED) {
        const a = await settleOutbound(shipmentId, ship, internal, 'delivery');
        out = { outbound: a, final: await finalize(shipmentId, [settleKey(shipmentId)]) };
      } else if (dp.status === ST.REFUSAL_COLLECTED) {
        const a = await settleOutbound(shipmentId, ship, internal, 'refusal');
        const b = await fundReturn(shipmentId, ship, false);
        out = { outbound: a, ret: b, final: b.waiting ? { pending: 'return_shipment' } : await finalize(shipmentId, [settleKey(shipmentId), returnFundKey(b.returnShipmentId)]) };
      } else {
        const a = await coverOutbound(shipmentId, ship, internal);
        const b = await fundReturn(shipmentId, ship, true);
        const need = [returnFundKey(b.returnShipmentId)];
        if (a.coverOutbound > 0) need.push(coverKey(shipmentId));
        out = { cover: a, ret: b, final: b.waiting ? { pending: 'return_shipment' } : await finalize(shipmentId, need) };
      }
      log({ action: 'processCashShipment', result: 'ok', shipmentId, status: dp.status, final: out.final, durationMs: Date.now() - started });
      return out;
    } catch (e) {
      if (e && e.cashAnomaly) {
        await markAnomaly(shipmentId, e.code);
        log({ action: 'processCashShipment', result: 'anomaly', shipmentId, errorCode: `RELAY_CASH_${String(e.code).toUpperCase()}` }, 'error');
        return { anomaly: e.code };
      }
      log({ action: 'processCashShipment', result: 'error', shipmentId, errorCode: 'RELAY_CASH_FAILED', message: String(e && e.message).slice(0, 200) }, 'error');
      throw e;
    }
  }

  async function reconcile({ limit = RECONCILE_LIMIT } = {}) {
    const out = { scanned: 0, settled: 0, anomalies: 0, pending: 0, failed: 0 };
    const snap = await db.collection(SHIPMENTS).where('deliveryPayment.status', 'in', [...SETTLE_STATUSES]).limit(limit).get();
    for (const d of snap.docs) {
      out.scanned += 1;
      try {
        const r = await processShipment(d.id);
        if (r.anomaly) out.anomalies += 1;
        else if (r.final && (r.final.settled || r.final.already)) out.settled += 1;
        else out.pending += 1;
      } catch (e) {
        out.failed += 1;
      }
    }
    log({ action: 'relayCashReconcile', result: 'done', ...out }, out.anomalies || out.failed ? 'warn' : undefined);
    return out;
  }

  // ── Triggerlar (YANGI nomlar — mavjud relay funksiyalariga tegilmaydi; deploy nomi bilan) ──
  exportsObj.onRelayCashShipmentUpdate = functions.firestore
    .document(`${SHIPMENTS}/{shipmentId}`)
    .onUpdate(async (change, context) => {
      const b = ((change.before.data() || {}).deliveryPayment) || {};
      const a = ((change.after.data() || {}).deliveryPayment) || {};
      if (a.method !== CASH || b.status === a.status || !SETTLE_STATUSES.includes(a.status)) return null;
      await processShipment(context.params.shipmentId);
      return null;
    });

  exportsObj.relayCashReconcile = functions
    .runWith({ timeoutSeconds: 300 })
    .pubsub.schedule('every 15 minutes')
    .onRun(async () => { await reconcile(); return null; });

  return {
    processShipment, reconcile, settleOutbound, coverOutbound, fundReturn,
  };
}

module.exports = {
  ST,
  SETTLE_STATUSES,
  AVA_COVER_ACCOUNT,
  settleKey,
  coverKey,
  returnFundKey,
  planCashOutbound,
  planReturnFund,
  planUnpaidRefusal,
  attachRelayCash,
};
