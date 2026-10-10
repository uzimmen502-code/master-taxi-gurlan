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
const { resolveFlags, getModuleConfig, DEFAULTS } = require('../core/config');
const sm = require('../core/state_machine');
const trustEvents = require('../trust/events');
const { getAdapter } = require('../core/registry');
const caps = require('../core/capabilities');
const { runMatching } = require('../matching/orchestrator');
const capabilities = require('../sources/capabilities');
const L = require('../core/logistics');

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

/** `lastUpdateTime` sharti bajarilmadi (gRPC 9) yoki hujjat yo'q (5). */
function isPreconditionFailed(e) {
  return e && (e.code === 9 || e.code === 5 || e.code === 'failed-precondition' || e.code === 'not-found');
}

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

    // Har bir hujjat SHARTLI yopiladi: so'rovdan beri o'zgarmagan bo'lsa
    // (`lastUpdateTime`). 2026-10-10 gacha bitta shartsiz batch edi — so'rov
    // va yozuv orasida mijoz taklifni qabul qilsa / kuryer LEG'ni olsa,
    // qabul `expired` bilan bosib ketilardi (emulatorda isbotlangan).
    // O'zgargan hujjat o'tkazib yuboriladi: u endi `active` emas yoki
    // muddati yangilangan — keyingi aylanish qaror qiladi.
    const patch = { status: sm.STATUS.EXPIRED, expiredAt: now, updatedAt: now };
    const outcomes = await Promise.all(snap.docs.map(async (d) => {
      try {
        await (d.updateTime ? d.ref.update(patch, { lastUpdateTime: d.updateTime }) : d.ref.update(patch));
        return true;
      } catch (e) {
        if (!isPreconditionFailed(e)) console.error(`talab yopilmadi (${d.id}): ${e.message}`);
        return false;
      }
    }));

    const ids = [];
    const legProblems = [];
    snap.docs.forEach((d, i) => {
      if (!outcomes[i]) return;
      const data = d.data() || {};
      ids.push(d.id);
      // AVA Logistics LEG'i (relay): muddati tugagan LEG jo'natmani
      // «qotirib» qo'ymasin — jo'natmaga admin ko'radigan belgi
      // (`legProblem`), admin `adminReactivateLeg` bilan qayta ochadi.
      const shipmentId = String((data.attributes || {}).shipmentId || '');
      if (data.module === L.MODULE && shipmentId) legProblems.push({ legId: d.id, shipmentId });
    });
    const skipped = snap.size - ids.length;

    for (const p of legProblems) {
      try {
        await db.collection(L.SHIPMENTS).doc(p.shipmentId).update({
          legProblem: { legId: p.legId, kind: 'leg_expired', at: now },
          updatedAt: now,
        });
      } catch (e) {
        console.error(`legProblem yozilmadi (${p.shipmentId}/${p.legId}): ${e.message}`);
      }
    }

    // Match yozuvlarini ham yopamiz — taklifchi inbox'ida eskirgan
    // talab ko'rinib qolmasligi uchun. Tartib muhim: avval match'lar
    // o'qiladi, KEYIN talab hali `expired`mi tekshiriladi (admin shu orada
    // LEG'ni qayta ochgan bo'lsa — tegilmaydi), har match SHARTLI yopiladi
    // (qayta ochish o'chirgan/yangilagan match qayta «expired» bo'lmaydi).
    for (const id of ids) {
      try {
        const ms = await db.collection(MATCHES).where('demandId', '==', id).get();
        if (ms.empty) continue;
        const cur = await db.collection(DEMANDS).doc(id).get();
        if ((cur.data() || {}).status !== sm.STATUS.EXPIRED) continue;
        await Promise.all(ms.docs.map(async (m) => {
          const close = { status: 'expired', closedAt: now };
          try {
            await (m.updateTime ? m.ref.update(close, { lastUpdateTime: m.updateTime }) : m.ref.update(close));
          } catch (e) {
            if (!isPreconditionFailed(e)) throw e;
          }
        }));
      } catch (e) {
        console.error(`match yopilmadi (${id}): ${e.message}`);
      }
    }

    console.log(`expireDemandsSweeper: ${ids.length} ta talab expired${legProblems.length ? `, ${legProblems.length} ta logistika LEG'i` : ''}${skipped ? `, ${skipped} ta o'zgargan — o'tkazildi` : ''}`);
    return { expired: ids.length, ids, legProblems: legProblems.length, skipped };
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
      // AVA Logistics LEG'i (relay) — BU SWEEPER'DAN CHIQARILGAN (ega qarori
      // 2026-10-07): LEG'ning o'z hayot sikli bor (custody kodi bilan
      // boshlanadi, egasi bekor qiladi, admin qayta rejalaydi/ochadi).
      // Umumiy 120 daqiqalik «qabul qildi, lekin boshlamadi» muddati bu
      // yerda noto'g'ri: LEG-2 kuryeri LEG-1 posilkani olib kelguncha
      // soatlab kutadi — uni chiqarib tashlash + NO_SHOW jazosi xato.
      if (demand.module === L.MODULE) continue;
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
// 13.6.3 — PRESENCE GIGIYENASI
// ═══════════════════════════════════════════════════════════════════════

/**
 * Eskirgan `provider_presence` yozuvlarini offline qiladi.
 *
 * Nega kerak: kuryer ilovani yopsa, tarmoq uzilsa yoki telefon o'chsa,
 * `isOnline: true` hujjatda QOLIB KETADI. Matching buni allaqachon
 * hisobga oladi (`sources/presence_geo.js` `maxLocationAgeSec`dan eski
 * yozuvni chiqarib tashlaydi), lekin hujjatning O'ZI yolg'on holatda
 * turaveradi — admin panelida «onlayn» bo'lib ko'rinadi va har qanday
 * yangi o'quvchi shu yolg'onni meros qilib oladi.
 *
 * ── Ikkita shartnoma qarori ─────────────────────────────────────────────
 *
 * 1. CHEGARA matching bilan BIR XIL (`maxLocationAgeSec`). Ikki xil raqam
 *    bo'lsa, «matching ko'rmayapti, lekin admin onlayn deb turibdi»
 *    oralig'i paydo bo'ladi. Bitta raqam — bitta ma'no.
 *
 * 2. `updatedAt` GA TEGILMAYDI. U faqat «qurilmadan kelgan oxirgi
 *    heartbeat» degani; sweep uni yangilasa, yozuv «yangi» bo'lib
 *    ko'rinardi va eskilik mezoni o'z-o'zini yo'q qilardi. Offline
 *    vaqti alohida `offlineAt` ga yoziladi.
 *
 * ── Shundan kelib chiqadigan KLIENT SHARTNOMASI ────────────────────────
 * Har bir heartbeat `isOnline: true` ni ham yozishi SHART. Aks holda
 * sweep bir marta offline qilgandan keyin kuryer hech qachon qaytib
 * onlayn bo'lmaydi (3-qadam shu shartnomaga ko'ra yoziladi).
 */
function makePresenceSweeper(deps) {
  const { db, now: nowFn, batchSize = 200, collection = 'provider_presence' } = deps;

  return async function presenceSweeper() {
    const now = nowFn ? nowFn() : new Date();
    // Presence eskirishi MODULGA bog'liq emas — bu yadro konstantasi.
    // `getModuleConfig(db, null, null)` soxta kalit yasab, keraksiz
    // Firestore o'qishi qilardi va keshni iflos qilardi.
    const maxAgeSec = Number(deps.maxLocationAgeSec || DEFAULTS.maxLocationAgeSec) || 120;
    const cutoffMs = now.getTime() - maxAgeSec * 1000;

    const snap = await db.collection(collection)
      .where('isOnline', '==', true)
      .limit(batchSize)
      .get();

    let offlined = 0;
    for (const d of snap.docs) {
      const p = d.data() || {};
      const ms = sm.toMillis(p.updatedAt);
      // `updatedAt` umuman yo'q bo'lsa — yozuv noto'g'ri shaklda, uni ham
      // offline qilamiz: aks holda u abadiy «onlayn» bo'lib qoladi.
      if (ms && ms >= cutoffMs) continue;

      try {
        await d.ref.update({
          isOnline: false,
          offlineAt: now,
          offlineReason: 'stale_heartbeat',
        });
        offlined += 1;
      } catch (e) {
        console.error(`presence offline qilinmadi (${d.id}): ${e.message}`);
      }
    }

    if (offlined) console.log(`presenceSweeper: ${offlined} ta yozuv offline qilindi`);
    return { offlined };
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

    /**
     * D-12…D-16: hujjat shakli o'zgardi — bitta uid, xizmatlar ichida.
     * `isEligible` IKKI shartni ham ko'radi: `status` (HUQUQ) va
     * `active` (XOHISH). Avval faqat `active` tekshirilardi, ya'ni
     * ruxsati bo'lmagan odam ham teskari matching olardi.
     */
    const capDoc = await capabilities.fetchForProvider(db, id);
    if (!capDoc || !caps.isEligible(capDoc, module)) {
      return { matched: 0, reason: 'no_capability' };
    }
    const cap = capDoc[module] || {};

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
  makePresenceSweeper,
  makeSubmitRating,
  makeOnProviderAvailable,
  recomputeAggregate,
};
