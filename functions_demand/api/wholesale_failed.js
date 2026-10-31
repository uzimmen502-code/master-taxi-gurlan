'use strict';

/**
 * ULGURJI — «ЕТКАЗИЛМАДИ» ХАРИДОР ТАСДИҒИ БИЛАН (ega qarori 2026-11-01: 2026-10-31 umumiy qoidalari
 * Ulgurji uchun ham; boshqa turlar — default codebase `functions/delivery_failed.js`).
 *
 * NEGA SHU YERDA (demand codebase), default `delivery_failed.js` da EMAS:
 *   rad etish natijasi = `wholesale_orders` holat o'tishi `in_delivery → refused` (holatlar jadvali
 *   FAQAT `core/wholesale_orders.js` da) + `writeRefusal` (`wholesale_card.js`). Pul (AVA ulushi
 *   sotuvchiga, chiqish jo'natmasini relay kalitlari bilan yopish, qaytish jo'natmasi haqi) — default
 *   triggerlari `status: refused` ga qarab ishlaydi, demand triggeri qaytish jo'natmasini ochadi. Default
 *   codebase'da shu o'tishni qayta yozish holat/rad mantiqini IKKI joyga bo'lardi (7-band). Shu sabab
 *   oqim (so'rov, xaridor javobi, muddat, sotuvchi/admin qarori) shu yerda, `delivery_failed.js` NAQSHI
 *   bilan (birinchi qaror yutadi, tranzaksiya, ro'yxat, sweeper), rad natijasi — mavjud `writeRefusal`.
 *
 *   markWholesaleBuyerRefused          oxirgi LEG kuryeri (posilka qo'lida), karta, to'lov `awaiting`:
 *                                       HOLAT/PUL O'ZGARMAYDI — `deliveryFailed` so'rovi + muddat
 *   respondWholesaleDeliveryFailed     xaridor: confirm → rad (mavjud natija) | reject («Олмоқчиман») → davom
 *   resolveWholesaleDeliveryFailed     muddat o'tgach: buyurtma SOTUVCHISI yoki qat'iy admin:
 *                                       failed → rad (mavjud natija) | deliver → davom; admin_audit
 *   listWholesaleDeliveryFailedPending qat'iy admin: ochiq so'rovlar (PII yo'q, faqat oxirgi 4 raqam)
 *   getWholesaleDeliveryFailedState    oxirgi LEG kuryeri: so'rov holati (kuryer buyurtmani o'qiy olmaydi)
 *   wholesaleDeliveryFailedSweeper     har daqiqa: muddat o'tdi → qaror sotuvchi/adminga (+ xabar)
 *
 * MAYDONLAR (`wholesale_orders/{id}`, faqat server — Rules: klient yozuvi yo'q):
 *   deliveryFailed       { seq, open, stage: awaiting_buyer|awaiting_decision, courierId, shipmentId, legId,
 *                          reasonCode, note, timeoutMin, requestedAt, escalateAt, escalatedAt,
 *                          resolution: null | {by, decision: failed|continue|superseded, at, actorId} }
 *   deliveryFailedOpen   true — ro'yxat (tenglik so'rovi, indeks kerak emas); yopilganda false
 *   deliveryFailedDueAt  muddat (sweeper bitta maydonli oraliq so'rovi); eskalatsiya/yopilishda null
 * Tarix — `wholesale_orders/{id}/history/{seq}` (o'zgarmas, mavjud), admin/sotuvchi qarori — `admin_audit`.
 *
 * TO'LOV USULLARI (core/wholesale_orders.js PAYMENT_METHODS): `card_on_delivery` — mavjud rad natijasi;
 * `wallet` — rad/qaytish PUL QOIDASI kodda YO'Q → so'rov ochilmaydi (`not_card_order`, avvalgidek),
 * ega savoli. Kuryerga «borib keldim» haqi va hisoblagich — mavjud `writeRefusal`/default qoidalari.
 */

const {
  callerIdFrom, sameUser, toCanonicalId,
} = require('../core/ids');
const L = require('../core/logistics');
const WO = require('../core/wholesale_orders');
const { assertStrictAdmin } = require('../analytics/access');
const notify = require('../notify/wholesale_notify');
const C = require('./wholesale_card');

const ORDERS = 'wholesale_orders';
const BUYER_STATS = 'wholesale_buyer_stats';
const ADMIN_AUDIT = 'admin_audit';
const CONFIG_DOC = ['server_config', 'customer_confirm'];

