const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios');
const crypto = require('crypto');
admin.initializeApp();

const db = admin.firestore();

const settlementLedger = require('./settlement_ledger');

const DEVICE_BINDING_MAX_FAILED = 5;
/** Soft cooldown (Faza 1) — 24 soat hard block o‘rniga. */
const DEVICE_BINDING_BLOCK_MS = 30 * 60 * 1000;
const DEVICE_TRANSFER_TTL_MS = 30 * 60 * 1000;
const DEVICE_TRUST_LIMITED_MS = 24 * 60 * 60 * 1000;
const DEVICE_TRANSFER_MAX_PER_DAY = 5;

/** Offline / hujjat yo'q — Dart [PassengerCancelRulesConfig.defaults] bilan sinxron. */
const PASSENGER_CANCEL_RULES_DEFAULTS = {
  cancelLimit: 5,
  windowMinutes: 10,
  blockMinutes: 10,
};

let cachedPassengerCancelRules = null;
let passengerCancelRulesCacheTime = 0;
const PASSENGER_CANCEL_RULES_CACHE_TTL_MS = 60 * 1000;

function passengerCancelRulesFromDefaults() {
  return {
    cancelLimit: PASSENGER_CANCEL_RULES_DEFAULTS.cancelLimit,
    windowMinutes: PASSENGER_CANCEL_RULES_DEFAULTS.windowMinutes,
    blockMinutes: PASSENGER_CANCEL_RULES_DEFAULTS.blockMinutes,
    windowMs: PASSENGER_CANCEL_RULES_DEFAULTS.windowMinutes * 60 * 1000,
    blockMs: PASSENGER_CANCEL_RULES_DEFAULTS.blockMinutes * 60 * 1000,
  };
}

/** `config/passenger_cancel_block` — marshrut (60s kesh). */
async function getPassengerCancelRules() {
  const now = Date.now();
  if (cachedPassengerCancelRules &&
      (now - passengerCancelRulesCacheTime) < PASSENGER_CANCEL_RULES_CACHE_TTL_MS) {
    return cachedPassengerCancelRules;
  }

  try {
    const doc = await db.collection('config').doc('passenger_cancel_block').get();
    if (doc.exists) {
      const d = doc.data() || {};
      const windowMinutes = Number(d.windowMinutes) ||
          PASSENGER_CANCEL_RULES_DEFAULTS.windowMinutes;
      const blockMinutes = Number(d.blockMinutes) ||
          PASSENGER_CANCEL_RULES_DEFAULTS.blockMinutes;
      cachedPassengerCancelRules = {
        cancelLimit: Number(d.cancelLimit) ||
            PASSENGER_CANCEL_RULES_DEFAULTS.cancelLimit,
        windowMinutes,
        blockMinutes,
        windowMs: windowMinutes * 60 * 1000,
        blockMs: blockMinutes * 60 * 1000,
      };
    } else {
      cachedPassengerCancelRules = passengerCancelRulesFromDefaults();
    }
  } catch (e) {
    console.error('getPassengerCancelRules:', e);
    cachedPassengerCancelRules = passengerCancelRulesFromDefaults();
  }

  passengerCancelRulesCacheTime = now;
  return cachedPassengerCancelRules;
}

async function applyPassengerCancelBlock(stateRef) {
  const rules = await getPassengerCancelRules();
  const snap = await stateRef.get();
  const now = Date.now();

  let cancelCount = 0;
  let firstCancelAt = now;
  let blockedUntil = null;

  if (snap.exists) {
    const d = snap.data() || {};
    blockedUntil = d.blockedUntil?.toMillis?.() ?? null;
    firstCancelAt = d.firstCancelAt?.toMillis?.() ?? now;
    cancelCount = d.cancelCount ?? 0;

    if (blockedUntil && now < blockedUntil) {
      return { blocked: true, cancelCount };
    }

    if (now - firstCancelAt > rules.windowMs) {
      cancelCount = 0;
      firstCancelAt = now;
    }
  }

  cancelCount += 1;

  if (cancelCount >= rules.cancelLimit) {
    await stateRef.set({
      cancelCount,
      firstCancelAt: admin.firestore.Timestamp.fromMillis(firstCancelAt),
      blockedUntil: admin.firestore.Timestamp.fromMillis(
          now + rules.blockMs),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { blocked: true, cancelCount };
  }
  await stateRef.set({
    cancelCount,
    firstCancelAt: admin.firestore.Timestamp.fromMillis(firstCancelAt),
    blockedUntil: null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { blocked: false, cancelCount };
}

/** Local taxi: accepted дан кейинги бекор зинаси.
 *  3 = енгил огоҳ; 4 = қаттиқ (қизил); 5+ = 15 дақ блок.
 *  Счёт муваффақ complete да нолга (қаранг completeLocalTrip).
 */
const LOCAL_CANCEL_SOFT_WARN_AT = 3;
const LOCAL_CANCEL_HARD_WARN_AT = 4;
const LOCAL_CANCEL_BLOCK_AT = 5;
const LOCAL_CANCEL_BLOCK_MS = 15 * 60 * 1000;

async function applyLocalTaxiCancelBlock(userPhone, { tripRef } = {}) {
  const phone = digits(userPhone);
  if (phone.length < 9) {
    return {
      blocked: false,
      softWarning: false,
      hardWarning: false,
      cancelCount: 0,
      level: 'none',
    };
  }
  const stateRef = db.collection('users').doc(phone)
      .collection('local_taxi_block').doc('state');

  return db.runTransaction(async (t) => {
    if (tripRef) {
      const tripSnap = await t.get(tripRef);
      if (!tripSnap.exists) {
        return {
          blocked: false,
          softWarning: false,
          hardWarning: false,
          cancelCount: 0,
          level: 'none',
          skipped: true,
        };
      }
      const trip = tripSnap.data() || {};
      if (trip.localTaxiBlockCounted === true) {
        return {
          blocked: false,
          softWarning: false,
          hardWarning: false,
          cancelCount: Number(trip.localCancelFeedback?.cancelCount || 0),
          level: trip.localCancelFeedback?.level || 'none',
          remaining: trip.localCancelFeedback?.remaining != null
              ? trip.localCancelFeedback.remaining
              : null,
          blockMinutes: trip.localCancelFeedback?.blockMinutes != null
              ? trip.localCancelFeedback.blockMinutes
              : null,
          alreadyCounted: true,
        };
      }
    }

    const snap = await t.get(stateRef);
    const now = Date.now();

    let cancelCount = 0;
    let blockedUntil = null;

    if (snap.exists) {
      const d = snap.data() || {};
      blockedUntil = d.blockedUntil?.toMillis?.() ?? null;

      if (blockedUntil && now < blockedUntil) {
        const result = {
          blocked: true,
          softWarning: false,
          hardWarning: false,
          cancelCount: d.cancelCount ?? 0,
          level: 'block',
          blockMinutes: Math.ceil((blockedUntil - now) / 60000),
        };
        if (tripRef) {
          t.update(tripRef, {
            localTaxiBlockCounted: true,
            localCancelFeedback: {
              level: result.level,
              cancelCount: result.cancelCount,
              remaining: null,
              blockMinutes: result.blockMinutes,
            },
          });
        }
        return result;
      }

      if (blockedUntil && now >= blockedUntil) {
        cancelCount = 0;
        blockedUntil = null;
      } else {
        cancelCount = d.cancelCount ?? 0;
      }
    }

    cancelCount += 1;

    let result;
    if (cancelCount >= LOCAL_CANCEL_BLOCK_AT) {
      t.set(stateRef, {
        cancelCount,
        blockedUntil: admin.firestore.Timestamp.fromMillis(
            now + LOCAL_CANCEL_BLOCK_MS),
        firstCancelAt: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      result = {
        blocked: true,
        softWarning: false,
        hardWarning: false,
        cancelCount,
        level: 'block',
        blockMinutes: Math.round(LOCAL_CANCEL_BLOCK_MS / 60000),
        remaining: 0,
      };
    } else {
      const softWarning = cancelCount === LOCAL_CANCEL_SOFT_WARN_AT;
      const hardWarning = cancelCount === LOCAL_CANCEL_HARD_WARN_AT;
      let level = 'none';
      if (hardWarning) level = 'hard';
      else if (softWarning) level = 'soft';

      t.set(stateRef, {
        cancelCount,
        blockedUntil: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      result = {
        blocked: false,
        softWarning,
        hardWarning,
        cancelCount,
        level,
        remaining: LOCAL_CANCEL_BLOCK_AT - cancelCount,
      };
    }

    if (tripRef) {
      t.update(tripRef, {
        localTaxiBlockCounted: true,
        localCancelFeedback: {
          level: result.level || 'none',
          cancelCount: result.cancelCount || 0,
          remaining: result.remaining != null ? result.remaining : null,
          blockMinutes: result.blockMinutes != null
              ? result.blockMinutes
              : null,
        },
      });
    }
    return result;
  });
}

async function resetLocalTaxiCancelBlock(userPhone) {
  const phone = digits(userPhone);
  if (phone.length < 9) return;
  const stateRef = db.collection('users').doc(phone)
      .collection('local_taxi_block').doc('state');
  await stateRef.set({
    cancelCount: 0,
    blockedUntil: null,
    firstCancelAt: null,
    resetReason: 'trip_completed',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

const MARSHRUT_CANCEL_WARN_AT = 5;
const MARSHRUT_CANCEL_BLOCK_AT = 7;
const MARSHRUT_CANCEL_BLOCK_MS = 10 * 60 * 1000;

async function applyMarshhrutCancelBlock(userPhone) {
  const phone = digits(userPhone);
  if (phone.length < 9) {
    return { blocked: false, warning: false };
  }

  const ref = db.collection('users').doc(phone)
      .collection('marshrut_block').doc('state');
  const snap = await ref.get();
  const now = Date.now();

  let cancelCount = 0;
  let blockedUntil = null;

  if (snap.exists) {
    const d = snap.data() || {};
    blockedUntil = d.blockedUntil?.toMillis?.() ?? null;

    if (blockedUntil && now < blockedUntil) {
      return { blocked: true, warning: false };
    }

    if (blockedUntil && now >= blockedUntil) {
      cancelCount = 0;
      blockedUntil = null;
    } else {
      cancelCount = d.cancelCount ?? 0;
    }
  }

  cancelCount += 1;

  if (cancelCount >= MARSHRUT_CANCEL_BLOCK_AT) {
    await ref.set({
      cancelCount,
      blockedUntil: admin.firestore.Timestamp.fromMillis(
          now + MARSHRUT_CANCEL_BLOCK_MS),
      warningShown: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { blocked: true, warning: false };
  }

  if (cancelCount === MARSHRUT_CANCEL_WARN_AT) {
    await ref.set({
      cancelCount,
      blockedUntil: null,
      warningShown: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {
      blocked: false,
      warning: true,
      remaining: MARSHRUT_CANCEL_BLOCK_AT - cancelCount,
    };
  }

  await ref.set({
    cancelCount,
    blockedUntil: null,
    warningShown: false,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { blocked: false, warning: false };
}

function isValidFingerprintHash(hash) {
  return typeof hash === 'string' && /^[a-f0-9]{64}$/i.test(hash.trim());
}

function deviceBindingBlocked(data) {
  if (!data || !data.isBlocked) return false;
  const until = data.blockedUntil;
  if (!until || typeof until.toDate !== 'function') return true;
  return until.toDate().getTime() > Date.now();
}

/** Peer-transferdan keyin 24s: pul yechish cheklangan. */
function isDeviceTrustLimited(userData) {
  const sec = (userData && userData.security) || {};
  if (String(sec.deviceTrustMode || '') !== 'limited') return false;
  const until = sec.deviceTrustUntil;
  if (!until || typeof until.toDate !== 'function') return true;
  return until.toDate().getTime() > Date.now();
}

async function assertNotDeviceTrustLimited(uid) {
  const id = canonicalUid(uid);
  if (id.length < 12) return;
  const snap = await db.collection('users').doc(id).get();
  if (!snap.exists) return;
  if (!isDeviceTrustLimited(snap.data())) return;
  const until = (snap.data().security || {}).deviceTrustUntil;
  const untilMs = until && typeof until.toDate === 'function'
    ? until.toDate().getTime()
    : 0;
  throw new functions.https.HttpsError(
    'failed-precondition',
    'Yangi qurilma: pul yechish 24 soatga cheklangan. Keyinroq urinib ko\'ring.',
    { code: 'device_trust_limited', untilMs },
  );
}

function oldDeviceLabelFromBinding(binding) {
  const fp = (binding && binding.fingerprint) || {};
  const brand = String(fp.brand || fp.Brand || '').trim();
  const model = String(fp.model || fp.Model || '').trim();
  return [brand, model].filter(Boolean).join(' ').slice(0, 80);
}

async function notifyDeviceTransferRequest(phone, requestId, newDeviceLabel) {
  const label = String(newDeviceLabel || '').trim();
  const body = label
    ? `Yangi qurilma (${label}) kirish so‘radi. Tasdiqlaysizmi?`
    : 'Yangi qurilma shu raqam bilan kirish so‘radi. Tasdiqlaysizmi?';
  await notifyUserInApp({
    userId: phone,
    title: '🔐 Qurilma almashtirish',
    body,
    category: 'info',
    source: 'device_transfer',
    dataType: 'device_transfer_request',
    screen: 'device_transfer',
    extraData: { requestId: String(requestId || '') },
  });
}

async function authUserForPhoneDigits(phone) {
  const digits = canonicalUid(phone);
  const e164 = `+${digits}`;
  try {
    return await admin.auth().getUserByPhoneNumber(e164);
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      try {
        return await admin.auth().createUser({ phoneNumber: e164 });
      } catch (createErr) {
        if (createErr.code === 'auth/phone-number-already-exists') {
          return admin.auth().getUserByPhoneNumber(e164);
        }
        throw createErr;
      }
    }
    throw e;
  }
}

function sanitizeFingerprintMap(raw) {
  if (!raw || typeof raw !== 'object') return {};
  const out = {};
  for (const [key, value] of Object.entries(raw)) {
    if (typeof key !== 'string' || !key.trim()) continue;
    const s = String(value == null ? '' : value).trim();
    if (s.length > 512) continue;
    out[key] = s;
  }
  return out;
}

async function createPhoneCustomToken(phone) {
  const digits = canonicalUid(phone);
  const e164 = `+${digits}`;
  try {
    const authUser = await authUserForPhoneDigits(digits);
    // phone_number must be a durable custom claim — createCustomToken developer
    // claims alone are dropped on ID token refresh (~1h), and Firestore isOwner()
    // / isAdmin() rely on token.phone_number (same pattern as adminWebSignIn).
    await admin.auth().setCustomUserClaims(authUser.uid, {
      ...(authUser.customClaims || {}),
      phone_number: e164,
    });
    return await admin.auth().createCustomToken(authUser.uid, {
      phone_number: e164,
    });
  } catch (err) {
    const code = err.errorInfo?.code ?? err.code ?? 'unknown';
    throw new functions.https.HttpsError(
      'internal',
      `Custom token creation failed: ${code}`,
    );
  }
}

async function isDeviceBindingAutoApproveEnabled() {
  const snap = await db.collection('settings').doc('app').get();
  return (snap.data() || {}).deviceBindingAutoApprove === true;
}

async function isDatingAutoApproveEnabled() {
  const snap = await db.collection('settings').doc('app').get();
  return (snap.data() || {}).datingAutoApprove === true;
}

async function isMarketAutoApproveEnabled() {
  const snap = await db.collection('settings').doc('app').get();
  return (snap.data() || {}).marketAutoApprove === true;
}

async function isJobsAutoApproveEnabled() {
  const snap = await db.collection('settings').doc('app').get();
  return (snap.data() || {}).jobsAutoApprove === true;
}

/** Admin yoki auto-rejim: telefon ↔ hash bog'lanishini majburan yangilash. */
async function forceDeviceBindingLink({
  hash,
  phone,
  verifiedMethod,
  fingerprint,
}) {
  const bindingRef = db.collection('device_bindings').doc(hash);
  const aliasRef = db.collection('device_aliases').doc(phone);
  const now = admin.firestore.FieldValue.serverTimestamp();

  await db.runTransaction(async (tx) => {
    const bindingSnap = await tx.get(bindingRef);
    const aliasSnap = await tx.get(aliasRef);

    if (aliasSnap.exists) {
      const oldHash = String(aliasSnap.data().deviceFingerprintHash || '').toLowerCase();
      if (oldHash && oldHash !== hash && isValidFingerprintHash(oldHash)) {
        const oldBindingRef = db.collection('device_bindings').doc(oldHash);
        tx.set(oldBindingRef, {
          phone: '',
          previousPhone: phone,
          unboundAt: now,
          updatedAt: now,
        }, { merge: true });
      }
    }

    if (bindingSnap.exists) {
      const oldPhone = canonicalUid(bindingSnap.data().phone || '');
      if (oldPhone && oldPhone !== phone) {
        tx.delete(db.collection('device_aliases').doc(oldPhone));
      }
    }

    tx.set(bindingRef, {
      phone,
      deviceFingerprintHash: hash,
      firstRegisteredAt: bindingSnap.exists
        ? (bindingSnap.data().firstRegisteredAt || now)
        : now,
      lastSeenAt: now,
      failedAttempts: 0,
      isBlocked: false,
      blockedUntil: admin.firestore.FieldValue.delete(),
      verifiedMethod: verifiedMethod || 'admin_manual',
      ...(fingerprint && typeof fingerprint === 'object' ? { fingerprint } : {}),
      adminApprovedAt: now,
      updatedAt: now,
    }, { merge: true });

    tx.set(aliasRef, {
      phone,
      deviceFingerprintHash: hash,
      updatedAt: now,
    }, { merge: true });
  });
}

function digits(v) {
  return String(v || '').replace(/[^\d]/g, '');
}

/** Firebase Phone Auth token'dan telefon raqamini digits formatida olish.
 *  token.phone_number = '+998901234567' → '998901234567'
 */
function callerPhone(context) {
  const raw = (context && context.auth && context.auth.token
    ? context.auth.token.phone_number || ''
    : '');
  return raw.replace(/\D/g, '');
}

/** Callable auth: token phone + Firestore role. Returns canonical uid (998…). */
async function requireCallerRoles(context, roles, deniedMessage) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }
  const phone = callerPhone(context);
  const uid = canonicalUid(phone);
  if (!uid || uid.length < 9) {
    throw new functions.https.HttpsError('unauthenticated', 'Phone token required');
  }
  const doc = await db.collection('users').doc(uid).get();
  const role = (doc.data() || {}).role || 'user';
  if (!roles.includes(role)) {
    throw new functions.https.HttpsError(
      'permission-denied',
      deniedMessage || 'Insufficient role',
    );
  }
  return uid;
}

/** Бир xil `users` / `targetUserId` формати (998 + 9 рақам). */
function canonicalUid(v) {
  const d = digits(v);
  if (d.length === 9) return `998${d}`;
  return d;
}

/**
 * Home bottom badge — denormalized counters (client watches 2 docs, not 6–8 news streams).
 * - Broadcast: increment config/home_news_badge.broadcastSeq
 * - Personal (dialog/order): increment users/{uid}.homeBadgePersonal
 */
async function bumpHomeNewsBadge(newsData) {
  const d = newsData || {};
  const target = canonicalUid(d.targetUserId || '');
  const source = String(d.source || '').trim();
  const category = String(d.category || '').trim();
  const isOrder =
    source === 'order_status' ||
    source === 'order_placed' ||
    category === 'order';
  const isPersonal = target.length >= 9;
  const isBroadcast =
    !isOrder &&
    !isPersonal &&
    (source === '' || source === 'admin_compose' || source === 'broadcast');

  if (isBroadcast) {
    await db.collection('config').doc('home_news_badge').set({
      broadcastSeq: admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return;
  }
  if (isPersonal) {
    await db.collection('users').doc(target).set({
      homeBadgePersonal: admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }
}

/** Админ номи билан мижоз чатига (support_chats) — systemOrder: такрор push йўқ */
async function appendSystemSupportChatMessage(userDigits, text) {
  const d = digits(userDigits);
  if (!d || d.length < 9) return;
  const t = String(text || '').trim();
  if (!t) return;
  const chatRef = db.collection('support_chats').doc(d);
  const msgRef = chatRef.collection('messages').doc();
  const batch = db.batch();
  batch.set(chatRef, {
    userPhone: d,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    lastMessage: t.slice(0, 200),
    lastFromAdmin: true,
  }, { merge: true });
  batch.set(msgRef, {
    text: t,
    fromAdmin: true,
    fromPhone: '',
    fromName: 'Админ',
    sender: 'admin',
    systemOrder: true,
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await batch.commit();
}

/** Мижозга admin_news + FCM (буюртма, эълон, сотиш, тасдиқ). */
async function notifyUserInApp({
  userId,
  title,
  body,
  category = 'info',
  source = 'system',
  dataType = 'general',
  screen = 'news',
  tab = '',
  extraNews = {},
  extraData = {},
  channelId = '',
}) {
  const uid = canonicalUid(userId);
  if (uid.length < 9) return;
  const t = String(title || '').trim();
  const b = String(body || '').trim();
  if (!t) return;

  await db.collection('admin_news').add({
    title: t,
    body: b || t,
    category,
    audience: 'user',
    targetUserId: uid,
    source,
    priority: 7,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    ...extraNews,
  });

  const userDoc = await db.collection('users').doc(uid).get();
  const token = userDoc.data()?.fcmToken;
  if (!token) return;

  try {
    await admin.messaging().send({
      token,
      notification: {
        title: t.startsWith('📢') ? t : `📢 ${t}`,
        body: b.slice(0, 120) || t,
      },
      data: {
        type: dataType,
        screen,
        ...(tab ? { tab } : {}),
        ...extraData,
      },
      android: {
        priority: 'high',
        ...(channelId
          ? { notification: { channelId, sound: 'incoming_ring' } }
          : {}),
      },
    });
  } catch (e) {
    console.error('notifyUserInApp FCM:', e.message || e);
  }
}

/** Мижозга қўнғироқли «курьер етиб келди» огоҳлантириши (барча курьер модуллари). */
async function notifyCourierArrivedToCustomer(customerPhone, extraData = {}) {
  const phone = canonicalUid(customerPhone || '');
  if (!phone || phone.length < 9) return;
  await notifyUserInApp({
    userId: phone,
    title: '🔔 Курьер етиб келди',
    body: 'Курьер манзилингизга етиб келди. Илтимос, кутиб олинг.',
    category: 'order',
    source: 'courier_arrived',
    dataType: 'courier_arrived',
    screen: 'orders',
    extraData: { ring: '1', ...extraData },
    channelId: 'courier_arrival_alarm',
  });
}

async function getOrderFlowMode(field, defaultValue = 'manual') {
  try {
    const snap = await db.collection('settings').doc('app').get();
    const v = snap.data()?.[field];
    return v === 'auto' ? 'auto' : defaultValue;
  } catch (_) {
    return defaultValue;
  }
}

// Буюртма статуси ўзгарганда
exports.onOrderUpdate = functions.firestore
  .document('orders/{orderId}')
  .onUpdate(async (change) => {
    const before = change.before.data();
    const after  = change.after.data();
    if (before.status === after.status) return;

    const afterStatus = after.status === 'courier' ? 'in_delivery' : after.status;
    if (
      before.status !== 'accepted' &&
      afterStatus === 'accepted'
    ) {
      const readyMode = await getOrderFlowMode('orderReadyMode');
      if (readyMode === 'auto') {
        await change.after.ref.update(buildOrderStatusPatch('ready'));
        return;
      }
    }

    const uid = canonicalUid(after.userPhone || after.phone || '');
    if (!uid || uid.length < 9) {
      console.warn('onOrderUpdate: userPhone topilmadi', change.after.id);
      return;
    }

    const user = await admin.firestore().collection('users').doc(uid).get();
    const token = user.data()?.fcmToken;

    const status = after.status === 'courier' ? 'in_delivery' : after.status;

    let title = '', body = '';
    switch (status) {
      case 'accepted':
        title = '✅ Буюртмангиз қабул қилинди!';
        body  = `🕐 ${after.deliveryTime || 'Яқин орада'}`;
        break;
      case 'rejected':
        title = '❌ Буюртмангиз рад этилди';
        body  = after.rejectReason || '';
        break;
      case 'ready':
        title = '🟠 Буюртмангиз тайёр!';
        body  = 'Жўнатишни кутинг';
        break;
      case 'in_delivery':
        title = '🚚 Буюртмангиз йўлда!';
        body  = 'Курьер етказилмоқда';
        break;
      case 'delivered':
        if (before.paymentStatus !== 'paid' && after.paymentStatus === 'paid') {
          return;
        }
        title = '🟢 Буюртма етказилди!';
        body  = 'Раҳмат!';
        break;
      case 'cancelled':
        title = '❌ Буюртма бекор қилинди';
        body  = after.cancelReason || after.rejectReason || '';
        break;
      default: return;
    }

    const orderType = after.type || 'bread';
    const typeLabel = orderType === 'food' ? 'Тайёр овқат' : 'Нон';
    const newsBody = [body, typeLabel].filter(Boolean).join('\n');
    await db.collection('admin_news').add({
      title,
      body: newsBody,
      category: 'order',
      audience: 'user',
      targetUserId: uid,
      source: 'order_status',
      orderId: change.after.id,
      orderStatus: status,
      orderType,
      priority: 8,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const fcmTitle = `📢 ${title}`;
    const fcmBody = body || typeLabel;

    if (token) {
      await admin.messaging().send({
        token,
        notification: { title: fcmTitle, body: fcmBody },
        data: { type: 'order', status, screen: 'news', tab: 'orders' },
        android: { priority: 'high' },
      });
    }
  });

function formatOrderReceiptBody(order) {
  const lines = [];
  const items = order.items || [];
  const fmt = new Intl.NumberFormat('uz-UZ');
  for (let i = 0; i < items.length; i += 1) {
    const it = items[i] || {};
    const name = String(it.name || '?');
    const count = it.count || 1;
    const qty = it.qty;
    const unit = String(it.unit || '').trim();
    if (qty != null && Number(qty) > 0) {
      lines.push(`• ${name}: ${qty}${unit ? ` ${unit}` : ''}`);
    } else {
      lines.push(`• ${name} × ${count}`);
    }
  }
  const extras = order.extras || [];
  for (let j = 0; j < extras.length; j += 1) {
    const ex = extras[j] || {};
    const name = String(ex.name || '').trim();
    if (!name) continue;
    const count = ex.count;
    const unit = String(ex.unit || '').trim();
    const total = ex.total;
    if (count != null && Number(count) > 0) {
      const price = total != null ? ` = ${fmt.format(Math.round(Number(total)))} сўм` : '';
      lines.push(`• ${name}: ${count}${unit ? ` ${unit}` : ''}${price}`);
    } else {
      lines.push(`• ${name}`);
    }
  }
  if (lines.length === 0) lines.push('• (маҳсулот йўқ)');
  lines.push(`Жами: ${fmt.format(order.total || 0)} сўм`);
  const bal = parseInt(String(order.balanceApplied || 0), 10);
  if (bal > 0) lines.push(`Кошелёкдан: ${fmt.format(bal)} сўм`);
  const cashDue = parseInt(String(order.cashDue || 0), 10);
  if (cashDue > 0) lines.push(`Нақд тўлов: ${fmt.format(cashDue)} сўм`);
  const cashPaid = parseInt(String(order.cashPaid || 0), 10);
  if (cashPaid > 0 && cashPaid !== cashDue) {
    lines.push(`Берилган нақд: ${fmt.format(cashPaid)} сўм`);
  }
  if (order.address) lines.push(`📍 ${order.address}`);
  return lines.join('\n');
}

// Янги буюртма — админ FCM + мижоз «Буюртма» чеки
exports.onOrderCreate = functions.firestore
  .document('orders/{orderId}')
  .onCreate(async (snap) => {
    const order = snap.data() || {};
    const orderType = order.type || 'bread';
    const total = order.total || 0;
    const fmt = new Intl.NumberFormat('uz-UZ').format(total);
    const emoji = orderType === 'food' ? 'Ovqat' : 'Non';
    const title = `Yangi ${emoji} buyurtmasi`;
    const body = `${fmt} sum - ${order.userName || order.userPhone || '-'}`;

    const adminSnap = await db.collection('users')
      .where('role', 'in', ['admin', 'superadmin', 'dispatcher'])
      .get();

    const tokens = adminSnap.docs
      .map((d) => d.data().fcmToken)
      .filter((t) => typeof t === 'string' && t.length > 10);

    if (tokens.length > 0) {
      const messages = tokens.map((token) => ({
        token,
        notification: { title, body },
        data: { type: 'new_order', orderId: snap.id, orderType: String(orderType) },
        android: { priority: 'high' },
      }));
      try {
        await admin.messaging().sendEach(messages);
      } catch (e) {
        console.error('onOrderCreate admin FCM xato:', e);
      }
    }

    // Pickup → sotuvchi POS (Tezkor emas, navbat).
    if (String(order.fulfillmentMode || '') === 'pickup') {
      try {
        const sellerSnap = await db.collection('users')
          .where('role', '==', 'seller')
          .get();
        const sellerMsgs = sellerSnap.docs
          .map((d) => d.data().fcmToken)
          .filter((t) => typeof t === 'string' && t.length > 10)
          .map((token) => ({
            token,
            notification: {
              title: '🛒 Yangi olib ketish',
              body: `${fmt} so'm · ${order.userName || order.userPhone || '-'}`,
            },
            data: {
              type: 'seller_pickup',
              screen: 'seller_pos',
              orderId: snap.id,
              orderType: String(orderType),
            },
            android: { priority: 'high' },
          }));
        if (sellerMsgs.length > 0) {
          await admin.messaging().sendEach(sellerMsgs);
        }
      } catch (e) {
        console.error('onOrderCreate seller pickup FCM xato:', e);
      }
    }

    const uid = canonicalUid(order.userPhone || order.phone || '');
    if (uid.length >= 9) {
      const typeLabel = orderType === 'food' ? 'Тайёр овқат' : 'Нон';
      const receipt = formatOrderReceiptBody(order);
      try {
        await db.collection('admin_news').add({
          title: '📋 Буюртма юборилди',
          body: `${receipt}\n${typeLabel}`,
          category: 'order',
          audience: 'user',
          targetUserId: uid,
          source: 'order_placed',
          orderId: snap.id,
          orderStatus: 'new',
          orderType,
          priority: 9,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        const userDoc = await db.collection('users').doc(uid).get();
        const token = userDoc.data()?.fcmToken;
        if (token) {
          await admin.messaging().send({
            token,
            notification: {
              title: '📋 Буюртма юборилди',
              body: `${fmt} сўм · ${typeLabel}`,
            },
            data: { type: 'order', status: 'new', screen: 'news', tab: 'orders' },
            android: { priority: 'high' },
          });
        }
      } catch (e) {
        console.error('onOrderCreate user news xato:', e);
      }
    }

    try {
      const userPhone = String(order.userPhone || order.phone || '');
      const uid9 = userUid(userPhone);
      const uid12 = canonicalUid(userPhone);
      let userRef = db.collection('users').doc(uid12);
      let userSnap = await userRef.get();
      if (!userSnap.exists && uid9 !== uid12) {
        userRef = db.collection('users').doc(uid9);
        userSnap = await userRef.get();
      }
      if (userSnap.exists) {
        const userData = userSnap.data() || {};
        const userAddr = userData.address;
        const patch = {};

        const orderMfy = String(order.mfy || '').trim();
        if (!orderMfy && userAddr && typeof userAddr === 'object') {
          const profileMfy = String(userAddr.mfy || '').trim();
          if (profileMfy) patch.mfy = profileMfy;
        }

        const orderLat = order.lat != null && order.lat !== ''
          ? Number(order.lat)
          : null;
        const orderLng = order.lng != null && order.lng !== ''
          ? Number(order.lng)
          : null;
        const hasOrderCoords = orderLat != null && orderLng != null
          && Number.isFinite(orderLat) && Number.isFinite(orderLng)
          && (Math.abs(orderLat) > 1e-6 || Math.abs(orderLng) > 1e-6);

        if (!hasOrderCoords && userAddr && typeof userAddr === 'object') {
          const lat = userAddr.lat != null ? Number(userAddr.lat) : null;
          const lng = userAddr.lng != null ? Number(userAddr.lng) : null;
          if (
            lat != null && lng != null &&
            Number.isFinite(lat) && Number.isFinite(lng) &&
            (Math.abs(lat) > 1e-6 || Math.abs(lng) > 1e-6)
          ) {
            patch.lat = lat;
            patch.lng = lng;
          }
        }

        if (Object.keys(patch).length > 0) {
          await snap.ref.update(patch);
        }
      }
    } catch (e) {
      console.error('onOrderCreate denormalize address xato:', e);
    }

    try {
      const acceptMode = await getOrderFlowMode('orderAcceptMode');
      if (acceptMode === 'auto' && String(order.status || 'new') === 'new') {
        await snap.ref.update(buildOrderStatusPatch('accepted'));
      }
    } catch (e) {
      console.error('onOrderCreate auto-accept xato:', e);
    }

    return null;
  });

// Эълон модерацияси — статус ўзгарса муаллифга хабар
// Jobs: authorPhone; Onlayn BOZOR (cheap_product): ownerId
exports.onAdUpdate = functions.firestore
  .document('ads/{adId}')
  .onUpdate(async (change) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    if (before.status === after.status) return;

    const isMarket = String(after.type || '') === 'cheap_product';

    // Авто: pending → active (янги эълон / қайта модерация).
    if (
      isMarket
      && after.status === 'pending'
      && before.status !== 'pending'
      && (await isMarketAutoApproveEnabled())
    ) {
      await change.after.ref.update({
        status: 'active',
        publishedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: marketActiveExpiresAt(),
        moderatedAt: admin.firestore.FieldValue.serverTimestamp(),
        moderatedBy: 'auto',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return null;
    }

    const uid = digits(after.authorPhone || after.ownerId || '');
    if (uid.length < 9) return;

    const preview = String(after.title || after.text || '').trim().slice(0, 120);
    let title = '';
    let body = preview;
    let dataType = 'ad_moderation';
    let screen = isMarket ? 'my_ads' : 'jobs';

    switch (after.status) {
      case 'active':
        title = isMarket
          ? '📢 Бозор эълонингиз жойлаштирилди'
          : '📢 Эълонингиз e\'lon qilindi';
        body = preview
          || (isMarket
            ? 'Онлайн бозорда кўринади'
            : 'ИШ ЭЪЛОН бўлимида кўринади');
        dataType = isMarket ? 'market_ad_published' : 'ad_published';
        break;
      case 'blocked':
        title = '⛔ Эълон блокланди';
        body = preview || 'Админ билан боғланинг';
        break;
      case 'completed':
        title = '✅ Эълон yakunlandi';
        body = preview || '';
        break;
      case 'inactive': {
        if (!isMarket) return;
        const moderatedChanged =
          String(before.moderatedAt || '') !== String(after.moderatedAt || '');
        // Owner hide — jim; admin reject/hide — хабар.
        if (before.status === 'pending') {
          title = '⛔ Бозор эълони қабул қилинмади';
        } else if (before.status === 'active' && moderatedChanged) {
          title = '🙈 Бозор эълони яширилди';
        } else {
          return;
        }
        body = preview || (after.adminNote || 'Менинг эълонларимда кўринг');
        dataType = 'market_ad_moderation';
        break;
      }
      case 'pending':
        return;
      default:
        return;
    }

    await notifyUserInApp({
      userId: uid,
      title,
      body,
      category: 'info',
      source: 'ad_moderation',
      dataType,
      screen,
      extraData: { adId: change.after.id, status: after.status },
    });
    return null;
  });

// Сотиш таклифи — админ кўрилди
exports.onSellSubmissionUpdate = functions.firestore
  .document('sell_submissions/{submissionId}')
  .onUpdate(async (change) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    function sellOfferSummary(items) {
      const list = Array.isArray(items) ? items : [];
      if (list.length === 0) return 'Yangi sotish taklifi';
      const first = list[0] || {};
      const name = String(first.productName || first.name || 'Mahsulot').trim();
      if (list.length === 1) return name;
      return `${name} va yana ${list.length - 1} ta mahsulot`;
    }

    async function notifySellForward() {
      const fwdBefore = String(before.forwardAudience || '');
      const fwdAfter = String(after.forwardAudience || '');
      if (!fwdAfter || fwdBefore === fwdAfter) return;

      const title = '🛒 Yangi sotish taklifi';
      const body = sellOfferSummary(after.items);
      const submissionId = change.after.id;

      if (fwdAfter === 'all') {
        await db.collection('admin_news').add({
          title,
          body,
          category: 'info',
          audience: 'all',
          source: 'sell_offer_forward',
          priority: 6,
          submissionId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      if (fwdAfter === 'selected') {
        const ids = Array.isArray(after.visibleToUserIds) ? after.visibleToUserIds : [];
        const seen = new Set();
        for (const raw of ids) {
          const uid = digits(raw);
          if (uid.length < 9 || seen.has(uid)) continue;
          seen.add(uid);
          await notifyUserInApp({
            userId: uid,
            title,
            body,
            category: 'info',
            source: 'sell_offer_forward',
            dataType: 'sell_offer',
            screen: 'sell',
            tab: 'forwarded',
            extraData: { submissionId },
            extraNews: { submissionId },
          });
        }
      }
    }

    if (before.status !== after.status && after.status === 'reviewed') {
      const uid = digits(after.userId || after.userPhone || '');
      if (uid.length >= 9) {
        const count = Array.isArray(after.items) ? after.items.length : 0;
        await notifyUserInApp({
          userId: uid,
          title: '📋 Сотиш таклифингиз кўрилди',
          body: `${count} ta mahsulot. Operator tez orada bog\'lanadi.`,
          category: 'info',
          source: 'sell_offer',
          dataType: 'sell_offer',
          screen: 'sell',
          extraData: { submissionId: change.after.id },
        });
      }
    }

    await notifySellForward();
    return null;
  });

// Туғилган кун / қурилма сўрови — тасдиқ ёки рад
exports.onBirthDateRequestUpdate = functions.firestore
  .document('birthdate_change_requests/{requestId}')
  .onUpdate(async (change) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    if (before.status === after.status) return;
    if (after.status !== 'approved' && after.status !== 'rejected') return;

    const uid = digits(after.userId || '');
    if (uid.length < 9) return;

    const approved = after.status === 'approved';
    await notifyUserInApp({
      userId: uid,
      title: approved
        ? '✅ Туғилган кун тасдиқланди'
        : '❌ Туғилган кун сўрови рад этилди',
      body: approved
        ? String(after.requestedBirthDate || '')
        : 'Админ билан чат орқали аниқлашинг',
      category: 'info',
      source: 'identity_request',
      dataType: 'identity',
      screen: 'news',
      tab: 'general',
    });
    return null;
  });

exports.onDeviceChangeRequestUpdate = functions.firestore
  .document('device_change_requests/{requestId}')
  .onUpdate(async (change) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    if (before.status === after.status) return;
    if (after.status !== 'approved' && after.status !== 'rejected') return;

    const uid = digits(after.requestedUserId || after.requestedPhone || '');
    if (uid.length < 9) return;

    const approved = after.status === 'approved';
    await notifyUserInApp({
      userId: uid,
      title: approved
        ? '✅ Қурилма тасдиқланди'
        : '❌ Қурилма сўрови рад этилди',
      body: approved
        ? 'Энди бу телефон билан кириш mumkin'
        : 'Админ билан чат орқали аниқлашинг',
      category: 'info',
      source: 'identity_request',
      dataType: 'identity',
      screen: 'news',
      tab: 'general',
    });
    return null;
  });

// ─── Yangi yetkazib berish reysi → kuryer(ga) push ───────────────────────────
exports.onDeliveryRouteCreate = functions.firestore
  .document('delivery_routes/{routeId}')
  .onCreate(async (snap) => {
    const route = snap.data() || {};
    const courierId = String(route.courierId || '');
    const ordersCount = (route.orders || route.orderIds || []).length;

    if (!courierId) {
      const onlineSnap = await db.collection('couriers')
        .where('isOnline', '==', true)
        .get();
      const tokens = onlineSnap.docs
        .map((d) => d.data().fcmToken)
        .filter((t) => typeof t === 'string' && t.length > 10);

      if (tokens.length === 0) return null;
      const messages = tokens.map((token) => ({
        token,
        notification: {
          title: '📦 Yangi yetkazib berish reysi',
          body: `${ordersCount} ta buyurtma tayyor`,
        },
        data: { type: 'new_route', routeId: snap.id },
        android: { priority: 'high' },
      }));
      try {
        await admin.messaging().sendEach(messages);
      } catch (_) {}
      return null;
    }

    const courierDoc = await db.collection('couriers').doc(courierId).get();
    const token = courierDoc.data()?.fcmToken;
    if (!token) return null;

    try {
      await admin.messaging().send({
        token,
        notification: {
          title: '📦 Sizga reys tayinlandi',
          body: `${ordersCount} ta buyurtma yetkazish kerak`,
        },
        data: { type: 'assigned_route', routeId: snap.id },
        android: { priority: 'high' },
      });
    } catch (_) {}
    return null;
  });

// Kuryer keyinroq tayinlanganda notification (onUpdate trigger)
exports.onDeliveryRouteAssign = functions.firestore
  .document('delivery_routes/{routeId}')
  .onUpdate(async (change) => {
    const before = change.before.data() || {};
    const after  = change.after.data()  || {};

    const oldCourier = String(before.courierId || '');
    const newCourier = String(after.courierId  || '');
    if (!newCourier || newCourier === oldCourier) return null;

    const ordersCount = (after.orders || after.orderIds || []).length;

    const courierDoc = await db.collection('couriers')
        .doc(newCourier).get();
    const token = courierDoc.data()?.fcmToken;
    if (!token) return null;

    try {
      await admin.messaging().send({
        token,
        notification: {
          title: '📦 Sizga reys tayinlandi',
          body: `${ordersCount} ta buyurtma yetkazish kerak`,
        },
        data: { type: 'assigned_route', routeId: change.after.id },
        android: { priority: 'high' },
      });
    } catch (_) {}
    return null;
  });

// ─── Marshrut pending trip → haydovchiga high-priority FCM ───────────────────
exports.onMarshrutTripCreate = functions.firestore
  .document('trips/{tripId}')
  .onCreate(async (snap) => {
    const trip = snap.data() || {};
    if (trip.taxiType !== 'marshrut') return null;
    if (trip.status !== 'pending') return null;

    const driverId = digits(trip.targetDriverId || trip.driverId || '');
    if (!driverId) return null;

    const [userDoc, driverDoc] = await Promise.all([
      db.collection('users').doc(driverId).get(),
      db.collection('drivers').doc(driverId).get(),
    ]);
    const token = userDoc.data()?.fcmToken || driverDoc.data()?.fcmToken || '';
    if (!token) {
      console.warn('onMarshrutTripCreate: driver token topilmadi', driverId);
      return null;
    }

    const pickup = trip.pickupMfy || trip.pickupAddr || 'Йўловчи';
    const dropoff = trip.dropoffMfy || trip.toAddr || 'Манзил';
    const phone = trip.userPhone || '';
    const timeout = Number(trip.offerTimeoutSeconds || 0);
    const title = '🚐 Янги маршрут сўрови';
    const body = `${pickup} → ${dropoff}${phone ? ' • ' + phone : ''}`;

    try {
      await admin.messaging().send({
        token,
        notification: { title, body },
        data: {
          type: 'marshrut_request',
          tripId: snap.id,
          pickupMfy: String(pickup),
          dropoffMfy: String(dropoff),
          userPhone: String(phone),
          offerTimeoutSeconds: String(timeout),
        },
        android: {
          priority: 'high',
          ttl: 30 * 1000,
          notification: {
            channelId: 'incoming_ride',
            sound: 'default',
            priority: 'max',
            visibility: 'public',
            notificationCount: 1,
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              category: 'MARSHRUT_REQUEST',
            },
          },
        },
      });
    } catch (e) {
      console.error('onMarshrutTripCreate FCM xato:', e);
    }
    return null;
  });

// Такси статуси ўзгарганда
exports.onTripUpdate = functions.firestore
  .document('trips/{tripId}')
  .onUpdate(async (change) => {
    const before = change.before.data();
    const after  = change.after.data();
    const tripId = change.after.id;
    const statusChanged = before.status !== after.status;

    // Local taxi: passenger selected a driver — notify driver (FCM).
    const prevTarget = String(before.targetDriverId || '');
    const newTarget = String(after.targetDriverId || '');
    const taxiType = after.taxiType || '';
    const isLocal = taxiType === 'local' || taxiType === 'alone';
    if (
      newTarget &&
      newTarget !== prevTarget &&
      after.status === 'searching' &&
      isLocal
    ) {
      const driverSnap = await db.collection('drivers').doc(newTarget).get();
      const userSnap = await db.collection('users').doc(newTarget).get();
      const fcmToken =
        driverSnap.data()?.fcmToken || userSnap.data()?.fcmToken || '';
      if (fcmToken) {
        const fromAddr = after.fromAddr || '';
        const toAddr = after.toAddr || '';
        try {
          await admin.messaging().send({
            token: fcmToken,
            notification: {
              title: 'Янги буюртма!',
              body: toAddr ? `${fromAddr} → ${toAddr}` : fromAddr,
            },
            data: {
              type: 'local_trip_request',
              tripId: tripId,
              screen: 'local_trip_request',
            },
            android: { priority: 'high' },
          });
        } catch (e) {
          console.warn('local_trip_request FCM xato:', newTarget, e);
        }
      }
    }

    if (!statusChanged) return;

    if (after.status === 'cancelled' && (after.taxiType || '') === 'marshrut') {
      const cancelledBy = String(after.cancelledBy || '');
      if (
        before.status === 'accepted' &&
        (cancelledBy === 'passenger' || cancelledBy === 'user')
      ) {
        const userPhone = digits(after.userPhone || '');
        if (userPhone.length >= 9 && after.marshrutBlockCounted !== true) {
          await applyMarshhrutCancelBlock(userPhone);
        }
      }
    }

    let localCancelFb = after.localCancelFeedback || null;

    if (
      after.status === 'cancelled' &&
      (after.taxiType === 'local' || after.taxiType === 'alone') &&
      (after.cancelledBy === 'passenger' || after.cancelledBy === 'user')
    ) {
      const localDriverId = String(
          after.acceptedDriverId || after.driverId || '');
      if (localDriverId) {
        try {
          await db.collection('drivers').doc(localDriverId).update({
            isBusy: false,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (e) {
          console.error('release driver isBusy failed:', e);
        }
      }

      // Faqat qabuldan keyingi bekor — qidiruv bekorida blok yo'q.
      // Block count + trip.localTaxiBlockCounted bitta txn (TOCTOU yo'q).
      if (
        before.status === 'accepted' &&
        after.localTaxiBlockCounted !== true
      ) {
        const userPhone = digits(after.userPhone || '');
        if (userPhone.length >= 9) {
          try {
            const blockResult = await applyLocalTaxiCancelBlock(userPhone, {
              tripRef: change.after.ref,
            });
            localCancelFb = {
              level: blockResult.level || 'none',
              cancelCount: blockResult.cancelCount || 0,
              remaining: blockResult.remaining != null
                  ? blockResult.remaining
                  : null,
              blockMinutes: blockResult.blockMinutes != null
                  ? blockResult.blockMinutes
                  : null,
            };
          } catch (e) {
            console.error('applyLocalTaxiCancelBlock failed:', e);
          }
        }
      }
    }

    const uid   = (after.userPhone || '').replace(/[^\d]/g, '');
    const user  = await admin.firestore().collection('users').doc(uid).get();
    const token = user.data()?.fcmToken;

    let title = '', body = '';
    switch (after.status) {
      case 'accepted':
        title = '🚕 Ҳайдовчи топилди!';
        body  = `${after.acceptedDriverName || ''} • ${after.acceptedDriverCar || ''}`;
        break;
      case 'completed':
        title = '✅ Сафар якунланди!';
        body  = after.fare
          ? `Йўлкира: ${after.fare} сўм`
          : 'Яхши сафар бўлди!';
        break;
      case 'cancelled':
        if (after.cancelReason === 'no_room' && after.notifyPassengerReroute) {
          title = 'Жой қолмаган';
          body = 'Сиз учун бошқа ҳайдовчи қидирилмоқда';
          break;
        }
        if (after.cancelledBy === 'driver') return null;
        {
          const fb = localCancelFb || {};
          if (fb.level === 'block') {
            title = '⛔ Чақирув вақтинча ёпилди';
            body = `Қабулдан кейин ${fb.cancelCount || 5} марта бекор.`
                + ` Маҳаллий такси ${fb.blockMinutes || 15} дақиқага чекланди.`;
          } else if (fb.level === 'hard') {
            title = '🚫 Охирги огоҳлантириш';
            body = `Қабулдан кейин ${fb.cancelCount} марта бекор қилдингиз.`
                + ` Яна 1 марта бекор қилсангиз`
                + ` ${Math.round(LOCAL_CANCEL_BLOCK_MS / 60000)} дақиқа блок.`;
          } else if (fb.level === 'soft') {
            title = '⚠️ Эслатма';
            body = `Қабулдан кейин ${fb.cancelCount} марта бекор.`
                + ` Яна ${fb.remaining != null ? fb.remaining : 2} мартадан`
                + ` кейин чақирув вақтинча ёпилади.`;
          } else {
            title = '❌ Сафар бекор қилинди';
            body  = 'Яна уриниб кўринг';
          }
        }
        break;
      default: return;
    }

    const chatText = `${title}\n${body}`.trim();
    await appendSystemSupportChatMessage(uid, chatText);

    const fcmTitle = `📢 Админ: ${title}`;
    const fcmBody = body || 'Хабар';

    if (token) {
      const taxiType = after.taxiType || '';
      const isMarshrut = taxiType === 'marshrut';
      const isLocal = taxiType === 'local' || taxiType === 'alone';
      const dataPayload = after.status === 'accepted'
        ? {
            type: isMarshrut
              ? 'marshrut_accepted'
              : (isLocal ? 'local_trip_accepted' : 'trip'),
            status: 'accepted',
            screen: isMarshrut
              ? 'marshrut_accepted'
              : (isLocal ? 'local_taxi' : 'marshrut'),
            tripId: tripId,
          }
        : { type: 'trip', status: after.status, screen: 'marshrut' };

      await admin.messaging().send({
        token,
        notification: { title: fcmTitle, body: fcmBody },
        data: dataPayload,
        android: { priority: 'high' },
      });
    }

    // Mahalliy yo'lkira: faqat destination + Directions bilan lock qilinadi
    // (client LocalTripFareLockService). Accept paytida soxta estimate yozilmaydi.
  });

// Админ/мижоз чат хабарлари учун push
exports.onSupportChatMessageCreate = functions.firestore
  .document('support_chats/{chatId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    if (data.systemOrder) return;
    const fromAdmin = !!data.fromAdmin;
    const chatId = context.params.chatId;
    const userUid = digits(chatId);
    if (!userUid) return;

    if (fromAdmin && userUid) {
      await db.collection('users').doc(userUid).set({
        homeBadgePersonal: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true }).catch((err) => {
        console.error('support chat homeBadgePersonal:', err.message || err);
      });
    }

    // Ҳозирча админ токени users коллекциясида role=admin бўлса шу ердан олинади.
    let targetToken = '';
    if (fromAdmin) {
      const userDoc = await db.collection('users').doc(userUid).get();
      targetToken = userDoc.data()?.fcmToken || '';
    } else {
      const adminSnap = await db.collection('users')
        .where('role', '==', 'admin')
        .limit(1)
        .get();
      if (!adminSnap.empty) {
        targetToken = adminSnap.docs.first.data().fcmToken || '';
      }
    }
    if (!targetToken) return;

    const title = fromAdmin ? '💬 Админдан янги хабар' : '💬 Мижоздан янги хабар';
    const body = String(data.text || '').trim().slice(0, 120) || 'Янги хабар';
    await admin.messaging().send({
      token: targetToken,
      notification: { title, body },
      data: {
        type: 'support_chat',
        chatId: userUid,
      },
      android: { priority: 'high' },
    });
  });

// 1-марта рўйхатдан ўтган мижозларга 3 кун давомида кунлик промо-хабар
exports.sendDailyOnboardingPromo = functions.pubsub
  .schedule('0 10 * * *') // ҳар куни 10:00
  .timeZone('Asia/Tashkent')
  .onRun(async () => {
    const now = new Date();
    const usersSnap = await db.collection('users')
      .limit(500)
      .get();

    const tasks = [];
    for (const doc of usersSnap.docs) {
      const u = doc.data() || {};
      const role = String(u.role || 'user');
      if (role === 'admin' || role === 'driver' || role === 'courier') continue;
      const token = u.fcmToken || '';
      if (!token) continue;

      const createdAt = u.createdAt;
      if (!createdAt || !createdAt.toDate) continue;
      const createdDate = createdAt.toDate();
      const dayDiff = Math.floor((now - createdDate) / (24 * 60 * 60 * 1000));
      if (dayDiff < 0 || dayDiff > 2) continue; // фақат дастлабки 3 кун

      const lastPromoDay = u.lastPromoDay || '';
      const dayKey = `${now.getFullYear()}-${now.getMonth() + 1}-${now.getDate()}`;
      if (lastPromoDay === dayKey) continue; // кунига 1 марта

      const useProbTheoryMessage = Math.random() < 0.45;
      const body = useProbTheoryMessage
        ? 'Эҳтимолий фойдали алмашинув: гўшт ўрнига сут, гуруч, тухум ва бошқа маҳсулотлар билан ҳисоб-китоб қилиш мумкин.'
        : 'Бизда сут, қатиқ, тухум, гуруч ва бошқа қишлоқ хўжалик маҳсулотлари билан ҳам ҳисоб-китоб қилиш имкони бор.';

      tasks.push(
        admin.messaging().send({
          token,
          notification: {
            title: '📢 Янги таклиф',
            body,
          },
          data: {
            type: 'daily_promo',
            day: String(dayDiff + 1),
          },
          android: { priority: 'high' },
        }).then(() => db.collection('users').doc(doc.id).set({
          lastPromoDay: dayKey,
          promoSentCount: admin.firestore.FieldValue.increment(1),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true }))
      );
    }

    await Promise.all(tasks);
    return null;
  });

// ══════════════════════════════════════
// BALANCE (ҳисоб-китоб / кошелёк) — callable
// ══════════════════════════════════════

async function assertAdmin(operatorPhone, context) {
  if (!context || !context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated', 'Login required');
  }
  const tokenPhone = String(
    context.auth.token.phone_number || '').replace(/\D/g, '');
  const opDigits = digits(operatorPhone);
  const phoneForLookup = opDigits || tokenPhone;
  if (!phoneForLookup) {
    throw new functions.https.HttpsError(
      'invalid-argument', 'operatorPhone');
  }

  if (opDigits && tokenPhone) {
    const canonOp = canonicalUid(opDigits);
    const canonTok = canonicalUid(tokenPhone);
    if (canonOp !== canonTok && opDigits !== tokenPhone) {
      throw new functions.https.HttpsError(
        'permission-denied', 'Phone mismatch');
    }
  }

  const found = await findUserDocByPhone(phoneForLookup);
  if (!found) {
    throw new functions.https.HttpsError(
      'permission-denied', 'User not found');
  }
  const role = (found.snap.data() || {}).role || 'user';
  if (role !== 'admin' && role !== 'superadmin'
      && role !== 'dispatcher') {
    throw new functions.https.HttpsError(
      'permission-denied', 'Admin only');
  }
  return found.docId;
}

async function assertAdminOrDriver(operatorPhone, context) {
  if (!context || !context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated', 'Login required');
  }
  const uid = digits(operatorPhone);
  if (!uid) throw new functions.https.HttpsError(
    'invalid-argument', 'operatorPhone');

  const tokenPhone = String(
    context.auth.token.phone_number || '').replace(/\D/g, '');
  const tokenUid = String(context.auth.uid || '');
  if (tokenPhone !== uid && tokenUid !== uid) {
    throw new functions.https.HttpsError(
      'permission-denied', 'Phone mismatch');
  }

  return db.collection('users').doc(uid).get().then((doc) => {
    const role = (doc.data() || {}).role || 'user';
    if (role !== 'admin' && role !== 'driver') {
      throw new functions.https.HttpsError('permission-denied', 'Not allowed');
    }
    return uid;
  });
}

function userUid(phone) {
  const uid = digits(phone);
  if (!uid || uid.length < 9) {
    throw new functions.https.HttpsError('invalid-argument', 'userPhone');
  }
  return uid;
}

/**
 * Hisobot denormalizatsiyasi: user hujjatidan regionId/districtId/serviceAreaId
 * ni order/trip hujjatiga bosish uchun (faqat boʻsh emas maydonlar).
 * Xizmat mavjudligiga taʼsir qilmaydi — faqat hisobot/dashboard uchun.
 */
function geoReportStamp(userData) {
  const u = userData || {};
  const out = {};
  const region = String(u.regionId || '').trim();
  const district = String(u.districtId || '').trim();
  const area = String(u.serviceAreaId || '').trim();
  if (region) out.regionId = region;
  if (district) out.districtId = district;
  if (area) out.serviceAreaId = area;
  return out;
}

/** Нақд қайтим → Balance (credit) */
exports.creditChange = functions.https.onCall(async (data, context) => {
  const operatorUid = await requireCallerRoles(
    context,
    ['admin', 'superadmin', 'dispatcher', 'driver'],
    'Operator role required',
  );

  const userPhone = String(data.userPhone || '');
  const orderTotal = parseInt(String(data.orderTotal ?? 0), 10);
  const cashPaid = parseInt(String(data.cashPaid ?? 0), 10);
  const refType = String(data.refType || 'order');
  const refId = String(data.refId || '');
  const module = String(data.module || 'bread');
  const idempotencyKey = String(data.idempotencyKey || '').trim();

  if (!idempotencyKey) {
    throw new functions.https.HttpsError('invalid-argument', 'idempotencyKey required');
  }

  const uid = userUid(userPhone);
  const delta = cashPaid - orderTotal;
  const idemRef = db.collection('wallet_idempotency').doc(idempotencyKey);

  const existing = await idemRef.get();
  if (existing.exists) {
    return existing.data().result || { ok: true, duplicate: true };
  }

  if (delta <= 0) {
    const result = { ok: true, credited: 0, delta };
    await idemRef.set({
      type: 'creditChange',
      result,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return result;
  }

  const ledgerId = db.collection('users').doc(uid).collection('wallet_ledger').doc().id;

  await db.runTransaction(async (t) => {
    const idemSnap = await t.get(idemRef);
    if (idemSnap.exists) return;

    const userRef = db.collection('users').doc(uid);
    const userSnap = await t.get(userRef);
    const prev = (userSnap.data() && userSnap.data().bonusBalance) || 0;
    const next = prev + delta;

    // Ledger ko'zgusi (READ fazasi) — yozuvlardan oldin.
    const bonusCtx = await settlementLedger.prepareBonusInTx(t, db, uid, {
      idempotencyKey,
    });

    t.set(userRef, {
      bonusBalance: next,
      balanceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    t.set(userRef.collection('wallet_ledger').doc(ledgerId), {
      type: 'change_accrued',
      amount: delta,
      module,
      refType,
      refId,
      meta: { orderTotal, cashPaid },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: operatorUid,
    });

    // Ledger ko'zgusi (WRITE fazasi) — Dr admin_clearing / Cr passenger_credit.
    settlementLedger.commitBonusInTx(t, bonusCtx, {
      delta,
      kind: 'change_accrued',
      refType,
      refId,
      meta: { module, orderTotal, cashPaid },
      postedBy: operatorUid,
      postedRole: 'operator',
    });

    t.set(idemRef, {
      type: 'creditChange',
      result: { ok: true, credited: delta, ledgerId },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { ok: true, credited: delta };
});

/** Сут, тухум, гуруч, гўшт, қатиқ … таъминотчи кредити (админ) — сумма аниқ. */
exports.creditSupplier = functions.https.onCall(async (data, context) => {
  const adminUid = await requireCallerRoles(
    context,
    ['admin', 'superadmin'],
    'Admin role required',
  );

  const userPhone = String(data.userPhone || '');
  const amount = parseInt(String(data.amount ?? 0), 10);
  const note = String(data.note || '');
  const dateKey = String(data.dateKey || '').trim();
  const module = String(data.module || 'milk').trim() || 'milk';

  if (!dateKey) {
    throw new functions.https.HttpsError('invalid-argument', 'dateKey required (YYYY-M-D)');
  }
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'amount must be positive');
  }

  const uid = userUid(userPhone);
  const safeMod = module.replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 40) || 'milk';
  const idempotencyKey = `supplier_${uid}_${dateKey}_${safeMod}`;
  const idemRef = db.collection('wallet_idempotency').doc(idempotencyKey);

  const existing = await idemRef.get();
  if (existing.exists) {
    return existing.data().result || { ok: true, duplicate: true };
  }

  const ledgerId = db.collection('users').doc(uid).collection('wallet_ledger').doc().id;

  await db.runTransaction(async (t) => {
    const idemSnap = await t.get(idemRef);
    if (idemSnap.exists) return;

    const userRef = db.collection('users').doc(uid);
    const userSnap = await t.get(userRef);
    const prev = (userSnap.data() && userSnap.data().bonusBalance) || 0;
    const next = prev + amount;

    // Ledger ko'zgusi (READ fazasi) — V2: supplier_payable funding.
    const bonusCtx = await settlementLedger.prepareBonusInTx(t, db, uid, {
      idempotencyKey,
      fundingAccount: settlementLedger.supplierPayableAccount(uid),
    });

    t.set(userRef, {
      bonusBalance: next,
      balanceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    t.set(userRef.collection('wallet_ledger').doc(ledgerId), {
      type: 'supplier_credit',
      amount,
      module: safeMod,
      refType: 'supplier_day',
      refId: dateKey,
      meta: { note, productKind: module },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: adminUid,
    });

    // Ledger ko'zgusi (WRITE fazasi) — Dr admin_clearing / Cr passenger_credit.
    settlementLedger.commitBonusInTx(t, bonusCtx, {
      delta: amount,
      kind: 'supplier_credit',
      refType: 'supplier_day',
      refId: dateKey,
      meta: { module: safeMod, note },
      postedBy: adminUid,
      postedRole: 'admin',
    });

    t.set(idemRef, {
      type: 'creditSupplier',
      result: { ok: true, credited: amount, ledgerId },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { ok: true, credited: amount };
});

/** Буюртма / хизмат учун балансдан ечиш */
exports.debitForOrder = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }
  const callerUid = canonicalUid(callerPhone(context));
  const targetUid = userUid(String(data.userPhone || ''));
  const callerDoc = await db.collection('users').doc(callerUid).get();
  const callerRole = (callerDoc.data() || {}).role || 'user';
  const callerIsAdmin = ['admin', 'superadmin', 'dispatcher'].includes(callerRole);
  if (callerUid !== targetUid && !callerIsAdmin) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Cannot debit another user',
    );
  }

  const userPhone = String(data.userPhone || '');
  const amount = parseInt(String(data.amount ?? 0), 10);
  const refType = String(data.refType || 'order');
  const refId = String(data.refId || '');
  const module = String(data.module || 'bread');
  const idempotencyKey = String(data.idempotencyKey || '').trim();

  if (!idempotencyKey) {
    throw new functions.https.HttpsError('invalid-argument', 'idempotencyKey required');
  }
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'amount must be positive');
  }

  const uid = userUid(userPhone);
  const idemRef = db.collection('wallet_idempotency').doc(idempotencyKey);

  const existing = await idemRef.get();
  if (existing.exists) {
    return existing.data().result || { ok: true, duplicate: true };
  }

  const ledgerId = db.collection('users').doc(uid).collection('wallet_ledger').doc().id;

  await db.runTransaction(async (t) => {
    const idemSnap = await t.get(idemRef);
    if (idemSnap.exists) return;

    const userRef = db.collection('users').doc(uid);
    const userSnap = await t.get(userRef);
    const prev = (userSnap.data() && userSnap.data().bonusBalance) || 0;
    if (prev < amount) {
      throw new functions.https.HttpsError('failed-precondition', 'insufficient_balance');
    }
    const next = prev - amount;

    // Ledger ko'zgusi (READ fazasi).
    const bonusCtx = await settlementLedger.prepareBonusInTx(t, db, uid, {
      idempotencyKey,
    });

    t.set(userRef, {
      bonusBalance: next,
      balanceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    t.set(userRef.collection('wallet_ledger').doc(ledgerId), {
      type: 'purchase_debit',
      amount: -amount,
      module,
      refType,
      refId,
      meta: {},
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: 'client',
    });

    // Ledger ko'zgusi (WRITE fazasi) — Dr passenger_credit / Cr admin_clearing.
    settlementLedger.commitBonusInTx(t, bonusCtx, {
      delta: -amount,
      kind: 'purchase_debit',
      refType,
      refId,
      meta: { module },
      postedBy: callerUid || 'client',
      postedRole: 'client',
    });

    t.set(idemRef, {
      type: 'debitForOrder',
      result: { ok: true, debited: amount, ledgerId },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { ok: true, debited: amount };
});

/** Кошелёк (аниқ сумма) + омбор + order + ledger + нақд қайтим — битта транзакция. */
function maxWalletDebit(balance, orderTotal) {
  const b = Number(balance) || 0;
  const t = Number(orderTotal) || 0;
  if (t <= 0 || b <= 0) return 0;
  return Math.min(b, t);
}

function inventoryCollectionForDecrementKind(kind) {
  const k = String(kind || '').toLowerCase();
  if (k === 'bread') return 'bread_products';
  if (k === 'extra') return 'extra_products';
  if (k === 'food') return 'food_inventory';
  if (k === 'platform') return 'platform_products';
  throw new functions.https.HttpsError('invalid-argument', 'bad inventory kind');
}

/** Sotuvchi POS: narxni katalogdan olish (client unitPrice ishonchsiz). */
async function resolveSellerCatalogLine(kind, inventoryId) {
  const id = String(inventoryId || '').trim();
  if (!id) {
    throw new functions.https.HttpsError('invalid-argument', 'inventoryId kerak');
  }
  if (kind === 'food') {
    const snap = await db.collection('food_catalog').doc(id).get();
    if (!snap.exists) {
      throw new functions.https.HttpsError('not-found', `Taom topilmadi: ${id}`);
    }
    const d = snap.data() || {};
    const unitPrice = Math.trunc(Number(d.price || 0));
    if (!Number.isInteger(unitPrice) || unitPrice <= 0) {
      throw new functions.https.HttpsError('failed-precondition', `Narx yo'q: ${id}`);
    }
    return {
      unitPrice,
      name: String(d.name || id).trim() || id,
      emoji: String(d.emoji || ''),
      unit: String(d.unit || 'dona'),
    };
  }
  if (kind === 'bread') {
    const snap = await db.collection('bread_products').doc(id).get();
    if (!snap.exists) {
      throw new functions.https.HttpsError('not-found', `Non topilmadi: ${id}`);
    }
    const d = snap.data() || {};
    const typeRaw = String(d.type || 'tayyor').toLowerCase();
    const isReady = typeRaw === 'tayyor' || typeRaw === 'тайёр' || typeRaw === 'ready';
    const isYopish = typeRaw === 'yopish' || typeRaw === 'ёпиш';
    // POS: tayyor + ёпиш қолдиқлари (той — yo'q).
    if (!isReady && !isYopish) {
      throw new functions.https.HttpsError(
          'failed-precondition',
          'POS faqat tayyor yoki yopish non',
      );
    }
    if (isYopish) {
      const total = Number(d.totalStock) || 0;
      const sold = Number(d.soldToday) || 0;
      if (total <= 0 || total - sold <= 0) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            'Yopish qoldiq zahirasi yo\'q',
        );
      }
    }
    const unitPrice = Math.trunc(Number(d.price || 0));
    if (!Number.isInteger(unitPrice) || unitPrice <= 0) {
      throw new functions.https.HttpsError('failed-precondition', `Narx yo'q: ${id}`);
    }
    return {
      unitPrice,
      name: String(d.name || id).trim() || id,
      emoji: String(d.emoji || '🫓'),
      unit: String(d.unit || 'dona'),
    };
  }
  throw new functions.https.HttpsError('invalid-argument', 'bad item kind');
}

/** To'lanmagan buyurtmalardan soldToday rezervini yig'ish. */
async function aggregateOpenOrderStockReservations() {
  const reserved = {};
  const snap = await db.collection('orders')
      .where('paymentStatus', '==', 'unpaid')
      .limit(500)
      .get();
  for (const doc of snap.docs) {
    const o = doc.data() || {};
    const fs = String(o.fulfillmentStatus || o.status || '').toLowerCase();
    if (['cancelled', 'canceled', 'completed', 'delivered', 'rejected'].includes(fs)) {
      continue;
    }
    const decs = Array.isArray(o.inventoryDecrements) ? o.inventoryDecrements : [];
    if (decs.length > 0) {
      for (let i = 0; i < decs.length; i += 1) {
        const c = decs[i] || {};
        const id = String(c.id || '').trim();
        const qty = Number(c.qty);
        if (!id || !Number.isFinite(qty) || qty <= 0) continue;
        let col;
        try {
          col = inventoryCollectionForDecrementKind(String(c.kind || ''));
        } catch (_) {
          continue;
        }
        const key = `${col}__${id}`;
        reserved[key] = (reserved[key] || 0) + qty;
      }
      continue;
    }
    // Legacy: food items inventoryId
    if (String(o.type || '') === 'food') {
      const items = Array.isArray(o.items) ? o.items : [];
      for (let i = 0; i < items.length; i += 1) {
        const it = items[i] || {};
        const id = String(it.inventoryId || '').trim();
        const qty = Number(it.qty || it.count || 0);
        if (!id || !(qty > 0)) continue;
        const key = `food_inventory__${id}`;
        reserved[key] = (reserved[key] || 0) + qty;
      }
    }
  }
  return reserved;
}

async function applyStockReservations(reserved) {
  const keys = Object.keys(reserved || {});
  if (keys.length === 0) return 0;
  let batch = db.batch();
  let writes = 0;
  let count = 0;
  for (let i = 0; i < keys.length; i += 1) {
    const key = keys[i];
    const qty = Number(reserved[key]) || 0;
    if (qty <= 0) continue;
    const sep = key.indexOf('__');
    if (sep < 1) continue;
    const col = key.slice(0, sep);
    const id = key.slice(sep + 2);
    batch.set(
        db.collection(col).doc(id),
        { soldToday: qty },
        { merge: true },
    );
    writes += 1;
    count += 1;
    if (writes >= 450) {
      await batch.commit();
      batch = db.batch();
      writes = 0;
    }
  }
  if (writes > 0) await batch.commit();
  return count;
}

/** @deprecated — хавфли (auth/reprice йўқ). Фақат `placeOrderPostPaid`. */
exports.placeOrderWithWallet = functions.https.onCall(async () => {
  throw new functions.https.HttpsError(
    'failed-precondition',
    'Deprecated: use placeOrderPostPaid',
  );
});

// ══════════════════════════════════════
// POST-PAID ORDERS (буюртмада кошелёк ечилмайди)
// ══════════════════════════════════════

function legacyStatusFromFulfillment(fs) {
  if (fs === 'cancelled') return 'rejected';
  if (fs === 'completed') return 'delivered';
  if (fs === 'courier_picked' || fs === 'arrived') return 'in_delivery';
  if (fs === 'confirmed') return 'accepted';
  return 'new';
}

function assertCourierPhone(courierPhone) {
  const uid = digits(courierPhone);
  if (!uid || uid.length < 9) {
    throw new functions.https.HttpsError('invalid-argument', 'courierPhone');
  }
  return uid;
}

/** Kuryer telefoni: `couriers/{uid}` yoki `users/{uid}.role === 'courier'`. */
async function resolveAuthorizedCourierUid(courierPhone) {
  const uid9 = userUid(courierPhone);
  const uid12 = canonicalUid(courierPhone);
  const ids = uid9 === uid12 ? [uid12] : [uid12, uid9];

  for (let i = 0; i < ids.length; i += 1) {
    const uid = ids[i];
    const courierDoc = await db.collection('couriers').doc(uid).get();
    if (courierDoc.exists) return uid;
  }

  for (let i = 0; i < ids.length; i += 1) {
    const uid = ids[i];
    const userDoc = await db.collection('users').doc(uid).get();
    const role = (userDoc.data() || {}).role || '';
    if (userDoc.exists && role === 'courier') return uid;
  }

  throw new functions.https.HttpsError('permission-denied', 'Courier not authorized');
}

async function loadOrderOrThrow(orderId) {
  const id = String(orderId || '').trim();
  if (!id) {
    throw new functions.https.HttpsError('invalid-argument', 'orderId required');
  }
  const snap = await db.collection('orders').doc(id).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'order not found');
  }
  return { ref: snap.ref, data: snap.data() || {}, id };
}

function paymentLinesTotal(lines) {
  let sum = 0;
  for (let i = 0; i < lines.length; i += 1) {
    const a = parseInt(String(lines[i].amount ?? 0), 10);
    if (Number.isFinite(a) && a > 0) sum += a;
  }
  return sum;
}

function resolvePaymentMethod(lines) {
  const kinds = new Set();
  for (let i = 0; i < lines.length; i += 1) {
    kinds.add(String(lines[i].kind || '').toLowerCase());
  }
  if (kinds.size > 1) return 'mixed';
  if (kinds.has('product')) return 'product';
  if (kinds.has('wallet')) return 'wallet';
  if (kinds.has('card')) return 'card';
  return 'cash';
}

/** food_catalog doc — inventoryId `food_N` (seed) ёки legacy. */
async function loadFoodCatalogDoc(inventoryId) {
  const id = String(inventoryId || '').trim();
  if (!id) return null;
  let snap = await db.collection('food_catalog').doc(id).get();
  if (!snap.exists && /^\d+$/.test(id)) {
    snap = await db.collection('food_catalog').doc(`food_${id}`).get();
  }
  if (!snap.exists) return null;
  return { docId: snap.id, data: snap.data() || {} };
}

/**
 * Food буюртма: нарх/ном фақат food_catalog дан (client price ишончсиз).
 * @returns {{ items: object[], total: number, decrements: object[] }}
 */
async function repriceFoodOrderFromCatalog(itemsIn) {
  const raw = Array.isArray(itemsIn) ? itemsIn : [];
  if (raw.length < 1 || raw.length > 40) {
    throw new functions.https.HttpsError('invalid-argument', 'items 1..40');
  }
  const items = [];
  const decrements = [];
  let total = 0;
  for (let i = 0; i < raw.length; i += 1) {
    const it = raw[i] || {};
    const invId = String(it.inventoryId || '').trim();
    const qty = Number(it.qty);
    if (!invId) {
      throw new functions.https.HttpsError(
          'invalid-argument', `items[${i}]: inventoryId required`);
    }
    if (!Number.isFinite(qty) || qty <= 0 || qty > 500) {
      throw new functions.https.HttpsError(
          'invalid-argument', `items[${i}]: bad qty`);
    }
    const cat = await loadFoodCatalogDoc(invId);
    if (!cat) {
      throw new functions.https.HttpsError('not-found', `Taom topilmadi: ${invId}`);
    }
    const unitPrice = Math.trunc(Number(cat.data.price || 0));
    if (!Number.isInteger(unitPrice) || unitPrice <= 0) {
      throw new functions.https.HttpsError(
          'failed-precondition', `Narx yo'q: ${invId}`);
    }
    const lineTotal = Math.round(unitPrice * qty);
    if (!Number.isFinite(lineTotal) || lineTotal <= 0) {
      throw new functions.https.HttpsError('invalid-argument', `items[${i}]: bad total`);
    }
    total += lineTotal;
    const name = String(cat.data.name || invId).trim() || invId;
    const unit = String(cat.data.unit || it.unit || 'кг');
    const emoji = String(cat.data.emoji || it.emoji || '🍽');
    const catalogInv = cat.docId.startsWith('food_') ? cat.docId : invId;
    items.push({
      name,
      emoji,
      price: unitPrice,
      qty,
      unit,
      total: lineTotal,
      inventoryId: catalogInv,
    });
    decrements.push({
      kind: 'food',
      id: catalogInv,
      qty,
      label: name,
    });
  }
  if (total <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'invalid order total');
  }
  return { items, total, decrements };
}

/** Платформа дўкони: нарх `platform_products` дан. */
async function repricePlatformOrderFromCatalog(itemsIn) {
  const raw = Array.isArray(itemsIn) ? itemsIn : [];
  if (raw.length < 1 || raw.length > 40) {
    throw new functions.https.HttpsError('invalid-argument', 'items 1..40');
  }
  const items = [];
  const decrements = [];
  let total = 0;
  for (let i = 0; i < raw.length; i += 1) {
    const it = raw[i] || {};
    const productId = String(it.productId || it.inventoryId || '').trim();
    const qty = Math.trunc(Number(it.qty));
    if (!productId) {
      throw new functions.https.HttpsError(
          'invalid-argument', `items[${i}]: productId required`);
    }
    if (!Number.isFinite(qty) || qty <= 0 || qty > 500) {
      throw new functions.https.HttpsError(
          'invalid-argument', `items[${i}]: bad qty`);
    }
    const snap = await db.collection('platform_products').doc(productId).get();
    if (!snap.exists) {
      throw new functions.https.HttpsError(
          'not-found', `Маҳсулот топилмади: ${productId}`);
    }
    const d = snap.data() || {};
    // Каталогдаги барча маҳсулотлар буюртма қилиниши мумкин (active чекловсиз).
    const unitPrice = Math.trunc(Number(d.price || 0));
    if (!Number.isInteger(unitPrice) || unitPrice <= 0) {
      throw new functions.https.HttpsError(
          'failed-precondition', `Нарх йўқ: ${productId}`);
    }
    const totalStock = Number(d.totalStock) || 0;
    if (totalStock > 0) {
      const sold = Number(d.soldToday) || 0;
      const remaining = totalStock - sold;
      if (remaining + 1e-9 < qty) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            `${d.name || productId}: керак ${qty}, қолди ${remaining}`,
        );
      }
    }
    const lineTotal = Math.round(unitPrice * qty);
    total += lineTotal;
    const name = String(d.name || productId).trim() || productId;
    const unit = String(d.unit || it.unit || 'дона');
    items.push({
      name,
      price: unitPrice,
      qty,
      unit,
      total: lineTotal,
      productId,
      inventoryId: productId,
    });
    decrements.push({
      kind: 'platform',
      id: productId,
      qty,
      label: name,
    });
  }
  if (total <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'invalid order total');
  }
  return { items, total, decrements };
}

function breadTypeNorm(raw) {
  const t = String(raw || 'tayyor').toLowerCase().trim();
  if (t === 'ёпиш' || t === 'yopish') return 'yopish';
  if (t === 'той' || t === 'toy') return 'toy';
  if (t === 'тайёр' || t === 'tayyor' || t === 'ready') return 'tayyor';
  return t;
}

function breadUnitPriceFromDoc(d, prices) {
  const direct = Math.trunc(Number(d.price || 0));
  if (Number.isInteger(direct) && direct > 0) return direct;
  const key = String(d.priceKey || '').trim();
  if (key && prices && prices[key] != null) {
    const fromKey = Math.trunc(Number(prices[key]));
    if (Number.isInteger(fromKey) && fromKey > 0) return fromKey;
  }
  return 0;
}

function breadFlourMilkCost(d, count, prices) {
  const flourG = Number(d.flourG) > 0 ? Number(d.flourG) : 300;
  const ratio = Number(d.milkRatio);
  const milkMl = Number(d.milkMl) > 0
      ? Number(d.milkMl)
      : Math.round((Number.isFinite(ratio) && ratio > 0 ? ratio : 0.575) * flourG);
  const flourPrice = Math.trunc(Number((prices && prices.flour_price) || 8000)) || 8000;
  const milkPrice = Math.trunc(Number((prices && prices.milk_price) || 7000)) || 7000;
  const n = Math.max(1, Math.trunc(count));
  return Math.round((flourG / 1000) * flourPrice * n)
      + Math.round((milkMl / 1000) * milkPrice * n);
}

function breadExtraDiscount(d, qty) {
  if (!(qty > 0) || d.bonusEnabled !== true) return 0;
  const threshold = Math.trunc(Number(d.bonusThreshold || 0));
  const bonusQty = Math.trunc(Number(d.bonusQty || 0));
  const bonusPercent = Math.trunc(Number(d.bonusPercent || 0));
  const price = Math.trunc(Number(d.price || 0));
  if (threshold <= 0 || bonusQty <= 0 || bonusPercent <= 0 || price <= 0) return 0;
  if (qty + 1e-9 < threshold) return 0;
  const discounted = bonusQty > qty ? Math.floor(qty) : bonusQty;
  return Math.round(price * discounted * (bonusPercent / 100));
}

/**
 * Bread буюртма: нарх bread_products + extra_products + settings/prices дан.
 * Client price/total e'tiborsiz. flourMilk faqat 'ours'|'yours' (mijoz tanlovi).
 */
async function repriceBreadOrderFromCatalog(orderBase) {
  const rawItems = Array.isArray(orderBase.items) ? orderBase.items : [];
  const rawExtras = Array.isArray(orderBase.extras) ? orderBase.extras : [];
  if (rawItems.length < 1 && rawExtras.length < 1) {
    throw new functions.https.HttpsError('invalid-argument', 'items or extras required');
  }
  if (rawItems.length > 40 || rawExtras.length > 40) {
    throw new functions.https.HttpsError('invalid-argument', 'too many lines');
  }

  const pricesSnap = await db.collection('settings').doc('prices').get();
  const prices = pricesSnap.exists ? (pricesSnap.data() || {}) : {};
  const saltUnit = Math.trunc(Number(prices.salt_yeast_unit || prices.saltYeastUnit || 50)) || 50;

  const items = [];
  const decrements = [];
  let breadSum = 0;
  let yopishToyCount = 0;
  let cartHadYopish = false;

  for (let i = 0; i < rawItems.length; i += 1) {
    const it = rawItems[i] || {};
    const fid = String(it.firestoreId || it.productId || '').trim();
    const count = Math.trunc(Number(it.count ?? it.qty ?? 0));
    if (!fid) {
      throw new functions.https.HttpsError(
          'invalid-argument', `items[${i}]: firestoreId required`);
    }
    if (!Number.isFinite(count) || count < 1 || count > 200) {
      throw new functions.https.HttpsError(
          'invalid-argument', `items[${i}]: bad count`);
    }
    const snap = await db.collection('bread_products').doc(fid).get();
    if (!snap.exists) {
      throw new functions.https.HttpsError('not-found', `Non topilmadi: ${fid}`);
    }
    const d = snap.data() || {};
    const type = breadTypeNorm(d.type);
    const unitPrice = breadUnitPriceFromDoc(d, prices);
    if (!Number.isInteger(unitPrice) || unitPrice <= 0) {
      throw new functions.https.HttpsError(
          'failed-precondition', `Narx yo'q: ${fid}`);
    }

    const flourMilkRaw = String(it.flourMilk || 'ours').toLowerCase();
    const flourMilk = (type === 'yopish' || type === 'toy')
        ? (flourMilkRaw === 'yours' ? 'yours' : 'ours')
        : 'none';

    const baseLineTotal = unitPrice * count;
    let fmCost = 0;
    if ((type === 'yopish' || type === 'toy') && flourMilk === 'ours') {
      fmCost = breadFlourMilkCost(d, count, prices);
    }
    const lineTotal = baseLineTotal + fmCost;
    breadSum += lineTotal;

    if (type === 'yopish' || type === 'toy') {
      yopishToyCount += count;
    }
    if (type === 'yopish') cartHadYopish = true;

    // Inventory: faqat tayyor (ready) — client bilan bir xil.
    if (type === 'tayyor') {
      decrements.push({
        kind: 'bread',
        id: fid,
        qty: count,
        label: String(d.name || fid).trim() || fid,
      });
    }

    const typeOut = type === 'yopish' ? 'ёпиш' : (type === 'toy' ? 'той' : 'тайёр');
    items.push({
      id: it.id != null ? it.id : fid,
      firestoreId: fid,
      emoji: String(d.emoji || it.emoji || '🫓'),
      name: String(d.name || fid).trim() || fid,
      count,
      type: typeOut,
      flourMilk,
      price: unitPrice,
      baseLineTotal,
      ...(fmCost > 0 ? { flourMilkCost: fmCost } : {}),
      lineTotal,
    });
  }

  const extras = [];
  let extrasSum = 0;
  for (let i = 0; i < rawExtras.length; i += 1) {
    const it = rawExtras[i] || {};
    const fid = String(it.firestoreId || '').trim();
    const qty = Number(it.count ?? it.qty ?? 0);
    if (!fid) {
      throw new functions.https.HttpsError(
          'invalid-argument', `extras[${i}]: firestoreId required`);
    }
    if (!Number.isFinite(qty) || qty <= 0 || qty > 500) {
      throw new functions.https.HttpsError(
          'invalid-argument', `extras[${i}]: bad qty`);
    }
    const snap = await db.collection('extra_products').doc(fid).get();
    if (!snap.exists) {
      throw new functions.https.HttpsError('not-found', `Qo'shimcha topilmadi: ${fid}`);
    }
    const d = snap.data() || {};
    const unitPrice = Math.trunc(Number(d.price || 0));
    if (!Number.isInteger(unitPrice) || unitPrice <= 0) {
      throw new functions.https.HttpsError(
          'failed-precondition', `Narx yo'q: ${fid}`);
    }
    const discount = breadExtraDiscount(d, qty);
    const lineTotal = Math.max(0, Math.round(unitPrice * qty) - discount);
    extrasSum += lineTotal;
    decrements.push({
      kind: 'extra',
      id: fid,
      qty,
      label: String(d.name || fid).trim() || fid,
    });
    extras.push({
      emoji: String(d.emoji || it.emoji || ''),
      caption: String(d.caption || it.caption || ''),
      name: String(d.name || fid).trim() || fid,
      count: qty,
      unit: String(d.unit || it.unit || 'dona'),
      firestoreId: fid,
      ...(discount > 0 ? {
        bonusDiscount: discount,
        bonusPercent: Math.trunc(Number(d.bonusPercent || 0)),
      } : {}),
      total: lineTotal,
    });
  }

  const saltYeastCost = yopishToyCount * saltUnit;
  const total = breadSum + extrasSum + saltYeastCost;
  if (!Number.isFinite(total) || total <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'invalid order total');
  }

  return {
    items,
    extras,
    saltYeastCost,
    cartHadYopishBread: cartHadYopish,
    total,
    decrements,
  };
}

/** Буюртма + омбор; food/bread нарх каталогдан; ҳамён (ixtiyoriy) ledger орқали. */
exports.placeOrderPostPaid = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const userPhone = String(data.userPhone || '');
  const idempotencyKey = String(data.idempotencyKey || '').trim();
  const orderBase = data.orderBase && typeof data.orderBase === 'object' ? data.orderBase : null;
  const decrementsIn = Array.isArray(data.decrements) ? data.decrements : [];

  if (!idempotencyKey) {
    throw new functions.https.HttpsError('invalid-argument', 'idempotencyKey required');
  }
  if (!orderBase) {
    throw new functions.https.HttpsError('invalid-argument', 'orderBase required');
  }

  const callerUid = canonicalUid(callerPhone(context));
  const orderPhone = canonicalUid(
    String(data.phone || orderBase.phone || orderBase.userPhone || userPhone),
  );
  if (!callerUid || !orderPhone || callerUid !== orderPhone) {
    throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
  }

  const orderType = String(orderBase.type || '');
  if (orderType !== 'bread' && orderType !== 'food' && orderType !== 'platform') {
    throw new functions.https.HttpsError(
        'invalid-argument', 'orderBase.type must be bread, food or platform');
  }

  const uid9 = userUid(userPhone);
  const uid12 = canonicalUid(userPhone);
  let userRef = db.collection('users').doc(uid12);
  let userCheck = await userRef.get();
  if (!userCheck.exists && uid9 !== uid12) {
    userRef = db.collection('users').doc(uid9);
    userCheck = await userRef.get();
  }
  if (!userCheck.exists) {
    throw new functions.https.HttpsError('not-found', 'user not found');
  }

  const idemRef = db.collection('wallet_idempotency').doc(idempotencyKey);
  const existing = await idemRef.get();
  if (existing.exists) {
    return existing.data().result || { ok: true, duplicate: true };
  }

  // Food/bread: server-side narx (client total/price e'tiborsiz).
  let pricedItems = Array.isArray(orderBase.items) ? orderBase.items : [];
  let pricedExtras = Array.isArray(orderBase.extras) ? orderBase.extras : null;
  let serverSaltYeast = null;
  let serverHadYopish = null;
  let serverTotal = parseInt(String(orderBase.total || 0), 10);
  let catalogDecs = null;
  let platformItemsTotal = null;
  let platformDeliveryFee = null;
  let platformDeliveryFeePercent = null;
  if (orderType === 'food') {
    const priced = await repriceFoodOrderFromCatalog(orderBase.items);
    pricedItems = priced.items;
    serverTotal = priced.total;
    catalogDecs = priced.decrements;
  } else if (orderType === 'bread') {
    const priced = await repriceBreadOrderFromCatalog(orderBase);
    pricedItems = priced.items;
    pricedExtras = priced.extras;
    serverSaltYeast = priced.saltYeastCost;
    serverHadYopish = priced.cartHadYopishBread;
    serverTotal = priced.total;
    catalogDecs = priced.decrements;
  } else if (orderType === 'platform') {
    const priced = await repricePlatformOrderFromCatalog(orderBase.items);
    pricedItems = priced.items;
    serverTotal = priced.total;
    catalogDecs = priced.decrements;
    const appSettings = await db.collection('settings').doc('app').get();
    let pct = Number((appSettings.data() || {}).platformDeliveryFeePercent);
    if (!Number.isFinite(pct) || pct < 0) pct = 5;
    if (pct > 100) pct = 100;
    platformItemsTotal = serverTotal;
    platformDeliveryFeePercent = pct;
    platformDeliveryFee = Math.round(serverTotal * pct / 100);
    serverTotal = platformItemsTotal + platformDeliveryFee;
  } else if (!Number.isFinite(serverTotal) || serverTotal <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'invalid order total');
  }

  const orderRef = db.collection('orders').doc();
  const module = orderType === 'bread'
      ? 'bread'
      : (orderType === 'platform' ? 'platform' : 'food');
  const agg = {};
  const decSource = catalogDecs || decrementsIn;
  for (let i = 0; i < decSource.length; i += 1) {
    const c = decSource[i] || {};
    const id = String(c.id || '').trim();
    const qty = Number(c.qty);
    if (!id || !Number.isFinite(qty) || qty <= 0) continue;
    const col = inventoryCollectionForDecrementKind(String(c.kind || ''));
    const key = `${col}__${id}`;
    if (!agg[key]) {
      agg[key] = { col, id, qty: 0, label: String(c.label || id) };
    }
    agg[key].qty += qty;
  }

  let txDuplicate = null;
  const result = await db.runTransaction(async (t) => {
    const idemSnap = await t.get(idemRef);
    if (idemSnap.exists) {
      txDuplicate = idemSnap.data().result;
      return null;
    }

    const orderTotal = serverTotal;
    if (!Number.isFinite(orderTotal) || orderTotal <= 0) {
      throw new functions.https.HttpsError('invalid-argument', 'invalid order total');
    }

    const invKeys = Object.keys(agg);
    const invSnaps = {};
    for (let i = 0; i < invKeys.length; i += 1) {
      const row = agg[invKeys[i]];
      invSnaps[invKeys[i]] = await t.get(db.collection(row.col).doc(row.id));
    }

    const userSnap = await t.get(userRef);
    const userData = userSnap.data() || {};
    const userAddr = userData.address;
    const prevBalance = parseInt(String(userData.bonusBalance ?? 0), 10) || 0;

    const failures = [];
    for (let i = 0; i < invKeys.length; i += 1) {
      const row = agg[invKeys[i]];
      const snap = invSnaps[invKeys[i]];
      const need = row.qty;
      if (!snap.exists) continue;
      const d = snap.data() || {};
      const total = Number(d.totalStock) || 0;
      const sold = Number(d.soldToday) || 0;
      if (total <= 0) continue;
      const remaining = total - sold;
      if (remaining + 1e-9 < need) {
        failures.push(`${row.label}: керак ${need}, қолди ${remaining}`);
      }
    }
    if (failures.length > 0) {
      throw new functions.https.HttpsError('failed-precondition', failures.join('; '));
    }

    // Ҳамён opt-in: фақат useWallet===true + аниқ balanceApplied (default 0).
    // Silent max debit йўқ — келажакдаги барча placeOrderPostPaid хизматлари учун.
    const maxWallet = maxWalletDebit(prevBalance, orderTotal);
    const useWallet = orderBase.useWallet === true;
    let requested = parseInt(String(orderBase.balanceApplied ?? 0), 10);
    if (!Number.isFinite(requested) || requested < 0) requested = 0;
    const walletDebit = useWallet ? Math.min(Math.floor(requested), maxWallet) : 0;
    const cashDue = orderTotal - walletDebit;

    const bonusCtx = walletDebit > 0
      ? await settlementLedger.prepareBonusInTx(t, db, userRef.id, { idempotencyKey })
      : null;

    for (let i = 0; i < invKeys.length; i += 1) {
      const row = agg[invKeys[i]];
      const snap = invSnaps[invKeys[i]];
      const ref = db.collection(row.col).doc(row.id);
      const need = row.qty;
      if (!snap.exists) {
        t.set(ref, { totalStock: 0, soldToday: need });
        continue;
      }
      t.update(ref, { soldToday: admin.firestore.FieldValue.increment(need) });
    }

    if (walletDebit > 0 && bonusCtx) {
      const nextBalance = prevBalance - walletDebit;
      if (nextBalance < 0) {
        throw new functions.https.HttpsError('failed-precondition', 'insufficient_balance');
      }
      t.set(userRef, {
        bonusBalance: nextBalance,
        balanceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      settlementLedger.commitBonusInTx(t, bonusCtx, {
        delta: -walletDebit,
        kind: 'order_wallet',
        refType: 'order',
        refId: orderRef.id,
        meta: { module, orderTotal, walletDebit, cashDue },
        postedBy: userRef.id,
        postedRole: 'client',
      });
      const ledgerId = userRef.collection('wallet_ledger').doc().id;
      t.set(userRef.collection('wallet_ledger').doc(ledgerId), {
        type: 'purchase_debit',
        amount: -walletDebit,
        module,
        refType: 'order',
        refId: orderRef.id,
        meta: { orderTotal, cashDue, roundingStep: 1 },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: 'client',
      });
    }

    const inventoryDecrements = Object.keys(agg).map((k) => ({
      kind: agg[k].col === 'bread_products'
          ? 'bread'
          : (agg[k].col === 'extra_products'
              ? 'extra'
              : (agg[k].col === 'platform_products' ? 'platform' : 'food')),
      id: agg[k].id,
      qty: agg[k].qty,
      label: agg[k].label,
    }));

    const paymentStatus = cashDue <= 0 ? 'paid' : 'unpaid';
    const clampStr = (v, max) => String(v || '').trim().slice(0, max);
    const orderPayload = {
      type: orderType,
      userName: clampStr(orderBase.userName, 80),
      userPhone: callerUid,
      address: clampStr(orderBase.address, 300),
      phone: callerUid,
      items: pricedItems,
      inventoryDecrements,
      total: orderTotal,
      balanceApplied: walletDebit,
      cashDue,
      cashPaid: 0,
      status: 'new',
      fulfillmentStatus: 'pending',
      paymentStatus,
      fulfillmentMode: (String(orderBase.fulfillmentMode || '') === 'pickup')
          ? 'pickup'
          : 'delivery',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (orderBase.note != null || orderBase.comment != null) {
      orderPayload.note = clampStr(orderBase.note || orderBase.comment, 500);
    }
    if (paymentStatus === 'paid') {
      orderPayload.paymentMethod = 'wallet';
      orderPayload.paidAmount = orderTotal;
      orderPayload.paidAt = admin.firestore.FieldValue.serverTimestamp();
    }
    if (orderType === 'bread') {
      if (Array.isArray(pricedExtras)) {
        orderPayload.extras = pricedExtras;
      }
      if (serverSaltYeast != null && serverSaltYeast > 0) {
        orderPayload.saltYeastCost = serverSaltYeast;
      }
      if (serverHadYopish === true) {
        orderPayload.cartHadYopishBread = true;
      }
    }
    if (orderType === 'platform') {
      if (platformItemsTotal != null) {
        orderPayload.itemsTotal = platformItemsTotal;
      }
      if (platformDeliveryFee != null) {
        orderPayload.deliveryFee = platformDeliveryFee;
      }
      if (platformDeliveryFeePercent != null) {
        orderPayload.deliveryFeePercent = platformDeliveryFeePercent;
      }
    }
    Object.assign(orderPayload, geoReportStamp(userData));
    let lat = orderBase.lat != null && orderBase.lat !== '' ? Number(orderBase.lat) : null;
    let lng = orderBase.lng != null && orderBase.lng !== '' ? Number(orderBase.lng) : null;
    if ((lat == null || lng == null) && userAddr && typeof userAddr === 'object') {
      if (lat == null && userAddr.lat != null) lat = Number(userAddr.lat);
      if (lng == null && userAddr.lng != null) lng = Number(userAddr.lng);
    }
    if (
      lat != null && lng != null &&
      Number.isFinite(lat) && Number.isFinite(lng) &&
      (Math.abs(lat) > 1e-6 || Math.abs(lng) > 1e-6)
    ) {
      orderPayload.lat = lat;
      orderPayload.lng = lng;
    }

    t.set(orderRef, orderPayload);
    const out = {
      ok: true,
      orderId: orderRef.id,
      total: orderTotal,
      useWallet,
      walletDebit,
      balanceApplied: walletDebit,
      cashDue,
      paymentStatus,
    };
    t.set(idemRef, {
      type: 'placeOrderPostPaid',
      result: out,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return out;
  });

  if (txDuplicate) return txDuplicate;
  return result;
});

/**
 * Мижоз: food/bread буюртмани бекор (фақат эрта ҳолат).
 * Захира қайтариш + ҳамён refund (agar balanceApplied > 0).
 */
exports.customerCancelOrder = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }
  const orderId = String((data && data.orderId) || '').trim();
  const reason = String((data && data.reason) || 'Мижоз бекор қилди').trim().slice(0, 200);
  if (!orderId) {
    throw new functions.https.HttpsError('invalid-argument', 'orderId required');
  }

  const callerUid = canonicalUid(callerPhone(context));
  if (!callerUid || callerUid.length < 9) {
    throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
  }

  const orderRef = db.collection('orders').doc(orderId);
  const idemKey = `customer_cancel_${orderId}`;
  const idemRef = db.collection('wallet_idempotency').doc(idemKey);
  const existing = await idemRef.get();
  if (existing.exists) {
    return existing.data().result || { ok: true, duplicate: true };
  }

  let txDuplicate = null;
  const result = await db.runTransaction(async (t) => {
    const idemSnap = await t.get(idemRef);
    if (idemSnap.exists) {
      txDuplicate = idemSnap.data().result;
      return null;
    }
    const snap = await t.get(orderRef);
    if (!snap.exists) {
      throw new functions.https.HttpsError('not-found', 'order not found');
    }
    const od = snap.data() || {};
    const owner = canonicalUid(String(od.userPhone || od.phone || ''));
    if (!owner || owner !== callerUid) {
      throw new functions.https.HttpsError('permission-denied', 'Not your order');
    }

    const status = String(od.status || '');
    const fs = String(od.fulfillmentStatus || '').toLowerCase();
    const cancelledAlready = status === 'cancelled' || status === 'rejected'
        || fs === 'cancelled';
    if (cancelledAlready) {
      const out = { ok: true, already: true, orderId };
      t.set(idemRef, {
        type: 'customerCancelOrder',
        result: out,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return out;
    }

    // Курьер олиб кетгандан кейин / тўлангандан кейин (қисман ҳамён + нақд) — йўқ.
    const blockedFs = ['courier_picked', 'arrived', 'completed', 'in_delivery'];
    if (blockedFs.includes(fs) || status === 'in_delivery' || status === 'delivered') {
      throw new functions.https.HttpsError(
          'failed-precondition',
          'Бу ҳолатда бекор қилиб бўлмайди',
      );
    }
    const allowedStatus = ['new', 'accepted', 'ready', ''].includes(status);
    const allowedFs = ['', 'pending', 'confirmed', 'ready'].includes(fs);
    if (!allowedStatus || !allowedFs) {
      throw new functions.https.HttpsError(
          'failed-precondition',
          'Бу ҳолатда бекор қилиб бўлмайди',
      );
    }

    // Захира қайтариш
    const decs = Array.isArray(od.inventoryDecrements) ? od.inventoryDecrements : [];
    for (let i = 0; i < decs.length; i += 1) {
      const c = decs[i] || {};
      const id = String(c.id || '').trim();
      const qty = Number(c.qty);
      if (!id || !Number.isFinite(qty) || qty <= 0) continue;
      let col;
      try {
        col = inventoryCollectionForDecrementKind(String(c.kind || ''));
      } catch (_) {
        continue;
      }
      const invRef = db.collection(col).doc(id);
      const invSnap = await t.get(invRef);
      if (!invSnap.exists) continue;
      const d = invSnap.data() || {};
      const totalStock = Number(d.totalStock) || 0;
      if (totalStock <= 0) continue;
      t.update(invRef, {
        soldToday: admin.firestore.FieldValue.increment(-qty),
      });
    }

    const walletRefund = Math.max(0, Math.trunc(Number(od.balanceApplied || 0)));
    const uid12 = canonicalUid(String(od.userPhone || od.phone || ''));
    const uid9 = userUid(String(od.userPhone || od.phone || ''));
    let customerRef = db.collection('users').doc(uid12);
    let customerSnap = await t.get(customerRef);
    if (!customerSnap.exists && uid9 !== uid12) {
      customerRef = db.collection('users').doc(uid9);
      customerSnap = await t.get(customerRef);
    }

    if (walletRefund > 0 && customerSnap.exists) {
      const bal = parseInt(String(customerSnap.data()?.bonusBalance ?? 0), 10) || 0;
      const bonusCtx = await settlementLedger.prepareBonusInTx(
          t, db, customerRef.id, { idempotencyKey: idemKey });
      t.set(customerRef, {
        bonusBalance: bal + walletRefund,
        balanceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      settlementLedger.commitBonusInTx(t, bonusCtx, {
        delta: walletRefund,
        kind: 'order_cancel_refund',
        refType: 'order',
        refId: orderId,
        meta: { walletRefund },
        postedBy: callerUid,
        postedRole: 'client',
      });
      const ledgerId = customerRef.collection('wallet_ledger').doc().id;
      t.set(customerRef.collection('wallet_ledger').doc(ledgerId), {
        type: 'order_cancel_refund',
        amount: walletRefund,
        module: String(od.type || 'food') === 'bread' ? 'bread' : 'food',
        refType: 'order',
        refId: orderId,
        meta: { reason },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: 'customerCancelOrder',
      });
    }

    t.update(orderRef, {
      status: 'cancelled',
      fulfillmentStatus: 'cancelled',
      cancelReason: reason || 'Мижоз бекор қилди',
      cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      cancelledBy: callerUid,
      statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const out = { ok: true, orderId, walletRefund };
    t.set(idemRef, {
      type: 'customerCancelOrder',
      result: out,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return out;
  });

  if (txDuplicate) return txDuplicate;
  return result;
});

/**
 * Sotuvchi mini-kassa — joyida sotuv (tayyor taom/non).
 * Naqd / hamyon / aralash; zaxira −; buyurtma darhol paid+completed.
 */
exports.sellerPlaceSale = functions.https.onCall(async (data, context) => {
  const sellerUid = await requireCallerRoles(
      context,
      ['seller', 'admin', 'superadmin'],
      'Faqat sotuvchi',
  );

  const idempotencyKey = String((data && data.idempotencyKey) || '').trim();
  if (!idempotencyKey) {
    throw new functions.https.HttpsError('invalid-argument', 'idempotencyKey kerak');
  }

  const itemsIn = Array.isArray(data && data.items) ? data.items : [];
  if (itemsIn.length < 1 || itemsIn.length > 40) {
    throw new functions.https.HttpsError('invalid-argument', 'items kerak');
  }

  const cashPaid = Math.trunc(Number((data && data.cashPaid) || 0));
  const walletPaid = Math.trunc(Number((data && data.walletPaid) || 0));
  if (!Number.isInteger(cashPaid) || cashPaid < 0) {
    throw new functions.https.HttpsError('invalid-argument', 'cashPaid >= 0');
  }
  if (!Number.isInteger(walletPaid) || walletPaid < 0) {
    throw new functions.https.HttpsError('invalid-argument', 'walletPaid >= 0');
  }

  const customerPhoneRaw = String((data && data.customerPhone) || '').trim();
  const customerUid = customerPhoneRaw ? canonicalUid(customerPhoneRaw) : '';
  if (walletPaid > 0 && (!customerUid || customerUid.length < 12)) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'Hamyon uchun mijoz telefoni kerak',
    );
  }

  const idemRef = db.collection('wallet_idempotency').doc(idempotencyKey);
  const existing = await idemRef.get();
  if (existing.exists) {
    return existing.data().result || { ok: true, duplicate: true };
  }

  const items = [];
  const agg = {};
  let computedTotal = 0;
  for (let i = 0; i < itemsIn.length; i += 1) {
    const row = itemsIn[i] || {};
    const kind = String(row.kind || '').toLowerCase();
    if (kind !== 'food' && kind !== 'bread') {
      throw new functions.https.HttpsError('invalid-argument', 'bad item kind');
    }
    const inventoryId = String(row.inventoryId || '').trim();
    const qty = Number(row.qty || 0);
    if (!inventoryId || !Number.isFinite(qty) || qty <= 0) {
      throw new functions.https.HttpsError('invalid-argument', 'bad item');
    }
    const catalog = await resolveSellerCatalogLine(kind, inventoryId);
    const unitPrice = catalog.unitPrice;
    const name = catalog.name;
    const lineTotal = Math.round(unitPrice * qty);
    computedTotal += lineTotal;
    items.push({
      kind,
      inventoryId,
      name,
      emoji: catalog.emoji || String(row.emoji || ''),
      price: unitPrice,
      qty,
      unit: catalog.unit || String(row.unit || 'dona'),
      total: lineTotal,
    });
    const col = inventoryCollectionForDecrementKind(kind);
    const key = `${col}__${inventoryId}`;
    if (!agg[key]) {
      agg[key] = { col, id: inventoryId, qty: 0, label: name };
    }
    agg[key].qty += qty;
  }

  if (computedTotal <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'jami 0');
  }
  if (cashPaid + walletPaid < computedTotal) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        `Kam to'lov: ${cashPaid + walletPaid} < ${computedTotal}`,
    );
  }
  if (walletPaid > computedTotal) {
    throw new functions.https.HttpsError(
        'invalid-argument',
        'walletPaid > jami',
    );
  }

  const hasFood = items.some((it) => it.kind === 'food');
  const orderType = hasFood ? 'food' : 'bread';
  const orderRef = db.collection('orders').doc();
  const changeCredit = Math.max(0, cashPaid + walletPaid - computedTotal);

  let txDuplicate = null;
  const result = await db.runTransaction(async (t) => {
    const idemSnap = await t.get(idemRef);
    if (idemSnap.exists) {
      txDuplicate = idemSnap.data().result;
      return null;
    }

    const invKeys = Object.keys(agg);
    const invSnaps = {};
    for (let i = 0; i < invKeys.length; i += 1) {
      const row = agg[invKeys[i]];
      invSnaps[invKeys[i]] = await t.get(db.collection(row.col).doc(row.id));
    }

    let customerRef = null;
    let customerSnap = null;
    if (walletPaid > 0 || changeCredit > 0) {
      if (!customerUid || customerUid.length < 12) {
        throw new functions.https.HttpsError(
            'invalid-argument',
            'Qaytim/hamyon uchun mijoz telefoni kerak',
        );
      }
      customerRef = db.collection('users').doc(customerUid);
      customerSnap = await t.get(customerRef);
      if (!customerSnap.exists) {
        const uid9 = userUid(customerPhoneRaw);
        if (uid9 !== customerUid) {
          customerRef = db.collection('users').doc(uid9);
          customerSnap = await t.get(customerRef);
        }
      }
      if (!customerSnap.exists) {
        throw new functions.https.HttpsError(
            'not-found',
            'Mijoz topilmadi — ilovada ro\'yxatdan o\'tsin',
        );
      }
    }

    const failures = [];
    for (let i = 0; i < invKeys.length; i += 1) {
      const row = agg[invKeys[i]];
      const snap = invSnaps[invKeys[i]];
      const need = row.qty;
      if (!snap.exists) continue;
      const d = snap.data() || {};
      const total = Number(d.totalStock) || 0;
      const sold = Number(d.soldToday) || 0;
      if (total <= 0) continue;
      const remaining = total - sold;
      if (remaining + 1e-9 < need) {
        failures.push(`${row.label}: kerak ${need}, qoldi ${remaining}`);
      }
    }
    if (failures.length > 0) {
      throw new functions.https.HttpsError(
          'failed-precondition',
          failures.join('; '),
      );
    }

    for (let i = 0; i < invKeys.length; i += 1) {
      const row = agg[invKeys[i]];
      const snap = invSnaps[invKeys[i]];
      const ref = db.collection(row.col).doc(row.id);
      const need = row.qty;
      if (!snap.exists) {
        t.set(ref, { totalStock: 0, soldToday: need });
        continue;
      }
      t.update(ref, { soldToday: admin.firestore.FieldValue.increment(need) });
    }

    if ((walletPaid > 0 || changeCredit > 0) && customerRef && customerSnap) {
      const balance = Math.trunc(
          Number((customerSnap.data() || {}).bonusBalance || 0));
      if (walletPaid > 0 && balance < walletPaid) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            `Hamyon yetarli emas: ${balance} < ${walletPaid}`,
        );
      }
      const bonusDelta = changeCredit - walletPaid;
      if (bonusDelta !== 0) {
        const bonusCtx = await settlementLedger.prepareBonusInTx(
            t, db, customerRef.id,
            { idempotencyKey: `seller_sale_${idempotencyKey}` });
        t.set(customerRef, {
          bonusBalance: balance + bonusDelta,
          balanceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        if (walletPaid > 0) {
          const debitId = customerRef.collection('wallet_ledger').doc().id;
          t.set(customerRef.collection('wallet_ledger').doc(debitId), {
            type: 'purchase_debit',
            amount: -walletPaid,
            module: 'seller_pos',
            refType: 'order',
            refId: orderRef.id,
            meta: { orderTotal: computedTotal },
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            createdBy: 'sellerPlaceSale',
          });
        }
        if (changeCredit > 0) {
          const creditId = customerRef.collection('wallet_ledger').doc().id;
          t.set(customerRef.collection('wallet_ledger').doc(creditId), {
            type: 'change_accrued',
            amount: changeCredit,
            module: 'seller_pos',
            refType: 'order',
            refId: orderRef.id,
            meta: { orderTotal: computedTotal, cashPaid, walletPaid },
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            createdBy: 'sellerPlaceSale',
          });
        }
        settlementLedger.commitBonusInTx(t, bonusCtx, {
          delta: bonusDelta,
          kind: 'seller_pos_sale',
          refType: 'order',
          refId: orderRef.id,
          meta: { module: 'seller_pos', cashPaid, walletPaid, changeCredit },
          postedBy: sellerUid,
          postedRole: 'seller',
        });
      }
    }

    const walkIn = !customerUid;
    const orderUserPhone = walkIn ? sellerUid : (customerRef ? customerRef.id : customerUid);
    const paymentMethod = walletPaid > 0 && cashPaid > 0
        ? 'mixed'
        : (walletPaid > 0 ? 'wallet' : 'cash');

    t.set(orderRef, {
      type: orderType,
      userName: walkIn ? 'Walk-in' : '',
      userPhone: orderUserPhone,
      phone: orderUserPhone,
      address: '',
      items,
      total: computedTotal,
      balanceApplied: walletPaid,
      cashDue: Math.max(0, computedTotal - walletPaid),
      cashPaid,
      status: 'delivered',
      fulfillmentStatus: 'completed',
      paymentStatus: 'paid',
      fulfillmentMode: 'pos',
      paymentMethod,
      paidAmount: cashPaid + walletPaid,
      paidBySellerId: sellerUid,
      paidAt: admin.firestore.FieldValue.serverTimestamp(),
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
      walkIn,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(changeCredit > 0 ? { changeCredited: changeCredit } : {}),
    });

    const out = {
      ok: true,
      orderId: orderRef.id,
      total: computedTotal,
      cashPaid,
      walletPaid,
      changeCredit,
    };
    t.set(idemRef, {
      type: 'sellerPlaceSale',
      result: out,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return out;
  });

  if (txDuplicate) return txDuplicate;
  return result;
});

/**
 * Sotuvchi smena xulosasi — bugungi (Asia/Tashkent) to'lovlar.
 * `orders.paidBySellerId` + `paidAt` oralig'i.
 */
exports.sellerGetShiftSummary = functions.https.onCall(async (data, context) => {
  const sellerUid = await requireCallerRoles(
      context,
      ['seller', 'admin', 'superadmin'],
      'Faqat sotuvchi',
  );

  const dayKeyIn = String((data && data.dateKey) || '').trim();
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Tashkent',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  const dayKey = /^\d{4}-\d{2}-\d{2}$/.test(dayKeyIn)
      ? dayKeyIn
      : fmt.format(new Date());
  const [y, m, d] = dayKey.split('-').map((x) => Number(x));
  // Tashkent = UTC+5 (DST yo'q)
  const startMs = Date.UTC(y, m - 1, d, 0, 0, 0, 0) - 5 * 3600 * 1000;
  const endMs = startMs + 24 * 3600 * 1000;
  const start = admin.firestore.Timestamp.fromMillis(startMs);
  const end = admin.firestore.Timestamp.fromMillis(endMs);

  const snap = await db.collection('orders')
      .where('paidBySellerId', '==', sellerUid)
      .where('paidAt', '>=', start)
      .where('paidAt', '<', end)
      .limit(300)
      .get();

  let total = 0;
  let cashPaid = 0;
  let walletPaid = 0;
  let changeCredit = 0;
  let posCount = 0;
  let pickupCount = 0;
  for (const doc of snap.docs) {
    const od = doc.data() || {};
    total += Math.trunc(Number(od.total || 0));
    cashPaid += Math.trunc(Number(od.cashPaid || 0));
    walletPaid += Math.trunc(Number(od.balanceApplied || od.walletPaid || 0));
    changeCredit += Math.trunc(Number(od.changeCredited || 0));
    const mode = String(od.fulfillmentMode || '');
    if (mode === 'pos') posCount += 1;
    else if (mode === 'pickup') pickupCount += 1;
  }

  return {
    ok: true,
    dateKey: dayKey,
    count: snap.size,
    total,
    cashPaid,
    walletPaid,
    changeCredit,
    posCount,
    pickupCount,
  };
});

exports.sellerGetCustomerWalletBalance = functions.https.onCall(async (data, context) => {
  await requireCallerRoles(
      context,
      ['seller', 'admin', 'superadmin'],
      'Faqat sotuvchi',
  );
  const customerPhone = String((data && data.customerPhone) || '').trim();
  if (!customerPhone) {
    throw new functions.https.HttpsError('invalid-argument', 'customerPhone kerak');
  }
  const uid9 = userUid(customerPhone);
  const uid12 = canonicalUid(customerPhone);
  let customerRef = db.collection('users').doc(uid12);
  let userSnap = await customerRef.get();
  if (!userSnap.exists && uid9 !== uid12) {
    customerRef = db.collection('users').doc(uid9);
    userSnap = await customerRef.get();
  }
  const bonusBalance = userSnap.exists
      ? parseInt(String(userSnap.data()?.bonusBalance ?? 0), 10) || 0
      : 0;
  return { bonusBalance, uid: customerRef.id, found: userSnap.exists };
});

/** Pickup buyurtmani «Tayyor» qilish. */
exports.sellerMarkPickupReady = functions.https.onCall(async (data, context) => {
  const sellerUid = await requireCallerRoles(
      context,
      ['seller', 'admin', 'superadmin'],
      'Faqat sotuvchi',
  );
  const orderId = String((data && data.orderId) || '').trim();
  if (!orderId) {
    throw new functions.https.HttpsError('invalid-argument', 'orderId kerak');
  }
  const ref = db.collection('orders').doc(orderId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'Buyurtma topilmadi');
  }
  const od = snap.data() || {};
  if (String(od.fulfillmentMode || '') !== 'pickup') {
    throw new functions.https.HttpsError('failed-precondition', 'Faqat olib ketish');
  }
  if (od.paymentStatus === 'paid') {
    throw new functions.https.HttpsError('failed-precondition', 'Allaqachon to\'langan');
  }
  const fs = String(od.fulfillmentStatus || 'pending');
  if (fs === 'ready' || fs === 'completed') {
    return { ok: true, already: true };
  }
  if (fs !== 'pending' && fs !== 'confirmed') {
    throw new functions.https.HttpsError('failed-precondition', `Holat: ${fs}`);
  }
  await ref.update({
    fulfillmentStatus: 'ready',
    status: 'ready',
    sellerReadyBy: sellerUid,
    sellerReadyAt: admin.firestore.FieldValue.serverTimestamp(),
    statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

/**
 * Pickup buyurtma — mijoz kelganda joyida to'lov (naqd/hamyon/aralash).
 */
exports.sellerSubmitPickupPayment = functions.https.onCall(async (data, context) => {
  const sellerUid = await requireCallerRoles(
      context,
      ['seller', 'admin', 'superadmin'],
      'Faqat sotuvchi',
  );
  const orderId = String((data && data.orderId) || '').trim();
  const cashPaid = Math.trunc(Number((data && data.cashPaid) || 0));
  const walletPaid = Math.trunc(Number((data && data.walletPaid) || 0));
  if (!orderId) {
    throw new functions.https.HttpsError('invalid-argument', 'orderId kerak');
  }
  if (!Number.isInteger(cashPaid) || cashPaid < 0) {
    throw new functions.https.HttpsError('invalid-argument', 'cashPaid >= 0');
  }
  if (!Number.isInteger(walletPaid) || walletPaid < 0) {
    throw new functions.https.HttpsError('invalid-argument', 'walletPaid >= 0');
  }

  const idempotencyKey = `seller_pickup_pay_${orderId}`;
  const idemRef = db.collection('wallet_idempotency').doc(idempotencyKey);
  const existing = await idemRef.get();
  if (existing.exists) {
    return existing.data().result || { ok: true, duplicate: true };
  }

  const orderRef = db.collection('orders').doc(orderId);
  let txDuplicate = null;
  const result = await db.runTransaction(async (t) => {
    const idemSnap = await t.get(idemRef);
    if (idemSnap.exists) {
      txDuplicate = idemSnap.data().result;
      return null;
    }
    const orderSnap = await t.get(orderRef);
    if (!orderSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Buyurtma topilmadi');
    }
    const od = orderSnap.data() || {};
    if (String(od.fulfillmentMode || '') !== 'pickup') {
      throw new functions.https.HttpsError('failed-precondition', 'Faqat olib ketish');
    }
    if (od.paymentStatus === 'paid' && String(od.fulfillmentStatus) === 'completed') {
      const paidOut = {
        ok: true,
        idempotent: true,
        orderId,
        total: Math.trunc(Number(od.total || 0)),
        cashPaid: Math.trunc(Number(od.cashPaid || 0)),
        walletPaid: Math.trunc(Number(od.balanceApplied || 0)),
        changeCredit: Math.trunc(Number(od.changeCredited || 0)),
      };
      t.set(idemRef, {
        type: 'sellerSubmitPickupPayment',
        result: paidOut,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return paidOut;
    }
    const fs = String(od.fulfillmentStatus || '');
    if (fs !== 'ready') {
      throw new functions.https.HttpsError(
          'failed-precondition',
          fs === 'pending' || fs === 'confirmed'
              ? 'Avval «Tayyor» qiling'
              : `Holat: ${fs}`,
      );
    }

    const orderTotal = Math.trunc(Number(od.total || od.grandTotal || 0));
    if (orderTotal <= 0) {
      throw new functions.https.HttpsError('invalid-argument', 'jami noto\'g\'ri');
    }
    const preApplied = Math.max(0, Math.trunc(Number(od.balanceApplied || 0)));
    const remainingDue = Math.max(0, orderTotal - preApplied);

    // Буюртмада ҳамён тўлиқ — қўшимча тўловсиз якун.
    if (remainingDue <= 0 || (od.paymentStatus === 'paid' && preApplied >= orderTotal)) {
      t.update(orderRef, {
        paymentStatus: 'paid',
        paymentMethod: od.paymentMethod || 'wallet',
        paidAmount: orderTotal,
        balanceApplied: Math.max(preApplied, orderTotal),
        cashDue: 0,
        fulfillmentStatus: 'completed',
        status: 'delivered',
        paidBySellerId: sellerUid,
        paidAt: od.paidAt || admin.firestore.FieldValue.serverTimestamp(),
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
        statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      const prepaidOut = {
        ok: true,
        orderId,
        total: orderTotal,
        cashPaid: 0,
        walletPaid: Math.max(preApplied, orderTotal),
        changeCredit: 0,
        prepaid: true,
      };
      t.set(idemRef, {
        type: 'sellerSubmitPickupPayment',
        result: prepaidOut,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return prepaidOut;
    }

    if (cashPaid + walletPaid < remainingDue) {
      throw new functions.https.HttpsError(
          'invalid-argument',
          `Kam to'lov: ${cashPaid + walletPaid} < ${remainingDue}`,
      );
    }
    if (walletPaid > remainingDue) {
      throw new functions.https.HttpsError('invalid-argument', 'walletPaid > qoldiq');
    }
    const changeCredit = Math.max(0, cashPaid + walletPaid - remainingDue);

    const customerPhone = String(od.userPhone || od.phone || '');
    let customerRef = null;
    let customerSnap = null;
    if (walletPaid > 0 || changeCredit > 0) {
      const uid12 = canonicalUid(customerPhone);
      const uid9 = userUid(customerPhone);
      if (!uid12 || uid12.length < 12) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            'Mijoz telefoni yo\'q',
        );
      }
      customerRef = db.collection('users').doc(uid12);
      customerSnap = await t.get(customerRef);
      if (!customerSnap.exists && uid9 !== uid12) {
        customerRef = db.collection('users').doc(uid9);
        customerSnap = await t.get(customerRef);
      }
      if (!customerSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Mijoz topilmadi');
      }
    }

    if ((walletPaid > 0 || changeCredit > 0) && customerRef && customerSnap) {
      const balance = Math.trunc(
          Number((customerSnap.data() || {}).bonusBalance || 0));
      if (walletPaid > 0 && balance < walletPaid) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            `Hamyon yetarli emas: ${balance} < ${walletPaid}`,
        );
      }
      const bonusDelta = changeCredit - walletPaid;
      if (bonusDelta !== 0) {
        const bonusCtx = await settlementLedger.prepareBonusInTx(
            t, db, customerRef.id,
            { idempotencyKey: `seller_pickup_${orderId}` });
        t.set(customerRef, {
          bonusBalance: balance + bonusDelta,
          balanceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        if (walletPaid > 0) {
          const debitId = customerRef.collection('wallet_ledger').doc().id;
          t.set(customerRef.collection('wallet_ledger').doc(debitId), {
            type: 'purchase_debit',
            amount: -walletPaid,
            module: 'seller_pickup',
            refType: 'order',
            refId: orderId,
            meta: { orderTotal },
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            createdBy: 'sellerSubmitPickupPayment',
          });
        }
        if (changeCredit > 0) {
          const creditId = customerRef.collection('wallet_ledger').doc().id;
          t.set(customerRef.collection('wallet_ledger').doc(creditId), {
            type: 'change_accrued',
            amount: changeCredit,
            module: 'seller_pickup',
            refType: 'order',
            refId: orderId,
            meta: { orderTotal, cashPaid, walletPaid },
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            createdBy: 'sellerSubmitPickupPayment',
          });
        }
        settlementLedger.commitBonusInTx(t, bonusCtx, {
          delta: bonusDelta,
          kind: 'seller_pickup_pay',
          refType: 'order',
          refId: orderId,
          meta: { cashPaid, walletPaid, changeCredit },
          postedBy: sellerUid,
          postedRole: 'seller',
        });
      }
    }

    const paymentMethod = walletPaid > 0 && cashPaid > 0
        ? 'mixed'
        : (walletPaid > 0 ? 'wallet' : 'cash');

    t.update(orderRef, {
      paymentStatus: 'paid',
      paymentMethod: preApplied > 0 && (walletPaid > 0 || cashPaid > 0)
          ? 'mixed'
          : paymentMethod,
      paidAmount: preApplied + cashPaid + walletPaid,
      cashPaid,
      balanceApplied: preApplied + walletPaid,
      cashDue: 0,
      fulfillmentStatus: 'completed',
      status: 'delivered',
      paidBySellerId: sellerUid,
      paidAt: admin.firestore.FieldValue.serverTimestamp(),
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
      statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(changeCredit > 0 ? { changeCredited: changeCredit } : {}),
    });

    const out = {
      ok: true,
      orderId,
      total: orderTotal,
      cashPaid,
      walletPaid: preApplied + walletPaid,
      changeCredit,
    };
    t.set(idemRef, {
      type: 'sellerSubmitPickupPayment',
      result: out,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return out;
  });

  if (txDuplicate) return txDuplicate;
  return result;
});

exports.courierMarkPicked = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }
  const orderId = String(data.orderId || '');
  const courierId = assertCourierPhone(data.courierPhone);
  if (callerPhone(context) !== courierId) {
    throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
  }
  const lat = data.lat != null ? Number(data.lat) : null;
  const lng = data.lng != null ? Number(data.lng) : null;
  const { ref, data: od } = await loadOrderOrThrow(orderId);
  const fs = od.fulfillmentStatus || legacyStatusFromFulfillment(od.status || 'new');
  if (fs === 'cancelled' || fs === 'completed') {
    throw new functions.https.HttpsError('failed-precondition', 'order closed');
  }
  await ref.update({
    fulfillmentStatus: 'courier_picked',
    status: 'in_delivery',
    courierId,
    pickedAt: admin.firestore.FieldValue.serverTimestamp(),
    statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    inDeliveryAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await ref.collection('payment_events').add({
    action: 'courier_picked',
    actorType: 'courier',
    actorId: courierId,
    lat: Number.isFinite(lat) ? lat : null,
    lng: Number.isFinite(lng) ? lng : null,
    at: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

exports.courierCreateRoute = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Login required');
    }

    const courierPhone = String(data.courierPhone || '');
    const courierDigits = assertCourierPhone(courierPhone);
    const caller = callerPhone(context);
    if (canonicalUid(caller) !== canonicalUid(courierDigits)) {
      throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
    }

    const courierId = await resolveAuthorizedCourierUid(courierPhone);

    const orderedIn = Array.isArray(data.orderedOrderIds) ? data.orderedOrderIds : [];
    const orderedOrderIds = orderedIn
      .map((id) => String(id || '').trim())
      .filter((id) => id.length > 0);
    if (orderedOrderIds.length < 1) {
      throw new functions.https.HttpsError('invalid-argument', 'orderedOrderIds required');
    }

    const result = await db.runTransaction(async (t) => {
      // Бир курьерда — битта фаол маршрут. Мавжуд бўлса, унга қўшамиз
      // (иккита active маршрут → яширин/етим буюртмаларни олдини олиш).
      const activeQuery = db.collection('delivery_routes')
        .where('courierId', '==', courierId)
        .where('status', 'in', ['active', 'ready'])
        .limit(1);
      const activeSnap = await t.get(activeQuery);
      const existingRoute = activeSnap.empty ? null : activeSnap.docs[0];

      const validated = [];
      for (let i = 0; i < orderedOrderIds.length; i += 1) {
        const orderId = orderedOrderIds[i];
        const orderRef = db.collection('orders').doc(orderId);
        const snap = await t.get(orderRef);
        if (!snap.exists) continue;
        const od = snap.data() || {};
        if (String(od.status || '') !== 'ready') continue;
        validated.push(orderId);
      }

      if (validated.length < 1) {
        throw new functions.https.HttpsError('failed-precondition', 'no_ready_orders');
      }

      let routeId;
      if (existingRoute) {
        const existingOrders = Array.isArray(existingRoute.data().orders)
          ? existingRoute.data().orders.slice()
          : [];
        for (const id of validated) {
          if (!existingOrders.includes(id)) existingOrders.push(id);
        }
        t.update(existingRoute.ref, {
          orders: existingOrders,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        routeId = existingRoute.id;
      } else {
        const routeRef = db.collection('delivery_routes').doc();
        t.set(routeRef, {
          orders: validated,
          courierId,
          status: 'active',
          currentIndex: 0,
          routeSource: 'courier_self',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          startedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        routeId = routeRef.id;
      }

      for (let j = 0; j < validated.length; j += 1) {
        const orderId = validated[j];
        t.update(db.collection('orders').doc(orderId), {
          status: 'in_delivery',
          fulfillmentStatus: 'courier_picked',
          courierId,
          deliveryRouteId: routeId,
          statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          inDeliveryAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      return { routeId, count: validated.length };
    });

    return result;
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('courierCreateRoute:', e);
    const msg = e && e.message ? String(e.message) : 'courierCreateRoute failed';
    throw new functions.https.HttpsError('internal', msg);
  }
});

/**
 * Хавфсизлик тўри: курьерда фаол маршрут йўқ, лекин ўзига бириктирилган
 * `in_delivery` + тўланмаган буюртма(лар) бўлса — улардан автоматик фаол
 * маршрут тиклайди. Шу туфайли «Курьерда қотиб қолган» буюртма қайта кўринади.
 */
exports.courierRecoverOrphanRoute = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Login required');
    }
    const courierPhone = String(data.courierPhone || '');
    const courierDigits = assertCourierPhone(courierPhone);
    if (canonicalUid(callerPhone(context)) !== canonicalUid(courierDigits)) {
      throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
    }
    const courierId = await resolveAuthorizedCourierUid(courierPhone);

    // Аллақачон фаол маршрут борми?
    const activeSnap = await db.collection('delivery_routes')
      .where('courierId', '==', courierId)
      .where('status', '==', 'active')
      .limit(1)
      .get();
    if (!activeSnap.empty) {
      return { revived: false, routeId: activeSnap.docs[0].id, reason: 'has_active' };
    }

    // Етим буюртмалар: in_delivery & тўланмаган & шу курьерники.
    const odSnap = await db.collection('orders')
      .where('status', '==', 'in_delivery')
      .get();
    const orphanIds = [];
    odSnap.forEach((doc) => {
      const od = doc.data() || {};
      const cid = canonicalUid(String(od.courierId || od.courierPhone || ''));
      if (cid !== canonicalUid(courierId)) return;
      if (od.paymentStatus === 'paid') return;
      orphanIds.push(doc.id);
    });

    if (orphanIds.length === 0) {
      return { revived: false, count: 0 };
    }

    const routeRef = db.collection('delivery_routes').doc();
    await routeRef.set({
      orders: orphanIds,
      courierId,
      status: 'active',
      currentIndex: 0,
      routeSource: 'auto_recover',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const batch = db.batch();
    for (const id of orphanIds) {
      batch.update(db.collection('orders').doc(id), {
        courierId,
        deliveryRouteId: routeRef.id,
        statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    return { revived: true, routeId: routeRef.id, count: orphanIds.length };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('courierRecoverOrphanRoute:', e.message || e);
    throw new functions.https.HttpsError('internal', e.message || 'recover failed');
  }
});

exports.courierMarkArrived = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }
  const orderId = String(data.orderId || '');
  const courierId = assertCourierPhone(data.courierPhone);
  if (callerPhone(context) !== courierId) {
    throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
  }
  const lat = data.lat != null ? Number(data.lat) : null;
  const lng = data.lng != null ? Number(data.lng) : null;
  const { ref, data: od } = await loadOrderOrThrow(orderId);
  const fs = od.fulfillmentStatus || '';
  if (fs !== 'courier_picked' && od.status !== 'in_delivery') {
    throw new functions.https.HttpsError('failed-precondition', 'pick first');
  }
  await ref.update({
    fulfillmentStatus: 'arrived',
    status: 'in_delivery',
    courierId,
    arrivedAt: admin.firestore.FieldValue.serverTimestamp(),
    statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await ref.collection('payment_events').add({
    action: 'courier_arrived',
    actorType: 'courier',
    actorId: courierId,
    lat: Number.isFinite(lat) ? lat : null,
    lng: Number.isFinite(lng) ? lng : null,
    at: admin.firestore.FieldValue.serverTimestamp(),
  });

  try {
    const customerPhone = od.userPhone || od.phone || '';
    await notifyCourierArrivedToCustomer(customerPhone, {
      orderId,
      module: 'orders',
    });
  } catch (e) {
    console.error('courierMarkArrived notify:', e.message || e);
  }

  return { ok: true };
});

/** Курьер: мижоз кошелёк қолдиғи (Firestore rules курьерга users o'qishni taqiqlaydi). */
exports.courierGetCustomerWalletBalance = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Login required');
    }

    const courierPhone = String(data.courierPhone || '');
    const customerPhone = String(data.customerPhone || '');
    const courierDigits = assertCourierPhone(courierPhone);
    const caller = callerPhone(context);
    if (canonicalUid(caller) !== canonicalUid(courierDigits)) {
      throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
    }

    await resolveAuthorizedCourierUid(courierPhone);

    if (!customerPhone.trim()) {
      throw new functions.https.HttpsError('invalid-argument', 'customerPhone required');
    }

    const uid9 = userUid(customerPhone);
    const uid12 = canonicalUid(customerPhone);
    let customerRef = db.collection('users').doc(uid12);
    let userSnap = await customerRef.get();
    if (!userSnap.exists && uid9 !== uid12) {
      customerRef = db.collection('users').doc(uid9);
      userSnap = await customerRef.get();
    }

    const bonusBalance = userSnap.exists
      ? parseInt(String(userSnap.data()?.bonusBalance ?? 0), 10) || 0
      : 0;

    return { bonusBalance, uid: customerRef.id };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('courierGetCustomerWalletBalance:', e.message || e);
    throw new functions.https.HttpsError(
      'internal',
      e.message || 'Failed to fetch wallet balance',
    );
  }
});

exports.courierSubmitPayment = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }
  const orderId = String(data.orderId || '');
  const courierId = assertCourierPhone(data.courierPhone);
  if (callerPhone(context) !== courierId) {
    throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
  }
  const linesIn = Array.isArray(data.lines) ? data.lines : [];
  const lat = data.lat != null ? Number(data.lat) : null;
  const lng = data.lng != null ? Number(data.lng) : null;

  const { ref, data: od } = await loadOrderOrThrow(orderId);
  const fs = od.fulfillmentStatus || '';
  if (fs !== 'arrived') {
    throw new functions.https.HttpsError('failed-precondition', 'arrived first');
  }
  if (od.paymentStatus === 'payment_pending_confirm') {
    throw new functions.https.HttpsError('failed-precondition', 'already_paid');
  }

  const orderTotal = parseInt(String(od.total ?? od.grandTotal ?? 0), 10);
  if (!Number.isFinite(orderTotal) || orderTotal <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'invalid order total');
  }
  const preApplied = Math.max(0, Math.trunc(Number(od.balanceApplied || 0)));
  const remainingDue = Math.max(0, orderTotal - preApplied);
  const alreadyPaidWallet = od.paymentStatus === 'paid' && remainingDue <= 0;

  // Буюртма вақтида ҳамён тўлиқ ёпилган — фақат етказишни якунлаш.
  if (alreadyPaidWallet || remainingDue <= 0) {
    if (od.paymentStatus === 'paid' && String(od.fulfillmentStatus) === 'completed') {
      throw new functions.https.HttpsError('failed-precondition', 'already_paid');
    }
    await ref.update({
      paymentStatus: 'paid',
      paymentMethod: od.paymentMethod || 'wallet',
      paidAmount: orderTotal,
      cashPaid: Math.trunc(Number(od.cashPaid || 0)),
      balanceApplied: Math.max(preApplied, orderTotal),
      cashDue: 0,
      fulfillmentStatus: 'completed',
      status: 'delivered',
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
      courierId: od.courierId || courierId,
      statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      paidByCourierId: courierId,
      paidAt: od.paidAt || admin.firestore.FieldValue.serverTimestamp(),
    });
    return {
      ok: true,
      orderId,
      orderTotal,
      prepaid: true,
      balanceApplied: Math.max(preApplied, orderTotal),
      changeCredit: 0,
    };
  }

  if (od.paymentStatus === 'paid') {
    throw new functions.https.HttpsError('failed-precondition', 'already_paid');
  }

  if (linesIn.length < 1 || linesIn.length > 20) {
    throw new functions.https.HttpsError('invalid-argument', 'lines required');
  }

  const normalized = [];
  for (let i = 0; i < linesIn.length; i += 1) {
    const row = linesIn[i] || {};
    const kind = String(row.kind || '').toLowerCase();
    if (!['cash', 'card', 'product', 'wallet'].includes(kind)) {
      throw new functions.https.HttpsError('invalid-argument', 'bad line kind');
    }
    const unitPrice = parseInt(String(row.unitPrice ?? 0), 10);
    const qty = Number(row.qty ?? 1);
    const amount = parseInt(String(row.amount ?? 0), 10);
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new functions.https.HttpsError('invalid-argument', 'bad amount');
    }
    if (kind === 'product') {
      if (!Number.isFinite(qty) || qty <= 0) {
        throw new functions.https.HttpsError('invalid-argument', 'bad product qty');
      }
      if (!Number.isFinite(unitPrice) || unitPrice <= 0) {
        throw new functions.https.HttpsError('invalid-argument', 'bad product unitPrice');
      }
      const expectedAmount = Math.round(qty * unitPrice);
      if (Math.abs(amount - expectedAmount) > 1) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          `product amount ${amount} != qty*unitPrice ${expectedAmount}`,
        );
      }
    }
    normalized.push({
      kind,
      productCode: String(row.productCode || ''),
      productLabel: String(row.productLabel || ''),
      qty: Number.isFinite(qty) ? qty : 1,
      unit: String(row.unit || ''),
      unitPrice: Number.isFinite(unitPrice) ? unitPrice : 0,
      suggestedUnitPrice: parseInt(String(row.suggestedUnitPrice ?? unitPrice), 10) || 0,
      amount,
      createdByCourierId: courierId,
      createdAt: admin.firestore.Timestamp.now(),
    });
  }

  const totalSubmitted = paymentLinesTotal(normalized);
  if (totalSubmitted < remainingDue - 1) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `Underpaid: ${totalSubmitted} < ${remainingDue}`,
    );
  }
  const paidSum = totalSubmitted;
  const changeCredit = Math.max(0, totalSubmitted - remainingDue);

  const userPhone = String(od.userPhone || od.phone || '');
  const uid9 = userUid(userPhone);
  const uid12 = canonicalUid(userPhone);
  let customerRef = db.collection('users').doc(uid12);
  let userSnap = await customerRef.get();
  if (!userSnap.exists && uid9 !== uid12) {
    customerRef = db.collection('users').doc(uid9);
    userSnap = await customerRef.get();
  }
  if (!userSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'customer user not found');
  }

  const walletSum = normalized
    .filter((l) => l.kind === 'wallet')
    .reduce((s, l) => s + (parseInt(String(l.amount || 0), 10) || 0), 0);

  if (walletSum > 0) {
    const prevBalance = parseInt(String(userSnap.data()?.bonusBalance ?? 0), 10) || 0;
    if (prevBalance < walletSum) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        `insufficient_balance: balance ${prevBalance}, required ${walletSum}`,
      );
    }
    const nonWalletSum = totalSubmitted - walletSum;
    const walletCap = remainingDue - nonWalletSum;
    if (walletSum > walletCap + 1) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        `wallet_overpay: wallet ${walletSum} > remaining due ${walletCap}`,
      );
    }
  }

  const module = od.type === 'food' ? 'food' : 'bread';
  const batch = db.batch();
  for (let i = 0; i < normalized.length; i += 1) {
    const lineRef = ref.collection('payment_lines').doc();
    batch.set(lineRef, normalized[i]);
  }
  const orderPatch = {
    paymentStatus: 'paid',
    paymentMethod: resolvePaymentMethod(normalized),
    paidAmount: paidSum,
    paidByCourierId: courierId,
    paidAt: admin.firestore.FieldValue.serverTimestamp(),
    paidLat: Number.isFinite(lat) ? lat : null,
    paidLng: Number.isFinite(lng) ? lng : null,
    customerConfirmed: true,
    customerConfirmedAt: admin.firestore.FieldValue.serverTimestamp(),
    cashPaid: paidSum,
    fulfillmentStatus: 'completed',
    status: 'delivered',
    completedAt: admin.firestore.FieldValue.serverTimestamp(),
    deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
    courierId: od.courierId || courierId,
    statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (changeCredit > 0) {
    orderPatch.changeCredited = changeCredit;
  }
  orderPatch.balanceApplied = preApplied + walletSum;
  orderPatch.cashDue = 0;
  batch.update(ref, orderPatch);
  batch.set(ref.collection('payment_events').doc(), {
    action: 'courier_submit_payment',
    actorType: 'courier',
    actorId: courierId,
    payload: { lines: normalized, paidSum, changeCredit, preApplied, remainingDue },
    lat: Number.isFinite(lat) ? lat : null,
    lng: Number.isFinite(lng) ? lng : null,
    at: admin.firestore.FieldValue.serverTimestamp(),
  });
  batch.set(ref.collection('payment_events').doc(), {
    action: 'courier_completed',
    actorType: 'courier',
    actorId: courierId,
    lat: Number.isFinite(lat) ? lat : null,
    lng: Number.isFinite(lng) ? lng : null,
    at: admin.firestore.FieldValue.serverTimestamp(),
  });
  for (let i = 0; i < normalized.length; i += 1) {
    const line = normalized[i];
    const kind = String(line.kind || '');
    const amount = parseInt(String(line.amount || 0), 10);
    if (!Number.isFinite(amount) || amount <= 0) continue;
    const ledgerRef = customerRef.collection('wallet_ledger').doc();
    if (kind === 'product') {
      batch.set(ledgerRef, {
        type: 'order_payment_product',
        amount,
        module,
        refType: 'order',
        refId: orderId,
        meta: {
          productCode: line.productCode || '',
          productLabel: line.productLabel || '',
          qty: line.qty,
          unit: line.unit,
          unitPrice: line.unitPrice,
          debitCredit: 'none',
          note: 'in_kind_payment',
          pending: false,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: 'courier_submit',
      });
    } else if (kind !== 'wallet') {
      batch.set(ledgerRef, {
        type: kind === 'card' ? 'order_payment_card' : 'order_payment_cash',
        amount: 0,
        module,
        refType: 'order',
        refId: orderId,
        meta: {
          paidAmount: amount,
          debitCredit: 'debit',
          note: `${kind} тўлов тасдиқланди`,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: 'courier_submit',
      });
    }
  }
  if (walletSum > 0) {
    batch.update(customerRef, {
      bonusBalance: admin.firestore.FieldValue.increment(-walletSum),
      balanceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    const walletDebitRef = customerRef.collection('wallet_ledger').doc();
    batch.set(walletDebitRef, {
      type: 'purchase_debit',
      amount: -walletSum,
      module,
      refType: 'order',
      refId: orderId,
      meta: { orderTotal },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: 'courier_submit',
    });
  }
  if (changeCredit > 0) {
    batch.update(customerRef, {
      bonusBalance: admin.firestore.FieldValue.increment(changeCredit),
      balanceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    const ledgerRef = customerRef.collection('wallet_ledger').doc();
    batch.set(ledgerRef, {
      type: 'change_accrued',
      amount: changeCredit,
      module,
      refType: 'order',
      refId: orderId,
      meta: { orderTotal, paidSum: totalSubmitted },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: 'courier_submit',
    });
  }

  // Ledger ko'zgusi (batch, increment orqali atomar) — net = changeCredit - walletSum.
  const bonusDelta = changeCredit - walletSum;
  if (bonusDelta !== 0) {
    settlementLedger.commitBonusInBatch(batch, db, {
      uid: customerRef.id,
      delta: bonusDelta,
      kind: 'order_courier_submit',
      idempotencyKey: `courier_submit_${orderId}`,
      refType: 'order',
      refId: orderId,
      meta: { module, orderTotal, walletSum, changeCredit },
      postedBy: 'courier_submit',
      postedRole: 'courier',
    });
  }

  await batch.commit();

  const customerUid = customerRef.id;
  let cashSum = 0;
  let cardSum = 0;
  const productLines = [];
  for (let i = 0; i < normalized.length; i += 1) {
    const line = normalized[i];
    const kind = String(line.kind || '').toLowerCase();
    const amount = parseInt(String(line.amount || 0), 10);
    if (kind === 'cash') cashSum += amount;
    else if (kind === 'card') cardSum += amount;
    else if (kind === 'product') productLines.push(line);
  }

  // Курьер қўлидаги нақд/карта → courier_cash (инкассациягача).
  // Ҳисоб калити ҳар доим 12 рақам (998…) — receiveCourierCash билан мос.
  const fieldCash = cashSum + cardSum;
  if (fieldCash > 0) {
    try {
      const courierCashUid = canonicalUid(courierId);
      await settlementLedger.postEntry(db, {
        idempotencyKey: `courierCash:${orderId}`,
        kind: 'courier_field_cash',
        refType: 'order',
        refId: orderId,
        postedBy: courierCashUid,
        postedRole: 'courier',
        legs: [
          {
            account: settlementLedger.courierCashAccount(courierCashUid),
            dr: fieldCash,
          },
          { account: 'admin_clearing', cr: fieldCash },
        ],
      }, {
        mirrorBonus: false,
        meta: {
          module,
          orderTotal,
          cashSum,
          cardSum,
          method: cardSum > 0 && cashSum > 0
            ? 'mixed'
            : (cardSum > 0 ? 'card' : 'cash'),
        },
      });
    } catch (e) {
      console.error('courierSubmitPayment courier_cash ledger:', e.message || e);
    }
  }

  let newBalance = 0;
  try {
    const balSnap = await customerRef.get();
    newBalance = parseInt(String(balSnap.data()?.bonusBalance ?? 0), 10) || 0;
  } catch (_) {}

  const receiptLines = [];
  receiptLines.push(
    `Буюртма ${orderTotal} сўм — қабул қилинди ва тўланди.${
      changeCredit > 0 ? ` Қайтим ${changeCredit} сўм кошелёкка.` : ''
    }`,
  );
  receiptLines.push('Тўлов турлари:');
  if (walletSum > 0) receiptLines.push(`  💼 Кошелёкдан: ${walletSum} сўм`);
  if (cashSum > 0) receiptLines.push(`  💵 Нақд: ${cashSum} сўм`);
  if (cardSum > 0) receiptLines.push(`  💳 Карта: ${cardSum} сўм`);
  if (productLines.length > 0) {
    receiptLines.push('  📦 Маҳсулотлар:');
    for (let i = 0; i < productLines.length; i += 1) {
      const p = productLines[i];
      const label = String(p.productLabel || p.productCode || 'Маҳсулот');
      const unit = String(p.unit || '').trim();
      receiptLines.push(
        `     • ${label}: ${p.qty}${unit ? ` ${unit}` : ''} × ${p.unitPrice} = ${p.amount} сўм`,
      );
    }
  }
  receiptLines.push(`Жами тўланди: ${totalSubmitted} сўм`);
  if (walletSum > 0 || changeCredit > 0) {
    const oldBalance = newBalance + walletSum - changeCredit;
    receiptLines.push('💼 Мижоз кошелёги:');
    receiptLines.push(`  💼 Эски қолдиқ: ${oldBalance} сўм`);
    if (changeCredit > 0) {
      receiptLines.push(`  🔁 Қайтим (+): ${changeCredit} сўм`);
    }
    if (walletSum > 0) {
      receiptLines.push(`  💼 Кошелёкдан (−): ${walletSum} сўм`);
    }
    receiptLines.push(`  💼 Янги қолдиқ: ${newBalance} сўм`);
  }
  receiptLines.push('✅ Битим якунланди.');

  try {
    await notifyUserInApp({
      userId: customerUid,
      title: '✅ Буюртма якунланди',
      body: receiptLines.join('\n'),
      category: 'order',
      source: 'payment_receipt',
      dataType: 'order_payment',
      screen: 'profile',
      extraData: { orderId, changeCredited: String(changeCredit) },
    });
  } catch (e) {
    console.error('courierSubmitPayment receipt push:', e.message || e);
  }

  return {
    ok: true,
    orderTotal,
    totalSubmitted,
    changeCredit,
    walletDebited: walletSum,
    newBalance,
  };
});

exports.requestPayout = functions.https.onCall(async (data, context) => {
  const userPhone = String(data.userPhone || '');
  const amount = parseInt(String(data.amount ?? 0), 10);
  const idempotencyKey = String(data.idempotencyKey || '').trim();

  if (!idempotencyKey) {
    throw new functions.https.HttpsError('invalid-argument', 'idempotencyKey required');
  }
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'amount must be positive');
  }

  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated',
      'Login required');
  }
  const callerPhone = String(
    context.auth.token.phone_number || '').replace(/\D/g, '');
  const callerUid = String(context.auth.uid || '');
  const targetUid = userUid(userPhone);
  if (callerPhone !== targetUid && callerUid !== targetUid) {
    throw new functions.https.HttpsError('permission-denied',
      'Can only request payout for your own account');
  }

  const uid = userUid(userPhone);
  const idemRef = db.collection('wallet_idempotency').doc(idempotencyKey);

  const existing = await idemRef.get();
  if (existing.exists) {
    return existing.data().result || { ok: true, duplicate: true };
  }

  const userSnap = await db.collection('users').doc(uid).get();
  if (!userSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'user not found');
  }
  const userData = userSnap.data() || {};
  if (!payoutKycOk(userData)) {
    throw new functions.https.HttpsError(
        'failed-precondition',
        'Payout KYC talab qilinadi — profil yoki admin tasdiqlashini yakunlang');
  }
  const bal = userData.bonusBalance || 0;
  if (bal < amount) {
    throw new functions.https.HttpsError('failed-precondition', 'insufficient_balance');
  }

  const settings = await getAnomalySettings();
  if (amount > settings.maxWithdrawalPerUser) {
    throw new functions.https.HttpsError(
        'failed-precondition',
        `Bir martada ${settings.maxWithdrawalPerUser.toLocaleString('uz-UZ')} so'mdan ko'p`);
  }
  const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
  const totalWithdrawn = await sumRecentWithdrawals(uid, oneHourAgo);
  if (totalWithdrawn + amount > settings.maxWithdrawalPerHour) {
    throw new functions.https.HttpsError(
        'failed-precondition',
        `1 soat ichida ${settings.maxWithdrawalPerHour.toLocaleString('uz-UZ')} so'mdan ko'p`);
  }

  const reqRef = db.collection('payout_requests').doc();
  await db.runTransaction(async (t) => {
    const idemSnap = await t.get(idemRef);
    if (idemSnap.exists) return;

    t.set(reqRef, {
      userPhone: uid,
      amount,
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    t.set(idemRef, {
      type: 'requestPayout',
      result: { ok: true, requestId: reqRef.id },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { ok: true, requestId: reqRef.id };
});

/** Админ: нақд чиқаришни тасдиқлаш */
exports.confirmPayout = functions.https.onCall(async (data, context) => {
  const adminUid = await requireCallerRoles(
    context,
    ['admin', 'superadmin', 'dispatcher'],
    'Admin role required',
  );

  const requestId = String(data.requestId || '');
  if (!requestId) {
    throw new functions.https.HttpsError('invalid-argument', 'requestId required');
  }

  const reqRef = db.collection('payout_requests').doc(requestId);
  const idempotencyKey = `payout_confirm_${requestId}`;
  const idemRef = db.collection('wallet_idempotency').doc(idempotencyKey);

  const existing = await idemRef.get();
  if (existing.exists) {
    return existing.data().result || { ok: true, duplicate: true };
  }

  await db.runTransaction(async (t) => {
    const idemSnap = await t.get(idemRef);
    if (idemSnap.exists) return;

    const reqSnap = await t.get(reqRef);
    if (!reqSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'request not found');
    }
    const req = reqSnap.data();
    if (req.status !== 'pending') {
      throw new functions.https.HttpsError('failed-precondition', 'not pending');
    }

    const uid = String(req.userPhone || '');
    const amount = parseInt(String(req.amount || 0), 10);
    const userRef = db.collection('users').doc(uid);
    const userSnap = await t.get(userRef);
    const userData = userSnap.exists ? (userSnap.data() || {}) : {};
    if (!payoutKycOk(userData)) {
      throw new functions.https.HttpsError(
          'failed-precondition',
          'Payout KYC talab qilinadi — profil yoki admin tasdiqlashini yakunlang');
    }
    const prev = userData.bonusBalance || 0;
    if (prev < amount) {
      throw new functions.https.HttpsError('failed-precondition', 'insufficient_balance');
    }
    const next = prev - amount;
    const ledgerId = db.collection('users').doc(uid).collection('wallet_ledger').doc().id;

    // Ledger ko'zgusi (READ fazasi) — naqd echish: funding = admin_cash.
    const bonusCtx = await settlementLedger.prepareBonusInTx(t, db, uid, {
      idempotencyKey,
      fundingAccount: 'admin_cash',
    });

    t.set(userRef, {
      bonusBalance: next,
      balanceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    t.set(userRef.collection('wallet_ledger').doc(ledgerId), {
      type: 'payout_paid',
      amount: -amount,
      module: 'admin',
      refType: 'payout_request',
      refId: requestId,
      meta: {},
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: adminUid,
    });

    // Ledger ko'zgusi (WRITE fazasi) — Dr passenger_credit / Cr admin_cash.
    settlementLedger.commitBonusInTx(t, bonusCtx, {
      delta: -amount,
      kind: 'payout_paid',
      refType: 'payout_request',
      refId: requestId,
      meta: { module: 'admin' },
      postedBy: adminUid,
      postedRole: 'admin',
    });

    t.update(reqRef, {
      status: 'completed',
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
      processedBy: adminUid,
    });

    t.set(idemRef, {
      type: 'confirmPayout',
      result: { ok: true, ledgerId },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { ok: true };
});

// ════════════════════════════════════════════════════════════════
// АНОМАЛИЯ ДЕТЕКТОРИ — settings/anomaly_settings
// ════════════════════════════════════════════════════════════════

const ANOMALY_SETTINGS_DEFAULTS = {
  anomalyAmountThreshold: 100000,
  maxWithdrawalPerUser: 1000000,
  maxWithdrawalPerHour: 1000000,
  anomalyNotificationEnabled: true,
};

const WITHDRAWAL_LEDGER_TYPES = new Set(['purchase_debit', 'payout_paid']);

async function getAnomalySettings() {
  const doc = await db.collection('settings').doc('anomaly_settings').get();
  if (!doc.exists) {
    return { ...ANOMALY_SETTINGS_DEFAULTS };
  }
  const d = doc.data() || {};
  return {
    anomalyAmountThreshold: Number(d.anomalyAmountThreshold)
      || ANOMALY_SETTINGS_DEFAULTS.anomalyAmountThreshold,
    maxWithdrawalPerUser: Number(d.maxWithdrawalPerUser)
      || ANOMALY_SETTINGS_DEFAULTS.maxWithdrawalPerUser,
    maxWithdrawalPerHour: Number(d.maxWithdrawalPerHour)
      || ANOMALY_SETTINGS_DEFAULTS.maxWithdrawalPerHour,
    anomalyNotificationEnabled: d.anomalyNotificationEnabled !== false,
  };
}

async function sendAnomalyTelegramMessage(text) {
  const cfg = (typeof functions.config === 'function' && functions.config().telegram) || {};
  const token = String(process.env.TELEGRAM_BOT_TOKEN || cfg.bot_token || '').trim();
  const chatId = String(process.env.TELEGRAM_ADMIN_CHAT_ID || cfg.admin_chat_id || '').trim();
  if (!token || !chatId) {
    console.log('anomaly telegram skipped (no bot token/chat id)');
    return false;
  }
  try {
    await axios.post(
      `https://api.telegram.org/bot${token}/sendMessage`,
      { chat_id: chatId, text, parse_mode: 'HTML' },
      { timeout: 15000 },
    );
    return true;
  } catch (err) {
    console.error('anomaly telegram error:', err.message || err);
    return false;
  }
}

async function sumRecentWithdrawals(userId, oneHourAgo) {
  const snap = await db.collection('users').doc(userId)
    .collection('wallet_ledger')
    .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(oneHourAgo))
    .get();
  let total = 0;
  snap.forEach((doc) => {
    const d = doc.data();
    if (!WITHDRAWAL_LEDGER_TYPES.has(String(d.type || ''))) return;
    total += Math.abs(Number(d.amount || 0));
  });
  return total;
}

/** Callable: бир марта / 1 соатлик чиқим лимитини текшириш. */
exports.checkWithdrawalLimit = functions.https.onCall(async (data, context) => {
  const userId = userUid(String(data.userId || data.userPhone || ''));
  const amount = parseInt(String(data.amount ?? 0), 10);
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'amount must be positive');
  }

  const settings = await getAnomalySettings();

  if (amount > settings.maxWithdrawalPerUser) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      `Бир мартада ${settings.maxWithdrawalPerUser.toLocaleString('uz-UZ')} сўмдан кўп ечиб бўлмайди`,
    );
  }

  const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
  const totalWithdrawn = await sumRecentWithdrawals(userId, oneHourAgo);
  if (totalWithdrawn + amount > settings.maxWithdrawalPerHour) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      `1 соат ичида ${settings.maxWithdrawalPerHour.toLocaleString('uz-UZ')} сўмдан кўп ечиб бўлмайди`,
    );
  }

  return { allowed: true, settings };
});

/** wallet_ledger яратилганда катта сумма — risk_events + Telegram. */
exports.detectAnomaly = functions.firestore
  .document('users/{userId}/wallet_ledger/{ledgerId}')
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const amount = Math.abs(Number(data.amount || 0));
    const userId = context.params.userId;
    const ledgerId = context.params.ledgerId;
    const settings = await getAnomalySettings();

    if (amount < settings.anomalyAmountThreshold) {
      return null;
    }

    const ledgerType = String(data.type || '');
    const createdBy = String(data.createdBy || '');
    const message = `Аномалия: ${amount.toLocaleString('uz-UZ')} сўм (${ledgerType})`;

    await db.collection('risk_events').add({
      userId,
      type: 'wallet_anomaly',
      severity: 'high',
      status: 'open',
      deviceId: '',
      message,
      meta: {
        ledgerId,
        amount,
        threshold: settings.anomalyAmountThreshold,
        ledgerType,
        createdBy,
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (!settings.anomalyNotificationEnabled) {
      return null;
    }

    const tgText = [
      '⚠️ <b>Аномалия (кошелёк)</b>',
      `User: <code>${userId}</code>`,
      `Сумма: <b>${amount.toLocaleString('uz-UZ')}</b> сўм`,
      `Тип: ${ledgerType}`,
      `Чеги: ${settings.anomalyAmountThreshold.toLocaleString('uz-UZ')} сўм`,
    ].join('\n');
    await sendAnomalyTelegramMessage(tgText);
    return null;
  });

/** Админ: birthday bonus (client Firestore patch ўрнига). */
exports.grantBirthdayBonus = functions.https.onCall(async (data, context) => {
  const adminUid = await requireCallerRoles(
    context,
    ['admin', 'superadmin', 'dispatcher'],
    'Admin role required',
  );

  const uid = userUid(String(data.uid || data.userPhone || ''));
  const year = parseInt(String(data.year ?? 0), 10);
  const amount = parseInt(String(data.amount ?? 0), 10);
  const operatorPhone = String(data.operatorPhone || adminUid);

  if (!Number.isFinite(year) || year < 2000 || year > 2100) {
    throw new functions.https.HttpsError('invalid-argument', 'invalid year');
  }
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'amount must be positive');
  }

  const userRef = db.collection('users').doc(uid);
  const claimRef = userRef.collection('birthday_bonus_claims').doc(String(year));
  const ledgerRef = userRef.collection('wallet_ledger').doc(`birthday_${year}`);
  const idemKey = `birthday_${uid}_${year}`;
  const idemRef = db.collection('wallet_idempotency').doc(idemKey);

  const existing = await idemRef.get();
  if (existing.exists) {
    return existing.data().result || { ok: true, duplicate: true };
  }

  let txDup = null;
  const out = await db.runTransaction(async (t) => {
    const idemSnap = await t.get(idemRef);
    if (idemSnap.exists) {
      txDup = idemSnap.data().result;
      return null;
    }
    const claimSnap = await t.get(claimRef);
    if (claimSnap.exists) {
      throw new functions.https.HttpsError(
        'already-exists',
        'birthday_bonus_already_claimed',
      );
    }
    const userSnap = await t.get(userRef);
    const prev = (userSnap.data() && userSnap.data().bonusBalance) || 0;
    const next = prev + amount;

    // Ledger ko'zgusi (READ fazasi) — claim/ledger yozuvlaridan OLDIN.
    const bonusCtx = await settlementLedger.prepareBonusInTx(t, db, uid, {
      idempotencyKey: idemKey,
    });

    t.set(claimRef, {
      year,
      amount,
      status: 'granted',
      operatorPhone: digits(operatorPhone),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    t.set(ledgerRef, {
      type: 'birthday_bonus',
      amount,
      module: 'loyalty',
      refType: 'birthday_bonus',
      refId: String(year),
      meta: { year, operatorPhone: digits(operatorPhone), note: 'Birthday bonus' },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: adminUid,
    });
    t.set(userRef, {
      bonusBalance: next,
      birthdayBonusLastYear: year,
      balanceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    // Ledger ko'zgusi (WRITE fazasi) — Dr admin_clearing / Cr passenger_credit.
    settlementLedger.commitBonusInTx(t, bonusCtx, {
      delta: amount,
      kind: 'birthday_bonus',
      refType: 'birthday_bonus',
      refId: String(year),
      meta: { module: 'loyalty', year },
      postedBy: adminUid,
      postedRole: 'admin',
    });

    const result = { ok: true, credited: amount, year, uid };
    t.set(idemRef, {
      type: 'grantBirthdayBonus',
      result,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return result;
  });

  if (txDup) return txDup;
  return out;
});

/** Админ: мой/фильтр каталоги upsert (client isAdmin() ишончсиз). */
exports.adminUpsertOilCatalogItem = functions.https.onCall(async (data, context) => {
  if (!context || !context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }
  const adminPhone = String((data && data.adminPhone) || '');
  await assertOilCatalogEditor(adminPhone, context);

  const idIn = String((data && data.id) || '').trim();
  const name = String((data && data.name) || '').trim();
  const price = parseInt(String((data && data.price) ?? ''), 10);
  if (!name) {
    throw new functions.https.HttpsError('invalid-argument', 'name required');
  }
  if (!Number.isFinite(price) || price < 0) {
    throw new functions.https.HttpsError('invalid-argument', 'price required');
  }

  const kind = String((data && data.kind) || 'oil') === 'filter' ? 'filter' : 'oil';
  const ref = idIn
    ? db.collection('oil_change_catalog').doc(idIn)
    : db.collection('oil_change_catalog').doc();

  const payload = {
    kind,
    name,
    meta: String((data && data.meta) || ''),
    reason: String((data && data.reason) || ''),
    price,
    imageUrl: String((data && data.imageUrl) || ''),
    specs: (data && data.specs && typeof data.specs === 'object') ? data.specs : {},
    sortOrder: parseInt(String((data && data.sortOrder) ?? '0'), 10) || 0,
    active: data && data.active === false ? false : true,
    must: !!(data && data.must),
    dust: !!(data && data.dust),
    gas: !!(data && data.gas),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  const existing = await ref.get();
  if (!existing.exists) {
    payload.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }
  await ref.set(payload, { merge: true });
  return { ok: true, id: ref.id };
});

exports.adminDeleteOilCatalogItem = functions.https.onCall(async (data, context) => {
  if (!context || !context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }
  await assertOilCatalogEditor(String((data && data.adminPhone) || ''), context);
  const id = String((data && data.id) || '').trim();
  if (!id) {
    throw new functions.https.HttpsError('invalid-argument', 'id required');
  }
  await db.collection('oil_change_catalog').doc(id).delete();
  return { ok: true };
});

exports.adminSeedOilCatalog = functions.https.onCall(async (data, context) => {
  if (!context || !context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }
  await assertOilCatalogEditor(String((data && data.adminPhone) || ''), context);

  const col = db.collection('oil_change_catalog');
  const existing = await col.limit(1).get();
  if (!existing.empty) {
    return { ok: true, seeded: 0, message: 'already_exists' };
  }

  const items = Array.isArray(data && data.items) ? data.items : [];
  if (!items.length) {
    throw new functions.https.HttpsError('invalid-argument', 'items required');
  }

  const batch = db.batch();
  let n = 0;
  for (const raw of items) {
    const id = String((raw && raw.id) || '').trim();
    if (!id) continue;
    const ref = col.doc(id);
    batch.set(ref, {
      kind: String((raw && raw.kind) || 'oil') === 'filter' ? 'filter' : 'oil',
      name: String((raw && raw.name) || id),
      meta: String((raw && raw.meta) || ''),
      reason: String((raw && raw.reason) || ''),
      price: parseInt(String((raw && raw.price) ?? '0'), 10) || 0,
      imageUrl: '',
      specs: (raw && raw.specs && typeof raw.specs === 'object') ? raw.specs : {},
      sortOrder: n,
      active: true,
      must: !!(raw && raw.must),
      dust: !!(raw && raw.dust),
      gas: !!(raw && raw.gas),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    n += 1;
  }
  await batch.commit();
  return { ok: true, seeded: n };
});

async function assertOilCatalogEditor(operatorPhone, context) {
  if (!context || !context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }
  const tokenPhone = String(
    context.auth.token.phone_number || '').replace(/\D/g, '');
  const opDigits = digits(operatorPhone);
  const phoneForLookup = opDigits || tokenPhone;
  if (!phoneForLookup) {
    throw new functions.https.HttpsError('invalid-argument', 'operatorPhone');
  }
  if (opDigits && tokenPhone) {
    const canonOp = canonicalUid(opDigits);
    const canonTok = canonicalUid(tokenPhone);
    if (canonOp !== canonTok && opDigits !== tokenPhone) {
      throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
    }
  }
  const found = await findUserDocByPhone(phoneForLookup);
  if (!found) {
    throw new functions.https.HttpsError('permission-denied', 'User not found');
  }
  const role = (found.snap.data() || {}).role || 'user';
  if (!['admin', 'superadmin', 'dispatcher', 'finance', 'auditor'].includes(role)) {
    throw new functions.https.HttpsError('permission-denied', 'Not allowed');
  }
  return found.docId;
}

/** Foydalanuvchi: profil avtomobilini birinchi marta to'liq kiritganda bonus. */
exports.claimCarProfileBonus = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const caller = callerPhone(context);
  const uid = userUid(caller);
  if (!uid || uid.length < 9) {
    throw new functions.https.HttpsError('permission-denied', 'Phone required');
  }

  const amountDefault = 5000;
  let amount = amountDefault;
  try {
    const settingsSnap = await db.collection('settings').doc('oil_change').get();
    const raw = settingsSnap.exists ? settingsSnap.data().carProfileBonusAmount : null;
    const parsed = parseInt(String(raw ?? amountDefault), 10);
    if (Number.isFinite(parsed) && parsed > 0 && parsed <= 100000) {
      amount = parsed;
    }
  } catch (_) {}

  const userRef = db.collection('users').doc(uid);
  const claimRef = userRef.collection('car_profile_bonus_claims').doc('v1');
  const ledgerRef = userRef.collection('wallet_ledger').doc('car_profile_bonus_v1');
  const idemKey = `car_profile_bonus_${uid}_v1`;
  const idemRef = db.collection('wallet_idempotency').doc(idemKey);

  const existing = await idemRef.get();
  if (existing.exists) {
    return existing.data().result || { ok: true, duplicate: true };
  }

  let txDup = null;
  const out = await db.runTransaction(async (t) => {
    const idemSnap = await t.get(idemRef);
    if (idemSnap.exists) {
      txDup = idemSnap.data().result;
      return null;
    }
    const claimSnap = await t.get(claimRef);
    if (claimSnap.exists) {
      const result = { ok: true, duplicate: true, credited: 0, uid };
      t.set(idemRef, {
        type: 'claimCarProfileBonus',
        result,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return result;
    }

    const userSnap = await t.get(userRef);
    if (!userSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'user not found');
    }
    const ud = userSnap.data() || {};
    const model = String(ud.carModel || '').trim();
    const color = String(ud.carColor || '').trim();
    const plate = String(ud.carPlate || '').trim();
    const seats = parseInt(String(ud.carSeats ?? 0), 10) || 0;
    if (!model || !color || !plate || seats <= 0) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'car_profile_incomplete',
      );
    }

    const prev = (ud.bonusBalance) || 0;
    const next = prev + amount;

    const bonusCtx = await settlementLedger.prepareBonusInTx(t, db, uid, {
      idempotencyKey: idemKey,
    });

    t.set(claimRef, {
      amount,
      status: 'granted',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    t.set(ledgerRef, {
      type: 'car_profile_bonus',
      amount,
      module: 'oil_change',
      refType: 'car_profile_bonus',
      refId: 'v1',
      meta: { note: 'Profil avtomobili bonus' },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: uid,
    });
    t.set(userRef, {
      bonusBalance: next,
      balanceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    settlementLedger.commitBonusInTx(t, bonusCtx, {
      delta: amount,
      kind: 'car_profile_bonus',
      refType: 'car_profile_bonus',
      refId: 'v1',
      meta: { module: 'oil_change' },
      postedBy: uid,
      postedRole: 'user',
    });

    const result = { ok: true, credited: amount, uid };
    t.set(idemRef, {
      type: 'claimCarProfileBonus',
      result,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return result;
  });

  if (txDup) return txDup;
  return out;
});

/** Admin web: SMSsiz kirish — faqat ishonchli operator raqami (server role tekshiruvi). */
const TRUSTED_ADMIN_WEB_PHONE = '998912778777';

async function findUserDocByPhone(rawPhone) {
  const candidates = [];
  const canon = canonicalUid(rawPhone);
  const d = digits(rawPhone);
  candidates.push(canon, d);
  if (d.length >= 12 && d.startsWith('998')) {
    candidates.push(d.substring(3));
  }
  if (d.length === 9) {
    candidates.push(`998${d}`);
  }
  const seen = new Set();
  for (const id of candidates) {
    if (!id || id.length < 9 || seen.has(id)) continue;
    seen.add(id);
    const snap = await db.collection('users').doc(id).get();
    if (snap.exists) return { snap, docId: id };
  }
  return null;
}

/** Auth/binding callables — Europe (UZ + Firestore eur3 ga yaqinroq). */
const authFunctions = functions.region('europe-west1');

/** Composite fingerprint: login oldin qurilma ↔ telefon tekshiruvi. */
exports.checkDeviceBinding = authFunctions
  .runWith({ timeoutSeconds: 60, memory: '256MB', minInstances: 1 })
  .https.onCall(async (data) => {
  // Client til ekranidan cold-start warmup.
  if (data && data.warmup === true) {
    return { status: 'warmup', ok: true };
  }

  const phone = canonicalUid(data.phone || '');
  const hash = String(data.deviceFingerprintHash || '').trim().toLowerCase();

  if (phone.length < 12) {
    throw new functions.https.HttpsError('invalid-argument', 'Telefon raqami noto\'g\'ri');
  }
  if (!isValidFingerprintHash(hash)) {
    throw new functions.https.HttpsError('invalid-argument', 'deviceFingerprintHash noto\'g\'ri');
  }

  const bindingRef = db.collection('device_bindings').doc(hash);
  const bindingSnap = await bindingRef.get();

  if (bindingSnap.exists) {
    const binding = bindingSnap.data() || {};
    if (deviceBindingBlocked(binding)) {
      const until = binding.blockedUntil;
      const retryAfterMs = until && typeof until.toDate === 'function'
        ? Math.max(0, until.toDate().getTime() - Date.now())
        : DEVICE_BINDING_BLOCK_MS;
      return {
        status: 'blocked',
        failedAttempts: binding.failedAttempts || 0,
        retryAfterMs,
        selfServeHint: 'use_correct_phone_or_wait',
        message:
          'Qurilma vaqtincha cheklangan. To\'g\'ri raqam bilan kiring yoki birozdan keyin qayta urinib ko\'ring.',
      };
    }

    const boundPhone = canonicalUid(binding.phone || '');
    if (boundPhone === phone) {
      await bindingRef.set({
        lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
        failedAttempts: 0,
        isBlocked: false,
        blockedUntil: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // Auth/token — alohida createPhoneSession (UI kutmasin).
      return {
        status: 'trusted_device',
        skipSms: true,
        sessionRequired: true,
      };
    }

    if (await isDeviceBindingAutoApproveEnabled()) {
      const fingerprint = data.fingerprint && typeof data.fingerprint === 'object'
        ? data.fingerprint
        : {};
      await forceDeviceBindingLink({
        hash,
        phone,
        verifiedMethod: 'admin_auto',
        fingerprint,
      });
      return {
        status: 'trusted_device',
        skipSms: true,
        sessionRequired: true,
        autoApproved: true,
      };
    }

    const failedAttempts = (binding.failedAttempts || 0) + 1;
    const block = failedAttempts >= DEVICE_BINDING_MAX_FAILED;
    const patch = {
      failedAttempts,
      isBlocked: block,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (block) {
      patch.blockedUntil = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + DEVICE_BINDING_BLOCK_MS),
      );
    }
    await bindingRef.set(patch, { merge: true });

    return {
      status: 'device_bound_other_phone',
      failedAttempts,
      selfServeHint: 'use_bound_phone',
      message: block
        ? 'Qurilma vaqtincha cheklangan. To\'g\'ri raqam bilan kiring yoki birozdan keyin qayta urinib ko\'ring.'
        : 'Bu qurilma boshqa raqamga bog\'liq. Shu qurilmaga biriktirilgan raqam bilan kiring.',
    };
  }

  const aliasSnap = await db.collection('device_aliases').doc(phone).get();
  if (aliasSnap.exists) {
    const aliasHash = String(aliasSnap.data().deviceFingerprintHash || '').toLowerCase();
    if (aliasHash && !isValidFingerprintHash(aliasHash)) {
      // Eski alias (legacy hash ID) — yangi qurilma sifatida davom etadi.
    } else if (aliasHash && aliasHash !== hash) {
      if (await isDeviceBindingAutoApproveEnabled()) {
        const fingerprint = data.fingerprint && typeof data.fingerprint === 'object'
          ? data.fingerprint
          : {};
        await forceDeviceBindingLink({
          hash,
          phone,
          verifiedMethod: 'admin_auto',
          fingerprint,
        });
        return {
          status: 'trusted_device',
          skipSms: true,
          sessionRequired: true,
          autoApproved: true,
        };
      }
      let oldDeviceLabel = '';
      try {
        const oldBind = await db.collection('device_bindings').doc(aliasHash).get();
        if (oldBind.exists) {
          oldDeviceLabel = oldDeviceLabelFromBinding(oldBind.data());
        }
      } catch (_) {}
      return {
        status: 'phone_bound_other_device',
        selfServeAvailable: true,
        oldDeviceLabel,
        message:
          'Bu raqam boshqa qurilmaga bog\'liq. Eski qurilmadan tasdiqlashingiz mumkin.',
      };
    }
  }

  // Янги қурилма ↔ телефон: фақат fingerprint боғлаш (token — createPhoneSession).
  // Низолар (бошқа рақам/қурилма) юқорида блокланади — бу ерга фақат «тоза» биринчи боғлаш келади.
  const fingerprint = data.fingerprint && typeof data.fingerprint === 'object'
    ? data.fingerprint
    : {};
  try {
    await forceDeviceBindingLink({
      hash,
      phone,
      verifiedMethod: 'fingerprint_first_bind',
      fingerprint,
    });
  } catch (linkErr) {
    console.error('checkDeviceBinding first bind failed:', linkErr.message || linkErr);
    // Pending-code fallback олиб ташланди — клиент қайта уринишни кўрсатади.
    return {
      status: 'needs_verification',
      skipSms: true,
      message: 'Qurilmani bog\'lab bo\'lmadi. Qayta urinib ko\'ring.',
    };
  }

  return {
    status: 'trusted_device',
    skipSms: true,
    sessionRequired: true,
    firstBind: true,
  };
});

/**
 * Device bindingдан кейин Auth session (createUser + claims + customToken).
 * UI checkDeviceBindingдан кейин очилиши мумкин — бу CF фонда чақирилади.
 */
exports.createPhoneSession = authFunctions
  .runWith({ timeoutSeconds: 60, memory: '256MB', minInstances: 1 })
  .https.onCall(async (data) => {
  if (data && data.warmup === true) {
    return { ok: true };
  }

  const phone = canonicalUid(data.phone || '');
  const hash = String(data.deviceFingerprintHash || '').trim().toLowerCase();

  if (phone.length < 12) {
    throw new functions.https.HttpsError('invalid-argument', 'Telefon raqami noto\'g\'ri');
  }
  if (!isValidFingerprintHash(hash)) {
    throw new functions.https.HttpsError('invalid-argument', 'deviceFingerprintHash noto\'g\'ri');
  }

  const bindingSnap = await db.collection('device_bindings').doc(hash).get();
  if (!bindingSnap.exists) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Qurilma hali bog\'lanmagan. Qayta urinib ko\'ring.',
    );
  }

  const binding = bindingSnap.data() || {};
  if (deviceBindingBlocked(binding)) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Qurilma vaqtincha cheklangan. Birozdan keyin qayta urinib ko\'ring.',
    );
  }

  const boundPhone = canonicalUid(binding.phone || '');
  if (boundPhone !== phone) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Qurilma va telefon mos emas.',
    );
  }

  try {
    const customToken = await createPhoneCustomToken(phone);
    return {
      status: 'ok',
      customToken,
    };
  } catch (authErr) {
    console.error('createPhoneSession failed:', authErr.message || authErr);
    throw new functions.https.HttpsError(
      'internal',
      'Kirish tokeni yaratilmadi. Qayta urinib ko\'ring.',
    );
  }
});

/**
 * Faza 1 self-serve: yangi qurilma eski qurilmadan tasdiq so‘raydi
 * (`phone_bound_other_device`). Auth yo‘q — hali session ochilmagan.
 */
exports.requestDeviceTransfer = authFunctions
  .runWith({ timeoutSeconds: 60, memory: '256MB' })
  .https.onCall(async (data) => {
  const phone = canonicalUid(data.phone || '');
  const toHash = String(data.deviceFingerprintHash || '').trim().toLowerCase();
  const fingerprint = data.fingerprint && typeof data.fingerprint === 'object'
    ? data.fingerprint
    : {};

  if (phone.length < 12) {
    throw new functions.https.HttpsError('invalid-argument', 'Telefon raqami noto\'g\'ri');
  }
  if (!isValidFingerprintHash(toHash)) {
    throw new functions.https.HttpsError('invalid-argument', 'deviceFingerprintHash noto\'g\'ri');
  }

  const aliasSnap = await db.collection('device_aliases').doc(phone).get();
  if (!aliasSnap.exists) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Bu raqam hali bog‘lanmagan. Oddiy kirishni urinib ko‘ring.',
    );
  }
  const fromHash = String(aliasSnap.data().deviceFingerprintHash || '').toLowerCase();
  if (!isValidFingerprintHash(fromHash)) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Eski qurilma yozuvi yaroqsiz. Adminga murojaat qiling.',
    );
  }
  if (fromHash === toHash) {
    return { status: 'already_bound', message: 'Qurilma allaqachon bog‘langan.' };
  }

  const dayAgo = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - 24 * 60 * 60 * 1000),
  );
  const recentSnap = await db.collection('device_transfer_requests')
    .where('phone', '==', phone)
    .where('createdAt', '>=', dayAgo)
    .limit(20)
    .get();
  if (recentSnap.size >= DEVICE_TRANSFER_MAX_PER_DAY) {
    throw new functions.https.HttpsError(
      'resource-exhausted',
      'Bugungi qurilma almashtirish limiti tugadi. Keyinroq urinib ko‘ring.',
    );
  }

  // Bir xil juftlik uchun mavjud pending ni qayta ishlatamiz.
  const existingPending = recentSnap.docs.find((d) => {
    const x = d.data() || {};
    return x.status === 'pending'
      && String(x.toHash || '') === toHash
      && String(x.fromHash || '') === fromHash;
  });
  if (existingPending) {
    const ex = existingPending.data() || {};
    const exp = ex.expiresAt && typeof ex.expiresAt.toDate === 'function'
      ? ex.expiresAt.toDate().getTime()
      : 0;
    if (exp > Date.now()) {
      return {
        status: 'pending',
        requestId: existingPending.id,
        expiresAtMs: exp,
        oldDeviceLabel: String(ex.oldDeviceLabel || ''),
      };
    }
    await existingPending.ref.set({
      status: 'expired',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  // Boshqa pending so‘rovlarni bekor qilish (bitta faol).
  const batch = db.batch();
  for (const d of recentSnap.docs) {
    if (d.id === (existingPending && existingPending.id)) continue;
    if ((d.data() || {}).status === 'pending') {
      batch.set(d.ref, {
        status: 'cancelled',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  }

  let oldDeviceLabel = '';
  try {
    const oldBind = await db.collection('device_bindings').doc(fromHash).get();
    if (oldBind.exists) oldDeviceLabel = oldDeviceLabelFromBinding(oldBind.data());
  } catch (_) {}

  const newDeviceLabel = oldDeviceLabelFromBinding({ fingerprint });
  const reqRef = db.collection('device_transfer_requests').doc();
  const expiresAt = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + DEVICE_TRANSFER_TTL_MS),
  );
  batch.set(reqRef, {
    phone,
    fromHash,
    toHash,
    toFingerprint: fingerprint,
    newDeviceLabel,
    oldDeviceLabel,
    status: 'pending',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt,
    channel: 'old_device_push',
  });
  await batch.commit();

  try {
    await notifyDeviceTransferRequest(phone, reqRef.id, newDeviceLabel);
  } catch (e) {
    console.error('requestDeviceTransfer notify:', e.message || e);
  }

  return {
    status: 'pending',
    requestId: reqRef.id,
    expiresAtMs: Date.now() + DEVICE_TRANSFER_TTL_MS,
    oldDeviceLabel,
  };
});

/** Yangi qurilma: transfer holatini poll qiladi (auth yo‘q). */
exports.getDeviceTransferStatus = authFunctions
  .runWith({ timeoutSeconds: 30, memory: '256MB' })
  .https.onCall(async (data) => {
  const phone = canonicalUid(data.phone || '');
  const toHash = String(data.deviceFingerprintHash || '').trim().toLowerCase();
  const requestId = String(data.requestId || '').trim();

  if (phone.length < 12 || !isValidFingerprintHash(toHash) || !requestId) {
    throw new functions.https.HttpsError('invalid-argument', 'Parametrlar noto\'g\'ri');
  }

  const snap = await db.collection('device_transfer_requests').doc(requestId).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'So‘rov topilmadi');
  }
  const req = snap.data() || {};
  if (canonicalUid(req.phone || '') !== phone || String(req.toHash || '') !== toHash) {
    throw new functions.https.HttpsError('permission-denied', 'So‘rov mos emas');
  }

  let status = String(req.status || 'pending');
  const exp = req.expiresAt && typeof req.expiresAt.toDate === 'function'
    ? req.expiresAt.toDate().getTime()
    : 0;
  if (status === 'pending' && exp > 0 && exp <= Date.now()) {
    await snap.ref.set({
      status: 'expired',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    status = 'expired';
  }

  return {
    status,
    requestId,
    expiresAtMs: exp || null,
    oldDeviceLabel: String(req.oldDeviceLabel || ''),
  };
});

/**
 * Eski qurilma (auth + fingerprint=fromHash): tasdiq / rad.
 * Approve → bog‘lanish ko‘chadi + 24s limited trust.
 */
exports.respondDeviceTransfer = authFunctions
  .runWith({ timeoutSeconds: 60, memory: '256MB' })
  .https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }
  const tokenPhone = canonicalUid(callerPhone(context));
  const requestId = String(data.requestId || '').trim();
  const approve = data.approve === true;
  const fromHash = String(data.deviceFingerprintHash || '').trim().toLowerCase();

  if (!requestId || !isValidFingerprintHash(fromHash)) {
    throw new functions.https.HttpsError('invalid-argument', 'Parametrlar noto\'g\'ri');
  }

  const ref = db.collection('device_transfer_requests').doc(requestId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'So‘rov topilmadi');
  }
  const req = snap.data() || {};
  const phone = canonicalUid(req.phone || '');
  if (!phone || phone !== tokenPhone) {
    throw new functions.https.HttpsError('permission-denied', 'Bu so‘rov sizniki emas');
  }
  if (String(req.fromHash || '') !== fromHash) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Faqat eski (joriy) qurilmadan tasdiqlash mumkin.',
    );
  }

  let status = String(req.status || '');
  const exp = req.expiresAt && typeof req.expiresAt.toDate === 'function'
    ? req.expiresAt.toDate().getTime()
    : 0;
  if (status === 'pending' && exp > 0 && exp <= Date.now()) {
    await ref.set({
      status: 'expired',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    status = 'expired';
  }
  if (status !== 'pending') {
    return { status, requestId };
  }

  if (!approve) {
    await ref.set({
      status: 'rejected',
      respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { status: 'rejected', requestId };
  }

  const toHash = String(req.toHash || '').toLowerCase();
  if (!isValidFingerprintHash(toHash)) {
    throw new functions.https.HttpsError('failed-precondition', 'Yangi qurilma hash yaroqsiz');
  }

  const toFingerprint = req.toFingerprint && typeof req.toFingerprint === 'object'
    ? req.toFingerprint
    : {};
  await forceDeviceBindingLink({
    hash: toHash,
    phone,
    verifiedMethod: 'peer_device_transfer',
    fingerprint: toFingerprint,
  });

  const limitedUntil = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + DEVICE_TRUST_LIMITED_MS),
  );
  await db.collection('users').doc(phone).set({
    security: {
      deviceTrustMode: 'limited',
      deviceTrustUntil: limitedUntil,
      deviceTrustReason: 'peer_device_transfer',
      deviceTrustUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  await ref.set({
    status: 'approved',
    respondedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    limitedUntil,
  }, { merge: true });

  return {
    status: 'approved',
    requestId,
    limitedUntilMs: Date.now() + DEVICE_TRUST_LIMITED_MS,
  };
});

/** Eski qurilma: o‘zining pending transferlari (fromHash mos). */
exports.listMyPendingDeviceTransfers = authFunctions
  .runWith({ timeoutSeconds: 30, memory: '256MB' })
  .https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }
  const phone = canonicalUid(callerPhone(context));
  const fromHash = String(data.deviceFingerprintHash || '').trim().toLowerCase();
  if (phone.length < 12 || !isValidFingerprintHash(fromHash)) {
    throw new functions.https.HttpsError('invalid-argument', 'Parametrlar noto\'g\'ri');
  }

  const snap = await db.collection('device_transfer_requests')
    .where('phone', '==', phone)
    .where('status', '==', 'pending')
    .limit(10)
    .get();

  const now = Date.now();
  const items = [];
  for (const d of snap.docs) {
    const x = d.data() || {};
    if (String(x.fromHash || '') !== fromHash) continue;
    const exp = x.expiresAt && typeof x.expiresAt.toDate === 'function'
      ? x.expiresAt.toDate().getTime()
      : 0;
    if (exp > 0 && exp <= now) {
      await d.ref.set({
        status: 'expired',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      continue;
    }
    items.push({
      requestId: d.id,
      newDeviceLabel: String(x.newDeviceLabel || ''),
      expiresAtMs: exp || null,
      createdAtMs: x.createdAt && typeof x.createdAt.toDate === 'function'
        ? x.createdAt.toDate().getTime()
        : null,
    });
  }
  return { items };
});

/** SMS yoki admin kodi tasdiqlangandan keyin qurilmani bog'lash. */
exports.registerDeviceBinding = authFunctions.https.onCall(async (data, context) => {
  const phone = canonicalUid(data.phone || '');
  const hash = String(data.deviceFingerprintHash || '').trim().toLowerCase();
  const verifiedMethod = String(data.verifiedMethod || 'sms');
  const fingerprint = data.fingerprint && typeof data.fingerprint === 'object'
    ? data.fingerprint
    : {};

  if (phone.length < 12) {
    throw new functions.https.HttpsError('invalid-argument', 'Telefon raqami noto\'g\'ri');
  }
  if (!isValidFingerprintHash(hash)) {
    throw new functions.https.HttpsError('invalid-argument', 'deviceFingerprintHash noto\'g\'ri');
  }
  if (!['sms', 'admin_code'].includes(verifiedMethod)) {
    throw new functions.https.HttpsError('invalid-argument', 'verifiedMethod noto\'g\'ri');
  }

  if (verifiedMethod === 'admin_code') {
    const code = String(data.adminCode || '').trim();
    const settingsSnap = await db.collection('settings').doc('app').get();
    const expected = String((settingsSnap.data() || {}).deviceAdminCode || '').trim();
    if (!expected || code !== expected) {
      throw new functions.https.HttpsError('permission-denied', 'Admin kodi noto\'g\'ri');
    }
  } else {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    }
    const tokenPhone = callerPhone(context);
    if (canonicalUid(tokenPhone) !== phone) {
      throw new functions.https.HttpsError('permission-denied', 'Telefon token mos emas');
    }
  }

  const bindingRef = db.collection('device_bindings').doc(hash);
  const aliasRef = db.collection('device_aliases').doc(phone);

  await db.runTransaction(async (tx) => {
    const bindingSnap = await tx.get(bindingRef);
    const aliasSnap = await tx.get(aliasRef);

    if (aliasSnap.exists) {
      const aliasHash = String(aliasSnap.data().deviceFingerprintHash || '').toLowerCase();
      if (aliasHash && isValidFingerprintHash(aliasHash) && aliasHash !== hash) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Bu raqam boshqa qurilmaga bog\'liq',
        );
      }
    }

    if (bindingSnap.exists) {
      const boundPhone = canonicalUid(bindingSnap.data().phone || '');
      if (boundPhone && boundPhone !== phone) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Bu qurilma boshqa raqamga bog\'liq',
        );
      }
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    tx.set(bindingRef, {
      phone,
      deviceFingerprintHash: hash,
      firstRegisteredAt: bindingSnap.exists
        ? (bindingSnap.data().firstRegisteredAt || now)
        : now,
      lastSeenAt: now,
      failedAttempts: 0,
      isBlocked: false,
      blockedUntil: admin.firestore.FieldValue.delete(),
      verifiedMethod,
      fingerprint,
      updatedAt: now,
    }, { merge: true });

    tx.set(aliasRef, {
      phone,
      deviceFingerprintHash: hash,
      updatedAt: now,
    }, { merge: true });
  });

  return { ok: true, deviceFingerprintHash: hash };
});

/** Mobil: admin kod so'rovi — faqat CF yozadi (Firestore rules client write blok). */
exports.requestPendingCode = authFunctions.https.onCall(async (data) => {
  const phone = canonicalUid(data.phone || '');
  const hash = String(data.deviceFingerprintHash || '').trim().toLowerCase();
  const fingerprint = sanitizeFingerprintMap(data.fingerprint);

  if (phone.length < 12) {
    throw new functions.https.HttpsError('invalid-argument', 'Telefon raqami noto\'g\'ri');
  }
  if (!isValidFingerprintHash(hash)) {
    throw new functions.https.HttpsError('invalid-argument', 'deviceFingerprintHash noto\'g\'ri');
  }

  const pendingRef = db.collection('pending_codes').doc(phone);
  const expiresAt = new Date(Date.now() + 5 * 60 * 1000);

  await pendingRef.set({
    phone: `+${phone}`,
    status: 'pending',
    code: admin.firestore.FieldValue.delete(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
    deviceFingerprintHash: hash,
    ...(Object.keys(fingerprint).length > 0 ? { fingerprint } : {}),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  return { ok: true, phone };
});

/** Mobil: kod holati (auth talab qilinmaydi — hash tekshiruvi). */
exports.getPendingCodeStatus = authFunctions.https.onCall(async (data) => {
  const phone = canonicalUid(data.phone || '');
  const hash = String(data.deviceFingerprintHash || '').trim().toLowerCase();

  if (phone.length < 12) {
    throw new functions.https.HttpsError('invalid-argument', 'Telefon raqami noto\'g\'ri');
  }
  if (!isValidFingerprintHash(hash)) {
    throw new functions.https.HttpsError('invalid-argument', 'deviceFingerprintHash noto\'g\'ri');
  }

  const pendingRef = db.collection('pending_codes').doc(phone);
  const pendingSnap = await pendingRef.get();
  if (!pendingSnap.exists) {
    return { status: 'none' };
  }

  const pending = pendingSnap.data() || {};
  const storedHash = String(pending.deviceFingerprintHash || '').toLowerCase();
  if (storedHash && isValidFingerprintHash(storedHash) && storedHash !== hash) {
    throw new functions.https.HttpsError('permission-denied', 'Qurilma mos emas');
  }

  let status = String(pending.status || 'pending');
  const expiresAt = pending.expiresAt;
  if (expiresAt && typeof expiresAt.toDate === 'function') {
    if (expiresAt.toDate().getTime() < Date.now()) {
      if (status === 'approved' || status === 'pending') {
        await pendingRef.set({
          status: 'expired',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      return { status: 'expired' };
    }
  }

  if (status === 'approved') {
    const code = String(pending.code || '').trim();
    return {
      status: 'approved',
      code: /^\d{6}$/.test(code) ? code : null,
    };
  }

  return { status: status || 'pending' };
});

/** Admin panel kodidan keyin: pending_codes tekshiruvi + device_bindings + custom token. */
exports.verifyPendingCodeAndRegister = authFunctions.https.onCall(async (data) => {
  try {
    const phone = canonicalUid(data.phone || '');
    const code = String(data.code || '').trim();
    const hash = String(data.deviceFingerprintHash || '').trim().toLowerCase();
    const fingerprint = sanitizeFingerprintMap(data.fingerprint);

    if (phone.length < 12) {
      throw new functions.https.HttpsError('invalid-argument', 'Telefon raqami noto\'g\'ri');
    }
    if (!/^\d{6}$/.test(code)) {
      throw new functions.https.HttpsError('invalid-argument', 'Kod 6 xonali bo\'lishi kerak');
    }
    if (!isValidFingerprintHash(hash)) {
      throw new functions.https.HttpsError('invalid-argument', 'deviceFingerprintHash noto\'g\'ri');
    }

    const pendingRef = db.collection('pending_codes').doc(phone);
    const pendingSnap = await pendingRef.get();
    if (!pendingSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Kod so\'rovi topilmadi');
    }

    const pending = pendingSnap.data() || {};
    const expectedCode = String(pending.code || '').trim();
    const status = String(pending.status || '');
    const storedHash = String(pending.deviceFingerprintHash || '').toLowerCase();

    if (status !== 'approved') {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Admin hali kod yaratmagan',
      );
    }
    if (!expectedCode || expectedCode !== code) {
      throw new functions.https.HttpsError('permission-denied', 'Kod noto\'g\'ri');
    }
    if (storedHash && isValidFingerprintHash(storedHash) && storedHash !== hash) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Qurilma o\'zgargan. Qayta urinib ko\'ring',
      );
    }

    const expiresAt = pending.expiresAt;
    if (expiresAt && typeof expiresAt.toDate === 'function') {
      if (expiresAt.toDate().getTime() < Date.now()) {
        await pendingRef.set({
          status: 'expired',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        throw new functions.https.HttpsError('deadline-exceeded', 'Kod muddati o\'tgan');
      }
    }

    const bindingRef = db.collection('device_bindings').doc(hash);
    const aliasRef = db.collection('device_aliases').doc(phone);

    const [bindingSnap, aliasSnap] = await Promise.all([
      bindingRef.get(),
      aliasRef.get(),
    ]);

    if (aliasSnap.exists) {
      const aliasHash = String(aliasSnap.data().deviceFingerprintHash || '').toLowerCase();
      if (aliasHash && isValidFingerprintHash(aliasHash) && aliasHash !== hash) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Bu raqam boshqa qurilmaga bog\'liq',
        );
      }
    }

    if (bindingSnap.exists) {
      const boundPhone = canonicalUid(bindingSnap.data().phone || '');
      if (boundPhone && boundPhone !== phone) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Bu qurilma boshqa raqamga bog\'liq',
        );
      }
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    await db.runTransaction(async (tx) => {
      const bindingInTx = await tx.get(bindingRef);
      const aliasInTx = await tx.get(aliasRef);

      if (aliasInTx.exists) {
        const aliasHash = String(aliasInTx.data().deviceFingerprintHash || '').toLowerCase();
        if (aliasHash && isValidFingerprintHash(aliasHash) && aliasHash !== hash) {
          throw new Error('phone_bound_other_device');
        }
      }

      if (bindingInTx.exists) {
        const boundPhone = canonicalUid(bindingInTx.data().phone || '');
        if (boundPhone && boundPhone !== phone) {
          throw new Error('device_bound_other_phone');
        }
      }

      tx.set(bindingRef, {
        phone,
        deviceFingerprintHash: hash,
        firstRegisteredAt: bindingInTx.exists
          ? (bindingInTx.data().firstRegisteredAt || now)
          : now,
        lastSeenAt: now,
        failedAttempts: 0,
        isBlocked: false,
        blockedUntil: admin.firestore.FieldValue.delete(),
        verifiedMethod: 'admin_code',
        fingerprint,
        updatedAt: now,
      }, { merge: true });

      tx.set(aliasRef, {
        phone,
        deviceFingerprintHash: hash,
        updatedAt: now,
      }, { merge: true });

      tx.delete(pendingRef);
    });

    let customToken;
    try {
      customToken = await createPhoneCustomToken(phone);
    } catch (authErr) {
      console.error('verifyPendingCodeAndRegister auth', authErr);
      throw new functions.https.HttpsError(
        'internal',
        authErr.message || 'Auth token yaratilmadi',
      );
    }

    return { ok: true, deviceFingerprintHash: hash, customToken };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    if (e && e.message === 'phone_bound_other_device') {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Bu raqam boshqa qurilmaga bog\'liq',
      );
    }
    if (e && e.message === 'device_bound_other_phone') {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Bu qurilma boshqa raqamga bog\'liq',
      );
    }
    console.error('verifyPendingCodeAndRegister', e);
    throw new functions.https.HttpsError(
      'internal',
      (e && e.message) ? e.message : 'Server xatolik',
    );
  }
});

exports.autoApprovePendingCode = functions.firestore
  .document('pending_codes/{phone}')
  .onCreate(async (snap, context) => {
    const phone = context.params.phone;
    const data = snap.data() || {};

    if (data.status !== 'pending') return null;

    if (!/^\d{12}$/.test(phone) || !phone.startsWith('998')) {
      console.error('autoApprovePendingCode: invalid phone', phone);
      return null;
    }

    try {
      const code = String(
        100000 + Math.floor(Math.random() * 900000),
      );
      const expiresAt = new Date(Date.now() + 5 * 60 * 1000);

      await snap.ref.set({
        code,
        status: 'approved',
        approvedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
        autoApproved: true,
      }, { merge: true });

      console.log(`autoApprovePendingCode: approved ${phone}`);
      return null;
    } catch (e) {
      console.error('autoApprovePendingCode error:', e);
      return null;
    }
  });

exports.autoApprovePendingCodeOnUpdate = functions.firestore
  .document('pending_codes/{phone}')
  .onUpdate(async (change, context) => {
    const after = change.after.data() || {};
    const before = change.before.data() || {};

    if (after.status !== 'pending' || before.status === 'pending') return null;

    const phone = context.params.phone;
    if (!/^\d{12}$/.test(phone) || !phone.startsWith('998')) return null;

    try {
      const code = String(
        100000 + Math.floor(Math.random() * 900000),
      );
      const expiresAt = new Date(Date.now() + 5 * 60 * 1000);

      await change.after.ref.set({
        code,
        status: 'approved',
        approvedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
        autoApproved: true,
      }, { merge: true });

      console.log(`autoApprovePendingCode onUpdate: approved ${phone}`);
      return null;
    } catch (e) {
      console.error('autoApprovePendingCode onUpdate error:', e);
      return null;
    }
  });

exports.changeDevicePhone = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Auth required');
  }

  const deviceFingerprintHash = String(data.deviceFingerprintHash || '')
    .trim()
    .toLowerCase();
  const newPhone = canonicalUid(data.newPhone || '');

  if (!isValidFingerprintHash(deviceFingerprintHash)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Bad fingerprint hash',
    );
  }
  if (newPhone.length < 12) {
    throw new functions.https.HttpsError('invalid-argument', 'Telefon noto\'g\'ri');
  }

  const bindingRef = db.collection('device_bindings').doc(deviceFingerprintHash);
  const bindingSnap = await bindingRef.get();

  if (!bindingSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Device binding not found');
  }

  const oldPhone = canonicalUid(bindingSnap.data().phone || '');
  if (!oldPhone || oldPhone.length < 12) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Binding has no phone',
    );
  }

  const userQuery = await db.collection('users')
    .where('phone', '==', oldPhone)
    .limit(1)
    .get();

  await db.runTransaction(async (t) => {
    t.update(bindingRef, {
      phone: newPhone,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    t.delete(db.collection('device_aliases').doc(oldPhone));
    t.set(db.collection('device_aliases').doc(newPhone), {
      phone: newPhone,
      deviceFingerprintHash,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    if (!userQuery.empty) {
      t.update(userQuery.docs[0].ref, {
        phone: newPhone,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });

  return { ok: true, message: 'Phone updated successfully' };
});

/** Admin: global avtomatik tasdiqlash rejimi. */
exports.adminSetDeviceBindingAutoApprove = functions.https.onCall(async (data, context) => {
  await assertAdmin(String(data.adminPhone || ''), context);
  const enabled = data.enabled === true;
  await db.collection('settings').doc('app').set({
    deviceBindingAutoApprove: enabled,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, enabled };
});

/** Admin: bir bosishda avtomatik tasdiqlash (konfliktlarni hal qiladi). */
exports.adminAutoApproveDeviceBinding = functions.https.onCall(async (data, context) => {
  await assertAdmin(String(data.adminPhone || ''), context);
  const hash = String(data.deviceFingerprintHash || '').trim().toLowerCase();
  let phone = canonicalUid(data.phone || '');
  if (!isValidFingerprintHash(hash)) {
    throw new functions.https.HttpsError('invalid-argument', 'deviceFingerprintHash noto\'g\'ri');
  }
  if (phone.length < 12) {
    const bindingSnap = await db.collection('device_bindings').doc(hash).get();
    phone = canonicalUid((bindingSnap.data() || {}).phone || '');
  }
  if (phone.length < 12) {
    throw new functions.https.HttpsError('invalid-argument', 'Telefon raqami topilmadi');
  }
  await forceDeviceBindingLink({
    hash,
    phone,
    verifiedMethod: 'admin_auto',
  });
  return { ok: true, phone, deviceFingerprintHash: hash };
});

/** Admin: qo'lda tasdiqlash (telefonni admin kiritadi). */
exports.adminManualApproveDeviceBinding = functions.https.onCall(async (data, context) => {
  await assertAdmin(String(data.adminPhone || ''), context);
  const hash = String(data.deviceFingerprintHash || '').trim().toLowerCase();
  const phone = canonicalUid(data.phone || '');
  if (!isValidFingerprintHash(hash)) {
    throw new functions.https.HttpsError('invalid-argument', 'deviceFingerprintHash noto\'g\'ri');
  }
  if (phone.length < 12) {
    throw new functions.https.HttpsError('invalid-argument', 'Telefon raqami noto\'g\'ri');
  }
  await forceDeviceBindingLink({
    hash,
    phone,
    verifiedMethod: 'admin_manual',
  });
  return { ok: true, phone, deviceFingerprintHash: hash };
});

/** Admin: blokni ochish. */
exports.adminUnblockDeviceBinding = functions.https.onCall(async (data, context) => {
  await assertAdmin(String(data.adminPhone || ''), context);
  const hash = String(data.deviceFingerprintHash || '').trim().toLowerCase();
  if (!isValidFingerprintHash(hash)) {
    throw new functions.https.HttpsError('invalid-argument', 'deviceFingerprintHash noto\'g\'ri');
  }
  await db.collection('device_bindings').doc(hash).set({
    isBlocked: false,
    failedAttempts: 0,
    blockedUntil: admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true };
});

/** Admin: binding rad etish / o'chirish. */
exports.adminRejectDeviceBinding = functions.https.onCall(async (data, context) => {
  await assertAdmin(String(data.adminPhone || ''), context);
  const hash = String(data.deviceFingerprintHash || '').trim().toLowerCase();
  if (!isValidFingerprintHash(hash)) {
    throw new functions.https.HttpsError('invalid-argument', 'deviceFingerprintHash noto\'g\'ri');
  }
  const bindingRef = db.collection('device_bindings').doc(hash);
  const bindingSnap = await bindingRef.get();
  if (!bindingSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Binding topilmadi');
  }
  const phone = canonicalUid(bindingSnap.data().phone || '');
  const batch = db.batch();
  batch.delete(bindingRef);
  if (phone.length >= 12) {
    batch.delete(db.collection('device_aliases').doc(phone));
  }
  await batch.commit();
  return { ok: true };
});

/**
 * Bir martalik: eski `device_bindings` (ID hash emas) → `device_bindings_legacy`.
 * `dryRun: true` — faqat hisob, yozmaydi.
 */
exports.migrateOldBindings = functions.https.onCall(async (data, context) => {
  await assertAdmin(String(data.adminPhone || ''), context);
  const dryRun = data.dryRun === true;
  const now = admin.firestore.FieldValue.serverTimestamp();

  const bindingsSnap = await db.collection('device_bindings').get();
  const legacyBindings = bindingsSnap.docs.filter((doc) => !isValidFingerprintHash(doc.id));

  const aliasesSnap = await db.collection('device_aliases').get();
  const staleAliases = aliasesSnap.docs.filter((doc) => {
    const h = String((doc.data() || {}).deviceFingerprintHash || '').toLowerCase();
    return h.length > 0 && !isValidFingerprintHash(h);
  });

  if (dryRun) {
    return {
      ok: true,
      dryRun: true,
      legacyBindingsCount: legacyBindings.length,
      staleAliasesCount: staleAliases.length,
      legacyBindingIds: legacyBindings.slice(0, 20).map((d) => d.id),
    };
  }

  let bindingsMoved = 0;
  let aliasesRemoved = 0;
  const BATCH_LIMIT = 400;

  for (let i = 0; i < legacyBindings.length; i += BATCH_LIMIT) {
    const chunk = legacyBindings.slice(i, i + BATCH_LIMIT);
    const batch = db.batch();
    for (const doc of chunk) {
      const legacyRef = db.collection('device_bindings_legacy').doc(doc.id);
      batch.set(legacyRef, {
        ...doc.data(),
        legacyDocId: doc.id,
        migratedAt: now,
        migratedBy: digits(data.adminPhone || ''),
      });
      batch.delete(doc.ref);
      bindingsMoved += 1;
    }
    await batch.commit();
  }

  for (let i = 0; i < staleAliases.length; i += BATCH_LIMIT) {
    const chunk = staleAliases.slice(i, i + BATCH_LIMIT);
    const batch = db.batch();
    for (const doc of chunk) {
      const legacyRef = db.collection('device_bindings_legacy').doc(`alias_${doc.id}`);
      batch.set(legacyRef, {
        type: 'stale_device_alias',
        phone: doc.id,
        ...doc.data(),
        migratedAt: now,
        migratedBy: digits(data.adminPhone || ''),
      });
      batch.delete(doc.ref);
      aliasesRemoved += 1;
    }
    await batch.commit();
  }

  return {
    ok: true,
    dryRun: false,
    bindingsMoved,
    aliasesRemoved,
  };
});

/**
 * Admin web: telefon bilan SMSsiz / parolsiz kirish.
 * Faqat Firestore'da panel roli bor raqamlar: admin, superadmin,
 * dispatcher, finance, auditor. Rol yo'q bo'lsa — permission-denied.
 */
exports.adminWebSignIn = functions.https.onCall(async (data) => {
  const phone = canonicalUid(data.phone || '');
  if (!phone || phone.length < 9) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Telefon raqami noto\'g\'ri',
    );
  }
  const found = await findUserDocByPhone(phone);
  if (!found) {
    throw new functions.https.HttpsError('not-found', 'User not found');
  }
  const role = String((found.snap.data() || {}).role || 'user')
    .trim()
    .toLowerCase();
  const panelRoles = [
    'admin',
    'superadmin',
    'dispatcher',
    'finance',
    'auditor',
  ];
  if (!panelRoles.includes(role)) {
    throw new functions.https.HttpsError('permission-denied', 'Not an admin');
  }
  const e164 = `+${phone}`;
  let authUser;
  try {
    authUser = await admin.auth().getUserByPhoneNumber(e164);
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      authUser = await admin.auth().createUser({ phoneNumber: e164 });
    } else {
      throw e;
    }
  }
  // phone_number'ni DOIMIY custom claim sifatida saqlaymiz — shunda ID token
  // 1 soatdan keyin yangilanganda ham claim yo'qolmaydi (Firestore qoidalari
  // isAdmin() shu claimga tayanadi).
  await admin.auth().setCustomUserClaims(authUser.uid, {
    ...(authUser.customClaims || {}),
    phone_number: e164,
  });
  const token = await admin.auth().createCustomToken(authUser.uid, {
    phone_number: e164,
  });
  return {
    token,
    uid: found.docId,
    phone: e164,
    role,
  };
});

/**
 * Admin web: maxfiy kod (PIN) bilan kirish — telefonsiz.
 * Kiritilgan kodning sha256 xeshi serverdagi xesh bilan solishtiriladi
 * (kod manba kodida ochiq turmaydi). To'g'ri bo'lsa — ishonchli admin
 * operator (TRUSTED_ADMIN_WEB_PHONE) uchun custom token qaytariladi.
 */
const ADMIN_WEB_CODE_SHA256 =
  'fca12b2d97e45c6117190cc65bf0f2e83a0c582c961a40796b7ee0c7bac54f9e';

exports.adminWebSignInWithCode = functions.https.onCall(async (data) => {
  const code = String((data && data.code) || '').trim();
  if (!code) {
    throw new functions.https.HttpsError('invalid-argument', 'Kod kiritilmadi');
  }
  const hash = crypto.createHash('sha256').update(code).digest('hex');
  // Doimiy vaqtli (timing-safe) solishtirish — brute-force timing'ni kamaytirish.
  const a = Buffer.from(hash, 'utf8');
  const b = Buffer.from(ADMIN_WEB_CODE_SHA256, 'utf8');
  const ok = a.length === b.length && crypto.timingSafeEqual(a, b);
  if (!ok) {
    throw new functions.https.HttpsError('permission-denied', 'Kod noto\'g\'ri');
  }

  const phone = TRUSTED_ADMIN_WEB_PHONE;
  const e164 = `+${phone}`;
  const adminRoles = ['admin', 'superadmin', 'dispatcher'];

  // Kod to'g'ri — maxfiy kodning o'zi admin huquqini beradi. Operator
  // hujjati admin bo'lmasa (yoki yo'q bo'lsa) — uni 'admin' qilamiz, shunda
  // Firebase Console'da qo'lda role o'zgartirish kerak bo'lmaydi.
  const found = await findUserDocByPhone(phone);
  const docId = found ? found.docId : canonicalUid(phone);
  const existingRole = found ? ((found.snap.data() || {}).role || '') : '';
  let role = existingRole;
  if (!adminRoles.includes(existingRole)) {
    await db.collection('users').doc(docId).set({
      role: 'admin',
      phone: e164,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    role = 'admin';
  }

  let authUser;
  try {
    authUser = await admin.auth().getUserByPhoneNumber(e164);
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      authUser = await admin.auth().createUser({ phoneNumber: e164 });
    } else {
      throw e;
    }
  }
  // phone_number'ni DOIMIY custom claim sifatida saqlaymiz — shunda ID token
  // 1 soatdan keyin yangilanganda ham claim yo'qolmaydi (Firestore qoidalari
  // isAdmin() shu claimga tayanadi).
  await admin.auth().setCustomUserClaims(authUser.uid, {
    ...(authUser.customClaims || {}),
    phone_number: e164,
  });
  const token = await admin.auth().createCustomToken(authUser.uid, {
    phone_number: e164,
  });
  return {
    token,
    uid: docId,
    phone: e164,
    role,
  };
});

/** Буюртма status patch — `OrdersRepository._statusPatch` билан синхрон. */
function buildOrderStatusPatch(status) {
  const s = String(status || '').trim();
  const data = {
    status: s,
    statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  const fulfillmentMap = {
    new: 'pending',
    accepted: 'confirmed',
    ready: 'confirmed',
    rejected: 'cancelled',
    in_delivery: 'courier_picked',
    delivered: 'completed',
  };
  if (fulfillmentMap[s]) {
    data.fulfillmentStatus = fulfillmentMap[s];
  }
  if (s === 'in_delivery') {
    data.inDeliveryAt = admin.firestore.FieldValue.serverTimestamp();
    data.fulfillmentStatus = 'courier_picked';
  }
  if (s === 'delivered') {
    data.deliveredAt = admin.firestore.FieldValue.serverTimestamp();
    data.fulfillmentStatus = 'completed';
    data.paymentStatus = 'paid';
  }
  if (s === 'rejected') {
    data.rejectedAt = admin.firestore.FieldValue.serverTimestamp();
    data.fulfillmentStatus = 'cancelled';
  }
  if (s === 'accepted' || s === 'ready') {
    data.fulfillmentStatus = 'confirmed';
    if (s === 'accepted') {
      data.confirmedAt = admin.firestore.FieldValue.serverTimestamp();
    }
  }
  if (s === 'new') {
    data.fulfillmentStatus = 'pending';
  }
  return data;
}

const ADMIN_JOB_AD_STATUSES = new Set([
  'pending', 'active', 'completed', 'blocked',
]);

function isJobsBoardAdDataJs(d) {
  const t = String((d && d.type) || '');
  if (t === 'cheap_product') return false;
  return ['work', 'service', 'ad', 'announcement'].includes(t) || t === '';
}

function urgentForJobAdType(type, isUrgent) {
  if (!isUrgent) return false;
  const t = String(type || '');
  return t === 'work' || t === 'ad';
}

function jobAdExpiryDays(type, isUrgent) {
  const t = String(type || '');
  const urgent = urgentForJobAdType(t, isUrgent === true);
  if (urgent) return 2;
  if (t === 'work') return 3;
  if (t === 'service') return 30;
  if (t === 'ad') return 14;
  return 14;
}

async function getJobsBoardAdOrThrow(adId) {
  const ref = db.collection('ads').doc(adId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'Ad not found');
  }
  if (!isJobsBoardAdDataJs(snap.data())) {
    throw new functions.https.HttpsError(
      'failed-precondition', 'Not a jobs board ad');
  }
  return { ref, snap };
}

const JOBS_DAILY_AD_LIMIT = 10;
const JOBS_DAILY_COMPLAINT_LIMIT = 20;

/** Mijoz: Иш топ эълон (CF-only, auth + телефон + кунлик лимит). */
exports.submitJobAd = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }
  const uid = canonicalUid(callerPhone(context));
  if (!uid || uid.length < 9) {
    throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
  }

  const type = String((data && data.type) || '').trim();
  if (!['work', 'service', 'ad'].includes(type)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid type');
  }
  const text = String((data && data.text) || '').trim();
  if (text.length < 3 || text.length > 2000) {
    throw new functions.https.HttpsError('invalid-argument', 'text 3..2000');
  }
  const title = String((data && data.title) || '').trim().slice(0, 120);
  if (title.length < 3 || title.length > 120) {
    throw new functions.https.HttpsError('invalid-argument', 'title 3..120');
  }
  const priceText = String((data && data.priceText) || '').trim().slice(0, 80);
  const authorName = String((data && data.authorName) || '').trim().slice(0, 80);
  const address = String((data && data.address) || '').trim().slice(0, 300);
  const isUrgent = urgentForJobAdType(type, data && data.isUrgent === true);

  const dayStart = new Date();
  dayStart.setHours(0, 0, 0, 0);
  // Янги ёзувлар canonical; эски 9-рақамли ҳам санаш.
  const phoneVariants = [...new Set([
    uid,
    uid.length >= 12 && uid.startsWith('998') ? uid.slice(3) : '',
  ].filter((p) => p.length >= 9))];

  let todayCount = 0;
  for (const phoneKey of phoneVariants) {
    const recentSnap = await db.collection('ads')
      .where('authorPhone', '==', phoneKey)
      .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(dayStart))
      .limit(40)
      .get();
    for (const doc of recentSnap.docs) {
      const t = String((doc.data() || {}).type || '');
      if (['work', 'service', 'ad'].includes(t)) {
        todayCount += 1;
      }
    }
    if (todayCount >= JOBS_DAILY_AD_LIMIT) break;
  }
  if (todayCount >= JOBS_DAILY_AD_LIMIT) {
    throw new functions.https.HttpsError(
      'resource-exhausted', 'Daily ad limit reached');
  }

  const days = jobAdExpiryDays(type, isUrgent);
  const expiresAt = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + days * 24 * 60 * 60 * 1000),
  );

  const autoApprove = await isJobsAutoApproveEnabled();
  const status = autoApprove ? 'active' : 'pending';

  const ref = await db.collection('ads').add({
    type,
    text,
    title,
    ...(priceText ? { priceText } : {}),
    authorName: authorName || 'Фойдаланувчи',
    authorPhone: uid,
    address,
    isUrgent,
    status,
    expiresAt,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    editedAt: null,
    ...(autoApprove
      ? {
          moderatedAt: admin.firestore.FieldValue.serverTimestamp(),
          moderatedBy: 'auto',
          autoApproved: true,
        }
      : {}),
  });
  return { ok: true, adId: ref.id, status };
});

/** Mijoz: Иш топ шикоят (CF-only, auth). */
exports.submitJobComplaint = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }
  const uid = canonicalUid(callerPhone(context));
  if (!uid || uid.length < 9) {
    throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
  }
  const adId = String((data && data.adId) || '').trim();
  const reason = String((data && data.reason) || '').trim();
  if (!adId) {
    throw new functions.https.HttpsError('invalid-argument', 'adId required');
  }
  if (reason.length < 3 || reason.length > 300) {
    throw new functions.https.HttpsError('invalid-argument', 'reason 3..300');
  }

  const { snap } = await getJobsBoardAdOrThrow(adId);
  const ad = snap.data() || {};
  const owner = canonicalUid(String(ad.authorPhone || ''));
  if (owner && owner === uid) {
    throw new functions.https.HttpsError(
      'failed-precondition', 'Cannot report own ad');
  }

  const dayStart = new Date();
  dayStart.setHours(0, 0, 0, 0);
  const todaySnap = await db.collection('complaints')
    .where('reporterPhone', '==', uid)
    .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(dayStart))
    .limit(JOBS_DAILY_COMPLAINT_LIMIT + 1)
    .get();
  if (todaySnap.size >= JOBS_DAILY_COMPLAINT_LIMIT) {
    throw new functions.https.HttpsError(
      'resource-exhausted', 'Daily complaint limit reached');
  }

  const openSnap = await db.collection('complaints')
    .where('adId', '==', adId)
    .where('reporterPhone', '==', uid)
    .where('resolved', '==', false)
    .limit(1)
    .get();
  if (!openSnap.empty) {
    return { ok: true, complaintId: openSnap.docs[0].id, duplicate: true };
  }

  const ref = await db.collection('complaints').add({
    adId,
    reason,
    reporterPhone: uid,
    resolved: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { ok: true, complaintId: ref.id };
});

/** Admin web: Иш топ e'lonini o'chirish (Firestore rules custom token bilan ishlamaydi). */
exports.adminDeleteJobAd = functions.https.onCall(async (data, context) => {
  await assertAdmin(String(data.adminPhone || ''), context);
  const adId = String(data.adId || '').trim();
  if (!adId) {
    throw new functions.https.HttpsError('invalid-argument', 'adId required');
  }
  const { ref } = await getJobsBoardAdOrThrow(adId);
  await ref.delete();
  return { ok: true, adId };
});

/** Admin web: Иш топ e'lon statusi. */
exports.adminUpdateJobAdStatus = functions.https.onCall(async (data, context) => {
  const adminDocId = await assertAdmin(String(data.adminPhone || ''), context);
  const adId = String(data.adId || '').trim();
  const status = String(data.status || '').trim();
  if (!adId) {
    throw new functions.https.HttpsError('invalid-argument', 'adId required');
  }
  if (!ADMIN_JOB_AD_STATUSES.has(status)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid status');
  }
  const { ref } = await getJobsBoardAdOrThrow(adId);
  await ref.update({
    status,
    moderatedAt: admin.firestore.FieldValue.serverTimestamp(),
    editedAt: admin.firestore.FieldValue.serverTimestamp(),
    moderatedBy: adminDocId,
  });
  return { ok: true, adId, status };
});

/** Admin web: Иш топ e'lonini to'liq tahrirlash. */
exports.adminUpdateJobAd = functions.https.onCall(async (data, context) => {
  const adminDocId = await assertAdmin(String(data.adminPhone || ''), context);
  const adId = String(data.adId || '').trim();
  if (!adId) {
    throw new functions.https.HttpsError('invalid-argument', 'adId required');
  }
  const { ref, snap } = await getJobsBoardAdOrThrow(adId);
  const existing = snap.data() || {};
  const text = String(data.text || '').trim();
  if (!text) {
    throw new functions.https.HttpsError('invalid-argument', 'text required');
  }
  const type = String(data.type || existing.type || 'ad');
  const patch = {
    text,
    type,
    isUrgent: urgentForJobAdType(type, data.isUrgent === true),
    title: String(data.title != null ? data.title : (existing.title || '')).trim(),
    priceText: String(
      data.priceText != null ? data.priceText : (existing.priceText || ''),
    ).trim(),
    address: String(
      data.address != null ? data.address : (existing.address || ''),
    ).trim(),
    adminNote: String(
      data.adminNote != null ? data.adminNote : (existing.adminNote || ''),
    ).trim(),
    editedAt: admin.firestore.FieldValue.serverTimestamp(),
    moderatedAt: admin.firestore.FieldValue.serverTimestamp(),
    moderatedBy: adminDocId,
  };
  const status = String(data.status || '').trim();
  if (status && ADMIN_JOB_AD_STATUSES.has(status)) {
    patch.status = status;
  }
  if (data.expiresAt) {
    const exp = new Date(data.expiresAt);
    if (!Number.isNaN(exp.getTime())) {
      patch.expiresAt = admin.firestore.Timestamp.fromDate(exp);
    }
  }
  await ref.update(patch);
  return { ok: true, adId };
});

const ADMIN_SELL_SUBMISSION_STATUSES = new Set(['pending', 'reviewed', 'archived']);

/** Mijoz: sell_submissions yaratish (CF-only, rate limit). */
exports.submitSellSubmission = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }
  const uid = canonicalUid(callerPhone(context));
  if (!uid || uid.length < 9) {
    throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
  }
  const itemsIn = Array.isArray(data.items) ? data.items : [];
  if (itemsIn.length < 1 || itemsIn.length > 20) {
    throw new functions.https.HttpsError('invalid-argument', 'items 1..20');
  }
  const userName = String(data.userName || '').trim().slice(0, 80);
  const pickupAddress = String(data.pickupAddress || '').trim().slice(0, 500);
  const pickupNote = String(data.pickupNote || '').trim().slice(0, 300);
  const pickupLat = data.pickupLat != null ? Number(data.pickupLat) : null;
  const pickupLng = data.pickupLng != null ? Number(data.pickupLng) : null;

  const dayStart = new Date();
  dayStart.setHours(0, 0, 0, 0);
  const recentSnap = await db.collection('sell_submissions')
    .where('userId', '==', uid)
    .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(dayStart))
    .limit(500)
    .get();
  if (recentSnap.size >= 500) {
    throw new functions.https.HttpsError(
      'resource-exhausted', 'Daily submission limit reached');
  }

  const payload = {
    userId: uid,
    userPhone: uid,
    userName,
    items: itemsIn.slice(0, 20),
    status: 'pending',
    visibleToUserIds: [],
    adminNote: '',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (pickupAddress) payload.pickupAddress = pickupAddress;
  if (Number.isFinite(pickupLat)) payload.pickupLat = pickupLat;
  if (Number.isFinite(pickupLng)) payload.pickupLng = pickupLng;
  if (pickupNote) payload.pickupDetails = { note: pickupNote };
  if (data.pickupDetails && typeof data.pickupDetails === 'object') {
    payload.pickupDetails = data.pickupDetails;
  }

  const ref = await db.collection('sell_submissions').add(payload);
  return { ok: true, submissionId: ref.id };
});

/** Admin web: sell_submissions status / forward (CF-only writes). */
exports.adminUpdateSellSubmission = functions.https.onCall(async (data, context) => {
  const adminDocId = await assertAdmin(String(data.adminPhone || ''), context);
  const submissionId = String(data.submissionId || '').trim();
  if (!submissionId) {
    throw new functions.https.HttpsError('invalid-argument', 'submissionId required');
  }
  const ref = db.collection('sell_submissions').doc(submissionId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'submission not found');
  }

  const action = String(data.action || 'setStatus').trim();
  if (action === 'setStatus') {
    const status = String(data.status || '').trim();
    if (!ADMIN_SELL_SUBMISSION_STATUSES.has(status)) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid status');
    }
    const patch = {
      status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      moderatedBy: adminDocId,
      moderatedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastAdminAction: 'setStatus',
    };
    if (data.adminNote != null) {
      patch.adminNote = String(data.adminNote).trim();
    }
    await ref.update(patch);
    return { ok: true, submissionId, status };
  }

  if (action === 'forward') {
    const audience = String(data.forwardAudience || '').trim();
    if (!['all', 'selected'].includes(audience)) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid audience');
    }
    const patch = {
      forwardAudience: audience,
      forwardedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      moderatedBy: adminDocId,
      moderatedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastAdminAction: 'forward',
    };
    if (audience === 'selected') {
      const raw = Array.isArray(data.targetUserIds) ? data.targetUserIds : [];
      const normalized = [...new Set(raw.map((x) => canonicalUid(String(x || '')))
        .filter((p) => p.length >= 9))];
      if (normalized.length === 0) {
        throw new functions.https.HttpsError('invalid-argument', 'targetUserIds required');
      }
      patch.visibleToUserIds = normalized;
    }
    if (data.adminNote != null && String(data.adminNote).trim()) {
      patch.adminNote = String(data.adminNote).trim();
    }
    await ref.update(patch);
    return { ok: true, submissionId, forwardAudience: audience };
  }

  throw new functions.https.HttpsError('invalid-argument', 'Unknown action');
});

/** Mijoz: tanishuv profili bo'yicha shikoyat (CF-only yozuv). */
exports.submitDatingReport = functions.https.onCall(async (data, context) => {
  const reporterId = datingCallerUid(context);
  const targetId = String(data.targetId || '').trim();
  const reason = String(data.reason || '').trim();
  if (!targetId || targetId === reporterId) {
    throw new functions.https.HttpsError('invalid-argument', 'targetId required');
  }
  if (reason.length < 3) {
    throw new functions.https.HttpsError('invalid-argument', 'reason too short');
  }
  const targetSnap = await db.collection('dating_profiles').doc(targetId).get();
  if (!targetSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'profile not found');
  }

  const dayStart = new Date();
  dayStart.setHours(0, 0, 0, 0);
  const todaySnap = await db.collection('reports')
    .where('type', '==', 'dating_profile')
    .where('reporterId', '==', reporterId)
    .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(dayStart))
    .limit(10)
    .get();
  if (todaySnap.size >= 5) {
    throw new functions.https.HttpsError(
      'resource-exhausted', 'Daily report limit reached');
  }

  const openSnap = await db.collection('reports')
    .where('type', '==', 'dating_profile')
    .where('reporterId', '==', reporterId)
    .where('targetId', '==', targetId)
    .where('status', '==', 'open')
    .limit(1)
    .get();
  if (!openSnap.empty) {
    return { ok: true, reportId: openSnap.docs[0].id, duplicate: true };
  }

  const ref = db.collection('reports').doc();
  await ref.set({
    type: 'dating_profile',
    reporterId,
    targetId,
    reason,
    status: 'open',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { ok: true, reportId: ref.id };
});

/** Admin web: dating report resolve. */
exports.adminResolveDatingReport = functions.https.onCall(async (data, context) => {
  const adminDocId = await assertAdmin(String(data.adminPhone || ''), context);
  const reportId = String(data.reportId || '').trim();
  if (!reportId) {
    throw new functions.https.HttpsError('invalid-argument', 'reportId required');
  }
  const ref = db.collection('reports').doc(reportId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'report not found');
  }
  await ref.update({
    status: 'resolved',
    resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
    resolvedBy: adminDocId,
  });
  return { ok: true, reportId };
});

/** Admin web: shikoyatni hal qilindi deb belgilash. */
exports.adminResolveJobComplaint = functions.https.onCall(async (data, context) => {
  const adminDocId = await assertAdmin(String(data.adminPhone || ''), context);
  const complaintId = String(data.complaintId || '').trim();
  if (!complaintId) {
    throw new functions.https.HttpsError(
      'invalid-argument', 'complaintId required');
  }
  const ref = db.collection('complaints').doc(complaintId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'Complaint not found');
  }
  await ref.update({
    resolved: true,
    resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
    resolvedBy: adminDocId,
  });
  return { ok: true, complaintId };
});

const ADMIN_MARKET_AD_STATUSES = new Set(['active', 'inactive']);

function isMarketAdDataJs(d) {
  return String((d && d.type) || '') === 'cheap_product';
}

async function getMarketAdOrThrow(adId) {
  const ref = db.collection('ads').doc(adId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'Ad not found');
  }
  if (!isMarketAdDataJs(snap.data())) {
    throw new functions.https.HttpsError(
      'failed-precondition', 'Not a market ad');
  }
  return { ref, snap };
}

async function deleteMarketAdStorageImages(imageUrls) {
  const bucket = admin.storage().bucket();
  for (const raw of imageUrls || []) {
    try {
      const url = String(raw || '');
      const m = url.match(/\/o\/([^?]+)/);
      if (!m) continue;
      const path = decodeURIComponent(m[1]);
      await bucket.file(path).delete();
    } catch (_) { /* best-effort */ }
  }
}

function marketTsToIso(v) {
  if (!v || typeof v.toDate !== 'function') return null;
  return v.toDate().toISOString();
}

const MARKET_SEARCH_MAX_TOKENS = 48;
const MARKET_SEARCH_MIN_LEN = 2;

function marketToLatin(s) {
  const map = {
    а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', е: 'e', ё: 'yo', ж: 'j', з: 'z',
    и: 'i', й: 'y', к: 'k', л: 'l', м: 'm', н: 'n', о: 'o', п: 'p', р: 'r',
    с: 's', т: 't', у: 'u', ф: 'f', х: 'x', ц: 'ts', ч: 'ch', ш: 'sh', щ: 'sh',
    ъ: '', ы: 'i', ь: '', э: 'e', ю: 'yu', я: 'ya', ҳ: 'h', қ: 'q', ғ: "g'",
    ў: "o'", ң: 'ng',
  };
  return String(s || '').toLowerCase().split('').map((c) => map[c] || c).join('');
}

function marketToCyrillic(s) {
  let result = String(s || '').toLowerCase();
  const digraphs = {
    sh: 'ш', ch: 'ч', yo: 'ё', yu: 'ю', ya: 'я', ts: 'ц', ng: 'ң',
    "o'": 'ў', "g'": 'ғ',
  };
  for (const [k, v] of Object.entries(digraphs)) {
    result = result.split(k).join(v);
  }
  const singles = {
    q: 'қ', h: 'ҳ', a: 'а', b: 'б', v: 'в', g: 'г', d: 'д', e: 'е', j: 'ж',
    z: 'з', i: 'и', y: 'й', k: 'к', l: 'л', m: 'м', n: 'н', o: 'о', p: 'п',
    r: 'р', s: 'с', t: 'т', u: 'у', f: 'ф', x: 'х',
  };
  return result.split('').map((c) => singles[c] || c).join('');
}

/** Title+description → searchTokens (кирилл + лотин). */
function buildMarketSearchTokens(title, description) {
  const text = `${title || ''} ${description || ''}`.toLowerCase();
  const words = text.split(/[^0-9a-zа-яёўқғҳʻʼ']+/i).filter(
    (w) => w && w.length >= MARKET_SEARCH_MIN_LEN,
  );
  const out = new Set();
  for (const w of words) {
    out.add(w);
    const latin = marketToLatin(w);
    const cyrl = marketToCyrillic(w);
    if (latin.length >= MARKET_SEARCH_MIN_LEN) out.add(latin);
    if (cyrl.length >= MARKET_SEARCH_MIN_LEN) out.add(cyrl);
    if (out.size >= MARKET_SEARCH_MAX_TOKENS) break;
  }
  return Array.from(out).slice(0, MARKET_SEARCH_MAX_TOKENS);
}

function serializeMarketAdForAdmin(doc) {
  const d = doc.data() || {};
  const title = String(d.title || '');
  return {
    id: doc.id,
    ownerId: String(d.ownerId || ''),
    title,
    titleLower: String(d.titleLower || title.toLowerCase()),
    description: String(d.description || ''),
    price: Number(d.price) || 0,
    phone: String(d.phone || ''),
    sellerName: String(d.sellerName || ''),
    imageUrls: Array.isArray(d.imageUrls) ? d.imageUrls : [],
    status: String(d.status || 'active'),
    views: Number(d.views) || 0,
    createdAt: marketTsToIso(d.createdAt),
    updatedAt: marketTsToIso(d.updatedAt),
    publishedAt: marketTsToIso(d.publishedAt),
    adminNote: String(d.adminNote || ''),
    moderatedAt: marketTsToIso(d.moderatedAt),
    moderatedBy: String(d.moderatedBy || ''),
  };
}

/** Admin web: Onlayn BOZOR ro'yxati (Firestore rules custom token bilan emas). */
exports.adminListMarketAds = functions.https.onCall(async (data, context) => {
  await assertAdmin(String(data.adminPhone || ''), context);
  const snap = await db.collection('ads')
    .where('type', '==', 'cheap_product')
    .limit(500)
    .get();
  const ads = snap.docs.map(serializeMarketAdForAdmin);
  ads.sort((a, b) => {
    const ap = Date.parse(a.publishedAt || a.createdAt || 0) || 0;
    const bp = Date.parse(b.publishedAt || b.createdAt || 0) || 0;
    return bp - ap;
  });
  return { ads };
});

/** Admin web: Onlayn BOZOR e'lonini o'chirish. */
exports.adminDeleteMarketAd = functions.https.onCall(async (data, context) => {
  await assertAdmin(String(data.adminPhone || ''), context);
  const adId = String(data.adId || '').trim();
  if (!adId) {
    throw new functions.https.HttpsError('invalid-argument', 'adId required');
  }
  const { ref, snap } = await getMarketAdOrThrow(adId);
  const existing = snap.data() || {};
  await ref.delete();
  await deleteMarketAdStorageImages(existing.imageUrls || []);
  return { ok: true, adId };
});

/** Admin web: Onlayn BOZOR status (active/inactive). */
exports.adminUpdateMarketAdStatus = functions.https.onCall(async (data, context) => {
  const adminDocId = await assertAdmin(String(data.adminPhone || ''), context);
  const adId = String(data.adId || '').trim();
  const status = String(data.status || '').trim();
  if (!adId) {
    throw new functions.https.HttpsError('invalid-argument', 'adId required');
  }
  if (!ADMIN_MARKET_AD_STATUSES.has(status)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid status');
  }
  const { ref } = await getMarketAdOrThrow(adId);
  const patch = {
    status,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    moderatedAt: admin.firestore.FieldValue.serverTimestamp(),
    moderatedBy: adminDocId,
  };
  if (status === 'active') {
    patch.publishedAt = admin.firestore.FieldValue.serverTimestamp();
    patch.expiresAt = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + 60 * 24 * 60 * 60 * 1000),
    );
  }
  await ref.update(patch);
  return { ok: true, adId, status };
});

/** Admin web: Onlayn BOZOR e'lonini tahrirlash. */
exports.adminUpdateMarketAd = functions.https.onCall(async (data, context) => {
  const adminDocId = await assertAdmin(String(data.adminPhone || ''), context);
  const adId = String(data.adId || '').trim();
  if (!adId) {
    throw new functions.https.HttpsError('invalid-argument', 'adId required');
  }
  const { ref, snap } = await getMarketAdOrThrow(adId);
  const existing = snap.data() || {};
  const title = String(data.title != null ? data.title : (existing.title || '')).trim();
  if (!title) {
    throw new functions.https.HttpsError('invalid-argument', 'title required');
  }
  const description = String(
    data.description != null ? data.description : (existing.description || ''),
  ).trim();
  const priceRaw = data.price != null ? data.price : existing.price;
  const price = Math.max(0, Math.floor(Number(priceRaw) || 0));
  const phone = String(
    data.phone != null ? data.phone : (existing.phone || ''),
  ).trim();
  const sellerName = String(
    data.sellerName != null ? data.sellerName : (existing.sellerName || ''),
  ).trim();
  const patch = {
    title,
    titleLower: title.toLowerCase(),
    searchTokens: buildMarketSearchTokens(title, description),
    description,
    price,
    phone,
    sellerName,
    adminNote: String(
      data.adminNote != null ? data.adminNote : (existing.adminNote || ''),
    ).trim(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    moderatedAt: admin.firestore.FieldValue.serverTimestamp(),
    moderatedBy: adminDocId,
  };
  const status = String(data.status || '').trim();
  if (status && ADMIN_MARKET_AD_STATUSES.has(status)) {
    patch.status = status;
    if (status === 'active') {
      patch.publishedAt = admin.firestore.FieldValue.serverTimestamp();
      patch.expiresAt = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + 60 * 24 * 60 * 60 * 1000),
      );
    }
  }
  // phone — owner canonical; админ ҳам ўзгартирмасин
  if (existing.ownerId) {
    patch.phone = canonicalUid(String(existing.ownerId));
  }
  await ref.update(patch);
  return { ok: true, adId };
});

const MARKET_DAILY_AD_LIMIT = 5000;
const MARKET_MAX_PENDING = 5000;
const MARKET_MAX_ACTIVE = 5000;
const MARKET_ACTIVE_TTL_DAYS = 60;
const MARKET_PENDING_TTL_DAYS = 14;
const MARKET_MAX_PRICE = 100000000;
const MARKET_DAILY_REPORT_LIMIT = 20;

function marketActiveExpiresAt() {
  return admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + MARKET_ACTIVE_TTL_DAYS * 24 * 60 * 60 * 1000),
  );
}

function marketPhoneVariants(uid) {
  const u = canonicalUid(uid);
  return [...new Set([
    u,
    u.length >= 12 && u.startsWith('998') ? u.slice(3) : '',
  ].filter((p) => p.length >= 9))];
}

function marketImageUrlsOk(urls, uid) {
  if (!Array.isArray(urls) || urls.length < 1 || urls.length > 5) return false;
  const markers = marketPhoneVariants(uid).flatMap((p) => [
    `ads/${p}/`,
    `ads%2F${p}%2F`,
  ]);
  return urls.every((raw) => {
    const u = String(raw || '');
    if (u.length < 20 || u.length > 2000) return false;
    if (!u.startsWith('https://')) return false;
    return markers.some((m) => u.includes(m));
  });
}

/** Mijoz: Onlayn BOZOR эълон (CF-only, auth + canonical phone + лимитлар). */
exports.submitMarketAd = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }
  const uid = canonicalUid(callerPhone(context));
  if (!uid || uid.length < 9) {
    throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
  }

  const title = String((data && data.title) || '').trim();
  if (title.length < 3 || title.length > 120) {
    throw new functions.https.HttpsError('invalid-argument', 'title 3..120');
  }
  const description = String((data && data.description) || '').trim();
  if (description.length < 3 || description.length > 2000) {
    throw new functions.https.HttpsError('invalid-argument', 'description 3..2000');
  }
  const price = Math.floor(Number((data && data.price)));
  if (!Number.isFinite(price) || price < 1 || price > MARKET_MAX_PRICE) {
    throw new functions.https.HttpsError('invalid-argument', 'price invalid');
  }
  const sellerName = String((data && data.sellerName) || '').trim().slice(0, 80)
    || 'Сотувчи';
  const imageUrls = Array.isArray(data && data.imageUrls) ? data.imageUrls : [];
  if (!marketImageUrlsOk(imageUrls, uid)) {
    throw new functions.https.HttpsError(
      'invalid-argument', 'imageUrls 1..5 under ads/{uid}/');
  }

  const phoneVariants = marketPhoneVariants(uid);
  let activeCount = 0;
  let pendingCount = 0;
  for (const phoneKey of phoneVariants) {
    const [activeAgg, pendingAgg] = await Promise.all([
      db.collection('ads')
        .where('type', '==', 'cheap_product')
        .where('ownerId', '==', phoneKey)
        .where('status', '==', 'active')
        .count()
        .get(),
      db.collection('ads')
        .where('type', '==', 'cheap_product')
        .where('ownerId', '==', phoneKey)
        .where('status', '==', 'pending')
        .count()
        .get(),
    ]);
    activeCount += activeAgg.data().count || 0;
    pendingCount += pendingAgg.data().count || 0;
  }
  if (activeCount >= MARKET_MAX_ACTIVE) {
    throw new functions.https.HttpsError(
      'resource-exhausted', 'Active ad limit reached');
  }
  if (pendingCount >= MARKET_MAX_PENDING) {
    throw new functions.https.HttpsError(
      'resource-exhausted', 'Pending ad limit reached');
  }

  const dayStart = new Date();
  dayStart.setHours(0, 0, 0, 0);
  let todayCount = 0;
  for (const phoneKey of phoneVariants) {
    const recentAgg = await db.collection('ads')
      .where('type', '==', 'cheap_product')
      .where('ownerId', '==', phoneKey)
      .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(dayStart))
      .count()
      .get();
    todayCount += recentAgg.data().count || 0;
    if (todayCount >= MARKET_DAILY_AD_LIMIT) break;
  }
  if (todayCount >= MARKET_DAILY_AD_LIMIT) {
    throw new functions.https.HttpsError(
      'resource-exhausted', 'Daily ad limit reached');
  }

  const autoApprove = await isMarketAutoApproveEnabled();
  const expiresAt = autoApprove
    ? marketActiveExpiresAt()
    : admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + MARKET_PENDING_TTL_DAYS * 24 * 60 * 60 * 1000),
    );

  const payload = {
    type: 'cheap_product',
    ownerId: uid,
    title,
    titleLower: title.toLowerCase(),
    searchTokens: buildMarketSearchTokens(title, description),
    description,
    price,
    phone: uid,
    sellerName,
    imageUrls: imageUrls.map((u) => String(u)),
    status: autoApprove ? 'active' : 'pending',
    views: 0,
    expiresAt,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (autoApprove) {
    payload.publishedAt = admin.firestore.FieldValue.serverTimestamp();
    payload.moderatedBy = 'auto';
    payload.moderatedAt = admin.firestore.FieldValue.serverTimestamp();
  }

  const ref = await db.collection('ads').add(payload);
  return { ok: true, adId: ref.id, status: payload.status };
});

/** Mijoz: Onlayn BOZOR шикоят → reports (CF-only). */
exports.submitMarketComplaint = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }
  const uid = canonicalUid(callerPhone(context));
  if (!uid || uid.length < 9) {
    throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
  }
  const adId = String((data && data.adId) || '').trim();
  const reason = String((data && data.reason) || '').trim();
  if (!adId) {
    throw new functions.https.HttpsError('invalid-argument', 'adId required');
  }
  if (reason.length < 3 || reason.length > 300) {
    throw new functions.https.HttpsError('invalid-argument', 'reason 3..300');
  }

  const { snap } = await getMarketAdOrThrow(adId);
  const ad = snap.data() || {};
  const owner = canonicalUid(String(ad.ownerId || ''));
  if (owner && owner === uid) {
    throw new functions.https.HttpsError(
      'failed-precondition', 'Cannot report own ad');
  }

  const dayStart = new Date();
  dayStart.setHours(0, 0, 0, 0);
  const todaySnap = await db.collection('reports')
    .where('type', '==', 'market_ad')
    .where('reporterId', '==', uid)
    .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(dayStart))
    .limit(MARKET_DAILY_REPORT_LIMIT + 1)
    .get();
  if (todaySnap.size >= MARKET_DAILY_REPORT_LIMIT) {
    throw new functions.https.HttpsError(
      'resource-exhausted', 'Daily complaint limit reached');
  }

  const openSnap = await db.collection('reports')
    .where('type', '==', 'market_ad')
    .where('reporterId', '==', uid)
    .where('targetId', '==', adId)
    .where('status', '==', 'open')
    .limit(1)
    .get();
  if (!openSnap.empty) {
    return { ok: true, reportId: openSnap.docs[0].id, duplicate: true };
  }

  const ref = db.collection('reports').doc();
  await ref.set({
    type: 'market_ad',
    reporterId: uid,
    targetId: adId,
    reason,
    status: 'open',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { ok: true, reportId: ref.id };
});

const ADMIN_ORDER_STATUSES = new Set([
  'new', 'accepted', 'ready', 'in_delivery', 'delivered', 'rejected',
]);

/** Admin web: буюртма status (Firestore rules `isAdmin()` custom token bilan ишламайди). */
exports.adminSetOrderStatus = functions.https.onCall(async (data, context) => {
  await assertAdmin(String(data.adminPhone || ''), context);
  const orderId = String(data.orderId || '').trim();
  const status = String(data.status || '').trim();
  if (!orderId) {
    throw new functions.https.HttpsError('invalid-argument', 'orderId required');
  }
  if (!ADMIN_ORDER_STATUSES.has(status)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid status');
  }
  const ref = db.collection('orders').doc(orderId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'Order not found');
  }
  await ref.update(buildOrderStatusPatch(status));
  return { ok: true, orderId, status };
});

/** Admin web: бир нечта буюртма status (Kanban ustun tugmasi). */
exports.adminSetOrderStatusBatch = functions.https.onCall(async (data, context) => {
  await assertAdmin(String(data.adminPhone || ''), context);
  const status = String(data.status || '').trim();
  const orderIds = Array.isArray(data.orderIds)
    ? data.orderIds.map((id) => String(id || '').trim()).filter(Boolean)
    : [];
  if (orderIds.length === 0) {
    throw new functions.https.HttpsError('invalid-argument', 'orderIds required');
  }
  if (!ADMIN_ORDER_STATUSES.has(status)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid status');
  }
  const patch = buildOrderStatusPatch(status);
  let batch = db.batch();
  let writes = 0;
  let updated = 0;
  for (const orderId of orderIds) {
    const ref = db.collection('orders').doc(orderId);
    const snap = await ref.get();
    if (!snap.exists) continue;
    batch.update(ref, patch);
    writes += 1;
    updated += 1;
    if (writes >= 450) {
      await batch.commit();
      batch = db.batch();
      writes = 0;
    }
  }
  if (writes > 0) await batch.commit();
  return { ok: true, updated, status };
});

/** Admin: sell_submission → collection_task (йiғib оlish). */
exports.adminCreateCollectionTask = functions.https.onCall(async (data, context) => {
  try {
    const adminUid = await assertAdmin(String(data.adminPhone || ''), context);
    const submissionId = String(data.submissionId || '').trim();
    const courierPhone = String(data.courierPhone || '');
    const itemsIn = Array.isArray(data.items) ? data.items : [];

    if (!submissionId) {
      throw new functions.https.HttpsError('invalid-argument', 'submissionId required');
    }
    if (itemsIn.length < 1) {
      throw new functions.https.HttpsError('invalid-argument', 'items required');
    }

    const submissionRef = db.collection('sell_submissions').doc(submissionId);
    const submissionSnap = await submissionRef.get();
    if (!submissionSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'submission not found');
    }
    const submission = submissionSnap.data() || {};

    if (submission.collectionTaskId || submission.inCollection === true) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'submission already in collection',
      );
    }

    const courierId = await resolveAuthorizedCourierUid(courierPhone);

    const normalizedItems = [];
    let totalValue = 0;
    for (let i = 0; i < itemsIn.length; i += 1) {
      const row = itemsIn[i] || {};
      const code = String(row.code || '').trim();
      const label = String(row.label || '').trim();
      const unit = String(row.unit || '').trim();
      const qty = Number(row.qty);
      const unitPrice = parseInt(String(row.unitPrice ?? 0), 10);
      if (!code || !label) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          `items[${i}]: code and label required`,
        );
      }
      if (!Number.isFinite(qty) || qty <= 0) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          `items[${i}]: qty must be positive`,
        );
      }
      if (!Number.isFinite(unitPrice) || unitPrice < 0) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          `items[${i}]: unitPrice must be >= 0`,
        );
      }
      const lineTotal = Math.round(qty * unitPrice);
      totalValue += lineTotal;
      normalizedItems.push({
        code,
        label,
        unit,
        qty,
        unitPrice,
        lineTotal,
      });
    }

    const customerUid = digits(submission.userId || submission.userPhone || '');
    const customerPhone = digits(submission.userPhone || submission.userId || '');
    const taskRef = db.collection('collection_tasks').doc();

    await db.runTransaction(async (t) => {
      const freshSubmission = await t.get(submissionRef);
      if (!freshSubmission.exists) {
        throw new functions.https.HttpsError('not-found', 'submission not found');
      }
      const fresh = freshSubmission.data() || {};
      if (fresh.collectionTaskId || fresh.inCollection === true) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'submission already in collection',
        );
      }

      t.set(taskRef, {
        submissionId,
        customerPhone,
        customerUid,
        customerName: String(fresh.userName || ''),
        pickupAddress: String(fresh.pickupAddress || ''),
        pickupLat: fresh.pickupLat != null ? Number(fresh.pickupLat) : null,
        pickupLng: fresh.pickupLng != null ? Number(fresh.pickupLng) : null,
        items: normalizedItems,
        totalValue,
        courierId,
        status: 'assigned',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: adminUid,
      });

      t.update(submissionRef, {
        status: 'reviewed',
        collectionTaskId: taskRef.id,
        inCollection: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return { ok: true, taskId: taskRef.id, totalValue };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('adminCreateCollectionTask:', e);
    const msg = e && e.message ? String(e.message) : 'adminCreateCollectionTask failed';
    throw new functions.https.HttpsError('internal', msg);
  }
});

/** Админ — омбор (`warehouse_stock`) ҳолатини ўқиш (read-only).
 *  Веб-админ Firestore'да isAdmin() эмас, шунинг учун Admin SDK орқали ўқиймиз.
 */
exports.adminGetWarehouseStock = functions.https.onCall(async (data, context) => {
  try {
    await assertAdmin(String(data.adminPhone || ''), context);

    const snap = await db.collection('warehouse_stock').get();
    const items = snap.docs.map((doc) => {
      const d = doc.data() || {};
      const updatedAt = d.updatedAt;
      let updatedAtMs = null;
      if (updatedAt && typeof updatedAt.toMillis === 'function') {
        updatedAtMs = updatedAt.toMillis();
      }
      return {
        code: String(d.code || doc.id),
        label: String(d.label || ''),
        unit: String(d.unit || ''),
        quantity: Number(d.quantity) || 0,
        updatedAt: updatedAtMs,
      };
    });

    items.sort((a, b) => a.label.localeCompare(b.label));

    return { items };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('adminGetWarehouseStock:', e);
    const msg = e && e.message ? String(e.message) : 'adminGetWarehouseStock failed';
    throw new functions.https.HttpsError('internal', msg);
  }
});

/** Курьер: йиғиб оlish манзилига етиб келди — мижозга қўнғироқли хабар. */
exports.courierMarkCollectionArrived = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Login required');
    }
    const courierId = assertCourierPhone(data.courierPhone);
    if (callerPhone(context) !== courierId) {
      throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
    }
    await resolveAuthorizedCourierUid(data.courierPhone);

    const taskId = String(data.taskId || '').trim();
    if (!taskId) {
      throw new functions.https.HttpsError('invalid-argument', 'taskId required');
    }

    const taskRef = db.collection('collection_tasks').doc(taskId);
    const taskSnap = await taskRef.get();
    if (!taskSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'task not found');
    }
    const task = taskSnap.data() || {};

    if (String(task.courierId || '') !== courierId) {
      throw new functions.https.HttpsError('permission-denied', 'Not your task');
    }
    if (!['assigned', 'collecting'].includes(String(task.status || ''))) {
      throw new functions.https.HttpsError('failed-precondition', 'task not active');
    }
    if (task.arrivedAt) {
      return { ok: true, idempotent: true, taskId };
    }

    const patch = {
      arrivedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (String(task.status || '') === 'assigned') {
      patch.status = 'collecting';
    }
    await taskRef.update(patch);

    try {
      const customerPhone = task.customerPhone || task.customerUid || '';
      await notifyCourierArrivedToCustomer(customerPhone, {
        taskId,
        module: 'collection',
      });
    } catch (e) {
      console.error('courierMarkCollectionArrived notify:', e.message || e);
    }

    return { ok: true, taskId };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('courierMarkCollectionArrived:', e);
    const msg = e && e.message ? String(e.message) : 'courierMarkCollectionArrived failed';
    throw new functions.https.HttpsError('internal', msg);
  }
});

/** Курьер: йиғиб олишни якунлаш — кошелёк кредити + омбор + далолатнома.
 *  Тескари иқтисод: платформа мижозга маҳсулот учун ТЎЛАЙДИ.
 */
exports.courierFinalizeCollection = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Login required');
    }
    const courierId = assertCourierPhone(data.courierPhone);
    if (callerPhone(context) !== courierId) {
      throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
    }
    await resolveAuthorizedCourierUid(data.courierPhone);

    const taskId = String(data.taskId || '').trim();
    if (!taskId) {
      throw new functions.https.HttpsError('invalid-argument', 'taskId required');
    }
    const itemsIn = Array.isArray(data.items) ? data.items : [];
    if (itemsIn.length < 1 || itemsIn.length > 50) {
      throw new functions.https.HttpsError('invalid-argument', 'items required');
    }
    const cashGiven = parseInt(String(data.cashGiven ?? 0), 10);
    if (!Number.isFinite(cashGiven) || cashGiven < 0) {
      throw new functions.https.HttpsError('invalid-argument', 'cashGiven must be >= 0');
    }

    const taskRef = db.collection('collection_tasks').doc(taskId);
    const taskSnap = await taskRef.get();
    if (!taskSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'task not found');
    }
    const task = taskSnap.data() || {};

    // Idempotency: якунланган бўлса — сақланган натижани қайтарамиз.
    if (task.status === 'completed') {
      return {
        ok: true,
        alreadyCompleted: true,
        V: parseInt(String(task.finalValue ?? 0), 10) || 0,
        cashGiven: parseInt(String(task.cashGiven ?? 0), 10) || 0,
        walletDelta: parseInt(String(task.walletDelta ?? 0), 10) || 0,
        walletCredit: parseInt(String(task.walletCredited ?? 0), 10) || 0,
        withdrawnFromBalance:
          parseInt(String(task.withdrawnFromBalance ?? 0), 10) || 0,
        newBalance: null,
      };
    }
    if (String(task.courierId || '') !== courierId) {
      throw new functions.https.HttpsError('permission-denied', 'Not your task');
    }
    if (!['assigned', 'collecting'].includes(String(task.status || ''))) {
      throw new functions.https.HttpsError('failed-precondition', 'task not active');
    }
    if (!task.arrivedAt) {
      throw new functions.https.HttpsError('failed-precondition', 'arrived first');
    }

    const normalizedItems = [];
    let totalValue = 0;
    for (let i = 0; i < itemsIn.length; i += 1) {
      const row = itemsIn[i] || {};
      const code = String(row.code || '').trim();
      const label = String(row.label || '').trim();
      const unit = String(row.unit || '').trim();
      const qty = Number(row.qty);
      const unitPrice = parseInt(String(row.unitPrice ?? 0), 10);
      if (!code || !label) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          `items[${i}]: code and label required`,
        );
      }
      if (!Number.isFinite(qty) || qty <= 0) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          `items[${i}]: qty must be positive`,
        );
      }
      if (!Number.isFinite(unitPrice) || unitPrice < 0) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          `items[${i}]: unitPrice must be >= 0`,
        );
      }
      const lineTotal = Math.round(qty * unitPrice);
      totalValue += lineTotal;
      normalizedItems.push({ code, label, unit, qty, unitPrice, lineTotal });
    }

    const customerPhone = String(task.customerPhone || task.customerUid || '');
    const uid9 = userUid(customerPhone);
    const uid12 = canonicalUid(customerPhone);
    let customerRef = db.collection('users').doc(uid12);
    let customerSnap = await customerRef.get();
    if (!customerSnap.exists && uid9 !== uid12) {
      customerRef = db.collection('users').doc(uid9);
      customerSnap = await customerRef.get();
    }
    if (!customerSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'customer user not found');
    }

    // Бир атом транзакция: status guard (идемпотентлик) + баланс текшируви
    // + барча ёзувлар. M (нақд) V дан ошса — фарқ мижоз кошелёгидан олинади.
    const walletDelta = totalValue - cashGiven; // ишорали: + кредит, - ечиш
    const withdrawnFromBalance = Math.max(0, cashGiven - totalValue);
    const walletCredit = Math.max(0, totalValue - cashGiven);
    let newBalance = 0;

    await db.runTransaction(async (t) => {
      const fresh = await t.get(taskRef);
      const freshData = fresh.data() || {};
      if (!fresh.exists || !['assigned', 'collecting'].includes(String(freshData.status || ''))) {
        throw new functions.https.HttpsError('failed-precondition', 'task not active');
      }

      const customerInTxn = await t.get(customerRef);
      const prevBalance =
        parseInt(String(customerInTxn.data()?.bonusBalance ?? 0), 10) || 0;

      const maxCash = totalValue + prevBalance;
      if (cashGiven > maxCash) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          `cash_exceeds_balance: cashGiven ${cashGiven} > max ${maxCash} ` +
            `(V ${totalValue} + balance ${prevBalance})`,
        );
      }
      newBalance = prevBalance + walletDelta;

      // Ledger ko'zgusi (READ fazasi) — kredit→admin_clearing, naqd echish→admin_cash.
      const bonusFunding = walletDelta >= 0 ? 'admin_clearing' : 'admin_cash';
      const bonusCtx = await settlementLedger.prepareBonusInTx(t, db, customerRef.id, {
        idempotencyKey: `collection_${taskId}`,
        fundingAccount: bonusFunding,
      });

      t.update(customerRef, {
        bonusBalance: admin.firestore.FieldValue.increment(walletDelta),
        balanceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      if (totalValue > 0) {
        t.set(customerRef.collection('wallet_ledger').doc(), {
          type: 'supplier_credit',
          amount: totalValue,
          module: 'collection',
          refType: 'collection',
          refId: taskId,
          meta: { totalValue, cashGiven },
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          createdBy: 'courier_collection',
        });
      }
      if (cashGiven > 0) {
        t.set(customerRef.collection('wallet_ledger').doc(), {
          type: 'collection_cashout',
          amount: -cashGiven,
          module: 'collection',
          refType: 'collection',
          refId: taskId,
          meta: { totalValue, withdrawnFromBalance },
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          createdBy: 'courier_collection',
        });
      }

      // Ledger ko'zgusi (WRITE fazasi) — net walletDelta (signed).
      if (walletDelta !== 0) {
        settlementLedger.commitBonusInTx(t, bonusCtx, {
          delta: walletDelta,
          kind: 'collection',
          refType: 'collection',
          refId: taskId,
          meta: { module: 'collection', totalValue, cashGiven },
          postedBy: 'courier_collection',
          postedRole: 'courier',
        });
      }

      for (let i = 0; i < normalizedItems.length; i += 1) {
        const item = normalizedItems[i];
        t.set(
          db.collection('warehouse_stock').doc(item.code),
          {
            code: item.code,
            label: item.label,
            unit: item.unit,
            quantity: admin.firestore.FieldValue.increment(item.qty),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }

      t.update(taskRef, {
        status: 'completed',
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        cashGiven,
        walletDelta,
        walletCredited: walletCredit,
        withdrawnFromBalance,
        finalItems: normalizedItems,
        finalValue: totalValue,
      });

      const submissionId = String(task.submissionId || '');
      if (submissionId) {
        t.set(
          db.collection('sell_submissions').doc(submissionId),
          {
            status: 'reviewed',
            collectionCompleted: true,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
    });

    const receiptLines = [];
    receiptLines.push(`Маҳсулотлар қабул қилинди: ${totalValue} сўм.`);
    for (let i = 0; i < normalizedItems.length; i += 1) {
      const it = normalizedItems[i];
      receiptLines.push(
        `• ${it.label}: ${it.qty}${it.unit ? ` ${it.unit}` : ''} × ${it.unitPrice} = ${it.lineTotal} сўм`,
      );
    }
    if (cashGiven > 0) {
      receiptLines.push(`💵 Нақд берилди: ${cashGiven} сўм.`);
    }
    if (walletCredit > 0) {
      receiptLines.push(`💼 Кошелёкка қўшилди: ${walletCredit} сўм.`);
    }
    if (withdrawnFromBalance > 0) {
      receiptLines.push(
        `💼 Кошелёкдан нақд олинди: ${withdrawnFromBalance} сўм.`,
      );
    }
    receiptLines.push(`💼 Янги баланс: ${newBalance} сўм`);

    try {
      await notifyUserInApp({
        userId: customerRef.id,
        title: '✅ Маҳсулот қабул қилинди',
        body: receiptLines.join('\n'),
        category: 'order',
        source: 'collection_receipt',
        dataType: 'order_payment',
        screen: 'profile',
        extraData: { taskId },
      });
    } catch (e) {
      console.error('courierFinalizeCollection receipt push:', e.message || e);
    }

    return {
      ok: true,
      V: totalValue,
      cashGiven,
      walletDelta,
      walletCredit,
      withdrawnFromBalance,
      newBalance,
    };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('courierFinalizeCollection:', e);
    const msg = e && e.message ? String(e.message) : 'courierFinalizeCollection failed';
    throw new functions.https.HttpsError('internal', msg);
  }
});

/** Админ: чиқариш талабини рад этиш */
exports.rejectPayout = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated', 'Auth required');
  }
  const callerPhone = context.auth.token.phone_number
      ?.replace(/\D/g, '') ?? '';
  const callerDoc = await db.collection('users')
      .doc(callerPhone).get();
  const callerRole = callerDoc.data()?.role ?? 'user';
  if (!['admin', 'superadmin', 'dispatcher'].includes(callerRole)) {
    throw new functions.https.HttpsError(
      'permission-denied', 'Admin role required');
  }

  const requestId = String(data.requestId || '');
  if (!requestId) {
    throw new functions.https.HttpsError('invalid-argument', 'requestId required');
  }

  const reqRef = db.collection('payout_requests').doc(requestId);
  const reqSnap = await reqRef.get();
  if (!reqSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'request not found');
  }
  if (reqSnap.data().status !== 'pending') {
    throw new functions.https.HttpsError('failed-precondition', 'not pending');
  }

  await reqRef.update({
    status: 'rejected',
    rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
    rejectedBy: digits(callerPhone),
  });

  return { ok: true };
});

/** Админ web: фoydalanuvchi rolini boshqarish (admin ↔ user). */
exports.setUserRoleByAdmin = functions.https.onCall(async (data, context) => {
  const adminPhone = String(data.adminPhone || '');
  const adminUid = await assertAdmin(adminPhone, context);

  const targetRaw = String(data.targetPhone || data.userPhone || '');
  const targetCanon = canonicalUid(targetRaw);
  const targetDigits = digits(targetRaw);
  if (targetDigits.length < 9) {
    throw new functions.https.HttpsError('invalid-argument', 'Telefon raqami noto\'g\'ri');
  }

  const role = String(data.role || 'user').trim();
  const allowedAll = ['user', 'admin', 'finance', 'auditor', 'seller', 'superadmin'];
  if (!allowedAll.includes(role)) {
    throw new functions.https.HttpsError('invalid-argument', 'Rol ruxsat etilmagan');
  }

  if (canonicalUid(adminPhone) === targetCanon && role !== 'admin' && role !== 'superadmin') {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'O\'zingizni adminlikdan olib tashlay olmaysiz',
    );
  }

  // users/{998…} yoki legacy 9 xona — mavjud doc ni top.
  let ref = db.collection('users').doc(targetCanon);
  let snap = await ref.get();
  if (!snap.exists && targetDigits !== targetCanon) {
    ref = db.collection('users').doc(targetDigits);
    snap = await ref.get();
  }
  if (!snap.exists) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Bu telefon Firestore\'da yo\'q. Avval ilovada ro\'yxatdan o\'ting.',
    );
  }

  const currentRole = String((snap.data() || {}).role || 'user');
  const adminSnap = await db.collection('users').doc(adminUid).get();
  const adminRole = String((adminSnap.data() || {}).role || 'user');

  // SoD: oddiy admin faqat seller / user; privileged faqat superadmin.
  if (adminRole === 'admin') {
    const allowedByAdmin = ['user', 'seller'];
    if (!allowedByAdmin.includes(role)) {
      throw new functions.https.HttpsError(
          'permission-denied',
          'Admin faqat Sotuvchi (yoki oddiy) rolini beradi',
      );
    }
    const privileged = ['admin', 'superadmin', 'finance', 'auditor'];
    if (privileged.includes(currentRole)) {
      throw new functions.https.HttpsError(
          'permission-denied',
          'Bu foydalanuvchi rolini faqat Super Admin o\'zgartiradi',
      );
    }
  } else if (adminRole !== 'superadmin') {
    throw new functions.https.HttpsError(
        'permission-denied',
        'Rol berish uchun Admin yoki Super Admin kerak',
    );
  }

  if (currentRole === 'superadmin' && adminRole !== 'superadmin') {
    throw new functions.https.HttpsError('permission-denied', 'Superadmin rolini faqat superadmin o\'zgartiradi');
  }
  if (role === 'superadmin' && adminRole !== 'superadmin') {
    throw new functions.https.HttpsError('permission-denied', 'Superadmin berish ruxsati yo\'q');
  }

  await ref.set({
    role,
    roleUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    roleUpdatedBy: adminUid,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  // uid = Firestore doc id (998… yoki legacy 9 xona).
  return { ok: true, uid: ref.id, role };
});

function normalizeDriverTaxiType(type) {
  const t = String(type || '').trim();
  if (t === 'marshrut') return 'marshrut';
  if (t === 'intercity') return 'intercity';
  return 'local';
}

function driverTaxiTypeLabel(type) {
  switch (normalizeDriverTaxiType(type)) {
    case 'marshrut':
      return 'Маршрут такси';
    case 'intercity':
      return 'Шаҳарлараро';
    default:
      return 'Маҳаллий такси';
  }
}

function parseCarModelFromApplication(car) {
  const s = String(car || '').trim();
  if (!s) return '';
  const parts = s.split('·');
  if (parts.length > 1) return parts[0].trim();
  return s;
}

function maxSeatsForCarModel(model) {
  const m = String(model || '').toLowerCase();
  if (m.includes('damas') || m.includes('дамас')) return 6;
  return 4;
}

function buildMarshrutStopsFromRequest(req) {
  const from = String(req.routeFrom || '').trim();
  const to = String(req.routeTo || '').trim();
  const mids = Array.isArray(req.routeStops) ? req.routeStops : [];
  const stops = [];
  if (from) stops.push(from);
  for (const m of mids) {
    const t = String(m || '').trim();
    if (t && !stops.includes(t)) stops.push(t);
  }
  if (to && to !== from && !stops.includes(to)) stops.push(to);
  return stops.length >= 2 ? stops : (from && to ? [from, to] : stops);
}

function routeFieldsFromPayload(data) {
  const from = String(data.routeFrom || '').trim();
  const to = String(data.routeTo || '').trim();
  const stops = Array.isArray(data.routeStops)
    ? data.routeStops.map((s) => String(s || '').trim()).filter(Boolean)
    : [];
  if (!from && !to) return {};
  const label = stops.length === 0
    ? `${from} → ${to}`
    : `${from} → ${stops.join(' → ')} → ${to}`;
  return {
    routeFrom: from,
    routeTo: to,
    ...(stops.length > 0 ? { routeStops: stops } : {}),
    routeLabel: label,
  };
}

/** Admin SDK — haydovchi arizasini tasdiqlash (umumiy). */
async function applyDriverRequestApproval(requestId, req, approvedBy) {
  let userPhone = canonicalUid(req.phone || requestId);
  if (digits(userPhone).length < 9) {
    userPhone = canonicalUid(requestId);
  }
  if (digits(userPhone).length < 9) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Telefon raqami topilmadi',
    );
  }

  const taxiType = normalizeDriverTaxiType(req.taxiType);
  const name = String(req.name || '').trim();
  const phoneRaw = String(req.phone || userPhone).trim();
  let car = String(req.car || '').trim();
  let plate = String(req.plate || '').trim();

  const userRef = db.collection('users').doc(userPhone);
  const userSnap = await userRef.get();
  const userData = userSnap.exists ? (userSnap.data() || {}) : {};

  if (!car || !plate) {
    car = car || String(userData.carModel || '').trim();
    plate = plate || String(userData.carPlate || '').trim();
  }

  const batch = db.batch();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const reqRef = db.collection('driver_requests').doc(requestId);

  batch.update(reqRef, {
    status: 'approved',
    approvedAt: now,
    approvedBy,
    approvalMode: approvedBy === 'auto' ? 'auto' : 'admin',
    updatedAt: now,
  });

  const driverRef = db.collection('drivers').doc(userPhone);
  batch.set(
    driverRef,
    {
      name,
      phone: phoneRaw || userPhone,
      car,
      car_model: car,
      car_plate: plate,
      plate,
      taxiType,
      taxiTypes: admin.firestore.FieldValue.arrayUnion(taxiType),
      approved: true,
      approvalStatus: 'approved',
      approvedAt: now,
      approvedBy,
      updatedAt: now,
    },
    { merge: true },
  );

  if (taxiType === 'intercity') {
    batch.set(
      db.collection('intercity_drivers').doc(userPhone),
      {
        name,
        phone: phoneRaw || userPhone,
        phoneDigits: userPhone,
        car,
        plate,
        isActive: true,
        isOnPanel: false,
        updatedAt: now,
      },
      { merge: true },
    );
  }

  if (taxiType === 'marshrut') {
    const carModel = parseCarModelFromApplication(car);
    const stops = buildMarshrutStopsFromRequest(req);
    const userSeats = Number(userData.carSeats) || 0;
    const resolvedSeats = userSeats > 0 ? userSeats : maxSeatsForCarModel(carModel);
    batch.set(
      db.collection('users').doc(userPhone).collection('driverProfiles').doc('marshrut'),
      {
        carModel: car,
        plate: plate.toUpperCase(),
        seats: resolvedSeats,
        stops,
        driverName: name,
        driverPhone: phoneRaw || userPhone,
        startTime: '07:00',
        isActive: true,
        approvedFromApplication: true,
        updatedAt: now,
      },
      { merge: true },
    );
  }

  if (userSnap.exists) {
    const currentRole = String(userData.role || 'user');
    if (currentRole === 'user' || currentRole === '') {
      batch.set(
        userRef,
        { role: 'driver', updatedAt: now },
        { merge: true },
      );
    }
  }

  if (phoneRaw.length >= 9 || userPhone.length >= 9) {
    const targetPhone = userPhone;
    const notifRef = db.collection('notifications').doc();
    batch.set(notifRef, {
      targetPhone,
      title: '✅ Ҳайдовчи аризангиз тасдиқланди',
      body: `${driverTaxiTypeLabel(taxiType)} бўйича ишга чиқишингиз мумкин.`,
      sent: false,
      type: 'driver_request_approved',
      taxiType,
      requestId,
      createdAt: now,
    });
  }

  await batch.commit();
  return { ok: true, uid: userPhone, taxiType };
}

/** Marshrut haydovchini navbat/reysdan to‘liq chiqarish (Admin revoke). */
async function removeDriverFromMarshrutRoute(userPhone, batch, now, reason) {
  const schedSnap = await db
    .collection('schedules')
    .where('driverId', '==', userPhone)
    .where('taxiType', '==', 'marshrut')
    .where('isActive', '==', true)
    .get();
  for (const doc of schedSnap.docs) {
    batch.update(doc.ref, {
      isActive: false,
      removedFromRouteAt: now,
      updatedAt: now,
    });
  }

  batch.set(
    db.collection('queue').doc(userPhone),
    {
      isActive: false,
      revokedAt: now,
      revokedReason: reason,
      autoPausedReason: admin.firestore.FieldValue.delete(),
      autoPausedAt: admin.firestore.FieldValue.delete(),
      updatedAt: now,
    },
    { merge: true },
  );

  batch.set(
    db.collection('drivers').doc(userPhone),
    {
      isOnline: false,
      isBusy: false,
      isAvailable: false,
      seatsLeft: 0,
      removedFromRouteAt: now,
      updatedAt: now,
    },
    { merge: true },
  );

  batch.set(
    db.collection('users').doc(userPhone).collection('driverProfiles').doc('marshrut'),
    {
      isActive: false,
      revokedAt: now,
      updatedAt: now,
    },
    { merge: true },
  );

  batch.delete(
    db.collection('users').doc(userPhone).collection('marshrut_state').doc('active'),
  );
}

/** Mobil: `driverApprovalMode == auto` — ariza + darhol tasdiq (Admin SDK). */
exports.autoApproveDriverApplication = functions.https.onCall(async (data, context) => {
  const authPhone = context.auth && context.auth.token
    ? String(context.auth.token.phone_number || '').trim()
    : '';
  if (!context.auth || !authPhone) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Ариза юбориш учун телефон рақамингизни тасдиқланг',
    );
  }
  const appSnap = await db.collection('settings').doc('app').get();
  const mode = String((appSnap.data() || {}).driverApprovalMode || 'manual');
  if (mode !== 'auto') {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Avto-tasdiq o‘chirilgan',
    );
  }

  const requestId = canonicalUid(data.uid || data.phone || '');
  if (digits(requestId).length < 12) {
    throw new functions.https.HttpsError('invalid-argument', 'Telefon raqami noto‘g‘ri');
  }

  const taxiType = normalizeDriverTaxiType(data.taxiType);
  if (!['intercity', 'marshrut', 'alone', 'local'].includes(taxiType)) {
    throw new functions.https.HttpsError('invalid-argument', 'taxiType noto‘g‘ri');
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const reqRef = db.collection('driver_requests').doc(requestId);
  const existing = await reqRef.get();
  const payload = {
    uid: requestId,
    name: String(data.name || '').trim(),
    phone: String(data.phone || '').trim(),
    car: String(data.car || '').trim(),
    plate: String(data.plate || '').trim(),
    taxiType,
    status: 'pending',
    updatedAt: now,
    ...routeFieldsFromPayload(data),
  };
  if (!existing.exists) {
    payload.createdAt = now;
  } else {
    const prev = existing.data() || {};
    if (prev.status === 'rejected') {
      payload.rejectedAt = admin.firestore.FieldValue.delete();
      payload.rejectedReason = admin.firestore.FieldValue.delete();
      payload.rejectedBy = admin.firestore.FieldValue.delete();
    }
  }
  await reqRef.set(payload, { merge: true });

  const reqSnap = await reqRef.get();
  const req = reqSnap.data() || {};
  const status = String(req.status || 'pending');
  if (status === 'approved') {
    return { ok: true, uid: requestId, taxiType, alreadyApproved: true };
  }
  if (status !== 'pending') {
    throw new functions.https.HttpsError('failed-precondition', 'Ariza pending emas');
  }

  return applyDriverRequestApproval(requestId, req, 'auto');
});

/** Админ: haydovchi arizasini tasdiqlash (Admin SDK batch). */
exports.approveDriverRequest = functions.https.onCall(async (data, context) => {
  const adminPhone = String(data.adminPhone || '');
  const adminUid = await assertAdmin(adminPhone, context);

  const requestId = String(data.requestId || '').trim();
  if (!requestId) {
    throw new functions.https.HttpsError('invalid-argument', 'requestId majburiy');
  }

  const reqRef = db.collection('driver_requests').doc(requestId);
  const reqSnap = await reqRef.get();
  if (!reqSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Ariza topilmadi');
  }

  const req = reqSnap.data() || {};
  const status = String(req.status || 'pending');
  if (status !== 'pending') {
    throw new functions.https.HttpsError('failed-precondition', 'Ariza pending emas');
  }

  const result = await applyDriverRequestApproval(requestId, req, adminUid);
  return { ...result, warnings: [] };
});

/** Админ: haydovchi arizasini rad etish. */
exports.rejectDriverRequest = functions.https.onCall(async (data, context) => {
  const adminPhone = String(data.adminPhone || '');
  const adminUid = await assertAdmin(adminPhone, context);

  const requestId = String(data.requestId || '').trim();
  const reason = String(data.reason || '').trim();
  if (!requestId) {
    throw new functions.https.HttpsError('invalid-argument', 'requestId majburiy');
  }
  if (!reason) {
    throw new functions.https.HttpsError('invalid-argument', 'Rad etish sababi majburiy');
  }
  if (reason.length > 500) {
    throw new functions.https.HttpsError('invalid-argument', 'Sabab juda uzun');
  }

  const reqRef = db.collection('driver_requests').doc(requestId);
  const reqSnap = await reqRef.get();
  if (!reqSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Ariza topilmadi');
  }

  const req = reqSnap.data() || {};
  if (String(req.status || 'pending') !== 'pending') {
    throw new functions.https.HttpsError('failed-precondition', 'Ariza pending emas');
  }

  const taxiType = normalizeDriverTaxiType(req.taxiType);
  const phoneRaw = String(req.phone || '').trim();
  let targetPhone = digits(phoneRaw);
  if (targetPhone.length < 9) {
    targetPhone = digits(requestId);
  }

  const batch = db.batch();
  const now = admin.firestore.FieldValue.serverTimestamp();

  batch.update(reqRef, {
    status: 'rejected',
    rejectedAt: now,
    rejectedBy: adminUid,
    rejectedReason: reason,
    updatedAt: now,
  });

  if (targetPhone.length >= 9) {
    batch.set(db.collection('notifications').doc(), {
      targetPhone,
      title: '❌ Ҳайдовчи аризангиз рад этилди',
      body: `${driverTaxiTypeLabel(taxiType)}: ${reason}`,
      sent: false,
      type: 'driver_request_rejected',
      taxiType,
      requestId,
      createdAt: now,
    });
  }

  await batch.commit();
  return { ok: true };
});

/** Админ: tasdiqlangan haydovchini faol bo‘lmaganda ruxsatdan chiqarish. */
exports.revokeDriverApproval = functions.https.onCall(async (data, context) => {
  const adminPhone = String(data.adminPhone || '');
  const adminUid = await assertAdmin(adminPhone, context);

  const requestId = String(data.requestId || '').trim();
  const reason = String(data.reason || '').trim();
  if (!requestId) {
    throw new functions.https.HttpsError('invalid-argument', 'requestId majburiy');
  }
  if (!reason) {
    throw new functions.https.HttpsError('invalid-argument', 'Sabab majburiy');
  }
  if (reason.length > 500) {
    throw new functions.https.HttpsError('invalid-argument', 'Sabab juda uzun');
  }

  const reqRef = db.collection('driver_requests').doc(requestId);
  const reqSnap = await reqRef.get();
  if (!reqSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Ariza topilmadi');
  }

  const req = reqSnap.data() || {};
  if (String(req.status || '') !== 'approved') {
    throw new functions.https.HttpsError('failed-precondition', 'Ariza tasdiqlangan emas');
  }

  let userPhone = digits(req.phone || '');
  if (userPhone.length < 9) {
    userPhone = digits(requestId);
  }
  if (userPhone.length < 9) {
    throw new functions.https.HttpsError('failed-precondition', 'Telefon raqami topilmadi');
  }

  const taxiType = normalizeDriverTaxiType(req.taxiType);
  const phoneRaw = String(req.phone || userPhone).trim();

  const driverRef = db.collection('drivers').doc(userPhone);
  const driverSnap = await driverRef.get();
  if (driverSnap.exists) {
    const d = driverSnap.data() || {};
    if (taxiType === 'intercity') {
      const icSnap = await db.collection('intercity_drivers').doc(userPhone).get();
      if (icSnap.exists && icSnap.data().isActive === true) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Haydovchi hozir faol — avval faolsizlantiring',
        );
      }
    } else if (taxiType !== 'marshrut' && d.isOnline === true) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Haydovchi hozir online — avval offline qiling',
      );
    }
  }

  let remainingTypes = [];
  if (driverSnap.exists) {
    const d = driverSnap.data() || {};
    let taxiTypes = Array.isArray(d.taxiTypes) ? d.taxiTypes.map(normalizeDriverTaxiType) : [];
    if (taxiTypes.length === 0 && d.taxiType) {
      taxiTypes = [normalizeDriverTaxiType(d.taxiType)];
    }
    remainingTypes = taxiTypes.filter((t) => t !== taxiType);
  }

  const batch = db.batch();
  const now = admin.firestore.FieldValue.serverTimestamp();

  batch.update(reqRef, {
    status: 'revoked',
    revokedAt: now,
    revokedBy: adminUid,
    revokedReason: reason,
    updatedAt: now,
  });

  if (driverSnap.exists) {
    const driverUpdate = {
      taxiTypes: admin.firestore.FieldValue.arrayRemove(taxiType),
      updatedAt: now,
    };
    if (remainingTypes.length === 0) {
      driverUpdate.approved = false;
      driverUpdate.approvalStatus = 'revoked';
      driverUpdate.isOnline = false;
      driverUpdate.isBusy = false;
      driverUpdate.isAvailable = false;
    } else {
      driverUpdate.taxiType = remainingTypes[0];
    }
    batch.set(driverRef, driverUpdate, { merge: true });
  }

  if (taxiType === 'intercity') {
    batch.set(
      db.collection('intercity_drivers').doc(userPhone),
      {
        isActive: false,
        isOnPanel: false,
        updatedAt: now,
      },
      { merge: true },
    );
  }

  if (taxiType === 'marshrut') {
    await removeDriverFromMarshrutRoute(userPhone, batch, now, reason);
  } else {
    batch.set(
      db.collection('queue').doc(userPhone),
      {
        isActive: false,
        updatedAt: now,
      },
      { merge: true },
    );

    const schedSnap = await db
      .collection('schedules')
      .where('driverId', '==', userPhone)
      .where('taxiType', '==', taxiType)
      .where('isActive', '==', true)
      .get();
    for (const doc of schedSnap.docs) {
      batch.update(doc.ref, { isActive: false, updatedAt: now });
    }
  }

  const userRef = db.collection('users').doc(userPhone);
  const userSnap = await userRef.get();
  if (userSnap.exists && remainingTypes.length === 0) {
    const role = String((userSnap.data() || {}).role || 'user');
    if (role === 'driver') {
      batch.set(
        userRef,
        { role: 'user', updatedAt: now },
        { merge: true },
      );
    }
  }

  batch.set(db.collection('notifications').doc(), {
    targetPhone: userPhone,
    title: '⚠️ Ҳайдовчи tasdiqligi bekor qilindi',
    body: `${driverTaxiTypeLabel(taxiType)}: ${reason}`,
    sent: false,
    type: 'driver_request_revoked',
    taxiType,
    requestId,
    createdAt: now,
  });

  await batch.commit();
  return { ok: true, uid: userPhone, taxiType, remainingTypes };
});

/** Foydalanuvchi: haydovchi rejimidan yo'lovchiga qaytish (tasdiq saqlanadi). */
exports.leaveDriverRole = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated', 'Auth required');
  }

  const uid = digits(String(data.userPhone || ''));
  if (uid.length < 9) {
    throw new functions.https.HttpsError('invalid-argument', 'userPhone');
  }

  const clientHandledCleanup = data.clientHandledCleanup === true;

  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = db.batch();

  if (!clientHandledCleanup) {
    // 1. Faol safarlarni bekor qilish (eski APK / fallback — o'rin qaytarish yo'q)
    const activeTrips = await db.collection('trips')
      .where('acceptedDriverId', '==', uid)
      .where('status', '==', 'accepted')
      .where('taxiType', '==', 'marshrut')
      .get();

    for (const trip of activeTrips.docs) {
      batch.update(trip.ref, {
        status: 'cancelled',
        cancelledBy: 'system',
        cancelReason: 'driver_left_mode',
        cancelledAt: now,
      });
    }

    // 2. Faol reyslarni deaktivatsiya
    const activeSched = await db.collection('schedules')
      .where('driverId', '==', uid)
      .where('isActive', '==', true)
      .where('taxiType', '==', 'marshrut')
      .get();

    for (const sched of activeSched.docs) {
      batch.update(sched.ref, {
        isActive: false,
        updatedAt: now,
      });
    }
  }

  // 3. Haydovchini offline
  batch.set(
    db.collection('drivers').doc(uid),
    {
      isOnline: false,
      isBusy: false,
      isAvailable: false,
      updatedAt: now,
    },
    { merge: true },
  );

  // 4. Navbatdan chiqarish
  batch.set(
    db.collection('queue').doc(uid),
    { isActive: false, updatedAt: now },
    { merge: true },
  );

  // 5. Rolni o'zgartirish
  batch.set(
    db.collection('users').doc(uid),
    { role: 'user', updatedAt: now },
    { merge: true },
  );

  batch.set(
    db.collection('intercity_drivers').doc(uid),
    { isActive: false, isOnPanel: false, updatedAt: now },
    { merge: true },
  );

  await batch.commit();

  return { success: true, message: 'Driver mode left successfully' };
});

async function batchDeleteDocs(docs, stats, key) {
  if (!docs.length) return;
  let batch = db.batch();
  let writes = 0;
  for (const doc of docs) {
    batch.delete(doc.ref);
    writes += 1;
    stats[key] = (stats[key] || 0) + 1;
    if (writes >= 450) {
      await batch.commit();
      batch = db.batch();
      writes = 0;
    }
  }
  if (writes > 0) await batch.commit();
}

async function wipeCollection(colName, stats, key) {
  let total = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await db.collection(colName).limit(400).get();
    if (snap.empty) break;
    await batchDeleteDocs(snap.docs, stats, key);
    total += snap.size;
    if (snap.size < 400) break;
  }
  return total;
}

/** Admin: marshrut/mahalliy/shaharlararo haydovchi bazasini tozalash — yangi ro'yxatdan o'tish. */
exports.adminResetTaxiDriversRegistry = functions.https.onCall(async (data, context) => {
  const adminPhone = String(data.adminPhone || '');
  await assertAdmin(adminPhone, context);

  const confirmText = String(data.confirmText || '').trim();
  if (confirmText !== 'RESET_TAXI_DRIVERS') {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'confirmText must be RESET_TAXI_DRIVERS',
    );
  }

  const stats = {};
  const now = admin.firestore.FieldValue.serverTimestamp();

  stats.queueDeleted = await wipeCollection('queue', stats, 'queueDeleted');
  stats.intercityDriversDeleted = await wipeCollection(
    'intercity_drivers',
    stats,
    'intercityDriversDeleted',
  );

  const schedSnap = await db
    .collection('schedules')
    .where('taxiType', 'in', ['marshrut', 'intercity', 'local'])
    .get();
  let batch = db.batch();
  let writes = 0;
  for (const doc of schedSnap.docs) {
    batch.delete(doc.ref);
    writes += 1;
    stats.schedulesDeleted = (stats.schedulesDeleted || 0) + 1;
    if (writes >= 450) {
      await batch.commit();
      batch = db.batch();
      writes = 0;
    }
  }
  if (writes > 0) await batch.commit();

  const reqSnap = await db.collection('driver_requests').get();
  writes = 0;
  batch = db.batch();
  for (const doc of reqSnap.docs) {
    const t = normalizeDriverTaxiType((doc.data() || {}).taxiType);
    if (t !== 'marshrut' && t !== 'intercity' && t !== 'local') continue;
    batch.delete(doc.ref);
    writes += 1;
    stats.driverRequestsDeleted = (stats.driverRequestsDeleted || 0) + 1;
    if (writes >= 450) {
      await batch.commit();
      batch = db.batch();
      writes = 0;
    }
  }
  if (writes > 0) await batch.commit();

  const driversSnap = await db.collection('drivers').get();
  writes = 0;
  batch = db.batch();
  for (const doc of driversSnap.docs) {
    const d = doc.data() || {};
    let types = Array.isArray(d.taxiTypes)
      ? d.taxiTypes.map(normalizeDriverTaxiType)
      : [];
    if (types.length === 0 && d.taxiType) {
      types = [normalizeDriverTaxiType(d.taxiType)];
    }
    const hasTaxi = types.some((t) => ['marshrut', 'intercity', 'local'].includes(t));
    if (!hasTaxi && !d.taxiType) continue;

    batch.set(
      doc.ref,
      {
        approved: false,
        approvalStatus: 'reset',
        isOnline: false,
        isBusy: false,
        isAvailable: false,
        taxiTypes: [],
        removedFromRegistryAt: now,
        updatedAt: now,
      },
      { merge: true },
    );
    writes += 1;
    stats.driversReset = (stats.driversReset || 0) + 1;

    batch.delete(
      db.collection('users').doc(doc.id).collection('driverProfiles').doc('marshrut'),
    );
    batch.delete(
      db.collection('users').doc(doc.id).collection('marshrut_state').doc('active'),
    );
    batch.set(
      db.collection('users').doc(doc.id),
      { role: 'user', updatedAt: now },
      { merge: true },
    );
    writes += 3;
    stats.usersRoleReset = (stats.usersRoleReset || 0) + 1;

    if (writes >= 400) {
      await batch.commit();
      batch = db.batch();
      writes = 0;
    }
  }
  if (writes > 0) await batch.commit();

  return { ok: true, stats };
});

/** Mobil/web: PIN bilan `users/{phone}.role = admin` — eski usul (mobil profildan olib tashlandi). */
exports.promoteToAdminWithPin = functions.https.onCall(async (data, context) => {
  throw new functions.https.HttpsError(
    'failed-precondition',
    'Mobil PIN o\'chirilgan. Admin web → Foydalanuvchilar bo\'limidan rol bering.',
  );
});

/**
 * Qo'llab-quvvatlash: telefonga admin rol (faqat ADMIN_BOOTSTRAP_SECRET bilan).
 * Firebase: `firebase functions:secrets:set ADMIN_BOOTSTRAP_SECRET`
 */
exports.bootstrapAdminUser = functions
  .runWith({ secrets: ['ADMIN_BOOTSTRAP_SECRET'] })
  .https.onCall(async (data) => {
    const expected = process.env.ADMIN_BOOTSTRAP_SECRET;
    if (!expected || String(data.secret || '') !== expected) {
      throw new functions.https.HttpsError('permission-denied', 'Maxfiy kalit xato');
    }
    const uid = canonicalUid(data.phone || data.rawPhone || '');
    if (uid.length < 9) {
      throw new functions.https.HttpsError('invalid-argument', 'Telefon noto\'g\'ri');
    }
    const ref = db.collection('users').doc(uid);
    const snap = await ref.get();
    const phoneRaw = String(data.phone || `+${uid}`).trim();
    await ref.set(
      {
        role: 'admin',
        phone: snap.exists ? String((snap.data() || {}).phone || phoneRaw) : phoneRaw,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        roleUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        roleUpdatedBy: 'bootstrap',
      },
      { merge: true },
    );
    return { ok: true, uid, role: 'admin' };
  });

/** Operator chat javobi — admin role + Admin SDK (client Firestore rules bypass). */
exports.sendSupportChatReply = functions.https.onCall(async (data, context) => {
  const adminPhone = String(data.adminPhone || '').trim();
  await assertAdmin(adminPhone, context);
  const chatId = digits(data.chatId || '');
  const text = String(data.text || '').trim();
  if (chatId.length < 9 || !text) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'chatId ва матн мажбурий',
    );
  }
  if (text.length > 4000) {
    throw new functions.https.HttpsError('invalid-argument', 'Матн узун');
  }
  await appendSystemSupportChatMessage(chatId, text);
  return { ok: true };
});

/** Callable: support чатига админ хабари (Admin SDK — fromAdmin: true, systemOrder). */
exports.appendAdminSystemChat = functions.https.onCall(async (data, context) => {
  const adminPhone = String(data.adminPhone || '');
  await assertAdmin(adminPhone, context);

  const chatId = String(data.chatId || '').replace(/\D/g, '');
  const text = String(data.text || '').trim();
  if (!chatId || chatId.length < 9 || !text) {
    throw new functions.https.HttpsError('invalid-argument', 'chatId va text majburiy');
  }

  await appendSystemSupportChatMessage(chatId, text);
  return { ok: true };
});

// ════════════════════════════════════════════════════════════════
// ҲАР КУНИ СОАТ 20:00 (Asia/Tashkent) — DAILY REPORT
// ════════════════════════════════════════════════════════════════

function _todayKey(now) {
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, '0');
  const d = String(now.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function _startOfDay(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
}

function _bucketCount(map, key) {
  map[key] = (map[key] || 0) + 1;
}

async function _buildDailyReport(now) {
  const today0 = _startOfDay(now);
  const tomorrow = new Date(today0.getTime() + 24 * 3600 * 1000);
  const week0 = new Date(today0.getTime() - 7 * 24 * 3600 * 1000);
  const month0 = new Date(today0.getTime() - 30 * 24 * 3600 * 1000);

  const [
    usersAgg, newUsersAgg, activeUsersAgg, blockedAgg,
    driversSnap, ordersTodaySnap, tripsTodaySnap,
    ordersMonthSnap, tripsMonthSnap, payoutsSnap,
  ] = await Promise.all([
    db.collection('users').count().get(),
    db.collection('users')
      .where('createdAt', '>=', today0).count().get(),
    db.collection('users')
      .where('lastActiveAt', '>=', today0).count().get(),
    db.collection('users')
      .where('blockedUntil', '>', now).count().get(),
    db.collection('drivers').get(),
    db.collection('orders')
      .where('createdAt', '>=', today0).get(),
    db.collection('trips')
      .where('createdAt', '>=', today0).get(),
    db.collection('orders')
      .where('createdAt', '>=', month0).get(),
    db.collection('trips')
      .where('createdAt', '>=', month0)
      .where('status', '==', 'completed').get(),
    db.collection('payout_requests')
      .where('status', '==', 'pending').get(),
  ]);

  // Drivers
  let onlineDrivers = 0;
  const activeDriversToday = new Set();
  for (const doc of driversSnap.docs) {
    if (doc.data().isOnline === true) onlineDrivers++;
  }

  // Orders bugun
  const ordersByStatus = {};
  const ordersByType = {};
  const rejectReasons = {};
  const productCounts = {};
  let todayOrdersRevenue = 0;
  let todayCashChange = 0;
  let sumOrderValue = 0;
  let countOrders = 0;
  const hourlyHeat = new Array(24).fill(0);
  for (const doc of ordersTodaySnap.docs) {
    const d = doc.data();
    const status = d.status || 'new';
    const type = d.type || 'bread';
    _bucketCount(ordersByStatus, status);
    _bucketCount(ordersByType, type);
    if (status === 'rejected') {
      _bucketCount(rejectReasons, d.rejectReason || 'Кўрсатилмаган');
    }
    const total = Number(d.total || 0);
    const cashPaid = Number(d.cashPaid || 0);
    if (status !== 'rejected' && status !== 'cancelled') {
      todayOrdersRevenue += total;
      sumOrderValue += total;
      countOrders++;
    }
    if (cashPaid > total) todayCashChange += (cashPaid - total);
    const created = d.createdAt ? d.createdAt.toDate() : null;
    if (created) hourlyHeat[created.getHours()]++;
    if (Array.isArray(d.items)) {
      for (const it of d.items) {
        if (it && it.name) {
          const q = Number(it.count || 1);
          productCounts[it.name] = (productCounts[it.name] || 0) + q;
        }
      }
    }
  }

  // Trips bugun
  const tripsByStatus = {};
  const tripsByTaxiType = {};
  const routeCounts = {};
  let todayTripsRevenue = 0;
  let sumTripValue = 0;
  let countTrips = 0;
  const driverTripCounts = {};
  for (const doc of tripsTodaySnap.docs) {
    const d = doc.data();
    const status = d.status || 'searching';
    const type = d.taxiType || 'alone';
    _bucketCount(tripsByStatus, status);
    _bucketCount(tripsByTaxiType, type);
    const fare = Number(d.fare || 0);
    const cashPaid = Number(d.cashPaid || 0);
    if (status === 'completed') {
      todayTripsRevenue += fare;
      sumTripValue += fare;
      countTrips++;
      const did = d.acceptedDriverId || '';
      if (did) {
        driverTripCounts[did] = (driverTripCounts[did] || 0) + 1;
        activeDriversToday.add(did);
      }
    }
    if (cashPaid > fare) todayCashChange += (cashPaid - fare);
    const created = d.createdAt ? d.createdAt.toDate() : null;
    if (created) hourlyHeat[created.getHours()]++;
    const from = d.from || d.fromAddr || d.pickupMfy || '';
    const to = d.to || d.toAddr || d.dropoffMfy || '';
    if (from && to) {
      const route = `${from} → ${to}`;
      routeCounts[route] = (routeCounts[route] || 0) + 1;
    }
  }

  // Ой давомида тушум
  let monthRevenue = 0;
  let weekRevenue = 0;
  const byModule = {};
  for (const doc of ordersMonthSnap.docs) {
    const d = doc.data();
    const status = d.status || 'new';
    if (status === 'rejected' || status === 'cancelled') continue;
    const total = Number(d.total || 0);
    const created = d.createdAt ? d.createdAt.toDate() : null;
    if (!created) continue;
    monthRevenue += total;
    if (created >= week0) weekRevenue += total;
    const m = `module_${d.type || 'bread'}`;
    byModule[m] = (byModule[m] || 0) + total;
  }
  for (const doc of tripsMonthSnap.docs) {
    const d = doc.data();
    const fare = Number(d.fare || 0);
    const completed = d.completedAt ? d.completedAt.toDate() : null;
    if (!completed) continue;
    monthRevenue += fare;
    if (completed >= week0) weekRevenue += fare;
    const m = `taxi_${d.taxiType || 'alone'}`;
    byModule[m] = (byModule[m] || 0) + fare;
  }

  // Peak hour
  let peakHour = 0;
  let peakHourValue = -1;
  for (let h = 0; h < 24; h++) {
    if (hourlyHeat[h] > peakHourValue) {
      peakHourValue = hourlyHeat[h];
      peakHour = h;
    }
  }

  // Bekor qilish %
  const totalCancellable =
    ordersTodaySnap.docs.length + tripsTodaySnap.docs.length;
  const cancelled =
    (ordersByStatus.rejected || 0) + (ordersByStatus.cancelled || 0) +
    (tripsByStatus.cancelled || 0);
  const cancellationRate =
    totalCancellable === 0 ? 0 : (cancelled / totalCancellable * 100);

  // Wallet balanslar
  const usersSnap = await db.collection('users').get();
  let totalWalletBalance = 0;
  for (const doc of usersSnap.docs) {
    const b = Number(doc.data().walletBalance || 0);
    if (b > 0) totalWalletBalance += b;
  }
  let pendingPayoutsAmount = 0;
  for (const doc of payoutsSnap.docs) {
    pendingPayoutsAmount += Number(doc.data().amount || 0);
  }

  // Top entries
  const topByCount = (map) =>
    Object.entries(map).sort((a, b) => b[1] - a[1]).slice(0, 5)
      .map(([k, v]) => ({ label: k, value: v }));

  // Driver names учун map
  const driverNames = {};
  for (const doc of driversSnap.docs) {
    driverNames[doc.id] = doc.data().name || '';
  }
  const topDrivers = Object.entries(driverTripCounts)
    .sort((a, b) => b[1] - a[1]).slice(0, 5)
    .map(([k, v]) => ({ label: driverNames[k] || k, value: v }));

  const notes = [];
  if (cancellationRate > 20) {
    notes.push(`⚠️ Бекор қилиш % юқори: ${cancellationRate.toFixed(1)}%`);
  }
  if (payoutsSnap.docs.length > 0) {
    notes.push(`💰 ${payoutsSnap.docs.length} та кутаётган payout: ${pendingPayoutsAmount} сўм`);
  }
  if ((blockedAgg.data().count || 0) > 5) {
    notes.push(`🚫 ${blockedAgg.data().count} та фойдаланувчи блокда`);
  }

  return {
    dateKey: _todayKey(now),
    generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    totalUsers: usersAgg.data().count || 0,
    newUsersToday: newUsersAgg.data().count || 0,
    activeUsersToday: activeUsersAgg.data().count || 0,
    totalDrivers: driversSnap.docs.length,
    onlineDriversNow: onlineDrivers,
    activeDriversToday: activeDriversToday.size,
    todayOrdersTotal: ordersTodaySnap.docs.length,
    todayOrdersByStatus: ordersByStatus,
    todayOrdersByType: ordersByType,
    todayRejectReasons: rejectReasons,
    todayTripsTotal: tripsTodaySnap.docs.length,
    todayTripsByStatus: tripsByStatus,
    todayTripsByTaxiType: tripsByTaxiType,
    todayRevenue: todayOrdersRevenue + todayTripsRevenue,
    todayRevenueByModule: byModule,
    todayCashChange,
    weekRevenue,
    monthRevenue,
    peakHour,
    cancellationRate,
    avgOrderValue: countOrders === 0 ? 0 : sumOrderValue / countOrders,
    avgTripValue: countTrips === 0 ? 0 : sumTripValue / countTrips,
    totalWalletBalance,
    pendingPayouts: payoutsSnap.docs.length,
    pendingPayoutsAmount,
    blockedUsers: blockedAgg.data().count || 0,
    topProducts: topByCount(productCounts),
    topRoutes: topByCount(routeCounts),
    topDrivers,
    notes,
  };
}

async function _notifyAdmins(report) {
  // Барча админларга FCM юбориш
  const adminsSnap = await db.collection('users')
    .where('role', '==', 'admin').get();
  const tokens = adminsSnap.docs
    .map(d => d.data().fcmToken)
    .filter(t => t && String(t).length > 0);

  if (tokens.length === 0) return;

  const title = '📊 Кундалик ҳисобот тайёр';
  const body = `${report.todayOrdersTotal} буюртма · ${report.todayTripsTotal} сафар · ${report.todayRevenue.toLocaleString()} сўм`;

  const messages = tokens.map(token => ({
    token,
    notification: { title, body },
    data: {
      type: 'daily_report',
      dateKey: String(report.dateKey),
    },
  }));

  try {
    await admin.messaging().sendEach(messages);
  } catch (e) {
    console.warn('Daily report notify failed:', e?.message);
  }
}

/// Ҳар куни Asia/Tashkent соат 20:00 да ишга тушади.
exports.dailyReport20 = functions.pubsub
  .schedule('0 20 * * *')
  .timeZone('Asia/Tashkent')
  .onRun(async () => {
    const now = new Date();
    const report = await _buildDailyReport(now);
    await db.collection('daily_reports').doc(report.dateKey).set(report);
    await _notifyAdmins(report);
    return null;
  });

/// Қўлда ишга тушириш — админдан callable.
exports.generateDailyReportNow = functions.https.onCall(async (data, context) => {
  const adminPhone = String(data.adminPhone || '');
  await assertAdmin(adminPhone, context);
  const now = new Date();
  const report = await _buildDailyReport(now);
  await db.collection('daily_reports').doc(report.dateKey).set(report);
  await _notifyAdmins(report);
  return { ok: true, dateKey: report.dateKey };
});

// ════════════════════════════════════════════════════════════════
// ҲАР КУНИ СОАТ 00:00 (Asia/Tashkent) — INVENTORY DAILY RESET
// ════════════════════════════════════════════════════════════════

async function _resetCollectionSoldToday(colName) {
  const col = db.collection(colName);
  const snap = await col.where('soldToday', '>', 0).get();
  if (snap.empty) return 0;
  let batch = db.batch();
  let count = 0;
  let writes = 0;
  for (const doc of snap.docs) {
    batch.update(doc.ref, { soldToday: 0 });
    writes++;
    count++;
    if (writes >= 450) {
      await batch.commit();
      batch = db.batch();
      writes = 0;
    }
  }
  if (writes > 0) await batch.commit();
  return count;
}

/// Ҳар кун ярим тунда soldToday нулга; ochiq unpaid buyurtma rezervini qayta qo‘yadi.
exports.resetDailySoldStock = functions.pubsub
  .schedule('0 0 * * *')
  .timeZone('Asia/Tashkent')
  .onRun(async () => {
    const reserved = await aggregateOpenOrderStockReservations();
    const [bread, extras, food, platform] = await Promise.all([
      _resetCollectionSoldToday('bread_products'),
      _resetCollectionSoldToday('extra_products'),
      _resetCollectionSoldToday('food_inventory'),
      _resetCollectionSoldToday('platform_products'),
    ]);
    const reapplied = await applyStockReservations(reserved);
    console.log(
      `Daily stock reset: bread=${bread}, extras=${extras}, food=${food}, platform=${platform}, reapplied=${reapplied}`);
    return null;
  });

/// Қўлда ишга тушириш — админдан callable (test/recovery учун).
exports.resetSoldStockNow = functions.https.onCall(async (data, context) => {
  const adminPhone = String(data.adminPhone || '');
  await assertAdmin(adminPhone, context);
  const reserved = await aggregateOpenOrderStockReservations();
  const [bread, extras, food, platform] = await Promise.all([
    _resetCollectionSoldToday('bread_products'),
    _resetCollectionSoldToday('extra_products'),
    _resetCollectionSoldToday('food_inventory'),
    _resetCollectionSoldToday('platform_products'),
  ]);
  const reapplied = await applyStockReservations(reserved);
  return {
    ok: true, bread, extras, food, platform, reapplied,
    reservedKeys: Object.keys(reserved).length,
  };
});

// ─── P1-2: Heartbeat crash cleanup (drivers + couriers) ───────────────────────
exports.cleanupStaleDrivers = functions.pubsub
  .schedule('every 2 minutes')
  .onRun(async () => {
    const cutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - 2 * 60 * 1000,
    );
    const [driversSnap, couriersSnap] = await Promise.all([
      db.collection('drivers')
        .where('isOnline', '==', true)
        .where('updatedAt', '<', cutoff)
        .get(),
      db.collection('couriers')
        .where('isOnline', '==', true)
        .where('updatedAt', '<', cutoff)
        .get(),
    ]);

    const allDocs = [...driversSnap.docs, ...couriersSnap.docs];
    if (allDocs.length === 0) return null;

    let batch = db.batch();
    let writes = 0;
    for (const doc of allDocs) {
      batch.update(doc.ref, {
        isOnline: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      writes++;
      if (doc.ref.parent.id === 'drivers') {
        const queueRef = db.collection('queue').doc(doc.id);
        batch.set(
          queueRef,
          {
            isActive: false,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        writes++;
      }
      if (writes >= 450) {
        await batch.commit();
        batch = db.batch();
        writes = 0;
      }
    }
    if (writes > 0) await batch.commit();
    console.log(
      `cleanupStaleDrivers: drivers=${driversSnap.size}, couriers=${couriersSnap.size}`,
    );
    return null;
  });

// ─── Intercity / umumiy notifications → server FCM (ilova o'chiq bo'lsa ham) ─
async function resolveFcmToken(targetPhone) {
  const d = digits(targetPhone);
  if (!d || d.length < 9) return '';
  const tryIds = [d];
  if (d.length === 9) tryIds.push('998' + d);
  if (d.startsWith('998') && d.length === 12) tryIds.push(d.slice(3));
  for (const uid of tryIds) {
    const userDoc = await db.collection('users').doc(uid).get();
    const t = userDoc.data()?.fcmToken;
    if (t) return t;
    const driverDoc = await db.collection('drivers').doc(uid).get();
    const dt = driverDoc.data()?.fcmToken;
    if (dt) return dt;
  }
  return '';
}

/** Йўловчига — `intercity_drivers.seats` ўзгарганда (барча актив бронлар). */
function buildIntercitySeatsChangeMessage(oldSeats, newSeats, seatCapacity, driverName) {
  const cap = seatCapacity > 0 ? seatCapacity : Math.max(oldSeats, newSeats);
  const name = driverName || 'Ҳайдовчи';
  if (newSeats > oldSeats) {
    const added = newSeats - oldSeats;
    return {
      title: '💺 Яна бўш ўрин пайдо бўлди',
      body: `${name}: рейсингизда яна ${added} та бўш ўрин (${newSeats}/${cap}). Дўстингизни таклиф қилинг!`,
      type: 'intercity_seats_update',
    };
  }
  if (newSeats <= 0) {
    return {
      title: '⏳ Рейс тўлди',
      body: `${name}: барча ўринлар банд. Ҳайдовчи билан боғланинг.`,
      type: 'intercity_seats_update',
    };
  }
  if (newSeats === 1) {
    return {
      title: '⏳ Рейс деярли тўлди',
      body: `${name}: фақат 1 та бўш ўрин қолди (1/${cap}).`,
      type: 'intercity_seats_update',
    };
  }
  return {
    title: '💺 Бўш ўрин янгиланди',
    body: `${name}: ҳозир ${newSeats}/${cap} бўш ўрин қолди.`,
    type: 'intercity_seats_update',
  };
}

async function updateDriverGenderStats(driverId) {
  try {
    const snap = await db.collection('intercity_bookings')
        .where('driverId', '==', driverId)
        .where('status', 'in', ['pending', 'confirmed'])
        .get();

    let maleCount   = 0;
    let femaleCount = 0;

    snap.docs.forEach(doc => {
      const d = doc.data();
      const count = d.passengers ?? 1;
      if (d.userGender === 'male')   maleCount   += count;
      if (d.userGender === 'female') femaleCount += count;
    });

    await db.collection('intercity_drivers')
        .doc(driverId)
        .update({
          maleCount,
          femaleCount,
          genderUpdatedAt:
              admin.firestore.FieldValue.serverTimestamp(),
        });
  } catch (e) {
    console.error('updateDriverGenderStats error:', e);
  }
}

async function notifyIntercityPassengersSeatsChanged(driverId, oldSeats, newSeats, driverData) {
  if (oldSeats === newSeats) return;
  const driverName = String(driverData.name || 'Ҳайдовчи');
  const seatCapacity = Number(driverData.seatCapacity) || newSeats;
  const msg = buildIntercitySeatsChangeMessage(oldSeats, newSeats, seatCapacity, driverName);

  const bookingsSnap = await db.collection('intercity_bookings')
    .where('driverId', '==', driverId)
    .where('status', 'in', ['pending', 'confirmed'])
    .get();

  const notified = new Set();
  let batch = db.batch();
  let writes = 0;

  for (const doc of bookingsSnap.docs) {
    const b = doc.data();
    const phone = digits(b.userPhone || '');
    if (phone.length < 9 || notified.has(phone)) continue;
    notified.add(phone);

    const notifRef = db.collection('notifications').doc();
    batch.set(notifRef, {
      targetPhone: phone,
      title: msg.title,
      body: msg.body,
      sent: false,
      type: msg.type,
      bookingId: doc.id,
      driverId,
      seatsLeft: newSeats,
      seatCapacity,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    writes++;
    if (writes >= 450) {
      await batch.commit();
      batch = db.batch();
      writes = 0;
    }
  }
  if (writes > 0) await batch.commit();
}

exports.onIntercityDriverUpdate = functions.firestore
  .document('intercity_drivers/{driverId}')
  .onUpdate(async (change) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    const oldSeats = Number(before.seats);
    const newSeats = Number(after.seats);
    if (!Number.isFinite(oldSeats) || !Number.isFinite(newSeats)) return;
    if (oldSeats === newSeats) return;
    await notifyIntercityPassengersSeatsChanged(
      change.after.id,
      oldSeats,
      newSeats,
      after,
    );
  });

// createBooking — client transaction; gender stats sync on new booking
exports.onIntercityBookingCreated = functions.firestore
  .document('intercity_bookings/{bookingId}')
  .onCreate(async (snap) => {
    const driverId = snap.data()?.driverId;
    if (driverId) await updateDriverGenderStats(driverId);
    return null;
  });

// cancelBooking / acceptBooking — status → cancelled or pending → confirmed
exports.onIntercityBookingUpdated = functions.firestore
  .document('intercity_bookings/{bookingId}')
  .onUpdate(async (change) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    const beforeStatus = String(before.status || '');
    const afterStatus = String(after.status || '');
    const driverId = after.driverId || before.driverId;
    if (!driverId) return null;

    const statusChanged = beforeStatus !== afterStatus;
    const profileChanged =
      before.userGender !== after.userGender ||
      before.passengers !== after.passengers;

    if (statusChanged || profileChanged) {
      await updateDriverGenderStats(driverId);
    }
    return null;
  });

exports.onIntercityBookingCancelled = functions.firestore
    .document('intercity_bookings/{bookingId}')
    .onUpdate(async (change, context) => {
      const before = change.before.data() || {};
      const after = change.after.data() || {};

      if (after.status !== 'cancelled') return null;
      if (before.status === 'cancelled') return null;

      const userPhone = after.userPhone ?? '';

      try {
        // Seat restore handled by client transaction.
        // CF only cleans up passenger lock (admin SDK).
        const userKey = userPhone.replace(/\D/g, '');
        if (userKey) {
          const lockRef = db
              .collection('intercity_passenger_locks')
              .doc(userKey);
          const lock = await lockRef.get();
          if (lock.exists &&
              lock.data()?.bookingId === context.params.bookingId) {
            await lockRef.delete();
          }
        }

        console.log(
            `onIntercityBookingCancelled: cleaned lock for booking ` +
            `${context.params.bookingId}`,
        );
      } catch (e) {
        console.error('onIntercityBookingCancelled error:', e);
      }
      return null;
    });

exports.updateIntercityDriverRating = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
        'unauthenticated', 'Auth required');
  }
  const {driverId, rating, bookingId} = data;
  if (!driverId || !rating ||
      rating < 1 || rating > 5) {
    throw new functions.https.HttpsError(
        'invalid-argument', 'Invalid rating');
  }

  const bookingSnap = await db.collection('intercity_bookings')
      .doc(bookingId).get();
  if (!bookingSnap.exists) {
    throw new functions.https.HttpsError(
        'not-found', 'Booking not found');
  }
  if (bookingSnap.data()?.passengerRating) {
    return {ok: true, skipped: true};
  }

  const driverRef = db.collection('intercity_drivers')
      .doc(driverId);
  const bookingRef = db.collection('intercity_bookings')
      .doc(bookingId);

  await db.runTransaction(async (t) => {
    const snap = await t.get(driverRef);
    if (!snap.exists) return;
    const d = snap.data();
    const totalRatings = (d.totalRatings ?? 0) + 1;
    const ratingSum = (d.ratingSum ?? 0) + rating;
    const avgRating =
        Math.round((ratingSum / totalRatings) * 10) / 10;

    t.update(driverRef, {
      totalRatings,
      ratingSum,
      avgRating,
      updatedAt: admin.firestore.FieldValue
          .serverTimestamp(),
    });
    t.update(bookingRef, {
      passengerRating: rating,
      ratedAt: admin.firestore.FieldValue
          .serverTimestamp(),
    });
  });
  return {ok: true};
});

exports.onIntercityPickupUpdated = functions.firestore
  .document('intercity_bookings/{bookingId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    const hadGps = before.pickupLat != null &&
        before.pickupLng != null;
    const hasGps = after.pickupLat != null &&
        after.pickupLng != null;

    if (hadGps || !hasGps) return null;

    const driverPhone = after.driverId ?? '';
    const userName = after.userName ?? 'Йўловчи';
    const pickup = after.pickupAddress ?? '';

    if (!driverPhone) return null;

    try {
      await db.collection('notifications').add({
        targetPhone: driverPhone,
        title: '📍 Йўловчи манзил юборди',
        body: `${userName}: ${pickup || 'GPS координата'}`,
        type: 'intercity_passenger_gps',
        bookingId: context.params.bookingId,
        sent: false,
        priority: 'high',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(
        `onIntercityPickupUpdated: notified ${driverPhone}`,
      );
    } catch (e) {
      console.error('onIntercityPickupUpdated error:', e);
    }
    return null;
  });

/** Тасдиқланган бронлар — жўнашдан ~30 дақ олдин эслатма (бир марта). */
async function sendIntercityDepartureReminders() {
  const nowMs = Date.now();
  const windowStart = admin.firestore.Timestamp.fromMillis(nowMs + 25 * 60000);
  const windowEnd = admin.firestore.Timestamp.fromMillis(nowMs + 40 * 60000);

  let snap;
  try {
    snap = await db.collection('intercity_bookings')
      .where('status', '==', 'confirmed')
      .where('departureTime', '>=', windowStart)
      .where('departureTime', '<=', windowEnd)
      .get();
  } catch (e) {
    console.error('intercityDepartureReminders query:', e.message || e);
    return;
  }

  let batch = db.batch();
  let writes = 0;

  for (const doc of snap.docs) {
    const b = doc.data();
    if (b.departureReminderSent === true) continue;
    const phone = digits(b.userPhone || '');
    if (phone.length < 9) continue;

    const dep = b.departureTime && b.departureTime.toDate
      ? b.departureTime.toDate()
      : new Date();
    const depText = `${String(dep.getHours()).padStart(2, '0')}:${String(dep.getMinutes()).padStart(2, '0')}`;
    const driverName = b.driverName || 'Ҳайдовчи';
    const route = [b.fromCity, b.toCity].filter(Boolean).join(' → ') || 'Шаҳарлараро';

    const notifRef = db.collection('notifications').doc();
    batch.set(notifRef, {
      targetPhone: phone,
      title: '🚗 Жўнаш вақти яқин',
      body: `${driverName} · ${route} · соат ${depText} да жўнаш. Тайёрланинг!`,
      sent: false,
      type: 'intercity_departure_reminder',
      bookingId: doc.id,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    batch.update(doc.ref, { departureReminderSent: true });
    writes += 2;
    if (writes >= 450) {
      await batch.commit();
      batch = db.batch();
      writes = 0;
    }
  }
  if (writes > 0) await batch.commit();
}

function adminNewsFcmPayload(d) {
  const title = String(d.title || '').trim();
  const body = String(d.body || '').trim();
  if (!title) return null;
  const category = String(d.category || 'info');
  const tab = category === 'order' ? 'orders' : 'general';
  const dataType = category === 'order' ? 'order' : 'general';
  return {
    title: title.startsWith('📢') ? title : `📢 ${title}`,
    body: body.slice(0, 120) || title,
    data: { type: dataType, screen: 'news', tab },
  };
}

/** Аудитория бўйича FCM tokenlar (битта token — битта user). */
async function collectFcmTokensForAudience(audience) {
  const aud = String(audience || 'all');
  const tokens = new Set();
  let query = db.collection('users');
  if (aud === 'driver') {
    query = query.where('role', '==', 'driver');
  } else if (aud === 'courier') {
    query = query.where('role', '==', 'courier');
  } else if (aud === 'user') {
    query = query.where('role', '==', 'user');
  }

  let lastDoc = null;
  const pageSize = 400;
  for (;;) {
    let q = query.orderBy(admin.firestore.FieldPath.documentId()).limit(pageSize);
    if (lastDoc) q = q.startAfter(lastDoc);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      const data = doc.data() || {};
      const t = data.fcmToken;
      if (typeof t !== 'string' || t.length < 10) continue;
      if (aud === 'user') {
        const role = String(data.role || 'user');
        if (role !== 'user') continue;
      }
      tokens.add(t);
    }
    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.size < pageSize) break;
  }
  return [...tokens];
}

async function sendFcmBroadcast(tokens, payload) {
  if (!tokens.length || !payload) return 0;
  const chunkSize = 500;
  let sent = 0;
  for (let i = 0; i < tokens.length; i += chunkSize) {
    const chunk = tokens.slice(i, i + chunkSize);
    const messages = chunk.map((token) => ({
      token,
      notification: { title: payload.title, body: payload.body },
      data: payload.data,
      android: { priority: 'high' },
    }));
    try {
      const resp = await admin.messaging().sendEach(messages);
      sent += resp.successCount || 0;
    } catch (e) {
      console.error('sendFcmBroadcast batch error:', e.message || e);
    }
  }
  return sent;
}

const ADMIN_NEWS_SKIP_PUSH_SOURCES = new Set([
  'order_status',
  'order_placed',
  'ad_moderation',
  'sell_offer',
  'identity_request',
  'system',
]);

/** Админ promo хабарлари учун FCM (create ёки pushResendAt). */
async function deliverAdminNewsPush(docRef, d) {
  const source = String(d.source || '').trim();
  if (source && ADMIN_NEWS_SKIP_PUSH_SOURCES.has(source)) {
    return { skipped: true, reason: 'skip_source', sent: 0 };
  }

  const payload = adminNewsFcmPayload(d);
  if (!payload) return { skipped: true, reason: 'no_title', sent: 0 };

  const uid = digits(d.targetUserId || '');
  if (uid.length >= 9) {
    const userDoc = await db.collection('users').doc(uid).get();
    const token = userDoc.data()?.fcmToken;
    if (!token) {
      return { skipped: true, reason: 'no_token', sent: 0 };
    }
    try {
      await admin.messaging().send({
        token,
        notification: { title: payload.title, body: payload.body },
        data: payload.data,
        android: { priority: 'high' },
      });
      await docRef.set(
        {
          pushBroadcastAt: admin.firestore.FieldValue.serverTimestamp(),
          pushSentCount: 1,
        },
        { merge: true },
      );
      return { skipped: false, sent: 1 };
    } catch (e) {
      console.error('deliverAdminNewsPush personal FCM:', e.message || e);
      return { skipped: false, sent: 0, error: e.message || String(e) };
    }
  }

  const audience = String(d.audience || 'all');
  const tokens = await collectFcmTokensForAudience(audience);
  if (tokens.length === 0) {
    console.log(`deliverAdminNewsPush broadcast: audience=${audience}, tokens=0`);
    return { skipped: false, sent: 0, tokens: 0 };
  }
  const sent = await sendFcmBroadcast(tokens, payload);
  console.log(`deliverAdminNewsPush broadcast: audience=${audience}, tokens=${tokens.length}, sent=${sent}`);
  try {
    await docRef.set(
      {
        pushBroadcastAt: admin.firestore.FieldValue.serverTimestamp(),
        pushSentCount: sent,
      },
      { merge: true },
    );
  } catch (e) {
    console.error('deliverAdminNewsPush pushBroadcastAt patch:', e.message || e);
  }
  return { skipped: false, sent, tokens: tokens.length };
}

// Админ қўлда ёзган хабар — FCM (notifyUserInApp / буюртма триггерлари алohida).
exports.onAdminNewsCreate = functions
  .runWith({ timeoutSeconds: 300, memory: '512MB' })
  .firestore
  .document('admin_news/{newsId}')
  .onCreate(async (snap) => {
    const d = snap.data() || {};
    await Promise.all([
      deliverAdminNewsPush(snap.ref, d),
      bumpHomeNewsBadge(d).catch((err) => {
        console.error('bumpHomeNewsBadge:', err.message || err);
      }),
    ]);
    return null;
  });

/** Админ «Push qayta yuborish» — pushResendAt ўзгарса қайта FCM. */
exports.onAdminNewsUpdate = functions
  .runWith({ timeoutSeconds: 300, memory: '512MB' })
  .firestore
  .document('admin_news/{newsId}')
  .onUpdate(async (change) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    const beforeMs = before.pushResendAt && before.pushResendAt.toMillis
      ? before.pushResendAt.toMillis()
      : 0;
    const afterMs = after.pushResendAt && after.pushResendAt.toMillis
      ? after.pushResendAt.toMillis()
      : 0;
    if (!afterMs || afterMs === beforeMs) return null;
    await deliverAdminNewsPush(change.after.ref, after);
    return null;
  });

exports.onNotificationCreate = functions.firestore
  .document('notifications/{notificationId}')
  .onCreate(async (snap) => {
    const data = snap.data() || {};
    if (data.sent === true) return;

    const title = String(data.title || 'Хабар');
    const body = String(data.body || '');
    const type = String(data.type || 'general');
    const bookingId = String(data.bookingId || '');
    const target = data.targetPhone || '';

    const token = await resolveFcmToken(target);
    const driverAlarmTypes = new Set([
      'intercity_booking_pending',
      'intercity_booking',
    ]);
    const passengerIntercityTypes = new Set([
      'intercity_pickup_request',
      'intercity_seats_update',
      'intercity_departure_reminder',
      'intercity_trip_completed',
      'intercity_booking_cancelled',
    ]);

    if (token) {
      let screen = String(data.screen || '');
      if (!screen) {
        if (passengerIntercityTypes.has(type)) {
          screen = 'intercity';
        } else if (type === 'trip_accepted') {
          screen = 'marshrut';
        }
      }
      const fcmData = { type, bookingId, screen };
      if (type === 'order' || type.startsWith('order_')) {
        fcmData.tab = 'orders';
      }
      const message = {
        token,
        notification: { title, body },
        data: fcmData,
        android: { priority: 'high' },
      };
      if (driverAlarmTypes.has(type)) {
        message.android = {
          priority: 'high',
          notification: {
            channelId: 'intercity_driver_alarm',
            sound: 'incoming_ring',
            priority: 'max',
            defaultSound: true,
          },
        };
      } else if (passengerIntercityTypes.has(type)) {
        message.android = {
          priority: 'high',
          notification: {
            channelId: 'taxi_channel',
            priority: 'high',
          },
        };
      }
      try {
        await admin.messaging().send(message);
      } catch (e) {
        console.error('onNotificationCreate FCM xato:', e.message || e);
      }
    }

    try {
      await snap.ref.update({ sent: true });
    } catch (e) {
      console.error('onNotificationCreate sent patch:', e.message || e);
    }
  });

function normalizeTimeoutAutoPauseStreak(raw) {
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 1) return 5;
  if (value > 20) return 20;
  return Math.floor(value);
}

async function getMarshrutTimeoutAutoPauseStreak() {
  const snap = await db.collection('settings').doc('app').get();
  return normalizeTimeoutAutoPauseStreak(snap.data()?.marshrutTimeoutAutoPauseStreak);
}

async function logMarshrutDispatchEvent({ tripId, type, data, driverIdOverride }) {
  const d = data || {};
  await db.collection('marshrut_dispatch_events').add({
    tripId,
    type,
    dispatchMode: d.dispatchMode || 'queue',
    dispatchSessionId: d.dispatchSessionId || '',
    dispatchAttempt: d.dispatchAttempt || 1,
    dispatchTotal: d.dispatchTotal || 1,
    userPhone: d.userPhone || '',
    pickupMfy: d.pickupMfy || '',
    dropoffMfy: d.dropoffMfy || '',
    driverId: driverIdOverride || d.targetDriverId || '',
    driverName: d.driverName || '',
    driverPhone: d.driverPhone || '',
    scheduleId: d.scheduleId || '',
    offerTimeoutSeconds: d.offerTimeoutSeconds || 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function clearMarshrutActiveIfMatches({ userPhone, tripId, status }) {
  const phone = digits(userPhone);
  if (phone.length < 9 || !tripId) return;
  const ref = db.collection('users').doc(phone).collection('marshrut_state').doc('active');
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    if ((snap.data()?.tripId || '') !== tripId) return;
    tx.set(ref, {
      status: status || 'cleared',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

async function applyMarshrutTimeoutPolicy(data) {
  const d = data || {};
  const driverId = d.targetDriverId || '';
  if (!driverId) return;

  const timeoutAutoPauseStreak = await getMarshrutTimeoutAutoPauseStreak();
  const queueRef = db.collection('queue').doc(driverId);
  let disabled = false;
  let streakAfter = 0;

  await db.runTransaction(async (tx) => {
    const queueDoc = await tx.get(queueRef);
    if (!queueDoc.exists) return;
    const streak = Number(queueDoc.data()?.dispatchTimeoutStreak || 0);
    streakAfter = streak + 1;
    const patch = {
      dispatchTimeoutStreak: streakAfter,
      dispatchTimeoutCount: admin.firestore.FieldValue.increment(1),
      todayTimeouts: admin.firestore.FieldValue.increment(1),
      lastTimeoutAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (streakAfter >= timeoutAutoPauseStreak) {
      disabled = true;
      patch.isActive = false;
      patch.autoPausedReason = 'dispatch_timeout_streak';
      patch.autoPausedAt = admin.firestore.FieldValue.serverTimestamp();
    }
    tx.set(queueRef, patch, { merge: true });
  });

  const scheduleId = d.scheduleId || '';
  if (scheduleId) {
    await db.collection('schedules').doc(scheduleId).set({
      todayTimeouts: admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }
  await db.collection('drivers').doc(driverId).set({
    todayTimeouts: admin.firestore.FieldValue.increment(1),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  if (disabled) {
    await db.collection('marshrut_dispatch_events').add({
      tripId: d.tripId || '',
      type: 'driver_auto_paused',
      dispatchMode: d.dispatchMode || 'queue',
      dispatchSessionId: d.dispatchSessionId || '',
      dispatchAttempt: d.dispatchAttempt || 1,
      dispatchTotal: d.dispatchTotal || 1,
      userPhone: d.userPhone || '',
      pickupMfy: d.pickupMfy || '',
      dropoffMfy: d.dropoffMfy || '',
      driverId,
      driverName: d.driverName || '',
      driverPhone: d.driverPhone || '',
      scheduleId,
      offerTimeoutSeconds: d.offerTimeoutSeconds || 0,
      reason: `${timeoutAutoPauseStreak} consecutive timeouts`,
      timeoutStreak: streakAfter,
      timeoutAutoPauseStreak,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
}

async function handleExpiredMarshrutTrip(doc) {
  const data = doc.data();
  if ((data.taxiType || '') !== 'marshrut') return;
  if ((data.status || '') !== 'pending') return;
  const tripId = doc.id;
  const tripData = { ...data, tripId };
  await applyMarshrutTimeoutPolicy(tripData);
  await logMarshrutDispatchEvent({ tripId, type: 'timeout', data: tripData });
  await clearMarshrutActiveIfMatches({
    userPhone: data.userPhone,
    tripId,
    status: 'expired',
  });
}

// ─── Trip + Booking TTL cleanup ───────────────────────────────────────────────
// Har 1 daqiqada: muddati o'tgan pending/searching trips va intercity bronlarni yopish
exports.expirePendingTrips = functions.pubsub
  .schedule('every 1 minutes')
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    await sendIntercityDepartureReminders();

    // 1. trips kolleksiyasi (local taxi + marshrut)
    const [pendingSnap, searchingSnap] = await Promise.all([
      db.collection('trips').where('status', '==', 'pending')
        .where('expiresAt', '<', now).get(),
      db.collection('trips').where('status', '==', 'searching')
        .where('expiresAt', '<', now).get(),
    ]);

    // 2. intercity_bookings — faqat pending (confirmed muddati o'tmasin) (#10)
    const intercitySnap = await db.collection('intercity_bookings')
      .where('status', '==', 'pending')
      .where('expiresAt', '<', now)
      .get();

    // 3. ads — ИШ ТОП: active|pending → completed; cheap_product → inactive
    const [expiredAdsActiveSnap, expiredAdsPendingSnap] = await Promise.all([
      db.collection('ads')
        .where('status', '==', 'active')
        .where('expiresAt', '<', now)
        .get(),
      db.collection('ads')
        .where('status', '==', 'pending')
        .where('expiresAt', '<', now)
        .get(),
    ]);
    const expiredAdsSnap = {
      docs: [...expiredAdsActiveSnap.docs, ...expiredAdsPendingSnap.docs],
      get size() { return this.docs.length; },
    };

    // 3b. yuk_listings — 48 soat muddati o'tgan active → closed
    const expiredYukSnap = await db.collection('yuk_listings')
      .where('status', '==', 'active')
      .where('expiresAt', '<', now)
      .get();

    // 3c. yuk_listings — T−6 soat FCM (ойна ~±90с, cron har 1 daqiqa)
    const sixHMs = 6 * 60 * 60 * 1000;
    const warnWindowMs = 90 * 1000;
    const nowMs = now.toMillis();
    const warnStart = admin.firestore.Timestamp.fromMillis(
      nowMs + sixHMs - warnWindowMs,
    );
    const warnEnd = admin.firestore.Timestamp.fromMillis(
      nowMs + sixHMs + warnWindowMs,
    );
    const warnYukSnap = await db.collection('yuk_listings')
      .where('status', '==', 'active')
      .where('expiresAt', '>=', warnStart)
      .where('expiresAt', '<=', warnEnd)
      .get();

    const allDocs = [
      ...pendingSnap.docs,
      ...searchingSnap.docs,
    ];

    let batch = db.batch();
    let writes = 0;

    // trips → expired (faqat hali searching/pending bo'lsa — accept race himoyasi)
    async function expireTripIfStillOpen(ref) {
      await db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        if (!snap.exists) return;
        const st = String((snap.data() || {}).status || '');
        if (st !== 'pending' && st !== 'searching') return;
        t.update(ref, {
          status: 'expired',
          expiredAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    }
    await Promise.all(allDocs.map((doc) => expireTripIfStillOpen(doc.ref)));

    const marshrutExpired = allDocs.filter((doc) => {
      const d = doc.data();
      return d.taxiType === 'marshrut' && d.status === 'pending';
    });
    for (const doc of marshrutExpired) {
      try {
        await handleExpiredMarshrutTrip(doc);
      } catch (e) {
        console.error('handleExpiredMarshrutTrip', doc.id, e.message || e);
      }
    }

    for (const doc of expiredAdsSnap.docs) {
      const adType = String((doc.data() || {}).type || '');
      if (adType === 'cheap_product') {
        batch.update(doc.ref, {
          status: 'inactive',
          autoExpiredAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else {
        batch.update(doc.ref, {
          status: 'completed',
          autoExpiredAt: admin.firestore.FieldValue.serverTimestamp(),
          editedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      writes++;
      if (writes >= 450) {
        await batch.commit();
        batch = db.batch();
        writes = 0;
      }
    }

    for (const doc of expiredYukSnap.docs) {
      const yuk = doc.data() || {};
      batch.update(doc.ref, {
        status: 'closed',
        closedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        autoExpired: true,
      });
      writes++;

      const ownerKey = digits(yuk.ownerId || yuk.phone || '');
      if (ownerKey.length >= 9) {
        const route = `${yuk.from || ''} → ${yuk.to || ''}`.trim();
        const notifRef = db.collection('notifications').doc();
        batch.set(notifRef, {
          targetPhone: ownerKey,
          title: 'Эълонингиз ёпилди',
          body: route
            ? `${route} — 48 соат муддати тугади`
            : 'Юк биржаси эълони 48 соатдан кейин ёпилди',
          sent: false,
          type: 'yuk_listing_closed',
          screen: 'yuk_birja',
          listingId: doc.id,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        writes++;
      }

      if (writes >= 450) {
        await batch.commit();
        batch = db.batch();
        writes = 0;
      }
    }

    // yuk T−6h огоҳлантириш (бир марта, expireSoonNotified)
    for (const doc of warnYukSnap.docs) {
      const yuk = doc.data() || {};
      if (yuk.expireSoonNotified === true) continue;
      const ownerKey = digits(yuk.ownerId || yuk.phone || '');
      if (ownerKey.length < 9) continue;

      batch.update(doc.ref, {
        expireSoonNotified: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      writes++;

      const route = `${yuk.from || ''} → ${yuk.to || ''}`.trim();
      const notifRef = db.collection('notifications').doc();
      batch.set(notifRef, {
        targetPhone: ownerKey,
        title: 'Эълон муддати тугамоқда',
        body: route
          ? `${route} — 6 соат қолди`
          : 'Юк биржаси эълонига 6 соат қолди',
        sent: false,
        type: 'yuk_listing_expire_soon',
        screen: 'yuk_birja',
        listingId: doc.id,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      writes++;

      if (writes >= 450) {
        await batch.commit();
        batch = db.batch();
        writes = 0;
      }
    }

    // intercity_bookings → expired + seat qaytarish
    const expiredIntercityDriverIds = new Set();
    for (const doc of intercitySnap.docs) {
      const booking = doc.data();
      const passengers = booking.passengers || 1;
      const driverId = booking.driverId || '';
      if (driverId) expiredIntercityDriverIds.add(driverId);

      batch.update(doc.ref, {
        status: 'expired',
        expiredAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const userKey = digits(booking.userPhone || '');
      if (userKey.length >= 9) {
        const notifRef = db.collection('notifications').doc();
        batch.set(notifRef, {
          targetPhone: userKey,
          title: '⏱ Брон муддати ўтди',
          body: 'Ҳайдовчи жавоб бермади. Бошқа ҳайдовчи танланг.',
          sent: false,
          type: 'intercity_booking_cancelled',
          bookingId: doc.id,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        writes++;
      }

      // O'rinni qaytarish (agar haqiqiy driver bo'lsa)
      if (driverId && !['1', '2', '3', '4', '5'].includes(driverId)) {
        const driverRef = db.collection('intercity_drivers').doc(driverId);
        batch.update(driverRef, {
          seats: admin.firestore.FieldValue.increment(passengers),
        });
      }

      // Doimiy mijoz statistikasi — cancelBooking kabi qaytarish
      const totalAmount = Number(booking.totalAmount) || 0;
      if (driverId && userKey.length >= 9 && totalAmount > 0) {
        const clientRef = db.collection('intercity_drivers')
          .doc(driverId)
          .collection('clients')
          .doc(userKey);
        const clientSnap = await clientRef.get();
        if (clientSnap.exists) {
          batch.update(clientRef, {
            bookingCount: admin.firestore.FieldValue.increment(-1),
            totalSpent: admin.firestore.FieldValue.increment(-totalAmount),
            lastBookingAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          writes++;
        }
      }

      if (driverId && userKey.length >= 9) {
        batch.delete(
          db.collection('intercity_booking_locks').doc(`${driverId}_${userKey}`),
        );
        writes++;
      }

      const bookingId = doc.id;
      if (userKey.length >= 9) {
        const passengerLockRef = db.collection('intercity_passenger_locks').doc(userKey);
        const passengerLockSnap = await passengerLockRef.get();
        if (passengerLockSnap.exists
            && passengerLockSnap.data()?.bookingId === bookingId) {
          batch.delete(passengerLockRef);
          writes++;
        }
      }

      writes++;
      if (writes >= 450) {
        await batch.commit();
        batch = db.batch();
        writes = 0;
      }
    }

    if (writes > 0) await batch.commit();

    for (const driverId of expiredIntercityDriverIds) {
      await updateDriverGenderStats(driverId);
    }

    console.log(
      `expirePendingTrips: trips=${allDocs.length}, intercity=${intercitySnap.size}`
        + `, yukClosed=${expiredYukSnap.size}, yukWarn=${warnYukSnap.size}`,
    );
    return null;
  });

// ─── Namoyish (demo) yuk — ish vaqti / TTL backfill (online model yo'q) ──────
// Mijoz endi `lastOnlineAt` stale filtrini ishlatmaydi: ko'rinish = GPS +
// work hours + expiresAt. Demo hech qachon expire qilinmaydi (client isDemo).
// Bu job eski demo hujjatlarga work hours / uzoq expiresAt yozadi.
exports.refreshYukDemoPresence = functions.pubsub
  .schedule('every 10 minutes')
  .timeZone('Asia/Tashkent')
  .onRun(async () => {
    const snap = await db.collection('yuk_local_drivers')
      .where('isDemo', '==', true)
      .get();
    if (snap.empty) return null;

    const now = admin.firestore.FieldValue.serverTimestamp();
    const far = admin.firestore.Timestamp.fromMillis(
      Date.now() + 180 * 24 * 60 * 60 * 1000,
    );
    let batch = db.batch();
    let writes = 0;
    for (const doc of snap.docs) {
      batch.set(
        doc.ref,
        {
          workStartMinutes: 0,
          workEndMinutes: 24 * 60,
          expiresAt: far,
          updatedAt: now,
          online: admin.firestore.FieldValue.delete(),
          lastOnlineAt: admin.firestore.FieldValue.delete(),
        },
        { merge: true },
      );
      writes += 1;
      if (writes >= 450) {
        await batch.commit();
        batch = db.batch();
        writes = 0;
      }
    }
    if (writes > 0) await batch.commit();
    console.log(`refreshYukDemoPresence: total=${snap.size}`);
    return null;
  });

// ONE-TIME: `food_catalog` — seed. Bir marta HTTP GET qiling, keyin exportni o‘chirib qayta deploy.
exports.seedFoodCatalog = functions
  .runWith({ timeoutSeconds: 120, memory: '256MB', secrets: ['SEED_SECRET'] })
  .https.onRequest(async (req, res) => {
    const expected = process.env.SEED_SECRET;
    if (!expected || req.query.secret !== expected) {
      res.status(403).send('Forbidden');
      return;
    }
    res.set('Access-Control-Allow-Origin', '*');
    const products = [
      { id: 1, name: 'Ош', emoji: '🍚', price: 45000, unit: 'кг', minQty: 0.5, step: 0.5, category: 'Асосий', desc: 'Тозалиги ва мазаси билан', imageUrl: '' },
      { id: 2, name: 'Товуқ табака', emoji: '🍗', price: 60000, unit: 'кг', minQty: 0.5, step: 0.5, category: 'Товуқ', desc: 'Тандирда босиб пишган', imageUrl: '' },
      { id: 3, name: 'Товуқ қовурдоқ', emoji: '🍳', price: 55000, unit: 'кг', minQty: 0.5, step: 0.5, category: 'Товуқ', desc: 'Зираворлар билан қовурилган', imageUrl: '' },
      { id: 4, name: 'Чўғда пишган товуқ', emoji: '🔥', price: 65000, unit: 'кг', minQty: 0.5, step: 0.5, category: 'Товуқ', desc: 'Кўмир устида', imageUrl: '' },
      { id: 5, name: 'Сарёғда қовурилган товуқ', emoji: '🧈', price: 70000, unit: 'кг', minQty: 0.5, step: 0.5, category: 'Товуқ', desc: 'Асл сарёғда', imageUrl: '' },
      { id: 6, name: 'Қовурилган балиқ', emoji: '🐟', price: 80000, unit: 'кг', minQty: 0.5, step: 0.5, category: 'Балиқ', desc: 'Тоза балиқ, зираворлар билан', imageUrl: '' },
      { id: 7, name: 'Кўмирда пишган балиқ', emoji: '🐠', price: 90000, unit: 'кг', minQty: 0.5, step: 0.5, category: 'Балиқ', desc: 'Кўмир ўтида', imageUrl: '' },
      { id: 8, name: 'Иликли шўрва', emoji: '🍲', price: 25000, unit: 'литр', minQty: 1.0, step: 0.5, category: 'Шўрва', desc: 'Иссиқ, тўйимли', imageUrl: '' },
      { id: 9, name: 'Мастава', emoji: '🥘', price: 22000, unit: 'литр', minQty: 1.0, step: 0.5, category: 'Шўрва', desc: 'Гуруч билан шўрва', imageUrl: '' },
      { id: 10, name: 'Димлама', emoji: '🫕', price: 50000, unit: 'кг', minQty: 0.5, step: 0.5, category: 'Асосий', desc: 'Сабзавотлар билан дамланган гўшт', imageUrl: '' },
      { id: 11, name: 'Қовурдоқ', emoji: '🥩', price: 75000, unit: 'кг', minQty: 0.5, step: 0.5, category: 'Асосий', desc: 'Пиёз билан қовурилган', imageUrl: '' },
      { id: 12, name: 'Шашлик', emoji: '🍢', price: 85000, unit: 'кг', minQty: 0.5, step: 0.5, category: 'Асосий', desc: 'Кўмирда пишган', imageUrl: '' },
      { id: 13, name: 'Сув 0.5 л', emoji: '💧', price: 3000, unit: 'дона', minQty: 1, step: 1, category: 'Ичимликлар', desc: 'Тоза ичимлик суви', imageUrl: '' },
      { id: 14, name: 'Сув 1.5 л', emoji: '💧', price: 6000, unit: 'дона', minQty: 1, step: 1, category: 'Ичимликлар', desc: 'Тоза ичимлик суви', imageUrl: '' },
      { id: 15, name: 'Кола 1 л', emoji: '🥤', price: 10000, unit: 'дона', minQty: 1, step: 1, category: 'Ичимликлар', desc: 'Совутилган', imageUrl: '' },
      { id: 16, name: 'Фанта 1 л', emoji: '🍊', price: 10000, unit: 'дона', minQty: 1, step: 1, category: 'Ичимликлар', desc: 'Апельсин', imageUrl: '' },
      { id: 17, name: 'Спрайт 1 л', emoji: '🫧', price: 10000, unit: 'дона', minQty: 1, step: 1, category: 'Ичимликлар', desc: 'Лимон-лайм', imageUrl: '' },
      { id: 18, name: 'Шарбат 1 л', emoji: '🧃', price: 12000, unit: 'дона', minQty: 1, step: 1, category: 'Ичимликлар', desc: 'Табиий шарбат', imageUrl: '' },
      { id: 19, name: 'Айран 0.5 л', emoji: '🥛', price: 7000, unit: 'дона', minQty: 1, step: 1, category: 'Ичимликлар', desc: 'Совутилган', imageUrl: '' },
      { id: 20, name: 'Сут 1 л', emoji: '🍼', price: 14000, unit: 'дона', minQty: 1, step: 1, category: 'Ичимликлар', desc: 'Тоза сут', imageUrl: '' },
    ];
    const batch = admin.firestore().batch();
    for (const p of products) {
      const ref = admin.firestore().collection('food_catalog').doc(`food_${p.id}`);
      batch.set(ref, {
        ...p,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    await batch.commit();
    res.json({ ok: true, count: products.length });
  });

/**
 * Directions API proxy — brauzerdan to'g'ri chaqirib bo'lmaydi (CORS).
 * Flutter web bu funksiyani ishlatadi.
 */
exports.getDirections = functions
  .runWith({ secrets: ['DIRECTIONS_API_KEY'] })
  .https.onCall(async (data, context) => {
    const origin = String(data.origin || '');
    const destination = String(data.destination || '');
    const waypoints = String(data.waypoints || '');
    const mode = String(data.mode || 'driving');
    const language = String(data.language || 'uz');

    if (!origin || !destination) {
      throw new functions.https.HttpsError(
        'invalid-argument', 'origin va destination majburiy');
    }

    const apiKey = process.env.DIRECTIONS_API_KEY;
    if (!apiKey) {
      throw new functions.https.HttpsError(
        'internal', 'DIRECTIONS_API_KEY sozlanmagan');
    }

    const params = new URLSearchParams({
      origin,
      destination,
      mode,
      language,
      key: apiKey,
    });
    if (waypoints) params.append('waypoints', waypoints);

    try {
      const url = `https://maps.googleapis.com/maps/api/directions/json?${params}`;
      const response = await axios.get(url);
      return response.data;
    } catch (e) {
      throw new functions.https.HttpsError('internal', `Directions xatosi: ${e.message}`);
    }
  });

// Auto-offline: marshrut haydovchi lastSeenAt > 3 daqiqa bo'lsa
exports.marshrutDriverAutoOffline = functions.pubsub
  .schedule('every 2 minutes')
  .onRun(async () => {
    try {
      const cutoff = admin.firestore.Timestamp.fromMillis(
        Date.now() - 3 * 60 * 1000,
      );

      let staleSnap;
      try {
        staleSnap = await db.collection('drivers')
          .where('isOnline', '==', true)
          .where('lastSeenAt', '<', cutoff)
          .get();
      } catch (err) {
        if (err.code === 9 || (err.message && err.message.includes('index'))) {
          console.log('marshrutDriverAutoOffline: index not ready, skipping.');
          return null;
        }
        console.error('marshrutDriverAutoOffline query error:', err.message);
        return null;
      }

      if (!staleSnap || staleSnap.empty) return null;

      let batch = db.batch();
      let writes = 0;
      for (const doc of staleSnap.docs) {
        const data = doc.data();
        if (data.taxiType !== 'marshrut' && data.taxiType !== 'both') continue;

        const activeTripSnap = await db.collection('trips')
          .where('acceptedDriverId', '==', doc.id)
          .where('taxiType', '==', 'marshrut')
          .where('status', '==', 'accepted')
          .limit(1)
          .get();

        if (!activeTripSnap.empty) {
          console.log(`marshrutAutoOffline: skip ${doc.id} — has active trip`);
          continue;
        }

        batch.update(doc.ref, {
          isOnline: false,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        writes++;

        batch.set(
          db.collection('queue').doc(doc.id),
          {
            isActive: false,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        writes++;

        if (writes >= 450) {
          await batch.commit();
          batch = db.batch();
          writes = 0;
        }
      }
      if (writes > 0) {
        await batch.commit();
      }
      return null;
    } catch (err) {
      console.error('marshrutDriverAutoOffline error:', err.message || err);
      return null;
    }
  });

/**
 * Migration: titleLower + searchTokens for cheap_product ads.
 * Callable; requires authenticated admin/superadmin user doc.
 */
exports.migrateCheapProductTitleLower = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Auth required',
      );
    }
    const phone = (context.auth.token.phone_number || '').replace('+', '');
    if (!phone) {
      throw new functions.https.HttpsError('failed-precondition', 'No phone');
    }
    const userSnap = await db.collection('users').doc(phone).get();
    const role = userSnap.exists ? userSnap.data().role : '';
    if (!['admin', 'superadmin'].includes(role)) {
      throw new functions.https.HttpsError('permission-denied', 'Admin only');
    }

    let updated = 0;
    let lastId = null;
    const pageSize = 400;
    // eslint-disable-next-line no-constant-condition
    while (true) {
      let q = db
        .collection('ads')
        .where('type', '==', 'cheap_product')
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(pageSize);
      if (lastId) q = q.startAfter(lastId);
      const snap = await q.get();
      if (snap.empty) break;

      const batch = db.batch();
      let writes = 0;
      for (const doc of snap.docs) {
        lastId = doc.id;
        const d = doc.data();
        const title = (d.title || '').toString();
        if (!title) continue;
        const description = (d.description || '').toString();
        const lower = (d.titleLower || '').toString();
        const tokens = Array.isArray(d.searchTokens) ? d.searchTokens : [];
        const needLower = !lower;
        const needTokens = tokens.length === 0;
        if (!needLower && !needTokens) continue;
        const patch = {};
        if (needLower) patch.titleLower = title.toLowerCase();
        if (needTokens) {
          patch.searchTokens = buildMarketSearchTokens(title, description);
        }
        batch.update(doc.ref, patch);
        writes++;
        updated++;
      }
      if (writes > 0) await batch.commit();
      if (snap.size < pageSize) break;
    }
    return { updated };
  },
);

/** Mahalliy taksi — yo'lovchi bahosi → haydovchi o'rtacha reytingi. */
exports.marshrutPassengerCancelAfterAccept = functions.https.onCall(
    async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            'unauthenticated',
            'Auth required',
        );
      }
      const tripId = String(data.tripId || '').trim();
      const reason = String(data.reason || 'passenger_cancel_after_accept')
          .trim();
      if (!tripId) {
        throw new functions.https.HttpsError(
            'invalid-argument',
            'tripId required',
        );
      }

      const tripRef = db.collection('trips').doc(tripId);
      let userPhone = '';

      await db.runTransaction(async (t) => {
        const tripSnap = await t.get(tripRef);
        if (!tripSnap.exists) {
          throw new functions.https.HttpsError('not-found', 'Trip not found');
        }
        const trip = tripSnap.data() || {};
        if (trip.taxiType !== 'marshrut') {
          throw new functions.https.HttpsError(
              'failed-precondition',
              'Not a marshrut trip',
          );
        }
        if (trip.status !== 'accepted') {
          throw new functions.https.HttpsError(
              'failed-precondition',
              'Trip not accepted',
          );
        }
        userPhone = digits(trip.userPhone || '');
        const scheduleId = trip.scheduleId || '';
        const driverId = trip.acceptedDriverId || '';

        t.update(tripRef, {
          status: 'cancelled',
          cancelledBy: 'passenger',
          cancelReason: reason,
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
          notifyPassengerReroute: false,
          marshrutBlockCounted: true,
        });

        if (scheduleId) {
          const schedRef = db.collection('schedules').doc(scheduleId);
          const schedSnap = await t.get(schedRef);
          if (schedSnap.exists) {
            const schedData = schedSnap.data() || {};
            const seats = Number(schedData.seats) || 1;
            const seatsLeft = Math.min(
                (Number(schedData.seatsLeft) || 0) + 1,
                seats,
            );
            t.update(schedRef, {
              seatsLeft,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
        }

        if (driverId) {
          const queueRef = db.collection('queue').doc(driverId);
          const queueSnap = await t.get(queueRef);
          if (queueSnap.exists) {
            const queueData = queueSnap.data() || {};
            const seats = Number(queueData.seats) || 1;
            const seatsLeft = Math.min(
                (Number(queueData.seatsLeft) || 0) + 1,
                seats,
            );
            t.update(queueRef, {
              seatsLeft,
              isActive: true,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
          t.set(
              db.collection('drivers').doc(driverId),
              {
                isBusy: false,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true },
          );
        }

        if (userPhone.length >= 9) {
          t.set(
              db.collection('users').doc(userPhone)
                  .collection('marshrut_state').doc('active'),
              {
                status: 'cancelled',
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true },
          );
        }
      });

      try {
        await db.collection('marshrut_dispatch_events').add({
          tripId,
          type: 'passenger_cancel_after_accept',
          cancelledBy: 'passenger',
          cancelReason: reason,
          userPhone,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (e) {
        console.warn('marshrut dispatch event:', e.message || e);
      }

      if (userPhone.length < 9) {
        return { ok: true };
      }

      const blockResult = await applyMarshhrutCancelBlock(userPhone);
      if (blockResult.warning) {
        return {
          ok: true,
          warning: true,
          remaining: blockResult.remaining,
        };
      }
      if (blockResult.blocked) {
        return { ok: true, blocked: true };
      }
      return { ok: true };
    },
);

exports.updateDriverRating = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Auth required',
    );
  }
  const { driverId, rating, tripId } = data;
  if (!driverId || !rating || rating < 1 || rating > 5) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Invalid rating',
    );
  }

  const driverRef = db.collection('drivers').doc(driverId);

  await db.runTransaction(async (t) => {
    const snap = await t.get(driverRef);
    if (!snap.exists) return;

    const d = snap.data();
    const totalRatings = (d.totalRatings ?? 0) + 1;
    const ratingSum = (d.ratingSum ?? 0) + rating;
    const avgRating = Math.round((ratingSum / totalRatings) * 10) / 10;

    t.update(driverRef, {
      totalRatings,
      ratingSum,
      avgRating,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const tripRef = db.collection('trips').doc(tripId);
    t.update(tripRef, {
      passengerRating: rating,
      ratedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { ok: true };
});

// ─────────────────────────────────────────────────────────────────────
// Marshrut yo'nalish narxi (flat, bir o'rin) — "birinchi haydovchi
// belgilaydi, qolganlar o'zgartira olmaydi, faqat admin tahrirlaydi".
//   marshrut_route_prices/{routeKey}  (routeKey = `${from}|${to}`)
//   seedMarshrutRoutePrice      — haydovchi: narx yo'q bo'lsa seed (bir marta),
//                                 bor bo'lsa o'z schedule/queue'siga ko'zgu.
//   adminSetMarshrutRoutePrice  — admin/finance: tahrir + faol reyslarga tarqatish.
// schedules.price / queue.price — faqat shu CF yozadi (fare manbai).
// ─────────────────────────────────────────────────────────────────────

const MARSHRUT_PRICE_CAP = 1000000;

function marshrutRouteKey(from, to) {
  return `${String(from || '').trim()}|${String(to || '').trim()}`;
}

exports.seedMarshrutRoutePrice = functions.https.onCall(async (data, context) => {
  const callerUid = requireCallerUid(context);
  const scheduleId = String((data && data.scheduleId) || '').trim();
  const proposed = Math.trunc(Number((data && data.price) || 0));
  if (!scheduleId) {
    throw new functions.https.HttpsError('invalid-argument', 'scheduleId kerak');
  }

  const schedRef = db.collection('schedules').doc(scheduleId);
  const result = await db.runTransaction(async (tx) => {
    const schedSnap = await tx.get(schedRef);
    if (!schedSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Reys topilmadi');
    }
    const sched = schedSnap.data() || {};
    if (canonicalUid(sched.driverId) !== callerUid) {
      throw new functions.https.HttpsError('permission-denied', 'Faqat reys egasi');
    }
    if ((sched.taxiType || '') !== 'marshrut') {
      throw new functions.https.HttpsError('failed-precondition', 'Faqat marshrut');
    }
    const from = sched.from || '';
    const to = sched.to || '';
    const routeKey = marshrutRouteKey(from, to);
    const routeRef = db.collection('marshrut_route_prices').doc(routeKey);
    const routeSnap = await tx.get(routeRef);

    let price;
    let seeded = false;
    if (routeSnap.exists && Number((routeSnap.data() || {}).price) > 0) {
      // Mavjud — o'zgartirilmaydi, faqat ko'zgu.
      price = Math.trunc(Number(routeSnap.data().price));
    } else {
      // Birinchi haydovchi — seed.
      if (!Number.isInteger(proposed) || proposed <= 0 ||
          proposed > MARSHRUT_PRICE_CAP) {
        throw new functions.https.HttpsError(
            'invalid-argument', 'Narx 0 dan katta va haqiqiy bo\'lsin');
      }
      price = proposed;
      seeded = true;
      tx.set(routeRef, {
        from,
        to,
        price,
        setByDriverId: callerUid,
        setByName: sched.driverName || '',
        lockedByAdmin: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    // Ko'zgu: schedule + queue (fare manbai).
    tx.set(schedRef,
        {price, updatedAt: admin.firestore.FieldValue.serverTimestamp()},
        {merge: true});
    tx.set(db.collection('queue').doc(callerUid),
        {price, updatedAt: admin.firestore.FieldValue.serverTimestamp()},
        {merge: true});
    return {price, seeded, routeKey};
  });

  return {ok: true, ...result};
});

exports.adminSetMarshrutRoutePrice = functions.https.onCall(
    async (data, context) => {
      const callerUid = await requireCallerRoles(
          context, ['admin', 'superadmin', 'finance'],
          'Admin/finance role required');
      const from = String((data && data.from) || '').trim();
      const to = String((data && data.to) || '').trim();
      const price = Math.trunc(Number((data && data.price) || 0));
      if (!from || !to) {
        throw new functions.https.HttpsError('invalid-argument', 'from/to kerak');
      }
      if (!Number.isInteger(price) || price <= 0 || price > MARSHRUT_PRICE_CAP) {
        throw new functions.https.HttpsError('invalid-argument', 'Narx noto\'g\'ri');
      }
      const routeKey = marshrutRouteKey(from, to);
      await db.collection('marshrut_route_prices').doc(routeKey).set({
        from,
        to,
        price,
        lockedByAdmin: true,
        lastEditedBy: callerUid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      // Faol reyslar + navbatga tarqatish.
      let propagated = 0;
      const schedSnap = await db.collection('schedules')
          .where('taxiType', '==', 'marshrut')
          .where('isActive', '==', true)
          .where('from', '==', from)
          .where('to', '==', to)
          .get();
      const batch = db.batch();
      schedSnap.forEach((doc) => {
        batch.set(doc.ref,
            {price, updatedAt: admin.firestore.FieldValue.serverTimestamp()},
            {merge: true});
        const driverId = canonicalUid((doc.data() || {}).driverId);
        if (driverId) {
          batch.set(db.collection('queue').doc(driverId),
              {price, updatedAt: admin.firestore.FieldValue.serverTimestamp()},
              {merge: true});
        }
        propagated += 1;
      });
      await batch.commit();

      return {ok: true, routeKey, price, propagated};
    });

// ─────────────────────────────────────────────────────────────────────
// Entertainment — yuklangan video avtomat 720p'ga siqiladi (ffmpeg).
//   Trigger: Storage finalize (2-avlod / Eventarc — .firebasestorage.app uchun).
//   Faqat `entertainment/*.mp4`. Loop oldini olish: `transcoded` metadata flag.
//   Natija: o'sha path ustiga 720p yoziladi + catalog.downloadUrl yangilanadi.
// ─────────────────────────────────────────────────────────────────────
const {onObjectFinalized} = require('firebase-functions/v2/storage');

exports.transcodeEntertainmentVideo = onObjectFinalized(
    {
      bucket: 'master-taxi-gurlan.firebasestorage.app',
      region: 'us-central1',
      memory: '4GiB',
      timeoutSeconds: 540,
      cpu: 2,
    },
    async (event) => {
      const object = event.data;
      const name = object.name || '';
      if (!name.startsWith('entertainment/') || !name.endsWith('.mp4')) {
        return;
      }
      // Loop guard — biz qayta yuklagan (siqilgan) fayl.
      const meta = object.metadata || {};
      if (meta.transcoded === 'true') {
        return;
      }

      const os = require('os');
      const path = require('path');
      const fs = require('fs');
      const {spawnSync} = require('child_process');
      const ffmpegPath = require('ffmpeg-static');

      const bucketName = object.bucket;
      const bucket = admin.storage().bucket(bucketName);
      const videoId = path.basename(name, '.mp4');
      const tmpIn = path.join(os.tmpdir(), `${videoId}_in.mp4`);
      const tmpOut = path.join(os.tmpdir(), `${videoId}_720.mp4`);

      try {
        await bucket.file(name).download({destination: tmpIn});

        try {
          fs.chmodSync(ffmpegPath, 0o755);
        } catch (_) {}

        // 720p (kichikni kattalashtirmaymiz), H.264 + faststart (stream uchun).
        const res = spawnSync(ffmpegPath, [
          '-i', tmpIn,
          '-vf', 'scale=-2:\'min(720,ih)\'',
          '-c:v', 'libx264',
          '-preset', 'veryfast',
          '-crf', '26',
          '-c:a', 'aac',
          '-b:a', '128k',
          '-movflags', '+faststart',
          '-y', tmpOut,
        ], {stdio: 'inherit', maxBuffer: 64 * 1024 * 1024});

        if (res.status !== 0 || !fs.existsSync(tmpOut)) {
          console.error('ffmpeg failed', res.status, res.error);
          return;
        }

        const token = crypto.randomUUID();
        await bucket.upload(tmpOut, {
          destination: name,
          metadata: {
            contentType: 'video/mp4',
            metadata: {
              transcoded: 'true',
              firebaseStorageDownloadTokens: token,
            },
          },
        });

        const encoded = encodeURIComponent(name);
        const url = `https://firebasestorage.googleapis.com/v0/b/${bucketName}` +
            `/o/${encoded}?alt=media&token=${token}`;

        await db.collection('entertainment_catalog').doc(videoId).set({
          downloadUrl: url,
          transcoded: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      } catch (e) {
        console.error('transcodeEntertainmentVideo error:', e);
      } finally {
        try {
          if (fs.existsSync(tmpIn)) fs.unlinkSync(tmpIn);
        } catch (_) {}
        try {
          if (fs.existsSync(tmpOut)) fs.unlinkSync(tmpOut);
        } catch (_) {}
      }
    });

exports.migratePhoneFormats = functions.https.onCall(
    async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            'unauthenticated', 'Auth required');
      }
      const callerPhone = context.auth.token.phone_number
          ?.replace(/\D/g, '') ?? '';
      const callerDoc = await db.collection('users')
          .doc(callerPhone).get();
      if (!['admin', 'superadmin']
          .includes(callerDoc.data()?.role)) {
        throw new functions.https.HttpsError(
            'permission-denied', 'Admin only');
      }

      const dryRun = data.dryRun !== false; // default dry run
      const collections = ['drivers', 'queue',
        'intercity_drivers', 'driver_requests'];
      const results = {};

      for (const col of collections) {
        const snap = await db.collection(col).get();
        results[col] = { found: 0, migrated: 0, skipped: 0 };

        for (const doc of snap.docs) {
          const id = doc.id;
          // Only migrate 9-digit IDs
          if (!/^\d{9}$/.test(id)) {
            results[col].skipped++;
            continue;
          }
          const newId = '998' + id;
          results[col].found++;

          if (!dryRun) {
            // Copy to new doc
            const newRef = db.collection(col).doc(newId);
            const existing = await newRef.get();
            if (!existing.exists) {
              await newRef.set(doc.data());
            }
            // Copy subcollections (clients under intercity_drivers)
            if (col === 'intercity_drivers') {
              const clients = await doc.ref
                  .collection('clients').get();
              for (const c of clients.docs) {
                await newRef.collection('clients')
                    .doc(c.id).set(c.data());
              }
            }
            // Mark old doc as migrated (don't delete yet)
            await doc.ref.update({
              _migratedTo: newId,
              _migratedAt: admin.firestore.FieldValue
                  .serverTimestamp(),
            });
            results[col].migrated++;
          } else {
            results[col].migrated++; // dry run count
          }
        }
      }

      return { dryRun, results };
    },
);

exports.autoUpdateDepartureTime =
    functions.pubsub
        .schedule('every 5 minutes')
        .onRun(async () => {
          const now = new Date();
          const soon = new Date(now.getTime() + 10 * 60 * 1000);

          const snap = await db
              .collection('intercity_drivers')
              .where('isActive', '==', true)
              .get();

          const batch = db.batch();
          let count = 0;

          snap.docs.forEach((doc) => {
            const d = doc.data();
            const dept = d.departureTime?.toDate?.();
            if (!dept) return;

            if (dept <= soon && dept >= now) {
              const newTime = new Date(
                  dept.getTime() + 2 * 60 * 60 * 1000);
              batch.update(doc.ref, {
                departureTime: admin.firestore.Timestamp.fromDate(newTime),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              });
              count++;
            }
          });

          if (count > 0) await batch.commit();
          console.log(`autoUpdateDepartureTime: ${count} updated`);
          return null;
        });

// ─────────────────────────────────────────────────────────────────────
// Local taxi: "осилиб қолган" reserved трипларни тозалаш (захира).
// Ҳайдовчи "Қабул" босиб трипни банд қилади (status: reserved), илова
// 10 сонияли таймер юритади. Агар илова ёпилса/интернет узилса, трип
// "reserved" ҳолатида осилиб қолмаслиги учун — бу CF ҳар 1 дақиқада
// reservedAt'дан 60+ сония ўтган reserved трипларни "searching"'га
// қайтаради (бошқа ҳайдовчилар яна кўра олиши учун).
// ─────────────────────────────────────────────────────────────────────
exports.releaseStaleReservations = functions.pubsub
  .schedule('every 1 minutes')
  .timeZone('Asia/Tashkent')
  .onRun(async () => {
    const cutoff = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - 60 * 1000)); // 60 сония олдин
    const snap = await db.collection('trips')
        .where('status', '==', 'reserved')
        .where('reservedAt', '<=', cutoff)
        .limit(100)
        .get();
    if (snap.empty) return null;

    const batch = db.batch();
    let count = 0;
    snap.forEach((doc) => {
      batch.update(doc.ref, {
        status: 'searching',
        reservedBy: '',
        reservedByName: '',
        reservedAt: admin.firestore.FieldValue.delete(),
      });
      count++;
    });
    await batch.commit();
    console.log(`releaseStaleReservations: ${count} trip(s) released`);
    return null;
  });

// ─────────────────────────────────────────────────────────────────────
// Settlement Ledger — sverka (reconciliation).
// Faqat admin/superadmin/finance/auditor o'qiy oladi. Invariantlarni
// tekshiradi: Σdr==Σcr, buxgalteriya tengligi, passenger_credit proeksiyasi.
// To'liq dizayn: docs/settlement_ledger_v1_uz.md
// ─────────────────────────────────────────────────────────────────────
exports.reconcileLedger = functions.https.onCall(async (data, context) => {
  await requireCallerRoles(
      context,
      ['superadmin', 'finance', 'auditor'],
      'Finance/audit role required',
  );
  return settlementLedger.reconcile(db);
});

// Пул назорати — битта snapshot (KPI + навбат + бугунги оқим).
exports.getMoneyControlSnapshot = functions.https.onCall(async (data, context) => {
  await requireCallerRoles(
      context,
      ['superadmin', 'finance', 'auditor'],
      'Finance/audit role required',
  );
  return settlementLedger.moneyControlSnapshot(db);
});

// Курьер нақдини кассага қабул қилиш (инкассация).
// Dr admin_cash / Cr courier_cash:{phone}
exports.receiveCourierCash = functions.https.onCall(async (data, context) => {
  const callerUid = await requireCallerRoles(
      context, ['superadmin', 'finance'], 'Finance role required');
  const courierPhone = canonicalUid(data && (data.courierPhone || data.courierUid));
  const amount = Math.trunc(Number((data && data.amount) || 0));
  const opId = String((data && data.opId) || '').trim();
  if (!courierPhone || courierPhone.length < 12) {
    throw new functions.https.HttpsError('invalid-argument', 'courierPhone noto\'g\'ri');
  }
  if (!Number.isInteger(amount) || amount <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'amount musbat butun bo\'lsin');
  }
  if (!opId || opId.length < 6) {
    throw new functions.https.HttpsError('invalid-argument', 'opId (idempotency key) kerak');
  }
  const cashAcc = settlementLedger.courierCashAccount(courierPhone);
  const res = await settlementLedger.postEntry(db, {
    idempotencyKey: `courierInkassa:${opId}`,
    kind: 'courier_inkassa',
    refType: 'courier_inkassa',
    refId: opId,
    postedBy: callerUid,
    postedRole: 'finance',
    legs: [
      { account: 'admin_cash', dr: amount },
      { account: cashAcc, cr: amount },
    ],
  }, {
    mirrorBonus: false,
    meta: { courierPhone, amount },
    assert: ({ accounts }) => {
      const ca = accounts.get(cashAcc);
      if (!ca || ca.prev < amount) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            `Курьерда етарли нақд йўқ (бор: ${ca ? ca.prev : 0})`);
      }
    },
  });
  const balSnap = await db.collection(settlementLedger.COL_ACCOUNTS).doc(cashAcc).get();
  const remaining = balSnap.exists ? ((balSnap.data() || {}).balance || 0) : 0;
  return {
    ok: true,
    idempotent: !!res.idempotent,
    amount,
    courierPhone,
    courierCashRemaining: remaining,
  };
});

// ─────────────────────────────────────────────────────────────────────
// Settlement Ledger — Daily Closing (Qadam 6).
//   closePeriod — kunlik davr qulfi. `period_closings/{YYYY-MM-DD}` ga
//   davr (UTC kun) yozuvlari + global reconcile snapshotini yozadi va
//   `locked: true` qiladi. Idempotent: davr qulflangan bo'lsa qayta hisoblamaydi.
//   journal_entries — o'zgarmas, shuning uchun qulf faqat snapshot/audit uchun.
// To'liq dizayn: docs/settlement_ledger_v1_uz.md (13-bo'lim)
// ─────────────────────────────────────────────────────────────────────
exports.closePeriod = functions.https.onCall(async (data, context) => {
  const callerUid = await requireCallerRoles(
      context, ['superadmin', 'finance'], 'Finance role required');

  const periodId = String((data && data.periodId) || '').trim() ||
      new Date().toISOString().slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(periodId)) {
    throw new functions.https.HttpsError(
        'invalid-argument', 'periodId YYYY-MM-DD bo\'lsin');
  }

  const ref = db.collection('period_closings').doc(periodId);
  const existing = await ref.get();
  if (existing.exists && (existing.data() || {}).locked) {
    return {
      ok: true, alreadyClosed: true, periodId,
      totals: (existing.data() || {}).totals || {},
    };
  }

  const from = new Date(`${periodId}T00:00:00.000Z`);
  const to = new Date(from.getTime() + 24 * 3600 * 1000);
  const fromTs = admin.firestore.Timestamp.fromDate(from);
  const toTs = admin.firestore.Timestamp.fromDate(to);

  // Global invariant snapshot (Σ=0, identity, proeksiya).
  const rec = await settlementLedger.reconcile(db);

  // Davr ichidagi yozuvlar (ts oralig'i [from, to)).
  const jSnap = await db.collection('journal_entries')
      .where('ts', '>=', fromTs)
      .where('ts', '<', toTs)
      .get();
  let periodDr = 0;
  let periodCr = 0;
  const kinds = {};
  jSnap.forEach((d) => {
    const x = d.data() || {};
    for (const l of (x.legs || [])) {
      periodDr += l.dr || 0;
      periodCr += l.cr || 0;
    }
    const k = x.kind || 'unknown';
    kinds[k] = (kinds[k] || 0) + 1;
  });

  const totals = {
    periodEntryCount: jSnap.size,
    periodDr,
    periodCr,
    periodBalanced: periodDr === periodCr,
    kinds,
    globalAssets: rec.assets,
    globalLiabilities: rec.liabilities,
    globalEntryCount: rec.entryCount,
    globalAccountCount: rec.accountCount,
    balanced: rec.balanced,
    identityOk: rec.identityOk,
    projectionOk: rec.projectionOk,
    mismatchCount: (rec.mismatches || []).length,
  };

  await ref.set({
    periodId,
    from: fromTs,
    to: toTs,
    closedBy: callerUid,
    closedAt: admin.firestore.FieldValue.serverTimestamp(),
    locked: true,
    totals,
  }, { merge: true });

  return { ok: true, periodId, locked: true, totals };
});

// ─────────────────────────────────────────────────────────────────────
// Settlement Ledger — Driver Float (Qadam 2).
//   floatTopUp     — haydovchi naqd depozit topshiradi (admin/finance yozadi)
//                    Dr admin_cash / Cr driver_float:{uid}, floatMax cap bilan.
//   floatReturn    — float qaytarish (finance tasdig'i)
//                    Dr driver_float:{uid} / Cr admin_cash, manfiylik bo'lmasin.
//   driverFloatStatus — float balansi + zona (read-only).
// Idempotent: klient `opId` (UUID) yuboradi. Cap/manfiylik TRANSACTION
// ichida (assert) tekshiriladi. To'liq dizayn: docs/settlement_ledger_v1_uz.md
// ─────────────────────────────────────────────────────────────────────

/** `data`'dan haydovchi uid (998 + 9), summa (butun, >0) va opId ni tekshiradi. */
function parseFloatOpInput(data) {
  const driverUid = canonicalUid(data && (data.driverUid || data.driverPhone));
  const amount = Math.trunc(Number((data && data.amount) || 0));
  const opId = String((data && data.opId) || '').trim();
  if (!driverUid || driverUid.length < 12) {
    throw new functions.https.HttpsError('invalid-argument', 'driverUid noto\'g\'ri');
  }
  if (!Number.isInteger(amount) || amount <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'amount musbat butun bo\'lsin');
  }
  if (!opId || opId.length < 6) {
    throw new functions.https.HttpsError('invalid-argument', 'opId (idempotency key) kerak');
  }
  return { driverUid, amount, opId };
}

async function floatStatusOf(driverUid) {
  const config = await settlementLedger.getConfig(db);
  const ref = db.collection(settlementLedger.COL_ACCOUNTS)
      .doc(settlementLedger.driverFloatAccount(driverUid));
  const snap = await ref.get();
  const a = snap.exists ? (snap.data() || {}) : {};
  const balance = a.balance || 0;
  const lastTopUpAmount = a.lastTopUpAmount || 0;
  const dto = a.deferredTimeoutAt && a.deferredTimeoutAt.toMillis
      ? a.deferredTimeoutAt.toMillis() : null;
  return {
    driverUid,
    balance,
    zone: settlementLedger.floatZone(balance, config),
    settlementEnabled: settlementLedger.settlementEnabled(balance, config),
    blocked: balance < 0,
    blockedReason: balance < 0 ? (a.blockedReason || 'deferred_debt') : '',
    lastTopUpAmount,
    deferredFloor: settlementLedger.deferredFloor(lastTopUpAmount, config),
    deferredTimeoutAt: dto,
    config,
  };
}

/** Float top-up deprecated — Cash Exchange (cashExchange) ishlatilsin. */
exports.floatTopUp = functions.https.onCall(async () => {
  throw new functions.https.HttpsError(
      'failed-precondition',
      'floatTopUp yopilgan. cashExchange (Cash In → Wallet) ishlating');
});

/** Float return deprecated — walletToCash ishlatilsin. */
exports.floatReturn = functions.https.onCall(async () => {
  throw new functions.https.HttpsError(
      'failed-precondition',
      'floatReturn yopilgan. walletToCash (Wallet → Cash) ishlating');
});

/**
 * Cash Exchange — bitta UI amali, orqada 2 journal:
 *   1) cash_in:        Dr admin_cash / Cr admin_clearing
 *   2) cash_to_wallet: Dr admin_clearing / Cr passenger_credit:{uid}
 * Net: admin_cash +, passenger_credit +, clearing 0. Manfiy wallet yo'q.
 */
exports.cashExchange = functions.https.onCall(async (data, context) => {
  const callerUid = await requireCallerRoles(
      context, ['superadmin', 'finance'], 'Finance role required');
  const userUid12 = canonicalUid(data && (data.phone || data.userPhone || data.uid));
  const amount = Math.trunc(Number((data && data.amount) || 0));
  const opId = String((data && data.opId) || '').trim();
  if (!userUid12 || userUid12.length < 12) {
    throw new functions.https.HttpsError('invalid-argument', 'phone noto\'g\'ri');
  }
  if (!Number.isInteger(amount) || amount <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'amount musbat butun bo\'lsin');
  }
  if (!opId || opId.length < 6) {
    throw new functions.https.HttpsError('invalid-argument', 'opId kerak');
  }
  if (!(await isIdentifiedUser(userUid12))) {
    throw new functions.https.HttpsError(
        'failed-precondition',
        'Foydalanuvchi Firestore\'da yo\'q — avval ilovada ro\'yxatdan o\'ting');
  }

  const pcAcc = settlementLedger.passengerCreditAccount(userUid12);
  const inRes = await settlementLedger.postEntry(db, {
    idempotencyKey: `cashExchange_in:${opId}`,
    kind: 'cash_in',
    refType: 'cash_exchange',
    refId: opId,
    postedBy: callerUid,
    postedRole: 'finance',
    legs: [
      { account: 'admin_cash', dr: amount },
      { account: 'admin_clearing', cr: amount },
    ],
  }, {
    mirrorBonus: false,
    meta: { userUid: userUid12, amount, step: 'cash_in' },
  });

  const wRes = await settlementLedger.postEntry(db, {
    idempotencyKey: `cashExchange_wallet:${opId}`,
    kind: 'cash_to_wallet',
    refType: 'cash_exchange',
    refId: opId,
    postedBy: callerUid,
    postedRole: 'finance',
    legs: [
      { account: 'admin_clearing', dr: amount },
      { account: pcAcc, cr: amount },
    ],
  }, {
    mirrorBonus: true,
    walletLedgerType: 'cash_to_wallet',
    meta: { userUid: userUid12, amount, step: 'cash_to_wallet' },
  });

  const userSnap = await db.collection('users').doc(userUid12).get();
  const bonusBalance = userSnap.exists
      ? (parseInt(String((userSnap.data() || {}).bonusBalance ?? 0), 10) || 0)
      : 0;
  return {
    ok: true,
    uid: userUid12,
    amount,
    bonusBalance,
    idempotent: !!(inRes.idempotent && wRes.idempotent),
  };
});

/** Wallet → Cash: Dr passenger_credit / Cr admin_cash. Manfiy taqiqlangan. */
exports.walletToCash = functions.https.onCall(async (data, context) => {
  const callerUid = await requireCallerRoles(
      context, ['superadmin', 'finance'], 'Finance role required');
  const userUid12 = canonicalUid(data && (data.phone || data.userPhone || data.uid));
  const amount = Math.trunc(Number((data && data.amount) || 0));
  const opId = String((data && data.opId) || '').trim();
  if (!userUid12 || userUid12.length < 12) {
    throw new functions.https.HttpsError('invalid-argument', 'phone noto\'g\'ri');
  }
  if (!Number.isInteger(amount) || amount <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'amount musbat butun bo\'lsin');
  }
  if (!opId || opId.length < 6) {
    throw new functions.https.HttpsError('invalid-argument', 'opId kerak');
  }
  if (!(await isIdentifiedUser(userUid12))) {
    throw new functions.https.HttpsError(
        'failed-precondition', 'Foydalanuvchi topilmadi');
  }

  const pcAcc = settlementLedger.passengerCreditAccount(userUid12);
  const res = await settlementLedger.postEntry(db, {
    idempotencyKey: `walletToCash:${opId}`,
    kind: 'wallet_to_cash',
    refType: 'wallet_to_cash',
    refId: opId,
    postedBy: callerUid,
    postedRole: 'finance',
    legs: [
      { account: pcAcc, dr: amount },
      { account: 'admin_cash', cr: amount },
    ],
  }, {
    mirrorBonus: true,
    walletLedgerType: 'wallet_to_cash',
    meta: { userUid: userUid12, amount },
    assert: ({ accounts }) => {
      const pc = accounts.get(pcAcc);
      if (pc && pc.next < 0) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            'Hamyon yetarli emas (manfiy taqiqlangan)');
      }
    },
  });

  const userSnap = await db.collection('users').doc(userUid12).get();
  const bonusBalance = userSnap.exists
      ? (parseInt(String((userSnap.data() || {}).bonusBalance ?? 0), 10) || 0)
      : 0;
  return {
    ok: true,
    uid: userUid12,
    amount,
    bonusBalance,
    idempotent: !!res.idempotent,
  };
});

/**
 * Bir martalik: driver_float:* > 0 → passenger_credit (xuddi shu uid).
 * Manfiy float → ledger_exceptions, migratsiya qilinmaydi.
 */
exports.migrateFloatToWallet = functions.https.onCall(async (data, context) => {
  const callerUid = await requireCallerRoles(
      context, ['superadmin', 'finance'], 'Finance role required');
  const dryRun = !!(data && data.dryRun);
  const snap = await db.collection(settlementLedger.COL_ACCOUNTS).get();
  const migrated = [];
  const skippedNegative = [];
  const skippedZero = [];

  for (const d of snap.docs) {
    if (!d.id.startsWith('driver_float:')) continue;
    const bal = parseInt(String((d.data() || {}).balance ?? 0), 10) || 0;
    const uid = settlementLedger.ownerUidOf(d.id);
    if (!uid) continue;
    if (bal < 0) {
      skippedNegative.push({ uid, balance: bal });
      if (!dryRun) {
        await db.collection('ledger_exceptions').doc(`float_neg_migrate:${uid}`).set({
          type: 'float_negative_migration_blocked',
          driverUid: uid,
          balance: bal,
          detectedAt: admin.firestore.FieldValue.serverTimestamp(),
          resolved: false,
        }, { merge: true });
      }
      continue;
    }
    if (bal === 0) {
      skippedZero.push({ uid });
      continue;
    }
    if (dryRun) {
      migrated.push({ uid, balance: bal, dryRun: true });
      continue;
    }
    const floatAcc = settlementLedger.driverFloatAccount(uid);
    const pcAcc = settlementLedger.passengerCreditAccount(uid);
    await settlementLedger.postEntry(db, {
      idempotencyKey: `floatToWallet:${uid}`,
      kind: 'float_to_wallet_migration',
      refType: 'migration',
      refId: uid,
      postedBy: callerUid,
      postedRole: 'finance',
      legs: [
        { account: floatAcc, dr: bal },
        { account: pcAcc, cr: bal },
      ],
    }, {
      mirrorBonus: true,
      walletLedgerType: 'float_to_wallet_migration',
      meta: { uid, amount: bal },
    });
    migrated.push({ uid, balance: bal });
  }

  return {
    ok: true,
    dryRun,
    migratedCount: migrated.length,
    migrated,
    skippedNegative,
    skippedZeroCount: skippedZero.length,
  };
});

exports.driverFloatStatus = functions.https.onCall(async (data, context) => {
  await requireCallerRoles(
      context,
      ['admin', 'superadmin', 'finance', 'auditor'],
      'Finance/audit role required',
  );
  const driverUid = canonicalUid(data && (data.driverUid || data.driverPhone));
  if (!driverUid || driverUid.length < 12) {
    throw new functions.https.HttpsError('invalid-argument', 'driverUid noto\'g\'ri');
  }
  return floatStatusOf(driverUid);
});

// ─────────────────────────────────────────────────────────────────────
// Settlement Ledger — Trip settlement (Qadam 3).
//   openSettlement    — haydovchi Pending settlement yaratadi (pul ko'chmaydi)
//   confirmSettlement — yo'lovchi tasdiqlaydi → Dr driver_float / Cr
//                       passenger_credit ATOMAR post + state 'completed'
//   cancelSettlement  — yo'lovchi/haydovchi/admin bekor qiladi (Pending → Cancelled)
//
// Faqat IDENTIFIKATSIYALANGAN foydalanuvchilar (users hujjati mavjud).
// Online: float manfiyga tushmaydi (assert). To'liq dizayn:
// docs/settlement_ledger_v1_uz.md (5–7 bo'lim)
// ─────────────────────────────────────────────────────────────────────

/** Auth token'dan chaqiruvchi uid (998 + 9). */
function requireCallerUid(context) {
  if (!context || !context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }
  const uid = canonicalUid(callerPhone(context));
  if (!uid || uid.length < 12) {
    throw new functions.https.HttpsError('unauthenticated', 'Phone token required');
  }
  return uid;
}

/** Identifikatsiyalangan = `users/{uid}` hujjati mavjud. */
async function isIdentifiedUser(uid) {
  const doc = await db.collection('users').doc(uid).get();
  return doc.exists;
}

/** Payout KYC — admin tasdiqlangan yoki to'liq profil (V1 fallback). */
function payoutKycOk(userData) {
  if (!userData || typeof userData !== 'object') return false;
  if (userData.payoutKycVerified === true) return true;
  const name = String(userData.name || '').trim();
  const birthDate = userData.birthDate;
  return name.length >= 2 && birthDate != null && String(birthDate).length >= 4;
}

/**
 * Mahalliy taksi — haydovchi safarni yakunlaydi, yo'lovchi hamyon intent'i bo'yicha
 * qisman/to'liq yechiladi, qaytim miqdori qaytariladi (settlement alohida).
 */
exports.completeLocalTrip = functions.https.onCall(async (data, context) => {
  const driverUid = requireCallerUid(context);
  const tripId = String((data && data.tripId) || '').trim();
  const clientFare = Math.trunc(Number((data && data.fare) || 0));
  const cashPaid = Math.trunc(Number((data && data.cashPaid) || 0));

  if (!tripId) {
    throw new functions.https.HttpsError('invalid-argument', 'tripId kerak');
  }
  if (!Number.isInteger(cashPaid) || cashPaid < 0) {
    throw new functions.https.HttpsError('invalid-argument', 'cashPaid >= 0 bo\'lsin');
  }

  const idemRef = db.collection('wallet_idempotency').doc(`local_trip_complete_${tripId}`);
  const existing = await idemRef.get();
  if (existing.exists) {
    return existing.data().result || { ok: true, duplicate: true };
  }

  const tripRef = db.collection('trips').doc(tripId);
  let resultPayload;

  await db.runTransaction(async (t) => {
    const idemSnap = await t.get(idemRef);
    if (idemSnap.exists) {
      resultPayload = idemSnap.data().result;
      return;
    }

    const tripSnap = await t.get(tripRef);
    if (!tripSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Trip topilmadi');
    }
    const trip = tripSnap.data() || {};
    if (trip.taxiType !== 'local' && trip.taxiType !== 'alone') {
      throw new functions.https.HttpsError(
          'failed-precondition', 'Faqat mahalliy taksi');
    }
    if (trip.status === 'completed') {
      resultPayload = {
        ok: true,
        idempotent: true,
        fare: Math.trunc(Number(trip.fare || 0)),
        cashPaid: Math.trunc(Number(trip.cashPaid || 0)),
        walletPaid: Math.trunc(Number(trip.walletPaid || 0)),
        change: Math.max(
            0,
            Math.trunc(Number(trip.cashPaid || 0))
            - Math.max(0, Math.trunc(Number(trip.fare || 0))
                - Math.trunc(Number(trip.walletPaid || 0))),
        ),
      };
      t.set(idemRef, {
        type: 'completeLocalTrip',
        result: resultPayload,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }
    if (trip.status !== 'accepted') {
      throw new functions.https.HttpsError(
          'failed-precondition', `Trip holati: ${trip.status}`);
    }
    const assignedDriver = String(
        trip.acceptedDriverId || trip.driverId || '').trim();
    if (assignedDriver !== driverUid) {
      throw new functions.https.HttpsError(
          'permission-denied', 'Bu safar sizga biriktirilmagan');
    }

    // Asosiy qoida: destination bo'yicha qulflangan yo'lkira.
    const lockedFare = Math.trunc(Number(trip.lockedFare || 0));
    const fare = lockedFare > 0 ? lockedFare : clientFare;
    if (!Number.isInteger(fare) || fare <= 0) {
      throw new functions.https.HttpsError(
          'invalid-argument',
          lockedFare > 0
            ? 'lockedFare noto\'g\'ri'
            : 'Avval manzilni belgilab yo\'lkirani qulflang yoki fare yuboring');
    }

    const passengerUid = canonicalUid(trip.userPhone || '');
    const walletIntent = Math.max(
        0, Math.trunc(Number(trip.passengerWalletIntent || 0)));
    let walletPaid = 0;

    if (walletIntent > 0 && passengerUid.length >= 12) {
      const userRef = db.collection('users').doc(passengerUid);
      const userSnap = await t.get(userRef);
      if (!userSnap.exists) {
        throw new functions.https.HttpsError(
            'failed-precondition', 'Yo\'lovchi identifikatsiyadan o\'tmagan');
      }
      const balance = Math.trunc(
          Number((userSnap.data() || {}).bonusBalance || 0));
      walletPaid = Math.min(walletIntent, fare, balance);
      if (walletPaid > 0) {
        const idempotencyKey = `trip_wallet_${tripId}`;
        const bonusCtx = await settlementLedger.prepareBonusInTx(
            t, db, passengerUid, { idempotencyKey });
        const nextBal = balance - walletPaid;
        t.set(userRef, {
          bonusBalance: nextBal,
          balanceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        const ledgerId = userRef.collection('wallet_ledger').doc().id;
        t.set(userRef.collection('wallet_ledger').doc(ledgerId), {
          type: 'local_taxi_debit',
          amount: -walletPaid,
          module: 'local_taxi',
          refType: 'trip',
          refId: tripId,
          meta: { driverUid },
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          createdBy: 'completeLocalTrip',
        });
        settlementLedger.commitBonusInTx(t, bonusCtx, {
          delta: -walletPaid,
          kind: 'local_taxi_debit',
          refType: 'trip',
          refId: tripId,
          meta: { module: 'local_taxi', driverUid },
          postedBy: driverUid,
          postedRole: 'driver',
        });
      }
    }

    const cashDue = Math.max(0, fare - walletPaid);
    const change = Math.max(0, cashPaid - cashDue);

    t.update(tripRef, {
      status: 'completed',
      fare,
      cashPaid,
      walletPaid,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (assignedDriver) {
      t.set(
          db.collection('drivers').doc(assignedDriver),
          {
            isBusy: false,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
      );
    }

    resultPayload = {
      ok: true,
      fare,
      cashPaid,
      walletPaid,
      cashDue,
      change,
    };
    t.set(idemRef, {
      type: 'completeLocalTrip',
      result: resultPayload,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  try {
    const tripSnap = await tripRef.get();
    const phone = (tripSnap.data() || {}).userPhone || '';
    await resetLocalTaxiCancelBlock(phone);
  } catch (e) {
    console.error('resetLocalTaxiCancelBlock failed:', e);
  }

  return resultPayload || { ok: true };
});

exports.openSettlement = functions.https.onCall(async (data, context) => {
  const driverUid = requireCallerUid(context);
  const passengerUid = canonicalUid(data && (data.passengerUid || data.passengerPhone));
  const tripId = String((data && data.tripId) || '').trim();
  const opId = String((data && data.opId) || '').trim();
  const totalChange = Math.trunc(Number((data && data.totalChange) || 0));
  const cashGiven = Math.trunc(Number((data && data.cashGiven) || 0));
  const settlementAmount = totalChange - cashGiven;

  if (!passengerUid || passengerUid.length < 12) {
    throw new functions.https.HttpsError('invalid-argument', 'passengerUid noto\'g\'ri');
  }
  if (passengerUid === driverUid) {
    throw new functions.https.HttpsError('invalid-argument', 'driver == passenger');
  }
  if (!tripId) {
    throw new functions.https.HttpsError('invalid-argument', 'tripId kerak');
  }
  if (!opId || opId.length < 6) {
    throw new functions.https.HttpsError('invalid-argument', 'opId (idempotency key) kerak');
  }
  if (!Number.isInteger(totalChange) || totalChange <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'totalChange musbat bo\'lsin');
  }
  if (!Number.isInteger(cashGiven) || cashGiven < 0) {
    throw new functions.https.HttpsError('invalid-argument', 'cashGiven >= 0 bo\'lsin');
  }
  if (!Number.isInteger(settlementAmount) || settlementAmount <= 0) {
    throw new functions.https.HttpsError(
        'invalid-argument', 'settlementAmount musbat bo\'lsin (cashGiven < totalChange)');
  }

  if (!(await isIdentifiedUser(driverUid))) {
    throw new functions.https.HttpsError(
        'failed-precondition', 'Haydovchi identifikatsiyadan o\'tmagan');
  }
  if (!(await isIdentifiedUser(passengerUid))) {
    throw new functions.https.HttpsError(
        'failed-precondition', 'Yo\'lovchi identifikatsiyadan o\'tmagan');
  }

  // Qaytim haydovchi HAMYONIDAN (passenger_credit) — manfiy taqiqlangan.
  const driverUser = await db.collection('users').doc(driverUid).get();
  const walletBalance = driverUser.exists
      ? (parseInt(String((driverUser.data() || {}).bonusBalance ?? 0), 10) || 0)
      : 0;
  if (walletBalance < settlementAmount) {
    throw new functions.https.HttpsError(
        'failed-precondition',
        'Hamyon yetarli emas — qolganini naqd qaytaring yoki Cash Exchange qiling');
  }

  const ref = db.collection(settlementLedger.COL_SETTLEMENTS).doc(opId);
  const tripRef = db.collection('trips').doc(tripId);
  const bookingRef = db.collection('intercity_bookings').doc(tripId);
  const created = await db.runTransaction(async (tx) => {
    const ex = await tx.get(ref);
    if (ex.exists) return false; // idempotent
    const [tripSnap, bookSnap] = await Promise.all([
      tx.get(tripRef), tx.get(bookingRef),
    ]);
    tx.set(ref, {
      tripId,
      driverUid,
      passengerUid,
      totalChange,
      cashGiven,
      settlementAmount,
      state: 'pending',
      createdBy: driverUid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      journalEntryId: '',
    });
    const hostPatch = {
      settlementId: opId,
      settlementState: 'pending',
      settlementAmount,
    };
    if (tripSnap.exists) {
      tx.set(tripRef, hostPatch, { merge: true });
    } else if (bookSnap.exists) {
      tx.set(bookingRef, hostPatch, { merge: true });
    }
    return true;
  });

  return {
    ok: true,
    idempotent: !created,
    settlementId: opId,
    state: 'pending',
    settlementAmount,
    walletBalance,
  };
});

exports.confirmSettlement = functions.https.onCall(async (data, context) => {
  const callerUid = requireCallerUid(context);
  const settlementId = String((data && data.settlementId) || '').trim();
  if (!settlementId) {
    throw new functions.https.HttpsError('invalid-argument', 'settlementId kerak');
  }

  const sref = db.collection(settlementLedger.COL_SETTLEMENTS).doc(settlementId);
  const snap = await sref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'Settlement topilmadi');
  }
  const s = snap.data() || {};
  if (s.passengerUid !== callerUid) {
    throw new functions.https.HttpsError(
        'permission-denied', 'Faqat yo\'lovchi tasdiqlay oladi');
  }
  if (s.state !== 'pending') {
    throw new functions.https.HttpsError(
        'failed-precondition', `Settlement holati: ${s.state} (pending kerak)`);
  }
  const amount = Math.trunc(Number(s.settlementAmount || 0));
  if (!Number.isInteger(amount) || amount <= 0) {
    throw new functions.https.HttpsError('failed-precondition', 'settlementAmount noto\'g\'ri');
  }

  // Haydovchi hamyonidan → yo'lovchi hamyoniga (ikkala passenger_credit).
  const driverPc = settlementLedger.passengerCreditAccount(s.driverUid);
  const passPc = settlementLedger.passengerCreditAccount(s.passengerUid);
  const res = await settlementLedger.postEntry(db, {
    idempotencyKey: `settle:${settlementId}`,
    kind: 'trip_settlement',
    refType: 'settlement',
    refId: settlementId,
    postedBy: callerUid,
    postedRole: 'passenger',
    legs: [
      { account: driverPc, dr: amount },
      { account: passPc, cr: amount },
    ],
  }, {
    mirrorBonus: true,
    meta: { tripId: s.tripId, settlementId, driverUid: s.driverUid },
    precheck: async (tx) => {
      const fresh = await tx.get(sref);
      const fd = fresh.exists ? (fresh.data() || {}) : {};
      if (!fresh.exists || fd.state !== 'pending') {
        throw new functions.https.HttpsError(
            'failed-precondition', 'Settlement endi pending emas');
      }
      let hostPatchRef = null;
      if (fd.tripId) {
        const tripRef = db.collection('trips').doc(fd.tripId);
        const bookingRef = db.collection('intercity_bookings').doc(fd.tripId);
        const [tripSnap, bookSnap] = await Promise.all([
          tx.get(tripRef), tx.get(bookingRef),
        ]);
        if (tripSnap.exists) hostPatchRef = tripRef;
        else if (bookSnap.exists) hostPatchRef = bookingRef;
      }
      return { fd, hostPatchRef };
    },
    assert: ({ accounts }) => {
      const da = accounts.get(driverPc);
      if (da && da.next < 0) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            'Haydovchi hamyoni yetarli emas (manfiy taqiqlangan)');
      }
    },
    onCommit: (tx, { entryId, pre }) => {
      tx.update(sref, {
        state: 'completed',
        confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        journalEntryId: entryId,
      });
      const hostPatchRef = pre && pre.hostPatchRef;
      if (hostPatchRef) {
        tx.set(hostPatchRef, { settlementState: 'completed' }, { merge: true });
      }
      const passRef = db.collection('users').doc(s.passengerUid);
      const drvRef = db.collection('users').doc(s.driverUid);
      tx.set(passRef.collection('wallet_ledger').doc(), {
        type: 'settlement_credit',
        amount,
        module: 'taxi',
        refType: 'settlement',
        refId: settlementId,
        meta: { tripId: s.tripId, driverUid: s.driverUid },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: 'confirmSettlement',
      });
      tx.set(drvRef.collection('wallet_ledger').doc(), {
        type: 'settlement_debit',
        amount: -amount,
        module: 'taxi',
        refType: 'settlement',
        refId: settlementId,
        meta: { tripId: s.tripId, passengerUid: s.passengerUid },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: 'confirmSettlement',
      });
    },
  });

  return {
    ok: true,
    idempotent: res.idempotent,
    settlementId,
    state: 'completed',
    amount,
  };
});

exports.cancelSettlement = functions.https.onCall(async (data, context) => {
  const callerUid = requireCallerUid(context);
  const settlementId = String((data && data.settlementId) || '').trim();
  const reason = String((data && data.reason) || '').slice(0, 200);
  if (!settlementId) {
    throw new functions.https.HttpsError('invalid-argument', 'settlementId kerak');
  }

  const sref = db.collection(settlementLedger.COL_SETTLEMENTS).doc(settlementId);
  const callerRoleDoc = await db.collection('users').doc(callerUid).get();
  const callerRole = (callerRoleDoc.data() || {}).role || 'user';
  const isAdminCaller = ['admin', 'superadmin', 'finance'].includes(callerRole);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(sref);
    if (!snap.exists) {
      throw new functions.https.HttpsError('not-found', 'Settlement topilmadi');
    }
    const s = snap.data() || {};
    if (!isAdminCaller
        && s.passengerUid !== callerUid
        && s.driverUid !== callerUid) {
      throw new functions.https.HttpsError(
          'permission-denied', 'Faqat tomonlar yoki admin bekor qiladi');
    }
    if (s.state !== 'pending') {
      throw new functions.https.HttpsError(
          'failed-precondition', `Settlement holati: ${s.state} (pending kerak)`);
    }
    tx.update(sref, {
      state: 'cancelled',
      cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      cancelledBy: callerUid,
      cancelReason: reason,
    });
    if (s.tripId) {
      const tripRef = db.collection('trips').doc(s.tripId);
      const bookingRef = db.collection('intercity_bookings').doc(s.tripId);
      const [tripSnap, bookSnap] = await Promise.all([
        tx.get(tripRef), tx.get(bookingRef),
      ]);
      const hostPatch = { settlementState: 'cancelled' };
      if (tripSnap.exists) {
        tx.set(tripRef, hostPatch, { merge: true });
      } else if (bookSnap.exists) {
        tx.set(bookingRef, hostPatch, { merge: true });
      }
    }
  });

  return { ok: true, settlementId, state: 'cancelled' };
});

// ─────────────────────────────────────────────────────────────────────
// Settlement Ledger — Deferred (offline-lite, Qadam 4).
//   submitDeferredSettlement — haydovchi internet qaytgach, naqd qaytara
//     olmagan qaytimni post qiladi. Float MANFIYGA tushishi mumkin (qarz),
//     ammo FAQAT headroom ichida: floor = -(oxirgi depozit %i). Floordan
//     oshsa → rad (naqd/top-up shart). Float < 0 bo'lsa → haydovchi BLOK
//     (yangi trip yo'q) + reconcile taymeri (deferredTimeoutHours).
//   settlementDeferredWatch — muddati o'tgan manfiy floatlarni
//     ledger_exceptions ga belgilaydi (finance ko'rishi uchun).
//
// Faqat IDENTIFIKATSIYALANGAN tomonlar. Yo'lovchi onlayn tasdiqlay olmagani
// uchun haydovchi ATTESTATSIYA qiladi (V1, ishonchli kontur).
// To'liq dizayn: docs/settlement_ledger_v1_uz.md (7-bo'lim)
// ─────────────────────────────────────────────────────────────────────
exports.submitDeferredSettlement = functions.https.onCall(async (data, context) => {
  const driverUid = requireCallerUid(context);
  const passengerUid = canonicalUid(data && (data.passengerUid || data.passengerPhone));
  const tripId = String((data && data.tripId) || '').trim();
  const opId = String((data && data.opId) || '').trim();
  const settlementAmount = Math.trunc(Number((data && data.settlementAmount) || 0));

  if (!passengerUid || passengerUid.length < 12) {
    throw new functions.https.HttpsError('invalid-argument', 'passengerUid noto\'g\'ri');
  }
  if (passengerUid === driverUid) {
    throw new functions.https.HttpsError('invalid-argument', 'driver == passenger');
  }
  if (!tripId) {
    throw new functions.https.HttpsError('invalid-argument', 'tripId kerak');
  }
  if (!opId || opId.length < 6) {
    throw new functions.https.HttpsError('invalid-argument', 'opId (idempotency key) kerak');
  }
  if (!Number.isInteger(settlementAmount) || settlementAmount <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'settlementAmount musbat bo\'lsin');
  }
  if (!(await isIdentifiedUser(driverUid))) {
    throw new functions.https.HttpsError(
        'failed-precondition', 'Haydovchi identifikatsiyadan o\'tmagan');
  }
  if (!(await isIdentifiedUser(passengerUid))) {
    throw new functions.https.HttpsError(
        'failed-precondition', 'Yo\'lovchi identifikatsiyadan o\'tmagan');
  }

  // Deferred ham hamyondan — manfiy taqiqlangan (float headroom yo'q).
  const driverUser = await db.collection('users').doc(driverUid).get();
  const walletBalance = driverUser.exists
      ? (parseInt(String((driverUser.data() || {}).bonusBalance ?? 0), 10) || 0)
      : 0;
  if (walletBalance < settlementAmount) {
    throw new functions.https.HttpsError(
        'failed-precondition',
        'Hamyon yetarli emas — manfiy deferred taqiqlangan');
  }

  const sref = db.collection(settlementLedger.COL_SETTLEMENTS).doc(opId);
  const tripRef = db.collection('trips').doc(tripId);
  const bookingRef = db.collection('intercity_bookings').doc(tripId);
  const driverPc = settlementLedger.passengerCreditAccount(driverUid);
  const passPc = settlementLedger.passengerCreditAccount(passengerUid);

  let resultNext = 0;
  const res = await settlementLedger.postEntry(db, {
    idempotencyKey: `settle:${opId}`,
    kind: 'trip_settlement_deferred',
    refType: 'settlement',
    refId: opId,
    postedBy: driverUid,
    postedRole: 'driver',
    legs: [
      { account: driverPc, dr: settlementAmount },
      { account: passPc, cr: settlementAmount },
    ],
  }, {
    mirrorBonus: true,
    meta: { tripId, settlementId: opId, driverUid, deferred: true },
    precheck: async (tx) => {
      const [tripSnap, bookSnap] = await Promise.all([
        tx.get(tripRef), tx.get(bookingRef),
      ]);
      let hostPatchRef = null;
      if (tripSnap.exists) hostPatchRef = tripRef;
      else if (bookSnap.exists) hostPatchRef = bookingRef;
      return { hostPatchRef };
    },
    assert: ({ accounts }) => {
      const da = accounts.get(driverPc);
      if (da && da.next < 0) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            'Hamyon yetarli emas (manfiy taqiqlangan)');
      }
    },
    onCommit: (tx, { entryId, balances, pre }) => {
      resultNext = balances[driverPc] || 0;
      tx.set(sref, {
        tripId,
        driverUid,
        passengerUid,
        totalChange: settlementAmount,
        cashGiven: 0,
        settlementAmount,
        state: 'completed',
        origin: 'deferred',
        attestedBy: 'driver',
        createdBy: driverUid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        journalEntryId: entryId,
      }, { merge: true });
      const hostPatchRef = pre && pre.hostPatchRef;
      if (hostPatchRef) {
        tx.set(hostPatchRef, {
          settlementId: opId,
          settlementState: 'completed',
          settlementAmount,
        }, { merge: true });
      }
      tx.set(db.collection('users').doc(driverUid),
          { settlementBlocked: false }, { merge: true });
      tx.set(db.collection('users').doc(passengerUid).collection('wallet_ledger').doc(), {
        type: 'settlement_credit',
        amount: settlementAmount,
        module: 'taxi',
        refType: 'settlement',
        refId: opId,
        meta: { tripId, driverUid, deferred: true },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: 'submitDeferredSettlement',
      });
      tx.set(db.collection('users').doc(driverUid).collection('wallet_ledger').doc(), {
        type: 'settlement_debit',
        amount: -settlementAmount,
        module: 'taxi',
        refType: 'settlement',
        refId: opId,
        meta: { tripId, passengerUid, deferred: true },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: 'submitDeferredSettlement',
      });
    },
  });

  return {
    ok: true,
    idempotent: res.idempotent,
    settlementId: opId,
    state: 'completed',
    amount: settlementAmount,
    walletBalance: res.idempotent ? walletBalance : resultNext,
    blocked: false,
  };
});

// Muddati o'tgan deferred qarzlarni (manfiy float) belgilaydi — finance ko'rishi uchun.
exports.settlementDeferredWatch = functions.pubsub
    .schedule('every 6 hours')
    .timeZone('Asia/Tashkent')
    .onRun(async () => {
      const now = Date.now();
      const snap = await db.collection(settlementLedger.COL_ACCOUNTS)
          .where('blocked', '==', true)
          .get();
      const batch = db.batch();
      let n = 0;
      snap.forEach((d) => {
        const a = d.data() || {};
        if (!d.id.startsWith('driver_float:')) return;
        const to = a.deferredTimeoutAt && a.deferredTimeoutAt.toMillis
            ? a.deferredTimeoutAt.toMillis() : null;
        if ((a.balance || 0) < 0 && to && to <= now) {
          const uid = a.ownerUid || d.id.split(':').slice(1).join(':');
          batch.set(db.collection('ledger_exceptions').doc(`deferred_timeout:${uid}`), {
            type: 'deferred_timeout',
            driverUid: uid,
            balance: a.balance || 0,
            deferredTimeoutAt: a.deferredTimeoutAt,
            detectedAt: admin.firestore.FieldValue.serverTimestamp(),
            resolved: false,
          }, { merge: true });
          n++;
        }
      });
      if (n > 0) await batch.commit();
      console.log(`settlementDeferredWatch: ${n} timed-out deferred debt(s)`);
      return null;
    });

// ═══════════════════════════════════════════════════════════════════════════
// TANISHUV / TURMUSH O'RTOG'I IZLASH (Dating)
// ═══════════════════════════════════════════════════════════════════════════

function datingCallerUid(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }
  const uid = canonicalUid(callerPhone(context));
  if (!uid || uid.length < 12) {
    throw new functions.https.HttpsError('unauthenticated', 'Phone token required');
  }
  return uid;
}

function datingMatchId(a, b) {
  return [a, b].sort().join('__');
}

/** Foydalanuvchi dating profilini saqlash → status pending (admin tasdiqlaydi). */
exports.saveDatingProfile = functions.https.onCall(async (data, context) => {
  const uid = datingCallerUid(context);
  const gender = String(data.gender || '');
  if (!['male', 'female'].includes(gender)) {
    throw new functions.https.HttpsError('invalid-argument', 'gender male/female');
  }
  const displayName = String(data.displayName || '').trim().slice(0, 60);
  if (displayName.length < 2) {
    throw new functions.https.HttpsError('invalid-argument', 'displayName required');
  }
  const birthYear = parseInt(String(data.birthYear ?? 0), 10);
  const nowYear = new Date().getFullYear();
  if (!Number.isFinite(birthYear) ||
      birthYear < nowYear - 80 || birthYear > nowYear - 18) {
    throw new functions.https.HttpsError('invalid-argument', '18+ va realistik yosh');
  }
  const photosIn = Array.isArray(data.photos) ? data.photos : [];
  const photos = photosIn
    .filter((p) => p && typeof p.url === 'string')
    .slice(0, 6)
    .map((p) => ({ url: String(p.url), path: String(p.path || '') }));
  if (photos.length === 0) {
    throw new functions.https.HttpsError('invalid-argument', 'Kamida 1 ta real foto');
  }

  const myAge = nowYear - birthYear;
  const ref = db.collection('dating_profiles').doc(uid);
  const prev = await ref.get();
  const prevData = prev.data() || {};
  const autoApprove = await isDatingAutoApproveEnabled();
  const status = autoApprove ? 'approved' : 'pending';
  const defaultPrefMin = Math.max(18, myAge - 15);
  const defaultPrefMax = Math.min(80, myAge + 15);
  await ref.set({
    userId: uid,
    displayName,
    gender,
    birthYear,
    about: String(data.about || '').trim().slice(0, 1000),
    city: String(data.city || '').trim().slice(0, 80),
    maritalStatus: String(data.maritalStatus || '').slice(0, 20),
    education: String(data.education || '').trim().slice(0, 120),
    job: String(data.job || '').trim().slice(0, 120),
    photos,
    status,
    rejectionReason: '',
    ...(autoApprove
      ? {
        moderatedBy: 'auto',
        moderatedAt: admin.firestore.FieldValue.serverTimestamp(),
        autoApproved: true,
      }
      : {}),
    active: prev.exists ? (prev.data().active !== false) : true,
    prefMinAge: prev.exists
      ? (Number(prevData.prefMinAge) || defaultPrefMin)
      : defaultPrefMin,
    prefMaxAge: prev.exists
      ? (Number(prevData.prefMaxAge) || defaultPrefMax)
      : defaultPrefMax,
    lastActive: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...(prev.exists
      ? {}
      : { createdAt: admin.firestore.FieldValue.serverTimestamp() }),
  }, { merge: true });
  return { ok: true, status };
});

/** Dating profilni faollashtirish/pauza (statusga tegmaydi). */
exports.setDatingActive = functions.https.onCall(async (data, context) => {
  const uid = datingCallerUid(context);
  const active = data.active === true;
  const ref = db.collection('dating_profiles').doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'Profil yoq');
  }
  await ref.set({
    active,
    lastActive: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, active };
});

/** Tavsiya ёш oralig‘i (18–80, foydalanuvchi tanlaydi). */
exports.setDatingAgePreference = functions.https.onCall(async (data, context) => {
  const uid = datingCallerUid(context);
  const minAge = parseInt(String(data.minAge ?? 0), 10);
  const maxAge = parseInt(String(data.maxAge ?? 0), 10);
  if (!Number.isFinite(minAge) || !Number.isFinite(maxAge)) {
    throw new functions.https.HttpsError('invalid-argument', 'yosh notogri');
  }
  const lo = Math.min(minAge, maxAge);
  const hi = Math.max(minAge, maxAge);
  if (lo < 18 || hi > 80) {
    throw new functions.https.HttpsError(
      'invalid-argument', 'yosh oralig\'i 18–80 oralig\'ida bo\'lishi kerak');
  }
  const ref = db.collection('dating_profiles').doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'Profil yoq');
  }
  await ref.set({
    prefMinAge: lo,
    prefMaxAge: hi,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, prefMinAge: lo, prefMaxAge: hi };
});

async function deleteDatingSubcollection(parentRef, subName) {
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await parentRef.collection(subName).limit(400).get();
    if (snap.empty) break;
    const stats = {};
    await batchDeleteDocs(snap.docs, stats, 'n');
    if (snap.size < 400) break;
  }
}

async function deleteDatingQueryDocs(buildQuery) {
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await buildQuery();
    if (snap.empty) break;
    const stats = {};
    await batchDeleteDocs(snap.docs, stats, 'n');
    if (snap.size < 400) break;
  }
}

async function deleteDatingStorageForUser(uid, photos) {
  const bucket = admin.storage().bucket();
  const paths = new Set();
  for (const p of photos || []) {
    const path = String((p || {}).path || '').trim();
    if (path) paths.add(path);
  }
  for (const path of paths) {
    try {
      await bucket.file(path).delete();
    } catch (_) { /* noop */ }
  }
  try {
    const [files] = await bucket.getFiles({ prefix: `dating/${uid}/` });
    await Promise.all(files.map((f) => f.delete().catch(() => {})));
  } catch (e) {
    console.error('deleteDatingStorageForUser:', e.message || e);
  }
}

/** Foydalanuvchi o'z tanishuv profilini butunlay o'chiradi. */
exports.deleteDatingProfile = functions.https.onCall(async (data, context) => {
  const uid = datingCallerUid(context);
  const ref = db.collection('dating_profiles').doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    return { ok: true, alreadyDeleted: true };
  }
  const profile = snap.data() || {};

  await deleteDatingStorageForUser(uid, profile.photos);

  await deleteDatingQueryDocs(() => db.collection('dating_interests')
    .where('fromId', '==', uid).limit(400).get());
  await deleteDatingQueryDocs(() => db.collection('dating_interests')
    .where('toId', '==', uid).limit(400).get());

  // eslint-disable-next-line no-constant-condition
  while (true) {
    const matchSnap = await db.collection('dating_matches')
      .where('users', 'array-contains', uid)
      .limit(40)
      .get();
    if (matchSnap.empty) break;
    for (const mdoc of matchSnap.docs) {
      await deleteDatingSubcollection(mdoc.ref, 'messages');
      await mdoc.ref.delete();
    }
  }

  const blockList = db.collection('dating_blocks').doc(uid).collection('list');
  await deleteDatingQueryDocs(() => blockList.limit(400).get());
  try {
    await db.collection('dating_blocks').doc(uid).delete();
  } catch (_) { /* noop */ }

  await ref.delete();
  return { ok: true };
});

/** Admin: dating profil moderatsiyasi (approve/reject/block). */
exports.adminModerateDatingProfile =
  functions.https.onCall(async (data, context) => {
    const adminUid = await requireCallerRoles(
      context, ['admin', 'superadmin', 'dispatcher'], 'Admin role required');
    const userId = canonicalUid(String(data.userId || ''));
    const action = String(data.action || '');
    if (!['approve', 'reject', 'block'].includes(action)) {
      throw new functions.https.HttpsError('invalid-argument', 'bad action');
    }
    const reason = String(data.reason || '').slice(0, 300);
    const statusMap = { approve: 'approved', reject: 'rejected', block: 'blocked' };
    const ref = db.collection('dating_profiles').doc(userId);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new functions.https.HttpsError('not-found', 'Profil topilmadi');
    }
    await ref.set({
      status: statusMap[action],
      rejectionReason: action === 'approve' ? '' : reason,
      moderatedBy: adminUid,
      moderatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(action === 'block' ? { active: false } : {}),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ok: true, status: statusMap[action] };
  });

/** Admin: tanishuv profillarini avtomatik tasdiqlash rejimi. */
exports.adminSetDatingAutoApprove = functions.https.onCall(async (data, context) => {
  await assertAdmin(String(data.adminPhone || ''), context);
  const enabled = data.enabled === true;
  await db.collection('settings').doc('app').set({
    datingAutoApprove: enabled,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, enabled };
});

/** Admin: Onlayn BOZOR эълонларини авто фаоллаштириш. */
exports.adminSetMarketAutoApprove = functions.https.onCall(async (data, context) => {
  await assertAdmin(String(data.adminPhone || ''), context);
  const enabled = data.enabled === true;
  await db.collection('settings').doc('app').set({
    marketAutoApprove: enabled,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, enabled };
});

/** Admin: ИШ ЭЪЛОН — авто / қўлда тасдиқлаш. */
exports.adminSetJobsAutoApprove = functions.https.onCall(async (data, context) => {
  await assertAdmin(String(data.adminPhone || ''), context);
  const enabled = data.enabled === true;
  await db.collection('settings').doc('app').set({
    jobsAutoApprove: enabled,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, enabled };
});

/** Admin: «Тавсия этамиз» витринаси — АВТО (барча фаол) / ҚЎЛДА (featuredOnHome). */
exports.adminSetPlatformFeaturedAuto = functions.https.onCall(async (data, context) => {
  await assertAdmin(String(data.adminPhone || ''), context);
  const enabled = data.enabled === true;
  await db.collection('settings').doc('app').set({
    platformFeaturedAuto: enabled,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, enabled };
});

/** AVA дўкони етказиб бериш ҳақи % — `settings/app.platformDeliveryFeePercent`. */
exports.adminSetPlatformDeliveryFeePercent = functions.https.onCall(async (data, context) => {
  await assertAdmin(String(data.adminPhone || ''), context);
  let pct = Number(data.percent);
  if (!Number.isFinite(pct) || pct < 0 || pct > 100) {
    throw new functions.https.HttpsError(
        'invalid-argument', 'percent 0..100 бўлиши керак');
  }
  pct = Math.round(pct * 100) / 100;
  await db.collection('settings').doc('app').set({
    platformDeliveryFeePercent: pct,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, percent: pct };
});

// ══════════════════════════════════════
// GLOBAL SEARCH INDEX (`search_index`)
// ══════════════════════════════════════

const SEARCH_INDEX_MAX_TOKENS = 64;

function searchIndexDocId(type, sourceId) {
  const sid = String(sourceId || '').trim().replace(/[/\\]/g, '_');
  return `${type}_${sid}`.slice(0, 700);
}

function buildSearchIndexTokens(...parts) {
  const text = parts.filter(Boolean).join(' ').toLowerCase();
  const words = text.split(/[^0-9a-zа-яёўқғҳʻʼ']+/i).filter(
    (w) => w && w.length >= 2,
  );
  const out = new Set();
  for (const w of words) {
    out.add(w);
    const latin = marketToLatin(w);
    const cyrl = marketToCyrillic(w);
    if (latin.length >= 2) out.add(latin);
    if (cyrl.length >= 2) out.add(cyrl);
    if (out.size >= SEARCH_INDEX_MAX_TOKENS) break;
  }
  return Array.from(out).slice(0, SEARCH_INDEX_MAX_TOKENS);
}

async function upsertSearchIndexEntry(entry) {
  const type = String(entry.type || '').trim();
  const sourceId = String(entry.sourceId || '').trim();
  if (!type || !sourceId) return;
  const id = searchIndexDocId(type, sourceId);
  const keywords = Array.isArray(entry.keywords)
    ? entry.keywords.map((k) => String(k || '').trim().toLowerCase()).filter(Boolean).slice(0, 48)
    : [];
  const tokens = Array.isArray(entry.searchTokens) && entry.searchTokens.length
    ? entry.searchTokens.slice(0, SEARCH_INDEX_MAX_TOKENS)
    : buildSearchIndexTokens(
      entry.title, entry.subtitle, ...(keywords),
      entry.geo && entry.geo.from, entry.geo && entry.geo.to,
    );
  const payload = {
    type,
    moduleId: String(entry.moduleId || '').trim(),
    sourceCollection: String(entry.sourceCollection || '').trim(),
    sourceId,
    title: String(entry.title || '').trim().slice(0, 160),
    subtitle: String(entry.subtitle || '').trim().slice(0, 200),
    imageUrl: String(entry.imageUrl || '').trim(),
    iconKey: String(entry.iconKey || '').trim(),
    keywords,
    searchTokens: tokens,
    priorityBoost: Math.trunc(Number(entry.priorityBoost) || 0),
    active: entry.active !== false,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (entry.price != null && Number.isFinite(Number(entry.price))) {
    payload.price = Math.trunc(Number(entry.price));
  } else {
    payload.price = admin.firestore.FieldValue.delete();
  }
  if (entry.geo && typeof entry.geo === 'object') {
    const geo = {};
    if (entry.geo.from) geo.from = String(entry.geo.from).trim();
    if (entry.geo.to) geo.to = String(entry.geo.to).trim();
    if (entry.geo.districtId) geo.districtId = String(entry.geo.districtId).trim();
    if (Object.keys(geo).length) payload.geo = geo;
  }
  await db.collection('search_index').doc(id).set(payload, { merge: true });
}

async function deleteSearchIndexEntry(type, sourceId) {
  const id = searchIndexDocId(type, sourceId);
  await db.collection('search_index').doc(id).delete().catch(() => null);
}

function platformProductToSearchEntry(id, d) {
  const name = String(d.name || '').trim();
  const active = d.active !== false && name.length > 0;
  const urls = Array.isArray(d.imageUrls) ? d.imageUrls : [];
  const cover = String((urls[0] || d.imageUrl || '')).trim();
  const kind = String(d.goodsKind || '').trim();
  const keywords = ['ава', 'дукон', 'дўкон', 'ava', 'store', 'платформа'];
  if (kind === 'food') keywords.push('озиқ', 'oziq', 'food');
  if (kind === 'non_food') keywords.push('но-озиқ', 'non_food');
  return {
    type: 'platform_product',
    moduleId: 'platform',
    sourceCollection: 'platform_products',
    sourceId: id,
    title: name,
    subtitle: 'AVA дўкони',
    price: Math.trunc(Number(d.price) || 0),
    imageUrl: cover,
    iconKey: 'shop',
    keywords,
    priorityBoost: 0,
    active,
  };
}

function adToSearchEntry(id, d) {
  const adType = String(d.type || '').trim();
  const isMarket = adType === 'cheap_product';
  const isJob = ['work', 'service', 'ad'].includes(adType);
  if (!isMarket && !isJob) return null;
  const title = String(d.title || '').trim()
    || String(d.text || '').trim().slice(0, 80);
  const status = String(d.status || '');
  const active = status === 'active' && title.length > 0;
  const desc = String(d.description || d.text || '');
  const tokens = Array.isArray(d.searchTokens) && d.searchTokens.length
    ? d.searchTokens
    : buildSearchIndexTokens(title, desc);
  if (isMarket) {
    return {
      type: 'market_ad',
      moduleId: 'cheap_products_home',
      sourceCollection: 'ads',
      sourceId: id,
      title,
      subtitle: 'Онлайн бозор',
      price: Math.trunc(Number(d.price) || 0),
      imageUrl: Array.isArray(d.imageUrls) && d.imageUrls[0]
        ? String(d.imageUrls[0])
        : '',
      iconKey: 'shop',
      keywords: ['бозор', 'bozor', 'эълон', 'сотиш'],
      searchTokens: tokens,
      priorityBoost: 0,
      active,
    };
  }
  return {
    type: 'job',
    moduleId: 'jobs',
    sourceCollection: 'ads',
    sourceId: id,
    title,
    subtitle: 'ИШ ЭЪЛОН',
    imageUrl: '',
    iconKey: 'job',
    keywords: ['иш', 'ish', 'вакансия', 'эълон', adType],
    searchTokens: tokens,
    priorityBoost: 0,
    active,
  };
}

function breadImageUrl(d) {
  return String(
    d.imageUrl || d.imageURL || d.image_url || d.photoUrl || d.image || '',
  ).trim();
}

function breadProductToSearchEntry(id, d) {
  const name = String(d.name || '').trim();
  const typeRaw = String(d.type || '').trim();
  const keywords = ['нон', 'non', 'патир', 'чўрек', typeRaw];
  return {
    type: 'bread_product',
    moduleId: 'bread',
    sourceCollection: 'bread_products',
    sourceId: id,
    title: name,
    subtitle: 'Нон',
    price: Math.trunc(Number(d.price) || 0),
    imageUrl: breadImageUrl(d),
    iconKey: 'bread',
    keywords,
    priorityBoost: 4,
    active: name.length > 0,
  };
}

function foodProductToSearchEntry(id, d) {
  const name = String(d.name || '').trim();
  const category = String(d.category || '').trim();
  const keywords = ['овқат', 'ovqat', 'таом', 'кафе', category];
  return {
    type: 'food_product',
    moduleId: 'food',
    sourceCollection: 'food_catalog',
    sourceId: id,
    title: name,
    subtitle: category || 'Овқат',
    price: Math.trunc(Number(d.price) || 0),
    imageUrl: String(d.imageUrl || '').trim(),
    iconKey: 'food',
    keywords,
    priorityBoost: 4,
    active: name.length > 0,
  };
}

function yukExpiresMs(d) {
  const e = d.expiresAt;
  if (!e) return 0;
  if (typeof e.toMillis === 'function') return e.toMillis();
  if (e._seconds != null) return Number(e._seconds) * 1000;
  const parsed = Date.parse(String(e));
  return Number.isFinite(parsed) ? parsed : 0;
}

function yukListingToSearchEntry(id, d) {
  const from = String(d.from || '').trim();
  const to = String(d.to || '').trim();
  const status = String(d.status || '').trim();
  const cargo = String(d.cargo || '').trim();
  const vehicle = String(d.vehicleType || '').trim();
  const listingType = String(d.type || '').trim();
  const expiresMs = yukExpiresMs(d);
  const notExpired = !expiresMs || expiresMs > Date.now();
  const title = from && to
    ? `${from} → ${to}`
    : (cargo || vehicle || 'Юк эълони');
  const subtitle = listingType === 'truck'
    ? (vehicle || 'Юк машина')
    : (cargo || 'Юк');
  const stops = Array.isArray(d.stops) ? d.stops.map((s) => String(s || '')) : [];
  return {
    type: 'yuk_listing',
    moduleId: 'yuk_birja',
    sourceCollection: 'yuk_listings',
    sourceId: id,
    title,
    subtitle,
    price: Math.trunc(Number(d.price) || 0),
    imageUrl: '',
    iconKey: 'yuk',
    keywords: [
      'юк', 'yuk', 'биржа', listingType, vehicle, cargo, from, to, ...stops,
    ],
    geo: { from, to },
    priorityBoost: 6,
    active: status === 'active' && notExpired && title.length > 0,
  };
}

const {onDocumentWritten} = require('firebase-functions/v2/firestore');

exports.onSearchIndexPlatformProductWrite = onDocumentWritten(
  {
    document: 'platform_products/{id}',
    region: 'europe-west1',
  },
  async (event) => {
    const id = event.params.id;
    const after = event.data && event.data.after;
    if (!after || !after.exists) {
      await deleteSearchIndexEntry('platform_product', id);
      return;
    }
    const d = after.data() || {};
    await upsertSearchIndexEntry(platformProductToSearchEntry(id, d));
  },
);

exports.onSearchIndexAdWrite = onDocumentWritten(
  {
    document: 'ads/{adId}',
    region: 'europe-west1',
  },
  async (event) => {
    const id = event.params.adId;
    const after = event.data && event.data.after;
    if (!after || !after.exists) {
      await deleteSearchIndexEntry('market_ad', id);
      await deleteSearchIndexEntry('job', id);
      return;
    }
    const d = after.data() || {};
    const entry = adToSearchEntry(id, d);
    if (!entry) return;
    if (entry.type === 'market_ad') {
      await deleteSearchIndexEntry('job', id);
    } else {
      await deleteSearchIndexEntry('market_ad', id);
    }
    await upsertSearchIndexEntry(entry);
  },
);

exports.onSearchIndexBreadProductWrite = onDocumentWritten(
  {
    document: 'bread_products/{id}',
    region: 'europe-west1',
  },
  async (event) => {
    const id = event.params.id;
    const after = event.data && event.data.after;
    if (!after || !after.exists) {
      await deleteSearchIndexEntry('bread_product', id);
      return;
    }
    await upsertSearchIndexEntry(
      breadProductToSearchEntry(id, after.data() || {}),
    );
  },
);

exports.onSearchIndexFoodProductWrite = onDocumentWritten(
  {
    document: 'food_catalog/{id}',
    region: 'europe-west1',
  },
  async (event) => {
    const id = event.params.id;
    const after = event.data && event.data.after;
    if (!after || !after.exists) {
      await deleteSearchIndexEntry('food_product', id);
      return;
    }
    await upsertSearchIndexEntry(
      foodProductToSearchEntry(id, after.data() || {}),
    );
  },
);

exports.onSearchIndexYukListingWrite = onDocumentWritten(
  {
    document: 'yuk_listings/{id}',
    region: 'europe-west1',
  },
  async (event) => {
    const id = event.params.id;
    const after = event.data && event.data.after;
    if (!after || !after.exists) {
      await deleteSearchIndexEntry('yuk_listing', id);
      return;
    }
    await upsertSearchIndexEntry(
      yukListingToSearchEntry(id, after.data() || {}),
    );
  },
);

const SEARCH_SERVICE_SEEDS = [
  {
    id: 'local_taxi',
    moduleId: 'local_taxi',
    title: 'Маҳаллий такси',
    subtitle: 'Туман ичида такси',
    iconKey: 'taxi',
    keywords: ['такси', 'taxi', 'маҳаллий', 'махаллий', 'йўловчи'],
    boost: 22,
  },
  {
    id: 'intercity',
    moduleId: 'intercity',
    title: 'Шаҳарлараро такси',
    subtitle: 'Шаҳарлараро йўналиш',
    iconKey: 'taxi',
    keywords: ['такси', 'taxi', 'шаҳарлараро', 'тошкент', 'йўловчи'],
    boost: 24,
  },
  {
    id: 'marshrut',
    moduleId: 'marshrut',
    title: 'Маршрут такси',
    subtitle: 'Маршрут бўйича',
    iconKey: 'taxi',
    keywords: ['такси', 'taxi', 'маршрут', 'marshrut'],
    boost: 20,
  },
  {
    id: 'yuk_birja',
    moduleId: 'yuk_birja',
    title: 'Юк биржа',
    subtitle: 'Юк ташиш',
    iconKey: 'yuk',
    keywords: ['юк', 'yuk', 'биржа', 'груз', 'такси'],
    boost: 18,
  },
  {
    id: 'platform',
    moduleId: 'platform',
    title: 'AVA дўкони',
    subtitle: 'Платформа дўкони',
    iconKey: 'shop',
    keywords: ['ава', 'ava', 'дўкон', 'дукон', 'магазин', 'платформа'],
    boost: 20,
  },
  {
    id: 'food',
    moduleId: 'food',
    title: 'Овқат',
    subtitle: 'Таом буюртма',
    iconKey: 'food',
    keywords: ['овқат', 'ovqat', 'таом', 'кафе', 'емак'],
    boost: 20,
  },
  {
    id: 'bread',
    moduleId: 'bread',
    title: 'Нон',
    subtitle: 'Нон буюртма',
    iconKey: 'bread',
    keywords: ['нон', 'non', 'патир', 'чўрек'],
    boost: 20,
  },
  {
    id: 'jobs',
    moduleId: 'jobs',
    title: 'ИШ ЭЪЛОН',
    subtitle: 'Иш ва хизмат эълонлари',
    iconKey: 'job',
    keywords: ['иш', 'ish', 'вакансия', 'эълон', 'лаборант'],
    boost: 22,
  },
  {
    id: 'cheap_products_home',
    moduleId: 'cheap_products_home',
    title: 'Онлайн бозор',
    subtitle: 'Арзон маҳсулотлар',
    iconKey: 'shop',
    keywords: ['бозор', 'bozor', 'сотиш', 'магазин'],
    boost: 18,
  },
  {
    id: 'milk',
    moduleId: 'milk',
    title: 'Сут қабул',
    subtitle: 'Сут ва қишлоқ маҳсулотлари',
    iconKey: 'milk',
    keywords: ['сут', 'sut', 'қатиқ', 'тухум'],
    boost: 16,
  },
  {
    id: 'oil_change',
    moduleId: 'oil_change',
    title: 'Мой алмаштириш',
    subtitle: 'Авто сервис',
    iconKey: 'oil',
    keywords: ['мой', 'oil', 'авто', 'машина'],
    boost: 14,
  },
  {
    id: 'sell',
    moduleId: 'sell',
    title: 'Сотиш',
    subtitle: 'Сотиш маркази',
    iconKey: 'sell',
    keywords: ['сотиш', 'sotish', 'продаж'],
    boost: 14,
  },
  {
    id: 'carpet_wash',
    moduleId: 'carpet_wash',
    title: 'Гилам ювиш',
    subtitle: 'Гилам хизмати',
    iconKey: 'carpet',
    keywords: ['гилам', 'gilam', 'ювиш'],
    boost: 12,
  },
];

const SEARCH_ROUTE_HUBS = ['Гурлан', 'Урганч', 'Хива'];
const SEARCH_ROUTE_DESTS = [
  'Тошкент', 'Самарқанд', 'Бухоро', 'Навоий', 'Нукус',
  'Андижон', 'Фарғона', 'Қарши', 'Термиз', 'Урганч', 'Хива',
];

/** Гурлан МФЙ — маҳаллий такси қидирув (P1 local_place). */
const SEARCH_GURLAN_MFY = [
  'Ёрмиш МФЙ', 'Обод МФЙ', 'Ишонч МФЙ', 'Дўстлик МФЙ', 'Навбаҳор МФЙ',
  'Чинобод МФЙ', 'Боғишамол МФЙ', 'Марифат МФЙ', 'Мевазор МФЙ', 'Дўсимбий МФЙ',
  'Фидокор МФЙ', 'Навбир-ёп МФЙ', 'Нукус МФЙ', 'Нурафшон МФЙ', 'Қатариқ МФЙ',
  'Чаккалар МФЙ', 'Зиёкор МФЙ', 'Сахтиён МФЙ', 'Янги боғ МФЙ', 'Эсабий МФЙ',
  'Қангли МФЙ', 'Ватанпарвар МФЙ', 'Марбугат МФЙ', 'Бирлашган МФЙ', 'Гулшан МФЙ',
  'Бўзқалъа МФЙ', 'Олчин МФЙ', 'Ўйилма МФЙ', 'Деҳқонобод МФЙ', 'Тахтакўпир МФЙ',
  'Мойли МФЙ', 'Шанғи МФЙ', 'Олға МФЙ', 'Янги аср МФЙ', 'Болдоқли МФЙ',
  'Шодлик МФЙ', 'Эшимжирон МФЙ', 'Жалойир МФЙ', 'Пахтачи МФЙ', 'Нурли йўл МФЙ',
  'Совунчи МФЙ', 'Пахтакор МФЙ', 'Деҳқон МФЙ', 'Беш уй МФЙ', 'Боғистон МФЙ',
  'Оққум МФЙ', 'Нуробод МФЙ', 'Дўстлик боғи МФЙ',
];

/** Admin: хизмат + йўналиш seed + мавжуд товар/эълон backfill. */
exports.adminSeedSearchIndex = functions
  .runWith({ timeoutSeconds: 540, memory: '1GB' })
  .https.onCall(async (data, context) => {
    await assertAdmin(String(data.adminPhone || ''), context);
    let services = 0;
    let routes = 0;
    let products = 0;
    let ads = 0;
    let bread = 0;
    let food = 0;
    let yuk = 0;
    let places = 0;

    for (const s of SEARCH_SERVICE_SEEDS) {
      await upsertSearchIndexEntry({
        type: 'service',
        moduleId: s.moduleId,
        sourceCollection: 'seed',
        sourceId: s.id,
        title: s.title,
        subtitle: s.subtitle,
        iconKey: s.iconKey,
        keywords: s.keywords,
        priorityBoost: s.boost,
        active: true,
      });
      services += 1;
    }

    for (const from of SEARCH_ROUTE_HUBS) {
      for (const to of SEARCH_ROUTE_DESTS) {
        if (from === to) continue;
        const sid = `${from}_${to}`.replace(/\s+/g, '_');
        await upsertSearchIndexEntry({
          type: 'intercity_route',
          moduleId: 'intercity',
          sourceCollection: 'seed',
          sourceId: sid,
          title: `${from} → ${to}`,
          subtitle: 'Шаҳарлараро такси',
          iconKey: 'taxi',
          keywords: [
            'такси', 'taxi', 'шаҳарлараро', from, to,
            `${to}га`, 'йўловчи',
          ],
          geo: { from, to },
          priorityBoost: 10,
          active: true,
        });
        routes += 1;
      }
    }

    for (const mfy of SEARCH_GURLAN_MFY) {
      const sid = mfy.replace(/\s+/g, '_');
      await upsertSearchIndexEntry({
        type: 'local_place',
        moduleId: 'local_taxi',
        sourceCollection: 'seed_mfy',
        sourceId: sid,
        title: mfy,
        subtitle: 'Гурлан · маҳаллий такси',
        iconKey: 'taxi',
        keywords: [
          'такси', 'taxi', 'мфй', 'mfy', 'маҳалла', 'гурлан', 'gurlan', mfy,
        ],
        geo: { districtId: 'gurlan', from: mfy },
        priorityBoost: 8,
        active: true,
      });
      places += 1;
    }

    const prodSnap = await db.collection('platform_products').limit(2000).get();
    for (const doc of prodSnap.docs) {
      await upsertSearchIndexEntry(platformProductToSearchEntry(doc.id, doc.data() || {}));
      products += 1;
    }

    const adsSnap = await db.collection('ads').limit(2000).get();
    for (const doc of adsSnap.docs) {
      const entry = adToSearchEntry(doc.id, doc.data() || {});
      if (!entry) continue;
      await upsertSearchIndexEntry(entry);
      ads += 1;
    }

    const breadSnap = await db.collection('bread_products').limit(500).get();
    for (const doc of breadSnap.docs) {
      await upsertSearchIndexEntry(
        breadProductToSearchEntry(doc.id, doc.data() || {}),
      );
      bread += 1;
    }

    const foodSnap = await db.collection('food_catalog').limit(500).get();
    for (const doc of foodSnap.docs) {
      await upsertSearchIndexEntry(
        foodProductToSearchEntry(doc.id, doc.data() || {}),
      );
      food += 1;
    }

    const yukSnap = await db.collection('yuk_listings').limit(500).get();
    for (const doc of yukSnap.docs) {
      await upsertSearchIndexEntry(
        yukListingToSearchEntry(doc.id, doc.data() || {}),
      );
      yuk += 1;
    }

    return {
      ok: true,
      services,
      routes,
      places,
      products,
      ads,
      bread,
      food,
      yuk,
    };
  });

/** Qiziqish bildirish — o'zaro (mutual) bo'lsa avtomatik match. */
exports.sendDatingInterest = functions.https.onCall(async (data, context) => {
  const fromId = datingCallerUid(context);
  const toId = canonicalUid(String(data.toUserId || ''));
  if (!toId || toId === fromId) {
    throw new functions.https.HttpsError('invalid-argument', 'bad target');
  }

  const [meSnap, toSnap] = await Promise.all([
    db.collection('dating_profiles').doc(fromId).get(),
    db.collection('dating_profiles').doc(toId).get(),
  ]);
  if (!meSnap.exists || meSnap.data().status !== 'approved') {
    throw new functions.https.HttpsError(
      'failed-precondition', 'Profilingiz tasdiqlanmagan');
  }
  if (!toSnap.exists || toSnap.data().status !== 'approved' ||
      toSnap.data().active === false) {
    throw new functions.https.HttpsError(
      'failed-precondition', 'Profil mavjud emas');
  }
  if (meSnap.data().gender === toSnap.data().gender) {
    throw new functions.https.HttpsError('failed-precondition', 'Mos kelmaydi');
  }

  const [b1, b2] = await Promise.all([
    db.collection('dating_blocks').doc(fromId).collection('list').doc(toId).get(),
    db.collection('dating_blocks').doc(toId).collection('list').doc(fromId).get(),
  ]);
  if (b1.exists || b2.exists) {
    throw new functions.https.HttpsError('permission-denied', 'Bloklangan');
  }

  const mId = datingMatchId(fromId, toId);
  const matchRef = db.collection('dating_matches').doc(mId);
  const matchSnap = await matchRef.get();
  if (matchSnap.exists) {
    return { ok: true, matched: true, matchId: mId };
  }

  const myName = String(meSnap.data().displayName || '');
  const toName = String(toSnap.data().displayName || '');

  // Teskari yo'nalishda pending interest bormi? → avto-match.
  const reverseQ = await db.collection('dating_interests')
    .where('fromId', '==', toId)
    .where('toId', '==', fromId)
    .where('status', '==', 'pending')
    .limit(1).get();
  if (!reverseQ.empty) {
    const batch = db.batch();
    batch.update(reverseQ.docs[0].ref, {
      status: 'accepted',
      respondedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    batch.set(matchRef, {
      users: [fromId, toId],
      userNames: { [fromId]: myName, [toId]: toName },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastMessage: '',
      lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return { ok: true, matched: true, matchId: mId };
  }

  const dupQ = await db.collection('dating_interests')
    .where('fromId', '==', fromId)
    .where('toId', '==', toId)
    .where('status', '==', 'pending')
    .limit(1).get();
  if (!dupQ.empty) {
    return { ok: true, matched: false, alreadySent: true };
  }

  await db.collection('dating_interests').add({
    fromId, toId,
    fromName: myName,
    toName,
    status: 'pending',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { ok: true, matched: false };
});

/** Qiziqishga javob (qabul/rad). Qabul → match yaratiladi. */
exports.respondDatingInterest = functions.https.onCall(async (data, context) => {
  const uid = datingCallerUid(context);
  const interestId = String(data.interestId || '');
  const accept = data.accept === true;
  if (!interestId) {
    throw new functions.https.HttpsError('invalid-argument', 'interestId required');
  }
  const ref = db.collection('dating_interests').doc(interestId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new functions.https.HttpsError('not-found', 'Topilmadi');
    }
    const d = snap.data();
    if (d.toId !== uid) {
      throw new functions.https.HttpsError('permission-denied', 'Sizniki emas');
    }
    if (d.status !== 'pending') {
      return { ok: true, status: d.status };
    }
    if (!accept) {
      tx.update(ref, {
        status: 'declined',
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { ok: true, status: 'declined' };
    }
    const mId = datingMatchId(d.fromId, d.toId);
    const matchRef = db.collection('dating_matches').doc(mId);
    tx.update(ref, {
      status: 'accepted',
      respondedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.set(matchRef, {
      users: [d.fromId, d.toId],
      userNames: { [d.fromId]: d.fromName || '', [d.toId]: d.toName || '' },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastMessage: '',
      lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { ok: true, status: 'accepted', matchId: mId };
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// NASAB DARAXTI — global graf poydevori (Faza 1: migratsiya + komponent)
// ═══════════════════════════════════════════════════════════════════════════

// ── Qarindoshlar: telefon bo'yicha kuzatuv + ro'yxatdan o'tish xabarlari ──

function isUserProfileReady(data) {
  if (!data) return false;
  const name = String(data.name || data.fullName || '').trim();
  return name.length >= 2;
}

function relativeJoinAlertDocId(alertType, targetPhone) {
  return alertType === 'new_user_welcome' ? '_welcome' : canonicalUid(targetPhone);
}

async function hasRelativeJoinAlert(ownerUid, targetPhone, alertType) {
  const id = relativeJoinAlertDocId(alertType, targetPhone);
  const snap = await db.collection('users').doc(ownerUid)
    .collection('relative_join_alerts').doc(id).get();
  return snap.exists;
}

async function markRelativeJoinAlert(ownerUid, targetPhone, alertType, extra = {}) {
  const id = relativeJoinAlertDocId(alertType, targetPhone);
  await db.collection('users').doc(ownerUid)
    .collection('relative_join_alerts').doc(id).set({
      ...extra,
      type: alertType,
      targetPhone: canonicalUid(targetPhone),
      notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}

async function upsertRelativePhoneWatcher(ownerUid, personId, displayName, phone) {
  const p = canonicalUid(phone);
  if (!p || p.length < 12 || p === ownerUid) return;
  const entryId = `${ownerUid}_${personId}`;
  await db.collection('relative_phone_watchers').doc(p)
    .collection('entries').doc(entryId).set({
      ownerUid,
      personId,
      displayName: String(displayName || '').trim() || 'Қариндош',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

async function removeRelativePhoneWatcher(ownerUid, personId, phone) {
  const p = canonicalUid(phone);
  if (!p || p.length < 12) return;
  const entryId = `${ownerUid}_${personId}`;
  try {
    await db.collection('relative_phone_watchers').doc(p)
      .collection('entries').doc(entryId).delete();
  } catch (_) { /* noop */ }
}

async function notifyOwnerRelativeJoined(ownerUid, displayName, phone, personId = '') {
  if (await hasRelativeJoinAlert(ownerUid, phone, 'owner_notified')) return false;
  const name = String(displayName || 'Қариндош').trim() || 'Қариндош';
  await notifyUserInApp({
    userId: ownerUid,
    title: '👨‍👩‍👧 Қариндош иловада',
    body: `Қариндошингиз ${name} AVA иловасига қўшилди.`,
    category: 'info',
    source: 'relative_registered',
    dataType: 'relative_registered',
    screen: 'relatives',
    extraData: {
      personId: personId || '',
      registeredPhone: canonicalUid(phone),
    },
  });
  await markRelativeJoinAlert(ownerUid, phone, 'owner_notified', {
    personId,
    displayName: name,
  });
  return true;
}

async function notifyNewUserRelativesWaiting(newUid) {
  if (await hasRelativeJoinAlert(newUid, newUid, 'new_user_welcome')) return false;
  await notifyUserInApp({
    userId: newUid,
    title: '👨‍👩‍👧 Қариндошлар кутмоқда',
    body: 'Сизни Қариндошларингиз кутмоқда. Қариндошлар тугмаси орқали Насаб дарахтига уланинг.',
    category: 'info',
    source: 'relative_waiting',
    dataType: 'relative_waiting',
    screen: 'relatives',
  });
  await markRelativeJoinAlert(newUid, newUid, 'new_user_welcome');
  return true;
}

async function notifyWatchersForRegisteredUser(newUid, userData) {
  const phone = canonicalUid(userData.phone || userData.phoneDigits || newUid);
  if (!phone || phone.length < 12) return { watchers: 0, notified: 0 };

  const entriesSnap = await db.collection('relative_phone_watchers').doc(phone)
    .collection('entries').get();
  if (entriesSnap.empty) return { watchers: 0, notified: 0 };

  let notified = 0;
  for (const doc of entriesSnap.docs) {
    const row = doc.data() || {};
    const ownerUid = row.ownerUid;
    if (!ownerUid || ownerUid === newUid) continue;
    const name = String(row.displayName || 'Қариндош').trim() || 'Қариндош';
    const sent = await notifyOwnerRelativeJoined(
      ownerUid, name, phone, row.personId || '');
    if (sent) notified++;
  }

  await notifyNewUserRelativesWaiting(newUid);
  return { watchers: entriesSnap.size, notified };
}

async function backfillRelativePhoneWatchers(ownerUid) {
  const peopleSnap = await db.collection('relatives').doc(ownerUid)
    .collection('people').get();
  for (const doc of peopleSnap.docs) {
    const data = doc.data() || {};
    const phone = canonicalUid(data.phone || '');
    if (phone.length >= 12 && phone !== ownerUid) {
      await upsertRelativePhoneWatcher(
        ownerUid,
        doc.id,
        String(data.fullName || '').trim() || 'Қариндош',
        phone);
    }
  }
}

async function checkOwnerRegisteredRelatives(ownerUid) {
  const peopleSnap = await db.collection('relatives').doc(ownerUid)
    .collection('people').get();
  let notified = 0;
  for (const doc of peopleSnap.docs) {
    const data = doc.data() || {};
    const phone = canonicalUid(data.phone || '');
    if (!phone || phone.length < 12 || phone === ownerUid) continue;
    if (await hasRelativeJoinAlert(ownerUid, phone, 'owner_notified')) continue;
    const regSnap = await db.collection('users').doc(phone).get();
    if (!regSnap.exists || !isUserProfileReady(regSnap.data())) continue;
    const displayName = String(data.fullName || '').trim() || 'Қариндош';
    const sent = await notifyOwnerRelativeJoined(
      ownerUid, displayName, phone, doc.id);
    if (sent) notified++;
  }
  return { notified };
}

async function syncRelativePhoneWatcherFromWrite(change, uid, pid, data) {
  const beforeData = change.before.exists ? (change.before.data() || {}) : {};
  const oldPhone = canonicalUid(beforeData.phone || '');
  const newPhone = canonicalUid((data || {}).phone || '');
  const displayName = String((data || {}).fullName || '').trim() || 'Қариндош';

  if (!change.after.exists) {
    if (oldPhone.length >= 12) {
      await removeRelativePhoneWatcher(uid, pid, oldPhone);
    }
    return;
  }

  if (oldPhone.length >= 12 && oldPhone !== newPhone) {
    await removeRelativePhoneWatcher(uid, pid, oldPhone);
  }

  if (newPhone.length >= 12 && newPhone !== uid) {
    await upsertRelativePhoneWatcher(uid, pid, displayName, newPhone);
    const regSnap = await db.collection('users').doc(newPhone).get();
    if (regSnap.exists && isUserProfileReady(regSnap.data())) {
      await notifyOwnerRelativeJoined(uid, displayName, newPhone, pid);
    }
  }
}

function parseBirthDateValue(raw) {
  if (!raw) return null;
  if (raw.toDate && typeof raw.toDate === 'function') return raw;
  if (raw._seconds != null) {
    return admin.firestore.Timestamp.fromMillis(raw._seconds * 1000);
  }
  const s = String(raw).trim();
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return null;
  const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
  if (Number.isNaN(d.getTime())) return null;
  return admin.firestore.Timestamp.fromDate(d);
}

function profileAddressLine(u) {
  const addr = u.address;
  if (typeof addr === 'string') return addr.trim();
  if (addr && typeof addr === 'object') {
    return [addr.mfy, addr.street, addr.house, addr.district]
      .map((x) => String(x || '').trim())
      .filter(Boolean)
      .join(', ');
  }
  return String(u.legacyAddress || '').trim();
}

function profileSelfFields(u) {
  const name = String(u.name || u.fullName || u.displayName || 'Мен').trim() || 'Мен';
  const phoneRaw = String(u.phone || u.phoneDigits || '').trim();
  const phoneDigits = canonicalUid(phoneRaw);
  return {
    fullName: name,
    photoUrl: String(u.photoUrl || u.avatar || ''),
    gender: String(u.gender || ''),
    birthDate: parseBirthDateValue(u.birthDate),
    phone: phoneRaw || phoneDigits,
    address: profileAddressLine(u),
    relationDegree: 'Мен',
    isSelf: true,
  };
}

function profileSelfFieldsChanged(before, after) {
  if (!before) return true;
  const keys = [
    'name', 'fullName', 'displayName', 'gender', 'birthDate',
    'photoUrl', 'avatar', 'phone', 'phoneDigits', 'legacyAddress',
  ];
  if (keys.some((k) => String(before[k] ?? '') !== String(after[k] ?? ''))) {
    return true;
  }
  return JSON.stringify(before.address || null)
    !== JSON.stringify(after.address || null);
}

/** Profildan «Мен» yozuvini relatives/people + tree_persons bilan sinxronlash. */
async function syncSelfRelativePerson(uid, selfId, u) {
  if (!selfId || !u || !isUserProfileReady(u)) return;
  const fields = profileSelfFields(u);
  const ref = db.collection('relatives').doc(uid).collection('people').doc(selfId);
  const snap = await ref.get();
  const mergeData = {
    ...fields,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (!snap.exists) {
    mergeData.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }
  await ref.set(mergeData, { merge: true });

  const userSnap = await db.collection('users').doc(uid).get();
  const componentId = (userSnap.data() || {}).treeComponentId
    || treeComponentIdFor(uid);
  await db.collection('tree_persons').doc(selfId).set({
    fullName: fields.fullName,
    photoUrl: fields.photoUrl,
    gender: fields.gender,
    birthDate: fields.birthDate,
    claimedBy: uid,
    ownerUid: uid,
    componentId,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

function treeComponentIdFor(uid) {
  return `cmp_${uid}`;
}

/// relatives/people hujjatidan ulashiladigan maydonlar (identity + bog'lanish).
/// relationDegree/side/phone/address/notes — SHAXSIY (perspektivaga bog'liq),
/// shu sabab global tugunga ko'chirilmaydi.
function treeNodeFromRelative(d) {
  return {
    fullName: String(d.fullName || ''),
    photoUrl: String(d.photoUrl || ''),
    photoPath: String(d.photoPath || ''),
    gender: String(d.gender || ''),
    birthDate: d.birthDate || null,
    fatherId: d.fatherId || null,
    motherId: d.motherId || null,
    spouseId: d.spouseId || null,
  };
}

/// Server maydonlarini (createdAt/updatedAt) snapshotdan olib tashlash.
function stripServerFields(d) {
  const out = { ...(d || {}) };
  delete out.createdAt;
  delete out.updatedAt;
  return out;
}

/// tree_history yozuvi (audit + undo payload).
async function writeTreeHistory(entry) {
  await db.collection('tree_history').add({
    type: entry.type,
    componentId: entry.componentId || '',
    actorUid: entry.actorUid || '',
    summary: entry.summary || '',
    data: entry.data || {},
    undone: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/// Illa kirishda: komponent + "Men" tuguni + mavjud qarindoshlarni migratsiya.
/// Idempotent — qayta chaqirsa zarar yo'q.
exports.ensureMyTree = functions.https.onCall(async (data, context) => {
  const uid = datingCallerUid(context);
  const userRef = db.collection('users').doc(uid);
  const userSnap = await userRef.get();
  const u = userSnap.data() || {};
  const componentId = u.treeComponentId || treeComponentIdFor(uid);

  const updates = {};
  if (!u.treeComponentId) updates.treeComponentId = componentId;

  // "Men" tuguni
  let selfId = u.treePersonId || null;
  if (!selfId) {
    const selfRef = db.collection('tree_persons').doc();
    selfId = selfRef.id;
    await selfRef.set({
      fullName: String(u.name || u.fullName || u.displayName || 'Мен'),
      photoUrl: String(u.photoUrl || u.avatar || ''),
      photoPath: '',
      gender: String(u.gender || ''),
      birthDate: u.birthDate || null,
      fatherId: null,
      motherId: null,
      spouseId: null,
      claimedBy: uid,
      ownerUid: uid,
      componentId,
      createdBy: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    updates.treePersonId = selfId;
  }

  await syncSelfRelativePerson(uid, selfId, u);

  // Backfill: relatives/{uid}/people → tree_persons/{xuddi shu id}
  const peopleSnap =
    await db.collection('relatives').doc(uid).collection('people').get();
  let migrated = 0;
  let batch = db.batch();
  let ops = 0;
  for (const doc of peopleSnap.docs) {
    const ref = db.collection('tree_persons').doc(doc.id);
    const rel = doc.data() || {};
    const relativeFields = treeNodeFromRelative(rel);
    const existing = await ref.get();
    if (!existing.exists) {
      batch.set(ref, {
        ...relativeFields,
        ownerUid: uid,
        componentId,
        createdBy: uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      migrated++;
    } else {
      const cur = existing.data() || {};
      const patch = {};
      for (const [k, v] of Object.entries(relativeFields)) {
        if (v == null || v === '') continue;
        const curVal = cur[k];
        if (curVal == null || curVal === '') patch[k] = v;
      }
      if (Object.keys(patch).length) {
        patch.updatedAt = admin.firestore.FieldValue.serverTimestamp();
        batch.set(ref, patch, { merge: true });
        migrated++;
      }
    }
    ops++;
    if (ops >= 400) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) await batch.commit();

  updates.treeMigratedAt = admin.firestore.FieldValue.serverTimestamp();
  await userRef.set(updates, { merge: true });

  await backfillRelativePhoneWatchers(uid);
  const relCheck = await checkOwnerRegisteredRelatives(uid);

  return {
    ok: true,
    componentId,
    personId: selfId,
    migrated,
    relativesRegisteredNotified: relCheck.notified,
  };
});

/// Merge'dan keyin eski id → omon qolgan id (tree_redirects).
async function resolveTreeRedirect(id) {
  if (!id) return id;
  const r = await db.collection('tree_redirects').doc(id).get();
  return r.exists ? (r.data().to || id) : id;
}

/// relatives/{uid}/people ichidagi eski id havolalarini yangi id ga o'zgartirish.
/// Qaytadi: [{ ownerUid, personId, fields: ['fatherId', ...] }]
async function rewriteRelativePersonRefs(ownerUid, fromId, toId) {
  if (!ownerUid || !fromId || !toId || fromId === toId) return [];
  const peopleSnap = await db.collection('relatives').doc(ownerUid)
    .collection('people').get();
  let batch = db.batch();
  let ops = 0;
  const changes = [];
  const flush = async () => {
    if (ops > 0) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  };
  for (const doc of peopleSnap.docs) {
    const d = doc.data() || {};
    const upd = {};
    const fields = [];
    if (d.fatherId === fromId) { upd.fatherId = toId; fields.push('fatherId'); }
    if (d.motherId === fromId) { upd.motherId = toId; fields.push('motherId'); }
    if (d.spouseId === fromId) { upd.spouseId = toId; fields.push('spouseId'); }
    if (fields.length) {
      upd.updatedAt = admin.firestore.FieldValue.serverTimestamp();
      batch.set(doc.ref, upd, { merge: true });
      ops++;
      changes.push({ ownerUid, personId: doc.id, fields });
      if (ops >= 400) await flush();
    }
  }
  if (ops > 0) await flush();
  return changes;
}

/// Komponent a'zolarining shaxsiy ro'yxatlarida id almashtirish.
async function rewriteComponentRelativeRefs(componentId, fromId, toId) {
  if (!componentId || !fromId || !toId || fromId === toId) return [];
  const us = await db.collection('users')
    .where('treeComponentId', '==', componentId).get();
  const all = [];
  for (const u of us.docs) {
    all.push(...await rewriteRelativePersonRefs(u.id, fromId, toId));
  }
  return all;
}

async function snapshotRelativePersonDoc(ownerUid, personId) {
  if (!ownerUid || !personId) return null;
  const ref = db.collection('relatives').doc(ownerUid)
    .collection('people').doc(personId);
  const snap = await ref.get();
  if (!snap.exists) return null;
  return {
    ownerUid,
    personId,
    data: stripServerFields(snap.data() || {}),
  };
}

async function restoreRelativePersonDoc(snapshot) {
  if (!snapshot?.ownerUid || !snapshot?.personId || !snapshot.data) return;
  await db.collection('relatives').doc(snapshot.ownerUid)
    .collection('people').doc(snapshot.personId).set({
      ...snapshot.data,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}

/// relatives ref o'zgarishlarini teskari yo'nalishda qaytarish.
async function undoRelativeRefChanges(changes, toId, fromId) {
  if (!toId || !fromId || toId === fromId) return;
  let batch = db.batch();
  let ops = 0;
  const flush = async () => {
    if (ops > 0) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  };
  for (const ch of (changes || [])) {
    const upd = {};
    for (const f of (ch.fields || [])) upd[f] = fromId;
    if (!Object.keys(upd).length) continue;
    upd.updatedAt = admin.firestore.FieldValue.serverTimestamp();
    batch.set(
      db.collection('relatives').doc(ch.ownerUid)
        .collection('people').doc(ch.personId),
      upd,
      { merge: true },
    );
    ops++;
    if (ops >= 400) await flush();
  }
  if (ops > 0) await flush();
}

/// relatives/people + photos subcollection o'chirish (Admin SDK).
async function deleteRelativePersonDocAdmin(ownerUid, personId) {
  const ref = db.collection('relatives').doc(ownerUid)
    .collection('people').doc(personId);
  const snap = await ref.get();
  if (!snap.exists) return false;
  const photosSnap = await ref.collection('photos').get();
  let batch = db.batch();
  let ops = 0;
  const flush = async () => {
    if (ops > 0) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  };
  for (const p of photosSnap.docs) {
    batch.delete(p.ref);
    ops++;
    if (ops >= 400) await flush();
  }
  batch.delete(ref);
  ops++;
  await flush();
  return true;
}

/// relatives/people o'zgarsa — global tree_persons'ni sinxron tutadi.
/// Merge bo'lgan tugunlar uchun redirect orqali omon qolgan tugunga yoziladi.
exports.onRelativePersonWrite = functions.firestore
  .document('relatives/{uid}/people/{pid}')
  .onWrite(async (change, context) => {
    const uid = context.params.uid;
    const pid = context.params.pid;
    const data = change.after.exists ? (change.after.data() || {}) : {};

    await syncRelativePhoneWatcherFromWrite(change, uid, pid, data);

    if (!change.after.exists) {
      // O'chirildi. Agar merge qilingan bo'lsa (redirect bor) — omon qolgan
      // tugunga tegmaymiz. Aks holda egasining shaxsiy tugunini o'chiramiz.
      const redir = await db.collection('tree_redirects').doc(pid).get();
      if (redir.exists) return null;
      const cur = await db.collection('tree_persons').doc(pid).get();
      if (cur.exists) {
        const node = cur.data() || {};
        const owner = node.ownerUid || '';
        const claimed = node.claimedBy || null;
        if (owner === uid && !claimed) {
          await db.collection('tree_persons').doc(pid).delete();
        } else if (owner === uid && claimed && claimed !== uid) {
          // Boshqa hisobga ulangan — daraxtda qoladi, lekin shaxsiy egalik
          // belgisini olib tashlaymiz (qayta relatives'ga ko'chmasin).
          await db.collection('tree_persons').doc(pid).set({
            ownerUid: admin.firestore.FieldValue.delete(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        }
      }
      return null;
    }

    const targetId = await resolveTreeRedirect(pid);
    const fatherId = await resolveTreeRedirect(data.fatherId || null);
    const motherId = await resolveTreeRedirect(data.motherId || null);
    const spouseId = await resolveTreeRedirect(data.spouseId || null);

    const node = {
      ...treeNodeFromRelative(data),
      fatherId,
      motherId,
      spouseId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (targetId === pid) {
      // Oddiy egalik tuguni — komponent/egani belgilaymiz.
      const userSnap = await db.collection('users').doc(uid).get();
      const u = userSnap.data() || {};
      const componentId = u.treeComponentId || treeComponentIdFor(uid);
      if (!u.treeComponentId) {
        await db.collection('users').doc(uid)
          .set({ treeComponentId: componentId }, { merge: true });
      }
      node.ownerUid = uid;
      node.componentId = componentId;
    }
    // Redirect holatida: egalik/komponent/claim'ga tegmaymiz (omon qolgan
    // tugun boshqa foydalanuvchiniki bo'lishi mumkin).

    await db.collection('tree_persons').doc(targetId).set(node, { merge: true });
    return null;
  });

/// Yangi foydalanuvchi profilini to'ldirganda — qarindosh kuzatuvchilarga xabar.
exports.onUserProfileReady = functions.firestore
  .document('users/{uid}')
  .onWrite(async (change) => {
    const after = change.after.exists ? change.after.data() : null;
    if (!isUserProfileReady(after)) return null;
    const before = change.before.exists ? change.before.data() : null;
    const uid = change.after.id;

    if (!isUserProfileReady(before)) {
      await notifyWatchersForRegisteredUser(uid, after);
    }

    if (profileSelfFieldsChanged(before, after) || !isUserProfileReady(before)) {
      let selfId = after.treePersonId || null;
      if (!selfId) {
        const ensured = await ensureTreeForUid(uid);
        selfId = ensured.selfId;
      }
      if (selfId) await syncSelfRelativePerson(uid, selfId, after);
    }
    return null;
  });

/// Foydalanuvchi uchun komponent + "Men" tugunini ta'minlash (inline, idempotent).
async function ensureTreeForUid(uid) {
  const userRef = db.collection('users').doc(uid);
  const snap = await userRef.get();
  const u = snap.data() || {};
  const componentId = u.treeComponentId || treeComponentIdFor(uid);
  const updates = {};
  if (!u.treeComponentId) updates.treeComponentId = componentId;
  let selfId = u.treePersonId || null;
  if (!selfId) {
    const selfRef = db.collection('tree_persons').doc();
    selfId = selfRef.id;
    await selfRef.set({
      fullName: String(u.name || u.fullName || u.displayName || 'Мен'),
      photoUrl: String(u.photoUrl || u.avatar || ''),
      photoPath: '',
      gender: String(u.gender || ''),
      birthDate: u.birthDate || null,
      fatherId: null,
      motherId: null,
      spouseId: null,
      claimedBy: uid,
      ownerUid: uid,
      componentId,
      createdBy: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    updates.treePersonId = selfId;
  }
  if (selfId && isUserProfileReady(u)) {
    await syncSelfRelativePerson(uid, selfId, u);
  }
  if (Object.keys(updates).length) await userRef.set(updates, { merge: true });
  return { componentId, selfId };
}

/// Shaxsiy qarindosh qo'shish — bitta id (relatives → mirror tree_persons).
exports.addRelativePerson = functions.https.onCall(async (data, context) => {
  const uid = datingCallerUid(context);
  await ensureTreeForUid(uid);

  const fullName = String(data.fullName || '').trim();
  if (!fullName) {
    throw new functions.https.HttpsError('invalid-argument', 'ism kerak');
  }

  const resolveRef = async (x) => {
    const s = String(x || '');
    if (!s) return null;
    return resolveTreeRedirect(s);
  };

  const birthDate = (data.birthDateMs != null && data.birthDateMs !== '')
    ? admin.firestore.Timestamp.fromMillis(Number(data.birthDateMs))
    : null;

  const fields = {
    fullName,
    firstName: String(data.firstName || '').trim(),
    lastName: String(data.lastName || '').trim(),
    patronymic: String(data.patronymic || '').trim(),
    gender: String(data.gender || ''),
    photoUrl: String(data.photoUrl || ''),
    photoPath: String(data.photoPath || ''),
    phone: String(data.phone || ''),
    address: String(data.address || ''),
    relationDegree: String(data.relationDegree || ''),
    side: String(data.side || ''),
    notes: String(data.notes || ''),
    birthDate,
    fatherId: await resolveRef(data.fatherId),
    motherId: await resolveRef(data.motherId),
    spouseId: await resolveRef(data.spouseId),
  };

  const ref = db.collection('relatives').doc(uid).collection('people').doc();
  await ref.set({
    ...fields,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { ok: true, personId: ref.id };
});

/// Daraxt tugunini telefon raqamiga ulash taklifi (taklif → qabul).
exports.sendTreeLinkInvite = functions.https.onCall(async (data, context) => {
  const fromUid = datingCallerUid(context);
  const nodeId = String(data.nodeId || '');
  const toPhone = canonicalUid(String(data.toPhone || ''));
  if (!nodeId) {
    throw new functions.https.HttpsError('invalid-argument', 'nodeId required');
  }
  if (!toPhone || toPhone.length < 12) {
    throw new functions.https.HttpsError('invalid-argument', 'telefon notogri');
  }
  if (toPhone === fromUid) {
    throw new functions.https.HttpsError(
      'failed-precondition', 'ozingizni ulay olmaysiz');
  }

  const nodeSnap = await db.collection('tree_persons').doc(nodeId).get();
  if (!nodeSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'tugun yoq');
  }
  const node = nodeSnap.data();
  if (node.ownerUid !== fromUid) {
    throw new functions.https.HttpsError('permission-denied', 'sizniki emas');
  }
  if (node.claimedBy) {
    throw new functions.https.HttpsError(
      'failed-precondition', 'allaqachon ulangan');
  }

  const fromUserSnap = await db.collection('users').doc(fromUid).get();
  const fu = fromUserSnap.data() || {};
  const fromComponentId = fu.treeComponentId || treeComponentIdFor(fromUid);

  const dup = await db.collection('tree_link_invites')
    .where('fromNodeId', '==', nodeId)
    .where('toUid', '==', toPhone)
    .where('status', '==', 'pending')
    .limit(1).get();
  if (!dup.empty) return { ok: true, alreadySent: true };

  const fromName = String(fu.name || fu.fullName || fu.displayName || '');
  const nodeName = String(node.fullName || '');
  const invRef = await db.collection('tree_link_invites').add({
    fromUid,
    fromComponentId,
    fromNodeId: nodeId,
    fromName,
    nodeName,
    toPhone,
    toUid: toPhone,
    status: 'pending',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await notifyUserInApp({
    userId: toPhone,
    title: 'Насаб дарахти — улаш таклифи',
    body: `${fromName || 'Қариндош'} сизни «${nodeName || 'қариндош'}» сифатида `
      + 'ўз дарахтига улашни таклиф қилмоқда.',
    category: 'info',
    source: 'tree_link_invite',
    dataType: 'tree_link_invite',
    screen: 'relatives',
    tab: 'tree',
    extraData: { inviteId: invRef.id },
  });

  return { ok: true };
});

/// Ulash taklifiga javob (qabul → komponentlar birlashadi, tugunlar merge).
exports.respondTreeLinkInvite =
  functions.https.onCall(async (data, context) => {
    const uid = datingCallerUid(context);
    const inviteId = String(data.inviteId || '');
    const accept = data.accept === true;
    if (!inviteId) {
      throw new functions.https.HttpsError(
        'invalid-argument', 'inviteId required');
    }
    const invRef = db.collection('tree_link_invites').doc(inviteId);
    const invSnap = await invRef.get();
    if (!invSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'topilmadi');
    }
    const inv = invSnap.data();
    if (inv.toUid !== uid) {
      throw new functions.https.HttpsError('permission-denied', 'sizniki emas');
    }
    if (inv.status !== 'pending') {
      return { ok: true, status: inv.status };
    }

    if (!accept) {
      await invRef.set({
        status: 'declined',
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      return { ok: true, status: 'declined' };
    }

    // Qabul qiluvchi daraxtini ta'minlaymiz.
    const me = await ensureTreeForUid(uid);
    const meComp = me.componentId;
    const survivorId = me.selfId; // omon qoladigan tugun (qabul qiluvchi "Men")
    const target = inv.fromComponentId; // omon qoladigan komponent (taklifchi)
    const victimId = inv.fromNodeId; // taklifchidagi placeholder

    const victimSnap = await db.collection('tree_persons').doc(victimId).get();
    const survivorSnap =
      await db.collection('tree_persons').doc(survivorId).get();
    if (!victimSnap.exists || !survivorSnap.exists) {
      throw new functions.https.HttpsError('failed-precondition', 'tugun yoq');
    }
    const victim = victimSnap.data();
    const survivor = survivorSnap.data();

    // Undo uchun snapshot.
    const survivorBefore = {
      componentId: survivor.componentId || meComp,
      claimedBy: survivor.claimedBy || null,
      fatherId: survivor.fatherId || null,
      motherId: survivor.motherId || null,
      spouseId: survivor.spouseId || null,
      photoUrl: survivor.photoUrl || '',
      birthDate: survivor.birthDate || null,
    };
    const toRestamped = []; // meComp → target ko'chgan tugunlar (survivor ham)
    const toRefChanges = []; // toNodes ichida victim → survivor o'zgargan refs
    const targetReferrers = []; // target ichida victim → survivor o'zgargan refs
    const usersRestamped = [];

    let batch = db.batch();
    let ops = 0;
    const flush = async () => {
      if (ops > 0) {
        await batch.commit();
        batch = db.batch();
        ops = 0;
      }
    };

    // Survivor: identity/link to'ldirish + komponent target + claim.
    batch.set(db.collection('tree_persons').doc(survivorId), {
      componentId: target,
      claimedBy: uid,
      fatherId: survivor.fatherId || victim.fatherId || null,
      motherId: survivor.motherId || victim.motherId || null,
      spouseId: survivor.spouseId || victim.spouseId || null,
      photoUrl: survivor.photoUrl || victim.photoUrl || '',
      birthDate: survivor.birthDate || victim.birthDate || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    ops++;
    if (meComp !== target) toRestamped.push(survivorId);

    // Redirect: victimId → survivorId (mirror trigger uchun).
    batch.set(db.collection('tree_redirects').doc(victimId), {
      to: survivorId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    ops++;

    // Qabul qiluvchi komponenti → target (survivor yuqorida).
    if (meComp !== target) {
      const toNodes = await db.collection('tree_persons')
        .where('componentId', '==', meComp).get();
      for (const d of toNodes.docs) {
        if (d.id === survivorId) continue;
        const dd = d.data();
        const upd = {
          componentId: target,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        const fields = [];
        if (dd.fatherId === victimId) { upd.fatherId = survivorId; fields.push('fatherId'); }
        if (dd.motherId === victimId) { upd.motherId = survivorId; fields.push('motherId'); }
        if (dd.spouseId === victimId) { upd.spouseId = survivorId; fields.push('spouseId'); }
        if (fields.length) toRefChanges.push({ id: d.id, fields });
        toRestamped.push(d.id);
        batch.set(d.ref, upd, { merge: true });
        ops++;
        if (ops >= 400) await flush();
      }
    }

    // Target (taklifchi) komponentidagi victim refs → survivor.
    const fromNodes = await db.collection('tree_persons')
      .where('componentId', '==', target).get();
    for (const d of fromNodes.docs) {
      const dd = d.data();
      const upd = {};
      const fields = [];
      if (dd.fatherId === victimId) { upd.fatherId = survivorId; fields.push('fatherId'); }
      if (dd.motherId === victimId) { upd.motherId = survivorId; fields.push('motherId'); }
      if (dd.spouseId === victimId) { upd.spouseId = survivorId; fields.push('spouseId'); }
      if (fields.length) {
        targetReferrers.push({ id: d.id, fields });
        upd.updatedAt = admin.firestore.FieldValue.serverTimestamp();
        batch.set(d.ref, upd, { merge: true });
        ops++;
        if (ops >= 400) await flush();
      }
    }

    // Victim tugunini o'chiramiz (redirect orqali resurrect bo'lmaydi).
    batch.delete(db.collection('tree_persons').doc(victimId));
    ops++;
    await flush();

    // Shaxsiy ro'yxat: havolalar survivor ga, taklifchi placeholder o'chiriladi.
    const relativeRefChanges = [
      ...(await rewriteComponentRelativeRefs(target, victimId, survivorId)),
    ];
    if (meComp !== target) {
      relativeRefChanges.push(
        ...(await rewriteComponentRelativeRefs(meComp, victimId, survivorId)));
    }
    relativeRefChanges.push(
      ...(await rewriteRelativePersonRefs(inv.fromUid, victimId, survivorId)));
    const victimRelativeSnapshot =
      await snapshotRelativePersonDoc(inv.fromUid, victimId);
    await deleteRelativePersonDocAdmin(inv.fromUid, victimId);

    // Users: qabul qiluvchi komponenti → target.
    if (meComp !== target) {
      const us = await db.collection('users')
        .where('treeComponentId', '==', meComp).get();
      let b2 = db.batch();
      let o2 = 0;
      for (const d of us.docs) {
        usersRestamped.push(d.id);
        b2.set(d.ref, { treeComponentId: target }, { merge: true });
        o2++;
        if (o2 >= 400) {
          await b2.commit();
          b2 = db.batch();
          o2 = 0;
        }
      }
      if (o2 > 0) await b2.commit();
    }

    await invRef.set({
      status: 'accepted',
      respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      mergedInto: survivorId,
    }, { merge: true });

    await writeTreeHistory({
      type: 'link',
      componentId: target,
      actorUid: uid,
      summary: `«${inv.nodeName || victim.fullName || ''}» дарахтга уланди`,
      data: {
        inviteId,
        victimId,
        survivorId,
        meComp,
        target,
        victimNode: stripServerFields(victim),
        survivorBefore,
        toRestamped,
        toRefChanges,
        targetReferrers,
        usersRestamped,
        relativeRefChanges,
        victimRelativeSnapshot,
      },
    });

    return { ok: true, status: 'accepted', componentId: target, personId: survivorId };
  });

/// Komponent ichida ikki tugunni birlashtirish (dedup, Faza 3).
/// mergeId → keepId; barcha refs qayta yo'naltiriladi, redirect yoziladi.
exports.mergeTreePersons = functions.https.onCall(async (data, context) => {
  const uid = datingCallerUid(context);
  const keepId = String(data.keepId || '');
  const mergeId = String(data.mergeId || '');
  if (!keepId || !mergeId || keepId === mergeId) {
    throw new functions.https.HttpsError('invalid-argument', 'keepId/mergeId');
  }

  const keepSnap = await db.collection('tree_persons').doc(keepId).get();
  const mergeSnap = await db.collection('tree_persons').doc(mergeId).get();
  if (!keepSnap.exists || !mergeSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'tugun yoq');
  }
  const keep = keepSnap.data();
  const merge = mergeSnap.data();

  const userSnap = await db.collection('users').doc(uid).get();
  const myComp = (userSnap.data() || {}).treeComponentId || '';
  if (!myComp || keep.componentId !== myComp || merge.componentId !== myComp) {
    throw new functions.https.HttpsError(
      'permission-denied', 'bir komponentda emas');
  }
  if (keep.claimedBy && merge.claimedBy && keep.claimedBy !== merge.claimedBy) {
    throw new functions.https.HttpsError('failed-precondition',
      'ikkalasi ham hisobga ulangan — birlashtirib bolmaydi');
  }

  const clean = (x) => (x && x !== keepId && x !== mergeId) ? x : null;
  const pick = (a, b) => clean(a) || clean(b) || null;

  // Undo uchun snapshot.
  const keepBefore = {
    fatherId: keep.fatherId || null,
    motherId: keep.motherId || null,
    spouseId: keep.spouseId || null,
    photoUrl: keep.photoUrl || '',
    birthDate: keep.birthDate || null,
    claimedBy: keep.claimedBy || null,
  };
  const referrers = [];

  let batch = db.batch();
  let ops = 0;
  const flush = async () => {
    if (ops > 0) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  };

  batch.set(db.collection('tree_persons').doc(keepId), {
    fatherId: pick(keep.fatherId, merge.fatherId),
    motherId: pick(keep.motherId, merge.motherId),
    spouseId: pick(keep.spouseId, merge.spouseId),
    photoUrl: keep.photoUrl || merge.photoUrl || '',
    birthDate: keep.birthDate || merge.birthDate || null,
    claimedBy: keep.claimedBy || merge.claimedBy || null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  ops++;

  batch.set(db.collection('tree_redirects').doc(mergeId), {
    to: keepId,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  ops++;

  const comp = await db.collection('tree_persons')
    .where('componentId', '==', myComp).get();
  for (const d of comp.docs) {
    if (d.id === mergeId || d.id === keepId) continue;
    const dd = d.data();
    const upd = {};
    const fields = [];
    if (dd.fatherId === mergeId) { upd.fatherId = keepId; fields.push('fatherId'); }
    if (dd.motherId === mergeId) { upd.motherId = keepId; fields.push('motherId'); }
    if (dd.spouseId === mergeId) { upd.spouseId = keepId; fields.push('spouseId'); }
    if (fields.length) {
      referrers.push({ id: d.id, fields });
      upd.updatedAt = admin.firestore.FieldValue.serverTimestamp();
      batch.set(d.ref, upd, { merge: true });
      ops++;
      if (ops >= 400) await flush();
    }
  }

  // mergeId hisobga ulangan bo'lsa — o'sha foydalanuvchi treePersonId'sini ko'chir.
  if (merge.claimedBy) {
    batch.set(db.collection('users').doc(merge.claimedBy),
      { treePersonId: keepId }, { merge: true });
    ops++;
  }

  batch.delete(db.collection('tree_persons').doc(mergeId));
  ops++;
  await flush();

  const relativeRefChanges =
    await rewriteComponentRelativeRefs(myComp, mergeId, keepId);
  let relativeSnapshot = null;
  if (merge.ownerUid) {
    relativeSnapshot = await snapshotRelativePersonDoc(merge.ownerUid, mergeId);
    await deleteRelativePersonDocAdmin(merge.ownerUid, mergeId);
  }

  await writeTreeHistory({
    type: 'merge',
    componentId: myComp,
    actorUid: uid,
    summary: `«${keep.fullName || merge.fullName}» — такрорлар бирлаштирилди`,
    data: {
      keepId,
      mergeId,
      keepBefore,
      mergedNode: stripServerFields(merge),
      referrers,
      claimUid: merge.claimedBy || null,
      relativeRefChanges,
      relativeSnapshot,
    },
  });

  return { ok: true, keepId };
});

/// Tarixdagi amalni qaytarish (Undo) — merge va link uchun (Faza 4).
exports.undoTreeOperation = functions.https.onCall(async (data, context) => {
  const uid = datingCallerUid(context);
  const historyId = String(data.historyId || '');
  if (!historyId) {
    throw new functions.https.HttpsError('invalid-argument', 'historyId');
  }
  const hRef = db.collection('tree_history').doc(historyId);
  const hSnap = await hRef.get();
  if (!hSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'topilmadi');
  }
  const h = hSnap.data();
  if (h.undone) return { ok: true, alreadyUndone: true };

  // Ruxsat: shu komponent a'zosi yoki admin.
  const userSnap = await db.collection('users').doc(uid).get();
  const myComp = (userSnap.data() || {}).treeComponentId || '';
  if (myComp !== h.componentId) {
    throw new functions.https.HttpsError('permission-denied', 'komponent emas');
  }

  const d = h.data || {};
  let batch = db.batch();
  let ops = 0;
  const flush = async () => {
    if (ops > 0) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  };
  const bump = () => {
    ops++;
    return ops >= 400 ? flush() : Promise.resolve();
  };

  if (h.type === 'merge') {
    // mergeId tugunini tiklash.
    batch.set(db.collection('tree_persons').doc(d.mergeId), {
      ...stripServerFields(d.mergedNode || {}),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await bump();
    batch.delete(db.collection('tree_redirects').doc(d.mergeId));
    await bump();
    // referrerlarni mergeId'ga qaytarish.
    for (const r of (d.referrers || [])) {
      const upd = {};
      for (const f of r.fields) upd[f] = d.mergeId;
      upd.updatedAt = admin.firestore.FieldValue.serverTimestamp();
      batch.set(db.collection('tree_persons').doc(r.id), upd, { merge: true });
      await bump();
    }
    // keep maydonlarini avvalgi holatga.
    batch.set(db.collection('tree_persons').doc(d.keepId), {
      fatherId: d.keepBefore.fatherId || null,
      motherId: d.keepBefore.motherId || null,
      spouseId: d.keepBefore.spouseId || null,
      photoUrl: d.keepBefore.photoUrl || '',
      birthDate: d.keepBefore.birthDate || null,
      claimedBy: d.keepBefore.claimedBy || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await bump();
    if (d.claimUid) {
      batch.set(db.collection('users').doc(d.claimUid),
        { treePersonId: d.mergeId }, { merge: true });
      await bump();
    }
    await flush();
    await undoRelativeRefChanges(d.relativeRefChanges, d.keepId, d.mergeId);
    if (d.relativeSnapshot) await restoreRelativePersonDoc(d.relativeSnapshot);
  } else if (h.type === 'link') {
    // victim tugunini tiklash.
    batch.set(db.collection('tree_persons').doc(d.victimId), {
      ...stripServerFields(d.victimNode || {}),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await bump();
    batch.delete(db.collection('tree_redirects').doc(d.victimId));
    await bump();
    // target ichidagi referrerlarni victim'ga qaytarish.
    for (const r of (d.targetReferrers || [])) {
      const upd = {};
      for (const f of r.fields) upd[f] = d.victimId;
      upd.updatedAt = admin.firestore.FieldValue.serverTimestamp();
      batch.set(db.collection('tree_persons').doc(r.id), upd, { merge: true });
      await bump();
    }
    // toRefChanges'ni victim'ga qaytarish.
    for (const r of (d.toRefChanges || [])) {
      const upd = {};
      for (const f of r.fields) upd[f] = d.victimId;
      upd.updatedAt = admin.firestore.FieldValue.serverTimestamp();
      batch.set(db.collection('tree_persons').doc(r.id), upd, { merge: true });
      await bump();
    }
    // survivor'ni avvalgi komponent/holatga.
    batch.set(db.collection('tree_persons').doc(d.survivorId), {
      componentId: d.survivorBefore.componentId || d.meComp,
      claimedBy: d.survivorBefore.claimedBy || null,
      fatherId: d.survivorBefore.fatherId || null,
      motherId: d.survivorBefore.motherId || null,
      spouseId: d.survivorBefore.spouseId || null,
      photoUrl: d.survivorBefore.photoUrl || '',
      birthDate: d.survivorBefore.birthDate || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await bump();
    // toRestamped tugunlarni meComp'ga qaytarish (survivor allaqachon yuqorida).
    for (const id of (d.toRestamped || [])) {
      if (id === d.survivorId) continue;
      batch.set(db.collection('tree_persons').doc(id),
        { componentId: d.meComp, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true });
      await bump();
    }
    await flush();
    // usersRestamped'ni meComp'ga qaytarish.
    let b2 = db.batch();
    let o2 = 0;
    for (const id of (d.usersRestamped || [])) {
      b2.set(db.collection('users').doc(id),
        { treeComponentId: d.meComp }, { merge: true });
      o2++;
      if (o2 >= 400) {
        await b2.commit();
        b2 = db.batch();
        o2 = 0;
      }
    }
    if (o2 > 0) await b2.commit();
    await undoRelativeRefChanges(d.relativeRefChanges, d.survivorId, d.victimId);
    if (d.victimRelativeSnapshot) {
      await restoreRelativePersonDoc(d.victimRelativeSnapshot);
    }
    // taklifni bekor qilamiz (qayta yuborish mumkin).
    if (d.inviteId) {
      await db.collection('tree_link_invites').doc(d.inviteId).set(
        { status: 'undone' }, { merge: true });
    }
  } else if (h.type === 'edit') {
    // Tahrirni avvalgi qiymatlarga qaytarish.
    const before = d.before || {};
    batch.set(db.collection('tree_persons').doc(d.nodeId), {
      ...before,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await bump();
    // Egasining relatives/people'siga ham qaytarish.
    if (d.ownerUid) {
      const relRef = db.collection('relatives').doc(d.ownerUid)
        .collection('people').doc(d.nodeId);
      const relSnap = await relRef.get();
      if (relSnap.exists) {
        batch.set(relRef, {
          ...before,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        await bump();
      }
    }
    await flush();
  } else if (h.type === 'create') {
    // Yaratilgan tugunni o'chirish.
    batch.delete(db.collection('tree_persons').doc(d.nodeId));
    await bump();
    if (d.ownerUid) {
      batch.delete(db.collection('relatives').doc(d.ownerUid)
        .collection('people').doc(d.nodeId));
      await bump();
    }
    await flush();
  } else {
    throw new functions.https.HttpsError(
      'failed-precondition', 'bu amal qaytarib bolmaydi');
  }

  await hRef.set({
    undone: true,
    undoneAt: admin.firestore.FieldValue.serverTimestamp(),
    undoneBy: uid,
  }, { merge: true });

  return { ok: true };
});

/// Shaxsiy qarindoshni o'chirish — server (Admin SDK), subcollection + tree tozalash.
exports.deleteRelativePerson = functions.https.onCall(async (data, context) => {
  const uid = datingCallerUid(context);
  const personId = String(data.personId || '');
  if (!personId) {
    throw new functions.https.HttpsError('invalid-argument', 'personId required');
  }

  const ref = db.collection('relatives').doc(uid).collection('people').doc(personId);
  const snap = await ref.get();
  if (!snap.exists) return { ok: true, alreadyDeleted: true };

  const row = snap.data() || {};
  if (row.isSelf === true) {
    throw new functions.https.HttpsError(
      'failed-precondition', 'men yozuvini ochirish mumkin emas');
  }

  const photosSnap = await ref.collection('photos').get();
  let batch = db.batch();
  let ops = 0;
  const flush = async () => {
    if (ops > 0) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  };
  for (const p of photosSnap.docs) {
    batch.delete(p.ref);
    ops++;
    if (ops >= 400) await flush();
  }
  batch.delete(ref);
  ops++;
  await flush();

  // tree_persons — onRelativePersonWrite ham ishlaydi; bu yerda aniq tozalash.
  const redir = await db.collection('tree_redirects').doc(personId).get();
  if (!redir.exists) {
    const nodeSnap = await db.collection('tree_persons').doc(personId).get();
    if (nodeSnap.exists) {
      const node = nodeSnap.data() || {};
      const owner = node.ownerUid || '';
      const claimed = node.claimedBy || null;
      if (owner === uid && !claimed) {
        await db.collection('tree_persons').doc(personId).delete();
      } else if (owner === uid && claimed && claimed !== uid) {
        await db.collection('tree_persons').doc(personId).set({
          ownerUid: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
    }
  }

  // Boshqa qarindoshlardagi osilib qolgan havolalar.
  const peopleSnap = await db.collection('relatives').doc(uid)
    .collection('people').get();
  batch = db.batch();
  ops = 0;
  for (const doc of peopleSnap.docs) {
    const d = doc.data() || {};
    const upd = {};
    if (d.fatherId === personId) upd.fatherId = null;
    if (d.motherId === personId) upd.motherId = null;
    if (d.spouseId === personId) upd.spouseId = null;
    if (Object.keys(upd).length) {
      upd.updatedAt = admin.firestore.FieldValue.serverTimestamp();
      batch.set(doc.ref, upd, { merge: true });
      ops++;
      if (ops >= 400) await flush();
    }
  }
  if (ops > 0) await batch.commit();

  return { ok: true };
});

/// Daraxt tugunini yaratish/tahrirlash (umumiy tahrir, Faza 5).
/// tree_persons — struktura uchun yagona manba; egasining relatives/people'si
/// ham sinxron tutiladi (mirror bilan zid kelmasligi uchun).
exports.saveTreeNode = functions.https.onCall(async (data, context) => {
  const uid = datingCallerUid(context);
  const me = await ensureTreeForUid(uid);
  const myComp = me.componentId;

  const nodeId = String(data.nodeId || '');
  const norm = (x) => {
    const s = String(x || '');
    return s && s !== nodeId ? s : null;
  };
  const fields = {
    fullName: String(data.fullName || '').trim(),
    firstName: String(data.firstName || '').trim(),
    lastName: String(data.lastName || '').trim(),
    patronymic: String(data.patronymic || '').trim(),
    gender: String(data.gender || ''),
    photoUrl: String(data.photoUrl || ''),
    photoPath: String(data.photoPath || ''),
    birthDate: (data.birthDateMs != null && data.birthDateMs !== '')
      ? admin.firestore.Timestamp.fromMillis(Number(data.birthDateMs))
      : null,
    fatherId: norm(data.fatherId),
    motherId: norm(data.motherId),
    spouseId: norm(data.spouseId),
  };
  if (!fields.fullName) {
    throw new functions.https.HttpsError('invalid-argument', 'ism kerak');
  }

  // YARATISH — bitta id: relatives → mirror (addRelativePerson bilan bir xil).
  if (!nodeId) {
    const resolveRef = async (x) => {
      const s = String(x || '');
      if (!s) return null;
      return resolveTreeRedirect(s);
    };
    const createFields = {
      ...fields,
      fatherId: await resolveRef(data.fatherId),
      motherId: await resolveRef(data.motherId),
      spouseId: await resolveRef(data.spouseId),
    };
    const ref = db.collection('relatives').doc(uid).collection('people').doc();
    await ref.set({
      ...createFields,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await writeTreeHistory({
      type: 'create',
      componentId: myComp,
      actorUid: uid,
      summary: `«${fields.fullName}» qo'shildi`,
      data: { nodeId: ref.id, ownerUid: uid },
    });
    return { ok: true, nodeId: ref.id };
  }

  // TAHRIRLASH
  const ref = db.collection('tree_persons').doc(nodeId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'tugun yoq');
  }
  const node = snap.data();
  const allowed = node.componentId === myComp
    || node.ownerUid === uid
    || node.claimedBy === uid;
  if (!allowed) {
    throw new functions.https.HttpsError('permission-denied', 'ruxsat yoq');
  }

  if (fields.fatherId) fields.fatherId = await resolveTreeRedirect(fields.fatherId);
  if (fields.motherId) fields.motherId = await resolveTreeRedirect(fields.motherId);
  if (fields.spouseId) fields.spouseId = await resolveTreeRedirect(fields.spouseId);

  const before = {
    fullName: node.fullName || '',
    gender: node.gender || '',
    photoUrl: node.photoUrl || '',
    photoPath: node.photoPath || '',
    birthDate: node.birthDate || null,
    fatherId: node.fatherId || null,
    motherId: node.motherId || null,
    spouseId: node.spouseId || null,
  };

  await ref.set({
    ...fields,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  // Egasining relatives/people'si bo'lsa — sinxron (clobber bo'lmasligi uchun).
  if (node.ownerUid) {
    const relRef = db.collection('relatives').doc(node.ownerUid)
      .collection('people').doc(nodeId);
    const relSnap = await relRef.get();
    if (relSnap.exists) {
      await relRef.set({
        ...fields,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  }

  await writeTreeHistory({
    type: 'edit',
    componentId: node.componentId || myComp,
    actorUid: uid,
    summary: `«${fields.fullName}» таҳрирланди`,
    data: { nodeId, ownerUid: node.ownerUid || null, before },
  });

  return { ok: true, nodeId };
});

// ══════════════════════════════════════
// CARPET WASH — gilam yuvish
// ══════════════════════════════════════

const CARPET_WASH_STATUSES = new Set([
  'new',
  'accepted',
  'pickup_ready',
  'pickup_in_delivery',
  'picked_up',
  'washing',
  'drying',
  'ready',
  'return_ready',
  'return_in_delivery',
  'delivered',
  'completed',
  'cancelled',
]);

async function loadCarpetWashOrderOrThrow(orderId) {
  const id = String(orderId || '').trim();
  if (!id) {
    throw new functions.https.HttpsError('invalid-argument', 'orderId required');
  }
  const snap = await db.collection('carpet_wash_orders').doc(id).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'order not found');
  }
  return { ref: snap.ref, data: snap.data() || {}, id };
}

/** Mijoz: gilam yuvish buyurtmasi yaratish. */
exports.placeCarpetWashOrder = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    }

    const idempotencyKey = String(data.idempotencyKey || '').trim();
    if (idempotencyKey) {
      const idemRef = db.collection('wallet_idempotency').doc('carpet_' + idempotencyKey);
      const idemSnap = await idemRef.get();
      if (idemSnap.exists) {
        const prev = idemSnap.data() || {};
        return { ok: true, orderId: String(prev.orderId || ''), idempotent: true };
      }
    }

    const carpetCount = parseInt(String(data.carpetCount || 0), 10);
    const pickupAddress = String(data.pickupAddress || '').trim();
    const note = String(data.note || '').trim();
    const pickupLat = data.pickupLat != null ? Number(data.pickupLat) : null;
    const pickupLng = data.pickupLng != null ? Number(data.pickupLng) : null;

    if (!Number.isFinite(carpetCount) || carpetCount < 1 || carpetCount > 20) {
      throw new functions.https.HttpsError('invalid-argument', 'carpetCount 1..20');
    }
    if (pickupAddress.length < 5) {
      throw new functions.https.HttpsError('invalid-argument', 'pickupAddress required');
    }

    const callerUid = canonicalUid(callerPhone(context));
    if (!callerUid || callerUid.length < 9) {
      throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
    }

    const uid9 = userUid(callerPhone(context));
    const uid12 = callerUid;
    let userRef = db.collection('users').doc(uid12);
    let userSnap = await userRef.get();
    if (!userSnap.exists && uid9 !== uid12) {
      userRef = db.collection('users').doc(uid9);
      userSnap = await userRef.get();
    }
    if (!userSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'user not found');
    }

    const userData = userSnap.data() || {};
    const customerPhone = canonicalUid(String(userData.phone || callerPhone(context)));
    const customerName = String(userData.name || userData.fullName || '').trim();
    const customerId = userRef.id;

    const orderRef = db.collection('carpet_wash_orders').doc();
    const payload = {
      customerId,
      customerPhone,
      customerName,
      pickupAddress,
      carpetCount,
      note,
      priceMode: 'admin',
      finalPrice: 0,
      status: 'new',
      pickupCourierId: '',
      returnCourierId: '',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (Number.isFinite(pickupLat)) payload.pickupLat = pickupLat;
    if (Number.isFinite(pickupLng)) payload.pickupLng = pickupLng;
    Object.assign(payload, geoReportStamp(userData));

    await orderRef.set(payload);
    if (idempotencyKey) {
      const idemRef = db.collection('wallet_idempotency').doc('carpet_' + idempotencyKey);
      await db.runTransaction(async (t) => {
        const idemSnap = await t.get(idemRef);
        if (idemSnap.exists) return;
        t.set(idemRef, {
          orderId: orderRef.id,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    }
    return { ok: true, orderId: orderRef.id };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('placeCarpetWashOrder:', e);
    const msg = e && e.message ? String(e.message) : 'placeCarpetWashOrder failed';
    throw new functions.https.HttpsError('internal', msg);
  }
});

/** Admin: gilam yuvish statusini o'zgartirish. */
exports.adminSetCarpetWashStatus = functions.https.onCall(async (data, context) => {
  try {
    await assertAdmin(String(data.adminPhone || ''), context);
    const orderId = String(data.orderId || '').trim();
    const status = String(data.status || '').trim();
    const finalPriceRaw = data.finalPrice;

    if (!orderId) {
      throw new functions.https.HttpsError('invalid-argument', 'orderId required');
    }
    if (!CARPET_WASH_STATUSES.has(status)) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid status');
    }

    const { ref, data: od } = await loadCarpetWashOrderOrThrow(orderId);
    const patch = {
      status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (finalPriceRaw != null && finalPriceRaw !== '') {
      const finalPrice = parseInt(String(finalPriceRaw), 10);
      if (Number.isFinite(finalPrice) && finalPrice >= 0) {
        patch.finalPrice = finalPrice;
      }
    }

    if (status === 'cancelled' && od.status === 'completed') {
      throw new functions.https.HttpsError('failed-precondition', 'already completed');
    }

    await ref.update(patch);
    return { ok: true, orderId, status };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('adminSetCarpetWashStatus:', e);
    const msg = e && e.message ? String(e.message) : 'adminSetCarpetWashStatus failed';
    throw new functions.https.HttpsError('internal', msg);
  }
});

async function assertCourierCaller(courierPhone, context) {
  const courierDigits = assertCourierPhone(courierPhone);
  const caller = callerPhone(context);
  if (canonicalUid(caller) !== canonicalUid(courierDigits)) {
    throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
  }
  return resolveAuthorizedCourierUid(courierPhone);
}

/** Kuryer: gilam olish vazifasini olish (pickup_ready → pickup_in_delivery). */
exports.courierClaimCarpetPickup = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Login required');
    }
    const orderId = String(data.orderId || '').trim();
    const courierId = await assertCourierCaller(String(data.courierPhone || ''), context);
    if (!orderId) {
      throw new functions.https.HttpsError('invalid-argument', 'orderId required');
    }

    const orderRef = db.collection('carpet_wash_orders').doc(orderId);
    await db.runTransaction(async (t) => {
      const snap = await t.get(orderRef);
      if (!snap.exists) {
        throw new functions.https.HttpsError('not-found', 'order not found');
      }
      const cur = snap.data() || {};
      const curStatus = String(cur.status || '');
      const existingCourier = String(cur.pickupCourierId || '');

      if (curStatus === 'pickup_in_delivery' && existingCourier === courierId) {
        return;
      }
      if (curStatus !== 'pickup_ready') {
        throw new functions.https.HttpsError('failed-precondition', 'not pickup_ready');
      }
      if (existingCourier && existingCourier !== courierId) {
        throw new functions.https.HttpsError('failed-precondition', 'already claimed');
      }

      t.update(orderRef, {
        status: 'pickup_in_delivery',
        pickupCourierId: courierId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return { ok: true, orderId };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('courierClaimCarpetPickup:', e);
    const msg = e && e.message ? String(e.message) : 'courierClaimCarpetPickup failed';
    throw new functions.https.HttpsError('internal', msg);
  }
});

/** Kuryer: gilam manzilga etib keldi (pickup yoki return) — qo'ng'iroqli xabar. */
exports.courierMarkCarpetArrived = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Login required');
    }
    const orderId = String(data.orderId || '').trim();
    const leg = String(data.leg || 'pickup').trim().toLowerCase();
    const courierId = await assertCourierCaller(String(data.courierPhone || ''), context);
    if (!orderId) {
      throw new functions.https.HttpsError('invalid-argument', 'orderId required');
    }
    if (leg !== 'pickup' && leg !== 'return') {
      throw new functions.https.HttpsError('invalid-argument', 'leg must be pickup or return');
    }

    const { ref, data: od } = await loadCarpetWashOrderOrThrow(orderId);
    const status = String(od.status || '');

    if (leg === 'pickup') {
      if (status !== 'pickup_in_delivery') {
        throw new functions.https.HttpsError('failed-precondition', 'not pickup_in_delivery');
      }
      if (String(od.pickupCourierId || '') !== courierId) {
        throw new functions.https.HttpsError('permission-denied', 'Not your pickup task');
      }
      if (od.pickupArrivedAt) {
        return { ok: true, idempotent: true, orderId, leg };
      }
      await ref.update({
        pickupArrivedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else {
      if (status !== 'return_in_delivery') {
        throw new functions.https.HttpsError('failed-precondition', 'not return_in_delivery');
      }
      if (String(od.returnCourierId || '') !== courierId) {
        throw new functions.https.HttpsError('permission-denied', 'Not your return task');
      }
      if (od.returnArrivedAt) {
        return { ok: true, idempotent: true, orderId, leg };
      }
      await ref.update({
        returnArrivedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    try {
      await notifyCourierArrivedToCustomer(String(od.customerPhone || ''), {
        orderId,
        module: 'carpet_wash',
        leg,
      });
    } catch (e) {
      console.error('courierMarkCarpetArrived notify:', e.message || e);
    }

    return { ok: true, orderId, leg };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('courierMarkCarpetArrived:', e);
    const msg = e && e.message ? String(e.message) : 'courierMarkCarpetArrived failed';
    throw new functions.https.HttpsError('internal', msg);
  }
});

/** Kuryer: gilam olib ketildi (pickup_in_delivery → picked_up). */
exports.courierMarkCarpetPickedUp = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Login required');
    }
    const orderId = String(data.orderId || '').trim();
    const courierId = await assertCourierCaller(String(data.courierPhone || ''), context);
    if (!orderId) {
      throw new functions.https.HttpsError('invalid-argument', 'orderId required');
    }

    const { ref, data: od } = await loadCarpetWashOrderOrThrow(orderId);
    if (String(od.status || '') !== 'pickup_in_delivery') {
      throw new functions.https.HttpsError('failed-precondition', 'not pickup_in_delivery');
    }
    if (String(od.pickupCourierId || '') !== courierId) {
      throw new functions.https.HttpsError('permission-denied', 'Not your pickup task');
    }
    if (!od.pickupArrivedAt) {
      throw new functions.https.HttpsError('failed-precondition', 'arrived first');
    }

    await ref.update({
      status: 'picked_up',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { ok: true, orderId };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('courierMarkCarpetPickedUp:', e);
    const msg = e && e.message ? String(e.message) : 'courierMarkCarpetPickedUp failed';
    throw new functions.https.HttpsError('internal', msg);
  }
});

/** Kuryer: gilam qaytarish vazifasini olish (return_ready → return_in_delivery). */
exports.courierClaimCarpetReturn = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Login required');
    }
    const orderId = String(data.orderId || '').trim();
    const courierId = await assertCourierCaller(String(data.courierPhone || ''), context);
    if (!orderId) {
      throw new functions.https.HttpsError('invalid-argument', 'orderId required');
    }

    const orderRef = db.collection('carpet_wash_orders').doc(orderId);
    await db.runTransaction(async (t) => {
      const snap = await t.get(orderRef);
      if (!snap.exists) {
        throw new functions.https.HttpsError('not-found', 'order not found');
      }
      const cur = snap.data() || {};
      const curStatus = String(cur.status || '');
      const existingCourier = String(cur.returnCourierId || '');

      if (curStatus === 'return_in_delivery' && existingCourier === courierId) {
        return;
      }
      if (curStatus !== 'return_ready') {
        throw new functions.https.HttpsError('failed-precondition', 'not return_ready');
      }
      if (existingCourier && existingCourier !== courierId) {
        throw new functions.https.HttpsError('failed-precondition', 'already claimed');
      }

      t.update(orderRef, {
        status: 'return_in_delivery',
        returnCourierId: courierId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return { ok: true, orderId };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('courierClaimCarpetReturn:', e);
    const msg = e && e.message ? String(e.message) : 'courierClaimCarpetReturn failed';
    throw new functions.https.HttpsError('internal', msg);
  }
});

/** Kuryer: gilam yetkazildi (return_in_delivery → completed). */
exports.courierMarkCarpetDelivered = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Login required');
    }
    const orderId = String(data.orderId || '').trim();
    const courierId = await assertCourierCaller(String(data.courierPhone || ''), context);
    if (!orderId) {
      throw new functions.https.HttpsError('invalid-argument', 'orderId required');
    }

    const { ref, data: od } = await loadCarpetWashOrderOrThrow(orderId);
    if (String(od.status || '') !== 'return_in_delivery') {
      throw new functions.https.HttpsError('failed-precondition', 'not return_in_delivery');
    }
    if (String(od.returnCourierId || '') !== courierId) {
      throw new functions.https.HttpsError('permission-denied', 'Not your return task');
    }
    if (!od.returnArrivedAt) {
      throw new functions.https.HttpsError('failed-precondition', 'arrived first');
    }

    await ref.update({
      status: 'completed',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { ok: true, orderId, status: 'completed' };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('courierMarkCarpetDelivered:', e);
    const msg = e && e.message ? String(e.message) : 'courierMarkCarpetDelivered failed';
    throw new functions.https.HttpsError('internal', msg);
  }
});

// ══════════════════════════════════════
// AGRO PICKUP — sut va boshqa mahsulot qabuli
// ══════════════════════════════════════

const AGRO_PICKUP_PRODUCT_TYPES = new Set(['milk']);

const AGRO_PICKUP_STATUSES = new Set([
  'new',
  'accepted',
  'pickup_in_delivery',
  'picked_up',
  'completed',
  'cancelled',
]);

async function loadAgroPickupOrderOrThrow(orderId) {
  const id = String(orderId || '').trim();
  if (!id) {
    throw new functions.https.HttpsError('invalid-argument', 'orderId required');
  }
  const snap = await db.collection('agro_pickup_orders').doc(id).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'order not found');
  }
  return { ref: snap.ref, data: snap.data() || {}, id };
}

/** Mijoz: agro qabul buyurtmasi (sut va h.k.). */
exports.placeAgroPickupOrder = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    }

    const idempotencyKey = String(data.idempotencyKey || '').trim();
    if (idempotencyKey) {
      const idemRef = db.collection('wallet_idempotency').doc('agro_' + idempotencyKey);
      const idemSnap = await idemRef.get();
      if (idemSnap.exists) {
        const prev = idemSnap.data() || {};
        return { ok: true, orderId: String(prev.orderId || ''), idempotent: true };
      }
    }

    const productType = String(data.productType || 'milk').trim();
    const literCount = Number(data.literCount);
    const pickupAddress = String(data.pickupAddress || '').trim();
    const note = String(data.note || '').trim();
    const pickupLat = data.pickupLat != null ? Number(data.pickupLat) : null;
    const pickupLng = data.pickupLng != null ? Number(data.pickupLng) : null;

    if (!AGRO_PICKUP_PRODUCT_TYPES.has(productType)) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid productType');
    }
    if (!Number.isFinite(literCount) || literCount < 1 || literCount > 500) {
      throw new functions.https.HttpsError('invalid-argument', 'literCount 1..500');
    }
    if (pickupAddress.length < 5) {
      throw new functions.https.HttpsError('invalid-argument', 'pickupAddress required');
    }

    const callerUid = canonicalUid(callerPhone(context));
    if (!callerUid || callerUid.length < 9) {
      throw new functions.https.HttpsError('permission-denied', 'Phone mismatch');
    }

    const uid9 = userUid(callerPhone(context));
    const uid12 = callerUid;
    let userRef = db.collection('users').doc(uid12);
    let userSnap = await userRef.get();
    if (!userSnap.exists && uid9 !== uid12) {
      userRef = db.collection('users').doc(uid9);
      userSnap = await userRef.get();
    }
    if (!userSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'user not found');
    }

    const userData = userSnap.data() || {};
    const customerPhone = canonicalUid(String(userData.phone || callerPhone(context)));
    const customerName = String(userData.name || userData.fullName || '').trim();
    const customerId = userRef.id;

    const orderRef = db.collection('agro_pickup_orders').doc();
    const payload = {
      customerId,
      customerPhone,
      customerName,
      productType,
      pickupAddress,
      literCount,
      note,
      priceMode: 'admin',
      finalPrice: 0,
      status: 'new',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (Number.isFinite(pickupLat)) payload.pickupLat = pickupLat;
    if (Number.isFinite(pickupLng)) payload.pickupLng = pickupLng;
    Object.assign(payload, geoReportStamp(userData));

    await orderRef.set(payload);
    if (idempotencyKey) {
      const idemRef = db.collection('wallet_idempotency').doc('agro_' + idempotencyKey);
      await db.runTransaction(async (t) => {
        const idemSnap = await t.get(idemRef);
        if (idemSnap.exists) return;
        t.set(idemRef, {
          orderId: orderRef.id,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    }
    return { ok: true, orderId: orderRef.id };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('placeAgroPickupOrder:', e);
    const msg = e && e.message ? String(e.message) : 'placeAgroPickupOrder failed';
    throw new functions.https.HttpsError('internal', msg);
  }
});

/** Admin: agro qabul statusini o'zgartirish. */
exports.adminSetAgroPickupStatus = functions.https.onCall(async (data, context) => {
  try {
    await assertAdmin(String(data.adminPhone || ''), context);
    const orderId = String(data.orderId || '').trim();
    const status = String(data.status || '').trim();
    const finalPriceRaw = data.finalPrice;

    if (!orderId) {
      throw new functions.https.HttpsError('invalid-argument', 'orderId required');
    }
    if (!AGRO_PICKUP_STATUSES.has(status)) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid status');
    }

    const { ref, data: od } = await loadAgroPickupOrderOrThrow(orderId);
    const patch = {
      status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (finalPriceRaw != null && finalPriceRaw !== '') {
      const finalPrice = parseInt(String(finalPriceRaw), 10);
      if (Number.isFinite(finalPrice) && finalPrice >= 0) {
        patch.finalPrice = finalPrice;
      }
    }

    if (status === 'cancelled' && od.status === 'completed') {
      throw new functions.https.HttpsError('failed-precondition', 'already completed');
    }

    await ref.update(patch);
    return { ok: true, orderId, status };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('adminSetAgroPickupStatus:', e);
    const msg = e && e.message ? String(e.message) : 'adminSetAgroPickupStatus failed';
    throw new functions.https.HttpsError('internal', msg);
  }
});

/** Kuryer: sut qabul vazifasini olish (accepted → pickup_in_delivery). */
exports.courierClaimAgroPickup = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Login required');
    }
    const orderId = String(data.orderId || '').trim();
    const courierId = await assertCourierCaller(String(data.courierPhone || ''), context);
    if (!orderId) {
      throw new functions.https.HttpsError('invalid-argument', 'orderId required');
    }

    const orderRef = db.collection('agro_pickup_orders').doc(orderId);
    await db.runTransaction(async (t) => {
      const snap = await t.get(orderRef);
      if (!snap.exists) {
        throw new functions.https.HttpsError('not-found', 'order not found');
      }
      const cur = snap.data() || {};
      const curStatus = String(cur.status || '');
      const existingCourier = String(cur.pickupCourierId || '');

      if (curStatus === 'pickup_in_delivery' && existingCourier === courierId) {
        return;
      }
      if (curStatus !== 'accepted') {
        throw new functions.https.HttpsError('failed-precondition', 'not accepted');
      }
      if (existingCourier && existingCourier !== courierId) {
        throw new functions.https.HttpsError('failed-precondition', 'already claimed');
      }

      t.update(orderRef, {
        status: 'pickup_in_delivery',
        pickupCourierId: courierId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return { ok: true, orderId };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('courierClaimAgroPickup:', e);
    const msg = e && e.message ? String(e.message) : 'courierClaimAgroPickup failed';
    throw new functions.https.HttpsError('internal', msg);
  }
});

/** Kuryer: sut qabul manziliga etib keldi — qo'ng'iroqli xabar. */
exports.courierMarkAgroPickupArrived = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Login required');
    }
    const orderId = String(data.orderId || '').trim();
    const courierId = await assertCourierCaller(String(data.courierPhone || ''), context);
    if (!orderId) {
      throw new functions.https.HttpsError('invalid-argument', 'orderId required');
    }

    const { ref, data: od } = await loadAgroPickupOrderOrThrow(orderId);
    if (String(od.status || '') !== 'pickup_in_delivery') {
      throw new functions.https.HttpsError('failed-precondition', 'not pickup_in_delivery');
    }
    if (String(od.pickupCourierId || '') !== courierId) {
      throw new functions.https.HttpsError('permission-denied', 'Not your pickup task');
    }
    if (od.arrivedAt) {
      return { ok: true, idempotent: true, orderId };
    }

    await ref.update({
      arrivedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    try {
      await notifyCourierArrivedToCustomer(String(od.customerPhone || ''), {
        orderId,
        module: 'agro_pickup',
        productType: String(od.productType || 'milk'),
      });
    } catch (e) {
      console.error('courierMarkAgroPickupArrived notify:', e.message || e);
    }

    return { ok: true, orderId };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('courierMarkAgroPickupArrived:', e);
    const msg = e && e.message ? String(e.message) : 'courierMarkAgroPickupArrived failed';
    throw new functions.https.HttpsError('internal', msg);
  }
});

/** Kuryer: sut olib ketildi (pickup_in_delivery → picked_up). */
exports.courierMarkAgroPickedUp = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Login required');
    }
    const orderId = String(data.orderId || '').trim();
    const courierId = await assertCourierCaller(String(data.courierPhone || ''), context);
    if (!orderId) {
      throw new functions.https.HttpsError('invalid-argument', 'orderId required');
    }

    const { ref, data: od } = await loadAgroPickupOrderOrThrow(orderId);
    if (String(od.status || '') !== 'pickup_in_delivery') {
      throw new functions.https.HttpsError('failed-precondition', 'not pickup_in_delivery');
    }
    if (String(od.pickupCourierId || '') !== courierId) {
      throw new functions.https.HttpsError('permission-denied', 'Not your pickup task');
    }
    if (!od.arrivedAt) {
      throw new functions.https.HttpsError('failed-precondition', 'arrived first');
    }

    await ref.update({
      status: 'picked_up',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { ok: true, orderId, status: 'picked_up' };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('courierMarkAgroPickedUp:', e);
    const msg = e && e.message ? String(e.message) : 'courierMarkAgroPickedUp failed';
    throw new functions.https.HttpsError('internal', msg);
  }
});

// --- Telegram Wallet Bot (Phase 0) -----------------------------
const { attachTelegramWalletBot } = require('./telegram_wallet_bot');
attachTelegramWalletBot(exports, {
  functions,
  db,
  admin,
  settlementLedger,
  requireCallerRoles,
  canonicalUid,
  notifyUserInApp,
  isIdentifiedUser,
  assertNotDeviceTrustLimited,
});
