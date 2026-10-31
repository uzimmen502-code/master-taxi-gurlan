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
 *   - yakunda haq (butun, floor), bps, versiya, baza, kuryer SERVERGA XOS
 *     `courier_task_payouts/{modul}_{vazifaId}` ga yoziladi; vazifa hujjatiga (mijoz o'qiydi,
 *     yig'ib olishda kuryer ham) HECH QANDAY `courierPayout*` maydoni yozilmaydi (maxfiylik, 14-qoida)
 *   - foiz sozlanmagan -> payout null (not_configured); narx noma'lum -> null (price_unknown)
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
// D5 (maxfiylik): kuryer haqi ichki xarajat - vazifa hujjatiga (mijoz o'qiydi) YOZILMAYDI,
// faqat serverga xos `courier_task_payouts/{modul}_{vazifaId}` ga.
const OLD_TASK_KEYS = ['courierPayout', 'courierPayoutBps', 'courierPayoutVersion', 'courierPayoutBase',
  'courierPayoutCourierId', 'courierPayoutReason', 'courierPayoutAt'];
const noPayoutOnTask = (d, label) => {
  for (const k of OLD_TASK_KEYS) assert.ok(!(k in d), `${label}: ${k} vazifa hujjatida bo'lmasligi kerak`);
};
const payoutDoc = (module, id) => get(`courier_task_payouts/${module}_${id}`);
const payoutOf = async (module, id) => {
  const d = await payoutDoc(module, id);
  assert.ok(d, `courier_task_payouts/${module}_${id} yo'q`);
  return { payout: d.payout, bps: d.bps, version: d.version, base: d.base, courierId: d.courierId, reason: d.reason };
};
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
    noPayoutOnTask(d, 'c1');
    assert.deepStrictEqual(await payoutOf('carpet', 'c1'), {
      payout: 6000, bps: 1500, version: 3, base: 40000,
      courierId: A, reason: null,
    });
    const pd1 = await payoutDoc('carpet', 'c1');
    assert.ok(pd1.computedAt, 'computedAt');
    assert.deepStrictEqual([pd1.module, pd1.taskId], ['carpet', 'c1']);
    assert.strictEqual(d.finalPrice, 40000, 'mijoz narxi tegilmadi');
    assert.strictEqual(await journalSize(), j0, 'ledger yozuvi YO\'Q');
    assert.strictEqual((await get(`users/${A}`)).bonusBalance, 0, 'kuryer hamyoni o\'zgarmadi');
  });
  await check('C2 takror yakun rad (status completed) - haq qayta hisoblanmaydi', async () => {
    await assert.rejects(call('courierMarkCarpetDelivered', { courierPhone: A, orderId: 'c1' }, A), (e) => e.code === 'failed-precondition');
    assert.strictEqual((await payoutDoc('carpet', 'c1')).payout, 6000);
  });
  await check('C3 floor: 33 333 x 15 % = 4 999', async () => {
    await carpet('c3', { finalPrice: 33333 });
    await call('courierMarkCarpetDelivered', { courierPhone: A, orderId: 'c3' }, A);
    assert.strictEqual((await payoutDoc('carpet', 'c3')).payout, 4999);
  });
  await check('C4 narx noma\'lum (finalPrice 0): yakun o\'tadi, courierPayout null, sabab price_unknown, foiz saqlanadi', async () => {
    await carpet('c4', { finalPrice: 0 });
    const r = await call('courierMarkCarpetDelivered', { courierPhone: A, orderId: 'c4' }, A);
    assert.strictEqual(r.status, 'completed');
    const d = await get('carpet_wash_orders/c4');
    noPayoutOnTask(d, 'c4');
    assert.deepStrictEqual(await payoutOf('carpet', 'c4'), {
      payout: null, bps: 1500, version: 3, base: null,
      courierId: A, reason: 'price_unknown',
    });
  });
  await check('C5 foiz sozlanmagan (null): yakun o\'tadi, courierPayout null, sabab not_configured, versiya = hujjat versiyasi', async () => {
    const r = await set('carpet', null);
    assert.strictEqual(r.version, 4);
    assert.strictEqual((await call('adminGetCourierTaskPayoutSettings', {}, ADMIN)).modules.carpet, null);
    await carpet('c5');
    await call('courierMarkCarpetDelivered', { courierPhone: A, orderId: 'c5' }, A);
    assert.deepStrictEqual(await payoutOf('carpet', 'c5'), {
      payout: null, bps: null, version: 4, base: 40000,
      courierId: A, reason: 'not_configured',
    });
    await set('carpet', 2000); // v5 - keyingi testlar uchun
    await carpet('c6');
    await call('courierMarkCarpetDelivered', { courierPhone: A, orderId: 'c6' }, A);
    assert.deepStrictEqual(await payoutOf('carpet', 'c6'), {
      payout: 8000, bps: 2000, version: 5, base: 40000,
      courierId: A, reason: null,
    });
    assert.strictEqual((await payoutDoc('carpet', 'c1')).version, 3, 'eski vazifa o\'z versiyasida qoladi');
  });

  // ── 3. Agro ──────────────────────────────────────────────────────────
  await check('G1 agro: narx olib ketishda ma\'lum (30 000 x 10 % = 3 000) - o\'sha qadamda hisoblanadi', async () => {
    await agro('g1', { finalPrice: 30000 });
    const r = await call('courierMarkAgroPickedUp', { courierPhone: A, orderId: 'g1' }, A);
    assert.deepStrictEqual(r, { ok: true, orderId: 'g1', status: 'picked_up' });
    assert.deepStrictEqual(await payoutOf('agro', 'g1'), {
      payout: 3000, bps: 1000, version: 5, base: 30000,
      courierId: A, reason: null,
    });
  });
  await check('G2 agro: narx noma\'lum -> price_unknown; admin yakunda narx qo\'yadi (20 000) -> o\'sha qadamda 2 000', async () => {
    await agro('g2');
    await call('courierMarkAgroPickedUp', { courierPhone: A, orderId: 'g2' }, A);
    let d = await get('agro_pickup_orders/g2');
    noPayoutOnTask(d, 'g2');
    const pdG2 = await payoutDoc('agro', 'g2');
    assert.strictEqual(pdG2.payout, null);
    assert.strictEqual(pdG2.reason, 'price_unknown');
    const r = await call('adminSetAgroPickupStatus', { adminPhone: ADMIN, orderId: 'g2', status: 'completed', finalPrice: 20000 }, ADMIN);
    assert.deepStrictEqual(r, { ok: true, orderId: 'g2', status: 'completed' });
    d = await get('agro_pickup_orders/g2');
    assert.strictEqual(d.finalPrice, 20000);
    noPayoutOnTask(d, 'g2 yakun');
    assert.deepStrictEqual(await payoutOf('agro', 'g2'), {
      payout: 2000, bps: 1000, version: 5, base: 20000,
      courierId: A, reason: null,
    });
  });
  await check('G3 agro: olib ketishda hisoblangan, admin yakunda narxni O\'ZGARTIRSA - baza o\'zgarganda qayta hisoblanadi (3 000 -> 4 000); o\'zgarmasa tegilmaydi', async () => {
    await agro('g3', { finalPrice: 30000 });
    await call('courierMarkAgroPickedUp', { courierPhone: A, orderId: 'g3' }, A);
    await call('adminSetAgroPickupStatus', { adminPhone: ADMIN, orderId: 'g3', status: 'completed', finalPrice: 40000 }, ADMIN);
    let d = await get('agro_pickup_orders/g3');
    noPayoutOnTask(d, 'g3');
    let pd = await payoutDoc('agro', 'g3');
    assert.deepStrictEqual([pd.payout, pd.base], [4000, 40000]);
    assert.deepStrictEqual([pd.previous.payout, pd.previous.base], [3000, 30000], 'avvalgi hisob izi saqlanadi (16-qoida)');
    await agro('g3b', { finalPrice: 30000 });
    await call('courierMarkAgroPickedUp', { courierPhone: A, orderId: 'g3b' }, A);
    await set('agro', 2500); // v6 - g3b allaqachon v5 da hisoblangan
    await call('adminSetAgroPickupStatus', { adminPhone: ADMIN, orderId: 'g3b', status: 'completed' }, ADMIN);
    pd = await payoutDoc('agro', 'g3b');
    assert.deepStrictEqual([pd.payout, pd.version], [3000, 5], 'baza o\'zgarmadi - hisob tegilmadi');
    await set('agro', 1000); // v7
  });
  await check('G4 agro: kuryersiz (admin qo\'lda yig\'di) - kuryer haqi maydonlari YOZILMAYDI', async () => {
    await db.collection('agro_pickup_orders').doc('g4').set({ customerId: CUSTOMER, customerPhone: CUSTOMER, productType: 'milk', literCount: 20, priceMode: 'admin', finalPrice: 10000, status: 'accepted', createdAt: at(1000) });
    await call('adminSetAgroPickupStatus', { adminPhone: ADMIN, orderId: 'g4', status: 'picked_up' }, ADMIN);
    await call('adminSetAgroPickupStatus', { adminPhone: ADMIN, orderId: 'g4', status: 'completed' }, ADMIN);
    const d = await get('agro_pickup_orders/g4');
    noPayoutOnTask(d, 'g4');
    assert.strictEqual(await payoutDoc('agro', 'g4'), undefined, 'kuryersiz - haq hujjati ham yo\'q');
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
    noPayoutOnTask(d, 'y1');
    assert.deepStrictEqual(await payoutOf('collection', t.taskId), {
      payout: 2500, bps: 500, version: 7, base: 50000,
      courierId: A, reason: null,
    });
    assert.strictEqual(d.finalValue, 50000);
    assert.strictEqual((await get(`users/${CUSTOMER}`)).bonusBalance, 50000, 'mijoz hamyoni avvalgidek');
    const again = await call('courierFinalizeCollection', { courierPhone: A, taskId: t.taskId, cashGiven: 0, items: [{ code: 'milk', qty: 10 }] }, A);
    assert.strictEqual(again.alreadyCompleted, true);
    assert.strictEqual((await payoutDoc('collection', t.taskId)).payout, 2500, 'takrorda o\'zgarmadi');
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
    noPayoutOnTask(d, 'y2');
    const pd2 = await payoutDoc('collection', t.taskId);
    assert.deepStrictEqual([pd2.payout, pd2.reason, pd2.bps], [null, 'not_configured', null]);
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
