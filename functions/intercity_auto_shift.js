/**
 * ШАҲАРЛАРАРО РЕЙС — АВТОМАТИК СУРИШ (эга қарори, 2026-10-15).
 *
 * Қоида (AVA_DECIDED): жўнашга ≤ 10 дақиқа қолганда салон тўлмаган бўлса
 * (бўш ўрин > 0) рейс 2 соатга сурилади. Кунига кўпи билан 4 марта.
 *
 * Қарорлар (эга жавоблари):
 *  - шарт: «салон тўлмаган» = `intercity_drivers.seats` (бўш ўрин) > 0;
 *  - тасдиқланган/кутилаётган бронлар САҚЛАНАДИ, вақти янгиланади,
 *    йўловчига хабар боради (бекор қилиш ҳуқуқи — мавжуд `intercityCancelBooking`);
 *  - кунига максимум [AUTO_SHIFT.maxPerDay] марта.
 *
 * Ҳал қилинган майда жойлар (PROPOSED, эга ўзгартира олади):
 *  - ярим кечадан ўтса сурилмайди (рейс `expiresAt` = кун охири);
 *  - 10 дақиқа ичида эълон қилинган/ўзгартирилган рейс сурилмайди
 *    (ҳайдовчи атайин яқин вақт қўйган).
 *
 * Манбалар: жўнаш вақти — `taxi_trips.departureAt` (дақиқа билан), у
 * бўлмаса `intercity_drivers.scheduleDate + hour`. Комиссия/тўлов
 * ЎЗГАРМАЙДИ: `taxi_billing.rescheduleWrites` (қўлда суришдаги билан бир
 * манба) — рейс ва тўлов сақланади, фақат сана/вақт.
 *
 * Идемпотент: ёзувлар битта tranzaksiyada, шарт (`D` ҳали ≤ 10 дақ) сурилгач
 * ёлғон бўлади; хабарлар детерминистик id билан `set` қилинади.
 *
 * Бу файл эски `autoUpdateDepartureTime` (index.js) ўрнини босади: у
 * ҳеч ким ёзмайдиган `intercity_drivers.departureTime` ни ўқирди ва
 * ўринларни текширмасди.
 */

const { TRIPS, RESCHEDULES, rescheduleWrites } = require('./taxi_billing');
const { render, langOfPhone } = require('./notif_i18n');

const AUTO_SHIFT = Object.freeze({
  triggerMinutes: 10,
  shiftHours: 2,
  maxPerDay: 4,
});

const COUNTERS = 'intercity_auto_shifts';
const TZ_OFFSET_MS = 5 * 3600000; // Asia/Tashkent, ёзги вақт йўқ
const MIN = 60000;

const pad = (n) => String(n).padStart(2, '0');
const local = (ms) => new Date(ms + TZ_OFFSET_MS);
const dateStr = (ms) => {
  const d = local(ms);
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
};
const hhmm = (ms) => {
  const d = local(ms);
  return `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`;
};

/** `YYYY-MM-DD` + соат (Тошкент) → UTC мс; нотўғри бўлса null. */
function deriveDepartureMs(scheduleDate, hour, minute = 0) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(scheduleDate || ''));
  const h = Number(hour);
  const min = minute == null ? 0 : Number(minute);
  if (!m || !Number.isInteger(h) || h < 0 || h > 23) return null;
  if (!Number.isInteger(min) || min < 0 || min > 59) return null;
  return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), h, min) - TZ_OFFSET_MS;
}

const toMs = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : 0);

/**
 * Соф қарор. Ёзмайди, ўқимайди.
 * @returns {{action:'shift', ...}|{action:'skip', reason:string, notify?:string}}
 */
function planShift({ listing, tripDepMs, tripTouchedMs, count, nowMs, cfg = AUTO_SHIFT }) {
  if (!listing || listing.isActive !== true) return { action: 'skip', reason: 'inactive' };
  const seatsLeft = Number(listing.seats);
  if (!Number.isFinite(seatsLeft)) return { action: 'skip', reason: 'seats_unknown' };
  if (seatsLeft <= 0) return { action: 'skip', reason: 'full' };

  const depMs = tripDepMs || deriveDepartureMs(listing.scheduleDate, listing.hour, listing.minute);
  if (!depMs) return { action: 'skip', reason: 'no_departure' };

  const left = depMs - nowMs;
  if (left <= 0) return { action: 'skip', reason: 'departed' };
  if (left > cfg.triggerMinutes * MIN) return { action: 'skip', reason: 'not_yet' };

  if (tripTouchedMs && depMs - tripTouchedMs <= cfg.triggerMinutes * MIN) {
    return { action: 'skip', reason: 'fresh_in_window' };
  }
  if ((Number(count) || 0) >= cfg.maxPerDay) {
    return { action: 'skip', reason: 'cap', notify: 'cap' };
  }
  const newMs = depMs + cfg.shiftHours * 3600000;
  if (dateStr(newMs) !== dateStr(depMs)) {
    return { action: 'skip', reason: 'midnight', notify: 'midnight' };
  }
  return {
    action: 'shift',
    depMs,
    newMs,
    newDate: dateStr(newMs),
    newHour: local(newMs).getUTCHours(),
    newMinute: local(newMs).getUTCMinutes(),
    newStartTime: hhmm(newMs),
    count: (Number(count) || 0) + 1,
  };
}

