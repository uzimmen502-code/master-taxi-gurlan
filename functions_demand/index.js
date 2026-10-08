'use strict';

/**
 * AVA: ТАЛАБ → ТАКЛИФ ЯДРОСИ — codebase kirish nuqtasi.
 *
 * Deploy:  firebase deploy --only functions:demand
 *          ^ mavjud 226 funksiyaga TEGMAYDI. Bu codebase darajasidagi
 *            kill switch: muammo bo'lsa faqat shu to'plam qaytariladi.
 *
 * REGION: `europe-west1`.
 *   Firestore `eur3` (Yevropa) — 2026-10-03 auditida aniqlangan.
 *   Mavjud 226 funksiya `us-central1`da, ya'ni ular Firestore bilan
 *   boshqa qit'ada (har o'qishda ~100-150 ms qo'shimcha). Yangi yadro
 *   bu xatoni takrorlamaydi.
 *   Repoda naqsh allaqachon bor: `functions/index.js:5355`
 *   (`authFunctions = functions.region('europe-west1')`) va klient
 *   tomonda `lib/core/firebase_functions_client.dart`.
 *
 * TIL: oddiy JavaScript (CommonJS). Konsepsiya TypeScript degan edi,
 * lekin repoda TS qurilishi yo'q va `functions/index.js` 690 KB oddiy
 * JS. Ikkinchi til qo'shish deploy quvurini murakkablashtirardi.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

const REGION = 'europe-west1';
const fn = functions.region(REGION);

// ── Yadro modullari ──────────────────────────────────────────────────
const keywords = require('./core/keywords');
const taxonomy = require('./core/seed/taxonomy_services.json');
const { makeModeration } = require('./core/moderation');
const { makeCreateDemand } = require('./api/create_demand');
const offersApi = require('./api/offers');
const maintenance = require('./api/maintenance');
const capabilitiesApi = require('./api/capabilities');
const agreementsApi = require('./api/agreements');
const adminCapsApi = require('./api/admin_capabilities');
const logisticsApi = require('./api/logistics');
const wholesaleAdminApi = require('./api/wholesale_admin');
const { makeDispatchNotifications } = require('./notify/dispatch');
const trustEventsApi = require('./trust/events');
const { getModuleConfig } = require('./core/config');
const caps = require('./core/capabilities');
const { toCanonicalId } = require('./core/ids');
const { enabledModules } = require('./core/registry');

/**
 * Kalit so'z indeksi — sovuq startda BIR MARTA quriladi.
 *
 * 40 kategoriya x 655 sinonim ustida har chaqiruvda aylanish qimmat,
 * shuning uchun modul darajasida saqlanadi.
 *
 * DIQQAT: hozir urug' fayldan quriladi. `taxonomy` kolleksiyasi admin
 * panelda tahrirlangandan keyin haqiqat manbai Firestore bo'ladi
 * (13.6.1) — o'sha paytda shu yer o'zgaradi.
 */
const keywordIndex = keywords.buildIndex(taxonomy);

const moderation = makeModeration(db);
const dispatchNotifications = makeDispatchNotifications({ db, messaging, keywordIndex });
const afterAccept = offersApi.makeAfterAccept({ db, messaging });

/** Callable xatolarini Firebase HttpsError'ga aylantiradi. */
function wrapCallable(handler) {
  return async (data, context) => {
    try {
      return await handler(data, context);
    } catch (e) {
      const known = new Set([
        'unauthenticated', 'invalid-argument', 'permission-denied',
        'not-found', 'already-exists', 'failed-precondition',
        'resource-exhausted', 'unavailable', 'unimplemented',
      ]);
      if (known.has(e.code)) {
        // `details` (masalan `{reason: 'agreement_required'}`) klientga
        // yetib boradi — UI sabab bo'yicha matn tanlaydi (25-qoida).
        throw new functions.https.HttpsError(e.code, e.message, e.details);
      }
      // Kutilmagan xato: foydalanuvchiga tafsilot BERILMAYDI, logga tushadi.
      console.error(`kutilmagan xato: ${e.stack || e.message}`);
      throw new functions.https.HttpsError('internal', 'Ichki xato');
    }
  };
}

// ═══════════════════════════════════════════════════════════════════════
// CALLABLE'LAR
// ═══════════════════════════════════════════════════════════════════════

