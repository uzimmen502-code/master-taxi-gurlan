/**
 * «МЕНИНГ БИЗНЕСИМ» — МАҲСУЛОТ БУЮРТМАСИ AVA КУРЬЕРИ БИЛАН (сервер томони).
 *
 * Эга қарорлари (CONFIRMED, 2026-11-03):
 *   - МАВЖУД курьер тизими қайта ишлатилади (параллел тизим йўқ): `orders` ҳужжати (`type: 'business'`),
 *     `delivery_routes`, `courier_auth.js` (new/finish, туман доираси), `courier_push.js`, `customer_confirm.js`,
 *     «етказилмади» — `delivery_failed.js` (модул `business`, қарорни сотувчи қилади — ресторандаги каби).
 *   - Етказиш ҳақини ХАРИДОР курьерга тўлайди (ресторан модели): нақд ёки ҳамён (`bizDelivery_{orderId}`,
 *     мижоз passenger_credit → курьер passenger_credit, ресторан `restDelivery_` билан бир хил ёндашув).
 *   - AVA ҳозир комиссия ОЛМАЙДИ (ресторан ҳужжатидаги `avaFeeBps` бу ерда ЎҚИЛМАЙДИ). Ҳар буюртмага
 *     `avaFee` муҳри (rateBps 0, settingsVersion). Комиссия ечиш коди ҲАЛИ ЙЎҚ — шунинг учун > 0 қиймат
 *     буюртмани РАД этади (`AVA_FEE_NOT_SUPPORTED`, fail closed), админ callable эса фақат 0 қабул қилади.
 *   - Фақат ЖИСМОНИЙ жойи бор объект (`businesses.online != true`, координата бор) ва фақат
 *     `kind == 'product'` маҳсулот; хизмат етказилмайди.
 *
 * ТОВАР ПУЛИ (CONFIRMED эга 2026-11-03 — ресторан `cash_buyout` семантикаси): курьер олиб кетишда товар
 * пулини СОТУВЧИГА ўз пулидан беради ва мижоздан жами (товар + нақд бўлса етказиш) олади. Товар пули
 * AVA ledger'ига ЁЗИЛМАЙДИ (AVA сотувчи эмас) — фақат ҳолат (`paymentStatus`, `buyoutAmount`) ва ҳодиса.
 * Курьернинг вэкуп лимити — мавжуд `restaurant_courier_prefs` (`courierSetBuyoutPrefs`).
 * «Етказилмади»да товар сотувчига қайтади (ҳодиса); вэкуп пулини сотувчи курьерга қайтариши — AVA'дан
 * ташқари (UNKNOWN: эга қарори керак).
 *
 * ТАРИФ — МАВЖУД ресторан тарифи `settings/restaurant_delivery` (эга 2026-11-03; соф функциялар
 * `restaurant_delivery_tariff.js`дан), тарих `restaurant_delivery_tariffs/v{n}`, ҳужжат/нарх йўқ →
 * `TARIFF_NOT_CONFIGURED`. Чегаралар (15 дақ, 100/30, ''/дона/кг/м²) — CONFIRMED эга 2026-11-03. Буюртмага `deliveryTariffVersion` + `deliveryTariffSnapshot` (9-қоида).
 *
 * БОСҚИЧ (42-қоида) — `server_config/business_orders` (rules'да match йўқ = клиентга ёпиқ; тестер
 * телефонлари оммавий эмас, 40-қоида): { stage: off|internal|pilot|public, testerIds, pilotDistrictIds,
 * acceptTimeoutMin, version }. Ҳужжат йўқ → OFF. Фақат ЯНГИ буюртма (quote/place) тўсилади; бошланган
 * буюртмалар якунланади (custody узилмасин).
 *
 * Ҳолатлар — `business_order_states.js` (ягона манба). Ҳар ўтиш транзакцияда ва `orders/{id}/order_events`
 * (append-only) га ёзилади. Structured log: orderId, businessId, userId (охирги 4), action, result,
 * errorCode, durationMs — телефон/манзил ЙЎҚ (24, 40-қоида). Хато коди `details.code` да (25-қоида).
 */
'use strict';

const crypto = require('crypto');
const tariff = require('./restaurant_delivery_tariff');
const localTaxi = require('./local_taxi');
const i18n = require('./notif_i18n');
const states = require('./business_order_states');
const deliveryFailedLib = require('./delivery_failed');

const { BS, ORDER_TYPE, isBusinessOrder, canTransition, statusFields } = states;

const MODULE_ID = 'business_orders';
/** `customer_confirm.js` модул калити. */
const CC_MODULE = 'business';
const ORDERS = 'orders';
const ORDER_EVENTS = 'order_events';
const PRIVATE = 'private';
const ROUTES = 'delivery_routes';
const IDEMPOTENCY = 'wallet_idempotency';
const BUSINESSES = 'businesses';
const ITEMS = 'tv_shop_items';
const COURIER_PREFS = 'restaurant_courier_prefs';
const COURIER_LIVE = 'order_courier_live';
const CUSTODY = 'custody_events';
const ADMIN_AUDIT = 'admin_audit';
const CONFIG_DOC = Object.freeze(['server_config', 'business_orders']);
/**
 * Эга 2026-11-03: «мавжуд тариф ишлатилсин» — ресторан етказиш тарифи (битта манба, 7-қоида).
 * Нархни фақат `adminSetRestaurantDeliveryPrices` ўзгартиради (версия + тарих шу ерда).
 */
const TARIFF_DOC = Object.freeze(['settings', 'restaurant_delivery']);
const TARIFF_HISTORY = 'restaurant_delivery_tariffs';

const STAGES = Object.freeze(['off', 'internal', 'pilot', 'public']);
/** Сотувчи қабул қилиш муддати, дақиқа (PROPOSED; `acceptTimeoutMin` билан ўзгаради). */
const ACCEPT_TIMEOUT_MIN_DEFAULT = 15;
const ACCEPT_TIMEOUT_MIN_MIN = 5;
const ACCEPT_TIMEOUT_MIN_MAX = 120;
const MAX_ITEMS = 30;
/** Бир маҳсулотдан энг кўп миқдор (PROPOSED). */
const MAX_QTY = 100;
/** firestore.rules `tvShopItemShapeOk` чегараси билан бир хил. */
const MAX_PRICE = 999999999;
/**
 * Буюртма бериладиган нарх бирликлари (PROPOSED): белгиланган нарх ('') ва дона/кг/м² — миқдор бутун сон.
 * 'from' (… дан бошлаб) ва 'negotiable' — қатъий нарх эмас; соат/кун/ой/сеанс/киши — хизмат бирликлари.
 */
const ORDERABLE_PRICE_UNITS = Object.freeze(['', 'piece', 'kg', 'm2']);
const GOODS_PAYMENT = Object.freeze(['cash_buyout']);
const DELIVERY_PAYMENT = Object.freeze(['cash', 'wallet']);
const PICKUP_CODE_ATTEMPTS = 5;
const NEARBY_RADIUS_KM_DEFAULT = 15;
const NEARBY_LIMIT = 100;
const COURIER_PUSH_MAX = 30;
const COURIER_PUSH_MIN_GAP_MS = 30 * 1000;
const EXPIRE_BATCH = 200;
/** AVA улуши ledger ҳисоб-китоб версияси (ҳозир ечилмайди; муҳр учун). */
const AVA_FEE_LEDGER_VERSION = 1;
const MAX_TESTERS = 500;

const TESTER_RE = /^998\d{9}$/;
const GEO_ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
const DOC_ID_RE = /^[A-Za-z0-9_-]{1,128}$/;
const IDEM_RE = /^[A-Za-z0-9_-]{8,80}$/;

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

const msOf = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : null);
const tail4 = (v) => String(v || '').replace(/\D/g, '').slice(-4);

// ─────────────────────────────────────────────────────────────────────────
// СОФ ҚИСМ (тестланади)
// ─────────────────────────────────────────────────────────────────────────

/** `server_config/business_orders` → меъёрланган босқич. Нотўғри қиймат → 'off' (fail closed). */
function parseConfig(raw, canon) {
  const d = raw && typeof raw === 'object' ? raw : {};
  const stage = STAGES.includes(d.stage) ? d.stage : 'off';
  const testerIds = [...new Set((Array.isArray(d.testerIds) ? d.testerIds : [])
    .filter((x) => typeof x === 'string' || typeof x === 'number')
    .map((x) => canon(String(x)))
    .filter((x) => TESTER_RE.test(x)))].sort();
  const pilotDistrictIds = [...new Set((Array.isArray(d.pilotDistrictIds) ? d.pilotDistrictIds : [])
    .map((x) => String(x == null ? '' : x).trim())
    .filter((x) => GEO_ID_RE.test(x)))].sort();
  return {
    stage,
    testerIds,
    pilotDistrictIds,
    acceptTimeoutMin: intOr(d.acceptTimeoutMin, ACCEPT_TIMEOUT_MIN_DEFAULT, ACCEPT_TIMEOUT_MIN_MIN, ACCEPT_TIMEOUT_MIN_MAX),
    version: intOr(d.version, 0, 0, 1000000),
  };
}

