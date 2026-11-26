/**
 * «AVA Супермаркет» 3-босқич — ФАҚАТ ҲИСОБОТЛАР (эга 2026-11-21).
 *
 * Тизим ҲЕЧ НАРСА СОТИБ ОЛМАЙДИ ва таъминотчига мурожаат ҚИЛМАЙДИ — фақат ҳисоблайди.
 *
 * A) adminSupermarketProcurementReport({date}) — admin/superadmin/dispatcher, фақат ўқиш:
 *    `orders` (type platform, subtype supermarket, paymentStatus paid, slot.date == date,
 *    status new|accepted, бекор/рад/етказилган эмас) → таклиф бўйича талаб (бирлик бўйича, тортиладиган — кг),
 *    `stock` («бўш қолдиқ» — буюртмада камаяди, CONFIRMED), reserved (очиқ new|accepted|ready буюртмаларда
 *    банд, ҲАР ҚАНДАЙ сана), onHand = stock + reserved («жисмоний қолдиқ»), shortfall = max(0, талаб − onHand)
 *    (эга 2026-11-26), буюртмалар сони; нав/гуруҳ/бўлим бўйича йиғма. Мижоз PII натижага КИРМАЙДИ.
 * B) smDailyStats (ҳар куни 00:30 Asia/Tashkent) → `supermarket_stats/{YYYY-MM-DD}` (кечаги кун, тўлиқ қайта
 *    ёзиш — идемпотент). Кун асоси — `slot.date` (етказиш куни; PROPOSED). adminSupermarketStats({from,to,backfill})
 *    — ≤92 кун; backfill:true — етишмаган кунни (≤7 та) ҳисоблаб ёзади (фақат admin/superadmin, audit).
 *    Курьер тўлови (эга 2026-11-26): етказилганларнинг orders/{id}/private/courier_payout.amount йиғиндиси, тўланган/тўланмаган;
 *    netLogistics = етказилганлар deliveryFee − тўлов (нусхаси йўқ буюртма бўлса null + courierPayoutPartial).
 *
 * ПУЛ — бутун сўм; миқдор — милли-бирлик бутун сонида йиғилади (supermarket.js toMilli).
 */
'use strict';

const { toMilli, fromMilli, isCancelled, tashkentParts, findGroup, ORDER_ORIGINS } = require('./supermarket');

const MODULE = 'supermarket_reports';
const ORDERS = 'orders';
const PRODUCTS = 'platform_products';
const STATS = 'supermarket_stats';
const ADMIN_AUDIT = 'admin_audit';
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);
const OPERATOR_ROLES = Object.freeze(['admin', 'superadmin', 'dispatcher']);
const PROCUREMENT_STATUSES = Object.freeze(['new', 'accepted']);
// Жисмоний қолдиқ учун «очиқ» буюртмалар (stock буюртмада камайган, ҳали етказилмаган) — эга 2026-11-26.
const RESERVING_STATUSES = Object.freeze(['new', 'accepted', 'ready']);
const ORIGINS = ORDER_ORIGINS; // ягона манба — supermarket.js
const STATS_SCHEMA = 'sm-stats-v1';
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const DAY_MS = 86400000;
const PAGE = 300;
const MAX_ORDERS = 3000; // пилот учун чегара; ошса truncated:true
const MAX_RANGE_DAYS = 92;
const MAX_BACKFILL = 7;
const TOP_GROUPS = 20;
const REPEAT_MAX = 1000; // такрорий мижоз текшируви (ҳар мижозга 1 сўров) чегараси
const REPORT_WINDOW_DAYS = 31;

// Қайтим тури (adjustOrder action) → ҳисобот гуруҳи.
const REFUND_BUCKET = Object.freeze({
  weigh: 'weigh',
  shortage_substitute: 'shortage',
  shortage_reduce: 'shortage',
  remove: 'removed',
  shortage_remove: 'removed',
});

const MSG = Object.freeze({
  UNAUTHENTICATED: ['Илтимос, тизимга киринг.', 'Iltimos, tizimga kiring.', 'Пожалуйста, войдите в систему.'],
  PERMISSION_DENIED: ['Бу амал учун рухсат йўқ.', 'Bu amal uçun ruxsat yöq.', 'Нет доступа к этому действию.'],
  DATE_INVALID: ['Сана нотўғри.', 'Sana notöğri.', 'Неверная дата.'],
  PAYOUT_REQUEST_INVALID: ['Сўров нотўғри.', "So'rov notöğri.", 'Неверный запрос.'],
  ORDER_NOT_FOUND: ['Буюртма топилмади.', 'Buyurtma topilmadi.', 'Заказ не найден.'],
  ORDER_NOT_SUPERMARKET: ['Бу супермаркет буюртмаси эмас.', 'Bu supermarket buyurtmasi emas.', 'Это не заказ супермаркета.'],
  ORDER_NOT_DELIVERED: ['Буюртма ҳали етказилмаган.', 'Buyurtma hali yetkazilmagan.', 'Заказ ещё не доставлен.'],
  COURIER_MISMATCH: ['Буюртма бошқа курьерга тегишли.', 'Buyurtma boşqa kuryerga tegişli.', 'Заказ принадлежит другому курьеру.'],
  PAYOUT_NOT_CONFIGURED: ['Бу буюртмада курьер тўлови белгиланмаган.', 'Bu buyurtmada kuryer tölovi belgilanmagan.', 'Для этого заказа не задана выплата курьеру.'],
  ALREADY_PAID: ['Бу буюртма аллақачон тўланган деб белгиланган.', 'Bu buyurtma allaqaçon tölangan deb belgilangan.', 'Этот заказ уже отмечен как оплаченный.'],
  RANGE_INVALID: ['Сана оралиғи нотўғри (кўпи билан 92 кун).', 'Sana oralığı notöğri (köpi bilan 92 kun).', 'Неверный период (не более 92 дней).'],
  INTERNAL: ['Ҳисоботни тайёрлаб бўлмади. Қайта уриниб кўринг.', "Hisobotni tayyorlab bölmadi. Qayta urinib köring.", 'Не удалось подготовить отчёт. Попробуйте ещё раз.'],
});
const messagesOf = (code) => { const m = MSG[code] || MSG.INTERNAL; return { uz_Cyrl: m[0], uz_Latn: m[1], ru: m[2] }; };

