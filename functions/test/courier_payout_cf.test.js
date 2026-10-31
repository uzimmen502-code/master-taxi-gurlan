/**
 * Relay kuryer haqi AVTOMATIK hamyonga (ega qarori 2026-10-31) — HAQIQIY ledger,
 * HAQIQIY `functions/index.js` eksportlari (`.run()`), Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-courierpay \
 *     "node functions/test/courier_payout_cf.test.js"
 *
 * Qulflanadi:
 *   - EARNED (relay trigger orqali) → bitta to'lov: Dr supplier_payable / Cr hamyon / Cr fee;
 *     takror trigger, reconcile, parallel chaqiruv — ikkinchi pul YO'Q
 *   - fee = ceil(gross × bps / 10000): 0, 1, 5000 bps chegaralari; net 0 bo'lsa hamyon oyog'i yo'q
 *   - kill switch false → pul yo'q (kechiktirilgan qayd); yoqilgach reconcile to'laydi
 *   - payable yetmasa / users yo'q / sozlama noto'g'ri → anomaliya, pul YO'Q
 *   - creditSupplier (qo'lda) ishlaydi; avtomatik + qo'lda yig'indisi ishlab topilgandan oshmaydi
 *   - hamyon ko'zgusi == passenger_credit (reconcile projectionOk), Σdr == Σcr
 *   - admin callable: rol, chegaralar, sabab, versiya + tarix + admin_audit
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:15237';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-courierpay';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require('../index');
const admin = require('firebase-admin');
const ledger = require('../settlement_ledger');
const cp = require('../courier_payout');

const db = admin.firestore();

const ADMIN = '998909990000';
const FINANCE = '998909990001';
const DISPATCHER = '998909990002';
const AUDITOR = '998909990003';
const STRANGER = '998904440004';
const K1 = '998902220002';
const K2 = '998902220003';
const K9 = '998907770007'; // users hujjati 9 xonali: 907770007
const NOUSER = '998906660006';

const ctxOf = (phone) => ({ auth: { uid: `uid_${phone}`, token: { phone_number: `+${phone}` } } });
const call = (name, data, phone) => fns[name].run(data, ctxOf(phone));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
async function expectCode(promise, code, httpsCode) {
  await assert.rejects(promise, (e) => {
    const got = (e.details && e.details.code) || e.message;
    if (code) assert.strictEqual(got, code, `kod ${got} (${e.code}): ${e.message}`);
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
  await Promise.all([
    db.collection('users').doc(ADMIN).set({ role: 'admin' }),
    db.collection('users').doc(FINANCE).set({ role: 'finance' }),
    db.collection('users').doc(DISPATCHER).set({ role: 'dispatcher' }),
    db.collection('users').doc(AUDITOR).set({ role: 'auditor' }),
    db.collection('users').doc(STRANGER).set({ role: 'user' }),
    db.collection('users').doc(K1).set({ role: 'user', bonusBalance: 0 }),
    db.collection('users').doc(K2).set({ role: 'user', bonusBalance: 0 }),
    db.collection('users').doc(K9.slice(3)).set({ role: 'user', bonusBalance: 0 }),
  ]);
}
const bal = async (acc) => ((await db.collection(ledger.COL_ACCOUNTS).doc(acc).get()).data() || {}).balance || 0;
const payable = (p) => bal(ledger.supplierPayableAccount(p));
const wallet = (uid) => bal(ledger.passengerCreditAccount(uid));
const bonus = async (uid) => ((await db.collection('users').doc(uid).get()).data() || {}).bonusBalance || 0;
const feeAcc = () => bal(cp.FEE_ACCOUNT);
const journal = async (id) => (await db.collection(ledger.COL_JOURNAL).doc(id).get());
const anomaly = async (key) => (await db.collection(cp.ANOMALIES).doc(key).get()).data();
const walletRows = async (uid) => (await db.collection('users').doc(uid).collection('wallet_ledger')
  .where('type', '==', cp.WALLET_LEDGER_TYPE).get()).docs.map((d) => d.data());
const setFee = (data, who = ADMIN) => call('adminSetCourierServiceFee', { reason: 'sinov', ...data }, who);
const reconcileRun = () => fns.courierPayoutReconcile.run({}, {});

/** HAQIQIY relay trigger orqali EARNED; `trigger` — payout trigger'ini ham chaqirish. */
async function earn(shipmentId, legId, providerId, payout, { trigger = true } = {}) {
  const evRef = db.collection('custody_events').doc(`ev_${shipmentId}_${legId}`);
  await evRef.set({
    shipmentId, completesLegId: legId, completedLegProviderId: providerId, completedLegPayout: payout,
    legIndex: 0, deliversShipment: false,
  });
  await fns.onLogisticsCustodyEvent.run(await evRef.get(), { params: { eventId: evRef.id } });
  const id = `relayEarned:${shipmentId}:${legId}`;
  const snap = await journal(id);
  assert.ok(snap.exists, 'EARNED yozilmadi');
  if (trigger) await fns.onRelayEarnedCourierPayout.run(snap, { params: { entryId: id } });
  return { id, key: `courierPayout:${shipmentId}:${legId}`, snap };
}
async function ledgerOk() {
  const r = await ledger.reconcile(db);
  assert.strictEqual(r.balanced, true, 'Σdr == Σcr');
  assert.strictEqual(r.projectionOk, true, `hamyon ko'zgusi: ${JSON.stringify(r.mismatches)}`);
}

