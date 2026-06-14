const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios');
const crypto = require('crypto');
admin.initializeApp();

const db = admin.firestore();

const DEVICE_BINDING_MAX_FAILED = 5;
const DEVICE_BINDING_BLOCK_MS = 24 * 60 * 60 * 1000;

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

/** `config/passenger_cancel_block` — marshrut + local taxi (60s kesh). */
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
      return;
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
  } else {
    await stateRef.set({
      cancelCount,
      firstCancelAt: admin.firestore.Timestamp.fromMillis(firstCancelAt),
      blockedUntil: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
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

async function applyLocalTaxiCancelBlock(userPhone) {
  const phone = digits(userPhone);
  if (phone.length < 9) return;

  const ref = db.collection('users').doc(phone)
      .collection('local_taxi_block').doc('state');
  await applyPassengerCancelBlock(ref);
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
exports.onAdUpdate = functions.firestore
  .document('ads/{adId}')
  .onUpdate(async (change) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    if (before.status === after.status) return;

    const uid = digits(after.authorPhone || '');
    if (uid.length < 9) return;

    const preview = String(after.title || after.text || '').trim().slice(0, 120);
    let title = '';
    let body = preview;
    let dataType = 'ad_moderation';

    switch (after.status) {
      case 'active':
        title = '📢 Эълонингиз e\'lon qilindi';
        body = preview || 'Иш топ бўлимида кўринади';
        dataType = 'ad_published';
        break;
      case 'blocked':
        title = '⛔ Эълон блокланди';
        body = preview || 'Админ билан боғланинг';
        break;
      case 'completed':
        title = '✅ Эълон yakunlandi';
        body = preview || '';
        break;
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
      screen: 'jobs',
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
            screen: 'jobs',
            tab: 'sell',
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

    if (after.status === 'cancelled' && (after.taxiType || '') === 'local') {
      const cancelledBy = String(after.cancelledBy || '');
      if (
        before.status === 'searching' &&
        (cancelledBy === 'passenger' || cancelledBy === 'user')
      ) {
        const userPhone = digits(after.userPhone || '');
        if (userPhone.length >= 9) {
          await applyLocalTaxiCancelBlock(userPhone);
        }
      }
    }

    if (
      after.status === 'cancelled' &&
      after.taxiType === 'local' &&
      after.cancelledBy === 'passenger' &&
      after.driverId
    ) {
      try {
        await db.collection('drivers').doc(after.driverId).update({
          isBusy: false,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (e) {
        console.error('release driver isBusy failed:', e);
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
        title = '❌ Сафар бекор қилинди';
        body  = 'Яна уриниб кўринг';
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

    if (
      after.status === 'accepted' &&
      (after.taxiType === 'local' || after.taxiType === 'alone') &&
      !after.estimatedPrice
    ) {
      const priceSnap = await db.collection('settings').doc('prices').get();
      const baseFare = priceSnap.data()?.local_base ?? 5000;
      const perKm = priceSnap.data()?.local_per_km ?? 1500;
      const distKm = after.distanceKm ?? 0;
      const estimated = Math.round(baseFare + distKm * perKm);
      await db.collection('trips').doc(tripId).update({
        estimatedPrice: estimated,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
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

function assertAdmin(operatorPhone) {
  const uid = digits(operatorPhone);
  if (!uid) throw new functions.https.HttpsError('invalid-argument', 'operatorPhone');
  return db.collection('users').doc(uid).get().then((doc) => {
    const role = (doc.data() || {}).role || 'user';
    if (role !== 'admin' && role !== 'superadmin' && role !== 'dispatcher') {
      throw new functions.https.HttpsError('permission-denied', 'Admin only');
    }
    return uid;
  });
}

function assertAdminOrDriver(operatorPhone) {
  const uid = digits(operatorPhone);
  if (!uid) throw new functions.https.HttpsError('invalid-argument', 'operatorPhone');
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
  throw new functions.https.HttpsError('invalid-argument', 'bad inventory kind');
}

exports.placeOrderWithWallet = functions.https.onCall(async (data, context) => {
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
  if (decrementsIn.length > 80) {
    throw new functions.https.HttpsError('invalid-argument', 'too many decrements');
  }

  const orderType = String(orderBase.type || '');
  if (orderType !== 'bread' && orderType !== 'food') {
    throw new functions.https.HttpsError('invalid-argument', 'orderBase.type must be bread or food');
  }

  const uid = userUid(userPhone);
  const userRef = db.collection('users').doc(uid);
  const userCheck = await userRef.get();
  if (!userCheck.exists) {
    throw new functions.https.HttpsError('not-found', 'user not found');
  }

  const idemRef = db.collection('wallet_idempotency').doc(idempotencyKey);

  const existing = await idemRef.get();
  if (existing.exists) {
    return existing.data().result || { ok: true, duplicate: true };
  }

  const orderRef = db.collection('orders').doc();
  const module = orderType === 'bread' ? 'bread' : 'food';

  /** key: "col__id" -> { col, id, qty, label } */
  const agg = {};
  for (let i = 0; i < decrementsIn.length; i += 1) {
    const c = decrementsIn[i] || {};
    const id = String(c.id || '').trim();
    const qty = Number(c.qty);
    if (!id || !Number.isFinite(qty) || qty <= 0) continue;
    let col;
    try {
      col = inventoryCollectionForDecrementKind(String(c.kind || ''));
    } catch (e) {
      throw new functions.https.HttpsError('invalid-argument', 'bad decrement kind');
    }
    const key = `${col}__${id}`;
    if (!agg[key]) {
      agg[key] = {
        col, id, qty: 0, label: String(c.label || id),
      };
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

    const userRef = db.collection('users').doc(uid);
    const userSnap = await t.get(userRef);
    const prevBalance = (userSnap.data() && userSnap.data().bonusBalance) || 0;

    const orderTotal = parseInt(String(orderBase.total || 0), 10);
    if (!Number.isFinite(orderTotal) || orderTotal <= 0) {
      throw new functions.https.HttpsError('invalid-argument', 'invalid order total');
    }

    const maxWallet = maxWalletDebit(prevBalance, orderTotal);
    let requested = parseInt(String(orderBase.balanceApplied ?? 0), 10);
    if (!Number.isFinite(requested) || requested < 0) requested = 0;
    requested = Math.floor(requested);
    const walletDebit = Math.min(requested, maxWallet);
    const cashDue = orderTotal - walletDebit;

    const cashPaidParsed = orderBase.cashPaid != null && orderBase.cashPaid !== ''
      ? parseInt(String(orderBase.cashPaid), 10)
      : cashDue;
    const cashPaid = Number.isFinite(cashPaidParsed) ? cashPaidParsed : cashDue;

    if (cashDue > 0 && cashPaid < cashDue) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        `insufficient_cash: need ${cashDue}, got ${cashPaid}`,
      );
    }

    const changeCredit = Math.max(0, cashPaid - cashDue);
    const nextBalance = prevBalance - walletDebit + changeCredit;
    if (nextBalance < 0) {
      throw new functions.https.HttpsError('failed-precondition', 'insufficient_balance');
    }

    const invKeys = Object.keys(agg);
    const invSnaps = {};
    for (let i = 0; i < invKeys.length; i += 1) {
      const row = agg[invKeys[i]];
      const ref = db.collection(row.col).doc(row.id);
      invSnaps[invKeys[i]] = await t.get(ref);
    }

    const failures = [];
    for (let i = 0; i < invKeys.length; i += 1) {
      const row = agg[invKeys[i]];
      const snap = invSnaps[invKeys[i]];
      const need = row.qty;
      if (!snap.exists) {
        continue;
      }
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

    for (let i = 0; i < invKeys.length; i += 1) {
      const row = agg[invKeys[i]];
      const snap = invSnaps[invKeys[i]];
      const ref = db.collection(row.col).doc(row.id);
      const need = row.qty;
      if (!snap.exists) {
        t.set(ref, {
          totalStock: 0,
          soldToday: need,
        });
        continue;
      }
      t.update(ref, {
        soldToday: admin.firestore.FieldValue.increment(need),
      });
    }

    let ledgerIdDebit = null;
    let ledgerIdChange = null;

    if (walletDebit > 0 || changeCredit > 0) {
      t.set(userRef, {
        bonusBalance: nextBalance,
        balanceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    if (walletDebit > 0) {
      ledgerIdDebit = userRef.collection('wallet_ledger').doc().id;
      t.set(userRef.collection('wallet_ledger').doc(ledgerIdDebit), {
        type: 'purchase_debit',
        amount: -walletDebit,
        module,
        refType: 'order',
        refId: orderRef.id,
        meta: {
          orderTotal, cashDue, cashPaid, roundingStep: 1,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: 'client',
      });
    }

    if (changeCredit > 0) {
      ledgerIdChange = userRef.collection('wallet_ledger').doc().id;
      t.set(userRef.collection('wallet_ledger').doc(ledgerIdChange), {
        type: 'change_accrued',
        amount: changeCredit,
        module,
        refType: 'order',
        refId: orderRef.id,
        meta: {
          orderTotal, cashPaid, cashDue, roundingStep: 1,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: 'client',
      });
    }

    const orderPayload = {
      type: orderType,
      userName: String(orderBase.userName || ''),
      userPhone: String(orderBase.userPhone || ''),
      address: String(orderBase.address || ''),
      phone: String(orderBase.phone || ''),
      items: orderBase.items || [],
      total: orderTotal,
      balanceApplied: walletDebit,
      cashDue,
      cashPaid,
      status: 'new',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (orderType === 'bread' && orderBase.extras) {
      orderPayload.extras = orderBase.extras;
    }
    const userData = userSnap.data() || {};
    const userAddr = userData.address;
    let lat = orderBase.lat != null && orderBase.lat !== ''
      ? Number(orderBase.lat)
      : null;
    let lng = orderBase.lng != null && orderBase.lng !== ''
      ? Number(orderBase.lng)
      : null;
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
      walletDebited: walletDebit,
      cashDue,
      cashPaid,
      ledgerIdDebit,
      ledgerIdChange,
    };

    t.set(idemRef, {
      type: 'placeOrderWithWallet',
      result: out,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return out;
  });

  if (txDuplicate) {
    return txDuplicate;
  }
  return result;
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

/** Буюртма + омбор; кошелёк ечилмайди (post-paid). */
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
  if (orderType !== 'bread' && orderType !== 'food') {
    throw new functions.https.HttpsError('invalid-argument', 'orderBase.type must be bread or food');
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

  const orderRef = db.collection('orders').doc();
  const agg = {};
  for (let i = 0; i < decrementsIn.length; i += 1) {
    const c = decrementsIn[i] || {};
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

    const orderTotal = parseInt(String(orderBase.total || 0), 10);
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

    const orderPayload = {
      type: orderType,
      userName: String(orderBase.userName || ''),
      userPhone: String(orderBase.userPhone || ''),
      address: String(orderBase.address || ''),
      phone: String(orderBase.phone || ''),
      items: orderBase.items || [],
      total: orderTotal,
      balanceApplied: 0,
      cashDue: orderTotal,
      cashPaid: 0,
      status: 'new',
      fulfillmentStatus: 'pending',
      paymentStatus: 'unpaid',
      fulfillmentMode: 'delivery',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (orderType === 'bread' && orderBase.extras) {
      orderPayload.extras = orderBase.extras;
    }
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
    const out = { ok: true, orderId: orderRef.id, cashDue: orderTotal };
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
        .where('status', '==', 'active')
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

  // Мижозга қўнғироқли огоҳлантириш (foreground'да 7с/10с×3 ритм, фонда канал овози).
  try {
    const customerPhone = od.userPhone || od.phone || '';
    if (customerPhone) {
      await notifyUserInApp({
        userId: customerPhone,
        title: '🔔 Курьер етиб келди',
        body: 'Курьер манзилингизга етиб келди. Илтимос, кутиб олинг.',
        category: 'order',
        source: 'courier_arrived',
        dataType: 'courier_arrived',
        screen: 'orders',
        extraData: { orderId, ring: '1' },
        channelId: 'courier_arrival_alarm',
      });
    }
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

  if (linesIn.length < 1 || linesIn.length > 20) {
    throw new functions.https.HttpsError('invalid-argument', 'lines required');
  }

  const { ref, data: od } = await loadOrderOrThrow(orderId);
  const fs = od.fulfillmentStatus || '';
  if (fs !== 'arrived') {
    throw new functions.https.HttpsError('failed-precondition', 'arrived first');
  }
  if (od.paymentStatus === 'paid' || od.paymentStatus === 'payment_pending_confirm') {
    throw new functions.https.HttpsError('failed-precondition', 'already_paid');
  }

  const orderTotal = parseInt(String(od.total ?? od.grandTotal ?? 0), 10);
  if (!Number.isFinite(orderTotal) || orderTotal <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'invalid order total');
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
  if (totalSubmitted < orderTotal - 1) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `Underpaid: ${totalSubmitted} < ${orderTotal}`,
    );
  }
  const paidSum = totalSubmitted;
  const changeCredit = Math.max(0, totalSubmitted - orderTotal);

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
    const remainingDue = orderTotal - nonWalletSum;
    if (walletSum > remainingDue + 1) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        `wallet_overpay: wallet ${walletSum} > remaining due ${remainingDue}`,
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
  if (walletSum > 0) {
    orderPatch.balanceApplied = walletSum;
  }
  batch.update(ref, orderPatch);
  batch.set(ref.collection('payment_events').doc(), {
    action: 'courier_submit_payment',
    actorType: 'courier',
    actorId: courierId,
    payload: { lines: normalized, paidSum, changeCredit },
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

/** Мижоз нақд чиқариш талаби */
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

  const uid = userUid(userPhone);
  const idemRef = db.collection('wallet_idempotency').doc(idempotencyKey);

  const existing = await idemRef.get();
  if (existing.exists) {
    return existing.data().result || { ok: true, duplicate: true };
  }

  const userSnap = await db.collection('users').doc(uid).get();
  const bal = (userSnap.data() && userSnap.data().bonusBalance) || 0;
  if (bal < amount) {
    throw new functions.https.HttpsError('failed-precondition', 'insufficient_balance');
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
    const prev = (userSnap.data() && userSnap.data().bonusBalance) || 0;
    if (prev < amount) {
      throw new functions.https.HttpsError('failed-precondition', 'insufficient_balance');
    }
    const next = prev - amount;
    const ledgerId = db.collection('users').doc(uid).collection('wallet_ledger').doc().id;

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

/** Composite fingerprint: login oldin qurilma ↔ telefon tekshiruvi. */
exports.checkDeviceBinding = functions.https.onCall(async (data) => {
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
      return {
        status: 'blocked',
        failedAttempts: binding.failedAttempts || 0,
        message: 'Qurilma vaqtincha bloklangan. Adminga murojaat qiling.',
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

      let customToken = null;
      try {
        customToken = await createPhoneCustomToken(phone);
      } catch (authErr) {
        console.error('createPhoneCustomToken failed:', authErr.message);
        return { status: 'needs_verification', skipSms: false };
      }
      return {
        status: 'trusted_device',
        skipSms: true,
        customToken,
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
      let customToken = null;
      try {
        customToken = await createPhoneCustomToken(phone);
      } catch (authErr) {
        console.error('createPhoneCustomToken failed:', authErr.message);
        return { status: 'needs_verification', skipSms: false };
      }
      return {
        status: 'trusted_device',
        skipSms: true,
        customToken,
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
      message: 'Bu qurilma boshqa raqamga bog\'liq. Adminga murojaat qiling.',
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
        let customToken = null;
        try {
          customToken = await createPhoneCustomToken(phone);
        } catch (authErr) {
          console.error('createPhoneCustomToken failed:', authErr.message);
          return { status: 'needs_verification', skipSms: false };
        }
        return {
          status: 'trusted_device',
          skipSms: true,
          customToken,
          autoApproved: true,
        };
      }
      return {
        status: 'phone_bound_other_device',
        message: 'Bu raqam boshqa qurilmaga bog\'liq. Adminga murojaat qiling.',
      };
    }
  }

  return {
    status: 'needs_verification',
    skipSms: false,
  };
});

/** SMS yoki admin kodi tasdiqlangandan keyin qurilmani bog'lash. */
exports.registerDeviceBinding = functions.https.onCall(async (data, context) => {
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

/** Admin panel kodidan keyin: pending_codes tekshiruvi + device_bindings + custom token. */
exports.verifyPendingCodeAndRegister = functions.https.onCall(async (data) => {
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
exports.adminSetDeviceBindingAutoApprove = functions.https.onCall(async (data) => {
  await assertAdmin(String(data.adminPhone || ''));
  const enabled = data.enabled === true;
  await db.collection('settings').doc('app').set({
    deviceBindingAutoApprove: enabled,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, enabled };
});

/** Admin: bir bosishda avtomatik tasdiqlash (konfliktlarni hal qiladi). */
exports.adminAutoApproveDeviceBinding = functions.https.onCall(async (data) => {
  await assertAdmin(String(data.adminPhone || ''));
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
exports.adminManualApproveDeviceBinding = functions.https.onCall(async (data) => {
  await assertAdmin(String(data.adminPhone || ''));
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
exports.adminUnblockDeviceBinding = functions.https.onCall(async (data) => {
  await assertAdmin(String(data.adminPhone || ''));
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
exports.adminRejectDeviceBinding = functions.https.onCall(async (data) => {
  await assertAdmin(String(data.adminPhone || ''));
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
exports.migrateOldBindings = functions.https.onCall(async (data) => {
  await assertAdmin(String(data.adminPhone || ''));
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

exports.adminWebSignIn = functions.https.onCall(async (data) => {
  const phone = canonicalUid(data.phone || '');
  if (phone !== TRUSTED_ADMIN_WEB_PHONE) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Trusted admin phone only',
    );
  }
  const found = await findUserDocByPhone(phone);
  if (!found) {
    throw new functions.https.HttpsError('not-found', 'User not found');
  }
  const role = (found.snap.data() || {}).role || 'user';
  if (!['admin', 'superadmin', 'dispatcher'].includes(role)) {
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

const ADMIN_ORDER_STATUSES = new Set([
  'new', 'accepted', 'ready', 'in_delivery', 'delivered', 'rejected',
]);

/** Admin web: буюртма status (Firestore rules `isAdmin()` custom token bilan ишламайди). */
exports.adminSetOrderStatus = functions.https.onCall(async (data) => {
  await assertAdmin(String(data.adminPhone || ''));
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
exports.adminSetOrderStatusBatch = functions.https.onCall(async (data) => {
  await assertAdmin(String(data.adminPhone || ''));
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
exports.adminCreateCollectionTask = functions.https.onCall(async (data) => {
  try {
    const adminUid = await assertAdmin(String(data.adminPhone || ''));
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
exports.adminGetWarehouseStock = functions.https.onCall(async (data) => {
  try {
    await assertAdmin(String(data.adminPhone || ''));

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
  const adminUid = await assertAdmin(adminPhone);

  const targetPhone = digits(data.targetPhone || data.userPhone || '');
  if (targetPhone.length < 9) {
    throw new functions.https.HttpsError('invalid-argument', 'Telefon raqami noto\'g\'ri');
  }

  const role = String(data.role || 'user').trim();
  const allowedForAdmin = ['user', 'admin'];
  if (!allowedForAdmin.includes(role)) {
    throw new functions.https.HttpsError('invalid-argument', 'Rol ruxsat etilmagan');
  }

  if (digits(adminPhone) === targetPhone && role !== 'admin' && role !== 'superadmin') {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'O\'zingizni adminlikdan olib tashlay olmaysiz',
    );
  }

  const ref = db.collection('users').doc(targetPhone);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Bu telefon Firestore\'da yo\'q. Avval ilovada ro\'yxatdan o\'ting.',
    );
  }

  const currentRole = String((snap.data() || {}).role || 'user');
  const adminSnap = await db.collection('users').doc(adminUid).get();
  const adminRole = String((adminSnap.data() || {}).role || 'user');

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

  return { ok: true, uid: targetPhone, role };
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
    batch.set(
      db.collection('users').doc(userPhone).collection('driverProfiles').doc('marshrut'),
      {
        carModel: car,
        plate: plate.toUpperCase(),
        seats: maxSeatsForCarModel(carModel),
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
  const adminUid = await assertAdmin(adminPhone);

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
  const adminUid = await assertAdmin(adminPhone);

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
  const adminUid = await assertAdmin(adminPhone);

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
  await assertAdmin(adminPhone);

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
  await assertAdmin(adminPhone);
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
  await assertAdmin(adminPhone);

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
  await assertAdmin(adminPhone);
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

/// Ҳар кун ярим тунда soldToday ҳисоблагичларини нулга қайтариш.
exports.resetDailySoldStock = functions.pubsub
  .schedule('0 0 * * *')
  .timeZone('Asia/Tashkent')
  .onRun(async () => {
    const [bread, extras, food] = await Promise.all([
      _resetCollectionSoldToday('bread_products'),
      _resetCollectionSoldToday('extra_products'),
      _resetCollectionSoldToday('food_inventory'),
    ]);
    console.log(
      `Daily stock reset: bread=${bread}, extras=${extras}, food=${food}`);
    return null;
  });

/// Қўлда ишга тушириш — админдан callable (test/recovery учун).
exports.resetSoldStockNow = functions.https.onCall(async (data, context) => {
  const adminPhone = String(data.adminPhone || '');
  await assertAdmin(adminPhone);
  const [bread, extras, food] = await Promise.all([
    _resetCollectionSoldToday('bread_products'),
    _resetCollectionSoldToday('extra_products'),
    _resetCollectionSoldToday('food_inventory'),
  ]);
  return { ok: true, bread, extras, food };
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
    await deliverAdminNewsPush(snap.ref, d);
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

    // 3. ads (ИШ ТОП) — muddati o'tgan active → completed
    const expiredAdsSnap = await db.collection('ads')
      .where('status', '==', 'active')
      .where('expiresAt', '<', now)
      .get();

    const allDocs = [
      ...pendingSnap.docs,
      ...searchingSnap.docs,
    ];

    let batch = db.batch();
    let writes = 0;

    // trips → expired
    for (const doc of allDocs) {
      batch.update(doc.ref, {
        status: 'expired',
        expiredAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      writes++;
      if (writes >= 450) {
        await batch.commit();
        batch = db.batch();
        writes = 0;
      }
    }

    if (writes > 0) {
      await batch.commit();
      batch = db.batch();
      writes = 0;
    }

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
      batch.update(doc.ref, {
        status: 'completed',
        autoExpiredAt: admin.firestore.FieldValue.serverTimestamp(),
        editedAt: admin.firestore.FieldValue.serverTimestamp(),
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

    console.log(`expirePendingTrips: trips=${allDocs.length}, intercity=${intercitySnap.size}`);
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
 * One-time migration: set titleLower on cheap_product ads missing it.
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
        const lower = (d.titleLower || '').toString();
        if (!title || lower) continue;
        batch.update(doc.ref, { titleLower: title.toLowerCase() });
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
