/**
 * Ichki (Ulgurji) jo'natma zanjiri + NAQD — HAQIQIY Firestore tranzaksiyasi bilan (Emulator, Admin SDK).
 *
 *   firebase emulators:exec --only firestore --project demo-internal-tx "node test/logistics_internal_chain_emulator.test.js"
 *
 * Qulflanadi (S7/S5, 2026-11-14):
 *   - createShipmentInternal parallel (trigger takrori ‖ reconcile): AYNAN BITTA jo'natma/ORDER/LEG to'plami;
 *   - openCashShipment parallel: bitta ochilish, muddat bir marta, LEG'lar bir marta ochiladi;
 *   - recordCashRefusal parallel (paid ‖ unpaid): aynan bitta natija, ikkinchisi ziddiyat/idempotent;
 *   - Ulgurji zanjiri muddati ‖ oxirgi olish: yoki locked (eskrou joyida), yoki expired +
 *     `wholesale_refund_pending` (HECH QACHON `refund_pending`).
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-internal-tx';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const api = require('../api/logistics');
const config = require('../core/config');
const tariffCore = require('../core/tariff');
const L = require('../core/logistics');
const {
  OWNER, K1, F1, NOW, ctx, seed, deps, fund, photoFor,
} = require('./helpers/logistics_harness');
const { resetEmulator, retryOnEmulatorClosedTx } = require('./helpers/emulator_hooks');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};

const CHAIN_CFG = {
  enabled: true,
  matchingEnabled: true,
  pushEnabled: false,
  logistics: {
    stage: 'public',
    chainMode: 'assemble_all',
    chainAssemblyHours: 48,
    transferPoints: { regions: { toshkent_shahri: { districtId: 'yunusobod', addressText: 'Yunusobod bekat' } } },
  },
};
const ORIGIN = { regionId: 'xorazm', districtId: 'gurlan', lat: 41.84, lng: 60.39, addressText: 'Gurlan, Sotuvchi' };
const DEST = { regionId: 'toshkent_shahri', districtId: 'chilonzor', lat: 41.28, lng: 69.2, addressText: 'Chilonzor 9' };
const PARCEL = { actualWeightG: 5000, declaredValue: 150000 };
const BUYER = '998905556677';
const H48 = 48 * 3600 * 1000;

async function reset() {
  config.clearCache(); tariffCore.clearCache();
  await resetEmulator(db, seed({
    'module_config/logistics_all': CHAIN_CFG,
    'geo_districts/yunusobod': { regionId: 'toshkent_shahri' },
  }));
}
const ship = async (id) => (await db.collection('shipments').doc(id).get()).data();
const settle = (p) => p.then((v) => ({ ok: true, v }), (e) => ({ ok: false, e }));
const accept = (legId, p, now) => retryOnEmulatorClosedTx(() => api.makeAcceptLeg(deps(db, now))({ legId }, ctx(p)));
const count = async (col) => (await db.collection(col).get()).size;

async function input(key, over = {}) {
  const rq = await api.quoteParcelForPoints(db, ORIGIN, DEST, PARCEL, { dimsOptional: true });
  return {
    idempotencyKey: key,
    ownerId: OWNER,
    recipientId: BUYER,
    recipient: { name: 'Xaridor' },
    origin: rq.origin,
    destination: rq.destination,
    parcel: { ...PARCEL, lengthCm: null, widthCm: null, heightCm: null, description: 'Un', fragile: false },
    priceSnapshot: rq.quote,
    pricedAt: NOW,
    source: 'wholesale',
    extra: { wholesaleOrderId: key },
    ...over,
  };
}

(async () => {
  await check('createShipmentInternal parallel ×4 (trigger takrori ‖ reconcile): AYNAN BITTA jo\'natma, 3 LEG', async () => {
    await reset();
    const inp = await input('wholesale_ship_TX1');
    const rs = await Promise.all([1, 2, 3, 4].map(() => settle(api.createShipmentInternal(deps(db), inp))));
    assert.ok(rs.every((r) => r.ok), rs.filter((r) => !r.ok).map((r) => r.e.message).join('; '));
    assert.strictEqual(new Set(rs.map((r) => r.v.shipmentId)).size, 1);
    assert.strictEqual(rs.filter((r) => !r.v.duplicate).length, 1, 'bitta g\'olib');
    assert.strictEqual(await count('shipments'), 1);
    assert.strictEqual(await count('logistics_orders'), 1);
    assert.strictEqual(await count('demands'), 3);
  });

  await check('openCashShipment parallel ×3: bitta ochilish, muddat bir marta, 3 LEG active', async () => {
    await reset();
    const r = await api.createShipmentInternal(deps(db), await input('wholesale_ship_TX2', { deliveryPaymentMethod: 'cash' }));
    const outs = await Promise.all([1, 2, 3].map(() => settle(retryOnEmulatorClosedTx(() => api.openCashShipment(deps(db), r.shipmentId)))));
    assert.ok(outs.every((o) => o.ok), outs.filter((o) => !o.ok).map((o) => o.e.message).join('; '));
    assert.strictEqual(outs.filter((o) => o.v.opened).length, 1, 'aynan bitta ochuvchi');
    const s = await ship(r.shipmentId);
    assert.strictEqual(s.paymentStatus, 'cash_on_delivery');
    assert.strictEqual(s.chain.deadlineAt.toMillis(), NOW.getTime() + H48);
    for (const id of s.legIds) {
      assert.strictEqual((await db.collection('demands').doc(id).get()).data().status, 'active');
    }
  });

  await check('recordCashRefusal parallel (paid ‖ unpaid): aynan bitta natija yoziladi, ikkinchisi ziddiyat', async () => {
    await reset();
    const r = await api.createShipmentInternal(deps(db), await input('wholesale_ship_TX3', { deliveryPaymentMethod: 'cash' }));
    await api.openCashShipment(deps(db), r.shipmentId);
    const { legIds } = await ship(r.shipmentId);
    await accept(legIds[1], F1);
    await accept(legIds[2], F1);
    await accept(legIds[0], K1);
    const q = (await db.collection('shipments').doc(r.shipmentId).collection('private').doc('secrets').get()).data().qrSecret;
    const code = L.handoverCodeFor(r.shipmentId, q);
    const scan = api.makeScanHandover(deps(db));
    await scan({ legId: legIds[0], code, photoUrls: photoFor(K1) }, ctx(K1));
    await scan({ legId: legIds[1], code, photoUrls: photoFor(F1) }, ctx(F1));
    await scan({ legId: legIds[2], code, photoUrls: photoFor(F1) }, ctx(F1));
    const rec = (paid) => settle(retryOnEmulatorClosedTx(() => api.recordCashRefusal(deps(db), {
      shipmentId: r.shipmentId, legId: legIds[2], courierId: F1, paid,
    })));
    const [a, b] = await Promise.all([rec(true), rec(false)]);
    const s = await ship(r.shipmentId);
    const winner = s.deliveryPayment.refusal.paid;
    assert.ok([a, b].filter((x) => x.ok && x.v.recorded).length === 1, 'aynan bitta yozuv');
    const loser = winner ? b : a;
    assert.ok(!loser.ok && loser.e.details.reason === 'cash_refusal_conflict', `yutqazgan: ${loser.ok ? 'ok' : loser.e.message}`);
    assert.strictEqual(s.deliveryPayment.status, winner ? 'refusal_collected' : 'refusal_unpaid');
    assert.ok((await db.collection('logistics_audit').doc(`cash_refusal_${r.shipmentId}`).get()).exists);
  });

  await check('Ulgurji zanjiri muddati ‖ oxirgi olish: locked (eskrou) YOKI expired + wholesale_refund_pending (3 raund)', async () => {
    await reset();
    for (let round = 0; round < 3; round += 1) {
      const r = await api.createShipmentInternal(deps(db), await input(`wholesale_ship_TX4_${round}`));
      await fund(db, r.shipmentId);
      const { legIds } = await ship(r.shipmentId);
      await accept(legIds[1], F1);
      await accept(legIds[2], F1);
      const edge = new Date(NOW.getTime() + H48 - 1000);
      const late = new Date(NOW.getTime() + H48 + 1000);
      const [acc, sw] = await Promise.all([
        settle(accept(legIds[0], K1, edge)),
        settle(retryOnEmulatorClosedTx(() => api.expireChain(deps(db, late), r.shipmentId, late))),
      ]);
      assert.ok(sw.ok, `sweeper: ${sw.e && sw.e.message}`);
      const s = await ship(r.shipmentId);
      assert.notStrictEqual(s.paymentStatus, 'refund_pending', 'Ulgurji: sotuvchi hamyoniga refund HECH QACHON');
      if (s.chain.state === 'locked') {
        assert.ok(acc.ok);
        assert.strictEqual(s.paymentStatus, 'escrow_funded');
      } else {
        assert.strictEqual(s.chain.state, 'expired');
        assert.strictEqual(s.paymentStatus, 'wholesale_refund_pending');
        assert.ok(!acc.ok);
      }
    }
  });

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi`);
  process.exit(failed ? 1 : 0);
})();
