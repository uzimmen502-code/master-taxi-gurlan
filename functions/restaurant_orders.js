/**
 * KAFE-RESTORAN — buyurtma zanjiri (default codebase, us-central1).
 *
 * Ega qarorlari D-REST-1…14 (2026-10-08, docs/kafe_restoran_taklifi_uz.md §10):
 *   - AVA to'lovga ARALASHMAYDI: taom puli mijozdan restoranga to'g'ridan-
 *     to'g'ri (karta/QR yoki naqd). Bu yerda taom puli uchun ledger yozuvi
 *     YO'Q — faqat holat (`paymentStatus`) va hodisa (`order_events`).
 *   - AVA ulushi = taom summasining 2 % — QABUL QILISHDA restoran egasining
 *     AVA hamyonidan (`passenger_credit:{ownerUid}` → `earnings:ava_restaurant_fee`),
 *     bekor/yetkazilmasa — qaytariladi. Taxi billing bilan bir xil yondashuv.
 *   - Yetkazish narxi (AVA kuryeri) — masofa tarifi, versiya bilan
 *     (`restaurant_delivery_tariff.js`); mijoz → kuryer (naqd yoki hamyon→hamyon).
 *   - Restoran o'z kuryeri bilan ham yetkazadi; olib ketish ham bor.
 *   - Naqd AVA kuryeri orqali = kuryer VYKUPI (kuryer restoranga o'z pulini
 *     beradi, mijozdan jami summani oladi) — faqat yoqqan kuryerga, limit bilan.
 *
 * Holatlar — BITTA jadval (`restaurantStatus`), eski `status`/`fulfillmentStatus`
 * undan hosil qilinadi (mavjud ekranlar va admin doskasi uchun):
 *   placed → accepted | rejected | cancelled
 *   accepted → ready | rejected
 *   ready → picked (AVA kuryeri) | delivered (o'z kuryeri / olib ketish) | rejected
 *   picked → arrived | delivery_failed
 *   arrived → delivered | delivery_failed
 * Noqonuniy o'tish — `ORDER_INVALID_TRANSITION`. Har o'tish tranzaksiyada va
 * `orders/{id}/order_events` ga yoziladi (16, 17-qoida).
 *
 * `orders` hujjati qayta ishlatiladi (`type: 'restaurant'`): kuryer marshruti
 * (`delivery_routes`), mijoz «Buyurtmalar» ekrani, admin doskasi o'zgarmaydi.
 * Mavjud `courierSubmitPayment` / `courierCreateRoute` / `customerCancelOrder`
 * restoran buyurtmasini RAD ETADI (index.js dagi gardlar) — ular AVA o'zi
 * sotuvchi bo'lgan non/taom uchun; bu yerda taom puli AVA niki emas.
 *
 * Diagnostika kodlari (`details.code`) — foydalanuvchi matni klientda, uch
 * tilda (25-qoida). Structured log: orderId, restaurantId, userId, action,
 * result, errorCode — telefon/manzil YO'Q (24, 40-qoida).
 */
'use strict';

const crypto = require('crypto');
const geoHash = require('./geo_hash');
const tariff = require('./restaurant_delivery_tariff');
const localTaxi = require('./local_taxi');

const RESTAURANTS = 'restaurants';
const MEMBERS = 'members';
const MENU_ITEMS = 'menu_items';
const PRIVATE = 'private';
const ORDERS = 'orders';
const ORDER_EVENTS = 'order_events';
const ROUTES = 'delivery_routes';
const IDEMPOTENCY = 'wallet_idempotency';
const CUSTOMER_STATS = 'restaurant_customer_stats';
const COURIER_PREFS = 'restaurant_courier_prefs';
/** Yetkazish tarifi tarixi — o'zgarmas `v{n}` hujjatlar (local_taxi_tariffs namunasi). */
const TARIFF_HISTORY = 'restaurant_delivery_tariffs';
const ADMIN_AUDIT = 'admin_audit';
const MODULE_CONFIG = ['module_config', 'restaurants_all'];
const TARIFF_DOC = ['settings', 'restaurant_delivery'];
const APP_SETTINGS = ['settings', 'app'];
const EARNINGS_ACCOUNT = 'earnings:ava_restaurant_fee';

const MODULE_ID = 'restaurants';
/** Restoran qabul qilish muddati (PROPOSED, Wolt 3 daq / §12.8 5 daq). */
const ACCEPT_TIMEOUT_MIN = 5;
/** Ketma-ket shuncha muddat o'tsa — restoran avtomatik pauzaga (PROPOSED). */
const AUTO_PAUSE_AFTER_TIMEOUTS = 3;
const AUTO_PAUSE_MIN = 30;
/** Mijoz shuncha marta eshikda olmasa — faqat oldindan to'lov (PROPOSED). */
const STRIKES_FOR_PREPAY_ONLY = 2;
const PREPAY_ONLY_DAYS = 30;
const MAX_ITEMS = 30;
const MAX_QTY = 50;
const MAX_PRICE = 50000000;
const PICKUP_CODE_ATTEMPTS = 5;
const NEARBY_RADIUS_KM_DEFAULT = 15;
const NEARBY_LIMIT = 100;
/** Kuryer push'i: eng yaqin nechta kuryer; bitta kuryerga ikki push orasidagi minimal vaqt. */
const COURIER_PUSH_MAX = 30;
const COURIER_PUSH_MIN_GAP_MS = 30 * 1000;
const TASHKENT_UTC_OFFSET_H = 5;

const RS = Object.freeze({
  placed: 'placed',
  accepted: 'accepted',
  ready: 'ready',
  picked: 'picked',
  arrived: 'arrived',
  delivered: 'delivered',
  rejected: 'rejected',
  cancelled: 'cancelled',
  deliveryFailed: 'delivery_failed',
});

const TRANSITIONS = Object.freeze({
  [RS.placed]: [RS.accepted, RS.rejected, RS.cancelled],
  [RS.accepted]: [RS.ready, RS.rejected],
  [RS.ready]: [RS.picked, RS.delivered, RS.rejected],
  [RS.picked]: [RS.arrived, RS.deliveryFailed],
  [RS.arrived]: [RS.delivered, RS.deliveryFailed],
  [RS.delivered]: [],
  [RS.rejected]: [],
  [RS.cancelled]: [],
  [RS.deliveryFailed]: [],
});

/** restaurantStatus → [status (legacy), fulfillmentStatus] — §5.3 jadvali. */
const LEGACY = Object.freeze({
  [RS.placed]: ['new', 'pending'],
  [RS.accepted]: ['accepted', 'confirmed'],
  [RS.ready]: ['ready', 'confirmed'],
  [RS.picked]: ['in_delivery', 'courier_picked'],
  [RS.arrived]: ['in_delivery', 'arrived'],
  [RS.delivered]: ['delivered', 'completed'],
  [RS.rejected]: ['rejected', 'cancelled'],
  [RS.cancelled]: ['cancelled', 'cancelled'],
  [RS.deliveryFailed]: ['cancelled', 'cancelled'],
});

const RESTAURANT_STATUS = Object.freeze({
  applied: 'applied', approved: 'approved', rejected: 'rejected',
  suspended: 'suspended', closed: 'closed',
});
const RESTAURANT_ADMIN_TRANSITIONS = Object.freeze({
  applied: ['approved', 'rejected'],
  rejected: ['approved'],
  approved: ['suspended', 'closed'],
  suspended: ['approved', 'closed'],
  closed: [],
});

const LEGAL_TYPES = ['individual', 'yatt', 'llc'];
const DELIVERY_MODES = ['ava_courier', 'own_courier', 'none'];
const FOOD_PAYMENT = ['prepay', 'cash_buyout', 'cash_to_restaurant'];
const DELIVERY_PAYMENT = ['cash', 'wallet', 'none'];
const FAIL_REASONS = ['customer_absent', 'customer_refused', 'courier_problem', 'other'];

function canTransition(from, to) {
  const allowed = TRANSITIONS[from];
  return !!allowed && allowed.includes(to);
}

function str(v, max) {
  return String(v == null ? '' : v).trim().slice(0, max);
}

function intOr(v, def, min, max) {
  if (v == null || v === '') return def;
  const n = Number(v);
  return Number.isInteger(n) && n >= min && n <= max ? n : def;
}

function validLatLng(lat, lng) {
  return Number.isFinite(lat) && Number.isFinite(lng)
      && Math.abs(lat) <= 90 && Math.abs(lng) <= 180
      && (Math.abs(lat) > 1e-6 || Math.abs(lng) > 1e-6);
}

/** 'HH:mm' → daqiqalar; noto'g'ri bo'lsa null. */
function hhmmToMin(s) {
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(s || '').trim());
  if (!m) return null;
  const h = Number(m[1]);
  const mi = Number(m[2]);
  if (h > 23 || mi > 59) return null;
  return h * 60 + mi;
}

/**
 * Ish vaqti (Toshkent). `openingHours` yo'q → doim ochiq. Yarim tundan
 * o'tadigan oraliq (close < open) ham qo'llanadi.
 */
function isOpenAt(openingHours, date) {
  if (!openingHours || typeof openingHours !== 'object') return true;
  const open = hhmmToMin(openingHours.open);
  const close = hhmmToMin(openingHours.close);
  if (open == null || close == null || open === close) return true;
  const nowMin = ((date.getUTCHours() + TASHKENT_UTC_OFFSET_H) % 24) * 60 + date.getUTCMinutes();
  return open < close ? (nowMin >= open && nowMin < close) : (nowMin >= open || nowMin < close);
}

function pickupCode() {
  return String(crypto.randomInt(0, 10000)).padStart(4, '0');
}

