'use strict';

/**
 * TAXI BILLING — D-TAXI-6…23 (default codebase, us-central1).
 *
 * O'ZGARMAS FORMULA (ega qarori, 2026-10-06):
 *
 *     AVA fee = farePerSeat × 4 × 2%
 *
 * AVA orqali NECHTA yo'lovchi topilgani komissiyaga TA'SIR QILMAYDI.
 * Shuning uchun bu faylda `passengers`, `seatsLeft`, `bookings` kabi
 * maydon bo'yicha hisob YO'Q va bo'lmaydi.
 *
 * Nega shu codebase: pul faqat `settlement_ledger.js` (ikki yozuvli
 * jurnal) orqali yuradi — u shu yerda (43-qoida: ikkinchi ledger yo'q).
 * Capability mantiqi `capabilities_model.js` nusxasidan (paritet testi).
 *
 * ── PUL YO'LI ──────────────────────────────────────────────────────────
 * Haydovchining AVA wallet'i = `passenger_credit:{usersDocId}` (liability,
 * `users.bonusBalance` ga ko'zgu). Komissiya:
 *   dr passenger_credit:{uid}   (wallet kamayadi)
 *   cr earnings:ava_taxi_fee    (AVA daromadi)
 * Refund — teskari yozuv, boshqa idempotentlik kaliti. Har ikkisi
 * `postEntry` orqali: Σdr == Σcr, faqat butun son, idempotent.
 *
 * ── HOLATLAR (`taxi_trips/{tripId}`) ───────────────────────────────────
 *   payment_required → published → completed | cancelled
 * `published` faqat to'lovdan KEYIN (D-TAXI-13). Reys hujjatini FAQAT
 * server yozadi (qoida: write false).
 *
 * ── BOSQICHMA-BOSQICH (42-qoida) ───────────────────────────────────────
 * `module_config/global.taxiBillingEnabled` (standart: false). O'chiq
 * bo'lsa: snapshot yoziladi, fee = 0, `billingMode: 'shadow'` — oqim
 * haqiqiy trafikda sinaladi, pul olinmaydi. Yoqilganda: faqat
 * `isTaxiBillable` (verified + grace tugagan) haydovchilardan olinadi.
 */

const caps = require('./capabilities_model');
const fraud = require('./taxi_fraud');

const TRIPS = 'taxi_trips';
const PRICE_CHANGES = 'taxi_price_changes';
/** D-TAXI-CANCEL-3 — kechiktirishlar jurnali (audit). */
const RESCHEDULES = 'taxi_reschedules';
const FRAUD_CASES = 'taxi_fraud_cases';
const AGREEMENTS = 'service_agreements';
const CAPS = 'provider_capabilities';
const EARNINGS_ACCOUNT = 'earnings:ava_taxi_fee';

const SEAT_BASIS = 4;
/** 2% = 200 bps. Butun son arifmetikasi uchun bps. */
const RATE_BPS = 200;
const BILLING_VERSION = 1;
/** Pasaytirishda refund — reys davomida nechta marta (D-TAXI-12 abuse). */
const MAX_DOWNWARD_REFUNDS = 1;
/** Jo'nashdan shuncha soat keyin "bekor" = aslida tugagan (refund yo'q). */
const CANCEL_AFTER_DEPARTURE_GRACE_H = 2;

/**
 * Komissiya — SOF, DETERMINISTIK, BUTUN SO'M (T-4, 8-qoida).
 *
 *   fee = ceil(farePerSeat × 4 × 200 / 10000)
 *
 * `ceil`: AVA o'ziga zarar qilmaydi, farq eng ko'pi 1 so'm.
 */
