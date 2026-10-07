/**
 * Mahalliy taksi (trips.taxiType local/alone) — SERVER narxi.
 *
 * Ega qarorlari (2026-10-07, memory: project-local-taxi-server-pricing):
 *   - yo'lkira FAQAT serverda hisoblanadi, har trip'da `tariffVersion` +
 *     `tariffSnapshot` saqlanadi (tarif o'zgarsa eski trip narxi o'zgarmaydi);
 *   - manzil MAJBURIY — narx buyurtma paytida qotiriladi;
 *   - qo'shimcha koeffitsient faqat TUN (server vaqti, Asia/Tashkent 23:00–06:00);
 *     bayram/yomg'ir/shoshilinch/kutish olib tashlandi;
 *   - narxni admin `TaxiPriceScreen`da tahrirlaydi → `adminSetLocalTaxiPrices`.
 *
 * Formula (eski klient `FareCalculator` bilan bir xil, kutishsiz):
 *   (base + round(km × perKm)) × coef × distCoef × nightCoef → round → 500 ga yaxlit.
 * Pul — butun son; koeffitsientlar permille (×1000) butun son, BigInt bilan.
 */
'use strict';

// Dart `GeoHash` bilan paritet — functions/test/geo_hash_parity.test.js.
const geoHash = require('./geo_hash');

const LOCAL_TAXI_TYPES = ['local', 'alone'];
const SEARCH_TTL_MS = 3 * 60 * 1000;
const NIGHT_PERMILLE = 1500;
const ROUND_TO = 500;
const TASHKENT_UTC_OFFSET_H = 5; // DST yo'q
const PRICES_DOC = ['settings', 'prices'];
const TARIFF_HISTORY = 'local_taxi_tariffs';
const REGION_KEYS = ['default', 'tashkent', 'xorazm', 'samarqand', 'namangan'];

/** `lib/utils/taxi_price_region.dart` bilan bir xil (paritet testi bor). */
function resolveRegionKey(lat, lng) {
  if (lat >= 41.10 && lat <= 41.55 && lng >= 69.00 && lng <= 69.55) return 'tashkent';
  if (lat >= 41.20 && lat <= 42.10 && lng >= 60.00 && lng <= 61.10) return 'xorazm';
  if (lat >= 39.50 && lat <= 40.00 && lng >= 66.80 && lng <= 67.20) return 'samarqand';
  if (lat >= 40.90 && lat <= 41.20 && lng >= 71.50 && lng <= 72.00) return 'namangan';
  return 'default';
}

function distanceCoefPermille(meters) {
  if (meters <= 3000) return 1000;
  if (meters <= 10000) return 900;
  if (meters <= 30000) return 800;
  if (meters <= 50000) return 700;
  return 600;
}

function isNightAt(date) {
  const h = (date.getUTCHours() + TASHKENT_UTC_OFFSET_H) % 24;
  return h >= 23 || h < 6;
}

/** a / b, yarim yuqoriga yaxlitlash (musbat BigInt). */
function divRoundHalfUp(a, b) {
  return (a * 2n + b) / (2n * b);
}

function toPermille(coef) {
  const n = Number(coef);
  if (!Number.isFinite(n) || n <= 0) return 1000;
  return Math.round(n * 1000);
}

/**
 * `settings/prices` dan mintaqa narxi. Topilmasa null (hardcode default YO'Q).
 * @return {{regionKey, base, perKm, coefPermille, source}|null}
 */
function resolvePrices(pricesDoc, regionKey) {
  const data = pricesDoc || {};
  const regions = (data.regions && typeof data.regions === 'object') ? data.regions : {};
  let region = null;
  let source = 'global';
  if (regions[regionKey] && typeof regions[regionKey] === 'object') {
    region = regions[regionKey];
    source = `region:${regionKey}`;
  } else if (regions.default && typeof regions.default === 'object') {
    region = regions.default;
    source = 'region:default';
  }
  const pick = (k) => {
    const v = region && region[k] != null ? region[k] : data[k];
    return v == null ? null : Number(v);
  };
  const base = pick('local_base');
  const perKm = pick('local_per_km');
  if (!Number.isInteger(base) || base <= 0 || !Number.isInteger(perKm) || perKm <= 0) {
    return null;
  }
  return {
    regionKey,
    base,
    perKm,
    coefPermille: toPermille(pick('local_coef')),
    source,
  };
}