/** Қарорни ўзгартирмаслик учун: ±шунча дақиқа захира (рейс ва эълон вақти бироз фарқ қилса ҳам транзакцияда қарор). */
const PREFILTER_SLACK_MIN = 5;

/**
 * Audit M6 (2026-10): ҳар дақиқада 2 соатлик ойнадаги ҲАР эълон учун транзакция очилар
 * эди (эълон + рейс + ҳисоблагич = 3+ ўқиш), ҳолбуки ≤10 дақиқа ойнасидагилар бироз.
 * Аллақачон ўқилган snapshot'даги `hour/minute`дан жўнаш вақти ҳисобланади
 * (`deriveDepartureMs`); ойнадан (≤10 дақ) ЗАХИРАДАН ҳам ташқарида бўлса сабаб қайтарилади
 * (`planShift` билан бир хил: `not_yet` / `departed`), акс ҳолда `null` — қарор
 * транзакцияда (рейс `departureAt` манбаси билан). `minute` йўқ (эски эълон) —
 * рейс вақти аниқ эмас, сараланмайди.
 */
function prefilterSkip(listing, nowMs, cfg = AUTO_SHIFT) {
  if (typeof listing.minute !== 'number') return null;
  const depMs = deriveDepartureMs(listing.scheduleDate, listing.hour, listing.minute);
  if (!depMs) return null;
  const left = depMs - nowMs;
  if (left > (cfg.triggerMinutes + PREFILTER_SLACK_MIN) * MIN) return 'not_yet';
  if (left <= -PREFILTER_SLACK_MIN * MIN) return 'departed';
  return null;
}

/**
 * Ҳар дақиқада (`expirePendingTrips` эмас — алоҳида `autoUpdateDepartureTime`).
 * Фақат БУГУНГИ, соати жорий/кейинги соат бўлган фаол эълонлар ўқилади.
 */
async function runAutoShift({ db, admin, nowMs = Date.now() }) {
  const Timestamp = admin.firestore.Timestamp;
  const FieldValue = admin.firestore.FieldValue;
  const today = dateStr(nowMs);
  const hourNow = local(nowMs).getUTCHours();

  const snap = await db.collection('intercity_drivers')
    .where('isActive', '==', true)
    .where('scheduleDate', '==', today)
    .where('hour', 'in', [hourNow, hourNow + 1])
    .get();

  const stats = { checked: snap.size, opened: 0, shifted: 0, skipped: {}, errors: 0 };
  const skip = (r) => { stats.skipped[r] = (stats.skipped[r] || 0) + 1; };

  for (const doc of snap.docs) {
    // Audit M6: oynadan aniq tashqaridagi e'lon uchun tranzaksiya (3+ o'qish) ochilmaydi.
    const early = prefilterSkip(doc.data() || {}, nowMs);
    if (early) { skip(early); continue; }
    stats.opened += 1;
    try {
      const out = await shiftOne({ db, admin, Timestamp, FieldValue, doc, nowMs, today });
      if (out.action === 'shift') stats.shifted += 1; else skip(out.reason);
    } catch (e) {
      stats.errors += 1;
      console.error('intercityAutoShift', doc.id, e && e.message ? e.message : e);
    }
  }
  return stats;
}

