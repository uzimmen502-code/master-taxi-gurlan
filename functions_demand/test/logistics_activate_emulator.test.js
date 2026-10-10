/**
 * LEG ochish (`activateLeg`: `onShipmentFunded`, `adminReactivateLeg`) va
 * `acceptLeg` — HAQIQIY Firestore tranzaksiyasi bilan (Emulator, Admin SDK).
 *
 *   npm --prefix functions_demand run test:activate-tx
 *
 * Qulflanadi (2026-10-10), har bir POYGA hook bilan aniq joyda:
 *   - to'lov triggeri ↔ qayta rejalash: bekor qilingan (eski reja) LEG
 *     qayta OCHILMAYDI
 *   - trigger takrori: kuryer olgan LEG'ni ikkinchi ochish `active`ga
 *     qaytarmaydi, kuryer match'i `new`ga qaytmaydi
 *   - acceptLeg: joriy marshrutda yo'q LEG olinmaydi (`leg_superseded`)
 *   - ikki admin bir vaqtda qayta ochsa: bittasi ochadi, match'lar o'chib
 *     ketmaydi (kuryer LEG'ni ola oladi)
 *   - qayta ochish ↔ qayta rejalash: eski reja LEG'i ochilmaydi
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-activate-tx';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const api = require('../api/logistics');
const maint = require('../api/maintenance');
const config = require('../core/config');
const tariffCore = require('../core/tariff');
const {
  OWNER, K1, ADMIN, NOW, ctx, seed, orderPayload, deps, fund,
} = require('./helpers/logistics_harness');
const { resetEmulator, dbWithHook } = require('./helpers/emulator_hooks');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};

async function reset() {
  config.clearCache(); tariffCore.clearCache();
  await resetEmulator(db, seed());
}
const ship = async (id) => (await db.collection('shipments').doc(id).get()).data();
const leg = async (id) => (await db.collection('demands').doc(id).get()).data();
const matchOf = async (legId, p) => (await db.collection('demand_matches').doc(`${legId}_${p}`).get()).data();
const settle = (p) => p.then((v) => ({ ok: true, v }), (e) => ({ ok: false, e }));
const NEW_ROUTE = [
  { to: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
  { from: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
];
const LATER = new Date(NOW.getTime() + (3 * 24 + 1) * 3600 * 1000);

/** Yaratilgan, TO'LANMAGAN jo'natma (LEG-1 draft). */
async function newShipment() {
  const r = await api.makeCreateLogisticsOrder(deps(db))(orderPayload(), ctx(OWNER));
  return r.shipmentIds[0];
}
/** Eskrou tushdi deb belgilaydi (trigger'siz) — before/after qaytaradi. */
async function markFunded(shipmentId) {
  const ref = db.collection('shipments').doc(shipmentId);
  const before = (await ref.get()).data();
  await ref.update({ paymentStatus: 'escrow_funded', status: 'ready', fundedAt: NOW });
  return { before, after: (await ref.get()).data() };
}
/** To'langan, LEG-1 muddati tugagan (sweeper) jo'natma. */
async function expiredShipment() {
  const shipmentId = await newShipment();
  await fund(db, shipmentId);
  await maint.makeExpireSweeper({ db, now: () => LATER })();
  const [legId] = (await ship(shipmentId)).legIds;
  assert.strictEqual((await leg(legId)).status, 'expired');
  return { shipmentId, legId };
}

