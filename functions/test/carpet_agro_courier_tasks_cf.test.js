/**
 * Gilam yuvish / sut qabul — kuryer vazifalari ro'yxati callable'lari
 * (`courierListCarpetTasks`, `courierListAgroTasks`). HAQIQIY
 * `functions/index.js` callable'lari `.run()` orqali, Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-carpet-agro-tasks \
 *     "node functions/test/carpet_agro_courier_tasks_cf.test.js"
 *
 * Muammo (2026-10-08): `role: 'user'` + tasdiqlangan courier capability'li
 * kuryer gilam (`pickup_ready` / `return_ready`) va sut (`accepted` /
 * `pickup_in_delivery`) vazifalari ro'yxatini ocholmaydi — qoida faqat staff
 * va mijozga o'qish beradi, `courier` esa `isStaff()`da yo'q (D-SERVICE-4 /
 * D-CLEAN-1). Qoida tomoni: `functions/test/carpet_agro_courier_rules.test.js`.
 *
 * Qulflanadi:
 *   - capability'siz foydalanuvchi hech qaysi ro'yxatni ololmaydi;
 *     suspended kuryer olish ro'yxatini ololmaydi, qo'lidagini ('active') oladi
 *   - olish ro'yxatida FAQAT id, son va vaqt — ism, telefon, manzil, izoh YO'Q
 *   - 'active' — FAQAT shu kuryer olgan vazifalar (sut: avval ekran HAMMA
 *     `pickup_in_delivery`ni olib, begonasini klientda yashirardi)
 *   - ro'yxatdagi vazifani claim callable oladi, keyin u 'active'da chiqadi
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-carpet-agro-tasks';
// Production'ga yozmaslik (28-qoida): faqat emulator `demo-*` loyihasi.
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require(process.env.COURIER_CF_INDEX || '../index');
const admin = require('firebase-admin');

const db = admin.firestore();

const A = '998901110001'; // tasdiqlangan kuryer
const B = '998902220002'; // tasdiqlangan kuryer (begona)
const S = '998903330003'; // suspended kuryer
const STRANGER = '998904440004'; // capability yo'q
const CUSTOMER = '998905550005';
const ACC = { [A]: 'accCOURIER0000000000A', [B]: 'accCOURIER0000000000B', [S]: 'accCOURIER0000000000S' };

const ctxOf = (phone) => ({ auth: { uid: `uid_${phone}`, token: { phone_number: `+${phone}` } } });
const call = (name, data, phone) => fns[name].run(data, ctxOf(phone));
const carpetList = (list, phone) => call('courierListCarpetTasks', { list }, phone);
const agroList = (list, phone) => call('courierListAgroTasks', { list }, phone);
const ids = (r) => r.tasks.map((t) => t.id);
const at = (ms) => admin.firestore.Timestamp.fromMillis(ms);

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
const rejectsWith = (promise, code) => assert.rejects(promise, (e) => {
  assert.strictEqual(e.code, code, `kod ${e.code}: ${e.message}`);
  return true;
});

async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
async function seedCourier(phone, status) {
  await db.collection('users').doc(phone).set({ role: 'user', accountId: ACC[phone] });
  await db.collection('provider_capabilities').doc(ACC[phone]).set({
    identity: { accountId: ACC[phone], primaryUid: phone },
    courier: { active: true },
    status: { courier: status },
  });
}
async function reset() {
  await clearEmulator();
  await seedCourier(A, 'approved');
  await seedCourier(B, 'approved');
  await seedCourier(S, 'suspended');
  await db.collection('users').doc(STRANGER).set({ role: 'user' });
  await db.collection('users').doc(CUSTOMER).set({ role: 'user' });
}

/** `placeCarpetWashOrder` yozadigan shakl (PII bilan). */
const carpet = (id, over = {}) => db.collection('carpet_wash_orders').doc(id).set({
  customerId: CUSTOMER, customerPhone: CUSTOMER, customerName: 'Mijoz Ismi',
  pickupAddress: 'Gurlan, Navoiy ko\'chasi 7', pickupLat: 41.84, pickupLng: 60.39,
  carpetCount: 3, note: '2-qavat, tel 998901234567', priceMode: 'admin', finalPrice: 0,
  status: 'pickup_ready', pickupCourierId: '', returnCourierId: '', createdAt: at(1000),
  ...over,
});
/** `placeAgroPickupOrder` yozadigan shakl (PII bilan). */
const agro = (id, over = {}) => db.collection('agro_pickup_orders').doc(id).set({
  customerId: CUSTOMER, customerPhone: CUSTOMER, customerName: 'Mijoz Ismi', productType: 'milk',
  pickupAddress: 'Gurlan, Navoiy ko\'chasi 7', pickupLat: 41.84, pickupLng: 60.39,
  literCount: 20, note: 'ertalab, tel 998901234567', priceMode: 'admin', finalPrice: 0,
  status: 'accepted', createdAt: at(1000),
  ...over,
});
const carpetDoc = async (id) => (await db.collection('carpet_wash_orders').doc(id).get()).data();

