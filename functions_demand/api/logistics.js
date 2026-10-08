'use strict';

/**
 * AVA LOGISTICS (RELAY) — API (hujjat §7.8; D-3…D-10).
 *
 *   quoteLogisticsOrder      narx (pulsiz), faol tarif bo'yicha
 *   createLogisticsOrder     ORDER + SHIPMENT'lar + sirlar + marshrut v1 + LEG(draft)
 *   acceptLeg                ijrochi LEG'ni oladi — birinchi qabul g'olib
 *   scanHandover             custody: oldi (QR/kod), ATOMAR (7.4)
 *   confirmDelivery          oxirgi LEG → qabul qiluvchi (yetkazish kodi)
 *   cancelLogisticsOrder     custody boshlanmagan bo'lsa — bekor (+ refund_pending)
 *   getShipmentSecrets       QR payload / kodlar (faqat egasi va joriy custodian)
 *   admin*                   tarif qoralamasi/faol qilish, marshrutni qayta rejalash
 *   onShipmentFunded         (trigger) eskrou tushdi → LEG-1 ochiladi
 *
 * ── CHEGARALAR ─────────────────────────────────────────────────────────
 * PUL bu codebase'da YO'Q. To'lov holatlarini (`paymentStatus`) bu yer
 * yozadi, ledger yozuvlarini `functions/relay_escrow.js` (default
 * codebase — ledger o'sha yerda, taksi billing namunasi). Ikkisi
 * Firestore hujjati orqali bog'lanadi.
 *
 * LEG — MAVJUD `demands` hujjati: `demand_matches`, `expireDemandsSweeper`,
 * `reopenStaleAssignments`, push siyosati o'zgarishsiz ishlaydi. Taklif
 * (`submitOffer`) LEG uchun ishlatilmaydi — narx tarifdan (D-8).
 */

const { callerIdFrom, toCanonicalId } = require('../core/ids');
const { resolveFlags, getModuleConfig } = require('../core/config');
const sm = require('../core/state_machine');
const tariffCore = require('../core/tariff');
const L = require('../core/logistics');
const { getAdapter } = require('../core/registry');
const { runMatching } = require('../matching/orchestrator');
const geoHash = require('../geo/geo_hash');
const { assertAnalyticsAdmin } = require('../analytics/access');

const DEMANDS = 'demands';
const MATCHES = 'demand_matches';
const IDEMPOTENCY = 'demand_idempotency';
const TARIFF_AUDIT = 'logistics_audit';
const MAX_PARCELS = 5;

/**
 * Konfig HUDUDSIZ: `module_config/logistics_all`. Logistika hududlararo
 * (Xorazm → Toshkent), bitta kill switch yetadi. Yana bir sabab: yadroning
 * `moduleRegionKey` `_`li hudud ID'sini (`toshkent_shahri`) qabul qilmaydi —
 * bu ids.js'dagi mavjud chegara, shu yerda aylanib o'tilmaydi.
 */
const CONFIG_REGION = 'all';

/** Hudud/tuman ID — `geo_regions`/`geo_districts` kalit shakli (`toshkent_shahri`). */
const GEO_ID_RE = /^[a-z0-9][a-z0-9_-]{0,63}$/;

function fail(code, message, reason, extra) {
  const e = new Error(message);
  e.code = code;
  e.httpErrorCode = code;
  e.details = { reason: reason || code, ...(extra || {}) };
  return e;
}

const isInt = (n) => typeof n === 'number' && Number.isInteger(n);
const isPosInt = (n) => isInt(n) && n > 0;

