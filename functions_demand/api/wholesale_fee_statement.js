'use strict';

/**
 * ULGURJI — AVA ULUSHI HISOBOTI (ega, 2026-11-14: «ҳар 10 кунда буюртмалар учун сотувчилардан олинадиган
 * 2% ҳисоботи»), demand codebase (europe-west1). FAQAT qat'iy admin (`assertStrictAdmin`: admin/superadmin).
 *
 *   adminGetWholesaleFeeStatement({periodStart:'YYYY-MM-DD'})
 *       10 kunlik davr (Asia/Tashkent): 1–10, 11–20, 21–oy oxiri. `periodStart` — 01 | 11 | 21.
 *       Davrda YETKAZILGAN (`status == delivered`, `deliveredAt` davr ichida) va AVA ulushi buyurtma
 *       paytida AVTOMATIK OLINMAGAN usullar (`FEE_STATEMENT_METHODS`; hozir faqat `bank_transfer`) —
 *       sotuvchi bo'yicha: soni, tovar summasi, AVA ulushi qarzi (muhrlangan `private/settlement.avaFee`
 *       yig'indisi, butun so'm) + jami + «yig'ildi» belgisi (`admin_audit`).
 *   adminGetWholesaleOrdersReport({month:'YYYY-MM'})
 *       Oylik: HAMMA usul, sotuvchi × usul — soni, tovar summasi, yetkazish haqi, AVA ulushi va u qanday
 *       olinadi (`release` — yetkazilganda ledger orqali; `statement` — shu hisobot orqali).
 *   adminMarkWholesaleFeeCollected({sellerId, periodStart, note?})
 *       Sotuvchidan shu davr ulushi olindi — `admin_audit/wholesale_fee_collected_{sotuvchi}_{davr}`
 *       (deterministik ID — idempotent; summa SERVERDA qayta hisoblanadi, klientdan olinmaydi). Pul
 *       harakati YO'Q (to'lov ilovadan tashqarida) — faqat audit yozuvi (41-band). Faqat yopilgan davr.
 *
 * O'qish narxi (37-band): bitta so'rov (davrdagi yetkazilgan buyurtmalar) + har buyurtmaga 1 o'qish
 * (`private/settlement`, `getAll` 100 talik bo'laklarda) + har sotuvchiga 1 o'qish (yig'ildi belgisi).
 * `MAX_ORDERS` dan ortig'i — `truncated: true` (jimgina kesilmaydi).
 * Kompozit indekslar (yaratilmagan — deploy ro'yxatida):
 *   wholesale_orders (paymentMethod ASC, status ASC, deliveredAt ASC) — 10 kunlik hisobot (`in` + tenglik + oraliq);
 *   wholesale_orders (status ASC, deliveredAt ASC)                   — oylik hisobot.
 * Log — telefon YO'Q (24, 40-band).
 */

const { toCanonicalId } = require('../core/ids');
const WO = require('../core/wholesale_orders');
const { assertStrictAdmin } = require('../analytics/access');

const ORDERS = 'wholesale_orders';
const PRIVATE = 'private';
const ADMIN_AUDIT = 'admin_audit';
/** AVA ulushi buyurtma paytida OLINMAYDIGAN (hisobot orqali yig'iladigan) usullar. O'z yetkazishi — keyin shu yerga. */
const FEE_STATEMENT_METHODS = Object.freeze([WO.PAYMENT_METHOD.BANK]);
const MAX_ORDERS = 5000;
const GETALL_CHUNK = 100;
const NOTE_MAX = 300;
const DAY_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const MONTH_RE = /^(\d{4})-(\d{2})$/;

function fail(code, message, reason, extra) {
  const e = new Error(message);
  e.code = code;
  e.httpErrorCode = code;
  e.details = { reason: reason || code, ...(extra || {}) };
  return e;
}

const isInt = (n) => typeof n === 'number' && Number.isInteger(n);

function log(action, fields) {
  console.log(JSON.stringify({ module: 'wholesale_fee_statement', action, ...fields }));
}

