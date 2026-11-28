/**
 * Taksi komissiyasi admin tomonidan o'zgartiriladi (ega 2026-11-28) — HAQIQIY Firestore (Emulator).
 * `taxi_commission/current {bps, version}` + tarix `taxi_commission_history/v{n}` + `admin_audit`;
 * reysga qo'llangan `rateBps` / `taxiCommissionVersion`; reprice reys snapshot'ida.
 *
 *   firebase emulators:exec --only firestore --project demo-taxi-commission "node test/taxi_commission_cf.test.js"
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-taxi-commission';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const settlementLedger = require('../settlement_ledger');
const { attachTaxiBilling } = require('../taxi_billing');
const caps = require('../capabilities_model');

const DRIVER = '998901120001';
const ACC = 'accDRVCOMM00000000000A';
const ADMIN = '998901120002';
const SUPER = '998901120003';
const DISPATCHER = '998901120004';
const NOW0 = new Date('2026-10-06T06:00:00Z');

const digits = (v) => String(v || '').replace(/\D/g, '');
const canonicalUid = (v) => { const d = digits(v); return d.length === 9 ? `998${d}` : d; };
const callerPhone = (ctx) => digits(ctx.auth.token.phone_number);
/** index.js `requireCallerRoles` bilan bir xil shartnoma (users.role). */
async function requireCallerRoles(context, roles, msg) {
  if (!context || !context.auth) throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  const uid = canonicalUid(callerPhone(context));
  const role = ((await db.collection('users').doc(uid).get()).data() || {}).role || 'user';
  if (!roles.includes(role)) throw new functions.https.HttpsError('permission-denied', msg || 'Insufficient role');
  return uid;
}
const exportsObj = {};
const api = attachTaxiBilling(exportsObj, {
  functions, db, admin, callerPhone, canonicalUid, settlementLedger, requireCallerRoles,
  notifyUserInApp: async () => {}, now: () => NOW0,
});
const ctxOf = (p) => ({ auth: { token: { phone_number: `+${p}` } } });
const ctx = ctxOf(DRIVER);

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const balance = async () => (await db.collection(settlementLedger.COL_ACCOUNTS).doc(settlementLedger.passengerCreditAccount(DRIVER)).get()).data()?.balance || 0;
const trip = async (id) => (await db.collection('taxi_trips').doc(id).get()).data();
const pub = (over = {}) => api.publish({ farePerSeat: 350000, from: 'Urganch', to: 'Toshkent', scheduleDate: '2026-10-07', startTime: '08:00',
  departureAt: '2026-10-07T03:00:00Z', ...over }, ctx);
const setBps = (bps, who = ADMIN, extra = {}) => api.adminSetCommission({ bps, reason: 'test', ...extra }, ctxOf(who));
async function expectReject(p, code, detailCode) {
  await assert.rejects(p, (e) => {
    assert.strictEqual(e.code, code, `${e.code}: ${e.message}`);
    if (detailCode) assert.strictEqual((e.details || {}).code, detailCode);
    return true;
  });
}