/**
 * Янги буюртмага рухсат: off → ҳеч ким; internal → фақат тестер; pilot → тестер ёки объект тумани
 * `pilotDistrictIds`да; public → ҳамма.
 */
function accessOf(cfg, uid, districtId) {
  const stage = cfg.stage;
  if (stage === 'off') return { allowed: false, stage, reason: 'MODULE_OFF' };
  if (stage === 'public') return { allowed: true, stage, reason: null };
  if (cfg.testerIds.includes(uid)) return { allowed: true, stage, reason: null };
  if (stage === 'pilot' && districtId && cfg.pilotDistrictIds.includes(districtId)) {
    return { allowed: true, stage, reason: null };
  }
  return { allowed: false, stage, reason: stage === 'internal' ? 'MODULE_INTERNAL_ONLY' : 'MODULE_NOT_IN_PILOT' };
}

/**
 * AVA улуши (эга 2026-11-03: ҳозир 0). Майдон йўқ → 0; нотўғри → `AVA_FEE_CONFIG_INVALID`;
 * > 0 → `AVA_FEE_NOT_SUPPORTED` (ечиш коди йўқ — жимгина 0 қилиб юбормаймиз, fail closed).
 */
function resolveAvaFee(tariffDoc) {
  const d = tariffDoc && typeof tariffDoc === 'object' ? tariffDoc : {};
  const settingsVersion = intOr(d.version, 0, 0, 1000000);
  const v = d.avaFeeBps;
  if (v === undefined || v === null) return { ok: true, rateBps: 0, source: 'default', settingsVersion };
  if (typeof v !== 'number' || !Number.isInteger(v) || v < tariff.AVA_FEE_BPS_MIN || v > tariff.AVA_FEE_BPS_MAX) {
    return { ok: false, code: 'AVA_FEE_CONFIG_INVALID' };
  }
  if (v > 0) return { ok: false, code: 'AVA_FEE_NOT_SUPPORTED' };
  return { ok: true, rateBps: 0, source: 'setting', settingsVersion };
}

/** Клиент рўйхати → { itemId → жами миқдор } (тартиб сақланади). `bad(code, extra)` — хато ясовчи. */
function parseWanted(itemsIn, bad) {
  const list = Array.isArray(itemsIn) ? itemsIn : [];
  if (list.length < 1 || list.length > MAX_ITEMS) throw bad('ITEMS_REQUIRED', { max: MAX_ITEMS });
  const wanted = new Map();
  for (const it of list) {
    const id = str(it && it.itemId, 128);
    const qty = intOr(it && it.qty, 0, 1, MAX_QTY);
    if (!id || !DOC_ID_RE.test(id) || qty < 1) throw bad('ITEM_INVALID', {});
    wanted.set(id, (wanted.get(id) || 0) + qty);
  }
  for (const [itemId, count] of wanted) {
    if (count > MAX_QTY) throw bad('QTY_LIMIT_EXCEEDED', { itemId, maxQty: MAX_QTY });
  }
  return wanted;
}

/**
 * Нарх ФАҚАТ каталогдан (18-қоида): клиент нархи эътиборсиз. Ҳар қатор — шу объектнинг (`businessId`),
 * шу эганинг (`ownerPhone`), фаол, `kind == 'product'`, қатъий нархли маҳсулоти.
 * @param {Map<string, number>} wanted
 * @param {Map<string, object|null>} docs itemId → маълумот (йўқ бўлса null)
 */
function priceLines({ wanted, docs, businessId, sellerUid, canon, bad }) {
  const items = [];
  let itemsTotal = 0;
  for (const [itemId, qty] of wanted) {
    const m = docs.get(itemId);
    if (!m) throw bad('ITEM_NOT_FOUND', { itemId });
    if (String(m.businessId || '') !== businessId || canon(String(m.ownerPhone || '')) !== sellerUid) {
      throw bad('ITEM_NOT_IN_BUSINESS', { itemId });
    }
    if (String(m.status || 'active') !== 'active') throw bad('ITEM_UNAVAILABLE', { itemId });
    if (String(m.kind || 'product') !== 'product') throw bad('ITEM_NOT_PRODUCT', { itemId });
    const priceUnit = typeof m.priceUnit === 'string' ? m.priceUnit : '';
    if (!ORDERABLE_PRICE_UNITS.includes(priceUnit)) throw bad('PRICE_NOT_FIXED', { itemId, priceUnit });
    // Фақат ҲАҚИҚИЙ бутун сон (`'5000'` сатри ҳам рад): ҳужжатни эгаси ёзади (клиент маълумоти).
    const price = typeof m.price === 'number' ? m.price : Number.NaN;
    if (!Number.isInteger(price) || price <= 0 || price > MAX_PRICE) throw bad('ITEM_PRICE_INVALID', { itemId });
    const lineTotal = price * qty;
    itemsTotal += lineTotal;
    items.push({ itemId, title: str(m.title, 120), unitPrice: price, priceUnit, qty, lineTotal });
  }
  if (!Number.isSafeInteger(itemsTotal)) throw bad('ITEMS_TOTAL_INVALID', {});
  return { items, itemsTotal };
}

function pickupCode() {
  return String(crypto.randomInt(0, 10000)).padStart(4, '0');
}

// ─────────────────────────────────────────────────────────────────────────
// CALLABLE'ЛАР
// ─────────────────────────────────────────────────────────────────────────

