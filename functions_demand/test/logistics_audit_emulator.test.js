/**
 * Kuryer/Relay auditi (2026-10-16) — poyga tuzatishlari, HAQIQIY Firestore
 * tranzaksiyasi bilan (Emulator, Admin SDK).
 *
 *   npm --prefix functions_demand run test:logaudit-tx
 *
 * Qulflanadi:
 *   L1  cancelLogisticsOrder ↔ eskrou tushishi: jo'natma `cancelled` bo'lib
 *       `escrow_funded` qolmasin (refund_pending bo'lsin)
 *   L1  cancelLogisticsOrder ↔ scanHandover: custody ham, bekor ham bo'lmasin
 *   L3b adminPlanShipmentRoute ↔ eskrou tushishi: yangi LEG-1 draft'da qolmasin
 *   L5  createLogisticsOrder: ikki parallel chaqiruv — BITTA ORDER
 *   L12 adminUpsertLogisticsTariff ↔ adminActivateLogisticsTariff: faol tarif draft'ga qaytmasin
 *
 * POYGA USULI (`raceDb`). Emulator ham ishlab chiqarishdagi kabi PESSIMISTIK
 * qulflaydi: tranzaksiya o'qigan hujjatga tashqaridan yozuv — tranzaksiya
 * tugamaguncha kutadi (kutib turgan yozuvni AWAIT qilsak — qulf timeout).
 * Shuning uchun raqib ikki xil joyda ishga tushadi:
 *   - TRANZAKSIYASIZ o'qishdan keyin (eski kod): raqib to'liq tugaydi (await) —
 *     eski kodning eskirgan snapshot'i bilan yozishi aniq ko'rinadi;
 *   - TRANZAKSIYA ichida, birinchi `tx.get`dan keyin (yangi kod): raqib AWAIT
 *     QILINMAYDI, parallel ketadi — qulf ularni ketma-ketlashtiradi; qaysi
 *     biri birinchi bo'lishidan qat'i nazar NATIJA izchil bo'lishi shart.
 * Raqiblar HAQIQIY kod yo'li: eskrou — `relay_escrow.js fund` kabi tranzaksiya
 * (faqat awaiting_payment + pending'dan); scan/activate — jamoat callable'lari.
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-logaudit-tx';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const api = require('../api/logistics');
const config = require('../core/config');
const tariffCore = require('../core/tariff');
const {
  OWNER, K1, ADMIN, ctx, seed, orderPayload, deps, fund, PHOTO, fixture,
} = require('./helpers/logistics_harness');
const { resetEmulator, dbWithHook } = require('./helpers/emulator_hooks');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};

async function reset(extra) {
  config.clearCache(); tariffCore.clearCache();
  await resetEmulator(db, seed(extra));
}

const ship = async (id) => (await db.collection('shipments').doc(id).get()).data();
const leg = async (id) => (await db.collection('demands').doc(id).get()).data();
const col = async (name) => (await db.collection(name).get()).docs;

/**
 * Raqib `hook` BIR MARTA (yuqoridagi izohga qarang). `queryOn`/`docOn` —
 * tranzaksiyasiz o'qishdan keyin (await); `db.runTransaction` — birinchi
 * `tx.get`dan keyin (await QILINMAYDI). `settle()` — raqib tugashini kutadi.
 */
function raceDb({ queryOn, docOn }, hook) {
  let fired = false;
  let pending = null;
  const awaited = async () => { if (!fired) { fired = true; await hook(); } };
  const parallel = () => { if (!fired) { fired = true; pending = Promise.resolve().then(hook).catch((e) => e); } };
  const wrapQ = (q) => new Proxy(q, {
    get(t, p) {
      if (p === 'get') return async (...a) => { const s = await t.get(...a); await awaited(); return s; };
      if (['where', 'limit', 'orderBy'].includes(p)) return (...a) => wrapQ(t[p](...a));
      const v = t[p];
      return typeof v === 'function' ? v.bind(t) : v;
    },
  });
  const proxy = new Proxy(db, {
    get(target, prop) {
      if (prop === 'runTransaction') {
        return (fn, opts) => target.runTransaction(async (tx) => {
          const wrapped = new Proxy(tx, {
            get(t, p) {
              if (p === 'get') return async (...a) => { const r = await t.get(...a); parallel(); return r; };
              const v = t[p];
              return typeof v === 'function' ? v.bind(t) : v;
            },
          });
          return fn(wrapped);
        }, opts);
      }
      if (prop !== 'collection') {
        const v = target[prop];
        return typeof v === 'function' ? v.bind(target) : v;
      }
      return (name) => {
        const c = target.collection(name);
        if (name !== queryOn && name !== docOn) return c;
        return new Proxy(c, {
          get(ct, p) {
            if (name === queryOn && (p === 'where' || p === 'limit')) return (...a) => wrapQ(ct[p](...a));
            if (name === docOn && p === 'doc') {
              return (...a) => new Proxy(ct.doc(...a), {
                get(r, rp) {
                  if (rp === 'get') return async () => { const s = await r.get(); await awaited(); return s; };
                  const v = r[rp];
                  return typeof v === 'function' ? v.bind(r) : v;
                },
              });
            }
            const v = ct[p];
            return typeof v === 'function' ? v.bind(ct) : v;
          },
        });
      };
    },
  });
  return { db: proxy, settle: async () => (pending ? pending : null), fired: () => fired };
}