/** Kuryer sabablari — default `restaurant_orders.js` FAIL_REASONS bilan AYNAN bir xil (codebase'lar aro import yo'q). */
const REASONS = Object.freeze(['customer_absent', 'customer_refused', 'courier_problem', 'other']);
/** Xaridor hisoblagichi faqat shu sabablarda (ega 4-qarori, 2026-10-31: «faqat hisoblagich»). */
const STRIKE_REASONS = Object.freeze(['customer_absent', 'customer_refused']);
/** Eski APK (sabab kodi yo'q, «Харидор тўламади» tugmasi) — INFERRED: xaridor rad etdi. */
const LEGACY_REASON = 'customer_refused';
const STAGE = Object.freeze({ AWAITING_BUYER: 'awaiting_buyer', AWAITING_DECISION: 'awaiting_decision' });
const DECISION = Object.freeze({ FAILED: 'failed', CONTINUE: 'continue', SUPERSEDED: 'superseded' });
/** `customer_confirm.js` FAILED_TIMEOUT_MIN_* bilan bir xil (o'sha hujjatni o'qiymiz). */
const TIMEOUT_DEFAULT = 15;
const TIMEOUT_MIN = 1;
const TIMEOUT_MAX = 240;
const NOTE_MAX = 300;
const SWEEP_LIMIT = 100;
const LIST_LIMIT = 100;
const STALE_CLEAN_LIMIT = 20;

const isInt = (n) => typeof n === 'number' && Number.isInteger(n);
const tail4 = (v) => {
  const d = String(v || '').replace(/\D/g, '');
  return d.length >= 4 ? d.slice(-4) : '';
};

function fail(code, message, reason, extra) {
  const e = new Error(message);
  e.code = code;
  e.httpErrorCode = code;
  e.details = { reason: reason || code, ...(extra || {}) };
  return e;
}

function msOf(v) {
  if (v == null) return null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return null;
}

function log(action, fields) {
  console.log(JSON.stringify({ module: 'wholesale_failed', action, ...fields }));
}

function denied(action, orderId, e) {
  log(action, { result: 'denied', orderId, errorCode: (e && e.details && e.details.reason) || (e && e.code) || 'UNKNOWN' });
}

/** Butun son [1..240] — o'zi, aks holda 15 (customer_confirm.normalizeFailedTimeout bilan bir xil). */
function normalizeTimeout(v) {
  return isInt(v) && v >= TIMEOUT_MIN && v <= TIMEOUT_MAX ? v : TIMEOUT_DEFAULT;
}

async function readTimeoutMin(db) {
  try {
    const s = await db.collection(CONFIG_DOC[0]).doc(CONFIG_DOC[1]).get();
    return normalizeTimeout(s.exists ? (s.data() || {}).failedTimeoutMin : undefined);
  } catch (e) {
    console.error(JSON.stringify({ module: 'wholesale_failed', action: 'readTimeout', result: 'failed', errorCode: 'CONFIG_READ_FAILED' }));
    return TIMEOUT_DEFAULT;
  }
}

/** Sabab: yangi ilova `reasonCode` (+ ixtiyoriy matn `reason`), eski APK — faqat matn. */
function parseReason(data) {
  const d = data || {};
  const note = String(d.reason == null ? '' : d.reason).trim().slice(0, NOTE_MAX);
  const code = String(d.reasonCode == null ? '' : d.reasonCode).trim();
  if (code) {
    if (!REASONS.includes(code)) throw fail('invalid-argument', 'Sabab noto\'g\'ri', 'reason_invalid', { allowed: REASONS });
    return { reasonCode: code, note, legacy: false };
  }
  return { reasonCode: LEGACY_REASON, note, legacy: true };
}

/** So'rov ochiqmi (sof): belgi ochiq va buyurtma hali yetkazilmoqda. */
function isPending(o) {
  const df = (o || {}).deliveryFailed;
  return !!df && df.open === true && (o || {}).status === WO.STATUS.IN_DELIVERY;
}

/** Qaror vaqti keldimi (sof): eskalatsiya bo'lgan yoki muddat o'tgan. */
function decisionDue(o, nowMs) {
  const df = (o || {}).deliveryFailed || {};
  if (df.escalatedAt != null) return true;
  const due = msOf(df.escalateAt);
  return due != null && due <= nowMs;
}

/**
 * Kuryer tekshiruvi (sof, tranzaksiya ichida o'qilgan hujjatlar ustida) — eski
 * `markWholesaleBuyerRefused` bilan AYNAN bir xil tartib (19-band: avval «kim», keyin «ruxsat»).
 * @returns {{lastLeg: string}}
 */
