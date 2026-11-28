/**
 * «AVA Супермаркет» ҳамкорга тўлов (эга 2026-11-28) — ҲАҚИҚИЙ `functions/index.js` (`.run()`), ҲАҚИҚИЙ буюртма занжири
 * (partnerUpsertSupermarketOffer → placeSupermarketOrder → тортиш/алмаштириш/олиш → етказилди) ва ҲАҚИҚИЙ ledger, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-sm-partner-payout "node test/sm_partner_payout_cf.test.js"
 *
 * Қулфланади: сукут OFF (пул йўқ) · қоида йўқ → blocked · комиссия 10 % · тортилган/алмаштирилган/олинган қаторлар ·
 * AVA қатори ҳисобга кирмайди · такрор trigger/қайта ҳисоб/параллел — иккинчи ёзув ЙЎҚ · қўлда тўлов (нақд/банк/offset) ·
 * параллел тўлов белгиси — битта ғолиб · тескари ёзув (accrued/paid → clawback) · бекор → тескари · ҳамкор кўриниши ·
 * роллар, сабаб, версия/тарих/admin_audit · Σdr == Σcr, assets == liabilities.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-sm-partner-payout';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const ledger = require('../settlement_ledger');
const sp = require('../sm_partner_payout');
const moduleGate = require('../module_gate');
const TAX = require('../tools/data/supermarket_taxonomy_v1.json');

const db = admin.firestore();
const ADMIN = '998915100001';
const FIN = '998915100002';
const DISP = '998915100003';
const AUD = '998915100004';
const USER = '998912100001'; // мижоз — 9 хонали users ҳужжати
const P1 = '998913100001';
const P2 = '998913100002';
const STRANGER = '998913100009';
const COURIER = '998917100001';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, who ? ctxOf(who) : {});
const { partnerKeyOf } = require('../supermarket');
const K1 = partnerKeyOf(P1);
const K2 = partnerKeyOf(P2);

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
async function expectCode(promise, code) {
  let caught;
  await assert.rejects(promise, (e) => {
    const got = (e.details && e.details.code) || e.message;
    assert.strictEqual(got, code, `kod ${got} (${e.code}): ${e.message}`);
    caught = e;
    return true;
  });
  return caught;
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const get = async (path) => (await db.doc(path).get()).data();
const bal = async (acc) => ((await db.collection(ledger.COL_ACCOUNTS).doc(acc).get()).data() || {}).balance || 0;
const pbal = (key) => bal(sp.partnerAccount(key));
const audits = async (kind) => (await db.collection('admin_audit').where('kind', '==', kind).get()).docs.map((d) => d.data());
const payable = (orderId, key) => get(`${sp.PAYABLES}/${sp.payableIdOf(orderId, key)}`);
const journalCount = async (kind) => (await db.collection(ledger.COL_JOURNAL).where('kind', '==', kind).get()).size;
const variety = (id, c, l, r) => ({ id, names: { uz_Cyrl: c, uz_Latn: l, ru: r } });
const ADDR = { districtId: 'gurlan', mahalla: 'Navoiy', street: 'Mustaqillik', house: '12', phone: '901234567', lat: 41.84, lng: 60.39 };
let seq = 0;
const rid = (p) => `${p}-${Date.now()}-${(seq += 1)}`.replace(/[^A-Za-z0-9_-]/g, '');
const place = async (items) => (await call('placeSupermarketOrder', { clientRequestId: rid('ord'), items, address: ADDR }, USER)).orderId;
const setSettings = (data, who = ADMIN) => call('adminSetSmPartnerPayoutSettings', { reason: 'sinov', ...data }, who);
const markPaid = (data, who = ADMIN) => call('adminMarkSmPartnerPaid', { clientRequestId: rid('pay'), ...data }, who);

/** Курьер якуни (мавжуд CF'лар ёзадиган майдонлар) + ҲАҚИҚИЙ trigger. */
async function deliver(orderId) {
  const ref = db.doc(`orders/${orderId}`);
  const before = await ref.get();
  await ref.update({ status: 'delivered', fulfillmentStatus: 'completed', courierId: COURIER, deliveredAt: admin.firestore.FieldValue.serverTimestamp() });
  await fns.onSmOrderPartnerPayout.run({ before, after: await ref.get() }, { params: { orderId } });
}
async function ledgerOk() {
  const r = await ledger.reconcile(db);
  assert.strictEqual(r.balanced, true, 'Σdr == Σcr');
  assert.strictEqual(r.identityOk, true, `assets ${r.assets} == liabilities ${r.liabilities}`);
  assert.strictEqual(r.projectionOk, true, `hamyon ko'zgusi: ${JSON.stringify(r.mismatches)}`);
}

