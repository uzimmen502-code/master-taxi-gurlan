/**
 * Relay zanjiri (assemble_all, ega qarori 2026-11-07) — HAQIQIY Firestore
 * tranzaksiyasi bilan (Emulator, Admin SDK).
 *
 *   npm --prefix functions_demand run test:chain-tx
 *
 * Qulflanadi:
 *   - ikki parallel «oxirgi» olish (turli LEG, turli kuryer): ikkalasi ham oladi,
 *     qulf AYNAN BIR MARTA, `claimed` = LEG soni, kontaktlar to'liq;
 *   - bitta oxirgi LEG uchun ikki kuryer: aynan bitta g'olib;
 *   - muddat sweeper'i ↔ oxirgi olish: yoki qulflangan (refund yo'q), yoki
 *     muddati o'tgan (olish rad) — hech qachon ikkalasi emas.
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-chain-tx';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const api = require('../api/logistics');
const config = require('../core/config');
const tariffCore = require('../core/tariff');
const {
  OWNER, K1, F1, NOW, ctx, seed, orderPayload, deps, fund,
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
const DEST = { regionId: 'toshkent_shahri', districtId: 'chilonzor', lat: 41.28, lng: 69.2, addressText: 'Chilonzor 9' };
const PARCELS = [{ actualWeightG: 5000, lengthCm: 50, widthCm: 40, heightCm: 40, declaredValue: 150000 }];
const H48 = 48 * 3600 * 1000;

async function reset() {
  config.clearCache(); tariffCore.clearCache();
  await resetEmulator(db, seed({
    'module_config/logistics_all': CHAIN_CFG,
    'geo_districts/yunusobod': { regionId: 'toshkent_shahri' },
  }));
}
const ship = async (id) => (await db.collection('shipments').doc(id).get()).data();
const leg = async (id) => (await db.collection('demands').doc(id).get()).data();
const matchOf = async (legId, p) => (await db.collection('demand_matches').doc(`${legId}_${p}`).get()).data();
const settle = (p) => p.then((v) => ({ ok: true, v }), (e) => ({ ok: false, e }));
const accept = (legId, p, now) => retryOnEmulatorClosedTx(() => api.makeAcceptLeg(deps(db, now))({ legId }, ctx(p)));

async function fundedChain(n) {
  const r = await api.makeCreateLogisticsOrder(deps(db))(orderPayload({
    clientRequestId: `req-chain-tx-${String(n).padStart(4, '0')}`, destination: DEST, parcels: PARCELS,
  }), ctx(OWNER));
  const shipmentId = r.shipmentIds[0];
  await fund(db, shipmentId);
  return { shipmentId, legIds: (await ship(shipmentId)).legIds };
}

(async () => {
  await check('parallel oxirgi olishlar (K1→LEG-1 ‖ F1→LEG-3): qulf AYNAN BIR MARTA, kontaktlar to\'liq (5 raund)', async () => {
    await reset();
    for (let round = 0; round < 5; round += 1) {
      const { shipmentId, legIds } = await fundedChain(round);
      assert.strictEqual(legIds.length, 3);
      await accept(legIds[1], F1);
      const [a, b] = await Promise.all([settle(accept(legIds[0], K1)), settle(accept(legIds[2], F1))]);
      assert.ok(a.ok, `K1: ${a.e && a.e.message}`);
      assert.ok(b.ok, `F1: ${b.e && b.e.message}`);
      const locks = [a.v, b.v].filter((x) => x.chain.state === 'locked' && x.chain.claimed === 3);
      assert.ok(locks.length >= 1, 'oxirgi chaqiruv qulfni ko\'radi');
      const s = await ship(shipmentId);
      assert.strictEqual(s.chain.state, 'locked');
      assert.strictEqual(s.chain.claimed, 3);
      assert.ok(s.chain.lockedAt, 'lockedAt');
      // Faqat bitta chaqiruv qulfni QO'YDI: ikkinchisining natijasi claimed < 3.
      const claims = [a.v.chain.claimed, b.v.chain.claimed].sort();
      assert.deepStrictEqual(claims, [2, 3], `bitta g'olib qulflaydi: ${claims}`);
      const m0 = (await matchOf(legIds[0], K1)).contactUnlocked;
      assert.strictEqual(m0.ownerPhone, OWNER);
      assert.strictEqual(m0.nextProviderPhone, F1);
      assert.strictEqual((await matchOf(legIds[1], F1)).contactUnlocked.ownerPhone, K1);
      assert.strictEqual((await matchOf(legIds[2], F1)).contactUnlocked.ownerPhone, F1);
    }
  });

  await check('bitta oxirgi LEG uchun ikki kuryer (K1 ‖ F1 → LEG-1): aynan bitta g\'olib, qulf bitta', async () => {
    await reset();
    const { shipmentId, legIds } = await fundedChain(100);
    await accept(legIds[1], F1);
    await accept(legIds[2], F1);
    const [a, b] = await Promise.all([settle(accept(legIds[0], K1)), settle(accept(legIds[0], F1))]);
    assert.strictEqual([a, b].filter((x) => x.ok).length, 1, `g'oliblar: ${[a, b].map((x) => x.ok)}`);
    const winner = a.ok ? K1 : F1;
    const l = await leg(legIds[0]);
    assert.strictEqual(l.assignment.providerId, winner);
    const s = await ship(shipmentId);
    assert.strictEqual(s.chain.state, 'locked');
    assert.strictEqual(s.chain.claimed, 3);
  });

  await check('muddat sweeper\'i ‖ oxirgi olish: yoki locked (refund yo\'q), yoki expired (olish rad) — ikkalasi EMAS (3 raund)', async () => {
    await reset();
    for (let round = 0; round < 3; round += 1) {
      const { shipmentId, legIds } = await fundedChain(200 + round);
      await accept(legIds[1], F1);
      await accept(legIds[2], F1);
      // Olish muddat oxirida (hali o'tmagan), sweeper muddatdan keyin — poyga.
      const edge = new Date(NOW.getTime() + H48 - 1000);
      const late = new Date(NOW.getTime() + H48 + 1000);
      const [acc, sw] = await Promise.all([
        settle(accept(legIds[0], K1, edge)),
        settle(retryOnEmulatorClosedTx(() => api.expireChain(deps(db, late), shipmentId, late))),
      ]);
      assert.ok(sw.ok, `sweeper: ${sw.e && sw.e.message}`);
      const s = await ship(shipmentId);
      if (s.chain.state === 'locked') {
        assert.ok(acc.ok, 'qulflangan — olish yutgan');
        assert.strictEqual(s.paymentStatus, 'escrow_funded', 'qulflangan zanjir refund qilinmaydi');
        assert.strictEqual(s.status, 'ready');
      } else {
        assert.strictEqual(s.chain.state, 'expired');
        assert.strictEqual(s.paymentStatus, 'refund_pending');
        assert.strictEqual(s.status, 'cancelled');
        const l0 = await leg(legIds[0]);
        assert.strictEqual(l0.status, 'cancelled', 'olish yutqazgan — LEG bekor');
        assert.ok(!acc.ok, 'olish rad etilgan bo\'lishi kerak');
      }
    }
  });

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi`);
  process.exit(failed ? 1 : 0);
})();
