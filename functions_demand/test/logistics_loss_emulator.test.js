/**
 * "Yo'qolgan posilka" (D1, 2026-10-16) — poyga/tranzaksiya, HAQIQIY Firestore (Emulator, Admin SDK).
 *
 *   npm --prefix functions_demand run test:loss-tx
 *
 * Qulflanadi:
 *   - ikki parallel `adminMarkShipmentLost` -> BITTA incident, bitta audit, bitta `declared` hodisa;
 *   - `adminMarkShipmentLost` ↔ `confirmDelivery` (kuryer yetkazyapti): faqat BITTASI g'olib —
 *     yoki `delivered` (incident yo'q), yoki `lost` (yetkazish hodisasi yo'q);
 *   - yo'qolish to'liq oqim (haqiqiy tranzaksiya): hujjat shakli.
 * Tranzaksiya tuzilishi: `tx.get` -> tekshiruv -> yozuv; ikki chaqiruv to'qnashsa Firestore qayta uradi
 * va ikkinchisi birinchining incident'ini ko'radi (idempotent natija).
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-loss-tx';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const api = require('../api/logistics');
const config = require('../core/config');
const tariffCore = require('../core/tariff');
const {
  OWNER, K1, ADMIN, ctx, seed, orderPayload, deps, fund, photoFor, DECLARED_VALUE,
} = require('./helpers/logistics_harness');
const { resetEmulator } = require('./helpers/emulator_hooks');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};

const ADMIN2 = '998907770000';
const reset = async () => {
  config.clearCache(); tariffCore.clearCache();
  await resetEmulator(db, seed({ [`users/${ADMIN2}`]: { role: 'superadmin' } }));
};
const ship = async (id) => (await db.collection('shipments').doc(id).get()).data();
const col = async (name) => (await db.collection(name).get()).docs;
const lost = (shipmentId, opId, who = ADMIN) => api.makeAdminMarkShipmentLost(deps(db))(
  { shipmentId, reason: 'Kuryer yo\'qotdi', note: '', opId }, ctx(who));

async function inTransit() {
  const r = await api.makeCreateLogisticsOrder(deps(db))(orderPayload(), ctx(OWNER));
  const shipmentId = r.shipmentIds[0];
  await fund(db, shipmentId);
  const [legId] = (await ship(shipmentId)).legIds;
  await api.makeAcceptLeg(deps(db))({ legId }, ctx(K1));
  const sec = await api.makeGetShipmentSecrets(deps(db))({ shipmentId }, ctx(OWNER));
  await api.makeScanHandover(deps(db))({ legId, code: sec.handoverCode, photoUrls: photoFor(K1) }, ctx(K1));
  return { shipmentId, legId, orderId: r.orderId, sec };
}

(async () => {
  await check('to\'liq oqim: hujjat shakli haqiqiy Firestore\'da (shipment lost/loss_pending, LEG disputed, incident, hodisa, audit, ORDER problem)', async () => {
    await reset();
    const { shipmentId, legId, orderId } = await inTransit();
    const r = await lost(shipmentId, 'lost-op-0001');
    assert.strictEqual(r.idempotent, false);
    const s = await ship(shipmentId);
    assert.strictEqual(s.status, 'lost');
    assert.strictEqual(s.paymentStatus, 'loss_pending');
    assert.strictEqual((await db.collection('demands').doc(legId).get()).data().status, 'disputed');
    const inc = (await db.collection('logistics_incidents').doc(shipmentId).get()).data();
    assert.strictEqual(inc.goodsValue, DECLARED_VALUE);
    assert.deepStrictEqual(inc.courier, { uid: K1, accountId: `acc${K1}` });
    assert.strictEqual(inc.declaredBy, ADMIN);
    const ev = await db.collection('logistics_incidents').doc(shipmentId).collection('events').get();
    assert.deepStrictEqual(ev.docs.map((d) => d.id), ['declared']);
    assert.ok((await db.collection('logistics_audit').doc(`lost_${shipmentId}`).get()).exists);
    assert.strictEqual((await db.collection('logistics_orders').doc(orderId).get()).data().status, 'problem');
  });

  await check('ikki parallel chaqiruv (turli admin, turli opId) — BITTA incident, bitta g\'olib, bitta audit', async () => {
    await reset();
    const { shipmentId } = await inTransit();
    const [a, b] = await Promise.all([lost(shipmentId, 'lost-op-aaaa', ADMIN), lost(shipmentId, 'lost-op-bbbb', ADMIN2)]);
    assert.strictEqual([a, b].filter((x) => x.idempotent === false).length, 1, 'aynan bitta g\'olib');
    assert.strictEqual([a, b].filter((x) => x.idempotent === true).length, 1);
    assert.strictEqual((await col('logistics_incidents')).length, 1);
    const ev = await db.collection('logistics_incidents').doc(shipmentId).collection('events').get();
    assert.strictEqual(ev.size, 1);
    assert.strictEqual((await col('logistics_audit')).filter((d) => d.id.startsWith('lost_')).length, 1);
    // G va holatlar bir marta yozilgan.
    const s = await ship(shipmentId);
    assert.strictEqual(s.paymentStatus, 'loss_pending');
    // To'rt parallel — baribir bitta.
    await reset();
    const t = await inTransit();
    const many = await Promise.all([1, 2, 3, 4].map((i) => lost(t.shipmentId, `lost-op-${i}${i}${i}${i}${i}${i}`, i % 2 ? ADMIN : ADMIN2)));
    assert.strictEqual(many.filter((x) => x.idempotent === false).length, 1);
    assert.strictEqual((await col('logistics_incidents')).length, 1);
  });

  await check('adminMarkShipmentLost ↔ confirmDelivery: faqat BITTASI g\'olib (delivered YOKI lost, ikkalasi emas)', async () => {
    for (let round = 0; round < 3; round += 1) {
      await reset();
      const { shipmentId, legId, sec } = await inTransit();
      const [lostRes, delRes] = await Promise.all([
        lost(shipmentId, `lost-op-r${round}x`).then((v) => ({ ok: true, v }), (e) => ({ ok: false, e })),
        api.makeConfirmDelivery(deps(db))(
          { legId, deliveryCode: sec.deliveryCode, photoUrls: photoFor(K1) }, ctx(K1),
        ).then((v) => ({ ok: true, v }), (e) => ({ ok: false, e })),
      ]);
      const s = await ship(shipmentId);
      const incidents = await col('logistics_incidents');
      const delivery = (await col('custody_events')).filter((d) => d.data().kind === 'delivery');
      if (s.status === 'lost') {
        assert.strictEqual(lostRes.ok, true);
        assert.strictEqual(delRes.ok, false, 'yo\'qolgan jo\'natma yetkazilmaydi');
        assert.strictEqual(delivery.length, 0);
        assert.strictEqual(incidents.length, 1);
        assert.strictEqual(s.paymentStatus, 'loss_pending');
      } else {
        assert.strictEqual(s.status, 'delivered');
        assert.strictEqual(delRes.ok, true);
        assert.strictEqual(lostRes.ok, false, 'yetkazilgan jo\'natma yo\'qolgan deb belgilanmaydi');
        assert.strictEqual(lostRes.e.details.reason, 'shipment_not_lossable');
        assert.strictEqual(incidents.length, 0);
        assert.strictEqual(delivery.length, 1);
        assert.strictEqual(s.paymentStatus, 'escrow_funded', 'yetkazildi: pul eskrouda (RELEASE default codebase\'da)');
      }
    }
  });

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi.`);
  process.exit(failed ? 1 : 0);
})();
