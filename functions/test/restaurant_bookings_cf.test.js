/**
 * KAFE-RESTORAN — stol bron (S5, D-REST-23) — HAQIQIY `functions/index.js` callable'lari `.run()` orqali, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-restaurant-bookings \
 *     "node functions/test/restaurant_bookings_cf.test.js"
 *
 * Qulflanadi: sozlama darvozasi (hujjat yo'q = OFF, internal faqat tester), ega tarifi (50k/150k/400k) bronga
 * SNAPSHOT, so'rovda pul yo'q, qabulda haq restoran hamyonidan (yetmasa qabul yo'q), takroriy qabul haqni ikki marta
 * yechmaydi, parallel qabulda sig'im (faqat bitta g'olib), rad/bekor oqimlari (mijoz bekor qilsa haq qaytmaydi;
 * restoran bekor qilsa ham qaytmaydi va limitdan keyin bron o'chadi), muddati o'tgan so'rov, admin force-majeure
 * qaytarish (bir marta), idempotent so'rov, ledger muvozanati.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-restaurant-bookings';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require('../index');
const admin = require('firebase-admin');
const ledger = require('../settlement_ledger');

const db = admin.firestore();

const OWNER = '998911000001';
const STAFF = '998911000002';
const GUEST = '998912000001';
const GUEST2 = '998912000002';
const GUEST3 = '998912000003';
const STRANGER = '998914000001';
const ADMIN = '998915000001';
const RID = 'rest_book';

const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, ctxOf(who));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function expectCode(promise, code, httpsCode) {
  await assert.rejects(promise, (e) => {
    const got = (e.details && e.details.code) || e.message;
    assert.strictEqual(got, code, `kod ${got} (${e.code}): ${e.message}`);
    if (httpsCode) assert.strictEqual(e.code, httpsCode);
    return true;
  });
}

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
const pcBal = async (uid) => {
  const s = await db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(uid)).get();
  return s.exists ? Number(s.data().balance || 0) : 0;
};
const bonus = async (uid) => Number(((await db.collection('users').doc(uid).get()).data() || {}).bonusBalance || 0);
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
const booking = async (id) => (await db.collection('restaurant_bookings').doc(id).get()).data() || {};
const events = async (id) => (await db.collection('restaurant_bookings').doc(id).collection('events').get()).size;
const restaurant = async () => (await db.collection('restaurants').doc(RID).get()).data() || {};

let keySeq = 0;
const key = () => `book_test_${Date.now()}_${keySeq += 1}`;
const HOUR = 3600 * 1000;
// Har bron oldingisidan 3 soat keyin (slot 2 soat) → sig'imlar bir-biriga halaqit bermaydi (alohida test bo'lmasa).
let slotSeq = 0;
const startMs = (hours = 3) => Date.now() + hours * HOUR + (slotSeq += 1) * 3 * HOUR;
const place = (who, over = {}) => call('placeRestaurantBooking', {
  idempotencyKey: key(), restaurantId: RID, guests: 4, startAtMs: startMs(), note: 'deraza yonida', ...over,
}, who);

async function seedRestaurant(over = {}) {
  await db.collection('restaurants').doc(RID).set({
    name: 'Gurlan osh', status: 'approved', ownerUid: OWNER, walletUserDocId: OWNER,
    address: 'Gurlan, markaz', acceptsBookings: true, bookingSeats: 20, bookingNote: 'Zakalat 100 000 so\'m',
    ...over,
  });
  await db.collection('restaurants').doc(RID).collection('members').doc(OWNER).set({ role: 'owner' });
  await db.collection('restaurants').doc(RID).collection('members').doc(STAFF).set({ role: 'staff' });
}

async function reset() {
  await clearEmulator();
  for (const u of [OWNER, STAFF, GUEST, GUEST2, GUEST3, STRANGER]) {
    await db.collection('users').doc(u).set({ role: 'user', name: `U${u.slice(-4)}`, bonusBalance: 0 });
  }
  await db.collection('users').doc(ADMIN).set({ role: 'admin', bonusBalance: 0 });
  await seedRestaurant();
}

async function main() {
  await reset();

  // ── Sozlama va darvoza ─────────────────────────────────────────────
  await check('B1 sozlama hujjati yo\'q = OFF: bron berib bo\'lmaydi', async () => {
    await expectCode(place(GUEST), 'BOOKINGS_OFF', 'failed-precondition');
  });

  await check('B2 admin sozlamani yozadi: v1, ega tarifi, tarix + audit; takroriy chaqiruv versiyani oshirmaydi; oddiy foydalanuvchi rad', async () => {
    const r = await call('adminSetRestaurantBookings', { stage: 'public', reason: 'test' }, ADMIN);
    assert.deepStrictEqual([r.ok, r.version, r.changed], [true, 1, true]);
    const cfg = (await db.collection('settings').doc('restaurant_bookings').get()).data();
    assert.deepStrictEqual(cfg.tiers, [{ upTo: 5, fee: 50000 }, { upTo: 10, fee: 150000 }, { upTo: 100, fee: 400000 }]);
    assert.strictEqual(cfg.stage, 'public');
    assert.ok((await db.collection('restaurant_bookings_history').doc('v1').get()).exists);
    const audit = await db.collection('admin_audit').where('kind', '==', 'restaurant_bookings_set').get();
    assert.strictEqual(audit.size, 1);
    const again = await call('adminSetRestaurantBookings', { stage: 'public', reason: 'test' }, ADMIN);
    assert.deepStrictEqual([again.version, again.changed], [1, false]);
    await assert.rejects(call('adminSetRestaurantBookings', { stage: 'off' }, GUEST));
    await expectCode(call('adminSetRestaurantBookings', { tiers: [{ upTo: 5, fee: 1.5 }] }, ADMIN), 'TIERS_INVALID');
  });

  await check('B3 internal bosqich: faqat tester', async () => {
    await call('adminSetRestaurantBookings', { stage: 'internal', testerIds: [GUEST2] }, ADMIN);
    await expectCode(place(GUEST), 'BOOKINGS_INTERNAL_ONLY', 'failed-precondition');
    const r = await place(GUEST2);
    assert.strictEqual(r.status, 'requested');
    await call('adminSetRestaurantBookings', { stage: 'public' }, ADMIN);
  });

  // ── So'rov ─────────────────────────────────────────────────────────
  let b1;
  await check('B4 so\'rov: requested, haq snapshot (4 kishi = 50 000), pul harakati YO\'Q, hodisa yozildi', async () => {
    const before = await pcBal(OWNER);
    const r = await place(GUEST);
    assert.deepStrictEqual([r.ok, r.status, r.feeAmount, !!r.duplicate], [true, 'requested', 50000, false]);
    b1 = r.bookingId;
    const bk = await booking(b1);
    assert.deepStrictEqual([bk.status, bk.guests, bk.userPhone, bk.restaurantId], ['requested', 4, GUEST, RID]);
    assert.deepStrictEqual([bk.fee.amount, bk.fee.charged, bk.fee.version, bk.tariffVersion], [50000, false, 3, 3]); // v1 (B2) → v2 (internal, B3) → v3 (public)
    assert.strictEqual(bk.bookingNote, 'Zakalat 100 000 so\'m');
    assert.strictEqual(bk.restaurantName, 'Gurlan osh');
    assert.strictEqual(await pcBal(OWNER), before, 'so\'rovda pul yechilmaydi');
    assert.strictEqual(await events(b1), 1);
  });

  await check('B5 haq pog\'onalari: 8 kishi = 150 000; 12 kishi = 400 000', async () => {
    assert.strictEqual((await place(GUEST2, { guests: 8 })).feeAmount, 150000);
    assert.strictEqual((await place(STRANGER, { guests: 12 })).feeAmount, 400000);
  });

  await check('B6 idempotent: bir xil kalit → bir xil bron, duplicate:true, ikkinchi hujjat YO\'Q', async () => {
    const k = key();
    const at = startMs();
    const a = await call('placeRestaurantBooking', { idempotencyKey: k, restaurantId: RID, guests: 3, startAtMs: at }, GUEST);
    const c = await call('placeRestaurantBooking', { idempotencyKey: k, restaurantId: RID, guests: 3, startAtMs: at }, GUEST);
    assert.strictEqual(a.bookingId, c.bookingId);
    assert.strictEqual(c.duplicate, true);
    const parallel = await Promise.all(Array.from({ length: 5 }, () => call('placeRestaurantBooking',
      { idempotencyKey: k, restaurantId: RID, guests: 3, startAtMs: at }, GUEST)));
    assert.ok(parallel.every((x) => x.bookingId === a.bookingId));
    assert.strictEqual((await db.collection('restaurant_bookings').where('idempotencyKey', '==', k).get()).size, 1);
    // boshqa foydalanuvchining bron kaliti bilan urinish — o'z hujjati (boshqa id)
    const other = await call('placeRestaurantBooking', { idempotencyKey: k, restaurantId: RID, guests: 3, startAtMs: at }, STRANGER);
    assert.notStrictEqual(other.bookingId, a.bookingId);
    // Takroriy chaqiruv bron vaqti o'tib-yaqinlashib qolganda ham xato bermaydi (tarmoq uzilib qayta yuborilgan)
    const late = await call('placeRestaurantBooking', { idempotencyKey: k, restaurantId: RID, guests: 3, startAtMs: Date.now() + 5 * 60000 }, GUEST);
    assert.strictEqual(late.bookingId, a.bookingId);
  });

  await check('B7 tekshiruvlar: vaqt, mehmonlar, kalit, o\'z restorani, belgi, o\'rinlar, pauza, ish vaqti', async () => {
    await expectCode(place(GUEST, { startAtMs: Date.now() + 30 * 60000 }), 'BOOKING_TOO_SOON', 'failed-precondition');
    await expectCode(place(GUEST, { startAtMs: Date.now() + 31 * 24 * HOUR }), 'BOOKING_TOO_FAR', 'failed-precondition');
    await expectCode(place(GUEST, { startAtMs: 'ertaga' }), 'BOOKING_TIME_INVALID', 'invalid-argument');
    await expectCode(place(GUEST, { guests: 0 }), 'GUESTS_INVALID', 'invalid-argument');
    await expectCode(place(GUEST, { guests: 4.5 }), 'GUESTS_INVALID', 'invalid-argument');
    await expectCode(place(GUEST, { guests: '4' }), 'GUESTS_INVALID', 'invalid-argument');
    await expectCode(place(GUEST, { guests: 101 }), 'GUESTS_INVALID', 'invalid-argument');
    await expectCode(place(GUEST, { idempotencyKey: 'short' }), 'IDEMPOTENCY_KEY_INVALID', 'invalid-argument');
    await expectCode(place(OWNER), 'OWN_RESTAURANT', 'failed-precondition');
    await expectCode(place(GUEST, { restaurantId: 'yoq' }), 'RESTAURANT_NOT_FOUND', 'not-found');
    await expectCode(place(GUEST, { guests: 25 }), 'NO_CAPACITY', 'failed-precondition'); // o'rinlar 20
    await db.collection('restaurants').doc(RID).update({ acceptsBookings: false });
    await expectCode(place(GUEST), 'BOOKINGS_NOT_ACCEPTED', 'failed-precondition');
    await db.collection('restaurants').doc(RID).update({ acceptsBookings: true, bookingSeats: admin.firestore.FieldValue.delete() });
    await expectCode(place(GUEST), 'SEATS_NOT_CONFIGURED', 'failed-precondition');
    await db.collection('restaurants').doc(RID).update({ bookingSeats: 20, pausedUntil: admin.firestore.Timestamp.fromMillis(Date.now() + 365 * 24 * HOUR) });
    await expectCode(place(GUEST), 'RESTAURANT_PAUSED', 'failed-precondition');
    await db.collection('restaurants').doc(RID).update({ pausedUntil: admin.firestore.FieldValue.delete() });
    // ish vaqti: 09:00–10:00 Toshkent; boshqa soatga bron — yopiq
    const at = new Date(startMs());
    const tashkentHour = (at.getUTCHours() + 5) % 24;
    const openH = (tashkentHour + 6) % 24;
    await db.collection('restaurants').doc(RID).update({ openingHours: { open: `${String(openH).padStart(2, '0')}:00`, close: `${String((openH + 1) % 24).padStart(2, '0')}:00` } });
    await expectCode(call('placeRestaurantBooking', { idempotencyKey: key(), restaurantId: RID, guests: 2, startAtMs: at.getTime() }, GUEST), 'BOOKING_CLOSED_AT_TIME', 'failed-precondition');
    await db.collection('restaurants').doc(RID).update({ openingHours: admin.firestore.FieldValue.delete() });
    await db.collection('restaurants').doc(RID).update({ status: 'pending' });
    await expectCode(place(GUEST), 'RESTAURANT_NOT_APPROVED', 'failed-precondition');
    await db.collection('restaurants').doc(RID).update({ status: 'approved' });
  });

  await check('B8 bir mijozning bir vaqtdagi ikki broni (DUPLICATE) va faol bronlar limiti', async () => {
    const at = startMs();
    await call('placeRestaurantBooking', { idempotencyKey: key(), restaurantId: RID, guests: 2, startAtMs: at }, STAFF);
    await expectCode(call('placeRestaurantBooking', { idempotencyKey: key(), restaurantId: RID, guests: 2, startAtMs: at + 30 * 60000 }, STAFF), 'DUPLICATE_BOOKING', 'failed-precondition');
    // limit 5 (default): STAFF da hozir 1 ta; yana 4 ta (boshqa kunlar) → 5; oltinchisi rad
    for (let i = 0; i < 4; i += 1) await call('placeRestaurantBooking', { idempotencyKey: key(), restaurantId: RID, guests: 2, startAtMs: startMs() }, STAFF);
    await expectCode(call('placeRestaurantBooking', { idempotencyKey: key(), restaurantId: RID, guests: 2, startAtMs: startMs() }, STAFF), 'TOO_MANY_ACTIVE_BOOKINGS', 'failed-precondition');
  });

  // ── Qabul ──────────────────────────────────────────────────────────
  await check('B9 qabul: hamyonda yetmasa RESTAURANT_WALLET_INSUFFICIENT, holat requested qoladi, pul harakati yo\'q', async () => {
    await topUp(OWNER, 20000, 'low');
    await expectCode(call('restaurantAcceptBooking', { bookingId: b1 }, OWNER), 'RESTAURANT_WALLET_INSUFFICIENT', 'failed-precondition');
    assert.strictEqual((await booking(b1)).status, 'requested');
    assert.strictEqual(await pcBal(OWNER), 20000);
  });

  await check('B10 qabul: haq restoran hamyonidan aniq 50 000; bonusBalance ko\'zgusi; ikkinchi qabul haqni yechmaydi', async () => {
    await topUp(OWNER, 500000, 'ok');
    const before = await pcBal(OWNER);
    const bonusBefore = await bonus(OWNER);
    const r = await call('restaurantAcceptBooking', { bookingId: b1 }, OWNER);
    assert.deepStrictEqual([r.ok, r.feeAmount, r.idempotent], [true, 50000, false]);
    const bk = await booking(b1);
    assert.deepStrictEqual([bk.status, bk.fee.charged, bk.confirmedBy], ['confirmed', true, OWNER]);
    assert.strictEqual(await pcBal(OWNER), before - 50000);
    assert.strictEqual(await bonus(OWNER), bonusBefore - 50000);
    const again = await call('restaurantAcceptBooking', { bookingId: b1 }, STAFF);
    assert.strictEqual(again.idempotent, true);
    assert.strictEqual(await pcBal(OWNER), before - 50000, 'ikki marta yechilmadi');
    assert.strictEqual(await events(b1), 2);
    await journalBalanced();
  });

  await check('B11 qabul: begona (a\'zo emas) rad; yo\'q bron', async () => {
    const r = await place(GUEST2, { guests: 2 });
    await expectCode(call('restaurantAcceptBooking', { bookingId: r.bookingId }, STRANGER), 'NOT_RESTAURANT_MEMBER', 'permission-denied');
    await expectCode(call('restaurantAcceptBooking', { bookingId: 'bk_yoq' }, OWNER), 'BOOKING_NOT_FOUND', 'not-found');
  });

  await check('B12 PARALLEL qabul: o\'rin 10, ikki bron 6+6 bir vaqtda — faqat BITTA g\'olib, haq bir marta', async () => {
    await db.collection('restaurants').doc(RID).update({ bookingSeats: 10 });
    const at = startMs();
    const a = await call('placeRestaurantBooking', { idempotencyKey: key(), restaurantId: RID, guests: 6, startAtMs: at }, GUEST);
    const c = await call('placeRestaurantBooking', { idempotencyKey: key(), restaurantId: RID, guests: 6, startAtMs: at + 30 * 60000 }, GUEST2);
    const before = await pcBal(OWNER);
    const out = await Promise.allSettled([
      call('restaurantAcceptBooking', { bookingId: a.bookingId }, OWNER),
      call('restaurantAcceptBooking', { bookingId: c.bookingId }, STAFF),
    ]);
    const won = out.filter((x) => x.status === 'fulfilled');
    const lost = out.filter((x) => x.status === 'rejected');
    assert.strictEqual(won.length, 1, 'bitta g\'olib');
    assert.strictEqual(lost.length, 1);
    const code = lost[0].reason.details && lost[0].reason.details.code;
    assert.ok(['NO_CAPACITY', 'CONTENTION_RETRY'].includes(code), `yutqazgan kodi ${code}`);
    const statuses = [(await booking(a.bookingId)).status, (await booking(c.bookingId)).status].sort();
    assert.deepStrictEqual(statuses, ['confirmed', 'requested']);
    assert.strictEqual(await pcBal(OWNER), before - 150000, 'faqat 6 kishi haqi (150 000) bir marta');
    // So'rov bosqichida ham to'la sig'im rad etiladi
    await expectCode(call('placeRestaurantBooking', { idempotencyKey: key(), restaurantId: RID, guests: 6, startAtMs: at + 10 * 60000 }, STRANGER), 'NO_CAPACITY', 'failed-precondition');
    await db.collection('restaurants').doc(RID).update({ bookingSeats: 20 });
    await journalBalanced();
  });

  // ── Rad va bekor ───────────────────────────────────────────────────
  await check('B13 rad: requested → rejected, hech narsa yechilmaydi; tasdiqlangan bronni rad etib bo\'lmaydi; takroriy rad xatosiz', async () => {
    const r = await place(GUEST2, { guests: 2 });
    const before = await pcBal(OWNER);
    const rej = await call('restaurantRejectBooking', { bookingId: r.bookingId, reason: 'Joy yo\'q' }, OWNER);
    assert.deepStrictEqual([rej.ok, rej.idempotent], [true, false]);
    const bk = await booking(r.bookingId);
    assert.deepStrictEqual([bk.status, bk.rejectReason], ['rejected', 'Joy yo\'q']);
    assert.strictEqual(await pcBal(OWNER), before);
    assert.strictEqual((await call('restaurantRejectBooking', { bookingId: r.bookingId }, OWNER)).idempotent, true);
    await expectCode(call('restaurantRejectBooking', { bookingId: b1 }, OWNER), 'BOOKING_INVALID_TRANSITION', 'failed-precondition');
    await expectCode(call('restaurantAcceptBooking', { bookingId: r.bookingId }, OWNER), 'BOOKING_INVALID_TRANSITION', 'failed-precondition');
  });

  await check('B14 mijoz bekor qiladi: so\'rov va tasdiqlangan; yechilgan haq QAYTMAYDI; begona bekor qila olmaydi', async () => {
    const r1 = await place(GUEST, { guests: 2 });
    const c1 = await call('cancelRestaurantBooking', { bookingId: r1.bookingId }, GUEST);
    assert.deepStrictEqual([c1.ok, c1.idempotent], [true, false]);
    assert.strictEqual((await booking(r1.bookingId)).status, 'cancelled_by_guest');
    assert.strictEqual((await call('cancelRestaurantBooking', { bookingId: r1.bookingId }, GUEST)).idempotent, true);
    await expectCode(call('cancelRestaurantBooking', { bookingId: b1 }, STRANGER), 'NOT_BOOKING_OWNER', 'permission-denied');

    const before = await pcBal(OWNER);
    const c = await call('cancelRestaurantBooking', { bookingId: b1 }, GUEST); // b1 tasdiqlangan, haq yechilgan
    assert.strictEqual(c.ok, true);
    const bk = await booking(b1);
    assert.deepStrictEqual([bk.status, bk.fee.charged, !!bk.fee.refunded], ['cancelled_by_guest', true, false]);
    assert.strictEqual(await pcBal(OWNER), before, 'qaytarilmadi');
    await expectCode(call('cancelRestaurantBooking', { bookingId: r1.bookingId.replace(/.$/, 'x') }, GUEST), 'BOOKING_NOT_FOUND', 'not-found');
  });

  await check('B15 admin force-majeure qaytarish: faqat yechilgan haq, bir marta; sabab shart; audit', async () => {
    const before = await pcBal(OWNER);
    await expectCode(call('adminRefundBookingFee', { bookingId: b1, reason: '' }, ADMIN), 'REASON_REQUIRED', 'invalid-argument');
    await assert.rejects(call('adminRefundBookingFee', { bookingId: b1, reason: 'force-majeure' }, GUEST));
    const r = await call('adminRefundBookingFee', { bookingId: b1, reason: 'force-majeure: elektr yo\'q' }, ADMIN);
    assert.deepStrictEqual([r.ok, r.amount], [true, 50000]);
    assert.strictEqual(await pcBal(OWNER), before + 50000);
    const again = await call('adminRefundBookingFee', { bookingId: b1, reason: 'force-majeure: elektr yo\'q' }, ADMIN);
    assert.strictEqual(again.idempotent, true);
    assert.strictEqual(await pcBal(OWNER), before + 50000, 'ikki marta qaytmadi');
    const unpaid = await place(GUEST3, { guests: 2 });
    await expectCode(call('adminRefundBookingFee', { bookingId: unpaid.bookingId, reason: 'tekshiruv' }, ADMIN), 'FEE_NOT_CHARGED', 'failed-precondition');
    assert.strictEqual((await db.collection('admin_audit').where('kind', '==', 'restaurant_booking_fee_refund').get()).size, 1);
    await journalBalanced();
  });

  await check('B16 restoran qabuldan keyin bekor qiladi: haq QAYTMAYDI, hisobda belgilanadi; 3-bekordan keyin bron qabul qilish avtomat o\'chadi', async () => {
    const ids = [];
    for (let i = 0; i < 3; i += 1) {
      const r = await place(GUEST, { guests: 2 });
      await call('restaurantAcceptBooking', { bookingId: r.bookingId }, OWNER);
      ids.push(r.bookingId);
    }
    const before = await pcBal(OWNER);
    const first = await call('restaurantCancelBooking', { bookingId: ids[0], reason: 'Oshpaz kasal' }, OWNER);
    assert.deepStrictEqual([first.ok, first.bookingsDisabled], [true, false]);
    assert.strictEqual((await booking(ids[0])).status, 'cancelled_by_restaurant');
    assert.strictEqual(await pcBal(OWNER), before, 'haq qaytarilmaydi');
    assert.strictEqual((await restaurant()).bookingCancels.length, 1);
    assert.strictEqual((await call('restaurantCancelBooking', { bookingId: ids[0] }, OWNER)).idempotent, true);
    assert.strictEqual((await restaurant()).bookingCancels.length, 1, 'takroriy chaqiruv sanalmaydi');
    await call('restaurantCancelBooking', { bookingId: ids[1] }, OWNER);
    const third = await call('restaurantCancelBooking', { bookingId: ids[2] }, OWNER);
    assert.strictEqual(third.bookingsDisabled, true);
    const r = await restaurant();
    assert.deepStrictEqual([r.acceptsBookings, r.bookingsDisabledReason], [false, 'cancel_limit']);
    await expectCode(place(GUEST2), 'BOOKINGS_NOT_ACCEPTED', 'failed-precondition');
    await db.collection('restaurants').doc(RID).update({ acceptsBookings: true, bookingsDisabledReason: admin.firestore.FieldValue.delete(), bookingCancels: [] });
  });

  await check('B16b admin tiklaydi: tarix va sabab tozalanadi, acceptsBookings ga tegilmaydi; sabab shart; oddiy foydalanuvchi rad; takroriy — zararsiz', async () => {
    await db.collection('restaurants').doc(RID).update({ acceptsBookings: false, bookingsDisabledReason: 'cancel_limit', bookingCancels: [1, 2, 3] });
    await assert.rejects(call('adminRestoreRestaurantBookings', { restaurantId: RID, reason: 'ok' }, OWNER));
    await expectCode(call('adminRestoreRestaurantBookings', { restaurantId: RID, reason: '' }, ADMIN), 'REASON_REQUIRED', 'invalid-argument');
    const r = await call('adminRestoreRestaurantBookings', { restaurantId: RID, reason: 'Egasi bilan gaplashildi' }, ADMIN);
    assert.deepStrictEqual([r.ok, r.restored], [true, true]);
    const d = await restaurant();
    assert.deepStrictEqual([d.acceptsBookings, d.bookingsDisabledReason, d.bookingCancels], [false, undefined, []]);
    assert.strictEqual((await call('adminRestoreRestaurantBookings', { restaurantId: RID, reason: 'qayta' }, ADMIN)).restored, false);
    assert.strictEqual((await db.collection('admin_audit').where('kind', '==', 'restaurant_bookings_restore').get()).size, 1);
    await db.collection('restaurants').doc(RID).update({ acceptsBookings: true });
  });
  // ── Muddat ─────────────────────────────────────────────────────────
  await check('B17 muddati o\'tgan so\'rov: expired; qabul qilib bo\'lmaydi (BOOKING_EXPIRED); yangi so\'rovga tegmaydi', async () => {
    const stale = await place(GUEST3, { guests: 2 });
    const fresh = await place(STRANGER, { guests: 2 });
    await db.collection('restaurant_bookings').doc(stale.bookingId).update({ acceptDeadlineAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000) });
    await expectCode(call('restaurantAcceptBooking', { bookingId: stale.bookingId }, OWNER), 'BOOKING_EXPIRED', 'failed-precondition');
    const res = await fns.expireRestaurantBookings.run({});
    assert.ok(res && res.expired >= 1, JSON.stringify(res));
    assert.strictEqual((await booking(stale.bookingId)).status, 'expired');
    assert.strictEqual((await booking(fresh.bookingId)).status, 'requested');
    const again = await fns.expireRestaurantBookings.run({});
    assert.strictEqual(again.expired, 0, 'takroriy ishga tushirish');
  });

  await check('B18 ledger muvozanati: Σdr == Σcr barcha yozuvlarda', async () => {
    const n = await journalBalanced();
    assert.ok(n > 0);
  });

  const ok = results.filter(Boolean).length;
  console.log(`\n${ok} passed, ${results.length - ok} failed`);
  process.exit(results.every(Boolean) ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
