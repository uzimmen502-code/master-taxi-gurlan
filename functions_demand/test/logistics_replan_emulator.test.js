/**
 * Marshrutni qayta rejalash (`adminPlanShipmentRoute`) — HAQIQIY Firestore
 * tranzaksiyasi bilan (Emulator, Admin SDK).
 *
 *   npm --prefix functions_demand run test:replan-tx
 *
 * Qulflanadi (2026-10-10):
 *   - qayta rejalashda `assignedProviderIds` tozalanadi (eski reja ijrochisi
 *     jo'natmani o'qiy olmasin; `legAssignments` allaqachon tozalanardi)
 *   - POYGA: rejalash LEG'larni tekshirgandan KEYIN, yozishdan OLDIN kuryer
 *     LEG'ni olsa — rejalash rad etiladi, qabul o'chib ketmaydi
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-replan-tx';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const api = require('../api/logistics');
const config = require('../core/config');
const tariffCore = require('../core/tariff');
const {
  OWNER, K1, ADMIN, ctx, seed, orderPayload, deps, fund,
} = require('./helpers/logistics_harness');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};

async function reset() {
  const url = `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/`
    + `${process.env.GCLOUD_PROJECT}/databases/(default)/documents`;
  const res = await fetch(url, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator tozalanmadi: ${res.status}`);
  config.clearCache(); tariffCore.clearCache();
  await Promise.all(Object.entries(seed()).map(([p, d]) => db.doc(p).set(d)));
}

/** To'langan, 1 LEG'li jo'natma; LEG-1 active. */
async function fundedShipment() {
  const r = await api.makeCreateLogisticsOrder(deps(db))(orderPayload(), ctx(OWNER));
  const shipmentId = r.shipmentIds[0];
  await fund(db, shipmentId);
  return shipmentId;
}

const ship = async (id) => (await db.collection('shipments').doc(id).get()).data();
const leg = async (id) => (await db.collection('demands').doc(id).get()).data();
const NEW_ROUTE = [
  { to: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
  { from: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
];

/**
 * `db` o'rami: `logistics_orders` hujjati o'qilganda (rejalash LEG'larni
 * tekshirib bo'lgan, hali yozmagan payt) bir marta `hook`ni ishga tushiradi.
 */
function dbWithHook(hook) {
  let fired = false;
  return new Proxy(db, {
    get(target, prop) {
      if (prop !== 'collection') {
        const v = target[prop];
        return typeof v === 'function' ? v.bind(target) : v;
      }
      return (name) => {
        const col = target.collection(name);
        if (name !== 'logistics_orders') return col;
        return {
          doc: (id) => {
            const ref = col.doc(id);
            return {
              id: ref.id,
              get: async () => {
                if (!fired) { fired = true; await hook(); }
                return ref.get();
              },
            };
          },
        };
      };
    },
  });
}

(async () => {
  await check('qayta rejalash: assignedProviderIds tozalanadi (eski reja ijrochisi qolmaydi)', async () => {
    await reset();
    const shipmentId = await fundedShipment();
    // 8ddae48 dan oldingi bekor qilish izi: LEG bo'sh, ro'yxatda K1 qolgan.
    await db.collection('shipments').doc(shipmentId).update({ assignedProviderIds: [K1] });
    const p = await api.makeAdminPlanShipmentRoute(deps(db))({ shipmentId, reason: 'test', legs: NEW_ROUTE }, ctx(ADMIN));
    assert.strictEqual(p.version, 2);
    const s = await ship(shipmentId);
    assert.deepStrictEqual(s.assignedProviderIds, []);
    assert.deepStrictEqual(s.legAssignments, {});
  });

  await check('POYGA: tekshiruvdan keyin kuryer LEG\'ni olsa — rejalash RAD, qabul saqlanadi', async () => {
    await reset();
    const shipmentId = await fundedShipment();
    const [oldLeg] = (await ship(shipmentId)).legIds;
    let acceptErr = null;
    const hooked = dbWithHook(async () => {
      try { await api.makeAcceptLeg(deps(db))({ legId: oldLeg }, ctx(K1)); } catch (e) { acceptErr = e; }
    });
    const plan = api.makeAdminPlanShipmentRoute({ ...deps(db), db: hooked });
    const planOut = await plan({ shipmentId, reason: 'poyga', legs: NEW_ROUTE }, ctx(ADMIN)).then(
      (v) => ({ ok: true, v }), (e) => ({ ok: false, e }),
    );
    assert.strictEqual(acceptErr, null, `kuryer LEG'ni olishi kerak edi: ${acceptErr && acceptErr.message}`);
    assert.strictEqual(planOut.ok, false, 'rejalash qabul qilingan LEG ustidan o\'tib ketdi');
    assert.strictEqual(planOut.e.details && planOut.e.details.reason, 'leg_assigned', planOut.e.message);
    const l = await leg(oldLeg);
    assert.strictEqual(l.status, 'accepted');
    assert.strictEqual(l.assignment.providerId, K1);
    const s = await ship(shipmentId);
    assert.deepStrictEqual(s.legIds, [oldLeg], 'eski reja saqlanadi');
    assert.strictEqual(s.routePlanVersion, 1);
    assert.strictEqual(s.legAssignments[oldLeg], K1);
    assert.deepStrictEqual(s.assignedProviderIds, [K1]);
  });

  await check('qayta rejalash: tayinlangan LEG bor — RAD (oddiy holat, poygasiz)', async () => {
    await reset();
    const shipmentId = await fundedShipment();
    const [oldLeg] = (await ship(shipmentId)).legIds;
    await api.makeAcceptLeg(deps(db))({ legId: oldLeg }, ctx(K1));
    await assert.rejects(
      () => api.makeAdminPlanShipmentRoute(deps(db))({ shipmentId, legs: NEW_ROUTE }, ctx(ADMIN)),
      (e) => e.details && e.details.reason === 'leg_assigned',
    );
  });

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi.`);
  process.exit(failed ? 1 : 0);
})();
