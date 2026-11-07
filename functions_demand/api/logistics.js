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

const { callerIdFrom, toCanonicalId, candidateIdsFor } = require('../core/ids');
const { resolveFlags, getModuleConfig, clearCache: clearConfigCache } = require('../core/config');
const sm = require('../core/state_machine');
const tariffCore = require('../core/tariff');
const L = require('../core/logistics');
const relaySplit = require('../core/relay_split');
const { getAdapter } = require('../core/registry');
const { runMatching, hardFilterReason, attachStats } = require('../matching/orchestrator');
const capabilitiesSource = require('../sources/capabilities');
const { SERVICES_BY_LEG_KIND } = require('../sources/logistics_candidates');
const caps = require('../core/capabilities');
const geoHash = require('../geo/geo_hash');
const { assertAnalyticsAdmin, assertStrictAdmin } = require('../analytics/access');

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

/**
 * E'lon qilingan qiymat (declaredValue) MAJBURIY (ega qarori 2026-10-16, D1):
 * posilka yo'qolsa mijozga aynan shu summa (G) qaytariladi — qiymatsiz
 * jo'natma qabul qilinmaydi. Yo'q / null / 0 / manfiy -> `declared_value_required`;
 * butun son bo'lmasa -> avvalgidek `parcel_invalid`. Haq hisobi (declaredValueFee)
 * va tarif chegarasi (`over_declared_value`) `core/tariff.js`da O'ZGARMAGAN.
 * Yangi qoida FAQAT shu yerda (quote ham, create ham shu validatsiyadan o'tadi);
 * `quoteParcel` toza hisob funksiyasi bo'lib qoladi (paritet fixturasi 0 ni ishlatadi).
 */
