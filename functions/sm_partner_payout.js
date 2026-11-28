'use strict';

/**
 * «AVA Супермаркет» — ҲАМКОРГА ТЎЛОВ (қарзни ҳисоблаш + қўлда тўлов белгиси), эга 2026-11-28 (11-банд).
 *
 * Модел (эга 2026-11-28): AVA'нинг ўз маҳсулоти ЙЎҚ; ҳар таклиф ҳамкорники (тасдиқланган Улгуржи
 * сотувчиси, `platform_products.smPartnerKey` + `private/partner.sellerId`). Харидор «AVA Супермаркет»ни
 * кўради. Бу модуль ПУЛНИ ТИЗИМДАН ТАШҚАРИГА ЎТКАЗМАЙДИ: фақат AVA'нинг ҳамкорга қарзини МАВЖУД
 * ledger'да ҳисоблайди ва админ қўлда (нақд / банк ўтказмаси) тўлаганини белгилайди.
 *
 * Коддан аниқланган (CONFIRMED, supermarket.js):
 *   - буюртма қаторидаги `price` = таклиф `price` = ҳамкор қўйган нарх = мижоз нархи
 *     (`private/partner_lines.partnerPrice: price`); алоҳида «ҳамкор нархи / таннарх / комиссия» ЙЎҚ;
 *   - якуний ҳолат — `status == 'delivered'` ёки `fulfillmentStatus == 'completed'`
 *     (supermarket_reports.isDelivered); етказилгандан кейин қайтариш/қайтим йўли КОДДА ЙЎҚ;
 *   - тортиш/алмаштириш/камайтириш/олиш курьер олгунча (`new|accepted|ready`) бўлади → етказилганда
 *     қаторлар якуний (`removed`, `finalTotal`, `substitutedFrom`).
 *
 * Шунинг учун комиссия қоидаси ЎЙЛАБ ТОПИЛМАДИ (1/50-банд): `settings/sm_partner_payout.commissionBp`
 * (бутун, базис пункт 0..10000) — версияланган админ созламаси; ЙЎҚ бўлса қарз ҳисобланмайди,
 * ёзув `blocked: RULE_NOT_SET` бўлиб туради (админ қоидани қўйгач «Қайта ҳисоблаш»).
 *
 *   goodsBasis = Σ ҳамкор қаторлари (олинган — 0; тортилган — finalTotal; қолган — total)
 *   commission = ceil(goodsBasis × commissionBp / 10000)   — AVA улуши юқорига (courier_payout билан бир хил)
 *   amount     = goodsBasis − commission                    — бутун сўм, float ЙЎҚ (8-банд)
 *
 * Ledger (мавжуд `settlement_ledger.postEntry`, янги ҳисоб тури ЙЎҚ; ҳамкор ҳисоби
 * `supplier_payable:smp_{partnerKey}` — курьер `supplier_payable:{телефон}` билан тўқнашмайди):
 *   ACCRUE  smPartnerAccrue:{orderId}:{key}  Dr admin_clearing / Cr supplier_payable:smp_{key}  amount
 *   REVERSE smPartnerReverse:{payableId}     Dr supplier_payable:smp_{key} / Cr admin_clearing  amount
 *   PAID    smPartnerPaid:{paymentId}        Dr supplier_payable:smp_{key} / Cr admin_cash      Σ (нақд/банк)
 *   OFFSET  (ledger ЁЗУВИ ЙЎҚ) — тўланганидан кейин қайтарилган (clawback) қарз янги қарзлар билан ёпилади.
 *
 * Инвариантлар: нақд/банк тўловидан кейин ҳамкор баланси ≥ 0 (ортиқча тўлов йўқ); offset ≤ очиқ clawback.
 * Идемпотентлик: journal id = калит; ҳамма ҳолат ўтиши — битта транзакцияда (21/22-банд).
 * Босқич (42-банд): settings.stage = off (сукут) | internal (фақат админ кўради) | public (ҳамкор ҳам кўради).
 */

const MODULE = 'sm_partner_payout';
const SETTINGS_DOC = Object.freeze(['settings', 'sm_partner_payout']);
const HISTORY = 'sm_partner_payout_history';
const PAYABLES = 'sm_partner_payables';
const PAYMENTS = 'sm_partner_payments';
const SUMMARY = 'sm_partner_payout_summary';
const EVENTS = 'events';
const ADMIN_AUDIT = 'admin_audit';
const ORDERS = 'orders';
const PRODUCTS = 'platform_products';
const SELLERS = 'wholesale_sellers';
const STAGES = Object.freeze(['off', 'internal', 'public']);
const STATUSES = Object.freeze(['blocked', 'accrued', 'paid', 'reversed', 'nothing_due', 'void']);
const BLOCK_REASONS = Object.freeze(['RULE_NOT_SET', 'WEIGH_PENDING', 'SELLER_UNKNOWN']);
const METHODS = Object.freeze(['cash', 'bank_transfer', 'offset']);
const KIND_ACCRUE = 'sm_partner_payable_accrued';
const KIND_REVERSE = 'sm_partner_payable_reversed';
const KIND_PAID = 'sm_partner_payable_paid';
const CLEARING = 'admin_clearing';
const CASH = 'admin_cash';
const BP_MAX = 10000;
const MARK_MAX = 100;
const RECOMPUTE_MAX = 50;
const SWEEP_MAX_ORDERS = 500;
const SWEEP_MAX_DAYS = 31;
const SET_ROLES = Object.freeze(['admin', 'superadmin', 'finance']);
const GET_ROLES = Object.freeze(['admin', 'superadmin', 'finance', 'auditor']);
const PARTNER_KEY_RE = /^[0-9a-f]{16}$/;
const ORDER_ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
const PAYABLE_ID_RE = /^[A-Za-z0-9_-]{1,64}__[0-9a-f]{16}$/;
const CLIENT_REQ_RE = /^[A-Za-z0-9_-]{8,64}$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