function attachRestaurantOrders(exportsObj, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, settlementLedger,
    requireCallerRoles, notifyUserInApp, notifyCourierArrivedToCustomer, axios,
    fetchRoute: fetchRouteOverride, now: nowFn, courierPush,
  } = deps;
  // `courierAuth` index.js da bu attach'dan KEYIN e'lon qilinadi (const, TDZ):
  // shuning uchun yuklashda emas, chaqiruvda olinadi (deps getter).
  const courierAuthOf = () => deps.courierAuth;
  const COURIER_AUTH_MODES = deps.COURIER_AUTH_MODES || { new: 'new', finish: 'finish' };
  const now = nowFn || (() => new Date());
  const HttpsError = functions.https.HttpsError;
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const inc = (n) => admin.firestore.FieldValue.increment(n);
  const tsOf = (d) => admin.firestore.Timestamp.fromDate(d);
  const fetchRoute = fetchRouteOverride
    || ((p) => localTaxi.fetchRouteViaGoogle(axios, p));

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

  /** `users/{12}` yoki eski `users/{9}` — mavjud hujjat ref'i. */
  async function findUserRef(uid12) {
    const ids = uid12.length === 12 && uid12.startsWith('998') ? [uid12, uid12.slice(3)] : [uid12];
    for (const id of ids) {
      const s = await db.collection('users').doc(id).get();
      if (s.exists) return { ref: s.ref, data: s.data() || {} };
    }
    return null;
  }

  // ── Modul darvozasi (42-qoida; logistics `stage`/`testerIds` namunasi) ──
  async function moduleAccess(uid) {
    const snap = await db.collection(MODULE_CONFIG[0]).doc(MODULE_CONFIG[1]).get();
    if (!snap.exists) return { allowed: false, stage: 'off', reason: 'MODULE_OFF' };
    const d = snap.data() || {};
    if (d.enabled === false) return { allowed: false, stage: 'off', reason: 'MODULE_OFF' };
    const cfg = (d[MODULE_ID] && typeof d[MODULE_ID] === 'object') ? d[MODULE_ID] : {};
    const stage = cfg.stage === 'public' ? 'public' : 'internal';
    if (stage === 'public') return { allowed: true, stage };
    const testers = Array.isArray(cfg.testerIds) ? cfg.testerIds.map((x) => canonicalUid(x)) : [];
    const ok = testers.includes(canonicalUid(uid));
    return { allowed: ok, stage, reason: ok ? null : 'MODULE_INTERNAL_ONLY' };
  }

  async function requireModule(uid) {
    const a = await moduleAccess(uid);
    if (!a.allowed) throw fail('failed-precondition', a.reason || 'MODULE_OFF', { stage: a.stage });
    return a;
  }

  // ── Umumiy yozuvlar ────────────────────────────────────────────────────
  function statusPatch(rs, extra = {}) {
    const [status, fulfillmentStatus] = LEGACY[rs];
    return {
      restaurantStatus: rs, status, fulfillmentStatus,
      statusUpdatedAt: ts(), updatedAt: ts(), ...extra,
    };
  }

  function addEvent(t, orderRef, { from, to, actor, actorId, reason = '', meta = {} }) {
    t.set(orderRef.collection(ORDER_EVENTS).doc(), {
      from: from || null, to, actor, actorId: actorId || null, reason, meta,
      at: ts(),
    });
  }

  function assertTransition(od, to, orderId) {
    const from = String(od.restaurantStatus || '');
    if (canTransition(from, to)) return from;
    log('transition', { orderId, result: 'denied', errorCode: 'ORDER_INVALID_TRANSITION', from, to });
    throw fail('failed-precondition', 'ORDER_INVALID_TRANSITION', { from, to });
  }

  /**
   * Buyurtmani kuryer marshrutidan olib tashlash (WRITE fazasi; `routeSnap`
   * READ fazasida o'qilgan). Bajariladigan buyurtma qolmasa (hammasi
   * `currentIndex`dan oldin — yakunlangan) marshrut ham yopiladi; aks holda
   * kuryer bo'sh «faol» marshrutda qolib, yangisini ololmas edi.
   */
  function detachFromRouteInTx(t, routeRef, routeSnap, orderId, reason) {
    if (!routeRef || !routeSnap || !routeSnap.exists) return { detached: false, routeCompleted: false };
    const rd = routeSnap.data() || {};
    const remaining = (Array.isArray(rd.orders) ? rd.orders : []).filter((id) => id !== orderId);
    const exhausted = remaining.length <= (Number(rd.currentIndex) || 0)
      && ['active', 'ready'].includes(String(rd.status || ''));
    t.update(routeRef, {
      orders: remaining, updatedAt: ts(),
      ...(exhausted ? { status: 'completed', completedAt: ts(), completedReason: reason } : {}),
    });
    return { detached: true, routeCompleted: exhausted };
  }

  /**
   * Tranzaksiya XOM xato bilan yiqilsa (ikki parallel chaqiruv — emulator va
   * serverda ham «ABORTED: contention» bo'lishi mumkin, Admin SDK qayta
   * urinishlari tugagach), buyurtmani BIR marta qayta o'qib, aniq kod
   * qaytaradi: natija klient uchun deterministik (22, 25-qoida).
   * `resolve(od)` — natija yoki HttpsError; `null` → xom xato `aborted` sifatida.
   */
  async function withContention(orderRef, action, run, resolve) {
    try {
      return await run();
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      const snap = await orderRef.get();
      const od = snap.exists ? (snap.data() || {}) : null;
      const out = od ? resolve(od) : null;
      log(action, { orderId: orderRef.id, result: 'contention', errorCode: out ? 'resolved' : 'ABORTED', message: String(e && e.message || e).slice(0, 120) });
      if (out) return out;
      throw fail('aborted', 'CONTENTION_RETRY');
    }
  }

  async function getOrderInTx(t, orderRef) {
    const s = await t.get(orderRef);
    if (!s.exists) throw fail('not-found', 'ORDER_NOT_FOUND');
    const od = s.data() || {};
    if (od.type !== 'restaurant') throw fail('failed-precondition', 'NOT_RESTAURANT_ORDER');
    return od;
  }

  /** Restoran a'zoligi — tranzaksiya READ fazasida. */
  async function requireMemberInTx(t, restaurantId, uid) {
    const rRef = db.collection(RESTAURANTS).doc(restaurantId);
    const [rSnap, mSnap] = await Promise.all([t.get(rRef), t.get(rRef.collection(MEMBERS).doc(uid))]);
    if (!rSnap.exists) throw fail('not-found', 'RESTAURANT_NOT_FOUND');
    if (!mSnap.exists) throw fail('permission-denied', 'NOT_RESTAURANT_MEMBER');
    return { rRef, r: rSnap.data() || {}, member: mSnap.data() || {} };
  }

  // ── AVA ulushi: hamyon ↔ ledger (D-REST-2, D-REST-3) ───────────────────
  /**
   * READ fazasi: komissiya uchun ledger holati. `charge` = true — yechish,
   * false — qaytarish. Idempotentlik: `restFee_{orderId}_v{n}` /
   * `restFeeRefund_{orderId}_v{n}` (bonus: prefiksi bilan jurnal).
   */
  async function prepareFeeInTx(t, od, orderId, charge) {
    const fee = od.avaFee || null;
    if (!fee || !Number.isInteger(fee.amount) || fee.amount <= 0) return null;
    if (!charge && !fee.charged) return null; // yechilmagan — qaytarilmaydi
    const walletUid = String(od.restaurantWalletUid || '');
    if (!walletUid) throw fail('failed-precondition', 'RESTAURANT_WALLET_UNKNOWN');
    const version = Number.isInteger(fee.version) ? fee.version : tariff.AVA_FEE_VERSION;
    const key = `${charge ? 'restFee' : 'restFeeRefund'}_${orderId}_v${version}`;
    const ctx = await settlementLedger.prepareBonusInTx(t, db, walletUid, {
      fundingAccount: EARNINGS_ACCOUNT, idempotencyKey: key,
    });
    return { ctx, fee, walletUid, charge, key };
  }

  /** WRITE fazasi. Yechishda qoldiq yetmasa — `RESTAURANT_WALLET_INSUFFICIENT`. */
  function commitFeeInTx(t, prep, { orderId, actorId }) {
    if (!prep) return { applied: false, amount: 0 };
    const { ctx, fee, walletUid, charge } = prep;
    if (ctx.jExists) return { applied: false, amount: fee.amount, idempotent: true };
    if (charge && ctx.pcPrev < fee.amount) {
      throw fail('failed-precondition', 'RESTAURANT_WALLET_INSUFFICIENT', {
        required: fee.amount, balance: ctx.pcPrev,
      });
    }
    const delta = charge ? -fee.amount : fee.amount;
    const kind = charge ? 'restaurant_fee' : 'restaurant_fee_refund';
    settlementLedger.commitBonusInTx(t, ctx, {
      delta, kind, refType: 'order', refId: orderId,
      meta: { module: MODULE_ID, basis: fee.basis, rateBps: fee.rateBps, version: fee.version },
      postedBy: actorId || 'system', postedRole: charge ? 'restaurant' : 'system',
    });
    const userRef = db.collection('users').doc(walletUid);
    // Ko'zgu — `postEntry(mirrorBonus)` bilan bir xil: increment + wallet_ledger.
    t.set(userRef, { bonusBalance: inc(delta), balanceUpdatedAt: ts() }, { merge: true });
    t.set(userRef.collection('wallet_ledger').doc(), {
      type: kind, amount: delta, module: MODULE_ID, refType: 'order', refId: orderId,
      meta: { basis: fee.basis, rateBps: fee.rateBps }, createdAt: ts(), createdBy: 'server',
    });
    return { applied: true, amount: fee.amount };
  }

  // ── Yetkazish narxi (D-REST-4) ─────────────────────────────────────────
  async function readTariffDoc() {
    const tariffSnap = await db.collection(TARIFF_DOC[0]).doc(TARIFF_DOC[1]).get();
    return tariffSnap.exists ? (tariffSnap.data() || {}) : {};
  }

  /** `preloaded` — chaqiruvchi hujjatni allaqachon o'qigan bo'lsa (ortiqcha o'qish yo'q). */
  async function quoteDelivery(r, { toLat, toLng }, preloaded) {
    const tariffData = preloaded || await readTariffDoc();
    const fromLat = Number(r.lat);
    const fromLng = Number(r.lng);
    if (!validLatLng(fromLat, fromLng)) throw fail('failed-precondition', 'RESTAURANT_LOCATION_MISSING');
    const regionKey = tariff.resolveRegionKey(fromLat, fromLng);
    const prices = tariff.resolveDeliveryPrices(tariffData, regionKey);
    if (!prices) throw fail('failed-precondition', 'TARIFF_NOT_CONFIGURED');

    let route = null;
    try {
      route = await fetchRoute({ fromLat, fromLng, toLat, toLng });
    } catch (e) {
      console.error('restaurant delivery route error:', e.message || e);
    }
    let distanceSource = 'route';
    if (!route || !(route.distanceMeters > 0)) {
      distanceSource = 'estimate';
      const straight = tariff.haversineMeters(fromLat, fromLng, toLat, toLng);
      route = { distanceMeters: Math.round((straight * prices.roadFactorPermille) / 1000) };
    }
    if (route.distanceMeters > prices.maxKm * 1000) {
      throw fail('failed-precondition', 'DELIVERY_TOO_FAR', { maxKm: prices.maxKm });
    }
    const at = now();
    const night = tariff.isNightAt(at, prices.nightStartH, prices.nightEndH);
    const r2 = tariff.computeDeliveryFee({ distanceMeters: route.distanceMeters, prices, night });
    return {
      deliveryFee: r2.fee,
      deliveryFeeSource: 'ava_tariff',
      deliveryTariffVersion: prices.version,
      deliveryTariffSnapshot: {
        regionKey: prices.regionKey, priceSource: prices.source,
        base: prices.base, perKm: prices.perKm, nightPermille: r2.nightPermille,
        nightStartH: prices.nightStartH, nightEndH: prices.nightEndH,
        roadFactorPermille: prices.roadFactorPermille, distancePart: r2.distancePart,
        night,
      },
      distanceMeters: route.distanceMeters,
      distanceSource,
    };
  }

  async function straightDistance(r, { toLat, toLng }) {
    const fromLat = Number(r.lat);
    const fromLng = Number(r.lng);
    if (!validLatLng(fromLat, fromLng)) return null;
    return tariff.haversineMeters(fromLat, fromLng, toLat, toLng);
  }

  // ── Xabarlar (best-effort, tranzaksiyadan tashqarida) ───────────────────
  async function notifyMembers(restaurantId, { title, body, orderId }) {
    try {
      const ms = await db.collection(RESTAURANTS).doc(restaurantId).collection(MEMBERS).limit(10).get();
      await Promise.all(ms.docs.map((m) => notifyUserInApp({
        userId: m.id, title, body, category: 'order', source: 'restaurant_order',
        // Лентада буюртма бўйича гуруҳланади (аввал `orderId`сиз — кўринмасди).
        extraNews: { orderId: String(orderId || ''), orderType: 'restaurant' },
        dataType: 'restaurant_order', screen: 'restaurant_orders',
        extraData: { orderId, restaurantId, ring: '1' },
        channelId: 'courier_arrival_alarm',
      })));
    } catch (e) {
      console.error('restaurant notifyMembers:', e.message || e);
    }
  }

  async function notifyCustomer(uid, { title, body, orderId }) {
    try {
      await notifyUserInApp({
        userId: uid, title, body, category: 'order', source: 'restaurant_order',
        extraNews: { orderId: String(orderId || ''), orderType: 'restaurant' },
        dataType: 'restaurant_order', screen: 'orders', extraData: { orderId },
      });
    } catch (e) {
      console.error('restaurant notifyCustomer:', e.message || e);
    }
  }

  /**
   * Yaqin ONLAYN kuryerlarga «buyurtma bor» taklifi (B5): qabulda va (kuryer
   * hali olmagan bo'lsa) tayyor bo'lganda. FAQAT FCM — `admin_news` yozilmaydi
   * (taklif vaqtinchalik; kuryer uni «Restoran buyurtmalari» ro'yxatida
   * baribir ko'radi), presence/token manbasi — `courier_push.js`.
   *   - radius `NEARBY_RADIUS_KM_DEFAULT`, eng yaqin `COURIER_PUSH_MAX` ta;
   *   - mijozning o'zi va restoran a'zolari — yo'q;
   *   - naqd (vykup) buyurtma — faqat limiti yetadigan kuryer;
   *   - har kuryerga `COURIER_PUSH_MIN_GAP_MS` dan tez-tez yo'q
   *     (`restaurant_courier_prefs.lastPushAt`, faqat server yozadi).
   * Xato push'ni to'xtatmaydi (log), asosiy amalga ta'sir qilmaydi.
   */
  async function notifyNearbyCouriers(orderId, od, stage) {
    const empty = { candidates: 0, notified: 0 };
    try {
      if (!courierPush || od.deliveryMode !== 'ava_courier' || od.courierId) return empty;
      const rLat = Number(od.restaurantLat);
      const rLng = Number(od.restaurantLng);
      if (!validLatLng(rLat, rLng)) return empty;
      const candidates = (await courierPush.onlineCouriers())
        .filter((c) => c.lat != null && c.lng != null)
        .map((c) => ({ ...c, distanceM: tariff.haversineMeters(rLat, rLng, c.lat, c.lng) }))
        .filter((c) => c.distanceM <= NEARBY_RADIUS_KM_DEFAULT * 1000)
        .sort((a, b) => a.distanceM - b.distanceM)
        .slice(0, COURIER_PUSH_MAX);
      if (candidates.length === 0) return empty;
      const customer = canonicalUid(String(od.userPhone || od.phone || ''));
      const membersSnap = await db.collection(RESTAURANTS).doc(String(od.restaurantId || '')).collection(MEMBERS).get();
      const members = new Set(membersSnap.docs.map((m) => canonicalUid(m.id)));
      const buyout = od.foodPaymentMethod === 'cash_buyout';
      const foodAmount = (Number(od.itemsTotal) || 0) + (Number(od.packagingTotal) || 0);
      const fee = Number(od.deliveryFee) || 0;
      const nowMs = now().getTime();
      let notified = 0;
      for (const c of candidates) {
        if (c.id === customer || members.has(c.id)) continue;
        const prefRef = db.collection(COURIER_PREFS).doc(c.id);
        const prefSnap = await prefRef.get();
        const p = prefSnap.exists ? (prefSnap.data() || {}) : {};
        if (buyout) {
          const limit = p.buyoutEnabled === true ? intOr(p.buyoutLimit, 0, 0, 100000000) : 0;
          if (foodAmount > limit) continue;
        }
        const lastMs = p.lastPushAt && typeof p.lastPushAt.toMillis === 'function' ? p.lastPushAt.toMillis() : 0;
        if (nowMs - lastMs < COURIER_PUSH_MIN_GAP_MS) continue;
        await prefRef.set({ lastPushAt: ts(), lastPushOrderId: orderId, lastPushStage: stage }, { merge: true });
        notified += 1;
        const token = await courierPush.resolveToken(c.id);
        if (!token) continue;
        const km = (c.distanceM / 1000).toFixed(1);
        try {
          await admin.messaging().send({
            token,
            notification: {
              title: stage === 'ready' ? '🍽 Tayyor buyurtma — kuryer kerak' : '🍽 Yangi restoran buyurtmasi',
              body: `${od.restaurantName || 'Restoran'} · ${km} km · yetkazish ${fee} so'm${buyout ? ` · naqd (vykup ${foodAmount} so'm)` : ''}`,
            },
            data: { type: 'restaurant_courier_offer', screen: 'courier', orderId, restaurantId: String(od.restaurantId || ''), stage },
            android: { priority: 'high' },
          });
        } catch (e) {
          console.error('restaurant courier push FCM:', e.message || e);
        }
      }
      log('courier_push', { orderId, stage, candidates: candidates.length, notified });
      return { candidates: candidates.length, notified };
    } catch (e) {
      console.error('restaurant notifyNearbyCouriers:', e.message || e);
      return empty;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // RESTORAN: ro'yxatdan o'tish va admin holati
  // ═══════════════════════════════════════════════════════════════════════

  exportsObj.getRestaurantsAccess = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const a = await moduleAccess(uid);
    return { allowed: a.allowed, stage: a.stage };
  });

  /** D-REST-7: barcha ro'yxatdan o'tadi; tasdiq — admin (yoki autoApprove). */
  exportsObj.restaurantRegister = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    await requireModule(uid);
    const user = await findUserRef(uid);
    if (!user) throw fail('failed-precondition', 'USER_NOT_FOUND');
    const d = data || {};
    const name = str(d.name, 80);
    if (name.length < 2) throw fail('invalid-argument', 'NAME_REQUIRED');
    const legalType = LEGAL_TYPES.includes(d.legalType) ? d.legalType : 'individual';
    const lat = Number(d.lat);
    const lng = Number(d.lng);
    if (!validLatLng(lat, lng)) throw fail('invalid-argument', 'LOCATION_REQUIRED');
    const delivery = d.delivery && typeof d.delivery === 'object' ? d.delivery : {};
    const mode = DELIVERY_MODES.includes(delivery.mode) ? delivery.mode : 'none';
    const pickup = delivery.pickup === true;
    if (mode === 'none' && !pickup) throw fail('invalid-argument', 'DELIVERY_OR_PICKUP_REQUIRED');
    const payment = d.payment && typeof d.payment === 'object' ? d.payment : {};
    const appSnap = await db.collection(APP_SETTINGS[0]).doc(APP_SETTINGS[1]).get();
    const autoApprove = appSnap.exists && (appSnap.data() || {}).restaurantAutoApprove === true;

    // Bir foydalanuvchi bir nechta kafe-restoran yuritadi (menejerlik,
    // D-REST-15, ega 2026-10-10): egaga son chegarasi YO'Q — tarmoq
    // (set) bo'lishi mumkin. Suiiste'mol admin tasdig'i orqali nazorat qilinadi.
    const rRef = db.collection(RESTAURANTS).doc();
    const batch = db.batch();
    batch.set(rRef, {
      name,
      legalType,
      description: str(d.description, 500),
      cuisineTags: Array.isArray(d.cuisineTags) ? d.cuisineTags.map((x) => str(x, 30)).filter(Boolean).slice(0, 3) : [],
      address: str(d.address, 300),
      contactPhone: str(d.contactPhone, 20).replace(/[^\d+]/g, ''),
      lat, lng,
      geohash: geoHash.encode(lat, lng, 7),
      logoUrl: '', coverUrl: '', announcement: '',
      openingHours: (d.openingHours && hhmmToMin(d.openingHours.open) != null
        && hhmmToMin(d.openingHours.close) != null)
        ? { open: str(d.openingHours.open, 5), close: str(d.openingHours.close, 5) } : null,
      prepTimeMin: intOr(d.prepTimeMin, 20, 5, 180),
      minOrderAmount: intOr(d.minOrderAmount, 0, 0, 1000000000),
      delivery: {
        mode, pickup,
        ownFee: delivery.ownFee && typeof delivery.ownFee === 'object' ? {
          type: delivery.ownFee.type === 'distance' ? 'distance' : 'fixed',
          fixed: intOr(delivery.ownFee.fixed, 0, 0, 1000000000),
          base: intOr(delivery.ownFee.base, 0, 0, 1000000000),
          perKm: intOr(delivery.ownFee.perKm, 0, 0, 1000000000),
          freeAbove: intOr(delivery.ownFee.freeAbove, null, 0, 1000000000),
          maxKm: intOr(delivery.ownFee.maxKm, null, 1, 100),
        } : { type: 'fixed', fixed: 0, base: 0, perKm: 0, freeAbove: null, maxKm: null },
      },
      payment: { prepay: payment.prepay !== false, cash: payment.cash !== false },
      pausedUntil: null,
      // server-only (qoida: a'zo yozolmaydi)
      status: autoApprove ? RESTAURANT_STATUS.approved : RESTAURANT_STATUS.applied,
      ownerUid: uid,
      walletUserDocId: user.ref.id,
      ratingAvg: 0, ratingCount: 0, timeoutStreak: 0,
      createdAt: ts(), updatedAt: ts(),
      ...(autoApprove ? { approvedAt: ts(), approvedBy: 'auto' } : {}),
    });
    batch.set(rRef.collection(MEMBERS).doc(uid), { role: 'owner', addedAt: ts(), addedBy: uid });
    const card = str(payment.cardNumber, 24).replace(/\D/g, '');
    if (card || payment.qrImageUrl) {
      batch.set(rRef.collection(PRIVATE).doc('payment'), {
        cardNumber: card.length === 16 ? card : '',
        cardHolder: str(payment.cardHolder, 60),
        qrImageUrl: str(payment.qrImageUrl, 500),
        updatedAt: ts(),
      });
    }
    await batch.commit();
    log('register', { restaurantId: rRef.id, userId: uid, result: 'ok', status: autoApprove ? 'approved' : 'applied', durationMs: Date.now() - t0 });
    return { ok: true, restaurantId: rRef.id, status: autoApprove ? 'approved' : 'applied' };
  });

  exportsObj.adminSetRestaurantStatus = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, ['admin', 'superadmin'], 'Admin role required');
    const restaurantId = str(data && data.restaurantId, 64);
    const to = str(data && data.status, 20);
    const reason = str(data && data.reason, 300);
    if (!restaurantId) throw fail('invalid-argument', 'RESTAURANT_ID_REQUIRED');
    if (!Object.values(RESTAURANT_STATUS).includes(to)) throw fail('invalid-argument', 'STATUS_INVALID');
    const rRef = db.collection(RESTAURANTS).doc(restaurantId);
    const from = await db.runTransaction(async (t) => {
      const s = await t.get(rRef);
      if (!s.exists) throw fail('not-found', 'RESTAURANT_NOT_FOUND');
      const cur = String((s.data() || {}).status || '');
      const allowed = RESTAURANT_ADMIN_TRANSITIONS[cur] || [];
      if (!allowed.includes(to)) throw fail('failed-precondition', 'RESTAURANT_INVALID_TRANSITION', { from: cur, to });
      t.update(rRef, {
        status: to, updatedAt: ts(),
        ...(to === 'approved' ? { approvedAt: ts(), approvedBy: actor } : {}),
        ...(to === 'suspended' || to === 'rejected' ? { statusReason: reason } : {}),
      });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'restaurant_status', actor, target: restaurantId, from: cur, to, reason, at: ts(),
      });
      return cur;
    });
    log('admin_status', { restaurantId, userId: actor, from, to, result: 'ok' });
    return { ok: true, from, to };
  });

  /**
   * Admin — AVA kuryeri yetkazish tarifi (D-REST-4, 9/41-qoida): har saqlash
   * yangi `version` va o'zgarmas tarix hujjati `restaurant_delivery_tariffs/v{n}`
   * (`adminSetLocalTaxiPrices` namunasi). Narxlar — ega qarori; server
   * default yozmaydi (hujjat bo'lmasa `TARIFF_NOT_CONFIGURED` qoladi).
   * data: { base, perKm, nightCoef, nightStart, nightEnd, roadFactor, maxKm,
   *         regions: { key: { base, perKm, nightCoef?, maxKm? } }, reason }
   * Mavjud buyurtmalar o'z `deliveryTariffVersion` bilan qoladi (9-qoida).
   */
  exportsObj.adminSetRestaurantDeliveryPrices = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, ['admin', 'superadmin', 'finance'], 'Admin role required');
    const d = data || {};
    const parsePrices = (o, label) => {
      const base = Number(o && o.base);
      const perKm = Number(o && o.perKm);
      if (!Number.isInteger(base) || base <= 0 || base > 10000000
          || !Number.isInteger(perKm) || perKm < 0 || perKm > 10000000) {
        throw fail('invalid-argument', 'PRICE_INVALID', { region: label });
      }
      const out = { base, perKm };
      if (o.nightCoef != null && o.nightCoef !== '') {
        const c = Number(o.nightCoef);
        if (!Number.isFinite(c) || c < 1 || c > 3) throw fail('invalid-argument', 'NIGHT_COEF_INVALID', { region: label });
        out.nightCoef = Math.round(c * 1000) / 1000;
      }
      if (o.maxKm != null && o.maxKm !== '') {
        const m = Number(o.maxKm);
        if (!Number.isInteger(m) || m < 1 || m > 100) throw fail('invalid-argument', 'MAX_KM_INVALID', { region: label });
        out.maxKm = m;
      }
      return out;
    };
    const global = parsePrices(d, 'global');
    // Global: tun soatlari va yo'l koeffitsienti (mintaqasiz).
    for (const h of [d.nightStart, d.nightEnd]) {
      if (h != null && h !== '' && !(Number.isInteger(Number(h)) && Number(h) >= 0 && Number(h) <= 23)) {
        throw fail('invalid-argument', 'NIGHT_HOURS_INVALID');
      }
    }
    if (d.roadFactor != null && d.roadFactor !== '') {
      const rf = Number(d.roadFactor);
      if (!Number.isFinite(rf) || rf < 1 || rf > 2) throw fail('invalid-argument', 'ROAD_FACTOR_INVALID');
    }
    const regions = {};
    const rawRegions = d.regions && typeof d.regions === 'object' ? d.regions : {};
    for (const [k, v] of Object.entries(rawRegions)) {
      if (!localTaxi.REGION_KEYS.includes(k)) throw fail('invalid-argument', 'REGION_UNKNOWN', { region: k });
      if (v) regions[k] = parsePrices(v, k);
    }
    const reason = str(d.reason, 300);
    const ref = db.collection(TARIFF_DOC[0]).doc(TARIFF_DOC[1]);
    const version = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const cur = snap.exists ? (snap.data() || {}) : {};
      const prevVersion = Number.isInteger(cur.version) ? cur.version : 0;
      const next = prevVersion + 1;
      const tariffDoc = {
        base: global.base,
        perKm: global.perKm,
        nightCoef: global.nightCoef != null ? global.nightCoef
          : (cur.nightCoef != null ? cur.nightCoef : tariff.DEFAULT_NIGHT_COEF),
        nightStart: d.nightStart != null && d.nightStart !== '' ? Number(d.nightStart)
          : intOr(cur.nightStart, tariff.DEFAULT_NIGHT_START_H, 0, 23),
        nightEnd: d.nightEnd != null && d.nightEnd !== '' ? Number(d.nightEnd)
          : intOr(cur.nightEnd, tariff.DEFAULT_NIGHT_END_H, 0, 23),
        roadFactor: d.roadFactor != null && d.roadFactor !== '' ? Math.round(Number(d.roadFactor) * 1000) / 1000
          : (cur.roadFactor != null ? cur.roadFactor : tariff.DEFAULT_ROAD_FACTOR),
        maxKm: global.maxKm != null ? global.maxKm : intOr(cur.maxKm, tariff.DEFAULT_MAX_KM, 1, 100),
        regions,
        // D9: AVA ulushi (`adminSetRestaurantFeeSettings`) narx tarifini saqlashda YO'QOLMAYDI.
        ...(cur.avaFeeBps != null ? { avaFeeBps: cur.avaFeeBps } : {}),
        version: next,
        reason,
        updatedAt: ts(),
        updatedBy: actor,
      };
      t.set(ref, tariffDoc);
      t.create(db.collection(TARIFF_HISTORY).doc(`v${next}`), {
        ...tariffDoc,
        previous: {
          version: prevVersion,
          base: cur.base == null ? null : cur.base,
          perKm: cur.perKm == null ? null : cur.perKm,
          nightCoef: cur.nightCoef == null ? null : cur.nightCoef,
          nightStart: cur.nightStart == null ? null : cur.nightStart,
          nightEnd: cur.nightEnd == null ? null : cur.nightEnd,
          roadFactor: cur.roadFactor == null ? null : cur.roadFactor,
          maxKm: cur.maxKm == null ? null : cur.maxKm,
          avaFeeBps: cur.avaFeeBps == null ? null : cur.avaFeeBps,
          regions: cur.regions && typeof cur.regions === 'object' ? cur.regions : {},
        },
        changedBy: actor,
        changedAt: ts(),
      });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'restaurant_delivery_tariff', actor, target: TARIFF_DOC.join('/'),
        from: String(prevVersion), to: String(next), reason, at: ts(),
      });
      return next;
    });
    log('admin_tariff', { userId: actor, version, result: 'ok' });
    return { ok: true, version };
  });

  /**
   * Admin — AVA ulushi (bps) va tungi koeffitsient (D9, ega qarori 2026-10-16).
   * `adminSetRestaurantDeliveryPrices` bilan BITTA hujjat (`settings/restaurant_delivery`)
   * va BITTA versiya zanjiri (`restaurant_delivery_tariffs/v{n}`): har haqiqiy
   * o'zgarish yangi `version` + o'zgarmas tarix + audit. Narxlar (base, perKm,
   * regions, ...) TEGILMAYDI. Mavjud buyurtmalar o'z `avaFee`/`deliveryTariffSnapshot`
   * muhri bilan qoladi (9-qoida). Sozlama yo'q → standart 200 bps / ×1.5.
   * data: { avaFeeBps?: butun 0..10000 | null (null = standartga qaytish),
   *         nightCoef?: 1..3, reason }
   * Bir xil qiymat qayta yuborilsa — versiya OCHILMAYDI (`unchanged: true`).
   */
  exportsObj.adminSetRestaurantFeeSettings = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, ['admin', 'superadmin'], 'Admin role required');
    const d = data || {};
    const wantFee = Object.prototype.hasOwnProperty.call(d, 'avaFeeBps') && d.avaFeeBps !== undefined;
    let feeBps = null; // null = standartga qaytarish
    if (wantFee && d.avaFeeBps !== null) {
      const v = d.avaFeeBps;
      if (typeof v !== 'number' || !Number.isInteger(v) || v < tariff.AVA_FEE_BPS_MIN || v > tariff.AVA_FEE_BPS_MAX) {
        throw fail('invalid-argument', 'AVA_FEE_BPS_INVALID', { min: tariff.AVA_FEE_BPS_MIN, max: tariff.AVA_FEE_BPS_MAX });
      }
      feeBps = v;
    }
    let nightCoef = null;
    if (d.nightCoef != null && d.nightCoef !== '') {
      const c = Number(d.nightCoef);
      if (!Number.isFinite(c) || c < tariff.NIGHT_COEF_MIN || c > tariff.NIGHT_COEF_MAX) {
        throw fail('invalid-argument', 'NIGHT_COEF_INVALID', { min: tariff.NIGHT_COEF_MIN, max: tariff.NIGHT_COEF_MAX });
      }
      nightCoef = Math.round(c * 1000) / 1000;
    }
    if (!wantFee && nightCoef == null) throw fail('invalid-argument', 'NOTHING_TO_CHANGE');
    const reason = str(d.reason, 300);
    const ref = db.collection(TARIFF_DOC[0]).doc(TARIFF_DOC[1]);
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const cur = snap.exists ? (snap.data() || {}) : {};
      const prevVersion = Number.isInteger(cur.version) ? cur.version : 0;
      const curFee = cur.avaFeeBps == null ? null : cur.avaFeeBps;
      const curNight = cur.nightCoef == null ? null : cur.nightCoef;
      const nextFee = wantFee ? feeBps : curFee;
      const nextNight = nightCoef != null ? nightCoef : curNight;
      if (nextFee === curFee && nextNight === curNight) {
        return { version: prevVersion, unchanged: true, avaFeeBps: curFee, nightCoef: curNight };
      }
      const next = prevVersion + 1;
      const tariffDoc = { ...cur, version: next, reason, updatedAt: ts(), updatedBy: actor };
      if (nextFee == null) delete tariffDoc.avaFeeBps; else tariffDoc.avaFeeBps = nextFee;
      if (nextNight != null) tariffDoc.nightCoef = nextNight;
      t.set(ref, tariffDoc);
      t.create(db.collection(TARIFF_HISTORY).doc(`v${next}`), {
        ...tariffDoc,
        previous: {
          version: prevVersion,
          base: cur.base == null ? null : cur.base,
          perKm: cur.perKm == null ? null : cur.perKm,
          nightCoef: curNight,
          nightStart: cur.nightStart == null ? null : cur.nightStart,
          nightEnd: cur.nightEnd == null ? null : cur.nightEnd,
          roadFactor: cur.roadFactor == null ? null : cur.roadFactor,
          maxKm: cur.maxKm == null ? null : cur.maxKm,
          avaFeeBps: curFee,
          regions: cur.regions && typeof cur.regions === 'object' ? cur.regions : {},
        },
        changeKind: 'fee_settings',
        changedBy: actor,
        changedAt: ts(),
      });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'restaurant_fee_settings', actor, target: TARIFF_DOC.join('/'),
        from: String(prevVersion), to: String(next), reason,
        detail: { avaFeeBps: nextFee, prevAvaFeeBps: curFee, nightCoef: nextNight, prevNightCoef: curNight },
        at: ts(),
      });
      return { version: next, unchanged: false, avaFeeBps: nextFee, nightCoef: nextNight };
    });
    log('admin_fee_settings', { userId: actor, version: out.version, unchanged: out.unchanged, result: 'ok' });
    return { ok: true, ...out };
  });

  /** Admin — `settings/app.restaurantAutoApprove` (D-REST-7: tasdiq admin yoki avto). */
  exportsObj.adminSetRestaurantAutoApprove = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, ['admin', 'superadmin'], 'Admin role required');
    const enabled = !!(data && data.enabled === true);
    const batch = db.batch();
    batch.set(db.collection(APP_SETTINGS[0]).doc(APP_SETTINGS[1]), {
      restaurantAutoApprove: enabled, updatedAt: ts(),
    }, { merge: true });
    batch.set(db.collection(ADMIN_AUDIT).doc(), {
      kind: 'restaurant_auto_approve', actor, target: APP_SETTINGS.join('/'),
      from: '', to: String(enabled), reason: '', at: ts(),
    });
    await batch.commit();
    log('admin_auto_approve', { userId: actor, enabled, result: 'ok' });
    return { ok: true, enabled };
  });

  /**
   * Admin — modul bosqichi (42-qoida): `internal` (faqat `testerIds`) yoki
   * `public`. `module_config/restaurants_all.restaurants` — merge, boshqa
   * kalitlar (`enabled`) tegilmaydi. Telefonlar kanonik ID'ga keltiriladi.
   */
  exportsObj.adminSetRestaurantsStage = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, ['admin', 'superadmin'], 'Admin role required');
    const stage = data && data.stage;
    if (!['internal', 'public'].includes(stage)) throw fail('invalid-argument', 'STAGE_INVALID');
    const raw = Array.isArray(data && data.testerIds) ? data.testerIds : [];
    if (raw.length > 200) throw fail('invalid-argument', 'TESTERS_TOO_MANY');
    const testerIds = [...new Set(raw.map((x) => canonicalUid(String(x || ''))).filter((x) => /^998\d{9}$/.test(x)))];
    const ref = db.collection(MODULE_CONFIG[0]).doc(MODULE_CONFIG[1]);
    const prev = await ref.get();
    const prevCfg = prev.exists && prev.data()[MODULE_ID] && typeof prev.data()[MODULE_ID] === 'object'
      ? prev.data()[MODULE_ID] : {};
    const batch = db.batch();
    batch.set(ref, { [MODULE_ID]: { stage, testerIds }, updatedAt: ts(), updatedBy: actor }, { merge: true });
    batch.set(db.collection(ADMIN_AUDIT).doc(), {
      kind: 'restaurants_stage', actor, target: MODULE_CONFIG.join('/'),
      from: String(prevCfg.stage || ''), to: stage, reason: `testers:${testerIds.length}`, at: ts(),
    });
    await batch.commit();
    log('admin_stage', { userId: actor, stage, testers: testerIds.length, result: 'ok' });
    return { ok: true, stage, testerIds };
  });

  /**
   * Admin — buyurtmani bekor qilish (holat jadvalidan tashqari, lekin yakuniy
   * holat o'zgarmaydi): yechilgan 2 % restoranga qaytadi, kuryer marshrutidan
   * olinadi, hamma tomonga xabar, audit. Takror chaqiruv — idempotent.
   */
  exportsObj.adminCancelRestaurantOrder = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, ['admin', 'superadmin'], 'Admin role required');
    const orderId = str(data && data.orderId, 64);
    const reason = str(data && data.reason, 300) || 'Admin bekor qildi';
    const orderRef = db.collection(ORDERS).doc(orderId);
    const out = await db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      const from = String(od.restaurantStatus || '');
      if (from === RS.cancelled && String(od.cancelledBy || '').startsWith('admin:')) return { idempotent: true };
      if ([RS.delivered, RS.rejected, RS.cancelled, RS.deliveryFailed].includes(from)) {
        throw fail('failed-precondition', 'ORDER_ALREADY_FINAL', { from });
      }
      const prep = await prepareFeeInTx(t, od, orderId, false);
      const routeRef = od.deliveryRouteId ? db.collection(ROUTES).doc(String(od.deliveryRouteId)) : null;
      const routeSnap = routeRef ? await t.get(routeRef) : null;
      // WRITE fazasi.
      const refund = commitFeeInTx(t, prep, { orderId, actorId: actor });
      t.update(orderRef, statusPatch(RS.cancelled, {
        cancelledAt: ts(), cancelledBy: `admin:${actor}`, cancelReason: reason, rejectReason: reason,
        'avaFee.refunded': refund.applied, 'avaFee.refundedAt': refund.applied ? ts() : null,
      }));
      const route = detachFromRouteInTx(t, routeRef, routeSnap, orderId, 'admin_cancelled');
      addEvent(t, orderRef, { from, to: RS.cancelled, actor: 'admin', actorId: actor, reason, meta: { refundAmount: refund.amount, routeCompleted: route.routeCompleted } });
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'restaurant_order_cancel', actor, target: orderId, from, to: RS.cancelled, reason, at: ts(),
      });
      return { idempotent: false, from, refund: refund.amount, customerUid: od.userPhone, restaurantId: od.restaurantId, courierId: od.courierId };
    });
    if (out.idempotent) return { ok: true, idempotent: true };
    log('admin_cancel', { orderId, userId: actor, from: out.from, refundAmount: out.refund, result: 'ok' });
    if (out.customerUid) await notifyCustomer(canonicalUid(out.customerUid), { title: 'Buyurtma bekor qilindi', body: reason, orderId });
    if (out.restaurantId) await notifyMembers(String(out.restaurantId), { title: 'Buyurtma bekor qilindi (admin)', body: reason, orderId });
    if (out.courierId) await notifyCustomer(canonicalUid(out.courierId), { title: 'Buyurtma bekor bo\'ldi', body: 'Admin buyurtmani bekor qildi', orderId });
    return { ok: true, from: out.from, refundAmount: out.refund };
  });

  // ═══════════════════════════════════════════════════════════════════════
  // MIJOZ: narx so'rovi, buyurtma, to'ladim, bekor
  // ═══════════════════════════════════════════════════════════════════════

  exportsObj.quoteRestaurantDelivery = functions
    .runWith({ secrets: ['DIRECTIONS_API_KEY'] })
    .https.onCall(async (data, context) => {
      const uid = requirePhoneUid(context);
      await requireModule(uid);
      const restaurantId = str(data && data.restaurantId, 64);
      const toLat = Number(data && data.lat);
      const toLng = Number(data && data.lng);
      if (!restaurantId) throw fail('invalid-argument', 'RESTAURANT_ID_REQUIRED');
      if (!validLatLng(toLat, toLng)) throw fail('invalid-argument', 'DELIVERY_ADDRESS_REQUIRED');
      const rs = await db.collection(RESTAURANTS).doc(restaurantId).get();
      if (!rs.exists) throw fail('not-found', 'RESTAURANT_NOT_FOUND');
      const r = rs.data() || {};
      const mode = (r.delivery || {}).mode;
      if (mode === 'ava_courier') {
        const q = await quoteDelivery(r, { toLat, toLng });
        return { deliveryMode: mode, deliveryFee: q.deliveryFee, distanceMeters: q.distanceMeters, tariffVersion: q.deliveryTariffVersion };
      }
      if (mode === 'own_courier') {
        const dist = await straightDistance(r, { toLat, toLng });
        const fee = tariff.computeOwnDeliveryFee((r.delivery || {}).ownFee, { distanceMeters: dist, itemsTotal: intOr(data && data.itemsTotal, 0, 0, 1000000000) });
        if (fee == null) throw fail('failed-precondition', 'DELIVERY_TOO_FAR');
        return { deliveryMode: mode, deliveryFee: fee, distanceMeters: dist, tariffVersion: null };
      }
      throw fail('failed-precondition', 'DELIVERY_NOT_AVAILABLE');
    });

  /**
   * Buyurtma — narx FAQAT menyudan (18-qoida), idempotent (`idempotencyKey`),
   * `acceptDeadlineAt` bilan `placed`. Pul harakati YO'Q (D-REST-1).
   */
  exportsObj.placeRestaurantOrder = functions
    .runWith({ secrets: ['DIRECTIONS_API_KEY'] })
    .https.onCall(async (data, context) => {
      const t0 = Date.now();
      const uid = requirePhoneUid(context);
      await requireModule(uid);
      const d = data || {};
      const idempotencyKey = str(d.idempotencyKey, 80);
      if (!/^[A-Za-z0-9_-]{8,80}$/.test(idempotencyKey)) throw fail('invalid-argument', 'IDEMPOTENCY_KEY_INVALID');
      const restaurantId = str(d.restaurantId, 64);
      if (!restaurantId) throw fail('invalid-argument', 'RESTAURANT_ID_REQUIRED');
      const itemsIn = Array.isArray(d.items) ? d.items : [];
      if (itemsIn.length < 1 || itemsIn.length > MAX_ITEMS) throw fail('invalid-argument', 'ITEMS_REQUIRED');
      const fulfillmentMode = d.fulfillmentMode === 'pickup' ? 'pickup' : 'delivery';
      const foodPaymentMethod = FOOD_PAYMENT.includes(d.foodPaymentMethod) ? d.foodPaymentMethod : 'prepay';
      let deliveryPaymentMethod = DELIVERY_PAYMENT.includes(d.deliveryPaymentMethod) ? d.deliveryPaymentMethod : 'cash';
      const toLat = d.lat != null ? Number(d.lat) : Number.NaN;
      const toLng = d.lng != null ? Number(d.lng) : Number.NaN;

      const idemRef = db.collection(IDEMPOTENCY).doc(idempotencyKey);
      const existing = await idemRef.get();
      if (existing.exists) {
        return { ...(existing.data().result || { ok: true }), duplicate: true };
      }

      const user = await findUserRef(uid);
      if (!user) throw fail('failed-precondition', 'USER_NOT_FOUND');

      const rRef = db.collection(RESTAURANTS).doc(restaurantId);
      const rSnap = await rRef.get();
      if (!rSnap.exists) throw fail('not-found', 'RESTAURANT_NOT_FOUND');
      const r = rSnap.data() || {};
      if (r.status !== RESTAURANT_STATUS.approved) throw fail('failed-precondition', 'RESTAURANT_NOT_APPROVED');
      if (canonicalUid(String(r.ownerUid || '')) === uid) throw fail('failed-precondition', 'OWN_RESTAURANT');
      const at = now();
      const paused = r.pausedUntil && typeof r.pausedUntil.toMillis === 'function' && r.pausedUntil.toMillis() > at.getTime();
      if (paused) throw fail('failed-precondition', 'RESTAURANT_PAUSED');
      if (!isOpenAt(r.openingHours, at)) throw fail('failed-precondition', 'RESTAURANT_CLOSED');

      const delivery = r.delivery || {};
      let deliveryMode;
      if (fulfillmentMode === 'pickup') {
        if (delivery.pickup !== true) throw fail('failed-precondition', 'PICKUP_NOT_AVAILABLE');
        deliveryMode = 'pickup';
      } else {
        if (!['ava_courier', 'own_courier'].includes(delivery.mode)) throw fail('failed-precondition', 'DELIVERY_NOT_AVAILABLE');
        deliveryMode = delivery.mode;
        if (!validLatLng(toLat, toLng)) throw fail('invalid-argument', 'DELIVERY_ADDRESS_REQUIRED');
      }
      // To'lov usuli — rejimga mos (D-REST-12).
      const payment = r.payment || {};
      if (deliveryMode === 'ava_courier') {
        if (!['prepay', 'cash_buyout'].includes(foodPaymentMethod)) throw fail('invalid-argument', 'FOOD_PAYMENT_INVALID');
        if (!['cash', 'wallet'].includes(deliveryPaymentMethod)) throw fail('invalid-argument', 'DELIVERY_PAYMENT_INVALID');
      } else {
        if (!['prepay', 'cash_to_restaurant'].includes(foodPaymentMethod)) throw fail('invalid-argument', 'FOOD_PAYMENT_INVALID');
        deliveryPaymentMethod = 'none';
      }
      if (foodPaymentMethod === 'prepay' && payment.prepay === false) throw fail('failed-precondition', 'PREPAY_NOT_ACCEPTED');
      if (foodPaymentMethod !== 'prepay' && payment.cash === false) throw fail('failed-precondition', 'CASH_NOT_ACCEPTED');
      if (foodPaymentMethod === 'cash_buyout') {
        const st = await db.collection(CUSTOMER_STATS).doc(uid).get();
        const until = st.exists && st.data().prepayOnlyUntil && st.data().prepayOnlyUntil.toMillis
          ? st.data().prepayOnlyUntil.toMillis() : 0;
        if (until > at.getTime()) throw fail('failed-precondition', 'PREPAY_ONLY', { until });
      }

      // Menyu — narx faqat serverdan (klient narxi e'tiborsiz).
      const wanted = new Map();
      for (const it of itemsIn) {
        const id = str(it && it.itemId, 64);
        const qty = intOr(it && it.qty, 0, 1, MAX_QTY);
        if (!id || qty < 1) throw fail('invalid-argument', 'ITEM_INVALID');
        wanted.set(id, (wanted.get(id) || 0) + qty);
      }
      const itemSnaps = await db.getAll(...[...wanted.keys()].map((id) => rRef.collection(MENU_ITEMS).doc(id)));
      const items = [];
      let itemsTotal = 0;
      let packagingTotal = 0;
      for (const s of itemSnaps) {
        if (!s.exists) throw fail('failed-precondition', 'MENU_ITEM_NOT_FOUND', { itemId: s.id });
        const m = s.data() || {};
        const stopped = m.stopUntil && typeof m.stopUntil.toMillis === 'function' && m.stopUntil.toMillis() > at.getTime();
        if (m.available === false || stopped) throw fail('failed-precondition', 'MENU_ITEM_UNAVAILABLE', { itemId: s.id });
        // Faqat HAQIQIY butun son: `'5000'` satri ham rad (menyuni restoran
        // yozadi — klient ma'lumoti, 18-qoida; qoida ham `int` talab qiladi).
        const price = typeof m.price === 'number' ? m.price : Number.NaN;
        if (!Number.isInteger(price) || price <= 0 || price > MAX_PRICE) throw fail('failed-precondition', 'MENU_PRICE_INVALID', { itemId: s.id });
        const packagingFee = intOr(m.packagingFee, 0, 0, MAX_PRICE);
        const count = wanted.get(s.id);
        const lineTotal = price * count;
        itemsTotal += lineTotal;
        packagingTotal += packagingFee * count;
        items.push({ itemId: s.id, name: str(m.name, 80), price, count, packagingFee, lineTotal });
      }
      const minOrder = intOr(r.minOrderAmount, 0, 0, 1000000000);
      if (itemsTotal < minOrder) throw fail('failed-precondition', 'MIN_ORDER_NOT_MET', { minOrderAmount: minOrder, itemsTotal });

      // Tarif hujjati BIR marta: yetkazish narxi VA AVA ulushi (D9) shundan.
      const tariffData = await readTariffDoc();

      // Yetkazish narxi.
      let deliveryFee = 0;
      let deliveryFeeSource = 'none';
      let deliveryQuote = {};
      if (deliveryMode === 'ava_courier') {
        const q = await quoteDelivery(r, { toLat, toLng }, tariffData);
        deliveryFee = q.deliveryFee;
        deliveryFeeSource = q.deliveryFeeSource;
        deliveryQuote = {
          deliveryTariffVersion: q.deliveryTariffVersion,
          deliveryTariffSnapshot: q.deliveryTariffSnapshot,
          distanceMeters: q.distanceMeters,
          distanceSource: q.distanceSource,
        };
      } else if (deliveryMode === 'own_courier') {
        const dist = await straightDistance(r, { toLat, toLng });
        const fee = tariff.computeOwnDeliveryFee(delivery.ownFee, { distanceMeters: dist, itemsTotal });
        if (fee == null) throw fail('failed-precondition', 'DELIVERY_TOO_FAR');
        deliveryFee = fee;
        deliveryFeeSource = 'restaurant';
        deliveryQuote = { distanceMeters: dist, distanceSource: 'straight', ownFeeSnapshot: delivery.ownFee || null };
      }

      // Oldindan to'lov uchun rekvizit — buyurtmaga snapshot (faqat egasi o'qiydi).
      let restaurantPayment = null;
      if (foodPaymentMethod === 'prepay') {
        const p = await rRef.collection(PRIVATE).doc('payment').get();
        if (p.exists) {
          const pd = p.data() || {};
          restaurantPayment = { cardNumber: str(pd.cardNumber, 16), cardHolder: str(pd.cardHolder, 60), qrImageUrl: str(pd.qrImageUrl, 500) };
        }
      }

      // D9: ulush foizi admin sozlamasidan (yo'q bo'lsa 2 %); buyurtmaga muhrlanadi —
      // keyin sozlama o'zgarsa ham shu buyurtmaning ulushi o'zgarmaydi.
      const avaFee = {
        ...tariff.computeAvaFee(itemsTotal, tariff.resolveAvaFeeSettings(tariffData)),
        charged: false,
      };
      const code = pickupCode();
      const deadline = new Date(at.getTime() + ACCEPT_TIMEOUT_MIN * 60 * 1000);
      const orderRef = db.collection(ORDERS).doc();
      const userData = user.data;
      const payload = {
        type: 'restaurant', module: MODULE_ID,
        restaurantId, restaurantName: str(r.name, 80),
        restaurantAddress: str(r.address, 300),
        restaurantLat: Number(r.lat), restaurantLng: Number(r.lng),
        restaurantWalletUid: String(r.walletUserDocId || r.ownerUid || ''),
        ...statusPatch(RS.placed),
        paymentStatus: 'unpaid',
        userName: str(d.userName || userData.name || userData.fullName, 80),
        userPhone: uid, phone: uid,
        address: str(d.address, 300),
        lat: Number.isFinite(toLat) ? toLat : null,
        lng: Number.isFinite(toLng) ? toLng : null,
        note: str(d.note, 200),
        utensils: intOr(d.utensils, 0, 0, 20),
        items, itemsTotal, packagingTotal, deliveryFee,
        total: itemsTotal + packagingTotal + deliveryFee,
        fulfillmentMode, deliveryMode, deliveryFeeSource, ...deliveryQuote,
        foodPaymentMethod, deliveryPaymentMethod,
        ...(restaurantPayment ? { restaurantPayment } : {}),
        avaFee,
        acceptDeadlineAt: tsOf(deadline),
        prepTimeMin: intOr(r.prepTimeMin, 20, 5, 180),
        courierId: null, deliveryRouteId: null,
        balanceApplied: 0, cashDue: 0, cashPaid: 0,
        createdAt: ts(),
      };
      const result = { ok: true, orderId: orderRef.id, itemsTotal, packagingTotal, deliveryFee, total: payload.total, acceptDeadlineAtMs: deadline.getTime() };
      // Parallel takror: ikkinchi chaqiruv BIRINCHISINING natijasini oladi —
      // o'zi yaratmagan orderId'ni qaytarmaydi.
      const txRes = await db.runTransaction(async (t) => {
        const again = await t.get(idemRef);
        if (again.exists) return { dup: again.data().result || { ok: true } };
        t.set(orderRef, payload);
        t.set(orderRef.collection(PRIVATE).doc('secrets'), { pickupCode: code, pickupAttempts: 0, createdAt: ts() });
        addEvent(t, orderRef, { from: null, to: RS.placed, actor: 'customer', actorId: uid, meta: { itemsTotal, deliveryFee, deliveryMode, foodPaymentMethod } });
        t.set(idemRef, { type: 'placeRestaurantOrder', result, createdAt: ts() });
        return { created: true };
      });
      if (txRes.dup) return { ...txRes.dup, duplicate: true };
      log('place', { orderId: orderRef.id, restaurantId, userId: uid, result: 'ok', itemsTotal, deliveryFee, deliveryMode, durationMs: Date.now() - t0 });
      await notifyMembers(restaurantId, { title: '🍽 Yangi buyurtma', body: `${new Intl.NumberFormat('uz-UZ').format(itemsTotal)} so'm · ${ACCEPT_TIMEOUT_MIN} daqiqada qabul qiling`, orderId: orderRef.id });
      return result;
    });

  /** Mijoz: «to'ladim» (oldindan to'lov) → `paid_declared`; tasdiq — restoran. */
  exportsObj.customerMarkRestaurantOrderPaid = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const orderId = str(data && data.orderId, 64);
    const orderRef = db.collection(ORDERS).doc(orderId);
    await db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      if (canonicalUid(String(od.userPhone || '')) !== uid) throw fail('permission-denied', 'NOT_ORDER_OWNER');
      if (od.foodPaymentMethod !== 'prepay') throw fail('failed-precondition', 'NOT_PREPAY_ORDER');
      if (od.paymentStatus === 'paid') return;
      if ([RS.rejected, RS.cancelled, RS.deliveryFailed].includes(od.restaurantStatus)) throw fail('failed-precondition', 'ORDER_CLOSED');
      t.update(orderRef, { paymentStatus: 'paid_declared', paidDeclaredAt: ts(), updatedAt: ts() });
      addEvent(t, orderRef, { from: od.restaurantStatus, to: od.restaurantStatus, actor: 'customer', actorId: uid, reason: 'paid_declared' });
    });
    return { ok: true };
  });

  /** Mijoz bekor — FAQAT `placed` (2 % hali yechilmagan). */
  exportsObj.customerCancelRestaurantOrder = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const orderId = str(data && data.orderId, 64);
    const reason = str(data && data.reason, 200);
    const orderRef = db.collection(ORDERS).doc(orderId);
    const out = await db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      if (canonicalUid(String(od.userPhone || '')) !== uid) throw fail('permission-denied', 'NOT_ORDER_OWNER');
      if (od.restaurantStatus === RS.cancelled) return { ok: true, idempotent: true };
      if (od.restaurantStatus !== RS.placed) throw fail('failed-precondition', 'CANCEL_NOT_ALLOWED', { from: od.restaurantStatus });
      assertTransition(od, RS.cancelled, orderId);
      t.update(orderRef, statusPatch(RS.cancelled, { cancelledAt: ts(), cancelledBy: uid, rejectReason: reason || 'Mijoz bekor qildi' }));
      addEvent(t, orderRef, { from: RS.placed, to: RS.cancelled, actor: 'customer', actorId: uid, reason });
      return { ok: true, restaurantId: od.restaurantId };
    });
    if (out.restaurantId) {
      log('customer_cancel', { orderId, restaurantId: out.restaurantId, userId: uid, result: 'ok' });
      await notifyMembers(out.restaurantId, { title: 'Buyurtma bekor qilindi', body: 'Mijoz buyurtmani bekor qildi', orderId });
    }
    return { ok: !!out.ok };
  });

  // ═══════════════════════════════════════════════════════════════════════
  // RESTORAN: qabul (2 % yechiladi), rad (qaytariladi), tayyor, to'lov keldi,
  // o'z kuryeri / olib ketish — yetkazildi
  // ═══════════════════════════════════════════════════════════════════════

  exportsObj.restaurantAcceptOrder = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    const orderId = str(data && data.orderId, 64);
    const prepIn = intOr(data && data.prepTimeMin, null, 5, 180);
    const orderRef = db.collection(ORDERS).doc(orderId);
    const out = await withContention(orderRef, 'accept', () => db.runTransaction(async (t) => {
      // READ fazasi.
      const od = await getOrderInTx(t, orderRef);
      const { rRef, r } = await requireMemberInTx(t, String(od.restaurantId || ''), uid);
      if (r.status !== RESTAURANT_STATUS.approved) throw fail('failed-precondition', 'RESTAURANT_NOT_APPROVED');
      if (od.restaurantStatus === RS.accepted) return { ok: true, idempotent: true, feeAmount: (od.avaFee || {}).amount || 0 };
      assertTransition(od, RS.accepted, orderId);
      const prep = await prepareFeeInTx(t, od, orderId, true);
      // WRITE fazasi.
      const fee = commitFeeInTx(t, prep, { orderId, actorId: uid });
      const prepTimeMin = prepIn || intOr(od.prepTimeMin, 20, 5, 180);
      t.update(orderRef, statusPatch(RS.accepted, {
        acceptedAt: ts(), acceptedBy: uid, prepTimeMin, acceptDeadlineAt: null,
        'avaFee.charged': fee.applied || !!(prep && prep.ctx.jExists),
        'avaFee.chargedAt': ts(),
      }));
      t.update(rRef, { timeoutStreak: 0, updatedAt: ts() });
      addEvent(t, orderRef, { from: RS.placed, to: RS.accepted, actor: 'restaurant', actorId: uid, meta: { prepTimeMin, feeAmount: fee.amount } });
      return { ok: true, feeAmount: fee.amount, prepTimeMin, customerUid: od.userPhone, od };
    }), (od) => {
      if (od.restaurantStatus === RS.accepted) return { ok: true, idempotent: true, feeAmount: (od.avaFee || {}).amount || 0 };
      if (od.restaurantStatus !== RS.placed) throw fail('failed-precondition', 'ORDER_INVALID_TRANSITION', { from: od.restaurantStatus, to: RS.accepted });
      return null;
    });
    log('accept', { orderId, userId: uid, result: 'ok', feeAmount: out.feeAmount, durationMs: Date.now() - t0 });
    let couriersNotified = 0;
    if (!out.idempotent) {
      if (out.customerUid) {
        await notifyCustomer(canonicalUid(out.customerUid), { title: '✅ Buyurtma qabul qilindi', body: `Tayyorlanmoqda, ~${out.prepTimeMin} daqiqa`, orderId });
      }
      // Kuryer tayyorlanish vaqtida yo'lga chiqsin (Meituan modeli, §12.9).
      couriersNotified = (await notifyNearbyCouriers(orderId, out.od || {}, 'accepted')).notified;
    }
    return { ok: true, feeAmount: out.feeAmount, idempotent: !!out.idempotent, couriersNotified };
  });

  /** Rad (placed/accepted/ready) — 2 % qaytadi; kuryer biriktirilgan bo'lsa marshrutdan olinadi. */
  exportsObj.restaurantRejectOrder = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const orderId = str(data && data.orderId, 64);
    const reason = str(data && data.reason, 200) || 'Restoran rad etdi';
    const orderRef = db.collection(ORDERS).doc(orderId);
    const out = await db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      await requireMemberInTx(t, String(od.restaurantId || ''), uid);
      if (od.restaurantStatus === RS.rejected) return { ok: true, idempotent: true };
      const from = assertTransition(od, RS.rejected, orderId);
      const prep = await prepareFeeInTx(t, od, orderId, false);
      const routeRef = od.deliveryRouteId ? db.collection(ROUTES).doc(String(od.deliveryRouteId)) : null;
      const routeSnap = routeRef ? await t.get(routeRef) : null;
      const refund = commitFeeInTx(t, prep, { orderId, actorId: uid });
      t.update(orderRef, statusPatch(RS.rejected, { rejectedAt: ts(), rejectedBy: uid, rejectReason: reason, 'avaFee.refunded': refund.applied, 'avaFee.refundedAt': refund.applied ? ts() : null }));
      detachFromRouteInTx(t, routeRef, routeSnap, orderId, 'restaurant_rejected');
      addEvent(t, orderRef, { from, to: RS.rejected, actor: 'restaurant', actorId: uid, reason, meta: { refundAmount: refund.amount } });
      return { ok: true, customerUid: od.userPhone, courierId: od.courierId };
    });
    if (!out.idempotent) {
      log('reject', { orderId, userId: uid, result: 'ok' });
      if (out.customerUid) await notifyCustomer(canonicalUid(out.customerUid), { title: 'Buyurtma rad etildi', body: reason, orderId });
      if (out.courierId) await notifyCustomer(canonicalUid(out.courierId), { title: 'Buyurtma bekor bo\'ldi', body: 'Restoran buyurtmani rad etdi', orderId });
    }
    return { ok: true, idempotent: !!out.idempotent };
  });

  exportsObj.restaurantMarkReady = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const orderId = str(data && data.orderId, 64);
    const orderRef = db.collection(ORDERS).doc(orderId);
    const out = await db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      await requireMemberInTx(t, String(od.restaurantId || ''), uid);
      if (od.restaurantStatus === RS.ready) return { ok: true, idempotent: true };
      const from = assertTransition(od, RS.ready, orderId);
      t.update(orderRef, statusPatch(RS.ready, { readyAt: ts(), readyBy: uid }));
      addEvent(t, orderRef, { from, to: RS.ready, actor: 'restaurant', actorId: uid });
      return { ok: true, customerUid: od.userPhone, courierId: od.courierId, deliveryMode: od.deliveryMode, od };
    });
    let couriersNotified = 0;
    if (!out.idempotent) {
      if (out.courierId) await notifyCustomer(canonicalUid(out.courierId), { title: '🍽 Buyurtma tayyor', body: 'Restorandan olib ketishingiz mumkin', orderId });
      if (out.deliveryMode === 'pickup' && out.customerUid) await notifyCustomer(canonicalUid(out.customerUid), { title: '🍽 Buyurtmangiz tayyor', body: 'Olib ketishingiz mumkin', orderId });
      // Kuryer hali olmagan — yaqinlarga yana taklif (shoshilinch).
      if (!out.courierId) couriersNotified = (await notifyNearbyCouriers(orderId, out.od || {}, 'ready')).notified;
    }
    return { ok: true, couriersNotified };
  });

  /** Restoran: oldindan to'lov keldi → `paid`. */
  exportsObj.restaurantConfirmPayment = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const orderId = str(data && data.orderId, 64);
    const orderRef = db.collection(ORDERS).doc(orderId);
    await db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      await requireMemberInTx(t, String(od.restaurantId || ''), uid);
      if (od.paymentStatus === 'paid') return;
      t.update(orderRef, { paymentStatus: 'paid', paidAt: ts(), paidConfirmedBy: uid, paidBy: 'restaurant_confirm', updatedAt: ts() });
      addEvent(t, orderRef, { from: od.restaurantStatus, to: od.restaurantStatus, actor: 'restaurant', actorId: uid, reason: 'payment_confirmed' });
    });
    return { ok: true };
  });

  /** O'z kuryeri / olib ketish: `ready → delivered`. Taom puli restoranga keldi deb hisoblanadi. */
  exportsObj.restaurantMarkDelivered = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const orderId = str(data && data.orderId, 64);
    const orderRef = db.collection(ORDERS).doc(orderId);
    const out = await db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      await requireMemberInTx(t, String(od.restaurantId || ''), uid);
      if (od.restaurantStatus === RS.delivered) return { ok: true, idempotent: true };
      if (od.deliveryMode === 'ava_courier') throw fail('failed-precondition', 'AVA_COURIER_ORDER');
      const from = assertTransition(od, RS.delivered, orderId);
      t.update(orderRef, statusPatch(RS.delivered, {
        deliveredAt: ts(), completedAt: ts(), deliveredBy: uid,
        paymentStatus: 'paid', paidAt: od.paidAt || ts(), paidBy: od.paidBy || 'restaurant_delivered',
      }));
      addEvent(t, orderRef, { from, to: RS.delivered, actor: 'restaurant', actorId: uid });
      t.set(db.collection(CUSTOMER_STATS).doc(canonicalUid(String(od.userPhone || ''))), { completedCount: inc(1), updatedAt: ts() }, { merge: true });
      return { ok: true, customerUid: od.userPhone };
    });
    if (!out.idempotent && out.customerUid) await notifyCustomer(canonicalUid(out.customerUid), { title: '✅ Buyurtma yetkazildi', body: 'Yoqimli ishtaha!', orderId });
    return { ok: true };
  });

  // ═══════════════════════════════════════════════════════════════════════
  // KURYER (AVA): yaqindagilar, olish, olib ketdim (kod), yetib keldim,
  // yakun (yetkazildi / yetkaza olmadim)
  // ═══════════════════════════════════════════════════════════════════════

  exportsObj.courierSetBuyoutPrefs = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    await courierAuthOf().resolve(uid, COURIER_AUTH_MODES.new);
    const enabled = !!(data && data.buyoutEnabled);
    const limit = intOr(data && data.buyoutLimit, 0, 0, 100000000);
    await db.collection(COURIER_PREFS).doc(uid).set({ buyoutEnabled: enabled, buyoutLimit: limit, updatedAt: ts() }, { merge: true });
    return { ok: true, buyoutEnabled: enabled, buyoutLimit: limit };
  });

  /**
   * Yaqindagi olinmagan restoran buyurtmalari — PROEKSIYA (40-qoida):
   * mijoz telefoni va aniq manzili YO'Q. `courierListReadyOrders` namunasi.
   */
  exportsObj.listNearbyRestaurantOrders = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const courierId = await courierAuthOf().resolve(uid, COURIER_AUTH_MODES.new);
    const lat = Number(data && data.lat);
    const lng = Number(data && data.lng);
    const hasLoc = validLatLng(lat, lng);
    const radiusKm = intOr(data && data.radiusKm, NEARBY_RADIUS_KM_DEFAULT, 1, 50);
    const prefsSnap = await db.collection(COURIER_PREFS).doc(courierId).get();
    const prefs = prefsSnap.exists ? (prefsSnap.data() || {}) : {};
    const buyoutLimit = prefs.buyoutEnabled === true ? intOr(prefs.buyoutLimit, 0, 0, 100000000) : 0;

    const snap = await db.collection(ORDERS)
      .where('type', '==', 'restaurant')
      .where('courierId', '==', null)
      .where('restaurantStatus', 'in', [RS.accepted, RS.ready])
      .limit(NEARBY_LIMIT * 3)
      .get();
    const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
    const orders = [];
    for (const doc of snap.docs) {
      const od = doc.data() || {};
      if (od.deliveryMode !== 'ava_courier') continue;
      if (courierAuthOf().isOwnOrder(od, courierId)) continue;
      const buyout = od.foodPaymentMethod === 'cash_buyout';
      const foodAmount = (Number(od.itemsTotal) || 0) + (Number(od.packagingTotal) || 0);
      if (buyout && foodAmount > buyoutLimit) continue;
      const rLat = num(od.restaurantLat);
      const rLng = num(od.restaurantLng);
      let courierToRestaurantM = null;
      if (hasLoc && rLat != null && rLng != null) {
        courierToRestaurantM = tariff.haversineMeters(lat, lng, rLat, rLng);
        if (courierToRestaurantM > radiusKm * 1000) continue;
      }
      orders.push({
        id: doc.id,
        restaurantId: od.restaurantId,
        restaurantName: od.restaurantName || '',
        restaurantAddress: od.restaurantAddress || '',
        restaurantLat: rLat, restaurantLng: rLng,
        restaurantStatus: od.restaurantStatus,
        deliveryFee: Number(od.deliveryFee) || 0,
        deliveryPaymentMethod: od.deliveryPaymentMethod || 'cash',
        foodPaymentMethod: od.foodPaymentMethod,
        buyoutAmount: buyout ? foodAmount : 0,
        distanceMeters: num(od.distanceMeters),
        courierToRestaurantM,
        prepTimeMin: num(od.prepTimeMin),
        readyAtMs: od.readyAt && od.readyAt.toMillis ? od.readyAt.toMillis() : null,
        createdAtMs: od.createdAt && od.createdAt.toMillis ? od.createdAt.toMillis() : null,
      });
      if (orders.length >= NEARBY_LIMIT) break;
    }
    orders.sort((a, b) => (a.courierToRestaurantM ?? 1e12) - (b.courierToRestaurantM ?? 1e12));
    return { orders };
  });

  /** Olish — birinchi g'olib (22-qoida); kuryerning faol marshrutiga qo'shiladi. */
  exportsObj.courierClaimRestaurantOrder = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    const courierId = await courierAuthOf().resolve(uid, COURIER_AUTH_MODES.new);
    const orderId = str(data && data.orderId, 64);
    const orderRef = db.collection(ORDERS).doc(orderId);
    const out = await withContention(orderRef, 'claim', () => db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      const assigned = canonicalUid(String(od.courierId || ''));
      if (assigned && assigned === courierId) return { ok: true, idempotent: true, routeId: od.deliveryRouteId };
      if (assigned) throw fail('failed-precondition', 'COURIER_ASSIGNMENT_CONFLICT');
      if (od.deliveryMode !== 'ava_courier') throw fail('failed-precondition', 'NOT_AVA_COURIER_ORDER');
      if (![RS.accepted, RS.ready].includes(od.restaurantStatus)) throw fail('failed-precondition', 'ORDER_NOT_CLAIMABLE', { from: od.restaurantStatus });
      if (courierAuthOf().isOwnOrder(od, courierId)) throw fail('permission-denied', 'COURIER_OWN_ORDER');
      const rRef = db.collection(RESTAURANTS).doc(String(od.restaurantId || ''));
      const [memberSnap, prefsSnap, routeSnap] = await Promise.all([
        t.get(rRef.collection(MEMBERS).doc(courierId)),
        t.get(db.collection(COURIER_PREFS).doc(courierId)),
        t.get(db.collection(ROUTES).where('courierId', '==', courierId).where('status', 'in', ['active', 'ready']).limit(1)),
      ]);
      if (memberSnap.exists) throw fail('permission-denied', 'COURIER_IS_RESTAURANT_MEMBER');
      if (od.foodPaymentMethod === 'cash_buyout') {
        const p = prefsSnap.exists ? (prefsSnap.data() || {}) : {};
        const limit = p.buyoutEnabled === true ? intOr(p.buyoutLimit, 0, 0, 100000000) : 0;
        const foodAmount = (Number(od.itemsTotal) || 0) + (Number(od.packagingTotal) || 0);
        if (foodAmount > limit) throw fail('failed-precondition', 'BUYOUT_LIMIT_EXCEEDED', { required: foodAmount, limit });
      }
      // WRITE fazasi.
      let routeId;
      if (!routeSnap.empty) {
        const rt = routeSnap.docs[0];
        const existing = Array.isArray(rt.data().orders) ? rt.data().orders.slice() : [];
        if (!existing.includes(orderId)) existing.push(orderId);
        t.update(rt.ref, { orders: existing, updatedAt: ts() });
        routeId = rt.id;
      } else {
        const routeRef = db.collection(ROUTES).doc();
        t.set(routeRef, {
          orders: [orderId], courierId, status: 'active', currentIndex: 0,
          routeSource: 'restaurant_claim', createdAt: ts(), startedAt: ts(),
        });
        routeId = routeRef.id;
      }
      t.update(orderRef, { courierId, deliveryRouteId: routeId, courierClaimedAt: ts(), updatedAt: ts() });
      addEvent(t, orderRef, { from: od.restaurantStatus, to: od.restaurantStatus, actor: 'courier', actorId: courierId, reason: 'claimed', meta: { routeId } });
      return { ok: true, routeId, restaurantId: od.restaurantId, customerUid: od.userPhone };
    }), (od) => {
      const assigned = canonicalUid(String(od.courierId || ''));
      if (assigned && assigned === courierId) return { ok: true, idempotent: true, routeId: od.deliveryRouteId };
      if (assigned) throw fail('failed-precondition', 'COURIER_ASSIGNMENT_CONFLICT');
      return null;
    });
    if (!out.idempotent) {
      log('claim', { orderId, restaurantId: out.restaurantId, userId: courierId, result: 'ok', routeId: out.routeId, durationMs: Date.now() - t0 });
      await notifyMembers(String(out.restaurantId), { title: '🛵 Kuryer biriktirildi', body: 'Kuryer buyurtmani olishga kelmoqda', orderId });
      if (out.customerUid) await notifyCustomer(canonicalUid(out.customerUid), { title: '🛵 Kuryer topildi', body: 'Buyurtmangizni kuryer yetkazadi', orderId });
    }
    return { ok: true, routeId: out.routeId, idempotent: !!out.idempotent };
  });

  /** Olib ketdim — faqat `ready` va to'g'ri `pickupCode` (restoran aytadi). */
  exportsObj.courierPickupRestaurantOrder = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const courierId = await courierAuthOf().resolve(uid, COURIER_AUTH_MODES.finish);
    const orderId = str(data && data.orderId, 64);
    const code = str(data && data.pickupCode, 8);
    const orderRef = db.collection(ORDERS).doc(orderId);
    await courierAuthOf().assertOrderOnActiveRoute(courierId, orderId);
    const out = await db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      courierAuthOf().assertOrderActionable(od, courierId, 'courierPickupRestaurantOrder', orderId);
      if (od.restaurantStatus === RS.picked) return { ok: true, idempotent: true };
      if (od.restaurantStatus !== RS.ready) throw fail('failed-precondition', 'RESTAURANT_NOT_READY', { from: od.restaurantStatus });
      const secretRef = orderRef.collection(PRIVATE).doc('secrets');
      const sec = await t.get(secretRef);
      const sd = sec.exists ? (sec.data() || {}) : {};
      const attempts = Number(sd.pickupAttempts) || 0;
      if (attempts >= PICKUP_CODE_ATTEMPTS) throw fail('failed-precondition', 'PICKUP_CODE_LOCKED');
      if (!code || String(sd.pickupCode || '') !== code) {
        t.update(secretRef, { pickupAttempts: inc(1), lastAttemptAt: ts() });
        return { mismatch: true, left: PICKUP_CODE_ATTEMPTS - attempts - 1 };
      }
      assertTransition(od, RS.picked, orderId);
      const buyout = od.foodPaymentMethod === 'cash_buyout';
      const foodAmount = (Number(od.itemsTotal) || 0) + (Number(od.packagingTotal) || 0);
      t.update(orderRef, statusPatch(RS.picked, {
        pickedAt: ts(), inDeliveryAt: ts(), courierId,
        ...(buyout ? { paymentStatus: 'paid', paidAt: ts(), paidBy: 'courier_buyout', buyoutAmount: foodAmount } : {}),
      }));
      addEvent(t, orderRef, { from: RS.ready, to: RS.picked, actor: 'courier', actorId: courierId, meta: buyout ? { buyoutPaid: foodAmount } : {} });
      return { ok: true, customerUid: od.userPhone };
    });
    if (out.mismatch) {
      log('pickup', { orderId, userId: courierId, result: 'denied', errorCode: 'PICKUP_CODE_MISMATCH' });
      throw fail('failed-precondition', 'PICKUP_CODE_MISMATCH', { attemptsLeft: out.left });
    }
    if (!out.idempotent && out.customerUid) await notifyCustomer(canonicalUid(out.customerUid), { title: '🛵 Buyurtma yo\'lda', body: 'Kuryer restorandan olib chiqdi', orderId });
    return { ok: true };
  });

  exportsObj.courierArriveRestaurantOrder = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const courierId = await courierAuthOf().resolve(uid, COURIER_AUTH_MODES.finish);
    const orderId = str(data && data.orderId, 64);
    const orderRef = db.collection(ORDERS).doc(orderId);
    await courierAuthOf().assertOrderOnActiveRoute(courierId, orderId);
    const out = await db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      courierAuthOf().assertOrderActionable(od, courierId, 'courierArriveRestaurantOrder', orderId);
      if (od.restaurantStatus === RS.arrived) return { ok: true, idempotent: true };
      assertTransition(od, RS.arrived, orderId);
      t.update(orderRef, statusPatch(RS.arrived, { arrivedAt: ts(), courierId }));
      addEvent(t, orderRef, { from: RS.picked, to: RS.arrived, actor: 'courier', actorId: courierId });
      return { ok: true, customerUid: od.userPhone };
    });
    if (!out.idempotent && out.customerUid && notifyCourierArrivedToCustomer) {
      try { await notifyCourierArrivedToCustomer(out.customerUid, { orderId, module: MODULE_ID }); } catch (e) { console.error('restaurant arrive notify:', e.message || e); }
    }
    return { ok: true };
  });

  /**
   * Yakun: `delivered` (yetkazish puli naqd yoki mijoz hamyoni → kuryer hamyoni)
   * yoki `delivery_failed` (2 % restoranga qaytadi, mijozga strike).
   * Idempotent: `wallet_idempotency/rest_complete_{orderId}`.
   */
  exportsObj.courierCompleteRestaurantDelivery = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    const courierId = await courierAuthOf().resolve(uid, COURIER_AUTH_MODES.finish);
    const orderId = str(data && data.orderId, 64);
    const outcome = (data && data.outcome) === 'failed' ? 'failed' : 'delivered';
    const failReason = FAIL_REASONS.includes(data && data.failReason) ? data.failReason : 'other';
    const orderRef = db.collection(ORDERS).doc(orderId);
    const idemRef = db.collection(IDEMPOTENCY).doc(`rest_complete_${orderId}`);
    await courierAuthOf().assertOrderOnActiveRoute(courierId, orderId);
    const out = await db.runTransaction(async (t) => {
      // READ fazasi.
      const [idemSnap, od] = await Promise.all([t.get(idemRef), getOrderInTx(t, orderRef)]);
      courierAuthOf().assertOrderActionable(od, courierId, 'courierCompleteRestaurantDelivery', orderId);
      if (idemSnap.exists) return { done: true, result: { ...(idemSnap.data().result || { ok: true }), idempotent: true } };
      const to = outcome === 'delivered' ? RS.delivered : RS.deliveryFailed;
      const from = assertTransition(od, to, orderId);
      // `ready → delivered` jadvalda restoranning O'Z kuryeri uchun (restaurantMarkDelivered).
      // AVA kuryeri esa olmasdan (kod, `picked`, `arrived` siz) yakunlay olmaydi:
      // buyurtma `accepted`da marshrutga olinadi, `ready` bo'lgach kod aylanib o'tilardi.
      if (from !== RS.picked && from !== RS.arrived) {
        log('complete', { orderId, result: 'denied', errorCode: 'ORDER_NOT_PICKED', from, to });
        throw fail('failed-precondition', 'ORDER_NOT_PICKED', { from, to });
      }
      const customerUid = canonicalUid(String(od.userPhone || ''));
      const fee = Number(od.deliveryFee) || 0;
      let walletPrep = null;
      let refundPrep = null;
      let prevStrikes = 0;
      if (to === RS.delivered && od.deliveryPaymentMethod === 'wallet' && fee > 0) {
        walletPrep = await settlementLedger.prepareBonusInTx(t, db, customerUid, {
          fundingAccount: settlementLedger.passengerCreditAccount(courierId),
          idempotencyKey: `restDelivery_${orderId}`,
        });
      }
      if (to === RS.deliveryFailed) {
        refundPrep = await prepareFeeInTx(t, od, orderId, false);
        const stSnap = await t.get(db.collection(CUSTOMER_STATS).doc(customerUid));
        prevStrikes = stSnap.exists ? (Number((stSnap.data() || {}).strikes) || 0) : 0;
      }
      // WRITE fazasi.
      let deliveryPaymentMethod = od.deliveryPaymentMethod || 'cash';
      let walletPaid = 0;
      let deliveryFeeFallback = null;
      if (walletPrep) {
        if (walletPrep.jExists) {
          walletPaid = fee;
        } else if (walletPrep.pcPrev >= fee) {
          settlementLedger.commitBonusInTx(t, walletPrep, {
            delta: -fee, kind: 'restaurant_delivery_fee', refType: 'order', refId: orderId,
            meta: { module: MODULE_ID, courierId: courierId.slice(-4) }, postedBy: customerUid, postedRole: 'client',
          });
          const cRef = db.collection('users').doc(customerUid);
          const kRef = db.collection('users').doc(courierId);
          t.set(cRef, { bonusBalance: inc(-fee), balanceUpdatedAt: ts() }, { merge: true });
          t.set(cRef.collection('wallet_ledger').doc(), { type: 'restaurant_delivery_debit', amount: -fee, module: MODULE_ID, refType: 'order', refId: orderId, meta: {}, createdAt: ts(), createdBy: 'server' });
          t.set(kRef, { bonusBalance: inc(fee), balanceUpdatedAt: ts() }, { merge: true });
          t.set(kRef.collection('wallet_ledger').doc(), { type: 'restaurant_delivery_credit', amount: fee, module: MODULE_ID, refType: 'order', refId: orderId, meta: {}, createdAt: ts(), createdBy: 'server' });
          walletPaid = fee;
        } else {
          deliveryPaymentMethod = 'cash';
          deliveryFeeFallback = 'insufficient_wallet';
        }
      }
      const buyout = od.foodPaymentMethod === 'cash_buyout';
      const foodAmount = (Number(od.itemsTotal) || 0) + (Number(od.packagingTotal) || 0);
      const cashCollected = to === RS.delivered
        ? (buyout ? foodAmount : 0) + (deliveryPaymentMethod === 'cash' ? fee : 0)
        : 0;
      let refund = { applied: false, amount: 0 };
      if (to === RS.delivered) {
        t.update(orderRef, statusPatch(RS.delivered, {
          deliveredAt: ts(), completedAt: ts(), courierId, deliveryPaymentMethod, deliveryFeeFallback,
          deliveryFeeWalletPaid: walletPaid, cashCollected, cashPaid: cashCollected,
          ...(buyout || od.paymentStatus === 'paid' ? { paymentStatus: 'paid' } : {}),
        }));
        t.set(db.collection(CUSTOMER_STATS).doc(customerUid), { completedCount: inc(1), updatedAt: ts() }, { merge: true });
      } else {
        refund = commitFeeInTx(t, refundPrep, { orderId, actorId: courierId });
        const strike = ['customer_absent', 'customer_refused'].includes(failReason);
        t.update(orderRef, statusPatch(RS.deliveryFailed, {
          failedAt: ts(), courierId, failReason, 'avaFee.refunded': refund.applied, 'avaFee.refundedAt': refund.applied ? ts() : null,
          rejectReason: `delivery_failed:${failReason}`,
        }));
        if (strike) {
          // Mijoz eshikda olmadi — strike; ikkinchisidan faqat oldindan
          // to'lov (PROPOSED, §11.2.4). Oldingi qiymat READ fazasida o'qilgan.
          const strikes = prevStrikes + 1;
          const prepayOnly = strikes >= STRIKES_FOR_PREPAY_ONLY;
          t.set(db.collection(CUSTOMER_STATS).doc(customerUid), {
            strikes, lastStrikeAt: ts(), updatedAt: ts(),
            ...(prepayOnly ? { prepayOnlyUntil: tsOf(new Date(now().getTime() + PREPAY_ONLY_DAYS * 24 * 3600 * 1000)) } : {}),
          }, { merge: true });
        }
      }
      const result = { ok: true, orderId, outcome, deliveryFee: fee, walletPaid, cashCollected, refundAmount: refund.amount, deliveryPaymentMethod };
      t.set(idemRef, { type: 'courierCompleteRestaurantDelivery', result, createdAt: ts() });
      addEvent(t, orderRef, { from, to, actor: 'courier', actorId: courierId, reason: to === RS.deliveryFailed ? failReason : '', meta: { walletPaid, cashCollected, refundAmount: refund.amount } });
      return { done: false, result, customerUid, restaurantId: od.restaurantId };
    });
    if (out.done) return out.result;
    log('complete', { orderId, restaurantId: out.restaurantId, userId: courierId, result: outcome, walletPaid: out.result.walletPaid, durationMs: Date.now() - t0 });
    if (outcome === 'delivered') {
      await notifyCustomer(out.customerUid, { title: '✅ Buyurtma yetkazildi', body: 'Yoqimli ishtaha!', orderId });
    } else {
      await notifyMembers(String(out.restaurantId), { title: 'Yetkazib bo\'lmadi', body: 'Kuryer buyurtmani yetkaza olmadi', orderId });
    }
    return out.result;
  });

  // ═══════════════════════════════════════════════════════════════════════
  // JADVAL: qabul qilinmagan buyurtmalar (taymaut) — har daqiqa
  // ═══════════════════════════════════════════════════════════════════════

  async function expireOne(orderRef, at) {
    return db.runTransaction(async (t) => {
      const s = await t.get(orderRef);
      if (!s.exists) return null;
      const od = s.data() || {};
      if (od.type !== 'restaurant' || od.restaurantStatus !== RS.placed) return null;
      const dl = od.acceptDeadlineAt && od.acceptDeadlineAt.toMillis ? od.acceptDeadlineAt.toMillis() : 0;
      if (!dl || dl > at.getTime()) return null;
      const rRef = db.collection(RESTAURANTS).doc(String(od.restaurantId || ''));
      const rSnap = await t.get(rRef);
      const streak = (rSnap.exists ? Number((rSnap.data() || {}).timeoutStreak) || 0 : 0) + 1;
      t.update(orderRef, statusPatch(RS.rejected, { rejectedAt: ts(), rejectedBy: 'system', rejectReason: 'timeout' }));
      addEvent(t, orderRef, { from: RS.placed, to: RS.rejected, actor: 'system', reason: 'timeout' });
      if (rSnap.exists) {
        const pause = streak >= AUTO_PAUSE_AFTER_TIMEOUTS;
        t.update(rRef, {
          timeoutStreak: pause ? 0 : streak, updatedAt: ts(),
          ...(pause ? { pausedUntil: tsOf(new Date(at.getTime() + AUTO_PAUSE_MIN * 60 * 1000)), pausedReason: 'timeouts' } : {}),
        });
      }
      return { orderId: orderRef.id, customerUid: od.userPhone, restaurantId: od.restaurantId, streak };
    });
  }

  async function expireUnaccepted() {
    const at = now();
    const snap = await db.collection(ORDERS)
      .where('type', '==', 'restaurant')
      .where('restaurantStatus', '==', RS.placed)
      .where('acceptDeadlineAt', '<=', tsOf(at))
      .limit(200)
      .get();
    let expired = 0;
    for (const doc of snap.docs) {
      try {
        const r = await expireOne(doc.ref, at);
        if (!r) continue;
        expired += 1;
        log('expire', { orderId: r.orderId, restaurantId: r.restaurantId, result: 'rejected_timeout', streak: r.streak });
        await notifyCustomer(canonicalUid(String(r.customerUid || '')), { title: 'Restoran javob bermadi', body: 'Buyurtma qabul qilinmadi — boshqa restoranni tanlang', orderId: r.orderId });
      } catch (e) {
        console.error('restaurant expire:', doc.id, e.message || e);
      }
    }
    return { scanned: snap.size, expired };
  }

  exportsObj.expireUnacceptedRestaurantOrders = functions.pubsub
    .schedule('every 1 minutes')
    .timeZone('Asia/Tashkent')
    .onRun(async () => expireUnaccepted());

  return {
    // test/diagnostika uchun sof qismlar
    RS, TRANSITIONS, LEGACY, canTransition, isOpenAt, expireUnaccepted, moduleAccess,
    ACCEPT_TIMEOUT_MIN, AUTO_PAUSE_AFTER_TIMEOUTS,
  };
}

module.exports = {
  attachRestaurantOrders,
  RS, TRANSITIONS, LEGACY, canTransition, isOpenAt, hhmmToMin,
  ACCEPT_TIMEOUT_MIN, AUTO_PAUSE_AFTER_TIMEOUTS, AUTO_PAUSE_MIN,
  STRIKES_FOR_PREPAY_ONLY, PREPAY_ONLY_DAYS, PICKUP_CODE_ATTEMPTS,
  EARNINGS_ACCOUNT, MODULE_ID,
};
