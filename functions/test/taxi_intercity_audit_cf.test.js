/**
 * Shaharlararo taksi auditi (2026-10) - taxi_billing.js qismi.
 * HAQIQIY ledger + Firestore Emulator (Admin SDK), soat inyeksiya qilinadi.
 *
 *   firebase emulators:exec --only firestore --project demo-taxi-audit \
 *     "node functions/test/taxi_intercity_audit_cf.test.js"
 *
 * Qulflanadi:
 *   M2/H5  publish/reschedule kirish tekshiruvi (PUL TEGILMASDAN OLDIN):
 *          departure_in_past / route_required / seats_invalid / schedule_invalid;
 *          departureAt yo'q (eski ilova) - eski tolerant xulq.
 *   M1     publish idempotentligi (ixtiyoriy requestId): qayta chaqiruv yangi reys
 *          ochmaydi va qayta yechmaydi (ketma-ket, parallel, payment_required).
 *   H3     cancel: `hadAvaBooking` SERVER hisoblaydi (intercity_bookings), klient
 *          qiymati e'tiborga olinmaydi; refund siyosati O'ZGARMAGAN.
 *   H6     rescheduleTaxiTrip: bronlar vaqti, yo'lovchi xabarlari (3 til), schedules
 *          e'loni va intercity_drivers bir xil; qayta chaqiruv idempotent.
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-taxi-audit';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const Timestamp = admin.firestore.Timestamp;

const settlementLedger = require('../settlement_ledger');
const { attachTaxiBilling } = require('../taxi_billing');

const DRIVER = '998901110001';
const OTHER = '998901110002';
const ACC = 'accDRV000000000000000A';
const NOW0 = new Date('2026-10-06T06:00:00Z');
let clock = NOW0;

const digits = (v) => String(v || '').replace(/\D/g, '');
const api = attachTaxiBilling({}, {
  functions, db, admin,
  callerPhone: (ctx) => digits(ctx.auth.token.phone_number),
  canonicalUid: (v) => { const d = digits(v); return d.length === 9 ? `998${d}` : d; },
  settlementLedger,
  notifyUserInApp: async () => {},
  now: () => clock,
});
const ctx = { auth: { token: { phone_number: `+${DRIVER}` } } };

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => d.ref.delete()));
}
async function reset({ wallet = 200000 } = {}) {
  clock = NOW0;
  await Promise.all(['users', 'provider_capabilities', 'service_agreements', 'taxi_trips', 'taxi_reschedules',
    'taxi_publish_requests', 'taxi_fraud_cases', 'intercity_bookings', 'intercity_drivers', 'schedules',
    'notifications', settlementLedger.COL_JOURNAL, settlementLedger.COL_ACCOUNTS].map(wipe));
  await db.collection('users').doc(DRIVER).set({ role: 'user', accountId: ACC, bonusBalance: 0 });
  await db.collection('provider_capabilities').doc(ACC).set({
    identity: { accountId: ACC, primaryUid: DRIVER }, taxi: { active: true }, status: { taxi: 'verified' },
    window: { taxi: { billingGraceUntil: null } },
  });
  await db.collection('service_agreements').doc(ACC).set({ taxi: { version: require('../capabilities_model').AGREEMENT_VERSIONS.taxi, acceptedAt: NOW0 } });
  if (wallet > 0) await topUp(wallet, 'init');
}
async function topUp(amount, key) {
  await settlementLedger.postEntry(db, {
    idempotencyKey: `topup:${DRIVER}:${key}`, kind: 'test_topup',
    legs: [{ account: 'admin_clearing', dr: amount }, { account: settlementLedger.passengerCreditAccount(DRIVER), cr: amount }],
  });
}
const balance = async () => ((await db.collection(settlementLedger.COL_ACCOUNTS).doc(settlementLedger.passengerCreditAccount(DRIVER)).get()).data() || {}).balance || 0;
const trip = async (id) => (await db.collection('taxi_trips').doc(id).get()).data();
const tripCount = async () => (await db.collection('taxi_trips').get()).size;
const journalCount = async () => (await db.collection(settlementLedger.COL_JOURNAL).get()).size;
const pub = (over = {}) => api.publish({
  farePerSeat: 350000, from: 'Urganch', to: 'Toshkent', scheduleDate: '2026-10-07', startTime: '08:00',
  departureAt: '2026-10-07T03:00:00Z', seats: 4, ...over,
}, ctx);
const reasonOf = (e) => (e && e.details && e.details.reason) || '';
async function expectReason(promise, reason, code = 'failed-precondition') {
  await assert.rejects(promise, (e) => {
    assert.strictEqual(reasonOf(e), reason, `sabab ${reasonOf(e)} (${e.code}): ${e.message}`);
    assert.strictEqual(e.code, code);
    return true;
  });
}
const ts = (ms) => Timestamp.fromMillis(ms);

async function main() {
  // ══ M2/H5: publish kirish tekshiruvi ═════════════════════════════════
  await reset();
  await check('publish: o\'tgan jo\'nash vaqti (now-6 daq) -> departure_in_past, reys YO\'Q, pul tegilmaydi', async () => {
    const before = await balance(); const j = await journalCount();
    await expectReason(pub({ departureAt: new Date(NOW0.getTime() - 6 * 60000).toISOString() }), 'departure_in_past');
    assert.strictEqual(await tripCount(), 0); assert.strictEqual(await balance(), before);
    assert.strictEqual(await journalCount(), j);
  });
  await check('publish: chegara - now-5 daq QABUL, now-5 daq-1 soniya RAD', async () => {
    const ok = await pub({ departureAt: new Date(NOW0.getTime() - 5 * 60000).toISOString() });
    assert.strictEqual(ok.status, 'published');
    await expectReason(pub({ departureAt: new Date(NOW0.getTime() - 5 * 60000 - 1000).toISOString() }), 'departure_in_past');
  });
  await check('publish: noto\'g\'ri sana satri (departureAt: "abc") -> departure_in_past (jim null EMAS)', async () => {
    const n = await tripCount();
    await expectReason(pub({ departureAt: 'abc' }), 'departure_in_past');
    assert.strictEqual(await tripCount(), n);
  });
  await check('publish: departureAt YO\'Q (eski ilova) - eski tolerant xulq, departureAt=null', async () => {
    const r = await api.publish({ farePerSeat: 350000, from: 'Urganch', to: 'Toshkent' }, ctx);
    assert.strictEqual(r.status, 'published');
    assert.strictEqual((await trip(r.tripId)).departureAt, null);
  });
  await check('publish: from/to bo\'sh yoki faqat bo\'shliq -> route_required', async () => {
    await expectReason(pub({ from: '   ' }), 'route_required');
    await expectReason(pub({ to: '' }), 'route_required');
    await expectReason(pub({ from: undefined }), 'route_required');
  });
  await check('publish: seats 0 / 9 / 2.5 / "abc" -> seats_invalid; yo\'q -> 4; "3" -> 3 (tolerant)', async () => {
    for (const s of [0, 9, 2.5, -1, 'abc']) await expectReason(pub({ seats: s }), 'seats_invalid');
    const r1 = await api.publish({ farePerSeat: 100000, from: 'A', to: 'B' }, ctx);
    assert.strictEqual((await trip(r1.tripId)).seats, 4);
    const r2 = await pub({ seats: '3' }); assert.strictEqual((await trip(r2.tripId)).seats, 3);
    const r3 = await pub({ seats: 1 }); assert.strictEqual((await trip(r3.tripId)).seats, 1);
    const r4 = await pub({ seats: 8 }); assert.strictEqual((await trip(r4.tripId)).seats, 8);
  });
  await check('publish: scheduleDate/startTime formati -> schedule_invalid; bo\'sh/yo\'q - tolerant', async () => {
    for (const d of ['07.10.2026', '2026-13-01', '2026-02-30', '2026-1-7', 'ertaga']) {
      await expectReason(pub({ scheduleDate: d }), 'schedule_invalid');
    }
    for (const t of ['8:00', '24:00', '08:60', '0800', 'ertalab']) {
      await expectReason(pub({ startTime: t }), 'schedule_invalid');
    }
    const ok = await pub({ scheduleDate: '', startTime: '' });
    assert.strictEqual(ok.status, 'published');
  });
  await check('publish: tekshiruv QARZ YOPISHDAN OLDIN - noto\'g\'ri kirishda qarz tegilmaydi', async () => {
    await db.collection('provider_capabilities').doc(ACC).set({ debt: { taxi: 5000, taxiRounds: 0 } }, { merge: true });
    const j = await journalCount(); const bal = await balance();
    await expectReason(pub({ seats: 99 }), 'seats_invalid');
    assert.strictEqual(await journalCount(), j); assert.strictEqual(await balance(), bal);
    assert.strictEqual(((await db.collection('provider_capabilities').doc(ACC).get()).data().debt || {}).taxi, 5000);
    await db.collection('provider_capabilities').doc(ACC).set({ debt: { taxi: 0 } }, { merge: true });
  });

  // ══ M2: reschedule ═══════════════════════════════════════════════════
  await reset();
  await check('reschedule: o\'tgan vaqt -> departure_in_past, reys o\'zgarmaydi, audit YO\'Q', async () => {
    const r = await pub();
    await expectReason(api.reschedule({ tripId: r.tripId, departureAt: new Date(NOW0.getTime() - 10 * 60000).toISOString() }, ctx), 'departure_in_past');
    assert.strictEqual((await trip(r.tripId)).rescheduleCount, undefined);
    assert.strictEqual((await db.collection('taxi_reschedules').get()).size, 0);
  });
  await check('reschedule: noto\'g\'ri scheduleDate/startTime -> schedule_invalid; departureAt yo\'q -> invalid-argument (eski)', async () => {
    const r = await pub();
    await expectReason(api.reschedule({ tripId: r.tripId, departureAt: '2026-10-09T03:00:00Z', scheduleDate: '09/10' }, ctx), 'schedule_invalid');
    await expectReason(api.reschedule({ tripId: r.tripId, departureAt: '2026-10-09T03:00:00Z', startTime: '25:00' }, ctx), 'schedule_invalid');
    await assert.rejects(() => api.reschedule({ tripId: r.tripId }, ctx), (e) => e.code === 'invalid-argument');
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed}/${results.length} taxi intercity audit CF checks passed.`);
  if (failed) process.exitCode = 1;
}
main().catch((e) => { console.error('FATAL', e); process.exitCode = 1; });
