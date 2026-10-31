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
const qtyTiers = require('./restaurant_qty_tiers');
const preorder = require('./restaurant_preorder');
const moduleGate = require('./module_gate');

/** `restaurantRegister` idempotentligi (C-2): mijoz kaliti va deterministik restoran id. */
const REGISTER_REQUEST_ID_RE = /^[A-Za-z0-9_-]{8,64}$/;
function restaurantIdFor(uid, requestId) {
  const h = crypto.createHash('sha256').update(`restaurantRegister:${uid}:${requestId}`).digest('hex');
  return `rst_${h.slice(0, 28)}`;
}

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
/** Kuryerning buyurtma bo'yicha jonli nuqtasi (S6); yozuvchi — kuryer ilovasi (rules), o'chiruvchi — shu fayl. */
const COURIER_LIVE = 'order_courier_live';
const COURIER_LIVE_TTL_MIN = 120;

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
/** Taomga alohida izoh uzunligi (klientdagi `RestaurantCart.maxItemNote` shuning nusxasi). */
const MAX_ITEM_NOTE = 100;
/**
 * Bir taomdan eng ko'p miqdor (D-REST-26): restoranning `maxQtyPerItem` maydoni,
 * yo'q bo'lsa — DEFAULT. CEILING — platforma shipi (firestore.rules ham 500).
 * Klientdagi `Restaurant.defaultMaxQtyPerItem` shu DEFAULT ning nusxasi.
 */
const DEFAULT_MAX_QTY = 50;
const MAX_QTY_CEILING = 500;
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
/**
 * Muassasa turi — kartada ko'rinadigan ixcham nom (D-REST-41, ega 2026-10-19): uy ovqati («Уй таоми») FAQAT uy ovqatchisi
 * (`legalType: individual`) uchun va avtomatik; kafe-restoran egasi 3 tadan birini o'zi tanlaydi. Eski hujjatlarga TEGILMAYDI.
 */
const VENUE_CHOICES = ['cafe', 'restaurant', 'chaikhana'];
const DELIVERY_MODES = ['ava_courier', 'own_courier', 'none'];
const FOOD_PAYMENT = ['prepay', 'cash_buyout', 'cash_to_restaurant'];
const DELIVERY_PAYMENT = ['cash', 'wallet', 'none'];
const FAIL_REASONS = ['customer_absent', 'customer_refused', 'courier_problem', 'other'];

/**
 * «Етказилмади» — мижоз тасдиғи (ega qarori 2026-10-31, C-1/C-2/A-1):
 *   kuryer 'failed' → `awaitingCustomerConfirm.step = 'delivery_failed'` (+ failReason, escalateAt);
 *   mijoz 'confirm' → delivery_failed (avvalgi yakun: 2 % qaytadi, strike sababga qarab);
 *   mijoz 'reject'  → belgi o'chadi, kuryer yetkazishni davom ettiradi;
 *   `failedTimeoutMin` (server_config/customer_confirm, standart 15) o'tsa → `escalateRestaurantDeliveryFailed`
 *   restoranga xabar beradi va `restaurantResolveDeliveryFailed` ochiladi (restoran a'zosi yoki admin).
 * Joriy holat maydonlari (faqat server yozadi; `orders` klient yozuvi yopiq):
 *   deliveryFailedEscalateAt  — muddat (jadval so'rovi uchun; eskalatsiyadan keyin o'chadi)
 *   deliveryFailedEscalatedAt — qaror restoranga o'tgan vaqt
 *   deliveryFailedResolution  — { by: customer|restaurant|admin, decision: failed|continue, at, actorId }
 * Tarix — `order_events` (o'zgarmas).
 */
const FAILED_STEP = 'delivery_failed';
const FAILED_ESCALATE_AT = 'deliveryFailedEscalateAt';
const FAILED_ESCALATED_AT = 'deliveryFailedEscalatedAt';
const FAILED_RESOLUTION = 'deliveryFailedResolution';
const FAILED_DECISIONS = ['failed', 'continue'];
const ESCALATE_BATCH = 100;
const { MARKER_FIELD: CC_MARKER_FIELD, REJECTED_FIELD: CC_REJECTED_FIELD } = require('./customer_confirm');
const i18n = require('./notif_i18n');

const msOf = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : null);

/**
 * TOPSHIRISH (ega qarorlari 2026-10-31: C-4..C-7, A-2, A-3) — FAQAT restoran buyurtmasi
 * (boshqa turlar alohida qaror, hisobotda UNKNOWN):
 *   - olishdan OLDIN (accepted/ready): kuryer buyurtmani qo'yib yuboradi → yangi kuryer qidiriladi;
 *   - olgandan KEYIN (picked/arrived): kod bilan jismoniy topshirish — boshqa kuryerga
 *     (`courierAcceptRestaurantHandover`, kod + GPS) yoki restoranga (`restaurantAcceptReturn`, kod);
 *   - restoranga qaytgach / qo'yib yuborilgach `RETURN_SEARCH_MIN` (30) daqiqa yangi kuryer
 *     qidiriladi; topilmasa buyurtma bekor (2 % restoranga qaytadi) — jadval `expireReturnedRestaurantOrders`;
 *   - chegara va jarima YO'Q;
 *   - kuryer haqi masofa ulushi bo'yicha (`computeCourierShares`): butun so'm, qoldiq oxirgi kuryerga.
 *   Custody zanjiri — mavjud `custody_events` (o'zgarmas; logistics bilan bir kolleksiya, `orderType: 'restaurant'`,
 *   `shipmentId`/`completesLegId`/`deliversShipment` YO'Q — relay/wholesale triggerlari o'tkazib yuboradi).
 */
const HANDOVER_TTL_MIN = 15;
const HANDOVER_CODE_ATTEMPTS = 5;
const HANDOVER_CALLER_ATTEMPTS = 10;
const HANDOVER_CALLER_WINDOW_MIN = 30;
const RETURN_SEARCH_MIN = 30;
const HANDOVER_TARGETS = ['courier', 'seller'];
const HANDOVER_CODES = 'courier_handover_codes';
const HANDOVER_ATTEMPTS = 'courier_handover_attempts';
const CUSTODY = 'custody_events';
/** Naqd ulush o'tkazmasi niyati (faqat server; rules'da match yo'q = klientga yopiq). */
const SHARE_PENDING = 'restaurant_courier_share_pending';
const cashShareId = (orderId, from, to) => `${orderId}_${from}_${to}`;

/**
 * Kuryerlar ulushi (A-3): `legs` = [{ courierId, meters }] tartib bilan (oxirgisi — yetkazgan kuryer).
 * Bir kuryer bir necha bo'lak olib borgan bo'lsa — qo'shiladi. Butun so'm (floor), qoldiq OXIRGI
 * kuryerga; jami har doim `fee` ga teng. Masofa yig'indisi 0 bo'lsa — hammasi oxirgi kuryerga.
 */
function computeCourierShares(fee, legs) {
  const total = Number.isInteger(fee) && fee > 0 ? fee : 0;
  const order = [];
  const meters = new Map();
  for (const l of Array.isArray(legs) ? legs : []) {
    const id = String((l && l.courierId) || '');
    if (!id) continue;
    const m = Number(l.meters);
    const add = Number.isFinite(m) && m > 0 ? Math.round(m) : 0;
    if (!meters.has(id)) order.push(id);
    meters.set(id, (meters.get(id) || 0) + add);
  }
  if (order.length === 0) return [];
  const last = String(legs[legs.length - 1].courierId);
  const sumM = order.reduce((s, id) => s + meters.get(id), 0);
  const out = order.map((id) => ({ courierId: id, meters: meters.get(id), amount: 0 }));
  if (sumM <= 0) {
    out.find((x) => x.courierId === last).amount = total;
    return out;
  }
  let given = 0;
  for (const x of out) {
    if (x.courierId === last) continue;
    x.amount = Math.floor((total * x.meters) / sumM);
    given += x.amount;
  }
  out.find((x) => x.courierId === last).amount = total - given;
  return out;
}

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

/**
 * Taom puli (mijoz restoranga to'laydigan, AVA kuryeri vykup qiladigan summa) = taom + ESKI buyurtmalardagi
 * qadoqlash. Qadoqlash haqi olib tashlangan (D-REST-28): yangi buyurtmada packagingTotal yo'q → 0;
 * eski hujjatlar to'g'ri o'qilishi uchun maydon saqlanadi. Hamma joyda SHU funksiya (7-qoida).
 */
