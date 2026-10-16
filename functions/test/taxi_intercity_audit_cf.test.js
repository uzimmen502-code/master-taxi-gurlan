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

  // ══ M1: publish idempotentligi ═══════════════════════════════════════
  await reset();
  await check('requestId formati: qisqa / belgi / 65 uzun -> request_id_invalid; hujjat yaratilmaydi', async () => {
    for (const rid of ['short', 'has space!!!', 'x'.repeat(65), 'bad/slash/1234']) {
      await expectReason(pub({ requestId: rid }), 'request_id_invalid', 'invalid-argument');
    }
    assert.strictEqual((await db.collection('taxi_publish_requests').get()).size, 0);
    assert.strictEqual(await tripCount(), 0);
  });
  await check('requestId: ketma-ket qayta chaqiruv -> BIR reys, BIR yechim, bir xil tripId', async () => {
    const a = await pub({ requestId: 'req-AAAA-0001' });
    const bal = await balance(); const j = await journalCount();
    const b = await pub({ requestId: 'req-AAAA-0001' });
    assert.strictEqual(b.tripId, a.tripId); assert.strictEqual(b.status, 'published');
    assert.strictEqual(b.idempotent, true); assert.strictEqual(b.feeAmount, a.feeAmount);
    assert.strictEqual(await tripCount(), 1); assert.strictEqual(await balance(), bal);
    assert.strictEqual(await journalCount(), j);
    const rq = await db.collection('taxi_publish_requests').doc(`${DRIVER}_req-AAAA-0001`).get();
    assert.ok(rq.exists); assert.strictEqual(rq.data().tripId, a.tripId);
  });
  await check('requestId: PARALLEL 2 ta chaqiruv -> BIR reys, komissiya BIR marta', async () => {
    const before = await balance();
    const [a, b] = await Promise.all([pub({ requestId: 'req-BBBB-0002' }), pub({ requestId: 'req-BBBB-0002' })]);
    assert.strictEqual(a.tripId, b.tripId);
    assert.strictEqual((await db.collection('taxi_trips').where('driverUid', '==', DRIVER).get()).docs
      .filter((d) => d.id === a.tripId).length, 1);
    assert.strictEqual(await tripCount(), 2, 'req-AAAA + req-BBBB = 2 reys');
    assert.strictEqual(before - await balance(), 28000, 'komissiya bir marta');
  });
  await check('requestId: boshqa requestId -> yangi reys (alohida harakat)', async () => {
    const a = await pub({ requestId: 'req-CCCC-0003' }); const b = await pub({ requestId: 'req-DDDD-0004' });
    assert.notStrictEqual(a.tripId, b.tripId);
  });
  await check('requestId YO\'Q -> eski xulq: ikki chaqiruv = ikki reys', async () => {
    const n = await tripCount();
    await pub(); await pub();
    assert.strictEqual(await tripCount(), n + 2);
  });
  await check('requestId: payment_required natijasi ham qayta chaqiruvda O\'SHA reys, yangi reys/yechim YO\'Q', async () => {
    await reset({ wallet: 10000 }); // fee 28 000 > 10 000
    const a = await pub({ requestId: 'req-EEEE-0005' });
    assert.strictEqual(a.status, 'payment_required');
    await topUp(100000, 'later');
    const bal = await balance(); const j = await journalCount();
    const b = await pub({ requestId: 'req-EEEE-0005' });
    assert.strictEqual(b.tripId, a.tripId); assert.strictEqual(b.status, 'payment_required');
    assert.strictEqual(await tripCount(), 1); assert.strictEqual(await balance(), bal);
    assert.strictEqual(await journalCount(), j, 'qayta chaqiruv pul harakatini yaratmaydi');
  });
  await check('requestId: kirish xatosida hujjat qolmaydi (keyin to\'g\'ri chaqiruv ishlaydi)', async () => {
    await reset();
    await expectReason(pub({ requestId: 'req-FFFF-0006', seats: 99 }), 'seats_invalid');
    assert.strictEqual((await db.collection('taxi_publish_requests').get()).size, 0);
    const ok = await pub({ requestId: 'req-FFFF-0006' });
    assert.strictEqual(ok.status, 'published');
  });
  await check('requestId: fee 0 (starter) yo\'li ham idempotent', async () => {
    await reset();
    await db.collection('provider_capabilities').doc(ACC).set({ status: { taxi: 'starter' } }, { merge: true });
    const a = await pub({ requestId: 'req-GGGG-0007' }); const b = await pub({ requestId: 'req-GGGG-0007' });
    assert.strictEqual(a.tripId, b.tripId); assert.strictEqual(await tripCount(), 1);
    assert.strictEqual(b.status, 'published'); assert.strictEqual(b.feeAmount, 0);
  });
  await check('requestId: boshqa haydovchining kaliti to\'qnashmaydi (kalit = driverUid_requestId)', async () => {
    await reset();
    const a = await pub({ requestId: 'req-HHHH-0008' });
    await db.collection('taxi_publish_requests').doc(`${OTHER}_req-HHHH-0008`).set({ tripId: 'foreign', status: 'published' });
    const b = await pub({ requestId: 'req-HHHH-0008' });
    assert.strictEqual(b.tripId, a.tripId);
  });

  // ══ H3: hadAvaBooking SERVER hisoblaydi ══════════════════════════════
  const seedBooking = (id, over = {}) => db.collection('intercity_bookings').doc(id).set({
    driverId: DRIVER, userPhone: '998905550001', status: 'confirmed', passengers: 1,
    createdAt: ts(NOW0.getTime() + 60000), departureTime: ts(NOW0.getTime() + 3600000), ...over,
  });
  const hadOf = async (tripId) => (await trip(tripId)).hadAvaBooking;
  await reset();
  await check('H3: bron YO\'Q, klient hadAvaBooking:true yuboradi -> server false yozadi (klient e\'tiborsiz)', async () => {
    const r = await pub();
    const c = await api.cancel({ tripId: r.tripId, hadAvaBooking: true }, ctx);
    assert.strictEqual(c.status, 'cancelled');
    assert.strictEqual(await hadOf(r.tripId), false);
  });
  await check('H3: tasdiqlangan bron BOR, klient false yuboradi -> true', async () => {
    const r = await pub(); await seedBooking('b1');
    await api.cancel({ tripId: r.tripId, hadAvaBooking: false }, ctx);
    assert.strictEqual(await hadOf(r.tripId), true);
  });
  await check('H3: completed bron ham sanaladi; 9 xonali driverId shakli ham', async () => {
    const r = await pub(); await seedBooking('b2', { status: 'completed', driverId: DRIVER.slice(3) });
    await api.cancel({ tripId: r.tripId }, ctx);
    assert.strictEqual(await hadOf(r.tripId), true);
  });
  await check('H3: faqat pending / cancelled / expired bronlar sanalmaydi', async () => {
    await reset();
    const r = await pub();
    await seedBooking('p1', { status: 'pending' }); await seedBooking('p2', { status: 'cancelled' });
    await seedBooking('p3', { status: 'expired' });
    await api.cancel({ tripId: r.tripId, hadAvaBooking: true }, ctx);
    assert.strictEqual(await hadOf(r.tripId), false);
  });
  await check('H3: reysdan OLDINGI (boshqa reysning) va BOSHQA haydovchining broni sanalmaydi', async () => {
    await reset();
    const r = await pub();
    await seedBooking('old1', { createdAt: ts(NOW0.getTime() - 3600000), status: 'completed' });
    await seedBooking('oth1', { driverId: OTHER });
    await api.cancel({ tripId: r.tripId, hadAvaBooking: true }, ctx);
    assert.strictEqual(await hadOf(r.tripId), false);
  });
  await check('H3: pul siyosati O\'ZGARMAGAN - bron bor bo\'lsa ham bekorda komissiya to\'liq qaytadi (CANCEL-9)', async () => {
    await reset();
    const before = await balance();
    const r = await pub(); await seedBooking('c1', { status: 'completed' });
    assert.strictEqual(before - await balance(), 28000);
    const c = await api.cancel({ tripId: r.tripId }, ctx);
    assert.strictEqual(c.refunded, true); assert.strictEqual(await balance(), before);
  });
  await check('H3: fraud baholash SERVER qiymatidan: bron yo\'q + klient true -> had_ava_booking signali YO\'Q (normal)', async () => {
    await reset();
    const r = await pub({ departureAt: '2026-10-07T03:00:00Z' });
    await api.cancel({ tripId: r.tripId, hadAvaBooking: true, driverLat: 41.55, driverLng: 60.63 }, ctx);
    await db.collection('taxi_trips').doc(r.tripId).update({ 'location.destLat': 41.3111, 'location.destLng': 69.2797, cancelledAt: new Date('2026-10-07T02:00:00Z') });
    clock = new Date('2026-10-07T15:00:00Z');
    await pub({ from: 'Toshkent', to: 'Urganch', farePerSeat: 100000, driverLat: 41.3111, driverLng: 69.2797, departureAt: '2026-10-08T03:00:00Z' });
    const t = await trip(r.tripId);
    assert.strictEqual(t.fraudReviewed, true); assert.strictEqual(t.fraudVerdict, 'normal');
    assert.ok(!(t.fraudSignals || []).includes('had_ava_booking'));
  });
  await check('H3: fraud baholash SERVER qiymatidan: tasdiqlangan bron bor -> had_ava_booking signali BOR', async () => {
    await reset();
    const r = await pub({ departureAt: '2026-10-07T03:00:00Z' });
    await seedBooking('f1');
    await api.cancel({ tripId: r.tripId, hadAvaBooking: false, driverLat: 41.55, driverLng: 60.63 }, ctx);
    await db.collection('taxi_trips').doc(r.tripId).update({ 'location.destLat': 41.3111, 'location.destLng': 69.2797, cancelledAt: new Date('2026-10-07T02:00:00Z') });
    clock = new Date('2026-10-07T15:00:00Z');
    await pub({ from: 'Toshkent', to: 'Urganch', farePerSeat: 100000, driverLat: 41.3111, driverLng: 69.2797, departureAt: '2026-10-08T03:00:00Z' });
    const t = await trip(r.tripId);
    assert.ok((t.fraudSignals || []).includes('had_ava_booking'));
    assert.strictEqual(t.fraudVerdict, 'confirmed');
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed}/${results.length} taxi intercity audit CF checks passed.`);
  if (failed) process.exitCode = 1;
}
main().catch((e) => { console.error('FATAL', e); process.exitCode = 1; });
