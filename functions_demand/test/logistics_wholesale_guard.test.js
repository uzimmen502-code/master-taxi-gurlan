/**
 * Ulgurji jo'natmasi himoyasi (jonli kod feat/ulg-relay-guards, 2026-10-31) relay zanjiri
 * bilan birlashtirilgandan keyin ham saqlanadi (2026-11-07), FakeFirestore.
 *
 *   node functions_demand/test/logistics_wholesale_guard.test.js
 *
 * Qulflanadi:
 *   - sotuvchi (ORDER egasi) Ulgurji buyurtmasini bekor qila olmaydi — wholesale_managed
 *     (belgi ORDER'da ham, jo'natmada ham);
 *   - getShipmentSecrets: Ulgurji jo'natmasida egasi (sotuvchi) yetkazish kodini OLMAYDI,
 *     egasi = qabul qiluvchi bo'lsa — oladi; oddiy jo'natmada egasi oladi (o'zgarmagan).
 */
const assert = require('assert');
const api = require('../api/logistics');
const config = require('../core/config');
const tariffCore = require('../core/tariff');
const { OWNER, ctx, makeDb, seed, deps } = require('./helpers/logistics_harness');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

function fresh(docs) {
  config.clearCache(); tariffCore.clearCache();
  return makeDb(seed(docs || {}));
}

async function rejects(p, code, reason) {
  try { await p; } catch (e) {
    assert.strictEqual(e.code, code, `code: ${e.code} ${e.message}`);
    if (reason) assert.strictEqual((e.details || {}).reason, reason, `reason: ${JSON.stringify(e.details)}`);
    return;
  }
  throw new Error('rad etilishi kutilgan edi');
}

function shipDoc(extra = {}) {
  return {
    orderId: 'O1', ownerId: OWNER, trackingNumber: 'AVA-W1', status: 'ready',
    paymentStatus: 'escrow_funded', custodyCount: 0, legIds: [], legCount: 1,
    currentCustodian: { kind: 'sender', id: OWNER }, ...extra,
  };
}

ok('sotuvchi bekor qila olmaydi: ORDER belgisi (source wholesale)', async () => {
  const db = fresh({
    'logistics_orders/O1': { ownerId: OWNER, source: 'wholesale', status: 'ready' },
    'shipments/S1': shipDoc(),
  });
  await rejects(api.makeCancelLogisticsOrder(deps(db))({ orderId: 'O1' }, ctx(OWNER)), 'permission-denied', 'wholesale_managed');
});

ok('sotuvchi bekor qila olmaydi: faqat jo\'natmada wholesaleOrderId', async () => {
  const db = fresh({
    'logistics_orders/O1': { ownerId: OWNER, status: 'ready' },
    'shipments/S1': shipDoc({ wholesaleOrderId: 'W1' }),
  });
  await rejects(api.makeCancelLogisticsOrder(deps(db))({ orderId: 'O1' }, ctx(OWNER)), 'permission-denied', 'wholesale_managed');
});

ok('getShipmentSecrets: Ulgurji — egasi (sotuvchi) yetkazish kodini olmaydi; egasi = qabul qiluvchi — oladi; oddiy — oladi', async () => {
  const db = fresh({
    'shipments/SW': shipDoc({ source: 'wholesale', recipientId: '998900000777' }),
    'shipments/SW/private/secrets': { qrSecret: 'q1' },
    'shipments/SR': shipDoc({ source: 'wholesale_return', recipientId: OWNER }),
    'shipments/SR/private/secrets': { qrSecret: 'q2' },
    'shipments/SN': shipDoc(),
    'shipments/SN/private/secrets': { qrSecret: 'q3' },
  });
  const get = api.makeGetShipmentSecrets(deps(db));
  const w = await get({ shipmentId: 'SW' }, ctx(OWNER));
  assert.strictEqual(w.deliveryCode, undefined, 'sotuvchiga yetkazish kodi yo\'q');
  assert.ok(w.handoverCode, 'topshirish kodi bor');
  const r = await get({ shipmentId: 'SR' }, ctx(OWNER));
  assert.ok(r.deliveryCode, 'egasi = qabul qiluvchi — kod bor');
  const n = await get({ shipmentId: 'SN' }, ctx(OWNER));
  assert.ok(n.deliveryCode, 'oddiy jo\'natma — o\'zgarmagan');
});

(async () => {
  for (const t of tests) {
    try { await t.fn(); passed += 1; console.log(`PASS - ${t.name}`); } catch (e) { console.log(`FAIL - ${t.name} :: ${e.message}`); }
  }
  console.log(`\n${passed}/${tests.length} passed`);
  process.exit(passed === tests.length ? 0 : 1);
})();