const pad = (n) => String(n).padStart(2, '0');
/** Toshkent mahalliy kun boshi (00:00) → UTC ms. */
const localDayStartMs = (y, m, d) => Date.UTC(y, m - 1, d) - WO.TASHKENT_OFFSET_MS;
const ymd = (y, m, d) => `${y}-${pad(m)}-${pad(d)}`;

/**
 * 10 kunlik davr (sof). `periodStart` — haqiqiy sana, kuni 01 | 11 | 21. Oxiri (EXCLUSIVE):
 * 01 → 11, 11 → 21, 21 → keyingi oyning 1-kuni (oy oxirigacha — 28/29/30/31 avtomatik).
 * @returns {{periodStart, periodEnd, startMs, endMs, lastDay}}
 */
function parsePeriod(raw) {
  const m = DAY_RE.exec(String(raw == null ? '' : raw).trim());
  const bad = () => fail('invalid-argument', 'Davr boshi YYYY-MM-DD (01, 11 yoki 21-kun)', 'period_invalid');
  if (!m) throw bad();
  const y = Number(m[1]);
  const mo = Number(m[2]);
  const d = Number(m[3]);
  if (y < 2020 || y > 2100 || mo < 1 || mo > 12 || ![1, 11, 21].includes(d)) throw bad();
  const startMs = localDayStartMs(y, mo, d);
  let endY = y;
  let endM = mo;
  let endD = d + 10;
  if (d === 21) {
    endD = 1;
    endM = mo === 12 ? 1 : mo + 1;
    endY = mo === 12 ? y + 1 : y;
  }
  const endMs = localDayStartMs(endY, endM, endD);
  const last = new Date(endMs + WO.TASHKENT_OFFSET_MS - 1);
  return {
    periodStart: ymd(y, mo, d),
    periodEnd: ymd(endY, endM, endD),
    lastDay: ymd(last.getUTCFullYear(), last.getUTCMonth() + 1, last.getUTCDate()),
    startMs,
    endMs,
  };
}

/** Oy (sof): `YYYY-MM` → [1-kun 00:00, keyingi oy 1-kun 00:00) Toshkent vaqtida. */
function parseMonth(raw) {
  const m = MONTH_RE.exec(String(raw == null ? '' : raw).trim());
  if (!m) throw fail('invalid-argument', 'Oy YYYY-MM shaklida', 'month_invalid');
  const y = Number(m[1]);
  const mo = Number(m[2]);
  if (y < 2020 || y > 2100 || mo < 1 || mo > 12) throw fail('invalid-argument', 'Oy YYYY-MM shaklida', 'month_invalid');
  const nY = mo === 12 ? y + 1 : y;
  const nM = mo === 12 ? 1 : mo + 1;
  return {
    month: `${y}-${pad(mo)}`, startMs: localDayStartMs(y, mo, 1), endMs: localDayStartMs(nY, nM, 1),
  };
}

const collectedDocId = (sellerKey, periodStart) => `wholesale_fee_collected_${sellerKey}_${periodStart}`;
/** «Yig'ildi» audit yozuvidagi summa (yo'q / buzilgan — null). */
const storedDue = (a) => {
  const v = ((a || {}).detail || {}).avaFeeDue;
  return isInt(v) ? v : null;
};

/** Muhrlangan settlement hujjatlari (`getAll`, bo'laklarda). @returns {Map<orderId, data|null>} */
async function readSettlements(db, orderIds) {
  const out = new Map();
  for (let i = 0; i < orderIds.length; i += GETALL_CHUNK) {
    const ids = orderIds.slice(i, i + GETALL_CHUNK);
    const refs = ids.map((id) => db.collection(ORDERS).doc(id).collection(PRIVATE).doc('settlement'));
    const snaps = ids.length ? await db.getAll(...refs) : [];
    snaps.forEach((s, k) => out.set(ids[k], s.exists ? (s.data() || {}) : null));
  }
  return out;
}