/** 13.2.2 — talab yaratish. */
exports.createDemand = fn.https.onCall(wrapCallable(
  makeCreateDemand({
    db, admin, keywordIndex, moderation,
    notify: dispatchNotifications,
  }),
));

/** 13.2.6 — taklif berish. */
exports.submitOffer = fn.https.onCall(wrapCallable(
  offersApi.makeSubmitOffer({ db }),
));

/** 13.2.6 — taklifni qaytarib olish. */
exports.withdrawOffer = fn.https.onCall(wrapCallable(
  offersApi.makeWithdrawOffer({ db }),
));

/** 13.2.7 — taklifni qabul qilish (birinchi g'olib). */
exports.acceptOffer = fn.https.onCall(wrapCallable(
  offersApi.makeAcceptOffer({ db, onAccepted: afterAccept }),
));

/** 13.2.8 — mijoz bekor qiladi. */
exports.cancelDemand = fn.https.onCall(wrapCallable(
  offersApi.makeCancelDemand({ db }),
));

/** 13.2.8 — ijrochi bekor qiladi, talab qayta ochiladi. */
exports.cancelAssignment = fn.https.onCall(wrapCallable(
  offersApi.makeCancelAssignment({ db }),
));

/** 13.2.10 — baho. */
exports.submitRating = fn.https.onCall(wrapCallable(
  maintenance.makeSubmitRating({ db }),
));

/**
 * D-12…D-16 — «men shu xizmatni ko'rsatmoqchiman».
 *
 * Natija: `status.<xizmat> = 'trial'` + 3 kunlik oyna. Odam O'ZIGA
 * faqat SINOV so'rashi mumkin; `approved` ni faqat admin beradi (D-14),
 * shuning uchun `status` ni klient qoidasi umuman yozolmaydi.
 */
exports.requestCapability = fn.https.onCall(wrapCallable(
  capabilitiesApi.makeRequestCapability({ db }),
));

/** D-SERVICE-2, D-TAXI-24 — xizmat kelishuvini qabul qilish (faqat joriy versiya). */
exports.acceptServiceAgreement = fn.https.onCall(wrapCallable(
  agreementsApi.makeAcceptServiceAgreement({ db }),
));

/**
 * ADMIN — capability statusi (D-TAXI-4: `verified` faqat admin) + audit
 * (41-qoida). O'tish `canTransition(..., 'admin')` bilan tekshiriladi.
 */
exports.adminSetCapabilityStatus = fn.https.onCall(wrapCallable(
  adminCapsApi.makeAdminSetCapabilityStatus({ db }),
));

/**
 * ADMIN — telefon bo'yicha xizmat qo'shish (kuryer: darhol `approved`,
 * ega qarori 2026-10-07). Faqat `not_registered` dan; har qadam audit.
 */
exports.adminGrantCapability = fn.https.onCall(wrapCallable(
  adminCapsApi.makeAdminGrantCapability({ db }),
));

/**
 * ADMIN — kuryer arizasini tasdiqlash rejimi (D-15.3): `manual` (sinov,
 * admin tasdiqlaydi; standart) | `auto` (ariza → darhol approved). Audit.
 */
exports.adminSetCourierApprovalMode = fn.https.onCall(wrapCallable(
  adminCapsApi.makeAdminSetCourierApprovalMode({ db }),
));

/**
 * ADMIN — T-6 migratsiyasi: `drivers.approved` → taxi `verified` +
 * 4 oylik billing grace. `dryRun` standart TRUE; `{dryRun:false}` yozadi.
 */
exports.adminMigrateTaxiDrivers = fn
  .runWith({ timeoutSeconds: 540 })
  .https.onCall(wrapCallable(adminCapsApi.makeAdminMigrateTaxiDrivers({ db })));

// ═══════════════════════════════════════════════════════════════════════
// AVA LOGISTICS (RELAY) — D-2…D-11 (docs/relay_delivery_architecture_uz.md)
// ═══════════════════════════════════════════════════════════════════════
//
// LEG = mavjud `demands` hujjati; ORDER/SHIPMENT/custody shu yerda. PUL
// (eskrou) — `functions/relay_escrow.js` (default codebase, ledger o'sha
// yerda); ikkisi `shipments.paymentStatus` orqali bog'lanadi.

const logisticsDeps = { db, keywordIndex, notify: dispatchNotifications };

/** Narx — pulsiz, faol tarif bo'yicha (D-8). */
exports.quoteLogisticsOrder = fn.https.onCall(wrapCallable(
  logisticsApi.makeQuoteLogisticsOrder({ db }),
));