// ══════════════════════ ТОЗА ФУНКЦИЯЛАР ══════════════════════

function validDateKey(s) {
  if (typeof s !== 'string' || !DATE_RE.test(s)) return false;
  const ms = Date.parse(`${s}T00:00:00Z`);
  return Number.isFinite(ms) && new Date(ms).toISOString().slice(0, 10) === s;
}
const dateMs = (s) => Date.parse(`${s}T00:00:00Z`);
function addDays(s, n) { return new Date(dateMs(s) + n * DAY_MS).toISOString().slice(0, 10); }
function daysBetween(from, to) { return Math.round((dateMs(to) - dateMs(from)) / DAY_MS); }

function isDelivered(od) {
  return String(od.status || '') === 'delivered' || String(od.fulfillmentStatus || '').toLowerCase() === 'completed';
}

/** Харид режасига кирадими: тўланган, new|accepted, бекор/етказилган эмас. */
function procurementEligible(od) {
  if (!od || od.subtype !== 'supermarket') return false;
  if (od.paymentStatus !== 'paid') return false;
  if (!PROCUREMENT_STATUSES.includes(String(od.status || ''))) return false;
  return !isCancelled(od) && !isDelivered(od);
}

/** Қатор миқдори (милли): тортилган бўлса actualQty, акс ҳолда qty; олинган — 0. */
function lineQtyMilli(l) {
  if (!l || l.removed) return 0;
  const m = toMilli(Number(l.actualQty != null ? l.actualQty : l.qty));
  return m != null && m > 0 ? m : 0;
}
function lineSum(l) {
  if (!l || l.removed) return 0;
  const v = l.finalTotal != null ? l.finalTotal : l.total;
  return Number.isInteger(v) && v > 0 ? v : 0;
}
const unitOf = (l, p) => String((l && l.smUnit) || (p && p.unit) || 'piece');
const addMilli = (map, unit, m) => { map[unit] = (map[unit] || 0) + m; };
const milliMapOut = (map) => {
  const o = {};
  for (const k of Object.keys(map).sort()) o[k] = fromMilli(map[k]);
  return o;
};

/**
 * Очиқ (new|accepted|ready, бекор/етказилган эмас) supermarket буюртмаларида банд миқдор (милли), таклиф бўйича.
 * placeSupermarketOrder stock'ни камайтиради, бекор → onSupermarketOrderCancelStock қайтаради, тортиш/олиш фарқни
 * stock'га қайтаради — шунинг учун жисмоний қолдиқ = stock + шу банд миқдор (lineQtyMilli: тортилган бўлса actualQty).
 */
function reservedByOffer(orders) {
  const out = {};
  for (const od of orders) {
    if (!od || od.subtype !== 'supermarket' || !RESERVING_STATUSES.includes(String(od.status || ''))) continue;
    if (isCancelled(od) || isDelivered(od)) continue;
    for (const l of (Array.isArray(od.items) ? od.items : [])) {
      const q = lineQtyMilli(l);
      if (q > 0 && typeof l.productId === 'string') out[l.productId] = (out[l.productId] || 0) + q;
    }
  }
  return out;
}

/**
 * Харид режаси (тоза).
 * @param {object[]} orders — буюртма ҳужжатлари (филтрланмаган ҳам бўлиши мумкин — бу ерда procurementEligible)
 * @param {{[productId]: object|null}} products — жорий таклиф ҳужжатлари
 * @param {object|null} taxonomy — taxonomy/supermarket
 */