function assertLastLegCourier(o, ship, orderId, shipmentId, callerId) {
  if (String((o.shipment || {}).shipmentId || '') !== shipmentId || ship.wholesaleOrderId !== orderId) {
    throw fail('permission-denied', 'Ruxsat yo\'q', 'not_last_leg_courier');
  }
  const legIds = Array.isArray(ship.legIds) ? ship.legIds : [];
  const lastLeg = legIds.length ? legIds[legIds.length - 1] : '';
  const assigned = lastLeg ? (ship.legAssignments || {})[lastLeg] : null;
  if (!assigned || !sameUser(assigned, callerId)) throw fail('permission-denied', 'Ruxsat yo\'q', 'not_last_leg_courier');
  return { lastLeg };
}

function parcelWith(ship, legId, courierId) {
  const cur = ship.currentCustodian || {};
  return ship.currentLegId === legId && cur.kind === L.CUSTODIAN_KIND.PROVIDER && sameUser(cur.id, courierId);
}

/**
 * Rad natijasiga hali yaroqlimi (sof): yetkazilmoqda, karta, to'lov `awaiting`, posilka o'sha kuryerda.
 * Aks holda so'rov eskirgan (xaridor chek yubordi / sotuvchi «Пул тушди» / yetkazildi / admin bekor qildi).
 */
function stillRefusable(o, ship) {
  const df = o.deliveryFailed || {};
  if (o.status !== WO.STATUS.IN_DELIVERY) return 'status_changed';
  if (WO.methodOf(o) !== WO.PAYMENT_METHOD.CARD) return 'not_card_order';
  if ((o.cardPayment || {}).status !== WO.CARD_PAYMENT.AWAITING) return 'card_payment_progressed';
  if (!parcelWith(ship || {}, df.legId, df.courierId)) return 'parcel_moved';
  return null;
}

function stateOf(o) {
  const df = (o || {}).deliveryFailed || null;
  if (!df) return { pending: false, stage: null, resolution: null };
  return {
    pending: isPending(o),
    seq: isInt(df.seq) ? df.seq : 0,
    stage: df.stage || null,
    reasonCode: REASONS.includes(df.reasonCode) ? df.reasonCode : 'other',
    escalateAtMs: msOf(df.escalateAt),
    escalated: df.escalatedAt != null,
    resolution: df.resolution ? { by: df.resolution.by || null, decision: df.resolution.decision || null } : null,
  };
}

const ACTOR_OF = Object.freeze({ buyer: WO.ACTOR.BUYER, seller: 'seller', admin: WO.ACTOR.ADMIN });

/** Belgini yopish (yozuv patch'i). */
function closePatch(by, decision, actorId, now) {
  return {
    'deliveryFailed.open': false,
    'deliveryFailed.resolution': { by, decision, at: now, actorId: actorId || null },
    deliveryFailedOpen: false,
    deliveryFailedDueAt: null,
    updatedAt: now,
  };
}

/**
 * Yakuniy «етказилмади» (WRITE fazasi; o'qishlar chaqiruvchida). Yaroqsiz bo'lsa — belgi yopiladi
 * (`superseded`), rad YO'Q. Yaroqli — MAVJUD `writeRefusal` (pul/qaytish triggerlari o'zgarmagan).
 * O'tish egasi — kuryer xabari (`ACTOR.COURIER: in_delivery → refused`, jadval o'zgarmagan);
 * kim tasdiqladi — tarix `actor` + `refusal.confirmedBy`.
 */
function finalizeInTx(tx, db, { ref, o, ship, statsSnap, by, actorId, now }) {
  const df = o.deliveryFailed || {};
  const why = stillRefusable(o, ship);
  if (why) {
    const seq = C.historyWrite(tx, ref, o, {
      from: o.status, to: o.status, event: 'delivery_failed_superseded', actor: ACTOR_OF[by] || by, actorId: actorId || null,
      meta: { deliveryFailedSeq: df.seq || null, why },
    }, now);
    tx.update(ref, { ...closePatch('system', DECISION.SUPERSEDED, null, now), historySeq: seq, 'deliveryFailed.supersededWhy': why });
    return { superseded: true, why };
  }
  WO.assertTransition(WO.ACTOR.COURIER, o.status, WO.STATUS.REFUSED);
  C.writeRefusal(tx, db, {
    ref,
    o,
    from: o.status,
    actor: ACTOR_OF[by] || by,
    actorId,
    via: 'courier',
    reason: df.note || df.reasonCode || '',
    shipmentId: df.shipmentId,
    legId: df.legId,
    statsSnap,
    now,
    refusalBy: df.courierId,
    countRefusal: STRIKE_REASONS.includes(df.reasonCode),
    refusalExtra: {
      reasonCode: df.reasonCode || null, confirmedBy: by, confirmedById: actorId || null, deliveryFailedSeq: df.seq || null,
    },
    metaExtra: { deliveryFailedSeq: df.seq || null, reportedBy: df.courierId || null, reasonCode: df.reasonCode || null, confirmedBy: by },
  });
  tx.update(ref, closePatch(by, DECISION.FAILED, actorId, now));
  return { superseded: false };
}