(async () => {
  await check('to\'lov triggeri ↔ qayta rejalash: eski (bekor) LEG qayta OCHILMAYDI', async () => {
    await reset();
    const shipmentId = await newShipment();
    const [oldLeg] = (await ship(shipmentId)).legIds;
    const { before, after } = await markFunded(shipmentId);
    // Trigger LEG'ni `draft` deb o'qidi; config o'qilayotganda admin qayta rejalaydi.
    const hooked = dbWithHook(db, 'module_config', async () => {
      await api.makeAdminPlanShipmentRoute(deps(db))({ shipmentId, reason: 'poyga', legs: NEW_ROUTE }, ctx(ADMIN));
    });
    config.clearCache();
    const r = await api.makeOnShipmentFunded({ ...deps(db), db: hooked })(before, after, shipmentId);
    assert.strictEqual((await leg(oldLeg)).status, 'cancelled', `eski LEG ochildi: ${JSON.stringify(r)}`);
    assert.ok(!r.activated, JSON.stringify(r));
    const s = await ship(shipmentId);
    assert.ok(!s.legIds.includes(oldLeg));
    assert.strictEqual((await leg(s.legIds[0])).status, 'active', 'yangi reja LEG-1 ochiq');
  });

  await check('trigger takrori: kuryer olgan LEG active\'ga QAYTMAYDI, match accepted qoladi', async () => {
    await reset();
    const shipmentId = await newShipment();
    const [legId] = (await ship(shipmentId)).legIds;
    const { before, after } = await markFunded(shipmentId);
    // A LEG'ni `draft` deb o'qidi; shu orada B ochib bo'ladi va K1 oladi.
    const hooked = dbWithHook(db, 'module_config', async () => {
      config.clearCache();
      const b = await api.makeOnShipmentFunded(deps(db))(before, after, shipmentId);
      assert.strictEqual(b.activated, true, JSON.stringify(b));
      await api.makeAcceptLeg(deps(db))({ legId }, ctx(K1));
    });
    config.clearCache();
    const a = await api.makeOnShipmentFunded({ ...deps(db), db: hooked })(before, after, shipmentId);
    const l = await leg(legId);
    assert.strictEqual(l.status, 'accepted', `A qabulni bosib ketdi: ${JSON.stringify(a)}`);
    assert.strictEqual(l.assignment.providerId, K1);
    assert.strictEqual((await matchOf(legId, K1)).status, 'accepted');
    assert.ok(!a.activated, JSON.stringify(a));
  });

  await check('acceptLeg: joriy marshrutda YO\'Q LEG olinmaydi (leg_superseded)', async () => {
    await reset();
    const shipmentId = await newShipment();
    await fund(db, shipmentId);
    const [legId] = (await ship(shipmentId)).legIds;
    // Eski reja izi: LEG active, match bor, lekin jo'natma boshqa rejada.
    await db.collection('shipments').doc(shipmentId).update({ legIds: ['otherLegX'] });
    const out = await settle(api.makeAcceptLeg(deps(db))({ legId }, ctx(K1)));
    assert.strictEqual(out.ok, false, 'eski reja LEG\'i olindi');
    assert.strictEqual(out.e.details && out.e.details.reason, 'leg_superseded', out.e.message);
    assert.strictEqual((await leg(legId)).status, 'active');
  });

  await check('ikki admin bir vaqtda qayta ochsa: bittasi ochadi, match\'lar qoladi, kuryer oladi', async () => {
    await reset();
    const { legId } = await expiredShipment();
    const d = { ...deps(db), now: () => LATER };
    let b = null;
    // A eski holatni tekshirdi; modul konfigini o'qiyotganda B to'liq ochib bo'ladi.
    const hooked = dbWithHook(db, 'module_config', async () => {
      b = await settle(api.makeAdminReactivateLeg(d)({ legId, reason: 'B' }, ctx(ADMIN)));
    });
    config.clearCache();
    const a = await settle(api.makeAdminReactivateLeg({ ...d, db: hooked })({ legId, reason: 'A' }, ctx(ADMIN)));
    assert.strictEqual(b && b.ok, true, `B: ${b && b.e && b.e.message}`);
    assert.strictEqual(a.ok, false, 'ikkalasi ham ochdi');
    const l = await leg(legId);
    assert.strictEqual(l.status, 'active');
    assert.strictEqual(l.reopenCount, 1);
    const m = await matchOf(legId, K1);
    assert.ok(m && m.status === 'new', `K1 match: ${JSON.stringify(m && m.status)}`);
    await api.makeAcceptLeg(d)({ legId }, ctx(K1));
    assert.strictEqual((await leg(legId)).status, 'accepted');
  });

  await check('qayta ochish ↔ qayta rejalash: eski reja LEG\'i OCHILMAYDI', async () => {
    await reset();
    const { shipmentId, legId } = await expiredShipment();
    const d = { ...deps(db), now: () => LATER };
    // A LEG joriy rejada ekanini tekshirdi; konfig o'qilayotganda admin qayta rejalaydi.
    const hooked = dbWithHook(db, 'module_config', async () => {
      await api.makeAdminPlanShipmentRoute(d)({ shipmentId, reason: 'poyga', legs: NEW_ROUTE }, ctx(ADMIN));
    });
    config.clearCache();
    const a = await settle(api.makeAdminReactivateLeg({ ...d, db: hooked })({ legId }, ctx(ADMIN)));
    assert.strictEqual((await leg(legId)).status, 'expired', 'eski reja LEG\'i ochildi');
    assert.strictEqual(a.ok, false);
    assert.ok(!(await ship(shipmentId)).legIds.includes(legId));
  });

  await check('oddiy holat: to\'lov → LEG ochiladi; qayta ochish → match yangilanadi', async () => {
    await reset();
    const shipmentId = await newShipment();
    const r = await fund(db, shipmentId);
    assert.strictEqual(r.activated, true, JSON.stringify(r));
    await reset();
    const { legId } = await expiredShipment();
    const res = await api.makeAdminReactivateLeg({ ...deps(db), now: () => LATER })({ legId }, ctx(ADMIN));
    assert.strictEqual(res.ok, true);
    assert.strictEqual((await matchOf(legId, K1)).status, 'new');
  });

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi.`);
  process.exit(failed ? 1 : 0);
})();
