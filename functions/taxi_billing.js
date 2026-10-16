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
 * ── BILLING KIMDAN (D-TAXI-6.1, 2026-10-06) ────────────────────────────
 * GLOBAL FLAG YO'Q. Yagona mezon — `caps.isTaxiBillable(cap, now)`
 * (verified + billing grace tugagan). Bosqichma-bosqichlik har
 * haydovchining o'z lifecycle'ida: 4 oy starter (fee 0) → admin
 * tekshiruvi → verified → 2%. Fee'siz reyslarda ham snapshot yoziladi
 * (`quotedFee`) va fraud baholash ishlaydi.
 *
 * ── KELISHUV (D-TAXI-24.1) ─────────────────────────────────────────────
 * Starter uchun kelishuv SHART EMAS. `caps.agreementDue(taxi, status)`
 * (verification_required, verified) bo'lsa — pullik e'londan oldin
 * joriy versiya qabul qilingan bo'lishi shart.
 */

const caps = require('./capabilities_model');
const fraud = require('./taxi_fraud');
const { render, langOfPhoneTx } = require('./notif_i18n');

const TRIPS = 'taxi_trips';
const PRICE_CHANGES = 'taxi_price_changes';
/** D-TAXI-CANCEL-3 — kechiktirishlar jurnali (audit). */
const RESCHEDULES = 'taxi_reschedules';
const FRAUD_CASES = 'taxi_fraud_cases';
const AGREEMENTS = 'service_agreements';
const CAPS = 'provider_capabilities';
/** Audit M1: publish idempotentligi - server-only `{driverUid}_{requestId}` hujjatlari. */
const PUBLISH_REQUESTS = 'taxi_publish_requests';
const EARNINGS_ACCOUNT = 'earnings:ava_taxi_fee';

const SEAT_BASIS = 4;
/** Starter tugashiga shuncha kun qolganda haydovchiga «AVA haqi» xabari ko'rsatiladi (ega, 2026-10-15). */
const STARTER_NOTICE_DAYS = 3;
/** 2% = 200 bps. Butun son arifmetikasi uchun bps. */
const RATE_BPS = 200;
const BILLING_VERSION = 1;
/** Pasaytirishda refund — reys davomida nechta marta (D-TAXI-12 abuse). */
const MAX_DOWNWARD_REFUNDS = 1;

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

/**
 * Starter davri tugashiga `STARTER_NOTICE_DAYS` kun yoki kam qolganmi.
 * Faqat `starter` holatida va `window.taxi.verificationDueAt` bo'lganda.
 * Muddati o'tgan, lekin sweeper hali `verification_required` qilmagan
 * starter ham «qolgan» hisoblanadi.
 */
function starterNoticeOf(cap, status, nowDate) {
  if (status !== caps.TAXI.starter) return { starterNotice: false, starterEndsAt: null };
  const win = ((cap && cap.window) || {}).taxi || {};
  const dueMs = caps.toMillis(win.verificationDueAt);
  if (!dueMs) return { starterNotice: false, starterEndsAt: null };
  return {
    starterNotice: dueMs - nowDate.getTime() <= STARTER_NOTICE_DAYS * caps.DAY_MS,
    starterEndsAt: new Date(dueMs).toISOString(),
  };
}

// ── Kirish tekshiruvi (audit M2/H5, 2026-10) ───────────────────────────
// `publish` oldin hech narsani tekshirmasdi: o'tgan jo'nash vaqti qabul qilinar,
// noto'g'ri sana jimgina `null` bo'lardi, from/to bo'sh, `seats` cheksiz, sana/vaqt
// erkin matn. Tekshiruv PUL TEGILMASDAN OLDIN (qarz yopish ham pul harakati).
// Eski ilovalar uchun TOLERANT: `departureAt` yo'q bo'lsa eski xulq (null), `seats`
// yo'q bo'lsa 4, `scheduleDate`/`startTime` bo'sh bo'lsa o'tkazib yuboriladi.
// Narx chegarasi (min/max) QO'SHILMAGAN - ega qarori kutilmoqda.

/** Jo'nash vaqti shu davrdan ko'p o'tgan bo'lsa rad etiladi (soat farqi / sekin tarmoq uchun zaxira). */
const DEPARTURE_PAST_TOLERANCE_MS = 5 * 60 * 1000;
/** Audit M1: parallel nusxa birinchi urinish tugashini shuncha kutadi / `processing` shundan eski bo'lsa kutilmaydi. */
const PUBLISH_REPLAY_WAIT_MS = 10000;
const PUBLISH_REPLAY_POLL_MS = 200;
const PUBLISH_PROCESSING_MAX_AGE_MS = 30000;
const SEATS_MIN = 1;
const SEATS_MAX = 8;
const SCHEDULE_DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const SCHEDULE_TIME_RE = /^([01]\d|2[0-3]):([0-5]\d)$/;
const REQUEST_ID_RE = /^[A-Za-z0-9_-]{8,64}$/;

function isRealDate(y, m, d) {
  const dt = new Date(Date.UTC(y, m - 1, d));
  return dt.getUTCFullYear() === y && dt.getUTCMonth() === m - 1 && dt.getUTCDate() === d;
}

/** `departureAt` (ISO satr yoki ms). Yo'q/bo'sh -> {present:false}; noto'g'ri -> {present:true, date:null}. */
function parseDeparture(raw) {
  if (!raw) return { present: false, date: null };
  if (typeof raw !== 'string' && typeof raw !== 'number') return { present: true, date: null };
  const d = new Date(raw);
  return { present: true, date: Number.isNaN(d.getTime()) ? null : d };
}

