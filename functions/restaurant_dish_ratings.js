/**
 * KAFE-RESTORAN — taom bahosi (D-REST-18, docs/kafe_restoran_taklifi_uz.md §10.1).
 *
 * Ega qarori (2026-10-19): bahoni mijoz TAOMGA 1–5 qo'yadi, FAQAT yetkazilgan (`delivered`)
 * buyurtma bo'yicha. «Yangi» belgisi (<5 baho) va «Arzon» bo'limi tartibi shu baholarga tayanadi (S3).
 *
 * Ma'lumot modeli (menyu hujjatiga YOZILMAYDI — `menu_items` qoidasi `hasOnly`, 20-qoida):
 *   - `restaurant_dish_ratings/{orderId}_{itemId}` — bitta buyurtmadagi bitta taomga BITTA baho.
 *     Hujjat identifikatori aniq (deterministik) → takroriy chaqiruv ikkinchi baho yaratmaydi
 *     (21-qoida). Baho o'zgarmaydi (birinchisi qoladi): aks holda sotuvchi bilan kelishib
 *     «qayta baholash» orqali reytingni aylantirish mumkin bo'lardi.
 *   - `restaurants/{rid}/menu_item_stats/{itemId}` — AGREGAT: `ratingSum`, `ratingCount` (butun
 *     sonlar; o'rtacha klientda/bo'limda hisoblanadi — float saqlanmaydi, 8-qoida ruhi).
 *     Hamma o'qiydi, yozuv faqat shu funksiya.
 *   - `orders/{id}.dishRatings` { itemId: stars } — mijoz ekrani qaysi taom baholanganini bilishi
 *     uchun (buyurtmani faqat egasi o'qiydi) + `order_events` ga `dish_rated` yozuvi (16-qoida).
 *
 * Xavfsizlik (18, 19, 22-qoida): kim ekani `callerPhone`dan; buyurtma egasi ekani
 * `orders.userPhone` bilan solishtiriladi; taom albatta SHU buyurtma `items`ida bo'lishi shart;
 * hamma o'qishlar yozishdan oldin tranzaksiyada; o'z restoraniga buyurtma berish `placeRestaurantOrder`da
 * taqiqlangan, shuning uchun sotuvchi o'z taomini baholay olmaydi.
 *
 * Diagnostika kodlari (`details.code`): AUTH_REQUIRED, PHONE_TOKEN_REQUIRED, ORDER_ID_REQUIRED,
 * RATINGS_REQUIRED, RATING_INVALID, ORDER_NOT_FOUND, NOT_ORDER_OWNER, NOT_RESTAURANT_ORDER,
 * ORDER_NOT_DELIVERED, RATING_WINDOW_CLOSED, ITEM_NOT_IN_ORDER, CONTENTION_RETRY.
 * Foydalanuvchi matni klientda, 3 tilda (25-qoida). Log'da telefon YO'Q (24, 40-qoida).
 */
'use strict';

const ORDERS = 'orders';
const ORDER_EVENTS = 'order_events';
const RATINGS = 'restaurant_dish_ratings';
const RESTAURANTS = 'restaurants';
const STATS = 'menu_item_stats';
const MODULE_ID = 'restaurants';

const MAX_RATINGS = 30; // placeRestaurantOrder MAX_ITEMS bilan bir xil
/**
 * Baholash muddati: yetkazilgandan keyin 30 daqiqa (ega, 2026-10-19: «30 daqiqa qo'y, baho
 * qo'yilsa qo'yildi, bo'lmasa yo'q»). Klientdagi `dishRatingWindow` shuning nusxasi — o'zgarsa
 * ikkalasi birga (test mosligini tekshiradi).
 */
const RATING_WINDOW_MIN = 30;

/** Muddat ochiqmi: yetkazilgan vaqt noma'lum yoki kelajakda bo'lsa — YOPIQ (xavfsiz tomon). */
function ratingWindowOpen(deliveredMs, nowMs) {
  if (!Number.isFinite(deliveredMs) || deliveredMs <= 0) return false;
  const age = nowMs - deliveredMs;
  return age >= 0 && age <= RATING_WINDOW_MIN * 60 * 1000;
}
const ITEM_ID_RE = /^[A-Za-z0-9_-]{1,64}$/;

function str(v, max) {
  return String(v == null ? '' : v).trim().slice(0, max);
}

/** `{orderId}_{itemId}` — baho hujjatining yagona identifikatori. */
function ratingDocId(orderId, itemId) {
  return `${orderId}_${itemId}`;
}

/** Faqat HAQIQIY butun son 1..5 (`'5'` satri, 4.5, NaN — rad). */
function validStars(v) {
  return typeof v === 'number' && Number.isInteger(v) && v >= 1 && v <= 5;
}

