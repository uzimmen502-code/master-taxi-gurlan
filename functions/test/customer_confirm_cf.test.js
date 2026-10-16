/**
 * MIJOZ TASDIG'I ("Oldim" / "Berdim") — D2/D7, ega qarori 2026-10-16.
 * HAQIQIY `functions/index.js` callable'lari `.run()` orqali, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-customer-confirm \
 *     "node functions/test/customer_confirm_cf.test.js"
 *
 * Qulflanadi (4 oqim: restoran / gilam [olish + qaytarish] / agro / yig'ib olish):
 *   - sozlama yo'q yoki noto'g'ri -> eski oqim (kuryer yakunlaydi), hujjatda kutish belgisi YO'Q
 *   - PUBLIC: kuryer chaqiruvi yakunlamaydi (awaitingCustomer), holat va pul O'ZGARMAYDI;
 *     takroriy chaqiruv bir xil javob; mijoz tasdig'i -> eski (gate'siz) oqim bilan AYNAN bir xil
 *     hujjatlar, jurnal yozuvlari va balans o'zgarishi
 *   - begona mijoz / kuryer rad; noto'g'ri qadam NOT_AWAITING; qayta tasdiq idempotent;
 *     parallel tasdiq -> bitta g'olib (pul bir marta)
 *   - holat o'zgarsa tasdiq STATE_CHANGED, belgi o'chadi, pul yo'q
 *   - INTERNAL: faqat testerlar; getCustomerPendingConfirmations ro'yxati va PII yo'qligi
 *   - admin callable: ruxsat (dispatcher rad), tekshiruvlar, audit, idempotent, ommaviy belgi
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-customer-confirm';
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.CUSTOMER_CONFIRM_CACHE_MS = '0'; // keshsiz: sozlama o'zgarishi darhol ko'rinadi
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require('../index');
const admin = require('firebase-admin');
const ledger = require('../settlement_ledger');

const db = admin.firestore();

const ADMIN = '998909990000';
const DISPATCHER = '998909990001';
const A = '998901110001'; // tasdiqlangan kuryer
const B = '998901110002'; // boshqa tasdiqlangan kuryer
const C1 = '998905550005'; // mijoz
const C2 = '998905550006'; // boshqa mijoz
const STRANGER = '998904440004';
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
async function expectReason(promise, reason, httpsCode) {
  await assert.rejects(promise, (e) => {
    const got = (e.details && (e.details.reason || e.details.code)) || e.message;
    assert.strictEqual(got, reason, `sabab ${got} (${e.code}): ${e.message}`);
    if (httpsCode) assert.strictEqual(e.code, httpsCode, `kod ${e.code}`);
    return true;
  });
}
const rejectsCode = (promise, code) => assert.rejects(promise, (e) => {
  assert.strictEqual(e.code, code, `kod ${e.code}: ${e.message}`);
  return true;
});

async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
async function topUp(uid, amount, key) {
  await ledger.postEntry(db, {
    idempotencyKey: `topup:${uid}:${key}`, kind: 'test_topup',
    legs: [{ account: 'admin_clearing', dr: amount }, { account: ledger.passengerCreditAccount(uid), cr: amount }],
  });
}
async function seedCourier(phone) {
  await db.collection('users').doc(phone).set({ role: 'user', accountId: ACC[phone], bonusBalance: 0 });
  await db.collection('provider_capabilities').doc(ACC[phone]).set({
    identity: { accountId: ACC[phone], primaryUid: phone }, courier: { active: true }, status: { courier: 'approved' },
  });
}
async function reset() {
  await clearEmulator();
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(DISPATCHER).set({ role: 'dispatcher' });
  await db.collection('users').doc(STRANGER).set({ role: 'user' });
  await db.collection('users').doc(C1).set({ role: 'user', bonusBalance: 0, name: 'Mijoz Bir', appLang: 'uz_Latn' });
  await db.collection('users').doc(C2).set({ role: 'user', bonusBalance: 0, name: 'Mijoz Ikki', appLang: 'ru' });
  await seedCourier(A);
  await seedCourier(B);
  await db.collection('settings').doc('courier_task_payout').set({
    version: 1, modules: { carpet: { bps: 1500 }, agro: { bps: 1000 }, collection: { bps: 500 } },
  });
  await db.collection('procurement_products').doc('milk').set({
    code: 'milk', label: 'Sut', unit: 'l', price: 5000, active: true, updatedAt: admin.firestore.Timestamp.now(),
  });
}

// ── Sozlama yordamchilari ────────────────────────────────────────────────
const CFG = db.collection('server_config').doc('customer_confirm');
const stages = (over = {}) => ({
  modules: Object.fromEntries(['restaurant', 'carpet', 'agro', 'collection'].map((m) => [m, { stage: over[m] || 'off' }])),
  testerIds: over.testerIds || [],
});
const setAll = (stage, testerIds = []) => CFG.set(stages({
  restaurant: stage, carpet: stage, agro: stage, collection: stage, testerIds,
}));
const cfgOff = () => CFG.delete();

// ── Oqim tavsifi: har oqim uchun bir xil sinov batareyasi ────────────────
let seq = 0;
const uniq = (p) => `${p}${(seq += 1)}`;

const FLOWS = {
  restaurant: {
    label: 'restoran',
    module: 'restaurant', step: 'received', collection: 'orders', done: 'delivered',
    statusField: 'restaurantStatus', phoneField: 'userPhone',
    extraDocs: () => [],
    async seed(id, customer, courier = A) {
      await db.collection('orders').doc(id).set({
        type: 'restaurant', restaurantId: 'rest1', restaurantStatus: 'arrived', status: 'in_delivery',
        fulfillmentStatus: 'arrived', userPhone: customer, courierId: courier, deliveryRouteId: `rt_${id}`,
        deliveryMode: 'ava_courier', deliveryFee: 6000, deliveryPaymentMethod: 'wallet', foodPaymentMethod: 'prepay',
        itemsTotal: 50000, packagingTotal: 0, paymentStatus: 'paid', createdAt: at(1000),
      });
      await db.collection('delivery_routes').doc(`rt_${id}`).set({
        courierId: courier, status: 'active', orders: [id], currentIndex: 0,
      });
      await topUp(customer, 20000, id);
    },
    courier: (id, who = A) => call('courierCompleteRestaurantDelivery', { orderId: id, outcome: 'delivered' }, who),
    cancel: (id) => db.collection('orders').doc(id).update({ restaurantStatus: 'cancelled', status: 'cancelled' }),
  },
  'gilam-olish': {
    label: 'gilam olish',
    module: 'carpet', step: 'handover_pickup', collection: 'carpet_wash_orders', done: 'picked_up',
    statusField: 'status', phoneField: 'customerPhone',
    extraDocs: () => [],
    async seed(id, customer, courier = A) {
      await db.collection('carpet_wash_orders').doc(id).set({
        customerId: customer, customerPhone: customer, carpetCount: 3, priceMode: 'admin', finalPrice: 40000,
        status: 'pickup_in_delivery', pickupCourierId: courier, returnCourierId: '', pickupArrivedAt: at(5000), createdAt: at(1000),
      });
    },
    courier: (id, who = A) => call('courierMarkCarpetPickedUp', { courierPhone: who, orderId: id }, who),
    cancel: (id) => db.collection('carpet_wash_orders').doc(id).update({ status: 'cancelled' }),
  },
  'gilam-qaytarish': {
    label: 'gilam qaytarish',
    module: 'carpet', step: 'handover_return', collection: 'carpet_wash_orders', done: 'completed',
    statusField: 'status', phoneField: 'customerPhone',
    extraDocs: (id) => [`courier_task_payouts/carpet_${id}`],
    async seed(id, customer, courier = A) {
      await db.collection('carpet_wash_orders').doc(id).set({
        customerId: customer, customerPhone: customer, carpetCount: 3, priceMode: 'admin', finalPrice: 40000,
        status: 'return_in_delivery', pickupCourierId: courier, returnCourierId: courier, returnArrivedAt: at(5000), createdAt: at(1000),
      });
    },
    courier: (id, who = A) => call('courierMarkCarpetDelivered', { courierPhone: who, orderId: id }, who),
    cancel: (id) => db.collection('carpet_wash_orders').doc(id).update({ status: 'cancelled' }),
  },
  agro: {
    label: 'agro',
    module: 'agro', step: 'handover_pickup', collection: 'agro_pickup_orders', done: 'picked_up',
    statusField: 'status', phoneField: 'customerPhone',
    extraDocs: (id) => [`courier_task_payouts/agro_${id}`],
    async seed(id, customer, courier = A) {
      await db.collection('agro_pickup_orders').doc(id).set({
        customerId: customer, customerPhone: customer, productType: 'milk', literCount: 20, priceMode: 'admin', finalPrice: 30000,
        status: 'pickup_in_delivery', pickupCourierId: courier, arrivedAt: at(5000), createdAt: at(1000),
      });
    },
    courier: (id, who = A) => call('courierMarkAgroPickedUp', { courierPhone: who, orderId: id }, who),
    cancel: (id) => db.collection('agro_pickup_orders').doc(id).update({ status: 'cancelled' }),
  },
  yigish: {
    label: 'yig\'ib olish',
    module: 'collection', step: 'finalize', collection: 'collection_tasks', done: 'completed',
    statusField: 'status', phoneField: 'customerPhone',
    extraDocs: (id) => [`courier_task_payouts/collection_${id}`, 'warehouse_stock/milk'],
    async seed(id, customer, courier = A) {
      await db.collection('sell_submissions').doc(`s_${id}`).set({ userPhone: customer, userId: customer, status: 'reviewed' });
      await db.collection('collection_tasks').doc(id).set({
        submissionId: `s_${id}`, customerPhone: customer, customerUid: customer, customerName: 'Mijoz', pickupAddress: 'Gurlan',
        items: [{ code: 'milk', label: 'Sut', unit: 'l', qty: 10, unitPrice: 5000, lineTotal: 50000, priceSource: 'catalog' }],
        totalValue: 50000, courierId: courier, status: 'collecting', arrivedAt: at(5000), createdAt: at(1000),
      });
    },
    courier: (id, who = A, over = {}) => call('courierFinalizeCollection', {
      courierPhone: who, taskId: id, cashGiven: 20000, items: [{ code: 'milk', qty: 10 }], ...over,
    }, who),
    cancel: (id) => db.collection('collection_tasks').doc(id).update({ status: 'cancelled' }),
  },
};

// ── Ta'sirlar: gate'siz oqim bilan taqqoslash uchun ──────────────────────
const VOLATILE_DOC_KEYS = ['awaitingCustomerConfirm', 'hasAwaitingCustomerConfirm', 'customerConfirmed'];
function plain(v) {
  if (v && typeof v.toMillis === 'function') return '<ts>';
  if (Array.isArray(v)) return v.map(plain);
  if (v && typeof v === 'object') return Object.fromEntries(Object.keys(v).sort().map((k) => [k, plain(v[k])]));
  return v;
}
async function snapState(flow, id, customer) {
  const accts = {};
  for (const acc of [customer, A]) {
    const u = await db.collection('users').doc(acc).get();
    const pc = await db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(acc)).get();
    accts[acc] = { bonus: Number((u.data() || {}).bonusBalance || 0), pc: pc.exists ? Number(pc.data().balance || 0) : 0 };
  }
  const journal = new Set((await db.collection(ledger.COL_JOURNAL).get()).docs.map((d) => d.id));
  const stock = await db.collection('warehouse_stock').doc('milk').get();
  const wlIds = new Set((await db.collection('users').doc(customer).collection('wallet_ledger').get()).docs.map((d) => d.id));
  return { accts, journal, stock: stock.exists ? Number(stock.data().quantity || 0) : 0, wlIds };
}
async function effects(flow, id, customer, before) {
  const after = await snapState(flow, id, customer);
  const dAcct = {};
  for (const k of Object.keys(after.accts)) {
    const role = k === customer ? 'CUST' : 'COUR';
    dAcct[role] = { bonus: after.accts[k].bonus - before.accts[k].bonus, pc: after.accts[k].pc - before.accts[k].pc };
  }
  const newJ = [];
  for (const jid of after.journal) {
    if (before.journal.has(jid)) continue;
    const d = (await db.collection(ledger.COL_JOURNAL).doc(jid).get()).data() || {};
    newJ.push({ kind: d.kind, amount: d.amount, refType: d.refType, legs: d.legs, meta: d.meta, postedRole: d.postedRole });
  }
  newJ.sort((a, b) => String(a.kind).localeCompare(String(b.kind)));
  const wlDocs = (await db.collection('users').doc(customer).collection('wallet_ledger').get()).docs
    .filter((d) => !before.wlIds.has(d.id))
    .map((d) => { const x = d.data(); return { type: x.type, amount: x.amount, module: x.module, refType: x.refType, meta: x.meta }; })
    .sort((a, b) => String(a.type).localeCompare(String(b.type)));
  const doc = (await db.collection(flow.collection).doc(id).get()).data() || {};
  for (const k of VOLATILE_DOC_KEYS) delete doc[k];
  const extra = {};
  for (const p of flow.extraDocs(id)) {
    const s = await db.doc(p).get();
    const x = s.exists ? s.data() : null;
    extra[p.replace(id, 'ID')] = x && p.startsWith('warehouse_stock') ? { quantity: x.quantity - before.stock } : x;
  }
  const blob = JSON.stringify(plain({ doc, extra, dAcct, newJ, wlDocs, stockDelta: after.stock - before.stock }));
  return blob.split(id).join('ID').split(customer).join('CUST').split(A).join('COUR');
}
async function journalBalanced() {
  const s = await db.collection(ledger.COL_JOURNAL).get();
  for (const d of s.docs) {
    const legs = d.data().legs || [];
    const dr = legs.reduce((a, l) => a + (l.dr || 0), 0);
    const cr = legs.reduce((a, l) => a + (l.cr || 0), 0);
    assert.strictEqual(dr, cr, `journal ${d.id} Σdr ${dr} != Σcr ${cr}`);
  }
  return s.size;
}
const docOf = async (flow, id) => (await db.collection(flow.collection).doc(id).get()).data() || {};
const newsFor = async (uid) => (await db.collection('admin_news').where('targetUserId', '==', uid).where('source', '==', 'customer_confirm').get()).docs.map((d) => d.data());
const confirm = (flow, id, who, step) => call('customerConfirmHandover', { module: flow.module, id, step: step || flow.step }, who);

async function main() {
  await reset();

  // ═════════════ 1. Admin callable'lari va sozlama ═════════════════════
  await check('A1 ruxsat: dispatcher / oddiy foydalanuvchi / kirmagan rad; admin ruxsat', async () => {
    for (const who of [DISPATCHER, STRANGER, C1]) {
      await rejectsCode(call('adminSetCustomerConfirmation', { module: 'carpet', stage: 'public', reason: 'sinov' }, who), 'permission-denied');
      await rejectsCode(call('adminGetCustomerConfirmation', {}, who), 'permission-denied');
    }
    await rejectsCode(fns.adminGetCustomerConfirmation.run({}, {}), 'unauthenticated');
    const g = await call('adminGetCustomerConfirmation', {}, ADMIN);
    assert.deepStrictEqual(
      { ok: g.ok, v: g.version, m: g.modules, n: g.testerCount, e: g.enabled },
      { ok: true, v: 0, m: { restaurant: 'off', carpet: 'off', agro: 'off', collection: 'off' }, n: 0, e: false },
    );
  });
  await check('A2 tekshiruvlar: modul / bosqich / tester / sabab xatolari, hech narsa yozilmaydi', async () => {
    const set = (d) => call('adminSetCustomerConfirmation', { reason: 'sinov', ...d }, ADMIN);
    await expectReason(set({ module: 'bread', stage: 'public' }), 'CC_MODULE_INVALID', 'invalid-argument');
    await expectReason(set({ module: 'carpet', stage: 'PUBLIC' }), 'CC_STAGE_INVALID', 'invalid-argument');
    await expectReason(set({ stage: 'public' }), 'CC_MODULE_REQUIRED', 'invalid-argument');
    await expectReason(set({ module: 'carpet', addTesterIds: ['abc'] }), 'CC_TESTER_INVALID', 'invalid-argument');
    await expectReason(set({ module: 'carpet', addTesterIds: ['12345'] }), 'CC_TESTER_INVALID', 'invalid-argument');
    await expectReason(set({ module: 'carpet', addTesterIds: 'x' }), 'CC_TESTER_INVALID', 'invalid-argument');
    await expectReason(set({ module: 'carpet', addTesterIds: [C1], removeTesterIds: [C1] }), 'CC_TESTER_CONFLICT', 'invalid-argument');
    await expectReason(set({ module: 'carpet' }), 'CC_NOTHING_TO_CHANGE', 'invalid-argument');
    await expectReason(call('adminSetCustomerConfirmation', { module: 'carpet', stage: 'public' }, ADMIN), 'CC_REASON_REQUIRED', 'invalid-argument');
    assert.strictEqual((await CFG.get()).exists, false, 'rad etilganlar hech narsa yozmadi');
    assert.strictEqual((await db.doc('module_config/customer_confirm').get()).exists, false);
    assert.strictEqual((await db.collection('admin_audit').where('kind', '==', 'customer_confirm_config').get()).size, 0);
  });
  await check('A3 set: bosqich + testerlar -> hujjat, versiya, ommaviy belgi, audit (telefon maskalangan)', async () => {
    const r = await call('adminSetCustomerConfirmation', {
      module: 'carpet', stage: 'internal', addTesterIds: [`+${C1}`, C1.slice(3), C2], reason: 'ichki sinov',
    }, ADMIN);
    assert.deepStrictEqual({ u: r.unchanged, v: r.version, n: r.testerCount, e: r.enabled }, { u: false, v: 1, n: 2, e: true });
    const d = (await CFG.get()).data();
    assert.strictEqual(d.modules.carpet.stage, 'internal');
    assert.strictEqual(d.modules.restaurant.stage, 'off');
    assert.deepStrictEqual(d.testerIds, [C1, C2].sort(), 'kanonik, takrorsiz, tartiblangan');
    assert.strictEqual(d.updatedBy, ADMIN);
    const mk = (await db.doc('module_config/customer_confirm').get()).data();
    assert.strictEqual(mk.enabled, true);
    const audit = await db.collection('admin_audit').where('kind', '==', 'customer_confirm_config').get();
    assert.strictEqual(audit.size, 1);
    const a = audit.docs[0].data();
    assert.strictEqual(a.actor, ADMIN);
    assert.strictEqual(a.detail.stagePrev, 'off');
    assert.strictEqual(a.detail.stageNew, 'internal');
    assert.strictEqual(a.detail.testersAdded, 2);
    assert.ok(!JSON.stringify(a).includes(C1), 'auditda to\'liq telefon YO\'Q');
    assert.ok(a.detail.addedMasked.every((x) => /^\*\*\*\d{4}$/.test(x)));
  });
  await check('A4 idempotent: bir xil qiymat qayta -> unchanged, versiya va audit ortmaydi', async () => {
    const r = await call('adminSetCustomerConfirmation', { module: 'carpet', stage: 'internal', addTesterIds: [C1], reason: 'takror' }, ADMIN);
    assert.deepStrictEqual({ u: r.unchanged, v: r.version }, { u: true, v: 1 });
    assert.strictEqual((await db.collection('admin_audit').where('kind', '==', 'customer_confirm_config').get()).size, 1);
  });
  await check('A5 testerni olib tashlash va get: telefonlar maskalangan, soni to\'g\'ri', async () => {
    const r = await call('adminSetCustomerConfirmation', { module: 'carpet', removeTesterIds: [C2], reason: 'chiqardik' }, ADMIN);
    assert.deepStrictEqual({ u: r.unchanged, v: r.version, n: r.testerCount }, { u: false, v: 2, n: 1 });
    const g = await call('adminGetCustomerConfirmation', {}, ADMIN);
    assert.strictEqual(g.modules.carpet, 'internal');
    assert.strictEqual(g.testerCount, 1);
    assert.ok(!JSON.stringify(g).includes(C1), 'get\'da to\'liq telefon YO\'Q');
    assert.deepStrictEqual(g.testersMasked, [`***${C1.slice(-4)}`]);
  });
  await check('A6 hammasi off -> ommaviy belgi enabled=false; belgi sinxrondan chiqsa keyingi chaqiruv tuzatadi', async () => {
    await call('adminSetCustomerConfirmation', { module: 'carpet', stage: 'off', reason: 'o\'chirdik' }, ADMIN);
    assert.strictEqual((await db.doc('module_config/customer_confirm').get()).data().enabled, false);
    await db.doc('module_config/customer_confirm').delete();
    const r = await call('adminSetCustomerConfirmation', { module: 'carpet', stage: 'off', reason: 'tuzatish' }, ADMIN);
    assert.deepStrictEqual({ u: r.unchanged, fixed: (await db.doc('module_config/customer_confirm').get()).data().enabled }, { u: true, fixed: false });
  });

  // ═════════════ 2. Oqim batareyasi (har oqim uchun) ═══════════════════
  const baseline = {}; // gate'siz oqim ta'siri (taqqoslash uchun)
  for (const [key, flow] of Object.entries(FLOWS)) {
    const L = flow.label;
    await check(`${L}: sozlama YO'Q -> eski oqim (yakunlanadi), kutish belgisi yo'q; ta'sir yozib olindi`, async () => {
      await cfgOff();
      const id = uniq(`${key}_off_`);
      await flow.seed(id, C1);
      const before = await snapState(flow, id, C1);
      const news0 = (await newsFor(C1)).length;
      const r = await flow.courier(id);
      assert.ok(!r.awaitingCustomer, `awaitingCustomer bo'lmasligi kerak: ${JSON.stringify(r)}`);
      const d = await docOf(flow, id);
      assert.strictEqual(d[flow.statusField], flow.done);
      assert.ok(!('awaitingCustomerConfirm' in d) && !('hasAwaitingCustomerConfirm' in d) && !('customerConfirmed' in d));
      baseline[key] = await effects(flow, id, C1, before);
      assert.strictEqual((await newsFor(C1)).length, news0, 'tasdiq push\'i yo\'q');
    });
    await check(`${L}: noto'g'ri sozlama qiymatlari -> off (eski oqim)`, async () => {
      const bad = [
        { modules: { [flow.module]: { stage: 'PUBLIC' } } },
        { modules: { [flow.module]: { stage: 1 } } },
        { modules: { [flow.module]: 'public' } },
        { modules: [] },
        { modules: { [flow.module]: { stage: 'internal' } }, testerIds: 'notalist' },
        'garbage',
      ];
      for (const cfg of bad) {
        await CFG.set(typeof cfg === 'string' ? { raw: cfg } : cfg);
        const id = uniq(`${key}_bad_`);
        await flow.seed(id, C1);
        const r = await flow.courier(id);
        assert.ok(!r.awaitingCustomer, `noto'g'ri sozlama ${JSON.stringify(cfg)} yoqmasligi kerak`);
        assert.strictEqual((await docOf(flow, id))[flow.statusField], flow.done);
      }
    });

    let id1;
    let before1;
    let news0;
    await check(`${L}: PUBLIC — kuryer chaqiruvi yakunlamaydi (awaitingCustomer), holat/pul o'zgarmaydi, belgi va push yozildi`, async () => {
      await setAll('public');
      id1 = uniq(`${key}_on_`);
      await flow.seed(id1, C1);
      before1 = await snapState(flow, id1, C1);
      news0 = (await newsFor(C1)).length;
      const jBefore = await journalBalanced();
      const r = await flow.courier(id1);
      assert.deepStrictEqual(r, { ok: true, awaitingCustomer: true, step: flow.step });
      const d = await docOf(flow, id1);
      assert.notStrictEqual(d[flow.statusField], flow.done, 'holat O\'ZGARMAGAN');
      const m = d.awaitingCustomerConfirm;
      assert.strictEqual(m.step, flow.step);
      assert.strictEqual(m.courierId, A);
      assert.ok(m.requestedAt && typeof m.requestedAt.toMillis === 'function', 'requestedAt — server vaqti');
      assert.strictEqual(d.hasAwaitingCustomerConfirm, true);
      assert.strictEqual(await journalBalanced(), jBefore, 'jurnal yozuvi YO\'Q');
      const after = await snapState(flow, id1, C1);
      assert.deepStrictEqual(after.accts, before1.accts, 'balanslar o\'zgarmadi');
      assert.strictEqual(after.stock, before1.stock, 'ombor o\'zgarmadi');
      assert.strictEqual((await db.doc(`courier_task_payouts/${flow.module}_${id1}`).get()).exists, false, 'kuryer haqi yozilmadi');
      const news = await newsFor(C1);
      assert.strictEqual(news.length, news0 + 1, 'mijozga bitta push/xabar');
      const last = news[news.length - 1];
      assert.ok(last.title && last.body);
      assert.ok(!/LEG|ZONE|settlement|zona/i.test(`${last.title} ${last.body}`), 'ichki atamalar yo\'q');
    });
    await check(`${L}: kuryer takroriy chaqiruvi — bir xil javob, belgi o'zgarmaydi, push takrorlanmaydi`, async () => {
      const m0 = (await docOf(flow, id1)).awaitingCustomerConfirm.requestedAt.toMillis();
      const r = await flow.courier(id1);
      assert.deepStrictEqual(r, { ok: true, awaitingCustomer: true, step: flow.step });
      const d = await docOf(flow, id1);
      assert.strictEqual(d.awaitingCustomerConfirm.requestedAt.toMillis(), m0);
      assert.notStrictEqual(d[flow.statusField], flow.done);
      assert.strictEqual((await newsFor(C1)).length, news0 + 1, 'ikkinchi push yo\'q');
    });
    await check(`${L}: begona kuryer baribir rad; begona mijoz va kuryer tasdiqlay olmaydi (NOT_YOUR_ORDER)`, async () => {
      await rejectsCode(flow.courier(id1, B), 'permission-denied');
      for (const who of [C2, STRANGER, A, B]) {
        await expectReason(confirm(flow, id1, who), 'NOT_YOUR_ORDER', 'permission-denied');
      }
      assert.notStrictEqual((await docOf(flow, id1))[flow.statusField], flow.done);
      await expectReason(confirm(flow, 'yoq-id', C1), 'NOT_YOUR_ORDER');
      await expectReason(call('customerConfirmHandover', { module: flow.module, id: id1, step: 'nope' }, C1), 'CONFIRM_ARGS_INVALID', 'invalid-argument');
      await expectReason(call('customerConfirmHandover', { module: 'bread', id: id1, step: flow.step }, C1), 'CONFIRM_ARGS_INVALID', 'invalid-argument');
      await rejectsCode(fns.customerConfirmHandover.run({ module: flow.module, id: id1, step: flow.step }, {}), 'unauthenticated');
    });
    await check(`${L}: mijoz tasdig'i -> gate'siz oqim bilan AYNAN bir xil hujjat, jurnal va balans; belgi o'chdi`, async () => {
      const jBefore = await journalBalanced();
      const r = await confirm(flow, id1, C1);
      assert.strictEqual(r.ok, true);
      assert.strictEqual(r.status, flow.done);
      assert.ok(!r.idempotent);
      const d = await docOf(flow, id1);
      assert.strictEqual(d[flow.statusField], flow.done);
      assert.ok(!('awaitingCustomerConfirm' in d) && !('hasAwaitingCustomerConfirm' in d), 'belgi o\'chdi');
      assert.strictEqual(d.customerConfirmed[flow.step].courierId, A);
      assert.ok(d.customerConfirmed[flow.step].at.toMillis() > 0);
      const eff = await effects(flow, id1, C1, before1);
      assert.strictEqual(eff, baseline[key], 'gate\'siz oqim bilan bir xil natija');
      await journalBalanced();
      assert.ok(jBefore >= 0);
    });
    await check(`${L}: qayta tasdiq idempotent (pul ikki marta o'tmaydi); kuryerning keyingi chaqiruvi hech narsani o'zgartirmaydi`, async () => {
      const before = await snapState(flow, id1, C1);
      const r = await confirm(flow, id1, C1);
      assert.deepStrictEqual({ ok: r.ok, idem: r.idempotent, st: r.status }, { ok: true, idem: true, st: flow.done });
      const after = await snapState(flow, id1, C1);
      assert.deepStrictEqual(after.accts, before.accts);
      assert.strictEqual(after.journal.size, before.journal.size);
      assert.strictEqual(after.stock, before.stock);
      await flow.courier(id1).catch(() => null); // yakunlangan: javob oqimga bog'liq (idempotent yoki rad)
      const again = await snapState(flow, id1, C1);
      assert.deepStrictEqual(again.accts, before.accts);
      assert.strictEqual(again.journal.size, before.journal.size);
      assert.strictEqual(again.stock, before.stock);
    });
    await check(`${L}: noto'g'ri qadam yoki kutilmayotgan hujjat -> NOT_AWAITING`, async () => {
      const id = uniq(`${key}_na_`);
      await flow.seed(id, C1);
      await expectReason(confirm(flow, id, C1), 'NOT_AWAITING', 'failed-precondition');
      await flow.courier(id);
      const other = flow.module === 'carpet' ? (flow.step === 'handover_pickup' ? 'handover_return' : 'handover_pickup') : null;
      if (other) await expectReason(confirm(flow, id, C1, other), 'NOT_AWAITING', 'failed-precondition');
      assert.ok((await docOf(flow, id)).awaitingCustomerConfirm, 'belgi saqlanib qoldi');
    });
    await check(`${L}: parallel ikki tasdiq -> bitta g'olib, pul BIR marta`, async () => {
      await setAll('public');
      const id = uniq(`${key}_par_`);
      await flow.seed(id, C1);
      await flow.courier(id);
      const before = await snapState(flow, id, C1);
      const rs = await Promise.allSettled([confirm(flow, id, C1), confirm(flow, id, C1)]);
      const ok = rs.filter((x) => x.status === 'fulfilled');
      assert.strictEqual(ok.length, 2, `ikkalasi ham xatosiz tugashi kerak: ${JSON.stringify(rs.map((x) => x.status === 'rejected' ? x.reason.message : 'ok'))}`);
      const winners = ok.filter((x) => !x.value.idempotent);
      assert.strictEqual(winners.length, 1, 'aynan bitta g\'olib');
      assert.strictEqual((await docOf(flow, id))[flow.statusField], flow.done);
      // Gate'siz oqim bilan bir xil ta'sir (jurnal yozuvlari va balans bir marta)
      assert.strictEqual(await effects(flow, id, C1, before), baseline[key]);
      await journalBalanced();
    });
    await check(`${L}: holat o'zgardi (bekor) -> STATE_CHANGED, belgi o'chadi, pul yo'q`, async () => {
      const id = uniq(`${key}_sc_`);
      await flow.seed(id, C1);
      await flow.courier(id);
      const before = await snapState(flow, id, C1);
      await flow.cancel(id);
      await expectReason(confirm(flow, id, C1), 'STATE_CHANGED', 'failed-precondition');
      const d = await docOf(flow, id);
      assert.ok(!('awaitingCustomerConfirm' in d) && !('hasAwaitingCustomerConfirm' in d), 'belgi tozalandi');
      assert.ok(!('customerConfirmed' in d));
      const after = await snapState(flow, id, C1);
      assert.deepStrictEqual(after.accts, before.accts);
      assert.strictEqual(after.journal.size, before.journal.size);
      // belgi yo'q: qayta tasdiq endi NOT_AWAITING
      await expectReason(confirm(flow, id, C1), 'NOT_AWAITING');
    });
    await check(`${L}: INTERNAL — faqat testerlar uchun yoqiladi (boshqa mijoz eski oqim)`, async () => {
      await CFG.set(stages({ [flow.module]: 'internal', testerIds: [C1] }));
      const idT = uniq(`${key}_tst_`);
      const idN = uniq(`${key}_non_`);
      await flow.seed(idT, C1);
      await flow.seed(idN, C2);
      const rT = await flow.courier(idT);
      assert.strictEqual(rT.awaitingCustomer, true, 'tester gate\'langan');
      const rN = await flow.courier(idN);
      assert.ok(!rN.awaitingCustomer, 'tester emas — eski oqim');
      assert.strictEqual((await docOf(flow, idN))[flow.statusField], flow.done);
      // 9 xonali yozilgan tester ham taniladi
      await CFG.set(stages({ [flow.module]: 'internal', testerIds: [C1.slice(3)] }));
      const id9 = uniq(`${key}_t9_`);
      await flow.seed(id9, C1);
      assert.strictEqual((await flow.courier(id9)).awaitingCustomer, true);
      await setAll('off');
    });
  }

  // ═════════════ 3. Yig'ib olish: qo'shimcha pul xavfsizligi ════════════
  const Y = FLOWS.yigish;
  await check('yig\'ib olish: kutish paytida boshqa son/naqd kiritilsa rad (saqlangan raqamlar o\'zgarmaydi); xuddi shu raqamlar — bir xil javob', async () => {
    await setAll('public');
    const id = uniq('y_diff_');
    await Y.seed(id, C1);
    await Y.courier(id);
    const m0 = (await docOf(Y, id)).awaitingCustomerConfirm;
    await expectReason(Y.courier(id, A, { items: [{ code: 'milk', qty: 99 }] }), 'AWAITING_OTHER_INPUT', 'failed-precondition');
    await expectReason(Y.courier(id, A, { cashGiven: 1 }), 'AWAITING_OTHER_INPUT', 'failed-precondition');
    const same = await Y.courier(id);
    assert.deepStrictEqual(same, { ok: true, awaitingCustomer: true, step: 'finalize' });
    const m1 = (await docOf(Y, id)).awaitingCustomerConfirm;
    assert.deepStrictEqual([m1.cashGiven, m1.items, m1.requestedAt.toMillis()], [m0.cashGiven, m0.items, m0.requestedAt.toMillis()]);
    assert.deepStrictEqual(m1.items, [{ code: 'milk', qty: 10 }]);
  });
  await check('yig\'ib olish: kuryer kiritishi eski tekshiruvlardan o\'tmasa belgi YOZILMAYDI (vazifada yo\'q mahsulot, juda katta naqd)', async () => {
    const id = uniq('y_val_');
    await Y.seed(id, C1);
    await expectReason(Y.courier(id, A, { items: [{ code: 'cheese', qty: 1 }] }), 'ITEM_NOT_IN_TASK', 'failed-precondition');
    await assert.rejects(Y.courier(id, A, { cashGiven: 999999999 }), (e) => e.code === 'failed-precondition' && /cash_exceeds_balance/.test(e.message));
    await assert.rejects(Y.courier(id, A, { items: [] }), (e) => e.code === 'invalid-argument');
    const d = await docOf(Y, id);
    assert.ok(!('awaitingCustomerConfirm' in d), 'belgi yozilmadi');
    assert.strictEqual(d.status, 'collecting');
  });
  await check('yig\'ib olish: mijoz hamyoni tasdiqdan oldin kamaysa (naqd > V + balans) -> STATE_CHANGED, belgi o\'chadi, pul yo\'q', async () => {
    const id = uniq('y_bal_');
    await Y.seed(id, C1);
    await db.collection('users').doc(C1).update({ bonusBalance: 100000 });
    // naqd 130 000 > V (50 000) + balans (100 000)? yo'q: 150 000 gacha ruxsat. 140 000 kiritamiz.
    await Y.courier(id, A, { cashGiven: 140000 });
    await db.collection('users').doc(C1).update({ bonusBalance: 0 }); // balans yo'qoldi
    const before = await snapState(Y, id, C1);
    await expectReason(confirm(Y, id, C1), 'STATE_CHANGED', 'failed-precondition');
    const d = await docOf(Y, id);
    assert.ok(!('awaitingCustomerConfirm' in d));
    assert.strictEqual(d.status, 'collecting');
    const after = await snapState(Y, id, C1);
    assert.deepStrictEqual(after.accts, before.accts);
    await db.collection('users').doc(C1).update({ bonusBalance: 0 });
  });
  await check('yig\'ib olish: ro\'yxatdagi tafsilot (miqdor/birlik/summa) serverda hisoblangan, mijoz yuborgan summa YO\'Q', async () => {
    const id = uniq('y_det_');
    await Y.seed(id, C1);
    await Y.courier(id, A, { cashGiven: 0 });
    const r = await call('getCustomerPendingConfirmations', {}, C1);
    const it = r.items.find((x) => x.id === id);
    assert.ok(it, 'ro\'yxatda bor');
    assert.deepStrictEqual(
      { m: it.module, s: it.step, q: it.details.qty, u: it.details.unit, a: it.details.amount, p: it.details.productLabel, c: it.details.cashGiven },
      { m: 'collection', s: 'finalize', q: 10, u: 'l', a: 50000, p: 'Sut', c: 0 },
    );
    assert.ok(Number.isInteger(it.details.amount));
    await call('customerConfirmHandover', { module: 'collection', id, step: 'finalize' }, C1);
  });

  // ═════════════ 4. getCustomerPendingConfirmations ═════════════════════
  await check('ro\'yxat: o\'z elementlari, eng eskisi birinchi, uch modul; boshqa mijoz ko\'rmaydi; PII yo\'q; tasdiqdan keyin tozalanadi', async () => {
    await setAll('public');
    const idR = uniq('l_r_');
    const idC = uniq('l_c_');
    const idA = uniq('l_a_');
    const idOther = uniq('l_o_');
    await FLOWS.restaurant.seed(idR, C1);
    await FLOWS['gilam-qaytarish'].seed(idC, C1);
    await FLOWS.agro.seed(idA, C1);
    await FLOWS.agro.seed(idOther, C2);
    await FLOWS.restaurant.courier(idR);
    await new Promise((r) => setTimeout(r, 15));
    await FLOWS['gilam-qaytarish'].courier(idC);
    await new Promise((r) => setTimeout(r, 15));
    await FLOWS.agro.courier(idA);
    await FLOWS.agro.courier(idOther);
    const r1 = await call('getCustomerPendingConfirmations', {}, C1);
    assert.strictEqual(r1.ok, true);
    const mine = r1.items.filter((x) => [idR, idC, idA].includes(x.id));
    assert.deepStrictEqual(mine.map((x) => `${x.module}:${x.step}`), ['restaurant:received', 'carpet:handover_return', 'agro:handover_pickup']);
    assert.ok(mine.every((x) => x.title && x.summary && x.requestedAtMs > 0));
    assert.ok(mine.every((x, i) => i === 0 || mine[i - 1].requestedAtMs <= x.requestedAtMs), 'eng eskisi birinchi');
    const text = JSON.stringify(r1);
    for (const secret of [A, B, C2, idOther, 'uid_', 'courierId']) assert.ok(!text.includes(secret), `PII/begona ma'lumot oqdi: ${secret}`);
    assert.ok(!/LEG|ZONE|settlement|zona/i.test(text), 'ichki atamalar yo\'q');
    const r2 = await call('getCustomerPendingConfirmations', {}, C2);
    assert.deepStrictEqual(r2.items.map((x) => x.id), [idOther]);
    assert.deepStrictEqual((await call('getCustomerPendingConfirmations', {}, STRANGER)).items, []);
    await call('customerConfirmHandover', { module: 'agro', id: idA, step: 'handover_pickup' }, C1);
    const r3 = await call('getCustomerPendingConfirmations', {}, C1);
    assert.ok(!r3.items.find((x) => x.id === idA), 'tasdiqlangan ro\'yxatdan chiqdi');
    assert.ok(r3.items.find((x) => x.id === idR), 'qolganlari turibdi');
    await rejectsCode(fns.getCustomerPendingConfirmations.run({}, {}), 'unauthenticated');
  });
  await check('ro\'yxat: sozlama off yoki INTERNAL (tester emas) bo\'lsa — bo\'sh; matn mijoz tilida (ru)', async () => {
    await setAll('off');
    assert.deepStrictEqual((await call('getCustomerPendingConfirmations', {}, C1)).items, []);
    await CFG.set(stages({ restaurant: 'internal', carpet: 'internal', agro: 'internal', collection: 'internal', testerIds: [C1] }));
    assert.ok((await call('getCustomerPendingConfirmations', {}, C1)).items.length >= 1, 'tester ko\'radi');
    assert.deepStrictEqual((await call('getCustomerPendingConfirmations', {}, C2)).items, [], 'tester emas');
    await setAll('public');
    const id = uniq('l_ru_');
    await FLOWS.agro.seed(id, C2);
    await FLOWS.agro.courier(id);
    const it = (await call('getCustomerPendingConfirmations', {}, C2)).items.find((x) => x.id === id);
    assert.ok(/[а-яА-Я]/.test(it.title) && !/[ўқғҳ]/.test(it.title), `ru matn kutilgan: ${it.title}`);
  });

  // ═════════════ 5. Kuryer chetlab o'tolmaydi / restoran 'failed' ochiq ══
  await check('restoran: kutish paytida kuryer \'failed\' desa o\'tadi (gate\'lanmaydi) va belgi tozalanadi; mijoz tasdig\'i NOT_AWAITING', async () => {
    await setAll('public');
    const id = uniq('r_fail_');
    await FLOWS.restaurant.seed(id, C1);
    await FLOWS.restaurant.courier(id);
    const r = await call('courierCompleteRestaurantDelivery', { orderId: id, outcome: 'failed', failReason: 'customer_absent' }, A);
    assert.strictEqual(r.outcome, 'failed');
    const d = await docOf(FLOWS.restaurant, id);
    assert.strictEqual(d.restaurantStatus, 'delivery_failed');
    assert.ok(!('awaitingCustomerConfirm' in d) && !('hasAwaitingCustomerConfirm' in d));
    await expectReason(confirm(FLOWS.restaurant, id, C1), 'NOT_AWAITING');
  });
  await check('sozlama o\'chirilsa (off) kutayotgan vazifani kuryer qayta chaqirib yakunlaydi va belgi tozalanadi (kill-switch)', async () => {
    await setAll('public');
    const id = uniq('k_kill_');
    await FLOWS['gilam-olish'].seed(id, C1);
    await FLOWS['gilam-olish'].courier(id);
    assert.ok((await docOf(FLOWS['gilam-olish'], id)).awaitingCustomerConfirm);
    await setAll('off');
    const r = await FLOWS['gilam-olish'].courier(id);
    assert.ok(!r.awaitingCustomer);
    const d = await docOf(FLOWS['gilam-olish'], id);
    assert.strictEqual(d.status, 'picked_up');
    assert.ok(!('awaitingCustomerConfirm' in d) && !('hasAwaitingCustomerConfirm' in d));
  });
  await check('admin gilam holatini o\'zgartirsa (bekor) kutish belgisi ham tozalanadi', async () => {
    await setAll('public');
    const id = uniq('k_adm_');
    await FLOWS['gilam-olish'].seed(id, C1);
    await FLOWS['gilam-olish'].courier(id);
    await call('adminSetCarpetWashStatus', { adminPhone: ADMIN, orderId: id, status: 'pickup_ready', reason: 'kuryer yo\'q' }, ADMIN);
    const d = await docOf(FLOWS['gilam-olish'], id);
    assert.strictEqual(d.status, 'pickup_ready');
    assert.ok(!('awaitingCustomerConfirm' in d) && !('hasAwaitingCustomerConfirm' in d), 'release belgini tozaladi');
    const id2 = uniq('k_adm2_');
    await FLOWS.agro.seed(id2, C1);
    await FLOWS.agro.courier(id2);
    await call('adminSetAgroPickupStatus', { adminPhone: ADMIN, orderId: id2, status: 'accepted', reason: 'kuryer yo\'q' }, ADMIN);
    const d2 = await docOf(FLOWS.agro, id2);
    assert.strictEqual(d2.status, 'accepted');
    assert.ok(!('awaitingCustomerConfirm' in d2) && !('hasAwaitingCustomerConfirm' in d2));
    await setAll('off');
  });

  await check('admin «qotib qolgan vazifalar» ro\'yxatida tasdiq kutilayotgan vazifa belgilanadi (awaitingCustomerStep); belgisizda maydon yo\'q; yosh belgi yozilgach tiklanmaydi', async () => {
    await setAll('public');
    const f = FLOWS['gilam-olish'];
    const id = uniq('k_stale_');
    await f.seed(id, C1);
    await db.collection('carpet_wash_orders').doc(id).update({ updatedAt: at(2000) });
    await f.courier(id);
    assert.strictEqual((await docOf(f, id)).updatedAt.toMillis(), 2000, 'belgi yozilganda updatedAt O\'ZGARMADI');
    const id2 = uniq('k_stale2_');
    await f.seed(id2, C1);
    const r = await call('adminListStaleTasks', { hours: 1 }, ADMIN);
    const by = Object.fromEntries(r.modules.carpet.items.map((i) => [i.id, i]));
    assert.strictEqual(by[id].awaitingCustomerStep, 'handover_pickup');
    assert.ok(!('awaitingCustomerStep' in by[id2]), 'belgisiz hujjatda maydon yo\'q');
    await setAll('off');
  });

  await check('S1 sverka: barcha jurnal yozuvlarida Σdr == Σcr', async () => {
    const n = await journalBalanced();
    assert.ok(n > 0);
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
