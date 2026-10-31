/**
 * Курьерлар рўйхати — ФАҚАТ ЎҚИШ (эга, 2026-10-31: «ҳозиргилар тест учун қўйилганлар, уларни ўчириб ташлаймиз»).
 * Ўчиришдан ОЛДИН эга рўйхатни кўриб тасдиқлаши учун (28-банд). Ҳеч нарса ёзмайди.
 *
 * Манбалар: `provider_capabilities` (status.courier бор ҳужжатлар) → `users` (исм, телефон охирги 4 рақами),
 * фаол иш: `delivery_routes` (ready/active), `collection_tasks` (assigned/collecting),
 * ресторан `orders` (courierId, якунланмаган), `courier_cash` ҳисоб қолдиғи.
 *
 * Ишлатиш: node functions/tools/list_couriers_readonly.js
 */
'use strict';
const path = require('path');
const admin = require('firebase-admin');

async function main() {
  admin.initializeApp({ credential: admin.credential.cert(require(path.join(__dirname, '..', 'service-account.json'))) });
  const db = admin.firestore();
  const caps = await db.collection('provider_capabilities').get();
  const rows = [];
  for (const d of caps.docs) {
    const c = d.data() || {};
    const st = c.status && c.status.courier;
    if (!st) continue;
    const uid = String((c.identity && c.identity.primaryUid) || '');
    let name = '';
    if (uid) {
      const u = await db.collection('users').doc(uid).get();
      if (u.exists) name = String((u.data() || {}).name || (u.data() || {}).fullName || '');
    }
    const ids = uid ? [uid, uid.length === 12 ? uid.slice(3) : uid] : [];
    let routes = 0;
    let tasks = 0;
    let restaurant = 0;
    for (const id of [...new Set(ids)]) {
      routes += (await db.collection('delivery_routes').where('courierId', '==', id)
        .where('status', 'in', ['ready', 'active']).get()).size;
      tasks += (await db.collection('collection_tasks').where('courierId', '==', id)
        .where('status', 'in', ['assigned', 'collecting']).get()).size;
      restaurant += (await db.collection('orders').where('type', '==', 'restaurant')
        .where('courierId', '==', id).get()).docs
        .filter((o) => !['delivered', 'delivery_failed', 'cancelled'].includes(String((o.data() || {}).restaurantStatus || ''))).length;
    }
    const cashAcc = uid ? await db.collection('ledger_accounts').doc(`courier_cash:${uid}`).get() : null;
    rows.push({
      accountId: d.id,
      phoneLast4: uid ? uid.slice(-4) : '',
      name,
      status: st,
      active: c.courier ? c.courier.active === true : null,
      activeRoutes: routes,
      activeCollectionTasks: tasks,
      openRestaurantOrders: restaurant,
      courierCashBalance: cashAcc && cashAcc.exists ? (cashAcc.data() || {}).balance || 0 : 0,
    });
  }
  console.log(JSON.stringify({ count: rows.length, rows }, null, 2));
}
main().catch((e) => { console.error(e); process.exit(1); });
