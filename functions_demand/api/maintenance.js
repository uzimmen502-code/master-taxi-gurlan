'use strict';

/**
 * 13.2.9  — `expireDemandsSweeper` (scheduled)
 * 13.2.10 — `submitRating`
 * 13.2.12 — `onProviderAvailable` (teskari matching)
 * Т-19.1  — `reopenStaleAssignments` (qabul qilindi, lekin ish boshlanmadi)
 *
 * Nega sweeper, nega Cloud Task emas (Т-5): loyihada Cloud Tasks UMUMAN
 * ishlatilmaydi (API ham yoqilmagan). Muddat uchun soniyalik aniqlik
 * kerak emas — 5 daqiqalik sweeper yetarli, va repoda ayni shu naqsh
 * allaqachon ishlab turibdi (`expirePendingTrips`, `releaseStaleReservations`).
 *
 * Ilova rо'yxatlarda QO'SHIMCHA ravishda `expiresAt > now` filtrini ham
 * ishlatadi — shunda sweeper kechiksa ham eskirgan talab ko'rinmaydi.
 */

const { callerIdFrom, requireCanonicalId } = require('../core/ids');
const { resolveFlags, getModuleConfig } = require('../core/config');
const sm = require('../core/state_machine');
const trustEvents = require('../trust/events');
const { getAdapter } = require('../core/registry');
const { runMatching } = require('../matching/orchestrator');
const capabilities = require('../sources/capabilities');

const DEMANDS = 'demands';
const MATCHES = 'demand_matches';
const RATINGS = 'demand_ratings';

function fail(code, message) {
  const e = new Error(message);
  e.code = code;
  e.httpErrorCode = code;
  return e;
}

// ═══════════════════════════════════════════════════════════════════════
// 13.2.9 — MUDDAT
// ═══════════════════════════════════════════════════════════════════════

function makeExpireSweeper(deps) {
  const { db, now: nowFn, batchSize = 200 } = deps;

  return async function expireDemandsSweeper() {
    const now = nowFn ? nowFn() : new Date();

    const snap = await db.collection(DEMANDS)
      .where('status', '==', sm.STATUS.ACTIVE)
      .where('timeWindow.expiresAt', '<=', now)
      .limit(batchSize)
      .get();

    if (snap.empty) return { expired: 0 };

    const batch = db.batch();
    const ids = [];
    for (const d of snap.docs) {
      batch.update(d.ref, {
        status: sm.STATUS.EXPIRED,
        expiredAt: now,
        updatedAt: now,
      });
      ids.push(d.id);
    }
    await batch.commit();

    // Match yozuvlarini ham yopamiz — taklifchi inbox'ida eskirgan
    // talab ko'rinib qolmasligi uchun.
    for (const id of ids) {
      try {
        const ms = await db.collection(MATCHES).where('demandId', '==', id).get();
        if (ms.empty) continue;
        const b = db.batch();
        for (const m of ms.docs) {
          b.set(m.ref, { status: 'expired', closedAt: now }, { merge: true });
        }
        await b.commit();
      } catch (e) {
        console.error(`match yopilmadi (${id}): ${e.message}`);
      }
    }

    console.log(`expireDemandsSweeper: ${ids.length} ta talab expired`);
    return { expired: ids.length, ids };
  };
}

// ═══════════════════════════════════════════════════════════════════════
// Т-19.1 — QABUL QILINDI, LEKIN ISH BOSHLANMADI
// ═══════════════════════════════════════════════════════════════════════

/**
 * Konsepsiyada bu holat umuman YO'Q edi: ijrochi «Qabul qilish»ni bosib
 * yo'q bo'lib ketsa, talab abadiy `accepted` holatda qolardi va mijoz
 * hech narsa qila olmasdi.
 */