function aggregateProcurement(orders, products, taxonomy, reserved = {}) {
  const offers = new Map();
  let orderCount = 0;
  for (const od of orders) {
    if (!procurementEligible(od)) continue;
    orderCount += 1;
    for (const l of (Array.isArray(od.items) ? od.items : [])) {
      const q = lineQtyMilli(l);
      if (!(q > 0) || typeof l.productId !== 'string') continue;
      const p = products[l.productId] || null;
      let o = offers.get(l.productId);
      if (!o) {
        const groupId = String(l.groupId || (p && p.smGroupId) || 'unknown');
        const found = findGroup(taxonomy, groupId);
        const categoryId = String((p && p.smCategoryId) || (found && found.category.id) || 'unknown');
        const variety = (p && p.smVariety) || null;
        o = {
          productId: l.productId,
          name: String((p && p.name) || l.name || l.productId),
          packLabel: (p && p.packLabel) || l.packLabel || null,
          groupId,
          groupNames: found ? found.group.names : null,
          categoryId,
          categoryNames: found ? found.category.names : null,
          categoryOrder: found && Number.isInteger(found.category.order) ? found.category.order : 9999,
          varietyId: (variety && variety.id) || l.varietyId || null,
          varietyNames: (variety && variety.names) || null,
          unit: unitOf(l, p),
          weighed: l.weighed === true,
          demandMilli: 0,
          orders: new Set(),
          stockMilli: p ? Math.max(0, toMilli(Number(p.stock)) || 0) : null,
          reservedMilli: Math.max(0, Number(reserved[l.productId]) || 0),
          productMissing: !p,
        };
        offers.set(l.productId, o);
      }
      o.demandMilli += q;
      o.orders.add(od.__id || od.id || `${orderCount}`);
    }
  }
  const offerRows = [];
  const groups = new Map();
  const varieties = new Map();
  const categories = new Map();
  const roll = (map, key, base, o, shortMilli) => {
    let r = map.get(key);
    if (!r) { r = { ...base, demand: {}, shortfall: {}, orders: new Set(), offerCount: 0 }; map.set(key, r); }
    addMilli(r.demand, o.unit, o.demandMilli);
    addMilli(r.shortfall, o.unit, shortMilli);
    o.orders.forEach((x) => r.orders.add(x));
    r.offerCount += 1;
  };
  for (const o of offers.values()) {
    // Эга 2026-11-26: жисмоний қолдиқ (onHand) = бўш қолдиқ (stock) + очиқ буюртмаларда банд; shortfall = max(0, талаб − onHand).
    const onHandMilli = o.stockMilli == null ? null : o.stockMilli + o.reservedMilli;
    const shortMilli = onHandMilli == null ? o.demandMilli : Math.max(0, o.demandMilli - onHandMilli);
    offerRows.push({
      productId: o.productId, name: o.name, packLabel: o.packLabel, groupId: o.groupId, groupNames: o.groupNames,
      categoryId: o.categoryId, categoryNames: o.categoryNames, varietyId: o.varietyId, varietyNames: o.varietyNames,
      unit: o.unit, weighed: o.weighed, demandQty: fromMilli(o.demandMilli),
      stock: o.stockMilli == null ? null : fromMilli(o.stockMilli), reserved: fromMilli(o.reservedMilli),
      onHand: onHandMilli == null ? null : fromMilli(onHandMilli), shortfall: fromMilli(shortMilli),
      orderCount: o.orders.size, productMissing: o.productMissing, categoryOrder: o.categoryOrder,
    });
    roll(groups, o.groupId, { groupId: o.groupId, groupNames: o.groupNames, categoryId: o.categoryId }, o, shortMilli);
    roll(varieties, `${o.groupId}/${o.varietyId || '-'}`, { groupId: o.groupId, varietyId: o.varietyId, varietyNames: o.varietyNames, categoryId: o.categoryId }, o, shortMilli);
    roll(categories, o.categoryId, { categoryId: o.categoryId, categoryNames: o.categoryNames, categoryOrder: o.categoryOrder }, o, shortMilli);
  }
  const out = (r) => {
    const { orders: set, demand, shortfall, ...rest } = r;
    return { ...rest, demandQty: milliMapOut(demand), shortfall: milliMapOut(shortfall), orderCount: set.size };
  };
  offerRows.sort((a, b) => (a.categoryOrder - b.categoryOrder) || a.categoryId.localeCompare(b.categoryId)
    || a.groupId.localeCompare(b.groupId) || a.name.localeCompare(b.name));
  return {
    orderCount,
    offers: offerRows,
    varieties: [...varieties.values()].map(out),
    groups: [...groups.values()].map(out),
    categories: [...categories.values()].map(out).sort((a, b) => (a.categoryOrder - b.categoryOrder) || a.categoryId.localeCompare(b.categoryId)),
  };
}

/**
 * Кунлик статистика (тоза). orders — шу кун (slot.date) нинг БАРЧА supermarket буюртмалари.
 * repeatCustomers — сонини чақирувчи ҳисоблайди (сўров керак), бу ерда фақат customers рўйхати қайтади.
 */