const PREVIEW_PII = ['customerName', 'customerPhone', 'customerId', 'pickupAddress', 'pickupLat', 'pickupLng', 'note'];

async function main() {
  // ── gilam: huquq ─────────────────────────────────────────────────────
  await reset();
  await check('gilam: autentifikatsiyasiz — unauthenticated', async () => {
    await rejectsWith(fns.courierListCarpetTasks.run({ list: 'pickup' }, {}), 'unauthenticated');
  });
  await check('gilam: noma\'lum `list` — invalid-argument', async () => {
    await rejectsWith(carpetList('everything', A), 'invalid-argument');
    await rejectsWith(carpetList('', A), 'invalid-argument');
    await rejectsWith(carpetList('__proto__', A), 'invalid-argument');
  });
  await check('gilam: capability\'siz foydalanuvchi — hech qaysi ro\'yxat yo\'q', async () => {
    for (const list of ['pickup', 'return', 'active']) {
      await rejectsWith(carpetList(list, STRANGER), 'permission-denied');
    }
  });
  await check('gilam: suspended — yangi ish (pickup/return) yo\'q, qo\'lidagini (active) oladi', async () => {
    await carpet('cS', { status: 'pickup_in_delivery', pickupCourierId: S });
    await rejectsWith(carpetList('pickup', S), 'permission-denied');
    await rejectsWith(carpetList('return', S), 'permission-denied');
    assert.deepStrictEqual(ids(await carpetList('active', S)), ['cS']);
  });

  // ── gilam: olish ro'yxatlari — faqat id/son/vaqt ─────────────────────
  await reset();
  await carpet('p1', { createdAt: at(1000) });
  await carpet('p2', { createdAt: at(3000), carpetCount: 5 });
  await carpet('pNoDate', { createdAt: null, carpetCount: 'x' });
  await carpet('r1', { status: 'return_ready', createdAt: at(2000) });
  await carpet('busyB', { status: 'pickup_in_delivery', pickupCourierId: B, createdAt: at(4000) });
  await carpet('washing', { status: 'washing', createdAt: at(5000) });
  await check('gilam pickup: faqat `pickup_ready`, yangisi birinchi, telefon/ism/manzil/izoh YO\'Q', async () => {
    const r = await carpetList('pickup', A);
    assert.deepStrictEqual(ids(r), ['p2', 'p1', 'pNoDate']);
    for (const t of r.tasks) {
      assert.deepStrictEqual(Object.keys(t).sort(), ['carpetCount', 'createdAtMs', 'id'], `ortiqcha maydon: ${t.id}`);
      for (const k of PREVIEW_PII) assert.ok(!(k in t), `${k} olishdan oldin berildi`);
    }
    assert.deepStrictEqual(r.tasks[0], { id: 'p2', carpetCount: 5, createdAtMs: 3000 });
    assert.deepStrictEqual(r.tasks[2], { id: 'pNoDate', carpetCount: 0, createdAtMs: null });
    assert.strictEqual(r.truncated, false);
  });
  await check('gilam return: faqat `return_ready`, faqat id/son/vaqt', async () => {
    const r = await carpetList('return', A);
    assert.deepStrictEqual(r.tasks, [{ id: 'r1', carpetCount: 3, createdAtMs: 2000 }]);
  });

  // ── gilam: 'active' — faqat o'ziniki, ish uchun to'liq ───────────────
  await reset();
  await carpet('aPick', { status: 'pickup_in_delivery', pickupCourierId: A, createdAt: at(1000) });
  await carpet('aRet', {
    status: 'return_in_delivery', pickupCourierId: B, returnCourierId: A, createdAt: at(2000),
    returnArrivedAt: at(2500),
  });
  await carpet('bPick', { status: 'pickup_in_delivery', pickupCourierId: B });
  await carpet('bRet', { status: 'return_in_delivery', pickupCourierId: A, returnCourierId: B });
  await carpet('aPickedUp', { status: 'picked_up', pickupCourierId: A });
  await carpet('aDone', { status: 'completed', pickupCourierId: A, returnCourierId: A });
  await carpet('aOld9', { status: 'pickup_in_delivery', pickupCourierId: A.slice(3) });
  await check('gilam active: faqat o\'zi olgan pickup/return, begonasi va tugagani yo\'q', async () => {
    const r = await carpetList('active', A);
    assert.deepStrictEqual(ids(r), ['aRet', 'aPick']);
    assert.deepStrictEqual(r.tasks[0], {
      id: 'aRet', status: 'return_in_delivery', carpetCount: 3,
      pickupAddress: 'Gurlan, Navoiy ko\'chasi 7', customerName: 'Mijoz Ismi', customerPhone: CUSTOMER,
      pickupArrivedAtMs: null, returnArrivedAtMs: 2500, createdAtMs: 2000,
    });
    assert.ok(!('note' in r.tasks[0]) && !('pickupLat' in r.tasks[0]), 'ekranda ishlatilmaydigan PII yo\'q');
    // B: o'zi olgan pickup va return; A ning vazifalari yo'q (vaqti bir xil — tartibsiz solishtiriladi).
    assert.deepStrictEqual(ids(await carpetList('active', B)).sort(), ['bPick', 'bRet']);
  });
  await check('gilam active: kanon bo\'lmagan (9 xonali) kuryer ID ko\'rinmaydi — mark callable ham rad etadi', async () => {
    assert.ok(!ids(await carpetList('active', A)).includes('aOld9'));
    await rejectsWith(call('courierMarkCarpetArrived', { courierPhone: A, orderId: 'aOld9', leg: 'pickup' }, A),
      'permission-denied');
  });

  // ── gilam: ro'yxat → claim → active ──────────────────────────────────
  await reset();
  await carpet('flow', { createdAt: at(1000) });
  await check('gilam: ro\'yxatdagi vazifani claim oladi, u pickup\'dan ketib active\'da chiqadi', async () => {
    const [task] = (await carpetList('pickup', A)).tasks;
    assert.strictEqual(task.id, 'flow');
    await call('courierClaimCarpetPickup', { courierPhone: A, orderId: task.id }, A);
    assert.deepStrictEqual((await carpetList('pickup', A)).tasks, []);
    assert.deepStrictEqual((await carpetList('pickup', B)).tasks, [], 'B ham endi ko\'rmaydi');
    let active = (await carpetList('active', A)).tasks;
    assert.deepStrictEqual(active.map((t) => t.id), ['flow']);
    assert.strictEqual(active[0].customerPhone, CUSTOMER, 'olgandan keyin telefon ochiladi');
    assert.strictEqual(active[0].pickupArrivedAtMs, null);
    await call('courierMarkCarpetArrived', { courierPhone: A, orderId: 'flow', leg: 'pickup' }, A);
    active = (await carpetList('active', A)).tasks;
    assert.strictEqual(typeof active[0].pickupArrivedAtMs, 'number', '«yetib keldim»dan keyin belgi bor');
    await call('courierMarkCarpetPickedUp', { courierPhone: A, orderId: 'flow' }, A);
    assert.deepStrictEqual((await carpetList('active', A)).tasks, [], 'olib ketilgach active bo\'sh');
    assert.strictEqual((await carpetDoc('flow')).status, 'picked_up');
  });

  // ── sut: huquq ───────────────────────────────────────────────────────
  await reset();
  await check('sut: autentifikatsiyasiz — unauthenticated; noma\'lum list — invalid-argument', async () => {
    await rejectsWith(fns.courierListAgroTasks.run({ list: 'pickup' }, {}), 'unauthenticated');
    await rejectsWith(agroList('return', A), 'invalid-argument');
  });
  await check('sut: capability\'siz — rad; suspended — pickup rad, active oladi', async () => {
    await agro('mS', { status: 'pickup_in_delivery', pickupCourierId: S });
    await rejectsWith(agroList('pickup', STRANGER), 'permission-denied');
    await rejectsWith(agroList('active', STRANGER), 'permission-denied');
    await rejectsWith(agroList('pickup', S), 'permission-denied');
    assert.deepStrictEqual(ids(await agroList('active', S)), ['mS']);
  });

  // ── sut: olish ro'yxati va 'active' ──────────────────────────────────
  await reset();
  await agro('m1', { createdAt: at(1000) });
  await agro('m2', { createdAt: at(2000), literCount: 35.5 });
  await agro('mNew', { status: 'new' });
  await agro('mA', { status: 'pickup_in_delivery', pickupCourierId: A, createdAt: at(3000), arrivedAt: at(3500) });
  await agro('mB', { status: 'pickup_in_delivery', pickupCourierId: B, createdAt: at(4000) });
  await agro('mAdone', { status: 'picked_up', pickupCourierId: A });
  await check('sut pickup: faqat `accepted`, faqat id/mahsulot/litr/vaqt', async () => {
    const r = await agroList('pickup', A);
    assert.deepStrictEqual(ids(r), ['m2', 'm1']);
    for (const t of r.tasks) {
      assert.deepStrictEqual(Object.keys(t).sort(), ['createdAtMs', 'id', 'literCount', 'productType'],
        `ortiqcha maydon: ${t.id}`);
    }
    assert.deepStrictEqual(r.tasks[0], { id: 'm2', productType: 'milk', literCount: 35.5, createdAtMs: 2000 });
  });
  await check('sut active: FAQAT o\'zi olgan — begona kuryerning `pickup_in_delivery`si kelmaydi', async () => {
    const r = await agroList('active', A);
    assert.deepStrictEqual(r.tasks, [{
      id: 'mA', status: 'pickup_in_delivery', productType: 'milk', literCount: 20,
      pickupAddress: 'Gurlan, Navoiy ko\'chasi 7', customerName: 'Mijoz Ismi', customerPhone: CUSTOMER,
      note: 'ertalab, tel 998901234567', arrivedAtMs: 3500, createdAtMs: 3000,
    }]);
    assert.deepStrictEqual(ids(await agroList('active', B)), ['mB']);
  });
  await check('sut: ro\'yxatdagi vazifani claim oladi, u active\'da chiqadi', async () => {
    await call('courierClaimAgroPickup', { courierPhone: B, orderId: 'm1' }, B);
    assert.deepStrictEqual(ids(await agroList('pickup', A)), ['m2']);
    assert.deepStrictEqual(ids(await agroList('active', B)), ['mB', 'm1']);
    assert.ok(!ids(await agroList('active', A)).includes('m1'));
  });

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} o'tdi.`);
  process.exit(failed.length ? 1 : 0);
}
main().catch((e) => { console.error('FATAL', e); process.exit(1); });
