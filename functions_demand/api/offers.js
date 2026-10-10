'use strict';

/**
 * 13.2.6 — `submitOffer` / `withdrawOffer`
 * 13.2.7 — `acceptOffer`
 * 13.2.8 — `cancelDemand` / `cancelAssignment`
 *
 * Uchtasi bitta faylda, chunki hammasi AYNI BIR hujjat juftligini
 * (`demands` + `demands/{id}/offers`) tranzaksiya ichida o'zgartiradi va
 * bir xil qoidalarga tayanadi. Alohida fayllarga bo'lish tranzaksiya
 * mantiqini uch joyga tarqatib, nomuvofiqlik xavfini oshirardi.
 *
 * ASOSIY HIMOYALAR:
 *   - Bitta taklifchi = bitta taklif (ID = providerId), <=3 tahrir
 *   - Birinchi `acceptOffer` TRANZAKSIYA orqali g'olib
 *   - Kontakt FAQAT qabul qilingandan keyin ochiladi (Т-9, 1-pog'ona)
 *   - Status o'tishlari state machine'dan tashqariga chiqmaydi
 */

const { callerIdFrom, requireCanonicalId } = require('../core/ids');
const { resolveFlags } = require('../core/config');
const { validateOfferInput } = require('../core/schema');
const sm = require('../core/state_machine');
const trustEvents = require('../trust/events');
const { prepareLegCancelInTx } = require('./logistics');

const DEMANDS = 'demands';
const MATCHES = 'demand_matches';
const IDEMPOTENCY = 'demand_idempotency';

function fail(code, message, reason) {
  const e = new Error(message);
  e.code = code;
  e.httpErrorCode = code;
  // `details.reason` klientga yetadi (wrapCallable) — UI sabab bo'yicha matn tanlaydi.
  if (reason) e.details = { reason };
  return e;
}

/** Taklifchi shu talabni ko'rish huquqiga egami. */
async function assertIsMatched(db, demandId, providerId) {
  const snap = await db.collection(MATCHES).doc(`${demandId}_${providerId}`).get();
  if (!snap.exists) {
    // Mos emas -> talab mavjudligini ham oshkor qilmaymiz.
    throw fail('permission-denied', 'Bu so\'rov sizga mos emas');
  }
  return snap.data() || {};
}

// ═══════════════════════════════════════════════════════════════════════
// 13.2.6 — TAKLIF BERISH
// ═══════════════════════════════════════════════════════════════════════