/**
 * Sof funksiya — narx. `distanceMeters` butun son (Directions `distance.value`).
 * @return {{fare, distancePart, distCoefPermille, nightPermille}}
 */
function computeFare({ distanceMeters, prices, night }) {
  const m = Math.max(0, Math.trunc(Number(distanceMeters) || 0));
  const distancePart = Number(divRoundHalfUp(BigInt(m) * BigInt(prices.perKm), 1000n));
  const subtotal = BigInt(prices.base + distancePart);
  const distCoefPermille = distanceCoefPermille(m);
  const nightPermille = night ? NIGHT_PERMILLE : 1000;
  const total = divRoundHalfUp(
      subtotal * BigInt(prices.coefPermille) * BigInt(distCoefPermille) * BigInt(nightPermille),
      1000000000n);
  const fare = Number(divRoundHalfUp(total, BigInt(ROUND_TO))) * ROUND_TO;
  return { fare, distancePart, distCoefPermille, nightPermille };
}

function validLatLng(lat, lng) {
  return Number.isFinite(lat) && Number.isFinite(lng)
      && Math.abs(lat) <= 90 && Math.abs(lng) <= 180
      && (Math.abs(lat) > 1e-6 || Math.abs(lng) > 1e-6);
}

function str(v, max) {
  return String(v == null ? '' : v).trim().slice(0, max);
}

/** Google Directions — server kaliti bilan (klientga ishonilmaydi). */
async function fetchRouteViaGoogle(axios, { fromLat, fromLng, toLat, toLng }) {
  const apiKey = process.env.DIRECTIONS_API_KEY;
  if (!apiKey) throw new Error('DIRECTIONS_API_KEY sozlanmagan');
  const params = new URLSearchParams({
    origin: `${fromLat},${fromLng}`,
    destination: `${toLat},${toLng}`,
    mode: 'driving',
    key: apiKey,
  });
  const res = await axios.get(
      `https://maps.googleapis.com/maps/api/directions/json?${params}`,
      { timeout: 10000 });
  const body = res.data || {};
  const leg = body.status === 'OK' && body.routes && body.routes[0]
      && body.routes[0].legs && body.routes[0].legs[0];
  if (!leg || !leg.distance || !Number.isInteger(leg.distance.value)) {
    return null;
  }
  return {
    distanceMeters: leg.distance.value,
    polyline: String((body.routes[0].overview_polyline || {}).points || ''),
  };
}

