'use strict';

/**
 * KURYER AVTORIZATSIYASI — ikki rejim (D-CLEAN-1; ega qarori 2026-10-07).
 *
 *   'new'    — YANGI ish olish (marshrut yaratish, gilam/sut vazifasini
 *              olish): capability ISHLAYDIGAN holatda (`isWorking`).
 *   'finish' — BOSHLANGAN ishni tugatish (olib ketdim, yetib keldim,
 *              to'lov, yig'ib olish yakuni): `suspended` ham o'tadi —
 *              ega qarori «to'xtatilgan kuryer qo'lidagi reysni tugatishi
 *              kerak» (15-qoida: custody uzilmasin; `canFinishActive`).
 *              Faqat `not_registered` yopiq.
 *
 * 'finish' rejimi o'zi yetarli EMAS: buyurtma shu kuryerning FAOL
 * marshrutida bo'lishi shart (`assertOrderOnActiveRoute`). Marshrutning
 * `courierId`sini faqat admin yoki server yozadi (`firestore.rules`
 * `delivery_routes`: create — admin, kuryer `courierId`ni o'zgartira
 * olmaydi), shuning uchun bu tekshiruvga ishonish mumkin.
 *
 * Tranzaksiya ichida yakuniy tekshiruv — `assertOrderActionable`: buyurtma
 * boshqa kuryerga biriktirilmagan (`COURIER_ASSIGNMENT_CONFLICT`) va
 * kuryer o'zi mijoz emas (`COURIER_OWN_ORDER`, ega qarori 2026-10-08).
 *
 * Nega kerak bo'ldi: `courierMarkPicked` / `courierMarkArrived` /
 * `courierSubmitPayment` hech qanday huquq va egalik tekshirmasdi —
 * ilovaga kirgan har kim o'z buyurtmasini «yetkazildi» qilib, ortiqcha
 * «naqd»ni qaytim sifatida o'z hamyoniga yoza olardi. O'zini `trial`
 * kuryer qilgan odam esa marshrut orqali ham shuni qila olardi — shuning
 * uchun «kuryer ≠ mijoz».
 *
 * Kuryer ID'lari bazada 9 va 12 xonali shaklda uchraydi — ikkalasi ham
 * qaraladi, natija doim kanon (12 xonali).
 */

const MODES = Object.freeze({ new: 'new', finish: 'finish' });
const ACTIVE_ROUTE_STATUSES = ['ready', 'active'];

/**
 * @param {object} deps
 * @param {FirebaseFirestore.Firestore} deps.db
 * @param {object} deps.caps `capabilities_model.js`
 * @param {(v: string) => string} deps.canonicalUid 12 xonali shakl (9 xonaga `998` qo'shadi)
 * @param {Function} deps.HttpsError `functions.https.HttpsError`
 */
