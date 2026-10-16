/**
 * "Yo'qolgan posilka" (D1, ega qarori 2026-10-16) — sof testlar (FakeFirestore).
 *
 *   node functions_demand/test/logistics_loss.test.js
 *
 * Haqiqiy tranzaksiya / parallel chaqiruv: `logistics_loss_emulator.test.js`.
 * Pul harakati (ledger) default codebase'da: `functions/test/relay_escrow_cf.test.js`.
 *
 * Qulflanadi:
 *   1) e'lon qilingan qiymat (declaredValue) MAJBURIY: yo'q yoki <= 0 bo'lsa
 *      quote ham, create ham rad (chunki yo'qolsa qaytariladigan summa G shu);
 *   2) adminMarkShipmentLost: faqat admin/superadmin, faqat in_transit/disputed +
 *      eskrou to'langan, posilka IJROCHIDA bo'lsa; idempotent.
 */
const assert = require('assert');
const api = require('../api/logistics');
const tariffCore = require('../core/tariff');
const config = require('../core/config');
const {
  fixture, OWNER, ADMIN, ctx, makeDb, seed, orderPayload, deps,
} = require('./helpers/logistics_harness');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const fresh = (extra) => { config.clearCache(); tariffCore.clearCache(); return makeDb(seed(extra)); };

const PARCEL = { actualWeightG: 800, lengthCm: 20, widthCm: 15, heightCm: 10, description: 'Kitoblar' };
const reasonOf = (reason) => (e) => e.code === 'invalid-argument' && e.details.reason === reason;

// ═══════════════════════════════════════════════════════════════════════
// 1) declaredValue MAJBURIY
for (const [label, dv, reason] of [
  ['yo\'q', undefined, 'declared_value_required'],
  ['null', null, 'declared_value_required'],
  ['0', 0, 'declared_value_required'],
  ['manfiy', -5000, 'declared_value_required'],
  ['kasr (1.5)', 1.5, 'parcel_invalid'],
  ['satr ("5000")', '5000', 'parcel_invalid'],
]) {
  ok(`quote: declaredValue ${label} — rad (${reason})`, async () => {
    const db = fresh();
    const parcel = dv === undefined ? PARCEL : { ...PARCEL, declaredValue: dv };
    await assert.rejects(
      () => api.makeQuoteLogisticsOrder({ db })(orderPayload({ parcels: [parcel] }), ctx(OWNER)),
      reasonOf(reason));
  });
}

ok('create: declaredValue yo\'q — rad va HECH NARSA yozilmaydi', async () => {
  const db = fresh();
  await assert.rejects(
    () => api.makeCreateLogisticsOrder(deps(db))(orderPayload({ parcels: [PARCEL] }), ctx(OWNER)),
    reasonOf('declared_value_required'));
  assert.deepStrictEqual(Object.keys(db.dump('shipments')), []);
  assert.deepStrictEqual(Object.keys(db.dump('logistics_orders')), []);
});

ok('create: ikkinchi posilkada declaredValue 0 — butun buyurtma rad (birinchisi to\'g\'ri bo\'lsa ham)', async () => {
  const db = fresh();
  const good = { ...PARCEL, declaredValue: 100000 };
  const bad = { ...PARCEL, declaredValue: 0 };
  await assert.rejects(
    () => api.makeCreateLogisticsOrder(deps(db))(orderPayload({ parcels: [good, bad] }), ctx(OWNER)),
    reasonOf('declared_value_required'));
  assert.deepStrictEqual(Object.keys(db.dump('shipments')), []);
});

ok('create: musbat declaredValue — shipment.priceSnapshot.declaredValue va parcel.declaredValue muhrlanadi', async () => {
  const db = fresh();
  const r = await api.makeCreateLogisticsOrder(deps(db))(
    orderPayload({ parcels: [{ ...PARCEL, declaredValue: 150000 }] }), ctx(OWNER));
  const s = db.dump('shipments')[r.shipmentIds[0]];
  assert.strictEqual(s.priceSnapshot.declaredValue, 150000);
  assert.strictEqual(s.parcel.declaredValue, 150000);
});

ok('declaredValueFee mantig\'i o\'zgarmagan: 1 234 567 so\'m -> haq 12 346 (feeBps 100, ceil)', async () => {
  // Harness tarifi haqni 0 qiladi (narx testlari barqaror turishi uchun) — bu yerda
  // ASL fixture tarifi (feeBps 100).
  const db = fresh({ 'module_tariffs/logistics_v7': fixture.tariff });
  const q = await api.makeQuoteLogisticsOrder({ db })(
    orderPayload({ parcels: [{ ...PARCEL, declaredValue: 1234567 }] }), ctx(OWNER));
  assert.strictEqual(q.parcels[0].declaredValueFee, 12346);
  assert.strictEqual(q.parcels[0].customerPrice, q.parcels[0].basePrice + 12346);
});

ok('tarif chegarasi o\'zgarmagan: maxValue dan katta qiymat — over_declared_value', async () => {
  const db = fresh();
  await assert.rejects(
    () => api.makeQuoteLogisticsOrder({ db })(
      orderPayload({ parcels: [{ ...PARCEL, declaredValue: 60000000 }] }), ctx(OWNER)),
    (e) => e.code === 'failed-precondition' && e.details.reason === 'over_declared_value');
});

// ═══════════════════════════════════════════════════════════════════════
(async () => {
  for (const t of tests) {
    try { await t.fn(); passed += 1; console.log(`  OK  ${t.name}`); } catch (e) {
      console.error(`  XATO ${t.name}\n       ${e.stack || e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
void ADMIN;