function attachLocalTaxi(exportsObj, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, axios,
    fetchRoute: fetchRouteOverride, now: nowFn,
  } = deps;
  const now = nowFn || (() => new Date());
  const fetchRoute = fetchRouteOverride || ((p) => fetchRouteViaGoogle(axios, p));
  const HttpsError = functions.https.HttpsError;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();

  // Foydalanuvchiga matn klientda (uch tilda) — bu yerda diagnostika kodi.
  const fail = (status, code, extra = {}) =>
    new HttpsError(status, code, { code, ...extra });

  function requirePhoneUid(context) {
    if (!context || !context.auth) throw fail('unauthenticated', 'AUTH_REQUIRED');
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length < 12) throw fail('unauthenticated', 'PHONE_TOKEN_REQUIRED');
    return uid;
  }

  function log(action, fields) {
    console.log(JSON.stringify({ module: 'local_taxi', action, ...fields }));
  }

  /** Narx + marshrut → trip'ga yoziladigan qulf maydonlari. */
  async function quote({ fromLat, fromLng, toLat, toLng }) {
    const pricesSnap = await db.collection(PRICES_DOC[0]).doc(PRICES_DOC[1]).get();
    const pricesData = pricesSnap.exists ? pricesSnap.data() : {};
    const regionKey = resolveRegionKey(fromLat, fromLng);
    const prices = resolvePrices(pricesData, regionKey);
    if (!prices) throw fail('failed-precondition', 'TARIFF_NOT_CONFIGURED');

    let route;
    try {
      route = await fetchRoute({ fromLat, fromLng, toLat, toLng });
    } catch (e) {
      console.error('local_taxi route error:', e.message || e);
      throw fail('unavailable', 'ROUTE_UNAVAILABLE');
    }
    if (!route || !(route.distanceMeters > 0)) throw fail('failed-precondition', 'ROUTE_NOT_FOUND');

    const at = now();
    const night = isNightAt(at);
    const r = computeFare({ distanceMeters: route.distanceMeters, prices, night });
    if (!(r.fare > 0)) throw fail('internal', 'FARE_ZERO');
    const tariffVersion = Number.isInteger(pricesData.localTariffVersion)
      ? pricesData.localTariffVersion : 0;
    return {
      lockedFare: r.fare,
      estimatedPrice: r.fare,
      lockedDistanceM: route.distanceMeters,
      lockedDistanceKm: Math.round(route.distanceMeters / 100) / 10,
      lockedPolyline: route.polyline || '',
      fareNight: night,
      fareSource: 'server',
      tariffVersion,
      tariffSnapshot: {
        regionKey: prices.regionKey,
        priceSource: prices.source,
        base: prices.base,
        perKm: prices.perKm,
        coefPermille: prices.coefPermille,
        distCoefPermille: r.distCoefPermille,
        nightPermille: r.nightPermille,
        distancePart: r.distancePart,
      },
    };
  }

  /**
   * Yo'lovchi buyurtmasi — trip'ni SERVER yaratadi (narx qotirilgan holda).
   * Idempotent: bir xil `requestId` → o'sha trip.
   */
  exportsObj.createLocalTaxiTrip = functions
    .runWith({ secrets: ['DIRECTIONS_API_KEY'] })
    .https.onCall(async (data, context) => {
      const t0 = Date.now();
      const uid = requirePhoneUid(context);
      const d = data || {};
      const requestId = str(d.requestId, 64);
      if (!/^[A-Za-z0-9_-]{8,64}$/.test(requestId)) throw fail('invalid-argument', 'REQUEST_ID_INVALID');
      const fromLat = Number(d.fromLat);
      const fromLng = Number(d.fromLng);
      const toLat = Number(d.toLat);
      const toLng = Number(d.toLng);
      if (!validLatLng(fromLat, fromLng)) throw fail('invalid-argument', 'PICKUP_REQUIRED');
      if (!validLatLng(toLat, toLng)) throw fail('invalid-argument', 'DESTINATION_REQUIRED');
      const fromAddr = str(d.fromAddr, 300);
      const toAddr = str(d.toAddr, 300);
      if (!fromAddr) throw fail('invalid-argument', 'PICKUP_REQUIRED');
      if (!toAddr) throw fail('invalid-argument', 'DESTINATION_REQUIRED');

      const tripRef = db.collection('trips').doc(`lt_${uid}_${requestId}`);
      const existing = await tripRef.get();
      if (existing.exists) {
        log('create', { tripId: tripRef.id, result: 'duplicate', durationMs: Date.now() - t0 });
        return { ok: true, tripId: tripRef.id, fare: existing.data().lockedFare || 0, duplicate: true };
      }

      // Blok — server tomonda (klientdagi tekshiruv faqat UX).
      const blockSnap = await db.collection('users').doc(uid)
          .collection('local_taxi_block').doc('state').get();
      const blockedUntil = blockSnap.exists && blockSnap.data().blockedUntil
          && blockSnap.data().blockedUntil.toMillis
        ? blockSnap.data().blockedUntil.toMillis() : 0;
      const nowMs = now().getTime();
      if (blockedUntil > nowMs) {
        log('create', { uidTail: uid.slice(-4), result: 'blocked' });
        throw fail('failed-precondition', 'LOCAL_TAXI_BLOCKED',
            { minutes: Math.ceil((blockedUntil - nowMs) / 60000) });
      }

      const lock = await quote({ fromLat, fromLng, toLat, toLng });
      const report = d.report && typeof d.report === 'object' ? d.report : {};
      const trip = {
        status: 'searching',
        taxiType: 'local',
        userPhone: uid,
        userName: str(d.userName, 80),
        userGender: str(d.userGender, 16),
        userBirthDate: str(d.userBirthDate, 16),
        fromAddr,
        toAddr,
        fromLat, fromLng, toLat, toLng,
        geohash4: geoHash.encode(fromLat, fromLng, 4),
        radiusKm: 3,
        driverId: '',
        driverName: '',
        price: 0,
        cancelCount: 0,
        ...lock,
        fareLockedAt: ts(),
        fareLockVersion: 1,
        createdVia: 'createLocalTaxiTrip',
        createdAt: ts(),
        expiresAt: admin.firestore.Timestamp.fromMillis(nowMs + SEARCH_TTL_MS),
      };
      for (const k of ['regionId', 'districtId', 'serviceAreaId']) {
        const v = str(report[k], 64);
        if (v) trip[k] = v;
      }

      let duplicate = false;
      await db.runTransaction(async (t) => {
        const snap = await t.get(tripRef);
        if (snap.exists) { duplicate = true; return; }
        t.create(tripRef, trip);
      });
      log('create', {
        tripId: tripRef.id, result: duplicate ? 'duplicate' : 'ok',
        fare: lock.lockedFare, tariffVersion: lock.tariffVersion, durationMs: Date.now() - t0,
      });
      return { ok: true, tripId: tripRef.id, fare: lock.lockedFare, duplicate };
    });

  /**
   * Eski (narxsiz) trip'ga manzil + server narxini qotirish, yoki manzilni
   * o'zgartirish. Yo'lovchi yoki biriktirilgan haydovchi.
   */
  exportsObj.lockLocalTripFare = functions
    .runWith({ secrets: ['DIRECTIONS_API_KEY'] })
    .https.onCall(async (data, context) => {
      const uid = requirePhoneUid(context);
      const d = data || {};
      const tripId = str(d.tripId, 128);
      const toLat = Number(d.toLat);
      const toLng = Number(d.toLng);
      const toAddr = str(d.toAddr, 300);
      if (!tripId) throw fail('invalid-argument', 'TRIP_ID_REQUIRED');
      if (!validLatLng(toLat, toLng) || !toAddr) throw fail('invalid-argument', 'DESTINATION_REQUIRED');

      const tripRef = db.collection('trips').doc(tripId);
      const snap = await tripRef.get();
      if (!snap.exists) throw fail('not-found', 'TRIP_NOT_FOUND');
      const trip = snap.data() || {};
      const isPassenger = canonicalUid(trip.userPhone || '') === uid;
      const assigned = String(trip.acceptedDriverId || trip.driverId || '');
      const isDriver = assigned !== '' && canonicalUid(assigned) === uid;
      if (!LOCAL_TAXI_TYPES.includes(trip.taxiType)) throw fail('failed-precondition', 'NOT_LOCAL_TAXI');
      if (!isPassenger && !isDriver) throw fail('permission-denied', 'NOT_TRIP_PARTICIPANT');
      if (!['searching', 'accepted'].includes(trip.status)) throw fail('failed-precondition', 'TRIP_NOT_ACTIVE');
      const fromLat = Number(trip.fromLat);
      const fromLng = Number(trip.fromLng);
      if (!validLatLng(fromLat, fromLng)) throw fail('failed-precondition', 'PICKUP_REQUIRED');

      const lock = await quote({ fromLat, fromLng, toLat, toLng });
      await db.runTransaction(async (t) => {
        const cur = await t.get(tripRef);
        const st = (cur.data() || {}).status;
        if (!['searching', 'accepted'].includes(st)) throw fail('failed-precondition', 'TRIP_NOT_ACTIVE');
        t.update(tripRef, {
          ...lock,
          toAddr, toLat, toLng,
          fareLockedAt: ts(),
          fareLockVersion: admin.firestore.FieldValue.increment(1),
          fareLockedBy: isPassenger ? 'passenger' : 'driver',
        });
      });
      log('lock', { tripId, by: isPassenger ? 'passenger' : 'driver', fare: lock.lockedFare });
      return { ok: true, fare: lock.lockedFare, distanceKm: lock.lockedDistanceKm, polyline: lock.lockedPolyline };
    });

  /**
   * Admin — mahalliy taksi narxi. Har saqlash yangi `localTariffVersion` va
   * o'zgarmas tarix hujjati `local_taxi_tariffs/v{n}` (kim, qachon, nima edi).
   */
  exportsObj.adminSetLocalTaxiPrices = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const userSnap = await db.collection('users').doc(uid).get();
    const role = (userSnap.data() || {}).role || 'user';
    if (!['admin', 'superadmin', 'finance'].includes(role)) throw fail('permission-denied', 'ADMIN_REQUIRED');

    const d = data || {};
    const parseTier = (o, label) => {
      const base = Number(o && o.base);
      const perKm = Number(o && o.perKm);
      const coef = Number(o && o.coef);
      if (!Number.isInteger(base) || base <= 0 || base > 10000000
          || !Number.isInteger(perKm) || perKm <= 0 || perKm > 10000000) {
        throw fail('invalid-argument', 'PRICE_INVALID', { tier: label });
      }
      if (!Number.isFinite(coef) || coef < 0.1 || coef > 5) {
        throw fail('invalid-argument', 'COEF_INVALID', { tier: label });
      }
      return { local_base: base, local_per_km: perKm, local_coef: Math.round(coef * 1000) / 1000 };
    };
    const global = parseTier(d.global, 'global');
    const regions = {};
    const rawRegions = d.regions && typeof d.regions === 'object' ? d.regions : {};
    for (const [k, v] of Object.entries(rawRegions)) {
      if (!REGION_KEYS.includes(k)) throw fail('invalid-argument', 'REGION_UNKNOWN', { region: k });
      if (v) regions[k] = parseTier(v, k);
    }

    const ref = db.collection(PRICES_DOC[0]).doc(PRICES_DOC[1]);
    const version = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const cur = snap.exists ? snap.data() : {};
      const next = (Number.isInteger(cur.localTariffVersion) ? cur.localTariffVersion : 0) + 1;
      t.set(ref, {
        ...global,
        regions,
        localTariffVersion: next,
        localTariffUpdatedAt: ts(),
        localTariffUpdatedBy: uid,
        updatedAt: ts(),
      }, {
        mergeFields: ['local_base', 'local_per_km', 'local_coef', 'regions',
          'localTariffVersion', 'localTariffUpdatedAt', 'localTariffUpdatedBy', 'updatedAt'],
      });
      t.create(db.collection(TARIFF_HISTORY).doc(`v${next}`), {
        version: next,
        ...global,
        regions,
        previous: {
          version: Number.isInteger(cur.localTariffVersion) ? cur.localTariffVersion : 0,
          local_base: cur.local_base == null ? null : cur.local_base,
          local_per_km: cur.local_per_km == null ? null : cur.local_per_km,
          local_coef: cur.local_coef == null ? null : cur.local_coef,
          regions: cur.regions || {},
        },
        changedBy: uid,
        changedAt: ts(),
      });
      return next;
    });
    log('admin_prices', { version, by: uid });
    return { ok: true, version };
  });
}

module.exports = {
  attachLocalTaxi,
  resolveRegionKey,
  resolvePrices,
  computeFare,
  isNightAt,
  distanceCoefPermille,
  LOCAL_TAXI_TYPES,
};