function aggregateDailyStats(orders) {
  const s = {
    orders: 0, delivered: 0, cancelled: 0, open: 0,
    gmv: 0, deliveryFeeRevenue: 0, deliveredFeeRevenue: 0,
    courierPayout: 0, courierPayoutPaid: 0, courierPayoutUnpaid: 0, courierPayoutMissing: 0,
    refundsTotal: 0, refundsByType: { weigh: 0, shortage: 0, removed: 0, unattributed: 0 },
    extraChargedTotal: 0,
    byOrigin: { catalog: 0, quick: 0, weekly: 0, reorder: 0, unknown: 0 },
  };
  const customers = new Set();
  const groups = new Map();
  let nonCancelled = 0;
  for (const od of orders) {
    if (!od || od.subtype !== 'supermarket') continue;
    s.orders += 1;
    const origin = ORIGINS.includes(od.smOrigin) ? od.smOrigin : 'unknown';
    s.byOrigin[origin] += 1;
    const refunded = Math.max(0, Math.trunc(Number(od.smRefundedTotal || 0)));
    s.refundsTotal += refunded;
    let attributed = 0;
    const by = od.smRefundByAction && typeof od.smRefundByAction === 'object' ? od.smRefundByAction : {};
    for (const k of Object.keys(by)) {
      const v = Math.max(0, Math.trunc(Number(by[k] || 0)));
      const b = REFUND_BUCKET[k];
      if (!b || !v) continue;
      s.refundsByType[b] += v;
      attributed += v;
    }
    s.refundsByType.unattributed += Math.max(0, refunded - attributed);
    s.extraChargedTotal += Math.max(0, Math.trunc(Number(od.smExtraChargedTotal || 0)));
    if (isCancelled(od)) { s.cancelled += 1; continue; }
    nonCancelled += 1;
    if (isDelivered(od)) {
      s.delivered += 1;
      // Курьер тўлови (эга 2026-11-26): етказилган буюртмадаги нусха (smCourierPayout.amount); пул тизимда юрмайди.
      s.deliveredFeeRevenue += Math.max(0, Math.trunc(Number(od.deliveryFee || 0)));
      const amt = od.smCourierPayout && Number.isInteger(od.smCourierPayout.amount) ? od.smCourierPayout.amount : null;
      if (amt == null) s.courierPayoutMissing += 1;
      else {
        s.courierPayout += amt;
        if (od.smCourierPaid && od.smCourierPaid.at) s.courierPayoutPaid += amt; else s.courierPayoutUnpaid += amt;
      }
    } else s.open += 1;
    s.gmv += Math.max(0, Math.trunc(Number(od.itemsTotal || 0)));
    s.deliveryFeeRevenue += Math.max(0, Math.trunc(Number(od.deliveryFee || 0)));
    if (od.userPhone) customers.add(String(od.userPhone));
    for (const l of (Array.isArray(od.items) ? od.items : [])) {
      const q = lineQtyMilli(l);
      if (!(q > 0)) continue;
      const gid = String(l.groupId || 'unknown');
      let g = groups.get(gid);
      if (!g) { g = { groupId: gid, sum: 0, qty: {}, lines: 0 }; groups.set(gid, g); }
      g.sum += lineSum(l);
      addMilli(g.qty, unitOf(l, null), q);
      g.lines += 1;
    }
  }
  s.avgBasket = nonCancelled > 0 ? Math.floor(s.gmv / nonCancelled) : 0;
  s.uniqueCustomers = customers.size;
  const all = [...groups.values()];
  const view = (g) => ({ groupId: g.groupId, sum: g.sum, qty: milliMapOut(g.qty), lines: g.lines });
  s.topGroupsBySum = all.slice().sort((a, b) => (b.sum - a.sum) || a.groupId.localeCompare(b.groupId)).slice(0, TOP_GROUPS).map(view);
  // Миқдор бўйича — бирликлар аралаш бўлгани учун қаторлар сони (кейин миқдор йиғиндиси) бўйича.
  const qtySum = (g) => Object.values(g.qty).reduce((a, b) => a + b, 0);
  s.topGroupsByQty = all.slice().sort((a, b) => (b.lines - a.lines) || (qtySum(b) - qtySum(a)) || a.groupId.localeCompare(b.groupId)).slice(0, TOP_GROUPS).map(view);
  // Соф логистика = етказилган буюртмалар deliveryFee − курьер тўлови; бирор етказилганда нусха йўқ → null (partial).
  s.courierPayoutSource = 'snapshot';
  s.courierPayoutPartial = s.courierPayoutMissing > 0;
  s.netLogistics = s.courierPayoutPartial ? null : s.deliveredFeeRevenue - s.courierPayout;
  return { stats: s, customers: [...customers].sort() };
}

/** Кунлар йиғмаси (callable учун). */
function summarizeDays(days) {
  const t = { orders: 0, delivered: 0, cancelled: 0, gmv: 0, deliveryFeeRevenue: 0, deliveredFeeRevenue: 0, refundsTotal: 0, uniqueCustomersSum: 0, repeatCustomersSum: 0, weeklyOrders: 0, days: days.length,
    courierPayout: 0, courierPayoutPaid: 0, courierPayoutUnpaid: 0, courierPayoutMissing: 0 };
  let netKnown = true;
  for (const d of days) {
    t.orders += d.orders || 0; t.delivered += d.delivered || 0; t.cancelled += d.cancelled || 0;
    t.gmv += d.gmv || 0; t.deliveryFeeRevenue += d.deliveryFeeRevenue || 0; t.refundsTotal += d.refundsTotal || 0;
    t.uniqueCustomersSum += d.uniqueCustomers || 0; t.repeatCustomersSum += d.repeatCustomers || 0;
    t.weeklyOrders += (d.byOrigin && d.byOrigin.weekly) || 0;
    t.deliveredFeeRevenue += d.deliveredFeeRevenue || 0;
    t.courierPayout += Number.isInteger(d.courierPayout) ? d.courierPayout : 0;
    t.courierPayoutPaid += d.courierPayoutPaid || 0; t.courierPayoutUnpaid += d.courierPayoutUnpaid || 0;
    t.courierPayoutMissing += d.courierPayoutMissing || 0;
    // Эски (курьер тўловисиз) ҳужжатда netLogistics null — йиғма ҳам null.
    if (!Number.isInteger(d.netLogistics)) netKnown = false;
  }
  const nonCancelled = t.orders - t.cancelled;
  t.avgBasket = nonCancelled > 0 ? Math.floor(t.gmv / nonCancelled) : 0;
  t.courierPayoutPartial = !netKnown;
  t.netLogistics = netKnown ? t.deliveredFeeRevenue - t.courierPayout : null;
  return t;
}

// ══════════════════════ CALLABLES / SCHEDULER ══════════════════════