async function shiftOne({ db, admin, Timestamp, FieldValue, doc, nowMs, today }) {
  const driverId = doc.id;
  const listingRef = doc.ref;
  const counterRef = db.collection(COUNTERS).doc(`${driverId}_${today}`);
  const noticesToSend = [];

  const result = await db.runTransaction(async (tx) => {
    noticesToSend.length = 0;
    const lSnap = await tx.get(listingRef);
    if (!lSnap.exists) return { action: 'skip', reason: 'gone' };
    const listing = lSnap.data() || {};
    if (listing.scheduleDate !== today) return { action: 'skip', reason: 'other_day' };

    const billingTripId = String(listing.billingTripId || '').trim();
    let tripRef = null;
    let trip = null;
    if (billingTripId) {
      tripRef = db.collection(TRIPS).doc(billingTripId);
      const tSnap = await tx.get(tripRef);
      trip = tSnap.exists ? (tSnap.data() || {}) : null;
      // Тўланган/ёпилган рейс эълон билан мос эмас — тегилмайди.
      if (trip && trip.status !== 'published') return { action: 'skip', reason: 'trip_not_published' };
    }
    const cSnap = await tx.get(counterRef);
    const counter = cSnap.exists ? (cSnap.data() || {}) : {};

    const plan = planShift({
      listing,
      tripDepMs: trip ? toMs(trip.departureAt) : 0,
      tripTouchedMs: trip ? toMs(trip.updatedAt) || toMs(trip.createdAt) : 0,
      count: counter.count,
      nowMs,
    });

    const driverPhone = String(listing.phoneDigits || listing.phone || driverId).replace(/\D/g, '');

    if (plan.action !== 'shift') {
      // Тўхтаганда ҳайдовчига БИР марта хабар (кун + сабаб бўйича).
      if (plan.notify && counter.noticeKey !== `${today}:${plan.notify}`) {
        tx.set(counterRef, { driverId, date: today, noticeKey: `${today}:${plan.notify}`,
          count: Number(counter.count) || 0, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
        if (driverPhone.length >= 9) {
          noticesToSend.push({
            id: `autoshift_stop_${driverId}_${today}_${plan.notify}`,
            phone: driverPhone,
            key: `auto_shift_stop_${plan.notify}`,
            params: { max: AUTO_SHIFT.maxPerDay },
            type: 'intercity_auto_shift_stop',
          });
        }
      }
      return plan;
    }

    // Барча ўқишлар ёзишдан олдин.
    const bookingsSnap = await tx.get(db.collection('intercity_bookings')
      .where('driverId', '==', driverId)
      .where('status', 'in', ['pending', 'confirmed']));
    const schedSnap = await tx.get(db.collection('schedules')
      .where('driverId', '==', driverId)
      .where('taxiType', '==', 'intercity')
      .where('date', '==', today)
      .where('isActive', '==', true));

    const when = Timestamp.fromMillis(nowMs);
    const newDeparture = new Date(plan.newMs);
    const shiftMs = plan.newMs - plan.depMs;

    if (tripRef && trip) {
      const w = rescheduleWrites({
        tripId: tripRef.id, trip, uid: driverPhone, accountId: trip.accountId || '',
        newDeparture, scheduleDate: plan.newDate, startTime: plan.newStartTime,
        when, Timestamp, source: 'auto_shift',
      });
      tx.set(db.collection(RESCHEDULES).doc(`autoshift_${tripRef.id}_${plan.count}_${today}`), w.audit);
      tx.update(tripRef, w.tripPatch);
    }
    tx.update(listingRef, {
      hour: plan.newHour,
      minute: plan.newMinute, // йўловчи экрани дақиқани кўрсатади
      scheduleDate: plan.newDate,
      updatedAt: FieldValue.serverTimestamp(),
    });
    for (const s of schedSnap.docs) tx.update(s.ref, { startTime: plan.newStartTime });

    const passengers = [];
    for (const b of bookingsSnap.docs) {
      const bd = b.data() || {};
      const oldDep = toMs(bd.departureTime);
      tx.update(b.ref, {
        departureTime: Timestamp.fromMillis((oldDep || plan.depMs) + shiftMs),
        departureReminderSent: false, // эслатма янги вақтга қайта юборилсин
        autoShiftedAt: when,
      });
      const phone = String(bd.userPhone || '').replace(/\D/g, '');
      if (phone.length >= 9) passengers.push({ phone, bookingId: b.id, route: bd.driverRouteLabel || '' });
    }

    tx.set(counterRef, {
      driverId, date: today, count: plan.count, lastAt: when,
      shifts: FieldValue.arrayUnion({ at: nowMs, fromMs: plan.depMs, toMs: plan.newMs }),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    const newText = plan.newStartTime;
    const key = `${driverId}_${today}_${plan.count}`;
    if (driverPhone.length >= 9) {
      noticesToSend.push({
        id: `autoshift_drv_${key}`,
        phone: driverPhone,
        key: 'auto_shift_driver',
        params: { hours: AUTO_SHIFT.shiftHours, time: newText, n: plan.count, max: AUTO_SHIFT.maxPerDay },
        type: 'intercity_auto_shift',
      });
    }
    for (const p of passengers) {
      noticesToSend.push({
        id: `autoshift_pax_${key}_${p.bookingId}`,
        phone: p.phone,
        key: 'auto_shift_passenger',
        params: { time: newText },
        type: 'intercity_trip_rescheduled',
        bookingId: p.bookingId,
      });
    }
    return plan;
  });

  // Хабарлар — tranzaksiyadan КЕЙИН, детерминистик id (retry икки марта юбормайди).
  for (const n of noticesToSend) {
    try {
      const lang = await langOfPhone(db, n.phone);
      const { title, body } = render(n.key, lang, n.params);
      await db.collection('notifications').doc(n.id).set({
        targetPhone: n.phone, title, body, type: n.type,
        ...(n.bookingId ? { bookingId: n.bookingId } : {}),
        sent: false, createdAt: FieldValue.serverTimestamp(),
      });
    } catch (e) {
      console.error('intercityAutoShift notify', n.id, e && e.message ? e.message : e);
    }
  }
  return result;
}

module.exports = {
  AUTO_SHIFT, COUNTERS, planShift, deriveDepartureMs, runAutoShift, dateStr, hhmm,
};
