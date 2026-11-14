/**
 * Mahalliy taksi — SERVER narxi (`functions/local_taxi.js`), ega qarori 2026-10-07.
 * Directions va soat stub qilinadi; Firestore — Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-local-taxi-pricing \
 *     "node functions/test/local_taxi_pricing_cf.test.js"
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-local-taxi-pricing';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const lt = require('../local_taxi');
const geoHash = require('../geo_hash');

const PASSENGER = '998901000001';
const DRIVER = '998902000001';
const STRANGER = '998903000001';
const ADMIN = '998909990001';
const GURLAN = { lat: 41.84, lng: 60.39 }; // xorazm
const DAY = new Date('2026-10-07T07:00:00Z'); // 12:00 Toshkent
const NIGHT = new Date('2026-10-07T19:30:00Z'); // 00:30 Toshkent

let clock = DAY;
let routeMeters = 5000;
let routeCalls = 0;
const api = {};
lt.attachLocalTaxi(api, {
  functions, db, admin,
  callerPhone: (ctx) => String(ctx.auth.token.phone_number || '').replace(/\D/g, ''),
  canonicalUid: (v) => { const d = String(v || '').replace(/\D/g, ''); return d.length === 9 ? `998${d}` : d; },
  fetchRoute: async () => {
    routeCalls += 1;
    if (routeMeters === 'throw') throw new Error('timeout');
    return routeMeters ? { distanceMeters: routeMeters, polyline: 'abc' } : null;
  },
  now: () => clock,
});
const ctxOf = (p) => ({ auth: { uid: `u_${p}`, token: { phone_number: `+${p}` } } });

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => d.ref.delete()));
}
async function reset(prices = { local_base: 5000, local_per_km: 1500, local_coef: 1.0, localTariffVersion: 3 }) {
  clock = DAY; routeMeters = 5000; routeCalls = 0;
  await Promise.all(['users', 'trips', 'settings', 'local_taxi_tariffs'].map(wipe));
  // users/*/local_taxi_block — subcollection
  await db.recursiveDelete(db.collection('users'));
  await db.collection('users').doc(PASSENGER).set({ role: 'user' });
  await db.collection('users').doc(DRIVER).set({ role: 'user' });
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  if (prices) await db.collection('settings').doc('prices').set(prices);
}
const order = (extra = {}) => ({
  requestId: 'req_abcdef01',
  fromAddr: 'Gurlan markaz', fromLat: GURLAN.lat, fromLng: GURLAN.lng,
  toAddr: 'Bozor', toLat: 41.86, toLng: 60.42,
  ...extra,
});
const codeOf = async (p) => { try { await p; return 'OK'; } catch (e) { return (e.details && e.details.code) || e.message; } };