async function main() {
  await clearEmulator();
  await Promise.all([
    db.doc(`users/${ADMIN}`).set({ role: 'admin' }),
    db.doc(`users/${FIN}`).set({ role: 'finance' }),
    db.doc(`users/${DISP}`).set({ role: 'dispatcher' }),
    db.doc(`users/${AUD}`).set({ role: 'auditor' }),
    db.doc(`users/${USER.slice(3)}`).set({ role: 'user', name: 'Ali', bonusBalance: 5000000, districtId: 'gurlan', regionId: 'xorazm' }),
    // Мижоз ҳамёни ledger'да ҳам (ҳамён кўзгуси == passenger_credit; Dr admin_clearing / Cr passenger_credit — тўлдириш шакли).
    db.doc(`${ledger.COL_ACCOUNTS}/${ledger.passengerCreditAccount(USER.slice(3))}`).set({ type: 'liability', ownerUid: USER.slice(3), balance: 5000000 }),
    db.doc(`${ledger.COL_ACCOUNTS}/admin_clearing`).set({ type: 'asset', ownerUid: '', balance: 5000000 }),
    db.doc(`users/${P1}`).set({ role: 'user', districtId: 'gurlan' }),
    db.doc(`users/${P2}`).set({ role: 'user', districtId: 'gurlan' }),
    db.doc(`users/${STRANGER}`).set({ role: 'user' }),
    db.doc(`wholesale_sellers/${P1}`).set({ approvalStatus: 'approved', companyName: 'Деҳқон ММ' }),
    db.doc(`wholesale_sellers/${P2}`).set({ approvalStatus: 'approved', companyName: 'Гўшт ММ' }),
    db.doc('settings/app').set({ platformDeliveryFeePercent: 11, platformDeliveryFeeVersion: 1, supermarketPartnerAutoApprove: true }),
    db.doc('config/module_defaults').set({ enforce: true, modules: { supermarket: 'enabled' } }),
  ]);
  moduleGate.resetCache();
  await call('adminSetSupermarketTaxonomy', { taxonomy: TAX, expectedVersion: 0 }, ADMIN);
  const up = async (who, sku, offer) => (await call('partnerUpsertSupermarketOffer', { sku, offer }, who)).productId;
  const P1_POTATO = await up(P1, 'kart', { smGroupId: 'potato', smVariety: variety('red', 'Қизил', 'Qizil', 'Красный'), stock: 100, smStatus: 'active', price: 6000 });
  const P1_MILK = await up(P1, 'milk', { smGroupId: 'milk', smVariety: variety('cow', 'Сигир', 'Sigir', 'Коровье'), packLabel: '1 л', stock: 100, smStatus: 'active', price: 12000 });
  const P2_BEEF = await up(P2, 'beef', { smGroupId: 'beef', smVariety: variety('lean', 'Лаҳм', 'Lahm', 'Постная'), stock: 100, smStatus: 'active', price: 80000 });
  const P2_POTATO = await up(P2, 'kart2', { smGroupId: 'potato', smVariety: variety('white', 'Оқ', 'Oq', 'Белый'), stock: 100, smStatus: 'active', price: 5800 });
  await call('adminUpsertSupermarketOffer', { productId: 'water_1', offer: { smGroupId: 'drinking_water', smVariety: variety('still', 'Газсиз', 'Gazsiz', 'Без газа'), packLabel: '1.5 л', stock: 100, smStatus: 'active', price: 4500 } }, ADMIN);

  let A;
  await check('S1 сукут OFF: етказилган буюртма → қарз ёзуви ЙЎҚ, journal ЙЎҚ; recompute → STAGE_OFF', async () => {
    A = await place([{ productId: P1_POTATO, qty: 2 }, { productId: P1_MILK, qty: 2 }, { productId: P2_BEEF, qty: 1.5 }, { productId: 'water_1', qty: 1 }]);
    await call('adminSettleSupermarketWeights', { orderId: A, lines: [{ productId: P1_POTATO, actualQty: 1.9 }, { productId: P2_BEEF, actualQty: 1.4 }] }, ADMIN);
    await deliver(A);
    assert.strictEqual((await db.collection(sp.PAYABLES).get()).size, 0);
    assert.strictEqual(await journalCount(sp.KIND_ACCRUE), 0);
    await expectCode(call('adminRecomputeSmPartnerPayables', { orderIds: [A] }, ADMIN), 'STAGE_OFF');
  });

  await check('S2 созлама: роллар, чегаралар (−1/10001/1.5), сабаб, версия + тарих + admin_audit; ўзгармаса — версия ошмайди', async () => {
    await assert.rejects(setSettings({ stage: 'internal' }, DISP), (e) => e.code === 'permission-denied');
    await assert.rejects(setSettings({ stage: 'internal' }, USER), (e) => e.code === 'permission-denied');
    await assert.rejects(call('adminGetSmPartnerPayoutSettings', {}, DISP), (e) => e.code === 'permission-denied');
    for (const bad of [-1, 10001, 1.5, '100']) await expectCode(setSettings({ commissionBp: bad }), 'SETTINGS_INVALID');
    await expectCode(setSettings({ stage: 'beta' }), 'SETTINGS_INVALID');
    await expectCode(setSettings({}), 'SETTINGS_INVALID');
    await expectCode(call('adminSetSmPartnerPayoutSettings', { stage: 'internal', reason: 'x' }, ADMIN), 'REASON_REQUIRED');
    const r = await setSettings({ stage: 'internal' }, FIN);
    assert.deepStrictEqual([r.version, r.stage, r.commissionBp, r.unchanged], [1, 'internal', null, false]);
    const same = await setSettings({ stage: 'internal' });
    assert.deepStrictEqual([same.unchanged, same.version], [true, 1]);
    const g = await call('adminGetSmPartnerPayoutSettings', {}, AUD);
    assert.deepStrictEqual([g.stage, g.commissionBp, g.version, g.bpMax], ['internal', null, 1, 10000]);
    assert.ok((await db.doc(`${sp.HISTORY}/v1`).get()).exists);
    assert.strictEqual((await audits('sm_partner_payout_settings')).length, 1);
  });

  await check('S3 қоида ЙЎҚ (commissionBp null): recompute → иккала ҳамкор blocked RULE_NOT_SET, пул ЙЎҚ; AVA қатори ҳисобга кирмайди', async () => {
    const r = await call('adminRecomputeSmPartnerPayables', { orderIds: [A] }, ADMIN);
    assert.deepStrictEqual([r.orders, r.blocked, r.accrued], [1, 2, 0]);
    const a1 = await payable(A, K1);
    const a2 = await payable(A, K2);
    assert.deepStrictEqual([a1.status, a1.blockReason, a1.goodsBasis, a1.amount, a1.sellerId, a1.companyName], ['blocked', 'RULE_NOT_SET', 35400, null, P1, 'Деҳқон ММ']);
    assert.deepStrictEqual([a2.status, a2.goodsBasis], ['blocked', 112000]);
    assert.strictEqual(await journalCount(sp.KIND_ACCRUE), 0);
    assert.strictEqual((await get(`${sp.SUMMARY}/${K1}`)).blockedCount, 1);
    const again = await call('adminRecomputeSmPartnerPayables', { orderIds: [A] }, ADMIN);
    assert.strictEqual(again.blocked, 2);
    assert.strictEqual((await get(`${sp.SUMMARY}/${K1}`)).blockedCount, 1, 'такрор — ҳисоблагич ошмайди');
  });

  await check('S4 комиссия 10 % (1000 bp, v2): recompute → accrued; P1 35400 → 3540 / 31860, P2 112000 → 11200 / 100800; ledger Dr admin_clearing / Cr supplier_payable:smp_*', async () => {
    const s = await setSettings({ commissionBp: 1000 });
    assert.strictEqual(s.version, 2);
    const r = await call('adminRecomputeSmPartnerPayables', { orderIds: [A] }, ADMIN);
    assert.deepStrictEqual([r.accrued, r.blocked], [2, 0]);
    const a1 = await payable(A, K1);
    assert.deepStrictEqual([a1.status, a1.blockReason, a1.goodsBasis, a1.commissionBp, a1.commission, a1.amount, a1.settingsVersion, a1.orderTariffVersion, a1.lines.length],
      ['accrued', null, 35400, 1000, 3540, 31860, 2, 'sm-v1', 2]);
    assert.deepStrictEqual([(await payable(A, K2)).amount, await pbal(K1), await pbal(K2)], [100800, 31860, 100800]);
    const j = await get(`${ledger.COL_JOURNAL}/${sp.accrueKeyOf(A, K1)}`);
    assert.deepStrictEqual([j.kind, j.amount, j.refId, j.legs.map((l) => l.account)], [sp.KIND_ACCRUE, 31860, A, ['admin_clearing', sp.partnerAccount(K1)]]);
    const sum = await get(`${sp.SUMMARY}/${K1}`);
    assert.deepStrictEqual([sum.accruedTotal, sum.openCount, sum.blockedCount], [31860, 1, 0]);
    const ev = (await db.collection(`${sp.PAYABLES}/${sp.payableIdOf(A, K1)}/events`).get()).docs.map((d) => d.data().type).sort();
    assert.deepStrictEqual(ev, ['accrued', 'blocked']);
    const text = JSON.stringify(a1);
    assert.ok(!text.includes(USER) && !text.includes(USER.slice(3)), 'қарз ёзувида мижоз телефони йўқ');
    await ledgerOk();
  });

  await check('S5 такрор: trigger ×2 + recompute + 3 параллел → иккинчи ёзув ЙЎҚ (journal 2 та, баланс ўзгармайди)', async () => {
    const ref = db.doc(`orders/${A}`);
    const s = await ref.get();
    const beforeSnap = { ...s, data: () => ({ ...s.data(), status: 'ready', fulfillmentStatus: 'pending' }) };
    await fns.onSmOrderPartnerPayout.run({ before: beforeSnap, after: s }, { params: { orderId: A } });
    await fns.onSmOrderPartnerPayout.run({ before: beforeSnap, after: s }, { params: { orderId: A } });
    await Promise.all([1, 2, 3].map(() => call('adminRecomputeSmPartnerPayables', { orderIds: [A] }, ADMIN)));
    assert.strictEqual(await journalCount(sp.KIND_ACCRUE), 2);
    assert.deepStrictEqual([await pbal(K1), await pbal(K2), (await get(`${sp.SUMMARY}/${K1}`)).accruedTotal], [31860, 100800, 31860]);
    // Ўзгармаган буюртма янгиланиши (етказилган → етказилган) — trigger ҳеч нарса қилмайди.
    await fns.onSmOrderPartnerPayout.run({ before: s, after: s }, { params: { orderId: A } });
    assert.strictEqual(await journalCount(sp.KIND_ACCRUE), 2);
  });

  let B; let C;
  await check('S6 тортилмаган қатор (етказилди, тортиш йўқ) → blocked WEIGH_PENDING; алмаштириш + олиш → фақат янги ҳамкор қарзи', async () => {
    B = await place([{ productId: P2_BEEF, qty: 1 }]);
    await deliver(B);
    const b2 = await payable(B, K2);
    assert.deepStrictEqual([b2.status, b2.blockReason, b2.goodsBasis], ['blocked', 'WEIGH_PENDING', 80000]);
    C = await place([{ productId: P1_POTATO, qty: 2 }, { productId: P1_MILK, qty: 1 }]);
    await call('adminReportSupermarketShortage', { orderId: C, productId: P1_POTATO, availableQty: 0, substitutes: [P2_POTATO] }, DISP);
    await call('respondSupermarketShortage', { orderId: C, productId: P1_POTATO, choice: 'substitute', offerId: P2_POTATO, clientRequestId: rid('sh') }, USER);
    await call('adminSettleSupermarketWeights', { orderId: C, lines: [{ productId: P2_POTATO, actualQty: 2 }] }, ADMIN);
    await call('adminRemoveSupermarketLine', { orderId: C, productId: P1_MILK, reason: 'Тугади' }, ADMIN);
    await deliver(C);
    assert.strictEqual(await payable(C, K1), undefined, 'P1 қаторлари йўқ (алмаштирилди/олинди) — ёзув йўқ');
    const c2 = await payable(C, K2);
    assert.deepStrictEqual([c2.status, c2.goodsBasis, c2.commission, c2.amount, c2.lines[0].substitutedFrom], ['accrued', 11600, 1160, 10440, P1_POTATO]);
    assert.strictEqual(await pbal(K2), 100800 + 10440);
  });

  await check('S7 тўлов белгиси рад этишлари: dispatcher/аудитор; бошқа ҳамкор ёзуви; blocked; банк — reference шарт; нотўғри шакл', async () => {
    const a1 = sp.payableIdOf(A, K1);
    await assert.rejects(markPaid({ partnerKey: K1, payableIds: [a1], method: 'cash' }, DISP), (e) => e.code === 'permission-denied');
    await assert.rejects(markPaid({ partnerKey: K1, payableIds: [a1], method: 'cash' }, AUD), (e) => e.code === 'permission-denied');
    await expectCode(markPaid({ partnerKey: K1, payableIds: [a1, sp.payableIdOf(A, K2)], method: 'cash' }), 'PAYABLE_PARTNER_MISMATCH');
    await expectCode(markPaid({ partnerKey: K2, payableIds: [sp.payableIdOf(B, K2)], method: 'cash' }), 'PAYABLE_NOT_PAYABLE');
    await expectCode(markPaid({ partnerKey: K1, payableIds: [a1], method: 'bank_transfer', reference: '' }), 'REFERENCE_REQUIRED');
    await expectCode(markPaid({ partnerKey: K1, payableIds: [a1], method: 'card' }), 'INVALID_REQUEST');
    await expectCode(markPaid({ partnerKey: K1, payableIds: [], method: 'cash' }), 'INVALID_REQUEST');
    await expectCode(markPaid({ partnerKey: K1, payableIds: [a1], method: 'cash', clientRequestId: 'x' }), 'INVALID_REQUEST');
    await expectCode(markPaid({ partnerKey: K1, payableIds: [`nope__${K1}`], method: 'cash' }), 'PAYABLE_NOT_FOUND');
    assert.strictEqual((await payable(A, K1)).status, 'accrued');
    assert.strictEqual(await journalCount(sp.KIND_PAID), 0);
  });

  await check('S8 нақд тўлов P1 (31860): ҳолат paid, journal Dr ҳамкор / Cr admin_cash, баланс 0, тўлов ҳужжати, admin_audit; шу clientRequestId қайта — duplicate, иккинчи journal ЙЎҚ', async () => {
    const reqId = rid('paycash');
    const r = await markPaid({ partnerKey: K1, payableIds: [sp.payableIdOf(A, K1)], method: 'cash', reference: 'Кассадан', clientRequestId: reqId }, FIN);
    assert.deepStrictEqual([r.amount, r.count, r.method, !!r.duplicate], [31860, 1, 'cash', false]);
    const a1 = await payable(A, K1);
    assert.deepStrictEqual([a1.status, a1.method, a1.paymentId], ['paid', 'cash', r.paymentId]);
    assert.deepStrictEqual([await pbal(K1), await bal('admin_cash')], [0, -31860]);
    const j = await get(`${ledger.COL_JOURNAL}/${sp.paidKeyOf(r.paymentId)}`);
    assert.deepStrictEqual([j.kind, j.amount, j.legs.map((l) => l.account)], [sp.KIND_PAID, 31860, [sp.partnerAccount(K1), 'admin_cash']]);
    const p = await get(`${sp.PAYMENTS}/${r.paymentId}`);
    assert.deepStrictEqual([p.amount, p.method, p.reference, p.channel, p.actor], [31860, 'cash', 'Кассадан', 'manual_outside_system', FIN]);
    const au = await audits('sm_partner_paid');
    assert.deepStrictEqual([au.length, au[0].total, au[0].actor], [1, 31860, FIN]);
    const dup = await markPaid({ partnerKey: K1, payableIds: [sp.payableIdOf(A, K1)], method: 'cash', clientRequestId: reqId }, FIN);
    assert.deepStrictEqual([dup.duplicate, dup.amount], [true, 31860]);
    assert.strictEqual(await journalCount(sp.KIND_PAID), 1);
    assert.strictEqual((await audits('sm_partner_paid')).length, 1);
    const sum = await get(`${sp.SUMMARY}/${K1}`);
    assert.deepStrictEqual([sum.paidTotal, sum.openCount], [31860, 0]);
    await expectCode(markPaid({ partnerKey: K1, payableIds: [sp.payableIdOf(A, K1)], method: 'cash' }), 'PAYABLE_NOT_PAYABLE');
    await ledgerOk();
  });

  await check('S9 ПАРАЛЛЕЛ тўлов белгиси (2 админ, турли clientRequestId) → битта ғолиб, иккинчиси PAYABLE_NOT_PAYABLE; пул БИР марта', async () => {
    const id = sp.payableIdOf(A, K2);
    const res = await Promise.allSettled([
      markPaid({ partnerKey: K2, payableIds: [id], method: 'cash' }, ADMIN),
      markPaid({ partnerKey: K2, payableIds: [id], method: 'bank_transfer', reference: 'BANK-777' }, FIN),
    ]);
    const ok = res.filter((x) => x.status === 'fulfilled');
    const bad = res.filter((x) => x.status === 'rejected');
    assert.deepStrictEqual([ok.length, bad.length], [1, 1], JSON.stringify(res.map((x) => x.status)));
    assert.strictEqual(bad[0].reason.details.code, 'PAYABLE_NOT_PAYABLE');
    assert.strictEqual(await journalCount(sp.KIND_PAID), 2);
    assert.strictEqual(await pbal(K2), 10440, 'фақат C қолди');
    assert.strictEqual((await get(`${sp.SUMMARY}/${K2}`)).paidTotal, 100800);
  });

  await check('S10 тескари ёзув (accrued): P2 C → reversed, баланс 0; такрор — changed:false; blocked/номаълум — рад; сабаб шарт; audit', async () => {
    const id = sp.payableIdOf(C, K2);
    await expectCode(call('adminReverseSmPartnerPayable', { payableId: id, reason: 'x' }, ADMIN), 'REASON_REQUIRED');
    await assert.rejects(call('adminReverseSmPartnerPayable', { payableId: id, reason: 'Қайтарилди' }, DISP), (e) => e.code === 'permission-denied');
    const r = await call('adminReverseSmPartnerPayable', { payableId: id, reason: 'Мижоз қайтарди' }, ADMIN);
    assert.deepStrictEqual([r.changed, !!r.clawback], [true, false]);
    const c2 = await payable(C, K2);
    assert.deepStrictEqual([c2.status, c2.reversedFrom, c2.clawback, c2.reverseReason], ['reversed', 'accrued', false, 'Мижоз қайтарди']);
    assert.strictEqual(await pbal(K2), 0);
    const again = await call('adminReverseSmPartnerPayable', { payableId: id, reason: 'Мижоз қайтарди' }, ADMIN);
    assert.strictEqual(again.changed, false);
    assert.strictEqual(await journalCount(sp.KIND_REVERSE), 1);
    await expectCode(call('adminReverseSmPartnerPayable', { payableId: sp.payableIdOf(B, K2), reason: 'Синов' }, ADMIN), 'PAYABLE_NOT_REVERSIBLE');
    await expectCode(call('adminReverseSmPartnerPayable', { payableId: `nope__${K2}`, reason: 'Синов' }, ADMIN), 'PAYABLE_NOT_FOUND');
    assert.strictEqual((await audits('sm_partner_payable_reversed')).length, 1);
    await expectCode(markPaid({ partnerKey: K2, payableIds: [id], method: 'cash' }), 'PAYABLE_NOT_PAYABLE');
  });

  let D;
  await check('S11 ТЎЛАНГАНДАН КЕЙИН қайтариш (clawback): P1 −31860; янги қарз 10800 → −21060; нақд тўлов рад (PAYMENT_EXCEEDS_BALANCE), offset — ўтади (journal ЙЎҚ)', async () => {
    const r = await call('adminReverseSmPartnerPayable', { payableId: sp.payableIdOf(A, K1), reason: 'Сифатсиз — қайтарилди' }, ADMIN);
    assert.deepStrictEqual([r.changed, r.clawback], [true, true]);
    assert.deepStrictEqual([(await payable(A, K1)).status, (await payable(A, K1)).clawback, await pbal(K1)], ['reversed', true, -31860]);
    D = await place([{ productId: P1_MILK, qty: 1 }]);
    await deliver(D);
    assert.deepStrictEqual([(await payable(D, K1)).amount, await pbal(K1)], [10800, -21060]);
    const dId = sp.payableIdOf(D, K1);
    const e = await expectCode(markPaid({ partnerKey: K1, payableIds: [dId], method: 'cash' }), 'PAYMENT_EXCEEDS_BALANCE');
    assert.deepStrictEqual([e.details.balance, e.details.sum], [-21060, 10800]);
    const paidBefore = await journalCount(sp.KIND_PAID);
    const off = await markPaid({ partnerKey: K1, payableIds: [dId], method: 'offset' });
    assert.deepStrictEqual([off.amount, off.method], [10800, 'offset']);
    assert.deepStrictEqual([(await payable(D, K1)).status, (await payable(D, K1)).method, await pbal(K1)], ['paid', 'offset', -21060]);
    assert.strictEqual(await journalCount(sp.KIND_PAID), paidBefore, 'offset — пул юрмайди');
    const sum = await get(`${sp.SUMMARY}/${K1}`);
    assert.deepStrictEqual([sum.offsetTotal, sum.clawbackTotal, sum.reversedTotal], [10800, 31860, 31860]);
    await ledgerOk();
  });

  await check('S12 бекор: етказилмасдан бекор → ёзув ЙЎҚ; етказилгандан кейин мажбурий бекор → автоматик тескари ёзув; банк ўтказмаси reference билан', async () => {
    const E = await place([{ productId: P1_MILK, qty: 1 }]);
    const ref = db.doc(`orders/${E}`);
    const before = await ref.get();
    await call('customerCancelOrder', { orderId: E }, USER);
    await fns.onSmOrderPartnerPayout.run({ before, after: await ref.get() }, { params: { orderId: E } });
    assert.strictEqual(await payable(E, K1), undefined);
    const F = await place([{ productId: P2_BEEF, qty: 1 }]);
    await call('adminSettleSupermarketWeights', { orderId: F, lines: [{ productId: P2_BEEF, actualQty: 1 }] }, ADMIN);
    await deliver(F);
    assert.deepStrictEqual([(await payable(F, K2)).amount, await pbal(K2)], [72000, 72000]);
    const fRef = db.doc(`orders/${F}`);
    const fb = await fRef.get();
    await fRef.update({ status: 'cancelled' });
    await fns.onSmOrderPartnerPayout.run({ before: fb, after: await fRef.get() }, { params: { orderId: F } });
    const f2 = await payable(F, K2);
    assert.deepStrictEqual([f2.status, f2.reverseReason, f2.reversedBy, await pbal(K2)], ['reversed', 'order_cancelled', 'system', 0]);
    // blocked B бекор қилинса — void (пул йўқ).
    const bRef = db.doc(`orders/${B}`);
    const bb = await bRef.get();
    await bRef.update({ status: 'cancelled' });
    await fns.onSmOrderPartnerPayout.run({ before: bb, after: await bRef.get() }, { params: { orderId: B } });
    assert.strictEqual((await payable(B, K2)).status, 'void');
    assert.strictEqual((await get(`${sp.SUMMARY}/${K2}`)).blockedCount, 0);
    // Банк ўтказмаси.
    const H = await place([{ productId: P2_BEEF, qty: 0.5 }]);
    await call('adminSettleSupermarketWeights', { orderId: H, lines: [{ productId: P2_BEEF, actualQty: 0.5 }] }, ADMIN);
    await deliver(H);
    const pay = await markPaid({ partnerKey: K2, payableIds: [sp.payableIdOf(H, K2)], method: 'bank_transfer', reference: 'TRX-2026-11-28-01' });
    assert.deepStrictEqual([pay.amount, await pbal(K2), (await get(`${sp.PAYMENTS}/${pay.paymentId}`)).reference], [36000, 0, 'TRX-2026-11-28-01']);
    await ledgerOk();
  });

  await check('S13 ҳамкор кўриниши: internal — enabled:false; public — ўз баланси/ёзувлари, бошқасиники йўқ, мижоз маълумоти йўқ; бегона — PARTNER_NOT_APPROVED', async () => {
    assert.deepStrictEqual(await call('partnerGetSmPayouts', {}, P1), { ok: true, enabled: false });
    await expectCode(call('partnerGetSmPayouts', {}, STRANGER), 'PARTNER_NOT_APPROVED');
    await setSettings({ stage: 'public' });
    const v = await call('partnerGetSmPayouts', {}, P1);
    assert.deepStrictEqual([v.enabled, v.balance, v.accruedTotal, v.paidTotal, v.reversedTotal, v.commissionBp], [true, -21060, 31860 + 10800, 31860 + 10800, 31860, 1000]);
    assert.deepStrictEqual(v.payables.map((p) => p.orderId).sort(), [A, D].sort());
    assert.ok(v.payments.length === 2 && v.payments.every((p) => p.reference === ''), 'нақд/offset изоҳи ҳамкорга кўрсатилмайди');
    const text = JSON.stringify(v);
    assert.ok(!text.includes(USER.slice(3)) && !text.includes('Navoiy') && !text.includes(P2), 'мижоз/бошқа ҳамкор маълумоти йўқ');
    const v2 = await call('partnerGetSmPayouts', {}, P2);
    assert.strictEqual(v2.payables.length, 5, 'P2 — ўз 5 ёзуви (A, B, C, F, H)');
    assert.ok(v2.payables.every((p) => [A, B, C].includes(p.orderId) || p.orderId !== D), 'P1 буюртмаси D йўқ');
    assert.ok(v2.payments.some((p) => p.reference === 'TRX-2026-11-28-01'), 'банк reference кўринади');
  });

  await check('S14 админ рўйхати: ҳамкорлар жамламаси + ledger баланси; ҳамкор ёзувлари ва тўловлари; blocked навбат; аудитор ўқийди, dispatcher — йўқ', async () => {
    await assert.rejects(call('adminListSmPartnerPayables', {}, DISP), (e) => e.code === 'permission-denied');
    const l = await call('adminListSmPartnerPayables', {}, AUD);
    const p1 = l.partners.find((p) => p.partnerKey === K1);
    assert.deepStrictEqual([p1.balance, p1.companyName, p1.paidTotal, p1.offsetTotal, p1.clawbackTotal], [-21060, 'Деҳқон ММ', 31860, 10800, 31860]);
    assert.strictEqual(l.blocked.length, 0);
    const d = await call('adminListSmPartnerPayables', { partnerKey: K2 }, ADMIN);
    assert.ok(d.payables.length >= 4 && d.payments.length === 2);
    await expectCode(call('adminListSmPartnerPayables', { partnerKey: 'bad' }, ADMIN), 'INVALID_REQUEST');
  });

  await check('S15 қайта ҳисоб сана оралиғи (slot.date): ≤31 кун; ортиқ — RANGE_INVALID; барча ёзувлар ўзгармайди', async () => {
    const day = (await get(`orders/${A}`)).slot.date;
    const before = await journalCount(sp.KIND_ACCRUE);
    const r = await call('adminRecomputeSmPartnerPayables', { from: day, to: day }, ADMIN);
    assert.ok(r.orders >= 5 && r.errors === 0, JSON.stringify(r));
    assert.strictEqual(await journalCount(sp.KIND_ACCRUE), before);
    await expectCode(call('adminRecomputeSmPartnerPayables', { from: '2026-01-01', to: '2026-03-01' }, ADMIN), 'RANGE_INVALID');
    await expectCode(call('adminRecomputeSmPartnerPayables', { orderIds: [] }, ADMIN), 'INVALID_REQUEST');
    await ledgerOk();
  });

  await check('S16 ҳамкорга ҳамён ўтказмаси ЙЎҚ (пул тизимдан ташқарида); stage off → янги етказилган буюртма ёзилмайди', async () => {
    assert.strictEqual((await get(`users/${P1}`)).bonusBalance, undefined);
    assert.strictEqual((await get(`users/${P2}`)).bonusBalance, undefined);
    await setSettings({ stage: 'off' });
    const G = await place([{ productId: P1_MILK, qty: 1 }]);
    await deliver(G);
    assert.strictEqual(await payable(G, K1), undefined);
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed} passed, ${results.length - passed} failed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