function finiteOrNull(v) {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

// ═══════════════════════════════════════════════════════════════════════
// VALIDATSIYA
// ═══════════════════════════════════════════════════════════════════════

/**
 * Nuqta: hudud ID'lari KLIENTDAN keladi (bu yerda u xavfsizlik emas,
 * NARX ma'lumoti) va SERVER ularni `geo_regions`/`geo_districts` bo'yicha
 * tekshiradi (repodagi `functions/index.js:7463` qoidasi bilan bir xil).
 */
async function validatePoint(db, raw, name) {
  const p = raw && typeof raw === 'object' ? raw : {};
  const regionId = String(p.regionId || '').trim();
  const districtId = String(p.districtId || '').trim();
  if (!regionId || !GEO_ID_RE.test(regionId)) {
    throw fail('invalid-argument', `${name}: viloyat tanlanmagan`, 'point_region_required');
  }
  if (districtId && !GEO_ID_RE.test(districtId)) {
    throw fail('invalid-argument', `${name}: tuman noto'g'ri`, 'point_district_invalid');
  }
  const r = await db.collection('geo_regions').doc(regionId).get();
  if (!r.exists) throw fail('invalid-argument', `${name}: noma'lum viloyat`, 'geo_region_unknown');
  if (districtId) {
    const d = await db.collection('geo_districts').doc(districtId).get();
    if (!d.exists || String((d.data() || {}).regionId || '') !== regionId) {
      throw fail('invalid-argument', `${name}: tuman viloyatga mos emas`, 'geo_district_unknown');
    }
  }
  const lat = finiteOrNull(p.lat);
  const lng = finiteOrNull(p.lng);
  if ((lat === null) !== (lng === null)) throw fail('invalid-argument', `${name}: lat/lng juft`, 'point_coords');
  if (lat !== null && (lat < -90 || lat > 90 || lng < -180 || lng > 180)) {
    throw fail('invalid-argument', `${name}: koordinata chegaradan tashqarida`, 'point_coords');
  }
  return {
    regionId,
    districtId,
    lat,
    lng,
    geohash: lat !== null ? geoHash.encode(lat, lng, 7) : '',
    addressText: String(p.addressText || '').slice(0, 300),
  };
}

function validateParcel(raw, i) {
  const p = raw && typeof raw === 'object' ? raw : {};
  const out = {
    actualWeightG: p.actualWeightG,
    lengthCm: p.lengthCm,
    widthCm: p.widthCm,
    heightCm: p.heightCm,
    declaredValue: p.declaredValue == null ? 0 : p.declaredValue,
    description: String(p.description || '').slice(0, 200),
    fragile: p.fragile === true,
  };
  for (const k of ['actualWeightG', 'lengthCm', 'widthCm', 'heightCm']) {
    if (!isPosInt(out[k])) throw fail('invalid-argument', `parcels[${i}].${k} musbat butun son bo'lishi kerak`, 'parcel_invalid');
  }
  if (!isInt(out.declaredValue) || out.declaredValue < 0) {
    throw fail('invalid-argument', `parcels[${i}].declaredValue butun so'm`, 'parcel_invalid');
  }
  return out;
}

function validateParcels(raw) {
  if (!Array.isArray(raw) || raw.length < 1 || raw.length > MAX_PARCELS) {
    throw fail('invalid-argument', `parcels 1..${MAX_PARCELS}`, 'parcels_count');
  }
  return raw.map(validateParcel);
}

function validateRecipient(raw) {
  const r = raw && typeof raw === 'object' ? raw : {};
  const name = String(r.name || '').trim().slice(0, 80);
  const phone = toCanonicalId(r.phone || '');
  if (name.length < 2) throw fail('invalid-argument', 'Qabul qiluvchi ismi', 'recipient_name');
  if (!phone) throw fail('invalid-argument', 'Qabul qiluvchi telefoni', 'recipient_phone');
  return { name, phone };
}

async function requireActiveTariff(db) {
  const t = await tariffCore.getActiveTariff(db);
  if (!t) throw fail('failed-precondition', 'Jo\'natma xizmati hali ishga tushmagan', 'tariff_not_active');
  return t;
}

async function requireEnabled(db, callerId) {
  const flags = await resolveFlags(db, L.MODULE, CONFIG_REGION);
  if (!flags.enabled) {
    throw fail('unavailable', flags.killReason
      ? 'Xizmat vaqtincha to\'xtatilgan'
      : 'Jo\'natma xizmati sizning hududingizda hali ishga tushmagan', 'module_disabled');
  }
  // INTERNAL bosqich (42-band): sinov ro'yxatida bo'lmagan — xizmat «hali
  // ishga tushmagan». Mavjudligini boshqacha oshkor qilmaymiz.
  if (!L.isStageAllowed(flags.config, callerId)) {
    throw fail('unavailable', 'Jo\'natma xizmati hali ishga tushmagan', 'module_internal_only');
  }
  return flags;
}

// ═══════════════════════════════════════════════════════════════════════
// NARX
// ═══════════════════════════════════════════════════════════════════════

async function quoteOrderInternal(db, data, callerId) {
  const origin = await validatePoint(db, data.origin, 'origin');
  const destination = await validatePoint(db, data.destination, 'destination');
  await requireEnabled(db, callerId);
  const t = await requireActiveTariff(db);
  const parcels = validateParcels(data.parcels);
  const quotes = parcels.map((p) => tariffCore.quoteParcel(t, p, origin, destination));
  const total = quotes.reduce((s, q) => s + q.customerPrice, 0);
  return { tariff: t, origin, destination, parcels, quotes, total };
}

function makeQuoteLogisticsOrder(deps) {
  const { db } = deps;
  return async function quoteLogisticsOrder(data, context) {
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const q = await quoteOrderInternal(db, data || {}, callerId);
    return {
      tariffVersion: q.tariff.version,
      currency: 'UZS',
      parcels: q.quotes.map((s) => ({
        zone: s.zone,
        chargeableWeightG: s.chargeableWeightG,
        volumetricWeightG: s.volumetricWeightG,
        basePrice: s.basePrice,
        declaredValueFee: s.declaredValueFee,
        customerPrice: s.customerPrice,
      })),
      total: q.total,
    };
  };
}

/**
 * Ilova kirish nuqtasi uchun: shu foydalanuvchiga «Jo'natma» ochiqmi.
 * `module_defaults` «soon» bo'lsa ham sinovchi kira olishi uchun (42-band).
 * Ro'yxatning o'zi QAYTARILMAYDI (40-band: boshqalarning telefoni).
 */
function makeGetLogisticsAccess(deps) {
  const { db } = deps;
  return async function getLogisticsAccess(data, context) {
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const flags = await resolveFlags(db, L.MODULE, CONFIG_REGION);
    const stage = L.stageOf(flags.config);
    return { allowed: flags.enabled && L.isStageAllowed(flags.config, callerId), stage };
  };
}

// ═══════════════════════════════════════════════════════════════════════
// LEG hujjati — MAVJUD `demand` shakli (create_demand.js bilan bir xil kalitlar)
// ═══════════════════════════════════════════════════════════════════════

function pointLabel(p) {
  return p.districtId || p.regionId || '';
}

function buildLegDemand({
  ownerId, order, shipment, shipmentId, leg, legIndex, legCount, legIds, adapter, now, ttlMinutes,
}) {
  const kinds = L.handoverKindsFor(legIndex, legCount);
  const parcel = shipment.parcel;
  const snap = shipment.priceSnapshot;
  return {
    schemaVersion: 1,
    ownerId,
    module: L.MODULE,
    mode: adapter.mode,
    categoryId: null,
    categoryGroup: null,
    status: sm.STATUS.DRAFT,
    matching: { state: sm.MATCHING_STATE.PENDING, matchedBucket: '0', wave: 0 },
    source: 'module',
    input: { type: 'form' },
    title: `Jo'natma ${shipment.trackingNumber}: ${pointLabel(leg.from)} → ${pointLabel(leg.to)}`,
    description: parcel.description || '',
    location: leg.from,
    destination: leg.to,
    timeWindow: { neededBy: null, expiresAt: new Date(now.getTime() + ttlMinutes * 60000) },
    budget: null,
    quantity: null,
    wholesale: false,
    media: { images: [] },
    contact: null,
    attributes: {
      shipmentId,
      orderId: order.id,
      trackingNumber: shipment.trackingNumber,
      legIndex,
      legCount,
      legKind: leg.kind,
      dependsOnLegId: legIndex > 0 ? legIds[legIndex - 1] : null,
      nextLegId: legIndex < legCount - 1 ? legIds[legIndex + 1] : null,
      handoverFromKind: kinds.fromKind,
      handoverToKind: kinds.toKind,
      /** Ijrochi haqi — ICHKI qatlam, ijrochiga ko'rinadi, mijozga emas (14). */
      payout: leg.payout,
      parcel: {
        chargeableWeightG: snap.chargeableWeightG,
        actualWeightG: snap.actualWeightG,
        lengthCm: snap.lengthCm,
        widthCm: snap.widthCm,
        heightCm: snap.heightCm,
        fragile: parcel.fragile === true,
      },
    },
    payerSide: 'sender',
    termsAcceptedAt: order.termsAcceptedAt || null,
    assignment: { providerId: null, offerId: null, acceptedAt: null },
    tariffVersion: snap.tariffVersion,
    payment: { kind: 'escrow', legPayout: leg.payout, currency: 'UZS' },
    createdAt: now,
    updatedAt: now,
  };
}

/** Marshrut rejasi + LEG hujjatlari (D-9, D-10). `from`/`to` tayyor nuqtalar. */
function buildRoute({ tariff, shipment, points, version }) {
  const count = points.length;
  const kinds = tariffCore.legKindsFor(count);
  const split = tariffCore.splitInternal(tariff, shipment.priceSnapshot.customerPrice, kinds);
  const legs = points.map((seg, i) => ({
    index: i,
    kind: kinds[i],
    from: seg.from,
    to: seg.to,
    payout: split.legPayouts[i].amount,
  }));
  return { version, legs, split };
}

// ═══════════════════════════════════════════════════════════════════════
// BUYURTMA YARATISH
// ═══════════════════════════════════════════════════════════════════════

/** Kunlik tracking hisoblagichi — tranzaksiya, N ta raqam bir yo'la. */
async function reserveTrackingSeq(db, now, count) {
  const key = L.trackingDayKey(now);
  const ref = db.collection(L.COUNTERS).doc(key);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const cur = snap.exists ? Number((snap.data() || {}).seq) || 0 : 0;
    tx.set(ref, { seq: cur + count, updatedAt: now }, { merge: true });
    return cur + 1;
  });
}