/** ORDER + SHIPMENT'lar + sirlar + marshrut v1 + LEG(draft). To'lovsiz LEG ochilmaydi. */
exports.createLogisticsOrder = fn.https.onCall(wrapCallable(
  logisticsApi.makeCreateLogisticsOrder({ db }),
));

/** Ijrochi LEG'ni oladi — birinchi qabul g'olib (taklif yo'q, narx tarifdan). */
exports.acceptLeg = fn.https.onCall(wrapCallable(logisticsApi.makeAcceptLeg({ db })));

/** Custody: oldi (QR/kod + rasm) — bitta tranzaksiya (7.4). Keyingi LEG ochiladi. */
exports.scanHandover = fn.https.onCall(wrapCallable(logisticsApi.makeScanHandover(logisticsDeps)));

/** Oxirgi LEG → qabul qiluvchi (yetkazish kodi). */
exports.confirmDelivery = fn.https.onCall(wrapCallable(logisticsApi.makeConfirmDelivery({ db })));

/** Custody boshlanmagan bo'lsa — bekor; eskrou → refund_pending. */
exports.cancelLogisticsOrder = fn.https.onCall(wrapCallable(logisticsApi.makeCancelLogisticsOrder({ db })));

/** QR payload va kodlar — egasi (hammasi) / joriy custodian (yetkazish kodisiz). */
exports.getShipmentSecrets = fn.https.onCall(wrapCallable(logisticsApi.makeGetShipmentSecrets({ db })));

/** ADMIN — tarif qoralamasi; faol/eski versiya o'zgarmas (9-band). */
exports.adminUpsertLogisticsTariff = fn.https.onCall(wrapCallable(
  logisticsApi.makeAdminUpsertLogisticsTariff({ db }),
));

/** ADMIN — tarifni faol qilish: narxlar TO'LIQ bo'lishi shart. */
exports.adminActivateLogisticsTariff = fn.https.onCall(wrapCallable(
  logisticsApi.makeAdminActivateLogisticsTariff({ db }),
));

/** ADMIN — marshrutni qayta rejalash (D-9 versiyalar, D-10 bosqichlar). */
exports.adminPlanShipmentRoute = fn.https.onCall(wrapCallable(
  logisticsApi.makeAdminPlanShipmentRoute(logisticsDeps),
));

/** ADMIN — muddati tugagan LEG'ni qayta ochish (matching qaytadan, payout o'zgarmaydi). */
exports.adminReactivateLeg = fn.https.onCall(wrapCallable(
  logisticsApi.makeAdminReactivateLeg(logisticsDeps),
));

// ═══════════════════════════════════════════════════════════════════════
// ULGURJI / XITOY BOZORI — admin
// ═══════════════════════════════════════════════════════════════════════

/**
 * ADMIN — mahsulotni Ulgurji ↔ Xitoy bozoriga ko'chirish (2026-10-07).
 * Rules `market`ni hech kimga o'zgartirtirmaydi (ataylab); bu yerda admin
 * tekshiruvi, tranzaksiya, idempotentlik va `wholesale_market_audit`
 * (41-qoida). Valyutali narxni so'mli Ulgurjiga o'tkazish RAD etiladi.
 */
exports.adminSetWholesaleProductMarket = fn.https.onCall(wrapCallable(
  wholesaleAdminApi.makeAdminSetWholesaleProductMarket({
    db,
    deleteField: () => admin.firestore.FieldValue.delete(),
  }),
));

/**
 * Eskrou tushdi (default codebase yozadi) → LEG-1 ochiladi + matching.
 * Idempotent: faqat `pending → escrow_funded` o'tishida, LEG draft bo'lsa.
 */
exports.onShipmentFunded = fn.firestore
  .document('shipments/{shipmentId}')
  .onUpdate(async (change, context) => {
    const run = logisticsApi.makeOnShipmentFunded(logisticsDeps);
    try {
      await run(change.before.data() || {}, change.after.data() || {}, context.params.shipmentId);
    } catch (e) {
      console.error(`onShipmentFunded xatosi (${context.params.shipmentId}): ${e.message}`);
    }
    return null;
  });

// ═══════════════════════════════════════════════════════════════════════
// REJALI ISHLAR (Т-5: Cloud Tasks o'rniga sweeper)
// ═══════════════════════════════════════════════════════════════════════