/** «Давом этсин» (xaridor «Олмоқчиман» yoki sotuvchi/admin «Етказилсин»). Holat va pul o'zgarmaydi. */
function continueInTx(tx, { ref, o, by, actorId, now }) {
  const df = o.deliveryFailed || {};
  const seq = C.historyWrite(tx, ref, o, {
    from: o.status, to: o.status, event: 'delivery_failed_continue', actor: ACTOR_OF[by] || by, actorId: actorId || null,
    meta: { deliveryFailedSeq: df.seq || null, reasonCode: df.reasonCode || null, courierId: df.courierId || null },
  }, now);
  tx.update(ref, { ...closePatch(by, DECISION.CONTINUE, actorId, now), historySeq: seq });
}

function paramsOf(o, orderId, timeoutMin) {
  return {
    orderId,
    product: String(o.productTitle || '').slice(0, 60),
    qty: o.qty,
    timeout: timeoutMin,
  };
}

/** Xabarlar — «best effort»: xato asosiy oqimni to'xtatmaydi. Har urinishga bitta (idSuffix `df{seq}`). */
async function send(deps, orderId, o, items) {
  const df = o.deliveryFailed || {};
  const idSuffix = `df${isInt(df.seq) ? df.seq : 0}`;
  const params = paramsOf(o, orderId, isInt(df.timeoutMin) ? df.timeoutMin : TIMEOUT_DEFAULT);
  for (const it of items) {
    try {
      if (it.to === 'admins') await notify.notifyAdmins(deps, { key: it.key, params, orderId, idSuffix });
      else await notify.notifyUser(deps, { uid: it.uid, key: it.key, params, orderId, idSuffix });
    } catch (e) {
      console.error(JSON.stringify({
        module: 'wholesale_failed', action: 'notify', result: 'failed', orderId, key: it.key, errorCode: 'NOTIFY_FAILED',
        message: String((e && e.message) || e).slice(0, 160),
      }));
    }
  }
}

async function readAfter(db, ref) {
  const s = await ref.get();
  return s.exists ? (s.data() || {}) : {};
}

// ═══════════════════════════════════════════════════════════════════════
// 1. KURYER: «етказилмади» (eski nom `markWholesaleBuyerRefused`)
// ═══════════════════════════════════════════════════════════════════════

