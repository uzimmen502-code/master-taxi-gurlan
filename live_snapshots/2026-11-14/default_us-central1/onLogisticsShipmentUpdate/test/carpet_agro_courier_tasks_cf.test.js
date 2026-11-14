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

  // ── F4: Mark* callable'lar tranzaksiyada (audit 2026-10-16) ───────────────
  // Muammo: read → tekshiruv → update orasida admin/boshqa yozuv bekor qilsa, eski
  // kod `picked_up`/`completed` bilan "tiriltirardi"; ikki parallel «yetib keldim»
  // mijozga ikki xabar yuborardi.
  const FS = require('@google-cloud/firestore');
  /** Hujjat o'qilgach BIR MARTA tashqi yozuv: status → cancelled (admin bekori). */
  const armConcurrentCancel = (collection, id) => {
    const path = `${collection}/${id}`;
    const ref = db.collection(collection).doc(id);
    const origRef = FS.DocumentReference.prototype.get;
    const origTx = FS.Transaction.prototype.get;
    let fired = false;
    let pending = null;
    const cancel = () => ref.update({ status: 'cancelled' });
    FS.DocumentReference.prototype.get = async function patchedGet(...a) {
      const snap = await origRef.apply(this, a);
      if (!fired && this.path === path) { fired = true; await cancel(); }
      return snap;
    };
    FS.Transaction.prototype.get = async function patchedTxGet(r, ...a) {
      const snap = await origTx.call(this, r, ...a);
      // tranzaksiya ichida kutmaymiz (qulf): yozuv commit'dan keyin yoki retry'ni keltirib chiqaradi
      if (!fired && r && r.path === path) { fired = true; pending = cancel(); }
      return snap;
    };
    return {
      done: async () => {
        FS.DocumentReference.prototype.get = origRef;
        FS.Transaction.prototype.get = origTx;
        if (pending) await pending;
        return fired;
      },
    };
  };
  const settle = (p) => p.then(() => 'ok', (e) => `err:${e.code}`);
  const newsCount = async (orderId) => (await db.collection('admin_news')
    .where('source', '==', 'courier_arrived').where('orderId', '==', orderId).get()).size;

  await reset();
  const racy = [
    ['courierMarkCarpetPickedUp', 'carpet_wash_orders', { status: 'pickup_in_delivery', pickupCourierId: A, pickupArrivedAt: at(1) },
      { courierPhone: A, orderId: 'race1' }],
    ['courierMarkCarpetDelivered', 'carpet_wash_orders', { status: 'return_in_delivery', returnCourierId: A, returnArrivedAt: at(1) },
      { courierPhone: A, orderId: 'race1' }],
    ['courierMarkAgroPickedUp', 'agro_pickup_orders', { status: 'pickup_in_delivery', pickupCourierId: A, arrivedAt: at(1) },
      { courierPhone: A, orderId: 'race1' }],
  ];
  for (const [fn, coll, seed, args] of racy) {
    await check(`F4 ${fn}: o'qishdan keyingi bekor "tiriltirilmaydi" (cancelled qoladi)`, async () => {
      await db.collection(coll).doc('race1').set({ customerPhone: CUSTOMER, createdAt: at(1000), ...seed });
      const arm = armConcurrentCancel(coll, 'race1');
      let r;
      try { r = await settle(call(fn, args, A)); } finally { assert.ok(await arm.done(), 'hook ishladi'); }
      const st = (await db.collection(coll).doc('race1').get()).data().status;
      assert.strictEqual(st, 'cancelled', `natija ${r}, status ${st}`);
    });
  }

  await check('F4 carpet: parallel ikki «yetib keldim» — mijozga BITTA xabar, ikkalasi ok', async () => {
    await carpet('par1', { status: 'pickup_in_delivery', pickupCourierId: A });
    const args = { courierPhone: A, orderId: 'par1', leg: 'pickup' };
    const rs = await Promise.all([1, 2, 3, 4].map(() => settle(call('courierMarkCarpetArrived', args, A))));
    assert.deepStrictEqual(rs, ['ok', 'ok', 'ok', 'ok']);
    assert.strictEqual(await newsCount('par1'), 1);
    // keyingi takror chaqiruv ham ok, xabar ko'paymaydi
    const again = await call('courierMarkCarpetArrived', args, A);
    assert.strictEqual(again.idempotent, true);
    assert.strictEqual(await newsCount('par1'), 1);
  });
  await check('F4 agro: parallel ikki «yetib keldim» — mijozga BITTA xabar', async () => {
    await agro('par2', { status: 'pickup_in_delivery', pickupCourierId: A });
    const args = { courierPhone: A, orderId: 'par2' };
    const rs = await Promise.all([1, 2, 3, 4].map(() => settle(call('courierMarkAgroPickupArrived', args, A))));
    assert.deepStrictEqual(rs, ['ok', 'ok', 'ok', 'ok']);
    assert.strictEqual(await newsCount('par2'), 1);
  });
  await check('F4: begona kuryer va noto\'g\'ri status — avvalgidek rad', async () => {
    await carpet('own1', { status: 'pickup_in_delivery', pickupCourierId: A });
    await rejectsWith(call('courierMarkCarpetArrived', { courierPhone: B, orderId: 'own1', leg: 'pickup' }, B), 'permission-denied');
    await rejectsWith(call('courierMarkCarpetPickedUp', { courierPhone: A, orderId: 'own1' }, A), 'failed-precondition'); // arrived first
    await rejectsWith(call('courierMarkCarpetArrived', { courierPhone: A, orderId: 'own1', leg: 'return' }, A), 'failed-precondition');
    await rejectsWith(call('courierMarkAgroPickupArrived', { courierPhone: A, orderId: 'nope' }, A), 'not-found');
  });

  // ── F5: place* idempotentligi atomik; agro koordinata tekshiruvi ─────────
  await reset();
  await check('F5 placeCarpetWashOrder: parallel bir xil idempotencyKey — BITTA buyurtma, bir xil orderId', async () => {
    const d = { idempotencyKey: 'k-carpet-1', carpetCount: 2, pickupAddress: 'Gurlan, Navoiy 7' };
    const rs = await Promise.all([1, 2, 3, 4, 5].map(() => call('placeCarpetWashOrder', d, CUSTOMER)));
    assert.strictEqual(new Set(rs.map((r) => r.orderId)).size, 1, 'orderId lar har xil');
    const all = await db.collection('carpet_wash_orders').get();
    assert.strictEqual(all.size, 1, `buyurtmalar: ${all.size}`);
    const idem = (await db.collection('wallet_idempotency').doc('carpet_k-carpet-1').get()).data();
    assert.strictEqual(idem.orderId, rs[0].orderId);
  });
  await check('F5 placeAgroPickupOrder: parallel bir xil idempotencyKey — BITTA buyurtma, bir xil orderId', async () => {
    const d = { idempotencyKey: 'k-agro-1', productType: 'milk', literCount: 10, pickupAddress: 'Gurlan, Navoiy 7' };
    const rs = await Promise.all([1, 2, 3, 4, 5].map(() => call('placeAgroPickupOrder', d, CUSTOMER)));
    assert.strictEqual(new Set(rs.map((r) => r.orderId)).size, 1, 'orderId lar har xil');
    const all = await db.collection('agro_pickup_orders').get();
    assert.strictEqual(all.size, 1, `buyurtmalar: ${all.size}`);
  });
  await check('F5: kalitsiz chaqiruvlar alohida buyurtma beradi (cheklov YO\'Q); takror kalit idempotent', async () => {
    const d = { productType: 'milk', literCount: 10, pickupAddress: 'Gurlan, Navoiy 7' };
    const a = await call('placeAgroPickupOrder', d, CUSTOMER);
    const b = await call('placeAgroPickupOrder', d, CUSTOMER);
    assert.notStrictEqual(a.orderId, b.orderId);
    const k = { ...d, idempotencyKey: 'k-agro-2' };
    const r1 = await call('placeAgroPickupOrder', k, CUSTOMER);
    const r2 = await call('placeAgroPickupOrder', k, CUSTOMER);
    assert.strictEqual(r2.orderId, r1.orderId);
    assert.strictEqual(r2.idempotent, true);
  });
  await check('F5 agro: koordinata diapazoni (|lat|<=90, |lng|<=180, chekli) tekshiriladi', async () => {
    const base = { productType: 'milk', literCount: 10, pickupAddress: 'Gurlan, Navoiy 7' };
    for (const bad of [{ pickupLat: 91, pickupLng: 60 }, { pickupLat: 41, pickupLng: 181 },
      { pickupLat: -90.5, pickupLng: 0 }, { pickupLat: 'abc', pickupLng: 60 }, { pickupLat: 41, pickupLng: Infinity }]) {
      await rejectsWith(call('placeAgroPickupOrder', { ...base, ...bad }, CUSTOMER), 'invalid-argument');
    }
    const ok = await call('placeAgroPickupOrder', { ...base, pickupLat: 90, pickupLng: -180 }, CUSTOMER);
    const doc = (await db.collection('agro_pickup_orders').doc(ok.orderId).get()).data();
    assert.strictEqual(doc.pickupLat, 90);
    await call('placeAgroPickupOrder', base, CUSTOMER); // koordinatasiz ham mumkin
  });

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} o'tdi.`);
  process.exit(failed.length ? 1 : 0);
}
main().catch((e) => { console.error('FATAL', e); process.exit(1); });