function attachSupermarketReports(exportsObj, deps) {
  const { functions, db, admin, requireCallerRoles } = deps;
  const HttpsError = functions.https.HttpsError;
  const FV = admin.firestore.FieldValue;
  const FieldPath = admin.firestore.FieldPath;
  const fail = (status, code, extra = {}) => new HttpsError(status, messagesOf(code).uz_Cyrl, { code, messages: messagesOf(code), ...extra });
  const log = (fields) => console.log(JSON.stringify({ module: MODULE, ...fields }));
  const now = () => (deps.nowMs ? deps.nowMs() : Date.now());
  const requireRoles = async (context, roles) => {
    try {
      return await requireCallerRoles(context, roles, 'Role required');
    } catch (e) {
      if (e instanceof HttpsError) throw fail(e.code, e.code === 'unauthenticated' ? 'UNAUTHENTICATED' : 'PERMISSION_DENIED');
      throw e;
    }
  };

  /** Сўров натижаси саҳифалаб (__name__), MAX_ORDERS гача. */
  async function pagedOrders(base, orderFirst = null) {
    const out = [];
    let last = null;
    for (;;) {
      let q = (orderFirst ? base.orderBy(orderFirst) : base).orderBy(FieldPath.documentId()).limit(PAGE);
      if (last) q = q.startAfter(last);
      const snap = await q.get();
      for (const d of snap.docs) out.push({ ...d.data(), __id: d.id });
      if (snap.size < PAGE) return { orders: out, truncated: false };
      if (out.length >= MAX_ORDERS) return { orders: out, truncated: true };
      last = snap.docs[snap.docs.length - 1];
    }
  }
  /** slot.date == date бўлган supermarket буюртмалари. */
  const ordersForDate = (date) => pagedOrders(db.collection(ORDERS).where('subtype', '==', 'supermarket').where('slot.date', '==', date));
  /** Барча очиқ (new|accepted|ready) supermarket буюртмалари — ҳар қандай сана (жисмоний қолдиқ учун). */
  const openOrders = () => pagedOrders(db.collection(ORDERS).where('subtype', '==', 'supermarket').where('status', 'in', [...RESERVING_STATUSES]));

  async function productsByIds(ids) {
    const res = {};
    for (let i = 0; i < ids.length; i += 100) {
      const refs = ids.slice(i, i + 100).map((id) => db.collection(PRODUCTS).doc(id));
      const snaps = refs.length ? await db.getAll(...refs) : [];
      snaps.forEach((s) => { res[s.id] = s.exists ? (s.data() || {}) : null; });
    }
    return res;
  }

  exportsObj.adminSupermarketProcurementReport = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = await requireRoles(context, OPERATOR_ROLES);
    const date = String((data || {}).date || '');
    const today = tashkentParts(now()).dateKey;
    if (!validDateKey(date) || Math.abs(daysBetween(today, date)) > REPORT_WINDOW_DAYS) throw fail('invalid-argument', 'DATE_INVALID');
    try {
      const [{ orders, truncated: t1 }, open] = await Promise.all([ordersForDate(date), openOrders()]);
      const truncated = t1 || open.truncated;
      const eligible = orders.filter(procurementEligible);
      const reserved = reservedByOffer(open.orders);
      const ids = [...new Set(eligible.flatMap((o) => (Array.isArray(o.items) ? o.items : []).filter((l) => !l.removed).map((l) => l.productId)).filter((x) => typeof x === 'string' && x))];
      const [products, taxSnap] = await Promise.all([productsByIds(ids), db.collection('taxonomy').doc('supermarket').get()]);
      const agg = aggregateProcurement(eligible, products, taxSnap.exists ? taxSnap.data() : null, reserved);
      log({ action: 'adminSupermarketProcurementReport', result: 'ok', userTail: uid.slice(-4), date, orders: agg.orderCount, offers: agg.offers.length, truncated, duration: Date.now() - started });
      return { ok: true, date, generatedAtMs: now(), truncated, stockIsNetOfReservations: true, onHandSource: 'stock+open_orders', ...agg };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error(JSON.stringify({ module: MODULE, action: 'adminSupermarketProcurementReport', errorCode: 'INTERNAL', error: String((e && e.message) || e) }));
      throw fail('internal', 'INTERNAL');
    }
  });

  /** Мижоз шу кундан олдин (slot.date < date) буюртма берганми — ҳар мижозга 1 сўров, 10 тадан параллел. */
  async function countRepeat(customers, date) {
    const list = customers.slice(0, REPEAT_MAX);
    let n = 0;
    for (let i = 0; i < list.length; i += 10) {
      const part = await Promise.all(list.slice(i, i + 10).map((u) => db.collection(ORDERS)
        .where('subtype', '==', 'supermarket').where('userPhone', '==', u).where('slot.date', '<', date)
        .limit(1).get().then((s) => (s.empty ? 0 : 1))));
      n += part.reduce((a, b) => a + b, 0);
    }
    return { repeatCustomers: n, repeatTruncated: customers.length > REPEAT_MAX };
  }

  async function listsWithReminders() {
    const snap = await db.collectionGroup('sm_lists').where('remindNextAt', '>', admin.firestore.Timestamp.fromMillis(0)).count().get();
    return snap.data().count;
  }

  /** Бир кунни ҳисоблаш (ёзмайди). */
  async function computeDay(date) {
    const { orders: raw, truncated } = await ordersForDate(date);
    // Курьер тўлови — фақат етказилганлар учун private ҳужжат ўқилади (37-банд).
    const orders = await attachPayouts(raw, (o) => isDelivered(o) && !isCancelled(o));
    const { stats, customers } = aggregateDailyStats(orders);
    const rep = await countRepeat(customers, date);
    return { date, dateBasis: 'slot.date', schema: STATS_SCHEMA, ...stats, ...rep, truncated };
  }

  /** Ҳисоблаб тўлиқ ёзади (set, merge йўқ) — қайта ишга тушса ҳам бир хил ҳужжат. */
  async function writeDay(date, source) {
    const day = await computeDay(date);
    let reminders = null;
    try { reminders = await listsWithReminders(); } catch (e) { log({ action: 'listsWithReminders', result: 'error', errorCode: 'COUNT_FAILED' }); }
    const doc = { ...day, listsWithReminders: reminders, source, computedAt: FV.serverTimestamp() };
    await db.collection(STATS).doc(date).set(doc);
    return doc;
  }

  async function runDailyStats() {
    const started = Date.now();
    const date = tashkentParts(now() - DAY_MS).dateKey;
    const doc = await writeDay(date, 'schedule');
    log({ action: 'smDailyStats', result: 'ok', date, orders: doc.orders, truncated: doc.truncated, duration: Date.now() - started });
    return { date, orders: doc.orders };
  }

  exportsObj.smDailyStats = functions.pubsub
    .schedule('30 0 * * *')
    .timeZone('Asia/Tashkent')
    .onRun(() => runDailyStats());

  exportsObj.adminSupermarketStats = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = await requireRoles(context, ADMIN_ROLES);
    const d = data || {};
    const from = String(d.from || '');
    const to = String(d.to || '');
    if (!validDateKey(from) || !validDateKey(to) || from > to || daysBetween(from, to) + 1 > MAX_RANGE_DAYS) throw fail('invalid-argument', 'RANGE_INVALID');
    const backfill = d.backfill === true;
    try {
      const n = daysBetween(from, to) + 1;
      const ids = Array.from({ length: n }, (_, i) => addDays(from, i));
      const snaps = await db.getAll(...ids.map((id) => db.collection(STATS).doc(id)));
      const byId = {};
      snaps.forEach((s) => { if (s.exists) byId[s.id] = s.data(); });
      const today = tashkentParts(now()).dateKey;
      const missing = ids.filter((id) => !byId[id]);
      const backfilled = [];
      const partial = [];
      if (backfill) {
        for (const id of missing.slice(0, MAX_BACKFILL)) {
          if (id >= today) { // кун тугамаган — ёзилмайди, фақат кўрсатилади
            byId[id] = { ...(await computeDay(id)), partial: true };
            partial.push(id);
          } else {
            byId[id] = await writeDay(id, 'backfill');
            backfilled.push(id);
          }
        }
        if (backfilled.length) {
          await db.collection(ADMIN_AUDIT).add({ kind: 'supermarket_stats_backfill', actor: uid, target: `${STATS}`, dates: backfilled, at: FV.serverTimestamp() });
        }
      }
      const days = ids.filter((id) => byId[id]).map((id) => {
        const { computedAt, ...rest } = byId[id];
        return { ...rest, computedAtMs: computedAt && typeof computedAt.toMillis === 'function' ? computedAt.toMillis() : null };
      });
      let reminders = null;
      try { reminders = await listsWithReminders(); } catch (e) { reminders = null; }
      const stillMissing = ids.filter((id) => !byId[id]);
      log({ action: 'adminSupermarketStats', result: 'ok', userTail: uid.slice(-4), from, to, days: days.length, backfilled: backfilled.length, duration: Date.now() - started });
      return { ok: true, from, to, days, missing: stillMissing, backfilled, partial, summary: summarizeDays(days.filter((x) => !x.partial)), listsWithReminders: reminders };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error(JSON.stringify({ module: MODULE, action: 'adminSupermarketStats', errorCode: 'INTERNAL', error: String((e && e.message) || e) }));
      throw fail('internal', 'INTERNAL');
    }
  });

  // ══════════════ Курьерларга тўлов (эга 2026-11-26) ══════════════
  // Тўлов канали — админ курьер КАРТАСИГА тизимдан ТАШҚАРИДА қўлда ўтказади. Тизим пул юрмайди, карта
  // маълумоти САҚЛАНМАЙДИ. Курьер — orders.courierId (courierCreateRoute / етказиш callable'лари ёзади).

  // Курьер тўлови нусхаси ва «тўланди» белгиси — orders/{id}/private/courier_payout (мижоз ўқимайди, 14-банд).
  const payoutRef = (orderRef) => orderRef.collection('private').doc('courier_payout');
  /** Хотирада smCourierPayout / smCourierPaid сифатида бириктиради (тоза агрегациялар ўзгармайди). */
  async function attachPayouts(orders, need = () => true) {
    const list = orders.filter((o) => o.__id && need(o));
    for (let i = 0; i < list.length; i += 100) {
      const part = list.slice(i, i + 100);
      const snaps = await db.getAll(...part.map((o) => payoutRef(db.collection(ORDERS).doc(o.__id))));
      snaps.forEach((s, j) => { Object.assign(part[j], withPayout({}, s)); });
    }
    return orders;
  }

  async function deliveredInRange(from, to) {
    const { orders: raw, truncated } = await pagedOrders(db.collection(ORDERS).where('subtype', '==', 'supermarket')
      .where('slot.date', '>=', from).where('slot.date', '<=', to), 'slot.date');
    const orders = await attachPayouts(raw.filter((o) => isDelivered(o) && !isCancelled(o)));
    return { orders, truncated };
  }

  async function courierNames(ids) {
    const out = {};
    const refs = ids.map((id) => db.collection('users').doc(id));
    const snaps = refs.length ? await db.getAll(...refs) : [];
    const retry = [];
    snaps.forEach((s, i) => {
      if (s.exists) out[ids[i]] = String((s.data() || {}).name || (s.data() || {}).fullName || '').slice(0, 80);
      else if (ids[i].length === 12 && ids[i].startsWith('998')) retry.push(ids[i]);
    });
    if (retry.length) {
      const s9 = await db.getAll(...retry.map((id) => db.collection('users').doc(id.slice(3))));
      s9.forEach((s, i) => { if (s.exists) out[retry[i]] = String((s.data() || {}).name || (s.data() || {}).fullName || '').slice(0, 80); });
    }
    return out;
  }

  exportsObj.adminSupermarketCourierPayouts = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = await requireRoles(context, ADMIN_ROLES);
    const d = data || {};
    const from = String(d.from || '');
    const to = String(d.to || '');
    if (!validDateKey(from) || !validDateKey(to) || from > to || daysBetween(from, to) + 1 > MAX_RANGE_DAYS) throw fail('invalid-argument', 'RANGE_INVALID');
    try {
      const { orders, truncated } = await deliveredInRange(from, to);
      const groups = groupCourierPayouts(orders);
      const names = await courierNames(groups.map((g) => g.courierId).filter((x) => x !== 'unknown'));
      for (const g of groups) g.name = names[g.courierId] || '';
      log({ action: 'adminSupermarketCourierPayouts', result: 'ok', userTail: uid.slice(-4), from, to, couriers: groups.length, orders: orders.length, duration: Date.now() - started });
      return { ok: true, from, to, truncated, couriers: groups };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error(JSON.stringify({ module: MODULE, action: 'adminSupermarketCourierPayouts', errorCode: 'INTERNAL', error: String((e && e.message) || e) }));
      throw fail('internal', 'INTERNAL');
    }
  });

  exportsObj.adminMarkSupermarketCourierPaid = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const actor = await requireRoles(context, ADMIN_ROLES);
    const d = data || {};
    const courierId = canonPhone(d.courierId);
    const ids = Array.isArray(d.orderIds) ? [...new Set(d.orderIds.map((x) => String(x || '').trim()))] : [];
    const note = typeof d.note === 'string' ? d.note.trim().slice(0, 300) : '';
    const reqId = typeof d.clientRequestId === 'string' ? d.clientRequestId.trim() : '';
    if (!courierId || ids.length < 1 || ids.length > MARK_MAX || ids.some((x) => !ORDER_ID_RE.test(x)) || !CLIENT_REQ_RE.test(reqId)) {
      throw fail('invalid-argument', 'PAYOUT_REQUEST_INVALID');
    }
    const idemRef = db.collection('wallet_idempotency').doc(`sm_cpaid_${actor}_${reqId}`);
    let out;
    try {
      out = await db.runTransaction(async (t) => {
        const prev = await t.get(idemRef);
        if (prev.exists) return { ...(prev.data().result || {}), duplicate: true };
        const refs = ids.map((id) => db.collection(ORDERS).doc(id));
        const pRefs = refs.map(payoutRef);
        const snaps = await Promise.all(refs.map((r) => t.get(r)));
        const pSnaps = await Promise.all(pRefs.map((r) => t.get(r)));
        let total = 0;
        snaps.forEach((s, i) => {
          const od = s.exists ? withPayout(s.data() || {}, pSnaps[i]) : null;
          const problem = markPaidProblem(od, courierId);
          if (problem) throw fail('failed-precondition', problem, { orderId: ids[i] });
          total += od.smCourierPayout.amount;
        });
        const paid = { at: FV.serverTimestamp(), by: actor, note, batchId: idemRef.id };
        pRefs.forEach((r) => t.update(r, { paid }));
        t.set(db.collection(ADMIN_AUDIT).doc(), {
          kind: 'sm_courier_paid', actor, target: `courier/${courierId}`, courierId, orderIds: ids, total, note,
          channel: 'manual_card_transfer_outside_system', at: FV.serverTimestamp(),
        });
        const result = { ok: true, courierId, count: ids.length, total };
        t.set(idemRef, { type: 'adminMarkSupermarketCourierPaid', result, createdAt: FV.serverTimestamp() });
        return result;
      });
    } catch (e) {
      const code = (e && e.details && e.details.code) || 'INTERNAL';
      log({ action: 'adminMarkSupermarketCourierPaid', result: 'error', errorCode: code, userTail: actor.slice(-4) });
      if (e instanceof HttpsError) throw e;
      console.error(JSON.stringify({ module: MODULE, action: 'adminMarkSupermarketCourierPaid', error: String((e && e.message) || e) }));
      throw fail('internal', 'INTERNAL');
    }
    log({ action: 'adminMarkSupermarketCourierPaid', result: 'ok', userTail: actor.slice(-4), count: out.count, total: out.total, duplicate: !!out.duplicate, duration: Date.now() - started });
    return out;
  });

  exportsObj.adminUnmarkSupermarketCourierPaid = functions.https.onCall(async (data, context) => {
    const actor = await requireRoles(context, ['superadmin']);
    const d = data || {};
    const orderId = String(d.orderId || '').trim();
    const reason = typeof d.reason === 'string' ? d.reason.trim().slice(0, 300) : '';
    if (!ORDER_ID_RE.test(orderId) || !reason) throw fail('invalid-argument', 'PAYOUT_REQUEST_INVALID');
    const ref = db.collection(ORDERS).doc(orderId);
    const pRef = payoutRef(ref);
    const out = await db.runTransaction(async (t) => {
      const s = await t.get(ref);
      const ps = await t.get(pRef);
      const od = s.exists ? withPayout(s.data() || {}, ps) : null;
      if (!od || od.subtype !== 'supermarket') throw fail('failed-precondition', 'ORDER_NOT_SUPERMARKET', { orderId });
      if (!od.smCourierPaid) return { ok: true, changed: false };
      t.update(pRef, { paid: FV.delete() });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'sm_courier_paid_undo', actor, target: `${ORDERS}/${orderId}`, courierId: String(od.courierId || ''),
        before: od.smCourierPaid, amount: od.smCourierPayout ? od.smCourierPayout.amount : null, reason, at: FV.serverTimestamp(),
      });
      return { ok: true, changed: true };
    });
    log({ action: 'adminUnmarkSupermarketCourierPaid', result: 'ok', userTail: actor.slice(-4), orderId, changed: out.changed });
    return out;
  });

  return { runDailyStats, computeDay, writeDay };
}

