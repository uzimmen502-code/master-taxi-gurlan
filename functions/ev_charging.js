'use strict';

/**
 * ⚡ EV zaryadlash nuqtalari — jamoa xaritasi (`ev_charging_stations`).
 *
 * Server-side fan-out counterlar:
 *   - confirmations/{userId} yozilganda — parent stansiyaga confirmationCount
 *     +1/-1 va lastConfirmedAt (create/delete asosida, update — no-op, chunki
 *     idempotent, docId = userId).
 *   - reports/{reportId} yaratilganda — parent stansiyaga reportCount +1 va
 *     reportLimits/{userId} counter +1.
 * `maxReportsPerUserPerStation` limiti bu yerda emas — firestore.rules'da
 * `evReportLimitOk()` orqali (report yaratilishidan OLDIN, `config/ev_charging`
 * hujjatidan) tekshiriladi; bu fayl faqat limitni oshirib boradi.
 *
 * Admin moderatsiya — `admin_jobs_service.dart`/`assertAdmin()` bilan bir xil
 * naqsh: mutatsiyalar callable orqali (Admin SDK, rules'ni chetlab o'tadi),
 * `admin_web` bevosita Firestore'ga yozmaydi.
 *
 * Deploy birligi o'zgarmagan — index.js require qiladi (yuk_local.js pattern).
 */
const { onDocumentWritten, onDocumentCreated } = require('firebase-functions/v2/firestore');

const EV_STATUS_VALUES = new Set(['working', 'partially_working', 'not_working', 'unknown']);

function attachEvCharging(exportsObj, deps) {
  const { db, admin, functions, assertAdmin } = deps;

  exportsObj.onEvConfirmationWrite = onDocumentWritten(
    {
      document: 'ev_charging_stations/{stationId}/confirmations/{userId}',
      region: 'europe-west1',
    },
    async (event) => {
      const stationId = event.params.stationId;
      const before = event.data && event.data.before;
      const after = event.data && event.data.after;
      const wasActive = !!(before && before.exists);
      const isActive = !!(after && after.exists);
      if (wasActive === isActive) return;

      const update = {
        confirmationCount: admin.firestore.FieldValue.increment(isActive ? 1 : -1),
      };
      if (isActive) {
        update.lastConfirmedAt = admin.firestore.FieldValue.serverTimestamp();
      }
      await db.collection('ev_charging_stations').doc(stationId)
        .update(update)
        .catch((e) => console.error(`onEvConfirmationWrite(${stationId}):`, e));
    },
  );

  exportsObj.onEvReportCreate = onDocumentCreated(
    {
      document: 'ev_charging_stations/{stationId}/reports/{reportId}',
      region: 'europe-west1',
    },
    async (event) => {
      const stationId = event.params.stationId;
      const snap = event.data;
      const reporterId = snap ? (snap.data() || {}).reporterId : null;
      if (!reporterId) return;

      const stationRef = db.collection('ev_charging_stations').doc(stationId);
      const limitRef = stationRef.collection('reportLimits').doc(reporterId);

      await db.runTransaction(async (tx) => {
        const limitSnap = await tx.get(limitRef);
        const nextCount = (limitSnap.exists ? Number(limitSnap.data().count) || 0 : 0) + 1;
        tx.set(limitRef, {
          count: nextCount,
          lastReportAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        tx.update(stationRef, {
          reportCount: admin.firestore.FieldValue.increment(1),
        });
      }).catch((e) => console.error(`onEvReportCreate(${stationId}):`, e));
    },
  );

  /** Admin web: report'ni "ko'rib chiqildi" deb belgilash (6-band). */
  exportsObj.adminResolveEvReport = functions.https.onCall(async (data, context) => {
    const adminDocId = await assertAdmin(String(data.adminPhone || ''), context);
    const stationId = String(data.stationId || '').trim();
    const reportId = String(data.reportId || '').trim();
    if (!stationId || !reportId) {
      throw new functions.https.HttpsError('invalid-argument', 'stationId/reportId required');
    }
    await db
      .collection('ev_charging_stations').doc(stationId)
      .collection('reports').doc(reportId)
      .update({
        resolved: true,
        resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
        resolvedBy: adminDocId,
      });
    return { ok: true, stationId, reportId };
  });

  /** Admin web: stansiya holatini o'zgartirish (`working`|...|`unknown`, 6-band). */
  exportsObj.adminUpdateEvStationStatus = functions.https.onCall(async (data, context) => {
    await assertAdmin(String(data.adminPhone || ''), context);
    const stationId = String(data.stationId || '').trim();
    const status = String(data.status || '').trim();
    if (!stationId) {
      throw new functions.https.HttpsError('invalid-argument', 'stationId required');
    }
    if (!EV_STATUS_VALUES.has(status)) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid status');
    }
    await db.collection('ev_charging_stations').doc(stationId).update({
      status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { ok: true, stationId, status };
  });

  /** Admin web: xaritadan yashirish/qaytarish (6-band, `isActive=false`). */
  exportsObj.adminSetEvStationActive = functions.https.onCall(async (data, context) => {
    await assertAdmin(String(data.adminPhone || ''), context);
    const stationId = String(data.stationId || '').trim();
    if (!stationId) {
      throw new functions.https.HttpsError('invalid-argument', 'stationId required');
    }
    await db.collection('ev_charging_stations').doc(stationId).update({
      isActive: data.isActive !== false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { ok: true, stationId };
  });
}

module.exports = { attachEvCharging };
