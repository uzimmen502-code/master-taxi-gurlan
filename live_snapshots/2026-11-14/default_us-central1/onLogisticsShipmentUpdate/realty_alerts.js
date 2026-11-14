'use strict';

/**
 * ИЖАРА / СОТУВ ХАБАРНОМАСИ — «шундай уй чиқса, хабар бер» (эга қарори
 * 2026-10-08, `docs/ijara_moslashtirish_taklifi_uz.md` §8-bis: A
 * архитектура, бепул, манзил пакетдан кейин).
 *
 * Оқим:
 *   1. Ижарачи `createRealtyAlert` — битим тури, марказ, радиус, хона,
 *      нарх чегараси. Ёзув `realty_alerts/{id}` (фақат сервер ёзади).
 *   2. Эълон `active` га ЎТГАНДА (`onRealtyListingActivated` trigger —
 *      авто-тасдиқ, админ тасдиғи, таҳрирдан кейинги қайта тасдиқ —
 *      учаласи ҳам шу битта йўлдан ўтади) мос хабарномалар топилади.
 *   3. Ҳар мос келган учун `realty_alert_hits/{alertId}_{listingId}`
 *      CREATE + `users/{uid}/realty_matches/{listingId}` (inbox) — битта
 *      batch'да. Hit бор бўлса batch йиқилади → push ИККИНЧИ МАРТА
 *      кетмайди (21-қоида).
 *   4. Push — кунлик чегара ва тинч соат (23:00–07:00 Тошкент) билан;
 *      чегарадан ошгани фақат inbox'да қолади.
 *
 * МАХФИЙЛИК (пуллик модель): push ва inbox'да эганинг рақами, кўча/уй,
 * аниқ нуқта ЙЎҚ — фақат очиқ ҳужжатдаги маълумот. Аниқ нуқта фақат
 * серверда, масофани ҳисоблаш учун ўқилади.
 *
 * `admin_news` ИШЛАТИЛМАЙДИ: у ҳаммага очиқ (`firestore.rules`
 * `allow read: if true`) — шахсий хабарнома у ерга тушмаслиги керак.
 */

const { encode: geohashEncode, decodeBounds } = require('./geo_hash');

/** Радиус вариантлари (км) — UI ҳам шу рўйхатни кўрсатади. */
const RADIUS_OPTIONS_KM = [1, 3, 5, 10];

/**
 * Хабарномалар prefix'и учун geohash аниқлиги. 4 → катак ≈ 39 × 19 км
 * (Хоразм кенглигида ≈ 29 × 19.5 км). Энг катта радиус 10 км, демак
 * марказ катакнинг ўзида ёки 8 қўшнисидан бирида бўлади.
 */
const ALERT_GEOHASH_PRECISION = 4;

/** Созлама топилмаса (`settings/app`). PROPOSED стандарт — эга ўзгартиради. */
const DEFAULT_MAX_ACTIVE_ALERTS = 3;
const DEFAULT_PUSH_PER_DAY = 10;
const ALERT_TTL_DAYS = 30;

/** Тинч соат — Тошкент вақти (UTC+5, ёзги вақт йўқ). */
const QUIET_FROM_HOUR = 23;
const QUIET_TO_HOUR = 7;
const TASHKENT_OFFSET_MS = 5 * 60 * 60 * 1000;

const DAY_MS = 24 * 60 * 60 * 1000;

function haversineKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(a)));
}

/**
 * Катак ва унинг 8 қўшниси. Қўшни — марказдан бир катак кенглиги/
 * баландлигича силжитилган нуқтанинг катаги (кенглик чегарасида
 * такрорлар `Set` билан тушиб қолади).
 */
function neighborCells(lat, lng, precision = ALERT_GEOHASH_PRECISION) {
  const b = decodeBounds(geohashEncode(lat, lng, precision));
  const h = b.maxLat - b.minLat;
  const w = b.maxLng - b.minLng;
  const cLat = (b.minLat + b.maxLat) / 2;
  const cLng = (b.minLng + b.maxLng) / 2;
  const out = new Set();
  for (const dy of [-1, 0, 1]) {
    for (const dx of [-1, 0, 1]) {
      const la = Math.max(-89.999, Math.min(89.999, cLat + dy * h));
      let lo = cLng + dx * w;
      if (lo > 180) lo -= 360;
      if (lo < -180) lo += 360;
      out.add(geohashEncode(la, lo, precision));
    }
  }
  return [...out];
}