/**
 * 13.2.9 — muddati o'tgan talablar.
 *
 * Har 5 daqiqada. Repoda ayni shu naqsh ishlab turibdi
 * (`expirePendingTrips`, `releaseStaleReservations`).
 */
exports.expireDemandsSweeper = fn.pubsub
  .schedule('every 5 minutes')
  .timeZone('Asia/Tashkent')
  .onRun(async () => {
    const run = maintenance.makeExpireSweeper({ db });
    return run();
  });

/** Т-19.1 — qabul qilindi, lekin ish boshlanmadi. */
exports.reopenStaleAssignments = fn.pubsub
  .schedule('every 10 minutes')
  .timeZone('Asia/Tashkent')
  .onRun(async () => {
    const run = maintenance.makeReopenStaleAssignments({ db });
    return run();
  });

/**
 * 13.6.3 — eskirgan `provider_presence` yozuvlari.
 *
 * Har 2 daqiqada: chegara `maxLocationAgeSec` (120 s), ya'ni sweep undan
 * tez-tez ishlashi kerak, aks holda yolg'on «onlayn» oynasi chegaradan
 * kattaroq bo'ladi. Eski `cleanupStaleDrivers` ham aynan shu qadamda
 * ishlaydi (`functions/index.js:9564`) — bir xil naqsh.
 */
exports.presenceSweeper = fn.pubsub
  .schedule('every 2 minutes')
  .timeZone('Asia/Tashkent')
  .onRun(async () => {
    const run = maintenance.makePresenceSweeper({ db });
    return run();
  });

/**
 * D-15.1 — SINOV MUDDATI.
 *
 *   trial         --3 kun-->  trial_expired (BIR MARTALIK 5 kun grace)
 *   trial_expired --5 kun-->  suspended
 *
 * Har SOATDA: muddat kunlar bilan o'lchanadi, ya'ni daqiqalik aniqlik
 * kerak emas va soatlik qadam 24x arzonroq. Eng yomon holatda odam
 * muddat tugagach 1 soat ko'proq ishlaydi — bu ataylab: chegara
 * «yumshoq» bo'lishi ega qarori (D-15.1).
 */
exports.capabilitySweeper = fn.pubsub
  .schedule('every 60 minutes')
  .timeZone('Asia/Tashkent')
  .onRun(async () => {
    // D-TAXI-24.1: starter tugaganda inbox xabari + push (kelishuv taqdimi).
    const run = capabilitiesApi.makeCapabilitySweeper({ db, messaging });
    return run();
  });

/**
 * 13.5.2 — SHADOW MODE ANALITIKASI (kunlik).
 *
 * Ega ro'yxatidagi 9 ko'rsatkich, modul x hudud kesimida.
 * KECHAGI kun hisoblanadi: bugungi kun hali tugamagan va uning hisobi
 * chala bo'lardi.
 *
 * 02:30 — kechasi, Asia/Tashkent. Tinch soat ichida, ya'ni hisob
 * foydalanuvchi faolligi bilan to'qnashmaydi.
 */
exports.aggregateDemandAnalytics = fn
  .runWith({ timeoutSeconds: 540, memory: '512MB' })
  .pubsub
  .schedule('30 2 * * *')
  .timeZone('Asia/Tashkent')
  .onRun(async () => {
    const { aggregateDay } = require('./analytics/aggregate');
    return aggregateDay({ db });
  });

/**
 * Qo'lda chaqirish — shadow mode kuzatuvi uchun.
 *
 * Kunlik ish 02:30 da ishlaydi, lekin shadow mode davomida natijani
 * KUN ICHIDA ko'rish kerak bo'ladi. `dryRun: true` bilan hech narsa
 * yozilmaydi — faqat hisob qaytariladi.
 */
exports.runDemandAnalytics = fn
  .runWith({ timeoutSeconds: 540, memory: '512MB' })
  .https.onCall(wrapCallable(async (data, context) => {
    const { assertAnalyticsAdmin } = require('./analytics/access');
    await assertAnalyticsAdmin(db, context);
    const { aggregateDay } = require('./analytics/aggregate');
    return aggregateDay({
      db,
      dateStr: data && data.date ? String(data.date) : undefined,
      dryRun: data ? data.dryRun === true : false,
    });
  }));

// ═══════════════════════════════════════════════════════════════════════
// TRIGGERLAR
// ═══════════════════════════════════════════════════════════════════════

