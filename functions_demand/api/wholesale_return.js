'use strict';

/**
 * ULGURJI — RAD ETILGAN KARTA BUYURTMASINING QAYTISH JO'NATMASI (3b, ega 2026-10-31).
 *
 * Buyurtma `refused` bo'lishi bilan (kuryer yoki admin `reject`) demand triggeri
 * (`onWholesaleOrderUpdated`) va reconcile shu yerdagi `ensureWholesaleReturnShipment` ni
 * chaqiradi:
 *   origin      = xaridor manzili (`order.destination`) — posilka hozir shu yerda, kuryer qo'lida;
 *   destination = sotuvchi jo'natish manzili (`order.origin`);
 *   ownerId = recipientId = sotuvchi (to'lovchi ham sotuvchi — default codebase uning
 *   hamyonidan `wholesaleReturnHold` / `wholesaleReturnFund`);
 *   narx = rad etilgan paytdagi FAOL tarif (muhrlanadi: `priceSnapshot.tariffVersion`),
 *   posilka — asl buyurtmaning vazni/o'lchami, e'lon qilingan qiymat = tovar summasi.
 *
 * NEGA `createShipmentInternal` EMAS: u `recipientId === ownerId` ni (to'g'ri) rad etadi,
 * qaytishda esa sotuvchi ikkalasi. Relay fayliga (`api/logistics.js`) tegilmaydi (jonli
 * relay lineage'dan farq qiladi) — shuning uchun jo'natma YOZUVLARI shu yerda, relay
 * eksport qilgan `buildRoute` / `buildLegDemand` / `quoteParcelForPoints` / `validateParcel`
 * ustida. Shakl `addShipmentWrites` bilan bir xil — PARITET TESTI qulflaydi
 * (test/wholesale_card.test.js «qaytish jo'natmasi shakli»).
 *
 * LEG-1 = posilkani USHLAB TURGAN kuryer (asl jo'natmaning `currentCustodian`, provider):
 * LEG `accepted` holatda, unga biriktirilgan holda yoziladi (match hujjati bilan — ijrochi
 * inbox'ida ko'rinadi). Relay `onShipmentFunded` → `activateLeg` faqat `draft` LEG'ni ochadi —
 * biriktirilgan LEG'ga matching ishlamaydi (boshqa kuryerga taklif ketmaydi). Custodian
 * provider bo'lmasa — LEG `draft`, to'langach odatdagi matching. Kuryer LEG-1 ni relay
 * `scanHandover` bilan oladi (kod — `getWholesaleReturnHandoverCode`), sotuvchiga relay
 * `confirmDelivery` bilan topshiradi (yetkazish kodi — sotuvchida, relay `getShipmentSecrets`).
 */

const { toCanonicalId } = require('../core/ids');
const { getModuleConfig } = require('../core/config');
const { getAdapter } = require('../core/registry');
const sm = require('../core/state_machine');
const L = require('../core/logistics');
const WO = require('../core/wholesale_orders');
const {
  quoteParcelForPoints, buildRoute, buildLegDemand, validateParcel, CONFIG_REGION,
} = require('./logistics');

const ORDERS = 'wholesale_orders';
const HISTORY = 'history';
const DEMANDS = 'demands';
const MATCHES = 'demand_matches';
const IDEMPOTENCY = 'demand_idempotency';
const RETURN_SOURCE = 'wholesale_return';
const RETURN_MAX_ATTEMPTS = 5;

function fail(code, message, reason, extra) {
  const e = new Error(message);
  e.code = code;
  e.httpErrorCode = code;
  e.details = { reason: reason || code, ...(extra || {}) };
  return e;
}

const isInt = (n) => typeof n === 'number' && Number.isInteger(n);
const isPosInt = (n) => isInt(n) && n > 0;

function log(action, fields) {
  console.log(JSON.stringify({ module: 'wholesale_orders', action, ...fields }));
}

const returnIdemKey = (orderId) => `wholesale_return_${orderId}`;