/** `relay_escrow.js` fund bilan bir xil qoida: faqat awaiting_payment + pending'dan. */
async function escrowFundTx(shipmentId) {
  const ref = db.collection('shipments').doc(shipmentId);
  return db.runTransaction(async (tx) => {
    const d = (await tx.get(ref)).data() || {};
    if (d.status !== 'awaiting_payment' || d.paymentStatus !== 'pending') return { funded: false };
    tx.update(ref, { paymentStatus: 'escrow_funded', status: 'ready', fundedAt: new Date() });
    return { funded: true };
  });
}

async function newOrder() {
  const r = await api.makeCreateLogisticsOrder(deps(db))(orderPayload(), ctx(OWNER));
  return { orderId: r.orderId, shipmentId: r.shipmentIds[0] };
}

(async () => {
  await check('L1: bekor qilish ↔ eskrou tushishi — cancelled + escrow_funded QOLMAYDI', async () => {
    await reset();
    const { orderId, shipmentId } = await newOrder();
    const race = raceDb({ queryOn: 'shipments' }, () => escrowFundTx(shipmentId));
    await api.makeCancelLogisticsOrder({ ...deps(db), db: race.db })({ orderId }, ctx(OWNER));
    const rival = await race.settle();
    assert.ok(!(rival instanceof Error), `raqib xatosi: ${rival && rival.message}`);
    const s = await ship(shipmentId);
    assert.strictEqual(s.status, 'cancelled');
    // Izchillik: pul tushgan bo'lsa — refund_pending; tushmagan bo'lsa — pending. `escrow_funded` QOLMASIN.
    assert.notStrictEqual(s.paymentStatus, 'escrow_funded', 'cancelled + escrow_funded: pul qaytmaydi');
  });

  await check('L1: bekor qilish ↔ eskrou — raqib BIRINCHI bo\'lsa refund_pending (deterministik)', async () => {
    await reset();
    const { orderId, shipmentId } = await newOrder();
    await escrowFundTx(shipmentId);
    const out = await api.makeCancelLogisticsOrder(deps(db))({ orderId }, ctx(OWNER));
    assert.strictEqual(out.refundPending, 1);
    const s = await ship(shipmentId);
    assert.strictEqual(s.status, 'cancelled');
    assert.strictEqual(s.paymentStatus, 'refund_pending');
  });

  await check('L1: bekor qilish ↔ scanHandover — custody ham, bekor ham BO\'LMAYDI', async () => {
    await reset();
    const { orderId, shipmentId } = await newOrder();
    const [legId] = (await ship(shipmentId)).legIds;
    await fund(db, shipmentId);
    await api.makeAcceptLeg(deps(db))({ legId }, ctx(K1));
    const sec = await api.makeGetShipmentSecrets(deps(db))({ shipmentId }, ctx(OWNER));
    const race = raceDb({ queryOn: 'shipments' }, () => api.makeScanHandover(deps(db))(
      { legId, code: sec.handoverCode, photoUrls: PHOTO }, ctx(K1),
    ));
    const out = await api.makeCancelLogisticsOrder({ ...deps(db), db: race.db })({ orderId }, ctx(OWNER))
      .then(() => ({ ok: true }), (e) => ({ ok: false, e }));
    const scan = await race.settle();
    const events = await col('custody_events');
    const s = await ship(shipmentId);
    if (events.length > 0) {
      // Custody boshlandi: jo'natma YO'LDA, bekor RAD.
      assert.ok(!(scan instanceof Error), `scan o'tishi kerak edi: ${scan && scan.message}`);
      assert.strictEqual(s.status, 'in_transit', `custody bor, lekin status=${s.status}`);
      assert.strictEqual(out.ok, false, 'custody boshlangach bekor qilish RAD etilishi kerak');
      assert.strictEqual(out.e.details && out.e.details.reason, 'in_transit');
      assert.strictEqual((await leg(legId)).status, 'in_progress');
      assert.strictEqual(s.paymentStatus, 'escrow_funded');
    } else {
      // Bekor birinchi bo'ldi: custody YO'Q, scan rad etilgan.
      assert.strictEqual(out.ok, true);
      assert.ok(scan instanceof Error, 'bekor qilingan LEG\'da scan RAD etilishi kerak');
      assert.strictEqual(s.status, 'cancelled');
      assert.strictEqual(s.paymentStatus, 'refund_pending');
    }
  });

  await check('L3b: qayta rejalash ↔ eskrou tushishi — yangi LEG-1 draft\'da QOLMAYDI', async () => {
    await reset();
    const { shipmentId } = await newOrder();
    // Rejalash jo'natmani o'qigach (to'lanmagan), tranzaksiyadan OLDIN eskrou tushadi.
    const hooked = dbWithHook(db, 'logistics_orders', () => escrowFundTx(shipmentId));
    const NEW_ROUTE = [
      { to: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
      { from: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
    ];
    const p = await api.makeAdminPlanShipmentRoute({ ...deps(db), db: hooked })(
      { shipmentId, reason: 'poyga', legs: NEW_ROUTE }, ctx(ADMIN),
    );
    const s = await ship(shipmentId);
    assert.strictEqual(s.paymentStatus, 'escrow_funded');
    assert.deepStrictEqual(s.legIds, p.legIds);
    assert.strictEqual((await leg(p.legIds[0])).status, 'active', 'yangi LEG-1 ochilishi kerak edi');
    assert.strictEqual((await leg(p.legIds[1])).status, 'draft', 'LEG-2 oldingisi olinmaguncha draft');
  });

  await check('L5: ikki parallel createLogisticsOrder — BITTA ORDER, ikkinchisi duplicate', async () => {
    await reset();
    const create = api.makeCreateLogisticsOrder(deps(db));
    const [a, b] = await Promise.all([
      create(orderPayload(), ctx(OWNER)),
      create(orderPayload(), ctx(OWNER)),
    ]);
    assert.strictEqual(a.orderId, b.orderId, 'ikkala chaqiruv bir xil orderId qaytarishi kerak');
    assert.strictEqual([a, b].filter((r) => r.duplicate).length, 1);
    assert.strictEqual((await col('logistics_orders')).length, 1);
    assert.strictEqual((await col('shipments')).length, 1);
    assert.strictEqual((await col('demand_idempotency')).length, 1);
    assert.deepStrictEqual(a.shipmentIds, b.shipmentIds);
  });

  await check('L12: tarif upsert ↔ faollashtirish — faol tarif draft\'ga QAYTMAYDI', async () => {
    await reset({ 'module_tariffs/logistics': { activeVersion: 0 }, 'module_tariffs/logistics_v7': { ...fixture.tariff, status: 'draft' } });
    const tariff = { ...fixture.tariff };
    delete tariff.status;
    const race = raceDb({ docOn: 'module_tariffs' }, () => api.makeAdminActivateLogisticsTariff(deps(db))({ version: 7 }, ctx(ADMIN)));
    await api.makeAdminUpsertLogisticsTariff({ ...deps(db), db: race.db })({ tariff }, ctx(ADMIN))
      .then(() => ({ ok: true }), (e) => ({ ok: false, e }));
    const act = await race.settle();
    assert.ok(!(act instanceof Error), `faollashtirish xatosi: ${act && act.message}`);
    const t = (await db.collection('module_tariffs').doc('logistics_v7').get()).data();
    const ptr = (await db.collection('module_tariffs').doc('logistics').get()).data();
    assert.strictEqual(ptr.activeVersion, 7, 'tarif faollashgan bo\'lishi kerak edi');
    assert.strictEqual(t.status, 'active', `ko'rsatkich faol, lekin hujjat status=${t.status}`);
  });

  await check('S4/L7: parallel noto\'g\'ri taxminlar HAMMASI sanaladi (hisob tranzaksiyada, read-then-write poygasi yo\'q)', async () => {
    await reset();
    const { shipmentId } = await newOrder();
    const [legId] = (await ship(shipmentId)).legIds;
    await fund(db, shipmentId);
    await api.makeAcceptLeg(deps(db))({ legId }, ctx(K1));
    const scan = api.makeScanHandover(deps(db));
    const N = 4; // standart chegara 5 dan past: hammasi `bad_proof`, qulfsiz
    const out = await Promise.all(Array.from({ length: N }, () => scan(
      { legId, code: '000000', photoUrls: PHOTO }, ctx(K1),
    ).then(() => ({ ok: true }), (e) => ({ ok: false, e }))));
    const reasons = out.map((r) => (r.ok ? 'OK' : (r.e.details && r.e.details.reason) || r.e.message));
    assert.deepStrictEqual(reasons, Array(N).fill('bad_proof'), `javoblar: ${reasons}`);
    const att = (await db.doc(`shipments/${shipmentId}/private/codeAttempts_handover_${legId}_${K1}`).get()).data();
    assert.strictEqual(att.fails, N, `${N} parallel xato sanalishi kerak edi, hisob=${att.fails}`);
    assert.strictEqual((await col('custody_events')).length, 0);
    // Beshinchi taxmin qulflaydi, oltinchi (to'g'ri kod bilan ham) o'tmaydi.
    await assert.rejects(() => scan({ legId, code: '000000', photoUrls: PHOTO }, ctx(K1)),
      (e) => e.details && e.details.reason === 'CODE_ATTEMPTS_LOCKED');
    const sec = await api.makeGetShipmentSecrets(deps(db))({ shipmentId }, ctx(OWNER));
    await assert.rejects(() => scan({ legId, code: sec.handoverCode, photoUrls: PHOTO }, ctx(K1)),
      (e) => e.details && e.details.reason === 'CODE_ATTEMPTS_LOCKED');
    assert.strictEqual((await col('custody_events')).length, 0);
  });

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi.`);
  process.exit(failed ? 1 : 0);
})();
