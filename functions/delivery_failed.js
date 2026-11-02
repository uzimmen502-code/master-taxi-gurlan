/**
 * «ЕТКАЗИЛМАДИ» — РЕСТОРАНДАН БОШҚА КУРЬЕР ТУРЛАРИ (эга қарорлари 2026-10-31, «тавсияларга розиман»;
 * таклиф: docs/kuryer_yetkazilmadi_boshqa_turlar_taklif_2026-10-31_uz.md, «Эга қарорлари» бўлими).
 *
 * МОДУЛЛАР (customer_confirm модул калити → ҳужжат):
 *   order      — нон/бозор буюртмаси `orders` (type bread | platform | бўш); курьер маршрутда
 *   carpet     — гилам `carpet_wash_orders`: олиб кетиш (pickup_in_delivery) ёки қайтариш (return_in_delivery)
 *   agro       — сут қабули `agro_pickup_orders` (pickup_in_delivery)
 *   collection — йиғиб олиш `collection_tasks` (assigned | collecting)
 * Ресторан йўли (restaurant_orders.js) ЎЗГАРМАЙДИ; улгуржи — ҳозир эмас (6-қарор).
 *
 * ОҚИМ:
 *   1. Курьер `courierReportDeliveryFailed({module, id, reason})` — ҲОЛАТ ВА ПУЛ ЎЗГАРМАЙДИ:
 *      `awaitingCustomerConfirm{step:'delivery_failed', module, leg, failReason, escalateAt}` + муддат
 *      (`server_config/customer_confirm.failedTimeoutMin`, стандарт 15; 9-қарор). Нонда буюртма маршрут
 *      охирига сурилади (курьер кейинги манзилга ўтади; эски APK `isOrderFinalized`га боғлиқ эмас).
 *   2. Мижоз (`customerConfirmHandover`, МАЖБУРИЙ, модул босқичига боғлиқ эмас):
 *      'confirm' → якуний «етказилмади»; 'reject' («Олмоқчиман») → курьер давом этади.
 *   3. Муддат ўтса `escalateDeliveryFailed` (ҳар дақиқа) қарорни узатади: нон/бозор — `seller` роли
 *      (захира admin/superadmin), бошқалар — admin/superadmin (1, 2-қарор). Улар
 *      `resolveDeliveryFailed({module, id, decision:'failed'|'continue'})`.
 *   Биринчи қарор ютади: ҳаммаси битта ҳужжат транзакциясида, белги йўқолгач қолганлари — idempotent/рад.
 *
 * ЯКУНИЙ «ЕТКАЗИЛМАДИ»:
 *   order      — мавжуд бекор қилиш ядроси (`prepareOrderCancelInTx`/`commitOrderCancelInTx`): ҳамёндан
 *                ечилган `balanceApplied` ТЎЛИҚ қайтади (deliveryFee ҳам ичида; 3-қарор), `soldToday`
 *                тикланади (10-қарор). `status:'cancelled'`, `fulfillmentStatus:'delivery_failed'`.
 *                Маршрутдан чиқарилади (сервер; ресторандаги `detachFromRouteInTx` намунаси, индекс тузатилади).
 *                Товар сотувчига қайтади — фақат ҳодиса (8-қарор).
 *   carpet     — олиб кетиш → `pickup_ready` (навбатга; мавжуд release қирраси), қайтариш → `return_ready`
 *                (цехга; `returnFailedCount`+1). Бекор — алоҳида admin амали (5-қарор).
 *   agro       — `accepted` (навбатга; мавжуд release қирраси).
 *   collection — `failed`; `sell_submissions.inCollection = false` (админ янги вазифа яратади).
 *   Курьерга ҳақ ЙЎҚ (7-қарор). Мижоз сабаби customer_absent|customer_refused бўлса — фақат ҳисоблагич
 *   `customer_delivery_stats/{uid}` (4-қарор; чеклов йўқ).
 *
 * МАЙДОНЛАР (фақат сервер ёзади; rules: orders/carpet/agro/collection — клиент ёзуви ёпиқ):
 *   deliveryFailedDueAt        — мижоз жавоби муддати (жадвал бир майдонли оралиқ сўрови; эскалациядан кейин ўчади).
 *                                Ресторан `deliveryFailedEscalateAt`дан АТАЙЛАБ бошқа ном: ресторан жадвали
 *                                `orders`даги ресторан бўлмаган ҳужжатни «эскирган» деб тозалаб юборарди.
 *   deliveryFailedEscalatedAt  — қарор сотувчи/админга ўтган вақт
 *   deliveryFailedOpen: true   — қарор кутилмоқда (рўйхат учун тенглик сўрови; индекс керак эмас)
 *   deliveryFailedResolution   — { by: customer|seller|admin|superadmin, decision: failed|continue, at, actorId }
 * Тарих — `delivery_failed_events` (ўзгармас; rules'да match йўқ = клиентга ёпиқ), admin қарори — `admin_audit`.
 */
'use strict';

const i18n = require('./notif_i18n');
const { MARKER_FIELD, FLAG_FIELD, REJECTED_FIELD } = require('./customer_confirm');
const { FAIL_REASONS } = require('./restaurant_orders');
// «Менинг бизнесим» маҳсулот буюртмаси (эга 2026-11-03): ҳолатлар жадвали — ягона манба.
const bizStates = require('./business_order_states');

const STEP = 'delivery_failed';
/**
 * business — «Менинг бизнесим» буюртмаси (`orders`, type business; business_orders.js). Қарорни шу
 * буюртманинг сотувчиси (`sellerUid` = businesses.ownerId) ёки admin/superadmin қилади; товар сотувчига
 * қайтади (ҳодиса), пул ҳаракати йўқ (етказиш ҳақи фақат якунда ечилади, AVA улуши 0).
 */
