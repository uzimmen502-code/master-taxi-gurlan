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
 * Янги станция қўшиш — ПУЛЛИК (эга қарори, 2026-09-22): `payAndCreateEvStation`
 * callable'и орқали (AVA ҳамёнидан, идемпотент, settlement ledger кўзгуси —
 * `assistant_chat.js`даги `assistantBuyPackage` билан бир хил нақш). Клиент
 * энди тўғридан-тўғри `ev_charging_stations`га ЯНГИ ҳужжат ёза олмайди
 * (`firestore.rules`: `create` фақат admin/Admin SDK) — фақат МАВЖУД
 * ҳужжатнинг ихтиёрий майдонларини таҳрирлай олади (`evStationCommunityPatch`,
 * бепул, ўзгармади).
 *
 * Deploy birligi o'zgarmagan — index.js require qiladi (yuk_local.js pattern).
 */
const { onDocumentWritten, onDocumentCreated } = require('firebase-functions/v2/firestore');
const geoHash = require('./geo_hash');

const EV_STATUS_VALUES = new Set(['working', 'partially_working', 'not_working', 'unknown']);

// Станция қўшиш тарифлари (битта станция учун, бир марталик тўлов —
// эга қарори 2026-09-22). `settings/ev_charging_tariffs` орқали релизсиз
// ўзгартирилади (майдонлар: {price, months}).
const EV_STATION_TARIFFS_DEFAULT = {
  m6: { months: 6, price: 350000 },
  y12: { months: 12, price: 500000 },
};
const DAY_MS = 24 * 60 * 60 * 1000;