/** @returns {string|null} xato tafsiloti yoki null (yaroqli). */
function departureProblem(date, nowMs) {
  if (!date) return 'invalid_date';
  if (date.getTime() < nowMs - DEPARTURE_PAST_TOLERANCE_MS) return 'in_past';
  return null;
}

/** `scheduleDate` YYYY-MM-DD (haqiqiy sana), `startTime` HH:MM; bo'sh/yo'q - ruxsat. */
function parseSchedule(scheduleDate, startTime) {
  const sd = scheduleDate === undefined || scheduleDate === null ? '' : scheduleDate;
  const st = startTime === undefined || startTime === null ? '' : startTime;
  if (typeof sd !== 'string' || typeof st !== 'string') return { ok: false };
  const date = sd.trim();
  const time = st.trim();
  if (date) {
    const m = SCHEDULE_DATE_RE.exec(date);
    if (!m || !isRealDate(Number(m[1]), Number(m[2]), Number(m[3]))) return { ok: false };
  }
  if (time && !SCHEDULE_TIME_RE.test(time)) return { ok: false };
  return { ok: true, scheduleDate: date, startTime: time };
}

/** Asia/Tashkent, yozgi vaqt yo'q (intercity_auto_shift.js bilan bir xil). */
const TZ_OFFSET_MS = 5 * 3600000;

/** Toshkent bo'yicha `YYYY-MM-DD` va `HH:MM` (UTC ms dan). */
function tashkentParts(ms) {
  const d = new Date(ms + TZ_OFFSET_MS);
  const p = (n) => String(n).padStart(2, '0');
  return {
    date: `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())}`,
    time: `${p(d.getUTCHours())}:${p(d.getUTCMinutes())}`,
  };
}

/** `YYYY-MM-DD` kunining Toshkent bo'yicha 23:59:59 vaqti (UTC ms) - ilova `expiresAt` ni shunday yozadi. */
function endOfTashkentDayMs(dateStr) {
  const m = SCHEDULE_DATE_RE.exec(dateStr);
  return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), 23, 59, 59) - TZ_OFFSET_MS;
}

/** `requestId` (ixtiyoriy): yo'q -> '' (eski ilova); yaroqli -> o'zi; yaroqsiz -> null. */
function parseRequestId(raw) {
  if (raw === undefined || raw === null || raw === '') return '';
  return typeof raw === 'string' && REQUEST_ID_RE.test(raw) ? raw : null;
}

