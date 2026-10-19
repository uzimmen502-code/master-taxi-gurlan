/**
 * KAFE-RESTORAN — stol bron (S5, D-REST-23; docs/kafe_restoran_taklifi_uz.md §10.1, D-REST-38).
 *
 * Ega qarorlari (CONFIRMED, 2026-10-19):
 *   - AVA xizmat haqi: 1–5 kishi 50 000 · 6–10 kishi 150 000 · 11+ kishi 400 000 so'm; 2 % YO'Q;
 *   - haqni RESTORAN to'laydi — restoran hamyonidan, bronni QABUL QILISHDA; hamyonda yetmasa qabul qila olmaydi;
 *   - mijoz bekor qilsa yoki kelmasa — haq QAYTARILMAYDI; qabuldan keyin RESTORAN bekor qilsa ham qaytarilmaydi
 *     va bekor qilish restoran hisobida belgilanadi; mijozdan restoran o'zi oladi (ilovadan tashqarida);
 *   - force-majeure: admin har birini ko'rib qo'lda qaytaradi (audit jurnali, 41-qoida).
 * Qolgan qiymatlar PROPOSED (ega aytmagan; «hammasini oxiriga yetkaz» buyrug'i bilan qabul qilingan, 2026-10-19) va
 * `settings/restaurant_bookings` da versiyalangan, kodga qotirilmagan (9-qoida): tarif pog'onalari, slot uzunligi,
 * oldindan muddat, qabul muddati, oylik bekor limiti, bitta mijozning faol bronlari.
 *
 * Ma'lumot modeli:
 *   - `restaurant_bookings/{bookingId}` — brondagi joriy holat; id = `bk_` + hash(uid + idempotencyKey) (takroriy
 *     chaqiruv ikkinchi bron yaratmaydi — 21-qoida). Hodisalar (o'zgarmas tarix, 16-qoida): `.../events/{auto}`.
 *   - Haq summasi bron yaratilganda `fee` ga SNAPSHOT bo'ladi (`fee.amount`, `fee.version` = `tariffVersion`):
 *     tarif keyin o'zgarsa eski bronning haqi o'zgarmaydi (9-qoida). Yechish `bookingFee_{id}_v{n}` kaliti bilan idempotent.
 *   - Restoran hujjati: `acceptsBookings` (bool), `bookingSeats` (bir slotdagi o'rinlar soni, stol xaritasi YO'Q),
 *     `bookingNote` (mijozga zakalat matni, erkin) — a'zo yozadi; `bookingCancels` (so'nggi bekor qilish vaqtlari)
 *     va avtomatik o'chirish belgisi — faqat shu modul.
 * Sig'im: tasdiqlangan bronlar `|start_i − start| < slot` bo'lsa o'rinlarni band qiladi (konservativ: bir-biriga
 * to'g'ri kelmaydigan ikki bron uchinchisiga ikkalasi ham hisoblanishi mumkin). Tekshiruv so'rovda (erta rad) VA
 * qabulda tranzaksiya ichida (poyga: ikki parallel qabulda faqat bittasi o'tadi — 22-qoida).
 *
 * Diagnostika kodlari: BOOKINGS_OFF, BOOKINGS_INTERNAL_ONLY, IDEMPOTENCY_KEY_INVALID, RESTAURANT_ID_REQUIRED,
 * GUESTS_INVALID, BOOKING_TIME_INVALID, BOOKING_TOO_SOON, BOOKING_TOO_FAR, RESTAURANT_NOT_FOUND, RESTAURANT_NOT_APPROVED,
 * OWN_RESTAURANT, BOOKINGS_NOT_ACCEPTED, SEATS_NOT_CONFIGURED, RESTAURANT_PAUSED, BOOKING_CLOSED_AT_TIME,
 * TOO_MANY_ACTIVE_BOOKINGS, DUPLICATE_BOOKING, NO_CAPACITY, BOOKING_NOT_FOUND, NOT_BOOKING_OWNER, NOT_RESTAURANT_MEMBER,
 * BOOKING_INVALID_TRANSITION, BOOKING_EXPIRED, RESTAURANT_WALLET_UNKNOWN, RESTAURANT_WALLET_INSUFFICIENT,
 * FEE_NOT_CHARGED, FEE_ALREADY_REFUNDED, CONTENTION_RETRY, TIERS_INVALID, STAGE_INVALID, RULES_INVALID, TESTERS_INVALID.
 * Foydalanuvchi matni klientda, 3 tilda (25-qoida). Logda telefon YO'Q (24, 40-qoida): faqat id'lar.
 */
'use strict';

const crypto = require('crypto');

const BOOKINGS = 'restaurant_bookings';
const EVENTS = 'events';
const RESTAURANTS = 'restaurants';
const MEMBERS = 'members';
const CONFIG_DOC = ['settings', 'restaurant_bookings'];
const HISTORY = 'restaurant_bookings_history';
const ADMIN_AUDIT = 'admin_audit';
const MODULE_ID = 'restaurants';
const STAGES = Object.freeze(['off', 'internal', 'public']);

/** Holatlar (markaziy ro'yxat, 17-qoida). */
const BS = Object.freeze({
  requested: 'requested',
  confirmed: 'confirmed',
  rejected: 'rejected',
  expired: 'expired',
  cancelledByGuest: 'cancelled_by_guest',
  cancelledByRestaurant: 'cancelled_by_restaurant',
});

/** Ruxsat etilgan o'tishlar (server tekshiradi). */
const TRANSITIONS = Object.freeze({
  [BS.requested]: [BS.confirmed, BS.rejected, BS.expired, BS.cancelledByGuest],
  [BS.confirmed]: [BS.cancelledByGuest, BS.cancelledByRestaurant],
  [BS.rejected]: [],
  [BS.expired]: [],
  [BS.cancelledByGuest]: [],
  [BS.cancelledByRestaurant]: [],
});

