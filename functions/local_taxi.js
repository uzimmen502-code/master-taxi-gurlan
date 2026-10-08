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
// Standart qiymatlar — admin tarifda bermasa (ega qarori 2026-10-07: tun ×1.5,
// 23:00–06:00). Admin `TaxiPriceScreen`da o'zgartiradi (versiya bilan).
const DEFAULT_NIGHT_PERMILLE = 1500;
const DEFAULT_NIGHT_START_H = 23;
const DEFAULT_NIGHT_END_H = 6;
// Directions ishlamasa: to'g'ri chiziq × yo'l koeffitsienti (PROPOSED 1.3 —
// shahar ichi yo'llari to'g'ri chiziqdan odatda ~25–40% uzun).
const DEFAULT_ROAD_FACTOR_PERMILLE = 1300;
const ROUND_TO = 500;
// Yo'l koeffitsientini haftalik hisoblash (variant D, PROPOSED parametrlar).
const CALIBRATION_COL = 'local_taxi_calibration';
const CALIBRATION_DOC = 'road_factor';
const CALIBRATION_WINDOW_DAYS = 30;
const CALIBRATION_MAX_TRIPS = 5000;
const MIN_CALIBRATION_SAMPLES = 30;
const MIN_STRAIGHT_M = 500; // juda qisqa safarda nisbat shovqinli
const MIN_RATIO_PERMILLE = 1000;
const MAX_RATIO_PERMILLE = 3000; // undan katta — xato nuqta (chiqarib tashlanadi)
const FACTOR_CLAMP = [1000, 2000]; // admin chegarasi bilan bir xil
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

/** Tun oralig'i [startH, endH) Toshkent vaqtida; start > end bo'lsa yarim tundan o'tadi. */
function isNightAt(date, startH = DEFAULT_NIGHT_START_H, endH = DEFAULT_NIGHT_END_H) {
  const h = (date.getUTCHours() + TASHKENT_UTC_OFFSET_H) % 24;
  if (startH === endH) return false; // tun koeffitsienti o'chirilgan
  return startH > endH ? (h >= startH || h < endH) : (h >= startH && h < endH);
}

/** Ikki nuqta orasidagi to'g'ri chiziq masofasi (metr, butun). */
function haversineMeters(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const toRad = (d) => d * Math.PI / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2
      + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return Math.round(2 * R * Math.asin(Math.sqrt(a)));
}

/**
 * Sof funksiya — mintaqa bo'yicha yo'l koeffitsienti (mediana, permille).
 * Kiruvchi: [{regionKey, fromLat, fromLng, toLat, toLng, routeM}].
 * Faqat haqiqiy Directions masofasi bor safarlar (distanceSource 'route').
 * @return {{[region]: {factorPermille, samples}}} — samples < MIN bo'lsa factor null.
 */
function computeRoadFactors(samples) {
  const byRegion = {};
  for (const s of samples) {
    const straight = haversineMeters(s.fromLat, s.fromLng, s.toLat, s.toLng);
    const routeM = Math.trunc(Number(s.routeM) || 0);
    if (straight < MIN_STRAIGHT_M || routeM <= 0) continue;
    const ratio = Math.round((routeM * 1000) / straight);
    if (ratio < MIN_RATIO_PERMILLE || ratio > MAX_RATIO_PERMILLE) continue;
    (byRegion[s.regionKey] = byRegion[s.regionKey] || []).push(ratio);
  }
  const out = {};
  for (const [region, list] of Object.entries(byRegion)) {
    list.sort((a, b) => a - b);
    const mid = Math.floor(list.length / 2);
    const median = list.length % 2 ? list[mid] : Math.round((list[mid - 1] + list[mid]) / 2);
    out[region] = {
      factorPermille: list.length >= MIN_CALIBRATION_SAMPLES
        ? Math.min(FACTOR_CLAMP[1], Math.max(FACTOR_CLAMP[0], median)) : null,
      samples: list.length,
    };
  }
  return out;
}