/**
 * 13.2.11 — trust qayta hisoblash.
 *
 * `trust_events` o'zgarmas jurnal, shuning uchun faqat `onCreate`.
 */
exports.recomputeTrust = fn.firestore
  .document('trust_events/{eventId}')
  .onCreate(async (snap) => {
    const e = snap.data() || {};
    if (!e.subjectId) return null;
    try {
      // Konfig modul bo'yicha, lekin trust GLOBAL — shuning uchun
      // pilot modulining konfigi ishlatiladi (vaznlar bir xil).
      const config = await getModuleConfig(db, 'service', 'xorazm');
      await trustEventsApi.recompute(db, e.subjectId, config);
    } catch (err) {
      console.error(`recomputeTrust xatosi (${e.subjectId}): ${err.message}`);
    }
    return null;
  });

/**
 * 13.2.12 — teskari matching.
 *
 * Taklifchi imkoniyat qo'shganda unga mos AKTIV talablar qaytadan
 * hisoblanadi. Avval push olganlarga qayta push KETMAYDI
 * (`demand_push_log` idempotentligi).
 */
exports.onProviderAvailable = fn.firestore
  .document('provider_capabilities/{accountId}')
  .onWrite(async (change) => {
    const after = change.after.exists ? (change.after.data() || {}) : null;
    if (!after) return null;
    const before = change.before.exists ? (change.before.data() || {}) : null;

    /**
     * KIMLIK — server yozgan `identity.primaryUid` (18-qoida). Kalit
     * endi barqaror `accountId` (T-1a), matching esa kanon telefon bilan
     * ishlaydi; `identity` SERVER_KEYS ichida, klient unga tegolmaydi.
     */
    const providerId = toCanonicalId(caps.identityOf(after).primaryUid);
    if (!providerId) return null;

    /**
     * D-13: bitta hujjatda bir nechta capability. Shuning uchun QAYSI
     * xizmat o'zgarganini aniqlash kerak — aks holda `taxi` ni
     * yangilash `courier` matching'ini ham bekorga qayta ishga
     * tushirardi.
     *
     * Faqat adapteri BOR xizmatlar qaraladi: qolganlari uchun yadro
     * hali nomzod izlamaydi.
     */
    const run = maintenance.makeOnProviderAvailable({
      db, keywordIndex, notify: dispatchNotifications,
    });
    const live = new Set(enabledModules());

    for (const service of caps.SERVICES) {
      if (!live.has(service)) continue;
      // Huquq + xohish: ikkisi ham bo'lmasa teskari matching yo'q.
      if (!caps.isEligible(after, service)) continue;
      // Haqiqiy o'zgarish shart: `updatedAt` yangilanishi yetarli emas.
      if (before && !capabilityChangedFor(before, after, service)) continue;

      try {
        await run(providerId, service);
      } catch (e) {
        console.error(`onProviderAvailable xatosi (${providerId}/${service}): ${e.message}`);
      }
    }
    return null;
  });

/** Shu xizmat uchun MA'NOLI o'zgarish bo'ldimi. */
function capabilityChangedFor(before, after, service) {
  const b = before[service] || {};
  const a = after[service] || {};
  const list = (v) => JSON.stringify(Array.isArray(v) ? v : []);
  return b.active !== a.active
    || list(b.categoryIds) !== list(a.categoryIds)
    || list(b.categoryGroups) !== list(a.categoryGroups)
    || list(b.regionIds) !== list(a.regionIds)
    || list(b.districtIds) !== list(a.districtIds)
    // Status o'zgarishi ham ma'noli: `trial` -> `approved` bo'lgan odam
    // aktiv talablarni DARHOL ko'rishi kerak.
    || caps.statusOf(before, service) !== caps.statusOf(after, service);
}

// ═══════════════════════════════════════════════════════════════════════
// DIAGNOSTIKA
// ═══════════════════════════════════════════════════════════════════════

/**
 * Yadroning holati — shadow mode kuzatuvi va deploy tekshiruvi uchun.
 * Hech qanday maxfiy ma'lumot qaytarmaydi.
 */
exports.demandCoreStatus = fn.https.onCall(wrapCallable(async () => {
  // `enabledModules` modul boshida import qilingan (47-qator).
  return {
    region: REGION,
    modules: enabledModules(),
    taxonomyVersion: taxonomy.version,
    categoryCount: (taxonomy.categories || []).length,
    keywordCount: keywordIndex.byKeyword.size,
  };
}));