function validateParcel(raw, i) {
  const p = raw && typeof raw === 'object' ? raw : {};
  const out = {
    actualWeightG: p.actualWeightG,
    lengthCm: p.lengthCm,
    widthCm: p.widthCm,
    heightCm: p.heightCm,
    declaredValue: p.declaredValue,
    description: String(p.description || '').slice(0, 200),
    fragile: p.fragile === true,
  };
  for (const k of ['actualWeightG', 'lengthCm', 'widthCm', 'heightCm']) {
    if (!isPosInt(out[k])) throw fail('invalid-argument', `parcels[${i}].${k} musbat butun son bo'lishi kerak`, 'parcel_invalid');
  }
  if (out.declaredValue === undefined || out.declaredValue === null || out.declaredValue === '') {
    throw fail('invalid-argument', `parcels[${i}].declaredValue majburiy (posilka qiymati, so'm)`, 'declared_value_required');
  }
  if (!isInt(out.declaredValue)) {
    throw fail('invalid-argument', `parcels[${i}].declaredValue butun so'm`, 'parcel_invalid');
  }
  if (out.declaredValue <= 0) {
    throw fail('invalid-argument', `parcels[${i}].declaredValue musbat bo'lishi kerak`, 'declared_value_required');
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

function assertModuleEnabled(flags) {
  if (!flags.enabled) {
    throw fail('unavailable', flags.killReason
      ? 'Xizmat vaqtincha to\'xtatilgan'
      : 'Jo\'natma xizmati sizning hududingizda hali ishga tushmagan', 'module_disabled');
  }
}

async function requireEnabled(db, callerId) {
  const flags = await resolveFlags(db, L.MODULE, CONFIG_REGION);
  assertModuleEnabled(flags);
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
  ownerId, order, shipment, shipmentId, leg, legIndex, legCount, legIds, adapter, now, ttlMinutes, chainMode,
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
      // Faqat `assemble_all` (2026-11-07): `sequential` LEG hujjati shakli O'ZGARMAGAN.
      ...(chainMode ? { chainMode } : {}),
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

/**
 * `assemble_all` (ega qarori 2026-11-07): marshrut transfer nuqtalari bo'yicha
 * avtomatik bo'linadi (`core/relay_split.js`). Oraliq markaz tumani `geo_*`da
 * yo'q / viloyatga mos emas bo'lsa — xuddi markaz yo'qdek bitta to'g'ridan-to'g'ri
 * LEG (mavjud xatti-harakat) va `TRANSFER_POINT_MISSING` log (24-band, PII'siz).
 */
async function planChainSegments(db, origin, destination, config, logCtx) {
  const tp = ((config || {}).logistics || {}).transferPoints || {};
  const plan = relaySplit.planRelayPoints(origin, destination, tp);
  const direct = [{ from: origin, to: destination }];
  const warn = (extra) => console.warn(JSON.stringify({
    action: 'createLogisticsOrder.split', result: 'fallback_direct',
    errorCode: relaySplit.ERROR_TRANSFER_POINT_MISSING, ...(logCtx || {}), ...extra,
  }));
  if (plan.fallback) {
    warn({ missingRegionIds: plan.fallback.missingRegionIds });
    return direct;
  }
  for (const p of plan.points.slice(1, -1)) {
    try {
      await validatePoint(db, p, 'transferPoint');
    } catch (e) {
      warn({ regionId: p.regionId, districtId: p.districtId, why: (e.details || {}).reason || e.message });
      return direct;
    }
  }
  return plan.segments;
}

/**
 * Admin per-jo'natma payout (2026-11-07): `[{legIndex, amount}]`, butun so'm,
 * har LEG AYNAN bir marta, yig'indi = `providerPool` (platforma ulushi o'zgarmaydi).
 * Noto'g'ri bo'lsa — `invalid-argument` (`payout_override_invalid`).
 */
function applyPayoutOverrides(route, raw) {
  if (raw === undefined || raw === null) return null;
  const n = route.legs.length;
  if (!Array.isArray(raw) || raw.length !== n) {
    throw fail('invalid-argument', `payoutOverrides: har LEG uchun bittadan (${n} ta)`, 'payout_override_invalid');
  }
  const amounts = new Array(n).fill(null);
  for (const o of raw) {
    const idx = (o || {}).legIndex;
    const amount = (o || {}).amount;
    if (!isInt(idx) || idx < 0 || idx >= n || amounts[idx] !== null) {
      throw fail('invalid-argument', 'payoutOverrides: legIndex noto\'g\'ri yoki takror', 'payout_override_invalid');
    }
    if (!isPosInt(amount) || !Number.isSafeInteger(amount)) {
      throw fail('invalid-argument', 'payoutOverrides: summa musbat butun so\'m', 'payout_override_invalid');
    }
    amounts[idx] = amount;
  }
  const sum = amounts.reduce((s, a) => s + a, 0);
  if (sum !== route.split.providerPool) {
    throw fail('invalid-argument', `payoutOverrides yig'indisi ${route.split.providerPool} bo'lishi kerak`,
      'payout_override_sum', { expected: route.split.providerPool, got: sum });
  }
  const before = route.legs.map((l) => l.payout);
  route.legs.forEach((l, i) => { l.payout = amounts[i]; });
  route.split.legPayouts = route.split.legPayouts.map((p, i) => ({ ...p, amount: amounts[i] }));
  return { before, after: amounts };
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
    // Zanjir rejimi buyurtma paytida MUHRLANADI (jo'natma `chain.mode`): konfig
    // keyin o'zgarsa ham eski jo'natma o'z rejimida yakunlanadi.
    const chainMode = L.chainModeOf(config);
    const assemble = chainMode === L.CHAIN_MODE.ASSEMBLE_ALL;
    const segments = assemble
      ? await planChainSegments(db, q.origin, q.destination, config, { requestId: clientRequestId })
      : [{ from: q.origin, to: q.destination }];

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
      const legRefs = segments.map(() => db.collection(DEMANDS).doc());
      const legIds = legRefs.map((r) => r.id);
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
        legIds,
        legCount: legIds.length,
        assignedProviderIds: [],
        custodyCount: 0,
        createdAt: now,
        updatedAt: now,
      };
      if (assemble) {
        shipment.chain = {
          mode: chainMode,
          state: L.CHAIN_STATE.ASSEMBLING,
          deadlineAt: null,
          lockedAt: null,
          claimed: 0,
          legCount: legIds.length,
          selfTransferLegIds: [],
        };
      }
      // Payout'lar — MAVJUD splitInternal (LEG turi bo'yicha, admin tarifi).
      const route = buildRoute({
        tariff: q.tariff, shipment, version: 1, points: segments,
      });

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
        legs: route.legs.map((l, k) => ({ ...l, legId: legIds[k] })),
        reason: 'initial',
        createdBy: 'system',
        createdAt: now,
        supersededAt: null,
      });
      for (let k = 0; k < route.legs.length; k += 1) {
        batch.set(legRefs[k], buildLegDemand({
          ownerId, order, shipment, shipmentId: shipmentRef.id, leg: route.legs[k],
          legIndex: k, legCount: route.legs.length, legIds, adapter, now, ttlMinutes: ttl,
          chainMode: assemble ? chainMode : undefined,
        }));
        batch.set(legRefs[k].collection('private').doc('stats'), {
          matchedCount: 0, candidateCount: 0, rejectedCount: 0, updatedAt: now,
        });
      }
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
    // Idempotentlik hujjati AYNI atomik yozuvda va `create()` bilan (audit L5):
    // yuqoridagi `get` tekshiruvi tranzaksiyasiz — ikki parallel chaqiruv ikkalasi
    // ham «yo'q» deb ko'rib ikkita ORDER yaratardi. `create()` hujjat bor bo'lsa
    // butun batch'ni rad etadi (ALREADY_EXISTS) → hech narsa yozilmaydi,
    // g'olibning natijasi qaytariladi. (Yutqazgan chaqiruv tracking raqamini
    // band qilgan bo'lishi mumkin — raqamda tirqish, ORDER yo'q.)
    batch.create(idemRef, {
      ownerId, kind: 'logistics_order', orderId: orderRef.id, shipmentIds, createdAt: now,
    });
    try {
      await batch.commit();
    } catch (e) {
      if (e && (e.code === 6 || e.code === 'already-exists')) {
        const won = await idemRef.get();
        if (won.exists) {
          const d = won.data() || {};
          return { orderId: d.orderId, shipmentIds: d.shipmentIds || [], duplicate: true };
        }
      }
      throw e;
    }

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
 * `opts.resetMatches` — g'olib ochuvchi eski match'larni o'chiradi (pastda).
 *
 * Holat o'tishi TRANZAKSIYADA (2026-10-10, emulatorda isbotlangan): avval
 * LEG tranzaksiyasiz o'qilib, keyin yozilardi —
 *   - to'lov triggeri ↔ qayta rejalash: bekor qilingan eski LEG qayta ochilardi;
 *   - trigger takrori: kuryer olgan (`accepted`) LEG `active`ga qaytardi,
 *     matching uning match'ini `new` qilardi;
 *   - ikki admin qayta ochishi: ikkinchisi birinchining yangi match'larini o'chirardi.
 * Endi faqat BITTA chaqiruv ochadi; joriy marshrutda yo'q LEG ochilmaydi.
 */
async function activateLeg(deps, legId, opts = {}) {
  const { db, now: nowFn } = deps;
  const now = nowFn ? nowFn() : new Date();
  const ref = db.collection(DEMANDS).doc(legId);
  const snap = await ref.get();
  if (!snap.exists) return { skipped: 'missing' };
  const pre = snap.data() || {};
  if (pre.module !== L.MODULE) return { skipped: 'not_logistics' };
  const allowed = opts.allowExpired ? [sm.STATUS.DRAFT, sm.STATUS.EXPIRED] : [sm.STATUS.DRAFT];
  if (!allowed.includes(pre.status)) return { skipped: `status_${pre.status}` };

  const flags = await resolveFlags(db, L.MODULE, CONFIG_REGION);
  if (!flags.enabled) return { skipped: 'disabled' };
  const config = flags.config;
  const ttl = Number((config.logistics || {}).legTtlMinutes) || 3 * 24 * 60;

  const shipmentId = String((pre.attributes || {}).shipmentId || '');
  const shipRef = shipmentId ? db.collection(L.SHIPMENTS).doc(shipmentId) : null;
  const claim = await db.runTransaction(async (tx) => {
    const [legSnap, shipSnap] = await Promise.all([tx.get(ref), shipRef ? tx.get(shipRef) : null]);
    if (!legSnap.exists) return { skipped: 'missing' };
    const d = legSnap.data() || {};
    // Boshqa chaqiruv allaqachon ochdi / kuryer oldi / bekor qilindi.
    if (!allowed.includes(d.status)) return { skipped: `status_${d.status}` };
    const shipData = shipSnap && shipSnap.exists ? (shipSnap.data() || {}) : null;
    const legIds = shipData ? shipData.legIds : null;
    if (Array.isArray(legIds) && !legIds.includes(legId)) return { skipped: 'superseded' };

    // `assemble_all` (2026-11-07): yig'ish paytida LEG muddati = zanjir muddati
    // (alohida LEG o'z TTL'i bilan erta yopilib, zanjirni «teshik» qilmasin).
    // Zanjir yig'ilmayotgan bo'lsa (expired/cancelled) — LEG ochilmaydi.
    let expiresAt = new Date(now.getTime() + ttl * 60000);
    if (shipData && L.isAssembleAll(shipData)) {
      const chain = shipData.chain || {};
      if (chain.state === L.CHAIN_STATE.ASSEMBLING) {
        if (!chain.deadlineAt) return { skipped: 'chain_not_funded' };
        expiresAt = new Date(sm.toMillis(chain.deadlineAt));
      } else if (chain.state !== L.CHAIN_STATE.LOCKED) {
        return { skipped: `chain_${chain.state}` };
      }
    }

    sm.assertTransition(d.status, sm.STATUS.ACTIVE, 'activateLeg');
    const patch = {
      status: sm.STATUS.ACTIVE,
      'timeWindow.expiresAt': expiresAt,
      activatedAt: now,
      updatedAt: now,
    };
    if (d.status === sm.STATUS.EXPIRED) {
      patch.reopenedAt = now;
      patch.reopenReason = opts.reason || 'admin_reactivate';
      patch.reopenCount = Number(d.reopenCount || 0) + 1;
      patch.expiredAt = null;
    }
    tx.update(ref, patch);
    return { d };
  });
  if (claim.skipped) return claim;
  const d = claim.d;

  if (opts.resetMatches) await deleteStaleMatches(db, legId);

  const matchResult = await matchAndNotifyLeg(deps, legId, { ...d, status: sm.STATUS.ACTIVE }, flags, now);
  return { activated: true, matchedBucket: matchResult ? matchResult.matchedBucket : '0' };
}

/**
 * `active` LEG uchun matching + push (activateLeg'dan ajratildi, 2026-11-07:
 * zanjir LEG'i bo'shatilganda / admin qayta ochganda QAYTA matching — xuddi
 * shu yo'l). `demand_matches` qayta yoziladi (`new`); push `demand_push_log`
 * bo'yicha takrorlanmaydi (avval push olgan ijrochiga ikkinchi push yo'q).
 */
async function matchAndNotifyLeg(deps, legId, d, flags, now) {
  const { db, keywordIndex, notify } = deps;
  const ref = db.collection(DEMANDS).doc(legId);
  const config = flags.config;
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
  return matchResult;
}

/**
 * Zanjir LEG'ini QAYTA matching (ijrochi yig'ish paytida bo'shatdi —
 * `cancelAssignment` → `onReopened`; yoki admin qulfdan keyin qayta ochdi).
 * Faqat `active` LEG; modul o'chiq bo'lsa — hech narsa (LEG `active`da qoladi,
 * zanjir sweeper'i muddatda yopadi).
 */
async function rematchLeg(deps, legId) {
  const { db, now: nowFn } = deps;
  const now = nowFn ? nowFn() : new Date();
  const snap = await db.collection(DEMANDS).doc(legId).get();
  if (!snap.exists) return { skipped: 'missing' };
  const d = snap.data() || {};
  if (d.module !== L.MODULE) return { skipped: 'not_logistics' };
  if (d.status !== sm.STATUS.ACTIVE) return { skipped: `status_${d.status}` };
  const flags = await resolveFlags(db, L.MODULE, CONFIG_REGION);
  if (!flags.enabled) return { skipped: 'disabled' };
  const r = await matchAndNotifyLeg(deps, legId, d, flags, now);
  return { rematched: true, matchedBucket: r ? r.matchedBucket : '0' };
}

/** `cancelAssignment` → `onReopened` (index.js): faqat `assemble_all` LEG'i qayta matching. */
function makeOnLegReopened(deps) {
  return async function onLegReopened({ demandId, demand }) {
    const a = (demand || {}).attributes || {};
    if ((demand || {}).module !== L.MODULE || a.chainMode !== L.CHAIN_MODE.ASSEMBLE_ALL) {
      return { skipped: 'not_chain_leg' };
    }
    const r = await rematchLeg(deps, demandId);
    console.log(JSON.stringify({
      action: 'onLegReopened', legId: demandId, shipmentId: a.shipmentId || null, result: r,
    }));
    return r;
  };
}

/**
 * Qayta ochilgan LEG'ning eski match'lari (`expired`) — matching qaytadan
 * yozadi; eski yozuv qolsa ijrochi inbox'ida «yopiq» bo'lib ko'rinmay qolardi.
 * LEG allaqachon `active`: oraliqda kimdir olsa, uning match'i o'zgargan —
 * `lastUpdateTime` sharti uni O'CHIRMAYDI (xato yutiladi, yozuv qoladi).
 */
async function deleteStaleMatches(db, legId) {
  const old = await db.collection(MATCHES).where('demandId', '==', legId).get();
  for (const m of old.docs) {
    try {
      await (m.updateTime ? m.ref.delete({ lastUpdateTime: m.updateTime }) : m.ref.delete());
    } catch (e) {
      console.warn(`eski match o'chirilmadi (${m.id}): ${e.message}`);
    }
  }
}

/** Trigger: shipments/{id} `paymentStatus` → escrow_funded bo'lganda LEG-1. */
function makeOnShipmentFunded(deps) {
  return async function onShipmentFunded(before, after, shipmentId) {
    const was = (before || {}).paymentStatus;
    const is = (after || {}).paymentStatus;
    if (is !== L.PAYMENT_STATUS.ESCROW_FUNDED || was === is) return { skipped: 'no_change' };
    const legIds = Array.isArray(after.legIds) ? after.legIds : [];
    if (!legIds.length) return { skipped: 'no_legs' };
    if (L.isAssembleAll(after)) return activateChain(deps, shipmentId);
    const r = await activateLeg(deps, legIds[0]);
    console.log(`onShipmentFunded ${shipmentId}: ${JSON.stringify(r)}`);
    return r;
  };
}

/**
 * `assemble_all` (ega qarori 2026-11-07): to'lov tushdi → yig'ish muddati
 * (`chain.deadlineAt = fundedAt + chainAssemblyHours`, soat to'lov paytidan —
 * pul to'langan) BIR MARTA tranzaksiyada yoziladi (trigger takrori muddatni
 * cho'zmaydi), so'ng BARCHA draft LEG mavjud `activateLeg` bilan ochiladi
 * (matching + har LEG mos ijrochilariga push). `activateLeg` idempotent.
 */
async function activateChain(deps, shipmentId) {
  const { db, now: nowFn } = deps;
  const now = nowFn ? nowFn() : new Date();
  const config = await getModuleConfig(db, L.MODULE, CONFIG_REGION);
  const hours = L.chainAssemblyHoursOf(config);
  const shipRef = db.collection(L.SHIPMENTS).doc(shipmentId);
  const st = await db.runTransaction(async (tx) => {
    const snap = await tx.get(shipRef);
    if (!snap.exists) return { skipped: 'missing' };
    const ship = snap.data() || {};
    const chain = ship.chain || {};
    if (ship.paymentStatus !== L.PAYMENT_STATUS.ESCROW_FUNDED) return { skipped: `payment_${ship.paymentStatus}` };
    if (chain.state !== L.CHAIN_STATE.ASSEMBLING) return { skipped: `chain_${chain.state}` };
    const legIds = Array.isArray(ship.legIds) ? ship.legIds : [];
    if (chain.deadlineAt) return { legIds, deadlineAt: chain.deadlineAt, already: true };
    const deadlineAt = L.chainDeadlineFrom(ship.fundedAt || now, hours);
    tx.update(shipRef, { 'chain.deadlineAt': deadlineAt, updatedAt: now });
    return { legIds, deadlineAt, already: false };
  });
  if (st.skipped) {
    console.log(JSON.stringify({ action: 'onShipmentFunded.chain', shipmentId, result: 'skipped', reason: st.skipped }));
    return st;
  }
  const results = [];
  for (const legId of st.legIds) {
    try {
      results.push(await activateLeg(deps, legId));
    } catch (e) {
      // Bitta LEG yiqilsa qolganlari ochilaveradi; draft qolgani legChainSweeper ochadi.
      results.push({ error: true });
      console.error(JSON.stringify({
        action: 'onShipmentFunded.chain', result: 'error', errorCode: 'LEG_ACTIVATE_FAILED',
        shipmentId, legId, message: e.message,
      }));
    }
  }
  const activated = results.filter((r) => r && r.activated).length;
  console.log(JSON.stringify({
    action: 'onShipmentFunded.chain', shipmentId, result: 'ok', legCount: st.legIds.length, activated,
    deadlineAlreadySet: st.already,
  }));
  return { chain: true, activated, legCount: st.legIds.length, results };
}

/**
 * SWEEPER: zanjir qotib qolmasin (audit L3c). LEG ochilishi uch joyda
 * «bir martalik» edi va xatosi faqat logga tushardi:
 *   - eskrou triggeri (`onShipmentFunded`) -> LEG-1;
 *   - `scanHandover` -> keyingi LEG;
 *   - `adminPlanShipmentRoute` -> yangi LEG-1.
 * Biri yiqilsa LEG `draft`da qoladi, kuryerga ko'rinmaydi, pul eskrouda.
 *
 * Bu sweeper TO'LANGAN (`escrow_funded`) jo'natmalarning ochilishi KERAK
 * bo'lgan BITTA LEG'ini tekshiradi va `draft` bo'lsa mavjud `activateLeg`ni
 * chaqiradi (u tranzaksion va idempotent: boshqa chaqiruv ochgan / bekor
 * qilingan / joriy marshrutda yo'q LEG'ni `skipped` qiladi):
 *   - `ready` jo'natma (hali olinmagan) -> LEG-1 (`legIds[0]`);
 *   - `in_transit` jo'natma -> `currentLegId`dan keyingi LEG (faqat
 *     `openNextLegOn: 'in_progress'` bo'lganda — scanHandover bilan bir xil).
 * Jo'natma uchun faqat 1 ta LEG hujjati o'qiladi (N+1 emas).
 *
 * Chegara: holat bo'yicha tenglik filtri + hujjat ID tartibi (yangi indeks
 * kerak emas), sahifa `batchSize`, bir aylanishda eng ko'pi `maxPages` sahifa.
 * Soni chegaradan oshsa `truncated: true` logga tushadi (jim yo'qolmaydi).
 * Yo'lda/tayyor jo'natmalar yetkazilgach shu holatlardan chiqadi.
 */
function makeLegChainSweeper(deps) {
  const { db, batchSize = 100, maxPages = 10 } = deps;

  return async function legChainSweeper() {
    const startedAt = Date.now();
    // Zanjir muddati (assemble_all) — modul o'chiq bo'lsa HAM: bu pulni
    // qaytarish (refund) yo'li, kill switch uni to'xtatmasin.
    const expiry = await sweepExpiredChains(deps);
    const flags = await resolveFlags(db, L.MODULE, CONFIG_REGION);
    if (!flags.enabled) {
      console.log(JSON.stringify({ action: 'legChainSweeper', result: 'skipped', reason: 'disabled', chainExpired: expiry.expired }));
      return { scanned: 0, opened: 0, failed: 0, truncated: false, skipped: 'disabled', chainExpired: expiry.expired };
    }
    const openNext = (((flags.config || {}).logistics || {}).openNextLegOn || 'in_progress') === 'in_progress';
    const out = { scanned: 0, opened: 0, failed: 0, truncated: false, chainExpired: expiry.expired };

    const openDraft = async (shipmentId, legId, idx) => {
      try {
        const ls = await db.collection(DEMANDS).doc(legId).get();
        if (!ls.exists || (ls.data() || {}).status !== sm.STATUS.DRAFT) return;
        const r = await activateLeg(deps, legId);
        if (r && r.activated) out.opened += 1;
        console.log(JSON.stringify({
          action: 'legChainSweeper.activate', shipmentId, legId, legIndex: idx, result: r,
        }));
      } catch (e) {
        out.failed += 1;
        console.error(JSON.stringify({
          action: 'legChainSweeper.activate', result: 'error', errorCode: 'LEG_ACTIVATE_FAILED',
          shipmentId, legId, message: e.message,
        }));
      }
    };

    const handle = async (shipmentId, ship, status) => {
      if (ship.paymentStatus !== L.PAYMENT_STATUS.ESCROW_FUNDED) return;
      const legIds = Array.isArray(ship.legIds) ? ship.legIds : [];
      if (L.isAssembleAll(ship)) {
        // Yig'ish paytida BARCHA draft LEG ochilishi kerak (trigger yiqilgan bo'lsa).
        // Muddat yozilmagan bo'lsa — avval activateChain (u muddatni yozadi va ochadi).
        const chain = ship.chain || {};
        if (chain.state !== L.CHAIN_STATE.ASSEMBLING) return;
        if (!chain.deadlineAt) {
          try { await activateChain(deps, shipmentId); } catch (e) {
            out.failed += 1;
            console.error(JSON.stringify({
              action: 'legChainSweeper.chain', result: 'error', errorCode: 'CHAIN_ACTIVATE_FAILED', shipmentId, message: e.message,
            }));
          }
          return;
        }
        for (let i = 0; i < legIds.length; i += 1) await openDraft(shipmentId, legIds[i], i);
        return;
      }
      let idx = 0;
      if (status === L.SHIPMENT_STATUS.IN_TRANSIT) {
        const cur = legIds.indexOf(ship.currentLegId);
        if (cur < 0 || !openNext) return;
        idx = cur + 1;
      }
      if (idx >= legIds.length) return;
      await openDraft(shipmentId, legIds[idx], idx);
    };

    for (const status of [L.SHIPMENT_STATUS.READY, L.SHIPMENT_STATUS.IN_TRANSIT]) {
      let last = null;
      for (let page = 0; page < maxPages; page += 1) {
        let q = db.collection(L.SHIPMENTS).where('status', '==', status).orderBy('__name__').limit(batchSize);
        if (last) q = q.startAfter(last);
        const snap = await q.get();
        for (const sd of snap.docs) {
          out.scanned += 1;
          await handle(sd.id, sd.data() || {}, status);
        }
        if (snap.size < batchSize) break;
        last = snap.docs[snap.docs.length - 1];
        if (page === maxPages - 1) out.truncated = true;
      }
    }
    console.log(JSON.stringify({ action: 'legChainSweeper', result: 'ok', ...out, durationMs: Date.now() - startedAt }));
    return out;
  };
}

// ═══════════════════════════════════════════════════════════════════════
// ZANJIR MUDDATI (assemble_all, ega qarori 2026-11-07)
// ═══════════════════════════════════════════════════════════════════════

/**
 * Ilova ichidagi xabar matni — PROPOSED (ega tahrirlaydi), 3 tilda
 * (uz_Cyrl + uz_Latn + ru). `title`/`body` — mavjud `admin_news` o'quvchisi
 * uchun (Lotin, `capabilities.js` TAXI_DUE_NEWS bilan bir xil naqsh), `i18n` — qo'shimcha.
 */
const CHAIN_EXPIRED_NEWS = {
  sender: {
    uz_Latn: { title: 'Jo\'natma bekor qilindi', body: 'Belgilangan muddatda barcha kuryerlar topilmadi. To\'lov hamyoningizga qaytariladi.' },
    uz_Cyrl: { title: 'Жўнатма бекор қилинди', body: 'Белгиланган муддатда барча курьерлар топилмади. Тўлов ҳамёнингизга қайтарилади.' },
    ru: { title: 'Отправка отменена', body: 'За отведённое время не удалось найти всех курьеров. Оплата будет возвращена на ваш кошелёк.' },
  },
  courier: {
    uz_Latn: { title: 'Jo\'natma bekor qilindi', body: 'Marshrutning hamma qismiga kuryer topilmadi — siz olgan qism ham bekor bo\'ldi.' },
    uz_Cyrl: { title: 'Жўнатма бекор қилинди', body: 'Маршрутнинг ҳамма қисмига курьер топилмади — сиз олган қисм ҳам бекор бўлди.' },
    ru: { title: 'Отправка отменена', body: 'Не удалось найти курьеров на все участки маршрута — ваш участок тоже отменён.' },
  },
};

/**
 * Muddati o'tgan yig'ilayotgan zanjirlar. So'rov: `chain.state == assembling`
 * VA `chain.deadlineAt <= now` — kompozit indeks (`relay_chain_indexes.json`).
 * Chegara: `batchSize`; har jo'natma alohida tranzaksiyada qayta tekshiriladi.
 */
async function sweepExpiredChains(deps) {
  const { db, now: nowFn, batchSize = 100 } = deps;
  const now = nowFn ? nowFn() : new Date();
  const out = { expired: 0, failed: 0 };
  let snap;
  try {
    snap = await db.collection(L.SHIPMENTS)
      .where('chain.state', '==', L.CHAIN_STATE.ASSEMBLING)
      .where('chain.deadlineAt', '<=', now)
      .limit(batchSize)
      .get();
  } catch (e) {
    console.error(JSON.stringify({ action: 'legChainSweeper.chainExpiry', result: 'error', errorCode: 'CHAIN_EXPIRY_QUERY_FAILED', message: e.message }));
    out.failed += 1;
    return out;
  }
  for (const d of snap.docs) {
    try {
      const r = await expireChain(deps, d.id, now);
      if (r && r.expired) out.expired += 1;
    } catch (e) {
      out.failed += 1;
      console.error(JSON.stringify({
        action: 'legChainSweeper.chainExpiry', result: 'error', errorCode: 'CHAIN_EXPIRE_FAILED', shipmentId: d.id, message: e.message,
      }));
    }
  }
  return out;
}

/**
 * Bitta zanjir: TRANZAKSIYADA qayta tekshiriladi (shu orada oxirgi LEG olinib
 * qulflangan / egasi bekor qilgan bo'lsa — tegilmaydi). Yozuv:
 *   - SHIPMENT `ready → cancelled` (`cancelledBy: 'assembly_expired'`),
 *     `chain.state = expired`, eskrou → `refund_pending` (mavjud refund yo'li:
 *     `functions/relay_escrow.js`, kalit `relayRefund:{id}` — idempotent);
 *   - barcha LEG → `cancelled`; `logistics_audit` (16-band).
 * Tranzaksiyadan KEYIN: match'lar yopiladi, ORDER holati, ilova ichidagi xabar
 * (jo'natuvchi + LEG olgan kuryerlar; hujjat ID deterministik — takror yo'q).
 */
async function expireChain(deps, shipmentId, now) {
  const { db } = deps;
  const shipRef = db.collection(L.SHIPMENTS).doc(shipmentId);
  const out = await db.runTransaction(async (tx) => {
    const snap = await tx.get(shipRef);
    if (!snap.exists) return { skipped: 'missing' };
    const ship = snap.data() || {};
    const chain = ship.chain || {};
    if (!L.isAssembleAll(ship) || chain.state !== L.CHAIN_STATE.ASSEMBLING) return { skipped: `chain_${chain.state}` };
    if (!chain.deadlineAt || sm.toMillis(chain.deadlineAt) > now.getTime()) return { skipped: 'not_due' };
    if ((Number(ship.custodyCount) || 0) > 0 || !L.canTransitionShipment(ship.status, L.SHIPMENT_STATUS.CANCELLED)) {
      // Yig'ilmagan zanjirda custody bo'lishi mumkin emas (pickup qulfni talab qiladi).
      return { skipped: 'not_cancellable', status: ship.status };
    }
    const legIds = Array.isArray(ship.legIds) ? ship.legIds : [];
    const legSnaps = await Promise.all(legIds.map((id) => tx.get(db.collection(DEMANDS).doc(id))));

    const patch = {
      status: L.assertShipmentTransition(ship.status, L.SHIPMENT_STATUS.CANCELLED, 'chainExpired'),
      cancelledAt: now,
      cancelledBy: 'assembly_expired',
      'chain.state': L.CHAIN_STATE.EXPIRED,
      updatedAt: now,
    };
    let refund = false;
    if (ship.paymentStatus === L.PAYMENT_STATUS.ESCROW_FUNDED) {
      patch.paymentStatus = L.assertPaymentTransition(ship.paymentStatus, L.PAYMENT_STATUS.REFUND_PENDING, 'chainExpired');
      refund = true;
    }
    tx.update(shipRef, patch);
    const couriers = [];
    for (const s of legSnaps) {
      if (!s.exists) continue;
      const l = s.data() || {};
      const p = (l.assignment || {}).providerId;
      if (p && l.status === sm.STATUS.ACCEPTED && !couriers.includes(p)) couriers.push(p);
      if (sm.canTransition(l.status, sm.STATUS.CANCELLED)) {
        tx.update(s.ref, { status: sm.STATUS.CANCELLED, cancelledBy: 'assembly_expired', cancelledAt: now, updatedAt: now });
      }
    }
    tx.set(db.collection(TARIFF_AUDIT).doc(`chain_expired_${shipmentId}`), {
      kind: 'chain_expired', shipmentId, orderId: ship.orderId || null, legCount: legIds.length,
      claimed: Number(chain.claimed) || 0, refundPending: refund, by: 'system', at: now,
    });
    return {
      expired: true, legIds, couriers, ownerId: ship.ownerId, orderId: ship.orderId || null,
      trackingNumber: ship.trackingNumber || '', refund, claimed: Number(chain.claimed) || 0,
    };
  });
  if (!out.expired) return out;

  try {
    for (const legId of out.legIds) await closeOtherMatches(db, legId, null, 'cancelled', now);
    await recomputeOrderStatus(db, out.orderId, now);
  } catch (e) {
    console.error(JSON.stringify({
      action: 'chainExpired.after', result: 'error', errorCode: 'CHAIN_EXPIRE_POST_STEPS_FAILED', shipmentId, message: e.message,
    }));
  }
  try {
    await writeChainNews(db, shipmentId, out.ownerId, 'sender', out.trackingNumber, now);
    for (const p of out.couriers) await writeChainNews(db, shipmentId, p, 'courier', out.trackingNumber, now);
  } catch (e) {
    console.error(JSON.stringify({
      action: 'chainExpired.notify', result: 'error', errorCode: 'CHAIN_EXPIRE_NOTIFY_FAILED', shipmentId, message: e.message,
    }));
  }
  console.log(JSON.stringify({
    action: 'chainExpired', result: 'ok', shipmentId, orderId: out.orderId, legCount: out.legIds.length,
    claimed: out.claimed, couriers: out.couriers.length, refundPending: out.refund,
  }));
  return out;
}

/** `admin_news` (mavjud shaxsiy inbox) — ID deterministik (21-band: takror xabar yo'q). */
async function writeChainNews(db, shipmentId, userId, role, trackingNumber, now) {
  const uid = toCanonicalId(userId || '');
  if (!uid) return;
  const t = CHAIN_EXPIRED_NEWS[role];
  const suffix = trackingNumber ? ` (${trackingNumber})` : '';
  await db.collection('admin_news').doc(`chainExpired_${shipmentId}_${uid}`).set({
    title: t.uz_Latn.title + suffix,
    body: t.uz_Latn.body,
    i18n: {
      uz_Latn: { title: t.uz_Latn.title + suffix, body: t.uz_Latn.body },
      uz_Cyrl: { title: t.uz_Cyrl.title + suffix, body: t.uz_Cyrl.body },
      ru: { title: t.ru.title + suffix, body: t.ru.body },
    },
    category: 'warning',
    audience: 'user',
    targetUserId: uid,
    source: 'logistics',
    dataType: 'logistics_chain_expired',
    shipmentId,
    priority: 6,
    createdAt: now,
  });
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

/**
 * Ijrochi hali ham shu LEG'ni olishga haqlimi (audit L6). Match hujjati
 * matching paytidagi holat: undan keyin capability bekor qilinishi, qarz
 * bloki, trust/moderator bloki yoki sinov ro'yxatidan chiqarish mumkin.
 * Qoidalar QAYTA YOZILMAYDI — matcher bilan bir xil hardFilterReason
 * (trust, blok, qarz, adapter.isEligible: hudud + INTERNAL bosqich).
 *
 * Ijrochi ma'lumoti tranzaksiyadan OLDIN yuklanadi (users -> accountId ->
 * capability + provider_stats); LEG o'zi tranzaksiya ichida o'qiladi.
 */
async function loadAcceptCandidates(db, providerId) {
  const doc = await capabilitiesSource.fetchForProvider(db, providerId);
  const out = [];
  if (!doc) return out;
  const services = new Set();
  for (const list of Object.values(SERVICES_BY_LEG_KIND)) for (const s of list) services.add(s);
  for (const service of services) {
    if (!caps.isEligible(doc, service)) continue;
    const svc = doc[service] || {};
    // Manba qoidasi bilan bir xil: kuryer faqat posilka oladiganlar.
    if (service === 'courier' && svc.acceptsParcels !== true) continue;
    out.push({
      providerId,
      accountId: doc.id,
      source: 'capabilities',
      viaService: service,
      regionIds: svc.regionIds || [],
      districtIds: svc.districtIds || [],
      acceptsParcels: svc.acceptsParcels === true,
      capabilityStatus: caps.statusOf(doc, service),
      // Kuryer toifasi (2026-10-31): adapter LEG toifasini shu ikkisidan tekshiradi (matcher bilan bir xil).
      raw: svc,
      courierScopeReview: service === 'courier' ? ((doc.review || {}).courierScopes || {}) : null,
    });
  }
  await attachStats(db, out);
  return out;
}

function assertStillEligible(legId, leg, candidates, config) {
  const adapter = getAdapter(L.MODULE);
  if (!adapter) throw fail('unimplemented', 'logistics adapteri ulanmagan');
  const kind = ((leg.attributes || {}).legKind) || 'direct';
  const services = SERVICES_BY_LEG_KIND[kind] || SERVICES_BY_LEG_KIND.direct;
  const demand = { id: legId, ...leg };
  let why = 'capability_not_eligible';
  for (const c of candidates) {
    if (!services.includes(c.viaService)) continue;
    const r = hardFilterReason(demand, c, config, adapter);
    if (!r) return;
    why = r;
  }
  // Foydalanuvchi matni match yo'qligi bilan bir xil (sababni oshkor qilmaymiz).
  // `not_matched` — mavjud kod (ilova matni bor, parity fixture'da); sabab `why`da (ichki).
  throw fail('permission-denied', 'Bu jo\'natma sizga mos emas', 'not_matched', { why });
}

// ─── ZANJIR (assemble_all, ega qarori 2026-11-07) ──────────────────────

/** LEG zanjirda «olingan» hisoblanadimi (ijrochisi bor, bekor/muddati o'tmagan). */
function isClaimedLeg(d) {
  return !!d && !!(d.assignment || {}).providerId
    && [sm.STATUS.ACCEPTED, sm.STATUS.IN_PROGRESS, sm.STATUS.COMPLETED].includes(d.status);
}
const providerOf = (d) => (isClaimedLeg(d) ? (d.assignment || {}).providerId : null);

/**
 * `shipments.chain.selfTransferLegIds` (klient shartnomasi, 2026-11-07): oldingi
 * LEG ham AYNAN shu kuryerniki bo'lgan LEG ID'lari — klient «o'zimga topshirish»
 * tugmasini shu bilan ko'rsatadi. Telefon YO'Q (40-band): `legAssignments`
 * zanjir jo'natmasida yozilmaydi. `legs` — [{id, d}] marshrut tartibida.
 */
function selfTransferLegIdsOf(legs) {
  const out = [];
  for (let i = 1; i < legs.length; i += 1) {
    const p = providerOf(legs[i].d);
    if (p && p === providerOf(legs[i - 1].d)) out.push(legs[i].id);
  }
  return out;
}

/**
 * Yig'ish holatida olish mumkinmi. Qulfdan keyin faqat admin qayta ochgan
 * (`chainReopenedAt`) LEG olinadi (`adminReopenChainLeg`).
 */
function assertChainAcceptable(ship, leg, now) {
  const chain = ship.chain || {};
  const deadlinePassed = chain.deadlineAt && sm.toMillis(chain.deadlineAt) <= now.getTime();
  if (chain.state === L.CHAIN_STATE.EXPIRED
    || (chain.state === L.CHAIN_STATE.ASSEMBLING && deadlinePassed)) {
    throw fail('failed-precondition', 'Jo\'natma muddati tugadi', L.CHAIN_ERROR.EXPIRED);
  }
  if (chain.state === L.CHAIN_STATE.LOCKED) {
    if (!leg.chainReopenedAt) throw fail('failed-precondition', 'Bu jo\'natma uchun kuryerlar to\'liq', L.CHAIN_ERROR.LOCKED);
    return;
  }
  if (chain.state !== L.CHAIN_STATE.ASSEMBLING || !chain.deadlineAt) {
    throw fail('failed-precondition', 'Jo\'natma hali to\'lanmagan yoki yopilgan', 'shipment_not_ready');
  }
}

/**
 * Zanjir to'liq tayinlanganda kontaktlar (1-pog'ona). Har LEG uchun:
 *   olish telefoni (`ownerPhone`, mavjud kalit) — LEG-1: jo'natuvchi;
 *   keyingilari: OLDINGI LEG ijrochisi (jo'natuvchi telefoni LEG-2+ ga HECH QACHON);
 *   `nextProviderPhone` — keyingi LEG ijrochisi (oxirgisida yo'q).
 * Posilkani allaqachon olgan (`in_progress`) LEG'ning 2-pog'ona kontakti
 * buzilmaydi — faqat `nextProviderPhone` yangilanadi; `completed` tegilmaydi.
 * `extraFor` — shu tranzaksiyada boshqa maydonlar ham yoziladigan match (bitta yozuv).
 */
function chainContactWrites(tx, db, legs, extraFor) {
  for (let i = 0; i < legs.length; i += 1) {
    const x = legs[i];
    const p = providerOf(x.d);
    if (!p) continue;
    const prevP = i > 0 ? providerOf(legs[i - 1].d) : null;
    const nextP = i < legs.length - 1 ? providerOf(legs[i + 1].d) : null;
    const ref = db.collection(MATCHES).doc(`${x.id}_${p}`);
    const extra = (extraFor && extraFor.legId === x.id) ? extraFor.fields : {};
    if (x.d.status === sm.STATUS.ACCEPTED) {
      const a = x.d.attributes || {};
      const loc = x.d.location || {};
      const pickup = i === 0 ? x.d.ownerId : (prevP && prevP !== x.d.ownerId ? prevP : null);
      tx.set(ref, {
        ...extra,
        contactUnlocked: {
          stage: 1,
          ownerPhone: pickup,
          pickupAddress: loc.addressText || '',
          pickupLat: loc.lat == null ? null : loc.lat,
          pickupLng: loc.lng == null ? null : loc.lng,
          handoverFromKind: a.handoverFromKind || null,
          nextProviderPhone: nextP || null,
        },
      }, { merge: true });
    } else if (x.d.status === sm.STATUS.IN_PROGRESS) {
      tx.set(ref, { ...extra, contactUnlocked: { nextProviderPhone: nextP || null } }, { merge: true });
    }
  }
}

/**
 * acceptLeg'ning zanjir shoxi — AYNI tranzaksiyada (chaqiruvchi LEG va
 * jo'natmani o'qib bo'lgan): avval QOLGAN LEG'lar o'qiladi, keyin yoziladi.
 * Jo'natma hujjatini HAR olish yozadi (`chain.claimed`) — ikki parallel
 * «oxirgi» olishdan biri qayta uriniladi va boshqasini ko'radi: qulfni
 * AYNAN BITTA chaqiruv qo'yadi. `claimed` hisoblagich emas, LEG'lardan
 * qayta hisoblanadi (qayta urinishda ham, drift'da ham to'g'ri).
 * Qulfgacha kontakt YO'Q (`contactUnlocked: null`).
 */
async function acceptChainLegInTx(tx, {
  db, now, leg, legId, legRef, matchRef, ship, shipmentRef, providerId,
}) {
  const legIds = Array.isArray(ship.legIds) ? ship.legIds : [legId];
  const otherIds = legIds.filter((id) => id !== legId);
  const otherSnaps = await Promise.all(otherIds.map((id) => tx.get(db.collection(DEMANDS).doc(id))));
  // ── o'qishlar tugadi ──
  const byId = new Map();
  otherSnaps.forEach((s, i) => byId.set(otherIds[i], s.exists ? (s.data() || {}) : null));
  byId.set(legId, { ...leg, status: sm.STATUS.ACCEPTED, assignment: { providerId, offerId: null, acceptedAt: now } });
  const legs = legIds.map((id) => ({ id, d: byId.get(id) }));
  const claimed = legs.filter((x) => isClaimedLeg(x.d)).length;
  const full = claimed === legIds.length;
  const chain = ship.chain || {};
  const lockedNow = full && chain.state === L.CHAIN_STATE.ASSEMBLING;
  const state = lockedNow ? L.CHAIN_STATE.LOCKED : chain.state;

  tx.update(legRef, {
    status: sm.STATUS.ACCEPTED,
    assignment: { providerId, offerId: null, acceptedAt: now },
    updatedAt: now,
  });
  const matchFields = { status: 'accepted', acceptedAt: now };
  if (full) {
    chainContactWrites(tx, db, legs, { legId, fields: matchFields });
  } else {
    tx.set(matchRef, { ...matchFields, contactUnlocked: null }, { merge: true });
  }
  const assigned = Array.isArray(ship.assignedProviderIds) ? ship.assignedProviderIds : [];
  const shipPatch = {
    assignedProviderIds: assigned.includes(providerId) ? assigned : [...assigned, providerId],
    'chain.claimed': claimed,
    'chain.selfTransferLegIds': selfTransferLegIdsOf(legs),
    updatedAt: now,
  };
  if (lockedNow) {
    shipPatch['chain.state'] = L.CHAIN_STATE.LOCKED;
    shipPatch['chain.lockedAt'] = now;
  }
  tx.update(shipmentRef, shipPatch);
  return {
    shipmentId: shipmentRef.id,
    legIndex: Number((leg.attributes || {}).legIndex) || 0,
    prevLegId: null,
    ship,
    lockedNow,
    chain: { state, claimed, legCount: legIds.length },
  };
}

function makeAcceptLeg(deps) {
  const { db, now: nowFn } = deps;

  return async function acceptLeg(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const providerId = callerIdFrom(context);
    if (!providerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const legId = String((data || {}).legId || '');
    if (!legId) throw fail('invalid-argument', 'legId majburiy');

    // Match tuzilgandan keyin holat o'zgargan bo'lishi mumkin (audit L6): kill
    // switch, INTERNAL bosqich, capability va qarz bloki shu yerda QAYTA
    // tekshiriladi (matcher bilan bir xil qoidalar). Ma'lumot tranzaksiyadan
    // oldin yuklanadi, tekshiruv — LEG/match o'qilgach (match yo'q ijrochiga
    // modul holati oshkor qilinmaydi: avvalgidek `not_matched`).
    const flags = await resolveFlags(db, L.MODULE, CONFIG_REGION);
    const acceptCandidates = await loadAcceptCandidates(db, providerId);

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
      const a = leg.attributes || {};
      if (sm.isPastExpiry((leg.timeWindow || {}).expiresAt, now)) {
        // Zanjir LEG'i muddati = zanjir muddati (activateLeg) → klientga zanjir kodi.
        if (a.chainMode === L.CHAIN_MODE.ASSEMBLE_ALL && !leg.chainReopenedAt) {
          throw fail('failed-precondition', 'Jo\'natma muddati tugadi', L.CHAIN_ERROR.EXPIRED);
        }
        throw fail('failed-precondition', 'LEG muddati tugagan', 'expired');
      }
      assertModuleEnabled(flags);
      assertStillEligible(legId, leg, acceptCandidates, flags.config);

      const shipmentRef = db.collection(L.SHIPMENTS).doc(String(a.shipmentId || ''));
      const shipSnap = await tx.get(shipmentRef);
      if (!shipSnap.exists) throw fail('failed-precondition', 'Jo\'natma topilmadi', 'shipment_missing');
      const ship = shipSnap.data() || {};
      const chainMode = L.isAssembleAll(ship);
      if (chainMode) assertChainAcceptable(ship, leg, now);
      if (![L.SHIPMENT_STATUS.READY, L.SHIPMENT_STATUS.IN_TRANSIT].includes(ship.status)) {
        throw fail('failed-precondition', 'Jo\'natma hali to\'lanmagan yoki yopilgan', 'shipment_not_ready');
      }
      // Faqat JORIY marshrut rejasining LEG'i (eski reja LEG'i qandaydir yo'l
      // bilan `active` qolsa ham — eski payout bilan «etim» ish olinmasin).
      if (Array.isArray(ship.legIds) && !ship.legIds.includes(legId)) {
        throw fail('failed-precondition', 'Bu LEG joriy marshrutda yo\'q (qayta rejalangan)', 'leg_superseded', { legId });
      }
      if (chainMode) {
        return acceptChainLegInTx(tx, {
          db, now, leg, legId, legRef, matchRef, ship, shipmentRef, providerId,
        });
      }

      // Olish nuqtasi kontakti (Т-9, 1-pog'ona): LEG-1 — jo'natuvchi;
      // keyingilari — OLDINGI LEG ijrochisi. 2026-11-07 tuzatish: avval
      // `currentCustodian.id` edi — oldingi LEG hali olinmagan bo'lsa u
      // JO'NATUVCHI va uning telefoni LEG-2+ ijrochisiga ochilardi (40-band).
      const idx = Number(a.legIndex) || 0;
      const prevAssignee = a.dependsOnLegId ? ((ship.legAssignments || {})[a.dependsOnLegId] || null) : null;
      const pickupPhone = idx === 0 ? leg.ownerId : (prevAssignee && prevAssignee !== leg.ownerId ? prevAssignee : null);
      const loc = leg.location || {};
      // Keyingi LEG avvalroq olingan bo'lsa (bu LEG bekor qilinib, qayta
      // olinmoqda) — topshirish nuqtasi kontakti shu yerda ochiladi; aks holda
      // keyingi ijrochi acceptLeg'da ochadi (pastda, tranzaksiyadan tashqari).
      const nextProvider = a.nextLegId ? (ship.legAssignments || {})[a.nextLegId] || null : null;

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
          ...(nextProvider ? { nextProviderPhone: nextProvider } : {}),
        },
      }, { merge: true });
      const assigned = Array.isArray(ship.assignedProviderIds) ? ship.assignedProviderIds : [];
      tx.update(shipmentRef, {
        assignedProviderIds: assigned.includes(providerId) ? assigned : [...assigned, providerId],
        [`legAssignments.${legId}`]: providerId,
        updatedAt: now,
      });
      return {
        shipmentId: shipmentRef.id, legIndex: idx, prevLegId: a.dependsOnLegId || null, ship,
        nextLegId: a.nextLegId || null, nextProvider,
      };
    });

    // Tranzaksiyadan TASHQARIDA: qolgan match'lar «olindi»; oldingi
    // ijrochiga keyingi ijrochi telefoni ochiladi (topshirish nuqtasi uchun).
    await closeOtherMatches(db, legId, providerId, 'taken', now);
    if (out.chain) {
      // Zanjir: kontaktlar faqat qulflanganda, AYNI tranzaksiyada yozildi.
      console.log(JSON.stringify({
        action: 'acceptLeg.chain', result: 'ok', shipmentId: out.shipmentId, legId, legIndex: out.legIndex,
        claimed: out.chain.claimed, legCount: out.chain.legCount, state: out.chain.state, lockedNow: out.lockedNow,
      }));
      return { ok: true, legId, shipmentId: out.shipmentId, chain: out.chain };
    }
    if (out.prevLegId) {
      const prevProvider = (out.ship.legAssignments || {})[out.prevLegId];
      if (prevProvider) {
        await db.collection(MATCHES).doc(`${out.prevLegId}_${prevProvider}`).set({
          contactUnlocked: { nextProviderPhone: providerId },
        }, { merge: true });
      }
    }
    // Keyingi LEG avval olingan bo'lsa — uning olish telefoni endi shu ijrochi
    // (2026-11-07: avval u yerda jo'natuvchi telefoni turishi mumkin edi).
    if (out.nextLegId && out.nextProvider) {
      await db.collection(MATCHES).doc(`${out.nextLegId}_${out.nextProvider}`).set({
        contactUnlocked: { ownerPhone: providerId },
      }, { merge: true });
    }
    return { ok: true, legId, shipmentId: out.shipmentId };
  };
}