function intOr(v, def, min, max) {
  if (v == null || v === '') return def; // Number(null) === 0 — tuzoq
  const n = Number(v);
  return Number.isInteger(n) && n >= min && n <= max ? n : def;
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
  const nightCoef = pick('local_night_coef');
  const roadFactor = pick('local_road_factor');
  return {
    regionKey,
    base,
    perKm,
    coefPermille: toPermille(pick('local_coef')),
    nightPermille: nightCoef == null ? DEFAULT_NIGHT_PERMILLE : toPermille(nightCoef),
    nightStartH: intOr(pick('local_night_start'), DEFAULT_NIGHT_START_H, 0, 23),
    nightEndH: intOr(pick('local_night_end'), DEFAULT_NIGHT_END_H, 0, 23),
    roadFactorPermille: roadFactor == null
      ? DEFAULT_ROAD_FACTOR_PERMILLE : toPermille(roadFactor),
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
  const nightPermille = night
    ? (Number.isInteger(prices.nightPermille) ? prices.nightPermille : DEFAULT_NIGHT_PERMILLE)
    : 1000;
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

    let route = null;
    try {
      route = await fetchRoute({ fromLat, fromLng, toLat, toLng });
    } catch (e) {
      console.error('local_taxi route error:', e.message || e);
    }
    // Directions ishlamasa / yo'l topmasa — buyurtma rad etilmaydi: masofa
    // to'g'ri chiziq × yo'l koeffitsienti (tarifda, versiya bilan) bo'yicha
    // hisoblanadi va trip'da `distanceSource: 'estimate'` deb belgilanadi.
    let distanceSource = 'route';
    let roadFactor = null; // { permille, source }
    if (!route || !(route.distanceMeters > 0)) {
      distanceSource = 'estimate';
      // Ega qarori 2026-10-08 (variant A + D): koeffitsient — shu mintaqaning
      // haftalik hisoblangan qiymati; ma'lumot yetarli bo'lmasa tarifdagisi.
      roadFactor = { permille: prices.roadFactorPermille, source: 'tariff' };
      try {
        const cal = await db.collection(CALIBRATION_COL).doc(CALIBRATION_DOC).get();
        const reg = cal.exists ? ((cal.data().regions || {})[regionKey]) : null;
        if (reg && Number.isInteger(reg.factorPermille) && reg.samples >= MIN_CALIBRATION_SAMPLES) {
          roadFactor = { permille: reg.factorPermille, source: `calibrated:${cal.data().runId || ''}` };
        }
      } catch (e) {
        console.error('local_taxi calibration read:', e.message || e);
      }
      const straight = haversineMeters(fromLat, fromLng, toLat, toLng);
      route = {
        distanceMeters: Number(divRoundHalfUp(
            BigInt(straight) * BigInt(roadFactor.permille), 1000n)),
        polyline: '',
      };
      log('route_fallback', {
        regionKey, straightM: straight, estimateM: route.distanceMeters,
        roadFactorPermille: roadFactor.permille, roadFactorSource: roadFactor.source,
      });
    }

    const at = now();
    const night = isNightAt(at, prices.nightStartH, prices.nightEndH);
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
      distanceSource,
      tariffVersion,
      tariffSnapshot: {
        regionKey: prices.regionKey,
        priceSource: prices.source,
        base: prices.base,
        perKm: prices.perKm,
        coefPermille: prices.coefPermille,
        distCoefPermille: r.distCoefPermille,
        nightPermille: r.nightPermille,
        nightStartH: prices.nightStartH,
        nightEndH: prices.nightEndH,
        roadFactorPermille: roadFactor ? roadFactor.permille : null,
        roadFactorSource: roadFactor ? roadFactor.source : null,
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
   * Haftalik: oxirgi 30 kunlik server narxli, HAQIQIY marshrutli trip'lardan
   * mintaqa bo'yicha «yo'l / to'g'ri chiziq» medianasi → `local_taxi_calibration/
   * road_factor` (joriy) + `runs/{runId}` (o'zgarmas tarix). Narxning o'zi
   * o'zgarmaydi — faqat Directions ishlamagan buyurtmada ishlatiladi va trip
   * snapshot'ida manbasi (`calibrated:{runId}`) saqlanadi.
   */
  async function runRoadFactorCalibration() {
    const at = now();
    const since = admin.firestore.Timestamp.fromMillis(
        at.getTime() - CALIBRATION_WINDOW_DAYS * 24 * 3600 * 1000);
    // Bitta maydon bo'yicha so'rov — kompozit indeks shart emas; qolganini xotirada.
    const snap = await db.collection('trips')
        .where('createdAt', '>=', since)
        .orderBy('createdAt', 'desc')
        .limit(CALIBRATION_MAX_TRIPS)
        .get();
    const samples = [];
    for (const doc of snap.docs) {
      const t = doc.data() || {};
      if (t.fareSource !== 'server') continue;
      // 2026-10-08 gacha zaxira yo'q edi — distanceSource yo'q = 'route'.
      if (t.distanceSource && t.distanceSource !== 'route') continue;
      const regionKey = (t.tariffSnapshot && t.tariffSnapshot.regionKey)
        || resolveRegionKey(Number(t.fromLat), Number(t.fromLng));
      samples.push({
        regionKey,
        fromLat: Number(t.fromLat), fromLng: Number(t.fromLng),
        toLat: Number(t.toLat), toLng: Number(t.toLng),
        routeM: t.lockedDistanceM,
      });
    }
    const regions = computeRoadFactors(samples);
    const runId = at.toISOString().slice(0, 10);
    const payload = {
      runId,
      regions,
      scannedTrips: snap.size,
      usedSamples: samples.length,
      windowDays: CALIBRATION_WINDOW_DAYS,
      minSamples: MIN_CALIBRATION_SAMPLES,
      computedAt: ts(),
    };
    const ref = db.collection(CALIBRATION_COL).doc(CALIBRATION_DOC);
    const batch = db.batch();
    batch.set(ref, payload);
    // Bir kunda qayta ishga tushsa — tarix ustidan yozilmaydi, yangi id.
    batch.set(ref.collection('runs').doc(`${runId}_${at.getTime()}`), payload);
    await batch.commit();
    log('road_factor_calibration', { runId, scanned: snap.size, used: samples.length, regions });
    return payload;
  }
  exportsObj.calibrateLocalTaxiRoadFactor = functions.pubsub
    .schedule('every monday 03:00')
    .timeZone('Asia/Tashkent')
    .onRun(() => runRoadFactorCalibration());

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

    // Tun va yo'l koeffitsienti — global (mintaqasiz). Berilmasa joriy qiymat.
    const night = d.night && typeof d.night === 'object' ? d.night : null;
    if (night) {
      const c = Number(night.coef);
      if (!Number.isFinite(c) || c < 1 || c > 3) throw fail('invalid-argument', 'NIGHT_COEF_INVALID');
      for (const h of [night.startH, night.endH]) {
        if (!Number.isInteger(h) || h < 0 || h > 23) throw fail('invalid-argument', 'NIGHT_HOURS_INVALID');
      }
    }
    if (d.roadFactor != null) {
      const rf = Number(d.roadFactor);
      if (!Number.isFinite(rf) || rf < 1 || rf > 2) throw fail('invalid-argument', 'ROAD_FACTOR_INVALID');
    }

    const ref = db.collection(PRICES_DOC[0]).doc(PRICES_DOC[1]);
    const version = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const cur = snap.exists ? snap.data() : {};
      const next = (Number.isInteger(cur.localTariffVersion) ? cur.localTariffVersion : 0) + 1;
      const extras = {
        local_night_coef: night ? Math.round(Number(night.coef) * 1000) / 1000
          : (cur.local_night_coef != null ? cur.local_night_coef : DEFAULT_NIGHT_PERMILLE / 1000),
        local_night_start: night ? night.startH
          : intOr(cur.local_night_start, DEFAULT_NIGHT_START_H, 0, 23),
        local_night_end: night ? night.endH
          : intOr(cur.local_night_end, DEFAULT_NIGHT_END_H, 0, 23),
        local_road_factor: d.roadFactor != null ? Math.round(Number(d.roadFactor) * 1000) / 1000
          : (cur.local_road_factor != null ? cur.local_road_factor : DEFAULT_ROAD_FACTOR_PERMILLE / 1000),
      };
      Object.assign(global, extras);
      t.set(ref, {
        ...global,
        regions,
        localTariffVersion: next,
        localTariffUpdatedAt: ts(),
        localTariffUpdatedBy: uid,
        updatedAt: ts(),
      }, {
        mergeFields: ['local_base', 'local_per_km', 'local_coef', 'regions',
          'local_night_coef', 'local_night_start', 'local_night_end', 'local_road_factor',
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
          local_night_coef: cur.local_night_coef == null ? null : cur.local_night_coef,
          local_night_start: cur.local_night_start == null ? null : cur.local_night_start,
          local_night_end: cur.local_night_end == null ? null : cur.local_night_end,
          local_road_factor: cur.local_road_factor == null ? null : cur.local_road_factor,
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
  haversineMeters,
  computeRoadFactors,
  distanceCoefPermille,
  LOCAL_TAXI_TYPES,
};