const MODULES = Object.freeze(['order', 'carpet', 'agro', 'collection', 'business']);
const DECISIONS = Object.freeze(['failed', 'continue']);
const DUE_AT = 'deliveryFailedDueAt';
const ESCALATED_AT = 'deliveryFailedEscalatedAt';
const OPEN = 'deliveryFailedOpen';
const RESOLUTION = 'deliveryFailedResolution';
const EVENTS = 'delivery_failed_events';
const STATS = 'customer_delivery_stats';
const IDEMPOTENCY = 'wallet_idempotency';
const COURIER_LIVE = 'order_courier_live';
const ADMIN_AUDIT = 'admin_audit';
const ESCALATE_BATCH = 100;
const LIST_LIMIT = 100;
const NOTIFY_LIMIT = 50;
const STRIKE_REASONS = Object.freeze(['customer_absent', 'customer_refused']);
const ORDER_TYPES = Object.freeze(['', 'bread', 'platform']);
const ORDER_ACTIVE_FS = Object.freeze(['courier_picked', 'arrived']);
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);
/** Ким ҳал қилади (1, 2-қарор). */
const DECIDER_ROLES = Object.freeze({
  order: Object.freeze(['seller', ...ADMIN_ROLES]),
  carpet: ADMIN_ROLES,
  agro: ADMIN_ROLES,
  collection: ADMIN_ROLES,
  // + ҳужжатнинг ўз сотувчиси (`SPECS.business.sellerOf`), роли қандай бўлишидан қатъи назар.
  business: ADMIN_ROLES,
});

const msOf = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : null);
const str = (v, max) => String(v == null ? '' : v).trim().slice(0, max);
const tail4 = (v) => {
  const d = String(v || '').replace(/\D/g, '');
  return d.length >= 4 ? d.slice(-4) : '';
};

/**
 * Модул тавсифи (соф): ҳужжатнинг жорий ҳолатидан «етказилмади» мумкин бўлган бўлак (`leg`) ва курьер.
 * `leg` null — бу ҳолатда «етказилмади» йўқ.
 */
const SPECS = Object.freeze({
  order: Object.freeze({
    collection: 'orders',
    phoneField: 'userPhone',
    phoneOf: (od) => String(od.userPhone || od.phone || ''),
    // `orders` коллекцияси `business` билан умумий: бошқа модул ҳужжати «эскирган» деб тозаланмасин.
    owns: (od) => ORDER_TYPES.includes(String(od.type || '')),
    onRoute: true,
    legOf: (od) => (ORDER_TYPES.includes(String(od.type || ''))
      && String(od.status || '') === 'in_delivery'
      && ORDER_ACTIVE_FS.includes(String(od.fulfillmentStatus || '')) ? 'delivery' : null),
    courierOf: (od) => String(od.courierId || ''),
    arrivedOf: () => true, // нонда «олиб кетдим»дан кейин ҳам мумкин (курьер муаммоси)
  }),
  carpet: Object.freeze({
    collection: 'carpet_wash_orders',
    phoneField: 'customerPhone',
    phoneOf: (od) => String(od.customerPhone || ''),
    legOf: (od) => {
      const s = String(od.status || '');
      if (s === 'pickup_in_delivery') return 'pickup';
      if (s === 'return_in_delivery') return 'return';
      return null;
    },
    courierOf: (od, leg) => String((leg === 'return' ? od.returnCourierId : od.pickupCourierId) || ''),
    arrivedOf: (od, leg) => !!(leg === 'return' ? od.returnArrivedAt : od.pickupArrivedAt),
  }),
  agro: Object.freeze({
    collection: 'agro_pickup_orders',
    phoneField: 'customerPhone',
    phoneOf: (od) => String(od.customerPhone || ''),
    legOf: (od) => (String(od.status || '') === 'pickup_in_delivery' ? 'pickup' : null),
    courierOf: (od) => String(od.pickupCourierId || ''),
    arrivedOf: (od) => !!od.arrivedAt,
  }),
  collection: Object.freeze({
    collection: 'collection_tasks',
    phoneField: 'customerPhone',
    phoneOf: (od) => String(od.customerPhone || od.customerUid || ''),
    legOf: (od) => (['assigned', 'collecting'].includes(String(od.status || '')) ? 'pickup' : null),
    courierOf: (od) => String(od.courierId || ''),
    arrivedOf: (od) => !!od.arrivedAt,
  }),
  business: Object.freeze({
    collection: 'orders',
    phoneField: 'userPhone',
    phoneOf: (od) => String(od.userPhone || od.phone || ''),
    owns: (od) => bizStates.isBusinessOrder(od),
    onRoute: true,
    legOf: (od) => (bizStates.isBusinessOrder(od) && bizStates.IN_DELIVERY.includes(String(od.businessStatus || ''))
      ? 'delivery' : null),
    courierOf: (od) => String(od.courierId || ''),
    arrivedOf: () => true, // ресторандаги каби: олиб кетгандан кейин ҳам (курьер муаммоси)
    sellerOf: (od) => String(od.sellerUid || ''),
  }),
});

/** Ҳужжат шу модулникими (умумий коллекцияда бошқа модул ҳужжатига тегилмайди). `owns` йўқ — ҳаммаси. */
function ownsDoc(moduleKey, od) {
  const spec = SPECS[moduleKey];
  return !!spec && (!spec.owns || spec.owns(od || {}));
}

/** Белги шу модулнинг «етказилмади» сўрови ва ҳужжат ҳали ўша бўлакдами (соф). */
function isPending(moduleKey, od) {
  const spec = SPECS[moduleKey];
  const m = od && od[MARKER_FIELD];
  if (!spec || !m || m.step !== STEP || m.module !== moduleKey) return false;
  const leg = spec.legOf(od);
  return !!leg && leg === m.leg;
}

/** Қарор вақти келдими: эскалация бўлган ёки муддат ўтган (соф). */
function decisionDue(od, nowMs) {
  if (od[ESCALATED_AT] !== undefined && od[ESCALATED_AT] !== null) return true;
  const m = od[MARKER_FIELD] || {};
  const due = msOf(m.escalateAt);
  return due !== null && due <= nowMs;
}

/**
 * Маршрут ичида буюртмани суриш (соф). `mode`:
 *   'to_end' — жорий бекатдаги буюртма охирига (курьер кейинги манзилга ўтади);
 *   'remove' — буюртма чиқарилади; ундан олдинги бўлса `currentIndex` бир камаяди.
 * @returns {null | {orders, currentIndex, exhausted}} — ўзгариш йўқ бўлса null.
 */
function routeAfter(route, orderId, mode) {
  const orders = Array.isArray(route && route.orders) ? route.orders.map(String) : [];
  const cur = Number.isInteger(route && route.currentIndex) && route.currentIndex >= 0 ? route.currentIndex : 0;
  const idx = orders.indexOf(String(orderId));
  if (idx < 0) return null;
  if (mode === 'to_end') {
    if (idx !== cur || idx >= orders.length - 1) return null;
    const next = orders.filter((_, i) => i !== idx);
    next.push(orders[idx]);
    return { orders: next, currentIndex: cur, exhausted: false };
  }
  const next = orders.filter((_, i) => i !== idx);
  const currentIndex = idx < cur ? cur - 1 : cur;
  return { orders: next, currentIndex, exhausted: next.length <= currentIndex };
}