/**
 * Davrdagi yetkazilgan buyurtmalar (so'rov) — `methods` berilsa `in` filtri bilan.
 * @returns {{docs: Array<{id, o}>, truncated: boolean}}
 */
async function deliveredIn(db, startMs, endMs, methods) {
  let q = db.collection(ORDERS);
  if (methods) q = q.where('paymentMethod', 'in', [...methods]);
  const snap = await q.where('status', '==', WO.STATUS.DELIVERED)
    .where('deliveredAt', '>=', new Date(startMs))
    .where('deliveredAt', '<', new Date(endMs))
    .limit(MAX_ORDERS + 1)
    .get();
  const docs = snap.docs.slice(0, MAX_ORDERS).map((d) => ({ id: d.id, o: d.data() || {} }));
  return { docs, truncated: snap.docs.length > MAX_ORDERS };
}

/**
 * Sotuvchi bo'yicha AVA ulushi qarzi (sof hisob, testlanadi). Muhr buzilgan buyurtma — `anomalies`
 * ga (summaga QO'SHILMAYDI, pul o'ylab topilmaydi).
 */
function buildStatement(rows, settlements) {
  const bySeller = new Map();
  const anomalies = [];
  for (const { id, o } of rows) {
    const st = settlements.get(id);
    const sellerKey = toCanonicalId(o.sellerId) || String(o.sellerId || '');
    if (!st || !isInt(st.avaFee) || st.avaFee < 0 || !isInt(o.goodsTotal) || o.goodsTotal <= 0
      || (isInt(st.goodsTotal) && st.goodsTotal !== o.goodsTotal)) {
      anomalies.push({ orderId: id, sellerId: sellerKey, code: 'settlement_invalid' });
      continue;
    }
    const cur = bySeller.get(sellerKey) || {
      sellerId: sellerKey, count: 0, goodsTotal: 0, avaFeeDue: 0, methods: {}, orderIds: [],
    };
    cur.count += 1;
    cur.goodsTotal += o.goodsTotal;
    cur.avaFeeDue += st.avaFee;
    const m = WO.methodOf(o);
    cur.methods[m] = (cur.methods[m] || 0) + 1;
    cur.orderIds.push(id);
    bySeller.set(sellerKey, cur);
  }
  const sellers = [...bySeller.values()].sort((a, b) => (b.avaFeeDue - a.avaFeeDue) || (a.sellerId < b.sellerId ? -1 : 1));
  const totals = sellers.reduce((t, s) => ({
    sellers: t.sellers + 1, count: t.count + s.count, goodsTotal: t.goodsTotal + s.goodsTotal, avaFeeDue: t.avaFeeDue + s.avaFeeDue,
  }), {
    sellers: 0, count: 0, goodsTotal: 0, avaFeeDue: 0,
  });
  if (![totals.goodsTotal, totals.avaFeeDue].every(Number.isSafeInteger)) {
    throw fail('failed-precondition', 'Summa juda katta', 'amount_too_large');
  }
  return { sellers, totals, anomalies };
}

const msOf = (v) => {
  if (v == null) return null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return null;
};

/** Bir davr uchun hisobot (callable va «yig'ildi» qayta hisobi uchun umumiy). */
async function computeStatement(db, period) {
  const { docs, truncated } = await deliveredIn(db, period.startMs, period.endMs, FEE_STATEMENT_METHODS);
  const settlements = await readSettlements(db, docs.map((d) => d.id));
  return { ...buildStatement(docs, settlements), truncated };
}