function makeCreateLogisticsOrder(deps) {
  const { db, now: nowFn } = deps;

  return async function createLogisticsOrder(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const ownerId = callerIdFrom(context);
    if (!ownerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const input = data || {};

    const clientRequestId = String(input.clientRequestId || '');
    if (!/^[A-Za-z0-9_-]{8,64}$/.test(clientRequestId)) {
      throw fail('invalid-argument', 'clientRequestId', 'client_request_id');
    }
    const idemRef = db.collection(IDEMPOTENCY).doc(`${ownerId}_${clientRequestId}`);
    const idem = await idemRef.get();
    if (idem.exists) {
      const d = idem.data() || {};
      return { orderId: d.orderId, shipmentIds: d.shipmentIds || [], duplicate: true };
    }

    const q = await quoteOrderInternal(db, input, ownerId);
    const recipient = validateRecipient(input.recipient);
    const adapter = getAdapter(L.MODULE);
    if (!adapter) throw fail('unimplemented', 'logistics adapteri ulanmagan');
    const config = await getModuleConfig(db, L.MODULE, CONFIG_REGION);
    const ttl = Number((config.logistics || {}).legTtlMinutes) || 3 * 24 * 60;
    const termsAcceptedAt = input.termsAcceptedAt ? new Date(String(input.termsAcceptedAt)) : null;

    const seqStart = await reserveTrackingSeq(db, now, q.parcels.length);

    const orderRef = db.collection(L.ORDERS).doc();
    const batch = db.batch();
    const shipmentIds = [];
    const trackingNumbers = [];
    const order = {
      id: orderRef.id,
      ownerId,
      termsAcceptedAt: termsAcceptedAt && !Number.isNaN(termsAcceptedAt.getTime()) ? termsAcceptedAt : null,
    };

    for (let i = 0; i < q.parcels.length; i += 1) {
      const shipmentRef = db.collection(L.SHIPMENTS).doc();
      const legRef = db.collection(DEMANDS).doc();
      const trackingNumber = L.formatTrackingNumber(now, seqStart + i);
      const qrSecret = L.newQrSecret();
      const shipment = {
        orderId: orderRef.id,
        ownerId,
        trackingNumber,
        status: L.SHIPMENT_STATUS.AWAITING_PAYMENT,
        paymentStatus: L.PAYMENT_STATUS.PENDING,
        origin: q.origin,
        destination: q.destination,
        recipientName: recipient.name,
        parcel: q.parcels[i],
        /** D-8: narx muhrlangan — tarif keyin o'zgarsa bu o'zgarmaydi. */
        priceSnapshot: { ...q.quotes[i], calculatedAt: now },
        currentCustodian: { kind: L.CUSTODIAN_KIND.SENDER, id: ownerId, since: now },
        currentLegId: null,
        routePlanVersion: 1,
        legIds: [legRef.id],
        legCount: 1,
        assignedProviderIds: [],
        custodyCount: 0,
        createdAt: now,
        updatedAt: now,
      };
      const route = buildRoute({
        tariff: q.tariff, shipment, version: 1,
        points: [{ from: q.origin, to: q.destination }],
      });
      const leg = route.legs[0];

      batch.set(shipmentRef, shipment);
      batch.set(shipmentRef.collection('private').doc('secrets'), { qrSecret, createdAt: now });
      // ICHKI qatlam — mijoz o'qimaydi (qoida: private/* yopiq).
      batch.set(shipmentRef.collection('private').doc('internal'), {
        platformShare: route.split.platformShare,
        providerPool: route.split.providerPool,
        legPayouts: route.split.legPayouts,
        tariffVersion: q.tariff.version,
        updatedAt: now,
      });
      batch.set(db.collection(L.ROUTE_PLANS).doc(shipmentRef.id), {
        shipmentId: shipmentRef.id, currentVersion: 1, updatedAt: now,
      });
      batch.set(db.collection(L.ROUTE_PLANS).doc(shipmentRef.id).collection('versions').doc('1'), {
        version: 1,
        legs: route.legs.map((l) => ({ ...l, legId: legRef.id })),
        reason: 'initial',
        createdBy: 'system',
        createdAt: now,
        supersededAt: null,
      });
      batch.set(legRef, buildLegDemand({
        ownerId, order, shipment, shipmentId: shipmentRef.id, leg,
        legIndex: 0, legCount: 1, legIds: [legRef.id], adapter, now, ttlMinutes: ttl,
      }));
      batch.set(legRef.collection('private').doc('stats'), {
        matchedCount: 0, candidateCount: 0, rejectedCount: 0, updatedAt: now,
      });
      shipmentIds.push(shipmentRef.id);
      trackingNumbers.push(trackingNumber);
    }

    batch.set(orderRef, {
      ownerId,
      status: L.deriveOrderStatus(shipmentIds.map(() => L.SHIPMENT_STATUS.AWAITING_PAYMENT)),
      shipmentIds,
      trackingNumbers,
      origin: q.origin,
      destination: q.destination,
      /** Qabul qiluvchi telefoni FAQAT shu yerda (egasi o'qiydi) — 40-band. */
      recipient,
      note: String(input.note || '').slice(0, 500),
      customerPriceTotal: q.total,
      currency: 'UZS',
      tariffVersion: q.tariff.version,
      consolidation: { count: shipmentIds.length, discountApplied: false, tariffVersion: q.tariff.version },
      termsAcceptedAt: order.termsAcceptedAt,
      createdAt: now,
      updatedAt: now,
    });
    batch.set(idemRef, {
      ownerId, kind: 'logistics_order', orderId: orderRef.id, shipmentIds, createdAt: now,
    });
    await batch.commit();

    return {
      orderId: orderRef.id,
      shipmentIds,
      trackingNumbers,
      total: q.total,
      currency: 'UZS',
      paymentStatus: L.PAYMENT_STATUS.PENDING,
      duplicate: false,
    };
  };
}

// ═══════════════════════════════════════════════════════════════════════
// LEG OCHISH (zanjir, 6.1) + MATCHING
// ═══════════════════════════════════════════════════════════════════════

/**
 * `draft` → `active` + matching + push. Modul o'chiq bo'lsa LEG draft'da
 * qoladi (`skipped: 'disabled'`) — keyin admin/qayta urinish ochadi.
 *
 * `opts.allowExpired` — admin qayta ochishi (`adminReactivateLeg`):
 * `expired` → `active` (state machine ruxsat beradi), muddat qaytadan.
 */
async function activateLeg(deps, legId, opts = {}) {
  const { db, keywordIndex, notify, now: nowFn } = deps;
  const now = nowFn ? nowFn() : new Date();
  const ref = db.collection(DEMANDS).doc(legId);
  const snap = await ref.get();
  if (!snap.exists) return { skipped: 'missing' };
  const d = snap.data() || {};
  if (d.module !== L.MODULE) return { skipped: 'not_logistics' };
  const allowed = opts.allowExpired ? [sm.STATUS.DRAFT, sm.STATUS.EXPIRED] : [sm.STATUS.DRAFT];
  if (!allowed.includes(d.status)) return { skipped: `status_${d.status}` };

  const flags = await resolveFlags(db, L.MODULE, CONFIG_REGION);
  if (!flags.enabled) return { skipped: 'disabled' };
  const config = flags.config;
  const ttl = Number((config.logistics || {}).legTtlMinutes) || 3 * 24 * 60;

  sm.assertTransition(d.status, sm.STATUS.ACTIVE, 'activateLeg');
  const patch = {
    status: sm.STATUS.ACTIVE,
    'timeWindow.expiresAt': new Date(now.getTime() + ttl * 60000),
    activatedAt: now,
    updatedAt: now,
  };
  if (d.status === sm.STATUS.EXPIRED) {
    patch.reopenedAt = now;
    patch.reopenReason = opts.reason || 'admin_reactivate';
    patch.reopenCount = Number(d.reopenCount || 0) + 1;
    patch.expiredAt = null;
  }
  await ref.update(patch);

  const demand = { id: legId, ...d, status: sm.STATUS.ACTIVE };
  const adapter = getAdapter(L.MODULE);
  let matchResult = null;
  if (flags.matchingEnabled && adapter) {
    try {
      matchResult = await runMatching({
        db, demand, config, adapter, sources: adapter.sources, keywordIndex,
      });
      await ref.update({
        'matching.state': matchResult.state,
        'matching.matchedBucket': matchResult.matchedBucket,
        updatedAt: now,
      });
    } catch (e) {
      console.error(`LEG matching xatosi (${legId}): ${e.stack || e.message}`);
      await ref.update({ 'matching.state': sm.MATCHING_STATE.FAILED });
    }
  }
  if (notify && matchResult && matchResult.matchedCount > 0) {
    try {
      await notify(db, demand, matchResult, { flags, config });
    } catch (e) {
      console.error(`LEG push xatosi (${legId}): ${e.message}`);
    }
  }
  return { activated: true, matchedBucket: matchResult ? matchResult.matchedBucket : '0' };
}

/** Trigger: shipments/{id} `paymentStatus` → escrow_funded bo'lganda LEG-1. */
function makeOnShipmentFunded(deps) {
  return async function onShipmentFunded(before, after, shipmentId) {
    const was = (before || {}).paymentStatus;
    const is = (after || {}).paymentStatus;
    if (is !== L.PAYMENT_STATUS.ESCROW_FUNDED || was === is) return { skipped: 'no_change' };
    const legIds = Array.isArray(after.legIds) ? after.legIds : [];
    if (!legIds.length) return { skipped: 'no_legs' };
    const r = await activateLeg(deps, legIds[0]);
    console.log(`onShipmentFunded ${shipmentId}: ${JSON.stringify(r)}`);
    return r;
  };
}

// ═══════════════════════════════════════════════════════════════════════
// ORDER holati (derived) — har o'zgarishdan keyin
// ═══════════════════════════════════════════════════════════════════════

async function recomputeOrderStatus(db, orderId, now) {
  if (!orderId) return null;
  const snap = await db.collection(L.SHIPMENTS).where('orderId', '==', orderId).get();
  const statuses = snap.docs.map((d) => (d.data() || {}).status);
  const status = L.deriveOrderStatus(statuses);
  const ref = db.collection(L.ORDERS).doc(orderId);
  const cur = await ref.get();
  if (!cur.exists) return status;
  if ((cur.data() || {}).status !== status) await ref.update({ status, updatedAt: now });
  return status;
}

// ═══════════════════════════════════════════════════════════════════════
// IJROCHI: LEG'ni OLISH (birinchi qabul g'olib)
// ═══════════════════════════════════════════════════════════════════════

function makeAcceptLeg(deps) {
  const { db, now: nowFn } = deps;

  return async function acceptLeg(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const providerId = callerIdFrom(context);
    if (!providerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const legId = String((data || {}).legId || '');
    if (!legId) throw fail('invalid-argument', 'legId majburiy');

    const legRef = db.collection(DEMANDS).doc(legId);
    const matchRef = db.collection(MATCHES).doc(`${legId}_${providerId}`);

    const out = await db.runTransaction(async (tx) => {
      const [legSnap, matchSnap] = await Promise.all([tx.get(legRef), tx.get(matchRef)]);
      if (!legSnap.exists) throw fail('not-found', 'LEG topilmadi');
      const leg = legSnap.data() || {};
      if (leg.module !== L.MODULE) throw fail('failed-precondition', 'Bu jo\'natma emas', 'not_logistics');
      // Mos emas → mavjudligini ham oshkor qilmaymiz (offers.js bilan bir xil).
      if (!matchSnap.exists) throw fail('permission-denied', 'Bu jo\'natma sizga mos emas', 'not_matched');
      if (leg.ownerId === providerId) throw fail('permission-denied', 'O\'z jo\'natmangizni olib bo\'lmaydi', 'self');
      // Birinchi g'olib: ikkinchi chaqiruv shu yerda to'xtaydi.
      sm.assertTransition(leg.status, sm.STATUS.ACCEPTED, 'acceptLeg');
      const expiresAt = (leg.timeWindow || {}).expiresAt;
      if (expiresAt && sm.toMillis(expiresAt) < now.getTime()) {
        throw fail('failed-precondition', 'LEG muddati tugagan', 'expired');
      }

      const a = leg.attributes || {};
      const shipmentRef = db.collection(L.SHIPMENTS).doc(String(a.shipmentId || ''));
      const shipSnap = await tx.get(shipmentRef);
      if (!shipSnap.exists) throw fail('failed-precondition', 'Jo\'natma topilmadi', 'shipment_missing');
      const ship = shipSnap.data() || {};
      if (![L.SHIPMENT_STATUS.READY, L.SHIPMENT_STATUS.IN_TRANSIT].includes(ship.status)) {
        throw fail('failed-precondition', 'Jo\'natma hali to\'lanmagan yoki yopilgan', 'shipment_not_ready');
      }

      // Olish nuqtasi kontakti (Т-9, 1-pog'ona): LEG-1 — jo'natuvchi;
      // keyingilari — oldingi ijrochi (joriy custodian).
      const idx = Number(a.legIndex) || 0;
      const pickupPhone = idx === 0 ? leg.ownerId : ((ship.currentCustodian || {}).id || null);
      const loc = leg.location || {};

      tx.update(legRef, {
        status: sm.STATUS.ACCEPTED,
        assignment: { providerId, offerId: null, acceptedAt: now },
        updatedAt: now,
      });
      tx.set(matchRef, {
        status: 'accepted',
        acceptedAt: now,
        contactUnlocked: {
          stage: 1,
          ownerPhone: pickupPhone,
          pickupAddress: loc.addressText || '',
          pickupLat: loc.lat == null ? null : loc.lat,
          pickupLng: loc.lng == null ? null : loc.lng,
          handoverFromKind: a.handoverFromKind || null,
        },
      }, { merge: true });
      const assigned = Array.isArray(ship.assignedProviderIds) ? ship.assignedProviderIds : [];
      tx.update(shipmentRef, {
        assignedProviderIds: assigned.includes(providerId) ? assigned : [...assigned, providerId],
        [`legAssignments.${legId}`]: providerId,
        updatedAt: now,
      });
      return { shipmentId: shipmentRef.id, legIndex: idx, prevLegId: a.dependsOnLegId || null, ship };
    });

    // Tranzaksiyadan TASHQARIDA: qolgan match'lar «olindi»; oldingi
    // ijrochiga keyingi ijrochi telefoni ochiladi (topshirish nuqtasi uchun).
    await closeOtherMatches(db, legId, providerId, 'taken', now);
    if (out.prevLegId) {
      const prevProvider = (out.ship.legAssignments || {})[out.prevLegId];
      if (prevProvider) {
        await db.collection(MATCHES).doc(`${out.prevLegId}_${prevProvider}`).set({
          contactUnlocked: { nextProviderPhone: providerId },
        }, { merge: true });
      }
    }
    return { ok: true, legId, shipmentId: out.shipmentId };
  };
}

async function closeOtherMatches(db, legId, winnerId, status, now) {
  const snap = await db.collection(MATCHES).where('demandId', '==', legId).get();
  if (snap.empty) return 0;
  const batch = db.batch();
  let n = 0;
  for (const d of snap.docs) {
    if ((d.data() || {}).providerId === winnerId) continue;
    batch.set(d.ref, { status, closedAt: now, contactUnlocked: null }, { merge: true });
    n += 1;
  }
  if (n) await batch.commit();
  return n;
}

// ═══════════════════════════════════════════════════════════════════════
// CUSTODY: OLISH (7.4) — bitta callable, bitta tranzaksiya
// ═══════════════════════════════════════════════════════════════════════

function validateProofInput(data, config) {
  const d = data || {};
  const code = d.code == null ? '' : String(d.code).trim();
  const qrPayload = d.qrPayload == null ? '' : String(d.qrPayload).trim();
  if (!code && !qrPayload) throw fail('invalid-argument', 'Kod yoki QR kerak', 'proof_required');
  const photos = (Array.isArray(d.photoUrls) ? d.photoUrls : [])
    .map((u) => String(u || '').trim()).filter((u) => /^https?:\/\//.test(u) && u.length <= 500).slice(0, 4);
  const requirePhoto = ((config || {}).logistics || {}).requireHandoverPhoto !== false;
  if (requirePhoto && photos.length === 0) throw fail('invalid-argument', 'Rasm majburiy', 'photo_required');
  const loc = d.location && typeof d.location === 'object' ? d.location : null;
  const location = loc && finiteOrNull(loc.lat) !== null && finiteOrNull(loc.lng) !== null
    ? { lat: Number(loc.lat), lng: Number(loc.lng), accuracy: finiteOrNull(loc.accuracy) }
    : null;
  return {
    code, qrPayload, photos, location,
    conditionFlags: L.normalizeConditionFlags(d.conditionFlags),
    clientRequestId: String(d.clientRequestId || '').slice(0, 64),
  };
}

function makeScanHandover(deps) {
  const { db, now: nowFn } = deps;

  return async function scanHandover(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const providerId = callerIdFrom(context);
    if (!providerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const legId = String((data || {}).legId || '');
    if (!legId) throw fail('invalid-argument', 'legId majburiy');

    const legRef = db.collection(DEMANDS).doc(legId);
    const pre = await legRef.get();
    if (!pre.exists) throw fail('not-found', 'LEG topilmadi');
    const preLeg = pre.data() || {};
    const config = await getModuleConfig(db, L.MODULE, CONFIG_REGION);
    const proof = validateProofInput(data, config);

    const a = preLeg.attributes || {};
    const shipmentId = String(a.shipmentId || '');
    const shipmentRef = db.collection(L.SHIPMENTS).doc(shipmentId);
    const secretsRef = shipmentRef.collection('private').doc('secrets');
    const orderRef = db.collection(L.ORDERS).doc(String(a.orderId || ''));
    const prevLegId = a.dependsOnLegId ? String(a.dependsOnLegId) : null;
    const prevLegRef = prevLegId ? db.collection(DEMANDS).doc(prevLegId) : null;
    const eventId = L.custodyIdempotencyKey(shipmentId, legId, 'pickup');
    const eventRef = db.collection(L.CUSTODY).doc(eventId);
    const idx = Number(a.legIndex) || 0;
    const count = Number(a.legCount) || 1;

    const result = await db.runTransaction(async (tx) => {
      const reads = [tx.get(legRef), tx.get(shipmentRef), tx.get(secretsRef), tx.get(eventRef), tx.get(orderRef)];
      if (prevLegRef) reads.push(tx.get(prevLegRef));
      const [legSnap, shipSnap, secSnap, evSnap, orderSnap, prevSnap] = await Promise.all(reads);

      if (evSnap.exists) {
        return { idempotent: true, event: evSnap.data() };
      }
      if (!legSnap.exists || !shipSnap.exists || !secSnap.exists) {
        throw fail('failed-precondition', 'Jo\'natma ma\'lumoti to\'liq emas', 'shipment_missing');
      }
      const leg = legSnap.data() || {};
      const ship = shipSnap.data() || {};
      const qrSecret = (secSnap.data() || {}).qrSecret;
      if ((leg.assignment || {}).providerId !== providerId) {
        throw fail('permission-denied', 'Bu LEG sizga tayinlanmagan', 'not_assigned');
      }
      if (leg.status !== sm.STATUS.ACCEPTED) {
        throw fail('failed-precondition', 'LEG olish holatida emas', 'leg_not_accepted', { status: leg.status });
      }
      if (![L.SHIPMENT_STATUS.READY, L.SHIPMENT_STATUS.IN_TRANSIT].includes(ship.status)) {
        throw fail('failed-precondition', 'Jo\'natma holati olishga mos emas', 'shipment_not_ready', { status: ship.status });
      }
      if (ship.paymentStatus !== L.PAYMENT_STATUS.ESCROW_FUNDED) {
        // D-TAXI-13 analogi: to'lovsiz custody yo'q.
        throw fail('failed-precondition', 'To\'lov tasdiqlanmagan', 'not_funded');
      }
      if (!L.verifyHandoverProof(shipmentId, qrSecret, { code: proof.code, qrPayload: proof.qrPayload })) {
        throw fail('permission-denied', 'Kod noto\'g\'ri', 'bad_proof');
      }

      // Kimdan olinadi — JORIY custodian (D-7: faqat jismoniy qabulda o'zgaradi).
      const cur = ship.currentCustodian || {};
      let prevLeg = null;
      if (idx > 0) {
        if (!prevSnap || !prevSnap.exists) throw fail('failed-precondition', 'Oldingi LEG yo\'q', 'prev_leg_missing');
        prevLeg = prevSnap.data() || {};
        if (prevLeg.status !== sm.STATUS.IN_PROGRESS) {
          throw fail('failed-precondition', 'Oldingi ijrochi posilkani hali olmagan', 'prev_leg_not_in_progress');
        }
        if (cur.kind !== L.CUSTODIAN_KIND.PROVIDER || cur.id !== (prevLeg.assignment || {}).providerId) {
          throw fail('failed-precondition', 'Custody zanjiri mos emas', 'custody_mismatch');
        }
      } else if (cur.kind !== L.CUSTODIAN_KIND.SENDER) {
        throw fail('failed-precondition', 'Posilka jo\'natuvchida emas', 'custody_mismatch');
      }

      const event = {
        shipmentId,
        legId,
        orderId: a.orderId || null,
        /** Qoida `get()`siz tekshirsin — egasi o'z tarixini o'qiydi. */
        ownerId: ship.ownerId,
        trackingNumber: a.trackingNumber || ship.trackingNumber || '',
        kind: 'pickup',
        from: { kind: cur.kind, id: cur.id },
        to: { kind: L.CUSTODIAN_KIND.PROVIDER, id: providerId },
        legIndex: idx,
        legCount: count,
        timestamp: now,
        location: proof.location,
        proof: {
          qrVerified: !!proof.qrPayload,
          codeVerified: !proof.qrPayload && !!proof.code,
          photoUrls: proof.photos,
          conditionFlags: proof.conditionFlags,
        },
        createdBy: providerId,
        idempotencyKey: eventId,
        // PUL uchun (default codebase o'qiydi): oldingi LEG tugadi → EARNED.
        completesLegId: prevLegId,
        completedLegProviderId: prevLeg ? (prevLeg.assignment || {}).providerId : null,
        completedLegPayout: prevLeg ? Number((prevLeg.attributes || {}).payout) || 0 : null,
        deliversShipment: false,
      };
      tx.set(eventRef, event);

      const shipPatch = {
        currentCustodian: { kind: L.CUSTODIAN_KIND.PROVIDER, id: providerId, since: now },
        currentLegId: legId,
        custodyCount: (Number(ship.custodyCount) || 0) + 1,
        lastCustodyEventId: eventId,
        updatedAt: now,
      };
      if (ship.status === L.SHIPMENT_STATUS.READY) {
        shipPatch.status = L.assertShipmentTransition(ship.status, L.SHIPMENT_STATUS.IN_TRANSIT, 'pickup');
        shipPatch.inTransitAt = now;
      }
      tx.update(shipmentRef, shipPatch);

      // Olgan ijrochi: accepted → in_progress; 2-pog'ona kontakt (topshirish).
      sm.assertTransition(leg.status, sm.STATUS.IN_PROGRESS, 'scanHandover');
      tx.update(legRef, { status: sm.STATUS.IN_PROGRESS, pickedUpAt: now, updatedAt: now });
      const dest = leg.destination || {};
      const isLast = idx === count - 1;
      const order = orderSnap.exists ? (orderSnap.data() || {}) : {};
      tx.set(db.collection(MATCHES).doc(`${legId}_${providerId}`), {
        status: 'in_progress',
        contactUnlocked: {
          stage: 2,
          recipientPhone: isLast ? ((order.recipient || {}).phone || null) : null,
          recipientName: isLast ? ((order.recipient || {}).name || '') : '',
          dropoffAddress: dest.addressText || '',
          dropoffLat: dest.lat == null ? null : dest.lat,
          dropoffLng: dest.lng == null ? null : dest.lng,
          handoverToKind: a.handoverToKind || null,
          deliveryCodeRequired: isLast,
        },
      }, { merge: true });

      // Oldingi ijrochi: in_progress → completed (topshirdi).
      if (prevLegRef && prevLeg) {
        sm.assertTransition(prevLeg.status, sm.STATUS.COMPLETED, 'scanHandover(prev)');
        tx.update(prevLegRef, { status: sm.STATUS.COMPLETED, completedAt: now, handedOverAt: now, updatedAt: now });
        const prevProvider = (prevLeg.assignment || {}).providerId;
        if (prevProvider) {
          tx.set(db.collection(MATCHES).doc(`${prevLegId}_${prevProvider}`), {
            status: 'completed', closedAt: now,
          }, { merge: true });
        }
      }

      return { idempotent: false, event, nextLegId: a.nextLegId || null, orderId: a.orderId || null };
    });

    if (result.idempotent) {
      return { ok: true, idempotent: true, eventId, legStatus: 'in_progress' };
    }
    // Zanjir (6.1): posilka yo'lda — keyingi LEG ochiladi.
    const openOn = ((config.logistics || {}).openNextLegOn) || 'in_progress';
    if (result.nextLegId && openOn === 'in_progress') {
      try { await activateLeg(deps, result.nextLegId); } catch (e) {
        console.error(`keyingi LEG ochilmadi (${result.nextLegId}): ${e.message}`);
      }
    }
    await recomputeOrderStatus(db, result.orderId, now);
    return { ok: true, idempotent: false, eventId, legStatus: 'in_progress', shipmentId };
  };
}

// ═══════════════════════════════════════════════════════════════════════
// CUSTODY: YETKAZISH (oxirgi LEG → qabul qiluvchi)
// ═══════════════════════════════════════════════════════════════════════

function makeConfirmDelivery(deps) {
  const { db, now: nowFn } = deps;

  return async function confirmDelivery(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const providerId = callerIdFrom(context);
    if (!providerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const legId = String((data || {}).legId || '');
    const deliveryCode = String((data || {}).deliveryCode || '').trim();
    if (!legId) throw fail('invalid-argument', 'legId majburiy');
    if (!/^\d{6}$/.test(deliveryCode)) throw fail('invalid-argument', 'Yetkazish kodi 6 xonali', 'delivery_code_format');

    const legRef = db.collection(DEMANDS).doc(legId);
    const pre = await legRef.get();
    if (!pre.exists) throw fail('not-found', 'LEG topilmadi');
    const preLeg = pre.data() || {};
    const config = await getModuleConfig(db, L.MODULE, CONFIG_REGION);
    const photos = (Array.isArray((data || {}).photoUrls) ? data.photoUrls : [])
      .map((u) => String(u || '').trim()).filter((u) => /^https?:\/\//.test(u) && u.length <= 500).slice(0, 4);
    if (((config.logistics || {}).requireHandoverPhoto !== false) && photos.length === 0) {
      throw fail('invalid-argument', 'Rasm majburiy', 'photo_required');
    }
    const loc = (data || {}).location || null;
    const location = loc && finiteOrNull(loc.lat) !== null && finiteOrNull(loc.lng) !== null
      ? { lat: Number(loc.lat), lng: Number(loc.lng), accuracy: finiteOrNull(loc.accuracy) }
      : null;

    const a = preLeg.attributes || {};
    const shipmentId = String(a.shipmentId || '');
    const shipmentRef = db.collection(L.SHIPMENTS).doc(shipmentId);
    const secretsRef = shipmentRef.collection('private').doc('secrets');
    const eventId = L.custodyIdempotencyKey(shipmentId, legId, 'delivery');
    const eventRef = db.collection(L.CUSTODY).doc(eventId);
    const idx = Number(a.legIndex) || 0;
    const count = Number(a.legCount) || 1;

    const result = await db.runTransaction(async (tx) => {
      const [legSnap, shipSnap, secSnap, evSnap] = await Promise.all([
        tx.get(legRef), tx.get(shipmentRef), tx.get(secretsRef), tx.get(eventRef),
      ]);
      if (evSnap.exists) return { idempotent: true };
      if (!legSnap.exists || !shipSnap.exists || !secSnap.exists) {
        throw fail('failed-precondition', 'Jo\'natma ma\'lumoti to\'liq emas', 'shipment_missing');
      }
      const leg = legSnap.data() || {};
      const ship = shipSnap.data() || {};
      if ((leg.assignment || {}).providerId !== providerId) {
        throw fail('permission-denied', 'Bu LEG sizga tayinlanmagan', 'not_assigned');
      }
      if (idx !== count - 1) throw fail('failed-precondition', 'Bu oxirgi LEG emas', 'not_last_leg');
      if (leg.status !== sm.STATUS.IN_PROGRESS) {
        throw fail('failed-precondition', 'Posilka hali olinmagan', 'leg_not_in_progress', { status: leg.status });
      }
      const cur = ship.currentCustodian || {};
      if (cur.kind !== L.CUSTODIAN_KIND.PROVIDER || cur.id !== providerId) {
        throw fail('failed-precondition', 'Custody zanjiri mos emas', 'custody_mismatch');
      }
      if (!L.verifyDeliveryCode(shipmentId, (secSnap.data() || {}).qrSecret, deliveryCode)) {
        throw fail('permission-denied', 'Yetkazish kodi noto\'g\'ri', 'bad_delivery_code');
      }

      const event = {
        shipmentId,
        legId,
        orderId: a.orderId || null,
        ownerId: ship.ownerId,
        trackingNumber: a.trackingNumber || ship.trackingNumber || '',
        kind: 'delivery',
        from: { kind: L.CUSTODIAN_KIND.PROVIDER, id: providerId },
        to: { kind: L.CUSTODIAN_KIND.RECIPIENT, id: null },
        legIndex: idx,
        legCount: count,
        timestamp: now,
        location,
        proof: { qrVerified: false, codeVerified: true, photoUrls: photos, conditionFlags: ['intact'] },
        createdBy: providerId,
        idempotencyKey: eventId,
        completesLegId: legId,
        completedLegProviderId: providerId,
        completedLegPayout: Number(a.payout) || 0,
        deliversShipment: true,
      };
      tx.set(eventRef, event);
      tx.update(shipmentRef, {
        status: L.assertShipmentTransition(ship.status, L.SHIPMENT_STATUS.DELIVERED, 'confirmDelivery'),
        currentCustodian: { kind: L.CUSTODIAN_KIND.RECIPIENT, id: null, since: now },
        deliveredAt: now,
        custodyCount: (Number(ship.custodyCount) || 0) + 1,
        lastCustodyEventId: eventId,
        updatedAt: now,
      });
      sm.assertTransition(leg.status, sm.STATUS.COMPLETED, 'confirmDelivery');
      tx.update(legRef, { status: sm.STATUS.COMPLETED, completedAt: now, updatedAt: now });
      tx.set(db.collection(MATCHES).doc(`${legId}_${providerId}`), {
        status: 'completed', closedAt: now,
      }, { merge: true });
      return { idempotent: false, orderId: a.orderId || null };
    });

    if (!result.idempotent) await recomputeOrderStatus(db, result.orderId, now);
    return { ok: true, idempotent: result.idempotent, eventId, shipmentStatus: L.SHIPMENT_STATUS.DELIVERED };
  };
}

// ═══════════════════════════════════════════════════════════════════════
// BEKOR QILISH (custody boshlanmagan bo'lsa)
// ═══════════════════════════════════════════════════════════════════════

function makeCancelLogisticsOrder(deps) {
  const { db, now: nowFn } = deps;

  return async function cancelLogisticsOrder(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const ownerId = callerIdFrom(context);
    if (!ownerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const orderId = String((data || {}).orderId || '');
    if (!orderId) throw fail('invalid-argument', 'orderId majburiy');

    const orderRef = db.collection(L.ORDERS).doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) throw fail('not-found', 'Buyurtma topilmadi');
    const order = orderSnap.data() || {};
    if (order.ownerId !== ownerId) throw fail('permission-denied', 'Bu buyurtma sizniki emas');

    const shipSnap = await db.collection(L.SHIPMENTS).where('orderId', '==', orderId).get();
    const ships = shipSnap.docs.map((d) => ({ ref: d.ref, id: d.id, data: d.data() || {} }));
    for (const s of ships) {
      if (s.data.status === L.SHIPMENT_STATUS.CANCELLED) continue;
      if (!L.isShipmentCancellable(s.data.status)) {
        throw fail('failed-precondition', 'Posilka allaqachon yo\'lda — bekor qilib bo\'lmaydi', 'in_transit', { shipmentId: s.id });
      }
    }

    let refundPending = 0;
    const legIdsAll = [];
    const batch = db.batch();
    for (const s of ships) {
      if (s.data.status === L.SHIPMENT_STATUS.CANCELLED) continue;
      const patch = {
        status: L.assertShipmentTransition(s.data.status, L.SHIPMENT_STATUS.CANCELLED, 'cancelLogisticsOrder'),
        cancelledAt: now,
        cancelledBy: 'owner',
        updatedAt: now,
      };
      // Eskrou tushgan bo'lsa — refund (pulni default codebase qaytaradi).
      if (s.data.paymentStatus === L.PAYMENT_STATUS.ESCROW_FUNDED) {
        patch.paymentStatus = L.assertPaymentTransition(s.data.paymentStatus, L.PAYMENT_STATUS.REFUND_PENDING, 'cancel');
        refundPending += 1;
      }
      batch.update(s.ref, patch);
      for (const legId of (s.data.legIds || [])) legIdsAll.push(legId);
    }
    for (const legId of legIdsAll) {
      const ref = db.collection(DEMANDS).doc(legId);
      const snap = await ref.get();
      if (!snap.exists) continue;
      const st = (snap.data() || {}).status;
      if (sm.canTransition(st, sm.STATUS.CANCELLED)) {
        batch.update(ref, { status: sm.STATUS.CANCELLED, cancelledBy: 'owner', cancelledAt: now, updatedAt: now });
      }
    }
    batch.update(orderRef, { status: 'cancelled', cancelledAt: now, updatedAt: now });
    await batch.commit();

    for (const legId of legIdsAll) await closeOtherMatches(db, legId, null, 'cancelled', now);
    return { ok: true, cancelled: ships.length, refundPending };
  };
}

// ═══════════════════════════════════════════════════════════════════════
// SIRLAR — QR payload va kodlar
// ═══════════════════════════════════════════════════════════════════════

function makeGetShipmentSecrets(deps) {
  const { db } = deps;

  return async function getShipmentSecrets(data, context) {
    const callerId = callerIdFrom(context);
    if (!callerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const shipmentId = String((data || {}).shipmentId || '');
    if (!shipmentId) throw fail('invalid-argument', 'shipmentId majburiy');

    const shipRef = db.collection(L.SHIPMENTS).doc(shipmentId);
    const [shipSnap, secSnap] = await Promise.all([shipRef.get(), shipRef.collection('private').doc('secrets').get()]);
    if (!shipSnap.exists || !secSnap.exists) throw fail('not-found', 'Jo\'natma topilmadi');
    const ship = shipSnap.data() || {};
    const qrSecret = (secSnap.data() || {}).qrSecret;
    const isOwner = ship.ownerId === callerId;
    const cur = ship.currentCustodian || {};
    const isCustodian = cur.kind === L.CUSTODIAN_KIND.PROVIDER && cur.id === callerId;
    if (!isOwner && !isCustodian) throw fail('permission-denied', 'Ruxsat yo\'q');
    if ([L.SHIPMENT_STATUS.DELIVERED, L.SHIPMENT_STATUS.CLOSED, L.SHIPMENT_STATUS.CANCELLED].includes(ship.status)) {
      throw fail('failed-precondition', 'Jo\'natma yakunlangan', 'shipment_closed');
    }

    const out = {
      shipmentId,
      trackingNumber: ship.trackingNumber,
      qrPayload: L.qrPayloadFor(shipmentId, qrSecret),
      handoverCode: L.handoverCodeFor(shipmentId, qrSecret),
    };
    // Yetkazish kodi — FAQAT egasiga (u qabul qiluvchiga yetkazadi).
    if (isOwner) out.deliveryCode = L.deliveryCodeFor(shipmentId, qrSecret);
    return out;
  };
}

// ═══════════════════════════════════════════════════════════════════════
// ADMIN — tarif
// ═══════════════════════════════════════════════════════════════════════

function makeAdminUpsertLogisticsTariff(deps) {
  const { db, now: nowFn } = deps;

  return async function adminUpsertLogisticsTariff(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const adminId = await assertAnalyticsAdmin(db, context);
    const t = (data || {}).tariff;
    if (!t || typeof t !== 'object') throw fail('invalid-argument', 'tariff majburiy');
    const doc = { ...t, module: tariffCore.MODULE, status: tariffCore.STATUS.DRAFT };
    const errors = tariffCore.validateTariff(doc);
    if (errors.length) throw fail('invalid-argument', errors[0], 'tariff_invalid', { errors });

    const ref = db.collection(tariffCore.COLLECTION).doc(tariffCore.versionDocId(doc.version));
    const prev = await ref.get();
    if (prev.exists && (prev.data() || {}).status !== tariffCore.STATUS.DRAFT) {
      // Faol/eski versiya O'ZGARMAS (9-band): yangi versiya ochiladi.
      throw fail('failed-precondition', 'Faol yoki eski versiyani tahrirlab bo\'lmaydi — yangi versiya oching', 'tariff_immutable');
    }
    await ref.set({ ...doc, updatedAt: now, updatedBy: adminId, createdAt: prev.exists ? (prev.data() || {}).createdAt || now : now });
    await db.collection(TARIFF_AUDIT).add({ kind: 'tariff_upsert', version: doc.version, by: adminId, at: now });
    return { version: doc.version, status: tariffCore.STATUS.DRAFT, activationErrors: tariffCore.validateTariff(doc, { forActivation: true }) };
  };
}

function makeAdminActivateLogisticsTariff(deps) {
  const { db, now: nowFn } = deps;

  return async function adminActivateLogisticsTariff(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const adminId = await assertAnalyticsAdmin(db, context);
    const version = Number((data || {}).version);
    if (!isPosInt(version)) throw fail('invalid-argument', 'version');
    const ref = db.collection(tariffCore.COLLECTION).doc(tariffCore.versionDocId(version));
    const ptrRef = db.collection(tariffCore.COLLECTION).doc(tariffCore.POINTER_DOC_ID);

    const out = await db.runTransaction(async (tx) => {
      const [snap, ptr] = await Promise.all([tx.get(ref), tx.get(ptrRef)]);
      if (!snap.exists) throw fail('not-found', 'Tarif versiyasi topilmadi');
      const t = snap.data() || {};
      const errors = tariffCore.validateTariff({ ...t, status: tariffCore.STATUS.ACTIVE }, { forActivation: true });
      if (errors.length) throw fail('failed-precondition', errors[0], 'tariff_incomplete', { errors });
      const prevVersion = ptr.exists ? Number((ptr.data() || {}).activeVersion) || 0 : 0;
      if (prevVersion && prevVersion !== version) {
        tx.set(db.collection(tariffCore.COLLECTION).doc(tariffCore.versionDocId(prevVersion)), {
          status: tariffCore.STATUS.RETIRED, retiredAt: now, retiredBy: adminId,
        }, { merge: true });
      }
      tx.set(ref, { status: tariffCore.STATUS.ACTIVE, activatedAt: now, activatedBy: adminId }, { merge: true });
      tx.set(ptrRef, { activeVersion: version, updatedAt: now, updatedBy: adminId }, { merge: true });
      tx.set(db.collection(TARIFF_AUDIT).doc(), {
        kind: 'tariff_activate', version, previousVersion: prevVersion || null, by: adminId, at: now,
      });
      return { version, previousVersion: prevVersion || null };
    });
    tariffCore.clearCache();
    return out;
  };
}

// ═══════════════════════════════════════════════════════════════════════
// ADMIN — marshrutni qayta rejalash (D-9, D-10)
// ═══════════════════════════════════════════════════════════════════════

function makeAdminPlanShipmentRoute(deps) {
  const { db, now: nowFn } = deps;

  return async function adminPlanShipmentRoute(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const adminId = await assertAnalyticsAdmin(db, context);
    const shipmentId = String((data || {}).shipmentId || '');
    const rawLegs = (data || {}).legs;
    const reason = String((data || {}).reason || '').slice(0, 300);
    if (!shipmentId) throw fail('invalid-argument', 'shipmentId majburiy');
    if (!Array.isArray(rawLegs) || rawLegs.length < 1 || rawLegs.length > 6) {
      throw fail('invalid-argument', 'legs 1..6', 'legs_count');
    }

    const shipRef = db.collection(L.SHIPMENTS).doc(shipmentId);
    const shipSnap = await shipRef.get();
    if (!shipSnap.exists) throw fail('not-found', 'Jo\'natma topilmadi');
    const ship = shipSnap.data() || {};
    if (![L.SHIPMENT_STATUS.AWAITING_PAYMENT, L.SHIPMENT_STATUS.READY].includes(ship.status)) {
      throw fail('failed-precondition', 'Marshrut faqat yo\'lga chiqmagan jo\'natmada o\'zgaradi', 'shipment_not_replannable', { status: ship.status });
    }
    // Zanjir uzluksizligi: birinchi FROM = origin, oxirgi TO = destination.
    const points = [];
    for (let i = 0; i < rawLegs.length; i += 1) {
      const from = i === 0 ? ship.origin : await validatePoint(db, rawLegs[i].from, `legs[${i}].from`);
      const to = i === rawLegs.length - 1 ? ship.destination : await validatePoint(db, rawLegs[i].to, `legs[${i}].to`);
      if (i > 0) {
        const prevTo = points[i - 1].to;
        if (prevTo.regionId !== from.regionId || (prevTo.districtId || '') !== (from.districtId || '')) {
          throw fail('invalid-argument', `legs[${i}].from oldingi LEG'ning to'xtash nuqtasiga mos emas`, 'legs_discontinuous');
        }
      }
      points.push({ from, to });
    }

    const tariffRef = db.collection(tariffCore.COLLECTION).doc(tariffCore.versionDocId(ship.priceSnapshot.tariffVersion));
    const tariffSnap = await tariffRef.get();
    if (!tariffSnap.exists) throw fail('failed-precondition', 'Buyurtma tarifi topilmadi', 'tariff_missing');
    const tariff = tariffSnap.data();
    const adapter = getAdapter(L.MODULE);
    const config = await getModuleConfig(db, L.MODULE, CONFIG_REGION);
    const ttl = Number((config.logistics || {}).legTtlMinutes) || 3 * 24 * 60;

    // Eski LEG'lar: accepted/in_progress bo'lsa — rad (custody boshlangan).
    const oldLegs = [];
    for (const legId of (ship.legIds || [])) {
      const s = await db.collection(DEMANDS).doc(legId).get();
      if (!s.exists) continue;
      const st = (s.data() || {}).status;
      if ([sm.STATUS.ACCEPTED, sm.STATUS.IN_PROGRESS].includes(st)) {
        throw fail('failed-precondition', 'LEG allaqachon ijrochiga tayinlangan', 'leg_assigned', { legId });
      }
      oldLegs.push({ ref: s.ref, id: legId, status: st });
    }

    const version = (Number(ship.routePlanVersion) || 1) + 1;
    const route = buildRoute({ tariff, shipment: ship, points, version });
    const legRefs = route.legs.map(() => db.collection(DEMANDS).doc());
    const legIds = legRefs.map((r) => r.id);
    const orderSnap = await db.collection(L.ORDERS).doc(ship.orderId).get();
    const order = { id: ship.orderId, termsAcceptedAt: (orderSnap.data() || {}).termsAcceptedAt || null };

    const batch = db.batch();
    for (const o of oldLegs) {
      if (sm.canTransition(o.status, sm.STATUS.CANCELLED)) {
        batch.update(o.ref, { status: sm.STATUS.CANCELLED, cancelledBy: 'replan', cancelledAt: now, updatedAt: now });
      }
    }
    for (let i = 0; i < route.legs.length; i += 1) {
      batch.set(legRefs[i], buildLegDemand({
        ownerId: ship.ownerId, order, shipment: ship, shipmentId, leg: route.legs[i],
        legIndex: i, legCount: route.legs.length, legIds, adapter, now, ttlMinutes: ttl,
      }));
      batch.set(legRefs[i].collection('private').doc('stats'), {
        matchedCount: 0, candidateCount: 0, rejectedCount: 0, updatedAt: now,
      });
    }
    const planRef = db.collection(L.ROUTE_PLANS).doc(shipmentId);
    batch.set(planRef, { shipmentId, currentVersion: version, updatedAt: now }, { merge: true });
    batch.set(planRef.collection('versions').doc(String(ship.routePlanVersion || 1)), { supersededAt: now }, { merge: true });
    batch.set(planRef.collection('versions').doc(String(version)), {
      version,
      legs: route.legs.map((l, i) => ({ ...l, legId: legIds[i] })),
      reason: reason || 'replan',
      createdBy: adminId,
      createdAt: now,
      supersededAt: null,
    });
    // `legProblem` eski marshrutning LEG'iga ishora qiladi — yangi reja
    // bilan u ma'nosiz (aks holda admin «LEG'ni qayta ochish» tugmasi eski,
    // bekor qilingan rejaning LEG'ini ochib yuborardi).
    batch.update(shipRef, {
      routePlanVersion: version, legIds, legCount: legIds.length, legAssignments: {},
      legProblem: null, updatedAt: now,
    });
    batch.set(shipRef.collection('private').doc('internal'), {
      platformShare: route.split.platformShare,
      providerPool: route.split.providerPool,
      legPayouts: route.split.legPayouts,
      updatedAt: now,
    }, { merge: true });
    await batch.commit();
    for (const o of oldLegs) await closeOtherMatches(db, o.id, null, 'cancelled', now);

    // To'langan bo'lsa birinchi LEG darhol ochiladi.
    let first = null;
    if (ship.paymentStatus === L.PAYMENT_STATUS.ESCROW_FUNDED) first = await activateLeg(deps, legIds[0]);
    return { version, legIds, legCount: legIds.length, firstLeg: first };
  };
}

// ═══════════════════════════════════════════════════════════════════════
// ADMIN — muddati tugagan LEG'ni qayta ochish (zanjir qotib qolmasin)
// ═══════════════════════════════════════════════════════════════════════

/**
 * `expireDemandsSweeper` LEG'ni `expired` qilib, jo'natmaga `legProblem`
 * yozadi (jo'natma `ready`/`in_transit`da qoladi, pul eskrouda). Admin shu
 * callable bilan o'sha LEG'ni qayta ochadi: muddat qaytadan, matching +
 * push qaytadan, payout va marshrut O'ZGARMAYDI. Audit (41-band).
 */
function makeAdminReactivateLeg(deps) {
  const { db, now: nowFn } = deps;

  return async function adminReactivateLeg(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const adminId = await assertAnalyticsAdmin(db, context);
    const legId = String((data || {}).legId || '');
    const reason = String((data || {}).reason || '').slice(0, 300);
    if (!legId) throw fail('invalid-argument', 'legId majburiy');

    const legRef = db.collection(DEMANDS).doc(legId);
    const legSnap = await legRef.get();
    if (!legSnap.exists) throw fail('not-found', 'LEG topilmadi');
    const leg = legSnap.data() || {};
    if (leg.module !== L.MODULE) throw fail('failed-precondition', 'Bu jo\'natma emas', 'not_logistics');
    if (leg.status !== sm.STATUS.EXPIRED) {
      throw fail('failed-precondition', 'LEG muddati tugamagan — qayta ochish shart emas', 'leg_not_expired', { status: leg.status });
    }
    const shipmentId = String((leg.attributes || {}).shipmentId || '');
    const shipRef = db.collection(L.SHIPMENTS).doc(shipmentId);
    const shipSnap = await shipRef.get();
    if (!shipSnap.exists) throw fail('failed-precondition', 'Jo\'natma topilmadi', 'shipment_missing');
    const ship = shipSnap.data() || {};
    if (![L.SHIPMENT_STATUS.READY, L.SHIPMENT_STATUS.IN_TRANSIT].includes(ship.status)) {
      throw fail('failed-precondition', 'Jo\'natma holati qayta ochishga mos emas', 'shipment_not_ready', { status: ship.status });
    }
    // Faqat JORIY marshrut rejasining LEG'i. Qayta rejalashdan keyin eski
    // `expired` LEG `cancelled`ga o'ta olmaydi (state machine) va o'sha
    // holatda qoladi — uni ochish eski payout bilan ikkinchi, «etim» LEG'ni
    // jonlantirardi (13/15-band: shipment/LEG/custody zanjiri buziladi).
    if (!Array.isArray(ship.legIds) || !ship.legIds.includes(legId)) {
      throw fail('failed-precondition', 'Bu LEG joriy marshrutda yo\'q (qayta rejalangan)', 'leg_superseded', { legId });
    }
    // Modul o'chiq bo'lsa `activateLeg` LEG'ni ochmaydi — eski match
    // yozuvlarini o'chirishdan OLDIN tekshiramiz (aks holda LEG `expired`da
    // qolib, match tarixi yo'qolardi).
    const preFlags = await resolveFlags(db, L.MODULE, CONFIG_REGION);
    if (!preFlags.enabled) {
      throw fail('failed-precondition', 'Logistika moduli o\'chiq', 'module_disabled');
    }

    // Eski match yozuvlari (`expired`) — matching qaytadan yozadi; eski
    // yozuv qolsa ijrochi inbox'ida «yopiq» bo'lib ko'rinmay qolardi.
    const old = await db.collection(MATCHES).where('demandId', '==', legId).get();
    for (const m of old.docs) await m.ref.delete();

    const res = await activateLeg(deps, legId, { allowExpired: true, reason: 'admin_reactivate' });
    if (!res.activated) throw fail('failed-precondition', 'LEG qayta ochilmadi', 'leg_reactivate_failed', res);

    await shipRef.update({ legProblem: null, updatedAt: now });
    await db.collection(TARIFF_AUDIT).add({
      kind: 'leg_reactivate', legId, shipmentId, by: adminId, reason, at: now,
    });
    return { ok: true, legId, shipmentId, matchedBucket: res.matchedBucket };
  };
}

module.exports = {
  TARIFF_AUDIT,
  MAX_PARCELS,
  CONFIG_REGION,
  validatePoint,
  validateParcels,
  validateRecipient,
  buildLegDemand,
  buildRoute,
  activateLeg,
  recomputeOrderStatus,
  makeQuoteLogisticsOrder,
  makeGetLogisticsAccess,
  makeCreateLogisticsOrder,
  makeOnShipmentFunded,
  makeAcceptLeg,
  makeScanHandover,
  makeConfirmDelivery,
  makeCancelLogisticsOrder,
  makeGetShipmentSecrets,
  makeAdminUpsertLogisticsTariff,
  makeAdminActivateLogisticsTariff,
  makeAdminPlanShipmentRoute,
  makeAdminReactivateLeg,
};