/** private/courier_payout снапшотини буюртма объектига (хотирада) қўшади. */
function withPayout(od, snap) {
  const out = od;
  if (snap && snap.exists) {
    const { paid, orderId, createdAt, ...cp } = snap.data() || {};
    out.smCourierPayout = cp;
    out.smCourierPaid = paid || null;
  }
  return out;
}

const MARK_MAX = 200;
const ORDER_ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
const CLIENT_REQ_RE = /^[A-Za-z0-9_-]{8,64}$/;

/** Телефон ID → 12 хонали (998…); бўш — ''. */
function canonPhone(v) {
  const dgt = String(v || '').replace(/\D/g, '');
  if (dgt.length === 9) return `998${dgt}`;
  return dgt.length === 12 && dgt.startsWith('998') ? dgt : '';
}

/** Тўланди деб белгилаш мумкинми — муаммо коди ёки ''. */
function markPaidProblem(od, courierId) {
  if (!od) return 'ORDER_NOT_FOUND';
  if (od.subtype !== 'supermarket') return 'ORDER_NOT_SUPERMARKET';
  if (!isDelivered(od) || isCancelled(od)) return 'ORDER_NOT_DELIVERED';
  if (canonPhone(od.courierId) !== courierId) return 'COURIER_MISMATCH';
  if (!od.smCourierPayout || !Number.isInteger(od.smCourierPayout.amount)) return 'PAYOUT_NOT_CONFIGURED';
  if (od.smCourierPaid) return 'ALREADY_PAID';
  return '';
}