function makeSubmitOffer(deps) {
  const { db, now: nowFn } = deps;

  return async function submitOffer(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const providerId = callerIdFrom(context);
    if (!providerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');

    const v = validateOfferInput(data);
    if (!v.valid) throw fail('invalid-argument', v.errors[0] || 'Yuklama noto\'g\'ri');
    const input = v.value;

    await assertIsMatched(db, input.demandId, providerId);

    const demandRef = db.collection(DEMANDS).doc(input.demandId);
    const offerRef = demandRef.collection('offers').doc(providerId);

    // Idempotentlik: ikki marta tap -> bitta taklif.
    const idemKey = `${providerId}_${input.clientRequestId}`;
    const idemRef = db.collection(IDEMPOTENCY).doc(idemKey);

    const result = await db.runTransaction(async (tx) => {
      const idem = await tx.get(idemRef);
      if (idem.exists) return { offerId: providerId, duplicate: true };

      const demandSnap = await tx.get(demandRef);
      if (!demandSnap.exists) throw fail('not-found', 'So\'rov topilmadi');
      const demand = demandSnap.data() || {};

      if (!sm.isOpenForOffers(demand.status)) {
        throw fail('failed-precondition', 'Bu so\'rov endi taklif qabul qilmaydi');
      }
      if (demand.ownerId === providerId) {
        throw fail('permission-denied', 'O\'z so\'rovingizga taklif berib bo\'lmaydi');
      }
      if (sm.isPastExpiry((demand.timeWindow || {}).expiresAt, now)) {
        throw fail('failed-precondition', 'So\'rov muddati tugagan', 'demand_expired');
      }

      const flags = await resolveFlags(db, demand.module, (demand.location || {}).regionId);
      const config = flags.config;

      const prev = await tx.get(offerRef);
      let revision = 0;
      if (prev.exists) {
        const p = prev.data() || {};
        if (p.status !== sm.OFFER_STATUS.ACTIVE) {
          throw fail('failed-precondition', 'Taklifingiz endi o\'zgartirilmaydi');
        }
        revision = Number(p.revision || 0) + 1;
        // Т-19.4: cheksiz tahrir narx o'yiniga va spamga olib keladi.
        if (revision > (config.maxOfferRevisions || 3)) {
          throw fail(
            'resource-exhausted',
            `Taklifni ${config.maxOfferRevisions} martadan ko'p o'zgartirib bo'lmaydi`,
          );
        }
      }

      tx.set(offerRef, {
        providerId,
        /** Т-2.2: qoidalar uchun denormalizatsiya — `get()` kerak bo'lmaydi. */
        ownerId: demand.ownerId,
        demandId: input.demandId,
        module: demand.module,
        price: input.price == null ? null : input.price,
        priceType: input.priceType || 'fixed',
        quantity: input.quantity == null ? null : input.quantity,
        message: String(input.message || '').slice(0, 500),
        etaMinutes: input.etaMinutes == null ? null : input.etaMinutes,
        delivery: input.delivery === true,
        media: (input.media || []).slice(0, 4),
        status: sm.OFFER_STATUS.ACTIVE,
        revision,
        createdAt: prev.exists ? (prev.data() || {}).createdAt : now,
        updatedAt: now,
      }, { merge: true });

      tx.set(idemRef, {
        ownerId: providerId, offerId: providerId, demandId: input.demandId, createdAt: now,
      });

      /**
       * 13.5.2 — АНАЛИТИКА HISOBLAGICHLARI.
       *
       * `offerCount` ва `firstOfferAt` талаб ҳужжатига ёзилади.
       *
       * Нега: кунлик агрегация `timeToFirstOffer`ни скандан ҳисоблаб
       * бўлмайди — ҳар талабнинг таклифлар субколлекциясини ўқиш
       * керак бўларди (200 талаб = 200 қўшимча сўров). Иккита майдон
       * эса нол қўшимча ўқиш.
       *
       * ДИҚҚАТ: `revision > 0` бўлса бу ЯНГИ таклиф эмас, таҳрир —
       * шунинг учун ҳисоб оширилмайди.
       */
      if (!prev.exists) {
        const patch = { offerCount: Number(demand.offerCount || 0) + 1 };
        if (!demand.firstOfferAt) patch.firstOfferAt = now;
        tx.update(demandRef, patch);
      }

      // Taklifchi ko'rganini belgilaymiz (takroriy push ketmasligi uchun).
      tx.set(
        db.collection(MATCHES).doc(`${input.demandId}_${providerId}`),
        { status: 'offered', offeredAt: now },
        { merge: true },
      );

      return { offerId: providerId, duplicate: false, revision };
    });

    return result;
  };
}

function makeWithdrawOffer(deps) {
  const { db, now: nowFn } = deps;

  return async function withdrawOffer(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const providerId = callerIdFrom(context);
    if (!providerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');

    const demandId = String((data || {}).demandId || '');
    if (!demandId) throw fail('invalid-argument', 'demandId majburiy');

    const offerRef = db.collection(DEMANDS).doc(demandId).collection('offers').doc(providerId);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(offerRef);
      if (!snap.exists) throw fail('not-found', 'Taklif topilmadi');
      const o = snap.data() || {};
      sm.assertOfferTransition(o.status, sm.OFFER_STATUS.WITHDRAWN, 'withdrawOffer');
      tx.update(offerRef, {
        status: sm.OFFER_STATUS.WITHDRAWN, updatedAt: now,
      });
    });

    return { ok: true };
  };
}

// ═══════════════════════════════════════════════════════════════════════
// 13.2.7 — TAKLIFNI QABUL QILISH
// ═══════════════════════════════════════════════════════════════════════

/**
 * Konsepsiya: «Транзакция: биринчи қабул ғолиб, бошқаларнинг push'и
 * янгиланади.»
 *
 * Tranzaksiya SHART: ikki parallel `acceptOffer` bo'lsa, ikkala
 * taklifchiga ham «siz tanlandingiz» ketib qolardi.
 */
