/**
 * УЛГУРЖИ / ХИТОЙ — «Буюртма ёзиш»: харидор ↔ эълон эгаси (сотувчи) чати.
 *
 * Эга қарори (2026-11-01): маҳсулот тафсилотида «Қўнғироқ қилиш» ёнида «Буюртма ёзиш» —
 * ШУ эълон эгаси билан чат очилади; миқдор ва шартлар чатда ёки телефонда келишилади.
 * Занжир: харидор очади → хабар сотувчига (push + «Хабарлар»даги рўйхат) → сотувчи жавоб
 * беради → харидорга push ва жавоб.
 *
 * Нега янги коллекция: кодда харидор↔сотувчи чати йўқ (`support_chats` — фақат мижоз↔админ,
 * ҳужжат ID = мижоз телефони; танишув чати — ташқи Telegram бот). `wholesale_orders` — пул/
 * етказиш занжири, унга чат аралаштирилмайди (13-банд).
 *
 * Аралаш бозор (эга 2026-11-01: «унга ҳам қўш»): эълон (`ads`, type cheap_product) ва дўкон
 * маҳсулоти (`tv_shop_items`) учун ҳам ШУ чат — `source` бўйича (SOURCES жадвали). Эски
 * Улгуржи/Хитой чатлари (`source` майдонисиз) — `wholesale`.
 *
 * Коллекциялар (ҳаммаси client-write ЁПИҚ, фақат шу CF'лар ёзади):
 *   deal_chats/{prefix}{productId}_{buyerUid} — чат (детерминистик ID → қайта очиш идемпотент;
 *     prefix: wholesale — йўқ (эски ID'лар сақланади), ad — `ad-`, shop_item — `si-`)
 *     /messages/{senderUid}-{clientId} — хабар (ID → қайта юбориш идемпотент, 21-банд)
 *   deal_chat_usage/{uid}              — дақиқалик чегара ҳисоби (ҳеч кимга ўқилмайди)
 *
 * `lastAt` фақат БИРИНЧИ хабарда пайдо бўлади: очилиб, ёзилмаган чат рўйхат сўровига
 * (`orderBy('lastAt')`) тушмайди — сотувчига бўш чат кўринмайди.
 *
 * Push'да хабар МАТНИ кўрсатилади (эга қарори 2026-11-01: «билдиришномада хабар матни
 * кўрсатилсин»; аввал 40-банд сабаб фақат маҳсулот номи эди) — `previewOf` бўйича 120 белги.
 * Сарлавҳа — маҳсулот номи. Логга матн ЁЗИЛМАЙДИ (24-банд).
 *
 * Диагностика кодлари (HttpsError message = код, клиент `byServerMessage` билан таржима қилади):
 * PHONE_REQUIRED, PRODUCT_INVALID, PRODUCT_UNAVAILABLE, OWN_PRODUCT, CHAT_INVALID, CHAT_NOT_FOUND,
 * TEXT_INVALID, CLIENT_ID_INVALID, RATE_LIMITED.
 */
'use strict';

const { render, langOfPhone } = require('./notif_i18n');

const CHATS = 'deal_chats';
const USAGE = 'deal_chat_usage';

/** Чат манбалари: коллекция, ID префикси, сотувчи/ном/расм/нарх қоидаси. */
const SOURCES = Object.freeze({
  wholesale: {
    collection: 'wholesale_products',
    prefix: '',
    isActive: (p) => p.status === 'active',
    seller: (p) => p.sellerId,
    photo: (p) => (Array.isArray(p.imageUrls) ? p.imageUrls[0] : ''),
    market: (p) => (p.market === 'china' ? 'china' : 'wholesale'),
    price: () => null,
  },
  // Аралаш бозор эълони: фақат `cheap_product` (бошқа эълон турлари — бошқа модуллар).
  ad: {
    collection: 'ads',
    prefix: 'ad-',
    isActive: (p) => p.status === 'active' && p.type === 'cheap_product',
    seller: (p) => p.ownerId,
    photo: (p) => (Array.isArray(p.imageUrls) ? p.imageUrls[0] : ''),
    market: () => 'aralash',
    price: (p) => p.price,
  },
  // Дўкон маҳсулоти: `status` йўқ эски ҳужжат = active (илова `TvShopItem.fromFirestore` билан бир хил).
  shop_item: {
    collection: 'tv_shop_items',
    prefix: 'si-',
    isActive: (p) => (p.status == null ? 'active' : p.status) === 'active',
    seller: (p) => p.ownerPhone,
    photo: (p) => (Array.isArray(p.photoUrls) && p.photoUrls[0]) || p.photoUrl || '',
    market: () => 'aralash',
    price: (p) => p.price,
  },
});

// PROPOSED (47-банд) — эга тасдиқлагунча; ўзгартириш = шу константалар.
const LIMITS = Object.freeze({
  textMax: 1000,
  previewMax: 120,
  titleMax: 120,
  perMinute: 20,
});