function makeCourierAuth(deps) {
  const { db, caps, canonicalUid, HttpsError } = deps;

  /** [12 xonali, 9 xonali] — eski hujjatlar 9 xonali kalitda bo'lishi mumkin. */
  const idForms = (phone) => {
    const uid12 = canonicalUid(phone);
    if (!/^\d{9,}$/.test(uid12)) throw new HttpsError('invalid-argument', 'courierPhone');
    return /^998\d{9}$/.test(uid12) ? [uid12, uid12.slice(3)] : [uid12];
  };

  /** `users/{tel}.accountId` → `provider_capabilities` → `status.courier`. */
  async function capabilityStatus(phone) {
    for (const id of idForms(phone)) {
      const userDoc = await db.collection('users').doc(id).get();
      if (!userDoc.exists) continue;
      const accountId = String((userDoc.data() || {}).accountId || '');
      if (!accountId) break;
      const cap = await db.collection('provider_capabilities').doc(accountId).get();
      return caps.statusOf(cap.exists ? (cap.data() || {}) : {}, 'courier');
    }
    return caps.COMMON.notRegistered;
  }

  /**
   * Kuryer huquqi rejim bo'yicha. Muvaffaqiyatda kanon ID qaytaradi.
   * Noma'lum rejim — eng qattiq ('new') deb olinadi.
   */
  async function resolve(phone, mode = MODES.new) {
    const status = await capabilityStatus(phone);
    const allowed = mode === MODES.finish
      ? caps.canFinishActive({ status: { courier: status } }, 'courier')
      : caps.isWorking('courier', status);
    if (!allowed) {
      throw new HttpsError('permission-denied', 'Courier not authorized');
    }
    return canonicalUid(phone);
  }

  /** Kuryerning `ready`/`active` marshrutlari (9 va 12 xonali `courierId`). */
  async function activeRoutes(phone) {
    const snaps = await Promise.all(idForms(phone).map((id) => db.collection('delivery_routes')
      .where('courierId', '==', id)
      .where('status', 'in', ACTIVE_ROUTE_STATUSES)
      .get()));
    return snaps.flatMap((s) => s.docs);
  }

  /** Buyurtma shu kuryerning faol marshrutidami — bo'lmasa `permission-denied`. */
  async function assertOrderOnActiveRoute(phone, orderId) {
    const id = String(orderId || '');
    const routes = await activeRoutes(phone);
    const hit = routes.find((r) => {
      const orders = (r.data() || {}).orders;
      return Array.isArray(orders) && orders.includes(id);
    });
    if (!hit) throw new HttpsError('permission-denied', 'Not your order');
    return hit;
  }

  /**
   * Mijoz shu kuryerning faol marshrutidagi biror buyurtma egasimi.
   * `courierGetCustomerWalletBalance` uchun: avval istalgan raqamning
   * hamyon qoldig'ini qaytarardi.
   */
  async function assertCustomerOnActiveRoute(phone, customerPhone) {
    const customer = canonicalUid(customerPhone);
    if (!customer) throw new HttpsError('invalid-argument', 'customerPhone required');
    const routes = await activeRoutes(phone);
    const orderIds = [...new Set(routes.flatMap((r) => {
      const orders = (r.data() || {}).orders;
      return Array.isArray(orders) ? orders.map(String) : [];
    }))];
    if (orderIds.length > 0) {
      const snaps = await db.getAll(...orderIds.map((oid) => db.collection('orders').doc(oid)));
      const match = snaps.some((s) => {
        if (!s.exists) return false;
        const od = s.data() || {};
        return canonicalUid(String(od.userPhone || od.phone || '')) === customer;
      });
      if (match) return;
    }
    throw new HttpsError('permission-denied', 'Not your customer');
  }

  /** Kuryer shu buyurtmaning MIJOZImi (9/12 xonali shakllar ham). */
  function isOwnOrder(od, courierPhone) {
    const customer = canonicalUid(String((od && (od.userPhone || od.phone)) || ''));
    return customer !== '' && customer === canonicalUid(courierPhone);
  }

  /**
   * TRANZAKSIYA ICHIDA o'qilgan buyurtma bo'yicha yakuniy tekshiruv
   * (`assertOrderOnActiveRoute`dan KEYIN):
   *   - boshqa kuryerga biriktirilgan → `COURIER_ASSIGNMENT_CONFLICT`
   *     (marshrut eskirgan yoki bitta buyurtma ikki marshrutda);
   *   - kuryer shu buyurtmaning MIJOZI → `COURIER_OWN_ORDER` (ega qarori
   *     2026-10-08): o'zini kuryer qilgan odam o'z buyurtmasidagi ortiqcha
   *     «naqd»ni qaytim sifatida o'z hamyoniga yoza olmasin.
   */
  function assertOrderActionable(od, courierPhone, action, orderId) {
    const me = canonicalUid(courierPhone);
    const assigned = canonicalUid(String((od && od.courierId) || ''));
    let errorCode = '';
    if (assigned && assigned !== me) errorCode = 'COURIER_ASSIGNMENT_CONFLICT';
    else if (isOwnOrder(od, courierPhone)) errorCode = 'COURIER_OWN_ORDER';
    if (!errorCode) return;
    console.warn(JSON.stringify({ action, orderId, result: 'denied', errorCode }));
    throw new HttpsError('permission-denied',
      errorCode === 'COURIER_OWN_ORDER' ? 'Own order' : 'Not your order', { reason: errorCode });
  }

  return {
    capabilityStatus, resolve, activeRoutes, assertOrderOnActiveRoute, assertCustomerOnActiveRoute,
    isOwnOrder, assertOrderActionable,
  };
}

module.exports = { MODES, ACTIVE_ROUTE_STATUSES, makeCourierAuth };
