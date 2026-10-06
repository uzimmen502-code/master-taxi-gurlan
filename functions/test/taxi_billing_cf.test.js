/**
 * Taxi billing — HAQIQIY ledger bilan (Firestore Emulator, Admin SDK).
 *
 *   firebase emulators:exec --only firestore --project demo-taxi-billing \
 *     "node functions/test/taxi_billing_cf.test.js"
 *
 * Qulflanadi (D-TAXI-13…23):
 *   - to'lovsiz `published` YO'Q; wallet yetmasa `payment_required`
 *   - komissiya BIR MARTA (idempotent), ledger Σdr == Σcr
 *   - narx oshsa farq, pasaysa bir martalik refund
 *   - bekor → wallet'ga refund; jo'nashdan keyin «bekor» → refund yo'q
 *   - starter/grace/shadow → fee 0; verification_required → yopiq
 *   - yolg'on otmena `confirmed` → reclaim + xabar
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-taxi-billing';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const settlementLedger = require('../settlement_ledger');
const { attachTaxiBilling, EARNINGS_ACCOUNT } = require('../taxi_billing');
const caps = require('../capabilities_model');

const DRIVER = '998901110001';
const ACC = 'accDRV000000000000000A';
const NOW0 = new Date('2026-10-06T06:00:00Z');
let clock = NOW0;
const notified = [];

const digits = (v) => String(v || '').replace(/\D/g, '');
const api = attachTaxiBilling({}, {
  functions, db, admin,
  callerPhone: (ctx) => digits(ctx.auth.token.phone_number),
  canonicalUid: (v) => { const d = digits(v); return d.length === 9 ? `998${d}` : d; },
  settlementLedger,
  notifyUserInApp: async (m) => { notified.push(m); },
  now: () => clock,
});
const ctx = { auth: { token: { phone_number: `+${DRIVER}` } } };

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => d.ref.delete()));
}
async function reset({ status = 'verified', graceUntil = null, flag = true, agreement = true, wallet = 100000 } = {}) {
  clock = NOW0;
  notified.length = 0;
  await Promise.all(['users', 'provider_capabilities', 'service_agreements', 'module_config',
    'taxi_trips', 'taxi_price_changes', 'taxi_fraud_cases', settlementLedger.COL_JOURNAL,
    settlementLedger.COL_ACCOUNTS].map(wipe));
  await db.collection('users').doc(DRIVER).set({ role: 'user', accountId: ACC, bonusBalance: 0 });
  await db.collection('provider_capabilities').doc(ACC).set({
    identity: { accountId: ACC, primaryUid: DRIVER },
    taxi: { active: true },
    status: { taxi: status },
    window: { taxi: { billingGraceUntil: graceUntil } },
  });
  if (agreement) {
    await db.collection('service_agreements').doc(ACC).set({ taxi: { version: caps.AGREEMENT_VERSIONS.taxi, acceptedAt: NOW0 } });
  }
  await db.collection('module_config').doc('global').set({ taxiBillingEnabled: flag });
  if (wallet > 0) {
    await settlementLedger.postEntry(db, {
      idempotencyKey: `topup:${DRIVER}:test`, kind: 'test_topup',
      legs: [{ account: 'admin_clearing', dr: wallet }, { account: settlementLedger.passengerCreditAccount(DRIVER), cr: wallet }],
    });
  }
}
const balance = async () => (await db.collection(settlementLedger.COL_ACCOUNTS).doc(settlementLedger.passengerCreditAccount(DRIVER)).get()).data()?.balance || 0;
const earnings = async () => (await db.collection(settlementLedger.COL_ACCOUNTS).doc(EARNINGS_ACCOUNT).get()).data()?.balance || 0;
const trip = async (id) => (await db.collection('taxi_trips').doc(id).get()).data();
const pub = (over = {}) => api.publish({ farePerSeat: 350000, from: 'Urganch', to: 'Toshkent', scheduleDate: '2026-10-07', startTime: '08:00',
  departureAt: '2026-10-07T03:00:00Z', originLat: 41.55, originLng: 60.63, driverLat: 41.55, driverLng: 60.63, ...over }, ctx);

async function main() {
  // Flag keshini har resetda yangilash uchun: 60 s kesh — testlar bir xil flag bilan guruhlanadi.
  await reset();
  await check('quote: 350 000 → 28 000, wallet 100 000, sufficient', async () => {
    const q = await api.quote({ farePerSeat: 350000 }, ctx);
    assert.strictEqual(q.allowed, true); assert.strictEqual(q.feeAmount, 28000);
    assert.strictEqual(q.billable, true); assert.strictEqual(q.sufficient, true);
  });
  let tripId;
  await check('publish: komissiya yechildi, `published`, snapshot (D-TAXI-13, 21)', async () => {
    const r = await pub();
    tripId = r.tripId;
    assert.strictEqual(r.status, 'published'); assert.strictEqual(r.feeAmount, 28000);
    assert.strictEqual(await balance(), 72000); assert.strictEqual(await earnings(), 28000);
    const t = await trip(tripId);
    assert.strictEqual(t.seatBasis, 4); assert.strictEqual(t.rate, 0.02); assert.strictEqual(t.grossBasis, 1400000);
    assert.strictEqual(t.billingVersion, 1); assert.ok(t.chargedAt); assert.ok(t.ledgerEntryId);
  });
  await check('ledger: Σdr == Σcr, users.bonusBalance ko\'zgusi', async () => {
    const j = await db.collection(settlementLedger.COL_JOURNAL).doc(`taxiFee:${tripId}:v1`).get();
    assert.ok(j.exists);
    const dr = j.data().legs.reduce((s, l) => s + l.dr, 0); const cr = j.data().legs.reduce((s, l) => s + l.cr, 0);
    assert.strictEqual(dr, cr);
    assert.strictEqual((await db.collection('users').doc(DRIVER).get()).data().bonusBalance, 72000);
  });
  await check('IDEMPOTENT: xuddi shu kalit bilan qayta yozilmaydi (D-TAXI-20)', async () => {
    const r = await api.charge({ usersDocId: DRIVER, phone: DRIVER, tripId, amount: 28000, version: 1, kind: 'taxi_fee', meta: {} });
    assert.strictEqual(r.idempotent, true); assert.strictEqual(await balance(), 72000);
  });
  await check('reprice 200k→350k mantiq: oshsa FARQ olinadi (D-TAXI-11)', async () => {
    const r = await pub({ farePerSeat: 200000 }); // fee 16 000, balance 56 000
    const rp = await api.reprice({ tripId: r.tripId, farePerSeat: 350000 }, ctx);
    assert.strictEqual(rp.status, 'ok'); assert.strictEqual(rp.delta, 12000);
    assert.strictEqual((await trip(r.tripId)).feeAmount, 28000);
    assert.strictEqual(await balance(), 44000);
    assert.strictEqual((await db.collection('taxi_price_changes').where('tripId', '==', r.tripId).get()).size, 1);
  });
  await check('reprice pasaysa: BIR MARTA refund, ikkinchisida yo\'q (D-TAXI-12)', async () => {
    const r = await pub({ farePerSeat: 300000 }); // fee 24 000 → balance 20 000
    const a = await api.reprice({ tripId: r.tripId, farePerSeat: 250000 }, ctx); // 20 000 → refund 4 000
    assert.strictEqual(a.delta, -4000); assert.strictEqual(await balance(), 24000);
    const b = await api.reprice({ tripId: r.tripId, farePerSeat: 200000 }, ctx);
    assert.strictEqual(b.refundLimited, true); assert.strictEqual(await balance(), 24000);
  });
  await check('wallet yetmasa: `payment_required`, e\'lon YO\'Q (D-TAXI-23)', async () => {
    const r = await pub({ farePerSeat: 400000 }); // 32 000 > 24 000
    assert.strictEqual(r.status, 'payment_required');
    assert.strictEqual((await trip(r.tripId)).status, 'payment_required');
    assert.strictEqual(await balance(), 24000, 'qisman yechilmagan');
  });
  await check('cancel → komissiya wallet\'ga refund (D-TAXI-15)', async () => {
    const r = await pub({ farePerSeat: 250000 }); // 20 000 → 4 000
    const c = await api.cancel({ tripId: r.tripId, hadAvaBooking: true, driverLat: 41.55, driverLng: 60.63 }, ctx);
    assert.strictEqual(c.status, 'cancelled'); assert.strictEqual(c.refunded, true);
    assert.strictEqual(await balance(), 24000);
    const c2 = await api.cancel({ tripId: r.tripId }, ctx);
    assert.strictEqual(c2.idempotent, true); assert.strictEqual(await balance(), 24000, 'ikki marta refund');
  });
  await check('YOLG\'ON OTMENA: keyingi teskari reys + GPS → reclaim + xabar (D-TAXI-17, 18)', async () => {
    clock = new Date('2026-10-07T15:00:00Z'); // 12 soatdan ko'p o'tdi, jo'nashdan keyin
    await db.collection('taxi_trips').doc((await db.collection('taxi_trips').where('status', '==', 'cancelled').get()).docs[0].id)
      .update({ 'location.destLat': 41.3111, 'location.destLng': 69.2797, cancelledAt: new Date('2026-10-07T02:00:00Z') });
    const before = await balance();
    const r = await pub({ from: 'Toshkent', to: 'Urganch', farePerSeat: 100000, driverLat: 41.3111, driverLng: 69.2797, departureAt: '2026-10-08T03:00:00Z' });
    assert.strictEqual(r.status, 'published');
    const cases = await db.collection('taxi_fraud_cases').where('type', '==', 'fake_cancel').get();
    assert.strictEqual(cases.size, 1); assert.strictEqual(cases.docs[0].data().verdict, 'confirmed');
    // Yangi fee 8 000 (24 000 → 16 000), keyin reclaim 20 000: wallet'da 16 000
    // bor — shunchasi olinadi, 4 000 QARZ (CANCEL-6), manfiy balans YO'Q.
    assert.strictEqual(before, 24000);
    assert.strictEqual(await balance(), 0);
    const cap = (await db.collection('provider_capabilities').doc(ACC).get()).data();
    assert.strictEqual(cap.debt.taxi, 4000);
    assert.strictEqual(notified.length, 1);
    assert.ok(notified[0].body.includes('qayta hisobdan yechildi'));
  });
  await reset(); // oldingi holatdagi qarz bu tekshiruvga aloqador emas
  await check('jo\'nashdan 2 soat keyin «bekor» → completed, refund YO\'Q', async () => {
    clock = new Date('2026-10-06T06:00:00Z');
    const r = await pub({ farePerSeat: 100000, departureAt: '2026-10-06T07:00:00Z' });
    clock = new Date('2026-10-06T10:00:00Z');
    const b = await balance();
    const c = await api.cancel({ tripId: r.tripId }, ctx);
    assert.strictEqual(c.status, 'completed'); assert.strictEqual(c.refunded, false);
    assert.strictEqual(await balance(), b);
  });

  // ── D-TAXI-CANCEL-3: RESCHEDULE ──────────────────────────────────────
  await reset();
  await check('reschedule: tripId va komissiya SAQLANADI, faqat sana/vaqt (CANCEL-3)', async () => {
    const r = await pub({ farePerSeat: 350000 }); // 28 000 → 72 000
    const rs = await api.reschedule({ tripId: r.tripId, departureAt: '2026-10-09T03:00:00Z', scheduleDate: '2026-10-09', startTime: '08:00' }, ctx);
    assert.strictEqual(rs.rescheduled, true); assert.strictEqual(rs.billing.status, 'unchanged');
    const t = await trip(r.tripId);
    assert.strictEqual(t.status, 'published'); assert.strictEqual(t.scheduleDate, '2026-10-09'); assert.strictEqual(t.feeAmount, 28000);
    assert.strictEqual(await balance(), 72000, 'refund ham, qayta charge ham YO\'Q');
    assert.strictEqual((await db.collection('taxi_reschedules').where('tripId', '==', r.tripId).get()).size, 1);
  });
  await check('reschedule + narx oshdi (350k→400k): faqat FARQ 4 000 (CANCEL-3)', async () => {
    const r = await pub({ farePerSeat: 350000 }); // 72 000 → 44 000
    const rs = await api.reschedule({ tripId: r.tripId, departureAt: '2026-10-10T03:00:00Z', farePerSeat: 400000 }, ctx);
    assert.strictEqual(rs.billing.delta, 4000); assert.strictEqual(rs.billing.feeAmount, 32000);
    assert.strictEqual(await balance(), 40000);
  });

  // ── D-TAXI-CANCEL-6: QARZ ────────────────────────────────────────────
  await reset({ wallet: 30000 });
  await check('reclaim wallet yetmasa → bor qismi olinadi, qolgani QARZ (CANCEL-6)', async () => {
    const r = await pub({ farePerSeat: 350000 }); // 30 000 → 2 000
    await api.cancel({ tripId: r.tripId, hadAvaBooking: true, driverLat: 41.55, driverLng: 60.63 }, ctx); // +28 000 → 30 000
    // Haydovchi pulni boshqa yerga sarfladi (wallet 3 000 qoldi).
    await settlementLedger.postEntry(db, {
      idempotencyKey: 'spend:test', kind: 'test_spend',
      legs: [{ account: settlementLedger.passengerCreditAccount(DRIVER), dr: 27000 }, { account: 'admin_clearing', cr: 27000 }],
    });
    await db.collection('taxi_trips').doc(r.tripId).update({ 'location.destLat': 41.3111, 'location.destLng': 69.2797, cancelledAt: new Date('2026-10-07T02:00:00Z') });
    clock = new Date('2026-10-07T15:00:00Z');
    await db.collection('module_config').doc('global').set({ taxiBillingEnabled: false }); // yangi reys fee 0 (faqat reclaim ko'rinsin)
    const freshApi = attachTaxiBilling({}, { functions, db, admin, callerPhone: (c) => digits(c.auth.token.phone_number), canonicalUid: (v) => digits(v), settlementLedger, notifyUserInApp: async () => {}, now: () => clock });
    await freshApi.publish({ farePerSeat: 100000, from: 'Toshkent', to: 'Urganch', driverLat: 41.3111, driverLng: 69.2797, departureAt: '2026-10-08T03:00:00Z' }, ctx);
    const t = await trip(r.tripId);
    assert.strictEqual(t.fraudVerdict, 'confirmed');
    assert.strictEqual(t.reclaimedAmount, 3000); assert.strictEqual(t.outstandingTaxiFee, 25000);
    assert.strictEqual(await balance(), 0, 'manfiyga tushmaydi');
    const cap = (await db.collection('provider_capabilities').doc(ACC).get()).data();
    assert.strictEqual(cap.debt.taxi, 25000, 'qarz capability\'da, ikkinchi ledger yo\'q');
  });
  await check('qarz bor + wallet yetmasa → yangi reys YOPIQ (outstanding_debt)', async () => {
    await db.collection('module_config').doc('global').set({ taxiBillingEnabled: true });
    const liveApi = attachTaxiBilling({}, { functions, db, admin, callerPhone: (c) => digits(c.auth.token.phone_number), canonicalUid: (v) => digits(v), settlementLedger, now: () => clock });
    await assert.rejects(() => liveApi.publish({ farePerSeat: 100000, from: 'Urganch', to: 'Xiva' }, ctx),
      (e) => e.details && e.details.reason === 'outstanding_debt' && e.details.outstanding === 25000);
  });
  await check('top-up → qarz AVVAL yopiladi, keyin yangi komissiya (CANCEL-6)', async () => {
    await settlementLedger.postEntry(db, {
      idempotencyKey: 'topup:test2', kind: 'test_topup',
      legs: [{ account: 'admin_clearing', dr: 40000 }, { account: settlementLedger.passengerCreditAccount(DRIVER), cr: 40000 }],
    });
    const liveApi = attachTaxiBilling({}, { functions, db, admin, callerPhone: (c) => digits(c.auth.token.phone_number), canonicalUid: (v) => digits(v), settlementLedger, now: () => clock });
    const r = await liveApi.publish({ farePerSeat: 100000, from: 'Urganch', to: 'Xiva', departureAt: '2026-10-09T03:00:00Z' }, ctx); // fee 8 000
    assert.strictEqual(r.status, 'published');
    assert.strictEqual(await balance(), 40000 - 25000 - 8000);
    const cap = (await db.collection('provider_capabilities').doc(ACC).get()).data();
    assert.strictEqual(cap.debt.taxi, 0);
  });

  // ── holatlar ─────────────────────────────────────────────────────────
  await reset({ status: 'starter' });
  await check('starter: ishlaydi, fee 0 (D-TAXI-1, 3)', async () => {
    const r = await pub();
    assert.strictEqual(r.status, 'published'); assert.strictEqual(r.feeAmount, 0);
    assert.strictEqual(await balance(), 100000);
  });
  await reset({ status: 'verification_required' });
  await check('verification_required: pullik e\'lon YOPIQ, sabab aniq (D-TAXI-5)', async () => {
    await assert.rejects(() => pub(), (e) => e.code === 'failed-precondition' && e.details.reason === 'taxi_verification_required');
  });
  await reset({ graceUntil: new Date('2027-02-06T00:00:00Z') });
  await check('T-6 billing grace: verified, lekin fee 0', async () => {
    const q = await api.quote({ farePerSeat: 350000 }, ctx);
    assert.strictEqual(q.billable, false); assert.strictEqual(q.feeAmount, 0); assert.strictEqual(q.quotedFee, 28000);
  });
  await reset({ agreement: false });
  await check('kelishuvsiz e\'lon yo\'q (D-TAXI-24)', async () => {
    const q = await api.quote({ farePerSeat: 350000 }, ctx);
    assert.strictEqual(q.allowed, false); assert.strictEqual(q.reason, 'agreement_required');
    await assert.rejects(() => pub(), (e) => e.details.reason === 'agreement_required');
  });
  // Flag keshi 60 s — shadow testi uchun yangi API nusxasi.
  const shadowApi = attachTaxiBilling({}, { functions, db, admin, callerPhone: (c) => digits(c.auth.token.phone_number), canonicalUid: (v) => digits(v), settlementLedger, now: () => clock });
  await reset({ flag: false });
  await check('SHADOW MODE: flag o\'chiq → snapshot yoziladi, pul olinmaydi (42-qoida)', async () => {
    const r = await shadowApi.publish({ farePerSeat: 350000, from: 'Urganch', to: 'Toshkent' }, ctx);
    assert.strictEqual(r.status, 'published'); assert.strictEqual(r.feeAmount, 0); assert.strictEqual(r.billingMode, 'shadow');
    assert.strictEqual((await trip(r.tripId)).quotedFee, 28000, 'hisob ko\'rinadi, pul yo\'q');
    assert.strictEqual(await balance(), 100000);
  });
  await check('FRAUD SHADOW: fee\'siz bekor ham BAHOLANADI — verdict yoziladi, pul harakatlanmaydi', async () => {
    clock = new Date('2026-10-06T06:00:00Z');
    const r = await shadowApi.publish({ farePerSeat: 350000, from: 'Urganch', to: 'Toshkent', departureAt: '2026-10-07T03:00:00Z' }, ctx);
    await shadowApi.cancel({ tripId: r.tripId, hadAvaBooking: true }, ctx);
    await db.collection('taxi_trips').doc(r.tripId).update({ 'location.destLat': 41.3111, 'location.destLng': 69.2797, cancelledAt: new Date('2026-10-07T02:00:00Z') });
    clock = new Date('2026-10-07T15:00:00Z');
    await shadowApi.publish({ farePerSeat: 100000, from: 'Toshkent', to: 'Urganch', driverLat: 41.3111, driverLng: 69.2797, departureAt: '2026-10-08T03:00:00Z' }, ctx);
    const t = await trip(r.tripId);
    assert.strictEqual(t.fraudReviewed, true);
    assert.strictEqual(t.fraudVerdict, 'confirmed', 'shadow davrida ham verdict chiqadi');
    assert.strictEqual(t.reclaimed, undefined, 'fee 0 edi — qaytarib oladigan narsa yo\'q');
    assert.strictEqual(await balance(), 100000);
    assert.strictEqual((await db.collection('taxi_fraud_cases').where('tripId', '==', r.tripId).get()).size, 1);
  });

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} taxi billing CF checks passed.`);
  if (failed.length) process.exitCode = 1;
}
main().catch((e) => { console.error('FATAL', e); process.exitCode = 1; });