function toMillis(v) {
  if (!v) return 0;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

/** Тошкент вақтида тинч соатми (23:00–07:00). */
function isQuietHour(nowMs) {
  const hour = new Date(nowMs + TASHKENT_OFFSET_MS).getUTCHours();
  return hour >= QUIET_FROM_HOUR || hour < QUIET_TO_HOUR;
}

/** Тошкент санаси `YYYY-MM-DD` — кунлик push саноғи калити. */
function tashkentDay(nowMs) {
  return new Date(nowMs + TASHKENT_OFFSET_MS).toISOString().slice(0, 10);
}

/**
 * МОСЛИК — соф функция (тестланади).
 *
 * [listing] — очиқ ҳужжат + аниқ нуқта (`lat`, `lng` — ёпиқ ҳужжатдан).
 * Хона ёки рақамли нарх эълонда кўрсатилмаган бўлса, ўша фильтр
 * қўлланмайди: «маълумот йўқ» ≠ «мос эмас» (акс ҳолда эски эълонлар
 * ҳеч кимга етиб бормасди).
 *
 * @returns {string} '' — мос; акс ҳолда сабаб (лог ва тест учун).
 */
function mismatchReason(alert, listing, nowMs) {
  if (!alert || !listing) return 'missing';
  if (alert.status !== 'active') return 'alert_inactive';
  const exp = toMillis(alert.expiresAt);
  if (exp && exp <= nowMs) return 'alert_expired';
  if (alert.deal !== listing.deal) return 'deal';
  if (alert.ownerId && listing.ownerId && alert.ownerId === listing.ownerId) {
    return 'own_listing';
  }
  const lat = Number(listing.lat);
  const lng = Number(listing.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return 'no_point';
  const km = haversineKm(Number(alert.centerLat), Number(alert.centerLng), lat, lng);
  if (!(km <= Number(alert.radiusKm))) return 'distance';

  const rooms = Number(listing.rooms);
  if (Number.isFinite(rooms) && rooms > 0) {
    if (Number.isFinite(alert.roomsMin) && rooms < alert.roomsMin) return 'rooms';
    if (Number.isFinite(alert.roomsMax) && rooms > alert.roomsMax) return 'rooms';
  }
  const price = Number(listing.priceAmount);
  if (Number.isFinite(price) && price > 0
      && Number.isFinite(alert.priceMax) && alert.priceMax > 0
      && price > alert.priceMax) {
    return 'price';
  }
  return '';
}

function optionalInt(v, min, max) {
  if (v === undefined || v === null || v === '') return null;
  const n = Number(v);
  if (!Number.isInteger(n) || n < min || n > max) return NaN;
  return n;
}

/**
 * Клиент юборган хабарнома — текширилган ва тозаланган (18-қоида).
 * Нотўғри қиймат → `reason` (callable `invalid-argument` қилади).
 */
function parseAlertInput(d) {
  const deal = d.deal === 'sale' ? 'sale' : (d.deal === 'rent' ? 'rent' : '');
  if (!deal) return { reason: 'deal_required' };
  const lat = Number(d.lat);
  const lng = Number(d.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)
      || lat < -90 || lat > 90 || lng < -180 || lng > 180
      || (lat === 0 && lng === 0)) {
    return { reason: 'location_required' };
  }
  const radiusKm = Number(d.radiusKm);
  if (!RADIUS_OPTIONS_KM.includes(radiusKm)) return { reason: 'radius_invalid' };
  const roomsMin = optionalInt(d.roomsMin, 1, 20);
  const roomsMax = optionalInt(d.roomsMax, 1, 20);
  if (Number.isNaN(roomsMin) || Number.isNaN(roomsMax)) return { reason: 'rooms_invalid' };
  if (roomsMin !== null && roomsMax !== null && roomsMin > roomsMax) {
    return { reason: 'rooms_invalid' };
  }
  // Пул — бутун сўм (8-қоида), float эмас.
  const priceMax = optionalInt(d.priceMax, 1, 1e12);
  if (Number.isNaN(priceMax)) return { reason: 'price_invalid' };
  return {
    value: {
      deal, centerLat: lat, centerLng: lng, radiusKm,
      roomsMin, roomsMax, priceMax,
    },
  };
}

function attachRealtyAlerts(exports, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid,
  } = deps;
  const messaging = () => (deps.messaging || admin.messaging());
  const nowMs = () => (deps.now ? deps.now() : Date.now());
  const ts = () => admin.firestore.FieldValue.serverTimestamp();

  function fail(code, reason, details) {
    return new functions.https.HttpsError(code, reason, {
      reason, ...(details || {}),
    });
  }

  function requireUid(context) {
    if (!context || !context.auth) throw fail('unauthenticated', 'auth_required');
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length < 9) throw fail('permission-denied', 'phone_required');
    return uid;
  }

  async function appSettings() {
    try {
      return (await db.collection('settings').doc('app').get()).data() || {};
    } catch (e) {
      console.error('realtyAlerts.settings', e.message || e);
      return {};
    }
  }

  function intSetting(app, field, fallback) {
    const n = Number((app || {})[field]);
    return Number.isInteger(n) && n > 0 ? n : fallback;
  }

  /** Эганинг актив (муддати ўтмаган) хабарномалари сони. */
  async function countActive(uid) {
    const snap = await db.collection('realty_alerts')
      .where('ownerId', '==', uid)
      .where('status', '==', 'active')
      .limit(50)
      .get();
    const now = nowMs();
    return snap.docs.filter((d) => {
      const exp = toMillis((d.data() || {}).expiresAt);
      return !exp || exp > now;
    }).length;
  }

  /**
   * Ҳозир мос келадиган АКТИВ эълонлар — хабарнома сақланганда дарҳол
   * кўрсатиш учун (push эмас). Масофа ОЧИҚ нуқта бўйича (≈1.2 км
   * силкитилган) — шунинг учун радиусга силкитиш чегараси қўшилади:
   * тахминий рўйхат, аниқ мослик trigger'да аниқ нуқта билан.
   */
  async function currentMatches(alert, uid) {
    const cells = neighborCells(alert.centerLat, alert.centerLng);
    const snap = await db.collection('realty_listings')
      .where('status', '==', 'active')
      .where('geohash4', 'in', cells)
      .limit(300)
      .get();
    const now = nowMs();
    const loose = { ...alert, radiusKm: alert.radiusKm + 1.2, status: 'active', ownerId: uid };
    const out = [];
    for (const doc of snap.docs) {
      const d = doc.data() || {};
      const exp = toMillis(d.expiresAt);
      if (exp && exp <= now) continue;
      const reason = mismatchReason(loose, {
        deal: d.deal, rooms: d.rooms, priceAmount: d.priceAmount,
        lat: d.areaLat, lng: d.areaLng,
      }, now);
      if (!reason) out.push({ id: doc.id, createdAt: toMillis(d.createdAt) });
    }
    out.sort((a, b) => b.createdAt - a.createdAt);
    return out.slice(0, 50).map((x) => x.id);
  }

  /**
   * Ижарачи: янги хабарнома. `idempotencyKey` берилса ҳужжат ID шундан —
   * тармоқ узилиб қайта босилса иккинчи хабарнома яратилмайди.
   */
  exports.createRealtyAlert = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const d = data || {};
    const parsed = parseAlertInput(d);
    if (parsed.reason) throw fail('invalid-argument', parsed.reason);
    const alert = parsed.value;

    const key = String(d.idempotencyKey || '').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 40);
    const ref = key
      ? db.collection('realty_alerts').doc(`${uid}_${key}`)
      : db.collection('realty_alerts').doc();
    if (key) {
      const existing = await ref.get();
      if (existing.exists) {
        return { ok: true, alertId: ref.id, duplicate: true, matches: [] };
      }
    }

    const app = await appSettings();
    const maxActive = intSetting(app, 'realtyAlertMaxActive', DEFAULT_MAX_ACTIVE_ALERTS);
    if (await countActive(uid) >= maxActive) {
      throw fail('resource-exhausted', 'alert_limit_reached', { limit: maxActive });
    }

    const now = nowMs();
    await ref.set({
      ownerId: uid,
      ...alert,
      geohash4: geohashEncode(alert.centerLat, alert.centerLng, ALERT_GEOHASH_PRECISION),
      status: 'active',
      expiresAt: admin.firestore.Timestamp.fromMillis(now + ALERT_TTL_DAYS * DAY_MS),
      createdAt: ts(),
      updatedAt: ts(),
    });

    let matches = [];
    try {
      matches = await currentMatches(alert, uid);
    } catch (e) {
      // Рўйхат ёрдамчи — хабарнома барибир сақланди.
      console.error('createRealtyAlert.currentMatches', e.message || e);
    }
    console.log(JSON.stringify({
      action: 'createRealtyAlert', alertId: ref.id, result: 'ok', matches: matches.length,
    }));
    return { ok: true, alertId: ref.id, matches };
  });

  /**
   * Ижарачи: тўхтатиш / қайта ёқиш (+30 кун) / ўчириш.
   * Қайта ёқиш ҳам лимитга киради.
   */
  exports.setRealtyAlertStatus = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const d = data || {};
    const alertId = String(d.alertId || '').trim();
    const status = String(d.status || '');
    if (!alertId) throw fail('invalid-argument', 'alert_required');
    if (!['active', 'paused', 'deleted'].includes(status)) {
      throw fail('invalid-argument', 'status_invalid');
    }
    const ref = db.collection('realty_alerts').doc(alertId);
    const snap = await ref.get();
    if (!snap.exists || (snap.data() || {}).ownerId !== uid) {
      throw fail('permission-denied', 'not_owner');
    }
    if (status === 'deleted') {
      await ref.delete();
      return { ok: true, status };
    }
    if (status === 'active') {
      const cur = snap.data() || {};
      const curActive = cur.status === 'active' && toMillis(cur.expiresAt) > nowMs();
      if (!curActive) {
        const app = await appSettings();
        const maxActive = intSetting(app, 'realtyAlertMaxActive', DEFAULT_MAX_ACTIVE_ALERTS);
        if (await countActive(uid) >= maxActive) {
          throw fail('resource-exhausted', 'alert_limit_reached', { limit: maxActive });
        }
      }
      await ref.update({
        status: 'active',
        expiresAt: admin.firestore.Timestamp.fromMillis(nowMs() + ALERT_TTL_DAYS * DAY_MS),
        updatedAt: ts(),
      });
      return { ok: true, status };
    }
    await ref.update({ status: 'paused', updatedAt: ts() });
    return { ok: true, status };
  });

  /**
   * Кунлик push чегараси — транзакцияда (22-қоида: иккита эълон бир
   * вақтда тасдиқланса ҳам чегара бузилмайди). `true` — юбориш мумкин.
   */
  async function takePushSlot(uid, perDay) {
    const ref = db.collection('users').doc(uid).collection('realty_alert_meta').doc('push');
    const day = tashkentDay(nowMs());
    return db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const cur = snap.data() || {};
      const count = cur.day === day ? Number(cur.count || 0) : 0;
      if (count >= perDay) return false;
      t.set(ref, { day, count: count + 1, updatedAt: ts() });
      return true;
    });
  }

  async function sendPush(uid, listingId, listing) {
    const user = (await db.collection('users').doc(uid).get()).data() || {};
    const token = user.fcmToken;
    if (!token) return 'no_token';
    const rooms = Number(listing.rooms) > 0 ? `${listing.rooms} хона` : '';
    const price = String(listing.priceText || '').trim();
    const body = [rooms, price].filter(Boolean).join(' · ')
      || String(listing.title || '').slice(0, 60);
    try {
      await messaging().send({
        token,
        notification: {
          title: listing.deal === 'sale'
            ? '🏠 Сиз қидирган ҳудудда янги эълон'
            : '🏠 Сиз қидирган ҳудудда янги ижара',
          body: body.slice(0, 120),
        },
        // Фақат ID — манзил ва рақам push'да ЙЎҚ.
        data: { type: 'realty_match', screen: 'realty_match', listingId },
        android: { priority: 'high' },
      });
      return 'sent';
    } catch (e) {
      console.error('realtyAlerts.push', e.message || e);
      return 'error';
    }
  }

  /**
   * Эълон актив бўлганда мос хабарномаларни топиш ва хабар бериш.
   * IDEMPOTENT: такрорий чақирув ҳеч нарса юбормайди (hit бор).
   */
  async function matchListing(listingId) {
    const started = nowMs();
    const ref = db.collection('realty_listings').doc(listingId);
    const [pubSnap, privSnap] = await Promise.all([
      ref.get(), ref.collection('private').doc('detail').get(),
    ]);
    if (!pubSnap.exists) return { matched: 0, pushed: 0, reason: 'no_listing' };
    const pub = pubSnap.data() || {};
    const priv = privSnap.data() || {};
    if (pub.status !== 'active') return { matched: 0, pushed: 0, reason: 'not_active' };
    const lat = Number(priv.lat);
    const lng = Number(priv.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      return { matched: 0, pushed: 0, reason: 'no_point' };
    }
    const listing = {
      deal: pub.deal, rooms: pub.rooms, priceAmount: pub.priceAmount,
      ownerId: canonicalUid(String(priv.ownerId || '')), lat, lng,
    };

    const cells = neighborCells(lat, lng);
    const snap = await db.collection('realty_alerts')
      .where('status', '==', 'active')
      .where('deal', '==', pub.deal)
      .where('geohash4', 'in', cells)
      .limit(500)
      .get();

    const app = await appSettings();
    const perDay = intSetting(app, 'realtyAlertPushPerDay', DEFAULT_PUSH_PER_DAY);
    const quiet = isQuietHour(nowMs());
    let matched = 0;
    let pushed = 0;
    for (const doc of snap.docs) {
      const alert = doc.data() || {};
      if (mismatchReason(alert, listing, nowMs())) continue;
      const uid = String(alert.ownerId || '');
      const batch = db.batch();
      batch.create(db.collection('realty_alert_hits').doc(`${doc.id}_${listingId}`), {
        alertId: doc.id, listingId, ownerId: uid, at: ts(),
      });
      batch.set(db.collection('users').doc(uid).collection('realty_matches').doc(listingId), {
        listingId,
        alertId: doc.id,
        deal: pub.deal,
        title: String(pub.title || '').slice(0, 120),
        priceText: String(pub.priceText || '').slice(0, 80),
        ...(Number(pub.rooms) > 0 ? { rooms: Number(pub.rooms) } : {}),
        seen: false,
        createdAt: ts(),
      });
      try {
        await batch.commit();
      } catch (e) {
        // 6 = ALREADY_EXISTS: шу хабарнома шу эълон учун аввал ишлаган.
        if (e.code === 6 || e.code === 'already-exists') continue;
        console.error('realtyAlerts.hit', doc.id, listingId, e.message || e);
        continue;
      }
      matched += 1;
      if (quiet) continue;
      try {
        if (!(await takePushSlot(uid, perDay))) continue;
      } catch (e) {
        console.error('realtyAlerts.slot', uid, e.message || e);
        continue;
      }
      if ((await sendPush(uid, listingId, pub)) === 'sent') pushed += 1;
    }
    console.log(JSON.stringify({
      action: 'matchRealtyListing', listingId, result: 'ok',
      candidates: snap.size, matched, pushed, quiet, duration: nowMs() - started,
    }));
    return { matched, pushed };
  }

  exports.onRealtyListingActivated = functions.firestore
    .document('realty_listings/{listingId}')
    .onWrite(async (change, context) => {
      const before = change.before.exists ? (change.before.data() || {}) : null;
      const after = change.after.exists ? (change.after.data() || {}) : null;
      if (!after || after.status !== 'active') return null;
      if (before && before.status === 'active') return null;
      try {
        await matchListing(context.params.listingId);
      } catch (e) {
        console.error('onRealtyListingActivated', context.params.listingId, e.message || e);
      }
      return null;
    });

  /** Кунига бир марта: муддати ўтган хабарномалар `expired` (сўровлар енгил бўлсин). */
  exports.realtyAlertsExpirySweep = functions.pubsub
    .schedule('40 0 * * *')
    .timeZone('Asia/Tashkent')
    .onRun(async () => {
      const now = admin.firestore.Timestamp.fromMillis(nowMs());
      let expired = 0;
      for (let round = 0; round < 10; round += 1) {
        const snap = await db.collection('realty_alerts')
          .where('status', '==', 'active')
          .where('expiresAt', '<=', now)
          .limit(300)
          .get();
        if (snap.empty) break;
        const batch = db.batch();
        snap.docs.forEach((doc) => batch.update(doc.ref, { status: 'expired', updatedAt: ts() }));
        await batch.commit();
        expired += snap.size;
        if (snap.size < 300) break;
      }
      console.log(JSON.stringify({ action: 'realtyAlertsExpirySweep', result: 'ok', expired }));
      return null;
    });

  return { matchListing };
}

module.exports = {
  attachRealtyAlerts,
  // Тест учун соф функциялар.
  mismatchReason,
  parseAlertInput,
  neighborCells,
  haversineKm,
  isQuietHour,
  tashkentDay,
  RADIUS_OPTIONS_KM,
};
