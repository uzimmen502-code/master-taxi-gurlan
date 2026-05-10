const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

const db = admin.firestore();

function digits(v) {
  return String(v || '').replace(/[^\d]/g, '');
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
    if (!token) return;

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

    await admin.messaging().send({
      token,
      notification: { title, body },
      data: { type: 'order', status: after.status },
      android: { priority: 'high' },
    });
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
    if (!token) return;

    let title = '', body = '';
    switch (after.status) {
      case 'accepted':
        title = '🚕 Ҳайдовчи топилди!';
        body  = `${after.acceptedDriverName || ''} • ${after.acceptedDriverCar || ''}`;
        break;
      case 'completed':
        title = '✅ Сафар якунланди!';
        body  = 'Яхши сафар бўлди!';
        break;
      case 'cancelled':
        title = '❌ Сафар бекор қилинди';
        body  = 'Яна уриниб кўринг';
        break;
      default: return;
    }

    await admin.messaging().send({
      token,
      notification: { title, body },
      data: { type: 'trip', status: after.status },
      android: { priority: 'high' },
    });
  });

// Админ/мижоз чат хабарлари учун push
exports.onSupportChatMessageCreate = functions.firestore
  .document('support_chats/{chatId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
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