function makeReportWholesaleDeliveryFailed(deps) {
  const { db, now: nowFn } = deps;
  return async function reportWholesaleDeliveryFailed(data, context) {
    const t0 = Date.now();
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const orderId = C.requireOrderId(data);
    const ref = db.collection(ORDERS).doc(orderId);
    try {
      const { reasonCode, note, legacy } = parseReason(data);
      const pre = await ref.get();
      if (!pre.exists) throw fail('not-found', 'Buyurtma topilmadi', 'order_not_found');
      const shipmentId = String(((pre.data() || {}).shipment || {}).shipmentId || '');
      if (!shipmentId) throw fail('permission-denied', 'Ruxsat yo\'q', 'not_last_leg_courier');
      const shipRef = db.collection(L.SHIPMENTS).doc(shipmentId);
      const timeoutMin = await readTimeoutMin(db);
      const now = nowFn ? nowFn() : new Date();
      const out = await db.runTransaction(async (tx) => {
        const [s, ss] = await Promise.all([tx.get(ref), tx.get(shipRef)]);
        const o = s.data() || {};
        const ship = ss.exists ? (ss.data() || {}) : {};
        const { lastLeg } = assertLastLegCourier(o, ship, orderId, shipmentId, callerId);
        // Eski (2026-11-01 gacha) darhol rad etilgan buyurtma — avvalgidek idempotent.
        if (o.status === WO.STATUS.REFUSED && sameUser((o.refusal || {}).by, callerId)) return { refused: true, o };
        if (isPending(o)) return { idempotent: true, o };
        if (WO.methodOf(o) !== WO.PAYMENT_METHOD.CARD) throw fail('failed-precondition', 'Buyurtma karta orqali emas', 'not_card_order');
        if (!parcelWith(ship, lastLeg, callerId)) throw fail('failed-precondition', 'Posilka sizda emas', 'parcel_not_in_hand');
        const cp = o.cardPayment || {};
        if (o.status === WO.STATUS.IN_DELIVERY) {
          if (cp.status === WO.CARD_PAYMENT.CONFIRMED) throw fail('failed-precondition', 'To\'lov tasdiqlangan', 'card_payment_confirmed');
          if (cp.status === WO.CARD_PAYMENT.RECEIPT_SUBMITTED) {
            throw fail('failed-precondition', 'Xaridor chek yuborgan — sotuvchi yoki admin hal qiladi', 'receipt_submitted');
          }
          if (cp.status !== WO.CARD_PAYMENT.AWAITING) throw fail('failed-precondition', 'To\'lov holati mos emas', 'card_payment_state');
        }
        // Keyingi qadam (tasdiqdan keyin) — kuryer o'tishi; boshqa holatda (nizo va h.k.) — so'rov ham yo'q.
        WO.assertTransition(WO.ACTOR.COURIER, o.status, WO.STATUS.REFUSED);
        const prev = o.deliveryFailed || {};
        const seqN = (isInt(prev.seq) ? prev.seq : 0) + 1;
        const escalateAt = new Date(now.getTime() + timeoutMin * 60 * 1000);
        const marker = {
          seq: seqN,
          open: true,
          stage: STAGE.AWAITING_BUYER,
          courierId: toCanonicalId(callerId) || callerId,
          shipmentId,
          legId: lastLeg,
          reasonCode,
          note,
          legacyClient: legacy,
          timeoutMin,
          requestedAt: now,
          escalateAt,
          escalatedAt: null,
          resolution: null,
        };
        const hseq = C.historyWrite(tx, ref, o, {
          from: o.status, to: o.status, event: 'delivery_failed_requested', actor: WO.ACTOR.COURIER, actorId: callerId, reason: note,
          meta: { deliveryFailedSeq: seqN, reasonCode, timeoutMin, shipmentId, legId: lastLeg, legacyClient: legacy },
        }, now);
        tx.update(ref, {
          deliveryFailed: marker,
          deliveryFailedOpen: true,
          deliveryFailedDueAt: escalateAt,
          historySeq: hseq,
          updatedAt: now,
        });
        return { created: true, o: { ...o, deliveryFailed: marker } };
      });
      if (out.refused) {
        log('report', { result: 'already_refused', orderId, shipmentId, durationMs: Date.now() - t0 });
        return { ok: true, orderId, status: WO.STATUS.REFUSED, idempotent: true };
      }
      if (out.created) {
        await send({ db, messaging: deps.messaging, now: nowFn }, orderId, out.o, [
          { uid: out.o.buyerId, key: 'ws_df_buyer_confirm' },
          { uid: callerId, key: 'ws_df_courier_wait' },
        ]);
      }
      const st = stateOf(out.o);
      log('report', {
        result: out.created ? 'requested' : 'idempotent', orderId, shipmentId, seq: st.seq, reasonCode: (out.o.deliveryFailed || {}).reasonCode, durationMs: Date.now() - t0,
      });
      return {
        ok: true,
        orderId,
        status: String(out.o.status || ''),
        awaitingBuyer: st.pending && st.stage === STAGE.AWAITING_BUYER,
        stage: st.stage,
        escalateAtMs: st.escalateAtMs,
        idempotent: !out.created,
      };
    } catch (e) {
      denied('report', orderId, e);
      throw e;
    }
  };
}

// ═══════════════════════════════════════════════════════════════════════
// 2. XARIDOR: tasdiq yoki «Олмоқчиман»
// ═══════════════════════════════════════════════════════════════════════

/** Yakun READ fazasi: jo'natma va xaridor hisoblagichi (tranzaksiyada, yozuvdan oldin). */
async function readFinalizeDeps(tx, db, o) {
  const df = o.deliveryFailed || {};
  const shipmentId = String(df.shipmentId || (o.shipment || {}).shipmentId || '');
  const ss = shipmentId ? await tx.get(db.collection(L.SHIPMENTS).doc(shipmentId)) : null;
  const statsSnap = await tx.get(db.collection(BUYER_STATS).doc(toCanonicalId(o.buyerId) || '_'));
  return { ship: ss && ss.exists ? (ss.data() || {}) : {}, statsSnap };
}