async function main() {
  // ── Sof formula (eski klient FareCalculator bilan bir xil natija) ──────
  const P = { base: 5000, perKm: 1500, coefPermille: 1000 };
  await check('F1 5 km kunduzi: (5000+7500)×0.9 = 11250 → 11500', () =>
    assert.strictEqual(lt.computeFare({ distanceMeters: 5000, prices: P, night: false }).fare, 11500));
  await check('F2 5 km tunda ×1.5: 16875 → 17000', () =>
    assert.strictEqual(lt.computeFare({ distanceMeters: 5000, prices: P, night: true }).fare, 17000));
  await check('F3 2 km: 8000 (masofa koeff. 1.0)', () =>
    assert.strictEqual(lt.computeFare({ distanceMeters: 2000, prices: P, night: false }).fare, 8000));
  await check('F4 coef 1.2, 12 km: 23000×1.2×0.8 = 22080 → 22000', () =>
    assert.strictEqual(lt.computeFare({ distanceMeters: 12000, prices: { ...P, coefPermille: 1200 }, night: false }).fare, 22000));
  await check('F5 chegaralar: 3000 m → 1.0, 3001 m → 0.9, 50001 m → 0.6', () => {
    assert.strictEqual(lt.distanceCoefPermille(3000), 1000);
    assert.strictEqual(lt.distanceCoefPermille(3001), 900);
    assert.strictEqual(lt.distanceCoefPermille(50001), 600);
  });
  await check('F6 natija har doim butun son va 500 ga karrali', () => {
    for (let m = 100; m < 80000; m += 777) {
      const f = lt.computeFare({ distanceMeters: m, prices: { base: 4300, perKm: 1730, coefPermille: 1137 }, night: m % 2 === 0 }).fare;
      assert.ok(Number.isInteger(f) && f % 500 === 0 && f > 0, `m=${m} fare=${f}`);
    }
  });
  await check('F7b maxsus soatlar: 20–24 (yarim tundan o\'tmaydi) va start==end (o\'chiq)', () => {
    assert.strictEqual(lt.isNightAt(new Date('2026-10-07T15:30:00Z'), 20, 0), true); // 20:30
    assert.strictEqual(lt.isNightAt(new Date('2026-10-07T14:30:00Z'), 20, 0), false); // 19:30
    assert.strictEqual(lt.isNightAt(new Date('2026-10-07T19:30:00Z'), 23, 23), false);
    assert.strictEqual(lt.isNightAt(new Date('2026-10-07T05:00:00Z'), 9, 17), true); // 10:00, start<end
  });
  await check('F7 tun chegarasi (Toshkent): 22:59 kun, 23:00 tun, 05:59 tun, 06:00 kun', () => {
    assert.strictEqual(lt.isNightAt(new Date('2026-10-07T17:59:00Z')), false);
    assert.strictEqual(lt.isNightAt(new Date('2026-10-07T18:00:00Z')), true);
    assert.strictEqual(lt.isNightAt(new Date('2026-10-07T00:59:00Z')), true);
    assert.strictEqual(lt.isNightAt(new Date('2026-10-07T01:00:00Z')), false);
  });
  await check('F8 mintaqa (Dart TaxiPriceRegion bilan bir xil nuqtalar)', () => {
    assert.strictEqual(lt.resolveRegionKey(41.3, 69.25), 'tashkent');
    assert.strictEqual(lt.resolveRegionKey(41.84, 60.39), 'xorazm');
    assert.strictEqual(lt.resolveRegionKey(39.65, 66.95), 'samarqand');
    assert.strictEqual(lt.resolveRegionKey(41.0, 71.6), 'namangan');
    assert.strictEqual(lt.resolveRegionKey(38.0, 65.0), 'default');
  });
  await check('F9 mintaqa narxi globalni bosadi; yo\'q bo\'lsa default mintaqa; umuman yo\'q — null', () => {
    const doc = { local_base: 5000, local_per_km: 1500, regions: { xorazm: { local_base: 4000, local_per_km: 1000, local_coef: 1.1 } } };
    assert.deepStrictEqual(lt.resolvePrices(doc, 'xorazm'), {
      regionKey: 'xorazm', base: 4000, perKm: 1000, coefPermille: 1100,
      nightPermille: 1500, nightStartH: 23, nightEndH: 6, roadFactorPermille: 1300,
      source: 'region:xorazm' });
    assert.strictEqual(lt.resolvePrices(doc, 'tashkent').base, 5000);
    assert.strictEqual(lt.resolvePrices({}, 'xorazm'), null);
  });

  // ── createLocalTaxiTrip ──────────────────────────────────────────────
  await reset();
  await check('C1 buyurtma: server trip yaratadi, narx qotirilgan, tariffVersion + snapshot', async () => {
    const r = await api.createLocalTaxiTrip.run(order(), ctxOf(PASSENGER));
    assert.strictEqual(r.fare, 11500);
    const t = (await db.collection('trips').doc(r.tripId).get()).data();
    assert.strictEqual(t.status, 'searching');
    assert.strictEqual(t.userPhone, PASSENGER);
    assert.strictEqual(t.taxiType, 'local');
    assert.strictEqual(t.lockedFare, 11500);
    assert.strictEqual(t.fareSource, 'server');
    assert.strictEqual(t.tariffVersion, 3);
    assert.strictEqual(t.tariffSnapshot.base, 5000);
    assert.strictEqual(t.tariffSnapshot.regionKey, 'xorazm');
    assert.strictEqual(t.fareNight, false);
    assert.strictEqual(t.geohash4, geoHash.encode(GURLAN.lat, GURLAN.lng, 4));
    assert.strictEqual(t.expiresAt.toMillis(), DAY.getTime() + 180000);
  });
  await check('C2 qayta urinish (bir xil requestId) — ikkinchi trip YO\'Q, Directions qayta chaqirilmaydi', async () => {
    const before = routeCalls;
    const r = await api.createLocalTaxiTrip.run(order(), ctxOf(PASSENGER));
    assert.strictEqual(r.duplicate, true);
    assert.strictEqual((await db.collection('trips').get()).size, 1);
    assert.strictEqual(routeCalls, before);
  });
  await check('C3 tarif o\'zgarsa ESKI trip narxi o\'zgarmaydi', async () => {
    await db.collection('settings').doc('prices').set({ local_base: 9000, localTariffVersion: 4 }, { merge: true });
    const t = (await db.collection('trips').get()).docs[0].data();
    assert.strictEqual(t.lockedFare, 11500);
    assert.strictEqual(t.tariffVersion, 3);
    const r2 = await api.createLocalTaxiTrip.run(order({ requestId: 'req_second01' }), ctxOf(PASSENGER));
    assert.strictEqual(r2.fare, 15000); // (9000+7500)×0.9 = 14850 → 15000
    assert.strictEqual((await db.collection('trips').doc(r2.tripId).get()).data().tariffVersion, 4);
  });
  await check('C4 tunda yaratilgan trip ×1.5 va fareNight=true', async () => {
    await reset();
    clock = NIGHT;
    const r = await api.createLocalTaxiTrip.run(order(), ctxOf(PASSENGER));
    assert.strictEqual(r.fare, 17000);
    assert.strictEqual((await db.collection('trips').doc(r.tripId).get()).data().fareNight, true);
  });
  await check('C5 manzilsiz buyurtma rad: DESTINATION_REQUIRED', async () => {
    await reset();
    assert.strictEqual(await codeOf(api.createLocalTaxiTrip.run(order({ toLat: 0, toLng: 0 }), ctxOf(PASSENGER))), 'DESTINATION_REQUIRED');
    assert.strictEqual(await codeOf(api.createLocalTaxiTrip.run(order({ toAddr: '' }), ctxOf(PASSENGER))), 'DESTINATION_REQUIRED');
  });
  await check('C6 tarif sozlanmagan — TARIFF_NOT_CONFIGURED (hardcode default YO\'Q)', async () => {
    await reset(null);
    assert.strictEqual(await codeOf(api.createLocalTaxiTrip.run(order(), ctxOf(PASSENGER))), 'TARIFF_NOT_CONFIGURED');
  });
  await check('C7 Directions yo\'l bermasa — rad EMAS: to\'g\'ri chiziq × 1.3, distanceSource=estimate', async () => {
    await reset();
    routeMeters = 0;
    const r = await api.createLocalTaxiTrip.run(order(), ctxOf(PASSENGER));
    const t = (await db.collection('trips').doc(r.tripId).get()).data();
    const straight = lt.haversineMeters(GURLAN.lat, GURLAN.lng, 41.86, 60.42);
    assert.strictEqual(t.distanceSource, 'estimate');
    assert.strictEqual(t.lockedDistanceM, Math.round(straight * 1.3));
    assert.strictEqual(t.tariffSnapshot.roadFactorPermille, 1300);
    assert.strictEqual(t.lockedFare, lt.computeFare({
      distanceMeters: t.lockedDistanceM, prices: { base: 5000, perKm: 1500, coefPermille: 1000 }, night: false }).fare);
  });
  await check('C7b Directions xato (timeout) — ham estimate, buyurtma o\'tadi', async () => {
    await reset();
    const saved = routeMeters;
    routeMeters = 'throw';
    const r = await api.createLocalTaxiTrip.run(order(), ctxOf(PASSENGER));
    routeMeters = saved;
    assert.strictEqual((await db.collection('trips').doc(r.tripId).get()).data().distanceSource, 'estimate');
  });
  await check('C7c oddiy holatda distanceSource=route, roadFactor snapshot null', async () => {
    await reset();
    const r = await api.createLocalTaxiTrip.run(order(), ctxOf(PASSENGER));
    const t = (await db.collection('trips').doc(r.tripId).get()).data();
    assert.strictEqual(t.distanceSource, 'route');
    assert.strictEqual(t.tariffSnapshot.roadFactorPermille, null);
  });
  await check('C7d admin tun koeffitsienti 1.2 va soatlari 22–05: 22:30 da ×1.2', async () => {
    await reset({ local_base: 5000, local_per_km: 1500, local_coef: 1.0,
      local_night_coef: 1.2, local_night_start: 22, local_night_end: 5 });
    clock = new Date('2026-10-07T17:30:00Z'); // 22:30 Toshkent
    const r = await api.createLocalTaxiTrip.run(order(), ctxOf(PASSENGER));
    // 12500 × 0.9 × 1.2 = 13500
    assert.strictEqual(r.fare, 13500);
    const t = (await db.collection('trips').doc(r.tripId).get()).data();
    assert.strictEqual(t.tariffSnapshot.nightPermille, 1200);
    assert.strictEqual(t.tariffSnapshot.nightStartH, 22);
  });
  await check('C7e tun koeffitsienti 1.0 — tunda ham oddiy narx', async () => {
    await reset({ local_base: 5000, local_per_km: 1500, local_coef: 1.0, local_night_coef: 1 });
    clock = NIGHT;
    assert.strictEqual((await api.createLocalTaxiTrip.run(order(), ctxOf(PASSENGER))).fare, 11500);
  });
  await check('C8 bloklangan yo\'lovchi — LOCAL_TAXI_BLOCKED (server tomonda)', async () => {
    await reset();
    await db.collection('users').doc(PASSENGER).collection('local_taxi_block').doc('state').set({
      blockedUntil: admin.firestore.Timestamp.fromMillis(DAY.getTime() + 10 * 60000),
    });
    assert.strictEqual(await codeOf(api.createLocalTaxiTrip.run(order(), ctxOf(PASSENGER))), 'LOCAL_TAXI_BLOCKED');
  });
  await check('C9 telefonsiz token — rad', async () => {
    await reset();
    const code = await codeOf(api.createLocalTaxiTrip.run(order(), { auth: { uid: 'x', token: {} } }));
    assert.strictEqual(code, 'PHONE_TOKEN_REQUIRED');
  });
  await check('C10 userPhone har doim token\'dan (klient yuborgan userPhone e\'tiborsiz)', async () => {
    await reset();
    const r = await api.createLocalTaxiTrip.run(order({ userPhone: STRANGER }), ctxOf(PASSENGER));
    assert.strictEqual((await db.collection('trips').doc(r.tripId).get()).data().userPhone, PASSENGER);
  });

  // ── lockLocalTripFare ────────────────────────────────────────────────
  await reset();
  await db.collection('trips').doc('old1').set({
    userPhone: PASSENGER, status: 'accepted', taxiType: 'local', fromLat: GURLAN.lat, fromLng: GURLAN.lng,
    acceptedDriverId: DRIVER, driverId: DRIVER, fromAddr: 'A',
  });
  await check('L1 eski trip: biriktirilgan haydovchi manzil qo\'yadi → server narxi', async () => {
    const r = await api.lockLocalTripFare.run({ tripId: 'old1', toLat: 41.86, toLng: 60.42, toAddr: 'B' }, ctxOf(DRIVER));
    assert.strictEqual(r.fare, 11500);
    const t = (await db.collection('trips').doc('old1').get()).data();
    assert.strictEqual(t.fareSource, 'server');
    assert.strictEqual(t.fareLockVersion, 1);
    assert.strictEqual(t.fareLockedBy, 'driver');
  });
  await check('L2 begona qulf qo\'ya olmaydi', async () => {
    assert.strictEqual(await codeOf(api.lockLocalTripFare.run({ tripId: 'old1', toLat: 41.86, toLng: 60.42, toAddr: 'B' }, ctxOf(STRANGER))), 'NOT_TRIP_PARTICIPANT');
  });
  await check('L3 yakunlangan trip\'ga qulf yo\'q', async () => {
    await db.collection('trips').doc('old1').update({ status: 'completed' });
    assert.strictEqual(await codeOf(api.lockLocalTripFare.run({ tripId: 'old1', toLat: 41.86, toLng: 60.42, toAddr: 'B' }, ctxOf(PASSENGER))), 'TRIP_NOT_ACTIVE');
  });

  // ── K. Yo'l koeffitsienti kalibrovkasi (variant A + D) ────────────────
  const mkSamples = (n, ratio, region = 'xorazm') => Array.from({ length: n }, (_, i) => {
    const to = { lat: GURLAN.lat + 0.01 + i * 0.001, lng: GURLAN.lng + 0.01 };
    const straight = lt.haversineMeters(GURLAN.lat, GURLAN.lng, to.lat, to.lng);
    return { regionKey: region, fromLat: GURLAN.lat, fromLng: GURLAN.lng, toLat: to.lat, toLng: to.lng,
      routeM: Math.round(straight * ratio) };
  });
  await check('K1 30 ta safar, nisbat 1.25 → 1250; 29 ta → null (ma\'lumot yetarli emas)', () => {
    assert.deepStrictEqual(lt.computeRoadFactors(mkSamples(30, 1.25)), { xorazm: { factorPermille: 1250, samples: 30 } });
    assert.deepStrictEqual(lt.computeRoadFactors(mkSamples(29, 1.25)), { xorazm: { factorPermille: null, samples: 29 } });
  });
  await check('K2 chetga chiquvchilar (nisbat >3, qisqa <500 m) tashlanadi; mediana barqaror', () => {
    const s = [...mkSamples(31, 1.3), ...mkSamples(5, 9.0),
      { regionKey: 'xorazm', fromLat: 41.84, fromLng: 60.39, toLat: 41.8401, toLng: 60.3901, routeM: 900 }];
    assert.deepStrictEqual(lt.computeRoadFactors(s), { xorazm: { factorPermille: 1300, samples: 31 } });
  });
  await check('K3 yuqori chegara 2.0 (clamp)', () => {
    assert.strictEqual(lt.computeRoadFactors(mkSamples(30, 2.6)).xorazm.factorPermille, 2000);
  });

  await reset();
  await db.recursiveDelete(db.collection('local_taxi_calibration'));
  const day = admin.firestore.Timestamp.fromMillis(DAY.getTime() - 24 * 3600 * 1000);
  const old = admin.firestore.Timestamp.fromMillis(DAY.getTime() - 40 * 24 * 3600 * 1000);
  let k = 0;
  for (const s of mkSamples(30, 1.25)) {
    await db.collection('trips').doc(`k${k++}`).set({
      taxiType: 'local', fareSource: 'server', distanceSource: 'route', createdAt: day,
      fromLat: s.fromLat, fromLng: s.fromLng, toLat: s.toLat, toLng: s.toLng,
      lockedDistanceM: s.routeM, tariffSnapshot: { regionKey: 'xorazm' },
    });
  }
  // Hisobga kirmasligi kerak: estimate, eski ilova (server narxisiz), 30 kundan eski.
  for (const [i, extra] of [{ distanceSource: 'estimate' }, { fareSource: null }, { createdAt: old }].entries()) {
    const s = mkSamples(1, 2.5)[0];
    await db.collection('trips').doc(`kx${i}`).set({
      taxiType: 'local', fareSource: 'server', distanceSource: 'route', createdAt: day,
      fromLat: s.fromLat, fromLng: s.fromLng, toLat: s.toLat, toLng: s.toLng,
      lockedDistanceM: s.routeM, tariffSnapshot: { regionKey: 'xorazm' }, ...extra,
    });
  }
  await check('K4 haftalik ish: xorazm 1250 (30 namuna), joriy + runs tarixi yoziladi', async () => {
    await api.calibrateLocalTaxiRoadFactor.run({});
    const cur = (await db.collection('local_taxi_calibration').doc('road_factor').get()).data();
    assert.deepStrictEqual(cur.regions.xorazm, { factorPermille: 1250, samples: 30 });
    assert.strictEqual(cur.usedSamples, 30);
    const runs = await db.collection('local_taxi_calibration').doc('road_factor').collection('runs').get();
    assert.strictEqual(runs.size, 1);
  });
  await check('K5 Directions ishlamasa — HISOBLANGAN koeffitsient (1.25) ishlatiladi, manbasi snapshot\'da', async () => {
    routeMeters = 0;
    const r = await api.createLocalTaxiTrip.run(order({ requestId: 'req_calib01' }), ctxOf(PASSENGER));
    const t = (await db.collection('trips').doc(r.tripId).get()).data();
    const straight = lt.haversineMeters(GURLAN.lat, GURLAN.lng, 41.86, 60.42);
    assert.strictEqual(t.lockedDistanceM, Math.round(straight * 1.25));
    assert.strictEqual(t.tariffSnapshot.roadFactorPermille, 1250);
    assert.ok(t.tariffSnapshot.roadFactorSource.startsWith('calibrated:'), t.tariffSnapshot.roadFactorSource);
    routeMeters = 5000;
  });
  await check('K6 boshqa mintaqada ma\'lumot yo\'q — tarif koeffitsienti (1.3), manba tariff', async () => {
    routeMeters = 0;
    const r = await api.createLocalTaxiTrip.run(order({ requestId: 'req_calib02', fromLat: 41.3, fromLng: 69.25, toLat: 41.32, toLng: 69.27 }), ctxOf(PASSENGER));
    const t = (await db.collection('trips').doc(r.tripId).get()).data();
    assert.strictEqual(t.tariffSnapshot.roadFactorPermille, 1300);
    assert.strictEqual(t.tariffSnapshot.roadFactorSource, 'tariff');
    routeMeters = 5000;
  });

  // ── adminSetLocalTaxiPrices ──────────────────────────────────────────
  await reset({ local_base: 5000, local_per_km: 1500, local_coef: 1.0, bread_price: 3000, regions: { tashkent: { local_base: 1, local_per_km: 1 } } });
  await check('A1 oddiy foydalanuvchi narxni o\'zgartira olmaydi', async () => {
    assert.strictEqual(await codeOf(api.adminSetLocalTaxiPrices.run({ global: { base: 1, perKm: 1, coef: 1 } }, ctxOf(PASSENGER))), 'ADMIN_REQUIRED');
  });
  await check('A2 admin saqlaydi: versiya 1, tarix hujjati (kim, avvalgi qiymat), non narxi tegilmaydi, o\'chirilgan mintaqa olib tashlanadi', async () => {
    const r = await api.adminSetLocalTaxiPrices.run({
      global: { base: 6000, perKm: 1600, coef: 1.1 },
      regions: { xorazm: { base: 4000, perKm: 1000, coef: 1 } },
    }, ctxOf(ADMIN));
    assert.strictEqual(r.version, 1);
    const p = (await db.collection('settings').doc('prices').get()).data();
    assert.strictEqual(p.local_base, 6000);
    assert.strictEqual(p.localTariffVersion, 1);
    assert.strictEqual(p.bread_price, 3000);
    assert.deepStrictEqual(Object.keys(p.regions), ['xorazm']);
    const h = (await db.collection('local_taxi_tariffs').doc('v1').get()).data();
    assert.strictEqual(h.changedBy, ADMIN);
    assert.strictEqual(h.previous.local_base, 5000);
  });
  await check('A3 ikkinchi saqlash — versiya 2, yangi trip tariffVersion=2', async () => {
    const r = await api.adminSetLocalTaxiPrices.run({ global: { base: 5000, perKm: 1500, coef: 1 } }, ctxOf(ADMIN));
    assert.strictEqual(r.version, 2);
    const t = await api.createLocalTaxiTrip.run(order({ fromLat: 38, fromLng: 65 }), ctxOf(PASSENGER));
    assert.strictEqual((await db.collection('trips').doc(t.tripId).get()).data().tariffVersion, 2);
  });
  await check('A3b admin tun/yo\'l koeffitsientini saqlaydi — versiya, tarix (avvalgi qiymat bilan)', async () => {
    const r = await api.adminSetLocalTaxiPrices.run({
      global: { base: 5000, perKm: 1500, coef: 1 },
      night: { coef: 1.3, startH: 22, endH: 5 },
      roadFactor: 1.4,
    }, ctxOf(ADMIN));
    assert.strictEqual(r.version, 3);
    const p = (await db.collection('settings').doc('prices').get()).data();
    assert.strictEqual(p.local_night_coef, 1.3);
    assert.strictEqual(p.local_night_start, 22);
    assert.strictEqual(p.local_night_end, 5);
    assert.strictEqual(p.local_road_factor, 1.4);
    const h = (await db.collection('local_taxi_tariffs').doc('v3').get()).data();
    assert.strictEqual(h.local_night_coef, 1.3);
    assert.strictEqual(h.previous.local_night_coef, 1.5);
  });
  await check('A3c tun/yo\'l berilmasa — joriy qiymat saqlanadi', async () => {
    await api.adminSetLocalTaxiPrices.run({ global: { base: 5000, perKm: 1500, coef: 1 } }, ctxOf(ADMIN));
    const p = (await db.collection('settings').doc('prices').get()).data();
    assert.strictEqual(p.local_night_coef, 1.3);
    assert.strictEqual(p.local_road_factor, 1.4);
  });
  await check('A3d noto\'g\'ri tun/yo\'l qiymatlari rad', async () => {
    const g = { base: 5000, perKm: 1500, coef: 1 };
    assert.strictEqual(await codeOf(api.adminSetLocalTaxiPrices.run({ global: g, night: { coef: 5, startH: 23, endH: 6 } }, ctxOf(ADMIN))), 'NIGHT_COEF_INVALID');
    assert.strictEqual(await codeOf(api.adminSetLocalTaxiPrices.run({ global: g, night: { coef: 1.5, startH: 24, endH: 6 } }, ctxOf(ADMIN))), 'NIGHT_HOURS_INVALID');
    assert.strictEqual(await codeOf(api.adminSetLocalTaxiPrices.run({ global: g, roadFactor: 3 }, ctxOf(ADMIN))), 'ROAD_FACTOR_INVALID');
  });
  await check('A4 noto\'g\'ri narx/koeffitsient rad (0, kasr, coef 0)', async () => {
    assert.strictEqual(await codeOf(api.adminSetLocalTaxiPrices.run({ global: { base: 0, perKm: 1, coef: 1 } }, ctxOf(ADMIN))), 'PRICE_INVALID');
    assert.strictEqual(await codeOf(api.adminSetLocalTaxiPrices.run({ global: { base: 100.5, perKm: 1, coef: 1 } }, ctxOf(ADMIN))), 'PRICE_INVALID');
    assert.strictEqual(await codeOf(api.adminSetLocalTaxiPrices.run({ global: { base: 100, perKm: 1, coef: 0 } }, ctxOf(ADMIN))), 'COEF_INVALID');
    assert.strictEqual(await codeOf(api.adminSetLocalTaxiPrices.run({ global: { base: 100, perKm: 1, coef: 1 }, regions: { mars: { base: 1, perKm: 1, coef: 1 } } }, ctxOf(ADMIN))), 'REGION_UNKNOWN');
  });

  const failed = results.filter((p) => !p).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