function attachBusinessOrders(exportsObj, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, settlementLedger, requireCallerRoles,
    notifyUserInApp, notifyCourierArrivedToCustomer, axios, fetchRoute: fetchRouteOverride, now: nowFn,
    courierPush, customerConfirm,
  } = deps;
  const courierAuthOf = () => deps.courierAuth;
  const MODES = deps.COURIER_AUTH_MODES || { new: 'new', finish: 'finish' };
  const now = nowFn || (() => new Date());
  const HttpsError = functions.https.HttpsError;
  const FV = admin.firestore.FieldValue;
  const ts = () => FV.serverTimestamp();
  const inc = (n) => FV.increment(n);
  const del = () => FV.delete();
  const tsOf = (d) => admin.firestore.Timestamp.fromDate(d);
  const canon = (v) => canonicalUid(String(v == null ? '' : v));
  const fetchRoute = fetchRouteOverride || ((p) => localTaxi.fetchRouteViaGoogle(axios, p));
  const fail = (status, code, extra = {}) => new HttpsError(status, code, { code, ...extra });
  const bad = (status) => (code, extra) => fail(status, code, extra);

  function log(action, fields) {
    console.log(JSON.stringify({ module: MODULE_ID, action, ...fields }));
  }

  function requirePhoneUid(context) {
    if (!context || !context.auth) throw fail('unauthenticated', 'AUTH_REQUIRED');
    const uid = canon(callerPhone(context));
    if (!uid || uid.length < 12) throw fail('unauthenticated', 'PHONE_TOKEN_REQUIRED');
    return uid;
  }

  function orderIdOf(data) {
    const id = str(data && data.orderId, 128);
    if (!id || !DOC_ID_RE.test(id)) throw fail('invalid-argument', 'ORDER_ID_REQUIRED');
    return id;
  }

  async function readConfig() {
    const s = await db.collection(CONFIG_DOC[0]).doc(CONFIG_DOC[1]).get();
    return parseConfig(s.exists ? s.data() : null, canon);
  }

  async function readTariffDoc() {
    const s = await db.collection(TARIFF_DOC[0]).doc(TARIFF_DOC[1]).get();
    return s.exists ? (s.data() || {}) : {};
  }

  // ── Умумий ёзувлар ───────────────────────────────────────────────────
  function statusPatch(bs, extra = {}) {
    return { ...statusFields(bs), statusUpdatedAt: ts(), updatedAt: ts(), ...extra };
  }

  function addEvent(t, orderRef, { from, to, actor, actorId, reason = '', meta = {} }) {
    t.set(orderRef.collection(ORDER_EVENTS).doc(), {
      from: from || null, to, actor, actorId: actorId || null, reason, meta, at: ts(),
    });
  }

  function assertTransition(od, to, orderId) {
    const from = String(od.businessStatus || '');
    if (canTransition(from, to)) return from;
    log('transition', { orderId, result: 'denied', errorCode: 'ORDER_INVALID_TRANSITION', from, to });
    throw fail('failed-precondition', 'ORDER_INVALID_TRANSITION', { from, to });
  }

  async function getOrderInTx(t, orderRef) {
    const s = await t.get(orderRef);
    if (!s.exists) throw fail('not-found', 'ORDER_NOT_FOUND');
    const od = s.data() || {};
    if (!isBusinessOrder(od)) throw fail('failed-precondition', 'NOT_BUSINESS_ORDER');
    return od;
  }

  /** Сотувчи = буюртмадаги `sellerUid` (= `businesses.ownerId`, ўзгармас; 19-қоида). */
  function requireSeller(od, uid) {
    if (canon(od.sellerUid) !== uid) throw fail('permission-denied', 'NOT_ORDER_SELLER');
  }

  /** «Етказилмади» кутиш майдонлари (delivery_failed.js) бўлса — ўчириш ямоқчаси, акс ҳолда `{}`. */
  function dfClear(od) {
    const out = {};
    for (const k of [deliveryFailedLib.DUE_AT, deliveryFailedLib.OPEN, deliveryFailedLib.ESCALATED_AT]) {
      if (od && od[k] !== undefined) out[k] = del();
    }
    return out;
  }

  function detachFromRouteInTx(t, routeRef, routeSnap, orderId, reason) {
    if (!routeRef || !routeSnap || !routeSnap.exists) return;
    const rd = routeSnap.data() || {};
    const remaining = (Array.isArray(rd.orders) ? rd.orders : []).filter((id) => id !== orderId);
    const exhausted = remaining.length <= (Number(rd.currentIndex) || 0)
      && ['active', 'ready'].includes(String(rd.status || ''));
    t.update(routeRef, {
      orders: remaining, updatedAt: ts(),
      ...(exhausted ? { status: 'completed', completedAt: ts(), completedReason: reason } : {}),
    });
  }

  function custodyDoc({ orderId, od, kind, from, to, location, proof, actorId }) {
    return {
      orderType: ORDER_TYPE,
      orderId,
      businessId: String(od.businessId || ''),
      // `shipmentId` йўқ — relay/wholesale custody триггерлари ўтказиб юборади.
      shipmentId: null,
      legId: null,
      ownerId: canon(od.userPhone),
      kind, from, to,
      timestamp: ts(),
      location: location || null,
      proof: proof || {},
      createdBy: actorId,
      idempotencyKey: `biz_${orderId}_${kind}`,
      meta: {},
      deliversShipment: false,
    };
  }

  /**
   * Транзакция хом хато билан йиқилса (параллел чақирув, ABORTED), буюртмани бир марта қайта ўқиб
   * аниқ код қайтаради (22, 25-қоида). `resolve(od)` — натижа ёки HttpsError; null → CONTENTION_RETRY.
   */
  async function withContention(orderRef, action, run, resolve) {
    try {
      return await run();
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      const snap = await orderRef.get();
      const od = snap.exists ? (snap.data() || {}) : null;
      const out = od ? resolve(od) : null;
      log(action, { orderId: orderRef.id, result: 'contention', errorCode: out ? 'resolved' : 'ABORTED' });
      if (out) return out;
      throw fail('aborted', 'CONTENTION_RETRY');
    }
  }

  // ── Хабарлар (3 тилда, best-effort, транзакциядан ташқарида) ──────────
  async function notifyI18n(userId, key, params, extra = {}) {
    try {
      const u = canon(userId);
      if (u.length < 12) return;
      const lang = await i18n.langOfPhone(db, u);
      const m = i18n.render(key, lang, params || {});
      await notifyUserInApp({
        userId: u, title: m.title, body: m.body, category: 'order', source: 'business_order',
        extraNews: { orderId: String(extra.orderId || ''), orderType: ORDER_TYPE },
        dataType: 'business_order', screen: extra.screen || 'orders',
        extraData: { orderId: String(extra.orderId || ''), ...(extra.data || {}) },
        ...(extra.channelId ? { channelId: extra.channelId } : {}),
      });
    } catch (e) {
      console.error(JSON.stringify({ module: MODULE_ID, action: 'notify', key, result: 'failed', errorCode: 'NOTIFY_FAILED', message: String((e && e.message) || e).slice(0, 160) }));
    }
  }

  const notifySeller = (sellerUid, key, params, orderId, businessId) => notifyI18n(sellerUid, key, params, {
    orderId, screen: 'business_orders', data: { businessId: String(businessId || ''), ring: '1' }, channelId: 'courier_arrival_alarm',
  });
  const notifyBuyer = (uid, key, params, orderId) => notifyI18n(uid, key, params, { orderId, screen: 'orders' });
  const notifyCourier = (uid, key, params, orderId) => notifyI18n(uid, key, params, { orderId, screen: 'courier' });
  const groupThousands = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');

  /**
   * Яқин ОНЛАЙН курьерларга таклиф (ресторан `notifyNearbyCouriers` намунаси): фақат FCM, радиус,
   * энг яқин N та, мижоз ва сотувчи — йўқ, вэкуп лимити етмайдиган курьер — йўқ, ҳар курьерга
   * `COURIER_PUSH_MIN_GAP_MS` дан тез эмас (`restaurant_courier_prefs.lastPushAt` — умумий чеклов).
   */
  async function notifyNearbyCouriers(orderId, od, stage) {
    const empty = { candidates: 0, notified: 0 };
    try {
      if (!courierPush || od.courierId) return empty;
      const pLat = Number(od.businessLat);
      const pLng = Number(od.businessLng);
      if (!validLatLng(pLat, pLng)) return empty;
      const candidates = (await courierPush.onlineCouriers())
        .filter((c) => c.lat != null && c.lng != null)
        .map((c) => ({ ...c, distanceM: tariff.haversineMeters(pLat, pLng, c.lat, c.lng) }))
        .filter((c) => c.distanceM <= NEARBY_RADIUS_KM_DEFAULT * 1000)
        .sort((a, b) => a.distanceM - b.distanceM)
        .slice(0, COURIER_PUSH_MAX);
      if (candidates.length === 0) return empty;
      const customer = canon(od.userPhone);
      const seller = canon(od.sellerUid);
      const buyout = Number(od.itemsTotal) || 0;
      const fee = Number(od.deliveryFee) || 0;
      const nowMs = now().getTime();
      let notified = 0;
      for (const c of candidates) {
        if (c.id === customer || c.id === seller) continue;
        const prefRef = db.collection(COURIER_PREFS).doc(c.id);
        const p = (await prefRef.get()).data() || {};
        const limit = p.buyoutEnabled === true ? intOr(p.buyoutLimit, 0, 0, 100000000) : 0;
        if (buyout > limit) continue;
        const lastMs = msOf(p.lastPushAt) || 0;
        if (nowMs - lastMs < COURIER_PUSH_MIN_GAP_MS) continue;
        await prefRef.set({ lastPushAt: ts(), lastPushOrderId: orderId, lastPushStage: `business_${stage}` }, { merge: true });
        notified += 1;
        const token = await courierPush.resolveToken(c.id);
        if (!token) continue;
        try {
          const lang = await i18n.langOfPhone(db, c.id);
          const m = i18n.render('business_courier_offer', lang, {
            name: str(od.businessName, 60), km: (c.distanceM / 1000).toFixed(1),
            fee: groupThousands(fee), buyout: groupThousands(buyout),
          });
          await admin.messaging().send({
            token,
            notification: { title: m.title, body: m.body },
            data: { type: 'business_courier_offer', screen: 'courier', orderId, businessId: String(od.businessId || ''), stage },
            android: { priority: 'high' },
          });
        } catch (e) {
          console.error(JSON.stringify({ module: MODULE_ID, action: 'courier_push', orderId, result: 'failed', errorCode: 'FCM_FAILED' }));
        }
      }
      log('courier_push', { orderId, stage, candidates: candidates.length, notified });
      return { candidates: candidates.length, notified };
    } catch (e) {
      console.error(JSON.stringify({ module: MODULE_ID, action: 'courier_push', orderId, result: 'failed', errorCode: 'COURIER_PUSH_FAILED', message: String((e && e.message) || e).slice(0, 160) }));
      return empty;
    }
  }

  // ── Етказиш нархи (масофа тарифи, версия) ───────────────────────────────
  async function quoteDelivery({ fromLat, fromLng, toLat, toLng }, tariffDoc) {
    const regionKey = tariff.resolveRegionKey(fromLat, fromLng);
    const prices = tariff.resolveDeliveryPrices(tariffDoc, regionKey);
    if (!prices) throw fail('failed-precondition', 'TARIFF_NOT_CONFIGURED');
    let route = null;
    try {
      route = await fetchRoute({ fromLat, fromLng, toLat, toLng });
    } catch (e) {
      console.error(JSON.stringify({ module: MODULE_ID, action: 'route', result: 'failed', errorCode: 'ROUTE_FAILED', message: String((e && e.message) || e).slice(0, 120) }));
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
    const night = tariff.isNightAt(now(), prices.nightStartH, prices.nightEndH);
    const r = tariff.computeDeliveryFee({ distanceMeters: route.distanceMeters, prices, night });
    return {
      deliveryFee: r.fee,
      deliveryTariffVersion: prices.version,
      deliveryTariffSnapshot: {
        regionKey: prices.regionKey, priceSource: prices.source,
        base: prices.base, perKm: prices.perKm, nightPermille: r.nightPermille,
        nightStartH: prices.nightStartH, nightEndH: prices.nightEndH,
        roadFactorPermille: prices.roadFactorPermille, maxKm: prices.maxKm,
        distancePart: r.distancePart, night,
      },
      distanceMeters: route.distanceMeters,
      distanceSource,
    };
  }

  /**
   * quote ва place учун УМУМИЙ тайёрлов (7-қоида): босқич, объект, сотувчи, маҳсулотлар, нарх,
   * етказиш тарифи, AVA улуши. Ёзув ЙЎҚ.
   */
  async function prepareOrder(uid, d) {
    const cfg = await readConfig();
    if (cfg.stage === 'off') throw fail('failed-precondition', 'MODULE_OFF', { stage: 'off' });
    const businessId = str(d.businessId, 128);
    if (!businessId || !DOC_ID_RE.test(businessId)) throw fail('invalid-argument', 'BUSINESS_ID_REQUIRED');
    const toLat = d.lat != null ? Number(d.lat) : Number.NaN;
    const toLng = d.lng != null ? Number(d.lng) : Number.NaN;
    const wanted = parseWanted(d.items, bad('invalid-argument'));

    const bSnap = await db.collection(BUSINESSES).doc(businessId).get();
    if (!bSnap.exists) throw fail('not-found', 'BUSINESS_NOT_FOUND');
    const b = bSnap.data() || {};
    if (String(b.status || 'active') !== 'active') throw fail('failed-precondition', 'BUSINESS_NOT_ACTIVE');
    const districtId = str(b.districtId, 64);
    const access = accessOf(cfg, uid, districtId);
    if (!access.allowed) throw fail('failed-precondition', access.reason, { stage: access.stage });
    if (b.online === true) throw fail('failed-precondition', 'BUSINESS_ONLINE_NO_PICKUP');
    const fromLat = Number(b.lat);
    const fromLng = Number(b.lng);
    if (typeof b.lat !== 'number' || typeof b.lng !== 'number' || !validLatLng(fromLat, fromLng)) {
      throw fail('failed-precondition', 'BUSINESS_LOCATION_MISSING');
    }
    const sellerUid = canon(b.ownerId);
    if (!TESTER_RE.test(sellerUid)) throw fail('failed-precondition', 'BUSINESS_NO_OWNER');
    if (sellerUid === uid) throw fail('failed-precondition', 'OWN_BUSINESS');
    if (!validLatLng(toLat, toLng)) throw fail('invalid-argument', 'DELIVERY_ADDRESS_REQUIRED');

    const ids = [...wanted.keys()];
    const snaps = await db.getAll(...ids.map((id) => db.collection(ITEMS).doc(id)));
    const docs = new Map(snaps.map((s) => [s.id, s.exists ? (s.data() || {}) : null]));
    const { items, itemsTotal } = priceLines({
      wanted, docs, businessId, sellerUid, canon, bad: bad('failed-precondition'),
    });

    const tariffDoc = await readTariffDoc();
    // Ресторан ҳужжатидаги `avaFeeBps` — ресторан улуши (D9), бизнес буюртмасига ТЕГИШЛИ ЭМАС:
    // эга 2026-11-03 — бизнес буюртмасидан AVA улуши йўқ. Муҳр версияси = босқич конфиги версияси.
    const ava = resolveAvaFee({ version: cfg.version });
    if (!ava.ok) throw fail('failed-precondition', ava.code);
    const quote = await quoteDelivery({ fromLat, fromLng, toLat, toLng }, tariffDoc);
    const avaFee = {
      rateBps: ava.rateBps,
      basis: itemsTotal,
      amount: tariff.computeAvaFee(itemsTotal, { rateBps: ava.rateBps }).amount,
      version: AVA_FEE_LEDGER_VERSION,
      settingsVersion: ava.settingsVersion,
      rateSource: ava.source,
      charged: false,
    };
    return { cfg, businessId, b, districtId, sellerUid, fromLat, fromLng, toLat, toLng, items, itemsTotal, quote, avaFee };
  }

  // ═══════════════════════════════════════════════════════════════════════
  // МИЖОЗ
  // ═══════════════════════════════════════════════════════════════════════

  /** data: { businessId? } → { allowed, stage, reason }. Тестер рўйхати қайтмайди (40-қоида). */
  exportsObj.getBusinessOrdersAccess = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const cfg = await readConfig();
    let districtId = '';
    const businessId = str(data && data.businessId, 128);
    if (cfg.stage === 'pilot' && businessId && DOC_ID_RE.test(businessId)) {
      const s = await db.collection(BUSINESSES).doc(businessId).get();
      districtId = s.exists ? str((s.data() || {}).districtId, 64) : '';
    }
    const a = accessOf(cfg, uid, districtId);
    return { allowed: a.allowed, stage: a.stage, reason: a.reason };
  });

  /** data: { businessId, items:[{itemId, qty}], lat, lng } → нарх (ёзувсиз). */
  exportsObj.quoteBusinessOrder = functions
    .runWith({ secrets: ['DIRECTIONS_API_KEY'] })
    .https.onCall(async (data, context) => {
      const uid = requirePhoneUid(context);
      const p = await prepareOrder(uid, data || {});
      return {
        ok: true,
        businessId: p.businessId,
        items: p.items,
        itemsTotal: p.itemsTotal,
        deliveryFee: p.quote.deliveryFee,
        total: p.itemsTotal + p.quote.deliveryFee,
        deliveryTariffVersion: p.quote.deliveryTariffVersion,
        distanceMeters: p.quote.distanceMeters,
        goodsPaymentMethods: [...GOODS_PAYMENT],
        deliveryPaymentMethods: [...DELIVERY_PAYMENT],
        avaFeeBps: p.avaFee.rateBps,
      };
    });

  /**
   * data: { idempotencyKey, businessId, items, lat, lng, address?, note?, userName?,
   *         deliveryPaymentMethod: 'cash'|'wallet', goodsPaymentMethod?: 'cash_buyout' }
   * Нарх фақат серверда (18), идемпотент (`wallet_idempotency/{key}` — транзакциядан олдин ва ичида, 21),
   * `placed` + `acceptDeadlineAt`. Пул ҳаракати ЙЎҚ (етказиш ҳақи — якунда).
   */
  exportsObj.placeBusinessOrder = functions
    .runWith({ secrets: ['DIRECTIONS_API_KEY'] })
    .https.onCall(async (data, context) => {
      const t0 = Date.now();
      const uid = requirePhoneUid(context);
      const d = data || {};
      const idempotencyKey = str(d.idempotencyKey, 80);
      if (!IDEM_RE.test(idempotencyKey)) throw fail('invalid-argument', 'IDEMPOTENCY_KEY_INVALID');
      const deliveryPaymentMethod = d.deliveryPaymentMethod == null ? 'cash' : d.deliveryPaymentMethod;
      if (!DELIVERY_PAYMENT.includes(deliveryPaymentMethod)) throw fail('invalid-argument', 'DELIVERY_PAYMENT_INVALID');
      const goodsPaymentMethod = d.goodsPaymentMethod == null ? 'cash_buyout' : d.goodsPaymentMethod;
      if (!GOODS_PAYMENT.includes(goodsPaymentMethod)) throw fail('invalid-argument', 'GOODS_PAYMENT_INVALID');

      // Идемпотент калит бошқа амалда ишлатилган бўлса — ўша натижа қайтмайди (`type` текширилади).
      const idemRef = db.collection(IDEMPOTENCY).doc(`biz_place_${idempotencyKey}`);
      const existing = await idemRef.get();
      if (existing.exists) {
        const ed = existing.data() || {};
        if (ed.uid && ed.uid !== uid) throw fail('failed-precondition', 'IDEMPOTENCY_KEY_CONFLICT');
        return { ...(ed.result || { ok: true }), duplicate: true };
      }

      const p = await prepareOrder(uid, d);
      const userSnap = await db.collection('users').doc(uid).get();
      const ud = userSnap.exists ? (userSnap.data() || {}) : {};
      const at = now();
      const deadline = new Date(at.getTime() + p.cfg.acceptTimeoutMin * 60 * 1000);
      const orderRef = db.collection(ORDERS).doc();
      const deliveryFee = p.quote.deliveryFee;
      const payload = {
        type: ORDER_TYPE, module: MODULE_ID,
        businessId: p.businessId,
        businessName: str(p.b.name, 80),
        businessAddress: str(p.b.address, 200),
        businessLat: p.fromLat, businessLng: p.fromLng,
        sellerUid: p.sellerUid,
        regionId: str(p.b.regionId, 64) || null,
        districtId: p.districtId || null,
        ...statusPatch(BS.placed),
        paymentStatus: 'unpaid',
        userName: str(d.userName || ud.name || ud.fullName, 80),
        userPhone: uid, phone: uid,
        address: str(d.address, 300),
        lat: p.toLat, lng: p.toLng,
        note: str(d.note, 200),
        items: p.items,
        itemsTotal: p.itemsTotal,
        deliveryFee,
        total: p.itemsTotal + deliveryFee,
        fulfillmentMode: 'delivery', deliveryMode: 'ava_courier',
        deliveryFeeSource: 'ava_tariff',
        deliveryTariffVersion: p.quote.deliveryTariffVersion,
        deliveryTariffSnapshot: p.quote.deliveryTariffSnapshot,
        distanceMeters: p.quote.distanceMeters,
        distanceSource: p.quote.distanceSource,
        goodsPaymentMethod, deliveryPaymentMethod,
        avaFee: p.avaFee,
        acceptDeadlineAt: tsOf(deadline),
        courierId: null, deliveryRouteId: null,
        createdAt: ts(),
      };
      const result = {
        ok: true, orderId: orderRef.id, itemsTotal: p.itemsTotal, deliveryFee,
        total: payload.total, deliveryTariffVersion: p.quote.deliveryTariffVersion,
        acceptDeadlineAtMs: deadline.getTime(),
      };
      const txRes = await db.runTransaction(async (t) => {
        const again = await t.get(idemRef);
        if (again.exists) return { dup: (again.data() || {}).result || { ok: true } };
        t.set(orderRef, payload);
        t.set(orderRef.collection(PRIVATE).doc('secrets'), { pickupCode: pickupCode(), pickupAttempts: 0, createdAt: ts() });
        addEvent(t, orderRef, {
          from: null, to: BS.placed, actor: 'customer', actorId: uid,
          meta: { itemsTotal: p.itemsTotal, deliveryFee, deliveryTariffVersion: p.quote.deliveryTariffVersion, deliveryPaymentMethod, goodsPaymentMethod },
        });
        t.set(idemRef, { type: 'placeBusinessOrder', uid, result, createdAt: ts() });
        return { created: true };
      });
      if (txRes.dup) return { ...txRes.dup, duplicate: true };
      log('place', {
        orderId: orderRef.id, businessId: p.businessId, userId: tail4(uid), result: 'ok',
        itemsTotal: p.itemsTotal, deliveryFee, durationMs: Date.now() - t0,
      });
      await notifySeller(p.sellerUid, 'business_order_new', { amount: groupThousands(p.itemsTotal), min: p.cfg.acceptTimeoutMin }, orderRef.id, p.businessId);
      return result;
    });

  /** Мижоз бекор қилади — ФАҚАТ `placed` (сотувчи қабул қилмаган). */
  exportsObj.customerCancelBusinessOrder = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const orderId = orderIdOf(data);
    const reason = str(data && data.reason, 200);
    const orderRef = db.collection(ORDERS).doc(orderId);
    const out = await withContention(orderRef, 'customer_cancel', () => db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      if (canon(od.userPhone) !== uid) throw fail('permission-denied', 'NOT_ORDER_OWNER');
      if (od.businessStatus === BS.cancelled) return { ok: true, idempotent: true };
      if (od.businessStatus !== BS.placed) throw fail('failed-precondition', 'CANCEL_NOT_ALLOWED', { from: od.businessStatus });
      assertTransition(od, BS.cancelled, orderId);
      t.update(orderRef, statusPatch(BS.cancelled, { cancelledAt: ts(), cancelledBy: uid, cancelReason: reason || 'customer', acceptDeadlineAt: null }));
      addEvent(t, orderRef, { from: BS.placed, to: BS.cancelled, actor: 'customer', actorId: uid, reason });
      return { ok: true, sellerUid: od.sellerUid, businessId: od.businessId };
    }), (od) => (od.businessStatus === BS.cancelled && canon(od.userPhone) === uid ? { ok: true, idempotent: true } : null));
    if (!out.idempotent) {
      log('customer_cancel', { orderId, userId: tail4(uid), result: 'ok' });
      await notifySeller(out.sellerUid, 'business_order_cancelled', {}, orderId, out.businessId);
    }
    return { ok: true, idempotent: !!out.idempotent };
  });

  // ═══════════════════════════════════════════════════════════════════════
  // СОТУВЧИ (businesses.ownerId)
  // ═══════════════════════════════════════════════════════════════════════

  exportsObj.businessAcceptOrder = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    const orderId = orderIdOf(data);
    const orderRef = db.collection(ORDERS).doc(orderId);
    const out = await withContention(orderRef, 'accept', () => db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      requireSeller(od, uid);
      if (od.businessStatus === BS.accepted) return { ok: true, idempotent: true };
      assertTransition(od, BS.accepted, orderId);
      // Объект админ томонидан блокланган/ўчирилган бўлса — янги иш олинмайди (рад этиш мумкин).
      const bSnap = await t.get(db.collection(BUSINESSES).doc(String(od.businessId || '_')));
      if (!bSnap.exists || String((bSnap.data() || {}).status || 'active') !== 'active') {
        throw fail('failed-precondition', 'BUSINESS_NOT_ACTIVE');
      }
      t.update(orderRef, statusPatch(BS.accepted, { acceptedAt: ts(), acceptedBy: uid, acceptDeadlineAt: null }));
      addEvent(t, orderRef, { from: BS.placed, to: BS.accepted, actor: 'seller', actorId: uid });
      return { ok: true, od };
    }), (od) => {
      if (od.businessStatus === BS.accepted && canon(od.sellerUid) === uid) return { ok: true, idempotent: true };
      return null;
    });
    let couriersNotified = 0;
    if (!out.idempotent) {
      log('accept', { orderId, businessId: out.od.businessId, userId: tail4(uid), result: 'ok', durationMs: Date.now() - t0 });
      await notifyBuyer(out.od.userPhone, 'business_order_accepted', {}, orderId);
      couriersNotified = (await notifyNearbyCouriers(orderId, out.od, 'accepted')).notified;
    }
    return { ok: true, idempotent: !!out.idempotent, couriersNotified };
  });

  /** Рад: placed / accepted / ready (курьер олиб кетмаган). Курьер бириктирилган бўлса маршрутдан олинади. */
  exportsObj.businessRejectOrder = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const orderId = orderIdOf(data);
    const reason = str(data && data.reason, 200);
    const orderRef = db.collection(ORDERS).doc(orderId);
    const out = await withContention(orderRef, 'reject', () => db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      requireSeller(od, uid);
      if (od.businessStatus === BS.rejected) return { ok: true, idempotent: true };
      const from = assertTransition(od, BS.rejected, orderId);
      const routeRef = od.deliveryRouteId ? db.collection(ROUTES).doc(String(od.deliveryRouteId)) : null;
      const routeSnap = routeRef ? await t.get(routeRef) : null;
      t.delete(db.collection(COURIER_LIVE).doc(orderId));
      t.update(orderRef, statusPatch(BS.rejected, { rejectedAt: ts(), rejectedBy: uid, rejectReason: reason || 'seller', acceptDeadlineAt: null }));
      detachFromRouteInTx(t, routeRef, routeSnap, orderId, 'business_rejected');
      addEvent(t, orderRef, { from, to: BS.rejected, actor: 'seller', actorId: uid, reason });
      return { ok: true, customerUid: od.userPhone, courierId: od.courierId };
    }), (od) => (od.businessStatus === BS.rejected && canon(od.sellerUid) === uid ? { ok: true, idempotent: true } : null));
    if (!out.idempotent) {
      log('reject', { orderId, userId: tail4(uid), result: 'ok' });
      await notifyBuyer(out.customerUid, 'business_order_rejected', {}, orderId);
      if (out.courierId) await notifyCourier(out.courierId, 'business_order_cancelled_courier', {}, orderId);
    }
    return { ok: true, idempotent: !!out.idempotent };
  });

  exportsObj.businessMarkReady = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const orderId = orderIdOf(data);
    const orderRef = db.collection(ORDERS).doc(orderId);
    const out = await withContention(orderRef, 'ready', () => db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      requireSeller(od, uid);
      if (od.businessStatus === BS.ready) return { ok: true, idempotent: true };
      const from = assertTransition(od, BS.ready, orderId);
      t.update(orderRef, statusPatch(BS.ready, { readyAt: ts(), readyBy: uid }));
      addEvent(t, orderRef, { from, to: BS.ready, actor: 'seller', actorId: uid });
      return { ok: true, od };
    }), (od) => (od.businessStatus === BS.ready && canon(od.sellerUid) === uid ? { ok: true, idempotent: true } : null));
    let couriersNotified = 0;
    if (!out.idempotent) {
      log('ready', { orderId, userId: tail4(uid), result: 'ok' });
      if (out.od.courierId) await notifyCourier(out.od.courierId, 'business_order_ready_courier', {}, orderId);
      else couriersNotified = (await notifyNearbyCouriers(orderId, out.od, 'ready')).notified;
    }
    return { ok: true, idempotent: !!out.idempotent, couriersNotified };
  });

  // ═══════════════════════════════════════════════════════════════════════
  // КУРЬЕР (мавжуд курьер тизими)
  // ═══════════════════════════════════════════════════════════════════════

  /** Яқиндаги олинмаган буюртмалар — ПРОЕКЦИЯ (40-қоида): мижоз телефони, исми ва аниқ манзили ЙЎҚ. */
  exportsObj.listNearbyBusinessOrders = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const courierId = await courierAuthOf().resolve(uid, MODES.new);
    const lat = Number(data && data.lat);
    const lng = Number(data && data.lng);
    const hasLoc = validLatLng(lat, lng);
    const radiusKm = intOr(data && data.radiusKm, NEARBY_RADIUS_KM_DEFAULT, 1, 50);
    const prefs = (await db.collection(COURIER_PREFS).doc(courierId).get()).data() || {};
    const buyoutLimit = prefs.buyoutEnabled === true ? intOr(prefs.buyoutLimit, 0, 0, 100000000) : 0;
    const snap = await db.collection(ORDERS)
      .where('type', '==', ORDER_TYPE)
      .where('courierId', '==', null)
      .where('businessStatus', 'in', [...states.CLAIMABLE])
      .limit(NEARBY_LIMIT * 3)
      .get();
    const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
    const orders = [];
    for (const doc of snap.docs) {
      const od = doc.data() || {};
      if (courierAuthOf().isOwnOrder(od, courierId) || canon(od.sellerUid) === courierId) continue;
      const buyout = Number(od.itemsTotal) || 0;
      const pLat = num(od.businessLat);
      const pLng = num(od.businessLng);
      let courierToPickupM = null;
      if (hasLoc && pLat != null && pLng != null) {
        courierToPickupM = Math.round(tariff.haversineMeters(lat, lng, pLat, pLng));
        if (courierToPickupM > radiusKm * 1000) continue;
      }
      orders.push({
        id: doc.id,
        businessId: od.businessId || '',
        businessName: od.businessName || '',
        businessAddress: od.businessAddress || '',
        businessLat: pLat, businessLng: pLng,
        businessStatus: od.businessStatus,
        deliveryFee: Number(od.deliveryFee) || 0,
        deliveryPaymentMethod: od.deliveryPaymentMethod || 'cash',
        goodsPaymentMethod: od.goodsPaymentMethod || 'cash_buyout',
        buyoutAmount: buyout,
        buyoutAllowed: buyout <= buyoutLimit,
        itemsCount: Array.isArray(od.items) ? od.items.reduce((s, it) => s + (Number(it.qty) || 0), 0) : 0,
        distanceMeters: num(od.distanceMeters),
        courierToPickupM,
        readyAtMs: msOf(od.readyAt),
        createdAtMs: msOf(od.createdAt),
      });
      if (orders.length >= NEARBY_LIMIT) break;
    }
    orders.sort((a, b) => (a.courierToPickupM ?? 1e12) - (b.courierToPickupM ?? 1e12));
    return { orders, buyoutLimit };
  });

  /** Олиш — биринчи ғолиб (22-қоида, транзакция); курьернинг фаол маршрутига қўшилади. */
  exportsObj.courierClaimBusinessOrder = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    const courierId = await courierAuthOf().resolve(uid, MODES.new);
    const orderId = orderIdOf(data);
    const orderRef = db.collection(ORDERS).doc(orderId);
    const sameCourier = (od) => {
      const assigned = canon(od.courierId || '');
      if (assigned && assigned === courierId) return { ok: true, idempotent: true, routeId: od.deliveryRouteId };
      if (assigned) throw fail('failed-precondition', 'COURIER_ASSIGNMENT_CONFLICT');
      return null;
    };
    const out = await withContention(orderRef, 'claim', () => db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      const same = sameCourier(od);
      if (same) return same;
      if (!states.CLAIMABLE.includes(od.businessStatus)) throw fail('failed-precondition', 'ORDER_NOT_CLAIMABLE', { from: od.businessStatus });
      if (courierAuthOf().isOwnOrder(od, courierId)) throw fail('permission-denied', 'COURIER_OWN_ORDER');
      if (canon(od.sellerUid) === courierId) throw fail('permission-denied', 'COURIER_IS_SELLER');
      const [prefsSnap, routeSnap] = await Promise.all([
        t.get(db.collection(COURIER_PREFS).doc(courierId)),
        t.get(db.collection(ROUTES).where('courierId', '==', courierId).where('status', 'in', ['active', 'ready']).limit(1)),
      ]);
      const p = prefsSnap.exists ? (prefsSnap.data() || {}) : {};
      const limit = p.buyoutEnabled === true ? intOr(p.buyoutLimit, 0, 0, 100000000) : 0;
      const buyout = Number(od.itemsTotal) || 0;
      if (buyout > limit) throw fail('failed-precondition', 'BUYOUT_LIMIT_EXCEEDED', { required: buyout, limit });
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
          routeSource: 'business_claim', createdAt: ts(), startedAt: ts(),
        });
        routeId = routeRef.id;
      }
      t.update(orderRef, { courierId, deliveryRouteId: routeId, courierClaimedAt: ts(), updatedAt: ts() });
      addEvent(t, orderRef, { from: od.businessStatus, to: od.businessStatus, actor: 'courier', actorId: courierId, reason: 'claimed', meta: { routeId } });
      return { ok: true, routeId, od };
    }), sameCourier);
    if (!out.idempotent) {
      log('claim', { orderId, businessId: out.od.businessId, userId: tail4(courierId), result: 'ok', routeId: out.routeId, durationMs: Date.now() - t0 });
      await notifySeller(out.od.sellerUid, 'business_order_courier_assigned_seller', {}, orderId, out.od.businessId);
      await notifyBuyer(out.od.userPhone, 'business_order_courier_assigned', {}, orderId);
    }
    return { ok: true, routeId: out.routeId, idempotent: !!out.idempotent };
  });

  /**
   * Олиб кетдим — фақат `ready` ва тўғри `pickupCode` (сотувчи айтади; 5 уриниш). Товар пули шу пайт
   * курьер вэкупи билан сотувчига тўланган деб белгиланади (AVA ledger'сиз). Custody: seller → courier.
   */
  exportsObj.courierPickupBusinessOrder = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const courierId = await courierAuthOf().resolve(uid, MODES.finish);
    const orderId = orderIdOf(data);
    const code = str(data && data.pickupCode, 8);
    const orderRef = db.collection(ORDERS).doc(orderId);
    await courierAuthOf().assertOrderOnActiveRoute(courierId, orderId);
    const out = await db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      courierAuthOf().assertOrderActionable(od, courierId, 'courierPickupBusinessOrder', orderId);
      if (od.businessStatus === BS.picked) return { ok: true, idempotent: true };
      if (od.businessStatus !== BS.ready) throw fail('failed-precondition', 'ORDER_NOT_READY', { from: od.businessStatus });
      const secretRef = orderRef.collection(PRIVATE).doc('secrets');
      const sd = (await t.get(secretRef)).data() || {};
      const attempts = Number(sd.pickupAttempts) || 0;
      if (attempts >= PICKUP_CODE_ATTEMPTS) throw fail('failed-precondition', 'PICKUP_CODE_LOCKED');
      if (!code || String(sd.pickupCode || '') !== code) {
        t.update(secretRef, { pickupAttempts: inc(1), lastAttemptAt: ts() });
        return { mismatch: true, left: PICKUP_CODE_ATTEMPTS - attempts - 1 };
      }
      assertTransition(od, BS.picked, orderId);
      const buyout = Number(od.itemsTotal) || 0;
      t.update(orderRef, statusPatch(BS.picked, {
        pickedAt: ts(), inDeliveryAt: ts(), courierId,
        paymentStatus: 'goods_paid_by_courier', goodsPaidAt: ts(), goodsPaidBy: 'courier_buyout', buyoutAmount: buyout,
      }));
      t.set(db.collection(CUSTODY).doc(`biz_${orderId}_pickup`), custodyDoc({
        orderId, od, kind: 'pickup',
        from: { kind: 'seller', id: canon(od.sellerUid) }, to: { kind: 'courier', id: courierId },
        location: validLatLng(Number(od.businessLat), Number(od.businessLng)) ? { lat: Number(od.businessLat), lng: Number(od.businessLng) } : null,
        proof: { codeVerified: true }, actorId: courierId,
      }));
      addEvent(t, orderRef, { from: BS.ready, to: BS.picked, actor: 'courier', actorId: courierId, meta: { buyoutPaid: buyout } });
      return { ok: true, od };
    });
    if (out.mismatch) {
      log('pickup', { orderId, userId: tail4(courierId), result: 'denied', errorCode: 'PICKUP_CODE_MISMATCH' });
      throw fail('failed-precondition', 'PICKUP_CODE_MISMATCH', { attemptsLeft: out.left });
    }
    if (!out.idempotent) {
      log('pickup', { orderId, userId: tail4(courierId), result: 'ok' });
      await notifyBuyer(out.od.userPhone, 'business_order_picked', {}, orderId);
    }
    return { ok: true, idempotent: !!out.idempotent };
  });

  exportsObj.courierArriveBusinessOrder = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const courierId = await courierAuthOf().resolve(uid, MODES.finish);
    const orderId = orderIdOf(data);
    const orderRef = db.collection(ORDERS).doc(orderId);
    await courierAuthOf().assertOrderOnActiveRoute(courierId, orderId);
    const out = await db.runTransaction(async (t) => {
      const od = await getOrderInTx(t, orderRef);
      courierAuthOf().assertOrderActionable(od, courierId, 'courierArriveBusinessOrder', orderId);
      if (od.businessStatus === BS.arrived) return { ok: true, idempotent: true };
      assertTransition(od, BS.arrived, orderId);
      t.update(orderRef, statusPatch(BS.arrived, { arrivedAt: ts(), courierId }));
      addEvent(t, orderRef, { from: BS.picked, to: BS.arrived, actor: 'courier', actorId: courierId });
      return { ok: true, customerUid: od.userPhone };
    });
    if (!out.idempotent && notifyCourierArrivedToCustomer) {
      try { await notifyCourierArrivedToCustomer(out.customerUid, { orderId, module: MODULE_ID }); } catch (e) {
        console.error(JSON.stringify({ module: MODULE_ID, action: 'arrive_notify', orderId, result: 'failed', errorCode: 'NOTIFY_FAILED' }));
      }
    }
    return { ok: true, idempotent: !!out.idempotent };
  });

  /**
   * ЯКУН ЯДРОСИ (ягона, 7-қоида): курьер чақируви ва мижоз тасдиғи (`customerConfirmHandover`,
   * модул `business`, қадам `received`) ШУНИ ишлатади.
   *   `gate` (курьер) ва мижоз тасдиғи шу мижоз учун ЁҚИЛГАН бўлса — фақат кутиш белгиси ёзилади.
   *   Ҳамён: `bizDelivery_{orderId}` (журнал `bonus:` калити) — қайта уриниш икки марта ечмайди (21);
   *   қолдиқ етмаса нақдга тушади (`deliveryFeeFallback: insufficient_wallet`, ресторандаги каби).
   *   Идемпотентлик: `wallet_idempotency/biz_complete_{orderId}`.
   */
  async function completeInTx(t, { orderRef, idemRef, orderId, courierId, gate, confirmStep }) {
    const [idemSnap, od] = await Promise.all([t.get(idemRef), getOrderInTx(t, orderRef)]);
    courierAuthOf().assertOrderActionable(od, courierId, 'courierCompleteBusinessOrder', orderId);
    if (idemSnap.exists) return { done: true, result: { ...((idemSnap.data() || {}).result || { ok: true }), idempotent: true } };
    const from = assertTransition(od, BS.delivered, orderId);
    const customerUid = canon(od.userPhone);
    if (gate && customerConfirm && await customerConfirm.isGated(CC_MODULE, customerUid)) {
      const rq = customerConfirm.requestInTx(t, orderRef, od, {
        step: 'received', courierId, extra: { module: CC_MODULE }, patch: dfClear(od),
      });
      if (rq.created) {
        addEvent(t, orderRef, { from, to: from, actor: 'courier', actorId: courierId, reason: 'customer_confirm_requested', meta: { step: 'received' } });
      }
      return { done: true, result: customerConfirm.awaitingResponse('received'), requested: { od, created: rq.created } };
    }
    const fee = Number(od.deliveryFee) || 0;
    let walletPrep = null;
    if (od.deliveryPaymentMethod === 'wallet' && fee > 0) {
      walletPrep = await settlementLedger.prepareBonusInTx(t, db, customerUid, {
        fundingAccount: settlementLedger.passengerCreditAccount(courierId),
        idempotencyKey: `bizDelivery_${orderId}`,
      });
    }
    // ── ЁЗИШ ──
    let deliveryPaymentMethod = od.deliveryPaymentMethod === 'wallet' ? 'wallet' : 'cash';
    let walletPaid = 0;
    let deliveryFeeFallback = null;
    if (walletPrep) {
      if (walletPrep.jExists) {
        walletPaid = fee;
      } else if (walletPrep.pcPrev >= fee) {
        settlementLedger.commitBonusInTx(t, walletPrep, {
          delta: -fee, kind: 'business_delivery_fee', refType: 'order', refId: orderId,
          meta: { module: MODULE_ID, courierTail: tail4(courierId) }, postedBy: customerUid, postedRole: 'client',
        });
        const cRef = db.collection('users').doc(customerUid);
        const kRef = db.collection('users').doc(courierId);
        // Кўзгу — ресторан `restDelivery_` билан бир хил: increment + wallet_ledger.
        t.set(cRef, { bonusBalance: inc(-fee), balanceUpdatedAt: ts() }, { merge: true });
        t.set(cRef.collection('wallet_ledger').doc(), { type: 'business_delivery_debit', amount: -fee, module: MODULE_ID, refType: 'order', refId: orderId, meta: {}, createdAt: ts(), createdBy: 'server' });
        t.set(kRef, { bonusBalance: inc(fee), balanceUpdatedAt: ts() }, { merge: true });
        t.set(kRef.collection('wallet_ledger').doc(), { type: 'business_delivery_credit', amount: fee, module: MODULE_ID, refType: 'order', refId: orderId, meta: {}, createdAt: ts(), createdBy: 'server' });
        walletPaid = fee;
      } else {
        deliveryPaymentMethod = 'cash';
        deliveryFeeFallback = 'insufficient_wallet';
      }
    } else if (od.deliveryPaymentMethod === 'wallet' && fee === 0) {
      deliveryPaymentMethod = 'wallet';
    }
    const buyout = Number(od.buyoutAmount != null ? od.buyoutAmount : od.itemsTotal) || 0;
    const cashCollected = buyout + (deliveryPaymentMethod === 'cash' ? fee : 0);
    t.delete(db.collection(COURIER_LIVE).doc(orderId));
    t.update(orderRef, statusPatch(BS.delivered, {
      deliveredAt: ts(), completedAt: ts(), courierId, deliveryPaymentMethod, deliveryFeeFallback,
      deliveryFeeWalletPaid: walletPaid, cashCollected, paymentStatus: 'paid',
      ...(customerConfirm ? customerConfirm.clearPatch(od) : {}),
      ...dfClear(od),
      ...(confirmStep && customerConfirm ? customerConfirm.confirmedPatch(confirmStep, courierId) : {}),
    }));
    const dLat = Number(od.lat);
    const dLng = Number(od.lng);
    t.set(db.collection(CUSTODY).doc(`biz_${orderId}_delivered`), custodyDoc({
      orderId, od, kind: 'delivered',
      from: { kind: 'courier', id: courierId }, to: { kind: 'customer', id: customerUid },
      location: validLatLng(dLat, dLng) ? { lat: dLat, lng: dLng } : null,
      proof: confirmStep ? { customerConfirmed: true } : { courierDeclared: true }, actorId: confirmStep ? customerUid : courierId,
    }));
    const result = { ok: true, orderId, outcome: 'delivered', deliveryFee: fee, walletPaid, cashCollected, deliveryPaymentMethod };
    t.set(idemRef, { type: 'courierCompleteBusinessOrder', result, createdAt: ts() });
    addEvent(t, orderRef, confirmStep
      ? { from, to: BS.delivered, actor: 'customer', actorId: customerUid, reason: 'customer_confirmed', meta: { walletPaid, cashCollected, courierId, step: confirmStep } }
      : { from, to: BS.delivered, actor: 'courier', actorId: courierId, meta: { walletPaid, cashCollected } });
    return { done: false, result, customerUid, sellerUid: od.sellerUid, businessId: od.businessId };
  }

  async function afterDelivered(orderId, out, t0) {
    log('complete', {
      orderId, businessId: out.businessId, result: 'delivered', walletPaid: out.result.walletPaid,
      ...(t0 ? { durationMs: Date.now() - t0 } : {}),
    });
    await notifyBuyer(out.customerUid, 'business_order_delivered', {}, orderId);
    await notifySeller(out.sellerUid, 'business_order_delivered_seller', {}, orderId, out.businessId);
  }

  /** «Етказилмади» — бу ерда ЭМАС: `courierReportDeliveryFailed({module:'business', id, reason})` (delivery_failed.js). */
  exportsObj.courierCompleteBusinessOrder = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    const courierId = await courierAuthOf().resolve(uid, MODES.finish);
    const orderId = orderIdOf(data);
    const orderRef = db.collection(ORDERS).doc(orderId);
    const idemRef = db.collection(IDEMPOTENCY).doc(`biz_complete_${orderId}`);
    await courierAuthOf().assertOrderOnActiveRoute(courierId, orderId);
    const out = await db.runTransaction((t) => completeInTx(t, { orderRef, idemRef, orderId, courierId, gate: true }));
    if (out.requested) {
      await customerConfirm.afterRequest(CC_MODULE, orderId, 'received', out.requested.od, { module: CC_MODULE }, out.requested.created);
    }
    if (out.done) return out.result;
    await afterDelivered(orderId, out, t0);
    return out.result;
  });

  // Мижоз тасдиғи ядроси: `customerConfirmHandover({module:'business', step:'received'})` — курьер
  // чақируви билан АЙНАН бир хил `completeInTx` (сақланган courierId билан). «Етказилмади» қадами —
  // delivery_failed.js (`registerStepHandler('business', 'delivery_failed')`).
  if (customerConfirm) {
    customerConfirm.registerHandler(CC_MODULE, {
      collection: ORDERS,
      phoneField: 'userPhone',
      customerPhoneOf: (od) => od.userPhone,
      statusOf: (od) => String(od.businessStatus || ''),
      describe: (od, marker) => {
        if (!isBusinessOrder(od) || !states.IN_DELIVERY.includes(od.businessStatus)) return null;
        if (marker && marker.step === 'received') return { key: 'confirm_restaurant_received', params: {} };
        return null;
      },
      confirm: async (t, { ref, id, od, marker, step }) => {
        // `invalid-argument` (STATE_CHANGED эмас): бошқа модул белгисини ўчириб юбормасин.
        if (!isBusinessOrder(od) || step !== 'received') throw fail('invalid-argument', 'NOT_BUSINESS_ORDER');
        const idemRef = db.collection(IDEMPOTENCY).doc(`biz_complete_${id}`);
        const out = await completeInTx(t, {
          orderRef: ref, idemRef, orderId: id, courierId: canon(marker.courierId), gate: false, confirmStep: 'received',
        });
        if (out.done) {
          t.update(ref, { ...customerConfirm.clearPatch(od), ...customerConfirm.confirmedPatch('received', marker.courierId) });
        }
        return { status: BS.delivered, ...(out.done ? {} : { after: () => afterDelivered(id, out) }) };
      },
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ЖАДВАЛ: сотувчи муддатида қабул қилмади → rejected (timeout), ҳар дақиқа
  // ═══════════════════════════════════════════════════════════════════════
  async function expireOne(orderRef, at) {
    return db.runTransaction(async (t) => {
      const s = await t.get(orderRef);
      if (!s.exists) return null;
      const od = s.data() || {};
      if (!isBusinessOrder(od) || od.businessStatus !== BS.placed) return null;
      const dl = msOf(od.acceptDeadlineAt) || 0;
      if (!dl || dl > at.getTime()) return null;
      t.update(orderRef, statusPatch(BS.rejected, { rejectedAt: ts(), rejectedBy: 'system', rejectReason: 'timeout', acceptDeadlineAt: null }));
      addEvent(t, orderRef, { from: BS.placed, to: BS.rejected, actor: 'system', reason: 'timeout' });
      return { orderId: orderRef.id, customerUid: od.userPhone, sellerUid: od.sellerUid, businessId: od.businessId };
    });
  }

  async function expireUnaccepted() {
    const at = now();
    const snap = await db.collection(ORDERS)
      .where('type', '==', ORDER_TYPE)
      .where('businessStatus', '==', BS.placed)
      .where('acceptDeadlineAt', '<=', tsOf(at))
      .limit(EXPIRE_BATCH)
      .get();
    let expired = 0;
    for (const doc of snap.docs) {
      try {
        const r = await expireOne(doc.ref, at);
        if (!r) continue;
        expired += 1;
        log('expire', { orderId: r.orderId, businessId: r.businessId, result: 'rejected_timeout' });
        await notifyBuyer(r.customerUid, 'business_order_expired', {}, r.orderId);
        await notifySeller(r.sellerUid, 'business_order_expired_seller', {}, r.orderId, r.businessId);
      } catch (e) {
        console.error(JSON.stringify({ module: MODULE_ID, action: 'expire', orderId: doc.id, result: 'failed', errorCode: 'EXPIRE_FAILED', message: String((e && e.message) || e).slice(0, 160) }));
      }
    }
    return { scanned: snap.size, expired };
  }

  exportsObj.expireUnacceptedBusinessOrders = functions.pubsub
    .schedule('every 1 minutes')
    .timeZone('Asia/Tashkent')
    .onRun(async () => expireUnaccepted());

  // ═══════════════════════════════════════════════════════════════════════
  // АДМИН: босқич (audit) — 41, 42-қоида. Тариф — ресторан callable (adminSetRestaurantDeliveryPrices).
  // ═══════════════════════════════════════════════════════════════════════
  const ADMIN_ROLES = ['admin', 'superadmin'];

  /**
   * data: { stage?, addTesterIds?, removeTesterIds?, pilotDistrictIds?, acceptTimeoutMin?, reason }
   * → { ok, version, stage, testerCount, pilotDistrictIds, acceptTimeoutMin }. Audit'да телефонлар яширин.
   */
  exportsObj.adminSetBusinessOrdersConfig = functions.https.onCall(async (data, context) => {
    const actor = await requireCallerRoles(context, ADMIN_ROLES, 'Admin role required');
    const d = data || {};
    const reason = str(d.reason, 300);
    if (reason.length < 3) throw fail('invalid-argument', 'REASON_REQUIRED');
    if (d.stage !== undefined && !STAGES.includes(d.stage)) throw fail('invalid-argument', 'STAGE_INVALID', { allowed: [...STAGES] });
    const phones = (raw, field) => {
      if (raw === undefined) return [];
      if (!Array.isArray(raw) || raw.length > 200) throw fail('invalid-argument', 'TESTER_INVALID', { field });
      return [...new Set(raw.map((x) => {
        const c = typeof x === 'string' || typeof x === 'number' ? canon(String(x)) : '';
        if (!TESTER_RE.test(c)) throw fail('invalid-argument', 'TESTER_INVALID', { field });
        return c;
      }))];
    };
    const add = phones(d.addTesterIds, 'addTesterIds');
    const remove = phones(d.removeTesterIds, 'removeTesterIds');
    let pilot = null;
    if (d.pilotDistrictIds !== undefined) {
      if (!Array.isArray(d.pilotDistrictIds) || d.pilotDistrictIds.length > 200
          || d.pilotDistrictIds.some((x) => typeof x !== 'string' || !GEO_ID_RE.test(x.trim()))) {
        throw fail('invalid-argument', 'PILOT_DISTRICTS_INVALID');
      }
      pilot = [...new Set(d.pilotDistrictIds.map((x) => x.trim()))].sort();
    }
    let timeout = null;
    if (d.acceptTimeoutMin !== undefined) {
      if (!Number.isInteger(d.acceptTimeoutMin) || d.acceptTimeoutMin < ACCEPT_TIMEOUT_MIN_MIN || d.acceptTimeoutMin > ACCEPT_TIMEOUT_MIN_MAX) {
        throw fail('invalid-argument', 'ACCEPT_TIMEOUT_INVALID', { min: ACCEPT_TIMEOUT_MIN_MIN, max: ACCEPT_TIMEOUT_MIN_MAX });
      }
      timeout = d.acceptTimeoutMin;
    }
    if (d.stage === undefined && !add.length && !remove.length && pilot === null && timeout === null) {
      throw fail('invalid-argument', 'NOTHING_TO_CHANGE');
    }
    const ref = db.collection(CONFIG_DOC[0]).doc(CONFIG_DOC[1]);
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const cur = parseConfig(snap.exists ? snap.data() : null, canon);
      const testerIds = [...new Set([...cur.testerIds, ...add])].filter((x) => !remove.includes(x)).sort();
      if (testerIds.length > MAX_TESTERS) throw fail('invalid-argument', 'TESTERS_LIMIT', { max: MAX_TESTERS });
      const next = {
        stage: d.stage !== undefined ? d.stage : cur.stage,
        testerIds,
        pilotDistrictIds: pilot !== null ? pilot : cur.pilotDistrictIds,
        acceptTimeoutMin: timeout !== null ? timeout : cur.acceptTimeoutMin,
        version: cur.version + 1,
        reason, updatedAt: ts(), updatedBy: actor,
      };
      t.set(ref, next);
      t.set(db.collection(ADMIN_AUDIT).doc(), {
        kind: 'business_orders_config', actor, target: CONFIG_DOC.join('/'),
        from: cur.stage, to: next.stage, reason,
        detail: {
          version: next.version,
          testersAdded: add.filter((x) => !cur.testerIds.includes(x)).map((x) => `***${tail4(x)}`).slice(0, 20),
          testersRemoved: remove.filter((x) => cur.testerIds.includes(x)).map((x) => `***${tail4(x)}`).slice(0, 20),
          testersAfter: testerIds.length,
          pilotDistrictIds: next.pilotDistrictIds,
          acceptTimeoutMin: next.acceptTimeoutMin,
        },
        at: ts(),
      });
      return next;
    });
    log('admin_config', { userId: tail4(actor), version: out.version, stage: out.stage, result: 'ok' });
    return {
      ok: true, version: out.version, stage: out.stage, testerCount: out.testerIds.length,
      pilotDistrictIds: out.pilotDistrictIds, acceptTimeoutMin: out.acceptTimeoutMin,
    };
  });

  return { expireUnaccepted, readConfig };
}

module.exports = {
  attachBusinessOrders,
  MODULE_ID, CC_MODULE, CONFIG_DOC, TARIFF_DOC, TARIFF_HISTORY, STAGES,
  ACCEPT_TIMEOUT_MIN_DEFAULT, MAX_ITEMS, MAX_QTY, ORDERABLE_PRICE_UNITS, GOODS_PAYMENT, DELIVERY_PAYMENT,
  PICKUP_CODE_ATTEMPTS,
  parseConfig, accessOf, resolveAvaFee, parseWanted, priceLines,
  // Ҳолатлар — business_order_states.js (қайта экспорт, қулайлик учун)
  ...states,
};
