/**
 * Kuryer vazifa haqi FOIZI (gilam / agro / yig'ib olish) - D5, ega qarori 2026-10-16.
 * HAQIQIY `functions/index.js` callable'lari `.run()` orqali, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-courier-payout \
 *     "node functions/test/courier_task_payout_cf.test.js"
 *
 * Qulflanadi:
 *   - admin sozlamasi: faqat admin/superadmin; modul/bps tekshiruvi; versiya + tarix + audit;
 *     bir xil qiymat qayta -> yangi versiya yo'q; null = "sozlanmagan"
 *   - yakunda `courierPayout` (butun, floor), `courierPayoutBps`, `courierPayoutVersion`,
 *     `courierPayoutBase`, `courierPayoutCourierId` vazifa hujjatiga yoziladi
 *   - foiz sozlanmagan -> courierPayout null (not_configured); narx noma'lum -> null (price_unknown)
 *   - agro: narx yakunda (admin 'completed') ma'lum bo'lsa o'sha qadamda hisoblanadi
 *   - mijoz narxi (finalPrice/finalValue) O'ZGARMAYDI; ledger/hamyonga YOZUV YO'Q
 *   - callable javoblari AVVALGI shaklda (eski ilova buzilmaydi)
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-courier-payout';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require('../index');
const admin = require('firebase-admin');
const ledger = require('../settlement_ledger');

const db = admin.firestore();

const ADMIN = '998909990000';
const STRANGER = '998904440004';
const A = '998901110001'; // tasdiqlangan kuryer
const CUSTOMER = '998905550005';
const ACC_A = 'accCOURIER0000000000A';

const ctxOf = (phone) => ({ auth: { uid: `uid_${phone}`, token: { phone_number: `+${phone}` } } });
const call = (name, data, phone) => fns[name].run(data, ctxOf(phone));
const at = (ms) => admin.firestore.Timestamp.fromMillis(ms);

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function expectCode(promise, code, httpsCode) {
  await assert.rejects(promise, (e) => {
    const got = (e.details && e.details.code) || e.message;
    assert.strictEqual(got, code, `kod ${got} (${e.code}): ${e.message}`);
    if (httpsCode) assert.strictEqual(e.code, httpsCode);
    return true;
  });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
async function reset() {
  await clearEmulator();
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(STRANGER).set({ role: 'user' });
  await db.collection('users').doc(CUSTOMER).set({ role: 'user', bonusBalance: 0, name: 'Mijoz' });
  await db.collection('users').doc(A).set({ role: 'user', accountId: ACC_A, bonusBalance: 0 });
  await db.collection('provider_capabilities').doc(ACC_A).set({
    identity: { accountId: ACC_A, primaryUid: A }, courier: { active: true }, status: { courier: 'approved' },
  });
  await db.collection('procurement_products').doc('milk').set({
    code: 'milk', label: 'Sut', unit: 'l', price: 5000, active: true, updatedAt: admin.firestore.Timestamp.now(),
  });
}
const get = async (path) => (await db.doc(path).get()).data();
const set = (module, bps, who = ADMIN, extra = {}) => call('adminSetCourierTaskPayoutPct', { module, bps, reason: 'sinov', ...extra }, who);
const carpet = (id, over = {}) => db.collection('carpet_wash_orders').doc(id).set({
  customerId: CUSTOMER, customerPhone: CUSTOMER, carpetCount: 3, priceMode: 'admin', finalPrice: 40000,
  status: 'return_in_delivery', pickupCourierId: A, returnCourierId: A, returnArrivedAt: at(5000), createdAt: at(1000), ...over,
});
const agro = (id, over = {}) => db.collection('agro_pickup_orders').doc(id).set({
  customerId: CUSTOMER, customerPhone: CUSTOMER, productType: 'milk', literCount: 20, priceMode: 'admin', finalPrice: 0,
  status: 'pickup_in_delivery', pickupCourierId: A, arrivedAt: at(5000), createdAt: at(1000), ...over,
});
const PAYOUT_KEYS = ['courierPayout', 'courierPayoutBps', 'courierPayoutVersion', 'courierPayoutBase', 'courierPayoutCourierId', 'courierPayoutReason'];
const payoutOf = (d) => Object.fromEntries(PAYOUT_KEYS.map((k) => [k, d[k]]));
const journalSize = async () => (await db.collection(ledger.COL_JOURNAL).get()).size;

async function main() {
  await reset();

  // ── 1. Admin sozlamasi ───────────────────────────────────────────────
  await check('P1 sozlama yo\'q: get -> versiya 0, hamma modul null (standart foiz YO\'Q)', async () => {
    const r = await call('adminGetCourierTaskPayoutSettings', {}, ADMIN);
    assert.deepStrictEqual({ v: r.version, m: r.modules }, { v: 0, m: { carpet: null, agro: null, collection: null } });
    await expectCode(call('adminGetCourierTaskPayoutSettings', {}, STRANGER), 'Admin role required', 'permission-denied');
  });
  await check('P2 set: begona rad; modul/bps tekshiruvi; saqlash -> v1, tarix, audit; takror -> yangi versiya YO\'Q', async () => {
    await expectCode(set('carpet', 1500, STRANGER), 'Admin role required', 'permission-denied');
    await expectCode(set('bread', 1500), 'MODULE_INVALID', 'invalid-argument');
    for (const bad of [-1, 10001, 12.5, '1500', true, undefined]) {
      await expectCode(set('carpet', bad), 'COURIER_PAYOUT_BPS_INVALID', 'invalid-argument');
    }
    assert.strictEqual((await db.doc('settings/courier_task_payout').get()).exists, false, 'rad etilganlar hech narsa yozmadi');
    const r = await set('carpet', 1500);
    assert.deepStrictEqual({ v: r.version, u: r.unchanged }, { v: 1, u: false });
    const doc = await get('settings/courier_task_payout');
    assert.deepStrictEqual({ v: doc.version, m: doc.modules, by: doc.updatedBy }, { v: 1, m: { carpet: { bps: 1500 } }, by: ADMIN });
    const h = await get('courier_task_payout_history/v1');
    assert.deepStrictEqual({ pv: h.previous.version, pb: h.previous.bps, by: h.changedBy, m: h.changedModule }, { pv: 0, pb: null, by: ADMIN, m: 'carpet' });
    const audit = await db.collection('admin_audit').where('kind', '==', 'courier_task_payout_pct').get();
    assert.strictEqual(audit.size, 1);
    assert.deepStrictEqual(audit.docs[0].data().detail, { module: 'carpet', bps: 1500, prevBps: null });
    const again = await set('carpet', 1500);
    assert.deepStrictEqual({ v: again.version, u: again.unchanged }, { v: 1, u: true });
    assert.strictEqual((await db.doc('courier_task_payout_history/v2').get()).exists, false);
    await set('agro', 1000);
    await set('collection', 500);
    const g = await call('adminGetCourierTaskPayoutSettings', {}, ADMIN);
    assert.deepStrictEqual({ v: g.version, m: g.modules }, { v: 3, m: { carpet: { bps: 1500 }, agro: { bps: 1000 }, collection: { bps: 500 } } });
    assert.strictEqual((await get('courier_task_payout_history/v3')).previous.version, 2);
  });

  // ── 2. Gilam ─────────────────────────────────────────────────────────
  await check('C1 gilam yakuni: 40 000 x 15 % = 6 000; maydonlar yozildi; javob avvalgi shaklda; mijoz narxi o\'zgarmadi; ledger yozuvi yo\'q', async () => {
    await carpet('c1');
    const j0 = await journalSize();
    const r = await call('courierMarkCarpetDelivered', { courierPhone: A, orderId: 'c1' }, A);
    assert.deepStrictEqual(r, { ok: true, orderId: 'c1', status: 'completed' });
    const d = await get('carpet_wash_orders/c1');
    assert.strictEqual(d.status, 'completed');
    assert.deepStrictEqual(payoutOf(d), {
      courierPayout: 6000, courierPayoutBps: 1500, courierPayoutVersion: 3, courierPayoutBase: 40000,
      courierPayoutCourierId: A, courierPayoutReason: null,
    });
    assert.ok(d.courierPayoutAt, 'courierPayoutAt');
    assert.strictEqual(d.finalPrice, 40000, 'mijoz narxi tegilmadi');
    assert.strictEqual(await journalSize(), j0, 'ledger yozuvi YO\'Q');
    assert.strictEqual((await get(`users/${A}`)).bonusBalance, 0, 'kuryer hamyoni o\'zgarmadi');
  });
  await check('C2 takror yakun rad (status completed) - haq qayta hisoblanmaydi', async () => {
    await assert.rejects(call('courierMarkCarpetDelivered', { courierPhone: A, orderId: 'c1' }, A), (e) => e.code === 'failed-precondition');
    assert.strictEqual((await get('carpet_wash_orders/c1')).courierPayout, 6000);
  });
  await check('C3 floor: 33 333 x 15 % = 4 999', async () => {
    await carpet('c3', { finalPrice: 33333 });
    await call('courierMarkCarpetDelivered', { courierPhone: A, orderId: 'c3' }, A);
    assert.strictEqual((await get('carpet_wash_orders/c3')).courierPayout, 4999);
  });
  await check('C4 narx noma\'lum (finalPrice 0): yakun o\'tadi, courierPayout null, sabab price_unknown, foiz saqlanadi', async () => {
    await carpet('c4', { finalPrice: 0 });
    const r = await call('courierMarkCarpetDelivered', { courierPhone: A, orderId: 'c4' }, A);
    assert.strictEqual(r.status, 'completed');
    const d = await get('carpet_wash_orders/c4');
    assert.deepStrictEqual(payoutOf(d), {
      courierPayout: null, courierPayoutBps: 1500, courierPayoutVersion: 3, courierPayoutBase: null,
      courierPayoutCourierId: A, courierPayoutReason: 'price_unknown',
    });
  });
  await check('C5 foiz sozlanmagan (null): yakun o\'tadi, courierPayout null, sabab not_configured, versiya = hujjat versiyasi', async () => {
    const r = await set('carpet', null);
    assert.strictEqual(r.version, 4);
    assert.strictEqual((await call('adminGetCourierTaskPayoutSettings', {}, ADMIN)).modules.carpet, null);
    await carpet('c5');
    await call('courierMarkCarpetDelivered', { courierPhone: A, orderId: 'c5' }, A);
    assert.deepStrictEqual(payoutOf(await get('carpet_wash_orders/c5')), {
      courierPayout: null, courierPayoutBps: null, courierPayoutVersion: 4, courierPayoutBase: 40000,
      courierPayoutCourierId: A, courierPayoutReason: 'not_configured',
    });
    await set('carpet', 2000); // v5 - keyingi testlar uchun
    await carpet('c6');
    await call('courierMarkCarpetDelivered', { courierPhone: A, orderId: 'c6' }, A);
    assert.deepStrictEqual(payoutOf(await get('carpet_wash_orders/c6')), {
      courierPayout: 8000, courierPayoutBps: 2000, courierPayoutVersion: 5, courierPayoutBase: 40000,
      courierPayoutCourierId: A, courierPayoutReason: null,
    });
    assert.strictEqual((await get('carpet_wash_orders/c1')).courierPayoutVersion, 3, 'eski vazifa o\'z versiyasida qoladi');
  });

  // ── 3. Agro ──────────────────────────────────────────────────────────
  await check('G1 agro: narx olib ketishda ma\'lum (30 000 x 10 % = 3 000) - o\'sha qadamda hisoblanadi', async () => {
    await agro('g1', { finalPrice: 30000 });
    const r = await call('courierMarkAgroPickedUp', { courierPhone: A, orderId: 'g1' }, A);
    assert.deepStrictEqual(r, { ok: true, orderId: 'g1', status: 'picked_up' });
    assert.deepStrictEqual(payoutOf(await get('agro_pickup_orders/g1')), {
      courierPayout: 3000, courierPayoutBps: 1000, courierPayoutVersion: 5, courierPayoutBase: 30000,
      courierPayoutCourierId: A, courierPayoutReason: null,
    });
  });
  await check('G2 agro: narx noma\'lum -> price_unknown; admin yakunda narx qo\'yadi (20 000) -> o\'sha qadamda 2 000', async () => {
    await agro('g2');
    await call('courierMarkAgroPickedUp', { courierPhone: A, orderId: 'g2' }, A);
    let d = await get('agro_pickup_orders/g2');
    assert.strictEqual(d.courierPayout, null);
    assert.strictEqual(d.courierPayoutReason, 'price_unknown');
    const r = await call('adminSetAgroPickupStatus', { adminPhone: ADMIN, orderId: 'g2', status: 'completed', finalPrice: 20000 }, ADMIN);
    assert.deepStrictEqual(r, { ok: true, orderId: 'g2', status: 'completed' });
    d = await get('agro_pickup_orders/g2');
    assert.strictEqual(d.finalPrice, 20000);
    assert.deepStrictEqual(payoutOf(d), {
      courierPayout: 2000, courierPayoutBps: 1000, courierPayoutVersion: 5, courierPayoutBase: 20000,
      courierPayoutCourierId: A, courierPayoutReason: null,
    });
  });
  await check('G3 agro: olib ketishda hisoblangan, admin yakunda narxni O\'ZGARTIRSA - baza o\'zgarganda qayta hisoblanadi (3 000 -> 4 000); o\'zgarmasa tegilmaydi', async () => {
    await agro('g3', { finalPrice: 30000 });
    await call('courierMarkAgroPickedUp', { courierPhone: A, orderId: 'g3' }, A);
    await call('adminSetAgroPickupStatus', { adminPhone: ADMIN, orderId: 'g3', status: 'completed', finalPrice: 40000 }, ADMIN);
    let d = await get('agro_pickup_orders/g3');
    assert.deepStrictEqual([d.courierPayout, d.courierPayoutBase], [4000, 40000]);
    await agro('g3b', { finalPrice: 30000 });
    await call('courierMarkAgroPickedUp', { courierPhone: A, orderId: 'g3b' }, A);
    await set('agro', 2500); // v6 - g3b allaqachon v5 da hisoblangan
    await call('adminSetAgroPickupStatus', { adminPhone: ADMIN, orderId: 'g3b', status: 'completed' }, ADMIN);
    d = await get('agro_pickup_orders/g3b');
    assert.deepStrictEqual([d.courierPayout, d.courierPayoutVersion], [3000, 5], 'baza o\'zgarmadi - hisob tegilmadi');
    await set('agro', 1000); // v7
  });
  await check('G4 agro: kuryersiz (admin qo\'lda yig\'di) - kuryer haqi maydonlari YOZILMAYDI', async () => {
    await db.collection('agro_pickup_orders').doc('g4').set({ customerId: CUSTOMER, customerPhone: CUSTOMER, productType: 'milk', literCount: 20, priceMode: 'admin', finalPrice: 10000, status: 'accepted', createdAt: at(1000) });
    await call('adminSetAgroPickupStatus', { adminPhone: ADMIN, orderId: 'g4', status: 'picked_up' }, ADMIN);
    await call('adminSetAgroPickupStatus', { adminPhone: ADMIN, orderId: 'g4', status: 'completed' }, ADMIN);
    const d = await get('agro_pickup_orders/g4');
    for (const k of PAYOUT_KEYS) assert.ok(!(k in d), `${k} yozilmasligi kerak`);
  });

  // ── 4. Yig'ib olish ──────────────────────────────────────────────────
  await check('Y1 yig\'ib olish: finalValue 50 000 x 5 % = 2 500; hamyon natijasi (mijozga 50 000) O\'ZGARMADI', async () => {
    await db.collection('sell_submissions').doc('s1').set({ userPhone: CUSTOMER, userId: CUSTOMER, userName: 'Mijoz', pickupAddress: 'Gurlan', status: 'new' });
    const t = await call('adminCreateCollectionTask', {
      adminPhone: ADMIN, submissionId: 's1', courierPhone: A, items: [{ code: 'milk', qty: 10 }],
    }, ADMIN);
    await db.collection('collection_tasks').doc(t.taskId).update({ arrivedAt: admin.firestore.Timestamp.now() });
    const r = await call('courierFinalizeCollection', { courierPhone: A, taskId: t.taskId, cashGiven: 0, items: [{ code: 'milk', qty: 10 }] }, A);
    assert.deepStrictEqual({ V: r.V, wc: r.walletCredit }, { V: 50000, wc: 50000 });
    const d = await get(`collection_tasks/${t.taskId}`);
    assert.deepStrictEqual(payoutOf(d), {
      courierPayout: 2500, courierPayoutBps: 500, courierPayoutVersion: 7, courierPayoutBase: 50000,
      courierPayoutCourierId: A, courierPayoutReason: null,
    });
    assert.strictEqual(d.finalValue, 50000);
    assert.strictEqual((await get(`users/${CUSTOMER}`)).bonusBalance, 50000, 'mijoz hamyoni avvalgidek');
    const again = await call('courierFinalizeCollection', { courierPhone: A, taskId: t.taskId, cashGiven: 0, items: [{ code: 'milk', qty: 10 }] }, A);
    assert.strictEqual(again.alreadyCompleted, true);
    assert.strictEqual((await get(`collection_tasks/${t.taskId}`)).courierPayout, 2500, 'takrorda o\'zgarmadi');
  });
  await check('Y2 yig\'ib olish: foiz sozlanmagan -> yakun o\'tadi (pul oqimi o\'zgarmaydi), courierPayout null', async () => {
    await set('collection', null);
    await db.collection('sell_submissions').doc('s2').set({ userPhone: CUSTOMER, userId: CUSTOMER, userName: 'Mijoz', pickupAddress: 'Gurlan', status: 'new' });
    const t = await call('adminCreateCollectionTask', {
      adminPhone: ADMIN, submissionId: 's2', courierPhone: A, items: [{ code: 'milk', qty: 2 }],
    }, ADMIN);
    await db.collection('collection_tasks').doc(t.taskId).update({ arrivedAt: admin.firestore.Timestamp.now() });
    const r = await call('courierFinalizeCollection', { courierPhone: A, taskId: t.taskId, cashGiven: 0, items: [{ code: 'milk', qty: 2 }] }, A);
    assert.strictEqual(r.walletCredit, 10000);
    const d = await get(`collection_tasks/${t.taskId}`);
    assert.deepStrictEqual([d.courierPayout, d.courierPayoutReason, d.courierPayoutBps], [null, 'not_configured', null]);
  });

  await check('S1 sverka: Σdr == Σcr (kuryer haqi uchun ledger yozuvi yaratilmagan)', async () => {
    const s = await db.collection(ledger.COL_JOURNAL).get();
    for (const d of s.docs) {
      const legs = d.data().legs || [];
      assert.strictEqual(legs.reduce((a, l) => a + (l.dr || 0), 0), legs.reduce((a, l) => a + (l.cr || 0), 0), d.id);
      assert.ok(!/payout|courier_task/i.test(String(d.data().kind || '')), `kutilmagan kind: ${d.data().kind}`);
    }
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
