'use strict';

/**
 * Shaharlararo bron muddati (audit M4, 2026-10).
 *
 * Avval `expirePendingTrips` (index.js) so'rovdagi barcha `pending` bronlarni BITTA
 * oddiy batch bilan yopardi: bron holati yozish paytida qayta tekshirilmasdi (haydovchi
 * o'sha soniyada qabul qilgan yoki yo'lovchi bekor qilgan bo'lsa ham `expired` yozilib,
 * o'rin ikkinchi marta qaytardi), `increment` `seatCapacity`dan oshib ketardi, haydovchi
 * hujjati yo'q bo'lsa butun batch yiqilardi (hamma bronlar yopilmay qolardi).
 *
 * Endi HAR BRON o'z tranzaksiyasida: holat va muddat qayta o'qiladi; faqat hali `pending`
 * va haqiqatan muddati o'tgan bron yopiladi; o'rin `restoredSeats` (cap bilan); qulflar faqat
 * SHU bronga tegishli bo'lsa o'chiriladi; xabar deterministik id bilan (qayta urinish ikki
 * marta yubormaydi).
 */

const DEMO_DRIVER_IDS = ['1', '2', '3', '4', '5'];

const digits = (v) => String(v || '').replace(/[^\d]/g, '');

/** O'rin qaytarish - har doim `seatCapacity` bilan cheklanadi (index.js'dagi bilan bir xil qoida). */
function restoredSeats(driverData, passengers) {
  const d = driverData || {};
  const seats = Number(d.seats) || 0;
  const restored = seats + (Number(passengers) || 1);
  const cap = d.seatCapacity != null ? Number(d.seatCapacity) : null;
  if (cap != null && Number.isFinite(cap)) return Math.min(restored, cap);
  return restored;
}

/**
 * Bitta `pending` bronni muddati o'tgani uchun yopadi.
 * @returns {Promise<{ok:true, driverId:string}|{skipped:string}>}
 */
async function expireIntercityBooking({ db, admin, bookingRef, nowMs = Date.now() }) {
  const FieldValue = admin.firestore.FieldValue;
  const out = await db.runTransaction(async (tx) => {
    const snap = await tx.get(bookingRef);
    if (!snap.exists) return { skipped: 'not_found' };
    const b = snap.data() || {};
    if (String(b.status || '') !== 'pending') return { skipped: 'not_pending' };
    const expMs = b.expiresAt && typeof b.expiresAt.toMillis === 'function' ? b.expiresAt.toMillis() : 0;
    if (!(expMs > 0 && expMs < nowMs)) return { skipped: 'not_expired' };

    const driverId = String(b.driverId || '');
    const userKey = digits(b.userPhone);
    const realDriver = driverId && !DEMO_DRIVER_IDS.includes(driverId);
    const totalAmount = Number(b.totalAmount) || 0;

    // ── Barcha o'qishlar yozishdan oldin ──
    const driverRef = realDriver ? db.collection('intercity_drivers').doc(driverId) : null;
    const driverSnap = driverRef ? await tx.get(driverRef) : null;
    const clientRef = realDriver && userKey.length >= 9 && totalAmount > 0
      ? driverRef.collection('clients').doc(userKey) : null;
    const clientSnap = clientRef ? await tx.get(clientRef) : null;
    const lockRef = driverId && userKey.length >= 9
      ? db.collection('intercity_booking_locks').doc(`${driverId}_${userKey}`) : null;
    const lockSnap = lockRef ? await tx.get(lockRef) : null;
    const pLockRef = userKey.length >= 9 ? db.collection('intercity_passenger_locks').doc(userKey) : null;
    const pLockSnap = pLockRef ? await tx.get(pLockRef) : null;

    // ── Yozishlar ──
    tx.update(bookingRef, { status: 'expired', expiredAt: FieldValue.serverTimestamp() });
    if (driverSnap && driverSnap.exists) {
      tx.update(driverRef, {
        seats: restoredSeats(driverSnap.data(), b.passengers),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    if (clientSnap && clientSnap.exists) {
      tx.update(clientRef, {
        bookingCount: FieldValue.increment(-1),
        totalSpent: FieldValue.increment(-totalAmount),
        lastBookingAt: FieldValue.serverTimestamp(),
      });
    }
    if (lockSnap && lockSnap.exists && String((lockSnap.data() || {}).bookingId || '') === bookingRef.id) {
      tx.delete(lockRef);
    }
    if (pLockSnap && pLockSnap.exists && String((pLockSnap.data() || {}).bookingId || '') === bookingRef.id) {
      tx.delete(pLockRef);
    }
    if (userKey.length >= 9) {
      tx.set(db.collection('notifications').doc(`bookingexpired_${bookingRef.id}`), {
        targetPhone: userKey,
        title: '⏱ Брон муддати ўтди',
        body: 'Ҳайдовчи жавоб бермади. Бошқа ҳайдовчи танланг.',
        sent: false,
        type: 'intercity_booking_cancelled',
        bookingId: bookingRef.id,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    return { ok: true, driverId };
  });
  if (out.ok) {
    console.log(JSON.stringify({
      action: 'expireIntercityBooking', result: 'expired', bookingId: bookingRef.id, driverId: out.driverId,
    }));
  }
  return out;
}

module.exports = { restoredSeats, expireIntercityBooking, DEMO_DRIVER_IDS };