function makeRespondWholesaleDeliveryFailed(deps) {
  const { db, now: nowFn } = deps;
  return async function respondWholesaleDeliveryFailed(data, context) {
    const t0 = Date.now();
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const orderId = C.requireOrderId(data);
    const answer = String((data || {}).decision || '');
    if (!['confirm', 'reject'].includes(answer)) throw fail('invalid-argument', 'Javob: confirm yoki reject', 'decision_invalid');
    const decision = answer === 'confirm' ? DECISION.FAILED : DECISION.CONTINUE;
    const ref = db.collection(ORDERS).doc(orderId);
    try {
      const now = nowFn ? nowFn() : new Date();
      const out = await db.runTransaction(async (tx) => {
        const s = await tx.get(ref);
        if (!s.exists) throw fail('not-found', 'Buyurtma topilmadi', 'order_not_found');
        const o = s.data() || {};
        if (!sameUser(o.buyerId, callerId)) throw fail('permission-denied', 'Bu buyurtma sizniki emas', 'not_order_party');
        if (!isPending(o)) {
          const res = (o.deliveryFailed || {}).resolution;
          if (res && res.by === 'buyer' && res.decision === decision) return { idempotent: true, o };
          throw fail('failed-precondition', 'So\'rov allaqachon hal qilingan', 'df_not_pending', { resolution: (res && res.decision) || null });
        }
        if (decision === DECISION.CONTINUE) {
          continueInTx(tx, { ref, o, by: 'buyer', actorId: callerId, now });
          return { continued: true, o };
        }
        const { ship, statsSnap } = await readFinalizeDeps(tx, db, o);
        const r = finalizeInTx(tx, db, {
          ref, o, ship, statsSnap, by: 'buyer', actorId: callerId, now,
        });
        return { ...r, o };
      });
      const df = (out.o.deliveryFailed || {});
      if (out.superseded) {
        log('respond', { result: 'superseded', orderId, why: out.why, durationMs: Date.now() - t0 });
        throw fail('failed-precondition', 'Buyurtma holati o\'zgardi', 'df_state_changed', { why: out.why });
      }
      if (out.continued) {
        await send({ db, messaging: deps.messaging, now: nowFn }, orderId, out.o, [{ uid: df.courierId, key: 'ws_df_courier_continue' }]);
      }
      log('respond', { result: out.idempotent ? 'idempotent' : decision, orderId, seq: df.seq, durationMs: Date.now() - t0 });
      return {
        ok: true, orderId, decision, status: decision === DECISION.FAILED ? WO.STATUS.REFUSED : WO.STATUS.IN_DELIVERY, idempotent: !!out.idempotent,
      };
    } catch (e) {
      denied('respond', orderId, e);
      throw e;
    }
  };
}

// ═══════════════════════════════════════════════════════════════════════
// 3. SOTUVCHI / ADMIN QARORI (muddat o'tgach; birinchi qaror yutadi)
// ═══════════════════════════════════════════════════════════════════════

function makeResolveWholesaleDeliveryFailed(deps) {
  const { db, now: nowFn } = deps;
  return async function resolveWholesaleDeliveryFailed(data, context) {
    const t0 = Date.now();
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const orderId = C.requireOrderId(data);
    const raw = String((data || {}).decision || '');
    if (!['failed', 'deliver'].includes(raw)) throw fail('invalid-argument', 'Qaror: failed yoki deliver', 'decision_invalid');
    const decision = raw === 'failed' ? DECISION.FAILED : DECISION.CONTINUE;
    const ref = db.collection(ORDERS).doc(orderId);
    try {
      // Kim: shu buyurtma SOTUVCHISI (wholesale_orders.sellerId) — aks holda qat'iy admin (admin/superadmin).
      const pre = await ref.get();
      if (!pre.exists) throw fail('not-found', 'Buyurtma topilmadi', 'order_not_found');
      let by = 'seller';
      if (!sameUser((pre.data() || {}).sellerId, callerId)) {
        try {
          await assertStrictAdmin(db, context);
        } catch (e) {
          throw fail('permission-denied', 'Ruxsat yo\'q', 'not_decider');
        }
        by = 'admin';
      }
      const now = nowFn ? nowFn() : new Date();
      const out = await db.runTransaction(async (tx) => {
        const s = await tx.get(ref);
        const o = s.data() || {};
        if (by === 'seller' && !sameUser(o.sellerId, callerId)) throw fail('permission-denied', 'Ruxsat yo\'q', 'not_decider');
        if (!isPending(o)) {
          const res = (o.deliveryFailed || {}).resolution;
          if (res && res.decision === decision && res.by === by) return { idempotent: true, o };
          throw fail('failed-precondition', 'So\'rov allaqachon hal qilingan', 'df_not_pending', { resolution: (res && res.decision) || null });
        }
        if (!decisionDue(o, now.getTime())) {
          throw fail('failed-precondition', 'Xaridor javobi kutilmoqda', 'decision_not_yet', { escalateAtMs: msOf((o.deliveryFailed || {}).escalateAt) });
        }
        const df = o.deliveryFailed || {};
        let r;
        if (decision === DECISION.CONTINUE) {
          continueInTx(tx, { ref, o, by, actorId: callerId, now });
          r = { continued: true };
        } else {
          const { ship, statsSnap } = await readFinalizeDeps(tx, db, o);
          r = finalizeInTx(tx, db, {
            ref, o, ship, statsSnap, by, actorId: callerId, now,
          });
        }
        // 41-band: sotuvchi va admin qarori audit'ga (rad → pul oqimi ishga tushadi).
        tx.set(db.collection(ADMIN_AUDIT).doc(), {
          kind: 'wholesale_delivery_failed_decision',
          actor: callerId,
          actorRole: by,
          target: `${ORDERS}/${orderId}`,
          from: o.status,
          to: r.superseded || decision === DECISION.CONTINUE ? o.status : WO.STATUS.REFUSED,
          reason: r.superseded ? DECISION.SUPERSEDED : decision,
          detail: { deliveryFailedSeq: df.seq || null, reasonCode: df.reasonCode || null, why: r.why || null },
          at: now,
        });
        return { ...r, o };
      });
      const df = out.o.deliveryFailed || {};
      if (out.superseded) {
        log('resolve', { result: 'superseded', orderId, by, why: out.why, durationMs: Date.now() - t0 });
        throw fail('failed-precondition', 'Buyurtma holati o\'zgardi', 'df_state_changed', { why: out.why });
      }
      if (out.continued) {
        await send({ db, messaging: deps.messaging, now: nowFn }, orderId, out.o, [
          { uid: df.courierId, key: 'ws_df_courier_continue' },
          { uid: out.o.buyerId, key: 'ws_df_buyer_continue' },
        ]);
      }
      log('resolve', { result: out.idempotent ? 'idempotent' : decision, orderId, by, seq: df.seq, durationMs: Date.now() - t0 });
      return {
        ok: true, orderId, decision: raw, by, status: decision === DECISION.FAILED ? WO.STATUS.REFUSED : WO.STATUS.IN_DELIVERY, idempotent: !!out.idempotent,
      };
    } catch (e) {
      denied('resolve', orderId, e);
      throw e;
    }
  };
}

