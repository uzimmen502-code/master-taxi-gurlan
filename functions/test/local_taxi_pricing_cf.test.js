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
  fetchRoute: async () => { routeCalls += 1; return routeMeters ? { distanceMeters: routeMeters, polyline: 'abc' } : null; },
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
    assert.deepStrictEqual(lt.resolvePrices(doc, 'xorazm'), { regionKey: 'xorazm', base: 4000, perKm: 1000, coefPermille: 1100, source: 'region:xorazm' });
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
  await check('C7 marshrut topilmasa — ROUTE_NOT_FOUND, trip yaratilmaydi', async () => {
    await reset();
    routeMeters = 0;
    assert.strictEqual(await codeOf(api.createLocalTaxiTrip.run(order(), ctxOf(PASSENGER))), 'ROUTE_NOT_FOUND');
    assert.strictEqual((await db.collection('trips').get()).size, 0);
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