/** Kunlik tracking hisoblagichi — relay `reserveTrackingSeq` bilan AYNI hujjat va qoida (eksport qilinmagan). */
async function reserveTrackingSeq(db, now) {
  const ref = db.collection(L.COUNTERS).doc(L.trackingDayKey(now));
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const cur = snap.exists ? Number((snap.data() || {}).seq) || 0 : 0;
    tx.set(ref, { seq: cur + 1, updatedAt: now }, { merge: true });
    return cur + 1;
  });
}

/** Buyurtmadagi asl posilka → qaytish posilkasi (vazn/o'lcham/qiymat o'sha). */
function returnParcelFromOrder(o) {
  const d = o.delivery && typeof o.delivery === 'object' ? o.delivery : {};
  if (!isPosInt(d.actualWeightG)) throw fail('failed-precondition', 'Vazn yo\'q', 'parcel_weight_missing');
  if (!isPosInt(o.goodsTotal)) throw fail('failed-precondition', 'Tovar summasi yo\'q', 'goods_total_invalid');
  const dims = d.dims && typeof d.dims === 'object' ? d.dims : null;
  const title = String(o.productTitle || '').trim();
  const pack = String(o.packLabel || '').trim();
  return {
    actualWeightG: d.actualWeightG,
    lengthCm: dims ? dims.l : null,
    widthCm: dims ? dims.w : null,
    heightCm: dims ? dims.h : null,
    declaredValue: o.goodsTotal,
    description: `Qaytarish: ${title}${pack ? ` (${pack})` : ''} × ${o.qty}`.slice(0, 200),
    fragile: false,
  };
}

/**
 * Qaytish jo'natmasi + ORDER + sirlar + ichki ulush + reja + LEG (+ biriktirish) — BITTA batch,
 * idempotent (`demand_idempotency/wholesale_return_{orderId}` create).
 * @returns {{orderId, shipmentId, legId, trackingNumber, fee, tariffVersion, courierId, duplicate}}
 */
