const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

const db = admin.firestore();

function digits(v) {
  return String(v || '').replace(/[^\d]/g, '');
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

// Буюртма статуси ўзгарганда
exports.onOrderUpdate = functions.firestore
  .document('orders/{orderId}')
  .onUpdate(async (change) => {
    const before = change.before.data();
    const after  = change.after.data();
    if (before.status === after.status) return;

    const uid   = (after.userPhone || '').replace(/[^\d]/g, '');
    const user  = await admin.firestore().collection('users').doc(uid).get();
    const token = user.data()?.fcmToken;

    let title = '', body = '';
    switch (after.status) {
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
      case 'delivered':
        title = '🟢 Буюртма етказилди!';
        body  = 'Раҳмат!';
        break;
      default: return;
    }

    const chatText = `${title}\n${body}`.trim();
    await appendSystemSupportChatMessage(uid, chatText);

    const fcmTitle = `📢 Админ: ${title}`;
    const fcmBody = body || 'Хабар';

    if (token) {
      await admin.messaging().send({
        token,
        notification: { title: fcmTitle, body: fcmBody },
        data: { type: 'order', status: after.status },
        android: { priority: 'high' },
      });
    }
  });

// Янги буюртма — админ / dispatcher FCM
exports.onOrderCreate = functions.firestore
  .document('orders/{orderId}')
  .onCreate(async (snap) => {
    const order = snap.data() || {};
    const orderType = order.type || 'buyurtma';
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

    if (tokens.length === 0) return null;

    const messages = tokens.map((token) => ({
      token,
      notification: { title, body },
      data: { type: 'new_order', orderId: snap.id, orderType: String(orderType) },
      android: { priority: 'high' },
    }));

    try {
      await admin.messaging().sendEach(messages);
    } catch (e) {
      console.error('onOrderCreate xato:', e);
    }
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

// Такси статуси ўзгарганда
exports.onTripUpdate = functions.firestore
  .document('trips/{tripId}')
  .onUpdate(async (change) => {
    const before = change.before.data();
    const after  = change.after.data();
    if (before.status === after.status) return;

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
      await admin.messaging().send({
        token,
        notification: { title: fcmTitle, body: fcmBody },
        data: { type: 'trip', status: after.status },
        android: { priority: 'high' },
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
    if (role !== 'admin' && role !== 'superadmin') {
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
  const userPhone = String(data.userPhone || '');
  const orderTotal = parseInt(String(data.orderTotal ?? 0), 10);
  const cashPaid = parseInt(String(data.cashPaid ?? 0), 10);
  const refType = String(data.refType || 'order');
  const refId = String(data.refId || '');
  const module = String(data.module || 'bread');
  const idempotencyKey = String(data.idempotencyKey || '').trim();
  const operatorPhone = data.operatorPhone != null ? String(data.operatorPhone) : '';

  if (!idempotencyKey) {
    throw new functions.https.HttpsError('invalid-argument', 'idempotencyKey required');
  }
  if (operatorPhone) {
    await assertAdminOrDriver(operatorPhone);
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
      createdBy: operatorPhone ? digits(operatorPhone) : 'client',
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
  const adminPhone = String(data.adminPhone || '');
  await assertAdmin(adminPhone);

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
      createdBy: digits(adminPhone),
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
  const adminPhone = String(data.adminPhone || '');
  await assertAdmin(adminPhone);

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
      createdBy: digits(adminPhone),
    });

    t.update(reqRef, {
      status: 'completed',
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
      processedBy: digits(adminPhone),
    });

    t.set(idemRef, {
      type: 'confirmPayout',
      result: { ok: true, ledgerId },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { ok: true };
});

/** Админ: чиқариш талабини рад этиш */
exports.rejectPayout = functions.https.onCall(async (data, context) => {
  const adminPhone = String(data.adminPhone || '');
  await assertAdmin(adminPhone);

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
    rejectedBy: digits(adminPhone),
  });

  return { ok: true };
});

/** Mobil/web: PIN bilan `users/{phone}.role = admin` (Firestore rules client'dan role yozmaydi). */
exports.promoteToAdminWithPin = functions.https.onCall(async (data, context) => {
  const pin = String(data.pin || '').trim();
  const ADMIN_PIN = '2024';
  if (pin !== ADMIN_PIN) {
    throw new functions.https.HttpsError('permission-denied', 'PIN-kod xato');
  }
  const phone = digits(data.phone || data.userPhone || '');
  if (phone.length < 9) {
    throw new functions.https.HttpsError('invalid-argument', 'Telefon raqami noto\'g\'ri');
  }
  const ref = db.collection('users').doc(phone);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Bu telefon Firestore\'da yo\'q. Avval ilovada ro\'yxatdan o\'ting.',
    );
  }
  const currentRole = String((snap.data() || {}).role || 'user');
  if (currentRole === 'admin' || currentRole === 'superadmin') {
    return { ok: true, alreadyAdmin: true, uid: phone };
  }
  await ref.set({
    role: 'admin',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, uid: phone };
});

/** Operator chat javobi — PIN + Admin SDK (client Firestore rules bypass). */
exports.sendSupportChatReply = functions.https.onCall(async (data, context) => {
  const ADMIN_PIN = '2024';
  const pin = String(data.pin || '').trim();
  if (pin !== ADMIN_PIN) {
    throw new functions.https.HttpsError('permission-denied', 'PIN-код xато');
  }
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

// ─── Trip + Booking TTL cleanup ───────────────────────────────────────────────
// Har 1 daqiqada: muddati o'tgan pending/searching trips va intercity bronlarni yopish
exports.expirePendingTrips = functions.pubsub
  .schedule('every 1 minutes')
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    // 1. trips kolleksiyasi (local taxi + marshrut)
    const [pendingSnap, searchingSnap] = await Promise.all([
      db.collection('trips').where('status', '==', 'pending')
        .where('expiresAt', '<', now).get(),
      db.collection('trips').where('status', '==', 'searching')
        .where('expiresAt', '<', now).get(),
    ]);

    // 2. intercity_bookings — pending/confirmed, muddati o'tgan
    const intercitySnap = await db.collection('intercity_bookings')
      .where('status', 'in', ['pending', 'confirmed'])
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

    // intercity_bookings → expired + seat qaytarish
    for (const doc of intercitySnap.docs) {
      const booking = doc.data();
      const passengers = booking.passengers || 1;
      const driverId = booking.driverId || '';

      batch.update(doc.ref, {
        status: 'expired',
        expiredAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // O'rinni qaytarish (agar haqiqiy driver bo'lsa)
      if (driverId && !['1', '2', '3', '4', '5'].includes(driverId)) {
        const driverRef = db.collection('intercity_drivers').doc(driverId);
        batch.update(driverRef, {
          seats: admin.firestore.FieldValue.increment(passengers),
        });
      }

      writes++;
      if (writes >= 450) {
        await batch.commit();
        batch = db.batch();
        writes = 0;
      }
    }

    if (writes > 0) await batch.commit();
    console.log(`expirePendingTrips: trips=${allDocs.length}, intercity=${intercitySnap.size}`);
    return null;
  });

// ONE-TIME: `food_catalog` — seed. Bir marta HTTP GET qiling, keyin exportni o‘chirib qayta deploy.
exports.seedFoodCatalog = functions
  .runWith({ timeoutSeconds: 120, memory: '256MB' })
  .https.onRequest(async (_req, res) => {
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
