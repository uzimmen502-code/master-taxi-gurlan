'use strict';
/**
 * «Бозорлар» STAGE 11 — КАТТА маиший техника учун етказиш нархи СЎРОВИ (эга 2026-11-16).
 *
 * Оқим: мижоз сўров юборади (манзил/lat-lng, қават, изоҳ) → яқин курьерларга push + админ рўйхати →
 * БИРИНЧИ жавоб берган (админ ёки курьер) бутун сўм нарх ёзади (транзакция, битта ғолиб) → мижоз
 * тасдиқлайди → буюртма МАВЖУД `placeOrder` йўли орқали (business_orders.js) шу нарх билан берилади.
 *
 * Ягона манбалар (7-қоида): босқич/рухсат, бозор orderable, олиб кетиш нуқтаси, нарх — business_orders.js
 * `prepareOrder`; «катта» тўплами — `LARGE_DELIVERY_CATEGORIES`. Ёзув фақат шу ерда (Admin SDK);
 * `delivery_quotes` ва `delivery_quote_locks` клиентга ёпиқ (rules: мижоз ўзиникини, админ ҳаммасини ЎҚИЙДИ).
 *
 * Муддат: 24 соат — ЛЕНИВ (status 'open'/'answered' + `expiresAt` ўтган = муддати тугаган; рўйхатларда
 * кўрсатилмайди, жавоб/тасдиқ рад этилади). Алоҳида scheduler ЙЎҚ.
 * Нарх чегаралари `PRICE_MIN_UZS..PRICE_MAX_UZS` — PROPOSED (эга тасдиғи керак).
 */
const tariff = require('./restaurant_delivery_tariff');
const i18n = require('./notif_i18n');
const bo = require('./business_orders');

const MODULE_ID = 'delivery_quotes';
const QUOTES = 'delivery_quotes';
const LOCKS = 'delivery_quote_locks';
const EVENTS = 'events';
const ADMIN_AUDIT = 'admin_audit';
const ITEMS = 'tv_shop_items';
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);
const QS = Object.freeze({ open: 'open', answered: 'answered', used: 'used' });
const EXPIRY_MS = 24 * 60 * 60 * 1000;
const PRICE_MIN_UZS = 1000; // PROPOSED
const PRICE_MAX_UZS = 10000000; // PROPOSED
const FLOOR_MAX = 60;
const NEARBY_RADIUS_KM_DEFAULT = 15;
const COURIER_PUSH_MAX = 30;
const LIST_LIMIT = 200;
const DOC_ID_RE = bo.DOC_ID_RE;

function str(v, max) {
  return typeof v === 'string' ? v.trim().slice(0, max) : '';
}
function validLatLng(lat, lng) {
  return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180
    && !(lat === 0 && lng === 0);
}
const msOf = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : null);
const tail4 = (v) => String(v || '').replace(/\D/g, '').slice(-4);
const groupThousands = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');

/** Сўров ҳозир «очиқ/жавобли ва муддати ўтмаган»ми. */
function isLive(q, nowMs) {
  if (!q || (q.status !== QS.open && q.status !== QS.answered)) return false;
  const exp = msOf(q.expiresAt);
  return exp != null && exp > nowMs;
}