function attachEvCharging(exportsObj, deps) {
  const {
    db, admin, functions, assertAdmin,
    callerPhone, canonicalUid, settlementLedger,
  } = deps;

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

  function requireEvUid(context) {
    if (!context || !context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Login required');
    }
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length < 9) {
      throw new functions.https.HttpsError('permission-denied', 'Phone required');
    }
    return uid;
  }

  async function loadStationTariffs() {
    try {
      const snap = await db.collection('config').doc('ev_charging').get();
      const raw = snap.exists ? (snap.data() || {}).stationTariffs : null;
      if (!raw || typeof raw !== 'object') return EV_STATION_TARIFFS_DEFAULT;
      const out = {};
      for (const [id, v] of Object.entries(raw)) {
        const months = parseInt(String((v || {}).months), 10);
        const price = parseInt(String((v || {}).price), 10);
        if (Number.isFinite(months) && months > 0 && Number.isFinite(price) && price > 0) {
          out[id] = { months, price };
        }
      }
      return Object.keys(out).length ? out : EV_STATION_TARIFFS_DEFAULT;
    } catch (e) {
      console.error('ev_charging: config/ev_charging read failed', e);
      return EV_STATION_TARIFFS_DEFAULT;
    }
  }

  /** Клиент учун: жорий тарифлар (варақада кўрсатиш учун). */
  exportsObj.getEvStationTariffs = functions.https.onCall(async () => {
    return { tariffs: await loadStationTariffs() };
  });

  /**
   * ЯНГИ станция қўшиш — ПУЛЛИК (эга қарори, 2026-09-22): AVA ҳамёнидан
   * (`bonusBalance`) бир марталик тўлов, идемпотент, settlement ledger
   * кўзгуси билан бирга (`assistantBuyPackage` нақши). Муваффақиятли
   * бўлса — станция шу заҳоти `isActive:true` билан яратилади (эга
   * қарори: admin тасдиғи шарт эмас).
   */
  exportsObj.payAndCreateEvStation = functions.https.onCall(async (data, context) => {
    const uid = requireEvUid(context);
    const idempotencyKey = String((data && data.idempotencyKey) || '').trim();
    if (!idempotencyKey) {
      throw new functions.https.HttpsError('invalid-argument', 'idempotencyKey required');
    }
    const tariffId = String((data && data.tariff) || '').trim();
    const tariffs = await loadStationTariffs();
    const tariff = tariffs[tariffId];
    if (!tariff) {
      throw new functions.https.HttpsError('invalid-argument', 'unknown_tariff');
    }

    const lat = Number(data && data.lat);
    const lng = Number(data && data.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      throw new functions.https.HttpsError('invalid-argument', 'lat/lng required');
    }
    const chargingTypes = Array.isArray(data.chargingTypes)
      ? data.chargingTypes.filter((x) => typeof x === 'string')
      : [];
    const connectors = Array.isArray(data.connectors)
      ? data.connectors.filter((x) => typeof x === 'string')
      : [];
    const powerKw = typeof data.powerKw === 'number' && Number.isFinite(data.powerKw)
      ? data.powerKw : null;
    const price = typeof data.price === 'number' && Number.isFinite(data.price)
      ? data.price : null;
    const operatorName = String((data && data.operatorName) || '').trim() || null;
    const note = String((data && data.note) || '').trim() || null;

    const idemKey = `ev_paid_station_${uid}_${idempotencyKey}`;
    const idemRef = db.collection('wallet_idempotency').doc(idemKey);
    const existing = await idemRef.get();
    if (existing.exists) {
      return existing.data().result || { ok: true, duplicate: true };
    }

    const FieldValue = admin.firestore.FieldValue;
    const Timestamp = admin.firestore.Timestamp;
    const userRef = db.collection('users').doc(uid);
    const stationRef = db.collection('ev_charging_stations').doc();
    const ledgerRef = userRef.collection('wallet_ledger').doc();

    const result = await db.runTransaction(async (t) => {
      const idemSnap = await t.get(idemRef);
      if (idemSnap.exists) {
        return idemSnap.data().result || { ok: true, duplicate: true };
      }
      const userSnap = await t.get(userRef);
      if (!userSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'user not found');
      }
      const ud = userSnap.data() || {};
      const prev = parseInt(String(ud.bonusBalance ?? 0), 10) || 0;
      if (prev < tariff.price) {
        throw new functions.https.HttpsError('failed-precondition', 'insufficient_balance', {
          reason: 'insufficient_balance',
          balance: prev,
          price: tariff.price,
        });
      }
      const nowMs = Date.now();
      const paidUntil = Timestamp.fromMillis(nowMs + tariff.months * 30 * DAY_MS);

      // Ledger ko'zgusi (READ fazasi).
      const bonusCtx = await settlementLedger.prepareBonusInTx(t, db, uid, {
        idempotencyKey: idemKey,
      });

      t.set(userRef, {
        bonusBalance: prev - tariff.price,
        balanceUpdatedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });

      t.set(ledgerRef, {
        type: 'purchase_debit',
        amount: -tariff.price,
        module: 'ev_charging',
        refType: 'ev_station_listing',
        refId: stationRef.id,
        meta: { tariff: tariffId, months: tariff.months },
        createdAt: FieldValue.serverTimestamp(),
        createdBy: uid,
      });

      t.set(stationRef, {
        location: { latitude: lat, longitude: lng },
        geohash4: geoHash.encode(lat, lng, 4),
        chargingTypes,
        connectors,
        ...(powerKw != null ? { powerKw } : {}),
        ...(price != null ? { price } : {}),
        ...(operatorName ? { operatorName } : {}),
        ...(note ? { note } : {}),
        status: 'unknown',
        verificationStatus: 'community',
        confirmationCount: 0,
        reportCount: 0,
        createdBy: uid,
        isActive: true,
        // Пуллик рўйхат — эга қарори 2026-09-22 (муддат назорати ҳозирча
        // йўқ, фақат метаданот сифатида сақланади).
        listingType: 'paid',
        paidTariff: tariffId,
        paidAmount: tariff.price,
        paidMonths: tariff.months,
        paidAt: FieldValue.serverTimestamp(),
        paidUntil,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      // Ledger ko'zgusi (WRITE fazasi) — Dr passenger_credit / Cr admin_clearing.
      settlementLedger.commitBonusInTx(t, bonusCtx, {
        delta: -tariff.price,
        kind: 'purchase_debit',
        refType: 'ev_station_listing',
        refId: stationRef.id,
        meta: { module: 'ev_charging', tariff: tariffId },
        postedBy: uid,
        postedRole: 'user',
      });

      const out = {
        ok: true,
        stationId: stationRef.id,
        debited: tariff.price,
        paidUntil: paidUntil.toMillis(),
        balance: prev - tariff.price,
      };
      t.set(idemRef, {
        type: 'payAndCreateEvStation',
        result: out,
        createdAt: FieldValue.serverTimestamp(),
      });
      return out;
    });

    return result;
  });
}

module.exports = { attachEvCharging };