function attachDeliveryFailed(exportsObj, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, notifyUserInApp, customerConfirm,
    prepareOrderCancelInTx, commitOrderCancelInTx, carpetReleaseEdges, agroReleaseEdge,
  } = deps;
  const courierAuthOf = () => deps.courierAuth;
  const MODES = deps.COURIER_AUTH_MODES || { new: 'new', finish: 'finish' };
  const now = deps.now || (() => new Date());
  const HttpsError = functions.https.HttpsError;
  const FV = admin.firestore.FieldValue;
  const ts = () => FV.serverTimestamp();
  const del = () => FV.delete();
  const tsOf = (d) => admin.firestore.Timestamp.fromDate(d);
  const canon = (v) => canonicalUid(String(v == null ? '' : v));
  const fail = (status, code, extra = {}) => new HttpsError(status, code, { reason: code, code, ...extra });
  const log = (fields) => console.log(JSON.stringify({ module: 'delivery_failed', ...fields }));

  function requirePhoneUid(context) {
    if (!context || !context.auth) throw fail('unauthenticated', 'AUTH_REQUIRED');
    const uid = canon(callerPhone(context));
    if (!uid || uid.length < 12) throw fail('unauthenticated', 'PHONE_TOKEN_REQUIRED');
    return uid;
  }

  function parseRef(data) {
    const moduleKey = str(data && data.module, 32);
    const id = str(data && data.id, 128);
    if (!MODULES.includes(moduleKey) || !id || id.includes('/')) throw fail('invalid-argument', 'DF_ARGS_INVALID');
    return { moduleKey, id, ref: db.collection(SPECS[moduleKey].collection).doc(id) };
  }

  function addEvent(t, { moduleKey, id, kind, actor, actorId, reason = '', meta = {} }) {
    t.set(db.collection(EVENTS).doc(), {
      module: moduleKey, refId: id, kind, actor, actorId: actorId || null, reason, meta, at: ts(),
    });
  }

  /** Ҳамма «етказилмади» кутиш майдонларини ўчириш (белги ҳам). */
  function clearAll(od) {
    return {
      ...customerConfirm.clearPatch(od),
      ...(od[DUE_AT] !== undefined ? { [DUE_AT]: del() } : {}),
      ...(od[ESCALATED_AT] !== undefined ? { [ESCALATED_AT]: del() } : {}),
      ...(od[OPEN] !== undefined ? { [OPEN]: del() } : {}),
    };
  }

  async function routeRefOf(t, od, orderId) {
    const rid = str(od.deliveryRouteId, 128);
    if (!rid || rid.includes('/')) return null;
    const ref = db.collection('delivery_routes').doc(rid);
    const snap = await t.get(ref);
    if (!snap.exists) return null;
    const rd = snap.data() || {};
    if (!Array.isArray(rd.orders) || !rd.orders.map(String).includes(orderId)) return null;
    return { ref, rd };
  }

  // ═════════════════════════════════════════════════════════════════════
  // 1. КУРЬЕР
  // ═════════════════════════════════════════════════════════════════════
  exportsObj.courierReportDeliveryFailed = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    const { moduleKey, id, ref } = parseRef(data);
    const reason = str(data && data.reason, 32);
    if (!FAIL_REASONS.includes(reason)) throw fail('invalid-argument', 'DF_REASON_INVALID', { allowed: FAIL_REASONS });
    const spec = SPECS[moduleKey];
    // 'finish' — тўхтатилган курьер ҳам қўлидагини якунлай олади (courier_auth.js).
    const courierId = await courierAuthOf().resolve(uid, MODES.finish);
    if (spec.onRoute) await courierAuthOf().assertOrderOnActiveRoute(courierId, id);
    const timeoutMin = await customerConfirm.getFailedTimeoutMin();
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) throw fail('not-found', 'DF_NOT_FOUND');
      const od = snap.data() || {};
      const leg = spec.legOf(od);
      // Эгалик АВВАЛ (бегона курьер ҳолатни билмасин).
      if (spec.onRoute) {
        courierAuthOf().assertOrderActionable(od, courierId, 'courierReportDeliveryFailed', id);
      } else if (canon(spec.courierOf(od, leg || 'pickup')) !== courierId) {
        throw fail('permission-denied', 'DF_NOT_YOUR_TASK');
      }
      const m = od[MARKER_FIELD];
      if (m && m.step === STEP && m.module === moduleKey && isPending(moduleKey, od)) {
        return { created: false, od, escalateAtMs: msOf(m.escalateAt) };
      }
      if (!leg) throw fail('failed-precondition', 'DF_NOT_ACTIVE', { status: String(od.status || '') });
      if (!spec.arrivedOf(od, leg)) throw fail('failed-precondition', 'DF_ARRIVE_FIRST');
      let route = null;
      if (moduleKey === 'order') {
        const idem = await t.get(db.collection(IDEMPOTENCY).doc(`courier_submit_${id}`));
        if (idem.exists || String(od.paymentStatus || '') === 'payment_pending_confirm') {
          throw fail('failed-precondition', 'DF_PAYMENT_SUBMITTED');
        }
        route = await routeRefOf(t, od, id);
      }
      // ── ЁЗИШ ──
      const escalateAt = tsOf(new Date(now().getTime() + timeoutMin * 60 * 1000));
      // `requestInTx` эмас: ўша қадамдаги ЭСКИРГАН белги (бошқа бўлак) ҳам алмашсин. Бошқа қадам
      // (handover_*, finalize, received) кутилаётган бўлса — у «етказилмади» билан алмашади (ресторандаги каби).
      t.update(ref, {
        [DUE_AT]: escalateAt, [OPEN]: true, [ESCALATED_AT]: del(), [RESOLUTION]: del(),
        ...customerConfirm.markerPatch(STEP, courierId, { module: moduleKey, leg, failReason: reason, escalateAt }),
      });
      let moved = false;
      if (route) {
        const r = routeAfter(route.rd, id, 'to_end');
        if (r) {
          t.update(route.ref, { orders: r.orders, updatedAt: ts() });
          moved = true;
        }
      }
      addEvent(t, {
        moduleKey, id, kind: 'requested', actor: 'courier', actorId: courierId, reason,
        meta: { leg, timeoutMin, routeMovedToEnd: moved, replacedStep: m && m.step ? String(m.step) : null },
      });
      return { created: true, od, escalateAtMs: escalateAt.toMillis(), leg };
    });
    if (out.created) {
      await customerConfirm.afterRequest(moduleKey, id, STEP, out.od,
        { module: moduleKey, leg: out.leg, failReason: reason }, true);
    }
    log({ action: 'courierReportDeliveryFailed', moduleKey, id, userId: courierId.slice(-4), result: out.created ? 'requested' : 'idempotent', durationMs: Date.now() - t0 });
    return {
      ok: true, awaitingCustomer: true, step: STEP, escalateAtMs: out.escalateAtMs,
      ...(out.created ? {} : { idempotent: true }),
    };
  });

  // ═════════════════════════════════════════════════════════════════════
  // 2. ЯКУН ЯДРОСИ (мижоз тасдиғи ҳам, сотувчи/админ қарори ҳам ШУНИ ишлатади — 7-қоида)
  // ═════════════════════════════════════════════════════════════════════
  /** READ фазаси. `od` — шу транзакцияда ўқилган ҳужжат. */
  async function prepareFailInTx(t, moduleKey, ref, od) {
    const ctx = { moduleKey, ref, od, id: ref.id };
    if (moduleKey === 'order') {
      ctx.idemRef = db.collection(IDEMPOTENCY).doc(`delivery_failed_${moduleKey}_${ref.id}`);
      const idem = await t.get(ctx.idemRef);
      if (idem.exists) throw fail('failed-precondition', 'DF_ALREADY_FINAL');
      ctx.route = await routeRefOf(t, od, ref.id);
      try {
        ctx.cancel = await prepareOrderCancelInTx(t, ref, od);
      } catch (e) {
        // Ҳамён қайтадиган ҳисоб топилмади — пул жимгина йўқолмасин: якун РАД, белги ҚОЛАДИ
        // (failed-precondition эмас: мижоз йўли уни «ҳолат ўзгарди» деб белгини ўчириб юборарди).
        if (e && e.message === 'REFUND_ACCOUNT_NOT_FOUND') throw fail('unavailable', 'DF_REFUND_ACCOUNT_NOT_FOUND');
        throw e;
      }
    } else if (moduleKey === 'business') {
      ctx.idemRef = db.collection(IDEMPOTENCY).doc(`delivery_failed_${moduleKey}_${ref.id}`);
      const idem = await t.get(ctx.idemRef);
      if (idem.exists) throw fail('failed-precondition', 'DF_ALREADY_FINAL');
      ctx.route = await routeRefOf(t, od, ref.id);
    }
    return ctx;
  }

  /** WRITE фазаси. `by` — customer|seller|admin|superadmin. */
  function commitFailInTx(t, ctx, { by, actorId, confirmStep }) {
    const { moduleKey, ref, od, id } = ctx;
    const spec = SPECS[moduleKey];
    const marker = od[MARKER_FIELD] || {};
    const reason = FAIL_REASONS.includes(marker.failReason) ? marker.failReason : 'other';
    const leg = String(marker.leg || spec.legOf(od) || '');
    const courierId = String(marker.courierId || '');
    const customerUid = canon(spec.phoneOf(od));
    const resolution = { [RESOLUTION]: { by, decision: 'failed', at: ts(), actorId: actorId || null } };
    const trace = confirmStep ? customerConfirm.confirmedPatch(confirmStep, courierId) : {};
    const common = {
      ...clearAll(od), ...resolution, ...trace, failReason: reason, failedAt: ts(), updatedAt: ts(),
    };
    let refundAmount = 0;
    let toStatus;
    if (moduleKey === 'order') {
      toStatus = 'cancelled';
      refundAmount = commitOrderCancelInTx(t, ctx.cancel, {
        orderPatch: {
          ...common,
          status: 'cancelled',
          fulfillmentStatus: 'delivery_failed',
          cancelReason: `delivery_failed:${reason}`,
          cancelledAt: ts(),
          cancelledBy: actorId || '',
          statusUpdatedAt: ts(),
        },
        actorUid: actorId || 'system',
        actorRole: by,
        createdBy: 'deliveryFailed',
        reason: `delivery_failed:${reason}`,
      });
      // Курьернинг жонли нуқтаси — етказиш тугади (40-қоида; ресторандаги каби).
      t.delete(db.collection(COURIER_LIVE).doc(id));
      if (ctx.route) {
        const r = routeAfter(ctx.route.rd, id, 'remove');
        if (r) {
          const active = ['active', 'ready'].includes(String(ctx.route.rd.status || ''));
          t.update(ctx.route.ref, {
            orders: r.orders, currentIndex: r.currentIndex, updatedAt: ts(),
            ...(r.exhausted && active ? { status: 'completed', completedAt: ts(), completedReason: 'delivery_failed' } : {}),
          });
        }
      }
      t.set(ctx.idemRef, {
        type: 'deliveryFailed', result: { ok: true, module: moduleKey, id, refundAmount, by }, createdAt: ts(),
      });
      // Товар сотувчига қайтади — 1-босқичда фақат ҳодиса (8-қарор; custody, 15-қоида).
      addEvent(t, {
        moduleKey, id, kind: 'goods_return_to_seller', actor: 'system', actorId: null, reason,
        meta: { from: courierId, to: 'seller', orderType: String(od.type || 'bread') },
      });
    } else if (moduleKey === 'carpet') {
      const fromStatus = String(od.status || '');
      const edge = carpetReleaseEdges[fromStatus];
      if (!edge) throw fail('failed-precondition', 'DF_NOT_ACTIVE', { status: fromStatus });
      toStatus = edge.to;
      t.update(ref, {
        ...common,
        status: edge.to,
        [edge.courierField]: '',
        [edge.arrivedField]: del(),
        ...(leg === 'return' ? { returnFailedCount: FV.increment(1), lastReturnFailedAt: ts() } : { pickupFailedCount: FV.increment(1) }),
      });
      if (leg === 'return') {
        addEvent(t, {
          moduleKey, id, kind: 'goods_return_to_workshop', actor: 'system', actorId: null, reason,
          meta: { from: courierId, to: 'workshop' },
        });
      }
    } else if (moduleKey === 'business') {
      // Ҳолат жадвали — business_order_states.js (17-қоида); пул ҳаракати йўқ: етказиш ҳақи фақат
      // `delivered`да ечилади, AVA улуши 0. Вэкуп товар пули — AVA ledger'идан ташқари (ҳодиса).
      const from = String(od.businessStatus || '');
      const to = bizStates.BS.deliveryFailed;
      if (!bizStates.canTransition(from, to)) throw fail('failed-precondition', 'DF_NOT_ACTIVE', { status: from });
      toStatus = to;
      t.update(ref, {
        ...common,
        ...bizStates.statusFields(to),
        statusUpdatedAt: ts(),
        rejectReason: `delivery_failed:${reason}`,
      });
      t.delete(db.collection(COURIER_LIVE).doc(id));
      if (ctx.route) {
        const r = routeAfter(ctx.route.rd, id, 'remove');
        if (r) {
          const active = ['active', 'ready'].includes(String(ctx.route.rd.status || ''));
          t.update(ctx.route.ref, {
            orders: r.orders, currentIndex: r.currentIndex, updatedAt: ts(),
            ...(r.exhausted && active ? { status: 'completed', completedAt: ts(), completedReason: 'delivery_failed' } : {}),
          });
        }
      }
      t.set(ctx.idemRef, {
        type: 'deliveryFailed', result: { ok: true, module: moduleKey, id, refundAmount: 0, by }, createdAt: ts(),
      });
      // Буюртма тарихи (append-only) — бизнес буюртмасининг ўз ҳодисалари ҳам тўлиқ бўлсин (16-қоида).
      t.set(ref.collection('order_events').doc(), {
        from, to, actor: by, actorId: actorId || null, reason: `delivery_failed:${reason}`,
        meta: { courierId, viaCustomerConfirm: !!confirmStep, buyoutAmount: Number(od.buyoutAmount) || 0 },
        at: ts(),
      });
      addEvent(t, {
        moduleKey, id, kind: 'goods_return_to_seller', actor: 'system', actorId: null, reason,
        meta: { from: courierId, to: 'seller', orderType: bizStates.ORDER_TYPE, buyoutAmount: Number(od.buyoutAmount) || 0 },
      });
    } else if (moduleKey === 'agro') {
      toStatus = agroReleaseEdge.to;
      t.update(ref, {
        ...common,
        status: agroReleaseEdge.to,
        [agroReleaseEdge.courierField]: '',
        [agroReleaseEdge.arrivedField]: del(),
        pickupFailedCount: FV.increment(1),
      });
    } else {
      toStatus = 'failed';
      t.update(ref, { ...common, status: 'failed' });
      const submissionId = str(od.submissionId, 128);
      if (submissionId && !submissionId.includes('/')) {
        // Мавжуд `adminCreateCollectionTask` шу ариза бўйича янги вазифа очиши учун (боғлиқ вазифа `failed`).
        t.set(db.collection('sell_submissions').doc(submissionId), {
          inCollection: false, collectionFailedAt: ts(), collectionFailedTaskId: id, updatedAt: ts(),
        }, { merge: true });
      }
    }
    if (STRIKE_REASONS.includes(reason) && customerUid.length >= 12) {
      // 4-қарор: фақат ҳисоблагич, «фақат олдиндан тўлов» чеклови ЙЎҚ.
      t.set(db.collection(STATS).doc(customerUid), {
        failedStrikes: FV.increment(1), failedStrikesByModule: { [moduleKey]: FV.increment(1) },
        lastFailedStrikeAt: ts(), updatedAt: ts(),
      }, { merge: true });
    }
    addEvent(t, {
      moduleKey, id, kind: 'failed', actor: by, actorId, reason,
      meta: { leg, from: String(od.status || ''), to: toStatus, refundAmount, courierId, viaCustomerConfirm: !!confirmStep },
    });
    const sellerUid = spec.sellerOf ? canon(spec.sellerOf(od)) : '';
    return { moduleKey, id, refundAmount, toStatus, courierId, customerUid, leg, reason, by, sellerUid };
  }

  /** «Давом этсин» (мижоз рад этди ёки қарор қилувчи «давом» деди) — WRITE фазаси. Ҳолат ўзгармайди. */
  function continueInTx(t, moduleKey, ref, od, { by, actorId }) {
    const marker = od[MARKER_FIELD] || {};
    t.update(ref, {
      ...clearAll(od),
      ...(by === 'customer' ? { [`${REJECTED_FIELD}.${STEP}`]: { at: ts(), courierId: String(marker.courierId || '') } } : {}),
      [RESOLUTION]: { by, decision: 'continue', at: ts(), actorId: actorId || null },
      updatedAt: ts(),
    });
    addEvent(t, {
      moduleKey, id: ref.id, kind: 'continue', actor: by, actorId,
      reason: String(marker.failReason || ''), meta: { leg: String(marker.leg || ''), courierId: String(marker.courierId || '') },
    });
    return { moduleKey, id: ref.id, courierId: String(marker.courierId || ''), customerUid: canon(SPECS[moduleKey].phoneOf(od)), by };
  }

  // ── Хабарлар (3 тилда; ҳар қабул қилувчининг `appLang`и). Хато асосий оқимни тўхтатмайди. ──
  async function notifyKey(userId, key, params, extra) {
    try {
      const u = canon(userId);
      if (u.length < 12) return;
      const lang = await i18n.langOfPhone(db, u);
      const m = i18n.render(key, lang, params || {});
      await notifyUserInApp({
        userId: u, title: m.title, body: m.body, category: 'order', source: 'delivery_failed',
        dataType: 'delivery_failed', screen: extra.screen || 'orders',
        extraData: { module: extra.moduleKey, id: String(extra.id) },
      });
    } catch (e) {
      console.error(JSON.stringify({ module: 'delivery_failed', action: 'notify', key, result: 'failed', errorCode: 'DF_NOTIFY_FAILED', message: String((e && e.message) || e).slice(0, 160) }));
    }
  }

  const CUSTOMER_FINAL_KEY = Object.freeze({
    order: 'customer_delivery_failed_final',
    carpet_pickup: 'customer_pickup_failed_final',
    carpet_return: 'customer_carpet_return_failed_final',
    agro_pickup: 'customer_pickup_failed_final',
    collection_pickup: 'customer_collection_failed_final',
    business_delivery: 'customer_delivery_failed_final',
  });
  const groupThousands = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');

  async function afterFinal(r) {
    log({ action: 'delivery_failed_final', moduleKey: r.moduleKey, id: r.id, result: 'failed', by: r.by, refundAmount: r.refundAmount, toStatus: r.toStatus });
    if (r.courierId) await notifyKey(r.courierId, 'courier_delivery_failed_final', {}, { moduleKey: r.moduleKey, id: r.id, screen: 'courier' });
    // Бизнес буюртмаси: сотувчи товар қайтишини билсин (ўзи қарор қилган бўлса ҳам — ҳолат ёпилди).
    if (r.sellerUid && r.by !== 'seller') await notifyKey(r.sellerUid, 'restaurant_delivery_failed_final', {}, { moduleKey: r.moduleKey, id: r.id, screen: 'business_orders' });
    if (!r.customerUid) return;
    if (r.refundAmount > 0) {
      // Ҳамёнга пул қайтди — мижоз ўзи тасдиқлаган бўлса ҳам суммани билсин.
      await notifyKey(r.customerUid, 'customer_order_delivery_failed_refund', { amount: groupThousands(r.refundAmount) }, { moduleKey: r.moduleKey, id: r.id });
      return;
    }
    if (r.by === 'customer') return; // мижоз ўзи тасдиқлади — қайта хабар шарт эмас (ресторандаги каби)
    const key = r.moduleKey === 'order' ? CUSTOMER_FINAL_KEY.order : CUSTOMER_FINAL_KEY[`${r.moduleKey}_${r.leg}`];
    if (key) await notifyKey(r.customerUid, key, {}, { moduleKey: r.moduleKey, id: r.id });
  }

  async function afterContinue(r) {
    log({ action: 'delivery_failed_continue', moduleKey: r.moduleKey, id: r.id, result: 'continue', by: r.by });
    if (r.courierId) await notifyKey(r.courierId, 'courier_delivery_failed_continue', {}, { moduleKey: r.moduleKey, id: r.id, screen: 'courier' });
    if (r.by !== 'customer' && r.customerUid) await notifyKey(r.customerUid, 'customer_delivery_failed_continue', {}, { moduleKey: r.moduleKey, id: r.id });
  }

  // ═════════════════════════════════════════════════════════════════════
  // 3. МИЖОЗ (customer_confirm орқали; МАЖБУРИЙ, рад этиладиган қадам)
  // ═════════════════════════════════════════════════════════════════════
  const DESCRIBE_KEY = Object.freeze({
    order: 'confirm_order_delivery_failed',
    carpet_pickup: 'confirm_carpet_pickup_failed',
    carpet_return: 'confirm_carpet_return_failed',
    agro_pickup: 'confirm_agro_pickup_failed',
    collection_pickup: 'confirm_collection_failed',
    // Умумий матн (пул қайтиши ҳақида гап йўқ — бизнес буюртмасида олдиндан ечилган пул йўқ).
    business_delivery: 'confirm_restaurant_delivery_failed',
  });

  for (const moduleKey of MODULES) {
    const spec = SPECS[moduleKey];
    const stepHandler = {
      describe: (od, marker) => {
        // `afterRequest` ҳали ёзилмаган ҳужжат ва белгига ўхшаш маълумот билан чақиради.
        const m = { ...(od[MARKER_FIELD] || {}), ...(marker || {}) };
        if (m.module !== moduleKey) return null;
        const leg = spec.legOf(od);
        if (!leg || leg !== m.leg) return null;
        const key = moduleKey === 'order' ? DESCRIBE_KEY.order : DESCRIBE_KEY[`${moduleKey}_${leg}`];
        if (!key) return null;
        return {
          key,
          params: {},
          details: {
            failReason: FAIL_REASONS.includes(m.failReason) ? m.failReason : 'other',
            escalateAtMs: msOf(m.escalateAt),
            leg,
          },
        };
      },
      confirm: async (t, { ref, od, step, customerId }) => {
        if (!isPending(moduleKey, od)) throw fail('failed-precondition', 'DF_NOT_ACTIVE');
        const ctx = await prepareFailInTx(t, moduleKey, ref, od);
        const r = commitFailInTx(t, ctx, { by: 'customer', actorId: customerId, confirmStep: step });
        return { status: r.toStatus, after: () => afterFinal(r) };
      },
      reject: async (t, { ref, od, customerId }) => {
        if (!isPending(moduleKey, od)) throw fail('failed-precondition', 'DF_NOT_ACTIVE');
        const r = continueInTx(t, moduleKey, ref, od, { by: 'customer', actorId: customerId });
        return { status: String(od.status || ''), after: () => afterContinue(r) };
      },
    };
    if (moduleKey === 'order') {
      // Нон/бозор учун модулнинг асосий ядроси ҳам шу (бошқа қадам йўқ).
      customerConfirm.registerHandler('order', {
        collection: spec.collection,
        phoneField: spec.phoneField,
        customerPhoneOf: spec.phoneOf,
        statusOf: (od) => String(od.status || ''),
        ...stepHandler,
      });
    }
    customerConfirm.registerStepHandler(moduleKey, STEP, stepHandler);
  }

  // ═════════════════════════════════════════════════════════════════════
  // 4. СОТУВЧИ / АДМИН ҚАРОРИ
  // ═════════════════════════════════════════════════════════════════════
  async function callerRole(context) {
    if (!context || !context.auth) throw fail('unauthenticated', 'AUTH_REQUIRED');
    const uid = requirePhoneUid(context);
    const snap = await db.collection('users').doc(uid).get();
    return { uid, role: String(((snap.exists && snap.data()) || {}).role || 'user') };
  }

  exportsObj.resolveDeliveryFailed = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const { moduleKey, id, ref } = parseRef(data);
    const decision = str(data && data.decision, 16);
    if (!DECISIONS.includes(decision)) throw fail('invalid-argument', 'DF_ARGS_INVALID');
    // Ким: телефон токени; рухсат: `users/{uid}.role` (requireCallerRoles билан бир хил манба), модулга қараб.
    const { uid, role } = await callerRole(context);
    const roleOk = DECIDER_ROLES[moduleKey].includes(role);
    // Бизнес: роль бўлмаса — шу буюртманинг сотувчиси бўлиши шарт (транзакцияда, ҳужжатдан текширилади).
    const sellerOf = SPECS[moduleKey].sellerOf;
    if (!roleOk && !sellerOf) {
      log({ action: 'resolveDeliveryFailed', moduleKey, id, userId: uid.slice(-4), role, result: 'denied', errorCode: 'DF_NOT_ALLOWED' });
      throw fail('permission-denied', 'DF_NOT_ALLOWED');
    }
    const by = roleOk ? role : 'seller'; // seller | admin | superadmin
    let out;
    try {
      out = await db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        if (!snap.exists) throw fail('not-found', 'DF_NOT_FOUND');
        const od = snap.data() || {};
        // Эгалик АВВАЛ (бегона фойдаланувчи ҳолатни билмасин).
        if (!roleOk && (!ownsDoc(moduleKey, od) || canon(sellerOf(od)) !== uid)) {
          throw fail('permission-denied', 'DF_NOT_ALLOWED');
        }
        if (!isPending(moduleKey, od)) {
          const res = od[RESOLUTION];
          // Такрор: шу қарор аллақачон қабул қилинган.
          if (res && res.decision === decision) return { idempotent: true, status: String(od.status || '') };
          throw fail('failed-precondition', 'DF_NOT_AWAITING_DECISION', { status: String(od.status || '') });
        }
        if (!decisionDue(od, now().getTime())) {
          throw fail('failed-precondition', 'DECISION_NOT_YET', { escalateAtMs: msOf((od[MARKER_FIELD] || {}).escalateAt) });
        }
        const marker = od[MARKER_FIELD] || {};
        // Сотувчи ва админ қарори audit'га (41-қоида): пул қайтиши ва навбатга қайтишга таъсир қилади.
        const audit = (to) => t.set(db.collection(ADMIN_AUDIT).doc(), {
          kind: 'delivery_failed_decision', actor: uid, actorRole: role, target: `${SPECS[moduleKey].collection}/${id}`,
          from: String(od.status || ''), to, reason: decision,
          detail: { module: moduleKey, leg: String(marker.leg || ''), failReason: String(marker.failReason || '') },
          at: ts(),
        });
        if (decision === 'continue') {
          const r = continueInTx(t, moduleKey, ref, od, { by, actorId: uid });
          audit(String(od.status || ''));
          return { status: String(od.status || ''), continued: r };
        }
        const ctx = await prepareFailInTx(t, moduleKey, ref, od);
        const r = commitFailInTx(t, ctx, { by, actorId: uid, confirmStep: '' });
        audit(r.toStatus);
        return { status: r.toStatus, final: r };
      });
    } catch (e) {
      if (e instanceof HttpsError) {
        log({ action: 'resolveDeliveryFailed', moduleKey, id, userId: uid.slice(-4), result: 'denied', errorCode: (e.details && e.details.reason) || e.message, durationMs: Date.now() - t0 });
        throw e;
      }
      // Параллел қарор/тасдиқ: Admin SDK уринишлари тугаса — ҳужжатни қайта ўқиб аниқ жавоб (22, 25-қоида).
      const s = await ref.get();
      const od = s.exists ? (s.data() || {}) : {};
      const res = od[RESOLUTION];
      if (!isPending(moduleKey, od) && res && res.decision === decision) {
        out = { idempotent: true, status: String(od.status || '') };
      } else {
        log({ action: 'resolveDeliveryFailed', moduleKey, id, result: 'contention', errorCode: 'CONTENTION_RETRY', message: String((e && e.message) || e).slice(0, 120) });
        throw fail('aborted', 'CONTENTION_RETRY');
      }
    }
    if (out.final) await afterFinal(out.final);
    if (out.continued) await afterContinue(out.continued);
    log({ action: 'resolveDeliveryFailed', moduleKey, id, userId: uid.slice(-4), role, result: out.idempotent ? 'idempotent' : decision, durationMs: Date.now() - t0 });
    return { ok: true, status: out.status, decision, ...(out.idempotent ? { idempotent: true } : {}) };
  });

  /**
   * Қарор кутаётганлар рўйхати (сотувчи — фақат нон/бозор; админ — ҳаммаси). Фақат керакли майдонлар
   * (40-қоида: телефон — охирги 4 рақам). Мижоз ҳали жавоб бера оладиганлар ҳам кўринади (`canDecide: false`).
   */
  async function cleanupIfStale(moduleKey, ref) {
    await db.runTransaction(async (t) => {
      const s = await t.get(ref);
      if (!s.exists) return;
      const od = s.data() || {};
      if (!ownsDoc(moduleKey, od) || isPending(moduleKey, od) || od[OPEN] === undefined) return;
      t.update(ref, {
        [OPEN]: del(),
        ...(od[DUE_AT] !== undefined ? { [DUE_AT]: del() } : {}),
        ...(od[ESCALATED_AT] !== undefined ? { [ESCALATED_AT]: del() } : {}),
      });
    });
  }

  exportsObj.listDeliveryFailedPending = functions.https.onCall(async (data, context) => {
    const { uid, role } = await callerRole(context);
    // Бизнес модули — роли бўлмаса фақат объект эгасига (`businesses.ownerId`) ва фақат ЎЗ (sellerUid)
    // буюртмалари; объекти йўқ оддий фойдаланувчи аввалгидек DF_NOT_ALLOWED олади.
    const modules = MODULES.filter((m) => DECIDER_ROLES[m].includes(role));
    if (!modules.includes('business')) {
      const own = await db.collection('businesses').where('ownerId', '==', uid).limit(1).get();
      if (!own.empty) modules.push('business');
    }
    if (modules.length === 0) throw fail('permission-denied', 'DF_NOT_ALLOWED');
    const nowMs = now().getTime();
    const per = await Promise.all(modules.map(async (moduleKey) => {
      const spec = SPECS[moduleKey];
      const ownOnly = !DECIDER_ROLES[moduleKey].includes(role);
      // Фақат тенглик филтрлари — композит индекс керак эмас.
      let q = db.collection(spec.collection).where(OPEN, '==', true);
      if (ownOnly) q = q.where('sellerUid', '==', uid);
      const snap = await q.limit(LIST_LIMIT).get();
      const items = [];
      const stale = [];
      for (const doc of snap.docs) {
        const od = doc.data() || {};
        if (!ownsDoc(moduleKey, od)) continue; // умумий коллекция: бошқа модул ҳужжати
        if (ownOnly && canon(spec.sellerOf(od)) !== uid) continue;
        if (!isPending(moduleKey, od)) { stale.push(doc.ref); continue; }
        const m = od[MARKER_FIELD] || {};
        items.push({
          module: moduleKey,
          id: doc.id,
          leg: String(m.leg || ''),
          status: String(od.status || ''),
          failReason: FAIL_REASONS.includes(m.failReason) ? m.failReason : 'other',
          requestedAtMs: msOf(m.requestedAt),
          escalateAtMs: msOf(m.escalateAt),
          escalated: od[ESCALATED_AT] !== undefined && od[ESCALATED_AT] !== null,
          canDecide: decisionDue(od, nowMs),
          customerName: str(od.userName || od.customerName, 80),
          customerPhoneTail: tail4(spec.phoneOf(od)),
          address: str(od.address || od.pickupAddress, 200),
          total: (moduleKey === 'order' || moduleKey === 'business') && Number.isInteger(od.total) ? od.total : null,
          courierTail: tail4(m.courierId),
        });
      }
      // Эскирган белги (буюртма бошқа йўл билан ёпилган, масалан админ ҳолатни ўзгартирган, эскалациядан
      // кейин муддат майдони йўқ): рўйхат лимитини эгалламасин — транзакцияда қайта текшириб тозаланади.
      await Promise.all(stale.slice(0, 20).map((r) => cleanupIfStale(moduleKey, r).catch(() => null)));
      return items;
    }));
    const items = per.flat().sort((a, b) => (a.requestedAtMs || 0) - (b.requestedAtMs || 0));
    log({ action: 'listDeliveryFailedPending', userId: uid.slice(-4), role, result: 'ok', count: items.length });
    return { ok: true, items };
  });

  // ═════════════════════════════════════════════════════════════════════
  // 5. ЖАДВАЛ: муддат ўтди → қарор сотувчи/админга (ҳар дақиқа, бир майдонли оралиқ сўрови)
  // ═════════════════════════════════════════════════════════════════════
  async function escalateOne(moduleKey, ref, at) {
    return db.runTransaction(async (t) => {
      const s = await t.get(ref);
      if (!s.exists) return null;
      const od = s.data() || {};
      const due = msOf(od[DUE_AT]);
      if (due === null) return null;
      // Умумий коллекция (`orders`: order + business): бошқа модул ҳужжатини «эскирган» деб тозаламаймиз.
      if (!ownsDoc(moduleKey, od)) return null;
      if (!isPending(moduleKey, od)) {
        // Эскирган муддат (бошқа йўл билан якунланган/белги алмашган) — фақат кутиш майдонлари ўчади.
        t.update(ref, {
          [DUE_AT]: del(),
          ...(od[OPEN] !== undefined ? { [OPEN]: del() } : {}),
          ...(od[ESCALATED_AT] !== undefined ? { [ESCALATED_AT]: del() } : {}),
        });
        return { stale: true };
      }
      if (due > at.getTime()) return null;
      t.update(ref, { [DUE_AT]: del(), [ESCALATED_AT]: ts() });
      const m = od[MARKER_FIELD] || {};
      addEvent(t, {
        moduleKey, id: ref.id, kind: 'escalated', actor: 'system', actorId: null, reason: String(m.failReason || ''),
        meta: { leg: String(m.leg || ''), courierId: String(m.courierId || ''), to: SPECS[moduleKey].sellerOf ? 'seller' : DECIDER_ROLES[moduleKey].join('|') },
      });
      return { id: ref.id, sellerUid: SPECS[moduleKey].sellerOf ? canon(SPECS[moduleKey].sellerOf(od)) : '' };
    });
  }

  async function notifyDeciders(moduleKey, id, sellerUid) {
    try {
      // Бизнес: қарорни шу буюртманинг сотувчиси қилади (админлар рўйхатда кўради).
      if (SPECS[moduleKey].sellerOf) {
        if (sellerUid) await notifyKey(sellerUid, 'delivery_failed_decide', {}, { moduleKey, id, screen: 'business_orders' });
        return;
      }
      const snap = await db.collection('users').where('role', 'in', [...DECIDER_ROLES[moduleKey]]).limit(NOTIFY_LIMIT).get();
      await Promise.all(snap.docs.map((d) => notifyKey(d.id, 'delivery_failed_decide', {}, {
        moduleKey, id, screen: moduleKey === 'order' ? 'seller_pos' : 'admin',
      })));
    } catch (e) {
      console.error(JSON.stringify({ module: 'delivery_failed', action: 'notifyDeciders', moduleKey, id, result: 'failed', errorCode: 'DF_NOTIFY_FAILED', message: String((e && e.message) || e).slice(0, 160) }));
    }
  }

  async function escalateAll() {
    const at = now();
    const out = { scanned: 0, escalated: 0, stale: 0, failed: 0 };
    for (const moduleKey of MODULES) {
      const snap = await db.collection(SPECS[moduleKey].collection)
        .where(DUE_AT, '<=', tsOf(at))
        .limit(ESCALATE_BATCH)
        .get();
      out.scanned += snap.size;
      for (const doc of snap.docs) {
        try {
          const r = await escalateOne(moduleKey, doc.ref, at);
          if (!r) continue;
          if (r.stale) { out.stale += 1; continue; }
          out.escalated += 1;
          log({ action: 'delivery_failed_escalate', moduleKey, id: r.id, result: 'escalated' });
          await notifyDeciders(moduleKey, r.id, r.sellerUid);
        } catch (e) {
          out.failed += 1;
          console.error(JSON.stringify({ module: 'delivery_failed', action: 'delivery_failed_escalate', moduleKey, id: doc.id, result: 'failed', errorCode: 'DF_ESCALATE_FAILED', message: String((e && e.message) || e).slice(0, 160) }));
        }
      }
    }
    if (out.scanned) log({ action: 'delivery_failed_escalate_run', result: 'ok', ...out });
    return out;
  }

  exportsObj.escalateDeliveryFailed = functions.pubsub
    .schedule('every 1 minutes')
    .timeZone('Asia/Tashkent')
    .onRun(async () => escalateAll());

  return { escalateAll, SPECS, isPending };
}

module.exports = {
  attachDeliveryFailed,
  STEP, MODULES, DECISIONS, DECIDER_ROLES, DUE_AT, ESCALATED_AT, OPEN, RESOLUTION, EVENTS, STATS,
  SPECS, isPending, decisionDue, routeAfter,
};