function attachDeliveryQuotes(exportsObj, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, requireCallerRoles, notifyUserInApp, courierPush,
    now: nowFn,
  } = deps;
  const courierAuthOf = () => deps.courierAuth;
  const boApi = () => deps.businessOrders;
  const MODES = deps.COURIER_AUTH_MODES || { new: 'new', finish: 'finish' };
  const now = nowFn || (() => new Date());
  const HttpsError = functions.https.HttpsError;
  const FV = admin.firestore.FieldValue;
  const ts = () => FV.serverTimestamp();
  const canon = (v) => canonicalUid(String(v == null ? '' : v));
  const fail = (status, code, extra = {}) => new HttpsError(status, code, { code, ...extra });

  function log(action, fields) {
    console.log(JSON.stringify({ module: MODULE_ID, action, ...fields }));
  }

  function requirePhoneUid(context) {
    if (!context || !context.auth) throw fail('unauthenticated', 'AUTH_REQUIRED');
    const uid = canon(callerPhone(context));
    if (!uid || uid.length < 12) throw fail('unauthenticated', 'PHONE_TOKEN_REQUIRED');
    return uid;
  }

  function quoteIdOf(data) {
    const id = str(data && data.quoteId, 128);
    if (!id || !DOC_ID_RE.test(id)) throw fail('invalid-argument', 'QUOTE_ID_REQUIRED');
    return id;
  }

  /** Админми (rol) ёки ишлаётган курьерми ('new' режим) — бошқа ҳолда QUOTE_RESPONDER_NOT_ALLOWED. */
  async function responderRoleOf(context, uid) {
    try {
      await requireCallerRoles(context, [...ADMIN_ROLES], 'Admin role required');
      return 'admin';
    } catch (_) { /* курьерми — пастда */ }
    try {
      await courierAuthOf().resolve(uid, MODES.new);
      return 'courier';
    } catch (_) {
      throw fail('permission-denied', 'QUOTE_RESPONDER_NOT_ALLOWED');
    }
  }

  async function notifyBuyer(q, quoteId) {
    try {
      const u = canon(q.buyerUid);
      if (u.length < 12) return;
      const lang = await i18n.langOfPhone(db, u);
      const m = i18n.render('delivery_quote_answered', lang, { title: str(q.itemTitle, 60), price: groupThousands(q.priceUzs) });
      await notifyUserInApp({
        userId: u, title: m.title, body: m.body, category: 'order', source: MODULE_ID,
        extraNews: { quoteId }, dataType: 'delivery_quote', screen: 'delivery_quote',
        extraData: { quoteId },
      });
    } catch (e) {
      console.error(JSON.stringify({ module: MODULE_ID, action: 'notify_buyer', quoteId, result: 'failed', errorCode: 'NOTIFY_FAILED' }));
    }
  }

  /** Яқин онлайн (capability текширилган) курьерларга FCM; best-effort, транзакциядан ташқарида. */
  async function notifyNearbyCouriers(quoteId, q) {
    const empty = { candidates: 0, notified: 0 };
    try {
      if (!courierPush || !validLatLng(q.pickupLat, q.pickupLng)) return empty;
      const skip = new Set([canon(q.buyerUid), canon(q.sellerUid)]);
      const candidates = (await courierPush.onlineCouriers())
        .filter((c) => c.lat != null && c.lng != null && !skip.has(c.id))
        .map((c) => ({ ...c, distanceM: tariff.haversineMeters(q.pickupLat, q.pickupLng, c.lat, c.lng) }))
        .filter((c) => c.distanceM <= NEARBY_RADIUS_KM_DEFAULT * 1000)
        .sort((a, b) => a.distanceM - b.distanceM)
        .slice(0, COURIER_PUSH_MAX);
      let notified = 0;
      for (const c of candidates) {
        const token = await courierPush.resolveToken(c.id);
        if (!token) continue;
        try {
          const lang = await i18n.langOfPhone(db, c.id);
          const m = i18n.render('delivery_quote_request_courier', lang, {
            title: str(q.itemTitle, 60), name: str(q.sellerName, 60), km: (c.distanceM / 1000).toFixed(1),
          });
          await admin.messaging().send({
            token,
            notification: { title: m.title, body: m.body },
            data: { type: 'delivery_quote_request', screen: 'courier', quoteId },
            android: { priority: 'high' },
          });
          notified += 1;
        } catch (_) {
          console.error(JSON.stringify({ module: MODULE_ID, action: 'courier_push', quoteId, result: 'failed', errorCode: 'FCM_FAILED' }));
        }
      }
      log('courier_push', { quoteId, candidates: candidates.length, notified });
      return { candidates: candidates.length, notified };
    } catch (e) {
      console.error(JSON.stringify({ module: MODULE_ID, action: 'courier_push', quoteId, result: 'failed', errorCode: 'COURIER_PUSH_FAILED' }));
      return empty;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // МИЖОЗ: сўров
  // ═══════════════════════════════════════════════════════════════════════

  /**
   * data: { itemId, qty?, lat, lng, address?, floor?, note? } → { ok, quoteId, status, expiresAtMs, duplicate }.
   * Идемпотент: шу мижоз + шу маҳсулот бўйича тирик сўров бўлса — ўшаниси (`delivery_quote_locks`).
   */
  exportsObj.requestDeliveryQuote = functions.https.onCall(async (data, context) => {
      const t0 = Date.now();
      const uid = requirePhoneUid(context);
      const d = data || {};
      const itemId = str(d.itemId, 128);
      if (!itemId || !DOC_ID_RE.test(itemId)) throw fail('invalid-argument', 'ITEM_INVALID');
      const qty = d.qty == null ? 1 : d.qty;
      if (!Number.isInteger(qty) || qty < 1 || qty > bo.MAX_QTY) throw fail('invalid-argument', 'ITEM_INVALID');
      const lat = d.lat != null ? Number(d.lat) : Number.NaN;
      const lng = d.lng != null ? Number(d.lng) : Number.NaN;
      if (!validLatLng(lat, lng)) throw fail('invalid-argument', 'DELIVERY_ADDRESS_REQUIRED');
      const floor = d.floor == null || d.floor === '' ? null : d.floor;
      if (floor !== null && (!Number.isInteger(floor) || floor < 0 || floor > FLOOR_MAX)) {
        throw fail('invalid-argument', 'FLOOR_INVALID', { max: FLOOR_MAX });
      }
      const itemSnap = await db.collection(ITEMS).doc(itemId).get();
      if (!itemSnap.exists) throw fail('failed-precondition', 'ITEM_NOT_FOUND', { itemId });
      const item = itemSnap.data() || {};
      const businessId = str(item.businessId, 128) || null;
      // Босқич, рухсат, бозор orderable, катта товар, олиб кетиш нуқтаси — ЯГОНА йўл (нарх ҳисобланмайди).
      const p = await boApi().prepareOrder(uid, { businessId, items: [{ itemId, qty }], lat, lng }, { delivery: { mode: 'request' } });
      const line = p.items[0];
      const nowMs = now().getTime();
      const lockRef = db.collection(LOCKS).doc(`${uid}_${itemId}`);
      const quoteRef = db.collection(QUOTES).doc();
      const doc = {
        buyerUid: uid, itemId, qty,
        itemTitle: line.title, unitPrice: line.unitPrice, priceUnit: line.priceUnit, itemsTotal: p.itemsTotal,
        market: line.market || null, category: line.category || null,
        sellerKind: p.sellerKind, sellerUid: p.sellerUid, businessId: p.businessId || null,
        sellerName: str(p.b.name, 80), pickupAddress: str(p.b.address, 200),
        pickupLat: p.fromLat, pickupLng: p.fromLng,
        regionId: str(p.b.regionId, 64) || null, districtId: p.districtId || null,
        lat, lng, address: str(d.address, 300), floor, note: str(d.note, 300),
        distanceMeters: Math.round(tariff.haversineMeters(p.fromLat, p.fromLng, lat, lng)),
        status: QS.open, priceUzs: null, respondedBy: null, responderRole: null, respondedAt: null,
        orderId: null,
        createdAt: ts(), updatedAt: ts(),
        expiresAt: admin.firestore.Timestamp.fromMillis(nowMs + EXPIRY_MS),
      };
      const out = await db.runTransaction(async (t) => {
        const lock = await t.get(lockRef);
        const prevId = lock.exists ? str((lock.data() || {}).quoteId, 128) : '';
        if (prevId) {
          const prev = await t.get(db.collection(QUOTES).doc(prevId));
          const pq = prev.exists ? (prev.data() || {}) : null;
          if (pq && isLive(pq, nowMs)) return { dup: true, quoteId: prevId, status: pq.status, expiresAtMs: msOf(pq.expiresAt) };
        }
        t.set(quoteRef, doc);
        t.set(quoteRef.collection(EVENTS).doc(), { to: QS.open, actor: 'customer', actorId: uid, at: ts() });
        t.set(lockRef, { quoteId: quoteRef.id, buyerUid: uid, itemId, updatedAt: ts() });
        return { dup: false, quoteId: quoteRef.id, status: QS.open, expiresAtMs: nowMs + EXPIRY_MS };
      });
      if (!out.dup) {
        log('request', { quoteId: out.quoteId, itemId, userId: tail4(uid), result: 'ok', durationMs: Date.now() - t0 });
        await notifyNearbyCouriers(out.quoteId, doc);
      }
      return { ok: true, quoteId: out.quoteId, status: out.status, expiresAtMs: out.expiresAtMs, duplicate: out.dup };
    });

  // ═══════════════════════════════════════════════════════════════════════
  // АДМИН / КУРЬЕР: нарх ёзиш (биринчи ғолиб)
  // ═══════════════════════════════════════════════════════════════════════

  /** data: { quoteId, priceUzs } → { ok, quoteId, priceUzs, responderRole, idempotent }. */
  exportsObj.respondDeliveryQuote = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const uid = requirePhoneUid(context);
    const quoteId = quoteIdOf(data);
    const priceUzs = data && data.priceUzs;
    if (!Number.isInteger(priceUzs) || priceUzs < PRICE_MIN_UZS || priceUzs > PRICE_MAX_UZS) {
      throw fail('invalid-argument', 'PRICE_INVALID', { min: PRICE_MIN_UZS, max: PRICE_MAX_UZS });
    }
    const role = await responderRoleOf(context, uid);
    const ref = db.collection(QUOTES).doc(quoteId);
    const decide = (q) => {
      if (q.status === QS.answered || q.status === QS.used) {
        if (canon(q.respondedBy) === uid) return { ok: true, idempotent: true, priceUzs: q.priceUzs, responderRole: q.responderRole };
        throw fail('failed-precondition', 'QUOTE_ALREADY_ANSWERED');
      }
      if (!isLive(q, now().getTime())) throw fail('failed-precondition', 'QUOTE_EXPIRED');
      return null;
    };
    let out;
    try {
      out = await db.runTransaction(async (t) => {
        const s = await t.get(ref);
        if (!s.exists) throw fail('not-found', 'QUOTE_NOT_FOUND');
        const q = s.data() || {};
        if (role === 'courier' && (canon(q.buyerUid) === uid || canon(q.sellerUid) === uid)) {
          throw fail('permission-denied', 'QUOTE_SELF_RESPOND');
        }
        const same = decide(q);
        if (same) return same;
        t.update(ref, {
          status: QS.answered, priceUzs, respondedBy: uid, responderRole: role, respondedAt: ts(), updatedAt: ts(),
        });
        t.set(ref.collection(EVENTS).doc(), { from: QS.open, to: QS.answered, actor: role, actorId: uid, priceUzs, at: ts() });
        if (role === 'admin') {
          t.set(db.collection(ADMIN_AUDIT).doc(), {
            kind: 'delivery_quote_respond', actor: uid, target: `${QUOTES}/${quoteId}`,
            from: QS.open, to: QS.answered, reason: '', detail: { priceUzs, itemId: q.itemId || null }, at: ts(),
          });
        }
        return { ok: true, q: { ...q, priceUzs } };
      });
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      // Параллел жавоб (ABORTED) — бир марта қайта ўқиб аниқ код (22, 25-қоида).
      const s = await ref.get();
      const resolved = s.exists ? decide(s.data() || {}) : null;
      log('respond', { quoteId, result: 'contention', errorCode: resolved ? 'resolved' : 'ABORTED' });
      if (resolved) return { ...resolved, quoteId };
      throw fail('aborted', 'CONTENTION_RETRY');
    }
    if (!out.idempotent) {
      log('respond', { quoteId, userId: tail4(uid), role, priceUzs, result: 'ok', durationMs: Date.now() - t0 });
      await notifyBuyer(out.q, quoteId);
      return { ok: true, quoteId, priceUzs, responderRole: role, idempotent: false };
    }
    return { ok: true, quoteId, priceUzs: out.priceUzs, responderRole: out.responderRole, idempotent: true };
  });

  // ═══════════════════════════════════════════════════════════════════════
  // МИЖОЗ: тасдиқ → буюртма (мавжуд placeOrder, нарх = сўров нархи)
  // ═══════════════════════════════════════════════════════════════════════

  /**
   * data: { quoteId, deliveryPaymentMethod?, note?, userName? } → placeBusinessOrder натижаси.
   * Идемпотент: калит `dq_{quoteId}` (битта сўров — битта буюртма); сўров `used` буюртма билан атомар.
   */
  exportsObj.acceptDeliveryQuote = functions.https.onCall(async (data, context) => {
      const uid = requirePhoneUid(context);
      const quoteId = quoteIdOf(data);
      const d = data || {};
      const ref = db.collection(QUOTES).doc(quoteId);
      const s = await ref.get();
      if (!s.exists) throw fail('not-found', 'QUOTE_NOT_FOUND');
      const q = s.data() || {};
      if (canon(q.buyerUid) !== uid) throw fail('permission-denied', 'NOT_QUOTE_OWNER');
      const checkLive = (cur) => {
        if (cur.status === QS.used) throw fail('failed-precondition', 'QUOTE_ALREADY_USED');
        if (cur.status === QS.open) {
          if (!isLive(cur, now().getTime())) throw fail('failed-precondition', 'QUOTE_EXPIRED');
          throw fail('failed-precondition', 'QUOTE_NOT_ANSWERED');
        }
        if (cur.status !== QS.answered || !isLive(cur, now().getTime())) throw fail('failed-precondition', 'QUOTE_EXPIRED');
        if (!Number.isSafeInteger(cur.priceUzs) || cur.priceUzs <= 0) throw fail('failed-precondition', 'QUOTE_NOT_ANSWERED');
      };
      // `used` бўлса — placeOrder идемпотент калити аввалги натижани қайтаради (дубликат буюртма йўқ).
      if (q.status !== QS.used) checkLive(q);
      const res = await boApi().placeOrder(uid, {
        idempotencyKey: `dq_${quoteId}`,
        businessId: q.businessId || null,
        items: [{ itemId: q.itemId, qty: q.qty }],
        lat: q.lat, lng: q.lng, address: q.address,
        note: str(d.note, 200) || str(q.note, 200),
        userName: d.userName,
        deliveryPaymentMethod: d.deliveryPaymentMethod,
      }, {
        delivery: { mode: 'quote', fee: q.priceUzs, quoteId },
        txCheck: async (t) => {
          const cur = (await t.get(ref)).data() || {};
          if (canon(cur.buyerUid) !== uid) throw fail('permission-denied', 'NOT_QUOTE_OWNER');
          checkLive(cur);
          if (cur.priceUzs !== q.priceUzs) throw fail('aborted', 'CONTENTION_RETRY');
          return (tx, orderId) => {
            tx.update(ref, { status: QS.used, orderId, usedAt: ts(), updatedAt: ts() });
            tx.set(ref.collection(EVENTS).doc(), { from: QS.answered, to: QS.used, actor: 'customer', actorId: uid, orderId, at: ts() });
          };
        },
      });
      if (!res.duplicate) log('accept', { quoteId, orderId: res.orderId, userId: tail4(uid), deliveryFee: res.deliveryFee, result: 'ok' });
      return res;
    });

  // ═══════════════════════════════════════════════════════════════════════
  // АДМИН / КУРЬЕР: очиқ сўровлар (проекция)
  // ═══════════════════════════════════════════════════════════════════════

  /**
   * data: { lat?, lng?, radiusKm? } → { viewer, quotes }. Курьерга мижоз телефони/аниқ манзили ЙЎҚ
   * (40-қоида) — фақат масофа, қават, изоҳ; ўз сўрови/ўз маҳсулоти кўрсатилмайди; жойлашув берилса — радиус.
   */
  exportsObj.listOpenDeliveryQuotes = functions.https.onCall(async (data, context) => {
    const uid = requirePhoneUid(context);
    const viewer = await responderRoleOf(context, uid);
    const lat = Number(data && data.lat);
    const lng = Number(data && data.lng);
    const hasLoc = validLatLng(lat, lng);
    const r = data && Number.isInteger(data.radiusKm) ? data.radiusKm : NEARBY_RADIUS_KM_DEFAULT;
    const radiusKm = Math.min(50, Math.max(1, r));
    const snap = await db.collection(QUOTES).where('status', '==', QS.open).limit(LIST_LIMIT).get();
    const nowMs = now().getTime();
    const quotes = [];
    for (const doc of snap.docs) {
      const q = doc.data() || {};
      if (!isLive(q, nowMs)) continue;
      if (viewer === 'courier' && (canon(q.buyerUid) === uid || canon(q.sellerUid) === uid)) continue;
      let courierToPickupM = null;
      if (hasLoc && validLatLng(q.pickupLat, q.pickupLng)) {
        courierToPickupM = Math.round(tariff.haversineMeters(lat, lng, q.pickupLat, q.pickupLng));
        if (viewer === 'courier' && courierToPickupM > radiusKm * 1000) continue;
      }
      quotes.push({
        id: doc.id, status: q.status, itemId: q.itemId, itemTitle: q.itemTitle || '', qty: q.qty || 1,
        market: q.market || null, category: q.category || null,
        sellerName: q.sellerName || '', pickupAddress: q.pickupAddress || '',
        pickupLat: q.pickupLat, pickupLng: q.pickupLng,
        floor: q.floor == null ? null : q.floor, note: q.note || '',
        distanceMeters: typeof q.distanceMeters === 'number' ? q.distanceMeters : null,
        courierToPickupM, districtId: q.districtId || null,
        createdAtMs: msOf(q.createdAt), expiresAtMs: msOf(q.expiresAt),
        ...(viewer === 'admin' ? { address: q.address || '', buyerPhoneTail: tail4(q.buyerUid) } : {}),
      });
    }
    if (viewer === 'courier') quotes.sort((a, b) => (a.courierToPickupM ?? 1e12) - (b.courierToPickupM ?? 1e12));
    else quotes.sort((a, b) => (b.createdAtMs || 0) - (a.createdAtMs || 0));
    return { viewer, quotes };
  });
}

module.exports = {
  attachDeliveryQuotes,
  MODULE_ID, QUOTES, LOCKS, EXPIRY_MS, PRICE_MIN_UZS, PRICE_MAX_UZS, FLOOR_MAX, isLive,
};