async function main() {
  await clearEmulator();
  await db.collection('users').doc(DRIVER).set({ role: 'user', accountId: ACC, bonusBalance: 0 });
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(SUPER).set({ role: 'superadmin' });
  await db.collection('users').doc(DISPATCHER).set({ role: 'dispatcher' });
  await db.collection('provider_capabilities').doc(ACC).set({
    identity: { accountId: ACC, primaryUid: DRIVER }, taxi: { active: true },
    status: { taxi: 'verified' }, window: { taxi: { billingGraceUntil: null } },
  });
  await db.collection('service_agreements').doc(ACC).set({ taxi: { version: caps.AGREEMENT_VERSIONS.taxi, acceptedAt: NOW0 } });
  await settlementLedger.postEntry(db, {
    idempotencyKey: `topup:${DRIVER}:comm`, kind: 'test_topup',
    legs: [{ account: 'admin_clearing', dr: 500000 }, { account: settlementLedger.passengerCreditAccount(DRIVER), cr: 500000 }],
  });

  await check('C0 export: adminGetTaxiCommission / adminSetTaxiCommission ro\'yxatda', () => {
    assert.strictEqual(typeof exportsObj.adminGetTaxiCommission, 'function');
    assert.strictEqual(typeof exportsObj.adminSetTaxiCommission, 'function');
  });

  let oldTripId;
  await check('C1 sozlama YO\'Q → 200 bps (avvalgidek): quote 28 000, reys rateBps 200, taxiCommissionVersion 0', async () => {
    const g = await api.adminGetCommission({}, ctxOf(ADMIN));
    assert.deepStrictEqual([g.bps, g.version, g.configured, g.defaultBps], [200, 0, false, 200]);
    const q = await api.quote({ farePerSeat: 350000 }, ctx);
    assert.deepStrictEqual([q.feeAmount, q.rateBps, q.taxiCommissionVersion], [28000, 200, 0]);
    const r = await pub();
    oldTripId = r.tripId;
    const t = await trip(r.tripId);
    assert.deepStrictEqual([t.feeAmount, t.rateBps, t.taxiCommissionVersion, t.rate], [28000, 200, 0, 0.02]);
  });

  let tripId300;
  await check('C2 admin 300 bps qo\'ydi → v1, tarix v1 (previous 200), admin_audit; yangi reys 42 000, rateBps 300, ledger meta', async () => {
    const s = await setBps(300);
    assert.deepStrictEqual([s.ok, s.version, s.bps, s.unchanged], [true, 1, 300, false]);
    const cur = (await db.doc('taxi_commission/current').get()).data();
    assert.deepStrictEqual([cur.bps, cur.version, cur.updatedBy], [300, 1, ADMIN]);
    const h = (await db.doc('taxi_commission_history/v1').get()).data();
    assert.deepStrictEqual([h.bps, h.previous.bps, h.previous.version, h.previous.configured, h.changedBy], [300, 200, 0, false, ADMIN]);
    const au = await db.collection('admin_audit').where('kind', '==', 'taxi_commission').get();
    assert.strictEqual(au.size, 1);
    assert.deepStrictEqual([au.docs[0].data().from, au.docs[0].data().to, au.docs[0].data().detail.bps], ['0', '1', 300]);
    const before = await balance();
    const r = await pub();
    tripId300 = r.tripId;
    const t = await trip(r.tripId);
    assert.deepStrictEqual([r.feeAmount, t.rateBps, t.taxiCommissionVersion, t.rate], [42000, 300, 1, 0.03]);
    assert.strictEqual(await balance(), before - 42000);
    const j = (await db.collection(settlementLedger.COL_JOURNAL).doc(`taxiFee:${r.tripId}:v1`).get()).data();
    assert.ok(j, 'journal');
  });

  await check('C3 IDEMPOTENT: xuddi shu 300 qayta → unchanged, v2 YO\'Q, audit ko\'paymaydi', async () => {
    const s = await setBps(300, SUPER);
    assert.deepStrictEqual([s.version, s.unchanged], [1, true]);
    assert.strictEqual((await db.doc('taxi_commission_history/v2').get()).exists, false);
    assert.strictEqual((await db.collection('admin_audit').where('kind', '==', 'taxi_commission').get()).size, 1);
  });

  await check('C4 ruxsat: user / dispatcher / haydovchi → permission-denied; autentsiz → unauthenticated (o\'qish ham)', async () => {
    await expectReject(setBps(100, DISPATCHER), 'permission-denied');
    await expectReject(setBps(100, DRIVER), 'permission-denied');
    await expectReject(api.adminGetCommission({}, ctxOf(DISPATCHER)), 'permission-denied');
    await expectReject(api.adminSetCommission({ bps: 100 }, {}), 'unauthenticated');
    assert.strictEqual((await db.doc('taxi_commission/current').get()).data().bps, 300);
  });

  await check('C5 negativ kiritish: \'250\' / 2.5 / -1 / 10001 → invalid-argument BPS_INVALID, yozuv yo\'q', async () => {
    for (const bad of ['250', 2.5, -1, 10001]) await expectReject(setBps(bad), 'invalid-argument', 'BPS_INVALID');
    assert.strictEqual((await db.doc('taxi_commission/current').get()).data().version, 1);
  });

  await check('C6 poyga: expectedVersion eskirgan → aborted VERSION_CONFLICT; to\'g\'risi → v2', async () => {
    await expectReject(setBps(250, ADMIN, { expectedVersion: 0 }), 'aborted', 'VERSION_CONFLICT');
    const s = await setBps(250, ADMIN, { expectedVersion: 1 });
    assert.deepStrictEqual([s.version, s.bps], [2, 250]);
  });

  await check('C7 9-qoida: stavka 250 ga o\'zgargach ham 300 da e\'lon qilingan reys reprice 300 da (400k → 48 000, farq 6 000)', async () => {
    const before = await balance();
    const rp = await api.reprice({ tripId: tripId300, farePerSeat: 400000 }, ctx);
    assert.deepStrictEqual([rp.status, rp.delta, rp.feeAmount], ['ok', 6000, 48000]);
    assert.strictEqual(await balance(), before - 6000);
    assert.strictEqual((await trip(tripId300)).rateBps, 300);
  });

  await check('C8 eski reys (rateBps yo\'q) reprice → 200 bps (avvalgi xulq)', async () => {
    await db.collection('taxi_trips').doc(oldTripId).update({ rateBps: admin.firestore.FieldValue.delete() });
    const rp = await api.reprice({ tripId: oldTripId, farePerSeat: 400000 }, ctx);
    assert.deepStrictEqual([rp.delta, rp.feeAmount], [4000, 32000]);
  });

  await check('C9 chegara: 0 bps → yangi reys fee 0, published (pulsiz), rateBps 0; quote ham 0', async () => {
    await setBps(0, SUPER);
    const q = await api.quote({ farePerSeat: 350000 }, ctx);
    assert.deepStrictEqual([q.feeAmount, q.rateBps, q.taxiCommissionVersion], [0, 0, 3]);
    const before = await balance();
    const r = await pub();
    assert.strictEqual(r.status, 'published');
    assert.deepStrictEqual([(await trip(r.tripId)).rateBps, (await trip(r.tripId)).feeAmount], [0, 0]);
    assert.strictEqual(await balance(), before);
  });

  await check('C10 klient rateBps yuborsa — e\'tiborsiz (server sozlamasi)', async () => {
    await setBps(200, ADMIN);
    const q = await api.quote({ farePerSeat: 350000, rateBps: 1, rate: 0.0001 }, ctx);
    assert.deepStrictEqual([q.feeAmount, q.rateBps], [28000, 200]);
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}
main().catch((e) => { console.error(e); process.exit(1); });