async function createReturnShipment(deps, orderId, o, courierIdRaw) {
  const { db, now: nowFn } = deps;
  const now = nowFn ? nowFn() : new Date();
  const idemRef = db.collection(IDEMPOTENCY).doc(returnIdemKey(orderId));
  const fromIdem = async (d) => {
    const shipmentId = (d.shipmentIds || [])[0] || null;
    const s = shipmentId ? await db.collection(L.SHIPMENTS).doc(shipmentId).get() : null;
    const ship = s && s.exists ? (s.data() || {}) : {};
    const snap = ship.priceSnapshot || {};
    const legId = (ship.legIds || [])[0] || null;
    return {
      orderId: d.orderId,
      shipmentId,
      legId,
      trackingNumber: (d.trackingNumbers || [])[0] || null,
      fee: snap.customerPrice,
      tariffVersion: snap.tariffVersion,
      courierId: legId ? ((ship.legAssignments || {})[legId] || null) : null,
      duplicate: true,
    };
  };
  const idem = await idemRef.get();
  if (idem.exists) return fromIdem(idem.data() || {});

  const sellerId = toCanonicalId(o.sellerId || '');
  if (!sellerId) throw fail('failed-precondition', 'Sotuvchi', 'seller_required');
  const courierId = courierIdRaw ? toCanonicalId(courierIdRaw) : '';
  if (courierId && courierId === sellerId) throw fail('failed-precondition', 'Kuryer = sotuvchi', 'courier_is_seller');
  const parcel = validateParcel(returnParcelFromOrder(o), 0, { dimsOptional: true });
  const quoteParcel = {
    actualWeightG: parcel.actualWeightG,
    ...(parcel.lengthCm ? { lengthCm: parcel.lengthCm, widthCm: parcel.widthCm, heightCm: parcel.heightCm } : {}),
    declaredValue: parcel.declaredValue,
  };
  // Narx — HOZIRGI faol tarif (rad etilgan payt), nuqtalar relay `validatePoint` dan.
  const rq = await quoteParcelForPoints(db, o.destination, o.origin, quoteParcel, { dimsOptional: true });
  const snap = rq.quote;
  if (!isPosInt(snap.customerPrice) || !isPosInt(snap.tariffVersion)) {
    throw fail('failed-precondition', 'Qaytish narxi hisoblanmadi', 'return_price_invalid');
  }
  const tariff = rq.tariff;
  const adapter = getAdapter(L.MODULE);
  if (!adapter) throw fail('unimplemented', 'logistics adapteri ulanmagan');
  const config = await getModuleConfig(db, L.MODULE, CONFIG_REGION);
  const ttl = Number((config.logistics || {}).legTtlMinutes) || 3 * 24 * 60;

  const seq = await reserveTrackingSeq(db, now);
  const trackingNumber = L.formatTrackingNumber(now, seq);
  const orderRef = db.collection(L.ORDERS).doc();
  const order = { id: orderRef.id, ownerId: sellerId, termsAcceptedAt: null };
  const shipmentRef = db.collection(L.SHIPMENTS).doc();
  const legRef = db.collection(DEMANDS).doc();
  const priceSnapshot = { ...snap, calculatedAt: now };
  const outboundShipmentId = String((o.shipment || {}).shipmentId || '') || null;

  // ── addShipmentWrites bilan AYNI shakl (paritet testi) + qaytish maydonlari ──
  const shipment = {
    orderId: order.id,
    ownerId: sellerId,
    trackingNumber,
    status: L.SHIPMENT_STATUS.AWAITING_PAYMENT,
    paymentStatus: L.PAYMENT_STATUS.PENDING,
    origin: rq.origin,
    destination: rq.destination,
    recipientName: '',
    parcel,
    priceSnapshot,
    currentCustodian: { kind: L.CUSTODIAN_KIND.SENDER, id: sellerId, since: now },
    currentLegId: null,
    routePlanVersion: 1,
    legIds: [legRef.id],
    legCount: 1,
    assignedProviderIds: courierId ? [courierId] : [],
    custodyCount: 0,
    createdAt: now,
    updatedAt: now,
    recipientId: sellerId,
    source: RETURN_SOURCE,
    wholesaleOrderId: orderId,
    wholesaleReturn: true,
    outboundShipmentId,
    ...(courierId ? { legAssignments: { [legRef.id]: courierId } } : {}),
  };
  const route = buildRoute({
    tariff, shipment, version: 1, points: [{ from: rq.origin, to: rq.destination }],
  });
  const leg = buildLegDemand({
    ownerId: sellerId, order, shipment, shipmentId: shipmentRef.id, leg: route.legs[0],
    legIndex: 0, legCount: 1, legIds: [legRef.id], adapter, now, ttlMinutes: ttl,
  });
  leg.attributes.wholesaleReturn = true;
  if (courierId) {
    // Posilka qo'lidagi kuryerga biriktirilgan (relay `acceptLeg` yozadigan maydonlar bilan bir xil).
    leg.status = sm.STATUS.ACCEPTED;
    leg.assignment = { providerId: courierId, offerId: null, acceptedAt: now };
    leg.preassigned = { by: 'system', reason: RETURN_SOURCE, at: now };
  }

  const batch = db.batch();
  batch.set(shipmentRef, shipment);
  batch.set(shipmentRef.collection('private').doc('secrets'), { qrSecret: L.newQrSecret(), createdAt: now });
  batch.set(shipmentRef.collection('private').doc('internal'), {
    platformShare: route.split.platformShare,
    providerPool: route.split.providerPool,
    legPayouts: route.split.legPayouts,
    tariffVersion: tariff.version,
    updatedAt: now,
  });
  batch.set(db.collection(L.ROUTE_PLANS).doc(shipmentRef.id), { shipmentId: shipmentRef.id, currentVersion: 1, updatedAt: now });
  batch.set(db.collection(L.ROUTE_PLANS).doc(shipmentRef.id).collection('versions').doc('1'), {
    version: 1,
    legs: route.legs.map((l) => ({ ...l, legId: legRef.id })),
    reason: 'initial',
    createdBy: 'system',
    createdAt: now,
    supersededAt: null,
  });
  batch.set(legRef, leg);
  batch.set(legRef.collection('private').doc('stats'), {
    matchedCount: courierId ? 1 : 0, candidateCount: courierId ? 1 : 0, rejectedCount: 0, updatedAt: now,
  });
  if (courierId) {
    const loc = leg.location || {};
    batch.set(db.collection(MATCHES).doc(`${legRef.id}_${courierId}`), {
      demandId: legRef.id,
      providerId: courierId,
      module: leg.module,
      mode: leg.mode,
      status: 'accepted',
      score: 1,
      rank: 1,
      sources: [RETURN_SOURCE],
      consentGiven: true,
      metrics: {},
      projection: adapter.buildProjection({ id: legRef.id, ...leg }, config),
      expiresAt: (leg.timeWindow || {}).expiresAt || null,
      createdAt: now,
      acceptedAt: now,
      contactUnlocked: {
        stage: 1,
        ownerPhone: sellerId,
        pickupAddress: loc.addressText || '',
        pickupLat: loc.lat == null ? null : loc.lat,
        pickupLng: loc.lng == null ? null : loc.lng,
        handoverFromKind: (leg.attributes || {}).handoverFromKind || null,
      },
    });
  }
  batch.set(orderRef, {
    ownerId: sellerId,
    status: L.deriveOrderStatus([L.SHIPMENT_STATUS.AWAITING_PAYMENT]),
    shipmentIds: [shipmentRef.id],
    trackingNumbers: [trackingNumber],
    origin: rq.origin,
    destination: rq.destination,
    recipient: { name: '', phone: sellerId },
    recipientId: sellerId,
    source: RETURN_SOURCE,
    wholesaleOrderId: orderId,
    wholesaleReturn: true,
    note: '',
    customerPriceTotal: snap.customerPrice,
    currency: 'UZS',
    tariffVersion: snap.tariffVersion,
    consolidation: { count: 1, discountApplied: false, tariffVersion: snap.tariffVersion },
    termsAcceptedAt: null,
    createdAt: now,
    updatedAt: now,
  });
  batch.create(idemRef, {
    ownerId: sellerId, kind: 'internal_shipment', source: RETURN_SOURCE, orderId: orderRef.id,
    shipmentIds: [shipmentRef.id], trackingNumbers: [trackingNumber], createdAt: now,
  });
  try {
    await batch.commit();
  } catch (e) {
    if (e && (e.code === 6 || e.code === 'already-exists')) {
      const won = await idemRef.get();
      if (won.exists) return fromIdem(won.data() || {});
    }
    throw e;
  }
  return {
    orderId: orderRef.id,
    shipmentId: shipmentRef.id,
    legId: legRef.id,
    trackingNumber,
    fee: snap.customerPrice,
    tariffVersion: snap.tariffVersion,
    courierId: courierId || null,
    duplicate: false,
  };
}