function makeAdminGetWholesaleFeeStatement(deps) {
  const { db, now: nowFn } = deps;
  return async function adminGetWholesaleFeeStatement(data, context) {
    const started = Date.now();
    await assertStrictAdmin(db, context);
    const period = parsePeriod((data || {}).periodStart);
    const st = await computeStatement(db, period);
    // «Yig'ildi» belgilari — har sotuvchiga bitta o'qish (deterministik audit ID).
    const refs = st.sellers.map((s) => db.collection(ADMIN_AUDIT).doc(collectedDocId(s.sellerId, period.periodStart)));
    const marks = refs.length ? await db.getAll(...refs) : [];
    const nowMs = (nowFn ? nowFn() : new Date()).getTime();
    const sellers = st.sellers.map((s, i) => {
      const a = marks[i] && marks[i].exists ? (marks[i].data() || {}) : null;
      return {
        ...s,
        collected: a ? { at: msOf(a.at), by: a.actor || null, amount: isInt((a.detail || {}).avaFeeDue) ? a.detail.avaFeeDue : null } : null,
      };
    });
    log('feeStatement', {
      result: 'ok', periodStart: period.periodStart, sellers: st.totals.sellers, orders: st.totals.count,
      avaFeeDue: st.totals.avaFeeDue, anomalies: st.anomalies.length, truncated: st.truncated, durationMs: Date.now() - started,
    });
    return {
      ok: true,
      periodStart: period.periodStart,
      periodEnd: period.periodEnd,
      lastDay: period.lastDay,
      timezone: 'Asia/Tashkent',
      closed: nowMs >= period.endMs,
      methods: [...FEE_STATEMENT_METHODS],
      sellers,
      totals: st.totals,
      anomalies: st.anomalies,
      truncated: st.truncated,
    };
  };
}

function makeAdminGetWholesaleOrdersReport(deps) {
  const { db } = deps;
  return async function adminGetWholesaleOrdersReport(data, context) {
    const started = Date.now();
    await assertStrictAdmin(db, context);
    const mo = parseMonth((data || {}).month);
    const { docs, truncated } = await deliveredIn(db, mo.startMs, mo.endMs, null);
    const settlements = await readSettlements(db, docs.map((d) => d.id));
    const rows = new Map();
    const byMethod = {};
    const anomalies = [];
    for (const { id, o } of docs) {
      const st = settlements.get(id);
      const m = WO.methodOf(o);
      const sellerKey = toCanonicalId(o.sellerId) || String(o.sellerId || '');
      if (!st || !isInt(st.avaFee) || st.avaFee < 0 || !isInt(o.goodsTotal) || !isInt(o.deliveryFee)) {
        anomalies.push({ orderId: id, sellerId: sellerKey, code: 'settlement_invalid' });
        continue;
      }
      const k = `${sellerKey}|${m}`;
      const cur = rows.get(k) || {
        sellerId: sellerKey, paymentMethod: m, count: 0, goodsTotal: 0, deliveryFee: 0, avaFee: 0,
        avaFeeVia: FEE_STATEMENT_METHODS.includes(m) ? 'statement' : 'release',
      };
      cur.count += 1;
      cur.goodsTotal += o.goodsTotal;
      cur.deliveryFee += o.deliveryFee;
      cur.avaFee += st.avaFee;
      rows.set(k, cur);
      const t = byMethod[m] || {
        count: 0, goodsTotal: 0, deliveryFee: 0, avaFee: 0,
      };
      t.count += 1; t.goodsTotal += o.goodsTotal; t.deliveryFee += o.deliveryFee; t.avaFee += st.avaFee;
      byMethod[m] = t;
    }
    const list = [...rows.values()].sort((a, b) => (a.sellerId < b.sellerId ? -1 : a.sellerId > b.sellerId ? 1
      : (a.paymentMethod < b.paymentMethod ? -1 : 1)));
    const totals = Object.values(byMethod).reduce((t, x) => ({
      count: t.count + x.count, goodsTotal: t.goodsTotal + x.goodsTotal, deliveryFee: t.deliveryFee + x.deliveryFee, avaFee: t.avaFee + x.avaFee,
    }), {
      count: 0, goodsTotal: 0, deliveryFee: 0, avaFee: 0,
    });
    if (!Object.values(totals).every(Number.isSafeInteger)) throw fail('failed-precondition', 'Summa juda katta', 'amount_too_large');
    log('ordersReport', {
      result: 'ok', month: mo.month, orders: totals.count, rows: list.length, anomalies: anomalies.length, truncated, durationMs: Date.now() - started,
    });
    return {
      ok: true, month: mo.month, timezone: 'Asia/Tashkent', rows: list, byMethod, totals, anomalies, truncated,
    };
  };
}

