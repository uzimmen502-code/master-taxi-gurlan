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
const { makeDispatchNotifications } = require('./notify/dispatch');
const trustEventsApi = require('./trust/events');
const { getModuleConfig } = require('./core/config');

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
        throw new functions.https.HttpsError(e.code, e.message);
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
  .document('provider_capabilities/{key}')
  .onWrite(async (change) => {
    const after = change.after.exists ? (change.after.data() || {}) : null;
    if (!after || after.active !== true) return null;

    const before = change.before.exists ? (change.before.data() || {}) : null;
    // Faqat haqiqiy o'zgarishda: `updatedAt` yangilanishi yetarli emas.
    if (before) {
      const same = JSON.stringify(before.categoryIds || []) === JSON.stringify(after.categoryIds || [])
        && JSON.stringify(before.regionIds || []) === JSON.stringify(after.regionIds || [])
        && before.active === after.active;
      if (same) return null;
    }

    const run = maintenance.makeOnProviderAvailable({
      db, keywordIndex, notify: dispatchNotifications,
    });
    try {
      await run(after.providerId, after.module);
    } catch (e) {
      console.error(`onProviderAvailable xatosi: ${e.message}`);
    }
    return null;
  });

// ═══════════════════════════════════════════════════════════════════════
// DIAGNOSTIKA
// ═══════════════════════════════════════════════════════════════════════

/**
 * Yadroning holati — shadow mode kuzatuvi va deploy tekshiruvi uchun.
 * Hech qanday maxfiy ma'lumot qaytarmaydi.
 */
exports.demandCoreStatus = fn.https.onCall(wrapCallable(async () => {
  const { enabledModules } = require('./core/registry');
  return {
    region: REGION,
    modules: enabledModules(),
    taxonomyVersion: taxonomy.version,
    categoryCount: (taxonomy.categories || []).length,
    keywordCount: keywordIndex.byKeyword.size,
  };
}));