function makeAcceptOffer(deps) {
  const { db, now: nowFn, onAccepted } = deps;

  return async function acceptOffer(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const ownerId = callerIdFrom(context);
    if (!ownerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');

    const demandId = String((data || {}).demandId || '');
    const providerId = requireCanonicalId((data || {}).providerId, 'providerId');
    if (!demandId) throw fail('invalid-argument', 'demandId majburiy');

    const demandRef = db.collection(DEMANDS).doc(demandId);
    const offerRef = demandRef.collection('offers').doc(providerId);

    const out = await db.runTransaction(async (tx) => {
      const demandSnap = await tx.get(demandRef);
      if (!demandSnap.exists) throw fail('not-found', 'So\'rov topilmadi');
      const demand = demandSnap.data() || {};

      if (demand.ownerId !== ownerId) {
        throw fail('permission-denied', 'Bu so\'rov sizga tegishli emas');
      }
      // Muddat o'tgan talabda taklif QABUL QILINMAYDI (ega qarori 2026-10-11).
      // SERVER vaqti, AYNI tranzaksiyada o'qilgan talab bo'yicha: sweeper
      // hali yopmagan bo'lsa ham. Avval bu tekshiruv yo'q edi va sweeper
      // poygasida talab ijrochi + ochiq kontakt bilan `expired` qolardi.
      if (demand.status === sm.STATUS.EXPIRED || sm.isPastExpiry((demand.timeWindow || {}).expiresAt, now)) {
        throw fail('failed-precondition', 'So\'rov muddati tugagan', 'demand_expired');
      }
      // Birinchi g'olib: ikkinchi chaqiruv shu yerda to'xtaydi.
      sm.assertTransition(demand.status, sm.STATUS.ACCEPTED, 'acceptOffer');

      const offerSnap = await tx.get(offerRef);
      if (!offerSnap.exists) throw fail('not-found', 'Taklif topilmadi');
      const offer = offerSnap.data() || {};
      sm.assertOfferTransition(offer.status, sm.OFFER_STATUS.ACCEPTED, 'acceptOffer');

      tx.update(demandRef, {
        status: sm.STATUS.ACCEPTED,
        assignment: { providerId, offerId: providerId, acceptedAt: now },
        updatedAt: now,
      });
      tx.update(offerRef, { status: sm.OFFER_STATUS.ACCEPTED, updatedAt: now });

      /**
       * Т-9 — KONTAKT OCHILISHINING 1-POG'ONASI.
       *
       * Konsepsiyada qabul qilingach IKKALA tomonning telefoni va aniq
       * manzil birga ochilardi. Bu «manzil yig'ish» hujumiga ochiq edi:
       * kuryer qabul qiladi, manzil va telefonlarni o'qiydi, kelmaydi.
       *
       * Shuning uchun hozir faqat YUBORUVCHI telefoni + OLISH manzili.
       * Qabul qiluvchi telefoni va yetkazish manzili `confirmPickup`
       * dan keyin ochiladi (2-pog'ona, P2).
       */
      tx.set(
        db.collection(MATCHES).doc(`${demandId}_${providerId}`),
        {
          status: 'accepted',
          acceptedAt: now,
          contactUnlocked: {
            stage: 1,
            ownerPhone: demand.ownerId,
            pickupAddress: (demand.location || {}).addressText || '',
            pickupLat: (demand.location || {}).lat || null,
            pickupLng: (demand.location || {}).lng || null,
          },
        },
        { merge: true },
      );

      return { demand, offer };
    });

    // Tranzaksiyadan TASHQARIDA: qolgan takliflarni rad etish va
    // push'larni yangilash. Ularni tranzaksiyaga qo'shish 500 hujjat
    // cheklovini buzishi va g'olibni kechiktirishi mumkin.
    if (onAccepted) {
      try {
        await onAccepted({ demandId, providerId, demand: out.demand, now });
      } catch (e) {
        console.error(`acceptOffer keyingi qadamlar xatosi (${demandId}): ${e.message}`);
      }
    }

    return { ok: true, demandId, providerId };
  };
}

/**
 * Qabul qilingandan keyingi tozalash: qolgan takliflar `rejected`,
 * ularning push'i «Buyurtma olindi» ga yangilanadi (collapse orqali).
 */
function makeAfterAccept(deps) {
  const { db, messaging } = deps;
  const fcm = require('../notify/fcm');

  return async function afterAccept({ demandId, providerId, demand, now }) {
    const offersSnap = await db.collection(DEMANDS).doc(demandId)
      .collection('offers').get();

    const batch = db.batch();
    const losers = [];
    for (const d of offersSnap.docs) {
      if (d.id === providerId) continue;
      const o = d.data() || {};
      if (o.status !== sm.OFFER_STATUS.ACTIVE) continue;
      batch.update(d.ref, { status: sm.OFFER_STATUS.REJECTED, updatedAt: now });
      losers.push(d.id);
    }

    // `demand_matches` — qolganlarga «olindi» belgisi.
    const matchesSnap = await db.collection(MATCHES)
      .where('demandId', '==', demandId).get();
    for (const d of matchesSnap.docs) {
      const m = d.data() || {};
      if (m.providerId === providerId) continue;
      batch.set(d.ref, { status: 'taken', takenAt: now }, { merge: true });
    }
    await batch.commit();

    // Push yangilash — faqat push OLGANLARGA (jurnal bo'yicha).
    if (messaging) {
      const msg = fcm.buildTakenMessage(demandId, demand.module);
      for (const loserId of losers) {
        const tokens = await fcm.tokensFor(db, loserId);
        if (tokens.length === 0) continue;
        try {
          await messaging.sendEach(tokens.map((token) => ({ ...msg, token })));
        } catch (e) {
          console.error(`«olindi» push xatosi (${loserId}): ${e.message}`);
        }
      }
    }

    return { rejected: losers.length };
  };
}

// ═══════════════════════════════════════════════════════════════════════
// 13.2.8 — BEKOR QILISH
// ═══════════════════════════════════════════════════════════════════════

/**
 * Mijoz talabni bekor qiladi.
 *
 * Konsepsiya: «Sabab so'ralmaydi, lekin qaysi paytda bekor qilingani
 * hisobga olinadi.» P0 da PUL JARIMA YO'Q (oferta matni hali yo'q,
 * Т-10/13.7.1) — faqat `trust_events`.
 */
function makeCancelDemand(deps) {
  const { db, now: nowFn } = deps;

  return async function cancelDemand(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const ownerId = callerIdFrom(context);
    if (!ownerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');

    const demandId = String((data || {}).demandId || '');
    if (!demandId) throw fail('invalid-argument', 'demandId majburiy');

    const demandRef = db.collection(DEMANDS).doc(demandId);

    const info = await db.runTransaction(async (tx) => {
      const snap = await tx.get(demandRef);
      if (!snap.exists) throw fail('not-found', 'So\'rov topilmadi');
      const demand = snap.data() || {};
      if (demand.ownerId !== ownerId) {
        throw fail('permission-denied', 'Bu so\'rov sizga tegishli emas');
      }
      sm.assertTransition(demand.status, sm.STATUS.CANCELLED, 'cancelDemand');

      tx.update(demandRef, {
        status: sm.STATUS.CANCELLED,
        cancelledBy: 'owner',
        cancelledAt: now,
        updatedAt: now,
      });
      return { demand, stage: demand.status };
    });

    // Haridor trust'i: ko'p talab berib hech birini qabul qilmaslik.
    if (info.stage === sm.STATUS.ACCEPTED) {
      await trustEvents.record(db, {
        subjectId: ownerId,
        type: trustEvents.EVENT.LATE_CANCEL,
        demandId,
        side: 'buyer',
        at: now,
      });
    }

    await markMatchesClosed(db, demandId, 'cancelled', now);
    return { ok: true };
  };
}

/**
 * Ijrochi bekor qiladi -> talab QAYTA OCHILADI.
 *
 * Т-19.2: rad etilgan takliflar `active`ga QAYTMAYDI (narxi eskirgan).
 * Talab faqat YANGI takliflarni kutadi.
 */
function makeCancelAssignment(deps) {
  const { db, now: nowFn, onReopened } = deps;

  return async function cancelAssignment(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const providerId = callerIdFrom(context);
    if (!providerId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');

    const demandId = String((data || {}).demandId || '');
    if (!demandId) throw fail('invalid-argument', 'demandId majburiy');

    const demandRef = db.collection(DEMANDS).doc(demandId);
    const offerRef = demandRef.collection('offers').doc(providerId);

    const info = await db.runTransaction(async (tx) => {
      const snap = await tx.get(demandRef);
      if (!snap.exists) throw fail('not-found', 'So\'rov topilmadi');
      const demand = snap.data() || {};
      const assigned = (demand.assignment || {}).providerId;
      if (assigned !== providerId) {
        throw fail('permission-denied', 'Bu buyurtma sizga tayinlanmagan');
      }

      const acceptedAt = (demand.assignment || {}).acceptedAt;
      const minutesSince = (now.getTime() - sm.toMillis(acceptedAt)) / 60000;

      sm.assertTransition(demand.status, sm.STATUS.ACTIVE, 'cancelAssignment');

      // Taklif YOZUVDAN OLDIN o'qiladi: haqiqiy SDK `tx.update`dan keyingi
      // `tx.get`ni rad etadi (?reads before writes?) ? avval shu tartib
      // teskari edi va har bir bekor qilish xato bilan tugardi.
      const offerSnap = await tx.get(offerRef);
      // Relay LEG: jo'natmadagi izlar ham shu tranzaksiyada (o'qish shu yerda).
      const commitLegCancel = await prepareLegCancelInTx(tx, db, demand, demandId, providerId);

      tx.update(demandRef, {
        status: sm.STATUS.ACTIVE,
        assignment: { providerId: null, offerId: null, acceptedAt: null },
        'matching.state': sm.MATCHING_STATE.DONE,
        reopenedAt: now,
        reopenCount: Number(demand.reopenCount || 0) + 1,
        updatedAt: now,
      });

      if (offerSnap.exists) {
        const o = offerSnap.data() || {};
        tx.update(offerRef, {
          status: sm.offerStatusOnReopen(o.status),
          updatedAt: now,
        });
      }
      commitLegCancel(now);

      return { demand, minutesSince };
    });

    /**
     * Konsepsiyadagi jadval: «Kuryer, qabul qilgandan keyin 2 daqiqa
     * ichida — jarima yo'q, lekin tez-tez bo'lsa trust pasayadi.»
     *
     * P0 da (service moduli) pul jarima yo'q, faqat trust.
     */
    await trustEvents.record(db, {
      subjectId: providerId,
      type: info.minutesSince <= 2
        ? trustEvents.EVENT.QUICK_CANCEL
        : trustEvents.EVENT.LATE_CANCEL,
      demandId,
      side: 'provider',
      at: now,
    });

    // Tayinlangan taklifchining match yozuvi yopiladi, kontakt YOPILADI.
    await db.collection(MATCHES).doc(`${demandId}_${providerId}`).set({
      status: 'cancelled_by_provider',
      contactUnlocked: null,
      updatedAt: now,
    }, { merge: true });

    if (onReopened) {
      try {
        await onReopened({ demandId, demand: info.demand, now });
      } catch (e) {
        console.error(`qayta ochish xatosi (${demandId}): ${e.message}`);
      }
    }

    return { ok: true, reopened: true };
  };
}

/** Barcha match yozuvlarini yopadi (talab tugaganda). */
async function markMatchesClosed(db, demandId, status, now) {
  const snap = await db.collection(MATCHES).where('demandId', '==', demandId).get();
  if (snap.empty) return 0;
  const batch = db.batch();
  for (const d of snap.docs) {
    batch.set(d.ref, { status, closedAt: now, contactUnlocked: null }, { merge: true });
  }
  await batch.commit();
  return snap.size;
}

module.exports = {
  makeSubmitOffer,
  makeWithdrawOffer,
  makeAcceptOffer,
  makeAfterAccept,
  makeCancelDemand,
  makeCancelAssignment,
  markMatchesClosed,
  assertIsMatched,
};