/**
 * LEG ijrochisi bekor qilganda (`cancelAssignment`) jo'natmadagi izlarni
 * AYNI tranzaksiyada tozalaydi. Ikki bosqich, chunki haqiqiy SDK yozuvdan
 * keyingi o'qishni rad etadi: bu funksiya faqat O'QIYDI, qaytargan
 * `commit(now)` esa YOZADI — chaqiruvchi uni o'z yozuvlari bilan chaqiradi.
 *
 * Tozalanadi (2026-10-10, emulatorda isbotlangan bo'shliqlar):
 *   - `legAssignments[legId]` — eskisi qolsa, keyingi LEG olinganda uning
 *     ijrochisi telefoni BEKOR QILGANning match'iga yozilardi;
 *   - `assignedProviderIds`dan ijrochi — boshqa LEG'i qolmagan bo'lsa
 *     (qoida shu ro'yxat bo'yicha jo'natmani o'qishga ruxsat beradi);
 *   - oldingi LEG ijrochisi match'idagi `nextProviderPhone` — bekor
 *     qilganning telefoni u yerda ochiq qolmasin.
 * Logistika bo'lmasa / eski hujjat (shipmentId yo'q) / jo'natma yo'q → no-op.
 */
async function prepareLegCancelInTx(tx, db, leg, legId, providerId) {
  const a = (leg && leg.attributes) || {};
  if (!leg || leg.module !== L.MODULE || !a.shipmentId) return () => {};
  const shipmentRef = db.collection(L.SHIPMENTS).doc(String(a.shipmentId));
  const shipSnap = await tx.get(shipmentRef);
  if (!shipSnap.exists) return () => {};
  const ship = shipSnap.data() || {};
  if (L.isAssembleAll(ship)) return prepareChainLegCancelInTx(tx, db, ship, shipmentRef, legId, providerId);

  const legAssignments = { ...(ship.legAssignments || {}) };
  if (legAssignments[legId] === providerId) delete legAssignments[legId];
  const assigned = Array.isArray(ship.assignedProviderIds) ? ship.assignedProviderIds : [];
  const stillHolds = Object.values(legAssignments).includes(providerId);

  const prevLegId = a.dependsOnLegId ? String(a.dependsOnLegId) : null;
  const prevProvider = prevLegId ? legAssignments[prevLegId] : null;
  let prevMatchRef = null;
  if (prevProvider) {
    const ref = db.collection(MATCHES).doc(`${prevLegId}_${prevProvider}`);
    const snap = await tx.get(ref);
    const c = snap.exists ? (snap.data() || {}).contactUnlocked : null;
    if (c && c.nextProviderPhone === providerId) prevMatchRef = ref;
  }

  return (now) => {
    tx.update(shipmentRef, {
      legAssignments,
      assignedProviderIds: stillHolds ? assigned : assigned.filter((p) => p !== providerId),
      updatedAt: now,
    });
    if (prevMatchRef) tx.update(prevMatchRef, { 'contactUnlocked.nextProviderPhone': null });
  };
}

