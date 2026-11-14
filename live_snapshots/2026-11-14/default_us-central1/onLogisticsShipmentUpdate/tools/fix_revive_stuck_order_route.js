/**
 * FIX: "Курьерда" қотиб қолган in_delivery/arrived буюртма учун курьерга
 * фаол (active) маршрут тиклайди, токи курьер иловасида кўриниб тўлов қилсин.
 *
 * Foydalanish:
 *   node tools/fix_revive_stuck_order_route.js <orderId> <courierDigits>
 *   (default: GU7PcsG33zCOlAn67AwC 998920224017)
 */
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

const orderId = process.argv[2] || 'GU7PcsG33zCOlAn67AwC';
const courierId = (process.argv[3] || '998920224017').replace(/\D/g, '');

async function main() {
  const orderRef = db.collection('orders').doc(orderId);
  const snap = await orderRef.get();
  if (!snap.exists) {
    console.log('❌ Buyurtma topilmadi:', orderId);
    return;
  }
  const od = snap.data() || {};
  console.log('Buyurtma holati:', {
    status: od.status,
    fulfillmentStatus: od.fulfillmentStatus,
    paymentStatus: od.paymentStatus,
    courierId: od.courierId,
  });

  if (od.paymentStatus === 'paid') {
    console.log('ℹ️  Buyurtma allaqachon to\'langan — fix kerak emas.');
    return;
  }
  if (od.status !== 'in_delivery') {
    console.log(`⚠️  Buyurtma status="${od.status}" (in_delivery emas). To\'xtatildi.`);
    return;
  }

  // Курьерда аллақачон фаол маршрут борми?
  const activeSnap = await db.collection('delivery_routes')
    .where('courierId', '==', courierId)
    .where('status', '==', 'active')
    .limit(1)
    .get();
  if (!activeSnap.empty) {
    console.log('⚠️  Курьерда фаол маршрут бор:', activeSnap.docs[0].id, '— қўлда текширинг.');
    return;
  }

  const routeRef = db.collection('delivery_routes').doc();
  await db.runTransaction(async (t) => {
    t.set(routeRef, {
      orders: [orderId],
      courierId,
      status: 'active',
      currentIndex: 0,
      routeSource: 'manual_fix_revive',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    t.update(orderRef, {
      courierId,
      deliveryRouteId: routeRef.id,
      // fulfillmentStatus 'arrived' o'zgarmaydi — kuryer to'g'ridan-to'g'ri "To'lov" qiladi.
      statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  console.log('✅ Faol marshrut tiklandi:', routeRef.id);
  console.log('   Endi kuryer ilovasida 1 ta buyurtma ko\'rinadi → "To\'lov" → "Yakunlash".');
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