const PRODUCT_ID_RE = /^[A-Za-z0-9_-]{1,100}$/;
const CHAT_ID_RE = /^[A-Za-z0-9_-]{1,104}_\d{11,15}$/;
const CLIENT_ID_RE = /^[A-Za-z0-9_-]{8,64}$/;
// Телефон рақами (E.164 рақамлари); ўзбек рақами — 998 + 9 хона.
const UID_RE = /^\d{11,15}$/;

/** Чат ID — манба префикси + маҳсулот + харидор (бир харидор бир маҳсулот бўйича битта чат). */
function dealChatId(productId, buyerUid, source = 'wholesale') {
  const src = SOURCES[source] || SOURCES.wholesale;
  return `${src.prefix}${productId}_${buyerUid}`;
}

/** Нарх — фақат манфий бўлмаган бутун сон (8-банд); бошқаси — сақланмайди. */
function priceOf(v) {
  return Number.isSafeInteger(v) && v > 0 ? v : null;
}

/** Хабар матни: trim; бўш ёки чегарадан узун — `null` (жимгина қисқартирилмайди). */
function normalizeText(v) {
  if (typeof v !== 'string') return null;
  const t = v.trim();
  if (!t || t.length > LIMITS.textMax) return null;
  return t;
}

/** Рўйхатдаги қисқа кўриниш: бир қатор, `previewMax` белги. */
function previewOf(text) {
  return String(text || '').replace(/\s+/g, ' ').trim().slice(0, LIMITS.previewMax);
}

/** Дақиқалик чегара: `{allowed, next}` — соф функция (тест учун). */
function rateGate(usage, nowMs, perMinute = LIMITS.perMinute) {
  const key = Math.floor(nowMs / 60000);
  const u = usage || {};
  const count = u.minuteKey === key && Number.isInteger(u.minuteCount) ? u.minuteCount : 0;
  if (count >= perMinute) return { allowed: false, next: null };
  return { allowed: true, next: { minuteKey: key, minuteCount: count + 1 } };
}