/**
 * Zanjir (assemble_all, 2026-11-07): ijrochi LEG'ni FAQAT yig'ish paytida
 * bo'shata oladi; qulfdan keyin — `CHAIN_LOCKED` (zanjir ishonchi: boshqa
 * kuryerlar shu tarkibga tayanib yo'lga chiqadi; tushib qolish — admin
 * `adminReopenChainLeg`). Yig'ishda kontakt ochilmagan, shuning uchun
 * tozalanadigan telefon yo'q; `chain.claimed` LEG'lardan qayta hisoblanadi.
 */
async function prepareChainLegCancelInTx(tx, db, ship, shipmentRef, legId, providerId) {
  const chain = ship.chain || {};
  if (chain.state === L.CHAIN_STATE.LOCKED) {
    throw fail('failed-precondition',
      'Kuryerlar to\'liq yig\'ilgan — endi voz kechib bo\'lmaydi. Admin bilan bog\'laning.', L.CHAIN_ERROR.LOCKED);
  }
  if (chain.state !== L.CHAIN_STATE.ASSEMBLING) {
    throw fail('failed-precondition', 'Jo\'natma yopilgan', `chain_${chain.state}`);
  }
  const legIds = Array.isArray(ship.legIds) ? ship.legIds : [];
  const otherIds = legIds.filter((id) => id !== legId);
  const snaps = await Promise.all(otherIds.map((id) => tx.get(db.collection(DEMANDS).doc(id))));
  const others = snaps.map((s) => (s.exists ? (s.data() || {}) : null));
  const claimed = others.filter(isClaimedLeg).length;
  const stillHolds = others.some((d) => providerOf(d) === providerId);
  const assigned = Array.isArray(ship.assignedProviderIds) ? ship.assignedProviderIds : [];
  const byId = new Map(otherIds.map((id, i) => [id, others[i]]));
  const ordered = legIds.map((id) => ({ id, d: id === legId ? null : byId.get(id) }));
  return (now) => {
    tx.update(shipmentRef, {
      assignedProviderIds: stillHolds ? assigned : assigned.filter((p) => p !== providerId),
      'chain.claimed': claimed,
      'chain.selfTransferLegIds': selfTransferLegIdsOf(ordered),
      updatedAt: now,
    });
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

/**
 * Ilovaning O'Z Storage bucket'lari (audit S5/L13). Manba tartibi:
 *   1) `deps.storageBucket` (qo'lda berilgan; string yoki massiv);
 *   2) `FIREBASE_CONFIG.storageBucket` — Functions runtime o'zi qo'yadi;
 *   3) `GCLOUD_PROJECT` -> Firebase standart nomlari (`<loyiha>.firebasestorage.app`,
 *      `<loyiha>.appspot.com`) — XULOSA (INFERRED), repo'da bucket nomi faqat
 *      `lib/firebase_options.dart`da;
 *   4) hech biri yo'q -> [] : bucket PIN QILINMAYDI (faqat host + `logistics/{id}/`).
 */
function storageBucketsFor(deps) {
  const d = (deps || {}).storageBucket;
  if (d) return (Array.isArray(d) ? d : [d]).map(String).filter(Boolean);
  try {
    const cfg = JSON.parse(process.env.FIREBASE_CONFIG || '{}');
    if (cfg && cfg.storageBucket) return [String(cfg.storageBucket)];
  } catch (_) { /* FIREBASE_CONFIG yaroqsiz — keyingi manba */ }
  const p = process.env.GCLOUD_PROJECT;
  if (p) return [`${p}.firebasestorage.app`, `${p}.appspot.com`];
  return [];
}

/**
 * Dalil rasmlari: faqat chaqiruvchining O'Z yuklagan fayli
 * (`logistics/{callerId}/...`). Bo'sh qatorlar avvalgidek tushiriladi; boshqa
 * har qanday URL (begona host, boshqa foydalanuvchi yo'li) — aniq rad.
 */
function normalizeProofPhotos(raw, callerId, buckets) {
  const out = [];
  for (const u of (Array.isArray(raw) ? raw : []).slice(0, 4)) {
    const s = String(u || '').trim();
    if (!s) continue;
    if (s.length > 500 || !L.isOwnProofPhotoUrl(s, callerId, buckets)) {
      throw fail('invalid-argument', 'Rasm manzili noto\'g\'ri', 'photo_url_invalid');
    }
    out.push(s);
  }
  return out;
}

// ─── Kod urinishlari cheklovi (audit S4/L7, 2026-10-16) ────────────────
// 6 xonali kod HMAC'dan, jo'natma uchun doimiy; ijrochi uni 10^6 ta urinib
// topishi mumkin edi. Har (jo'natma, LEG, chaqiruvchi, tur) uchun xato
// urinishlar `shipments/{id}/private/codeAttempts_*` hujjatida SANALADI
// (`private/{docId}` qoidasi: klient o'qimaydi ham, yozmaydi ham). Hisob
// kod tekshiruvi bilan BIR tranzaksiyada: ikki parallel xato taxmin ham
// sanaladi. Xato urinishdan keyin chaqiruv tranzaksiyadan SO'NG xato
// tashlaydi (aks holda tranzaksiya yozuvni bekor qilardi).

function codeLockedError(retryAfterSec) {
  return fail('resource-exhausted',
    'Juda ko\'p noto\'g\'ri urinish bo\'ldi. Biroz kutib, qayta urinib ko\'ring.',
    'CODE_ATTEMPTS_LOCKED', { retryAfterSec });
}

function codeAttemptsRef(shipmentRef, kind, legId, callerId) {
  return shipmentRef.collection('private').doc(`codeAttempts_${kind}_${legId}_${callerId}`);
}

/**
 * Tranzaksiya ICHIDA, o'qishlardan keyin. `verify()` — kod to'g'rimi.
 * Qaytaradi: `null` (to'g'ri — davom eting; hisoblagich o'chirildi) yoki
 * `{ blocked: 'locked'|'bad', retryAfterSec }`.
 */
function applyCodeAttempt(tx, ref, snap, now, limits, verify, meta) {
  const att = snap && snap.exists ? (snap.data() || {}) : null;
  const leftMs = L.codeLockRemainingMs(att, now);
  if (leftMs > 0) return { blocked: 'locked', retryAfterSec: Math.ceil(leftMs / 1000) };
  if (verify()) {
    if (att) tx.delete(ref);
    return null;
  }
  const next = L.registerFailedCodeAttempt(att, now, limits);
  tx.set(ref, { ...meta, ...next, updatedAt: now });
  if (next.lockedUntil) return { blocked: 'locked', retryAfterSec: Math.ceil(limits.lockMs / 1000) };
  return { blocked: 'bad' };
}

/** Qulf bo'lsa — qulf xatosi (+ log); aks holda chaqiruvchi o'zi «noto'g'ri kod» tashlaydi. */
function throwIfCodeLocked(blocked, log) {
  if (blocked.blocked !== 'locked') return;
  console.error(JSON.stringify({ result: 'denied', errorCode: 'CODE_ATTEMPTS_LOCKED', ...log }));
  throw codeLockedError(blocked.retryAfterSec);
}

/**
 * `selfTransfer` (zanjir, 2026-11-07): ketma-ket LEG'larni BITTA kuryer olgan
 * bo'lsa posilka uning qo'lidan chiqmaydi — kod/QR va rasm talab qilinmaydi
 * (berilgan rasm baribir tekshiriladi). Haqiqatan o'zi-o'ziga topshirishmi —
 * tranzaksiyada tekshiriladi (`self_transfer_invalid`).
 */
function validateProofInput(data, config, photoCtx) {
  const d = data || {};
  const selfTransfer = d.selfTransfer === true;
  const code = d.code == null ? '' : String(d.code).trim();
  const qrPayload = d.qrPayload == null ? '' : String(d.qrPayload).trim();
  if (!selfTransfer && !code && !qrPayload) throw fail('invalid-argument', 'Kod yoki QR kerak', 'proof_required');
  const photos = normalizeProofPhotos(d.photoUrls, (photoCtx || {}).callerId, (photoCtx || {}).buckets);
  const requirePhoto = ((config || {}).logistics || {}).requireHandoverPhoto !== false;
  if (!selfTransfer && requirePhoto && photos.length === 0) throw fail('invalid-argument', 'Rasm majburiy', 'photo_required');
  const loc = d.location && typeof d.location === 'object' ? d.location : null;
  const location = loc && finiteOrNull(loc.lat) !== null && finiteOrNull(loc.lng) !== null
    ? { lat: Number(loc.lat), lng: Number(loc.lng), accuracy: finiteOrNull(loc.accuracy) }
    : null;
  return {
    code, qrPayload, photos, location, selfTransfer,
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
    const proof = validateProofInput(data, config, { callerId: providerId, buckets: storageBucketsFor(deps) });

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
    const attemptsRef = codeAttemptsRef(shipmentRef, 'handover', legId, providerId);

    const result = await db.runTransaction(async (tx) => {
      const reads = [tx.get(legRef), tx.get(shipmentRef), tx.get(secretsRef), tx.get(eventRef), tx.get(orderRef), tx.get(attemptsRef)];
      if (prevLegRef) reads.push(tx.get(prevLegRef));
      const [legSnap, shipSnap, secSnap, evSnap, orderSnap, attSnap, prevSnap] = await Promise.all(reads);

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
      // Zanjir (2026-11-07): butun zanjir yig'ilmaguncha posilka olinmaydi.
      const chainMode = L.isAssembleAll(ship);
      if (chainMode && (ship.chain || {}).state !== L.CHAIN_STATE.LOCKED) {
        throw fail('failed-precondition', 'Hamma kuryerlar hali topilmadi — posilkani olishni kuting', L.CHAIN_ERROR.NOT_LOCKED);
      }
      // O'zi-o'ziga topshirish: faqat zanjirda, LEG-2+, oldingi LEG ham shu
      // kuryerniki va posilka hozir uning qo'lida (kod/rasmsiz — dalil hodisada).
      const prevAssignee = prevSnap && prevSnap.exists ? ((prevSnap.data() || {}).assignment || {}).providerId : null;
      if (proof.selfTransfer) {
        const curC = ship.currentCustodian || {};
        if (!chainMode || idx === 0 || prevAssignee !== providerId
          || curC.kind !== L.CUSTODIAN_KIND.PROVIDER || curC.id !== providerId) {
          throw fail('failed-precondition', 'Bu topshirishni kodsiz tasdiqlab bo\'lmaydi', 'self_transfer_invalid');
        }
      } else {
        const blocked = applyCodeAttempt(
          tx, attemptsRef, attSnap, now, L.codeAttemptLimits(config),
          () => L.verifyHandoverProof(shipmentId, qrSecret, { code: proof.code, qrPayload: proof.qrPayload }),
          { kind: 'handover', shipmentId, legId, callerId: providerId },
        );
        if (blocked) return { blocked };
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
          qrVerified: !proof.selfTransfer && !!proof.qrPayload,
          codeVerified: !proof.selfTransfer && !proof.qrPayload && !!proof.code,
          photoUrls: proof.photos,
          conditionFlags: proof.conditionFlags,
          ...(proof.selfTransfer ? { selfTransfer: true } : {}),
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
          // Topshirgan ijrochida PII qolmasin (audit L10): kontakt shu tranzaksiyada yopiladi.
          tx.set(db.collection(MATCHES).doc(`${prevLegId}_${prevProvider}`), {
            status: 'completed', closedAt: now, contactUnlocked: null,
          }, { merge: true });
        }
      }

      return {
        idempotent: false, event, nextLegId: a.nextLegId || null, orderId: a.orderId || null, chainMode,
      };
    });

    if (result.blocked) {
      throwIfCodeLocked(result.blocked, { action: 'scanHandover', shipmentId, legId });
      throw fail('permission-denied', 'Kod noto\'g\'ri', 'bad_proof');
    }

    // Zanjir (6.1): posilka yo'lda — keyingi LEG ochiladi.
    // `assemble_all` LEG'i: barcha LEG to'lovda ochilgan va qulfda tayinlangan —
    // ketma-ket ochish YO'Q.
    const isChainLeg = a.chainMode === L.CHAIN_MODE.ASSEMBLE_ALL;
    const openOn = ((config.logistics || {}).openNextLegOn) || 'in_progress';
    const openNextLeg = async (nextLegId) => {
      if (!nextLegId || openOn !== 'in_progress' || isChainLeg) return;
      try { await activateLeg(deps, nextLegId); } catch (e) {
        console.error(JSON.stringify({
          action: 'scanHandover.openNextLeg', result: 'error', errorCode: 'NEXT_LEG_OPEN_FAILED',
          shipmentId, legId, nextLegId, message: e.message,
        }));
      }
    };
    if (result.idempotent) {
      // Takroriy chaqiruv (audit L3a): birinchi chaqiruvda keyingi LEG ochilmay
      // qolgan bo'lishi mumkin (xato faqat logga tushadi) — shu yerda QAYTA
      // uriniladi. `activateLeg` tranzaksion va idempotent: LEG allaqachon
      // ochilgan bo'lsa `skipped` qaytaradi. Faqat hodisani yozgan ijrochi uchun.
      if (((result.event || {}).createdBy) === providerId) await openNextLeg(a.nextLegId || null);
      return { ok: true, idempotent: true, eventId, legStatus: 'in_progress' };
    }
    await openNextLeg(result.nextLegId);
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
    const photos = normalizeProofPhotos((data || {}).photoUrls, providerId, storageBucketsFor(deps));
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
    const attemptsRef = codeAttemptsRef(shipmentRef, 'delivery', legId, providerId);

    const result = await db.runTransaction(async (tx) => {
      const [legSnap, shipSnap, secSnap, evSnap, attSnap] = await Promise.all([
        tx.get(legRef), tx.get(shipmentRef), tx.get(secretsRef), tx.get(eventRef), tx.get(attemptsRef),
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
      const blocked = applyCodeAttempt(
        tx, attemptsRef, attSnap, now, L.codeAttemptLimits(config),
        () => L.verifyDeliveryCode(shipmentId, (secSnap.data() || {}).qrSecret, deliveryCode),
        { kind: 'delivery', shipmentId, legId, callerId: providerId },
      );
      if (blocked) return { blocked };

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
      // Yetkazilgach qabul qiluvchi ismi/telefoni/manzili ijrochida qolmasin (audit L10).
      tx.set(db.collection(MATCHES).doc(`${legId}_${providerId}`), {
        status: 'completed', closedAt: now, contactUnlocked: null,
      }, { merge: true });
      return { idempotent: false, orderId: a.orderId || null };
    });

    if (result.blocked) {
      throwIfCodeLocked(result.blocked, { action: 'confirmDelivery', shipmentId, legId });
      throw fail('permission-denied', 'Yetkazish kodi noto\'g\'ri', 'bad_delivery_code');
    }
    if (!result.idempotent) await recomputeOrderStatus(db, result.orderId, now);
    return { ok: true, idempotent: result.idempotent, eventId, shipmentStatus: L.SHIPMENT_STATUS.DELIVERED };
  };
}

// ═══════════════════════════════════════════════════════════════════════
// BEKOR QILISH (custody boshlanmagan bo'lsa)
// ═══════════════════════════════════════════════════════════════════════

/** Ulgurji buyurtmasi ORDER/jo'natmasi (`source` 'wholesale…' yoki `wholesaleOrderId`). */
function isWholesaleRecord(d) {
  const x = d || {};
  return !!x.wholesaleOrderId || (typeof x.source === 'string' && x.source.startsWith('wholesale'));
}

function makeCancelLogisticsOrder(deps) {
  const { db, now: nowFn } = deps;

  return async function cancelLogisticsOrder(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const ownerId = callerIdFrom(context);
    if (!ownerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');
    const orderId = String((data || {}).orderId || '');
    if (!orderId) throw fail('invalid-argument', 'orderId majburiy');

    const orderRef = db.collection(L.ORDERS).doc(orderId);

    // O'qish + tekshiruv + yozuv BITTA tranzaksiyada (audit L1, 2026-10-16).
    // Avval jo'natmalar tranzaksiyasiz o'qilib, keyin batch yozilardi:
    //   - oradagi eskrou tushishi: jo'natma `cancelled` + `escrow_funded`
    //     qolardi (refund_pending yozilmasdi — pul qaytmasdi);
    //   - oradagi `scanHandover`: yo'lga chiqqan (`in_transit`) jo'natma
    //     bekor qilinardi (custody boshlangan, ijrochi qo'lida).
    // Endi `scanHandover`/eskrou bilan to'qnashsa commit qayta uriniladi va
    // holat/`paymentStatus`/`custodyCount` yangidan tekshiriladi.
    const out = await db.runTransaction(async (tx) => {
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) throw fail('not-found', 'Buyurtma topilmadi');
      const order = orderSnap.data() || {};
      if (order.ownerId !== ownerId) throw fail('permission-denied', 'Bu buyurtma sizniki emas');
      // Ulgurji buyurtmasi jo'natmasi: egasi = sotuvchi, u bekor QILA OLMAYDI (ega,
      // 2026-10-31: sotuvchi buyurtmaga aralashmaydi). Bekor — xaridor/admin, Ulgurji
      // buyurtmasining o'z oqimi orqali. Belgi ORDER'da ham, jo'natmada ham tekshiriladi.
      // (Jonli kod feat/ulg-relay-guards dan — relay zanjiri bilan 2026-11-07 birlashtirildi.)
      if (isWholesaleRecord(order)) {
        throw fail('permission-denied', 'Bu jo\'natmani bekor qilib bo\'lmaydi', 'wholesale_managed');
      }

      const shipSnap = await tx.get(db.collection(L.SHIPMENTS).where('orderId', '==', orderId));
      const ships = shipSnap.docs.map((d) => ({ ref: d.ref, id: d.id, data: d.data() || {} }));
      if (ships.some((s) => isWholesaleRecord(s.data))) {
        throw fail('permission-denied', 'Bu jo\'natmani bekor qilib bo\'lmaydi', 'wholesale_managed');
      }
      for (const s of ships) {
        if (s.data.status === L.SHIPMENT_STATUS.CANCELLED) continue;
        // Custody boshlangan bo'lsa (status ham, `custodyCount` ham) — bekor yo'q.
        if (!L.isShipmentCancellable(s.data.status) || (Number(s.data.custodyCount) || 0) > 0) {
          throw fail('failed-precondition', 'Posilka allaqachon yo\'lda — bekor qilib bo\'lmaydi', 'in_transit', { shipmentId: s.id });
        }
      }

      const legIdsAll = [];
      for (const s of ships) {
        if (s.data.status === L.SHIPMENT_STATUS.CANCELLED) continue;
        for (const legId of (s.data.legIds || [])) legIdsAll.push(legId);
      }
      const legSnaps = await Promise.all(legIdsAll.map((id) => tx.get(db.collection(DEMANDS).doc(id))));

      // Barcha o'qishlar tugadi — endi faqat yozuv.
      let refundPending = 0;
      for (const s of ships) {
        if (s.data.status === L.SHIPMENT_STATUS.CANCELLED) continue;
        const patch = {
          status: L.assertShipmentTransition(s.data.status, L.SHIPMENT_STATUS.CANCELLED, 'cancelLogisticsOrder'),
          cancelledAt: now,
          cancelledBy: 'owner',
          updatedAt: now,
        };
        if (L.isAssembleAll(s.data)) patch['chain.state'] = L.CHAIN_STATE.CANCELLED;
        // Eskrou tushgan bo'lsa — refund (pulni default codebase qaytaradi).
        if (s.data.paymentStatus === L.PAYMENT_STATUS.ESCROW_FUNDED) {
          patch.paymentStatus = L.assertPaymentTransition(s.data.paymentStatus, L.PAYMENT_STATUS.REFUND_PENDING, 'cancel');
          refundPending += 1;
        }
        tx.update(s.ref, patch);
      }
      for (const snap of legSnaps) {
        if (!snap.exists) continue;
        const st = (snap.data() || {}).status;
        if (sm.canTransition(st, sm.STATUS.CANCELLED)) {
          tx.update(snap.ref, { status: sm.STATUS.CANCELLED, cancelledBy: 'owner', cancelledAt: now, updatedAt: now });
        }
      }
      tx.update(orderRef, { status: 'cancelled', cancelledAt: now, updatedAt: now });
      return { cancelled: ships.length, refundPending, legIdsAll };
    });

    for (const legId of out.legIdsAll) await closeOtherMatches(db, legId, null, 'cancelled', now);
    return { ok: true, cancelled: out.cancelled, refundPending: out.refundPending };
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
    // Ulgurji jo'natmasida egasi (sotuvchi) kodni OLMAYDI — pul shu kod bilan yechiladi;
    // xaridor kodni `getWholesaleDeliveryCode` dan oladi. Istisno: egasi = qabul qiluvchi
    // (`recipientId`, masalan qaytish jo'natmasi) — o'zi qabul qiladi.
    const ownerGetsCode = isOwner && (!isWholesaleRecord(ship)
      || (typeof ship.recipientId === 'string' && ship.recipientId !== '' && ship.recipientId === callerId));
    if (ownerGetsCode) out.deliveryCode = L.deliveryCodeFor(shipmentId, qrSecret);
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
    // O'qish + holat tekshiruvi + yozuv BITTA tranzaksiyada (audit L12): avval
    // `get` → `set` tranzaksiyasiz edi — oradagi `adminActivateLogisticsTariff`
    // faol tarifni `draft`ga qaytarib yuborardi (ko'rsatkich esa hamon shu
    // versiyani faol deb turardi). Endi to'qnashuvda qayta uriniladi va
    // `active`/`retired` hujjat ustiga HECH QACHON yozilmaydi (9-band).
    await db.runTransaction(async (tx) => {
      const prev = await tx.get(ref);
      if (prev.exists && (prev.data() || {}).status !== tariffCore.STATUS.DRAFT) {
        // Faol/eski versiya O'ZGARMAS (9-band): yangi versiya ochiladi.
        throw fail('failed-precondition', 'Faol yoki eski versiyani tahrirlab bo\'lmaydi — yangi versiya oching', 'tariff_immutable');
      }
      tx.set(ref, { ...doc, updatedAt: now, updatedBy: adminId, createdAt: prev.exists ? (prev.data() || {}).createdAt || now : now });
      tx.set(db.collection(TARIFF_AUDIT).doc(), { kind: 'tariff_upsert', version: doc.version, by: adminId, at: now });
    });
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
    // Zanjir (2026-11-07): qayta rejalash va payout o'zgartirish — FAQAT yig'ish
    // paytida (qulfdan keyin kuryerlar shu narxga rozi bo'lib yo'lga chiqqan).
    const chainMode = L.isAssembleAll(ship);
    const rawOverrides = (data || {}).payoutOverrides;
    const hasOverrides = rawOverrides !== undefined && rawOverrides !== null;
    if (chainMode && (ship.chain || {}).state !== L.CHAIN_STATE.ASSEMBLING) {
      throw fail('failed-precondition', 'Zanjir yig\'ilgan — marshrut/payout o\'zgarmaydi', L.CHAIN_ERROR.LOCKED, { state: (ship.chain || {}).state });
    }
    if (hasOverrides && !chainMode) {
      throw fail('failed-precondition', 'Payout faqat zanjir (assemble_all) jo\'natmada, yig\'ish paytida o\'zgaradi', 'payout_override_chain_only');
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

    const version = (Number(ship.routePlanVersion) || 1) + 1;
    const route = buildRoute({ tariff, shipment: ship, points, version });
    const overrides = applyPayoutOverrides(route, rawOverrides);
    const legRefs = route.legs.map(() => db.collection(DEMANDS).doc());
    const legIds = legRefs.map((r) => r.id);
    const orderSnap = await db.collection(L.ORDERS).doc(ship.orderId).get();
    const order = { id: ship.orderId, termsAcceptedAt: (orderSnap.data() || {}).termsAcceptedAt || null };

    // Tekshiruv va yozuv BITTA tranzaksiyada (2026-10-10): avval LEG'lar
    // tranzaksiyasiz o'qilib, keyin batch yozilardi — oradagi `acceptLeg`
    // qabulini rejalash jimgina o'chirib yuborardi (emulatorda isbotlangan).
    // `acceptLeg` ham LEG + jo'natmani tranzaksiyada o'qiydi → bitta g'olib.
    const { old: oldLegs, paymentStatus: paidStatus } = await db.runTransaction(async (tx) => {
      const curSnap = await tx.get(shipRef);
      const cur = curSnap.data() || {};
      if (![L.SHIPMENT_STATUS.AWAITING_PAYMENT, L.SHIPMENT_STATUS.READY].includes(cur.status)) {
        throw fail('failed-precondition', 'Marshrut faqat yo\'lga chiqmagan jo\'natmada o\'zgaradi', 'shipment_not_replannable', { status: cur.status });
      }
      if ((Number(cur.routePlanVersion) || 1) !== (Number(ship.routePlanVersion) || 1)) {
        throw fail('failed-precondition', 'Marshrut boshqa admin tomonidan o\'zgartirildi, qayta urining', 'route_changed');
      }
      if (chainMode && (cur.chain || {}).state !== L.CHAIN_STATE.ASSEMBLING) {
        throw fail('failed-precondition', 'Zanjir yig\'ilgan — marshrut/payout o\'zgarmaydi', L.CHAIN_ERROR.LOCKED, { state: (cur.chain || {}).state });
      }
      // Eski LEG'lar: accepted/in_progress bo'lsa — rad (custody boshlangan).
      const legSnaps = await Promise.all((cur.legIds || []).map((id) => tx.get(db.collection(DEMANDS).doc(id))));
      const old = [];
      for (const s of legSnaps) {
        if (!s.exists) continue;
        const st = (s.data() || {}).status;
        if ([sm.STATUS.ACCEPTED, sm.STATUS.IN_PROGRESS].includes(st)) {
          throw fail('failed-precondition', 'LEG allaqachon ijrochiga tayinlangan', 'leg_assigned', { legId: s.id });
        }
        old.push({ ref: s.ref, id: s.id, status: st });
      }

      for (const o of old) {
        if (sm.canTransition(o.status, sm.STATUS.CANCELLED)) {
          tx.update(o.ref, { status: sm.STATUS.CANCELLED, cancelledBy: 'replan', cancelledAt: now, updatedAt: now });
        }
      }
      for (let i = 0; i < route.legs.length; i += 1) {
        tx.set(legRefs[i], buildLegDemand({
          ownerId: ship.ownerId, order, shipment: ship, shipmentId, leg: route.legs[i],
          legIndex: i, legCount: route.legs.length, legIds, adapter, now, ttlMinutes: ttl,
          chainMode: chainMode ? L.CHAIN_MODE.ASSEMBLE_ALL : undefined,
        }));
        tx.set(legRefs[i].collection('private').doc('stats'), {
          matchedCount: 0, candidateCount: 0, rejectedCount: 0, updatedAt: now,
        });
      }
      const planRef = db.collection(L.ROUTE_PLANS).doc(shipmentId);
      tx.set(planRef, { shipmentId, currentVersion: version, updatedAt: now }, { merge: true });
      tx.set(planRef.collection('versions').doc(String(ship.routePlanVersion || 1)), { supersededAt: now }, { merge: true });
      tx.set(planRef.collection('versions').doc(String(version)), {
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
      // `assignedProviderIds` ham bo'shaydi: yuqoridagi tekshiruvdan keyin
      // hech bir LEG tayinlanmagan, ro'yxatda qolgan har kim — eski reja
      // izi, u jo'natmani o'qiy olmasin (qoida shu ro'yxatga qaraydi).
      const shipPatch = {
        routePlanVersion: version, legIds, legCount: legIds.length, legAssignments: {},
        assignedProviderIds: [], legProblem: null, updatedAt: now,
      };
      if (chainMode) {
        // Yig'ish davom etadi (muddat O'ZGARMAYDI — pul to'langan paytdan), yangi LEG'lar bo'sh.
        shipPatch['chain.claimed'] = 0;
        shipPatch['chain.legCount'] = legIds.length;
        shipPatch['chain.selfTransferLegIds'] = [];
      }
      tx.update(shipRef, shipPatch);
      tx.set(shipRef.collection('private').doc('internal'), {
        platformShare: route.split.platformShare,
        providerPool: route.split.providerPool,
        legPayouts: route.split.legPayouts,
        ...(overrides ? { payoutOverride: { by: adminId, at: now, before: overrides.before } } : {}),
        updatedAt: now,
      }, { merge: true });
      if (overrides) {
        // 41-band: payout o'zgartirish — admin audit (kim, qachon, avval/keyin, sabab).
        tx.set(db.collection(TARIFF_AUDIT).doc(`payout_override_${shipmentId}_v${version}`), {
          kind: 'payout_override', shipmentId, routePlanVersion: version,
          providerPool: route.split.providerPool, before: overrides.before, after: overrides.after,
          by: adminId, reason, at: now,
        });
      }
      // To'lov holati AYNI tranzaksiyadan (audit L3b): tashqarida o'qilgan
      // `ship.paymentStatus` eskirishi mumkin — rejalash paytida eskrou tushsa
      // yangi LEG-1 `draft`da qolardi (trigger eski `legIds[0]`ni ochardi).
      return { old, paymentStatus: cur.paymentStatus };
    });
    for (const o of oldLegs) await closeOtherMatches(db, o.id, null, 'cancelled', now);

    // To'langan bo'lsa birinchi LEG darhol ochiladi.
    let first = null;
    if (paidStatus === L.PAYMENT_STATUS.ESCROW_FUNDED) {
      // Zanjir: BARCHA yangi LEG ochiladi (muddat — mavjud chain.deadlineAt).
      first = chainMode ? await activateChain(deps, shipmentId) : await activateLeg(deps, legIds[0]);
    }
    return {
      version, legIds, legCount: legIds.length, firstLeg: first,
      ...(overrides ? { payouts: overrides.after } : {}),
    };
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

    // Eski match'lar FAQAT g'olib ochuvchi tomonidan o'chiriladi (activateLeg
    // ichida, holat o'tishidan keyin) — aks holda parallel ikkinchi admin
    // birinchining yangi match'larini o'chirib yuborardi.
    const res = await activateLeg(deps, legId, { allowExpired: true, reason: 'admin_reactivate', resetMatches: true });
    if (!res.activated) throw fail('failed-precondition', 'LEG qayta ochilmadi', 'leg_reactivate_failed', res);

    await shipRef.update({ legProblem: null, updatedAt: now });
    await db.collection(TARIFF_AUDIT).add({
      kind: 'leg_reactivate', legId, shipmentId, by: adminId, reason, at: now,
    });
    return { ok: true, legId, shipmentId, matchedBucket: res.matchedBucket };
  };
}

// ═══════════════════════════════════════════════════════════════════════
// ADMIN — qulflangan zanjirda kuryer tushib qoldi (assemble_all, 2026-11-07)
// ═══════════════════════════════════════════════════════════════════════

/**
 * `adminReopenChainLeg({ shipmentId, legId, reason })`.
 *
 * DIZAYN (PROPOSED, eng xavfsiz izchil variant): zanjir `locked`da QOLADI,
 * faqat shu LEG `accepted → active` (ijrochisiz, `chainReopenedAt`), qayta
 * matching + push; boshqa LEG'lar o'z kuryerlarini SAQLAYDI. `assembling`ga
 * qaytarilmaydi, chunki:
 *   - posilka yo'lda bo'lishi mumkin — yig'ish muddati o'tsa refund + bekor
 *     yo'lda turgan posilkani «egasiz» qoldirardi (state machine ham
 *     `in_transit → cancelled`ni man qiladi);
 *   - `assembling`da boshqa kuryerlar ham bo'shata olardi — zanjir yemiriladi.
 * Custody o'z-o'zidan to'xtaydi: ochiq LEG'ning ijrochisi yo'q (olish mumkin
 * emas), keyingi LEG esa oldingisi `in_progress` bo'lmaguncha olmaydi.
 * `chain.claimed` kamayadi; yangi kuryer olganda (`acceptLeg`, qulf holatida
 * faqat `chainReopenedAt` LEG) zanjir yana to'liq bo'ladi va qo'shni
 * kontaktlar yangilanadi. LEG o'z TTL'i bilan yopilsa — mavjud `legProblem`
 * + `adminReactivateLeg` yo'li.
 *
 * Faqat `accepted` LEG (posilka hali olinmagan). Idempotent: LEG allaqachon
 * qayta ochilgan bo'lsa (`active` + `chainReopenedAt`) — hech narsa yozilmaydi.
 * Audit (41-band) AYNI tranzaksiyada.
 */
function makeAdminReopenChainLeg(deps) {
  const { db, now: nowFn } = deps;

  return async function adminReopenChainLeg(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const adminId = await assertAnalyticsAdmin(db, context);
    const d = data || {};
    const shipmentId = String(d.shipmentId || '').trim();
    const legId = String(d.legId || '').trim();
    const reason = String(d.reason || '').trim().slice(0, 300);
    try {
      if (!shipmentId || !legId) throw fail('invalid-argument', 'shipmentId va legId majburiy');
      if (reason.length < 3) throw fail('invalid-argument', 'Sabab majburiy (kamida 3 belgi)', 'reason_required');
      const config = await getModuleConfig(db, L.MODULE, CONFIG_REGION);
      const ttl = Number((config.logistics || {}).legTtlMinutes) || 3 * 24 * 60;
      const shipRef = db.collection(L.SHIPMENTS).doc(shipmentId);
      const legRef = db.collection(DEMANDS).doc(legId);

      const out = await db.runTransaction(async (tx) => {
        const [shipSnap, legSnap] = await Promise.all([tx.get(shipRef), tx.get(legRef)]);
        if (!shipSnap.exists) throw fail('not-found', 'Jo\'natma topilmadi');
        if (!legSnap.exists) throw fail('not-found', 'LEG topilmadi');
        const ship = shipSnap.data() || {};
        const leg = legSnap.data() || {};
        if (!L.isAssembleAll(ship)) throw fail('failed-precondition', 'Bu zanjir (assemble_all) jo\'natma emas', 'not_chain');
        const legIds = Array.isArray(ship.legIds) ? ship.legIds : [];
        if (!legIds.includes(legId) || (leg.attributes || {}).shipmentId !== shipmentId) {
          throw fail('failed-precondition', 'Bu LEG joriy marshrutda yo\'q', 'leg_superseded', { legId });
        }
        if (leg.status === sm.STATUS.ACTIVE && leg.chainReopenedAt) {
          return { idempotent: true, claimed: Number((ship.chain || {}).claimed) || 0 };
        }
        if ((ship.chain || {}).state !== L.CHAIN_STATE.LOCKED) {
          throw fail('failed-precondition', 'Zanjir qulflanmagan — kuryer o\'zi bo\'shata oladi', L.CHAIN_ERROR.NOT_LOCKED);
        }
        if (![L.SHIPMENT_STATUS.READY, L.SHIPMENT_STATUS.IN_TRANSIT].includes(ship.status)) {
          throw fail('failed-precondition', 'Jo\'natma holati mos emas', 'shipment_not_ready', { status: ship.status });
        }
        if (leg.status !== sm.STATUS.ACCEPTED) {
          throw fail('failed-precondition', 'Faqat posilka hali olinmagan (accepted) LEG qayta ochiladi', 'leg_not_reopenable', { status: leg.status });
        }
        const dropped = (leg.assignment || {}).providerId || null;
        const idx = legIds.indexOf(legId);
        const otherIds = legIds.filter((id) => id !== legId);
        const otherSnaps = await Promise.all(otherIds.map((id) => tx.get(db.collection(DEMANDS).doc(id))));
        // ── o'qishlar tugadi ──
        const byId = new Map();
        otherSnaps.forEach((s, i) => byId.set(otherIds[i], s.exists ? (s.data() || {}) : null));
        const others = otherIds.map((id) => byId.get(id));
        const claimed = others.filter(isClaimedLeg).length;
        const stillHolds = others.some((x) => providerOf(x) === dropped);
        const prevP = idx > 0 ? providerOf(byId.get(legIds[idx - 1])) : null;
        const nextP = idx < legIds.length - 1 ? providerOf(byId.get(legIds[idx + 1])) : null;

        sm.assertTransition(leg.status, sm.STATUS.ACTIVE, 'adminReopenChainLeg');
        const reopenCount = Number(leg.reopenCount || 0) + 1;
        tx.update(legRef, {
          status: sm.STATUS.ACTIVE,
          assignment: { providerId: null, offerId: null, acceptedAt: null },
          'matching.state': sm.MATCHING_STATE.PENDING,
          'timeWindow.expiresAt': new Date(now.getTime() + ttl * 60000),
          chainReopenedAt: now,
          reopenedAt: now,
          reopenReason: 'admin_chain_reopen',
          reopenCount,
          updatedAt: now,
        });
        const assigned = Array.isArray(ship.assignedProviderIds) ? ship.assignedProviderIds : [];
        tx.update(shipRef, {
          'chain.claimed': claimed,
          'chain.selfTransferLegIds': selfTransferLegIdsOf(legIds.map((id) => ({ id, d: id === legId ? null : byId.get(id) }))),
          assignedProviderIds: stillHolds || !dropped ? assigned : assigned.filter((p) => p !== dropped),
          updatedAt: now,
        });
        // Tushib qolgan kuryer kontaktlari yopiladi; qo'shnilarda uning telefoni qolmasin.
        if (dropped) {
          tx.set(db.collection(MATCHES).doc(`${legId}_${dropped}`), {
            status: 'reopened_by_admin', closedAt: now, contactUnlocked: null,
          }, { merge: true });
        }
        if (prevP) {
          tx.set(db.collection(MATCHES).doc(`${legIds[idx - 1]}_${prevP}`), {
            contactUnlocked: { nextProviderPhone: null },
          }, { merge: true });
        }
        if (nextP) {
          tx.set(db.collection(MATCHES).doc(`${legIds[idx + 1]}_${nextP}`), {
            contactUnlocked: { ownerPhone: null },
          }, { merge: true });
        }
        tx.set(db.collection(TARIFF_AUDIT).doc(`chain_reopen_${legId}_${reopenCount}`), {
          kind: 'chain_leg_reopen', shipmentId, legId, legIndex: idx,
          droppedProviderId: dropped, by: adminId, reason, at: now,
        });
        return { idempotent: false, claimed, legIndex: idx };
      });

      let rematch = null;
      if (!out.idempotent) {
        try { rematch = await rematchLeg(deps, legId); } catch (e) {
          console.error(JSON.stringify({
            action: 'adminReopenChainLeg.rematch', result: 'error', errorCode: 'LEG_REMATCH_FAILED', shipmentId, legId, message: e.message,
          }));
        }
      }
      console.log(JSON.stringify({
        action: 'adminReopenChainLeg', result: out.idempotent ? 'idempotent' : 'ok', shipmentId, legId,
        legIndex: out.legIndex, claimed: out.claimed,
      }));
      return {
        ok: true, idempotent: out.idempotent, shipmentId, legId, claimed: out.claimed,
        matchedBucket: rematch && rematch.matchedBucket ? rematch.matchedBucket : null,
      };
    } catch (e) {
      console.error(JSON.stringify({
        action: 'adminReopenChainLeg', result: 'denied', shipmentId, legId,
        errorCode: (e.details && e.details.reason) || e.code || 'UNKNOWN',
      }));
      throw e;
    }
  };
}

// ═══════════════════════════════════════════════════════════════════════
// ADMIN — posilka YO'QOLDI (D1, ega qarori 2026-10-16)
// ═══════════════════════════════════════════════════════════════════════

/**
 * `adminMarkShipmentLost({ shipmentId, reason, note?, opId })` — faqat admin/superadmin.
 *
 * BITTA tranzaksiya (cancel -> refund_pending -> trigger naqshi bilan bir xil):
 *   - SHIPMENT `in_transit|disputed` -> `lost`, `paymentStatus`
 *     `escrow_funded|escrow_frozen` -> `loss_pending`;
 *   - yo'qolgan LEG (`currentLegId`, posilka qo'lidagi ijrochi) `in_progress` -> `disputed`
 *     (LEG state machine'dagi yagona «muammo» holati; `completed` EMAS — haq to'lanmaydi;
 *     `cancelled` EMAS — ish bekor bo'lmadi, yo'qoldi); keyingi LEG'lar `cancelled`;
 *   - `logistics_incidents/{shipmentId}` (G, kuryer, mijoz, admin, sabab) + `events/declared`
 *     + `logistics_audit` (41-band) — hammasi AYNI tranzaksiyada.
 * PUL bu yerda YO'Q: default codebase `onLogisticsShipmentUpdate` (+ reconcile) `loss_pending`
 * ni ko'rib G ni kuryer hamyonidan mijozga o'tkazadi (`functions/relay_escrow.js`).
 *
 * G = `priceSnapshot.declaredValue` (muhrlangan). Jazo = G (qo'shimcha to'lov EMAS).
 * Idempotent: incident bor bo'lsa hech narsa yozilmaydi, birinchi natija qaytadi.
 * Parallel ikki chaqiruv: tranzaksiya qayta uriniladi va ikkinchisi incident'ni ko'radi.
 */
/**
 * `db.runTransaction` + CHEKLANGAN qayta urinish FAQAT xom (HttpsError bo'lmagan) xatolarda.
 * Biznes rad (`fail(...)` = HttpsError) qayta urinilmaydi. Tranzaksiya funksiyasi idempotent
 * bo'lishi shart (holatni har urinishda qayta o'qiydi).
 */
async function runTxRetryRaw(db, fn, attempts = 3) {
  let last = null;
  for (let i = 1; i <= attempts; i += 1) {
    try {
      return await db.runTransaction(fn);
    } catch (e) {
      if (e && typeof e.code === 'string' && e.httpErrorCode) throw e; // HttpsError - biznes rad
      last = e;
      console.warn(JSON.stringify({
        action: 'runTxRetryRaw', result: 'retry', attempt: i, errorCode: 'TX_RAW_ERROR',
        message: String((e && e.message) || e).slice(0, 120),
      }));
      await new Promise((r) => setTimeout(r, 40 * i + Math.floor(Math.random() * 60)));
    }
  }
  throw last;
}

function makeAdminMarkShipmentLost(deps) {
  const { db, now: nowFn } = deps;

  async function run(data, context, adminId, now) {
    const d = data || {};
    const shipmentId = String(d.shipmentId || '').trim();
    const reason = String(d.reason || '').trim().slice(0, 300);
    const note = String(d.note || '').trim().slice(0, 1000);
    const opId = String(d.opId || '').trim();
    if (!shipmentId) throw fail('invalid-argument', 'shipmentId majburiy');
    if (reason.length < 3) throw fail('invalid-argument', 'Yo\'qolish sababi majburiy (kamida 3 belgi)', 'loss_reason_required');
    if (!/^[A-Za-z0-9_-]{6,64}$/.test(opId)) throw fail('invalid-argument', 'opId (6-64 belgi: harf, raqam, _ -)', 'loss_op_id');

    const shipRef = db.collection(L.SHIPMENTS).doc(shipmentId);
    const incRef = db.collection(L.INCIDENTS).doc(shipmentId);

    // Parallel `confirmDelivery` bilan poygada yutqazgan tomon Firestore'dan XOM xato olardi
    // ("Transaction is invalid or closed", kod 3 - Admin SDK qayta urinishda eski get'larni
    // yopilgan tranzaksiyaga o'tkazadi; courierSubmitPayment'da ham shunday topilgan).
    // Biznes rad (HttpsError) darhol; xom xatoda tranzaksiya qayta ishga tushiriladi - ikkinchi
    // urinish holatni qayta o'qib toza `shipment_not_lossable` beradi (qarang runTxRetryRaw).
    const out = await runTxRetryRaw(db, async (tx) => {
      const [shipSnap, incSnap] = await Promise.all([tx.get(shipRef), tx.get(incRef)]);
      if (!shipSnap.exists) throw fail('not-found', 'Jo\'natma topilmadi');
      const ship = shipSnap.data() || {};
      if (incSnap.exists) {
        const inc = incSnap.data() || {};
        return {
          idempotent: true, status: ship.status, paymentStatus: ship.paymentStatus,
          goodsValue: inc.goodsValue, legId: inc.legId, accountId: (inc.courier || {}).accountId,
        };
      }

      if (![L.SHIPMENT_STATUS.IN_TRANSIT, L.SHIPMENT_STATUS.DISPUTED].includes(ship.status)) {
        throw fail('failed-precondition', 'Faqat yo\'lda yoki nizoli jo\'natma yo\'qolgan deb belgilanadi', 'shipment_not_lossable', { status: ship.status });
      }
      if (![L.PAYMENT_STATUS.ESCROW_FUNDED, L.PAYMENT_STATUS.ESCROW_FROZEN].includes(ship.paymentStatus)) {
        throw fail('failed-precondition', 'To\'lov holati yo\'qolishga mos emas', 'payment_not_lossable', { paymentStatus: ship.paymentStatus });
      }
      const cur = ship.currentCustodian || {};
      const courierUid = toCanonicalId(cur.id);
      if (cur.kind !== L.CUSTODIAN_KIND.PROVIDER || !courierUid) {
        throw fail('failed-precondition', 'Posilka ijrochi qo\'lida emas — yo\'qolgan deb belgilab bo\'lmaydi', 'custodian_not_provider', { kind: cur.kind || null });
      }
      const goodsValue = L.goodsValueOf(ship);
      if (!goodsValue) {
        throw fail('failed-precondition', 'Posilka qiymati yozilmagan — qo\'lda hal qilinadi', 'declared_value_missing');
      }
      const legIds = Array.isArray(ship.legIds) ? ship.legIds : [];
      const idx = legIds.indexOf(ship.currentLegId);
      if (idx < 0) throw fail('failed-precondition', 'Joriy LEG marshrutda yo\'q', 'leg_superseded', { legId: ship.currentLegId || null });
      const legId = legIds[idx];

      // Barcha o'qishlar — yozuvdan OLDIN.
      const legSnaps = await Promise.all(legIds.slice(idx).map((id) => tx.get(db.collection(DEMANDS).doc(id))));
      const userSnaps = await Promise.all(candidateIdsFor(courierUid).map((id) => tx.get(db.collection('users').doc(id))));

      const lostLeg = legSnaps[0].exists ? (legSnaps[0].data() || {}) : null;
      if (!lostLeg || lostLeg.module !== L.MODULE) throw fail('failed-precondition', 'LEG topilmadi', 'shipment_missing');
      if ((lostLeg.assignment || {}).providerId !== courierUid) {
        throw fail('failed-precondition', 'Custody zanjiri mos emas', 'custody_mismatch');
      }
      if (![sm.STATUS.IN_PROGRESS, sm.STATUS.DISPUTED].includes(lostLeg.status)) {
        throw fail('failed-precondition', 'LEG olish holatida emas', 'leg_not_in_progress', { status: lostLeg.status });
      }
      const accountId = String((userSnaps.find((s) => s.exists && (s.data() || {}).accountId) || { data: () => ({}) }).data().accountId || '');
      if (!accountId) {
        throw fail('failed-precondition', 'Kuryer hisobi (accountId) topilmadi — qarzni yozib bo\'lmaydi', 'courier_account_missing');
      }

      // ── YOZUV ──
      tx.update(shipRef, {
        status: L.assertShipmentTransition(ship.status, L.SHIPMENT_STATUS.LOST, 'adminMarkShipmentLost'),
        paymentStatus: L.assertPaymentTransition(ship.paymentStatus, L.PAYMENT_STATUS.LOSS_PENDING, 'adminMarkShipmentLost'),
        lostAt: now,
        lostLegId: legId,
        lossIncidentId: shipmentId,
        updatedAt: now,
      });
      if (lostLeg.status === sm.STATUS.IN_PROGRESS) {
        sm.assertTransition(lostLeg.status, sm.STATUS.DISPUTED, 'adminMarkShipmentLost');
        tx.update(legSnaps[0].ref, { status: sm.STATUS.DISPUTED, lostAt: now, updatedAt: now });
      }
      const laterLegIds = [];
      for (let i = 1; i < legSnaps.length; i += 1) {
        const s = legSnaps[i];
        if (!s.exists) continue;
        if (sm.canTransition((s.data() || {}).status, sm.STATUS.CANCELLED)) {
          tx.update(s.ref, { status: sm.STATUS.CANCELLED, cancelledBy: 'lost', cancelledAt: now, updatedAt: now });
          laterLegIds.push(s.id);
        }
      }
      tx.set(incRef, {
        type: 'lost',
        status: 'declared',
        shipmentId,
        orderId: ship.orderId || null,
        trackingNumber: ship.trackingNumber || '',
        legId,
        legIndex: idx,
        courier: { uid: courierUid, accountId },
        customer: { uid: ship.ownerId },
        /** G — mijozga qaytariladigan summa; yetkazish haqi QAYTARILMAYDI (ega qarori). */
        goodsValue,
        customerPrice: Number((ship.priceSnapshot || {}).customerPrice) || 0,
        tariffVersion: (ship.priceSnapshot || {}).tariffVersion || null,
        /** Default codebase to'ldiradi (relay_escrow.js settleLoss): hisoblangunga qadar null. */
        refundedNow: null,
        outstanding: null,
        paidTotal: 0,
        declaredBy: adminId,
        reason,
        note,
        opId,
        declaredAt: now,
        updatedAt: now,
      });
      tx.set(incRef.collection('events').doc('declared'), {
        type: 'declared', amount: goodsValue, by: adminId, reason, at: now,
      });
      tx.set(db.collection(TARIFF_AUDIT).doc(`lost_${shipmentId}`), {
        kind: 'shipment_lost', shipmentId, legId, goodsValue, by: adminId, reason, at: now,
      });
      return {
        idempotent: false, status: L.SHIPMENT_STATUS.LOST, paymentStatus: L.PAYMENT_STATUS.LOSS_PENDING,
        goodsValue, legId, accountId, orderId: ship.orderId || null, closeLegIds: [legId, ...laterLegIds],
      };
    });

    if (!out.idempotent) {
      // Tranzaksiyadan TASHQARIDA: matchlar yopiladi (kuryerda qabul qiluvchi PII qolmasin),
      // ORDER holati qayta hisoblanadi (`lost` -> `problem`). Yiqilsa ham yo'qolish yozilgan.
      try {
        for (const id of out.closeLegIds) await closeOtherMatches(db, id, null, 'cancelled', now);
        await recomputeOrderStatus(db, out.orderId, now);
      } catch (e) {
        console.error(JSON.stringify({
          action: 'adminMarkShipmentLost.after', result: 'error', errorCode: 'LOSS_POST_STEPS_FAILED',
          shipmentId, legId: out.legId, message: e.message,
        }));
      }
    }
    console.log(JSON.stringify({
      action: 'adminMarkShipmentLost', result: out.idempotent ? 'idempotent' : 'ok', shipmentId, legId: out.legId,
      accountId: out.accountId, goodsValue: out.goodsValue,
    }));
    return {
      ok: true, idempotent: out.idempotent, shipmentId, legId: out.legId, status: out.status,
      paymentStatus: out.paymentStatus, goodsValue: out.goodsValue,
    };
  }

  return async function adminMarkShipmentLost(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const adminId = await assertStrictAdmin(db, context);
    try {
      return await run(data, context, adminId, now);
    } catch (e) {
      console.error(JSON.stringify({
        action: 'adminMarkShipmentLost', result: 'denied', shipmentId: String((data || {}).shipmentId || ''),
        errorCode: (e.details && e.details.reason) || e.code || 'UNKNOWN',
      }));
      throw e;
    }
  };
}

// ═══════════════════════════════════════════════════════════════════════
// ADMIN - ishga tushirish bosqichi va sinovchilar (D8, ega qarori 2026-10-16)
// ═══════════════════════════════════════════════════════════════════════

/** Sinovchilar ro'yxati chegarasi (hujjat o'lchami / suiiste'mol himoyasi, biznes qoida emas). */
const STAGE_TESTERS_MAX = 500;
/** Server konfigni shuncha soniya keshlaydi (`core/config.js`) - o'zgarish shu ichida kuchga kiradi. */
const STAGE_EFFECTIVE_WITHIN_SECONDS = 60;

function parseTesterList(raw) {
  if (raw === undefined) return undefined;
  if (!Array.isArray(raw)) throw fail('invalid-argument', 'Sinovchilar ro\'yxati massiv bo\'lishi kerak', 'tester_invalid');
  const out = [];
  for (const item of raw) {
    const s = String(item === null || item === undefined ? '' : item).trim();
    if (!s) continue;
    const id = toCanonicalId(s);
    if (!id) throw fail('invalid-argument', 'Telefon raqami noto\'g\'ri', 'tester_invalid');
    if (!out.includes(id)) out.push(id);
  }
  return out;
}

/**
 * `adminSetLogisticsStage({ stage?, addTesterIds?, removeTesterIds?, testerIds?, reason? })`
 * - `tools/set_logistics_stage.js` ning callable shakli. Faqat admin/superadmin
 * (dispatcher EMAS: bosqich butun xizmatni ochadi/yopadi). `module_config/
 * logistics_all.logistics.{stage,testerIds}` ni YANGILAYDI (boshqa kalitlar
 * tegilmaydi; hujjat yo'q bo'lsa YARATMAYDI - CLI kabi), bitta tranzaksiyada
 * `logistics_audit` (41-band). Telefonlar javobga ham, auditga ham CHIQMAYDI
 * (faqat soni, 40-band). O'zgarish yo'q -> `unchanged: true`, audit yo'q.
 * `testerIds` (to'liq almashtirish) `addTesterIds`/`removeTesterIds` bilan birga berilmaydi.
 */
function makeAdminSetLogisticsStage(deps) {
  const { db, now: nowFn } = deps;
  const ref = db.collection('module_config').doc(`${L.MODULE}_${CONFIG_REGION}`);

  return async function adminSetLogisticsStage(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const adminId = await assertStrictAdmin(db, context);
    const d = data || {};
    const reason = String(d.reason || '').trim().slice(0, 300);
    try {
      let nextStageArg = null;
      if (d.stage !== undefined && d.stage !== null) {
        if (!Object.values(L.STAGE).includes(d.stage)) {
          throw fail('invalid-argument', 'Bosqich noma\'lum', 'stage_invalid', { allowed: Object.values(L.STAGE) });
        }
        nextStageArg = d.stage;
      }
      const add = parseTesterList(d.addTesterIds);
      const remove = parseTesterList(d.removeTesterIds);
      const replace = parseTesterList(d.testerIds);
      if (replace !== undefined && (add !== undefined || remove !== undefined)) {
        throw fail('invalid-argument', 'testerIds va add/remove birga berilmaydi', 'tester_args_conflict');
      }
      if (nextStageArg === null && add === undefined && remove === undefined && replace === undefined) {
        throw fail('invalid-argument', 'O\'zgartirish yo\'q', 'nothing_to_change');
      }

      const out = await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) throw fail('failed-precondition', 'Logistika moduli konfigi yo\'q', 'module_config_missing');
        const cur = (snap.data() || {}).logistics || {};
        const curStage = L.stageOf({ logistics: cur });
        const curList = (Array.isArray(cur.testerIds) ? cur.testerIds : [])
          .map((t) => toCanonicalId(String(t))).filter(Boolean);
        let nextList;
        if (replace !== undefined) {
          nextList = replace;
        } else {
          nextList = curList.filter((t) => !(remove || []).includes(t));
          for (const t of (add || [])) if (!nextList.includes(t)) nextList.push(t);
        }
        if (nextList.length > STAGE_TESTERS_MAX) {
          throw fail('invalid-argument', `Sinovchilar ${STAGE_TESTERS_MAX} tadan oshmasin`, 'testers_limit');
        }
        const nextStage = nextStageArg === null ? curStage : nextStageArg;
        const added = nextList.filter((t) => !curList.includes(t)).length;
        const removed = curList.filter((t) => !nextList.includes(t)).length;
        const sameList = added === 0 && removed === 0;
        if (nextStage === curStage && sameList) {
          return { unchanged: true, stage: curStage, testerCount: curList.length, added: 0, removed: 0 };
        }
        tx.update(ref, {
          'logistics.stage': nextStage,
          'logistics.testerIds': nextList,
          updatedAt: now,
          updatedBy: adminId,
        });
        tx.set(db.collection(TARIFF_AUDIT).doc(), {
          kind: 'stage_update',
          from: { stage: curStage, testerCount: curList.length },
          to: { stage: nextStage, testerCount: nextList.length },
          added,
          removed,
          by: adminId,
          reason,
          at: now,
        });
        return { unchanged: false, stage: nextStage, testerCount: nextList.length, added, removed };
      });
      clearConfigCache();
      console.log(JSON.stringify({
        action: 'adminSetLogisticsStage', result: out.unchanged ? 'unchanged' : 'ok', stage: out.stage,
        testerCount: out.testerCount, added: out.added, removed: out.removed,
      }));
      return { ok: true, ...out, effectiveWithinSeconds: STAGE_EFFECTIVE_WITHIN_SECONDS };
    } catch (e) {
      console.error(JSON.stringify({
        action: 'adminSetLogisticsStage', result: 'denied', errorCode: (e.details && e.details.reason) || e.code || 'UNKNOWN',
      }));
      throw e;
    }
  };
}

module.exports = {
  TARIFF_AUDIT,
  MAX_PARCELS,
  STAGE_TESTERS_MAX,
  CONFIG_REGION,
  validatePoint,
  validateParcels,
  validateRecipient,
  buildLegDemand,
  buildRoute,
  activateLeg,
  activateChain,
  rematchLeg,
  applyPayoutOverrides,
  expireChain,
  sweepExpiredChains,
  makeOnLegReopened,
  makeAdminReopenChainLeg,
  recomputeOrderStatus,
  makeQuoteLogisticsOrder,
  makeGetLogisticsAccess,
  makeCreateLogisticsOrder,
  makeOnShipmentFunded,
  makeLegChainSweeper,
  makeAcceptLeg,
  prepareLegCancelInTx,
  makeScanHandover,
  makeConfirmDelivery,
  makeCancelLogisticsOrder,
  makeGetShipmentSecrets,
  makeAdminUpsertLogisticsTariff,
  makeAdminActivateLogisticsTariff,
  makeAdminPlanShipmentRoute,
  makeAdminReactivateLeg,
  makeAdminMarkShipmentLost,
  makeAdminSetLogisticsStage,
};