// diagnostic code → [uz_Cyrl, uz_Latn, ru] (25-банд)
const MSG = Object.freeze({
  UNAUTHENTICATED: ['Илтимос, тизимга киринг.', 'Iltimos, tizimga kiring.', 'Пожалуйста, войдите в систему.'],
  PERMISSION_DENIED: ['Бу амал учун рухсат йўқ.', 'Bu amal uçun ruxsat yöq.', 'Нет доступа к этому действию.'],
  INVALID_REQUEST: ['Маълумот нотўғри. Қайта уриниб кўринг.', "Ma'lumot notöğri. Qayta urinib köring.", 'Неверные данные. Попробуйте ещё раз.'],
  SETTINGS_INVALID: ['Созламалар нотўғри.', 'Sozlamalar notöğri.', 'Неверные настройки.'],
  REASON_REQUIRED: ['Сабабни ёзинг (камида 3 белги).', 'Sababni yozing (kamida 3 belgi).', 'Укажите причину (минимум 3 символа).'],
  REFERENCE_REQUIRED: ['Ўтказма рақами / изоҳ ёзинг.', "Ötkazma raqami / izoh yozing.", 'Укажите номер перевода / комментарий.'],
  STAGE_OFF: ['Ҳамкорларга тўлов ҳисоби ҳозир ўчиқ.', "Hamkorlarga tölov hisobi hozir öçiq.", 'Учёт выплат партнёрам сейчас выключен.'],
  PAYABLE_NOT_FOUND: ['Қарз ёзуви топилмади.', 'Qarz yozuvi topilmadi.', 'Запись задолженности не найдена.'],
  PAYABLE_NOT_PAYABLE: ['Бу ёзувни тўланди деб белгилаб бўлмайди (ҳолати ўзгарган).', "Bu yozuvni tölandi deb belgilab bölmaydi (holati özgargan).", 'Эту запись нельзя отметить оплаченной (статус изменился).'],
  PAYABLE_PARTNER_MISMATCH: ['Танланган ёзувлар бошқа ҳамкорники.', 'Tanlangan yozuvlar boşqa hamkorniki.', 'Выбранные записи принадлежат другому партнёру.'],
  PAYABLE_NOT_REVERSIBLE: ['Бу ёзувни қайтариб бўлмайди.', "Bu yozuvni qaytarib bölmaydi.", 'Эту запись нельзя сторнировать.'],
  PAYMENT_EXCEEDS_BALANCE: ['Тўлов ҳамкор балансидан ортиқ — аввал қайтарилган қарзни ёпинг (offset).', "Tölov hamkor balansidan ortiq — avval qaytarilgan qarzni yoping (offset).", 'Выплата превышает баланс партнёра — сначала закройте возвраты (зачёт).'],
  OFFSET_EXCEEDS_CLAWBACK: ['Зачёт суммаси очиқ қайтарилган қарздан ортиқ.', "Zachyot summasi oçiq qaytarilgan qarzdan ortiq.", 'Сумма зачёта превышает открытый возврат.'],
  RECOMPUTE_NOT_ALLOWED: ['Бу буюртма бўйича қайта ҳисоблаб бўлмайди.', "Bu buyurtma böyiça qayta hisoblab bölmaydi.", 'Пересчёт по этому заказу невозможен.'],
  RANGE_INVALID: ['Сана оралиғи нотўғри (31 кундан ошмасин).', "Sana oralığı notöğri (31 kundan oşmasin).", 'Неверный диапазон дат (не более 31 дня).'],
  PARTNER_NOT_APPROVED: ['Фақат тасдиқланган Улгуржи сотувчиси учун.', 'Faqat tasdiqlangan Ulgurji sotuvçisi uçun.', 'Только для одобренного оптового продавца.'],
  INTERNAL: ['Амални бажариб бўлмади. Қайта уриниб кўринг.', "Amalni bajarib bölmadi. Qayta urinib köring.", 'Не удалось выполнить. Попробуйте ещё раз.'],
});
function messagesOf(code) {
  const m = MSG[code] || MSG.INTERNAL;
  return { uz_Cyrl: m[0], uz_Latn: m[1], ru: m[2] };
}

// ══════════════════════ ТОЗА ФУНКЦИЯЛАР ══════════════════════

const isInt = (n) => typeof n === 'number' && Number.isSafeInteger(n);
const isBp = (n) => isInt(n) && n >= 0 && n <= BP_MAX;

/** Ҳамкор ledger ҳисоби (курьер `supplier_payable:{телефон}` билан тўқнашмайди). */
function partnerAccount(partnerKey) {
  if (!PARTNER_KEY_RE.test(String(partnerKey || ''))) throw new Error('smPartnerPayout: partnerKey invalid');
  return `supplier_payable:smp_${partnerKey}`;
}
const payableIdOf = (orderId, partnerKey) => `${orderId}__${partnerKey}`;
const accrueKeyOf = (orderId, partnerKey) => `smPartnerAccrue:${orderId}:${partnerKey}`;
const reverseKeyOf = (payableId) => `smPartnerReverse:${payableId}`;
const paidKeyOf = (paymentId) => `smPartnerPaid:${paymentId}`;

/**
 * Созлама ҳужжати → { stage, commissionBp|null, version, valid, configured }.
 * Йўқ → off / null (қоида белгиланмаган). Нотўғри қиймат → valid:false (пул ҳисобланмайди).
 */
function parseSettings(doc) {
  const d = doc && typeof doc === 'object' ? doc : null;
  if (!d) return { stage: 'off', commissionBp: null, version: 0, valid: true, configured: false };
  const version = isInt(d.version) && d.version >= 0 ? d.version : 0;
  const stage = STAGES.includes(d.stage) ? d.stage : 'off';
  if (d.commissionBp === undefined || d.commissionBp === null) return { stage, commissionBp: null, version, valid: true, configured: true };
  if (!isBp(d.commissionBp)) return { stage, commissionBp: null, version, valid: false, configured: true };
  return { stage, commissionBp: d.commissionBp, version, valid: true, configured: true };
}

/** ceil(basis × bp / 10000) — фақат бутун сонлар. */
function commissionOf(basis, bp) {
  if (!isInt(basis) || basis < 0) throw new Error('smPartnerPayout: basis must be a non-negative integer');
  if (!isBp(bp)) throw new Error('smPartnerPayout: bp out of range');
  const product = basis * bp;
  if (!Number.isSafeInteger(product)) throw new Error('smPartnerPayout: amount too large');
  const rem = product % BP_MAX;
  return (product - rem) / BP_MAX + (rem > 0 ? 1 : 0);
}

/** Буюртма қатори → { basis, weighPending } (олинган — 0; тортилмаган тортиладиган — total + белги). */
function lineBasis(l) {
  if (!l || l.removed) return { basis: 0, weighPending: false };
  const total = isInt(l.total) && l.total >= 0 ? l.total : 0;
  if (l.weighed === true) {
    if (l.actualQty == null) return { basis: total, weighPending: true };
    return { basis: isInt(l.finalTotal) && l.finalTotal >= 0 ? l.finalTotal : total, weighPending: false };
  }
  return { basis: total, weighPending: false };
}

/**
 * Етказилган буюртмадан ҳамкорлар бўйича режа (тоза).
 * partnerOf: { [productId]: { partnerKey, sellerId|null } | null } — null: AVA/ҳамкорсиз таклиф.
 * settings: parseSettings натижаси.
 * @returns {{ partners: object[], avaGoods: number, avaLines: number }}
 */