function canTransition(from, to) {
  const allowed = TRANSITIONS[from];
  return !!allowed && allowed.includes(to);
}

const MIN = 60 * 1000;
const DAY = 24 * 60 * MIN;

/** Ega tarifi (CONFIRMED) + PROPOSED qoidalar. Klient shu qiymatlarni `settings` dan o'qiydi (parity testi). */
const DEFAULTS = Object.freeze({
  tiers: Object.freeze([
    Object.freeze({ upTo: 5, fee: 50000 }),
    Object.freeze({ upTo: 10, fee: 150000 }),
    Object.freeze({ upTo: 100, fee: 400000 }),
  ]),
  slotMin: 120,
  minLeadMin: 60,
  maxDays: 30,
  acceptCapMin: 120,
  acceptBeforeMin: 30,
  cancelLimit30d: 3,
  maxActivePerGuest: 5,
});

const LIMITS = Object.freeze({
  maxTiers: 8, maxUpTo: 500, maxFee: 10000000,
  slotMin: [30, 480], minLeadMin: [0, 24 * 60], maxDays: [1, 180],
  acceptCapMin: [5, 24 * 60], acceptBeforeMin: [0, 24 * 60], cancelLimit30d: [1, 30], maxActivePerGuest: [1, 50],
});

function str(v, max) {
  return String(v == null ? '' : v).trim().slice(0, max);
}

/** Haq pog'onalari: o'sib boruvchi `upTo` (butun), `fee` butun so'm. Xato bo'lsa `null`. */
function sanitizeTiers(raw) {
  if (!Array.isArray(raw) || raw.length < 1 || raw.length > LIMITS.maxTiers) return null;
  const out = [];
  let prev = 0;
  for (const t of raw) {
    if (!t || typeof t !== 'object') return null;
    const upTo = t.upTo;
    const fee = t.fee;
    if (!Number.isInteger(upTo) || upTo <= prev || upTo > LIMITS.maxUpTo) return null;
    if (!Number.isInteger(fee) || fee < 0 || fee > LIMITS.maxFee) return null;
    out.push({ upTo, fee });
    prev = upTo;
  }
  return out;
}

/** Mehmonlar soniga mos haq pog'onasi; son pog'onalardan oshsa yoki noto'g'ri bo'lsa `null` (bron mumkin emas). */
function tierFor(guests, tiers) {
  if (!Number.isInteger(guests) || guests < 1) return null;
  for (const t of tiers) if (guests <= t.upTo) return t;
  return null;
}

/** Bron identifikatori: `bk_` + hash(uid:key) — deterministik (idempotent). */
function bookingIdFor(uid, key) {
  return `bk_${crypto.createHash('sha256').update(`${uid}:${key}`).digest('hex').slice(0, 24)}`;
}

/** Bron vaqti oynasi: `null` — to'g'ri; aks holda xato kodi. */
function checkWindow(nowMs, startMs, cfg) {
  const lead = startMs - nowMs;
  if (lead < cfg.minLeadMin * MIN) return 'BOOKING_TOO_SOON';
  if (lead > cfg.maxDays * DAY) return 'BOOKING_TOO_FAR';
  return null;
}

/** Restoran javob berish muddati: so'rovdan `acceptCapMin` yoki bron vaqtidan `acceptBeforeMin` oldin (qaysi biri avval). */
function acceptDeadlineMs(nowMs, startMs, cfg) {
  return Math.min(nowMs + cfg.acceptCapMin * MIN, startMs - cfg.acceptBeforeMin * MIN);
}

/** Tasdiqlangan bronlar (ro'yxat) ichida `startMs` bilan sig'im bo'yicha to'qnashadiganlar yig'indisi. */
function seatsUsed(confirmed, startMs, slotMin, excludeId) {
  let used = 0;
  for (const b of confirmed) {
    if (excludeId && b.id === excludeId) continue;
    if (Math.abs(b.startMs - startMs) < slotMin * MIN) used += b.guests;
  }
  return used;
}

/** `settings/restaurant_bookings` (qisman) → to'liq, tekshirilgan sozlama (yoki HttpsError). */
function mergeConfig(input, current, { fail, canonicalUid }) {
  const d = input || {};
  const cur = current || {};
  let stage = STAGES.includes(cur.stage) ? cur.stage : 'off';
  if (d.stage != null) {
    if (!STAGES.includes(d.stage)) throw fail('invalid-argument', 'STAGE_INVALID');
    stage = d.stage;
  }
  let tiers = sanitizeTiers(cur.tiers) || DEFAULTS.tiers.map((t) => ({ ...t }));
  if (d.tiers != null) {
    tiers = sanitizeTiers(d.tiers);
    if (!tiers) throw fail('invalid-argument', 'TIERS_INVALID');
  }
  const rule = (key) => {
    const raw = d[key] != null && d[key] !== '' ? d[key] : (cur[key] != null ? cur[key] : DEFAULTS[key]);
    const n = Number(raw);
    const [lo, hi] = LIMITS[key];
    if (!Number.isInteger(n) || n < lo || n > hi) throw fail('invalid-argument', 'RULES_INVALID', { field: key });
    return n;
  };
  let testerIds = Array.isArray(cur.testerIds) ? cur.testerIds : [];
  if (d.testerIds != null) {
    if (!Array.isArray(d.testerIds) || d.testerIds.length > 200) throw fail('invalid-argument', 'TESTERS_INVALID');
    testerIds = [...new Set(d.testerIds.map((x) => canonicalUid(String(x || ''))))];
    if (testerIds.some((x) => !/^\d{12}$/.test(x))) throw fail('invalid-argument', 'TESTERS_INVALID');
  }
  return {
    stage,
    testerIds,
    tiers,
    slotMin: rule('slotMin'),
    minLeadMin: rule('minLeadMin'),
    maxDays: rule('maxDays'),
    acceptCapMin: rule('acceptCapMin'),
    acceptBeforeMin: rule('acceptBeforeMin'),
    cancelLimit30d: rule('cancelLimit30d'),
    maxActivePerGuest: rule('maxActivePerGuest'),
  };
}