async function main() {
  // ── Sof funksiyalar ────────────────────────────────────────────────
  await check('computeFee: ceil, 0/1/5000 bps chegaralari, noto\'g\'ri kirish rad', async () => {
    assert.strictEqual(cp.computeFee(96000, 0), 0);
    assert.strictEqual(cp.computeFee(96000, 1), 10, '9.6 → 10');
    assert.strictEqual(cp.computeFee(10000, 1), 1, 'aniq 1');
    assert.strictEqual(cp.computeFee(9999, 1), 1, '0.9999 → 1');
    assert.strictEqual(cp.computeFee(96000, 1000), 9600);
    assert.strictEqual(cp.computeFee(96001, 5000), 48001, '48000.5 → 48001');
    assert.strictEqual(cp.computeFee(1, 5000), 1);
    assert.strictEqual(cp.computeFee(40000, 1250), 5000);
    for (const [a, b] of [[96000, 5001], [96000, -1], [96000, 1.5], [0, 100], [1.5, 100], [96000, '100']]) {
      assert.throws(() => cp.computeFee(a, b), undefined, `${a}/${b}`);
    }
  });
  await check('parseSettings: yo\'q → 0 bps/yoqilgan; false hurmat; 9999 → invalid', async () => {
    assert.deepStrictEqual(cp.parseSettings(null), { feeBps: 0, feeVersion: 0, autoPayoutEnabled: true, valid: true, configured: false });
    assert.strictEqual(cp.parseSettings({ autoPayoutEnabled: false }).autoPayoutEnabled, false);
    assert.strictEqual(cp.parseSettings({ feeBps: 9999 }).valid, false);
    assert.strictEqual(cp.parseSettings({ feeBps: '100' }).valid, false);
    assert.strictEqual(cp.parseSettings({ feeBps: 250, feeVersion: 4 }).feeBps, 250);
  });
  await check('parseEarned: kalit relay bilan mos; buzuq meta → earned_malformed', async () => {
    const good = cp.parseEarned('relayEarned:S1:leg0', {
      kind: 'logistics_leg_earned', meta: { shipmentId: 'S1', legId: 'leg0' },
      legs: [{ account: 'platform_accrual', dr: 500, cr: 0 }, { account: `supplier_payable:${K1}`, dr: 0, cr: 500 }],
    });
    assert.strictEqual(good.ok, true); assert.strictEqual(good.key, 'courierPayout:S1:leg0');
    assert.strictEqual(good.providerId, K1); assert.strictEqual(good.amount, 500);
    const bad = cp.parseEarned('relayEarned:S1:leg0', { kind: 'logistics_leg_earned', meta: { shipmentId: 'S2', legId: 'leg0' }, legs: [] });
    assert.strictEqual(bad.ok, false); assert.strictEqual(bad.reason, 'earned_malformed');
  });

  // ── Admin callable ─────────────────────────────────────────────────
  await reset();
  await check('admin: rol (stranger/dispatcher rad; admin, finance OK; auditor faqat o\'qiydi)', async () => {
    await expectCode(setFee({ feeBps: 100 }, STRANGER), null, 'permission-denied');
    await expectCode(setFee({ feeBps: 100 }, DISPATCHER), null, 'permission-denied');
    await expectCode(setFee({ feeBps: 100 }, AUDITOR), null, 'permission-denied');
    await expectCode(call('adminGetCourierServiceFee', {}, DISPATCHER), null, 'permission-denied');
    await expectCode(fns.adminSetCourierServiceFee.run({ feeBps: 100, reason: 'x y z' }, { auth: null }), null, 'unauthenticated');
    const g = await call('adminGetCourierServiceFee', {}, AUDITOR);
    assert.strictEqual(g.configured, false); assert.strictEqual(g.feeBps, 0); assert.strictEqual(g.autoPayoutEnabled, true);
    const r = await setFee({ feeBps: 100 }, FINANCE);
    assert.strictEqual(r.feeVersion, 1);
  });
  await check('admin: chegaralar 0..5000, butun, sabab ≥3, bo\'sh so\'rov rad — audit yozilmaydi', async () => {
    const auditBefore = (await db.collection('admin_audit').get()).size;
    for (const v of [-1, 5001, 1.5, '100', true]) await expectCode(setFee({ feeBps: v }), 'FEE_BPS_INVALID', 'invalid-argument');
    await expectCode(setFee({ autoPayoutEnabled: 'no' }), 'AUTO_PAYOUT_INVALID');
    await expectCode(setFee({}), 'NOTHING_TO_CHANGE');
    await expectCode(call('adminSetCourierServiceFee', { feeBps: 100, reason: 'ab' }, ADMIN), 'REASON_REQUIRED');
    assert.strictEqual((await db.collection('admin_audit').get()).size, auditBefore);
  });
  await check('admin: 0 va 5000 qabul; versiya + tarix + admin_audit; bir xil qiymat → unchanged', async () => {
    const a = await setFee({ feeBps: 5000 });
    assert.strictEqual(a.feeVersion, 2); assert.strictEqual(a.unchanged, false);
    const same = await setFee({ feeBps: 5000 });
    assert.strictEqual(same.unchanged, true); assert.strictEqual(same.feeVersion, 2);
    const z = await setFee({ feeBps: 0, autoPayoutEnabled: false });
    assert.strictEqual(z.feeVersion, 3); assert.strictEqual(z.autoPayoutEnabled, false);
    const s = (await db.doc('settings/courier_service_fee').get()).data();
    assert.deepStrictEqual([s.feeBps, s.feeVersion, s.autoPayoutEnabled, s.updatedBy], [0, 3, false, ADMIN]);
    const h3 = (await db.doc('courier_service_fee_history/v3').get()).data();
    assert.deepStrictEqual(h3.previous, { feeBps: 5000, feeVersion: 2, autoPayoutEnabled: true });
    const audits = (await db.collection('admin_audit').where('kind', '==', 'courier_service_fee').get()).docs.map((d) => d.data());
    assert.strictEqual(audits.length, 3, 'v1, v2, v3 — unchanged audit yozmaydi');
    const last = audits.find((x) => x.to === '3');
    assert.deepStrictEqual(last.detail, { feeBps: 0, prevFeeBps: 5000, autoPayoutEnabled: false, prevAutoPayoutEnabled: true });
    assert.strictEqual(last.reason, 'sinov');
    const only = await setFee({ autoPayoutEnabled: true });
    assert.strictEqual(only.feeBps, 0, 'faqat kalit — foiz saqlanadi'); assert.strictEqual(only.feeVersion, 4);
  });

  // ── To'lov: asosiy yo'l ────────────────────────────────────────────
  await reset();
  await check('EARNED 96 000, 10 % → hamyon 86 400, fee 9 600, payable 0; ko\'zgu + wallet_ledger + courier_payouts', async () => {
    await setFee({ feeBps: 1000 });
    const e = await earn('shpA', 'leg0', K1, 96000);
    assert.strictEqual(await payable(K1), 0);
    assert.strictEqual(await wallet(K1), 86400);
    assert.strictEqual(await bonus(K1), 86400);
    assert.strictEqual(await feeAcc(), 9600);
    const j = (await journal(e.key)).data();
    assert.strictEqual(j.kind, 'logistics_courier_payout');
    assert.deepStrictEqual(j.legs, [
      { account: `supplier_payable:${K1}`, dr: 96000, cr: 0 },
      { account: `passenger_credit:${K1}`, dr: 0, cr: 86400 },
      { account: cp.FEE_ACCOUNT, dr: 0, cr: 9600 },
    ]);
    assert.strictEqual(j.meta.feeVersion, 1); assert.strictEqual(j.meta.feeBps, 1000);
    const rows = await walletRows(K1);
    assert.strictEqual(rows.length, 1);
    assert.strictEqual(rows[0].amount, 86400);
    assert.deepStrictEqual([rows[0].meta.shipmentId, rows[0].meta.legId, rows[0].meta.fee, rows[0].meta.feeVersion], ['shpA', 'leg0', 9600, 1]);
    const pr = (await db.collection(cp.PAYOUTS).doc(e.key).get()).data();
    assert.deepStrictEqual([pr.gross, pr.fee, pr.net, pr.walletUid, pr.source], [96000, 9600, 86400, K1, 'trigger']);
    await ledgerOk();
  });
  await check('takror trigger + reconcile + parallel → ikkinchi pul yo\'q', async () => {
    const id = 'relayEarned:shpA:leg0';
    const snap = await journal(id);
    await Promise.all([
      fns.onRelayEarnedCourierPayout.run(snap, { params: { entryId: id } }),
      fns.onRelayEarnedCourierPayout.run(snap, { params: { entryId: id } }),
      reconcileRun(),
    ]);
    await reconcileRun();
    assert.strictEqual(await wallet(K1), 86400);
    assert.strictEqual(await bonus(K1), 86400);
    assert.strictEqual(await feeAcc(), 9600);
    assert.strictEqual((await walletRows(K1)).length, 1);
    assert.strictEqual(await payable(K1), 0);
    await ledgerOk();
  });
  await check('parallel BIRINCHI to\'lov (trigger ×3 + reconcile bir vaqtda) → bitta g\'olib', async () => {
    const e = await earn('shpP', 'leg0', K2, 50000, { trigger: false });
    await Promise.all([
      fns.onRelayEarnedCourierPayout.run(e.snap, { params: { entryId: e.id } }),
      fns.onRelayEarnedCourierPayout.run(e.snap, { params: { entryId: e.id } }),
      fns.onRelayEarnedCourierPayout.run(e.snap, { params: { entryId: e.id } }),
      reconcileRun(),
    ]);
    assert.strictEqual(await wallet(K2), 45000);
    assert.strictEqual(await bonus(K2), 45000);
    assert.strictEqual((await walletRows(K2)).length, 1);
    assert.strictEqual(await payable(K2), 0);
    await ledgerOk();
  });

  // ── Yaxlitlash chegaralari (trigger orqali) ────────────────────────
  await reset();
  await check('0 bps → fee oyog\'i yo\'q, hamyonga to\'liq', async () => {
    await setFee({ feeBps: 0 });
    const e = await earn('shpR0', 'leg0', K1, 96001);
    const j = (await journal(e.key)).data();
    assert.strictEqual(j.legs.length, 2);
    assert.strictEqual(await wallet(K1), 96001);
    assert.strictEqual(await feeAcc(), 0);
  });
  await check('1 bps: 96 001 → fee 10 (ceil 9.6001); 10 000 → fee 1', async () => {
    await setFee({ feeBps: 1 });
    await earn('shpR1', 'leg0', K2, 96001);
    assert.strictEqual(await feeAcc(), 10);
    assert.strictEqual(await wallet(K2), 95991);
    await earn('shpR1', 'leg1', K2, 10000);
    assert.strictEqual(await feeAcc(), 11);
    assert.strictEqual(await wallet(K2), 95991 + 9999);
  });
  await check('5000 bps: 96 001 → fee 48 001, net 48 000; 1 so\'m → fee 1, net 0 (hamyon oyog\'i va wallet_ledger yo\'q)', async () => {
    await setFee({ feeBps: 5000 });
    const before = await wallet(K1);
    await earn('shpR5', 'leg0', K1, 96001);
    assert.strictEqual(await wallet(K1) - before, 48000);
    assert.strictEqual(await feeAcc(), 11 + 48001);
    const rowsBefore = (await walletRows(K1)).length;
    const e = await earn('shpR5', 'leg1', K1, 1);
    const j = (await journal(e.key)).data();
    assert.deepStrictEqual(j.legs.map((l) => l.account), [`supplier_payable:${K1}`, cp.FEE_ACCOUNT]);
    assert.strictEqual((await walletRows(K1)).length, rowsBefore);
    assert.strictEqual(await payable(K1), 0);
    await ledgerOk();
  });

  // ── Kill switch ────────────────────────────────────────────────────
  await reset();
  await check('autoPayoutEnabled=false → pul yo\'q, kechiktirilgan qayd; reconcile o\'chiqda ham yo\'q', async () => {
    await setFee({ feeBps: 1000, autoPayoutEnabled: false });
    const e = await earn('shpK', 'leg0', K1, 40000);
    assert.strictEqual(await payable(K1), 40000);
    assert.strictEqual(await wallet(K1), 0);
    assert.strictEqual((await journal(e.key)).exists, false);
    const a = await anomaly(e.key);
    assert.deepStrictEqual([a.status, a.reason, a.amount, a.providerId], ['open', 'auto_payout_disabled', 40000, K1]);
    await reconcileRun();
    assert.strictEqual(await wallet(K1), 0);
    assert.strictEqual((await anomaly(e.key)).attempts, 2);
  });
  await check('yoqilgach reconcile to\'laydi (40 000 → fee 4 000 → hamyon 36 000), qayd yopiladi', async () => {
    await setFee({ autoPayoutEnabled: true });
    await reconcileRun();
    assert.strictEqual(await wallet(K1), 36000);
    assert.strictEqual(await feeAcc(), 4000);
    assert.strictEqual(await payable(K1), 0);
    const a = await anomaly('courierPayout:shpK:leg0');
    assert.strictEqual(a.status, 'resolved');
    assert.strictEqual((await db.collection(cp.PAYOUTS).doc('courierPayout:shpK:leg0').get()).data().source, 'reconcile_open');
    await ledgerOk();
  });

  // ── Anomaliyalar ───────────────────────────────────────────────────
  await reset();
  await check('users yo\'q → anomaliya user_missing, payable joyida; user paydo bo\'lgach reconcile to\'laydi', async () => {
    await setFee({ feeBps: 1000 });
    const e = await earn('shpU', 'leg0', NOUSER, 30000);
    assert.strictEqual(await payable(NOUSER), 30000);
    assert.strictEqual((await anomaly(e.key)).reason, 'user_missing');
    assert.strictEqual((await db.collection('users').doc(NOUSER).get()).exists, false, 'mirror users hujjatini yaratmaydi');
    await db.collection('users').doc(NOUSER).set({ role: 'user', bonusBalance: 0 });
    await reconcileRun();
    assert.strictEqual(await wallet(NOUSER), 27000);
    assert.strictEqual(await payable(NOUSER), 0);
    assert.strictEqual((await anomaly(e.key)).status, 'resolved');
    await ledgerOk();
  });
  await check('9 xonali users hujjati → hamyon passenger_credit:{9 xonali}', async () => {
    await earn('shp9', 'leg0', K9, 20000);
    assert.strictEqual(await wallet(K9.slice(3)), 18000);
    assert.strictEqual(await bonus(K9.slice(3)), 18000);
    assert.strictEqual(await payable(K9), 0);
    await ledgerOk();
  });
  await check('sozlama noto\'g\'ri (qo\'lda 9999) → fee_config_invalid, pul yo\'q', async () => {
    await db.doc('settings/courier_service_fee').set({ feeBps: 9999, feeVersion: 9, autoPayoutEnabled: true });
    const e = await earn('shpBad', 'leg0', K1, 10000);
    assert.strictEqual((await anomaly(e.key)).reason, 'fee_config_invalid');
    assert.strictEqual(await wallet(K1), 0);
    assert.strictEqual(await payable(K1), 10000);
  });
  await check('relay bo\'lmagan jurnal yozuvi → trigger hech narsa qilmaydi', async () => {
    await ledger.postEntry(db, {
      idempotencyKey: 'topup:x', kind: 'test_topup',
      legs: [{ account: 'admin_clearing', dr: 5 }, { account: ledger.passengerCreditAccount(K2), cr: 5 }],
    });
    const before = (await db.collection(cp.ANOMALIES).get()).size;
    await fns.onRelayEarnedCourierPayout.run(await journal('topup:x'), { params: { entryId: 'topup:x' } });
    assert.strictEqual((await db.collection(cp.ANOMALIES).get()).size, before);
    assert.strictEqual((await journal('courierPayout:x')).exists, false);
  });

  // ── creditSupplier (qo'lda) bilan o'zaro ta'sir ────────────────────
  await reset();
  await check('qo\'lda creditSupplier to\'lab qo\'ygan → avtomatik: payable_insufficient, IKKINCHI pul yo\'q', async () => {
    await setFee({ feeBps: 1000, autoPayoutEnabled: false });
    const e = await earn('shpM', 'leg0', K1, 50000);
    const r = await call('creditSupplier', { userPhone: K1, amount: 50000, dateKey: '2026-10-31', module: 'relay' }, ADMIN);
    assert.strictEqual(r.credited, 50000);
    assert.strictEqual(await payable(K1), 0);
    assert.strictEqual(await bonus(K1), 50000);
    await setFee({ autoPayoutEnabled: true });
    await reconcileRun();
    assert.strictEqual(await bonus(K1), 50000, 'avtomatik ikkinchi marta to\'lamadi');
    assert.strictEqual(await payable(K1), 0, 'payable manfiyga tushmadi');
    const a = await anomaly(e.key);
    assert.deepStrictEqual([a.status, a.reason, a.detail.available, a.detail.shortfall], ['open', 'payable_insufficient', 0, 50000]);
    await ledgerOk();
  });
  await check('qoldiq: 2 LEG (40 000 + 60 000), qo\'lda 40 000 → avtomatik yig\'indi + qo\'lda + qoldiq == ishlab topilgan; payable ≥ 0', async () => {
    await setFee({ autoPayoutEnabled: false });
    await earn('shpQ', 'leg0', K2, 40000);
    await earn('shpQ', 'leg1', K2, 60000);
    await call('creditSupplier', { userPhone: K2, amount: 40000, dateKey: '2026-10-31', module: 'relay' }, ADMIN);
    assert.strictEqual(await payable(K2), 60000);
    await setFee({ autoPayoutEnabled: true });
    await reconcileRun();
    const pays = (await db.collection(cp.PAYOUTS).where('providerId', '==', K2).get()).docs.map((d) => d.data());
    const autoGross = pays.reduce((s, p) => s + p.gross, 0);
    const left = await payable(K2);
    assert.ok(left >= 0, 'payable ≥ 0');
    assert.strictEqual(pays.length, 1, 'faqat bittasi sig\'adi, ikkinchisi anomaliya');
    assert.strictEqual(40000 + autoGross + left, 100000, 'qo\'lda + avtomatik + qoldiq == ishlab topilgan');
    const open = (await db.collection(cp.ANOMALIES).where('status', '==', 'open').get()).docs.map((d) => d.data());
    assert.ok(open.some((x) => x.providerId === K2 && x.reason === 'payable_insufficient'));
    // creditSupplier qolgan qoldiq bo'yicha ham ishlaydi:
    if (left > 0) {
      await call('creditSupplier', { userPhone: K2, amount: left, dateKey: '2026-11-01', module: 'relay' }, ADMIN);
      assert.strictEqual(await payable(K2), 0);
    }
    await ledgerOk();
  });

  // ── Reconcile: o'tkazib yuborilgan trigger ─────────────────────────
  await reset();
  await check('trigger ishlamagan EARNED → reconcile oynada topadi va to\'laydi; ikkinchi reconcile — yo\'q', async () => {
    await setFee({ feeBps: 250 });
    const e = await earn('shpMiss', 'leg0', K1, 40000, { trigger: false });
    assert.strictEqual(await wallet(K1), 0);
    await reconcileRun();
    assert.strictEqual(await wallet(K1), 39000, '40 000 − 1 000 (2,5 %)');
    assert.strictEqual((await db.collection(cp.PAYOUTS).doc(e.key).get()).data().source, 'reconcile_scan');
    await reconcileRun();
    assert.strictEqual(await wallet(K1), 39000);
    await ledgerOk();
  });
  await check('getter: oxirgi to\'lovlar, ochiq anomaliyalar, fee hisobi balansi', async () => {
    await earn('shpG', 'leg0', NOUSER, 1000);
    const g = await call('adminGetCourierServiceFee', {}, ADMIN);
    assert.strictEqual(g.feeBps, 250); assert.strictEqual(g.feeVersion, 1); assert.strictEqual(g.autoPayoutEnabled, true);
    assert.strictEqual(g.recentPayouts.length, 1);
    assert.deepStrictEqual([g.recentPayouts[0].gross, g.recentPayouts[0].fee, g.recentPayouts[0].net], [40000, 1000, 39000]);
    assert.strictEqual(g.openAnomalies.length, 1);
    assert.strictEqual(g.openAnomalies[0].reason, 'user_missing');
    assert.strictEqual(g.feeAccountBalance, 1000);
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed}/${results.length} courier payout CF checks passed.`);
  if (failed) process.exitCode = 1;
}
main().catch((e) => { console.error('FATAL', e); process.exitCode = 1; }).finally(() => {
  // index.js ochiq handle'lari (axios va h.k.) jarayonni ushlab turmasin.
  setTimeout(() => process.exit(process.exitCode || 0), 200);
});