function attachRestaurantDishRatings(exportsObj, deps) {
  const { functions, db, admin, callerPhone, canonicalUid, now: nowFn } = deps;
  const now = nowFn || (() => new Date());
  const HttpsError = functions.https.HttpsError;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const inc = (n) => admin.firestore.FieldValue.increment(n);
  const fail = (status, code, extra = {}) => new HttpsError(status, code, { code, ...extra });

  function log(action, fields) {
    console.log(JSON.stringify({ module: MODULE_ID, action, ...fields }));
  }

  function requirePhoneUid(context) {
    if (!context || !context.auth) throw fail('unauthenticated', 'AUTH_REQUIRED');
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length < 12) throw fail('unauthenticated', 'PHONE_TOKEN_REQUIRED');
    return uid;
  }

  /**
   * Mijoz yetkazilgan buyurtmadagi taomlarga baho qo'yadi.
   * data: { orderId, ratings: [{ itemId, stars }] }
   * → { ok, saved: [itemId], alreadyRated: [itemId] }
   *
   * Takroriy chaqiruv xavfsiz: bahosi bor taom o'tkazib yuboriladi (`alreadyRated`),
   * agregat ikki marta oshmaydi.
   */
  exportsObj.submitDishRatings = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    const d = data || {};
    const orderId = str(d.orderId, 64);
    if (!orderId) throw fail('invalid-argument', 'ORDER_ID_REQUIRED');
    const rawList = Array.isArray(d.ratings) ? d.ratings : [];
    if (rawList.length < 1) throw fail('invalid-argument', 'RATINGS_REQUIRED');
    if (rawList.length > MAX_RATINGS) throw fail('invalid-argument', 'RATING_INVALID');

    // Bir taom ikki marta kelsa — birinchisi hisobga olinadi (qolgani e'tiborsiz).
    const wanted = new Map();
    for (const r of rawList) {
      const itemId = str(r && r.itemId, 64);
      if (!ITEM_ID_RE.test(itemId) || !validStars(r && r.stars)) throw fail('invalid-argument', 'RATING_INVALID');
      if (!wanted.has(itemId)) wanted.set(itemId, r.stars);
    }

    const orderRef = db.collection(ORDERS).doc(orderId);

    const run = () => db.runTransaction(async (t) => {
      // ── O'QISH fazasi ──
      const orderSnap = await t.get(orderRef);
      if (!orderSnap.exists) throw fail('not-found', 'ORDER_NOT_FOUND');
      const od = orderSnap.data() || {};
      if (canonicalUid(String(od.userPhone || '')) !== uid) throw fail('permission-denied', 'NOT_ORDER_OWNER');
      if (od.type !== 'restaurant' || !od.restaurantId) throw fail('failed-precondition', 'NOT_RESTAURANT_ORDER');
      if (od.restaurantStatus !== 'delivered') throw fail('failed-precondition', 'ORDER_NOT_DELIVERED');
      const inOrder = new Set((Array.isArray(od.items) ? od.items : []).map((it) => String(it && it.itemId || '')));
      for (const itemId of wanted.keys()) {
        if (!inOrder.has(itemId)) throw fail('failed-precondition', 'ITEM_NOT_IN_ORDER', { itemId });
      }
      const ids = [...wanted.keys()];
      const existing = await Promise.all(ids.map((id) => t.get(db.collection(RATINGS).doc(ratingDocId(orderId, id)))));

      // Muddat: faqat YANGI baho uchun tekshiriladi — bahosi bor taom uchun takroriy chaqiruv
      // (tarmoq uzilib qayta yuborilgan) muddatdan keyin ham xatosiz `alreadyRated` qaytaradi.
      const hasNew = existing.some((s) => !s.exists);
      if (hasNew) {
        const at = od.deliveredAt || od.statusUpdatedAt;
        const deliveredMs = at && typeof at.toMillis === 'function' ? at.toMillis() : Number.NaN;
        if (!ratingWindowOpen(deliveredMs, now().getTime())) {
          throw fail('failed-precondition', 'RATING_WINDOW_CLOSED', { windowMin: RATING_WINDOW_MIN });
        }
      }

      // ── YOZISH fazasi ──
      const saved = [];
      const alreadyRated = [];
      const patch = {};
      ids.forEach((itemId, i) => {
        if (existing[i].exists) {
          alreadyRated.push(itemId);
          return;
        }
        const stars = wanted.get(itemId);
        t.set(db.collection(RATINGS).doc(ratingDocId(orderId, itemId)), {
          orderId, itemId, restaurantId: od.restaurantId, userId: uid, stars, createdAt: ts(),
        });
        t.set(
          db.collection(RESTAURANTS).doc(od.restaurantId).collection(STATS).doc(itemId),
          { ratingSum: inc(stars), ratingCount: inc(1), updatedAt: ts() },
          { merge: true },
        );
        patch[`dishRatings.${itemId}`] = stars;
        saved.push(itemId);
      });
      if (saved.length > 0) {
        t.update(orderRef, { ...patch, updatedAt: ts() });
        t.set(orderRef.collection(ORDER_EVENTS).doc(), {
          from: od.restaurantStatus, to: od.restaurantStatus, actor: 'customer', actorId: uid,
          reason: 'dish_rated', meta: { items: saved.length }, at: ts(),
        });
      }
      return { saved, alreadyRated, restaurantId: od.restaurantId };
    });

    // Parallel chaqiruvda tranzaksiya XOM xato bilan yiqilishi mumkin — tranzaksiya
    // takrorlanuvchan (mavjud baho o'tkazib yuboriladi), shuning uchun 3 martagacha qayta uramiz.
    let out = null;
    let failure = null;
    for (let attempt = 1; attempt <= 3 && !out && !failure; attempt += 1) {
      try {
        out = await run();
      } catch (e) {
        if (e instanceof HttpsError) failure = e;
        else if (attempt === 3) failure = fail('aborted', 'CONTENTION_RETRY');
      }
    }
    if (failure) {
      log('rate_dishes', {
        orderId, userId: uid, result: 'denied',
        errorCode: (failure.details && failure.details.code) || 'ABORTED', durationMs: Date.now() - t0,
      });
      throw failure;
    }
    log('rate_dishes', {
      orderId, restaurantId: out.restaurantId, userId: uid, result: 'ok',
      saved: out.saved.length, alreadyRated: out.alreadyRated.length, durationMs: Date.now() - t0,
    });
    return { ok: true, saved: out.saved, alreadyRated: out.alreadyRated };
  });
}

module.exports = {
  attachRestaurantDishRatings,
  ratingDocId,
  validStars,
  ratingWindowOpen,
  RATING_WINDOW_MIN,
  MAX_RATINGS,
};