function makeReopenStaleAssignments(deps) {
  const { db, now: nowFn, batchSize = 100 } = deps;

  return async function reopenStaleAssignments() {
    const now = nowFn ? nowFn() : new Date();

    const snap = await db.collection(DEMANDS)
      .where('status', '==', sm.STATUS.ACCEPTED)
      .limit(batchSize)
      .get();

    let reopened = 0;
    for (const d of snap.docs) {
      const demand = d.data() || {};
      const a = demand.assignment || {};
      if (!a.acceptedAt || !a.providerId) continue;

      const regionId = (demand.location || {}).regionId;
      const config = await getModuleConfig(db, demand.module, regionId);
      const dl = sm.assignmentDeadline(a.acceptedAt, demand.mode, config, now);
      if (!dl.expired) continue;

      try {
        await d.ref.update({
          status: sm.STATUS.ACTIVE,
          assignment: { providerId: null, offerId: null, acceptedAt: null },
          reopenedAt: now,
          reopenReason: 'assignment_deadline',
          reopenCount: Number(demand.reopenCount || 0) + 1,
          updatedAt: now,
        });
        await trustEvents.record(db, {
          subjectId: a.providerId,
          type: trustEvents.EVENT.NO_SHOW,
          demandId: d.id,
          side: 'provider',
          note: 'assignment_deadline',
          at: now,
        });
        await db.collection(MATCHES).doc(`${d.id}_${a.providerId}`).set({
          status: 'deadline_missed', contactUnlocked: null, updatedAt: now,
        }, { merge: true });
        reopened += 1;
      } catch (e) {
        console.error(`qayta ochilmadi (${d.id}): ${e.message}`);
      }
    }

    if (reopened) console.log(`reopenStaleAssignments: ${reopened} ta talab qayta ochildi`);
    return { reopened };
  };
}

// ═══════════════════════════════════════════════════════════════════════
// 13.2.10 — BAHOLASH
// ═══════════════════════════════════════════════════════════════════════

/**
 * Konsepsiya: «Public rating'ni фақат мижоз қўяди. AVA уни ўзгартирмайди.»
 * va «Фақат completed статусидаги талаб бўйича».
 *
 * Shuning uchun server IKKI narsani tekshiradi:
 *   1) talab haqiqatan `completed`
 *   2) baho qo'yuvchi haqiqatan shu talabning egasi (yoki ijrochisi)
 */
function makeSubmitRating(deps) {
  const { db, now: nowFn } = deps;

  return async function submitRating(data, context) {
    const now = nowFn ? nowFn() : new Date();
    const raterId = callerIdFrom(context);
    if (!raterId) throw fail('unauthenticated', 'Telefon bilan kirish talab qilinadi');

    const demandId = String((data || {}).demandId || '');
    const stars = Number((data || {}).stars);
    const comment = String((data || {}).comment || '').slice(0, 500);

    if (!demandId) throw fail('invalid-argument', 'demandId majburiy');
    if (!Number.isInteger(stars) || stars < 1 || stars > 5) {
      throw fail('invalid-argument', 'Baho 1 dan 5 gacha bo\'lishi kerak');
    }

    const demandSnap = await db.collection(DEMANDS).doc(demandId).get();
    if (!demandSnap.exists) throw fail('not-found', 'So\'rov topilmadi');
    const demand = demandSnap.data() || {};

    if (!sm.canRate(demand.status)) {
      throw fail('failed-precondition', 'Baho faqat bajarilgan ish bo\'yicha qo\'yiladi');
    }

    const providerId = (demand.assignment || {}).providerId;
    if (!providerId) throw fail('failed-precondition', 'Bu so\'rovda ijrochi yo\'q');

    // Ikki tomon ham bir-birini baholaydi — kim kimni baholayotganini
    // aniqlaymiz.
    let subjectId;
    let side;
    if (demand.ownerId === raterId) { subjectId = providerId; side = 'provider'; }
    else if (providerId === raterId) { subjectId = demand.ownerId; side = 'buyer'; }
    else throw fail('permission-denied', 'Siz bu ishda qatnashmagansiz');

    // Bir talabga bitta baho — ID deterministik.
    const ratingId = `${demandId}_${raterId}`;
    const ratingRef = db.collection(RATINGS).doc(ratingId);
    const existing = await ratingRef.get();
    if (existing.exists) throw fail('already-exists', 'Siz allaqachon baho qo\'ygansiz');

    await ratingRef.set({
      demandId,
      raterId,
      subjectId,
      side,
      stars,
      comment,
      module: demand.module,
      createdAt: now,
    });

    await trustEvents.record(db, {
      subjectId,
      type: stars >= 5 ? trustEvents.EVENT.RATING_5
        : (stars <= 2 ? trustEvents.EVENT.RATING_LOW : trustEvents.EVENT.COMPLETED),
      demandId,
      side,
      at: now,
    });

    await recomputeAggregate(db, subjectId, now);
    return { ok: true, ratingId };
  };
}

/**
 * `provider_stats.rating` — o'rtacha baho.
 *
 * AVA bahoni O'ZGARTIRMAYDI, faqat o'rtachani hisoblaydi (konsepsiya
 * talabi). Hisob 200 oxirgi baho bo'yicha.
 */