/** `seats`: yo'q -> 4 (eski ilova); aks holda butun son SEATS_MIN..SEATS_MAX (raqamli satr ham). */
function parseSeats(raw) {
  if (raw === undefined || raw === null || raw === '') return { ok: true, seats: SEAT_BASIS };
  let n = Number.NaN;
  if (typeof raw === 'number') n = raw;
  else if (typeof raw === 'string' && raw.trim() !== '') n = Number(raw);
  if (!Number.isInteger(n) || n < SEATS_MIN || n > SEATS_MAX) return { ok: false };
  return { ok: true, seats: n };
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

    // D-TAXI-24.1: kelishuv faqat starter TUGAGANDAN keyin (verification_required,
    // verified). Starter — kelishuvsiz ishlaydi.
    let agreementMissing = false;
    if (caps.agreementDue('taxi', status)) {
      const agr = await db.collection(AGREEMENTS).doc(me.accountId).get();
      agreementMissing = !caps.hasCurrentAgreement(agr.exists ? agr.data() : null, 'taxi');
    }
    const agreementInfo = agreementMissing
      ? { agreementRequired: true, agreementVersion: caps.AGREEMENT_VERSIONS.taxi }
      : { agreementRequired: false };

    if (!caps.canPublishPaid(me.cap, 'taxi')) {
      // `verification_required`: ilova shu javobda kelishuvni ham taqdim
      // qiladi (agreementRequired), keyin admin tekshiruvi kutiladi.
      return {
        allowed: false,
        reason: status === caps.TAXI.verificationRequired ? 'taxi_verification_required' : 'taxi_not_allowed',
        taxiStatus: status, ...agreementInfo, ...fee, feeAmount: 0,
      };
    }
    if (agreementMissing) {
      return {
        allowed: false, reason: 'agreement_required',
        taxiStatus: status, ...agreementInfo, ...fee, feeAmount: 0,
      };
    }
    // D-TAXI-6.1: yagona mezon, global flag yo'q.
    const billable = caps.isTaxiBillable(me.cap, when);
    const feeAmount = billable ? fee.feeAmount : 0;
    const balance = billable ? await walletBalance(me.usersDocId) : null;
    return {
      allowed: true, reason: 'ok', taxiStatus: status, billable, ...agreementInfo,
      ...starterNoticeOf(me.cap, status, when),
      ...fee, feeAmount, quotedFee: fee.feeAmount,
      walletBalance: balance,
      sufficient: billable ? balance >= feeAmount : true,
    };
  }

  /**
   * Komissiyani ledger orqali oladi. Yetarli bo'lmasa `insufficient`.
   * `precheck`/`onCommit` — reys holatini AYNI tranzaksiyada tekshirish va
   * yangilash uchun (hamyon auditi Y-5: avval reys tashqarida o'qilardi).
   */
  async function charge({ usersDocId, phone, tripId, amount, version, kind, meta, precheck, onCommit }) {
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
        precheck: precheck || null,
        onCommit: onCommit || null,
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

  /**
   * Qaytim. Kalit MAQSADGA qarab alohida (hamyon auditi Y-5): avval
   * pasaytirish va bekor qilish bitta `taxiRefund:{trip}:v{version}`
   * kalitini ishlatardi — pastga reprice'dan keyin bekor qilinsa qolgan
   * komissiya qaytmasdi (ledger «allaqachon bor» deb hech narsa yozmasdi).
   */
  function deltaRefundKey(tripId, version) {
    return `taxiDeltaRefund:${tripId}:v${version}`;
  }
  function cancelRefundKey(tripId) {
    return `taxiCancelRefund:${tripId}`;
  }

  async function refund({ usersDocId, tripId, amount, key, kind, meta, precheck, onCommit }) {
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
    }, {
      mirrorBonus: true, walletLedgerType: kind, meta: { tripId, ...meta },
      precheck: precheck || null, onCommit: onCommit || null,
    });
    return { entryId: res.id, idempotent: res.idempotent };
  }

  /**
   * Reys hali shu holatdami — tranzaksiya ichida (Y-5). Parallel
   * reprice/cancel boshqasining eskirgan holatidan hisob qilmasin:
   * holat o'zgargan bo'lsa `aborted`, ilova qayta urinadi.
   */
  function tripGuard(tripRef, expect) {
    return async (tx) => {
      const s = await tx.get(tripRef);
      const t = s.exists ? (s.data() || {}) : null;
      const ok = t && t.status === expect.status
        && (Number(t.billingVersion) || 1) === expect.billingVersion
        && (Number(t.feeAmount) || 0) === expect.feeAmount;
      if (!ok) {
        throw err('aborted', 'Reys holati o\'zgardi — qayta urinib ko\'ring',
            { reason: 'trip_changed' });
      }
      return { trip: t };
    };
  }

  /**
   * Audit M1: shu `requestId` bilan boshlangan e'lonning joriy natijasi (yoki null).
   * Birinchi urinish hali ishlayotgan bo'lsa (`processing`, 30 soniyadan yosh) qisqa
   * kutiladi - parallel nusxa "to'lov kerak" deb noto'g'ri javob olmasin. Yangi reys
   * ochilmaydi, pul harakati YO'Q.
   */
  async function existingPublishResult(reqRef, me) {
    let req = await reqRef.get();
    if (!req.exists) return null;
    const startedAt = Date.now();
    while (req.exists && (req.data() || {}).status === 'processing'
      && Date.now() - Number((req.data() || {}).startedAtMs || 0) < PUBLISH_PROCESSING_MAX_AGE_MS
      && Date.now() - startedAt < PUBLISH_REPLAY_WAIT_MS) {
      await new Promise((resolve) => setTimeout(resolve, PUBLISH_REPLAY_POLL_MS));
      req = await reqRef.get();
    }
    if (!req.exists) return null;
    const tripSnap = await db.collection(TRIPS).doc(String((req.data() || {}).tripId || '_')).get();
    if (!tripSnap.exists) return null;
    const t = tripSnap.data() || {};
    const out = {
      tripId: tripSnap.id, status: t.status, feeAmount: Number(t.feeAmount) || 0, idempotent: true,
    };
    if (t.status === 'payment_required') out.walletBalance = await walletBalance(me.usersDocId);
    else out.billable = t.billable === true;
    console.log(JSON.stringify({
      action: 'publishTaxiTrip', result: 'replayed', tripId: tripSnap.id, userId: me.phone, status: t.status,
    }));
    return out;
  }

  const inputError = (reason, message, detail) => err('failed-precondition', message,
    detail ? { reason, detail } : { reason });

  /**
   * Audit M2/H5: `publish` kirishini tekshiradi va tozalaydi. Xato -
   * `failed-precondition` + `details.reason` (ilova uch tilli matn tanlaydi,
   * 25-qoida); pul harakati bundan KEYIN.
   */
  function validatePublishInput(data, nowMs) {
    const requestId = parseRequestId(data.requestId);
    if (requestId === null) {
      throw err('invalid-argument', 'requestId 8..64 belgi bo\'lishi kerak ([A-Za-z0-9_-])',
        { reason: 'request_id_invalid' });
    }
    const dep = parseDeparture(data.departureAt);
    if (dep.present) {
      const problem = departureProblem(dep.date, nowMs);
      if (problem) throw inputError('departure_in_past', 'Jo\'nash vaqti noto\'g\'ri yoki o\'tib ketgan', problem);
    }
    const from = typeof data.from === 'string' ? data.from.trim() : '';
    const to = typeof data.to === 'string' ? data.to.trim() : '';
    if (!from || !to) throw inputError('route_required', 'Yo\'nalish (qayerdan/qayerga) kerak');
    const seats = parseSeats(data.seats);
    if (!seats.ok) throw inputError('seats_invalid', `Joylar soni ${SEATS_MIN}..${SEATS_MAX} butun son bo'lishi kerak`);
    const sched = parseSchedule(data.scheduleDate, data.startTime);
    if (!sched.ok) throw inputError('schedule_invalid', 'Sana (YYYY-MM-DD) yoki vaqt (HH:MM) formati noto\'g\'ri');
    return {
      requestId, departureAt: dep.date, from, to, seats: seats.seats,
      scheduleDate: sched.scheduleDate, startTime: sched.startTime,
    };
  }

  /**
   * E'LON (D-TAXI-13): narx → komissiya → to'lov → `published`.
   * To'lovsiz `published` BO'LMAYDI. Snapshot — D-TAXI-21.
   */
  async function publish(data, context) {
    const me = await resolveCaller(context);
    data = data || {};
    // Audit M2/H5: kirish tekshiruvi - qarz yopish va komissiyadan OLDIN.
    const input = validatePublishInput(data, now().getTime());
    // Audit M1: shu `requestId` bilan avval boshlangan e'lon bo'lsa - o'sha natija
    // (yangi reys ham, qayta yechim ham, qarz yopish ham YO'Q).
    const reqRef = input.requestId
      ? db.collection(PUBLISH_REQUESTS).doc(`${me.phone}_${input.requestId}`) : null;
    if (reqRef) {
      const replay = await existingPublishResult(reqRef, me);
      if (replay) return replay;
    }
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
    const departureAt = input.departureAt;
    const snapshot = {
      driverUid: me.phone,
      usersDocId: me.usersDocId,
      accountId: me.accountId,
      taxiType: 'intercity',
      from: input.from,
      to: input.to,
      scheduleDate: input.scheduleDate,
      startTime: input.startTime,
      departureAt: departureAt ? Timestamp.fromDate(departureAt) : null,
      seats: input.seats,
      // D-TAXI-21 snapshot
      farePerSeat: q.farePerSeat,
      seatBasis: SEAT_BASIS,
      rate: q.rate,
      rateBps: RATE_BPS,
      grossBasis: q.grossBasis,
      feeAmount: q.feeAmount,
      quotedFee: q.quotedFee,
      billable: q.billable,
      billingVersion: BILLING_VERSION,
      chargedAt: null,
      status: 'payment_required',
      // D-TAXI-14 — location qaydi
      location: {
        originDeclared: input.from,
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

    // Reys hujjati va (bo'lsa) `requestId` hujjati BITTA tranzaksiyada: ikkala parallel
    // chaqiruvdan faqat bittasi yaratadi, ikkinchisi birinchisining natijasini oladi.
    const createTrip = async (tripDoc, requestStatus) => {
      const created = await db.runTransaction(async (tx) => {
        if (reqRef) {
          const r = await tx.get(reqRef);
          if (r.exists) return false;
        }
        tx.set(tripRef, tripDoc);
        if (reqRef) {
          tx.set(reqRef, {
            driverUid: me.phone, requestId: input.requestId, tripId: tripRef.id, status: requestStatus,
            startedAtMs: Date.now(), createdAt: when, updatedAt: when,
          });
        }
        return true;
      });
      if (created) return null;
      const replay = await existingPublishResult(reqRef, me);
      if (replay) return replay;
      throw err('aborted', 'E\'lon holati o\'zgardi - qayta urinib ko\'ring', { reason: 'publish_in_progress' });
    };
    const setRequestStatus = (status) => (reqRef
      ? reqRef.update({ status, updatedAt: now() }).catch((e) => {
        console.error(`taxi_publish_requests status (${reqRef.id}): ${e.message}`);
      })
      : Promise.resolve());

    if (q.feeAmount > 0) {
      const replay = await createTrip(snapshot, 'processing');
      if (replay) return replay;
      let c;
      try {
        c = await charge({
          usersDocId: me.usersDocId, phone: me.phone, tripId: tripRef.id,
          amount: q.feeAmount, version: BILLING_VERSION, kind: 'taxi_fee',
          meta: { farePerSeat: q.farePerSeat, grossBasis: q.grossBasis },
        });
      } catch (e) {
        await setRequestStatus('error');
        throw e;
      }
      if (!c.ok) {
        // D-TAXI-23: `payment_required` da qoladi, e'lon chiqmaydi.
        await setRequestStatus('payment_required');
        return { tripId: tripRef.id, status: 'payment_required', feeAmount: q.feeAmount, walletBalance: q.walletBalance };
      }
      const publishedPatch = { status: 'published', chargedAt: now(), ledgerEntryId: c.entryId, updatedAt: now() };
      if (reqRef) {
        const batch = db.batch();
        batch.update(tripRef, publishedPatch);
        batch.update(reqRef, { status: 'published', updatedAt: now() });
        await batch.commit();
      } else {
        await tripRef.update(publishedPatch);
      }
    } else {
      const replay = await createTrip({ ...snapshot, status: 'published', chargedAt: null }, 'published');
      if (replay) return replay;
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

    return { tripId: tripRef.id, status: 'published', feeAmount: q.feeAmount, billable: q.billable };
  }

  async function reviewLastCancelled(me, nextSnap, when) {
    // Fee'siz (starter/grace) bekorlar ham BAHOLANADI — verdict yoziladi,
    // pul esa faqat refund bo'lgan reysda harakatlanadi. Shunday qilib
    // starter davrida ham fraud pipeline ma'lumot beradi (D-TAXI-6.1).
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
    // Faqat HAQIQATAN refund bo'lgan reysda (starter/grace'da fee 0 edi —
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
    let takeNow = Math.max(0, Math.min(amount, bal));
    if (takeNow > 0) {
      const pcId = settlementLedger.passengerCreditAccount(usersDocId);
      try {
        await settlementLedger.postEntry(db, {
          idempotencyKey: `taxiReclaim:${tripId}`,
          kind: 'taxi_fee_reclaim', refType: 'taxi_trip', refId: tripId,
          postedBy: 'system', postedRole: 'system',
          legs: [
            { account: pcId, dr: takeNow },
            { account: EARNINGS_ACCOUNT, cr: takeNow },
          ],
        }, {
          mirrorBonus: true, walletLedgerType: 'taxi_fee_reclaim', meta: { tripId, signals },
          // Balans tashqarida o'qilgan — orada kamaygan bo'lsa wallet manfiyga
          // tushmasin (hamyon auditi O-13): u holda hammasi QARZ.
          assert: ({ accounts }) => {
            const st = accounts.get(pcId);
            if (st && st.next < 0) {
              const e = new Error('insufficient');
              e.insufficient = true;
              throw e;
            }
          },
        });
      } catch (e) {
        if (!(e && e.insufficient)) throw e;
        takeNow = 0;
      }
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

  /**
   * Qarz bo'lsa — yangi komissiyadan OLDIN yopiladi (CANCEL-6).
   *
   * Hamyon auditi O-13: avval kalit sekund-timestamp edi, qarz tashqarida
   * o'qilib `debt.taxi: 0` alohida yozilardi → parallel publish qarzni ikki
   * marta yechardi. Endi kalit «raund» hisoblagichidan (`debt.taxiRounds`,
   * `debt` — server-only maydon), qarz va raund tranzaksiyada qayta
   * tekshiriladi, nolga tushirish AYNI tranzaksiyada, wallet manfiy emas.
   */
  async function settleOutstanding(me) {
    const debtMap = (me.cap || {}).debt || {};
    const debt = Number(debtMap.taxi) || 0;
    if (debt <= 0) return { settled: 0, outstanding: 0 };
    const bal = await walletBalance(me.usersDocId);
    if (bal < debt) return { settled: 0, outstanding: debt, walletBalance: bal };
    const round = Number(debtMap.taxiRounds) || 0;
    const capRef = db.collection(CAPS).doc(me.accountId);
    const pcId = settlementLedger.passengerCreditAccount(me.usersDocId);
    let res;
    try {
      res = await settlementLedger.postEntry(db, {
        idempotencyKey: `taxiDebt:${me.accountId}:r${round}`,
        kind: 'taxi_fee_debt_settlement', refType: 'provider', refId: me.accountId,
        postedBy: 'system', postedRole: 'system',
        legs: [
          { account: pcId, dr: debt },
          { account: EARNINGS_ACCOUNT, cr: debt },
        ],
      }, {
        mirrorBonus: true, walletLedgerType: 'taxi_fee_debt_settlement',
        meta: { accountId: me.accountId, round },
        precheck: async (tx) => {
          const c = ((await tx.get(capRef)).data() || {}).debt || {};
          if ((Number(c.taxi) || 0) !== debt || (Number(c.taxiRounds) || 0) !== round) {
            const e = new Error('debt_changed');
            e.debtChanged = true;
            throw e;
          }
          return null;
        },
        assert: ({ accounts }) => {
          const st = accounts.get(pcId);
          if (st && st.next < 0) {
            const e = new Error('insufficient');
            e.insufficient = true;
            throw e;
          }
        },
        onCommit: (tx) => tx.set(capRef, {
          debt: { taxi: 0, taxiRounds: round + 1 }, updatedAt: now(),
        }, { merge: true }),
      });
    } catch (e) {
      if (!(e && (e.debtChanged || e.insufficient))) throw e;
      res = { idempotent: true };
    }
    if (res.idempotent) {
      // Boshqa so'rov yopgan yoki holat o'zgargan — haqiqiy qoldiqni qaytaramiz.
      const c = ((await capRef.get()).data() || {}).debt || {};
      const left = Number(c.taxi) || 0;
      return left > 0
        ? { settled: 0, outstanding: left, walletBalance: await walletBalance(me.usersDocId) }
        : { settled: 0, outstanding: 0 };
    }
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
    const baseVersion = Number(trip.billingVersion) || 1;
    const version = baseVersion + 1;
    // Y-5: ledger yozuvi va reys yangilanishi BITTA tranzaksiyada, reys
    // tashqarida o'qilgan holatda ekani tranzaksiya ichida tekshiriladi.
    const guard = tripGuard(tripRef, { status: 'published', billingVersion: baseVersion, feeAmount: oldFee });

    await db.collection(PRICE_CHANGES).add({
      tripId: tripRef.id, uid: me.phone, accountId: me.accountId,
      oldFare, newFare: fee.farePerSeat, oldFee, newFee, changedAt: when,
    });

    // Kalit allaqachon bor (parallel yoki qayta yuborilgan so'rov) — natija
    // reysning HOZIRGI holatidan: shu narx shu versiyada qo'llangan bo'lsa
    // muvaffaqiyat, aks holda boshqa so'rov yutgan → `aborted`.
    const resolveIdempotent = async () => {
      const t = (await tripRef.get()).data() || {};
      if ((Number(t.billingVersion) || 1) >= version && t.farePerSeat === fee.farePerSeat) {
        return { status: 'ok', idempotent: true, feeAmount: Number(t.feeAmount) || 0 };
      }
      throw err('aborted', 'Reys holati o\'zgardi — qayta urinib ko\'ring', { reason: 'trip_changed' });
    };

    if (newFee > oldFee) {
      const delta = newFee - oldFee;
      const c = await charge({
        usersDocId: me.usersDocId, phone: me.phone, tripId: tripRef.id, amount: delta,
        version, kind: 'taxi_fee_delta', meta: { oldFare, newFare: fee.farePerSeat },
        precheck: guard,
        onCommit: (tx) => tx.update(tripRef, {
          farePerSeat: fee.farePerSeat, grossBasis: fee.grossBasis, feeAmount: newFee,
          billingVersion: version, repriceStatus: 'ok', pendingFare: null, updatedAt: when,
        }),
      });
      if (!c.ok) {
        // Qo'shimcha to'lamasdan yangi narx aktiv BO'LMAYDI.
        await tripRef.update({ pendingFare: fee.farePerSeat, pendingFee: newFee, pendingDelta: delta, repriceStatus: 'payment_required', updatedAt: when });
        return { status: 'payment_required', delta, walletBalance: await walletBalance(me.usersDocId) };
      }
      if (c.idempotent) return resolveIdempotent();
      return { status: 'ok', delta, feeAmount: newFee };
    }

    const refundsSoFar = Number(trip.downwardRefunds) || 0;
    const patch = (refunded) => ({
      farePerSeat: fee.farePerSeat, grossBasis: fee.grossBasis,
      feeAmount: refunded ? newFee : oldFee,
      downwardRefunds: refundsSoFar + (refunded ? 1 : 0),
      billingVersion: version, repriceStatus: 'ok', updatedAt: when,
    });
    if (newFee < oldFee && refundsSoFar < MAX_DOWNWARD_REFUNDS) {
      const refunded = oldFee - newFee;
      const r = await refund({
        usersDocId: me.usersDocId, tripId: tripRef.id, amount: refunded,
        key: deltaRefundKey(tripRef.id, version), kind: 'taxi_fee_delta_refund',
        meta: { oldFare, newFare: fee.farePerSeat },
        precheck: guard,
        onCommit: (tx) => tx.update(tripRef, patch(true)),
      });
      if (r.idempotent) return resolveIdempotent();
      return { status: 'ok', delta: -refunded, feeAmount: newFee, refundLimited: false };
    }
    // Pul harakati yo'q (narx teng yoki refund chegarasi) — baribir
    // tranzaksiyada, reys holati o'zgarmagan bo'lsagina.
    await db.runTransaction(async (tx) => {
      await guard(tx);
      tx.update(tripRef, patch(false));
    });
    return { status: 'ok', delta: 0, feeAmount: oldFee, refundLimited: newFee < oldFee };
  }

  /**
   * Audit H3: shu reys davomida AVA orqali tasdiqlangan (`confirmed`/`completed`) bron
   * bormi - `intercity_bookings`dan (driverId = haydovchi telefoni, 12 yoki 9 xonali;
   * reys yaratilgandan KEYIN ochilgan bronlar). `pending`/`cancelled`/`expired` sanalmaydi.
   * O'qish xatosi - `false` (fraud tomoniga xavfsiz: noaniq holatda pul qaytarib olinmaydi);
   * refund siyosatiga ta'sir qilmaydi.
   */
  async function serverHadAvaBooking(me, trip) {
    const sinceMs = tsMillis(trip.createdAt);
    const ids = [...new Set([me.phone, me.phone.length === 12 ? me.phone.slice(3) : me.phone])];
    try {
      const snaps = await Promise.all(ids.map((id) => db.collection('intercity_bookings')
        .where('driverId', '==', id).where('status', 'in', ['confirmed', 'completed']).get()));
      return snaps.some((s) => s.docs.some((d) => tsMillis((d.data() || {}).createdAt) >= sinceMs));
    } catch (e) {
      console.error(JSON.stringify({
        action: 'cancelTaxiTrip', result: 'error', errorCode: 'HAD_BOOKING_LOOKUP_FAILED',
        userId: me.phone, message: e && e.message,
      }));
      return false;
    }
  }

  /**
   * D-TAXI-15: bekor → komissiya wallet'ga `refund`.
   *
   * D-TAXI-CANCEL-9 (2026-10-06): jo'nash vaqtidan KEYIN ham bekor qilish
   * mumkin va refund beriladi — yo'lovchi o'z vaqtida topilmay qolishi
   * mumkin. «Jo'nashdan 2 soat keyin = completed, refund yo'q» qoidasi
   * BEKOR. Soxta otmena faqat fraud dalillari bilan (CANCEL-4…7):
   * `late_cancel` — tasdiqlovchi SIGNAL, bekorni taqiqlamaydi.
   */
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
    const amount = Number(trip.feeAmount) || 0;
    // Audit H3: `hadAvaBooking` klientdan KELMAYDI (18-qoida) - server `intercity_bookings`dan
    // hisoblaydi. Klient qiymati fraud/refund qaroriga ta'sir qilmaydi, faqat log'da solishtiriladi.
    const hadAvaBooking = (await serverHadAvaBooking(me, trip)) || trip.hadAvaBooking === true;
    if ((data.hadAvaBooking === true) !== hadAvaBooking) {
      console.log(JSON.stringify({
        action: 'cancelTaxiTrip', result: 'had_booking_client_mismatch', tripId: tripRef.id,
        userId: me.phone, client: data.hadAvaBooking === true, server: hadAvaBooking,
      }));
    }
    const cancelPatch = (refunded) => ({
      status: 'cancelled', cancelledAt: when, refunded, fraudReviewed: false,
      hadAvaBooking,
      'location.cancelLat': numOrNull(data.driverLat), 'location.cancelLng': numOrNull(data.driverLng),
      updatedAt: when,
    });
    if (trip.status === 'published' && amount > 0 && trip.chargedAt) {
      // Y-5: o'z kaliti (pasaytirish refund'i bilan to'qnashmaydi) + reys
      // holati AYNI tranzaksiyada tekshiriladi va `cancelled` qilinadi.
      const r = await refund({
        usersDocId: me.usersDocId, tripId: tripRef.id, amount,
        key: cancelRefundKey(tripRef.id), kind: 'taxi_fee_refund', meta: { reason: 'cancelled' },
        precheck: tripGuard(tripRef, {
          status: 'published', billingVersion: Number(trip.billingVersion) || 1, feeAmount: amount,
        }),
        onCommit: (tx) => tx.update(tripRef, cancelPatch(true)),
      });
      if (r.idempotent) {
        const t = (await tripRef.get()).data() || {};
        return { status: t.status, refunded: t.refunded === true, idempotent: true };
      }
      return { status: 'cancelled', refunded: true, amount };
    }
    // Pulsiz bekor — baribir tranzaksiyada (parallel bekor/charge bilan).
    const res = await db.runTransaction(async (tx) => {
      const s = await tx.get(tripRef);
      const t = s.data() || {};
      if (t.status === 'cancelled' || t.status === 'completed') {
        return { status: t.status, refunded: t.refunded === true, idempotent: true };
      }
      if (t.status === 'published' && (Number(t.feeAmount) || 0) > 0 && t.chargedAt) {
        throw err('aborted', 'Reys holati o\'zgardi — qayta urinib ko\'ring', { reason: 'trip_changed' });
      }
      tx.update(tripRef, cancelPatch(false));
      return { status: 'cancelled', refunded: false, amount };
    });
    return res;
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
   * Audit H6: qo'lda ko'chirish BITTA tranzaksiyada hammasini bir xil qiladi - reys, uning
   * pending/confirmed bronlari (`departureTime`, eslatma qayta), `schedules` e'loni
   * (`date/startTime/expiresAt` - ilovaning `closeExpiredForDriver` i ko'chirilgan e'lonni
   * eski `expiresAt` bo'yicha yopib qo'ymasin), `intercity_drivers` e'loni (shu reysga
   * tegishli bo'lsa) va yo'lovchilarga uch tilli xabar (deterministik id).
   * Idempotent: xuddi shu vaqtga qayta chaqiruv hech narsa yozmaydi. Holat tranzaksiya ichida
   * qayta tekshiriladi (parallel bekor/reprice/avto-surish bilan).
   */
  async function applyReschedule({ tripRef, me, newDeparture, newDate, newTime, when }) {
    const FieldValue = admin.firestore.FieldValue;
    const newMs = newDeparture.getTime();
    const ids = [...new Set([me.phone, me.phone.length === 12 ? me.phone.slice(3) : me.phone])];
    const [hh, mm] = newTime.split(':').map(Number);
    const out = await db.runTransaction(async (tx) => {
      const tSnap = await tx.get(tripRef);
      const t = tSnap.exists ? (tSnap.data() || {}) : null;
      if (!t || t.status !== 'published' || t.driverUid !== me.phone) {
        throw err('aborted', 'Reys holati o\'zgardi — qayta urinib ko\'ring', { reason: 'trip_changed' });
      }
      if (tsMillis(t.departureAt) === newMs && t.scheduleDate === newDate && t.startTime === newTime) {
        return { idempotent: true };
      }

      // ── Barcha o'qishlar yozishdan oldin ──
      const bookings = [];
      const listings = [];
      const schedules = [];
      for (const id of ids) {
        const bs = await tx.get(db.collection('intercity_bookings')
          .where('driverId', '==', id).where('status', 'in', ['pending', 'confirmed']));
        bookings.push(...bs.docs);
        const ls = await tx.get(db.collection('intercity_drivers').doc(id));
        if (ls.exists && String((ls.data() || {}).billingTripId || '') === tripRef.id) listings.push(ls);
        if (t.scheduleDate) {
          const ss = await tx.get(db.collection('schedules')
            .where('driverId', '==', id).where('taxiType', '==', 'intercity')
            .where('date', '==', t.scheduleDate).where('isActive', '==', true));
          schedules.push(...ss.docs);
        }
      }
      const langs = new Map();
      for (const b of bookings) {
        const phone = String((b.data() || {}).userPhone || '').replace(/\D/g, '');
        if (phone.length >= 9 && !langs.has(phone)) langs.set(phone, await langOfPhoneTx(tx, db, phone));
      }

      // ── Yozishlar ──
      const w = rescheduleWrites({
        tripId: tripRef.id, trip: t, uid: me.phone, accountId: me.accountId,
        newDeparture, scheduleDate: newDate, startTime: newTime, when, Timestamp, source: 'driver',
      });
      const count = w.tripPatch.rescheduleCount;
      tx.set(db.collection(RESCHEDULES).doc(`manual_${tripRef.id}_${count}`), w.audit);
      tx.update(tripRef, w.tripPatch);
      for (const l of listings) {
        tx.update(l.ref, { scheduleDate: newDate, hour: hh, minute: mm, updatedAt: FieldValue.serverTimestamp() });
      }
      const expiresAt = Timestamp.fromMillis(endOfTashkentDayMs(newDate));
      for (const s of schedules) tx.update(s.ref, { date: newDate, startTime: newTime, expiresAt });
      const dateText = `${newDate.slice(8, 10)}.${newDate.slice(5, 7)}`;
      for (const b of bookings) {
        tx.update(b.ref, {
          departureTime: Timestamp.fromDate(newDeparture),
          departureReminderSent: false, // eslatma yangi vaqtga qayta yuborilsin
          rescheduledAt: when,
        });
        const phone = String((b.data() || {}).userPhone || '').replace(/\D/g, '');
        if (phone.length < 9) continue;
        const { title, body } = render('reschedule_passenger', langs.get(phone), { date: dateText, time: newTime });
        tx.set(db.collection('notifications').doc(`resched_pax_${tripRef.id}_${count}_${b.id}`), {
          targetPhone: phone, title, body, type: 'intercity_trip_rescheduled', bookingId: b.id,
          sent: false, createdAt: FieldValue.serverTimestamp(),
        });
      }
      return { idempotent: false, bookings: bookings.length, schedules: schedules.length, listings: listings.length };
    });
    console.log(JSON.stringify({
      action: 'rescheduleTaxiTrip', result: out.idempotent ? 'noop' : 'moved', tripId: tripRef.id,
      userId: me.phone, bookings: out.bookings || 0, schedules: out.schedules || 0, listings: out.listings || 0,
    }));
    return out;
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
    const newDeparture = parseDeparture(data.departureAt).date;
    if (!newDeparture) {
      throw err('invalid-argument', 'departureAt kerak');
    }
    // Audit M2: yangi vaqt o'tmishda bo'lmasin; sana/vaqt formati to'g'ri bo'lsin.
    if (departureProblem(newDeparture, when.getTime())) {
      throw inputError('departure_in_past', 'Yangi jo\'nash vaqti o\'tib ketgan', 'in_past');
    }
    const sched = parseSchedule(data.scheduleDate, data.startTime);
    if (!sched.ok) throw inputError('schedule_invalid', 'Sana (YYYY-MM-DD) yoki vaqt (HH:MM) formati noto\'g\'ri');
    const parts = tashkentParts(newDeparture.getTime());
    const moved = await applyReschedule({
      tripRef, me, newDeparture,
      newDate: sched.scheduleDate || parts.date,
      newTime: sched.startTime || parts.time,
      when,
    });

    let billing = { status: 'unchanged', delta: 0, feeAmount: trip.feeAmount };
    if (typeof data.farePerSeat === 'number' && data.farePerSeat !== trip.farePerSeat) {
      billing = await reprice({ tripId: tripRef.id, farePerSeat: data.farePerSeat }, context);
    }
    return {
      tripId: tripRef.id, status: 'published', rescheduled: true,
      ...(moved.idempotent ? { idempotent: true } : {}), billing,
    };
  }

  exports.quoteTaxiFee = functions.https.onCall(quote);
  exports.publishTaxiTrip = functions.https.onCall(publish);
  exports.repriceTaxiTrip = functions.https.onCall(reprice);
  exports.rescheduleTaxiTrip = functions.https.onCall(reschedule);
  exports.cancelTaxiTrip = functions.https.onCall(cancel);
  exports.completeTaxiTrip = functions.https.onCall(complete);

  return {
    quote, publish, reprice, reschedule, cancel, complete, charge, refund,
    resolveCaller, settleOutstanding,
  };
}

/**
 * Kechiktirish yozuvlari: reys patch + audit hujjati. Qo'lda (`reschedule`,
 * haydovchi) va avtomatik (`intercity_auto_shift.js`, `source: 'auto_shift'`)
 * KECHIKTIRISH BIR MANBADAN — reys va komissiya saqlanadi, faqat sana/vaqt.
 * Sof funksiya: yozishni chaqiruvchi (tranzaksiya yoki oddiy) bajaradi.
 */
function rescheduleWrites({
  tripId, trip, uid, accountId, newDeparture, scheduleDate, startTime, when, Timestamp, source,
}) {
  const newDate = String(scheduleDate || trip.scheduleDate || '');
  return {
    audit: {
      tripId, uid, accountId, source,
      oldDepartureAt: trip.departureAt || null,
      newDepartureAt: Timestamp.fromDate(newDeparture),
      oldScheduleDate: trip.scheduleDate || '',
      newScheduleDate: newDate,
      changedAt: when,
    },
    tripPatch: {
      departureAt: Timestamp.fromDate(newDeparture),
      scheduleDate: newDate,
      startTime: String(startTime || trip.startTime || ''),
      rescheduleCount: (Number(trip.rescheduleCount) || 0) + 1,
      updatedAt: when,
    },
  };
}

function tsMillis(v) {
  if (!v) return 0;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function numOrNull(v) {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

module.exports = {
  TRIPS, PRICE_CHANGES, RESCHEDULES, FRAUD_CASES, AGREEMENTS, EARNINGS_ACCOUNT, PUBLISH_REQUESTS,
  rescheduleWrites,
  SEAT_BASIS, RATE_BPS, BILLING_VERSION, MAX_DOWNWARD_REFUNDS, STARTER_NOTICE_DAYS,
  calculateTaxiFee, starterNoticeOf, attachTaxiBilling,
  DEPARTURE_PAST_TOLERANCE_MS, SEATS_MIN, SEATS_MAX,
};
