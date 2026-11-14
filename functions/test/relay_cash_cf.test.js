/**
 * Naqd yetkazish haqi hisobi — HAQIQIY ledger bilan (Firestore Emulator, Admin SDK).
 *
 *   firebase emulators:exec --only firestore --project demo-relay-cash "node functions/test/relay_cash_cf.test.js"
 *
 * Qulflanadi (S5, ega 2026-11-14):
 *   - ko'p LEG yetkazish: yig'uvchi hamyonidan oldingi LEG'lar + AVA ulushi; platform_accrual 0 ga
 *     yopiladi (EARNED bilan); idempotent; parallel ×3 → bitta yozuv;
 *   - xizmat haqi (courier_service_fee) yig'uvchi ulushidan;
 *   - hamyon yetmaydi → qarz `provider_capabilities.debt.logistics` + AVA (admin_clearing), hamyon manfiy EMAS;
 *   - rad, to'ladi: chiqish + qaytish eskrousi yig'uvchi hamyonidan, qaytish `escrow_funded/ready`;
 *     qaytish jo'natmasi keyin paydo bo'lsa — reconcile yakunlaydi;
 *   - rad, to'lamadi: AVA oldingi kuryerlarni + qaytishni qoplaydi, xaridor qarzi qayd, hamyonga tegilmaydi;
 *   - anomaliya (qaytish narxi mos emas) — pul YO'Q.
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-relay-cash';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const settlementLedger = require('../settlement_ledger');
const C = require('../relay_cash');

const SELLER = '998901110001';
const K1 = '998902220002';
const F1 = '998904440004';
const NOW = new Date('2026-11-14T06:00:00Z');
const digits = (v) => String(v || '').replace(/\D/g, '');
const exportsObj = {};
const api = C.attachRelayCash(exportsObj, {
  functions, db, admin,
  canonicalUid: (v) => { const d = digits(v); return d.length === 9 ? `998${d}` : d; },
  settlementLedger,
  now: () => NOW,
});

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => d.ref.delete()));
}
const bal = async (acc) => ((await db.collection(settlementLedger.COL_ACCOUNTS).doc(acc).get()).data() || {}).balance || 0;
const wallet = (u) => bal(settlementLedger.passengerCreditAccount(u));
const ship = async (id) => (await db.collection('shipments').doc(id).get()).data();
const journal = async (k) => (await db.collection(settlementLedger.COL_JOURNAL).doc(k).get()).exists;

const PRICE = 240000;
const SHARE = 48000;
const POOL = 192000;
const PAYOUTS = [48000, 96000, 48000];
const RET_FEE = 100000;

async function seed({ walletF1 = 300000, status = 'collected', refusal = null, feeBps = null } = {}) {
  await Promise.all(['shipments', 'users', 'provider_capabilities', 'logistics_audit', 'settings',
    settlementLedger.COL_JOURNAL, settlementLedger.COL_ACCOUNTS].map(wipe));
  await db.collection('users').doc(F1).set({ bonusBalance: 0, accountId: `acc${F1}` });
  await db.collection('users').doc(K1).set({ bonusBalance: 0, accountId: `acc${K1}` });
  if (feeBps !== null) await db.collection('settings').doc('courier_service_fee').set({ feeBps, feeVersion: 1, autoPayoutEnabled: true });
  const dp = {
    method: 'cash', amount: PRICE, currency: 'UZS', status, collectorLegId: 'L3', collectorLegPayout: PAYOUTS[2],
    collectedBy: status === 'collected' || status === 'refusal_collected' ? F1 : null, collectedAt: NOW,
    ...(refusal ? { refusal } : {}),
  };
  await db.collection('shipments').doc('S1').set({
    ownerId: SELLER, status: status === 'collected' ? 'delivered' : 'in_transit', paymentStatus: 'cash_on_delivery',
    priceSnapshot: { customerPrice: PRICE, tariffVersion: 7 }, legIds: ['L1', 'L2', 'L3'],
    source: 'wholesale', wholesaleOrderId: 'WO1', recipientId: '998905556677', deliveryPayment: dp,
  });
  await db.collection('shipments').doc('S1').collection('private').doc('internal').set({
    platformShare: SHARE, providerPool: POOL, legPayouts: PAYOUTS.map((amount, index) => ({ index, amount })),
  });
  if (walletF1 > 0) {
    await settlementLedger.postEntry(db, {
      idempotencyKey: `topup:${F1}`, kind: 'test_topup',
      legs: [{ account: 'admin_clearing', dr: walletF1 }, { account: settlementLedger.passengerCreditAccount(F1), cr: walletF1 }],
    });
  }
  // Oldingi LEG'lar EARNED'i — relay_escrow.postEarned bilan AYNI yozuv (pickup hodisalaridan).
  for (const [legId, prov, amount] of [['L1', K1, PAYOUTS[0]], ['L2', F1, PAYOUTS[1]]]) {
    await settlementLedger.postEntry(db, {
      idempotencyKey: `relayEarned:S1:${legId}`, kind: 'logistics_leg_earned', refType: 'shipment', refId: 'S1',
      legs: [{ account: 'platform_accrual', dr: amount }, { account: settlementLedger.supplierPayableAccount(prov), cr: amount }],
    }, { mirrorBonus: false });
  }
}
async function seedReturn(fee = RET_FEE) {
  await db.collection('shipments').doc('R1').set({
    ownerId: SELLER, status: 'awaiting_payment', paymentStatus: 'pending', source: 'wholesale_return',
    outboundShipmentId: 'S1', wholesaleOrderId: 'WO1', priceSnapshot: { customerPrice: fee, tariffVersion: 7 }, legIds: ['RL1'],
  });
}
const REFUSAL = (paid) => ({
  paid, deliveryFee: PRICE, returnFee: RET_FEE, total: PRICE + RET_FEE, returnTariffVersion: 7, currency: 'UZS',
  collectorId: F1, legId: 'L3', collectorLegPayout: PAYOUTS[2], at: NOW,
});

(async () => {
  await check('ko\'p LEG yetkazish: hamyon −192 000 (oldingi LEG\'lar 144 000 + AVA 48 000), accrual 0, settled, idempotent', async () => {
    await seed();
    const r = await api.processShipment('S1');
    assert.strictEqual(r.final.settled, true);
    assert.strictEqual(await wallet(F1), 300000 - 192000);
    assert.strictEqual(await bal('platform_accrual'), 0, 'oldingi LEG EARNED\'i yopildi');
    assert.strictEqual(await bal('earnings:ava_logistics_fee'), SHARE);
    const s = await ship('S1');
    assert.strictEqual(s.paymentStatus, 'settled');
    assert.strictEqual(s.deliveryPayment.status, 'settled');
    assert.strictEqual(s.deliveryPayment.settlement.outbound.due, 192000);
    assert.strictEqual((await db.collection('users').doc(F1).get()).data().bonusBalance, 108000, 'hamyon ko\'zgusi (bonusBalance == ledger)');
    const again = await api.processShipment('S1');
    assert.strictEqual(again.skipped, 'status_settled');
    assert.strictEqual(await wallet(F1), 108000, 'ikkinchi yechish yo\'q');
  });

  await check('parallel processShipment ×3: bitta yozuv, hamyon bir marta', async () => {
    await seed();
    const rs = await Promise.allSettled([1, 2, 3].map(() => api.processShipment('S1')));
    assert.ok(rs.some((x) => x.status === 'fulfilled'));
    assert.strictEqual(await wallet(F1), 108000);
    assert.strictEqual((await ship('S1')).paymentStatus, 'settled');
  });

  await check('xizmat haqi 5%: yig\'uvchi ulushidan ceil (48 000 → 2 400) qo\'shimcha yechiladi', async () => {
    await seed({ feeBps: 500 });
    await api.processShipment('S1');
    assert.strictEqual(await wallet(F1), 300000 - 192000 - 2400);
    assert.strictEqual(await bal('earnings:ava_courier_service_fee'), 2400);
  });

  await check('hamyon yetmaydi (50 000): take 50 000, qarz 142 000 + AVA qoplaydi; hamyon 0 (manfiy EMAS)', async () => {
    await seed({ walletF1: 50000 });
    await api.processShipment('S1');
    assert.strictEqual(await wallet(F1), 0);
    const cap = (await db.collection('provider_capabilities').doc(`acc${F1}`).get()).data();
    assert.strictEqual(cap.debt.logistics, 142000);
    assert.strictEqual(await bal('platform_accrual'), 0);
    const audit = (await db.collection('logistics_audit').doc('cash_settle_S1').get()).data();
    assert.strictEqual(audit.courierDebt, 142000);
    assert.strictEqual(audit.avaCovered, 142000);
  });

  await check('rad, xaridor to\'ladi: chiqish + qaytish (100 000) yig\'uvchi hamyonidan; qaytish escrow_funded/ready', async () => {
    await seed({ status: 'refusal_collected', refusal: REFUSAL(true), walletF1: 400000 });
    await seedReturn();
    const r = await api.processShipment('S1');
    assert.strictEqual(r.final.settled, true);
    assert.strictEqual(await wallet(F1), 400000 - 192000 - RET_FEE);
    assert.strictEqual(await bal('escrow:R1'), RET_FEE);
    const rs = await ship('R1');
    assert.strictEqual(rs.paymentStatus, 'escrow_funded');
    assert.strictEqual(rs.status, 'ready');
    assert.strictEqual(rs.fundedBy, 'cash_refusal');
    assert.strictEqual((await ship('S1')).deliveryPayment.settlement.return.returnShipmentId, 'R1');
  });

  await check('rad, to\'ladi, qaytish jo\'natmasi hali yo\'q: chiqish yozildi, yakun kutadi; keyin reconcile yakunlaydi', async () => {
    await seed({ status: 'refusal_collected', refusal: REFUSAL(true), walletF1: 400000 });
    const r = await api.processShipment('S1');
    assert.strictEqual(r.final.pending, 'return_shipment');
    assert.ok(await journal('relayCashSettle:S1'));
    assert.strictEqual((await ship('S1')).paymentStatus, 'cash_on_delivery');
    await seedReturn();
    const rec = await api.reconcile();
    assert.strictEqual(rec.settled, 1);
    assert.strictEqual(await wallet(F1), 400000 - 192000 - RET_FEE, 'chiqish ikki marta yechilmadi');
    assert.strictEqual((await ship('S1')).paymentStatus, 'settled');
  });

  await check('rad, xaridor to\'lamadi: AVA 144 000 + qaytish 100 000; xaridor qarzi 340 000; hamyonga tegilmaydi', async () => {
    await seed({ status: 'refusal_unpaid', refusal: REFUSAL(false), walletF1: 400000 });
    await seedReturn();
    const r = await api.processShipment('S1');
    assert.strictEqual(r.final.settled, true);
    assert.strictEqual(await wallet(F1), 400000);
    assert.strictEqual(await bal('platform_accrual'), 0, 'oldingi kuryerlar EARNED\'i AVA hisobidan yopildi');
    assert.strictEqual(await bal('escrow:R1'), RET_FEE);
    const s = await ship('S1');
    assert.deepStrictEqual(
      { ...s.deliveryPayment.buyerDebt, at: undefined },
      { amount: 340000, deliveryFee: PRICE, returnFee: RET_FEE, owedToCollector: 48000, avaCovered: 244000, status: 'open', at: undefined },
    );
    assert.ok((await db.collection('logistics_audit').doc('cash_buyer_debt_S1').get()).exists);
    assert.strictEqual((await ship('R1')).paymentStatus, 'escrow_funded');
  });

  await check('anomaliya: qaytish narxi muhrga mos emas — qaytish puli YO\'Q, settleAnomaly yoziladi', async () => {
    await seed({ status: 'refusal_collected', refusal: REFUSAL(true), walletF1: 400000 });
    await seedReturn(99999);
    const r = await api.processShipment('S1');
    assert.strictEqual(r.anomaly, 'return_fee_mismatch');
    assert.strictEqual(await bal('escrow:R1'), 0);
    assert.strictEqual((await ship('R1')).paymentStatus, 'pending');
    assert.strictEqual((await ship('S1')).deliveryPayment.settleAnomaly.code, 'return_fee_mismatch');
    assert.strictEqual(await wallet(F1), 400000 - 192000, 'faqat chiqish qismi (u to\'g\'ri) yozildi');
  });

  await check('eskrou jo\'natma / pending naqd — tegilmaydi', async () => {
    await seed({ status: 'pending' });
    assert.strictEqual((await api.processShipment('S1')).skipped, 'status_pending');
    await db.collection('shipments').doc('S1').update({ 'deliveryPayment.method': 'escrow', 'deliveryPayment.status': 'collected' });
    assert.strictEqual((await api.processShipment('S1')).skipped, 'not_cash');
    assert.strictEqual(await wallet(F1), 300000);
  });

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi`);
  process.exit(failed ? 1 : 0);
})();
