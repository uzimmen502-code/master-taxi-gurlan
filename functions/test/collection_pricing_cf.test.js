/**
 * Xarid narxi — FAQAT katalogdan (K-5, ega qarori 2026-10-08).
 * HAQIQIY `functions/index.js` callable'lari `.run()` orqali, Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-collection-pricing \
 *     "node functions/test/collection_pricing_cf.test.js"
 *
 * Qulflanadi:
 *   - `adminCreateCollectionTask`: narx/nom/birlik katalogdan, shu paytda
 *     QOTADI (`priceSource: 'catalog'`); yo'q / nofaol mahsulot — rad
 *   - `courierFinalizeCollection`: kuryer yuborgan narx HISOBGA OLINMAYDI,
 *     vazifadagi qotgan narx; katalog keyin o'zgarsa ham; vazifada yo'q — rad
 *   - `courierSubmitPayment` «mahsulot»: katalogdan YUQORI narx — rad
 *     (pul yaratilmaydi), pastroq — mumkin; katalogda yo'q — rad
 *   - sverka: Σdr == Σcr, ledger == bonusBalance
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-collection-pricing';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

// `COURIER_CF_INDEX` — eski versiyaga qarshi qayta tekshirish (bug isboti).
const fns = require(process.env.COURIER_CF_INDEX || '../index');
const admin = require('firebase-admin');
const settlementLedger = require('../settlement_ledger');

const db = admin.firestore();

const ADMIN = '998909990000';
const A = '998901110001'; // tasdiqlangan kuryer
const CUSTOMER = '998905550005';
const ACC_A = 'accCOURIER0000000000A';

const ctxOf = (phone) => ({ auth: { uid: `uid_${phone}`, token: { phone_number: `+${phone}` } } });
const call = (name, data, phone) => fns[name].run(data, ctxOf(phone));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function expectFail(promise, code, reason) {
  await assert.rejects(promise, (e) => {
    assert.strictEqual(e.code, code, `kod ${e.code}: ${e.message}`);
    if (reason) assert.strictEqual(e.details && e.details.reason, reason, `sabab: ${JSON.stringify(e.details)}`);
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
  await db.collection('users').doc(A).set({ role: 'user', accountId: ACC_A, bonusBalance: 0 });
  await db.collection('provider_capabilities').doc(ACC_A).set({
    identity: { accountId: ACC_A, primaryUid: A }, courier: { active: true }, status: { courier: 'approved' },
  });
  await db.collection('users').doc(CUSTOMER).set({ role: 'user', bonusBalance: 0, name: 'Mijoz' });
  const cat = (code, label, unit, price, active = true) => db.collection('procurement_products').doc(code)
    .set({ code, label, unit, price, active, updatedAt: admin.firestore.Timestamp.now() });
  await cat('milk', 'Sut', 'l', 5000);
  await cat('cheese', 'Pishloq', 'kg', 20000);
  await cat('old', 'Eski', 'kg', 1000, false);
}
async function submission(id) {
  await db.collection('sell_submissions').doc(id).set({
    userPhone: CUSTOMER, userId: CUSTOMER, userName: 'Mijoz', pickupAddress: 'Gurlan', status: 'new',
  });
}
const createTask = (submissionId, items) => call('adminCreateCollectionTask',
  { adminPhone: ADMIN, submissionId, courierPhone: A, items }, ADMIN);
const task = async (id) => (await db.collection('collection_tasks').doc(id).get()).data();
const bonus = async () => (await db.collection('users').doc(CUSTOMER).get()).data().bonusBalance || 0;

async function main() {
  await reset();

  // ── vazifa yaratish: narx katalogdan, shu paytda qotadi ───────────────
  let taskId = '';
  await check('admin «999 999» yuborsa ham vazifaga KATALOG narxi yoziladi', async () => {
    await submission('s1');
    const r = await createTask('s1', [{ code: 'milk', label: 'X', unit: 'X', qty: 10, unitPrice: 999999 }]);
    taskId = r.taskId;
    assert.strictEqual(r.totalValue, 50000);
    const it = (await task(taskId)).items[0];
    assert.strictEqual(it.unitPrice, 5000);
    assert.strictEqual(it.label, 'Sut'); assert.strictEqual(it.unit, 'l');
    assert.strictEqual(it.priceSource, 'catalog');
    assert.ok(it.catalogUpdatedAt, 'katalog versiyasi saqlangan');
  });
  await check('katalogda yo\'q / nofaol mahsulot — vazifa YARATILMAYDI', async () => {
    await submission('s2');
    await expectFail(createTask('s2', [{ code: 'gold', qty: 1, unitPrice: 1 }]), 'failed-precondition', 'PRICE_NOT_IN_CATALOG');
    await expectFail(createTask('s2', [{ code: 'old', qty: 1 }]), 'failed-precondition', 'PRODUCT_INACTIVE');
    const all = await db.collection('collection_tasks').get();
    assert.strictEqual(all.size, 1, 'faqat s1 vazifasi');
  });

  // ── yakunlash: qotgan narx, kuryer narxi hisobga olinmaydi ────────────
  await check('kuryer «1 000 000» yuborsa ham hamyonga VAZIFA narxi bo\'yicha (10 × 5 000)', async () => {
    await db.collection('collection_tasks').doc(taskId).update({ arrivedAt: admin.firestore.Timestamp.now() });
    // Katalog narxi vazifadan KEYIN o'zgardi — yakun eski (qotgan) narxda.
    await db.collection('procurement_products').doc('milk').update({ price: 9000 });
    const r = await call('courierFinalizeCollection', {
      courierPhone: A, taskId, cashGiven: 0,
      items: [{ code: 'milk', label: 'Oltin', unit: 'kg', qty: 10, unitPrice: 1000000 }],
    }, A);
    assert.strictEqual(r.walletCredit, 50000, JSON.stringify(r));
    assert.strictEqual(await bonus(), 50000);
    const t = await task(taskId);
    assert.strictEqual(t.finalItems[0].unitPrice, 5000);
    assert.strictEqual(t.finalItems[0].label, 'Sut');
  });
  await check('vazifada YO\'Q mahsulot — rad (ITEM_NOT_IN_TASK), pul yo\'q', async () => {
    await submission('s3');
    const r = await createTask('s3', [{ code: 'milk', qty: 1 }]);
    await db.collection('collection_tasks').doc(r.taskId).update({ arrivedAt: admin.firestore.Timestamp.now() });
    const before = await bonus();
    await expectFail(call('courierFinalizeCollection', {
      courierPhone: A, taskId: r.taskId, cashGiven: 0,
      items: [{ code: 'cheese', qty: 100, unitPrice: 20000 }],
    }, A), 'failed-precondition', 'ITEM_NOT_IN_TASK');
    assert.strictEqual(await bonus(), before);
  });

  // ── kuryer to'lovi: «mahsulot» qatori ─────────────────────────────────
  const seedOrder = async (id) => {
    await db.collection('orders').doc(id).set({
      type: 'bread', userPhone: CUSTOMER, total: 30000, balanceApplied: 0,
      paymentStatus: 'unpaid', status: 'in_delivery', fulfillmentStatus: 'arrived', courierId: A,
    });
    await db.collection('delivery_routes').doc(`r_${id}`).set({ courierId: A, status: 'active', orders: [id] });
  };
  const submit = (id, lines) => call('courierSubmitPayment', { orderId: id, courierPhone: A, lines }, A);
  await check('to\'lov: mahsulot narxi katalogdan YUQORI — rad, pul yaratilmaydi', async () => {
    await seedOrder('p1');
    const before = await bonus();
    // 10 l × 100 000 = 1 000 000 «mahsulot» → 970 000 qaytim bo'lardi.
    await expectFail(submit('p1', [{ kind: 'product', productCode: 'cheese', qty: 10, unitPrice: 100000, amount: 1000000 }]),
      'failed-precondition', 'PRICE_ABOVE_CATALOG');
    assert.strictEqual(await bonus(), before);
    assert.notStrictEqual((await db.collection('orders').doc('p1').get()).data().paymentStatus, 'paid');
  });
  await check('to\'lov: katalogda yo\'q mahsulot — rad', async () => {
    await expectFail(submit('p1', [{ kind: 'product', productCode: 'gold', qty: 1, unitPrice: 30000, amount: 30000 }]),
      'failed-precondition', 'PRICE_NOT_IN_CATALOG');
  });
  await check('to\'lov: katalog narxi yoki PASTROQ — o\'tadi; nom va tavsiya narxi katalogdan', async () => {
    const r = await submit('p1', [{ kind: 'product', productCode: 'cheese', productLabel: 'X', qty: 1.5, unitPrice: 20000, amount: 30000 }]);
    assert.strictEqual(r.ok, true);
    const lines = (await db.collection('orders').doc('p1').collection('payment_lines').get()).docs.map((d) => d.data());
    assert.strictEqual(lines[0].productLabel, 'Pishloq');
    assert.strictEqual(lines[0].suggestedUnitPrice, 20000);
    await seedOrder('p2');
    const r2 = await submit('p2', [
      { kind: 'product', productCode: 'cheese', qty: 1, unitPrice: 15000, amount: 15000 },
      { kind: 'cash', amount: 15000 },
    ]);
    assert.strictEqual(r2.ok, true);
    assert.strictEqual(r2.changeCredit, 0);
  });
  await check('sverka: Σdr == Σcr, aktiv == passiv, ledger == bonusBalance', async () => {
    const rec = await settlementLedger.reconcile(db);
    assert.strictEqual(rec.balanced, true, `dr ${rec.totalDr} cr ${rec.totalCr}`);
    assert.strictEqual(rec.identityOk, true, `aktiv ${rec.assets} passiv ${rec.liabilities}`);
    assert.strictEqual(rec.projectionOk, true, JSON.stringify(rec.mismatches));
  });

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} o'tdi.`);
  process.exit(failed.length ? 1 : 0);
}
main().catch((e) => { console.error('FATAL', e); process.exit(1); });