function calculateTaxiFee(farePerSeat) {
  // Faqat HAQIQIY son: `'350000'` satri ham rad etiladi — pul maydoni
  // tipi klientdan kelganda aniq bo'lishi kerak (18-qoida).
  const fare = typeof farePerSeat === 'number' ? farePerSeat : Number.NaN;
  if (!Number.isInteger(fare) || fare <= 0) {
    const e = new Error('farePerSeat musbat butun son bo\'lishi kerak');
    e.code = 'invalid-argument';
    throw e;
  }
  const grossBasis = fare * SEAT_BASIS;
  const feeAmount = Math.ceil((grossBasis * RATE_BPS) / 10000);
  return {
    farePerSeat: fare, seatBasis: SEAT_BASIS, rateBps: RATE_BPS,
    rate: RATE_BPS / 10000, grossBasis, feeAmount,
  };
}

function attachTaxiBilling(exports, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, settlementLedger,
    notifyUserInApp, now: nowFn,
  } = deps;
  const now = () => (nowFn ? nowFn() : new Date());
  const Timestamp = admin.firestore.Timestamp;

  const err = (code, msg, extra) => {
    const e = new functions.https.HttpsError(code, msg, extra);
    return e;
  };

  // ── flag (60 s kesh) ───────────────────────────────────────────────
  let flagCache = { at: 0, value: false };
  async function billingEnabled() {
    const t = Date.now();
    if (t - flagCache.at < 60000) return flagCache.value;
    try {
      const s = await db.collection('module_config').doc('global').get();
      flagCache = { at: t, value: !!(s.exists && s.data().taxiBillingEnabled === true) };
    } catch (e) {
      // Flag o'qilmasa — pul OLINMAYDI (xavfsiz tomon).
      console.error(`taxiBillingEnabled o'qilmadi: ${e.message}`);
      flagCache = { at: t, value: false };
    }
    return flagCache.value;
  }

  // ── kimlik ─────────────────────────────────────────────────────────
  /** Token telefoni → users hujjati (9/12) → accountId + capability. */
  async function resolveCaller(context) {
    if (!context || !context.auth) throw err('unauthenticated', 'Login required');
    const phone = canonicalUid(callerPhone(context));
    if (phone.length !== 12) throw err('unauthenticated', 'Telefon claim yo\'q');
    const ids = [phone, phone.slice(3)];
    let userRef = null;
    let userData = null;
    for (const id of ids) {
      const s = await db.collection('users').doc(id).get();
      if (s.exists) { userRef = s.ref; userData = s.data() || {}; break; }
    }
    if (!userRef) throw err('failed-precondition', 'users hujjati yo\'q', { reason: 'no_user' });
    const accountId = String(userData.accountId || '');
    if (!accountId) {
      throw err('failed-precondition', 'Avval taxi xizmatini yoqing', { reason: 'no_capability' });
    }
    const capSnap = await db.collection(CAPS).doc(accountId).get();
    const cap = capSnap.exists ? (capSnap.data() || {}) : {};
    return { phone, usersDocId: userRef.id, accountId, cap };
  }

  async function walletBalance(usersDocId) {
    const s = await db.collection(settlementLedger.COL_ACCOUNTS)
      .doc(settlementLedger.passengerCreditAccount(usersDocId)).get();
    return s.exists ? Number(s.data().balance || 0) : 0;
  }

  /**
   * Narx va ruxsat — PULSIZ. UI «N so'm to'lab e'lon qilish» tugmasini
   * shu natijadan chizadi (D-TAXI-22). Sabablar `reason` bilan: UI
   * foydalanuvchiga sodda matn ko'rsatadi, kod esa diagnostika oladi
   * (25-qoida).
   */
  async function quote(data, context) {
    const me = await resolveCaller(context);
    const fee = calculateTaxiFee(data && data.farePerSeat);
    const when = now();

    const status = caps.statusOf(me.cap, 'taxi');
    if (!caps.canPublishPaid(me.cap, 'taxi')) {
      return {
        allowed: false,
        reason: status === caps.TAXI.verificationRequired ? 'taxi_verification_required' : 'taxi_not_allowed',
        taxiStatus: status, ...fee, feeAmount: 0,
      };
    }
    const agr = await db.collection(AGREEMENTS).doc(me.accountId).get();
    if (!caps.hasCurrentAgreement(agr.exists ? agr.data() : null, 'taxi')) {
      return {
        allowed: false, reason: 'agreement_required',
        agreementVersion: caps.AGREEMENT_VERSIONS.taxi, taxiStatus: status, ...fee, feeAmount: 0,
      };
    }
    const enabled = await billingEnabled();
    const billable = enabled && caps.isTaxiBillable(me.cap, when);
    const feeAmount = billable ? fee.feeAmount : 0;
    const balance = billable ? await walletBalance(me.usersDocId) : null;
    return {
      allowed: true, reason: 'ok', taxiStatus: status, billable,
      billingMode: enabled ? 'live' : 'shadow',
      ...fee, feeAmount, quotedFee: fee.feeAmount,
      walletBalance: balance,
      sufficient: billable ? balance >= feeAmount : true,
    };
  }

  /** Komissiyani ledger orqali oladi. Yetarli bo'lmasa `insufficient`. */
  async function charge({ usersDocId, phone, tripId, amount, version, kind, meta }) {
    const key = `taxiFee:${tripId}:v${version}`;
    try {
      const res = await settlementLedger.postEntry(db, {
        idempotencyKey: key,
        kind,
        refType: 'taxi_trip',
        refId: tripId,
        postedBy: phone,
        postedRole: 'driver',
        legs: [
          { account: settlementLedger.passengerCreditAccount(usersDocId), dr: amount },
          { account: EARNINGS_ACCOUNT, cr: amount },
        ],
      }, {
        mirrorBonus: true,
        walletLedgerType: kind,
        meta: { tripId, ...meta },
        // D-TAXI-23: wallet manfiyga tushmasin.
        assert: ({ accounts }) => {
          const st = accounts.get(settlementLedger.passengerCreditAccount(usersDocId));
          if (st && st.next < 0) {
            const e = new Error('insufficient');
            e.insufficient = true;
            throw e;
          }
        },
      });
      return { ok: true, entryId: res.id, idempotent: res.idempotent };
    } catch (e) {
      if (e && e.insufficient) return { ok: false, insufficient: true };
      throw e;
    }
  }

  async function refund({ usersDocId, tripId, amount, version, kind, meta }) {
    const key = `taxiRefund:${tripId}:v${version}`;
    const res = await settlementLedger.postEntry(db, {
      idempotencyKey: key,
      kind,
      refType: 'taxi_trip',
      refId: tripId,
      postedBy: 'system',
      postedRole: 'system',
      legs: [
        { account: EARNINGS_ACCOUNT, dr: amount },
        { account: settlementLedger.passengerCreditAccount(usersDocId), cr: amount },
      ],
    }, { mirrorBonus: true, walletLedgerType: kind, meta: { tripId, ...meta } });
    return { entryId: res.id, idempotent: res.idempotent };
  }

  /**
   * E'LON (D-TAXI-13): narx → komissiya → to'lov → `published`.
   * To'lovsiz `published` BO'LMAYDI. Snapshot — D-TAXI-21.
   */
  async function publish(data, context) {
    const me = await resolveCaller(context);
    // D-TAXI-CANCEL-6: avval qarz, keyin yangi komissiya.
    const debt = await settleOutstanding(me);
    if (debt.outstanding > 0) {
      throw err('failed-precondition', 'Avvalgi AVA xizmat haqi qarzi yopilmagan',
        { reason: 'outstanding_debt', outstanding: debt.outstanding, walletBalance: debt.walletBalance });
    }
    const q = await quote(data, context);
    if (!q.allowed) throw err('failed-precondition', 'Reys e\'lon qilib bo\'lmaydi', { reason: q.reason, taxiStatus: q.taxiStatus });

    const when = now();
    const tripRef = db.collection(TRIPS).doc();
    const departureAt = data.departureAt ? new Date(data.departureAt) : null;
    const snapshot = {
      driverUid: me.phone,
      usersDocId: me.usersDocId,
      accountId: me.accountId,
      taxiType: 'intercity',
      from: String(data.from || '').trim(),
      to: String(data.to || '').trim(),
      scheduleDate: String(data.scheduleDate || ''),
      startTime: String(data.startTime || ''),
      departureAt: departureAt && !Number.isNaN(departureAt.getTime()) ? Timestamp.fromDate(departureAt) : null,
      seats: Number(data.seats) || SEAT_BASIS,
      // D-TAXI-21 snapshot
      farePerSeat: q.farePerSeat,
      seatBasis: SEAT_BASIS,
      rate: q.rate,
      rateBps: RATE_BPS,
      grossBasis: q.grossBasis,
      feeAmount: q.feeAmount,
      quotedFee: q.quotedFee,
      billingMode: q.billingMode,
      billable: q.billable,
      billingVersion: BILLING_VERSION,
      chargedAt: null,
      status: 'payment_required',
      // D-TAXI-14 — location qaydi
      location: {
        originDeclared: String(data.from || '').trim(),
        originLat: numOrNull(data.originLat),
        originLng: numOrNull(data.originLng),
        driverLat: numOrNull(data.driverLat),
        driverLng: numOrNull(data.driverLng),
        locationAccuracy: numOrNull(data.locationAccuracy),
        locationCapturedAt: when,
      },
      createdAt: when,
      updatedAt: when,
    };

    if (q.feeAmount > 0) {
      await tripRef.set(snapshot);
      const c = await charge({
        usersDocId: me.usersDocId, phone: me.phone, tripId: tripRef.id,
        amount: q.feeAmount, version: BILLING_VERSION, kind: 'taxi_fee',
        meta: { farePerSeat: q.farePerSeat, grossBasis: q.grossBasis },
      });
      if (!c.ok) {
        // D-TAXI-23: `payment_required` da qoladi, e'lon chiqmaydi.
        return { tripId: tripRef.id, status: 'payment_required', feeAmount: q.feeAmount, walletBalance: q.walletBalance };
      }
      await tripRef.update({ status: 'published', chargedAt: now(), ledgerEntryId: c.entryId, updatedAt: now() });
    } else {
      await tripRef.set({ ...snapshot, status: 'published', chargedAt: null });
    }

    // D-TAXI-14: mismatch — signal, hukm emas.
    const mm = fraud.evaluateOriginMismatch({
      originLat: snapshot.location.originLat, originLng: snapshot.location.originLng,
      driverLat: snapshot.location.driverLat, driverLng: snapshot.location.driverLng,
      publishedAt: when, departureAt,
    });
    if (mm.flagged) {
      await db.collection(FRAUD_CASES).add({
        type: 'origin_mismatch', tripId: tripRef.id, driverUid: me.phone, accountId: me.accountId,
        verdict: 'suspicious', detail: mm, createdAt: when, resolved: false,
      });
    }

    // D-TAXI-16…19: oldingi bekor qilingan reysni qayta baholash.
    try {
      await reviewLastCancelled(me, snapshot, when);
    } catch (e) {
      console.error(`fraud review xato (${tripRef.id}): ${e.message}`);
    }

    return { tripId: tripRef.id, status: 'published', feeAmount: q.feeAmount, billingMode: q.billingMode };
  }

  async function reviewLastCancelled(me, nextSnap, when) {
    // Fee'siz (shadow/starter) bekorlar ham BAHOLANADI — verdict yoziladi,
    // pul esa faqat refund bo'lgan reysda harakatlanadi. Shunday qilib
    // shadow davrida fraud pipeline ma'lumot beradi, sukut saqlamaydi.
    const prevSnap = await db.collection(TRIPS)
      .where('driverUid', '==', me.phone)
      .where('status', '==', 'cancelled')
      .where('fraudReviewed', '==', false)
      .orderBy('cancelledAt', 'desc')
      .limit(1).get();
    if (prevSnap.empty) return;
    const prevDoc = prevSnap.docs[0];
    const prev = prevDoc.data();
    const thresholds = await fraudThresholds();
    const loc = prev.location || {};
    const res = fraud.evaluateCancelFraud({
      prev: {
        from: prev.from, to: prev.to,
        originLat: loc.originLat, originLng: loc.originLng,
        destLat: loc.destLat, destLng: loc.destLng,
        cancelLat: loc.cancelLat, cancelLng: loc.cancelLng,
        cancelledAt: prev.cancelledAt, departureAt: prev.departureAt,
        hadAvaBooking: prev.hadAvaBooking === true,
      },
      next: {
        from: nextSnap.from, to: nextSnap.to, publishedAt: when,
        driverLat: nextSnap.location.driverLat, driverLng: nextSnap.location.driverLng,
      },
      thresholds,
    });
    await prevDoc.ref.update({ fraudReviewed: true, fraudVerdict: res.verdict, fraudSignals: res.signals, fraudReason: res.reason });
    // D-TAXI-CANCEL-1/2: haqiqiy bekor va keyingi reys — normal, hech qanday yozuv yo'q.
    if (res.verdict === 'normal') return;

    await db.collection(FRAUD_CASES).add({
      type: 'fake_cancel', tripId: prevDoc.id, driverUid: me.phone, accountId: me.accountId,
      verdict: res.verdict, signals: res.signals, reason: res.reason, createdAt: when,
      resolved: res.verdict === 'confirmed',
    });

    // D-TAXI-CANCEL-7: `suspicious` va `manual_review` da pul TEGILMAYDI.
    if (res.verdict !== 'confirmed') return;

    // D-TAXI-CANCEL-5/6: refund qaytarib olinadi; wallet yetmasa QARZ.
    // Faqat HAQIQATAN refund bo'lgan reysda (shadow/starter'da fee 0 edi —
    // qaytarib oladigan narsa yo'q, verdict esa yozildi).
    const amount = prev.refunded === true ? (Number(prev.feeAmount) || 0) : 0;
    if (amount > 0) await reclaimWithDebt({ me, usersDocId: prev.usersDocId, tripRef: prevDoc.ref, tripId: prevDoc.id, amount, when, signals: res.signals });
    if (amount === 0) return;

    if (notifyUserInApp) {
      await notifyUserInApp({
        userId: me.phone,
        title: 'AVA xizmat haqi qayta hisobdan yechildi',
        body: 'Avvalgi reys bekor qilingan deb belgilangan edi. Tizim tekshiruvi reys amalga '
          + 'oshirilganini tasdiqladi. Shu sabab avval qaytarilgan AVA xizmat haqi qayta '
          + 'hisobdan yechildi.',
        category: 'warning', source: 'taxi_billing', dataType: 'taxi_fraud',
      });
    }
  }

  /**
   * D-TAXI-CANCEL-6 — reclaim, wallet yetmasa QARZ (ikkinchi ledger YO'Q).
   *
   * Wallet'da bor qismi darhol olinadi (ledger: wallet → earnings). Qolgani
   * `provider_capabilities.debt.taxi` ga `outstandingTaxiFee` sifatida
   * yoziladi (server kaliti). Keyingi `publishTaxiTrip` AVVAL shu qarzni
   * yopadi (`settleOutstanding`), shundan keyingina yangi komissiya.
   */
  async function reclaimWithDebt({ me, usersDocId, tripRef, tripId, amount, when, signals }) {
    const bal = await walletBalance(usersDocId);
    const takeNow = Math.max(0, Math.min(amount, bal));
    if (takeNow > 0) {
      await settlementLedger.postEntry(db, {
        idempotencyKey: `taxiReclaim:${tripId}`,
        kind: 'taxi_fee_reclaim', refType: 'taxi_trip', refId: tripId,
        postedBy: 'system', postedRole: 'system',
        legs: [
          { account: settlementLedger.passengerCreditAccount(usersDocId), dr: takeNow },
          { account: EARNINGS_ACCOUNT, cr: takeNow },
        ],
      }, { mirrorBonus: true, walletLedgerType: 'taxi_fee_reclaim', meta: { tripId, signals } });
    }
    const outstanding = amount - takeNow;
    if (outstanding > 0) {
      await db.collection(CAPS).doc(me.accountId).set({
        debt: { taxi: admin.firestore.FieldValue.increment(outstanding) },
        updatedAt: when,
      }, { merge: true });
    }
    await tripRef.update({ reclaimed: true, reclaimedAt: when, reclaimedAmount: takeNow, outstandingTaxiFee: outstanding });
  }

  /** Qarz bo'lsa — yangi komissiyadan OLDIN yopiladi (CANCEL-6). */
  async function settleOutstanding(me) {
    const debt = Number(((me.cap || {}).debt || {}).taxi) || 0;
    if (debt <= 0) return { settled: 0, outstanding: 0 };
    const bal = await walletBalance(me.usersDocId);
    if (bal < debt) return { settled: 0, outstanding: debt, walletBalance: bal };
    await settlementLedger.postEntry(db, {
      idempotencyKey: `taxiDebt:${me.accountId}:${debt}:${Math.floor(now().getTime() / 1000)}`,
      kind: 'taxi_fee_debt_settlement', refType: 'provider', refId: me.accountId,
      postedBy: 'system', postedRole: 'system',
      legs: [
        { account: settlementLedger.passengerCreditAccount(me.usersDocId), dr: debt },
        { account: EARNINGS_ACCOUNT, cr: debt },
      ],
    }, { mirrorBonus: true, walletLedgerType: 'taxi_fee_debt_settlement', meta: { accountId: me.accountId } });
    await db.collection(CAPS).doc(me.accountId).set({ debt: { taxi: 0 }, updatedAt: now() }, { merge: true });
    return { settled: debt, outstanding: 0 };
  }

  async function fraudThresholds() {
    try {
      const s = await db.collection('module_config').doc('taxi_fraud').get();
      return s.exists ? (s.data() || {}) : {};
    } catch (_) { return {}; }
  }

  /** D-TAXI-11/12: narx o'zgardi — farq to'lanadi yoki (bir marta) qaytariladi. */
  async function reprice(data, context) {
    const me = await resolveCaller(context);
    const tripRef = db.collection(TRIPS).doc(String(data.tripId || ''));
    const snap = await tripRef.get();
    if (!snap.exists) throw err('not-found', 'Reys topilmadi');
    const trip = snap.data();
    if (trip.driverUid !== me.phone) throw err('permission-denied', 'Reys sizniki emas');
    if (trip.status !== 'published') throw err('failed-precondition', 'Reys e\'lon holatida emas', { reason: 'not_published' });

    const fee = calculateTaxiFee(data.farePerSeat);
    const when = now();
    const oldFare = trip.farePerSeat;
    const oldFee = Number(trip.feeAmount) || 0;
    const newFee = trip.billable ? fee.feeAmount : 0;
    const version = (Number(trip.billingVersion) || 1) + 1;

    await db.collection(PRICE_CHANGES).add({
      tripId: tripRef.id, uid: me.phone, accountId: me.accountId,
      oldFare, newFare: fee.farePerSeat, oldFee, newFee, changedAt: when,
    });

    if (newFee > oldFee) {
      const delta = newFee - oldFee;
      const c = await charge({
        usersDocId: me.usersDocId, phone: me.phone, tripId: tripRef.id, amount: delta,
        version, kind: 'taxi_fee_delta', meta: { oldFare, newFare: fee.farePerSeat },
      });
      if (!c.ok) {
        // Qo'shimcha to'lamasdan yangi narx aktiv BO'LMAYDI.
        await tripRef.update({ pendingFare: fee.farePerSeat, pendingFee: newFee, pendingDelta: delta, repriceStatus: 'payment_required', updatedAt: when });
        return { status: 'payment_required', delta, walletBalance: await walletBalance(me.usersDocId) };
      }
      await tripRef.update({
        farePerSeat: fee.farePerSeat, grossBasis: fee.grossBasis, feeAmount: newFee,
        billingVersion: version, repriceStatus: 'ok', pendingFare: null, updatedAt: when,
      });
      return { status: 'ok', delta, feeAmount: newFee };
    }

    const refundsSoFar = Number(trip.downwardRefunds) || 0;
    let refunded = 0;
    if (newFee < oldFee && refundsSoFar < MAX_DOWNWARD_REFUNDS) {
      refunded = oldFee - newFee;
      await refund({ usersDocId: me.usersDocId, tripId: tripRef.id, amount: refunded, version, kind: 'taxi_fee_delta_refund', meta: { oldFare, newFare: fee.farePerSeat } });
    }
    await tripRef.update({
      farePerSeat: fee.farePerSeat, grossBasis: fee.grossBasis,
      feeAmount: refunded ? newFee : oldFee,
      downwardRefunds: refundsSoFar + (refunded ? 1 : 0),
      billingVersion: version, repriceStatus: 'ok', updatedAt: when,
    });
    return { status: 'ok', delta: -refunded, feeAmount: refunded ? newFee : oldFee, refundLimited: newFee < oldFee && !refunded };
  }

  /** D-TAXI-15: bekor → komissiya wallet'ga `refund`. */
  async function cancel(data, context) {
    const me = await resolveCaller(context);
    const tripRef = db.collection(TRIPS).doc(String(data.tripId || ''));
    const snap = await tripRef.get();
    if (!snap.exists) throw err('not-found', 'Reys topilmadi');
    const trip = snap.data();
    if (trip.driverUid !== me.phone) throw err('permission-denied', 'Reys sizniki emas');
    if (trip.status === 'cancelled' || trip.status === 'completed') {
      return { status: trip.status, refunded: trip.refunded === true, idempotent: true };
    }
    const when = now();

    // Jo'nashdan ancha keyin «bekor» = aslida tugagan reys: refund yo'q
    // (PROPOSED, egaga ko'rsatilgan). Fraud baholash baribir ishlaydi.
    const depMs = trip.departureAt && trip.departureAt.toMillis ? trip.departureAt.toMillis() : 0;
    const afterDeparture = depMs && when.getTime() > depMs + CANCEL_AFTER_DEPARTURE_GRACE_H * 3600000;
    if (afterDeparture) {
      await tripRef.update({ status: 'completed', completedAt: when, completedReason: 'cancel_after_departure', updatedAt: when });
      return { status: 'completed', refunded: false, reason: 'after_departure' };
    }

    const amount = Number(trip.feeAmount) || 0;
    let refundedNow = false;
    if (trip.status === 'published' && amount > 0 && trip.chargedAt) {
      await refund({ usersDocId: me.usersDocId, tripId: tripRef.id, amount, version: Number(trip.billingVersion) || 1, kind: 'taxi_fee_refund', meta: { reason: 'cancelled' } });
      refundedNow = true;
    }
    await tripRef.update({
      status: 'cancelled', cancelledAt: when, refunded: refundedNow, fraudReviewed: false,
      hadAvaBooking: data.hadAvaBooking === true || trip.hadAvaBooking === true,
      'location.cancelLat': numOrNull(data.driverLat), 'location.cancelLng': numOrNull(data.driverLng),
      updatedAt: when,
    });
    return { status: 'cancelled', refunded: refundedNow, amount };
  }

  async function complete(data, context) {
    const me = await resolveCaller(context);
    const tripRef = db.collection(TRIPS).doc(String(data.tripId || ''));
    const snap = await tripRef.get();
    if (!snap.exists) throw err('not-found', 'Reys topilmadi');
    if (snap.data().driverUid !== me.phone) throw err('permission-denied', 'Reys sizniki emas');
    if (snap.data().status !== 'published') return { status: snap.data().status, idempotent: true };
    await tripRef.update({ status: 'completed', completedAt: now(), updatedAt: now() });
    return { status: 'completed' };
  }

  /**
   * D-TAXI-CANCEL-3 — RESCHEDULE: reys va komissiya SAQLANADI, faqat
   * sana/vaqt o'zgaradi. `tripId` o'sha, refund YO'Q, qayta charge YO'Q.
   * Narx ham o'zgarsa — `reprice` qoidasi (oshsa farq, pasaysa bir
   * martalik refund). Har reschedule `taxi_reschedules` da (audit).
   */
  async function reschedule(data, context) {
    const me = await resolveCaller(context);
    const tripRef = db.collection(TRIPS).doc(String(data.tripId || ''));
    const snap = await tripRef.get();
    if (!snap.exists) throw err('not-found', 'Reys topilmadi');
    const trip = snap.data();
    if (trip.driverUid !== me.phone) throw err('permission-denied', 'Reys sizniki emas');
    if (trip.status !== 'published') throw err('failed-precondition', 'Reys e\'lon holatida emas', { reason: 'not_published' });

    const when = now();
    const newDeparture = data.departureAt ? new Date(data.departureAt) : null;
    if (!newDeparture || Number.isNaN(newDeparture.getTime())) {
      throw err('invalid-argument', 'departureAt kerak');
    }
    await db.collection(RESCHEDULES).add({
      tripId: tripRef.id, uid: me.phone, accountId: me.accountId,
      oldDepartureAt: trip.departureAt || null, newDepartureAt: Timestamp.fromDate(newDeparture),
      oldScheduleDate: trip.scheduleDate || '', newScheduleDate: String(data.scheduleDate || trip.scheduleDate || ''),
      changedAt: when,
    });
    await tripRef.update({
      departureAt: Timestamp.fromDate(newDeparture),
      scheduleDate: String(data.scheduleDate || trip.scheduleDate || ''),
      startTime: String(data.startTime || trip.startTime || ''),
      rescheduleCount: (Number(trip.rescheduleCount) || 0) + 1,
      updatedAt: when,
    });

    let billing = { status: 'unchanged', delta: 0, feeAmount: trip.feeAmount };
    if (typeof data.farePerSeat === 'number' && data.farePerSeat !== trip.farePerSeat) {
      billing = await reprice({ tripId: tripRef.id, farePerSeat: data.farePerSeat }, context);
    }
    return { tripId: tripRef.id, status: 'published', rescheduled: true, billing };
  }

  exports.quoteTaxiFee = functions.https.onCall(quote);
  exports.publishTaxiTrip = functions.https.onCall(publish);
  exports.repriceTaxiTrip = functions.https.onCall(reprice);
  exports.rescheduleTaxiTrip = functions.https.onCall(reschedule);
  exports.cancelTaxiTrip = functions.https.onCall(cancel);
  exports.completeTaxiTrip = functions.https.onCall(complete);

  return {
    quote, publish, reprice, reschedule, cancel, complete, charge, refund,
    billingEnabled, resolveCaller, settleOutstanding,
  };
}

function numOrNull(v) {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

module.exports = {
  TRIPS, PRICE_CHANGES, FRAUD_CASES, AGREEMENTS, EARNINGS_ACCOUNT,
  SEAT_BASIS, RATE_BPS, BILLING_VERSION, MAX_DOWNWARD_REFUNDS,
  calculateTaxiFee, attachTaxiBilling,
};