function foodAmountOf(od) {
  return (Number(od.itemsTotal) || 0) + (Number(od.packagingTotal) || 0);
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

/** Xabar matni uchun Toshkent vaqti: `21.10 19:00` (TASHKENT_UTC_OFFSET_H; yozgi vaqt yo'q). */
function tashkentLabel(date) {
  const t = new Date(date.getTime() + TASHKENT_UTC_OFFSET_H * 3600 * 1000);
  const p = (n) => String(n).padStart(2, '0');
  return `${p(t.getUTCDate())}.${p(t.getUTCMonth() + 1)} ${p(t.getUTCHours())}:${p(t.getUTCMinutes())}`;
}

function pickupCode() {
  return String(crypto.randomInt(0, 10000)).padStart(4, '0');
}

function attachRestaurantOrders(exportsObj, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, settlementLedger,
    requireCallerRoles, notifyUserInApp, notifyCourierArrivedToCustomer, axios,
    fetchRoute: fetchRouteOverride, now: nowFn, courierPush,
    // Mijoz tasdig'i (D2/D7): `customer_confirm.js`. Yo'q bo'lsa — eski oqim (gate yo'q).
    customerConfirm,
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

  /** «Yetkazilmadi» kutish maydonlari bo'lsa — o'chirish yamoqchasi, aks holda `{}` (eski hujjat o'zgarmaydi). */
  function failedPendingClear(od) {
    if (!od || (od[FAILED_ESCALATE_AT] === undefined && od[FAILED_ESCALATED_AT] === undefined)) return {};
    const del = admin.firestore.FieldValue.delete();
    return { [FAILED_ESCALATE_AT]: del, [FAILED_ESCALATED_AT]: del };
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

  /**
   * `preloaded` — chaqiruvchi hujjatni allaqachon o'qigan bo'lsa (ortiqcha o'qish yo'q; kuryer auditi D9).
   * `at` — oldindan buyurtmada yetkazish vaqti (S4b, tungi koeffitsient shu vaqtga qarab).
   */
  async function quoteDelivery(r, { toLat, toLng, at: atOverride }, preloaded) {
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
    // Oldindan buyurtmada tungi koeffitsient YETKAZISH vaqtiga qarab (S4b): ertaga 02:00 ga buyurtma — tungi narx.
    const at = atOverride || now();
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

  /** Kuryerning ko'rsatiladigan ismi (profilidagi `name`, ≤ 40 belgi); topilmasa bo'sh (xato yutiladi). */
  async function courierDisplayName(courierId) {
    try {
      const u = await findUserRef(canonicalUid(String(courierId || '')));
      const d = u ? u.data : {};
      return str(d.name || d.fullName || '', 40);
    } catch (e) {
      return '';
    }
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
      const foodAmount = foodAmountOf(od);
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

  /** D-REST-7: barcha ro'yxatdan o'tadi. Ega, 2026-10-31: «серверда доим дарҳол жонли бўлсин» — yangi obyekt
   *  DOIM `approved` (avvalgi `settings/app.restaurantAutoApprove` kaliti endi o'qilmaydi; nazorat — admin bloki). */
  exportsObj.restaurantRegister = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    await requireModule(uid);
    // C-2 IDEMPOTENT (21-qoida): ixtiyoriy `requestId` → deterministik hujjat id (`submitJobAd` namunasi).
    // Shu chaqiruvchi + shu `requestId` qayta kelsa — BIRINCHI natija qaytadi, ikkinchi restoran yaratilmaydi.
    // `requestId` yo'q/yaroqsiz (eski ilova) — avvalgi xatti-harakat (avto-id).
    const requestId = str(data && data.requestId, 64);
    const rRefFixed = REGISTER_REQUEST_ID_RE.test(requestId)
      ? db.collection(RESTAURANTS).doc(restaurantIdFor(uid, requestId)) : null;
    const duplicateOf = (snap) => {
      const x = snap.data() || {};
      log('register', { restaurantId: snap.id, userId: uid, result: 'duplicate', durationMs: Date.now() - t0 });
      return { ok: true, restaurantId: snap.id, status: String(x.status || RESTAURANT_STATUS.applied), duplicate: true };
    };
    if (rRefFixed) {
      const existing = await rRefFixed.get();
      if (existing.exists) {
        if (existing.data().ownerUid !== uid) throw fail('failed-precondition', 'REQUEST_ID_CONFLICT');
        return duplicateOf(existing);
      }
    }
    // MEDIUM-4: admin «Ҳудудлар ва хизматлар» — `restaurants` moduli shu foydalanuvchi hududida ochiq bo'lishi
    // shart (yuqoridagi `requireModule` bosqich darvozasiga QO'SHIMCHA). Konfig o'qilmasa — fail-open.
    const gate = await moduleGate.moduleOpenFor(db, MODULE_ID, uid, { activeDistrictId: data && data.geoDistrictId });
    if (!gate.open) {
      log('register', { userId: uid, result: 'error', errorCode: moduleGate.MODULE_CLOSED, moduleStatus: gate.status });
      throw fail('failed-precondition', moduleGate.MODULE_CLOSED, { moduleId: MODULE_ID, status: gate.status });
    }
    const user = await findUserRef(uid);
    if (!user) throw fail('failed-precondition', 'USER_NOT_FOUND');
    const d = data || {};
    const name = str(d.name, 80);
    if (name.length < 2) throw fail('invalid-argument', 'NAME_REQUIRED');
    const legalType = LEGAL_TYPES.includes(d.legalType) ? d.legalType : 'individual';
    // Uy ovqatchisi — doim `home`; boshqalar: berilgan bo'lsa to'g'ri bo'lishi shart; berilmasa (eski ilova) — maydon yozilmaydi.
    let venueType = null;
    if (legalType === 'individual') {
      venueType = 'home';
    } else if (d.venueType != null && d.venueType !== '') {
      if (!VENUE_CHOICES.includes(d.venueType)) throw fail('invalid-argument', 'VENUE_TYPE_INVALID');
      venueType = d.venueType;
    }    const lat = Number(d.lat);
    const lng = Number(d.lng);
    if (!validLatLng(lat, lng)) throw fail('invalid-argument', 'LOCATION_REQUIRED');
    // Matnli manzil ham majburiy (ega 2026-10-23): mijoz «olib ketish»da va kuryer shu manzilga boradi.
    const address = str(d.address, 300);
    if (!address) throw fail('invalid-argument', 'ADDRESS_REQUIRED');
    const delivery = d.delivery && typeof d.delivery === 'object' ? d.delivery : {};
    const mode = DELIVERY_MODES.includes(delivery.mode) ? delivery.mode : 'none';
    const pickup = delivery.pickup === true;
    if (mode === 'none' && !pickup) throw fail('invalid-argument', 'DELIVERY_OR_PICKUP_REQUIRED');
    const payment = d.payment && typeof d.payment === 'object' ? d.payment : {};
    // Ariza zanjiri yo'q (ega, 2026-10-31): yangi kafe/uy oshpazi darhol jonli.
    const autoApprove = true;

    // Bir foydalanuvchi bir nechta kafe-restoran yuritadi (menejerlik,
    // D-REST-15, ega 2026-10-10): egaga son chegarasi YO'Q — tarmoq
    // (set) bo'lishi mumkin. Suiiste'mol admin tasdig'i orqali nazorat qilinadi.
    const rRef = rRefFixed || db.collection(RESTAURANTS).doc();
    const batch = db.batch();
    // `create` — hujjat allaqachon bo'lsa (parallel ikki chaqiruv) butun batch rad etiladi (a'zo/private ham yozilmaydi).
    batch.create(rRef, {
      name,
      legalType,
      ...(venueType ? { venueType } : {}),
      description: str(d.description, 500),
      cuisineTags: Array.isArray(d.cuisineTags) ? d.cuisineTags.map((x) => str(x, 30)).filter(Boolean).slice(0, 3) : [],
      address,
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
    try {
      await batch.commit();
    } catch (e) {
      // Poyga: shu `requestId` bilan parallel chaqiruv birinchi yaratdi — o'shani qaytaramiz.
      if (rRefFixed && e && (e.code === 6 || /ALREADY_EXISTS/i.test(String(e.message || '')))) {
        const again = await rRefFixed.get();
        if (again.exists && again.data().ownerUid === uid) return duplicateOf(again);
      }
      throw e;
    }
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

  /** Admin — `settings/app.restaurantAutoApprove`. ESKI admin panellar uchun qoldirildi: 2026-10-31 dan
   *  `restaurantRegister` bu kalitni O'QIMAYDI (doim darhol jonli, ega qarori) — admin panelda tugma olib tashlandi. */
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
      // Oldindan buyurtma: tungi koeffitsient yetkazish vaqtiga (noto'g'ri qiymat e'tiborsiz — oddiy hisob).
      const sched = preorder.parseScheduled(data && data.scheduledForMs);
      const quoteAt = sched.ms != null ? new Date(sched.ms) : undefined;
      if (mode === 'ava_courier') {
        const q = await quoteDelivery(r, { toLat, toLng, at: quoteAt });
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
      // Oldindan buyurtma (S4b): bajarilish vaqti; barcha chegara va ish vaqti tekshiruvi pastda, serverda.
      const sched = preorder.parseScheduled(d.scheduledForMs);
      if (sched.error) throw fail('invalid-argument', sched.error);

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
      // Намуна (demo) ресторан: лентада кўринади, лекин буюртма қабул қилинмайди (`functions/restaurant_demo.js`).
      if (r.isDemo === true) throw fail('failed-precondition', 'RESTAURANT_DEMO');
      if (canonicalUid(String(r.ownerUid || '')) === uid) throw fail('failed-precondition', 'OWN_RESTAURANT');
      const at = now();
      const pausedUntilMs = r.pausedUntil && typeof r.pausedUntil.toMillis === 'function' ? r.pausedUntil.toMillis() : 0;
      let scheduledFor = null;
      if (sched.ms != null) {
        // Oldindan buyurtma: restoran belgisi, 60 daqiqa…7 kun oynasi, ish vaqti VA pauza — BAJARILISH vaqtida.
        // «Hozir ochiqmi» tekshiruvi qo'llanmaydi (restoran hozir yopiq bo'lsa ham ertangi buyurtma mumkin).
        if (r.acceptsPreorder !== true) throw fail('failed-precondition', 'PREORDER_NOT_ACCEPTED');
        const windowErr = preorder.checkWindow(at.getTime(), sched.ms);
        if (windowErr) throw fail('failed-precondition', windowErr, { minLeadMin: preorder.MIN_LEAD_MIN, maxDays: preorder.MAX_DAYS });
        scheduledFor = new Date(sched.ms);
        if (pausedUntilMs > sched.ms) throw fail('failed-precondition', 'RESTAURANT_PAUSED');
        if (!isOpenAt(r.openingHours, scheduledFor)) throw fail('failed-precondition', 'PREORDER_CLOSED_AT_TIME');
      } else {
        if (pausedUntilMs > at.getTime()) throw fail('failed-precondition', 'RESTAURANT_PAUSED');
        if (!isOpenAt(r.openingHours, at)) throw fail('failed-precondition', 'RESTAURANT_CLOSED');
      }

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
      // Taomga alohida izoh («piyozsiz»): bir taom bir nechta qatorda kelsa, birinchi BO'SH BO'LMAGAN izoh olinadi.
      // Izoh narxga ta'sir qilmaydi, faqat oshpazga ko'rsatiladi; eski klient yubormaydi — maydon ixtiyoriy.
      const itemNotes = new Map();
      for (const it of itemsIn) {
        const id = str(it && it.itemId, 64);
        const qty = intOr(it && it.qty, 0, 1, MAX_QTY_CEILING);
        if (!id || qty < 1) throw fail('invalid-argument', 'ITEM_INVALID');
        wanted.set(id, (wanted.get(id) || 0) + qty);
        const itemNote = str(it && it.note, MAX_ITEM_NOTE);
        if (itemNote && !itemNotes.has(id)) itemNotes.set(id, itemNote);
      }
      // Limit YIG'INDI miqdorga: bir taom bir nechta qatorda kelsa ham aylanib o'tilmaydi.
      const maxQty = intOr(r.maxQtyPerItem, DEFAULT_MAX_QTY, 1, MAX_QTY_CEILING);
      for (const [itemId, count] of wanted) {
        if (count > maxQty) throw fail('failed-precondition', 'QTY_LIMIT_EXCEEDED', { itemId, maxQty });
      }
      const itemSnaps = await db.getAll(...[...wanted.keys()].map((id) => rRef.collection(MENU_ITEMS).doc(id)));
      const items = [];
      let itemsTotal = 0;
      let qtyDiscountTotal = 0;
      for (const s of itemSnaps) {
        if (!s.exists) throw fail('failed-precondition', 'MENU_ITEM_NOT_FOUND', { itemId: s.id });
        const m = s.data() || {};
        const stopped = m.stopUntil && typeof m.stopUntil.toMillis === 'function' && m.stopUntil.toMillis() > at.getTime();
        if (m.available === false || stopped) throw fail('failed-precondition', 'MENU_ITEM_UNAVAILABLE', { itemId: s.id });
        // Faqat HAQIQIY butun son: `'5000'` satri ham rad (menyuni restoran
        // yozadi — klient ma'lumoti, 18-qoida; qoida ham `int` talab qiladi).
        const price = typeof m.price === 'number' ? m.price : Number.NaN;
        if (!Number.isInteger(price) || price <= 0 || price > MAX_PRICE) throw fail('failed-precondition', 'MENU_PRICE_INVALID', { itemId: s.id });
        // Qadoqlash haqi YO'Q (D-REST-28): qadoqlashni har sotuvchi o'z narxiga kiritadi.
        // Eski menyu hujjatlaridagi `packagingFee` e'tiborsiz — buyurtma summasiga kirmaydi.
        const count = wanted.get(s.id);
        // Miqdorga chegirma (D-REST-25): pog'ona menyudan, restoran hisobidan; son YIG'INDI bo'yicha.
        const { unitPrice, tierMinQty } = qtyTiers.unitPriceFor(price, m.qtyTiers, count);
        const lineTotal = unitPrice * count;
        const discount = price * count - lineTotal;
        itemsTotal += lineTotal;
        qtyDiscountTotal += discount;
        // `price` — ro'yxat narxi (o'zgarmas), `unitPrice` — qo'llangan narx; ikkalasi snapshot (9-qoida).
        items.push({
          itemId: s.id, name: str(m.name, 80), price, unitPrice, tierMinQty, count, lineTotal, discount,
          ...(itemNotes.has(s.id) ? { note: itemNotes.get(s.id) } : {}),
        });
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
        const q = await quoteDelivery(r, { toLat, toLng, at: scheduledFor || undefined }, tariffData);
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
      // Oddiy buyurtma — 5 daqiqa; oldindan — 2 soat yoki bajarilishdan 30 daqiqa oldin (restoran_preorder.js).
      const deadline = scheduledFor
        ? new Date(preorder.acceptDeadlineMs(at.getTime(), scheduledFor.getTime()))
        : new Date(at.getTime() + ACCEPT_TIMEOUT_MIN * 60 * 1000);
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
        items, itemsTotal, qtyDiscountTotal, deliveryFee,
        total: itemsTotal + deliveryFee,
        fulfillmentMode, deliveryMode, deliveryFeeSource, ...deliveryQuote,
        foodPaymentMethod, deliveryPaymentMethod,
        ...(restaurantPayment ? { restaurantPayment } : {}),
        avaFee,
        acceptDeadlineAt: tsOf(deadline),
        // Oldindan buyurtma (S4b): bajarilish vaqti; oddiy buyurtmada maydon YO'Q.
        ...(scheduledFor ? { scheduledFor: tsOf(scheduledFor), isPreorder: true } : {}),
        prepTimeMin: intOr(r.prepTimeMin, 20, 5, 180),
        courierId: null, deliveryRouteId: null,
        balanceApplied: 0, cashDue: 0, cashPaid: 0,
        createdAt: ts(),
      };
      const result = {
        ok: true, orderId: orderRef.id, itemsTotal, deliveryFee, total: payload.total, acceptDeadlineAtMs: deadline.getTime(),
        ...(scheduledFor ? { scheduledForMs: scheduledFor.getTime() } : {}),
      };
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
      const sum = new Intl.NumberFormat('uz-UZ').format(itemsTotal);
      await notifyMembers(restaurantId, scheduledFor
        ? { title: '📅 Oldindan buyurtma', body: `${sum} so'm · ${tashkentLabel(scheduledFor)} ga · qabul qiling`, orderId: orderRef.id }
        : { title: '🍽 Yangi buyurtma', body: `${sum} so'm · ${ACCEPT_TIMEOUT_MIN} daqiqada qabul qiling`, orderId: orderRef.id });
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
      const schedMs = preorder.scheduledMsOf(out.od);
      if (out.customerUid) {
        await notifyCustomer(canonicalUid(out.customerUid), schedMs != null
          ? { title: '✅ Oldindan buyurtma qabul qilindi', body: `${tashkentLabel(new Date(schedMs))} ga tayyor bo'ladi`, orderId }
          : { title: '✅ Buyurtma qabul qilindi', body: `Tayyorlanmoqda, ~${out.prepTimeMin} daqiqa`, orderId });
      }
      // Kuryer tayyorlanish vaqtida yo'lga chiqsin (Meituan modeli, §12.9). Oldindan buyurtmada — faqat
      // bajarilishdan 90 daqiqa oldin ochilgach (kunlar oldin chaqirilmasin); oynagacha — «tayyor» bosilganda.
      if (schedMs == null || preorder.courierWindowOpen(now().getTime(), schedMs)) {
        couriersNotified = (await notifyNearbyCouriers(orderId, out.od || {}, 'accepted')).notified;
      }
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
      t.delete(db.collection(COURIER_LIVE).doc(orderId)); // kuryer nuqtasi qolib ketmasin (S6, 40-qoida)
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
      // Oldindan buyurtma: «tayyor» (= kuryer chaqiruvi) faqat bajarilishdan 90 daqiqa oldin ochiladi.
      const schedMs = preorder.scheduledMsOf(od);
      if (schedMs != null && !preorder.courierWindowOpen(now().getTime(), schedMs)) {
        throw fail('failed-precondition', 'PREORDER_TOO_EARLY', { opensAtMs: schedMs - preorder.COURIER_WINDOW_MIN * 60 * 1000 });
      }
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
      // Oldindan buyurtma kuryer ro'yxatiga bajarilishdan 90 daqiqa oldin chiqadi (S4b).
      const schedMs = preorder.scheduledMsOf(od);
      if (schedMs != null && !preorder.courierWindowOpen(now().getTime(), schedMs)) continue;
      const buyout = od.foodPaymentMethod === 'cash_buyout';
      const foodAmount = foodAmountOf(od);
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
    const courierName = await courierDisplayName(courierId);
    const out = await withContention(orderRef, 'claim', () => db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      const assigned = canonicalUid(String(od.courierId || ''));
      if (assigned && assigned === courierId) return { ok: true, idempotent: true, routeId: od.deliveryRouteId };
      if (assigned) throw fail('failed-precondition', 'COURIER_ASSIGNMENT_CONFLICT');
      if (od.deliveryMode !== 'ava_courier') throw fail('failed-precondition', 'NOT_AVA_COURIER_ORDER');
      if (![RS.accepted, RS.ready].includes(od.restaurantStatus)) throw fail('failed-precondition', 'ORDER_NOT_CLAIMABLE', { from: od.restaurantStatus });
      const schedMs = preorder.scheduledMsOf(od);
      if (schedMs != null && !preorder.courierWindowOpen(now().getTime(), schedMs)) throw fail('failed-precondition', 'PREORDER_TOO_EARLY');
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
        const foodAmount = foodAmountOf(od);
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
      // `courierName` — mijoz va restoran egasi kimni kutishini bilishi uchun (S6); faqat buyurtma ishtirokchilari o'qiydi.
      t.update(orderRef, {
        courierId, deliveryRouteId: routeId, courierClaimedAt: ts(), updatedAt: ts(), ...(courierName ? { courierName } : {}),
        // Qaytarilgan/qo'yib yuborilgan buyurtmaga kuryer topildi — 30 daqiqalik qidiruv tugadi.
        ...(od.returnSearchUntil !== undefined ? { returnSearchUntil: admin.firestore.FieldValue.delete() } : {}),
      });
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
      const foodAmount = foodAmountOf(od);
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
   * Yakun tranzaksiyasi — YAGONA yadro (7-qoida): kuryerning `courierCompleteRestaurantDelivery`
   * chaqiruvi ham, mijozning tasdig'i (`customerConfirmHandover`, modul `restaurant`) ham shuni
   * ishlatadi.
   *   `gate: true` (kuryer chaqiruvi) va mijoz tasdig'i shu mijoz uchun YOQILGAN bo'lsa,
   *   'delivered' YAKUNLANMAYDI: faqat kutish belgisi yoziladi (holat va pul o'zgarmaydi).
   *   `confirmStep` — mijoz tasdig'i: yadro bajariladi, belgi o'chadi, tasdiq izi yoziladi.
   * Sozlama o'chiq bo'lsa yo'l AVVALGI kod bilan bir xil. Pul kalitlari o'zgarmagan
   * (`rest_complete_{id}`, `restDelivery_{id}`), shuning uchun qayta urinish ikki marta to'lamaydi.
   */
  async function completeInTx(t, {
    orderRef, idemRef, orderId, courierId, outcome, failReason, gate, confirmStep,
    // Kim yakunladi (hodisa uchun): 'courier' (standart) | 'customer' | 'restaurant' | 'admin'.
    actor, actorId,
  }) {
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
      // «Yetkazilmadi» (ega qarori 2026-10-31, HAMMA mijoz uchun): kuryer o'zi YAKUNLAY OLMAYDI.
      // Mijozdan tasdiq so'raladi; `failedTimeoutMin` ichida javob bo'lmasa qaror restoranga o'tadi
      // (`escalateRestaurantDeliveryFailed`). Holat va pul O'ZGARMAYDI.
      if (gate && to === RS.deliveryFailed && customerConfirm) {
        const m = od[CC_MARKER_FIELD];
        if (m && m.step === FAILED_STEP) {
          // Takroriy chaqiruv: birinchi so'rov (sababi va muddati) o'zgarmaydi.
          return { done: true, result: { ...customerConfirm.awaitingResponse(FAILED_STEP), escalateAtMs: msOf(m.escalateAt) }, requested: { od, created: false } };
        }
        const timeoutMin = await customerConfirm.getFailedTimeoutMin();
        const escalateAt = tsOf(new Date(now().getTime() + timeoutMin * 60 * 1000));
        const rq = customerConfirm.requestInTx(t, orderRef, od, {
          step: FAILED_STEP, courierId, extra: { failReason, escalateAt },
          patch: {
            [FAILED_ESCALATE_AT]: escalateAt,
            [FAILED_ESCALATED_AT]: admin.firestore.FieldValue.delete(),
            [FAILED_RESOLUTION]: admin.firestore.FieldValue.delete(),
          },
        });
        addEvent(t, orderRef, {
          from, to: from, actor: 'courier', actorId: courierId, reason: 'delivery_failed_requested',
          meta: { step: FAILED_STEP, failReason, timeoutMin, replacedStep: m && m.step ? String(m.step) : null },
        });
        return {
          done: true,
          result: { ...customerConfirm.awaitingResponse(FAILED_STEP), escalateAtMs: escalateAt.toMillis() },
          requested: { od, created: rq.created, step: FAILED_STEP, failReason },
        };
      }
      // Mijoz tasdig'i (D2/D7): yoqilgan bo'lsa kuryer yetkazishni YAKUNLAY OLMAYDI.
      if (gate && to === RS.delivered && customerConfirm && await customerConfirm.isGated('restaurant', customerUid)) {
        // «Yetkazilmadi» kutilayotgan bo'lsa (mijoz chiqib keldi) — u bekor bo'ladi, muddat o'chadi.
        const rq = customerConfirm.requestInTx(t, orderRef, od, { step: 'received', courierId, patch: failedPendingClear(od) });
        if (rq.created) {
          addEvent(t, orderRef, { from, to: from, actor: 'courier', actorId: courierId, reason: 'customer_confirm_requested', meta: { step: 'received' } });
        }
        return { done: true, result: customerConfirm.awaitingResponse('received'), requested: { od, created: rq.created } };
      }
      const clearMarker = { ...(customerConfirm ? customerConfirm.clearPatch(od) : {}), ...failedPendingClear(od) };
      const evActor = actor || (confirmStep ? 'customer' : 'courier');
      const evActorId = actorId || (confirmStep ? customerUid : courierId);
      const resolution = to === RS.deliveryFailed && evActor !== 'courier'
        ? { [FAILED_RESOLUTION]: { by: evActor, decision: 'failed', at: ts(), actorId: evActorId } }
        : {};
      const fee = Number(od.deliveryFee) || 0;
      let walletPrep = null;
      let refundPrep = null;
      let prevStrikes = 0;
      // Topshirish bo'lgan bo'lsa (A-3): yetkazish haqi kuryerlar orasida masofa ulushi bo'yicha.
      // Bo'laklar: `courierLegs` (qaytarilganlar — hissasiz) + oxirgi topshirish nuqtasi → mijoz.
      let shares = null;
      if (to === RS.delivered && Array.isArray(od.courierLegs) && od.courierLegs.length > 0) {
        const cLat = Number(od.lat);
        const cLng = Number(od.lng);
        const custPt = validLatLng(cLat, cLng) ? { lat: cLat, lng: cLng } : null;
        const legs = od.courierLegs.filter((l) => l && !l.returned)
          .map((l) => ({ courierId: canonicalUid(String(l.courierId || '')), meters: Number(l.meters) || 0 }));
        legs.push({ courierId, meters: legMeters(custodyStartPoint(od), custPt) });
        shares = computeCourierShares(fee, legs);
      }
      const split = shares && shares.filter((s) => s.amount > 0).length > 1 ? shares.filter((s) => s.amount > 0) : null;
      let splitPreps = null;
      if (to === RS.delivered && od.deliveryPaymentMethod === 'wallet' && fee > 0 && split) {
        splitPreps = await Promise.all(split.map((s) => settlementLedger.prepareBonusInTx(t, db, customerUid, {
          fundingAccount: settlementLedger.passengerCreditAccount(s.courierId),
          idempotencyKey: `restDeliveryShare_${orderId}_${s.courierId}`,
        })));
      } else if (to === RS.delivered && od.deliveryPaymentMethod === 'wallet' && fee > 0) {
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
      if (splitPreps) {
        // Bitta tranzaksiyada mijoz hisobidan bir nechta yozuv: `commitBonusInTx` mutlaq balans yozadi,
        // shuning uchun har keyingi yozuvga oldingisidan keyingi qoldiq beriladi (o'qish READ fazasida).
        const already = splitPreps.every((p) => p.jExists);
        const pending = split.reduce((sum, s, i) => sum + (splitPreps[i].jExists ? 0 : s.amount), 0);
        if (already) {
          walletPaid = fee;
        } else if (splitPreps[0].pcPrev >= pending) {
          let pc = splitPreps[0].pcPrev;
          const cRef = db.collection('users').doc(customerUid);
          split.forEach((s, i) => {
            const prep = splitPreps[i];
            if (prep.jExists) return;
            prep.pcPrev = pc;
            settlementLedger.commitBonusInTx(t, prep, {
              delta: -s.amount, kind: 'restaurant_delivery_fee', refType: 'order', refId: orderId,
              meta: { module: MODULE_ID, courierId: s.courierId.slice(-4), share: true, meters: s.meters },
              postedBy: customerUid, postedRole: 'client',
            });
            pc -= s.amount;
            const kRef = db.collection('users').doc(s.courierId);
            t.set(kRef, { bonusBalance: inc(s.amount), balanceUpdatedAt: ts() }, { merge: true });
            t.set(kRef.collection('wallet_ledger').doc(), { type: 'restaurant_delivery_credit', amount: s.amount, module: MODULE_ID, refType: 'order', refId: orderId, meta: { share: true }, createdAt: ts(), createdBy: 'server' });
          });
          t.set(cRef, { bonusBalance: inc(-pending), balanceUpdatedAt: ts() }, { merge: true });
          t.set(cRef.collection('wallet_ledger').doc(), { type: 'restaurant_delivery_debit', amount: -pending, module: MODULE_ID, refType: 'order', refId: orderId, meta: { split: split.length }, createdAt: ts(), createdBy: 'server' });
          walletPaid = fee;
        } else {
          deliveryPaymentMethod = 'cash';
          deliveryFeeFallback = 'insufficient_wallet';
        }
      }
      // Naqd (ega qarori 2026-10-31): oxirgi kuryer hamma naqdni oladi; oldingi kuryer(lar) ulushi OXIRGI
      // kuryerning AVA hamyonidan AVTOMATIK o'tkaziladi. Niyat shu tranzaksiyada yoziladi (yakun bilan
      // bir marta), o'tkazma esa `settleCashShare` (darhol) / `restaurantCourierSharePendingSweep` (qayta).
      const cashShares = to === RS.delivered && split && walletPaid !== fee
        ? split.filter((s) => s.courierId !== courierId && s.amount > 0) : [];
      const sharePendingIds = cashShares.map((s) => cashShareId(orderId, courierId, s.courierId));
      cashShares.forEach((s, i) => {
        t.set(db.collection(SHARE_PENDING).doc(sharePendingIds[i]), {
          orderId, fromCourierId: courierId, toCourierId: s.courierId, amount: s.amount, meters: s.meters,
          status: 'pending', attempts: 0, createdAt: ts(),
        });
      });
      const payoutSettlement = !shares ? null
        : !split ? 'single'
          : walletPaid === fee ? 'wallet_split' : 'cash_last_pays';
      const buyout = od.foodPaymentMethod === 'cash_buyout';
      const foodAmount = foodAmountOf(od);
      const cashCollected = to === RS.delivered
        ? (buyout ? foodAmount : 0) + (deliveryPaymentMethod === 'cash' ? fee : 0)
        : 0;
      let refund = { applied: false, amount: 0 };
      t.delete(db.collection(COURIER_LIVE).doc(orderId)); // yetkazish tugadi — kuryer nuqtasi o'chadi (S6, 40-qoida)
      if (to === RS.delivered) {
        t.update(orderRef, statusPatch(RS.delivered, {
          deliveredAt: ts(), completedAt: ts(), courierId, deliveryPaymentMethod, deliveryFeeFallback,
          deliveryFeeWalletPaid: walletPaid, cashCollected, cashPaid: cashCollected,
          ...(shares ? { payoutShares: shares, payoutSettlement, custodyPoint: admin.firestore.FieldValue.delete() } : {}),
          ...(buyout || od.paymentStatus === 'paid' ? { paymentStatus: 'paid' } : {}),
          ...clearMarker,
          ...(confirmStep ? customerConfirm.confirmedPatch(confirmStep, courierId) : {}),
        }));
        t.set(db.collection(CUSTOMER_STATS).doc(customerUid), { completedCount: inc(1), updatedAt: ts() }, { merge: true });
      } else {
        refund = commitFeeInTx(t, refundPrep, { orderId, actorId: courierId });
        const strike = ['customer_absent', 'customer_refused'].includes(failReason);
        t.update(orderRef, statusPatch(RS.deliveryFailed, {
          failedAt: ts(), courierId, failReason, 'avaFee.refunded': refund.applied, 'avaFee.refundedAt': refund.applied ? ts() : null,
          rejectReason: `delivery_failed:${failReason}`,
          ...clearMarker,
          ...resolution,
          ...(confirmStep ? customerConfirm.confirmedPatch(confirmStep, courierId) : {}),
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
      const result = {
        ok: true, orderId, outcome, deliveryFee: fee, walletPaid, cashCollected, refundAmount: refund.amount, deliveryPaymentMethod,
        ...(shares ? { payoutShares: shares.map((s) => ({ courierTail: s.courierId.slice(-4), meters: s.meters, amount: s.amount })), payoutSettlement } : {}),
      };
      t.set(idemRef, { type: 'courierCompleteRestaurantDelivery', result, createdAt: ts() });
      addEvent(t, orderRef, confirmStep
        ? { from, to, actor: 'customer', actorId: customerUid, reason: 'customer_confirmed', meta: { walletPaid, cashCollected, refundAmount: refund.amount, step: confirmStep, courierId, ...(to === RS.deliveryFailed ? { failReason } : {}) } }
        : evActor !== 'courier'
          ? { from, to, actor: evActor, actorId: evActorId, reason: `delivery_failed_decided:${failReason}`, meta: { refundAmount: refund.amount, courierId, failReason } }
          : { from, to, actor: 'courier', actorId: courierId, reason: to === RS.deliveryFailed ? failReason : '', meta: { walletPaid, cashCollected, refundAmount: refund.amount } });
      return { done: false, result, customerUid, restaurantId: od.restaurantId, courierId, sharePendingIds };
  }

  /**
   * Naqd ulush o'tkazmasi: oxirgi kuryer hamyoni → oldingi kuryer hamyoni (mavjud `settlementLedger.postEntry`,
   * passenger_credit ↔ passenger_credit, butun so'm). Idempotentlik kaliti (jurnal hujjati id'si)
   * `restCourierShare_{orderId}_{from}_{to}` — qayta urinish ikki marta o'tkazmaydi; niyat hujjati
   * AYNI tranzaksiyada o'chadi. Hamyon yetmasa yakun TO'XTAMAYDI: niyat `insufficient_balance` bo'lib
   * qoladi va jadval har 5 daqiqada qayta uradi (`courierCashPendingSweep` naqshi, R1).
   * @returns {'posted'|'already'|'insufficient'|'failed'|'missing'}
   */
  async function settleCashShare(pendingId) {
    const pRef = db.collection(SHARE_PENDING).doc(pendingId);
    const snap = await pRef.get();
    if (!snap.exists) return 'missing';
    const p = snap.data() || {};
    const from = canonicalUid(String(p.fromCourierId || ''));
    const toC = canonicalUid(String(p.toCourierId || ''));
    const amount = Number(p.amount);
    if (!from || !toC || from === toC || !Number.isInteger(amount) || amount <= 0) {
      await pRef.update({ status: 'invalid', updatedAt: ts() });
      return 'failed';
    }
    const fromAcc = settlementLedger.passengerCreditAccount(from);
    try {
      const r = await settlementLedger.postEntry(db, {
        idempotencyKey: `restCourierShare_${cashShareId(String(p.orderId || ''), from, toC)}`,
        kind: 'restaurant_courier_share',
        refType: 'order',
        refId: String(p.orderId || ''),
        postedBy: 'system',
        postedRole: 'system',
        legs: [{ account: fromAcc, dr: amount }, { account: settlementLedger.passengerCreditAccount(toC), cr: amount }],
      }, {
        walletLedgerType: 'restaurant_courier_share',
        meta: { module: MODULE_ID, meters: Number(p.meters) || 0, fromTail: from.slice(-4), toTail: toC.slice(-4) },
        assert: ({ accounts }) => {
          const s = accounts.get(fromAcc);
          if (s && s.next < 0) {
            const e = new Error('COURIER_SHARE_INSUFFICIENT');
            e.insufficient = true;
            e.balance = s.prev;
            throw e;
          }
        },
        onCommit: (tx) => { tx.delete(pRef); },
      });
      if (r.idempotent) await pRef.delete();
      log('courier_share', { orderId: p.orderId, result: r.idempotent ? 'already' : 'posted', amount });
      return r.idempotent ? 'already' : 'posted';
    } catch (e) {
      const insufficient = !!(e && e.insufficient);
      try {
        await pRef.update({
          status: insufficient ? 'insufficient_balance' : 'error', attempts: inc(1), lastAttemptAt: ts(),
          lastError: insufficient ? 'COURIER_SHARE_INSUFFICIENT' : String((e && e.message) || e).slice(0, 160),
        });
      } catch (_) { /* niyat qoladi — jadval qayta uradi */ }
      log('courier_share', {
        orderId: p.orderId, result: insufficient ? 'insufficient' : 'failed',
        errorCode: insufficient ? 'COURIER_SHARE_INSUFFICIENT' : 'COURIER_SHARE_FAILED', amount,
      });
      return insufficient ? 'insufficient' : 'failed';
    }
  }

  async function settleCashShares(ids) {
    for (const id of ids || []) await settleCashShare(id);
  }

  /** Jadval: o'tkazilmagan naqd ulushlar (hamyon yetmagan / xato) — har 5 daqiqa qayta. */
  async function sweepCashShares() {
    const snap = await db.collection(SHARE_PENDING).orderBy('createdAt').limit(200).get();
    const out = { scanned: snap.size, posted: 0, insufficient: 0, failed: 0 };
    for (const d of snap.docs) {
      const r = await settleCashShare(d.id);
      if (r === 'posted' || r === 'already') out.posted += 1;
      else if (r === 'insufficient') out.insufficient += 1;
      else out.failed += 1;
    }
    if (snap.size) log('courier_share_sweep', out);
    return out;
  }

  exportsObj.restaurantCourierSharePendingSweep = functions.pubsub
    .schedule('every 5 minutes')
    .timeZone('Asia/Tashkent')
    .onRun(async () => sweepCashShares());

  /**
   * Yakun: `delivered` (yetkazish puli naqd yoki mijoz hamyoni → kuryer hamyoni)
   * yoki `delivery_failed` (2 % restoranga qaytadi, mijozga strike).
   * Idempotent: `wallet_idempotency/rest_complete_{orderId}`.
   * Mijoz tasdig'i yoqilgan bo'lsa 'delivered' kuryer chaqiruvida yakunlanmaydi:
   * `{ ok, awaitingCustomer: true, step: 'received' }` qaytadi (yadro: `completeInTx`).
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
    const out = await db.runTransaction((t) => completeInTx(t, {
      orderRef, idemRef, orderId, courierId, outcome, failReason, gate: true,
    }));
    if (out.requested) {
      const step = out.requested.step || 'received';
      await customerConfirm.afterRequest('restaurant', orderId, step, out.requested.od,
        step === FAILED_STEP ? { failReason: out.requested.failReason } : {}, out.requested.created);
    }
    if (out.done) return out.result;
    log('complete', { orderId, restaurantId: out.restaurantId, userId: courierId, result: outcome, walletPaid: out.result.walletPaid, durationMs: Date.now() - t0 });
    if (outcome === 'delivered') {
      await settleCashShares(out.sharePendingIds);
      await notifyCustomer(out.customerUid, { title: '✅ Buyurtma yetkazildi', body: 'Yoqimli ishtaha!', orderId });
    } else {
      await notifyMembers(String(out.restaurantId), { title: 'Yetkazib bo\'lmadi', body: 'Kuryer buyurtmani yetkaza olmadi', orderId });
    }
    return out.result;
  });

  // Mijoz tasdig'i yadrosi (D2/D7): `customerConfirmHandover({module:'restaurant', step:'received'})`
  // kuryer chaqiruvi bilan AYNAN bir xil `completeInTx` ni ishlatadi (saqlangan courierId bilan).
  if (customerConfirm) {
    customerConfirm.registerHandler('restaurant', {
      collection: ORDERS,
      phoneField: 'userPhone',
      customerPhoneOf: (od) => od.userPhone,
      statusOf: (od) => String(od.restaurantStatus || ''),
      describe: (od, marker) => {
        if (![RS.picked, RS.arrived].includes(od.restaurantStatus)) return null;
        if (marker.step === 'received') return { key: 'confirm_restaurant_received', params: {} };
        if (marker.step === FAILED_STEP) {
          const reason = FAIL_REASONS.includes(marker.failReason) ? marker.failReason : 'other';
          return {
            key: 'confirm_restaurant_delivery_failed',
            params: {},
            details: { failReason: reason, escalateAtMs: msOf(marker.escalateAt) },
          };
        }
        return null;
      },
      confirm: async (t, { ref, id, od, marker, step }) => {
        const orderId = id;
        const idemRef = db.collection(IDEMPOTENCY).doc(`rest_complete_${orderId}`);
        const courierId = canonicalUid(String(marker.courierId || ''));
        if (step === FAILED_STEP) {
          // Mijoz «olmadim»ni tasdiqladi — avvalgi yakun (2 % qaytadi, strike sababga qarab).
          const failReason = FAIL_REASONS.includes(marker.failReason) ? marker.failReason : 'other';
          const out = await completeInTx(t, {
            orderRef: ref, idemRef, orderId, courierId,
            outcome: 'failed', failReason, gate: false, confirmStep: FAILED_STEP,
          });
          if (out.done) {
            t.update(ref, { ...customerConfirm.clearPatch(od), ...failedPendingClear(od), ...customerConfirm.confirmedPatch(FAILED_STEP, marker.courierId) });
          }
          return {
            status: RS.deliveryFailed,
            after: out.done ? null : () => afterFailedFinal(orderId, out, 'customer'),
          };
        }
        const out = await completeInTx(t, {
          orderRef: ref, idemRef, orderId, courierId,
          outcome: 'delivered', failReason: 'other', gate: false, confirmStep: 'received',
        });
        if (out.done) {
          // Pul allaqachon yopilgan (idempotentlik hujjati bor), belgi esa qolib ketgan: tozalaymiz.
          t.update(ref, { ...customerConfirm.clearPatch(od), ...customerConfirm.confirmedPatch('received', marker.courierId) });
        }
        const ids = out.done ? [] : (out.sharePendingIds || []);
        return { status: RS.delivered, ...(ids.length ? { after: () => settleCashShares(ids) } : {}) };
      },
      // Mijoz «Олмоқчиман»: kuryer «yetkazilmadi» degan, mijoz esa olmoqchi — yetkazish davom etadi.
      reject: async (t, { ref, id, od, marker, step, customerId }) => {
        if (step !== FAILED_STEP) throw fail('failed-precondition', 'NOT_REJECTABLE');
        if (![RS.picked, RS.arrived].includes(od.restaurantStatus)) {
          throw fail('failed-precondition', 'ORDER_INVALID_TRANSITION', { from: od.restaurantStatus });
        }
        continueInTx(t, ref, od, { by: 'customer', actorId: customerId, marker });
        return {
          status: String(od.restaurantStatus || ''),
          after: () => afterContinue(id, od, marker, 'customer'),
        };
      },
    });
  }

  /**
   * «Davom etsin» (mijoz rad etdi yoki restoran/admin «yetkazilsin» dedi) — WRITE fazasi.
   * Holat o'zgarmaydi (picked/arrived), belgi va muddat o'chadi, qaror joriy holatga va hodisaga yoziladi.
   */
  function continueInTx(t, ref, od, { by, actorId, marker }) {
    t.update(ref, {
      ...customerConfirm.clearPatch(od),
      ...failedPendingClear(od),
      ...(by === 'customer' ? { [`${CC_REJECTED_FIELD}.${FAILED_STEP}`]: { at: ts(), courierId: String(marker.courierId || '') } } : {}),
      [FAILED_RESOLUTION]: { by, decision: 'continue', at: ts(), actorId: actorId || null },
      updatedAt: ts(),
    });
    addEvent(t, ref, {
      from: od.restaurantStatus, to: od.restaurantStatus, actor: by, actorId,
      reason: 'delivery_failed_rejected',
      meta: { courierId: String(marker.courierId || ''), failReason: String(marker.failReason || '') },
    });
  }

  /** Xabar: 3 tilda, har qabul qiluvchining `appLang` iga qarab. Xato asosiy oqimni to'xtatmaydi. */
  async function notifyI18n(userId, key, params, extra) {
    try {
      if (!userId) return;
      const lang = await i18n.langOfPhone(db, userId);
      const m = i18n.render(key, lang, params || {});
      await notifyUserInApp({
        userId: canonicalUid(String(userId)), title: m.title, body: m.body, category: 'order', source: 'restaurant_order',
        extraNews: { orderId: String(extra.orderId || ''), orderType: 'restaurant' },
        dataType: 'restaurant_order', screen: extra.screen || 'orders',
        extraData: { orderId: extra.orderId, ...(extra.data || {}) },
        ...(extra.channelId ? { channelId: extra.channelId } : {}),
      });
    } catch (e) {
      console.error(JSON.stringify({ module: MODULE_ID, action: 'notifyI18n', key, result: 'failed', errorCode: 'NOTIFY_FAILED', message: String((e && e.message) || e).slice(0, 160) }));
    }
  }

  async function notifyMembersI18n(restaurantId, key, params, orderId) {
    try {
      const ms = await db.collection(RESTAURANTS).doc(String(restaurantId || '')).collection(MEMBERS).limit(10).get();
      await Promise.all(ms.docs.map((m) => notifyI18n(m.id, key, params, {
        orderId, screen: 'restaurant_orders', data: { restaurantId, ring: '1' }, channelId: 'courier_arrival_alarm',
      })));
    } catch (e) {
      console.error('restaurant notifyMembersI18n:', e.message || e);
    }
  }

  async function afterFailedFinal(orderId, out, by) {
    log('delivery_failed_final', { orderId, restaurantId: out.restaurantId, result: 'delivery_failed', by, refundAmount: out.result.refundAmount });
    await notifyMembersI18n(out.restaurantId, 'restaurant_delivery_failed_final', {}, orderId);
    if (out.courierId) await notifyI18n(out.courierId, 'courier_delivery_failed_final', {}, { orderId });
    if (by !== 'customer' && out.customerUid) await notifyI18n(out.customerUid, 'customer_delivery_failed_final', {}, { orderId });
  }

  async function afterContinue(orderId, od, marker, by) {
    log('delivery_failed_continue', { orderId, restaurantId: od.restaurantId, result: 'continue', by });
    if (marker.courierId) await notifyI18n(marker.courierId, 'courier_delivery_failed_continue', {}, { orderId });
    if (by !== 'customer' && od.userPhone) await notifyI18n(od.userPhone, 'customer_delivery_failed_continue', {}, { orderId });
  }

  /**
   * Mijoz `failedTimeoutMin` ichida javob bermadi → qaror restoranga (ega qarori A-1, 2026-10-31).
   * `decision`: 'failed' — yetkazilmadi (avvalgi yakun), 'continue' — kuryer yetkazishni davom ettiradi.
   * Ruxsat: restoran a'zosi (shu buyurtmaning restorani) yoki admin/superadmin (zaxira, audit bilan — PROPOSED).
   * Muddat o'tmaguncha — `DECISION_NOT_YET` (mijoz navbatida). Birinchi qaror yutadi (tranzaksiya).
   */
  exportsObj.restaurantResolveDeliveryFailed = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    const orderId = str(data && data.orderId, 64);
    const decision = str(data && data.decision, 16);
    if (!orderId || orderId.includes('/') || !FAILED_DECISIONS.includes(decision)) {
      throw fail('invalid-argument', 'RESOLVE_ARGS_INVALID');
    }
    let isAdmin = false;
    try {
      await requireCallerRoles(context, ['admin', 'superadmin'], 'admin');
      isAdmin = true;
    } catch (_) { isAdmin = false; }
    const orderRef = db.collection(ORDERS).doc(orderId);
    const idemRef = db.collection(IDEMPOTENCY).doc(`rest_complete_${orderId}`);
    const out = await withContention(orderRef, 'resolve_failed', () => db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      const rRef = db.collection(RESTAURANTS).doc(String(od.restaurantId || ''));
      const mSnap = await t.get(rRef.collection(MEMBERS).doc(uid));
      const by = mSnap.exists ? 'restaurant' : (isAdmin ? 'admin' : null);
      if (!by) throw fail('permission-denied', 'NOT_RESTAURANT_MEMBER');
      const res = od[FAILED_RESOLUTION];
      const marker = od[CC_MARKER_FIELD];
      if (!marker || marker.step !== FAILED_STEP) {
        // Takror: shu qaror allaqachon qabul qilingan.
        if (decision === 'failed' && od.restaurantStatus === RS.deliveryFailed) return { idempotent: true, status: od.restaurantStatus };
        if (decision === 'continue' && res && res.decision === 'continue' && [RS.picked, RS.arrived].includes(od.restaurantStatus)) {
          return { idempotent: true, status: od.restaurantStatus };
        }
        throw fail('failed-precondition', 'NOT_AWAITING_DECISION', { status: od.restaurantStatus });
      }
      const escalateMs = msOf(marker.escalateAt);
      const escalated = od[FAILED_ESCALATED_AT] !== undefined && od[FAILED_ESCALATED_AT] !== null;
      if (!escalated && (escalateMs === null || escalateMs > now().getTime())) {
        throw fail('failed-precondition', 'DECISION_NOT_YET', { escalateAtMs: escalateMs });
      }
      // Admin qarori audit jurnaliga (41-qoida). Yozuv — barcha o'qishlardan KEYIN (tranzaksiya qoidasi).
      const audit = () => {
        if (by !== 'admin') return;
        t.set(db.collection(ADMIN_AUDIT).doc(), {
          kind: 'restaurant_delivery_failed_decision', actor: uid, target: `orders/${orderId}`,
          from: od.restaurantStatus, to: decision === 'failed' ? RS.deliveryFailed : od.restaurantStatus,
          reason: decision, detail: { failReason: String(marker.failReason || ''), restaurantId: String(od.restaurantId || '') }, at: ts(),
        });
      };
      if (decision === 'continue') {
        if (![RS.picked, RS.arrived].includes(od.restaurantStatus)) {
          throw fail('failed-precondition', 'ORDER_INVALID_TRANSITION', { from: od.restaurantStatus });
        }
        continueInTx(t, orderRef, od, { by, actorId: uid, marker });
        audit();
        return { status: od.restaurantStatus, continued: { od, marker, by } };
      }
      const failReason = FAIL_REASONS.includes(marker.failReason) ? marker.failReason : 'other';
      const r = await completeInTx(t, {
        orderRef, idemRef, orderId, courierId: canonicalUid(String(marker.courierId || '')),
        outcome: 'failed', failReason, gate: false, actor: by, actorId: uid,
      });
      if (r.done) return { idempotent: true, status: RS.deliveryFailed };
      audit();
      return { status: RS.deliveryFailed, final: { ...r, by } };
    }), (od) => {
      if (decision === 'failed' && od.restaurantStatus === RS.deliveryFailed) return { idempotent: true, status: od.restaurantStatus };
      return null;
    });
    if (out.final) await afterFailedFinal(orderId, out.final, out.final.by);
    if (out.continued) await afterContinue(orderId, out.continued.od, out.continued.marker, out.continued.by);
    log('resolve_failed', { orderId, userId: uid.slice(-4), result: out.idempotent ? 'idempotent' : decision, durationMs: Date.now() - t0 });
    return { ok: true, status: out.status, decision, ...(out.idempotent ? { idempotent: true } : {}) };
  });

  /**
   * Jadval (har daqiqa): mijoz javob bermagan «yetkazilmadi» so'rovlari muddati o'tdi →
   * `deliveryFailedEscalatedAt` qo'yiladi, restoran a'zolariga 3 tilda xabar. Bitta maydon bo'yicha
   * diapazon so'rovi — kompozit indeks KERAK EMAS. Takror ishga tushsa ikkinchi marta yozmaydi.
   */
  async function escalateOne(orderRef, at) {
    return db.runTransaction(async (t) => {
      const s = await t.get(orderRef);
      if (!s.exists) return null;
      const od = s.data() || {};
      const dl = msOf(od[FAILED_ESCALATE_AT]);
      if (dl === null) return null;
      const marker = od[CC_MARKER_FIELD];
      const pending = od.type === 'restaurant' && marker && marker.step === FAILED_STEP
        && [RS.picked, RS.arrived].includes(od.restaurantStatus);
      if (!pending) {
        // Eskirgan muddat (buyurtma boshqa yo'l bilan yakunlangan) — faqat maydon o'chadi.
        t.update(orderRef, { [FAILED_ESCALATE_AT]: admin.firestore.FieldValue.delete() });
        return { stale: true };
      }
      if (dl > at.getTime()) return null;
      t.update(orderRef, { [FAILED_ESCALATE_AT]: admin.firestore.FieldValue.delete(), [FAILED_ESCALATED_AT]: ts() });
      addEvent(t, orderRef, {
        from: od.restaurantStatus, to: od.restaurantStatus, actor: 'system', reason: 'delivery_failed_escalated',
        meta: { failReason: String(marker.failReason || ''), courierId: String(marker.courierId || '') },
      });
      return { orderId: orderRef.id, restaurantId: od.restaurantId, customerUid: od.userPhone };
    });
  }

  async function escalateDeliveryFailed() {
    const at = now();
    const snap = await db.collection(ORDERS)
      .where(FAILED_ESCALATE_AT, '<=', tsOf(at))
      .limit(ESCALATE_BATCH)
      .get();
    let escalated = 0;
    let stale = 0;
    for (const doc of snap.docs) {
      try {
        const r = await escalateOne(doc.ref, at);
        if (!r) continue;
        if (r.stale) { stale += 1; continue; }
        escalated += 1;
        log('delivery_failed_escalate', { orderId: r.orderId, restaurantId: r.restaurantId, result: 'escalated' });
        await notifyMembersI18n(r.restaurantId, 'restaurant_delivery_failed_decide', {}, r.orderId);
      } catch (e) {
        console.error(JSON.stringify({ module: MODULE_ID, action: 'delivery_failed_escalate', orderId: doc.id, result: 'failed', errorCode: 'ESCALATE_FAILED', message: String((e && e.message) || e).slice(0, 160) }));
      }
    }
    return { scanned: snap.size, escalated, stale };
  }

  exportsObj.escalateRestaurantDeliveryFailed = functions.pubsub
    .schedule('every 1 minutes')
    .timeZone('Asia/Tashkent')
    .onRun(async () => escalateDeliveryFailed());

  // ═══════════════════════════════════════════════════════════════════════
  // TOPSHIRISH: boshqa kuryerga / restoranga (ega qarorlari 2026-10-31)
  // ═══════════════════════════════════════════════════════════════════════

  const delField = () => admin.firestore.FieldValue.delete();
  const handoverCode = () => String(crypto.randomInt(0, 1000000)).padStart(6, '0');

  function optLatLng(data) {
    const lat = Number(data && data.lat);
    const lng = Number(data && data.lng);
    return validLatLng(lat, lng) ? { lat, lng } : null;
  }

  /** Buyurtma bo'yicha joriy jismoniy nuqta: oxirgi topshirish nuqtasi, bo'lmasa restoran. */
  function custodyStartPoint(od) {
    const p = od.custodyPoint;
    if (p && validLatLng(Number(p.lat), Number(p.lng))) return { lat: Number(p.lat), lng: Number(p.lng) };
    const rLat = Number(od.restaurantLat);
    const rLng = Number(od.restaurantLng);
    return validLatLng(rLat, rLng) ? { lat: rLat, lng: rLng } : null;
  }

  function legMeters(from, to) {
    if (!from || !to) return 0;
    return Math.round(tariff.haversineMeters(from.lat, from.lng, to.lat, to.lng));
  }

  function custodyEventDoc({ orderId, od, kind, from, to, location, proof, actorId, handoverId, meta }) {
    return {
      orderType: 'restaurant',
      orderId,
      restaurantId: String(od.restaurantId || ''),
      shipmentId: null,
      legId: null,
      /** Qoida `get()`siz: mijoz o'z buyurtmasi tarixini o'qiy oladi (`isOwner(ownerId)`). */
      ownerId: canonicalUid(String(od.userPhone || '')),
      kind,
      from,
      to,
      timestamp: ts(),
      location: location || null,
      proof: proof || {},
      createdBy: actorId,
      idempotencyKey: `rest_${orderId}_${handoverId}`,
      handoverId,
      meta: meta || {},
      deliversShipment: false,
    };
  }

  /**
   * Kuryer topshirishni boshlaydi.
   *   accepted/ready (hali olinmagan): DARHOL qo'yib yuboradi — kuryer, marshrut o'chadi, 30 daqiqa qidiruv.
   *   picked/arrived: kod chiqadi (TTL 15 daq). `target: 'courier'` — kod boshqa kuryerga aytiladi;
   *   `target: 'seller'` — kod restoranga aytiladi. Takroriy chaqiruv o'sha kodni qaytaradi.
   */
  exportsObj.courierStartRestaurantHandover = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    const courierId = await courierAuthOf().resolve(uid, COURIER_AUTH_MODES.finish);
    const orderId = str(data && data.orderId, 64);
    const target = str(data && data.target, 16);
    if (!orderId || orderId.includes('/') || !HANDOVER_TARGETS.includes(target)) throw fail('invalid-argument', 'HANDOVER_ARGS_INVALID');
    const loc = optLatLng(data);
    await courierAuthOf().assertOrderOnActiveRoute(courierId, orderId);
    const orderRef = db.collection(ORDERS).doc(orderId);
    const secretRef = orderRef.collection(PRIVATE).doc('secrets');
    const out = await withContention(orderRef, 'handover_start', () => db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      courierAuthOf().assertOrderActionable(od, courierId, 'courierStartRestaurantHandover', orderId);
      const st = od.restaurantStatus;
      // ── Olishdan oldin: qo'yib yuborish (jismoniy narsa yo'q, kod kerak emas) ──
      if ([RS.accepted, RS.ready].includes(st)) {
        const routeRef = od.deliveryRouteId ? db.collection(ROUTES).doc(String(od.deliveryRouteId)) : null;
        const routeSnap = routeRef ? await t.get(routeRef) : null;
        const until = tsOf(new Date(now().getTime() + RETURN_SEARCH_MIN * 60 * 1000));
        t.update(orderRef, {
          courierId: null, courierName: delField(), deliveryRouteId: delField(), courierClaimedAt: delField(),
          returnSearchUntil: until, releasedAt: ts(), releasedBy: courierId, updatedAt: ts(),
          handoverCount: inc(1),
        });
        detachFromRouteInTx(t, routeRef, routeSnap, orderId, 'courier_released');
        addEvent(t, orderRef, { from: st, to: st, actor: 'courier', actorId: courierId, reason: 'courier_released', meta: { searchMin: RETURN_SEARCH_MIN } });
        return { released: true, od: { ...od, courierId: null }, untilMs: until.toMillis() };
      }
      if (![RS.picked, RS.arrived].includes(st)) {
        throw fail('failed-precondition', 'HANDOVER_NOT_ALLOWED', { from: st });
      }
      const m = od[CC_MARKER_FIELD];
      if (m && m.step === FAILED_STEP) throw fail('failed-precondition', 'HANDOVER_BLOCKED_FAILED_PENDING');
      // Naqd vykup: kuryer A restoranga o'z pulini bergan; B ga o'tkazishda kuryerlararo hisob — ega qarori yo'q.
      if (target === 'courier' && od.foodPaymentMethod === 'cash_buyout') {
        throw fail('failed-precondition', 'HANDOVER_BUYOUT_UNSUPPORTED');
      }
      const ho = od.handover;
      const nowMs = now().getTime();
      const sec = await t.get(secretRef);
      const sd = sec.exists ? (sec.data() || {}) : {};
      if (ho && ho.status === 'pending' && ho.fromCourierId === courierId && ho.target === target
          && msOf(ho.expiresAt) > nowMs && sd.handoverCode) {
        return { idempotent: true, handoverId: ho.id, code: sd.handoverCode, expiresAtMs: msOf(ho.expiresAt) };
      }
      // Kuryerga: kod butun tizimda yagona (B buyurtma raqamini bilmaydi) — `courier_handover_codes/{code}`.
      let code = handoverCode();
      let codeRef = null;
      if (target === 'courier') {
        for (let i = 0; i < 5; i += 1) {
          codeRef = db.collection(HANDOVER_CODES).doc(code);
          const cs = await t.get(codeRef);
          if (!cs.exists || (msOf((cs.data() || {}).expiresAt) || 0) <= nowMs) break;
          code = handoverCode();
          codeRef = null;
        }
        if (!codeRef) throw fail('aborted', 'HANDOVER_CODE_BUSY');
      }
      const oldCodeRef = ho && ho.status === 'pending' && ho.target === 'courier' && sd.handoverCode
        ? db.collection(HANDOVER_CODES).doc(String(sd.handoverCode)) : null;
      // WRITE fazasi.
      const handoverId = `h${nowMs.toString(36)}${crypto.randomInt(0, 1296).toString(36)}`;
      const expiresAt = tsOf(new Date(nowMs + HANDOVER_TTL_MIN * 60 * 1000));
      if (oldCodeRef && (!codeRef || oldCodeRef.path !== codeRef.path)) t.delete(oldCodeRef);
      if (codeRef) t.set(codeRef, { orderId, handoverId, fromCourierId: courierId, expiresAt, createdAt: ts() });
      t.set(secretRef, { handoverCode: code, handoverAttempts: 0, handoverId }, { merge: true });
      t.update(orderRef, {
        handover: {
          status: 'pending', id: handoverId, target, fromCourierId: courierId, createdAt: ts(), expiresAt,
          ...(loc ? { fromLat: loc.lat, fromLng: loc.lng } : {}),
        },
        updatedAt: ts(),
      });
      addEvent(t, orderRef, { from: st, to: st, actor: 'courier', actorId: courierId, reason: 'handover_started', meta: { target, handoverId } });
      return { handoverId, code, expiresAtMs: expiresAt.toMillis() };
    }), () => null);
    if (out.released) {
      log('handover_release', { orderId, userId: courierId.slice(-4), result: 'released', durationMs: Date.now() - t0 });
      await notifyNearbyCouriers(orderId, out.od, 'ready');
      return { ok: true, released: true, searchUntilMs: out.untilMs };
    }
    log('handover_start', { orderId, userId: courierId.slice(-4), result: out.idempotent ? 'idempotent' : 'ok', target, durationMs: Date.now() - t0 });
    return { ok: true, handoverId: out.handoverId, code: out.code, expiresAtMs: out.expiresAtMs, target, ...(out.idempotent ? { idempotent: true } : {}) };
  });

  /** Kuryer boshlagan topshirishni bekor qiladi (kod o'chadi). Takror — idempotent. */
  exportsObj.courierCancelRestaurantHandover = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const courierId = await courierAuthOf().resolve(uid, COURIER_AUTH_MODES.finish);
    const orderId = str(data && data.orderId, 64);
    const orderRef = db.collection(ORDERS).doc(orderId);
    const secretRef = orderRef.collection(PRIVATE).doc('secrets');
    await db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      courierAuthOf().assertOrderActionable(od, courierId, 'courierCancelRestaurantHandover', orderId);
      const ho = od.handover;
      if (!ho || ho.status !== 'pending') return;
      const sec = await t.get(secretRef);
      const sd = sec.exists ? (sec.data() || {}) : {};
      if (ho.target === 'courier' && sd.handoverCode) t.delete(db.collection(HANDOVER_CODES).doc(String(sd.handoverCode)));
      t.set(secretRef, { handoverCode: delField(), handoverAttempts: delField(), handoverId: delField() }, { merge: true });
      t.update(orderRef, { handover: delField(), updatedAt: ts() });
      addEvent(t, orderRef, { from: od.restaurantStatus, to: od.restaurantStatus, actor: 'courier', actorId: courierId, reason: 'handover_cancelled', meta: { handoverId: ho.id } });
    });
    return { ok: true };
  });

  /** Kod bo'yicha urinishlar chegarasi (kuryer boshiga, oyna bilan) — kod taxmin qilinmasin. */
  async function consumeCallerAttempt(uid) {
    const ref = db.collection(HANDOVER_ATTEMPTS).doc(uid);
    return db.runTransaction(async (t) => {
      const s = await t.get(ref);
      const d = s.exists ? (s.data() || {}) : {};
      const nowMs = now().getTime();
      const windowStart = msOf(d.windowStart) || 0;
      const fresh = nowMs - windowStart > HANDOVER_CALLER_WINDOW_MIN * 60 * 1000;
      const count = fresh ? 0 : (Number(d.count) || 0);
      if (count >= HANDOVER_CALLER_ATTEMPTS) return false;
      t.set(ref, { count: count + 1, windowStart: fresh ? tsOf(new Date(nowMs)) : d.windowStart, updatedAt: ts() });
      return true;
    });
  }

  /**
   * Kuryer B kuryer A dan buyurtmani oladi: A ning ekranidagi 6 xonali kod + B ning GPS'i (custody joyi, 15-qoida).
   * Bitta g'olib (tranzaksiya). Holat `picked` (B mijozga yo'lda); A marshrutidan olinadi, B marshrutiga qo'shiladi;
   * `courierLegs` ga A ning bo'lagi (oxirgi nuqta → topshirish nuqtasi) yoziladi; `custody_events` ga A → B.
   */
  exportsObj.courierAcceptRestaurantHandover = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    const courierId = await courierAuthOf().resolve(uid, COURIER_AUTH_MODES.new);
    const code = str(data && data.code, 8);
    const loc = optLatLng(data);
    if (!/^\d{6}$/.test(code)) throw fail('invalid-argument', 'HANDOVER_CODE_INVALID');
    if (!loc) throw fail('invalid-argument', 'HANDOVER_LOCATION_REQUIRED');
    if (!(await consumeCallerAttempt(courierId))) throw fail('resource-exhausted', 'HANDOVER_TOO_MANY_ATTEMPTS');
    const codeRef = db.collection(HANDOVER_CODES).doc(code);
    const pre = await codeRef.get();
    const cd = pre.exists ? (pre.data() || {}) : null;
    if (!cd || (msOf(cd.expiresAt) || 0) <= now().getTime()) throw fail('failed-precondition', 'HANDOVER_CODE_MISMATCH');
    const orderId = String(cd.orderId || '');
    const orderRef = db.collection(ORDERS).doc(orderId);
    const secretRef = orderRef.collection(PRIVATE).doc('secrets');
    const courierName = await courierDisplayName(courierId);
    const out = await withContention(orderRef, 'handover_accept', () => db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      const ho = od.handover;
      const [cs, sec, memberSnap, routeQ] = await Promise.all([
        t.get(codeRef), t.get(secretRef),
        t.get(db.collection(RESTAURANTS).doc(String(od.restaurantId || '')).collection(MEMBERS).doc(courierId)),
        t.get(db.collection(ROUTES).where('courierId', '==', courierId).where('status', 'in', ['active', 'ready']).limit(1)),
      ]);
      const sd = sec.exists ? (sec.data() || {}) : {};
      const cdx = cs.exists ? (cs.data() || {}) : null;
      if (!ho || ho.status !== 'pending' || ho.target !== 'courier' || !cdx || cdx.handoverId !== ho.id
          || sd.handoverCode !== code || (msOf(ho.expiresAt) || 0) <= now().getTime()) {
        // Takror: shu kuryer allaqachon olgan.
        if (canonicalUid(String(od.courierId || '')) === courierId && od.lastHandoverId === (cdx && cdx.handoverId)) {
          return { idempotent: true };
        }
        throw fail('failed-precondition', 'HANDOVER_CODE_MISMATCH');
      }
      if ((Number(sd.handoverAttempts) || 0) >= HANDOVER_CODE_ATTEMPTS) throw fail('failed-precondition', 'HANDOVER_CODE_LOCKED');
      const fromCourier = canonicalUid(String(ho.fromCourierId || ''));
      if (fromCourier === courierId) throw fail('failed-precondition', 'HANDOVER_SAME_COURIER');
      if (canonicalUid(String(od.courierId || '')) !== fromCourier) throw fail('failed-precondition', 'HANDOVER_STALE');
      if (![RS.picked, RS.arrived].includes(od.restaurantStatus)) throw fail('failed-precondition', 'HANDOVER_NOT_ALLOWED', { from: od.restaurantStatus });
      if (courierAuthOf().isOwnOrder(od, courierId)) throw fail('permission-denied', 'COURIER_OWN_ORDER');
      if (memberSnap.exists) throw fail('permission-denied', 'COURIER_IS_RESTAURANT_MEMBER');
      const oldRouteRef = od.deliveryRouteId ? db.collection(ROUTES).doc(String(od.deliveryRouteId)) : null;
      const oldRouteSnap = oldRouteRef ? await t.get(oldRouteRef) : null;
      // WRITE fazasi.
      const startPt = custodyStartPoint(od);
      const meters = legMeters(startPt, loc);
      const legs = Array.isArray(od.courierLegs) ? od.courierLegs.slice() : [];
      legs.push({ courierId: fromCourier, meters, fromLat: startPt ? startPt.lat : null, fromLng: startPt ? startPt.lng : null, toLat: loc.lat, toLng: loc.lng, handoverId: ho.id });
      detachFromRouteInTx(t, oldRouteRef, oldRouteSnap, orderId, 'handed_over');
      let routeId;
      if (!routeQ.empty) {
        const rt = routeQ.docs[0];
        const existing = Array.isArray(rt.data().orders) ? rt.data().orders.slice() : [];
        if (!existing.includes(orderId)) existing.push(orderId);
        t.update(rt.ref, { orders: existing, updatedAt: ts() });
        routeId = rt.id;
      } else {
        const routeRef = db.collection(ROUTES).doc();
        t.set(routeRef, {
          orders: [orderId], courierId, status: 'active', currentIndex: 0,
          routeSource: 'restaurant_handover', createdAt: ts(), startedAt: ts(),
        });
        routeId = routeRef.id;
      }
      t.delete(codeRef);
      t.set(secretRef, { handoverCode: delField(), handoverAttempts: delField(), handoverId: delField() }, { merge: true });
      t.delete(db.collection(COURIER_LIVE).doc(orderId)); // A ning nuqtasi; B o'zi yozadi (S6)
      t.update(orderRef, statusPatch(RS.picked, {
        courierId, deliveryRouteId: routeId, courierName: courierName || delField(),
        handover: delField(), lastHandoverId: ho.id, handoverCount: inc(1),
        courierLegs: legs, custodyPoint: { lat: loc.lat, lng: loc.lng },
      }));
      t.set(db.collection(CUSTODY).doc(`rest_${orderId}_${ho.id}`), custodyEventDoc({
        orderId, od, kind: 'handover',
        from: { kind: 'courier', id: fromCourier }, to: { kind: 'courier', id: courierId },
        location: loc, proof: { codeVerified: true }, actorId: courierId, handoverId: ho.id,
        meta: { meters, statusBefore: od.restaurantStatus },
      }));
      addEvent(t, orderRef, {
        from: od.restaurantStatus, to: RS.picked, actor: 'courier', actorId: courierId, reason: 'handover_accepted',
        meta: { handoverId: ho.id, fromCourierId: fromCourier, meters, routeId },
      });
      return { ok: true, fromCourier, customerUid: od.userPhone, restaurantId: od.restaurantId };
    }), (od) => (canonicalUid(String(od.courierId || '')) === courierId && od.lastHandoverId === cd.handoverId ? { idempotent: true } : null)).catch(async (e) => {
      // Noto'g'ri kod / bloklangan: urinishni buyurtma sirida ham hisoblaymiz (kod bo'yicha chegara).
      if (e instanceof HttpsError && (e.details || {}).code === 'HANDOVER_CODE_MISMATCH') {
        try { await secretRef.set({ handoverAttempts: inc(1) }, { merge: true }); } catch (_) { /* log yetarli */ }
      }
      throw e;
    });
    log('handover_accept', { orderId, userId: courierId.slice(-4), result: out.idempotent ? 'idempotent' : 'ok', durationMs: Date.now() - t0 });
    if (!out.idempotent) {
      await notifyI18n(out.fromCourier, 'courier_handover_done', {}, { orderId });
      await notifyI18n(out.customerUid, 'customer_courier_changed', {}, { orderId });
    }
    return { ok: true, orderId, ...(out.idempotent ? { idempotent: true } : {}) };
  });

  /**
   * Restoran (a'zo) kuryer qaytargan buyurtmani qabul qiladi: kuryer ekranidagi kod. Holat `ready`
   * (yangi olish kodi), kuryer va marshrut o'chadi, 30 daqiqa yangi kuryer qidiriladi; custody kuryer → restoran.
   * Naqd vykup bo'lgan bo'lsa — to'lov belgisi qaytariladi (yangi kuryer qayta vykup qiladi);
   * restoran kuryerga vykup pulini jismonan qaytaradi (AVA hisobida emas — D-REST-1; hodisada qayd).
   */
  exportsObj.restaurantAcceptReturn = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    const orderId = str(data && data.orderId, 64);
    const code = str(data && data.code, 8);
    if (!orderId || orderId.includes('/') || !/^\d{6}$/.test(code)) throw fail('invalid-argument', 'HANDOVER_CODE_INVALID');
    const orderRef = db.collection(ORDERS).doc(orderId);
    const secretRef = orderRef.collection(PRIVATE).doc('secrets');
    const out = await withContention(orderRef, 'handover_return', () => db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      await requireMemberInTx(t, String(od.restaurantId || ''), uid);
      const ho = od.handover;
      const sec = await t.get(secretRef);
      const sd = sec.exists ? (sec.data() || {}) : {};
      if (!ho || ho.status !== 'pending' || ho.target !== 'seller') {
        if (od.lastReturnBy === uid && od.restaurantStatus === RS.ready && !od.courierId) return { idempotent: true };
        throw fail('failed-precondition', 'HANDOVER_NOT_PENDING');
      }
      if ((msOf(ho.expiresAt) || 0) <= now().getTime()) throw fail('failed-precondition', 'HANDOVER_EXPIRED');
      const attempts = Number(sd.handoverAttempts) || 0;
      if (attempts >= HANDOVER_CODE_ATTEMPTS) throw fail('failed-precondition', 'HANDOVER_CODE_LOCKED');
      if (!sd.handoverCode || sd.handoverCode !== code) {
        t.set(secretRef, { handoverAttempts: inc(1) }, { merge: true });
        return { mismatch: true, left: HANDOVER_CODE_ATTEMPTS - attempts - 1 };
      }
      if (![RS.picked, RS.arrived].includes(od.restaurantStatus)) throw fail('failed-precondition', 'HANDOVER_NOT_ALLOWED', { from: od.restaurantStatus });
      const fromCourier = canonicalUid(String(ho.fromCourierId || ''));
      const routeRef = od.deliveryRouteId ? db.collection(ROUTES).doc(String(od.deliveryRouteId)) : null;
      const routeSnap = routeRef ? await t.get(routeRef) : null;
      // WRITE fazasi.
      const rPt = custodyStartPoint({ restaurantLat: od.restaurantLat, restaurantLng: od.restaurantLng });
      const startPt = custodyStartPoint(od);
      const legs = Array.isArray(od.courierLegs) ? od.courierLegs.slice() : [];
      // Qaytarilgan bo'lak yetkazishga hissa qo'shmaydi (ulushdan chiqariladi — hisobotda UNKNOWN).
      legs.push({ courierId: fromCourier, meters: 0, returned: true, handoverId: ho.id,
        fromLat: startPt ? startPt.lat : null, fromLng: startPt ? startPt.lng : null, toLat: rPt ? rPt.lat : null, toLng: rPt ? rPt.lng : null });
      const buyoutPaid = od.paidBy === 'courier_buyout' ? (Number(od.buyoutAmount) || foodAmountOf(od)) : 0;
      const until = tsOf(new Date(now().getTime() + RETURN_SEARCH_MIN * 60 * 1000));
      detachFromRouteInTx(t, routeRef, routeSnap, orderId, 'returned_to_restaurant');
      t.set(secretRef, {
        handoverCode: delField(), handoverAttempts: delField(), handoverId: delField(),
        pickupCode: pickupCode(), pickupAttempts: 0,
      }, { merge: true });
      t.delete(db.collection(COURIER_LIVE).doc(orderId));
      t.update(orderRef, statusPatch(RS.ready, {
        courierId: null, courierName: delField(), deliveryRouteId: delField(), courierClaimedAt: delField(),
        handover: delField(), lastHandoverId: ho.id, lastReturnBy: uid, handoverCount: inc(1),
        courierLegs: legs, custodyPoint: delField(), returnSearchUntil: until, returnedAt: ts(),
        ...(buyoutPaid > 0 ? { paymentStatus: 'unpaid', paidBy: delField(), paidAt: delField(), buyoutAmount: delField() } : {}),
      }));
      t.set(db.collection(CUSTODY).doc(`rest_${orderId}_${ho.id}`), custodyEventDoc({
        orderId, od, kind: 'return_to_seller',
        from: { kind: 'courier', id: fromCourier }, to: { kind: 'restaurant', id: String(od.restaurantId || '') },
        location: rPt, proof: { codeVerified: true }, actorId: uid, handoverId: ho.id,
        meta: { statusBefore: od.restaurantStatus, buyoutReturnDue: buyoutPaid },
      }));
      addEvent(t, orderRef, {
        from: od.restaurantStatus, to: RS.ready, actor: 'restaurant', actorId: uid, reason: 'returned_to_restaurant',
        meta: { handoverId: ho.id, fromCourierId: fromCourier, buyoutReturnDue: buyoutPaid, searchMin: RETURN_SEARCH_MIN },
      });
      return { ok: true, fromCourier, od: { ...od, courierId: null, restaurantStatus: RS.ready }, untilMs: until.toMillis(), buyoutPaid };
    }), (od) => (od.lastReturnBy === uid && od.restaurantStatus === RS.ready && !od.courierId ? { idempotent: true } : null));
    if (out.mismatch) {
      log('handover_return', { orderId, result: 'denied', errorCode: 'HANDOVER_CODE_MISMATCH' });
      throw fail('failed-precondition', 'HANDOVER_CODE_MISMATCH', { attemptsLeft: out.left });
    }
    log('handover_return', { orderId, userId: uid.slice(-4), result: out.idempotent ? 'idempotent' : 'ok', durationMs: Date.now() - t0 });
    if (!out.idempotent) {
      await notifyI18n(out.fromCourier, 'courier_return_done', {}, { orderId });
      await notifyNearbyCouriers(orderId, out.od, 'ready');
    }
    return { ok: true, ...(out.idempotent ? { idempotent: true } : { searchUntilMs: out.untilMs, buyoutReturnDue: out.buyoutPaid }) };
  });

  /**
   * Jadval (har daqiqa): qaytarilgan / qo'yib yuborilgan buyurtmaga 30 daqiqada kuryer topilmadi →
   * bekor (`rejected`, `rejectedBy: system`, sabab `no_courier_after_return`), 2 % restoranga qaytadi.
   * Kuryer olgan bo'lsa — faqat maydon o'chadi. Bitta maydon diapazon so'rovi — kompozit indeks yo'q.
   */
  async function expireReturnedOne(orderRef, at) {
    return db.runTransaction(async (t) => {
      const s = await t.get(orderRef);
      if (!s.exists) return null;
      const od = s.data() || {};
      const dl = msOf(od.returnSearchUntil);
      if (dl === null) return null;
      const searching = od.type === 'restaurant' && !od.courierId && [RS.accepted, RS.ready].includes(od.restaurantStatus);
      if (!searching) {
        t.update(orderRef, { returnSearchUntil: delField() });
        return { stale: true };
      }
      if (dl > at.getTime()) return null;
      const prep = await prepareFeeInTx(t, od, orderRef.id, false);
      const refund = commitFeeInTx(t, prep, { orderId: orderRef.id, actorId: 'system' });
      t.update(orderRef, statusPatch(RS.rejected, {
        rejectedAt: ts(), rejectedBy: 'system', rejectReason: 'no_courier_after_return', returnSearchUntil: delField(),
        'avaFee.refunded': refund.applied, 'avaFee.refundedAt': refund.applied ? ts() : null,
      }));
      addEvent(t, orderRef, { from: od.restaurantStatus, to: RS.rejected, actor: 'system', reason: 'no_courier_after_return', meta: { refundAmount: refund.amount } });
      return { orderId: orderRef.id, restaurantId: od.restaurantId, customerUid: od.userPhone, prepaid: od.foodPaymentMethod === 'prepay' && od.paymentStatus === 'paid' };
    });
  }

  async function expireReturned() {
    const at = now();
    const snap = await db.collection(ORDERS).where('returnSearchUntil', '<=', tsOf(at)).limit(ESCALATE_BATCH).get();
    let cancelled = 0;
    for (const doc of snap.docs) {
      try {
        const r = await expireReturnedOne(doc.ref, at);
        if (!r || r.stale) continue;
        cancelled += 1;
        log('return_expire', { orderId: r.orderId, restaurantId: r.restaurantId, result: 'rejected_no_courier', prepaid: r.prepaid });
        await notifyI18n(r.customerUid, r.prepaid ? 'customer_no_courier_cancel_prepaid' : 'customer_no_courier_cancel', {}, { orderId: r.orderId });
        await notifyMembersI18n(r.restaurantId, r.prepaid ? 'restaurant_no_courier_cancel_prepaid' : 'restaurant_no_courier_cancel', {}, r.orderId);
      } catch (e) {
        console.error(JSON.stringify({ module: MODULE_ID, action: 'return_expire', orderId: doc.id, result: 'failed', errorCode: 'RETURN_EXPIRE_FAILED', message: String((e && e.message) || e).slice(0, 160) }));
      }
    }
    return { scanned: snap.size, cancelled };
  }

  exportsObj.expireReturnedRestaurantOrders = functions.pubsub
    .schedule('every 1 minutes')
    .timeZone('Asia/Tashkent')
    .onRun(async () => expireReturned());

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

  /**
   * Kuryer jonli nuqtalarini tozalash (S6, 40-qoida: PII minimal): hujjati 2 soatdan eski yoki buyurtmasi
   * endi faol emas (terminal holat / yo'q). Asosiy tozalash buyurtma yakunida tranzaksiya ichida; bu — zaxira.
   */
  async function sweepCourierLive() {
    const cutoff = tsOf(new Date(now().getTime() - COURIER_LIVE_TTL_MIN * 60 * 1000));
    const snap = await db.collection(COURIER_LIVE).where('updatedAt', '<', cutoff).limit(400).get();
    if (snap.empty) return { deleted: 0 };
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    return { deleted: snap.size };
  }

  exportsObj.sweepRestaurantCourierLive = functions.pubsub
    .schedule('every 60 minutes')
    .timeZone('Asia/Tashkent')
    .onRun(async () => {
      const r = await sweepCourierLive();
      if (r.deleted > 0) log('courier_live_sweep', { result: 'ok', deleted: r.deleted });
      return null;
    });

  exportsObj.expireUnacceptedRestaurantOrders = functions.pubsub
    .schedule('every 1 minutes')
    .timeZone('Asia/Tashkent')
    .onRun(async () => expireUnaccepted());

  return {
    // test/diagnostika uchun sof qismlar
    RS, TRANSITIONS, LEGACY, canTransition, isOpenAt, expireUnaccepted, moduleAccess, sweepCourierLive,
    ACCEPT_TIMEOUT_MIN, AUTO_PAUSE_AFTER_TIMEOUTS,
  };
}

module.exports = {
  attachRestaurantOrders,
  RS, TRANSITIONS, LEGACY, canTransition, isOpenAt, hhmmToMin, tashkentLabel,
  ACCEPT_TIMEOUT_MIN, AUTO_PAUSE_AFTER_TIMEOUTS, AUTO_PAUSE_MIN,
  STRIKES_FOR_PREPAY_ONLY, PREPAY_ONLY_DAYS, PICKUP_CODE_ATTEMPTS,
  EARNINGS_ACCOUNT, MODULE_ID,
  // «Yetkazilmadi» sabablari — boshqa modullar (delivery_failed.js) ham shuni ishlatadi (7-qoida).
  FAIL_REASONS,
  computeCourierShares, HANDOVER_TTL_MIN, RETURN_SEARCH_MIN, HANDOVER_CODE_ATTEMPTS,
};
