/**
 * Admin «vazifani kuryerdan olib qo'yish» (B1, ega qarori 2026-10-16): gilam va agro.
 * HAQIQIY `functions/index.js` callable'lari `.run()` orqali, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-task-release \
 *     "node functions/test/courier_task_release_cf.test.js"
 *
 * Yangi qirralar (FAQAT admin; kuryer callable'lari o'zgarmagan):
 *   gilam: pickup_in_delivery -> pickup_ready, return_in_delivery -> return_ready
 *   agro : pickup_in_delivery -> accepted
 * Release: kuryer maydonlari (id + "yetib keldim" belgisi) bitta tranzaksiyada tozalanadi,
 * `admin_audit` yoziladi, takror bosish - o'zgarishsiz (audit ko'paymaydi), hech kimga
 * xabar yuborilmaydi. Boshqa o'tishlar (masalan pickup_in_delivery -> picked_up) AVVALGIDEK rad.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-task-release';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require('../index');
const admin = require('firebase-admin');

const db = admin.firestore();

const ADMIN = '998909990000';
const STRANGER = '998904440004';
const A = '998901110001';
const B = '998902220002';
const CUSTOMER = '998905550005';
const ACC = { [A]: 'accCOURIER0000000000A', [B]: 'accCOURIER0000000000B' };

const ctxOf = (phone) => ({ auth: { uid: `uid_${phone}`, token: { phone_number: `+${phone}` } } });
const call = (name, data, phone) => fns[name].run(data, ctxOf(phone));
const at = (ms) => admin.firestore.Timestamp.fromMillis(ms);

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
const rejectsWith = (promise, code, msg) => assert.rejects(promise, (e) => {
  assert.strictEqual(e.code, code, `kod ${e.code}: ${e.message}`);
  if (msg) assert.strictEqual(e.message, msg);
  return true;
});

async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
async function seedCourier(phone) {
  await db.collection('users').doc(phone).set({ role: 'user', accountId: ACC[phone] });
  await db.collection('provider_capabilities').doc(ACC[phone]).set({
    identity: { accountId: ACC[phone], primaryUid: phone }, courier: { active: true }, status: { courier: 'approved' },
  });
}
async function reset() {
  await clearEmulator();
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(STRANGER).set({ role: 'user' });
  await db.collection('users').doc(CUSTOMER).set({ role: 'user', name: 'Mijoz' });
  await seedCourier(A);
  await seedCourier(B);
}
const carpet = (id, over = {}) => db.collection('carpet_wash_orders').doc(id).set({
  customerId: CUSTOMER, customerPhone: CUSTOMER, carpetCount: 3, priceMode: 'admin', finalPrice: 40000,
  status: 'pickup_in_delivery', pickupCourierId: A, returnCourierId: '', pickupArrivedAt: at(5000), createdAt: at(1000), ...over,
});
const agro = (id, over = {}) => db.collection('agro_pickup_orders').doc(id).set({
  customerId: CUSTOMER, customerPhone: CUSTOMER, productType: 'milk', literCount: 20, priceMode: 'admin', finalPrice: 0,
  status: 'pickup_in_delivery', pickupCourierId: A, arrivedAt: at(5000), createdAt: at(1000), ...over,
});
const get = async (path) => (await db.doc(path).get()).data();
const setCarpet = (orderId, status, who = ADMIN, extra = {}) => call('adminSetCarpetWashStatus', { adminPhone: who, orderId, status, ...extra }, who);
const setAgro = (orderId, status, who = ADMIN, extra = {}) => call('adminSetAgroPickupStatus', { adminPhone: who, orderId, status, ...extra }, who);
const audits = async (kind) => (await db.collection('admin_audit').where('kind', '==', kind).get()).docs.map((d) => d.data());
const newsCount = async () => (await db.collection('admin_news').get()).size;

async function main() {
  await reset();

  await check('R1 gilam olib ketish: pickup_in_delivery -> pickup_ready; kuryer id va "yetib keldim" tozalanadi; audit; xabar yo\'q', async () => {
    await carpet('r1');
    const n0 = await newsCount();
    const r = await setCarpet('r1', 'pickup_ready', ADMIN, { reason: 'kuryer javob bermayapti' });
    assert.deepStrictEqual(r, { ok: true, orderId: 'r1', status: 'pickup_ready' });
    const d = await get('carpet_wash_orders/r1');
    assert.strictEqual(d.status, 'pickup_ready');
    assert.strictEqual(d.pickupCourierId, '');
    assert.ok(!('pickupArrivedAt' in d), 'pickupArrivedAt o\'chirildi');
    assert.strictEqual(d.finalPrice, 40000, 'narx tegilmadi');
    const a = await audits('carpet_task_release');
    assert.strictEqual(a.length, 1);
    assert.deepStrictEqual({ t: a[0].target, f: a[0].from, to: a[0].to, actor: a[0].actor, r: a[0].reason, c: a[0].detail.releasedCourierId },
      { t: 'r1', f: 'pickup_in_delivery', to: 'pickup_ready', actor: ADMIN, r: 'kuryer javob bermayapti', c: A });
    assert.strictEqual(await newsCount(), n0, 'hech kimga xabar yuborilmadi');
  });
  await check('R2 release\'dan keyin: eski kuryer "olib ketdim" qila olmaydi; yangi kuryer oladi va yakunlaydi', async () => {
    await rejectsWith(call('courierMarkCarpetPickedUp', { courierPhone: A, orderId: 'r1' }, A), 'failed-precondition');
    await call('courierClaimCarpetPickup', { courierPhone: B, orderId: 'r1' }, B);
    assert.strictEqual((await get('carpet_wash_orders/r1')).pickupCourierId, B);
    await rejectsWith(call('courierMarkCarpetPickedUp', { courierPhone: B, orderId: 'r1' }, B), 'failed-precondition'); // arrived first
    await call('courierMarkCarpetArrived', { courierPhone: B, orderId: 'r1', leg: 'pickup' }, B);
    await call('courierMarkCarpetPickedUp', { courierPhone: B, orderId: 'r1' }, B);
    assert.strictEqual((await get('carpet_wash_orders/r1')).status, 'picked_up');
  });
  await check('R3 gilam qaytarish: return_in_delivery -> return_ready; returnCourierId + returnArrivedAt tozalanadi; yangi kuryer oladi', async () => {
    await carpet('r3', { status: 'return_in_delivery', returnCourierId: A, returnArrivedAt: at(6000), pickupCourierId: B });
    await setCarpet('r3', 'return_ready');
    const d = await get('carpet_wash_orders/r3');
    assert.strictEqual(d.status, 'return_ready');
    assert.strictEqual(d.returnCourierId, '');
    assert.ok(!('returnArrivedAt' in d));
    assert.strictEqual(d.pickupCourierId, B, 'olib ketgan kuryer yozuvi tegilmadi');
    await rejectsWith(call('courierMarkCarpetDelivered', { courierPhone: A, orderId: 'r3' }, A), 'failed-precondition');
    await call('courierClaimCarpetReturn', { courierPhone: B, orderId: 'r3' }, B);
    assert.strictEqual((await get('carpet_wash_orders/r3')).returnCourierId, B);
    const a = (await audits('carpet_task_release')).filter((x) => x.target === 'r3');
    assert.deepStrictEqual([a.length, a[0].detail.releasedCourierId], [1, A]);
  });
  await check('R4 agro: pickup_in_delivery -> accepted; kuryer id va arrivedAt tozalanadi; audit; yangi kuryer oladi', async () => {
    await agro('r4');
    const r = await setAgro('r4', 'accepted', ADMIN, { reason: 'kuryer yo\'q' });
    assert.deepStrictEqual(r, { ok: true, orderId: 'r4', status: 'accepted' });
    const d = await get('agro_pickup_orders/r4');
    assert.strictEqual(d.status, 'accepted');
    assert.strictEqual(d.pickupCourierId, '');
    assert.ok(!('arrivedAt' in d));
    const a = await audits('agro_task_release');
    assert.deepStrictEqual([a.length, a[0].target, a[0].detail.releasedCourierId, a[0].reason], [1, 'r4', A, 'kuryer yo\'q']);
    await rejectsWith(call('courierMarkAgroPickedUp', { courierPhone: A, orderId: 'r4' }, A), 'failed-precondition');
    await call('courierClaimAgroPickup', { courierPhone: B, orderId: 'r4' }, B);
    assert.strictEqual((await get('agro_pickup_orders/r4')).pickupCourierId, B);
  });
  await check('R5 takror bosish: o\'zgarish yo\'q, audit ko\'paymaydi (idempotent)', async () => {
    await carpet('r5');
    await setCarpet('r5', 'pickup_ready');
    const again = await setCarpet('r5', 'pickup_ready');
    assert.strictEqual(again.ok, true);
    const parallel = await Promise.all([1, 2, 3].map(() => setCarpet('r5', 'pickup_ready').then(() => 'ok', (e) => `err:${e.code}`)));
    assert.deepStrictEqual(parallel, ['ok', 'ok', 'ok']);
    assert.strictEqual((await audits('carpet_task_release')).filter((x) => x.target === 'r5').length, 1);
    await agro('r5a');
    await setAgro('r5a', 'accepted');
    await setAgro('r5a', 'accepted');
    assert.strictEqual((await audits('agro_task_release')).filter((x) => x.target === 'r5a').length, 1);
  });
  await check('R6 faqat admin: begona / kuryer o\'zi rad; hujjat o\'zgarmaydi', async () => {
    await carpet('r6');
    await rejectsWith(setCarpet('r6', 'pickup_ready', STRANGER), 'permission-denied');
    await rejectsWith(setCarpet('r6', 'pickup_ready', A), 'permission-denied');
    await agro('r6a');
    await rejectsWith(setAgro('r6a', 'accepted', STRANGER), 'permission-denied');
    assert.strictEqual((await get('carpet_wash_orders/r6')).status, 'pickup_in_delivery');
    assert.strictEqual((await get('agro_pickup_orders/r6a')).status, 'pickup_in_delivery');
  });
  await check('R7 boshqa o\'tishlar AVVALGIDEK rad: pickup_in_delivery -> picked_up, return_in_delivery -> completed, agro -> picked_up (kuryer olgan)', async () => {
    await carpet('r7');
    await rejectsWith(setCarpet('r7', 'picked_up'), 'failed-precondition', 'CARPET_TRANSITION_NOT_ALLOWED');
    await carpet('r7b', { status: 'return_in_delivery', returnCourierId: A, returnArrivedAt: at(1) });
    await rejectsWith(setCarpet('r7b', 'completed'), 'failed-precondition', 'CARPET_TRANSITION_NOT_ALLOWED');
    await rejectsWith(setCarpet('r7b', 'ready'), 'failed-precondition', 'CARPET_TRANSITION_NOT_ALLOWED');
    await agro('r7a');
    await rejectsWith(setAgro('r7a', 'picked_up'), 'failed-precondition', 'AGRO_TRANSITION_NOT_ALLOWED');
    // kuryersiz holatlardan release qirrasi yo'q
    await carpet('r7c', { status: 'pickup_ready', pickupCourierId: '' });
    await rejectsWith(setCarpet('r7c', 'accepted'), 'failed-precondition', 'CARPET_TRANSITION_NOT_ALLOWED');
    assert.strictEqual((await get('carpet_wash_orders/r7')).pickupCourierId, A);
  });
  await check('R8 mavjud admin yo\'llari: new -> accepted -> pickup_ready (narx bilan); bekor; release auditi yo\'q', async () => {
    await db.collection('carpet_wash_orders').doc('r8').set({ customerPhone: CUSTOMER, finalPrice: 0, status: 'new', pickupCourierId: '', returnCourierId: '', createdAt: at(1) });
    await setCarpet('r8', 'accepted');
    await setCarpet('r8', 'pickup_ready', ADMIN, { finalPrice: 55000 });
    let d = await get('carpet_wash_orders/r8');
    assert.deepStrictEqual([d.status, d.finalPrice], ['pickup_ready', 55000]);
    await setCarpet('r8', 'cancelled');
    d = await get('carpet_wash_orders/r8');
    assert.strictEqual(d.status, 'cancelled');
    assert.strictEqual((await audits('carpet_task_release')).filter((x) => x.target === 'r8').length, 0);
  });
  await check('R9 parallel: kuryer "olib ketdim" ↔ admin release - BITTA g\'olib, holat aralashmaydi (status va kuryer maydoni izchil)', async () => {
    for (let i = 0; i < 6; i += 1) {
      const id = `race${i}`;
      await carpet(id);
      const rs = await Promise.all([
        call('courierMarkCarpetPickedUp', { courierPhone: A, orderId: id }, A).then(() => 'picked', (e) => `err:${e.code}`),
        setCarpet(id, 'pickup_ready').then(() => 'released', (e) => `err:${e.code}`),
      ]);
      const d = await get(`carpet_wash_orders/${id}`);
      if (d.status === 'picked_up') {
        assert.strictEqual(d.pickupCourierId, A, `${id}: picked_up, lekin kuryer tozalangan (${rs})`);
      } else {
        assert.strictEqual(d.status, 'pickup_ready', `${id}: ${d.status} (${rs})`);
        assert.strictEqual(d.pickupCourierId, '', `${id}: pickup_ready, lekin kuryer qolgan (${rs})`);
      }
      assert.strictEqual(rs.filter((x) => x === 'picked' || x === 'released').length >= 1, true);
    }
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