/**
 * `refused` buyurtma uchun qaytish jo'natmasi (bor bo'lsa — o'sha) + buyurtmaga bog'lash
 * (`order.returnShipment`, `returnStatus: awaiting_payment`, history). Idempotent.
 * Xato: `order.returnShipmentError = {code, at, attempts, final}` (PII yo'q), reconcile qayta urinadi.
 */
async function ensureWholesaleReturnShipment(deps, orderId) {
  const { db, now: nowFn } = deps;
  const started = Date.now();
  const ref = db.collection(ORDERS).doc(orderId);
  const s0 = await ref.get();
  if (!s0.exists) return { skipped: 'order_missing' };
  const o0 = s0.data() || {};
  if ((o0.returnShipment || {}).shipmentId) return { skipped: 'already_linked', shipmentId: o0.returnShipment.shipmentId };
  if (o0.status !== WO.STATUS.REFUSED) return { skipped: `status_${o0.status || 'none'}` };
  try {
    // Posilka qo'lidagi kuryer (asl jo'natmaning joriy custodian'i).
    let courierId = null;
    const outboundId = String((o0.shipment || {}).shipmentId || '');
    if (outboundId) {
      const os = await db.collection(L.SHIPMENTS).doc(outboundId).get();
      const cur = os.exists ? ((os.data() || {}).currentCustodian || {}) : {};
      if (cur.kind === L.CUSTODIAN_KIND.PROVIDER && toCanonicalId(cur.id)) courierId = toCanonicalId(cur.id);
    }
    const r = await createReturnShipment(deps, orderId, o0, courierId);
    const now = nowFn ? nowFn() : new Date();
    const out = await db.runTransaction(async (tx) => {
      const s = await tx.get(ref);
      const o = s.data() || {};
      if ((o.returnShipment || {}).shipmentId) return { already: true, shipmentId: o.returnShipment.shipmentId };
      const seq = (isInt(o.historySeq) ? o.historySeq : 0) + 1;
      tx.update(ref, {
        returnShipment: {
          shipmentId: r.shipmentId,
          orderId: r.orderId,
          legId: r.legId,
          trackingNumber: r.trackingNumber,
          fee: r.fee,
          tariffVersion: r.tariffVersion,
          courierId: r.courierId,
          createdAt: now,
        },
        returnStatus: WO.RETURN_STATUS.AWAITING_PAYMENT,
        returnShipmentError: null,
        historySeq: seq,
        updatedAt: now,
      });
      tx.set(ref.collection(HISTORY).doc(String(seq)), {
        seq, from: o.status, to: o.status, event: 'return_shipment_created', actor: WO.ACTOR.SYSTEM, actorId: null, reason: '',
        meta: {
          shipmentId: r.shipmentId, trackingNumber: r.trackingNumber, fee: r.fee, tariffVersion: r.tariffVersion, preassigned: !!r.courierId,
        },
        at: now,
      });
      return { already: false, shipmentId: r.shipmentId };
    });
    log('ensureReturnShipment', {
      result: out.already ? 'already' : 'ok', orderId, shipmentId: out.shipmentId, fee: r.fee,
      tariffVersion: r.tariffVersion, preassigned: !!r.courierId, durationMs: Date.now() - started,
    });
    return { linked: !out.already, shipmentId: out.shipmentId, fee: r.fee, courierId: r.courierId };
  } catch (e) {
    const code = String((e && e.details && e.details.reason) || (e && e.code) || 'UNKNOWN').slice(0, 64);
    const now = nowFn ? nowFn() : new Date();
    let rec = null;
    try {
      rec = await db.runTransaction(async (tx) => {
        const s = await tx.get(ref);
        const o = s.data() || {};
        if ((o.returnShipment || {}).shipmentId) return null;
        const prev = o.returnShipmentError && isInt(o.returnShipmentError.attempts) ? o.returnShipmentError.attempts : 0;
        const err = { code, at: now, attempts: prev + 1, final: prev + 1 >= RETURN_MAX_ATTEMPTS };
        tx.update(ref, { returnShipmentError: err, updatedAt: now });
        return err;
      });
    } catch (e2) {
      rec = null;
    }
    console.error(JSON.stringify({
      module: 'wholesale_orders', action: 'ensureReturnShipment', result: 'failed', orderId, errorCode: code,
      attempts: rec ? rec.attempts : null, final: rec ? rec.final : null,
      message: String((e && e.message) || e).slice(0, 200), durationMs: Date.now() - started,
    }));
    return { failed: true, code, attempts: rec ? rec.attempts : null, final: rec ? rec.final : null };
  }
}

module.exports = {
  RETURN_SOURCE,
  RETURN_MAX_ATTEMPTS,
  returnIdemKey,
  returnParcelFromOrder,
  createReturnShipment,
  ensureWholesaleReturnShipment,
};