// ═══════════════════════════════════════════════════════════════════════
// 4. RO'YXAT (admin) va KURYER HOLATI
// ═══════════════════════════════════════════════════════════════════════

/** Eskirgan belgi (buyurtma boshqa yo'l bilan yetkazildi/bekor/rad) — tranzaksiyada qayta tekshirib yopiladi. */
async function cleanupStale(db, ref, nowFn) {
  await db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    if (!s.exists) return;
    const o = s.data() || {};
    if (isPending(o)) return;
    const df = o.deliveryFailed || {};
    const now = nowFn ? nowFn() : new Date();
    if (df.open === true) {
      tx.update(ref, { ...closePatch('system', DECISION.SUPERSEDED, null, now), 'deliveryFailed.supersededWhy': 'status_changed' });
    } else if (o.deliveryFailedOpen === true || o.deliveryFailedDueAt != null) {
      tx.update(ref, { deliveryFailedOpen: false, deliveryFailedDueAt: null });
    }
  });
}

function makeListWholesaleDeliveryFailedPending(deps) {
  const { db, now: nowFn } = deps;
  return async function listWholesaleDeliveryFailedPending(data, context) {
    const adminId = await assertStrictAdmin(db, context);
    const nowMs = (nowFn ? nowFn() : new Date()).getTime();
    const snap = await db.collection(ORDERS).where('deliveryFailedOpen', '==', true).limit(LIST_LIMIT).get();
    const items = [];
    const stale = [];
    for (const d of snap.docs) {
      const o = d.data() || {};
      if (!isPending(o)) { stale.push(d.ref); continue; }
      const df = o.deliveryFailed || {};
      items.push({
        orderId: d.id,
        productTitle: String(o.productTitle || '').slice(0, 80),
        qty: isInt(o.qty) ? o.qty : null,
        total: isInt(o.goodsTotal) && isInt(o.deliveryFee) ? o.goodsTotal + o.deliveryFee : null,
        stage: df.stage || null,
        reasonCode: REASONS.includes(df.reasonCode) ? df.reasonCode : 'other',
        requestedAtMs: msOf(df.requestedAt),
        escalateAtMs: msOf(df.escalateAt),
        escalated: df.escalatedAt != null,
        canDecide: decisionDue(o, nowMs),
        buyerTail: tail4(o.buyerId),
        sellerTail: tail4(o.sellerId),
        courierTail: tail4(df.courierId),
      });
    }
    await Promise.all(stale.slice(0, STALE_CLEAN_LIMIT).map((r) => cleanupStale(db, r, nowFn).catch(() => null)));
    items.sort((a, b) => (a.requestedAtMs || 0) - (b.requestedAtMs || 0));
    log('list', { result: 'ok', userId: tail4(adminId), count: items.length, stale: stale.length });
    return { ok: true, items };
  };
}