/**
 * Етказилган буюртмалар → курьер бўйича (тоза). Мижоз PII йўқ: фақат буюртма ID, сана, сумма.
 * @returns {{courierId, orders[], total, paid, unpaid, missing}[]}
 */
function groupCourierPayouts(orders) {
  const by = new Map();
  for (const od of orders) {
    if (!od || od.subtype !== 'supermarket' || !isDelivered(od) || isCancelled(od)) continue;
    const cid = canonPhone(od.courierId) || 'unknown';
    let g = by.get(cid);
    if (!g) { g = { courierId: cid, phone: cid === 'unknown' ? '' : cid, orders: [], total: 0, paid: 0, unpaid: 0, missing: 0 }; by.set(cid, g); }
    const amount = od.smCourierPayout && Number.isInteger(od.smCourierPayout.amount) ? od.smCourierPayout.amount : null;
    const paidAt = od.smCourierPaid && od.smCourierPaid.at && typeof od.smCourierPaid.at.toMillis === 'function' ? od.smCourierPaid.at.toMillis() : null;
    const isPaid = !!(od.smCourierPaid && od.smCourierPaid.at);
    g.orders.push({
      orderId: od.__id || od.id || '', date: (od.slot && od.slot.date) || '', deliveryFee: Math.max(0, Math.trunc(Number(od.deliveryFee || 0))),
      amount, mode: (od.smCourierPayout && od.smCourierPayout.mode) || null, paid: isPaid, paidAtMs: paidAt,
    });
    if (amount == null) g.missing += 1;
    else { g.total += amount; if (isPaid) g.paid += amount; else g.unpaid += amount; }
  }
  const out = [...by.values()];
  for (const g of out) g.orders.sort((a, b) => a.date.localeCompare(b.date) || a.orderId.localeCompare(b.orderId));
  return out.sort((a, b) => (b.unpaid - a.unpaid) || a.courierId.localeCompare(b.courierId));
}

module.exports = {
  attachSupermarketReports,
  groupCourierPayouts, markPaidProblem, canonPhone, withPayout,
  aggregateProcurement, reservedByOffer, RESERVING_STATUSES, aggregateDailyStats, summarizeDays, procurementEligible, isDelivered, lineQtyMilli,
  validDateKey, addDays, daysBetween, ORIGINS, REFUND_BUCKET, STATS, STATS_SCHEMA, MAX_RANGE_DAYS, MAX_BACKFILL, messagesOf,
};