function attachRestaurantBookings(exportsObj, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, settlementLedger, requireCallerRoles, notifyUserInApp,
    isOpenAt, tashkentLabel, EARNINGS_ACCOUNT, now: nowFn,
  } = deps;
  const now = nowFn || (() => new Date());
  const HttpsError = functions.https.HttpsError;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const inc = (n) => admin.firestore.FieldValue.increment(n);
  const tsOf = (ms) => admin.firestore.Timestamp.fromMillis(ms);
  const fail = (status, code, extra = {}) => new HttpsError(status, code, { code, ...extra });

  function log(action, fields) {
    console.log(JSON.stringify({ module: MODULE_ID, action: `booking_${action}`, ...fields }));
  }

  function requirePhoneUid(context) {
    if (!context || !context.auth) throw fail('unauthenticated', 'AUTH_REQUIRED');
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length < 12) throw fail('unauthenticated', 'PHONE_TOKEN_REQUIRED');
    return uid;
  }

  const msOf = (t) => (t && typeof t.toMillis === 'function' ? t.toMillis() : null);

  async function findUserRef(uid12) {
    const ids = uid12.length === 12 && uid12.startsWith('998') ? [uid12, uid12.slice(3)] : [uid12];
    for (const id of ids) {
      const s = await db.collection('users').doc(id).get();
      if (s.exists) return { ref: s.ref, data: s.data() || {} };
    }
    return null;
  }

  /** Sozlama + darvoza (42-qoida). Hujjat yo'q = OFF: server o'zi hech narsani yoqmaydi. */
  async function loadConfig() {
    const snap = await db.collection(CONFIG_DOC[0]).doc(CONFIG_DOC[1]).get();
    const cur = snap.exists ? (snap.data() || {}) : null;
    if (!cur) return { cfg: null, version: 0 };
    const tiers = sanitizeTiers(cur.tiers) || DEFAULTS.tiers.map((t) => ({ ...t }));
    const pick = (k) => (Number.isInteger(cur[k]) ? cur[k] : DEFAULTS[k]);
    return {
      version: Number.isInteger(cur.version) ? cur.version : 0,
      cfg: {
        stage: STAGES.includes(cur.stage) ? cur.stage : 'off',
        testerIds: Array.isArray(cur.testerIds) ? cur.testerIds.map((x) => canonicalUid(String(x))) : [],
        tiers,
        slotMin: pick('slotMin'),
        minLeadMin: pick('minLeadMin'),
        maxDays: pick('maxDays'),
        acceptCapMin: pick('acceptCapMin'),
        acceptBeforeMin: pick('acceptBeforeMin'),
        cancelLimit30d: pick('cancelLimit30d'),
        maxActivePerGuest: pick('maxActivePerGuest'),
      },
    };
  }

  function requireStage(cfg, uid) {
    if (!cfg || cfg.stage === 'off') throw fail('failed-precondition', 'BOOKINGS_OFF');
    if (cfg.stage === 'internal' && !cfg.testerIds.includes(uid)) throw fail('failed-precondition', 'BOOKINGS_INTERNAL_ONLY');
  }

  function addEvent(t, bookingRef, { from, to, actor, actorId, reason = '', meta = {} }) {
    t.set(bookingRef.collection(EVENTS).doc(), {
      from: from || null, to, actor, actorId: actorId || null, reason, meta, at: ts(),
    });
  }

  async function requireMemberInTx(t, restaurantId, uid) {
    const rRef = db.collection(RESTAURANTS).doc(restaurantId);
    const [rSnap, mSnap] = await Promise.all([t.get(rRef), t.get(rRef.collection(MEMBERS).doc(uid))]);
    if (!rSnap.exists) throw fail('not-found', 'RESTAURANT_NOT_FOUND');
    if (!mSnap.exists) throw fail('permission-denied', 'NOT_RESTAURANT_MEMBER');
    return { rRef, r: rSnap.data() || {} };
  }

  const toBooking = (doc) => {
    const d = doc.data() || {};
    return { id: doc.id, guests: Number(d.guests) || 0, startMs: msOf(d.startAt) || 0, status: d.status };
  };

  /** Restoranning shu vaqt atrofidagi TASDIQLANGAN bronlari (tranzaksiya ichida o'qiladi). */
  async function confirmedAround(t, restaurantId, startMs, slotMin) {
    const q = db.collection(BOOKINGS)
      .where('restaurantId', '==', restaurantId)
      .where('startAt', '>', tsOf(startMs - slotMin * MIN))
      .where('startAt', '<', tsOf(startMs + slotMin * MIN));
    const snap = await t.get(q);
    return snap.docs.map(toBooking).filter((b) => b.status === BS.confirmed);
  }

  // ── Notifications (best-effort, tranzaksiyadan tashqarida) ──────────────
  async function notifyMembers(restaurantId, { title, body, bookingId }) {
    try {
      const ms = await db.collection(RESTAURANTS).doc(restaurantId).collection(MEMBERS).limit(10).get();
      await Promise.all(ms.docs.map((m) => notifyUserInApp({
        userId: m.id, title, body, category: 'order', source: 'restaurant_booking',
        extraNews: { bookingId: String(bookingId || ''), orderType: 'restaurant_booking' },
        dataType: 'restaurant_booking', screen: 'restaurant_orders', extraData: { bookingId, restaurantId },
      })));
    } catch (e) {
      console.error('booking notifyMembers:', e.message || e);
    }
  }

  async function notifyGuest(uid, { title, body, bookingId }) {
    try {
      await notifyUserInApp({
        userId: uid, title, body, category: 'order', source: 'restaurant_booking',
        extraNews: { bookingId: String(bookingId || ''), orderType: 'restaurant_booking' },
        dataType: 'restaurant_booking', screen: 'orders', extraData: { bookingId },
      });
    } catch (e) {
      console.error('booking notifyGuest:', e.message || e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MIJOZ: so'rov
  // ═══════════════════════════════════════════════════════════════════════
  /**
   * data: { restaurantId, guests, startAtMs, note?, idempotencyKey }
   * → { ok, bookingId, status: 'requested', feeAmount, duplicate? }
   * Pul harakati YO'Q (haq restoran qabul qilganda yechiladi).
   */
  exportsObj.placeRestaurantBooking = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    const d = data || {};
    const idempotencyKey = str(d.idempotencyKey, 80);
    if (!/^[A-Za-z0-9_-]{8,80}$/.test(idempotencyKey)) throw fail('invalid-argument', 'IDEMPOTENCY_KEY_INVALID');
    const restaurantId = str(d.restaurantId, 64);
    if (!restaurantId) throw fail('invalid-argument', 'RESTAURANT_ID_REQUIRED');
    const guests = d.guests;
    if (typeof guests !== 'number' || !Number.isInteger(guests) || guests < 1) throw fail('invalid-argument', 'GUESTS_INVALID');
    const startMs = d.startAtMs;
    if (typeof startMs !== 'number' || !Number.isInteger(startMs) || startMs <= 0) throw fail('invalid-argument', 'BOOKING_TIME_INVALID');
    const note = str(d.note, 200);

    const { cfg, version } = await loadConfig();
    requireStage(cfg, uid);
    const tier = tierFor(guests, cfg.tiers);
    if (!tier) throw fail('invalid-argument', 'GUESTS_INVALID', { maxGuests: cfg.tiers[cfg.tiers.length - 1].upTo });

    const bookingId = bookingIdFor(uid, idempotencyKey);
    const bookingRef = db.collection(BOOKINGS).doc(bookingId);
    const at = now();
    const nowMs = at.getTime();
    const windowErr = checkWindow(nowMs, startMs, cfg);
    // Takroriy chaqiruv (tarmoq uzilib qayta yuborilgan) vaqt o'tib ketgan bo'lsa ham o'sha bronni qaytaradi.
    const dup = await bookingRef.get();
    if (dup.exists) {
      const b = dup.data() || {};
      if (canonicalUid(String(b.userPhone || '')) !== uid) throw fail('permission-denied', 'NOT_BOOKING_OWNER');
      return { ok: true, bookingId, status: b.status, feeAmount: (b.fee || {}).amount || 0, duplicate: true };
    }
    if (windowErr) throw fail('failed-precondition', windowErr, { minLeadMin: cfg.minLeadMin, maxDays: cfg.maxDays });

    const user = await findUserRef(uid);
    if (!user) throw fail('failed-precondition', 'USER_NOT_FOUND');

    const rRef = db.collection(RESTAURANTS).doc(restaurantId);
    const startAt = new Date(startMs);

    const out = await db.runTransaction(async (t) => {
      // ── O'QISH fazasi ──
      const [existing, rSnap] = await Promise.all([t.get(bookingRef), t.get(rRef)]);
      if (existing.exists) {
        const b = existing.data() || {};
        return { duplicate: true, status: b.status, feeAmount: (b.fee || {}).amount || 0 };
      }
      if (!rSnap.exists) throw fail('not-found', 'RESTAURANT_NOT_FOUND');
      const r = rSnap.data() || {};
      if (r.status !== 'approved') throw fail('failed-precondition', 'RESTAURANT_NOT_APPROVED');
      if (canonicalUid(String(r.ownerUid || '')) === uid) throw fail('failed-precondition', 'OWN_RESTAURANT');
      if (r.acceptsBookings !== true) throw fail('failed-precondition', 'BOOKINGS_NOT_ACCEPTED');
      const seats = r.bookingSeats;
      if (!Number.isInteger(seats) || seats < 1) throw fail('failed-precondition', 'SEATS_NOT_CONFIGURED');
      if (guests > seats) throw fail('failed-precondition', 'NO_CAPACITY', { seats });
      if ((msOf(r.pausedUntil) || 0) > startMs) throw fail('failed-precondition', 'RESTAURANT_PAUSED');
      if (!isOpenAt(r.openingHours, startAt)) throw fail('failed-precondition', 'BOOKING_CLOSED_AT_TIME');

      const mine = await t.get(db.collection(BOOKINGS).where('userPhone', '==', uid).where('status', 'in', [BS.requested, BS.confirmed]).limit(50));
      const active = mine.docs.map((x) => ({ id: x.id, ...(x.data() || {}) })).filter((b) => (msOf(b.startAt) || 0) > nowMs);
      if (active.length >= cfg.maxActivePerGuest) throw fail('failed-precondition', 'TOO_MANY_ACTIVE_BOOKINGS', { max: cfg.maxActivePerGuest });
      if (active.some((b) => b.restaurantId === restaurantId && Math.abs((msOf(b.startAt) || 0) - startMs) < cfg.slotMin * MIN)) {
        throw fail('failed-precondition', 'DUPLICATE_BOOKING');
      }
      const confirmed = await confirmedAround(t, restaurantId, startMs, cfg.slotMin);
      if (seatsUsed(confirmed, startMs, cfg.slotMin) + guests > seats) throw fail('failed-precondition', 'NO_CAPACITY', { seats });

      // ── YOZISH fazasi ──
      const deadline = acceptDeadlineMs(nowMs, startMs, cfg);
      t.set(bookingRef, {
        restaurantId,
        restaurantName: str(r.name, 80),
        restaurantAddress: str(r.address, 200),
        userPhone: uid,
        userName: str(user.data.name || user.data.fullName || '', 60),
        guests,
        startAt: tsOf(startMs),
        note,
        bookingNote: str(r.bookingNote, 300),
        status: BS.requested,
        acceptDeadlineAt: tsOf(deadline),
        fee: { amount: tier.fee, upTo: tier.upTo, version, charged: false },
        tariffVersion: version,
        restaurantWalletUid: String(r.walletUserDocId || r.ownerUid || ''),
        idempotencyKey,
        createdAt: ts(),
        statusUpdatedAt: ts(),
        updatedAt: ts(),
      });
      addEvent(t, bookingRef, { from: null, to: BS.requested, actor: 'customer', actorId: uid, meta: { guests, startMs } });
      return { duplicate: false, status: BS.requested, feeAmount: tier.fee, restaurantName: str(r.name, 80) };
    }).catch((e) => {
      if (e instanceof HttpsError) throw e;
      log('place', { bookingId, restaurantId, result: 'contention', errorCode: 'ABORTED', message: String(e && e.message || e).slice(0, 120) });
      throw fail('aborted', 'CONTENTION_RETRY');
    });

    if (!out.duplicate) {
      log('place', { bookingId, restaurantId, result: 'ok', guests, durationMs: Date.now() - t0 });
      await notifyMembers(restaurantId, {
        title: '🍽 Yangi stol bron so\'rovi',
        body: `${guests} kishi · ${tashkentLabel(new Date(startMs))}`,
        bookingId,
      });
    }
    return { ok: true, bookingId, status: out.status, feeAmount: out.feeAmount, duplicate: !!out.duplicate };
  });

  // ═══════════════════════════════════════════════════════════════════════
  // RESTORAN: qabul (haq yechiladi), rad, bekor
  // ═══════════════════════════════════════════════════════════════════════
  async function prepareFeeInTx(t, bk, bookingId, charge) {
    const fee = bk.fee || {};
    if (!Number.isInteger(fee.amount) || fee.amount <= 0) return null;
    if (!charge && !fee.charged) return null;
    const walletUid = String(bk.restaurantWalletUid || '');
    if (!walletUid) throw fail('failed-precondition', 'RESTAURANT_WALLET_UNKNOWN');
    const version = Number.isInteger(fee.version) ? fee.version : 0;
    const key = `${charge ? 'bookingFee' : 'bookingFeeRefund'}_${bookingId}_v${version}`;
    const ctx = await settlementLedger.prepareBonusInTx(t, db, walletUid, { fundingAccount: EARNINGS_ACCOUNT, idempotencyKey: key });
    return { ctx, fee, walletUid, charge };
  }

  function commitFeeInTx(t, prep, { bookingId, actorId, postedRole }) {
    if (!prep) return { applied: false, amount: 0 };
    const { ctx, fee, walletUid, charge } = prep;
    if (ctx.jExists) return { applied: false, amount: fee.amount, idempotent: true };
    if (charge && ctx.pcPrev < fee.amount) {
      throw fail('failed-precondition', 'RESTAURANT_WALLET_INSUFFICIENT', { required: fee.amount, balance: ctx.pcPrev });
    }
    const delta = charge ? -fee.amount : fee.amount;
    const kind = charge ? 'restaurant_booking_fee' : 'restaurant_booking_fee_refund';
    settlementLedger.commitBonusInTx(t, ctx, {
      delta, kind, refType: 'restaurant_booking', refId: bookingId,
      meta: { module: MODULE_ID, upTo: fee.upTo, version: fee.version },
      postedBy: actorId || 'system', postedRole: postedRole || 'restaurant',
    });
    const userRef = db.collection('users').doc(walletUid);
    t.set(userRef, { bonusBalance: inc(delta), balanceUpdatedAt: ts() }, { merge: true });
    t.set(userRef.collection('wallet_ledger').doc(), {
      type: kind, amount: delta, module: MODULE_ID, refType: 'restaurant_booking', refId: bookingId,
      meta: { upTo: fee.upTo }, createdAt: ts(), createdBy: 'server',
    });
    return { applied: true, amount: fee.amount };
  }

  async function runWithRetry(fn, action, bookingId) {
    let lastErr = null;
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      try {
        return await fn();
      } catch (e) {
        if (e instanceof HttpsError) throw e;
        lastErr = e;
      }
    }
    log(action, { bookingId, result: 'contention', errorCode: 'ABORTED', message: String(lastErr && lastErr.message || lastErr).slice(0, 120) });
    throw fail('aborted', 'CONTENTION_RETRY');
  }

  /** data: { bookingId } → { ok, feeAmount, idempotent? }. Hamyonda yetmasa RESTAURANT_WALLET_INSUFFICIENT. */
  exportsObj.restaurantAcceptBooking = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    const bookingId = str(data && data.bookingId, 64);
    if (!bookingId) throw fail('invalid-argument', 'BOOKING_ID_REQUIRED');
    const { cfg } = await loadConfig();
    const slotMin = cfg ? cfg.slotMin : DEFAULTS.slotMin;
    const bookingRef = db.collection(BOOKINGS).doc(bookingId);
    const out = await runWithRetry(() => db.runTransaction(async (t) => {
      const snap = await t.get(bookingRef);
      if (!snap.exists) throw fail('not-found', 'BOOKING_NOT_FOUND');
      const bk = snap.data() || {};
      const { r } = await requireMemberInTx(t, String(bk.restaurantId || ''), uid);
      if (bk.status === BS.confirmed) return { ok: true, idempotent: true, feeAmount: (bk.fee || {}).amount || 0 };
      if (!canTransition(bk.status, BS.confirmed)) throw fail('failed-precondition', 'BOOKING_INVALID_TRANSITION', { from: bk.status, to: BS.confirmed });
      const nowMs = now().getTime();
      const startMs = msOf(bk.startAt) || 0;
      if (startMs <= nowMs || (msOf(bk.acceptDeadlineAt) || 0) < nowMs) throw fail('failed-precondition', 'BOOKING_EXPIRED');
      if (r.status !== 'approved') throw fail('failed-precondition', 'RESTAURANT_NOT_APPROVED');
      const seats = r.bookingSeats;
      if (!Number.isInteger(seats) || seats < 1) throw fail('failed-precondition', 'SEATS_NOT_CONFIGURED');
      const confirmed = await confirmedAround(t, bk.restaurantId, startMs, slotMin);
      if (seatsUsed(confirmed, startMs, slotMin, bookingId) + bk.guests > seats) throw fail('failed-precondition', 'NO_CAPACITY', { seats });
      const prep = await prepareFeeInTx(t, bk, bookingId, true);
      // YOZISH fazasi.
      const fee = commitFeeInTx(t, prep, { bookingId, actorId: uid, postedRole: 'restaurant' });
      t.update(bookingRef, {
        status: BS.confirmed, confirmedAt: ts(), confirmedBy: uid,
        'fee.charged': fee.applied || !!(prep && prep.ctx.jExists), 'fee.chargedAt': ts(),
        statusUpdatedAt: ts(), updatedAt: ts(),
      });
      addEvent(t, bookingRef, { from: bk.status, to: BS.confirmed, actor: 'restaurant', actorId: uid, meta: { feeAmount: fee.amount } });
      return { ok: true, feeAmount: fee.amount, guestUid: bk.userPhone, startMs, name: bk.restaurantName };
    }), 'accept', bookingId);
    log('accept', { bookingId, userId: uid, result: 'ok', feeAmount: out.feeAmount, idempotent: !!out.idempotent, durationMs: Date.now() - t0 });
    if (!out.idempotent && out.guestUid) {
      await notifyGuest(canonicalUid(out.guestUid), {
        title: '✅ Stol bron qilindi', body: `${out.name || 'Restoran'} · ${tashkentLabel(new Date(out.startMs))}`, bookingId,
      });
    }
    return { ok: true, feeAmount: out.feeAmount, idempotent: !!out.idempotent };
  });

  /** data: { bookingId, reason? } — faqat `requested`; hech narsa yechilmagan. */
  exportsObj.restaurantRejectBooking = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const bookingId = str(data && data.bookingId, 64);
    if (!bookingId) throw fail('invalid-argument', 'BOOKING_ID_REQUIRED');
    const reason = str(data && data.reason, 200) || 'Restoran rad etdi';
    const bookingRef = db.collection(BOOKINGS).doc(bookingId);
    const out = await runWithRetry(() => db.runTransaction(async (t) => {
      const snap = await t.get(bookingRef);
      if (!snap.exists) throw fail('not-found', 'BOOKING_NOT_FOUND');
      const bk = snap.data() || {};
      await requireMemberInTx(t, String(bk.restaurantId || ''), uid);
      if (bk.status === BS.rejected) return { ok: true, idempotent: true };
      if (!canTransition(bk.status, BS.rejected)) throw fail('failed-precondition', 'BOOKING_INVALID_TRANSITION', { from: bk.status, to: BS.rejected });
      t.update(bookingRef, { status: BS.rejected, rejectedAt: ts(), rejectedBy: uid, rejectReason: reason, statusUpdatedAt: ts(), updatedAt: ts() });
      addEvent(t, bookingRef, { from: bk.status, to: BS.rejected, actor: 'restaurant', actorId: uid, reason });
      return { ok: true, guestUid: bk.userPhone, name: bk.restaurantName };
    }), 'reject', bookingId);
    if (!out.idempotent) {
      log('reject', { bookingId, userId: uid, result: 'ok' });
      if (out.guestUid) await notifyGuest(canonicalUid(out.guestUid), { title: 'Bron rad etildi', body: reason, bookingId });
    }
    return { ok: true, idempotent: !!out.idempotent };
  });

  /**
   * Qabuldan keyin RESTORAN bekor qiladi: haq QAYTARILMAYDI (ega, 1-variant) va bekor qilish restoran hisobida
   * belgilanadi. So'nggi 30 kunda `cancelLimit30d` marta bo'lsa, restoran bron qabul qilishi avtomatik o'chadi
   * (`acceptsBookings=false`, sabab belgisi) — admin ko'radi (PROPOSED).
   */
  exportsObj.restaurantCancelBooking = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const bookingId = str(data && data.bookingId, 64);
    if (!bookingId) throw fail('invalid-argument', 'BOOKING_ID_REQUIRED');
    const reason = str(data && data.reason, 200) || 'Restoran bekor qildi';
    const { cfg } = await loadConfig();
    const limit = cfg ? cfg.cancelLimit30d : DEFAULTS.cancelLimit30d;
    const bookingRef = db.collection(BOOKINGS).doc(bookingId);
    const out = await runWithRetry(() => db.runTransaction(async (t) => {
      const snap = await t.get(bookingRef);
      if (!snap.exists) throw fail('not-found', 'BOOKING_NOT_FOUND');
      const bk = snap.data() || {};
      const { rRef, r } = await requireMemberInTx(t, String(bk.restaurantId || ''), uid);
      if (bk.status === BS.cancelledByRestaurant) return { ok: true, idempotent: true };
      if (!canTransition(bk.status, BS.cancelledByRestaurant)) throw fail('failed-precondition', 'BOOKING_INVALID_TRANSITION', { from: bk.status, to: BS.cancelledByRestaurant });
      const nowMs = now().getTime();
      const recent = (Array.isArray(r.bookingCancels) ? r.bookingCancels : [])
        .filter((x) => Number.isFinite(x) && nowMs - x < 30 * DAY).slice(-20);
      recent.push(nowMs);
      const disable = recent.length >= limit;
      t.update(bookingRef, { status: BS.cancelledByRestaurant, cancelledAt: ts(), cancelledBy: uid, cancelReason: reason, statusUpdatedAt: ts(), updatedAt: ts() });
      t.update(rRef, {
        bookingCancels: recent,
        ...(disable ? { acceptsBookings: false, bookingsDisabledReason: 'cancel_limit', bookingsDisabledAt: ts() } : {}),
        updatedAt: ts(),
      });
      addEvent(t, bookingRef, { from: bk.status, to: BS.cancelledByRestaurant, actor: 'restaurant', actorId: uid, reason, meta: { feeKept: !!(bk.fee && bk.fee.charged), disabled: disable } });
      return { ok: true, guestUid: bk.userPhone, name: bk.restaurantName, startMs: msOf(bk.startAt), disabled: disable, restaurantId: bk.restaurantId };
    }), 'restaurant_cancel', bookingId);
    if (!out.idempotent) {
      log('restaurant_cancel', { bookingId, restaurantId: out.restaurantId, userId: uid, result: 'ok', disabled: out.disabled });
      if (out.guestUid) {
        await notifyGuest(canonicalUid(out.guestUid), { title: 'Bron bekor qilindi', body: `${out.name || 'Restoran'} · ${tashkentLabel(new Date(out.startMs))}`, bookingId });
      }
    }
    return { ok: true, idempotent: !!out.idempotent, bookingsDisabled: !!out.disabled };
  });

  /** Mijoz bekor qiladi (so'rov yoki tasdiqlangan). Pul harakati YO'Q: yechilgan haq qaytarilmaydi (ega). */
  exportsObj.cancelRestaurantBooking = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const bookingId = str(data && data.bookingId, 64);
    if (!bookingId) throw fail('invalid-argument', 'BOOKING_ID_REQUIRED');
    const bookingRef = db.collection(BOOKINGS).doc(bookingId);
    const out = await runWithRetry(() => db.runTransaction(async (t) => {
      const snap = await t.get(bookingRef);
      if (!snap.exists) throw fail('not-found', 'BOOKING_NOT_FOUND');
      const bk = snap.data() || {};
      if (canonicalUid(String(bk.userPhone || '')) !== uid) throw fail('permission-denied', 'NOT_BOOKING_OWNER');
      if (bk.status === BS.cancelledByGuest) return { ok: true, idempotent: true };
      if (!canTransition(bk.status, BS.cancelledByGuest)) throw fail('failed-precondition', 'BOOKING_INVALID_TRANSITION', { from: bk.status, to: BS.cancelledByGuest });
      t.update(bookingRef, { status: BS.cancelledByGuest, cancelledAt: ts(), cancelledBy: uid, statusUpdatedAt: ts(), updatedAt: ts() });
      addEvent(t, bookingRef, { from: bk.status, to: BS.cancelledByGuest, actor: 'customer', actorId: uid, meta: { feeKept: !!(bk.fee && bk.fee.charged) } });
      return { ok: true, restaurantId: bk.restaurantId, startMs: msOf(bk.startAt), guests: bk.guests, wasConfirmed: bk.status === BS.confirmed };
    }), 'guest_cancel', bookingId);
    if (!out.idempotent) {
      log('guest_cancel', { bookingId, restaurantId: out.restaurantId, userId: uid, result: 'ok' });
      await notifyMembers(out.restaurantId, { title: 'Bron bekor qilindi', body: `${out.guests} kishi · ${tashkentLabel(new Date(out.startMs))}`, bookingId });
    }
    return { ok: true, idempotent: !!out.idempotent };
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ADMIN: force-majeure qaytarish, sozlama
  // ═══════════════════════════════════════════════════════════════════════
  /** data: { bookingId, reason } — yechilgan haqni qo'lda qaytaradi (bir marta; audit jurnali). */
  exportsObj.adminRefundBookingFee = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, ['admin', 'superadmin'], 'Admin role required');
    const bookingId = str(data && data.bookingId, 64);
    const reason = str(data && data.reason, 300);
    if (!bookingId) throw fail('invalid-argument', 'BOOKING_ID_REQUIRED');
    if (reason.length < 3) throw fail('invalid-argument', 'REASON_REQUIRED');
    const bookingRef = db.collection(BOOKINGS).doc(bookingId);
    const out = await runWithRetry(() => db.runTransaction(async (t) => {
      const snap = await t.get(bookingRef);
      if (!snap.exists) throw fail('not-found', 'BOOKING_NOT_FOUND');
      const bk = snap.data() || {};
      if (!(bk.fee && bk.fee.charged)) throw fail('failed-precondition', 'FEE_NOT_CHARGED');
      if (bk.fee.refunded) return { ok: true, idempotent: true, amount: bk.fee.amount };
      const prep = await prepareFeeInTx(t, bk, bookingId, false);
      const refund = commitFeeInTx(t, prep, { bookingId, actorId: actor, postedRole: 'admin' });
      t.update(bookingRef, { 'fee.refunded': true, 'fee.refundedAt': ts(), 'fee.refundReason': reason, updatedAt: ts() });
      addEvent(t, bookingRef, { from: bk.status, to: bk.status, actor: 'admin', actorId: actor, reason, meta: { refundAmount: refund.amount } });
      t.set(db.collection(ADMIN_AUDIT).doc(), { kind: 'restaurant_booking_fee_refund', actor, target: bookingId, reason, at: ts() });
      return { ok: true, amount: refund.amount };
    }), 'admin_refund', bookingId);
    log('admin_refund', { bookingId, userId: actor, result: 'ok', idempotent: !!out.idempotent });
    return out;
  });

  /**
   * Admin — cheklov tufayli avtomat o'chirilgan restoranni tiklaydi: bekor qilish tarixi va sabab belgisi tozalanadi
   * (restoran bron qabul qilishni o'zi qayta yoqadi — `acceptsBookings` ga tegilmaydi). Audit jurnali (41-qoida).
   * data: { restaurantId, reason } — takroriy chaqiruv zararsiz.
   */
  exportsObj.adminRestoreRestaurantBookings = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, ['admin', 'superadmin'], 'Admin role required');
    const restaurantId = str(data && data.restaurantId, 64);
    const reason = str(data && data.reason, 300);
    if (!restaurantId) throw fail('invalid-argument', 'RESTAURANT_ID_REQUIRED');
    if (reason.length < 3) throw fail('invalid-argument', 'REASON_REQUIRED');
    const rRef = db.collection(RESTAURANTS).doc(restaurantId);
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(rRef);
      if (!snap.exists) throw fail('not-found', 'RESTAURANT_NOT_FOUND');
      const r = snap.data() || {};
      const had = !!r.bookingsDisabledReason || (Array.isArray(r.bookingCancels) && r.bookingCancels.length > 0);
      if (!had) return { restored: false };
      t.update(rRef, {
        bookingCancels: [],
        bookingsDisabledReason: admin.firestore.FieldValue.delete(),
        bookingsDisabledAt: admin.firestore.FieldValue.delete(),
        updatedAt: ts(),
      });
      t.set(db.collection(ADMIN_AUDIT).doc(), { kind: 'restaurant_bookings_restore', actor, target: restaurantId, reason, at: ts() });
      return { restored: true };
    });
    log('restore', { restaurantId, userId: actor, result: 'ok', restored: out.restored });
    return { ok: true, ...out };
  });
  /**
   * Admin — bron sozlamasi (qisman: berilmagan qiymat saqlanadi). Har o'zgarish yangi `version`, o'zgarmas
   * tarix va audit; o'zgarish bo'lmasa versiya OSHMAYDI (idempotent). Hujjat yo'q = OFF.
   */
  exportsObj.adminSetRestaurantBookings = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, ['admin', 'superadmin'], 'Admin role required');
    const reason = str(data && data.reason, 300);
    const ref = db.collection(CONFIG_DOC[0]).doc(CONFIG_DOC[1]);
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const cur = snap.exists ? (snap.data() || {}) : {};
      const next = mergeConfig(data, cur, { fail, canonicalUid });
      const same = snap.exists && JSON.stringify(next) === JSON.stringify({
        stage: cur.stage, testerIds: cur.testerIds, tiers: cur.tiers, slotMin: cur.slotMin, minLeadMin: cur.minLeadMin,
        maxDays: cur.maxDays, acceptCapMin: cur.acceptCapMin, acceptBeforeMin: cur.acceptBeforeMin,
        cancelLimit30d: cur.cancelLimit30d, maxActivePerGuest: cur.maxActivePerGuest,
      });
      if (same) return { version: Number.isInteger(cur.version) ? cur.version : 0, changed: false };
      const version = (Number.isInteger(cur.version) ? cur.version : 0) + 1;
      const doc = { ...next, version, reason, updatedAt: ts(), updatedBy: actor };
      t.set(ref, doc);
      t.create(db.collection(HISTORY).doc(`v${version}`), {
        ...doc,
        previous: snap.exists ? { version: cur.version || 0, stage: cur.stage || 'off', tiers: cur.tiers || null } : null,
      });
      t.set(db.collection(ADMIN_AUDIT).doc(), { kind: 'restaurant_bookings_set', actor, target: `v${version}`, reason, at: ts() });
      return { version, changed: true };
    });
    log('config', { userId: actor, version: out.version, changed: out.changed, result: 'ok' });
    return { ok: true, ...out };
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Muddati o'tgan so'rovlar
  // ═══════════════════════════════════════════════════════════════════════
  /** Javob berilmagan va muddati o'tgan `requested` bronlarni yopadi; hech narsa yechilmagan. */
  async function expireRequested() {
    const at = now();
    const snap = await db.collection(BOOKINGS)
      .where('status', '==', BS.requested)
      .where('acceptDeadlineAt', '<=', tsOf(at.getTime()))
      .limit(200)
      .get();
    let expired = 0;
    for (const doc of snap.docs) {
      try {
        const r = await db.runTransaction(async (t) => {
          const s = await t.get(doc.ref);
          if (!s.exists) return null;
          const bk = s.data() || {};
          if (bk.status !== BS.requested || (msOf(bk.acceptDeadlineAt) || 0) > at.getTime()) return null;
          t.update(doc.ref, { status: BS.expired, expiredAt: ts(), statusUpdatedAt: ts(), updatedAt: ts() });
          addEvent(t, doc.ref, { from: BS.requested, to: BS.expired, actor: 'system', actorId: null, reason: 'accept_deadline' });
          return { guestUid: bk.userPhone, name: bk.restaurantName };
        });
        if (!r) continue;
        expired += 1;
        log('expire', { bookingId: doc.id, result: 'expired' });
        if (r.guestUid) await notifyGuest(canonicalUid(String(r.guestUid)), { title: 'Restoran javob bermadi', body: 'Bron qabul qilinmadi — boshqa vaqt yoki restoranni tanlang', bookingId: doc.id });
      } catch (e) {
        console.error('booking expire:', doc.id, e.message || e);
      }
    }
    return { scanned: snap.size, expired };
  }

  exportsObj.expireRestaurantBookings = functions.pubsub
    .schedule('every 5 minutes')
    .timeZone('Asia/Tashkent')
    .onRun(async () => expireRequested());

  return { expireRequested, loadConfig };
}

module.exports = {
  attachRestaurantBookings,
  BS, TRANSITIONS, canTransition,
  DEFAULTS, LIMITS, STAGES, CONFIG_DOC,
  sanitizeTiers, tierFor, bookingIdFor, checkWindow, acceptDeadlineMs, seatsUsed, mergeConfig,
};