function planOrder({ items, partnerOf, settings }) {
  const by = new Map();
  let avaGoods = 0;
  let avaLines = 0;
  for (const l of Array.isArray(items) ? items : []) {
    if (!l || l.removed) continue;
    const p = partnerOf[l.productId] || null;
    const { basis, weighPending } = lineBasis(l);
    if (!p || !p.partnerKey) { avaGoods += basis; avaLines += 1; continue; }
    let g = by.get(p.partnerKey);
    if (!g) {
      g = { partnerKey: p.partnerKey, sellerId: p.sellerId || null, lines: [], goodsBasis: 0, weighPending: false };
      by.set(p.partnerKey, g);
    }
    if (!g.sellerId && p.sellerId) g.sellerId = p.sellerId;
    g.goodsBasis += basis;
    if (weighPending) g.weighPending = true;
    const row = { productId: String(l.productId), price: isInt(l.price) ? l.price : 0, qty: l.qty, basis };
    if (l.actualQty != null) row.actualQty = l.actualQty;
    if (l.substitutedFrom && l.substitutedFrom.productId) row.substitutedFrom = String(l.substitutedFrom.productId);
    g.lines.push(row);
  }
  const partners = [...by.values()].sort((a, b) => a.partnerKey.localeCompare(b.partnerKey)).map((g) => {
    const out = {
      partnerKey: g.partnerKey, sellerId: g.sellerId, lines: g.lines, goodsBasis: g.goodsBasis,
      commissionBp: null, commission: null, amount: null, settingsVersion: settings.version, status: 'blocked', blockReason: null,
    };
    if (!g.sellerId) return { ...out, blockReason: 'SELLER_UNKNOWN' };
    if (g.weighPending) return { ...out, blockReason: 'WEIGH_PENDING' };
    if (!settings.valid || settings.commissionBp == null) return { ...out, blockReason: 'RULE_NOT_SET' };
    const commission = commissionOf(g.goodsBasis, settings.commissionBp);
    const amount = g.goodsBasis - commission;
    return { ...out, commissionBp: settings.commissionBp, commission, amount, status: amount > 0 ? 'accrue' : 'nothing_due' };
  });
  return { partners, avaGoods, avaLines };
}

function isDelivered(od) {
  return String((od && od.status) || '') === 'delivered' || String((od && od.fulfillmentStatus) || '').toLowerCase() === 'completed';
}
function isCancelled(od) {
  const s = String((od && od.status) || '');
  const fs = String((od && od.fulfillmentStatus) || '').toLowerCase();
  return s === 'rejected' || s === 'cancelled' || fs === 'cancelled';
}

/**
 * Тўлов шартлари (тоза). balance — ҳамкор ledger баланси (тўловдан ОЛДИН); openAccrued — очиқ (accrued) Σ;
 * sum — танланганлар Σ. cash/bank: balance − sum ≥ 0. offset: sum ≤ openAccrued − balance (очиқ clawback).
 * @returns {string} '' ёки diagnostic code
 */
function paymentProblem({ method, balance, openAccrued, sum }) {
  if (!METHODS.includes(method) || !isInt(balance) || !isInt(openAccrued) || !isInt(sum) || sum <= 0) return 'INVALID_REQUEST';
  if (method === 'offset') return sum <= openAccrued - balance ? '' : 'OFFSET_EXCEEDS_CLAWBACK';
  return balance - sum >= 0 ? '' : 'PAYMENT_EXCEEDS_BALANCE';
}

function daysBetween(a, b) {
  return Math.round((Date.UTC(+b.slice(0, 4), +b.slice(5, 7) - 1, +b.slice(8, 10)) - Date.UTC(+a.slice(0, 4), +a.slice(5, 7) - 1, +a.slice(8, 10))) / 86400000);
}

// ══════════════════════ CLOUD FUNCTIONS ══════════════════════