async function recomputeAggregate(db, subjectId, now = new Date()) {
  const id = requireCanonicalId(subjectId, 'subjectId');
  const snap = await db.collection(RATINGS)
    .where('subjectId', '==', id)
    .limit(200)
    .get();

  let sum = 0;
  let n = 0;
  for (const d of snap.docs) {
    const s = Number((d.data() || {}).stars);
    if (Number.isInteger(s) && s >= 1 && s <= 5) { sum += s; n += 1; }
  }

  await db.collection('provider_stats').doc(id).set({
    providerId: id,
    rating: n > 0 ? Number((sum / n).toFixed(2)) : null,
    ratingCount: n,
    ratingUpdatedAt: now,
  }, { merge: true });

  return { rating: n > 0 ? sum / n : null, count: n };
}

// ═══════════════════════════════════════════════════════════════════════
// 13.2.12 — TESKARI MATCHING
// ═══════════════════════════════════════════════════════════════════════

/**
 * Konsepsiya: «Matching фақат талаб яратилганда ишласа, 10:30 да онлайн
 * бўлган курьер 10:00 даги талабни кўрмайди.»
 *
 * Shuning uchun taklifchi imkoniyat qo'shganda (yoki onlayn bo'lganda,
 * yoki yangi safar yaratganda) unga mos AKTIV talablar qaytadan
 * hisoblanadi.
 *
 * MUHIM: avval push olganlarga QAYTA push KETMAYDI — `demand_push_log`
 * idempotentligi buni o'zi ta'minlaydi.
 */
function makeOnProviderAvailable(deps) {
  const { db, keywordIndex, notify, now: nowFn, maxDemands = 50 } = deps;

  return async function onProviderAvailable(providerId, module) {
    const now = nowFn ? nowFn() : new Date();
    const id = requireCanonicalId(providerId, 'providerId');

    const cap = await capabilities.fetchForProvider(db, id, module);
    if (!cap || cap.active !== true) return { matched: 0, reason: 'no_capability' };

    const adapter = getAdapter(module);
    if (!adapter) return { matched: 0, reason: 'no_adapter' };

    const regions = Array.isArray(cap.regionIds) ? cap.regionIds : [];
    if (regions.length === 0) return { matched: 0, reason: 'no_region' };

    let matched = 0;
    for (const regionId of regions.slice(0, 5)) {
      const flags = await resolveFlags(db, module, regionId);
      if (!flags.enabled || !flags.matchingEnabled) continue;

      const snap = await db.collection(DEMANDS)
        .where('module', '==', module)
        .where('location.regionId', '==', regionId)
        .where('status', '==', sm.STATUS.ACTIVE)
        .where('timeWindow.expiresAt', '>', now)
        .limit(maxDemands)
        .get();

      for (const d of snap.docs) {
        const demand = { id: d.id, ...(d.data() || {}) };
        if (demand.ownerId === id) continue;

        // Allaqachon mos topilgan bo'lsa qayta hisoblamaymiz.
        const existing = await db.collection(MATCHES).doc(`${d.id}_${id}`).get();
        if (existing.exists) continue;

        // FAQAT shu taklifchini qaraymiz — butun matching'ni qaytadan
        // yugurtirish bekorga qimmat (va boshqalarga takroriy yozuv berardi).
        const soleCandidate = {
          providerId: id,
          source: 'capabilities',
          categoryIds: cap.categoryIds || [],
          categoryGroups: cap.categoryGroups || [],
          regionIds: cap.regionIds || [],
          districtIds: cap.districtIds || [],
          vehicle: cap.vehicle || null,
          consentGiven: true,
          raw: cap,
        };

        try {
          const res = await runMatching({
            db, demand, config: flags.config, adapter,
            sources: [async () => [soleCandidate]],
            keywordIndex,
          });
          if (res.matchedCount > 0) {
            matched += 1;
            if (notify && flags.pushEnabled) {
              await notify(db, demand, res, { flags, config: flags.config });
            }
          }
        } catch (e) {
          console.error(`teskari matching xatosi (${d.id}/${id}): ${e.message}`);
        }
      }
    }

    if (matched) console.log(`onProviderAvailable ${id}/${module}: ${matched} ta talab`);
    return { matched };
  };
}

module.exports = {
  makeExpireSweeper,
  makeReopenStaleAssignments,
  makeSubmitRating,
  makeOnProviderAvailable,
  recomputeAggregate,
};