function makeGetWholesaleDeliveryFailedState(deps) {
  const { db } = deps;
  return async function getWholesaleDeliveryFailedState(data, context) {
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const orderId = C.requireOrderId(data);
    try {
      const s = await db.collection(ORDERS).doc(orderId).get();
      if (!s.exists) throw fail('not-found', 'Buyurtma topilmadi', 'order_not_found');
      const o = s.data() || {};
      const shipmentId = String((o.shipment || {}).shipmentId || '');
      if (!shipmentId) throw fail('permission-denied', 'Ruxsat yo\'q', 'not_last_leg_courier');
      const ss = await db.collection(L.SHIPMENTS).doc(shipmentId).get();
      assertLastLegCourier(o, ss.exists ? (ss.data() || {}) : {}, orderId, shipmentId, callerId);
      return { ok: true, orderId, status: String(o.status || ''), ...stateOf(o) };
    } catch (e) {
      denied('getState', orderId, e);
      throw e;
    }
  };
}

// ═══════════════════════════════════════════════════════════════════════
// 5. SWEEPER: muddat o'tdi → qaror sotuvchi/adminga
// ═══════════════════════════════════════════════════════════════════════

async function runWholesaleDeliveryFailedSweep(deps, { limit = SWEEP_LIMIT } = {}) {
  const { db, now: nowFn } = deps;
  const now = nowFn ? nowFn() : new Date();
  const out = { scanned: 0, escalated: 0, stale: 0, young: 0, failed: 0 };
  const snap = await db.collection(ORDERS).where('deliveryFailedDueAt', '<=', now).limit(limit).get();
  out.scanned = snap.size;
  for (const d of snap.docs) {
    try {
      const r = await db.runTransaction(async (tx) => {
        const s = await tx.get(d.ref);
        if (!s.exists) return null;
        const o = s.data() || {};
        const due = msOf(o.deliveryFailedDueAt);
        if (due == null) return null;
        if (!isPending(o)) {
          const df = o.deliveryFailed || {};
          tx.update(d.ref, df.open === true
            ? { ...closePatch('system', DECISION.SUPERSEDED, null, now), 'deliveryFailed.supersededWhy': 'status_changed' }
            : { deliveryFailedDueAt: null, deliveryFailedOpen: false });
          return { stale: true };
        }
        if (due > now.getTime()) return { young: true };
        const df = o.deliveryFailed || {};
        const seq = C.historyWrite(tx, d.ref, o, {
          from: o.status, to: o.status, event: 'delivery_failed_escalated', actor: WO.ACTOR.SYSTEM, actorId: null,
          meta: { deliveryFailedSeq: df.seq || null, to: 'seller|admin' },
        }, now);
        tx.update(d.ref, {
          deliveryFailedDueAt: null,
          'deliveryFailed.stage': STAGE.AWAITING_DECISION,
          'deliveryFailed.escalatedAt': now,
          historySeq: seq,
          updatedAt: now,
        });
        return { escalated: true, o };
      });
      if (!r) continue;
      if (r.stale) { out.stale += 1; continue; }
      if (r.young) { out.young += 1; continue; }
      out.escalated += 1;
      await send({ db, messaging: deps.messaging, now: nowFn }, d.id, r.o, [
        { uid: r.o.sellerId, key: 'ws_df_decide_seller' },
        { to: 'admins', key: 'ws_df_decide_admin' },
      ]);
    } catch (e) {
      out.failed += 1;
      console.error(JSON.stringify({
        module: 'wholesale_failed', action: 'sweep', result: 'failed', orderId: d.id, errorCode: 'DF_SWEEP_FAILED',
        message: String((e && e.message) || e).slice(0, 160),
      }));
    }
  }
  if (out.scanned) log('sweep', { result: 'ok', ...out });
  return out;
}

module.exports = {
  REASONS,
  STRIKE_REASONS,
  LEGACY_REASON,
  STAGE,
  DECISION,
  TIMEOUT_DEFAULT,
  normalizeTimeout,
  parseReason,
  isPending,
  decisionDue,
  stillRefusable,
  stateOf,
  makeReportWholesaleDeliveryFailed,
  makeRespondWholesaleDeliveryFailed,
  makeResolveWholesaleDeliveryFailed,
  makeListWholesaleDeliveryFailedPending,
  makeGetWholesaleDeliveryFailedState,
  runWholesaleDeliveryFailedSweep,
};
