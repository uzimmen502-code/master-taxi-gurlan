/**
 * Ulgurji «Етказилмади» — poyga/tranzaksiya, HAQIQIY Firestore (Emulator, Admin SDK):
 *
 *   npm --prefix functions_demand run test:wfailed-tx
 *
 * Qulflanadi (birinchi qaror yutadi — 22-band):
 *   - to'liq oqim haqiqiy tranzaksiyada: xabar → tasdiq → refused (hujjat shakli)
 *   - ikki parallel kuryer xabari — BITTA so'rov (seq 1), bitta tarix yozuvi
 *   - ikki parallel xaridor tasdig'i — BITTA rad, hisoblagich AYNAN +1, bitta rad tarixi
 *   - xaridor tasdig'i ↔ sotuvchi «Етказилсин» (muddat o'tgan) parallel — faqat BITTASI; ikkinchisi df_not_pending
 *   - xaridor «Олмоқчиман» ↔ admin «Етказилмади» parallel — faqat bittasi
 *   - ikki parallel sweeper — BITTA eskalatsiya
 *   - muddat o'tmagan sweeper — real oraliq so'rovi null/kelajak muddatni olmaydi
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18282';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-wfailed-tx';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const C = require('../api/wholesale_card');
const F = require('../api/wholesale_failed');
const { resetEmulator } = require('./helpers/emulator_hooks');
const {
  BUYER, SELLER, ADMIN, ORDER_ID, K1, NOW, ctx, seedW, flow, quiet: q,
} = require('./helpers/wholesale_flow');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};

const MIN = 60 * 1000;
const at = (ms) => () => new Date(NOW.getTime() + ms);
const ref = () => db.collection('wholesale_orders').doc(ORDER_ID);
const order = async () => (await ref().get()).data();
const history = async () => (await ref().collection('history').get()).docs.map((d) => d.data());
const settle = (ps) => Promise.allSettled(ps.map((p) => q(() => p)));
const reasons = (rs) => rs.filter((r) => r.status === 'rejected').map((r) => (r.reason.details || {}).reason || r.reason.message);

const report = (data = { reasonCode: 'customer_refused' }) => C.makeMarkWholesaleBuyerRefused({ db, now: at(0) })({ orderId: ORDER_ID, ...data }, ctx(K1));
const respond = (decision, now = at(0)) => F.makeRespondWholesaleDeliveryFailed({ db, now })({ orderId: ORDER_ID, decision }, ctx(BUYER));
const resolve = (decision, who, now) => F.makeResolveWholesaleDeliveryFailed({ db, now })({ orderId: ORDER_ID, decision }, ctx(who));

async function fresh() {
  await resetEmulator(db, seedW());
  return q(() => flow(db));
}

(async () => {
  await check('to\'liq oqim haqiqiy tranzaksiyada: so\'rov (holat o\'zgarmaydi) → xaridor tasdig\'i → refused (+returnStatus, refusal, hisoblagich, tarix)', async () => {
    const { legId } = await fresh();
    const r = await q(() => report({ reasonCode: 'customer_absent', reason: 'eshik yopiq' }));
    assert.deepStrictEqual([r.status, r.awaitingBuyer], ['in_delivery', true]);
    let o = await order();
    assert.deepStrictEqual([o.status, o.deliveryFailed.seq, o.deliveryFailedOpen], ['in_delivery', 1, true]);
    assert.strictEqual(o.deliveryFailedDueAt.toMillis(), NOW.getTime() + 15 * MIN);
    const c = await q(() => respond('confirm'));
    assert.strictEqual(c.status, 'refused');
    o = await order();
    assert.deepStrictEqual([o.status, o.refundStatus, o.returnStatus, o.refusal.by, o.refusal.legId, o.refusal.confirmedBy, o.deliveryFailedOpen, o.deliveryFailedDueAt],
      ['refused', 'pending', 'pending_shipment', K1, legId, 'buyer', false, null]);
    assert.strictEqual((await db.collection('wholesale_buyer_stats').doc(BUYER).get()).data().cardRefusals, 1);
    const h = (await history()).filter((x) => x.seq >= 4).sort((a, b) => a.seq - b.seq).map((x) => `${x.seq}:${x.event || x.to}`);
    assert.deepStrictEqual(h, ['4:delivery_failed_requested', '5:refused']);
  });

  await check('ikki parallel kuryer xabari — BITTA so\'rov (seq 1), bitta so\'rov tarixi', async () => {
    await fresh();
    const rs = await settle([report(), report()]);
    assert.ok(rs.every((x) => x.status === 'fulfilled'), JSON.stringify(reasons(rs)));
    assert.deepStrictEqual(rs.map((x) => x.value.idempotent).sort(), [false, true]);
    const o = await order();
    assert.strictEqual(o.deliveryFailed.seq, 1);
    assert.strictEqual((await history()).filter((x) => x.event === 'delivery_failed_requested').length, 1);
  });

  await check('ikki parallel xaridor tasdig\'i — BITTA rad, hisoblagich AYNAN +1, bitta rad tarixi', async () => {
    await fresh();
    await q(() => report());
    const rs = await settle([respond('confirm'), respond('confirm')]);
    assert.ok(rs.every((x) => x.status === 'fulfilled'), JSON.stringify(reasons(rs)));
    assert.deepStrictEqual(rs.map((x) => x.value.idempotent).sort(), [false, true]);
    assert.strictEqual((await order()).status, 'refused');
    assert.strictEqual((await db.collection('wholesale_buyer_stats').doc(BUYER).get()).data().cardRefusals, 1);
    assert.strictEqual((await history()).filter((x) => x.to === 'refused').length, 1);
  });

  await check('xaridor tasdig\'i ↔ sotuvchi «Етказилсин» (muddat o\'tgan) parallel — faqat BITTASI, ikkinchisi df_not_pending; audit faqat g\'olib sotuvchi bo\'lsa', async () => {
    await fresh();
    await q(() => report());
    const rs = await settle([respond('confirm', at(16 * MIN)), resolve('deliver', SELLER, at(16 * MIN))]);
    const won = rs.filter((x) => x.status === 'fulfilled');
    assert.strictEqual(won.length, 1, JSON.stringify(reasons(rs)));
    assert.deepStrictEqual(reasons(rs), ['df_not_pending']);
    const o = await order();
    const audit = (await db.collection('admin_audit').where('kind', '==', 'wholesale_delivery_failed_decision').get()).size;
    if (o.status === 'refused') {
      assert.deepStrictEqual([o.deliveryFailed.resolution.by, audit], ['buyer', 0]);
      assert.strictEqual((await db.collection('wholesale_buyer_stats').doc(BUYER).get()).data().cardRefusals, 1);
    } else {
      assert.deepStrictEqual([o.status, o.deliveryFailed.resolution.by, o.deliveryFailed.resolution.decision, audit], ['in_delivery', 'seller', 'continue', 1]);
      assert.strictEqual((await db.collection('wholesale_buyer_stats').doc(BUYER).get()).exists, false);
    }
  });

  await check('xaridor «Олмоқчиман» ↔ admin «Етказилмади» parallel — faqat bittasi; holat izchil', async () => {
    await fresh();
    await q(() => report());
    const rs = await settle([respond('reject', at(20 * MIN)), resolve('failed', ADMIN, at(20 * MIN))]);
    assert.strictEqual(rs.filter((x) => x.status === 'fulfilled').length, 1, JSON.stringify(reasons(rs)));
    const o = await order();
    const res = o.deliveryFailed.resolution;
    if (res.by === 'buyer') assert.deepStrictEqual([o.status, res.decision], ['in_delivery', 'continue']);
    else assert.deepStrictEqual([o.status, res.by, res.decision], ['refused', 'admin', 'failed']);
    assert.strictEqual(o.deliveryFailedOpen, false);
  });

  await check('ikki parallel sweeper (muddat o\'tgan) — BITTA eskalatsiya tarixi; muddat o\'tmagan — so\'rov olmaydi', async () => {
    await fresh();
    await q(() => report());
    const young = await q(() => F.runWholesaleDeliveryFailedSweep({ db, now: at(15 * MIN - 1) }));
    assert.strictEqual(young.scanned, 0, 'real oraliq so\'rovi: kelajak muddat olinmaydi');
    const rs = await settle([
      F.runWholesaleDeliveryFailedSweep({ db, now: at(15 * MIN) }),
      F.runWholesaleDeliveryFailedSweep({ db, now: at(15 * MIN) }),
    ]);
    assert.ok(rs.every((x) => x.status === 'fulfilled'));
    assert.strictEqual(rs.reduce((n, x) => n + x.value.escalated, 0), 1);
    assert.strictEqual((await history()).filter((x) => x.event === 'delivery_failed_escalated').length, 1);
    const o = await order();
    assert.deepStrictEqual([o.deliveryFailed.stage, o.deliveryFailedDueAt], ['awaiting_decision', null]);
    const again = await q(() => F.runWholesaleDeliveryFailedSweep({ db, now: at(30 * MIN) }));
    assert.strictEqual(again.scanned, 0, 'null muddat — real so\'rovda yo\'q');
  });

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi`);
  process.exit(failed ? 1 : 0);
})();