function attachDealChats(exportsObj, deps) {
  const { functions, db, admin, callerPhone, canonicalUid, resolveFcmToken } = deps;
  const HttpsError = functions.https.HttpsError;
  const FieldValue = admin.firestore.FieldValue;
  const ts = () => FieldValue.serverTimestamp();
  const fail = (status, code) => new HttpsError(status, code, { code });
  const log = (o) => console.log(JSON.stringify({ module: 'deal_chat', ...o }));

  /** Фақат телефон токени (uid = рақамлар). Аноним сессия — рад. */
  function requireUser(context) {
    if (!context || !context.auth) throw new HttpsError('unauthenticated', 'Authentication required');
    const uid = canonicalUid(callerPhone(context));
    if (!UID_RE.test(uid)) throw fail('unauthenticated', 'PHONE_REQUIRED');
    return uid;
  }

  function chatRefOf(data) {
    const chatId = String((data && data.chatId) || '').trim();
    if (!CHAT_ID_RE.test(chatId)) throw fail('invalid-argument', 'CHAT_INVALID');
    return db.collection(CHATS).doc(chatId);
  }

  /** Аъзо эмас — «топилмади» билан бир хил жавоб (чат борлиги ошкор бўлмасин). */
  function assertMember(snap, uid) {
    const members = snap.exists ? (snap.data() || {}).members : null;
    if (!Array.isArray(members) || !members.includes(uid)) throw fail('not-found', 'CHAT_NOT_FOUND');
    return snap.data();
  }

  async function pushToOther({ to, chatId, productTitle, text }) {
    const token = await resolveFcmToken(to);
    if (!token) return 'no_token';
    const lang = await langOfPhone(db, to);
    const m = render('deal_chat_message', lang, { title: productTitle || 'AVA', text: previewOf(text) });
    await admin.messaging().send({
      token,
      notification: { title: m.title, body: m.body },
      // `tab: messages` — эски илова (deal_chat ни билмайди) «Хабарлар»ни очади.
      data: { type: 'deal_chat', screen: 'deal_chat', tab: 'messages', chatId },
      android: { priority: 'high', collapseKey: chatId, notification: { tag: `deal_${chatId}` } },
    });
    return 'sent';
  }

  /**
   * data: { productId, source? } → { ok, chatId, created }. source: wholesale (default) | ad | shop_item.
   * Мавжуд чат (аъзо бўлса) — маҳсулот ҳолатидан қатъи назар қайтарилади (келишув давом этади).
   */
  exportsObj.openDealChat = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = requireUser(context);
    const productId = String((data && data.productId) || '').trim();
    if (!PRODUCT_ID_RE.test(productId)) throw fail('invalid-argument', 'PRODUCT_INVALID');
    const source = data && data.source != null ? String(data.source) : 'wholesale';
    const src = Object.prototype.hasOwnProperty.call(SOURCES, source) ? SOURCES[source] : null;
    if (!src) throw fail('invalid-argument', 'PRODUCT_INVALID');
    const chatRef = db.collection(CHATS).doc(dealChatId(productId, uid, source));
    const productRef = db.collection(src.collection).doc(productId);

    const out = await db.runTransaction(async (t) => {
      const [chatSnap, productSnap] = await Promise.all([t.get(chatRef), t.get(productRef)]);
      if (chatSnap.exists) {
        assertMember(chatSnap, uid);
        return { created: false };
      }
      if (!productSnap.exists) throw fail('not-found', 'PRODUCT_UNAVAILABLE');
      const p = productSnap.data() || {};
      if (!src.isActive(p)) throw fail('failed-precondition', 'PRODUCT_UNAVAILABLE');
      const sellerUid = canonicalUid(String(src.seller(p) || ''));
      if (!UID_RE.test(sellerUid)) throw fail('failed-precondition', 'PRODUCT_UNAVAILABLE');
      if (sellerUid === uid) throw fail('failed-precondition', 'OWN_PRODUCT');
      const rawPhoto = src.photo(p);
      const photo = typeof rawPhoto === 'string' ? rawPhoto : '';
      const price = priceOf(src.price(p));
      t.create(chatRef, {
        members: [uid, sellerUid],
        buyerId: uid,
        sellerId: sellerUid,
        productId,
        source,
        market: src.market(p),
        ...(price != null ? { productPrice: price } : {}),
        productTitle: String(p.title || '').trim().slice(0, LIMITS.titleMax),
        productPhoto: photo.slice(0, 1000),
        lastMessage: '',
        lastFrom: '',
        unread: { [uid]: 0, [sellerUid]: 0 },
        createdAt: ts(),
        updatedAt: ts(),
      });
      return { created: true };
    });
    log({ action: 'openDealChat', userId: uid, chatId: chatRef.id, productId, source, result: out.created ? 'created' : 'existing', durationMs: Date.now() - started });
    return { ok: true, chatId: chatRef.id, created: out.created };
  });

  /** data: { chatId, text, clientId } → { ok, messageId, duplicate }. */
  exportsObj.sendDealMessage = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = requireUser(context);
    const chatRef = chatRefOf(data);
    const text = normalizeText(data && data.text);
    if (text == null) throw fail('invalid-argument', 'TEXT_INVALID');
    const clientId = String((data && data.clientId) || '').trim();
    if (!CLIENT_ID_RE.test(clientId)) throw fail('invalid-argument', 'CLIENT_ID_INVALID');
    const msgRef = chatRef.collection('messages').doc(`${uid}-${clientId}`);
    const usageRef = db.collection(USAGE).doc(uid);

    const out = await db.runTransaction(async (t) => {
      const [chatSnap, msgSnap, usageSnap] = await Promise.all([t.get(chatRef), t.get(msgRef), t.get(usageRef)]);
      const chat = assertMember(chatSnap, uid);
      if (msgSnap.exists) return { duplicate: true };
      const gate = rateGate(usageSnap.exists ? usageSnap.data() : null, Date.now());
      if (!gate.allowed) throw fail('resource-exhausted', 'RATE_LIMITED');
      const other = chat.members.find((m) => m !== uid) || '';
      t.set(usageRef, { ...gate.next, updatedAt: ts() });
      t.create(msgRef, { from: uid, text, at: ts(), clientId });
      t.update(chatRef, {
        lastMessage: previewOf(text),
        lastFrom: uid,
        lastAt: ts(),
        updatedAt: ts(),
        [`unread.${uid}`]: 0,
        ...(other ? { [`unread.${other}`]: FieldValue.increment(1) } : {}),
      });
      return { duplicate: false, other, productTitle: chat.productTitle || '' };
    });

    let push = 'skipped';
    if (!out.duplicate && out.other) {
      // Push муваффақиятсиз бўлса ҳам хабар сақланган — хато логга (23-банд).
      try {
        push = await pushToOther({ to: out.other, chatId: chatRef.id, productTitle: out.productTitle, text });
      } catch (e) {
        push = 'error';
        log({ action: 'deal_chat_push', chatId: chatRef.id, result: 'error', errorCode: 'PUSH_FAILED', message: String(e && e.message).slice(0, 200) });
      }
    }
    log({ action: 'sendDealMessage', userId: uid, chatId: chatRef.id, result: out.duplicate ? 'duplicate' : 'ok', push, durationMs: Date.now() - started });
    return { ok: true, messageId: msgRef.id, duplicate: out.duplicate };
  });

  /** data: { chatId } → { ok, changed }. Ўқилмаган аллақачон 0 бўлса ёзув йўқ. */
  exportsObj.markDealChatRead = functions.https.onCall(async (data, context) => {
    const uid = requireUser(context);
    const chatRef = chatRefOf(data);
    const out = await db.runTransaction(async (t) => {
      const chat = assertMember(await t.get(chatRef), uid);
      const n = chat.unread && Number.isInteger(chat.unread[uid]) ? chat.unread[uid] : 0;
      if (n === 0) return { changed: false };
      t.update(chatRef, { [`unread.${uid}`]: 0 });
      return { changed: true };
    });
    return { ok: true, ...out };
  });
}

module.exports = {
  attachDealChats, dealChatId, normalizeText, previewOf, rateGate, priceOf, LIMITS, SOURCES,
};