/**
 * `adminMarkWholesaleFeeCollected({sellerId, periodStart, note?})`. Faqat YOPILGAN davr (keyin
 * yetkazilgan buyurtma o'tgan davrga tushmaydi — `deliveredAt` = yetkazish payti). Summa — serverda qayta
 * hisoblangan (`computeStatement`), 0 bo'lsa — `nothing_due`. Takror — idempotent (birinchi yozuv qaytadi).
 */
function makeAdminMarkWholesaleFeeCollected(deps) {
  const { db, now: nowFn } = deps;
  return async function adminMarkWholesaleFeeCollected(data, context) {
    const started = Date.now();
    const adminId = await assertStrictAdmin(db, context);
    const d = data || {};
    const sellerKey = toCanonicalId(d.sellerId);
    if (!sellerKey) throw fail('invalid-argument', 'Sotuvchi tanlanmagan', 'seller_required');
    const period = parsePeriod(d.periodStart);
    const note = String(d.note == null ? '' : d.note).trim().slice(0, NOTE_MAX);
    const now = nowFn ? nowFn() : new Date();
    if (now.getTime() < period.endMs) throw fail('failed-precondition', 'Davr hali tugamagan', 'period_not_closed');
    const ref = db.collection(ADMIN_AUDIT).doc(collectedDocId(sellerKey, period.periodStart));
    const existing = await ref.get();
    if (existing.exists) {
      const a = existing.data() || {};
      log('markFeeCollected', { result: 'already', periodStart: period.periodStart });
      return {
        ok: true, idempotent: true, periodStart: period.periodStart, avaFeeDue: storedDue(a),
      };
    }
    const st = await computeStatement(db, period);
    if (st.truncated) throw fail('failed-precondition', 'Davrda buyurtmalar juda ko\'p', 'statement_truncated');
    const row = st.sellers.find((s) => s.sellerId === sellerKey);
    if (!row || row.avaFeeDue <= 0) throw fail('failed-precondition', 'Bu davrda ushbu sotuvchidan olinadigan ulush yo\'q', 'nothing_due');
    const out = await db.runTransaction(async (tx) => {
      const s = await tx.get(ref);
      if (s.exists) return { idempotent: true, avaFeeDue: storedDue(s.data()) };
      tx.set(ref, {
        kind: 'wholesale_fee_collected',
        actor: adminId,
        target: `wholesale_sellers/${sellerKey}`,
        from: 'due',
        to: 'collected',
        reason: note,
        detail: {
          sellerId: sellerKey,
          periodStart: period.periodStart,
          periodEnd: period.periodEnd,
          methods: [...FEE_STATEMENT_METHODS],
          count: row.count,
          goodsTotal: row.goodsTotal,
          avaFeeDue: row.avaFeeDue,
          orderIds: row.orderIds.slice(0, 500),
        },
        at: now,
      });
      return { idempotent: false, avaFeeDue: row.avaFeeDue };
    });
    log('markFeeCollected', {
      result: out.idempotent ? 'already' : 'ok', periodStart: period.periodStart, avaFeeDue: out.avaFeeDue, durationMs: Date.now() - started,
    });
    return {
      ok: true, idempotent: out.idempotent, periodStart: period.periodStart, avaFeeDue: out.avaFeeDue,
    };
  };
}

module.exports = {
  FEE_STATEMENT_METHODS,
  MAX_ORDERS,
  parsePeriod,
  parseMonth,
  buildStatement,
  collectedDocId,
  makeAdminGetWholesaleFeeStatement,
  makeAdminGetWholesaleOrdersReport,
  makeAdminMarkWholesaleFeeCollected,
};