function attachSmPartnerPayout(exportsObj, deps) {
  const {
    functions, db, admin, settlementLedger, requireCallerRoles, requirePartner,
  } = deps;
  const { HttpsError } = functions.https;
  const FV = admin.firestore.FieldValue;
  const ts = () => FV.serverTimestamp();
  const fail = (status, code, extra = {}) => new HttpsError(status, messagesOf(code).uz_Cyrl, { code, messages: messagesOf(code), ...extra });
  const log = (fields, level) => {
    const line = JSON.stringify({ module: MODULE, ...fields });
    if (level === 'error') console.error(line); else if (level === 'warn') console.warn(line); else console.log(line);
  };
  const reasonError = (reason, extra) => Object.assign(new Error(reason), { reason, ...(extra || {}) });
  const settingsRef = () => db.collection(SETTINGS_DOC[0]).doc(SETTINGS_DOC[1]);
  const payableRef = (id) => db.collection(PAYABLES).doc(id);
  const summaryRef = (key) => db.collection(SUMMARY).doc(key);
  const journalRef = (id) => db.collection(settlementLedger.COL_JOURNAL).doc(id);
  const accountRef = (key) => db.collection(settlementLedger.COL_ACCOUNTS).doc(partnerAccount(key));
  const toMs = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : null);
  const roles = async (context, list) => {
    try {
      return await requireCallerRoles(context, [...list], 'Role required');
    } catch (e) {
      if (e instanceof HttpsError) throw fail(e.code, e.code === 'unauthenticated' ? 'UNAUTHENTICATED' : 'PERMISSION_DENIED');
      throw e;
    }
  };
  const event = (t, pid, fields) => t.set(payableRef(pid).collection(EVENTS).doc(), { ...fields, at: ts() });

  async function readSettings() {
    const s = await settingsRef().get();
    return parseSettings(s.exists ? s.data() : null);
  }

  /** productId → {partnerKey, sellerId}: таклиф ҳужжати + private/partner, захира — буюртма private/partner_lines. */
  async function partnerMap(orderRef, items) {
    const ids = [...new Set((items || []).filter((l) => l && !l.removed && typeof l.productId === 'string' && l.productId).map((l) => l.productId))];
    const out = {};
    if (!ids.length) return out;
    const pRefs = ids.map((id) => db.collection(PRODUCTS).doc(id));
    const privRefs = pRefs.map((r) => r.collection('private').doc('partner'));
    const [pSnaps, privSnaps, linesSnap] = await Promise.all([
      db.getAll(...pRefs), db.getAll(...privRefs), orderRef.collection('private').doc('partner_lines').get(),
    ]);
    const snapLines = linesSnap.exists && Array.isArray((linesSnap.data() || {}).lines) ? linesSnap.data().lines : [];
    ids.forEach((id, i) => {
      const p = pSnaps[i].exists ? (pSnaps[i].data() || {}) : null;
      const priv = privSnaps[i].exists ? (privSnaps[i].data() || {}) : {};
      const fromOrder = snapLines.find((x) => x && x.productId === id && x.partnerKey);
      const key = (p && typeof p.smPartnerKey === 'string' && p.smPartnerKey) || (fromOrder && fromOrder.partnerKey) || '';
      if (!key || !PARTNER_KEY_RE.test(key)) { out[id] = null; return; }
      const sellerId = (priv.partnerKey === key && priv.sellerId) || (fromOrder && fromOrder.sellerId) || null;
      out[id] = { partnerKey: key, sellerId: sellerId ? String(sellerId) : null };
    });
    return out;
  }

  async function companyNames(sellerIds) {
    const ids = [...new Set(sellerIds.filter(Boolean))];
    const out = {};
    if (!ids.length) return out;
    const snaps = await db.getAll(...ids.map((id) => db.collection(SELLERS).doc(id)));
    snaps.forEach((s, i) => { out[ids[i]] = s.exists ? String((s.data() || {}).companyName || '').trim().slice(0, 120) : ''; });
    return out;
  }

  /** Бир ҳамкор режаси → ёзув (accrue: ledger + payable + summary атомар; blocked/nothing_due: фақат payable). */
  async function applyPlan(orderId, od, p, names, settings, source) {
    const pid = payableIdOf(orderId, p.partnerKey);
    const ref = payableRef(pid);
    const base = {
      payableId: pid, orderId, partnerKey: p.partnerKey, sellerId: p.sellerId || null,
      companyName: (p.sellerId && names[p.sellerId]) || '', slotDate: (od.slot && od.slot.date) || '',
      orderTariffVersion: String(od.tariffVersion || ''), goodsBasis: p.goodsBasis, lines: p.lines,
      commissionBp: p.commissionBp, commission: p.commission, amount: p.amount, settingsVersion: p.settingsVersion,
    };
    if (p.status === 'accrue') {
      try {
        const res = await settlementLedger.postEntry(db, {
          idempotencyKey: accrueKeyOf(orderId, p.partnerKey),
          kind: KIND_ACCRUE,
          refType: 'order',
          refId: orderId,
          postedBy: 'system',
          postedRole: 'system',
          legs: [{ account: CLEARING, dr: p.amount }, { account: partnerAccount(p.partnerKey), cr: p.amount }],
        }, {
          mirrorBonus: false,
          meta: { module: 'supermarket', orderId, partnerKey: p.partnerKey, goodsBasis: p.goodsBasis, commissionBp: p.commissionBp, commission: p.commission, settingsVersion: p.settingsVersion, source },
          precheck: async (tx) => {
            const [s, st] = await Promise.all([tx.get(ref), tx.get(settingsRef())]);
            const cur = parseSettings(st.exists ? st.data() : null);
            if (cur.stage === 'off') throw reasonError('stage_off');
            if (!cur.valid || cur.commissionBp !== settings.commissionBp || cur.version !== settings.version) throw reasonError('settings_changed');
            const x = s.exists ? (s.data() || {}) : null;
            if (x && x.status !== 'blocked') throw reasonError('exists', { status: x.status });
            return { wasBlocked: !!x };
          },
          onCommit: (tx, { entryId, pre }) => {
            tx.set(ref, {
              ...base, status: 'accrued', blockReason: null, accrueEntryId: entryId, accruedAt: ts(),
              ...(pre.wasBlocked ? {} : { createdAt: ts() }), updatedAt: ts(),
            }, { merge: true });
            tx.set(summaryRef(p.partnerKey), {
              partnerKey: p.partnerKey, sellerId: p.sellerId, companyName: base.companyName,
              accruedTotal: FV.increment(p.amount), openCount: FV.increment(1),
              ...(pre.wasBlocked ? { blockedCount: FV.increment(-1) } : {}), updatedAt: ts(),
            }, { merge: true });
            event(tx, pid, { type: 'accrued', amount: p.amount, goodsBasis: p.goodsBasis, commissionBp: p.commissionBp, entryId, source });
          },
        });
        return res.idempotent ? 'idempotent' : 'accrued';
      } catch (e) {
        if (e && e.reason === 'exists') return 'exists';
        if (e && e.reason === 'stage_off') return 'stage_off';
        if (e && e.reason === 'settings_changed') return 'settings_changed';
        throw e;
      }
    }
    // blocked / nothing_due — пул ЙЎҚ.
    return db.runTransaction(async (t) => {
      const s = await t.get(ref);
      const x = s.exists ? (s.data() || {}) : null;
      if (x && x.status !== 'blocked') return 'exists';
      if (x && p.status === 'blocked' && x.blockReason === p.blockReason && x.goodsBasis === p.goodsBasis) return 'unchanged';
      const status = p.status === 'nothing_due' ? 'nothing_due' : 'blocked';
      t.set(ref, { ...base, status, blockReason: status === 'blocked' ? p.blockReason : null, ...(x ? {} : { createdAt: ts() }), updatedAt: ts() }, { merge: true });
      if (!x && status === 'blocked') {
        t.set(summaryRef(p.partnerKey), { partnerKey: p.partnerKey, sellerId: p.sellerId, companyName: base.companyName, blockedCount: FV.increment(1), updatedAt: ts() }, { merge: true });
      }
      if (x && status !== 'blocked') t.set(summaryRef(p.partnerKey), { blockedCount: FV.increment(-1), updatedAt: ts() }, { merge: true });
      event(t, pid, { type: status, blockReason: status === 'blocked' ? p.blockReason : null, goodsBasis: p.goodsBasis, source });
      return status;
    });
  }

  /**
   * Буюртма бўйича ҳисоб (trigger / админ қайта ҳисоби / sweep). Идемпотент: accrued/paid/reversed ёзувга тегилмайди.
   * @returns {{result: string, partners?: object[]}}
   */
  async function processOrder(orderId, source) {
    const started = Date.now();
    const settings = await readSettings();
    if (settings.stage === 'off') return { result: 'stage_off' };
    const orderRef = db.collection(ORDERS).doc(orderId);
    const snap = await orderRef.get();
    if (!snap.exists) return { result: 'not_found' };
    const od = snap.data() || {};
    if (od.subtype !== 'supermarket') return { result: 'not_supermarket' };
    if (isCancelled(od)) return { result: 'cancelled', ...(await cancelOrder(orderId, source)) };
    if (!isDelivered(od)) return { result: 'not_final' };
    const partnerOf = await partnerMap(orderRef, od.items);
    const plan = planOrder({ items: od.items, partnerOf, settings });
    const names = await companyNames(plan.partners.map((p) => p.sellerId));
    const partners = [];
    for (const p of plan.partners) {
      let r;
      for (let attempt = 0; attempt < 3; attempt += 1) {
        r = await applyPlan(orderId, od, p, names, settings, source);
        if (r !== 'settings_changed') break;
        const fresh = await readSettings();
        Object.assign(settings, fresh);
        Object.assign(p, planOrder({ items: od.items, partnerOf, settings: fresh }).partners.find((x) => x.partnerKey === p.partnerKey));
      }
      partners.push({ partnerKey: p.partnerKey, status: p.status, blockReason: p.blockReason, amount: p.amount, result: r });
      log({ action: 'processOrder', orderId, partnerKey: p.partnerKey, result: r, status: p.status, blockReason: p.blockReason, amount: p.amount, source }, p.status === 'blocked' ? 'warn' : undefined);
    }
    log({ action: 'processOrder', orderId, result: 'done', partners: partners.length, avaLines: plan.avaLines, source, durationMs: Date.now() - started });
    return { result: 'done', partners, avaLines: plan.avaLines };
  }

  /** Бекор қилинган буюртма: accrued/paid → тескари ёзув; blocked → void. */
  async function cancelOrder(orderId, source) {
    const snap = await db.collection(PAYABLES).where('orderId', '==', orderId).get();
    const out = { reversed: 0, voided: 0 };
    for (const d of snap.docs) {
      const x = d.data() || {};
      if (x.status === 'accrued' || x.status === 'paid') {
        const r = await reversePayable(d.id, { reason: 'order_cancelled', actor: 'system', actorRole: 'system', source });
        if (r.changed) out.reversed += 1;
      } else if (x.status === 'blocked') {
        const changed = await db.runTransaction(async (t) => {
          const s = await t.get(d.ref);
          if (!s.exists || (s.data() || {}).status !== 'blocked') return false;
          t.update(d.ref, { status: 'void', voidReason: 'order_cancelled', updatedAt: ts() });
          t.set(summaryRef(x.partnerKey), { blockedCount: FV.increment(-1), updatedAt: ts() }, { merge: true });
          event(t, d.id, { type: 'void', reason: 'order_cancelled', source });
          return true;
        });
        if (changed) out.voided += 1;
      }
    }
    return out;
  }

  /** accrued|paid → reversed (бир марта). paid'дан — clawback (ҳамкор AVA'га қарздор, баланс манфий). */
  async function reversePayable(pid, { reason, actor, actorRole, source }) {
    const ref = payableRef(pid);
    const s0 = await ref.get();
    if (!s0.exists) throw reasonError('not_found');
    const x0 = s0.data() || {};
    if (x0.status === 'reversed') return { changed: false, idempotent: true };
    if (!['accrued', 'paid'].includes(x0.status) || !isInt(x0.amount) || x0.amount <= 0) throw reasonError('not_reversible', { status: x0.status });
    try {
      const res = await settlementLedger.postEntry(db, {
        idempotencyKey: reverseKeyOf(pid),
        kind: KIND_REVERSE,
        refType: 'order',
        refId: x0.orderId,
        postedBy: actor,
        postedRole: actorRole,
        legs: [{ account: partnerAccount(x0.partnerKey), dr: x0.amount }, { account: CLEARING, cr: x0.amount }],
      }, {
        mirrorBonus: false,
        meta: { module: 'supermarket', payableId: pid, orderId: x0.orderId, partnerKey: x0.partnerKey, reason, source },
        precheck: async (tx) => {
          const s = await tx.get(ref);
          const x = s.exists ? (s.data() || {}) : {};
          if (!['accrued', 'paid'].includes(x.status) || x.amount !== x0.amount) throw reasonError('not_reversible', { status: x.status });
          return { wasPaid: x.status === 'paid' };
        },
        onCommit: (tx, { entryId, pre }) => {
          tx.update(ref, {
            status: 'reversed', reversedFrom: pre.wasPaid ? 'paid' : 'accrued', clawback: pre.wasPaid,
            reverseReason: reason, reversedBy: actor, reversedAt: ts(), reverseEntryId: entryId, updatedAt: ts(),
          });
          tx.set(summaryRef(x0.partnerKey), {
            reversedTotal: FV.increment(x0.amount),
            ...(pre.wasPaid ? { clawbackTotal: FV.increment(x0.amount) } : { openCount: FV.increment(-1) }),
            updatedAt: ts(),
          }, { merge: true });
          event(tx, pid, { type: 'reversed', amount: x0.amount, from: pre.wasPaid ? 'paid' : 'accrued', reason, actor, entryId, source });
          if (actorRole !== 'system') {
            tx.set(db.collection(ADMIN_AUDIT).doc(), {
              kind: 'sm_partner_payable_reversed', actor, actorRole, target: `${PAYABLES}/${pid}`, partnerKey: x0.partnerKey,
              orderId: x0.orderId, amount: x0.amount, clawback: pre.wasPaid, reason, at: ts(),
            });
          }
        },
      });
      return { changed: !res.idempotent, idempotent: res.idempotent, clawback: x0.status === 'paid' };
    } catch (e) {
      if (e && e.reason === 'not_reversible') {
        const again = await ref.get();
        if (again.exists && (again.data() || {}).status === 'reversed') return { changed: false, idempotent: true };
      }
      throw e;
    }
  }

  // ── Trigger: етказилди → ҳисоб; бекор → тескари ──
  exportsObj.onSmOrderPartnerPayout = functions.firestore
    .document(`${ORDERS}/{orderId}`)
    .onUpdate(async (change, context) => {
      const after = change.after.data() || {};
      if (after.subtype !== 'supermarket') return null;
      const before = change.before.data() || {};
      const delivered = isDelivered(after) && !isDelivered(before);
      const cancelled = isCancelled(after) && !isCancelled(before);
      if (!delivered && !cancelled) return null;
      const orderId = context.params.orderId;
      try {
        const r = await processOrder(orderId, 'trigger');
        log({ action: 'onSmOrderPartnerPayout', orderId, result: r.result });
      } catch (e) {
        // Retry'сиз trigger: йиқилса админ «Қайта ҳисоблаш» (sweep) билан ёпади — пул икки марта ЁЗИЛМАЙДИ (калит).
        log({ action: 'onSmOrderPartnerPayout', orderId, result: 'error', errorCode: 'SM_PARTNER_PAYOUT_FAILED', message: String(e && e.message) }, 'error');
      }
      return null;
    });

  // ── Админ: созлама ──
  function settingsView(raw) {
    const st = parseSettings(raw);
    const d = raw || {};
    return {
      configured: st.configured, valid: st.valid, stage: st.stage, commissionBp: st.commissionBp, version: st.version,
      reason: typeof d.reason === 'string' ? d.reason : '', updatedAtMs: toMs(d.updatedAt), updatedBy: typeof d.updatedBy === 'string' ? d.updatedBy : '',
      bpMax: BP_MAX, stages: STAGES,
    };
  }

  exportsObj.adminGetSmPartnerPayoutSettings = functions.https.onCall(async (data, context) => {
    await roles(context, GET_ROLES);
    const s = await settingsRef().get();
    return { ok: true, ...settingsView(s.exists ? s.data() : null) };
  });

  /**
   * data: { stage?: off|internal|public, commissionBp?: int 0..10000 | null (null = белгиланмаган), reason ≥3 }.
   * Ҳар ўзгариш: version+1, ўзгармас тарих + admin_audit — битта транзакцияда (9/16/41-банд).
   */
  exportsObj.adminSetSmPartnerPayoutSettings = functions.https.onCall(async (data, context) => {
    const actor = await roles(context, SET_ROLES);
    const d = data && typeof data === 'object' ? data : {};
    const hasStage = d.stage !== undefined;
    const hasBp = Object.prototype.hasOwnProperty.call(d, 'commissionBp');
    if (hasStage && !STAGES.includes(d.stage)) throw fail('invalid-argument', 'SETTINGS_INVALID', { field: 'stage' });
    if (hasBp && d.commissionBp !== null && !isBp(d.commissionBp)) throw fail('invalid-argument', 'SETTINGS_INVALID', { field: 'commissionBp', min: 0, max: BP_MAX });
    if (!hasStage && !hasBp) throw fail('invalid-argument', 'SETTINGS_INVALID', { field: 'nothing' });
    const reason = String(d.reason || '').trim().slice(0, 300);
    if (reason.length < 3) throw fail('invalid-argument', 'REASON_REQUIRED');
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(settingsRef());
      const raw = snap.exists ? (snap.data() || {}) : null;
      const cur = parseSettings(raw);
      const stage = hasStage ? d.stage : cur.stage;
      const commissionBp = hasBp ? d.commissionBp : (cur.valid ? cur.commissionBp : null);
      if (cur.configured && cur.valid && stage === cur.stage && commissionBp === cur.commissionBp) return { unchanged: true, version: cur.version, stage, commissionBp };
      const version = cur.version + 1;
      const doc = { stage, commissionBp, version, reason, updatedAt: ts(), updatedBy: actor };
      const previous = { stage: raw ? cur.stage : null, commissionBp: raw && raw.commissionBp !== undefined ? raw.commissionBp : null, version: cur.version };
      t.set(settingsRef(), doc);
      t.create(db.collection(HISTORY).doc(`v${version}`), { ...doc, previous, changedBy: actor, changedAt: ts() });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'sm_partner_payout_settings', actor, target: SETTINGS_DOC.join('/'), from: String(cur.version), to: String(version), reason,
        detail: { stage, prevStage: previous.stage, commissionBp, prevCommissionBp: previous.commissionBp }, at: ts(),
      });
      return { unchanged: false, version, stage, commissionBp };
    });
    log({ action: 'adminSetSmPartnerPayoutSettings', result: 'ok', userTail: actor.slice(-4), ...out });
    return { ok: true, ...out };
  });

  // ── Админ: рўйхат ──
  const payableView = (id, x) => ({
    payableId: id, orderId: x.orderId || '', partnerKey: x.partnerKey || '', sellerId: x.sellerId || null, companyName: x.companyName || '',
    slotDate: x.slotDate || '', status: x.status || '', blockReason: x.blockReason || null, goodsBasis: isInt(x.goodsBasis) ? x.goodsBasis : 0,
    commissionBp: isInt(x.commissionBp) ? x.commissionBp : null, commission: isInt(x.commission) ? x.commission : null,
    amount: isInt(x.amount) ? x.amount : null, settingsVersion: isInt(x.settingsVersion) ? x.settingsVersion : null,
    paymentId: x.paymentId || null, method: x.method || null, paidAtMs: toMs(x.paidAt), clawback: x.clawback === true,
    reverseReason: x.reverseReason || null, createdAtMs: toMs(x.createdAt), lines: Array.isArray(x.lines) ? x.lines.length : 0,
  });
  const summaryView = (id, x, balance) => ({
    partnerKey: id, sellerId: x.sellerId || null, companyName: x.companyName || '', balance,
    accruedTotal: x.accruedTotal || 0, paidTotal: x.paidTotal || 0, offsetTotal: x.offsetTotal || 0, reversedTotal: x.reversedTotal || 0,
    clawbackTotal: x.clawbackTotal || 0, openCount: x.openCount || 0, blockedCount: x.blockedCount || 0,
  });

  /** data: { partnerKey? } — ҳамкорлар жамлмаси (+ ledger баланси); partnerKey берилса — унинг ёзувлари ва тўловлари. */
  exportsObj.adminListSmPartnerPayables = functions.https.onCall(async (data, context) => {
    await roles(context, GET_ROLES);
    const key = data && typeof data.partnerKey === 'string' ? data.partnerKey.trim() : '';
    if (key && !PARTNER_KEY_RE.test(key)) throw fail('invalid-argument', 'INVALID_REQUEST');
    const [sumSnap, blockedSnap, st] = await Promise.all([
      db.collection(SUMMARY).limit(500).get(),
      db.collection(PAYABLES).where('status', '==', 'blocked').limit(200).get(),
      settingsRef().get(),
    ]);
    const accSnaps = sumSnap.size ? await db.getAll(...sumSnap.docs.map((d) => accountRef(d.id))) : [];
    const partners = sumSnap.docs.map((d, i) => summaryView(d.id, d.data() || {}, accSnaps[i].exists ? ((accSnaps[i].data() || {}).balance || 0) : 0))
      .sort((a, b) => (b.balance - a.balance) || a.partnerKey.localeCompare(b.partnerKey));
    const out = { ok: true, settings: settingsView(st.exists ? st.data() : null), partners, blocked: blockedSnap.docs.map((d) => payableView(d.id, d.data() || {})) };
    if (key) {
      const [pSnap, paySnap] = await Promise.all([
        db.collection(PAYABLES).where('partnerKey', '==', key).orderBy('createdAt', 'desc').limit(300).get(),
        db.collection(PAYMENTS).where('partnerKey', '==', key).orderBy('createdAt', 'desc').limit(100).get(),
      ]);
      out.payables = pSnap.docs.map((d) => payableView(d.id, d.data() || {}));
      out.payments = paySnap.docs.map((d) => {
        const x = d.data() || {};
        return { paymentId: d.id, amount: x.amount || 0, method: x.method || '', reference: x.reference || '', count: Array.isArray(x.payableIds) ? x.payableIds.length : 0, actor: x.actor || '', createdAtMs: toMs(x.createdAt) };
      });
    }
    return out;
  });

  /**
   * Қўлда тўлов белгиси: { partnerKey, payableIds[1..100], method: cash|bank_transfer|offset, reference, clientRequestId }.
   * Пул ТИЗИМДАН ТАШҚАРИДА ўтказилади (нақд / банк); бу ерда фақат ledger ва ҳолат. Идемпотент (clientRequestId),
   * параллел белгилашда фақат битта ғолиб (транзакция ичида ҳолат қайта ўқилади).
   */
  exportsObj.adminMarkSmPartnerPaid = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const actor = await roles(context, SET_ROLES);
    const d = data || {};
    const key = typeof d.partnerKey === 'string' ? d.partnerKey.trim() : '';
    const ids = Array.isArray(d.payableIds) ? [...new Set(d.payableIds.map((x) => String(x || '').trim()))] : [];
    const method = String(d.method || '');
    const reference = typeof d.reference === 'string' ? d.reference.trim().slice(0, 200) : '';
    const reqId = typeof d.clientRequestId === 'string' ? d.clientRequestId.trim() : '';
    if (!PARTNER_KEY_RE.test(key) || ids.length < 1 || ids.length > MARK_MAX || ids.some((x) => !PAYABLE_ID_RE.test(x))
        || !METHODS.includes(method) || !CLIENT_REQ_RE.test(reqId)) {
      throw fail('invalid-argument', 'INVALID_REQUEST');
    }
    if (method === 'bank_transfer' && reference.length < 3) throw fail('invalid-argument', 'REFERENCE_REQUIRED');
    const paymentId = `${actor}_${reqId}`;
    const payRef = db.collection(PAYMENTS).doc(paymentId);
    const refs = ids.map(payableRef);

    // READ фазаси (иккала йўл учун бир хил): тўлов ҳужжати, ёзувлар, ҳамкор баланси, очиқ accrued Σ.
    const readPhase = async (t) => {
      const prev = await t.get(payRef);
      if (prev.exists) return { duplicate: prev.data() || {} };
      const snaps = await Promise.all(refs.map((r) => t.get(r)));
      let sum = 0;
      snaps.forEach((s, i) => {
        const x = s.exists ? (s.data() || {}) : null;
        if (!x) throw fail('not-found', 'PAYABLE_NOT_FOUND', { payableId: ids[i] });
        if (x.partnerKey !== key) throw fail('failed-precondition', 'PAYABLE_PARTNER_MISMATCH', { payableId: ids[i] });
        if (x.status !== 'accrued' || !isInt(x.amount) || x.amount <= 0) throw fail('failed-precondition', 'PAYABLE_NOT_PAYABLE', { payableId: ids[i], status: x.status || '' });
        sum += x.amount;
      });
      const [acc, openSnap] = await Promise.all([
        t.get(accountRef(key)),
        t.get(db.collection(PAYABLES).where('partnerKey', '==', key).where('status', '==', 'accrued')),
      ]);
      const balance = acc.exists ? ((acc.data() || {}).balance || 0) : 0;
      const openAccrued = openSnap.docs.reduce((a, s) => a + (isInt((s.data() || {}).amount) ? s.data().amount : 0), 0);
      const problem = paymentProblem({ method, balance, openAccrued, sum });
      if (problem) throw fail('failed-precondition', problem, { balance, openAccrued, sum });
      const sellerId = (snaps[0].data() || {}).sellerId || null;
      return { sum, balance, openAccrued, sellerId };
    };
    const writePhase = (t, pre, entryId) => {
      const paid = { status: 'paid', paymentId, method, paidAt: ts(), paidBy: actor, updatedAt: ts() };
      refs.forEach((r, i) => {
        t.update(r, paid);
        event(t, ids[i], { type: 'paid', method, paymentId, actor, entryId: entryId || null });
      });
      t.set(payRef, {
        paymentId, partnerKey: key, sellerId: pre.sellerId, payableIds: ids, amount: pre.sum, method, reference,
        entryId: entryId || null, actor, channel: method === 'offset' ? 'offset_against_clawback' : 'manual_outside_system', createdAt: ts(),
      });
      t.set(summaryRef(key), {
        ...(method === 'offset' ? { offsetTotal: FV.increment(pre.sum) } : { paidTotal: FV.increment(pre.sum) }),
        openCount: FV.increment(-ids.length), lastPaidAt: ts(), updatedAt: ts(),
      }, { merge: true });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'sm_partner_paid', actor, target: `${SUMMARY}/${key}`, partnerKey: key, payableIds: ids, total: pre.sum, method, reference,
        paymentId, balanceBefore: pre.balance, at: ts(),
      });
    };

    let out;
    try {
      if (method === 'offset') {
        out = await db.runTransaction(async (t) => {
          const pre = await readPhase(t);
          if (pre.duplicate) return { duplicate: true, amount: pre.duplicate.amount || 0 };
          writePhase(t, pre, null);
          return { duplicate: false, amount: pre.sum };
        });
      } else {
        // Нақд/банк: journal калити = paymentId; postEntry ўзи ҳам идемпотент.
        if ((await journalRef(paidKeyOf(paymentId)).get()).exists) {
          const p = await payRef.get();
          out = { duplicate: true, amount: p.exists ? ((p.data() || {}).amount || 0) : 0 };
        } else {
          const sum = await (async () => {
            // Сумма ledger оёқлари учун керак — транзакциядан олдин тахминий ўқилади, ичкарида қайта текширилади.
            const snaps = await db.getAll(...refs);
            const missing = snaps.findIndex((s) => !s.exists);
            if (missing >= 0) throw fail('not-found', 'PAYABLE_NOT_FOUND', { payableId: ids[missing] });
            return snaps.reduce((a, s) => a + (isInt((s.data() || {}).amount) ? s.data().amount : 0), 0);
          })();
          if (!(sum > 0)) throw fail('failed-precondition', 'PAYABLE_NOT_PAYABLE');
          const res = await settlementLedger.postEntry(db, {
            idempotencyKey: paidKeyOf(paymentId),
            kind: KIND_PAID,
            refType: 'sm_partner_payment',
            refId: paymentId,
            postedBy: actor,
            postedRole: 'admin',
            legs: [{ account: partnerAccount(key), dr: sum }, { account: CASH, cr: sum }],
          }, {
            mirrorBonus: false,
            meta: { module: 'supermarket', partnerKey: key, method, reference, payableIds: ids },
            precheck: async (tx) => {
              const pre = await readPhase(tx);
              if (pre.duplicate) throw reasonError('duplicate', { amount: pre.duplicate.amount || 0 });
              if (pre.sum !== sum) throw reasonError('sum_changed');
              return pre;
            },
            onCommit: (tx, { entryId, pre }) => writePhase(tx, pre, entryId),
          });
          out = { duplicate: res.idempotent, amount: sum };
        }
      }
    } catch (e) {
      if (e && e.reason === 'duplicate') out = { duplicate: true, amount: e.amount || 0 };
      else {
        const code = (e && e.reason === 'sum_changed') ? 'PAYABLE_NOT_PAYABLE' : ((e && e.details && e.details.code) || 'INTERNAL');
        log({ action: 'adminMarkSmPartnerPaid', result: 'error', errorCode: code, partnerKey: key, userTail: actor.slice(-4) }, 'warn');
        if (e instanceof HttpsError) throw e;
        if (e && e.reason === 'sum_changed') throw fail('failed-precondition', 'PAYABLE_NOT_PAYABLE');
        log({ action: 'adminMarkSmPartnerPaid', result: 'error', errorCode: 'INTERNAL', message: String(e && e.message) }, 'error');
        throw fail('internal', 'INTERNAL');
      }
    }
    log({ action: 'adminMarkSmPartnerPaid', result: 'ok', partnerKey: key, count: ids.length, amount: out.amount, method, duplicate: out.duplicate, userTail: actor.slice(-4), durationMs: Date.now() - started });
    return { ok: true, paymentId, partnerKey: key, count: ids.length, amount: out.amount, method, ...(out.duplicate ? { duplicate: true } : {}) };
  });

  /** { payableId, reason ≥3 } — қайтариш/шикоят учун тескари ёзув (accrued ёки paid → reversed). */
  exportsObj.adminReverseSmPartnerPayable = functions.https.onCall(async (data, context) => {
    const actor = await roles(context, SET_ROLES);
    const pid = typeof (data && data.payableId) === 'string' ? data.payableId.trim() : '';
    const reason = typeof (data && data.reason) === 'string' ? data.reason.trim().slice(0, 300) : '';
    if (!PAYABLE_ID_RE.test(pid)) throw fail('invalid-argument', 'INVALID_REQUEST');
    if (reason.length < 3) throw fail('invalid-argument', 'REASON_REQUIRED');
    try {
      const r = await reversePayable(pid, { reason, actor, actorRole: 'admin', source: 'admin' });
      log({ action: 'adminReverseSmPartnerPayable', result: 'ok', payableId: pid, changed: r.changed, clawback: !!r.clawback, userTail: actor.slice(-4) });
      return { ok: true, payableId: pid, changed: r.changed, ...(r.clawback ? { clawback: true } : {}) };
    } catch (e) {
      if (e && e.reason === 'not_found') throw fail('not-found', 'PAYABLE_NOT_FOUND');
      if (e && e.reason === 'not_reversible') throw fail('failed-precondition', 'PAYABLE_NOT_REVERSIBLE', { status: e.status || '' });
      log({ action: 'adminReverseSmPartnerPayable', result: 'error', errorCode: 'INTERNAL', message: String(e && e.message) }, 'error');
      throw fail('internal', 'INTERNAL');
    }
  });

  /**
   * Қайта ҳисоблаш: { orderIds[≤50] } ёки { from, to } (slot.date, ≤31 кун, ≤500 буюртма).
   * Блокланган (қоида йўқ, тортилмаган…) ва trigger ўтказиб юборган буюртмалар учун. Пул икки марта ёзилмайди.
   */
  exportsObj.adminRecomputeSmPartnerPayables = functions.https.onCall(async (data, context) => {
    const actor = await roles(context, SET_ROLES);
    const settings = await readSettings();
    if (settings.stage === 'off') throw fail('failed-precondition', 'STAGE_OFF');
    const d = data || {};
    let ids = [];
    let truncated = false;
    if (Array.isArray(d.orderIds)) {
      ids = [...new Set(d.orderIds.map((x) => String(x || '').trim()))];
      if (ids.length < 1 || ids.length > RECOMPUTE_MAX || ids.some((x) => !ORDER_ID_RE.test(x))) throw fail('invalid-argument', 'INVALID_REQUEST');
    } else {
      const from = String(d.from || '');
      const to = String(d.to || '');
      if (!DATE_RE.test(from) || !DATE_RE.test(to) || from > to || daysBetween(from, to) + 1 > SWEEP_MAX_DAYS) throw fail('invalid-argument', 'RANGE_INVALID');
      const snap = await db.collection(ORDERS).where('subtype', '==', 'supermarket').where('slot.date', '>=', from).where('slot.date', '<=', to)
        .orderBy('slot.date').limit(SWEEP_MAX_ORDERS + 1).get();
      truncated = snap.size > SWEEP_MAX_ORDERS;
      ids = snap.docs.slice(0, SWEEP_MAX_ORDERS).filter((s) => { const x = s.data() || {}; return isDelivered(x) || isCancelled(x); }).map((s) => s.id);
    }
    const tally = { orders: ids.length, accrued: 0, blocked: 0, nothingDue: 0, existing: 0, reversed: 0, voided: 0, errors: 0 };
    for (const id of ids) {
      try {
        const r = await processOrder(id, 'admin_recompute');
        if (r.result === 'cancelled') { tally.reversed += r.reversed || 0; tally.voided += r.voided || 0; continue; }
        for (const p of r.partners || []) {
          if (p.result === 'accrued') tally.accrued += 1;
          else if (p.result === 'blocked' || p.result === 'unchanged') tally.blocked += 1;
          else if (p.result === 'nothing_due') tally.nothingDue += 1;
          else tally.existing += 1;
        }
      } catch (e) {
        tally.errors += 1;
        log({ action: 'adminRecomputeSmPartnerPayables', orderId: id, result: 'error', errorCode: 'SM_PARTNER_RECOMPUTE_ITEM', message: String(e && e.message) }, 'error');
      }
    }
    await db.collection(ADMIN_AUDIT).add({ kind: 'sm_partner_payout_recompute', actor, target: PAYABLES, ...tally, truncated, at: ts() });
    log({ action: 'adminRecomputeSmPartnerPayables', result: 'ok', userTail: actor.slice(-4), ...tally, truncated });
    return { ok: true, ...tally, truncated };
  });

  // ── Ҳамкор: ўз баланси ва ёзувлари (фақат stage == public) ──
  exportsObj.partnerGetSmPayouts = functions.https.onCall(async (data, context) => {
    let partner;
    try {
      partner = await requirePartner(context);
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      throw fail('internal', 'INTERNAL');
    }
    const settings = await readSettings();
    if (settings.stage !== 'public') return { ok: true, enabled: false };
    const key = partner.key;
    const [sum, acc, pSnap, paySnap] = await Promise.all([
      summaryRef(key).get(),
      accountRef(key).get(),
      db.collection(PAYABLES).where('partnerKey', '==', key).orderBy('createdAt', 'desc').limit(100).get(),
      db.collection(PAYMENTS).where('partnerKey', '==', key).orderBy('createdAt', 'desc').limit(30).get(),
    ]);
    const s = summaryView(key, sum.exists ? (sum.data() || {}) : {}, acc.exists ? ((acc.data() || {}).balance || 0) : 0);
    // Ҳамкорга мижоз маълумоти ЙЎҚ (40-банд): фақат буюртма ID, сана, суммалар, ҳолат.
    return {
      ok: true,
      enabled: true,
      commissionBp: settings.commissionBp,
      balance: s.balance, accruedTotal: s.accruedTotal, paidTotal: s.paidTotal + s.offsetTotal, reversedTotal: s.reversedTotal, blockedCount: s.blockedCount,
      payables: pSnap.docs.map((d) => {
        const x = d.data() || {};
        return {
          orderId: x.orderId || '', slotDate: x.slotDate || '', status: x.status || '', goodsBasis: isInt(x.goodsBasis) ? x.goodsBasis : 0,
          commission: isInt(x.commission) ? x.commission : null, amount: isInt(x.amount) ? x.amount : null, paidAtMs: toMs(x.paidAt),
        };
      }),
      payments: paySnap.docs.map((d) => {
        const x = d.data() || {};
        return { amount: x.amount || 0, method: x.method || '', reference: x.method === 'bank_transfer' ? (x.reference || '') : '', createdAtMs: toMs(x.createdAt) };
      }),
    };
  });

  return { processOrder, reversePayable, cancelOrder };
}

module.exports = {
  attachSmPartnerPayout,
  // тоза (тестлар)
  parseSettings, commissionOf, lineBasis, planOrder, paymentProblem, partnerAccount, payableIdOf,
  accrueKeyOf, reverseKeyOf, paidKeyOf, isDelivered, isCancelled, messagesOf,
  STAGES, STATUSES, BLOCK_REASONS, METHODS, PAYABLES, PAYMENTS, SUMMARY, SETTINGS_DOC, HISTORY, BP_MAX, KIND_ACCRUE, KIND_REVERSE, KIND_PAID,
};
